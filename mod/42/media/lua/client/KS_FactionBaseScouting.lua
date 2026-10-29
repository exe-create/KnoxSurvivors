require "KS_Persistence"
require "KS_SurvivorOrigins"

local BaseScouting = rawget(_G, "KnoxFactionBaseScouting") or {}
_G.KnoxFactionBaseScouting = BaseScouting

-- Search locally first, then widen only when the nearby ring produced no valid
-- shelter.  Faction scouting remains loaded-world work; the staged radii keep
-- the common case cheap without making a group give up because its first block
-- contains only tiny or already-claimed buildings.
local SCAN_RADII = { 30, 60, 90 }
local MIN_ROOMS = 2
local MIN_AREA = 30

local function overlaps(first, second)
    if first == nil or second == nil then return false end
    local firstMinX = tonumber(first.minX)
    local firstMinY = tonumber(first.minY)
    local firstMaxX = tonumber(first.maxX)
        or (firstMinX ~= nil and firstMinX + (tonumber(first.width) or 1) - 1)
    local firstMaxY = tonumber(first.maxY)
        or (firstMinY ~= nil and firstMinY + (tonumber(first.height) or 1) - 1)
    local secondMinX = tonumber(second.minX)
    local secondMinY = tonumber(second.minY)
    local secondMaxX = tonumber(second.maxX)
        or (secondMinX ~= nil and secondMinX + (tonumber(second.width) or 1) - 1)
    local secondMaxY = tonumber(second.maxY)
        or (secondMinY ~= nil and secondMinY + (tonumber(second.height) or 1) - 1)
    if firstMinX == nil or firstMinY == nil or firstMaxX == nil or firstMaxY == nil
        or secondMinX == nil or secondMinY == nil
        or secondMaxX == nil or secondMaxY == nil then
        return false
    end
    return firstMinX <= secondMaxX and firstMaxX >= secondMinX
        and firstMinY <= secondMaxY and firstMaxY >= secondMinY
end

local function overlapsPersistedBase(definition, z)
    for _, base in pairs(KnoxPersistence.getBases() or {}) do
        local area = base ~= nil and (base.territory or base.home) or nil
        if area ~= nil and tonumber(area.z or 0) == tonumber(z or 0)
            and overlaps({
                minX = definition:getX(), minY = definition:getY(),
                maxX = definition:getX2(), maxY = definition:getY2(),
            }, area) then
            return true
        end
    end
    return false
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function safehouseOverlaps(definition)
    local success, safehouse = pcall(function()
        return SafeHouse.getSafehouseOverlapping(
            definition:getX(),
            definition:getY(),
            definition:getX() + definition:getW(),
            definition:getY() + definition:getH()
        )
    end)
    if not success then return true, "safehouse_query_failed" end
    return safehouse ~= nil, "overlaps_existing_safehouse"
end

local function nearestExteriorSquare(origin, definition)
    local cell = getCell()
    if cell == nil then
        return nil
    end
    local best = nil
    local bestDistance = nil
    local minX = definition:getX() - 1
    local minY = definition:getY() - 1
    local maxX = definition:getX2()
    local maxY = definition:getY2()
    for x = minX, maxX do
        for _, y in ipairs({ minY, maxY }) do
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:isOutside() and square:canStand() then
                local distance = distanceSquared(origin, square)
                if bestDistance == nil or distance < bestDistance then
                    best = square
                    bestDistance = distance
                end
            end
        end
    end
    for y = minY + 1, maxY - 1 do
        for _, x in ipairs({ minX, maxX }) do
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:isOutside() and square:canStand() then
                local distance = distanceSquared(origin, square)
                if bestDistance == nil or distance < bestDistance then
                    best = square
                    bestDistance = distance
                end
            end
        end
    end
    return best, bestDistance
end

local function assessBuilding(origin, building, inspectedSquare)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil then return nil end
    local blocked, reason = safehouseOverlaps(definition)
    if blocked then return nil, reason end
    if overlapsPersistedBase(definition, origin:getZ()) then
        return nil
    end
    local rooms = definition:getRoomsNumber()
    local area = definition:getArea()
    if rooms < MIN_ROOMS or area < MIN_AREA then
        return nil
    end
    local target, distance = nearestExteriorSquare(origin, definition)
    if target == nil then
        return nil
    end
    local residential = building:isResidential()
    local water = building:hasWater()
    local score = rooms * 8
        + math.min(area, 240) * 0.15
        + (residential and 25 or 0)
        + (water and 15 or 0)
        - math.sqrt(distance or 0) * 0.35
    return {
        buildingId = tostring(definition:getID()),
        probeX = inspectedSquare ~= nil and inspectedSquare:getX() or nil,
        probeY = inspectedSquare ~= nil and inspectedSquare:getY() or nil,
        probeZ = inspectedSquare ~= nil and inspectedSquare:getZ() or nil,
        x = target:getX(),
        y = target:getY(),
        z = target:getZ(),
        minX = definition:getX(),
        minY = definition:getY(),
        width = definition:getW(),
        height = definition:getH(),
        rooms = rooms,
        area = area,
        residential = residential,
        water = water,
        score = score,
        distance = distance,
    }
end

function BaseScouting.findBestCandidate(character, factionId, worldAgeHours)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local cell = origin ~= nil and getCell() or nil
    if origin == nil or cell == nil then
        return nil
    end
    -- This synchronous search cannot move the survivor between tile probes.
    -- Read fixed engine values once rather than crossing Lua/Java per tile.
    local originX, originY, originZ = origin:getX(), origin:getY(), origin:getZ()
    local best = nil
    local faction = KnoxPersistence.getFaction ~= nil and KnoxPersistence.getFaction(factionId) or nil
    local background = faction ~= nil and faction.background or nil
    local preferredContext = (background == "law_enforcement" or background == "fire_service"
        or background == "military") and background or nil
    local seen = {}
    for _, radius in ipairs(SCAN_RADII) do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Only inspect the newly-added outer ring after the first
                -- radius. This avoids rescanning the same loaded squares while
                -- preserving the nearest-first scoring behavior.
                local outsidePrevious = radius == SCAN_RADII[1]
                    or math.max(math.abs(dx), math.abs(dy)) > (radius - 30)
                if outsidePrevious then
                    local square = cell:getGridSquare(
                        originX + dx,
                        originY + dy,
                        originZ
                    )
                    local building = square ~= nil and square:getBuilding() or nil
                    if building ~= nil and not seen[building] then
                        seen[building] = true
                        local candidate = assessBuilding(origin, building, square)
                        if candidate ~= nil then
                            candidate.facilityPreferred = false
                            if preferredContext ~= nil then
                                local ok, context = pcall(function()
                                    local names, rooms = {}, building:getDef():getRooms()
                                    for i=0,rooms:size()-1 do names[#names+1]=rooms:get(i):getName() end
                                    return KnoxSurvivorOrigins.classifyRooms(names)
                                end)
                                candidate.facilityPreferred = ok and context == preferredContext
                            end
                        end
                        if candidate ~= nil
                            and not KnoxPersistence.isFactionBaseCandidateRejected(
                                factionId,
                                candidate.buildingId,
                                worldAgeHours
                            )
                            and (best == nil
                                or (candidate.facilityPreferred and not best.facilityPreferred)
                                or (candidate.facilityPreferred == best.facilityPreferred
                                    and (candidate.score > best.score
                                or (candidate.score == best.score
                                    and (candidate.distance < best.distance
                                        or (candidate.distance == best.distance
                                            and candidate.buildingId < best.buildingId)))))) then
                            best = candidate
                        end
                    end
                end
            end
        end
        if best ~= nil then break end
    end
    return best
end

function BaseScouting.resolveTarget(candidate)
    if type(candidate) ~= "table" or getCell() == nil then
        return nil
    end
    local square = getCell():getGridSquare(candidate.x, candidate.y, candidate.z)
    return square ~= nil and square:canStand() and square or nil
end

-- Saved plans are leads, not evidence that a streamed building is still there.
-- Use the inspected tile, with a small local fallback for older saved leads.
function BaseScouting.validateArrival(character, candidate, factionId, worldAgeHours)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local target = BaseScouting.resolveTarget(candidate)
    if origin == nil or target == nil then return false, "target_unloaded" end
    if origin:getZ() ~= target:getZ() or distanceSquared(origin,target) > 9 then
        return false, "leader_not_at_candidate"
    end
    if KnoxPersistence.isFactionBaseCandidateRejected(factionId,candidate.buildingId,worldAgeHours) then
        return false, "candidate_rejected"
    end
    local inspected = nil
    local function matches(square)
        local building = square ~= nil and square:getBuilding() or nil
        local definition = building ~= nil and building:getDef() or nil
        if definition ~= nil and tostring(definition:getID()) == candidate.buildingId then
            inspected = square
            return building
        end
        return nil
    end
    local building
    if candidate.probeX ~= nil and candidate.probeY ~= nil and candidate.probeZ ~= nil then
        building = matches(getCell():getGridSquare(candidate.probeX,candidate.probeY,candidate.probeZ))
    else
        for dx=-4,4 do
            for dy=-4,4 do
                building = matches(getCell():getGridSquare(target:getX()+dx,target:getY()+dy,target:getZ()))
                if building ~= nil then break end
            end
            if building ~= nil then break end
        end
    end
    if building == nil then return false, "building_unavailable" end
    local fresh, reason = assessBuilding(origin,building,inspected)
    if fresh == nil then return false, reason or "building_no_longer_suitable" end
    if fresh.minX ~= candidate.minX or fresh.minY ~= candidate.minY
        or fresh.width ~= candidate.width or fresh.height ~= candidate.height then
        return false, "building_changed"
    end
    return true, "arrival_verified"
end

return BaseScouting
