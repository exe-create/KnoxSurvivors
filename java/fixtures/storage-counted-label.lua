-- The filter list speaks in counts: "Weapons (4/4)" is the row a player reads.
-- One function owns that wording, so the screen and the rule cannot disagree.
local Storage = assert(rawget(_G, "KnoxBaseStorage"), "storage owner missing")
assert(type(Storage.countedLabel) == "function", "countedLabel missing")

local function eq(actual, expected, what)
    assert(actual == expected, what .. ", got " .. tostring(actual))
end

eq(Storage.countedLabel("Weapons", 4, 4), "Weapons (4/4)", "a full group reads four of four")
eq(Storage.countedLabel("Trade goods", 0, 1), "Trade goods (0/1)",
    "a group that is off accepts none of the one item it holds")
eq(Storage.countedLabel("Food", 3, 5), "Food (3/5)", "a partial count keeps both numbers")
eq(Storage.countedLabel("Food"), "Food", "no count prints no numbers")
eq(Storage.countedLabel("Food", 3), "Food", "a count without a total stays plain")
eq(Storage.countedLabel("Food", 9, 3), "Food (3/3)", "accepted never exceeds what is present")
eq(Storage.countedLabel("Food", -2, 3), "Food (0/3)", "a negative count floors at zero")
eq(Storage.countedLabel("Food", "2", "5"), "Food (2/5)", "numeric strings still count")
eq(Storage.countedLabel("Food", 2, 2.7), "Food (2/2)", "a fractional total floors")
eq(Storage.countedLabel("Food", 0, 0), "Food (0/0)", "an empty container still reads")
eq(Storage.countedLabel("", 0, 0), "", "no label, no row text")
eq(Storage.countedLabel(nil, 0, 0), "", "nil label, no row text")

print("storage_counted_label: 4/4 0/1 3/5 clamp=present floor=zero")
