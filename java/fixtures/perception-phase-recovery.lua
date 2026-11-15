local C=assert(KnoxAutonomyController)
local actors={}
for i=1,60 do
 actors[i]=setmetatable({perceptionPhase=codecPerceptionOffset("ks-dev-"..i)},C)
 actors[i].deadline=actors[i]:nextThreatScanAfter(100)
 assert(actors[i].deadline>100 and actors[i].deadline<=115,
  "post-interruption observation is never postponed beyond the original interval")
end
local peak,total=0,0
for tick=101,160 do
 local count=0
 for _,actor in ipairs(actors) do
  if tick>=actor.deadline then count=count+1;actor.deadline=actor:nextThreatScanAfter(tick) end
 end
 total=total+count;peak=math.max(peak,count)
end
assert(total==240,"sixty actors retain four periodic observations each over sixty ticks")
assert(peak<=12,"a shared interruption does not leave sixty periodic scans on one tick")
print("Perception phase PASS actors=60 periodic_observations="..total.." peak="..peak.." native_fps=false")
return "Perception phase: actors=60 scans="..total.." peak="..peak.." nativeFPS=NOT_VERIFIED"
