-- PT-40. The creator's roster is player-facing text that becomes real people, so
-- the model has to be boringly predictable: a bounded list, a name that cannot
-- split a record, and a decode that keeps a person when a field is nonsense.
local Creator = rawget(_G, "KnoxCreator")
assert(Creator ~= nil, "creator model missing")
assert(#Creator.LOOKS > 0 and #Creator.WEAPONS > 0 and #Creator.PROFESSIONS > 0,
    "creator catalogues are empty")

-- cycling
local total = #Creator.LOOKS
assert(Creator.cycle(1, total, 1) == 2, "one step forward")
assert(Creator.cycle(total, total, 1) == 1, "the last entry wraps to the first")
assert(Creator.cycle(1, total, -1) == total, "one step back wraps to the last")
assert(Creator.cycle(nil, total, 1) == 2, "a missing index starts at the first entry")
assert(Creator.cycle(3, 0, 1) == 1, "an empty catalogue never divides by zero")

-- validation
local roster = {}
local ok, reason = Creator.draftValid({ name = "A" }, 0)
assert(not ok and reason == "Name is too short.", "a one-letter name is refused")
ok, reason = Creator.draftValid({ name = string.rep("a", Creator.MAX_NAME + 1) }, 0)
assert(not ok and reason == "Name is too long.", "an overlong name is refused")
ok, reason = Creator.draftValid({ name = "Ann" }, Creator.MAX_PEOPLE)
assert(not ok and reason == "The list is full.", "a full list refuses another person")

-- adding
local added
ok, added = Creator.add(roster, { name = "  Ann|Baker  ", look = 3, kit = 2, weapon = 2,
    profession = 3, pack = 2 })
assert(ok, "a normal name is accepted")
assert(added.name == "AnnBaker", "the separator is stripped from a name, got "
    .. tostring(added.name))
assert(#roster == 1, "the person is on the list")
assert(added.look == Creator.LOOKS[3].id, "the chosen look is stored")
assert(added.kit == Creator.KITS[2].id, "the chosen kit is stored")
assert(added.weapon == "Base.BaseballBat", "the chosen weapon is stored as an item")
assert(added.profession == Creator.PROFESSIONS[3].id, "the chosen profession is stored")
assert(added.pack == Creator.PACKS[2].id, "the chosen pack is stored")
assert(added.spawned == false, "a new person has not spawned yet")

-- catalogues
assert(#Creator.lookItems("military") == #Creator.LOOKS[4].items,
    "a look resolves to its real clothing list")
assert(#Creator.lookItems("nonsense") == 0, "an unknown look dresses nobody")
assert(Creator.weaponItem("bat") == "Base.BaseballBat", "a weapon resolves to its item")
assert(Creator.weaponItem("none") == nil, "no weapon carries nothing")
assert(#Creator.packItems("meal") == #Creator.PACKS[2].items,
    "a pack resolves to its real items")
assert(#Creator.packItems("nonsense") == 0, "an unknown pack carries nothing")

-- round trip
Creator.add(roster, { name = "Ben", look = 5, kit = 1, weapon = 1, profession = 2 })
roster[2].spawned = true
-- Format 3 names the group faction by id; a group handed over only as the old
-- numeric position still reads as that faction, which is the compatibility the
-- format change had to keep.
local text = Creator.encode(roster, { name = "Millers", factionId = "military" })
local back, group = Creator.decode(text)
local legacyText = Creator.encode(roster, { name = "Millers", faction = 3 })
local _, legacyGroup = Creator.decode(legacyText)
assert(#back == 2, "both people survive the round trip, got " .. tostring(#back))
assert(back[1].name == "AnnBaker" and back[2].name == "Ben", "names survive")
assert(back[1].look == Creator.LOOKS[3].id and back[2].profession == "base:policeofficer",
    "choices survive")
assert(back[2].spawned == true and back[1].spawned == false, "the spawned flag survives")
assert(back[1].pack == Creator.PACKS[2].id, "the pack survives the round trip")
assert(group.name == "Millers" and group.factionId == "military",
    "the group survives by id")
assert(legacyGroup.factionId == "military",
    "an index-only group still reads as the same faction")

-- hostile input
local weak = Creator.decode("p||casual|none|none|base:chef|0\n"
    .. "p|Cara|nonsense|none|laser|base:chef|0\n")
assert(#weak == 1, "a nameless record is dropped, got " .. tostring(#weak))
assert(weak[1].name == "Cara", "the readable person is kept")
assert(weak[1].look == Creator.LOOKS[1].id, "an unknown look falls back to the first")
assert(weak[1].weaponId == "none", "an unknown weapon falls back to none")
local many = {}
for index = 1, Creator.MAX_PEOPLE + 4 do
    many[#many + 1] = "p|P" .. tostring(index) .. "|casual|none|none|base:chef|0"
end
local capped = Creator.decode(table.concat(many, "\n"))
assert(#capped == Creator.MAX_PEOPLE, "the list is capped on read, got " .. tostring(#capped))
assert(type(Creator.decode(nil)) == "table", "a missing file decodes to an empty list")

-- an unreadable record is counted, not lost in silence
local NL = string.char(10)
local _, _, skippedMany = Creator.decode("p||casual|none|none|base:chef|0" .. NL
    .. "p|Cara|casual|none|none|base:chef|0" .. NL)
assert(skippedMany == 1, "one unreadable record is counted, got " .. tostring(skippedMany))
local _, _, skippedNone = Creator.decode("p|Ann|casual|none|none|base:chef|0" .. NL)
assert(skippedNone == 0, "a readable roster reports no loss")
local _, _, skippedNil = Creator.decode(nil)
assert(skippedNil == 0, "a missing file loses nobody")

-- one person, one name
local names = {}
assert(Creator.add(names, { name = "Ann" }), "the first Ann is accepted")
local dupOk, dupReason = Creator.add(names, { name = "Ann" })
assert(not dupOk and dupReason == "Somebody here already has that name.",
    "a duplicate name is refused, got " .. tostring(dupReason))
dupOk = Creator.add(names, { name = "ann" })
assert(not dupOk, "a duplicate is refused whatever its case")
assert(Creator.add(names, { name = "Anna" }), "a similar name is still a different person")
assert(#names == 2, "only the two real people were added, got " .. tostring(#names))

-- the summary stays one label
assert(Creator.summaryText({}) == "Nobody yet. Name one person, then add them.",
    "an empty roster explains itself")
assert(Creator.summaryText({ { name = "Ann" }, { name = "Ben" } })
    == "2 ready: Ann, Ben", "a short roster names everyone, got "
    .. Creator.summaryText({ { name = "Ann" }, { name = "Ben" } }))
local five = { { name = "A" }, { name = "B" }, { name = "C" }, { name = "D" },
    { name = "E" } }
assert(Creator.summaryText(five) == "5 ready: A, B, C and 2 more",
    "a long roster counts the rest, got " .. Creator.summaryText(five))
assert(Creator.summaryText(nil) == "Nobody yet. Name one person, then add them.",
    "a missing roster reads as empty")

-- removing the last person
local pair = { { name = "Ann" }, { name = "Ben" } }
local removedOk, removed = Creator.removeLast(pair)
assert(removedOk and #pair == 1, "the last person is removed")
assert(removed.name == "Ben", "the removed person is the last one, got "
    .. tostring(removed.name))
assert(Creator.removeLast({}) == false, "an empty list has nobody to remove")

-- the name a created group asks a faction to take
assert(Creator.requestedFactionName("  Millers  ") == "Millers",
    "a normal group name is kept")
assert(Creator.requestedFactionName("") == nil, "an empty name is not a faction name")
assert(Creator.requestedFactionName("A") == nil, "a one-letter name is refused")
assert(Creator.requestedFactionName(string.rep("m", 33)) == nil,
    "an overlong name is refused")
assert(Creator.requestedFactionName("Miller|s") == "Millers",
    "a separator is stripped before it can reach a faction")
assert(Creator.chooseFactionName("Rosewood Remnant", "Millers", false) == "Millers",
    "a free requested name replaces the generated one")
assert(Creator.chooseFactionName("Rosewood Remnant", "Millers", true)
    == "Rosewood Remnant", "a taken name keeps the generated one")
assert(Creator.chooseFactionName("Rosewood Remnant", nil, false) == "Rosewood Remnant",
    "no request keeps the generated name")
assert(Creator.chooseFactionName("Rosewood Remnant", "", false) == "Rosewood Remnant",
    "an empty request keeps the generated name")
assert(Creator.requestedFactionName("Miller_s") == nil,
    "an internal-looking code is not a faction name")
print("creator_roster: " .. tostring(#back) .. " people, group " .. group.name)
