-- Add-person target is explicit: owned groups and Solo take people, the
-- companions filter and shipped previews refuse with guidance. Drives the
-- real KnoxCreator.resolveAddTarget and devSpawnEntries.
local C = assert(KnoxCreator)

local group = C.newGroup()
local ok, household = C.addFaction(group.defs, "River Household", "household")
assert(ok, "owned household is created")
local ownedId = household.id

-- Nil selection names the choice instead of falling back to a household.
local okNil, msgNil = C.resolveAddTarget(nil, group)
assert(okNil == false and msgNil:find("Choose the group", 1, true) ~= nil,
  "no selection asks for a group")

-- The companions view is a filter, not a group: adding there used to make a
-- hidden householder, so the new person never appeared in the viewed list.
local okCast, msgCast = C.resolveAddTarget("starting", group)
assert(okCast == false and msgCast:find("filter, not a group", 1, true) ~= nil,
  "companions filter refuses with guidance")

-- A shipped kind preview is never an add target: accepting it would grow the
-- default id instead of the player's own group.
local okPreview, msgPreview = C.resolveAddTarget("household", group)
assert(okPreview == false and msgPreview:find("shipped preview", 1, true) ~= nil,
  "default preview refuses with copy guidance")

-- Solo and owned groups accept.
assert(C.resolveAddTarget("solo", group) == true, "solo accepts")
local okOwned, targetOwned = C.resolveAddTarget(ownedId, group)
assert(okOwned == true and targetOwned == ownedId, "owned group accepts")

-- The accepted target is what the draft carries: no silent fallback.
local draft = C.draftForFaction(targetOwned, group.defs)
draft.name = "Ava Test"
draft.faction = targetOwned
local roster = {}
assert(C.add(roster, draft), "person adds to the owned group")
assert(C.personFactionId(roster[1], group) == ownedId, "new person stays in the chosen group")

-- Dev spawn menu lists roster people with their group for the in-game menu.
local soloDraft = C.draftForFaction("solo", group.defs)
soloDraft.name = "Wren Solo"
soloDraft.faction = "solo"
assert(C.add(roster, soloDraft), "solo person adds")
local entries = C.devSpawnEntries(roster, group)
assert(#entries == 2 and entries[1].label == "Ava Test", "dev menu names roster people")
assert(entries[2].detail ~= nil and entries[2].index == 2, "dev menu carries group detail")

print("Creator add target PASS owned=" .. tostring(ownedId) .. " entries=" .. tostring(#entries))
