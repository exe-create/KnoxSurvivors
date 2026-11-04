local M = assert(KnoxHumanCombatRelations, "the human combat owner is loaded")
assert(type(M.factionWitnesses) == "function", "the faction witness projection is loaded")

local function ids(list) return table.concat(list, ",") end

local candidates = {
    { id = "victim", factionId = "raiders" },
    { id = "ally", factionId = "raiders" },
    { id = "stranger", factionId = "traders" },
    { id = "resident", factionId = "raiders", playerOwned = true },
    { id = "angry", factionId = "raiders", hostile = true },
    { id = "blind", factionId = "raiders" },
}
local seen = { ally = true, stranger = true, resident = true, angry = true }
local witnesses = M.factionWitnesses("victim", "raiders", candidates,
    function(candidate) return seen[candidate.id] == true end)
assert(ids(witnesses) == "ally", "only a seeing faction peer joins: " .. ids(witnesses))
assert(#M.factionWitnesses("victim", "raiders", candidates,
    function() return false end) == 0, "nobody who could not see the blow joins")
assert(#M.factionWitnesses("victim", nil, candidates,
    function() return true end) == 0, "an unaffiliated victim has no faction answer")
assert(#M.factionWitnesses("victim", "raiders", nil,
    function() return true end) == 0, "a missing candidate list is quiet")
assert(#M.factionWitnesses("victim", "", candidates,
    function() return true end) == 0, "an empty faction id is quiet")
print("Faction witness PASS peer=true sight=true player_owned=false hostile=false")
