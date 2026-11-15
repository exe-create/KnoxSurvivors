-- BED CLAIM AFTER A MOVEABLES PICKUP
-- The installed moveables pickup removes the bed itself and never touches a
-- claim: ISMoveableSpriteProps:pickUpMoveable -> pickUpMoveableInternal has no
-- bed, occupant or claim handling anywhere in the file. Nothing in this
-- codebase queues an NPC pickup (only "place" and repair are queued), so the
-- consequence is judged where it lands today - the existing bed-claim reader:
-- a stored claim names a bed only while that bed still exists.
local P = assert(KnoxPersistence)
local factory = assert(bedShortageFactory)
local now = 10
local ensure = factory(function() return now end)

local oldData, oldCell, oldRuntime = data, getCell, KnoxSurvivorRuntime
local oldFeed, oldAdjacent = KnoxActivityFeed, AdjacentFreeTileFinder
data = {}
local ids = { "bed-pickup-a", "bed-pickup-b" }
for _, id in ipairs(ids) do assert(P.setRecord(id, expectedRecord)) end
local root = data.KnoxSurvivors_IsoPlayer
local faction = { id = "bed-pickup-faction", name = "Pickup House", kind = "npc",
    leaderId = ids[1], memberIds = ids }
root.factions[faction.id] = faction
local base = { id = "bed-pickup-base", ownerKind = "faction", ownerId = faction.id,
    home = { buildingId = "bed-pickup-house", minX = 0, minY = 0, width = 3, height = 1, z = 0 } }
root.bases[base.id] = base
local function resident(id)
    root.survivors[id].affiliation = { kind = "faction", factionId = faction.id }
    root.survivors[id].duty = { mode = "base", baseId = base.id }
end
for _, id in ipairs(ids) do resident(id) end

-- World: one loaded ground-floor row of three tiles inside the base building.
local tiles = {}
local function tile(x, y)
    tiles[x] = tiles[x] or {}
    tiles[x][y] = { loaded = true, objects = {} }
end
local function bed(index)
    return { getObjectIndex = function() return index end,
        getProperties = function() return { get = function(_, key)
            return key == "BedType" and "goodBed" or nil end } end,
        isFurnitureOccupied = function() return false end }
end
local definition = { getID = function() return "bed-pickup-house" end }
local building = { getDef = function() return definition end }
local function squareAt(x, y)
    local entry = tiles[x] and tiles[x][y]
    if entry == nil or entry.loaded == false then return nil end
    local objects = entry.objects
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end,
        getBuilding = function() return building end,
        getObjects = function() return { size = function() return #objects end,
            get = function(_, i) return objects[i + 1] end } end }
end
getCell = function() return { getGridSquare = function(_, x, y, z)
    if z ~= 0 then return nil end
    return squareAt(x, y)
end } end
AdjacentFreeTileFinder = { Find = function(square) return square end }
KnoxSurvivorRuntime = { getCharacter = function(id) return { id = id } end }
local notices = {}
KnoxActivityFeed = { event = function(text) notices[#notices + 1] = text end }

for x = 0, 2 do tile(x, 0) end
tiles[0][0].objects = { bed(0) }   -- the donor's bed
tiles[1][0].objects = { bed(0) }   -- the neighbour's bed
tiles[2][0].objects = { bed(0) }   -- a free bed in the same building
assert(P.setFactionResidentBed(ids[1], faction.id, base.id,
    { x = 0, y = 0, z = 0, objectIndex = 0 }, now))
assert(P.setFactionResidentBed(ids[2], faction.id, base.id,
    { x = 1, y = 0, z = 0, objectIndex = 0 }, now))

local writes = 0
local realSet = P.setFactionResidentBed
P.setFactionResidentBed = function(...) writes = writes + 1 return realSet(...) end

-- 1. A bed that still exists keeps its owner: the reader invents no claim and
--    moves nobody.
assert(ensure(base, faction) == 0 and writes == 0,
    "a resident's live claimed bed is honoured without a second claim")
assert(P.getSurvivorPolicies(ids[1]).assignedBed.x == 0
    and P.getSurvivorPolicies(ids[2]).assignedBed.x == 1,
    "each resident keeps the only claim on their own bed")

-- 2. The pickup removes the bed and touches no claim. The resident must become
--    assignable again instead of holding a phantom bed forever.
now = 11
tiles[0][0].objects = {}
local assignedCount = ensure(base, faction)
assert(assignedCount == 1 and writes == 1,
    "a resident whose claimed bed was picked up is assigned again through the existing claim writer")
local donor = P.getSurvivorPolicies(ids[1]).assignedBed
assert(donor.x == 2 and donor.y == 0 and donor.objectIndex == 0,
    "the removed bed is not kept and the free live bed is taken instead")
assert(P.getSurvivorPolicies(ids[2]).assignedBed.x == 1,
    "the neighbour's claim is not disturbed by the pickup")

-- 3. With no live bed left the resident is not silently holding a claim: the
--    shortage names them.
now = 12
tiles[2][0].objects = {}
ensure(base, faction)
assert(writes == 1, "no claim is written when the base has no live bed to give")
assert(#notices == 1 and notices[1]:find("One resident still has no bed", 1, true),
    "a resident left without a bed after the pickup is named in the shortage notice")
assert(notices[1]:find("Pickup House", 1, true), "the notice identifies the settlement")

-- 4. A square out of stream is unknown, not empty: with a free bed standing in
--    the same base, the resident must keep the claim instead of being handed a
--    second one for furniture that may still exist.
now = 13
tiles[0][0].objects = { bed(0) }    -- a free live bed is available
tiles[2][0].objects = { bed(0) }
tiles[2][0].loaded = false
assert(ensure(base, faction) == 0 and writes == 1,
    "an unloaded claimed bed is unknown, so no second claim is written")
assert(P.getSurvivorPolicies(ids[1]).assignedBed.x == 2,
    "the claim survives while its square is out of stream, even with a free bed available")
assert(#notices == 1, "an unloaded bed is not reported as a lost bed")
tiles[2][0].loaded = true

-- 5. A replacement bed on the picked-up tile is real furniture again: a resident
--    who has none may take it, and no two residents share a claim.
now = 14
tiles[0][0].objects = { bed(0) }
local third = "bed-pickup-c"
assert(P.setRecord(third, expectedRecord))
resident(third)
-- memberIds is the same table as ids, so one insert adds the member.
table.insert(ids, third)
assert(ensure(base, faction) == 1 and writes == 2,
    "a replacement bed on the picked-up tile is assignable to a resident who has none")
assert(P.getSurvivorPolicies(third).assignedBed.x == 0,
    "the new resident takes the replacement bed")
local seen = {}
for _, id in ipairs(ids) do
    local claim = P.getSurvivorPolicies(id).assignedBed
    if claim ~= nil then
        local key = tostring(claim.x) .. ":" .. tostring(claim.y) .. ":" .. tostring(claim.objectIndex)
        assert(seen[key] == nil, "no two residents hold the same bed reference ("
            .. tostring(key) .. " held by " .. tostring(seen[key])
            .. " and " .. tostring(id) .. ")")
        seen[key] = id
    end
end

P.setFactionResidentBed = realSet
data, getCell, KnoxSurvivorRuntime = oldData, oldCell, oldRuntime
KnoxActivityFeed, AdjacentFreeTileFinder = oldFeed, oldAdjacent
print("Donor bed pickup PASS liveClaimKept=true removedBedReassigned=true shortageNamed=true unloadedKept=true replacementAssignable=true duplicateClaim=false nativeGameplay=false")
