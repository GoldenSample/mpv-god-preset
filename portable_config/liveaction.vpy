# 2xLiveActionV1_SPAN: нейро-апскейл ЖИВОГО кино 2x на TensorRT (RTX 5090).
# Вход из mpv: video_in. Кнопка L (smart-modes.lua).
#
# Модель jcj83429 (Apache 2.0): чинит компрессию, дехало, деблюр, СОХРАНЯЕТ
# зерно (в отличие от аниме-сетей, которые денойзят). Обучена на JPEG/H264/
# VP9/H265, chroma subsampling, пересжатии, oversharpening-гало, экранном
# тексте. Ниша: стримы, сериалы, веб-рипы, покоцанное цифровое кино.
# НЕ включать: на зернистых 35мм-ремуксах (лёгкое зерно ок, тяжёлое мажет),
# на VHS, на аниме (для аниме есть janai.vpy).
import os
import sys

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

try:
    core.std.LoadPlugin(os.path.join(PLUGINS, "vstrt.dll"))
except vs.Error:
    pass  # уже загружен

import vsmlrt
from vsmlrt import Backend

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

# апскейлим только то, что ниже 4K; 4K-исходники не трогаем (эта модель
# для доводки битого 1080p, на нативном 4K смысла нет)
if clip.width <= 1920 and clip.height <= 1200:
    matrix = "709" if clip.height >= 600 else "170m"
    orig_fmt = clip.format.id

    work = core.std.RemoveFrameProps(clip, props=["_ColorRange", "_Range", "_ChromaLocation"])

    # ⚠ RGBS (float32), НЕ RGBH: автор модели прямо клиппит диапазон
    # 0..1 перед сетью — "The model can't handle out of range values".
    # На half-float клип уровней ненадёжен у краёв, поэтому single.
    rgb = core.resize.Bicubic(work, format=vs.RGBS, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")
    # ОБЯЗАТЕЛЬНО: срезать значения вне [0,1], иначе модель ломается
    rgb = core.std.Levels(rgb, min_in=0.0, max_in=1.0, min_out=0.0, max_out=1.0)

    # SPAN без unshuffle → кратность не требуется, паддинг не нужен
    up = vsmlrt.inference(
        rgb,
        network_path=os.path.join(PLUGINS, "models", "liveaction", "2xLiveActionV1.onnx"),
        backend=Backend.TRT(**TRT),
    )

    clip = core.resize.Bicubic(up, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="error_diffusion")

clip.set_output()
