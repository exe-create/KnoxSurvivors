-- The labelled grid: a gutter for row names, equal cells after it, and a hit
-- test that returns the cell under the pointer. Pure, with the gutter supplied.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.tableCells) == "function", "the layout owns the table")
assert(type(L.tableCellAt) == "function", "the layout owns the table hit test")

local grid = L.tableCells(8, 4, 844, { gutter = 84, gap = 4, rowHeight = 20 })
assert(grid.rows == 8 and grid.columns == 4, "eight jobs by four states")
assert(#grid.cells == 32, "one cell per state per job, got " .. #grid.cells)
assert(grid.cellWidth == 186, "cells divide the body, got " .. tostring(grid.cellWidth))
assert(grid.cells[1].x == 88, "the first cell starts after the gutter and gap, got "
    .. tostring(grid.cells[1].x))
assert(grid.cells[1].y == 0, "the first row starts at the top")
assert(grid.cells[2].x == 278, "the next state follows the gap, got "
    .. tostring(grid.cells[2].x))
assert(grid.cells[5].y == 20, "the second job sits one row down, got "
    .. tostring(grid.cells[5].y))
assert(grid.height == 160, "eight rows are eight row heights, got " .. tostring(grid.height))
assert(grid.cells[32].x + grid.cells[32].width <= 844, "the last cell stays on the page")

local hit = L.tableCellAt(grid, 100, 10)
assert(hit ~= nil and hit.row == 1 and hit.column == 1, "the first cell is hit")
local second = L.tableCellAt(grid, 279, 25)
assert(second ~= nil and second.row == 2 and second.column == 2,
    "a cell on the second job and state is hit")
assert(L.tableCellAt(grid, 50, 10) == nil, "the gutter is not a cell")
assert(L.tableCellAt(grid, 100, 400) == nil, "below the last row is not a cell")

local none = L.tableCells(0, 4, 844, { gutter = 84 })
assert(#none.cells == 0 and none.height == 0, "no rows reserves no height")
