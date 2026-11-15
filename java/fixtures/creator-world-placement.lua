local C = KnoxCreator
local W = KnoxCreatorWorld
local oldP, oldWorld = KnoxPersistence, KnoxWorldPopulation
local oldSpawn, oldPlan, oldPrepared = C.spawnPending, C.pendingWorldPlan, C.preparedPopulation
W.install(C)
local function site(building, number, context, home)
    return {source="world_building", buildingId=building, key=building .. number, x=number, y=number, z=0,
        context=context, household=home, residential=home, professionCandidates={"base:unemployed"}}
end
local catalog = {origins={ site("home1",1,"residential",true), site("home1",2,"residential",true),
    site("home2",1,"residential",true), site("home2",2,"residential",true),
    site("police",1,"law_enforcement"), site("police",2,"law_enforcement") }}
local state, origins, records, alive, groups, nextId = {}, {}, {}, {}, {}, 0
KnoxWorldPopulation = {spawnCatalog=function() return catalog end}
KnoxPersistence = {
    getPopulationState=function() return state end,
    getAllWorldSurvivorIds=function() local ids={} for id in pairs(origins) do ids[#ids+1]=id end return ids end,
    getLivingWorldSurvivorIds=function() local ids={} for id in pairs(alive) do if alive[id] then ids[#ids+1]=id end end return ids end,
    getUsedWorldOriginKeys=function() local used={} for _,o in pairs(origins) do used[o.key]=true end return used end,
    getSurvivorOrigin=function(id) return origins[id] end,
    getSurvivorCreatorRecord=function(id) return records[id] end,
    allocateWorldSurvivor=function(origin) nextId=nextId+1; local id="s"..nextId; origins[id]=origin; alive[id]=true; return id end,
    setSurvivorCreatorRecord=function(id, record) records[id]=record; return true end,
    getTravelGroupFor=function(id) return groups[id] end,
    createTravelGroup=function(ids) local g={id="g"..ids[1]}; for _,id in ipairs(ids) do groups[id]=g end; return g end,
    promoteTravelGroupToFaction=function() return {} end,
}
-- Two households, each its own group, plus a police detail: the creator makes
-- instances, so their ids are per group rather than shipped kind ids.
local defs = {}
local okHomeA, homeA = C.addFaction(defs, "Barley", "household")
local okHomeB, homeB = C.addFaction(defs, "Voss", "household")
assert(okHomeA and okHomeB, "two households exist at once")
local roster = {
    {name="Mara Barley",faction=homeA.id},{name="Elias Barley",faction=homeA.id},
    {name="Nora Voss",faction=homeB.id},{name="Owen Voss",faction=homeB.id},
    {name="June Reid",faction="police"},{name="Miles Reid",faction="police"},
}
local group = C.newGroup()
group.defs = defs
local originalLoad = C.load
C.load = function() return roster, group end
local added, degraded, reason = C.spawnPending()
assert(added==6 and degraded==0 and reason=="ready", "all groups allocated")
local b1,b2=state.creatorRoster[homeA.id..":Mara Barley"],state.creatorRoster[homeA.id..":Elias Barley"]
local t1,t2=state.creatorRoster[homeB.id..":Nora Voss"],state.creatorRoster[homeB.id..":Owen Voss"]
local p1=state.creatorRoster["police:June Reid"]
assert(origins[b1].buildingId==origins[b2].buildingId and origins[t1].buildingId==origins[t2].buildingId, "each household shares a home")
assert(origins[b1].buildingId~=origins[t1].buildingId and groups[b1]~=groups[t1], "groups have separate buildings")
assert(origins[p1].context=="law_enforcement" and origins[p1].source=="world_building", "police use real police origin")
alive[b1]=false
C.preparedPopulation=nil
assert(C.spawnPending()==0 and nextId==6, "dead receipt is not recreated")
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
assert(C.spawnPending()==6, "new world creates templates anew")
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
catalog={origins={}}
local count,_,why=C.spawnPending()
assert(count==0 and why=="no_suitable_site" and C.preparedPopulation==nil, "missing site remains pending")
roster={{name="Unknown Person",faction="removed_faction"}}
catalog={origins={site("home",1,"residential",true)}}
count,_,why=C.spawnPending()
assert(count==0 and why=="unknown_profile", "unknown profile stays pending")
group.readOnly=true
count,_,why=C.spawnPending()
assert(count==0 and why=="creator_file_needs_review", "recovery blocks spawning")
group.readOnly=false
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
roster={{name="Legacy Person",faction=homeA.id}}
origins.legacy=site("home",1,"residential",true)
records.legacy={name="Legacy Person",faction=homeA.id}
alive.legacy=false
count,_,why=C.spawnPending()
assert(count==0 and state.creatorRoster[homeA.id..":Legacy Person"]=="legacy", "legacy dead record reconciled")
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
local recordFn=KnoxPersistence.setSurvivorCreatorRecord
KnoxPersistence.setSurvivorCreatorRecord=function() return false end
count,degraded=C.spawnPending()
assert(count==1 and degraded==1 and C.preparedPopulation==nil, "record failure retains receipt")
KnoxPersistence.setSurvivorCreatorRecord=recordFn
count,degraded=C.spawnPending()
assert(count==0 and degraded==0 and C.preparedPopulation==state, "retry fills record without duplicate")
-- Solo survivors are not a group. Treating them as a cohort used to demand N free
-- origins in one building and then put them in a travel group; each one is
-- independent, so each takes its own site and joins nothing.
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
catalog={origins={site("soloA",1,"residential",true),site("soloB",1,"residential",true),
    site("soloC",1,"residential",true)}}
roster={{name="Ada Solo",faction="solo"},{name="Ivo Solo",faction="solo"},{name="Rae Solo",faction="solo"}}
count,degraded,why=C.spawnPending()
assert(count==3 and degraded==0 and why=="ready", "three independent survivors allocate: " .. tostring(why))
local s1=state.creatorRoster["solo:Ada Solo"]
local s2=state.creatorRoster["solo:Ivo Solo"]
local s3=state.creatorRoster["solo:Rae Solo"]
assert(s1 and s2 and s3, "every solo survivor has its own receipt")
assert(origins[s1].buildingId~=origins[s2].buildingId
    and origins[s1].buildingId~=origins[s3].buildingId
    and origins[s2].buildingId~=origins[s3].buildingId,
    "solo survivors do not share one building")
assert(groups[s1]==nil and groups[s2]==nil and groups[s3]==nil,
    "solo survivors never join a travel group")
-- Returning to the independent bucket after it contains several origins must
-- not turn its receipts into a shared-home constraint.
C.preparedPopulation=nil
catalog.origins[#catalog.origins+1]=site("soloD",1,"residential",true)
roster[#roster+1]={name="New Solo",faction="solo"}
count,degraded,why=C.spawnPending()
assert(count==1 and degraded==0 and why=="ready", "adding a solo survivor respects independent existing origins")
assert(state.creatorRoster["solo:New Solo"] and groups[state.creatorRoster["solo:New Solo"]]==nil,
    "the later custom solo remains ungrouped")
-- Ticked out of the spawn pool: no cohort, no site, no receipt, no body.
state, origins, records, alive, groups = {}, {}, {}, {}, {}
C.preparedPopulation=nil
catalog={origins={site("poolhome",1,"residential",true),site("poolhome",2,"residential",true)}}
roster={{name="Kept Keeper",faction=homeA.id},{name="Left Out",faction=homeA.id}}
assert(C.toggleSpawn(roster, roster[2]), "a household member can leave the pool")
count,degraded,why=C.spawnPending()
assert(count==1 and degraded==0 and why=="ready", "only the pool member allocates: " .. tostring(why))
assert(state.creatorRoster[homeA.id..":Kept Keeper"]~=nil, "the pool member has a receipt")
assert(state.creatorRoster[homeA.id..":Left Out"]==nil, "the outsider has no receipt and no body")
-- A ticked-out marked companion bypasses the pool without rejoining it.
roster[2].startCompanion=true
C.preparedPopulation=nil
count,degraded,why=C.spawnPending()
assert(count==1 and degraded==0 and why=="ready", "the marked outsider allocates: " .. tostring(why))
assert(state.creatorRoster[homeA.id..":Left Out"]~=nil, "the marked outsider has a receipt")
C.load=originalLoad

KnoxPersistence, KnoxWorldPopulation = oldP, oldWorld
C.spawnPending, C.pendingWorldPlan, C.preparedPopulation = oldSpawn, oldPlan, oldPrepared
