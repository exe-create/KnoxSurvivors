local P,T=assert(KnoxPersistence),assert(KnoxNpcVehicleTravel)
assert(type(codecRecordVehicleAssignment)=='function' and type(codecReleaseVehicleAssignment)=='function','production assignment functions loaded')
local saved={aff=P.getSurvivorAffiliation,group=P.getTravelGroupFor,bases=P.getBases,
    baseManager=KnoxBaseManager,runtime=KnoxSurvivorRuntime,vehicles=KnoxCompanionVehicles,
    count=getNumActivePlayers,player=getSpecificPlayer,parked=T.parkedVehicles}
local id='vehicle-claim-fixture-npc'
local own={factionId='vehicle-claim-fixture-faction'}
local group={leaderId=id,factionId=own.factionId}
P.getSurvivorAffiliation=function() return own end
P.getTravelGroupFor=function() return group end
P.getBases=function() return {} end
KnoxBaseManager={containsSquare=function() return true end}
KnoxSurvivorRuntime={idForCharacter=function() return id end}
local function sq(x) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end} end
local origin=sq(0)
local player={getCurrentSquare=function() return sq(100) end,getX=function(self) return self:getCurrentSquare():getX() end,getY=function() return 0 end,getVehicle=function() return nil end}
getNumActivePlayers=function() return 1 end
getSpecificPlayer=function() return player end
local actor={getCurrentSquare=function() return origin end,getX=function() return 0 end,getY=function() return 0 end,
    getInventory=function() return {haveThisKeyId=function() return true end} end,isDead=function() return false end}
local function car(sql,x)
    local square=sq(x)
    return {getSqlId=function() return sql end,isRemovedFromWorld=function() return false end,
        getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end,getSquare=function() return square end,
        getDriver=function() return nil end,getKeyId=function() return 1 end,isKeysInIgnition=function() return true end,isHotwired=function() return false end,
        isEngineRunning=function() return true end,isDriveable=function() return true end,getCurrentSpeedKmHour=function() return 0 end,
        getVehicleTowing=function() return nil end,getVehicleTowedBy=function() return nil end,getRemainingFuelPercentage=function() return 50 end,
        areAllDoorsLocked=function() return false end}
end
local a,b=car(99110001,10),car(99110002,5)
P.clearVehicleAssignment('99110001'); P.clearVehicleAssignment('99110002'); P.clearVehicleAssignment('99110003')
assert(T.claimAdmission(actor,car(0,10),true)==false,'unsaved vehicle cannot be claimed')
P.getBases=function() return {{ownerKind='player'}} end
assert(T.claimAdmission(actor,a,true)==false,'protected player base excludes claim')
P.getBases=function() return {} end
player.getCurrentSquare=function() return sq(10) end
assert(T.claimAdmission(actor,a,true)==false,'nearby player excludes claim')
player.getCurrentSquare=function() return sq(100) end
assert(P.setVehicleAssignment({vehicleKey='99110001',ownerKind='faction',ownerId=own.factionId,driverId=id,role='transport'},0))
assert(T.claimAdmission(actor,a,true)==false,'legacy running assignment is not promoted')
P.clearVehicleAssignment('99110001')
local chosen
KnoxCompanionVehicles={driveTo=function(who,vehicle,x,y,z,options)
    chosen=vehicle
    return codecRecordVehicleAssignment(who,vehicle,'transport',options.autonomousClaim and 'autonomous' or nil),'driving'
end,setRunPassengers=function() return true end}
T.parkedVehicles=function() return {a} end
local controller={character=actor,id=id,groupMembers={}}
assert(T.tryBegin(controller,{x=100,y=0,z=0},0)==true and chosen==a,'autonomous accepted trip creates claim')
local record=P.getVehicleAssignment('99110001')
assert(record and record.claimSource=='autonomous' and record.ownerId==own.factionId,'claim is real faction record')
codecReleaseVehicleAssignment(actor,a)
assert(P.getVehicleAssignment('99110001').claimSource=='autonomous','ordinary interrupted or completed run keeps claim')
local blocked,why=P.setVehicleAssignment({vehicleKey='99110001',ownerKind='faction',ownerId='foreign',driverId='foreign',role='transport'},0)
assert(blocked==nil and why=='vehicle_claimed','foreign driver cannot overwrite claim')
own={factionId='foreign'}
assert(T.claimAdmission(actor,a,false)==false,'foreign faction cannot use claim')
own={factionId='vehicle-claim-fixture-faction'}
T.parkedVehicles=function() return {b,a} end
controller.nextNpcVehicleTravelAt=0; chosen=nil
assert(T.tryBegin(controller,{x=100,y=0,z=0},0)==true and chosen==a,'owned claim preferred over nearer abandoned car')
actor.isDead=function() return true end
codecReleaseVehicleAssignment(actor,a)
assert(P.getVehicleAssignment('99110001')==nil,'observed claimant death releases claim')
P.clearVehicleAssignment('99110002'); P.clearVehicleAssignment('99110003')
P.getSurvivorAffiliation,P.getTravelGroupFor,P.getBases=saved.aff,saved.group,saved.bases
KnoxBaseManager,KnoxSurvivorRuntime,KnoxCompanionVehicles=saved.baseManager,saved.runtime,saved.vehicles
getNumActivePlayers,getSpecificPlayer,T.parkedVehicles=saved.count,saved.player,saved.parked
print('Vehicle claim PASS accepted=true legacy=true base=true foreign=true reuse=true death=true')
