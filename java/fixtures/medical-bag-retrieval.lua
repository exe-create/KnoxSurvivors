-- Bagged bandage retrieval through the real owner.
-- Needs.decide can choose a bandage found in a bag, but the native bandage
-- action requires main-inventory ownership. The real Needs.execute must use the
-- same prepare_supply transfer as a bagged meal, then the existing controller
-- cleanup owner must receive a full-pack rejection with the medical goal.
local C=assert(KnoxAutonomyController)
local N=KnoxSurvivorNeeds
local Medical=assert(KnoxMedicalActions)
local oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage,oldMedicalActions=
    KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,ISTimedActionQueue,KnoxBaseStorage,KnoxMedicalActions
local oldQueueBandage,oldDecide,oldQueueTransfer=Medical.queueBandage,N.decide,KnoxInventoryActions.queueTransfer

local Loot=assert(codecWaterLooting)
KnoxSurvivorLooting=Loot
local P=KnoxPersistence
local A=KnoxInventoryActions
local B=KnoxBaseStorage
local oldCleanupPlan,oldFindNearby,oldCanReceive=
    Loot.cleanupPlan,B.findNearbyDeposit,B.canReceiveItem
local oldDuty,oldAffiliation,oldGetBase=
    P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase

local function itemList(...)
    local items={...}
    return {size=function() return #items end,get=function(_,index) return items[index+1] end},items
end
local function container(items,parent)
    local c={items=items,parent=parent}
    function c:getItems()
        return {size=function() return #self.items end,
            get=function(_,index) return self.items[index+1] end}
    end
    function c:contains(item)
        for _,candidate in ipairs(self.items) do if candidate==item then return true end end
        return false
    end
    function c:getContainingItem() return self.parent end
    return c
end

local square={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end}
local mainItems,bagItems={},{}
local main=container(mainItems)
local bagStore=container(bagItems,main)
local dest=container({})
local bag={}
function bag:IsInventoryContainer() return true end
function bag:getInventory() return bagStore end
function bag:getContainer() return main end
local bandage={}
function bandage:IsInventoryContainer() return false end
function bandage:isCanBandage() return true end
function bandage:getFullType() return "Base.Bandage" end
function bandage:getContainer() return bagStore end
bagItems[1]=bandage
mainItems[1]=bag
local bodyPart={HasInjury=function() return true end,bandaged=function() return false end}

local full,rejectToMain,transferCalls,bandageCalls=false,false,0,0
local pawn={getCurrentSquare=function() return square end,getInventory=function() return main end,
    getCharacterActions=function() return nil end,hasFullInventory=function() return full end}
local base={id="base"}

-- Doubled native/engine edges only. The real Needs.execute decides whether a
-- bagged bandage reaches the transfer, the real controller owns the cleanup.
local queue={queue={}}
ISTimedActionQueue={queues={[pawn]=queue}}
A.queueTransfer=function(character,item,src,dst,_,guard)
    transferCalls=transferCalls+1
    if dst==main and rejectToMain then return nil,"native_full" end
    local action={character=character,item=item,srcContainer=src,destContainer=dst}
    action.knoxTransferGuard=guard
    queue.queue={action}
    return action,"queued"
end
Medical.queueBandage=function(character,item,part,admit)
    bandageCalls=bandageCalls+1
    local action={character=character,item=item,bodyPart=part}
    if admit~=nil then
        local accepted,refusal=admit(character,action)
        return accepted,refusal or "queued"
    end
    return action,"queued"
end
N.decide=function() return {kind="bandage"} end
P.getSurvivorDuty=function() return {mode="base",baseId="base"} end
P.getSurvivorAffiliation=function() return {kind="player",ownerId="owner"} end
P.getBase=function() return base end
KnoxBaseManager={containsSquare=function() return true end}
Loot.cleanupPlan=function() return {{item=bandage,source=bagStore,reason="surplus"}},"base_deposit" end
B.findNearbyDeposit=function() return {container=dest,policy={key="shelf"}} end
B.canReceiveItem=function() return true end

local c=setmetatable({id="wounded",baseId="base",base=base,character=pawn,state="IDLE",
    nextCleanupAt=0,nextThink=0,selfCareRetryAt={},reservations={items={}},counts={},blockedAreas={}},C)
function c:waitingForTransferActions() return false end
function c:recordFailure() end
function c:releaseSelfCare(plan)
    self.pendingSelfCare=nil
    if plan~=nil and plan.item~=nil and self.reservations.items~=nil then
        self.reservations.items[plan.item]=nil
    end
    if self.state=="TIMED_ACTION" then self.state="IDLE" end
end
function c:releaseInventoryCleanup()
    if self.pendingCleanup~=nil and self.pendingCleanup.item~=nil
        and self.reservations.items~=nil then
        self.reservations.items[self.pendingCleanup.item]=nil
    end
    self.pendingCleanup=nil
end

-- 1. Real Needs.execute: a bagged bandage is transferred first, never handed to
-- a native action that cannot see an item in the bag.
queue.queue={}
local action,result,intent=N.execute(pawn,{kind="bandage",item=bandage,bodyPart=bodyPart,
    state={bleedingParts=1}})
assert(action~=nil and intent~=nil,"medical_bag: bagged bandage starts a real transfer")
assert(intent.kind=="prepare_supply" and intent.needKind=="bandage",
    "medical_bag: bagged bandage rides the existing prepare_supply owner")
assert(intent.bodyPart==bodyPart,"medical_bag: the transfer keeps the treatment body part")
assert(intent.source==bagStore and intent.destination==main,
    "medical_bag: the transfer moves the bagged bandage to the main inventory")
assert(transferCalls==1,"medical_bag: exactly one retrieve transfer is attempted")
assert(bandageCalls==0,"medical_bag: native bandage waits until the item is in hand")

-- 2. Full pack: the real failed transfer reaches the real controller cleanup
-- owner with the medical goal and the same nearby owned container.
queue.queue={}
full=true;rejectToMain=true;bandageCalls=0
local rejected,rejection=c:executeNeedAction({kind="bandage",item=bandage,bodyPart=bodyPart,
    state={bleedingParts=1}},100)
assert(rejected==nil and rejection=="supply_transfer_rejected",
    "medical_bag: a full pack reports the failed retrieval")
local transfer=c.pendingCleanup
assert(transfer~=nil and transfer.waterCapacity==true and transfer.capacityNeed=="find_medical",
    "medical_bag: full pack hands the bagged bandage to capacity cleanup")
assert(c.state=="INVENTORY_CLEANUP","medical_bag: cleanup owns the decision after handoff")
assert(transfer.destination==dest,"medical_bag: a real nearby owned container is retained")

-- 3. Unchanged path: a bandage already in the main inventory still goes straight
-- to the native bandage owner with no transfer call.
c:releaseInventoryCleanup();c.state="IDLE";c.nextCleanupAt=0
mainItems[1]=bandage;bagItems[1]=nil
bandage.getContainer=function() return main end
full=false;rejectToMain=false;transferCalls=0;bandageCalls=0
local direct,directResult=N.execute(pawn,{kind="bandage",item=bandage,bodyPart=bodyPart,
    state={bleedingParts=1}})
assert(direct~=nil and directResult=="queued",
    "medical_bag: a main-inventory bandage still queues the native action")
assert(bandageCalls==1 and transferCalls==0,
    "medical_bag: a main-inventory bandage takes no retrieval transfer")

-- Restore every stubbed method on shared tables, then the global names.
A.queueTransfer=oldQueueTransfer
Medical.queueBandage=oldQueueBandage
Loot.cleanupPlan=oldCleanupPlan
B.findNearbyDeposit,B.canReceiveItem=oldFindNearby,oldCanReceive
P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase=oldDuty,oldAffiliation,oldGetBase
N.decide=oldDecide
KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,
    ISTimedActionQueue,KnoxBaseStorage,KnoxMedicalActions=
    oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage,oldMedicalActions
print("Medical bag PASS real_execute=true cleanup_owner=true native_transfer_stub=true")
