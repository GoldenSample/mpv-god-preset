-- Smart mode hotkeys: exclusivity + an HDR gate for SDR-trained networks.
-- The vapoursynth bridge does not pass the frame's transfer to scripts
-- (verified by dumping frame props), so the HDR gate lives here, where mpv
-- knows gamma before the filter.
-- Keys are exclusive: enabling a mode disables the others, no stacking.

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
        mp.osd_message(label .. ": off")
        return
    end
    if current then
        mp.command("vf remove vapoursynth=~~/" .. current)
    end
    mp.command("vf append vapoursynth=~~/" .. target)
    mp.osd_message(label .. ": on")
end

mp.add_key_binding("r", "smart-rife", function()
    switch_to("rife.vpy", "RIFE interpolation")
end)

mp.add_key_binding("u", "smart-upscale", function()
    if is_hdr() then
        mp.osd_message("HDR content: the anime network is SDR-trained, upscale skipped")
        return
    end
    switch_to("janai.vpy", "AnimeJaNai upscale")
end)

mp.add_key_binding("e", "smart-envy", function()
    if is_hdr() then
        mp.osd_message("HDR content: upscale skipped, enabling RIFE only")
        switch_to("rife.vpy", "RIFE interpolation")
        return
    end
    switch_to("envy.vpy", "Envy mode (upscale + RIFE)")
end)

mp.add_key_binding("8", "smart-8k", function()
    if is_hdr() then
        mp.osd_message("HDR content: the anime network is SDR-trained, 8K upscale skipped")
        return
    end
    switch_to("janai8k.vpy", "8K upscale (no interpolation)")

    -- 4K source + 60 Hz panel = 24 frames onto 60 Hz = 3:2 judder.
    -- 8K inference and interpolation don't fit the budget together (measured 17 Hz).
    local w = mp.get_property_number("video-params/w", 0)
    local dfps = mp.get_property_number("display-fps", 0)
    if w > 2560 and dfps > 50 and dfps < 70 then
        mp.osd_message("8K upscale: switch the panel to 8K 24 Hz for clean cadence", 5)
    end
end)
