local C=assert(codecCountyOrigins)
local oldP=KnoxPersistence
local claimed=false
KnoxPersistence={getBaseAtSquare=function() return claimed and {id="claimed"} or nil end}
local function origin(key,building,context)
    return {key=key,buildingId=building,context=context,source="world_building",x=10,y=20,z=0}
end
local occupied=origin("occupied-new","family","generic")
local region={key="test",origins={origin("old","family","generic"),occupied,
    origin("station","police","law_enforcement"),origin("army","military","military"),
    origin("clinic","clinic","medical")}}
assert(C.next(region,{old=true},0,C.eligible).key=="clinic",
    "later arrivals avoid occupied households and professional garrison replacement")
claimed=true
assert(C.next(region,{old=true},0,C.eligible)==nil,"claimed property cannot receive a new arrival")
claimed=false
assert(not C.eligible({source="player_spawn",x=10,y=20},{}) and not C.eligible({},{}),
    "later arrivals require a real building origin")
KnoxPersistence.isIndependentSurvivor=function(id) return id~="recruited" end
KnoxPersistence.getTravelGroupFor=function(id) return id=="grouped" and {id="group"} or nil end
KnoxPersistence.getSurvivorCreatorRecord=function(id) return id=="authored" and {name="Authored Solo"} or nil end
KnoxPersistence.getSurvivorOrigin=function(id) return {context=id=="doctor" and "medical" or "generic"} end
assert(C.social("ordinary") and not C.social("authored") and not C.social("doctor")
    and not C.social("grouped") and not C.social("recruited"),
    "opening groups respect authored rosters, independent doctors and existing membership")
KnoxPersistence=oldP

local state={initialized=true,lastTarget=3}
local ids={"one","two"}
local target,uncapped,days=3,false,1
local serial,calls,exhausted=0,0,false
local maintain=openingBudgetFactory({world={spawnCatalog=function() return {} end},
    settings={worldPopulation=function() return target end,capsDisabled=function() return uncapped end,
        populationRefillDays=function() return days end},
    persistence={getPopulationState=function() return state end,getLivingWorldSurvivorIds=function() return ids end,
        getUsedWorldOriginKeys=function() return {} end},regionCounts=function() return {} end,
    general=function()
        calls=calls+1
        if exhausted then return nil,"spawn_origins_exhausted" end
        serial=serial+1;local id="new"..serial;ids[#ids+1]=id;return id
    end})
assert(maintain(0).status=="waiting" and state.nextRefillHours==24,"shortage starts a full arrival interval")
assert(maintain(23).status=="waiting" and calls==0,"no premature replenishment")
assert(maintain(24).status=="refilled" and #ids==3 and state.nextRefillHours==0,"one scheduled arrival reaches the target")
table.remove(ids,1)
assert(maintain(48).status=="waiting" and state.nextRefillHours==72,"a later loss waits rather than replacing immediately")
assert(maintain(200).status=="refilled" and calls==2,"a long absence produces one arrival without catch-up burst")
table.remove(ids,1);days=0
assert(maintain(201).status=="refill_disabled" and state.nextRefillHours==0,"finite population remains finite")
days=1
assert(maintain(202).status=="waiting" and state.nextRefillHours==226,"reenabling arrivals starts a fresh interval")
uncapped=true
assert(maintain(226).status=="arrived" and #ids==3 and state.nextRefillHours==250,"uncapped arrivals retain their cadence")
assert(maintain(250).status=="arrived" and #ids==4,"uncapped population may grow above the opening target")
exhausted=true
assert(maintain(274).status=="spawn_origins_exhausted" and #ids==4 and state.nextRefillHours==298,
    "exhaustion waits honestly and never invents or resurrects a person")
print("Population continuity PASS laterOrigins=true cadence=true finite=true uncapped=true noCatchUp=true nativeGameplay=NOT_VERIFIED")
