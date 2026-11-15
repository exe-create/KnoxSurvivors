-- GH2 drives the real capacity owner and the real base-storage traversal. Only
-- the native items themselves are doubled: food reports its remaining hunger
-- relief, fluid reports its real amount and safety answer.
local C = assert(KnoxSettlementCapacity, "settlement capacity owner missing")
local S = assert(KnoxBaseStorage, "base storage owner missing")
assert(type(S.walkItems) == "function",
    "the base storage owner exports its own traversal instead of a second walker")

local function bottle(amount, opts)
    opts = opts or {}
    return {
        getFluidContainer = function()
            return {
                getAmount = function() return amount end,
                isTainted = function() return opts.tainted == true end,
                isPoisonous = function() return opts.poisonous == true end,
                getPrimaryFluid = function() return opts.fluid or { kind = "water" } end,
                isPureFluid = function(_, value) return opts.pure ~= false end,
            }
        end,
    }
end
local function food(hungChange, opts)
    opts = opts or {}
    return {
        getHungChange = function() return hungChange end,
        isRotten = function() return opts.rotten == true end,
    }
end
local function container(items)
    return {
        getItems = function()
            return {
                size = function() return #items end,
                get = function(_, index) return items[index + 1] end,
            }
        end,
    }
end

-- Real floor squares: a floor container plus loose world items, exactly the two
-- shapes the storage owner's own floor read counts.
local floorSquares = {}
local function setSquare(x, y, square) floorSquares[x .. ":" .. y] = square end
local function floorSquare(items, loose)
    local floorItems = items ~= nil and container(items) or nil
    local objects = {}
    local all={}
    for _,item in ipairs(items or {}) do all[#all+1]=item end
    for _,item in ipairs(loose or {}) do all[#all+1]=item end
    for _, item in ipairs(all) do
        objects[#objects + 1] = { getItem = function() return item end }
    end
    return {
        getFloor = function() return floorItems end,
        getWorldObjects = function()
            return {
                size = function() return #objects end,
                get = function(_, index) return objects[index + 1] end,
            }
        end,
    }
end
local priorCell = getCell
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            local square = floorSquares[x .. ":" .. y]
            if square ~= nil then return square end
            -- Unknown coordinates keep the previous cell's answer so neighbouring
            -- fixtures still see the world they expect.
            local prior = priorCell ~= nil and priorCell() or nil
            if prior ~= nil and prior.getGridSquare ~= nil then
                return prior.getGridSquare(prior, x, y, z)
            end
            return nil
        end,
    }
end

-- 1. Real remaining food relief, counted once. A half-eaten item is worth its
--    remaining value, never its full item value and never twice.
local partial = food(-0.2)
local measuredPartial = assert(C.itemProvisions(partial))
assert(measuredPartial.food == 0.2,
    "partially eaten native food contributes its remaining hunger relief")
local partialTotals = C.provisions({ container({ partial }) })
assert(partialTotals.food == 0.2 and partialTotals.unreadable == 0,
    "the remaining relief is summed once, not multiplied by a portion factor")
assert(partial:getHungChange() == -0.2,
    "measuring never rewrites the item's own reported value")

-- 2. Real fluid amount, only after every existing safety answer passes.
local full = bottle(1.0)
local emptyBottle = bottle(0)
local tainted = bottle(1.0, { tainted = true })
local poisonous = bottle(1.0, { poisonous = true })
local impure = bottle(1.0, { pure = false })
local mixed = C.provisions({ container({ full, emptyBottle, tainted, poisonous, impure }) })
assert(mixed.water == 1.0,
    "only the safe filled container contributes, at its actual remaining amount")
assert(mixed.unsafe == 3,
    "tainted, poisonous and impure fluid each fail a real safety check")
assert(mixed.unreadable == 0,
    "a failed safety check is a measured zero, not an unreadable item")
assert(tainted:getFluidContainer():getAmount() == 1.0,
    "a failed safety check is never silently repaired")

-- 3. Spoiled food contributes nothing and is reported, not hidden.
local rotten = food(-0.5, { rotten = true })
local rottenTotals = C.provisions({ container({ rotten }) })
assert(rottenTotals.food == 0 and rottenTotals.unsafe == 1,
    "spoiled food feeds nobody and is counted as unsafe")

-- 4. Unreadable stock contributes nothing and cannot support a group.
local opaque = {
    getFluidContainer = function()
        return { getAmount = function() error("fluid amount unreadable") end }
    end,
}
local unreadableTotals = C.provisions({ container({ full, opaque }) })
assert(unreadableTotals.unreadable == 1,
    "an unreadable entry is counted as unreadable, not as zero stock")
assert(unreadableTotals.water == 1.0, "readable entries still measure")
local noSupport, noWhy = C.support(unreadableTotals, 1)
assert(noSupport == nil and noWhy == "provisions_unreadable",
    "unreadable provisions never pass a sufficiency gate")

-- A non-provision item is readable and worth nothing; it must not poison a read.
local tool = { getCount = function() return 1 end }
local withTool = C.provisions({ container({ tool, full }) })
assert(withTool.unreadable == 0 and withTool.water == 1.0,
    "an ordinary item is readable stock, not an unreadable one")

-- 5. The gate decides on measured quantities at an exact boundary.
local enough = C.provisions({ container({ food(-0.6), food(-0.6),
    bottle(2.0), bottle(2.0) }) })
local supported, supportedWhy = C.support(enough, 2)
assert(supported ~= nil and supported.supported == true and supportedWhy == "supported",
    "two people with exactly their stored need are supported")
assert(supported.foodNeed == 1.2 and supported.waterNeed == 4.0,
    "need is the per-person requirement times the living population")

local shortFood = C.provisions({ container({ food(-0.6), food(-0.5),
    bottle(2.0), bottle(2.0) }) })
local foodRefused, foodWhy = C.support(shortFood, 2)
assert(foodRefused ~= nil and foodRefused.supported == false and foodWhy == "food_short",
    "one unit below the measured need refuses support")

local shortWater = C.provisions({ container({ food(-0.6), food(-0.6),
    bottle(2.0), bottle(1.9) }) })
local waterRefused, waterWhy = C.support(shortWater, 2)
assert(waterRefused ~= nil and waterRefused.supported == false and waterWhy == "water_short",
    "a short measured water amount refuses support")

-- 6. A base's own storage read: no readable container is unknown, not empty.
local noStorageBase = { id = "gh2-base", storage = {} }
local baseTotals = C.baseProvisions(noStorageBase)
assert(baseTotals.unreadable > 0,
    "a base with no readable assigned storage has no authoritative stock")
local baseRefused, baseWhy = C.supportsFormation(noStorageBase, 2)
assert(baseRefused == nil and baseWhy == "provisions_unreadable",
    "unreadable base stock refuses the formation provision gate")
local homeless, homelessWhy = C.supportsFormation(nil, 2)
assert(homeless == nil and homelessWhy == "no_home",
    "a group without a home has no provision evidence to offer")

-- 7. Floor stock belongs to the home that owns the square, and only that home.
local homeArea = { minX = 10, minY = 10, width = 2, height = 1, buildingId = "floor-home" }
local floorHome = { id = "gh3-floor-home", home = homeArea, storage = {} }
setSquare(10, 10, floorSquare({ food(-0.6), bottle(2.0) }))
setSquare(11, 10, floorSquare(nil, { food(-0.5) }))
local neighbour = { id = "gh3-neighbour",
    home = { minX = 20, minY = 20, width = 1, height = 1, buildingId = "neighbour-home" },
    storage = {} }
setSquare(20, 20, floorSquare({ food(-5.0) }))

local floorTotals = C.baseProvisions(floorHome)
assert(floorTotals.unreadable == 0,
    "floor stock in the home's own squares is readable, not unreadable")
assert(floorTotals.food == 1.1 and floorTotals.water == 2.0,
    "floor food contributes its remaining relief once and floor fluid its real amount")
assert(floorTotals.items == 3, "both the floor container and the loose world item are measured")
local floorSupported, floorWhy = C.supportsFormation(floorHome, 1)
assert(floorSupported ~= nil and floorSupported.supported == true and floorWhy == "supported",
    "a home stocked on its own floor now supports its people")

local neighbourTotals = C.baseProvisions(neighbour)
assert(neighbourTotals.food == 5.0,
    "the neighbour's floor stock is measured for the neighbour, not for us")
assert(floorTotals.food == 1.1,
    "measuring another home never adds its floor stock to ours")

-- The home's own floor is added to its assigned shelves, not substituted for them.
local priorResolve = S.resolvePolicy
local shelf = container({ bottle(1.0) })
S.resolvePolicy = function(policy)
    if type(policy) == "table" and policy.container ~= nil then
        return { policy = policy, container = policy.container }
    end
    return nil
end
local mixedHome = { id = "gh3-mixed-home", home = homeArea,
    storage = { { key = "shelf", storageFilterVersion = 1, storageRole = "supplies",
        container = shelf } } }
local mixedHomeTotals = C.baseProvisions(mixedHome)
assert(mixedHomeTotals.food == 1.1 and mixedHomeTotals.water == 3.0,
    "assigned storage and the home's floor stock are summed by one measurement")
S.resolvePolicy = priorResolve
priorResolve = nil

-- An ordinary item on the floor is readable stock, not an unreadable home.
local plainHome = { id = "gh3-plain-home",
    home = { minX = 30, minY = 30, width = 1, height = 1, buildingId = "plain-home" },
    storage = {} }
setSquare(30, 30, floorSquare(nil, { { getCount = function() return 1 end } }))
local plainTotals = C.baseProvisions(plainHome)
assert(plainTotals.unreadable == 0 and plainTotals.food == 0 and plainTotals.water == 0,
    "a readable non-provision floor item is a measured zero, not an unreadable home")

-- A readable empty floor is a measured zero too: empty is not unknown.
local emptyHome = { id = "gh3-empty-home",
    home = { minX = 40, minY = 40, width = 1, height = 1, buildingId = "empty-home" },
    storage = {} }
setSquare(40, 40, floorSquare({}, {}))
local emptyTotals = C.baseProvisions(emptyHome)
assert(emptyTotals.unreadable == 0,
    "a readable empty floor is a measured zero, not an unreadable home")

-- A floor item whose state genuinely cannot be read still refuses the gate.
local brokenHome = { id = "gh3-broken-home",
    home = { minX = 50, minY = 50, width = 1, height = 1, buildingId = "broken-home" },
    storage = {} }
setSquare(50, 50, floorSquare(nil, { {
    getHungChange = function() error("floor item state unreadable") end,
} }))
local brokenTotals = C.baseProvisions(brokenHome)
assert(brokenTotals.unreadable == 1,
    "an unreadable floor item is counted as unreadable stock")
local brokenRefused, brokenWhy = C.supportsFormation(brokenHome, 1)
assert(brokenRefused == nil and brokenWhy == "provisions_unreadable",
    "unreadable floor stock refuses the formation provision gate")

-- A home whose squares are not loaded is unknown, never assumed empty.
local unloadedHome = { id = "gh3-unloaded-home",
    home = { minX = 60, minY = 60, width = 2, height = 1, buildingId = "unloaded-home" },
    storage = {} }
setSquare(60, 60, floorSquare({}, {}))
local unloadedTotals = C.baseProvisions(unloadedHome)
assert(unloadedTotals.unreadable >= 1,
    "a partially unloaded home is unknown, not a measured zero")

-- 8. Nothing is cached: the same boundary call re-measures changed items.
local liveBottle = bottle(2.5)
local liveFood = food(-0.6)
local liveStore = container({ liveFood })
local liveBase = { id = "gh2-live", storage = {} }
local liveFirst = C.support(C.provisions({ container({ liveFood, liveBottle }) }), 1)
assert(liveFirst ~= nil and liveFirst.supported == true, "a full store supports one person")
local drained = C.support(C.provisions({ container({ food(0), bottle(0) }) }), 1)
assert(drained ~= nil and drained.supported == false,
    "the same read after the store is gone refuses support instead of reusing an old figure")

-- 9. Codec probe: quantities are re-measured from item state after a real
--    table-codec reload; no provision figure is persisted to authorize support.
provisionProbe = { container = container({ food(-0.6), bottle(2.0) }),
    food = 0.6, water = 2.0,
    floorBase = floorHome, floorFood = 1.1, floorWater = 2.0 }
provisionReceipt = "food=" .. tostring(enough.food) .. " water=" .. tostring(enough.water)
    .. " need=" .. tostring(supported.foodNeed) .. "/" .. tostring(supported.waterNeed)
    .. " unsafe=" .. tostring(mixed.unsafe)
    .. " unreadable=" .. tostring(unreadableTotals.unreadable)
    .. " partial=" .. tostring(partialTotals.food)
    .. " floorFood=" .. tostring(floorTotals.food)
    .. " floorWater=" .. tostring(floorTotals.water)
    .. " floorItems=" .. tostring(floorTotals.items)
    .. " floorSquares=2 neighbourItems=1 unreadableFloor=1 plainFloor=0 unloadedFloor=1"
provisionPass = true

function verifyProvisionsCodec()
    local capacity = KnoxSettlementCapacity
    local totals = capacity.provisions({ provisionProbe.container })
    assert(totals.food == provisionProbe.food and totals.water == provisionProbe.water
        and totals.unreadable == 0,
        "measured provisions come from real item state after a codec reload")
    local decision, why = capacity.support(totals, 1)
    assert(decision ~= nil and decision.supported == true and why == "supported",
        "the reloaded quantities still decide support on their own numbers")
    local floorAfter = capacity.baseProvisions(provisionProbe.floorBase)
    assert(floorAfter.unreadable == 0 and floorAfter.food == provisionProbe.floorFood
        and floorAfter.water == provisionProbe.floorWater,
        "floor stock re-measures from the home's own squares after a codec reload")
    for _, base in pairs(KnoxPersistence.getBases()) do
        assert(base.provisions == nil,
            "no provision figure is persisted into a home to authorize support later")
    end
end
