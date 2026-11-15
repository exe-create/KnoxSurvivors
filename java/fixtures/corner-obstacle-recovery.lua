-- A named wall-corner refusal (diagonal clip, blocked cardinal edge) is the
-- same shape as a plain obstacle: the engine would not take that line, not
-- the room. Supply/explore travel must offer the existing door owner and
-- alternate entry before the generic retry; other states and the edge
-- cooldown must not touch the door owner.
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

local door = {
    isDoor = true,
    IsOpen = function() return false end,
    isLocked = function() return false end,
    isLockedByKey = function() return false end,
    isBarricaded = function() return false end,
}
local function makeWorld(withDoor)
    local current = {
        getX = function() return 10 end,
        getY = function() return 10 end,
        getZ = function() return 0 end,
        getObjects = function()
            if withDoor then
                return {
                    size = function() return 1 end,
                    get = function() return door end,
                }
            end
            return {
                size = function() return 0 end,
                get = function() return nil end,
            }
        end,
    }
    door.getSquare = function() return current end
    return current, {
        getGridSquare = function(_, x, y, z)
            if x == 10 and y == 10 and z == 0 then return current end
            return nil
        end,
    }
end

local current, cell = makeWorld(true)
getCell = function() return cell end
instanceof = function(object, kind)
    return kind == "IsoDoor" and object ~= nil and object.isDoor == true
end

local opened = nil
local function drive(state, movementText, pendingSupply, refuseDoor)
    opened = nil
    local controller = setmetatable({
        id = "corner-fixture",
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
                if refuseDoor then refuseDoor.count = refuseDoor.count + 1; return "FAILED_DOOR_OUT_OF_REACH" end
                opened = which
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
    if refuseDoor then controller.beginWindowDetour = function() refuseDoor.detour = true; return true end end
    controller:tick(100)
    return controller
end

local supply = { targetSquare = current }
local refusal = {count = 0}
drive("MOVING_TO_EXPLORE", "TICK_FAILED:FailedObstacle:FAILED_BLOCKED_DIAGONAL", supply, refusal)
assert(refusal.count == 1 and refusal.detour, "one refused door attempt hands the corner to alternate entry")
local c = drive("MOVING_TO_EXPLORE", "TICK_FAILED:FailedObstacle:FAILED_BLOCKED_DIAGONAL", supply)
assert(opened == door,
    "a diagonal clip beside a closed door is handed to the door owner")
assert(c.finishedAt == 100,
    "the recovered door attempt finishes the failed move through one decision")

c = drive("MOVING_TO_SUPPLY", "TICK_FAILED:FailedObstacle:FAILED_STATIC_BLOCKAGE", supply)
assert(opened == door,
    "a blocked cardinal edge beside a closed door is handed to the door owner")
assert(c.finishedAt == 100,
    "the recovered door attempt finishes the failed supply move through one decision")

c = drive("ROAMING", "TICK_FAILED:FailedObstacle:FAILED_BLOCKED_DIAGONAL", supply)
assert(opened == nil,
    "a diagonal clip outside supply/explore never touches the door owner")
assert(c.finishedAt == 100,
    "the unaffected state still finishes its failed move")

c = drive("MOVING_TO_EXPLORE", "TICK_FAILED:FailedObstacle:FAILED_EDGE_COOLDOWN", supply)
assert(opened == nil,
    "an edge cooldown is a wait, not a refusal, and never touches the door owner")
assert(c.finishedAt == 100,
    "the cooling move still finishes through the generic path")

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    _G[name] = saved[name]
end
C.isNativeRecoveryBusy, C.isNativeAttackBusy = previousRecoveryBusy, previousAttackBusy
print("Corner obstacle recovery PASS doorOwner=true stateGated=true cooldownHeld=true")
