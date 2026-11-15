local P = assert(KnoxPersistence)
local oldData, oldCell, oldRuntime = data, getCell, KnoxSurvivorRuntime
local oldFeed, oldAdjacent = KnoxActivityFeed, AdjacentFreeTileFinder
data = {}
local ids = { "bed-person-a", "bed-person-b" }
for _, id in ipairs(ids) do assert(P.setRecord(id, expectedRecord)) end
local root = data.KnoxSurvivors_IsoPlayer
local faction = { id = "bed-notice-faction", name = "Bed House", kind = "npc", leaderId = ids[1], memberIds = ids }
root.factions[faction.id] = faction
local base = { id = "bed-notice-base", ownerKind = "faction", ownerId = faction.id,
    home = { buildingId = "bed-house", minX = 0, minY = 0, width = 1, height = 1, z = 0 } }
root.bases[base.id] = base
for _, id in ipairs(ids) do
    root.survivors[id].affiliation = { kind = "faction", factionId = faction.id }
    root.survivors[id].duty = { mode = "base", baseId = base.id }
end
local loaded, beds, now = true, 0, 10
local characters = { [ids[1]] = {}, [ids[2]] = {} }
KnoxSurvivorRuntime = { getCharacter = function(id) return loaded and characters[id] or nil end }
local notices = {}
KnoxActivityFeed = { event = function(text) notices[#notices + 1] = text end }
local definition = { getID = function() return "bed-house" end }
local building = { getDef = function() return definition end }
local square = { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    getBuilding = function() return building end }
square.getObjects = function()
    return { size = function() return beds end, get = function(_, i)
        return { getProperties = function() return { get = function() return "goodBed" end } end,
            getObjectIndex = function() return i end, isFurnitureOccupied = function() return false end }
    end }
end
getCell = function() return { getGridSquare = function(_, _, _, z) return z == 0 and square or nil end } end
AdjacentFreeTileFinder = { Find = function() return square end }
local ensure = bedShortageFactory(function() return now end)
assert(ensure(base, faction) == 0 and #notices == 1 and notices[1]:find("2 residents", 1, true),
    "the real bed owner states the loaded two-resident shortage")
assert(notices[1]:find("Bed House", 1, true), "the notice identifies its actual settlement")
assert(P.getSurvivorPolicies(ids[1]).assignedBed == nil, "a notice invents no bed assignment")
now = 11
ensure(base, faction)
assert(#notices == 1, "an unchanged shortage is not repeated after the retry window")
beds, now = 1, 12
assert(ensure(base, faction) == 1 and #notices == 2 and notices[2]:find("One resident", 1, true),
    "one real bed assigns one resident and reports only the remaining shortage")
assert(P.getSurvivorPolicies(ids[1]).assignedBed ~= nil and P.getSurvivorPolicies(ids[2]).assignedBed == nil,
    "the existing persisted bed writer gives the real bed to the leader")
beds, now = 2, 13
assert(ensure(base, faction) == 1 and #notices == 2, "enough real beds resolve the shortage silently")
root.survivors[ids[2]].policies.assignedBed = nil
beds, now = 1, 14
ensure(base, faction)
assert(#notices == 3, "a resolved shortage can be reported when it genuinely returns")
loaded, now = false, 15
ensure(base, faction)
assert(#notices == 3, "unloaded residents create no new shortage notice")
loaded, beds, now = true, 2, 16
assert(P.setFactionResidentBed(ids[2], faction.id, base.id, { x = 0, y = 0, z = 0, objectIndex = 1 }, now))
ensure(base, faction)
root.survivors[ids[2]].policies.assignedBed = nil
beds, now = 1, 17
ensure(base, faction)
assert(#notices == 4, "an externally resolved shortage resets the notice before a later loss")
local playerBase = { id = "bed-player", ownerKind = "player", ownerId = faction.id }
ensure(playerBase, faction)
assert(#notices == 4, "the faction owner does not invent a player-base bed notice")
data, getCell, KnoxSurvivorRuntime = oldData, oldCell, oldRuntime
KnoxActivityFeed, AdjacentFreeTileFinder = oldFeed, oldAdjacent
print("Bed shortage PASS realOwner=true noInventedBed=true once=true partial=true resolved=true recurrence=true unloadedSilent=true nativeGameplay=false")
