-- Production entry scoring; native world objects are replaced by fact tables.
-- Both halves matter: entryCandidateScore is the contract, doorEntryScore is
-- the single wiring point that a call site can no longer get wrong by shifting
-- the optional slots (which made every locked door score nil).
local Controller=codecEntryScore
assert(type(Controller)=="table" and type(Controller.entryCandidateScore)=="function",
    "entry candidate score is loaded")
assert(type(Controller.doorEntryScore)=="function","the door wiring is loaded")
local score=Controller.entryCandidateScore
local doorScore=Controller.doorEntryScore

local function doors(facts)
    local door={IsOpen=false,isBarricaded=false,isLocked=false}
    for key,value in pairs(facts or {}) do door[key]=value end
    return door
end

-- A door: open is free, unlocked is quiet, everything else needs force.
assert(doorScore(doors{IsOpen=true},false)==0,"an open door is free")
assert(doorScore(doors{IsOpen=false},false)==1,"an unlocked closed door is quiet")
assert(doorScore(doors{IsOpen=false,isBarricaded=true},true)==nil,
    "a barricaded door is refused even when force is allowed")
assert(doorScore(doors{IsOpen=false,isLocked=true},false)==nil,
    "a locked door without force is refused")
assert(doorScore(doors{IsOpen=false,isLocked=true},true)==4,
    "a locked door is forceable: the slot the shift used to swallow")
assert(doorScore(doors{IsOpen=false,isLockedByKey=true},true)==4,
    "a key-locked door is forceable")
assert(doorScore(nil,true)==nil,"a missing door never scores")

-- A window: climbing and the permanent lock both belong to the window branch.
assert(score("window",true,false,false,false,false,true,false)==2,
    "an open window is entered by climbing")
assert(score("window",true,false,false,false,false,false,false)==nil,
    "an open window nobody may climb is refused")
assert(score("window",false,true,false,false,false,true,false)==2,
    "a shattered window is climbed like an open one")
assert(score("window",false,false,false,false,false,true,false)==3,
    "a closed unlocked window is quiet")
assert(score("window",false,false,false,false,false,false,false)==3,
    "climbing does not gate a closed window")
assert(score("window",false,false,false,true,false,true,false)==nil,
    "a locked window without force is refused")
assert(score("window",false,false,false,true,false,true,true)==4,
    "a locked window is forceable")
assert(score("window",false,false,false,false,true,true,false)==nil,
    "a permanently locked window is refused even when unlocked")
assert(score("window",false,false,true,false,false,true,true)==nil,
    "a barricaded window is refused")

-- Anything that is neither a door nor a window must never win a score.
assert(score("unknown",true,false,false,false,false,true,true)==nil,
    "an unknown kind never scores")
assert(score(nil,true,false,false,false,false,true,true)==nil,
    "a missing kind never scores")
