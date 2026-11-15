-- P2: stored-material labour advances off-screen only when the base already
-- holds every item the claimed job needs. Drives the production duty module,
-- not a copy: both directions, refusal shapes, and the watch predicate's own
-- meaning (which gates the return walk elsewhere).
local Duty = assert(codecDutyLabor, "the base duty simulation loaded")
local base = { id = "b1" }
local held = { ["Base.Plank"] = 4, ["Base.Nails"] = 10 }
local reads = 0
local function countAssigned(fullType)
    reads = reads + 1
    return held[fullType] or 0
end

local task = {
    state = "claimed", type = "barricade", claimedBy = "s1",
    requirements = { items = { ["Base.Plank"] = 4, ["Base.Nails"] = 8 } },
}

-- Direction one: the need is provably in storage, so labour accrues.
local allowed, reason = Duty.canAdvanceLaborOffscreen(base, task, countAssigned)
assert(allowed == true and reason == "stored_materials",
    "stored material permits off-screen labour: " .. tostring(reason))
local moved, hours = Duty.advanceLabor(base, task, 2, countAssigned)
assert(moved == true and hours == 2, "labour accumulates the elapsed hours")
assert(reads >= 2, "the decision read real stock, not a guess")
assert(task.offscreenWorkHours == 2, "worked hours use the field this module already keeps")
assert(task.offscreenShiftsCompleted == nil, "labour records no watch shift")
assert(task.state == "claimed" and task.claimedBy == "s1", "labour completes and releases nothing off-screen")
assert(task.consumed == nil, "labour consumes nothing off-screen")

-- Direction two: one item short, so the task refuses and accrues nothing.
held["Base.Nails"] = 7
local refused, why = Duty.canAdvanceLaborOffscreen(base, task, countAssigned)
assert(refused == false and why == "material_missing:Base.Nails",
    "short stock refuses by name: " .. tostring(why))
local moved2, hours2 = Duty.advanceLabor(base, task, 3, countAssigned)
assert(moved2 == false and hours2 == 0 and task.offscreenWorkHours == 2,
    "a refused task accrues nothing and loses nothing")

-- Unprovable shapes fail closed rather than assuming the best.
assert(Duty.canAdvanceLaborOffscreen(base,
    { state = "queued", type = "barricade", requirements = { items = { ["Base.Plank"] = 1 } } },
    countAssigned) == false, "an unclaimed task does not labour")
assert(Duty.canAdvanceLaborOffscreen(base, { state = "claimed", type = "barricade" },
    countAssigned) == false, "a missing requirement is not proof")
assert(Duty.canAdvanceLaborOffscreen(base, task, nil) == false,
    "a missing storage reader is not proof")
assert(Duty.canAdvanceLaborOffscreen(base, task, function() return nil end) == false,
    "an unreadable count is not proof")
assert(Duty.advanceLabor(base, task, 3, function() return nil end) == false,
    "an unreadable count advances no hours")

-- The watch predicate keeps its own meaning and its own bookkeeping.
local guard = { state = "claimed", type = "guard", requirements = { items = { ["Base.Plank"] = 1 } } }
assert(Duty.canAdvanceOffscreen(guard) == true, "the watch predicate still answers guard")
assert(Duty.canAdvanceOffscreen(task) == false, "labour did not widen the watch predicate")
assert(Duty.canAdvanceLaborOffscreen(base, guard, countAssigned) == false,
    "a watch shift is not labour bookkeeping")
assert(Duty.advanceLabor(base, guard, 4, countAssigned) == false,
    "a watch shift accrues no labour hours")
assert(guard.offscreenWorkHours == nil, "the watch path was left untouched")

print("Base off-screen labour PASS stored=true short=false completion=false watch_unchanged=true")
