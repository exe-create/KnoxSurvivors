-- A base square can hold a clean tap and a tainted barrel. The survivor's
-- water trip must take the clean one, however much more the barrel holds.
-- Drives the production ranking the controller's source scan now uses.
local N = assert(KnoxSurvivorNeeds, "needs owner missing")

local clean = { available = true, tainted = false, amount = 1 }
local dirty = { available = true, tainted = true, amount = 50 }
local dry = { available = false, tainted = false, amount = 0 }

assert(N.betterWaterSource(dirty, clean) == clean,
    "clean water wins even in a smaller amount")
assert(N.betterWaterSource(clean, dirty) == clean,
    "dirty water never displaces clean water")
assert(N.betterWaterSource(nil, dirty) == dirty,
    "the first admissible source is a start, not a preference")
assert(N.betterWaterSource(dirty, nil) == dirty,
    "a missing candidate changes nothing")
assert(N.betterWaterSource(dirty, dry) == dirty,
    "an empty source is not a source")

local fullerDirty = { available = true, tainted = true, amount = 80 }
assert(N.betterWaterSource(dirty, fullerDirty) == fullerDirty,
    "among tainted sources the fullest wins")
assert(N.betterWaterSource(clean, clean) == clean,
    "equal sources do not churn")

print("Water source choice PASS clean=first fuller=tainted-only empty=skip")
