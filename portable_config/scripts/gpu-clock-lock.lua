-- Cure for the once-per-second microstutter.
--
-- Diagnosis 07-12: with two monitors of different refresh rates
-- (1440p@360 + 8K@60) and the low load of video playback, the driver drops
-- memory clocks 15306 -> 7001 MHz and back every second. Each memory clock
-- transition freezes the GPU for a few ms. Measured: output jitter 0.065
-- versus 0.0001 with locked memory (650x), plus delayed frames.
--
-- The lock is held only while the player is open and released on exit,
-- so the card doesn't sit at P0 around the clock.

local NVSMI = os.getenv("SystemRoot") .. "\\System32\\nvidia-smi.exe"
local MEM_CLOCK = "15306"   -- GDDR7 maximum on the 5090
local locked = false

local function run(args, async)
    local t = {
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    }
    if async then
        mp.command_native_async(t, function() end)
    else
        mp.command_native(t)
    end
end

local function lock()
    if locked then return end
    locked = true
    run({NVSMI, "-lmc", MEM_CLOCK}, true)
end

local function unlock()
    if not locked then return end
    locked = false
    run({NVSMI, "-rmc"}, false)  -- synchronous: must finish before exit
end

mp.register_event("file-loaded", lock)
mp.register_event("shutdown", unlock)

-- safety net: re-lock when playback resumes after a long pause
mp.observe_property("pause", "bool", function(_, paused)
    if paused == false then lock() end
end)
