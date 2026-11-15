local C=assert(KnoxAutonomyController)
local oldCell,oldManager,oldNeeds,oldRuntime,oldCount,oldPlayer=getCell,KnoxBaseManager,KnoxSurvivorNeeds,KnoxSurvivorRuntime,getNumActivePlayers,getSpecificPlayer
local lookups=0
getNumActivePlayers=function() return 0 end
getSpecificPlayer=function(index) assert(index==0,"zero-player lookup uses index zero");lookups=lookups+1;return nil end
local square={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end}
local source={getSquare=function() return square end}
local actor={getCurrentSquare=function() return square end,hasFullInventory=function() return true end}
getCell=function() return {getZombieList=function() return {size=function() return 0 end} end} end
KnoxSurvivorRuntime=nil
KnoxBaseManager={containsSquare=function() return true end}
KnoxSurvivorNeeds={decide=function() return {kind="find_water"} end,snapshot=function() return {thirst=0.8} end}
local c=setmetatable({id="water-capacity-fixture",base={},baseId="base",character=actor,state="MOVING_TO_SUPPLY",
 pendingSupply={waterSource=source,approach=square},selfCareRetryAt={},nextThink=0},C)
function c:allowNeedDetour() return true end
function c:executeNeedAction() return nil,"native_water_action_refused_full_inventory" end
function c:recordFailure() end
function c:sayAction() return true end
function c:releaseSupply() self.pendingSupply=nil end
function c:finishDecision() self.state="IDLE" end
function c:beginInventoryCleanup(_,mode) self.cleanupMode=mode; return true end
local ok,err=pcall(function() c:beginWorldWaterAction(100) end)
getCell,KnoxBaseManager,KnoxSurvivorNeeds,KnoxSurvivorRuntime,getNumActivePlayers,getSpecificPlayer=oldCell,oldManager,oldNeeds,oldRuntime,oldCount,oldPlayer
assert(ok,"water_capacity: production call failed: "..tostring(err))
assert(lookups==1,"water_capacity: real zero-player threat lookup executed")
assert(c.cleanupMode==true,"water_capacity: full inventory invokes deposit-only cleanup")
-- Integration through actual cleanup owner; only planner and native/engine edges are doubled.
local oldLoot=KnoxSurvivorLooting
local Loot=assert(codecWaterLooting)
KnoxSurvivorLooting=Loot
local P=KnoxPersistence
local A=KnoxInventoryActions
local B=KnoxBaseStorage
local oldPlan,oldDuty,oldAff,oldBase=Loot.cleanupPlan,P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase
local oldNear,oldReceive,oldTransfer,oldQueue=B.findNearbyDeposit,B.canReceiveItem,A.queueTransfer,ISTimedActionQueue
local oldManager2,oldNeeds2=KnoxBaseManager,KnoxSurvivorNeeds
local full=true
local contents={}
local stored={}
local inv={contains=function(_,item) return contents[item]==true end}
local dest={contains=function(_,item) return stored[item]==true end}
local item={getContainer=function() return inv end,isFavorite=function() return false end}
contents[item]=true
local pawn={getCurrentSquare=function() return square end,getInventory=function() return inv end,
 getCharacterActions=function() return nil end,hasFullInventory=function() return full end}
local base={id="base"}
P.getSurvivorDuty=function() return {mode="base",baseId="base"} end
P.getSurvivorAffiliation=function() return {kind="player",ownerId="owner"} end
P.getBase=function() return base end
KnoxBaseManager={containsSquare=function() return true end}
KnoxSurvivorNeeds={decide=function() return {kind="find_water"} end}
local planReads,nearReads=0,0
local hasSurplus=true
Loot.cleanupPlan=function() planReads=planReads+1;return hasSurplus and {{item=item,source=inv,reason="surplus"}} or {},"base_deposit" end
local found=true
B.findNearbyDeposit=function(_,_,_,key) nearReads=nearReads+1;if not found then return nil end return {container=dest,policy={key="shelf"}} end
B.canReceiveItem=function() return true end
local queue={queue={}}
ISTimedActionQueue={queues={[pawn]=queue}}
A.queueTransfer=function(character,selected,src,dst,_,guard)
 local action={character=character,item=selected,srcContainer=src,destContainer=dst}
 action.knoxTransferGuard=guard; queue.queue={action};return action,"queued"
end
local r=setmetatable({id="resident",baseId="base",base=base,character=pawn,state="IDLE",nextCleanupAt=0,
 nextThink=0,selfCareRetryAt={},reservations={items={}},counts={},blockedAreas={}},C)
function r:beginDepositTrip() error("water mode must never start a deposit trip") end
function r:recordBaseSupplyDepositReceipt() return false end
function r:releaseTransferActions() queue.queue={} return false end
function r:recordFailure(reason) self.failure=reason end
function r:finishDecision() self:releaseInventoryCleanup();self.state="IDLE" end
assert(r:beginInventoryCleanup(100,true),"real cleanup owner admits nearby deposit")
assert(planReads==1 and nearReads==1,"one planner and nearby lookup for single candidate")
local transfer=r.pendingCleanup
assert(transfer and transfer.waterCapacity and transfer.destination==dest and transfer.guard(transfer.action,item),
 "water cleanup retains exact guarded deposit")
KnoxBaseManager.containsSquare=function() return false end
assert(not transfer.guard(transfer.action,item),"leaving owned base revokes cleanup")
KnoxBaseManager.containsSquare=function() return true end
assert(not r:yieldInventoryCleanupForNeed(101),"same water need does not cancel pending transfer")
contents[item]=nil;stored[item]=true;full=false
assert(not r:yieldInventoryCleanupForNeed(200),"completed transfer reaches receipt when no longer full")
queue.queue={}
r:updateInventoryCleanup(200)
assert(r.state=="IDLE" and r.pendingCleanup==nil and dest:contains(item),"real receipt releases cleanup after actual containment change")
-- No owned nearby store never falls through to a world drop or trip.
contents[item]=true;stored[item]=nil;full=true;found=false;r.nextCleanupAt=0
assert(not r:beginInventoryCleanup(500,true) and r.pendingCleanup==nil,"no nearby store refuses safely")
found=true;r.nextCleanupAt=0;hasSurplus=false
assert(not r:beginInventoryCleanup(500,true),"no safe surplus refuses")
hasSurplus=true;r.nextCleanupAt=0
r.reservations.items[item]="other"
assert(not r:beginInventoryCleanup(500,true),"reserved surplus refuses")
r.reservations.items[item]=nil
found=true;r.nextCleanupAt=0;r.baseId="foreign"
assert(not r:beginInventoryCleanup(500,true),"foreign base refuses")
r.baseId="base";r.nextCleanupAt=0;r.companionOrder="follow"
assert(not r:beginInventoryCleanup(500,true),"order preempts capacity cleanup")
r.companionOrder=nil;r.nextCleanupAt=0
assert(r:beginInventoryCleanup(500,true))
transfer=r.pendingCleanup;r.companionOrder="follow"
assert(not transfer.guard(transfer.action,item),"changed order revokes transfer")
r:releaseInventoryCleanup();r.state="IDLE";r.companionOrder=nil
-- Failed receipt retains item; no capacity success is invented.
r.nextCleanupAt=0;contents[item]=true;stored[item]=nil;full=true
assert(r:beginInventoryCleanup(800,true));queue.queue={}
r:updateInventoryCleanup(810)
assert(r.failure=="cleanup_transfer_not_completed" and contents[item] and not stored[item],"failed transfer remains unreceived")
-- Verified transfer with still-full or unreadable capacity never starts drink.
r.nextCleanupAt=0;r.depositRetryAt={};r.failure=nil;assert(r:beginInventoryCleanup(1200,true));contents[item]=nil;stored[item]=true;queue.queue={}
full=true;r:updateInventoryCleanup(1210)
assert(r.nextCleanupAt>=1510 and r.state=="IDLE","still-full receipt uses bounded retry")
contents[item]=true;stored[item]=nil;r.nextCleanupAt=0;full=true
assert(r:beginInventoryCleanup(1600,true));contents[item]=nil;stored[item]=true;queue.queue={}
pawn.hasFullInventory=function() error("unreadable") end
r:updateInventoryCleanup(1610)
assert(r.failure=="water_capacity_unreadable" and r.state=="IDLE","unknown capacity fails honestly")
pawn.hasFullInventory=function() return full end
-- Changed higher-priority need and threat revoke cleanup admission guard.
contents[item]=true;stored[item]=nil;r.nextCleanupAt=0;full=true
assert(r:beginInventoryCleanup(2000,true));transfer=r.pendingCleanup
KnoxSurvivorNeeds.decide=function() return {kind="find_medical"} end
assert(not transfer.guard(transfer.action,item),"medical need revokes pending transfer")
r.nextCleanupNeedCheck=0;assert(r:yieldInventoryCleanupForNeed(2001),"medical need preempts cleanup")
KnoxSurvivorNeeds.decide=function() return {kind="find_water"} end
r.nextCleanupAt=0;assert(r:beginInventoryCleanup(2100,true));transfer=r.pendingCleanup
r.combatTarget={}
assert(not transfer.guard(transfer.action,item),"combat target revokes pending transfer")
r:releaseInventoryCleanup();r.state="IDLE";r.combatTarget=nil
assert(not transfer.guard(transfer.action,item),"cancelled cleanup cannot transfer")
-- Rejected/full/unloaded destination never becomes a successful receipt.
r.nextCleanupAt=0;contents[item]=true;stored[item]=nil;full=true
assert(r:beginInventoryCleanup(2200,true),"candidate can be selected before destination changes")
transfer=r.pendingCleanup;B.canReceiveItem=function() return false end
assert(not transfer.guard(transfer.action,item),"full destination revokes native transfer")
B.canReceiveItem=function() return true end
r:releaseInventoryCleanup();r.state="IDLE";r.nextCleanupAt=0
A.queueTransfer=function() return nil,"queue_refused" end
assert(not r:beginInventoryCleanup(2500,true) and r.pendingCleanup==nil and contents[item],
 "refused queue retains real item")
-- Full refusal through real water owner reaches the real cleanup owner.
local handCell,handRuntime,handCount,handPlayer=getCell,KnoxSurvivorRuntime,getNumActivePlayers,getSpecificPlayer
getNumActivePlayers=function() return 0 end;getSpecificPlayer=function() return nil end
getCell=function() return {getZombieList=function() return {size=function() return 0 end} end} end
KnoxSurvivorRuntime=nil
A.queueTransfer=function(character,selected,src,dst,_,guard)
 local action={character=character,item=selected,srcContainer=src,destContainer=dst}
 action.knoxTransferGuard=guard;queue.queue={action};return action,"queued"
end
KnoxSurvivorNeeds.snapshot=function() return {thirst=0.8} end
r.nextCleanupAt=0;r.depositRetryAt={};r.state="MOVING_TO_SUPPLY";r.pendingSupply={waterSource=source,approach=square}
function r:allowNeedDetour() return true end
function r:executeNeedAction() return nil,"native_water_action_refused_full_inventory" end
function r:sayAction() return true end
function r:releaseSupply() self.pendingSupply=nil end
assert(r:beginWorldWaterAction(3000) and r.pendingCleanup and r.pendingCleanup.waterCapacity,
 "water_capacity: full refusal reaches real nearby cleanup")
r:releaseInventoryCleanup();r.state="IDLE"
getCell,KnoxSurvivorRuntime,getNumActivePlayers,getSpecificPlayer=handCell,handRuntime,handCount,handPlayer
-- Existing real item utility protection is exercised independently of planner stub.
local protected={getFullType=function() return "Base.Test" end,isFavorite=function() return true end}
local allowed,reason=Loot.itemUtility({isEquipped=function() return false end,isHandItem=function() return false end},protected,{}, {},true)
assert(allowed==nil and reason=="equipped_or_favorite","real loot owner protects favorite")
Loot.cleanupPlan,P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase=oldPlan,oldDuty,oldAff,oldBase
B.findNearbyDeposit,B.canReceiveItem,A.queueTransfer,ISTimedActionQueue=oldNear,oldReceive,oldTransfer,oldQueue
KnoxBaseManager,KnoxSurvivorNeeds,KnoxSurvivorLooting=oldManager2,oldNeeds2,oldLoot
print("Water capacity integration PASS cleanup_owner=true planner_stub=true native_transfer_stub=true")
-- Real Needs water admission and verification with a shaped native action.
local N=KnoxSurvivorNeeds
local oldWaterClass,oldQueue2,oldStats=ISTakeWaterAction,ISTimedActionQueue,CharacterStat
ISTakeWaterAction={}
CharacterStat={HUNGER="hunger",THIRST="thirst",FATIGUE="fatigue",ENDURANCE="endurance"}
local thirst,amount=0.8,2
local body={getNumPartsBleeding=function() return 0 end,getHealth=function() return 100 end}
local waterActor={getStats=function() return {get=function(_,k) return k=="thirst" and thirst or 0 end} end,
 getBodyDamage=function() return body end,hasFullInventory=function() return full end,
 getInventory=function() return {getItems=function() return {size=function() return 0 end} end} end}
local faucet={hasFluid=function() return amount>0 end,getFluidAmount=function() return amount end,
 isTaintedWater=function() return false end}
local waterQueue={queue={}}
ISTimedActionQueue={queues={[waterActor]=waterQueue},add=function(action) waterQueue.queue={action};return waterQueue end}
local mutateSource,mutateThirst=true,true
ISTakeWaterAction.new=function(_,character,_,object)
 local action={character=character,waterObject=object,isValid=function() return not full and amount>0 end}
 function action:transferFluid()
  if mutateSource then amount=amount-0.5 end
  if mutateThirst then thirst=thirst-0.2 end
 end
 function action:complete() self:transferFluid();return true end
 return action
end
local function admission()
 local before=N.snapshot(waterActor)
 return N.execute(waterActor,{kind="drink_world",source=faucet,state=before},{allowed=function() return true end})
end
full=true;local action,why=admission()
assert(action==nil and why=="native_water_action_refused_full_inventory","native full refusal remains intact")
full=false;amount=0;action,why=admission()
assert(action==nil and why=="water_source_unavailable","dry source yields honest refusal")
amount=2;thirst=0.8;waterQueue.queue={}
ISTimedActionQueue.add=function() return nil end
local refused,refusal=admission();assert(refused==nil and refusal=="native_water_action_queue_rejected","native queue refusal is distinct")
ISTimedActionQueue.add=function(a) waterQueue.queue={a};return waterQueue end
amount=2;thirst=0.8;waterQueue.queue={};local intent;action,why,intent=admission()
assert(action and intent and not N.verify(waterActor,intent),"queued action alone never proves drink")
action:complete();assert(N.verify(waterActor,intent),"actual simulated source and thirst deltas verify")
amount=2;thirst=0.8;waterQueue.queue={};mutateSource=true;mutateThirst=false
local onlySource,_,sourceIntent=admission();onlySource:complete()
assert(not N.verify(waterActor,sourceIntent),"source delta without thirst is not consumption")
amount=2;thirst=0.8;waterQueue.queue={};mutateSource=false;mutateThirst=true
local onlyThirst,_,thirstIntent=admission();onlyThirst:complete()
assert(not N.verify(waterActor,thirstIntent),"thirst delta without source is not consumption")
amount=2;thirst=0.8;waterQueue.queue={};mutateSource=true;mutateThirst=true
local cancelled,_,cancelledIntent=admission();cancelledIntent.cancelled=true
assert(not cancelled:complete() and not N.verify(waterActor,cancelledIntent),"cancelled action cannot mutate or verify")
ISTakeWaterAction,ISTimedActionQueue,CharacterStat=oldWaterClass,oldQueue2,oldStats
print("Water receipt PASS real_needs=true native_action_stub=true both_deltas_required=true")
