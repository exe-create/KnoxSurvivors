require "KS_BaseStorage"
require "KS_SurvivorInventoryActions"
require "KS_SurvivorNeeds"
require "TimedActions/ISToggleStoveAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISAddItemInRecipe"
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
    -- Direct heating cannot safely handle callbacks or replacement items.
    local replacements = call(item,"getReplaceOnCooked",nil)
    if replacements ~= nil and replacements:size() > 0 then return false end
    if call(item,"getOnCooked","") ~= "" then return false end
    -- Keep safe raw ingredients (such as eggplant) for the recipe path or
    -- eating. Direct heating is for food unsafe to eat uncooked.
    if not call(item,"isbDangerousUncooked",false) then return false end
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

local function policyAllowsItem(policy,item,itemAvailable)
    return (itemAvailable==nil or itemAvailable(item)==true)
        and (KnoxBaseStorage.filterAllowsItem==nil
            or KnoxBaseStorage.filterAllowsItem(policy,item)==true)
end

function Cooking.hasReadyMeal(base,itemAvailable)
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        local store=KnoxBaseStorage.resolvePolicy(policy)
        if store~=nil and foodIn(store.container,function(item)
            -- An edible raw ingredient is emergency food, but it is not the
            -- cooked meal this check promises. Otherwise eggplant/tomato in
            -- storage prevent a hungry resident from preparing their recipe.
            return KnoxSurvivorNeeds.isSafeFood(item)
                and not call(item,"isFavorite",false)
                and (not call(item,"isCookable",false) or call(item,"isCooked",false))
                and policyAllowsItem(policy,item,itemAvailable)
        end,0)~=nil then return true end
    end
    return false
end

local function foodSource(base,character,itemAvailable)
    local predicate=function(item) return owners[item]==nil and Cooking.canCook(item)
        and (itemAvailable==nil or itemAvailable(item)==true) end
    local item,source=foodIn(character:getInventory(),predicate,0)
    if item~=nil then return {item=item,container=source} end
    local origin=character:getCurrentSquare()
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        if math.abs((tonumber(policy.z) or 0)-origin:getZ())<=2
            and ((tonumber(policy.x) or math.huge)-origin:getX())^2
                + ((tonumber(policy.y) or math.huge)-origin:getY())^2<=32*32 then
            local store=KnoxBaseStorage.resolvePolicy(policy)
            if store~=nil then
                item,source=foodIn(store.container,function(candidate)
                    return predicate(candidate) and policyAllowsItem(policy,candidate,itemAvailable)
                end,0)
                if item~=nil then return {item=item,container=source,square=store.square,policy=policy.key} end
            end
        end
    end
end

-- The vanilla evolved-recipe action owns ingredient consumption and the new
-- food instance. Only a small set of actual cooked meals belongs in this
-- kitchen path; raw ingredients alone are never counted as a finished meal.
local PREPARED_MEALS = { ["Stir fry"] = true, Soup = true, Stew = true }
local RECIPE_BASE_ITEMS = {
    ["Base.Pan"] = true, ["Base.PanFriedVegetables"] = true,
    ["Base.Pot"] = true, ["Base.PotOfSoupRecipe"] = true,
    ["Base.PotOfStew"] = true,
}
local function recipeFood(item)
    return call(item,"IsFood",false) and not call(item,"isRotten",true)
        and not call(item,"isPoison",true) and call(item,"getPoisonPower",1)<=0
        and not call(item,"isFavorite",false)
        and call(item,"getHungerChange",0)<-0.01
end

local function preparedCount(item)
    local extras=call(item,"getExtraItems",nil)
    return extras~=nil and extras:size() or 0
end

local function recipeContainers(base,character,itemAvailable)
    if ArrayList==nil or RecipeManager==nil then return nil,nil,nil end
    local root=character:getInventory()
    local containers=ArrayList.new()
    local entries,byItem={},{}
    local seen={}
    local function add(container,square,policy)
        if container==nil or seen[container] then return end
        seen[container]=true
        containers:add(container)
        local items=container:getItems()
        for i=0,items:size()-1 do
            local item=items:get(i)
            if item~=nil and owners[item]==nil
                and (itemAvailable==nil or itemAvailable(item)==true)
                and (policy==nil or policyAllowsItem(policy,item,itemAvailable)) then
                local entry={item=item,container=container,square=square,
                    policy=policy~=nil and policy.key or nil}
                entries[#entries+1]=entry
                byItem[item]=entry
            end
        end
    end
    add(root,nil,nil)
    local origin=character:getCurrentSquare()
    if origin==nil then return nil,nil,nil end
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        if math.abs((tonumber(policy.z) or 0)-origin:getZ())<=2
            and ((tonumber(policy.x) or math.huge)-origin:getX())^2
                + ((tonumber(policy.y) or math.huge)-origin:getY())^2<=32*32 then
            local store=KnoxBaseStorage.resolvePolicy(policy)
            if store~=nil then add(store.container,store.square,policy) end
        end
    end
    return containers,entries,byItem
end

local function recipeSource(base,character,itemAvailable)
    local containers,entries,byItem=recipeContainers(base,character,itemAvailable)
    if containers==nil then return nil end
    for _,baseEntry in ipairs(entries) do
        local baseItem=baseEntry.item
        if RECIPE_BASE_ITEMS[call(baseItem,"getFullType","")]
            and baseItem~=call(character,"getPrimaryHandItem",nil)
            and baseItem~=call(character,"getSecondaryHandItem",nil)
            and not call(baseItem,"isFavorite",false)
            and not call(baseItem,"isRotten",false)
            and not call(baseItem,"isPoison",false) then
            local ok,recipes=pcall(RecipeManager.getEvolvedRecipe,
                baseItem,character,containers,true)
            if ok and recipes~=nil then
                for r=0,recipes:size()-1 do
                    local recipe=recipes:get(r)
                    if PREPARED_MEALS[call(recipe,"getUntranslatedName","")]
                        and call(recipe,"isCookable",false) then
                        local existing=preparedCount(baseItem)
                        local needed=math.max(0,2-existing)
                        if needed>0 and needed<=2 then
                            local compatible=call(recipe,"getItemsCanBeUse",nil,
                                character,baseItem,containers)
                            local selected,types={},{}
                            local previous=call(baseItem,"getExtraItems",nil)
                            if previous~=nil then
                                for i=0,previous:size()-1 do
                                    local ingredient=previous:get(i)
                                    local kind=type(ingredient)=="string" and ingredient
                                        or call(ingredient,"getFullType","")
                                    types[kind]=true
                                end
                            end
                            if compatible~=nil then
                                for i=0,compatible:size()-1 do
                                    local item=compatible:get(i)
                                    local entry=byItem[item]
                                    local itemType=call(item,"getFullType","")
                                    if entry~=nil and item~=baseItem and recipeFood(item)
                                        and not types[itemType] then
                                        selected[#selected+1]=entry
                                        types[itemType]=true
                                        if #selected==needed then break end
                                    end
                                end
                            end
                            if #selected==needed then
                                local sources={baseEntry}
                                for _,entry in ipairs(selected) do sources[#sources+1]=entry end
                                return {recipe=recipe,sources=sources,
                                    initialIngredients=existing}
                            end
                        end
                    end
                end
            end
        end
    end
end

function Cooking.findRecipeMeal(base,character,itemAvailable)
    return recipeSource(base,character,itemAvailable)
end

local function canHeat(plan)
    if plan.kind~="recipe" then return Cooking.canCook(plan.item) end
    local item=plan.item
    return recipeFood(item) and preparedCount(item)>=2
        and call(item,"isCookable",false) and not call(item,"isCooked",false)
        and not call(item,"isBurnt",false)
        and call(item,"getMinutesToCook",0)>0
        and call(item,"getMinutesToBurn",0)-call(item,"getMinutesToCook",0)>=6
        and call(item,"getCookingTime",0)<call(item,"getMinutesToBurn",0)-4
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

function Cooking.findTask(base,character,itemAvailable)
    if not enabled() or base==nil or character==nil or getCell==nil or getCell()==nil then return nil,"cooking_unavailable" end
    local origin=character:getCurrentSquare()
    if origin==nil then return nil,"cooking_unavailable" end
    local now=getTimestampMs~=nil and tonumber(getTimestampMs()) or nil
    if now~=nil and nextScan[base]~=nil and now<nextScan[base] then return nil,"kitchen_scan_cooldown" end
    local recipe=recipeSource(base,character,itemAvailable)
    local source=recipe==nil and foodSource(base,character,itemAvailable) or nil
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
                        if (recovered~=nil and (itemAvailable==nil or itemAvailable(recovered)==true)
                            and (Cooking.canCook(recovered) or KnoxSurvivorNeeds.isSafeFood(recovered)
                                or canHeat({kind="recipe",item=recovered})))
                            or ((recipe~=nil or source~=nil) and empty
                                and not object:Activated() and mark==nil) then
                            return {id="cook:"..tostring(base.id),action="cook",x=x,y=y,z=square:getZ(),
                                objectIndex=object:getObjectIndex(),spriteName=call(call(object,"getSprite",nil),"getName",""),
                                zoneId=region.id,mode=recipe~=nil and "recipe" or "direct"},"found"
                        end
                    end
                end
            end
        end end
    end
    if now~=nil then nextScan[base]=now+10000 end
    return nil, source==nil and recipe==nil and "no_suitable_meal_ingredients"
        or "no_available_powered_appliance"
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

function Cooking.begin(base,target,character,id,itemAvailable)
    local object=resolve(base,target)
    if object==nil or owners[object]~=nil then return nil,"cooking_appliance_unavailable" end
    local recovered=markedItem(object,base)
    if recovered~=nil and itemAvailable~=nil and itemAvailable(recovered)~=true then
        return nil,"cooking_ingredient_reserved"
    end
    local recipe=nil
    if recovered==nil and target.mode=="recipe" then
        recipe=recipeSource(base,character,itemAvailable)
    end
    local source=recovered~=nil and {item=recovered,container=object:getContainer()}
        or (recipe~=nil and recipe.sources[1]) or foodSource(base,character,itemAvailable)
    if source==nil or owners[source.item]~=nil then return nil,"cooking_ingredient_unavailable" end
    if recovered==nil and (object:Activated() or not object:getContainer():getItems():isEmpty()
        or object:getModData().KnoxCooking~=nil) then return nil,"cooking_appliance_in_use" end
    local kind=recipe~=nil and "recipe" or "direct"
    if recovered~=nil and not Cooking.canCook(recovered) then kind="recipe" end
    -- Older saves may contain a marked safe raw ingredient from the previous
    -- direct-heating policy. It cannot become a meal in the stove by itself;
    -- return that exact item to the resident so the appliance can be reused.
    local recoverRaw=recovered~=nil and KnoxSurvivorNeeds.isSafeFood(recovered)
        and not call(recovered,"isCooked",false)
        and not Cooking.canCook(recovered)
        and not canHeat({kind="recipe",item=recovered})
    local plan={object=object,item=source.item,source=source,baseId=base.id,target=target,id=id,
        phase=recovered~=nil and (recoverRaw and "recover_raw" or "heat")
            or (recipe~=nil and "collect_recipe" or "collect"),
        recovered=recovered~=nil,kind=kind,recipe=recipe~=nil and recipe.recipe or nil,
        recipeSources=recipe~=nil and recipe.sources or nil,
        ingredientIndex=1,sourceIndex=1,claimedItems={source.item}}
    if recipe~=nil then
        for index=2,#recipe.sources do
            local ingredient=recipe.sources[index].item
            if owners[ingredient]~=nil then return nil,"cooking_ingredient_reserved" end
            plan.claimedItems[#plan.claimedItems+1]=ingredient
        end
    end
    owners[object]=plan
    for _,item in ipairs(plan.claimedItems) do owners[item]=plan end
    return plan,"ready"
end

local HeatAction=ISToggleStoveAction:derive("KnoxMicrowaveHeatAction")
function HeatAction:isValid()
    local p=self.plan
    return enabled() and owners[self.object]==p and usable(self.object) and near(self.character,self.object:getSquare())
        and not self.object:Activated() and self.object:getContainer():getItems():size()==1
        and self.object:getContainer():contains(p.item) and canHeat(p)
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
    for _,item in ipairs(plan.claimedItems or {plan.item}) do
        if owners[item]==plan then owners[item]=nil end
    end
end

local function move(plan,square,character,bridge,ticks,phase)
    local approach=AdjacentFreeTileFinder.Find(square,character)
    if approach==nil then return "failed","kitchen_unreachable" end
    local started=plan.moveStarted
    local result=tostring(bridge:moveNpc(plan.id,approach))
    if result:find("MOVE_STARTED",1,true)~=1 then
        -- A route the movement owner refuses is retried by the phase that
        -- asked for it, inside the leg's existing deadline, instead of
        -- cancelling the whole cook order on the first obstacle.
        plan.moveStarted=started or ticks
        if ticks-plan.moveStarted>1800 then return "failed","kitchen_route:"..result end
        return "working"
    end
    plan.phase,plan.afterMove,plan.moveStarted="move",phase,ticks
    return "working"
end

local function transfer(plan,character,source,destination,nextPhase,item)
    item=item or plan.item
    local action,reason=KnoxInventoryActions.queueTransfer(character,item,source,destination,nil)
    if action==nil then return "failed",reason end
    plan.action,plan.phase,plan.destination,plan.afterTransfer=action,"transfer",destination,nextPhase
    plan.transferItem=item
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
        elseif ticks-(plan.moveStarted or ticks)>1800 then return "failed","kitchen_route:"..result
        elseif result:find("Failed",1,true) then
            -- The movement owner has already cooled the failed edge down and
            -- recorded it. Hand the leg back to its phase so the same approach
            -- is re-issued; only the deadline above ends a trip that cannot
            -- reach the store.
            plan.phase=plan.afterMove
        end
        return "working"
    end
    local queue=ISTimedActionQueue.getTimedActionQueue(character)
    if not character:getCharacterActions():isEmpty()
        or (type(queue.queue)=="table" and #queue.queue>0)
        or (plan.action~=nil and queue:indexOf(plan.action)~=-1) then return "working" end
    if plan.phase=="transfer" then
        if not plan.destination:contains(plan.transferItem or plan.item) then
            return "failed","cooking_transfer_not_completed"
        end
        if plan.afterTransfer=="collect_recipe" then
            plan.sourceIndex=(plan.sourceIndex or 1)+1
        end
        plan.phase,plan.action=plan.afterTransfer,nil
        plan.transferItem=nil
    end
    if plan.phase=="recover_raw" then
        if not near(character,object:getSquare()) then
            return move(plan,object:getSquare(),character,bridge,ticks,"recover_raw")
        end
        if markedItem(object,base)~=plan.item then return "failed","cooking_contents_changed" end
        stopHeat(plan,character)
        return transfer(plan,character,container,inventory,"return_raw")
    end
    if plan.phase=="return_raw" then
        if not inventory:contains(plan.item) then return "failed","raw_ingredient_transfer_failed" end
        return "done","raw_ingredient_recovered_to_inventory"
    end
    if plan.phase=="collect_recipe" then
        local entry=plan.recipeSources~=nil and plan.recipeSources[plan.sourceIndex or 1] or nil
        if entry==nil then
            plan.phase="assemble_recipe"
        else
            local item=entry.item
            if entry.container==inventory then
                if not inventory:contains(item) then return "failed","recipe_item_missing" end
                plan.sourceIndex=plan.sourceIndex+1
                return "working"
            end
            local valid=false
            if entry.policy~=nil then
                for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
                    if policy.key==entry.policy then
                        local store=KnoxBaseStorage.resolvePolicy(policy)
                        valid=store~=nil and store.container==entry.container
                            and policyAllowsItem(policy,item,nil)
                        break
                    end
                end
            end
            if not valid or not entry.container:contains(item) then
                return "failed","recipe_source_changed"
            end
            if entry.square~=nil and not near(character,entry.square) then
                return move(plan,entry.square,character,bridge,ticks,"collect_recipe")
            end
            return transfer(plan,character,entry.container,inventory,"collect_recipe",item)
        end
    end
    if plan.phase=="assemble_recipe" then
        local entry=plan.recipeSources[plan.ingredientIndex+1]
        if entry==nil then
            if preparedCount(plan.item)<2 then return "failed","recipe_not_a_meal" end
            plan.phase="load"
        else
            local used=entry.item
            if not inventory:contains(plan.item) or not inventory:contains(used) then
                return "failed","recipe_item_missing"
            end
            local compatible=call(plan.recipe,"getItemsCanBeUse",nil,
                character,plan.item,nil)
            if compatible==nil or not compatible:contains(used) then
                return "failed","recipe_ingredient_no_longer_usable"
            end
            local action=ISAddItemInRecipe:new(character,plan.recipe,plan.item,used)
            if action==nil then return "failed","recipe_action_unavailable" end
            -- Queue admission may complete synchronously; capture the old
            -- ingredient count before the game's action can mutate the pan.
            plan.recipeBeforeCount=preparedCount(plan.item)
            local admitted=ISTimedActionQueue.add(action)
            if admitted==nil or ISTimedActionQueue.queues==nil
                or admitted~=ISTimedActionQueue.queues[character] then
                return "failed","recipe_action_not_queued"
            end
            plan.action,plan.phase=action,"recipe_action"
            return "working"
        end
    end
    if plan.phase=="recipe_action" then
        local result=plan.action~=nil and plan.action.baseItem or nil
        if result==nil or not inventory:contains(result)
            or preparedCount(result)<=plan.recipeBeforeCount
            or not call(plan.recipe,"isResultItem",false,result) then
            return "failed","recipe_action_no_result"
        end
        plan.item=result
        owners[result]=plan
        plan.claimedItems[#plan.claimedItems+1]=result
        plan.ingredientIndex=plan.ingredientIndex+1
        plan.action=nil
        plan.phase="assemble_recipe"
        return "working"
    end
    if plan.phase=="collect" then
        local actualSource
        if plan.source.policy~=nil then
            for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
                if policy.key==plan.source.policy then
                    local store=KnoxBaseStorage.resolvePolicy(policy)
                    if store~=nil then
                        local _,source=foodIn(store.container,function(item)
                            return item==plan.item and policyAllowsItem(policy,item,nil)
                        end,0)
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
        if not canHeat(plan) then return "failed","cooking_ingredient_changed" end
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
        if not canHeat(plan) then return "failed","cooking_food_no_longer_suitable" end
        character:faceThisObject(object)
        if not object:Activated() then
            local now=getGameTime():getWorldAgeHours()
            plan.heatStarted=plan.heatStarted or now
            if now-plan.heatStarted>2 then return "failed","cooking_heat_timeout" end
            local action=HeatAction:new(character,object)
            action.plan=plan
            -- begin may complete synchronously. Admission is the registered
            -- native queue return, not continued action membership.
            local admittedQueue=ISTimedActionQueue.add(action)
            if admittedQueue==nil or ISTimedActionQueue.queues==nil
                or admittedQueue~=ISTimedActionQueue.queues[character] then
                return "failed","cooking_heat_action_not_queued"
            end
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
