-- A resident's repair scan must see the structure that is nearly gone, not
-- skip it. Drives the production predicate KS_BaseRepairs.damaged reads
-- (mod/42/media/lua/client/KS_BaseRepairs.lua); the values mirror what the
-- installed IsoDoor/IsoThumpable getHealth/getMaxHealth pair returns.
local R = assert(KnoxBaseRepairs, "base repair owner missing")

assert(type(R.needsRepair) == "function", "the scan's damage rule is readable")

-- The repaired case: the worst-hit door in the base was invisible before.
assert(R.needsRepair(250, 2500), "a door at a tenth of its health is repaired")
assert(R.needsRepair(50, 2500), "a door at 2% is repaired, not walked past")

-- The rule it replaces still holds where it was right.
assert(not R.needsRepair(2500, 2500), "an intact door is not busywork")
assert(not R.needsRepair(2400, 2500), "a door at 96% waits")
assert(R.needsRepair(2300, 2500), "a door at 92% is repaired")

-- Bad reads never become a job: the install decides repairability, not a guess.
assert(not R.needsRepair(0, 2500), "a destroyed structure is not a repair target")
assert(not R.needsRepair(-5, 2500), "a negative health read is not damage")
assert(not R.needsRepair(0/0, 2500), "a NaN health read is not damage")
assert(not R.needsRepair(250, 0), "no maximum health is not a structure")
assert(not R.needsRepair(nil, 2500), "a missing health read is not damage")

print("Base repair scan PASS tenth=repair 2pct=repair intact=skip 96pct=skip destroyed=skip")
