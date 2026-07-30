-- nls.lua — one key for all of NLS. Looks at the video aspect ratio:
--   4:3 and narrower  -> superview  (horizontal stretch, edges sideways)
--   2.0:1 and wider   -> zoom + scope-fill (the Envy recipe: part of the
--                        work is done by zoom, part by the vertical stretch)
--   ~16:9             -> hunts for BAKED-IN black bars (cropdetect,
--                        ~1.5-3.5 s), crops them and proceeds as a scope.
--
-- KEYS: n on/off · N off · Alt+n more zoom · Alt+N less zoom
--
-- WHY THE ZOOM (paid for by a Miami Vice closeup): pure NLS hangs the
-- ENTIRE 1.32x stretch on the frame edges — locally ~2.8x at the rim, and
-- a closeup face spanning the full height gets uglified at forehead and
-- chin. So split the work: zoom shaves the sides (usually empty space),
-- leaving the stretch less to do. ZOOM_SHARE: 0 = stretch only, 1 = zoom
-- only (pure crop, zero distortion), 0.5 = even split. Live-tunable with
-- Alt+n / Alt+N, or preset with --script-opts=nls-zoom=0.35
--
-- IMPORTANT: shader and aspect are set directly, NOT via mpv.conf
-- profiles. video-aspect-override recomputes the pixel shape from the
-- FULL frame aspect, so for a crop the override must be computed:
--   override = (16/9) * (full frame aspect) / (crop aspect)

local SCOPE_SHADER = "~~/shaders/nls-scope.glsl"
local SV_SHADER    = "~~/shaders/nls-superview.glsl"
local TARGET       = 16 / 9
local FALLOFF      = 2.5

local zoom_share = tonumber(mp.get_opt("nls-zoom") or "") or 0.5
local shader_on, cropped, detecting = nil, false, false
local last = nil   -- remembered region, so the share can be tuned live

local function src_dims()
    local p = mp.get_property_native("video-params") or {}
    return p.w or 0, p.h or 0, p.aspect or 0
end

local function clear()
    if cropped then mp.set_property("video-crop", ""); cropped = false end
    if shader_on then
        mp.commandv("change-list", "glsl-shaders", "remove", shader_on)
        mp.set_property("video-aspect-override", "-1")
        mp.set_property("glsl-shader-opts", "")
        shader_on = nil
    end
end

-- single entry point: frame region (in source pixels) -> zoom + stretch
local function go(rx, ry, rw, rh, label, quiet)
    local sw, sh, sa = src_dims()
    if sw == 0 then return end
    last = { rx, ry, rw, rh, label }
    local full_ar = sa > 0 and sa or (sw / sh)
    local px = full_ar / (sw / sh)              -- pixel shape
    local region_ar = (rw / rh) * px
    label = label or ""

    if region_ar > 1.95 then
        -- scope: zoom shaves the sides, vertical stretch does the rest
        local needed = region_ar / TARGET       -- e.g. 1.32
        local z = needed ^ zoom_share
        local new_w = math.floor(rw / z / 2) * 2
        rx = rx + math.floor((rw - new_w) / 2)
        rw = new_w
        local rest = (rw / rh) * px / TARGET    -- what's left for the stretch
        mp.set_property("video-crop", ("%dx%d+%d+%d"):format(rw, rh, rx, ry))
        cropped = true
        if rest > 1.001 then
            mp.set_property("glsl-shader-opts",
                ("strength=%.4f,falloff=%.2f"):format(rest, FALLOFF))
            mp.commandv("change-list", "glsl-shaders", "append", SCOPE_SHADER)
            shader_on = SCOPE_SHADER
        end
        mp.set_property("video-aspect-override",
            tostring(TARGET * (sw / sh) / (rw / rh)))
        if not quiet then
            mp.osd_message(("NLS: %szoom %.0f%% + stretch %.0f%%  (zoom share %.1f)")
                :format(label, (z - 1) * 100, (rest - 1) * 100, zoom_share))
        end
    elseif region_ar < 1.55 then
        -- 4:3: pure horizontal NLS (zoom would cut heads off at the top)
        if rw ~= sw or rh ~= sh then
            mp.set_property("video-crop", ("%dx%d+%d+%d"):format(rw, rh, rx, ry))
            cropped = true
        end
        mp.set_property("glsl-shader-opts",
            ("strength=%.4f,falloff=%.2f"):format(TARGET / region_ar, FALLOFF))
        mp.commandv("change-list", "glsl-shaders", "append", SV_SHADER)
        shader_on = SV_SHADER
        mp.set_property("video-aspect-override",
            tostring(TARGET * (sw / sh) / (rw / rh)))
        if not quiet then
            mp.osd_message(("NLS superview: ON (%sAR %.2f -> 16:9)"):format(label, region_ar))
        end
    else
        mp.osd_message(("NLS: genuinely ~16:9 (AR %.2f), nothing to stretch"):format(region_ar))
    end
end

local function off()
    if detecting then return end
    clear(); last = nil
    mp.osd_message("NLS: off")
end

-- live tuning of the zoom share: rebuild the same region with a new value
local function nudge(d)
    if not last then mp.osd_message("NLS: turn it on first (n)") return end
    zoom_share = math.max(0, math.min(1, zoom_share + d))
    clear()
    go(last[1], last[2], last[3], last[4], last[5])
end

-- ~16:9 container: hunt for baked-in bars, then the normal path
local function detect_baked_bars()
    detecting = true
    mp.osd_message("NLS: hunting for baked-in bars...", 2)
    mp.command("vf add @nlsdet:lavfi=[cropdetect=limit=0.10:round=2:reset=0]")
    local tries, timer = 0, nil
    timer = mp.add_periodic_timer(0.25, function()
        tries = tries + 1
        local md = mp.get_property_native("vf-metadata/nlsdet") or {}
        local w = tonumber(md["lavfi.cropdetect.w"])
        local h = tonumber(md["lavfi.cropdetect.h"])
        local x = tonumber(md["lavfi.cropdetect.x"])
        local y = tonumber(md["lavfi.cropdetect.y"])
        local ready = w and h and w > 0 and h > 0 and tries >= 6
        if not ready and tries < 14 then return end
        timer:kill()
        mp.command("vf remove @nlsdet")
        detecting = false
        local sw, sh = src_dims()
        if not (w and h) or sw == 0 then
            mp.osd_message("NLS: no bars found (dark scene? try a brighter one)")
            return
        end
        local ar = w / h
        if w >= sw * 0.95 and h <= sh * 0.92 then
            -- over-crop guard for dark scenes: snap to 2.39, symmetric
            if ar < 1.95 or ar > 2.45 then
                h = math.floor(sw / 2.39 / 2) * 2
                y = math.floor((sh - h) / 2)
            end
            go(0, y or 0, sw, h, "bars cropped, ")
        elseif h >= sh * 0.95 and w <= sw * 0.92 then
            if ar < 1.25 or ar > 1.55 then
                w = math.floor(sh * 4 / 3 / 2) * 2
                x = math.floor((sw - w) / 2)
            end
            go(x or 0, 0, w, sh, "bars cropped, ")
        else
            mp.osd_message(("NLS: genuinely ~16:9 (picture %dx%d), nothing to stretch"):format(w, h))
        end
    end)
end

local function toggle()
    if shader_on or cropped or detecting then off() return end
    local sw, sh, a = src_dims()
    if a <= 0 then mp.osd_message("NLS: no video") return end
    if a >= 1.55 and a <= 1.95 then
        detect_baked_bars()
    else
        go(0, 0, sw, sh)
    end
end

mp.register_event("file-loaded", function()
    shader_on, cropped, detecting, last = nil, false, false, nil
end)

mp.add_key_binding(nil, "nls-toggle", toggle)
mp.add_key_binding(nil, "nls-off", off)
mp.add_key_binding(nil, "nls-more-zoom", function() nudge(0.1) end)
mp.add_key_binding(nil, "nls-less-zoom", function() nudge(-0.1) end)
