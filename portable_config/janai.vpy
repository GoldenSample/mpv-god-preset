# AnimeJaNai V3.1 SPANF3: нейро-апскейл аниме 2x на TensorRT (RTX 5090)
# Вход из mpv: video_in
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
    output_format=1,  # fp16-выход: вдвое меньше трафика с GPU
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

clip = video_in

# апскейлим только то, что ниже 4K; 4K-исходники не трогаем
if clip.width <= 1920 and clip.height <= 1200:
    name = MODELS["sd"] if clip.height <= 600 else MODELS[MODEL]

    # матрица самосокращается (декод и энкод одной константой), влияет
    # только на RGB-базис, который видит сеть
    matrix = "709" if clip.height >= 600 else "170m"

    orig_fmt = clip.format.id

    # range и chromaloc фиксируются симметрично и независимо от пропов:
    # full-range проходит сквозь RGBH как out-of-range float без потерь
    work = core.std.RemoveFrameProps(clip, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    # паддинг до кратности 16 (pixel-unshuffle внутри графа), обрезка после
    pad_r = (-clip.width) % 16
    pad_b = (-clip.height) % 16
    if pad_r or pad_b:
        rgb = core.std.AddBorders(rgb, right=pad_r, bottom=pad_b)

    # HDR-гейт живёт в scripts/smart-modes.lua: мост не отдаёт transfer
    # в пропсах кадра, а mpv знает gamma до фильтра
    up = vsmlrt.inference(
        rgb,
        network_path=os.path.join(PLUGINS, "models", "animejanai", name),
        backend=Backend.TRT(**TRT),
    )

    if pad_r or pad_b:
        up = core.std.Crop(up, right=pad_r * 2, bottom=pad_b * 2)

    # весь кадр сгенерён сетью: квантование в 8/10 бит с дизерингом
    clip = core.resize.Bicubic(up, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="error_diffusion")

clip.set_output()
