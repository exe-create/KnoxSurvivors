local C=assert(KnoxAutonomyController)
local P=assert(KnoxPersistence)
local oldP,oldM,oldS,oldR=KnoxPersistence,KnoxMedicalActions,KnoxSettings,KnoxSurvivorRuntime
local oldPlayer,oldCount=getSpecificPlayer,getNumActivePlayers
local on,bandages,bleeding=true,true,true
local square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
local part={bleeding=function() return bleeding end,bandaged=function() return false end}
local patient={getCurrentSquare=function() return square end,isDead=function() return false end,
 getBodyDamage=function() return {getBodyParts=function() return {size=function() return 1 end,get=function() return part end} end} end,
 getVehicle=function() return nil end}
local doctor={getCurrentSquare=function() return square end,getVehicle=function() return nil end,
 getCharacterActions=function() return {isEmpty=function() return true end} end}
local bandage={}
KnoxPersistence={getSurvivorPolicies=function() return {autoMedical=on} end,
 ensurePlayerId=function() return "owner" end,isSurvivorHostileToPlayer=function() return false end,
 getPlayerSocialDisposition=function() return "warm_up" end}
KnoxMedicalActions={findBandageItem=function() return bandages and bandage or nil end}
KnoxSettings={allowSurvivorsTreatPlayer=function() return true end}
getSpecificPlayer=function() return patient end;getNumActivePlayers=function() return 1 end
local received=nil;local paused=0
local c=setmetatable({id="medic",character=doctor,state="BASE_TASK_WORK",companionOwnerId="owner",
 bridge={cancelNpcMove=function() end},reservations={items={}},
 aidNeedsSelfCare=function() return false end,
 canPauseWorkForInteraction=function() return true end,
 pauseWorkForInteraction=function() paused=paused+1;return true end,
 beginBattlefieldAid=function(self,ticks,found) received=found;return true end},C)
on=false
local ok,reason=c:requestMedicalAid(patient,10,true)
assert(not ok and reason=="automatic_medical_off" and paused==0, "auto preference prevents unsolicited treatment and work interruption")
ok,reason=c:requestMedicalAid(patient,10,false)
assert(ok and received.patient==patient and received.part==part and received.bandage==bandage and received.directRequest,
 "explicit request still reaches aid with exact patient, native wound and owned supply when automatic aid is off")
assert(paused==1, "medical request uses existing safe work pause")
received=nil;on=true
assert(c:tryAutomaticPlayerAid(90) and received and not received.directRequest, "owned-player automatic scan reaches same aid owner")
assert(c:tryAutomaticPlayerAid(91)==false and paused==2, "automatic aid is bounded by scan interval")
bandages=false
ok,reason=c:requestMedicalAid(patient,100,false)
assert(not ok and reason=="no_bandage" and paused==2, "no supplies produces a real reason without abandoning work")
bandages=true;bleeding=false
ok,reason=c:requestMedicalAid(patient,100,false)
assert(not ok and reason=="no_treatable_bleeding", "unsupported injuries are explained, never healed by fiat")
local antiseptic={}
KnoxMedicalActions.maintenancePlan=function() return {kind="disinfect",item=antiseptic,bodyPart=part} end
ok,reason=c:requestMedicalAid(patient,100,false)
assert(ok and received.kind=="disinfect" and received.bandage==antiseptic,
 "direct request selects real carried disinfectant for an uncovered non-bleeding wound")
KnoxMedicalActions.maintenancePlan=nil
bleeding=true;c.state="COMBAT"
ok,reason=c:requestMedicalAid(patient,100,false)
assert(not ok and reason=="unsafe_to_treat", "medical request does not override live combat")
KnoxPersistence,KnoxMedicalActions,KnoxSettings,KnoxSurvivorRuntime=oldP,oldM,oldS,oldR
getSpecificPlayer,getNumActivePlayers=oldPlayer,oldCount
-- Test real persistence ownership guard without altering another fixture's graph.
local priorData=data;data={}
local id="medical-policy-owner"
-- Production player assignment owns the policy boundary; use existing fixture setter idiom.
local wrong=P.setSurvivorAutoMedical(id,"stranger",false,0)
assert(not wrong, "an unaffiliated person cannot receive an owned medical preference")
assert(P.setRecord(id,expectedRecord))
assert(P.setPlayerCompanion(id,"owner","follow",0))
assert(P.setSurvivorAutoMedical(id,"owner",false,1) and P.getSurvivorPolicies(id).autoMedical==false,
 "owned companion preference persists an explicit off")
assert(not P.setSurvivorAutoMedical(id,"stranger",true,2) and P.getSurvivorPolicies(id).autoMedical==false,
 "another player cannot overwrite the medical preference")
data=priorData
print("Medical help PASS explicit=true automaticToggle=true safeWorkPause=true exactPatient=true refusalReasons=true")
