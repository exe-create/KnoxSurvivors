-- One day as blocks across the width, and the hit test that turns a click into
-- a block. Pure arithmetic: the timeline never guesses its own geometry.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.timelineCells) == "function", "the layout owns the timeline")
assert(type(L.timelineIndexAt) == "function", "the layout owns the timeline hit test")

local day = L.timelineCells(6, 600, { gap = 4, height = 28 })
assert(day.count == 6, "six blocks")
assert(day.cellWidth == 96, "block width divides the bar, got " .. tostring(day.cellWidth))
assert(day.cells[1].x == 0, "the first block starts at the left edge")
assert(day.cells[2].x == 100, "blocks are separated by the gap, got "
    .. tostring(day.cells[2].x))
assert(day.cells[6].x + day.cells[6].width <= 600, "the last block stays inside the bar")
assert(day.height == 28, "the bar keeps its height")

assert(L.timelineIndexAt(day, 0) == 1, "the left edge is the first block")
assert(L.timelineIndexAt(day, 95) == 1, "a point inside a block belongs to it")
assert(L.timelineIndexAt(day, 98) == nil, "the gap between blocks belongs to neither")
assert(L.timelineIndexAt(day, 100) == 2, "the next block starts after the gap")
assert(L.timelineIndexAt(day, 595) == 6, "the last block is reachable")
assert(L.timelineIndexAt(day, 600) == nil, "past the bar is no block")
assert(L.timelineIndexAt(day, -1) == nil, "before the bar is no block")

-- Twenty-four hours with no gap: each hour is its own block.
local hours = L.timelineCells(24, 600, { gap = 0, height = 20 })
assert(hours.cellWidth == 25, "twenty-four blocks of an even bar, got "
    .. tostring(hours.cellWidth))
assert(L.timelineIndexAt(hours, 25) == 2, "hour two begins at 25px")
assert(L.timelineIndexAt(hours, 599) == 24, "the last hour is reachable")

-- A degenerate bar still hits its first block instead of erroring.
local hair = L.timelineCells(1, 1, { gap = 0 })
assert(hair.cellWidth == 1, "one block of one pixel")
assert(L.timelineIndexAt(hair, 0) == 1, "the single block is hit")

-- Measured labels determine columns; a narrow schedule keeps every time range.
local wrapped = L.timelineCells(6, 380, {gap=3,height=54,minCellWidth=120})
assert(wrapped.columns == 3 and wrapped.rows == 2 and wrapped.height == 111,
    "measured schedule wraps into two complete rows")
for _, cell in ipairs(wrapped.cells) do
    assert(cell.width >= 120 and cell.x + cell.width <= 380, "measured range fits cell")
    assert(L.timelineIndexAt(wrapped,cell.x,cell.y) == cell.index, "each wrapped block is reachable")
end
assert(L.timelineIndexAt(wrapped,0,54) == nil, "row gap is not a block")
assert(L.timelineIndexAt(wrapped,0,111) == nil, "below schedule is not a block")
assert(L.timelineIndexAt(wrapped,wrapped.cellWidth,0) == nil, "column gap is not a block")
local tiny = L.timelineCells(6, 30, {gap=3,height=54,minCellWidth=120})
assert(tiny.columns == 1 and tiny.rows == 6 and tiny.cells[6].width == 30,
    "very narrow viewport uses one column")
