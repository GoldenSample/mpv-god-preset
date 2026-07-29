-- auto-refresh.lua — switch the display to film cadence (23/24 Hz) when a
-- movie loads, restore the original rate when mpv quits. What madVR's
-- "display mode switcher" did, minus madVR.
--
-- Uses tools/set-refresh.ps1 (pure Win32, no third-party exes).
-- Disable per-launch with: mpv --script-opts=autorefresh=no
--
-- CAVEAT: 23.976 must exist as a mode ("23 Hz" on NVIDIA). If the driver
-- does not expose it, create it once in NVIDIA Control Panel -> Change
-- resolution -> Customize. True 24.000 is usually there out of the box.
-- CAVEAT: the restore-on-quit subprocess can be skipped if mpv is killed
-- hard; run set-refresh.ps1 -Hz <rate> by hand in that case.

local ps1 = mp.command_native({ "expand-path", "~~/tools/set-refresh.ps1" })
local original = nil
local enabled = mp.get_opt("autorefresh") ~= "no"

local function ps(args)
    local a = { "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1 }
    for _, v in ipairs(args) do table.insert(a, v) end
    local r = mp.command_native({
        name = "subprocess", args = a,
        capture_stdout = true, playback_only = false, -- must run at shutdown too
    })
    return r and r.status == 0, r and (r.stdout or "") or ""
end

local function current_hz()
    local ok, out = ps({ "-Get" })
    if ok then return tonumber(out:match("%d+")) end
end

-- candidate rates per container fps, best first
local function targets_for(fps)
    if not fps then return nil end
    if math.abs(fps - 23.976) < 0.02 then return { 23, 24 } end
    if math.abs(fps - 24.0)   < 0.02 then return { 24, 23 } end
    if math.abs(fps - 25.0)   < 0.02 then return { 50, 25 } end
    if math.abs(fps - 29.97)  < 0.05 then return { 60 } end
    if math.abs(fps - 50.0)   < 0.02 then return { 50 } end
    if fps > 59 and fps < 61          then return { 60 } end
    return nil
end

mp.register_event("file-loaded", function()
    if not enabled then return end
    local fps = mp.get_property_native("container-fps")
    local want = targets_for(fps)
    if not want then return end
    local cur = current_hz()
    if not cur then return end
    if not original then original = cur end
    for _, hz in ipairs(want) do
        if cur == hz then return end -- already there
    end
    for _, hz in ipairs(want) do
        if ps({ "-Hz", tostring(hz) }) then
            mp.osd_message(("Display: %d Hz (video %.3f fps)"):format(hz, fps), 3)
            return
        end
    end
    mp.osd_message("Refresh switch failed - create the mode in NVIDIA Control Panel", 4)
end)

mp.register_event("shutdown", function()
    if original then ps({ "-Hz", tostring(original) }) end
end)

mp.add_key_binding("H", "refresh-toggle", function()
    enabled = not enabled
    mp.osd_message("Auto refresh switch: " .. (enabled and "on" or "off"))
end)
