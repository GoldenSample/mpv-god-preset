# mpv «как божеенька» — нейро-пресет для RTX 5090

Домашний видеопроцессор уровня madVR Envy на своём железе: идеальная киношная
каденция без 3:2-джадера, RIFE-интерполяция кадров, нейро-апскейл аниме до 4K/8K,
HDR-passthrough. Всё в реальном времени, всё бесплатно, всё на одной видеокарте.

Собрано и обкатано 2026-07-12 на RTX 5090 (дисплей 4K@144, затем 8K@60 + 4K@165).
Каденция подстраивается под панель сама: на 144 Гц кино идёт 6:6, на 165 - дробным
множителем 82.5/55 с локом, на 8K@60 - ровно 60. Для справки: внутри madVR Envy
Extreme MK2 стоит RTX 4080, и интерполяции кадров у Envy нет вообще.

## Кнопки (все режимы)

| Кнопка | Режим | Для чего |
|---|---|---|
| `e` | **Envy: апскейл + уплавнялка** | Основная кнопка для аниме. 1080p24 -> 4K 72fps одним графом |
| `r` | **RIFE-уплавнялка** | Живое кино. Частота подбирается под дисплей сама (144/72/60, PAL/NTSC через дробный множитель) |
| `u` | **AnimeJaNai 2x апскейл** | Аниме до 1080p -> 4K, кадры родные (24 fps как в кино) |
| `8` | **8K-профиль** | Нейро-2x до 7680x4320 для 4K-исходников. На 60 Гц панелях кино дополнительно интерполируется до 30 fps (лок 2:2, без 3:2-джадера); полные 60 вместе с 8K-апскейлом в бюджет 5090 не влезают |
| `b` | Дебандинг | Полосы в градиентах (стримы, старые энкоды) |
| `TAB` | Статистика | fps, дропы, активные фильтры |
| `s` | Скриншот | В `Pictures\mpv-shots` |

Кнопки режимов **эксклюзивны**: включение одного само снимает другой.
Выключение — та же кнопка ещё раз. На HDR-контенте (PQ/HLG) апскейл-сети
не включаются (обучены на SDR): `u` и `8` откажут с пояснением на экране,
`e` автоматически деградирует в чистый RIFE.

## Замеры (RTX 5090, все с 0 дропов)

| Сценарий | Результат |
|---|---|
| Кино 24 fps без фильтров | каждый кадр ровно 6 раз на 144 Гц, pulldown физически невозможен |
| RIFE 1080p24 (v4.26 x6) | 143.86 fps |
| RIFE 4K24 (v4.25_lite x3) | 71.93 fps, запас throughput 20% |
| RIFE 25 fps PAL (дробный x5.76) | ровно 144.0 |
| RIFE 29.97 NTSC (дробный x4.8) | ровно 144.0 |
| Envy-граф 1080p24 -> 4K 72fps | 98 fps throughput при потребности 72 |
| AnimeJaNai 4K -> 8K | 36.3 fps (кино 24/30 тянет), VRAM 3.7 ГБ |
| Кнопка 8 на живом 8K@60 (RIFE до 30 + апскейл) | ровно 30.0 fps на панель 7680x4320 |
| RIFE 4K на живом 8K@60 (дробный x2.5) | ровно 60.0 fps |
| HDR PQ через RIFE | gamma/primaries/10 бит проходят нетронутыми |

## Архитектура

```
mpv (vo=gpu-next, d3d11) --vf vapoursynth--> VS R76 (embedded Python 3.14)
    -> vs-mlrt v15.16 (TensorRT 10.16, движки кэшируются на диск)
        -> RIFE v4.26 (<=1440p) / v4.25_lite (4K) - интерполяция
        -> AnimeJaNai V3.1 SPANF3 (Balanced) - апскейл 2x
```

- `portable_config/mpv.conf` - каденция (display-resample + oversample), HDR passthrough, скейлинг ewa_lanczossharp
- `portable_config/*.vpy` - графы фильтров (rife / janai / envy / janai8k)
- `portable_config/scripts/smart-modes.lua` - кнопки, эксклюзивность, HDR-гейт

## Грабли, оплаченные кровью (главные уроки)

1. **Два vapoursynth-фильтра цепочкой душат друг друга.** Апскейл и RIFE двумя
   `--vf` дают 24.8 fps; те же два шага одним VS-графом - 107 fps. Все
   «прыгающие fps» пакетных сборок AnimeJanai+RIFE лечатся сшивкой в один .vpy.
2. **RIFE v4.6 рисует «чешую» на зерне.** На временнОм зерне рипов (нетфликс,
   старые BD) v4.6 в любом режиме (fp16/fp32/scale) даёт регулярную вафельную
   сетку на интерполированных кадрах. Лечение: v4.26 до 1440p, v4.25_lite на 4K.
   Обе на полном flow (scale=1).
3. **Порядок в комбо-режиме: RIFE до апскейла.** На исходном разрешении работают
   чистые новые модели; интерполировать после апскейла = гнать RIFE на 4K, где
   выбор моделей по скорости беднее.
4. **Full-range без симметрии выцветает.** Конверсия YUV->RGB->YUV без явного
   range на обеих сторонах жмёт full-range в limited (чёрный сереет). Фикс:
   RemoveFrameProps + range_in_s/range_s="limited" симметрично - full проходит
   сквозь RGBH как out-of-range float без потерь.
5. **Дробный множитель обязан ставить AssumeFPS.** Мост mpv отдаёт клип с fps
   0/0, vsmlrt свой AssumeFPS пропускает, кадры уносят полную длительность
   исходника - слоумо. Целочисленный путь не затронут (Interleave делит сам).
6. **Мост mpv не отдаёт colorimetry в пропсах кадра.** Только
   _ColorRange/_ColorSpace/_ChromaLocation. _Transfer/_Matrix/_Primaries НЕТ,
   поэтому HDR-гейт живёт в lua (mpv знает gamma до фильтра), а матрица -
   константная эвристика (декод и энкод одной константой самосокращаются).
7. **floor на границе герцовки.** Панель, отдающая 143.856 вместо 144, роняет
   `int(target // fps)` с 6 на 5. Выбор множителя - только через проверку лока
   с допуском 1% (лимит подгонки скорости display-resample).

## Установка с нуля

Компоненты (версии рабочей сборки):

1. **mpv** x86_64-v3 от [shinchiro](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
   (сборка 2026-06-10, v0.41 git) - распаковать в `C:\Apps\mpv`
2. **Python 3.14 embeddable** с python.org - распаковать туда же,
   в `python314._pth` добавить строку `Lib\site-packages`
3. **VapourSynth R76 portable** ([releases](https://github.com/vapoursynth/vapoursynth/releases)) -
   распаковать туда же, поставить колесо: `python.exe -m pip install wheel\VapourSynth-*.whl`
   (pip сначала через get-pip.py). Скопировать из `Lib\site-packages\vapoursynth\`
   файлы `vsscript.dll` (как `VSScript.dll`) и `libvapoursynth.dll` в корень mpv
4. **vs-mlrt TensorRT** ([v15.16](https://github.com/AmusementClub/vs-mlrt/releases)) -
   распаковать в `vs-plugins\`
5. **Модели**: RIFE `rife_v4.26.7z`, `rife_v4.25_lite.7z` (оттуда же, релиз
   external-models) в `vs-plugins\models\rife\`; AnimeJaNai V3.1 SPANF3 из
   [overlay-пака 3.5.0](https://github.com/the-database/mpv-AnimeJaNai/releases)
   в `vs-plugins\models\animejanai\`; miscfilters
   ([R2](https://github.com/vapoursynth/vs-miscfilters-obsolete/releases)) в `vs-plugins\`
6. **Конфиги этого репозитория** - в `portable_config\`
7. **VSScript-конфиг**: файл `vapoursynth.toml` из этого репо в
   `%APPDATA%\vapoursynth\` (пути внутри поправить под свою установку).
   Без него mpv не найдёт Python: «Failed to initialize VSScript»

Первый запуск каждого режима на новом разрешении собирает TensorRT-движок
(1-2 минуты разово), кэш в `vs-plugins\trt-engines\`.

## Лицензии

Конфиги репозитория - делайте что хотите. Модели НЕ включены в репозиторий:
AnimeJaNai - [the-database](https://github.com/the-database/mpv-AnimeJaNai),
RIFE - [hzwer/Practical-RIFE](https://github.com/hzwer/Practical-RIFE) через
[vs-mlrt](https://github.com/AmusementClub/vs-mlrt). Sintel / Tears of Steel
(тестовый контент) - (c) Blender Foundation, CC BY.
