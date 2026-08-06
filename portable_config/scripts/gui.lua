-- gui.lua — on-screen menu: every mode as a button, driven by the mouse.
-- Open: right-click the picture, or press m.
-- Close: right-click, m, Esc, or click outside the panel.
--
-- Why, on top of hotkeys: two dozen keys have piled up, and nobody keeps that
-- in their head from a couch or a remote. The menu shows EVERYTHING that is on
-- at a glance, and switches it with one click.
--
-- State is read from the player at draw time rather than cached, so it can
-- never drift out of sync after a keypress or a profile switch.

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local open, hover, timer = false, nil, nil

-- ---------- geometry ----------
-- Sized for a 1080-tall OSD and scaled to the real one: on 4K and 8K panels
-- the menu has to stay readable from the couch instead of shrinking into a
-- postage stamp in the corner.
local BASE_PAD, BASE_BW, BASE_BH, BASE_GAP, COLS = 18, 190, 38, 9, 3
local BASE_TITLE_H, BASE_FS, BASE_FS_SMALL, BASE_FS_GRP, BASE_FS_KEY = 34, 16, 14, 14, 12
local PAD, BW, BH, GAP, TITLE_H = BASE_PAD, BASE_BW, BASE_BH, BASE_GAP, BASE_TITLE_H
local FS, FS_SMALL, FS_GRP, FS_KEY = BASE_FS, BASE_FS_SMALL, BASE_FS_GRP, BASE_FS_KEY

-- ---------- state readers ----------
local function shaders()
    return mp.get_property_native("glsl-shaders") or {}
end

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
    local it = mp.get_property_number("deband-iterations", 0)
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
    on = function() return has_shader("nls%-") end,
    act = function() mp.commandv("script-binding", "nls-toggle") end },
  { label = "more zoom",  key = "Alt+n", small = true,
    on = function() return false end,
    act = function() mp.commandv("script-binding", "nls-more-zoom") end },
  { label = "more stretch", key = "Alt+N", small = true,
    on = function() return false end,
    act = function() mp.commandv("script-binding", "nls-less-zoom") end },

  { grp = "AGAINST HALOS" },
  { label = "anti-bloom (peak 600)", key = "A",
    on = function() local p = mp.get_property("target-peak"); return p and p ~= "auto" end,
    act = function()
        local p = mp.get_property("target-peak")
        if p and p ~= "auto" then mp.commandv("apply-profile","hdr-antibloom","restore")
        else mp.commandv("apply-profile","hdr-antibloom") end
    end },
  { label = "dark film in SDR", key = "S",
    on = function() return mp.get_property("target-trc") == "gamma2.2" end,
    act = function()
        if mp.get_property("target-trc") == "gamma2.2" then
            mp.commandv("apply-profile","sdr-dark-cinema","restore")
        else mp.commandv("apply-profile","sdr-dark-cinema") end
    end },
  { label = "cycle peak cap", key = "k",
    on = function() return false end,
    act = function() mp.commandv("cycle-values","profile","peak-1000","peak-600","peak-400") end },

  { grp = "DEBAND" },
  { label = "light",  key = "1", on = function() return deband_level()=="light"  end,
    act = function() mp.commandv("apply-profile","deband-light") end },
  { label = "medium", key = "2", on = function() return deband_level()=="medium" end,
    act = function() mp.commandv("apply-profile","deband-medium") end },
  { label = "strong", key = "3", on = function() return deband_level()=="strong" end,
    act = function() mp.commandv("apply-profile","deband-strong") end },
  { label = "for HDR", key = "5", on = function() return deband_level()=="HDR"    end,
    act = function() mp.commandv("apply-profile","deband-hdr") end },
  { label = "off", key = "0", on = function() return deband_level()==nil     end,
    act = function() mp.set_property_bool("deband", false) end },

  { grp = "NEURAL" },
  { label = "RIFE: smoothness", key = "r", on = function() return cur_vpy()=="rife" end,
    act = function() mp.commandv("script-binding","smart-rife") end },
  { label = "anime upscale", key = "u", on = function() return cur_vpy()=="janai" end,
    act = function() mp.commandv("script-binding","smart-upscale") end },
  { label = "Envy: all in one", key = "e", on = function() return cur_vpy()=="envy" end,
    act = function() mp.commandv("script-binding","smart-envy") end },
  { label = "upscale to 8K", key = "8", on = function() return cur_vpy()=="janai8k" end,
    act = function() mp.commandv("script-binding","smart-8k") end },

  { grp = "DIAGNOSTICS" },
  { label = "metrics console", key = "F1", on = function() return false end,
    act = function() mp.commandv("script-binding","console-toggle") end },
  { label = "mpv stats", key = "TAB", on = function() return false end,
    act = function() mp.commandv("script-binding","stats/display-stats-toggle") end },
}

-- ---------- layout: compute the rectangles ----------
local function osd_size()
    local d = mp.get_property_native("osd-dimensions")
    local W = (d and d.w and d.w > 0) and d.w or mp.get_property_number("osd-width", 0)
    local H = (d and d.h and d.h > 0) and d.h or mp.get_property_number("osd-height", 0)
    if not W or W <= 0 then W = 1920 end
    if not H or H <= 0 then H = 1080 end
    return W, H
end

local function rescale(H)
    local s = H / 1080
    if s < 1 then s = 1 end          -- never smaller than the base size
    if s > 4 then s = 4 end
    PAD      = math.floor(BASE_PAD * s)
    BW       = math.floor(BASE_BW * s)
    BH       = math.floor(BASE_BH * s)
    GAP      = math.floor(BASE_GAP * s)
    TITLE_H  = math.floor(BASE_TITLE_H * s)
    FS       = math.floor(BASE_FS * s)
    FS_SMALL = math.floor(BASE_FS_SMALL * s)
    FS_GRP   = math.floor(BASE_FS_GRP * s)
    FS_KEY   = math.floor(BASE_FS_KEY * s)
    return s
end

local function layout()
    local W, H = osd_size()
    rescale(H)
    local rows, col, items = {}, 0, {}
    local y = 0
    for _, b in ipairs(BUTTONS) do
        if b.grp then
            if col > 0 then y = y + BH + GAP; col = 0 end
            y = y + TITLE_H
            items[#items+1] = { grp = b.grp, y = y - math.floor(TITLE_H * 0.6) }
        else
            local x = col * (BW + GAP)
            items[#items+1] = { btn = b, x = x, y = y, w = BW, h = BH }
            col = col + 1
            if col >= COLS then col = 0; y = y + BH + GAP end
        end
    end
    if col > 0 then y = y + BH + GAP end
    local panelW = COLS * BW + (COLS - 1) * GAP + PAD * 2
    local panelH = y + PAD * 2
    local ox = math.floor((W - panelW) / 2)
    local oy = math.floor((H - panelH) / 2)
    return items, ox, oy, panelW, panelH, W, H
end

local function hit(items, ox, oy, mx, my)
    for _, it in ipairs(items) do
        if it.btn then
            local x, y = ox + PAD + it.x, oy + PAD + it.y
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

    -- panel background
    a:new_event()
    a:append("{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H101010&\\1a&H30&}")
    a:draw_start(); a:rect_cw(ox, oy, ox + pw, oy + ph); a:draw_stop()

    -- title
    a:new_event()
    a:append(string.format("{\\an7\\pos(%d,%d)\\fs%d\\bord1\\shad1\\fnConsolas\\1c&HF0D060&}",
        ox + PAD, oy + PAD - math.floor(FS * 0.9), FS))
    a:append("PLAYER MENU{\\1c&H909090&}   right-click or m to close")

    for _, it in ipairs(items) do
        if it.grp then
            a:new_event()
            a:append(string.format("{\\an7\\pos(%d,%d)\\fs%d\\bord1\\shad0\\fnConsolas\\1c&HF0D060&}",
                ox + PAD, oy + PAD + it.y, FS_GRP))
            a:append(it.grp)
        else
            local b = it.btn
            local x, y = ox + PAD + it.x, oy + PAD + it.y
            local active = b.on and b.on() or false
            local hot = (hover == it)
            -- button plate
            local fill = active and "&H2E7D32&" or (hot and "&H404040&" or "&H232323&")
            a:new_event()
            a:append(string.format("{\\an7\\pos(0,0)\\bord%d\\shad0\\1c%s\\1a&H20&\\3c&H%s&}",
                hot and 2 or 1, fill, active and "70D070" or "555555"))
            a:draw_start(); a:rect_cw(x, y, x + it.w, y + it.h); a:draw_stop()
            -- label
            a:new_event()
            a:append(string.format("{\\an4\\pos(%d,%d)\\fs%d\\bord1\\shad1\\fnConsolas\\1c&H%s&}",
                x + math.floor(10 * (BH / BASE_BH)), y + it.h / 2,
                b.small and FS_SMALL or FS,
                active and "C8FFC8" or "E8E8E8"))
            a:append(b.label)
            -- key hint, right-aligned
            a:new_event()
            a:append(string.format("{\\an6\\pos(%d,%d)\\fs%d\\bord1\\shad0\\fnConsolas\\1c&H808080&}",
                x + it.w - math.floor(9 * (BH / BASE_BH)), y + it.h / 2, FS_KEY))
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
        mp.add_timeout(0.05, draw)   -- let the change settle before redrawing
    elseif pos.x < ox or pos.x > ox + pw or pos.y < oy or pos.y > oy + ph then
        -- a click outside the panel closes the menu
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
        timer = mp.add_periodic_timer(0.5, draw)  -- keys can change state too
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
