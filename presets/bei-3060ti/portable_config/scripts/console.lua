-- console.lua — the metrics console.
-- Live numbers, the real frame budget, the priciest render passes,
-- the chain and the active modes. Open with F1 or i.
--
-- WHY. When playback stutters, eyes cannot tell where the wall is:
-- the decoder, the upscaler, a shader, or mismatched refresh rates. This
-- answers in numbers: how many ms of the budget a frame eats, and WHICH
-- pass eats the most.
--
-- ⚠ The subtlety it exists for: with
-- video-sync=display-resample and interpolation=yes a frame is recomputed
-- AT THE PANEL RATE, not the video rate. On 8K that means a 4K->8K upscale
-- runs 60 times a second instead of 24, and the budget drops
-- from 41.7 ms to 16.7. The "computed N times/s" line makes that explicit.
--
-- ⚠ vo-passes units: the docs say microseconds, but measured against
-- real fps with zero drops they are NANOseconds.
-- Verified on 4K HDR: 828000 units at 24 fps with no drops means
-- 0.83 ms, not 828 ms. So divide by 1e6.

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local visible, timer = false, nil

-- Claude palette. ASS reverses the channels: BGR, not RGB.
--  clay #D97757 · graphite #1A1915 · plate #2A2823 · border #46433A
--  text #F5F3EE · secondary #8F8B82 · dim #6B6862
local ACCENT = "{\\c&H5777D9&}"   -- #D97757, doubles as "attention"
local OK     = "{\\c&HA0BF7F&}"   -- muted sage, "healthy"
local WARN   = "{\\c&H70A8D0&}"   -- warm ochre, "borderline"
local FAINT  = "{\\c&H6B686B&}"   -- #6B6862
local R      = "{\\c&HEEF3F5&}"   -- #F5F3EE primary text
-- legacy names so the body below stays untouched
local GREEN, YELLOW, RED, GREY, CYAN = OK, WARN, ACCENT, FAINT, ACCENT

local function osd_size()
    local d = mp.get_property_native("osd-dimensions")
    local W = (d and d.w and d.w > 0) and d.w or mp.get_property_number("osd-width", 0)
    local H = (d and d.h and d.h > 0) and d.h or mp.get_property_number("osd-height", 0)
    if not W or W <= 0 then W = 1920 end
    if not H or H <= 0 then H = 1080 end
    return W, H
end

-- ⚠ assdraw SCALES coordinates (×8 by default). Draw only through its own
-- methods: appending "m x y l x y" by hand collapses the shape into a corner.
local function rrect(a, x, y, w, h, r)
    r = math.min(r, math.floor(w / 2), math.floor(h / 2))
    local x2, y2 = x + w, y + h
    a:move_to(x + r, y); a:line_to(x2 - r, y)
    a:bezier_curve(x2, y, x2, y, x2, y + r)
    a:line_to(x2, y2 - r); a:bezier_curve(x2, y2, x2, y2, x2 - r, y2)
    a:line_to(x + r, y2); a:bezier_curve(x, y2, x, y2, x, y2 - r)
    a:line_to(x, y + r);  a:bezier_curve(x, y, x, y, x + r, y)
end

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

-- total render time and the priciest passes
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

    -- Same warm graphite plate as the menu: numbers stay readable over any
    -- frame, and both overlays read as one family.
    local _, oh = osd_size()
    local s   = math.max(1, math.min(4, oh / 1080))
    local fs  = math.floor(12 * s + 0.5)
    local m   = math.floor(20 * s + 0.5)     -- panel inset from the edge
    local pad = math.floor(18 * s + 0.5)     -- inner padding
    a:new_event()
    a:append("{\\an7\\pos(0,0)\\bord1\\shad0\\1c&H15191A&\\1a&H2A&\\3c&H3A4346&\\3a&H60&}")
    a:draw_start()
    rrect(a, m, m, math.floor(470 * s), math.floor(395 * s), math.floor(10 * s))
    a:draw_stop()

    a:new_event()
    a:append(string.format("{\\an7\\pos(%d,%d)\\fs%d\\bord0\\shad0\\fnConsolas}",
        m + pad, m + pad, fs))

    local dw, dh   = num("display-width", 0), num("display-height", 0)
    local dfps     = num("display-fps", 0)
    local sw, sh   = num("video-params/w", 0), num("video-params/h", 0)
    local cfps     = num("container-fps", 0)
    local gamma    = str("video-params/gamma", "")
    local hdr      = (gamma == "pq" or gamma == "hlg") and (CYAN .. "HDR " .. gamma:upper() .. R) or "SDR"
    local interp   = mp.get_property_bool("interpolation", false)
    local vsync    = str("video-sync", "?")

    a:append(CYAN .. "CONSOLE" .. R .. GREY .. "  F1 to close" .. R .. "\\N")
    a:append(string.format("panel     %dx%d @ %.3f Hz\\N", dw, dh, dfps))
    a:append(string.format("source    %dx%d @ %.3f  %s %s  %s\\N",
        sw, sh, cfps, str("video-format", "?"):upper(),
        str("video-params/pixelformat", "?"), hdr))
    a:append(string.format("decoder   %s\\N", str("hwdec-current", "none")))

    -- ---------- the budget: the whole point ----------
    local rt, top = passes()
    local render_hz = (interp and vsync:find("display") and dfps > 0) and dfps or cfps
    if render_hz <= 0 then render_hz = dfps > 0 and dfps or 24 end
    local budget = 1000 / render_hz

    a:append("\\N" .. CYAN .. "FRAME BUDGET" .. R .. "\\N")
    if rt then
        local frac = rt / budget
        a:append(string.format("render    %s%.2f ms%s of %.1f  %s %d%%\\N",
            col(frac), rt, R, budget, bar(frac), math.floor(frac * 100 + 0.5)))
    else
        a:append(GREY .. "render    no data (needs vo=gpu-next)\\N" .. R)
    end
    if interp and render_hz > cfps + 1 then
        a:append(string.format("%scomputed %.0f times/s instead of %.0f (interpolation)%s\\N",
            YELLOW, render_hz, cfps, R))
    else
        a:append(string.format("%scomputed %.0f times/s (at video rate)%s\\N", GREY, render_hz, R))
    end

    if rt and #top > 0 then
        a:append(GREY .. "priciest passes:" .. R .. "\\N")
        for i = 1, math.min(3, #top) do
            if top[i].ms > 0.01 then
                a:append(string.format("  %s%5.2f ms%s  %s\\N",
                    col(top[i].ms / budget), top[i].ms, R, top[i].desc:sub(1, 40)))
            end
        end
    end

    -- ---------- stream ----------
    local drop    = num("frame-drop-count", 0)
    local ddrop   = num("decoder-frame-drop-count", 0)
    local delayed = num("vo-delayed-frame-count", 0)

    a:append("\\N" .. CYAN .. "STREAM" .. R .. "\\N")
    a:append(string.format("fps %.2f · %.1f Mbit/s · av-sync %.3f s\\N",
        num("estimated-vf-fps", 0), num("video-bitrate", 0) / 1e6, num("avsync", 0)))
    a:append(string.format("drops %s%d%s VO · %s%d%s decoder · delayed %s%d%s\\N",
        drop > 0 and RED or GREEN, drop, R,
        ddrop > 0 and RED or GREEN, ddrop, R,
        delayed > 60 and YELLOW or GREY, delayed, R))

    -- ---------- chain ----------
    a:append("\\N" .. CYAN .. "CHAIN" .. R .. "\\N")
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

    a:append(string.format("deband %s · interp %s · shaders %s · filters %s\\N",
        deband and (GREEN .. "on" .. R) or (GREY .. "off" .. R),
        interp and (YELLOW .. "on " .. str("tscale", "") .. R) or (GREY .. "off" .. R),
        #sh > 0 and (GREEN .. table.concat(sh, ",") .. R) or (GREY .. "none" .. R),
        #vfn > 0 and (GREEN .. table.concat(vfn, ",") .. R) or (GREY .. "none" .. R)))

    -- ---------- modes ----------
    local tp = mp.get_property("target-peak")
    local anti = tp and tp ~= "auto"
    a:append("\\N" .. CYAN .. "MODES" .. R .. "  "
        .. (nls and GREEN or GREY) .. "NLS" .. R .. "  "
        .. (anti and GREEN or GREY) .. "anti-bloom" .. R
        .. (anti and string.format(" (peak %s, contrast %s)", tp, str("target-contrast", "auto")) or "")
        .. "\\N")
    a:append(GREY .. "n NLS · A anti-bloom · S to SDR · 1-5 deband" .. R)

    return a.text
end

local function render()
    if not visible then return end
    local W, H = osd_size()
    mp.set_osd_ass(W, H, build())
end

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
