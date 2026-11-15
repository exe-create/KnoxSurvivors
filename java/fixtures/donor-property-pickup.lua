-- A world item another resident owns is not free stock: the one pick-up owner
-- refuses a protected item by name, leaves it and its marker untouched, and
-- still collects ordinary floor items and the base's own stock.
local A = assert(KnoxInventoryActions, "the pickup owner is loaded")
local previousGrab, previousQueue = ISGrabItemAction, ISTimedActionQueue
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")

ISGrabItemAction = {}
function ISGrabItemAction:derive(name)
    return setmetatable({ className = name }, { __index = self })
end
-- queueGrab calls ISGrabItemAction.new(klass, character, object, duration).
function ISGrabItemAction.new(klass, character, worldObject, duration)
    return { klass = klass, character = character, object = worldObject,
        maxTime = duration }
end
local queued = {}
ISTimedActionQueue = { queues = {} }
ISTimedActionQueue.add = function(action)
    local queue = { queue = { action } }
    ISTimedActionQueue.queues[action.character] = queue
    queued[#queued + 1] = action
    return queue
end
KnoxSurvivorRuntime = { idForCharacter = function() return "resident" end }

local function item(fields)
    local self = { favourite = false, container = nil }
    for key, value in pairs(fields or {}) do self[key] = value end
    self.isFavorite = function() return self.favourite end
    self.getFullType = function() return "Base.FloorItem" end
    self.getContainer = function() return self.container end
    return self
end
local function world(entity, square)
    return { getItem = function() return entity end,
        getSquare = function() return square end }
end
local square = { getX = function() return 10 end, getY = function() return 12 end,
    getZ = function() return 0 end,
    getWorldObjects = function() return { size = function() return 1 end,
        get = function() return current end } end }
local resident = { getInventory = function() return { } end }

-- 1. An ordinary floor item is free to collect.
local plain = item()
local current = world(plain, square)
local firstCharacter = { id = "first" }
local action, reason = A.queueGrab(firstCharacter, current)
assert(action ~= nil and tostring(reason) == "queued",
    "an ordinary world item is free to collect, got " .. tostring(reason))
assert(action.character == firstCharacter and action.object == current,
    "the queued pick-up belongs to this survivor and this world object")

-- 2. The player's protected item is refused by name, and stays put.
queued = {}
local protected = item({ favourite = true })
current = world(protected, square)
local secondCharacter = { id = "second" }
local refused, refusal = A.queueGrab(secondCharacter, current)
assert(refused == nil and tostring(refusal) == "property_favourite_owned",
    "a favourite world item is refused by name, got " .. tostring(refusal))

-- 3. A refused take leaves the marker and the floor untouched.
local markerReads = 0
local originalIsFavorite = protected.isFavorite
protected.isFavorite = function() markerReads = markerReads + 1 return true end
local again, againReason = A.queueGrab({ id = "third" }, current)
assert(again == nil and tostring(againReason) == "property_favourite_owned"
    and #queued == 0,
    "a refused take leaves the item and its protection untouched")
assert(protected:isFavorite() == true,
    "the protection marker survives every refused take")
assert(ISTimedActionQueue.queues[secondCharacter] == nil
    and ISTimedActionQueue.queues and #queued == 0,
    "no pick-up action is admitted for a refused take")
protected.isFavorite = originalIsFavorite
assert(markerReads > 0, "the gate reads the real protection marker")

-- 4. Settlement stock and the resident's own floor item stay collectable.
local stock = item({ container = nil })
local stockData = { KnoxBaseProvision = "home" }
stock.getModData = function() return stockData end
current = world(stock, square)
local stockAction, stockReason = A.queueGrab({ id = "resident" }, current)
assert(stockAction ~= nil and tostring(stockReason) == "queued",
    "settlement stock stays collectable, got " .. tostring(stockReason))
assert(stockData.KnoxBaseProvision == "home",
    "collecting stock never rewrites its allocation")

-- 5. A caller's own guard is still wired to the native action.
local guard = function() return false end
current = world(item(), square)
local guarded = A.queueGrab({ id = "guarded" }, current, guard)
assert(guarded ~= nil and guarded.knoxGrabGuard == guard,
    "the caller's own guard still travels with the pick-up action")

ISGrabItemAction, ISTimedActionQueue = previousGrab, previousQueue
_G.KnoxSurvivorRuntime = previousRuntime
print("Donor property pickup PASS plain=true favouriteRefused=true markerKept=true stock=true guard=true")
