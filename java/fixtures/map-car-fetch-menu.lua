-- The menu promise and the order must agree. This drives the decision that
-- marks an entry unavailable, with stub vehicles that expose only why they are
-- refused.
local orders = rawget(_G, "KnoxMapOrders")
assert(orders ~= nil, "map orders owner missing")
assert(orders.carFetchState ~= nil, "fetch state missing")

local driver = { name = "driver" }
local function travelReturning(vehicle, reason)
    return { readyVehicleNear = function() return vehicle, reason end }
end

local ready = orders.carFetchState(travelReturning({ ready = true }), driver, {})
assert(ready == true, "a ready car makes the entry available")
local available, reason = orders.carFetchState(travelReturning(nil, "vehicle_doors_locked"), driver, {})
assert(available == false and reason == "vehicle_doors_locked",
    "a locked car is refused with its own reason, got " .. tostring(reason))
available, reason = orders.carFetchState(travelReturning(nil, "vehicle_low_fuel"), driver, {})
assert(available == false and reason == "vehicle_low_fuel", "an empty tank keeps its reason")
available, reason = orders.carFetchState(travelReturning(nil, nil), driver, {})
assert(available == false and reason == "vehicle_unavailable",
    "a refusal without a reason still says something, got " .. tostring(reason))
available, reason = orders.carFetchState(nil, driver, {})
assert(available == false and reason == "vehicle_state_unknown",
    "a missing travel owner refuses instead of promising")
available, reason = orders.carFetchState(travelReturning({ ready = true }), nil, {})
assert(available == false and reason == "survivor_unavailable",
    "a missing survivor is not promised a car")

-- The aboard menu answers a different question: can this companion drive this
-- car. Engine, key, tank and seats all come from the shared admission.
assert(orders.driveHereState ~= nil, "drive here state missing")
local function readinessReturning(ok, why)
    return { assessReadiness = function() return ok, why end }
end
local car = { id = "car" }

local canDrive = orders.driveHereState(readinessReturning(true, nil), car, driver, false)
assert(canDrive == true, "a ready car and free seat make the entry available")
local able, why = orders.driveHereState(readinessReturning(false, "vehicle_engine_off"), car, driver, false)
assert(able == false and why == "vehicle_engine_off", "a dead engine keeps its own reason, got " .. tostring(why))
able, why = orders.driveHereState(readinessReturning(false, "vehicle_low_fuel"), car, driver, false)
assert(able == false and why == "vehicle_low_fuel", "a dry tank keeps its own reason")
able, why = orders.driveHereState(readinessReturning(false, nil), car, driver, false)
assert(able == false and why == "vehicle_not_driveable",
    "a refusal without a reason still says something, got " .. tostring(why))
able, why = orders.driveHereState(readinessReturning(true, nil), car, driver, true)
assert(able == false and why == "player_must_vacate_driver_seat",
    "the player's own seat is the first thing said, got " .. tostring(why))
assert(orders.driveHereState(readinessReturning(true, nil), nil, driver, false) == false,
    "no car is no entry")
assert(select(2, orders.driveHereState(nil, car, driver, false)) == "vehicle_state_unknown",
    "a missing travel owner refuses instead of promising")
assert(select(2, orders.driveHereState(readinessReturning(true, nil), car, nil, false)) == "survivor_unavailable",
    "a missing survivor is not offered the wheel")

-- An empty vehicle menu explains itself while the player is in a car.
assert(orders.vehicleMenuHint ~= nil, "menu hint missing")
local aboard = { getVehicle = function() return { id = "car" } end }
local onFoot = { getVehicle = function() return nil end }
assert(orders.vehicleMenuHint(aboard, true, 0) ~= nil,
    "sitting in a car with nobody to drive it says so")
assert(orders.vehicleMenuHint(aboard, true, 2) == nil,
    "companions mean real entries, not an explanation")
assert(orders.vehicleMenuHint(aboard, false, 0) == nil,
    "driving off advertises nothing")
assert(orders.vehicleMenuHint(onFoot, true, 0) == nil,
    "on foot is not a vehicle menu")
assert(orders.vehicleMenuHint(nil, true, 0) == nil, "no player says nothing")

print("Map car fetch menu PASS ready=true reason=true fallback=true missing=true aboard=true hint=true")
