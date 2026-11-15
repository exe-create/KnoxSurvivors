-- Real storage selector -> controller trip -> guarded transfer -> receipt -> real meal decision.
local C, S, N = assert(KnoxAutonomyController), assert(KnoxBaseStorage), assert(KnoxSurvivorNeeds)
local old = {cell=getCell, loot=KnoxSurvivorLooting, finder=AdjacentFreeTileFinder,
    actions=KnoxInventoryActions, queue=ISTimedActionQueue, dialogue=KnoxSurvivorDialogue,
    policies=S.operationalPolicies, resolve=S.resolvePolicy, snapshot=N.snapshot}
local square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,
    getRoom=function() return nil end,getBuilding=function() return nil end}
local base={id="base"}; local owner, full, permit, approach, travel=nil,false,true,true,true
local cleanupAllowed=true
local contents={}
local inv={contains=function(_,item) return owner==item end,
    getItems=function() return {size=function() return owner and 1 or 0 end,get=function() return owner end} end}
local function item(rotten)
    return {IsFood=function() return true end,getHungerChange=function() return -0.3 end,
        getUnhappyChange=function() return 0 end,isRotten=function() return rotten end,
        isPoison=function() return false end,getPoisonPower=function() return 0 end,
        isbDangerousUncooked=function() return false end,isCooked=function() return true end,
        getFluidContainer=function() return nil end,IsInventoryContainer=function() return false end,
        getFullType=function() return "Base.Meal" end,
        getContainer=function(self) return owner==self and inv or contents[self] end}
end
local spoiled, meal, unreadable=item(true),item(false),{IsFood=function() error("unreadable") end}
local stock={spoiled,unreadable,meal}
local box; box={isExistYet=function() return true end,getSourceGrid=function() return square end,
    getParent=function() return nil end,
    getItems=function() return {size=function() return #stock end,get=function(_,i) return stock[i+1] end} end,
    contains=function(_,v) return contents[v]==box and owner~=v end}
contents[spoiled]=box;contents[unreadable]=box;contents[meal]=box
local policy={key="pantry",x=0,y=0,z=0,storageRole="food"};local policies={policy}
S.operationalPolicies=function(b) return b==base and policies or {} end
S.resolvePolicy=function(p) if p.unloaded then return nil end; return {policy=p,square=square,container=box} end
getCell=function() return {} end
KnoxSurvivorLooting={canLootSquare=function() return permit end}
AdjacentFreeTileFinder={Find=function() return approach and square or nil end}
KnoxSurvivorDialogue=nil
local nativeQueue={queue={}}
local actor={getCurrentSquare=function() return square end,getInventory=function() return inv end,
    isDead=function() return false end,getVehicle=function() return nil end,
    hasFullInventory=function() return full end,getCharacterActions=function() return {isEmpty=function() return true end} end}
ISTimedActionQueue={queues={[actor]=nativeQueue}}
KnoxInventoryActions={queueTransfer=function(character,thing,source,destination,duration,guard)
    local action={character=character,item=thing,srcContainer=source,destContainer=destination,knoxTransferGuard=guard}
    nativeQueue.queue={action}; return action,"queued"
end}
N.snapshot=function() return {bleedingParts=0,thirst=0,hunger=1,endurance=1,fatigue=0} end
local c=setmetatable({id="resident",base=base,baseId="base",character=actor,
    reservations={items={},containers={},waterSources={}},inspectedContainers={},blockedAreas={},
    nextWorldSearch=0,nextThink=0,state="IDLE",selfCareRetryAt={}},C)
function c:allowNeedDetour() return true end
function c:setLifeIntent() end
function c:recordMovementFailure() end
function c:recordFailure() end
function c:finishDecision() self.state="IDLE";self.activeDecision=nil end
function c:releaseTransferActions() end
function c:releaseBaseRecreation() end
function c:releaseBaseTaskSupplyTransfer() end
function c:recordSettlementLootReceipt() end
function c:beginInventoryCleanup(_,_,goal) self.cleanupGoal=goal;return cleanupAllowed end
c.bridge={moveNpc=function() return travel and "MOVE_STARTED" or "MOVE_FAILED" end}
assert(N.decide(actor,nil).kind=="find_food","d3b: pantry stock alone never becomes carried food")
local pick=C.findSupplyCandidate(c,"find_food",1)
assert(pick and pick.item==meal and pick.container==box and pick.assignedFood,
    "d3b: real storage selector skips unsafe and unreadable food")
c.reservations.items[meal]="other"
assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: reservation prevents selection")
c.reservations.items[meal]=nil
policy.storageFilterVersion=1;policy.storageFilters={medical=true}
assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: filter refuses food")
policy.storageFilterVersion=nil;policy.storageFilters=nil
policy.unloaded=true;assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: unloaded source refused");policy.unloaded=false
permit=false;assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: foreign or forbidden source refused");permit=true
approach=false;assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: no approach refused");approach=true
c.inspectedContainers[box]=999;assert(C.findSupplyCandidate(c,"find_food",1)==nil,"d3b: failed source cooldown retained");c.inspectedContainers[box]=nil
travel=false;assert(not c:beginWorldSearch("find_food",10),"d3b: failed route not admitted")
assert(c.reservations.items[meal]==nil and owner==nil,"d3b: failed route releases claim and consumes nothing")
c.inspectedContainers={};c.nextWorldSearch=0;travel=true
assert(c:beginWorldSearch("find_food",100),"d3b: movement owns selected physical item")
local pending=c.pendingSupply
assert(pending and pending.item==meal and owner==nil,"d3b: movement is not a transfer receipt")
local admitted=c:queueSupplyCollection(101)
assert(admitted and #nativeQueue.queue==1,"d3b: storage admits one guarded native transfer")
local action=nativeQueue.queue[1]
assert(action.knoxTransferGuard(action,meal),"d3b: live claim permits native transfer")
c.baseId="foreign";assert(not action.knoxTransferGuard(action,meal),"d3b: foreign base revokes transfer");c.baseId="base"
policy.storageFilterVersion=1;policy.storageFilters={medical=true}
assert(not action.knoxTransferGuard(action,meal),"d3b: changed filter revokes transfer")
policy.storageFilterVersion=nil;policy.storageFilters=nil
pending.collectionRetired=true;assert(not action.knoxTransferGuard(action,meal),"d3b: interruption revokes transfer");pending.collectionRetired=nil
assert(not c:collectionItemReceived(pending,meal) and N.decide(actor,nil).kind=="find_food",
    "d3b: no receipt cannot invent a meal")
owner=meal;contents[meal]=nil
assert(c:collectionItemReceived(pending,meal),"d3b: exact physical receipt observed")
local decision=N.decide(actor,nil)
assert(decision.kind=="eat" and decision.item==meal,"d3b: real need re-evaluates carried food")
assert(meal:getHungerChange()==-0.3,"d3b: selection and receipt do not consume food")
-- A carried bag inside a live cupboard need not expose its own world square.
local bagSource; bagSource={getSourceGrid=function() return nil end,getParent=function() return nil end,
    getItems=function() return {size=function() return 1 end,get=function() return meal end} end,
    contains=function(_,v) return v==meal and contents[meal]==bagSource and owner~=meal end}
local bag={IsFood=function() return false end,IsInventoryContainer=function() return true end,
    getInventory=function() return bagSource end}
owner=nil;contents[meal]=bagSource;stock={bag};c.reservations.items={};c.inspectedContainers={}
local nested=C.findSupplyCandidate(c,"find_food",150)
assert(nested and nested.item==meal and nested.container==bagSource,
    "d3b: real selector finds pantry bag without nested world square")
c.pendingSupply=nested;c.activeDecision="find_food";c.state="MOVING_TO_SUPPLY"
c.reservations.items[meal]=c.id;nativeQueue.queue={}
assert(c:queueSupplyCollection(151),"d3b: nested food enters the guarded transfer")
local nestedAction=nativeQueue.queue[1]
assert(nestedAction.knoxTransferGuard(nestedAction,meal),
    "d3b: nested food guard accepts live cupboard containment")
stock={};assert(not nestedAction.knoxTransferGuard(nestedAction,meal),
    "d3b: removing bag from cupboard revokes its pending action")
stock={spoiled,unreadable,meal};owner=nil;contents[meal]=box;nativeQueue.queue={};c.pendingSupply=pick;c.activeDecision="find_food";c.state="MOVING_TO_SUPPLY"
c.reservations.items[meal]=c.id;full=true
local yes,reason=c:queueSupplyCollection(200)
assert(not yes and reason=="inventory_full","d3b: real full-pack read refuses pickup")
c:finishSupplyCollectionRefusal(pick,reason,200)
assert(c.cleanupGoal=="find_food" and owner==nil,"d3b: real recovery owner hands full pack to cleanup")
cleanupAllowed=false;c.cleanupGoal=nil;full=true
assert(not c:recoverCapacityForNeed("eat",202) and c.cleanupGoal=="find_food" and owner==nil,
    "d3b: no owned cleanup destination never creates room or consumes food")
cleanupAllowed=true;c.cleanupGoal=nil;full=false;c:finishSupplyCollectionRefusal(pick,"collection_queue_refused",201)
assert(c.cleanupGoal==nil and owner==nil,"d3b: non-capacity failure does not invent cleanup or consumption")
S.operationalPolicies,S.resolvePolicy=old.policies,old.resolve;N.snapshot=old.snapshot
getCell,KnoxSurvivorLooting,AdjacentFreeTileFinder=old.cell,old.loot,old.finder
KnoxInventoryActions,ISTimedActionQueue,KnoxSurvivorDialogue=old.actions,old.queue,old.dialogue
print("d3b assigned pantry fixture PASS selector=true transfer=true receipt=true meal_decision=true nativeGameplay=false")
