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

-- Read actual transition evidence only. Missing posture/square APIs are
-- reported as unavailable, never used to grant sleep or manufacture posture.
local function diagSleep(character, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log == nil or log.log == nil then return end
    if log.diagnosticsEnabled ~= nil then
        local ok, enabled = pcall(log.diagnosticsEnabled)
        if not ok or not enabled then return end
    end
    local function read(getter)
        local ok, value = pcall(getter)
        if not ok or value == nil then return "unavailable" end
        return value
    end
    details = details or {}
    details.asleep = read(function() return character:isAsleep() end)
    details.sitOnGround = read(function() return character:isSitOnGround() end)
    details.sittingOnFurniture = read(function() return character:isSittingOnFurniture() end)
    details.square = read(function()
        local square = character:getCurrentSquare()
        if square == nil then return "unloaded" end
        return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
    end)
    details.fatigue = read(function() return character:getStats():get(CharacterStat.FATIGUE) end)
    details.visibleZombies = read(function() return character:getStats():getNumVisibleZombies() end)
    details.chasingZombies = read(function() return character:getStats():getNumChasingZombies() end)
    details.closeZombies = read(function() return character:getStats():getNumVeryCloseZombies() end)
    diagNeed(character, event, details)
end

local function walkInventory(container, visitor)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if visitor(item, container) == true then return true end
        if item:IsInventoryContainer() then
            if walkInventory(item:getInventory(), visitor) == true then return true end
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

function Needs.findBestFood(character, available)
    local best = nil
    local bestScore = -math.huge
    walkInventory(character:getInventory(), function(item)
        if isSafeFood(item) and (available == nil or available(item)) then
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
        or amount ~= amount or amount == math.huge or amount == -math.huge
        or type(tainted) ~= "boolean" then return nil end
    return { source = source, amount = amount,
        available = hasFluid and amount > 0, tainted = tainted }
end

local function isSmokeItem(item)
    local ok, supported = pcall(function()
        return item ~= nil and item:IsFood() and ItemTag ~= nil
            and ItemTag.SMOKABLE ~= nil and item:hasTag(ItemTag.SMOKABLE)
    end)
    return ok and supported == true
end

-- Build 42 uses tagged Food cigarettes/cigars, not unopened drainable packs.
-- Native Eat and its timed action own consumption, relief and ignition use.
function Needs.findSmokeItem(character, available)
    if character == nil or character.getInventory == nil then return nil end
    local inventory = character:getInventory()
    if inventory == nil then return nil end
    local found = nil
    pcall(function()
        walkInventory(inventory, function(item)
            if isSmokeItem(item) and (available == nil or available(item)) then found = item; return true end
        end)
    end)
    return found
end

local function smokeState(character)
    local function read(getter)
        local ok, value = pcall(getter)
        if ok and type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge and value >= 0 then return value end
    end
    local state = {
        elapsed = read(function() return character:getStats():getTimeSinceLastSmoke() end),
        stress = read(function() return character:getStats():get(CharacterStat.STRESS) end),
        unhappy = read(function() return character:getStats():get(CharacterStat.UNHAPPINESS) end),
    }
    if state.elapsed == nil and state.stress == nil and state.unhappy == nil then return nil end
    return state
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

function Needs.findBestWater(character, allowTainted, available)
    local best = nil
    walkInventory(character:getInventory(), function(item)
        local state = waterState(item)
        if state ~= nil and (allowTainted or not state.tainted)
            and (available == nil or available(item)) then
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

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function carriedIn(character, item, source)
    local found = false
    walkInventory(character:getInventory(), function(candidate, container)
        if candidate == item and (source == nil or container == source) then found = true; return true end
    end)
    return found
end

local function consumptionReceipt(character, intent)
    local after = Needs.snapshot(character)
    if intent.kind == "eat" then
        local remaining = math.abs(intent.item:getHungerChange())
        local consumed = not carriedIn(character, intent.item, nil)
            or (finite(remaining) and remaining < intent.foodAmount - NEED_CHANGE_EPSILON)
        return consumed and finite(after.hunger) and finite(intent.before.hunger)
            and after.hunger < intent.before.hunger - NEED_CHANGE_EPSILON
    elseif intent.kind == "drink" or intent.kind == "drink_world" then
        local amount
        if intent.kind == "drink" then
            if intent.item:getFluidContainer() ~= intent.fluid then return false end
            amount = intent.fluid:getAmount()
        else
            local state = Needs.waterSourceState(intent.source)
            amount = state ~= nil and state.amount or nil
        end
        return finite(amount) and amount < intent.sourceAmount - NEED_CHANGE_EPSILON
            and finite(after.thirst) and finite(intent.before.thirst)
            and after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON
    elseif intent.kind == "smoke" then
        if carriedIn(character, intent.item, nil) then return false end
        local current = smokeState(character)
        if current == nil then return false end
        for _, key in ipairs({"elapsed", "stress", "unhappy"}) do
            if finite(intent.smokeBefore[key]) and finite(current[key])
                and current[key] < intent.smokeBefore[key] - NEED_CHANGE_EPSILON then return true end
        end
    elseif intent.kind == "bandage" then
        return intent.bodyPart ~= nil and intent.bodyPart:bandaged()
            and not carriedIn(character, intent.item, nil)
    elseif intent.kind == "improvise_medical" then
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        return not carriedIn(character, intent.item, nil) and treatment ~= nil
            and treatment ~= intent.treatmentBefore
    end
    return false
end

-- This is permission around the existing native action, never replacement
-- consumption. Install before add: native begin/complete can run immediately.
local function bindNeedAction(character, action, intent, ownership)
    local item, source = intent.item, intent.source
    intent.character, intent.action = character, action
    if ownership ~= nil then ownership.action, ownership.intent, ownership.source = action, intent, source end
    local function allowed(candidate)
        local ok, valid = pcall(function()
            if candidate ~= action or candidate.character ~= character or intent.cancelled
                or intent.item ~= item or intent.source ~= source then return false end
            if ownership ~= nil and (ownership.cancelled or ownership.allowed(candidate, intent) ~= true) then return false end
            if intent.kind == "drink_world" then
                if candidate.waterObject ~= intent.source then return false end
                local state = Needs.waterSourceState(intent.source)
                local thirst = Needs.snapshot(character).thirst
                return state ~= nil and state.available
                    and (not state.tainted or (finite(thirst) and thirst >= 0.90))
            end
            if intent.kind == "improvise_medical" then
                -- Native start/serverStart constructs a fresh HandcraftLogic.
                -- The accepted recipe survives that transition; logic identity does not.
                return candidate.knoxMedicalSource == item and intent.craftRecipe ~= nil
                    and candidate.craftRecipe == intent.craftRecipe
                    and ((intent.recipeCompleted and intent.receipt == true)
                        or (carriedIn(character, item, source)
                            and KnoxMedicalSupplies.canImprovise(character, intent.supplyPlan) == true))
            end
            if candidate.item ~= intent.item or not carriedIn(character, intent.item, intent.source) then return false end
            if intent.kind == "bandage" then
                return candidate.bodyPart == intent.bodyPart and candidate.otherPlayer == character
                    and intent.bodyPart:HasInjury() and not intent.bodyPart:bandaged()
            end
            if intent.kind == "prepare_supply" then return true end
            if intent.kind == "eat" then return isSafeFood(intent.item) end
            if intent.kind == "smoke" then return isSmokeItem(intent.item) end
            if intent.kind == "drink" then
                local state = waterState(intent.item)
                local thirst = Needs.snapshot(character).thirst
                return state ~= nil and intent.item:getFluidContainer() == intent.fluid
                    and (not state.tainted or (finite(thirst) and thirst >= 0.90))
            end
            return false
        end)
        return ok and valid == true
    end
    intent.guard, action.knoxNeedGuard = allowed, allowed
    if ownership ~= nil then ownership.guard = allowed end
    local nativeValid = action.isValid
    action.isValid = function(candidate)
        return allowed(candidate) and nativeValid ~= nil and nativeValid(candidate)
    end
    local function wrapMutation(name, once)
        local native = action[name]
        if native == nil then return end
        local completedKey = name == "performRecipe" and "recipeCompleted" or "nativeCompleted"
        action[name] = function(candidate, ...)
            if not allowed(candidate) or (once and intent[completedKey]) then return false end
            if once then intent[completedKey] = true end
            local result = native(candidate, ...)
            local ok, received = pcall(consumptionReceipt, character, intent)
            if ok and received then intent.receipt = true end
            return result
        end
    end
    if intent.kind ~= "prepare_supply" then
        wrapMutation("complete", true)
        -- Native stops/partial water updates can consume too. Revoked care
        -- must not eat/drink later while an unrelated current queue drains.
        if intent.kind == "eat" or intent.kind == "smoke" then wrapMutation("eat")
        elseif intent.kind == "drink" then wrapMutation("drink")
        elseif intent.kind == "drink_world" then wrapMutation("transferFluid")
        elseif intent.kind == "improvise_medical" then wrapMutation("performRecipe", true) end
    end
end

local function registeredNeedAction(character, action, admitted, intent)
    local registered = ISTimedActionQueue.queues and ISTimedActionQueue.queues[character]
    if admitted == nil or admitted ~= registered or intent.cancelled then return false end
    for _, candidate in ipairs(admitted.queue or {}) do if candidate == action then return true end end
    return intent.receipt == true
end

local function queueNeedAction(character, action, intent, ownership)
    bindNeedAction(character, action, intent, ownership)
    if not intent.guard(action) then intent.cancelled = true; return nil, "permission_changed" end
    local ok, admitted = pcall(ISTimedActionQueue.add, action)
    if not ok or not registeredNeedAction(character, action, admitted, intent)
        or (ownership ~= nil and ownership.cancelled) then
        intent.cancelled = true
        return nil, ok and "queue_refused" or "queue_failed"
    end
    intent.admitted = true
    return action
end

function Needs.execute(character, decision, ownership)
    if decision == nil then
        return nil, "missing_decision"
    end
    if (decision.kind == "eat" and (decision.state == nil or not finite(decision.state.hunger)))
        or ((decision.kind == "drink" or decision.kind == "drink_world")
            and (decision.state == nil or not finite(decision.state.thirst))) then
        return nil, "need_state_unavailable"
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
        local intent = { kind = "bandage", before = decision.state,
            item = decision.item, bodyPart = decision.bodyPart }
        if ownership ~= nil then
            local action, result = KnoxMedicalActions.queueBandage(character,
                decision.item, decision.bodyPart, function(actor, candidate)
                    return queueNeedAction(actor, candidate, intent, ownership)
                end)
            return report(action, result or "queued_bandage", intent)
        end
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
    if decision.kind == "smoke" then
        decision.item = decision.item or Needs.findSmokeItem(character)
        if not isSmokeItem(decision.item) then return report(nil, "no_smoke_carried") end
    end
    if decision.kind == "drink" or decision.kind == "eat" or decision.kind == "smoke" then
        local inventory, source = character:getInventory(), nil
        walkInventory(inventory, function(item, container)
            if item == decision.item then source = container; return true end
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
            local intent = { kind = "prepare_supply", needKind = decision.kind,
                before = decision.state, item = decision.item, source = source, destination = inventory }
            local guard
            guard = function(candidate, item)
                if intent.action == nil then
                    bindNeedAction(character, candidate, intent, ownership)
                    if ownership ~= nil then ownership.guard = guard end
                end
                return intent.guard(candidate) and item == intent.item
                    and candidate.srcContainer == source and candidate.destContainer == inventory
            end
            if ownership ~= nil then ownership.guard, ownership.intent = guard, intent end
            local ok, action, reason = pcall(KnoxInventoryActions.queueTransfer,
                character, decision.item, source, inventory, nil, guard)
            if ok and action ~= nil then
                if intent.action == nil then bindNeedAction(character, action, intent, ownership) end
                if ownership ~= nil then ownership.guard = guard end
                intent.receipt = not carriedIn(character, intent.item, source)
                    and carriedIn(character, intent.item, inventory)
            end
            local registered = ISTimedActionQueue.queues and ISTimedActionQueue.queues[character]
            if not ok or action == nil or not registeredNeedAction(character, action, registered, intent)
                or (ownership ~= nil and ownership.cancelled) then
                intent.cancelled = true
                diagNeed(character, "need_action_failed", {
                    kind = tostring(decision.kind), result = "supply_transfer_rejected",
                })
                return nil, "supply_transfer_rejected"
            end
            intent.admitted = true
            return report(action, reason, intent)
        end
    end
    if decision.kind == "drink" then
        local thirst = decision.state.thirst
        local uses = math.max(1, math.ceil(math.max(0, thirst - 0.15) / 0.1))
        local state = waterState(decision.item)
        if state == nil or not finite(state.amount) then return report(nil, "water_state_unavailable") end
        local intent = { kind = "drink", before = decision.state, item = decision.item,
            source = character:getInventory(), fluid = decision.item:getFluidContainer(), sourceAmount = state.amount }
        local action = ISDrinkFromBottle:new(character, decision.item, uses)
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "drink", result = "drink_queue_rejected",
            })
            return nil, "drink_queue_rejected"
        end
        return report(action, "queued_drink", intent)
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
        local intent = { kind = "drink_world", before = decision.state, source = decision.source,
            sourceAmount = sourceState.amount, tainted = sourceState.tainted }
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            return report(nil, "native_water_action_queue_rejected")
        end
        return report(action, "queued_native_water_drink", intent)
    end
    if decision.kind == "eat" then
        local benefit = math.max(0.01, math.abs(decision.item:getHungerChange()))
        local percentage = math.max(
            0.25,
            math.min(1.0, math.max(0, decision.state.hunger - 0.15) / benefit)
        )
        local action = ISEatFoodAction:new(character, decision.item, percentage)
        local intent = { kind = "eat", before = decision.state, item = decision.item,
            source = character:getInventory(), foodAmount = math.abs(decision.item:getHungerChange()) }
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "eat", result = "eat_queue_rejected",
            })
            return nil, "eat_queue_rejected"
        end
        return report(action, "queued_eat percentage=" .. tostring(percentage), intent)
    end
    if decision.kind == "improvise_medical" then
        if ownership ~= nil then
            local intent = { kind = "improvise_medical", before = decision.state,
                item = decision.supplyPlan ~= nil and decision.supplyPlan.item or nil,
                supplyPlan = decision.supplyPlan,
                treatmentBefore = KnoxMedicalSupplies.findTreatment(character) }
            local ok, action = KnoxMedicalSupplies.queueImprovisation(character,
                decision.supplyPlan, function(actor, candidate)
                    intent.craftRecipe = candidate.craftRecipe
                    return queueNeedAction(actor, candidate, intent, ownership)
                end)
            return report(ok and action or nil, ok and "queued_improvise_medical" or action, intent)
        end
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
        local ignitionOk, ignition = pcall(function()
            return smokeAction.carLighter or smokeAction.openFlame
                or smokeAction:getRequiredItem() ~= nil
        end)
        if not ignitionOk or not ignition then return report(nil, "smoke_ignition_unavailable") end
        local baseline = smokeState(character)
        if baseline == nil then return report(nil, "smoke_state_unavailable") end
        local intent = { kind = "smoke", before = decision.state, item = smoke,
            source = character:getInventory(), smokeBefore = baseline }
        local accepted = queueNeedAction(character, smokeAction, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "smoke", result = "smoke_queue_rejected",
            })
            return nil, "smoke_queue_rejected"
        end
        return report(smokeAction, "queued_smoke", intent)
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
    if intent.kind == "eat" or intent.kind == "drink" or intent.kind == "drink_world"
        or intent.kind == "smoke" or intent.kind == "prepare_supply"
        or ((intent.kind == "bandage" or intent.kind == "improvise_medical") and intent.action ~= nil) then
        if intent.cancelled or intent.action == nil or intent.admitted ~= true then
            return false, "need_action_unconfirmed"
        end
        if intent.kind ~= "prepare_supply" and intent.receipt ~= true then
            return false, "native_consumption_unconfirmed"
        end
    end
    local after = Needs.snapshot(character)
    if intent.kind == "smoke" then
        local carriedOk, carried = pcall(function()
            local found = false
            walkInventory(character:getInventory(), function(item)
                if item == intent.item then found = true; return true end
            end)
            return found
        end)
        if not carriedOk or type(carried) ~= "boolean" or carried or intent.item == nil then
            return false, "smoke_consumption_unconfirmed"
        end
        local baseline, current = intent.smokeBefore, smokeState(character)
        if type(baseline) ~= "table" or current == nil then return false, "smoke_state_unavailable" end
        for _, key in ipairs({"elapsed", "stress", "unhappy"}) do
            if type(baseline[key]) == "number" and type(current[key]) == "number"
                and current[key] < baseline[key] - NEED_CHANGE_EPSILON then
                return true, "smoke_consumed " .. key .. "=" .. tostring(baseline[key]) .. "->" .. tostring(current[key])
            end
        end
        return false, "smoke_no_observed_change"
    end
    if intent.kind == "prepare_supply" then
        local ok, received = pcall(function()
            return intent.source ~= nil and not carriedIn(character, intent.item, intent.source)
                and carriedIn(character, intent.item, character:getInventory())
        end)
        return ok and received == true, "supply_main_inventory"
    end
    if intent.kind == "eat" then
        local ok, received = pcall(consumptionReceipt, character, intent)
        return ok and received == true,
            "hunger=" .. tostring(intent.before.hunger) .. "->" .. tostring(after.hunger)
    end
    if intent.kind == "drink" then
        local ok, received = pcall(consumptionReceipt, character, intent)
        return ok and received == true,
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

function Needs.sleepHours(character, fatigue, bedType)
    local value = tonumber(fatigue) or 0
    -- Installed onSleepWalkToComplete order, preserving fractional hours.
    local hours = ZombRand(value * 10, value * 13) + 1
    local quality = tostring(bedType or "averageBed")
    if string.find(quality, "goodBed", 1, true) ~= nil then hours = hours - 1 end
    if string.find(quality, "badBed", 1, true) ~= nil then hours = hours + 1 end
    if string.find(quality, "floor", 1, true) ~= nil then hours = hours * 0.7 end
    if character:hasTrait(CharacterTrait.INSOMNIAC) then
        hours = hours * 0.5
    end
    if character:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
        hours = hours * 0.75
    end
    if character:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
        hours = hours * 1.18
    end
    return math.max(3, math.min(16, hours))
end

-- This is the same native sleep transition used by Build 42's world context
-- menu, without touching local-player UI or time controls for the off-slot NPC.
function Needs.startSleep(character, bed, bedType)
    if character == nil or character:isAsleep() then
        return false, "sleep_unavailable"
    end
    -- Recheck at arrival, just as the installed Build 42 context-menu sleep
    -- transition does. Conditions may have changed while walking to the bed.
    -- Unreadable native state cannot authorize sleep.
    local inspected, blocker = pcall(function()
        local stats = character:getStats()
        if stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
            or stats:getNumVeryCloseZombies() > 0 then
            return "sleep_not_safe"
        end
        if character:getSleepingTabletEffect() < 2000 then
            local moodles = character:getMoodles()
            if moodles:getMoodleLevel(MoodleType.PAIN) >= 2
                and stats:get(CharacterStat.FATIGUE) <= 0.85 then
                return "sleep_pain"
            end
            if moodles:getMoodleLevel(MoodleType.PANIC) >= 1 then
                return "sleep_panic"
            end
        end
        return nil
    end)
    if not inspected or blocker ~= nil then
        local result = inspected and blocker or "sleep_state_unavailable"
        diagSleep(character, "sleep_blocked", { result = result })
        return false, result
    end
    local state = Needs.snapshot(character)
    local sleepBedType = bedType or (bed ~= nil and "averageBed" or "floor")
    local hours = Needs.sleepHours(character, state.fatigue, sleepBedType)
    local wakeAt = GameTime.getInstance():getTimeOfDay() + hours
    if wakeAt >= 24 then
        wakeAt = wakeAt - 24
    end
    character:setVariable("ExerciseStarted", false)
    character:setVariable("ExerciseEnded", true)
    local ok, reason = pcall(function()
        character:setBed(bed)
        character:setBedType(sleepBedType)
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
        diagSleep(character, "sleep_failed", {
            result = "native_sleep_error", bedType = tostring(sleepBedType),
        })
        return false, "native_sleep_error:" .. tostring(reason)
    end
    diagSleep(character, "sleep_started", {
        hours = hours, bedType = tostring(sleepBedType), wakeAt = wakeAt,
    })
    return true, "native_sleep hours=" .. tostring(hours)
end

function Needs.wakeForDanger(character)
    if character == nil or not character:isAsleep() then
        return false
    end
    getSleepingEvent():wakeUp(character)
    diagSleep(character, "sleep_woken", { result = "requested_wake" })
    return true
end
