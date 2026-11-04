local Persistence = assert(KnoxPersistence, "persistence is loaded")
local Planner = assert(KnoxBaseSupplyPlanner, "supply planner is loaded")

assert(Persistence.validBaseReserveTargets(nil) == true,
    "missing targets are valid and mean planner defaults")
assert(Persistence.validBaseReserveTargets({}) == true,
    "an empty target map is a clear request")
assert(Persistence.validBaseReserveTargets({
    food = 3, water = 0, medical = 2, ammunition = 4, fuel = 2,
    weapons = 1, tools = 1, logs = 6, building = 4, clothing = 2,
}) == true, "every executor-backed supply category is a valid target")
assert(Persistence.validBaseReserveTargets({ farming = 1 }) == false,
    "a category without a supply executor is refused")
assert(Persistence.validBaseReserveTargets({ food = -1 }) == false,
    "negative targets are refused")
assert(Persistence.validBaseReserveTargets({ food = 2.5 }) == false,
    "fractional targets are refused")
assert(Persistence.validBaseReserveTargets({ food = 51 }) == false,
    "targets are bounded")

local base, created = Persistence.createBase(
    "player",
    "base-supply-targets-player",
    { minX = 6000, minY = 6000, width = 3, height = 3, buildingId = "base-supply-targets-building" },
    12
)
assert(base ~= nil and created == "created", "fixture base was created")
assert(Persistence.getBaseReserveTargets(base.id) == nil,
    "a new base has no target overrides")

local ok, reason = Persistence.setBaseReserveTargets(base.id,
    "base-supply-targets-player",
    { food = 5, water = 1, medical = 3, ammunition = 2, fuel = 2,
        weapons = 2, tools = 1, logs = 8, building = 4, clothing = 3 }, 13)
assert(ok == true and reason == "saved", "owner can save stock targets")
local saved = Persistence.getBaseReserveTargets(base.id)
assert(saved.food == 5 and saved.water == 1 and saved.medical == 3
    and saved.ammunition == 2 and saved.fuel == 2, "saved targets read back exactly")
assert(saved.weapons == 2 and saved.tools == 1 and saved.logs == 8
    and saved.building == 4 and saved.clothing == 3,
    "the executor-backed categories read back exactly too")
saved.food = 99
assert(Persistence.getBaseReserveTargets(base.id).food == 5,
    "readers receive a copy, not the live base table")

ok, reason = Persistence.setBaseReserveTargets(base.id, "someone-else", { food = 1 }, 14)
assert(ok == false and reason == "not_your_base", "another owner cannot set targets")
ok, reason = Persistence.setBaseReserveTargets(base.id, "base-supply-targets-player",
    { food = 3, farming = 1 }, 14)
assert(ok == false and reason == "invalid_targets",
    "an unsupported key refuses the whole change")
assert(Persistence.getBaseReserveTargets(base.id).food == 5,
    "a refused target change leaves the previous map intact")

ok, reason = Persistence.setBaseReserveTargets(base.id, "base-supply-targets-player", {}, 15)
assert(ok == true and reason == "cleared" and Persistence.getBaseReserveTargets(base.id) == nil,
    "an empty map clears overrides back to defaults")

local defaults = Planner.reserveStatus({ food = 0 }, 2)
local defaultByCategory = {}
for _, status in ipairs(defaults) do defaultByCategory[status.category] = status end
assert(defaultByCategory.food.target == 4, "food keeps its per-resident default")
assert(defaultByCategory.water.target == 4, "water keeps its per-resident default")
assert(defaultByCategory.medical.target == 1, "medical keeps its flat default")
assert(defaultByCategory.ammunition.target == 2, "ammo keeps its flat default")
assert(defaultByCategory.fuel.target == 2, "fuel keeps its two-can default")
assert(defaultByCategory.fuel.kind == "find_fuel", "fuel has a real supply kind")
assert(defaultByCategory.weapons.target == 1, "weapons keep their one-item default")
assert(defaultByCategory.tools.target == 1, "tools keep their one-item default")
assert(defaultByCategory.logs.target == 8, "logs keep their per-resident default")
assert(defaultByCategory.building.target == 4, "building keeps its flat default")
assert(defaultByCategory.clothing.target == 2, "clothing keeps its per-resident default")

assert(Planner.waterSourceState(10, 14) == "running",
    "water is running before the shutoff day")
assert(Planner.waterSourceState(14, 14) == "dry",
    "the shutoff day itself is dry")
assert(Planner.waterSourceState(20, 0) == "running",
    "a disabled shutoff keeps the taps running")
assert(Planner.waterSourceState(nil, 14) == "unknown",
    "an absent clock is unknown, not running")
assert(Planner.waterSourceState(20, nil) == "unknown",
    "an absent modifier is unknown, not running")

local dry = Planner.reserveStatus({ water = 0 }, 2, nil, "dry")
assert(dry[2].category == "water" and dry[2].target == 8,
    "dry taps raise the unreserved water target to four per resident")
local dryOverride = Planner.reserveStatus({ water = 0 }, 2, { water = 1 }, "dry")
assert(dryOverride[2].target == 1,
    "a saved water target still wins over the shutoff bump")
local running = Planner.reserveStatus({ water = 0 }, 2, nil, "running")
assert(running[2].target == 4, "running taps keep the normal water target")

local custom = { food = 5, water = 1, medical = 3, ammunition = 2, fuel = 2,
    weapons = 2, tools = 1, logs = 6, building = 3, clothing = 1 }
local statuses = Planner.reserveStatus(
    { food = 2, water = 0, medical = 1, ammunition = 0, fuel = 0 }, 1, custom)
local byCategory = {}
for _, status in ipairs(statuses) do byCategory[status.category] = status end
assert(byCategory.food.target == 5 and byCategory.food.missing == 3,
    "a food target replaces only the food threshold")
assert(byCategory.water.target == 1 and byCategory.water.missing == 1,
    "a water target replaces only the water threshold")
assert(byCategory.medical.target == 3 and byCategory.medical.missing == 2,
    "a medical target replaces only the medical threshold")
assert(byCategory.ammunition.target == 2 and byCategory.ammunition.missing == 2,
    "an ammo target replaces only the ammo threshold")
assert(byCategory.fuel.target == 2 and byCategory.fuel.missing == 2,
    "a fuel target replaces only the fuel threshold")
assert(byCategory.weapons.target == 2 and byCategory.weapons.missing == 2,
    "a weapons target replaces only the weapons threshold")
assert(byCategory.tools.target == 1 and byCategory.tools.missing == 1,
    "a tools target replaces only the tools threshold")
assert(byCategory.logs.target == 6 and byCategory.logs.missing == 6,
    "a logs target replaces only the logs threshold")
assert(byCategory.building.target == 3 and byCategory.building.missing == 3,
    "a building target replaces only the building threshold")
assert(byCategory.clothing.target == 1 and byCategory.clothing.missing == 1,
    "a clothing target replaces only the clothing threshold")

local shortage = Planner.shortages(
    { food = 5, water = 0, medical = 3, ammunition = 2, fuel = 2 }, 1, custom)
assert(shortage[1] == "find_water", "the shared shortage order sees the target override")
assert(Planner.chooseAvailableShortage(
    { food = 5, water = 0, medical = 3, ammunition = 2, fuel = 2 }, 1, {}, "resident", custom)
    == "find_water", "automatic supply election uses the same target override")

local Jobs = assert(KnoxBaseJobs, "base jobs are loaded")
local Storage = assert(KnoxBaseStorage, "base storage is loaded")
ok, reason = Persistence.setBaseReserveTargets(base.id,
    "base-supply-targets-player", custom, 16)
assert(ok == true, "fixture target map is saved for the settlement read")
local oldSummarize = Storage.summarize
Storage.summarize = function()
    return {
        loadedPolicies = 1, unavailablePolicies = 0, misplacedItems = 0,
        totals = { food = 2, water = 0, medical = 1, ammunition = 0, fuel = 0 },
    }
end
local settlement = Jobs.settlementSummary(base, 20)
Storage.summarize = oldSummarize
local settlementByCategory = {}
for _, status in ipairs(settlement.reserves or {}) do
    settlementByCategory[status.category] = status
end
assert(settlementByCategory.food.target == 5 and settlementByCategory.food.missing == 3,
    "settlement summary reads the base food target")
assert(settlement.shortages[1] == "find_food",
    "settlement summary publishes the target-aware food shortage first")
assert(settlementByCategory.fuel.target == 2 and settlementByCategory.fuel.missing == 2,
    "settlement summary reads the base fuel target")
assert(settlement.shortages[#settlement.shortages] == "find_fuel",
    "settlement summary publishes the fuel shortage too")

base.reserveTargets = { food = 10, water = 7, medical = 99, ammunition = 2.5 }
local corrupt = Persistence.getBaseReserveTargets(base.id)
assert(corrupt.food == 10 and corrupt.water == 7
    and corrupt.medical == nil and corrupt.ammunition == nil,
    "invalid saved values are ignored without discarding valid siblings")

print("Base supply targets PASS owner=true default=true override=true shortage=true copy=true")