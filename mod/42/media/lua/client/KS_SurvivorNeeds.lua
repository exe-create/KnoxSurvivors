require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFromBottle"
require "TimedActions/ISTakeWaterAction"
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivalMedical"
require "KS_SurvivorMedicalActions"
require "KS_SurvivorInventoryActions"
pcall(function() require "KS_DebugLog" end)

local Needs = rawget(_G, "KnoxSurvivorNeeds") or {}
_G.KnoxSurvivorNeeds = Needs

Needs.thresholds = {
    bleeding = 1,
    -- Needs are normalized 0..1 in Build 42. Starting recovery just below
    -- half-full prevents workers from waiting until a task has already made
    -- them visibly desperate, while the completion checks still use hysteresis.
    thirst = 0.45,
    hunger = 0.45,
    lowEndurance = 0.45,
    fatigue = 0.72,
}

local NEED_CHANGE_EPSILON = 0.001

-- Throttled self-care telemetry (1st + every 10th per survivor/kind):
-- queue rejections and sleep transitions are rare enough to always matter,
-- successful meals are frequent but confirm the loop works.
local function diagNeed(character, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log == nil or log.log == nil then return end
    local id = "unknown"
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.idForCharacter ~= nil then
        local ok, found = pcall(function() return runtime.idForCharacter(character) end)
        if ok and found ~= nil then id = tostring(found) end
    end
    pcall(function() log.log("needs", id, event, details) end)
end

local function actionAccepted(character, action)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    return action ~= nil and queue:indexOf(action) ~= -1
end

local function walkInventory(container, visitor)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item, container)
        if item:IsInventoryContainer() then
            walkInventory(item:getInventory(), visitor)
        end
    end
end

local function isSafeFood(item)
    if item == nil or not item:IsFood() or item:getHungerChange() >= -0.01 then
        return false
    end
    if item:isRotten() or item:isPoison() or item:getPoisonPower() > 0 then
        return false
    end
    if item:isbDangerousUncooked() and not item:isCooked() then
        return false
    end
    return true
end

local function foodScore(item)
    local hunger = math.abs(item:getHungerChange())
    local unhappinessPenalty = math.max(0, item:getUnhappyChange()) / 100
    return hunger - unhappinessPenalty
end

local function waterState(item)
    if item == nil or item:getFluidContainer() == nil then
        return nil
    end
    local fluid = item:getFluidContainer()
    if fluid:isEmpty() or not fluid:isWaterSource() then
        return nil
    end
    -- Unknown fluid state is not potable by default. Native drinking checks
    -- this same tag and can apply sickness/poison, so a missing enum or failed
    -- accessor must not be treated as clean water.
    local success, result = pcall(function()
        if Fluid == nil or Fluid.TaintedWater == nil then return nil end
        return fluid:contains(Fluid.TaintedWater)
    end)
    if not success or type(result) ~= "boolean" then return nil end
    local tainted = result
    return { item = item, tainted = tainted, amount = fluid:getAmount() }
end

function Needs.findBestFood(character)
    local best = nil
    local bestScore = -math.huge
    walkInventory(character:getInventory(), function(item)
        if isSafeFood(item) then
            local score = foodScore(item)
            if score > bestScore then
                best = item
                bestScore = score
            end
        end
    end)
    return best
end

function Needs.isSafeFood(item)
    return isSafeFood(item)
end

function Needs.isWaterItem(item, allowTainted)
    local state = waterState(item)
    return state ~= nil and (allowTainted or not state.tainted)
end

-- Loaded IsoObjects expose the same real fluid/taint facts used by vanilla's
-- ISTakeWaterAction. Missing accessors and unreadable taint fail closed.
function Needs.waterSourceState(source)
    if source == nil then return nil end
    local ok, hasFluid, amount, tainted = pcall(function()
        if source.hasFluid == nil or source.getFluidAmount == nil
            or source.isTaintedWater == nil then return nil, nil, nil end
        return source:hasFluid(), source:getFluidAmount(), source:isTaintedWater()
    end)
    amount = ok and tonumber(amount) or nil
    if not ok or type(hasFluid) ~= "boolean" or amount == nil or amount < 0
        or type(tainted) ~= "boolean" then return nil end
    return { source = source, amount = amount,
        available = hasFluid and amount > 0, tainted = tainted }
end

-- Smoking runs through the same native eat action as food: vanilla
-- ISEatFoodAction special-cases Base.Cigarettes, so stress/unhappiness
-- relief, sounds and timing are engine-owned, exactly like the player.
function Needs.findSmokeItem(character)
    if character == nil or character.getInventory == nil then return nil end
    local inventory = character:getInventory()
    if inventory == nil or inventory.getItems == nil then return nil end
    local found = nil
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or items == nil then return nil end
    local okSize, count = pcall(function() return items:size() end)
    for index = 0, (okSize and tonumber(count) or 0) - 1 do
        local okItem, item = pcall(function() return items:get(index) end)
        if okItem and item ~= nil and item.getFullType ~= nil then
            local okType, fullType = pcall(function() return item:getFullType() end)
            local name = okType and tostring(fullType or "") or ""
            if name == "Base.Cigarettes" or string.find(name, "Cigar", 1, true) then
                found = item
                break
            end
        end
    end
    return found
end

function Needs.smokeMotive(character)
    if character == nil then return false end
    local smoker = false
    pcall(function()
        local traits = character.getTraits and character:getTraits()
        if traits ~= nil and traits.contains ~= nil then
            smoker = traits:contains("Smoker") == true
        end
    end)
    if smoker then return true end
    local stressed, unhappy = 0, 0
    pcall(function()
        local moodles = character:getMoodles()
        if moodles ~= nil and MoodleType ~= nil then
            stressed = tonumber(moodles:getMoodleLevel(MoodleType.STRESS)) or 0
            unhappy = tonumber(moodles:getMoodleLevel(MoodleType.UNHAPPY)) or 0
        end
    end)
    return stressed >= 2 or unhappy >= 2
end

function Needs.findBestWater(character, allowTainted)
    local best = nil
    walkInventory(character:getInventory(), function(item)
        local state = waterState(item)
        if state ~= nil and (allowTainted or not state.tainted) then
            if best == nil
                or (best.tainted and not state.tainted)
                or (best.tainted == state.tainted and state.amount > best.amount) then
                best = state
            end
        end
    end)
    return best ~= nil and best.item or nil, best ~= nil and best.tainted or false
end

function Needs.snapshot(character)
    local stats = character:getStats()
    local bodyDamage = character:getBodyDamage()
    -- Pain is exposed by current Build 42 body damage, but older game builds
    -- and a few test doubles do not provide the accessor.  Keep it optional:
    -- native body state remains the source of truth and an unavailable value
    -- must never be reported as painless.
    local pain = nil
    if bodyDamage ~= nil and bodyDamage.getPain ~= nil then
        local ok, value = pcall(function() return bodyDamage:getPain() end)
        if ok and tonumber(value) ~= nil then pain = tonumber(value) end
    end
    return {
        hunger = stats:get(CharacterStat.HUNGER),
        thirst = stats:get(CharacterStat.THIRST),
        fatigue = stats:get(CharacterStat.FATIGUE),
        endurance = stats:get(CharacterStat.ENDURANCE),
        bleedingParts = bodyDamage:getNumPartsBleeding(),
        health = bodyDamage:getHealth(),
        pain = pain,
    }
end

-- Dialogue and durable intents must use the same native stat boundary as the
-- decision planner. This prevents an old `find_food` state from producing a
-- fresh hunger callout after the survivor has already recovered.
function Needs.isNeedCurrent(character, kind)
    if character == nil or kind == nil then return false end
    local success, snapshot = pcall(Needs.snapshot, character)
    if not success or snapshot == nil then return false end
    if kind == "find_food" or kind == "eat" then
        return (tonumber(snapshot.hunger) or 0) >= Needs.thresholds.hunger
    end
    if kind == "find_water" or kind == "drink" then
        return (tonumber(snapshot.thirst) or 0) >= Needs.thresholds.thirst
    end
    if kind == "find_medical" or kind == "bandage"
        or kind == "improvise_medical" then
        return (tonumber(snapshot.bleedingParts) or 0) >= Needs.thresholds.bleeding
    end
    if kind == "rest" then
        return (tonumber(snapshot.endurance) or 1) <= Needs.thresholds.lowEndurance
    end
    if kind == "sleep" then
        return (tonumber(snapshot.fatigue) or 0) >= Needs.thresholds.fatigue
    end
    -- Unknown or stale intents must not keep producing player-facing need
    -- callouts.  The planner owns the supported kinds above; an old save or
    -- interrupted action can otherwise make a survivor claim a need forever.
    return false
end

function Needs.sleepRequired()
    if not isClient() then
        return true
    end
    local options = getServerOptions()
    return options:getBoolean("SleepAllowed") and options:getBoolean("SleepNeeded")
end

function Needs.describe(snapshot)
    return "hunger=" .. tostring(snapshot.hunger)
        .. " thirst=" .. tostring(snapshot.thirst)
        .. " fatigue=" .. tostring(snapshot.fatigue)
        .. " endurance=" .. tostring(snapshot.endurance)
        .. " bleedingParts=" .. tostring(snapshot.bleedingParts)
        .. " health=" .. tostring(snapshot.health)
        .. " pain=" .. tostring(snapshot.pain)
end

function Needs.decide(character, threat)
    local state = Needs.snapshot(character)
    if threat ~= nil then
        return { kind = "fight", target = threat, state = state }
    end
    if state.bleedingParts >= Needs.thresholds.bleeding then
        local injury = KnoxMedicalActions.mostUrgentInjury(character)
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        if treatment ~= nil then
            return {
                kind = "bandage",
                item = treatment,
                bodyPart = injury,
                state = state,
            }
        end
        local supplyPlan = KnoxMedicalSupplies.plan(character, 8)
        local canImprovise = supplyPlan.kind == "rip_owned_sheet"
            or supplyPlan.kind == "rip_owned_spare_clothing"
        return {
            kind = canImprovise and "improvise_medical" or "find_medical",
            supplyPlan = supplyPlan,
            state = state,
        }
    end
    if state.thirst >= Needs.thresholds.thirst then
        local water, tainted = Needs.findBestWater(character, state.thirst >= 0.90)
        return {
            kind = water ~= nil and "drink" or "find_water",
            item = water,
            tainted = tainted,
            state = state,
        }
    end
    if state.hunger >= Needs.thresholds.hunger then
        local food = Needs.findBestFood(character)
        return {
            kind = food ~= nil and "eat" or "find_food",
            item = food,
            state = state,
        }
    end
    if state.endurance <= Needs.thresholds.lowEndurance then
        return { kind = "rest", state = state }
    end
    if state.fatigue >= Needs.thresholds.fatigue and Needs.sleepRequired() then
        return { kind = "sleep", state = state }
    end
    return { kind = "roam", state = state }
end

function Needs.execute(character, decision)
    if decision == nil then
        return nil, "missing_decision"
    end
    -- Report queue outcomes (success confirms the loop; rejections are the
    -- usual "won't eat/drink" evidence). Throttled per survivor/kind.
    local function report(action, result, intent)
        local okAction = action ~= nil and action ~= false
        local itemType = nil
        pcall(function()
            local item = decision.item
                or (intent ~= nil and intent.item)
                or (decision.supplyPlan ~= nil and decision.supplyPlan.item)
            if item ~= nil and item.getFullType ~= nil then
                itemType = item:getFullType()
            end
        end)
        diagNeed(character, okAction and "need_action_queued" or "need_action_failed", {
            kind = tostring(decision.kind),
            result = tostring(result),
            item = itemType,
        })
        return action, result, intent
    end
    if decision.kind == "bandage" then
        local action, result = KnoxMedicalActions.queueBandage(
            character,
            decision.item,
            decision.bodyPart
        )
        return report(action, result, {
            kind = "bandage",
            before = decision.state,
            item = decision.item,
            bodyPart = decision.bodyPart,
        })
    end
    if decision.kind == "drink" or decision.kind == "eat" then
        local inventory, source = character:getInventory(), nil
        walkInventory(inventory, function(item, container)
            if item == decision.item then source = container end
        end)
        if source == nil then
            diagNeed(character, "need_action_failed", {
                kind = tostring(decision.kind), result = "supply_no_longer_carried",
            })
            return nil, "supply_no_longer_carried"
        end
        if source ~= inventory then
            -- Native eating validates main-inventory ownership. Retrieving a
            -- bagged meal is a separate verified action, never consumption.
            local action, reason = KnoxInventoryActions.queueTransfer(
                character, decision.item, source, inventory)
            if not actionAccepted(character, action) then
                diagNeed(character, "need_action_failed", {
                    kind = tostring(decision.kind), result = "supply_transfer_rejected",
                })
                return nil, "supply_transfer_rejected"
            end
            return report(action, reason, { kind = "prepare_supply", needKind = decision.kind,
                before = decision.state, item = decision.item })
        end
    end
    if decision.kind == "drink" then
        local thirst = decision.state.thirst
        local uses = math.max(1, math.ceil(math.max(0, thirst - 0.15) / 0.1))
        local action = ISDrinkFromBottle:new(character, decision.item, uses)
        ISTimedActionQueue.add(action)
        if not actionAccepted(character, action) then
            diagNeed(character, "need_action_failed", {
                kind = "drink", result = "drink_queue_rejected",
            })
            return nil, "drink_queue_rejected"
        end
        return report(action, "queued_drink", {
            kind = "drink",
            before = decision.state,
            item = decision.item,
        })
    end
    if decision.kind == "drink_world" then
        local sourceState = Needs.waterSourceState(decision.source)
        if sourceState == nil or not sourceState.available then
            return report(nil, "water_source_unavailable")
        end
        if sourceState.tainted and decision.state.thirst < 0.90 then
            return report(nil, "tainted_water_not_emergency_eligible")
        end
        -- Vanilla rejects this action when inventory is full even for direct
        -- drinking. Do not make room or bypass that native check.
        local fullOk, full = pcall(function() return character:hasFullInventory() end)
        if fullOk and full == true then
            return report(nil, "native_water_action_refused_full_inventory")
        end
        local action = ISTakeWaterAction:new(
            character, nil, decision.source, sourceState.tainted)
        ISTimedActionQueue.add(action)
        if not actionAccepted(character, action) then
            return report(nil, "native_water_action_queue_rejected")
        end
        return report(action, "queued_native_water_drink", {
            kind = "drink_world",
            before = decision.state,
            source = decision.source,
            sourceAmount = sourceState.amount,
            tainted = sourceState.tainted,
        })
    end
    if decision.kind == "eat" then
        local benefit = math.max(0.01, math.abs(decision.item:getHungerChange()))
        local percentage = math.max(
            0.25,
            math.min(1.0, math.max(0, decision.state.hunger - 0.15) / benefit)
        )
        local action = ISEatFoodAction:new(character, decision.item, percentage)
        ISTimedActionQueue.add(action)
        if not actionAccepted(character, action) then
            diagNeed(character, "need_action_failed", {
                kind = "eat", result = "eat_queue_rejected",
            })
            return nil, "eat_queue_rejected"
        end
        return report(action, "queued_eat percentage=" .. tostring(percentage), {
            kind = "eat",
            before = decision.state,
            item = decision.item,
        })
    end
    if decision.kind == "improvise_medical" then
        local action, result = KnoxMedicalSupplies.queueImprovisation(
            character,
            decision.supplyPlan
        )
        return report(action, result, {
            kind = "improvise_medical",
            before = decision.state,
            item = decision.supplyPlan ~= nil and decision.supplyPlan.item or nil,
        })
    end
    if decision.kind == "smoke" then
        local smoke = decision.item or Needs.findSmokeItem(character)
        if smoke == nil then
            diagNeed(character, "need_action_failed", {
                kind = "smoke", result = "no_smoke_carried",
            })
            return nil, "no_smoke_carried"
        end
        local smokeAction = ISEatFoodAction:new(character, smoke, 1.0)
        ISTimedActionQueue.add(smokeAction)
        if not actionAccepted(character, smokeAction) then
            diagNeed(character, "need_action_failed", {
                kind = "smoke", result = "smoke_queue_rejected",
            })
            return nil, "smoke_queue_rejected"
        end
        return report(smokeAction, "queued_smoke", {
            kind = "smoke",
            before = decision.state,
            item = smoke,
        })
    end
    diagNeed(character, "need_action_failed", {
        kind = tostring(decision.kind), result = "decision_requires_world_action",
    })
    return nil, "decision_requires_world_action=" .. tostring(decision.kind)
end

-- An empty timed-action queue proves only that native ownership ended. These
-- checks prove that the authoritative game state actually changed before the
-- controller records self-care as successful.
function Needs.verify(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_intent"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "prepare_supply" then
        return character:getInventory():contains(intent.item), "supply_main_inventory"
    end
    if intent.kind == "eat" then
        return after.hunger < intent.before.hunger - NEED_CHANGE_EPSILON,
            "hunger=" .. tostring(intent.before.hunger) .. "->" .. tostring(after.hunger)
    end
    if intent.kind == "drink" then
        return after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON,
            "thirst=" .. tostring(intent.before.thirst) .. "->" .. tostring(after.thirst)
    end
    if intent.kind == "drink_world" then
        local sourceState = Needs.waterSourceState(intent.source)
        local thirstChanged = after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON
        local sourceChanged = sourceState ~= nil
            and sourceState.amount < intent.sourceAmount - NEED_CHANGE_EPSILON
        return thirstChanged and sourceChanged,
            "thirst=" .. tostring(intent.before.thirst) .. "->" .. tostring(after.thirst)
                .. " sourceAmount=" .. tostring(intent.sourceAmount) .. "->"
                .. tostring(sourceState ~= nil and sourceState.amount or "unavailable")
    end
    if intent.kind == "bandage" then
        local treated = intent.bodyPart ~= nil
            and (intent.bodyPart:bandaged() or not intent.bodyPart:bleeding())
        return treated,
            "bleedingParts=" .. tostring(intent.before.bleedingParts)
                .. "->" .. tostring(after.bleedingParts)
    end
    if intent.kind == "improvise_medical" then
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        return treatment ~= nil, treatment ~= nil
            and "treatment_created=" .. tostring(treatment:getFullType())
            or "no_treatment_created"
    end
    return false, "unsupported_intent=" .. tostring(intent.kind)
end

function Needs.verifyRecovery(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_recovery_intent"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "rest" then
        return after.endurance > intent.before.endurance + NEED_CHANGE_EPSILON,
            "endurance=" .. tostring(intent.before.endurance)
                .. "->" .. tostring(after.endurance)
    end
    if intent.kind == "sleep" then
        return after.fatigue < intent.before.fatigue - NEED_CHANGE_EPSILON,
            "fatigue=" .. tostring(intent.before.fatigue)
                .. "->" .. tostring(after.fatigue)
    end
    return false, "unsupported_recovery=" .. tostring(intent.kind)
end

function Needs.sleepHours(character, fatigue)
    local value = tonumber(fatigue) or 0
    local hours = math.floor(value * 10) + 1
    if character:hasTrait(CharacterTrait.INSOMNIAC) then
        hours = math.floor(hours * 0.5)
    end
    if character:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
        hours = math.floor(hours * 0.75)
    end
    if character:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
        hours = math.ceil(hours * 1.18)
    end
    return math.max(3, math.min(16, hours))
end

-- This is the same native sleep transition used by Build 42's world context
-- menu, without touching local-player UI or time controls for the off-slot NPC.
function Needs.startSleep(character, bed, bedType)
    if character == nil or character:isAsleep() then
        return false, "sleep_unavailable"
    end
    local state = Needs.snapshot(character)
    local hours = Needs.sleepHours(character, state.fatigue)
    local wakeAt = GameTime.getInstance():getTimeOfDay() + hours
    if wakeAt >= 24 then
        wakeAt = wakeAt - 24
    end
    character:setVariable("ExerciseStarted", false)
    character:setVariable("ExerciseEnded", true)
    local ok, reason = pcall(function()
        character:setBed(bed)
        character:setBedType(bedType or (bed ~= nil and "averageBed" or "floor"))
        character:setForceWakeUpTime(wakeAt)
        character:setAsleepTime(0.0)
        character:setAsleep(true)
        getSleepingEvent():setPlayerFallAsleep(character, hours)
    end)
    if not ok then
        -- A streamed or partially restored shell may lack the sleep event for
        -- one tick. Leave the controller recoverable and retry later instead
        -- of keeping a false SLEEPING_RECOVERY state forever.
        pcall(function() character:setAsleep(false) end)
        pcall(function() character:setBed(nil) end)
        diagNeed(character, "sleep_failed", {
            result = "native_sleep_error", bedType = tostring(bedType),
        })
        return false, "native_sleep_error:" .. tostring(reason)
    end
    diagNeed(character, "sleep_started", {
        hours = hours, bedType = tostring(bedType or (bed ~= nil and "averageBed" or "floor")),
    })
    return true, "native_sleep hours=" .. tostring(hours)
end

function Needs.wakeForDanger(character)
    if character == nil or not character:isAsleep() then
        return false
    end
    getSleepingEvent():wakeUp(character)
    return true
end
