-- Sharing food with a self-reserve: the need read, the giver's reserve, the
-- one native remaining-hunger value, and the real transfer/speech owners.
-- Only the engine character/container surface is doubled.
local N = assert(KnoxSurvivorNeeds)

local transferred, spoken = {}, {}
local queue = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = queue
queue.queueTransfer = function(giver, item, source, destination, duration)
    transferred[#transferred + 1] = { giver = giver, item = item,
        source = source, destination = destination, duration = duration }
    return { item = item }
end
KnoxSurvivorDialogue = { sayLines = function(character, id, event, lines, ticks, cooldown)
    spoken[#spoken + 1] = { character = character, id = id, event = event,
        lines = lines, ticks = ticks, cooldown = cooldown }
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

local function food(props)
    props = props or {}
    return {
        IsFood = function() return true end,
        IsInventoryContainer = function() return false end,
        getHungerChange = function() return props.hunger or -0.2 end,
        isRotten = function() return props.rotten == true end,
        isPoison = function() return props.poison == true end,
        getPoisonPower = function() return props.poison == true and 20 or 0 end,
        isbDangerousUncooked = function() return false end,
        isCooked = function() return true end,
        getUnhappyChange = function() return 0 end,
        getContainer = function() return props.container end,
    }
end

local function person(hunger, items)
    local inventory = container(items or {})
    return {
        inventory = inventory,
        getInventory = function() return inventory end,
        getStats = function()
            return { get = function(_, key)
                if hunger == nil then error("hunger unreadable") end
                return hunger
            end }
        end,
    }
end

-- Refusals: no people, an unreadable need on either side, somebody who is not
-- hungry, a giver who must keep their own meal, no safe food, and a portion
-- that would leave the giver hungry.
assert(select(2, N.shareFoodOffer(nil, person(0.9))) == "missing_people")
assert(select(2, N.shareFoodOffer(person(0.1), person(nil, {}))) == "unreadable_need",
    "an unreadable hunger is never a need")
assert(select(2, N.shareFoodOffer(person(nil), person(0.9))) == "unreadable_need",
    "an unreadable giver is never a safe donor")
local notHungry = person(0.2, { food() })
assert(select(2, N.shareFoodOffer(person(0.1), notHungry)) == "no_need")
local hungryGiver = person(0.5, { food() })
assert(select(2, N.shareFoodOffer(hungryGiver, person(0.9))) == "keeping_own_reserve",
    "a hungry survivor keeps their own meal first")
local rotten = food({ rotten = true })
local poisoned = food({ poison = true })
local noFood = person(0.1, { rotten, poisoned })
assert(select(2, N.shareFoodOffer(noFood, person(0.9))) == "no_safe_food",
    "rotten or poisoned food is never shared")
local thin = person(0.40, { food({ hunger = -0.2 }) })
assert(select(2, N.shareFoodOffer(thin, person(0.9))) == "reserve_too_thin",
    "the offer never leaves the giver hungry")

-- A part-eaten portion is its own native remaining-hunger value, counted once.
local partial = person(0.30, { food({ hunger = -0.1 }) })
local offered, why = N.shareFoodOffer(partial, person(0.9))
assert(offered ~= nil and why == "share", "a half portion counts once, not twice")

-- The transfer goes through the existing inventory action owner, not a second
-- inventory path, and one line names the reason.
local giver = person(0.10, { food({ hunger = -0.2 }) })
local target = person(0.9)
local action, reason = N.queueFoodShare(giver, target, "giver-id", 1000, 60)
assert(action ~= nil and reason == "share")
assert(#transferred == 1, "one offer is one transfer, never a stack")
assert(transferred[1].giver == giver and transferred[1].source == giver.inventory
    and transferred[1].destination == target.inventory and transferred[1].duration == 60,
    "the real transfer owner receives the giver, the item and both packs")
assert(#spoken == 1 and spoken[1].event == "share_food"
    and spoken[1].id == "giver-id" and spoken[1].ticks == 1000,
    "the share is named once by the speaker")
assert(string.find(spoken[1].lines[1], "need", 1, true) ~= nil,
    "the line names the reason, not an inventory instruction")

-- The partial offer also transfers once; the earlier full offer is not repeated.
local partialAction = N.queueFoodShare(partial, person(0.9), "giver-id", 2000, 60)
assert(partialAction ~= nil and #transferred == 2 and #spoken == 2)

shareReserveReceipt = "refused=7 share=2 spoken=2 transferred=2 partialOnce=1"
shareReservePass = true
