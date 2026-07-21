# 8K profile: AnimeJaNai 2x up to 7680x4320 for 4K sources (RTX 5090).
# On a 60 Hz panel (8K TVs) 24 fps film is additionally interpolated to
# display/2 = 30 fps (a clean 2:2 lock, no 3:2 judder). Full 60 together
# with the 8K upscale doesn't fit the 5090 budget (janai 4K->8K = ~36 fps
# of capacity).
import os
import sys
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

# Upscale model: "balanced" | "performance" (half the weight, if drops appear)
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
    "sd": "2x_AnimeJaNai_SD_V1beta34_Compact_1x3xHxW_dyn-HW_strong_fp16_op21_dynamo.onnx",
}

TRT = dict(
    fp16=True,
    device_id=0,
    num_streams=2,
    use_cuda_graph=True,
    static_shape=True,
    output_format=1,
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

clip = video_in

src_fps = container_fps if container_fps else 0.0
target = display_fps if display_fps and display_fps > 0 else 60.0

# gate up to 4K inclusive: 2x from 4K = 8K
if clip.width <= 3840 and clip.height <= 2400:
    name = MODELS["sd"] if clip.height <= 600 else MODELS[MODEL]

    matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

    orig_fmt = clip.format.id

    work = clip

    # Interpolation here is only for light input (up to 1440p -> output up to
    # 2880p). None for 4K->8K: measured on a live 8K@60 panel it's 17 Hz with
    # it versus 57 without (8K inference plus 33 Mpix output don't fit the
    # 5090 together). 24 fps film on 60 Hz will show 3:2 judder - for clean
    # cadence switch the panel to 8K@24 (1:1 lock, measured 0 drops), or
    # watch 4K through the r/e keys.
    do_rife = (56 <= target <= 62 and 0 < src_fps < 32
               and clip.width * clip.height <= 2560 * 1440)
    if do_rife:
        work = core.misc.SCDetect(work, threshold=0.08)

    work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    if do_rife:
        src = Fraction(src_fps).limit_denominator(1001)
        multi = Fraction(round(target), 2) / src   # 24 -> 30 at 60 Hz, 2:2 lock
        if multi > 1:
            big = rgb.width * rgb.height > 2560 * 1440
            model = RIFEModel.v4_25_lite if big else RIFEModel.v4_26
            mod = 128 if big else 32
            pad_r = (-rgb.width) % mod
            pad_b = (-rgb.height) % mod
            if pad_r or pad_b:
                rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)
            rgb = vsmlrt.RIFE(rgb, multi=multi, scale=1.0, model=model,
                              backend=Backend.TRT(**TRT), video_player=True)
            # the bridge hands over fps 0/0: set fractional-path durations ourselves
            out_fps = src * multi
            rgb = core.std.AssumeFPS(rgb, fpsnum=out_fps.numerator, fpsden=out_fps.denominator)
            if pad_r or pad_b:
                rgb = core.std.Crop(rgb, right=pad_r, bottom=pad_b)

    pad_r = (-rgb.width) % 16
    pad_b = (-rgb.height) % 16
    if pad_r or pad_b:
        rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

    # the HDR gate lives in scripts/smart-modes.lua
    up = vsmlrt.inference(
        rgb,
        network_path=os.path.join(PLUGINS, "models", "animejanai", name),
        backend=Backend.TRT(**TRT),
    )

    if pad_r or pad_b:
        up = core.std.Crop(up, right=pad_r * 2, bottom=pad_b * 2)

    # ordered instead of error_diffusion: error diffusion on 33 Mpix strangles the CPU
    clip = core.resize.Bicubic(up, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="ordered")

clip.set_output()
