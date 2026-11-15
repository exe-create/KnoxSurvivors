-- Exercise the real movement tick, corner selector, task retry and waypoint
-- completion. World/native actions and unrelated tick arbitration are stubs.
local C = assert(KnoxAutonomyController)
local savedCell, savedVehicles, savedInstanceof = getCell, KnoxCompanionVehicles, instanceof
local savedJobs = KnoxBaseJobs
KnoxBaseJobs = {}
KnoxCompanionVehicles = nil
local DIAGONAL = "TICK_FAILED:FailedObstacle:FAILED_BLOCKED_DIAGONAL"
local squares, origin, goal
local function world()
    squares = {}
    for _, xy in ipairs({ {10,10}, {11,10}, {9,10}, {10,9}, {12,12} }) do
        local x, y = xy[1], xy[2]
        local s = {
            getX = function() return x end, getY = function() return y end,
            getZ = function() return 0 end, canStand = function() return true end,
            TreatAsSolidFloor = function() return true end, HasStairs = function() return false end,
            isBlockedTo = function() return false end, isWindowTo = function() return false end,
            isHoppableTo = function() return false end,
        }
        squares[x .. "," .. y] = s
    end
    origin, goal = squares["10,10"], squares["12,12"]
    getCell = function() return { getGridSquare = function(_, x, y, z)
        if z == 0 then return squares[x .. "," .. y] end
    end } end
    KnoxBaseJobs.resolveTaskSquare = function() return goal end
end

local function controller(state)
    world()
    local c = setmetatable({
        id = "corner-worker", state = state, observedState = state,
        stateStartedAt = 100, nextThink = math.huge, nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge, nextRoamNeedsCheck = math.huge,
        nextFormationRefresh = math.huge, companionOrder = "follow",
        counts = { search = 0, failures = 0, groupTravel = 0 },
        selfCareRetryAt = {}, blockedAreas = {}, inspectedContainers = {},
        recentRoamGoals = {}, roamGoalOrder = {}, moves = {}, movement = DIAGONAL,
        baseTask = { id = "corner-job", type = "repair", state = "claimed", claimedBy = "corner-worker" },
        baseTaskMoveSquare = goal,
        formationTargetX = 12, formationTargetY = 12, formationTargetZ = 0,
        character = {
            getCurrentSquare = function() return origin end,
            getCharacterActions = function() return {isEmpty = function() return true end} end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
            getVehicle = function() return nil end, isDead = function() return false end,
        },
    }, C)
    c.bridge = {
        tickNpc = function() return c.movement end,
        moveNpc = function(_, _, square)
            c.moves[#c.moves + 1] = square
            return c.moveResult or "MOVE_STARTED"
        end,
        cancelNpcMove = function() c.cancelled = true end,
    }
    c.bridge.moveNpcWithPace = c.bridge.moveNpc
    for _, name in ipairs({ "checkSharedMeal", "observeGroupEntry", "recoverIdleAnimationLatch",
        "recoverFromDetached", "isSettlementSupplyEntry", "tryAutomaticPlayerAid", "yieldBaseTaskForNeed",
        "yieldInventoryCleanupForNeed", "yieldAidForNeed", "yieldCollectionForNeed",
        "waitingForTransferActions", "sharedMealPostureReady", "prepareRouteWindowGlass",
        "applyGroupLeaderOrder", "releaseSupply", "releaseBaseTaskSupplyTransfer" }) do
        c[name] = function() return false end
    end
    c.applyPendingCombatPolicy = function() return true end
    c.recordFailure = function(self, reason) self.failure = reason end
    c.finishDecision = function(self)
        self.state, self.baseTaskCornerMove, self.finished = "IDLE", nil, true
    end
    c.finishBaseTask = function(self, success, reason)
        self.jobResult = {success = success, reason = reason}
        self:clearBaseTaskRuntimeState()
    end
    c.failBaseTaskAction = function(self, ticks, reason)
        self:finishBaseTask(false, reason)
        self:finishDecision(ticks)
    end
    c.queueBaseTaskSupplyTransfer = function(self)
        self.transfers = (self.transfers or 0) + 1
        self.state = "BASE_TASK_SUPPLY_TRANSFER"
        return true
    end
    return c
end

for _, state in ipairs({ "BASE_TASK_MOVE", "BASE_TASK_SUPPLY_MOVE" }) do
    local c = controller(state)
    local task = c.baseTask
    local transfer = { approach = goal }
    if state == "BASE_TASK_SUPPLY_MOVE" then c.baseTaskSupplyTransfer = transfer end
    c:tick(100)
    assert(#c.moves == 1 and c.moves[1] == squares["11,10"],
        "a job takes a reachable corner sidestep (" .. state .. ")")
    assert(c.baseTask == task and c.baseTaskCornerMove ~= nil and c.jobResult == nil,
        "a sidestep retains the claimed job (" .. state .. ")")
    assert(c.state == state and c.baseTaskMoveRetryIssued == true,
        "job corner recovery consumes the existing bounded retry (" .. state .. ")")
    origin, c.movement = squares["11,10"], "Succeeded"
    c:tick(101)
    assert(#c.moves == 2 and c.moves[2] == goal and c.state == state,
        "waypoint arrival resumes the real job destination (" .. state .. ")")
    assert(c.baseTaskCornerMove == nil and c.baseTaskMoveRetryIssued == true and c.transfers == nil,
        "a waypoint neither credits work nor resets the retry budget (" .. state .. ")")
    if state == "BASE_TASK_SUPPLY_MOVE" then
        assert(c.baseTaskSupplyTransfer == transfer, "the exact pickup lease survives the detour")
        origin = goal
        c:tick(102)
        assert(c.transfers == 1 and c.state == "BASE_TASK_SUPPLY_TRANSFER",
            "only arrival at the actual supplies admits the pickup action")
    else
        c.movement = DIAGONAL
        c:tick(102)
        assert(#c.moves == 2 and c.jobResult ~= nil and c.jobResult.success == false,
            "a second blocked job route fails normally instead of looping sidesteps")
    end
end

-- A worker going to its work site gets the existing door owner too.
local doorJob = controller("BASE_TASK_MOVE")
local door = {
    IsOpen = function() return false end, isLocked = function() return false end,
    isLockedByKey = function() return false end, isBarricaded = function() return false end,
}
origin.getObjects = function() return {
    size = function() return 1 end, get = function() return door end,
} end
instanceof = function(object, kind) return object == door and kind == "IsoDoor" end
doorJob.bridge.openNpcDoor = function(_, _, target)
    assert(target == door, "the work route opens the actual nearby door")
    doorJob.opened = true
    return "OPENING_DOOR"
end
doorJob:tick(100)
assert(doorJob.opened == true and doorJob.jobResult == nil and doorJob.baseTask ~= nil
    and doorJob.baseTaskMoveRetryIssued == true and doorJob.finished == true,
    "work travel opens the nearby door and keeps its claimed job for normal revalidation")

local permission = controller("BASE_TASK_MOVE")
origin.getObjects = function() return {
    size = function() return 1 end, get = function() return door end,
} end
permission.allowDoorWindowOpening = false
permission.bridge.openNpcDoor = function() error("opening was not authorized") end
permission:tick(100)
assert(permission.baseTaskCornerMove ~= nil and permission.baseTask ~= nil,
    "corner recovery obeys closed-door permission while retaining safe movement")

for _, state in ipairs({ "GROUP_FOLLOW", "COMPANION_FOLLOW", "GROUP_REGROUP" }) do
    local c = controller(state)
    c.baseTask = nil
    c:tick(100)
    assert(#c.moves == 1 and c.formationDoorRetry.count == 1,
        "the real tick recovers a follower using its stored goal (" .. state .. ")")
    origin, c.movement = squares["11,10"], "Succeeded"
    c:tick(101)
    assert(#c.moves == 2 and c.moves[2] == goal and c.state == state,
        "a follow sidestep resumes its original destination (" .. state .. ")")
    assert(c.formationDoorRetry ~= nil and c.formationDoorRetry.count == 1,
        "waypoint success preserves the follower retry cap (" .. state .. ")")
    origin = goal
    c:tick(102)
    assert(c.formationDoorRetry == nil,
        "only final route success clears the follower retry cap (" .. state .. ")")
end

local repeated = controller("GROUP_FOLLOW")
repeated.baseTask = nil
for attempt = 1, 3 do
    repeated:handleFormationMovementFailure(DIAGONAL, 100 + attempt)
    repeated.movement = "Succeeded"
    repeated:tick(110 + attempt)
    assert(repeated.formationDoorRetry.count == attempt,
        "repeated waypoint successes never replenish the corner retry budget")
end
repeated:handleFormationMovementFailure(DIAGONAL, 120)
assert(repeated.state == "GROUP_WAIT" and #repeated.moves == 6 and repeated.cancelled,
    "three completed sidesteps still escalate when the original route stays blocked")

local cancelled = controller("BASE_TASK_MOVE")
cancelled:tick(100)
cancelled.baseTask.state = "cancelled"
cancelled.movement = "Succeeded"
cancelled:tick(101)
assert(#cancelled.moves == 1 and cancelled.baseTask == nil and cancelled.finished,
    "a cancelled job is never resumed after the sidestep")

local reassigned = controller("BASE_TASK_MOVE")
reassigned:tick(100)
local newTask = {id="new-job", type="repair", state="claimed", claimedBy=reassigned.id}
reassigned.baseTask, reassigned.movement = newTask, "Succeeded"
reassigned:tick(101)
assert(#reassigned.moves == 1 and reassigned.baseTask == newTask and reassigned.finished,
    "a replacement job cannot inherit arrival at a previous job's waypoint")

local changed = controller("BASE_TASK_SUPPLY_MOVE")
changed.baseTaskSupplyTransfer = { approach = goal }
changed:tick(100)
changed.baseTaskSupplyTransfer = { approach = goal }
changed.movement = "Succeeded"
changed:tick(101)
assert(#changed.moves == 1 and changed.transfers == nil and changed.jobResult.success == false,
    "a replaced pickup lease fails closed after the waypoint")

local unloaded = controller("BASE_TASK_SUPPLY_MOVE")
unloaded.baseTaskSupplyTransfer = { approach = goal }
unloaded:tick(100)
squares["12,12"], unloaded.movement = nil, "Succeeded"
unloaded:tick(101)
assert(#unloaded.moves == 1 and unloaded.transfers == nil and unloaded.jobResult.success == false,
    "an unloaded supply goal is not treated as remotely reached")

local dragging = controller("BASE_TASK_MOVE")
dragging.baseTask.type, dragging.baseTaskCorpsePhase = "haul_corpse", "drop"
assert(dragging:recoverBaseTaskObstacle(DIAGONAL, 100) == false and #dragging.moves == 0,
    "an attached corpse keeps its existing fail-closed recovery")
local climbing = controller("BASE_TASK_MOVE")
climbing.character.isClimbing = function() return true end
assert(climbing:recoverBaseTaskObstacle(DIAGONAL, 100) == false and #climbing.moves == 0,
    "native traversal never acquires a competing recovery route")
local refused = controller("BASE_TASK_MOVE")
refused.moveResult = "MOVE_FAILED"
assert(refused:recoverBaseTaskObstacle(DIAGONAL, 100) == false
    and refused.baseTaskCornerMove == nil and refused.baseTaskMoveRetryIssued == true,
    "native sidestep admission failure consumes its retry without inventing a waypoint")
local cooldown = controller("BASE_TASK_MOVE")
assert(cooldown:recoverBaseTaskObstacle("FailedObstacle:FAILED_EDGE_COOLDOWN", 100) == false
    and #cooldown.moves == 0, "a known cooling edge never triggers geometric recovery")

getCell, KnoxCompanionVehicles = savedCell, savedVehicles
instanceof = savedInstanceof
KnoxBaseJobs = savedJobs
print("Base corner movement PASS jobs=true waypoint=true pickup=true follow=true bounded=true stale=true traversal=true")
