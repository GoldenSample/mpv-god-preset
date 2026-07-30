-- nls.lua — one key for all of NLS. Looks at the video aspect ratio:
--   4:3 and narrower  -> superview   (horizontal stretch, edges sideways)
--   2.0:1 and wider   -> scope-fill  (vertical stretch, edges up/down)
--   ~16:9             -> hunts for BAKED-IN black bars (cropdetect,
--                        ~1.5-3.5 s), crops them off and stretches what
--                        was underneath; found nothing — says so honestly.
-- Press n again = off. N = force off.
--
-- IMPORTANT: the shader and aspect are set directly, NOT via mpv.conf
-- profiles. Paid-for reason: video-aspect-override recomputes the pixel
-- shape from the aspect of the FULL frame. For a 16:9 rip with baked-in
-- bars, override=16/9 is a no-op (pixels stay square) and the cropped
-- frame honestly displays as 2.35 with window bars. The correct override
-- for a cropped region is:
--   override = (16/9) * (full-frame pixel AR) / (crop pixel AR)

local SCOPE_SHADER = "~~/shaders/nls-scope.glsl"
local SV_SHADER    = "~~/shaders/nls-superview.glsl"
local TARGET       = 16 / 9

local shader_on = nil     -- path of the active shader
local cropped = false
local detecting = false

local function src_dims()
    local p = mp.get_property_native("video-params") or {}
    return p.w or 0, p.h or 0, p.aspect or 0
end

local function engage(shader, crop_w, crop_h, label)
    local sw, sh, sa = src_dims()
    if sw == 0 then return end
    local full_ar = sa > 0 and sa or (sw / sh)
    local crop_ar = (crop_w / crop_h) * (full_ar / (sw / sh))
    local override = TARGET * full_ar / crop_ar
    mp.commandv("change-list", "glsl-shaders", "append", shader)
    mp.set_property("video-aspect-override", tostring(override))
    shader_on = shader
    mp.osd_message(("NLS: ON (%sAR %.2f -> 16:9, center protected)"):format(label or "", crop_ar))
end

local function off()
    if detecting then return end
    if cropped then mp.set_property("video-crop", ""); cropped = false end
    if shader_on then
        mp.commandv("change-list", "glsl-shaders", "remove", shader_on)
        mp.set_property("video-aspect-override", "-1")
        shader_on = nil
    end
    mp.osd_message("NLS: off")
end

-- ~16:9 container: hunt for baked-in bars, crop, stretch what's underneath
local function detect_baked_bars()
    detecting = true
    mp.osd_message("NLS: hunting for baked-in bars...", 2)
    mp.command("vf add @nlsdet:lavfi=[cropdetect=limit=0.10:round=2:reset=0]")
    local tries = 0
    local timer
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
        -- letterbox: near-full width, scope hiding under the bars
        if w >= sw * 0.95 and h <= sh * 0.92 then
            -- over-crop guard for dark scenes: snap to 2.39, symmetric
            if ar < 1.95 or ar > 2.45 then
                h = math.floor(sw / 2.39 / 2) * 2
                y = math.floor((sh - h) / 2)
            end
            mp.set_property("video-crop", ("%dx%d+0+%d"):format(sw, h, y or 0))
            cropped = true
            engage(SCOPE_SHADER, sw, h, "bars cropped, ")
        -- pillarbox: near-full height, 4:3 hiding under the bars
        elseif h >= sh * 0.95 and w <= sw * 0.92 then
            if ar < 1.25 or ar > 1.55 then
                w = math.floor(sh * 4 / 3 / 2) * 2
                x = math.floor((sw - w) / 2)
            end
            mp.set_property("video-crop", ("%dx%d+%d+0"):format(w, sh, x or 0))
            cropped = true
            engage(SV_SHADER, w, sh, "bars cropped, ")
        else
            mp.osd_message(("NLS: genuinely ~16:9 (picture %dx%d), nothing to stretch"):format(w, h))
        end
    end)
end

local function toggle()
    if shader_on or cropped or detecting then off() return end
    local sw, sh, a = src_dims()
    if a <= 0 then mp.osd_message("NLS: no video") return end
    if a < 1.55 then
        engage(SV_SHADER, sw, sh)
    elseif a > 1.95 then
        engage(SCOPE_SHADER, sw, sh)
    else
        detect_baked_bars()
    end
end

-- reset state on file change (crop and options die with the file anyway)
mp.register_event("file-loaded", function()
    shader_on = nil; cropped = false; detecting = false
end)

mp.add_key_binding(nil, "nls-toggle", toggle)
mp.add_key_binding(nil, "nls-off", off)
