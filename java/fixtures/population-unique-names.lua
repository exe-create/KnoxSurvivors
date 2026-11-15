-- Exercise the production allocator with a deliberately stuck native name RNG.
-- Restore the shared harness state so later fixtures see their original world.
local P = assert(KnoxPersistence)
local data = ModData.getOrCreate("KnoxSurvivors_IsoPlayer")
local oldSurvivors, oldNext, oldFactory = data.survivors, data.nextWorldSurvivorId, SurvivorFactory
-- Normalize the owner before swapping its graph.
P.getPopulationState()
data.survivors = {
    saved = { identity = { forename = "Alex", surname = "Smith" }, alive = false },
    authored = { creator = { name = "  CASEY   SMITH " } },
}
data.nextWorldSurvivorId = 1
local genderCalls = 0
SurvivorFactory = {
    getRandomForename = function(female)
        assert(type(female) == "boolean", "native selection receives a gender")
        genderCalls = genderCalls + 1
        return "Alex"
    end,
    getRandomSurname = function() return "Smith" end,
}
local function allocate(n, building)
    local id, why = P.allocateWorldSurvivor({x = 71000 + n, y = 72000, z = 0,
        source = "world_building", buildingId = building, household = true}, 10)
    assert(id, "unique name allocation succeeds: " .. tostring(why))
    return id, P.getSurvivorIdentity(id)
end
local seen = { ["alex smith"] = true, ["casey smith"] = true }
for i = 1, 400 do
    local id, identity = allocate(i, "same-house")
    local key = (identity.forename .. " " .. identity.surname):lower()
    assert(not seen[key], "every generated full name is unique, including saved and authored names")
    assert(identity.surname == "Smith", "household keeps its shared surname")
    seen[key] = true
end
assert(data.survivors.saved.identity.forename == "Alex" and data.survivors.saved.identity.surname == "Smith",
    "saved dead identity remains unchanged")
assert(data.survivors.authored.creator.name == "  CASEY   SMITH ", "authored identity remains unchanged")
assert(genderCalls > 0, "native forename selection is attempted")
for i = 401, 674 do allocate(i, "same-house") end
local beforeExhaustion = data.nextWorldSurvivorId
local failed, exhausted = P.allocateWorldSurvivor({x=71999,y=72000,z=0,
    source="world_building",buildingId="same-house",household=true}, 10)
assert(failed == nil and exhausted == "name_pool_exhausted"
    and data.nextWorldSurvivorId == beforeExhaustion and data.survivors["ks-world-"..beforeExhaustion] == nil,
    "name pool exhaustion leaves both the ID and survivor graph unchanged")
SurvivorFactory.getRandomForename = function(female) return "Unique" end
SurvivorFactory.getRandomSurname = function() return "Native" end
local id = assert(P.allocateWorldSurvivor({x = 72000, y = 73000, z = 0}, 10))
local identity = P.getSurvivorIdentity(id)
assert(identity.forename == "Unique" and identity.surname == "Native", "unique native name is retained")
local nextId = data.nextWorldSurvivorId
local duplicate, reason = P.allocateWorldSurvivor({x = 72000, y = 73000, z = 0}, 10)
assert(duplicate == nil and reason == "origin_already_used" and data.nextWorldSurvivorId == nextId,
    "occupied origin does not consume an id")
data.survivors, data.nextWorldSurvivorId, SurvivorFactory = oldSurvivors, oldNext, oldFactory
print("Population unique names PASS stuckRng=674 household=true saved=true authored=true nativeFirst=true exhaustion=true")
return "PASS stuckRng=674 household=true saved=true authored=true nativeFirst=true exhaustion=true nativeGameplay=false"
