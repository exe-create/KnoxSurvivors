-- A visible intruder in the same home may interrupt leisure without turning
-- the surrounding yard or another building into a combat objective.
local C = KnoxAutonomyController
local homeBuilding, neighborBuilding = {}, {}
local function square(x, y, building)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
        getBuilding = function() return building end,
    }
end
local here = square(10, 10, homeBuilding)
local resident = setmetatable({
    base = {home = {minX = 8, minY = 8, width = 12, height = 12}},
    character = {getCurrentSquare = function() return here end},
}, C)
local function intruder(at)
    return {getCurrentSquare = function() return at end}
end
assert(resident:isResidentHomeIntruder(intruder(square(13, 11, homeBuilding))))
assert(not resident:isResidentHomeIntruder(intruder(square(13, 11, neighborBuilding))))
assert(not resident:isResidentHomeIntruder(intruder(square(20, 11, homeBuilding))))
-- The far corner of the same home is still the home: distance is no
-- longer the test inside the building.
assert(resident:isResidentHomeIntruder(intruder(square(19, 19, homeBuilding))))
assert(not resident:isResidentHomeIntruder(intruder(square(40, 40, homeBuilding))))
local zombie = intruder(square(13, 11, homeBuilding))
function zombie:isDead() return false end
function zombie:getTarget() return nil end
function zombie:CanSee() return false end
function resident.character:CanSee() return true end
getCell = function()
    return {getZombieList = function()
        return {size = function() return 1 end, get = function() return zombie end}
    end}
end
KnoxSettings = {cautiousTravel = function() return true end}
assert(not C.shouldRemainStealthy(resident), "visible home intruder interrupts leisure")
zombie = intruder(square(20, 11, homeBuilding))
function zombie:isDead() return false end
function zombie:getTarget() return nil end
function zombie:CanSee() return false end
assert(C.shouldRemainStealthy(resident), "a zombie outside the home remains a sighting")
print("Base home defense PASS inside=true neighboring_building=false outside_bounds=false same_building_far=true stealth_interrupt=true")
