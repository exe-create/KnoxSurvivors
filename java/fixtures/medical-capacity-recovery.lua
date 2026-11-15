-- Medical supply capacity recovery through the real owner.
-- A bagged bandage that cannot come to hand because the pack is full used to
-- return supply_transfer_rejected forever. The recovery must reach the one
-- existing cleanup owner with the medical goal, refuse to invent room, and
-- revoke when the need or the base changes.
local C=assert(KnoxAutonomyController)
local N=KnoxSurvivorNeeds
local oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage=
    KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,ISTimedActionQueue,KnoxBaseStorage
local oldExecute,oldDecide=N.execute,N.decide

local Loot=assert(codecWaterLooting)
KnoxSurvivorLooting=Loot
local P=KnoxPersistence
local A=KnoxInventoryActions
local B=KnoxBaseStorage
local oldQueueTransfer,oldCleanupPlan,oldFindNearby,oldCanReceive=
    A.queueTransfer,Loot.cleanupPlan,B.findNearbyDeposit,B.canReceiveItem
local oldDuty,oldAffiliation,oldGetBase=
    P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase

local square={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end}
local contents,stored,full={},{},true
local inv={contains=function(_,item) return contents[item]==true end}
local dest={contains=function(_,item) return stored[item]==true end}
local bandage={getContainer=function() return inv end,isFavorite=function() return false end,
    isCanBandage=function() return true end}
contents[bandage]=true
local pawn={getCurrentSquare=function() return square end,getInventory=function() return inv end,
    getCharacterActions=function() return nil end,hasFullInventory=function() return full end}
local base={id="base"}

-- Doubled edges only: the need decision, its action executor, and native/engine.
N.execute=function() return nil,"supply_transfer_rejected" end
N.decide=function() return {kind="bandage"} end
P.getSurvivorDuty=function() return {mode="base",baseId="base"} end
P.getSurvivorAffiliation=function() return {kind="player",ownerId="owner"} end
P.getBase=function() return base end
KnoxBaseManager={containsSquare=function() return true end}
Loot.cleanupPlan=function() return {{item=bandage,source=inv,reason="surplus"}},"base_deposit" end
B.findNearbyDeposit=function() return {container=dest,policy={key="shelf"}} end
B.canReceiveItem=function() return true end
local queue={queue={}}
ISTimedActionQueue={queues={[pawn]=queue}}
A.queueTransfer=function(character,selected,src,dst,_,guard)
    local action={character=character,item=selected,srcContainer=src,destContainer=dst}
    action.knoxTransferGuard=guard; queue.queue={action}; return action,"queued"
end

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
        and self.reservations.items~=nil then self.reservations.items[self.pendingCleanup.item]=nil end
    self.pendingCleanup=nil
end

-- A pack that is not really full never invents room, and an unreadable reading is
-- not a full pack.
full=false
assert(not c:recoverCapacityForNeed("bandage",10),
    "medical_capacity: a pack with room starts no cleanup")
assert(c.pendingCleanup==nil,"medical_capacity: no cleanup transfer without a full pack")
pawn.hasFullInventory=function() error("unreadable") end
assert(not c:recoverCapacityForNeed("bandage",10),
    "medical_capacity: unreadable capacity is not full")
pawn.hasFullInventory=function() return full end
full=true
assert(not c:recoverCapacityForNeed("smoke",10),
    "medical_capacity: smoke never recovers capacity")

-- The real failed bandage retrieval reaches the real cleanup owner with the
-- medical goal. The cleanup plan and native transfer are labelled doubles.
local action,result=c:executeNeedAction({kind="bandage",item=bandage,bodyPart={}},100)
assert(result=="supply_transfer_rejected","medical_capacity: real retrieval failure is reported")
assert(action==nil,"medical_capacity: no action is invented for a rejected retrieval")
local transfer=c.pendingCleanup
assert(transfer~=nil and transfer.waterCapacity==true and transfer.capacityNeed=="find_medical",
    "medical_capacity: full pack hands the failed bandage to capacity cleanup")
assert(c.state=="INVENTORY_CLEANUP","medical_capacity: cleanup owns the decision after handoff")
assert(transfer.destination==dest,"medical_capacity: a real nearby owned container is retained")

-- The transfer stays valid only while medical care still drives it.
assert(transfer.guard(transfer.action,bandage),"medical_capacity: carried bandage keeps the cleanup")
N.decide=function() return {kind="find_medical"} end
assert(transfer.guard(transfer.action,bandage),"medical_capacity: the medical goal keeps the cleanup")
N.decide=function() return {kind="improvise_medical"} end
assert(transfer.guard(transfer.action,bandage),"medical_capacity: other medical care keeps the cleanup")
N.decide=function() return {kind="find_food"} end
assert(not transfer.guard(transfer.action,bandage),"medical_capacity: food need revokes the cleanup")
N.decide=function() return {kind="find_water"} end
assert(not transfer.guard(transfer.action,bandage),"medical_capacity: water need revokes the cleanup")
N.decide=function() return {kind="bandage"} end
assert(transfer.guard(transfer.action,bandage),"medical_capacity: medical need keeps the cleanup again")

-- Leaving the owned base revokes it; a full pack alone is not permission to deposit.
KnoxBaseManager.containsSquare=function() return false end
assert(not transfer.guard(transfer.action,bandage),
    "medical_capacity: leaving the base revokes cleanup")
KnoxBaseManager.containsSquare=function() return true end
assert(transfer.guard(transfer.action,bandage),
    "medical_capacity: at base it is admitted again")

-- Restore every method stubbed on a shared real table, then the global names.
A.queueTransfer=oldQueueTransfer
Loot.cleanupPlan=oldCleanupPlan
B.findNearbyDeposit,B.canReceiveItem=oldFindNearby,oldCanReceive
P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase=oldDuty,oldAffiliation,oldGetBase
N.execute,N.decide=oldExecute,oldDecide
KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,
    ISTimedActionQueue,KnoxBaseStorage=
    oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage
print("Medical capacity PASS cleanup_owner=true need_executor_stub=true native_transfer_stub=true")
