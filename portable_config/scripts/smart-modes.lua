-- Умные хоткеи режимов: эксклюзивность + HDR-гейт для SDR-обученных сетей.
-- Мост vapoursynth не отдаёт скриптам transfer кадра (проверено дампом пропсов),
-- поэтому HDR-гейт живёт здесь, где mpv знает gamma до фильтра.
-- Кнопки эксклюзивны: включение режима снимает другие, складывать нельзя.

local VPYS = { "rife.vpy", "janai.vpy", "envy.vpy", "janai8k.vpy" }

local function is_hdr()
    local g = mp.get_property("video-params/gamma", "")
    return g == "pq" or g == "hlg"
end

local function active_vpy()
    local vf = mp.get_property_native("vf", {})
    for _, f in ipairs(vf) do
        if f.name == "vapoursynth" and f.params and f.params.file then
            local file = f.params.file:match("([^/\\]+%.vpy)$")
            if file then return file end
        end
    end
    return nil
end

local function switch_to(target, label)
    local current = active_vpy()
    if current == target then
        mp.command("vf remove vapoursynth=~~/" .. target)
        mp.osd_message(label .. ": выкл")
        return
    end
    if current then
        mp.command("vf remove vapoursynth=~~/" .. current)
    end
    mp.command("vf append vapoursynth=~~/" .. target)
    mp.osd_message(label .. ": вкл")
end

-- ⛔ ГЕЙТ БЕСПОЛЕЗНОГО УПЛАВНЕНИЯ (замер 08-06 на Хоббите 4K HDR).
-- Если частота панели почти равна частоте видео (панель 24.000 против
-- фильма 23.976), множитель RIFE выходит ~1.001: сеть гоняется на КАЖДОМ
-- 4K-кадре ради одной тысячной лишних кадров. Замерено: 41 дропнутый кадр
-- за 22 секунды при загрузке GPU-рендера всего 3% - то есть захлёбывается
-- не видеокарта, а мост vapoursynth. Плавности при этом ноль.
-- Порог тот же, что в rife.vpy: MIN_GAIN = 1.15.
local function pointless_interp()
    local dfps = mp.get_property_number("display-fps") or 0
    local cfps = mp.get_property_number("container-fps") or 0
    if dfps <= 0 or cfps <= 0 then return false end
    -- какой максимум выхода имеет смысл: цель либо панель, либо её половина
    local target = dfps
    local px = (mp.get_property_number("video-params/w") or 0)
             * (mp.get_property_number("video-params/h") or 0)
    if px > 2560 * 1440 and dfps >= 56 and dfps <= 62 then target = dfps / 2 end
    return (target / cfps) < 1.15
end

mp.add_key_binding("r", "smart-rife", function()
    if pointless_interp() then
        mp.osd_message(("Уплавнение бессмысленно: панель %.3f Гц ~ видео %.3f fps.
Сеть гоняла бы кадры впустую и роняла их. Смени частоту панели."):format(
            mp.get_property_number("display-fps") or 0,
            mp.get_property_number("container-fps") or 0), 5)
        return
    end
    switch_to("rife.vpy", "RIFE-уплавнялка")
end)

mp.add_key_binding("u", "smart-upscale", function()
    if is_hdr() then
        mp.osd_message("HDR-контент: аниме-сеть обучена на SDR, апскейл пропущен")
        return
    end
    switch_to("janai.vpy", "Апскейл AnimeJaNai")
end)

mp.add_key_binding("e", "smart-envy", function()
    if is_hdr() then
        if pointless_interp() then
            mp.osd_message("HDR + уплавнение бессмысленно на этой частоте: включать нечего", 4)
            return
        end
        mp.osd_message("HDR-контент: апскейл пропущен, включаю только RIFE")
        switch_to("rife.vpy", "RIFE-уплавнялка")
        return
    end
    switch_to("envy.vpy", "Режим Envy (апскейл + RIFE)")
end)

mp.add_key_binding("8", "smart-8k", function()
    if is_hdr() then
        mp.osd_message("HDR-контент: аниме-сеть обучена на SDR, 8K-апскейл пропущен")
        return
    end
    switch_to("janai8k.vpy", "8K-апскейл (без уплавнялки)")

    -- 4K-исходник + 60 Гц панель = 24 кадра на 60 Гц = 3:2-джадер.
    -- Инференс 8K и уплавнялка вместе в бюджет не влезают (замер 17 Гц).
    local w = mp.get_property_number("video-params/w", 0)
    local dfps = mp.get_property_number("display-fps", 0)
    if w > 2560 and dfps > 50 and dfps < 70 then
        mp.osd_message("8K-апскейл: для ровной каденции переключи панель в 8K 24 Гц", 5)
    end
end)
