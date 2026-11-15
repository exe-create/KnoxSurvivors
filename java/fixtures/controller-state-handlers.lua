-- Run through the real tick, including its arbitration before state dispatch.
local C = assert(KnoxAutonomyController)
local oldRecovery, oldQueue, oldVehicles = C.isNativeRecoveryBusy, ISTimedActionQueue, KnoxCompanionVehicles
local recovering = false
C.isNativeRecoveryBusy = function() return recovering end
ISTimedActionQueue = { queues = {} }
KnoxCompanionVehicles = nil
local function controller(state)
    local c = setmetatable({ id = "state-fixture", state = state, observedState = state,
        stateStartedAt = 100, nextThink = math.huge, nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge, counts = { search = 0 },
        character = { getCurrentSquare = function() return {} end,
            getCharacterActions = function() return nil end },
        receipts = {}, moves = 0 }, C)
    for _, name in ipairs({ "tryBoardFollowVehicle", "recoverFromDetached",
        "yieldBaseTaskForNeed", "yieldInventoryCleanupForNeed", "yieldAidForNeed",
        "yieldCollectionForNeed", "hasNeedEscort", "refreshFormationFollow", "resetMovementRecovery" }) do
        c[name] = function() return false end
    end
    c.applyPendingCombatPolicy = function() return true end
    c.bridge = { tickNpc = function(_, id)
        assert(id == c.id, "movement keeps the same survivor owner")
        c.moves = c.moves + 1
        return c.movementResult or "MOVE_RUNNING"
    end }
    function c:recordFailure(reason) self.receipts[#self.receipts + 1] = reason end
    function c:releaseSupply() self.receipts[#self.receipts + 1] = "released" end
    function c:finishDecision() self.receipts[#self.receipts + 1] = "finished" end
    return c
end

local movingStates = {
    "MOVING_TO_SUPPLY", "MOVING_TO_EXPLORE", "EVENT_TRAVEL", "MOVING_TO_DEPOSIT",
    "ROAMING", "GROUP_FOLLOW", "GROUP_REGROUP", "COMPANION_FOLLOW",
    "MOVING_TO_COMPANION_POINT", "MOVING_TO_COMPANION_PATROL", "BASE_RETURN", "BASE_PATROL",
    "BASE_DEFEND", "BASE_TASK_MOVE", "BASE_TASK_SUPPLY_MOVE", "ROLE_KIT_MOVE",
    "MEETING_APPROACH", "MOVING_TO_WINDOW_ENTRY", "CROSSING_WINDOW_ENTRY", "MOVING_TO_REST",
    "NIGHT_SHELTER_MOVE", "AID_MOVE", "MOVING_TO_BASE_CANDIDATE", "CAMP_RETURN",
    "CAMP_REPOSITION", "AWAY_RETURN", "FLEEING",
}
for _, state in ipairs(movingStates) do
    local c = controller(state)
    -- Avoid the separate roaming needs check; this fixture controls state completion only.
    c.nextRoamNeedsCheck = math.huge
    c:tick(100)
    assert(c.moves == 1 and c.state == state and #c.receipts == 0,
        "pending movement runs once without completing: " .. state)
end
local unknown = controller("UNRECOGNIZED_FIXTURE_STATE")
unknown:tick(100)
assert(unknown.moves == 0, "an unknown state never reaches native movement")
recovering = true
local paused = controller("MOVING_TO_EXPLORE")
paused:tick(100)
assert(paused.moves == 0, "native recovery pauses ordinary movement")
local shelter = controller("NIGHT_SHELTER_MOVE")
shelter:tick(100)
assert(shelter.moves == 1, "night shelter retains its existing recovery-gate exception")
recovering = false

local arrived = controller("EVENT_TRAVEL")
arrived.movementResult = "Succeeded"
arrived.eventMoveFailures = 2
arrived:tick(100)
assert(arrived.moves == 1 and arrived.eventMoveFailures == 0
    and table.concat(arrived.receipts, ",") == "finished",
    "arrival clears event failures and finishes exactly once")
local failed = controller("EVENT_TRAVEL")
failed.movementResult = "TICK_FAILED:fixture"
function failed:recordMovementFailure() self.receipts[#self.receipts + 1] = "move-failed" end
function failed.bridge:cancelNpcMove() failed.receipts[#failed.receipts + 1] = "cancelled" end
failed:tick(100)
assert(failed.eventMoveFailures == 1
    and table.concat(failed.receipts, ",") == "move-failed,cancelled,finished",
    "failed event travel retains its verdict, cancellation and finish order")
local home = controller("NIGHT_SHELTER_MOVE")
home.movementResult = "Succeeded"
home:tick(100)
assert(home.nextThink == 100 and #home.receipts == 1, "shelter arrival re-decides at this tick")

local searching = controller("SEARCHING")
searching:tick(100)
assert(table.concat(searching.receipts, ",") == "container_search_not_completed,released,finished",
    "an unverified search fails before releasing and finishing")
local away = controller("SEARCHING")
away.pendingSupply = { awayMission = true, searchAction = { knoxSearchCompleted = true } }
away.awayTeamId = "fixture-team"
function away:finishAwayCollection() self.receipts[#self.receipts + 1] = "away-complete" end
away:tick(100)
assert(table.concat(away.receipts, ",") == "away-complete" and away.counts.search == 0,
    "verified away search hands off once without ordinary search aftermath")
-- One empty container must not end a need order. The order owns a three-miss
-- budget, so the search moves to the next container instead of walking away.
local oldClearDirective = KnoxPersistence.clearCompanionDirective
KnoxPersistence.clearCompanionDirective = function() return true end
local chained = controller("SEARCHING")
chained.pendingSupply = { container = {}, searchAction = { knoxSearchCompleted = true } }
chained.companionDirective = { kind = "find_water" }
chained.directiveMisses = 0
chained.nextExplorationSearch = 0
chained.nextWorldSearch = 0
function chained:beginExploration(ticks, directive)
    assert(directive == self.companionDirective, "the same order continues the search")
    self.receipts[#self.receipts + 1] = "explore:" .. tostring(directive.kind)
    self.state = "MOVING_TO_EXPLORE"
    return true
end
chained:tick(100)
assert(table.concat(chained.receipts, ",") == "released,explore:find_water",
    "an empty container hands the order to the next container")
assert(chained.directiveMisses == 1 and chained.companionDirective ~= nil,
    "one empty container spends one miss and keeps the order")
local spent = controller("SEARCHING")
spent.pendingSupply = { container = {}, searchAction = { knoxSearchCompleted = true } }
spent.companionDirective = { kind = "find_water" }
spent.directiveMisses = 2
spent.nextExplorationSearch = 0
function spent:beginExploration()
    self.receipts[#self.receipts + 1] = "unexpected"
    return true
end
spent:tick(100)
assert(spent.companionDirective == nil and spent.directiveMisses == 0,
    "an exhausted order budget still ends the order exactly as before")
KnoxPersistence.clearCompanionDirective = oldClearDirective
assert(C.allowsNeedWaterSource("find_water") and C.allowsNeedWaterSource("find_food")
    and C.allowsNeedWaterSource("find_medical"),
    "a need order may drink at the source it was sent to")
assert(not C.allowsNeedWaterSource("loot_area") and not C.allowsNeedWaterSource("find_tools")
    and not C.allowsNeedWaterSource(nil),
    "base, group and mission orders still block a need water source")
local unreceived = controller("LOOTING")
unreceived.activeDecision = "find_food"
unreceived.selfCareRetryAt = {}
unreceived.inspectedContainers = {}
local failedSource = {}
unreceived.pendingSupply = {container=failedSource,item={}}
function unreceived:collectionItemReceived() return false end
unreceived:tick(100)
assert(table.concat(unreceived.receipts, ",") == "need_supply_transfer_not_completed,released,finished"
    and unreceived.selfCareRetryAt.find_food == 100 + C.TUNING.SELF_CARE_RETRY_TICKS,
    "unreceived food keeps the failure and retry; it cannot become a meal")
assert(unreceived.inspectedContainers[failedSource] == 700,
    "need_source_retry: failed source is cooled down for alternate store")
local failedWater=controller("LOOTING")
failedWater.activeDecision="find_water";failedWater.selfCareRetryAt={};failedWater.inspectedContainers={}
local failedWaterSource={};failedWater.pendingSupply={container=failedWaterSource,item={}}
function failedWater:collectionItemReceived() return false end
failedWater:tick(100)
assert(failedWater.inspectedContainers[failedWaterSource]==700 and failedWater.selfCareRetryAt.find_water==400,
    "failed water pickup cools source and preserves need retry")
local noSource=controller("LOOTING")
noSource.activeDecision="find_food";noSource.selfCareRetryAt={};noSource.inspectedContainers={}
function noSource:collectionItemReceived() return false end
noSource:tick(100)
assert(noSource.selfCareRetryAt.find_food==400,"missing source still yields safely")
-- Actual selector and receipt handoff after the failed-source cooldown.
local oldCell,oldStorage,oldLooting,oldFinder,oldNeeds = getCell,KnoxBaseStorage,KnoxSurvivorLooting,AdjacentFreeTileFinder,KnoxSurvivorNeeds
local origin={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,getRoom=function() return nil end}
local function list(item) return {size=function() return item and 1 or 0 end,get=function() return item end} end
local itemA,itemB={},{}
local sourceA,sourceB=failedSource,{}
local owner=nil
local reads={}
local function setupSource(src,item)
 src.isExistYet=function() return true end
 src.getSourceGrid=function() return origin end
 src.getItems=function() reads[src]=(reads[src] or 0)+1; return list(item) end
 src.contains=function(_,query) return query==item and owner~=query end
 item.getContainer=function() return owner==item and unreceived.character:getInventory() or src end
end
setupSource(sourceA,itemA);setupSource(sourceB,itemB)
assert(unreceived.inspectedContainers[sourceA]==700)
unreceived.blockedAreas={};unreceived.base={};unreceived.baseId="base"
unreceived.reservations={items={}}
unreceived.character.getCurrentSquare=function() return origin end
local inventory={contains=function(_,item) return owner==item end}
unreceived.character.getInventory=function() return inventory end
function unreceived:allowNeedDetour() return true end
getCell=function() return {} end
KnoxSurvivorLooting={canLootSquare=function() return true end}
AdjacentFreeTileFinder={Find=function() return origin end}
KnoxSurvivorNeeds={snapshot=function() return {thirst=0.5} end}
local policies={{storageRole="food",x=0,y=0,z=0},{storageRole="food",x=0,y=0,z=0}}
KnoxBaseStorage={orderedPoliciesByDistance=function() return policies end,
 resolvePolicy=function(p) return {container=p==policies[1] and sourceA or sourceB,square=origin} end,
 hasActiveFilters=function() return false end,filterAllowsItem=function() return true end}
for _,goal in ipairs({"find_food","find_water"}) do
 reads[sourceA],reads[sourceB]=0,0
 local pick=C.findSupplyCandidate(unreceived,goal,400,function() return true end)
 assert(reads[sourceA]==0 and reads[sourceB]==1,"cooled source avoids item read; alternate read once")
 assert(pick and pick.container==sourceB and pick.item==itemB,
    "need_source_retry: alternate real assigned store selected for "..goal)
 local expired=C.findSupplyCandidate(unreceived,goal,700,function() return true end)
 assert(expired and expired.container==sourceA,"failed source reeligible at cooldown expiry")
 unreceived.inspectedContainers[sourceA]=700
end
-- Real movement admission: a failed first source must leave time to try another.
unreceived.inspectedContainers={}; unreceived.reservations={items={},waterSources={}}
unreceived.nextWorldSearch=0; unreceived.nextThink=0
KnoxSurvivorNeeds.isSafeFood=function() return true end
function unreceived:setLifeIntent() end
function unreceived.bridge:moveNpc() return "MOVE_FAILED" end
function unreceived:recordMovementFailure(_,_,ticks,cooldown)
 self.nextThink=math.max(self.nextThink,ticks+cooldown)
end
assert(not unreceived:beginWorldSearch("find_food",100),"first food movement fails")
assert(unreceived.inspectedContainers[sourceA]==700 and unreceived.nextWorldSearch==400
 and unreceived.nextThink==400 and unreceived.reservations.items[itemA]==nil,
 "need_route_retry: failed food source leaves shorter alternate retry")
-- Retry selects B using the actual marker; both rejected sources back off.
assert(not unreceived:beginWorldSearch("find_food",400),"second food movement fails")
assert(unreceived.inspectedContainers[sourceB]==1000 and unreceived.reservations.items[itemB]==nil,
 "alternate food route tries second real store and releases claim")
sourceA.isExistYet=function() return false end;sourceB.isExistYet=function() return false end
assert(not unreceived:beginWorldSearch("find_food",700) and unreceived.lastWorldSearchOutcome=="no_candidate"
    and unreceived.nextWorldSearch==1300,"no usable stores keep no-candidate backoff")
sourceA.isExistYet=function() return true end;sourceB.isExistYet=function() return true end
assert(C.findSupplyCandidate(unreceived,"find_food",1000,function() return true end).container==sourceA,
 "source is eligible again after its existing cooldown")
-- Explicit orders keep their original retry and unrelated deadlines remain.
unreceived.inspectedContainers={};unreceived.nextWorldSearch=0;unreceived.nextThink=900
unreceived.baseSupplyOrder={};unreceived.reservations={items={},waterSources={}}
assert(not unreceived:beginWorldSearch("find_food",100) and unreceived.nextWorldSearch==700
 and unreceived.nextThink==900,"explicit order keeps delay and larger deadline")
unreceived.baseSupplyOrder=nil
for _,order in ipairs({"companionOrder","groupObjective"}) do
 unreceived[order]={};assert(not C.isOrdinaryNeedRoute(unreceived,"find_food"),"explicit group or companion order preserves route policy")
 unreceived[order]=nil
end
unreceived.inspectedContainers={};unreceived.nextWorldSearch=0
assert(not unreceived:beginWorldSearch("find_food",100) and unreceived.nextThink==900,
 "ordinary need preserves unrelated larger deadline")
-- Real water selector scores available objects, then skips the failed object.
local oldManager=KnoxBaseManager
KnoxBaseManager={containsSquare=function() return true end}
local tapA={getSquare=function() return origin end,getContainerCount=function() return 0 end};local tapB={getSquare=function() return origin end,getContainerCount=function() return 0 end}
local waterReads={}
KnoxSurvivorNeeds.waterSourceState=function(source) waterReads[source]=(waterReads[source] or 0)+1
 return {source=source,available=true,tainted=false,amount=source==tapA and 2 or 1} end
KnoxSurvivorNeeds.betterWaterSource=function(a,b) if a==nil or b.amount>a.amount then return b end return a end
origin.getObjects=function() return {size=function() return 2 end,get=function(_,i) return i==0 and tapA or tapB end} end
getCell=function() return {getGridSquare=function(_,x,y,z) if x==0 and y==0 and z==0 then return origin end end} end
policies={};unreceived.inspectedContainers={};unreceived.reservations={items={},waterSources={}}
unreceived.nextWorldSearch=0;unreceived.nextThink=0
assert(not unreceived:beginWorldSearch("find_water",100) and unreceived.inspectedContainers[tapA]==700
 and unreceived.nextWorldSearch==400 and unreceived.reservations.waterSources[tapA]==nil,
 "need_route_retry: failed tap uses existing source cooldown")
assert(not unreceived:beginWorldSearch("find_water",400) and unreceived.inspectedContainers[tapB]==1000,
 "second water retry selects alternate tap")
-- Async movement failure passes through the real state handler.
local async=controller("MOVING_TO_SUPPLY")
async.activeDecision="find_water";async.pendingSupply={waterSource=tapA};async.inspectedContainers={}
async.nextWorldSearch=0;async.nextThink=0;async.movementResult="Failed:fixture"
function async:recordMovementFailure(_,_,ticks,base,maximum)
 self.recordedRetry=base;self.nextThink=math.max(self.nextThink,ticks+base)
 assert(maximum==base,"need movement backoff cap uses existing need cadence")
end
async:tick(100)
assert(async.inspectedContainers[tapA]==700 and async.nextWorldSearch==400
 and async.nextThink==400 and async.recordedRetry==300,
 "async failed water route cools the actual tap and retries alternate")
KnoxBaseManager=oldManager
-- Drive the real receipt predicate and update handoff with actual containment changes.
local received=controller("LOOTING");received.activeDecision="find_food";received.selfCareRetryAt={}
received.inspectedContainers={};received.counts.loot=0;received.pendingSupply={container=sourceB,item=itemB}
received.character=unreceived.character
owner=itemB
function received:reconsiderEquipment() return false end
KnoxSurvivorNeeds.decide=function() return {kind="eat"} end
function received:executeNeedAction(decision) self.receipts[#self.receipts+1]="action:"..decision.kind; return {},"queued",{kind=decision.kind} end
function received:sayNeedIfGrouped() end
received:tick(400)
assert(table.concat(received.receipts,",")=="released,finished,action:eat" and received.state=="TIMED_ACTION"
 and received.inspectedContainers[sourceB]==nil,
 "verified receipt hands off without cooling successful source")
local waterReceived=controller("LOOTING");waterReceived.activeDecision="find_water";waterReceived.selfCareRetryAt={}
waterReceived.inspectedContainers={};waterReceived.counts.loot=0;waterReceived.pendingSupply={container=sourceB,item=itemB}
waterReceived.character=unreceived.character
function waterReceived:reconsiderEquipment() return false end
KnoxSurvivorNeeds.decide=function() return {kind="drink"} end
function waterReceived:executeNeedAction(decision) self.receipts[#self.receipts+1]="action:"..decision.kind; return {},"queued",{kind=decision.kind} end
function waterReceived:sayNeedIfGrouped() end
waterReceived:tick(400)
assert(table.concat(waterReceived.receipts,",")=="released,finished,action:drink" and waterReceived.state=="TIMED_ACTION"
 and waterReceived.inspectedContainers[sourceB]==nil,"verified water receipt hands off without cooling source")
getCell,KnoxBaseStorage,KnoxSurvivorLooting,AdjacentFreeTileFinder,KnoxSurvivorNeeds=oldCell,oldStorage,oldLooting,oldFinder,oldNeeds
local pending = controller("LOOTING")
ISTimedActionQueue.queues[pending.character] = { queue = { {} } }
pending:tick(100)
assert(#pending.receipts == 0 and pending.moves == 0, "pending loot actions retain ownership")

C.isNativeRecoveryBusy, ISTimedActionQueue, KnoxCompanionVehicles = oldRecovery, oldQueue, oldVehicles
print("Controller state handlers PASS movement_states=27 recovery_boundary=true arrival=true failure=true search_receipt=true loot_receipt=true pending_loot=true")
