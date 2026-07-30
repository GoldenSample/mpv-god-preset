-- nls.lua — one key for all of NLS. Looks at the video aspect ratio:
--   4:3 and narrower  -> superview   (horizontal stretch, edges sideways)
--   2.0:1 and wider   -> scope-fill  (vertical stretch, edges up/down)
--   ~16:9             -> nothing to stretch, says so honestly
-- Press n again = off. N = force off.
--
-- Real-world trap this is designed around: rips with BAKED-IN black bars
-- (a 4:3 show encoded as 1920x1080 with pillarbox burned into the pixels)
-- report ~16:9 and will NOT trigger — correctly, because stretching them
-- would smear the baked bars into the picture. Crop such files first.

local active = nil

local function off()
    if not active then return end
    mp.commandv("apply-profile", active, "restore")
    mp.osd_message("NLS: off")
    active = nil
end

local function toggle()
    if active then off() return end
    local a = mp.get_property_native("video-params/aspect") or 0
    if a <= 0 then mp.osd_message("NLS: no video") return end
    if a < 1.55 then
        active = "superview"
        mp.commandv("apply-profile", active)
        mp.osd_message(("NLS superview: ON (4:3 -> 16:9, AR %.2f)"):format(a))
    elseif a > 1.95 then
        active = "scope-fill"
        mp.commandv("apply-profile", active)
        mp.osd_message(("NLS scope-fill: ON (scope -> 16:9, AR %.2f)"):format(a))
    else
        mp.osd_message(("NLS: frame is already ~16:9 (AR %.2f), nothing to stretch"):format(a))
    end
end

-- reset state on file change (the applied profile dies with the file anyway)
mp.register_event("file-loaded", function() active = nil end)

mp.add_key_binding(nil, "nls-toggle", toggle)
mp.add_key_binding(nil, "nls-off", off)
