require "KS_CompanionService"
require "KS_Persistence"
require "KS_SurvivorCapabilities"
require "KS_SurvivorNeeds"
require "KS_SurvivorRuntime"
require "KS_OrderCatalog"
local SurvivorNames = require "KS_SurvivorNames"
local ReputationView = require "KS_ReputationView"
if type(ReputationView) ~= "table" then
    ReputationView = rawget(_G, "KnoxReputationView") or {}
end

local ViewModel = rawget(_G, "KnoxSurvivorViewModel") or {}
_G.KnoxSurvivorViewModel = ViewModel


local ACTIVITY_LABELS = {
    regroup_last_contact = "Returning to last contact",
    awaiting_player_contact = "Waiting at last contact", regroup_route_blocked = "Regrouping route blocked",
    reading = "Reading",
    eating = "Eating", drinking = "Drinking", sleeping = "Sleeping",
    washing = "Washing", reloading = "Reloading",
    treating_wounds = "Treating wounds", preparing_bandages = "Preparing bandages",
    barricading = "Barricading windows", hauling_corpse = "Hauling a corpse",
    farming = "Farming", woodcutting = "Cutting trees", sawing_logs = "Sawing logs",
    repairing = "Repairing",
    waiting_for_route = "Keeping watch; route blocked",
    cooking_collect = "Collecting ingredients", cooking_load = "Preparing the microwave",
    cooking_heat = "Cooking food", cooking_deposit = "Storing cooked meals",
    cooking_move = "Working in the kitchen", cooking_transfer = "Moving kitchen supplies",
    collecting_book = "Collecting a book",
    returning_book = "Returning a book",
    organizing = "Organizing storage",
    collecting_item = "Collecting an item",
    shelving_item = "Shelving an item",
    fighting = "Fighting",
    retreating = "Retreating",
    guarding = "Keeping watch",
    patrolling = "Patrolling",
    collecting_job_supplies = "Collecting job supplies",
    waiting_for_materials = "Waiting for materials",
    waiting_for_food = "Waiting for food", waiting_for_water = "Waiting for water",
    waiting_for_medical = "Waiting for medical supplies",
    sorting_inventory = "Sorting inventory",
    storing_supplies = "Storing supplies",
    seeking_base_supplies = "Looking for base supplies",
    collecting_base_supplies = "Collecting base supplies",
    on_supply_run = "On a supply run",
    returning_with_base_supplies = "Returning with base supplies",
    returning_from_supply_run = "Returning from supply run",
    storing_base_supplies = "Storing base supplies",
    taking_base_supplies_to_storage = "Taking base supplies to storage",
    waiting_to_store_base_supplies = "Waiting to store base supplies",
    looting = "Looting",
    searching = "Searching",
    seeking_supplies = "Looking for supplies",
    exploring = "On the move",
    resting = "Resting",
    busy = "Busy",
    travelling = "Travelling",
    following = "Following",
    holding = "Waiting here",
    returning_home = "Returning to base",
    working_at_base = "Working",
    at_base = "Standing by",
    walking_at_base = "Walking around",
    scouting_base = "Looking for a base",
    meeting = "Talking",
    stopped = "Stopped",
    waiting = "Waiting",
    idle = "Taking a moment",
    trading = "Trading",
    returning_to_shelter = "Returning to shelter",
    at_shelter = "At shelter",
    driving = "Driving",
    waiting_for_road = "Waiting for a clear route",
    riding = "In vehicle",
    boarding = "Using vehicle",
}

local ROLE_LABELS = {
    companion = "Companion",
    resident = "Base resident",
    faction = "Faction survivor",
    independent = "Independent",
}

local LIFE_INTENT_LABELS = {
    find_food = "Looking for food",
    find_water = "Looking for water",
    find_medical = "Looking for medical supplies",
    scavenge = "Scavenging",
    investigate_building = "Checking a building",
    travel_area = "Travelling onward",
}

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function cleanNamePart(value)
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function identityFor(id, character)
    local stored = KnoxPersistence.getSurvivorIdentity(id) or {}
    return SurvivorNames.resolve(id, stored, character)
end

local function liveCharacter(id)
    local success, character = pcall(function()
        return KnoxSurvivorRuntime.getCharacter(id)
    end)
    if not success or character == nil then
        return nil
    end
    local squareOk, square = pcall(function()
        return character:getCurrentSquare()
    end)
    return squareOk and square ~= nil and character or nil
end


-- CONDITION ROWS (pure)
-- The card's Condition tab reads the same body state as the Needs line. Pain is
-- a fraction for the bar; a bleed count is a word, because "2 parts" is not a
-- percentage. Both are projections over the self-report the snapshot already
-- carries; neither infers a wound the survivor did not report.
local function painFraction(pain)
    local value = tonumber(pain)
    if value == nil or value ~= value then return nil end
    return math.max(0, math.min(1, value / 100))
end
local function bleedingWord(count)
    local value = math.max(0, math.floor(tonumber(count) or 0))
    if value == 0 then return nil end
    return value == 1 and "1 part" or (tostring(value) .. " parts")
end
-- The card's one medical button names the condition above it, without
-- promising a treatment the native check may not perform.
local function medicalLabel(bleedingParts)
    local count = math.max(0, math.floor(tonumber(bleedingParts) or 0))
    return count > 0 and "Check Bleeding" or "Medical Check"
end
-- The bite is the condition that changes the whole plan. Only the engine's own
-- boolean names it; a clean or unreadable body spends no row.
local function infectionWord(bitten)
    return bitten == true and "Bitten" or nil
end
-- END CONDITION ROWS

-- ORDER ROW (pure)
-- The card keeps the accepted order and adds the one fact that changes what
-- the player can ask for next. A steady or unknown person changes nothing.
local function orderRowLabel(label, willingness)
    local text = tostring(label or "")
    if willingness == "wary" then
        return text ~= "" and (text .. " - won't take new orders")
            or "Won't take new orders"
    end
    if willingness == "hostile" then
        return text ~= "" and (text .. " - hostile") or "Hostile"
    end
    return label
end
-- END ORDER ROW

-- WEAPON WORD (pure)
-- A weapon's condition is the warning before the break, not a second
-- durability model. Sound weapons spend no words; only the two worn bands do.
local function conditionWord(current, maximum)
    local value = tonumber(current)
    local max = tonumber(maximum)
    if value == nil or max == nil or max <= 0 then return nil end
    value = math.max(0, math.min(max, value))
    local ratio = value / max
    if ratio >= 0.75 then return nil end
    if ratio >= 0.4 then return "Worn" end
    if value > 0 then return "Fragile" end
    return nil
end
-- The card names what is in the hand. A broken weapon says so, because the
-- inventory is the only other place that fact is visible. A worn one adds one
-- word before it becomes unusable. The rule is pure so the suffix and the
-- empty-name case can be driven without a body.
local function weaponWord(rawName, broken, condition)
    local name = tostring(rawName or ""):gsub("%s+", " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    if broken == true then
        name = name .. " (broken)"
    elseif condition == "Worn" or condition == "Fragile" then
        name = name .. " - " .. condition
    end
    return name
end
-- The held gun's rounds are the same kind of projection: the engine's count,
-- not a guess. A chambered round is still a shot when the magazine reads zero,
-- so it is named rather than called empty; an unreadable or non-ranged item
-- spends no row at all.
local function ammoWord(rounds, chambered)
    local count = tonumber(rounds)
    if count == nil or count ~= count then return nil end
    count = math.max(0, math.floor(count))
    if count > 1 then return tostring(count) .. " rounds" end
    if count == 1 then return "1 round" end
    if chambered == true then return "1 chambered" end
    return "Empty"
end
-- END WEAPON WORD

local function weaponName(character)
    if character == nil then
        return "Equipment unavailable"
    end
    local success, item = pcall(function()
        return character:getPrimaryHandItem() or character:getSecondaryHandItem()
    end)
    if not success or item == nil then
        return "Unarmed"
    end
    local nameOk, name = pcall(function()
        return item:getDisplayName()
    end)
    local broken = false
    if success then
        pcall(function() broken = item:isBroken() == true end)
    end
    local condition = nil
    if nameOk and not broken then
        local currentOk, current = pcall(function() return item:getCondition() end)
        local maxOk, maximum = pcall(function() return item:getConditionMax() end)
        if currentOk and maxOk then
            condition = conditionWord(current, maximum)
        end
    end
    return nameOk and weaponWord(name, broken, condition) or "Unarmed"
end

-- AMMO NAME (projection)
local function ammoMethodAt(item, name)
    return item[name]
end

local function ammoRead(item, name)
    local found, method = pcall(ammoMethodAt, item, name)
    if not found or type(method) ~= "function" then return false, nil end
    return pcall(method, item)
end

local function ammoName(character)
    if character == nil then return nil end
    local success, item = pcall(function()
        return character:getPrimaryHandItem() or character:getSecondaryHandItem()
    end)
    if not success or item == nil or not instanceof(item, "HandWeapon") then return nil end
    local rangedOk, ranged = ammoRead(item, "isRanged")
    if not rangedOk or ranged ~= true then return nil end
    local countOk, count = ammoRead(item, "getCurrentAmmoCount")
    if not countOk then return nil end
    local chamberOk, chambered = ammoRead(item, "isRoundChambered")
    if not chamberOk then return nil end
    return ammoWord(count, chambered == true)
end
-- END AMMO NAME

local function roleFor(affiliation, duty)
    if affiliation.kind == "player" then
        return duty.mode == "companion" and "companion" or "resident"
    end
    if affiliation.kind == "faction" then
        return "faction"
    end
    return "independent"
end

local function worldAgeHours()
    local gameTime = getGameTime ~= nil and getGameTime() or nil
    return gameTime ~= nil and tonumber(gameTime:getWorldAgeHours()) or 0
end

local function wholeDaysSince(startedAtHours, nowHours)
    local started = tonumber(startedAtHours)
    if started == nil then
        return nil
    end
    return math.floor(math.max(0, (tonumber(nowHours) or 0) - started) / 24)
end

local function liveNumber(character, getterName)
    if character == nil or character[getterName] == nil then
        return nil
    end
    local success, value = pcall(function()
        return character[getterName](character)
    end)
    return success and tonumber(value) or nil
end

local function existingPlayerId(player)
    if player == nil or player.getModData == nil then
        return nil
    end
    local success, modData = pcall(function()
        return player:getModData()
    end)
    local knox = success and type(modData) == "table" and modData.KnoxSurvivors or nil
    local playerId = type(knox) == "table" and knox.playerId or nil
    return type(playerId) == "string" and playerId ~= "" and playerId or nil
end

local function professionLabelFor(id)
    local success, label = pcall(function()
        local profile = KnoxPersistence.getSurvivorCapabilities(id)
        return KnoxSurvivorCapabilities.professionLabel(profile)
    end)
    return success and cleanNamePart(label) ~= "" and tostring(label) or "Survivor"
end

-- Base duty is persisted separately from the loaded controller.  Projecting an
-- active claim here keeps the Notebook/Card truthful after a reload or while
-- the controller is between ticks, without creating another order owner.
local function claimedBaseTaskFor(id, duty)
    if id == nil or type(duty) ~= "table" or duty.mode ~= "base"
        or duty.baseId == nil or KnoxPersistence.getBase == nil then
        return nil
    end
    local base = KnoxPersistence.getBase(duty.baseId)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if type(task) == "table" and task.state == "claimed"
            and tostring(task.claimedBy or "") == tostring(id) then
            return task
        end
    end
    return nil
end

local function orderLabelFor(duty, survivorId)
    -- A stale companion directive may survive a delayed duty refresh.  Base
    -- ownership is authoritative, so never let that transient field mask the
    -- resident's real claimed work in the player-facing status.
    local directive = duty.mode ~= "base"
        and type(duty.directive) == "table" and duty.directive or nil
    local directiveLabel = directive ~= nil and KnoxOrderCatalog.statusLabel(
        tostring(directive.kind or ""), nil
    ) or nil
    if directiveLabel ~= nil then
        return directiveLabel
    end
    if duty.mode == "base" then
        local supplyOrder = type(duty.baseSupplyOrder) == "table" and duty.baseSupplyOrder or nil
        local supplyLabel = supplyOrder ~= nil
            and KnoxOrderCatalog.statusLabel(supplyOrder.kind, nil) or nil
        if supplyLabel ~= nil then return supplyLabel end
        local task = claimedBaseTaskFor(survivorId, duty)
        if task ~= nil then
            return KnoxOrderCatalog.label(
                KnoxOrderCatalog.normalizeTaskType(task.type) or task.type,
                "Working at base"
            )
        end
        if duty.lastJobType ~= nil then
            return "Available at base (last: " .. KnoxOrderCatalog.label(
                KnoxOrderCatalog.normalizeTaskType(duty.lastJobType) or duty.lastJobType,
                tostring(duty.lastJobType)
            ) .. ")"
        end
        return "Available at base"
    end
    if duty.mode == "companion" then
        local directive = type(duty.directive) == "table" and duty.directive or nil
        if directive ~= nil then
            local label = KnoxOrderCatalog.statusLabel(tostring(directive.kind or ""), nil)
            if label ~= nil then return label end
        end
        return duty.order == "hold" and "Holding here"
            or (duty.order == "relax" and "Relaxing" or "Following")
    end
    if duty.order == "return" or duty.order == "return_to_base" then
        return "Returning to base"
    end
    return ACTIVITY_LABELS[tostring(duty.order or "")] or "Surviving"
end

local function locationLabelFor(duty, character, distance, sameLevel)
    if duty.mode == "base" and type(duty.baseId) == "string" then
        local base = KnoxPersistence.getBase(duty.baseId)
        local name = tostring(base ~= nil and base.name or "Home Base")
        local manager = rawget(_G, "KnoxBaseManager")
        if character ~= nil and manager ~= nil and manager.containsSquare ~= nil then
            local ok, inside = pcall(function()
                return manager.containsSquare(base, character:getCurrentSquare())
            end)
            if ok and inside then return "At " .. name end
        end
        return (character == nil and "Away - assigned to " or "Outside ") .. name
    end
    if character == nil then
        return "Away"
    end
    if distance == nil then
        return "Nearby"
    end
    if not sameLevel then
        return "Nearby, another floor"
    end
    return "With you - " .. tostring(math.floor(distance + 0.5)) .. " tiles"
end

local function runtimeActivity(id)
    local success, snapshot = pcall(function()
        return KnoxSurvivorRuntime.snapshot(id)
    end)
    if not success or type(snapshot) ~= "table" or snapshot.loaded == false then
        local intent = KnoxPersistence.getSurvivorLifeIntent ~= nil
            and KnoxPersistence.getSurvivorLifeIntent(id) or nil
        local intentLabel = intent ~= nil
            and LIFE_INTENT_LABELS[tostring(intent.kind or "")] or nil
        local stored = KnoxPersistence.getUnloadedSurvivalState ~= nil
            and KnoxPersistence.getUnloadedSurvivalState(id) or nil
        local labels = {
            base_life = "Settled",
            base_working = "Working",
            group_travel = "Travelling with group",
            group_waiting = "Waiting for group",
            group_regrouping = "Regrouping",
            surviving = "Surviving offscreen",
            exploring = "Exploring",
            seeking_supplies = "Looking for supplies",
            sleeping = "Sleeping",
            resting = "Resting",
            sheltering = "Staying nearby",
            returning_to_base = "Returning to base",
            waiting_for_leader = "Waiting for leader",
            away_mission = "On a mission",
        }
        -- A life intent is a longer-term goal; it must not hide the current
        -- rest, return, mission or base-work activity. It only refines an
        -- active supply search (or supplies a fallback without known activity).
        local storedActivity = stored ~= nil and stored.activity or nil
        if storedActivity == "seeking_supplies" and intentLabel ~= nil then
            return intentLabel
        end
        return labels[storedActivity] or intentLabel
    end
    if snapshot.activity == "busy" then
        local selfCare = { eat = "Eating", drink = "Drinking", bandage = "Treating wounds",
            improvise_medical = "Preparing bandages" }
        local label = selfCare[tostring(snapshot.decision or "")]
        if label ~= nil then return label end
    end
    return ACTIVITY_LABELS[tostring(snapshot.activity or "")]
end

local function needSummary(state, available)
    if not available then return "Condition unavailable" end
    local labels = {}
    local thresholds = KnoxSurvivorNeeds.thresholds
    -- A bite is-the death sentence: surface it first, ahead of bleeding.
    -- No exclamation marks in player copy (UI.md law 8): a bite is already the
    -- first, critical entry in this list and reads in the red tone.
    if state.bitten == true then labels[#labels + 1] = "Bitten" end
    if (tonumber(state.bleedingParts) or 0) > 0 then labels[#labels + 1] = "Bleeding" end
    if (tonumber(state.bleedingParts) or 0) == 0 and (tonumber(state.health) or 100) < 75 then
        labels[#labels + 1] = "Hurt"
    end
    if tonumber(state.pain) ~= nil and tonumber(state.pain) > 0 then
        labels[#labels + 1] = "Pain"
    end
    if (tonumber(state.thirst) or 0) >= 0.90 then labels[#labels + 1] = "Dehydrated"
    elseif (tonumber(state.thirst) or 0) >= thresholds.thirst then labels[#labels + 1] = "Water" end
    if (tonumber(state.hunger) or 0) >= 0.90 then labels[#labels + 1] = "Starving"
    elseif (tonumber(state.hunger) or 0) >= thresholds.hunger then labels[#labels + 1] = "Food" end
    if (tonumber(state.endurance) or 1) <= 0.12 then labels[#labels + 1] = "Critical exhaustion"
    elseif (tonumber(state.endurance) or 1) <= thresholds.lowEndurance then labels[#labels + 1] = "Catch breath" end
    if (tonumber(state.fatigue) or 0) >= thresholds.fatigue then labels[#labels + 1] = "Sleep" end
    return #labels > 0 and table.concat(labels, ", ") or nil
end

local function activityFor(duty, state, loaded, alive, currentActivity)
    if not alive then
        return "Dead"
    end
    if not loaded then
        return currentActivity or "Away"
    end
    if currentActivity ~= nil then
        return currentActivity
    end
    if (tonumber(state.bleedingParts) or 0) > 0 or (tonumber(state.health) or 100) < 75 then
        return "Hurt"
    end
    if (tonumber(state.thirst) or 0) >= KnoxSurvivorNeeds.thresholds.thirst then
        return "Needs water"
    end
    if (tonumber(state.hunger) or 0) >= KnoxSurvivorNeeds.thresholds.hunger then
        return "Needs food"
    end
    if (tonumber(state.endurance) or 1) <= KnoxSurvivorNeeds.thresholds.lowEndurance then
        return "Catching breath"
    end
    if (tonumber(state.fatigue) or 0) >= KnoxSurvivorNeeds.thresholds.fatigue then
        return "Tired"
    end
    if duty.mode == "companion" then
        local directive = type(duty.directive) == "table" and duty.directive or nil
        if directive ~= nil then
            if directive.kind == "guard" then
                return "Guarding"
            end
            if directive.kind == "go_to" then
                return "Moving"
            end
        end
        return duty.order == "hold" and "Waiting here"
            or (duty.order == "relax" and "Relaxing" or "Following")
    end
    if duty.mode == "base" then
        return "At base"
    end
    return "Surviving"
end

local function playerDistance(player, character)
    if player == nil or character == nil then
        return nil, false
    end
    local success, distance, sameLevel = pcall(function()
        local dx = player:getX() - character:getX()
        local dy = player:getY() - character:getY()
        return math.sqrt(dx * dx + dy * dy), player:getZ() == character:getZ()
    end)
    return success and distance or nil, success and sameLevel or false
end

function ViewModel.resolveLiveCharacter(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return liveCharacter(id)
end

-- Preserve the existing card's trust bands without exposing a private score.
-- The band itself lives in KS_ReputationView so the card, Talk and any later
-- roster cannot describe the same relationship differently.
local function trustLabelFor(relationship)
    local trust = relationship ~= nil and tonumber(relationship.trust) or nil
    if trust == nil or trust ~= trust then return "Unknown" end
    if ReputationView.personalLabel ~= nil then
        return ReputationView.personalLabel(trust)
    end
    return trust >= 70 and "Trusting" or (trust >= 40 and "Cautious" or "Wary")
end
-- The Talk panel's standing line is the same read-out as the card's, so one
-- relationship cannot be described two different ways.
ViewModel.trustLabelFor = trustLabelFor

function ViewModel.getSurvivor(id, playerNum)
    if type(id) ~= "string" or id == "" then
        return nil
    end

    local playerIndex = tonumber(playerNum)
    if playerIndex == nil then return nil end
    local player = getSpecificPlayer(playerIndex)
    local body = liveCharacter(id)
    local visible, direct = pcall(function() return body ~= nil and player:CanSee(body) == true end)
    local character = visible and direct and body or nil
    local observerId = existingPlayerId(player)
    local known = observerId ~= nil and KnoxPersistence.getObserverKnowledge ~= nil
        and KnoxPersistence.getObserverKnowledge(observerId, id) or nil
    local report = known ~= nil and known.report or nil
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {
        kind = "independent",
    }
    local duty = KnoxPersistence.getSurvivorDuty(id) or {
        mode = "autonomous",
        order = "survive",
    }
    -- Precise needs are self-reported, never inferred from a hidden simulation
    -- snapshot or from merely opening a notebook.
    local state = report ~= nil and report.value.state or {health=100, hunger=0, thirst=0,
        fatigue=0, endurance=1, bleedingParts=0}
    local vitalsAvailable = report ~= nil and type(report.value.state) == "table"
    local forename, surname, displayName = identityFor(id, character)
    local distance, sameLevel = playerDistance(player, character)
    local currentActivity = character ~= nil and runtimeActivity(id) or nil
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    local nowHours = worldAgeHours()
    local ageYears = tonumber(identity.ageYears) or liveNumber(character, "getAge")
    local daysSurvived = wholeDaysSince(identity.createdAtHours, nowHours)
    if daysSurvived == nil then
        local survivedHours = liveNumber(character, "getHoursSurvived")
        daysSurvived = survivedHours ~= nil and math.floor(math.max(0, survivedHours) / 24) or nil
    end
    local playerId = existingPlayerId(player)
    local relationship = playerId ~= nil
        and KnoxPersistence.getPlayerRelationshipSnapshot(playerId, id)
        or nil
    local orderWillingness = nil
    if playerId ~= nil and type(affiliation) == "table"
        and affiliation.kind == "player" then
        local service = rawget(_G, "KnoxCompanionService")
        if service ~= nil and service.orderWillingness ~= nil then
            local ok, verdict = pcall(service.orderWillingness, id, playerId)
            if ok and type(verdict) == "string" then orderWillingness = verdict end
        end
    end
    local orderLabel = character ~= nil and orderLabelFor(duty, id) or "Last accepted order"
    local hostile = false
    if playerId ~= nil and KnoxPersistence.isSurvivorHostileToPlayer ~= nil then
        local hostileOk, flag = pcall(KnoxPersistence.isSurvivorHostileToPlayer,
            id, playerId)
        hostile = hostileOk and flag == true
    end
    local standing = ReputationView.personal ~= nil
        and ReputationView.personal(relationship, hostile) or nil
    local factionStanding = ReputationView.factionFor ~= nil
        and ReputationView.factionFor(playerId, id) or nil
    local playerData = player ~= nil and player.getModData ~= nil and player:getModData() or nil
    local spouseStart = playerData ~= nil and playerData.KnoxSurvivors ~= nil
        and playerData.KnoxSurvivors.spouseStart or nil
    local capabilities = KnoxPersistence.getSurvivorCapabilities(id) or {}
    local lifeIntent = nil -- Intent requires communication; activity is not proof of purpose.
    local faction = affiliation.factionId ~= nil and KnoxPersistence.getFaction ~= nil
        and KnoxPersistence.getFaction(affiliation.factionId) or nil
    local knownSince = relationship ~= nil and relationship.firstMetHours
        or affiliation.joinedAtHours
    local role = roleFor(affiliation, duty)
    local alive = true
    local recentHistory = {} -- Private/offscreen memories require an actual report.
    if character ~= nil then
        local success, dead = pcall(function()
            return character:isDead()
        end)
        alive = alive and not (success and dead == true)
    end
    local deathEvidence = nil
    local deathCauseLabel = nil
    if character ~= nil and not alive then
        local sq = character:getCurrentSquare()
        deathEvidence = {x=sq:getX(), y=sq:getY(), z=sq:getZ(), locationSource="observed"}
        -- The body is where the person fell; why they fell is already on the
        -- death evidence the death owner stored. Reading it here keeps the card
        -- and the map marker on the same record the death line printed.
        local stored = KnoxPersistence.getSurvivorDeathEvidence ~= nil
            and KnoxPersistence.getSurvivorDeathEvidence(id) or nil
        local cause = type(stored) == "table" and stored.cause or nil
        deathEvidence.cause = cause
        local needs = rawget(_G, "KnoxSurvivorNeeds")
        deathCauseLabel = needs ~= nil and needs.deathCauseLabel ~= nil
            and needs.deathCauseLabel(cause) or nil
    end
    local deathLocationLabel = "Deceased - witnessed"

    local snapshot = {
        version = 2,
        id = id,
        forename = forename,
        surname = surname,
        displayName = displayName,
        role = role,
        roleLabel = ROLE_LABELS[role] or "Survivor",
        professionLabel = professionLabelFor(id),
        personality = identity.personality,
        personalityLabel = identity.personalityLabel,
        traits = capabilities.traitIds or {},
        skills = capabilities.skills or {},
        trustLabel = standing ~= nil and standing.label or trustLabelFor(relationship),
        standing = standing,
        factionStanding = factionStanding,
        relationshipMeetings = relationship ~= nil and tonumber(relationship.meetings) or nil,
        recentHistory = recentHistory,
        latestMemory = recentHistory[1] ~= nil and recentHistory[1].label or nil,
        isSpouse = type(spouseStart) == "table" and spouseStart.id == id,
        factionName = faction ~= nil and tostring(faction.name or faction.id or "") or nil,
        ageYears = ageYears ~= nil and math.floor(ageYears) or nil,
        daysSurvived = daysSurvived,
        daysKnown = wholeDaysSince(knownSince, nowHours),
        locationLabel = character ~= nil and (alive and locationLabelFor(duty, character, distance, sameLevel) or deathLocationLabel) or "Location unknown",
        deathEvidence = deathEvidence,
        deathCauseLabel = deathCauseLabel,
        orderLabel = orderLabel,
        orderDisplayLabel = orderRowLabel(orderLabel, orderWillingness),
        orderWillingness = orderWillingness,
        order = tostring(duty.order or "survive"),
        activity = character ~= nil and activityFor(duty, {}, true, alive, currentActivity) or "Out of contact",
        needSummary = needSummary(state, vitalsAvailable),
        lifeIntent = lifeIntent ~= nil and {
            kind = lifeIntent.kind,
            phase = lifeIntent.phase,
            label = LIFE_INTENT_LABELS[tostring(lifeIntent.kind or "")],
        } or nil,
        loaded = character ~= nil,
        alive = alive,
        health = vitalsAvailable and clamp01((tonumber(state.health) or 100) / 100) or nil,
        infectionLabel = vitalsAvailable and infectionWord(state.bitten) or nil,
        bleedingParts = math.max(0, tonumber(state.bleedingParts) or 0),
        bleedingLabel = vitalsAvailable and bleedingWord(state.bleedingParts) or nil,
        medicalActionLabel = vitalsAvailable and medicalLabel(state.bleedingParts) or "Medical Check",
        needs = {
            food = vitalsAvailable and (1 - clamp01(state.hunger)) or nil,
            water = vitalsAvailable and (1 - clamp01(state.thirst)) or nil,
            -- Sleepiness (fatigue). The legacy `rest` key stays as an alias
            -- for older HUD/card builds reading the same snapshot.
            sleep = vitalsAvailable and (1 - clamp01(state.fatigue)) or nil,
            rest = vitalsAvailable and (1 - clamp01(state.fatigue)) or nil,
            endurance = vitalsAvailable and clamp01(state.endurance) or nil,
        },
        vitals = {
            available = vitalsAvailable == true,
            health = vitalsAvailable and clamp01((tonumber(state.health) or 100) / 100) or nil,
            hunger = vitalsAvailable and clamp01(state.hunger) or nil,
            thirst = vitalsAvailable and clamp01(state.thirst) or nil,
            fatigue = vitalsAvailable and clamp01(state.fatigue) or nil,
            endurance = vitalsAvailable and clamp01(state.endurance) or nil,
            bleedingParts = vitalsAvailable and math.max(0, tonumber(state.bleedingParts) or 0) or nil,
            pain = vitalsAvailable and painFraction(state.pain) or nil,
        },
        weaponName = weaponName(character),
        ammoName = ammoName(character),
        distanceTiles = distance,
        sameLevel = sameLevel,
        affiliation = {
            kind = tostring(affiliation.kind or "independent"),
            ownerId = affiliation.ownerId,
            factionId = affiliation.factionId,
            joinedAtHours = tonumber(affiliation.joinedAtHours),
        },
        duty = {
            mode = tostring(duty.mode or "autonomous"),
            order = tostring(duty.order or "survive"),
            ownerId = duty.ownerId,
            baseId = duty.baseId,
            jobPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or duty.jobPreference,
            directiveKind = type(duty.directive) == "table"
                and tostring(duty.directive.kind or "")
                or nil,
        },
        portraitKey = character ~= nil and tostring(character) or "unloaded",
    }
    -- Reports remain useful history; sight alone does not refresh physiology.
    -- Every consumer (including the compact HUD) receives the same dated text.
    if report ~= nil then
        local ageMinutes = math.floor(math.max(0, nowHours - report.atHours) * 60)
        snapshot.needSummary = "Last reported (" .. tostring(ageMinutes) .. " min ago): "
            .. tostring(snapshot.needSummary or "All right")
    else
        snapshot.needSummary = "Needs not reported"
    end
    snapshot.knowledge = {source=character ~= nil and "observation" or "unknown",
        atHours=character ~= nil and nowHours or nil, reportAtHours=report ~= nil and report.atHours or nil,
        reportSource=report ~= nil and report.source or nil, current=character ~= nil}
    local keys = {"alive", "role", "roleLabel", "duty", "order", "orderLabel", "activity",
        "locationLabel", "weaponName", "ammoName", "deathEvidence", "deathCauseLabel", "position", "affiliation", "factionName",
        "skills", "traits", "daysSurvived"}
    if character ~= nil then
        local sq = character:getCurrentSquare()
        snapshot.position = {x=sq:getX(), y=sq:getY(), z=sq:getZ()}
        local value = {}
        for _, key in ipairs(keys) do value[key] = snapshot[key] end
        if observerId ~= nil and KnoxPersistence.rememberObserverKnowledge ~= nil then
            KnoxPersistence.rememberObserverKnowledge(observerId,id,"seen",value,nowHours)
        end
    else
        local seen = known ~= nil and known.seen or nil
        local previous = seen ~= nil and seen.value or {}
        for _, key in ipairs(keys) do snapshot[key] = previous[key] end
        local commitment = known ~= nil and known.commitment or nil
        if commitment ~= nil and (seen == nil or commitment.atHours >= seen.atHours) then
            snapshot.role, snapshot.duty, snapshot.order = commitment.value.role, commitment.value.duty, commitment.value.order
            snapshot.roleLabel = ROLE_LABELS[snapshot.role]
        end
        snapshot.role = snapshot.role or role
        snapshot.roleLabel = snapshot.roleLabel or ROLE_LABELS[snapshot.role]
        snapshot.activity = seen ~= nil and (previous.alive == false and "Dead (witnessed)"
            or "Last seen: " .. tostring(previous.activity or "Unknown")) or "Out of contact"
        snapshot.locationLabel = seen ~= nil and "Last seen - " .. tostring(math.floor(math.max(0,
            nowHours-seen.atHours)*60)) .. " min ago" or "Location unknown"
        snapshot.weaponName = previous.weaponName or "Equipment unavailable"
        snapshot.ammoName = previous.ammoName
        snapshot.distanceTiles, snapshot.sameLevel = nil, nil
        snapshot.knowledge.source = seen ~= nil and seen.source or "unknown"
        snapshot.knowledge.atHours = seen ~= nil and seen.atHours or nil
        -- Accepted owner orders remain known commitments, not proof of current
        -- execution. Do not project autonomous task-board activity here.
        if duty.ownerId == observerId and duty.mode == "companion" then
            snapshot.order, snapshot.duty = duty.order, {mode=duty.mode, order=duty.order, ownerId=duty.ownerId}
            snapshot.orderLabel = KnoxOrderCatalog.label(type(duty.directive)=="table" and duty.directive.kind or duty.order, "Follow")
        end
    end
    return snapshot
end

function ViewModel.getForPlayer(playerNum)
    local playerIndex = tonumber(playerNum)
    if playerIndex == nil then return {} end
    local player = getSpecificPlayer(playerIndex)
    if player == nil then
        return {}
    end

    local snapshots = {}
    local ids, included = {}, {}
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(player) or {}) do ids[#ids+1]=id; included[id]=true end
    local observerId = existingPlayerId(player)
    if observerId ~= nil and KnoxPersistence.getKnownSurvivorIds ~= nil then
        for _, id in ipairs(KnoxPersistence.getKnownSurvivorIds(observerId)) do
            if not included[id] then
                local known = KnoxPersistence.getObserverKnowledge(observerId,id)
                local latest = known ~= nil and known.seen or nil
                if known ~= nil and known.commitment ~= nil and (latest == nil or known.commitment.atHours >= latest.atHours) then latest=known.commitment end
                local rememberedRole = latest ~= nil and latest.value.role or nil
                if rememberedRole == "companion" then
                    ids[#ids+1]=id; included[id]=true
                end
            end
        end
    end
    for _, id in ipairs(ids or {}) do
        local snapshot = ViewModel.getSurvivor(id, playerIndex)
        if snapshot ~= nil and snapshot.alive ~= false and snapshot.role == "companion" then
            snapshots[#snapshots + 1] = snapshot
        end
    end
    table.sort(snapshots, function(first, second)
        local firstName = string.lower(first.displayName or first.id)
        local secondName = string.lower(second.displayName or second.id)
        if firstName == secondName then
            return first.id < second.id
        end
        return firstName < secondName
    end)
    return snapshots
end

-- PARTY STRIP SUMMARY (pure)
-- The compact and expanded strips share one readable projection. It reads
-- reported needs, visible activity, health and the alive flag; it adds no
-- physiological thresholds and never invents an observation.
local PARTY_NEED_CONDITIONS = {
    { token = "Bitten", label = "Bitten", tone = "critical" },
    { token = "Bleeding", label = "Bleeding", tone = "critical" },
    { token = "Starving", label = "Starving", tone = "critical" },
    { token = "Dehydrated", label = "Dehydrated", tone = "critical" },
    { token = "Critical exhaustion", label = "Exhausted", tone = "critical" },
    { token = "Hurt", label = "Hurt", tone = "warn" },
    { token = "Pain", label = "In pain", tone = "warn" },
    { token = "Water", label = "Thirsty", tone = "warn" },
    { token = "Food", label = "Hungry", tone = "warn" },
    { token = "Catch breath", label = "Winded", tone = "warn" },
    { token = "Sleep", label = "Tired", tone = "warn" },
}

local PARTY_ACTIVITY_CONDITIONS = {
    ["Hurt"] = { label = "Hurt", tone = "warn" },
    ["Needs water"] = { label = "Thirsty", tone = "warn" },
    ["Needs food"] = { label = "Hungry", tone = "warn" },
    ["Catching breath"] = { label = "Winded", tone = "warn" },
    ["Tired"] = { label = "Tired", tone = "warn" },
    ["Falling back"] = { label = "Withdrawing", tone = "warn" },
    ["Regrouping"] = { label = "Regrouping", tone = "warn" },
    ["Retreating"] = { label = "Withdrawing", tone = "warn" },
    ["Dead"] = { label = "Dead", tone = "critical" },
    ["Dead (witnessed)"] = { label = "Dead", tone = "critical" },
}

local function cleanNeedText(snapshot)
    local summary = tostring(snapshot.needSummary or "")
    local clean = summary:gsub("^Last reported %([^%)]*%): ", "")
    if clean == "" or clean == "Needs not reported"
        or clean == "Condition unavailable" then
        return nil, false
    end
    return clean, true
end

function ViewModel.partyCondition(snapshot)
    if type(snapshot) ~= "table" then
        return { label = "Unknown", tone = "muted" }
    end
    if snapshot.alive == false then
        return { label = "Dead", tone = "critical" }
    end
    local clean, known = cleanNeedText(snapshot)
    if known then
        for _, entry in ipairs(PARTY_NEED_CONDITIONS) do
            if string.find(clean, entry.token, 1, true) ~= nil then
                return { label = entry.label, tone = entry.tone }
            end
        end
    end
    local health = tonumber(snapshot.health)
    if health ~= nil and health < 0.75 then
        return { label = "Hurt", tone = "warn" }
    end
    -- A dry gun during a fight is the fact that changes the next move. Only a
    -- visible body whose own engine count said Empty earns the word; an
    -- offscreen memory, a holstered gun or a melee fighter says nothing here.
    -- A wound or a reported need above already outranks it.
    if snapshot.loaded == true and snapshot.ammoName == "Empty" then
        local doing = tostring(snapshot.activity or "")
        if doing == "Fighting" or doing == "Retreating"
            or doing == "Falling back" then
            return { label = "Out of ammo", tone = "warn" }
        end
    end
    local activity = PARTY_ACTIVITY_CONDITIONS[tostring(snapshot.activity or "")]
    if activity ~= nil then return activity end
    if known or health ~= nil then
        return { label = "Fine", tone = "good" }
    end
    return { label = "Unknown", tone = "muted" }
end

-- A crew roster row has room for one condition word only when it is a problem.
-- The strip's own projection decides what that word is, so a bitten resident
-- cannot read Fine in the notebook and Bitten in the HUD. A clean or unknown
-- body spends no column.
function ViewModel.rosterCondition(snapshot)
    local condition = ViewModel.partyCondition(snapshot)
    if condition.tone == "warn" or condition.tone == "critical" then
        return condition.label
    end
    return nil
end

-- Hover replaces the row's condition word with a lower-priority detail line.
-- It must not hide the fact that changes the plan: a critical word is already
-- the answer to "what is wrong?".
function ViewModel.hoverKeepsCondition(tone)
    return tone == "critical"
end

-- The party strip's one refusal badge reads the same order gate the order
-- commands do. Only a real refusal earns it; steady and unknown spend nothing.
function ViewModel.partyRefusal(willingness)
    if willingness == "wary" then
        return { label = "Wary", tone = "warn" }
    end
    if willingness == "hostile" then
        return { label = "Hostile", tone = "critical" }
    end
    return nil
end

-- One short line for a hovered strip row: the fact the row itself has no
-- room for. It reads only what this file already projected for the snapshot -
-- a need that crossed its threshold, or the last known place for someone out
-- of contact. It is not a reason and never guesses why something happened.
function ViewModel.partyDetail(snapshot)
    if type(snapshot) ~= "table" then return nil end
    if snapshot.alive == false then return "Dead" end
    -- Out of contact, the place is the actionable fact. A need on that report
    -- describes the body last seen, not the one in front of the player.
    if snapshot.loaded == false then
        local where = tostring(snapshot.locationLabel or "")
        if where == "" then return "Away" end
        -- The producer already frames an offscreen body: it overwrites the
        -- label with "Last seen - N min ago" or "Location unknown", and the
        -- duty branch can supply its own "Away - assigned to ...". Prefixing
        -- any of those would report the same absence twice.
        if string.sub(where, 1, 9) == "Last seen"
            or string.sub(where, 1, 13) == "Last reported"
            or where == "Location unknown"
            or string.sub(where, 1, 4) == "Away" then
            return where
        end
        return "Away - " .. where
    end
    local clean, known = cleanNeedText(snapshot)
    -- "All right" is what the offscreen projection stores when nothing crossed a
    -- threshold, so prefixing it with Needs: would read "Needs: All right".
    if known and clean ~= nil and clean ~= "" and clean ~= "All right" then
        return "Needs: " .. clean
    end
    return nil
end

function ViewModel.partyProblemCount(snapshots)
    local count = 0
    for _, snapshot in ipairs(type(snapshots) == "table" and snapshots or {}) do
        local condition = ViewModel.partyCondition(snapshot)
        if condition.tone == "warn" or condition.tone == "critical" then
            count = count + 1
        end
    end
    return count
end

-- The strip's one-line state, shared by the expanded header and the compact
-- row. It reports only the conditions already projected above; it never adds
-- a new need threshold or invents an observation.
function ViewModel.partyHeadline(snapshots, compact)
    local list = type(snapshots) == "table" and snapshots or {}
    local total = #list
    if total == 0 then return "No one with you" end
    local problems = ViewModel.partyProblemCount(list)
    if compact == true then
        if problems > 0 then
            return tostring(total) .. " with you - " .. tostring(problems)
                .. (problems == 1 and " problem" or " problems")
        end
        return tostring(total) .. " with you"
    end
    if problems > 0 then
        return tostring(total) .. " - " .. tostring(problems)
            .. (problems == 1 and " needs you" or " need you")
    end
    local unreported = 0
    for _, snapshot in ipairs(list) do
        if ViewModel.partyCondition(snapshot).tone == "muted" then
            unreported = unreported + 1
        end
    end
    if unreported > 0 then
        return tostring(total) .. " - " .. tostring(unreported) .. " unreported"
    end
    return tostring(total) .. " - all clear"
end

-- The strongest condition in the party, used for the compact row's one accent
-- and the header. `good` wins only when at least one person is known to be
-- fine; an all-unknown party stays muted rather than claiming an all-clear.
function ViewModel.partyTone(snapshots)
    local list = type(snapshots) == "table" and snapshots or {}
    if #list == 0 then return "muted" end
    local hasGood, hasWarn, hasUnknown = false, false, false
    for _, snapshot in ipairs(list) do
        local condition = ViewModel.partyCondition(snapshot)
        if condition.tone == "critical" then return "critical" end
        if condition.tone == "warn" then hasWarn = true end
        if condition.tone == "good" then hasGood = true end
        if condition.tone == "muted" then hasUnknown = true end
    end
    if hasWarn then return "warn" end
    if hasUnknown then return "muted" end
    if hasGood then return "good" end
    return "muted"
end
-- END PARTY STRIP SUMMARY

-- END PARTY STRIP SUMMARY

return ViewModel
