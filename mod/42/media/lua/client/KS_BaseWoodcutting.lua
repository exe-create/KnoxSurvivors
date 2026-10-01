require "TimedActions/ISChopTreeAction"
require "TimedActions/ISTimedActionQueue"
require "Entity/TimedActions/ISHandcraftAction"

local Woodcutting = rawget(_G, "KnoxBaseWoodcutting") or {}
_G.KnoxBaseWoodcutting = Woodcutting

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
end

local function walkItems(container, visitor)
    if container == nil or container.getItems == nil then
        return
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item)
        if item ~= nil and item.IsInventoryContainer ~= nil
            and item:IsInventoryContainer() then
            walkItems(item:getInventory(), visitor)
        end
    end
end

local function findAxe(character)
    if character == nil or character.getInventory == nil
        or ItemTag == nil or ItemTag.CHOP_TREE == nil then
        return nil
    end
    local found = nil
    walkItems(character:getInventory(), function(item)
        if found ~= nil or item == nil or item.hasTag == nil then
            return
        end
        local success, isAxe = pcall(item.hasTag, item, ItemTag.CHOP_TREE)
        local broken = safeCall(item, "isBroken") == true
        if success and isAxe == true and broken ~= true then
            found = item
        end
    end)
    return found
end

local function findItem(character, fullType, tag)
    if character == nil or character.getInventory == nil then
        return nil
    end
    local found = nil
    walkItems(character:getInventory(), function(item)
        if found ~= nil or item == nil then
            return
        end
        local matchesType = fullType == nil or (item.getFullType ~= nil
            and item:getFullType() == fullType)
        local matchesTag = tag == nil or (item.hasTag ~= nil
            and safeCall(item, "hasTag", tag) == true)
        local broken = safeCall(item, "isBroken") == true
        if matchesType and matchesTag and not broken then
            found = item
        end
    end)
    return found
end

local function sawItem(character)
    return ItemTag ~= nil and findItem(character, nil, ItemTag.SAW) or nil
end

local function logItem(character)
    return findItem(character, "Base.Log", nil)
end

local function storedItem(base, predicate)
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage == nil or storage.findItemType == nil then return nil end
    return storage.findItemType(base, predicate)
end

local function craftContainers(character)
    if ArrayList == nil or character == nil or character.getInventory == nil then
        return nil
    end
    local containers = ArrayList.new()
    containers:add(character:getInventory())
    return containers
end

local function sawRecipe()
    local manager = getScriptManager ~= nil and getScriptManager() or nil
    return safeCall(manager, "getCraftRecipe", "Base.SawLogs")
end

local function canSaw(character, log, saw)
    local recipe, containers = sawRecipe(), craftContainers(character)
    if recipe == nil or containers == nil or log == nil or saw == nil
        or HandcraftLogic == nil then return nil, nil, "saw_recipe_unavailable" end
    local ok, valid = pcall(function()
        local logic = HandcraftLogic.new(character, nil, nil)
        logic:setContainers(containers)
        logic:setRecipe(recipe)
        return logic:canPerformCurrentRecipe()
    end)
    if not ok or not valid then return nil, nil, "saw_recipe_not_valid" end
    return recipe, containers, "ready"
end

local function treeAt(square)
    if square == nil or square.HasTree == nil then
        return nil
    end
    local hasTree = safeCall(square, "HasTree")
    if hasTree ~= true or square.getTree == nil then
        return nil
    end
    return safeCall(square, "getTree")
end

local function orderedZones(base, purpose)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        -- A wood lot is for harvesting trees; a log-processing area is for the
        -- saw recipe. They share one native executor, but keeping the boundaries
        -- distinct prevents a saw bench from becoming an accidental chop area.
        local isWood = zone ~= nil and zone.type == "woodcutting"
        local isLogs = zone ~= nil and zone.type == "log_processing"
        local selected = purpose == "saw" and isLogs or purpose ~= "saw" and isWood
        -- Preserve the original behavior for existing bases that only have a
        -- woodcutting area: it remains a valid fallback saw location.
        if purpose == "saw" and isWood and not selected then
            local hasLogZone = false
            for _, candidate in pairs(base ~= nil and base.zones or {}) do
                if candidate ~= nil and candidate.enabled ~= false
                    and candidate.type == "log_processing" then
                    hasLogZone = true
                    break
                end
            end
            selected = not hasLogZone
        end
        if zone ~= nil and zone.enabled ~= false
            and selected then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.id) < tostring(second.id)
    end)
    return zones
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1) or 0
    local minY = tonumber(zone.y1) or 0
    local maxX = tonumber(zone.x2) or minX
    local maxY = tonumber(zone.y2) or minY
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function descriptor(base, zone, square, tree, axe)
    return {
        id = "woodcut:" .. tostring(base.id) .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()),
        auto = true,
        zoneType = "chop_tree",
        zoneId = zone.id,
        action = "chop_tree",
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = tree ~= nil and tree:getObjectIndex() or -1,
        axeType = axe ~= nil and axe:getFullType() or nil,
    }
end

function Woodcutting.findAxe(character)
    return findAxe(character)
end

function Woodcutting.findSaw(character)
    return sawItem(character)
end

function Woodcutting.findLog(character)
    return logItem(character)
end

-- Explicit inventory orders use the same native handcraft action as an
-- automatic base task. The owner is deliberately passed through unchanged:
-- an off-slot IsoPlayer survivor, not the local player, performs the recipe.
function Woodcutting.queueSawLogs(character)
    local log, saw = logItem(character), sawItem(character)
    local recipe, containers, reason = canSaw(character, log, saw)
    if recipe == nil then return nil, reason end
    return Woodcutting.queueAction(character, {
        action = "saw_logs",
        character = character,
        log = log,
        saw = saw,
        recipe = recipe,
        containers = containers,
    })
end

function Woodcutting.findTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    local axe = findAxe(character)
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local log, saw = logItem(character), sawItem(character)
    local logType = log ~= nil and log:getFullType() or storedItem(base, function(item)
        return safeCall(item, "getFullType") == "Base.Log"
    end)
    local sawType = saw ~= nil and saw:getFullType() or storedItem(base, function(item)
        return ItemTag ~= nil and ItemTag.SAW ~= nil
            and safeCall(item, "hasTag", ItemTag.SAW) == true
            and safeCall(item, "isBroken") ~= true
    end)
    if logType ~= nil and sawType ~= nil and sawRecipe() ~= nil then
        for _, zone in ipairs(orderedZones(base, "saw")) do
            local targetId = "saw:" .. tostring(base.id) .. ":" .. tostring(zone.id)
            -- A claimed zone-level processing task cannot use another tile in
            -- the same zone. Skip its scan before inspecting hundreds of squares.
            if eligible == nil or eligible({ id = targetId, action = "saw_logs", zoneId = zone.id }) then
                local minX, minY, maxX, maxY, z = zoneBounds(zone)
                -- A blocked corner does not invalidate the whole work area.
                -- Bound discovery just as tree scanning is bounded below.
                for x = minX, math.min(maxX, minX + 96) do
                    for y = minY, math.min(maxY, minY + 96) do
                        local square = cell:getGridSquare(x, y, z)
                        if square ~= nil and safeCall(square, "canStand") == true then
                            local target = { id = targetId,
                                action = "saw_logs", zoneType = "saw_logs", zoneId = zone.id, auto = true,
                                x = x, y = y, z = z, logType = logType, sawType = sawType }
                            if eligible == nil or eligible(target) then return target, "found" end
                        end
                    end
                end
            end
        end
        -- Storage-based auto processing: logs (falling back to legacy
        -- building) storage doubles as the saw site so logs become planks
        -- when needed without a log_processing zone.
        -- Tries every candidate store closest-first so multiple locations work.
        local storage = rawget(_G, "KnoxBaseStorage")
        if storage ~= nil and storage.policies ~= nil and storage.resolvePolicy ~= nil then
            local candidates = {}
            for _, policy in ipairs(storage.policies(base)) do
                local filters = storage.filtersForPolicy ~= nil
                    and storage.filtersForPolicy(policy) or nil
                local eligible = policy.storageFilterVersion == 1 and filters ~= nil
                    and filters.logs == true
                    or policy.storageFilterVersion ~= 1
                        and (policy.storageRole == "logs" or policy.storageRole == "building")
                if eligible then
                    candidates[#candidates + 1] = policy
                end
            end
            local origin = character ~= nil and character.getCurrentSquare ~= nil
                and character:getCurrentSquare() or nil
            if origin ~= nil then
                table.sort(candidates, function(a, b)
                    local da = ((tonumber(a.x) or 0) - origin:getX()) ^ 2
                        + ((tonumber(a.y) or 0) - origin:getY()) ^ 2
                    local db = ((tonumber(b.x) or 0) - origin:getX()) ^ 2
                        + ((tonumber(b.y) or 0) - origin:getY()) ^ 2
                    return da < db
                end)
            end
            for _, policy in ipairs(candidates) do
                local resolved = storage.resolvePolicy(policy)
                local square = resolved ~= nil and resolved.square or nil
                if square ~= nil then
                    local targetId = "saw:" .. tostring(base.id) .. ":storage:" .. tostring(policy.key)
                    local workSquare = square
                    if safeCall(square, "canStand") ~= true then
                        -- Use an adjacent standable tile; the log comes from storage.
                        local Adjacent = rawget(_G, "AdjacentFreeTileFinder")
                        if Adjacent ~= nil and Adjacent.Find ~= nil then
                            local ok, adjacent = pcall(function()
                                return Adjacent.Find(square, character)
                            end)
                            if ok and adjacent ~= nil then workSquare = adjacent end
                        end
                    end
                    if workSquare ~= nil and safeCall(workSquare, "canStand") == true then
                        local target = { id = targetId,
                            action = "saw_logs", zoneType = "saw_logs",
                            zoneId = "storage:" .. tostring(policy.key), auto = true,
                            x = workSquare:getX(), y = workSquare:getY(), z = workSquare:getZ(),
                            logType = logType, sawType = sawType,
                            storageKey = policy.key }
                        if eligible == nil or eligible(target) then return target, "found_storage" end
                    end
                end
            end
        end
    end
    if axe == nil then
        local axeType = storedItem(base, function(item)
            return item ~= nil and item.hasTag ~= nil and ItemTag ~= nil
                and ItemTag.CHOP_TREE ~= nil
                and safeCall(item, "hasTag", ItemTag.CHOP_TREE) == true
                and safeCall(item, "isBroken") ~= true
        end)
        if axeType ~= nil then
            axe = { getFullType = function() return axeType end }
        end
    end
    for _, zone in ipairs(orderedZones(base, "chop")) do
        local minX, minY, maxX, maxY, z = zoneBounds(zone)
        maxX = math.min(maxX, minX + 96)
        maxY = math.min(maxY, minY + 96)
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                local tree = treeAt(square)
                if tree ~= nil then
                    local target = descriptor(base, zone, square, tree, axe)
                    if eligible == nil or eligible(target) then return target, "found" end
                end
            end
        end
    end
    return nil, axe == nil and "missing_axe" or "no_tree_ready"
end

function Woodcutting.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_woodcutting_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    if target.action == "saw_logs" then
        local log = logItem(character)
        local saw = sawItem(character)
        local recipe, containers, result = canSaw(character, log, saw)
        if recipe == nil then
            return nil, result
        end
        return {
            log = log,
            character = character,
            saw = saw,
            recipe = recipe,
            containers = containers,
        }, "resolved"
    end
    local tree = treeAt(square)
    if tree == nil or (target.objectIndex ~= nil
        and tonumber(target.objectIndex) ~= tonumber(tree:getObjectIndex())) then
        return nil, "tree_no_longer_valid"
    end
    local axe = findAxe(character)
    if axe == nil then
        return nil, "missing_axe"
    end
    return { square = square, tree = tree, axe = axe }, "resolved"
end

function Woodcutting.queueAction(character, target)
    if target ~= nil and target.recipe ~= nil then
        local recipe, containers, reason = canSaw(character, target.log, target.saw)
        if recipe == nil then return nil, reason end
        -- Build 42 converts manualInputs through convertToPZNetTable during
        -- construction. Passing nil throws before the action reaches the
        -- queue, which made saw-log jobs emit an error every time the worker
        -- recovered and retried. An empty table means no manual selections
        -- while preserving the recipe's normal container resolution.
        local action = ISHandcraftAction:new(character, recipe, containers,
            nil, nil, {}, nil, nil, 1)
        target.action = action
        ISTimedActionQueue.add(action)
        return action, "queued_saw"
    end
    if character == nil or target == nil or target.tree == nil or target.axe == nil then
        return nil, "missing_tree_or_axe"
    end
    character:setPrimaryHandItem(target.axe)
    local action = ISChopTreeAction:new(character, target.tree)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function Woodcutting.isComplete(target)
    if target ~= nil and target.recipe ~= nil then
        -- Native craft completion must consume the real log. An empty queue
        -- alone is never evidence that a plank was produced.
        local stillCarried = false
        walkItems(target.character:getInventory(), function(item)
            if item == target.log then stillCarried = true end
        end)
        if stillCarried or target.action == nil
            or target.action.craftStarted ~= true or ArrayList == nil then return false end
        local outputs = ArrayList.new()
        local logic = target.action.logic
        if logic == nil or logic.getCreatedOutputItems == nil then return false end
        local ok = pcall(logic.getCreatedOutputItems, logic, outputs)
        if not ok then return false end
        for index = 0, outputs:size() - 1 do
            if safeCall(outputs:get(index), "getFullType") == "Base.Plank" then
                return true
            end
        end
        return false
    end
    if target == nil or target.tree == nil then
        return false
    end
    local objectIndex = safeCall(target.tree, "getObjectIndex")
    return objectIndex ~= nil and tonumber(objectIndex) < 0
end

return Woodcutting
