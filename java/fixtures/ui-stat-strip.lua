-- The count strip: one cell per count, sized from the available width, wrapped
-- rather than squeezed when the width cannot hold the minimum. Pure arithmetic,
-- so this is the only place the rule can be wrong.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.statStripCells) == "function", "the layout owns the count strip")

local four = {
    { value = "3", label = "residents" },
    { value = "2", label = "work areas" },
    { value = "1", label = "waiting" },
    { value = "0", label = "posts" },
}

-- A wide page holds all four in one row.
local wide = L.statStripCells(four, 400, { gap = 8, minCell = 90, rowH = 26 })
assert(wide.columns == 4, "four cells fit a wide page, got " .. tostring(wide.columns))
assert(wide.rows == 1, "a fitting strip is one row, got " .. tostring(wide.rows))
assert(wide.height == 26, "one row is one row height, got " .. tostring(wide.height))
assert(wide.cellWidth == 94, "cell width divides the page, got " .. tostring(wide.cellWidth))
assert(wide.cells[1].x == 0, "the first cell starts at the left edge")
assert(wide.cells[2].x == 102, "cells are separated by the gap, got " .. tostring(wide.cells[2].x))
assert(wide.cells[4].row == 0, "no cell wraps when the row fits")

-- A narrow page wraps instead of shrinking the cells past the minimum.
local narrow = L.statStripCells(four, 200, { gap = 8, minCell = 90, rowH = 26 })
assert(narrow.columns == 2, "a narrow page holds two cells, got " .. tostring(narrow.columns))
assert(narrow.rows == 2, "four cells over two columns is two rows, got " .. tostring(narrow.rows))
assert(narrow.height == 52, "two rows are two row heights, got " .. tostring(narrow.height))
assert(narrow.cells[3].row == 1, "the third cell wraps")
assert(narrow.cells[3].x == 0, "a wrapped row starts at the left edge")
assert(narrow.cells[3].y == 26, "a wrapped row sits one row down, got " .. tostring(narrow.cells[3].y))

-- Narrower than two minima: one cell per row, never a clipped number.
local tiny = L.statStripCells(four, 90, { gap = 8, minCell = 90, rowH = 26 })
assert(tiny.columns == 1, "a page narrower than two minima holds one cell")
assert(tiny.rows == 4, "one column means one row per cell, got " .. tostring(tiny.rows))

-- No values is not an error and reserves no height.
local none = L.statStripCells({}, 300, {})
assert(#none.cells == 0, "no values means no cells")
assert(none.height == 0, "no cells means no height, got " .. tostring(none.height))

-- Every cell keeps the width it was given.
for _, cell in ipairs(wide.cells) do
    assert(cell.width == wide.cellWidth, "every cell shares the row width")
end

local measure=function(text) return #text*13.2 end
local measured=L.statStripCells({L.valueRow(100,"tasks blocked"),L.valueRow(1,"resident")},380,
    {gap=10,minCell=130,rowH=34,measure=measure})
assert(measured.columns==1 and measured.rows==2,"large-font status units reflow instead of ellipsizing")
for _,cell in ipairs(measured.cells) do
    assert(measure(cell.value)+5+measure(cell.label)<=cell.width,"complete count and its unit fit")
end
