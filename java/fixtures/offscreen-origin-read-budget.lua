-- Origin-only population must advance travel without reading nonexistent body state.
local savedPersistence, savedPopulation, savedEvents = KnoxPersistence, KnoxWorldPopulation, KnoxEvents
local ids, travel, records, seen = {}, 0, 0, {}
for i = 1, 100 do ids[i] = "budget-origin-" .. tostring(i) end
ids[101] = "budget-active"
KnoxPersistence = {
    getActivatableSurvivorIds = function() return ids end,
    getTravelGroupsFor = function() return {}, {} end,
    getRecord = function(id)
        assert(id ~= "budget-active", "active body must not be read by offscreen pass")
        records = records + 1
        return nil
    end,
    getSurvivorDuty = function() error("origin has no stored duty to process") end,
    getUnloadedSurvivalState = function() error("origin has no stored body physiology") end,
}
KnoxEvents = nil
KnoxWorldPopulation = { advanceOriginTravel = function(id, hours)
    assert(id ~= "budget-active" and hours == 13)
    travel = travel + 1
    seen[id] = true
    return true
end }
for pass=1,2 do
    local before=travel
    local advanced, notable = KnoxUnloadedSurvival.advanceAll({"budget-active"}, 13)
    assert(advanced == 64 and notable == 0 and travel-before == 64,
        "one county pass advances at most 64 origin travel entries")
end
local unique=0
for _ in pairs(seen) do unique=unique+1 end
assert(unique==100 and records==200, "rotation reaches every independent origin without reading active body state")
KnoxPersistence, KnoxWorldPopulation, KnoxEvents = savedPersistence, savedPopulation, savedEvents
print("Offscreen read budget PASS per_pass=64 unique_origins=100 zero_irrelevant_physiology=true")
