-- The map marker has room for one condition word on a single-person marker.
-- This drives the real `markerCondition` helper through the loaded view model;
-- it does not draw a map.
local M = assert(codecMapCondition, "map condition source is loaded")

local bitten = { alive = true, loaded = true,
    needSummary = "Last reported (4 min ago): Bitten" }
assert(M.markerCondition(bitten) == "Bitten", "a bite names the map marker")

local hungry = { alive = true, loaded = true,
    needSummary = "Last reported (3 min ago): Food" }
assert(M.markerCondition(hungry) == "Hungry", "a need names the map marker")

local clear = { alive = true, loaded = true, health = 1,
    needSummary = "Last reported (3 min ago): All right" }
assert(M.markerCondition(clear) == nil, "a fine marker spends no condition")

local dead = { alive = false, needSummary = "Last reported (1 min ago): Bitten" }
assert(M.markerCondition(dead) == nil, "a dead marker keeps its cause, not a condition")

assert(M.markerCondition(nil) == nil, "a missing marker says nothing")
assert(M.markerCondition("Iris") == nil, "a non-table marker says nothing")

print("MapCondition PASS bitten=true hungry=true fine=true dead=quiet")
