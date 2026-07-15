-- Лечение микростаттера раз в секунду.
--
-- Диагноз 07-12: с двумя мониторами разной герцовки (1440p@360 + 8K@60)
-- и низкой нагрузкой от видео драйвер каждую секунду роняет память
-- 15306 -> 7001 МГц и поднимает обратно. Каждая смена частоты памяти
-- морозит GPU на несколько мс. Замер: джиттер вывода 0.065 против 0.0001
-- при залоченной памяти (в 650 раз), плюс задержанные кадры.
--
-- Лок держится только пока открыт плеер и снимается при выходе,
-- чтобы карта не сидела на P0 круглые сутки.

local NVSMI = os.getenv("SystemRoot") .. "\\System32\\nvidia-smi.exe"
local MEM_CLOCK = "15306"   -- максимум GDDR7 на 5090
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
    run({NVSMI, "-rmc"}, false)  -- синхронно: успеть до выхода
end

mp.register_event("file-loaded", lock)
mp.register_event("shutdown", unlock)

-- страховка: снять лок, если плеер долго стоит на паузе
mp.observe_property("pause", "bool", function(_, paused)
    if paused == false then lock() end
end)
