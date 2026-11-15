local T,C=assert(KnoxThreatClassifier),assert(KnoxAutonomyController)
local oldBandit=Bandit
local square={getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end}
local body={getVariableBoolean=function() return true end,getCurrentSquare=function() return square end,
 isDead=function() return false end,isZombie=function() return true end,isReanimatedForGrappleOnly=function() return false end}
Bandit={IsHostile=function() return false end}
assert(T.banditDisposition(body)=="neutral" and T.ignoreForeignNpc(body),"owner-neutral bandit is not ordinary zombie prey")
local control=setmetatable({character={getCurrentSquare=function() return square end},
 perceivedThreats={[body]={}},combatTarget=body},{__index=C})
assert(control:evaluateCombatThreat(body,0)==nil and control.perceivedThreats[body]==nil,
 "real threat acquisition clears a neutral bandit")
assert(control:shouldDropCombatTarget(0),"real target retention drops neutral foreign NPC before attack intent")
Bandit.IsHostile=function() return true end
assert(T.banditDisposition(body)=="hostile" and not T.ignoreForeignNpc(body),"owner-hostile bandits retain ordinary threat admission")
Bandit.IsHostile=function() error("not ready") end
assert(T.ignoreForeignNpc(body),"identified but unreadable foreign ownership prevents accidental aggression")
body.getVariableBoolean=function() return false end
assert(T.banditDisposition(body)==nil and not T.ignoreForeignNpc(body),"ordinary zombies are unchanged")
Bandit=oldBandit
print("Bandit disposition PASS nativeOwner=readOnly acquisition=true retirement=true unknown=protected")
