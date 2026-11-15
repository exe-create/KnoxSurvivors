-- Eat/drink capacity recovery through the real owner.
-- A bagged meal or bottle that cannot come to hand because the pack is full used
-- to return supply_transfer_rejected forever. The recovery must reach the one
-- existing cleanup owner with the food/water goal, refuse to invent room, and
-- revoke when the need or the base changes.
local C=assert(KnoxAutonomyController)
local N=KnoxSurvivorNeeds
local oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage=
    KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,ISTimedActionQueue,KnoxBaseStorage
local oldExecute,oldDecide,oldSnapshot=N.execute,N.decide,N.snapshot

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
local meal={getContainer=function() return inv end,isFavorite=function() return false end,
    getHungerChange=function() return -0.3 end}
contents[meal]=true
local pawn={getCurrentSquare=function() return square end,getInventory=function() return inv end,
    getCharacterActions=function() return nil end,hasFullInventory=function() return full end}
local base={id="base"}

-- Doubled edges only: the need decision, its action executor, and native/engine.
N.execute=function() return nil,"supply_transfer_rejected" end
N.decide=function() return {kind="eat",state={hunger=0.8}} end
P.getSurvivorDuty=function() return {mode="base",baseId="base"} end
P.getSurvivorAffiliation=function() return {kind="player",ownerId="owner"} end
P.getBase=function() return base end
KnoxBaseManager={containsSquare=function() return true end}
Loot.cleanupPlan=function() return {{item=meal,source=inv,reason="surplus"}},"base_deposit" end
B.findNearbyDeposit=function() return {container=dest,policy={key="shelf"}} end
B.canReceiveItem=function() return true end
local queue={queue={}}
ISTimedActionQueue={queues={[pawn]=queue}}
A.queueTransfer=function(character,selected,src,dst,_,guard)
    local action={character=character,item=selected,srcContainer=src,destContainer=dst}
    action.knoxTransferGuard=guard; queue.queue={action}; return action,"queued"
end

local c=setmetatable({id="eater",baseId="base",base=base,character=pawn,state="IDLE",
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
assert(not c:recoverCapacityForNeed("eat",10),"eat_capacity: a pack with room starts no cleanup")
assert(c.pendingCleanup==nil,"eat_capacity: no cleanup transfer without a full pack")
pawn.hasFullInventory=function() error("unreadable") end
assert(not c:recoverCapacityForNeed("eat",10),"eat_capacity: unreadable capacity is not full")
pawn.hasFullInventory=function() return full end
full=true
assert(not c:recoverCapacityForNeed("smoke",10),"eat_capacity: only eat and drink recover capacity")

-- The real failed retrieval reaches the real cleanup owner with the food goal.
local action,result=c:executeNeedAction({kind="eat",item=meal,state={hunger=0.8}},100)
assert(result=="supply_transfer_rejected","eat_capacity: real retrieval failure is reported")
assert(action==nil,"eat_capacity: no action is invented for a rejected retrieval")
local transfer=c.pendingCleanup
assert(transfer~=nil and transfer.waterCapacity==true and transfer.capacityNeed=="find_food",
    "eat_capacity: full pack hands the failed meal to capacity cleanup")
assert(c.state=="INVENTORY_CLEANUP","eat_capacity: cleanup owns the decision after handoff")
assert(transfer.destination==dest,"eat_capacity: a real nearby owned container is retained")

-- The transfer stays valid only while food still drives it.
assert(transfer.guard(transfer.action,meal),"eat_capacity: carried meal keeps the cleanup")
N.decide=function() return {kind="find_food",state={hunger=0.8}} end
assert(transfer.guard(transfer.action,meal),"eat_capacity: the food goal keeps the cleanup")
N.decide=function() return {kind="find_medical"} end
assert(not transfer.guard(transfer.action,meal),"eat_capacity: medical need revokes the cleanup")
N.decide=function() return {kind="eat",state={hunger=0.8}} end
assert(transfer.guard(transfer.action,meal),"eat_capacity: meal keeps the cleanup again")

-- Leaving the owned base revokes it; a full pack alone is not permission to deposit.
KnoxBaseManager.containsSquare=function() return false end
assert(not transfer.guard(transfer.action,meal),"eat_capacity: leaving the base revokes cleanup")
KnoxBaseManager.containsSquare=function() return true end
assert(transfer.guard(transfer.action,meal),"eat_capacity: at base it is admitted again")

-- A drink maps to the water goal on the same cleanup owner. The eat path above
-- already drove the real owner; this spies on it so the goal is read directly.
c:releaseInventoryCleanup();c.state="IDLE";c.nextCleanupAt=0;c.depositRetryAt={}
local seenDrink=nil
c.beginInventoryCleanup=function(self,ticks,waterCapacity,capacityNeed)
    seenDrink={ticks=ticks,waterCapacity=waterCapacity,capacityNeed=capacityNeed}
    return true
end
assert(c:recoverCapacityForNeed("drink",200),"eat_capacity: full pack recovers for a drink")
assert(seenDrink~=nil and seenDrink.waterCapacity==true and seenDrink.capacityNeed=="find_water",
    "eat_capacity: a drink uses the water goal on the one cleanup owner")
assert(c:recoverCapacityForNeed("smoke",210)==false,"eat_capacity: smoke never recovers capacity")
c.beginInventoryCleanup=nil
c:releaseInventoryCleanup();c.state="IDLE"

-- Restore every method stubbed on a shared real table, then the global names.
A.queueTransfer=oldQueueTransfer
Loot.cleanupPlan=oldCleanupPlan
B.findNearbyDeposit,B.canReceiveItem=oldFindNearby,oldCanReceive
P.getSurvivorDuty,P.getSurvivorAffiliation,P.getBase=oldDuty,oldAffiliation,oldGetBase
N.execute,N.decide,N.snapshot=oldExecute,oldDecide,oldSnapshot
KnoxSurvivorNeeds,KnoxSurvivorLooting,KnoxPersistence,KnoxBaseManager,KnoxInventoryActions,
    ISTimedActionQueue,KnoxBaseStorage=
    oldNeeds,oldLoot,oldPersistence,oldManager,oldActions,oldQueue,oldStorage
print("Eat capacity PASS cleanup_owner=true need_executor_stub=true native_transfer_stub=true")
