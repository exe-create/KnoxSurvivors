-- A decision pass asks one settlement for its stock once per resident, and each
-- ask used to walk every assigned container and its nested bags again. The
-- short read-only window must collapse that without hiding a real change, and
-- must never hand a caller the stored snapshot to mutate.
local Storage = KnoxBaseStorage
local oldPolicies, oldResolve, oldClassify, oldAccepts =
    Storage.policies, Storage.resolvePolicy, Storage.classifyItem, Storage.acceptsDeposit
local oldClock = getTimestampMs

local clock = 1000
getTimestampMs = function() return clock end

Storage.classifyItem = function() return "food" end
Storage.acceptsDeposit = function() return true end
Storage.policies = function(base) return base.policyList or {} end
Storage.resolvePolicy = function(policy)
    return { policy = policy, container = policy.container, square = {} }
end

local function container(quantity)
    local entries = {}
    for index = 1, quantity do
        entries[index] = { getFullType = function() return "Base.CannedBeans" end }
    end
    local list = {
        size = function() return #entries end,
        get = function(_, index) return entries[index + 1] end,
    }
    local scanned = { count = 0 }
    return {
        scanned = scanned,
        getItems = function()
            scanned.count = scanned.count + 1
            return list
        end,
    }
end

local shelfA, shelfB = container(2), container(1)
local cabinetA = container(1)
local base = {
    id = "cache-base",
    storage = { a = true, b = true },
    policyList = {
        { key = "a", container = shelfA },
        { key = "b", container = shelfB },
    },
}

-- One pass costs one walk per container, not one per asker.
local first = Storage.summarize(base)
assert(shelfA.scanned.count == 1 and shelfB.scanned.count == 1,
    "the first snapshot walks each assigned container once")
assert(first.totals.food == 3 and first.loadedPolicies == 2,
    "the snapshot still reports the real stock")

for _ = 1, 4 do
    local shared = Storage.summarize(base)
    assert(shared.totals.food == 3, "every asker inside the window sees the same stock")
end
assert(shelfA.scanned.count == 1 and shelfB.scanned.count == 1,
    "four residents in the same decision pass reuse one walk")

-- The window never hands out the stored table: a caller that writes to a
-- summary cannot corrupt what the settlement reports next.
local mutated = Storage.summarize(base)
mutated.totals.food = 999
mutated.misplacedItems = 999
assert(Storage.summarize(base).totals.food == 3,
    "a mutated summary does not poison the cached snapshot")
assert(shelfA.scanned.count == 1, "reading a cached snapshot still costs no walk")

-- A real change is visible once the window closes.
clock = clock + 2000
local refreshed = Storage.summarize(base)
assert(shelfA.scanned.count == 2 and refreshed.totals.food == 3,
    "the window expires and the stock is walked again")

-- Assigning or removing a container is never served stale, even inside the
-- window, because the key carries the policy count.
local beforeChange = shelfA.scanned.count
base.storage.c = true
base.policyList[3] = { key = "c", container = cabinetA }
local withCabinet = Storage.summarize(base)
assert(withCabinet.totals.food == 4 and withCabinet.loadedPolicies == 3,
    "a newly assigned container is counted immediately")
assert(shelfA.scanned.count == beforeChange + 1,
    "the changed policy set bypasses the previous snapshot")
base.storage.c = nil
base.policyList[3] = nil

-- Another settlement never borrows this one's snapshot.
local otherShelf = container(5)
local other = {
    id = "cache-other-base",
    storage = { x = true },
    policyList = { { key = "x", container = otherShelf } },
}
assert(Storage.summarize(other).totals.food == 5 and otherShelf.scanned.count == 1,
    "each settlement's stock is walked for itself")

-- Without the game clock the cache is inert, so fixtures and hardened paths keep
-- their per-call behaviour unchanged.
getTimestampMs = nil
local freshShelf = container(2)
local fresh = { id = "cache-no-clock", storage = { y = true },
    policyList = { { key = "y", container = freshShelf } } }
Storage.summarize(fresh)
Storage.summarize(fresh)
assert(freshShelf.scanned.count == 2,
    "with no clock every ask walks the containers")

Storage.policies, Storage.resolvePolicy, Storage.classifyItem, Storage.acceptsDeposit =
    oldPolicies, oldResolve, oldClassify, oldAccepts
getTimestampMs = oldClock
print("Storage summary cache PASS oneWalkPerPass=true copySafe=true policyChangeFresh=true"
    .. " perBase=true clocklessBypass=true")
