local Looting = assert(KnoxSurvivorLooting)
local oldNeeds, oldStorage, oldJobs = KnoxSurvivorNeeds, KnoxBaseStorage, KnoxBaseJobs
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local function item(fullType, broken, uses)
    return { getFullType = function() return fullType end,
        isBroken = function() return broken == true end,
        IsFood = function() return false end,
        IsInventoryContainer = function() return false end,
        getCurrentUses = function() return uses or 0 end,
        getUnequippedWeight = function() return 1 end }
end
KnoxSurvivorNeeds = { isSafeFood = function() return false end,
    isWaterItem = function() return false end }
KnoxBaseStorage = { matchesCategory = function() return false end }
local inventory = { getItems = function() return list({}) end,
    getFreeCapacity = function() return 20 end }
local actor = { getInventory = function() return inventory end }
local good = item("Base.Hammer", false)
local broken = item("Base.Hammer", true)
local other = item("Base.Screwdriver", false)
local source = { getItems = function() return list({broken, other, good}) end }
local needs = { categories = {}, types = { ["Base.Hammer"] = 1 },
    typeRules = { ["Base.Hammer"] = {{ items = { ["Base.Hammer"] = 1 },
        itemRules = { ["Base.Hammer"] = { usable = true } } }} } }
local selected = Looting.plan(actor, source, 4, true, { supplyNeeds = needs })
assert(#selected == 1 and selected[1].item == good,
    "a supply pair collects the intact required tool, refusing broken and unrelated items")
needs.reservedCounts = { types = { ["Base.Hammer"] = 1 } }
assert(#Looting.plan(actor, source, 4, true, { supplyNeeds = needs }) == 0,
    "a pending transfer already covering the shortage prevents duplicate collection")
needs.reservedCounts = nil
needs.typeRules["Base.Hammer"] = {{ items = { ["Base.Hammer"] = 1 },
    itemRules = { ["Base.Hammer"] = { minUses = 2 } } }}
assert(#Looting.plan(actor, source, 4, true, { supplyNeeds = needs }) == 0,
    "an intact but depleted tool cannot satisfy a declared uses requirement")
needs.typeRules["Base.Hammer"] = {{ items = { ["Base.Hammer"] = 1 } }}
assert(#Looting.plan(actor, source, 4, true, { supplyNeeds = needs }) == 1,
    "a named stock floor uses the same exact-item path without a tool rule")

local totals = { food = 50, water = 6, medical = 50, weapons = 50,
    tools = 50, logs = 50, building = 50, clothing = 50, ammunition = 50, fuel = 50 }
local summary = { loadedPolicies = 1, totals = totals }
KnoxBaseStorage = { summarize = function() return summary end,
    goalItemCount = function() return 0 end }
local water = "running"
KnoxBaseJobs = { waterSourceState = function() return water end }
local controller = { baseId = "supply-base", base = { tasks = {} } }
assert(codecSettlementSupplyNeeds(controller, 2) == nil,
    "known stock above the running-water targets needs no outing")
summary = { loadedPolicies = 1, totals = { food = 2, water = 6, medical = 50, weapons = 50,
    tools = 50, logs = 50, building = 50, clothing = 50, ammunition = 50, fuel = 50 },
    floorTotals = { food = 2 } }
assert(codecSettlementSupplyNeeds(controller, 2) == nil,
    "assigned floor food and shelf food together satisfy the category reserve")
assert(summary.totals.food == 2 and summary.floorTotals.food == 2,
    "category demand does not mutate the storage snapshot")
summary = { loadedPolicies = 0, totals = {}, floorTotals = { food = 100 } }
assert(codecSettlementSupplyNeeds(controller, 2) == nil,
    "floor stock does not turn unknown storage into a known snapshot")
summary = { loadedPolicies = 1, totals = totals }
water = "dry"
local shortage = codecSettlementSupplyNeeds(controller, 2)
assert(shortage ~= nil and shortage.categories.water == 2,
    "pairs use the same dry-tap reserve of four water units per resident")
controller.base.reserveTargets = { water = 5 }
assert(codecSettlementSupplyNeeds(controller, 2) == nil,
    "the saved water floor still wins over the dry-tap default")
controller.base.reserveTargets = { ["item:Base.Bandage"] = 3 }
shortage = codecSettlementSupplyNeeds(controller, 2)
assert(shortage.types["Base.Bandage"] == 3,
    "named item floors join the pair's real demand")
summary = { loadedPolicies = 0, unavailablePolicies = 2, totals = {} }
assert(codecSettlementSupplyNeeds(controller, 2) == nil,
    "streamed-out storage is unknown, including named stock floors")
summary = { loadedPolicies = 1, totals = {} }
assert(codecSettlementSupplyNeeds(controller, 2).categories.food == 4,
    "an inspected empty pantry is a real shortage")
assert(codecSettlementSupplyNeeds({ baseId = "missing" }, 2) == nil,
    "a missing settlement cannot produce a supply demand")
KnoxSurvivorNeeds, KnoxBaseStorage, KnoxBaseJobs = oldNeeds, oldStorage, oldJobs
print("Settlement supply handoff PASS exactRules=true reservations=true dryTaps=true unknownStock=true")
