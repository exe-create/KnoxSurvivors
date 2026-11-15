local D=assert(KnoxSurvivorDialogue)
local service=assert(CompanionService)
local oldRecount=D.recountLines
local actor={};local player={Say=function() end}
KS_ASK_SET({character=actor,hostile=false,hearing=true})
D.recountLines=function() return {} end
local seen={}
for i=1,6 do
 local ok,line=service.askAbout(player,"fallback-speaker","travels")
 assert(ok and not seen[line], "six no-history answers stay distinct without inventing an event")
 seen[line]=true
end
local facts={"I met Ada at the store.","Nora told me the bridge was blocked.","I was hurt near the farm."}
D.recountLines=function() return facts end
seen={}
for i=1,3 do
 local ok,line=service.askAbout(player,"history-speaker","travels")
 local actual=false
 for _,fact in ipairs(facts) do if fact==line then actual=true end end
 assert(ok and actual and not seen[line], "successive travel answers select separate real recorded facts")
 seen[line]=true
end
D.recountLines=oldRecount
print("History answers PASS honestFallbacks=true recordedFacts=true distinctUntilExhausted=true")
