local P=assert(KnoxPersistence)
for _,id in ipairs({"one","two","three","four"}) do P.ensureSurvivorIdentity(id,"Soldier","Fixture",10,30) end
local oldRuntime,oldNeeds,oldSettings=KnoxSurvivorRuntime,KnoxSurvivorNeeds,KnoxSettings
P.ensureSurvivorIdentity("military-candidate","Applicant","Fixture",10,30)
local bitten=false
local visible=true
local leader={getX=function() return 0 end,getY=function() return 0 end,
    getZ=function() return 0 end,CanSee=function() return visible end}
local candidate={getX=function() return 1 end,getY=function() return 0 end,getZ=function() return 0 end}
KnoxSurvivorRuntime={getCharacter=function(id)
    if id=="military-candidate" then return candidate end
    if id=="military-leader" then return leader end
end}
KnoxSurvivorNeeds={biteReading=function(character)
    assert(character==candidate,"screening reads the actual candidate")
    return bitten
end}
KnoxSettings={npcFactionMinimumMembers=function() return 4 end}
local faction={kind="npc",background="military",leaderId="military-leader",memberIds={"one","two"}}
assert(P.militaryRecruitmentMode(faction,"military-candidate")=="recruit","understaffed military offers a clean civilian recruitment")
bitten=true
assert(P.militaryRecruitmentMode(faction,"military-candidate")=="hostile","a bitten applicant is not recruited")
bitten=nil
assert(P.militaryRecruitmentMode(faction,"military-candidate")=="screen","unknown wounds require screening instead of a clean diagnosis")
bitten=false;visible=false
assert(P.militaryRecruitmentMode(faction,"military-candidate")=="screen","hidden wounds are not known before visual contact")
visible=true
bitten=false; faction.memberIds={"one","two","three","four"}
assert(P.militaryRecruitmentMode(faction,"military-candidate")=="hostile","full-strength military retains its hostile policy")
faction.background="law_enforcement"
assert(P.militaryRecruitmentMode(faction,"military-candidate")==nil,"police never inherit military hostility")
KnoxSurvivorRuntime,KnoxSurvivorNeeds,KnoxSettings=oldRuntime,oldNeeds,oldSettings
