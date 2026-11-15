local T=assert(KnoxMissionTargets)
local p=assert(KnoxPersistence)
local A=assert(KnoxSurvivorAutonomy)

-- The world map right-click used to return before offering anything whenever
-- the optional legacy command group was off (its default), so a crew armed in
-- the notebook opened the map and the click did nothing (owner report).
local O=assert(KnoxMapOrders)
assert(O.missionMapOffered(false,{memberIds={"a"}},false)==true,
    "an armed crew is offered the map order even with legacy commands off")
assert(O.missionMapOffered(false,nil,true)==false,
    "the legacy drive orders stay off while their toggle is off")
assert(O.missionMapOffered(true,nil,true)==true,
    "the legacy group still offers its own map orders when switched on")
assert(O.missionMapOffered(true,nil,false)==false,
    "no base and no crew offers nothing")
local oldRoot=data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"]=nil
local oldBridge,oldTime,oldBoundary=KnoxJavaBridge,getGameTime,codecDispatchBoundary
local pd={}
local point={getX=function() return 20 end,getY=function() return 30 end,getZ=function() return 0 end}
local player={getModData=function() return pd end,getX=point.getX,getY=point.getY,
    getZ=point.getZ,getCurrentSquare=function() return point end}
local owner=p.ensurePlayerId(player)
local base=assert(p.createBase("player",owner,{minX=20,minY=30,width=8,height=8,z=0},10,nil,true))
local ids={}
for i=1,8 do
    local id="map-crew-"..tostring(i)
    ids[i]=id
    assert(p.setRecord(id,expectedRecord))
    assert(p.setPlayerCompanion(id,owner,"hold",10))
    assert(p.setPlayerBaseResident(id,owner,base.id,10))
    controllers[id]={state="IDLE"}
end
local crew=A.missionCrewIds(player,base.id,"food",nil)
assert(#crew==8,"all eight residents must be selectable")
local opened=0
assert(T.armMap(0,base.id,"food",ids,{openMap=function() opened=opened+1 return true end}))
ids[1]="changed-after-confirm"
assert(opened==1 and #T.mapDraft(0).memberIds==8
    and T.mapDraft(0).memberIds[1]=="map-crew-1","map placement owns a copy of the confirmed crew")
local called=0
assert(not T.sendMap(0,player,500,600,0,{dispatch=function()
    called=called+1 return false,"crew_changed"
end}))
assert(called==1 and T.mapDraft(0)~=nil,"a rejected order keeps the chosen crew for review")
local boundaryMembers
codecDispatchBoundary=function(bridge,kind,oid,members,mission,destination,now,eta,returnPoint)
    boundaryMembers=members
    return true,assert(p.createAwayTeam(kind,oid,members,mission,destination,now,eta,returnPoint))
end
KnoxJavaBridge={}
getGameTime=function() return {getWorldAgeHours=function() return 12 end} end
assert(T.sendMap(0,player,500.9,600.8,0),"confirmed map dispatch reaches the existing mission owner")
assert(T.mapDraft(0)==nil and #boundaryMembers==8,"one dispatch sends the whole chosen crew")
local team=assert(p.getAwayTeamForSurvivor("map-crew-1"))
assert(team.destination.x==500 and team.destination.y==600 and team.destination.radius==80
    and team.destination.fillPacks==true,"exact map coordinates and fill-pack policy survive in the trip")
assert(#p.getBaseLastCrew(base.id,"food")==8,"remembered crews have no hidden three-person truncation")
assert(p.recordAwaySearch(team.id,"not-on-team",4,"searching",12)==false,"outsiders cannot update mission history")
assert(p.beginAwayTeamLiveArrival(team.id,13))
assert(p.beginAwayTeamCollection(team.id,13))
assert(p.recordAwaySearch(team.id,"map-crew-1",51,"searching",13))
assert(p.getAwayTeam(team.id).searchProgress["map-crew-1"].step==51,"search progress is durable")
p.advanceAwayTeams(200)
assert(p.getAwayTeam(team.id).state=="collecting","scarcity does not expire a fill-pack mission into an empty return")
assert(p.markSurvivorDead("map-crew-1",201,"fixture_observed_death"))
for i=2,8 do assert(p.recordAwayTeamCollection(team.id,"map-crew-"..tostring(i),{},202,true)) end
assert(p.awayTeamCollectionReady(team.id),"a recorded death cannot strand the surviving full crew")
assert(p.beginAwayTeamReturn(team.id,202))
assert(p.getAwayTeam(team.id).memberResults["map-crew-1"].success==false,
    "the dead member is never reported as returning alive")
for i=2,8 do assert(p.completeAwayTeamMember(team.id,"map-crew-"..tostring(i),true,"returned",203)) end
assert(p.getAwayTeam(team.id).state=="complete","survivors can complete the real return boundary")
assert(T.armMap(0,base.id,"food",{"map-crew-1"},{openMap=function() return true end}))
T.cancelMap(0)
assert(T.mapDraft(0)==nil,"cancel creates no trip")
assert(p.setRecord("map-lost",expectedRecord))
assert(p.setPlayerCompanion("map-lost",owner,"hold",204))
local lost=assert(p.createAwayTeam("player",owner,{"map-lost"},"food",
    {x=500,y=600,z=0,fillPacks=true},204,205,{x=20,y=30,z=0}))
assert(p.markSurvivorDead("map-lost",205,"fixture_observed_death"))
p.advanceAwayTeams(206)
assert(p.getAwayTeam(lost.id).state=="blocked" and p.getAwayTeam(lost.id).result.reason=="crew_lost",
    "canonical loss cannot leave an endless active mission or invent a return")
codecMissionGraph={["KnoxSurvivors_IsoPlayer"]=data["KnoxSurvivors_IsoPlayer"]}
function verifyMissionReload()
    local restored=assert(p.getAwayTeam(team.id))
    assert(#restored.memberIds==8 and restored.destination.fillPacks==true
        and restored.destination.radius==80,"native codec preserves the complete mission contract")
    assert(restored.searchProgress["map-crew-1"].step==51
        and #p.getBaseLastCrew(base.id,"food")==8,"native codec preserves search phase and uncapped remembered crew")
end
for i=1,8 do controllers["map-crew-"..tostring(i)]=nil end
KnoxJavaBridge,getGameTime,codecDispatchBoundary=oldBridge,oldTime,oldBoundary
data["KnoxSurvivors_IsoPlayer"]=oldRoot
print("Mission map crew PASS eight=true exactCrew=true map=true retry=true durable=true noFakeLoot=true")
