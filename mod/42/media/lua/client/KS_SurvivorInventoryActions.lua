require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"

local InventoryActions = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = InventoryActions

local KnoxNpcInventoryTransferAction = ISInventoryTransferAction:derive(
    "KnoxNpcInventoryTransferAction"
)

local KnoxNpcSearchContainerAction = ISBaseTimedAction:derive(
    "KnoxNpcSearchContainerAction"
)

function KnoxNpcSearchContainerAction:isValid()
    if self.knoxSearchGuard ~= nil then
        local ok, allowed = pcall(self.knoxSearchGuard, self)
        if not ok or allowed ~= true then return false end
    end
    return self.container ~= nil and self.container:isExistYet()
end

function KnoxNpcSearchContainerAction:waitToStart()
    local parent = self.container:getParent()
    if parent ~= nil then
        self.character:faceThisObject(parent)
    end
    return self.character:shouldBeTurning()
end

function KnoxNpcSearchContainerAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function KnoxNpcSearchContainerAction:start()
    self:setActionAnim("Loot")
    self:setAnimVariable("LootPosition", "")
    if self.container:getContainerPosition() then
        self:setAnimVariable("LootPosition", self.container:getContainerPosition())
    end
    self:setOverrideHandModels(nil, nil)
    self.character:reportEvent("EventLootItem")
    self.knoxSearchAnimationRequested = true
end

function KnoxNpcSearchContainerAction:perform()
    if not self:isValid() then
        ISBaseTimedAction.perform(self)
        return
    end
    self.knoxSearchCompleted = true
    ISBaseTimedAction.perform(self)
end

function KnoxNpcSearchContainerAction:new(character, container, duration)
    local action = ISBaseTimedAction.new(self, character)
    action.container = container
    action.maxTime = duration or 90
    action.stopOnWalk = true
    action.stopOnRun = true
    return action
end

-- The stock action drives the selected local player's loot panel. An off-slot
-- IsoPlayer has no panel, so preserve inventory rules, animation, and sound
-- while omitting only that UI reference.
function KnoxNpcInventoryTransferAction:startActionAnim()
    ISInventoryTransferAction.startActionAnim(self)
    self.knoxLootAnimationRequested = true
    self.selectedContainer = nil
end

function KnoxNpcInventoryTransferAction:start()
    ISInventoryTransferAction.start(self)
    self.knoxRummageSoundStarted = self.loopSound ~= nil
end

function KnoxNpcInventoryTransferAction:isValid()
    if self.knoxTransferGuard ~= nil then
        local ok, allowed = pcall(self.knoxTransferGuard, self, self.item)
        if not ok or allowed ~= true then return false end
    end
    local events = rawget(_G, "KnoxEventRuntime")
    if self.knoxEventContext ~= nil and (events == nil or not events.lootTransferAllowed(
        self.knoxEventContext, self.character, self.srcContainer, self.destContainer)) then return false end
    -- Native validity decides everything including real container capacity:
    -- assigned storage fills like ordinary Project Zomboid containers, and
    -- full shelves simply reject so deposits overflow elsewhere.
    return ISInventoryTransferAction.isValid(self)
end

function KnoxNpcInventoryTransferAction:canMergeAction(action)
    if action == nil then return false end
    -- A plan's transient permission applies to one exact item/destination.
    -- Native batching must not absorb an action with a different permission.
    if self.knoxTransferGuard ~= nil or action.knoxTransferGuard ~= nil then return false end
    local first, other = self.knoxEventContext, action.knoxEventContext
    if (first == nil) ~= (other == nil) then return false end
    if first ~= nil and (first.eventId ~= other.eventId or first.memberId ~= other.memberId
        or first.x ~= other.x or first.y ~= other.y or first.z ~= other.z) then return false end
    return ISInventoryTransferAction.canMergeAction(self, action)
end

function KnoxNpcInventoryTransferAction:transferItem(item)
    if self.knoxTransferGuard ~= nil then
        local ok, allowed = pcall(self.knoxTransferGuard, self, item)
        if not ok or allowed ~= true then return end
    end
    local events, context = rawget(_G, "KnoxEventRuntime"), self.knoxEventContext
    if context ~= nil and (events == nil or not events.lootTransferAllowed(
        context, self.character, self.srcContainer, self.destContainer)) then return end
    local wasPresent = context ~= nil and self.srcContainer:contains(item)
    -- Exact 42.20.3 SP perform() calls this once per actual batched item. Native
    -- transfer can replace self.item or put it on the floor when capacity changes.
    ISInventoryTransferAction.transferItem(self, item)
    if context ~= nil then
        events.observeLootTransfer(context, self.character, self.srcContainer, self.destContainer,
            item, self.item, wasPresent)
    end
end

function KnoxNpcInventoryTransferAction:new(character, item, source, destination, duration)
    return ISInventoryTransferAction.new(
        self,
        character,
        item,
        source,
        destination,
        duration
    )
end

-- Native admission returns the character's registered queue, including when
-- begin completes synchronously. Item receipt remains the caller's separate
-- contract. Preserve native exceptions for existing controller error cleanup.
local function admitAction(character, action, kind, result)
    local queue = ISTimedActionQueue.add(action)
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, kind .. "_queue_refused"
    end
    return action, result
end

function InventoryActions.queueTransfer(character, item, source, destination, duration, guard)
    if character == nil or item == nil or source == nil or destination == nil then
        return nil, "missing_transfer_input"
    end
    local action = KnoxNpcInventoryTransferAction:new(
        character,
        item,
        source,
        destination,
        duration
    )
    -- Install before admission: vanilla can start/complete synchronously.
    action.knoxTransferGuard = guard
    local events = rawget(_G, "KnoxEventRuntime")
    if events ~= nil then action.knoxEventContext = events.captureLootContext(character, source, destination) end
    return admitAction(character, action, "transfer", "queued")
end

function InventoryActions.queueSearch(character, container, duration, guard)
    if character == nil or container == nil then
        return nil, "missing_search_input"
    end
    local action = KnoxNpcSearchContainerAction:new(character, container, duration)
    action.knoxSearchGuard = guard
    return admitAction(character, action, "search", "queued_search")
end

function InventoryActions.queueDrop(character, item, guard)
    if character == nil or item == nil or character:getCurrentSquare() == nil
        or character:getVehicle() ~= nil then return nil, "drop_unavailable" end
    -- Match ISInventoryPage.GetFloorContainer without borrowing a local player's
    -- indexed UI container. Native transfer places the actual item in the world.
    local floor = ItemContainer.new("floor", nil, nil)
    floor:setExplored(true)
    return InventoryActions.queueTransfer(character, item, item:getContainer(), floor, nil, guard)
end
