local D=assert(KnoxSurvivorDialogue)
local old={feed=KnoxActivityFeed,settings=KnoxSettings,persistence=KnoxPersistence,runtime=KnoxSurvivorRuntime,instanceof=instanceof}
local spoken={};local enabled=true;local accept=true
KnoxActivityFeed={speak=function(_,line) if not accept then return false end;spoken[#spoken+1]=line;return true end}
KnoxSettings={showSurvivorSpeech=function() return enabled end}
KnoxPersistence={getSurvivorPersonality=function() return {personality="brave"} end}
KnoxSurvivorRuntime={idForCharacter=function(target) if target.human then return "human" end end}
instanceof=function(target,kind) return kind=="IsoZombie" and target.zombie==true end
local c={id="fighter",character={},currentTicks=0,nextThreatScan=0,sampleCombatConfidence=function() end}
D.resetRuntime()
assert(combatBarkEntryFactory(c,{zombie=true})=="zombie" and spoken[1]~=nil
 and (spoken[1]=="Come get some!" or spoken[1]=="Come on, you f*cker."),
 "zombie entry uses authored zombie combat voice")
D.resetRuntime();spoken={};assert(combatBarkEntryFactory(c,{human=true})=="survivor" and #spoken==1
 and spoken[1]~="Come get some!" and spoken[1]~="Come on, you f*cker.","human keeps generic combat voice")
D.resetRuntime();spoken={};assert(combatBarkEntryFactory(c,{})=="unknown" and #spoken==1,
 "unknown target keeps generic combat voice")
D.resetRuntime();spoken={};combatBarkEntryFactory(c,{zombie=true});combatBarkEntryFactory(c,{zombie=true})
assert(#spoken==1,"global/event budget suppresses repeated entry")
local firstEntry=spoken[1];c.currentTicks=900;combatBarkEntryFactory(c,{zombie=true})
assert(#spoken==2 and spoken[2]~=firstEntry,"next eligible combat entry avoids repeating the line")
D.resetRuntime();spoken={};c.currentTicks=nil;combatBarkEntryFactory(c,{zombie=true})
assert(#spoken==1 and spoken[1]~="Come get some!" and spoken[1]~="Come on, you f*cker.","missing tick uses generic fallback")
c.currentTicks=0/0;D.resetRuntime();spoken={};combatBarkEntryFactory(c,{zombie=true})
assert(#spoken==1 and spoken[1]~="Come get some!" and spoken[1]~="Come on, you f*cker.","invalid tick uses generic fallback")
for _,invalid in ipairs({math.huge,-1,"100"}) do
 c.currentTicks=invalid;D.resetRuntime();spoken={};combatBarkEntryFactory(c,{zombie=true})
 assert(#spoken==1 and spoken[1]~="Come get some!" and spoken[1]~="Come on, you f*cker.",
  "non-finite, negative or nonnumeric tick uses generic fallback")
end
c.currentTicks=0;D.resetRuntime();spoken={};enabled=false;combatBarkEntryFactory(c,{zombie=true});assert(#spoken==0,"disabled speech is silent")
enabled=true;accept=false;combatBarkEntryFactory(c,{zombie=true});assert(#spoken==0,"failed delivery is silent")
accept=true;combatBarkEntryFactory(c,{zombie=true});assert(#spoken==1,"failed delivery does not consume budget")
for _,voice in ipairs({"frightened","guarded","loner","sociable","brave"}) do
 KnoxPersistence.getSurvivorPersonality=function() return {personality=voice} end
 local lines,actual=D.linesFor("fighter","combat_zombie")
 assert(actual==voice and #lines==2,"zombie combat authored voice "..voice)
end
D.resetRuntime();KnoxActivityFeed=old.feed;KnoxSettings=old.settings;KnoxPersistence=old.persistence;KnoxSurvivorRuntime=old.runtime;instanceof=old.instanceof
print("Zombie combat entry voice PASS nativeGameplay=false")
