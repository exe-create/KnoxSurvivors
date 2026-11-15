-- The owner's console on 2026-11-10 showed a survivor giving up a supply order
-- with movement=FailedObstacle:FAILED_BLOCKED_DIAGONAL and blocking the room for
-- 3600 ticks. A refused approach and a dead end are different answers, and this
-- predicate is the one place that decides which a movement string is.
local C = assert(codecPathFailure, "the controller slice loaded")

assert(type(C.transientPathFailure) == "function", "the classification exists")

local transient = {
    "movement:FailedObstacle",
    "movement:FailedObstacle:FAILED_BLOCKED_DIAGONAL",
    "movement:Failed",
    "formation_movement:FailedObstacle",
}
for _, movement in ipairs(transient) do
    assert(C.transientPathFailure(movement) == true,
        movement .. " is one refused approach and is retried, not blacklisted")
end

local deadEnd = {
    "unreachable_supply",
    "movement:unreachable",
    "movement:NO_PATH",
    "formation_movement:FailedWrongFloorOrPosition",
}
for _, movement in ipairs(deadEnd) do
    assert(C.transientPathFailure(movement) == false,
        movement .. " is a dead end, so the order may end")
end

assert(C.transientPathFailure(nil) == false, "a missing movement string is not transient")
assert(C.transientPathFailure("") == false, "an empty movement string is not transient")
assert(C.transientPathFailure("Succeeded") == false, "success is not a path failure")

print("Path failure classification PASS blockedDiagonal=retry unreachable=blocked")
