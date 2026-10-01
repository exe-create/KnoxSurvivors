require "KS_BaseStorage"
require "KS_SurvivorInventoryActions"
require "KS_SurvivorNeeds"
require "TimedActions/ISToggleStoveAction"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

local Cooking = {}
KnoxBaseCooking = Cooking
local owners = setmetatable({}, {__mode="k"})
local nextScan = setmetatable({}, {__mode="k"})

local function call(object, method, fallback, ...)
    if object == nil or object[method] == nil then return fallback end
    local ok, result = pcall(object[method], object, ...)
    if ok and result ~= nil then return result end
    return fallback
end

local function enabled()
    return KnoxSettings == nil or KnoxSettings.baseCookingEnabled == nil or KnoxSettings.baseCookingEnabled()
end

local function near(character, square)
    local origin = character:getCurrentSquare()
    return origin ~= nil and square ~= nil and origin:getZ() == square:getZ()
        and (origin:getX()-square:getX())^2+(origin:getY()-square:getY())^2 <= 2
        and (origin == square or not call(origin,"isSomethingTo",true,square))
end

function Cooking.canCook(item)
    if not call(item,"IsFood",false) or not call(item,"isCookable",false)
        or call(item,"isCooked",false) or call(item,"isBurnt",false)
        or call(item,"isRotten",true) or call(item,"isPoison",true)
        or call(item,"getPoisonPower",1) > 0 or call(item,"isFavorite",false)
        or call(item,"getHungerChange",0) >= -0.01
        or call(item,"getMetalValue",1) > 0 then return false end
    -- Recipe callbacks/replacements can change item identity and produce metal
    -- cookware. This executor handles direct native heating only.
    local replacements = call(item,"getReplaceOnCooked",nil)
    if replacements ~= nil and replacements:size() > 0 then return false end
    if call(item,"getOnCooked","") ~= "" then return false end
    local cook, burn = call(item,"getMinutesToCook",0),call(item,"getMinutesToBurn",0)
    return cook > 0 and burn-cook >= 6 and call(item,"getCookingTime",0) < burn-4
end

local function foodIn(container, predicate, depth)
    if container == nil or depth > 4 then return nil end
    local items = container:getItems()
    for i=0,items:size()-1 do
        local item = items:get(i)
        if predicate(item) then return item,container end
        if call(item,"IsInventoryContainer",false) then
            local found,source=foodIn(item:getInventory(),predicate,depth+1)
            if found ~= nil then return found,source end
        end
    end
end

function Cooking.hasReadyMeal(base)
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        local store=KnoxBaseStorage.resolvePolicy(policy)
        if store~=nil and foodIn(store.container,KnoxSurvivorNeeds.isSafeFood,0)~=nil then return true end
    end
    return false
end

local function foodSource(base,character)
    local predicate=function(item) return owners[item]==nil and Cooking.canCook(item) end
    local item,source=foodIn(character:getInventory(),predicate,0)
    if item~=nil then return {item=item,container=source} end
    local origin=character:getCurrentSquare()
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        if math.abs((tonumber(policy.z) or 0)-origin:getZ())<=2
            and ((tonumber(policy.x) or math.huge)-origin:getX())^2
                + ((tonumber(policy.y) or math.huge)-origin:getY())^2<=32*32 then
            local store=KnoxBaseStorage.resolvePolicy(policy)
            if store~=nil then
                item,source=foodIn(store.container,predicate,0)
                if item~=nil then return {item=item,container=source,square=store.square,policy=policy.key} end
            end
        end
    end
end

local function usable(object)
    -- Microwaves and stoves are both valid cooking areas. Microwave timers
    -- shut off heat automatically; stove timers are alarms only, so stove
    -- cooks are monitored and shut off manually in step().
    if object == nil or instanceof == nil then return false end
    local ok, isStove = pcall(function() return instanceof(object, "IsoStove") end)
    if not ok or isStove ~= true then return false end
    if call(object, "isBroken", true) then return false end
    if call(object, "getObjectIndex", -1) == -1 then return false end
    local isMicrowave = call(object, "isMicrowave", false)
    local container = call(object, "getContainer", nil)
    -- Microwaves require power; stoves require power or fuel heat.
    if isMicrowave then
        return call(container, "isPowered", false) == true
    end
    if call(container, "isPowered", false) == true then return true end
    -- Residual heat is observable here. Fuel-backed stove semantics are not
    -- inferred without a supported native fuel signal.
    local temp = call(object, "getCurrentTemperature", 0)
    if tonumber(temp) ~= nil and tonumber(temp) > 0 then return true end
    return false
end

local function applianceType(object)
    if call(object, "isMicrowave", false) then return "microwave" end
    return "stove"
end

local function markedItem(object,base)
    local mark=object:getModData().KnoxCooking
    if type(mark)~="table" or mark.baseId~=base.id then return nil end
    local container=object:getContainer()
    local items=container:getItems()
    if items:size()~=1 then return nil end
    local item=items:get(0)
    if tostring(call(item,"getID",""))==mark.itemId then return item end
end

local function bounds(region)
    local x1,y1=tonumber(region.x1 or region.minX),tonumber(region.y1 or region.minY)
    local x2=tonumber(region.x2 or region.maxX) or (x1 and x1+(region.width or 1)-1)
    local y2=tonumber(region.y2 or region.maxY) or (y1 and y1+(region.height or 1)-1)
    if x1==nil or y1==nil then return nil end
    return math.min(x1,x2),math.min(y1,y2),math.max(x1,x2),math.max(y1,y2)
end

local function inRegion(square,region)
    local x1,y1,x2,y2=bounds(region)
    return x1~=nil and square:getX()>=x1 and square:getX()<=x2
        and square:getY()>=y1 and square:getY()<=y2
end

local function allowed(base,square,zoneId)
    if zoneId~=nil then
        local zone=base.zones and base.zones[zoneId]
        return zone~=nil and zone.enabled~=false and zone.type=="cooking"
            and square:getZ()==(tonumber(zone.z) or 0) and inRegion(square,zone)
    end
    return KnoxBaseManager~=nil and KnoxBaseManager.containsSquare(base,square)
end

function Cooking.findTask(base,character)
    if not enabled() or base==nil or character==nil or getCell==nil or getCell()==nil then return nil,"cooking_unavailable" end
    local origin=character:getCurrentSquare()
    if origin==nil then return nil,"cooking_unavailable" end
    local now=getTimestampMs~=nil and tonumber(getTimestampMs()) or nil
    if now~=nil and nextScan[base]~=nil and now<nextScan[base] then return nil,"kitchen_scan_cooldown" end
    local source=foodSource(base,character)
    local regions={}
    local hasCookingArea=false
    for _,zone in pairs(base.zones or {}) do
        if zone.type=="cooking" then
            hasCookingArea=true
            if zone.enabled~=false then regions[#regions+1]=zone end
        end
    end
    if hasCookingArea and #regions==0 then return nil,"cooking_areas_disabled" end
    if #regions==0 then
        local home=base.territory or base.home
        if home~=nil then
            for z=math.max(0,origin:getZ()-2),origin:getZ()+2 do
                regions[#regions+1]={minX=home.minX,minY=home.minY,maxX=home.maxX,maxY=home.maxY,
                    width=home.width,height=home.height,z=z}
            end
        end
    end
    for _,region in ipairs(regions) do
        local minX,minY,maxX,maxY=bounds(region)
        local x1=math.max(origin:getX()-24,minX or math.huge)
        local y1=math.max(origin:getY()-24,minY or math.huge)
        local x2=math.min(origin:getX()+24,maxX or -math.huge)
        local y2=math.min(origin:getY()+24,maxY or -math.huge)
        for x=x1,x2 do for y=y1,y2 do
            local square=getCell():getGridSquare(x,y,region.z or 0)
            if square~=nil and allowed(base,square,region.id) then
                local objects=square:getObjects()
                for i=0,objects:size()-1 do
                    local object=objects:get(i)
                    if usable(object) and owners[object]==nil then
                        local recovered=markedItem(object,base)
                        local empty=object:getContainer():getItems():isEmpty()
                        local mark=object:getModData().KnoxCooking
                        if mark~=nil and mark.baseId==base.id and empty and not object:Activated() then
                            object:getModData().KnoxCooking=nil
                            mark=nil
                        end
                        if (recovered~=nil and (Cooking.canCook(recovered) or KnoxSurvivorNeeds.isSafeFood(recovered)))
                            or (source~=nil and empty and not object:Activated() and mark==nil) then
                            return {id="cook:"..tostring(base.id),action="cook",x=x,y=y,z=square:getZ(),
                                objectIndex=object:getObjectIndex(),spriteName=call(call(object,"getSprite",nil),"getName",""),
                                zoneId=region.id},"found"
                        end
                    end
                end
            end
        end end
    end
    if now~=nil then nextScan[base]=now+10000 end
    return nil, source==nil and "no_microwave_safe_ingredients" or "no_available_powered_microwave"
end

local function resolve(base,target)
    local cell=getCell~=nil and getCell() or nil
    local square=cell~=nil and cell:getGridSquare(target.x,target.y,target.z) or nil
    if square==nil or not allowed(base,square,target.zoneId) then return nil end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if usable(object) and object:getObjectIndex()==target.objectIndex
            and call(call(object,"getSprite",nil),"getName","")==target.spriteName then return object end
    end
end

function Cooking.resolveTaskSquare(base,target,character)
    local object=resolve(base,target)
    return object~=nil and AdjacentFreeTileFinder.Find(object:getSquare(),character) or nil
end

function Cooking.begin(base,target,character,id)
    local object=resolve(base,target)
    if object==nil or owners[object]~=nil then return nil,"cooking_appliance_unavailable" end
    local recovered=markedItem(object,base)
    local source=recovered~=nil and {item=recovered,container=object:getContainer()} or foodSource(base,character)
    if source==nil or owners[source.item]~=nil then return nil,"cooking_ingredient_unavailable" end
    if recovered==nil and (object:Activated() or not object:getContainer():getItems():isEmpty()
        or object:getModData().KnoxCooking~=nil) then return nil,"cooking_appliance_in_use" end
    local plan={object=object,item=source.item,source=source,baseId=base.id,target=target,id=id,
        phase=recovered~=nil and "heat" or "collect",recovered=recovered~=nil}
    owners[object],owners[plan.item]=plan,plan
    return plan,"ready"
end

local HeatAction=ISToggleStoveAction:derive("KnoxMicrowaveHeatAction")
function HeatAction:isValid()
    local p=self.plan
    return enabled() and owners[self.object]==p and usable(self.object) and near(self.character,self.object:getSquare())
        and not self.object:Activated() and self.object:getContainer():getItems():size()==1
        and self.object:getContainer():contains(p.item) and Cooking.canCook(p.item)
end
function HeatAction:complete()
    if not self:isValid() then return false end
    self.object:setMaxTemperature(100)
    -- Microwaves shut their own heat off when the timer ends, so a short
    -- timer means endless re-activation loops. Give microwave cooks a full
    -- ten-minute run; the heat phase still stops it the moment the meal is
    -- done. Stove timers are alarms only and keep their cadence.
    if call(self.object, "isMicrowave", false) == true then
        self.object:setTimer(600)
    else
        self.object:setTimer(120)
    end
    return ISToggleStoveAction.complete(self)
end

local function stopHeat(plan,character)
    local object=plan.object
    if owners[object]==plan and near(character,object:getSquare()) and object:getObjectIndex()~=-1
        and object:getModData().KnoxCooking~=nil
        and object:getModData().KnoxCooking.baseId==plan.baseId and object:Activated() then
        object:PlayToggleSound()
        object:Toggle()
    end
    -- If physically displaced, never operate an appliance remotely. A still
    -- running microwave is wound down to a minute instead: setTimer is a
    -- plain field write, safe without proximity, and bounds unattended heat.
    pcall(function()
        if object:getObjectIndex() ~= -1 and object:Activated()
            and object:isMicrowave()
            and object:getModData().KnoxCooking ~= nil
            and object:getModData().KnoxCooking.baseId == plan.baseId then
            object:setTimer(1)
        end
    end)
end

function Cooking.cancel(plan,character)
    if plan==nil then return end
    local queue=ISTimedActionQueue.getTimedActionQueue(character)
    if plan.action~=nil and queue:indexOf(plan.action)~=-1 then
        if queue.current==plan.action then ISTimedActionQueue.clear(character)
        else plan.action:forceCancel();queue:removeFromQueue(plan.action) end
    end
    stopHeat(plan,character)
    local mark=plan.object:getModData().KnoxCooking
    if mark~=nil and mark.baseId==plan.baseId and mark.itemId==tostring(plan.item:getID())
        and not plan.object:getContainer():contains(plan.item) then plan.object:getModData().KnoxCooking=nil end
    if owners[plan.object]==plan then owners[plan.object]=nil end
    if owners[plan.item]==plan then owners[plan.item]=nil end
end

local function move(plan,square,character,bridge,ticks,phase)
    local approach=AdjacentFreeTileFinder.Find(square,character)
    if approach==nil then return "failed","kitchen_unreachable" end
    local result=tostring(bridge:moveNpc(plan.id,approach))
    if result:find("MOVE_STARTED",1,true)~=1 then return "failed","kitchen_route:"..result end
    plan.phase,plan.afterMove,plan.moveStarted="move",phase,ticks
    return "working"
end

local function transfer(plan,character,source,destination,nextPhase)
    local action,reason=KnoxInventoryActions.queueTransfer(character,plan.item,source,destination,nil)
    if action==nil then return "failed",reason end
    plan.action,plan.phase,plan.destination,plan.afterTransfer=action,"transfer",destination,nextPhase
    return "working"
end

function Cooking.step(plan,character,base,bridge,ticks)
    if not enabled() or base==nil or base.id~=plan.baseId or resolve(base,plan.target)~=plan.object then
        return "failed","cooking_appliance_or_area_unavailable"
    end
    local object,inventory=plan.object,character:getInventory()
    local container=object:getContainer()
    if plan.phase=="move" then
        local result=tostring(bridge:tickNpc(plan.id))
        if result=="Succeeded" then plan.phase=plan.afterMove
        elseif result:find("Failed",1,true) or ticks-plan.moveStarted>1800 then return "failed","kitchen_route:"..result end
        return "working"
    end
    local queue=ISTimedActionQueue.getTimedActionQueue(character)
    if not character:getCharacterActions():isEmpty()
        or (plan.action~=nil and queue:indexOf(plan.action)~=-1) then return "working" end
    if plan.phase=="transfer" then
        if not plan.destination:contains(plan.item) then return "failed","cooking_transfer_not_completed" end
        plan.phase,plan.action=plan.afterTransfer,nil
    end
    if plan.phase=="collect" then
        local actualSource
        if plan.source.policy~=nil then
            for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
                if policy.key==plan.source.policy then
                    local store=KnoxBaseStorage.resolvePolicy(policy)
                    if store~=nil then
                        local _,source=foodIn(store.container,function(item) return item==plan.item end,0)
                        actualSource=source
                    end
                end
            end
        else
            local _,source=foodIn(inventory,function(item) return item==plan.item end,0)
            actualSource=source
        end
        if actualSource~=plan.source.container then return "failed","cooking_source_no_longer_assigned" end
        if not Cooking.canCook(plan.item) or not plan.source.container:contains(plan.item) then return "failed","cooking_ingredient_changed" end
        if plan.source.square~=nil and not near(character,plan.source.square) then
            return move(plan,plan.source.square,character,bridge,ticks,"collect")
        end
        if plan.source.container==inventory then plan.phase="load"
        else return transfer(plan,character,plan.source.container,inventory,"load") end
    end
    if plan.phase=="load" then
        if not inventory:contains(plan.item) then return "failed","cooking_ingredient_missing" end
        if not near(character,object:getSquare()) then return move(plan,object:getSquare(),character,bridge,ticks,"load") end
        if object:Activated() or not container:getItems():isEmpty() then return "failed","cooking_appliance_in_use" end
        if not Cooking.canCook(plan.item) then return "failed","cooking_ingredient_changed" end
        local status,reason=transfer(plan,character,inventory,container,"heat")
        if status=="working" then
            object:getModData().KnoxCooking={baseId=base.id,itemId=tostring(plan.item:getID())}
        end
        return status,reason
    end
    if plan.phase=="heat" then
        if not near(character,object:getSquare()) then return move(plan,object:getSquare(),character,bridge,ticks,"heat") end
        if markedItem(object,base)~=plan.item then return "failed","cooking_contents_changed" end
        if call(plan.item,"isCooked",false) and KnoxSurvivorNeeds.isSafeFood(plan.item) then
            stopHeat(plan,character)
            return transfer(plan,character,container,inventory,"deposit")
        end
        if not Cooking.canCook(plan.item) then return "failed","cooking_food_no_longer_suitable" end
        character:faceThisObject(object)
        if not object:Activated() then
            local now=getGameTime():getWorldAgeHours()
            plan.heatStarted=plan.heatStarted or now
            if now-plan.heatStarted>2 then return "failed","cooking_heat_timeout" end
            local action=HeatAction:new(character,object)
            action.plan=plan
            ISTimedActionQueue.add(action)
            if queue:indexOf(action)==-1 then return "failed","cooking_heat_action_not_queued" end
            plan.action=action
        end
        return "working"
    end
    if plan.phase=="deposit" then
        local mark=object:getModData().KnoxCooking
        if mark~=nil and mark.baseId==base.id and mark.itemId==tostring(plan.item:getID()) then object:getModData().KnoxCooking=nil end
        if not inventory:contains(plan.item) then return "failed","cooked_meal_missing" end
        if not KnoxSurvivorNeeds.isSafeFood(plan.item) then return "failed","cooked_meal_unsafe" end
        if plan.personal then return "done","meal_ready_to_eat" end
        local destination=KnoxBaseStorage.findDepositTrip(base,character,plan.item)
        if destination==nil then return "done","meal_retained_storage_full" end
        if not near(character,destination.square) then return move(plan,destination.square,character,bridge,ticks,"deposit") end
        return transfer(plan,character,inventory,destination.container,"done")
    end
    if plan.phase=="done" then return "done","cooked_food_stored" end
    return "failed","unknown_cooking_phase"
end

return Cooking
