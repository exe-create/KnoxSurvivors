
local function getAnyLoadedPlayer()
    if getSpecificPlayer == nil then return nil end
    local count = 4
    if getNumActivePlayers ~= nil then
        local ok, n = pcall(getNumActivePlayers)
        if ok and tonumber(n) ~= nil then count = math.max(1, math.floor(tonumber(n))) end
    end
    for i = 0, math.max(0, count - 1) do
        local ok, p = pcall(getSpecificPlayer, i)
        if ok and p ~= nil and p.getCurrentSquare ~= nil then
            local okSq, sq = pcall(function() return p:getCurrentSquare() end)
            if okSq and sq ~= nil then return p end
        end
    end
    return nil
end
local TAG = "[KnoxSurvivors][EquipmentTest]"
-- Start on the first tick where the player, cell, and Java bridge are ready. The
-- former fixed 120-tick pause made a restored survivor visibly pop in late.
local STEP_DELAY_TICKS = 15
local MAX_WAIT_TICKS = 900

local ticks = 0
local phase = "IDLE"
local phaseStartedAt = 0
local lastResult = nil
local update

local function report(status, reason, evidence)
    lastResult = {
        status = tostring(status),
        reason = tostring(reason),
        evidence = tostring(evidence or "none"),
    }
    print(
        TAG
            .. " RESULT scenario=equipment status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function fail(reason, evidence)
    report("FAIL", reason, evidence)
    phase = "FINISHED"
    stop()
end

local function findNewSurvivorSquare()
    local player = getSpecificPlayer(0)
    local cell = getCell()
    if player == nil or player:getCurrentSquare() == nil or cell == nil then
        return nil
    end
    local origin = player:getCurrentSquare()
    local offsets = {
        { 4, 0 }, { 0, 4 }, { -4, 0 }, { 0, -4 },
        { 5, 2 }, { 2, 5 }, { -5, -2 }, { -2, -5 },
    }
    for _, offset in ipairs(offsets) do
        local square = cell:getGridSquare(
            origin:getX() + offset[1],
            origin:getY() + offset[2],
            origin:getZ()
        )
        if square ~= nil and square:canStand() then
            return square
        end
    end
    return nil
end

local function squareForRecord(bridge, record)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success then
        return nil, x
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function saveRecord()
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then
        return false, "persistence_module_unavailable"
    end
    return persistence.captureActiveTestSurvivor()
end

local function finishPass(reason, evidence)
    local saved, record = saveRecord()
    if not saved then
        fail("record_capture_failed", record)
        return
    end
    report("PASS", reason, evidence .. " recordBytes=" .. tostring(string.len(record)))
    phase = "FINISHED"
    stop()
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_WAIT_TICKS then
        fail("timeout", "phase=" .. phase)
        return
    end
    if phase ~= "WAIT_START" and ticks - phaseStartedAt < STEP_DELAY_TICKS then
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return
    end

    if phase == "WAIT_START" then
        local player = getSpecificPlayer(0)
        if player == nil or player:getCurrentSquare() == nil or getCell() == nil then
            return
        end
        local persistence = rawget(_G, "KnoxPersistence")
        local record = persistence ~= nil and persistence.getTestRecord() or nil
        if record ~= nil then
            local square, location = squareForRecord(bridge, record)
            if square == nil then
                report("BLOCKED", "saved_square_not_loaded", "location=" .. tostring(location))
                phase = "FINISHED"
                stop()
                return
            end
            local success, result = pcall(function()
                return bridge:restoreTestNpcRecord(record, square)
            end)
            if not success or string.find(tostring(result), "RESTORED", 1, true) ~= 1 then
                fail("disk_restore_failed", result)
                return
            end
            phase = "VERIFY_RESTORED"
            phaseStartedAt = ticks
            print(TAG .. " disk-restore=" .. tostring(result))
            return
        end

        local square = findNewSurvivorSquare()
        if square == nil then
            fail("no_valid_spawn_square", "near_player=true")
            return
        end
        local success, result = pcall(function()
            return bridge:spawnTestNpc(square)
        end)
        if not success or string.find(tostring(result), "SPAWNED", 1, true) ~= 1 then
            fail("spawn_failed", result)
            return
        end
        phase = "GENERATE_APPEARANCE"
        phaseStartedAt = ticks
        print(TAG .. " spawn=" .. tostring(result))
        return
    end

    if phase == "GENERATE_APPEARANCE" then
        local appearance = rawget(_G, "KnoxCharacterAppearance")
        if appearance == nil then
            fail("appearance_generator_unavailable", "none")
            return
        end
        local success, result = appearance.randomizeNewTestSurvivor(bridge)
        if not success then
            fail("appearance_generation_failed", result)
            return
        end
        phase = "SEED_EQUIPMENT"
        phaseStartedAt = ticks
        print(TAG .. " appearance=" .. tostring(result))
        return
    end

    if phase == "SEED_EQUIPMENT" then
        local success, result = pcall(function()
            return bridge:seedAndEquipTestNpc()
        end)
        if not success or string.find(tostring(result), "EQUIPPED", 1, true) ~= 1 then
            fail("auto_equip_failed", result)
            return
        end
        -- Persist the valid fixture before the destructive body recreation.
        -- This keeps the remaining QA probes independent when recreation
        -- reports a mismatch; a failed recreation must not erase their input.
        local saved, record = saveRecord()
        if not saved then
            fail("record_capture_failed", record)
            return
        end
        phase = "RECREATE_BODY"
        phaseStartedAt = ticks
        print(TAG .. " equipment=" .. tostring(result))
        return
    end

    if phase == "RECREATE_BODY" then
        local success, result = pcall(function()
            return bridge:recreateTestNpc()
        end)
        if not success
            or string.find(tostring(result), "RECREATED", 1, true) ~= 1
            or string.find(tostring(result), "matches=true", 1, true) == nil then
            fail("body_recreation_failed", result)
            return
        end
        finishPass("new_record_created", tostring(result))
        return
    end

    if phase == "VERIFY_RESTORED" then
        local success, result = pcall(function()
            return bridge:getTestNpcEquipmentStatus()
        end)
        if not success
            or string.find(tostring(result), "ACTIVE", 1, true) ~= 1
            or string.find(tostring(result), "primary=Base.BaseballBat", 1, true) == nil then
            fail("restored_state_mismatch", result)
            return
        end
        finishPass("disk_record_restored", tostring(result))
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "equipment" then
        return false, "disabled"
    end
    print(TAG .. " START auto=true scenario=equipment")
    ticks = 0
    phase = "WAIT_START"
    phaseStartedAt = 0
    lastResult = nil
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    if phase ~= "IDLE" then
        saveRecord()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxEquipmentProbe") or {}
_G.KnoxEquipmentProbe = Probe
function Probe.start()
    return start()
end
function Probe.status()
    return {
        phase = phase,
        finished = phase == "FINISHED",
        result = lastResult,
        ticks = ticks,
    }
end
function Probe.cleanup()
    stop()
end
