local C,D=KnoxAutonomyController,KnoxSurvivorDialogue
local old={runtime=KnoxSurvivorRuntime,persistence=KnoxPersistence,feed=KnoxActivityFeed,
 settings=KnoxSettings,cell=getCell,threat=KnoxThreatClassifier,indicators=KnoxSpeechIndicators}
local spoken,rails,lists,seenCalls={},0,0,0
KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end,event=function() rails=rails+1;return {} end}
KnoxSettings={showSurvivorSpeech=function() return true end}
KnoxThreatClassifier={isCorpseProxy=function(z) return z.proxy==true end}
KnoxSpeechIndicators={compassWord=function() return "east" end}
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local origin=square(0)
local function zombie(x,z)
 return setmetatable({square=square(x,z),visible=true,dead=false}, {__tostring=function() return "same" end,
 __index={getCurrentSquare=function(self) return self.square end,isDead=function(self) return self.dead end}})
end
local hidden,visible,other=zombie(1),zombie(2),zombie(3)
local dead,proxy,far,floor=zombie(1),zombie(1),zombie(100),zombie(1,1)
hidden.visible=false;dead.dead=true;proxy.proxy=true
local zombies={hidden,visible,other,dead,proxy,far,floor}
getCell=function() return {getZombieList=function() lists=lists+1;return {size=function() return #zombies end,get=function(_,i) return zombies[i+1] end} end} end
local observer={getCurrentSquare=function() return origin end,CanSee=function(_,z) seenCalls=seenCalls+1;if z.unknown then error("sight unknown") end;return z.visible end}
KnoxSurvivorRuntime={activeIds=function() return {} end,getCharacter=function() end}
KnoxPersistence={getSurvivorPersonality=function() return {personality="brave"} end}
local count,near,seen=codecZombiePressure(origin,10)
assert(count==3 and near==hidden.square and seen==nil and seenCalls==0,"legacy pressure preserves count and nearest without sight calls")
local count2,near2,seen2=codecZombiePressure(origin,10,observer)
assert(count2==3 and near2==hidden.square and seen2==visible,"closest visible zombie selected despite closer hidden")
visible.unknown=true
local _,_,nextVisible=codecZombiePressure(origin,10,observer)
assert(nextVisible==other,"unreadable sight is not visibility")
visible.unknown=false
local c=setmetatable({id="r3a-observer",character=observer},C)
D.resetRuntime();spoken={};lists=0
assert(c:reportPatrolSighting(0,true) and #spoken==1 and lists==1,"patrol recognizes visible undead from one zombie list")
assert(spoken[1]=="There's a zombie." or spoken[1]=="One of them. Stay ready.","authored anonymous undead voice")
assert(c:reportPatrolSighting(1800,true) and #spoken==2 and spoken[2]:find("A few",1,true)==1,
 "same undead falls back to ordinary periodic pressure")
visible.visible=false
assert(c:reportPatrolSighting(3600,true) and #spoken==3 and spoken[3]~=spoken[1],
 "different visible physical zombie can be recognized")
local person={getCurrentSquare=function() return square(1) end,isDead=function() return false end}
KnoxSurvivorRuntime={activeIds=function() return {"human"} end,getCharacter=function() return person end}
KnoxPersistence.getSurvivorAffiliation=function() return {kind="faction"} end
KnoxPersistence.getFactionForSurvivor=function() return {name="Ward"} end
observer.CanSee=function() return true end
D.resetRuntime();spoken={};local priority=setmetatable({id="r3a-priority",character=observer},C)
assert(priority:reportPatrolSighting(0,true) and spoken[1]:find("a member of Ward",1,true),"living faction contact outranks undead")
-- Equality uses the object itself, not a displayed string or synthetic ID.
D.resetRuntime();spoken={}
assert(tostring(visible)==tostring(other),"distinct zombie fixtures share the same string representation")
assert(D.sayRecognition(observer,"mixed",visible,0,nil,"recognition_undead"),"first physical object spoken")
assert(not D.sayRecognition(observer,"mixed",visible,240,nil,"recognition_undead"),"same object suppressed")
assert(D.sayRecognition(observer,"mixed",other,240,nil,"recognition_undead"),"distinct object receives own recognition")
assert(D.sayRecognition(observer,"mixed","person-id",480,nil,"npc_known","Nora"),"string subject coexists with object subjects")
assert(not D.sayRecognition(observer,"mixed","fake-id",720,nil,"recognition_undead"),"undead string identities refused")
D.resetRuntime()
local objects={}
for i=1,32 do objects[i]=zombie(2);assert(D.sayRecognition(observer,"bounded",objects[i],i*240,nil,"recognition_undead")) end
assert(D.sayRecognition(observer,"bounded","living-id",33*240),"mixed cache accepts string subject")
assert(D.sayRecognition(observer,"bounded",objects[1],34*240,nil,"recognition_undead"),"oldest physical reference evicted at shared cap")
D.resetRuntime();assert(D.sayRecognition(observer,"bounded",objects[32],0,nil,"recognition_undead"),"runtime reset clears physical references")
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 KnoxPersistence.getSurvivorPersonality=function() return {personality=voice} end
 local lines,chosen=D.linesFor("r3a-observer","recognition_undead")
 assert(chosen==voice and #lines==2,"undead authored voice "..voice)
end
D.resetRuntime();KnoxActivityFeed.speak=function() return false end
assert(not D.sayRecognition(observer,"failed",visible,0,nil,"recognition_undead"),"failed undead delivery refused")
KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
assert(D.sayRecognition(observer,"failed",visible,0,nil,"recognition_undead"),"failed undead delivery leaves cache and budget untouched")
D.resetRuntime();KnoxSettings.showSurvivorSpeech=function() return false end
assert(not D.sayRecognition(observer,"disabled",visible,0,nil,"recognition_undead"),"disabled speech refuses undead recognition")
KnoxSettings.showSurvivorSpeech=function() return true end
local attempts=0;KnoxActivityFeed.speak=function() attempts=attempts+1;return false end
local remote=setmetatable({id="r3a-remote",character=observer},C);KnoxSurvivorRuntime={activeIds=function() return {} end,getCharacter=function() end}
assert(remote:reportPatrolSighting(0,true) and rails==1 and attempts==1,"undead base rail delivers once after failed speech")
D.resetRuntime();KnoxSurvivorRuntime=old.runtime;KnoxPersistence=old.persistence;KnoxActivityFeed=old.feed
KnoxSettings=old.settings;getCell=old.cell;KnoxThreatClassifier=old.threat;KnoxSpeechIndicators=old.indicators
print("Visible undead recognition PASS nativeGameplay=false")
