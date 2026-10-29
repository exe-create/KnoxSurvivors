require "KS_Settings"
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
local function enabled()
    return KnoxSettings.enableExperimentalEngineWork ~= nil
        and KnoxSettings.enableExperimentalEngineWork() and ISRepairEngine ~= nil
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
    if not enabled() or tonumber(call(vehicle,"getSqlId"))==nil
        or tonumber(call(vehicle,"getSqlId"))<=0 then return nil end
    local speed=tonumber(call(vehicle,"getCurrentSpeedKmHour"))
    if speed==nil or speed~=speed or math.abs(speed)>.1
        or call(vehicle,"isEngineRunning")~=false then return nil end
    local part=call(vehicle,"getPartById","Engine")
    local cond=condition(part)
    local script=call(vehicle,"getScript")
    local level=tonumber(call(script,"getEngineRepairLevel"))
    local skill=Perks ~= nil and tonumber(call(character,"getPerkLevel",Perks.Mechanics)) or nil
    if cond==nil or (cond>=100 and not allowCompleted) or level==nil or skill==nil or skill<level then return nil end
    local cover=call(vehicle,"getPartById","EngineDoor")
    if cover ~= nil and call(cover,"getInventoryItem") ~= nil then
        local door=call(cover,"getDoor")
        if door==nil or call(door,"isLocked")~=false then return nil end
        local open=call(door,"isOpen")
        if open==nil or (open~=true and (ISOpenVehicleDoor==nil or ISCloseVehicleDoor==nil)) then return nil end
    end
    local square=call(vehicle,"getSquareForArea",call(part,"getArea"))
    if not inside(base,call(vehicle,"getSquare")) or not inside(base,square)
        or call(square,"canStand")~=true then return nil end
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
    if tool==nil then return nil end
    local full=call(tool,"getFullType")
    if type(full)~="string" then return nil end
    local required={items={[full]=1,["Base.EngineParts"]=1},itemRules={[full]={usable=true}}}
    if storage ~= nil and storage.requirementsAvailable ~= nil
        and storage.requirementsAvailable(base,character,required) then return required end
    return nil
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
return Engine
