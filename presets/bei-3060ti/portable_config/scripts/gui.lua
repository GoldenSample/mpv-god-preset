-- gui.lua — on-screen menu: every mode as a button, driven by the mouse.
-- Open: right-click the picture, or press m.
-- (Distribution build: the NEURAL group is omitted — RIFE/AnimeJaNai need
--  VapourSynth plugins and multi-GB TensorRT engines that ship separately.)
-- Close: right-click, m, Esc, or click outside the panel.
--
-- Why, on top of hotkeys: two dozen keys have piled up, and nobody keeps that
-- in their head from a couch or a remote. The menu shows EVERYTHING that is on
-- at a glance, and switches it with one click.
--
-- State is read from the player at draw time rather than cached, so it can
-- never drift out of sync after a keypress or a profile switch.
--
-- LOOK: Claude design language — warm graphite panel, clay accent, cream text,
-- rounded plates, generous breathing room. Colors below are written as RGB in
-- the comment and as ASS BGR in the code, because ASS reverses the channels.

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local open, hover, timer = false, nil, nil

-- ---------- palette (Claude) ----------
--  clay accent     #D97757   panel bg    #1A1915   plate bg   #2A2823
--  plate hover     #3A372F   border      #46433A   text       #F5F3EE
--  text secondary  #8F8B82   text dim    #6B6862
local C = {
    accent   = "5777D9",   -- #D97757
    panel    = "15191A",   -- #1A1915
    plate    = "23282A",   -- #2A2823
    hover    = "2F373A",   -- #3A372F
    border   = "3A4346",   -- #46433A
    text     = "EEF3F5",   -- #F5F3EE
    on_text  = "15191A",   -- #1A1915 (on the clay fill)
    dim      = "828B8F",   -- #8F8B82
    faint    = "6B686B",   -- #6B6862
}

-- ---------- geometry ----------
-- Sized for a 1080-tall OSD and scaled to the real one: on 4K and 8K panels
-- the menu has to stay readable from the couch instead of shrinking into a
-- postage stamp in the corner.
local BASE = { pad = 30, bw = 210, bh = 46, gap = 11, cols = 3,
               title_h = 42, fs = 17, fs_small = 15, fs_grp = 13, fs_key = 12,
               radius = 8, head = 34 }
local G = {}
for k, v in pairs(BASE) do G[k] = v end

-- ---------- state readers ----------
local function shaders() return mp.get_property_native("glsl-shaders") or {} end

local function has_shader(pat)
    for _, s in ipairs(shaders()) do if s:find(pat) then return true end end
    return false
end

local function cur_vpy()
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.name == "vapoursynth" and f.params and f.params.file then
            return f.params.file:match("([^/\\]+)%.vpy$")
        end
    end
    return nil
end

local function deband_level()
    if not mp.get_property_bool("deband", false) then return nil end
    local th = mp.get_property_number("deband-threshold", 0)
    if th >= 80 then return "xtreme" elseif th >= 60 then return "strong"
    elseif th >= 40 then return (mp.get_property_number("deband-grain",0) <= 8) and "HDR" or "medium"
    else return "light" end
end

-- ---------- button table ----------
-- on() = is it active right now; act() = what a click does
local BUTTONS = {
  { grp = "FRAME" },
  { label = "NLS: fill the screen", key = "n",
    on  = function() return has_shader("nls%-") end,
    act = function() mp.commandv("script-binding", "nls-toggle") end },
  { label = "more zoom", key = "Alt+n", small = true,
    act = function() mp.commandv("script-binding", "nls-more-zoom") end },
  { label = "more stretch", key = "Alt+N", small = true,
    act = function() mp.commandv("script-binding", "nls-less-zoom") end },

  { grp = "AGAINST HALOS" },
  { label = "anti-bloom", key = "A", note = "peak 600",
    on  = function() local p = mp.get_property("target-peak"); return p and p ~= "auto" end,
    act = function()
        local p = mp.get_property("target-peak")
        if p and p ~= "auto" then mp.commandv("apply-profile","hdr-antibloom","restore")
        else mp.commandv("apply-profile","hdr-antibloom") end
    end },
  { label = "dark film in SDR", key = "S",
    on  = function() return mp.get_property("target-trc") == "gamma2.2" end,
    act = function()
        if mp.get_property("target-trc") == "gamma2.2" then
            mp.commandv("apply-profile","sdr-dark-cinema","restore")
        else mp.commandv("apply-profile","sdr-dark-cinema") end
    end },
  { label = "cycle peak cap", key = "k",
    act = function() mp.commandv("cycle-values","profile","peak-1000","peak-600","peak-400") end },

  { grp = "DEBAND" },
  { label = "light",  key = "1", on = function() return deband_level()=="light"  end,
    act = function() mp.commandv("apply-profile","deband-light") end },
  { label = "medium", key = "2", on = function() return deband_level()=="medium" end,
    act = function() mp.commandv("apply-profile","deband-medium") end },
  { label = "strong", key = "3", on = function() return deband_level()=="strong" end,
    act = function() mp.commandv("apply-profile","deband-strong") end },
  { label = "for HDR", key = "5", on = function() return deband_level()=="HDR" end,
    act = function() mp.commandv("apply-profile","deband-hdr") end },
  { label = "off", key = "0", on = function() return deband_level()==nil end,
    act = function() mp.set_property_bool("deband", false) end },

  { grp = "DIAGNOSTICS" },
  { label = "metrics console", key = "F1",
    act = function() mp.commandv("script-binding","console-toggle") end },
  { label = "mpv stats", key = "TAB",
    act = function() mp.commandv("script-binding","stats/display-stats-toggle") end },
}

-- ---------- rounded rectangle ----------
-- ⚠ Paid for in debugging: assdraw SCALES coordinates (by 2^(scale-1), ×8 by
-- default). Appending "m x y l x y" by hand collapses the shape into the
-- corner of the screen. Use only move_to / line_to / bezier_curve — those
-- apply the multiplier themselves.
local function rrect(a, x, y, w, h, r)
    r = math.min(r, math.floor(w / 2), math.floor(h / 2))
    local x2, y2 = x + w, y + h
    a:move_to(x + r, y)
    a:line_to(x2 - r, y)
    a:bezier_curve(x2, y, x2, y, x2, y + r)
    a:line_to(x2, y2 - r)
    a:bezier_curve(x2, y2, x2, y2, x2 - r, y2)
    a:line_to(x + r, y2)
    a:bezier_curve(x, y2, x, y2, x, y2 - r)
    a:line_to(x, y + r)
    a:bezier_curve(x, y, x, y, x + r, y)
end

-- ---------- layout ----------
local function osd_size()
    local d = mp.get_property_native("osd-dimensions")
    local W = (d and d.w and d.w > 0) and d.w or mp.get_property_number("osd-width", 0)
    local H = (d and d.h and d.h > 0) and d.h or mp.get_property_number("osd-height", 0)
    if not W or W <= 0 then W = 1920 end
    if not H or H <= 0 then H = 1080 end
    return W, H
end

local function rescale(H)
    local s = math.max(1, math.min(4, H / 1080))
    for k, v in pairs(BASE) do
        G[k] = (k == "cols") and v or math.floor(v * s + 0.5)
    end
end

local function layout()
    local W, H = osd_size()
    rescale(H)
    local col, items, y = 0, {}, G.head
    for _, b in ipairs(BUTTONS) do
        if b.grp then
            if col > 0 then y = y + G.bh + G.gap; col = 0 end
            y = y + G.title_h
            items[#items+1] = { grp = b.grp, y = y - math.floor(G.title_h * 0.55) }
        else
            items[#items+1] = { btn = b, x = col * (G.bw + G.gap), y = y, w = G.bw, h = G.bh }
            col = col + 1
            if col >= G.cols then col = 0; y = y + G.bh + G.gap end
        end
    end
    if col > 0 then y = y + G.bh + G.gap end
    local pw = G.cols * G.bw + (G.cols - 1) * G.gap + G.pad * 2
    local ph = y + G.pad
    return items, math.floor((W - pw) / 2), math.floor((H - ph) / 2), pw, ph, W, H
end

local function hit(items, ox, oy, mx, my)
    for _, it in ipairs(items) do
        if it.btn then
            local x, y = ox + G.pad + it.x, oy + it.y
            if mx >= x and mx <= x + it.w and my >= y and my <= y + it.h then return it end
        end
    end
    return nil
end

-- ---------- drawing ----------
local function draw()
    if not open then return end
    local items, ox, oy, pw, ph, W, H = layout()
    local a = assdraw.ass_new()

    -- panel: soft graphite, barely translucent, hairline warm border
    a:new_event()
    a:append(string.format("{\\an7\\pos(0,0)\\bord%d\\shad0\\1c&H%s&\\1a&H26&\\3c&H%s&\\3a&H50&}",
        math.max(1, math.floor(G.radius / 5)), C.panel, C.border))
    a:draw_start(); rrect(a, ox, oy, pw, ph, G.radius * 2); a:draw_stop()

    -- title: clay wordmark + quiet hint
    a:new_event()
    a:append(string.format("{\\an1\\pos(%d,%d)\\fs%d\\b1\\bord0\\shad0\\1c&H%s&}",
        ox + G.pad, oy + G.head - math.floor(G.fs * 0.4), G.fs, C.accent))
    a:append("mpv")
    a:new_event()
    a:append(string.format("{\\an1\\pos(%d,%d)\\fs%d\\bord0\\shad0\\1c&H%s&}",
        ox + G.pad + math.floor(G.fs * 2.6), oy + G.head - math.floor(G.fs * 0.4),
        G.fs_grp, C.faint))
    a:append("right-click or m to close")

    for _, it in ipairs(items) do
        if it.grp then
            a:new_event()
            a:append(string.format("{\\an1\\pos(%d,%d)\\fs%d\\bord0\\shad0\\fsp%d\\1c&H%s&}",
                ox + G.pad, oy + it.y, G.fs_grp, math.max(1, math.floor(G.fs_grp / 9)), C.dim))
            a:append(it.grp)
        else
            local b = it.btn
            local x, y = ox + G.pad + it.x, oy + it.y
            local active = b.on and b.on() or false
            local hot = (hover == it)

            -- plate
            local fill = active and C.accent or (hot and C.hover or C.plate)
            local alpha = active and "&H14&" or (hot and "&H1E&" or "&H32&")
            a:new_event()
            a:append(string.format("{\\an7\\pos(0,0)\\bord%d\\shad0\\1c&H%s&\\1a%s\\3c&H%s&\\3a&H%s&}",
                hot and math.max(2, math.floor(G.radius / 3)) or 1,
                fill, alpha, active and C.accent or C.border, hot and "40" or "70"))
            a:draw_start(); rrect(a, x, y, it.w, it.h, G.radius); a:draw_stop()

            -- label
            a:new_event()
            a:append(string.format("{\\an4\\pos(%d,%d)\\fs%d\\bord0\\shad0\\1c&H%s&}",
                x + math.floor(G.bh * 0.34), y + it.h / 2,
                b.small and G.fs_small or G.fs,
                active and C.on_text or C.text))
            a:append(b.label)

            -- optional note under the label (e.g. "peak 600")
            if b.note and not b.small then
                a:new_event()
                a:append(string.format("{\\an4\\pos(%d,%d)\\fs%d\\bord0\\shad0\\1c&H%s&}",
                    x + math.floor(G.bh * 0.34), y + it.h / 2 + math.floor(G.fs * 0.95),
                    G.fs_key, active and C.on_text or C.faint))
                a:append(b.note)
            end

            -- key hint, right aligned
            a:new_event()
            a:append(string.format("{\\an6\\pos(%d,%d)\\fs%d\\bord0\\shad0\\1c&H%s&}",
                x + it.w - math.floor(G.bh * 0.30), y + it.h / 2, G.fs_key,
                active and C.on_text or C.faint))
            a:append(b.key)
        end
    end

    mp.set_osd_ass(W, H, a.text)
end

-- ---------- input ----------
local function on_mouse()
    if not open then return end
    local pos = mp.get_property_native("mouse-pos")
    if not pos then return end
    local items, ox, oy = layout()
    local h = hit(items, ox, oy, pos.x, pos.y)
    if h ~= hover then hover = h; draw() end
end

local function click()
    if not open then return end
    local pos = mp.get_property_native("mouse-pos")
    if not pos then return end
    local items, ox, oy, pw, ph = layout()
    local h = hit(items, ox, oy, pos.x, pos.y)
    if h then
        h.btn.act()
        mp.add_timeout(0.05, draw)          -- let the change settle
    elseif pos.x < ox or pos.x > ox + pw or pos.y < oy or pos.y > oy + ph then
        mp.commandv("script-binding", "gui-toggle")
    end
end

local BINDS = {
    { "MBTN_LEFT",  "gui-click", click },
    { "MBTN_RIGHT", "gui-close", function() mp.commandv("script-binding", "gui-toggle") end },
    { "ESC",        "gui-esc",   function() mp.commandv("script-binding", "gui-toggle") end },
}

local function toggle()
    open = not open
    if open then
        for _, b in ipairs(BINDS) do mp.add_forced_key_binding(b[1], b[2], b[3]) end
        mp.observe_property("mouse-pos", "native", on_mouse)
        draw()
        timer = mp.add_periodic_timer(0.5, draw)   -- keys can change state too
    else
        for _, b in ipairs(BINDS) do mp.remove_key_binding(b[2]) end
        mp.unobserve_property(on_mouse)
        if timer then timer:kill(); timer = nil end
        hover = nil
        mp.set_osd_ass(0, 0, "")
    end
end

mp.add_key_binding(nil, "gui-toggle", toggle)
mp.register_event("shutdown", function() mp.set_osd_ass(0, 0, "") end)
