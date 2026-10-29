-- One continuous production-controller/persistence journey. Native actors,
-- movement, timed queues and combat admission remain explicit engine doubles.
local p,C=KnoxPersistence,KnoxAutonomyController
local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z end,
        canStand=function() return true end,isBlockedTo=function() return false end,
        isHoppableTo=function() return false end,getRoom=function() end,getBuilding=function() end}
end
local list={size=function() return 0 end,get=function() end}
getCell=function() return {getGridSquare=function(_,x,y,z) return square(x,y,z) end,
    getZombieList=function() return list end} end
local function actor(x)
    local a={x=x,y=203,z=0,visible=true,state="idle",swing=false}
    function a:getCurrentSquare() return square(self.x,self.y,self.z) end
    function a:getX() return self.x end;function a:getY() return self.y end;function a:getZ() return self.z end
    function a:CanSee() return self.visible end
    function a:getCurrentStateName() return self.state end
    function a:getCurrentActionContextStateName() return self.state end
    function a:isPerformingAttackAnimation() return self.swing end
    function a:isDead() return false end;function a:isAsleep() return false end
    function a:isKnockedDown() return self.knockedDown == true end
    function a:getVehicle() end;function a:Say() end
    function a:isSneaking() return false end;function a:isSprinting() return false end
    function a:getForwardDirectionX() return 1 end;function a:getForwardDirectionY() return 0 end
    function a:getPrimaryHandItem() end
    function a:getCharacterActions() return {isEmpty=function() return true end} end
    function a:getBodyDamage() return {getHealth=function() return 91 end,getBodyParts=function() return list end} end
    function a:getStats() return {get=function() return .8 end} end
    return a
end
local body,leader=actor(90),actor(102)
local moves,resets,nativeCombat,recoveryObservations=0,0,false,0
local bridge={cancelNpcMove=function() end,resetNpcCombat=function() resets=resets+1;nativeCombat=false end,
    moveNpcWithPace=function() assert(not body.swing,"movement stole native swing");moves=moves+1;return "MOVE_STARTED" end,
    observeNpcNativeRecovery=function()
        assert(nativeCombat and C.isNativeRecoveryBusy(body),"recovery observation belongs to this same native combat body")
        recoveryObservations=recoveryObservations+1;return "NATIVE_RECOVERY"
    end}
local c=setmetatable({id="codec-person",character=body,bridge=bridge,
    companionOwnerId="codec-owner",companionTarget=leader,companionOrder="follow",
    companionFormationSlot=1,companionPartySize=1,state="IDLE",nextThink=0,nextThreatScan=0,
    nextFormationRefresh=0,formationFailureCount=0,failureReasons={},failedThreats={},groupMembers={},
    counts={failures=0},reservations={threats={},items={},restSpots={}}},C)
ISTimedActionQueue={clear=function() end}
KnoxSettings={allowAutonomousRetreat=function() return true end}
KnoxActivityFeed={speak=function() end}
KnoxSurvivorNeeds={wakeForDanger=function() end}
AdjacentFreeTileFinder={Find=function(sq) return sq end}
assert(c:beginCompanionFollow(1),"journey begins with real Follow arbitration")
local before=moves
-- Engine may expose the native traversal flag before readable state names.
body.state="idle";body.climbing=true
function body:isClimbing() return self.climbing == true end
c:setCompanionOrder("codec-owner",leader,"hold",1)
assert(c.companionOrderInterruptPending and moves==before,"Hold waits for native traversal")
body.climbing=false;body.state="idle";c:tick(2)
assert(c.state=="IDLE" and not c.companionOrderInterruptPending,"landing applies latest order without route competition")
assert(p.setPlayerCompanion("codec-person","codec-owner","follow",12))
c:setCompanionOrder("codec-owner",leader,"follow",1)
assert(c:beginCompanionFollow(3))
body.visible=false;leader.x=9000
assert(c:resolvePlayerPartyAnchor(4):getX()==102,"contact loss cannot reveal hidden leader")
-- The native bridge has admitted an attack and the graph is executing its frames.
nativeCombat=true;c.state="COMBAT";body.swing=true
local resetBefore=resets;before=moves
assert(c:beginFlee(5,{reason="outnumbered",health=91,endurance=.8}))
c:tick(6)
assert(c.pendingFleeAttack and nativeCombat and resets==resetBefore and moves==before,
    "danger cannot reset/move the body before native action release")
body.swing=false;body.knockedDown=true;body.state="PlayerOnGroundState";c:tick(7)
assert(c.pendingFleeAttack and nativeCombat and moves==before and recoveryObservations==1,
    "the same pending retreat must survive a real native recovery owner without consuming a terminal receipt")
body.knockedDown=false;body.state="PlayerGetUpState"
c:setCompanionOrder("codec-owner",leader,"hold",1)
c:setCompanionOrder("codec-owner",leader,"follow",1)
c:tick(8)
assert(c.pendingFleeAttack and c.companionOrderInterruptPending and c.companionOrder=="follow"
    and nativeCombat and moves==before and recoveryObservations==2,
    "get-up retains the latest delivered intent and pending escape after knockdown flags clear")
body.state="idle";c:tick(9)
assert(c.state=="FLEEING" and not nativeCombat and moves==before+1,"one native escape follows release")
assert(not c:retreatIsSafelyClear(false,{nearestDistanceSquared=math.huge},10))
assert(c:retreatIsSafelyClear(false,{nearestDistanceSquared=math.huge},11))
c:finishDecision(12)
assert(c:beginCompanionFollow(13) and c.formationTargetX==102,"recovery resumes known Follow without hidden tracking")
assert(p.getSurvivorDuty("codec-person").order=="follow")
assert(p.getObserverKnowledge("codec-other","codec-person").seen.value.position.x==50,
    "another observer cannot inherit the journey's information")
print("Connected journey PASS follow=true traversal_order=true native_attack_drain=true knockdown_getup=true latest_intent=true retreat=true recovery=true known_contact=true")

-- Continue this same actor/controller through the production save event fixture.
journeyController,journeyBody=c,body
