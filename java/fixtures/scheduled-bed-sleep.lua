-- A scheduled night uses the native sleep path for both base owners, but a
-- player's base only through a bed the player actually assigned.
local C = codecScheduledBedSleep

assert(type(C.scheduledSleepUsesBed) == "function", "scheduledSleepUsesBed must exist")

-- A faction assigns its own beds, so its night always sleeps natively.
assert(C.scheduledSleepUsesBed("faction", true) == true)
assert(C.scheduledSleepUsesBed("faction", false) == true,
    "a faction resident sleeps in a discovered bed, not the floor fallback")
assert(C.scheduledSleepUsesBed("faction", nil) == true)

-- A player's base sleeps natively only in a bed the player assigned.
assert(C.scheduledSleepUsesBed("player", true) == true,
    "an assigned bed is the whole point of the gate")
assert(C.scheduledSleepUsesBed("player", false) == false,
    "no assignment must not invent a bed")
assert(C.scheduledSleepUsesBed("player", nil) == false)

-- Only a real boolean true counts; a truthy non-boolean is not an assignment.
assert(C.scheduledSleepUsesBed("player", 1) == false)
assert(C.scheduledSleepUsesBed("player", "yes") == false)

-- Unknown or missing owners keep the historical ambient rest.
assert(C.scheduledSleepUsesBed(nil, true) == false)
assert(C.scheduledSleepUsesBed("camp", true) == false)
assert(C.scheduledSleepUsesBed("", true) == false)

print("Scheduled bed sleep PASS faction=true playerAssigned=true playerUnassigned=false unknown=false")
