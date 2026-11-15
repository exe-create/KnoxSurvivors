local C = assert(KnoxAutonomyController)
local oldCell, oldFlags, oldDirections, oldUtils, oldQueue, oldClimb, oldStat = getCell, IsoFlagType, IsoDirections, luautils, ISTimedActionQueue, ISClimbOverFence, CharacterStat
local oldRecovery, oldVehicles = C.isNativeRecoveryBusy, KnoxCompanionVehicles
C.isNativeRecoveryBusy = function() return false end
KnoxCompanionVehicles = nil
local sq = {getX=function() return 0 end, getY=function() return 0 end, getZ=function() return 0 end}
local leaderSquare, memberSquare, playerSquare = {}, {}, {}
local leader = {getCurrentSquare=function() return leaderSquare end}
local member = {getCurrentSquare=function() return memberSquare end}
local player = {getCurrentSquare=function() return playerSquare end}
local cell = {getGridSquare=function() return nil end}
getCell = function() return cell end
local function controller(state)
 local c = setmetatable({id="t1",state=state, observedState=state, stateStartedAt=100, nextThink=math.huge,
 nextThreatScan=math.huge,nextIdleLatchCheck=math.huge,counts={search=0}, groupLeader=leader,regroupMember=member,
 character={getCurrentSquare=function() return sq end, getCharacterActions=function() return nil end,
 getCurrentStateName=function() return "idle" end,getCurrentActionContextStateName=function() return "idle" end},
 bridge={tickNpc=function() return "TICK_FAILED:FAILED_LOCKED_OR_UNUSABLE_WINDOW" end,
 cancelNpcMove=function() end}}, C)
 for _,name in ipairs({"tryBoardFollowVehicle","recoverFromDetached","yieldBaseTaskForNeed","yieldInventoryCleanupForNeed","yieldAidForNeed","yieldCollectionForNeed","hasNeedEscort","refreshFormationFollow","resetMovementRecovery"}) do c[name]=function() return false end end
 c.applyPendingCombatPolicy=function() return true end
 c.resolvePlayerPartyAnchor=function() return player,playerSquare end
 c.beginWindowDetour=function(self,_,resume) self.selected=self.pendingSupply.targetSquare; self.entryDetour={resumeState=resume}; self.state="MOVING_TO_WINDOW_ENTRY"; return true end
 c.recordFailure=function(self,reason) self.failure=reason end
 c.reactToTraversal=function() end
 return c
end
for _,case in ipairs({{"GROUP_FOLLOW",leaderSquare},{"GROUP_REGROUP",memberSquare},{"COMPANION_FOLLOW",playerSquare}}) do
 for _,failure in ipairs({"FAILED_LOCKED_DOOR", "FAILED_BLOCKED_WINDOW", "FAILED_BARRICADED_WINDOW"}) do
 local c=controller(case[1]); c.bridge.tickNpc=function() return "TICK_FAILED:"..failure end; c:tick(100)
 assert(c.state=="MOVING_TO_WINDOW_ENTRY" and c.selected==case[2] and c.entryDetour.resumeState==case[1], "tick recovers correct follow target and resume state: "..case[1]..failure)
 end
end
for _,intent in ipairs({"follow_group","follow_player","party_regrouping","party_catching_up","regroup_last_contact","retrieve_group_member"}) do
 assert(not C.forcedEntryIntentAllows(intent), "follow intent cannot force entry: "..intent)
end
local cap=controller("GROUP_FOLLOW"); cap.beginWindowDetour=nil; cap.pendingSupply={entryAttemptCount=8}; cap.bridge.moveNpc=function() error("cap moved") end
assert(not cap:beginWindowDetour(100,"GROUP_FOLLOW") and cap.pendingSupply.entryAttemptCount==8,"eight attempts refuse without moving")
local resumed=controller("MOVING_TO_WINDOW_ENTRY"); resumed.entryDetour={resumeState="GROUP_REGROUP",object={}}; resumed.pendingSupply={approach=memberSquare}; resumed.bridge.moveNpc=function(_,_,target) assert(target==memberSquare); return "MOVE_STARTED" end
assert(resumed:resumeAfterWindowDetour(100) and resumed.state=="GROUP_REGROUP" and resumed.pendingSupply==nil and resumed.regroupMember==member,"regroup resumes and clears temporary supply")
-- Exercise the production candidate scan against a tiny native-shaped room.
local room, inside, outside = {}, {}, {}
inside.getX=function() return 10 end; inside.getY=function() return 10 end; inside.getZ=function() return 0 end
inside.getRoom=function() return room end
outside.getX=function() return 10 end; outside.getY=function() return 9 end; outside.getZ=function() return 0 end
outside.getRoom=function() return nil end; outside.canStand=function() return true end
room.getSquares=function() return {size=function() return 1 end,get=function() return inside end} end
local door, window
inside.getDoorTo=function() return door end; outside.getDoorTo=function() return door end
inside.getWindowTo=function() return window end; outside.getWindowTo=function() return window end
local origin={getX=function() return 4 end,getY=function() return 4 end,getZ=function() return 0 end}
local function entranceController()
 local c=controller("GROUP_FOLLOW"); c.beginWindowDetour=nil; c.activeDecision="follow_group"; c.pendingSupply={targetSquare=inside,approach=inside}
 c.character.getCurrentSquare=function() return origin end; c.allowNeedDetour=function() return true end
 c.bridge.moveNpc=function(_,_,target) c.moved=target; return "MOVE_STARTED" end
 cell.getGridSquare=function(_,x,y) if x==10 and y==9 then return outside end end
 return c
end
local function object(open,barricaded,locked,climb)
 return {IsOpen=function() return open end,isBarricaded=function() return barricaded end,
 isLocked=function() return locked end,isLockedByKey=function() return false end,
 isSmashed=function() return false end,canClimbThrough=function() return climb end}
end
door=object(true,false,false,true); window=object(true,false,false,true)
local routed=entranceController(); routed.pendingSupply=nil; routed.groupLeader={getCurrentSquare=function() return inside end}
routed.bridge.tickNpc=function() return "TICK_FAILED:FAILED_LOCKED_DOOR" end
routed:tick(100)
assert(routed.state=="MOVING_TO_WINDOW_ENTRY" and routed.entryDetour.kind=="door" and routed.moved==outside,"real tick reaches actual alternate-door selection")
-- Leader observation must be a real adjacent crossing; the existing scorer
-- still validates a preferred opening even when a cheaper door shares its edge.
local oldRuntime=KnoxSurvivorRuntime
local building={};inside.getBuilding=function() return building end;outside.getBuilding=function() return nil end
origin.getBuilding=function() return nil end
local leaderBody={square=outside,getCurrentSquare=function(self) return self.square end}
local leaderController=setmetatable({character=leaderBody},C)
KnoxSurvivorRuntime={idForCharacter=function(body) if body==leaderBody then return "leader" end end,
 getController=function(id) if id=="leader" then return leaderController end end}
door=nil; window=object(true,false,false,true)
leaderController:observeGroupEntry(10)
assert(leaderController.groupUsedEntry==nil,"requested or standing outside is not used entrance")
leaderBody.square=inside;leaderController:observeGroupEntry(11)
assert(leaderController.groupUsedEntry and leaderController.groupUsedEntry.object==window,
 "observed outside to inside crossing records exact window")
door=object(true,false,false,true)
local ambiguousBody={square=outside,getCurrentSquare=function(self) return self.square end}
local ambiguous=setmetatable({character=ambiguousBody,groupUsedEntry={object=window}},C)
ambiguous:observeGroupEntry(10);ambiguousBody.square=inside;ambiguous:observeGroupEntry(11)
assert(ambiguous.groupUsedEntry==nil,"ambiguous natural edge records neither opening")
local confirmed=entranceController();confirmed.character=ambiguousBody
confirmed.entryDetour={outside=outside,inside=inside,object=window,kind="window",resumeState="GROUP_FOLLOW"}
confirmed.pendingSupply={approach=inside}
assert(confirmed:resumeAfterWindowDetour(11) and confirmed.groupUsedEntry
 and confirmed.groupUsedEntry.object==window,"confirmed detour landing records exact opening")
local follower=entranceController();follower.pendingSupply=nil;follower.groupLeader=leaderBody
assert(follower:beginPreferredGroupEntry(12) and follower.entryDetour.object==window
 and not follower.entryDetour.force,"used window beats cheaper door on same edge")
local unsafe=entranceController();unsafe.pendingSupply=nil;unsafe.groupLeader=leaderBody
window.canClimbThrough=function() return false end
assert(not unsafe:beginPreferredGroupEntry(12),"unsafe preferred window falls back")
window.canClimbThrough=function() return true end
local forbidden=entranceController();forbidden.pendingSupply=nil;forbidden.groupLeader=leaderBody;forbidden.allowClimbing=false
assert(not forbidden:beginPreferredGroupEntry(12),"climbing restriction rejects preferred window")
local stale=entranceController();stale.pendingSupply=nil;stale.groupLeader=leaderBody
assert(not stale:beginPreferredGroupEntry(912),"stale entrance cannot route follower")
local orderChanged=entranceController();orderChanged.pendingSupply=nil;orderChanged.groupLeader=leaderBody;orderChanged.groupEntryOrderChangedAt=12
assert(not orderChanged:beginPreferredGroupEntry(12),"changed order invalidates older entrance")
local blocked=entranceController();blocked.pendingSupply=nil;blocked.groupLeader=leaderBody
window.isBarricaded=function() return true end
assert(not blocked:beginPreferredGroupEntry(12),"barricaded preferred opening is refused")
window.isBarricaded=function() return false end
local locked=entranceController();locked.pendingSupply=nil;locked.groupLeader=leaderBody
window.IsOpen=function() return false end;window.isLocked=function() return true end
assert(not locked:beginPreferredGroupEntry(12),"preferred locked window is never forced")
window.IsOpen=function() return true end;window.isLocked=function() return false end
local changed=entranceController();changed.pendingSupply=nil;changed.groupLeader=leaderBody
inside.getBuilding=function() return {} end
assert(not changed:beginPreferredGroupEntry(12),"leader goal building change invalidates anchor")
inside.getBuilding=function() return building end
local replaced=entranceController();replaced.pendingSupply=nil;replaced.groupLeader={getCurrentSquare=function() return inside end}
assert(not replaced:beginPreferredGroupEntry(12),"leader identity change invalidates anchor")
KnoxSurvivorRuntime=oldRuntime
local real=entranceController(); assert(real:beginWindowDetour(100,"GROUP_FOLLOW") and real.entryDetour.kind=="door" and real.moved==outside,"real scan prefers usable door")
door=nil; real=entranceController(); assert(real:beginWindowDetour(100,"GROUP_FOLLOW") and real.entryDetour.kind=="window" and real.moved==outside,"real scan admits safe open window")
real.moved=nil
assert(not real:beginWindowDetour(101,"GROUP_FOLLOW") and real.moved==nil,
 "unchanged selected entrance is not retried through a fresh candidate scan")
window.IsOpen=function() return false end
assert(real:beginWindowDetour(102,"GROUP_FOLLOW") and real.moved==outside,
 "real world-state change earns a fresh entrance attempt")
window=object(true,false,false,true)
local combatRoute=entranceController(); combatRoute.combatTarget={}
assert(not combatRoute:beginWindowDetour(100,"GROUP_FOLLOW") and combatRoute.moved==nil,
 "combat after a door failure cannot select a window detour")
door=object(true,false,false,true); combatRoute=entranceController(); combatRoute.combatTarget={}
assert(combatRoute:beginWindowDetour(100,"GROUP_FOLLOW") and combatRoute.entryDetour.kind=="door",
 "combat can still select an ordinary usable door")
door=nil; combatRoute=entranceController()
assert(combatRoute:beginWindowDetour(100,"GROUP_FOLLOW"))
combatRoute.combatTarget={}
combatRoute.bridge.crossNpc=function() error("combat crossing reached native action") end
assert(not combatRoute:crossWindowDetour(101),
 "combat acquired after window selection blocks the native crossing")
window=object(true,false,false,false); real=entranceController(); assert(not real:beginWindowDetour(100,"GROUP_FOLLOW") and real.moved==nil,"real scan refuses unsafe landing")
window=object(true,true,false,true); real=entranceController(); assert(not real:beginWindowDetour(100,"GROUP_FOLLOW"),"real scan refuses barricaded window")
window=object(true,false,false,true); real=entranceController(); real.allowClimbing=false; assert(not real:beginWindowDetour(100,"GROUP_FOLLOW"),"real scan respects climbing denial")
window=object(false,false,false,true); real=entranceController(); real.allowDoorWindowOpening=false; assert(not real:beginWindowDetour(100,"GROUP_FOLLOW"),"real scan respects opening denial")
door=object(false,false,true,true); window=nil; real=entranceController(); assert(not real:beginWindowDetour(100,"GROUP_FOLLOW"),"follow cannot force locked door")
-- Real scan and retry owner: quiet door, two failed windows, then one admitted smash.
local previousBase, previousNeeds, previousInstance = KnoxBaseManager, KnoxSurvivorNeeds, instanceof
local secondInside={getX=function() return 11 end,getY=function() return 10 end,getZ=function() return 0 end,getRoom=function() return room end}
local secondOutside={getX=function() return 11 end,getY=function() return 9 end,getZ=function() return 0 end,getRoom=function() return nil end,canStand=function() return true end}
local firstWindow, secondWindow = object(false,false,true,false), object(false,false,true,false)
local lockedDoor=object(false,false,true,false); lockedDoor.isDoor=true
inside.getDoorTo=function() return lockedDoor end; outside.getDoorTo=function() return lockedDoor end
inside.getWindowTo=function() return firstWindow end; outside.getWindowTo=function() return firstWindow end
secondInside.getDoorTo=function() return nil end; secondOutside.getDoorTo=function() return nil end
secondInside.getWindowTo=function() return secondWindow end; secondOutside.getWindowTo=function() return secondWindow end
room.getSquares=function() return {size=function() return 2 end,get=function(_,i) if i==0 then return inside end return secondInside end} end
KnoxBaseManager={canDamageStructure=function() return true end}
KnoxSurvivorNeeds=setmetatable({snapshot=function() return {endurance=1} end},{__index=previousNeeds})
instanceof=function(obj,kind) return kind=="IsoDoor" and obj.isDoor==true end
local function admitted()
 local c=entranceController(); c.activeDecision="scavenge"; c.character.getPrimaryHandItem=function() return {IsWeapon=function() return true end,isBroken=function() return false end,isRanged=function() return false end} end
 c.releaseBaseTaskSupplyTransfer=function() end
 cell.getGridSquare=function(_,x,y) if x==10 and y==9 then return outside elseif x==11 and y==9 then return secondOutside end end
 return c
end
local sequence=admitted(); assert(sequence:beginWindowDetour(10,"MOVING_TO_SUPPLY") and sequence.entryDetour.object==firstWindow,"quiet window wins over forcing locked door")
assert(sequence:retryWindowDetour(11,"FAILED_LOCKED_OR_UNUSABLE_WINDOW") and sequence.entryDetour.object==secondWindow,"one failed handle selects a different quiet window")
assert(sequence:retryWindowDetour(12,"FAILED_LOCKED_OR_UNUSABLE_WINDOW") and sequence.entryDetour.force and sequence.entryDetour.kind=="window","two real failures allow one forced window")
local priorQueue,priorSmash=ISTimedActionQueue,ISSmashWindow
local smashes=0; ISTimedActionQueue={add=function(action) if action.window then smashes=smashes+1 end end}; ISSmashWindow={new=function(_,_,item) return {window=item} end}
sequence.activeDecision="follow_group"; assert(not sequence:crossWindowDetour(13) and smashes==0,"changed intent refuses destructive action at execution")
sequence.activeDecision="scavenge"; KnoxBaseManager.canDamageStructure=function() return false end
assert(not sequence:crossWindowDetour(14) and smashes==0,"protection changes refuse selected window")
KnoxBaseManager.canDamageStructure=function() return true end
assert(sequence:crossWindowDetour(14) and smashes==1 and sequence.state=="OPENING_ENTRY_WINDOW","admitted scavenge queues native smash for selected window")
ISTimedActionQueue,ISSmashWindow=priorQueue,priorSmash
-- With no usable windows, the exact goal-room locked door is the only break target.
inside.getWindowTo=function() return nil end; outside.getWindowTo=function() return nil end
secondInside.getWindowTo=function() return nil end; secondOutside.getWindowTo=function() return nil end
local doorCase=admitted(); local attacked=nil
doorCase.bridge.beginNpcLockedDoorCombatAt=function(_,_,target) attacked=target; return "COMBAT_STARTED" end
assert(doorCase:beginWindowDetour(30,"MOVING_TO_SUPPLY") and doorCase.entryDetour.object==lockedDoor and doorCase.entryDetour.force,"goal-room locked door is explicitly selected")
doorCase.activeDecision="follow_group"; assert(not doorCase:crossWindowDetour(31) and attacked==nil,"changed intent denies door attack")
doorCase.activeDecision="scavenge"; assert(doorCase:crossWindowDetour(32) and attacked==lockedDoor and doorCase.state=="BREAKING_LOCKED_DOOR","native door combat receives selected object")
local taskCase=admitted(); taskCase.activeDecision="base_task_move"; taskCase.baseTask={type="repair",target={x=10,y=10,z=0}}; taskCase.pendingSupply.taskEntry=true
local taskAttacked=nil; taskCase.bridge.beginNpcLockedDoorCombatAt=function(_,_,target) taskAttacked=target; return "COMBAT_STARTED" end
assert(not taskCase:beginBaseTaskLockedDoorBreak(34) and taskAttacked==nil,"task without selected goal door refuses incidental neighbor")
assert(taskCase:beginWindowDetour(35,"BASE_TASK_MOVE") and taskCase.entryDetour.object==lockedDoor,"task scanner selects goal-room door")
cell.getGridSquare=function(_,x,y) if x==10 and y==10 then return inside elseif x==10 and y==9 then return outside end end
assert(taskCase:crossWindowDetour(36) and taskAttacked==lockedDoor and taskCase.entryDetour.baseTask==true,"base task starts combat against selected door")
inside.getWindowTo=function() return firstWindow end; outside.getWindowTo=function() return firstWindow end
secondInside.getWindowTo=function() return secondWindow end; secondOutside.getWindowTo=function() return secondWindow end
local follow=admitted(); follow.activeDecision="follow_group"; follow:traversalMemoryRecordFailure(firstWindow,"window","locked",inside,outside,1); follow:traversalMemoryRecordFailure(secondWindow,"window","locked",secondInside,secondOutside,2)
assert(not follow:beginWindowDetour(20,"GROUP_FOLLOW"),"ordinary follow cannot smash after failures")
KnoxBaseManager,KnoxSurvivorNeeds,instanceof=previousBase,previousNeeds,previousInstance
inside.getDoorTo=function() return door end; outside.getDoorTo=function() return door end
inside.getWindowTo=function() return window end; outside.getWindowTo=function() return window end
room.getSquares=function() return {size=function() return 1 end,get=function() return inside end} end
cell.getGridSquare=function() return nil end
-- Failed initial route requests must transfer ownership to the detour.
local oldFinder=AdjacentFreeTileFinder
AdjacentFreeTileFinder={Find=function() return outside end}
local function startController()
 local c=controller("IDLE"); c.character.getCurrentSquare=function() return origin end
 c.bridge.moveNpcWithPace=function() return "FAILED_LOCKED_DOOR" end
 c.groupLeader={getCurrentSquare=function() return inside end,getForwardDirectionX=function() return 0 end,getForwardDirectionY=function() return 1 end}
 c.regroupMember=nil
 return c
end
inside.canStand=function() return true end
local start=startController(); assert(start:beginGroupRegroup({getCurrentSquare=function() return inside end},100) and start.state=="MOVING_TO_WINDOW_ENTRY" and start.entryDetour.resumeState=="GROUP_REGROUP" and start.selected==inside,"regroup initial failure owns detour")
start=startController(); start.companionOrder="follow"; start.resolvePlayerPartyAnchor=function() return {getCurrentSquare=function() return inside end},inside end; start.findPlayerPartyFormationTarget=function() return outside,false end
assert(start:beginCompanionFollow(100) and start.state=="MOVING_TO_WINDOW_ENTRY" and start.entryDetour.resumeState=="COMPANION_FOLLOW","companion initial failure owns detour")
cell.getGridSquare=function() return inside end
local formationTile={getX=function() return 9 end,getY=function() return 9 end,getZ=function() return 0 end,getRoom=function() return room end,canStand=function() return true end}
cell.getGridSquare=function() return formationTile end
start=startController(); assert(start:beginGroupFollow(100) and start.state=="MOVING_TO_WINDOW_ENTRY" and start.entryDetour.resumeState=="GROUP_FOLLOW","group initial failure owns detour")
AdjacentFreeTileFinder=oldFinder; cell.getGridSquare=function() return nil end
-- Drive both actual movement dispatch branches to their common entrance owner.
for _,taskType in ipairs({"guard","repair"}) do
 local dispatched=controller("BASE_TASK_MOVE"); dispatched.baseTask={type=taskType,state="claimed",claimedBy="t1"}; dispatched.activeDecision="base_task_move"
 dispatched.bridge.tickNpc=function() return "TICK_FAILED:FAILED_LOCKED_DOOR" end
 dispatched.beginBaseTaskWindowDetour=function(self) self.routed=true; self.state="MOVING_TO_WINDOW_ENTRY"; return true end
 dispatched.deferSecurityRoute=function() error("entry dispatch was skipped") end
 dispatched:tick(100)
 assert(dispatched.routed and dispatched.state=="MOVING_TO_WINDOW_ENTRY","locked "..taskType.." task dispatches to entry owner")
end
local homeRoute=controller("BASE_RETURN"); homeRoute.activeDecision="return_to_base"; homeRoute.ambientMovementSquare=inside
homeRoute.bridge.tickNpc=function() return "TICK_FAILED:FAILED_LOCKED_DOOR" end
homeRoute:tick(100)
assert(homeRoute.state=="MOVING_TO_WINDOW_ENTRY" and homeRoute.selected==inside and homeRoute.entryDetour.resumeState=="BASE_RETURN","base return scans the real route destination")
-- Production follow requests: a reached tile followed by a small shifted slot
-- must not send a visible follower straight back during the same commitment.
local function tile(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end,getRoom=function() return nil end,getBuilding=function() return nil end} end
local pos, routeTarget, visible = tile(0), tile(4), true
local anchorSquare=tile(8); local movingAnchor={getCurrentSquare=function() return anchorSquare end}
local route=controller("IDLE"); route.companionOrder="follow"; route.companionTarget=movingAnchor
route.character.getCurrentSquare=function() return pos end; route.character.CanSee=function() return visible end
route.resolvePlayerPartyAnchor=function() return movingAnchor,anchorSquare end
route.findPlayerPartyFormationTarget=function() return routeTarget,false end
local requests,cancels=0,0; route.bridge.moveNpcWithPace=function() requests=requests+1; return "MOVE_STARTED" end
route.bridge.cancelNpcMove=function() cancels=cancels+1 end
assert(route:beginCompanionFollow(100) and requests==1,"initial production route starts")
pos=tile(4); routeTarget=tile(3); route.nextFormationRefresh=0
assert(not route:refreshFormationFollow(110) and cancels==0 and requests==1,"arrival refresh retains committed route for reverse slot")
route.bridge.tickNpc=function() return "Succeeded" end; route.nextFormationRefresh=999
route:tick(111); assert(route.state=="COMPANION_WAIT","production tick observes route completion")
assert(not route:beginCompanionFollow(112) and requests==1,"post-success opposite request held inside commitment")
visible=false; assert(route:beginCompanionFollow(113) and requests==2,"lost sight releases continuity")
-- Re-establish an eastbound route for each real invalidation and expiry.
local function eastbound(at)
 pos=tile(0); routeTarget=tile(4); visible=true; route.formationRouteContinuity=nil; route.state="IDLE"; route.companionOrder="follow"
 assert(route:beginCompanionFollow(at)); pos=tile(4); routeTarget=tile(3)
end
pos=tile(0); routeTarget=tile(4); movingAnchor.getForwardDirectionX=function() return 1 end; movingAnchor.getForwardDirectionY=function() return 0 end
local group=controller("IDLE"); group.groupLeader=movingAnchor; group.character.getCurrentSquare=function() return pos end; group.character.CanSee=function() return true end
local groupRequests=0; group.bridge.moveNpcWithPace=function() groupRequests=groupRequests+1; return "MOVE_STARTED" end
cell.getGridSquare=function() return routeTarget end; routeTarget.canStand=function() return true end
assert(group:beginGroupFollow(200),"group route begins"); pos=tile(4); routeTarget=tile(3); routeTarget.canStand=function() return true end
assert(not group:beginGroupFollow(201) and groupRequests==1,"group reverse is held")
group:setGroupLeaderOrder({kind="follow",revision=2,leaderId="leader"})
assert(group:beginGroupFollow(202) and groupRequests==2,"changed group order releases continuity")
cell.getGridSquare=function() return nil end
eastbound(300); route.character.getCurrentStateName=function() return "idle" end
route:handleFormationMovementFailure("TICK_FAILED:route_stalled",301)
assert(route.formationRouteContinuity==nil,"movement failure releases continuity")
route.state="IDLE"; assert(route:beginCompanionFollow(302),"failed movement can request replacement")
eastbound(400); pos=tile(4,1); routeTarget=tile(3,1)
assert(route:beginCompanionFollow(401),"floor change releases continuity")
eastbound(500); assert(route:beginCompanionFollow(500+C.TUNING.FORMATION_ROUTE_COMMIT_TICKS),"commitment expiry releases continuity")
local combat=controller("GROUP_FOLLOW"); combat.combatTarget={}; local combatOwned=combat:handleFormationMovementFailure("FAILED_LOCKED_OR_UNUSABLE_WINDOW",100)
assert(combatOwned and combat.activeDecision=="holding_at_window" and combat.selected==nil,"combat holds rather than entering window")
local busy=controller("GROUP_REGROUP"); busy.character.isClimbing=function() return true end; local busyOwned=busy:handleFormationMovementFailure("FAILED_LOCKED_OR_UNUSABLE_WINDOW",100)
assert(busyOwned and busy.state=="GROUP_REGROUP" and busy.regroupMember==member and busy.selected==nil and busy.failure==nil,"native climbing retains ownership")
local blocked=controller("GROUP_FOLLOW")
blocked.recordFailure=nil; blocked.nextThink=0; blocked.nextFormationRefresh=0
blocked:handleFormationMovementFailure("TICK_FAILED:route_stalled",100)
assert(blocked.state=="GROUP_WAIT" and blocked.counts.failures==1
 and blocked.lastFailure.reason=="formation_movement:TICK_FAILED"
 and blocked.nextThink==100+C.TUNING.FORMATION_FAILURE_COOLDOWN_TICKS
 and blocked.nextFormationRefresh==blocked.nextThink,
 "unrecoverable movement keeps the real failure cooldown and formation deadline")
local fence={isTallHoppable=function() return false end, getSprite=function() return {getProperties=function() return {has=function(_,flag) return flag=="N" end} end} end}
local edge={has=function(_,flag) return flag=="N" end,getX=function() return 0 end,getY=function() return -1 end,getObjects=function() return {size=function() return 1 end,get=function() return fence end} end}
cell.getGridSquare=function(_,x,y) if x==0 and y==-1 then return edge end end
IsoFlagType={HoppableN="N",HoppableW="W"}; IsoDirections={N="N",S="S",E="E",W="W"}; CharacterStat={FATIGUE="fatigue"}
local actions={}; ISTimedActionQueue={queues={},add=function(action) actions[#actions+1]=action end}; ISClimbOverFence={new=function(_,_,item,direction) return {item=item,direction=direction} end}
local decoy={isTallHoppable=function() return false end,getSprite=function() return {getProperties=function() return {has=function() return false end} end} end}
sq.getObjects=function() return {size=function() return 2 end,get=function(_,i) if i==0 then return decoy end return fence end} end
local goal={getX=function() return 0 end,getY=function() return -5 end,getZ=function() return 0 end}
local adjacent=false; luautils={walkAdjFence=function() return adjacent end}
local f=controller("GROUP_FOLLOW"); f.character.getX=function() return 0 end; f.character.getY=function() return 0 end
f.character.getHealth=function() return 100 end; f.character.getStats=function() return {get=function() return 0 end} end
assert(not f:hopNearestFence(100,goal) and #actions==0 and f.fenceHopAt==nil,"failed adjacency cannot queue climb or consume cooldown")
adjacent=true; assert(f:hopNearestFence(101,goal) and #actions==1 and f.fenceHopAt==101 and actions[1].item==fence and actions[1].direction=="N","successful adjacency queues the goal-facing fence")
assert(not f:hopNearestFence(102,goal) and #actions==1,"cooldown prevents duplicate climb")
f.fenceHopAt=nil; assert(not f:hopNearestFence(199,{getX=function() return 5 end,getY=function() return 0 end,getZ=function() return 0 end}) and #actions==1,"unrelated fence is not selected"); f.allowClimbing=false; assert(not f:hopNearestFence(200,goal) and #actions==1,"closed climbing prevents action")
f.allowClimbing=true; adjacent=false; luautils.walkAdjFence=function() error("failed") end
assert(not f:hopNearestFence(201,goal) and #actions==1 and f.fenceHopAt==nil,"adjacency exception cannot queue or cool down")
luautils.walkAdjFence=function() return true end
f.character.getHealth=function() return 10 end
assert(not f:hopNearestFence(202,goal) and #actions==1,"injury blocks fence action")
f.character.getHealth=function() return 100 end; fence.isTallHoppable=function() return true end
f.character.getStats=function() return {get=function() return 1 end} end
assert(not f:hopNearestFence(203,goal) and #actions==1,"fatigue blocks tall fence action")
-- All four edges: north/west live on the origin, south/east on the next square.
local orient="N"
local realFence={isTallHoppable=function() return false end,getSprite=function() return {getProperties=function() return {has=function(_,flag) return flag==orient end} end} end}
local function objects() return {size=function() return 2 end,get=function(_,i) if i==0 then return decoy end return realFence end} end
local selectedSquare
sq.getObjects=objects
cell.getGridSquare=function(_,x,y,z) selectedSquare={x=x,y=y,z=z,getObjects=objects}; return selectedSquare end
local cases={{0,-3,"N","N",0,0},{-3,0,"W","W",0,0},{0,3,"N","S",0,1},{3,0,"W","E",1,0}}
for _,case in ipairs(cases) do
 orient=case[3]; f.fenceHopAt=nil; f.character.getStats=function() return {get=function() return 0 end} end
 local target={getX=function() return case[1] end,getY=function() return case[2] end,getZ=function() return 0 end}
 assert(f:hopNearestFence(300,target),"goal edge should admit "..case[4])
 assert(actions[#actions].item==realFence and actions[#actions].direction==case[4],"correct object and direction "..case[4])
 if case[5]~=0 or case[6]~=0 then assert(selectedSquare.x==case[5] and selectedSquare.y==case[6],"correct neighbor") end
end
f.fenceHopAt=nil; orient="other"
assert(not f:hopNearestFence(400,goal),"no matching object flag refuses floor decoy")
f.formationTargetX=0; f.formationTargetY=-5; f.formationTargetZ=0
assert(not f:hopNearestFence(401,{getX=function() error("missing") end}),"unreadable explicit goal cannot reuse stale target")
f.formationTargetX=nil; assert(not f:hopNearestFence(402),"unknown goal cannot select a fence")
sq.getObjects=nil
-- Obstacle failures in follow reach the existing door owner (the garage
-- shape one room over); furniture with no door nearby keeps the ordinary
-- cancel-and-retry path, and the bounded retries still escalate.
local oldInstanceofFollow = instanceof
instanceof = function(object, kind)
    return kind == "IsoDoor" and object ~= nil and object.isDoor == true
end
local oldAttackBusyFollow = C.isNativeAttackBusy
C.isNativeAttackBusy = function() return false end
local followDoor = { isDoor = true,
    IsOpen = function() return false end,
    isLocked = function() return false end,
    isLockedByKey = function() return false end,
    isBarricaded = function() return false end }
local followSquare = {
    getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    getObjects = function()
        return { size = function() return 1 end, get = function() return followDoor end }
    end }
local openedFollowDoor = nil
local function followController(state)
    local c = controller(state)
    c.character.getCurrentSquare = function() return followSquare end
    c.bridge.openNpcDoor = function(_, _, which)
        openedFollowDoor = which
        return "OPENING_DOOR"
    end
    return c
end
cell.getGridSquare = function(_, x, y, z)
    if x == 0 and y == 0 and z == 0 then return followSquare end
end
for _, failure in ipairs({ "TICK_FAILED:FailedObstacle",
    "FailedObstacle:FAILED_STATIC_BLOCKAGE", "FailedObstacle:FAILED_BLOCKED_DIAGONAL" }) do
    openedFollowDoor = nil
    local c = followController("GROUP_FOLLOW")
    assert(c:handleFormationMovementFailure(failure, 100) == true,
        "obstacle failure reaches the door owner: " .. failure)
    assert(openedFollowDoor == followDoor,
        "the adjacent shut door is opened: " .. failure)
    assert(c.state == "GROUP_FOLLOW" and c.formationDoorRetry ~= nil
        and c.formationDoorRetry.count == 1,
        "door retry owns the follow without cancelling: " .. failure)
end
local companionFollow = followController("COMPANION_FOLLOW")
openedFollowDoor = nil
assert(companionFollow:handleFormationMovementFailure("TICK_FAILED:FailedObstacle", 100) == true
    and openedFollowDoor == followDoor,
    "companion obstacle failure reaches the door owner")
-- No door nearby: the retry is scheduled but nothing opens, and the
-- ordinary path below is untouched.
cell.getGridSquare = function() return nil end
local stranded = controller("GROUP_FOLLOW")
stranded.bridge.openNpcDoor = function() error("no door to open") end
assert(stranded:handleFormationMovementFailure("TICK_FAILED:FailedObstacle", 100) == true,
    "doorless obstacle schedules its bounded retry")
assert(stranded.state == "GROUP_FOLLOW" and stranded.formationDoorRetry ~= nil
    and stranded.formationDoorRetry.count == 1 and stranded.formationDoorRetry.opened == false,
    "doorless obstacle records the attempt without opening")
-- Exhausted retries still escalate instead of holding the door forever.
local exhausted = followController("GROUP_FOLLOW")
exhausted.formationDoorRetry = { count = 3 }
openedFollowDoor = nil
local released = exhausted:handleFormationMovementFailure("FailedObstacle:FAILED_STATIC_BLOCKAGE", 100)
assert(released ~= true,
    "exhausted retries do not claim the door hold")
assert(exhausted.state == "GROUP_WAIT" and openedFollowDoor == nil
    and exhausted.formationDoorRetry == nil,
    "an entrance that stays shut through the bounded retries escalates")
instanceof = oldInstanceofFollow
C.isNativeAttackBusy = oldAttackBusyFollow
getCell,IsoFlagType,IsoDirections,luautils,ISTimedActionQueue,ISClimbOverFence,CharacterStat=oldCell,oldFlags,oldDirections,oldUtils,oldQueue,oldClimb,oldStat
C.isNativeRecoveryBusy,KnoxCompanionVehicles=oldRecovery,oldVehicles
print("Traversal follow recovery PASS")
