require "KS_GroupCohesion"
local Simulation = rawget(_G, "KnoxUnloadedSurvival") or {}
_G.KnoxUnloadedSurvival = Simulation
require "KS_BaseDutySimulation"
require "KS_OffscreenStories"
require "KS_OrderCatalog"

-- Hibernated survivors are not hidden active characters.  This module advances a
-- small persisted survival ledger between body capture and reconstruction.  It
-- never creates supplies: food and water are removed from the encoded portable
-- inventory before the relief is recorded.
local MAX_STEP_HOURS = 6
local PHYSICAL_TASK_OFFSCREEN_WAIT_HOURS = 12
-- Meal triggers match the loaded need thresholds (0.45) so hibernated
-- survivors eat/drink on the same schedule they would while loaded.
local FOOD_TRIGGER = 0.45
local WATER_TRIGGER = 0.45
local FOOD_AFTER_MEAL = 0.22
local WATER_AFTER_DRINK = 0.22
local HUNGER_PER_HOUR = 0.026
local THIRST_PER_HOUR = 0.040
local FATIGUE_RECOVERY_PER_HOUR = 0.055
local ENDURANCE_RECOVERY_PER_HOUR = 0.090
local STARVATION_DAMAGE_PER_HOUR = 1.20
local DEHYDRATION_DAMAGE_PER_HOUR = 2.00
local RETURN_TILES_PER_HOUR = 40
local GROUP_REGROUP_DISTANCE = 20
local GROUP_REJOIN_DISTANCE = 6
local AWAKE_FATIGUE_PER_HOUR = 0.020
local WALK_ENDURANCE_PER_HOUR = 0.025
local REST_ENDURANCE = 0.30
local RESUME_ENDURANCE = 0.80
local SLEEP_FATIGUE = 0.72
local WAKE_FATIGUE = 0.35
-- A bounded carried reserve bridges loaded base storage into the existing
-- serialized-inventory simulation. These are item counts, not generated need
-- relief; weak foods and small water containers still provide only native value.
local BASE_HIBERNATION_FOOD_ITEMS = 4
local BASE_HIBERNATION_WATER_ITEMS = 3

local function canonicalTaskType(taskType)
    if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeTaskType ~= nil then
        return KnoxOrderCatalog.normalizeTaskType(taskType) or taskType
    end
    return taskType
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value > -math.huge and value < math.huge
end

local function validNeeds(snapshot)
    if type(snapshot) ~= "table" then return false end
    for _, key in ipairs({ "hunger", "thirst", "fatigue", "endurance", "health" }) do
        if not finite(snapshot[key]) then return false end
    end
    return true
end

-- A prepared ledger does not prove that native removal succeeded. Never spend
-- serialized inventory while its live body still owns those same items.
local function nativeBodyAbsent(id)
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.getNpcCharacter == nil then return true end
    local ok, body = pcall(bridge.getNpcCharacter, bridge, id)
    return ok and body == nil
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function hoursAboveThreshold(before, rate, elapsed, threshold)
    before = tonumber(before) or 0
    elapsed = math.max(0, tonumber(elapsed) or 0)
    if before >= threshold then return elapsed end
    if rate <= 0 then return 0 end
    local crossing = (threshold - before) / rate
    return math.max(0, elapsed - crossing)
end

-- Territory stores inclusive min/max bounds; legacy home areas store spans.
-- Use the same geometry for return routes and dispersed offscreen base life.
local function areaDimensions(area)
    local minX, minY = tonumber(area.minX) or 0, tonumber(area.minY) or 0
    local width = tonumber(area.maxX) ~= nil and tonumber(area.maxX) - minX + 1
        or tonumber(area.width) or 1
    local height = tonumber(area.maxY) ~= nil and tonumber(area.maxY) - minY + 1
        or tonumber(area.height) or 1
    return math.max(1, math.floor(width)), math.max(1, math.floor(height))
end

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or 0
end

local function survivorPresent(persistence, id)
    if persistence == nil then return false end
    if persistence.isSurvivorPresent ~= nil then
        return persistence.isSurvivorPresent(id)
    end
    return persistence.isSurvivorAlive ~= nil and persistence.isSurvivorAlive(id)
end

local function consumeStoredSupply(id, kind, amount, communalBase, reserve)
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if persistence == nil or bridge == nil or bridge.consumeNpcRecordSupply == nil then
        return false, "record_mutator_unavailable"
    end
    local record = persistence.getRecord(id)
    if record == nil then
        return false, "record_unavailable"
    end
    local mutator = communalBase ~= nil and bridge.consumeNpcRecordBaseSupply or bridge.consumeNpcRecordSupply
    if mutator == nil then return false, "communal_mutator_unavailable" end
    local ok, result = pcall(mutator, bridge, record, kind, amount, communalBase, reserve)
    if not ok or result == nil then
        return false, "item_not_present"
    end
    local readOk, updated, hunger, thirst, itemType = pcall(function()
        return result:get("record"), tonumber(result:get("hungerRelief")),
            tonumber(result:get("thirstRelief")), tostring(result:get("itemType"))
    end)
    if not readOk or type(updated) ~= "string" or updated == "" or updated == record
        or hunger == nil or thirst == nil or hunger ~= hunger or thirst ~= thirst
        or hunger < 0 or hunger > 1 or math.abs(thirst) > 1 then
        return false, "invalid_supply_result"
    end
    if not persistence.setRecord(id, updated) then
        return false, "record_save_failed"
    end
    local summaryOk, summary = pcall(bridge.getNpcRecordInventorySummary, bridge, updated)
    if summaryOk and type(summary) == "string" then
        persistence.setInventorySummary(id, summary, nowHours())
    end
    return true, itemType, hunger, thirst
end

local function consumeAvailableSupply(id, kind, amount, recipient, hours)
    local consumed, evidence, hunger, thirst = consumeStoredSupply(id, kind, amount)
    if consumed then return true, evidence, hunger, thirst end
    local persistence = rawget(_G, "KnoxPersistence")
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or nil
    if duty == nil or duty.mode ~= "base" or duty.baseId == nil
        or persistence.getBaseResidentIds == nil then
        return false, evidence
    end
    local base = persistence.getBase ~= nil and persistence.getBase(duty.baseId) or nil
    local area = base ~= nil and base.territory or nil
    if recipient == nil or area == nil then return false, evidence end
    local width, height = areaDimensions(area)
    local function atBase(state)
        return state ~= nil and finite(state.virtualX) and finite(state.virtualY) and finite(state.virtualZ)
            and state.virtualX >= area.minX and state.virtualX < area.minX + width
            and state.virtualY >= area.minY and state.virtualY < area.minY + height
            and (area.allFloors == true or state.virtualZ == (tonumber(area.z) or 0))
    end
    if not atBase(recipient) then return false, evidence end
    -- Base membership is not permission to consume personal possessions. Only
    -- nearby, stored, same-floor residents captured at this same simulation time
    -- can offer explicitly allocated native
    -- base provisions, retaining the same one/two-item reserve as loaded help.
    for _, donorId in ipairs(persistence.getBaseResidentIds(duty.baseId) or {}) do
        if donorId ~= id and survivorPresent(persistence, donorId) then
            local donorDuty = persistence.getSurvivorDuty(donorId) or {}
            local donorState = persistence.getUnloadedSurvivalState(donorId)
            if donorDuty.mode == "base" and donorDuty.baseId == duty.baseId
                and atBase(donorState) and donorState.lastHours == hours
                and donorState.virtualZ == recipient.virtualZ
                and (donorState.virtualX-recipient.virtualX)^2+(donorState.virtualY-recipient.virtualY)^2 <= 9
                and donorState.status == "hibernated" and donorState.pendingMaterialization ~= true
                and nativeBodyAbsent(donorId) then
                local ownNeed = kind == "food" and (tonumber(donorState.hunger) or 1) >= FOOD_TRIGGER
                    or kind == "water" and (tonumber(donorState.thirst) or 1) >= WATER_TRIGGER
                local shared, itemType, sharedHunger, sharedThirst = consumeStoredSupply(
                    donorId, kind, amount, duty.baseId, ownNeed and 2 or 1)
                if shared then return true, "base:" .. tostring(donorId) .. ":" .. tostring(itemType), sharedHunger, sharedThirst end
            end
        end
    end
    return false, evidence
end

local function ensureState(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local existing = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if existing ~= nil then
        return existing
    end
    return {
        hunger = clamp(snapshot and snapshot.hunger, 0, 1),
        thirst = clamp(snapshot and snapshot.thirst, 0, 1),
        fatigue = clamp(snapshot and snapshot.fatigue, 0, 1),
        endurance = clamp(snapshot and snapshot.endurance, 0, 1),
        health = clamp(snapshot and snapshot.health, 0, 100),
        bleedingParts = math.max(0, math.floor(tonumber(snapshot and snapshot.bleedingParts) or 0)),
        lastHours = hours,
        status = "stored",
        activity = "stored",
        activitySinceHours = hours,
    }
end

local function stableHash(value)
    local result = 5381
    for index = 1, #tostring(value or "") do
        result = (result * 33 + string.byte(tostring(value), index)) % 2147483647
    end
    return result
end

local function recordLocation(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    local record = persistence ~= nil and persistence.getRecord(id) or nil
    if bridge == nil or record == nil then return nil end
    local ok, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record), bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not ok then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

local function setActivity(state, activity, hours)
    if state.activity ~= activity then
        state.activity = activity
        state.activitySinceHours = hours
    end
end

function Simulation.prepareBaseResidentForStorage(id, character, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or character == nil then
        return false, "persistence_or_character_unavailable"
    end
    local duty = persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or nil
    if duty == nil or duty.mode ~= "base" or duty.baseId == nil then
        return false, "not_base_resident"
    end
    local base = persistence.getBase ~= nil and persistence.getBase(duty.baseId) or nil
    local square = character.getCurrentSquare ~= nil and character:getCurrentSquare() or nil
    local baseManager = rawget(_G, "KnoxBaseManager")
    if base == nil or square == nil or baseManager == nil
        or baseManager.containsSquare == nil
        or not baseManager.containsSquare(base, square) then
        return false, "resident_not_at_loaded_base"
    end
    local baseStorage = rawget(_G, "KnoxBaseStorage")
    if baseStorage == nil or baseStorage.provisionSurvivalSupplies == nil then
        return false, "base_storage_provisioning_unavailable"
    end
    local prepared, report = baseStorage.provisionSurvivalSupplies(
        base,
        character,
        {
            food = BASE_HIBERNATION_FOOD_ITEMS,
            water = BASE_HIBERNATION_WATER_ITEMS,
        }
    )
    if not prepared or type(report) ~= "table" then
        return false, tostring(report or "provision_failed")
    end
    local state = persistence.getUnloadedSurvivalState ~= nil
        and persistence.getUnloadedSurvivalState(id) or nil
    if state ~= nil then
        state.baseProvision = {
            baseId = tostring(duty.baseId),
            atHours = tonumber(hours) or nowHours(),
            foodBefore = tonumber(report.before and report.before.food) or 0,
            foodAfter = tonumber(report.after and report.after.food) or 0,
            waterBefore = tonumber(report.before and report.before.water) or 0,
            waterAfter = tonumber(report.after and report.after.water) or 0,
            foodShortage = report.shortages and report.shortages.food or nil,
            waterShortage = report.shortages and report.shortages.water or nil,
        }
        persistence.setUnloadedSurvivalState(id, state)
    end
    local transferred = report.transferred or {}
    return true, "base=" .. tostring(duty.baseId)
        .. " food=" .. tostring(tonumber(transferred.food) or 0)
        .. " water=" .. tostring(tonumber(transferred.water) or 0)
        .. " foodShortage=" .. tostring(report.shortages and report.shortages.food or "none")
        .. " waterShortage=" .. tostring(report.shortages and report.shortages.water or "none")
end

local function advanceWorldActivity(id, state, elapsed, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return 0 end
    local duty = persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or {}
    if duty.eventId ~= nil then
        -- A borrowed resident must not be moved back into ambient home squares
        -- while its event still owns travel. The cohort scheduler advances only
        -- a wholly stored party; needs still advance here when a member is loaded.
        state.baseReturn = nil
        setActivity(state, "event_waiting_loaded", hours)
        return 0
    end
    if duty.mode == "away" then
        -- Away-team simulation owns travel, risk, ETA, and mission results.
        -- Keep the last known destination in the durable ledger so a member
        -- can materialize there after the team resolves instead of snapping
        -- back to the stale departure square.
        local team = persistence.getAwayTeamForSurvivor ~= nil
            and persistence.getAwayTeamForSurvivor(id) or nil
        local destination = team ~= nil and team.destination or nil
        if destination ~= nil and tonumber(destination.x) ~= nil
            and tonumber(destination.y) ~= nil then
            state.virtualX = math.floor(tonumber(destination.x))
            state.virtualY = math.floor(tonumber(destination.y))
            state.virtualZ = math.floor(tonumber(destination.z) or 0)
            state.virtualAtHours = hours
        end
        setActivity(state, "away_mission", hours)
        return 0
    end
    local x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
    if x == nil or y == nil or z == nil then
        x, y, z = recordLocation(id)
    end
    if x == nil or y == nil or z == nil then return 0 end
    local residentBase = duty.mode == "base" and duty.baseId ~= nil
        and persistence.getBase ~= nil and persistence.getBase(duty.baseId) or nil
    local residentArea = residentBase ~= nil and (residentBase.territory or residentBase.home) or nil
    local residentTask = nil
    if residentBase ~= nil and type(residentBase.tasks) == "table" then
        for _, candidate in pairs(residentBase.tasks) do
            if candidate ~= nil and candidate.state == "claimed" and candidate.claimedBy == id then
                residentTask = candidate
                break
            end
        end
    end
    local security = residentTask ~= nil and KnoxBaseDutySimulation ~= nil
        and KnoxBaseDutySimulation.canAdvanceOffscreen(residentTask)
    local returning = type(state.baseReturn) == "table" and state.baseReturn or nil
    if returning == nil and residentArea ~= nil and not security
        and tonumber(residentArea.minX) ~= nil and tonumber(residentArea.minY) ~= nil then
        local minX, minY = tonumber(residentArea.minX), tonumber(residentArea.minY)
        local width, height = areaDimensions(residentArea)
        if x < minX or y < minY or x >= minX + width or y >= minY + height
            or (residentArea.allFloors ~= true and z ~= (tonumber(residentArea.z) or z)) then
            -- Ordinary hibernation may catch a resident outside on a supply
            -- outing. Return from that captured position before ambient home
            -- placement or work can run; use the existing durable route owner.
            returning = { baseId = duty.baseId, startedAtHours = hours - elapsed }
            state.baseReturn = returning
        end
    end
    if returning ~= nil then
        local area = residentArea
        if area == nil or tonumber(area.minX) == nil or tonumber(area.minY) == nil then
            -- Dismiss/recruit/base removal must not leave a trip owning this person.
            state.baseReturn, returning = nil, nil
        else
            -- A relocated/reassigned base supersedes the old destination from the
            -- current virtual position, never from the original departure point.
            local width, height = areaDimensions(area)
            returning.baseId = duty.baseId
            returning.targetX = math.floor(tonumber(area.minX)) + math.floor((width - 1) / 2)
            returning.targetY = math.floor(tonumber(area.minY)) + math.floor((height - 1) / 2)
            returning.targetZ = area.allFloors == true and z or (tonumber(area.z) or z)
        end
    end
    if returning ~= nil and tonumber(returning.targetX) ~= nil
        and tonumber(returning.targetY) ~= nil then
        local targetX = tonumber(returning.targetX)
        local targetY = tonumber(returning.targetY)
        local targetZ = tonumber(returning.targetZ) or z
        if targetZ ~= z then
            -- Coarse foot travel cannot prove a staircase/elevator route.
            -- Retain the destination and actual floor for loaded recovery.
            state.virtualX, state.virtualY, state.virtualZ = x, y, z
            state.virtualAtHours = hours
            setActivity(state, "sheltering", hours)
            return 0
        end
        local dx, dy = targetX - x, targetY - y
        local distance = math.sqrt(dx * dx + dy * dy)
        local travel = math.max(0, elapsed) * RETURN_TILES_PER_HOUR
        if distance <= math.max(0.01, travel) then
            x, y, z = targetX, targetY, targetZ
            state.baseReturn = nil
            setActivity(state, "base_life", hours)
        else
            x = x + dx / distance * travel
            y = y + dy / distance * travel
            setActivity(state, "returning_to_base", hours)
        end
        state.virtualX, state.virtualY, state.virtualZ = x, y, z
        state.virtualAtHours = hours
        return math.min(elapsed, distance / RETURN_TILES_PER_HOUR)
    end
    if duty.mode == "base" and duty.baseId ~= nil then
        local area, task = residentArea, residentTask
        if area ~= nil and not security then
            -- A stored resident should not return to the exact old tile every
            -- time, or make a whole settlement reappear in one stack.  This is
            -- low-cost ambient base life rather than simulated pathfinding: each
            -- six-hour phase gives each identity one deterministic place inside
            -- its own saved territory.  Materialization still validates the
            -- real square before committing it to the persistent Java record.
            local minX = math.floor(tonumber(area.minX) or x)
            local minY = math.floor(tonumber(area.minY) or y)
            local width, height = areaDimensions(area)
            local phase = math.floor(hours / MAX_STEP_HOURS)
            local seed = stableHash(tostring(id) .. ":base:" .. tostring(phase))
            x = minX + (seed % width)
            y = minY + (math.floor(seed / width) % height)
            z = area.allFloors == true and z or (tonumber(area.z) or z)
        end
        local workingOffscreen = false
        if task ~= nil and KnoxBaseDutySimulation ~= nil then
            KnoxBaseDutySimulation.advance(task, elapsed)
            workingOffscreen = true
            -- A completed watch shift is elapsed time, not a completed Guard or
            -- Patrol order. Preserve the task owner and last physical location.
            setActivity(state, "base_working", hours)
        end
        if not workingOffscreen then setActivity(state, "base_life", hours) end
    elseif duty.mode == "companion" then
        -- Companions normally remain loaded. If streaming briefly stores one,
        -- preserve their exact last location for reliable reunion.
        setActivity(state, "waiting_for_leader", hours)
    else
        local group = persistence.getTravelGroupFor ~= nil
            and persistence.getTravelGroupFor(id) or nil
        local population = rawget(_G, "KnoxWorldPopulation")
        if group == nil then
            state.virtualX, state.virtualY, state.virtualZ = x, y, z
            local moving = 0
            if population ~= nil and population.advanceItinerary ~= nil then
                local advanced, _, travelHours = population.advanceItinerary(id, state, hours - elapsed, hours)
                if advanced then moving = tonumber(travelHours) or 0 end
            end
            local intent = persistence.getSurvivorLifeIntent ~= nil
                and persistence.getSurvivorLifeIntent(id) or nil
            local seeking = intent ~= nil and (intent.kind == "find_food"
                or intent.kind == "find_water" or intent.kind == "find_medical")
            setActivity(
                state,
                moving > 0 and (seeking and "seeking_supplies" or "exploring")
                    or "sheltering",
                hours
            )
            state.virtualAtHours = hours
            return moving
        end
        -- Only the batch scheduler can move a whole stored group. A single
        -- member update must not drift away from a still-loaded group member.
        setActivity(state, "group_waiting", hours)
    end
    state.virtualX = x
    state.virtualY = y
    state.virtualZ = z
    state.virtualAtHours = hours
    return 0
end

local function advanceRestAndTravel(id, state, elapsed, hours, cohort)
    local persistence = rawget(_G, "KnoxPersistence")
    local duty = persistence.getSurvivorDuty(id) or {}
    if duty.mode == "away" then
        -- Away teams retain their existing mission travel/recovery owner.
        advanceWorldActivity(id, state, elapsed, hours)
        state.fatigue = clamp(state.fatigue - FATIGUE_RECOVERY_PER_HOUR * elapsed, 0, 1)
        state.endurance = clamp(state.endurance + ENDURANCE_RECOVERY_PER_HOUR * elapsed, 0, 1)
        return
    end
    if state.virtualX == nil then
        state.virtualX, state.virtualY, state.virtualZ = recordLocation(id)
    end
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    local sleepEnabled = needs ~= nil and needs.sleepRequired ~= nil and needs.sleepRequired() == true
    local cursor = hours - elapsed
    -- Split at rest/travel transitions rather than granting sleep while walking.
    -- All clocks and intent stay in the existing serializable survival ledger.
    for _ = 1, 8 do
        if cursor >= hours - 0.000001 then break end
        if state.restMode == "sleep" and (not sleepEnabled or state.fatigue <= WAKE_FATIGUE + 0.000001) then
            state.restMode = nil
        elseif state.restMode == "rest" and state.endurance >= RESUME_ENDURANCE - 0.000001 then
            state.restMode = nil
        end
        if state.restMode ~= "sleep" and state.restMode ~= "rest" then state.restMode = nil end
        if state.restMode == nil then
            if sleepEnabled and state.fatigue >= SLEEP_FATIGUE - 0.000001 then state.restMode = "sleep"
            elseif state.endurance <= REST_ENDURANCE + 0.000001 then state.restMode = "rest" end
        end
        local span = hours - cursor
        if state.restMode ~= nil then
            local sleeping = state.restMode == "sleep"
            local recoveryHours = sleeping and (state.fatigue - WAKE_FATIGUE) / FATIGUE_RECOVERY_PER_HOUR
                or (RESUME_ENDURANCE - state.endurance) / ENDURANCE_RECOVERY_PER_HOUR
            span = math.min(span, math.max(0.000001, recoveryHours))
            state.fatigue = clamp(state.fatigue + (sleeping and -FATIGUE_RECOVERY_PER_HOUR
                or (sleepEnabled and AWAKE_FATIGUE_PER_HOUR or 0)) * span, 0, 1)
            state.endurance = clamp(state.endurance + ENDURANCE_RECOVERY_PER_HOUR * span, 0, 1)
            setActivity(state, sleeping and "sleeping" or "resting", cursor)
        else
            span = math.min(span, math.max(0.000001,
                (state.endurance - REST_ENDURANCE) / WALK_ENDURANCE_PER_HOUR))
            if sleepEnabled then
                span = math.min(span, math.max(0.000001,
                    (SLEEP_FATIGUE - state.fatigue) / AWAKE_FATIGUE_PER_HOUR))
            end
            local moving = clamp(cohort ~= nil and cohort.move(span, cursor + span)
                or advanceWorldActivity(id, state, span, cursor + span), 0, span)
            state.endurance = clamp(state.endurance - WALK_ENDURANCE_PER_HOUR * moving
                + ENDURANCE_RECOVERY_PER_HOUR * (span - moving), 0, 1)
            if sleepEnabled then state.fatigue = clamp(state.fatigue + AWAKE_FATIGUE_PER_HOUR * span, 0, 1) end
        end
        if cohort ~= nil then
            state.fatigue, state.endurance = cohort.apply(span, state.restMode, sleepEnabled,
                state.activity, cursor + span)
        end
        cursor = cursor + span
    end
    state.virtualAtHours = hours
end

function Simulation.captureLoaded(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or type(id) ~= "string" or not validNeeds(snapshot) then
        return false
    end
    local state = ensureState(id, snapshot, tonumber(hours) or nowHours())
    state.hunger = clamp(snapshot.hunger, 0, 1)
    state.thirst = clamp(snapshot.thirst, 0, 1)
    state.fatigue = clamp(snapshot.fatigue, 0, 1)
    state.endurance = clamp(snapshot.endurance, 0, 1)
    state.health = clamp(snapshot.health, 0, 100)
    state.bleedingParts = math.max(0, math.floor(tonumber(snapshot.bleedingParts) or 0))
    state.pain = tonumber(snapshot.pain)
    state.lastHours = tonumber(hours) or nowHours()
    state.status = "loaded"
    state.pendingMaterialization = nil
    state.eventEntryId = nil
    state.travelTarget, state.departAtHours = nil, nil
    state.currentTravelKey, state.previousTravelKey, state.travelSequence = nil, nil, nil
    state.travelPhase, state.restMode = nil, nil
    -- captureActiveSurvivor has already saved the real current body. Old virtual
    -- coordinates must not win over movement performed since its last activation.
    local x, y, z = recordLocation(id)
    state.virtualX, state.virtualY, state.virtualZ = x, y, z
    state.virtualAtHours = state.lastHours
    return persistence.setUnloadedSurvivalState(id, state)
end

function Simulation.markStored(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState ~= nil
        and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or state.pendingMaterialization == true then
        return false, "real_survival_snapshot_required"
    end
    state.status = "hibernated"
    state.lastHours = tonumber(hours) or state.lastHours or nowHours()
    if persistence.setUnloadedSurvivalState(id, state) ~= true then
        return false, "storage_persistence_failed"
    end
    return true, "stored"
end

-- A dispatch may reserve a stored ledger before native body removal. If the
-- later team/teardown step aborts while that body is still live, return only
-- ledger ownership to the loaded shell; its already-captured identity,
-- inventory, equipment and need state remain authoritative.
function Simulation.rollbackStored(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState ~= nil
        and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or state.pendingMaterialization == true then
        return false, "real_survival_snapshot_required"
    end
    local now = tonumber(hours) or nowHours()
    state.status = "loaded"
    state.activity = "loaded"
    state.activitySinceHours = now
    state.lastHours = now
    if persistence.setUnloadedSurvivalState(id, state) ~= true then
        return false, "stored_rollback_persistence_failed"
    end
    return true, "stored_rollback_loaded"
end

-- Starts a durable off-screen trip to an existing base. The caller is
-- responsible for capturing/removing the active shell first; this function
-- records only the virtual route and never creates or relocates a world body.
function Simulation.beginBaseReturn(id, base, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local area = type(base) == "table" and (base.territory or base.home) or nil
    if persistence == nil or type(id) ~= "string" or area == nil
        or tonumber(area.minX) == nil or tonumber(area.minY) == nil then
        return false, "base_destination_unavailable"
    end
    local now = tonumber(hours) or nowHours()
    local state = persistence.getUnloadedSurvivalState(id)
    if state == nil or state.pendingMaterialization == true then
        return false, "real_survival_snapshot_required"
    end
    -- captureActiveSurvivor has just written the current engine position into
    -- the record. Prefer that fresh location over any old virtual route.
    local x, y, z = recordLocation(id)
    if x == nil or y == nil or z == nil then
        x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
    end
    if x == nil or y == nil then
        return false, "return_origin_unavailable"
    end
    local width, height = areaDimensions(area)
    state.virtualX, state.virtualY, state.virtualZ = x, y, tonumber(z) or 0
    state.virtualAtHours = now
    -- A foot route home supersedes any vehicle leg: trips never reroute trips.
    state.vehicleTrip = nil
    state.baseReturn = {
        baseId = tostring(base.id or ""),
        targetX = math.floor(tonumber(area.minX)) + math.floor((width - 1) / 2),
        targetY = math.floor(tonumber(area.minY)) + math.floor((height - 1) / 2),
        targetZ = area.allFloors == true and (tonumber(z) or 0) or (tonumber(area.z) or tonumber(z) or 0),
        startedAtHours = now,
    }
    setActivity(state, "returning_to_base", now)
    if persistence.setUnloadedSurvivalState(id, state) ~= true then
        return false, "base_return_persistence_failed"
    end
    return true, "base_return_started"
end

-- A virtual return is prepared while its live shell still exists.  If native
-- removal then fails, retain the captured body state but return ledger
-- ownership to that live shell; no body is recreated or relocated here.
function Simulation.rollbackBaseReturn(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState ~= nil
        and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or state.pendingMaterialization == true then
        return false, "real_survival_snapshot_required"
    end
    local rolledBack, result = Simulation.rollbackStored(id, hours)
    if not rolledBack then
        return false, result == "stored_rollback_persistence_failed"
            and "base_return_rollback_persistence_failed" or result
    end
    state = persistence.getUnloadedSurvivalState(id)
    state.baseReturn = nil
    if persistence.setUnloadedSurvivalState(id, state) ~= true then
        return false, "base_return_rollback_persistence_failed"
    end
    return true, "base_return_rolled_back"
end

local function advanceOne(id, state, hours, activityAdvanced)
    -- Legacy narrative rides had no vehicle/resource owner. Discard only the
    -- unsupported trip; retain captured position, needs, inventory and intent.
    state.vehicleTrip = nil
    local elapsed = math.max(0, hours - (tonumber(state.lastHours) or hours))
    if elapsed <= 0 then
        return state, nil
    end
    local hungerBefore = clamp(state.hunger, 0, 1)
    local thirstBefore = clamp(state.thirst, 0, 1)
    state.hunger = clamp(hungerBefore + HUNGER_PER_HOUR * elapsed, 0, 1)
    state.thirst = clamp(thirstBefore + THIRST_PER_HOUR * elapsed, 0, 1)
    if not activityAdvanced then advanceRestAndTravel(id, state, elapsed, hours) end
    local events = {}
    if state.thirst >= WATER_TRIGGER then
        for _ = 1, 4 do
            if state.thirst <= WATER_AFTER_DRINK + 0.00001 then break end
            local consumed, evidence, hunger, thirst = consumeAvailableSupply(id, "water", state.thirst - WATER_AFTER_DRINK, state, hours)
            if not consumed then break end
            state.hunger = clamp(state.hunger - hunger, 0, 1)
            state.thirst = clamp(state.thirst - thirst, 0, 1)
            events[#events + 1] = "drank=" .. evidence
            if thirst <= 0 then break end
        end
    end
    if state.hunger >= FOOD_TRIGGER then
        for _ = 1, 4 do
            if state.hunger <= FOOD_AFTER_MEAL + 0.00001 then break end
            local consumed, evidence, hunger, thirst = consumeAvailableSupply(id, "food", state.hunger - FOOD_AFTER_MEAL, state, hours)
            if not consumed then break end
            state.hunger = clamp(state.hunger - hunger, 0, 1)
            state.thirst = clamp(state.thirst - thirst, 0, 1)
            events[#events + 1] = "ate=" .. evidence
            if hunger <= 0 then break end
        end
    end
    if state.hunger >= 0.95 then
        local exposed = hoursAboveThreshold(
            hungerBefore, HUNGER_PER_HOUR, elapsed, 0.95
        )
        state.health = clamp(state.health - STARVATION_DAMAGE_PER_HOUR * exposed, 0, 100)
        events[#events + 1] = "starving"
    end
    if state.thirst >= 0.95 then
        local exposed = hoursAboveThreshold(
            thirstBefore, THIRST_PER_HOUR, elapsed, 0.95
        )
        state.health = clamp(state.health - DEHYDRATION_DAMAGE_PER_HOUR * exposed, 0, 100)
        events[#events + 1] = "dehydrated"
    end
    local stories = rawget(_G, "KnoxOffscreenStories")
    if stories ~= nil and stories.resolveFor ~= nil and state.status == "hibernated"
        and (tonumber(state.health) or 0) > 0 then
        local storyOk, storyEvent = pcall(stories.resolveFor, id, state, hours, elapsed)
        if storyOk and storyEvent ~= nil then
            events[#events + 1] = "story:" .. tostring(storyEvent)
        end
    end
    state.lastHours = hours
    state.status = state.health <= 0 and "dead" or "hibernated"
    return state, #events > 0 and table.concat(events, ",") or nil
end

function Simulation.advanceHibernated(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or not survivorPresent(persistence, id) or persistence.getRecord(id) == nil then
        return false, "not_hibernated"
    end
    if not nativeBodyAbsent(id) then return false, "native_body_not_absent" end
    local targetHours = tonumber(hours) or nowHours()
    local state = persistence.getUnloadedSurvivalState(id)
    if state == nil or state.pendingMaterialization == true then
        return false, "real_survival_snapshot_required"
    end
    if not validNeeds(state) or not finite(state.lastHours) or not finite(targetHours) then
        return false, "invalid_survival_state"
    end
    local events = {}
    while (tonumber(state.lastHours) or targetHours) < targetHours do
        local stepHours = math.min(
            targetHours,
            (tonumber(state.lastHours) or targetHours) + MAX_STEP_HOURS
        )
        local nextState, event = advanceOne(id, state, stepHours)
        state = nextState
        if event ~= nil then
            events[#events + 1] = event
        end
        if state.status == "dead" then
            break
        end
    end
    persistence.setUnloadedSurvivalState(id, state)
    if state.status == "dead" then
        persistence.markSurvivorDead(id, targetHours, "unloaded_survival", {
            locationSource = "logical", corpseState = "logical_only",
        })
        return true, "died"
    end
    return true, #events > 0 and table.concat(events, ",") or "advanced"
end

local function pendingMeetOrder(intent)
    if type(intent) ~= "table" then return -math.huge, "" end
    return tonumber(intent.atHours) or -math.huge, tostring(intent.pairPhase or "")
end

local function mergeConcurrentStoryFields(state, latest)
    if type(state) ~= "table" or type(latest) ~= "table" then return state end
    local stateHours, stateToken = pendingMeetOrder(state.pendingMeet)
    local latestHours, latestToken = pendingMeetOrder(latest.pendingMeet)
    if latestHours > stateHours or (latestHours == stateHours and latestToken > stateToken) then
        state.pendingMeet = latest.pendingMeet
        state.lastOffscreenMeetToken = latest.lastOffscreenMeetToken
    elseif state.pendingMeet == nil and latest.lastOffscreenMeetToken ~= nil then
        -- A pair token can remain after loaded code consumed the intent. Keep
        -- it for same-phase idempotency without resurrecting the intent.
        state.lastOffscreenMeetToken = latest.lastOffscreenMeetToken
    end
    return state
end

local function advanceStoredGroup(group, active, hours)
    local persistence = KnoxPersistence
    local event = group.kind == "faction_raid" or group.kind == "faction_entry"
    local eventRuntime = rawget(_G, "KnoxEventRuntime")
    if event and (eventRuntime == nil or (group.phase ~= "approaching"
        and group.phase ~= "withdrawing" and group.phase ~= "active" and group.phase ~= "objective")) then return nil end
    local members, seen = {}, {}
    local start = 0
    -- Validate the whole cohort before changing anything. Companion/base/mission
    -- duties and active bodies remain owned by their existing controllers.
    for _, id in ipairs(group.memberIds or {}) do
        if not seen[id] and persistence.isSurvivorAlive(id) then
            seen[id] = true
            local duty = persistence.getSurvivorDuty(id)
            if not (event and group.phase == "withdrawing" and (duty == nil or duty.eventId ~= group.id)) then
                local state = persistence.getUnloadedSurvivalState(id)
                -- Never probe native ownership or scan county groups for an
                -- origin that has no captured body/needs to simulate here.
                if active[id] or persistence.getRecord(id) == nil or state == nil
                    or state.pendingMaterialization or not finite(state.lastHours)
                    or not validNeeds(state) then return nil end
                local canonical = persistence.getTravelGroupFor(id)
                local ownsTravel = duty ~= nil and (event and duty.eventId == group.id
                    or (not event and duty.mode == "autonomous" and canonical ~= nil and canonical.id == group.id))
                if not ownsTravel or not nativeBodyAbsent(id) then return nil end
                if state.virtualX == nil then
                    state.virtualX, state.virtualY, state.virtualZ = recordLocation(id)
                end
                if not finite(state.virtualX) or not finite(state.virtualY) or not finite(state.virtualZ)
                    or not finite(state.fatigue) or not finite(state.endurance) then return nil end
                start = math.max(start, state.lastHours)
                members[#members + 1] = { id = id, state = state }
            end
        end
    end
    if #members < (event and 1 or 2) or start > hours then return nil end
    table.sort(members, function(a, b) return a.id < b.id end)
    local anchor, ids = members[1], {}
    for _, member in ipairs(members) do
        ids[#ids + 1] = member.id
        if member.id == group.leaderId then anchor = member end
    end
    for _, member in ipairs(members) do
        if member.state.virtualZ ~= anchor.state.virtualZ then return nil end
    end
    local results = {}
    -- Different capture times cannot grant earlier movement to the later member.
    -- Catch up physiology in place before starting the shared interval.
    for _, member in ipairs(members) do
        if member.state.lastHours < start then
            local ok, result = Simulation.advanceHibernated(member.id, start)
            if ok then results[member.id] = result end
            member.state = persistence.getUnloadedSurvivalState(member.id)
            if not survivorPresent(persistence, member.id) then return results end
        end
    end
    local signature = table.concat(ids, ":") .. ":leader:" .. anchor.id
    local shared = group.unloadedTravel
    if type(shared) ~= "table" or shared.members ~= signature or shared.lastHours ~= start
        or shared.virtualX ~= anchor.state.virtualX or shared.virtualY ~= anchor.state.virtualY
        or shared.virtualZ ~= anchor.state.virtualZ then
        shared = { members = signature, lastHours = start, virtualX = anchor.state.virtualX,
            virtualY = anchor.state.virtualY, virtualZ = anchor.state.virtualZ }
        -- Membership/capture changes discard stale routing, not existing rest.
        for _, member in ipairs(members) do
            if member.state.restMode == "sleep" then shared.restMode = "sleep" break end
            if member.state.restMode == "rest" then shared.restMode = "rest" end
        end
    end
    local function condition()
        local fatigue, endurance = 0, 1
        for _, member in ipairs(members) do
            fatigue = math.max(fatigue, member.state.fatigue)
            endurance = math.min(endurance, member.state.endurance)
        end
        return fatigue, endurance
    end
    local moved = {}
    local cohort = {}
    cohort.move = function(span, atHours)
        moved = {}
        local regroup = shared.regrouping == true
        for _, member in ipairs(members) do
            local dx = member.state.virtualX - anchor.state.virtualX
            local dy = member.state.virtualY - anchor.state.virtualY
            if dx * dx + dy * dy > GROUP_REGROUP_DISTANCE * GROUP_REGROUP_DISTANCE then regroup = true end
        end
        if regroup then
            local stillSeparated, movingHours = false, 0
            for _, member in ipairs(members) do
                local state = member.state
                local dx, dy = anchor.state.virtualX - state.virtualX, anchor.state.virtualY - state.virtualY
                local distance = math.sqrt(dx * dx + dy * dy)
                local travel = math.min(math.max(0, distance - GROUP_REJOIN_DISTANCE), RETURN_TILES_PER_HOUR * span)
                if travel > 0 then
                    state.virtualX = state.virtualX + dx / distance * travel
                    state.virtualY = state.virtualY + dy / distance * travel
                end
                moved[member.id] = travel / RETURN_TILES_PER_HOUR
                movingHours = math.max(movingHours, moved[member.id])
                if distance - travel > GROUP_REJOIN_DISTANCE + .000001 then stillSeparated = true end
            end
            shared.regrouping = stillSeparated or nil
            setActivity(shared, "group_regrouping", atHours)
            return movingHours
        end
        local x, y = shared.virtualX, shared.virtualY
        local population = rawget(_G, "KnoxWorldPopulation")
        local movingHours = 0
        if event then
            local destination = eventRuntime.destination(group, anchor.id)
            if destination ~= nil and (group.phase == "approaching" or group.phase == "withdrawing") then
                local dx, dy = destination.x - x, destination.y - y
                local distance = math.sqrt(dx * dx + dy * dy)
                local travel = math.min(distance, RETURN_TILES_PER_HOUR * span)
                if distance > 0 then
                    shared.virtualX, shared.virtualY = x + dx / distance * travel, y + dy / distance * travel
                end
                if travel >= distance then shared.virtualZ = destination.z end
                movingHours = travel / RETURN_TILES_PER_HOUR
            end
        else
            local scoutHandled, _, scoutHours = false, nil, 0
            if anchor.id == group.leaderId and population ~= nil
                and population.advanceFactionScout ~= nil then
                scoutHandled, _, scoutHours = population.advanceFactionScout(
                    group, shared, atHours-span, atHours)
            end
            if scoutHandled then
                movingHours = clamp(scoutHours, 0, span)
            else
            local objective = persistence.getTravelGroupObjective ~= nil
                and persistence.getTravelGroupObjective(group.id) or nil
            local objectiveOwnsTravel = objective ~= nil
                and (objective.phase == "seeking" or objective.phase == "traveling")
                and finite(objective.targetX) and finite(objective.targetY)
                and finite(objective.targetZ) and objective.targetZ == shared.virtualZ
            local hourOfDay = atHours - math.floor(atHours / 24) * 24
            local nightShelter = objective ~= nil and objective.kind == "night_shelter"
            local night = hourOfDay < 7 or hourOfDay >= 20
            if nightShelter and not night then
                -- A temporary refuge expires at dawn. It is only a group
                -- travel/rest objective, never a hidden camp or base claim.
                persistence.clearTravelGroupObjective(group.id, anchor.id)
                persistence.clearSurvivorLifeIntent(anchor.id)
                objective = nil
                objectiveOwnsTravel = false
            elseif nightShelter and objective.phase == "arrived" then
                for _, member in ipairs(members) do
                    member.state.restMode = "sleep"
                end
                setActivity(shared, "sheltering", atHours)
                return 0
            end
            if objectiveOwnsTravel then
                if shared.objectiveRevision ~= objective.revision then
                    -- A new leader purpose supersedes a stale random itinerary.
                    shared.travelTarget = nil
                    shared.departAtHours = nil
                    shared.objectiveRevision = objective.revision
                end
                local dx = objective.targetX - x
                local dy = objective.targetY - y
                local distance = math.sqrt(dx * dx + dy * dy)
                local travel = math.min(distance, RETURN_TILES_PER_HOUR * span)
                if distance > 0 then
                    shared.virtualX = x + dx / distance * travel
                    shared.virtualY = y + dy / distance * travel
                end
                movingHours = travel / RETURN_TILES_PER_HOUR
                if travel >= distance then
                    shared.virtualX = objective.targetX
                    shared.virtualY = objective.targetY
                    shared.virtualZ = objective.targetZ
                    objective.phase = nightShelter and "arrived" or "reassess"
                    objective.targetKey = nil
                    objective.targetX, objective.targetY, objective.targetZ = nil, nil, nil
                    objective.startedAtHours = objective.startedAtHours or atHours
                    persistence.setSurvivorLifeIntent(anchor.id, objective, atHours)
                    persistence.setTravelGroupObjective(group.id, anchor.id, objective, atHours)
                    local updated = persistence.getTravelGroupObjective(group.id)
                    shared.objectiveRevision = updated ~= nil and updated.revision
                        or shared.objectiveRevision
                    shared.departAtHours = atHours + 2
                end
            elseif population ~= nil and population.advanceItinerary ~= nil then
                local advanced, _, travelHours = population.advanceItinerary(
                    group.id,
                    shared,
                    atHours - span,
                    atHours
                )
                if advanced then movingHours = clamp(travelHours, 0, span) end
            end
            end
        end
        local dx, dy = shared.virtualX - x, shared.virtualY - y
        for _, member in ipairs(members) do
            member.state.virtualX = member.state.virtualX + dx
            member.state.virtualY = member.state.virtualY + dy
            if event then member.state.virtualZ = shared.virtualZ end
            moved[member.id] = movingHours
        end
        local objective = not event and persistence.getTravelGroupObjective ~= nil
            and persistence.getTravelGroupObjective(group.id) or nil
        setActivity(shared, event and (movingHours > 0 and "event_travel" or "event_waiting")
            or (movingHours > 0 and objective ~= nil
                    and (objective.phase == "seeking" or objective.phase == "traveling")
                and "group_objective"
                or (movingHours > 0 and "group_travel" or "sheltering")), atHours)
        return movingHours
    end
    cohort.apply = function(span, restMode, sleepEnabled, activity, atHours)
        for _, member in ipairs(members) do
            local state = member.state
            local moving = restMode == nil and (moved[member.id] or 0) or 0
            state.endurance = clamp(state.endurance - WALK_ENDURANCE_PER_HOUR * moving
                + ENDURANCE_RECOVERY_PER_HOUR * (span - moving), 0, 1)
            local fatigueRate = restMode == "sleep" and -FATIGUE_RECOVERY_PER_HOUR
                or (sleepEnabled and AWAKE_FATIGUE_PER_HOUR or 0)
            state.fatigue = clamp(state.fatigue + fatigueRate * span, 0, 1)
            state.restMode = restMode
            state.virtualAtHours = atHours
            setActivity(state, activity, atHours)
        end
        return condition()
    end
    while start < hours do
        local socialBefore=not event and KnoxGroupCohesion.snapshot(members) or nil
        local step = math.min(hours, start + MAX_STEP_HOURS)
        shared.fatigue, shared.endurance = condition()
        advanceRestAndTravel(anchor.id, shared, step - start, step, cohort)
        -- Condition is derived from real member ledgers, not a parallel group stat.
        shared.fatigue, shared.endurance = nil, nil
        local died = false
        for _, member in ipairs(members) do
            local state, event = advanceOne(member.id, member.state, step, true)
            -- Another member's storylet may have written a symmetric pending
            -- intent into this ledger after the cohort snapshots were loaded.
            -- Merge only the concurrent story-owned pair fields; the current
            -- member still owns physiology, position, history, and activity.
            local latest = persistence.getUnloadedSurvivalState(member.id)
            state = mergeConcurrentStoryFields(state, latest)
            member.state = state
            persistence.setUnloadedSurvivalState(member.id, state)
            if state.status == "dead" then
                persistence.markSurvivorDead(member.id, step, "unloaded_survival")
                results[member.id], died = "died", true
            elseif event ~= nil then
                results[member.id] = results[member.id] ~= nil and results[member.id] ~= "advanced"
                    and (results[member.id] .. "," .. event) or event
            else results[member.id] = results[member.id] or "advanced" end
        end
        if not event and not died then KnoxGroupCohesion.record(group,socialBefore,members,step) end
        shared.lastHours = step
        group.unloadedTravel = shared
        start = step
        -- Death may replace the leader or dissolve the group. Rebuild the cohort
        -- from canonical membership on the next reconciliation, never resurrect it.
        if died then break end
    end
    for _, member in ipairs(members) do results[member.id] = results[member.id] or "advanced" end
    return results
end

function Simulation.advanceAll(activeIds, hours)
    local active = {}
    for _, id in ipairs(activeIds or {}) do
        active[id] = true
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then
        return 0, 0
    end
    local targetHours = tonumber(hours) or nowHours()
    if not finite(targetHours) then return 0, 0 end
    local advanced, notable = 0, 0
    local ids = persistence.getActivatableSurvivorIds()
    local membership = persistence.getTravelGroupsFor ~= nil
        and persistence.getTravelGroupsFor(ids) or nil
    local groups, groupIds, handled = {}, {}, {}
    for _, id in ipairs(ids) do
        local group = membership ~= nil and membership[id] or nil
        if membership == nil and persistence.getTravelGroupFor ~= nil then
            group = persistence.getTravelGroupFor(id)
        end
        if group ~= nil and not groups[group.id] then
            groups[group.id] = group
            groupIds[#groupIds + 1] = group.id
        end
    end
    table.sort(groupIds)
    local events = rawget(_G, "KnoxEvents")
    if events ~= nil then
        for _, eventId in ipairs(events.activeIds()) do
            local event = events.get(eventId)
            local _, reason = events.validate(event)
            if event ~= nil and reason ~= "invalid_event_record" then
                local key = "event:" .. eventId
                groups[key] = event
                table.insert(groupIds, 1, key)
            end
        end
    end
    for _, groupId in ipairs(groupIds) do
        local results = advanceStoredGroup(groups[groupId], active, targetHours)
        if results ~= nil and (groups[groupId].kind == "faction_raid"
            or groups[groupId].kind == "faction_entry") then
            events.saveUnloadedTravel(groups[groupId].id, groups[groupId].revision, groups[groupId].unloadedTravel)
        end
        for id, result in pairs(results or {}) do
            handled[id] = true
            advanced = advanced + 1
            if result ~= "advanced" then
                notable = notable + 1
                print("[KnoxSurvivors][Unloaded] id=" .. id .. " event=" .. tostring(result))
            end
        end
    end
    -- Stored/event steps may remove people or change canonical group membership.
    -- Build a fresh candidate set for this synchronous origin-travel phase only.
    local originGroupCandidates
    if persistence.getTravelGroupsFor ~= nil then
        local unused
        unused, originGroupCandidates = persistence.getTravelGroupsFor(ids)
    end
    for _, id in ipairs(ids) do
        local record = persistence.getRecord(id)
        local duty = persistence.getSurvivorDuty ~= nil
            and persistence.getSurvivorDuty(id) or nil
        local state = persistence.getUnloadedSurvivalState ~= nil
            and persistence.getUnloadedSurvivalState(id) or nil
        local task = nil
        if type(duty) == "table" and duty.mode == "base"
            and type(duty.baseId) == "string" then
            local base = persistence.getBase ~= nil
                and persistence.getBase(duty.baseId) or nil
            for _, candidate in pairs(base ~= nil and base.tasks or {}) do
                if type(candidate) == "table"
                    and candidate.state == "claimed"
                    and candidate.claimedBy == id then
                    task = candidate
                    break
                end
            end
        end
        if not active[id] and record == nil then
            local population = rawget(_G, "KnoxWorldPopulation")
            if population ~= nil and population.advanceOriginTravel ~= nil then
                local ok = population.advanceOriginTravel(id, targetHours, originGroupCandidates)
                if ok then advanced = advanced + 1 end
            end
        elseif not active[id] and not handled[id] and record ~= nil then
            -- A claimed base job does not suspend physiology.  The ordinary
            -- stored-survivor path also advances the only jobs that are safe
            -- to simulate without a loaded square (guard/patrol watch shifts).
            -- Physical jobs remain native-only and are handled by the bounded
            -- claim-wait policy below.
            local ok, result = Simulation.advanceHibernated(id, targetHours)
            if ok then
                advanced = advanced + 1
                if result ~= "advanced" then
                    notable = notable + 1
                    print("[KnoxSurvivors][Unloaded] id=" .. id .. " event=" .. tostring(result))
                end
            end
            state = persistence.getUnloadedSurvivalState ~= nil
                and persistence.getUnloadedSurvivalState(id) or nil
            local stillOwnsTask = task ~= nil and task.state == "claimed"
                and task.claimedBy == id and survivorPresent(persistence, id)
            local abstractable = stillOwnsTask and state ~= nil
                and KnoxBaseDutySimulation ~= nil
                and KnoxBaseDutySimulation.canAdvanceOffscreen ~= nil
                and KnoxBaseDutySimulation.canAdvanceOffscreen(task)
            local returningHome = state ~= nil and type(state.baseReturn) == "table"
            if stillOwnsTask and not abstractable and returningHome then
                -- Returning is not waiting to execute a native job. Preserve
                -- its claim and activity, and exclude journey time from the
                -- later unloaded execution timeout.
                task.offscreenLastHours = targetHours
            elseif stillOwnsTask and not abstractable then
                -- World-changing jobs stay native-only, but an automatic claim
                -- must not reserve settlement work forever while its square is
                -- streamed out. A missing survival ledger cannot strand the
                -- claim either. Manual Notebook assignments remain intact.
                local previousTaskHours = tonumber(task.offscreenLastHours)
                    or tonumber(task.claimedAtHours) or targetHours
                local taskElapsed = math.max(0, targetHours - previousTaskHours)
                task.offscreenLastHours = targetHours
                task.offscreenWaitHours = (tonumber(task.offscreenWaitHours) or 0)
                    + taskElapsed
                if task.offscreenWaitHours >= PHYSICAL_TASK_OFFSCREEN_WAIT_HOURS
                    and task.manual ~= true
                    and persistence.releaseBaseTaskClaim ~= nil then
                    local released, releaseResult = persistence.releaseBaseTaskClaim(
                        duty.baseId,
                        task.id,
                        id,
                        "unloaded_execution_wait",
                        targetHours
                    )
                    if released ~= nil then
                        task = nil
                        if state ~= nil then setActivity(state, "base_life", targetHours) end
                    else
                        print("[KnoxSurvivors][Unloaded] base-claim-release-failed id="
                            .. tostring(id) .. " task=" .. tostring(task.id)
                            .. " result=" .. tostring(releaseResult))
                    end
                end
                if task ~= nil and state ~= nil then
                    setActivity(state, "base_working", targetHours)
                end
            end
            if state ~= nil and persistence.setUnloadedSurvivalState ~= nil then
                persistence.setUnloadedSurvivalState(id, state)
            end
        end
    end
    return advanced, notable
end

function Simulation.applyToLoaded(id, character)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or character == nil then
        return false, "no_stored_state"
    end
    if state.pendingMaterialization == true then
        return false, "no_real_survival_snapshot"
    end
    if not validNeeds(state) then return false, "invalid_survival_state" end
    local ok, evidence = pcall(function()
        local stats = character:getStats()
        stats:set(CharacterStat.HUNGER, clamp(state.hunger, 0, 1))
        stats:set(CharacterStat.THIRST, clamp(state.thirst, 0, 1))
        stats:set(CharacterStat.FATIGUE, clamp(state.fatigue, 0, 1))
        stats:set(CharacterStat.ENDURANCE, clamp(state.endurance, 0, 1))
        local bodyDamage = character:getBodyDamage()
        -- BodyDamage has no setHealth() in Build 42.20.3.  The aggregate
        -- body-health setter is the supported counterpart to getHealth(); the
        -- old call was caught by pcall, so a survivor still spawned but every
        -- spawn produced a Lua error and skipped its unloaded-health restore.
        bodyDamage:setOverallBodyHealth(clamp(state.health, 0, 100))
    end)
    if ok then
        state.status = "loaded"
        -- A stale/rolled-back clock must never make the next hibernation pass
        -- replay elapsed off-screen time after materialization.
        state.lastHours = math.max(tonumber(state.lastHours) or 0, nowHours())
        local stories = rawget(_G, "KnoxOffscreenStories")
        -- Retire legacy narrative travel without claiming a real ride ended.
        state.vehicleTrip = nil
        persistence.setUnloadedSurvivalState(id, state)
        if stories ~= nil and stories.resolveScars ~= nil then
            pcall(stories.resolveScars, id, character, nowHours())
        end
        return true, "applied"
    end
    return false, tostring(evidence)
end

return Simulation
