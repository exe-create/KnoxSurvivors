local C=assert(KnoxAutonomyController)
local P=assert(KnoxPersistence)
local oldRoot=data["KnoxSurvivors_IsoPlayer"]
local oldCell=getCell
data["KnoxSurvivors_IsoPlayer"]=nil
local id="handoff-member"
assert(P.setRecord(id,expectedRecord))
assert(P.setPlayerCompanion(id,"handoff-owner","hold",10))
local team=assert(P.createAwayTeam("player","handoff-owner",{id},"food",
    {x=100,y=100,z=0,radius=80,fillPacks=true},10,11,{x=0,y=0,z=0}))
assert(P.beginAwayTeamLiveArrival(team.id,11))
assert(P.beginAwayTeamCollection(team.id,11))
assert(P.recordAwaySearch(team.id,id,17,"searching",11))
local square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
local actor={getCurrentSquare=function() return square end}
local c=setmetatable({id=id,character=actor},C)
c:setAwayTeam(team.id)
assert(c.awaySearchStep==17 and c.state=="IDLE","the installed mission methods restore the durable search phase")
getCell=function() return {getGridSquare=function() return nil end} end
assert(c:beginAwayTravel(100,P.getAwayTeam(team.id)),"missing native squares retain travel ownership")
assert(c.activeDecision=="away_waiting_for_world" and c.nextThink>100,
    "unloaded travel is a bounded wait, never a fabricated collection")
assert(P.getAwayTeam(team.id).collection==nil,"waiting cannot create cargo receipts")
local cancelled=assert(P.cancelAwayTeam(team.id,"fixture_cancel",12))
assert(c:clearFinishedAwayTeam(101,cancelled),"a finished ledger releases loaded mission ownership")
assert(c.awayTeamId==nil and c.activeDecision==nil and c.state=="IDLE" and c.nextThink<=101,
    "all mission wait decisions release immediately on a finished trip")
for _,decision in ipairs({"away_continue_search","away_search_wait","away_waiting_for_world"}) do
    c.awayTeamId=team.id;c.activeDecision=decision;c.nextThink=999
    assert(c:clearFinishedAwayTeam(102,cancelled) and c.activeDecision==nil and c.nextThink<=102,
        "each resource-search decision uses the same finished-team handoff")
end
getCell=oldCell
data["KnoxSurvivors_IsoPlayer"]=oldRoot
print("Mission controller handoff PASS sameController=true durablePhase=true unloadedWait=true finishedRelease=true")
