-- A clock range the player reads has to survive the game's bitmap font. The en
-- dash this text used to carry has no glyph there, so "4am-8am" was drawn as
-- "4am8am"; every block is checked for a plain-ASCII separator.
local Catalog = assert(rawget(_G, "KnoxOrderCatalog"), "order catalogue is loaded")

assert(type(Catalog.scheduleBlocks) == "table" and #Catalog.scheduleBlocks > 0,
    "the schedule blocks exist")

local seen = 0
for _, block in ipairs(Catalog.scheduleBlocks) do
    local hours = Catalog.scheduleBlockHours(block)
    assert(type(hours) == "string" and hours ~= "",
        "block " .. tostring(block.key) .. " has a range")
    assert(hours:match("^%d+[ap]m%-%d+[ap]m$") ~= nil,
        "range is two labelled hours joined by a hyphen, got " .. hours)
    -- 0x20..0x7E: printable ASCII only. A non-ASCII separator renders as
    -- nothing in game, which is exactly the reported defect.
    assert(hours:find("[^\32-\126]") == nil,
        "range " .. hours .. " contains a non-ASCII character")
    local label = Catalog.scheduleBlockLabel(block)
    assert(type(label) == "string" and label:find(hours, 1, true) ~= nil,
        "the block label carries its range, got " .. tostring(label))
    seen = seen + 1
end
assert(seen == #Catalog.scheduleBlocks, "every block was checked")

-- The four-hour windows themselves are unchanged; only the join is.
assert(Catalog.scheduleBlockHours({ startHour = 4 }) == "4am-8am",
    "the dawn block reads 4am-8am, got "
        .. tostring(Catalog.scheduleBlockHours({ startHour = 4 })))
assert(Catalog.scheduleBlockHours({ startHour = 20 }) == "8pm-12am",
    "a block ending at midnight reads 12am, got "
        .. tostring(Catalog.scheduleBlockHours({ startHour = 20 })))
assert(Catalog.scheduleBlockHours({ startHour = 0 }) == "12am-4am",
    "midnight reads 12am, not 0am")
assert(Catalog.scheduleBlockHours({ startHour = 12 }) == "12pm-4pm",
    "noon reads 12pm, not 0pm")
assert(Catalog.scheduleBlockHours({}) == nil, "a block with no hour has no range")
assert(Catalog.scheduleBlockHours(nil) == nil, "a missing block has no range")

print("Schedule hour range PASS ascii=true hyphen=true midnight=12am noon=12pm")
