# Режим "Envy": AnimeJaNai 2x + RIFE в ОДНОМ графе VapourSynth.
# Один проход RGB, без промежуточных YUV-конверсий и без второго моста mpv.
#
# Известное ограничение (VFR): multi выбирается по номинальному fps файла.
# В mixed-cadence аниме (тело 24, OP/ED 30) секции 30fps дадут выход выше
# дисплея и управляемые дропы - это ожидаемо, не баг.
import os
import sys
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core

PLUGINS = r"C:\Apps\mpv\vs-plugins"
sys.path.insert(0, PLUGINS)

# Модель апскейла: "balanced" | "performance" | "balanced_sharp" | "performance_sharp"
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
    output_format=1,  # fp16-выход: вдвое меньше трафика с GPU
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

LOCK_EPS = 0.01  # допуск подгонки скорости display-resample (дефолт mpv 1%)


def pick_multi(src_fps, target, cap):
    """Множитель кадров с локом каденции на дисплей (см. rife.vpy)."""
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

    # матрица самосокращается (декод и энкод одной константой), влияет
    # только на RGB-базис, который видит сеть
    matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

    work = clip
    if do_rife:
        # детект смены сцены на исходнике (дёшево), пропсы едут дальше по графу
        work = core.misc.SCDetect(work, threshold=0.14)

    # range и chromaloc фиксируются симметрично и независимо от пропов:
    # full-range проходит сквозь RGBH как out-of-range float без потерь
    work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

    rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                              range_in_s="limited", chromaloc_in_s="left")

    # ПОРЯДОК: RIFE до апскейла. На исходном разрешении работает v4.26,
    # а v4.6 (единственная скоростная на 4K) вафлит зерно рипов регулярной
    # сеткой - воспроизведено и закрыто 07-12.
    if do_rife:
        pixels = rgb.width * rgb.height
        if do_upscale:
            cap = 3  # впереди janai-стадия, её потолок ~122 fps на 4K-выходе
        elif pixels > 2560 * 1440:
            cap = 3
        elif pixels > 1920 * 1080:
            cap = 4
        else:
            cap = 6
        multi, fractional = pick_multi(src_fps, target, cap)

        if multi is not None:
            big = pixels > 2560 * 1440
            # v4.6/scale=0.5 вафлит зерно (закрыто 07-12): 4K = v4.25_lite,
            # малые разрешения = v4.26, обе на полном flow
            scale_val = 1.0
            model = RIFEModel.v4_25_lite if big else RIFEModel.v4_26

            mod = 128 if big else 32  # требование тайла v4.25_lite = 128
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
                # мост mpv отдаёт клип с fps 0/0: без явного AssumeFPS кадры
                # дробного пути уносят полную длительность исходного (слоумо)
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

        # HDR-гейт живёт в scripts/smart-modes.lua: мост не отдаёт transfer
        # в пропсах кадра, а mpv знает gamma до фильтра
        rgb = vsmlrt.inference(
            rgb,
            network_path=os.path.join(PLUGINS, "models", "animejanai", name),
            backend=Backend.TRT(**TRT),
        )

        if pad_r or pad_b:
            rgb = core.std.Crop(rgb, right=pad_r * 2, bottom=pad_b * 2)

    # выход сгенерён сетями: квантование в 8/10 бит с дизерингом
    clip = core.resize.Bicubic(rgb, format=orig_fmt, matrix_s=matrix,
                               range_s="limited", chromaloc_s="left",
                               dither_type="error_diffusion")

clip.set_output()
