-- Production traversal memory; edges and the clock are doubles.
local Controller=codecTraversalMemory
assert(type(Controller)=="table" and type(Controller.traversalMemoryGet)=="function",
    "traversal memory is loaded")
local savedGameTime=getGameTime
local hours=12
getGameTime=function() return {getWorldAgeHours=function() return hours end} end

local function edge(open,locked,barricaded)
    return {IsOpen=open==true,isLocked=locked==true,isBarricaded=barricaded==true,
        isSmashed=false,isPermaLocked=false}
end
local function owner()
    return setmetatable({id="survivor-1"},{__index=Controller})
end
local function get(who,object,kind) return Controller.traversalMemoryGet(who,object,kind) end
local function record(who,object,kind,reason,inside)
    return Controller.traversalMemoryRecord(who,object,kind,reason,inside,nil,100)
end
local function fail(who,object,kind,reason,inside)
    return Controller.traversalMemoryRecordFailure(who,object,kind,reason,inside,nil,120)
end

local who=owner()
local door=edge(false,true,false)
assert(get(who,door,"door")==nil,"an unseen edge is not blocked")
record(who,door,"door","selected")
local entry=get(who,door,"door")
assert(entry~=nil and entry.reason=="selected" and entry.failures==0,
    "a selected edge is remembered before its failure")
door.IsOpen=true
assert(get(who,door,"door")==nil,"a changed door earns one fresh attempt")
door.IsOpen=false
record(who,door,"door","selected")
fail(who,door,"door","locked")
entry=get(who,door,"door")
assert(entry.failures==1 and entry.reason=="locked","a locked edge records one failure")
assert(Controller.traversalMemoryForceAllowed(who,door,"door"),
    "one locked failure still allows a single forced attempt")
Controller.traversalMemoryMarkForced(who,door,"door",140)
assert(not Controller.traversalMemoryForceAllowed(who,door,"door"),
    "a forced attempt spends the force budget")
assert(get(who,door,"door").forced==true)
assert(get(who,door,"window")==nil,"an edge is remembered by kind as well as object")

local expiring=owner()
local window=edge(false,false,false)
record(expiring,window,"window","selected")
fail(expiring,window,"window","locked")
hours=12+0.15
assert(get(expiring,window,"window")~=nil,"the memory lasts inside ten game minutes")
hours=12+0.17
assert(get(expiring,window,"window")==nil,"the memory expires after ten game minutes")

local capped=owner()
local first=edge(false,false,false)
record(capped,first,"door","selected")
for index=1,30 do record(capped,edge(false,false,false),"door","selected") end
assert(#capped.traversalMemoryState.entries==24,"the memory is bounded to twenty-four edges")
assert(get(capped,first,"door")==nil,"the oldest edge is evicted first")

local counts=owner()
local center={getX=function() return 10 end,getY=function() return 10 end}
local function at(x,y) return {getX=function() return x end,getY=function() return y end} end
fail(counts,edge(false,false,false),"window","locked",at(11,10))
fail(counts,edge(false,false,false),"window","locked",at(9,11))
assert(Controller.traversalMemoryClosedCountNear(counts,center,20)==2,
    "two closed windows in this approach are visible to the next search")
fail(counts,edge(false,false,false),"window","locked",at(100,100))
assert(Controller.traversalMemoryClosedCountNear(counts,center,20)==2,
    "a closed window in another building does not suppress this approach")
record(counts,edge(false,false,false),"door","selected",at(10,10))
assert(Controller.traversalMemoryClosedCountNear(counts,center,20)==2,
    "a selected door is not a closed window")

local timer=owner()
assert(Controller.traversalResumeRetry(timer,100)==true)
assert(Controller.traversalResumeRetry(timer,249)==true,
    "the native handoff retry holds the crossing state")
assert(Controller.traversalResumeRetry(timer,250)==false,
    "the handoff retry gives up after 150 ticks")
assert(Controller.traversalResumeRetry(timer,251)==true,
    "a later failure gets its own bounded retry")

local forgetful=owner()
local reused=edge(false,false,false)
record(forgetful,reused,"door","selected")
Controller.traversalMemoryForget(forgetful,reused)
assert(get(forgetful,reused,"door")==nil,
    "a successful traversal is not remembered as a failure")

-- 2026-11-02: a window must never be asked for a door-only getter. In Kahlua a
-- missing Java method is a hard failure, so these objects raise on any field
-- their kind does not own, the way the game did (console f:27650).
local function strict(values,forbidden)
    return setmetatable(values,{__index=function(_,key)
        for _,name in ipairs(forbidden) do
            if key==name then error("binding failure: "..tostring(key)) end
        end
        return nil
    end})
end
local windowOwner=owner()
local strictWindow=strict({IsOpen=false,isSmashed=false,isBarricaded=false,isLocked=false},
    {"isPermaLocked","isLockedByKey"})
record(windowOwner,strictWindow,"window","locked")
local windowEntry=get(windowOwner,strictWindow,"window")
assert(windowEntry~=nil,"a window is fingerprinted without a door-only getter")
assert(not string.find(windowEntry.worldState,"isPermaLocked",1,true),
    "a window is never asked for isPermaLocked: "..tostring(windowEntry.worldState))
assert(string.find(windowEntry.worldState,"isSmashed=false",1,true)~=nil,
    "a window's smashed state is part of its fingerprint")
strictWindow.isSmashed=true
assert(get(windowOwner,strictWindow,"window")==nil,
    "shattering the window is a world change and earns one fresh attempt")

local doorOwner=owner()
local strictDoor=strict({IsOpen=false,isLocked=false,isBarricaded=false,isLockedByKey=false},
    {"isSmashed","isPermaLocked"})
record(doorOwner,strictDoor,"door","locked")
local doorEntry=get(doorOwner,strictDoor,"door")
assert(doorEntry~=nil,"a door is fingerprinted without window-only getters")
assert(not string.find(doorEntry.worldState,"isSmashed",1,true),
    "a door is never asked for isSmashed: "..tostring(doorEntry.worldState))
assert(string.find(doorEntry.worldState,"isLockedByKey=false",1,true)~=nil,
    "a door's key locking is part of its fingerprint")

local bareOwner=owner()
local bareEdge=strict({IsOpen=false},
    {"isSmashed","isBarricaded","isLocked","isLockedByKey","isPermaLocked"})
record(bareOwner,bareEdge,nil,"selected")
assert(get(bareOwner,bareEdge,nil)~=nil,
    "an edge of unknown kind is fingerprinted by its open state only")

getGameTime=savedGameTime
print("Traversal memory PASS expiry=true world_change=true force_budget=true cap=true resume_retry=true")