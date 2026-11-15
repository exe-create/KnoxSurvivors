-- A cook at the stove may need an ingredient from a store one floor up of the
-- same site. Selection already admits floors within reach of the policy; the
-- collect leg must walk through the movement owner to an approach on the
-- store's own floor and only then take that exact instance. A store floor the
-- approach owner cannot name is a refusal by name, never a remote pickup.
local Cooking = assert(KnoxBaseCooking)
local saved = {}
for _, name in ipairs({ "KnoxBaseStorage", "KnoxSurvivorNeeds", "KnoxSettings", "KnoxBaseManager",
    "KnoxInventoryActions", "AdjacentFreeTileFinder", "ArrayList", "RecipeManager", "instanceof",
    "getCell", "ISTimedActionQueue", "ISAddItemInRecipe" }) do saved[name] = rawget(_G, name) end

local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end,
        add = function(_, value) values[#values + 1] = value end,
        contains = function(_, value)
            for _, candidate in ipairs(values) do if candidate == value then return true end end
            return false
        end,
        remove = function(_, value)
            for i, candidate in ipairs(values) do
                if candidate == value then table.remove(values, i) return end
            end
        end,
        isEmpty = function() return #values == 0 end }
end
local function squareAt(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z or 0 end, isSomethingTo = function() return false end,
        getObjects = function() return list({}) end }
end
local function foodItem(fullType)
    local item = { getFullType = function() return fullType end, IsFood = function() return true end,
        isCookable = function() return true end, isCooked = function() return false end,
        isBurnt = function() return false end, isRotten = function() return false end,
        isPoison = function() return false end, getPoisonPower = function() return 0 end,
        isFavorite = function() return false end, getHungerChange = function() return -0.2 end,
        getMetalValue = function() return 0 end, getOnCooked = function() return "" end,
        isbDangerousUncooked = function() return false end,
        getMinutesToCook = function() return 30 end, getMinutesToBurn = function() return 60 end,
        getCookingTime = function() return 0 end,
        getReplaceOnCooked = function() return list({}) end,
        getID = function() return fullType end }
    item.getContainer = function() return item.container end
    return item
end

local stoveSquare, storeSquare, stoveApproach, storeApproach
local inventory, storeContainer, stoveContainer, inventoryItems, storeItems, stoveItems
local pan, nearFood, upFood, panExtras, stove, stoveMark
local character, bridge, position, moves, transfers, tickResult, nextMoveResult, filterAllowed
local reachableStore

local function containerOf(values)
    return { getItems = function() return list(values) end,
        contains = function(_, item)
            for _, candidate in ipairs(values) do if candidate == item then return true end end
            return false
        end,
        add = function(_, item) values[#values + 1] = item end,
        remove = function(_, item)
            for i, candidate in ipairs(values) do
                if candidate == item then table.remove(values, i) return end
            end
        end }
end

local function fresh()
    stoveSquare, stoveApproach = squareAt(0, 0, 0), squareAt(1, 0, 0)
    storeSquare, storeApproach = squareAt(8, 0, 1), squareAt(7, 0, 1)
    inventoryItems, storeItems, stoveItems, panExtras = {}, {}, {}, {}
    pan, nearFood, upFood = foodItem("Base.Pan"), foodItem("Base.Tomato"), foodItem("Base.Onion")
    pan.getExtraItems = function() return list(panExtras) end
    inventory, storeContainer, stoveContainer = containerOf(inventoryItems),
        containerOf(storeItems), containerOf(stoveItems)
    stoveContainer.isPowered = function() return true end
    inventoryItems[1], inventoryItems[2] = pan, nearFood
    pan.container, nearFood.container = inventory, inventory
    storeItems[1] = upFood
    upFood.container = storeContainer
    stoveMark = {}
    stove = { getObjectIndex = function() return 0 end, getSquare = function() return stoveSquare end,
        getContainer = function() return stoveContainer end,
        isBroken = function() return false end, isMicrowave = function() return false end,
        Activated = function() return false end, getModData = function() return stoveMark end,
        getSprite = function() return { getName = function() return "stove" end } end,
        getCurrentTemperature = function() return 0 end,
        PlayToggleSound = function() end, Toggle = function() end,
        setTimer = function() end, setMaxTemperature = function() end }
    stoveSquare.getObjects = function() return list({ stove }) end
    position, moves, transfers, tickResult, nextMoveResult, filterAllowed
        = stoveApproach, {}, {}, "Working", nil, true
end

local target = { x = 0, y = 0, z = 0, objectIndex = 0, spriteName = "stove", mode = "recipe" }
local selected = {}
local recipe = { getUntranslatedName = function() return "Stew" end,
    isCookable = function() return true end,
    getItemsCanBeUse = function(_, who, baseItem, containers) return list(selected) end,
    isResultItem = function(_, item) return item == pan end }

KnoxBaseStorage = { policies = function() return { { key = "upstairs", x = 8, y = 0, z = 1 } } end,
    resolvePolicy = function() return { container = storeContainer, square = storeSquare } end,
    filterAllowsItem = function() return filterAllowed end }
KnoxSurvivorNeeds = { isSafeFood = function() return true end }
KnoxSettings = nil
KnoxBaseManager = { containsSquare = function() return true end }
ArrayList = { new = function() return list({}) end }
RecipeManager = { getEvolvedRecipe = function() return list({ recipe }) end }
instanceof = function(object, name) return object == stove and name == "IsoStove" end
AdjacentFreeTileFinder = { Find = function(square)
    if square == storeSquare then
        if reachableStore == false then return nil end
        return storeApproach
    end
    if square == stoveSquare then return stoveApproach end
    return nil
end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    if z == 0 then
        if x == 0 and y == 0 then return stoveSquare end
        if x == 1 and y == 0 then return stoveApproach end
    elseif z == 1 then
        if x == 8 and y == 0 then return storeSquare end
        if x == 7 and y == 0 then return storeApproach end
    else
        return nil
    end
    return squareAt(x, y, z)
end } end
ISTimedActionQueue = { queues = {} }
ISTimedActionQueue.getTimedActionQueue = function(who)
    local queue = ISTimedActionQueue.queues[who]
    if queue == nil then queue = { queue = {}, indexOf = function() return -1 end }
        ISTimedActionQueue.queues[who] = queue end
    return queue
end
ISTimedActionQueue.add = function(action)
    local queue = { queue = { action }, indexOf = function() return -1 end }
    ISTimedActionQueue.queues[character] = queue
    return queue
end
ISAddItemInRecipe = { new = function(_, who, recipeObject, baseItem, used)
    return { baseItem = baseItem, ingredient = used }
end }
local originalActions = KnoxInventoryActions
KnoxInventoryActions = { queueTransfer = function(_, item, source, destination)
    local action = { item = item, source = source, destination = destination }
    transfers[#transfers + 1] = action
    return action
end }

character = { getCurrentSquare = function() return position end,
    getInventory = function() return inventory end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    faceThisObject = function() end }
bridge = { moveNpc = function(_, id, square)
        moves[#moves + 1] = square
        local result = nextMoveResult or "MOVE_STARTED"
        nextMoveResult = nil
        return result
    end,
    tickNpc = function() return tickResult end,
    cancelNpcMove = function() end }

local function start()
    fresh()
    selected = { nearFood, upFood }
    local base = { id = "cooking-cross-base" }
    local plan, reason = Cooking.begin(base, target, character, "cooker", nil)
    assert(plan ~= nil, "the installed recipe selects a stored ingredient: " .. tostring(reason))
    assert(#plan.recipeSources == 3 and plan.recipeSources[3].item == upFood
        and plan.recipeSources[3].square == storeSquare
        and plan.recipeSources[3].square:getZ() == 1,
        "the exact item stored one floor up is named with its own floor")
    return base, plan
end

local function advanceCarried(base, plan, ticks)
    assert(Cooking.step(plan, character, base, bridge, ticks + 1) == "working"
        and plan.sourceIndex == 2, "the carried pan entry needs no walk")
    assert(Cooking.step(plan, character, base, bridge, ticks + 2) == "working"
        and plan.sourceIndex == 3, "the carried ingredient entry needs no walk")
    assert(#moves == 0 and #transfers == 0,
        "carried entries are used where the survivor stands, without a trip")
end

-- 1. The store one floor up: the cook walks to that floor, and only standing
--    there does the ordinary nearby transfer take the exact instance.
reachableStore = true
local base, plan = start()
advanceCarried(base, plan, 100)
assert(Cooking.step(plan, character, base, bridge, 110) == "working"
    and plan.phase == "move" and plan.afterMove == "collect_recipe",
    "an ingredient stored one floor up starts a trip to that floor's approach")
assert(#moves == 1 and moves[1] == storeApproach and moves[1]:getZ() == 1,
    "the trip targets the store's own floor, not the appliance floor")
assert(#transfers == 0 and upFood:getContainer() == storeContainer
    and position:getZ() == 0,
    "nothing is taken from the other floor before the survivor walks there")
assert(Cooking.step(plan, character, base, bridge, 111) == "working"
    and plan.phase == "move" and #transfers == 0,
    "the trip is still in progress on the lower floor")
tickResult = "Succeeded"
position = storeApproach
assert(Cooking.step(plan, character, base, bridge, 112) == "working"
    and plan.phase == "collect_recipe", "arrival hands the leg back to collection")
assert(Cooking.step(plan, character, base, bridge, 113) == "working"
    and plan.phase == "transfer" and #transfers == 1
    and transfers[1].item == upFood and transfers[1].source == storeContainer
    and transfers[1].destination == inventory,
    "standing on the store's floor, the ordinary nearby transfer takes that exact item")
Cooking.cancel(plan, character)

-- 2. A store floor the approach owner cannot name is a refusal by name: no
--    remote pickup, nothing consumed, and the plan is released by the caller.
reachableStore = false
base, plan = start()
advanceCarried(base, plan, 200)
local outcome, reason = Cooking.step(plan, character, base, bridge, 210)
assert(outcome == "failed" and reason == "kitchen_unreachable",
    "a store floor the approach owner cannot reach is refused by name (got "
        .. tostring(outcome) .. "/" .. tostring(reason) .. "/" .. tostring(plan.phase)
        .. "/sourceIndex=" .. tostring(plan.sourceIndex)
        .. "/moves=" .. tostring(#moves) .. "/z=" .. tostring(position:getZ()) .. ")")
assert(#transfers == 0 and upFood:getContainer() == storeContainer
    and #storeItems == 1 and position:getZ() == 0,
    "an unreachable other-floor store takes and consumes nothing")
Cooking.cancel(plan, character)

KnoxInventoryActions = originalActions
for name, value in pairs(saved) do _G[name] = value end
print("Cooking cross-floor trip PASS walkToStoreFloor=true noEarlyTransfer=true "
    .. "nearbyTransferOnFloor=true unreachableByName=true consumed=0")
