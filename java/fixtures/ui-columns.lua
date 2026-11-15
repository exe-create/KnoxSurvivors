-- The column rule and the static-list height, with no atlas in the fixture.
-- A page splits only when both columns can hold their minimum, which is what
-- keeps a narrow sheet from clipping its right side.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.columns) == "function", "the layout owns the column split")
assert(type(L.stackHeight) == "function", "the layout owns the static list height")

local wide = L.columns(844, { gap = 12, minLeft = 300, minRight = 300 })
assert(wide.count == 2, "a wide page splits, got " .. tostring(wide.count))
assert(wide.cells[1].width == 416, "the left column takes its half, got "
    .. tostring(wide.cells[1].width))
assert(wide.cells[1].x == 0, "the left column starts at the edge")
assert(wide.cells[2].x == 428, "the right column follows the gap, got "
    .. tostring(wide.cells[2].x))
assert(wide.cells[2].width == 416, "the two columns are equal, got "
    .. tostring(wide.cells[2].width))

-- Exactly at the minimum still splits; one pixel under does not.
local exact = L.columns(612, { gap = 12, minLeft = 300, minRight = 300 })
assert(exact.count == 2, "a page exactly wide enough still splits")
local narrow = L.columns(600, { gap = 12, minLeft = 300, minRight = 300 })
assert(narrow.count == 1, "a page too narrow for two columns stays one, got "
    .. tostring(narrow.count))
assert(narrow.cells[1].width == 600, "one column uses the whole page")
assert(narrow.cells[2].x == 0, "a stacked page does not offset its second block")

local tiny = L.columns(1, { gap = 12, minLeft = 300, minRight = 300 })
assert(tiny.count == 1 and tiny.cells[1].width == 1, "a degenerate width still returns a cell")

assert(L.stackHeight(5, 20, 3, 8) == 108, "five rows are five row heights plus padding")
assert(L.stackHeight(1, 20, 3, 8) == 68, "the minimum rows keep the list readable")
assert(L.stackHeight(0, 20, 1, 0) == 20, "an empty list keeps one row")
