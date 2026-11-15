local C=assert(KnoxAutonomyController)
local previousQueue=ISTimedActionQueue
ISTimedActionQueue={getTimedActionQueue=function() return {queue={}} end}
local turns,moving,climbing,attacking=0,false,false,false
local body={getCurrentStateName=function() return climbing and "ClimbOverFenceState" or "IdleState" end,
 getCurrentActionContextStateName=function() return climbing and "climbfence" or "idle" end,
 isClimbing=function() return climbing end,isPlayerMoving=function() return moving end,
 isPerformingAttackAnimation=function() return attacking end,isAttackStarted=function() return attacking end,
 isAttacking=function() return attacking end,isKnockedDown=function() return false end,
 isDead=function() return false end,isAsleep=function() return false end,getVehicle=function() return nil end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,
 isDraggingCorpse=function() return false end,
 faceThisObject=function() turns=turns+1 end}
local c=setmetatable({character=body,state="IDLE"},C)
assert(c:faceForAmbient({}) and turns==1,"idle survivor can face a speaker")
moving=true
local turnedWhileMoving=c:faceForAmbient({})
assert(not turnedWhileMoving and turns==1,"native movement cannot be turned by ambient speech")
moving=false
for _,state in ipairs({"ROAMING","FLEEING","COMBAT","MOVING_TO_BASE_TASK","TIMED_ACTION"}) do
 c.state=state;assert(not c:faceForAmbient({}) and turns==1,"active owner keeps facing: "..state)
end
c.state="IDLE";climbing=true
assert(not c:faceForAmbient({}) and turns==1,"native crossing keeps facing")
climbing=false;attacking=true
assert(not c:faceForAmbient({}) and turns==1,"native attack keeps facing")
attacking=false;c.state="BASE_IDLE"
assert(c:faceForAmbient({}) and turns==2,"stationary base greeting still turns normally")
assert(c:canHibernateForDistance(),"ordinary safe body permits distance handoff")
c.state="COMBAT"
assert(not c:canHibernateForDistance(),"distance handoff cannot retire an active fight")
c.state="IDLE";climbing=true
assert(not c:canHibernateForDistance(),"distance handoff cannot cancel a crossing")
ISTimedActionQueue=previousQueue
print("Ambient facing PASS movement_preserved=true native_owners=true idle_greeting=true")
