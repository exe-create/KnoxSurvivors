local oldPersistence, oldManager, oldEvents = KnoxPersistence, KnoxBaseManager, KnoxEvents
local L, W = assert(KnoxSurvivorLooting), assert(codecClaimedOrigin)
local square = { base = "home" }
local bases = { home = { id = "home", ownerKind = "player", ownerId = "player" },
    camp = { id = "camp", ownerKind = "faction", ownerId = "other" } }
local duty, event = nil, nil
KnoxPersistence = { getBases = function() return bases end,
    getSurvivorDuty = function() return duty end }
KnoxBaseManager = { containsSquare = function(base, tile) return tile.base == base.id end }
KnoxEvents = { get = function() return event end }
assert(not L.canLootSquare("stranger", square), "stranger cannot loot a claimed home")
bases.home.overnightGuests={stranger={status="accepted",untilHours=31}}
assert(not L.canLootSquare("stranger",square),"an accepted overnight guest does not gain storage access")
assert(not W.firstSpawnUnclaimed(square), "random first spawn cannot use a claimed home")
assert(L.canLootSquare("stranger", { base = "unclaimed" }), "unclaimed buildings remain scavengable")
assert(W.firstSpawnUnclaimed({ base = "unclaimed" }), "unclaimed origins remain available")
assert(not W.firstSpawnUnclaimed(nil), "missing spawn square is refused")
local origin={source="world_building",buildingId="house"}
local loadedId="house"
local loadedSquare={getRoom=function() return {} end,getBuilding=function() return {
    getDef=function() return {getID=function() return loadedId end} end,
} end}
assert(W.originSquareMatches(origin,loadedSquare),"materialization stays inside its real origin building")
loadedId="next-door"
assert(not W.originSquareMatches(origin,loadedSquare),"a blocked origin cannot move the person into a neighbor's house")
loadedSquare.getRoom=function() return nil end
loadedId="house"
assert(not W.originSquareMatches(origin,loadedSquare),"a household cannot materialize in its yard instead of a room")
assert(not L.canLootSquare(nil, square), "missing actor is refused")
duty = { mode = "base", baseId = "home" }
assert(L.canLootSquare("resident", square), "resident can take from home")
assert(not L.canLootSquare("resident", { base = "camp" }), "residence grants no other base")
duty = { mode = "companion", ownerId = "player" }
assert(L.canLootSquare("companion", square), "owner companion can use home supplies")
duty.ownerId = "someone_else"
assert(not L.canLootSquare("outsider", square), "another player's companion has no permission")
duty = { mode = "event", eventId = "raid" }
event = { kind = "faction_raid", phase = "objective", targetBaseId = "home" }
assert(L.canLootSquare("raider", square), "active raid may select its target stores")
event.targetBaseId = "camp"
assert(not L.canLootSquare("raider", square), "raid cannot select another base")
event.targetBaseId, event.phase = "home", "returning"
assert(not L.canLootSquare("raider", square), "finished raid loses permission")
event.phase, event.kind = "objective", "faction_entry"
assert(not L.canLootSquare("visitor", square), "visiting is not permission to loot")
duty = { mode = "base", baseId = "home" }
assert(L.canLootSquare("resident", square), "initial claim allows resident")
duty.baseId = "camp"
assert(not L.canLootSquare("resident", square), "permission is reread after residence changes")
KnoxBaseManager = nil
assert(not L.canLootSquare("stranger", square), "unavailable ownership service refuses taking")
assert(not W.firstSpawnUnclaimed(square), "unavailable ownership service refuses first spawn")
KnoxPersistence, KnoxBaseManager, KnoxEvents = oldPersistence, oldManager, oldEvents
