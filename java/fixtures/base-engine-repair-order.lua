-- Player-issued engine repair must use the same admission and executor as the
-- autonomous repair task. This drives Engine.order against a real base square,
-- a stationary vehicle, a qualified resident, a wrench and Engine Parts.
local Engine = assert(KnoxBaseEngineRepairs, "engine repair owner missing")
assert(type(Engine.order) == "function", "player engine order missing")
assert(type(Engine.assess) == "function", "engine admission missing")
assert(type(Engine.describe) == "function", "engine refusal text missing")
assert(type(Engine.addVehicleContextMenu) == "function", "base-vehicle engine menu missing")

local prior = {
    KnoxSettings = KnoxSettings, KnoxActivityFeed = KnoxActivityFeed,
    KnoxSurvivorRuntime = KnoxSurvivorRuntime, KnoxPersistence = KnoxPersistence,
    KnoxBaseStorage = KnoxBaseStorage, ISRepairEngine = ISRepairEngine,
    ISTimedActionQueue = ISTimedActionQueue, ISOpenVehicleDoor = ISOpenVehicleDoor,
    ISCloseVehicleDoor = ISCloseVehicleDoor, Perks = Perks, ItemTag = ItemTag,
    getCell = getCell, KnoxBaseManager = KnoxBaseManager,
    KnoxCompanionService = KnoxCompanionService, ISContextMenu = ISContextMenu,
    getSpecificPlayer = getSpecificPlayer,
}

local player = {}
local setting = false
local feed = {}
KnoxSettings = {
    enabled = function() return true end,
    enableExperimentalEngineWork = function() return setting end,
}
KnoxActivityFeed = { event = function(text) feed[#feed + 1] = tostring(text) end }
KnoxSurvivorRuntime = {
    idForCharacter = function() return "r1" end,
    getCharacter = function() return nil end,
}
KnoxPersistence = {
    getBaseResidentIds = function() return { "r1" } end,
    getSurvivorIdentity = function() return { forename = "Ada", surname = "Reyes" } end,
}
KnoxBaseStorage = { requirementsAvailable = function() return true end }
Perks = { Mechanics = "Mechanics" }
ItemTag = { WRENCH = "WRENCH" }

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end
local inventoryItems = {}
local inventory = { getItems = function() return list(inventoryItems) end }
local character = {
    getPerkLevel = function() return 5 end,
    getInventory = function() return inventory end,
}
local base = { id = "base1", territory = { minX = 0, minY = 0, maxX = 10, maxY = 10, z = 0 } }
local carX, carY = 2, 2
local carSquare = {
    getX = function() return carX end,
    getY = function() return carY end,
    getZ = function() return 0 end,
    canStand = function() return true end,
}
local hoodDoor = { isLocked = function() return false end, isOpen = function() return true end }
local hood = { getInventoryItem = function() return {} end, getDoor = function() return hoodDoor end }
local part = { getCondition = function() return 40 end, getArea = function() return { x = 2, y = 2, z = 0 } end }
local script = { getEngineRepairLevel = function() return 3 end, getName = function() return "car" end }
local car = {}
car.getSqlId = function() return 7 end
car.getCurrentSpeedKmHour = function() return 0 end
car.isEngineRunning = function() return false end
car.getPartById = function(_, id)
    if id == "Engine" then return part end
    if id == "EngineDoor" then return hood end
    return nil
end
car.getScript = function() return script end
car.getSquareForArea = function() return carSquare end
car.getSquare = function() return carSquare end
car.isInArea = function() return true end
car.getX = function() return carX end
car.getY = function() return carY end

local wrenchItem = {
    getFullType = function() return "Base.Wrench" end,
    isBroken = function() return false end,
    hasTag = function() return true end,
}
local partsItem = {
    getFullType = function() return "Base.EngineParts" end,
    isBroken = function() return false end,
}
getCell = function() return { getVehicles = function() return list({ car }) end } end

local queue = nil
ISRepairEngine = {
    new = function(_, who, enginePart, tool)
        return { character = who, part = enginePart, tool = tool }
    end,
}
ISTimedActionQueue = {
    queues = {},
    add = function(action)
        queue = { action = action }
        ISTimedActionQueue.queues[action.character] = queue
        return queue
    end,
}
ISOpenVehicleDoor, ISCloseVehicleDoor = nil, nil

-- Off: the order refuses with the experimental setting named and speaks it.
setting = false
inventoryItems = { wrenchItem, partsItem }
local ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "engine_work_disabled",
    "setting off refuses the order, got " .. tostring(reason))
assert(feed[#feed]:find("Experimental resident engine repairs", 1, true) ~= nil,
    "setting off speaks the refusal")

-- On, but the resident is not qualified.
setting = true
character.getPerkLevel = function() return 1 end
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "mechanics_skill_too_low",
    "low Mechanics refuses, got " .. tostring(reason))
character.getPerkLevel = function() return 5 end

-- Missing wrench, then missing parts.
inventoryItems = {}
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "missing_wrench", "missing wrench refuses, got " .. tostring(reason))
inventoryItems = { wrenchItem }
KnoxBaseStorage.requirementsAvailable = function() return false end
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "missing_engine_parts", "missing parts refuses, got " .. tostring(reason))
KnoxBaseStorage.requirementsAvailable = function() return true end
inventoryItems = { wrenchItem, partsItem }

-- A resident who does not belong to this base is refused before admission.
KnoxPersistence.getBaseResidentIds = function() return {} end
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "not_base_resident",
    "non-resident refuses, got " .. tostring(reason))
KnoxPersistence.getBaseResidentIds = function() return { "r1" } end

-- A running engine is refused.
car.isEngineRunning = function() return true end
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "engine_running", "running engine refuses, got " .. tostring(reason))
car.isEngineRunning = function() return false end

-- Moving vehicle.
car.getCurrentSpeedKmHour = function() return 2 end
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "vehicle_moving", "moving vehicle refuses, got " .. tostring(reason))
car.getCurrentSpeedKmHour = function() return 0 end

-- Outside the base territory.
carX = 40
ok, reason = Engine.order(player, base, car, character)
assert(ok == false and reason == "vehicle_outside_base",
    "out-of-territory vehicle refuses, got " .. tostring(reason))
carX = 2

-- Every refusal reason has player-facing text.
for _, code in ipairs({
    "engine_work_disabled", "vehicle_moving", "engine_running",
    "mechanics_skill_too_low", "missing_wrench", "missing_engine_parts",
    "vehicle_outside_base", "engine_area_outside_base", "not_base_resident",
}) do
    assert(type(Engine.describe(code)) == "string" and #Engine.describe(code) > 0,
        "refusal text missing for " .. code)
end

-- Ready: the real executor queues and the order reports success.
ok, reason = Engine.order(player, base, car, character)
assert(ok == true and reason == "queued", "ready order queues, got " .. tostring(reason))
assert(queue ~= nil and queue.action ~= nil, "a native repair action was queued")
assert(feed[#feed]:find("starts on the engine", 1, true) ~= nil, "success is spoken")

-- Completion needs a higher engine condition and a consumed Engine Parts.
local before = { condition = 40, parts = { partsItem } }
part.getCondition = function() return 51 end
inventoryItems = { wrenchItem }
local target = { vehicle = car, part = part, vehicleSqlId = 7, character = character, base = base }
assert(Engine.isComplete(target, before) == true, "a repaired engine with consumed parts completes")

-- The base vehicle menu is the player's reachable door into that same order.
part.getCondition = function() return 40 end
car.getCurrentSpeedKmHour = function() return 0 end
car.isEngineRunning = function() return false end
inventoryItems = { wrenchItem, partsItem }
queue = nil
ISTimedActionQueue.queues = {}
KnoxBaseManager = { getForOwner = function() return base end }
KnoxCompanionService = { getPlayerId = function() return "p1" end }
KnoxSurvivorRuntime.getCharacter = function() return character end
getSpecificPlayer = function() return player end
local function captureMenu()
    local value = { options = {} }
    function value:addOption(label, target, method, ...)
        local option = { label = tostring(label), target = target, method = method, args = { ... } }
        self.options[#self.options + 1] = option
        return option
    end
    function value:addSubMenu() end
    return value
end
local submenu = nil
ISContextMenu = { getNew = function()
    if submenu == nil then submenu = captureMenu() end
    return submenu
end }
local context = {
    options = {},
    addOption = function(self, label)
        local option = { label = tostring(label) }
        self.options[#self.options + 1] = option
        return option
    end,
    addSubMenu = function() end,
}
setting = false
Engine.addVehicleContextMenu(0, context, { { getVehicle = function() return car end } }, false)
assert(#context.options == 1 and context.options[1].label == "Engine Repairs",
    "base vehicle exposes the engine repair menu")
assert(submenu ~= nil and #submenu.options == 1
    and submenu.options[1].label:find("is off", 1, true) ~= nil,
    "setting off is shown in the menu")
assert(submenu.options[1].tooltip ~= nil
    and submenu.options[1].tooltip:find("Experimental resident engine repairs are off", 1, true) ~= nil,
    "setting off explains itself in the menu")
setting = true
submenu = nil
Engine.addVehicleContextMenu(0, context, { { getVehicle = function() return car end } }, false)
assert(submenu ~= nil and #submenu.options == 1 and submenu.options[1].label == "Ada Reyes",
    "base vehicle lists the resident repair order")
assert(submenu.options[1].notAvailable ~= true, "a ready resident order is selectable")
local residentOption = submenu.options[1]
residentOption.method(residentOption.target,
    residentOption.args[1], residentOption.args[2], residentOption.args[3])
assert(queue ~= nil and feed[#feed]:find("starts on the engine", 1, true) ~= nil,
    "the base vehicle menu queues the real repair and reports it")

KnoxSettings, KnoxActivityFeed, KnoxSurvivorRuntime, KnoxPersistence =
    prior.KnoxSettings, prior.KnoxActivityFeed, prior.KnoxSurvivorRuntime, prior.KnoxPersistence
KnoxBaseStorage, ISRepairEngine, ISTimedActionQueue = prior.KnoxBaseStorage, prior.ISRepairEngine, prior.ISTimedActionQueue
ISOpenVehicleDoor, ISCloseVehicleDoor, Perks, ItemTag, getCell =
    prior.ISOpenVehicleDoor, prior.ISCloseVehicleDoor, prior.Perks, prior.ItemTag, prior.getCell
KnoxBaseManager, KnoxCompanionService, ISContextMenu, getSpecificPlayer =
    prior.KnoxBaseManager, prior.KnoxCompanionService, prior.ISContextMenu, prior.getSpecificPlayer
print("Base engine repair order PASS off=refused skill=refused tools=refused moving=refused outside=refused queued=yes complete=yes")
