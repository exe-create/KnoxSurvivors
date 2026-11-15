local P=assert(KnoxPersistence)
local oldRoot=ModData.getOrCreate
local isolated={}
ModData.getOrCreate=function(key)
    if key=="KnoxSurvivors_IsoPlayer" then return isolated end
    return oldRoot(key)
end
local old={runtime=KnoxSurvivorRuntime,settings=KnoxSettings,needs=KnoxSurvivorNeeds,safe=SafeHouse,protection=KnoxFactionSafehouse}
local function cohort(building,x,context)
    local ids={}
    for i=1,3 do
        ids[i]=assert(P.allocateWorldSurvivor({x=x+i,y=29000,z=0,source="world_building",
            buildingId=building,region="Rosewood, KY",context=context or "military"},50))
    end
    local group=assert(P.createTravelGroup(ids,50))
    group.originCohort=true;group.background=context or "military"
    return group,ids
end
local a,aid=cohort("military-fixture-a",28000)
local command=assert(P.promoteTravelGroupToFaction(a.id,50,3))
assert(command.name=="Fort Knox Military" and command.militaryCommand,"military has the shared command identity")
local b,bid=cohort("military-fixture-b",28100)
local second,why=P.promoteTravelGroupToFaction(b.id,50,3)
assert(second==command and why=="linked_military_command" and #command.memberIds==6,
    "separate military facilities join one faction")
assert(P.getTravelGroupFor(aid[1])==a and P.getTravelGroupFor(bid[1])==b and a~=b,
    "local garrisons keep distinct travel groups")
assert(P.promoteTravelGroupToFaction(b.id,50,3)==command and #command.memberIds==6,
    "linking again cannot duplicate members")
local civilian,cid=cohort("civilian-fixture",28200,"residential")
assert(not P.isMilitaryCohort(civilian),"a civilian cohort cannot inherit military command")
local police,pid=cohort("police-fixture",28300,"law_enforcement")
local policeFaction=assert(P.promoteTravelGroupToFaction(police.id,50,3))
assert(policeFaction~=command and policeFaction.name:find("Rosewood",1,true),"police retain town identity and their own faction")

local characters={}
KnoxSurvivorRuntime={getCharacter=function(id) return characters[id] end,notifyDutyChanged=function() end}
KnoxSettings={autoGenerateBaseWorkAreas=function() return false end,npcFactionMinimumMembers=function() return 4 end}
SafeHouse={getSafehouseOverlapping=function() return nil end}
KnoxFactionSafehouse=nil
local Manager=militaryOutpostFactory({applyFactionIntent=function() end,factionIntentFacts=function() return {} end})
assert(Manager.ensureMilitaryOutposts(command)==0,"unloaded origins cannot invent established bases")
local function character(building,x)
    local definition={getID=function() return building end,getX=function() return x end,
        getY=function() return 29000 end,getW=function() return 10 end,getH=function() return 10 end}
    local square={getX=function() return x+1 end,getY=function() return 29001 end,getZ=function() return 0 end,
        getBuilding=function() return {getDef=function() return definition end} end}
    return {getCurrentSquare=function() return square end,getX=function() return x+1 end,
        getY=function() return 29001 end,getZ=function() return 0 end,CanSee=function() return true end}
end
characters[aid[1]]=character("military-fixture-a",28000)
characters[bid[1]]=character("military-fixture-b",28100)
assert(Manager.ensureMilitaryOutposts(command)==2,"physical arrival establishes both real garrison bases")
local bases=P.getBasesForOwner("faction",command.id)
assert(#bases==2 and bases[1].ownerId==bases[2].ownerId,"both bases have one faction owner")
local firstDuty,secondDuty=P.getSurvivorDuty(aid[1]),P.getSurvivorDuty(bid[1])
assert(firstDuty.baseId~=secondDuty.baseId,"garrisons reside at their own facilities")
Manager.ensureFactionBase(command)
assert(P.getSurvivorDuty(aid[1]).baseId==firstDuty.baseId
    and P.getSurvivorDuty(bid[1]).baseId==secondDuty.baseId,"primary refresh preserves outpost duty")
local ownerLookup=P.getBasesForOwner
local ownerLookups=0
P.getBasesForOwner=function(...) ownerLookups=ownerLookups+1;return ownerLookup(...) end
local refreshed=Manager.ensureMilitaryOutposts(command)
P.getBasesForOwner=ownerLookup
assert(refreshed==0 and #P.getBasesForOwner("faction",command.id)==2,"refresh never duplicates a base")
assert(ownerLookups==1,"garrison refresh indexes owned bases once rather than sorting the owner roster per site")
assert(P.setFactionResidentBed(bid[1],command.id,secondDuty.baseId,{x=28102,y=29002,z=0,objectIndex=1},50),
    "an outpost resident may use a real bed reference at the outpost")
P.ensureSurvivorIdentity("military-local-applicant","Local","Applicant",50,30)
characters["military-local-applicant"]=character("military-fixture-b",28100)
KnoxSurvivorNeeds={biteReading=function() return false end}
assert(P.militaryRecruitmentMode(command,"military-local-applicant",bid[1])=="recruit",
    "a low-manpower base recruits even when the wider command has enough members")
assert(P.militaryRecruitmentMode(command,"military-local-applicant",pid[1])=="screen",
    "a police officer cannot authorize a military recruitment screening")
assert(P.setRecord("military-local-applicant",expectedRecord),"the applicant has a materialized native record")
assert(P.addTravelGroupMember(b.id,"military-local-applicant")==b,"the local garrison admits the screened applicant")
assert(P.getSurvivorDuty("military-local-applicant").baseId==secondDuty.baseId,
    "recruitment places a recruit at the recruiting garrison, not command headquarters")
assert(#P.getBaseResidentIds(secondDuty.baseId)==4 and #P.getBaseResidentIds(firstDuty.baseId)==3,
    "actual local manpower grows where the recruitment took place")
Manager.ensureFactionBase(command)
assert(P.getSurvivorDuty("military-local-applicant").baseId==secondDuty.baseId,"primary refresh preserves the recruit's local base")
local c,third=cohort("military-fixture-c",28400)
assert(P.promoteTravelGroupToFaction(c.id,50,3)==command)
characters[third[1]]=character("wrong-building",28400)
assert(Manager.ensureMilitaryOutposts(command)==0,"standing in another building cannot claim the origin")
characters[third[1]]=character("military-fixture-c",28400)
assert(P.createBase("player","fixture-player",{buildingId="occupied",x=28401,y=29001,z=0,
    minX=28400,minY=29000,width=10,height=10},50))
assert(Manager.ensureMilitaryOutposts(command)==0,"military never overwrites existing property")
KnoxSurvivorRuntime,KnoxSettings,KnoxSurvivorNeeds,SafeHouse,KnoxFactionSafehouse=old.runtime,old.settings,old.needs,old.safe,old.protection
ModData.getOrCreate=oldRoot
print("Military command PASS sharedFaction=true localGroups=true bases=2 localDuty=true noTeleport=true noPropertyOverwrite=true")
