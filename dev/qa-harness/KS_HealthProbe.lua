
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
local ZOMBIE_CONTROL_INTERVAL_TICKS = 15
local HEALTH_GATE_KEY = "health_injury_v1"
local HEALTH_RELOAD_GATE_KEY = "health_reload_v1"

local ticks = 0
local phase = "IDLE"
local npc = nil
local targetZombie = nil
local initialHealth = nil
local reportScenario = "health"
local lastResult = nil
local replacements = 0
local MAX_REPLACEMENTS = 5
local stashedPrimary, stashedSecondary = nil, nil
local update
local pacifySurvivor, releasePacified

local function report(status, reason, evidence)
    lastResult = {
        scenario = tostring(reportScenario),
        status = tostring(status),
        reason = tostring(reason),
        evidence = tostring(evidence or "none"),
    }
    print(
        TAG
            .. " RESULT scenario="
            .. tostring(reportScenario)
            .. " status="
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
    zombie:setUseless(true)
    zombie:setCanWalk(false)
    zombie:setTarget(nil)
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

local function findZombieSquare(origin)
    local cell = getCell()
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    }
    for _, direction in ipairs(directions) do
        local square = cell:getGridSquare(
            origin:getX() + direction[1],
            origin:getY() + direction[2],
            origin:getZ()
        )
        if square ~= nil and square:canStand() and not origin:isBlockedTo(square) then
            return square
        end
    end
    return nil
end

-- The injury probe needs the zombie to land a hit, but the test survivor
-- fights back with her baseball bat and kills it first. Disarm her for the
-- probe so she stands there and the zombie gets its chance. Hands are
-- restored on every exit path below.
local function disarmNpc()
    if npc == nil then return end
    pcall(function() stashedPrimary = npc:getPrimaryHandItem() end)
    pcall(function() stashedSecondary = npc:getSecondaryHandItem() end)
    pcall(function() npc:setPrimaryHandItem(nil) end)
    pcall(function() npc:setSecondaryHandItem(nil) end)
end

local function restoreHands()
    if npc == nil then
        stashedPrimary, stashedSecondary = nil, nil
        return
    end
    -- Only put back what is not already held: the run may have ended with
    -- the survivor holding something else (or nothing) through no fault here.
    pcall(function()
        if stashedPrimary ~= nil and npc:getPrimaryHandItem() == nil then
            npc:setPrimaryHandItem(stashedPrimary)
        end
    end)
    pcall(function()
        if stashedSecondary ~= nil and npc:getSecondaryHandItem() == nil then
            npc:setSecondaryHandItem(stashedSecondary)
        end
    end)
    stashedPrimary, stashedSecondary = nil, nil
end

local function fail(reason, evidence)
    releasePacified()
    restoreHands()
    if npc ~= nil then
        -- Hand back a vulnerable survivor. Leaving ZombiesDontAttack(true)
        -- here produced "swarmed but invincible" NPCs that persisted into
        -- normal saves when the test survivor was captured.
        pcall(function() npc:setZombiesDontAttack(false) end)
    end
    if targetZombie ~= nil then
        removeZombie(targetZombie)
        targetZombie = nil
    end
    report("FAIL", reason, evidence)
    phase = "FINISHED"
    stop()
end

local function startAttack(bridge)
    local prepared = tostring(bridge:prepareTestNpcHealthGate())
    if string.find(prepared, "HEALTH_GATE_READY", 1, true) ~= 1 then
        fail("health_gate_prepare_failed", prepared)
        return
    end
    initialHealth = bridge:getTestNpcHealth()
    local zombieSquare = findZombieSquare(npc:getCurrentSquare())
    if zombieSquare == nil then
        fail("no_adjacent_zombie_square", "stand_with_survivor_in_open_area=true")
        return
    end
    local zombies = addZombiesInOutfit(
        zombieSquare:getX(), zombieSquare:getY(), zombieSquare:getZ(), 1, nil, nil
    )
    targetZombie = zombies ~= nil and zombies:size() > 0 and zombies:get(0) or nil
    if targetZombie == nil then
        fail("test_zombie_spawn_failed", "square=" .. tostring(zombieSquare))
        return
    end
    local directed = tostring(bridge:directTestZombieAtNpc(targetZombie))
    if string.find(directed, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
        fail("zombie_target_failed", directed)
        return
    end
    -- Stand still and take the hit: disarm before the zombie arrives so
    -- autonomy combat has nothing to swing with, and hold her decision
    -- brain so she neither roams off nor punches back.
    disarmNpc()
    pacifySurvivor()
    print(
        TAG
            .. " health-attack=STARTED initialHealth="
            .. tostring(initialHealth)
            .. " inventoryItems="
            .. tostring(npc:getInventory():getItems():size())
            .. " zombieSquare="
            .. tostring(zombieSquare:getX())
            .. ","
            .. tostring(zombieSquare:getY())
            .. " disarmed=true"
    )
    phase = "AWAITING_NATIVE_DAMAGE"
end

-- Bare hands still kill: her autonomy brain must also stand down, or every
-- attacker dies to punches before it bites. Suppression holds as long as the
-- probe ticks; every exit path releases her back to normal duty.
local pacifiedController = nil

pacifySurvivor = function()
    if npc == nil then return end
    if pacifiedController == nil then
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        local okStatus, status = pcall(function()
            return autonomy ~= nil and autonomy.status ~= nil and autonomy.status() or nil
        end)
        local controllers = okStatus and status ~= nil and status.controllers or nil
        if controllers ~= nil then
            for _, controller in pairs(controllers) do
                if controller ~= nil and controller.character == npc then
                    pacifiedController = controller
                    break
                end
            end
        end
    end
    if pacifiedController ~= nil then
        -- One-time settle: stop any fight or walk already in flight so the
        -- Java-driven zombie meets a stationary target.
        if pacifiedController.settlingProbe ~= true then
            pacifiedController.settlingProbe = true
            local captiveBridge = pacifiedController.bridge
            if captiveBridge ~= nil then
                if captiveBridge.cancelNpcMove ~= nil then
                    pcall(function() captiveBridge:cancelNpcMove(pacifiedController.id) end)
                end
                if captiveBridge.resetNpcCombat ~= nil then
                    pcall(function() captiveBridge:resetNpcCombat(pacifiedController.id) end)
                end
            end
            pacifiedController.state = "IDLE"
            pacifiedController.activeDecision = nil
        end
        pcall(function() pacifiedController.nextThink = ticks + 100000 end)
        pcall(function() pacifiedController.nextThreatScan = ticks + 100000 end)
    end
end

releasePacified = function()
    if pacifiedController ~= nil then
        pcall(function() pacifiedController.nextThink = ticks end)
        pcall(function() pacifiedController.nextThreatScan = ticks end)
        pacifiedController.settlingProbe = nil
        pacifiedController = nil
    end
end

-- She may still punch it to death bare-handed. Respawn a fresh attacker a
-- bounded number of times instead of waiting forever on a corpse.
local function replaceDeadZombie(bridge)
    local dead = targetZombie == nil
    if not dead then
        local okDead, isDead = pcall(function() return targetZombie:isDead() end)
        dead = not okDead or isDead == true
    end
    if not dead then return true end
    targetZombie = nil
    if replacements >= MAX_REPLACEMENTS then
        return false
    end
    local square = npc ~= nil and findZombieSquare(npc:getCurrentSquare()) or nil
    if square == nil then return false end
    local spawned = addZombiesInOutfit(
        square:getX(), square:getY(), square:getZ(), 1, nil, nil
    )
    local fresh = spawned ~= nil and spawned:size() > 0 and spawned:get(0) or nil
    if fresh == nil then return false end
    local directed = tostring(bridge:directTestZombieAtNpc(fresh))
    if string.find(directed, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
        pcall(function()
            fresh:setUseless(true)
            fresh:removeFromWorld()
            fresh:removeFromSquare()
        end)
        return false
    end
    targetZombie = fresh
    replacements = replacements + 1
    print(TAG .. " zombie-replaced replacement=" .. tostring(replacements)
        .. "/" .. tostring(MAX_REPLACEMENTS))
    return true
end

local function finishReceivedDamage(bridge, receivedHealth, receivedInjuries, receivedBleeding)
    removeZombie(targetZombie)
    targetZombie = nil
    restoreHands()
    releasePacified()
    local normalized = tostring(bridge:normalizeTestNpcMinorInjury())
    if string.find(normalized, "CONTROLLED_INJURY", 1, true) ~= 1 then
        fail("minor_injury_normalization_failed", normalized)
        return
    end
    local controlledHealth = bridge:getTestNpcHealth()
    local controlledInjuries = bridge:getTestNpcInjuredPartCount()
    local controlledBleeding = bridge:getTestNpcBleedingPartCount()
    if controlledHealth >= initialHealth or controlledInjuries < 1 or controlledBleeding < 1 then
        fail("controlled_injury_missing", normalized)
        return
    end

    local persistence = rawget(_G, "KnoxPersistence")
    local saved, record = persistence.captureActiveTestSurvivor()
    if not saved then
        fail("post_injury_save_failed", tostring(record))
        return
    end
    persistence.markDevGateComplete("health")
    persistence.markDevGateComplete(HEALTH_GATE_KEY)
    report(
        "PASS",
        "native_damage_received_and_injury_saved",
        "nativeHealthBefore=" .. tostring(initialHealth)
            .. " nativeHealthAfter=" .. tostring(receivedHealth)
            .. " nativeInjuredParts=" .. tostring(receivedInjuries)
            .. " nativeBleedingParts=" .. tostring(receivedBleeding)
            .. " controlledHealth=" .. tostring(controlledHealth)
            .. " controlledInjuredParts=" .. tostring(controlledInjuries)
            .. " controlledBleedingParts=" .. tostring(controlledBleeding)
            .. " injury=ForeArm_L wound=scratch"
            .. " inventoryItems=" .. tostring(npc:getInventory():getItems():size())
            .. " next=health_reload"
    )
    phase = "FINISHED"
    stop()
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_TEST_TICKS then
        fail("timeout", "phase=" .. tostring(phase))
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
            fail("survivor_restore_failed", tostring(result))
            return
        end
        npc = bridge:getTestNpcCharacterForAction()
        if npc == nil then
            fail("npc_character_unavailable", tostring(result))
            return
        end
        print(TAG .. " survivor=" .. tostring(result))

        local persistence = rawget(_G, "KnoxPersistence")
        if persistence.isDevGateComplete(HEALTH_GATE_KEY) then
            reportScenario = "health_reload"
            if persistence.isDevGateComplete(HEALTH_RELOAD_GATE_KEY) then
                report("SKIP", "already_passed", "next=medical")
                phase = "FINISHED"
                stop()
                return
            end

            local restoredHealth = bridge:getTestNpcHealth()
            local restoredInjuries = bridge:getTestNpcInjuredPartCount()
            local restoredBleeding = bridge:getTestNpcBleedingPartCount()
            local restoredItems = npc:getInventory():getItems():size()
            if restoredHealth >= 100 or restoredInjuries < 1 or restoredBleeding < 1 then
                report(
                    "FAIL",
                    "saved_injury_not_restored",
                    "health=" .. tostring(restoredHealth)
                        .. " injuredParts=" .. tostring(restoredInjuries)
                        .. " bleedingParts=" .. tostring(restoredBleeding)
                        .. " inventoryItems=" .. tostring(restoredItems)
                )
                phase = "FINISHED"
                stop()
                return
            end
            if restoredItems < 11 then
                report(
                    "FAIL",
                    "post_loot_inventory_not_restored",
                    "inventoryItems=" .. tostring(restoredItems) .. " expectedAtLeast=11"
                )
                phase = "FINISHED"
                stop()
                return
            end
            persistence.markDevGateComplete(HEALTH_RELOAD_GATE_KEY)
            report(
                "PASS",
                "injury_and_inventory_restored",
                "health=" .. tostring(restoredHealth)
                    .. " injuredParts=" .. tostring(restoredInjuries)
                    .. " bleedingParts=" .. tostring(restoredBleeding)
                    .. " inventoryItems=" .. tostring(restoredItems)
                    .. " next=medical"
            )
            phase = "FINISHED"
            stop()
            return
        end
        clearLoadedZombies(nil)
        startAttack(bridge)
        return
    end

    if phase ~= "AWAITING_NATIVE_DAMAGE" then
        return
    end

    -- She killed it before it landed a hit: bring a fresh one, bounded.
    if not replaceDeadZombie(bridge) then
        fail("test_zombie_killed_without_damage",
            "replacements=" .. tostring(replacements))
        return
    end

    if ticks % ZOMBIE_CONTROL_INTERVAL_TICKS == 0 then
        clearLoadedZombies(targetZombie)
        local directed = tostring(bridge:directTestZombieAtNpc(targetZombie))
        if string.find(directed, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
            fail("zombie_retarget_failed", directed)
            return
        end
    end

    local currentHealth = bridge:getTestNpcHealth()
    local injuredParts = bridge:getTestNpcInjuredPartCount()
    local bleedingParts = bridge:getTestNpcBleedingPartCount()
    if currentHealth < initialHealth - 0.01 or injuredParts > 0 or bleedingParts > 0 then
        finishReceivedDamage(bridge, currentHealth, injuredParts, bleedingParts)
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        pacifySurvivor()
        local attacking, onTarget = nil, nil
        pcall(function() attacking = targetZombie:isAttacking() end)
        pcall(function() onTarget = targetZombie:getTarget() == npc end)
        print(
            TAG
                .. " health-status=AWAITING_NATIVE_DAMAGE health="
                .. tostring(currentHealth)
                .. " zombieAttacking="
                .. tostring(attacking)
                .. " targetIsNpc="
                .. tostring(onTarget)
                .. " replacements="
                .. tostring(replacements)
        )
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "health" then
        return false, "disabled"
    end
    print(TAG .. " START auto=true scenario=health clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    targetZombie = nil
    initialHealth = nil
    reportScenario = "health"
    lastResult = nil
    replacements = 0
    stashedPrimary, stashedSecondary = nil, nil
    pacifiedController = nil
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    releasePacified()
    restoreHands()
    if npc ~= nil then
        -- Same handoff rule as fail(): menu exit returns the NPC to normal
        -- gameplay, so it must be zombie-vulnerable.
        pcall(function() npc:setZombiesDontAttack(false) end)
    end
    if targetZombie ~= nil then
        removeZombie(targetZombie)
    end
    targetZombie = nil
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxHealthProbe") or {}
_G.KnoxHealthProbe = Probe
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
    releasePacified()
    restoreHands()
    if npc ~= nil then pcall(function() npc:setZombiesDontAttack(false) end) end
    stop()
end
