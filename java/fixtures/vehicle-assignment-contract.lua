-- The motor pool record was reachable from nowhere. The driver run now writes
-- it, so the record's own contract has to be true before that matters.
local P = KnoxPersistence

local key = "1042"
local record, status = P.setVehicleAssignment({
    vehicleKey = key, ownerKind = "player", ownerId = "player-1",
    driverId = "survivor-a", passengerIds = { "survivor-b" },
    role = "transport", createdAtHours = 12,
}, 12)
assert(record ~= nil and status == "assigned", "a player vehicle can be assigned")
assert(record.vehicleKey == key and record.driverId == "survivor-a")
assert(#record.passengerIds == 1 and record.passengerIds[1] == "survivor-b")
assert(record.role == "transport" and tonumber(record.createdAtHours) == 12)

-- Readers answer the same fact from three directions.
assert(P.getVehicleAssignment(key).driverId == "survivor-a")
local asPassenger, seat = P.getVehicleAssignmentForSurvivor("survivor-b")
assert(asPassenger ~= nil and seat == "passenger")
local asDriver, driverSeat = P.getVehicleAssignmentForSurvivor("survivor-a")
assert(asDriver ~= nil and driverSeat == "driver")
assert(P.getVehicleAssignmentForSurvivor("nobody") == nil)

-- One survivor belongs to one vehicle.
local second, why = P.setVehicleAssignment({
    vehicleKey = "2048", ownerKind = "player", ownerId = "player-1",
    driverId = "survivor-a", role = "transport",
}, 13)
assert(second == nil and why == "survivor_already_assigned")

-- Re-setting the same car is an update, not a second assignment.
local updated, updateStatus = P.setVehicleAssignment({
    vehicleKey = key, ownerKind = "player", ownerId = "player-1",
    driverId = "survivor-a", passengerIds = {}, role = "cargo",
}, 14)
assert(updated ~= nil and updateStatus == "assigned" and updated.role == "cargo")
assert(#P.getVehicleAssignment(key).passengerIds == 0)

-- Bad input fails closed and never writes a partial record.
assert(select(2, P.setVehicleAssignment({
    vehicleKey = "0", ownerKind = "player", ownerId = "p", role = "transport",
}, 1)) == "vehicle_identity_unavailable")
assert(select(2, P.setVehicleAssignment({
    vehicleKey = "77", ownerKind = "npc", ownerId = "p", role = "transport",
}, 1)) == "invalid_owner")
assert(select(2, P.setVehicleAssignment({
    vehicleKey = "77", ownerKind = "player", ownerId = "", role = "transport",
}, 1)) == "invalid_owner")
assert(select(2, P.setVehicleAssignment({
    vehicleKey = "77", ownerKind = "player", ownerId = "p", role = "siege",
}, 1)) == "invalid_role")
assert(select(2, P.setVehicleAssignment({
    vehicleKey = "77", ownerKind = "player", ownerId = "p", role = "transport",
    driverId = "survivor-a", passengerIds = { "survivor-a" },
}, 1)) == "duplicate_survivor")
assert(P.getVehicleAssignment("77") == nil, "a refused assignment writes nothing")

-- Releasing is explicit and idempotent enough to be called on every teardown.
assert(P.clearVehicleAssignment(key, "run_ended") == true)
assert(P.getVehicleAssignment(key) == nil, "a released vehicle is unassigned")
assert(P.clearVehicleAssignment(key) == false, "releasing twice is harmless")
assert(P.clearVehicleAssignment("0") == false, "an invalid key is refused")
assert(P.getVehicleAssignmentForSurvivor("survivor-a") == nil,
    "releasing frees the survivor for another car")

print("Vehicle assignment PASS write=true read=true once=true release=true")
