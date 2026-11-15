-- Real medical receipt hook -> full companion service -> persistence writer.
-- Only native actors, items, completion effects and speech are doubled.
local M,C,P=KnoxMedicalActions,KnoxCompanionService,KnoxPersistence
local old={Runtime=KnoxSurvivorRuntime,Feed=KnoxActivityFeed,Signals=KnoxOrderSignals,
 Needs=KnoxSurvivorNeeds,Player=getSpecificPlayer,Time=getGameTime,
 Bandage=ISApplyBandage,Disinfect=ISDisinfect,Splint=ISSplint,Stitch=ISStitch,Types=BodyPartType,Data=data}
BodyPartType={Head="head",Torso_Upper="upper",Torso_Lower="lower",ForeArm_L="arm"}
data={}
assert(P.setRecord("care-patient",expectedRecord),"care patient record exists")
local now,spoken,reputation,nativeCalls=12,0,0,0
local square={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end}
local contents,playerData={},{}
local inventory={contains=function(_,item) return contents[item]==true end}
local doctor={getPlayerNum=function() return 0 end,getInventory=function() return inventory end,
 getModData=function() return playerData end,getCurrentSquare=function() return square end,
 isDead=function() return false end}
local part={injured=true,covered=false,life=0,alcohol=0}
function part:HasInjury() return self.injured end
function part:bandaged() return self.covered end
function part:getBandageLife() return self.life end
function part:getAlcoholLevel() return self.alcohol end
function part:getFractureTime() return self.fracture or 0 end
function part:getSplintFactor() return self.splint or 0 end
function part:stitched() return self.stitches==true end
function part:isDeepWounded() return self.deep==true end
function part:haveGlass() return self.glass==true end
function part:getType() return self.kind end
part.kind=BodyPartType.ForeArm_L
local bodyParts={size=function() return 1 end,get=function() return part end}
local patient={getCurrentSquare=function() return square end,isDead=function(self) return self.dead==true end,
 getBodyDamage=function() return {getBodyParts=function() return bodyParts end} end}
local mapped=patient
KnoxSurvivorRuntime={idForCharacter=function(actor) if actor==patient then return "care-patient" end end,
 getCharacter=function(id) if id=="care-patient" then return mapped end end,
 canInteract=function() return true end,beginPlayerConversation=function() return true end,
 endPlayerConversation=function() return true end}
getSpecificPlayer=function(index) if index==0 then return doctor end end
getGameTime=function() return {getWorldAgeHours=function() return now end} end
KnoxOrderSignals=nil;KnoxSurvivorNeeds=nil
KnoxActivityFeed={speak=function(_,line) assert(type(line)=="string" and line~="");spoken=spoken+1 end,
 reputation=function(_,delta) reputation=reputation+delta end}
local function supply(fluid)
 local item={amount=1}
 if fluid then function item:getFluidContainer() return {getAmount=function() return item.amount end} end end
 contents[item]=true;return item
end
local mode="normal"
local function nativeComplete(action,kind)
 nativeCalls=nativeCalls+1
 if mode=="fail" then return false end
 if kind=="bandage" then
  if mode~="no-effect" then action.bodyPart.covered=action.doIt;action.bodyPart.life=10 end
  if mode~="free" then contents[action.item]=nil end
 else
  if mode~="no-effect" then action.bodyPart.alcohol=action.bodyPart.alcohol+4 end
  if mode~="free" then action.alcohol.amount=action.alcohol.amount-0.15 end
 end
 if mode=="remap" then mapped={} end
 return true
end
ISApplyBandage={complete=function(action) return nativeComplete(action,"bandage") end}
ISDisinfect={complete=function(action) return nativeComplete(action,"disinfect") end}
M.installPlayerCareReceipts()
local wrapped=ISApplyBandage.complete
M.installPlayerCareReceipts()
assert(ISApplyBandage.complete==wrapped,"completion hook installs once")
local playerId=P.ensurePlayerId(doctor)
local relation=P.getPlayerRelationship(playerId,"care-patient")
local function bandage(who,target,wound)
 part.covered=false;part.life=0
 return {character=who or doctor,otherPlayer=target or patient,bodyPart=wound or part,
  item=supply(false),doIt=true}
end
local function disinfect()
 return {character=doctor,otherPlayer=patient,bodyPart=part,alcohol=supply(true)}
end
for _,act in ipairs(C.socialActs()) do assert(act~="healed","care receipt cannot be selected in Talk") end
local a=bandage()
assert(relation.trust==30 and spoken==0,"admission earns no standing")
assert(ISApplyBandage.complete(a)==true,"native bandage result preserved")
assert(relation.trust==35 and relation.lastTrustCause=="healed" and relation.lastTrustDelta==5,
 "completed costed bandage earns five standing")
assert(relation.history.healed==5 and C.historyTone(relation)=="warmer" and spoken==1 and reputation==5,
 "existing history and speech consume the care receipt")
local calls=nativeCalls
assert(ISApplyBandage.complete(a)==true and nativeCalls==calls and relation.trust==35 and spoken==1,
 "duplicate completion repeats neither native cost nor reward")
local b=disinfect()
assert(ISDisinfect.complete(b)==true and b.alcohol.amount==0.85 and part.alcohol==4,
 "cooldown never prevents real native treatment")
assert(relation.trust==35 and spoken==1,"same-hour care is quietly cooldown limited")
now=13.1
assert(ISDisinfect.complete(disinfect())==true and relation.trust==40 and spoken==2,
 "later costed disinfection earns standing through same writer")
assert(relation.history.healed==10 and relation.meetings==2,"two recorded care exchanges share existing history")
local baseline=relation.trust
local function noReward(action,class,label)
 now=now+2;local beforeSpoken=spoken
 class.complete(action)
 assert(relation.trust==baseline and spoken==beforeSpoken,label)
end
mode="fail";noReward(bandage(),ISApplyBandage,"failed native completion earns nothing")
mode="free";noReward(bandage(),ISApplyBandage,"effect without supply cost earns nothing")
mode="no-effect";noReward(bandage(),ISApplyBandage,"supply cost without effect earns nothing")
mode="normal"
local remove=bandage();remove.doIt=false
noReward(remove,ISApplyBandage,"bandage removal earns nothing")
noReward(bandage(doctor,doctor),ISApplyBandage,"self care earns nothing")
local npc={getPlayerNum=function() return -1 end}
noReward(bandage(npc),ISApplyBandage,"NPC treatment is not attributed to player")
local stranger={isDead=function() return false end,getBodyDamage=patient.getBodyDamage}
noReward(bandage(doctor,stranger),ISApplyBandage,"unmapped patient earns nothing")
local wrongPart={HasInjury=function() return true end}
noReward(bandage(doctor,patient,wrongPart),ISApplyBandage,"another body's part earns nothing")
patient.dead=true;noReward(bandage(),ISApplyBandage,"dead patient earns nothing");patient.dead=false
part.injured=false;noReward(bandage(),ISApplyBandage,"uninjured part earns nothing");part.injured=true
local absent=bandage();contents[absent.item]=nil
noReward(absent,ISApplyBandage,"supply absent before completion earns nothing")
mode="remap";noReward(bandage(),ISApplyBandage,"changed patient identity invalidates receipt");mapped=patient
mode="normal"
-- Disinfect has independent cost/effect checks, not just the bandage branch.
mode="free";noReward(disinfect(),ISDisinfect,"free disinfection earns nothing")
mode="no-effect";noReward(disinfect(),ISDisinfect,"ineffective disinfection earns nothing")
mode="normal"
P.setSurvivorHostileToPlayer("care-patient",playerId,true)
noReward(bandage(),ISApplyBandage,"hostile standing admission still refuses care reward")
P.setSurvivorHostileToPlayer("care-patient",playerId,false)
-- CS2a: assembled/prebuilt splints and consumed-use sutures share the same act.
ISSplint={complete=function(action)
 nativeCalls=nativeCalls+1
 if mode=="fail" then return false end
 if mode~="no-effect" then action.bodyPart.splint=action.doIt and 2 or 0 end
 if action.doIt and mode~="free" then
  contents[action.plank]=nil
  if action.rippedSheet and mode~="partial" then contents[action.rippedSheet]=nil end
 end
 return true
end}
ISStitch={complete=function(action)
 nativeCalls=nativeCalls+1
 if mode=="fail" then return false end
 if mode~="no-effect" then action.bodyPart.stitches=action.doIt end
 if action.item and mode~="free" then action.item.amount=action.item.amount-0.2 end
 return true
end}
M.installPlayerCareReceipts()
local function splint(prebuilt)
 part.splint=0;part.fracture=6;part.stitches=false
 return {character=doctor,otherPlayer=patient,bodyPart=part,doIt=true,
  plank=supply(false),rippedSheet=not prebuilt and supply(false) or nil}
end
local function stitch()
 part.covered=false;part.stitches=false;part.deep=true;part.glass=false
 local thread=supply(false)
 function thread:getCurrentUsesFloat() return self.amount end
 return {character=doctor,otherPlayer=patient,bodyPart=part,doIt=true,item=thread}
end
mode="normal";now=now+2
local cast=splint(false)
assert(ISSplint.complete(cast)==true and part.splint>0
 and not contents[cast.plank] and not contents[cast.rippedSheet] and relation.trust==45,
 "assembled splint earns standing only after both supplies are consumed")
calls=nativeCalls
ISSplint.complete(cast)
assert(nativeCalls==calls and relation.trust==45,"splint duplicate cannot spend or reward twice")
now=now+2;local ready=splint(true)
assert(ISSplint.complete(ready) and relation.trust==50,"prebuilt splint needs its one real consumed item")
now=now+2;local suture=stitch()
local holder=supply(false)
assert(ISStitch.complete(suture) and suture.item.amount==0.8 and contents[suture.item]
 and contents[holder] and relation.trust==55,"stitch observes consumed thread use without spending reusable holder")
calls=nativeCalls;ISStitch.complete(suture)
assert(nativeCalls==calls and relation.trust==55,"stitch duplicate cannot spend or reward twice")
baseline=relation.trust
for _,which in ipairs({"splint","stitch"}) do
 local class=which=="splint" and ISSplint or ISStitch
 local function action() if which=="splint" then return splint(false) end;return stitch() end
 mode="fail";noReward(action(),class,which.." failure earns nothing")
 mode="free";noReward(action(),class,which.." free effect earns nothing")
 mode="no-effect";noReward(action(),class,which.." spent supply without effect earns nothing")
 mode="normal";local removal=action();removal.doIt=false
 noReward(removal,class,which.." removal earns nothing")
 local selfCare=action();selfCare.otherPlayer=doctor
 noReward(selfCare,class,which.." self care earns nothing")
 local npcCare=action();npcCare.character=npc
 noReward(npcCare,class,which.." NPC care is not player credit")
end
mode="partial";noReward(splint(false),ISSplint,"assembled splint with unspent sheet earns nothing")
mode="normal";local missing=splint(false);contents[missing.rippedSheet]=nil
noReward(missing,ISSplint,"missing selected sheet prevents care receipt")
local duplicateSupply=splint(false);duplicateSupply.rippedSheet=duplicateSupply.plank
noReward(duplicateSupply,ISSplint,"one item cannot satisfy both splint materials")
local noFracture=splint(true);part.fracture=0
noReward(noFracture,ISSplint,"splint without fracture earns nothing")
local alreadySplinted=splint(true);part.splint=2
noReward(alreadySplinted,ISSplint,"already splinted part earns nothing")
local alreadyStitched=stitch();part.stitches=true
noReward(alreadyStitched,ISStitch,"already stitched part earns nothing")
local superficial=stitch();part.deep=false
noReward(superficial,ISStitch,"non-deep wound cannot earn stitch credit")
local glassWound=stitch();part.glass=true
noReward(glassWound,ISStitch,"glass must be removed before stitch credit")
local covered=stitch();part.covered=true
noReward(covered,ISStitch,"covered wound cannot earn stitch credit")
for _,excluded in ipairs({BodyPartType.Head,BodyPartType.Torso_Upper,BodyPartType.Torso_Lower}) do
 local unsupported=splint(true);part.kind=excluded
 noReward(unsupported,ISSplint,"unsupported native anatomy earns no cast standing")
end
part.kind=BodyPartType.ForeArm_L
KnoxSurvivorRuntime=old.Runtime;KnoxActivityFeed=old.Feed;KnoxOrderSignals=old.Signals
KnoxSurvivorNeeds=old.Needs;getSpecificPlayer=old.Player;getGameTime=old.Time
ISApplyBandage=old.Bandage;ISDisinfect=old.Disinfect;ISSplint=old.Splint;ISStitch=old.Stitch;data=old.Data
BodyPartType=old.Types
KnoxCompanionService=careSourcePrior.Service;Events=careSourcePrior.Events;careSourcePrior=nil
print("Player care standing CS1/CS2a PASS nativeGameplay=false")
