-- The faction catalogue is code plus the player's own file. What matters: an id
-- identifies a faction across updates, a default can be added without moving
-- anybody, a built-in cannot be deleted, and a record written by a newer version
-- is kept rather than dropped.
local Creator = assert(rawget(_G, "KnoxCreator"), "the creator model is loaded")

local function indexOf(list, id)
    for index, entry in ipairs(list) do
        if entry.id == id then return index end
    end
    return nil
end

-- The catalogue is *kinds*, not factions. It used to carry four named families
-- (Barley/Voss/Turner/Mercer), which made a kind and an instance the same thing,
-- so a second household could not exist and every new group became a household.
assert(#Creator.FACTIONS == 10, "ten kinds including custom: " .. tostring(#Creator.FACTIONS))
local seen = {}
for _, faction in ipairs(Creator.FACTIONS) do
    assert(not seen[faction.id], "kind id is unique: " .. faction.id)
    seen[faction.id] = true
    assert(type(faction.label) == "string" and #faction.label >= 3,
        "kind has a label: " .. tostring(faction.id))
    assert(type(faction.note) == "string" and #faction.note >= 8,
        "kind says what it does: " .. tostring(faction.id))
    assert(indexOf(Creator.LOOKS, Creator.resolveLook(faction.look)) ~= nil,
        "look exists: " .. faction.id)
    assert(indexOf(Creator.KITS, faction.kit) ~= nil, "kit exists: " .. faction.id)
    assert(indexOf(Creator.WEAPONS, faction.weapon) ~= nil, "weapon exists: " .. faction.id)
    assert(indexOf(Creator.PACKS, faction.pack) ~= nil, "pack exists: " .. faction.id)
end
assert(seen["fire_service"], "fire service is a kind")
assert(seen["police"] and seen["military"] and seen["looters"] and seen["robbers"],
    "the request's group kinds exist")
for _, instanceId in ipairs({ "barley", "voss", "turner", "mercer" }) do
    assert(seen[instanceId] == nil, "a named family is not a shipped kind: " .. instanceId)
end
assert(seen["solo"], "solo still resolves so an older save keeps its people")
-- Solo names a person who belongs to nothing: it is never offered as a group.
for _, kind in ipairs(Creator.groupKinds()) do
    assert(kind.id ~= "solo", "solo is not a group kind")
end
assert(#Creator.groupKinds() == 9, "nine kinds can be founded as a group")
assert(Creator.isGroupKind("household") and not Creator.isGroupKind("solo"),
    "the group test separates a kind from a solo person")

-- Defaults first, a player's own after them, and nothing is merged into the
-- default table itself.
local defs = {}
local ok, added = Creator.addFaction(defs, "Riverside Runners")
assert(ok == true, "a user faction is added")
assert(added.id == "user_riverside_runners", "user id is prefixed: " .. tostring(added.id))
assert(#Creator.FACTIONS == 10, "the expanded default table is untouched")
local merged = Creator.allFactions(defs)
assert(#merged == #Creator.defaultEntries() + 1, "merged list has authoring defaults and the user group")
assert(merged[1].id == Creator.FACTIONS[1].id, "defaults come first")
assert(merged[#merged].id == added.id, "user factions follow in file order")

-- Names: too short, duplicate, and case-insensitive duplicate are refused.
assert(Creator.addFaction(defs, "x") == false, "a one-letter name is refused")
assert(Creator.addFaction(defs, "riverside runners") == false, "a duplicate name is refused")
assert(Creator.addFaction(defs, "Police") == false, "a default's name cannot be taken")

-- Collision handling for a generated id.
local same = { { id = "user_riverside_runners", label = "Other" } }
assert(Creator.newFactionId("Riverside Runners", same) == "user_riverside_runners_2",
    "a taken id gets a suffix")

-- Rename and delete rules.
assert(Creator.renameFaction(defs, "police", "Sheriff") == false,
    "a built-in keeps its name")
assert(Creator.renameFaction(defs, added.id, "River Runners") == true, "a user faction renames")
assert(Creator.renameFaction(defs, added.id, "Military") == false,
    "a rename cannot collide with a default")
assert(Creator.deleteFaction(defs, "police", {}, {}) == false,
    "a built-in cannot be deleted")

-- People and counts, sorted by name regardless of case.
local group = Creator.newGroup()
group.factionId = "police"
local roster = {}
local function make(name, factionId)
    local draft = Creator.draftForFaction(factionId, defs)
    draft.name = name
    draft.faction = factionId
    assert(Creator.add(roster, draft) == true, "person added: " .. name)
end
make("zoe", "police")
make("Abe", "police")
make("Mia", added.id)
local police = Creator.peopleByFaction(roster, group, "police")
assert(#police == 2, "police holds two")
assert(police[1].person.name == "Abe", "names sort case-insensitively")
assert(police[2].person.name == "zoe", "second name follows")
local counts = Creator.factionCounts(roster, group, defs)
assert(counts.police == 2 and counts[added.id] == 1, "counts match the roster")
assert(counts.military == 0, "an empty faction counts zero")

-- The sidebar: all row, every faction header with its people indented, new row.
local rows = Creator.railRows(roster, group, defs, "police")
assert(rows[1].kind == "all" and rows[1].count == 3, "the all row carries the total")
assert(rows[#rows].kind == "new", "the new-faction row is last")
local personRows, factionRows = 0, 0
for index, row in ipairs(rows) do
    if row.kind == "faction" then
        factionRows = factionRows + 1
        assert(row.count ~= nil, "a header carries its count")
        if row.id == "police" then
            assert(rows[index + 1].kind == "person" and rows[index + 1].indent == true,
                "a faction header is followed by its people")
            assert(rows[index + 1].label == "Abe", "people are name-sorted under the header")
        end
    elseif row.kind == "person" then
        personRows = personRows + 1
        assert(row.index ~= nil, "a person row addresses the roster")
    end
end
assert(factionRows == #Creator.defaultEntries() + 1, "every authoring default and custom group has a header: " .. tostring(factionRows))
assert(personRows == 3, "every person has a row: " .. tostring(personRows))

-- Deleting a faction that still holds people is refused.
assert(Creator.deleteFaction(defs, added.id, roster, group) == false,
    "a faction with people cannot be deleted")
local emptyDefs = {}
local okEmpty, emptyEntry = Creator.addFaction(emptyDefs, "Empty Crew")
assert(okEmpty == true, "second user faction added")
assert(Creator.deleteFaction(emptyDefs, emptyEntry.id, roster, group) == true,
    "an empty user faction is deleted")

-- Format 3 round trip: group faction, user definitions and people survive.
group.defs = defs
group.name = "River Team"
local text = Creator.encode(roster, group)
local read, readGroup, skipped = Creator.decode(text)
assert(#read == 3, "all three people read back")
assert(skipped == 0, "nothing was skipped")
assert(readGroup.name == "River Team", "the group name survives")
assert(readGroup.factionId == "police", "the group faction is an id")
assert(#readGroup.defs == 1, "user definitions survive: " .. tostring(#readGroup.defs))
assert(#readGroup.extras == 0, "a format-3 file has no unknown lines")
local mia = nil
for _, person in ipairs(read) do
    if person.name == "Mia" then mia = person end
end
assert(mia ~= nil and mia.faction == added.id, "a person's faction is its id")

-- Format 2 still reads, and its numeric group faction maps to the same id even
-- when a default is added later: this is the defect the format removes.
local legacyRoster, legacyGroup = Creator.decode("knox-creator 2\ngroup|Old Crew\nfaction|2\n" ..
    "p|Old Sam|casual|none|none|base:unemployed|meal|0|0|||brown||\n")
assert(#legacyRoster == 1, "a format-2 person reads")
assert(legacyGroup.factionId == "police", "a format-2 index resolves to its id")
assert(legacyGroup.factionId == Creator.FACTIONS[2].id, "the id is the one at that index")

-- An id from a missing/future definition stays saved instead of being reassigned.
local unknownRoster, unknownGroup = Creator.decode(
    "knox-creator 3\ngroup|Gone\ngroupfaction|no_such_faction\n")
assert(unknownGroup.factionId == "no_such_faction",
    "an unknown faction id survives without silently becoming another group")

-- A line a newer version wrote is preserved in the encode that follows.
local futureRoster, futureGroup = Creator.decode(
    "knox-creator 5\ngroup|Ahead\ngroupfaction|police\nfeature|new|line\n")
assert(#futureGroup.extras == 1, "an unknown line is kept")
assert(futureGroup.factionId == "police", "the known lines still read")
local forward = Creator.encode(futureRoster, futureGroup)
assert(string.find(forward, "feature|new|line", 1, true) ~= nil,
    "an unknown line is written back unchanged")

-- A record carries the person's faction, else the group's.
local record = Creator.recordFor(roster[1], group)
assert(record.faction == "police", "the record carries the faction id")
local loose = { name = "No Faction", look = "casual", kit = "none", pack = "meal", slots = {} }
assert(Creator.recordFor(loose, group).faction == "police",
    "a person without a choice uses the group's faction")

-- The defect this pass repairs: a kind is not an instance. Two households, each
-- its own group, both with they own people and settings.
local homes = {}
local okHomeA, homeA = Creator.addFaction(homes, "Barley", "household")
local okHomeB, homeB = Creator.addFaction(homes, "Voss", "household")
assert(okHomeA and okHomeB, "two households can be founded")
assert(homeA.id ~= homeB.id, "each household is its own group")
assert(homeA.profile == "household" and homeB.profile == "household",
    "both groups are the household kind")
assert(homeA.id == "user_barley" and homeB.id == "user_voss", "ids are per instance")
assert(Creator.addFaction(homes, "Lone Wolves", "solo") == false,
    "solo is not a kind you can found a group from")
assert(Creator.addFaction(homes, "Nameless", "no_such_kind") == false,
    "an invented kind is refused")
local okRobbers, gang = Creator.addFaction(homes, "Road Robbers", "robbers")
assert(okRobbers and gang.profile == "robbers", "a robber gang is its own group kind")
assert(Creator.profileFor(gang.id, homes).attitude == "hostile",
    "a robber group starts hostile because its kind does")
assert(Creator.profileFor(homeA.id, homes).settlementPolicy == "home",
    "a household settles its home")
local blankDefs,blankRoster={},{}
local blankOk,blank=Creator.addFaction(blankDefs,"My Custom Crew","custom")
assert(blankOk and blank.profile=="custom" and blank.pack=="none" and blank.kit=="none",
    "blank custom group has its own purpose and no inherited supply kit")
local blankPolicy=Creator.profileFor(blank.id,blankDefs)
assert(blankPolicy.attitude=="neutral" and blankPolicy.settlementPolicy=="mobile",
    "custom group begins neutral and without a forced household home")
local blankGroup=Creator.newGroup();blankGroup.defs=blankDefs
Creator.populateFaction(blankRoster,blankGroup,blank.id,1)
assert(#blankRoster==1 and Creator.recordFor(blankRoster[1],blankGroup).profile=="custom",
    "custom purpose reaches the actual survivor record")
local decodedRoster,decodedGroup=Creator.decode(Creator.encode(blankRoster,blankGroup))
assert(decodedGroup.defs[1].profile=="custom" and #decodedRoster==1,
    "custom group survives the existing creator codec")
local examples={}
for i,id in ipairs({"template_solo_civilian","template_solo_worker","template_solo_scavenger"}) do
    assert(Creator.addSoloTemplate(examples,({"Maya Cole","Owen Brooks","Iris Reed"})[i],id))
end
assert(#examples==3 and examples[2].look=="work" and examples[2].faction=="solo",
    "independent examples provide distinct editable builds without shared group membership")
local fireLook=Creator.LOOKS[Creator.indexOf(Creator.LOOKS,"firefighter")]
assert(fireLook.items[1]=="Base.Hat_Fireman" and fireLook.items[2]=="Base.Jacket_Fireman"
    and Creator.profileFor("fire_service").look=="firefighter", "fire service uses installed turnout gear")

print("creator_factions ok")
