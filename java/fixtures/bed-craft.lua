local P, C, Jobs = assert(KnoxPersistence), assert(KnoxAutonomyController), assert(KnoxBaseJobs)
local names = { "data", "getCell", "getGameTime", "getTimestampMs", "KnoxSurvivorRuntime",
    "KnoxActivityFeed", "AdjacentFreeTileFinder", "ArrayList", "getScriptManager",
    "HandcraftLogic", "ISHandcraftAction", "ISTimedActionQueue", "KnoxBaseManager",
    "KnoxInventoryActions", "KnoxBaseFarming", "KnoxBaseWoodcutting", "KnoxBaseCorpseHandling",
    "KnoxBaseRepairs", "KnoxBaseCooking", "KnoxBaseBarricades", "KnoxJobTestSupplies",
    "KnoxSurvivorNeeds", "KnoxNightShelter", "KnoxSettings", "ISInventoryTransferAction",
    "KnoxEventRuntime", "ISMoveablesAction", "ISMoveableSpriteProps", "ISGrabItemAction", "KnoxCompanionVehicles" }
local saved = {}
for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end,
        add = function(_, value) values[#values + 1] = value end,
        contains = function(_, value) for _, candidate in ipairs(values) do if candidate == value then return true end end return false end,
        remove = function(_, value) for i, candidate in ipairs(values) do if candidate == value then table.remove(values, i) return end end end }
end
data = {}
local id, now = "bed-crafter", 10
getGameTime = function() return { getWorldAgeHours = function() return now end } end
getTimestampMs = function() return now * 3600000 end
assert(P.setRecord(id, expectedRecord))
assert(P.setSurvivorCapabilities(id, {}))
local root = data.KnoxSurvivors_IsoPlayer
local faction = { id = "craft-faction", name = "Craft House", leaderId = id, memberIds = {id} }
local base = { id = "craft-base", ownerKind = "faction", ownerId = faction.id, tasks = {}, zones = {},
    settings = { autoBarricade = false },
    home = { buildingId = "craft-building", minX = 0, minY = 0, width = 1, height = 1, z = 0 } }
root.factions[faction.id], root.bases[base.id] = faction, base
root.survivors[id].affiliation = { kind = "faction", factionId = faction.id }
root.survivors[id].duty = { mode = "base", baseId = base.id, allowLootRuns = true }
local inventoryItems, floorItems = {}, {}
local inventory = { getItems = function() return list(inventoryItems) end }
local known, skilled, inputs = true, true, 1
local surfaceUsable, surfaceIndex, inRange = true, 0, true
local surface = { getObjectIndex = function() return surfaceIndex end,
    getProperties = function() return { get = function() return "" end } end }
local square = { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    getObjects = function() return list({surface}) end, isOutside = function() return false end,
    getWorldObjects = function()
        local objects = {}
        for _, item in ipairs(floorItems) do objects[#objects + 1] = { getItem = function() return item end } end
        return list(objects)
    end,
    getBuilding = function() return { getDef = function() return { getID = function() return "craft-building" end } end } end }
local body = { getCurrentSquare = function() return square end, getInventory = function() return inventory end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    canUseAsGenericCraftingSurface = function(_, object) return object == surface and surfaceUsable end,
    isRecipeKnown = function() return known end }
KnoxSurvivorRuntime = { getCharacter = function(who) return who == id and body or nil end }
getCell = function() return { getGridSquare = function(_, x, y, z) return x == 0 and y == 0 and z == 0 and square or nil end } end
KnoxActivityFeed = { event = function() end, speak = function() end }
KnoxSurvivorNeeds = nil
KnoxSettings = { ignoreJobResourceRequirements = function() return true end }
KnoxNightShelter = { currentHour = function() return 12 end }
AdjacentFreeTileFinder = { Find = function() return square end }
ArrayList = { new = function() return list({}) end }
local recipe = { characterHasRequiredSkills = function() return skilled end, isAnySurfaceCraft = function() return true end }
local unpackRecipe = { characterHasRequiredSkills = function() return true end, isAnySurfaceCraft = function() return false end }
getScriptManager = function() return { getCraftRecipe = function(_, name)
    assert(name == "SewHideSleepingBag" or name == "UnpackSleepingBag", "only installed bed recipes are requested")
    return name == "UnpackSleepingBag" and unpackRecipe or recipe
end } end
HandcraftLogic = { new = function(character, _, object)
    return { character = character, surface = object, outputs = {}, setContainers = function(self, containers) self.containers = containers end,
        setRecipeFromContextClick = function(self, value, selected) self.recipe, self.selected = value, selected end,
        canPerformCurrentRecipe = function(self) return self.recipe == unpackRecipe and self.selected ~= nil or inputs > 0 end,
        isCharacterInRangeOfWorkbench = function() return inRange end,
        startCraftAction = function(self, action) self.started = action end,
        getCreatedOutputItems = function(self, result) for _, item in ipairs(self.outputs) do result:add(item) end end }
end }
ISHandcraftAction = { FromLogic = function(logic) return { character = logic.character, logic = logic,
    isoObject = logic.surface, craftRecipe = logic.recipe, isValid = function() return true end } end }
KnoxEventRuntime = nil
ISInventoryTransferAction = {}
function ISInventoryTransferAction:derive() return setmetatable({}, { __index = self }) end
function ISInventoryTransferAction:new(character, item, source, destination)
    return setmetatable({ character = character, item = item, srcContainer = source, destContainer = destination }, { __index = self })
end
function ISInventoryTransferAction:isValid() return true end
function ISInventoryTransferAction:transferItem(item)
    self.srcContainer:remove(item)
    self.destContainer:add(item)
    item.container = self.destContainer
end
ISGrabItemAction = {}
function ISGrabItemAction:derive() return setmetatable({}, { __index = self }) end
function ISGrabItemAction:new(character, object, duration)
    local action = setmetatable({character = character, item = object, destContainer = character:getInventory(), maxTime = duration}, {__index=self})
    action:checkQueueList()
    return action
end
function ISGrabItemAction:isValid()
    return self.item:getSquare() ~= nil and self.item:getSquare():getWorldObjects():contains(self.item)
        and self.destContainer:hasRoomFor(self.character, self.item:getItem())
end
function ISGrabItemAction:transferItem(object)
    local item = object:getItem()
    object:getSquare():getWorldObjects():remove(object)
    object.square, item.world, item.container = nil, nil, self.destContainer
    self.destContainer:add(item)
end
local acceptQueue = true
ISTimedActionQueue = { queues = {} }
ISTimedActionQueue.add = function(action)
    if not acceptQueue then return nil end
    local queue = { queue = { action } }
    ISTimedActionQueue.queues[body] = queue
    return queue
end
local manager, ensureBeds = bedCraftManagerFactory(function() return now end)
local shortageRead, originalNeeds = 0, manager.needsBedCraft
manager.needsBedCraft = function(value) shortageRead = shortageRead + 1 return originalNeeds(value) end
KnoxBaseManager, KnoxInventoryActions = manager, bedCraftActionsFactory()
for _, name in ipairs({ "KnoxBaseFarming", "KnoxBaseWoodcutting", "KnoxBaseCorpseHandling",
    "KnoxBaseRepairs", "KnoxBaseCooking", "KnoxBaseBarricades" }) do
    _G[name] = { findTask = function() return nil end, canPrepare = function() return false end }
end
-- The native queue and crafting recipe are doubled; no debug supply path may run.
local topUps = 0
KnoxJobTestSupplies = { topUp = function() topUps = topUps + 1 error("bed crafting cannot mint inputs") end }
assert(ensureBeds(base, faction) == 0 and manager.needsBedCraft(base), "the real bed owner exposes a measured shortage")
local planned = assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag"), "known skilled actor with real inputs has a craft plan")
assert(planned.surface == surface, "the actual nearby work surface is handed to native craft logic")
known = false
assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag") == nil, "unknown recipe is refused")
known, skilled = true, false
assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag") == nil, "insufficient real recipe skill is refused")
skilled, inputs = true, 0
assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag") == nil, "missing native inputs are refused")
inputs = 1
surfaceUsable = false
assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag") == nil, "a surface recipe cannot be sewn without a reachable usable surface")
surfaceUsable, inRange = true, false
assert(KnoxInventoryActions.craftPlan(body, "SewHideSleepingBag") == nil, "native workstation range must admit the planned craft")
inRange = true
Jobs.prepareWorkforce(base, body, now)
local task
for _, value in pairs(base.tasks) do if value.type == "craft_bed" then task = value end end
assert(task ~= nil and task.auto == true, "workforce discovery queues a sleeping-bag task through the existing board")
assert(Jobs.selectEligibleTask({task}, id, base.id, "auto", manager.canPerformTask) == task,
    "the ordinary automatic scheduler selects the supported bed craft task")
assert(KnoxOrderCatalog.tasks.craft_bed.label == "Sew a Sleeping Bag", "the work board names the craft in player language")
Jobs.prepareWorkforce(base, body, now)
local count = 0
for _, value in pairs(base.tasks) do if value.type == "craft_bed" then count = count + 1 end end
assert(count == 1, "repeated preparation does not create parallel bed craft jobs")
known = false
assert(not manager.canPerformTask(id, base.id, task), "ordinary task admission refuses a crafter who lost recipe knowledge")
known = true
assert(manager.canPerformTask(id, base.id, task), "ordinary task admission accepts the qualified resident")
assert(P.claimBaseTask(base.id, task.id, id, now))
local controller = setmetatable({ id = id, character = body, base = base, baseId = base.id,
    baseTask = task, state = "BASE_IDLE", reservations = {} }, { __index = C })
controller.releaseBaseCooking = function() end
controller.releaseBaseTaskSupplyTransfer = function() end
controller.diag = function() end
controller.finishDecision = function(self) self.state = "BASE_IDLE" end
assert(controller:beginBaseTaskSupplyOrWork(100) and controller.state == "BASE_TASK_ACTION" and topUps == 0,
    "the real task start enters native crafting without debug supply top-up or a synthetic work timer")
controller:updateBaseTaskAction(101)
local action = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the real action loop admits and watches its native craft")
assert(action.logic.started == action and action:isValid(), "native craft starts only after registered queue admission")
local scansBefore = shortageRead
for i = 1, 20 do assert(action:isValid()) end
assert(shortageRead == scansBefore, "native validity checks do not repeat settlement-wide bag scans")
task.claimedBy = "some-other-resident"
assert(not action:isValid(), "the controller's native action guard rejects a lost task claim")
task.claimedBy = id
surfaceIndex = -1
assert(not action:isValid(), "a removed native work surface invalidates the queued craft")
surfaceIndex = 0
controller:updateBaseTaskAction(102)
assert(task.state == "claimed", "a still-pending craft cannot complete its base task")
-- Simulate a canceled native action: no real created output means failure.
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(103)
assert(task.state == "blocked" and task.result == "bed_craft_no_output",
    "a drained native queue without created output never credits a sleeping bag")
now = 11
ensureBeds(base, faction)
Jobs.prepareWorkforce(base, body, now)
assert(P.claimBaseTask(base.id, task.id, id, now))
controller.baseTask, controller.baseTaskActionQueued = task, false
assert(controller:beginBaseTaskSupplyOrWork(200))
controller:updateBaseTaskAction(201)
action = assert(controller.baseTaskActionWatch.action)
local bag = { getFullType = function() return "Base.SleepingBag_Hide_Packed" end,
    IsInventoryContainer = function() return false end, getContainer = function() return inventory end,
    getWorldItem = function() return nil end }
-- Native boundary receipt: the doubled recipe consumes its own material and
-- produces an actual item; production code never creates either.
inputs, inventoryItems[1], action.logic.outputs[1] = 0, bag, bag
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(202)
assert(task.state == "complete" and task.result == "sleeping_bag_crafted" and inputs == 0,
    "a real native-created output is required before the existing task writer records completion")
assert(P.getSurvivorPolicies(id).assignedBed == nil, "crafting a packed bag invents no placed bed or assignment")
local missingOutput = { logic = { getCreatedOutputItems = function(_, result) result:add({
    getFullType = function() return "Base.SleepingBag_Hide_Packed" end,
    getContainer = function() return nil end, getWorldItem = function() return nil end }) end } }
assert(KnoxInventoryActions.craftedOutput(missingOutput, "Base.SleepingBag_Hide_Packed") == nil,
    "a created output no longer present anywhere cannot count as delivered craft output")
assert(not manager.needsBedCraft(base), "a carried packed bag covers the shortage until placement")
inventoryItems[1], floorItems[1] = nil, bag
assert(not manager.needsBedCraft(base), "a packed bag on the actual home floor also prevents duplicate crafting")
floorItems[1] = nil
acceptQueue, inputs = false, 1
local denied = KnoxInventoryActions.queueCraft(body, "SewHideSleepingBag", function() return true end)
assert(denied == nil, "constructed action without native queue admission is refused")
acceptQueue = true
local permission = true
local guarded = assert(KnoxInventoryActions.queueCraft(body, "SewHideSleepingBag", function() return permission end))
permission = false
assert(not guarded:isValid(), "permission is rechecked by the actual queued native action")
local oldFloor = square.getWorldObjects
square.getWorldObjects = nil
assert(not manager.needsBedCraft(base), "an unreadable home floor cannot be treated as an empty bag store")
square.getWorldObjects = oldFloor
now = 12
assert(not manager.needsBedCraft(base), "an expired bed-owner shortage cannot initiate fresh crafting")

-- Continue the same actual task loop through retrieval, unpack, and native
-- placement. Furniture geometry and engine mutation remain doubled boundaries.
now, inputs = 13, 0
base.home.width = 2
local bedObjects, outsideFootprint, canPlace = {}, false, true
local tile = { getX = function() return 1 end, getY = function() return 0 end, getZ = function() return 0 end,
    getObjects = function() return list(bedObjects) end,
    getWorldObjects = function() return list({}) end, getBuilding = square.getBuilding }
local outside = { getX = function() return 2 end, getY = function() return 0 end, getZ = function() return 0 end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    if y == 0 and z == 0 then if x == 0 then return square elseif x == 1 then return tile end end
end } end
body.getPrimaryHandItem, body.getSecondaryHandItem = function() return nil end, function() return nil end
body.getX, body.getY, body.getZ = function() return 0 end, function() return 0 end, function() return 0 end
KnoxSurvivorRuntime.idForCharacter = function(who) return who == body and id or nil end
inventory.add = function(_, item) inventoryItems[#inventoryItems + 1] = item end
inventory.remove = function(_, item)
    for i, value in ipairs(inventoryItems) do if value == item then table.remove(inventoryItems, i) return end end
end
local bagItems = { bag }
local nested = { getItems = function() return list(bagItems) end, isInCharacterInventory = function() return true end,
    remove = function(_, item) assert(bagItems[1] == item) table.remove(bagItems, 1) end }
bag.container = nested
bag.getContainer = function(self) return self.container end
bag.getWorldSprite = function() return "camping_02_80" end
inventoryItems = { { getFullType = function() return "Base.Bag" end, IsInventoryContainer = function() return true end,
    getInventory = function() return nested end } }
ISMoveableSpriteProps = { new = function()
    return { isMoveable = true, facing = "S",
        canPlaceMoveable = function(_, _, squareToPlace) return canPlace and squareToPlace == tile end,
        getSpriteGridTopLeft = function(_, x, y) return x, y end,
        getMultiTileSquares = function() return outsideFootprint and {tile, outside} or {tile} end }
end }
ISMoveablesAction = { new = function(_, character, squareToPlace, mode, sprite, _, direction, item)
    assert(mode == "place" and sprite == "camping_02_80" and direction == "S", "native moveable placement receives the actual sprite and facing")
    return { character = character, square = squareToPlace, item = item,
        isValid = function() return item:getContainer() == inventory and canPlace end }
end }
ensureBeds(base, faction)
-- Nearby base storage uses the real storage finder/filter and loot permission.
local stored = { getItems = function() return list({bag}) end, getType = function() return "crate" end,
    isExistYet = function() return true end, isInCharacterInventory = function() return false end,
    getParent = function() return nil end, getSourceGrid = function() return tile end }
local crate = { getContainerCount = function() return 1 end, getContainerByIndex = function() return stored end,
    getObjectIndex = function() return 0 end, getSquare = function() return tile end }
bagItems[1], bag.container = nil, stored
tile.getObjects = function() return list({crate}) end
local storedPlan = manager.bedPreparationPlan(base, body)
assert(storedPlan ~= nil and storedPlan.phase == "retrieve" and storedPlan.item == bag,
    "a nearby real base-storage bag is retrieved through the existing storage and permission owners")
root.survivors[id].duty.mode = "autonomous"
assert(manager.bedPreparationPlan(base, body) == nil, "lost residency refuses the same stored bag")
root.survivors[id].duty.mode = "base"
stored.getSourceGrid = function() return outside end
assert(manager.bedPreparationPlan(base, body) == nil, "a distant stored bag is never transferred without a walking step")
stored.getSourceGrid = function() return tile end
bagItems[1], bag.container = bag, nested
tile.getObjects = function() return list(bedObjects) end
Jobs.prepareWorkforce(base, body, now)
local preparation
for _, value in pairs(base.tasks) do if value.type == "prepare_bed" then preparation = value end end
assert(preparation ~= nil, "workforce discovery queues the carried sleeping bag's preparation")
assert(P.claimBaseTask(base.id, preparation.id, id, now))
controller.baseTask, controller.baseTaskActionQueued = preparation, false
ISTimedActionQueue.queues[body].queue = {}
-- A nearby loose bag uses the same task, floor owner and real guarded grab wrapper.
local floorObjects, room = {}, true
local object = { square = square, getSquare = function(self) return self.square end, getItem = function() return bag end }
floorObjects[1], bag.world, bag.container, bagItems[1] = object, object, nil, nil
bag.getWorldItem = function(self) return self.world end
local originalWorldObjects = square.getWorldObjects
square.getWorldObjects = function() return list(floorObjects) end
inventory.hasRoomFor = function() return room end
local floorPlan = manager.bedPreparationPlan(base, body)
assert(floorPlan ~= nil and floorPlan.phase == "grab" and floorPlan.object == object,
    "the bed owner finds the actual nearby loose bag through the floor stock reader")
local originalTileWorld = tile.getWorldObjects
tile.getWorldObjects = nil
assert(manager.bedPreparationPlan(base, body) == nil, "an unreadable floor refuses even a partially observed collection plan")
tile.getWorldObjects = originalTileWorld
root.survivors[id].duty.mode = "autonomous"
assert(manager.bedPreparationPlan(base, body) == nil, "a non-resident cannot select a base floor bag")
root.survivors[id].duty.mode = "base"
object.square = outside
assert(not manager.bedFloorCollectionAllowed(base, body, object, bag), "a moved floor bag outside the base is refused")
object.square = square
local farFloor = { getX = function() return 3 end, getY = function() return 0 end, getZ = function() return 0 end,
    getWorldObjects = function() return list(floorObjects) end }
base.home.width, object.square = 4, farFloor
assert(not manager.bedFloorCollectionAllowed(base, body, object, bag), "a distant in-base floor bag requires walking before collection")
base.home.width, object.square = 2, square
assert(controller:beginBaseTaskSupplyOrWork(280), "the ordinary preparation task starts for a loose floor bag")
controller:updateBaseTaskAction(281)
local grab = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the preparation action loop queues a real native grab for the loose bag")
assert(controller.baseTaskBedPlan.phase == "grab" and ISTimedActionQueue.queues[body].queue[1] == grab,
    "the actual registered native queue owns the floor-bag pickup")
room = false
assert(not grab:isValid(), "native capacity refusal is preserved for a floor bag")
room = true
bag.world = {}
assert(not grab:isValid(), "the queued grab rechecks the loose item's actual world-object link")
bag.world = object
root.survivors[id].duty.mode = "autonomous"
assert(not grab:isValid(), "the queued floor grab rechecks resident permission")
grab:transferItem(object)
assert(bag:getWorldItem() == object and bag:getContainer() == nil, "lost permission prevents the actual grab transfer")
root.survivors[id].duty.mode = "base"
assert(grab:isValid())
grab:transferItem(object)
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(282)
assert(preparation.state == "claimed" and bag:getContainer() == inventory and bag:getWorldItem() == nil
    and #floorObjects == 0 and not controller.baseTaskActionQueued,
    "a real floor-to-inventory receipt advances preparation without crediting a bed")

-- Distant collection uses the real tick/movement owner and rechecks physical
-- proximity after its terminal movement report; native movement is doubled.
local position = square
body.getCurrentSquare = function() return position end
body.getSquare = body.getCurrentSquare
body.getX, body.getY, body.getZ = function() return position:getX() end, function() return 0 end, function() return 0 end
body.getVehicle = function() return nil end
setmetatable(body, { __index = function() return function() return false end end })
local cells, distantObjects = { [0] = square, [1] = tile }, {}
for x = 2, 5 do
    local px = x
    cells[x] = { getX = function() return px end, getY = function() return 0 end, getZ = function() return 0 end,
        getObjects = function() return list({}) end, getWorldObjects = function() return list({}) end,
        canStand = function() return false end, getBuilding = square.getBuilding }
end
local far, approach = cells[4], cells[3]
far.getWorldObjects = function() return list(distantObjects) end
base.home.width = 6
getCell = function() return { getGridSquare = function(_, x, y, z) return y == 0 and z == 0 and cells[x] or nil end } end
inventory:remove(bag)
local distantObject = { square = far, getSquare = object.getSquare, getItem = function() return bag end }
distantObjects[1], bag.world, bag.container = distantObject, distantObject, nil
local oldFind = AdjacentFreeTileFinder.Find
AdjacentFreeTileFinder.Find = function() return nil end
assert(manager.bedPreparationPlan(base, body) == nil, "a distant bag without a real approach cannot become a collection trip")
local invalidApproach = {getX = function() return 5 end, getY = function() return 0 end, getZ = function() return 0 end}
AdjacentFreeTileFinder.Find = function() return invalidApproach end
base.home.width = 5
assert(manager.bedPreparationPlan(base, body) == nil, "a collection approach outside the base is refused")
base.home.width = 6
AdjacentFreeTileFinder.Find = function() return approach end
local travelPlan = manager.bedPreparationPlan(base, body)
assert(travelPlan ~= nil and travelPlan.phase == "move" and travelPlan.approach == approach,
    "the real bed owner plans a walk to a loaded distant floor bag")
local farCrate = { getContainerCount = function() return 1 end, getContainerByIndex = function() return stored end,
    getObjectIndex = function() return 0 end, getSquare = function() return far end }
far.getObjects = function() return list({farCrate}) end
distantObjects[1], bag.world, bag.container = nil, nil, stored
stored.getSourceGrid = function() return far end
local storedTravel = manager.bedPreparationPlan(base, body)
assert(storedTravel ~= nil and storedTravel.phase == "move",
    "a real distant storage bag also plans walking rather than an instant transfer")
assert(Jobs.resolveTaskSquare(preparation, body) == approach,
    "the existing task-square resolver supplies the current bag approach")
far.getObjects = function() return list({}) end
distantObjects[1], bag.world, bag.container = distantObject, distantObject, nil
local destination, moveCount, movement = nil, 0, "Working"
controller.bridge = { moveNpc = function(_, who, target)
    assert(who == id) destination, moveCount = target, moveCount + 1 return "MOVE_STARTED"
end, tickNpc = function() return movement end, cancelNpcMove = function() end }
controller.nextThink, controller.nextThreatScan = 1000000, 1000000
controller.failedThreats, controller.selfCareRetryAt = {}, {}
local early = { "observeGroupEntry", "checkSharedMeal", "recoverIdleAnimationLatch", "tryBoardFollowVehicle",
    "recoverFromDetached", "waitingForTransferActions", "tryAutomaticPlayerAid", "yieldBaseTaskForNeed",
    "yieldInventoryCleanupForNeed", "yieldAidForNeed", "yieldCollectionForNeed", "isSettlementSupplyEntry",
    "sharedMealPostureReady" }
for _, method in ipairs(early) do controller[method] = function() return false end end
controller.applyPendingCombatPolicy = function() return true end
controller.canApplyDutyChange = function() return true end
controller.think = function() error("a collection trip cannot return to idle thinking") end
local recoveryBusy = C.isNativeRecoveryBusy
C.isNativeRecoveryBusy = function() return false end
KnoxCompanionVehicles = nil
controller:tick(283)
assert(controller.state == "BASE_TASK_MOVE" and moveCount == 1 and destination == approach,
    "the real tick starts collection through the existing native task movement owner")
assert(bag:getContainer() == nil and #ISTimedActionQueue.queues[body].queue == 0,
    "no pickup or transfer occurs while the collection route is pending")
controller:tick(284)
assert(controller.state == "BASE_TASK_MOVE" and moveCount == 1, "a pending native route is retained without replanning every tick")
movement = "Succeeded"
controller:tick(285)
assert(controller.state == "BASE_TASK_ACTION" and bag:getContainer() == nil,
    "movement completion returns to the same preparation action without transferring a distant item")
controller:tick(286)
assert(controller.state == "BASE_TASK_MOVE" and moveCount == 2 and bag:getContainer() == nil,
    "a terminal native report without actual proximity reissues travel instead of a remote pickup")
position = approach
controller:tick(287)
controller:tick(288)
grab = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "after physical arrival the real tick admits a nearby floor grab")
assert(controller.baseTaskBedPlan.phase == "grab" and grab:isValid())
grab:transferItem(distantObject)
ISTimedActionQueue.queues[body].queue = {}
controller:tick(289)
assert(bag:getContainer() == inventory and preparation.state == "claimed" and not controller.baseTaskActionQueued,
    "physical arrival and native grab receipt advance the same preparation task")
C.isNativeRecoveryBusy = recoveryBusy
AdjacentFreeTileFinder.Find, base.home.width, position = oldFind, 2, square
getCell = function() return { getGridSquare = function(_, x, y, z) return y == 0 and z == 0 and (x == 0 and square or x == 1 and tile) or nil end } end
-- Reset only native world/inventory state for the earlier backpack case.
inventory:remove(bag)
bag.container, bagItems[1] = nested, bag
square.getWorldObjects = originalWorldObjects
assert(controller:beginBaseTaskSupplyOrWork(300) and controller.state == "BASE_TASK_ACTION",
    "the real task start sends bed preparation through the native action owner")
controller:updateBaseTaskAction(301)
action = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the real preparation action loop queues its retrieval")
assert(controller.baseTaskBedPlan.phase == "retrieve" and action:isValid(),
    "a backpack sleeping bag must be retrieved before unpacking or placement")
action:transferItem(bag)
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(302)
assert(preparation.state == "claimed" and bag:getContainer() == inventory and not controller.baseTaskActionQueued,
    "real inventory transfer receipt advances preparation without crediting a bed")
local packPlan = manager.bedPreparationPlan(base, body)
assert(packPlan ~= nil and packPlan.phase == "unpack", "the retrieved packed bag admits its real unpack recipe")
controller:updateBaseTaskAction(303)
action = assert(controller.baseTaskActionWatch.action)
assert(controller.baseTaskBedPlan.phase == "unpack" and action.logic.selected == bag,
    "the exact retrieved packed bag is passed to the actual unpack recipe")
local opened = { container = inventory, getFullType = function() return "Base.SleepingBag_Hide" end,
    IsInventoryContainer = function() return false end, getWorldSprite = bag.getWorldSprite,
    getContainer = bag.getContainer, getWorldItem = function() return nil end }
inventory:remove(bag) bag.container = nil inventory:add(opened)
action.logic.outputs[1] = opened
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(304)
assert(preparation.state == "claimed" and not controller.baseTaskActionQueued,
    "native unpack output advances preparation without assigning or crediting a bed")
outsideFootprint = true
assert(manager.bedPreparationPlan(base, body) == nil, "the entire sleeping-bag footprint must remain inside the base")
outsideFootprint, canPlace = false, false
assert(manager.bedPreparationPlan(base, body) == nil, "native placement rejection cannot become a synthetic bed")
canPlace = true
controller:updateBaseTaskAction(305)
action = assert(controller.baseTaskActionWatch.action)
assert(controller.baseTaskBedPlan.phase == "place" and action:isValid(), "the native placement action receives the unpacked item")
assert(ISTimedActionQueue.queues[body].queue[1] == action, "placement must be admitted to the character's actual registered native queue")
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(306)
assert(preparation.state == "blocked" and preparation.result == "bed_preparation_no_result",
    "an empty native queue without a new physical bed is a failed placement")
now = 14
ensureBeds(base, faction)
Jobs.prepareWorkforce(base, body, now)
assert(P.claimBaseTask(base.id, preparation.id, id, now))
controller.baseTask, controller.baseTaskActionQueued = preparation, false
assert(controller:beginBaseTaskSupplyOrWork(400))
controller:updateBaseTaskAction(401)
local plan = controller.baseTaskBedPlan
local oldBed = { getObjectIndex = function() return 0 end, getProperties = function()
    return { get = function() return "badBed" end } end, isFurnitureOccupied = function() return false end }
plan.before[oldBed], bedObjects[1] = true, oldBed
inventory:remove(opened) opened.container = nil
assert(not manager.bedPlacementComplete(base, plan), "an already existing bed cannot receipt this placement")
bedObjects[1] = { getObjectIndex = function() return 0 end, getProperties = oldBed.getProperties,
    isFurnitureOccupied = function() return false end }
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(402)
assert(preparation.state == "complete" and preparation.result == "sleeping_bag_placed",
    "only consumed moveable plus a new real bed object completes preparation")
assert(P.getSurvivorPolicies(id).assignedBed == nil, "the placement task does not invent an assignment")
assert(ensureBeds(base, faction) == 1 and P.getSurvivorPolicies(id).assignedBed ~= nil,
    "placement invalidates the old shortage scan and the original bed owner assigns the discovered bed")

-- Threat suspension can race native perform. Share the ordinary physical
-- receipt, keep incomplete work claimed, and never promote an unpack to a bed.
controller.releaseAid, controller.leaveRecoveryPosture, controller.releaseSupply = function() end, function() end, function() end
KnoxBaseCorpseHandling.isDragging = function() return false end
local clearCount, sequence = 0, 0
ISTimedActionQueue.clear = function(character)
    assert(character == body) clearCount = clearCount + 1 ISTimedActionQueue.queues[body].queue = {}
end
local function interruptedTask(kind, phase, outputs, placed)
    sequence = sequence + 1
    local record = assert(KnoxBaseTaskBoard.queue(base.id, kind, {id = "bed-interrupt:" .. sequence, x=0,y=0,z=0}, {}, 80))
    assert(P.claimBaseTask(base.id, record.id, id, now))
    controller.baseTask, controller.state, controller.baseTaskActionQueued = record, "BASE_TASK_ACTION", true
    local native = {character=body, logic={getCreatedOutputItems=function(_, result)
        for _, item in ipairs(outputs or {}) do result:add(item) end
    end}}
    controller:watchBaseTaskAction(native, 500 + sequence, nil)
    local before = {}
    for _, object in ipairs(bedObjects) do before[object] = true end
    controller.baseTaskBedPlan = phase ~= nil and {phase=phase,item=opened,square=tile,before=before} or nil
    if placed then bedObjects[#bedObjects + 1] = {getObjectIndex=function() return #bedObjects - 1 end,
        getProperties=oldBed.getProperties, isFurnitureOccupied=function() return false end} end
    ISTimedActionQueue.queues[body].queue = {}
    return record, native
end
bag.container = inventory
local completed = interruptedTask("craft_bed", nil, {bag}, false)
assert(controller:suspendBaseTaskForThreat("danger") and completed.state == "complete"
    and completed.result == "sleeping_bag_crafted" and completed.claimedBy == nil,
    "a finished native craft is credited before threat suspension can replay it")
assert(not controller:suspendBaseTaskForThreat("danger-again") and completed.state == "complete",
    "completed craft receipt is not credited twice after task cleanup")
opened.container = nil
completed = interruptedTask("prepare_bed", "place", {}, true)
assert(controller:suspendBaseTaskForThreat("danger") and completed.state == "complete"
    and completed.result == "sleeping_bag_placed", "a finished physical bed is credited at threat suspension")
local unfinished, native = interruptedTask("craft_bed", nil, {}, false)
ISTimedActionQueue.queues[body].queue = {native}
local clearsBefore = clearCount
assert(controller:suspendBaseTaskForThreat("danger") and unfinished.state == "claimed"
    and unfinished.claimedBy == id and unfinished.interruptedReason == "danger"
    and controller.baseTaskActionWatch == nil and not controller.baseTaskActionQueued
    and clearCount == clearsBefore + 1,
    "an unfinished native craft is canceled but its task claim survives for resumption")
controller:finishBaseTask(false, "fixture_cleanup")
opened.container = inventory
unfinished = interruptedTask("prepare_bed", "unpack", {opened}, false)
assert(controller:suspendBaseTaskForThreat("danger") and unfinished.state == "claimed"
    and controller.baseTaskBedPlan == nil, "a real unpack output is not a finished bed and stale placement state is cleared")
controller:finishBaseTask(false, "fixture_cleanup")
opened.container = nil
unfinished = interruptedTask("prepare_bed", "place", {}, false)
assert(controller:suspendBaseTaskForThreat("danger") and unfinished.state == "claimed",
    "old furniture alone cannot complete a suspended placement")
controller:finishBaseTask(false, "fixture_cleanup")
completed = interruptedTask("craft_bed", nil, {bag}, false)
completed.claimedBy = "another-resident"
controller:suspendBaseTaskForThreat("stale-owner")
assert(completed.state == "claimed" and completed.claimedBy == "another-resident",
    "a physical output never grants a stale controller another resident's completion claim")

-- Stored recipe inputs: native selection is the boundary. Production must
-- transfer those exact real instances, validate storage, then craft carried.
now, inputs = 20, 0
local ingredientBase = {id="recipe-base",ownerKind="faction",ownerId=faction.id,tasks={},zones={},
    settings={autoBarricade=false},home={buildingId="recipe-building",minX=40,minY=40,width=2,height=1,z=0}}
root.bases[ingredientBase.id] = ingredientBase
root.survivors[id].duty = {mode="base",baseId=ingredientBase.id,allowLootRuns=true}
local definition = {getID=function() return "recipe-building" end}
local function recipeSquare(x)
    return {getX=function() return x end,getY=function() return 40 end,getZ=function() return 0 end,
        getBuilding=function() return {getDef=function() return definition end} end,
        getWorldObjects=function() return list({}) end}
end
local workSquare, storeSquare = recipeSquare(40), recipeSquare(41)
local selectedInputs, stockItems, nativeMissing = {}, {}, false
inventoryItems = {}
inventory.isInCharacterInventory = function() return true end
inventory.contains = function(_, item) return list(inventoryItems):contains(item) end
local cupboard = {getType=function() return "crate" end,isExistYet=function() return true end,
    getItems=function() return list(stockItems) end,isInCharacterInventory=function() return false end,
    getSourceGrid=function() return storeSquare end,getParent=function() return nil end,
    contains=function(_, item) return list(stockItems):contains(item) end,
    remove=function(_, item) list(stockItems):remove(item) end}
local cupboardObject = {getObjectIndex=function() return 0 end,getSquare=function() return storeSquare end,
    getContainerCount=function() return 1 end,getContainerByIndex=function() return cupboard end,
    getProperties=function() return {get=function() return "" end} end}
workSquare.getObjects = function() return list({surface}) end
storeSquare.getObjects = function() return list({cupboardObject}) end
position = workSquare
body.getY = function() return position:getY() end
getCell = function() return {getGridSquare=function(_, x,y,z)
    if y==40 and z==0 then return x==40 and workSquare or x==41 and storeSquare or nil end
end} end
local function ingredient(fullType)
    return {container=cupboard,getFullType=function() return fullType end,IsInventoryContainer=function() return false end,
        getContainer=function(self) return self.container end,getCount=function() return 1 end}
end
local wool, awl, unrelated = ingredient("Base.WoolRaw"), ingredient("Base.Awl"), ingredient("Base.Nails")
stockItems, selectedInputs = {wool,awl,unrelated}, {wool,awl}
local previousLogic = HandcraftLogic.new
-- Native-shaped selector: one real item per required type, chosen only from the
-- containers the logic was actually handed. A narrowed container set therefore
-- makes the installed recipe choose its own alternative.
local function selectedFrom(containers)
    local chosen, types = {}, {}
    for _, item in ipairs(selectedInputs) do
        local kind = item:getFullType()
        if not types[kind] and containers:contains(item:getContainer()) then
            types[kind] = true
            chosen[#chosen + 1] = item
        end
    end
    return chosen
end
HandcraftLogic.new = function(...)
    local logic = previousLogic(...)
    logic.canPerformCurrentRecipe = function(self)
        if nativeMissing then return false end
        local available = {}
        for _, item in ipairs(selectedFrom(self.containers)) do available[item:getFullType()] = true end
        for _, item in ipairs(selectedInputs) do
            if not available[item:getFullType()] then return false end
        end
        return true
    end
    logic.getRecipeData = function(self)
        return {getAllInputItems=function() return list(selectedFrom(self.containers)) end}
    end
    return logic
end
local reference = {key="recipe-store",x=41,y=40,z=0,objectIndex=0,containerIndex=0,containerType="crate"}
assert(P.setBaseStorageFilters(ingredientBase.id, reference, {general=true}))
assert(ensureBeds(ingredientBase, faction)==0 and manager.needsBedCraft(ingredientBase), "the new settlement has a real measured bed shortage")
assert(KnoxInventoryActions.craftPlan(body,"SewHideSleepingBag",ingredientBase)==nil,
    "stored ingredients never satisfy a carried-only executable craft")
local supplyPlan = assert(manager.bedCraftPlan(ingredientBase,body), "native-selected nearby stored ingredients admit preparation")
assert(supplyPlan.phase=="craft_supply" and supplyPlan.item==wool,
    "the supply plan chooses the native recipe's exact first item instead of a fixed category")
assert(KnoxInventoryActions.queueCraft(body,"SewHideSleepingBag",function() return true end,ingredientBase)==nil,
    "an executable craft never consumes directly from the read-only storage projection")
nativeMissing = true
assert(manager.bedCraftPlan(ingredientBase,body)==nil, "a partial native recipe never authorizes speculative ingredient hauling")
nativeMissing = false
assert(P.setBaseStorageFilters(ingredientBase.id,reference,{["item:Base.Awl"]=true}))
local blockedNear = manager.bedCraftPlan(ingredientBase,body)
assert(blockedNear ~= nil and blockedNear.phase == "craft_blocked"
    and blockedNear.itemType == "Base.WoolRaw" and blockedNear.reason == "recipe_input_forbidden",
    "all selected stored inputs must pass the real storage filters or be refused by name")
assert(P.setBaseStorageFilters(ingredientBase.id,reference,{general=true}))
KnoxSurvivorNeeds = {isSafeFood=function() return false end,isWaterItem=function() return false end}
Jobs.prepareWorkforce(ingredientBase,body,now)
local recipeTask
for _, value in pairs(ingredientBase.tasks) do if value.type=="craft_bed" then recipeTask=value end end
assert(recipeTask~=nil, "workforce discovery admits a complete native recipe in nearby storage")
assert(manager.canPerformTask(id,ingredientBase.id,recipeTask), "normal admission recognizes retrievable native-selected recipe inputs")
assert(P.claimBaseTask(ingredientBase.id,recipeTask.id,id,now))
controller.base,controller.baseId,controller.baseTask = ingredientBase,ingredientBase.id,recipeTask
assert(controller:beginBaseTaskSupplyOrWork(600), "the real task start accepts stored recipe inputs without debug top-up")
controller:updateBaseTaskAction(601)
local supplyAction=assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the real craft task queues an ordinary native ingredient transfer")
assert(controller.baseTaskBedPlan.item==wool and supplyAction.item==wool and supplyAction.logic==nil
    and ISTimedActionQueue.queues[body].queue[1]==supplyAction,
    "the exact recipe ingredient is admitted as transfer before any crafting action")
assert(P.setBaseStorageFilters(ingredientBase.id,reference,{["item:Base.Awl"]=true}))
assert(not supplyAction:isValid(), "queued ingredient retrieval rechecks changed storage filters")
supplyAction:transferItem(wool)
assert(wool:getContainer()==cupboard, "revoked storage permission prevents native ingredient movement")
assert(P.setBaseStorageFilters(ingredientBase.id,reference,{general=true}))
ingredientBase.home.width,position=5,recipeSquare(44)
assert(not supplyAction:isValid(), "queued recipe input retrieval cannot become a remote transfer")
ingredientBase.home.width,position=2,workSquare
assert(supplyAction:isValid())
supplyAction:transferItem(wool)
ISTimedActionQueue.queues[body].queue={}
controller:updateBaseTaskAction(602)
assert(recipeTask.state=="claimed" and not controller.baseTaskActionQueued and wool:getContainer()==inventory,
    "real ingredient arrival advances preparation without crediting a craft")
controller:updateBaseTaskAction(603)
supplyAction=assert(controller.baseTaskActionWatch.action)
assert(controller.baseTaskBedPlan.item==awl, "native selection is recalculated after each ingredient arrives")
supplyAction:transferItem(awl)
ISTimedActionQueue.queues[body].queue={}
controller:updateBaseTaskAction(604)
controller:updateBaseTaskAction(605)
local craftAction=assert(controller.baseTaskActionWatch.action)
assert(craftAction.logic~=nil and craftAction.logic.started==craftAction and controller.baseTaskBedPlan==nil
    and craftAction.logic.containers:size()==1 and recipeTask.state=="claimed",
    "craft starts only when the native recipe succeeds from carried containers alone")
inventory:remove(wool) wool.container=nil
local produced=ingredient("Base.SleepingBag_Hide_Packed")
produced.container=inventory produced.getWorldItem=function() return nil end
inventory:add(produced) craftAction.logic.outputs[1]=produced
ISTimedActionQueue.queues[body].queue={}
controller:updateBaseTaskAction(606)
assert(recipeTask.state=="complete" and recipeTask.result=="sleeping_bag_crafted" and topUps==0
    and awl:getContainer()==inventory and unrelated:getContainer()==cupboard,
    "stored recipe preparation completes only on actual output, retaining tools and leaving unrelated stock")
-- A later canceled pickup must fail through the existing task owner, not be
-- confused with delivery merely because the native queue drained.
inventory:remove(produced) produced.container=nil
now=21
wool.container=cupboard stockItems[#stockItems+1]=wool
ensureBeds(ingredientBase,faction)
assert(P.requeueBaseTask(ingredientBase.id,recipeTask.id,now))
assert(P.claimBaseTask(ingredientBase.id,recipeTask.id,id,now))
controller.baseTask=recipeTask
assert(controller:beginBaseTaskSupplyOrWork(700))
controller:updateBaseTaskAction(701)
assert(controller.baseTaskBedPlan~=nil and controller.baseTaskBedPlan.phase=="craft_supply")
ISTimedActionQueue.queues[body].queue={}
controller:updateBaseTaskAction(702)
assert(recipeTask.state=="blocked" and recipeTask.result=="recipe_supply_transfer_not_completed"
    and wool:getContainer()==cupboard, "an empty native queue without actual ingredient delivery blocks the craft")
-- Distant recipe input: native selection may name an item stored across the
-- base. The worker walks there through the existing task movement owner,
-- transfers only after nearby permission, then returns to the selected surface
-- before the installed recipe runs from carried containers alone.
now, inventoryItems = 22, {awl}
ingredientBase.home.width = 5
local returnNear = recipeSquare(41)
returnNear.getObjects = function() return list({cupboardObject}) end
local walkway = recipeSquare(42)
walkway.getObjects = function() return list({}) end
local approachFar, storeFar = recipeSquare(43), recipeSquare(44)
approachFar.getObjects = function() return list({}) end
local farStock = {wool}
local farCupboard = {getType=function() return "crate" end,isExistYet=function() return true end,
    getItems=function() return list(farStock) end,isInCharacterInventory=function() return false end,
    getSourceGrid=function() return storeFar end,getParent=function() return nil end,
    contains=function(_, item) return list(farStock):contains(item) end,
    remove=function(_, item) list(farStock):remove(item) end}
local farObject = {getObjectIndex=function() return 0 end,getSquare=function() return storeFar end,
    getContainerCount=function() return 1 end,getContainerByIndex=function() return farCupboard end,
    getProperties=function() return {get=function() return "" end} end}
storeFar.getObjects = function() return list({farObject}) end
workSquare.getObjects = function() return list({surface}) end
stockItems = {unrelated}
wool.container, selectedInputs, nativeMissing = farCupboard, {wool, awl}, false
getCell = function() return {getGridSquare=function(_, x,y,z)
    if y~=40 or z~=0 then return nil end
    if x==40 then return workSquare elseif x==41 then return returnNear
        elseif x==42 then return walkway elseif x==43 then return approachFar
        elseif x==44 then return storeFar end
end} end
local farReference = {key="recipe-far",x=44,y=40,z=0,objectIndex=0,containerIndex=0,containerType="crate"}
assert(P.setBaseStorageFilters(ingredientBase.id, farReference, {general=true}))
position = workSquare
local oldFindDistant = AdjacentFreeTileFinder.Find
AdjacentFreeTileFinder.Find = function(square)
    if square==storeFar then return approachFar end
    if square==workSquare then return returnNear end
    return oldFindDistant(square)
end
ensureBeds(ingredientBase, faction)
assert(P.requeueBaseTask(ingredientBase.id, recipeTask.id, now))
assert(P.claimBaseTask(ingredientBase.id, recipeTask.id, id, now))
controller.base, controller.baseId, controller.baseTask = ingredientBase, ingredientBase.id, recipeTask
controller.baseTaskActionQueued, controller.baseTaskBedPlan = false, nil
controller.baseTaskBedApproach, controller.baseTaskBedSurface, controller.baseTaskBedReturn = nil, nil, nil
local destination, moveCount, movement = nil, 0, "Working"
controller.bridge = {moveNpc=function(_, who, target)
        assert(who == id) destination, moveCount = target, moveCount + 1 return "MOVE_STARTED"
    end, tickNpc=function() return movement end, cancelNpcMove=function() end}
controller.nextThink, controller.nextThreatScan = 1000000, 1000000
local recoveryBusyDistant = C.isNativeRecoveryBusy
C.isNativeRecoveryBusy = function() return false end
assert(controller:beginBaseTaskSupplyOrWork(800) and controller.state == "BASE_TASK_MOVE"
    and destination == approachFar and moveCount == 1,
    "a distant native-selected ingredient starts a real task movement instead of a remote transfer")
local pending = ISTimedActionQueue.queues[body] and ISTimedActionQueue.queues[body].queue or {}
assert(controller.baseTaskBedPlan.phase == "craft_supply_move"
    and controller.baseTaskBedPlan.item == wool and controller.baseTaskBedPlan.surface == workSquare
    and #pending == 0,
    "native selection names the exact distant item and the surface to return to")
position, movement = approachFar, "Succeeded"
controller:tick(801)
assert(controller.state == "BASE_TASK_ACTION" and wool:getContainer() == farCupboard,
    "arrival returns to the craft action without transferring the distant item")
controller:updateBaseTaskAction(802)
local farAction = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "at the distant source the same native transfer owner is queued")
assert(farAction.item == wool and controller.baseTaskBedPlan.phase == "craft_supply_move",
    "the exact native-selected distant item is the one transferred")
assert(P.setBaseStorageFilters(ingredientBase.id, farReference, {["item:Base.Awl"]=true}))
assert(not farAction:isValid(), "distant retrieval rechecks changed storage filters")
farAction:transferItem(wool)
assert(wool:getContainer() == farCupboard, "revoked filters prevent the distant transfer")
assert(P.setBaseStorageFilters(ingredientBase.id, farReference, {general=true}))
position = workSquare
assert(not farAction:isValid(), "distant retrieval cannot become a remote transfer")
position = approachFar
assert(farAction:isValid())
farAction:transferItem(wool)
assert(wool:getContainer() == inventory, "nearby permission admits the actual distant transfer")
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(803)
assert(wool:getContainer() == inventory and not controller.baseTaskActionQueued
    and controller.baseTaskBedReturn == true and controller.baseTaskBedSurface == workSquare,
    "a delivered distant ingredient requests the return leg to the selected surface")
controller:updateBaseTaskAction(804)
assert(controller.state == "BASE_TASK_MOVE" and controller.baseTaskBedPlan.phase == "craft_return"
    and destination == returnNear and moveCount == 2,
    "the return leg walks to the surface through the same movement owner")
position, movement = returnNear, "Succeeded"
controller:tick(805)
assert(controller.state == "BASE_TASK_ACTION"
    and controller.baseTaskBedPlan ~= nil and controller.baseTaskBedPlan.phase == "craft_return",
    "return arrival hands the craft task back to its action loop at the surface")
controller:updateBaseTaskAction(806)
assert(controller.baseTaskBedReturn == false, "native selection at the surface clears the return leg")
local farCraft = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the installed recipe runs from carried containers after the round trip")
assert(farCraft.logic ~= nil and farCraft.logic.started == farCraft
    and farCraft.logic.containers:size() == 1 and controller.baseTaskBedPlan == nil
    and recipeTask.state == "claimed",
    "the round trip ends in an executable carried-only craft")
inventory:remove(wool) wool.container = nil
local farProduced = ingredient("Base.SleepingBag_Hide_Packed")
farProduced.container = inventory farProduced.getWorldItem = function() return nil end
inventory:add(farProduced) farCraft.logic.outputs[1] = farProduced
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(807)
assert(recipeTask.state == "complete" and recipeTask.result == "sleeping_bag_crafted" and topUps == 0,
    "the distant-input craft completes only on actual native output")
C.isNativeRecoveryBusy = recoveryBusyDistant
AdjacentFreeTileFinder.Find = oldFindDistant
-- Forbidden native selection: the read-only projection may name an input the
-- settlement will not release. The installed recipe is asked once more without
-- that source; if it still cannot offer a permitted input the craft is refused
-- by name, with no transfer, no consumption and no leftover runtime plan.
now = 23
inventory:remove(farProduced) farProduced.container = nil
local spoken = {}
local originalSpeak = KnoxActivityFeed.speak
KnoxActivityFeed.speak = function(_, text) spoken[#spoken + 1] = tostring(text) end
local altStock = {}
local wool2 = {container = nil, getFullType = function() return "Base.WoolRaw" end,
    IsInventoryContainer = function() return false end,
    getContainer = function(self) return self.container end, getCount = function() return 1 end}
local altCupboard = {getType=function() return "crate" end,isExistYet=function() return true end,
    getItems=function() return list(altStock) end,isInCharacterInventory=function() return false end,
    getSourceGrid=function() return returnNear end,getParent=function() return nil end,
    contains=function(_, item) return list(altStock):contains(item) end,
    remove=function(_, item) list(altStock):remove(item) end}
local altObject = {getObjectIndex=function() return 1 end,getSquare=function() return returnNear end,
    getContainerCount=function() return 1 end,getContainerByIndex=function() return altCupboard end,
    getProperties=function() return {get=function() return "" end} end}
returnNear.getObjects = function() return list({cupboardObject, altObject}) end
wool.container, wool2.container, altStock[1] = farCupboard, altCupboard, wool2
farStock[1] = wool
selectedInputs, nativeMissing = {wool, wool2, awl}, false
local altReference = {key="recipe-alt",x=41,y=40,z=0,objectIndex=1,containerIndex=0,containerType="crate"}
assert(P.setBaseStorageFilters(ingredientBase.id, altReference, {["item:Base.Awl"]=true}))
assert(P.setBaseStorageFilters(ingredientBase.id, farReference, {["item:Base.Awl"]=true}))
ensureBeds(ingredientBase, faction)
local blockedPlan = manager.bedCraftPlan(ingredientBase, body)
assert(blockedPlan ~= nil and blockedPlan.phase == "craft_blocked"
    and blockedPlan.itemType == "Base.WoolRaw" and blockedPlan.reason == "recipe_input_forbidden",
    "a native-selected forbidden input becomes a named refusal, not a silent substitution")
local function freshCraftTask(tag)
    local record = assert(KnoxBaseTaskBoard.queue(ingredientBase.id, "craft_bed",
        {id="bed-craft-blocked:"..tostring(tag),x=40,y=40,z=0}, {}, 92))
    assert(P.claimBaseTask(ingredientBase.id, record.id, id, now))
    record.baseId = ingredientBase.id
    controller.baseTask = record
    return record
end
local blockedTask = freshCraftTask("refuse")
controller.baseTaskActionQueued, controller.baseTaskActionWatch = false, nil
controller.baseTaskBedPlan, controller.baseTaskBedApproach = {phase="craft_supply",item=wool2}, returnNear
controller.baseTaskBedSurface, controller.baseTaskBedReturn = workSquare, true
controller.nextBedRecipeBlockedSpeech = 0
assert(controller:beginBaseTaskSupplyOrWork(900) == false)
assert(blockedTask.state == "blocked"
    and tostring(blockedTask.result) == "recipe_input_forbidden:Base.WoolRaw",
    "the refusal is recorded through the existing task writer")
assert(#spoken == 1 and string.find(spoken[1], "not allowed", 1, true) ~= nil,
    "the survivor says why the craft did not happen")
assert(wool:getContainer() == farCupboard and wool2:getContainer() == altCupboard
    and #inventoryItems == 1 and inventoryItems[1] == awl,
    "a forbidden selection transfers and consumes nothing")
assert(controller.baseTaskBedPlan == nil and controller.baseTaskBedApproach == nil
    and controller.baseTaskBedSurface == nil and controller.baseTaskBedReturn == nil
    and controller.baseTaskActionQueued == false and controller.baseTaskActionWatch == nil,
    "the refused plan leaves no runtime bed or plan state behind")
assert((ISTimedActionQueue.queues[body] == nil or #ISTimedActionQueue.queues[body].queue == 0)
    and topUps == 0, "the refusal queues no native action and mints no supply")
-- Ask again after permitting the alternative: the installed recipe now picks the
-- permitted item and the ordinary carried-only craft completes.
assert(P.setBaseStorageFilters(ingredientBase.id, altReference, {general=true}))
local reselectTask = freshCraftTask("reselect")
controller.baseTaskActionQueued, controller.baseTaskActionWatch = false, nil
controller.baseTaskBedPlan, controller.baseTaskBedApproach = nil, nil
controller.baseTaskBedSurface, controller.baseTaskBedReturn = nil, nil
assert(controller:beginBaseTaskSupplyOrWork(910),
    "a permitted alternative re-selection starts the craft task")
controller:updateBaseTaskAction(911)
local reselectAction = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "re-asked native selection admits a permitted alternative")
assert(controller.baseTaskBedPlan.phase == "craft_supply" and reselectAction.item == wool2,
    "the installed recipe chooses the permitted alternative itself")
reselectAction:transferItem(wool2)
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(912)
controller:updateBaseTaskAction(913)
local reselectCraft = assert(controller.baseTaskActionWatch.action,
    "the permitted alternative still crafts from carried containers")
assert(wool:getContainer() == farCupboard, "the forbidden input was never touched")
inventory:remove(wool2) wool2.container = nil
local reselectOutput = ingredient("Base.SleepingBag_Hide_Packed")
reselectOutput.container = inventory reselectOutput.getWorldItem = function() return nil end
inventory:add(reselectOutput) reselectCraft.logic.outputs[1] = reselectOutput
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(914)
assert(reselectTask.state == "complete" and reselectTask.result == "sleeping_bag_crafted"
    and topUps == 0, "the permitted re-selection completes only on actual output")
-- Cross-floor stored ingredient: native selection may name an item stored on
-- another loaded floor of the same site. The walk uses the existing task
-- movement owner; at the source the same nearby permission admits the exact
-- transfer, then the worker returns to the selected work surface for fresh
-- native selection and carried-only crafting. The site is a fresh faction base
-- on its own tiles, so its measured bed shortage and room ownership are the
-- ordinary owners' answers, not inherited state.
now, inventoryItems = 24, {awl}
local crossBase = {id="recipe-cross-base",ownerKind="faction",ownerId=faction.id,
    tasks={},zones={},settings={autoBarricade=false},
    home={buildingId="recipe-building",minX=60,minY=60,width=2,height=1,z=0,allFloors=true}}
root.bases[crossBase.id] = crossBase
root.survivors[id].duty = {mode="base",baseId=crossBase.id,allowLootRuns=true}
controller.base, controller.baseId = crossBase, crossBase.id
local function floorSquare(x, z)
    return {getX=function() return x end,getY=function() return 60 end,getZ=function() return z end,
        getBuilding=function() return {getDef=function() return definition end} end,
        getWorldObjects=function() return list({}) end, isOutside=function() return false end}
end
local lowerWork, nearSquare = floorSquare(60,0), floorSquare(61,0)
local upperStore, upperApproach = floorSquare(61,1), floorSquare(60,1)
lowerWork.getObjects = function() return list({surface}) end
local crossStock = {}
local crossCupboard = {getType=function() return "crate" end,isExistYet=function() return true end,
    getItems=function() return list(crossStock) end,isInCharacterInventory=function() return false end,
    getSourceGrid=function() return upperStore end,getParent=function() return nil end,
    contains=function(_, item) return list(crossStock):contains(item) end,
    remove=function(_, item) list(crossStock):remove(item) end}
local crossObject = {getObjectIndex=function() return 0 end,getSquare=function() return upperStore end,
    getContainerCount=function() return 1 end,getContainerByIndex=function() return crossCupboard end,
    getProperties=function() return {get=function() return "" end} end}
upperStore.getObjects = function() return list({crossObject}) end
upperApproach.getObjects = function() return list({}) end
local nearStock = {}
local nearCupboard = {getType=function() return "crate" end,isExistYet=function() return true end,
    getItems=function() return list(nearStock) end,isInCharacterInventory=function() return false end,
    getSourceGrid=function() return nearSquare end,getParent=function() return nil end,
    contains=function(_, item) return list(nearStock):contains(item) end,
    remove=function(_, item) list(nearStock):remove(item) end}
local nearObject = {getObjectIndex=function() return 0 end,getSquare=function() return nearSquare end,
    getContainerCount=function() return 1 end,getContainerByIndex=function() return nearCupboard end,
    getProperties=function() return {get=function() return "" end} end}
nearSquare.getObjects = function() return list({nearObject}) end
getCell = function() return {getGridSquare=function(_, x,y,z)
    if y~=60 then return nil end
    if z==0 then return x==60 and lowerWork or (x==61 and nearSquare or nil)
    elseif z==1 then return x==61 and upperStore or (x==60 and upperApproach or nil) end
end} end
local oldFindFloor = AdjacentFreeTileFinder.Find
AdjacentFreeTileFinder.Find = function(target)
    if target==upperStore then return upperApproach end
    if target==lowerWork then return lowerWork end
    return nil
end
local crossReference = {key="recipe-cross",x=61,y=60,z=1,objectIndex=0,containerIndex=0,containerType="crate"}
local nearReference = {key="recipe-cross-near",x=61,y=60,z=0,objectIndex=0,containerIndex=0,containerType="crate"}
assert(P.setBaseStorageFilters(crossBase.id, crossReference, {general=true}))
assert(P.setBaseStorageFilters(crossBase.id, nearReference, {general=true}))
ensureBeds(crossBase, faction)
assert(manager.needsBedCraft(crossBase), "the cross-floor settlement has a measured bed shortage")
local function freshCrossTask(tag)
    local record = assert(KnoxBaseTaskBoard.queue(crossBase.id, "craft_bed",
        {id="bed-craft-cross:"..tostring(tag),x=60,y=60,z=0}, {}, 94))
    assert(P.claimBaseTask(crossBase.id, record.id, id, now))
    controller.baseTask = record
    return record
end
local crossWool = ingredient("Base.WoolRaw")
crossWool.container, crossStock[1] = crossCupboard, crossWool
selectedInputs, nativeMissing = {crossWool, awl}, false
position = lowerWork
local crossPlan = assert(manager.bedCraftPlan(crossBase, body),
    "a native-selected ingredient on another loaded floor plans a cross-floor ingredient trip")
assert(crossPlan.phase == "craft_supply_move" and crossPlan.item == crossWool
    and crossPlan.crossFloor == true and crossPlan.approach == upperApproach
    and crossPlan.surface == lowerWork,
    "the cross-floor plan names the exact item, the other-floor approach and the return surface")
local crossTask = freshCrossTask("cross-floor")
controller.baseTaskActionQueued, controller.baseTaskActionWatch = false, nil
controller.baseTaskBedPlan, controller.baseTaskBedApproach = nil, nil
controller.baseTaskBedSurface, controller.baseTaskBedReturn = nil, nil
local crossDest, crossMoves, crossReport = nil, 0, "Working"
controller.bridge = {moveNpc=function(_, who, target)
        assert(who == id) crossDest, crossMoves = target, crossMoves + 1 return "MOVE_STARTED"
    end, tickNpc=function() return crossReport end, cancelNpcMove=function() end}
assert(controller:beginBaseTaskSupplyOrWork(1000) and controller.state == "BASE_TASK_MOVE"
    and crossDest == upperApproach and crossMoves == 1,
    "the cross-floor ingredient trip starts through the existing task movement owner")
assert(controller.baseTaskBedPlan.phase == "craft_supply_move"
    and controller.baseTaskBedPlan.item == crossWool
    and crossWool:getContainer() == crossCupboard,
    "nothing is transferred before the resident reaches the other floor")
position, crossReport = upperApproach, "Succeeded"
controller:tick(1001)
assert(controller.state == "BASE_TASK_ACTION" and crossWool:getContainer() == crossCupboard,
    "arrival on the other floor returns to the craft action without a remote pickup")
controller:updateBaseTaskAction(1002)
local crossAction = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "at the cross-floor source the same native transfer owner is queued")
assert(crossAction.item == crossWool and controller.baseTaskBedPlan.phase == "craft_supply_move"
    and crossAction:isValid(), "the exact cross-floor native-selected item passes the nearby checks")
crossAction:transferItem(crossWool)
assert(crossWool:getContainer() == inventory, "the permitted cross-floor item is really carried")
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(1003)
assert(controller.baseTaskBedReturn == true and controller.baseTaskBedSurface == lowerWork
    and not controller.baseTaskActionQueued,
    "a delivered cross-floor ingredient requests the return leg to the selected surface")
controller:updateBaseTaskAction(1004)
assert(controller.state == "BASE_TASK_MOVE" and controller.baseTaskBedPlan.phase == "craft_return"
    and crossDest == lowerWork and crossMoves == 2,
    "the return leg crosses back to the surface through the same movement owner")
position, crossReport = lowerWork, "Succeeded"
controller:tick(1005)
assert(controller.state == "BASE_TASK_ACTION"
    and controller.baseTaskBedPlan ~= nil and controller.baseTaskBedPlan.phase == "craft_return",
    "return arrival hands the craft task back to its action loop at the surface")
controller:updateBaseTaskAction(1006)
assert(controller.baseTaskBedReturn == false,
    "native selection at the work surface clears the cross-floor return leg")
local crossCraft = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the installed recipe runs from carried containers after the cross-floor round trip")
assert(crossCraft.logic ~= nil and crossCraft.logic.started == crossCraft
    and crossCraft.logic.containers:size() == 1 and controller.baseTaskBedPlan == nil,
    "the cross-floor trip ends in an executable carried-only craft")
inventory:remove(crossWool) crossWool.container = nil
local crossOutput = ingredient("Base.SleepingBag_Hide_Packed")
crossOutput.container, crossOutput.getWorldItem = inventory, function() return nil end
inventory:add(crossOutput) crossCraft.logic.outputs[1] = crossOutput
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(1007)
assert(crossTask.state == "complete" and crossTask.result == "sleeping_bag_crafted"
    and topUps == 0, "the cross-floor ingredient craft completes only on actual native output")

-- The approach owner can name a square on the other floor, but the installed
-- movement owner can still report no route. That is a named refusal with a
-- spoken reason, not a partial transfer or an endless walk.
now, inventoryItems = 25, {awl}
inventory:remove(crossOutput) crossOutput.container = nil
local laneWool = ingredient("Base.WoolRaw")
laneWool.container, crossStock[1] = crossCupboard, laneWool
selectedInputs = {laneWool, awl}
ensureBeds(crossBase, faction)
position = lowerWork
local plannedLane = assert(manager.bedCraftPlan(crossBase, body),
    "a cross-floor source with an approach first plans the walk the movement owner must report on")
assert(plannedLane.phase == "craft_supply_move" and plannedLane.crossFloor == true,
    "the unreachable row starts from a real cross-floor movement plan")
local unreachableTask = freshCrossTask("cross-unreachable")
controller.baseTaskActionQueued, controller.baseTaskActionWatch = false, nil
controller.baseTaskBedPlan, controller.baseTaskBedApproach = nil, nil
controller.baseTaskBedSurface, controller.baseTaskBedReturn = nil, nil
controller.nextBedRecipeBlockedSpeech = 0
local spokenBefore = #spoken
controller.bridge = {moveNpc=function() return "MOVE_FAILED NO_ROUTE" end,
    tickNpc=function() return "Working" end, cancelNpcMove=function() end}
assert(controller:beginBaseTaskSupplyOrWork(1100) == false)
assert(unreachableTask.state == "blocked"
    and tostring(unreachableTask.result) == "recipe_input_unreachable:Base.WoolRaw",
    "a cross-floor route the movement owner cannot reach is refused by name")
assert(#spoken == spokenBefore + 1
    and string.find(spoken[#spoken], "can't get to", 1, true) ~= nil,
    "the survivor says the ingredient store cannot be reached")
assert(laneWool:getContainer() == crossCupboard and #inventoryItems == 1
    and inventoryItems[1] == awl, "an unreachable cross-floor refusal transfers and consumes nothing")
assert(controller.baseTaskBedPlan == nil and controller.baseTaskBedApproach == nil
    and controller.baseTaskBedSurface == nil and controller.baseTaskBedReturn == nil
    and controller.baseTaskActionQueued == false and controller.baseTaskActionWatch == nil,
    "the unreachable refusal leaves no runtime bed, plan or return state behind")
assert((ISTimedActionQueue.queues[body] == nil or #ISTimedActionQueue.queues[body].queue == 0)
    and topUps == 0, "the unreachable refusal queues no native action and mints no supply")
-- A floor the approach owner cannot stand on is the same named refusal before
-- any route is attempted.
AdjacentFreeTileFinder.Find = function(target)
    if target==lowerWork then return lowerWork end
    return nil
end
local blockedFloor = assert(manager.bedCraftPlan(crossBase, body),
    "a cross-floor source with no usable approach is still a named refusal")
assert(blockedFloor.phase == "craft_blocked" and blockedFloor.reason == "recipe_input_unreachable"
    and blockedFloor.itemType == "Base.WoolRaw",
    "a cross-floor source with no usable approach is refused as unreachable, not substituted")
AdjacentFreeTileFinder.Find = function(target)
    if target==upperStore then return upperApproach end
    if target==lowerWork then return lowerWork end
    return nil
end
-- Ask again after the recipe can select a permitted nearby input: the ordinary
-- carried-only craft still completes.
now = 26
local recoveryWool = ingredient("Base.WoolRaw")
recoveryWool.container, nearStock[1] = nearCupboard, recoveryWool
selectedInputs = {recoveryWool, awl}
ensureBeds(crossBase, faction)
local recoveryTask = freshCrossTask("cross-recover")
controller.baseTaskActionQueued, controller.baseTaskActionWatch = false, nil
controller.baseTaskBedPlan, controller.baseTaskBedApproach = nil, nil
controller.baseTaskBedSurface, controller.baseTaskBedReturn = nil, nil
position = lowerWork
controller.bridge = {moveNpc=function() return "MOVE_STARTED" end,
    tickNpc=function() return "Succeeded" end, cancelNpcMove=function() end}
assert(controller:beginBaseTaskSupplyOrWork(1200) and controller.state == "BASE_TASK_ACTION",
    "after a cross-floor refusal a permitted re-selection starts the craft task")
controller:updateBaseTaskAction(1201)
local recoveryAction = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the re-selected permitted input is retrieved through the ordinary transfer owner")
assert(controller.baseTaskBedPlan.phase == "craft_supply" and recoveryAction.item == recoveryWool,
    "the installed recipe chooses the permitted nearby input itself")
recoveryAction:transferItem(recoveryWool)
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(1202)
controller:updateBaseTaskAction(1203)
local recoveryCraft = assert(controller.baseTaskActionWatch and controller.baseTaskActionWatch.action,
    "the permitted re-selection still crafts from carried containers")
assert(recoveryCraft.logic ~= nil and recoveryCraft.logic.started == recoveryCraft,
    "the re-selected craft starts through the native action owner")
inventory:remove(recoveryWool) recoveryWool.container = nil
local recoveryOutput = ingredient("Base.SleepingBag_Hide_Packed")
recoveryOutput.container, recoveryOutput.getWorldItem = inventory, function() return nil end
inventory:add(recoveryOutput) recoveryCraft.logic.outputs[1] = recoveryOutput
ISTimedActionQueue.queues[body].queue = {}
controller:updateBaseTaskAction(1204)
assert(recoveryTask.state == "complete" and recoveryTask.result == "sleeping_bag_crafted"
    and topUps == 0, "the permitted re-selection after a cross-floor refusal completes only on real output")
AdjacentFreeTileFinder.Find = oldFindFloor

KnoxActivityFeed.speak = originalSpeak
HandcraftLogic.new=previousLogic
for _, name in ipairs(names) do _G[name] = saved[name] end
print("Bed craft PASS realBedOwner=true taskDiscovery=true admission=true queue=true outputReceipt=true noInventedBed=true duplicateGuard=true nativeGameplay=false")
