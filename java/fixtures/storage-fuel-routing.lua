local Storage = KnoxBaseStorage
local oldNeeds = KnoxSurvivorNeeds
local oldTag = ItemTag
KnoxSurvivorNeeds = {
    isWaterItem = function() return false end,
    isSafeFood = function() return false end,
}

local function item(full, category)
    local value = { full = full, category = category or "VehicleMaintenance" }
    function value:getFullType() return self.full end
    function value:getDisplayCategory() return self.category end
    function value:hasTag() return false end
    return value
end

for _, full in ipairs({ "Base.PetrolCan", "Base.EmptyPetrolCan", "Base.JerryCan" }) do
    local can = item(full)
    assert(Storage.matchesCategory(can, "fuel"), full .. " is fuel")
    assert(Storage.classifyItem(can) == "fuel", full .. " classifies as fuel before materials")
    assert(Storage.acceptsDeposit({ storageFilterVersion = 1,
        storageFilters = { fuel = true } }, can), full .. " enters fuel storage")
    assert(not Storage.acceptsDeposit({ storageFilterVersion = 1,
        storageFilters = { building = true } }, can),
        full .. " does not leak into building storage")
end

assert(not Storage.matchesCategory(item("Base.Plank", "Material"), "fuel"),
    "ordinary materials are not fuel")
assert(not Storage.matchesCategory(item("Base.WaterBottle", "Water"), "fuel"),
    "water containers are not fuel")
assert(Storage.filterLabel("fuel") == "Fuel", "fuel has a player-facing label")
assert(Storage.isValidFilterCategory("fuel"), "fuel is a valid filter category")
assert(Storage.filtersForPolicy({ storageRole = "fuel" }).fuel,
    "legacy fuel policies resolve to the fuel filter")

ItemTag = { FUEL = "fuel" }
local tagged = { getFullType = function() return "Base.UnknownFuel" end,
    getDisplayCategory = function() return "" end,
    hasTag = function(_, tag) return tag == "fuel" end }
assert(Storage.matchesCategory(tagged, "fuel"), "the native fuel tag is honored")
assert(not Storage.matchesCategory(tagged, "building"),
    "a tagged fuel item cannot be reclassified as building")
ItemTag = oldTag
KnoxSurvivorNeeds = oldNeeds
print("Storage fuel PASS types=3 filter=true building_excluded=true tag=true")
