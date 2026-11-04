-- Role-aware mission selection. The catalogue owns the pure fit table and the
-- dispatch owner orders only ids it has already admitted; this fixture drives
-- both against real persistence duties. It does not create a loaded body or a
-- mission, so native formation and travel remain outside its evidence.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local Catalog = assert(KnoxOrderCatalog, "the order catalogue is loaded")
local Autonomy = assert(KnoxSurvivorAutonomy, "the dispatch owner is loaded")
local p = assert(KnoxPersistence, "persistence is loaded")
assert(type(Autonomy.rankMissionCandidates) == "function",
    "the dispatch owner exposes its role ordering")

-- Pure table: a food run values the cook, weapons value the guard, tools value
-- the builder, and an unknown type has no invented ordering.
assert(Catalog.missionRoleScore("cook", "food") == 100,
    "the cook is the strongest food fit")
assert(Catalog.missionRoleScore("guard", "weapons") == 100,
    "the guard is the strongest weapons fit")
assert(Catalog.missionRoleScore("builder", "tools") == 100,
    "the builder is the strongest tools fit")
assert(Catalog.missionRoleScore("cooking", "food") == 100,
    "a legacy cooking preference keeps the cook's fit")
assert(Catalog.missionRoleScore("rest", "scout") == 50,
    "a roleless preference uses the neutral score")
assert(Catalog.missionRoleScore("cook", "teleport") == nil,
    "an unknown mission type has no role score")
local pure = Catalog.rankMissionCandidates({
    { id = "c", role = "guard" }, { id = "a", role = "cook" },
    { id = "b", role = "scavenger" },
}, "food")
assert(#pure == 3 and pure[1] == "a" and pure[2] == "b" and pure[3] == "c",
    "food ranks cook, scavenger, guard")
local tied = Catalog.rankMissionCandidates({
    { id = "z", role = "auto" }, { id = "a", role = "auto" },
}, "scout")
assert(tied[1] == "a" and tied[2] == "z",
    "equal roles resolve by id")
assert(#Catalog.rankMissionCandidates({}, "food") == 0,
    "an empty candidate list stays empty")
assert(#Catalog.rankMissionCandidates({ { id = "a", role = "cook" } }, "teleport") == 0,
    "an invalid mission type ranks nobody")

-- Real dispatch selection: the same helper reads the stored duty role, so a
-- table entry cannot diverge from the resident's saved preference.
local function seed(id, forename)
    assert(p.setRecord(id, expectedRecord))
    p.ensureSurvivorIdentity(id, forename, "Rook", 10, 34)
end

local playerData = {}
local player = { getModData = function() return playerData end }
local ownerId = assert(p.ensurePlayerId(player), "the player keeps a durable id")
for index, id in ipairs({ "mr-cook", "mr-scav", "mr-guard", "mr-build", "mr-auto-a", "mr-auto-b" }) do
    seed(id, "R" .. tostring(index))
end
local base = assert(p.createBase("player", ownerId, {
    minX = 700, minY = 800, width = 12, height = 10, z = 0, buildingId = "mission-roles-home",
}, 10, nil, true))
local roles = {
    ["mr-cook"] = "cook", ["mr-scav"] = "scavenger", ["mr-guard"] = "guard",
    ["mr-build"] = "builder", ["mr-auto-a"] = "auto", ["mr-auto-b"] = "auto",
}
for id, role in pairs(roles) do
    assert(p.setPlayerCompanion(id, ownerId, "hold", 10),
        "the survivor belongs to the player before becoming a resident: " .. id)
    assert(p.setPlayerBaseResident(id, ownerId, base.id, 10))
    assert(p.setBaseJobPreference(id, ownerId, base.id, role, 10),
        "the resident keeps its saved mission role: " .. id)
end

local food = Autonomy.rankMissionCandidates({ "mr-guard", "mr-cook", "mr-scav" }, "food")
assert(#food == 3 and food[1] == "mr-cook" and food[2] == "mr-scav" and food[3] == "mr-guard",
    "the real dispatch selector uses the saved cook and scavenger roles")
local weapons = Autonomy.rankMissionCandidates({ "mr-cook", "mr-guard", "mr-scav" }, "weapons")
assert(weapons[1] == "mr-guard" and weapons[2] == "mr-scav" and weapons[3] == "mr-cook",
    "the real dispatch selector uses the saved guard role")
local tools = Autonomy.rankMissionCandidates({ "mr-guard", "mr-build", "mr-scav" }, "tools")
assert(tools[1] == "mr-build" and tools[2] == "mr-scav" and tools[3] == "mr-guard",
    "the real dispatch selector uses the saved builder role")
local auto = Autonomy.rankMissionCandidates({ "mr-auto-b", "mr-auto-a" }, "scout")
assert(auto[1] == "mr-auto-a" and auto[2] == "mr-auto-b",
    "unassigned residents use the neutral score and the id tie-break")
assert(#Autonomy.rankMissionCandidates({ "mr-cook" }, "teleport") == 0,
    "the dispatch owner does not rank an unknown mission type")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Mission roles PASS food=true weapons=true tools=true tie=true legacy=true")