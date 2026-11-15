require "KS_CompanionVehicles"
require "KS_SurvivorRuntime"

-- Loaded-world transport for autonomous travel groups. This deliberately
-- reuses the native boarding and driving boundary: faction transport cannot
-- teleport, create a vehicle, bypass a locked seat, or drive a player car.
-- If no safe vehicle or route exists, normal on-foot travel stays in control.
local VehicleTravel = rawget(_G, "KnoxNpcVehicleTravel") or {}
_G.KnoxNpcVehicleTravel = VehicleTravel

local MIN_TRIP_DISTANCE_SQUARED = 60 * 60
local SEARCH_DISTANCE_SQUARED = 28 * 28
local PLAYER_EXCLUSION_DISTANCE_SQUARED = 45 * 45
local RETRY_TICKS = 600

local function distanceSquared(first, second)
    local dx, dy = first:getX() - second:getX(), first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function currentPlayers()
    local result, count = {}, getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer ~= nil and getSpecificPlayer(playerNum) or nil
        if player ~= nil then result[#result + 1] = player end
    end
    return result
end

local function playerOwnsOrIsNear(vehicle)
    for _, player in ipairs(currentPlayers()) do
        if player:getVehicle() == vehicle then return true end
        local square = player:getCurrentSquare()
        if square ~= nil and square:getZ() == vehicle:getZ()
            and distanceSquared(player, vehicle) <= PLAYER_EXCLUSION_DISTANCE_SQUARED then
            return true
        end
    end
    return false
end

-- Shared admission verdict for one parked vehicle: intrinsic native state
-- only (driver, engine, driveability, speed, towing, fuel, locks). Returns
-- true plus "vehicle_ready", or false plus a snake_case reason reusing the
-- KS_CompanionVehicles drive-admission vocabulary where the meaning matches.
-- Discovery position/player filters stay in safeVehicle below; drive admission
-- in KS_CompanionVehicles consumes these same reason strings. Native fuel
-- evidence: BaseVehicle:getRemainingFuelPercentage() as used by the shipped
-- ISVehicleDashboard; native lock evidence: BaseVehicle:areAllDoorsLocked().
-- A sub-1% tank reads as unfueled; that threshold is implementation policy
-- awaiting live pacing evidence, not a native fuel rule. Missing optional
-- native methods fail closed with "vehicle_state_unknown" rather than an
-- invented usable verdict. Locked vehicles are rejected here; forced entry
-- remains an explicitly deferred future track.
local LOW_FUEL_PERCENT = 1
-- Build 42 key evidence, audited against the installed jar: BaseVehicle exposes
-- isKeysInIgnition(), isHotwired(), isHotwiredBroken(), getKeyId(), and
-- IsoPlayer inventory exposes haveThisKeyId(int). A vehicle is admitted only
-- when one of those real states allows it; an absent reader fails closed.
function VehicleTravel.keyAdmission(vehicle, character)
    if vehicle == nil then return false, "vehicle_missing" end
    if vehicle.isKeysInIgnition == nil or vehicle.isHotwired == nil
        or vehicle.getKeyId == nil then
        return false, "vehicle_state_unknown"
    end
    local ignitionOk, ignition = pcall(function() return vehicle:isKeysInIgnition() end)
    if not ignitionOk then return false, "vehicle_state_unknown" end
    if ignition == true then return true, "keys_in_ignition" end
    local hotwireOk, hotwired = pcall(function() return vehicle:isHotwired() end)
    if not hotwireOk then return false, "vehicle_state_unknown" end
    if hotwired == true then
        if vehicle.isHotwiredBroken ~= nil then
            local brokenOk, broken = pcall(function() return vehicle:isHotwiredBroken() end)
            if not brokenOk then return false, "vehicle_state_unknown" end
            if broken == true then return false, "vehicle_engine_off" end
        end
        return true, "hotwired"
    end
    if character == nil or character.getInventory == nil then
        return false, "no_keys"
    end
    local keyOk, keyId = pcall(function() return vehicle:getKeyId() end)
    if not keyOk or tonumber(keyId) == nil then return false, "vehicle_state_unknown" end
    local inventoryOk, inventory = pcall(function() return character:getInventory() end)
    if not inventoryOk or inventory == nil or inventory.haveThisKeyId == nil then
        return false, "vehicle_state_unknown"
    end
    local haveOk, have = pcall(function() return inventory:haveThisKeyId(keyId) end)
    if not haveOk then return false, "vehicle_state_unknown" end
    if have == true then return true, "key_on_person" end
    return false, "no_keys"
end

function VehicleTravel.assessReadiness(vehicle, character)
    if vehicle == nil then return false, "vehicle_missing" end
    if vehicle.getDriver ~= nil and vehicle:getDriver() ~= nil
        and vehicle:getDriver() ~= character then
        return false, "driver_seat_occupied"
    end
    -- Key admission applies to parked cars too; the native start action decides
    -- whether their engine actually starts after the driver takes the seat.
    local keyed, keyReason = VehicleTravel.keyAdmission(vehicle, character)
    if not keyed then return false, keyReason end
    if vehicle.isEngineRunning == nil then return false, "vehicle_state_unknown" end
    if not vehicle:isEngineRunning() then
        local ok, inventory = pcall(function() return character:getInventory() end)
        if not ok or inventory == nil or inventory.haveThisKeyId == nil then
            return false, "vehicle_state_unknown"
        end
    end
    if vehicle.isDriveable == nil or not vehicle:isDriveable() then
        return false, "vehicle_not_driveable"
    end
    if vehicle.getCurrentSpeedKmHour ~= nil
        and math.abs(vehicle:getCurrentSpeedKmHour()) > 1 then
        return false, "vehicle_moving"
    end
    if vehicle.getVehicleTowing ~= nil and vehicle:getVehicleTowing() ~= nil
        or vehicle.getVehicleTowedBy ~= nil and vehicle:getVehicleTowedBy() ~= nil then
        return false, "towing_not_supported"
    end
    if vehicle.getRemainingFuelPercentage == nil then
        return false, "vehicle_state_unknown"
    end
    local fueled, percent = pcall(function() return vehicle:getRemainingFuelPercentage() end)
    if not fueled or (tonumber(percent) or 0) < LOW_FUEL_PERCENT then
        return false, "vehicle_low_fuel"
    end
    if vehicle.areAllDoorsLocked == nil then
        return false, "vehicle_state_unknown"
    end
    local checked, allLocked = pcall(function() return vehicle:areAllDoorsLocked() end)
    if not checked then return false, "vehicle_state_unknown" end
    if allLocked then return false, "vehicle_doors_locked" end
    return true, "vehicle_ready"
end

-- A claim belongs to a real faction, never to a transient driver-run record.
-- Existing assignments without claimSource keep their old run-only meaning.
function VehicleTravel.claimAdmission(character, vehicle, autonomous)
    local persistence, runtime = rawget(_G, "KnoxPersistence"), rawget(_G, "KnoxSurvivorRuntime")
    if persistence == nil or runtime == nil or runtime.idForCharacter == nil
        or persistence.getVehicleAssignmentFor == nil then
        return not autonomous, autonomous and "vehicle_claim_unavailable" or nil
    end
    local id = runtime.idForCharacter(character)
    local affiliation = id ~= nil and persistence.getSurvivorAffiliation ~= nil
        and persistence.getSurvivorAffiliation(id) or nil
    local factionId = type(affiliation) == "table" and affiliation.factionId or nil
    local record = persistence.getVehicleAssignmentFor(vehicle)
    if record ~= nil and record.claimSource == "autonomous" then
        if factionId == nil or record.ownerKind ~= "faction" or record.ownerId ~= tostring(factionId) then
            return false, "vehicle_claimed"
        end
    elseif autonomous and record ~= nil then
        return false, "vehicle_assigned"
    end
    if not autonomous then return true, record ~= nil and record.claimSource == "autonomous" and "owned_claim" or nil end
    local key = persistence.vehicleKeyFor ~= nil and persistence.vehicleKeyFor(vehicle) or nil
    local group = id ~= nil and persistence.getTravelGroupFor ~= nil and persistence.getTravelGroupFor(id) or nil
    if key == nil or factionId == nil or group == nil or group.leaderId ~= id
        or tostring(group.factionId or "") ~= tostring(factionId) then
        return false, "vehicle_claim_unavailable"
    end
    local bases = rawget(_G, "KnoxBaseManager")
    if persistence.getBases == nil or bases == nil or bases.containsSquare == nil
        or vehicle.getSquare == nil or vehicle:getSquare() == nil
        or getNumActivePlayers == nil or getSpecificPlayer == nil then
        return false, "vehicle_claim_unavailable"
    end
    local count = getNumActivePlayers()
    if count == nil or count < 1 then return false, "vehicle_claim_unavailable" end
    for i = 0, count - 1 do if getSpecificPlayer(i) == nil then return false, "vehicle_claim_unavailable" end end
    if playerOwnsOrIsNear(vehicle) then return false, "vehicle_player_near" end
    for _, base in pairs(persistence.getBases()) do
        if base.ownerKind == "player" and bases.containsSquare(base, vehicle:getSquare()) then
            return false, "vehicle_player_base"
        end
    end
    return true, record ~= nil and "owned_claim" or "unclaimed"
end

local function safeVehicle(vehicle, origin, character)
    if VehicleTravel.assessReadiness(vehicle, character) ~= true then return false end
    if VehicleTravel.claimAdmission(character, vehicle, false) ~= true then return false end
    if playerOwnsOrIsNear(vehicle) then return false end
    local square = vehicle:getSquare()
    return square ~= nil and square:getZ() == origin:getZ()
        and distanceSquared(origin, vehicle) <= SEARCH_DISTANCE_SQUARED
end

-- The nearest parked car a given survivor could actually drive. This is the
-- same admission group travel uses, so a car that cannot join a trip cannot be
-- fetched either. The optional candidate list keeps the search testable
-- without a live cell; callers in game pass nothing and get the cell scan.
local POLICE_SCRIPTS = {
    CarLightsPolice=true, PickUpVanLightsPolice=true, CarLightsLouisvilleCounty=true,
    ModernCarLightsCityLouisvillePD=true, CarLightsKST=true, CarLightsMuldraughPolice=true,
    PickUpVanLightsStatePolice=true, PickUpVanLightsLouisvilleCounty=true,
    StepVan_LouisvilleSWAT=true, CarLightsBulletinSheriff=true,
    ModernCarLightsMeadeSheriff=true, ModernCarLightsWestPoint=true,
}

function VehicleTravel.readyVehicleNear(character, candidates)
    local origin = character ~= nil and character.getCurrentSquare ~= nil
        and character:getCurrentSquare() or nil
    if origin == nil then return nil, "vehicle_missing" end
    local id = KnoxSurvivorRuntime ~= nil and KnoxSurvivorRuntime.idForCharacter ~= nil
        and KnoxSurvivorRuntime.idForCharacter(character) or nil
    local creator = id ~= nil and KnoxPersistence.getSurvivorCreatorRecord(id) or nil
    local originData = id ~= nil and KnoxPersistence.getSurvivorOrigin(id) or nil
    local police = creator ~= nil and creator.profile == "police"
        or originData ~= nil and originData.context == "law_enforcement"
    local military = creator ~= nil and creator.profile == "military"
        or originData ~= nil and originData.context == "military"
    local nearest, nearestDistance, preferred, preferredDistance, refusal = nil, nil, nil, nil, nil
    local claimed, claimedDistance = nil, nil
    for _, vehicle in ipairs(candidates or VehicleTravel.parkedVehicles()) do
        if safeVehicle(vehicle, origin, character) then
            local squared = distanceSquared(origin, vehicle)
            local _, ownership = VehicleTravel.claimAdmission(character, vehicle, false)
            if ownership == "owned_claim" and (claimed == nil or squared < claimedDistance) then
                claimed, claimedDistance = vehicle, squared
            end
            if nearest == nil or squared < nearestDistance then
                nearest, nearestDistance = vehicle, squared
            end
            if (police or military) and vehicle.getScriptName ~= nil then
                local ok, name = pcall(function() return vehicle:getScriptName() end)
                name = ok and type(name) == "string" and (name:match("([^%.]+)$") or name) or nil
                local lower = name ~= nil and string.lower(name) or ""
                local matches = police and POLICE_SCRIPTS[name]
                    or military and (string.find(lower, "military", 1, true) ~= nil
                        or string.find(lower, "army", 1, true) ~= nil)
                if matches and (preferred == nil or squared < preferredDistance) then
                    preferred, preferredDistance = vehicle, squared
                end
            end
        elseif refusal == nil then
            local _, reason = VehicleTravel.assessReadiness(vehicle, character)
            refusal = reason
        end
    end
    if claimed ~= nil then return claimed, "vehicle_ready" end
    if preferred ~= nil then return preferred, "vehicle_ready" end
    if nearest ~= nil then return nearest, "vehicle_ready" end
    return nil, refusal or "vehicle_unavailable"
end

-- Opening the map with several companions must not walk the cell's vehicle
-- list once per companion. The list itself is cached for a short window; every
-- readiness verdict is still re-evaluated per vehicle, so a car that was just
-- locked, started or emptied is judged honestly. A different vehicle count, or
-- a clock we cannot read, forces a fresh scan rather than a stale answer.
local VEHICLE_LIST_TTL_MS = 1000
local cachedVehicles, cachedVehicleSize, cachedVehicleAt = nil, nil, nil

function VehicleTravel.parkedVehicles()
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or cell.getVehicles == nil then return {} end
    local vehicles = cell:getVehicles()
    if vehicles == nil then return {} end
    local now = getTimestampMs ~= nil and getTimestampMs() or nil
    local size = vehicles.size ~= nil and vehicles:size() or nil
    if cachedVehicles ~= nil and now ~= nil and size == cachedVehicleSize
        and now >= cachedVehicleAt and now - cachedVehicleAt < VEHICLE_LIST_TTL_MS then
        return cachedVehicles
    end
    local result = {}
    if vehicles.iterator ~= nil then
        local iterator = vehicles:iterator()
        while iterator:hasNext() do result[#result + 1] = iterator:next() end
    else
        for index = 0, vehicles:size() - 1 do result[#result + 1] = vehicles:get(index) end
    end
    if now ~= nil then
        cachedVehicles, cachedVehicleSize, cachedVehicleAt = result, size, now
    end
    return result
end

local function vehiclesInCell()
    return VehicleTravel.parkedVehicles()
end

local function boardNearbyMembers(controller, vehicle)
    local roster = {}
    for _, member in ipairs(controller.groupMembers or {}) do
        if member ~= nil and member ~= controller.character and member:getVehicle() == nil
            and member:getCurrentSquare() ~= nil and member:getCurrentSquare():getZ() == vehicle:getZ()
            and distanceSquared(member, vehicle) <= SEARCH_DISTANCE_SQUARED then
            -- Seat exhaustion is an explicit outcome, not a silent skip: only
            -- committed members join the roster the abort path rolls back.
            local success = KnoxCompanionVehicles.board(member, vehicle)
            if success then roster[#roster + 1] = { member = member, vehicle = vehicle } end
        end
    end
    return roster
end

function VehicleTravel.tryBegin(controller, destination, ticks)
    if controller == nil or controller.character == nil or destination == nil
        or controller.companionOrder ~= nil or controller.baseTask ~= nil
        or ticks < (controller.nextNpcVehicleTravelAt or 0) then return false end
    local origin = controller.character:getCurrentSquare()
    local group = KnoxPersistence.getTravelGroupFor(controller.id)
    local dx = destination.x - controller.character:getX()
    local dy = destination.y - controller.character:getY()
    if origin == nil or group == nil or group.leaderId ~= controller.id
        or origin:getZ() ~= destination.z
        or dx * dx + dy * dy < MIN_TRIP_DISTANCE_SQUARED then return false end
    controller.nextNpcVehicleTravelAt = ticks + RETRY_TICKS
    local candidates = vehiclesInCell()
    -- Reuse our faction's car first; fall back to an eligible abandoned car.
    for pass = 1, 2 do
    for _, vehicle in ipairs(candidates) do
        local permitted, ownership = VehicleTravel.claimAdmission(controller.character, vehicle, true)
        if permitted and (pass == 1 and ownership == "owned_claim" or pass == 2 and ownership ~= "owned_claim")
            and safeVehicle(vehicle, origin, controller.character) then
            local started, reason = KnoxCompanionVehicles.driveTo(
                controller.character, vehicle, destination.x, destination.y, destination.z,
                {autonomousClaim=true}
            )
            if started then
                -- Failed routing/disabled driving must not strand passengers
                -- in a vehicle the leader will never drive.
                local roster = boardNearbyMembers(controller, vehicle)
                KnoxCompanionVehicles.setRunPassengers(controller.character, vehicle, roster)
                print("[KnoxSurvivors][VehicleTravel] leader=" .. tostring(controller.id)
                    .. " passengers=" .. tostring(#roster) .. " destination="
                    .. tostring(destination.x) .. "," .. tostring(destination.y))
                return true
            end
            print("[KnoxSurvivors][VehicleTravel] rejected=" .. tostring(reason))
        end
    end
    end
    return false
end

return VehicleTravel
