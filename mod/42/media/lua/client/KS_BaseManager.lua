require "KS_Persistence"
require "KS_SurvivorCapabilities"
require "KS_SurvivorRuntime"
require "KS_BaseStorage"
require "KS_ToolCupboard"
require "KS_Settings"
require "KS_CompanionPatrol"
require "Util/AdjacentFreeTileFinder"

local BaseManager = rawget(_G, "KnoxBaseManager") or {}
_G.KnoxBaseManager = BaseManager

local PLAYER_BASE_YARD_PADDING = 6

BaseManager.ZONE_TYPES = {
    farming = true,
    cooking = true,
    woodcutting = true,
    log_processing = true,
    guard = true,
    patrol = true,
    corpse = true,
    repair = true,
    general = true,
}

BaseManager.STORAGE_CATEGORIES = {
    food = true,
    water = true,
    medical = true,
    weapons = true,
    ammunition = true,
    tools = true,
    logs = true,
    fuel = true,
    general = true,
    building = true,
    farming = true,
    clothing = true,
    junk = true,
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function areaFromBuilding(building, square)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil then
        return nil
    end
    return {
        buildingId = tostring(definition:getID()),
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        minX = definition:getX(),
        minY = definition:getY(),
        width = definition:getW(),
        height = definition:getH(),
    }
end

local function territoryAround(area, padding)
    local pad = math.max(0, tonumber(padding) or 0)
    return {
        minX = area.minX - pad,
        minY = area.minY - pad,
        maxX = area.minX + area.width - 1 + pad,
        maxY = area.minY + area.height - 1 + pad,
    }
end

local function blockedBySurvivorSafehouse(area)
    local overlapping = SafeHouse ~= nil and SafeHouse.getSafehouseOverlapping(
        area.minX,
        area.minY,
        area.maxX + 1,
        area.maxY + 1
    ) or nil
    if overlapping == nil then return false end
    local owner = tostring(overlapping:getOwner() or "")
    return string.find(owner, "KnoxSurvivors:", 1, true) == 1
end

local function hasZoneType(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == zoneType then
            return true
        end
    end
    return false
end

local function countZoneType(base, zoneType)
    local count = 0
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == zoneType then
            count = count + 1
        end
    end
    return count
end

local function ensureFactionZone(base, zoneType, bounds, label, count)
    if countZoneType(base, zoneType) < (count or 1) and bounds ~= nil then
        return KnoxPersistence.addBaseZone(base.id, zoneType, bounds, label)
    end
    return nil, "existing"
end

local function findOutdoorSquare(area, preferredDistance, accepts)
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or area == nil then return nil end
    local centerX = math.floor((tonumber(area.minX) or 0)
        + math.max(1, tonumber(area.width)
            or ((tonumber(area.maxX) or area.minX) - area.minX + 1)) / 2)
    local centerY = math.floor((tonumber(area.minY) or 0)
        + math.max(1, tonumber(area.height)
            or ((tonumber(area.maxY) or area.minY) - area.minY + 1)) / 2)
    local z = tonumber(area.z) or 0
    for radius = math.max(2, tonumber(preferredDistance) or 2), 18 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil
                    and (accepts == nil or accepts(square)) then
                    return square
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            for _, dx in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil
                    and (accepts == nil or accepts(square)) then
                    return square
                end
            end
        end
    end
    return nil
end

local function ensureFactionZones(base, faction)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area == nil then return end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    ensureFactionZone(base, "patrol", {
        x1 = minX, y1 = minY, x2 = maxX, y2 = maxY, z = z, priority = 72,
    }, "Base Patrol")
    local entryWatch = findOutdoorSquare(area, 2)
    local guardX = entryWatch ~= nil and entryWatch:getX()
        or math.floor(tonumber(area.x) or ((minX + maxX) / 2))
    local guardY = entryWatch ~= nil and entryWatch:getY()
        or math.floor(tonumber(area.y) or ((minY + maxY) / 2))
    ensureFactionZone(base, "guard", {
        x1 = guardX - 1, y1 = guardY - 1,
        x2 = guardX + 1, y2 = guardY + 1, z = z, priority = 84,
    }, "Entry Watch")
    -- Larger settlements need relief and a second sight line.  Keep this as a
    -- second ordinary guard zone rather than inventing a separate security
    -- system; BaseJobs will claim/rotate it using the same fairness rules as
    -- every other resident duty.  The opposite corner keeps posts apart even
    -- when the first outdoor square resolves near the building entrance.
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or {}
    local residentCount = type(residentIds) == "table" and #residentIds or 0
    if faction ~= nil and faction.background == "law_enforcement" and residentCount >= 3
        and (KnoxSettings.policeNeighborhoodPatrols==nil or KnoxSettings.policeNeighborhoodPatrols()) then
        local existing = false
        for _,zone in pairs(base.zones or {}) do
            if zone.label == "Neighborhood Patrol" then existing=true break end
        end
        if not existing then
            -- This is a work route, never territory. Wait for real loaded
            -- standing positions near every corner before offering the route.
            local centerX,centerY=math.floor((minX+maxX)/2),math.floor((minY+maxY)/2)
            local margin=KnoxSettings.policePatrolMargin~=nil and KnoxSettings.policePatrolMargin() or 16
            local route={x1=math.max(minX-margin,centerX-32),y1=math.max(minY-margin,centerY-32),
                x2=math.min(maxX+margin,centerX+32),y2=math.min(maxY+margin,centerY+32),z=z,priority=73}
            local patrol=rawget(_G,"KnoxCompanionPatrol")
            local cell=getCell ~= nil and getCell() or nil
            local points=patrol ~= nil and patrol.waypoints(route) or {}
            local valid=#points==4 and cell~=nil
            for step=0,#points-1 do
                local stop=patrol.resolveWaypoint(route,base.id,step,cell,nil,nil,0,true)
                if stop==nil or stop:getRoom()~=nil then valid=false break end
            end
            if valid then KnoxPersistence.addBaseZone(base.id,"patrol",route,"Neighborhood Patrol") end
        end
    end
    if residentCount >= 6 and countZoneType(base, "patrol") < 2 then
        -- Split a large settlement's perimeter into a second route.  It is
        -- still an ordinary patrol zone; task claims and waypoint rotation
        -- remain owned by BaseJobs/CompanionPatrol.
        local outerPatrol = findOutdoorSquare(area, math.max(5,
            math.floor(math.max(6, tonumber(area.width) or 6) / 2)))
        local patrolX = outerPatrol ~= nil and outerPatrol:getX()
            or math.floor(maxX - 2)
        local patrolY = outerPatrol ~= nil and outerPatrol:getY()
            or math.floor(maxY - 2)
        ensureFactionZone(base, "patrol", {
            x1 = patrolX - 3, y1 = patrolY - 3,
            x2 = patrolX + 3, y2 = patrolY + 3, z = z, priority = 71,
        }, "Outer Patrol", 2)
    end
    if residentCount >= 4 and countZoneType(base, "guard") < 2 then
        local farWatch = findOutdoorSquare(area, math.max(4,
            math.floor(math.max(4, tonumber(area.width) or 4) / 2)))
        local farX = farWatch ~= nil and farWatch:getX()
            or math.floor(maxX - 1)
        local farY = farWatch ~= nil and farWatch:getY()
            or math.floor(maxY - 1)
        ensureFactionZone(base, "guard", {
            x1 = farX - 1, y1 = farY - 1,
            x2 = farX + 1, y2 = farY + 1, z = z, priority = 83,
        }, "Outer Watch", 2)
    end
    -- Structure repair scans the owned territory directly; it does not need a
    -- second full-base work-area overlay. Construction areas were removed.
    local work = not hasZoneType(base, "farming") and findOutdoorSquare(area, 4, function(square)
        if ISFarmingMenu == nil or ISFarmingMenu.canDigHereSquare == nil then return false end
        local ok, diggable = pcall(ISFarmingMenu.canDigHereSquare, square)
        return ok and diggable == true
    end) or nil
    if work ~= nil then
        ensureFactionZone(base, "farming", {
            x1 = work:getX() - 2, y1 = work:getY() - 2,
            x2 = work:getX() + 2, y2 = work:getY() + 2,
            z = work:getZ(), priority = 82,
        }, "Food Plot")
    end
    local outer = findOutdoorSquare(area, 8)
    if outer ~= nil then
        ensureFactionZone(base, "woodcutting", {
            x1 = outer:getX() - 6, y1 = outer:getY() - 6,
            x2 = outer:getX() + 6, y2 = outer:getY() + 6,
            z = outer:getZ(), priority = 68,
        }, "Wood Lot")
        -- Keep log processing close to the wood lot while exposing it as its
        -- own durable work area. Offset east so exclusive production areas do
        -- not share tiles; the executor distinguishes the two.
        ensureFactionZone(base, "log_processing", {
            x1 = outer:getX() + 7, y1 = outer:getY() - 2,
            x2 = outer:getX() + 11, y2 = outer:getY() + 2,
            z = outer:getZ(), priority = 70,
        }, "Log Yard")
        -- Corpse drop sits west of the wood lot for the same exclusivity reason.
        ensureFactionZone(base, "corpse", {
            x1 = outer:getX() - 10, y1 = outer:getY() - 1,
            x2 = outer:getX() - 8, y2 = outer:getY() + 1,
            z = outer:getZ(), priority = 91,
        }, "Corpse Drop")
    end
end

-- Faction storage helpers: a role is covered when any assigned policy serves
-- it, and container kinds map to roles by what those containers hold in the
-- world (cupboards/counters hold tools, crates/shelves hold materials).
local function storageRoleAssigned(base, role)
    for _, policy in pairs(base ~= nil and base.storage or {}) do
        if policy ~= nil and tostring(policy.storageRole or policy.key) == role then
            return true
        end
    end
    return false
end

local function containerFitsFactionRole(kind, role)
    kind = string.lower(tostring(kind or ""))
    if role == "tools" then
        return kind:find("cupboard", 1, true) ~= nil
            or kind:find("counter", 1, true) ~= nil
            or kind:find("drawer", 1, true) ~= nil
            or kind:find("locker", 1, true) ~= nil
            or kind:find("cabinet", 1, true) ~= nil
    end
    if role == "building" then
        return kind:find("crate", 1, true) ~= nil
            or kind:find("shelf", 1, true) ~= nil
            or kind:find("pallet", 1, true) ~= nil
    end
    if role == "logs" then
        return kind:find("woodpile", 1, true) ~= nil
            or kind:find("pallet", 1, true) ~= nil
            or kind:find("crate", 1, true) ~= nil
    end
    return false
end

local function ensureFactionStorage(base)
    if base == nil then return end
    base.storage = base.storage or {}
    local area = base.territory or base.home
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil then return end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    local found = {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and square:getObjects() or nil
            if objects ~= nil then
                for objectIndex = 0, objects:size() - 1 do
                    local object = objects:get(objectIndex)
                    local count = object ~= nil and object:getContainerCount() or 0
                    for containerIndex = 0, count - 1 do
                        local container = object:getContainerByIndex(containerIndex)
                        local kind = container ~= nil and string.lower(tostring(container:getType() or "")) or ""
                        if container ~= nil and kind ~= "corpse" then
                            found[#found + 1] = {
                                object = object,
                                containerIndex = containerIndex,
                                kind = kind,
                            }
                        end
                    end
                end
            end
        end
    end
    for _, entry in ipairs(found) do
        if entry.kind:find("fridge", 1, true) or entry.kind:find("freezer", 1, true) then
            local reference = BaseManager.containerReference(entry.object, entry.containerIndex, base.id)
            if reference ~= nil and base.storage[reference.key] == nil then
                BaseManager.setStoragePolicy(base.id, entry.object, "food", entry.containerIndex)
            end
        end
        -- Main Supplies auto-designation retired: typed storages are explicit.
    end
    -- Faction upkeep needs the same typed stores a player assigns by hand:
    -- without a tools/materials cupboard, barricade/repair/woodcutting tasks
    -- can never leave the supply-wait state. Designate from real world
    -- containers only; map loot and resident scavenging fill them.
    local roles = { "tools", "building", "logs" }
    for _, role in ipairs(roles) do
        if not storageRoleAssigned(base, role) then
            for _, entry in ipairs(found) do
                if containerFitsFactionRole(entry.kind, role) then
                    local reference = BaseManager.containerReference(
                        entry.object, entry.containerIndex, base.id)
                    if reference ~= nil and base.storage[reference.key] == nil then
                        BaseManager.setStoragePolicy(
                            base.id, entry.object, role, entry.containerIndex)
                        break
                    end
                end
            end
        end
    end
    -- Houses without a refrigerator still need a pantry. Fill uncovered
    -- categories from remaining real dry containers without reassigning any
    -- existing player or faction policy. Separate roles are optional capacity.
    for _, role in ipairs({ "food", "water", "tools", "logs", "building", "medical",
        "farming", "weapons", "ammunition", "clothing", "junk" }) do
        if not storageRoleAssigned(base, role) then
            for _, entry in ipairs(found) do
                if KnoxToolCupboard ~= nil and KnoxToolCupboard.isDryContainerType ~= nil
                    and KnoxToolCupboard.isDryContainerType(entry.kind) then
                    local reference = BaseManager.containerReference(entry.object, entry.containerIndex, base.id)
                    if reference ~= nil and base.storage[reference.key] == nil then
                        local policy = BaseManager.setStoragePolicy(base.id, entry.object, role, entry.containerIndex)
                        if policy ~= nil then break end
                    end
                end
            end
        end
    end
end

local AUTO_BED_QUALITY = {
    goodBed = 5,
    averageBed = 4,
    badBed = 2,
}
local factionBedAttemptedMembership = {}

local function bedReferenceKey(ref)
    return table.concat({ tostring(ref.x), tostring(ref.y), tostring(ref.z),
        tostring(ref.objectIndex) }, ":")
end

-- Faction bed placement is a projection of the faction's existing base and
-- resident records. Only loaded native beds in that exact building are
-- considered; no bed, square, or body is created by this pass.
local function discoverFactionBeds(base, faction)
    local area = base ~= nil and (base.home or faction.homeBase) or nil
    local cell = getCell ~= nil and getCell() or nil
    local buildingId = area ~= nil and area.buildingId or nil
    local minX, minY = area ~= nil and tonumber(area.minX), area ~= nil and tonumber(area.minY)
    local width, height = area ~= nil and tonumber(area.width), area ~= nil and tonumber(area.height)
    if cell == nil or type(buildingId) ~= "string" or buildingId == ""
        or minX == nil or minY == nil or width == nil or height == nil
        or width < 1 or height < 1 or width * height > 4096 then
        return {}
    end
    local beds = {}
    -- Build 42 rooms can place beds on upper floors even when the base marker
    -- was founded on the ground floor. Query only already-loaded squares.
    for z = -2, 8 do
        for x = minX, minX + width - 1 do
            for y = minY, minY + height - 1 do
                local square = cell:getGridSquare(x, y, z)
                local building = square ~= nil and square:getBuilding() or nil
                local definition = building ~= nil and building:getDef() or nil
                local sameBuilding = false
                pcall(function()
                    sameBuilding = definition ~= nil
                        and tostring(definition:getID()) == tostring(buildingId)
                end)
                if sameBuilding and square.getObjects ~= nil then
                    local objects = square:getObjects()
                    for objectIndex = 0, objects:size() - 1 do
                        local object = objects:get(objectIndex)
                        local properties = object ~= nil and object:getProperties() or nil
                        local bedType = properties ~= nil
                            and tostring(properties:get("BedType") or "") or ""
                        local quality = AUTO_BED_QUALITY[bedType]
                        local index = object ~= nil and object:getObjectIndex() or -1
                        if quality ~= nil and index >= 0 then
                            beds[#beds + 1] = {
                                object = object,
                                square = square,
                                quality = quality,
                                ref = { x = square:getX(), y = square:getY(),
                                    z = square:getZ(), objectIndex = index },
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(beds, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.ref.z ~= b.ref.z then return a.ref.z < b.ref.z end
        if a.ref.y ~= b.ref.y then return a.ref.y < b.ref.y end
        if a.ref.x ~= b.ref.x then return a.ref.x < b.ref.x end
        return a.ref.objectIndex < b.ref.objectIndex
    end)
    return beds
end

local function ensureFactionBeds(base, faction)
    if base == nil or faction == nil or base.ownerKind ~= "faction"
        or base.ownerId ~= faction.id or KnoxPersistence.setFactionResidentBed == nil then
        return 0
    end
    local members, seen = {}, {}
    local function append(id)
        if type(id) ~= "string" or seen[id] then return end
        seen[id] = true
        members[#members + 1] = id
    end
    append(faction.leaderId)
    for _, id in ipairs(faction.memberIds or {}) do append(id) end
    table.sort(members, function(a, b)
        if a == faction.leaderId then return true end
        if b == faction.leaderId then return false end
        return a < b
    end)

    local unassignedLoaded = {}
    for _, id in ipairs(members) do
        local policies = KnoxPersistence.getSurvivorPolicies ~= nil
            and KnoxPersistence.getSurvivorPolicies(id) or nil
        local assigned = type(policies) == "table" and policies.assignedBed or nil
        if assigned == nil or (type(assigned) == "table"
            and assigned.autoFactionId == faction.id
            and assigned.autoBaseId ~= base.id) then
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            local character = runtime ~= nil and runtime.getCharacter ~= nil
                and runtime.getCharacter(id) or nil
            if character ~= nil then unassignedLoaded[#unassignedLoaded + 1] = id end
        end
    end
    if #unassignedLoaded == 0 then return 0 end
    local signature = base.id .. ":" .. table.concat(unassignedLoaded, ",")
    local now = worldAge()
    local previous = factionBedAttemptedMembership[base.id]
    if type(previous) == "table" and previous.signature == signature
        and now - (tonumber(previous.atHours) or 0) < 0.5 then
        return 0
    end
    factionBedAttemptedMembership[base.id] = {
        signature = signature, atHours = now,
    }

    local beds = discoverFactionBeds(base, faction)
    if #beds == 0 then return 0 end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")

    local claimed = {}
    for _, id in ipairs(members) do
        local policies = KnoxPersistence.getSurvivorPolicies ~= nil
            and KnoxPersistence.getSurvivorPolicies(id) or nil
        local assigned = type(policies) == "table" and policies.assignedBed or nil
        if type(assigned) == "table" then
            claimed[bedReferenceKey(assigned)] = true
        end
    end

    local assignedCount = 0
    for _, id in ipairs(unassignedLoaded) do
        local policies = KnoxPersistence.getSurvivorPolicies ~= nil
            and KnoxPersistence.getSurvivorPolicies(id) or nil
        local assigned = type(policies) == "table" and policies.assignedBed or nil
        local canRefresh = type(assigned) == "table"
            and assigned.autoFactionId == faction.id
            and assigned.autoBaseId ~= base.id
        if assigned == nil or canRefresh then
            local character = runtime ~= nil and runtime.getCharacter ~= nil
                and runtime.getCharacter(id) or nil
            if character ~= nil then
                for _, bed in ipairs(beds) do
                    local key = bedReferenceKey(bed.ref)
                    if not claimed[key] then
                        local occupiedOk, occupied = pcall(function()
                            return bed.object:isFurnitureOccupied(character)
                        end)
                        -- nil means the engine could not tell us whether the
                        -- furniture is occupied. Treat that as unavailable;
                        -- auto-assignment must not overwrite ambiguous beds.
                        local approachOk, approach = false, nil
                        if occupiedOk and occupied == false then
                            approachOk, approach = pcall(function()
                                return AdjacentFreeTileFinder.Find(
                                    bed.square, character, nil
                                )
                            end)
                        end
                        if approachOk and approach ~= nil then
                            local ok = KnoxPersistence.setFactionResidentBed(
                                id, faction.id, base.id, bed.ref, worldAge()
                            )
                            if ok then
                                claimed[key] = true
                                assignedCount = assignedCount + 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return assignedCount
end

-- BASE BED ROSTER (pure)
-- The Notebook's bed view reads the existing per-survivor assignedBed
-- record. This is a projection only: it never scans for a bed, assigns one,
-- clears one or writes a survivor record. A companion is listed only when
-- they already hold a bed; every living base resident is listed so a missing
-- assignment is visible rather than silently absent.
function BaseManager.bedRoster(base, playerId)
    local rows = {}
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId
        or KnoxPersistence.getBaseResidentIds == nil then
        return rows
    end
    local seen = {}
    local function append(id, includeWithoutBed)
        if type(id) ~= "string" or seen[id] then return end
        seen[id] = true
        if KnoxPersistence.isSurvivorAlive ~= nil
            and KnoxPersistence.isSurvivorAlive(id) == false then
            return
        end
        local identity = KnoxPersistence.getSurvivorIdentity ~= nil
            and KnoxPersistence.getSurvivorIdentity(id) or nil
        local name = identity ~= nil and tostring(identity.forename or "") or ""
        local surname = identity ~= nil and tostring(identity.surname or "") or ""
        name = (name .. " " .. surname):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name = "Resident " .. tostring(id) end
        local policies = KnoxPersistence.getSurvivorPolicies ~= nil
            and KnoxPersistence.getSurvivorPolicies(id) or nil
        local assigned = type(policies) == "table" and policies.assignedBed or nil
        local bed = nil
        if type(assigned) == "table" then
            local x, y, z = tonumber(assigned.x), tonumber(assigned.y), tonumber(assigned.z)
            local objectIndex = tonumber(assigned.objectIndex)
            if x ~= nil and y ~= nil and z ~= nil and objectIndex ~= nil
                and x == x and y == y and z == z then
                bed = { x = x, y = y, z = z, objectIndex = objectIndex }
            end
        end
        if bed == nil and includeWithoutBed ~= true then return end
        local roomName = nil
        if bed ~= nil then
            local compound = rawget(_G, "KnoxBaseCompound")
            if compound ~= nil and compound.roomNameAt ~= nil then
                roomName = compound.roomNameAt(base, bed.x, bed.y, bed.z)
            end
        end
        rows[#rows + 1] = { id = id, name = name, bed = bed, room = roomName }
    end
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        append(id, true)
    end
    if KnoxPersistence.getCompanionIds ~= nil then
        for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
            append(id, false)
        end
    end
    table.sort(rows, function(first, second)
        if first.name ~= second.name then return first.name < second.name end
        return tostring(first.id) < tostring(second.id)
    end)
    return rows
end
-- END BASE BED ROSTER

-- BASE HOME ATTENTION (pure)
-- One read-only projection for the Work tab's attention band. Callers pass
-- facts already gathered from the existing owners; this function only chooses
-- the three most useful problems and phrases them. It never reads persistence,
-- creates work, assigns stock, scans the world or invents a cause.
local function attentionWhole(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number < 0 then return 0 end
    return math.floor(number)
end

local function attentionCount(count, singular, plural)
    return tostring(count) .. " " .. (count == 1 and singular or plural)
end

-- A resident's home state is a fact table first, so the display can be
-- exercised without a world. Missing is reserved for a future known-unknown
-- state; today an absent living resident is away, not invented as missing.
function BaseManager.homeCounts(rows)
    local counts = { home = 0, away = 0, missing = 0, dead = 0 }
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" then
            if row.alive == false then
                counts.dead = counts.dead + 1
            elseif row.missing == true then
                counts.missing = counts.missing + 1
            elseif row.present == false or row.away == true or row.event == true then
                counts.away = counts.away + 1
            else
                counts.home = counts.home + 1
            end
        end
    end
    return counts
end

-- Who is deliberately out of the way? A resident holding at the fallback is
-- a fact the raid line can name, so the player reads one sentence instead of
-- watching a corner to guess. Rows are the same home rows `homeCounts` takes,
-- plus the resident's current decision when a controller is loaded. Only the
-- fallback decisions count: an armed defender answering the alarm is doing the
-- opposite of standing clear.
function BaseManager.fallbackCount(rows)
    local count = 0
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.alive ~= false and row.away ~= true
            and row.present ~= false then
            local decision = tostring(row.decision or "")
            if decision == "base_withdraw" or decision == "base_hold" then
                count = count + 1
            end
        end
    end
    return count
end

-- BASE ADVICE (pure)
-- One authored sentence per problem the home projection can raise. This is the
-- leader's voice, not a second advice system: the key comes from the existing
-- attention item, and an unknown key has no line rather than a generic one.
local BASE_ADVICE_LINES = {
    raid = "Someone's coming for us. Get to the gate when it starts.",
    blocked = "We're stuck on a job. Something's missing and nobody's said what.",
    unshelved = "Somebody's still carrying a haul. We need a shelf for it.",
    security = "Nobody's watching the house. Give one of us a post.",
    security_unstaffed = "There's a post with nobody on it. It won't watch itself.",
    zones = "There's no work area here. We're just standing about.",
    storage = "Nothing's set aside for supplies. Show us where things go.",
    beds = "Some of us have no bed. Pick one for each of us.",
}

function BaseManager.baseAdvice(item)
    local key = type(item) == "table" and type(item.key) == "string" and item.key or ""
    local line = BASE_ADVICE_LINES[key]
    if type(line) ~= "string" then return nil end
    return line
end
-- END BASE ADVICE

local RESERVE_LABELS = {
    food = "Food", water = "Water", medical = "Medical", weapons = "Weapons",
    ammunition = "Ammo", tools = "Tools", building = "Materials",
    farming = "Farming", clothing = "Clothing", fuel = "Fuel", logs = "Logs",
}

function BaseManager.attentionItems(facts)
    local source = type(facts) == "table" and facts or {}
    local items = {}
    local function add(item) items[#items + 1] = item end

    local tasks = type(source.tasks) == "table" and source.tasks or {}
    local blocked = attentionWhole(tasks.blocked)
    local unshelved = attentionWhole(source.unshelved)
    local residents = attentionWhole(source.residents)
    local zones = attentionWhole(source.zones)
    local security = type(source.security) == "table" and source.security or {}
    local guards = attentionWhole(security.guardPosts)
    local patrols = attentionWhole(security.patrolRoutes)
    local understaffed = attentionWhole(security.understaffed)
    local bedsWithout = attentionWhole(source.bedsWithout)
    local kitShort = attentionWhole(source.kitShort)
    local kitUnknown = attentionWhole(source.kitUnknown)
    local storageAssigned = attentionWhole(source.storageAssigned)
    local shortage = type(source.shortage) == "table" and source.shortage or nil
    local shortageMissing = shortage ~= nil and attentionWhole(shortage.missing) or 0
    local shortageCurrent = shortage ~= nil and attentionWhole(shortage.current) or 0
    local shortageTarget = shortage ~= nil and attentionWhole(shortage.target) or 0
    -- A raid outranks every housekeeping problem: the copy belongs to the event
    -- owner, so this is one existing item fed by one projection, not a second
    -- threat model.
    local raid = type(source.raid) == "table" and source.raid
        and type(source.raid.title) == "string" and source.raid or nil

    if raid ~= nil then
        add({
            key = "raid",
            title = tostring(raid.title),
            detail = type(raid.detail) == "string" and raid.detail or nil,
            action = type(raid.action) == "string" and raid.action or "review_world",
            actionLabel = type(raid.actionLabel) == "string" and raid.actionLabel or "Review threat",
        })
    end
    if blocked > 0 then
        add({
            key = "blocked",
            title = attentionCount(blocked, "task is blocked", "tasks are blocked"),
            detail = "Work is waiting on a missing item or cause.",
            action = "review_tasks",
            actionLabel = "Review tasks",
        })
    end
    if unshelved > 0 then
        add({
            key = "unshelved",
            title = attentionCount(unshelved, "haul still unshelved", "hauls still unshelved"),
            detail = "A resident is still carrying supplies.",
            action = "review_storage",
            actionLabel = "Review storage",
        })
    end
    local depot = type(source.depot) == "table" and source.depot or nil
    if depot ~= nil and depot.full == true then
        add({
            key = "depot_full",
            title = "Depot floor is full",
            detail = type(depot.line) == "string" and depot.line
                or "The yard has no free tile left for another load.",
            action = "review_storage",
            actionLabel = "Review storage",
        })
    end
    if residents > 0 and guards + patrols == 0 then
        add({
            key = "security",
            title = "No security posts",
            detail = "Residents have no watch or patrol.",
            action = "add_guard",
            actionLabel = "Set guard post",
        })
    elseif understaffed > 0 then
        add({
            key = "security_unstaffed",
            title = attentionCount(understaffed,
                "security post is unstaffed", "security posts are unstaffed"),
            detail = "No resident is on watch.",
            action = "review_security",
            actionLabel = "Review areas",
        })
    end
    if residents > 0 and zones == 0 then
        add({
            key = "zones",
            title = "No work areas",
            detail = "Residents have nowhere to work.",
            action = "choose_area",
            actionLabel = "Choose area",
        })
    end
    if residents > 0 and storageAssigned == 0 then
        add({
            key = "storage",
            title = "No storage assigned",
            detail = "Residents have nowhere to shelve supplies.",
            action = "review_storage",
            actionLabel = "Review storage",
        })
    end
    if bedsWithout > 0 then
        add({
            key = "beds",
            title = attentionCount(bedsWithout,
                "resident has no bed", "residents have no bed"),
            detail = "Assign a bed from any bed's context menu.",
            action = "review_beds",
            actionLabel = "Review beds",
        })
    end
    if kitShort > 0 then
        add({
            key = "kits",
            title = attentionCount(kitShort,
                "role kit is short", "role kits are short"),
            detail = "Assigned role gear is not in stock.",
            action = "review_kits",
            actionLabel = "Review kits",
        })
    end
    if source.stockKnown == true and shortage ~= nil and shortageMissing > 0 then
        local label = RESERVE_LABELS[shortage.category]
            or tostring(shortage.label or shortage.category or "A reserve")
        local stock = shortageTarget > 0
            and (" (" .. tostring(shortageCurrent) .. " / " .. tostring(shortageTarget) .. ")") or ""
        local dry = source.waterSource == "dry" and shortage.category == "water"
        add({
            key = "reserve",
            title = label .. " is " .. tostring(shortageMissing) .. " below target" .. stock,
            detail = dry and "The taps are dry; stored water is the whole supply."
                or "Assigned storage is below the target.",
            action = "review_stock",
            actionLabel = "Review stock",
            stockKey = shortage.category ~= nil and tostring(shortage.category) or nil,
        })
    end
    if kitUnknown > 0 then
        add({
            key = "kits_unknown",
            title = attentionCount(kitUnknown,
                "resident is out of contact", "residents are out of contact"),
            detail = "Their readiness cannot be read out of contact.",
            action = "review_kits",
            actionLabel = "Review kits",
        })
    end

    local selected = {}
    for index = 1, math.min(3, #items) do selected[index] = items[index] end
    return selected
end
-- END BASE HOME ATTENTION

-- BASE HOME STATUS (read-only)
-- The base HUD and the notebook attention band need one answer about who is
-- home and what needs attention. This projection reads the existing duty,
-- away-team, task, storage, security and bed owners; it writes nothing. The
-- two-second cache is presentation only and is never persisted.
local homeStatusCache = {}
local HOME_STATUS_CACHE_MS = 2000
-- Session-only: a dry tap is announced once per base. This is a rail notice,
-- not a saved event or a second water state.
local waterShutNotified = {}

local function homeStatusNow()
    if getTimestampMs == nil then return 0 end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or 0
end

function BaseManager.waterShutNotice(baseName)
    local name = type(baseName) == "string" and baseName:match("^%s*(.-)%s*$") or ""
    if name == "" then return "The taps are dry. Water now comes from storage." end
    return "The taps are dry at " .. name .. ". Water now comes from storage."
end

function BaseManager.homeStatus(base, playerId, force)
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId
        or KnoxPersistence.getBaseResidentIds == nil then
        return nil
    end
    local residentIds = KnoxPersistence.getBaseResidentIds(base.id) or {}
    local now = homeStatusNow()
    local cached = homeStatusCache[base.id]
    if force ~= true and cached ~= nil
        and now - cached.at < HOME_STATUS_CACHE_MS
        and cached.residents == #residentIds then
        return cached.value
    end

    local controllerRuntime = rawget(_G, "KnoxSurvivorRuntime")
    local rows = {}
    for _, id in ipairs(residentIds) do
        local alive = KnoxPersistence.isSurvivorAlive == nil
            or KnoxPersistence.isSurvivorAlive(id) ~= false
        local present = KnoxPersistence.isSurvivorPresent == nil
            or KnoxPersistence.isSurvivorPresent(id) ~= false
        local away = KnoxPersistence.getAwayTeamForSurvivor ~= nil
            and KnoxPersistence.getAwayTeamForSurvivor(id) ~= nil
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(id) or nil
        local controller = controllerRuntime ~= nil
            and controllerRuntime.getController ~= nil
            and controllerRuntime.getController(id) or nil
        rows[#rows + 1] = {
            alive = alive,
            present = present,
            away = away,
            event = duty ~= nil and duty.eventId ~= nil,
            decision = controller ~= nil and controller.activeDecision or nil,
        }
    end
    local counts = BaseManager.homeCounts(rows)
    local fallback = BaseManager.fallbackCount(rows)

    local jobs = rawget(_G, "KnoxBaseJobs")
    local settlement = jobs ~= nil and jobs.settlementSummary ~= nil
        and jobs.settlementSummary(base, worldAge()) or nil
    local waterSource = settlement ~= nil and settlement.waterSource or nil
    if waterSource == "dry" then
        if not waterShutNotified[base.id] then
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then
                waterShutNotified[base.id] = true
                feed.event(BaseManager.waterShutNotice(base.name))
            end
        end
    else
        waterShutNotified[base.id] = nil
    end
    local tasks = settlement ~= nil and settlement.tasks or {}
    if settlement == nil then
        tasks = { queued = 0, claimed = 0, blocked = 0 }
        for _, task in pairs(base.tasks or {}) do
            if type(task) == "table" then
                local state = tostring(task.state or "queued")
                if tasks[state] ~= nil then tasks[state] = tasks[state] + 1 end
            end
        end
    end
    local security = settlement ~= nil and settlement.security or nil
    if security == nil and jobs ~= nil and jobs.securityCoverage ~= nil then
        security = jobs.securityCoverage(base)
    end
    security = security or { guardPosts = 0, patrolRoutes = 0, understaffed = 0 }

    local zones, storageAssigned = 0, 0
    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" and zone.enabled ~= false then
            zones = zones + 1
        end
    end
    for _ in pairs(base.storage or {}) do storageAssigned = storageAssigned + 1 end

    local bedRows = BaseManager.bedRoster(base, playerId) or {}
    local bedsWithout = 0
    for _, row in ipairs(bedRows) do
        if row.bed == nil then bedsWithout = bedsWithout + 1 end
    end

    local storageApi = rawget(_G, "KnoxBaseStorage")
    -- The depot is part of the home's storage answer, so the band reads it
    -- through the same projection instead of a panel of its own.
    local depot = nil
    if storageApi ~= nil and storageApi.depotStatus ~= nil then
        local depotOk, depotSummary = pcall(storageApi.depotStatus, base)
        if depotOk then depot = depotSummary end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local kitEntries, kitShort, kitUnknown = {}, 0, 0
    if storageApi ~= nil and storageApi.roleKitShortages ~= nil and runtime ~= nil then
        local roster = {}
        for _, id in ipairs(residentIds) do
            if KnoxPersistence.isSurvivorAlive == nil
                or KnoxPersistence.isSurvivorAlive(id) ~= false then
                local duty = KnoxPersistence.getSurvivorDuty ~= nil
                    and KnoxPersistence.getSurvivorDuty(id) or nil
                roster[#roster + 1] = {
                    id = id,
                    preference = duty ~= nil and duty.jobPreference or nil,
                    character = runtime.getCharacter ~= nil
                        and runtime.getCharacter(id) or nil,
                }
            end
        end
        kitEntries = storageApi.roleKitShortages(base, roster) or {}
        for _, entry in ipairs(kitEntries) do
            if entry.status == "shortage" then
                kitShort = kitShort + 1
            elseif entry.status == "unknown" then
                kitUnknown = kitUnknown + 1
            end
        end
    end

    local firstShortage = nil
    for _, reserve in ipairs(settlement ~= nil and settlement.reserves or {}) do
        local missing = tonumber(reserve.missing) or 0
        if missing > 0 and (firstShortage == nil or missing > firstShortage.missing) then
            firstShortage = {
                category = reserve.category,
                label = reserve.category,
                missing = missing,
                current = reserve.current,
                target = reserve.target,
            }
        end
    end

    local living = math.max(0, #residentIds - counts.dead)
    -- An inbound raid is the most urgent thing a home can face, so the same
    -- projection that powers the band, the pill and the in-world line carries
    -- it. The event owner supplies the sentence; this only hands it over.
    local raid = nil
    local events = rawget(_G, "KnoxEvents")
    if events ~= nil and events.inboundRaidForBase ~= nil then
        local watch = {
            posts = (tonumber(security.guardPosts) or 0) + (tonumber(security.patrolRoutes) or 0),
            staffed = tonumber(security.staffed) or 0,
            holding = fallback,
        }
        local ok, summary = pcall(function()
            return events.inboundRaidForBase(base.id, worldAge(), watch)
        end)
        if ok and type(summary) == "table" then raid = summary end
    end
    local facts = {
        residents = living,
        fallback = fallback,
        raid = raid,
        zones = zones,
        tasks = tasks,
        security = security,
        unshelved = settlement ~= nil and #(settlement.storageProblems or {}) or 0,
        storageAssigned = storageAssigned,
        depot = depot,
        bedsWithout = bedsWithout,
        kitShort = kitShort,
        kitUnknown = kitUnknown,
        stockKnown = settlement ~= nil and settlement.stockKnown == true,
        waterSource = settlement ~= nil and settlement.waterSource or nil,
        shortage = firstShortage,
    }
    local items = BaseManager.attentionItems(facts)
    local value = {
        home = counts.home,
        away = counts.away,
        missing = counts.missing,
        dead = counts.dead,
        attention = #items,
        items = items,
        facts = facts,
        settlement = settlement,
        beds = bedRows,
        kits = kitEntries,
    }
    homeStatusCache[base.id] = { at = now, residents = #residentIds, value = value }
    return value
end

-- The base line is a compact presentation of the same status. It never
-- recomputes attention: it only names the first existing item and the number
-- behind it. Clear and dead states stay explicit so the strip cannot imply
-- that a dead resident is merely another problem to review.
function BaseManager.baseLineModel(status)
    if type(status) ~= "table" then return nil end
    local items = type(status.items) == "table" and status.items or {}
    local item = type(items[1]) == "table" and items[1] or nil
    local attention = math.max(0, math.floor(tonumber(status.attention) or 0))
    local extra = math.max(0, attention - 1)
    local title = item ~= nil and tostring(item.title or "") or ""
    if item ~= nil and extra > 0 then
        title = title .. " +" .. tostring(extra)
    end
    local function count(value)
        return math.max(0, math.floor(tonumber(value) or 0))
    end
    return {
        expanded = item ~= nil,
        itemKey = item ~= nil and item.key or nil,
        itemAction = item ~= nil and item.action or nil,
        actionLabel = item ~= nil and tostring(item.actionLabel or "Review") or "",
        title = title,
        extra = extra,
        attention = attention,
        home = count(status.home),
        away = count(status.away),
        missing = count(status.missing),
        dead = count(status.dead),
    }
end
-- The standing order is the existing base intent spoken in plain words.
-- The caller supplies the label; this only joins it to the first real
-- attention item, so a resident cannot invent a problem or a priority.
function BaseManager.standingOrderText(label, status, homeName)
    local place = type(homeName) == "string" and homeName ~= ""
        and homeName or "The base"
    local items = type(status) == "table" and status.items or nil
    local top = type(items) == "table" and items[1] or nil
    local problem = top ~= nil and tostring(top.title or "") or ""
    local prefix = type(label) == "string" and label ~= ""
        and (place .. " is on " .. label)
        or (place .. " has no standing order")
    if problem ~= "" then
        return prefix .. "; the first fix is " .. problem:lower() .. "."
    end
    return prefix .. "; nothing pressing."
end

-- END BASE HOME STATUS

function BaseManager.get(id)
    return KnoxPersistence.getBase(id)
end

function BaseManager.getForOwner(ownerKind, ownerId)
    return KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
end

function BaseManager.establishPlayerBase(player, square)
    if player == nil or square == nil then
        return nil, "invalid_location"
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then
        return nil, "must_be_inside_building"
    end
    local existing = BaseManager.getForOwner("player", playerId)
    if existing ~= nil then
        return existing, existing.home ~= nil and existing.home.buildingId == area.buildingId
            and "existing" or "move_confirmation_required"
    end
    local territory = territoryAround(area, PLAYER_BASE_YARD_PADDING)
    if blockedBySurvivorSafehouse(territory) then
        return nil, "claimed_by_survivor_faction"
    end
    local base, result = KnoxPersistence.createBase(
        "player",
        playerId,
        area,
        worldAge(),
        territory
    )
    if base ~= nil then
        local faction = KnoxPersistence.ensurePlayerFaction(playerId, worldAge())
        faction.homeBaseId = base.id
        BaseManager.syncStructureProtection()
    end
    return base, result
end

-- Additional player base (outpost) in another building. The primary home
-- base is untouched: faction home, move flow and every singular getter
-- keep resolving to the earliest base. Territory overlap and faction
-- claims are enforced exactly like the first home.
function BaseManager.establishOutpost(player, square)
    if player == nil or square == nil then
        return nil, "invalid_location"
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then
        return nil, "must_be_inside_building"
    end
    local owned = KnoxPersistence.getBasesForOwner ~= nil
        and KnoxPersistence.getBasesForOwner("player", playerId) or {}
    for _, other in ipairs(owned) do
        if other ~= nil and other.home ~= nil
            and other.home.buildingId == area.buildingId then
            return other, "existing"
        end
    end
    local territory = territoryAround(area, PLAYER_BASE_YARD_PADDING)
    if blockedBySurvivorSafehouse(territory) then
        return nil, "claimed_by_survivor_faction"
    end
    local base, result = KnoxPersistence.createBase(
        "player",
        playerId,
        area,
        worldAge(),
        territory,
        true
    )
    if base == nil then return nil, result end
    base.name = "Outpost " .. tostring(#owned + 1)
    BaseManager.syncStructureProtection()
    return base, result
end

function BaseManager.movePlayerBase(player, square)
    if player == nil or square == nil then return nil, "invalid_location" end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = BaseManager.getForOwner("player", playerId)
    if base == nil then return BaseManager.establishPlayerBase(player, square) end
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then return nil, "must_be_inside_building" end
    if base.home ~= nil and base.home.buildingId == area.buildingId then
        return base, "existing"
    end
    local territory = territoryAround(area, PLAYER_BASE_YARD_PADDING)
    if blockedBySurvivorSafehouse(territory) then
        return nil, "claimed_by_survivor_faction"
    end
    local moved, result = KnoxPersistence.relocateBase(base.id, area, territory, worldAge())
    if moved ~= nil then
        BaseManager.syncStructureProtection()
    end
    return moved, result
end

function BaseManager.ensureFactionBase(faction)
    if faction == nil or faction.kind == "player" or faction.homeBase == nil then
        return nil, "not_ready"
    end
    local base = faction.homeBaseId ~= nil
        and KnoxPersistence.getBase(faction.homeBaseId)
        or nil
    -- A stale save may retain a base id after ownership changed or the base
    -- was replaced. Never let an NPC faction adopt a player/other-faction
    -- record just because its id still exists; rebuild the faction-owned
    -- record from the persisted home definition instead.
    if base ~= nil and (base.ownerKind ~= "faction" or base.ownerId ~= faction.id) then
        print("[KnoxSurvivors][BaseManager] discarded-stale-faction-base="
            .. tostring(faction.homeBaseId) .. " faction=" .. tostring(faction.id))
        if KnoxPersistence.clearFactionResidentBed ~= nil then
            for _, survivorId in ipairs(faction.memberIds or {}) do
                KnoxPersistence.clearFactionResidentBed(survivorId, faction.id)
            end
        end
        faction.homeBaseId = nil
        base = nil
    end
    local result = "existing"
    if base == nil then
        base, result = KnoxPersistence.createBase(
            "faction",
            faction.id,
            faction.homeBase,
            faction.homeBase.selectedAtHours or worldAge()
        )
        if base ~= nil then
            faction.homeBaseId = base.id
        end
    end
    if base ~= nil then
        -- Keep the settlement identity visible everywhere the player sees the
        -- property. Do not overwrite a name the player or a future UI has
        -- intentionally customized.
        if (base.name == nil or base.name == "" or base.name == "Survivor Camp")
            and type(faction.name) == "string" and faction.name ~= "" then
            base.name = faction.name .. " Base"
        end
        if KnoxSettings.autoGenerateBaseWorkAreas() then
            ensureFactionZones(base, faction)
            ensureFactionStorage(base)
        end
        for _, survivorId in ipairs(faction.memberIds or {}) do
            local resident, residentResult = KnoxPersistence.setFactionBaseResident(
                survivorId,
                faction.id,
                base.id,
                worldAge()
            )
            -- Base creation can happen while the leader is still active in the
            -- world. Notify that runtime immediately so it drops stale roaming
            -- or faction-scouting intent and begins resident duty on its next
            -- decision boundary. Persisted duty remains authoritative; this is
            -- only the in-memory handoff signal.
            if resident and residentResult ~= "existing"
                and KnoxSurvivorRuntime ~= nil
                and KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
                KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
            end
        end
        if KnoxSettings.autoGenerateBaseWorkAreas() then
            ensureFactionBeds(base, faction)
        end
        -- The leader now actually leads: this only changes the weight the
        -- existing job selector already reads, never a task or a roster.
        BaseManager.applyFactionIntent(
            base, faction, BaseManager.factionIntentFacts(faction, base), worldAge()
        )
    end
    return base, base ~= nil and result or "failed"
end

function BaseManager.ensureFactionBases()
    for _, faction in pairs(KnoxPersistence.getFactions()) do
        BaseManager.ensureFactionBase(faction)
    end
end

-- Exposed for focused offline coverage; gameplay invokes it through the
-- canonical faction-base refresh above.
BaseManager.ensureFactionBeds = ensureFactionBeds

function BaseManager.ensurePlayerBases()
    -- Player work areas and storage policies are explicit choices made through
    -- the Notebook. Automatic planning is reserved for autonomous NPC bases.
end

function BaseManager.containsSquare(base, square)
    local home = base ~= nil and (base.territory or base.home) or nil
    if home == nil or square == nil then
        return false
    end
    local x = square:getX()
    local y = square:getY()
    local maxX = home.maxX or (home.minX + home.width - 1)
    local maxY = home.maxY or (home.minY + home.height - 1)
    local floorMatches = home.allFloors == true or square:getZ() == (home.z or 0)
    if floorMatches and x >= home.minX and x <= maxX and y >= home.minY and y <= maxY then
        return true
    end
    -- A compound base is its buildings. A barn across the street is inside the
    -- base even when the boundary drawn around the house is not, so work,
    -- storage and structure protection read the same membership the claim wrote.
    for _, establishment in pairs(base.establishments or {}) do
        local area = type(establishment) == "table" and establishment.area or nil
        local compound = rawget(_G, "KnoxBaseCompound")
        if area ~= nil and compound ~= nil and compound.contains(area, x, y)
            and (tonumber(area.z) or 0) == (square:getZ() or 0) then
            return true
        end
    end
    return false
end

function BaseManager.setTerritory(player, baseId, firstSquare, secondSquare)
    local base = BaseManager.get(baseId)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId
        or firstSquare == nil or secondSquare == nil then
        return nil, "not_your_base"
    end
    local territory, result = KnoxPersistence.updateBaseTerritory(baseId, {
        minX = firstSquare:getX(),
        minY = firstSquare:getY(),
        maxX = secondSquare:getX(),
        maxY = secondSquare:getY(),
    }, worldAge())
    if territory ~= nil then
        BaseManager.syncStructureProtection()
    end
    return territory, result
end

-- LEADER INTENT (pure)
-- An NPC faction's leader chooses what the settlement cares about. Only facts
-- that already have a producer are consulted: an inbound raid for this base,
-- and the group's own member count against its own minimum strength. A leader
-- below strength works on growth, a raid always outranks that, and with
-- neither fact the leader keeps the intent it already had instead of being
-- handed an invented priority. Hunger, wounds, beds and diplomacy have no cheap
-- producer here, so they are deliberately not guessed at.
function BaseManager.chooseIntent(facts, current)
    if type(facts) ~= "table" then return current, "unchanged" end
    if facts.raidInbound == true then return "security", "raid_inbound" end
    local members = tonumber(facts.members)
    local minimum = tonumber(facts.minimumMembers)
    if members ~= nil and minimum ~= nil and minimum > 0 and members < minimum then
        return "growth", "under_strength"
    end
    return current, "unchanged"
end

function BaseManager.factionIntentFacts(faction, base)
    local facts = {
        members = type(faction) == "table" and #(faction.memberIds or {}) or 0,
    }
    if KnoxSettings ~= nil and KnoxSettings.npcFactionMinimumMembers ~= nil then
        local ok, value = pcall(KnoxSettings.npcFactionMinimumMembers)
        if ok then facts.minimumMembers = tonumber(value) end
    end
    local events = rawget(_G, "KnoxEvents")
    if events ~= nil and events.inboundRaidForBase ~= nil
        and type(base) == "table" then
        local ok, raid = pcall(events.inboundRaidForBase, base.id, worldAge())
        facts.raidInbound = ok and type(raid) == "table"
    end
    return facts
end

function BaseManager.applyFactionIntent(base, faction, facts, worldAgeHours)
    if type(base) ~= "table" or type(faction) ~= "table" then
        return nil, "not_ready"
    end
    local chosen, reason = BaseManager.chooseIntent(facts, base.intent)
    if chosen == nil then return nil, reason end
    if chosen == base.intent then return chosen, "unchanged" end
    if KnoxPersistence.setFactionBaseIntent == nil then
        return nil, "writer_unavailable"
    end
    local ok, detail = KnoxPersistence.setFactionBaseIntent(
        base.id, faction.id, chosen, worldAgeHours
    )
    if ok ~= true then return nil, tostring(detail) end
    return chosen, reason
end
-- END LEADER INTENT

-- BASE RALLY (pure)
-- A resident who is not sent at the intruder still has to leave the room the
-- intruder is in, and the design says a retreat without a rally point is just
-- running. The base already knows its own walls, so it owns the choice: the
-- corner of the stored territory farthest from the intruder, inset by a tile
-- so a body can stand there, on the intruder's floor. Pure arithmetic over
-- stored bounds; the caller asks the cell whether the square can be stood on.
BaseManager.RALLY_INSET = 1
BaseManager.RALLY_CORNERED_DISTANCE = 64

local function rallyBounds(bounds)
    if type(bounds) ~= "table" then return nil end
    local minX, minY = tonumber(bounds.minX), tonumber(bounds.minY)
    if minX == nil or minY == nil then return nil end
    local maxX = tonumber(bounds.maxX) or (minX + (tonumber(bounds.width) or 0) - 1)
    local maxY = tonumber(bounds.maxY) or (minY + (tonumber(bounds.height) or 0) - 1)
    if maxX < minX or maxY < minY then return nil end
    return minX, minY, maxX, maxY
end

-- Every corner the base can offer, best first. A single best corner is not
-- enough: the first one can be a wall, or a walk that passes the intruder, and
-- the caller must be able to reject it without losing the fallback. The order
-- is the order `defenceRally` has always weighed the corners in, so a tie still
-- resolves to the same square it always did.
function BaseManager.rallyCandidates(bounds, threat, options)
    local minX, minY, maxX, maxY = rallyBounds(bounds)
    if minX == nil then return nil, "no_bounds" end
    if type(threat) ~= "table" then return nil, "no_threat" end
    local tx, ty = tonumber(threat.x), tonumber(threat.y)
    if tx == nil or ty == nil then return nil, "no_threat" end
    local inset = math.floor(tonumber(type(options) == "table" and options.inset)
        or BaseManager.RALLY_INSET)
    if inset < 0 then inset = 0 end
    local lowX, highX = minX + inset, maxX - inset
    local lowY, highY = minY + inset, maxY - inset
    if highX < lowX then lowX, highX = minX, maxX end
    if highY < lowY then lowY, highY = minY, maxY end
    local z = tonumber(threat.z) or tonumber(bounds.z) or 0
    local ranked = {}
    for _, corner in ipairs({
        { lowX, lowY }, { highX, lowY }, { lowX, highY }, { highX, highY },
    }) do
        local dx, dy = corner[1] - tx, corner[2] - ty
        ranked[#ranked + 1] = {
            x = corner[1], y = corner[2], z = z,
            distance2 = dx * dx + dy * dy,
        }
    end
    if #ranked == 0 then return nil, "no_corner" end
    -- Selection sort with a strict comparison: equal scores keep input order.
    for index = 1, #ranked - 1 do
        local bestIndex = index
        for other = index + 1, #ranked do
            if ranked[other].distance2 > ranked[bestIndex].distance2 then
                bestIndex = other
            end
        end
        ranked[index], ranked[bestIndex] = ranked[bestIndex], ranked[index]
    end
    for _, entry in ipairs(ranked) do
        entry.cornered = entry.distance2 < BaseManager.RALLY_CORNERED_DISTANCE
        entry.reason = entry.cornered and "cornered" or "away_from_threat"
    end
    return ranked
end

-- The corner the base would pick if nobody asked whether it can be reached.
-- Kept as the first entry of the ranked list so the two cannot disagree.
function BaseManager.defenceRally(bounds, threat, options)
    local ranked, reason = BaseManager.rallyCandidates(bounds, threat, options)
    if ranked == nil then return nil, reason end
    return ranked[1]
end
-- Can a body actually walk from one square of this base to another? The
-- straight line says no the moment a wall stands in it, even where the room
-- continues around that wall, so a fallback needs the building's own
-- connectivity rather than a direction. Pure: the caller supplies
-- `passable(fromX, fromY, toX, toY)` and the search never looks outside the
-- stored territory. Cardinal steps only - squeezing diagonally between two
-- walls is not a walk the native mover will take.
BaseManager.RALLY_REACH_STEPS = 200

function BaseManager.rallyReach(bounds, from, to, passable, options)
    local minX, minY, maxX, maxY = rallyBounds(bounds)
    if minX == nil then return nil, "no_bounds" end
    if type(passable) ~= "function" then return nil, "no_pass" end
    if type(from) ~= "table" or type(to) ~= "table" then return nil, "no_square" end
    local fx, fy = tonumber(from.x), tonumber(from.y)
    local tx, ty = tonumber(to.x), tonumber(to.y)
    if fx == nil or fy == nil or tx == nil or ty == nil then return nil, "no_square" end
    fx, fy, tx, ty = math.floor(fx), math.floor(fy), math.floor(tx), math.floor(ty)
    local function inside(x, y)
        return x >= minX and x <= maxX and y >= minY and y <= maxY
    end
    if not inside(fx, fy) or not inside(tx, ty) then return nil, "outside" end
    local maxSteps = math.max(0, math.floor(tonumber(type(options) == "table"
        and options.maxSteps) or BaseManager.RALLY_REACH_STEPS))
    local span = math.max(maxX - minX + 1, maxY - minY + 1)
    local function key(x, y)
        return (y - minY) * span + (x - minX)
    end
    local startKey, goalKey = key(fx, fy), key(tx, ty)
    if startKey == goalKey then
        return { steps = 0, path = { { x = fx, y = fy } } }
    end
    local seen, parent, stepsByKey = { [startKey] = true }, {}, { [startKey] = 0 }
    local queue, head, tail = { { fx, fy } }, 1, 1
    local found, truncated = false, false
    while head <= tail and not found do
        local node = queue[head]
        head = head + 1
        local nx, ny = node[1], node[2]
        local nodeKey = key(nx, ny)
        local step = stepsByKey[nodeKey]
        if step >= maxSteps then
            -- The caller's budget is a promise: do not explore past it, but
            -- remember that "not found" was a stopping point, not a wall.
            truncated = true
        else
            for _, delta in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local ax, ay = nx + delta[1], ny + delta[2]
                local ak = key(ax, ay)
                if inside(ax, ay) and not seen[ak] then
                    local ok, open = pcall(passable, nx, ny, ax, ay)
                    if ok and open == true then
                        seen[ak] = true
                        parent[ak] = nodeKey
                        stepsByKey[ak] = step + 1
                        tail = tail + 1
                        queue[tail] = { ax, ay }
                        if ak == goalKey then found = true end
                    end
                end
            end
        end
    end
    if not found then
        return nil, truncated and "too_far" or "unreachable"
    end
    local path, cursor = {}, goalKey
    while cursor ~= nil and #path <= maxSteps + 1 do
        table.insert(path, 1, {
            x = math.floor(cursor % span) + minX,
            y = math.floor(cursor / span) + minY,
        })
        if cursor == goalKey then
            path[1].x, path[1].y = tx, ty
        end
        cursor = parent[cursor]
        if cursor == startKey then
            table.insert(path, 1, { x = fx, y = fy })
            return { steps = stepsByKey[goalKey], path = path }
        end
    end
    return nil, "unreachable"
end
-- END BASE RALLY

function BaseManager.playerBaseAtSquare(square)
    for _, base in pairs(KnoxPersistence.getBases()) do
        if base ~= nil and base.ownerKind == "player"
            and BaseManager.containsSquare(base, square) then
            return base
        end
    end
    return nil
end

function BaseManager.canDamageStructure(survivorId, square)
    local base = BaseManager.playerBaseAtSquare(square)
    if base == nil then
        return true
    end
    return KnoxPersistence.isSurvivorHostileToPlayer(
        survivorId,
        base.ownerId
    )
end

function BaseManager.syncStructureProtection()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.setNpcProtectedArea == nil then
        return
    end
    local protected = nil
    local protectedPlayerId = nil
    for _, base in pairs(KnoxPersistence.getBases()) do
        if base ~= nil and base.ownerKind == "player" then
            protected = base.territory or base.home
            protectedPlayerId = base.ownerId
            break
        end
    end
    for _, survivorId in ipairs(KnoxSurvivorRuntime.activeIds()) do
        if protected == nil or KnoxPersistence.isSurvivorHostileToPlayer(
                survivorId,
                protectedPlayerId
            ) then
            bridge:clearNpcProtectedArea(survivorId)
        else
            bridge:setNpcProtectedArea(
                survivorId,
                protected.minX,
                protected.minY,
                protected.maxX or (protected.minX + protected.width - 1),
                protected.maxY or (protected.minY + protected.height - 1)
            )
        end
    end
end

function BaseManager.addZone(baseId, zoneType, bounds, label)
    if BaseManager.ZONE_TYPES[zoneType] ~= true then
        return nil, "unknown_zone_type"
    end
    return KnoxPersistence.addBaseZone(baseId, zoneType, bounds, label)
end

function BaseManager.containerReference(object, requestedContainerIndex, baseId)
    local square = object ~= nil and object:getSquare() or nil
    local containerIndex = math.max(0, tonumber(requestedContainerIndex) or 0)
    local container = object ~= nil and object.getContainerByIndex ~= nil
        and object:getContainerByIndex(containerIndex)
        or (object ~= nil and object:getContainer() or nil)
    if square == nil or container == nil then
        return nil
    end
    local objectIndex = object:getObjectIndex()
    local containerType = tostring(container:getType() or "container")
    local marker = object:getModData()
    marker.KnoxSurvivors = marker.KnoxSurvivors or {}
    marker.KnoxSurvivors.storageIds = marker.KnoxSurvivors.storageIds or {}
    local markerKey = tostring(baseId or "unbound") .. ":" .. tostring(containerIndex)
    local stableId = marker.KnoxSurvivors.storageIds[markerKey]
    if type(stableId) ~= "string" or stableId == "" then
        stableId = tostring(baseId or "base") .. ":container:"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY())
            .. ":" .. tostring(square:getZ()) .. ":" .. tostring(objectIndex)
            .. ":" .. tostring(containerIndex)
        marker.KnoxSurvivors.storageIds[markerKey] = stableId
        if object.transmitModData ~= nil then
            object:transmitModData()
        end
    end
    return {
        key = stableId,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = objectIndex,
        containerIndex = containerIndex,
        containerType = containerType,
    }
end

function BaseManager.setStoragePolicy(baseId, object, category, containerIndex)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or object == nil or not BaseManager.containsSquare(base, object:getSquare()) then
        return nil, "outside_base"
    end
    if category == "depot" then return nil, "main_supplies_retired" end
    if BaseManager.STORAGE_CATEGORIES[category] ~= true then return nil, "unknown_storage_category" end
    local reference = BaseManager.containerReference(object, containerIndex, baseId)
    if reference == nil then return nil, "not_a_container" end
    local kind = string.lower(reference.containerType)
    if kind == "corpse" or kind:find("water", 1, true) or kind:find("rain", 1, true) then
        return nil, "use_item_storage"
    end
    -- Normalize legacy references before adding an explicit store.
    KnoxBaseStorage.policies(base)
    -- One lookup, at assignment time: the policy remembers the room so no
    -- reader has to guess which building a shelf belongs to later.
    local compound = rawget(_G, "KnoxBaseCompound")
    if compound ~= nil and compound.roomIdentity ~= nil then
        local identity = compound.roomIdentity(base, reference.x, reference.y, reference.z)
        if identity ~= nil then
            reference.roomKey = identity.roomKey
            reference.roomLabel = identity.roomLabel
            reference.establishmentId = identity.establishmentId
        end
    end
    local policy, result = KnoxPersistence.setBaseStoragePolicy(baseId, reference, category, false)
    if policy ~= nil then
        -- Mirror the assigned type onto the world container and apply the
        -- native capacity ceiling while retaining the pre-assignment value for
        -- the existing storage-removal boundary.
        local container = object.getContainerByIndex ~= nil
            and object:getContainerByIndex(tonumber(containerIndex) or 0) or nil
        if container ~= nil then
            if KnoxBaseStorage.syncContainerName ~= nil then
                KnoxBaseStorage.syncContainerName(policy, container)
            end
            if KnoxToolCupboard ~= nil and KnoxToolCupboard.applyInfinite ~= nil then
                pcall(function()
                    KnoxToolCupboard.applyInfinite(
                        object, container, policy.key, containerIndex
                    )
                end)
            end
        end
    end
    return policy, result
end

function BaseManager.setStorageFilters(baseId, object, filters, containerIndex)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or object == nil
        or not BaseManager.containsSquare(base, object:getSquare()) then
        return nil, "outside_base"
    end
    if type(filters) ~= "table" then return nil, "invalid_storage_filters" end
    for category, enabled in pairs(filters) do
        if enabled == true and not KnoxBaseStorage.isValidFilterCategory(category) then
            return nil, "unknown_storage_category"
        end
    end
    local reference = BaseManager.containerReference(object, containerIndex, baseId)
    if reference == nil then return nil, "not_a_container" end
    local kind = string.lower(reference.containerType)
    if kind == "corpse" or kind:find("water", 1, true) or kind:find("rain", 1, true) then
        return nil, "use_item_storage"
    end
    -- The same room lookup as the typed path: a container sorted by exact
    -- items is as addressable as one sorted by category.
    local compound = rawget(_G, "KnoxBaseCompound")
    if compound ~= nil and compound.roomIdentity ~= nil then
        local identity = compound.roomIdentity(base, reference.x, reference.y, reference.z)
        if identity ~= nil then
            reference.roomKey = identity.roomKey
            reference.roomLabel = identity.roomLabel
            reference.establishmentId = identity.establishmentId
        end
    end
    local policy, result = KnoxPersistence.setBaseStorageFilters(baseId, reference, filters)
    if policy ~= nil then
        local container = object.getContainerByIndex ~= nil
            and object:getContainerByIndex(tonumber(containerIndex) or 0) or nil
        if container ~= nil then
            if KnoxBaseStorage.syncContainerName ~= nil then
                KnoxBaseStorage.syncContainerName(policy, container)
            end
            if KnoxToolCupboard ~= nil and KnoxToolCupboard.applyInfinite ~= nil then
                pcall(function()
                    KnoxToolCupboard.applyInfinite(object, container, policy.key, containerIndex)
                end)
            end
        end
    end
    return policy, result
end

local function findTraitDefinition(id)
    local definitions = CharacterTraitDefinition.getTraits()
    for index = 0, definitions:size() - 1 do
        local definition = definitions:get(index)
        if definition ~= nil and tostring(definition:getType()) == id then
            return definition
        end
    end
    return nil
end

local function meetsRequirements(survivorId, profile, requirements, base)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    for perkId, required in pairs(requirements ~= nil and requirements.skills or {}) do
        local level = KnoxSurvivorCapabilities.skillLevel(profile, perkId)
        local perk = character ~= nil and Perks.FromString(perkId) or nil
        if perk ~= nil then
            level = character:getPerkLevel(perk)
        end
        if level < (tonumber(required) or 0) then
            return false, "skill=" .. tostring(perkId)
        end
    end
    for _, traitId in ipairs(requirements ~= nil and requirements.traits or {}) do
        local hasTrait = KnoxSurvivorCapabilities.hasTrait(profile, traitId)
        local definition = character ~= nil and findTraitDefinition(traitId) or nil
        if definition ~= nil then
            hasTrait = character:hasTrait(definition:getType())
        end
        if not hasTrait then
            return false, "trait=" .. tostring(traitId)
        end
    end
    for _, recipeId in ipairs(requirements ~= nil and requirements.recipes or {}) do
        if character == nil or not character:getKnownRecipes():contains(recipeId) then
            return false, "recipe=" .. tostring(recipeId)
        end
    end
    local available, reason = KnoxBaseStorage.requirementsAvailable(
        base,
        character,
        requirements
    )
    return available, available and "eligible" or reason
end

-- Depot filters are the container filters. The zone record is policy-shaped,
-- so this writer normalises the same keys a container policy takes and nothing
-- else has to learn a second filter vocabulary.
function BaseManager.setZoneFilters(baseId, zoneId, filters)
    local base = BaseManager.get(baseId)
    local zone = base ~= nil and base.zones ~= nil and base.zones[zoneId] or nil
    if base == nil or zone == nil then return nil, "unknown_zone" end
    if base.ownerKind ~= "player" then return nil, "not_player_base" end
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage == nil or not storage.isDepotZone(zone) then return nil, "not_a_depot" end
    local kept = {}
    for key, enabled in pairs(type(filters) == "table" and filters or {}) do
        if enabled == true and storage.isValidFilterCategory(key) then kept[key] = true end
    end
    zone.storageFilters = kept
    zone.storageFilterVersion = 1
    zone.depot = true
    return zone, "saved"
end

function BaseManager.canPerformTask(survivorId, baseId, task)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then
        return false, "base_missing"
    end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil or duty.mode ~= "base" or duty.baseId ~= baseId then
        return false, "not_base_resident"
    end
    local profile = KnoxPersistence.getSurvivorCapabilities(survivorId)
    if profile == nil then
        return false, "capabilities_missing"
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local square=character~=nil and character:getCurrentSquare() or nil
    local jobs=rawget(_G,"KnoxBaseJobs")
    local atWork=square~=nil and jobs~=nil and jobs.containsWorkSquare~=nil
        and jobs.containsWorkSquare(base,square)
    if square==nil or (not BaseManager.containsSquare(base,square) and not atWork) then
        return false, "not_physically_at_base"
    end
    if task ~= nil and task.target ~= nil and task.target.action == "repair_engine" then
        local engine = rawget(_G, "KS_BaseEngineRepairs")
        if engine == nil or engine.resolveTarget(base, task.target, character) == nil then
            return false, "engine_work_unavailable"
        end
    end
    -- Real pain is a reason a person gives, not a hidden penalty. The same gate
    -- that already answers "can this resident do this task" refuses heavy work
    -- while the body reports it, so an automatic worker turns to lighter work
    -- instead of being silently slowed, and a player assignment is refused with
    -- a readable cause. Light work, and a body whose pain cannot be read, are
    -- untouched.
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs ~= nil and needs.heavyWorkRefusal ~= nil and task ~= nil then
        local taskType = task.type
        if taskType == nil and task.target ~= nil then taskType = task.target.action end
        -- The gate owns the verdict, not the wording: pain and infection are
        -- different body facts and the player-facing reason says which.
        local refusal = needs.heavyWorkRefusal(character, taskType)
        if refusal ~= nil then
            return false, tostring(refusal)
        end
    end
    return meetsRequirements(
        survivorId,
        profile,
        task ~= nil and task.requirements or nil,
        base
    )
end

-- BASE LAYOUT PROPOSAL (pure)
-- This reads loaded rooms, containers and cooking appliances and returns ordinary
-- addZone entries. It does not
-- create work, choose residents or rewrite an existing area.

local LAYOUT_ROOM_RULES = {
    { zoneType = "cooking", label = "Kitchen", words = {
        "kitchen", "pantry", "cafeteria", "restaurant", "diner", "bakery",
    } },
    { zoneType = "repair", label = "Workshop", words = {
        "garage", "workshop", "workbench", "tool", "utility", "maintenance",
    } },
    { zoneType = "farming", label = "Garden", words = {
        "garden", "greenhouse", "farm", "barn",
    } },
    { zoneType = "general", label = "Store Room", needsContainers = true, words = {
        "storage", "store room", "storeroom", "warehouse", "stockroom", "closet",
    } },
}

local LAYOUT_SKIP_WORDS = {
    "bedroom", "bathroom", "toilet", "laundry", "medical", "clinic",
    "infirmary", "living", "dining", "hall", "corridor", "landing", "stairs",
}

local LAYOUT_ORDER = { cooking = 1, repair = 2, farming = 3, general = 4,
    woodcutting = 5, log_processing = 6, guard = 7 }

local function layoutText(value)
    return string.lower(tostring(value or ""))
end

local function layoutContains(text, word)
    return string.find(text, word, 1, true) ~= nil
end

local function layoutRoomName(room)
    if room == nil or room.getName == nil then return "" end
    local ok, value = pcall(function() return room:getName() end)
    return ok and tostring(value or "") or ""
end

local function layoutRoomBounds(room, fallbackZ)
    if room == nil or room.getRects == nil then return nil end
    local minX, minY, maxX, maxY, z = nil, nil, nil, nil, nil
    local ok = pcall(function()
        local rects = room:getRects()
        if rects == nil or rects.size == nil or rects.get == nil then return end
        for index = 0, rects:size() - 1 do
            local rect = rects:get(index)
            local x = tonumber(rect:getX())
            local y = tonumber(rect:getY())
            local w = tonumber(rect:getW())
            local h = tonumber(rect:getH())
            if x ~= nil and y ~= nil and w ~= nil and h ~= nil and w > 0 and h > 0 then
                minX = minX == nil and x or math.min(minX, x)
                minY = minY == nil and y or math.min(minY, y)
                maxX = maxX == nil and (x + w - 1) or math.max(maxX, x + w - 1)
                maxY = maxY == nil and (y + h - 1) or math.max(maxY, y + h - 1)
            end
        end
        if room.getZ ~= nil then z = tonumber(room:getZ()) end
    end)
    if not ok or minX == nil then return nil end
    return {
        x1 = minX, y1 = minY, x2 = maxX, y2 = maxY,
        z = z ~= nil and z or (tonumber(fallbackZ) or 0),
    }
end

local LAYOUT_STORAGE_RULES = {
    { categories = { "food", "water" }, words = {
        "kitchen", "pantry", "cafeteria", "restaurant", "diner", "bakery",
    } },
    { categories = { "medical" }, words = {
        "bathroom", "toilet", "laundry", "medical", "clinic", "infirmary",
    } },
    { categories = { "logs" }, words = {
        "log store", "log storage", "lumber room", "lumber storage",
        "lumber yard", "wood store", "wood storage", "wood shed", "woodpile",
    } },
    { categories = { "fuel" }, words = {
        "fuel store", "fuel storage", "fuel room", "fuel shed",
        "generator room", "generator shed", "gas store", "gas storage",
    } },
    { categories = { "tools", "building", "fuel" }, words = {
        "garage", "workshop", "workbench", "tool", "utility", "maintenance",
        "shed",
    } },
    { categories = { "farming" }, words = {
        "garden", "greenhouse", "farm", "barn",
    } },
    { categories = { "general" }, words = {
        "storage", "store room", "storeroom", "warehouse", "stockroom", "closet",
    } },
}

local LAYOUT_STORAGE_SKIP_WORDS = {
    "bedroom", "living", "dining", "hall", "corridor", "landing", "stairs",
}

local LAYOUT_BAD_CONTAINER_WORDS = {
    "toilet", "sink", "bathtub", "shower", "trash", "garbage", "compost",
    "corpse", "floor", "water", "rain",
}

local LAYOUT_STORAGE_LABELS = {
    food = "Food & Drink", water = "Water", medical = "Medical",
    tools = "Tools", building = "Materials", farming = "Farming",
    fuel = "Fuel", general = "General Storage", logs = "Logs & Lumber",
    weapons = "Weapons", ammunition = "Ammunition",
}

local LAYOUT_STORAGE_ORDER = {
    food = 1, water = 2, medical = 3, tools = 4, building = 5,
    fuel = 6, farming = 7, general = 8, logs = 9, weapons = 10, ammunition = 11,
}

local LAYOUT_SECURE_STORAGE_WORDS = {
    "armory", "armoury", "gun room", "weapons", "ammunition", "ammo",
    "vault", "safe room",
}

local function layoutContainsAny(text, words)
    for _, word in ipairs(words) do
        if layoutContains(text, word) then return true end
    end
    return false
end

local function layoutContainers(bounds)
    if bounds == nil or getCell == nil then return {} end
    local cell = getCell()
    if cell == nil then return {} end
    local result = {}
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            local square = cell:getGridSquare(x, y, bounds.z)
            local objects = square ~= nil and square.getObjects ~= nil
                and square:getObjects() or nil
            if objects ~= nil and objects.size ~= nil and objects.get ~= nil then
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local count = object ~= nil and object.getContainerCount ~= nil
                        and object:getContainerCount() or 0
                    for containerIndex = 0, count - 1 do
                        local container = object.getContainerByIndex ~= nil
                            and object:getContainerByIndex(containerIndex) or nil
                        local exists = container ~= nil
                            and (container.isExistYet == nil or container:isExistYet() ~= false)
                        if exists then
                            local kind = container.getType ~= nil
                                and layoutText(container:getType()) or ""
                            if kind ~= ""
                                and not layoutContainsAny(kind, LAYOUT_BAD_CONTAINER_WORDS) then
                                result[#result + 1] = {
                                    object = object, container = container,
                                    containerIndex = containerIndex, kind = kind,
                                    square = square,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

local function layoutContainerCount(bounds)
    return #layoutContainers(bounds)
end

local function layoutObjectSquare(object)
    if object == nil or object.getSquare == nil then return nil end
    local ok, square = pcall(function() return object:getSquare() end)
    return ok and square or nil
end

local function layoutObjectIndex(object)
    if object == nil or object.getObjectIndex == nil then return nil end
    local ok, index = pcall(function() return object:getObjectIndex() end)
    return ok and tonumber(index) or nil
end

local function layoutStorageAssigned(base, category)
    for _, policy in pairs(base ~= nil and base.storage or {}) do
        if policy ~= nil and (policy.storageRole == category or policy.category == category) then
            return true
        end
        if policy ~= nil and policy.storageFilterVersion == 1
            and type(policy.storageFilters) == "table"
            and policy.storageFilters[category] == true then
            return true
        end
    end
    return false
end

local function layoutContainerAssigned(base, object, containerIndex)
    local square = layoutObjectSquare(object)
    if square == nil then return false end
    local objectIndex = layoutObjectIndex(object)
    local wantedIndex = tonumber(containerIndex)
    for _, policy in pairs(base ~= nil and base.storage or {}) do
        if policy ~= nil
            and tonumber(policy.x) == tonumber(square:getX())
            and tonumber(policy.y) == tonumber(square:getY())
            and tonumber(policy.z or 0) == tonumber(square:getZ() or 0)
            and tonumber(policy.containerIndex or 0) == wantedIndex
            and (objectIndex == nil or tonumber(policy.objectIndex) == objectIndex) then
            return true
        end
    end
    return false
end

local function layoutIsSecureRoomName(name)
    local text = layoutText(name)
    return text ~= "" and layoutContainsAny(text, LAYOUT_SECURE_STORAGE_WORDS)
end

local function layoutIsStorageRoom(name)
    local text = layoutText(name)
    if text == "" or layoutContainsAny(text, LAYOUT_STORAGE_SKIP_WORDS) then
        return false
    end
    if layoutIsSecureRoomName(text) then return false end
    for _, rule in ipairs(LAYOUT_STORAGE_RULES) do
        if #rule.categories == 1 and rule.categories[1] == "general"
            and layoutContainsAny(text, rule.words) then
            return true
        end
    end
    return false
end

local function layoutStorageCategories(name, containerCount, reachable)
    local text = layoutText(name)
    if text == "" then return {} end
    if layoutContainsAny(text, LAYOUT_STORAGE_SKIP_WORDS) then return {} end
    if layoutIsSecureRoomName(text) then
        if reachable == true then return { "weapons", "ammunition" } end
        return {}
    end
    for _, rule in ipairs(LAYOUT_STORAGE_RULES) do
        if layoutContainsAny(text, rule.words) then return rule.categories end
    end
    if (tonumber(containerCount) or 0) > 0 then return { "general" } end
    return {}
end

local function layoutContainerEligible(entry, category)
    local kind = layoutText(entry ~= nil and entry.kind or "")
    if kind == "" or layoutContainsAny(kind, LAYOUT_BAD_CONTAINER_WORDS) then
        return false
    end
    if category == "food"
        and (layoutContains(kind, "fridge") or layoutContains(kind, "freezer")) then
        return true
    end
    if KnoxToolCupboard ~= nil and KnoxToolCupboard.isDryContainerType ~= nil then
        return KnoxToolCupboard.isDryContainerType(kind) == true
    end
    return kind ~= "corpse" and not layoutContains(kind, "water")
        and not layoutContains(kind, "rain")
end

local function layoutContainerScore(kind, category)
    kind = layoutText(kind)
    if category == "food" then
        if layoutContains(kind, "fridge") or layoutContains(kind, "freezer") then
            return 30
        end
        return 10
    end
    if category == "medical" then
        if layoutContainsAny(kind, { "cabinet", "cupboard", "drawer", "shelf", "locker" }) then
            return 20
        end
        return 10
    end
    if category == "tools" then
        if layoutContainsAny(kind, { "cupboard", "counter", "drawer", "locker", "cabinet" }) then
            return 20
        end
        return 10
    end
    if category == "fuel" then
        if layoutContainsAny(kind, { "crate", "shelf", "pallet" }) then return 20 end
        return 10
    end
    if category == "building" or category == "farming" then
        if layoutContainsAny(kind, { "crate", "shelf", "pallet" }) then return 20 end
        return 10
    end
    if category == "weapons" or category == "ammunition" then
        if layoutContainsAny(kind, { "locker", "safe", "cabinet", "crate" }) then return 20 end
        return 10
    end
    if category == "logs" then
        if layoutContainsAny(kind, { "woodpile", "pallet", "crate" }) then return 20 end
        return 10
    end
    if category == "general" then
        -- Leave a locker, safe or cabinet for the reachable weapons fallback;
        -- crates, shelves and pallets remain the ordinary general store.
        if layoutContainsAny(kind, { "locker", "safe", "cabinet" }) then return 5 end
        return 10
    end
    return 10
end

local function layoutLockableContainerKind(kind)
    return layoutContainsAny(layoutText(kind), { "locker", "safe", "cabinet" })
end

local function layoutContainerKind(object, containerIndex)
    if object == nil or object.getContainerByIndex == nil then return "" end
    local index = tonumber(containerIndex)
    if index == nil then return "" end
    local ok, container = pcall(function() return object:getContainerByIndex(index) end)
    if not ok or container == nil or container.getType == nil then return "" end
    local read, kind = pcall(function() return container:getType() end)
    return read and layoutText(kind) or ""
end

local function layoutPickStorageContainer(base, containers, category, used, lockable)
    local best, bestScore = nil, nil
    for _, entry in ipairs(containers or {}) do
        if used[entry] ~= true
            and not layoutContainerAssigned(base, entry.object, entry.containerIndex)
            and layoutContainerEligible(entry, category)
            and (lockable ~= true or layoutLockableContainerKind(entry.kind)) then
            local score = layoutContainerScore(entry.kind, category)
            if best == nil or score > bestScore then
                best, bestScore = entry, score
            end
        end
    end
    return best
end

local function layoutCollectStorage(base, roomName, containers, entries, proposed, used, reachable)
    local categories = layoutStorageCategories(roomName, #(containers or {}), reachable)
    for _, category in ipairs(categories) do
        if proposed[category] ~= true and not layoutStorageAssigned(base, category) then
            local candidate = layoutPickStorageContainer(base, containers, category, used)
            if candidate ~= nil then
                used[candidate] = true
                proposed[category] = true
                entries[#entries + 1] = {
                    category = category,
                    label = LAYOUT_STORAGE_LABELS[category] or category,
                    roomLabel = roomName,
                    object = candidate.object,
                    containerIndex = candidate.containerIndex,
                    kind = candidate.kind,
                }
            end
        end
    end
end

local function layoutCollectFallbackStorage(base, rooms, entries, proposed, used)
    for _, room in ipairs(rooms or {}) do
        for _, category in ipairs({ "weapons", "ammunition" }) do
            if proposed[category] ~= true and not layoutStorageAssigned(base, category) then
                local candidate = layoutPickStorageContainer(
                    base, room.containers, category, used, true)
                if candidate ~= nil then
                    used[candidate] = true
                    proposed[category] = true
                    entries[#entries + 1] = {
                        category = category,
                        label = LAYOUT_STORAGE_LABELS[category] or category,
                        roomLabel = room.roomLabel,
                        object = candidate.object,
                        containerIndex = candidate.containerIndex,
                        kind = candidate.kind,
                    }
                end
            end
        end
    end
end

local function layoutClassifyRoom(name, containers, cookingAppliance)
    local text = layoutText(name)
    if text == "" then return nil end
    for _, word in ipairs(LAYOUT_SKIP_WORDS) do
        if layoutContains(text, word) then return nil end
    end
    for _, rule in ipairs(LAYOUT_ROOM_RULES) do
        if rule.needsContainers ~= true or (tonumber(containers) or 0) > 0 then
            for _, word in ipairs(rule.words) do
                if layoutContains(text, word) then return rule.zoneType, rule.label end
            end
        end
    end
    -- A real stove is a location fact. Power, breakage and ownership stay
    -- with KS_BaseCooking; this only gives an otherwise unknown room a cooking
    -- area instead of treating it as generic storage.
    if cookingAppliance == true then return "cooking", "Kitchen" end
    if (tonumber(containers) or 0) > 0 then return "general", "Store Room" end
    return nil
end

-- One room classifier for the whole mod: the layout proposal and a claimed
-- building's room map must never grow two word lists.
BaseManager.classifyRoom = layoutClassifyRoom

local function layoutHasType(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.type == zoneType then return true end
    end
    return false
end

local function layoutBuildingId(building)
    if building == nil or building.getDef == nil then return nil end
    local ok, definition = pcall(function() return building:getDef() end)
    if not ok or definition == nil or definition.getID == nil then return nil end
    local identified, id = pcall(function() return definition:getID() end)
    return identified and id ~= nil and tostring(id) or nil
end

local function layoutRooms(building)
    if building == nil or building.getRooms == nil then return nil end
    local ok, rooms = pcall(function() return building:getRooms() end)
    if not ok or rooms == nil or rooms.size == nil or rooms.get == nil then return nil end
    return rooms
end

local function layoutSquareCanStand(square)
    if square == nil or square.canStand == nil then return false end
    local ok, value = pcall(function() return square:canStand() end)
    return ok and value == true
end

local function layoutSquareRoom(square)
    if square == nil or square.getRoom == nil then return nil end
    local ok, room = pcall(function() return square:getRoom() end)
    if not ok then return true end
    return room
end

local function layoutIsDoor(object)
    if object == nil then return false end
    if instanceof ~= nil then
        local ok, value = pcall(instanceof, object, "IsoDoor")
        if ok and value == true then return true end
    end
    if type(object.isDoor) == "function" then
        local ok, value = pcall(function() return object:isDoor() end)
        return ok and value == true
    end
    return object.isDoor == true
end

local function layoutObjects(square)
    if square == nil or square.getObjects == nil then return nil end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or objects == nil or objects.size == nil or objects.get == nil then return nil end
    return objects
end

local function layoutCookingAppliance(object)
    if object == nil or instanceof == nil then return false end
    local ok, value = pcall(instanceof, object, "IsoStove")
    return ok and value == true
end

local function layoutRoomHasCookingAppliance(bounds)
    if bounds == nil or getCell == nil then return false end
    local cell = getCell()
    if cell == nil then return false end
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            local square = cell:getGridSquare(x, y, bounds.z)
            local objects = layoutObjects(square)
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    if layoutCookingAppliance(objects:get(index)) then return true end
                end
            end
        end
    end
    return false
end

local function layoutDoorLocked(door)
    if door == nil then return false end
    for _, method in ipairs({ "isLockedByKey", "isLocked" }) do
        if door[method] ~= nil then
            local ok, value = pcall(function() return door[method](door) end)
            if ok and value == true then return true end
        end
    end
    return false
end

local function layoutLeaderHasKey(leader, keyId)
    if leader == nil or keyId == nil or leader.getInventory == nil then
        return false
    end
    local inventoryOk, inventory = pcall(function() return leader:getInventory() end)
    if not inventoryOk or inventory == nil or inventory.haveThisKeyId == nil then
        return false
    end
    local candidates = { keyId }
    local numeric = tonumber(keyId)
    if numeric ~= nil and numeric ~= keyId then candidates[#candidates + 1] = numeric end
    for _, candidate in ipairs(candidates) do
        local readOk, hasKey = pcall(function() return inventory:haveThisKeyId(candidate) end)
        if readOk and hasKey == true then return true end
    end
    return false
end

local function layoutDoorReachable(door, leader)
    if not layoutDoorLocked(door) then return true end
    local keyed = false
    if door ~= nil and door.isLockedByKey ~= nil then
        local ok, value = pcall(function() return door:isLockedByKey() end)
        keyed = ok and value == true
    end
    if not keyed or door.getKeyId == nil then return false end
    local ok, keyId = pcall(function() return door:getKeyId() end)
    if not ok or keyId == nil then return false end
    return layoutLeaderHasKey(leader, keyId)
end

-- Every room a building actually has, with bounds, resolved once. Not every
-- build exposes a room list on the building, and a list whose rooms carry no
-- rectangle is unusable, so the list, the building definition and finally the
-- squares are asked in that order. The layout proposal and the compound's
-- room map both read through here; neither invents a room.
function BaseManager.buildingRooms(building, z)
    if building == nil then return {} end
    local level = tonumber(z) or 0
    local rooms = {}
    local function adopt(room)
        if room == nil or room == true then return nil end
        for _, existing in ipairs(rooms) do
            if existing.room == room then return existing end
        end
        local entry = { room = room }
        rooms[#rooms + 1] = entry
        return entry
    end
    local direct = layoutRooms(building)
    if direct ~= nil then
        for index = 0, direct:size() - 1 do adopt(direct:get(index)) end
    end
    local definition = nil
    if building.getDef ~= nil then
        local ok, found = pcall(function() return building:getDef() end)
        if ok then definition = found end
    end
    if #rooms == 0 and definition ~= nil then
        local fromDef = layoutRooms(definition)
        if fromDef ~= nil then
            for index = 0, fromDef:size() - 1 do adopt(fromDef:get(index)) end
        end
    end
    -- Squares answer both questions at once: which rooms exist, and where.
    local cell = getCell ~= nil and getCell() or nil
    local minX, minY, width, height = nil, nil, nil, nil
    if definition ~= nil then
        local ok = pcall(function()
            minX, minY = tonumber(definition:getX()), tonumber(definition:getY())
            width, height = tonumber(definition:getW()), tonumber(definition:getH())
        end)
        if not ok then minX, minY, width, height = nil, nil, nil, nil end
    end
    if cell ~= nil and minX ~= nil and minY ~= nil
        and width ~= nil and height ~= nil then
        for x = minX, minX + width - 1 do
            for y = minY, minY + height - 1 do
                local room = layoutSquareRoom(cell:getGridSquare(x, y, level))
                if room ~= nil and room ~= true then
                    local entry = adopt(room)
                    local bounds = entry.bounds
                    if bounds == nil then
                        entry.bounds = { x1 = x, y1 = y, x2 = x, y2 = y, z = level }
                    else
                        bounds.x1 = math.min(bounds.x1, x)
                        bounds.y1 = math.min(bounds.y1, y)
                        bounds.x2 = math.max(bounds.x2, x)
                        bounds.y2 = math.max(bounds.y2, y)
                    end
                end
            end
        end
    end
    local result = {}
    for _, entry in ipairs(rooms) do
        local bounds = entry.bounds or layoutRoomBounds(entry.room, level)
        local name = layoutRoomName(entry.room)
        if bounds ~= nil then
            result[#result + 1] = { room = entry.room, name = name, bounds = bounds }
        end
    end
    return result
end
local function layoutRoomReachable(bounds, leader)
    if bounds == nil or getCell == nil then return false end
    local cell = getCell()
    if cell == nil then return false end
    for x = bounds.x1 - 1, bounds.x2 + 1 do
        for y = bounds.y1 - 1, bounds.y2 + 1 do
            local square = cell:getGridSquare(x, y, bounds.z)
            local objects = layoutObjects(square)
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    if layoutIsDoor(object) and layoutDoorReachable(object, leader) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function layoutGuardSquare(base, z)
    local area = base ~= nil and base.home or nil
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil then return nil end
    local minX = tonumber(area.minX)
    local minY = tonumber(area.minY)
    local maxX = tonumber(area.maxX)
        or (minX ~= nil and minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY)
        or (minY ~= nil and minY + math.max(1, tonumber(area.height) or 1) - 1)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return nil end
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = layoutObjects(square)
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    if layoutIsDoor(objects:get(index)) then
                        for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                            local outside = cell:getGridSquare(x + offset[1], y + offset[2], z)
                            if outside ~= nil and layoutSquareCanStand(outside)
                                and layoutSquareRoom(outside) == nil then
                                return outside
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- A player wood lot is anchored on a real loaded tree inside the home
-- yard. It proposes only the two existing work-area types, using the
-- same addZone writer and the same native tree predicate as the
-- woodcutting executor; it does not add a tree, storage or task.
local LAYOUT_OUTDOOR_SIZE = 3
local LAYOUT_OUTDOOR_LABELS = {
    woodcutting = "Wood Lot", log_processing = "Log Yard",
}

local function layoutHomeArea(base, z)
    local home = base ~= nil and (base.territory or base.home) or nil
    if home == nil then return nil end
    local minX = tonumber(home.minX)
    local minY = tonumber(home.minY)
    if minX == nil or minY == nil then return nil end
    local width = tonumber(home.width) or 1
    local height = tonumber(home.height) or 1
    local maxX = tonumber(home.maxX) or (minX + math.max(1, width) - 1)
    local maxY = tonumber(home.maxY) or (minY + math.max(1, height) - 1)
    return {
        minX = minX, minY = minY, maxX = maxX, maxY = maxY,
        z = tonumber(z) or tonumber(home.z) or 0,
    }
end

local function layoutTreeAtSquare(square)
    if square == nil or square.HasTree == nil or square.getTree == nil then
        return false
    end
    local hasOk, hasTree = pcall(function() return square:HasTree() end)
    if not hasOk or hasTree ~= true then return false end
    local treeOk, tree = pcall(function() return square:getTree() end)
    return treeOk and tree ~= nil
end

local function layoutFindWoodTree(area)
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil then return nil end
    for x = area.minX, area.maxX do
        for y = area.minY, area.maxY do
            local square = cell:getGridSquare(x, y, area.z)
            if square ~= nil and layoutSquareRoom(square) == nil
                and layoutTreeAtSquare(square) then
                return square
            end
        end
    end
    return nil
end

local function layoutBoundsOverlap(first, second)
    if first == nil or second == nil then return false end
    if (tonumber(first.z) or 0) ~= (tonumber(second.z) or 0) then return false end
    local ax1 = math.min(tonumber(first.x1) or 0, tonumber(first.x2) or 0)
    local ax2 = math.max(tonumber(first.x1) or 0, tonumber(first.x2) or 0)
    local ay1 = math.min(tonumber(first.y1) or 0, tonumber(first.y2) or 0)
    local ay2 = math.max(tonumber(first.y1) or 0, tonumber(first.y2) or 0)
    local bx1 = math.min(tonumber(second.x1) or 0, tonumber(second.x2) or 0)
    local bx2 = math.max(tonumber(second.x1) or 0, tonumber(second.x2) or 0)
    local by1 = math.min(tonumber(second.y1) or 0, tonumber(second.y2) or 0)
    local by2 = math.max(tonumber(second.y1) or 0, tonumber(second.y2) or 0)
    return ax1 <= bx2 and bx1 <= ax2 and ay1 <= by2 and by1 <= ay2
end

local function layoutOutdoorOverlaps(bounds, base, entries)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false
            and layoutBoundsOverlap(bounds, zone) then
            return true
        end
    end
    for _, entry in ipairs(entries or {}) do
        if entry ~= nil and entry.bounds ~= nil
            and layoutBoundsOverlap(bounds, entry.bounds) then
            return true
        end
    end
    return false
end

local function layoutOutdoorBox(x, y, area)
    local size = LAYOUT_OUTDOOR_SIZE
    if area == nil or area.maxX - area.minX + 1 < size
        or area.maxY - area.minY + 1 < size then
        return nil
    end
    local half = math.floor(size / 2)
    local x1 = math.max(area.minX, math.min(x - half, area.maxX - size + 1))
    local y1 = math.max(area.minY, math.min(y - half, area.maxY - size + 1))
    return { x1 = x1, y1 = y1, x2 = x1 + size - 1, y2 = y1 + size - 1, z = area.z }
end

local function layoutAdjacentBox(box, area)
    local size = LAYOUT_OUTDOOR_SIZE
    local candidates = {
        { x1 = box.x2 + 1, y1 = box.y1, x2 = box.x2 + size, y2 = box.y2 },
        { x1 = box.x1 - size, y1 = box.y1, x2 = box.x1 - 1, y2 = box.y2 },
        { x1 = box.x1, y1 = box.y2 + 1, x2 = box.x2, y2 = box.y2 + size },
        { x1 = box.x1, y1 = box.y1 - size, x2 = box.x2, y2 = box.y1 - 1 },
    }
    for _, candidate in ipairs(candidates) do
        if candidate.x1 >= area.minX and candidate.y1 >= area.minY
            and candidate.x2 <= area.maxX and candidate.y2 <= area.maxY then
            candidate.z = area.z
            return candidate
        end
    end
    return nil
end

local function layoutOutdoorEntries(base, z)
    local missingWood = not layoutHasType(base, "woodcutting")
    local missingLogs = not layoutHasType(base, "log_processing")
    if not missingWood and not missingLogs then return {} end
    local area = layoutHomeArea(base, z)
    if area == nil then return {} end
    local tree = layoutFindWoodTree(area)
    if tree == nil then return {} end
    local wood = layoutOutdoorBox(tree:getX(), tree:getY(), area)
    if wood == nil then return {} end
    local woodClear = not layoutOutdoorOverlaps(wood, base, nil)
    if missingWood and not woodClear then return {} end
    local entries = {}
    if missingWood then
        entries[#entries + 1] = {
            zoneType = "woodcutting", label = LAYOUT_OUTDOOR_LABELS.woodcutting,
            bounds = wood,
        }
    end
    if missingLogs then
        local logs = layoutAdjacentBox(wood, area)
        if logs ~= nil and not layoutOutdoorOverlaps(logs, base, entries) then
            entries[#entries + 1] = {
                zoneType = "log_processing", label = LAYOUT_OUTDOOR_LABELS.log_processing,
                bounds = logs,
            }
        end
    end
    return entries
end

function BaseManager.proposeLayout(baseId, building, z, leader)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return {}, "base_missing" end
    if base.ownerKind ~= "player" then return {}, "not_player_base" end
    if leader == nil and type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok then leader = player end
    end
    local buildingId = layoutBuildingId(building)
    if buildingId == nil then return {}, "no_building" end
    local homeId = base.home ~= nil and base.home.buildingId or nil
    -- A base claimed without a building has no home id to compare against;
    -- the building the player is standing in is then the one proposed.
    if homeId ~= nil and tostring(homeId) ~= buildingId then
        return {}, "not_home_building"
    end
    z = tonumber(z) or tonumber(base.home.z) or 0
    local rooms = BaseManager.buildingRooms(building, z)
    if #rooms == 0 then return {}, "no_rooms" end
    local best = {}
    local storageEntries, proposedStorage, usedStorage = {}, {}, {}
    local fallbackRooms = {}
    for _, found in ipairs(rooms) do
        local room, bounds = found.room, found.bounds
        if bounds ~= nil and (tonumber(bounds.z) or z) == z then
            local roomName = found.name ~= "" and found.name or layoutRoomName(room)
            local containers = layoutContainers(bounds)
            local containerCount = #containers
            local reachable = layoutRoomReachable(bounds, leader)
            local cookingAppliance = layoutRoomHasCookingAppliance(bounds)
            local zoneType, label = layoutClassifyRoom(roomName, containerCount, cookingAppliance)
            if zoneType ~= nil and not layoutHasType(base, zoneType) then
                local area = (bounds.x2 - bounds.x1 + 1) * (bounds.y2 - bounds.y1 + 1)
                local current = best[zoneType]
                if current == nil or area > current.area
                    or (area == current.area and containerCount > current.containers) then
                    best[zoneType] = {
                        zoneType = zoneType, label = label, bounds = bounds,
                        area = area, containers = containerCount,
                    }
                end
            end
            layoutCollectStorage(base, roomName, containers, storageEntries,
                proposedStorage, usedStorage, reachable)
            if reachable == true and layoutIsStorageRoom(roomName) then
                fallbackRooms[#fallbackRooms + 1] = {
                    roomLabel = roomName, containers = containers,
                }
            end
        end
    end
    layoutCollectFallbackStorage(base, fallbackRooms, storageEntries,
        proposedStorage, usedStorage)
    for _, entry in ipairs(layoutOutdoorEntries(base, z)) do
        best[entry.zoneType] = entry
    end
    local entries = {}
    for _, entry in pairs(best) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b)
        return (LAYOUT_ORDER[a.zoneType] or 99) < (LAYOUT_ORDER[b.zoneType] or 99)
    end)
    if not layoutHasType(base, "guard") then
        local guard = layoutGuardSquare(base, z)
        if guard ~= nil then
            local guardBounds = { x1 = guard:getX(), y1 = guard:getY(),
                x2 = guard:getX(), y2 = guard:getY(), z = guard:getZ() }
            if not layoutOutdoorOverlaps(guardBounds, nil, entries) then
                entries[#entries + 1] = {
                    zoneType = "guard", label = "Entry Watch",
                    bounds = guardBounds,
                }
            end
        end
    end
    table.sort(storageEntries, function(a, b)
        local orderA = LAYOUT_STORAGE_ORDER[a.category] or 99
        local orderB = LAYOUT_STORAGE_ORDER[b.category] or 99
        if orderA ~= orderB then return orderA < orderB end
        return tostring(a.roomLabel) < tostring(b.roomLabel)
    end)
    entries.storage = storageEntries
    if #entries == 0 and #storageEntries == 0 then return {}, "no_new_rooms" end
    return entries, "proposed"
end

local function layoutWeaponsCategoryReachable(object, containerIndex, category, leader)
    local square = layoutObjectSquare(object)
    if square == nil then return false end
    local room = layoutSquareRoom(square)
    if room == nil or room == true then return false end
    local bounds = layoutRoomBounds(room, square:getZ())
    if bounds == nil then return false end
    local roomName = layoutRoomName(room)
    if layoutIsSecureRoomName(roomName) then
        local categories = layoutStorageCategories(roomName, 1,
            layoutRoomReachable(bounds, leader))
        for _, allowed in ipairs(categories) do
            if allowed == category then return true end
        end
        return false
    end
    if not layoutIsStorageRoom(roomName) then return false end
    if not layoutRoomReachable(bounds, leader) then return false end
    return layoutLockableContainerKind(layoutContainerKind(object, containerIndex))
end

local function layoutWeaponsUnreachableReason(object)
    local square = layoutObjectSquare(object)
    local room = layoutSquareRoom(square)
    if room ~= nil and room ~= true
        and layoutIsSecureRoomName(layoutRoomName(room)) then
        return "secure_room_unreachable"
    end
    return "storage_room_unreachable"
end

function BaseManager.applyLayout(baseId, entries, playerId, leader)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return nil, "base_missing" end
    if base.ownerKind ~= "player" then return nil, "not_player_base" end
    if playerId == nil or tostring(base.ownerId) ~= tostring(playerId) then
        return nil, "not_your_base"
    end
    if leader == nil and type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok then leader = player end
    end
    if type(entries) ~= "table" then return nil, "no_entries" end
    local storageEntries = type(entries.storage) == "table" and entries.storage or {}
    if #entries == 0 and #storageEntries == 0 then return nil, "no_entries" end
    local added, skipped = 0, {}
    for _, entry in ipairs(entries) do
        local zoneType = type(entry) == "table" and entry.zoneType or nil
        local bounds = type(entry) == "table" and entry.bounds or nil
        if type(zoneType) ~= "string" or type(bounds) ~= "table" then
            skipped[#skipped + 1] = { zoneType = tostring(zoneType or "?"), reason = "invalid_entry" }
        elseif layoutHasType(base, zoneType) then
            skipped[#skipped + 1] = { zoneType = zoneType, reason = "existing" }
        else
            local zone, reason = BaseManager.addZone(baseId, zoneType, bounds, entry.label)
            if zone ~= nil then
                added = added + 1
            else
                skipped[#skipped + 1] = { zoneType = zoneType, reason = reason or "refused" }
            end
        end
    end
    local assigned, storageSkipped = 0, {}
    for _, entry in ipairs(storageEntries) do
        local category = type(entry) == "table" and entry.category or nil
        local object = type(entry) == "table" and entry.object or nil
        local containerIndex = type(entry) == "table" and tonumber(entry.containerIndex) or nil
        if type(category) ~= "string" or object == nil or containerIndex == nil then
            storageSkipped[#storageSkipped + 1] = {
                category = tostring(category or "?"), reason = "invalid_storage_entry",
            }
        elseif layoutStorageAssigned(base, category) then
            storageSkipped[#storageSkipped + 1] = {
                category = category, reason = "existing_storage",
            }
        elseif layoutContainerAssigned(base, object, containerIndex) then
            storageSkipped[#storageSkipped + 1] = {
                category = category, reason = "existing_storage",
            }
        elseif (category == "weapons" or category == "ammunition")
            and not layoutWeaponsCategoryReachable(object, containerIndex, category, leader) then
            storageSkipped[#storageSkipped + 1] = {
                category = category, reason = layoutWeaponsUnreachableReason(object),
            }
        else
            local policy, reason = BaseManager.setStoragePolicy(
                baseId, object, category, containerIndex)
            if policy ~= nil then
                assigned = assigned + 1
            else
                storageSkipped[#storageSkipped + 1] = {
                    category = category, reason = reason or "storage_refused",
                }
            end
        end
    end
    return {
        added = added, skipped = skipped,
        assigned = assigned, storageSkipped = storageSkipped,
        total = #entries + #storageEntries,
        zoneTotal = #entries, storageTotal = #storageEntries,
    }
end

-- END BASE LAYOUT PROPOSAL

-- BASE RADIO ARRIVAL (pure)
-- D7.3: a broadcast is a call for help, and help is a real person on the road
-- the county already walks. The chance comes from the operator's Electrical
-- level, the interval is one world day, and the answer is decided by a roll
-- handed in by the caller so the rule is checkable without a save. Nothing
-- here stores anything: the base's radio record owns the last call and the
-- world population owner already owns who arrives.
local RADIO_ARRIVAL_INTERVAL_HOURS = 24

-- The strongest living resident answers, exactly as the context menu decides
-- it. No levels means no operator, and no operator means no chance.
function BaseManager.radioOperatorLevel(levels)
    local best = nil
    if type(levels) ~= "table" then return nil end
    for _, level in ipairs(levels) do
        local value = tonumber(level)
        if value ~= nil and value == value and (best == nil or value > best) then
            best = value
        end
    end
    return best
end

function BaseManager.radioArrivalChance(operatorLevel)
    local level = tonumber(operatorLevel)
    if level == nil or level ~= level or level <= 0 then return 0 end
    local steps = math.floor(level)
    if steps < 1 then steps = 1 end
    if steps > 6 then steps = 6 end
    -- Whole percent, not accumulated tenths: 0.10 + 0.05 is 0.15000000000000002 in binary floating point, and odds that drift by a bit are odds nobody can state.
    return (10 + 5 * steps) / 100
end

function BaseManager.radioArrivalDue(mode, lastCallHours, nowHours)
    if mode ~= "broadcast" then return false, "not_broadcasting" end
    local now = tonumber(nowHours)
    if now == nil then return false, "no_clock" end
    local last = tonumber(lastCallHours)
    if last ~= nil and now - last < RADIO_ARRIVAL_INTERVAL_HOURS then
        return false, "recent"
    end
    return true
end

function BaseManager.radioArrivalRoll(roll, chance)
    local r = tonumber(roll)
    local c = tonumber(chance)
    if r == nil or c == nil or r ~= r or c ~= c or r < 0 or r >= 1 then
        return false, "invalid_roll"
    end
    if c <= 0 then return false, "no_operator" end
    if r < c then return true, "answered" end
    return false, "quiet"
end

function BaseManager.radioArrivalPlan(mode, operatorLevel, lastCallHours, nowHours, roll)
    local due, reason = BaseManager.radioArrivalDue(mode, lastCallHours, nowHours)
    if not due then return false, reason end
    local chance = BaseManager.radioArrivalChance(operatorLevel)
    local answered, why = BaseManager.radioArrivalRoll(roll, chance)
    if not answered then return false, why end
    return true, "answered", chance
end

function BaseManager.radioRiskChance(operatorLevel)
    -- A short, practised call is harder to find. Whole percent for the same
    -- reason the arrival odds are: a chance of 0.30000000000000004 is not a
    -- chance anyone can put on a tooltip.
    local level = tonumber(operatorLevel)
    local steps = 0
    if level ~= nil and level == level and level > 0 then
        steps = math.floor(level)
        if steps > 6 then steps = 6 end
    end
    return (30 - 4 * steps) / 100
end

function BaseManager.radioRiskDue(lastRiskHours, nowHours)
    local now = tonumber(nowHours)
    if now == nil then return false end
    local last = tonumber(lastRiskHours)
    if last ~= nil and now - last < RADIO_ARRIVAL_INTERVAL_HOURS then
        return false
    end
    return true
end

function BaseManager.radioRiskRoll(roll, chance)
    return BaseManager.radioArrivalRoll(roll, chance)
end

-- Said before the switch, not after the raid. Plain about the fact and never
-- promising that a good operator is safe.
function BaseManager.radioRiskText(operatorLevel)
    local level = tonumber(operatorLevel)
    if level ~= nil and level > 0 then
        return "A practised hand keeps the call short. Someone unfriendly can still hear it."
    end
    return "Nobody here can run this set well. A long call can carry to unfriendly people."
end

-- END BASE RADIO ARRIVAL

local function onGameStart()
    BaseManager.ensureFactionBases()
    BaseManager.ensurePlayerBases()
    BaseManager.syncStructureProtection()
end

Events.OnGameStart.Add(onGameStart)

return BaseManager
