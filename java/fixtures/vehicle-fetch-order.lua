-- Who can drive a car to you is decided by KS_NpcVehicleTravel's own admission,
-- not by a second list of rules. The stubbed vehicles expose only the native
-- readers that admission actually asks for.
assert(KnoxNpcVehicleTravel ~= nil, "travel owner missing")
local travel = KnoxNpcVehicleTravel
assert(travel.readyVehicleNear ~= nil, "vehicle search missing")

local savedCount, savedSpecific = getNumActivePlayers, getSpecificPlayer
getNumActivePlayers = function() return 0 end
getSpecificPlayer = function() return nil end

local function squareAt(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end }
end

local function vehicleAt(x, y, z, overrides)
    local square = squareAt(math.floor(x), math.floor(y), z)
    local state = { driver = nil, keys = true, engine = true, driveable = true,
        speed = 0, fuel = 50, locked = false }
    for key, value in pairs(overrides or {}) do state[key] = value end
    return {
        getX = function() return x end, getY = function() return y end,
        getSquare = function() return square end,
        getDriver = function() return state.driver end,
        isKeysInIgnition = function() return state.keys end,
        isHotwired = function() return false end,
        getKeyId = function() return 1 end,
        isEngineRunning = function() return state.engine end,
        isDriveable = function() return state.driveable end,
        getCurrentSpeedKmHour = function() return state.speed end,
        getVehicleTowing = function() return nil end,
        getVehicleTowedBy = function() return nil end,
        getRemainingFuelPercentage = function() return state.fuel end,
        areAllDoorsLocked = function() return state.locked end,
    }
end

-- One survivor standing on an empty street; the car has to come to them.
local driver = { getCurrentSquare = function() return squareAt(10, 10, 0) end,
    getX = function() return 10 end, getY = function() return 10 end }

local near = vehicleAt(14, 10, 0)
local far = vehicleAt(28, 10, 0)
assert(travel.readyVehicleNear(driver, { near, far }) == near,
    "the nearest ready car is the one sent")
-- Neither the first nor the last candidate decides: distance does.
assert(travel.readyVehicleNear(driver, { far, near }) == near,
    "candidate order does not choose the car")

-- Every refusal keeps the car out of the order instead of promising a trip.
local cases = {
    { vehicleAt(12, 10, 0, { locked = true }), "a locked car is not sent" },
    { vehicleAt(12, 10, 0, { keys = false }), "a keyless car is not sent" },
    { vehicleAt(12, 10, 0, { engine = false }), "a dead engine is not sent" },
    { vehicleAt(12, 10, 0, { driveable = false }), "a wreck is not sent" },
    { vehicleAt(12, 10, 0, { speed = 12 }), "a moving car is not sent" },
    { vehicleAt(12, 10, 0, { fuel = 0 }), "an empty tank is not sent" },
    { vehicleAt(12, 10, 0, { driver = {} }), "an occupied driver seat is not sent" },
    { vehicleAt(12, 10, 1), "a car on another floor is not sent" },
    { vehicleAt(60, 10, 0), "a car beyond the search radius is not sent" },
}
for _, case in ipairs(cases) do
    local found = select(1, travel.readyVehicleNear(driver, { case[1] }))
    assert(found == nil, case[2])
end

local found, reason = travel.readyVehicleNear(driver, { vehicleAt(12, 10, 0, { fuel = 0 }) })
assert(found == nil and reason == "vehicle_low_fuel",
    "the refusal names the real reason, got " .. tostring(reason))

local blocked = vehicleAt(12, 10, 0, { locked = true })
local ready = vehicleAt(18, 10, 0)
assert(travel.readyVehicleNear(driver, { blocked, ready }) == ready,
    "a refusal on one car does not abandon the search")
assert(travel.readyVehicleNear(driver, {}) == nil, "an empty street sends nothing")

getNumActivePlayers, getSpecificPlayer = savedCount, savedSpecific
-- Opening the map with several companions must not walk the cell per candidate.
local scans = 0
local clock = 1000
-- Count iterator work, not the cheap accessor: the cache is allowed to ask the
-- cell for its vehicle set, it is not allowed to walk it again.
local listed = { size = function() return 0 end,
    iterator = function()
        scans = scans + 1
        return { hasNext = function() return false end, next = function() end }
    end }
local savedCell, savedClock = getCell, getTimestampMs
getCell = function() return { getVehicles = function() return listed end } end
getTimestampMs = function() return clock end
local first = travel.parkedVehicles()
local second = travel.parkedVehicles()
assert(first == second, "the parked list is reused inside the window")
assert(scans == 1, "one scan answers repeated asks, got " .. tostring(scans))
clock = 5000
travel.parkedVehicles()
assert(scans == 2, "the list refreshes after the window, got " .. tostring(scans))
getCell, getTimestampMs = savedCell, savedClock

print("Vehicle fetch order PASS nearest=true refusal=true reason=true sameFloor=true radius=true cache=true")
