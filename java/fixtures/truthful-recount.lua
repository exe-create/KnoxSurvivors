local D=assert(KnoxSurvivorDialogue)
local oldStories,oldP=KnoxOffscreenStories,KnoxPersistence
KnoxPersistence={getSurvivorIdentity=function(id) return {forename=id=="source" and "Nora" or "Ada"} end}
assert(D.recountEntry("speaker",{kind="close_call",outcome="severe",t=5})=="Took a bad wound.",
    "a measured wound claims no treatment, cover, location or bleeding")
assert(D.recountEntry("speaker",{kind="close_call",outcome="hurt",t=5})=="Got hurt.")
assert(D.recountEntry("speaker",{kind="close_call",outcome="unknown"})==nil,
    "unknown outcomes cannot invent an attacker")
assert(D.recountEntry("speaker",nil)==nil)
local heard=D.recountEntry("speaker",{kind="heard",from="source",heardKind="scar"})
assert(heard=="Nora told me about returning to a place they remembered.",
    "legacy hearsay without detail invents no weapons or scenery")
assert(D.recountEntry("speaker",{kind="heard",from="source",heardKind="close_call",heardOutcome="hurt"})
    =="Nora told me about getting hurt.","hearsay keeps its real source")
local history={{kind="close_call",outcome="severe"},{kind="close_call",outcome="hurt"},
    {kind="close_call",outcome="hurt"},{kind="unsupported"},{kind="unsupported"},{kind="unsupported"}}
KnoxOffscreenStories={historyFor=function() return history end}
local lines=D.recountLines("speaker")
assert(#lines==2 and lines[1]=="Got hurt." and lines[2]=="Took a bad wound.",
    "unsupported and duplicate rows do not hide distinct recorded facts")
history={{kind="close_call",outcome="severe"}}
for i=1,12 do history[#history+1]={kind="unsupported"} end
assert(#D.recountLines("speaker")==0,"malformed oversized history still has a twelve-row read bound")
KnoxOffscreenStories,KnoxPersistence=oldStories,oldP
print("Truthful recount PASS facts=true hearsay=attributed noInventedPlace=true bounded=true")
