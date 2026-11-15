-- The chip row, with no atlas in the fixture. A chip is its measured text plus
-- its padding; a chip that does not fit moves to the next row instead of
-- overlapping its neighbour or leaving the sheet.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.chipCells) == "function", "the layout owns chip placement")

local measure = function(value) return #value end
local row = L.chipCells({ "Resident", "Trusted" }, 200,
    { gap = 6, pad = 8, height = 16, measure = measure })
assert(row.rows == 1, "two short chips share one row, got " .. tostring(row.rows))
assert(row.cells[1].width == 24, "a chip is its text plus its padding, got "
    .. tostring(row.cells[1].width))
assert(row.cells[1].x == 0, "the first chip starts at the edge")
assert(row.cells[2].x == 30, "the second chip follows the gap, got "
    .. tostring(row.cells[2].x))
assert(row.height == 16, "one row is one chip high, got " .. tostring(row.height))

local wrapped = L.chipCells({ "Resident", "Trusted" }, 40,
    { gap = 6, pad = 8, height = 16, measure = measure })
assert(wrapped.rows == 2, "a chip that does not fit moves to the next row, got "
    .. tostring(wrapped.rows))
assert(wrapped.cells[2].x == 0 and wrapped.cells[2].y == 22,
    "the wrapped chip starts a new row")
assert(wrapped.height == 38, "two rows are two chip heights plus the gap, got "
    .. tostring(wrapped.height))

local clamped = L.chipCells({ "An unusually long standing label" }, 40,
    { gap = 6, pad = 8, height = 16, measure = measure })
assert(clamped.cells[1].width == 40, "a chip wider than the room takes the room, got "
    .. tostring(clamped.cells[1].width))

local toned = L.chipCells({ { text = "Resident", tone = "green" } }, 100, { measure = measure })
assert(toned.cells[1].tone == "green", "a chip keeps its tone")

local empty = L.chipCells({ "" }, 100, { measure = measure })
assert(#empty.cells == 0 and empty.rows == 0 and empty.height == 0,
    "an empty chip is not drawn")

local oldText,oldFont=getTextManager,UIFont
UIFont={Small=1}
getTextManager=function() return {getFontHeight=function() return 14 end,
    MeasureStringX=function(self,font,text) return #text*7 end} end
local paints=0
L.drawChips({drawText=function() end,drawRect=function(self,x,y,w,h,a,r,g,b)
    paints=paints+1
    assert(a==0.30 and r==L.theme.border[1] and g==L.theme.border[2] and b==L.theme.border[3],
        "chip border uses native alpha-first colour arguments")
end},toned,0,0)
assert(paints==1,"chip colour contract drives the production renderer")
getTextManager,UIFont=oldText,oldFont
