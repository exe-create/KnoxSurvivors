-- A task pointer must not outlive the claim it was taken for. Two residents can
-- elect the same queued task, a work area can be reassigned, or the player can
-- move the claim; only the claimant may walk to the post or finish the work.
-- Losing the claim is not a failed action, so it records no failure and speaks
-- no refusal line.
local C = KnoxAutonomyController
-- Everything this fixture stubs is restored before it returns: the harness
-- shares one environment with every later fixture.
local savedGetBase = KnoxPersistence.getBase
local savedBoard = KnoxBaseTaskBoard

local function resident(id, task)
    local self = setmetatable({
        id = id,
        baseId = "b1",
        baseTask = task,
        state = "BASE_TASK_WORK",
        activeDecision = "base_task_guard",
        bridge = { cancelNpcMove = function() return "MOVE_CANCELLED" end },
    }, C)
    self.releaseBaseTaskSupplyTransfer = function(target) target.supplyReleased = true end
    self.diagTaskSnapshot = function() return {} end
    self.diag = function(target, category, event) target.diagEvents = (target.diagEvents or {}) end
    self.recordFailure = function(target, reason) target.failureReason = reason end
    return self
end

local task = { id = "task-1", baseId = "b1", type = "guard", state = "claimed", claimedBy = "ks-a" }

-- 1. The claim is ours: the pointer is live.
KnoxPersistence.getBase = function() return { tasks = { ["task-1"] = task } } end
assert(resident("ks-a", task):baseTaskStillOurs() == true, "own claim stays")

-- 2. Another resident claimed the same record: the pointer is stale.
local heldByOther = { id = "task-1", baseId = "b1", type = "guard", state = "claimed", claimedBy = "ks-b" }
KnoxPersistence.getBase = function() return { tasks = { ["task-1"] = heldByOther } } end
assert(resident("ks-a", task):baseTaskStillOurs() == false, "another resident's claim is stale")

-- 3. The base loaded but the task is gone: the work was cancelled.
KnoxPersistence.getBase = function() return { tasks = {} } end
assert(resident("ks-a", task):baseTaskStillOurs() == false, "removed task is stale")

-- 4. The owner cannot be read: trust the pointer rather than dropping work.
KnoxPersistence.getBase = function() return nil end
assert(resident("ks-a", task):baseTaskStillOurs() == true, "unreadable owner keeps the pointer")

-- 5. Finishing work we no longer hold drops the pointer instead of asking the
--    task board to finish it, and records no failure for the resident.
local finished = 0
KnoxBaseTaskBoard = { finish = function() finished = finished + 1; return nil, "not_claimed_by_survivor" end }
KnoxPersistence.getBase = function() return { tasks = { ["task-1"] = heldByOther } } end
local stale = resident("ks-a", { id = "task-1", baseId = "b1", type = "guard", state = "claimed", claimedBy = "ks-a" })
stale.releaseBaseCooking = function() end
assert(stale:finishBaseTask(true, "completed_guard") == false, "a lost claim does not finish")
assert(finished == 0, "the task board is never asked to finish a lost claim")
assert(stale.baseTask == nil, "the stale pointer is dropped")
assert(stale.state == "IDLE" and stale.activeDecision == nil, "the resident returns to decision")
assert(stale.failureReason == nil, "a lost claim is not the resident's failure")
assert(stale.supplyReleased == true, "the supply lease is released with the pointer")

-- 6. A claim we still hold goes through the board exactly once.
KnoxPersistence.getBase = function() return { tasks = { ["task-1"] = task } } end
local live = resident("ks-a", { id = "task-1", baseId = "b1", type = "guard", state = "claimed", claimedBy = "ks-a" })
live.releaseBaseCooking = function() end
local accepted = 0
KnoxBaseTaskBoard = { finish = function() accepted = accepted + 1; return { id = "task-1" }, "complete" end }
assert(live:finishBaseTask(true, "completed_guard") == true, "an owned claim finishes")
assert(accepted == 1, "the owned finish crosses the board once")

print("Stale base claim PASS owned=true moved=false cancelled=false unreadable=true no_failure=true board_once=true")
KnoxPersistence.getBase = savedGetBase
KnoxBaseTaskBoard = savedBoard
