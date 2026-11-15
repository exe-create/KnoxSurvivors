-- A roster written by an older build must still read, and a new one must carry
-- the face, the skills and the per-person faction. One format, one reader.
local Creator = assert(rawget(_G, "KnoxCreator"), "creator model missing")

-- Guns are real items, not labels: a weapon entry without a fullType cannot be
-- worn, and a gun entry without one would silently become "no weapon".
local pistols, longGuns = 0, 0
for _, entry in ipairs(Creator.WEAPONS) do
    if entry.id == "pistol" then
        pistols = pistols + 1
        assert(entry.fullType == "Base.Pistol", "the pistol is the real item, got "
            .. tostring(entry.fullType))
    end
    if entry.id == "shotgun" or entry.id == "rifle" then
        longGuns = longGuns + 1
        assert(type(entry.fullType) == "string" and #entry.fullType > 6,
            "a firearm carries a real fullType, got " .. tostring(entry.fullType))
    end
end
assert(pistols == 1, "exactly one pistol entry")
assert(longGuns == 2, "both long guns are listed, got " .. tostring(longGuns))

-- Skill levels are bounded integers, and the codec only carries non-zero ones.
local skills = {}
assert(Creator.skillLevel(skills, "Aiming") == 0, "an unknown level reads as zero")
Creator.cycleSkill(skills, "Aiming")
assert(Creator.skillLevel(skills, "Aiming") == 1, "one step raises the level")
for _ = 1, 12 do Creator.cycleSkill(skills, "Aiming") end
assert(Creator.skillLevel(skills, "Aiming") <= Creator.MAX_SKILL,
    "a level never passes the cap")
assert(Creator.encodeSkills({ Aiming = 3, Cooking = 2 }) == "Aiming=3;Cooking=2",
    "skills encode in catalogue order, got " .. Creator.encodeSkills({ Aiming = 3, Cooking = 2 }))
local decodedSkills = Creator.decodeSkills("Aiming=3;Bogus=99")
assert(decodedSkills.Aiming == 3, "a known skill survives the read")
assert(decodedSkills.Bogus == nil, "an unknown skill is not invented")

-- A full round trip keeps the appearance a player picked.
local roster = { { name = "Nora", look = "police", kit = "police",
    weapon = "Base.Pistol", weaponId = "pistol", profession = "base:policeofficer",
    pack = "medical", spawned = false, female = true, hair = "Messy",
    beard = "", hairColour = "red", skills = { Aiming = 4, FirstAid = 1 },
    faction = "police" } }
local text = Creator.encode(roster, { name = "Millers", faction = 2 })
local readRoster, group = Creator.decode(text)
assert(#readRoster == 1, "one person reads back, got " .. tostring(#readRoster))
local person = readRoster[1]
assert(person.hair == "Messy", "hair survives, got " .. tostring(person.hair))
assert(person.beard == "", "an empty beard stays empty, got " .. tostring(person.beard))
assert(person.hairColour == "red", "hair colour survives, got " .. tostring(person.hairColour))
assert(person.female == true, "sex survives")
assert(person.skills.Aiming == 4 and person.skills.FirstAid == 1,
    "skills survive the file")
assert(person.weapon == "Base.Pistol", "the firearm survives the file")
assert(group.name == "Millers", "the group name survives")

-- A format-1 line has no appearance fields; it must still yield the person.
local legacy = "knox-creator 1\ngroup|Old Crew\nfaction|household\n"
    .. "p|Ben|casual|none|bat|base:carpenter|meal|1\n"
local oldRoster, oldGroup, skipped = Creator.decode(legacy)
assert(#oldRoster == 1 and skipped == 0, "a format-1 person is not lost")
assert(oldRoster[1].name == "Ben", "an old name is read")
assert(oldRoster[1].hair == "" and oldRoster[1].beard == "",
    "an old record has no invented hair")
assert(oldRoster[1].hairColour == "brown", "an old record gets the default colour")
-- The harness has no next(), so the emptiness is counted rather than asserted
-- through a helper it does not provide.
local legacySkillCount = 0
for _ in pairs(oldRoster[1].skills or {}) do legacySkillCount = legacySkillCount + 1 end
assert(legacySkillCount == 0, "an old record has no invented skills")
assert(oldGroup.name == "Old Crew", "an old group name is read")

-- Roster edits keep indexes honest instead of silently doing nothing.
local edits = { { name = "Ann" }, { name = "Ben" }, { name = "Cara" } }
assert(Creator.setFactionAt(edits, 2, "police") == true, "a person joins a faction")
assert(edits[2].faction == "police", "the faction is stored on the person")
assert(Creator.setFactionAt(edits, 2, "no_such_faction") == false,
    "an unknown faction is refused")
assert(Creator.setFactionAt(edits, 9, "police") == false, "a missing person is refused")
local removedOk, removed = Creator.removeAt(edits, 2)
assert(removedOk == true and removed.name == "Ben", "the named person is removed")
assert(#edits == 2 and edits[2].name == "Cara", "the roster closes the gap")
assert(Creator.removeAt(edits, 7) == false, "removing nobody is refused")
assert(Creator.resetRoster(edits) == true and #edits == 0, "reset empties the roster")

-- The People page's per-person faction is a choice the player made, so the
-- file has to carry it; without the field the assignment looked saved and the
-- next read quietly reverted the person to the group's faction.
assert(readRoster[1].faction == "police",
    "a per-person faction survives the file, got " .. tostring(readRoster[1].faction))
-- A hand-edited file names a faction that does not exist: it must not become
-- membership, because faction membership decides who is allied at a raid.
local handEdited = Creator.decode([[knox-creator 2
group|X
faction|household
p|Cy|casual|none|bat|base:carpenter|meal|0|0|||||nonsense]])
assert(#handEdited == 1, "the hand-edited line still yields one person")
assert(handEdited[1].faction == "nonsense", "an unknown faction id is preserved as data")
assert(Creator.profileFor(handEdited[1].faction, {}) == nil,
    "preserving a future id cannot invent a usable faction profile")
-- Per-slot clothing: one item replaces the preset's item in that slot, the
-- rest of the preset is kept, and nothing else can be named.
local base = Creator.lookItems("police")
assert(#base == 4, "the police preset includes shoes and is four items, got " .. tostring(#base))
assert(Creator.encodeSlots({}) == "", "no choices encode as an empty field")
local chosen = Creator.decodeSlots(Creator.encodeSlots(
    { legs = "Base.Trousers_Denim", head = "Base.Hat_Army" }))
assert(chosen.legs == "Base.Trousers_Denim" and chosen.head == "Base.Hat_Army",
    "slot choices survive the file")
local merged = Creator.lookItemsWithSlots("police", chosen)
assert(#merged == 4, "a swap keeps the item count, got " .. tostring(#merged))
local function has(list, value)
    for _, entry in ipairs(list) do if entry == value then return true end end
    return false
end
assert(has(merged, "Base.Trousers_Denim"), "the chosen trousers are worn")
assert(not has(merged, "Base.Trousers_Police"),
    "the preset trousers are not worn as well")
assert(has(merged, "Base.Shirt_PoliceBlue"), "an untouched slot keeps the preset")

-- A file naming an item that slot never offered is ignored, not worn.
local invented = Creator.decodeSlots("legs:Base.Trousers_Nonexistent;head:Base.Trousers_Denim")
assert(invented.legs == "Base.Trousers_Nonexistent", "missing items stay saved for when their mod returns")
assert(Creator.slotChoice("legs", invented) == nil, "a missing item is not applied")
assert(Creator.slotChoice("head", invented) == nil, "an item from another slot is not worn")

-- The reading the appearance owner uses takes the saved record shape.
local fromRecord = Creator.lookItemsFromRecord({ look = "police",
    slots = "legs:Base.Trousers_Denim" })
assert(has(fromRecord, "Base.Trousers_Denim"), "the record path applies the slot")
assert(#fromRecord == 4, "the record path keeps the preset's other items")
assert(#Creator.lookItemsFromRecord(nil) == 0, "a missing record dresses nothing")
assert(#Creator.lookItemsFromRecord({ look = "police" }) == 4,
    "a record without slots is the plain preset")

-- The hand-over built at spawn carries every choice the card showed. This is
-- the seam where hair, skills and slot clothing were silently lost: the spawn
-- site listed its own fields and never passed them.
local handover = Creator.recordFor({
    name = "Nora", look = "police", kit = "police", weapon = "Base.Pistol",
    pack = "medical", female = true, hair = "Messy", beard = "",
    hairColour = "red", skills = { Aiming = 3 },
    slots = { legs = "Base.Trousers_Denim" },
}, { name = "Millers", faction = 2 })
assert(handover ~= nil, "a real person yields a hand-over")
assert(handover.hair == "Messy", "the hand-over carries the hair")
assert(handover.beard == "", "the hand-over carries an empty beard")
assert(handover.hairColour == "red", "the hand-over carries the hair colour")
assert(handover.female == true, "the hand-over carries the sex")
assert(handover.skills == "Aiming=3",
    "the hand-over encodes the skills, got " .. tostring(handover.skills))
assert(handover.slots == "legs:Base.Trousers_Denim",
    "the hand-over encodes the slot choice, got " .. tostring(handover.slots))
assert(handover.faction == "police", "the hand-over names the group's faction")
assert(handover.groupName == "Millers", "the hand-over names the group")
assert(handover.weapon == "Base.Pistol", "the hand-over carries the weapon")
assert(Creator.recordFor(nil, nil) == nil, "a missing person has no hand-over")
local bare = Creator.recordFor({ name = "Cy" }, nil)
assert(bare.skills == "" and bare.slots == "" and bare.female == false,
    "a person with no choices hands over empty fields, not nil strings")

print("creator_appearance: format=2 legacy=read guns=3 skills=bounded edits=refused")
