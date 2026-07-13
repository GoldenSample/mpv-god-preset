# 8K-профиль: AnimeJaNai 2x до 7680x4320 для 4K-исходников (RTX 5090).
# На 60 Гц панели (8K-телевизоры) кино 24 fps дополнительно интерполируется
# до display/2 = 30 fps (ровный лок 2:2, без 3:2-джадера). Полные 60 вместе
# с 8K-апскейлом в бюджет 5090 не влезают (janai 4K->8K = ~36 fps ёмкости).
import os
import sys
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

# Модель апскейла: "balanced" | "performance" (легче вдвое, если появятся дропы)
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

# гейт до 4K включительно: 2x от 4K = 8K
if clip.width <= 3840 and clip.height <= 2400:
    name = MODELS["sd"] if clip.height <= 600 else MODELS[MODEL]

    matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

    orig_fmt = clip.format.id

    work = clip

    # лёгкая интерполяция до target/2 только на ~60 Гц панелях и киношном fps
    do_rife = 56 <= target <= 62 and 0 < src_fps < 32
    if do_rife:
        work = core.misc.SCDetect(work, threshold=0.14)

    work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    if do_rife:
        src = Fraction(src_fps).limit_denominator(1001)
        multi = Fraction(round(target), 2) / src   # 24 -> 30 на 60 Гц, лок 2:2
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
            # мост отдаёт fps 0/0: длительности дробного пути ставим сами
            out_fps = src * multi
            rgb = core.std.AssumeFPS(rgb, fpsnum=out_fps.numerator, fpsden=out_fps.denominator)
            if pad_r or pad_b:
                rgb = core.std.Crop(rgb, right=pad_r, bottom=pad_b)

    pad_r = (-rgb.width) % 16
    pad_b = (-rgb.height) % 16
    if pad_r or pad_b:
        rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

    # HDR-гейт живёт в scripts/smart-modes.lua
    up = vsmlrt.inference(
        rgb,
        network_path=os.path.join(PLUGINS, "models", "animejanai", name),
        backend=Backend.TRT(**TRT),
    )

    if pad_r or pad_b:
        up = core.std.Crop(up, right=pad_r * 2, bottom=pad_b * 2)

    # ordered вместо error_diffusion: диффузия ошибки на 33 Мпикс душит CPU
    clip = core.resize.Bicubic(up, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="ordered")

clip.set_output()
