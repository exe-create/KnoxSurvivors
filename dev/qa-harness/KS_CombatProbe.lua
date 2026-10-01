
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
local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 1800
local STATUS_INTERVAL_TICKS = 60
local ZOMBIE_CLEAR_INTERVAL_TICKS = 15

local ticks = 0
local phase = "IDLE"
local targetZombie = nil
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
            .. " RESULT scenario=combat status="
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

local function removeZombie(zombie)
    if zombie == nil then
        return
    end
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end

local function clearLoadedZombies(exceptZombie)
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.allowZombieCleanup ~= true then
        return 0
    end
    local cell = getCell()
    if cell == nil then
        return 0
    end
    local zombies = cell:getZombieList()
    local removed = 0
    for index = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(index)
        if zombie ~= exceptZombie then
            removeZombie(zombie)
            removed = removed + 1
        end
    end
    return removed
end

local function findCombatSquares(origin)
    local cell = getCell()
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    }
    for _, direction in ipairs(directions) do
        local previous = origin
        local approach = nil
        local valid = true
        for distance = 1, 3 do
            local square = cell:getGridSquare(
                origin:getX() + direction[1] * distance,
                origin:getY() + direction[2] * distance,
                origin:getZ()
            )
            if square == nil or not square:canStand() or previous:isBlockedTo(square) then
                valid = false
                break
            end
            if distance == 2 then
                approach = square
            end
            previous = square
        end
        if valid then
            return approach, previous
        end
    end
    return nil, nil
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

local function restoreSurvivor(bridge)
    local persistence = rawget(_G, "KnoxPersistence")
    local record = persistence ~= nil and persistence.getTestRecord() or nil
    if record == nil then
        return false, "missing_persistent_survivor"
    end
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return false, "saved_square_not_loaded location=" .. tostring(location)
    end
    local success, result = pcall(function()
        return bridge:restoreTestNpcRecord(record, square)
    end)
    return success and string.find(tostring(result), "RESTORED", 1, true) == 1, result
end

local function startCombat(bridge, survivorSquare, playerSquare)
    local removed = clearLoadedZombies(nil)
    local approachSquare, zombieSquare = findCombatSquares(survivorSquare)
    local laneSource = "survivor"
    if zombieSquare == nil and playerSquare ~= nil then
        approachSquare, zombieSquare = findCombatSquares(playerSquare)
        laneSource = "player"
    end
    if zombieSquare == nil then
        report(
            "BLOCKED",
            "no_clear_combat_lane",
            "clearedLoadedZombies=" .. tostring(removed) .. " stand_in_an_open_area=true"
        )
        phase = "FINISHED"
        stop()
        return
    end

    local zombies = addZombiesInOutfit(
        zombieSquare:getX(), zombieSquare:getY(), zombieSquare:getZ(), 1, nil, nil
    )
    targetZombie = zombies ~= nil and zombies:size() > 0 and zombies:get(0) or nil
    if targetZombie == nil then
        report("FAIL", "test_zombie_spawn_failed", "cleared=" .. tostring(removed))
        phase = "FINISHED"
        stop()
        return
    end

    local success, result = pcall(function()
        return bridge:beginTestNpcCombat(targetZombie, approachSquare)
    end)
    if not success or string.find(tostring(result), "COMBAT_STARTED", 1, true) ~= 1 then
        removeZombie(targetZombie)
        targetZombie = nil
        report("FAIL", "combat_start_failed", tostring(result))
        phase = "FINISHED"
        stop()
        return
    end

    print(
        TAG
            .. " combat-start="
            .. tostring(result)
            .. " clearedLoadedZombies="
            .. tostring(removed)
            .. " laneSource="
            .. laneSource
    )
    phase = "COMBAT"
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_TEST_TICKS then
        report("FAIL", "timeout", "phase=" .. tostring(phase))
        phase = "FINISHED"
        stop()
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getAnyLoadedPlayer()
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end

    if phase == "WAIT_START" then
        local restored, result = restoreSurvivor(bridge)
        if not restored then
            if string.find(tostring(result), "saved_square_not_loaded", 1, true) ~= nil then
                return
            end
            report("FAIL", "survivor_restore_failed", tostring(result))
            phase = "FINISHED"
            stop()
            return
        end
        print(TAG .. " survivor=" .. tostring(result))

        local persistence = rawget(_G, "KnoxPersistence")
        if persistence.isDevGateComplete("combat") then
            report("SKIP", "already_passed", "next=loot")
            phase = "FINISHED"
            stop()
            return
        end

        local record = persistence.getTestRecord()
        local survivorSquare = squareForRecord(bridge, record)
        startCombat(bridge, survivorSquare, player:getCurrentSquare())
        return
    end

    if phase ~= "COMBAT" then
        return
    end

    if ticks % ZOMBIE_CLEAR_INTERVAL_TICKS == 0 then
        clearLoadedZombies(targetZombie)
    end

    local success, result = pcall(function()
        return bridge:tickTestNpcCombat()
    end)
    if not success or string.find(tostring(result), "COMBAT_FAILED", 1, true) == 1 then
        report("FAIL", "combat_controller", tostring(result))
        phase = "FINISHED"
        stop()
        return
    end

    if string.find(tostring(result), "COMBAT_SUCCEEDED", 1, true) == 1 then
        local persistence = rawget(_G, "KnoxPersistence")
        local saved, record = persistence.captureActiveTestSurvivor()
        if not saved then
            report("FAIL", "post_combat_save_failed", tostring(record))
        else
            persistence.markDevGateComplete("combat")
            report("PASS", "zombie_killed", tostring(result))
        end
        phase = "FINISHED"
        stop()
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(TAG .. " combat-status=" .. tostring(result))
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "combat" then
        return false, "disabled"
    end
    print(TAG .. " START auto=true scenario=combat clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    targetZombie = nil
    lastResult = nil
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    if targetZombie ~= nil and not targetZombie:isDead() then
        removeZombie(targetZombie)
    end
    targetZombie = nil
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxCombatProbe") or {}
_G.KnoxCombatProbe = Probe
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
    if targetZombie ~= nil then
        pcall(function() removeZombie(targetZombie) end)
        targetZombie = nil
    end
    stop()
end
