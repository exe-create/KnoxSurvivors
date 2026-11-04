-- The held-weapon word is a pure projection over the item's display name and
-- broken flag. This fixture does not read an inventory or prove the card draws
-- the row; it proves the suffix and the cases that must stay empty.
local word = assert(codecWeaponWord, "weapon word source is loaded")
local condition = assert(codecWeaponCondition, "weapon condition source is loaded")

-- Three quarters is still sound; the two worn bands each add one word.
assert(condition(100, 100) == nil, "a full weapon spends no condition word")
assert(condition(75, 100) == nil, "three quarters is still sound")
assert(condition(74, 100) == "Worn", "below three quarters is worn")
assert(condition(40, 100) == "Worn", "two fifths is still the worn band")
assert(condition(39, 100) == "Fragile", "below two fifths is fragile")
assert(condition(1, 100) == "Fragile", "one point left is fragile")
assert(condition(0, 100) == nil, "a zero condition is left to the broken flag")
assert(condition(nil, 100) == nil, "a missing condition stays silent")
assert(condition(10, 0) == nil, "a zero maximum cannot divide by zero")
assert(condition(10, nil) == nil, "a missing maximum stays silent")

assert(word("Fire Axe", false) == "Fire Axe", "a healthy weapon keeps its name")
assert(word("Fire Axe", false, "Worn") == "Fire Axe - Worn",
    "a worn weapon adds one word")
assert(word("Fire Axe", false, "Fragile") == "Fire Axe - Fragile",
    "a fragile weapon adds one word")
assert(word("Fire Axe", true, "Worn") == "Fire Axe (broken)",
    "the broken flag outranks a stale condition word")
assert(word("Fire Axe", false, "Broken") == "Fire Axe",
    "only the two worn bands are appended")
assert(word("Fire Axe", true) == "Fire Axe (broken)",
    "a broken weapon says so")
assert(word("  Fire   Axe  ", false) == "Fire Axe",
    "the name is trimmed and its spacing collapsed")
assert(word("Baseball Bat", false) == "Baseball Bat",
    "a clean name is not rewritten")
assert(word(nil, false) == nil, "a missing name stays empty")
assert(word("", false) == nil, "an empty name stays empty")
assert(word("   ", false) == nil, "whitespace is not a weapon name")
assert(word("Knife", 1) == "Knife", "only a real broken flag adds the suffix")
assert(word("Knife", "true") == "Knife", "a string flag is not a boolean")

print("WeaponWord PASS healthy=true broken=true worn=true fragile=true trim=true empty=true flag=true")
