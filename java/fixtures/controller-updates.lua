-- Exercise the controller entry points before and after their module extraction.
local C = assert(KnoxAutonomyController)
local events = {}
local c = setmetatable({ nextIdleLatchCheck = 0, pendingFleeAttack = {} }, C)
function c:recoverIdleAnimationLatch(ticks)
    events[#events + 1] = "latch:" .. ticks
end
function c:applyPendingCombatPolicy()
    events[#events + 1] = "policy"
    return false
end

c:tick(100)
assert(c.currentTicks == 100 and c.nextIdleLatchCheck == 115,
    "tick retains the controller clock and fifteen-tick latch cadence")
assert(c.pendingFleeAttack == nil, "a detached stale retreat is cleared before policy arbitration")
assert(table.concat(events, ",") == "latch:100,policy",
    "latch recovery precedes policy arbitration")
c:tick(114)
assert(#events == 3 and events[3] == "policy", "the latch is not probed early")
c:tick(115)
assert(events[4] == "latch:115" and events[5] == "policy",
    "the latch is probed at the exact cadence boundary")

local observations = 0
c.character = { isClimbing = function() return true end }
c.bridge = { observeNpcNativeAction = function(_, id)
    assert(id == "update-fixture", "native observation keeps survivor ownership")
    observations = observations + 1
end }
c.id = "update-fixture"
c:tick(116)
assert(observations == 1, "native traversal is observed even while combat policy blocks the tick")

local task = setmetatable({ state = "IDLE" }, C)
assert(task:updateBaseTaskAction(200) == false, "another state does not consume a base-task update")
task.state = "BASE_TASK_ACTION"
function task:finishBaseTask(success, reason)
    assert(success == false and reason == "unsupported_base_action",
        "a missing or unsupported task retains its failure verdict")
    events[#events + 1] = "task-failed"
end
function task:finishDecision(ticks)
    assert(ticks == 200, "the decision receives the same update clock")
    events[#events + 1] = "decision-finished"
end
assert(task:updateBaseTaskAction(200) == true, "a rejected task consumes its update")
assert(events[#events - 1] == "task-failed" and events[#events] == "decision-finished",
    "task failure is recorded before finishing the decision")
task.baseTask = { type = "unsupported-fixture" }
assert(task:updateBaseTaskAction(200) == true, "an unknown task uses the same rejection path")

local oldNeeds, oldCell = KnoxSurvivorNeeds, getCell
getCell = function() return nil end
KnoxSurvivorNeeds = { decide = function() return { kind = "fight", target = "fixture-target" } end }
local thinker = setmetatable({ nextThink = 0, nextThreatScan = 0,
    character = { getCurrentSquare = function() return nil end } }, C)
function thinker:allowsCompanionThreat() return true end
function thinker:beginCombat(target)
    assert(target == "fixture-target", "decision selection retains the real needs target")
    return false
end
thinker:think(300)
assert(thinker.nextThink == 330 and thinker.nextThreatScan == 315,
    "a rejected combat decision retains both retry intervals")
KnoxSurvivorNeeds, getCell = oldNeeds, oldCell

print("Controller updates PASS tick_order=true cadence=true traversal=true task_verdict=true decision_retry=true")
