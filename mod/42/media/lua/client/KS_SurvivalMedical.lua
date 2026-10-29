require "Entity/TimedActions/ISHandcraftAction"
require "TimedActions/ISTimedActionQueue"

local MedicalSupplies = rawget(_G, "KnoxMedicalSupplies") or {}
_G.KnoxMedicalSupplies = MedicalSupplies

local function findTreatment(container)
    if container == nil then
        return nil
    end
    local best = nil
    local bestScore = -math.huge
    local function inspect(current)
        local items = current:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item:isCanBandage() then
                local dirtyPenalty = string.find(item:getType(), "Dirty", 1, true) and 50 or 0
                local alcoholBonus = item:isAlcoholic() and 100 or 0
                local score = alcoholBonus + item:getBandagePower() - dirtyPenalty
                if score > bestScore then
                    best = item
                    bestScore = score
                end
            end
            if item:IsInventoryContainer() then
                inspect(item:getInventory())
            end
        end
    end
    inspect(container)
    return best
end

local function isProtectedPersonalItem(character, item)
    return item == nil
        or item:isFavorite()
        or item:IsInventoryContainer()
        or character:getWornItems():contains(item)
        or character:getPrimaryHandItem() == item
        or character:getSecondaryHandItem() == item
end

local function isSheet(item)
    return item ~= nil and item:getFullType() == "Base.Sheet"
end

local function isRippableCotton(item)
    return item ~= nil
        and item:IsClothing()
        and item:getFabricType() == "Cotton"
end

local function firstMatching(container, predicate)
    if container == nil then
        return nil
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if predicate(item) then
            return item
        end
    end
    return nil
end

local function firstMatchingRecursive(container, predicate)
    local direct = firstMatching(container, predicate)
    if direct ~= nil then
        return direct
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:IsInventoryContainer() then
            local nested = firstMatchingRecursive(item:getInventory(), predicate)
            if nested ~= nil then
                return nested
            end
        end
    end
    return nil
end

local function addOwnedContainers(container, containers)
    containers:add(container)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:IsInventoryContainer() then
            addOwnedContainers(item:getInventory(), containers)
        end
    end
end

local function worldContainersNear(character, radius)
    local found = {}
    local square = character:getCurrentSquare()
    if square == nil or getCell() == nil then
        return found
    end
    for scanRadius = 0, radius do
        for dx = -scanRadius, scanRadius do
            for dy = -scanRadius, scanRadius do
                if math.max(math.abs(dx), math.abs(dy)) == scanRadius then
                    local candidate = getCell():getGridSquare(
                        square:getX() + dx,
                        square:getY() + dy,
                        square:getZ()
                    )
                    if candidate ~= nil then
                        local objects = candidate:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local container = object:getContainerByIndex(containerIndex)
                                if container ~= nil and container:isExistYet() then
                                    table.insert(found, {
                                        container = container,
                                        object = object,
                                        square = candidate,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return found
end

local function findWorldSource(character, radius)
    local containers = worldContainersNear(character, radius)

    -- Search the world before sacrificing anything the survivor already owns.
    for _, source in ipairs(containers) do
        local item = findTreatment(source.container)
        if item ~= nil then
            source.item = item
            source.kind = "world_treatment"
            return source
        end
    end
    for _, source in ipairs(containers) do
        local item = firstMatching(source.container, isSheet)
        if item ~= nil then
            source.item = item
            source.kind = "world_sheet"
            return source
        end
    end
    for _, source in ipairs(containers) do
        local item = firstMatching(source.container, isRippableCotton)
        if item ~= nil then
            source.item = item
            source.kind = "world_spare_clothing"
            return source
        end
    end
    return nil
end

local function queueCraft(character, recipeName, selectedItem, admit)
    local recipe = getScriptManager():getCraftRecipe(recipeName)
    if recipe == nil then
        return false, "recipe_missing=" .. tostring(recipeName)
    end
    local containers = ArrayList.new()
    addOwnedContainers(character:getInventory(), containers)
    local logic = HandcraftLogic.new(character, nil, nil)
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, selectedItem)
    if not logic:canPerformCurrentRecipe() then
        return false, "recipe_unavailable=" .. tostring(recipeName)
    end
    local action = ISHandcraftAction.FromLogic(logic)
    if action == nil then
        return false, "action_creation_failed=" .. tostring(recipeName)
    end
    -- The registered queue returned by add is native admission evidence even
    -- when begin completes synchronously. A constructed action alone is not.
    action.knoxMedicalSource = selectedItem
    if admit ~= nil then
        local accepted, reason = admit(character, action)
        if accepted ~= action then return false, reason or "craft_queue_refused" end
    else
        local queue = ISTimedActionQueue.add(action)
        if queue == nil or ISTimedActionQueue.queues == nil
            or queue ~= ISTimedActionQueue.queues[character] then
            return false, "craft_queue_refused"
        end
    end
    logic:startCraftAction(action)
    return true, action
end

function MedicalSupplies.plan(character, radius)
    if character == nil then
        return { kind = "invalid", reason = "missing_character" }
    end
    local inventory = character:getInventory()
    local treatment = findTreatment(inventory)
    if treatment ~= nil then
        return { kind = "use_treatment", item = treatment }
    end

    local worldSource = findWorldSource(character, radius or 8)
    if worldSource ~= nil then
        return worldSource
    end

    local sheet = firstMatchingRecursive(inventory, function(item)
        return isSheet(item) and not isProtectedPersonalItem(character, item)
    end)
    if sheet ~= nil then
        return { kind = "rip_owned_sheet", item = sheet, recipe = "RipSheets" }
    end

    local spareClothing = firstMatchingRecursive(inventory, function(item)
        return isRippableCotton(item) and not isProtectedPersonalItem(character, item)
    end)
    if spareClothing ~= nil then
        return {
            kind = "rip_owned_spare_clothing",
            item = spareClothing,
            recipe = "RipClothing",
        }
    end
    return { kind = "search_world", reason = "no_safe_treatment_source" }
end

function MedicalSupplies.canImprovise(character, plan)
    if plan == nil
        or (plan.kind ~= "rip_owned_sheet" and plan.kind ~= "rip_owned_spare_clothing") then
        return false, "plan_not_craftable"
    end
    if isProtectedPersonalItem(character, plan.item) then
        return false, "source_became_protected"
    end
    return true
end

function MedicalSupplies.queueImprovisation(character, plan, admit)
    local allowed, reason = MedicalSupplies.canImprovise(character, plan)
    if not allowed then return false, reason end
    return queueCraft(character, plan.recipe, plan.item, admit)
end

function MedicalSupplies.findTreatment(character)
    return character ~= nil and findTreatment(character:getInventory()) or nil
end
