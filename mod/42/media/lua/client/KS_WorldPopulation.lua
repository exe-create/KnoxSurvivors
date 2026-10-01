require "SpawnRegions"
require "KS_Persistence"
require "KS_Settings"
require "KS_GroupCohesion"
require "KS_SurvivorOrigins"
require "KS_SurvivorCapabilities"

local WorldPopulation = rawget(_G, "KnoxWorldPopulation") or {}
_G.KnoxWorldPopulation = WorldPopulation

-- This module owns durable population allocation and loaded-square selection.
-- It deliberately has no OnTick hook. Autonomy calls maintain() and
-- activationCandidates() on a slow schedule instead of rescanning spawn files
-- or the entire map every frame.
local catalogCache = nil
local catalogCacheKey = nil
local FIRST_SPAWN_SEARCH_RADIUS = 4
-- Fresh saves may need dozens of durable identities, but creating the whole
-- population inside one OnTick callback can keep the game thread unresponsive
-- long enough for the operating system to treat Project Zomboid as hung.
-- Population records do not need engine bodies, so spread only this initial
-- bookkeeping across bounded maintenance passes. The final target, origin
-- balance, and opening-group policy are unchanged.
local INITIAL_ALLOCATION_BATCH = 6
local TRAVEL_BUCKET_SIZE = 300
local ORIGIN_TRAVEL_SPEED = 40 -- net tiles/game-hour, with separate shelter stops
local ORIGIN_TRAVEL_RADIUS = 600
local INITIAL_REGION_COHORT_MIN = 4
local INITIAL_REGION_COHORT_MAX = 12
local INITIAL_GROUP_MAX_SEPARATION = 64

-- These ledger activities retain a concrete logical position.  They may safely
-- become a hidden engine shell once their square streams in.  Event ownership,
-- origin staging, and transitional runtime states deliberately stay out of
-- this set: their dedicated paths decide when they may materialize.
local VIRTUAL_LOCATION_ACTIVITIES = {
    surviving = true,
    seeking_supplies = true,
    exploring = true,
    riding = true,
    waiting_for_leader = true,
    group_travel = true,
    group_waiting = true,
    group_regrouping = true,
    group_objective = true,
    base_life = true,
    base_working = true,
    sleeping = true,
    resting = true,
    sheltering = true,
    returning_to_base = true,
    away_mission = true,
}

local function hasMaterializableVirtualLocation(state)
    return type(state) == "table" and VIRTUAL_LOCATION_ACTIVITIES[state.activity] == true
end

local function ownedPlayerCompanionOwner(id)
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(id) or nil
    local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
        and KnoxPersistence.getSurvivorAffiliation(id) or nil
    if duty ~= nil and duty.mode == "companion"
        and type(duty.ownerId) == "string" and duty.ownerId ~= ""
        and affiliation ~= nil and affiliation.kind == "player"
        and affiliation.ownerId == duty.ownerId then
        return duty.ownerId, duty
    end
    return nil, duty
end

local function isOwnedPlayerCompanion(id)
    return ownedPlayerCompanionOwner(id) ~= nil
end

local function isOwnedPlayerFollower(id)
    local ownerId, duty = ownedPlayerCompanionOwner(id)
    return duty ~= nil and duty.order == "follow" and ownerId or nil
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value > -math.huge and value < math.huge
end

local function coordinateKey(x, y, z)
    return tostring(math.floor(tonumber(x) or 0))
        .. "," .. tostring(math.floor(tonumber(y) or 0))
        .. "," .. tostring(math.floor(tonumber(z) or 0))
end

local function stableHash(value)
    local result = 5381
    value = tostring(value or "")
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(first, second)
        return tostring(first) < tostring(second)
    end)
    return keys
end

local function currentMapKey()
    local success, map = pcall(function()
        return getWorld() ~= nil and getWorld():getMap() or "unknown"
    end)
    return success and tostring(map or "unknown") or "unknown"
end

-- Meta buildings exist before their squares stream in. Choose a real ground-floor
-- room rectangle, never the building bounding-box center (which may be a courtyard).
-- This supplements player starts without consulting the player's current position.
local function addBuildingOrigins(catalog)
    local ok, buildings = pcall(function() return getWorld():getMetaGrid():getBuildings() end)
    if not ok or buildings == nil then return end
    local bucketCandidates = {}
    local countOk, count = pcall(function() return buildings:size() end)
    if not countOk then return end
    for index = 0, count - 1 do
        local valid, x, y, roomNames, buildingId = pcall(function()
            local building = buildings:get(index)
            local rooms = building:getRooms()
            local names = {}
            local chosenX, chosenY = nil, nil
            for roomIndex = 0, rooms:size() - 1 do
                local room = rooms:get(roomIndex)
                local nameOk, name = pcall(function() return room:getName() end)
                if nameOk and type(name) == "string" and name ~= "" then
                    names[#names + 1] = name
                end
                if room:getZ() == 0 then
                    local rects = room:getRects()
                    for rectIndex = 0, rects:size() - 1 do
                        local rect = rects:get(rectIndex)
                        if chosenX == nil and rect:getW() >= 2 and rect:getH() >= 2 then
                            chosenX = rect:getX() + math.floor(rect:getW() / 2)
                            chosenY = rect:getY() + math.floor(rect:getH() / 2)
                        end
                    end
                end
            end
            local idOk, id = pcall(function() return building:getID() end)
            return chosenX, chosenY, names, idOk and tostring(id) or nil
        end)
        if valid and finite(x) and finite(y) then
            x, y = math.floor(x), math.floor(y)
            local bucket = math.floor(x / 100) .. ":" .. math.floor(y / 100)
            local key = coordinateKey(x, y, 0)
            if not catalog.byKey[key] then
                table.sort(roomNames)
                local candidate = {
                    x = x, y = y, z = 0, key = key,
                    source = "world_building",
                    context = KnoxSurvivorOrigins.classifyRooms(roomNames),
                    roomNames = roomNames,
                    buildingId = buildingId,
                }
                local existing = bucketCandidates[bucket]
                local candidatePriority = KnoxSurvivorOrigins.contextPriority(candidate.context)
                local existingPriority = existing ~= nil
                    and KnoxSurvivorOrigins.contextPriority(existing.context) or -1
                if existing == nil or candidatePriority > existingPriority
                    or (candidatePriority == existingPriority and candidate.key < existing.key) then
                    bucketCandidates[bucket] = candidate
                end
            end
        end
    end
    for _, bucket in ipairs(sortedKeys(bucketCandidates)) do
        local origin = bucketCandidates[bucket]
        local nearest, nearestDistance = nil, math.huge
        -- Regions have fixed anchors from player starts, so adding metadata
        -- never pulls the next region's allocation toward earlier additions.
        for _, region in ipairs(catalog.regions) do
            local distance = (origin.x - region.anchorX)^2 + (origin.y - region.anchorY)^2
            if distance < nearestDistance then nearest, nearestDistance = region, distance end
        end
        if nearest ~= nil then
            origin.region, origin.regionKey = nearest.name, nearest.key
            nearest.origins[#nearest.origins + 1] = origin
            catalog.origins[#catalog.origins + 1] = origin
            catalog.byKey[origin.key] = origin
            catalog.buildingOrigins = catalog.buildingOrigins + 1
        end
    end
end

local function indexTravelOrigins(catalog)
    catalog.travelBuckets = {}
    for _, origin in ipairs(catalog.origins) do
        local key = math.floor(origin.x / TRAVEL_BUCKET_SIZE) .. ":"
            .. math.floor(origin.y / TRAVEL_BUCKET_SIZE)
        local bucket = catalog.travelBuckets[key] or {}
        bucket[#bucket + 1] = origin
        catalog.travelBuckets[key] = bucket
    end
end

local function buildSpawnCatalog()
    if SpawnRegionMgr == nil or SpawnRegionMgr.getSpawnRegions == nil then
        return nil, "spawn_region_manager_unavailable"
    end
    local success, loaded = pcall(SpawnRegionMgr.getSpawnRegions)
    if not success or type(loaded) ~= "table" then
        return nil, "spawn_regions_unavailable"
    end

    local rawRegions = {}
    for index, region in ipairs(loaded) do
        if type(region) == "table" and type(region.points) == "table" then
            rawRegions[#rawRegions + 1] = {
                index = index,
                name = tostring(region.name or ("Region " .. tostring(index))),
                points = region.points,
            }
        end
    end
    table.sort(rawRegions, function(first, second)
        if first.name == second.name then
            return first.index < second.index
        end
        return first.name < second.name
    end)

    local catalog = { regions = {}, origins = {}, byKey = {}, buildingOrigins = 0 }
    local nameOccurrences = {}
    for _, rawRegion in ipairs(rawRegions) do
        nameOccurrences[rawRegion.name] = (nameOccurrences[rawRegion.name] or 0) + 1
        local occurrence = nameOccurrences[rawRegion.name]
        local regionKey = rawRegion.name .. "#" .. tostring(occurrence)
        local region = {
            key = regionKey,
            name = rawRegion.name,
            origins = {},
        }
        local regionSeen = {}
        for _, profession in ipairs(sortedKeys(rawRegion.points)) do
            local professionPoints = rawRegion.points[profession]
            if type(professionPoints) == "table" then
                for _, point in ipairs(professionPoints) do
                    if type(point) == "table"
                        and tonumber(point.posX) ~= nil and tonumber(point.posY) ~= nil then
                        local x = math.floor(tonumber(point.posX))
                        local y = math.floor(tonumber(point.posY))
                        local z = math.floor(tonumber(point.posZ) or 0)
                        local key = coordinateKey(x, y, z)
                        local existing = regionSeen[key] or catalog.byKey[key]
                        if existing ~= nil then
                            existing.professionCandidates = KnoxSurvivorOrigins.mergeProfessionCandidate(
                                existing.professionCandidates,
                                profession
                            )
                        elseif catalog.byKey[key] == nil then
                            local origin = {
                                x = x,
                                y = y,
                                z = z,
                                key = key,
                                region = rawRegion.name,
                                regionKey = regionKey,
                                source = "player_spawn",
                                professionCandidates = KnoxSurvivorOrigins.mergeProfessionCandidate(
                                    nil,
                                    profession
                                ),
                            }
                            regionSeen[key] = origin
                            region.origins[#region.origins + 1] = origin
                            catalog.origins[#catalog.origins + 1] = origin
                            catalog.byKey[key] = origin
                        end
                    end
                end
            end
        end
        table.sort(region.origins, function(first, second)
            return first.key < second.key
        end)
        if #region.origins > 0 then
            local x, y = 0, 0
            for _, origin in ipairs(region.origins) do x, y = x + origin.x, y + origin.y end
            region.anchorX, region.anchorY = x / #region.origins, y / #region.origins
            catalog.regions[#catalog.regions + 1] = region
        end
    end
    for _, origin in ipairs(catalog.origins) do
        KnoxSurvivorOrigins.finalizeCatalogOrigin(origin)
    end
    addBuildingOrigins(catalog)
    for _, region in ipairs(catalog.regions) do
        table.sort(region.origins, function(first, second) return first.key < second.key end)
    end
    table.sort(catalog.origins, function(first, second)
        return first.key < second.key
    end)
    if #catalog.origins == 0 then
        return nil, "no_player_spawn_origins"
    end
    indexTravelOrigins(catalog)
    return catalog, "loaded"
end

function WorldPopulation.invalidateSpawnCatalog()
    catalogCache = nil
    catalogCacheKey = nil
end

function WorldPopulation.spawnCatalog()
    local key = currentMapKey()
    if catalogCache ~= nil and catalogCacheKey == key then
        return catalogCache, "cached"
    end
    local catalog, result = buildSpawnCatalog()
    if catalog ~= nil then
        catalogCache = catalog
        catalogCacheKey = key
        print("[KnoxSurvivors][WorldPopulation] catalog playerStarts="
            .. tostring(#catalog.origins - catalog.buildingOrigins)
            .. " buildingOrigins=" .. tostring(catalog.buildingOrigins)
            .. " regions=" .. tostring(#catalog.regions))
    end
    return catalog, result
end

local EVENT_ENTRY_OFFSETS = {
    { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 2, 2 },
}

local function farEnoughFromPlayers(x, y, z, players, minimum)
    for _, player in ipairs(players or {}) do
        local square = player ~= nil and player:getCurrentSquare() or nil
        if square ~= nil and square:getZ() == z then
            local dx, dy = x - square:getX(), y - square:getY()
            if dx * dx + dy * dy < minimum * minimum then return false end
        end
    end
    return true
end

-- Selects a compact, unused party origin near an existing world anchor. No
-- square/body is loaded here; normal first-materialization safety remains final.
function WorldPopulation.eventEntryOrigins(target, count, seed, options)
    local x, y = type(target) == "table" and tonumber(target.x) or nil,
        type(target) == "table" and tonumber(target.y) or nil
    count = math.floor(tonumber(count) or 0)
    if not finite(x) or not finite(y) or count < 2 or count > #EVENT_ENTRY_OFFSETS then
        return nil, "invalid_event_entry"
    end
    options = type(options) == "table" and options or {}
    local minimum = math.max(60, math.min(300, tonumber(options.minimumTargetDistance) or 100))
    local maximum = math.max(minimum, math.min(1200, tonumber(options.maximumTargetDistance) or 600))
    local playerMinimum = math.max(60, math.min(300, tonumber(options.minimumPlayerDistance) or 100))
    local catalog, reason = WorldPopulation.spawnCatalog()
    if catalog == nil then return nil, reason end
    local used, candidates = KnoxPersistence.getUsedWorldOriginKeys(), {}
    for _, anchor in ipairs(catalog.origins) do
        local dx, dy = anchor.x - x, anchor.y - y
        local distance = math.sqrt(dx * dx + dy * dy)
        if anchor.z == 0 and distance >= minimum and distance <= maximum
            and farEnoughFromPlayers(anchor.x, anchor.y, 0, options.players, playerMinimum) then
            candidates[#candidates + 1] = {
                anchor = anchor,
                order = stableHash(tostring(seed or "event") .. ":" .. anchor.key),
                distance = distance,
            }
        end
    end
    table.sort(candidates, function(first, second)
        if first.order ~= second.order then return first.order < second.order end
        return first.anchor.key < second.anchor.key
    end)
    for _, candidate in ipairs(candidates) do
        local origins, valid = {}, true
        for index = 1, count do
            local offset = EVENT_ENTRY_OFFSETS[index]
            local ox, oy = candidate.anchor.x + offset[1], candidate.anchor.y + offset[2]
            local key = coordinateKey(ox, oy, 0)
            if used[key] or not farEnoughFromPlayers(ox, oy, 0, options.players, playerMinimum) then
                valid = false
                break
            end
            origins[index] = {
                x = ox, y = oy, z = 0, key = key,
                region = candidate.anchor.region,
                regionKey = candidate.anchor.regionKey,
                source = "knox_event",
                eventAnchorKey = candidate.anchor.key,
            }
        end
        if valid then return origins, "selected" end
    end
    return nil, "no_safe_event_entry_origin"
end

local function regionCounts()
    local counts = {}
    for _, id in ipairs(KnoxPersistence.getAllWorldSurvivorIds()) do
        local origin = KnoxPersistence.getSurvivorOrigin(id)
        if origin ~= nil then
            local regionKey = tostring(origin.regionKey or origin.region or "Unknown")
            counts[regionKey] = (counts[regionKey] or 0) + 1
        end
    end
    return counts
end

local function firstUnusedOrigin(region, used, cursor)
    local count = #region.origins
    if count == 0 then
        return nil
    end
    local start = (stableHash(region.key) + cursor * 37) % count
    local preferredSource = cursor % 3 == 2 and "world_building" or "player_spawn"
    for pass = 1, 2 do
        local generic = nil
        for offset = 0, count - 1 do
            local index = ((start + offset) % count) + 1
            local origin = region.origins[index]
            if not used[origin.key] and (pass == 2 or origin.source == preferredSource) then
                if origin.source == "world_building"
                    and origin.context ~= nil and origin.context ~= "generic" then
                    return origin
                end
                if generic == nil then generic = origin end
            end
        end
        if generic ~= nil then return generic end
    end
    return nil
end

local function chooseTravelOrigin(catalog, id, state)
    local x, y = state.virtualX, state.virtualY
    local choices = {}
    local minX, maxX = math.floor((x - ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE),
        math.floor((x + ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE)
    local minY, maxY = math.floor((y - ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE),
        math.floor((y + ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE)
    for bx = minX, maxX do
        for by = minY, maxY do
            for _, origin in ipairs(catalog.travelBuckets[bx .. ":" .. by] or {}) do
                local distance = (origin.x - x)^2 + (origin.y - y)^2
                if origin.z == state.virtualZ and distance >= 16^2
                    and distance <= ORIGIN_TRAVEL_RADIUS^2 and origin.key ~= state.previousTravelKey then
                    choices[#choices + 1] = origin
                end
            end
        end
    end
    if #choices == 0 then return nil end
    table.sort(choices, function(a, b) return a.key < b.key end)
    local profile = KnoxPersistence.getSurvivorCapabilities ~= nil
        and KnoxPersistence.getSurvivorCapabilities(id) or nil
    local professionId = type(profile) == "table" and profile.professionId or nil
    local preferred = {}
    for _, origin in ipairs(choices) do
        if origin.source == "world_building"
            and KnoxSurvivorOrigins.facilityAffinity(professionId, origin.context) > 0 then
            preferred[#preferred + 1] = origin
        end
    end
    local pool = #preferred > 0 and preferred or choices
    return pool[(stableHash(id .. ":" .. tostring(state.travelSequence or 0)) % #pool) + 1]
end

-- Faction scouting uses the same real origin catalogue as ordinary unloaded
-- travel, but keeps the cohort at the chosen anchor until its leader can load
-- the cell and inspect an actual building. This is only a rendezvous point;
-- it never treats an origin as a shelter or creates an abstract base.
function WorldPopulation.nearestScoutingOrigin(x, y, z, seed, previousKey)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    local catalog = WorldPopulation.spawnCatalog()
    if catalog == nil then return nil end
    local choices = {}
    for _, origin in ipairs(catalog.origins or {}) do
        if origin.z == z and origin.key ~= previousKey then
            local dx, dy = origin.x - x, origin.y - y
            local distance = dx * dx + dy * dy
            if distance >= 24 * 24 and distance <= ORIGIN_TRAVEL_RADIUS * ORIGIN_TRAVEL_RADIUS then
                choices[#choices + 1] = {
                    origin = origin,
                    distance = distance,
                    order = stableHash(tostring(seed or "faction") .. ":" .. origin.key),
                }
            end
        end
    end
    table.sort(choices, function(first, second)
        if first.distance ~= second.distance then return first.distance < second.distance end
        if first.order ~= second.order then return first.order < second.order end
        return first.origin.key < second.origin.key
    end)
    return choices[1] ~= nil and choices[1].origin or nil
end

-- Shared coarse itinerary for a durable position. The caller owns physiology,
-- duties and persistence. Return moving time so travel is not mistaken for rest.
function WorldPopulation.advanceItinerary(id, state, startHours, endHours)
    if type(state) ~= "table" or not finite(startHours) or not finite(endHours) then
        return false, "invalid_travel_clock", 0
    end
    local now = math.max(0, tonumber(endHours))
    if not finite(state.virtualX) or not finite(state.virtualY) or not finite(state.virtualZ) then
        return false, "invalid_virtual_location", 0
    end
    local cursor = math.max(tonumber(startHours), now - 48)
    if now <= cursor then return false, "up_to_date", 0 end
    local catalog = WorldPopulation.spawnCatalog()
    if catalog == nil then return false, "catalog_unavailable", 0 end
    local movingHours = 0
    for _ = 1, 8 do
        if cursor >= now then break end
        if state.travelTarget == nil then
            cursor = math.max(cursor, tonumber(state.departAtHours) or cursor)
            if cursor >= now then break end
            local target = chooseTravelOrigin(catalog, id, state)
            if target == nil then
                state.departAtHours = now + 3
                state.travelPhase = "shelter"
                break
            end
            state.travelTarget = { x = target.x, y = target.y, z = target.z, key = target.key }
            state.travelSequence = (tonumber(state.travelSequence) or 0) + 1
        end
        local target = state.travelTarget
        if not finite(target.x) or not finite(target.y) or not finite(target.z)
            or target.z ~= state.virtualZ then
            state.travelTarget = nil
            state.departAtHours = now + 3
            state.travelPhase = "shelter"
            break
        end
        local dx, dy = target.x - state.virtualX, target.y - state.virtualY
        local distance = math.sqrt(dx * dx + dy * dy)
        local available = (now - cursor) * ORIGIN_TRAVEL_SPEED
        if distance > available then
            state.virtualX = state.virtualX + dx / distance * available
            state.virtualY = state.virtualY + dy / distance * available
            state.travelPhase = "moving"
            movingHours = movingHours + now - cursor
            cursor = now
        else
            movingHours = movingHours + distance / ORIGIN_TRAVEL_SPEED
            cursor = cursor + distance / ORIGIN_TRAVEL_SPEED
            state.virtualX, state.virtualY, state.virtualZ = target.x, target.y, target.z
            state.previousTravelKey = state.currentTravelKey
            state.currentTravelKey = target.key
            state.travelTarget = nil
            state.travelPhase = "shelter"
            state.departAtHours = cursor + 2 + stableHash(id .. ":rest:" .. state.travelSequence) % 4
        end
    end
    state.virtualAtHours = now
    return true, "travel_advanced", movingHours
end

-- Before first body creation only location is known. This never invents health
-- or inventory. After capture the stored-survival controller owns the identity.
function WorldPopulation.advanceOriginTravel(id, hours)
    if not KnoxPersistence.isSurvivorPresent(id) or KnoxPersistence.getRecord(id) ~= nil then
        return false, "not_unmaterialized"
    end
    local origin = KnoxPersistence.getSurvivorOrigin(id)
    if origin == nil or not finite(hours) then return false, "origin_unavailable" end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if duty ~= nil and duty.mode ~= nil and duty.mode ~= "autonomous" then
        return false, "duty_owns_travel"
    end
    local now = math.max(0, tonumber(hours))
    local state = KnoxPersistence.getUnloadedSurvivalState(id)
    if state == nil then
        state = { pendingMaterialization = true, virtualX = origin.x, virtualY = origin.y,
            virtualZ = origin.z, lastHours = now, currentTravelKey = origin.key,
            activity = "origin_shelter", status = "unmaterialized" }
        KnoxPersistence.setUnloadedSurvivalState(id, state)
    end
    if state.pendingMaterialization ~= true then return false, "survival_ledger_owns_travel" end
    if type(state.eventEntryId) == "string" and state.eventEntryId ~= "" then
        state.activity, state.lastHours, state.virtualAtHours = "event_entry_waiting", now, now
        KnoxPersistence.setUnloadedSurvivalState(id, state)
        return false, "event_entry_waiting"
    end
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(id) or nil
    if group ~= nil then
        if group.leaderId ~= id then return false, "origin_group_leader_owns_travel" end
        local members = {}
        for _, memberId in ipairs(group.memberIds or {}) do
            local memberState = KnoxPersistence.getUnloadedSurvivalState(memberId)
            if KnoxPersistence.getRecord(memberId) ~= nil or memberState == nil
                or memberState.pendingMaterialization ~= true then
                return false, "origin_group_waiting_for_materialization"
            end
            members[#members + 1] = { id = memberId, state = memberState }
        end
        if #members < 2 then return false, "origin_group_unavailable" end
        local leaderState = nil
        for _, member in ipairs(members) do
            if member.id == group.leaderId then leaderState = member.state break end
        end
        if leaderState == nil then return false, "origin_group_leader_unavailable" end
        local shared = type(group.unloadedTravel) == "table" and group.unloadedTravel or {
            virtualX = leaderState.virtualX,
            virtualY = leaderState.virtualY,
            virtualZ = leaderState.virtualZ,
            lastHours = leaderState.lastHours,
            currentTravelKey = leaderState.currentTravelKey,
            previousTravelKey = leaderState.previousTravelKey,
            departAtHours = leaderState.departAtHours,
            travelSequence = leaderState.travelSequence,
        }
        local oldX, oldY = shared.virtualX, shared.virtualY
        local socialBefore=KnoxGroupCohesion.snapshot(members)
        local advanced, result = WorldPopulation.advanceItinerary(
            group.id,
            shared,
            tonumber(shared.lastHours) or now,
            now
        )
        if not advanced then return false, result end
        local dx, dy = shared.virtualX - oldX, shared.virtualY - oldY
        shared.lastHours = now
        group.unloadedTravel = shared
        for _, member in ipairs(members) do
            local memberState = member.state
            memberState.virtualX = memberState.virtualX + dx
            memberState.virtualY = memberState.virtualY + dy
            memberState.virtualAtHours = now
            memberState.lastHours = now
            memberState.currentTravelKey = shared.currentTravelKey
            memberState.previousTravelKey = shared.previousTravelKey
            memberState.activity = shared.travelPhase == "moving"
                and "group_travel" or "group_waiting"
            KnoxPersistence.setUnloadedSurvivalState(member.id, memberState)
        end
        KnoxGroupCohesion.record(group,socialBefore,members,now)
        return true, "origin_group_advanced"
    end
    local advanced, result = WorldPopulation.advanceItinerary(id, state, tonumber(state.lastHours) or now, now)
    if not advanced then return false, result end
    state.activity = state.travelPhase == "moving" and "origin_travel" or "origin_shelter"
    state.lastHours, state.virtualAtHours = now, now
    return KnoxPersistence.setUnloadedSurvivalState(id, state), "origin_advanced"
end

local function chooseBalancedOrigin(catalog, used, counts, cursor)
    local available = {}
    local lowestCount = nil
    for index, region in ipairs(catalog.regions) do
        local origin = firstUnusedOrigin(region, used, cursor)
        if origin ~= nil then
            local count = (counts[region.key] or 0)
                + (region.key ~= region.name and (counts[region.name] or 0) or 0)
            if lowestCount == nil or count < lowestCount then
                lowestCount = count
                available = { { index = index, region = region, origin = origin } }
            elseif count == lowestCount then
                available[#available + 1] = {
                    index = index,
                    region = region,
                    origin = origin,
                }
            end
        end
    end
    if #available == 0 then
        return nil
    end
    -- Rotate equal-count regions using a persisted cursor. This keeps initial
    -- allocation balanced while avoiding dependence on Lua pairs() order.
    local selected = available[(cursor % #available) + 1]
    return selected.origin, selected.region.key
end

local function primaryPlayerSquare(options)
    local function currentSquare(player)
        local success, square = pcall(function()
            return player ~= nil and player:getCurrentSquare() or nil
        end)
        return success and square or nil
    end
    local supplied = type(options) == "table" and options.players or nil
    if type(supplied) == "table" then
        for _, player in ipairs(supplied) do
            local square = currentSquare(player)
            if square ~= nil then return square end
        end
    end
    local countSuccess, count = pcall(function() return getNumActivePlayers() end)
    if countSuccess then
        for index = 0, math.max(0, tonumber(count) or 0) - 1 do
            local playerSuccess, player = pcall(function() return getSpecificPlayer(index) end)
            local square = playerSuccess and currentSquare(player) or nil
            if square ~= nil then return square end
        end
    end
    return nil
end

local function nearestStartingRegion(catalog, options)
    local square = primaryPlayerSquare(options)
    if square == nil then return nil end
    local selected, selectedDistance = nil, math.huge
    for _, region in ipairs(catalog.regions or {}) do
        local dx, dy = region.anchorX - square:getX(), region.anchorY - square:getY()
        local distance = dx * dx + dy * dy
        if distance < selectedDistance then
            selected, selectedDistance = region, distance
        end
    end
    return selected
end

local function initialRegionCohortSize(target, regionCount)
    if target <= 0 or regionCount <= 0 then return 0 end
    local balancedShare = math.ceil(target / regionCount)
    local presenceBonus = math.max(2, math.floor(target * 0.10 + 0.5))
    return math.min(
        target,
        INITIAL_REGION_COHORT_MAX,
        math.max(INITIAL_REGION_COHORT_MIN, balancedShare + presenceBonus)
    )
end

local function ensureOriginCapabilities(id, origin)
    -- Allocation remains durable even if definitions are unavailable during a
    -- transient load phase. First materialization runs the same precedence
    -- helper again, so contextual evidence fails soft without rerolling an
    -- already-persisted profile.
    if CharacterProfessionDefinition == nil
        or CharacterProfessionDefinition.getProfessions == nil then
        return false, "profession_definitions_unavailable"
    end
    local ok, profile, reason = pcall(
        KnoxSurvivorCapabilities.ensureForOrigin,
        id,
        nil,
        true,
        nil,
        origin
    )
    if ok and profile ~= nil then return true, reason end
    print("[KnoxSurvivors][WorldPopulation] capability deferral id="
        .. tostring(id) .. " reason=" .. tostring(ok and reason or profile))
    return false, ok and reason or profile
end

local function allocateFromRegion(region, worldAgeHours, state, used, counts)
    if region == nil then return nil, "starting_region_unavailable" end
    local cursor = math.max(0, math.floor(tonumber(state.allocationCursor) or 0))
    local origin = firstUnusedOrigin(region, used, cursor)
    if origin == nil then return nil, "starting_region_origins_exhausted" end
    local id, result = KnoxPersistence.allocateWorldSurvivor(origin, worldAgeHours)
    if id == nil then return nil, result end
    ensureOriginCapabilities(id, origin)
    used[origin.key] = true
    counts[region.key] = (counts[region.key] or 0) + 1
    state.allocationCursor = cursor + 1
    return id, "allocated"
end

local function removeSelectedIds(available, selected)
    local removed = {}
    for _, id in ipairs(selected) do removed[id] = true end
    local retained = {}
    for _, id in ipairs(available) do
        if not removed[id] then retained[#retained + 1] = id end
    end
    return retained
end

local function compactGroup(available, size)
    if #available < size then return nil end
    table.sort(available)
    for _, anchorId in ipairs(available) do
        local anchor = KnoxPersistence.getSurvivorOrigin(anchorId)
        if anchor ~= nil then
            local nearby = {}
            for _, candidateId in ipairs(available) do
                if candidateId ~= anchorId then
                    local candidate = KnoxPersistence.getSurvivorOrigin(candidateId)
                    if candidate ~= nil and candidate.z == anchor.z then
                        local dx, dy = candidate.x - anchor.x, candidate.y - anchor.y
                        local distance = dx * dx + dy * dy
                        if distance <= INITIAL_GROUP_MAX_SEPARATION^2 then
                            nearby[#nearby + 1] = { id = candidateId, distance = distance }
                        end
                    end
                end
            end
            table.sort(nearby, function(first, second)
                if first.distance == second.distance then return first.id < second.id end
                return first.distance < second.distance
            end)
            if #nearby >= size - 1 then
                local selected = { anchorId }
                for index = 1, size - 1 do selected[#selected + 1] = nearby[index].id end
                table.sort(selected)
                return selected
            end
        end
    end
    return nil
end

local function formInitialGroups(startingIds, worldAgeHours, state)
    if state.initialGroupsCreated then return 0 end
    local available = {}
    for _, id in ipairs(startingIds or {}) do available[#available + 1] = id end
    local chance = KnoxSettings.initialGroupChance ~= nil
        and KnoxSettings.initialGroupChance() or 65
    local maxSize = KnoxSettings.initialGroupMaxSize ~= nil
        and KnoxSettings.initialGroupMaxSize() or 4
    local requestedSizes = {}
    -- Keep the opening world social without turning population allocation into
    -- an army spawn.  A normal 48-person world can begin with up to three small
    -- compact cohorts; tiny test populations still produce the original single
    -- pair.  Each cohort gets its own deterministic roll so one failed roll does
    -- not prevent later, independent groups from forming.
    local configuredGroups = KnoxSettings.initialGroupCount ~= nil
        and KnoxSettings.initialGroupCount() or 3
    local maxGroups = math.min(configuredGroups, math.floor(#available / 6))
    if #available >= 2 and maxGroups == 0 then maxGroups = 1 end
    for groupIndex = 1, maxGroups do
        local roll = stableHash(
            tostring(worldAgeHours) .. ":cohort:" .. tostring(groupIndex)
        ) % 100
        if roll < chance then
            -- The first cohort can reach the advertised configurable group
            -- size. The former hard cap of three made the default four-member
            -- faction threshold unreachable for every opening group.
            local requested = groupIndex == 1 and math.min(maxSize, math.max(2, math.floor(#available/2)))
                or 2 + stableHash(tostring(worldAgeHours)..":cohort-size:"..groupIndex) % math.max(1,maxSize-1)
            requestedSizes[#requestedSizes + 1] = math.min(maxSize, requested)
        end
    end
    local created = 0
    for _, size in ipairs(requestedSizes) do
        local members = compactGroup(available, size)
        while members==nil and size>2 do
            size=size-1
            members=compactGroup(available,size)
        end
        if members ~= nil then
            local group = KnoxPersistence.createTravelGroup(members, worldAgeHours)
            if group ~= nil then
                group.originCohort = true
                available = removeSelectedIds(available, members)
                created = created + 1
            end
        end
    end
    state.initialGroupsCreated = true
    state.initialGroupCount = created
    return created
end

-- Replacements normally enter alone, but a world that has suffered deaths
-- should not slowly lose all of its human clusters.  Give a new identity one
-- modest, deterministic chance to join a nearby independent survivor.  This
-- only links existing persisted identities; it never teleports or fabricates
-- a body, and the normal encounter/faction rules still govern later growth.
local function formRefillGroup(id, worldAgeHours)
    if id == nil or KnoxPersistence.getSurvivorOrigin == nil
        or KnoxPersistence.getAllWorldSurvivorIds == nil
        or KnoxPersistence.getTravelGroupFor == nil
        or KnoxPersistence.isIndependentSurvivor == nil
        or KnoxPersistence.createTravelGroup == nil then
        return nil
    end
    if stableHash(tostring(id) .. ":refill-group:" .. tostring(worldAgeHours or 0)) % 100 >= 40 then
        return nil
    end
    local origin = KnoxPersistence.getSurvivorOrigin(id)
    if origin == nil then return nil end
    local nearest, nearestDistance = nil, 64 * 64 + 1
    for _, otherId in ipairs(KnoxPersistence.getAllWorldSurvivorIds() or {}) do
        if otherId ~= id and KnoxPersistence.isIndependentSurvivor(otherId)
            and KnoxPersistence.getTravelGroupFor(otherId) == nil then
            local other = KnoxPersistence.getSurvivorOrigin(otherId)
            if other ~= nil and (tonumber(other.z) or 0) == (tonumber(origin.z) or 0) then
                local dx = (tonumber(other.x) or 0) - (tonumber(origin.x) or 0)
                local dy = (tonumber(other.y) or 0) - (tonumber(origin.y) or 0)
                local distance = dx * dx + dy * dy
                if distance < nearestDistance then
                    nearest, nearestDistance = otherId, distance
                end
            end
        end
    end
    if nearest == nil then return nil end
    return KnoxPersistence.createTravelGroup({ id, nearest }, worldAgeHours)
end

local function allocateOne(catalog, worldAgeHours, state, used, counts)
    local cursor = math.max(0, math.floor(tonumber(state.allocationCursor) or 0))
    local origin, regionKey = chooseBalancedOrigin(catalog, used, counts, cursor)
    if origin == nil then
        return nil, "spawn_origins_exhausted"
    end
    local id, result = KnoxPersistence.allocateWorldSurvivor(origin, worldAgeHours)
    if id == nil then
        return nil, result
    end
    ensureOriginCapabilities(id, origin)
    used[origin.key] = true
    counts[regionKey] = (counts[regionKey] or 0) + 1
    state.allocationCursor = cursor + 1
    return id, "allocated"
end

-- Creates the initial region-balanced population in one save transaction.
-- Later deaths are replaced one survivor at a time, never as a catch-up burst.
function WorldPopulation.maintain(worldAgeHours, options)
    local now = math.max(0, tonumber(worldAgeHours) or 0)
    local target = KnoxSettings.worldPopulation()
    local uncapped = KnoxSettings.capsDisabled()
    local refillHours = KnoxSettings.populationRefillDays() * 24
    local state = KnoxPersistence.getPopulationState()
    local living = #KnoxPersistence.getLivingWorldSurvivorIds()
    local result = {
        status = "unchanged",
        addedIds = {},
        living = living,
        target = target,
        capsDisabled = uncapped,
        nextRefillHours = tonumber(state.nextRefillHours) or 0,
    }

    if not state.initialized then
        if target == 0 then
            state.initialized = true
            state.lastTarget = target
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
            result.status = "initialized_empty"
            result.nextRefillHours = state.nextRefillHours
            return result
        end
        local catalog, catalogResult = WorldPopulation.spawnCatalog()
        if catalog == nil then
            result.status = catalogResult
            return result
        end
        local used = KnoxPersistence.getUsedWorldOriginKeys()
        local counts = regionCounts()
        local startingIds = {}
        local allocationBudget = math.max(1, math.floor(tonumber(
            type(options) == "table" and options.initialAllocationBudget or nil
        ) or INITIAL_ALLOCATION_BATCH))
        local allocatedThisPass = 0
        local startingRegion = nearestStartingRegion(catalog, options)
        local startingTarget = startingRegion ~= nil
            and initialRegionCohortSize(target, #catalog.regions) or 0
        state.initialRegionKey = startingRegion ~= nil and startingRegion.key or nil
        state.initialRegionTarget = startingTarget
        while living < target and startingRegion ~= nil
            and (counts[startingRegion.key] or 0) < startingTarget
            and allocatedThisPass < allocationBudget do
            local id = allocateFromRegion(startingRegion, now, state, used, counts)
            if id == nil then break end
            result.addedIds[#result.addedIds + 1] = id
            startingIds[#startingIds + 1] = id
            living = living + 1
            allocatedThisPass = allocatedThisPass + 1
        end
        while living < target and allocatedThisPass < allocationBudget do
            local id = allocateOne(catalog, now, state, used, counts)
            if id == nil then
                break
            end
            result.addedIds[#result.addedIds + 1] = id
            -- Keep the social pass aware of every identity created during the
            -- opening population, not just the player's nearest cohort. This
            -- lets compact spawn clusters elsewhere on the map begin as small
            -- groups while still using the same distance/size/chance gates.
            startingIds[#startingIds + 1] = id
            living = living + 1
            allocatedThisPass = allocatedThisPass + 1
        end
        result.living = living
        -- More origins remain: yield to the game and continue on the next
        -- population maintenance pass. Do not start refill timing or form
        -- partial opening groups while initial allocation is still underway.
        if living < target and allocatedThisPass > 0 then
            result.status = "initializing"
            result.nextRefillHours = 0
            return result
        end
        -- The final pass may contain only part of the opening population.
        -- Build groups from every living population-managed identity so batch
        -- boundaries cannot change the social layout of the same fresh world.
        startingIds = KnoxPersistence.getLivingWorldSurvivorIds()
        formInitialGroups(startingIds, now, state)
        state.initialized = true
        state.lastTarget = target
        if refillHours > 0 and (living < target or uncapped) then
            state.belowTargetSinceHours = now
            state.nextRefillHours = now + refillHours
        else
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
        end
        result.status = #result.addedIds > 0 and "initialized" or "spawn_origins_exhausted"
        result.nextRefillHours = state.nextRefillHours
        return result
    end

    state.lastTarget = target
    -- Zero means a finite starting population, including in uncapped games.
    -- Clear the old deadline so enabling arrivals later starts a full interval
    -- rather than immediately replacing losses accumulated while disabled.
    if refillHours == 0 then
        state.belowTargetSinceHours = nil
        state.nextRefillHours = 0
        result.status = "refill_disabled"
        result.nextRefillHours = 0
        return result
    end
    if living >= target and not uncapped then
        state.belowTargetSinceHours = nil
        state.nextRefillHours = 0
        result.status = "at_target"
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    if state.belowTargetSinceHours == nil then
        state.belowTargetSinceHours = now
        state.nextRefillHours = now + refillHours
        result.status = "waiting"
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    if now < (tonumber(state.nextRefillHours) or 0) then
        result.status = "waiting"
        result.nextRefillHours = state.nextRefillHours
        return result
    end

    local catalog, catalogResult = WorldPopulation.spawnCatalog()
    if catalog == nil then
        result.status = catalogResult
        state.nextRefillHours = now + refillHours
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    local id, allocationResult = allocateOne(
        catalog,
        now,
        state,
        KnoxPersistence.getUsedWorldOriginKeys(),
        regionCounts()
    )
    state.nextRefillHours = now + refillHours
    result.nextRefillHours = state.nextRefillHours
    if id ~= nil then
        local refillGroup = formRefillGroup(id, now)
        result.status = uncapped and "arrived" or "refilled"
        result.addedIds[1] = id
        result.groupId = refillGroup ~= nil and refillGroup.id or nil
        result.living = living + 1
        if result.living >= target and not uncapped then
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
            result.nextRefillHours = 0
        else
            state.belowTargetSinceHours = now
        end
    else
        result.status = allocationResult
    end
    return result
end

local function playersFrom(options)
    if type(options) == "table" and type(options.players) == "table" then
        return options.players
    end
    local players = {}
    local success, count = pcall(function()
        return getNumActivePlayers()
    end)
    if not success then
        count = 1
    end
    for playerIndex = 0, math.max(0, tonumber(count) or 1) - 1 do
        local playerSuccess, player = pcall(function()
            return getSpecificPlayer(playerIndex)
        end)
        if playerSuccess and player ~= nil then
            players[#players + 1] = player
        end
    end
    return players
end

local function playerSquare(player)
    local success, square = pcall(function()
        return player:getCurrentSquare()
    end)
    return success and square or nil
end

local function distanceSquared(square, other)
    local dx = square:getX() - other:getX()
    local dy = square:getY() - other:getY()
    return dx * dx + dy * dy
end

function WorldPopulation.nearestPlayerDistanceSquared(square, players)
    if square == nil then
        return nil
    end
    local nearest = nil
    for _, player in ipairs(players or playersFrom(nil)) do
        local other = playerSquare(player)
        if other ~= nil then
            local value = distanceSquared(square, other)
            if nearest == nil or value < nearest then
                nearest = value
            end
        end
    end
    return nearest
end

local function visibleToAnyPlayer(square, players)
    for fallbackIndex, player in ipairs(players) do
        local playerIndex = fallbackIndex - 1
        pcall(function()
            playerIndex = player:getPlayerNum()
        end)
        local canSeeSuccess, canSee = pcall(function()
            return square:isCanSee(playerIndex)
        end)
        if canSeeSuccess and canSee then
            return true
        end
        if not canSeeSuccess then
            local couldSeeSuccess, couldSee = pcall(function()
                return square:isCouldSee(playerIndex)
            end)
            if couldSeeSuccess and couldSee then
                return true
            end
        end
    end
    return false
end

local function safeStandable(square)
    if square == nil then
        return false
    end
    local standSuccess, standable = pcall(function()
        return square:canStand()
    end)
    if not standSuccess or not standable then
        return false
    end
    local fireSuccess, hasFire = pcall(function()
        return square:haveFire()
    end)
    if fireSuccess and hasFire then
        return false
    end
    local movingSuccess, occupied = pcall(function()
        local movingObjects = square:getMovingObjects()
        return movingObjects ~= nil and movingObjects:size() > 0
    end)
    return not (movingSuccess and occupied)
end

local function ringOffsets(radius, rotation)
    local offsets = {}
    if radius == 0 then
        return { { x = 0, y = 0 } }
    end
    for dx = -radius, radius do
        for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                offsets[#offsets + 1] = { x = dx, y = dy }
            end
        end
    end
    table.sort(offsets, function(first, second)
        if first.x == second.x then
            return first.y < second.y
        end
        return first.x < second.x
    end)
    local rotated = {}
    local count = #offsets
    local start = count > 0 and rotation % count or 0
    for offset = 0, count - 1 do
        rotated[#rotated + 1] = offsets[((start + offset) % count) + 1]
    end
    return rotated
end

-- When a player explicitly has an owned survivor following, the old virtual
-- floor may no longer be streamed (or may have no safe tile). Rejoin the same
-- persistent person beside that owner using a real loaded square on the
-- owner's current floor. This is a last resort after the saved location, not
-- a general relocation rule for independent survivors, Hold, or base duty.
local function safeFollowerSquare(players, id, ownerId)
    local rotation = stableHash(id .. ":follow-return")
    for _, player in ipairs(players or {}) do
        local playerId = KnoxPersistence.ensurePlayerId ~= nil
            and KnoxPersistence.ensurePlayerId(player) or nil
        local anchor = playerId == ownerId and playerSquare(player) or nil
        if anchor ~= nil then
            local z = math.floor(tonumber(anchor:getZ()) or 0)
            for radius = 1, FIRST_SPAWN_SEARCH_RADIUS do
                for _, offset in ipairs(ringOffsets(radius, rotation)) do
                    local square = getCell():getGridSquare(
                        math.floor(anchor:getX()) + offset.x,
                        math.floor(anchor:getY()) + offset.y,
                        z
                    )
                    if safeStandable(square) then return square end
                end
            end
        end
    end
    return nil
end

local function withinMaximumDistance(square, players, maximumDistance)
    if maximumDistance == nil then
        return true, WorldPopulation.nearestPlayerDistanceSquared(square, players)
    end
    local nearest = WorldPopulation.nearestPlayerDistanceSquared(square, players)
    return nearest ~= nil and nearest <= maximumDistance * maximumDistance, nearest
end

local function locationOutsideBand(x, y, players, maximumDistance)
    if maximumDistance == nil then return false end
    local maximum = maximumDistance + FIRST_SPAWN_SEARCH_RADIUS * math.sqrt(2)
    for _, player in ipairs(players) do
        local square = playerSquare(player)
        if square ~= nil and (square:getX() - x)^2 + (square:getY() - y)^2 <= maximum^2 then
            return false
        end
    end
    return true
end

-- First materialization may move at most four tiles from its original player
-- spawn point to find a valid square. It never occurs in sight of, or inside
-- the configured exclusion radius around, any local player.
function WorldPopulation.findFirstMaterializationSquare(origin, options)
    if type(origin) ~= "table" or getCell() == nil then
        return nil, "origin_or_cell_unavailable"
    end
    local players = playersFrom(options)
    local minimumDistance = type(options) == "table" and options.minimumDistance
        or KnoxSettings.minimumSpawnDistance()
    minimumDistance = math.max(0, tonumber(minimumDistance) or 0)
    local maximumDistance = type(options) == "table"
        and tonumber(options.maximumDistance)
        or nil
    if locationOutsideBand(origin.x, origin.y, players, maximumDistance) then
        return nil, "outside_activation_distance"
    end
    local rotation = stableHash(origin.key or coordinateKey(origin.x, origin.y, origin.z))

    for radius = 0, FIRST_SPAWN_SEARCH_RADIUS do
        for _, offset in ipairs(ringOffsets(radius, rotation)) do
            local square = getCell():getGridSquare(
                math.floor(tonumber(origin.x)) + offset.x,
                math.floor(tonumber(origin.y)) + offset.y,
                math.floor(tonumber(origin.z) or 0)
            )
            if safeStandable(square) and not visibleToAnyPlayer(square, players) then
                local nearest = WorldPopulation.nearestPlayerDistanceSquared(square, players)
                local farEnough = nearest == nil
                    or nearest >= minimumDistance * minimumDistance
                local closeEnough = maximumDistance == nil
                    or (nearest ~= nil and nearest <= maximumDistance * maximumDistance)
                if farEnough and closeEnough then
                    return square, "ready"
                end
            end
        end
    end
    return nil, "no_safe_hidden_loaded_square"
end

local function recordLocation(bridge, record)
    if bridge == nil then
        return nil, nil, nil, "bridge_unavailable"
    end
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success or tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil then
        return nil, nil, nil, "record_location_unavailable"
    end
    return math.floor(tonumber(x)), math.floor(tonumber(y)), math.floor(tonumber(z)), nil
end

local function materializeVirtualLocation(id, bridge, record, players, maximumDistance)
    local state = KnoxPersistence.getUnloadedSurvivalState ~= nil
        and KnoxPersistence.getUnloadedSurvivalState(id) or nil
    if state == nil then
        return record, nil, nil, nil, "no_virtual_travel"
    end
    if state.pendingMaterialization == true then
        return record, nil, nil, nil, "pending_materialization"
    end
    -- OnSave captures live bodies too. Their native record is authoritative;
    -- the last offscreen activity is not a reason to hide them on reload.
    if state.status == "loaded" then
        return record, nil, nil, nil, "no_virtual_travel"
    end
    if not hasMaterializableVirtualLocation(state) then
        -- A ledger state with a virtual position is authoritative over the
        -- saved record.  Do not resurrect it at that stale record location
        -- while an event/origin/transitional owner has not released it.
        return record, nil, nil, nil, "virtual_activity_blocked"
    end
    local x = math.floor(tonumber(state.virtualX) or -1)
    local y = math.floor(tonumber(state.virtualY) or -1)
    local z = math.floor(tonumber(state.virtualZ) or 0)
    if x < 0 or y < 0 or getCell() == nil then
        return record, nil, nil, nil, "virtual_location_unavailable"
    end
    if locationOutsideBand(x, y, players, maximumDistance) then
        return record, nil, nil, nil, "outside_activation_distance"
    end
    local selected = nil
    -- Returning player-owned companions must be allowed to rematerialize at
    -- their real logical position even when the player can see it. Requiring
    -- an unseen square here can strand an owned survivor in hibernation while
    -- the player is standing beside the saved map location. Independent
    -- population still uses hidden placement to avoid visible spawn-in.
    local allowVisible = isOwnedPlayerCompanion(id)
    local rotation = stableHash(id .. ":virtual:" .. tostring(x) .. ":" .. tostring(y))
    for radius = 0, FIRST_SPAWN_SEARCH_RADIUS do
        for _, offset in ipairs(ringOffsets(radius, rotation)) do
            local square = getCell():getGridSquare(x + offset.x, y + offset.y, z)
            if safeStandable(square)
                and (allowVisible or not visibleToAnyPlayer(square, players)) then
                selected = square
                break
            end
        end
        if selected ~= nil then break end
    end
    if selected == nil then
        local followerOwnerId = isOwnedPlayerFollower(id)
        if followerOwnerId ~= nil then
            selected = safeFollowerSquare(players, id, followerOwnerId)
            if selected ~= nil then
                print("[KnoxSurvivors][WorldPopulation] activation-fallback id="
                    .. tostring(id) .. " reason=follow_owner_saved_square_unavailable from="
                    .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                    .. " to=" .. tostring(selected:getX()) .. ","
                    .. tostring(selected:getY()) .. "," .. tostring(selected:getZ()))
            end
        end
        if selected == nil then
            return record, nil, nil, nil, "virtual_square_not_loaded_or_visible"
        end
    end
    if bridge.relocateNpcRecord == nil then
        return record, nil, nil, nil, "record_relocator_unavailable"
    end
    local ok, updated = pcall(
        bridge.relocateNpcRecord,
        bridge,
        record,
        selected:getX(),
        selected:getY(),
        selected:getZ()
    )
    if not ok or type(updated) ~= "string" or updated == "" then
        return record, nil, nil, nil, "record_relocation_failed"
    end
    if not KnoxPersistence.setRecord(id, updated) then
        return record, nil, nil, nil, "record_relocation_save_failed"
    end
    state.virtualX, state.virtualY, state.virtualZ = selected:getX(), selected:getY(), selected:getZ()
    KnoxPersistence.setUnloadedSurvivalState(id, state)
    return updated, selected:getX(), selected:getY(), selected:getZ(), nil
end

-- A saved record always wins over its origin. Restoration returns the exact
-- recorded square or waits for that square to load; it never silently moves a
-- persistent survivor back to their original spawn point.
local function activationPriority(id)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if duty ~= nil and duty.mode == "companion" then return 0 end
    if duty ~= nil and duty.mode == "base" and duty.ownerId ~= nil then
        local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
            and KnoxPersistence.getSurvivorAffiliation(id) or nil
        return affiliation ~= nil and affiliation.kind == "player" and 1 or 2
    end
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(id) or nil
    return group ~= nil and 3 or 4
end

local AWAY_MEMBER_OFFSETS = {
    { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 },
    { 2, 2 }, { -2, 2 }, { 2, -2 }, { -2, -2 },
}

local function awayDestinationSquare(team, survivorId, destination)
    local cell = getCell()
    if cell == nil then return nil end
    local memberIndex = 1
    for index, id in ipairs(team.memberIds or {}) do
        if id == survivorId then memberIndex = index break end
    end
    local preferred = AWAY_MEMBER_OFFSETS[((memberIndex - 1)
        % #AWAY_MEMBER_OFFSETS) + 1]
    local attempts = { preferred }
    for _, offset in ipairs(AWAY_MEMBER_OFFSETS) do
        if offset ~= preferred then attempts[#attempts + 1] = offset end
    end
    for _, offset in ipairs(attempts) do
        local square = cell:getGridSquare(
            math.floor(destination.x) + offset[1],
            math.floor(destination.y) + offset[2],
            math.floor(destination.z)
        )
        if square ~= nil then
            local canStand = true
            if square.canStand ~= nil then
                local ok, value = pcall(square.canStand, square)
                canStand = ok and value == true
            end
            if canStand then return square end
        end
    end
    return nil
end

function WorldPopulation.activationCandidate(id, bridge, options)
    if type(id) ~= "string" or id == "" or not KnoxPersistence.isSurvivorPresent(id) then
        return nil, "not_living"
    end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    local blockedRecovery = KnoxPersistence.getBlockedAwayTeamRecovery ~= nil
        and KnoxPersistence.getBlockedAwayTeamRecovery(id) or nil
    -- An away team owns its members' off-world lifecycle until it finishes or
    -- blocks. Normal proximity activation must not pull them back into a loaded
    -- engine shell just because the player passes their recorded origin. The
    -- explicit mission path may materialize an active mission member at its
    -- persisted destination (or return point); blocked dispatch recovery is a
    -- separate explicit path that restores only an acknowledged removed body
    -- through its canonical persisted record.
    if duty ~= nil and duty.mode == "away" then
        if blockedRecovery ~= nil then
            if type(options) ~= "table" or options.allowBlockedDispatchRecovery ~= true then
                return nil, "blocked_dispatch_recovery"
            end
        else
            local allowAway = type(options) == "table"
                and options.allowAwayMission == true
            if not allowAway then
                return nil, "away_mission"
            end
            local team = KnoxPersistence.getAwayTeamForSurvivor ~= nil
                and KnoxPersistence.getAwayTeamForSurvivor(id) or nil
            local missionState = team ~= nil and (team.state == "awaiting_collection"
                or team.state == "collecting" or team.state == "returning")
            local destination = nil
            if missionState then
                destination = team.state == "returning"
                    and team.returnDestination or team.destination
            end
            local record = KnoxPersistence.getRecord(id)
            if not missionState or destination == nil or record == nil
                or not finite(destination.x) or not finite(destination.y)
                or not finite(destination.z) then
                return nil, "away_destination_unavailable"
            end
            local players = playersFrom(options)
            local maximumDistance = tonumber(options.maximumDistance)
            local square = awayDestinationSquare(team, id, destination)
            if square == nil then return nil, "away_square_not_loaded" end
            local closeEnough, nearest = withinMaximumDistance(
                square, players, maximumDistance
            )
            if not closeEnough then return nil, "outside_activation_distance" end
            return {
                id = id,
                mode = "restore",
                record = record,
                square = square,
                x = square:getX(),
                y = square:getY(),
                z = square:getZ(),
                exact = true,
                firstMaterialization = false,
                distanceSquared = nearest,
                activationPriority = 0,
                awayMission = true,
                awayTeamId = team.id,
            }, "ready"
        end
    end
    local players = playersFrom(options)
    local maximumDistance = type(options) == "table"
        and tonumber(options.maximumDistance)
        or nil
    local record = KnoxPersistence.getRecord(id)
    if record ~= nil then
        local virtualRecord, virtualX, virtualY, virtualZ, virtualResult =
            materializeVirtualLocation(id, bridge, record, players, maximumDistance)
        if virtualResult ~= "no_virtual_travel" then
            if virtualResult ~= nil then return nil, virtualResult end
            record = virtualRecord
        end
        local x, y, z, locationError = virtualX, virtualY, virtualZ, nil
        if x == nil then
            x, y, z, locationError = recordLocation(bridge, record)
        end
        if locationError ~= nil then
            return nil, locationError
        end
        local square = getCell() ~= nil and getCell():getGridSquare(x, y, z) or nil
        if square == nil then
            return nil, "saved_square_not_loaded"
        end
        local closeEnough, nearest = withinMaximumDistance(square, players, maximumDistance)
        if not closeEnough then
            return nil, "outside_activation_distance"
        end
        return {
            id = id,
            mode = "restore",
            record = record,
            square = square,
            x = x,
            y = y,
            z = z,
            exact = true,
            firstMaterialization = false,
            distanceSquared = nearest,
            activationPriority = activationPriority(id),
            blockedDispatchRecovery = blockedRecovery ~= nil,
            blockedAwayTeamId = blockedRecovery ~= nil and blockedRecovery.id or nil,
        }, "ready"
    end

    local origin = KnoxPersistence.getSurvivorOrigin(id)
    if origin == nil then
        return nil, "origin_unavailable"
    end
    local location = origin
    local state = KnoxPersistence.getUnloadedSurvivalState(id)
    if state ~= nil and state.pendingMaterialization == true then
        if not finite(state.virtualX) or not finite(state.virtualY) or not finite(state.virtualZ) then
            return nil, "virtual_location_unavailable"
        end
        location = { x = state.virtualX, y = state.virtualY, z = state.virtualZ, key = id }
    end
    local square, squareResult = WorldPopulation.findFirstMaterializationSquare(location, options)
    if square == nil then
        return nil, squareResult
    end
    return {
        id = id,
        mode = "spawn",
        origin = origin,
        square = square,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        exact = false,
        firstMaterialization = true,
        distanceSquared = WorldPopulation.nearestPlayerDistanceSquared(square, players),
        activationPriority = activationPriority(id),
    }, "ready"
end

local function activeLookup(activeIds)
    local lookup = {}
    for key, value in pairs(activeIds or {}) do
        if type(key) == "number" and type(value) == "string" then
            lookup[value] = true
        elseif type(key) == "string" and value then
            lookup[key] = true
        end
    end
    return lookup
end

-- Restore every durable survivor record, including companions and manually-created
-- development survivors. New first-materializations remain production-managed only.
function WorldPopulation.activationCandidates(bridge, activeIds, limit, options)
    local candidates = {}
    local rejected = {}
    local active = activeLookup(activeIds)
    local maximum = math.max(0, math.floor(tonumber(limit) or KnoxSettings.maxActiveSurvivors()))
    if maximum == 0 then return candidates, { activation_budget_full = 1 } end
    for _, id in ipairs(KnoxPersistence.getActivatableSurvivorIds()) do
        if not active[id] then
            local candidate, result = WorldPopulation.activationCandidate(id, bridge, options)
            if candidate ~= nil and options ~= nil and options.acceptCandidate ~= nil
                and not options.acceptCandidate(candidate) then
                candidate, result = nil, "streaming_edge_cooldown"
            end
            if candidate ~= nil then
                candidates[#candidates + 1] = candidate
            else
                rejected[result] = (rejected[result] or 0) + 1
                if isOwnedPlayerCompanion(id) then
                    print("[KnoxSurvivors][WorldPopulation] activation-deferred id="
                        .. tostring(id) .. " reason=" .. tostring(result))
                end
            end
        end
    end
    table.sort(candidates, function(first, second)
        local firstPriority = tonumber(first.activationPriority) or 4
        local secondPriority = tonumber(second.activationPriority) or 4
        if firstPriority ~= secondPriority then
            return firstPriority < secondPriority
        end
        local firstDistance = tonumber(first.distanceSquared) or math.huge
        local secondDistance = tonumber(second.distanceSquared) or math.huge
        if firstDistance == secondDistance then
            if first.mode ~= second.mode then
                return first.mode == "restore"
            end
            return first.id < second.id
        end
        return firstDistance < secondDistance
    end)
    -- Prefer loading a complete nearby travel group when it fits the remaining
    -- activation budget. This keeps persistent cohorts from appearing one body
    -- at a time, while never exceeding the active-survivor cap.
    local selected, selectedIds = {}, {}
    for _, candidate in ipairs(candidates) do
        if #selected >= maximum then break end
        if not selectedIds[candidate.id] then
            local group = KnoxPersistence.getTravelGroupFor ~= nil
                and KnoxPersistence.getTravelGroupFor(candidate.id) or nil
            local cohort = { candidate }
            if group ~= nil and type(group.memberIds) == "table" then
                local byId = {}
                for _, sibling in ipairs(candidates) do byId[sibling.id] = sibling end
                local complete = true
                for _, memberId in ipairs(group.memberIds) do
                    if memberId ~= candidate.id and not selectedIds[memberId] then
                        if byId[memberId] == nil then complete = false break end
                        cohort[#cohort + 1] = byId[memberId]
                    end
                end
                if not complete or #selected + #cohort > maximum then
                    cohort = { candidate }
                end
            end
            for _, member in ipairs(cohort) do
                if #selected >= maximum then break end
                if not selectedIds[member.id] then
                    selected[#selected + 1] = member
                    selectedIds[member.id] = true
                end
            end
        end
    end
    return selected, rejected
end

return WorldPopulation
