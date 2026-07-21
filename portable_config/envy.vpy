# "Envy" mode: AnimeJaNai 2x + RIFE in ONE VapourSynth graph.
# A single RGB pass, no intermediate YUV conversions, no second mpv bridge.
#
# Known limitation (VFR): multi is chosen from the file's nominal fps.
# In mixed-cadence anime (body 24, OP/ED 30) the 30fps sections output above
# the display rate and cause controlled drops - expected, not a bug.
import os
import sys
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

# Upscale model: "balanced" | "performance" | "balanced_sharp" | "performance_sharp"
MODEL = "balanced"

for dll in ("vstrt.dll", "miscfilters.dll"):
    try:
        core.std.LoadPlugin(os.path.join(PLUGINS, dll))
    except vs.Error:
        pass

import vsmlrt
from vsmlrt import Backend, RIFEModel

MODELS = {
    "balanced": "2x_AnimeJaNai_HD_V3.1_Balanced_SPANF3_b8f64_unshuffle_fp16.onnx",
    "performance": "2x_AnimeJaNai_HD_V3.1_Performance_SPANF3_b5f48_unshuffle_fp16.onnx",
    "balanced_sharp": "2x_AnimeJaNai_HD_V3.1Sharp1_Balanced_SPANF3_b8f64_unshuffle_fp16.onnx",
    "performance_sharp": "2x_AnimeJaNai_HD_V3.1Sharp1_Performance_SPANF3_b5f48_unshuffle_fp16.onnx",
    "sd": "2x_AnimeJaNai_SD_V1beta34_Compact_1x3xHxW_dyn-HW_strong_fp16_op21_dynamo.onnx",
}

TRT = dict(
    fp16=True,
    device_id=0,
    num_streams=2,
    use_cuda_graph=True,
    static_shape=True,
    output_format=1,  # fp16 output: half the GPU traffic
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

LOCK_EPS = 0.01  # display-resample speed-adjustment tolerance (mpv default 1%)


def pick_multi(src_fps, target, cap):
    """Frame multiplier with a cadence lock onto the display (see rife.vpy)."""
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

do_upscale = clip.width <= 1920 and clip.height <= 1200
do_rife = 0 < src_fps < 32

if do_upscale or do_rife:
    orig_fmt = clip.format.id

    # the matrix cancels itself out (decode and encode with the same
    # constant); it only affects the RGB basis the network sees
    matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

    work = clip
    if do_rife:
        # scene-change detection on the source (cheap); props travel down the graph
        work = core.misc.SCDetect(work, threshold=0.08)

    # range and chromaloc are pinned symmetrically, independent of props:
    # full range passes through RGBH as out-of-range float, bit-exact
    work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    # ORDER: RIFE before the upscale. At source resolution v4.26 is fast
    # enough, while v4.6 (the only fast option at 4K) waffles the grain of
    # real rips into a regular grid - reproduced and closed 07-12.
    if do_rife:
        pixels = rgb.width * rgb.height
        if do_upscale:
            cap = 3  # the janai stage follows; its ceiling is ~122 fps at 4K output
        elif pixels > 2560 * 1440:
            cap = 3
        elif pixels > 1920 * 1080:
            cap = 4
        else:
            cap = 6
        multi, fractional = pick_multi(src_fps, target, cap)

        if multi is not None:
            big = pixels > 2560 * 1440
            # v4.6/scale=0.5 waffles grain (closed 07-12): 4K = v4.25_lite,
            # smaller resolutions = v4.26, both at full flow
            scale_val = 1.0
            model = RIFEModel.v4_25_lite if big else RIFEModel.v4_26

            mod = 128 if big else 32  # v4.25_lite tile requirement = 128
            pad_r = (-rgb.width) % mod
            pad_b = (-rgb.height) % mod
            if pad_r or pad_b:
                rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

            rgb = vsmlrt.RIFE(
                rgb,
                multi=multi,
                scale=scale_val,
                model=model,
                backend=Backend.TRT(**TRT),
                video_player=True,
            )

            if fractional:
                # the mpv bridge hands over a clip with fps 0/0: without an
                # explicit AssumeFPS, fractional-path frames inherit the full
                # source duration (slow motion)
                out_fps = Fraction(src_fps).limit_denominator(1001) * multi
                rgb = core.std.AssumeFPS(rgb, fpsnum=out_fps.numerator, fpsden=out_fps.denominator)

            if pad_r or pad_b:
                rgb = core.std.Crop(rgb, right=pad_r, bottom=pad_b)

    if do_upscale:
        name = MODELS["sd"] if clip.height <= 600 else MODELS[MODEL]
        pad_r = (-rgb.width) % 16
        pad_b = (-rgb.height) % 16
        if pad_r or pad_b:
            rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

        # the HDR gate lives in scripts/smart-modes.lua: the bridge doesn't
        # pass transfer in frame props, and mpv knows gamma before the filter
        rgb = vsmlrt.inference(
            rgb,
            network_path=os.path.join(PLUGINS, "models", "animejanai", name),
            backend=Backend.TRT(**TRT),
        )

        if pad_r or pad_b:
            rgb = core.std.Crop(rgb, right=pad_r * 2, bottom=pad_b * 2)

    # the output is network-generated: quantize to 8/10 bit with dithering
    clip = core.resize.Bicubic(rgb, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="error_diffusion")

clip.set_output()
