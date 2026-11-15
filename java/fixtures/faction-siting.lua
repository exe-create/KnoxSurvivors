-- Faction store siting: drives the real BaseManager.ensureFactionStorage slice
-- (KS_BaseManager.lua:296-380) over a stubbed world/cell boundary.
-- Proves the three contract claims: a store is assigned exactly once, an
-- existing policy is never overwritten, and outside-territory or unloaded
-- squares are skipped. The persistence writer and container key are boundary
-- doubles; the siting decisions are the production code.
local S = assert(codecFactionSiting)
local B = assert(S.BaseManager)
-- Harness lifetime: restore whatever earlier fixtures installed instead of
-- leaving the world/cupboard boundary cleared for later fixtures.
local oldCell, oldCupboard = getCell, KnoxToolCupboard
local writes, policies, currentBase = {}, {}, nil
local function reference(object, index, baseId)
    return {
        key = tostring(baseId) .. ":" .. tostring(object.name) .. ":" .. tostring(index),
        containerType = object.kind,
    }
end
B.containerReference = reference
-- Boundary double: records the call and mirrors what the persistence writer
-- does, writing the policy back onto the base table the caller handed in.
B.setStoragePolicy = function(baseId, object, category, index)
    local ref = reference(object, index, baseId)
    writes[#writes + 1] = { key = ref.key, category = category }
    policies[ref.key] = category
    if currentBase ~= nil then
        currentBase.storage[ref.key] = { key = ref.key, storageRole = category, category = category }
    end
    return { key = ref.key, storageRole = category }
end
local function container(kind) return { getType = function() return kind end } end
local function worldObject(name, kind)
    local list = { [0] = container(kind) }
    return {
        name = name, kind = kind,
        getContainerCount = function() return 1 end,
        getContainerByIndex = function(_, i) return list[i] end,
    }
end
local function square(objects)
    return { getObjects = function()
        return { size = function() return #objects end,
                 get = function(_, i) return objects[i + 1] end }
    end }
end
local fridge, crate = worldObject("fridgeA", "fridge"), worldObject("crateA", "crate")
local outside = worldObject("outsideFridge", "fridge")
local squares = {
    ["0:0:0"] = square({ fridge }),
    ["1:0:0"] = square({ crate }),
    ["10:0:0"] = square({ outside }),   -- exists in the cell, outside the territory
}
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
    end }
end
KnoxToolCupboard = { isDryContainerType = function(kind) return kind == "crate" or kind == "shelf" end }
local base = { id = "factionBase", storage = {},
    territory = { minX = 0, minY = 0, width = 3, height = 1, z = 0 } }
local function run(target)
    currentBase = target
    S.ensure(target)
end
-- Claim 1: assignment happens, once per store, for a fridge and a crate.
run(base)
local byCategory = {}
for _, write in ipairs(writes) do byCategory[write.category] = (byCategory[write.category] or 0) + 1 end
assert(#writes == 2, "faction_siting: expected the fridge and the crate to be sited, got " .. #writes)
assert(byCategory.food == 1, "faction_siting: the fridge must be sited as food")
assert(byCategory.building == 1, "faction_siting: the crate must be sited as building")
assert(policies["factionBase:fridgeA:0"] == "food", "faction_siting: fridge policy missing")
-- Claim 2: a second pass adds nothing (assign exactly once).
local firstRun = #writes
run(base)
assert(#writes == firstRun, "faction_siting: a second pass must not re-site an assigned store")
-- Claim 3: an existing policy is never overwritten.
writes = {}
local kept = { id = "keptBase", storage = {},
    territory = { minX = 1, minY = 0, width = 1, height = 1, z = 0 } }
local keptKey = "keptBase:crateA:0"
kept.storage[keptKey] = { key = keptKey, storageRole = "building", marker = "player-set" }
run(kept)
for _, write in ipairs(writes) do
    assert(write.key ~= keptKey, "faction_siting: an existing policy must never be overwritten")
end
assert(kept.storage[keptKey].marker == "player-set", "faction_siting: the existing policy must survive untouched")
-- Claim 4: outside-territory and unloaded squares are skipped, not assigned.
for _, write in ipairs(writes) do
    assert(write.key:find("outsideFridge", 1, true) == nil, "faction_siting: an outside-territory container was sited")
end
assert(policies["keptBase:outsideFridge:0"] == nil, "faction_siting: outside container must never gain a policy")
-- The unloaded square (2,0) returns nil from the cell and must not break the scan.
assert(#writes == 0, "faction_siting: no store should be sited on a base that already covers building, got " .. #writes)
getCell, KnoxToolCupboard = oldCell, oldCupboard
