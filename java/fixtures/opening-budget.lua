local planner=assert(WorldPopulation.openingSitePlan)
local function scenario(budget,target,refused)
    local state,used,ids,order={},{},{},{}
    local calls,plans,groups,general,peak=0,0,0,0,0
    local catalog={origins={}}
    for _,site in ipairs({{"barracks","military",4},{"station","law_enforcement",4},{"home","generic",3}}) do
        for n=1,site[3] do catalog.origins[#catalog.origins+1]={key=site[1]..n,source="world_building",
            buildingId=site[1],regionKey=site[1],context=site[2],household=site[1]=="home"} end
    end
    local dependencies={world={spawnCatalog=function() return catalog end,openingSitePlan=function(...)
            plans=plans+1;return planner(...) end},
        settings={worldPopulation=function() return target end,capsDisabled=function() return false end,
            populationRefillDays=function() return 1 end,initialGroupCount=function() return 3 end,
            allowNPCFactions=function() return true end,initialFactionCount=function() return 3 end,
            npcFactionMinimumMembers=function() return 4 end},
        persistence={getPopulationState=function() return state end,getLivingWorldSurvivorIds=function() return ids end,
            getUsedWorldOriginKeys=function() return used end},regionCounts=function() return {} end,
        allocate=function(origin)
            calls=calls+1
            if refused.value then return nil,"allocation_refused" end
            assert(not used[origin.key],"no duplicate origin is allocated")
            used[origin.key]=true;ids[#ids+1]=origin.key;order[#order+1]=origin.key
            return origin.key
        end,
        general=function()
            calls=calls+1;general=general+1
            local id="general"..general;ids[#ids+1]=id;return id
        end,
        groups=function(all,now,s)
            groups=groups+1;assert(#all==target,"social formation waits for the entire opening population")
            s.initialGroupsCreated=true
        end}
    local maintain=openingBudgetFactory(dependencies)
    local function step(now)
        local previous=calls
        local result=maintain(now,{initialAllocationBudget=budget})
        peak=math.max(peak,calls-previous)
        assert(calls-previous<=budget,"allocation work exceeds budget: observed="..(calls-previous).." budget="..budget)
        assert(#result.addedIds<=budget and result.living==#ids,"reported population matches actual allocation")
        return result
    end
    return {step=step,state=state,ids=ids,order=order,dependencies=dependencies,
        stats=function() return plans,groups,general,peak end}
end
local refusal={value=false}
local small=scenario(2,13,refusal)
assert(small.step(10).status=="initializing" and not small.state.openingSitesSeeded,"partial reservation yields without claiming completion")
for n=1,5 do small.step(10+n) end
assert(#small.ids==12 and small.state.openingSitesSeeded,"reserved sites finish before general allocation")
assert(small.step(20).status=="initialized" and #small.ids==13,"the final partial batch initializes once")
local plans,groups,general=small.stats()
assert(plans==1 and groups==1 and general==2,"one cached plan, one social pass, exact general remainder")
assert(small.order[1]=="barracks1" and small.order[5]=="station1" and small.order[9]=="home1",
    "batching preserves facility and household ordering")
local large=scenario(24,13,{value=false})
assert(large.step(10).status=="initialized","a larger budget may complete the same population in one pass")
for n,key in ipairs(small.order) do assert(large.order[n]==key,"budget cannot change reserved identities or sites") end
local blockedFlag={value=true}
local blocked=scenario(2,13,blockedFlag)
assert(blocked.step(10).status=="allocation_refused" and not blocked.state.openingSitesSeeded,
    "failed reservation stays pending with its actual reason")
local _,groupCalls,generalCalls=blocked.stats()
assert(groupCalls==0 and generalCalls==0 and #blocked.ids==0,"refusal cannot fall through to general fill or social formation")
blockedFlag.value=false
assert(blocked.step(11).status=="initializing" and #blocked.ids==2,"a refused opening allocation retries after its dependency recovers")
-- Resume after reload: only the seed and allocated identities are durable.
local reloaded=scenario(2,13,{value=false})
reloaded.step(10)
local seed=reloaded.state.initialGroupSeedHours
local fresh=openingBudgetFactory(reloaded.dependencies)
fresh(99,{initialAllocationBudget=2})
assert(#reloaded.ids==4 and reloaded.state.initialGroupSeedHours==seed,"reload skips used origins and preserves the opening seed")
local tiny=scenario(1,1,{value=false})
assert(tiny.step(10).status=="initialized" and #tiny.ids==1,"a tiny target never gains a whole bonus garrison")
print("Opening budget PASS maxPerPass=2 reserved=11 general=2 cachedPlans=1 refusalRetained=true reloadResume=true nativeFrameTime=NOT_VERIFIED")

local _,_,_,peak=small.stats()
return '{"allocationBudget":2,"observedPeakAllocations":'..peak..',"reservedOrigins":'..#small.order..',"generalAllocations":'..general..',"planBuilds":'..plans..',"socialPasses":'..groups..',"nativeFrameTimeVerified":false}'
