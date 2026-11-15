local C,P,D=KnoxAutonomyController,KnoxCompanionPatrol,KnoxSurvivorDialogue
local old={runtime=KnoxSurvivorRuntime,persistence=KnoxPersistence,feed=KnoxActivityFeed,
 settings=KnoxSettings,cell=getCell,indicators=KnoxSpeechIndicators}
local spoken,events,scans={},0,0
KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end,event=function() events=events+1 end}
KnoxSettings={showSurvivorSpeech=function() return true end}
getCell=function() return {getZombieList=function() return {size=function() return 0 end} end} end
KnoxSpeechIndicators={compassWord=function() return "east" end}
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local origin=square(0);local person={square=square(2),dead=false,visible=true}
function person:getCurrentSquare() return self.square end
function person:isDead() return self.dead end
local observer={getCurrentSquare=function() return origin end,CanSee=function(_,target) return target.visible end}
local bodies={other=person};local ids={"other"}
KnoxSurvivorRuntime={activeIds=function() scans=scans+1;return ids end,getCharacter=function(id) return bodies[id] end}
local affiliation={kind="independent"};local known=false
KnoxPersistence={getSurvivorAffiliation=function() return affiliation end,
 getFactionForSurvivor=function() return nil end,getObserverKnowledge=function() return known and {} or nil end,
 getSurvivorIdentity=function() return {forename="Nora",surname="Vale"} end,
 getSurvivorPersonality=function() return {personality="brave"} end}
local c=setmetatable({id="watcher",character=observer,companionOwnerId="player"},C)
D.resetRuntime()
local where,word,id,kind=c:nearestSightingContact(origin,10)
assert(where==person.square and word=="a stranger" and id=="other" and kind=="stranger",
 "visible living stranger produces typed exact identity")
assert(c:reportPatrolSighting(100,true) and #spoken==1 and scans==2,"patrol speaks real stranger from existing scan")
assert(not c:reportPatrolSighting(1899,true) and scans==2,"patrol cadence blocks early scan")
assert(c:reportPatrolSighting(1900,true) and scans==3 and #spoken==2 and events==0
 and spoken[2]:find("I see a stranger",1,true)==1,
 "recent stranger gets one ordinary patrol warning at the single cooldown")
ids={"another"};bodies.another=person
assert(c:reportPatrolSighting(3700,true) and #spoken==3
 and spoken[3]:find("I see a stranger",1,true)==nil,"another real stranger gets first recognition")
for _,case in ipairs({"player","known","faction","dead","distant","occluded"}) do
 ids={"other"};affiliation={kind="independent"};known=false;person.dead=false;person.visible=true;person.square=square(2)
 if case=="player" then affiliation={kind="player"} elseif case=="known" then known=true
 elseif case=="faction" then affiliation={kind="faction"};KnoxPersistence.getFactionForSurvivor=function() return {name="Ward"} end
 elseif case=="dead" then person.dead=true elseif case=="distant" then person.square=square(100)
 elseif case=="occluded" then person.visible=false end
 local _,_,subject,category=c:nearestSightingContact(origin,10)
 assert(category~="stranger" or subject==nil,"non-stranger or unseen cannot trigger recognition: "..case)
 KnoxPersistence.getFactionForSurvivor=function() return nil end
end
-- A base warning uses the existing rail once when overhead delivery refuses.
D.resetRuntime();spoken={};events=0;ids={"other"};affiliation={kind="independent"};known=false
person.dead=false;person.visible=true;person.square=square(2)
KnoxActivityFeed.speak=function() return false end
KnoxActivityFeed.event=function() events=events+1;return {} end
local remote=setmetatable({id="remote",character=observer,companionOwnerId="player"},C)
assert(remote:reportPatrolSighting(0,true) and events==1,"unheard base stranger has one rail delivery")
assert(not remote:reportPatrolSighting(1800,true) and events==2,
 "recent stranger gets one existing generic rail warning")
KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
affiliation={kind="independent"};ids={"other"};person.visible=true;person.square=square(2)
person.isDead=function() error("life unreadable") end
assert(c:nearestSightingContact(origin,10)==nil,"unreadable life cannot be recognized as living")
person.isDead=function(self) return self.dead end;person.dead=false
affiliation={kind="faction"};ids={"other"};known=false
KnoxPersistence.getFactionForSurvivor=function() return nil end
local _,fallbackWord,_,fallbackKind=c:nearestSightingContact(origin,10)
assert(fallbackWord=="a stranger" and fallbackKind=="faction", "unnamed faction preserves wording without false stranger recognition")
D.resetRuntime();spoken={}
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 KnoxPersistence.getSurvivorPersonality=function() return {personality=voice} end
 local lines,actual=D.linesFor("voice", "recognition_living")
 assert(actual==voice and type(lines)=="table" and #lines>=2,"authored recognition voice "..voice)
end
KnoxSettings.showSurvivorSpeech=function() return false end
assert(not D.sayRecognition(observer,"silent","x",0),"disabled speech is not remembered")
KnoxSettings.showSurvivorSpeech=function() return true end
assert(D.sayRecognition(observer,"silent","x",0),"previously refused subject can speak")
assert(not D.sayRecognition(observer,"silent","y",1),"global speech cooldown applies")
assert(D.sayRecognition(observer,"silent","y",240),"distinct subject speaks after cooldown")
assert(D.sayRecognition(observer,"other-observer","x",0),"recent subjects are per observer")
D.resetRuntime()
for i=1,33 do assert(D.sayRecognition(observer,"bounded","subject-"..i,i*240),"bounded subject spoken") end
assert(not D.sayRecognition(observer,"bounded","subject-33",34*240),"recent subject remains suppressed")
assert(D.sayRecognition(observer,"bounded","subject-1",34*240),"oldest subject is evicted at 32")
D.resetRuntime();assert(D.sayRecognition(observer,"bounded","subject-33",0),"runtime reset clears recent subjects")
D.resetRuntime();KnoxSurvivorRuntime=old.runtime;KnoxPersistence=old.persistence;KnoxActivityFeed=old.feed
KnoxSettings=old.settings;getCell=old.cell;KnoxSpeechIndicators=old.indicators
print("Living stranger recognition PASS nativeGameplay=false")
