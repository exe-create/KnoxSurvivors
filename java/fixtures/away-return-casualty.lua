local P=assert(KnoxPersistence)
local oldRoot=data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"]=nil
local function returning(prefix)
    local ids={prefix.."-a",prefix.."-b"}
    for _,id in ipairs(ids) do
        assert(P.setRecord(id,expectedRecord))
        assert(P.setPlayerCompanion(id,"return-owner","hold",10))
    end
    local team=assert(P.createAwayTeam("player","return-owner",ids,"food",
        {x=100,y=100,z=0,radius=80,fillPacks=true},10,11,{x=0,y=0,z=0}))
    assert(P.beginAwayTeamLiveArrival(team.id,11))
    assert(P.beginAwayTeamCollection(team.id,11))
    for _,id in ipairs(ids) do assert(P.recordAwayTeamCollection(team.id,id,{},11,true)) end
    assert(P.beginAwayTeamReturn(team.id,11))
    return team,ids
end
local team,ids=returning("before-arrival")
assert(P.markSurvivorDead(ids[2],11.1,"fixture_observed_death"))
local result=assert(P.completeAwayTeamMember(team.id,ids[1],true,"returned",11.2))
assert(result.state=="complete","a canonical return-leg casualty cannot strand the arrived survivor")
assert(result.result.members[ids[1]].success and not result.result.members[ids[2]].success
    and result.result.members[ids[2]].reason=="died_on_mission","the outcome cannot resurrect a lost crew member")
local late,lateIds=returning("after-arrival")
assert(P.completeAwayTeamMember(late.id,lateIds[1],true,"returned",11.2))
assert(P.markSurvivorDead(lateIds[2],11.3,"fixture_observed_death"))
P.advanceAwayTeams(11.4,{returnMemberLoaded=function() return true end})
assert(P.getAwayTeam(late.id).state=="complete","late observed death resolves without a fabricated walk or timeout")
local history,historyIds=returning("later-life")
assert(P.completeAwayTeamMember(history.id,historyIds[1],true,"returned",11.2))
assert(P.markSurvivorDead(historyIds[1],11.3,"fixture_later_death"))
local ended=assert(P.completeAwayTeamMember(history.id,historyIds[2],true,"returned",11.4))
assert(ended.result.members[historyIds[1]].success,"a later death does not rewrite an already observed return")
data["KnoxSurvivors_IsoPlayer"]=oldRoot
print("Away return casualty PASS livingReturn=true canonicalLoss=true noTimeout=true priorHistoryPreserved=true")
