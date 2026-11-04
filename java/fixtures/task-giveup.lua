-- A work order that fails three times is an obstacle, not bad timing. The board
-- must stop promising it, keep the record as the signature the planner may not
-- recreate, and never cancel an order the player gave in person. It must also
-- say what stopped the work in words, and familiarity must stop paying trust
-- once the pair is merely familiar.
local P = KnoxPersistence
local C = assert(KnoxAutonomyController, "the controller must be loaded")
-- These ids belong to this fixture alone: the harness shares one environment,
-- and a survivor id reused by another fixture already carries its faction.
local SID, PID = "giveup-survivor", "giveup-player"
local savedGetBase = P.getBase

-- 1. Automatic work gives up on the third failure and keeps its reason.
local task = { id = "t1", baseId = "b1", type = "chop_tree", state = "claimed", claimedBy = SID }
local base = { id = "b1", tasks = { t1 = task } }
P.getBase = function() return base end

for attempt = 1, 2 do
    task.state, task.claimedBy = "claimed", SID
    local _, result = P.finishBaseTask("b1", "t1", SID, false,
        "task_move_start_failed:MOVE_BLOCKED", attempt)
    assert(result == "finished", "attempt " .. attempt .. " still retries, got " .. tostring(result))
    assert(task.state == "blocked", "attempt " .. attempt .. " is blocked, not cancelled")
    assert((tonumber(task.retryAtHours) or 0) > attempt, "a blocked task keeps a retry hour")
end

task.state, task.claimedBy = "claimed", SID
local _, result = P.finishBaseTask("b1", "t1", SID, false,
    "task_move_start_failed:MOVE_BLOCKED", 3)
assert(result == "gave_up", "the third failure gives up, got " .. tostring(result))
assert(task.state == "cancelled", "giving up cancels the record, got " .. tostring(task.state))
assert(task.retryAtHours == nil, "a cancelled task is not retried")
assert(task.result == "task_move_start_failed:MOVE_BLOCKED", "the reason is kept for the player")
assert(task.cancelledAtHours == 3, "the cancellation is stamped with the world age")

-- 2. A player's own order is not cancelled behind their back.
local manual = { id = "t2", baseId = "b1", type = "chop_tree", state = "claimed",
    claimedBy = SID, manualOrder = true }
base.tasks = { t2 = manual }
for attempt = 1, 4 do
    manual.state, manual.claimedBy = "claimed", SID
    P.finishBaseTask("b1", "t2", SID, false, "interrupted", attempt)
end
assert(manual.state == "blocked", "a manual order keeps waiting, got " .. tostring(manual.state))

-- 3. The player is told what stopped it, not a machine token.
assert(C.taskStopText("no_loaded_work_square:unresolved") == "the site was out of sight",
    "an unloaded site is explained")
assert(C.taskStopText("task_move_start_failed:MOVE_BLOCKED") == "they could not find a way there",
    "a failed walk is explained")
assert(C.taskStopText("something_new:1") == "it could not be finished",
    "an unknown reason never leaks a token")

-- 4. Familiarity has a ceiling: standing nearby cannot carry trust to 100.
P.getBase = savedGetBase
if P.ensureSurvivorIdentity ~= nil then
    pcall(P.ensureSurvivorIdentity, SID, "Nora", "Vance", 10, 34)
end
local relation = assert(P.getPlayerRelationship(PID, SID), "a relationship exists")
assert((tonumber(relation.trust) or 0) == 30, "a new relationship starts at 30")
local ceilingHitAt = nil
for hour = 1, 40 do
    local _, why = P.recordPlayerProximity(PID, SID, hour)
    if why == "ceiling" and ceilingHitAt == nil then ceilingHitAt = hour end
end
local trust = tonumber(relation.trust) or 0
assert(trust == 45, "familiarity stops at 45, got " .. tostring(trust))
assert(ceilingHitAt ~= nil, "the ceiling is reported as its own result")
assert((tonumber(relation.nearbyHours) or 0) > 0, "time nearby is still remembered")

-- 5. A spoken act writes through the shared ledger and never invents a faction.
assert(P.ensurePlayerFaction(PID, 40) ~= nil, "the player has a group to hold standing")
local acted, why = P.recordPlayerSocialAct(PID, SID, "insult", -12, 1, 50)
assert(acted ~= nil, "a social act is recorded: " .. tostring(why))
assert(tonumber(relation.trust) == 33, "the insult cost real trust, got " .. tostring(relation.trust))
local faction, factionWhy = P.recordSocialReputation(PID, SID, "insult", 51)
assert(faction == nil and factionWhy == "no_faction",
    "no faction means no invented standing change: " .. tostring(factionWhy))
assert(P.recordSocialReputation(PID, SID, "nonsense", 51) == nil,
    "an unknown act has no standing")

-- 6. A reason that cannot fix itself stops the work at once instead of three
-- trips up the backoff ladder, and the resident says why out loud.
local stuck = { id = "t3", baseId = "b1", type = "barricade", state = "claimed", claimedBy = SID }
base.tasks = { t3 = stuck }
P.getBase = function() return base end
local _, stopped = P.finishBaseTask("b1", "t3", SID, false,
    "stay_home_missing_supplies:missing_assigned_item=Base.Plank", 10)
assert(stopped == "gave_up",
    "a missing material stops the work at once, got " .. tostring(stopped))
assert(stuck.state == "cancelled", "the stuck order is cancelled on the first try")
assert(C.taskStopText("missing_assigned_item=Base.Plank") == "the base was out of the material",
    "an item reason is explained without the item id")
assert(C.taskStopText("barricade_no_progress") == "the window would not take another board",
    "a window that takes no board is explained")
assert(C.stopSpokenText("missing_assigned_item=Base.Plank"):find("missing the materials", 1, true) ~= nil,
    "the resident says the material is missing")
assert(C.stopSpokenText("barricade_no_progress"):find("won't take another board", 1, true) ~= nil,
    "the resident says the window will not take a board")
P.getBase = savedGetBase

print("Task giveup PASS cancelsAt=3 manualKept=true reasonKept=true words=true ceiling=45 actLedger=true")
