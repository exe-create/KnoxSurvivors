local C,D,P=KnoxAutonomyController,KnoxSurvivorDialogue,KnoxPersistence
local old={data=data,runtime=KnoxSurvivorRuntime,feed=KnoxActivityFeed,settings=KnoxSettings,cell=getCell,indicators=KnoxSpeechIndicators}
data={}
for _,id in ipairs({"r2b-owner","r2b-other"}) do
 assert(P.ensurePlayerId({getModData=function() return {KnoxSurvivors={playerId=id}} end})==id)
end
assert(P.setRecord("r2b-person",expectedRecord));assert(P.setRecord("r2b-nameless",expectedRecord))
assert(P.ensureSurvivorIdentity("r2b-person","Nora%","Vale",0))
assert(P.rememberObserverKnowledge("r2b-other","r2b-person","seen",{alive=true},1))
local spoken,rails,scans={},0,0
KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end,event=function() rails=rails+1;return {} end}
KnoxSettings={showSurvivorSpeech=function() return true end}
getCell=function() return {getZombieList=function() return {size=function() return 0 end} end} end
KnoxSpeechIndicators={compassWord=function() return "east" end}
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local origin=square(0);local person={square=square(2),dead=false,visible=true}
function person:getCurrentSquare() return self.square end;function person:isDead() return self.dead end
local observer={getCurrentSquare=function() return origin end,CanSee=function(_,who) return who.visible end}
local ids={"r2b-person"};local bodies={["r2b-person"]=person,["r2b-nameless"]=person}
KnoxSurvivorRuntime={activeIds=function() scans=scans+1;return ids end,getCharacter=function(id) return bodies[id] end}
local c=setmetatable({id="r2b-watch",character=observer,companionOwnerId="r2b-owner"},C)
D.resetRuntime()
local _,word,id,kind=c:nearestSightingContact(origin,10)
assert(word=="a stranger" and id=="r2b-person" and kind=="stranger", "another owner's knowledge does not name stranger")
assert(c:reportPatrolSighting(0,true) and #spoken==1,"first unknown sighting uses stranger recognition")
assert(P.rememberObserverKnowledge("r2b-owner","r2b-person","seen",{alive=true},2))
local _,name,knownId,knownKind=c:nearestSightingContact(origin,10)
assert(name=="Nora% Vale" and knownId=="r2b-person" and knownKind=="known", "real owner knowledge produces exact known identity")
assert(c:reportPatrolSighting(1800,true) and #spoken==2 and spoken[2]:find("Nora% Vale",1,true),
 "owner-known visible person gets factual named voice")
assert(not spoken[2]:find("remember",1,true) and not spoken[2]:find("met",1,true),"named voice does not invent personal history")
assert(c:reportPatrolSighting(3600,true) and #spoken==3 and spoken[3]:find("I see Nora% Vale",1,true)==1,
 "repeat known sighting retains ordinary patrol report")
assert(scans==5,"recognition does not add a population scan")
ids={"r2b-nameless"};assert(P.rememberObserverKnowledge("r2b-owner","r2b-nameless","seen",{alive=true},3))
local _,nameless,_,namelessKind=c:nearestSightingContact(origin,10)
assert(nameless=="a stranger" and namelessKind=="stranger","missing identity cannot invent a name")
ids={"r2b-person"}
for _,mode in ipairs({"hidden","dead","floor"}) do
 person.visible=true;person.dead=false;person.square=square(2)
 if mode=="hidden" then person.visible=false elseif mode=="dead" then person.dead=true else person.square=square(2,1) end
 assert(c:nearestSightingContact(origin,10)==nil,"unseen or nonliving body is excluded "..mode)
end
person.visible=true;person.dead=false;person.square=square(2)
assert(P.setPlayerCompanion("r2b-person","r2b-owner","follow",4))
assert(c:nearestSightingContact(origin,10)==nil,"player-owned contact is excluded")
D.resetRuntime();spoken={};KnoxActivityFeed.speak=function() return false end
local remote=setmetatable({id="r2b-remote",character=observer,companionOwnerId="r2b-other"},C)
-- Use a separate independent identity for the real owner-known rail case.
ids={"r2b-nameless"};assert(P.ensureSurvivorIdentity("r2b-nameless","Mira","Stone",0))
assert(P.rememberObserverKnowledge("r2b-other","r2b-nameless","seen",{alive=true},4))
assert(remote:reportPatrolSighting(0,true) and rails==1,"known named base sighting uses existing rail fallback once")
assert(not D.sayRecognition(observer,"r2b-x","id",0,nil,"npc_known"," "),"blank known name refused")
KnoxSettings.showSurvivorSpeech=function() return false end
assert(not D.sayRecognition(observer,"r2b-disabled","id",0,nil,"npc_known","Mira"),"disabled speech refuses known line")
KnoxSettings.showSurvivorSpeech=function() return true end
KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
assert(D.sayRecognition(observer,"r2b-disabled","id",0,nil,"npc_known","Mira"),"failed speech did not remember name")
assert(not D.sayRecognition(observer,"r2b-disabled","other",1,nil,"npc_known","Mira"),"known lines share global budget")
local oldPersonality=P.getSurvivorPersonality
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 P.getSurvivorPersonality=function() return {personality=voice} end
 local lines,chosen=D.linesFor("r2b-watch","npc_known")
 assert(chosen==voice and #lines==2,"known-person authored voice "..voice)
end
P.getSurvivorPersonality=oldPersonality
D.resetRuntime();spoken={};local failedAttempts=0
KnoxActivityFeed.speak=function() failedAttempts=failedAttempts+1;return false end
assert(not D.sayRecognition(observer,"r2b-failed","person",0,nil,"npc_known","Mira"),
 "failed voice delivery does not count")
KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
assert(D.sayRecognition(observer,"r2b-failed","person",0,nil,"npc_known","Mira") and failedAttempts==1,
 "failed voice delivery leaves cache and budget untouched")
D.resetRuntime();data=old.data;KnoxSurvivorRuntime=old.runtime;KnoxActivityFeed=old.feed
KnoxSettings=old.settings;getCell=old.cell;KnoxSpeechIndicators=old.indicators
print("Owner-known sighting PASS nativeGameplay=false")
