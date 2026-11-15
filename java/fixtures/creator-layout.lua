-- The window's geometry is arithmetic, so it can be checked without a screen.
-- The grid wraps by width, clamps its scroll, and never returns two cards on the
-- same pixels or a card past the area it was given.
local Creator = assert(rawget(_G, "KnoxCreator"), "the creator model is loaded")

local function overlaps(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width
        and a.y < b.y + b.height and b.y < a.y + a.height
end

-- Empty roster: no cards, nothing to scroll.
local empty = Creator.cardGrid(0, 10, 20, 660, 500, 0)
assert(#empty.cards == 0, "no people, no cards")
assert(empty.maxScroll == 0 and empty.scroll == 0, "nothing to scroll")

-- Eight people in a 660 wide area: three columns, three rows, scrollable.
local grid = Creator.cardGrid(8, 10, 20, 660, 500, 0)
assert(grid.columns == 3, "three columns at 660: " .. tostring(grid.columns))
assert(#grid.cards == 8, "every person gets a card")
assert(grid.contentHeight == 650, "three rows of 210 with gaps: " .. tostring(grid.contentHeight))
assert(grid.maxScroll == 150, "the content is taller than the area: " .. tostring(grid.maxScroll))
assert(grid.cards[1].x == 10 and grid.cards[1].y == 20, "the first card starts at the origin")
for _, card in ipairs(grid.cards) do
    assert(card.width == Creator.CARD_WIDTH and card.height == Creator.CARD_HEIGHT,
        "every card has the card's size")
    assert(card.x >= 10 and card.x + card.width <= 10 + 660,
        "a card stays inside the area's width")
end
for i = 1, #grid.cards do
    for j = i + 1, #grid.cards do
        assert(not overlaps(grid.cards[i], grid.cards[j]),
            "cards never overlap: " .. tostring(i) .. "/" .. tostring(j))
    end
end

-- Narrow and tiny areas degrade to fewer columns, never to zero.
assert(Creator.cardGrid(4, 0, 0, 400, 400, 0).columns == 2, "two columns at 400")
assert(Creator.cardGrid(4, 0, 0, 200, 400, 0).columns == 1, "one column at 200")
assert(Creator.cardGrid(4, 0, 0, 10, 400, 0).columns == 1, "never zero columns")

-- Scroll is clamped at both ends, and the clamp is what the rows are placed by.
local bottom = Creator.cardGrid(8, 0, 0, 660, 500, 9999)
assert(bottom.scroll == 150, "a big scroll clamps to the end: " .. tostring(bottom.scroll))
assert(bottom.cards[#bottom.cards].y + bottom.cards[#bottom.cards].height == 650 - 150,
    "the last card sits at the clamped offset")
local top = Creator.cardGrid(8, 0, 0, 660, 500, -50)
assert(top.scroll == 0, "a negative scroll clamps to the top")

-- The sidebar: one row per faction and per person, with the two fixed ends.
local group = Creator.newGroup()
local roster = {}
local function make(name, factionId)
    local draft = Creator.draftForFaction(factionId, {})
    draft.name = name
    draft.faction = factionId
    Creator.add(roster, draft)
end
make("Bex", "police")
make("Cal", "military")
make("Ada", "police")
local rows = Creator.railRows(roster, group, {}, nil)
assert(rows[1].kind == "all" and rows[1].count == 3, "the all row counts everybody")
assert(rows[#rows].kind == "new", "the new row is last")
local headers = 0
for _, row in ipairs(rows) do
    if row.kind == "faction" then headers = headers + 1 end
end
assert(headers == #Creator.defaultEntries(), "one header per authoring default")

print("creator_layout ok")
