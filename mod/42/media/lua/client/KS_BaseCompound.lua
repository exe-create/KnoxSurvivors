local KS_SafeCall = require "KS_SafeCall"
-- One base can be several buildings. A house, a garage across the street and a
-- barn beyond the fence are the same home; the boundary drawn around the first
-- building was never a second concept of ownership, only its first outline.
--
-- The record lives where every other base fact lives: `base.establishments` on
-- the persisted base. This module owns three decisions that had no owner:
-- which buildings may be one base, what each building is called, and what each
-- room in it is called. It never moves a survivor, assigns work or writes a
-- storage policy; it only says what the ground is.
require "KS_Persistence"

local Compound = rawget(_G, "KnoxBaseCompound") or {}
_G.KnoxBaseCompound = Compound

-- A building further than this from every other building of the base is a
-- separate place, not part of a walkable home. Forty tiles crosses a street,
-- a yard and a barn track; it does not cross a town. Keeping the limit here
-- means a claim is refused before anything is written, and the survivors never
-- inherit a home they cannot walk between.
Compound.MAX_GAP = 40

-- AREA MATHS (pure)
-- Bounds may be a home area (minX/minY/width/height) or a territory
-- (minX/minY/maxX/maxY); both are read without a world.
function Compound.maxX(area)
    if type(area) ~= "table" then return nil end
    if area.maxX ~= nil then return tonumber(area.maxX) end
    if area.minX ~= nil and area.width ~= nil then
        return tonumber(area.minX) + tonumber(area.width) - 1
    end
    return nil
end

function Compound.maxY(area)
    if type(area) ~= "table" then return nil end
    if area.maxY ~= nil then return tonumber(area.maxY) end
    if area.minY ~= nil and area.height ~= nil then
        return tonumber(area.minY) + tonumber(area.height) - 1
    end
    return nil
end

function Compound.contains(area, x, y)
    if type(area) ~= "table" then return false end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local limitX, limitY = Compound.maxX(area), Compound.maxY(area)
    if minX == nil or minY == nil or limitX == nil or limitY == nil then return false end
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return false end
    return x >= minX and x <= limitX and y >= minY and y <= limitY
end

-- The gap is measured between rectangles, not between doors: two buildings
-- that share a wall are zero tiles apart, and a barn twenty tiles up the track
-- is twenty. Diagonal counts once, so a house behind a garage across the road
-- is not refused for being far in a straight line.
-- Two outlines intersect when both axes overlap. Corner containment is not
-- enough: a long barn overlapping the edge of the house shares tiles without
-- holding either corner.
function Compound.overlaps(first, second)
    local aX1, aY1 = tonumber(first ~= nil and first.minX), tonumber(first ~= nil and first.minY)
    local bX1, bY1 = tonumber(second ~= nil and second.minX), tonumber(second ~= nil and second.minY)
    local aX2, aY2 = Compound.maxX(first), Compound.maxY(first)
    local bX2, bY2 = Compound.maxX(second), Compound.maxY(second)
    if aX1 == nil or aY1 == nil or aX2 == nil or aY2 == nil then return false end
    if bX1 == nil or bY1 == nil or bX2 == nil or bY2 == nil then return false end
    return aX1 <= bX2 and bX1 <= aX2 and aY1 <= bY2 and bY1 <= aY2
end

function Compound.gapBetween(first, second)
    local aX1, aY1 = tonumber(first ~= nil and first.minX), tonumber(first ~= nil and first.minY)
    local bX1, bY1 = tonumber(second ~= nil and second.minX), tonumber(second ~= nil and second.minY)
    local aX2, aY2 = Compound.maxX(first), Compound.maxY(first)
    local bX2, bY2 = Compound.maxX(second), Compound.maxY(second)
    if aX1 == nil or aY1 == nil or bX1 == nil or bY1 == nil then return nil end
    if aX2 == nil or aY2 == nil or bX2 == nil or bY2 == nil then return nil end
    local gapX = math.max(0, bX1 - aX2, aX1 - bX2)
    local gapY = math.max(0, bY1 - aY2, aY1 - bY2)
    return math.max(gapX, gapY)
end

-- CLAIM RULES (pure)
-- `established` is the current list of { name =, area =, buildingId = } entries
-- and `candidate` is the building the player is standing in. The first refusal
-- wins and names a different fact each time, so the menu can say why instead of
-- failing silently.
function Compound.claimRefusal(established, candidate, maxGap)
    if type(candidate) ~= "table" or type(candidate.area) ~= "table" then
        return "no_building"
    end
    local limit = tonumber(maxGap) or Compound.MAX_GAP
    local nearest, nearestGap = nil, nil
    for _, entry in ipairs(established or {}) do
        local area = type(entry) == "table" and entry.area or nil
        if area ~= nil then
            if candidate.buildingId ~= nil and entry.buildingId == candidate.buildingId then
                return "already_in_base"
            end
            if Compound.overlaps(area, candidate.area) then
                return "overlaps_establishment"
            end
            local gap = Compound.gapBetween(area, candidate.area)
            if gap ~= nil then
                if nearestGap == nil or gap < nearestGap then
                    nearest, nearestGap = entry, gap
                end
            end
        end
    end
    if nearest == nil then return nil end
    if nearestGap > limit then return "too_far", nearestGap, nearest end
    return nil, nearestGap, nearest
end

-- ROOM LABELS (pure)
-- Native room names repeat ("bedroom" three times in one house), so a numbered
-- label is what makes a room addressable: Bedroom 1, Bedroom 2, Kitchen. The
-- classifier decides the kind; this only makes the label unique and readable.
function Compound.numberRooms(rooms)
    local counters, result = {}, {}
    for _, room in ipairs(rooms or {}) do
        if type(room) == "table" then
            local base = tostring(room.label ~= nil and room.label ~= "" and room.label
                or room.native or "Room")
            local count = (counters[base] or 0) + 1
            counters[base] = count
            local copy = {}
            for key, value in pairs(room) do copy[key] = value end
            copy.name = base .. " " .. tostring(count)
            result[#result + 1] = copy
        end
    end
    return result
end

-- RECORD (base.establishments)
function Compound.list(base)
    if type(base) ~= "table" then return {} end
    if type(base.establishments) ~= "table" then base.establishments = {} end
    return base.establishments
end

-- Older saves hold a single `home` area and no establishment list. Backfilling
-- from that area is not a migration step the player must run: the house they
-- already own becomes Building 1 the first time anything asks.
function Compound.ensure(base, worldAgeHours)
    if type(base) ~= "table" then return {} end
    local list = Compound.list(base)
    if #list == 0 and type(base.home) == "table" and base.home.minX ~= nil then
        base.nextEstablishmentId = tonumber(base.nextEstablishmentId) or 2
        list[1] = {
            id = tostring(base.id) .. "-building-1",
            name = "Building 1",
            buildingId = base.home.buildingId,
            area = {
                minX = tonumber(base.home.minX), minY = tonumber(base.home.minY),
                width = tonumber(base.home.width), height = tonumber(base.home.height),
                z = tonumber(base.home.z) or 0,
            },
            claimedAtHours = tonumber(base.claimedAtHours) or tonumber(worldAgeHours) or 0,
            rooms = {},
        }
    end
    for index, entry in ipairs(list) do
        if type(entry) == "table" then
            entry.name = entry.name or ("Building " .. tostring(index))
            entry.rooms = type(entry.rooms) == "table" and entry.rooms or {}
        end
    end
    return list
end

function Compound.establishmentFor(base, buildingId)
    if buildingId == nil then return nil end
    for _, entry in ipairs(Compound.ensure(base)) do
        if entry ~= nil and entry.buildingId ~= nil
            and tostring(entry.buildingId) == tostring(buildingId) then
            return entry
        end
    end
    return nil
end

function Compound.roomAt(base, square)
    if square == nil then return nil, nil end
    local x, y, z = square:getX(), square:getY(), square:getZ() or 0
    for _, entry in ipairs(Compound.ensure(base)) do
        if Compound.contains(entry.area, x, y) and (tonumber(entry.area.z) or 0) == z then
            for _, room in ipairs(entry.rooms or {}) do
                if Compound.contains(room.bounds, x, y)
                    and (tonumber(room.bounds.z) or 0) == z then
                    return entry, room
                end
            end
            return entry, nil
        end
    end
    return nil, nil
end

-- ROOM DETECTION (world read)
-- Native rooms are the truth about walls; the existing classifier in
-- KS_BaseManager turns a native name into a kind. Nothing here invents a room
-- that the building definition does not already report.
local function safeCall(object, method)
    local value = KS_SafeCall.invoke(object, method)
    return value
end

function Compound.detectRooms(building, z)
    local level = tonumber(z) or 0
    local manager = rawget(_G, "KnoxBaseManager")
    local found = manager ~= nil and manager.buildingRooms ~= nil
        and manager.buildingRooms(building, level) or {}
    local entries = {}
    for _, room in ipairs(found) do
        local native = type(room.name) == "string"
            and string.lower(room.name):gsub("%s+", " ") or nil
        local bounds = room.bounds
        if native ~= nil and native ~= "" and bounds ~= nil then
            local kind, label = nil, nil
            if manager ~= nil and manager.classifyRoom ~= nil then
                -- Contents decide a bathroom or a living room when the building
                -- data has the name wrong or missing.
                local fixtures = manager.roomFixtures ~= nil
                    and manager.roomFixtures(bounds) or nil
                kind, label = manager.classifyRoom(native, 0, false, fixtures)
                if type(fixtures) == "table" and fixtures.bathroom == true then
                    label = "Bathroom"
                elseif label == nil and type(fixtures) == "table"
                    and fixtures.living == true and fixtures.bed ~= true then
                    label = "Living Room"
                end
            end
            local minX, minY = tonumber(bounds.x1), tonumber(bounds.y1)
            local width = (tonumber(bounds.x2) or 0) - (minX or 0) + 1
            local height = (tonumber(bounds.y2) or 0) - (minY or 0) + 1
            entries[#entries + 1] = {
                key = "room-" .. tostring(minX) .. "-" .. tostring(minY)
                    .. "-" .. tostring(level),
                native = native,
                kind = kind,
                label = label or (native:sub(1, 1):upper() .. native:sub(2)),
                bounds = { minX = minX, minY = minY, width = width,
                    height = height, z = level },
            }
        end
    end
    return Compound.numberRooms(entries)
end


-- Fill a building's room map from the world. Re-runs are safe: a name the
-- player set is kept, and only auto labels are rewritten.
function Compound.refreshRooms(base, establishment, building, z)
    if establishment == nil or building == nil then return {} end
    local detected = Compound.detectRooms(building, z)
    local previous = {}
    for _, room in ipairs(establishment.rooms or {}) do previous[room.key] = room end
    for _, room in ipairs(detected) do
        local old = previous[room.key]
        if old ~= nil and old.custom == true and type(old.name) == "string" then
            room.name = old.name
            room.custom = true
        end
    end
    establishment.rooms = detected
    return detected
end

-- The candidate a menu offers for the square under the cursor. Reading the
-- building definition is the only world access; the rules above stay pure.
function Compound.candidateFor(square)
    local building = safeCall(square, "getBuilding")
    local definition = safeCall(building, "getDef")
    if definition == nil then return nil end
    local minX, minY = safeCall(definition, "getX"), safeCall(definition, "getY")
    local width, height = safeCall(definition, "getW"), safeCall(definition, "getH")
    if minX == nil or minY == nil or width == nil or height == nil then return nil end
    local id = safeCall(definition, "getID")
    return {
        buildingId = id ~= nil and tostring(id) or nil,
        area = {
            minX = tonumber(minX), minY = tonumber(minY),
            width = tonumber(width), height = tonumber(height),
            z = tonumber(square:getZ()) or 0,
        },
    }
end

-- Detect the rooms of the establishment a square belongs to. A base
-- backfilled from its old home has an establishment but no room map yet,
-- so the first lookup in that building fills it instead of reporting that
-- a house the player has owned for weeks has no rooms.
function Compound.refreshAt(base, x, y, z)
    local cell = getCell ~= nil and getCell() or nil
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if cell == nil or x == nil or y == nil then return nil end
    local square = cell:getGridSquare(x, y, z)
    local building = safeCall(square, "getBuilding")
    if building == nil then return nil end
    local definition = safeCall(building, "getDef")
    local buildingId = definition ~= nil and safeCall(definition, "getID") or nil
    local entry = Compound.establishmentFor(base, buildingId)
    if entry == nil then return nil end
    return Compound.refreshRooms(base, entry, building, z)
end
function Compound.claim(base, building, square, worldAgeHours)
    if type(base) ~= "table" or building == nil or square == nil then
        return nil, "invalid_location"
    end
    local definition = safeCall(building, "getDef")
    if definition == nil then return nil, "no_building" end
    local minX, minY = safeCall(definition, "getX"), safeCall(definition, "getY")
    local width, height = safeCall(definition, "getW"), safeCall(definition, "getH")
    if minX == nil or minY == nil or width == nil or height == nil then
        return nil, "no_building"
    end
    local buildingId = safeCall(definition, "getID")
    local list = Compound.ensure(base, worldAgeHours)
    local candidate = {
        buildingId = buildingId ~= nil and tostring(buildingId) or nil,
        area = {
            minX = tonumber(minX), minY = tonumber(minY),
            width = tonumber(width), height = tonumber(height),
            z = tonumber(square:getZ()) or 0,
        },
    }
    local reason, gap = Compound.claimRefusal(list, candidate)
    if reason ~= nil then return nil, reason, gap end
    local index = tonumber(base.nextEstablishmentId) or (#list + 1)
    base.nextEstablishmentId = index + 1
    local establishment = {
        id = tostring(base.id) .. "-building-" .. tostring(index),
        name = "Building " .. tostring(#list + 1),
        buildingId = candidate.buildingId,
        area = candidate.area,
        claimedAtHours = tonumber(worldAgeHours) or 0,
        rooms = {},
    }
    Compound.refreshRooms(base, establishment, building, candidate.area.z)
    list[#list + 1] = establishment
    return establishment
end

-- A room by coordinate, for owners that hold a square's numbers rather than
-- the square itself: storage policies and the bed roster both keep x/y/z.
function Compound.roomNameAt(base, x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if x == nil or y == nil then return nil end
    for _, entry in ipairs(Compound.ensure(base)) do
        local area = entry.area
        if area ~= nil and Compound.contains(area, x, y)
            and (tonumber(area.z) or 0) == z then
            for _, room in ipairs(entry.rooms or {}) do
                if room.bounds ~= nil and Compound.contains(room.bounds, x, y)
                    and (tonumber(room.bounds.z) or 0) == z then
                    return room.name, room, entry
                end
            end
            return nil, nil, entry
        end
    end
    return nil
end

-- What a storage policy may record about where it lives. Coordinates stay on
-- the record because the game loads by square; the room is how a person reads
-- it back, and the key survives a room rename.
function Compound.roomIdentity(base, x, y, z)
    local name, room, entry = Compound.roomNameAt(base, x, y, z)
    if entry ~= nil and room == nil and Compound.refreshAt ~= nil then
        -- A building claimed before room detection existed fills its map on
        -- first use, so a policy still records a room rather than nothing.
        if Compound.refreshAt(base, x, y, z) ~= nil then
            name, room = Compound.roomNameAt(base, x, y, z)
        end
    end
    local name, room, entry = Compound.roomNameAt(base, x, y, z)
    if entry == nil then return nil end
    if room == nil then
        return { establishmentId = entry.id, roomKey = nil, roomLabel = entry.name }
    end
    return { establishmentId = entry.id, roomKey = room.key, roomLabel = name }
end
-- The names a player can set from the room they stand in. A free-text box is
-- a second input surface for a two-word answer; a short list keeps the label
-- consistent with what the classifier would have produced, and the record
-- still marks the choice custom so no refresh overwrites it.
Compound.ROOM_PRESETS = {
    "Bedroom", "Guest Room", "Kids Room", "Living Room", "Kitchen",
    "Bathroom", "Garage", "Store Room", "Workshop", "Office",
}

function Compound.renameRoomAt(base, x, y, z, name)
    local _, room, entry = Compound.roomNameAt(base, x, y, z)
    if entry ~= nil and room == nil and Compound.refreshAt ~= nil then
        Compound.refreshAt(base, x, y, z)
        _, room = Compound.roomNameAt(base, x, y, z)
    end
    local _, room, entry = Compound.roomNameAt(base, x, y, z)
    if entry == nil then return false, "unknown_establishment" end
    if room == nil then return false, "unknown_room" end
    return Compound.renameRoom(base, entry.id, room.key, name)
end
function Compound.renameRoom(base, establishmentId, roomKey, name)
    for _, entry in ipairs(Compound.ensure(base)) do
        if entry.id == establishmentId then
            for _, room in ipairs(entry.rooms or {}) do
                if room.key == roomKey then
                    local text = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if text == "" then return false, "empty_name" end
                    room.name = text
                    room.custom = true
                    -- Containers store the label they were assigned with.
                    -- The rename owns that word, so refresh them in the same
                    -- write rather than leaving an old name on a shelf in a
                    -- room the player has just renamed.
                    for _, policy in pairs(type(base.storage) == "table" and base.storage or {}) do
                        if type(policy) == "table" and policy.roomKey == room.key
                            and policy.establishmentId == entry.id then
                            policy.roomLabel = text
                        end
                    end
                    return true
                end
            end
            return false, "unknown_room"
        end
    end
    return false, "unknown_establishment"
end

-- What the player is told. One sentence per refusal so the menu never lies
-- about why a building could not be added.
Compound.REFUSALS = {
    no_building = "Stand inside a building to add it to the base.",
    already_in_base = "This building is already part of the base.",
    overlaps_establishment = "This building shares its outline with one already in the base.",
    invalid_location = "That building could not be read.",
}

function Compound.refusalText(reason, gap)
    if reason == "too_far" then
        return "Too far from the rest of the base" .. (gap ~= nil and (" (" .. tostring(gap) .. " tiles)") or "")
            .. ". Establish an outpost instead."
    end
    return Compound.REFUSALS[tostring(reason)] or "That building cannot join this base."
end

return Compound
