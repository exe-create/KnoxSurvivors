-- Seven slots, each with one kind. A shirt is only ever offered for the torso,
-- a bag only for the back, and the two weapon slots carry real item ids. The card
-- and the spawn hand-over read the same tables, so the fixture reads them too.
local Creator = assert(rawget(_G, "KnoxCreator"), "the creator model is loaded")

local IDS = { "head", "torso", "legs", "feet", "backpack", "primary", "secondary" }
local KINDS = { head = "clothing", torso = "clothing", legs = "clothing",
    feet = "clothing", backpack = "bag", primary = "weapon", secondary = "weapon" }

assert(#Creator.SLOTS == 7, "seven slots: " .. tostring(#Creator.SLOTS))
for _, slot in ipairs(Creator.SLOTS) do
    assert(KINDS[slot.id] ~= nil, "known slot id: " .. tostring(slot.id))
    assert(slot.kind == KINDS[slot.id], "kind is as stated: " .. slot.id)
    assert(type(slot.label) == "string" and #slot.label > 0, "slot has a label: " .. slot.id)
    for _, option in ipairs(slot.options) do
        assert(string.find(string.lower(option.fullType), "^base%.") ~= nil,
            "a preset names a base item: " .. tostring(option.fullType))
    end
end

-- Every clothing slot has a catalogue, and a torso choice is never a legs item.
for _, slotId in ipairs({ "head", "torso", "legs", "feet" }) do
    local catalogue = Creator.slotCatalogue(slotId)
    assert(#catalogue > 0, "clothing catalogue is not empty: " .. slotId)
end
for _, option in ipairs(Creator.slotCatalogue("torso")) do
    local lower = string.lower(option.fullType)
    assert(string.find(lower, "trousers", 1, true) == nil, "no trousers in the torso list")
    assert(string.find(lower, "shoes", 1, true) == nil, "no shoes in the torso list")
end
for _, option in ipairs(Creator.slotCatalogue("legs")) do
    local lower = string.lower(option.fullType)
    assert(string.find(lower, "shirt", 1, true) == nil, "no shirt in the legs list")
end

-- Bags and weapons: a bag slot offers containers, a weapon slot offers items the
-- weapon catalogue names, and the "no weapon" preset is not an item.
local bags = Creator.slotCatalogue("backpack")
assert(#bags > 0, "bag catalogue is not empty")
for _, option in ipairs(bags) do
    local lower = string.lower(option.fullType)
    assert(string.find(lower, "bag", 1, true) ~= nil, "a bag entry names a bag")
end
for _, slotId in ipairs({ "primary", "secondary" }) do
    local catalogue = Creator.slotCatalogue(slotId)
    assert(#catalogue > 0, "weapon catalogue is not empty: " .. slotId)
    for _, option in ipairs(catalogue) do
        assert(type(option.fullType) == "string" and option.fullType ~= "",
            "a weapon slot only offers real items: " .. slotId)
    end
end

-- A full set of choices survives the roster's own encoding, and a choice that is
-- not in that slot's catalogue is dropped rather than written.
local slots = {
    head = "Base.Hat_Police",
    torso = "Base.Shirt_Workman",
    legs = "Base.Trousers_Denim",
    backpack = "Base.Bag_Schoolbag",
    primary = "Base.Crowbar",
    secondary = "Base.BaseballBat",
}
local encoded = Creator.encodeSlots(slots)
local decoded = Creator.decodeSlots(encoded)
for slotId, fullType in pairs(slots) do
    assert(decoded[slotId] == fullType, "slot survives the round trip: " .. slotId)
end
assert(decoded.primary == "Base.Crowbar" and decoded.secondary == "Base.BaseballBat",
    "both carried weapons are written")
assert(Creator.decodeSlots("torso:Base.NotAThing")["torso"] == nil,
    "an item the catalogue does not offer is dropped")
assert(Creator.decodeSlots("wing:Base.Hat_Police")["wing"] == nil,
    "an unknown slot is dropped")

-- The outfit merge swaps clothing only. A bag is worn by its own call and a
-- weapon is carried, so neither may be handed to the dressing path.
local look = Creator.lookItemsWithSlots("police", slots)
local sawBag, sawWeapon = false, false
for _, fullType in ipairs(look) do
    if fullType == "Base.Bag_Schoolbag" then sawBag = true end
    if fullType == "Base.Crowbar" then sawWeapon = true end
end
assert(not sawBag, "a bag is not in the outfit list")
assert(not sawWeapon, "a weapon is not in the outfit list")
local shirts, trousers = 0, 0
for _, fullType in ipairs(look) do
    if fullType == "Base.Shirt_Workman" or fullType == "Base.Shirt_PoliceBlue" then
        shirts = shirts + 1
    end
    if fullType == "Base.Trousers_Police" or fullType == "Base.Trousers_Denim" then
        trousers = trousers + 1
    end
end
assert(shirts == 1, "the chosen shirt replaces the preset's: " .. tostring(shirts))
assert(trousers == 1, "the chosen trousers replace the preset's: " .. tostring(trousers))

-- The two readers the spawn path uses.
local bag = Creator.bagFromSlots(slots)
assert(bag ~= nil and bag.fullType == "Base.Bag_Schoolbag", "the bag reader finds the bag")
local primary, secondary = Creator.carriedFromSlots(slots)
assert(primary == "Base.Crowbar", "the primary reader finds the primary")
assert(secondary == "Base.BaseballBat", "the secondary reader finds the secondary")

-- The hand-over: primary beats the "Carries" preset, the bag travels separately,
-- and the secondary is still in the slot table the spawn path decodes.
local group = Creator.newGroup()
local person = { name = "Nora", look = "casual", kit = "none", pack = "meal",
    weapon = "Base.KitchenKnife", weaponId = "knife", slots = slots }
local record = Creator.recordFor(person, group)
assert(record.weapon == "Base.Crowbar", "the primary slot is what is carried")
assert(record.bag == "Base.Bag_Schoolbag", "the bag is handed over by name")
assert(string.find(record.slots, "secondary:Base.BaseballBat", 1, true) ~= nil,
    "the secondary is in the record's slot field")
local back = Creator.decodeSlots(record.slots)
assert(back.secondary == "Base.BaseballBat", "and it reads back")
local noPrimary = { name = "Sam", look = "casual", kit = "none", pack = "meal",
    weapon = "Base.KitchenKnife", slots = {} }
assert(Creator.recordFor(noPrimary, group).weapon == "Base.KitchenKnife",
    "with no slot choice the preset weapon is carried")

print("creator_slots ok")
