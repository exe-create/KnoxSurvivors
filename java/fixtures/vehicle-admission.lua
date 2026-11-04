local Travel=assert(KnoxNpcVehicleTravel,"vehicle travel admission is loaded")
local function vehicle(options)
    options=options or {}
    return {
        getDriver=function() return options.driver end,
        isEngineRunning=function() return options.engine~=false end,
        isDriveable=function() return options.driveable~=false end,
        getCurrentSpeedKmHour=function() return options.speed or 0 end,
        getVehicleTowing=function() return nil end,
        getRemainingFuelPercentage=function() return options.fuel or 50 end,
        areAllDoorsLocked=function() return options.locked==true end,
        isKeysInIgnition=function() return options.ignition==true end,
        isHotwired=function() return options.hotwired==true end,
        isHotwiredBroken=function() return options.broken==true end,
        getKeyId=function() return 321 end,
    }
end
local function person(haveKey)
    return {getInventory=function()
        return {haveThisKeyId=function(self,id) return haveKey==true and id==321 end}
    end}
end
local owner=person(true)
local stranger=person(false)

assert(Travel.keyAdmission(vehicle{ignition=true},nil)==true,
    "a key in the ignition admits the vehicle without a body")
local ok,reason=Travel.keyAdmission(vehicle{hotwired=true},nil)
assert(ok==true and reason=="hotwired","a real hotwire is an ignition state")
ok,reason=Travel.keyAdmission(vehicle{hotwired=true,broken=true},nil)
assert(ok==false and reason=="vehicle_engine_off",
    "a broken hotwire fails closed instead of pretending the car starts")
ok,reason=Travel.keyAdmission(vehicle{},owner)
assert(ok==true and reason=="key_on_person","a real key in the inventory is admitted")
ok,reason=Travel.keyAdmission(vehicle{},stranger)
assert(ok==false and reason=="no_keys","no key is a named refusal")
ok,reason=Travel.keyAdmission({},owner)
assert(ok==false and reason=="vehicle_state_unknown",
    "an absent native key reader fails closed")

assert(Travel.assessReadiness(vehicle{ignition=true},nil)==true,
    "the existing fuel/lock/driveability admission still accepts a ready car")
ok,reason=Travel.assessReadiness(vehicle{engine=false},nil)
assert(ok==false and reason=="no_keys",
    "a keyless parked car reports no keys before a misleading engine-off verdict")
ok,reason=Travel.assessReadiness(vehicle{ignition=true,engine=false},nil)
assert(ok==false and reason=="vehicle_engine_off",
    "a keyed but stopped engine keeps its own reason")
ok,reason=Travel.assessReadiness(vehicle{ignition=true,locked=true},nil)
assert(ok==false and reason=="vehicle_doors_locked",
    "a locked keyed car keeps the existing lock refusal")
ok,reason=Travel.assessReadiness(vehicle{ignition=true,fuel=0},nil)
assert(ok==false and reason=="vehicle_low_fuel",
    "an empty tank is refused after the key check passes")
ok,reason=Travel.assessReadiness(vehicle{ignition=true,driver=owner},nil)
assert(ok==false and reason=="driver_seat_occupied",
    "an occupied driver seat remains the first refusal")
assert(Travel.assessReadiness(vehicle{ignition=true},owner)==true,
    "the same ready car is admitted for a character with the key")
