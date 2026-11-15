-- Production controllers, native posture actions, self-care lease and real Needs
-- receipt verification; only the installed engine/world boundary is doubled.
local C,N,R=KnoxAutonomyController,KnoxSurvivorNeeds,KnoxSurvivorRuntime
local old={Queue=ISTimedActionQueue,Sit=ISSitOnGround,Rest=ISRestAction,Eat=ISEatFoodAction,
 Stats=CharacterStat,Cell=getCell,Bridge=KnoxJavaBridge,Vehicles=KnoxCompanionVehicles,
 Duty=KnoxPersistence.getSurvivorDuty,Residents=KnoxPersistence.getBaseResidentIds,
 Contains=KnoxBaseManager.containsSquare,Schedule=KnoxBaseJobs.scheduleAssignment,
 Say=KnoxSurvivorDialogue.say,Client=isClient,NativeTransfer=ISInventoryTransferAction.transferItem,NativeCancel=ISInventoryTransferAction.forceCancel}
CharacterStat={HUNGER="hunger",THIRST="thirst",FATIGUE="fatigue",ENDURANCE="endurance",
 SICKNESS="sickness",FOOD_SICKNESS="foodSickness",POISON="poison"}
isClient=function() return false end
getCell=function() return nil end;KnoxJavaBridge=nil;KnoxCompanionVehicles=nil
local people,spoken,seatReject,seatReentry={},0,nil,nil
local transferMode=nil
KnoxPersistence.getSurvivorDuty=function(id) return {mode="base",baseId="meal-base"} end
KnoxPersistence.getBaseResidentIds=function() return {"meal-one","meal-two"} end
KnoxBaseManager.containsSquare=function(_,square) return square and square.x<10 end
KnoxBaseJobs.scheduleAssignment=function(id) return people[id] and people[id].assignment or "recreation" end
KnoxSurvivorDialogue.say=function() spoken=spoken+1;return true end
local queues={}
local function queueFor(a)
 if queues[a] then return queues[a] end
 local q={queue={}}
 function q:indexOf(action) for i,x in ipairs(self.queue) do if action==x then return i end end return -1 end
 function q:removeFromQueue(action) local i=self:indexOf(action);if i~=-1 then table.remove(self.queue,i) end end
 queues[a]=q;return q
end
ISTimedActionQueue={queues=queues,add=function(action)
 if action.seat and seatReject==action.character then error("native seat refused") end
 local q=queueFor(action.character);q.queue[#q.queue+1]=action
 if action.seat and seatReentry==action.character then people[action.character.id]:releaseSharedMeal(1) end
 if action.srcContainer and transferMode=="reentry" then people[action.character.id]:releaseSharedMeal(2) end
 return q
end,clear=function(a) queueFor(a).queue={};queueFor(a).current=nil end}
local function inventory()
 local inv={items={}}
 function inv:getItems() return {size=function() return #self.items end,get=function(_,i) return self.items[i+1] end} end
 function inv:contains(item) for _,x in ipairs(self.items) do if x==item then return true end end return false end
 function inv:isInCharacterInventory() return true end
 function inv:add(item) self.items[#self.items+1]=item;item.container=self end
 function inv:remove(item) for i,x in ipairs(self.items) do if x==item then table.remove(self.items,i);item.container=nil;return end end end
 return inv
end
local function food(inv)
 local f={container=inv,amount=-0.3}
 function f:IsFood() return true end
 function f:IsInventoryContainer() return false end
 function f:getHungerChange() return self.amount end
 function f:getUnhappyChange() return 0 end
 function f:isRotten() return self.rotten==true end
 function f:isPoison() return false end
 function f:getPoisonPower() return 0 end
 function f:isbDangerousUncooked() return false end
 function f:isCooked() return true end
 function f:getContainer() return self.container end
 function f:getFullType() return "Base.Apple" end
 inv.items[#inv.items+1]=f;return f
end
local function actor(id,x)
 local inv=inventory()
 local a={id=id,inv=inv,hunger=0.35,endurance=1,fatigue=0,sickness=0,seated=false,
 square={x=x,getX=function(self) return self.x end,getY=function() return 0 end,getZ=function() return 0 end}}
 local body={getNumPartsBleeding=function() return 0 end,getHealth=function() return 100 end,
 getPain=function() return 0 end,getColdStrength=function() return 0 end,
 getBodyParts=function() return {size=function() return 0 end,get=function() end} end}
 function a:getInventory() return self.inv end
 function a:getStats() return {get=function(_,k) return self[k] or 0 end} end
 function a:getBodyDamage() return body end
 function a:getCurrentSquare() return self.square end
 function a:getCharacterActions() return nil end
 function a:getVehicle() return nil end
 function a:isDead() return self.dead==true end
 function a:isAsleep() return false end
 function a:isPlayerMoving() return false end
 function a:isKnockedDown() return self.down==true end
 function a:isOnFloor() return false end
 function a:isSitOnGround() return self.seated end
 function a:isSittingOnFurniture() return false end
 function a:getCurrentStateName() return self.seated and "PlayerSitOnGroundState" or "IdleState" end
 function a:getCurrentActionContextStateName() return self.seated and "sitonground" or "idle" end
 function a:CanSee(other) return not self.hidden end
 function a:setIsResting(value) self.resting=value end
 function a:setBed(value) self.bed=value end
 function a:setVariable(key,value) if key=="forceGetUp" and value then self.seated=false end end
 food(inv);return a
end
ISSitOnGround={new=function(_,a)
 return {character=a,seat=true,forceCancel=function() end,isValid=function() return true end,
 start=function(self) a.seated=true;return true end,complete=function() return true end}
end}
ISRestAction=ISSitOnGround
ISEatFoodAction={new=function(_,a,item,percentage)
 return {character=a,item=item,forceCancel=function() end,isValid=function() return a.inv:contains(item) end,
 complete=function(self)
  if not a.noConsumption then a.hunger=a.hunger-0.1;item.amount=item.amount+0.1 end
  return true
 end}
end}
ISInventoryTransferAction.forceCancel=function() end
ISInventoryTransferAction.transferItem=function(action,item)
 if transferMode=="missing" then return end
 local moved=transferMode=="wrong" and action.srcContainer.items[2] or item
 if moved then old.NativeTransfer(action,moved) end
end
local function bagFood(c)
 local main=c.character.inv;local item=main.items[1];main:remove(item)
 local bagInv=inventory();bagInv.items[1]=item;item.container=bagInv
 local bag={getInventory=function() return bagInv end,IsInventoryContainer=function() return true end,
  IsFood=function() return false end,getContainer=function() return main end}
 main.items[#main.items+1]=bag
 return item,bagInv
end
local serial=0
local function pair()
 for id,c in pairs(people) do R.unregister(id,c) end
 queues={};ISTimedActionQueue.queues=queues;spoken=0;seatReject=nil;seatReentry=nil;transferMode=nil
 local shared={items={},restSpots={}}
 local function controller(id,x)
  local a=actor(id,x)
  local c=setmetatable({id=id,character=a,state="IDLE",baseId="meal-base",base={},reservations=shared,
   nextThink=math.huge,nextThreatScan=math.huge,nextIdleLatchCheck=math.huge,
   observedState="IDLE",stateStartedAt=0,selfCareRetryAt={},counts={needs=0}},C)
  for _,name in ipairs({"tryBoardFollowVehicle","tryAutomaticPlayerAid","yieldBaseTaskForNeed",
   "yieldInventoryCleanupForNeed","yieldAidForNeed","yieldCollectionForNeed"}) do c[name]=function() return false end end
  c.applyPendingCombatPolicy=function() return true end
  c.bridge={cancelNpcMove=function() end}
  people[id]=c;assert(R.register(id,c));return c
 end
 local a=controller("meal-one",0);local b=controller("meal-two",2)
 return a,b
end
local function nativeDone(c)
 local q=queueFor(c.character);local action=q.queue[1]
 assert(action,"a real native action was queued")
 q.current=action
 if not action.srcContainer and action.start then action:start() end
 local result
 if action.srcContainer then action:transferItem(action.item);result=true
 else result=action:complete() end
 q:removeFromQueue(action);q.current=nil
 return action,result
end
local function sitBoth(a,b)
 nativeDone(a);nativeDone(b)
 assert(a.character.seated and b.character.seated,"actual sit posture is established")
 a:tick(2);b:tick(2)
 assert(a.state=="TIMED_ACTION" and b.state=="TIMED_ACTION","both native eating owners start after seating")
end
local a,b=pair()
assert(a:beginSharedMeal(0),"safe compatible pair begins")
assert(a.sharedMeal and b.sharedMealOwner==a and not b.sharedMeal,"one ephemeral plan and peer reference")
a:tick(1);assert(a.state=="BASE_AMBIENT_REST" and a.pendingSelfCare==nil,"queued sitting is not posture receipt")
sitBoth(a,b)
local plan=a.sharedMeal;local firstIntent=a.selfCareIntent
local action,result=nativeDone(a)
assert(result and N.verify(a.character,firstIntent),"real food and hunger change produce first receipt")
a:tick(3)
assert(plan.first.received and not plan.second.received and spoken==0,"first receipt waits for peer")
assert(a:completeSharedMeal(3,false,firstIntent) and a.sharedMeal==plan,"duplicate completion cannot cancel or double count")
local secondIntent=b.selfCareIntent
nativeDone(b);assert(N.verify(b.character,secondIntent),"second real native receipt")
b:tick(4)
assert(spoken==2 and a.sharedMeal==nil and b.sharedMealOwner==nil,"both verified meals produce one exchange")
assert(not a.character.seated and not b.character.seated and a.state=="IDLE" and b.state=="IDLE","owned posture released")
assert(not a:completeSharedMeal(5,true,firstIntent) and spoken==2,"stale callback cannot repeat dialogue")
assert(a.character.hunger<0.35 and b.character.hunger<0.35,"both actual hunger values fall")
local claimed=0;for _,value in pairs(a.reservations.items) do claimed=claimed+1 end
assert(claimed==0,"food reservations are released")
a,b=pair();b.character.inv.items={};assert(not a:beginSharedMeal(0) and not a.sharedMeal,"no food refuses without invented supplies")
a,b=pair();a.character.inv.items[1].rotten=true;assert(not a:beginSharedMeal(0),"unsafe food refuses")
a,b=pair();a.reservations.items[a.character.inv.items[1]]="other";assert(not a:beginSharedMeal(0),"other food owner is respected")
a,b=pair();b.assignment="work";assert(not a:beginSharedMeal(0),"scheduled work is not stolen")
a,b=pair();b.character.sickness=1;assert(not a:beginSharedMeal(0),"sickness refuses")
a,b=pair();b.character.fatigue=0.9;assert(not a:beginSharedMeal(0),"sleep need refuses")
a,b=pair();b.character.square.x=5;assert(not a:beginSharedMeal(0),"distant partner gets no rendezvous")
a,b=pair();seatReject=b.character;assert(not a:beginSharedMeal(0),"second native seat refusal aborts pair")
assert(not a.sharedMeal and not b.sharedMealOwner and #queueFor(a.character).queue==0,"first seat action retired after second refusal")
a,b=pair();seatReentry=a.character;assert(not a:beginSharedMeal(0),"reentrant seat cancellation closes plan")
assert(#queueFor(a.character).queue==0 and not b.sharedMealOwner and a.state=="IDLE","reentrant cancellation leaves no owned action")
a,b=pair();assert(a:beginSharedMeal(0));nativeDone(a);queueFor(b.character).queue={};b:tick(1)
assert(not a.sharedMeal and not b.sharedMealOwner and spoken==0,"seat action without real posture fails closed")
a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b);b.character.noConsumption=true
nativeDone(a);a:tick(3);nativeDone(b);b:tick(4)
assert(not a.sharedMeal and spoken==0 and a.character.hunger<0.35 and b.character.hunger==0.35,"one real meal cannot invent shared receipt or roll food back")
a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b)
local oldEat=a.pendingSelfCare.action;b.combatTarget={};a:checkSharedMeal(3)
assert(not a.sharedMeal and not b.sharedMealOwner and not oldEat:complete() and spoken==0,"danger cancels exact consumption permission")
a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b);b.character.square.x=8;a:checkSharedMeal(3)
assert(not a.sharedMeal and spoken==0,"moved peer cancels without speech")
a,b=pair();assert(a:beginSharedMeal(0));b.character.dead=true;a:checkSharedMeal(1)
assert(not a.sharedMeal,"peer death cancels")
a,b=pair();assert(a:beginSharedMeal(0));R.unregister(b.id,b);a:checkSharedMeal(1)
assert(not a.sharedMeal,"lost runtime identity cancels")
a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b)
local oldBody=b.character;local oldFood=oldBody.inv.items[1]
local newBody=actor("meal-newbody",1);local newAction={}
b.character=newBody;queueFor(newBody).queue={newAction}
a:checkSharedMeal(3)
assert(not a.sharedMeal and not b.sharedMealOwner and a.reservations.items[oldFood]==nil
 and queueFor(newBody).queue[1]==newAction,"body replacement releases old meal claim and preserves new body work")
a,b=pair();assert(a:beginSharedMeal(0));a:checkSharedMeal(1800)
assert(not a.sharedMeal,"exact timeout releases both")
a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b)
local unrelated={forceCancel=function() error("unrelated cancellation") end}
local q=queueFor(a.character);q.current=unrelated;q.queue[#q.queue+1]=unrelated
a:checkSharedMeal(3)
assert(#q.queue==1 and q.queue[1]==unrelated,"foreign native work survives exact owned cancellation")
a,b=pair();assert(a:beginSharedMeal(0))
local staleSeat=a.sharedMeal.first.seatAction
q=queueFor(a.character);q.current=unrelated;q.queue[#q.queue+1]=unrelated
a:checkSharedMeal(1)
assert(not staleSeat:start() and not a.character.seated and q.queue[1]==unrelated,
 "a canceled not-yet-started seat cannot sit later or cancel another owner")
for _,reaction in ipairs({"knockdown","getup","hitreaction"}) do
 a,b=pair();assert(a:beginSharedMeal(0));sitBoth(a,b)
 if reaction=="knockdown" then b.character.down=true
 elseif reaction=="getup" then b.character.getCurrentStateName=function() return "PlayerGetUpState" end
 else b.character.getCurrentActionContextStateName=function() return "hitreaction" end end
 assert(b.character.seated and not b:sharedMealPostureReady(),"seated flag cannot bypass native "..reaction)
 a:checkSharedMeal(3)
 assert(not a.sharedMeal and spoken==0,"native "..reaction.." interrupts shared meal")
end
a,b=pair();assert(a:beginSharedMeal(0));a:interruptForDirective(true)
assert(not a.sharedMeal and not b.sharedMealOwner and spoken==0,"new directive releases pair")
-- Retrieval is the existing guarded self-care action, not a food receipt.
a,b=pair();local itemA=bagFood(a);assert(a:beginSharedMeal(0), "bagged food starts shared meal");sitBoth(a,b)
assert(a.selfCareIntent.kind=="prepare_supply" and b.selfCareIntent.kind=="eat", "one bag queues native retrieval")
local bagPlan=a.sharedMeal;local prepareIntent=a.selfCareIntent;nativeDone(a);a:tick(3)
assert(a.sharedMeal==bagPlan and not bagPlan.first.received and spoken==0
 and itemA:getContainer()==a.character.inv and a.activeDecision=="base_shared_meal", "retrieval is not consumption")
assert(a:completeSharedMeal(3,true,prepareIntent) and a.sharedMeal==bagPlan
 and not bagPlan.first.received and spoken==0 and #queueFor(a.character).queue==0,
 "duplicate prepare receipt does not restart transfer")
a:tick(4);assert(a.selfCareIntent.kind=="eat", "retrieved exact item starts eat")
local eatAction=a.pendingSelfCare.action
assert(a:completeSharedMeal(4,true,prepareIntent) and a.sharedMeal==bagPlan
 and a.pendingSelfCare.action==eatAction and not bagPlan.first.received and spoken==0,
 "late prepare duplicate preserves eat")
nativeDone(a);a:tick(5);nativeDone(b);b:tick(6)
assert(spoken==2 and not a.sharedMeal, "one bag still requires both real eats")
a,b=pair();bagFood(a);bagFood(b);assert(a:beginSharedMeal(0));sitBoth(a,b)
assert(a.selfCareIntent.kind=="prepare_supply" and b.selfCareIntent.kind=="prepare_supply", "both bags retrieve")
nativeDone(a);a:tick(3);nativeDone(b);b:tick(3);a:tick(4);b:tick(4)
nativeDone(a);a:tick(5);assert(spoken==0, "one meal after both transfers waits")
nativeDone(b);b:tick(6);assert(spoken==2, "both bagged meals require both receipts")
for _,mode in ipairs({"missing","wrong"}) do
 a,b=pair();local item,bag=bagFood(a);food(bag);transferMode=mode
 assert(a:beginSharedMeal(0));sitBoth(a,b);nativeDone(a);a:tick(3)
 assert(not a.sharedMeal and spoken==0 and item:getContainer()==bag, "unreceived exact item closes "..mode)
end
a,b=pair();bagFood(a);assert(a:beginSharedMeal(0));sitBoth(a,b)
local pendingTransfer=a.pendingSelfCare.action;b.combatTarget={};a:checkSharedMeal(3)
assert(not a.sharedMeal and (pendingTransfer:transferItem(pendingTransfer.item)==nil) and spoken==0, "danger revokes bag transfer")
a,b=pair();bagFood(a);assert(a:beginSharedMeal(0));sitBoth(a,b)
local foreign={forceCancel=function() error("foreign transfer work canceled") end}
local transferQueue=queueFor(a.character);transferQueue.queue[#transferQueue.queue+1]=foreign
a:checkSharedMeal(3)
assert(not a.sharedMeal and transferQueue.queue[1]==foreign, "bag cancellation preserves foreign action")
a,b=pair();bagFood(a);assert(a:beginSharedMeal(0));sitBoth(a,b)
a:interruptForDirective(true);assert(not a.sharedMeal and spoken==0, "directive cancels bag transfer")
a,b=pair();local reserved=bagFood(a);a.reservations.items[reserved]="other"
assert(not a:beginSharedMeal(0), "reserved bag food cannot start meal")
a,b=pair();local reentryFood,reentryBag=bagFood(a);transferMode="reentry";assert(a:beginSharedMeal(0))
nativeDone(a);nativeDone(b);a:tick(2)
assert(not a.sharedMeal and not b.sharedMealOwner and spoken==0, "reentrant retrieval cancellation closes pair")
assert(a.pendingSelfCare==nil and #queueFor(a.character).queue==0
 and reentryFood:getContainer()==reentryBag and a.state~="TIMED_ACTION",
 "reentrant admission retires care and keeps food")
for id,c in pairs(people) do R.unregister(id,c) end
ISTimedActionQueue,ISSitOnGround,ISRestAction,ISEatFoodAction=old.Queue,old.Sit,old.Rest,old.Eat
CharacterStat,getCell,KnoxJavaBridge,KnoxCompanionVehicles=old.Stats,old.Cell,old.Bridge,old.Vehicles
KnoxPersistence.getSurvivorDuty,KnoxPersistence.getBaseResidentIds=old.Duty,old.Residents
KnoxBaseManager.containsSquare,KnoxBaseJobs.scheduleAssignment=old.Contains,old.Schedule
KnoxSurvivorDialogue.say=old.Say;isClient=old.Client;ISInventoryTransferAction.transferItem=old.NativeTransfer;ISInventoryTransferAction.forceCancel=old.NativeCancel
print("Shared meal PASS production_controllers=true actual_posture=true both_native_food_receipts=true owned_cleanup=true")
