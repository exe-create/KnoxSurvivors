-- Water and medical sharing: actual fluid amount after the drinking safety
-- checks, and medical supply only through MedicalSupplies.plan. Only the engine
-- character/container/fluid surface and the external supply planner are doubled.
local N = assert(KnoxSurvivorNeeds)

Fluid = { TaintedWater = "tainted", Water = "water" }

local transferred, spoken = {}, {}
local queue = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = queue
queue.queueTransfer = function(giver, item, source, destination, duration)
    transferred[#transferred + 1] = { giver = giver, item = item,
        source = source, destination = destination, duration = duration }
    return { item = item }
end
KnoxSurvivorDialogue = { sayLines = function(character, id, event, lines, ticks, cooldown)
    spoken[#spoken + 1] = { id = id, event = event, lines = lines }
    return true, lines[1]
end }

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

local function fluid(amount, tainted, broken)
    return function()
        if broken then error("fluid unreadable") end
        return {
            isEmpty = function() return amount <= 0 end,
            isWaterSource = function() return true end,
            getAmount = function() return amount end,
            contains = function(_, tag) return tainted and tag == "tainted" or false end,
        }
    end
end

local function bottle(amount, tainted, broken, opts)
    opts = opts or {}
    local fluidState = {
        isEmpty = function()
            if opts.empty ~= nil then return opts.empty end
            return amount <= 0
        end,
        isWaterSource = function() return true end,
        getAmount = function()
            if broken then error("fluid unreadable") end
            return amount
        end,
        contains = function(_, tag) return tainted and tag == "tainted" or false end,
    }
    return {
        IsFood = function() return false end,
        IsInventoryContainer = function() return false end,
        getFluidContainer = function() return fluidState end,
        -- A nominal stack count is deliberately present and must never be used
        -- as the amount of drinkable fluid.
        stackCount = 99,
    }
end

local function person(stats, items)
    local inventory = container(items or {})
    return {
        inventory = inventory,
        getInventory = function() return inventory end,
        getStats = function()
            return { get = function(_, key)
                local value = stats[key]
                if value == nil then error("stat unreadable: " .. tostring(key)) end
                return value
            end }
        end,
        getBodyDamage = function()
            return { getNumPartsBleeding = function()
                local value = stats.bleeding
                if value == nil then error("wounds unreadable") end
                return value
            end }
        end,
        plan = stats.plan,
    }
end

local HUNGER, THIRST = CharacterStat.HUNGER, CharacterStat.THIRST
local function stats(hunger, thirst, bleeding, plan)
    return { [HUNGER] = hunger, [THIRST] = thirst, bleeding = bleeding, plan = plan }
end

-- Refusals shared with the food half, plus the fluid-specific ones.
assert(select(2, N.shareWaterOffer(nil, person(stats(0, 0.9, 0)))) == "missing_people")
assert(select(2, N.shareWaterOffer(person(stats(0, 0.1, 0), { bottle(4) }),
    person(stats(0, nil, 0)))) == "unreadable_need", "an unreadable thirst is never a need")
assert(select(2, N.shareWaterOffer(person(stats(0, 0.1, 0), { bottle(4) }),
    person(stats(0, 0.2, 0)))) == "no_need")
assert(select(2, N.shareWaterOffer(person(stats(0, 0.5, 0), { bottle(4), bottle(2) }),
    person(stats(0, 0.9, 0)))) == "keeping_own_reserve",
    "a thirsty survivor keeps their own drink first")
assert(select(2, N.shareWaterOffer(person(stats(0, 0.1, 0), {}),
    person(stats(0, 0.9, 0)))) == "no_safe_water")

-- An actual amount is required after the drinking checks: tainted, empty and
-- unreadable containers are all refused even when the item is present.
local taintedOnly = person(stats(0, 0.1, 0), { bottle(4, true), bottle(3, true) })
assert(select(2, N.shareWaterOffer(taintedOnly, person(stats(0, 0.9, 0))))
    == "no_safe_water", "tainted water is never shared, however full")
local empty = person(stats(0, 0.1, 0), { bottle(0), bottle(0) })
assert(select(2, N.shareWaterOffer(empty, person(stats(0, 0.9, 0)))) == "no_safe_water",
    "an empty bottle is not water")
local unreadable = person(stats(0, 0.1, 0), { bottle(4, false, true), bottle(4) })
assert(select(2, N.shareWaterOffer(unreadable, person(stats(0, 0.9, 0))))
    == "unreadable_water", "an unreadable fluid is never a safe offer")
-- A container that does not report empty but holds no actual amount is still
-- not water: the real amount decides, never the item's own claim or its count.
local lyingEmpty = person(stats(0, 0.1, 0), { bottle(0, false, false, { empty = false }) })
assert(select(2, N.shareWaterOffer(lyingEmpty, person(stats(0, 0.9, 0))))
    == "unreadable_water", "a container with no actual amount is not water")
local single = person(stats(0, 0.1, 0), { bottle(4) })
assert(select(2, N.shareWaterOffer(single, person(stats(0, 0.9, 0)))) == "last_bottle",
    "the giver keeps a bottle of their own")

-- A clean full bottle with a spare behind it is the one offer, measured from
-- the container and moved by the production transfer owner.
local small, big = bottle(2), bottle(4)
local giver = person(stats(0, 0.10, 0), { small, big })
local target = person(stats(0, 0.9, 0))
local action, reason = N.queueWaterShare(giver, target, "giver-id", 500, 60)
assert(action ~= nil and reason == "share")
assert(transferred[1].item == big,
    "the fuller bottle is the one measured and offered")
assert(#transferred == 1, "one bottle offer is one transfer")
assert(transferred[1].giver == giver and transferred[1].source == giver.inventory
    and transferred[1].destination == target.inventory and transferred[1].item ~= nil,
    "the real transfer owner receives the bottle and both packs")
assert(#spoken == 1 and spoken[1].event == "share_water"
    and string.find(spoken[1].lines[1], "bottle", 1, true) ~= nil,
    "the water share names the reason once")

-- Medical supply is the existing planner's named treatment, never a guess.
local supplies = { plan = function(character) return character.plan or { kind = "search_world" } end }
KnoxMedicalSupplies = supplies
assert(select(2, N.shareMedicalOffer(person(stats(0, 0.1, 0)), person(stats(0, 0.1, 0))))
    == "no_need", "an uninjured neighbour is not a medical need")
assert(select(2, N.shareMedicalOffer(person(stats(0, 0.1, 0)), person(stats(0, 0.1, nil))))
    == "unreadable_need", "an unreadable wound is never a medical need")
assert(select(2, N.shareMedicalOffer(person(stats(0, 0.1, 1)), person(stats(0, 0.1, 2))))
    == "keeping_own_reserve", "a bleeding survivor keeps their own dressing")
local searching = person(stats(0, 0.1, 0), {})
searching.plan = { kind = "search_world" }
assert(select(2, N.shareMedicalOffer(searching, person(stats(0, 0.1, 2))))
    == "no_safe_supply", "a search plan is not proof that medicine exists")
local noPlanner = rawget(_G, "KnoxMedicalSupplies")
KnoxMedicalSupplies = nil
assert(select(2, N.shareMedicalOffer(person(stats(0, 0.1, 0)), person(stats(0, 0.1, 2))))
    == "supply_unreadable", "an unreadable stock owner never counts as supply")
KnoxMedicalSupplies = noPlanner

local dressing = { IsFood = function() return false end, IsInventoryContainer = function() return false end }
local donor = person(stats(0, 0.1, 0), { dressing })
donor.plan = { kind = "use_treatment", item = dressing }
local medicalAction, medicalReason = N.queueMedicalShare(donor,
    person(stats(0, 0.1, 2)), "donor-id", 900, 60)
assert(medicalAction ~= nil and medicalReason == "share")
assert(#transferred == 2 and transferred[2].item == dressing
    and transferred[2].destination ~= nil, "the dressing moves through the same owner")
assert(#spoken == 2 and spoken[2].event == "share_medical"
    and string.find(spoken[2].lines[1], "take this", 1, true) ~= nil,
    "the medical share names the reason once")

shareSuppliesReceipt = "waterRefused=7 water=1 medRefused=4 med=1 spoken=2 transferred=2 fluidMeasured=true"
shareSuppliesPass = true
