# 8K-профиль: AnimeJaNai 2x на TensorRT для 4K-исходников (выход 7680x4320).
# Для входа ниже 4K тоже один проход 2x (1080p -> 4K, дальше скейлит mpv/панель).
# RIFE сюда не влезает по бюджету 5090: нейро-8K = только детализация, без уплавнялки.
import os
import sys

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

# Модель: "balanced" | "performance" | "balanced_sharp" | "performance_sharp"
MODEL = "balanced"

try:
    core.std.LoadPlugin(os.path.join(PLUGINS, "vstrt.dll"))
except vs.Error:
    pass  # уже загружен

import vsmlrt
from vsmlrt import Backend

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
    output_format=1,  # fp16-выход: на 8K-кадрах трафик с GPU критичен
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

clip = video_in

# гейт до 4K включительно: 2x от 4K = 8K
if clip.width <= 3840 and clip.height <= 2400:
    name = MODELS["sd"] if clip.height <= 600 else MODELS[MODEL]

    matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

    orig_fmt = clip.format.id

    work = core.std.RemoveFrameProps(clip, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    pad_r = (-clip.width) % 16
    pad_b = (-clip.height) % 16
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

    # ordered вместо error_diffusion: на 33 Мпикс диффузия ошибки душит CPU
    clip = core.resize.Bicubic(up, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="ordered")

clip.set_output()
