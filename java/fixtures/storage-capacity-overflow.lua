-- A settlement that runs out of room in the shelf it named for a category must
-- still be able to file the haul. Capacity overflow answers exactly that: when
-- the matching shelves are full, an assigned shelf that names another category
-- may take the item, ranked behind every matching shelf and never in a food,
-- water or medicine store. A filter refusal, a wall or a cooldown is a different
-- problem and must keep its own reported cause.
local Storage = KnoxBaseStorage
local oldFinder = AdjacentFreeTileFinder
local oldNeeds = KnoxSurvivorNeeds
local oldPolicies, oldResolve, oldClassify =
    Storage.operationalPolicies, Storage.resolvePolicy, Storage.classifyItem

KnoxSurvivorNeeds = { isWaterItem = function() return false end,
    isSafeFood = function() return false end }

local policies = {}
local classified = "food"
local function square(x)
    return { getX = function() return x end, getY = function() return 0 end,
        getZ = function() return 0 end, isSomethingTo = function() return false end }
end
local origin = square(0)
local actor = { getCurrentSquare = function() return origin end }
local base = { id = "overflow-test" }
local roomy = { hasRoomFor = function() return true end, isItemAllowed = function() return true end }
local full = { hasRoomFor = function() return false end, isItemAllowed = function() return true end }
local refuses = { hasRoomFor = function() return true end, isItemAllowed = function() return false end }

Storage.operationalPolicies = function() return policies end
Storage.classifyItem = function() return classified end
Storage.resolvePolicy = function(policy)
    if policy.unloaded then return nil end
    return { policy = policy, square = square(policy.x), container = policy.container or roomy }
end
AdjacentFreeTileFinder = { Find = function(tile) return tile end }

-- A saved record is exactly what KnoxPersistence writes: version 1 with its own
-- filter list and the matching storageRole, so the role is what decides.
local function policy(key, role, x, container)
    return { key = key, x = x or 1, y = 0, z = 0,
        storageFilterVersion = 1, storageRole = role,
        storageFilters = { [role] = true }, container = container }
end

local beans = { getFullType = function() return "Base.CannedBeans" end,
    getDisplayCategory = function() return "Food" end,
    IsFood = function() return true end, getName = function() return "Canned Beans" end }
local bandage = { getFullType = function() return "Base.Bandage" end,
    getDisplayCategory = function() return "Medical" end,
    IsFood = function() return false end, getName = function() return "Bandage" end }

local function trip()
    return Storage.findDepositTrip(base, actor, beans, nil, 100)
end

-- The matching shelf wins whenever it has room; overflow is not preferred.
policies = { policy("food-a", "food", 1, roomy), policy("tools-a", "tools", 3, roomy) }
local target, reason = trip()
assert(target ~= nil and target.policy.key == "food-a" and reason == "nearby_storage",
    "a matching shelf with room is still chosen first")
assert(target.overflow ~= true, "a matching shelf is not an overflow")

-- One full shelf plus another assigned shelf with room: the haul is filed.
policies = { policy("food-a", "food", 1, full), policy("tools-a", "tools", 3, roomy) }
target, reason = trip()
assert(target ~= nil and target.policy.key == "tools-a" and reason == "nearby_storage",
    "a full matching shelf redirects the haul to an assigned shelf with room")
assert(target.overflow == true, "the redirected destination is marked as overflow")

-- Priority then distance order the overflow candidates, matching the existing
-- ranking rules for real destinations.
policies = {
    policy("food-a", "food", 1, full),
    policy("tools-low", "tools", 5, roomy), policy("tools-critical", "tools", 7, roomy),
}
policies[2].priority, policies[3].priority = "low", "critical"
target = trip()
assert(target.policy.key == "tools-critical", "a critical overflow shelf outranks a low one")
policies = { policy("food-a", "food", 1, full),
    policy("tools-far", "tools", 9, roomy), policy("tools-near", "tools", 3, roomy) }
target = trip()
assert(target.policy.key == "tools-near", "the nearer overflow shelf wins at equal priority")

-- Food, water and medicine stores stay reserved for their own stock.
policies = { policy("food-a", "food", 1, full), policy("medical-a", "medical", 3, roomy) }
target, reason = trip()
assert(target == nil and reason == "storage_full",
    "a full food shelf never spills into the medicine cabinet")
classified = "medical"
policies = { policy("medical-a", "medical", 1, full), policy("food-a", "food", 3, roomy) }
target, reason = Storage.findDepositTrip(base, actor, bandage, nil, 100)
assert(target == nil and reason == "storage_full",
    "a full medicine shelf never spills into the kitchen")

-- Filters remain authoritative when no shelf names the category at all: the
-- resident reports the filter problem instead of dumping the item anywhere.
classified = "food"
policies = { policy("tools-a", "tools", 1, roomy) }
target, reason = trip()
assert(target == nil and reason == "no_matching_storage",
    "no matching shelf and no full shelf means a filter problem, not overflow")

-- Capacity is the only cause that justifies overflow. A wall, a cooldown or a
-- container that cannot hold the item keeps its own explanation. Here the native
-- adjacent-square finder has no side to stand on and the only usable square is
-- too far from the shelf, so the shelf is unreachable rather than full.
AdjacentFreeTileFinder = { Find = function() return nil end }
policies = { policy("food-a", "food", 3, roomy), policy("tools-a", "tools", 1, roomy) }
target, reason = trip()
assert(target == nil and reason == "storage_inaccessible",
    "an unreachable matching shelf stays a reachability problem")
AdjacentFreeTileFinder = { Find = function(tile) return tile end }
policies = { policy("food-a", "food", 1, roomy), policy("tools-a", "tools", 3, roomy) }
target, reason = Storage.findDepositTrip(base, actor, beans, { ["food-a"] = 200 }, 100)
assert(target == nil and reason == "storage_retry_cooldown",
    "a cooled-down matching shelf stays a retry problem")
policies = { policy("food-a", "food", 1, full), policy("tools-a", "tools", 3, refuses) }
target, reason = trip()
assert(target == nil and reason == "storage_full",
    "an overflow shelf that cannot hold the item is not used, and the full shelf is still named")

-- A discovered container is still the existing stopgap, but an assigned shelf
-- that can hold the item outranks it.
policies = { policy("food-a", "food", 1, full) }
policies[2] = policy("loose", "tools", 3, roomy)
policies[2].transientContainer = true
target, reason = trip()
assert(target ~= nil and target.policy.key == "loose" and reason == "nearby_storage",
    "an unassigned container still receives a haul when nothing assigned can")
policies = { policy("food-a", "food", 1, full), policy("tools-a", "tools", 5, roomy) }
policies[3] = policy("loose", "tools", 3, roomy)
policies[3].transientContainer = true
target = trip()
assert(target ~= nil and target.policy.key == "tools-a",
    "an assigned overflow shelf outranks a discovered container")

-- The transfer owner re-validates the plan by asking for that exact container:
-- a pinned lookup must return the overflow destination, not discard it.
policies = { policy("food-a", "food", 2, full), policy("tools-a", "tools", 1, roomy) }
local pinned, pinnedReason = Storage.findNearbyDeposit(base, actor, beans, "tools-a")
assert(pinned ~= nil and pinned.policy.key == "tools-a" and pinnedReason == "nearby_storage",
    "the planned overflow shelf survives re-validation")
assert(pinned.overflow == true, "the re-validated overflow keeps its meaning")
local matched = Storage.findNearbyDeposit(base, actor, beans, "food-a")
assert(matched == nil, "a full shelf cannot be re-validated into a destination")

Storage.operationalPolicies, Storage.resolvePolicy, Storage.classifyItem =
    oldPolicies, oldResolve, oldClassify
AdjacentFreeTileFinder = oldFinder
KnoxSurvivorNeeds = oldNeeds
print("Storage capacity overflow PASS fullShelfRedirects=true consumablesReserved=true"
    .. " filterProblemKept=true pinnedRevision=true")
