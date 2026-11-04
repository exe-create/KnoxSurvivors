local C=KnoxAutonomyController
local body={state="IdleState",action="idle",attack=true,clears=0}
function body:getCurrentStateName() return self.state end
function body:getCurrentActionContextStateName() return self.action end
function body:isPerformingAttackAnimation() return self.attack end
function body:getCharacterActions() return {isEmpty=function() return true end} end
function body:setPerformingAttackAnimation(value) self.attack=value end
function body:setPerformingShoveAnimation(value) assert(value==false) end
function body:setPerformingStompAnimation(value) assert(value==false) end
function body:clearHandToHandAttack() self.clears=self.clears+1 end
local c=setmetatable({character=body},C)
assert(not c:recoverIdleAnimationLatch(1) and not c:recoverIdleAnimationLatch(180))
body.state="SwipeStatePlayer";body.action="attack"
assert(not c:recoverIdleAnimationLatch(400) and body.attack,"real graph attack remains owned")
body.state="IdleState";body.action="idle"
assert(not c:recoverIdleAnimationLatch(401))
assert(c:recoverIdleAnimationLatch(581) and not body.attack and body.clears==1,
    "stable idle grace recovers flags which would otherwise starve combat/order ticks")
assert(not c:recoverIdleAnimationLatch(600) and body.clears==1)
print("Idle animation recovery PASS native_graph_preserved=true bounded_grace=true one_cleanup=true")
