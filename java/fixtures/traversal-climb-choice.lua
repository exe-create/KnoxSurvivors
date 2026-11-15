-- Drives the real KnoxSurvivorTraversal rules: which floor a walk crosses, and
-- whether a ladder or a sheet rope is used. Native actions are not queued here;
-- the choice and the direction they are chosen from are.
local T = assert(Traversal, "the traversal module loads")
assert(T.climbDirection(0, 1) == "up", "a higher goal is a climb up")
assert(T.climbDirection(1, 0) == "down", "a lower goal is a climb down")
assert(T.climbDirection(1, 1) == nil, "the same floor needs no climb")
assert(T.climbDirection(nil, 1) == nil, "an unknown floor needs no climb")
assert(T.climbChoice(true, true) == "ladder", "a ladder is used before a rope")
assert(T.climbChoice(false, true) == "rope", "a sheet rope is the fallback")
assert(T.climbChoice(false, false) == nil, "nothing climbable means no climb")
assert(T.climbChoice(nil, nil) == nil, "missing probes mean no climb")
