local C = KnoxAutonomyController
local previousSpecificPlayer = getSpecificPlayer
getSpecificPlayer = function() return nil end
assert(not C.retreatAdmission(6,true,false,false,true,0,8,1,30,"fit"),
    "a distant pursuing crowd alone must not force a healthy fighter to flee")
assert(not C.retreatAdmission(6,true,false,false,true,1,5,1,20,"fit"))
assert(C.retreatAdmission(2,true,false,false,true,3,6,1,20,"surrounded"))
assert(C.retreatAdmission(6,true,true,true,false,0,1,1,3,"critical"))
assert(C.retreatAdmission(6,true,false,true,false,0,2,1,12,"injured"))
assert(not C.retreatAdmission(0,true,true,true,true,4,9,1,30,"blocked"),
    "no legal escape lane must not admit an impossible route")
local fit = {health=95,endurance=.8,bleeding=0,severe=0,close=4,targeting=4,
    nearestDistanceSquared=20}
local recovering = setmetatable({}, C)
assert(not recovering:retreatIsSafelyClear(false,fit,1))
assert(recovering:retreatIsSafelyClear(false,fit,2),
    "fit survivor can resume combat after two safe separation scans despite pursuit")
recovering.state="FLEEING"
recovering.beginFlee=function() error("safe separation must not restart an endless retreat") end
assert(not recovering:retryRetreatForDanger(2,false,fit),
    "route retry cannot preempt safe-scan reengagement")
fit.nearestDistanceSquared=2
assert(not recovering:retreatIsSafelyClear(false,fit,3), "contact still prevents premature return")

local priorCapture = KnoxPersistence.captureActiveSurvivor
local captures = 0
KnoxPersistence.captureActiveSurvivor = function() captures=captures+1; return true end
local checkpoint = setmetatable({id="checkpoint-test"},C)
for tick=0,299 do checkpoint:captureDecisionCheckpoint(tick) end
assert(captures==1,"300 routine decisions must not serialize 300 inventories")
assert(checkpoint:captureDecisionCheckpoint(300) and captures==2)
KnoxPersistence.captureActiveSurvivor = priorCapture

local body = journeyBody
local previousVisible = body.visible
body.visible = true
local player = setmetatable({x=body.x+1,y=body.y,z=body.z,state="idle"},{__index=body})
local task = {type="guard",state="claimed",claimedBy="guard-interaction"}
local pauses = 0
local guard = setmetatable({id="guard-interaction",character=body,state="BASE_TASK_WORK",
    currentTicks=20,nextThreatScan=0,baseTask=task,groupMembers={},failedThreats={},
    reservations={items={},threats={},restSpots={}},bridge={cancelNpcMove=function() end},
    suspendBaseTaskForThreat=function(self) pauses=pauses+1;self.securityRoute=nil;return true end,
    releaseBaseRecreation=function() end,releaseBaseHygiene=function() end,
    releaseBaseOrganize=function() end,releaseWatch=function() end,releaseLights=function() end,
    releaseSupply=function() end,leaveRecoveryPosture=function() end,
    tradeNeedsSelfCare=function() return false end},C)
assert(guard:beginPlayerConversation(player),"claimed guard can speak without abandoning duty")
assert(guard.state=="PLAYER_CONVERSATION" and guard.baseTask==task and task.state=="claimed")
assert(guard:beginPlayerConversation(player),"same attention lease remains usable")
local offer={npc=body,giving={},taking={},browsing=true}
assert(guard:beginTrade(offer),"guard conversation can enter ordinary trade")
assert(guard.state=="TRADING" and guard.baseTask==task and guard.playerConversation==nil)
assert(guard:releaseTrade(offer) and guard.state=="IDLE" and guard.baseTask==task and pauses==2)
task.type="repair";guard.state="BASE_TASK_WORK"
assert(guard:canPauseWorkForInteraction(),"finite work must allow player interaction too")
body.visible = previousVisible

local previousJobs, previousRequeue = KnoxBaseJobs, KnoxPersistence.requeueAutomaticBaseTasksForSurvivor
local previousDecide = KnoxSurvivorNeeds.decide
local requeued, interrupted = 0,0
KnoxBaseJobs={scheduleAssignment=function() return "sleep" end}
KnoxPersistence.requeueAutomaticBaseTasksForSurvivor=function(id,baseId)
    assert(id=="watcher" and baseId=="test-base");requeued=requeued+1
end
local watcher=setmetatable({id="watcher",baseId="test-base",state="BASE_TASK_WORK",
    baseTask={type="guard",state="claimed",claimedBy="watcher",target={}},
    interruptForDirective=function(self) interrupted=interrupted+1;self.state="IDLE" end},C)
watcher:updateBaseSecurityDuty(100)
assert(requeued==1 and interrupted==1 and watcher.state=="IDLE",
    "an indefinite automatic guard duty releases its claim when sleep starts")
watcher.baseTask.manual=true;watcher.nextSecurityCheck=0
KnoxSurvivorNeeds.decide=function() return {kind="roam"} end
watcher.state="BASE_SECURITY_WAIT"
watcher:updateBaseSecurityDuty(200)
assert(requeued==1,"manual watch assignment survives schedule changes")
KnoxBaseJobs,KnoxPersistence.requeueAutomaticBaseTasksForSurvivor=previousJobs,previousRequeue

-- Forced entry must name the door the survivor is beside. The old bridge read
-- only the last movement edge's traversal target, already cleared after a
-- window detour, and failed with NO_LOCKED_DOOR_TARGET.
local priorCell, priorInstanceof = getCell, instanceof
local priorManager = KnoxBaseManager
local priorEntryNeeds = KnoxSurvivorNeeds
local function doorObject(locked, open, barricaded)
    return { isDoor = true,
        IsOpen = function() return open == true end,
        isLocked = function() return locked == true end,
        isLockedByKey = function() return false end,
        isBarricaded = function() return barricaded == true end }
end
local lockedDoor = doorObject(true, false, false)
local openDoor = doorObject(false, true, false)
local barricadedDoor = doorObject(true, false, true)
local origin = { getX = function() return 10 end, getY = function() return 10 end,
    getZ = function() return 0 end, getRoom = function() return nil end,
    getObjects = function() return { size = function() return 0 end,
        get = function() end } end }
local function entrySquare(x, y, objects)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, getRoom = function() return nil end,
        getObjects = function() return { size = function() return #objects end,
            get = function(_, index) return objects[index + 1] end } end }
end
local entrySquares = {
    ["10,10"] = origin,
    ["11,10"] = entrySquare(11, 10, { lockedDoor }),
    ["9,10"] = entrySquare(9, 10, { openDoor }),
    ["10,11"] = entrySquare(10, 11, { barricadedDoor }),
}
getCell = function() return { getGridSquare = function(_, x, y)
    return entrySquares[x .. "," .. y] end } end
instanceof = function(object, class)
    return class == "IsoDoor" and object.isDoor == true
end
KnoxBaseManager = { canDamageStructure = function() return true end }
KnoxSurvivorNeeds = setmetatable({ snapshot = function() return { endurance = 1 } end },
    { __index = priorEntryNeeds })
local entryBody = { getCurrentSquare = function() return origin end,
    getPrimaryHandItem = function() return { IsWeapon = function() return true end,
        isRanged = function() return false end, isBroken = function() return false end } end }
local finder = setmetatable({ character = entryBody }, C)
assert(C.findForcedEntryDoor(finder, nil) == nil,
    "an incidental adjacent door is not proof of the target edge")
local rivalDoor = doorObject(true, false, false)
assert(C.findForcedEntryDoor(finder, rivalDoor) == rivalDoor,
    "an explicitly known door wins over the neighbourhood scan")
assert(C.findForcedEntryDoor(finder, openDoor) == nil,
    "an open preferred object cannot substitute an incidental door")

local targetSquare = entrySquare(11, 10, {})
local breaks, blockedReason = 0, nil
local breaker = setmetatable({
    id = "door-breaker", character = entryBody, activeDecision = "base_task_move",
    entryDetour = {object=lockedDoor},
    blockedAreas = {},
    pendingSupply = {
        container = { getSourceGrid = function() return targetSquare end },
        targetSquare = targetSquare, entryAttempts = {}, entryAttemptCount = 0,
    },
    bridge = { beginNpcLockedDoorCombatAt = function(_, id, chosen)
        breaks = breaks + 1
        assert(id == "door-breaker" and chosen == lockedDoor,
            "the native boundary receives the resolved door")
        return "COMBAT_STARTED mode=locked-door"
    end },
}, C)
assert(breaker:beginLockedDoorBreak(10, "BASE_TASK_SUPPLY_MOVE", true),
    "forced entry starts against the adjacent door")
assert(breaks == 1 and breaker.state == "BREAKING_LOCKED_DOOR")

entrySquares["11,10"] = entrySquare(11, 10, {})
entrySquares["10,11"] = entrySquare(10, 11, {})
local noDoor = setmetatable({
    id = "no-door", character = entryBody, activeDecision = "base_task_move",
    blockedAreas = {},
    pendingSupply = {
        container = { getSourceGrid = function() return targetSquare end },
        targetSquare = targetSquare, entryAttempts = {}, entryAttemptCount = 0,
    },
    bridge = { beginNpcLockedDoorCombatAt = function()
        error("forced entry must not call the native boundary without a door")
    end },
}, C)
assert(not noDoor:beginLockedDoorBreak(20, "BASE_TASK_SUPPLY_MOVE", true),
    "no adjacent door fails locally instead of at the native boundary")
assert(noDoor.blockedAreas[targetSquare] ~= nil,
    "a missing door is recorded as a real blocked entry")
getCell, instanceof = priorCell, priorInstanceof
KnoxBaseManager = priorManager
KnoxSurvivorNeeds = priorEntryNeeds

KnoxSurvivorNeeds.decide=previousDecide
getSpecificPlayer=previousSpecificPlayer
print("Playtest core PASS tactical_retreat=true recovery=true capture_budget=true forced_entry=true guard_talk_trade=true schedule_handoff=true")
