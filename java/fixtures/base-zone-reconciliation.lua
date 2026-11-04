local jobs=codecZoneJobs
local previousPersistence,previousAge=KnoxPersistence,worldAge
local cancelled,requeued=0,0
KnoxPersistence={
    baseTaskTargetSignature=function(target)
        return "x="..tostring(target.x1)..";y="..tostring(target.y1)
            ..";x2="..tostring(target.x2)..";y2="..tostring(target.y2)
            ..";z="..tostring(target.z)
    end,
    cancelBaseTask=function(_,taskId,now)
        cancelled=cancelled+1
        local task=fixtureTasks[taskId]
        task.state="cancelled"
        task.result="cancelled_by_player"
        task.completedAtHours=now
        return task,"cancelled"
    end,
    requeueBaseTask=function(_,taskId,now)
        requeued=requeued+1
        local task=fixtureTasks[taskId]
        task.state="queued"
        task.retryAtHours=nil
        task.requeuedAtHours=now
        return task,"requeued"
    end,
}
worldAge=function() return 42 end
fixtureTasks={}
local function signature(zoneType,x,y1,x2,y2,z)
    return zoneType..":x="..tostring(x)..";y="..tostring(y1)
        ..";x2="..tostring(x2)..";y2="..tostring(y2)..";z="..tostring(z)
end
local function task(id,state,x)
    local value={id=id,baseId="home",type="farm_seed",state=state,priority=50,
        signature=signature("farm_seed",x,10,x+3,13,0),
        target={auto=true,autoZoneId="zone-1",zoneType="farm_seed",
            x1=x,y1=10,x2=x+3,y2=13,z=0}}
    fixtureTasks[id]=value
    return value
end
local moved=task("moved","queued",10)
local zone={id="zone-1",type="farm_seed",x1=30,y1=40,x2=35,y2=45,z=1,priority=72}
assert(jobs.reconcileAutomaticZoneTask(moved,zone,42)=="moved")
assert(moved.target.x1==30 and moved.target.y2==45 and moved.target.z==1
    and moved.priority==72,"queued work follows the edited work area and priority")
assert(moved.signature==signature("farm_seed",30,40,35,45,1),
    "queued work keeps its durable signature aligned with the edited area")

local blocked=task("blocked","blocked",10)
blocked.retryAtHours=80
assert(jobs.reconcileAutomaticZoneTask(blocked,zone,42)=="moved_and_requeued")
assert(blocked.state=="queued" and blocked.retryAtHours==nil and requeued==1,
    "moving a blocked work area retries at its new valid destination")

local claimed=task("claimed","claimed",10)
claimed.claimedBy="resident"
assert(jobs.reconcileAutomaticZoneTask(claimed,zone,42)=="in_progress")
assert(claimed.target.x1==10,"an active executor keeps its admitted target")

local changedType=task("changed-type","queued",10)
changedType.basePriority=12
local watch={id="zone-1",type="guard",x1=10,y1=10,x2=13,y2=13,z=0,priority=80}
assert(jobs.reconcileAutomaticZoneTask(changedType,watch,42)=="moved")
assert(changedType.type=="guard" and changedType.target.zoneType=="guard"
    and changedType.basePriority==80,"executor type and shortage priority follow edited zone")
assert(changedType.signature==signature("guard",10,10,13,13,0),
    "retyped work also updates the durable job signature")

-- A work area retyped to a discovery label (farming, woodcutting, cooking,
-- corpse and similar) has no recurring task of its own. The old assignment is
-- retired so that zone's finder can emit concrete finite jobs instead of
-- leaving a resident on a type no executor serves.
local retyped=task("retyped","queued",10)
local garden={id="zone-1",type="farming",x1=20,y1=20,x2=24,y2=24,z=0,priority=60}
assert(jobs.reconcileAutomaticZoneTask(retyped,garden,42)=="zone_type_retired")
assert(retyped.state=="cancelled" and retyped.type=="farm_seed"
    and retyped.target.x1==10,"retyped discovery area retires its old recurring job")
assert(cancelled==1,"retiring a retyped recurring job uses the normal cancel path")

local retypedClaimed=task("retyped-claimed","claimed",10)
retypedClaimed.claimedBy="resident"
assert(jobs.reconcileAutomaticZoneTask(retypedClaimed,garden,42)=="in_progress")
assert(retypedClaimed.state=="claimed" and retypedClaimed.type=="farm_seed"
    and retypedClaimed.target.x1==10,
    "an executor keeps its admitted work through a zone type edit")
assert(cancelled==1,"an active job is never cancelled by a zone type edit")

local stopped=task("stopped","cancelled",10)
assert(jobs.reconcileAutomaticZoneTask(stopped,watch,42)=="already_cancelled")
assert(stopped.type=="farm_seed" and stopped.target.x1==10,
    "zone edits preserve explicitly cancelled work")

local stoppedRetyped=task("stopped-retyped","cancelled",10)
assert(jobs.reconcileAutomaticZoneTask(stoppedRetyped,garden,42)=="already_cancelled")
assert(stoppedRetyped.type=="farm_seed" and stoppedRetyped.target.x1==10,
    "cancelled work stays retired even when its area changes type")
assert(cancelled==1,"a cancelled job is not cancelled twice")

local removed=task("removed","queued",10)
assert(jobs.reconcileAutomaticZoneTask(removed,nil,42)=="zone_removed")
assert(removed.state=="cancelled" and cancelled==2,
    "queued work is retired when its assigned zone is removed")

KnoxPersistence,worldAge=previousPersistence,previousAge
print("Base zone reconciliation PASS moved=true blocked_requeued=true active_target_preserved=true retyped_retired=true removed_cancelled=true")
