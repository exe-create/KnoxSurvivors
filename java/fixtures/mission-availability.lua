-- The Missions tab asks the dispatch owner how many residents a base could
-- really send before it asks for a party size, so the refusal must come from the
-- same rules the order applies. This fixture drives the real
-- `Autonomy.baseMissionAvailability` (and the dispatch early refusal) against
-- real persistence: a base with nobody on base duty, a base-duty resident whose
-- body is not loaded, and the invalid/absent inputs. The positive count needs a
-- loaded controller and is therefore native-only.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
local Autonomy = KnoxSurvivorAutonomy
assert(type(Autonomy) == "table" and type(Autonomy.baseMissionAvailability) == "function",
    "the dispatch owner must expose its availability rule")
assert(type(Autonomy.dispatchBaseScout) == "function",
    "the dispatch owner under test is the real one")

local function seed(id, forename)
    assert(p.setRecord(id, expectedRecord))
    p.ensureSurvivorIdentity(id, forename, "Vale", 10, 34)
end

-- One fake player owns every base below; the id comes from the owner itself so
-- the fixture cannot disagree with ensurePlayerId.
local playerData = {}
local player = { getModData = function() return playerData end }
local ownerId = assert(p.ensurePlayerId(player), "the player keeps a durable id")
assert(p.ensurePlayerId(player) == ownerId, "the player id is stable")

seed("avail-a", "Mira")
seed("avail-b", "Ansel")

local empty = assert(p.createBase("player", ownerId, {
    minX = 100, minY = 200, width = 12, height = 10, z = 0, buildingId = "avail-empty",
}, 10, nil, true))
local left = assert(p.createBase("player", ownerId, {
    minX = 300, minY = 400, width = 12, height = 10, z = 0, buildingId = "avail-left",
}, 10, nil, true))
local resident = assert(p.createBase("player", ownerId, {
    minX = 500, minY = 600, width = 12, height = 10, z = 0, buildingId = "avail-resident",
}, 10, nil, true))

-- A resident who moved to another duty is no longer this base's resident, so a
-- base whose only resident left reads as empty rather than as a crew.
assert(p.setPlayerCompanion("avail-b", ownerId, "hold", 10))
assert(p.setPlayerBaseResident("avail-b", ownerId, left.id, 10))
assert(#p.getBaseResidentIds(left.id) == 1, "the resident starts on base duty")
assert(p.setPlayerCompanion("avail-b", ownerId, "hold", 10))
assert(p.getSurvivorDuty("avail-b").mode ~= "base", "the resident left base duty")
assert(#p.getBaseResidentIds(left.id) == 0, "a resident on another duty is not counted")

assert(p.setPlayerCompanion("avail-a", ownerId, "hold", 10))
assert(p.setPlayerBaseResident("avail-a", ownerId, resident.id, 10))

local count, reason = Autonomy.baseMissionAvailability(player, empty.id, "scout", nil)
assert(count == 0 and reason == "no_base_residents",
    "a base with nobody at it says so, got " .. tostring(reason))

count, reason = Autonomy.baseMissionAvailability(player, left.id, "scout", nil)
assert(count == 0 and reason == "no_base_residents",
    "a base whose resident left for another duty also says nobody is there")

count, reason = Autonomy.baseMissionAvailability(player, resident.id, "scout", nil)
assert(count == 0 and reason == "need_loaded_base_resident",
    "a base-duty resident who is not loaded cannot be sent, got " .. tostring(reason))

-- The same resident is still refused for a supply run, before the visibility
-- question, because no body is in the world to search.
count, reason = Autonomy.baseMissionAvailability(player, resident.id, "food", nil)
assert(count == 0 and reason == "need_loaded_base_resident",
    "an unloaded base is refused before the visibility question")

count, reason = Autonomy.baseMissionAvailability(player, resident.id, "teleport", nil)
assert(count == 0 and reason == "invalid_mission",
    "an unsupported order type is refused by name")

count, reason = Autonomy.baseMissionAvailability(nil, resident.id, "scout", nil)
assert(count == 0 and reason == "dispatch_unavailable",
    "no player means no order, and it says so")

count, reason = Autonomy.baseMissionAvailability(player, nil, "scout", nil)
assert(count == 0 and reason == "dispatch_unavailable",
    "no base means no order, and it says so")

-- The real dispatch keeps refusing the same impossible orders with its own
-- codes, so the tab's explanation and the order's failure cannot point apart.
local dispatched, failure = Autonomy.dispatchBaseScout(player, resident.id, nil, 1, "scout")
assert(dispatched == false and failure == "dispatch_unavailable",
    "an order with no destination is the existing unavailable failure")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Mission availability PASS emptyBase=true leftDuty=true unloaded=true "
    .. "invalidType=true noPlayer=true")
