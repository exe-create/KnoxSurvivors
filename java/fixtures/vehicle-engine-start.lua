-- Exercise the real driver run with a seated driver and a stub native action queue.
local vehicles=assert(KnoxCompanionVehicles)
local nav=assert(KnoxVehicleNavigation)
local oldGeometry,oldPlan=nav.geometry,nav.plan
local oldSettings,oldRuntime,oldQueue,oldStart,oldTime,oldPersistence =
    KnoxSettings,KnoxSurvivorRuntime,ISTimedActionQueue,ISStartVehicleEngine,getTimestampMs,KnoxPersistence
local now=0
getTimestampMs=function() return now end
KnoxSettings={enableExperimentalNpcDriving=function() return true end}
KnoxPersistence=nil
KnoxSurvivorRuntime={idForCharacter=function() return "driver" end,prepareVehicle=function() return true end}
local controls={forward=false,reset=function(self) self.forward=false end}
local controller={getClientControls=function() return controls end,park=function() end}
local square={getZ=function() return 0 end}
local driver
local car={running=false}
function car:getDriver() return driver end
function car:isEngineRunning() return self.running end
function car:isDriveable() return true end
function car:isKeysInIgnition() return true end
function car:isHotwired() return false end
function car:getKeyId() return 1 end
function car:getCurrentSpeedKmHour() return 0 end
function car:getRemainingFuelPercentage() return 50 end
function car:areAllDoorsLocked() return false end
function car:getSquare() return square end
function car:getX() return 0 end
function car:getY() return 0 end
function car:getController() return controller end
driver={getVehicle=function() return car end,isDead=function() return false end,
    getInventory=function() return {haveThisKeyId=function() return false end} end}
nav.geometry=function() return {} end
nav.plan=function() return {{x=10,y=0,z=0}} end
local queue={}
ISTimedActionQueue={queues={[driver]={queue=queue}},add=function(action) queue[#queue+1]=action end,
    clear=function() for i=#queue,1,-1 do queue[i]=nil end end}
local built=0
ISStartVehicleEngine={new=function(_,character) built=built+1; return {character=character} end}
assert(vehicles.driveTo(driver,car,10,0,0), "a seated driver can request the parked car")
vehicles.tick()
assert(built==1 and #queue==1 and vehicles.driverStatus(driver).phase=="starting", "queue one native start action")
assert(not controls.forward and controls.brake, "no acceleration during startup")
vehicles.tick()
assert(built==1 and vehicles.driverStatus(driver).phase=="starting", "wait without repeating the start")
queue[1]=nil
car.running=true
vehicles.tick()
assert(vehicles.driverStatus(driver).phase=="driving", "only observed running engine permits driving")
vehicles.cancel(driver)
car.running=false; now=0
assert(vehicles.driveTo(driver,car,10,0,0))
vehicles.tick()
now=15001
vehicles.tick()
assert(vehicles.driverStatus(driver)==nil and #queue==0, "failed start times out and cancels its action")
assert(not controls.forward and controls.brake, "failed startup leaves controls stopped")
nav.geometry,nav.plan=oldGeometry,oldPlan
KnoxSettings,KnoxSurvivorRuntime,ISTimedActionQueue,ISStartVehicleEngine,getTimestampMs,KnoxPersistence =
    oldSettings,oldRuntime,oldQueue,oldStart,oldTime,oldPersistence
print("Vehicle engine start PASS queue=once wait=running timeout=stopped")
