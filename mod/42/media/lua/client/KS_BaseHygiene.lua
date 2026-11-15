require "TimedActions/ISWashYourself"
require "TimedActions/ISCleanBlood"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISWashClothing"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

local Hygiene = rawget(_G, "KnoxBaseHygiene") or {}
_G.KnoxBaseHygiene = Hygiene

local function call(value, method, fallback, ...)
    if value == nil or value[method] == nil then return fallback end
    local ok, result = pcall(value[method], value, ...)
    return ok and result ~= nil and result or fallback
end

local function inside(area, square)
    if area == nil or square == nil then return false end
    local minX, minY = tonumber(area.minX) or 0, tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or minX + (tonumber(area.width) or 1) - 1
    local maxY = tonumber(area.maxY) or minY + (tonumber(area.height) or 1) - 1
    return square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
end

local function readDirtyParts(character)
    -- Mirror vanilla ISWashYourself exactly: static enum access uses dot
    -- calls with no self argument. The generic call() helper above passes
    -- self explicitly, which is correct for instance methods but turns
    -- BloodBodyPartType.FromIndex(index) into a two-argument Java
    -- reflection call; that type error escapes Kahlua pcall and spammed a
    -- stack dump on every hygiene check while silently disabling washing.
    if character == nil or character.getHumanVisual == nil
        or BloodBodyPartType == nil or BloodBodyPartType.MAX == nil then return nil end
    local okVisual, visual = pcall(function() return character:getHumanVisual() end)
    if not okVisual or visual == nil then return nil end
    local okMax, maximum = pcall(function() return BloodBodyPartType.MAX:index() end)
    maximum = (okMax and tonumber(maximum)) or 0
    if maximum <= 0 or maximum~=maximum or maximum==math.huge then return nil end
    local dirty = 0
    for index = 0, maximum - 1 do
        local okPart, part = pcall(function() return BloodBodyPartType.FromIndex(index) end)
        if okPart and part ~= nil then
            local okRead, blood, dirt = pcall(function()
                return visual:getBlood(part), visual:getDirt(part)
            end)
            blood,dirt=tonumber(blood),tonumber(dirt)
            if not okRead or blood==nil or dirt==nil or blood~=blood or dirt~=dirt
                or blood<0 or dirt<0 or blood==math.huge or dirt==math.huge then return nil end
            if blood + dirt > 0 then
                dirty = dirty + 1
            end
        else return nil end
    end
    return dirty, maximum
end

function Hygiene.dirtyParts(character)
    -- Compatibility for admission callers: unknown state cannot request work.
    -- The action receipt uses the readable snapshot directly, never this zero.
    return readDirtyParts(character) or 0
end

-- Hygiene is an ambient base activity. A few stains after work are normal;
-- residents seek a real water source only once they are visibly filthy.
function Hygiene.isNeeded(character)
    return Hygiene.dirtyParts(character) >= 4
end

function Hygiene.find(character, base)
    local origin = character ~= nil and call(character, "getCurrentSquare", nil) or nil
    local area = base ~= nil and (base.territory or base.home) or nil
    local cell = getCell ~= nil and getCell() or nil
    if origin == nil or area == nil or cell == nil or not inside(area, origin) then return nil end
    local minX, minY = tonumber(area.minX) or 0, tonumber(area.minY) or 0
    local maxX = math.min(tonumber(area.maxX) or minX + (tonumber(area.width) or 1) - 1, minX + 96)
    local maxY = math.min(tonumber(area.maxY) or minY + (tonumber(area.height) or 1) - 1, minY + 96)
    local startZ = tonumber(area.z) or origin:getZ()
    local best, bestDistance = nil, math.huge
    for z = startZ, startZ + 3 do
        for x = minX, maxX do for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and call(square, "getObjects", nil) or nil
            if objects ~= nil then for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                local water = tonumber(call(object, "getFluidAmount", 0)) or 0
                if water >= 1 then
                    local approach = AdjacentFreeTileFinder.Find(square, character)
                    if approach ~= nil then
                        local dx, dy = approach:getX() - origin:getX(), approach:getY() - origin:getY()
                        local distance = dx * dx + dy * dy
                        if distance < bestDistance then
                            best, bestDistance = { object = object, approach = approach }, distance
                        end
                    end
                end
            end end
        end end
    end
    return best
end

function Hygiene.begin(character, base, bridge, id, ticks)
    if not Hygiene.isNeeded(character) then return nil, "not_dirty" end
    local plan = Hygiene.find(character, base)
    if plan == nil then return nil, "no_base_water_source" end
    local result = tostring(bridge:moveNpc(id, plan.approach))
    if not string.find(result, "MOVE_STARTED", 1, true) then return nil, "wash_route:" .. result end
    plan.phase, plan.startedAt, plan.dirtyBefore = "move", ticks, Hygiene.dirtyParts(character)
    return plan, "working"
end

-- Field washing for followers on the move. Same dirt threshold and vanilla
-- ISWashYourself machinery as the base version, but the water search is a
-- radius scan around the survivor instead of base territory: a sink, tub
-- or rain barrel in a building the party is already passing is fair game.
-- No soap logic, no new actions; when nothing wet is near, the caller
-- picks other idle instead of roaming for water.
function Hygiene.findNearby(character, radius)
    local origin = character ~= nil and call(character, "getCurrentSquare", nil) or nil
    local cell = getCell ~= nil and getCell() or nil
    if origin == nil or cell == nil then return nil end
    radius = math.max(4, math.min(24, tonumber(radius) or 16))
    local ox, oy, oz = origin:getX(), origin:getY(), origin:getZ()
    local best, bestDistance = nil, math.huge
    for x = ox - radius, ox + radius do for y = oy - radius, oy + radius do
        local square = cell:getGridSquare(x, y, oz)
        local objects = square ~= nil and call(square, "getObjects", nil) or nil
        if objects ~= nil then for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local water = tonumber(call(object, "getFluidAmount", 0)) or 0
            if water >= 1 then
                local approach = AdjacentFreeTileFinder.Find(square, character)
                if approach ~= nil then
                    local dx, dy = approach:getX() - ox, approach:getY() - oy
                    local distance = dx * dx + dy * dy
                    if distance < bestDistance then
                        best, bestDistance = { object = object, approach = approach }, distance
                    end
                end
            end
        end end
    end end
    return best
end

function Hygiene.beginNear(character, radius, bridge, id, ticks)
    if not Hygiene.isNeeded(character) then return nil, "not_dirty" end
    if bridge == nil then return nil, "no_bridge" end
    local plan = Hygiene.findNearby(character, radius)
    if plan == nil then return nil, "no_nearby_water" end
    local result = tostring(bridge:moveNpc(id, plan.approach))
    if not string.find(result, "MOVE_STARTED", 1, true) then return nil, "wash_route:" .. result end
    plan.phase, plan.startedAt, plan.dirtyBefore = "move", ticks, Hygiene.dirtyParts(character)
    return plan, "working"
end

function Hygiene.cancel(character, plan, bridge, id)
    if plan ~= nil and plan.phase == "move" and bridge ~= nil then pcall(bridge.cancelNpcMove, bridge, id) end
    if plan ~= nil and plan.action ~= nil then
        local queue = ISTimedActionQueue.getTimedActionQueue(character)
        if queue ~= nil and queue:indexOf(plan.action) ~= -1 then
            if queue.current == plan.action then ISTimedActionQueue.clear(character)
            else plan.action:forceCancel(); queue:removeFromQueue(plan.action) end
        end
    end
end

function Hygiene.step(plan, character, bridge, id, ticks)
    if plan == nil or character == nil then return "failed", "wash_plan_missing" end
    if plan.phase == "move" then
        local result = tostring(bridge:tickNpc(id))
        if result == "Succeeded" then plan.phase = "prepare"
        elseif string.find(result, "Failed", 1, true) or ticks - plan.startedAt > 1800 then
            return "failed", "wash_route:" .. result
        else return "working" end
    end
    if plan.phase == "prepare" then
        if character:getCharacterActions():isEmpty() == false then return "failed", "wash_action_busy" end
        if (tonumber(call(plan.object, "getFluidAmount", 0)) or 0) < 1 then return "failed", "wash_water_empty" end
        local before=readDirtyParts(character)
        if before==nil then return "failed", "wash_dirty_unavailable" end
        if before==0 then return "failed", "wash_no_longer_needed" end
        local action = ISWashYourself:new(character, plan.object)
        local queue = ISTimedActionQueue.add(action)
        if queue == nil or ISTimedActionQueue.queues==nil
            or queue~=ISTimedActionQueue.queues[character] then return "failed", "wash_not_queued" end
        plan.phase, plan.action, plan.actionStarted, plan.dirtyBefore = "washing", action, ticks, before
        return "working"
    end
    if plan.phase == "washing" then
        if character:getCharacterActions():isEmpty() == false then return "working" end
        local queue=ISTimedActionQueue.getTimedActionQueue(character)
        if queue==nil then return "failed", "wash_queue_unavailable" end
        if plan.action~=nil and queue:indexOf(plan.action)~=-1 then return "working" end
        local before=tonumber(plan.dirtyBefore)
        local after,maximum=readDirtyParts(character)
        if before==nil or before~=before or before<=0 or after==nil
            or before>maximum or before~=math.floor(before) then
            return "failed", "wash_dirty_unavailable"
        end
        if after < before then return "complete", "washed" end
        if ticks - plan.actionStarted > 7200 then return "failed", "wash_timeout" end
        return "failed", "wash_no_change"
    end
    return "failed", "wash_invalid_phase"
end

-- Surface chores share this activity owner; they never change body-wash plans.
do
    local function stain(square)
        return square:haveBloodFloor() or square:haveBloodWall()
            or square:haveGrimeFloor() or square:haveGrimeWall()
    end
    local function eligible(square)
        if square == nil then return false end
        local room = square:getRoomDef()
        return (room == nil or room:getName() ~= "bathroom") and stain(square)
    end
    local function cost() return ZomboidGlobals.CleanBloodBleachAmount end
    local function cleaner(item)
        local f = item:getFluidContainer()
        return f ~= nil and (f:contains(Fluid.Bleach) or f:contains(Fluid.CleaningLiquid))
            and f:getAmount() >= cost()
    end
    local function carried(character, item)
        return character:getInventory():containsEvalRecurse(function(candidate) return candidate == item end)
    end
    local function supplies(character, available)
        local inv = character:getInventory()
        local liquid = inv:getFirstEvalRecurse(function(item)
            return (available == nil or available(item)) and cleaner(item)
        end)
        local tool = inv:getFirstTagEvalRecurse(ItemTag.CLEAN_STAINS, function(item)
            return not item:isBroken() and (available == nil or available(item))
        end)
        return tool, liquid
    end
    -- At most 64 loaded-square lookups; advance on empty/unloaded squares too.
    function Hygiene.findSurface(character, base, cursor, available)
        local area = base and (base.territory or base.home)
        local origin = character and character:getCurrentSquare()
        if not area or not origin or not inside(area, origin) then return nil, cursor end
        local supplyOk,tool,liquid = pcall(supplies,character,available)
        if not supplyOk or not tool or not liquid then return nil, cursor end
        local minX, minY = tonumber(area.minX), tonumber(area.minY)
        if not minX or not minY then return nil, cursor end
        local maxX = tonumber(area.maxX) or minX + (tonumber(area.width) or 1) - 1
        local maxY = tonumber(area.maxY) or minY + (tonumber(area.height) or 1) - 1
        local width, height = maxX-minX+1, maxY-minY+1
        if width<=0 or height<=0 then return nil, cursor end
        local total, cell = width*height, getCell()
        if not cell then return nil, cursor end
        local index = (tonumber(cursor) or 0)%total
        for _=1, math.min(total,64) do
            local loaded,square = pcall(cell.getGridSquare,cell,minX+index%width,minY+math.floor(index/width),origin:getZ())
            index=(index+1)%total
            local ok, dirty = pcall(eligible,loaded and square or nil)
            if ok and dirty then
                local approach = AdjacentFreeTileFinder.Find(square,character)
                if approach then
                    return {kind="surface",square=square,approach=approach,tool=tool,
                        cleaner=liquid,base=base,character=character,phase="surface_move"},index
                end
            end
        end
        return nil,index
    end
    local function allowed(plan, character)
        if plan.cancelled or plan.character~=character or character:isDead()
            or not carried(character,plan.tool) or not carried(character,plan.cleaner)
            or plan.tool:isBroken() or not plan.tool:hasTag(ItemTag.CLEAN_STAINS)
            or not cleaner(plan.cleaner) then return false end
        local area=plan.base.territory or plan.base.home
        local cell,here=getCell(),character:getCurrentSquare()
        if not cell or cell:getGridSquare(plan.square:getX(),plan.square:getY(),plan.square:getZ())~=plan.square then return false end
        if plan.phase~="surface_move" then
            if not here or here:getZ()~=plan.square:getZ()
                or (here:getX()-plan.square:getX())^2+(here:getY()-plan.square:getY())^2>2
                or (here~=plan.square and (here.isSomethingTo==nil or here:isSomethingTo(plan.square))) then return false end
        end
        return inside(area,character:getCurrentSquare()) and inside(area,plan.square)
            and eligible(plan.square) and (plan.permission==nil or plan.permission())
    end
    local function guarded(plan, character, action, completing)
        for _, name in ipairs({"isValid","start","perform","complete"}) do
            local original=action[name]
            if original then
                action[name]=function(self,...)
                    local ok,permitted=pcall(allowed,plan,character)
                    if name=="perform" then
                        if completing then return original(self,...) end
                        if not ok or not permitted then return ISBaseTimedAction.perform(self) end
                    end
                    if not ok or not permitted then return false end
                    if name=="complete" and completing then
                        if plan.cleanAttempted then return false end
                        plan.cleanAttempted=true
                    end
                    local result=original(self,...)
                    if name=="complete" and completing and result==true then plan.nativeCompleted=true end
                    return result
                end
            end
        end
        return action
    end
    local function enqueue(plan,character,action,receipt,completing)
        plan.action=guarded(plan,character,action,completing)
        plan.receipt=receipt
        local queue=ISTimedActionQueue.add(action)
        if plan.cancelled or queue==nil or ISTimedActionQueue.queues[character]~=queue then
            return "failed","surface_queue_refused"
        end
        plan.phase="surface_wait"
        return "working"
    end
    function Hygiene.stepSurface(plan,character,bridge,id,ticks)
        if plan.phase=="surface_done" then return "complete","surface_cleaned" end
        if ticks-(plan.startedAt or ticks)>7200 then return "failed","surface_timeout" end
        if plan.phase=="surface_wait" then
            local q=ISTimedActionQueue.getTimedActionQueue(character)
            if q and q:indexOf(plan.action)~=-1 then return "working" end
            local ok,received=pcall(plan.receipt)
            if not ok or not received then return "failed","surface_receipt_missing" end
            plan.action,plan.receipt=nil,nil
            if plan.nativeCompleted then plan.phase="surface_done";return "complete","surface_cleaned" end
            plan.phase="surface_prepare"
        end
        if not allowed(plan,character) then return "failed","surface_permission_changed" end
        if plan.phase=="surface_move" then
            local result=tostring(bridge:tickNpc(id))
            if result=="Succeeded" then plan.phase="surface_prepare"
            elseif result:find("Failed",1,true) then return "failed","surface_route_failed"
            else return "working" end
        end
        if plan.phase~="surface_prepare" then return "failed","surface_invalid_phase" end
        local q=ISTimedActionQueue.getTimedActionQueue(character)
        if not character:getCharacterActions():isEmpty() or q.current~=nil or #q.queue>0 then
            return "failed","surface_foreign_action"
        end
        local inv=character:getInventory()
        for _,item in ipairs({plan.tool,plan.cleaner}) do
            if item:getContainer()~=inv then
                local source=item:getContainer()
                local function guard(_,candidate)
                    return candidate==item and allowed(plan,character) and item:getContainer()==source
                end
                plan.guard=guard
                local action,reason=KnoxInventoryActions.queueTransfer(character,item,source,inv,nil,guard)
                if not action then return "failed",reason end
                plan.action=action
                plan.receipt=function() return item:getContainer()==inv and inv:contains(item) and not source:contains(item) end
                plan.phase="surface_wait"
                return "working"
            end
        end
        local both=instanceof(plan.tool,"HandWeapon") and plan.tool:isTwoHandWeapon()
        if character:getPrimaryHandItem()~=plan.tool or both and character:getSecondaryHandItem()~=plan.tool then
            return enqueue(plan,character,ISEquipWeaponAction:new(character,plan.tool,50,true,both),function()
                return character:getPrimaryHandItem()==plan.tool and (not both or character:getSecondaryHandItem()==plan.tool)
            end)
        end
        if not both and character:getSecondaryHandItem()~=plan.cleaner then
            return enqueue(plan,character,ISEquipWeaponAction:new(character,plan.cleaner,50,false,false),function()
                return character:getSecondaryHandItem()==plan.cleaner
            end)
        end
        local before=plan.cleaner:getFluidContainer():getAmount()
        local action=ISCleanBlood:new(character,plan.square,plan.cleaner)
        return enqueue(plan,character,action,function()
            local delta=before-plan.cleaner:getFluidContainer():getAmount()
            return plan.nativeCompleted==true and not stain(plan.square) and math.abs(delta-cost())<0.0001
        end,true)
    end
end

return Hygiene
