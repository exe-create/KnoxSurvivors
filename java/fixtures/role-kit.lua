local Equipment = assert(KnoxEquipmentIntelligence, "the equipment owner is loaded")
local Storage = assert(KnoxBaseStorage, "the storage owner is loaded")
local Catalog = assert(KnoxOrderCatalog, "the role catalogue is loaded")
local previousNeeds = KnoxSurvivorNeeds
KnoxSurvivorNeeds = {
    isWaterItem = function(item) return item ~= nil and item.water == true end,
}

local function list(items)
    return {
        size = function() return #items end,
        get = function(_, index) return items[index + 1] end,
    }
end

local function container(items)
    return { getItems = function() return list(items) end }
end

local function item(fullType, options)
    options = options or {}
    local value = {
        type = fullType,
        category = options.category or "",
        display = options.display or "",
        favorite = options.favorite == true,
        water = options.water == true,
        container = options.container == true,
        bandage = options.bandage == true,
        weapon = options.weapon == true,
        ranged = options.ranged == true,
    }
    function value:getFullType() return self.type end
    function value:getCategory() return self.category end
    function value:getDisplayCategory() return self.display end
    function value:isFavorite(...)
        assert(select("#", ...) == 0, "isFavorite receives no extra arguments")
        return self.favorite
    end
    function value:IsWeapon() return self.weapon end
    function value:isRanged() return self.ranged end
    function value:isBroken() return false end
    function value:getConditionMax() return 100 end
    function value:getCondition() return 100 end
    function value:getMinDamage() return 1 end
    function value:getMaxDamage() return 2 end
    function value:getMaxRange() return 1 end
    function value:getBaseSpeed() return 1 end
    function value:getCriticalChance() return 0 end
    function value:isCanBandage() return self.bandage end
    function value:IsInventoryContainer() return self.container end
    function value:getInventory() return self.inventory or list({}) end
    function value:hasTag(tag) return options.tags ~= nil and options.tags[tag] == true end
    function value:getModData() return self.modData or {} end
    return value
end

local samples = {
    melee = item("Base.Axe", { weapon = true }),
    firearm = item("Base.Pistol", { weapon = true, ranged = true }),
    ammo = item("Base.Bullets9mm"),
    bandage = item("Base.Bandage", { bandage = true }),
    water = item("Base.WaterBottle", { water = true }),
    bag = item("Base.Bag", { container = true }),
    knife = item("Base.KitchenKnife", { category = "Knife" }),
    light = item("Base.Flashlight", { display = "Light" }),
    can_opener = item("Base.CanOpener"),
    fuel = item("Base.PetrolCan"),
    hoe = item("Base.HandShovel"),
    seeds = item("Base.SeedTomato"),
    hammer = item("Base.Hammer"),
    saw = item("Base.Saw"),
    planks = item("Base.Plank"),
    nails = item("Base.Nails"),
    disinfectant = item("Base.BottleDisinfectant"),
    painkiller = item("Base.Pills"),
    wrench = item("Base.Wrench"),
    screwdriver = item("Base.Screwdriver"),
    parts = item("Base.NormalTire1", { display = "VehicleMaintenance" }),
    clipboard = item("Base.Clipboard"),
}
local dogtag = item("Base.Dogtag")
for _, role in ipairs(Catalog.baseRoleOrder) do
    for _, tag in ipairs(Catalog.roleGear(role)) do
        assert(samples[tag] ~= nil, "the fixture covers every role tag: " .. tag)
        assert(Equipment.roleKitMatches(tag, samples[tag]) == true,
            "the role tag matches its real item shape: " .. tag)
        assert(Equipment.roleKitMatches(tag, dogtag) == false,
            "the role tag rejects an unrelated item: " .. tag)
    end
end
assert(Equipment.roleKitMatches("melee", item("Base.Axe", { weapon = true, ranged = true })) == false,
    "a ranged weapon does not satisfy the melee slot")

local carriedBag = samples.bag
carriedBag.inventory = container({ samples.bandage })
local resident = { getInventory = function()
    return container({ samples.melee, carriedBag })
end }
local missing = Equipment.roleKitMissing(resident, { "melee", "firearm", "ammo", "bandage", "water" })
assert(#missing == 3 and missing[1] == "firearm" and missing[2] == "ammo"
    and missing[3] == "water", "only genuinely missing role tags are reported: "
    .. table.concat(missing, ","))
local excluded = Equipment.roleKitMissing(resident, { "bandage" }, function() return false end)
assert(#excluded == 1 and excluded[1] == "bandage",
    "an excluded claim still leaves the carried item as the readiness fact")

local oldOperational = Storage.operationalPolicies
local oldResolve = Storage.resolvePolicy
local source = {}
local policy = { key = "medical", x = 1, y = 0, z = 0, container = source }
local origin = {
    getX = function() return 0 end,
    getY = function() return 0 end,
    getZ = function() return 0 end,
}
local actor = { getCurrentSquare = function() return origin end }
local base = { id = "role-kit-test" }
Storage.operationalPolicies = function() return { policy } end
Storage.resolvePolicy = function(value)
    return { policy = value, square = origin, container = value.container }
end
source.getItems = function() return list({ item("Base.Bandage", { favorite = true, bandage = true }),
    samples.bandage }) end
local transfer, result = Storage.findRoleKitTransfer(
    base, actor, { "bandage" }, Equipment.roleKitMatches)
assert(result == "found" and transfer ~= nil and transfer.tag == "bandage"
    and transfer.item == samples.bandage, "favourite stock is skipped, real bandage is found")
assert(transfer.sourcePolicy == policy and transfer.source.container == source,
    "the transfer keeps the exact assigned source")
local stock = Storage.roleKitStock(
    base, actor, { "bandage", "water" }, Equipment.roleKitMatches)
assert(stock.bandage == samples.bandage and stock.water == nil,
    "read-only stock names only the missing tag with an eligible item")
local excludedStock = Storage.roleKitStock(
    base, actor, { "bandage" }, Equipment.roleKitMatches, function() return false end)
assert(excludedStock.bandage == nil,
    "an excluded claim is not reported as available stock")
local refused = Storage.findRoleKitTransfer(
    base, actor, { "bandage" }, Equipment.roleKitMatches, function() return false end)
assert(refused == nil, "an unavailable claim is not treated as stock")
policy.storageFilterVersion = 1
policy.storageFilters = { food = true }
local filtered = Storage.findRoleKitTransfer(
    base, actor, { "bandage" }, Equipment.roleKitMatches)
assert(filtered == nil, "the assigned storage filter still rejects a non-food item")
local filteredStock = Storage.roleKitStock(
    base, actor, { "bandage" }, Equipment.roleKitMatches)
assert(filteredStock.bandage == nil,
    "the assigned storage filter also rejects a displayed kit replacement")
policy.storageFilterVersion = nil
policy.storageFilters = nil
source.getItems = function() return list({ samples.bandage, samples.water }) end
local roster = {
    { id = "kit-guard", preference = "guard", character = resident },
    { id = "kit-absent", preference = "guard", character = nil },
    { id = "kit-auto", preference = "auto", character = resident },
}
local readout = Storage.roleKitShortages(base, roster)
assert(#readout == 3, "the roster readout keeps every resident, got " .. #readout)
assert(readout[1].status == "shortage" and readout[1].role == "guard",
    "the loaded guard is short against the real carried kit")
assert(readout[1].stock.water == samples.water,
    "the base-wide readout names real stock for a missing tag")
assert(readout[2].status == "unknown" and readout[2].role == "guard",
    "an out-of-contact guard is unknown, not fabricated ready")
assert(readout[3].status == "no_role" and readout[3].role == nil,
    "a resident with automatic work has no role kit to report")
source.getItems = function() return list({}) end
local empty = Storage.findRoleKitTransfer(
    base, actor, { "bandage" }, Equipment.roleKitMatches)
assert(empty == nil, "an empty assigned container does not invent a kit item")
local emptyStock = Storage.roleKitStock(
    base, actor, { "bandage" }, Equipment.roleKitMatches)
assert(emptyStock.bandage == nil,
    "an empty assigned container does not invent displayed stock")

local guardGear = Catalog.roleGear("guard")
assert(Catalog.roleKitStatusText("guard", guardGear, {}, {}) == "Kit ready: Guard.",
    "a complete kit reads ready")
assert(Catalog.roleKitStatusText(nil, nil, nil, nil) == "Kit: no role assigned.",
    "a roleless resident does not invent a kit")
local missingTags = { "bandage", "water" }
assert(Catalog.roleKitStatusText("guard", guardGear, missingTags,
    { bandage = samples.bandage, water = samples.water })
    == "Kit shortage: bandage, water — stock available.",
    "missing tags with stock read as a restockable shortage")
assert(Catalog.roleKitStatusText("guard", guardGear, missingTags, {})
    == "Kit shortage: bandage, water — no assigned stock.",
    "missing tags without stock name the real shortage")
assert(Catalog.roleKitStatusText("guard", guardGear, missingTags,
    { bandage = samples.bandage })
    == "Kit shortage: bandage, water — stock for bandage only.",
    "partial stock names only the replacement that exists")
assert(Catalog.roleKitStatusText("cook", Catalog.roleGear("cook"),
    { "can_opener" }, {})
    == "Kit shortage: can opener — no assigned stock.",
    "tag labels are readable in the Crew line")

local previousFinder = AdjacentFreeTileFinder
local standableSquare = { canStand = function() return true end }
AdjacentFreeTileFinder = nil
assert(Storage.approachSquare({ source = { square = standableSquare } }, actor) == standableSquare,
    "the storage approach falls back to a standable source square")
local approach = { x = 1, y = 0, z = 0 }
AdjacentFreeTileFinder = { Find = function() return approach end }
assert(Storage.approachSquare({ source = { square = standableSquare } }, actor) == approach,
    "the storage approach asks the native adjacent-tile finder first")
AdjacentFreeTileFinder = previousFinder

Storage.operationalPolicies = oldOperational
Storage.resolvePolicy = oldResolve
KnoxSurvivorNeeds = previousNeeds
print("Role kit PASS tags=22 nested=true favorite=true filter=true stock=false approach=true")
