-- Two companions must not stack on one zombie, and a companion who already
-- holds a threat must not be blocked by his own claim. This drives the real
-- reserve/release functions the controller uses, not a copy of them.
local C = codecThreatReservation

assert(type(C.reserveThreat) == "function", "reserveThreat must be exported")
assert(type(C.releaseThreat) == "function", "releaseThreat must be exported")

-- A zombie nobody is fighting yet admits one attacker: the first companion
-- takes it, the second is pushed to a different target.
assert(C.threatAttackerLimit("visible") == 1, "a merely seen threat admits one attacker")
assert(C.threatAttackerLimit("immediate") == 2, "an adjacent threat admits two")
assert(C.threatAttackerLimit("group_target") == 2, "a threat on a group member admits two")
assert(C.threatAttackerLimit("player_target") == 2, "a threat on a player admits two")
assert(C.threatAttackerLimit("active_target") == 3, "a threat already hitting us admits three")
assert(C.threatAttackerLimit(nil) == 1, "an unknown reason falls back to one attacker")

local zed = { name = "zed-1" }
local reservations = { threats = {} }

assert(C.threatReservationCount(reservations, zed, "a") == 0,
    "a fresh threat starts with no other attacker")
assert(C.reserveThreat(reservations, zed, "a", 1) == true, "the first attacker reserves")
assert(C.threatReservationCount(reservations, zed, "b") == 1,
    "the second companion sees one attacker already on it")
assert(C.reserveThreat(reservations, zed, "b", 1) == false,
    "a second attacker is refused on a one-attacker threat")
-- Re-reserving is idempotent: a companion scanning every tick must not refuse
-- himself and drop the fight he is already in.
assert(C.reserveThreat(reservations, zed, "a", 1) == true, "the holder may re-reserve")
assert(C.threatReservationCount(reservations, zed, "a") == 0,
    "a companion is never counted against his own claim")

-- Releasing frees the zombie for the next companion immediately.
C.releaseThreat(reservations, zed, "a")
assert(C.threatReservationCount(reservations, zed, "b") == 0, "the release is visible at once")
assert(C.reserveThreat(reservations, zed, "b", 1) == true, "the freed threat is available")

-- A group threat takes two: the pair covering an ally is allowed, a third is not.
local groupZed = { name = "zed-2" }
assert(C.reserveThreat(reservations, groupZed, "a", C.threatAttackerLimit("group_target")) == true)
assert(C.reserveThreat(reservations, groupZed, "b", C.threatAttackerLimit("group_target")) == true)
assert(C.reserveThreat(reservations, groupZed, "c", C.threatAttackerLimit("group_target")) == false,
    "a third attacker is refused even on a group threat")
assert(C.threatReservationCount(reservations, groupZed, "c") == 2,
    "an outside companion sees both holders")
assert(C.threatReservationCount(reservations, groupZed, "a") == 1,
    "a holder is not counted against his own pair")

-- A missing threat is refused rather than stored under nil.
assert(C.reserveThreat(reservations, nil, "a", 1) == false, "a missing threat is refused")
C.releaseThreat(reservations, nil, "a")
C.releaseThreat(reservations, groupZed, "a")
C.releaseThreat(reservations, groupZed, "b")
assert(reservations.threats[groupZed] == nil, "the last release drops the entry")

print("Threat reservations PASS single=true pair=true triple=false idempotent=true release=true")
