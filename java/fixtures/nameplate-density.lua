-- Two survivors standing together painted their second lines into the same pixels.
-- The rule is a pure overlap test, so it can be checked without a screen.
local Nameplates = assert(rawget(_G, "KnoxSurvivorNameplates"), "nameplate owner missing")

assert(Nameplates.crowdedBy(nil, 100, 100, 20, 12) == false, "no list is not crowded")
assert(Nameplates.crowdedBy({}, 100, 100, 20, 12) == false, "an empty pass is not crowded")
assert(Nameplates.crowdedBy({}, nil, 100, 20, 12) == false, "no position is not crowded")

local drawn = { { x = 100, y = 100, halfWidth = 20 } }

-- Directly on top of another plate is crowded.
assert(Nameplates.crowdedBy(drawn, 100, 100, 20, 12) == true, "same spot is crowded")
-- A plate one font height away still collides with the second line.
assert(Nameplates.crowdedBy(drawn, 100, 112, 20, 12) == true, "one line down is crowded")
-- Further out, and clear of the horizontal reach, is not.
assert(Nameplates.crowdedBy(drawn, 100, 140, 20, 12) == false, "a clear gap is not crowded")
assert(Nameplates.crowdedBy(drawn, 200, 100, 20, 12) == false, "across the screen is not crowded")
-- Half widths decide the horizontal reach, not a fixed number.
assert(Nameplates.crowdedBy({ { x = 100, y = 100, halfWidth = 10 } }, 120, 100, 10, 12) == true,
    "touching edges are crowded")
assert(Nameplates.crowdedBy({ { x = 100, y = 100, halfWidth = 10 } }, 121, 100, 10, 12) == false,
    "a pixel clear is not crowded")

-- Several plates are checked, not just the first.
local many = { { x = 500, y = 500, halfWidth = 10 }, { x = 100, y = 100, halfWidth = 20 } }
assert(Nameplates.crowdedBy(many, 102, 101, 20, 12) == true, "the second plate is checked too")

-- Junk in the list is ignored rather than throwing during a render pass.
assert(Nameplates.crowdedBy({ "junk", { x = 100, y = 100, halfWidth = 20 } }, 100, 100, 20, 12) == true,
    "junk records do not stop the check")

print("Nameplate density PASS overlap=true spacing=true reach=true junk=true")
