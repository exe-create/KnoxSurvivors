-- Production notice policy; widgets and the clock are doubles.
-- The empty digest names the theme's muted tone, so the fixture does not copy it.
local Layout=assert(rawget(_G,"KnoxSurvivorUILayout"),"layout missing")
local muted=Layout.theme.muted
local EMPTY_DIGEST="<RGB:" .. tostring(muted[1]) .. "," .. tostring(muted[2])
    .. "," .. tostring(muted[3]) .. "> Nothing to report."
local Feed=codecActivityFeed
assert(type(Feed)=="table" and type(Feed.note)=="function","notice policy is loaded")
local savedTime=getTimestampMs
local now=0
getTimestampMs=function() return now end
Feed.refreshRail=function() end
Feed.clear()

local entry=Feed.note("David finished hauling.")
assert(entry.priority=="outcome" and #Feed.digest==1 and #Feed.toasts==1,
    "an ordinary event is one digest row and one notice")
entry=Feed.note("Routine tick.",{priority="routine",key="tick"})
assert(entry.priority=="routine" and #Feed.digest==2 and #Feed.toasts==1,
    "a routine event reaches the digest but never the rail")

now=1000
entry=Feed.note("David finished hauling.")
assert(#Feed.digest==2 and Feed.digest[1].count==2,"a repeat collapses into its digest row")
assert(#Feed.toasts==1 and Feed.toasts[1].count==2,"the same notice counts up instead of stacking")

assert(Feed.classify("Could not set storage: container is full.")=="refusal")
assert(Feed.classify("No contact with David. Existing orders continue.")=="refusal")
assert(Feed.classify("Your survivor passed away.")=="danger")
assert(Feed.classify("Base established.")=="outcome")

now=2000
Feed.note("Could not open the door.")
local refusal=nil
for _,toast in ipairs(Feed.toasts) do if toast.priority=="refusal" then refusal=toast end end
assert(refusal~=nil,"a refusal uses the attention accent on the rail")

now=3000
Feed.note("A survivor attacked without warning.")
now=3500
Feed.note("Another survivor attacked.")
local dangerToasts=0
for _,toast in ipairs(Feed.toasts) do if toast.priority=="danger" then dangerToasts=dangerToasts+1 end end
assert(dangerToasts==1,"danger is held to one notice every two seconds")
local dangers=0
for _,row in ipairs(Feed.digest) do if row.priority=="danger" then dangers=dangers+1 end end
assert(dangers==2,"both danger events still reach the digest")

now=10000
Feed.note("Danger now.",{priority="danger",key="danger-now"})
Feed.note("Outcome A.",{key="a",now=10001})
Feed.note("Outcome B.",{key="b",now=10002})
Feed.note("Outcome C.",{key="c",now=10003})
assert(#Feed.toasts==3,"the rail never holds more than three notices")
assert(Feed.toasts[1].priority=="danger","danger sorts ahead of ordinary outcomes")
Feed.pruneToasts(20000)
assert(#Feed.toasts==0,"a notice expires after six seconds")
assert(Feed.toastAlpha({at=10000},10000)==0.35,
    "a new notice enters gently instead of popping")
assert(Feed.toastAlpha({at=10000},10120)==1,
    "the entrance settles after 120 ms")
assert(Feed.toastAlpha({at=10000},15500)<1,
    "the notice fades before it expires")
assert(Feed.toastAlpha({at=10000},16000)==0,
    "the exit is complete at the six-second boundary")

Feed.clear()
for index=1,60 do
    Feed.note("Entry "..tostring(index)..".",{key="entry-"..tostring(index),now=20000+index})
end
assert(#Feed.digest==50,"the digest is bounded to fifty rows")
assert(Feed.digest[1].text=="Entry 11.","the oldest rows are evicted first")

Feed.clear()
Feed.note("2 back from scavenge.",{group="Scavenging",priority="outcome",now=30000})
Feed.note("1 injury.",{group="Scavenging",priority="danger",now=30001})
local groups=Feed.digestGroups()
assert(#groups==1 and groups[1].name=="Scavenging" and groups[1].count==2,
    "caller-supplied groups replace the priority default")
-- The separator is ASCII by the owner UI rule (2026-11-04): the digest used
-- a middle dot, which the in-game font renders as a placeholder glyph.
assert(Feed.digestText():find("Scavenging, 2",1,true)~=nil,
    "the digest names the group and its real count")

Feed.clear()
Feed.note("One.",{key="same",now=40000})
Feed.note("One.",{key="same",now=40000+30001})
assert(#Feed.digest==2 and Feed.digest[2].count==1,
    "a repeated line outside the collapse window is a fresh event")

Feed.clear()
assert(Feed.digestText()==EMPTY_DIGEST,
    "an empty digest says so instead of showing an empty log")

getTimestampMs=savedTime
print("Notice rail PASS priority=true collapse=true digest_bound=true expiry=true groups=true speech_not_a_toast=true")