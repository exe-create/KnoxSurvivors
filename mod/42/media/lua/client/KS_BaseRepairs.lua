require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveablesAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWearClothing"
require "Util/AdjacentFreeTileFinder"
require "ISUI/ISWorldObjectContextMenu"
require "KS_SurvivorInventoryActions"
require "KS_BaseSupplyPlanner"
require "KS_BaseEngineRepairs"

local Repairs = rawget(_G, "KnoxBaseRepairs") or {}
_G.KnoxBaseRepairs = Repairs

local MAX_SCAN_RADIUS = 36

local function safeCall(object, method, ...)
    if object == nil or object == false or object == true
        or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    if success then return value end
    return nil
end

local function instanceOf(object, className)
    if object == nil or instanceof == nil then
        return false
    end
    local success, result = pcall(function()
        return instanceof(object, className)
    end)
    return success and result == true
end

local function isStructure(object)
    return instanceOf(object, "IsoDoor")
        or instanceOf(object, "IsoThumpable")
        or instanceOf(object, "IsoBarricade")
end

local function damaged(object)
    local health = tonumber(safeCall(object, "getHealth")) or 0
    local maximum = tonumber(safeCall(object, "getMaxHealth")) or 0
    local fraction = maximum > 0 and health / maximum or 1
    return maximum > 0 and fraction >= 0.20 and fraction <= 0.95
end

local function repairProps(object, character, discovery)
    if not isStructure(object) or not damaged(object)
        or ISMoveableSpriteProps == nil
        or ISMoveableSpriteProps.fromObjectForRepair == nil then
        return nil
    end
    local success, props = pcall(
        ISMoveableSpriteProps.fromObjectForRepair,
        object
    )
    if not success or props == nil or props.canRepairObject == nil then
        return nil
    end
    local valid, result = pcall(props.canRepairObject, props, character)
    if not valid or result == nil or (result.canRepair ~= true
        and not (discovery and result.craftValid == true)) then
        return nil
    end
    return props
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1 or zone.minX) or 0
    local minY = tonumber(zone.y1 or zone.minY) or 0
    local maxX = tonumber(zone.x2 or zone.maxX)
        or minX + (tonumber(zone.width) or 1) - 1
    local maxY = tonumber(zone.y2 or zone.maxY)
        or minY + (tonumber(zone.height) or 1) - 1
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function repairRegions(base, character)
    local regions = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "repair" then
            regions[#regions + 1] = zone
        end
    end
    if #regions == 0 then
        local territory = base ~= nil and (base.territory or base.home) or nil
        if territory ~= nil then
            local current = character ~= nil and character:getCurrentSquare() or nil
            regions[1] = {
                id = "territory",
                x1 = territory.minX,
                y1 = territory.minY,
                x2 = territory.maxX
                    or (territory.minX + (territory.width or 1) - 1),
                y2 = territory.maxY
                    or (territory.minY + (territory.height or 1) - 1),
                z = current ~= nil and current:getZ() or territory.z or 0,
            }
        end
    end
    table.sort(regions, function(first, second)
        return tostring(first.id or "territory") < tostring(second.id or "territory")
    end)
    return regions
end

local function approachSquare(object, character)
    local square = safeCall(object, "getSquare")
    if square == nil then
        return nil
    end
    if AdjacentFreeTileFinder ~= nil and character ~= nil then
        local success, result = pcall(function()
            return AdjacentFreeTileFinder.Find(square, character)
        end)
        if success and result ~= nil then
            return result
        end
    end
    return nil
end

local function toolRule(fullType)
    return { usable = true, minUsesFloat = fullType == "Base.BlowTorch" and 0.1 or nil }
end

local function usableTool(item)
    if item == true then return true end
    local fullType = safeCall(item, "getFullType")
    if fullType == nil then return false end
    return KnoxBaseSupplyPlanner.matchesRequirement(item, {
        items = { [fullType] = 1 }, itemRules = { [fullType] = toolRule(fullType) },
    })
end

local function requirementsAvailable(base, character, requirements)
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage ~= nil and storage.requirementsAvailable ~= nil then
        return storage.requirementsAvailable(base, character, requirements) == true
    end
    for fullType, count in pairs(requirements.items) do
        if KnoxBaseSupplyPlanner.inventoryCount(character:getInventory(), fullType, requirements) < count then
            return false
        end
    end
    return true
end

local function repairTool(props, character, base, second)
    local carried = safeCall(props, "hasRepairTool", character, second)
    if usableTool(carried) then return carried end
    local definitions = ISMoveableDefinitions ~= nil and ISMoveableDefinitions:getInstance() or nil
    local definition = definitions ~= nil and definitions.getRepairDefinition(props.material) or nil
    local choices = definition ~= nil and (second and definition.tools2 or definition.tools) or nil
    if type(choices) ~= "table" then return nil end
    if #choices == 0 then return true end
    -- Native lookup returns the first matching type, which may be depleted or
    -- broken while another usable copy is already carried in a bag.
    local function carriedMatch(container, fullType, seen)
        if container == nil or seen[container] then return nil end
        seen[container] = true
        local items = safeCall(container, "getItems")
        if items == nil then return nil end
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if safeCall(item, "getFullType") == fullType and usableTool(item) then return item end
            if safeCall(item, "IsInventoryContainer") == true then
                local nested = carriedMatch(safeCall(item, "getInventory"), fullType, seen)
                if nested ~= nil then return nested end
            end
        end
        return nil
    end
    for _, fullType in ipairs(choices) do
        local item = carriedMatch(character:getInventory(), fullType, {})
        if item ~= nil then return item end
    end
    local storage = rawget(_G, "KnoxBaseStorage")
    if base == nil or storage == nil or storage.findItemType == nil then return nil end
    for _, fullType in ipairs(choices) do
        local _, item = storage.findItemType(base, function(candidate)
            return safeCall(candidate, "getFullType") == fullType and usableTool(candidate)
        end)
        if item ~= nil then return item end
    end
    return nil
end

local function addPart(requirements, part)
    local fullType = part.itemType
    if type(fullType) ~= "string" or fullType == "" or string.sub(fullType, 1, 4) == "Tag." then
        return false
    end
    local amount = math.max(1, math.ceil(tonumber(part.amount) or 1))
    local script = ScriptManager ~= nil and ScriptManager.instance ~= nil
        and ScriptManager.instance:FindItem(fullType) or nil
    if instanceOf(script, "DrainableComboItem") then
        requirements.items[fullType] = math.max(requirements.items[fullType] or 0, 1)
        requirements.itemRules[fullType] = requirements.itemRules[fullType] or {}
        requirements.itemRules[fullType].minUses = (requirements.itemRules[fullType].minUses or 0) + amount
    else
        requirements.items[fullType] = (requirements.items[fullType] or 0) + amount
    end
    return true
end

local function requirementsFor(props, character, base)
    local requirements = { items = {}, itemRules = {} }
    for _, second in ipairs({ false, true }) do
        local tool = repairTool(props, character, base, second)
        if tool == nil then return nil end
        if tool ~= true then
            local fullType = tool:getFullType()
            requirements.items[fullType] = 1
            requirements.itemRules[fullType] = toolRule(fullType)
        end
    end
    local parts = safeCall(props, "getAllRepairParts")
    if type(parts) ~= "table" then return nil end
    local optional = {}
    for _, part in ipairs(parts) do
        if part.required == true then
            if not addPart(requirements, part) then return nil end
        else optional[#optional + 1] = part end
    end
    if #optional == 0 then
        return requirementsAvailable(base, character, requirements) and requirements or nil
    end
    for _, part in ipairs(optional) do
        local candidate = { items = {}, itemRules = {} }
        for key, count in pairs(requirements.items) do candidate.items[key] = count end
        for key, rule in pairs(requirements.itemRules) do
            candidate.itemRules[key] = {}
            for field, value in pairs(rule) do candidate.itemRules[key][field] = value end
        end
        if addPart(candidate, part) and requirementsAvailable(base, character, candidate) then
            return candidate
        end
    end
    return nil
end

local function spriteName(object)
    local sprite = safeCall(object, "getSprite")
    return tostring(safeCall(sprite, "getName") or "")
end

local function descriptor(base, region, object, props)
    local square = object:getSquare()
    local name = spriteName(object)
    return {
        id = "repair:" .. tostring(base.id) .. ":"
            .. tostring(region.id or "territory") .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()) .. ":" .. name,
        auto = true,
        action = "repair",
        zoneType = "repair",
        zoneId = region.id,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = object:getObjectIndex(),
        spriteName = name,
        requiredItems = {},
    }
end

local function inside(x, y, minX, minY, maxX, maxY)
    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

local function closestRepairOnSquare(square, character, best, bestDistance, base, region, eligible)
    local objects = square ~= nil and square:getObjects() or nil
    if objects == nil then
        return best, bestDistance
    end
    local origin = character ~= nil and character:getCurrentSquare() or nil
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local props = repairProps(object, character, true)
        local approach = props ~= nil and approachSquare(object, character) or nil
        if props ~= nil and approach ~= nil then
            local dx = origin ~= nil and square:getX() - origin:getX() or 0
            local dy = origin ~= nil and square:getY() - origin:getY() or 0
            local distance = dx * dx + dy * dy
            if distance < bestDistance then
                local target = descriptor(base, region, object, props)
                local requirements = requirementsFor(props, character, base)
                if requirements ~= nil and (eligible == nil or eligible(target)) then
                    target.requiredItems = requirements.items
                    target.requiredItemRules = requirements.itemRules
                    best = target
                    bestDistance = distance
                end
            end
        end
    end
    return best, bestDistance
end

function Repairs.findTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil or character == nil then
        return nil, "base_character_or_cell_unavailable"
    end
    local origin = character:getCurrentSquare()
    local best, bestDistance = nil, math.huge
    for _, region in ipairs(repairRegions(base, character)) do
        local minX, minY, maxX, maxY, z = zoneBounds(region)
        local centerX = origin ~= nil and origin:getX()
            or math.floor((minX + maxX) / 2)
        local centerY = origin ~= nil and origin:getY()
            or math.floor((minY + maxY) / 2)
        for radius = 0, MAX_SCAN_RADIUS do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local x, y = centerX + dx, centerY + dy
                        if inside(x, y, minX, minY, maxX, maxY) then
                            best, bestDistance = closestRepairOnSquare(
                                cell:getGridSquare(x, y, z),
                                character,
                                best,
                                bestDistance,
                                base,
                                region,
                                eligible
                            )
                        end
                    end
                end
            end
            -- Rings are visited nearest-first, so the first successful ring is
            -- already optimal. Avoid scanning thousands of farther squares once
            -- a valid loaded repair is known.
            if best ~= nil then
                return best, "found"
            end
        end
    end
    local engine,engineResult=nil,nil
    if KnoxBaseEngineRepairs ~= nil then
        engine,engineResult=KnoxBaseEngineRepairs.findTask(base,character,eligible)
    end
    if engine ~= nil then return engine,engineResult end
    return best, best ~= nil and "found" or "no_repair_ready"
end

local function objectAt(square, target)
    local objects = square ~= nil and square:getObjects() or nil
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if isStructure(object) and spriteName(object) == tostring(target.spriteName or "") then
            if tonumber(object:getObjectIndex()) == tonumber(target.objectIndex) then
                return object
            end
        end
    end
    return nil
end

function Repairs.resolveTarget(base, target, character)
    if target ~= nil and target.action == "repair_engine" then
        return KnoxBaseEngineRepairs.resolveTarget(base,target,character)
    end
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil or character == nil then
        return nil, "missing_repair_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local object = objectAt(square, target)
    local props = repairProps(object, character)
    local approach = props ~= nil and approachSquare(object, character) or nil
    if object == nil or props == nil or approach == nil then
        return nil, "repair_target_unavailable"
    end
    return {
        object = object,
        props = props,
        square = square,
        approach = approach,
        spriteName = spriteName(object),
    }, "resolved"
end

-- Installed add returns this character's queue on admission, nil on refusal.
-- begin() may run synchronously, so admission is distinct from queue presence
-- or eventual repair health receipt. The controller owns failure cleanup.
local function queueNativeAction(character, action, stage)
    local ok, queue = pcall(ISTimedActionQueue.add, action)
    if not ok then return nil, stage .. "_queue_error" end
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, stage .. "_queue_refused"
    end
    return action, "queued"
end

function Repairs.queueAction(character, target)
    if target ~= nil and target.kind == "engine" then
        return KnoxBaseEngineRepairs.queueAction(character,target)
    end
    if character == nil or target == nil or target.props == nil
        or target.object == nil or target.square == nil then
        return nil, "missing_repair_target"
    end
    if repairProps(target.object, character) == nil then return nil, "repair_not_ready" end
    local firstTool = repairTool(target.props, character, nil, false)
    local secondTool = repairTool(target.props, character, nil, true)
    if not usableTool(firstTool) or not usableTool(secondTool) then
        return nil, "repair_tool_unavailable"
    end
    if firstTool ~= true then
        ISWorldObjectContextMenu.equip(
            character,
            character:getPrimaryHandItem(),
            firstTool,
            true,
            false
        )
    end
    if secondTool ~= true then
        if instanceOf(secondTool, "Clothing") then
            if safeCall(character, "isEquippedClothing", secondTool) ~= true then
                local source = safeCall(secondTool, "getContainer")
                local inventory = character:getInventory()
                if source ~= nil and source ~= inventory then
                    local transfer = KnoxInventoryActions.queueTransfer(
                        character,
                        secondTool,
                        source,
                        inventory,
                        nil
                    )
                    if transfer == nil then
                        return nil, "repair_clothing_transfer_failed"
                    end
                end
                local wear, wearReason = queueNativeAction(character,
                    ISWearClothing:new(character, secondTool), "repair_clothing")
                if wear == nil then return nil, wearReason end
            end
        else
            ISWorldObjectContextMenu.equip(
                character,
                character:getSecondaryHandItem(),
                secondTool,
                false,
                false
            )
        end
    end
    local action = ISMoveablesAction:new(
        character,
        target.square,
        "repair",
        target.spriteName,
        target.object,
        nil,
        nil,
        nil
    )
    return queueNativeAction(character, action, "repair_action")
end

function Repairs.snapshot(target)
    if target ~= nil and target.kind == "engine" then return KnoxBaseEngineRepairs.snapshot(target) end
    local object = target ~= nil and target.object or nil
    local square = safeCall(object,"getSquare")
    local index = tonumber(safeCall(object,"getObjectIndex"))
    local objects = safeCall(square,"getObjects")
    if object == nil or square == nil or square ~= target.square
        or index == nil or index < 0 or objects == nil
        or safeCall(objects,"get",index) ~= object then return nil end
    local health = tonumber(safeCall(object,"getHealth"))
    if health == nil or health ~= health or health < 0 or health == math.huge then return nil end
    return health
end

function Repairs.isComplete(target, before)
    if target ~= nil and target.kind == "engine" then return KnoxBaseEngineRepairs.isComplete(target,before) end
    before = tonumber(before)
    if before == nil or before ~= before or before < 0 or before == math.huge then return false end
    local health = Repairs.snapshot(target)
    return health ~= nil and health > before
end

function Repairs.resolveTaskSquare(base, target, character)
    local resolved = Repairs.resolveTarget(base, target, character)
    return resolved ~= nil and resolved.approach or nil
end

return Repairs
