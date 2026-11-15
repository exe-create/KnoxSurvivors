local C,p = KnoxAutonomyController,KnoxPersistence
local oldPlayer,oldCorpse,oldQueues,oldJobs = getSpecificPlayer,KnoxBaseCorpseHandling,ISTimedActionQueue,KnoxBaseJobs
getSpecificPlayer=function() return nil end
KnoxBaseCorpseHandling={isDragging=function() return false end}
local body=journeyBody
local oldVisible=body.visible
body.visible=true
local player=setmetatable({x=body.x+1,y=body.y,z=body.z,state="idle"},{__index=body})
local clears=0
ISTimedActionQueue={queues={},clear=function(actor)
    clears=clears+1;ISTimedActionQueue.queues[actor].queue={}
end}
local completed=0
local function worker(kind,state)
    local id="working-"..kind
    return setmetatable({id=id,character=body,baseId="work-base",base={settings={}},state=state,
        baseTask={type=kind,state="claimed",claimedBy=id},currentTicks=20,
        groupMembers={},failedThreats={},reservations={items={},threats={},restSpots={}},
        bridge={cancelNpcMove=function() end},releaseAid=function() end,releaseSupply=function() end,
        releaseWatch=function() end,releaseLights=function() end,leaveRecoveryPosture=function() end,
        tradeNeedsSelfCare=function() return false end,
        finishBaseTask=function(self,ok)
            assert(ok==true);completed=completed+1;self.baseTask=nil;return true
        end},C)
end
local kinds={"guard","patrol","cook","barricade","repair","farm_water","farm_harvest",
    "farm_plow","farm_seed","chop_tree","saw_logs","haul_corpse","burn_corpse"}
local priorDuty,priorCapabilities=p.getSurvivorDuty,p.getSurvivorCapabilities
p.getSurvivorDuty=function() return {mode="base",baseId="work-base",jobPreference="auto"} end
p.getSurvivorCapabilities=function() return {} end
KnoxBaseJobs={scheduleAssignment=function() return "anything" end}
for _,kind in ipairs(kinds) do
    local c=worker(kind,kind=="cook" and "BASE_COOKING" or "BASE_TASK_ACTION")
    local task=c.baseTask
    ISTimedActionQueue.queues[body]={queue={{kind=kind}}}
    assert(c:beginPlayerConversation(player),"Talk must pause "..kind)
    assert(c.baseTask==task and task.state=="claimed" and task.claimedBy==c.id)
    assert(#ISTimedActionQueue.queues[body].queue==0,"old native work cannot continue behind dialogue")
    assert(c:endPlayerConversation(player) and c.state=="IDLE")
    local resumed=0
    c.beginBaseTaskSupplyOrWork=function(self)
        assert(self.baseTask==task);resumed=resumed+1;return true
    end
    assert(c:beginBaseTask(21) and resumed==1,"normal work owner resumes same "..kind.." claim")
    local offer={npc=body,giving={},taking={},browsing=true}
    assert(c:beginTrade(offer),"Trade must also pause "..kind)
    assert(c:releaseTrade(offer) and c.baseTask==task)
end
assert(clears==#kinds,"one cancellation per queued work action")

local stale=worker("guard","BASE_SECURITY_WAIT")
local reassigned=stale.baseTask
reassigned.claimedBy="new-worker"
assert(stale:beginPlayerConversation(player) and stale.baseTask==nil,
    "stale task pointer must not make a visible survivor unresponsive")
assert(reassigned.state=="claimed" and reassigned.claimedBy=="new-worker",
    "interaction cannot release another worker's canonical claim")

local repair=worker("repair","BASE_TASK_ACTION")
local oldRepairs=KnoxBaseRepairs
KnoxBaseRepairs={isComplete=function() return true end}
repair.baseTaskActionQueued=true;repair.baseTaskRepairTarget={};repair.baseTaskRepairBefore={}
assert(repair:beginPlayerConversation(player) and completed==1 and repair.baseTask==nil,
    "already completed native repair must be credited once before pausing")
assert(repair:beginPlayerConversation(player) and completed==1,"lease refresh cannot credit repair again")
KnoxBaseRepairs=oldRepairs

local crossing=worker("barricade","BASE_TASK_MOVE")
body.climbing=true
local admitted,reason=crossing:beginPlayerConversation(player)
assert(not admitted and reason=="work_step_finishing" and crossing.baseTask.state=="claimed")
body.climbing=false
assert(crossing:beginPlayerConversation(player),"request works when native crossing releases body")
crossing:endPlayerConversation(player)
crossing.state="COMBAT"
assert(not crossing:beginPlayerConversation(player),"a retained job must not let dialogue steal combat")

local conversation=worker("repair","BASE_TASK_ACTION")
assert(conversation:beginPlayerConversation(player))
conversation.baseTask=nil
ISTimedActionQueue.queues[body]={queue={{kind="equip-from-inventory"}}}
local countBefore=clears
assert(conversation:beginPlayerConversation(player) and clears==countBefore,
    "renewing the same attention lease must not cancel inventory equipment actions")
ISTimedActionQueue.queues[body].queue={}
conversation.tradeNeedsSelfCare=nil
local priorDecide=KnoxSurvivorNeeds.decide
KnoxSurvivorNeeds.decide=function() return {kind="find_food"} end
conversation:updatePlayerConversation(30)
assert(conversation.state=="PLAYER_CONVERSATION","missing food is a reason to ask for help, not close Talk")
KnoxSurvivorNeeds.decide=function() return {kind="eat"} end
conversation:updatePlayerConversation(100)
assert(conversation.state=="IDLE","available urgent self-care still preempts attention")
KnoxSurvivorNeeds.decide=priorDecide

-- A pack is a loot pane, not a conversation: needs must not close it and cancel
-- the transfer the player is in the middle of. Default talk keeps the rule above.
local packing=worker("repair","BASE_TASK_ACTION")
assert(packing:beginPlayerConversation(player,{managePack=true}),
    "pack management takes the same attention lease")
assert(packing.playerConversation.managePack==true,"the lease records gear management")
packing.tradeNeedsSelfCare=function() return true end
KnoxSurvivorNeeds.decide=function() return {kind="eat"} end
packing:updatePlayerConversation(300)
assert(packing.state=="PLAYER_CONVERSATION",
    "an open pack outlives the self-care decision that ends Talk")
packing:updatePlayerConversation(3000)
assert(packing.state=="IDLE","the pack lease still expires on its own clock")
KnoxSurvivorNeeds.decide=priorDecide
assert(packing:beginPlayerConversation(player),
    "closing the pack returns the survivor to a normal conversation")
assert(packing.playerConversation.managePack==nil,"normal attention clears gear management")
assert(packing:endPlayerConversation(player))

body.visible=oldVisible
p.getSurvivorDuty,p.getSurvivorCapabilities=priorDuty,priorCapabilities
getSpecificPlayer,KnoxBaseCorpseHandling,ISTimedActionQueue,KnoxBaseJobs=oldPlayer,oldCorpse,oldQueues,oldJobs
print("All-work interactions PASS kinds=13 talk_trade_resume=true native_queue_retired=true physical_receipt_once=true crossing_preserved=true")
