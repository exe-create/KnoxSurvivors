local P = KnoxPersistence
local oldRoot, oldManager, oldCell = ModData.getOrCreate, KnoxBaseManager, getCell
local world = {}
ModData.getOrCreate = function(key) if key == "KnoxSurvivors_IsoPlayer" then return world end return oldRoot(key) end
local function cohort(n, military)
    local ids = {}
    for i=1,3 do ids[i] = assert(P.allocateWorldSurvivor({x=n+i,y=41000,z=0,source="world_building",buildingId=tostring(n),region="R",context=military and "military" or "residential"},1)) end
    local group = assert(P.createTravelGroup(ids,1))
    group.originCohort = military
    return group, ids
end
local commandGroup = cohort(100,true)
local command = assert(P.promoteTravelGroupToFaction(commandGroup.id,1))
local incoming, ids = cohort(200,true)
local unrelated = {id="invalid",kind="npc",memberIds={"missing"},homeBaseId="missing"}
world.factions.invalid = unrelated
local originalSort = table.sort
local area={buildingId="1",minX=0,minY=0,width=1,height=1}
command.homeBase=area
local beds=5
KnoxBaseManager={discoverFactionBeds=function() local found={} for i=1,beds do found[i]={} end return found end}
getCell=function() return {getGridSquare=function() return {} end} end
local priorNext = world.nextFactionId
local blocked=world.survivors[ids[2]]
local originalPrint=print
local notices=0
print=function() notices=notices+1 end
local function denied(expected)
    local value, why=P.promoteTravelGroupToFaction(incoming.id,2)
    assert(value==nil and why==expected and incoming.factionId==nil and #incoming.memberIds==3, "preflight denies unavailable member without mutation")
end
blocked.alive=false; denied("dead"); blocked.alive=true
blocked.eventManaged=true; denied("event_managed"); blocked.eventManaged=nil
blocked.departure={status="pending"}; denied("departing"); blocked.departure=nil
world.awayTeams.fixture={id="fixture"}; blocked.duty.awayTeamId="fixture"; denied("away_team"); blocked.duty.awayTeamId=nil; world.awayTeams.fixture=nil
local oldAffiliation=blocked.affiliation
blocked.affiliation={kind="player"}; denied("player_affiliated"); blocked.affiliation=oldAffiliation
assert(notices==0, "refusals do not emit notices")
print=originalPrint
local result, reason = P.promoteTravelGroupToFaction(incoming.id,2)
assert(result == nil and reason == "at_capacity", "real capacity refuses entire cohort")
assert(incoming.factionId == nil and #incoming.memberIds == 3 and #command.memberIds == 3 and world.factions.invalid == unrelated and unrelated.homeBaseId == "missing" and world.nextFactionId == priorNext, "refusal preserves world and unrelated invalid record")
beds=6
for failure=1,3 do
    local count=0
    local roster=command.memberIds
    local join=command.memberJoinedAtHours
    local affiliation={world.survivors[ids[1]].affiliation,world.survivors[ids[2]].affiliation,world.survivors[ids[3]].affiliation}
    table.sort=function(value, ...) if value==command.memberIds then count=count+1; if count==failure then error("injected") end end return originalSort(value, ...) end
    local value, why=P.promoteTravelGroupToFaction(incoming.id,2)
    assert(value==nil and why:find("injected",1,true) ~= nil, "injected member failure returns no linked faction")
    assert(command.memberIds==roster and command.memberJoinedAtHours==join and incoming.factionId==nil and #incoming.memberIds==3 and world.nextFactionId==priorNext, "failed military write restores references")
    for i=1,3 do assert(world.survivors[ids[i]].affiliation==affiliation[i], "failed military write restores affiliation identity") end
end
table.sort=originalSort
local commandRoster, commandJoins, memberAffiliation = command.memberIds, command.memberJoinedAtHours, world.survivors[ids[1]].affiliation
assert(P.promoteTravelGroupToFaction(incoming.id,2)==command and #command.memberIds==6 and #incoming.memberIds==3, "whole military cohort joins")
assert(command.memberIds==commandRoster and command.memberJoinedAtHours==commandJoins and world.survivors[ids[1]].affiliation==memberAffiliation, "success preserves existing membership references")
local existing, existingIds=cohort(250,true)
command.memberIds[#command.memberIds+1]=existingIds[1]
world.survivors[existingIds[1]].affiliation={kind="faction",factionId=command.id}
beds=9
assert(P.promoteTravelGroupToFaction(existing.id,2)==command and #command.memberIds==9, "existing member does not consume an extra admission at exact capacity")
local ordinary, ordinaryIds=cohort(300,false)
for failure=1,3 do
    local count=0
    table.sort=function(value, ...) local target=world.factions["faction-"..tostring(world.nextFactionId)]; if target and value==target.memberIds then count=count+1; if count==failure then error("injected") end end return originalSort(value, ...) end
    local nextId=world.nextFactionId
    local value, why=P.promoteTravelGroupToFaction(ordinary.id,2)
    assert(value==nil and why:find("injected",1,true) ~= nil and world.nextFactionId==nextId and world.factions["faction-"..tostring(nextId)]==nil and ordinary.factionId==nil and #ordinary.memberIds==3, "ordinary write failure restores ID and group")
end
table.sort=originalSort
local faction, why=P.promoteTravelGroupToFaction(ordinary.id,2)
assert(faction and why=="created" and #faction.memberIds==3 and #ordinary.memberIds==3, "ordinary cohort created together")
local transfer, transferIds=cohort(400,false)
local former, formerIds=cohort(500,false)
local formerFaction=assert(P.promoteTravelGroupToFaction(former.id,1))
local moving=world.survivors[transferIds[1]]
formerFaction.memberIds[#formerFaction.memberIds+1]=transferIds[1]
formerFaction.memberJoinedAtHours[transferIds[1]]=7
moving.affiliation={kind="faction",factionId=formerFaction.id}
moving.duty={mode="base",baseId="transfer-base",revision=4}
moving.policies.assignedBed={autoFactionId=formerFaction.id,autoBaseId="transfer-base"}
local task={state="claimed",claimedBy=transferIds[1],claimedAtHours=3,manual=true}
world.bases["transfer-base"]={id="transfer-base",ownerKind="faction",ownerId=formerFaction.id,tasks={one=task}}
local newFaction=assert(P.promoteTravelGroupToFaction(transfer.id,9))
assert(moving.affiliation.factionId==newFaction.id and moving.duty.mode=="autonomous" and moving.duty.revision==5, "transfer updates affiliation and duty")
assert(moving.policies.assignedBed==nil and task.state=="queued" and task.claimedBy==nil, "transfer clears bed and releases claim")
assert(formerFaction.memberJoinedAtHours[transferIds[1]]==nil, "transfer clears former join time")
KnoxBaseManager=oldManager
getCell=oldCell
ModData.getOrCreate=oldRoot
print("Promotion transaction PASS")
