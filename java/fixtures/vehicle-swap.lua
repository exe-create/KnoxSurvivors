local Vehicles=assert(KnoxCompanionVehicles,"vehicle owner is loaded")
assert(KnoxNpcVehicleTravel~=nil,"the shared key admission is loaded for the handoff")
local now=0
getTimestampMs=function() return now end
KnoxSettings={enableExperimentalNpcDriving=function() return true end,
    npcDrivingSpeed=function() return 20 end}
local spoken,events={},{}
KnoxActivityFeed={
    speak=function(character,line) spoken[#spoken+1]={character=character,line=line} end,
    event=function(line) events[#events+1]=line end,
}
KnoxSurvivorRuntime={idForCharacter=function(character) return character and character.id or nil end,
    prepareVehicle=function(id) return true end}
ISTimedActionQueue={queues={},add=function(action)
    local queue=ISTimedActionQueue.queues[action.character]
    if queue==nil then queue={queue={}}; ISTimedActionQueue.queues[action.character]=queue end
    queue.queue[#queue.queue+1]=action
end,clear=function(character) end}
ISSwitchVehicleSeat={new=function(self,character,seat,from)
    return {character=character,seatTo=seat,seatFrom=from}
end}

local occupants={}
local vehicle={speed=0,driver=nil,max=4,ignition=true}
function vehicle:getMaxPassengers() return self.max end
function vehicle:getCurrentSpeedKmHour() return self.speed end
function vehicle:isSeatOccupied(seat) return occupants[seat]~=nil end
function vehicle:isSeatInstalled(seat) return true end
function vehicle:isEnterBlocked(character,seat) return false end
function vehicle:getDriver() return self.driver end
function vehicle:isDriver(character) return self.driver==character end
function vehicle:getSeat(character)
    for seat,occupant in pairs(occupants) do
        if occupant==character then return seat end
    end
    return -1
end
function vehicle:getSquare() return {getZ=function() return 0 end} end
function vehicle:getX() return 10 end
function vehicle:getY() return 10 end
function vehicle:isKeysInIgnition() return self.ignition==true end
function vehicle:isHotwired() return false end
function vehicle:isHotwiredBroken() return false end
function vehicle:getKeyId() return 99 end

local function square() return {getZ=function() return 0 end} end
local player={id="player-1",x=10,y=10}
function player:getVehicle() return self.vehicle end
function player:isDead() return false end
function player:getCurrentSquare() return square() end
function player:getX() return self.x end
function player:getY() return self.y end
function player:getInventory() return {haveThisKeyId=function() return true end} end
local companion={id="ks-david",x=11,y=10}
function companion:getVehicle() return self.vehicle end
function companion:isDead() return false end
function companion:getCurrentSquare() return square() end
function companion:getX() return self.x end
function companion:getY() return self.y end
function companion:getInventory() return {haveThisKeyId=function() return false end} end

player.vehicle=vehicle
vehicle.driver=player
occupants[0]=player
assert(Vehicles.beginHandoff(player,companion,vehicle)==true,
    "a stopped player-driven car with a nearby companion starts the handoff")
local handoffSpoken=spoken[#spoken]
assert(handoffSpoken~=nil and handoffSpoken.line=="Move over. I'll drive.",
    "the companion asks for the seat instead of the mod moving the player")

now=9999
Vehicles.tick()
assert(#events==0,"a player who is still driving is not rushed before the wait")
now=10001
Vehicles.tick()
local timedOut=false
for _,line in ipairs(events) do if line=="You're still in the driver seat." then timedOut=true end end
assert(timedOut,"the ten-second wait cancels with the real reason")

events,spoken={},{}
player.vehicle=vehicle
vehicle.driver=player
occupants[0]=player
assert(Vehicles.beginHandoff(player,companion,vehicle)==true)
occupants[0]=nil
occupants[1]=player
vehicle.driver=nil
local realDriveAhead=Vehicles.driveAhead
Vehicles.driveAhead=function(character,car)
    occupants[0]=character
    character.vehicle=car
    car.driver=character
    return true,"driving_ahead"
end
now=20000
Vehicles.tick()
assert(vehicle.driver==companion,"the companion takes seat zero after the player moves")
Vehicles.tick()
local tookWheel=false
for _,line in ipairs(spoken) do if line.line=="I have the wheel." then tookWheel=true end end
assert(tookWheel,"the handoff confirms only after the companion is really driving")
Vehicles.driveAhead=realDriveAhead

events,spoken={},{}
occupants[0]=companion
occupants[1]=player
occupants[2]=nil
vehicle.driver=companion
companion.vehicle=vehicle
player.vehicle=vehicle
assert(Vehicles.beginTakeover(player,companion,vehicle)==true,
    "a stopped companion-driven car lets the companion move to a passenger seat")
local queue=ISTimedActionQueue.queues[companion]
assert(queue~=nil and #queue.queue==1 and queue.queue[1].seatTo==2,
    "the native seat switch is queued for a real free passenger seat")
occupants[0]=nil
occupants[2]=companion
vehicle.driver=nil
Vehicles.tick()
local seatFree=false
for _,line in ipairs(events) do if line=="The driver seat is free. Take the wheel." then seatFree=true end end
assert(seatFree,"the player is told only after seat zero is actually free")

occupants[0]=companion
occupants[1]=player
occupants[2]={id="filler-2"}
occupants[3]={id="filler-3"}
vehicle.driver=companion
assert(Vehicles.beginTakeover(player,companion,vehicle)==false,
    "a full car cannot clear the driver seat")
local fullReason=nil
local began,reason=Vehicles.beginTakeover(player,companion,vehicle)
fullReason=reason
assert(began==false and fullReason=="no_free_passenger_seat",
    "the full-car refusal names the missing seat")

occupants[1]=nil
occupants[2]=nil
occupants[3]=nil
vehicle.driver=companion
vehicle.speed=5
began,reason=Vehicles.beginTakeover(player,companion,vehicle)
assert(began==false and reason=="vehicle_moving","a moving car refuses the takeover")
vehicle.speed=0

vehicle.driver=player
occupants[0]=player
occupants[1]=nil
occupants[2]=nil
occupants[3]=nil
companion.vehicle=nil
player.vehicle=vehicle
vehicle.ignition=false
began,reason=Vehicles.beginHandoff(player,companion,vehicle)
assert(began==false and reason=="no_keys",
    "a survivor without the key cannot be handed a car that needs one")
vehicle.ignition=true

occupants[1]=companion
occupants[2]=companion
occupants[3]=companion
began,reason=Vehicles.beginHandoff(player,companion,vehicle)
assert(began==false and reason=="no_free_passenger_seat",
    "the player needs a real passenger seat before the handoff starts")

occupants[1]=nil
occupants[2]=nil
occupants[3]=nil
companion.x=60
began,reason=Vehicles.beginHandoff(player,companion,vehicle)
assert(began==false and reason=="too_far",
    "a companion outside the handoff radius is not ordered to the car")
