-- A failed native route should make a resident try another seat or the ground
-- until the same furniture is worth reconsidering later.
local previousCell = getCell
local previousFinder = AdjacentFreeTileFinder
local previousPolicies = KnoxPersistence.getSurvivorPolicies
local bed = {
    getObjectIndex = function() return 7 end,
    getProperties = function() return {get = function(_, key)
        return key == "BedType" and "averageBed" or nil
    end} end,
    isFurnitureOccupied = function() return false end,
}
local square = {getObjects = function() return {
    size = function() return 1 end,
    get = function() return bed end,
} end}
getCell = function() return {getGridSquare = function() return square end} end
AdjacentFreeTileFinder = {Find = function() return square end}
KnoxPersistence.getSurvivorPolicies = function() return {
    assignedBed = {x = 1, y = 2, z = 0, objectIndex = 7},
} end
local resident = setmetatable({id = "rest-fixture", currentTicks = 100,
    character = {}, reservations = {restSpots = {}}}, KnoxAutonomyController)
assert(resident:assignedBedSpot() ~= nil, "assigned bed is initially available")
resident.pendingRest = {object = bed}
assert(resident:deferRestSpot(100))
resident.pendingRest = nil
resident.currentTicks = 200
assert(resident:assignedBedSpot() == nil, "failed bed is temporarily skipped")
resident.currentTicks = 3700
assert(resident:assignedBedSpot() ~= nil, "bed is retried after cooldown")
getCell = previousCell
AdjacentFreeTileFinder = previousFinder
KnoxPersistence.getSurvivorPolicies = previousPolicies
print("Rest spot retry PASS failed_bed_skipped=true retry_after_cooldown=true")
