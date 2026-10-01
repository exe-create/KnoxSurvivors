require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/TimedActions/ISExitVehicle"
require "Vehicles/TimedActions/ISUnlockVehicleDoor"
require "Vehicles/TimedActions/ISOpenVehicleDoor"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "KS_Settings"
require "KS_VehicleNavigation"
require "Vehicles/TimedActions/ISSwitchVehicleSeat"

-- Native entry/seat/exit actions and physics, with bounded Knox route planning
-- on loaded ground. Driving remains opt-in until live physics acceptance.
local CompanionVehicles = rawget(_G, "KnoxCompanionVehicles") or {}
_G.KnoxCompanionVehicles = CompanionVehicles

-- Short-lived native action ownership; no seats or actions enter save data.
local pending = setmetatable({}, { __mode = "k" })
local driverRuns = setmetatable({}, { __mode = "k" })
-- Passengers whose abort-time exit was refused (a moving vehicle) wait here
-- for a stationary retry instead of sitting lease-free with no owner.
local awaitingExit = setmetatable({}, { __mode = "k" })
local EXIT_RETRY_LIMIT = 20
local ACTION_TIMEOUT_MS = 45000
local DRIVER_DISTANCE = 18
local DRIVER_STOP_DISTANCE = 2.5
local DRIVER_TIMEOUT_MS = 180000
local PLAYER_SYNC_DISTANCE_SQUARED = 30 * 30

local function sameFloorAndNear(character, vehicle, maxDistanceSquared)
    if character == nil or vehicle == nil or character.getCurrentSquare == nil
        or vehicle.getSquare == nil then return false end
    local actorSquare, vehicleSquare = character:getCurrentSquare(), vehicle:getSquare()
    if actorSquare == nil or vehicleSquare == nil
        or actorSquare:getZ() ~= vehicleSquare:getZ() then return false end
    local dx, dy = character:getX() - vehicle:getX(), character:getY() - vehicle:getY()
    return dx * dx + dy * dy <= (maxDistanceSquared or PLAYER_SYNC_DISTANCE_SQUARED)
end

local function loadedVehicles()
    local cell = getCell ~= nil and getCell() or nil
    local list = cell ~= nil and cell.getVehicles ~= nil and cell:getVehicles() or nil
    local result = {}
    if list == nil then return result end
    if list.iterator ~= nil then
        local iterator = list:iterator()
        while iterator:hasNext() do result[#result + 1] = iterator:next() end
    elseif list.size ~= nil and list.get ~= nil then
        for index = 0, list:size() - 1 do result[#result + 1] = list:get(index) end
    end
    return result
end

local function distanceSquaredToVehicle(character, vehicle)
    local dx, dy = character:getX() - vehicle:getX(), character:getY() - vehicle:getY()
    return dx * dx + dy * dy
end

local function resetDriverControls(run, character)
    local vehicle = run ~= nil and run.vehicle or nil
    if vehicle ~= nil and vehicle.getDriver ~= nil then
        local driver=vehicle:getDriver()
        if driver~=nil and driver~=character then return end
        if run.phase=="boarding" and driver~=character then return end
    end
    local controller = vehicle ~= nil and vehicle.getController ~= nil
        and vehicle:getController() or nil
    if controller == nil then return end
    local controls = controller.getClientControls ~= nil
        and controller:getClientControls() or nil
    if controls ~= nil and controls.reset ~= nil then
        pcall(controls.reset, controls)
    end
    if controller.park ~= nil then pcall(controller.park, controller) end
    -- park() resets controls. Keep the brake applied until a real driver or a
    -- later NPC request takes control; clearing it immediately allowed coasting.
    if controls ~= nil then controls.brake=true end
end

local function stopDriver(character)
    local run = driverRuns[character]
    if run ~= nil then resetDriverControls(run, character) end
    -- Assigning nil to an absent key during pairs traversal is undefined
    -- behavior ("invalid key to 'next'"); passenger rollback cancels
    -- characters that never owned a driver run, so only clear a present key.
    if driverRuns[character] ~= nil then driverRuns[character] = nil end
end

local function health(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, value = pcall(function() return character:getBodyDamage():getHealth() end)
    return ok and tonumber(value) or nil
end

local function setBoardingPace(character, request, enabled)
    if character == nil or request == nil or request.runToVehicle ~= true
        or character.setRunning == nil then return end
    if enabled then
        local wasRunning = false
        if character.isRunning ~= nil then
            local ok, value = pcall(function() return character:isRunning() end)
            wasRunning = ok and value == true
        end
        request.wasRunning = wasRunning
        local ok = pcall(function() character:setRunning(true) end)
        request.paceApplied = ok
    elseif request.paceApplied then
        -- Restore the native movement flag at every boarding teardown. This
        -- makes the jog a temporary pathing preference, not an autonomy owner.
        pcall(function() character:setRunning(request.wasRunning == true) end)
        request.paceApplied = false
    end
end

-- Settle one driver run's committed passenger roster: pending leases cancel
-- at once instead of waiting out the action timeout, and seated passengers
-- get the existing native exit (which refuses a moving vehicle itself).
-- Members riding another vehicle are only unleased, never touched. A finished
-- run with no roster is a no-op.
local function rollbackRoster(character, run)
    local roster = run ~= nil and run.passengers or nil
    if roster == nil then return end
    for _, entry in ipairs(roster) do
        local member = entry ~= nil and entry.member or nil
        -- The driver is settled by their own run teardown, never by the
        -- passenger sweep: on arrival they stay seated until an explicit
        -- order moves them, and the run simply ends beneath them.
        if member ~= nil and member ~= character then
            local memberVehicle = member.getVehicle ~= nil and member:getVehicle() or nil
            if memberVehicle ~= nil then
                -- A stale roster must not cancel a newer vehicle run or queue
                -- an exit from a different car. Only the exact committed
                -- vehicle is owned by this driver's rollback.
                if run.vehicle ~= nil and memberVehicle == run.vehicle then
                    -- A refused exit (moving vehicle, missing action) must not
                    -- strand the rider lease-free: mark them for the bounded
                    -- stationary retry in tick() below instead of inventing an exit.
                    if not CompanionVehicles.exit(member) and member:getVehicle() == run.vehicle then
                        awaitingExit[member] = { vehicle = run.vehicle, tries = 0 }
                    end
                end
            else
                CompanionVehicles.cancel(member)
            end
        end
    end
end

-- Bounded recovery sweep for abort-time exit refusals. A member with fresh
-- ownership (a new boarding lease) or who left the marked vehicle clears the
-- mark; otherwise a stationary vehicle gets a native exit attempt. Attempts
-- while moving do not count down, so a long drive waits rather than expires.
local function retryAwaitingExits()
    for member, mark in pairs(awaitingExit) do
        local aboard = member.getVehicle ~= nil and member:getVehicle() ~= nil
            and (mark.vehicle == nil or member:getVehicle() == mark.vehicle)
        if not aboard or CompanionVehicles.isBusy(member) then
            awaitingExit[member] = nil
        else
            local speed = 0
            if mark.vehicle ~= nil and mark.vehicle.getCurrentSpeedKmHour ~= nil then
                local ok, value = pcall(function() return mark.vehicle:getCurrentSpeedKmHour() end)
                speed = (ok and tonumber(value)) or 0
            end
            if math.abs(speed) <= 1 then
                mark.tries = (mark.tries or 0) + 1
                if CompanionVehicles.exit(member) or member:getVehicle() == nil then
                    awaitingExit[member] = nil
                elseif mark.tries > EXIT_RETRY_LIMIT then
                    awaitingExit[member] = nil
                    -- A bounded wait that never resolves is a reportable fact,
                    -- not a silent print: one restrained line to the member,
                    -- exactly once, alongside the existing diagnostic.
                    if KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
                        KnoxActivityFeed.speak(member, "I can't get out.")
                    end
                    print("[KnoxSurvivors][Driving] exit_unrecoverable member_mark_cleared=true")
                end
            end
        end
    end
end

function CompanionVehicles.cancel(character, keepPassengers)
    local run = driverRuns[character]
    stopDriver(character)
    local request = pending[character]
    if request == nil then
        if not keepPassengers then rollbackRoster(character, run) end
        return
    end
    pending[character] = nil
    setBoardingPace(character, request, false)
    local queue = ISTimedActionQueue.queues[character]
    if queue ~= nil then
        for _, action in ipairs(queue.queue) do
            if request.actions[action] then
                ISTimedActionQueue.clear(character)
                break
            end
        end
    end
    if not keepPassengers then rollbackRoster(character, run) end
end

function CompanionVehicles.isBusy(character)
    local request = pending[character]
    if request == nil then return false end
    local currentHealth = health(character)
    if getTimestampMs() >= request.deadline
        or (character.isDead ~= nil and character:isDead())
        or (currentHealth ~= nil and request.health ~= nil and currentHealth < request.health) then
        CompanionVehicles.cancel(character)
        return false, "interrupted"
    end
    if request.runToVehicle and character.getVehicle ~= nil
        and character:getVehicle() == request.vehicle then
        setBoardingPace(character, request, false)
    end
    local queue = ISTimedActionQueue.queues[character]
    for _, action in ipairs(queue ~= nil and queue.queue or {}) do
        if request.actions[action] then return true end
    end
    pending[character] = nil
    setBoardingPace(character, request, false)
    return false
end

function CompanionVehicles.activity(character)
    -- Read-only presentation: expiry/cleanup belongs to isBusy in the controller.
    local run=driverRuns[character]
    if run ~= nil then
        if run.phase=="boarding" then return "boarding" end
        return run.blockedSince~=nil and "waiting_for_road" or "driving"
    end
    if pending[character] ~= nil then return "boarding" end
    if character ~= nil and character:getVehicle() ~= nil then return "riding" end
    return nil
end

local function reserved(vehicle, seat, character)
    for other, request in pairs(pending) do
        if other ~= character and request.vehicle == vehicle and request.seat == seat
            and CompanionVehicles.isBusy(other) then return true end
    end
    return false
end

local function queueActions(character, vehicle, seat, actions, options)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local id = runtime ~= nil and runtime.idForCharacter(character) or nil
    if id == nil or runtime.prepareVehicle == nil or not runtime.prepareVehicle(id) then
        return false, "survivor_busy"
    end
    local request = { vehicle = vehicle, seat = seat,
        deadline = getTimestampMs() + ACTION_TIMEOUT_MS, health = health(character), actions = {},
        runToVehicle = options ~= nil and options.runToVehicle == true }
    if request.runToVehicle then setBoardingPace(character, request, true) end
    for _, action in ipairs(actions) do request.actions[action] = true end
    pending[character] = request
    local ok, queued = pcall(function()
        for _, action in ipairs(actions) do
            ISTimedActionQueue.add(action)
            -- Native add can silently refuse an action (for example during
            -- sleep). Never queue entry after a rejected path or report success
            -- without the actual native action owning the character.
            local queue = ISTimedActionQueue.queues[character]
            local found = false
            for _, queuedAction in ipairs(queue ~= nil and queue.queue or {}) do
                if queuedAction == action then found = true; break end
            end
            if not found then return false end
        end
        return true
    end)
    if not ok or not queued then
        CompanionVehicles.cancel(character)
        return false, "vehicle_action_failed"
    end
    return true
end

local function usablePassengerSeat(character, vehicle, seat)
    if character == nil or vehicle == nil or seat == nil
        or vehicle:isSeatOccupied(seat) or reserved(vehicle, seat, character) then
        return false
    end
    if vehicle.isSeatInstalled ~= nil and not vehicle:isSeatInstalled(seat) then
        return false
    end
    if vehicle.isEnterBlocked ~= nil and vehicle:isEnterBlocked(character, seat) then
        return false
    end
    -- A locked door does not make an installed seat unavailable. Vanilla's
    -- ISVehicleMenu queues native unlock/open actions before entering; board()
    -- mirrors that flow and lets the real action/key state decide the result.
    return true
end

local function appendDoorEntryActions(character, vehicle, seat, actions)
    local doorPart = vehicle:getPassengerDoor(seat)
    local door = doorPart ~= nil and doorPart:getDoor() or nil
    local hasDoorItem = doorPart ~= nil and doorPart.getInventoryItem ~= nil
        and doorPart:getInventoryItem() ~= nil
    if door == nil or not hasDoorItem then
        actions[#actions + 1] = assert(ISEnterVehicle:new(character, vehicle, seat))
        return
    end

    if door:isLocked() then
        local keyOnDoor = vehicle.isKeyIsOnDoor ~= nil and vehicle:isKeyIsOnDoor()
            and vehicle.getCurrentKey ~= nil and vehicle:getCurrentKey() or nil
        if keyOnDoor ~= nil and character.getInventory ~= nil
            and vehicle.setKeyIsOnDoor ~= nil and vehicle.setCurrentKey ~= nil then
            vehicle:setKeyIsOnDoor(false)
            vehicle:setCurrentKey(nil)
            character:getInventory():AddItem(keyOnDoor)
            if isClient ~= nil and isClient() and sendClientCommand ~= nil then
                sendClientCommand(character, "vehicle", "removeKeyFromDoor",
                    { vehicle = vehicle:getId() })
            end
        else
            assert(ISUnlockVehicleDoor ~= nil, "native vehicle unlock action unavailable")
            actions[#actions + 1] = assert(ISUnlockVehicleDoor:new(character, doorPart))
        end
    end
    if not door:isOpen() then
        assert(ISOpenVehicleDoor ~= nil, "native vehicle door action unavailable")
        actions[#actions + 1] = assert(ISOpenVehicleDoor:new(character, vehicle, doorPart))
    end
    actions[#actions + 1] = assert(ISEnterVehicle:new(character, vehicle, seat))
    if ISCloseVehicleDoor ~= nil then
        actions[#actions + 1] = assert(ISCloseVehicleDoor:new(character, vehicle, doorPart))
    end
end

local function usableDriverSeat(character, vehicle)
    if character == nil or vehicle == nil or vehicle:isSeatOccupied(0)
        or reserved(vehicle, 0, character) then
        return false
    end
    if vehicle.isSeatInstalled ~= nil and not vehicle:isSeatInstalled(0) then
        return false
    end
    if vehicle.isEnterBlocked ~= nil and vehicle:isEnterBlocked(character, 0) then
        return false
    end
    local doorPart = vehicle.getPassengerDoor ~= nil
        and vehicle:getPassengerDoor(0) or nil
    local door = doorPart ~= nil and doorPart:getDoor() or nil
    return door == nil or not door:isLocked()
end

local function driveTarget(vehicle, geometry, character)
    local origin=vehicle:getSquare()
    local fx,fy=KnoxVehicleNavigation.forward(vehicle)
    if origin==nil or fx==nil then return nil end
    for distance=DRIVER_DISTANCE,8,-2 do
        local x,y=vehicle:getX()+fx*distance,vehicle:getY()+fy*distance
        local route=KnoxVehicleNavigation.plan(vehicle,x,y,origin:getZ(),geometry,character)
        if route~=nil then return route end
    end
    return nil
end

function CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if character == nil or vehicle == nil or vehicle.getMaxPassengers == nil then
        return nil
    end
    -- Ordinary boarding always leaves seat zero for an explicit driver order.
    for seat = 1, vehicle:getMaxPassengers() - 1 do
        if usablePassengerSeat(character, vehicle, seat) then
            return seat
        end
    end
    return nil
end

function CompanionVehicles.board(character, vehicle)
    if character == nil or vehicle == nil then
        return false, "vehicle_unavailable"
    end
    if character:getVehicle() ~= nil then
        return false, "already_in_vehicle"
    end
    if CompanionVehicles.isBusy(character) then return false, "vehicle_action_pending" end
    if ISTimedActionQueue == nil or ISPathFindAction == nil or ISEnterVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    local seat = CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if seat == nil then
        return false, "no_free_passenger_seat"
    end
    -- Construct the complete sequence before interrupting the controller.
    -- A missing path must not leave a sparse array that silently skips entry.
    local built, actions = pcall(function()
        local path = assert(ISPathFindAction:pathToVehicleSeat(character, vehicle, seat))
        local result = { path }
        appendDoorEntryActions(character, vehicle, seat, result)
        return result
    end)
    if not built then return false, "vehicle_action_failed" end
    local queued, reason = queueActions(character, vehicle, seat, actions,
        { runToVehicle = true })
    if not queued then return false, reason end
    return true, "boarding_seat=" .. tostring(seat)
end

-- Complete the player-entered-vehicle transition for the already-filtered
-- Follow roster supplied by CompanionService. Native actions and leases stay
-- here; held, ordered, base-duty, and non-party survivors never enter this path.
function CompanionVehicles.syncPlayerEntered(player, members)
    local vehicle = player ~= nil and player:getVehicle() or nil
    if vehicle == nil or vehicle:getSquare() == nil then
        return false, "player_not_in_vehicle"
    end
    if math.abs(vehicle:getCurrentSpeedKmHour()) > 1 then
        return false, "vehicle_moving"
    end
    members = type(members) == "table" and members or {}
    local playerDriving = vehicle.isDriver ~= nil and vehicle:isDriver(player)
    local driver = vehicle:getDriver()
    local assignedDriver = nil

    -- When the player chose a passenger seat and this parked vehicle has no
    -- driver, let one nearby Follow companion take the native driver path if
    -- Experimental NPC Driving is enabled. If that safe admission fails, that
    -- survivor can still take a passenger seat below.
    local settings = rawget(_G, "KnoxSettings")
    local mayDrive = not playerDriving and driver == nil and settings ~= nil
        and settings.enableExperimentalNpcDriving ~= nil
        and settings.enableExperimentalNpcDriving()
    if mayDrive then
        local candidates = {}
        for index, member in ipairs(members) do
            if member ~= nil and member ~= player and member:getVehicle() == nil
                and sameFloorAndNear(member, vehicle) then
                candidates[#candidates + 1] = {
                    character = member, distance = distanceSquaredToVehicle(member, vehicle),
                    order = index,
                }
            end
        end
        table.sort(candidates, function(first, second)
            if first.distance == second.distance then return first.order < second.order end
            return first.distance < second.distance
        end)
        for _, candidate in ipairs(candidates) do
            local member = candidate.character
            local started = CompanionVehicles.driveAhead(member, vehicle)
            if started then
                assignedDriver = member
                break
            end
        end
    end

    local boarded, rejected = 0, {}
    for _, member in ipairs(members) do
        if member ~= nil and member ~= player and member ~= assignedDriver
            and member:getVehicle() == nil and sameFloorAndNear(member, vehicle) then
            local started, reason = CompanionVehicles.board(member, vehicle)
            if started then boarded = boarded + 1
            else rejected[#rejected + 1] = tostring(reason or "vehicle_action_failed") end
        end
    end
    return true, { vehicle = vehicle, boarded = boarded,
        driver = assignedDriver, rejected = rejected }
end

function CompanionVehicles.exitAfterPlayer(character, vehicle)
    if character == nil or vehicle == nil or character:getVehicle() ~= vehicle then
        return false, "vehicle_changed"
    end
    local success, reason = CompanionVehicles.exit(character)
    if not success and reason == "vehicle_moving" and character:getVehicle() == vehicle then
        awaitingExit[character] = { vehicle = vehicle, tries = 0 }
        return false, "exit_waiting_for_stop"
    end
    return success, reason
end

function CompanionVehicles.syncPlayerExited(player, vehicle, members)
    if player == nil or vehicle == nil then return false, "vehicle_unavailable" end
    members = type(members) == "table" and members or {}
    local exited, cancelled, rejected = 0, 0, {}
    for _, member in ipairs(members) do
        if member ~= nil and member ~= player then
            if member:getVehicle() == vehicle then
                local success, reason = CompanionVehicles.exitAfterPlayer(member, vehicle)
                if success then exited = exited + 1
                else rejected[#rejected + 1] = tostring(reason or "vehicle_action_failed") end
            else
                local request = pending[member]
                if request ~= nil and request.vehicle == vehicle then
                    CompanionVehicles.cancel(member)
                    cancelled = cancelled + 1
                end
            end
        end
    end
    return true, { vehicle = vehicle, exited = exited,
        cancelled = cancelled, rejected = rejected }
end

function CompanionVehicles.driveNearest(character, maxDistance)
    if KnoxSettings == nil or KnoxSettings.enableExperimentalNpcDriving == nil
        or not KnoxSettings.enableExperimentalNpcDriving() then
        return false, "npc_driving_disabled"
    end
    if character == nil or character.getCurrentSquare == nil
        or character:getCurrentSquare() == nil then return false, "vehicle_origin_unavailable" end
    local limit = (tonumber(maxDistance) or 30)
    local limitSquared = limit * limit
    local candidates = {}
    for _, vehicle in ipairs(loadedVehicles()) do
        if sameFloorAndNear(character, vehicle, limitSquared) then
            candidates[#candidates + 1] = {
                vehicle = vehicle, distance = distanceSquaredToVehicle(character, vehicle),
            }
        end
    end
    table.sort(candidates, function(first, second)
        if first.distance == second.distance then
            return tostring(first.vehicle) < tostring(second.vehicle)
        end
        return first.distance < second.distance
    end)
    local lastReason = "no_usable_vehicle_nearby"
    for _, candidate in ipairs(candidates) do
        local started, reason = CompanionVehicles.driveAhead(character, candidate.vehicle)
        if started then return true, "driving_nearest_vehicle", candidate.vehicle end
        lastReason = reason or lastReason
    end
    return false, lastReason
end

function CompanionVehicles.exit(character)
    if character == nil or character:getVehicle() == nil then
        return false, "not_in_vehicle"
    end
    local speed=character:getVehicle().getCurrentSpeedKmHour~=nil
        and math.abs(character:getVehicle():getCurrentSpeedKmHour()) or 0
    if speed>1 then return false, "vehicle_moving" end
    if ISTimedActionQueue == nil or ISExitVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    if CompanionVehicles.isBusy(character) then return false, "vehicle_action_pending" end
    local built, action = pcall(function() return assert(ISExitVehicle:new(character)) end)
    if not built then return false, "vehicle_action_failed" end
    local queued, reason = queueActions(character, character:getVehicle(), nil, { action })
    if not queued then return false, reason end
    return true, "exiting"
end

local function startDrive(character,vehicle,destination)
    if KnoxSettings==nil or not KnoxSettings.enableExperimentalNpcDriving() then return false,"npc_driving_disabled" end
    if character==nil or vehicle==nil then return false,"vehicle_unavailable" end
    local occupied=character:getVehicle()
    if occupied~=nil and occupied~=vehicle then return false,"already_in_vehicle" end
    if CompanionVehicles.isBusy(character) then return false,"vehicle_action_pending" end
    local driver=vehicle:getDriver()
    if driver~=nil and driver~=character then return false,"driver_seat_occupied" end
    if driver~=character and math.abs(vehicle:getCurrentSpeedKmHour())>1 then return false,"vehicle_moving" end
    if not vehicle:isEngineRunning() then return false,"vehicle_engine_off" end
    if not vehicle:isDriveable() then return false,"vehicle_not_driveable" end
    local travel = rawget(_G, "KnoxNpcVehicleTravel")
    if travel ~= nil and travel.assessReadiness ~= nil then
        local ready, reason = travel.assessReadiness(vehicle)
        if not ready then return false, reason end
    else
        -- Unit-test contexts that never load KS_NpcVehicleTravel still need
        -- the same fuel/lock gate. Keep these two checks identical to
        -- VehicleTravel.assessReadiness above; production always resolves the
        -- shared definition through the loaded travel module.
        if vehicle.getRemainingFuelPercentage == nil then
            return false, "vehicle_state_unknown"
        end
        local fueled, percent = pcall(function() return vehicle:getRemainingFuelPercentage() end)
        if not fueled or (tonumber(percent) or 0) < 1 then
            return false, "vehicle_low_fuel"
        end
        if vehicle.areAllDoorsLocked == nil then
            return false, "vehicle_state_unknown"
        end
        local checked, allLocked = pcall(function() return vehicle:areAllDoorsLocked() end)
        if not checked then return false, "vehicle_state_unknown" end
        if allLocked then return false, "vehicle_doors_locked" end
    end
    if vehicle.getVehicleTowing~=nil and vehicle:getVehicleTowing()~=nil
        or vehicle.getVehicleTowedBy~=nil and vehicle:getVehicleTowedBy()~=nil then
        return false,"towing_not_supported"
    end
    local inspected,geometry=pcall(KnoxVehicleNavigation.geometry,vehicle)
    if not inspected or geometry==nil then return false,"vehicle_geometry_unavailable" end
    local route,reason
    if destination~=nil then
        route,reason=KnoxVehicleNavigation.plan(vehicle,destination.x,destination.y,destination.z,geometry,character)
    else route=driveTarget(vehicle,geometry,character) end
    if route==nil then return false,reason or "drive_route_unavailable" end
    local phase="boarding"
    if driver==character then
        local runtime=rawget(_G,"KnoxSurvivorRuntime")
        local id=runtime~=nil and runtime.idForCharacter(character) or nil
        if id==nil or not runtime.prepareVehicle(id) then return false,"survivor_busy" end
        phase="driving"
    else
        if occupied~=vehicle and not usableDriverSeat(character,vehicle) then return false,"driver_seat_unavailable" end
        if occupied==vehicle and (vehicle:isSeatOccupied(0) or reserved(vehicle,0,character)
            or not vehicle:isSeatInstalled(0)) then return false,"driver_seat_unavailable" end
        local built,actions=pcall(function()
            if occupied==vehicle then
                return {assert(ISSwitchVehicleSeat:new(character,0,vehicle:getSeat(character)))}
            end
            return {assert(ISPathFindAction:pathToVehicleSeat(character,vehicle,0)),
                assert(ISEnterVehicle:new(character,vehicle,0))}
        end)
        if not built then return false,"vehicle_action_failed" end
        local queued,result=queueActions(character,vehicle,0,actions)
        if not queued then return false,result end
    end
    -- prepareVehicle interrupts the old duty and cancels its vehicle lease.
    -- Publish this new run AFTER that boundary, so it cannot cancel itself.
    driverRuns[character]={vehicle=vehicle,route=route,index=1,goal=route[#route],
        geometry=geometry,phase=phase,deadline=getTimestampMs()+DRIVER_TIMEOUT_MS,
        health=health(character),lastProgress=getTimestampMs(),lastX=vehicle:getX(),lastY=vehicle:getY()}
    return true,destination~=nil and "driving_to_destination" or "driving_ahead"
end

function CompanionVehicles.driveAhead(character,vehicle)
    return startDrive(character,vehicle,nil)
end
function CompanionVehicles.driveTo(character,vehicle,x,y,z)
    return startDrive(character,vehicle,{x=x,y=y,z=z})
end
function CompanionVehicles.stopDriving(character)
    local active=driverRuns[character]~=nil
    -- Player takeover preserves the passengers: they keep riding with the
    -- new driver instead of being settled by the abort path below.
    CompanionVehicles.cancel(character, true)
    return active
end
function CompanionVehicles.driverStatus(character)
    local run=driverRuns[character]
    return run~=nil and {phase=run.phase,blocked=run.blockedSince~=nil,destination=run.goal,
        waypoint=run.index,waypoints=#run.route,remaining=run.remaining,routeError=run.routeError,
        reason=run.blockedReason,targetSpeed=run.targetSpeed} or nil
end

-- Attach a committed passenger roster to an active driver run so any abort
-- or arrival rolls it back through the same lease/exit ownership above.
-- Silently ignores a missing run or a roster for another vehicle.
function CompanionVehicles.setRunPassengers(character, vehicle, roster)
    local run = driverRuns[character]
    if run == nil or (vehicle ~= nil and run.vehicle ~= nil and run.vehicle ~= vehicle) then
        return false
    end
    run.passengers = roster
    return true
end

local function finishDrive(character,reason)
    -- cancel() settles the attached passenger roster as part of teardown,
    -- so every abort and arrival shares one rollback owner.
    CompanionVehicles.cancel(character)
    if KnoxActivityFeed~=nil and KnoxActivityFeed.speak~=nil then
        KnoxActivityFeed.speak(character,reason=="arrived" and "We've arrived."
            or "I'm stopping here. I can't safely continue.")
    end
    print("[KnoxSurvivors][Driving] stop="..tostring(reason))
end

local function tickDrive(character,run,now)
    local vehicle=run.vehicle
    if now>=run.deadline or character:isDead() or not KnoxSettings.enableExperimentalNpcDriving() then
        finishDrive(character,"interrupted");return
    end
    if run.phase=="boarding" then
        if character:getVehicle()==vehicle and vehicle:getDriver()==character then
            run.phase="driving";run.lastProgress=now
        elseif not CompanionVehicles.isBusy(character) then finishDrive(character,"boarding_failed") end
        return
    end
    if character:getVehicle()~=vehicle or vehicle:getDriver()~=character then
        finishDrive(character,"driver_changed");return
    end
    local current=vehicle:getSquare()
    local controller=vehicle:getController()
    local controls=controller~=nil and controller:getClientControls() or nil
    local healthNow=health(character)
    if current==nil or controls==nil or not vehicle:isDriveable() or not vehicle:isEngineRunning()
        or (healthNow~=nil and run.health~=nil and healthNow<run.health) then
        finishDrive(character,"vehicle_unavailable");return
    end
    if current:getZ()~=run.goal.z then finishDrive(character,"floor_changed");return end
    if vehicle.getVehicleTowing~=nil and vehicle:getVehicleTowing()~=nil
        or vehicle.getVehicleTowedBy~=nil and vehicle:getVehicleTowedBy()~=nil then
        finishDrive(character,"towing_changed");return
    end
    local x,y=vehicle:getX(),vehicle:getY()
    local speed=math.abs(vehicle:getCurrentSpeedKmHour())
    local goalDistance=math.sqrt((run.goal.x-x)^2+(run.goal.y-y)^2)
    if goalDistance<=DRIVER_STOP_DISTANCE and run.index>=#run.route-2 and speed<=1 then
        finishDrive(character,"arrived");return
    end
    local nav=KnoxVehicleNavigation
    local tracking=nav.follow(run.route,run.index,x,y,speed)
    run.index,run.remaining,run.routeError=tracking.index,tracking.remaining,tracking.error
    local fx,fy=nav.forward(vehicle)
    if fx==nil then finishDrive(character,"heading_unavailable");return end
    local heading=math.atan2(fy,fx)
    local rearX,rearY=nav.rearPosition(x,y,heading,run.geometry)
    local aimX,aimY=nav.rearPosition(tracking.aim.x,tracking.aim.y,tracking.aim.heading,run.geometry)
    local dx,dy=aimX-rearX,aimY-rearY
    local distance=math.sqrt(dx*dx+dy*dy)
    local dot=(fx*dx+fy*dy)/math.max(0.1,distance)
    local cross=(fx*dy-fy*dx)/math.max(0.1,distance)
    local limit=KnoxSettings.npcDrivingSpeed~=nil and KnoxSettings.npcDrivingSpeed() or 20
    local command,desired=nav.controls(speed,tracking.remaining,dot,cross,limit,run.geometry,distance,tracking.curvature)
    local nativeLimit=vehicle:getScript():getSteeringClamp(speed)
    command.steering=math.max(-nativeLimit,math.min(nativeLimit,command.steering))
    run.targetSpeed=desired
    if now>=(run.nextSafetyCheck or 0) then
        run.nextSafetyCheck=now+150
        local context=nav.context(vehicle,run.geometry,character)
        local lookahead=nav.stoppingDistance(speed)
        local intended=math.tan(command.steering)/run.geometry.wheelbase
        local actual=controller.getVehicleSteering~=nil
            and -math.tan(controller:getVehicleSteering())/run.geometry.wheelbase or intended
        -- Cover native steering lag as well as the intended bend. Reset the
        -- world cache each check so moving people/vehicles cannot remain clear.
        run.laneClear=nav.arcClear(context,x,y,heading,intended,lookahead,current:getZ())
            and nav.arcClear(context,x,y,heading,actual,lookahead,current:getZ())
            and nav.arcClear(context,x,y,heading,(actual+intended)/2,lookahead,current:getZ())
    end
    if not run.laneClear or dot<0 or tracking.error>3 then
        controls.forward,controls.backward,controls.brake,controls.shift=false,false,true,false
        controls.steering=(dot>=0 and tracking.error<=3) and command.steering or 0
        run.blockedReason=tracking.error>3 and "off_route" or (dot<0 and "route_behind" or "obstacle")
        run.blockedSince=run.blockedSince or now
        if now-run.blockedSince>15000 then finishDrive(character,"route_blocked");return end
        if speed<=1 and now>=(run.nextReplan or 0) then
            run.nextReplan=now+3000
            local replacement=nav.plan(vehicle,run.goal.x,run.goal.y,run.goal.z,run.geometry,character)
            if replacement~=nil then
                run.route,run.index=replacement,1
                run.nextSafetyCheck=0 -- a different bend needs a fresh sweep
            end
        end
        return
    end
    if run.blockedSince~=nil then
        -- Deliberately waiting for an obstruction is not failed motion.
        run.lastProgress,run.lastX,run.lastY=now,x,y
    end
    run.blockedSince,run.blockedReason=nil,nil
    if (x-run.lastX)^2+(y-run.lastY)^2>=1 then
        run.lastProgress,run.lastX,run.lastY=now,x,y
    elseif now-run.lastProgress>15000 then finishDrive(character,"no_progress");return end
    for key,value in pairs(command) do controls[key]=value end
end

function CompanionVehicles.tick()
    -- Expire passenger leases even when their ground AI is no longer ticking.
    for character in pairs(pending) do CompanionVehicles.isBusy(character) end
    for character,run in pairs(driverRuns) do
        local ok,reason=pcall(tickDrive,character,run,getTimestampMs())
        if not ok then
            -- Failures cannot leave throttle latched on the native controller.
            CompanionVehicles.cancel(character)
            print("[KnoxSurvivors][Driving] error="..tostring(reason))
        end
    end
    retryAwaitingExits()
end
return CompanionVehicles
