-- The saved library feeds real world-building placement and creator records.
-- Each world owns allocation receipts; spawning never rewrites the library.
local C = assert(KnoxCreator)
local old = {p=KnoxPersistence,world=KnoxWorldPopulation,reader=getFileReader,
    writer=getFileWriter,time=getGameTime,prepared=C.preparedPopulation}
local state, origins, records, alive, allocations = {}, {}, {}, {}, 0
local recordOk, allocateOk = true, true
local contents, captured
local catalog = {origins={}}
for n=1,12 do catalog.origins[n]={x=4000+n,y=8000,z=0,key=tostring(4000+n)..",8000,0",
    source="world_building",buildingId="fixture-barracks",context="military"} end
KnoxWorldPopulation={spawnCatalog=function() return catalog end}
KnoxPersistence={
    getPopulationState=function() return state end,
    getAllWorldSurvivorIds=function() local ids={} for id in pairs(origins) do ids[#ids+1]=id end return ids end,
    getLivingWorldSurvivorIds=function() local ids={} for id in pairs(alive) do ids[#ids+1]=id end return ids end,
    getUsedWorldOriginKeys=function() local used={} for _,o in pairs(origins) do used[o.key]=true end return used end,
    getSurvivorOrigin=function(id) return origins[id] end,
    getSurvivorCreatorRecord=function(id) return records[id] end,
    allocateWorldSurvivor=function(origin)
        if not allocateOk then return nil,"refused" end
        allocations=allocations+1;local id="handover-"..allocations
        origins[id],alive[id]=origin,true;return id
    end,
    setSurvivorCreatorRecord=function(id,record)
        captured=record;if not recordOk then return false,"refused" end
        records[id]=record;return true
    end,
    createTravelGroup=function() error("one person must not become a group") end,
}
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
getFileReader=function()
    local lines={};for line in contents:gmatch("[^\r\n]+") do lines[#lines+1]=line end
    local index=0
    return {readLine=function() index=index+1;return lines[index] end,close=function() end}
end
getFileWriter=function() error("world placement must not rewrite the reusable library") end
local function prepare(name)
    state,origins,records,alive={},{},{},{};C.preparedPopulation=nil
    contents=C.encode({{name=name,look="police",kit="police",weapon="Base.BaseballBat",
        weaponId="bat",profession="base:veteran",pack="medical",spawned=false}},
        {name="Millers",faction=3})
end
prepare("Ann")
local count,degraded=C.spawnPending()
assert(count==1 and degraded==0,"one pending person reaches the world")
assert(captured.pack=="medical" and captured.look=="police" and captured.kit=="police"
    and captured.weapon=="Base.BaseballBat","all loadout fields reach the creator record")
assert(captured.faction=="military" and captured.groupName=="Millers","legacy group intent survives")
local id=state.creatorRoster["military:Ann"]
assert(id and origins[id].source=="world_building" and origins[id].context=="military"
    and origins[id].professionCandidates[1]=="base:veteran","real origin and chosen profession reach allocation")
assert(C.spawnPending()==0 and allocations==1,"repeat startup does not duplicate this world's person")
assert(C.decode(contents)[1].spawned==false,"the saved library stays reusable in another world")
prepare("Ben");recordOk=false
count,degraded=C.spawnPending()
assert(count==1 and degraded==1,"a refused record is reported without hiding a real allocation")
local before=allocations;recordOk=true
count,degraded=C.spawnPending()
assert(count==0 and degraded==0 and allocations==before,"record retry uses the existing ID without another body")
prepare("Cara");allocateOk=false
assert(C.spawnPending()==0 and state.creatorRoster["military:Cara"]==nil,
    "refused allocation remains pending without a receipt")
allocateOk=true
assert(C.spawnPending()==1,"later availability can satisfy that pending person")
KnoxPersistence,KnoxWorldPopulation,getFileReader,getFileWriter,getGameTime,C.preparedPopulation=
    old.p,old.world,old.reader,old.writer,old.time,old.prepared
print("Creator handover PASS realSites=true records=true perWorld=true noLibraryRewrite=true")
