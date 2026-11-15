local p=KnoxPersistence
local oldPopulation=KnoxWorldPopulation
local population=KnoxWorldPopulation or {}
KnoxWorldPopulation=population
local prior=p.getAwayTeams
local priorCandidate=population.activationCandidate
local calls=0
p.getAwayTeams=function() return {
    ["away:alpha"]={state="collecting",memberIds={"alpha","beta"}},
    ["away:departing"]={state="outbound",memberIds={"not-arrived"}},
} end
population.activationCandidate=function(id,bridge,options)
    calls=calls+1
    assert(options.allowAwayMission and options.allowBlockedDispatchRecovery,
        "mission activation retains the real population gate options")
    return {id=id}
end
local result=codecMissionActivation(1,{})
assert(#result==1 and calls==1,"dictionary-keyed teams enter the existing activation budget")
calls=0
result=codecMissionActivation(4,{"alpha"})
assert(#result==1 and result[1].id=="beta" and calls==1,
    "already loaded members and outbound teams are not activated again")
p.getAwayTeams=prior
population.activationCandidate=priorCandidate
KnoxWorldPopulation=oldPopulation
print("Mission activation PASS dictionary=true budget=true loadedExcluded=true outboundExcluded=true")
