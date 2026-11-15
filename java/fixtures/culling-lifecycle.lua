local policy=assert(KnoxSurvivorLifecyclePolicy)
local ticks,syncs=0,0
local pending={person=true}
local tickOwner=activeControllerTickFactory({"person"},{person={state="IDLE",tick=function() ticks=ticks+1 end}},
 pending,{syncController=function() syncs=syncs+1 end})
tickOwner()
assert(ticks==0 and syncs==0,"incomplete ownership rollback cannot also tick the loaded controller")
pending.person=nil;tickOwner()
assert(ticks==1 and syncs==1,"confirmed loaded ownership resumes normal controller projection and tick")
assert(policy.distanceEligible(true,"base",101,100,false),"persistent resident is distance eligible")
assert(not policy.distanceEligible(true,"base",100,100,false),"distance boundary stays loaded")
assert(not policy.distanceEligible(true,"companion",1000,100,false),"companions keep their live follow owner")
assert(not policy.distanceEligible(true,"autonomous",1000,100,true),"visible survivor is not culled")
assert(not policy.distanceEligible(false,"autonomous",1000,100,false),"unknown identity cannot be culled")
local function scene(count)
 local b={ids={},controllers={},bodies={},records={},states={},removed=0,attempts=0,unregistered=0}
 local function square(x) return {x=x,getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end} end
 for i=1,count do
  local id="manual-"..i;local sq=square(1000+i)
  local body={getCurrentSquare=function() return sq end,getVehicle=function() return nil end,
   getCurrentStateName=function() return "IdleState" end}
  local c={character=body,state="ROAMING"}
  function c:canHibernateForDistance() return not self.busy end
  function c:shutdown(preserveWork)
   assert(preserveWork==true,"hibernation preserves durable work instead of failing it")
   b.attempts=b.attempts+1
   if self.failCapture then return false,"capture_failed" end
   b.records[id]="captured:"..id;return true,"captured"
  end
  function c:resumeAfterHibernateRollback() self.resumed=true;return true,"resumed" end
  b.ids[i]=id;b.controllers[id]=c;b.bodies[id]=body
 end
 b.bridge={getNpcCharacter=function(_,id) return b.bodies[id] end,
  removeNpc=function(_,id)
   assert(b.records[id] and b.states[id]=="hibernated","capture and stored ownership precede removal")
   b.removed=b.removed+1
   if not b.failRemove then b.bodies[id]=nil end
   return b.failRemove and "FAILED" or "REMOVED"
  end}
 b.persistence={getSurvivorDuty=function(id) return {mode=b.companion==id and "companion" or "autonomous"} end,
  isSurvivorPresent=function() return true end}
 b.world={nearestPlayerDistanceSquared=function(sq) return sq.x^2 end,
  squareVisibleToPlayers=function(sq) return b.visible==sq.x end}
 b.runtime={setLifecycleState=function() end,unregister=function() b.unregistered=b.unregistered+1 end}
 b.unloaded={markStored=function(id)
  if b.failMark then return false,"mark_failed" end;b.states[id]="hibernated";return true,"stored" end,
  rollbackStored=function(id) b.states[id]="loaded";return true,"loaded" end}
 b.run=cullingFactory(b,policy)
 return b
end
local b=scene(5)
b.visible=1004;b.companion="manual-5"
b.run(100)
assert(b.removed==2 and #b.ids==3 and b.unregistered==2,
 "one culling pass retires at most two saved non-world bodies")
b.run(130)
assert(b.removed==3 and #b.ids==2 and b.bodies["manual-4"] and b.bodies["manual-5"],
 "later pass drains remaining eligible bodies while preserving visible and companion bodies")
b=scene(1);b.controllers["manual-1"].failCapture=true;b.run(100)
assert(b.removed==0 and b.bodies["manual-1"] and b.controllers["manual-1"].resumed,
 "capture failure leaves the same native person alive and resumes arbitration")
b.run(130)
assert(b.attempts==1,"failed capture has a retry backoff")
b=scene(1);b.failMark=true;b.run(100)
assert(b.removed==0 and b.bodies["manual-1"],"stored-ledger failure cannot remove the body")
b.failMark=false;b.run(130)
assert(b.states["manual-1"]=="loaded" and b.controllers["manual-1"].resumed,
 "failed handoff rolls ownership back to the same live controller")
b=scene(1);b.failRemove=true;b.run(100)
assert(b.states["manual-1"]=="loaded" and b.controllers["manual-1"].resumed
 and b.bodies["manual-1"] and b.unregistered==0,"failed native removal cannot create a second person")
-- Exercise the real controller shutdown and suspension branch. Native cleanup
-- operations and the separately verified persistence boundary are doubled here.
local C=assert(KnoxAutonomyController)
local c={id="claim-owner",state="BASE_TASK_MOVE",baseTask={state="claimed",claimedBy="claim-owner"},
 bridge={cancelNpcMove=function() end,resetNpcCombat=function() end},
 waitingForTransferActions=function() return false end}
for _,name in ipairs({"releaseSupplyCollection","releaseSharedMeal","releaseSelfCare","releaseWatch","releaseLights","cancelTrade",
 "releaseBaseHygiene","releaseBaseOrganize","releaseRestSpot","releaseAmbientMovement","releaseGroupSupport",
 "releaseAid","releaseBaseCooking","releaseBaseTaskSupplyTransfer","releaseSupply","releaseCampPosition",
 "releaseInventoryCleanup","releaseRoleKit","releaseCombat","clearFirearmCombatState","releasePlayerFormationTarget",
 "releasePartyDestinationTarget","releaseAllTransientReservations"}) do c[name]=function() end end
c.mealReleases=0
c.releaseSharedMeal=function(self) self.mealReleases=self.mealReleases+1 end
c.suspendBaseTaskForThreat=C.suspendBaseTaskForThreat
c.abandonBaseTask=function() error("hibernation must not fail the job") end
local oldCapture=KnoxPersistence.captureActiveSurvivor
KnoxPersistence.captureActiveSurvivor=function(id) assert(id=="claim-owner");return true,"captured" end
local saved=C.shutdown(c,true)
KnoxPersistence.captureActiveSurvivor=oldCapture
assert(saved and c.mealReleases==1 and c.baseTask.state=="claimed" and c.baseTask.claimedBy=="claim-owner"
 and c.baseTask.interruptedReason=="hibernate","actual shutdown keeps the job claim and requests suspension")
print("Culling lifecycle PASS budget=2 manual_bodies=true visibility=true transactional_failures=true")
