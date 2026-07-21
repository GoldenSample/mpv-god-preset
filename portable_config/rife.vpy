# RIFE interpolation on TensorRT (RTX 5090)
# Input from mpv: video_in, container_fps, display_fps
#
# Known limitation (VFR): multi is chosen from the file's nominal fps.
# In mixed-cadence anime (body 24, OP/ED 30) the 30fps sections output above
# the display rate and cause controlled drops - expected, not a bug. For such
# files the u key (upscale without interpolation) is the honest choice.
import os
import sys
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

for dll in ("vstrt.dll", "miscfilters.dll"):
    try:
        core.std.LoadPlugin(os.path.join(PLUGINS, dll))
    except vs.Error:
        pass  # already loaded

import vsmlrt
from vsmlrt import Backend, RIFEModel

TRT = dict(
    fp16=True,
    device_id=0,
    num_streams=2,
    use_cuda_graph=True,
    static_shape=True,
    output_format=1,  # fp16 output: half the GPU traffic, no CPU round-trips
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

LOCK_EPS = 0.01  # display-resample speed-adjustment tolerance (mpv default 1%)


def pick_multi(src_fps, target, cap):
    """Frame multiplier with a cadence lock onto the display.

    Integer multipliers are scanned top-down; take the first whose output
    locks onto target/k (the 24 family at 144 Hz: 6, 3, 2; NOT 4 or 5).
    If no integer lock exists (25, 29.97 fps), use a fractional multiplier
    with output exactly target/k. Returns (multi, fractional?) or (None, False).
    """
    for m in range(cap, 1, -1):
        out = src_fps * m
        if out > target * (1 + LOCK_EPS):
            continue
        k = max(1, round(target / out))
        if abs(out * k / target - 1) <= LOCK_EPS:
            return m, False
    src = Fraction(src_fps).limit_denominator(1001)
    for k in range(1, 8):
        multi = Fraction(round(target), k) / src
        if multi <= cap:
            return (multi, True) if multi > 1 else (None, False)
    return None, False


clip = video_in

src_fps = container_fps if container_fps else 0.0
target = display_fps if display_fps and display_fps > 0 else 144.0

# interpolate film rates only; leave 50/60 fps and unknown fps alone
if 0 < src_fps < 32:
    pixels = clip.width * clip.height
    if pixels > 2560 * 1440:
        cap = 3
    elif pixels > 1920 * 1080:
        cap = 4
    else:
        cap = 6
    # The 8K@60 budget: RIFE on 4K frames plus 33 Mpix output don't fit the
    # 5090 together - measured on 4K HDR: 46-49 fps of presentation instead
    # of 60 (stutter, delayed frames). On 60 Hz panels with 4K+ content we
    # target 30: a 2:2 lock, half the work, still no 3:2 judder.
    eff_target = target
    if pixels > 2560 * 1440 and 56 <= target <= 62:
        eff_target = target / 2

    multi, fractional = pick_multi(src_fps, eff_target, cap)

    if multi is not None:
        orig_fmt = clip.format.id
        big = pixels > 2560 * 1440
        # v4.6 (and all legacy models at scale=0.5) waffles the grain of real
        # rips into a regular grid - closed 07-12. 4K is only viable on
        # v4.25_lite (full flow); at smaller resolutions v4.26 looks better.
        scale_val = 1.0
        model = RIFEModel.v4_25_lite if big else RIFEModel.v4_26

        # the matrix cancels itself out (decode and encode with the same
        # constant); it only affects the RGB basis the network sees
        matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

        # scene-change detection so RIFE doesn't morph across cuts
        work = core.misc.SCDetect(clip, threshold=0.08)

        # range and chromaloc are pinned symmetrically, independent of props:
        # full range passes through RGBH as out-of-range float, bit-exact
        work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

        rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                                  range_in_s="limited", chromaloc_in_s="left")

        mod = 128 if big else 32  # v4.25_lite tile requirement = 128
        pad_r = (-rgb.width) % mod
        pad_b = (-rgb.height) % mod
        if pad_r or pad_b:
            rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

        smooth = vsmlrt.RIFE(
            rgb,
            multi=multi,
            scale=scale_val,
            model=model,
            backend=Backend.TRT(**TRT),
            video_player=True,
        )

        if fractional:
            # the mpv bridge hands over a clip with fps 0/0 and vsmlrt skips
            # its own AssumeFPS: without an explicit one, fractional-path
            # frames inherit the full source duration (slow motion)
            out_fps = Fraction(src_fps).limit_denominator(1001) * multi
            smooth = core.std.AssumeFPS(smooth, fpsnum=out_fps.numerator, fpsden=out_fps.denominator)

        if pad_r or pad_b:
            smooth = core.std.Crop(smooth, right=pad_r, bottom=pad_b)

        clip = core.resize.Bicubic(smooth, format=orig_fmt, matrix_s=matrix,
                                   range_s="limited", chromaloc_s="left")

clip.set_output()
