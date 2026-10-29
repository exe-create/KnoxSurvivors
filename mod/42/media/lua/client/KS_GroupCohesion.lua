-- Loaded by the population/survival owners; do not initialize world persistence
-- or engine events merely to inspect this policy.
local Cohesion={}
KnoxGroupCohesion=Cohesion
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
function Cohesion.snapshot(members)
    local result={}
    for _,member in ipairs(members) do
        local s=member.state
        result[member.id]={x=s.virtualX,y=s.virtualY,z=s.virtualZ,hours=s.lastHours}
    end
    return result
end
local function close(a,b)
    return a~=nil and b~=nil and finite(a.x) and finite(a.y) and finite(a.z)
        and finite(b.x) and finite(b.y) and finite(b.z) and a.z==b.z
        and (a.x-b.x)^2+(a.y-b.y)^2<=32*32
end
function Cohesion.record(group,before,members,hours,groupCandidates)
    if group==nil or group.factionId~=nil or not finite(hours) then return nil end
    local after=Cohesion.snapshot(members)
    -- Only the complete, canonical autonomous cohort can supply this evidence.
    -- Real bodies, needs and movement remain with the calling simulation owner.
    if #members~=#(group.memberIds or {}) then return nil end
    for _,id in ipairs(group.memberIds) do
        local duty=KnoxPersistence.getSurvivorDuty(id)
        local affiliation=KnoxPersistence.getSurvivorAffiliation(id)
        local canonical=KnoxPersistence.getTravelGroupFor(id,groupCandidates)
        if before[id]==nil or after[id]==nil or not KnoxPersistence.isSurvivorAlive(id)
            or duty==nil or duty.mode~="autonomous" or (affiliation~=nil and affiliation.kind=="player")
            or canonical==nil or canonical.id~=group.id then return nil end
    end
    local previous=tonumber(group.cohesionAtHours) or 0
    for i=1,#group.memberIds do
        local a=group.memberIds[i]
        for j=i+1,#group.memberIds do
            local b=group.memberIds[j]
            local first,second=before[a],before[b]
            if finite(first.hours) and finite(second.hours) and close(first,second) and close(after[a],after[b]) then
                local joined=group.memberJoinedAtHours or {}
                local start=math.max(first.hours,second.hours,previous,hours-48,
                    tonumber(joined[a]) or 0,tonumber(joined[b]) or 0)
                local elapsed=math.max(0,hours-start)
                local relationship=KnoxPersistence.getRelationship(a,b)
                -- recordEncounter deliberately caps one observation at 15 game
                -- minutes. Credit the verified interval in bounded pieces, up
                -- to the one shared hour needed for faction readiness.
                local remaining=math.min(elapsed,math.max(0,1-(relationship~=nil and relationship.nearbyHours or 0)))
                for _=1,math.ceil(remaining/0.25) do
                    local span=math.min(0.25,remaining)
                    KnoxPersistence.recordEncounter(a,b,{worldAgeHours=hours-remaining+span,began=false,nearbyHours=span})
                    remaining=remaining-span
                end
            end
        end
    end
    group.cohesionAtHours=math.max(previous,hours)
    if KnoxSettings~=nil and KnoxSettings.allowNPCFactions~=nil and not KnoxSettings.allowNPCFactions() then return nil end
    local minimum=KnoxSettings~=nil and KnoxSettings.npcFactionMinimumMembers~=nil
        and KnoxSettings.npcFactionMinimumMembers() or 4
    local faction,reason=KnoxPersistence.evaluateTravelGroupFaction(group.id,hours,minimum)
    if faction~=nil and reason=="created" then
        print("[KnoxSurvivors][Relationships] faction-formed="..faction.id.." source=shared_unloaded_survival")
    end
    return faction,reason
end
return Cohesion
