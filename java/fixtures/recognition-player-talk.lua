local S,D=assert(recognitionTalkService),assert(KnoxSurvivorDialogue)
local old={p=KnoxPersistence,r=KnoxSurvivorRuntime,f=KnoxActivityFeed,s=KnoxSettings,time=getGameTime}
local spoken,age={},500
KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end,event=function() end,reputation=function() end}
KnoxSettings={showSurvivorSpeech=function() return true end}
getGameTime=function() return {getWorldAgeHours=function() return age end} end
local tile={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
local player={getCurrentSquare=function() return tile end,isDead=function() return false end}
local person={visible=true,getCurrentSquare=function() return tile end,isDead=function() return false end,
 CanSee=function(self) if self.throw then error("vision unknown") end return self.visible end}
local controller={currentTicks=100};local social="join";local team=false;local relation=nil;local cooldown=false;local ended=0
KnoxSurvivorRuntime={getCharacter=function() return person end,getController=function() return controller end,
 beginPlayerConversation=function() return true end,endPlayerConversation=function() ended=ended+1 end}
KnoxPersistence={ensurePlayerId=function() return "player-id" end,getSurvivorIdentity=function() return {forename="Nora",surname="Vale"} end,
 getSurvivorPersonality=function() return {personality="brave"} end,
 getPlayerSocialDisposition=function() return social end,getSurvivorAffiliation=function() return {kind=team and "player" or "independent"} end,
 isSurvivorHostileToPlayer=function() return false end,setSurvivorHostileToPlayer=function() end,
 getPlayerRelationship=function() return relation end,
 recordPlayerConversation=function(_,_,gain,hours,window)
  assert(gain==8 and hours==age and window==0.5,"reward uses actual world hours and original cooldown")
  if not relation then relation={meetings=0,trust=30} end
  if cooldown then return relation,"cooldown" end
  relation.meetings=relation.meetings+1;relation.trust=relation.trust+gain;return relation,"recorded"
 end}
D.resetRuntime();assert(S.talk(player,"npc"),"first talk admitted")
assert(relation.meetings==1 and (spoken[1]=="Easy. Who are you?" or spoken[1]=="You all right?"),"visual first meeting uses authored greeting")
controller.currentTicks=340;age=501;assert(S.talk(player,"npc"),"second talk admitted")
assert(relation.meetings==2 and (spoken[2]=="You're still standing. Good." or spoken[2]=="Good to see you."),
 "in-place relationship mutation still uses prior count for known greeting")
controller.currentTicks=580;age=502;assert(S.talk(player,"npc"))
assert(spoken[3]~="You're still standing. Good." and spoken[3]~="Good to see you.","same known greeting is not repeated")
-- R1 and player recognition share a real controller-tick budget.
D.resetRuntime();spoken={};relation=nil;controller.currentTicks=100
assert(D.sayRecognition(person,"npc","other",100),"living recognition admitted")
assert(S.talk(player,"npc"));assert(spoken[2]~="Easy. Who are you?" and spoken[2]~="You all right?",
 "R1 global cooldown prevents a second recognition")
assert(D.sayRecognition(person,"npc","third",340),"world age does not poison controller tick budget")
for _,case in ipairs({"blind","unreadable","missing-clock","nan-clock","infinite-clock","negative-clock","string-clock","protected","independent","warmup","lure","warn","volatile","cooldown"}) do
 D.resetRuntime();spoken={};relation=nil;controller={currentTicks=100};person.visible=true;person.throw=false;social="join";team=false;cooldown=false;ended=0
 if case=="blind" then person.visible=false elseif case=="unreadable" then person.throw=true
 elseif case=="missing-clock" then controller=nil elseif case=="nan-clock" then controller.currentTicks=0/0
 elseif case=="infinite-clock" then controller.currentTicks=math.huge elseif case=="negative-clock" then controller.currentTicks=-1
 elseif case=="string-clock" then controller.currentTicks="100"
 elseif case=="protected" then team=true
 elseif case=="independent" then social="independent" elseif case=="warmup" then social="warm_up"
 elseif case=="lure" then social="lure" elseif case=="warn" then social="warn_then_attack"
 elseif case=="volatile" then social="volatile" elseif case=="cooldown" then cooldown=true end
 local ok=S.talk(player,"npc")
 assert(ok==(case~="cooldown" and case~="volatile"),"talk outcome stays intact "..case)
 assert(spoken[1]~="Easy. Who are you?" and spoken[1]~="You all right?","no first visual greeting "..case)
 if case=="cooldown" then assert(ended==0 and relation.meetings==0,"reward cooldown keeps attention without reward") end
end
-- Failed delivery does not consume recognition cache or budget.
D.resetRuntime();spoken={};relation=nil;controller={currentTicks=100};person.throw=false;person.visible=true;social="join";team=false;cooldown=false
local attempts=0;KnoxActivityFeed.speak=function() attempts=attempts+1;return false end
assert(S.talk(player,"npc"));KnoxActivityFeed.speak=function(_,line) spoken[#spoken+1]=line;return true end
relation=nil;assert(S.talk(player,"npc"));assert(spoken[1]=="Easy. Who are you?" or spoken[1]=="You all right?",
 "failed delivery leaves first greeting available")
-- Disabled voice uses the existing fallback and remembers no greeting.
D.resetRuntime();spoken={};relation=nil;controller={currentTicks=0};person.visible=true;person.throw=false;social="join";team=false;cooldown=false
KnoxSettings.showSurvivorSpeech=function() return false end
assert(S.talk(player,"npc") and spoken[1]~="Easy. Who are you?" and spoken[1]~="You all right?",
 "disabled voice uses ordinary fallback")
KnoxSettings.showSurvivorSpeech=function() return true end
relation=nil;spoken={};assert(S.talk(player,"npc") and (spoken[1]=="Easy. Who are you?" or spoken[1]=="You all right?"),
 "zero ticks is valid and disabled delivery did not remember greeting")
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 KnoxPersistence.getSurvivorPersonality=function() return {personality=voice} end
 for _,event in ipairs({"player_first","player_known"}) do
  local lines,chosen=D.linesFor("npc",event)
  assert(chosen==voice and #lines==2,"player greeting uses authored voice "..voice.." "..event)
 end
end
D.resetRuntime();KnoxPersistence=old.p;KnoxSurvivorRuntime=old.r;KnoxActivityFeed=old.f;KnoxSettings=old.s;getGameTime=old.time
print("Player visual recognition PASS nativeGameplay=false")
