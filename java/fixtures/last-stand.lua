-- A survivor that cannot get away turns and fights, once, and says so.
local C = codecLastStand

assert(type(C.lastStandDue) == "function", "lastStandDue must exist")
assert(type(C.lastStandLine) == "function", "lastStandLine must exist")
assert(C.LAST_STAND_FAILURES == 3, "three failed escapes is the threshold")
assert(type(C.LAST_STAND_FAILURE_WINDOW) == "number" and C.LAST_STAND_FAILURE_WINDOW > 0)
assert(type(C.LAST_STAND_TICKS) == "number" and C.LAST_STAND_TICKS > 0)

-- Two failed escapes is bad luck, not hopelessness.
assert(C.lastStandDue({ failures = 0 }) == false)
assert(C.lastStandDue({ failures = 1 }) == false)
assert(C.lastStandDue({ failures = 2 }) == false)

-- The third attempt that produced no distance is the decision.
assert(C.lastStandDue({ failures = 3 }) == true, "three failed escapes means stand")
assert(C.lastStandDue({ failures = 7 }) == true)

-- If the lane has actually opened, the count is irrelevant.
assert(C.lastStandDue({ failures = 5, escapeClear = true }) == false,
    "a real escape is never overridden by the counter")

-- Absent facts never start a heroic last stand.
assert(C.lastStandDue({}) == false)
assert(C.lastStandDue(nil) == false)
assert(C.lastStandDue({ failures = "3" }) == true, "numeric strings are read as numbers")

-- The line is stable per survivor and always one of the authored ones.
local first = C.lastStandLine("ks-survivor-17")
assert(type(first) == "string" and #first > 0)
assert(first == C.lastStandLine("ks-survivor-17"), "the same survivor says the same line")
assert(C.LAST_STAND_LINES ~= nil and #C.LAST_STAND_LINES >= 3,
    "several lines exist so a group does not speak in unison")
local authored = false
for _, line in ipairs(C.LAST_STAND_LINES) do
    if line == first then authored = true end
end
assert(authored, "the chosen line is one of the authored lines")
for _, line in ipairs(C.LAST_STAND_LINES) do
    assert(#line <= 120, "a spoken line stays short enough for the feed")
end
assert(C.lastStandLine(nil) ~= nil, "a missing id still yields a line")

print("Last stand PASS threshold=true clear=false stable=true lines=true")
