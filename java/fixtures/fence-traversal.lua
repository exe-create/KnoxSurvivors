-- A fence is a body-and-object decision, not a boolean. A tall wall needs the
-- slow climb and a body that can manage it; a low fence stays a quick hop even
-- when the survivor is worn out. This drives the real rule the hop asks before
-- it ever queues the native action.
local refusal = assert(codecFenceTraversalRefusal, "the fence refusal rule is loaded")

-- 1. A healthy, rested survivor takes any fence.
assert(refusal(80, 0.10, true) == nil, "a healthy survivor climbs a tall wall")
assert(refusal(80, 0.10, false) == nil, "a healthy survivor hops a low fence")
assert(refusal(100, 0, true) == nil, "full health and no fatigue is never a refusal")

-- 2. A bad wound refuses every fence, tall or low.
assert(refusal(24, 0.10, false) == "too_hurt", "a bad wound refuses a low fence too")
assert(refusal(25, 0.10, true) == nil, "25 health is the boundary, not a refusal")
assert(refusal(0, 0, true) == "too_hurt", "a dying survivor does not climb")

-- 3. Exhaustion refuses the tall climb and only the tall climb.
assert(refusal(80, 0.86, true) == "too_tired", "exhaustion refuses the tall wall")
assert(refusal(80, 0.85, true) == nil, "0.85 fatigue is the boundary, not a refusal")
assert(refusal(80, 0.99, false) == nil, "exhaustion still allows a low hop")

-- 4. Unreadable vitals are not a refusal: the world decides, never a guess.
assert(refusal(nil, nil, true) == nil, "an unreadable body is not refused")
assert(refusal("80", "0.2", true) == nil, "numeric strings are read as numbers")

print("Fence traversal PASS hurt=25 tallFatigue=0.85 lowFenceAlways=true unreadable=none")
