require "TimedActions/ISWashYourself"
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

return Hygiene
