-- The wrapped footer: measured widths, a second row instead of an overlap, and
-- a height the page reserves before drawing. Pure, with the measure injected.
-- The four Missions actions were positioned by chaining each x to the previous
-- button's right edge, which is how a narrow page produced an overlap.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.footerPlacements) == "function", "the layout owns the footer")

local function measure(value) return #value end
local function buttons(...)
    local list = {}
    for index = 1, select("#", ...) do
        list[index] = { title = (select(index, ...)), width = 90 }
    end
    return list
end

local wide = L.footerPlacements(buttons("To Party", "To Base", "Resume Duty", "Dispatch..."),
    900, { spacing = 6, buttonHeight = 20, measure = measure })
assert(#wide.placements == 4, "every control is placed")
assert(wide.rows == 1, "four short controls share a wide row, got " .. tostring(wide.rows))
assert(wide.height == 20, "one row is one button height, got " .. tostring(wide.height))

-- Narrow: never an overlap, and the extra rows are paid for in height.
local narrow = L.footerPlacements(buttons("To Party", "To Base", "Resume Duty", "Dispatch..."),
    200, { spacing = 6, buttonHeight = 20, measure = measure })
assert(narrow.rows > 1, "four controls cannot share a narrow row, got " .. tostring(narrow.rows))
assert(narrow.height == narrow.rows * 20 + (narrow.rows - 1) * 6,
    "the reserved height includes the spacing, got " .. tostring(narrow.height))
local byRow = {}
for _, placement in ipairs(narrow.placements) do
    byRow[placement.row] = byRow[placement.row] or {}
    table.insert(byRow[placement.row], placement)
end
for row, placements in pairs(byRow) do
    table.sort(placements, function(first, second) return first.x < second.x end)
    for index = 2, #placements do
        local previous = placements[index - 1]
        assert(previous.x + previous.width <= placements[index].x,
            "row " .. tostring(row) .. " overlaps: " .. tostring(previous.x + previous.width)
                .. " > " .. tostring(placements[index].x))
    end
    for _, placement in ipairs(placements) do
        assert(placement.x + placement.width <= 200, "a footer control stays inside the page")
    end
end

-- A control wider than the page is clamped, never drawn past the edge.
local huge = L.footerPlacements({ { title = "All Of It", width = 500 } }, 120,
    { spacing = 6, buttonHeight = 20, measure = measure })
assert(huge.placements[1].width == 120, "an oversized control is clamped to the page")

local none = L.footerPlacements({}, 200, { measure = measure })
assert(#none.placements == 0 and none.height == 0, "no controls reserves no height")
