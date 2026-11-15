-- Door and corner recovery contract (owner request 2026-11-12).
--
-- When a route names an edge the body cannot take - a door it is not adjacent
-- to (FAILED_DOOR_OUT_OF_REACH) or a wall corner (FAILED_BLOCKED_DIAGONAL,
-- FAILED_STATIC_BLOCKAGE) - the survivor must land in the existing door
-- recovery owner and must NOT land in WAIT, the generic release-and-retry
-- path, or a failed job. This drives the real handler and the real tick; it
-- does not restate their logic.
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

local REACH = "FailedObstacle:FAILED_DOOR_OUT_OF_REACH"
local DIAGONAL = "FailedObstacle:FAILED_BLOCKED_DIAGONAL"
local STATIC = "FailedObstacle:FAILED_STATIC_BLOCKAGE"
local PLAIN = "FailedObstacle"
local REFUSALS = {
    { name = "reach", text = REACH },
    { name = "diagonal corner", text = DIAGONAL },
    { name = "static corner", text = STATIC },
}

local door = {
    isDoor = true,
    IsOpen = function() return false end,
    isLocked = function() return false end,
    isLockedByKey = function() return false end,
    isBarricaded = function() return false end,
}
local function makeSquare(withDoor)
    local square = {
        getX = function() return 10 end,
        getY = function() return 10 end,
        getZ = function() return 0 end,
    }
    if withDoor then
        square.getObjects = function()
            return {
                size = function() return 1 end,
                get = function() return door end,
            }
        end
    end
    return square
end
local doorSquare = makeSquare(true)
local bareSquare = makeSquare(false)
local function cellFor(square)
    return {
        getGridSquare = function(_, x, y, z)
            if square ~= nil and x == 10 and y == 10 and z == 0 then return square end
            return nil
        end,
    }
end
instanceof = function(object, kind)
    return kind == "IsoDoor" and object ~= nil and object.isDoor == true
end

-- PART A: followers. The real handler must claim the attempt, open the real
-- door, and stay in follow. WAIT is the pre-fix symptom.
local function followController(state, withDoor)
    local square = withDoor and doorSquare or bareSquare
    getCell = function() return cellFor(square) end
    local opened = nil
    local c = setmetatable({
        id = "contract-follow",
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
            openNpcDoor = function(_, _, which)
                if not withDoor then error("no door to open") end
                opened = which
                return "OPENING_DOOR"
            end,
            cancelNpcMove = function() end,
        },
    }, C)
    c.bridge.cancelNpcMove = function() c.cancelled = true end
    c.applyPendingCombatPolicy = function() return true end
    c.recordFailure = function(self2, reason) self2.failure = reason end
    return c, function() return opened end
end

for _, refusal in ipairs(REFUSALS) do
    for _, state in ipairs({ "GROUP_FOLLOW", "COMPANION_FOLLOW" }) do
        local c, opened = followController(state, true)
        c:handleFormationMovementFailure("TICK_FAILED:" .. refusal.text, 100)
        assert(opened() == door,
            "a " .. refusal.name .. " refusal beside a shut door reaches the door owner ("
                .. state .. ")")
        assert(c.state == state,
            "a " .. refusal.name .. " refusal does not send the follower to WAIT ("
                .. state .. ")")
        assert(c.formationDoorRetry ~= nil and c.formationDoorRetry.count == 1,
            "a " .. refusal.name .. " refusal is owned by the bounded door retry ("
                .. state .. ")")
    end
end

-- A refuser with no door nearby still holds the follow for its bounded retry
-- instead of cancelling into WAIT; the bound then escalates (deliberate).
local doorless, doorlessOpened = followController("GROUP_FOLLOW", false)
doorless:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100)
assert(doorlessOpened() == nil and doorless.state == "GROUP_FOLLOW"
    and doorless.formationDoorRetry.count == 1,
    "a doorless corner holds the follow on its bounded retry")
local spent, spentOpened = followController("GROUP_FOLLOW", true)
spent.formationDoorRetry = { count = 3 }
assert(spent:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100) ~= true
    and spent.state == "GROUP_WAIT",
    "an exhausted corner retry still escalates instead of looping")

-- PART B: supply and explore travel through the real tick. Recovery must open
-- the door and finish the failed move through one decision, without
-- blacklisting the container area (the generic give-up path).
local function travelController(state, movementText, withDoor)
    local square = withDoor and doorSquare or bareSquare
    getCell = function() return cellFor(square) end
    local c = setmetatable({
        id = "contract-travel",
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
        pendingSupply = { targetSquare = square },
        baseTask = { type = "supply", id = "job-1", target = {} },
        baseTaskSupplyTransfer = nil,
        character = {
            getCurrentSquare = function() return square end,
            getCharacterActions = function()
                return { isEmpty = function() return true end }
            end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
            getVehicle = function() return nil end,
            isDead = function() return false end,
        },
        bridge = { tickNpc = function() return movementText end },
    }, C)
    -- Assigned after construction: a closure written inside the table literal
    -- cannot see the controller it belongs to under the installed Kahlua.
    c.bridge.openNpcDoor = function(_, _, which)
        if not withDoor then error("no door to open") end
        c.doorOpened = which
        return "OPENING_DOOR"
    end
    c.bridge.cancelNpcMove = function() c.cancelCount = (c.cancelCount or 0) + 1 end
    for _, name in ipairs({
        "applyPendingCombatPolicy", "checkSharedMeal", "observeGroupEntry",
        "recoverIdleAnimationLatch", "recoverFromDetached", "isSettlementSupplyEntry",
        "tryAutomaticPlayerAid", "yieldBaseTaskForNeed", "yieldInventoryCleanupForNeed",
        "yieldAidForNeed", "yieldCollectionForNeed", "waitingForTransferActions",
        "sharedMealPostureReady", "prepareRouteWindowGlass", "releaseSupply",
        "releaseBaseTaskSupplyTransfer",
    }) do
        c[name] = function() return false end
    end
    c.applyPendingCombatPolicy = function() return true end
    c.recordMovementFailure = function(self2, kind, text)
        self2.lastRecordedFailure = tostring(kind) .. ":" .. tostring(text)
    end
    c.finishDecision = function(self2, ticks) self2.finishedAt = ticks end
    c.finishBaseTask = function(self2, ok, reason)
        self2.jobFinishedAt = { ok = ok, reason = tostring(reason) }
    end
    return c
end

local function isEmpty(t)
    for _ in pairs(t or {}) do return false end
    return true
end

for _, refusal in ipairs(REFUSALS) do
    for _, state in ipairs({ "MOVING_TO_SUPPLY", "MOVING_TO_EXPLORE" }) do
        local c = travelController(state, "TICK_FAILED:" .. refusal.text, true)
        c:tick(100)
        assert(c.doorOpened == door,
            "a " .. refusal.name .. " refusal in " .. state .. " opens the shut door")
        assert(c.finishedAt == 100,
            "a " .. refusal.name .. " refusal in " .. state
                .. " finishes the failed move through one decision")
        assert(isEmpty(c.blockedAreas),
            "a " .. refusal.name .. " refusal in " .. state
                .. " does not blacklist the container area")
    end
end

-- PART C: base-task supply. The same refusals must keep the job, not fail it.
for _, refusal in ipairs(REFUSALS) do
    local c = travelController("BASE_TASK_SUPPLY_MOVE",
        "TICK_FAILED:" .. refusal.text, true)
    c:tick(100)
    assert(c.doorOpened == door,
        "a " .. refusal.name
            .. " refusal while fetching job supplies opens the shut door")
    assert(c.jobFinishedAt == nil,
        "a " .. refusal.name
            .. " refusal while fetching job supplies does not fail the job")
    assert(c.state == "BASE_TASK_SUPPLY_MOVE",
        "a " .. refusal.name
            .. " refusal while fetching job supplies holds the job state")
end

-- A plain (unclassified) obstacle is the garage shape at a supply job too: it
-- opens the door and keeps the job instead of failing it outright.
local garage = travelController("BASE_TASK_SUPPLY_MOVE", "TICK_FAILED:" .. PLAIN, true)
garage:tick(100)
assert(garage.doorOpened == door and garage.jobFinishedAt == nil,
    "a plain obstacle while fetching job supplies opens the door and keeps the job")

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    _G[name] = saved[name]
end
C.isNativeRecoveryBusy, C.isNativeAttackBusy = previousRecoveryBusy, previousAttackBusy
print("Door corner recovery PASS followOwned=true travelOwned=true jobKept=true")
