-- A closed garage door can stop the native route as a plain obstacle rather
-- than as FAILED_LOCKED_DOOR. The survivor must open the adjacent door through
-- the existing door owner instead of starting an alternate-entry tour.
local C = assert(KnoxAutonomyController)
local saved = {}
for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    saved[name] = rawget(_G, name)
end
local previousRecoveryBusy, previousAttackBusy =
    C.isNativeRecoveryBusy, C.isNativeAttackBusy
C.isNativeRecoveryBusy = function() return false end
C.isNativeAttackBusy = function() return false end
KnoxCompanionVehicles = nil

local garage = {
    isDoor = true,
    IsOpen = function() return false end,
    isLocked = function() return false end,
    isLockedByKey = function() return false end,
    isBarricaded = function() return false end,
}
local current = {
    getX = function() return 10 end,
    getY = function() return 10 end,
    getZ = function() return 0 end,
    getObjects = function()
        return {
            size = function() return 1 end,
            get = function() return garage end,
        }
    end,
}
garage.getSquare = function() return current end
local cell = {
    getGridSquare = function(_, x, y, z)
        if x == 10 and y == 10 and z == 0 then return current end
        return nil
    end,
}
getCell = function() return cell end
instanceof = function(object, kind)
    return kind == "IsoDoor" and object ~= nil and object.isDoor == true
end

local opened = nil
local controller = setmetatable({
    id = "garage-fixture",
    state = "MOVING_TO_EXPLORE",
    observedState = "MOVING_TO_EXPLORE",
    activeDecision = "loot_useful_items_1",
    stateStartedAt = 100,
    nextThink = math.huge,
    nextThreatScan = math.huge,
    nextIdleLatchCheck = math.huge,
    counts = { search = 0, failures = 0 },
    selfCareRetryAt = {},
    pendingSupply = { targetSquare = current },
    character = {
        getCurrentSquare = function() return current end,
        getCharacterActions = function()
            return { isEmpty = function() return true end }
        end,
        getCurrentStateName = function() return "idle" end,
        getCurrentActionContextStateName = function() return "idle" end,
        getVehicle = function() return nil end,
        isDead = function() return false end,
    },
    bridge = {
        tickNpc = function() return "TICK_FAILED:FailedObstacle" end,
        openNpcDoor = function(_, _, door)
            opened = door
            return "OPENING_DOOR"
        end,
        cancelNpcMove = function() end,
    },
}, C)
for _, name in ipairs({
    "applyPendingCombatPolicy", "checkSharedMeal", "observeGroupEntry",
    "recoverIdleAnimationLatch", "recoverFromDetached", "isSettlementSupplyEntry",
    "tryAutomaticPlayerAid", "yieldBaseTaskForNeed", "yieldInventoryCleanupForNeed",
    "yieldAidForNeed", "yieldCollectionForNeed", "waitingForTransferActions",
    "sharedMealPostureReady", "prepareRouteWindowGlass",
}) do
    controller[name] = function() return false end
end
controller.applyPendingCombatPolicy = function() return true end
controller.recordMovementFailure = function() end
controller.releaseSupply = function() end
controller.finishDecision = function(self, ticks)
    self.finishedAt = ticks
end

controller:tick(100)
assert(opened == garage,
    "a plain obstacle beside a closed garage door is handed to the door owner")
assert(controller.finishedAt == 100,
    "the recovered door attempt finishes the failed move through one decision")

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    _G[name] = saved[name]
end
C.isNativeRecoveryBusy, C.isNativeAttackBusy = previousRecoveryBusy, previousAttackBusy
print("Garage door obstacle PASS nativeDoorObject=true recoveryOwner=true alternateDetour=false")
