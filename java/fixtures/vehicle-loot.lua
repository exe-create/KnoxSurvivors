local L=assert(KnoxSurvivorLooting)
local oldNeeds,oldInstance,oldP,oldB,oldNum,oldPlayer=KnoxSurvivorNeeds,instanceof,KnoxPersistence,KnoxBaseManager,getNumActivePlayers,getSpecificPlayer
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local function square(x,y,z) return {getX=function() return x end,getY=function() return y end,getZ=function() return z end,canStand=function() return true end} end
local sq=square(10,10,0)
local far=square(100,100,0)
local contents={}
local src={getItems=function() return list(contents) end,isExistYet=function() return true end,isExplored=function(self) return self.explored end,getSourceGrid=function() return sq end,getVehiclePart=function(self) return self.part end,explored=true}
local med={getFullType=function() return 'Base.Pills' end,getUnequippedWeight=function() return 1 end,isBroken=function() return false end,IsWeapon=function() return false end,IsInventoryContainer=function() return false end,isCanBandage=function() return false end,getAmmoType=function() return nil end}
local bag={getItems=function() return list({}) end,getFreeCapacity=function() return 20 end}
local actor={getCurrentSquare=function() return sq end,getInventory=function() return bag end,getVehicle=function() return nil end}
local player={getCurrentSquare=function() return far end,getVehicle=function() return nil end}
local car={getSquare=function() return sq end,isRemovedFromWorld=function() return false end,getCurrentSpeedKmHour=function() return 0 end,getPartCount=function() return 1 end,getPartByIndex=function(self,i) return i==0 and self.part or nil end,getSquareForArea=function() return sq end,canAccessContainer=function(self) return self.access end,access=true}
local part={getId=function() return 'GloveBox' end,getItemContainer=function() return src end,getVehicle=function() return car end,getIndex=function() return 0 end,getArea=function() return 'SeatFrontRight' end}
car.part,src.part=part,part
KnoxPersistence={getVehicleAssignmentFor=function() return nil end,getSurvivorDuty=function() return nil end,getBases=function() return {} end}
KnoxBaseManager={containsSquare=function() return false end}
getNumActivePlayers=function() return 1 end
getSpecificPlayer=function() return player end
KnoxSurvivorNeeds={isSafeFood=function() return false end,isWaterItem=function() return false end}
instanceof=function() return false end
contents[1]=med
local result=L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})
assert(result and result.container==src and #result.items==1 and result.items[1].item==med,'real explored stock is planned')
assert(L.vehicleStockAllowed(actor,'npc',car,part,true),'native access admitted')
-- The verifier extracts findExploration from the real controller before this
-- fixture. Stub only its world/controller boundaries, not its scan loop.
assert(type(codecVehicleDiscovery)=='function','production discovery loaded')
local saved={Controller=Controller, safeMethod=safeMethod, getCell=getCell,
    EXPLORATION_SCAN_RADIUS=EXPLORATION_SCAN_RADIUS, isOwnPlayerBaseSquare=isOwnPlayerBaseSquare,
    containerUnavailable=containerUnavailable,areaUnavailable=areaUnavailable,
    reservedByOther=reservedByOther,sortiePeerClaimedContainer=sortiePeerClaimedContainer,
    controllers=controllers}
Controller={TUNING={LOOT_CONTAINER_ITEM_LIMIT=2,CONVENIENT_INSPECTION_RADIUS=0}}
EXPLORATION_SCAN_RADIUS=0
safeMethod=function(obj,name,default) if obj and obj[name] then return obj[name](obj) end return default end
isOwnPlayerBaseSquare=function() return false end
containerUnavailable=function() return false end
areaUnavailable=function() return false end
reservedByOther=function() return false end
sortiePeerClaimedContainer=function() return false end
controllers={}
sq.getVehicleContainer=function() return car end
sq.getObjects=function() return list({}) end
sq.getBuilding=function() return nil end
getCell=function() return {getGridSquare=function() return sq end} end
local owner={character=actor,id='npc',reservations={},scavengingForSettlement=function() return true end,
    allowNeedDetour=function() return true end}
local found=codecVehicleDiscovery(owner,0,nil,nil)
assert(found and found.vehicle==car and found.vehiclePart==part and found.container==src
    and found.items[1].item==med,'controller exploration discovers real vehicle stock')
assert(codecVehicleDiscovery(owner,600,nil,nil)==nil,'exploration cadence bounds car searches')
assert(codecVehicleDiscovery(owner,0,{kind='loot_area'},nil)==nil,'vehicle discovery stays autonomous')
Controller,safeMethod,getCell,EXPLORATION_SCAN_RADIUS=saved.Controller,saved.safeMethod,saved.getCell,saved.EXPLORATION_SCAN_RADIUS
isOwnPlayerBaseSquare,containerUnavailable,areaUnavailable=saved.isOwnPlayerBaseSquare,saved.containerUnavailable,saved.areaUnavailable
reservedByOther,sortiePeerClaimedContainer,controllers=saved.reservedByOther,saved.sortiePeerClaimedContainer,saved.controllers
car.access=false
assert(not L.vehicleStockAllowed(actor,'npc',car,part,true),'closed or locked part denied at pickup')
car.access=true
KnoxPersistence.getVehicleAssignmentFor=function() return {ownerKind='player'} end
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'assigned car excluded')
KnoxPersistence.getVehicleAssignmentFor=function() return nil end
player.getCurrentSquare=function() return sq end
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'nearby player car excluded')
player.getCurrentSquare=function() return far end
actor.getCurrentSquare=function() return square(10,10,1) end
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'wrong floor excluded')
actor.getCurrentSquare=function() return sq end
src.explored=false
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'unexplored not generated')
src.explored=true
contents={}
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'empty stock skipped')
contents={med}
car.getPartCount=function() return 17 end
car.getPartByIndex=function(self,i) if i==16 then return part end return nil end
assert(L.vehicleCandidate(actor,'npc',car,2,true,{purpose='medicine'})==nil,'part scan capped at sixteen')
KnoxSurvivorNeeds,instanceof,KnoxPersistence,KnoxBaseManager,getNumActivePlayers,getSpecificPlayer=oldNeeds,oldInstance,oldP,oldB,oldNum,oldPlayer
print('Vehicle loot PASS explored=true access=true ownership=true bounded=true')
