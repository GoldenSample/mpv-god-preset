-- console.lua — визуальная консоль плеера.
-- Живые метрики, реальный бюджет кадра, самые дорогие проходы рендера,
-- состав цепочки и активные режимы. Вызов: F1 или i.
--
-- ЗАЧЕМ. Когда картинка «тормозит», глазами не понять, где узкое место:
-- декодер, апскейл, шейдер или просто рассинхрон частот. Консоль отвечает
-- цифрами: сколько миллисекунд из отведённых съедает кадр и КАКОЙ проход
-- съедает больше всех.
--
-- ⚠ Ключевая тонкость, ради которой она вообще написана: при
-- video-sync=display-resample с interpolation=yes кадр пересчитывается
-- НА ЧАСТОТЕ ПАНЕЛИ, а не на частоте видео. На 8K это значит, что апскейл
-- 4K->8K крутится, скажем, 60 раз в секунду вместо 24, и бюджет падает
-- с 41.7 мс до 16.7 мс. Строка «считается N раз/с» показывает это явно.
--
-- ⚠ Единицы vo-passes: документация называет микросекунды, но по факту
-- (сумма проходов против реального fps без дропов) это НАНОсекунды.
-- Проверено на 4K HDR: сумма 828000 единиц при 24 fps и нуле дропов, то
-- есть 0.83 мс, а не 828 мс. Делим на 1e6.

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local visible, timer = false, nil

local GREEN, YELLOW, RED, GREY, CYAN =
      "{\\c&H50D050&}", "{\\c&H30C0F0&}", "{\\c&H5050F0&}",
      "{\\c&H909090&}", "{\\c&HF0D060&}"
local R = "{\\c&HFFFFFF&}"

local function num(p, d) local v = mp.get_property_number(p); return v == nil and d or v end
local function str(p, d) local v = mp.get_property(p); return (v == nil or v == "") and d or v end

local function col(frac)
    return frac < 0.6 and GREEN or (frac < 0.85 and YELLOW or RED)
end

local function bar(frac, w)
    w = w or 16
    local f = math.max(0, math.min(w, math.floor(frac * w + 0.5)))
    return col(frac) .. string.rep("|", f) .. GREY .. string.rep(".", w - f) .. R
end

-- суммарное и самое дорогое время рендера
local function passes()
    local vp = mp.get_property_native("vo-passes")
    if not vp then return nil, {} end
    local total, list = 0, {}
    for _, group in pairs(vp) do
        for _, p in ipairs(group) do
            local ns = p.avg or 0
            total = total + ns
            list[#list+1] = { desc = p.desc or "?", ms = ns / 1e6 }
        end
    end
    table.sort(list, function(a, b) return a.ms > b.ms end)
    return total / 1e6, list
end

local function build()
    local a = assdraw.ass_new()
    a:new_event()
    a:append("{\\an7\\pos(24,24)\\fs11\\bord1\\shad1\\fnConsolas}")

    local dw, dh   = num("display-width", 0), num("display-height", 0)
    local dfps     = num("display-fps", 0)
    local sw, sh   = num("video-params/w", 0), num("video-params/h", 0)
    local cfps     = num("container-fps", 0)
    local gamma    = str("video-params/gamma", "")
    local hdr      = (gamma == "pq" or gamma == "hlg") and (CYAN .. "HDR " .. gamma:upper() .. R) or "SDR"
    local interp   = mp.get_property_bool("interpolation", false)
    local vsync    = str("video-sync", "?")

    a:append(CYAN .. "КОНСОЛЬ" .. R .. GREY .. "  F1 закрыть" .. R .. "\\N")
    a:append(string.format("панель    %dx%d @ %.3f Гц\\N", dw, dh, dfps))
    a:append(string.format("исходник  %dx%d @ %.3f  %s %s  %s\\N",
        sw, sh, cfps, str("video-format", "?"):upper(),
        str("video-params/pixelformat", "?"), hdr))
    a:append(string.format("декодер   %s\\N", str("hwdec-current", "нет")))

    -- ---------- бюджет: главное ----------
    local rt, top = passes()
    local render_hz = (interp and vsync:find("display") and dfps > 0) and dfps or cfps
    if render_hz <= 0 then render_hz = dfps > 0 and dfps or 24 end
    local budget = 1000 / render_hz

    a:append("\\N" .. CYAN .. "БЮДЖЕТ КАДРА" .. R .. "\\N")
    if rt then
        local frac = rt / budget
        a:append(string.format("рендер    %s%.2f мс%s из %.1f  %s %d%%\\N",
            col(frac), rt, R, budget, bar(frac), math.floor(frac * 100 + 0.5)))
    else
        a:append(GREY .. "рендер    нет данных (нужен vo=gpu-next)\\N" .. R)
    end
    if interp and render_hz > cfps + 1 then
        a:append(string.format("%sсчитается %.0f раз/с вместо %.0f (интерполяция)%s\\N",
            YELLOW, render_hz, cfps, R))
    else
        a:append(string.format("%sсчитается %.0f раз/с (по частоте видео)%s\\N", GREY, render_hz, R))
    end

    if rt and #top > 0 then
        a:append(GREY .. "самое дорогое:" .. R .. "\\N")
        for i = 1, math.min(3, #top) do
            if top[i].ms > 0.01 then
                a:append(string.format("  %s%5.2f мс%s  %s\\N",
                    col(top[i].ms / budget), top[i].ms, R, top[i].desc:sub(1, 40)))
            end
        end
    end

    -- ---------- поток ----------
    local drop    = num("frame-drop-count", 0)
    local ddrop   = num("decoder-frame-drop-count", 0)
    local delayed = num("vo-delayed-frame-count", 0)

    a:append("\\N" .. CYAN .. "ПОТОК" .. R .. "\\N")
    a:append(string.format("fps %.2f · %.1f Мбит/с · рассинхр %.3f с\\N",
        num("estimated-vf-fps", 0), num("video-bitrate", 0) / 1e6, num("avsync", 0)))
    a:append(string.format("дропы %s%d%s VO · %s%d%s декодер · задержки %s%d%s\\N",
        drop > 0 and RED or GREEN, drop, R,
        ddrop > 0 and RED or GREEN, ddrop, R,
        delayed > 60 and YELLOW or GREY, delayed, R))

    -- ---------- цепочка ----------
    a:append("\\N" .. CYAN .. "ЦЕПОЧКА" .. R .. "\\N")
    local line = {}
    for _, k in ipairs({ "scale", "cscale", "dscale", "tscale" }) do
        local v = str(k, "?")
        line[#line+1] = string.format("%s%s %s%s", GREY, k, v:find("ewa") and YELLOW or R, v)
    end
    a:append(table.concat(line, GREY .. " · " .. R) .. R .. "\\N")

    local deband = mp.get_property_bool("deband", false)
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local sh, nls = {}, false
    for _, s in ipairs(shaders) do
        sh[#sh+1] = s:match("([^/\\]+)%.glsl$") or s
        if s:find("nls%-") then nls = true end
    end
    local vf, vfn = mp.get_property_native("vf") or {}, {}
    for _, f in ipairs(vf) do vfn[#vfn+1] = f.label or f.name end

    a:append(string.format("дебанд %s · интерп. %s · шейдеры %s · фильтры %s\\N",
        deband and (GREEN .. "вкл" .. R) or (GREY .. "выкл" .. R),
        interp and (YELLOW .. "вкл " .. str("tscale", "") .. R) or (GREY .. "выкл" .. R),
        #sh > 0 and (GREEN .. table.concat(sh, ",") .. R) or (GREY .. "нет" .. R),
        #vfn > 0 and (GREEN .. table.concat(vfn, ",") .. R) or (GREY .. "нет" .. R)))

    -- ---------- режимы ----------
    local tp = mp.get_property("target-peak")
    local anti = tp and tp ~= "auto"
    a:append("\\N" .. CYAN .. "РЕЖИМЫ" .. R .. "  "
        .. (nls and GREEN or GREY) .. "NLS" .. R .. "  "
        .. (anti and GREEN or GREY) .. "антиблум" .. R
        .. (anti and string.format(" (пик %s, контраст %s)", tp, str("target-contrast", "auto")) or "")
        .. "\\N")
    a:append(GREY .. "n NLS · A антиблум · S в SDR · 1-5 дебанд · r/u/e/8 нейро" .. R)

    return a.text
end

local function render() if visible then mp.set_osd_ass(0, 0, build()) end end

local function toggle()
    visible = not visible
    if visible then
        render()
        timer = mp.add_periodic_timer(0.3, render)
    else
        if timer then timer:kill(); timer = nil end
        mp.set_osd_ass(0, 0, "")
    end
end

mp.add_key_binding(nil, "console-toggle", toggle)
mp.register_event("shutdown", function() mp.set_osd_ass(0, 0, "") end)
