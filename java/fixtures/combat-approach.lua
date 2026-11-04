-- A survivor attacks along the line it already stands on, and never walks
-- through an ally to get there.
local C = codecCombatApproach

assert(type(C.attackLineOffset) == "function", "attackLineOffset must exist")
assert(type(C.chooseApproach) == "function", "chooseApproach must exist")

-- Standing at 0,0 with the target at 2,0: the square between them is dead in
-- line, the two diagonals are one tile off it.
assert(C.attackLineOffset(0, 0, 2, 0, 1, 0) == 0, "the straight square is in line")
assert(C.attackLineOffset(0, 0, 2, 0, 1, 1) == 1, "a diagonal is one tile off the line")
assert(C.attackLineOffset(0, 0, 0, 3, 0, 1) == 0, "vertical approach is in line too")
assert(C.attackLineOffset(0, 0, 0, 0, 1, 1) == 0, "a zero-length line is not a divide by zero")
assert(C.attackLineOffset(nil, 0, 1, 0, 1, 1) == nil, "missing coordinates answer nil")

-- The in-line square wins even though a diagonal is nearer.
local chosen = C.chooseApproach({
    { distance = 2, lineOffset = 1 },   -- nearer, off line
    { distance = 4, lineOffset = 0 },   -- farther, in line
})
assert(chosen == 2, "the in-line square beats a closer diagonal")

-- Two equally aligned squares fall back to the nearer one.
assert(C.chooseApproach({
    { distance = 9, lineOffset = 0 },
    { distance = 1, lineOffset = 0 },
}) == 2, "distance breaks a tie on the same line")

-- A square somebody already stands on is never chosen, even if it is perfect.
assert(C.chooseApproach({
    { distance = 1, lineOffset = 0, occupied = true },
    { distance = 2, lineOffset = 1 },
}) == 2, "an occupied square is stepped around, not through")

-- If every square is occupied, the caller falls through to its native search.
assert(C.chooseApproach({
    { distance = 1, lineOffset = 0, occupied = true },
    { distance = 2, lineOffset = 1, occupied = true },
}) == nil, "no free square means no choice")
assert(C.chooseApproach({}) == nil)
assert(C.chooseApproach(nil) == nil)

-- Numeric strings are read as numbers, not discarded.
assert(C.chooseApproach({
    { distance = "5", lineOffset = "1" },
    { distance = "3", lineOffset = "0" },
}) == 2)

print("Combat approach PASS line=true occupied=false tie=true digits=true")
