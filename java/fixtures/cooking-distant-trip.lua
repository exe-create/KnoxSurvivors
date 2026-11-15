-- A resident at the stove may fetch a permitted ingredient from a store that is
-- not adjacent: it walks there through the movement owner, transfers that exact
-- native-selected instance, walks back to the selected surface, and only then
-- hands the assembled meal to the appliance. A refused route on the way is
-- retried inside the leg's existing deadline instead of cancelling the order.
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
local pan, nearFood, farFood, panExtras, stove, stoveMark
local character, bridge, position, moves, transfers, tickResult, nextMoveResult, filterAllowed
local ticks = 100

local function containerOf(items)
    return { getItems = function() return list(items) end,
        contains = function(_, item)
            for _, candidate in ipairs(items) do if candidate == item then return true end end
            return false
        end,
        add = function(_, item) items[#items + 1] = item end,
        remove = function(_, item)
            for i, candidate in ipairs(items) do
                if candidate == item then table.remove(items, i) return end
            end
        end }
end

local function fresh()
    stoveSquare, storeSquare = squareAt(0, 0), squareAt(8, 0)
    stoveApproach, storeApproach = squareAt(1, 0), squareAt(7, 0)
    inventoryItems, storeItems, stoveItems, panExtras = {}, {}, {}, {}
    pan, nearFood, farFood = foodItem("Base.Pan"), foodItem("Base.Tomato"), foodItem("Base.Onion")
    pan.getExtraItems = function() return list(panExtras) end
    inventory, storeContainer, stoveContainer = containerOf(inventoryItems),
        containerOf(storeItems), containerOf(stoveItems)
    stoveContainer.isPowered = function() return true end
    inventoryItems[1], inventoryItems[2] = pan, nearFood
    pan.container, nearFood.container = inventory, inventory
    storeItems[1] = farFood
    farFood.container = storeContainer
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
    position, moves, transfers, tickResult, nextMoveResult, filterAllowed = stoveApproach, {},
        {}, "Working", nil, true
    return { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
        getObjects = function() return list({ stove }) end }
end

local target = { x = 0, y = 0, z = 0, objectIndex = 0, spriteName = "stove", mode = "recipe" }
local selected = {}
local canUseCalls = 0
local recipe = { getUntranslatedName = function() return "Stew" end,
    isCookable = function() return true end,
    getItemsCanBeUse = function(_, who, baseItem, containers)
        canUseCalls = canUseCalls + 1
        return list(selected)
    end,
    isResultItem = function(_, item) return item == pan end }

KnoxBaseStorage = { policies = function() return { { key = "pantry", x = 8, y = 0, z = 0 } } end,
    resolvePolicy = function() return { container = storeContainer, square = storeSquare } end,
    filterAllowsItem = function() return filterAllowed end }
KnoxSurvivorNeeds = { isSafeFood = function() return true end }
KnoxSettings = nil
KnoxBaseManager = { containsSquare = function() return true end }
ArrayList = { new = function() return list({}) end }
RecipeManager = { getEvolvedRecipe = function() return list({ recipe }) end }
instanceof = function(object, name) return object == stove and name == "IsoStove" end
AdjacentFreeTileFinder = { Find = function(square)
    if square == storeSquare then return storeApproach end
    if square == stoveSquare then return stoveApproach end
    return nil
end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    if z ~= 0 then return nil end
    if x == 0 and y == 0 then return stoveSquare end
    if x == 8 and y == 0 then return storeSquare end
    if x == 1 and y == 0 then return stoveApproach end
    if x == 7 and y == 0 then return storeApproach end
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
    -- The native add action only changes the pan when the queue admits it.
    if action.ingredient ~= nil then panExtras[#panExtras + 1] = action.ingredient end
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
    ISTimedActionQueue.getTimedActionQueue(character).queue[#transfers] = action
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

local function completeTransfer()
    local action = transfers[#transfers]
    assert(action ~= nil, "a transfer was queued")
    action.source:remove(action.item)
    action.destination:add(action.item)
    action.item.container = action.destination
    ISTimedActionQueue.getTimedActionQueue(character).queue = {}
end

local function start()
    fresh()
    selected = { nearFood, farFood }
    canUseCalls = 0
    local base = { id = "cooking-base" }
    local plan, reason = Cooking.begin(base, target, character, "cooker", nil)
    assert(plan ~= nil, "the installed recipe selects a distant stored ingredient: " .. tostring(reason))
    assert(plan.phase == "collect_recipe" and plan.sourceIndex == 1,
        "the native selection owns the ingredient phases")
    assert(#plan.recipeSources == 3 and plan.recipeSources[3].item == farFood
        and plan.recipeSources[3].square == storeSquare,
        "the exact item instance in the non-adjacent store is named with its square")
    return base, plan
end

local function advanceToStore(base, plan)
    assert(Cooking.step(plan, character, base, bridge, ticks + 1) == "working"
        and plan.sourceIndex == 2, "the carried pan entry needs no walk")
    assert(Cooking.step(plan, character, base, bridge, ticks + 2) == "working"
        and plan.sourceIndex == 3, "the carried ingredient entry needs no walk")
end

-- 1. The distant ingredient: walk there, transfer that exact instance, walk
--    back to the selected surface, and hand the meal to the appliance.
local base, plan = start()
advanceToStore(base, plan)
assert(Cooking.step(plan, character, base, bridge, ticks + 3) == "working"
    and plan.phase == "move" and plan.afterMove == "collect_recipe"
    and #moves == 1 and moves[1] == storeApproach,
    "an ingredient out of reach starts a real trip to its own square")
tickResult = "FailedObstacle:MOVING"
assert(Cooking.step(plan, character, base, bridge, ticks + 4) == "working"
    and plan.phase == "collect_recipe",
    "an obstacle on the ingredient trip is retried, not a cancelled order")
assert(Cooking.step(plan, character, base, bridge, ticks + 5) == "working"
    and plan.phase == "move" and #moves == 2 and moves[2] == storeApproach,
    "the same approach is re-issued after the movement owner cools the edge")
tickResult = "Succeeded"
position = storeApproach
assert(Cooking.step(plan, character, base, bridge, ticks + 6) == "working"
    and plan.phase == "collect_recipe", "arrival hands the leg back to collection")
assert(Cooking.step(plan, character, base, bridge, ticks + 7) == "working"
    and plan.phase == "transfer" and #transfers == 1,
    "the store transfer is queued from the store itself")
assert(transfers[1].item == farFood and transfers[1].source == storeContainer
    and transfers[1].destination == inventory,
    "only the native-selected instance moves, and it moves into the survivor")
completeTransfer()
assert(Cooking.step(plan, character, base, bridge, ticks + 8) == "working"
    and plan.sourceIndex == 4 and farFood:getContainer() == inventory,
    "one transfer at a time advances the same ingredient list")
local beforeAssemble = canUseCalls
local trace = {}
for step = 9, 12 do
    local outcome, reason = Cooking.step(plan, character, base, bridge, ticks + step)
    trace[#trace + 1] = step .. "=" .. tostring(outcome) .. "/" .. tostring(reason)
        .. "/" .. tostring(plan.phase) .. "/extras=" .. tostring(#panExtras)

    if plan.phase == "recipe_action" then
        ISTimedActionQueue.getTimedActionQueue(character).queue = {}
    end
end
assert(canUseCalls > beforeAssemble,
    "the installed recipe is asked again before the meal is assembled: "
    .. table.concat(trace, " "))
assert(#panExtras == 2, "both ingredients were added only after their trips")
assert(Cooking.step(plan, character, base, bridge, ticks + 13) == "working"
    and plan.phase == "move" and plan.afterMove == "load" and #moves == 3
    and moves[3] == stoveApproach,
    "the return leg walks back to the selected surface")
tickResult = "Succeeded"
position = stoveApproach
assert(Cooking.step(plan, character, base, bridge, ticks + 14) == "working"
    and plan.phase == "load" and #transfers == 1,
    "return arrival resumes the load phase at the stove")
assert(Cooking.step(plan, character, base, bridge, ticks + 15) == "working"
    and plan.phase == "transfer" and #transfers == 2,
    "the assembled meal is handed to the appliance after the trip")
assert(transfers[2].item == pan and transfers[2].destination == stoveContainer
    and stoveMark.KnoxCooking ~= nil,
    "the appliance receives the assembled meal and marks it as cooking")
Cooking.cancel(plan, character)

-- 2. A refused route at the tile owner is retried, and the trip still arrives.
base, plan = start()
advanceToStore(base, plan)
nextMoveResult = "FailedDutyAreaRoute"
local refusedAt = ticks + 20
assert(Cooking.step(plan, character, base, bridge, refusedAt) == "working"
    and plan.phase == "collect_recipe" and plan.moveStarted == refusedAt,
    "a route refusal on the trip is retried instead of cancelling the cook")
assert(Cooking.step(plan, character, base, bridge, refusedAt + 1) == "working"
    and plan.phase == "move" and #moves == 2,
    "the trip re-issues the refused approach once the owner admits it")
Cooking.cancel(plan, character)

-- 3. A trip that cannot reach the store still ends by name at its deadline.
base, plan = start()
advanceToStore(base, plan)
assert(Cooking.step(plan, character, base, bridge, ticks + 30) == "working"
    and plan.phase == "move", "the trip starts")
plan.moveStarted = ticks + 30 - 1801
tickResult = "FailedObstacle:MOVING"
local outcome, reason = Cooking.step(plan, character, base, bridge, ticks + 31)
assert(outcome == "failed" and tostring(reason):find("kitchen_route:", 1, true) == 1,
    "a trip past its deadline fails by name instead of walking forever")
Cooking.cancel(plan, character)

KnoxInventoryActions = originalActions
for name, value in pairs(saved) do _G[name] = value end
print("Cooking distant trip PASS distantWalk=true instanceTransfer=true obstacleRetry=true "
    .. "routeRefusalRetry=true returnLeg=true deadlineFail=true")
