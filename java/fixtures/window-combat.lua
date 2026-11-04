-- A window is not a doorway in a fight. This drives the real policy the
-- movement-failure handler asks before it retries a route it cannot take: wait
-- for the zombie to come through, walk round to a door, and only climb a window
-- outside a fight, when nothing else is left.
local policy = assert(codecWindowCombatPolicy, "the window combat policy is loaded")

-- 1. The target is on this side: fight normally, window or not.
assert(policy({ sameSide = true }) == "engage", "a target on this side is engaged")
assert(policy({ sameSide = true, combat = true }) == "engage",
    "combat on this side is still combat")
assert(policy({ sameSide = true, combat = true, doorReachable = true }) == "engage",
    "a door does not matter when the path is already clear")

-- 2. In a fight, a window is never the way through.
assert(policy({ combat = true }) == "hold",
    "a zombie across a window is waited for, not climbed to")
assert(policy({ combat = true, climbAllowed = true, windowSafe = true }) == "hold",
    "even a safe window is not climbed into a fight")
assert(policy({ combat = true, doorReachable = true }) == "around",
    "a reachable door is the way round in a fight")

-- 3. Outside a fight the old ordering holds: door first, then a safe window.
assert(policy({ doorReachable = true }) == "around", "a door outranks a window")
assert(policy({ climbAllowed = true, windowSafe = true }) == "climb",
    "a safe window is the last resort when nothing else is reachable")
assert(policy({ climbAllowed = false, windowSafe = true }) == "hold",
    "climbing closed holds instead of crossing")
assert(policy({ climbAllowed = true, windowSafe = false }) == "hold",
    "an unsafe window is not crossed")
assert(policy({}) == "hold", "no facts means no crossing")

print("Window combat PASS hold=combat around=door climb=lastResort sameSide=engage")
