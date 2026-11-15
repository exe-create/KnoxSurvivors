local C = assert(KnoxCreator)
local defs, id = {}, "household"
local original = assert(C.factionIndexIn(nil, id))
local oldLabel = original.label
assert(C.isDefault(id), "built-in recognised")
local ok, override = C.editDefault(defs, id)
assert(ok and override ~= original and override.id == id, "edit creates same-id copy")
ok = C.updateFaction(defs, id, {memberCount=2})
assert(ok and C.factionIndexIn(defs, id).memberCount == 2, "override wins lookup")
assert(C.factionIndexIn(nil, id) == original and original.label == oldLabel, "global default unchanged")
local seen = 0
for _, entry in ipairs(C.allFactions(defs)) do if entry.id == id then seen=seen+1; assert(entry == override) end end
assert(seen == 1, "merged list contains the override once")
local group = C.newGroup(); group.defs = defs
local roster, restored = C.decode(C.encode({}, group))
assert(C.factionIndexIn(restored.defs,id).memberCount == 2, "same-id override survives codec")
assert(C.resetDefault(restored.defs,id), "reset succeeds")
assert(C.factionIndexIn(restored.defs,id) == original, "reset restores built-in")
assert(not C.editDefault(defs,"no_such_default"), "unknown default rejected")

local regional = "template_rosewood_police"
local regionDefault = assert(C.factionIndexIn(nil, regional))
assert(regionDefault.profile == "police" and regionDefault.region == "Rosewood" and regionDefault.group, "regional default derives its kind and region")
assert(not C.isDefault("template_rosewood_doctors"), "independent medical template remains a person template")
local regionalDefs = {}
local created, regionalOverride = C.editDefault(regionalDefs, regional)
assert(created and regionalOverride.id == regional, "regional override keeps template id")
assert(C.updateFaction(regionalDefs, regional, {memberCount=2}), "regional override can be edited")
local regionalGroup = C.newGroup(); regionalGroup.defs = regionalDefs
local _, regionalRestored = C.decode(C.encode({}, regionalGroup))
assert(C.factionIndexIn(regionalRestored.defs, regional).memberCount == 2, "regional override survives codec")
assert(C.resetDefault(regionalRestored.defs, regional), "regional reset succeeds")
assert(C.factionIndexIn(regionalRestored.defs, regional).memberCount == regionDefault.memberCount, "regional reset restores template")
