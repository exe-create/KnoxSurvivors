local C=assert(KnoxAutonomyController)
local attempted=0
local actor=setmetatable({id="guest-one",character={getCurrentSquare=function() return {
    getX=function() return 8701 end,getY=function() return 8701 end,getZ=function() return 0 end,
} end},beginRoam=function() attempted=attempted+1;return false end},{__index=C})
assert(actor:beginRecovery("sleep",100)==false,"unauthorized rest is not accepted")
assert(attempted==1 and actor.nextThink==220,"private-floor rest uses outward routing with a bounded retry")
assert(actor.selfCareIntent==nil,"an unavailable exit never fabricates sleep or recovery")
