require "Farming/TimedActions/ISWaterPlantAction"
require "Farming/TimedActions/ISHarvestPlantAction"
require "Farming/TimedActions/ISPlowAction"
require "Farming/TimedActions/ISSeedActionNew"
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivorInventoryActions"
pcall(function() require "KS_DebugLog" end)

local Farming = rawget(_G, "KnoxBaseFarming") or {}
_G.KnoxBaseFarming = Farming

local function farmingSystem()
    if CFarmingSystem ~= nil and CFarmingSystem.instance ~= nil then
        return CFarmingSystem.instance
    end
    if SFarmingSystem ~= nil and SFarmingSystem.instance ~= nil then
        return SFarmingSystem.instance
    end
    return nil
end

local function plantAt(square)
    local system = farmingSystem()
    if system == nil or square == nil then
        return nil
    end
    local success, plant = pcall(function()
        return system:getLuaObjectOnSquare(square)
    end)
    return success and plant or nil
end

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    if success then return value end
    return nil
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

local function itemHasTag(item, tag)
    if item == nil or tag == nil or item.hasTag == nil then
        return false
    end
    local success, result = pcall(item.hasTag, item, tag)
    return success and result == true
end

local function itemUsable(item)
    if item == nil then
        return false
    end
    if item.isBroken ~= nil then
        local success, broken = pcall(item.isBroken, item)
        if success and broken == true then
            return false
        end
    end
    return true
end

local function findInventoryItem(character, predicate)
    if character == nil or character.getInventory == nil then
        return nil
    end
    local found = nil
    walkItems(character:getInventory(), function(item)
        if found == nil and itemUsable(item) and predicate(item) then
            found = item
        end
    end)
    return found
end

local function plowItem(character)
    return findInventoryItem(character, function(item)
        return ItemTag ~= nil and itemHasTag(item, ItemTag.DIG_PLOW)
    end)
end

local function seedTypeForItem(item)
    if item == nil or item.getFullType == nil
        or farming_vegetableconf == nil
        or farming_vegetableconf.props == nil then
        return nil
    end
    local fullType = item:getFullType()
    for typeOfSeed, props in pairs(farming_vegetableconf.props) do
        local seedTypes = props.seedTypes or { props.seedName }
        for _, seedType in ipairs(seedTypes) do
            if seedType ~= nil and seedType == fullType then
                return typeOfSeed
            end
        end
    end
    return nil
end

local function usableSeed(item)
    if not itemUsable(item) then return false end
    -- Planting material can be food (fruit, vegetables or cuttings). Apply
    -- the installed player planting restrictions before selecting supplies;
    -- the native seed action itself checks possession, not food quality.
    local food = instanceof ~= nil and instanceof(item, "Food")
    if not food then return true end
    if safeCall(item, "isRotten") ~= false or safeCall(item, "isCooked") ~= false
        or safeCall(item, "isBurnt") ~= false then return false end
    local fresh = safeCall(item, "isFresh")
    if fresh == nil then return false end
    if ItemTag ~= nil and itemHasTag(item, ItemTag.IS_CUTTING) and not fresh then return false end
    local whole = tonumber(safeCall(item, "getBaseHunger"))
    local remaining = tonumber(safeCall(item, "getHungerChange"))
    if whole == nil or remaining == nil or whole ~= whole or remaining ~= remaining
        or math.abs(whole) == math.huge or math.abs(remaining) == math.huge then return false end
    return math.abs(remaining) >= math.abs(whole) * (fresh and 1 or 0.75)
end

local function seedItem(character, desiredItemType, desiredCrop)
    if ItemTag == nil or ItemTag.IS_SEED == nil then
        return nil, nil
    end
    local found, foundType = nil, nil
    if character == nil or character.getInventory == nil then
        return nil, nil
    end
    walkItems(character:getInventory(), function(item)
        if found ~= nil or not itemHasTag(item, ItemTag.IS_SEED) or not usableSeed(item) then
            return
        end
        local typeOfSeed = seedTypeForItem(item)
        if typeOfSeed ~= nil
            and (desiredItemType == nil or item:getFullType() == desiredItemType)
            and (desiredCrop == nil or typeOfSeed == desiredCrop) then
            found = item
            foundType = typeOfSeed
        end
    end)
    return found, foundType
end

local function canDig(square)
    if square == nil or ISFarmingMenu == nil
        or ISFarmingMenu.canDigHereSquare == nil then
        return false
    end
    local success, result = pcall(ISFarmingMenu.canDigHereSquare, square)
    return success and result == true
end

local function wateringItem(character)
    if character == nil or ISFarmingMenu == nil
        or ISFarmingMenu.getWaterUsesInteger == nil then
        return nil, 0
    end
    local found, uses = nil, 0
    walkItems(character:getInventory(), function(item)
        if found ~= nil or item == nil then
            return
        end
        local success, count = pcall(function()
            return ISFarmingMenu.getWaterUsesInteger(item)
        end)
        if success and (tonumber(count) or 0) > 0 then
            found = item
            uses = tonumber(count) or 0
        end
    end)
    return found, uses
end

function Farming.findWaterItem(character, desiredFullType)
    local item, uses = wateringItem(character)
    if item == nil then
        return nil, 0
    end
    if desiredFullType ~= nil and item:getFullType() ~= desiredFullType then
        local found, foundUses = nil, 0
        walkItems(character:getInventory(), function(candidate)
            if found ~= nil or candidate == nil
                or candidate:getFullType() ~= desiredFullType
                or ISFarmingMenu == nil
                or ISFarmingMenu.getWaterUsesInteger == nil then
                return
            end
            local success, count = pcall(function()
                return ISFarmingMenu.getWaterUsesInteger(candidate)
            end)
            if success and (tonumber(count) or 0) > 0 then
                found = candidate
                foundUses = tonumber(count) or 0
            end
        end)
        return found, foundUses
    end
    return item, uses
end

local function canHarvest(plant)
    local result = safeCall(plant, "canHarvest")
    return result == true
end

local function isAlive(plant)
    local result = safeCall(plant, "isAlive")
    return result == nil or result == true
end

local function isSeeded(plant)
    return plant ~= nil and tostring(plant.state or "") == "seeded" and isAlive(plant)
end

-- Native watering adds ten points per use. Keep a reserve above the crop's
-- minimum, without repeatedly topping off healthy plants or exceeding its cap.
local function wateringPlan(plant, availableUses)
    if not isSeeded(plant) then return 0, 0 end
    local level = tonumber(plant.waterLvl)
    if level == nil then return 0, 0 end
    local minimum = math.max(0, math.min(100, tonumber(plant.waterNeeded) or 70))
    local maximum = math.max(0, math.min(100, tonumber(plant.waterNeededMax) or 100))
    local target = math.min(maximum, minimum + 20)
    if level > math.min(target - 10, minimum + 5) then return 0, 0 end
    local uses = math.min(math.floor(tonumber(availableUses) or 0),
        math.max(0, math.floor((maximum - level) / 10)),
        math.max(0, math.ceil((target - level) / 10)))
    return uses, math.max(0, minimum - level)
end

local function descriptor(base, zone, square, plant, action, waterItem, waterUses,
    plowTool, seed, seedType)
    return {
        id = "farm:" .. tostring(base.id) .. ":" .. tostring(action) .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()),
        auto = true,
        zoneType = action,
        zoneId = zone.id,
        action = action,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        waterUses = tonumber(waterUses) or 0,
        waterItemType = waterItem ~= nil and waterItem:getFullType() or nil,
        plantType = tostring(plant ~= nil and plant.typeOfSeed or "unknown"),
        plowToolType = plowTool ~= nil and plowTool:getFullType() or nil,
        seedItemType = seed ~= nil and seed:getFullType() or nil,
        seedType = seedType,
    }
end

local function orderedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "farming" then
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

function Farming.findTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local water, waterUses = wateringItem(character)
    local seed, seedType = seedItem(character)
    local plowTool = plowItem(character)
    -- Discovery may use real cupboard supplies; execution still requires
    -- the job supply planner to transfer them into the worker's inventory.
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage ~= nil and storage.findItemType ~= nil then
        if seed == nil then
            local _, storedSeed = storage.findItemType(base, function(item)
                return usableSeed(item) and ItemTag ~= nil
                    and itemHasTag(item, ItemTag.IS_SEED) and seedTypeForItem(item) ~= nil
            end)
            seed, seedType = storedSeed, seedTypeForItem(storedSeed)
        end
        if plowTool == nil then
            local _, storedTool = storage.findItemType(base, function(item)
                return itemUsable(item) and ItemTag ~= nil
                    and itemHasTag(item, ItemTag.DIG_PLOW)
            end)
            plowTool = storedTool
        end
        if water == nil and ISFarmingMenu ~= nil then
            local _, storedWater = storage.findItemType(base, function(item)
                return (tonumber(ISFarmingMenu.getWaterUsesInteger(item)) or 0) > 0
            end)
            if storedWater ~= nil then
                water = storedWater
                waterUses = tonumber(ISFarmingMenu.getWaterUsesInteger(water)) or 0
            end
        end
    end
    local best, bestReason, bestRank, bestDeficit, bestDistance = nil, nil, -1, -1, math.huge
    local current = safeCall(character, "getCurrentSquare")
    local cx, cy, cz = safeCall(current, "getX"), safeCall(current, "getY"), safeCall(current, "getZ")
    -- Compare work across every assigned garden. One visit per tile replaces
    -- four separate scans and prevents an early zone's new plots hiding harvests.
    for _, zone in ipairs(orderedZones(base)) do
        local minX, minY, maxX, maxY, z = zoneBounds(zone)
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                local plant = square ~= nil and plantAt(square) or nil
                local action, reason, rank, uses, deficit = nil, nil, 0, 0, 0
                if plant ~= nil and isAlive(plant) and canHarvest(plant) then
                    action, reason, rank = "farm_harvest", "harvest", 4
                elseif plant ~= nil and water ~= nil then
                    uses, deficit = wateringPlan(plant, waterUses)
                    if uses > 0 then action, reason, rank = "farm_water", "water", 3 end
                end
                if action == nil and seed ~= nil and seedType ~= nil then
                    if plant ~= nil and tostring(plant.state or "") == "plow" then
                        action, reason, rank = "farm_seed", "seed", 2
                    elseif square ~= nil and plant == nil and plowTool ~= nil and canDig(square) then
                        action, reason, rank = "farm_plow", "plow", 1
                    end
                end
                local distance = cx ~= nil and cy ~= nil and cz == z
                    and ((x - cx)^2 + (y - cy)^2) or math.huge
                if action ~= nil and (rank > bestRank
                    or rank == bestRank and (deficit > bestDeficit
                        or deficit == bestDeficit and distance < bestDistance)) then
                    local candidate = descriptor(base, zone, square, plant, action,
                        action == "farm_water" and water or nil, uses,
                        action == "farm_plow" and plowTool or nil,
                        (action == "farm_plow" or action == "farm_seed") and seed or nil,
                        (action == "farm_plow" or action == "farm_seed") and seedType or nil)
                    if eligible == nil or eligible(candidate) then
                        best = candidate
                        bestReason, bestRank, bestDeficit, bestDistance = reason, rank, deficit, distance
                    end
                end
            end
        end
    end
    if best ~= nil then return best, bestReason end
    return nil, "no_farming_action_ready"
end

function Farming.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_farming_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local plant = square ~= nil and plantAt(square) or nil
    if target.action == "farm_plow" then
        if square == nil or plant ~= nil or not canDig(square) then
            return nil, "square_not_diggable"
        end
        local tool = findInventoryItem(character, function(item)
            return ItemTag ~= nil and itemHasTag(item, ItemTag.DIG_PLOW)
        end)
        if tool == nil then
            return nil, "plow_tool_unavailable"
        end
        return {
            action = target.action,
            square = square,
            plant = nil,
            plowItem = tool,
        }, "resolved"
    end
    if plant == nil then
        return nil, "plant_unloaded"
    end
    if target.action == "farm_harvest" and not canHarvest(plant) then
        return nil, "plant_not_harvestable"
    end
    if target.action == "farm_water"
        and wateringPlan(plant, 10) <= 0 then
        return nil, "plant_does_not_need_water"
    end
    if target.action == "farm_seed"
        and tostring(plant.state or "") ~= "plow" then
        return nil, "plant_not_plowed"
    end
    local seed, typeOfSeed = seedItem(character, target.seedItemType, target.seedType)
    if target.action == "farm_seed" and (seed == nil or typeOfSeed == nil) then
        return nil, "seed_item_unavailable"
    end
    return {
        action = target.action,
        square = square,
        plant = plant,
        seedItem = seed,
        seedType = typeOfSeed or target.seedType,
    }, "resolved"
end

local function prepareCarriedItem(character, item)
    local inventory = character:getInventory()
    local source = safeCall(item, "getContainer")
    if source == nil then return false, "farming_item_unavailable" end
    if source == inventory then return true end
    local carried = false
    walkItems(inventory, function(candidate)
        if candidate == item then carried = true end
    end)
    if not carried then return false, "farming_item_not_carried" end
    local action, reason = KnoxInventoryActions.queueTransfer(character, item, source, inventory, nil)
    return action ~= nil, reason
end

local function traceEnabled()
    local log = rawget(_G, "KnoxDebugLog")
    if log == nil or log.log == nil or log.diagnosticsEnabled == nil then return false end
    local ok, enabled = pcall(log.diagnosticsEnabled)
    return ok and enabled == true
end

-- Observe a native action instance, never its global class. This can also be
-- used for a paired local-player action in the disposable diagnostic replay.
function Farming.traceAction(character, target, action, context)
    if action == nil or action.KnoxFarmingTraceAttached == true or not traceEnabled() then return action end
    action.KnoxFarmingTraceAttached = true
    context = context or {}
    local lastPoll, observedPoll = {}, {}
    local function emit(phase, result)
        if not traceEnabled() then return end
        -- Diagnostics cannot change native admission, returns or errors.
        pcall(function()
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            local id = context.survivorId or (runtime ~= nil and runtime.idForCharacter ~= nil
                and runtime.idForCharacter(character)) or "player_or_unregistered"
            local square = safeCall(character, "getCurrentSquare")
            local item = action.item or action.seed or target.plowItem or target.seedItem
            local source = safeCall(item, "getContainer")
            local client = CFarmingSystem ~= nil and CFarmingSystem.instance or nil
            local server = SFarmingSystem ~= nil and SFarmingSystem.instance or nil
            local clientPlant = safeCall(client, "getLuaObjectOnSquare", target.square)
            local serverPlant = safeCall(server, "getLuaObjectOnSquare", target.square)
            local function value(value) return value ~= nil and tostring(value) or "unavailable" end
            KnoxDebugLog.log("jobs", id, "farm_native_" .. phase, {
                task = context.taskId, base = context.baseId, kind = target.action,
                action = value(action.Type), actionToken = tostring(action), result = value(result),
                actorClass = value(safeCall(safeCall(character, "getClass"), "getName")),
                charX = value(safeCall(square, "getX")), charY = value(safeCall(square, "getY")),
                charZ = value(safeCall(square, "getZ")),
                tx = value(safeCall(target.square, "getX")), ty = value(safeCall(target.square, "getY")),
                tz = value(safeCall(target.square, "getZ")),
                itemId = value(safeCall(item, "getID")), itemType = value(safeCall(item, "getFullType")),
                itemInSource = value(safeCall(source, "contains", item)),
                itemInRoot = value(safeCall(safeCall(character, "getInventory"), "contains", item)),
                clientSystem = client ~= nil, serverSystem = server ~= nil,
                clientState = value(clientPlant ~= nil and clientPlant.state or nil),
                clientWater = value(clientPlant ~= nil and clientPlant.waterLvl or nil),
                serverState = value(serverPlant ~= nil and serverPlant.state or nil),
                serverWater = value(serverPlant ~= nil and serverPlant.waterLvl or nil),
            })
        end)
    end
    local function pack(...) return { n = select("#", ...), ... } end
    for _, phase in ipairs({ "isValid", "waitToStart", "start", "stop", "perform", "complete" }) do
        local original = action[phase]
        if type(original) == "function" then
            action[phase] = function(self, ...)
                local poll = phase == "isValid" or phase == "waitToStart"
                if not poll then emit(phase .. "_enter") end
                local returned = pack(original(self, ...))
                if poll then
                    if not observedPoll[phase] or lastPoll[phase] ~= returned[1] then
                        observedPoll[phase], lastPoll[phase] = true, returned[1]
                        emit(phase, returned[1])
                    end
                else emit(phase .. "_return", returned[1]) end
                return unpack(returned, 1, returned.n)
            end
        end
    end
    -- Attaching observation does not prove queue admission or native success.
    emit("observed")
    return action
end

-- Native add may refuse or throw from begin(), and successful begin can finish
-- synchronously. The registered queue is admission; crop changes remain the
-- separate completion receipt owned by isComplete and the controller.
local function admitAction(character, target, action, context)
    Farming.traceAction(character, target, action, context)
    local ok, queue = pcall(ISTimedActionQueue.add, action)
    if not ok then return nil, "farming_queue_error" end
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, "farming_queue_refused"
    end
    return action, "queued"
end

function Farming.queueAction(character, target, water, context)
    if character == nil or target == nil then
        return nil, "missing_farming_target"
    end
    if target.action == "farm_harvest" then
        local action = ISHarvestPlantAction:new(character, target.plant, 100)
        return admitAction(character, target, action, context)
    end
    if target.action == "farm_water" then
        local item = water ~= nil and water.item or nil
        safeCall(target.plant, "updateFromIsoObject")
        local uses = wateringPlan(target.plant,
            tonumber(water ~= nil and water.uses or target.waterUses) or 0)
        if item == nil or uses <= 0 then
            return nil, "watering_item_unavailable"
        end
        local ready, reason = prepareCarriedItem(character, item)
        if not ready then return nil, reason end
        local action = ISWaterPlantAction:new(
            character,
            item,
            uses,
            target.square,
            20 + (6 * uses)
        )
        return admitAction(character, target, action, context)
    end
    if target.action == "farm_plow" then
        if target.plowItem == nil then
            return nil, "plow_tool_unavailable"
        end
        local ready, reason = prepareCarriedItem(character, target.plowItem)
        if not ready then return nil, reason end
        local action = ISPlowAction:new(
            character,
            target.square,
            target.plowItem
        )
        return admitAction(character, target, action, context)
    end
    if target.action == "farm_seed" then
        if target.seedItem == nil or target.seedType == nil or not usableSeed(target.seedItem) then
            return nil, "seed_item_unavailable"
        end
        local ready, reason = prepareCarriedItem(character, target.seedItem)
        if not ready then return nil, reason end
        local action = ISSeedActionNew:new(
            character,
            target.seedItem,
            target.seedType,
            target.plant
        )
        -- A transfer/wait may outlive this plan. The native complete callback
        -- removes its seed before checking whether the plot is still plowed,
        -- so reject stale material/plots before either native boundary runs.
        local nativeValid, nativeComplete = action.isValid, action.complete
        local function current(self)
            safeCall(target.plant, "updateFromIsoObject")
            return usableSeed(self.seed) and seedTypeForItem(self.seed) == target.seedType
                and plantAt(target.square) == target.plant and target.plant.state == "plow"
                and (nativeValid == nil or nativeValid(self) == true)
        end
        action.isValid = current
        if nativeComplete ~= nil then
            action.complete = function(self)
                if not current(self) then return false end
                return nativeComplete(self)
            end
        end
        return admitAction(character, target, action, context)
    end
    return nil, "unsupported_farming_action"
end

function Farming.snapshot(target)
    if target == nil then
        return { water = 0, harvestable = false, state = nil }
    end
    if target.action == "farm_plow" then
        local plant = plantAt(target.square)
        return {
            water = 0,
            harvestable = false,
            state = plant ~= nil and plant.state or nil,
        }
    end
    if target.plant == nil then
        return { water = 0, harvestable = false, state = nil }
    end
    return {
        water = tonumber(target.plant.waterLvl),
        harvestable = canHarvest(target.plant),
        state = target.plant.state,
    }
end

function Farming.isComplete(target, before)
    if target == nil then
        return false
    end
    if target.action == "farm_plow" then
        local plant = plantAt(target.square)
        return plant ~= nil and tostring(plant.state or "") == "plow"
    end
    if target.plant == nil then
        return false
    end
    if target.action == "farm_harvest" then
        -- A failed native read is unknown, not evidence that harvest completed.
        return before ~= nil and before.harvestable == true
            and safeCall(target.plant, "canHarvest") == false
    end
    if target.action == "farm_seed" then
        return isSeeded(target.plant)
            and (target.seedType == nil or target.plant.typeOfSeed == target.seedType)
    end
    if target.action ~= "farm_water" then return false end
    local after = tonumber(target.plant.waterLvl)
    local prior = tonumber(before ~= nil and before.water or nil)
    return after ~= nil and prior ~= nil and after == after and prior == prior
        and after >= 0 and after < math.huge and prior >= 0 and prior < math.huge
        and after > prior
end

return Farming
