-- A survivor checks the body it just put down, but only the one within reach.
local C = codecBodyCheck

assert(type(C.bodyCheckApplies) == "function", "bodyCheckApplies must exist")

-- The kill this survivor just made, at its own feet and one tile out.
assert(C.bodyCheckApplies(true, true, 0) == true)
assert(C.bodyCheckApplies(true, true, 1) == true, "an adjacent body is still this kill")
assert(C.bodyCheckApplies(true, true, 4) == true, "two tiles is the edge of arm's reach")

-- Anything further is a second movement goal, not a body check.
assert(C.bodyCheckApplies(true, true, 5) == false, "a body three tiles out is not checked")
assert(C.bodyCheckApplies(true, true, 100) == false)

-- Not dead, or a different floor, is not a corpse this survivor can reach.
assert(C.bodyCheckApplies(false, true, 1) == false, "a living target is not a corpse")
assert(C.bodyCheckApplies(true, false, 1) == false, "another floor is not reachable")
assert(C.bodyCheckApplies(nil, true, 1) == false)
assert(C.bodyCheckApplies(true, nil, 1) == false)

-- Unreadable distance never authorizes a loot.
assert(C.bodyCheckApplies(true, true, nil) == false)
assert(C.bodyCheckApplies(true, true, "far") == false)

-- Numeric strings are read as numbers, like the rest of the controller.
assert(C.bodyCheckApplies(true, true, "2") == true)

print("Body check PASS near=true far=false living=false floor=false")
