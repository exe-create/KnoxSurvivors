-- Farming intent drives the real sowing decision: the area's own crop plan, no
-- substitution, an unplanned area that rests, and the seed the area keeps back.
local Farming = assert(KnoxBaseFarming, "the farming owner must be loaded")
local P = KnoxPersistence
farmingPrior = { data = data, system = CFarmingSystem, cell = getCell,
    menu = ISFarmingMenu, conf = farming_vegetableconf, tags = ItemTag,
    plow = ItemTag ~= nil and ItemTag.DIG_PLOW or "DIG_PLOW",
    seed = ItemTag ~= nil and ItemTag.IS_SEED or "IS_SEED" }
data = {}

ItemTag = { IS_SEED = "IS_SEED", DIG_PLOW = "DIG_PLOW" }
farming_vegetableconf = { props = {
    Cabbage = { seedName = "Base.SeedCabbage" },
    Carrot = { seedName = "Base.SeedCarrot" },
} }

local function listOf(items)
    return { size = function() return #items end,
        get = function(_, index) return items[index + 1] end }
end
local function container(items)
    local list = listOf(items or {})
    return { getItems = function() return list end }
end
local function seedItem(fullType, tag)
    return { getFullType = function() return fullType end,
        hasTag = function(_, wanted)
            return wanted == ItemTag.IS_SEED or wanted == tag
        end,
        getItems = function() return listOf({}) end }
end
local cabbage, carrot = seedItem("Base.SeedCabbage"), seedItem("Base.SeedCarrot")
local cabbageTwo = seedItem("Base.SeedCabbage")
local plowTool = { getFullType = function() return "Base.Shovel" end,
    hasTag = function(_, wanted) return wanted == ItemTag.DIG_PLOW end,
    getItems = function() return listOf({}) end }
local wateringCan = { getFullType = function() return "Base.WaterCan" end,
    hasTag = function() return false end,
    getItems = function() return listOf({}) end }
local bag = container({ plowTool, wateringCan })
local character = { getInventory = function() return bag end,
    getCurrentSquare = function() return { getX = function() return 0 end,
        getY = function() return 0 end, getZ = function() return 0 end } end }

local plants = {}
local function plant(x, y)
    return plants[x .. ":" .. y]
end
CFarmingSystem = { instance = { getLuaObjectOnSquare = function(_, square)
    return plant(square:getX(), square:getY())
end } }
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return { getX = function() return x end, getY = function() return y end,
            getZ = function() return z or 0 end }
    end }
end
ISFarmingMenu = { canDigHereSquare = function() return true end,
    getWaterUsesInteger = function() return 0 end }

local farmRoot = ModData.getOrCreate("KnoxSurvivors_IsoPlayer")
assert(type(farmRoot) == "table", "the persistence root is available")
local base = { id = "farm-base", zones = {}, nextZoneId = 1,
    settings = {}, storage = {} }
farmRoot.bases = farmRoot.bases or {}
farmRoot.bases[base.id] = base
local function addZone(id, zoneType, x1, x2)
    local zone = { id = id, type = zoneType, label = zoneType, x1 = x1, y1 = 0,
        x2 = x2, y2 = 0, z = 0, enabled = true, priority = 50 }
    base.zones[id] = zone
    return zone
end
addZone("farm-base-zone-1", "farming", 0, 1)
local zoneA = addZone("farm-base-zone-2", "farming", 10, 11)
local zoneB = addZone("farm-base-zone-3", "farming", 20, 21)
assert(base.zones ~= nil, "the fixture base is the zone owner")
plants["0:0"] = { state = "plow", typeOfSeed = "Cabbage", waterLevel = 100 }
plants["10:0"] = { state = "plow", typeOfSeed = "Cabbage", waterLevel = 100 }
plants["11:0"] = { state = "plow", typeOfSeed = "Cabbage", waterLevel = 100 }
plants["20:0"] = { state = "plow", typeOfSeed = "Carrot", waterLevel = 100 }

-- 1. No plan, nothing sown: an unplanned area rests and only prepares soil.
assert(select(2, Farming.setZoneCrops(base.zones["farm-base-zone-1"], {})) == "updated")
local task, reason = Farming.findTask(base, character)
assert(task == nil and reason == "no_farming_action_ready",
    "an unplanned area rests and never invents a crop: "
    .. tostring(task and task.action) .. "/" .. tostring(reason))

-- 2. A plan names the crop, and only that crop is sown, even when another seed
--    is listed first in the pack.
bag = container({ plowTool, wateringCan, carrot, cabbage, cabbageTwo })
character.getInventory = function() return bag end
local updated = assert(Farming.setZoneCrops(zoneA, { "Cabbage" }))
assert(updated[1] == "Cabbage" and #updated == 1, "the plan stores the named crop")
local planned, plannedWhy = Farming.zoneCrops(zoneA), "planned"
assert(planned ~= nil and planned[1] == "Cabbage" and plannedWhy == "planned", "the plan reads back")
task = assert(Farming.findTask(base, character), "a planned area finds work")
assert(task.action == "farm_seed" and task.seedType == "Cabbage" and task.zoneId == zoneA.id,
    "the planned crop is the one sown: " .. tostring(task.action) .. "/" .. tostring(task.seedType))

-- 3. A planned crop with no seed plants nothing: a carrot is never substituted.
bag = container({ plowTool, wateringCan, carrot })
character.getInventory = function() return bag end
assert(Farming.setZoneCrops(zoneA, {}))
assert(Farming.setZoneCrops(zoneB, { "Cabbage" }))
task = Farming.findTask(base, character)
assert(task == nil or task.action ~= "farm_seed",
    "a missing planned seed never becomes another crop: "
    .. tostring(task and task.action) .. "/" .. tostring(task and task.seedType))

-- 4. The area keeps one seed back while another plowed square still waits.
assert(Farming.setZoneCrops(zoneA, { "Cabbage" }))
assert(Farming.setZoneCrops(zoneB, {}))
bag = container({ plowTool, wateringCan, cabbage })
character.getInventory = function() return bag end
task = Farming.findTask(base, character)
assert(task == nil or task.action ~= "farm_seed",
    "the last seed of a crop with two plowed squares stays in the pack")

-- 5. Two planned areas each sow their own crop, so the plan is per field.
bag = container({ plowTool, wateringCan, cabbage, carrot })
character.getInventory = function() return bag end
assert(Farming.setZoneCrops(zoneA, { "Cabbage" }))
assert(Farming.setZoneCrops(zoneB, { "Carrot" }))
local taskB = assert(Farming.findTask(base, character), "the planned parcels find work")
assert((taskB.zoneId == zoneA.id and taskB.seedType == "Cabbage")
    or (taskB.zoneId == zoneB.id and taskB.seedType == "Carrot"),
    "each area sows its own crop: " .. tostring(taskB.zoneId) .. "/" .. tostring(taskB.seedType))

-- 6. The plan owner refuses what is not a farm, and survives a codec reload.
addZone("farm-base-zone-4", "guard", 30, 30)
local refused, refusedWhy = Farming.setZoneCrops(base.zones["farm-base-zone-4"], { "Cabbage" })
assert(refused == nil and refusedWhy == "not_a_farm", "only a farm area carries a crop plan")
assert(select(2, Farming.setZoneCrops(nil, { "Cabbage" })) == "unknown_zone")
assert(select(2, Farming.setZoneCrops(zoneA, "cabbage")) == "invalid_plan")
assert(select(2, Farming.setZoneCrops(zoneA, { 7 })) == "invalid_crop")

farmingProbe = { baseId = base.id, cabbageZone = zoneA.id, carrotZone = zoneB.id }
farmingReceipt = "unplanned=1 planned=1 noSubstitute=1 reserve=1 perField=1 "
    .. "refused=3"
farmingPass = true

function finishFarmingIntent()
    data = farmingPrior.data
    CFarmingSystem = farmingPrior.system
    getCell = farmingPrior.cell
    ISFarmingMenu = farmingPrior.menu
    farming_vegetableconf = farmingPrior.conf
    ItemTag = farmingPrior.tags
end
