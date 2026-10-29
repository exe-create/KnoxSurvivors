require "TimedActions/ISGrabCorpseAction"
require "TimedActions/ISDropCorpseAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISTimedActionQueue"

local CorpseHandling = rawget(_G, "KnoxBaseCorpseHandling") or {}
_G.KnoxBaseCorpseHandling = CorpseHandling

local MAX_SOURCE_SCAN_RADIUS = 36
local GRAB_SETTLE_TICKS = 180
local GRAB_RETRY_SETTLE_TICKS = 180

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1) or 0
    local minY = tonumber(zone.y1) or 0
    local maxX = tonumber(zone.x2) or minX
    local maxY = tonumber(zone.y2) or minY
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function orderedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "corpse" then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.id) < tostring(second.id)
    end)
    return zones
end

local function sourceBounds(base, zone)
    local territory = base ~= nil and (base.territory or base.home) or nil
    if territory == nil then
        return zoneBounds(zone)
    end
    local minX = tonumber(territory.minX) or 0
    local minY = tonumber(territory.minY) or 0
    local maxX = tonumber(territory.maxX)
        or minX + (tonumber(territory.width) or 1) - 1
    local maxY = tonumber(territory.maxY)
        or minY + (tonumber(territory.height) or 1) - 1
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function insideZone(zone, square)
    if zone == nil or square == nil then
        return false
    end
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    return square:getZ() == z
        and square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
end

local function insideAnyZone(zones, square)
    for _, zone in ipairs(zones) do
        if insideZone(zone, square) then return true end
    end
    return false
end

local function isDeadBody(object)
    if object == nil or instanceof == nil then
        return false
    end
    local success, result = pcall(function()
        return instanceof(object, "IsoDeadBody")
    end)
    return success and result == true
end

local function isAnimalBody(object)
    if object == nil or object.isAnimal == nil then
        return false
    end
    local success, result = pcall(object.isAnimal, object)
    return success and result == true
end

local function haulable(object)
    if not isDeadBody(object) or isAnimalBody(object) then
        return false
    end
    local index = safeCall(object, "getStaticMovingObjectIndex")
    return index == nil or tonumber(index) == nil or tonumber(index) >= 0
end

local function distanceSquared(first, second)
    if first == nil or second == nil then
        return math.huge
    end
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function canStand(square)
    if square == nil then
        return false
    end
    if square.canStand == nil then
        return true
    end
    local success, result = pcall(square.canStand, square)
    return success and result == true
end

local function candidateDropSquare(cell, zone, character, corpseSquare)
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    local centerX = math.floor((minX + maxX) / 2)
    local centerY = math.floor((minY + maxY) / 2)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local candidates = {
        { centerX, centerY },
        { minX, minY },
        { maxX, minY },
        { minX, maxY },
        { maxX, maxY },
    }
    local best, bestScore = nil, math.huge
    for _, point in ipairs(candidates) do
        for radius = 0, 4 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = cell:getGridSquare(
                            point[1] + dx, point[2] + dy, z
                        )
                        if insideZone(zone, square) and canStand(square)
                            and square ~= corpseSquare then
                            local centerDistance = (square:getX() - centerX) ^ 2
                                + (square:getY() - centerY) ^ 2
                            local originDistance = distanceSquared(square, origin)
                            local score = centerDistance + originDistance * 0.05
                            if score < bestScore then
                                best = square
                                bestScore = score
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function approachSquare(corpseSquare, character)
    if corpseSquare == nil then
        return nil
    end
    if AdjacentFreeTileFinder ~= nil and character ~= nil then
        local success, result = pcall(function()
            return AdjacentFreeTileFinder.Find(corpseSquare, character)
        end)
        if success and result ~= nil then
            return result
        end
    end
    return canStand(corpseSquare) and corpseSquare or nil
end

local function targetId(base, zone, body, square)
    local corpseItem = safeCall(body, "getItem")
    local itemId = safeCall(corpseItem, "getID")
    local identity = itemId ~= nil and ("item-" .. tostring(itemId))
        or ("index-" .. tostring(safeCall(body, "getStaticMovingObjectIndex") or 0))
    return "corpse:" .. tostring(base.id) .. ":" .. tostring(zone.id) .. ":"
        .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square:getZ()) .. ":" .. identity
end

local function descriptor(base, zone, body, square, dropSquare)
    local corpseItem = safeCall(body, "getItem")
    local corpseItemId = safeCall(corpseItem, "getID")
    return {
        id = targetId(base, zone, body, square),
        auto = true,
        action = "haul_corpse",
        zoneType = "corpse",
        zoneId = zone.id,
        corpseX = square:getX(),
        corpseY = square:getY(),
        corpseZ = square:getZ(),
        corpseIndex = safeCall(body, "getStaticMovingObjectIndex"),
        corpseItemId = corpseItemId ~= nil and tostring(corpseItemId) or nil,
        dropX = dropSquare:getX(),
        dropY = dropSquare:getY(),
        dropZ = dropSquare:getZ(),
    }
end

local function firstHaulableBody(square, eligible)
    if square == nil or square.getStaticMovingObjects == nil then
        return nil
    end
    local objects = square:getStaticMovingObjects()
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if haulable(object) and (eligible == nil or eligible(object)) then
            return object
        end
    end
    return nil
end

local function insideBounds(x, y, minX, minY, maxX, maxY)
    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

local BURN_FULL_THRESHOLD = 8

function CorpseHandling.countInZone(cell, zone)
    if cell == nil or zone == nil then return 0 end
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    local count = 0
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            if square ~= nil and square.getStaticMovingObjects ~= nil then
                local objects = square:getStaticMovingObjects()
                if objects ~= nil then
                    for index = 0, objects:size() - 1 do
                        if haulable(objects:get(index)) then count = count + 1 end
                    end
                end
            end
        end
    end
    return count
end

function CorpseHandling.findFullZones(base)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then return {} end
    local full = {}
    for _, zone in ipairs(orderedZones(base)) do
        if CorpseHandling.countInZone(cell, zone) >= BURN_FULL_THRESHOLD then
            full[#full + 1] = zone
        end
    end
    return full
end

-- Burn piled corpses in place when a drop area is full. Execution deletes
-- bodies via native removal; a lighter in inventory or storage is required.
function CorpseHandling.findBurnTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then return nil, "base_or_cell_unavailable" end
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local best, bestDistance = nil, math.huge
    for _, zone in ipairs(orderedZones(base)) do
        local count = CorpseHandling.countInZone(cell, zone)
        if count >= BURN_FULL_THRESHOLD then
            local minX, minY, maxX, maxY, z = zoneBounds(zone)
            local cx = math.floor((minX + maxX) / 2)
            local cy = math.floor((minY + maxY) / 2)
            local square = cell:getGridSquare(cx, cy, z)
            if square == nil or not canStand(square) then
                square = candidateDropSquare(cell, zone, character, nil)
            end
            if square ~= nil then
                local target = {
                    id = "burn:" .. tostring(base.id) .. ":" .. tostring(zone.id),
                    auto = true,
                    action = "burn_corpse",
                    zoneType = "corpse",
                    zoneId = zone.id,
                    x = square:getX(), y = square:getY(), z = square:getZ(),
                    corpseCount = count,
                }
                if eligible == nil or eligible(target) then
                    local d = origin ~= nil and distanceSquared(origin, square) or 0
                    if d < bestDistance then best, bestDistance = target, d end
                end
            end
        end
    end
    return best, best ~= nil and "found_burn" or "no_burn_ready"
end

function CorpseHandling.burnZoneCorpses(base, zoneId)
    local cell = getCell ~= nil and getCell() or nil
    local zone = base ~= nil and base.zones ~= nil and base.zones[zoneId] or nil
    if cell == nil or zone == nil then return 0, "zone_unavailable" end
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    local removed = 0
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            if square ~= nil and square.getStaticMovingObjects ~= nil then
                local objects = square:getStaticMovingObjects()
                if objects ~= nil then
                    local victims = {}
                    for index = 0, objects:size() - 1 do
                        local body = objects:get(index)
                        if haulable(body) then victims[#victims + 1] = body end
                    end
                    for _, body in ipairs(victims) do
                        local done = false
                        pcall(function()
                            if body.removeFromWorld ~= nil then body:removeFromWorld(); done = true end
                        end)
                        if not done then pcall(function()
                            if body.removeFromSquare ~= nil then body:removeFromSquare(square); done = true end
                        end) end
                        if not done then pcall(function()
                            if square.removeCorpse ~= nil then square:removeCorpse(body, false); done = true end
                        end) end
                        if not done then pcall(function()
                            local c = getCell(); if c ~= nil and c.removeCorpse ~= nil then c:removeCorpse(body); done = true end
                        end) end
                        if done then removed = removed + 1 end
                    end
                end
            end
        end
    end
    return removed, removed > 0 and "burned" or "nothing_burned"
end

function CorpseHandling.findTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local best, bestDistance = nil, math.huge
    local zones = orderedZones(base)
    for _, zone in ipairs(zones) do
        local minX, minY, maxX, maxY, z = sourceBounds(base, zone)
        local zoneMinX, zoneMinY, zoneMaxX, zoneMaxY = zoneBounds(zone)
        local centerX = origin ~= nil and origin:getX()
            or math.floor((zoneMinX + zoneMaxX) / 2)
        local centerY = origin ~= nil and origin:getY()
            or math.floor((zoneMinY + zoneMaxY) / 2)
        -- Sources are outside the drop zone, so all bodies can share this
        -- bounded destination search during one discovery pass.
        local zoneDropSquare = candidateDropSquare(cell, zone, character, nil)
        -- Search outward from the worker so a very large player-drawn base remains
        -- bounded per decision. Patrol and ordinary base movement naturally expose
        -- other loaded sections later instead of scanning the whole territory at once.
        for radius = 0, MAX_SOURCE_SCAN_RADIUS do
            -- Every tile on a later ring is farther than radius. Once a nearer
            -- eligible body is known, those rings cannot improve the choice.
            if origin ~= nil and best ~= nil and radius * radius > bestDistance then break end
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local x, y = centerX + dx, centerY + dy
                        local square = insideBounds(x, y, minX, minY, maxX, maxY)
                            and cell:getGridSquare(x, y, z) or nil
                        local body = zoneDropSquare ~= nil and not insideAnyZone(zones, square)
                            and firstHaulableBody(square, function(candidate)
                                return eligible == nil or eligible(descriptor(
                                    base, zone, candidate, square, zoneDropSquare))
                            end) or nil
                        if body ~= nil then
                            local approach = approachSquare(square, character)
                            local dropSquare = zoneDropSquare
                            if approach ~= nil and dropSquare ~= nil
                                and distanceSquared(square, dropSquare) > 1 then
                                local distance = distanceSquared(square, origin)
                                if distance < bestDistance then
                                    best = descriptor(
                                        base, zone, body, square, dropSquare
                                    )
                                    bestDistance = distance
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, best ~= nil and "found" or "no_corpse_ready"
end

local function bodyAtSquare(square, objectIndex, corpseItemId)
    if square == nil or square.getStaticMovingObjects == nil then
        return nil
    end
    local objects = square:getStaticMovingObjects()
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local body = objects:get(index)
        if haulable(body) then
            local item = safeCall(body, "getItem")
            local itemId = safeCall(item, "getID")
            local currentIndex = safeCall(body, "getStaticMovingObjectIndex")
            if (corpseItemId ~= nil and tostring(itemId) == tostring(corpseItemId))
                or (corpseItemId == nil and (objectIndex == nil
                    or tonumber(currentIndex) == tonumber(objectIndex))) then
                return body
            end
        end
    end
    return nil
end

function CorpseHandling.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_corpse_target"
    end
    local corpseSquare = cell:getGridSquare(
        tonumber(target.corpseX) or 0,
        tonumber(target.corpseY) or 0,
        tonumber(target.corpseZ) or 0
    )
    local body = bodyAtSquare(
        corpseSquare,
        target.corpseIndex,
        target.corpseItemId
    )
    if body == nil then
        return nil, "corpse_unloaded_or_moved"
    end
    if insideAnyZone(orderedZones(base), corpseSquare) then
        return nil, "corpse_already_in_disposal_area"
    end
    local approach = approachSquare(corpseSquare, character)
    local zone = base.zones ~= nil and base.zones[target.zoneId] or nil
    if zone == nil or zone.enabled == false or zone.type ~= "corpse" then
        return nil, "corpse_zone_unavailable"
    end
    local dropSquare = candidateDropSquare(
        cell, zone, character, corpseSquare
    )
    if approach == nil or dropSquare == nil then
        return nil, "corpse_path_unavailable"
    end
    return {
        body = body,
        corpseSquare = corpseSquare,
        approach = approach,
        dropSquare = dropSquare,
    }, "resolved"
end

local function admitAction(character, action, stage)
    -- Native begin may complete synchronously; the registered queue return
    -- proves admission, while grapple/destination receipts remain separate.
    local queue = ISTimedActionQueue.add(action)
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, stage .. "_queue_refused"
    end
    return action, "queued"
end

local function unequipHeld(character)
    local primary = safeCall(character, "getPrimaryHandItem")
    local secondary = safeCall(character, "getSecondaryHandItem")
    if primary ~= nil then
        local action, reason = admitAction(character,
            ISUnequipAction:new(character, primary, 50), "corpse_unequip_primary")
        if action == nil then return false, reason end
    end
    if secondary ~= nil and secondary ~= primary then
        local action, reason = admitAction(character,
            ISUnequipAction:new(character, secondary, 50), "corpse_unequip_secondary")
        if action == nil then return false, reason end
    end
    return true
end

function CorpseHandling.queueGrab(character, target)
    if character == nil or target == nil or target.body == nil then
        return nil, "missing_corpse"
    end
    if safeCall(character, "isDraggingCorpse") == true then
        return nil, "already_dragging_corpse"
    end
    local prepared, reason = unequipHeld(character)
    if not prepared then return nil, reason end
    local action = ISGrabCorpseAction:new(character, target.body)
    return admitAction(character, action, "corpse_grab")
end

function CorpseHandling.grabTransitionState(character)
    if CorpseHandling.isDragging(character) then
        return "dragging"
    end
    if safeCall(character, "isGrappling") == true
        or safeCall(character, "isPerformingGrappleAnimation") == true
        or safeCall(character, "isPerformingAnyGrappleAnimation") == true then
        return "transitioning"
    end
    return "idle"
end

-- Build 42's pickUpCorpse starts a grapple handshake. isDraggingCorpse becomes
-- true only after the native grapple target accepts, so checking it in the same
-- Lua call incorrectly treats a valid pickup as a failure. This helper gives the
-- native transition one bounded settle window and then terminates cleanly.
-- Replaying pickup here would restart the same grapple animation.
function CorpseHandling.nextGrabStep(character, retryIssued, verifyUntil, ticks)
    local state = CorpseHandling.grabTransitionState(character)
    if state == "dragging" then
        return "ready", state, verifyUntil
    end
    local deadline = tonumber(verifyUntil)
    if deadline == nil then
        local delay = state == "transitioning"
            and GRAB_RETRY_SETTLE_TICKS or GRAB_SETTLE_TICKS
        return "wait", state, ticks + delay
    end
    if ticks < deadline then
        return "wait", state, deadline
    end
    return "failed", state, deadline
end

function CorpseHandling.requestGrabRetry(character, target)
    return false, "native_pickup_retry_disabled"
end

function CorpseHandling.nextDropStep(character, retryIssued, verifyUntil, ticks)
    local state = CorpseHandling.grabTransitionState(character)
    if state == "idle" then
        return "ready", "released", verifyUntil
    end
    local deadline = tonumber(verifyUntil)
    if deadline == nil then
        return "wait", state, ticks + GRAB_RETRY_SETTLE_TICKS
    end
    if ticks < deadline then
        return "wait", state, deadline
    end
    if retryIssued ~= true then
        return "retry", state, ticks + GRAB_RETRY_SETTLE_TICKS
    end
    return "failed", state, deadline
end

function CorpseHandling.requestDropRetry(character)
    if character == nil then
        return false, "missing_character"
    end
    if not CorpseHandling.isDragging(character) then
        return true, "already_released"
    end
    local success = pcall(function()
        character:setDoGrappleLetGo()
    end)
    return success, success and "native_release_requested" or "native_release_failed"
end

function CorpseHandling.queueDrop(character, target)
    if character == nil or target == nil or target.dropSquare == nil then
        return nil, "missing_drop_square"
    end
    if safeCall(character, "isDraggingCorpse") ~= true then
        return nil, "not_dragging_corpse"
    end
    local action = ISDropCorpseAction:new(character, target.dropSquare)
    return admitAction(character, action, "corpse_drop")
end

function CorpseHandling.isDragging(character)
    return safeCall(character, "isDraggingCorpse") == true
end

function CorpseHandling.isAtDropSquare(character, square)
    local current = character ~= nil and safeCall(character, "getCurrentSquare") or nil
    if current == nil or square == nil or current:getZ() ~= square:getZ() then
        return false
    end
    local dx, dy = current:getX() - square:getX(), current:getY() - square:getY()
    return dx * dx + dy * dy <= 4
end

return CorpseHandling
