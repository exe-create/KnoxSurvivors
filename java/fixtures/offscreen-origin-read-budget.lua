-- Origin-only population must advance travel without reading nonexistent body state.
local savedPersistence, savedPopulation, savedEvents = KnoxPersistence, KnoxWorldPopulation, KnoxEvents
local ids, travel, records = {}, 0, 0
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
    return true
end }
local advanced, notable = KnoxUnloadedSurvival.advanceAll({"budget-active"}, 13)
assert(advanced == 100 and notable == 0 and travel == 100 and records == 100)
KnoxPersistence, KnoxWorldPopulation, KnoxEvents = savedPersistence, savedPopulation, savedEvents
print("Offscreen read budget PASS 100 real origin travel advances; zero irrelevant duty/physiology reads")
