-- The card grid and the parts inside a card, with no atlas in the fixture.
-- Three across is a measurement, not an assumption: fewer cards fit on a narrow
-- page, and the steppers stay inside the card at every width.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.cardGrid) == "function", "the layout owns the card grid")
assert(type(L.cardParts) == "function", "the layout owns the card parts")

local wide = L.cardGrid(7, 844, { gap = 10, minWidth = 220, cardHeight = 74, columns = 3 })
assert(wide.columns == 3, "a wide page holds three cards, got " .. tostring(wide.columns))
assert(wide.cellWidth == 274, "the card width divides the row, got " .. tostring(wide.cellWidth))
assert(wide.cells[1].x == 0, "the first card starts at the edge")
assert(wide.cells[2].x == 284, "the second card follows the gap, got " .. tostring(wide.cells[2].x))
assert(wide.cells[4].y == 84, "the second row starts below a card and the gap, got "
    .. tostring(wide.cells[4].y))
assert(wide.rows == 3, "seven cards on three columns are three rows, got " .. tostring(wide.rows))
assert(wide.height == 242, "the grid reserves every row, got " .. tostring(wide.height))

local mid = L.cardGrid(7, 500, { gap = 10, minWidth = 220, cardHeight = 74, columns = 3 })
assert(mid.columns == 2, "a narrow page drops to two cards, got " .. tostring(mid.columns))
assert(mid.cells[3].y == 84, "the third card wraps below, got " .. tostring(mid.cells[3].y))

local one = L.cardGrid(4, 300, { gap = 10, minWidth = 220, cardHeight = 74, columns = 3 })
assert(one.columns == 1, "a page too narrow for two cards stacks them, got "
    .. tostring(one.columns))
assert(one.cellWidth == 300, "one card uses the whole page")
assert(one.cells[2].y == 84, "stacked cards do not share a row")

local none = L.cardGrid(0, 844, { gap = 10, minWidth = 220, cardHeight = 74, columns = 3 })
assert(#none.cells == 0 and none.height == 0, "no cards reserve no height")

local parts = L.cardParts({ width = 245, height = 74 })
assert(parts.bar.width == 233, "the bar spans the card inside its padding, got "
    .. tostring(parts.bar.width))
assert(parts.bar.y == 40, "the bar sits above the steppers, got " .. tostring(parts.bar.y))
assert(parts.plus.x == 217, "the plus stepper is inside the right edge, got "
    .. tostring(parts.plus.x))
assert(parts.minus.x == 191, "the minus stepper sits left of it, got "
    .. tostring(parts.minus.x))
assert(parts.minus.x + parts.minus.width <= parts.plus.x,
    "the two steppers do not overlap")
assert(parts.bar.y + parts.bar.height <= parts.minus.y,
    "the bar does not cover the steppers")

-- The item minimum row keeps its steppers inside the row and its label readable.
local row = L.itemTargetParts(240, 26)
assert(row.plus.x + row.plus.width == 232, "the plus stepper sits inside the right padding, got "
    .. tostring(row.plus.x + row.plus.width))
assert(row.minus.x + row.minus.width + 4 == row.plus.x, "the steppers keep one gap")
assert(row.label.width >= 70, "the item label keeps a readable width, got " .. tostring(row.label.width))
assert(row.count.width >= 72, "the count column holds on-hand against the minimum")
assert(row.count.x > row.label.x + row.label.width, "the count starts after the label")
assert(row.count.x + row.count.width <= row.minus.x, "the count never runs under a stepper")
local narrow = L.itemTargetParts(160, 26)
assert(narrow.count.width == 0, "a narrow row drops the count instead of overlapping")
assert(narrow.label.width > 0 and narrow.label.x + narrow.label.width <= narrow.minus.x,
    "the narrow row gives the label the space")
