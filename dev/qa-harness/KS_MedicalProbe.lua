
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
require "TimedActions/ISApplyBandage"
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivalMedical"
require "KS_SurvivorMedicalActions"

local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 900
local STATUS_INTERVAL_TICKS = 60
local MEDICAL_GATE_KEY = "medical_self_bandage_v1"
local MEDICAL_RELOAD_GATE_KEY = "medical_self_bandage_reload_v1"

local ticks = 0
local phase = "IDLE"
local npc = nil
local bodyPart = nil
local bandage = nil
local action = nil
local actionObserved = false
local reportScenario = "medical"
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
            .. " RESULT scenario=" .. tostring(reportScenario) .. " status="
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

local function mostUrgentInjury(character)
    return KnoxMedicalActions.mostUrgentInjury(character)
end

local function fail(reason, evidence)
    report("FAIL", reason, evidence)
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
        if not persistence.isDevGateComplete("health_reload_v1") then
            fail("health_reload_prerequisite_missing", "run_health_scenario_first=true")
            return
        end

        bodyPart = mostUrgentInjury(npc)
        if bodyPart == nil then
            fail("no_saved_injury", "health=" .. tostring(bridge:getTestNpcHealth()))
            return
        end
        if persistence.isDevGateComplete(MEDICAL_GATE_KEY) then
            reportScenario = "medical_reload"
            if persistence.isDevGateComplete(MEDICAL_RELOAD_GATE_KEY) then
                report("SKIP", "already_passed", "next=medical_supplies")
                phase = "FINISHED"
                stop()
                return
            end
            if not bodyPart:bandaged() then
                fail(
                    "saved_treatment_not_restored",
                    "injury=" .. tostring(bodyPart:getType())
                        .. " bandaged=" .. tostring(bodyPart:bandaged())
                )
                return
            end
            local presentation = tostring(bridge:refreshTestNpcHealthPresentation())
            if string.find(presentation, "HEALTH_PRESENTATION", 1, true) ~= 1 then
                fail("bandage_visual_restore_failed", presentation)
                return
            end
            persistence.markDevGateComplete(MEDICAL_RELOAD_GATE_KEY)
            report(
                "PASS",
                "treatment_restored",
                "injury=" .. tostring(bodyPart:getType())
                    .. " bandaged=" .. tostring(bodyPart:bandaged())
                    .. " health=" .. tostring(bridge:getTestNpcHealth())
                    .. " presentation=" .. presentation
                    .. " next=medical_supplies"
            )
            phase = "FINISHED"
            stop()
            return
        end

        bandage = KnoxMedicalSupplies.findTreatment(npc)
        if bandage == nil then
            local plan = KnoxMedicalSupplies.plan(npc, 8)
            fail(
                "no_treatment_item_in_inventory",
                "fallbackPlan=" .. tostring(plan.kind)
                    .. " source=" .. tostring(plan.item and plan.item:getFullType() or "none")
            )
            return
        end
        action = KnoxMedicalActions.queueBandage(npc, bandage, bodyPart)
        actionObserved = action.action ~= nil and npc:getCharacterActions():contains(action.action)
        print(
            TAG
                .. " medical-action=QUEUED injury="
                .. tostring(bodyPart:getType())
                .. " item="
                .. tostring(bandage:getFullType())
                .. " durationTicks="
                .. tostring(action.maxTime)
                .. " actionObserved="
                .. tostring(actionObserved)
                .. " animationRequested="
                .. tostring(action.knoxBandageAnimationRequested == true)
        )
        phase = "TREATING"
        return
    end

    if phase ~= "TREATING" then
        return
    end

    if not npc:getCharacterActions():isEmpty() then
        actionObserved = true
    end
    if bodyPart:bandaged() and not npc:getInventory():contains(bandage) then
        if not actionObserved then
            fail("treatment_without_timed_action", tostring(bodyPart:getType()))
            return
        end
        local presentation = tostring(bridge:refreshTestNpcHealthPresentation())
        if string.find(presentation, "HEALTH_PRESENTATION", 1, true) ~= 1 then
            fail("bandage_visual_failed", presentation)
            return
        end
        local persistence = rawget(_G, "KnoxPersistence")
        local saved, record = persistence.captureActiveTestSurvivor()
        if not saved then
            fail("post_medical_save_failed", tostring(record))
            return
        end
        persistence.markDevGateComplete("medical")
        persistence.markDevGateComplete(MEDICAL_GATE_KEY)
        report(
            "PASS",
            "self_bandaged_and_saved",
            "injury=" .. tostring(bodyPart:getType())
                .. " actionObserved=" .. tostring(actionObserved)
                .. " animationRequested="
                .. tostring(action.knoxBandageAnimationRequested == true)
                .. " bandaged=" .. tostring(bodyPart:bandaged())
                .. " bleeding=" .. tostring(bodyPart:bleeding())
                .. " inventoryItems=" .. tostring(npc:getInventory():getItems():size())
                .. " presentation=" .. presentation
                .. " next=medical_reload"
        )
        phase = "FINISHED"
        stop()
        return
    end

    if action ~= nil
        and not ISTimedActionQueue.hasAction(action)
        and npc:getCharacterActions():isEmpty() then
        fail(
            "medical_action_ended_without_bandage",
            "bandaged=" .. tostring(bodyPart:bandaged())
                .. " inventoryContainsItem=" .. tostring(npc:getInventory():contains(bandage))
        )
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(
            TAG
                .. " medical-status=TREATING actionObserved="
                .. tostring(actionObserved)
                .. " bandaged="
                .. tostring(bodyPart:bandaged())
        )
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "medical" then
        return false, "disabled"
    end
    print(TAG .. " START auto=true scenario=medical clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    bodyPart = nil
    bandage = nil
    action = nil
    actionObserved = false
    reportScenario = "medical"
    lastResult = nil
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    if npc ~= nil and action ~= nil and ISTimedActionQueue.hasAction(action) then
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

local Probe = rawget(_G, "KnoxMedicalProbe") or {}
_G.KnoxMedicalProbe = Probe
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
    if npc ~= nil and action ~= nil and ISTimedActionQueue.hasAction(action) then
        pcall(function() ISTimedActionQueue.clear(npc) end)
    end
    stop()
end
