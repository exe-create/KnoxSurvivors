
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
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivorNeeds"

local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 1800
local STATUS_INTERVAL_TICKS = 60
local NEEDS_GATE_KEY = "needs_consume_v1"
local NEEDS_RELOAD_GATE_KEY = "needs_consume_reload_v1"
local MEDICAL_GATE_KEY = "medical_self_bandage_v1"
local MEDICAL_RELOAD_GATE_KEY = "medical_self_bandage_reload_v1"

local ticks = 0
local phase = "IDLE"
local npc = nil
local activeAction = nil
local activeKind = nil
local actionObserved = false
local drank = false
local ate = false
local initialHunger = 0
local initialThirst = 0
local reportScenario = "needs"
local lastResult = nil
local update

local function report(status, reason, evidence)
    lastResult = {
        scenario = tostring(reportScenario),
        status = tostring(status),
        reason = tostring(reason),
        evidence = tostring(evidence or "none"),
    }
    print(
        TAG
            .. " RESULT scenario=" .. tostring(reportScenario)
            .. " status=" .. tostring(status)
            .. " reason=" .. tostring(reason)
            .. " evidence=" .. tostring(evidence or "none")
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

local function removeLoadedZombies()
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
        zombie:removeFromWorld()
        zombie:removeFromSquare()
        removed = removed + 1
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

local function verifyMedicalReload(bridge, persistence)
    if not persistence.isDevGateComplete(MEDICAL_GATE_KEY)
        or persistence.isDevGateComplete(MEDICAL_RELOAD_GATE_KEY) then
        return true, "not_required"
    end
    local bodyPart = KnoxMedicalActions.mostUrgentInjury(npc)
    if bodyPart == nil or not bodyPart:bandaged() then
        return false, "saved_treatment_not_restored"
    end
    local presentation = tostring(bridge:refreshTestNpcHealthPresentation())
    if string.find(presentation, "HEALTH_PRESENTATION", 1, true) ~= 1 then
        return false, presentation
    end
    persistence.markDevGateComplete(MEDICAL_RELOAD_GATE_KEY)
    print(
        TAG
            .. " CHECK scenario=medical_reload status=PASS injury="
            .. tostring(bodyPart:getType())
            .. " bandaged=true presentation=" .. presentation
    )
    return true, presentation
end

local function ensureTestSupplies()
    local inventory = npc:getInventory()
    if KnoxSurvivorNeeds.findBestFood(npc) == nil then
        inventory:AddItem("Base.Apple")
    end
    local water = KnoxSurvivorNeeds.findBestWater(npc, false)
    if water == nil then
        inventory:AddItem("Base.WaterBottle")
    end
    return KnoxSurvivorNeeds.findBestFood(npc), KnoxSurvivorNeeds.findBestWater(npc, false)
end

local function beginNeedsGate()
    removeLoadedZombies()
    local food, water = ensureTestSupplies()
    if food == nil or water == nil then
        fail(
            "controlled_supplies_unavailable",
            "food=" .. tostring(food ~= nil) .. " water=" .. tostring(water ~= nil)
        )
        return
    end
    local stats = npc:getStats()
    stats:set(CharacterStat.HUNGER, 0.70)
    stats:set(CharacterStat.THIRST, 0.70)
    stats:set(CharacterStat.FATIGUE, 0.20)
    stats:set(CharacterStat.ENDURANCE, 0.80)
    initialHunger = stats:get(CharacterStat.HUNGER)
    initialThirst = stats:get(CharacterStat.THIRST)
    phase = "DECIDING"
    print(
        TAG
            .. " needs-controlled="
            .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(npc))
            .. " food=" .. tostring(food:getFullType())
            .. " water=" .. tostring(water:getFullType())
    )
end

local function finishGate()
    local state = KnoxSurvivorNeeds.snapshot(npc)
    local hungerSatisfied = state.hunger < KnoxSurvivorNeeds.thresholds.hunger
    local thirstSatisfied = state.thirst < KnoxSurvivorNeeds.thresholds.thirst
    if not hungerSatisfied or not thirstSatisfied or not actionObserved then
        fail(
            "required_consumption_result_missing",
            "ate=" .. tostring(ate)
                .. " drank=" .. tostring(drank)
                .. " hungerSatisfied=" .. tostring(hungerSatisfied)
                .. " thirstSatisfied=" .. tostring(thirstSatisfied)
                .. " actionObserved=" .. tostring(actionObserved)
        )
        return
    end
    if state.hunger >= initialHunger or state.thirst >= initialThirst then
        fail(
            "needs_not_reduced",
            KnoxSurvivorNeeds.describe(state)
                .. " initialHunger=" .. tostring(initialHunger)
                .. " initialThirst=" .. tostring(initialThirst)
        )
        return
    end
    local persistence = rawget(_G, "KnoxPersistence")
    local saved, record = persistence.captureActiveTestSurvivor()
    if not saved then
        fail("post_needs_save_failed", tostring(record))
        return
    end
    persistence.markDevGateComplete(NEEDS_GATE_KEY)
    report(
        "PASS",
        "needs_satisfied_and_saved",
        KnoxSurvivorNeeds.describe(state)
            .. " ate=" .. tostring(ate)
            .. " drank=" .. tostring(drank)
            .. " actionObserved=" .. tostring(actionObserved)
            .. " next=needs_reload_then_autonomy"
    )
    phase = "FINISHED"
    stop()
end

local function verifyNeedsReload(persistence)
    reportScenario = "needs_reload"
    local state = KnoxSurvivorNeeds.snapshot(npc)
    if state.hunger >= 0.55 or state.thirst >= 0.55 then
        fail("consumed_needs_not_restored", KnoxSurvivorNeeds.describe(state))
        return
    end
    persistence.markDevGateComplete(NEEDS_RELOAD_GATE_KEY)
    report(
        "PASS",
        "physiology_restored",
        KnoxSurvivorNeeds.describe(state) .. " next=autonomy"
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
        local medicalOk, medicalEvidence = verifyMedicalReload(bridge, persistence)
        if not medicalOk then
            fail("medical_reload_preflight", medicalEvidence)
            return
        end
        if persistence.isDevGateComplete(NEEDS_GATE_KEY) then
            if persistence.isDevGateComplete(NEEDS_RELOAD_GATE_KEY) then
                report("SKIP", "already_passed", "next=autonomy")
                phase = "FINISHED"
                stop()
            else
                verifyNeedsReload(persistence)
            end
            return
        end
        beginNeedsGate()
        return
    end

    if phase == "ACTING" then
        if not npc:getCharacterActions():isEmpty() then
            actionObserved = true
            return
        end
        if activeKind == "drink" then
            drank = npc:getStats():get(CharacterStat.THIRST) < initialThirst
        elseif activeKind == "eat" then
            ate = npc:getStats():get(CharacterStat.HUNGER) < initialHunger
        end
        activeAction = nil
        activeKind = nil
        phase = "DECIDING"
    end

    if phase ~= "DECIDING" then
        return
    end
    local currentState = KnoxSurvivorNeeds.snapshot(npc)
    if currentState.hunger < KnoxSurvivorNeeds.thresholds.hunger
        and currentState.thirst < KnoxSurvivorNeeds.thresholds.thirst then
        finishGate()
        return
    end
    if ate and drank then
        finishGate()
        return
    end

    local decision = KnoxSurvivorNeeds.decide(npc, nil)
    if decision.kind ~= "eat" and decision.kind ~= "drink" then
        fail(
            "unexpected_need_decision",
            "kind=" .. tostring(decision.kind)
                .. " " .. KnoxSurvivorNeeds.describe(decision.state)
        )
        return
    end
    activeAction = KnoxSurvivorNeeds.execute(npc, decision)
    if activeAction == nil then
        fail("need_action_not_queued", tostring(decision.kind))
        return
    end
    activeKind = decision.kind
    actionObserved = actionObserved
        or (activeAction.action ~= nil and npc:getCharacterActions():contains(activeAction.action))
    phase = "ACTING"
    print(
        TAG
            .. " needs-action=QUEUED kind=" .. tostring(activeKind)
            .. " item=" .. tostring(decision.item:getFullType())
            .. " durationTicks=" .. tostring(activeAction.maxTime)
            .. " actionObserved=" .. tostring(actionObserved)
    )

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(TAG .. " needs-status=" .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(npc)))
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "needs" then
        return false, "disabled"
    end
    print(TAG .. " START auto=true scenario=needs clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    activeAction = nil
    activeKind = nil
    actionObserved = false
    drank = false
    ate = false
    lastResult = nil
    reportScenario = "needs"
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    if npc ~= nil and not npc:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(npc)
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxNeedsProbe") or {}
_G.KnoxNeedsProbe = Probe
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
    if npc ~= nil and not npc:getCharacterActions():isEmpty() then
        pcall(function() ISTimedActionQueue.clear(npc) end)
    end
    stop()
end
