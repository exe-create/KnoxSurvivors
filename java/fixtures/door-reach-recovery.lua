-- A door edge refused for reach names the door but not an adjacent body:
-- Java openNativeDoor answers FAILED_DOOR_OUT_OF_REACH while the survivor is
-- still outside (diagonal approach, body/square drift, a two-tile edge). No
-- Lua owner named that token, so formation cancelled to GROUP_WAIT, supply
-- and explore fell to the generic retry, and base-task supply failed the
-- task. The reach failure now shares the existing door owner without the
-- window-detour priority: the fix is one more step, not another room.
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

local REACH = "TICK_FAILED:FailedObstacle:FAILED_DOOR_OUT_OF_REACH"
assert(C.isDoorReachFailure(REACH),
    "the out-of-reach door edge is a reach failure")
assert(C.isDoorReachFailure("FailedObstacle:FAILED_DOOR_OUT_OF_REACH"),
    "reach is recognized without the tick prefix")
for _, other in ipairs({
    "TICK_FAILED:FailedObstacle:FAILED_LOCKED_DOOR",
    "FailedObstacle:FAILED_DOOR_OPENING_DISABLED",
    "FailedObstacle:FAILED_BLOCKED_DIAGONAL",
    "TICK_FAILED:FailedObstacle",
    "TICK_FAILED:FailedObstacle:FAILED_EDGE_COOLDOWN",
    "", nil,
}) do
    assert(not C.isDoorReachFailure(other),
        "locks, cooldowns and plain obstacles are not reach failures")
end
assert(not C.isEntryTraversalFailure(REACH),
    "reach keeps its own owner and never takes the window-detour priority")
assert(not C.isFollowObstacleFailure(REACH),
    "reach keeps its own owner and never shares the obstacle retry")

local door = {
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
            get = function() return door end,
        }
    end,
}
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

local function followController(state, withDoor)
    local square = withDoor and current or {
        getX = function() return 10 end,
        getY = function() return 10 end,
        getZ = function() return 0 end,
    }
    local opened = nil
    local c = setmetatable({
        id = "reach-follow",
        state = state,
        observedState = state,
        stateStartedAt = 100,
        nextThink = math.huge,
        nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge,
        counts = { search = 0 },
        character = {
            getCurrentSquare = function() return square end,
            getCharacterActions = function() return nil end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
        },
        bridge = {
            tickNpc = function() return REACH end,
            openNpcDoor = function(_, _, which)
                if not withDoor then error("no door to open") end
                opened = which
                return "OPENING_DOOR"
            end,
            cancelNpcMove = function() end,
        },
    }, C)
    c.applyPendingCombatPolicy = function() return true end
    c.recordFailure = function(self, reason) self.failure = reason end
    return c, function() return opened end
end

for _, state in ipairs({ "GROUP_FOLLOW", "COMPANION_FOLLOW" }) do
    local c, opened = followController(state, true)
    assert(c:handleFormationMovementFailure(REACH, 100) == true,
        "a reach refusal beside a shut door uses the door owner: " .. state)
    assert(opened() == door,
        "the adjacent shut door is opened on a reach refusal: " .. state)
    assert(c.state == state and c.formationDoorRetry ~= nil
        and c.formationDoorRetry.count == 1,
        "the door retry holds the follow without cancelling: " .. state)
end

local stranded, strandedOpened = followController("GROUP_FOLLOW", false)
assert(stranded:handleFormationMovementFailure(REACH, 100) == true,
    "a doorless reach refusal schedules its bounded retry")
assert(stranded.state == "GROUP_FOLLOW"
    and stranded.formationDoorRetry ~= nil
    and stranded.formationDoorRetry.count == 1
    and stranded.formationDoorRetry.opened == false,
    "a doorless reach refusal records the attempt without opening")

local exhausted = followController("GROUP_FOLLOW", true)
exhausted.formationDoorRetry = { count = 3 }
local released = exhausted:handleFormationMovementFailure(REACH, 100)
assert(released ~= true and exhausted.state == "GROUP_WAIT"
    and exhausted.formationDoorRetry == nil,
    "an unreachable door escalates instead of holding the follow")

local openedSupply = nil
local function drive(state, movementText, pendingSupply)
    openedSupply = nil
    local controller = setmetatable({
        id = "reach-supply",
        state = state,
        observedState = state,
        activeDecision = "loot_useful_items_1",
        stateStartedAt = 100,
        nextThink = math.huge,
        nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge,
        nextRoamNeedsCheck = math.huge,
        counts = { search = 0, failures = 0 },
        selfCareRetryAt = {},
        blockedAreas = {},
        recentRoamGoals = {},
        roamGoalOrder = {},
        inspectedContainers = {},
        pendingSupply = pendingSupply,
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
            tickNpc = function() return movementText end,
            openNpcDoor = function(_, _, which)
                openedSupply = which
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
    return controller
end

local supply = { targetSquare = current }
local c = drive("MOVING_TO_SUPPLY", REACH, supply)
assert(openedSupply == door,
    "a supply reach refusal beside a closed door is handed to the door owner")
assert(c.finishedAt == 100,
    "the recovered door attempt finishes the failed supply move through one decision")

c = drive("ROAMING", REACH, supply)
assert(openedSupply == nil,
    "a reach refusal outside supply/explore never touches the door owner")
assert(c.finishedAt == 100,
    "the unaffected state still finishes its failed move")

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    _G[name] = saved[name]
end
C.isNativeRecoveryBusy, C.isNativeAttackBusy = previousRecoveryBusy, previousAttackBusy
print("Door reach recovery PASS reachNamed=true doorOwned=true stateGated=true")
