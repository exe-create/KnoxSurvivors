-- Item minimums: one exact item type with a count, saved beside the category
-- defaults and driven through the same supply planner the residents obey.
local Planner = assert(KnoxBaseSupplyPlanner, "the supply planner is loaded")
local Persistence = assert(KnoxPersistence, "persistence is loaded")

-- The save shape stays additive: an item minimum is one more key in the same
-- optional table, so every older target keeps working.
assert(Persistence.validBaseReserveTargets(nil) == true, "no targets is a valid save")
assert(Persistence.validBaseReserveTargets({ food = 8 }) == true, "a category target saves")
assert(Persistence.validBaseReserveTargets({ ["item:Base.Bandage"] = 20 }) == true,
    "an item minimum saves beside the categories")
assert(Persistence.validBaseReserveTargets({ ["item:Base.Bandage"] = 20, water = 4 }) == true,
    "categories and items share one table")
assert(Persistence.validBaseReserveTargets({ ["item:Base.Bandage"] = -1 }) == false,
    "a negative minimum is refused")
assert(Persistence.validBaseReserveTargets({ ["item:Base.Bandage"] = 51 }) == false,
    "a minimum above the save ceiling is refused")
assert(Persistence.validBaseReserveTargets({ ["item:"] = 3 }) == false,
    "an empty item key is refused")
assert(Persistence.validBaseReserveTargets({ ["item:Base Bandage"] = 3 }) == false,
    "an item key with a space is refused")
assert(Persistence.validBaseReserveTargets({ ["item:Base.Bandage"] = 1.5 }) == false,
    "a fractional minimum is refused")

assert(Planner.itemTargetKey("Base.Bandage") == "item:Base.Bandage",
    "the key names the exact type")
assert(Planner.itemTargetKey("") == nil, "an empty type has no key")
assert(Planner.itemTargetType("item:Base.Bandage") == "Base.Bandage", "the key reads back")
assert(Planner.itemTargetType("food") == nil, "a category key is not an item minimum")

local held = { ["Base.Bandage"] = 4, ["Base.BandageDirty"] = 9 }
local goals = Planner.itemGoalStatus({ ["item:Base.Bandage"] = 20,
    ["item:Base.BandageDirty"] = 6, food = 20 }, function(fullType)
    return held[fullType] or 0
end)
assert(#goals == 2, "only item minimums become item goals, got " .. tostring(#goals))
assert(goals[1].fullType == "Base.Bandage", "goals are ordered by type")
assert(goals[1].current == 4 and goals[1].target == 20 and goals[1].missing == 16,
    "a shortage is the minimum minus what the shelves hold")
assert(goals[2].missing == 0, "stock at or above the minimum is not a shortage")

local met = Planner.itemGoalStatus({ ["item:Base.Bandage"] = 3 }, function() return 9 end)
assert(met[1].missing == 0 and met[1].current == 9,
    "surplus stock reports no shortage")

local unreadable = Planner.itemGoalStatus({ ["item:Base.Bandage"] = 3 }, function()
    error("no world")
end)
assert(unreadable[1].current == 0 and unreadable[1].missing == 3,
    "an unreadable shelf count is a shortage, never a satisfied minimum")

assert(#Planner.itemGoalStatus({}, function() return 0 end) == 0,
    "no goals without targets")
assert(#Planner.itemGoalStatus({ ["item:Base.Bandage"] = 0 }, function() return 0 end) == 0,
    "a zero minimum is not a goal")
assert(#Planner.itemGoalStatus({ ["item:Base.Bandage"] = 2 }, nil) == 0,
    "a goal without a shelf reader is not invented")
