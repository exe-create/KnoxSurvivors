require "ISUI/ISContextMenu"
require "ISUI/ISInventoryPane"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "KS_CompanionService"
require "KS_CompanionInventory"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"
require "KS_BaseWoodcutting"

local InventoryMenu = rawget(_G, "KnoxCompanionInventoryMenu") or {}
_G.KnoxCompanionInventoryMenu = InventoryMenu

local GIVE_DISTANCE_SQUARED = 16

local function nearbyCompanions(player)
    local result = {}
    if player == nil or player:getCurrentSquare() == nil then return result end
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(player) or {}) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local square = character ~= nil and character:getCurrentSquare() or nil
        if square ~= nil and square:getZ() == player:getZ() then
            local dx, dy = character:getX() - player:getX(), character:getY() - player:getY()
            if dx * dx + dy * dy <= GIVE_DISTANCE_SQUARED then
                result[#result + 1] = { id = id, character = character }
            end
        end
    end
    return result
end

local function displayName(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local identity = persistence ~= nil and persistence.getSurvivorIdentity ~= nil
        and persistence.getSurvivorIdentity(id) or nil
    if identity ~= nil then
        local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
        if name ~= " " then return name end
    end
    return tostring(id)
end

function InventoryMenu.give(_, player, target, survivorId, items)
    local playerNum = player ~= nil and player:getPlayerNum() or nil
    if playerNum == nil or not KnoxCompanionInventory.canManage(playerNum, survivorId, target) then
        KnoxActivityFeed.event("Cannot give items: stay close to one of your available survivors.")
        return
    end
    if player == nil or target == nil or target:getCurrentSquare() == nil then return end
    local destination = target:getInventory()
    local moved = 0
    for _, item in ipairs(ISInventoryPane.getActualItems(items) or {}) do
        local source = item ~= nil and item:getContainer() or nil
        if source ~= nil and source:contains(item) then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(
                player, item, source, destination
            )
            if action ~= nil then
                ISTimedActionQueue.add(action)
                moved = moved + 1
            end
        end
    end
    if moved > 0 then
        KnoxActivityFeed.event("Giving " .. tostring(moved) .. " item(s) to "
            .. displayName(survivorId) .. ".")
    end
end

local function selectedLog(items)
    for _, item in ipairs(ISInventoryPane.getActualItems(items) or {}) do
        if item ~= nil and item.getFullType ~= nil
            and item:getFullType() == "Base.Log" then
            return true
        end
    end
    return false
end

local function canSawLogs(character)
    return character ~= nil
        and KnoxBaseWoodcutting.findLog(character) ~= nil
        and KnoxBaseWoodcutting.findSaw(character) ~= nil
end

function InventoryMenu.sawLogs(_, character, survivorId, playerNum)
    if playerNum == nil or not KnoxCompanionInventory.canManage(playerNum, survivorId, character) then
        KnoxActivityFeed.event("Cannot give this work order: stay close to one of your available survivors.")
        return
    end
    if not canSawLogs(character) then
        KnoxActivityFeed.event(displayName(survivorId) .. " is missing a saw or log.")
        return
    end
    local action, result = KnoxBaseWoodcutting.queueSawLogs(character)
    if action == nil then
        KnoxActivityFeed.event(displayName(survivorId) .. " cannot saw logs: "
            .. tostring(result or "recipe_unavailable") .. ".")
        return
    end
    KnoxActivityFeed.event(displayName(survivorId) .. " is sawing logs.")
end

local function addSawLogsOptions(context, player, items, companions)
    if not selectedLog(items) then return end
    local actors, seen = {}, {}

    -- When the clicked log belongs to the open survivor pane, that survivor is
    -- the actor. Never redirect this to the local player's timed-action queue.
    for _, item in ipairs(ISInventoryPane.getActualItems(items) or {}) do
        local owner, survivorId = nil, nil
        if KnoxCompanionInventory.getSurvivorForItem ~= nil then
            owner, survivorId = KnoxCompanionInventory.getSurvivorForItem(item, player:getPlayerNum())
        end
        if owner ~= nil and canSawLogs(owner) then
            survivorId = KnoxSurvivorRuntime.idForCharacter(owner)
            local key = tostring(survivorId or owner)
            if not seen[key] then
                seen[key] = true
                actors[#actors + 1] = { character = owner, id = survivorId }
            end
        end
    end

    -- A log in the player's inventory may still be an explicit order for a
    -- nearby survivor, but only a survivor carrying both ingredients is offered.
    for _, entry in ipairs(companions or {}) do
        if canSawLogs(entry.character) then
            local key = tostring(entry.id)
            if not seen[key] then
                seen[key] = true
                actors[#actors + 1] = entry
            end
        end
    end
    if #actors == 0 then return end

    local root = context:addOption("Saw Logs", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    for _, entry in ipairs(actors) do
        menu:addOption("Have " .. displayName(entry.id) .. " saw logs",
            InventoryMenu, InventoryMenu.sawLogs, entry.character, entry.id, player:getPlayerNum())
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local companions = nearbyCompanions(player)
    if player == nil or #(ISInventoryPane.getActualItems(items) or {}) == 0 then
        return
    end
    addSawLogsOptions(context, player, items, companions)
    if #companions == 0 then return end
    local root = context:addOption("Give to Companion", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    for _, entry in ipairs(companions) do
        menu:addOption(displayName(entry.id), InventoryMenu, InventoryMenu.give,
            player, entry.character, entry.id, items)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

return InventoryMenu
