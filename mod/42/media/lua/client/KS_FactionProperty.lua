require "TimedActions/ISInventoryTransferAction"
require "KS_Persistence"
require "KS_ActivityFeed"

local Property = rawget(_G, "KnoxFactionProperty") or {}
_G.KnoxFactionProperty = Property

local function worldAge()
    local time = getGameTime ~= nil and getGameTime() or nil
    return time ~= nil and time:getWorldAgeHours() or 0
end

local function localPlayerId(character)
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, (tonumber(count) or 1) - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            return KnoxPersistence.ensurePlayerId(player)
        end
    end
    return nil
end

local function theftContext(action, playerId)
    if action == nil or action.character == nil or action.srcContainer == nil
        or action.destContainer == nil then return nil end
    if playerId == nil or action.destContainer.isInCharacterInventory == nil
        or not action.destContainer:isInCharacterInventory(action.character) then
        return nil
    end
    local parent = action.srcContainer.getParent ~= nil and action.srcContainer:getParent() or nil
    local square = nil
    if parent ~= nil and parent.getSquare ~= nil then
        local ok, result = pcall(function() return parent:getSquare() end)
        square = ok and result or nil
    end
    if square == nil then return nil end
    local base = KnoxPersistence.getBaseAtSquare(
        square:getX(), square:getY(), square:getZ(), "faction"
    )
    return base ~= nil and { playerId = playerId, baseId = base.id } or nil
end

-- A transferred bag carries its contents into the same explicit allocation.
-- Native inventories are trees; bound malformed/cyclic containers defensively.
local function clearCommunalAllocation(item, seen, depth)
    if item == nil or seen[item] or depth > 32 then return end
    seen[item] = true
    if item.getModData ~= nil then
        local ok, data = pcall(function() return item:getModData() end)
        if ok and data ~= nil then data.KnoxBaseProvision = nil end
    end
    local ok, inventory = pcall(function() return item:getInventory() end)
    if not ok or inventory == nil then return end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        clearCommunalAllocation(items:get(index), seen, depth + 1)
    end
end

-- Build 42 performs authoritative inventory transfers locally in singleplayer.
-- Multiplayer completion is server-owned, so do not create a client-only
-- diplomacy change from a packet that may still be rejected by the server.
if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.transferItem ~= nil then
    Property._nativeTransferItem = Property._nativeTransferItem or ISInventoryTransferAction.transferItem
    local nativeTransferItem = Property._nativeTransferItem
    function ISInventoryTransferAction:transferItem(item)
        local playerId = not (isClient ~= nil and isClient()) and localPlayerId(self.character) or nil
        local context = playerId ~= nil and theftContext(self, playerId) or nil
        local source, destination = self.srcContainer, self.destContainer
        local wasPresent = playerId ~= nil and item ~= nil and source ~= nil and source:contains(item)
        local result = nativeTransferItem(self, item)
        -- A failed transfer leaves the item in its source. Escalate only after
        -- the stock action really completed, including batched transfers.
        local received = self.item or item
        if wasPresent and not source:contains(item) and received ~= nil
            and destination:contains(received) then
            -- An explicit player allocation supersedes an earlier base withdrawal.
            -- Clear only on a native receipt, never on refusal or a repeated callback.
            clearCommunalAllocation(received, {}, 0)
            if context == nil then return result end
            local relation, status = KnoxPersistence.recordPlayerFactionTheft(
                context.playerId, context.baseId, worldAge()
            )
            if relation ~= nil and status == "hostile" then
                KnoxActivityFeed.event("You took supplies from an NPC faction base. They are now hostile.")
            end
        end
        return result
    end
end

return Property
