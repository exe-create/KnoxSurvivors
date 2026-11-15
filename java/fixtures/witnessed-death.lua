local P,C,D=KnoxPersistence,KnoxAutonomyController,KnoxSurvivorDialogue
local old={data=data,runtime=KnoxSurvivorRuntime,feed=KnoxActivityFeed,settings=KnoxSettings,
 relationships=KnoxSurvivorRelationships,time=getGameTime,needs=KnoxSurvivorNeeds,service=KnoxCompanionService}
data={};getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
for _,id in ipairs({"w-owner","w-other"}) do assert(P.ensurePlayerId({getModData=function() return {KnoxSurvivors={playerId=id}} end})==id) end
for _,id in ipairs({"w-victim","w-watch","w-unknown","w-error","w-live"}) do assert(P.setRecord(id,expectedRecord)) end
assert(P.ensureSurvivorIdentity("w-victim","Nora%","Vale",0))
assert(P.ensureSurvivorIdentity("w-live","Living","Person",0))
assert(P.rememberObserverKnowledge("w-owner","w-live","seen",{alive=true},1))
assert(P.rememberObserverKnowledge("w-owner","w-victim","seen",{alive=true},1))
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local victim={square=square(2),dead=true}
function victim:getCurrentSquare() return self.square end;function victim:isDead() return self.dead end
function victim:getX() return 2 end;function victim:getY() return 0 end;function victim:getZ() return 0 end
function victim:getAttackedBy() return nil end
local observer={square=square(0),dead=false,visible=true}
function observer:getCurrentSquare() return self.square end;function observer:isDead() return self.dead end
function observer:CanSee() if self.unknown then error("unknown sight") end return self.visible end
local spoken,feedCalls,removed,errors={},0,0,0
KnoxSettings={showSurvivorSpeech=function() return true end};KnoxSurvivorNeeds=nil;KnoxCompanionService=nil
KnoxSurvivorRelationships=assert(relationshipObservationProbe.relationships)
KnoxSurvivorRuntime={idForCharacter=function() return nil end,unregister=function() end}
KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end,
 survivorDied=function(id) feedCalls=feedCalls+1;assert(P.rememberObserverKnowledge("w-other",id,"seen",{alive=false},10)) end}
local watched=setmetatable({id="w-watch",character=observer,companionOwnerId="w-owner",currentTicks=100},C)
local unknown=setmetatable({id="w-unknown",character=observer,companionOwnerId="w-other",currentTicks=100},C)
local callbackCounts={}
for _,w in ipairs({watched,unknown}) do
 w.reportWitnessedDeath=function(self,id,body)
  callbackCounts[self.id]=(callbackCounts[self.id] or 0)+1
  return C.reportWitnessedDeath(self,id,body)
 end
end
local bad={reportWitnessedDeath=function() errors=errors+1;error("fixture callback failure") end}
local deadController={id="w-victim",character=victim,shutdown=function() end}
local ids={"w-victim","w-watch","w-unknown","w-error"}
local controllers={["w-victim"]=deadController,["w-watch"]=watched,["w-unknown"]=unknown,["w-error"]=bad}
local retire=witnessedDeathFactory(ids,controllers,function() removed=removed+1 end)
local bridge={retireNpcAsCorpse=function() return "CORPSE_CREATED" end,getNpcCharacter=function() return nil end}
D.resetRuntime();retire(bridge,"w-victim",deadController)
assert(not P.isSurvivorAlive("w-victim") and #spoken==1 and spoken[1]:find("Nora% Vale",1,true),
 "prior-known visible witness speaks actual death name")
assert(feedCalls==1 and removed==1 and errors==1 and callbackCounts["w-watch"]==1
 and callbackCounts["w-unknown"]==1 and controllers["w-victim"]==nil,
 "callback error cannot stop feed and physical retirement")
assert(P.getObserverKnowledge("w-other","w-victim")~=nil and #spoken==1,
 "later player feed knowledge cannot retroactively authorize unknown witness")
assert(not watched:reportWitnessedDeath("w-victim",victim),"same death line is not repeated")
for _,mode in ipairs({"self","victim-alive","observer-dead","hidden","unreadable-sight","unloaded","floor","far","no-owner","other-owner","missing-clock","nan-clock","infinite-clock","logical-alive","missing-name"}) do
 D.resetRuntime();observer.dead=false;observer.visible=true;observer.unknown=false;observer.square=square(0);victim.dead=true;victim.square=square(2)
 watched.id="w-watch";watched.companionOwnerId="w-owner";watched.currentTicks=100
 local id="w-victim"
 if mode=="self" then watched.id=id elseif mode=="victim-alive" then victim.dead=false
 elseif mode=="observer-dead" then observer.dead=true elseif mode=="hidden" then observer.visible=false
 elseif mode=="unreadable-sight" then observer.unknown=true elseif mode=="unloaded" then observer.square=nil
 elseif mode=="floor" then victim.square=square(2,1) elseif mode=="far" then victim.square=square(40)
 elseif mode=="no-owner" then watched.companionOwnerId=nil elseif mode=="other-owner" then watched.companionOwnerId="no-ledger"
 elseif mode=="missing-clock" then watched.currentTicks=nil elseif mode=="nan-clock" then watched.currentTicks=0/0
 elseif mode=="infinite-clock" then watched.currentTicks=math.huge elseif mode=="logical-alive" then id="w-live"
 elseif mode=="missing-name" then id="w-nameless";assert(P.setRecord(id,expectedRecord));assert(P.rememberObserverKnowledge("w-owner",id,"seen",{alive=true},1));assert(P.markSurvivorDead(id,1,"fixture")) end
 assert(not watched:reportWitnessedDeath(id,victim),"ineligible death stays silent "..mode)
end
D.resetRuntime();watched.id="w-watch";watched.companionOwnerId="w-owner";watched.currentTicks=100
victim.dead=true;victim.square=square(2);observer.dead=false;observer.visible=true;observer.square=square(0)
local attempts=0;KnoxActivityFeed.speak=function() attempts=attempts+1;return false end
assert(not watched:reportWitnessedDeath("w-victim",victim),"failed delivery does not report success")
KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
assert(watched:reportWitnessedDeath("w-victim",victim) and attempts==1,"failed delivery does not spend recognition")
local oldPersonality=P.getSurvivorPersonality
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 P.getSurvivorPersonality=function() return {personality=voice} end
 local lines,chosen=D.linesFor("w-watch","known_death")
 assert(chosen==voice and #lines==2,"known-death authored voice "..voice)
end
P.getSurvivorPersonality=oldPersonality
D.resetRuntime();data=old.data;KnoxSurvivorRuntime=old.runtime;KnoxActivityFeed=old.feed;KnoxSettings=old.settings
KnoxSurvivorRelationships=old.relationships;getGameTime=old.time;KnoxSurvivorNeeds=old.needs;KnoxCompanionService=old.service
print("Witnessed known death PASS nativeGameplay=false")
