local C=KnoxAutonomyController
local previousQueue,previousHygiene=ISTimedActionQueue,KnoxBaseHygiene
local body=journeyBody
local previousState=body.state
local progress,started=0,false
local action={getJobDelta=function() return progress end,action={isStarted=function() return started end}}
ISTimedActionQueue={queues={[body]={queue={action}}}}
local c=setmetatable({character=body},C)
local plan={action=action}
local budget=C.TUNING.ACTION_TIMEOUT_TICKS
assert(not c:ambientActionStalled(plan,0))
progress=.2;started=true
assert(not c:ambientActionStalled(plan,budget))
assert(not c:ambientActionStalled(plan,budget*2),"real progress and one start transition renew the budget")
assert(c:ambientActionStalled(plan,budget*2+1),"queued action without progress cannot hold the survivor forever")
body.state="PlayerHitReactionState"
assert(not c:ambientActionStalled(plan,budget*3),"native injury recovery owns the body")
body.state="idle"
assert(not c:ambientActionStalled(plan,budget*3+100))
ISTimedActionQueue.queues[body].queue={}
assert(not c:ambientActionStalled(plan,budget*10),"drained action must reach its real completion receipt")

local cancelled,failed=0,nil
plan={action=action}
ISTimedActionQueue.queues[body].queue={action}
KnoxBaseHygiene={step=function() return "working" end}
local washer=setmetatable({character=body,pendingHygiene=plan,state="BASE_HYGIENE",
    nextHygieneNeedsCheck=math.huge,hygieneStartedAt=0,
    releaseBaseHygiene=function(self) cancelled=cancelled+1;self.pendingHygiene=nil end,
    recordFailure=function(_,reason) failed=reason end,
    finishDecision=function(self) self.state="IDLE" end},C)
washer:updateBaseHygiene(0)
washer:updateBaseHygiene(budget+1)
assert(cancelled==1 and washer.state=="IDLE" and failed=="base_hygiene:wash_action_stalled",
    "stalled washing exits through its existing cancellation/retry owner before the long session timeout")
body.state=previousState
ISTimedActionQueue,KnoxBaseHygiene=previousQueue,previousHygiene
print("Ambient action recovery PASS stalled_queue=true real_progress=true native_recovery=true receipt_first=true wash_auto_recovery=true")
