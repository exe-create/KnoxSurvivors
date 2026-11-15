require "KS_Settings"
pcall(require, "ISUI/ISContextMenu")
pcall(require, "Vehicles/TimedActions/ISRepairEngine")
pcall(require, "Vehicles/TimedActions/ISOpenVehicleDoor")
pcall(require, "Vehicles/TimedActions/ISCloseVehicleDoor")

-- Executor for the existing Repair task owner; no scheduler or vehicle ledger.
local Engine = rawget(_G,"KnoxBaseEngineRepairs") or {}
_G.KnoxBaseEngineRepairs = Engine
local function call(object,method,...)
    if object == nil or object[method] == nil then return nil end
    local ok,value=pcall(object[method],object,...)
    if ok then return value end
    return nil
end
local function settingEnabled()
    return KnoxSettings ~= nil and KnoxSettings.enableExperimentalEngineWork ~= nil
        and KnoxSettings.enableExperimentalEngineWork() == true
end
local function enabled()
    return settingEnabled() and ISRepairEngine ~= nil
end
local function vehicles()
    local list=call(getCell ~= nil and getCell() or nil,"getVehicles")
    local result={}
    if list ~= nil then
        if list.iterator ~= nil then
            local iterator=list:iterator()
            while iterator:hasNext() do result[#result+1]=iterator:next() end
        else
            for i=0,list:size()-1 do result[#result+1]=list:get(i) end
        end
    end
    return result
end
local function items(character)
    local result,seen,readable={},{},true
    local function visit(container)
        if container == nil then readable=false return end
        if seen[container] then return end
        seen[container]=true
        local list=call(container,"getItems")
        if list == nil then readable=false return end
        for i=0,list:size()-1 do
            local item=list:get(i)
            result[#result+1]=item
            if call(item,"IsInventoryContainer") == true then visit(call(item,"getInventory")) end
        end
    end
    visit(call(character,"getInventory"))
    return result,readable
end
local function wrench(item)
    local tag=ItemTag ~= nil and ItemTag.WRENCH or nil
    return call(item,"isBroken") ~= true and (tag ~= nil and call(item,"hasTag",tag)==true
        or tag == nil and call(item,"getFullType")=="Base.Wrench")
end
local function condition(part)
    local value=tonumber(call(part,"getCondition"))
    return value ~= nil and value==value and value>=0 and value<=100 and value or nil
end
local function inside(base,square)
    local area=base ~= nil and (base.territory or base.home) or nil
    if area == nil or square == nil then return false end
    local x,y,z=call(square,"getX"),call(square,"getY"),call(square,"getZ")
    local minX,minY=tonumber(area.minX),tonumber(area.minY)
    if x==nil or y==nil or minX==nil or minY==nil then return false end
    local maxX=tonumber(area.maxX) or minX+(tonumber(area.width) or 1)-1
    local maxY=tonumber(area.maxY) or minY+(tonumber(area.height) or 1)-1
    return z==(tonumber(area.z) or 0) and x>=minX and x<=maxX and y>=minY and y<=maxY
end
local function assess(base,vehicle,character,allowCompleted)
    if not settingEnabled() then return nil,"engine_work_disabled" end
    if ISRepairEngine == nil then return nil,"engine_action_unavailable" end
    local sqlId=tonumber(call(vehicle,"getSqlId"))
    if sqlId==nil or sqlId<=0 then return nil,"vehicle_state_unknown" end
    local speed=tonumber(call(vehicle,"getCurrentSpeedKmHour"))
    if speed==nil or speed~=speed then return nil,"vehicle_state_unknown" end
    if math.abs(speed)>.1 then return nil,"vehicle_moving" end
    local running=call(vehicle,"isEngineRunning")
    if running==true then return nil,"engine_running" end
    if running~=false then return nil,"vehicle_state_unknown" end
    local part=call(vehicle,"getPartById","Engine")
    local cond=condition(part)
    if cond==nil then return nil,"engine_condition_unreadable" end
    if cond>=100 and not allowCompleted then return nil,"engine_condition_complete" end
    local script=call(vehicle,"getScript")
    local level=tonumber(call(script,"getEngineRepairLevel"))
    if level==nil then return nil,"engine_script_unreadable" end
    local skill=Perks ~= nil and tonumber(call(character,"getPerkLevel",Perks.Mechanics)) or nil
    if skill==nil then return nil,"mechanics_skill_unreadable" end
    if skill<level then return nil,"mechanics_skill_too_low" end
    local cover=call(vehicle,"getPartById","EngineDoor")
    if cover ~= nil and call(cover,"getInventoryItem") ~= nil then
        local door=call(cover,"getDoor")
        if door==nil then return nil,"engine_hood_locked" end
        if call(door,"isLocked")~=false then return nil,"engine_hood_locked" end
        local open=call(door,"isOpen")
        if open==nil then return nil,"engine_hood_state_unknown" end
        if open~=true and (ISOpenVehicleDoor==nil or ISCloseVehicleDoor==nil) then
            return nil,"engine_hood_unavailable"
        end
    end
    local square=call(vehicle,"getSquareForArea",call(part,"getArea"))
    if not inside(base,call(vehicle,"getSquare")) then return nil,"vehicle_outside_base" end
    if not inside(base,square) then return nil,"engine_area_outside_base" end
    if call(square,"canStand")~=true then return nil,"engine_area_unreachable" end
    return {kind="engine",vehicle=vehicle,part=part,hood=cover,base=base,character=character,
        square=square,approach=square,vehicleSqlId=vehicle:getSqlId(),
        scriptName=tostring(call(script,"getName") or "")}
end
local function requirements(character,base)
    local tool=nil
    for _,item in ipairs(items(character)) do if wrench(item) then tool=item break end end
    local storage=rawget(_G,"KnoxBaseStorage")
    if tool==nil and storage ~= nil and storage.findItemType ~= nil then
        local _,stored=storage.findItemType(base,wrench)
        tool=stored
    end
    if tool==nil then return nil,"missing_wrench" end
    local full=call(tool,"getFullType")
    if type(full)~="string" then return nil,"missing_wrench" end
    local required={items={[full]=1,["Base.EngineParts"]=1},itemRules={[full]={usable=true}}}
    if storage ~= nil and storage.requirementsAvailable ~= nil
        and storage.requirementsAvailable(base,character,required) then return required,"available" end
    return nil,"missing_engine_parts"
end
function Engine.findTask(base,character,eligible)
    if not enabled() then return nil end
    for _,vehicle in ipairs(vehicles()) do
        local resolved=assess(base,vehicle,character)
        local required=resolved ~= nil and requirements(character,base) or nil
        if required ~= nil then
            local target={id="repair:engine:"..tostring(resolved.vehicleSqlId),action="repair_engine",
                vehicleSqlId=resolved.vehicleSqlId,scriptName=resolved.scriptName,
                x=resolved.square:getX(),y=resolved.square:getY(),z=resolved.square:getZ(),
                requiredItems=required.items,requiredItemRules=required.itemRules}
            if eligible==nil or eligible(target) then return target,"found" end
        end
    end
    return nil
end
function Engine.resolveTarget(base,target,character,allowCompleted)
    for _,vehicle in ipairs(vehicles()) do
        if tonumber(call(vehicle,"getSqlId"))==tonumber(target.vehicleSqlId) then
            local resolved=assess(base,vehicle,character,allowCompleted)
            if resolved ~= nil and resolved.scriptName==target.scriptName then return resolved,"resolved" end
        end
    end
    return nil,"engine_target_unavailable"
end
function Engine.snapshot(target)
    if not enabled() then return nil end
    local resolved=Engine.resolveTarget(target.base,target,target.character)
    if resolved==nil or resolved.vehicle~=target.vehicle or resolved.part~=target.part then return nil end
    local captured={}
    local carried,readable=items(target.character)
    if not readable then return nil end
    for _,item in ipairs(carried) do
        if call(item,"getFullType")=="Base.EngineParts" then captured[#captured+1]=item end
    end
    if #captured==0 then return nil end
    return {condition=condition(target.part),parts=captured}
end
function Engine.isComplete(target,before)
    if type(before)~="table" or type(before.parts)~="table" then return false end
    local current=nil
    for _,vehicle in ipairs(vehicles()) do
        if vehicle==target.vehicle and tonumber(call(vehicle,"getSqlId"))==target.vehicleSqlId
            and call(vehicle,"getPartById","Engine")==target.part then current=condition(target.part) break end
    end
    local prior=tonumber(before.condition)
    if current==nil or prior==nil or prior~=prior or prior<0 or prior>100 or current<=prior then return false end
    local carried={}
    local values,readable=items(target.character)
    if not readable then return false end
    for _,item in ipairs(values) do carried[item]=true end
    for _,item in ipairs(before.parts) do if not carried[item] then return true end end
    return false
end
function Engine.queueAction(character,target)
    local current=Engine.resolveTarget(target.base,target,character)
    if current==nil or current.vehicle~=target.vehicle or current.part~=target.part then
        return nil,"engine_target_unavailable"
    end
    local tool=nil
    for _,item in ipairs(items(character)) do if wrench(item) then tool=item break end end
    local baseline=Engine.snapshot(target)
    if tool==nil or baseline==nil or call(target.vehicle,"isInArea",target.part:getArea(),character)~=true then
        return nil,"engine_tools_parts_or_position_unavailable"
    end
    local action=ISRepairEngine:new(character,target.part,tool,300)
    local cover=current.hood
    local hasCover=cover~=nil and call(cover,"getInventoryItem")~=nil
    local opensHood=hasCover and call(call(cover,"getDoor"),"isOpen")==false
    local function carriesTool()
        for _,item in ipairs(items(character)) do if item==tool then return true end end
        return false
    end
    -- Vanilla isValid always returns true; retain native execution but enforce
    -- eligibility throughout its wait/perform boundary.
    function action:isValid()
        local fresh=Engine.resolveTarget(target.base,target,character)
        return fresh ~= nil and fresh.vehicle==target.vehicle and fresh.part==target.part
            and wrench(tool) and carriesTool()
            and Engine.snapshot(target)~=nil
            and (not hasCover or (fresh.hood==cover and call(call(cover,"getDoor"),"isOpen")==true))
            and call(target.vehicle,"isInArea",target.part:getArea(),character)==true
    end
    local function admit(native,stage)
        local ok,queue=pcall(ISTimedActionQueue.add,native)
        if not ok or queue==nil or ISTimedActionQueue.queues==nil
            or queue~=ISTimedActionQueue.queues[character] then return nil,stage.."_queue_refused" end
        return native
    end
    local function hoodAction(class,opening)
        local native=class:new(character,target.vehicle,cover)
        local valid=native.isValid
        function native:isValid()
            local fresh=Engine.resolveTarget(target.base,target,character,not opening)
            return fresh~=nil and fresh.vehicle==target.vehicle and fresh.vehicleSqlId==target.vehicleSqlId
                and fresh.scriptName==target.scriptName and fresh.part==target.part and fresh.hood==cover
                and call(target.vehicle,"isInArea",target.part:getArea(),character)==true
                and call(call(cover,"getDoor"),"isOpen")==not opening
                and valid~=nil and valid(self)==true
                and (not opening or (wrench(tool) and carriesTool() and Engine.snapshot(target)~=nil))
        end
        -- Native completion retains door transmission and alarms. These two
        -- helpers only select/collapse a local player's inventory UI.
        function native:selectContainerInLootWindow() end
        function native:collapseLootWindow() end
        return native
    end
    if opensHood then
        local accepted,reason=admit(hoodAction(ISOpenVehicleDoor,true),"engine_hood_open")
        if not accepted then return nil,reason end
    end
    local accepted,reason=admit(action,"engine")
    if not accepted then return nil,reason end
    if opensHood then
        accepted,reason=admit(hoodAction(ISCloseVehicleDoor,false),"engine_hood_close")
        if not accepted then return nil,reason end
    end
    return action,"queued"
end

-- One admission surface for the player-issued order. It returns the same
-- target and the same reasons the autonomous scan uses.
function Engine.assess(base,vehicle,character,allowCompleted)
    return assess(base,vehicle,character,allowCompleted)
end

local REFUSAL_TEXT = {
    engine_work_disabled="Experimental resident engine repairs are off. Enable them in Sandbox Options, Settlement page.",
    engine_action_unavailable="The native engine repair action is unavailable in this install.",
    survivor_unavailable="That resident is unavailable.",
    vehicle_state_unknown="The vehicle's state could not be read.",
    vehicle_moving="Stop the vehicle first, then ask them to repair the engine.",
    engine_running="Turn the engine off first.",
    engine_condition_unreadable="The engine condition could not be read.",
    engine_condition_complete="That engine is already in good repair.",
    engine_script_unreadable="This engine's repair requirement could not be read.",
    mechanics_skill_unreadable="Their Mechanics skill could not be read.",
    mechanics_skill_too_low="Their Mechanics skill is not high enough for this engine.",
    engine_hood_locked="The hood is locked.",
    engine_hood_state_unknown="The hood state could not be read.",
    engine_hood_unavailable="The hood cannot be opened here.",
    vehicle_outside_base="That vehicle is outside the base territory.",
    engine_area_outside_base="The engine work area is outside the base territory.",
    engine_area_unreachable="There is no standable spot beside that engine.",
    missing_wrench="They need a usable wrench.",
    missing_engine_parts="They need Engine Parts.",
    not_base_resident="They are not a resident of this base.",
    engine_target_unavailable="That engine repair is no longer available.",
    engine_tools_parts_or_position_unavailable="They need a wrench, Engine Parts and a clear spot beside the engine.",
    engine_queue_refused="The repair action was refused.",
}
function Engine.describe(reason)
    return REFUSAL_TEXT[reason] or "That engine repair is not available right now."
end

local function feedEvent(text)
    local feed=rawget(_G,"KnoxActivityFeed")
    if feed~=nil and feed.event~=nil then feed.event(text) end
end
local function nameForId(id)
    local persistence=rawget(_G,"KnoxPersistence")
    local identity=persistence~=nil and persistence.getSurvivorIdentity~=nil
        and persistence.getSurvivorIdentity(id) or nil
    local name=(tostring(identity~=nil and identity.forename or "").." "
        ..tostring(identity~=nil and identity.surname or "")):match("^%s*(.-)%s*$")
    return name~="" and name or tostring(id or "Resident")
end

function Engine.order(player,base,vehicle,character)
    if not settingEnabled() then
        feedEvent(Engine.describe("engine_work_disabled")); return false,"engine_work_disabled"
    end
    if character==nil then
        feedEvent(Engine.describe("survivor_unavailable")); return false,"survivor_unavailable"
    end
    local runtime=rawget(_G,"KnoxSurvivorRuntime")
    local id=runtime~=nil and runtime.idForCharacter~=nil and runtime.idForCharacter(character) or nil
    local persistence=rawget(_G,"KnoxPersistence")
    if id~=nil and persistence~=nil and persistence.getBaseResidentIds~=nil and base~=nil then
        local found=false
        for _,resident in ipairs(persistence.getBaseResidentIds(base.id) or {}) do
            if tostring(resident)==tostring(id) then found=true break end
        end
        if not found then
            feedEvent(Engine.describe("not_base_resident")); return false,"not_base_resident"
        end
    end
    local target,reason=assess(base,vehicle,character)
    if target==nil then feedEvent(Engine.describe(reason)); return false,reason end
    local required,requiredReason=requirements(character,base)
    if required==nil then feedEvent(Engine.describe(requiredReason)); return false,requiredReason end
    local action,queueReason=Engine.queueAction(character,target)
    if action==nil then feedEvent(Engine.describe(queueReason)); return false,queueReason end
    feedEvent(nameForId(id).." starts on the engine.")
    return true,"queued"
end

-- Player-facing order on a base vehicle. The menu lists real residents and the
-- tooltip is the same refusal the order itself would speak.
local function vehicleFrom(objects)
    for _,object in ipairs(objects or {}) do
        local vehicle=call(object,"getVehicle")
        if vehicle~=nil then return vehicle end
        if call(object,"getSqlId")~=nil and call(object,"getPartById")~=nil then return object end
    end
end
function Engine.addVehicleContextMenu(playerNum,context,worldObjects,test)
    if test or context==nil or ISContextMenu==nil then return end
    local player=getSpecificPlayer~=nil and getSpecificPlayer(playerNum) or nil
    local vehicle=vehicleFrom(worldObjects)
    if player==nil or vehicle==nil then return end
    local manager=rawget(_G,"KnoxBaseManager")
    local service=rawget(_G,"KnoxCompanionService")
    local playerId=service~=nil and service.getPlayerId~=nil and service.getPlayerId(player) or nil
    local base=manager~=nil and playerId~=nil and manager.getForOwner~=nil
        and manager.getForOwner("player",playerId) or nil
    if base==nil or not inside(base,call(vehicle,"getSquare")) then return end
    local root=context:addOption("Engine Repairs",nil,nil)
    local menu=ISContextMenu:getNew(context)
    context:addSubMenu(root,menu)
    if not settingEnabled() then
        local line=menu:addOption("Experimental Resident Engine Repairs is off",nil,nil)
        line.notAvailable=true
        line.tooltip=Engine.describe("engine_work_disabled")
        return
    end
    local persistence=rawget(_G,"KnoxPersistence")
    local ids=persistence~=nil and persistence.getBaseResidentIds~=nil
        and persistence.getBaseResidentIds(base.id) or {}
    if type(ids)~="table" or #ids==0 then
        local line=menu:addOption("No residents are assigned to this base",nil,nil)
        line.notAvailable=true
        return
    end
    local runtime=rawget(_G,"KnoxSurvivorRuntime")
    for _,residentId in ipairs(ids) do
        local character=runtime~=nil and runtime.getCharacter~=nil
            and runtime.getCharacter(residentId) or nil
        local target,reason=assess(base,vehicle,character)
        if target~=nil then
            local required,requiredReason=requirements(character,base)
            if required==nil then target,reason=nil,requiredReason end
        end
        local option=menu:addOption(nameForId(residentId),player,Engine.order,base,vehicle,character)
        if target==nil then
            option.notAvailable=true
            option.tooltip=Engine.describe(reason)
        end
    end
end
if Events~=nil and Events.OnFillWorldObjectContextMenu~=nil then
    Events.OnFillWorldObjectContextMenu.Add(Engine.addVehicleContextMenu)
end
return Engine
