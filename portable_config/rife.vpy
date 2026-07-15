# RIFE-интерполяция на TensorRT (RTX 5090)
# Вход из mpv: video_in, container_fps, display_fps
#
# Известное ограничение (VFR): multi выбирается по номинальному fps файла.
# В mixed-cadence аниме (тело 24, OP/ED 30) секции 30fps дадут выход выше
# дисплея и управляемые дропы - это ожидаемо, не баг. Для таких файлов
# честнее клавиша u (апскейл без интерполяции).
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
        pass  # уже загружен

import vsmlrt
from vsmlrt import Backend, RIFEModel

TRT = dict(
    fp16=True,
    device_id=0,
    num_streams=2,
    use_cuda_graph=True,
    static_shape=True,
    output_format=1,  # fp16-выход: вдвое меньше трафика с GPU, без CPU-переливов
    engine_folder=os.path.join(PLUGINS, "trt-engines"),
)

LOCK_EPS = 0.01  # допуск подгонки скорости display-resample (дефолт mpv 1%)


def pick_multi(src_fps, target, cap):
    """Множитель кадров с локом каденции на дисплей.

    Целые множители перебираются сверху вниз, берётся первый, чей выход
    лочится на target/k (24-семейство на 144 Гц: 6, 3, 2; НЕ 4 и не 5).
    Если целого лока нет (25, 29.97 fps), берётся дробный множитель с
    выходом ровно target/k. Возвращает (multi, дробный?) или (None, False).
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

# уплавняем только киношные частоты; 50/60 fps и неизвестный fps не трогаем
if 0 < src_fps < 32:
    pixels = clip.width * clip.height
    if pixels > 2560 * 1440:
        cap = 3
    elif pixels > 1920 * 1080:
        cap = 4
    else:
        cap = 6
    # Бюджет 8K@60: RIFE на 4K-кадрах + вывод 33 Мпикс не влезают в 5090 вместе -
    # замер на 4K HDR даёт 46-49 fps презентации вместо 60 (рывки, задержанные
    # кадры). На 60 Гц панелях с 4K+ контентом целимся в 30: лок 2:2, работы
    # вдвое меньше, 3:2-джадера всё равно нет.
    eff_target = target
    if pixels > 2560 * 1440 and 56 <= target <= 62:
        eff_target = target / 2

    multi, fractional = pick_multi(src_fps, eff_target, cap)

    if multi is not None:
        orig_fmt = clip.format.id
        big = pixels > 2560 * 1440
        # v4.6 (и весь легаси со scale=0.5) вафлит зерно рипов регулярной
        # сеткой - закрыто 07-12. 4K тянет только v4.25_lite (полный flow),
        # на малых разрешениях качественнее v4.26.
        scale_val = 1.0
        model = RIFEModel.v4_25_lite if big else RIFEModel.v4_26

        # матрица самосокращается (декод и энкод одной константой), влияет
        # только на RGB-базис, который видит сеть
        matrix = "2020ncl" if clip.width >= 3200 else ("709" if clip.height >= 600 else "170m")

        # детект смены сцены, чтобы RIFE не морфил монтажные склейки
        work = core.misc.SCDetect(clip, threshold=0.08)

        # range и chromaloc фиксируются симметрично и независимо от пропов:
        # full-range проходит сквозь RGBH как out-of-range float без потерь
        work = core.std.RemoveFrameProps(work, props=["_ColorRange", "_Range", "_ChromaLocation"])

        rgb = core.resize.Bicubic(work, format=vs.RGBH, matrix_in_s=matrix,
                                  range_in_s="limited", chromaloc_in_s="left")

        mod = 128 if big else 32  # требование тайла v4.25_lite = 128
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
            # мост mpv отдаёт клип с fps 0/0 и vsmlrt свой AssumeFPS пропускает:
            # без явного кадры дробного пути уносят полную длительность (слоумо)
            out_fps = Fraction(src_fps).limit_denominator(1001) * multi
            smooth = core.std.AssumeFPS(smooth, fpsnum=out_fps.numerator, fpsden=out_fps.denominator)

        if pad_r or pad_b:
            smooth = core.std.Crop(smooth, right=pad_r, bottom=pad_b)

        clip = core.resize.Bicubic(smooth, format=orig_fmt, matrix_s=matrix,
                                   range_s="limited", chromaloc_s="left")

clip.set_output()
