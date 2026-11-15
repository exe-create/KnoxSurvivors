local N, M, S, C = KnoxSurvivorNeeds, KnoxMedicalActions, KnoxMedicalSupplies, KnoxAutonomyController
local oldQueue, oldNew, oldStats, oldCell = ISTimedActionQueue, ISApplyBandage.new, CharacterStat, getCell
local oldVehicles = KnoxCompanionVehicles
CharacterStat = { HUNGER="hunger", THIRST="thirst", FATIGUE="fatigue", ENDURANCE="endurance" }
getCell = function() return nil end
KnoxCompanionVehicles = nil
local part = { injured = true, covered = false, bleedingNow = true, alcohol = 4, life = 5 }
function part:HasInjury() return self.injured end
function part:bandaged() return self.covered end
function part:bleeding() return self.bleedingNow end
function part:bitten() return false end
function part:isInfectedWound() return false end
function part:getAlcoholLevel() return self.alcohol end
function part:getBandageLife() return self.life end
local second = { injured = false, covered = false }
function second:HasInjury() return self.injured end
function second:bandaged() return self.covered end
function second:bleeding() return false end
function second:bitten() return false end
function second:isInfectedWound() return false end
function second:getAlcoholLevel() return 4 end
function second:getBandageLife() return 5 end
local parts = {size=function() return 2 end, get=function(_, i) return i == 0 and part or second end}
local contents = {}
local list = {size=function() return #contents end, get=function(_, i) return contents[i+1] end}
local inv = {getItems=function() return list end, contains=function(_, x)
    for _, item in ipairs(contents) do if item == x then return true end end return false end}
local dressing = {isCanBandage=function() return true end, getType=function() return "Bandage" end,
 isAlcoholic=function() return false end, getBandagePower=function() return 1 end,
 IsInventoryContainer=function() return false end, isFavorite=function() return false end,
 isBroken=function() return false end, isInfected=function() return false end,
 getContainer=function() return inv end, getFullType=function() return "Base.Bandage" end}
local square = {}
local body = {getBodyParts=function() return parts end, getHealth=function() return 100 end,
 getNumPartsBleeding=function() return part.bleedingNow and not part.covered and 1 or 0 end}
local actor = {getBodyDamage=function() return body end, getInventory=function() return inv end,
 getStats=function() return {get=function(_, key) return key == "endurance" and 1 or 0 end} end,
 isEquipped=function() return false end, getReduceInfectionPower=function() return 0 end,
 getCurrentSquare=function() return square end, getCharacterActions=function() return nil end,
 getWornItems=function() return {contains=function() return false end} end,
 getPrimaryHandItem=function() return nil end, getSecondaryHandItem=function() return nil end}
local queue = {queue={}}
ISTimedActionQueue = {queues={[actor]=queue}, add=function(action) queue.queue={action}; return queue end}
ISApplyBandage.new = function(_, character, patient, item, wound, applying)
 return {character=character, otherPlayer=patient, item=item, bodyPart=wound, doIt=applying,
  isValid=function() return true end, complete=function()
   if applying then contents={}; wound.covered=true; wound.bleedingNow=false
   else wound.covered=false end
   return true
  end}
end
local allowed = {allowed=function() return true end}
contents={dressing}
assert(S.plan(actor,8).kind == "use_treatment", "real supply plan selects carried dressing")
assert(M.mostUrgentInjury(actor) == part, "real injury triage selects the bleeding wound")
local choice=N.decide(actor,nil)
assert(choice.kind=="bandage" and choice.item==dressing and choice.bodyPart==part, "real need selects treatment")
local action,_,intent=N.execute(actor,choice,allowed)
assert(action and action:complete() and N.verify(actor,intent) and part.covered, "native-bound treatment yields receipt")
queue.queue={}
assert(N.decide(actor,nil).kind=="roam", "covered injured part is not removed")
part.injured=false
choice=N.decide(actor,nil)
assert(choice.kind=="remove_healed_bandage", "healing selects removal")
action,_,intent=N.execute(actor,choice,allowed)
assert(action and action:isValid(), "healed removal admitted")
part.injured=true
assert(not action:isValid() and not action:complete() and part.covered, "new injury revokes removal")
part.injured=false
queue.queue={}
action,_,intent=N.execute(actor,N.decide(actor,nil),allowed)
assert(action:complete() and N.verify(actor,intent) and not part.covered, "confirmed removal completes")
assert(not action:complete(), "completed action cannot be duplicated")
second.injured=true
contents={dressing}
assert(N.decide(actor,nil).kind=="bandage", "next wound is treated after removal")
second.injured=false
part.injured=true; part.bleedingNow=true; contents={}
assert(N.decide(actor,nil).kind=="find_medical", "missing supplies yields a search, not invented care")
part.injured=false; part.bleedingNow=false; part.covered=true
queue.queue={}
local c=setmetatable({id="care",character=actor,state="COMPANION_WAIT",observedState="COMPANION_WAIT",
 stateStartedAt=100,nextThink=math.huge,nextThreatScan=math.huge,nextIdleLatchCheck=math.huge,
 nextFollowerCareCheck=190,selfCareRetryAt={}}, C)
for _, name in ipairs({"tryBoardFollowVehicle","recoverFromDetached","tryAutomaticPlayerAid",
 "yieldBaseTaskForNeed","yieldInventoryCleanupForNeed","yieldAidForNeed","yieldCollectionForNeed"}) do
 c[name]=function() return false end
end
c.applyPendingCombatPolicy=function() return true end
c.bridge={cancelNpcMove=function() end}
c:tick(189)
assert(c.state=="COMPANION_WAIT", "settled follower does not recheck early")
c:tick(190)
assert(c.state=="IDLE" and c.nextThink==190 and c.nextFollowerCareCheck==280,
 "follower wakes for real care at exact deadline")
c.state="COMPANION_WAIT"; c.observedState=c.state; c.nextThink=math.huge
queue.queue={{}}
c:tick(280)
assert(c.state=="COMPANION_WAIT" and c.nextFollowerCareCheck==280, "queued native action owns the survivor")
queue.queue={}; actor.isKnockedDown=function() return true end
c:tick(281)
assert(c.state=="COMPANION_WAIT", "native injury recovery retains ownership")
actor.isKnockedDown=nil
c:tick(282)
assert(c.state=="IDLE", "care resumes when native ownership clears")
c.state="COMPANION_FOLLOW"; c.observedState=c.state; c.nextThink=math.huge
c.nextFollowerCareCheck=400; c.combatTarget={}
c.bridge.tickNpc=function() return "MOVE_RUNNING" end
c.refreshFormationFollow=function() return false end
c:tick(400)
assert(c.state=="COMPANION_FOLLOW" and c.nextFollowerCareCheck==400, "known combat target defers follow care")
c.combatTarget=nil; c.state="GROUP_FOLLOW"; c.observedState=c.state
c:tick(400)
assert(c.state=="IDLE" and c.nextFollowerCareCheck==490, "group follower wakes for care at deadline")
-- The controller's actual ownership boundary must admit an itemless removal.
actor.isDead=function() return false end
c.waitingForTransferActions=function() return false end
c.releaseTransferActions=function() end
c.state="IDLE"; c.pendingSelfCare=nil; c.reservations={}; queue.queue={}
local controllerAction, reason, controllerIntent=c:executeNeedAction(N.decide(actor,nil),300)
assert(controllerAction and c.state=="TIMED_ACTION", "controller admits healed removal without a supply claim: "..tostring(reason))
assert(controllerAction:complete() and N.verify(actor,controllerIntent), "controller-owned removal has native receipt")
c:releaseSelfCare()
ISTimedActionQueue, ISApplyBandage.new, CharacterStat, getCell, KnoxCompanionVehicles = oldQueue, oldNew, oldStats, oldCell, oldVehicles
print("Care lifecycle PASS real_planners=true native_boundary=true follower_cadence=true")
