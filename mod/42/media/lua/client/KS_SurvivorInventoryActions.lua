require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISGrabItemAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "Entity/TimedActions/ISHandcraftAction"
require "Moveables/ISMoveablesAction"

local InventoryActions = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = InventoryActions

function InventoryActions.canTakeWorldStock(character, source, destination)
    if character==nil or source==nil or destination==nil then return false end
    if (destination~=character:getInventory() and not destination:isInCharacterInventory(character))
        or source:isInCharacterInventory(character) then return true end
    local parent=source:getParent()
    if parent~=nil and instanceof(parent,"IsoGameCharacter") then return true end
    local square=source:getSourceGrid()
    if square==nil then return true end -- personal handoffs have no world source
    local runtime=rawget(_G,"KnoxSurvivorRuntime")
    local looting=rawget(_G,"KnoxSurvivorLooting")
    local id=runtime~=nil and runtime.idForCharacter(character) or nil
    return looting~=nil and looting.canLootSquare(id,square)==true
end

local KnoxNpcInventoryTransferAction = ISInventoryTransferAction:derive(
    "KnoxNpcInventoryTransferAction"
)

-- One native world-object grab per action: never merge identity-sensitive work.
local KnoxNpcGrabWorldItemAction = ISGrabItemAction:derive("KnoxNpcGrabWorldItemAction")

function KnoxNpcGrabWorldItemAction:checkQueueList()
    self.queueList = {{ items = { self.item }, time = self.maxTime,
        type = self.item:getItem():getFullType() }}
end

local function grabAllowed(action, object)
    local ok, allowed = pcall(function()
        if object == nil or object ~= action.knoxWorldObject or action.item ~= object
            or action.character ~= action.knoxGrabCharacter
            or object:getSquare() ~= action.knoxWorldSquare
            or object:getItem() ~= action.knoxInventoryItem then return false end
        local square = action.knoxWorldSquare
        if square == nil or square:getWorldObjects() == nil
            or not square:getWorldObjects():contains(object) then return false end
        if action.knoxGrabGuard ~= nil
            and action.knoxGrabGuard(action, object, action.knoxInventoryItem, square) ~= true then
            return false
        end
        return true
    end)
    return ok and allowed == true
end

function KnoxNpcGrabWorldItemAction:isValid()
    if not grabAllowed(self, self.item) then return false end
    return ISGrabItemAction.isValid(self)
end

function KnoxNpcGrabWorldItemAction:transferItem(object)
    if not grabAllowed(self, object) then return end
    return ISGrabItemAction.transferItem(self, object)
end

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
    if not InventoryActions.canTakeWorldStock(self.character,self.srcContainer,self.destContainer) then return false end
    if self.knoxTransferGuard ~= nil then
        local ok, allowed = pcall(self.knoxTransferGuard, self, self.item)
        if not ok or allowed ~= true then return false end
    end
    local events = rawget(_G, "KnoxEventRuntime")
    if self.knoxEventContext ~= nil and (events == nil or not events.lootTransferAllowed(
        self.knoxEventContext, self.character, self.srcContainer, self.destContainer)) then return false end
    if self.knoxHandoverContext ~= nil and (events == nil or not events.handoverAllowed(
        self.knoxHandoverContext, self.character, self.srcContainer, self.destContainer)) then return false end
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
    -- A handover is one item to one named body; batching it would lose the id.
    if self.knoxHandoverContext ~= nil or action.knoxHandoverContext ~= nil then return false end
    local first, other = self.knoxEventContext, action.knoxEventContext
    if (first == nil) ~= (other == nil) then return false end
    if first ~= nil and (first.eventId ~= other.eventId or first.memberId ~= other.memberId
        or first.x ~= other.x or first.y ~= other.y or first.z ~= other.z) then return false end
    return ISInventoryTransferAction.canMergeAction(self, action)
end

function KnoxNpcInventoryTransferAction:transferItem(item)
    if not InventoryActions.canTakeWorldStock(self.character,self.srcContainer,self.destContainer) then return end
    if self.knoxTransferGuard ~= nil then
        local ok, allowed = pcall(self.knoxTransferGuard, self, item)
        if not ok or allowed ~= true then return end
    end
    local events, context = rawget(_G, "KnoxEventRuntime"), self.knoxEventContext
    if context ~= nil and (events == nil or not events.lootTransferAllowed(
        context, self.character, self.srcContainer, self.destContainer)) then return end
    local wasPresent = context ~= nil and self.srcContainer:contains(item)
    local handover = self.knoxHandoverContext
    local handoverPresent = handover ~= nil and self.srcContainer:contains(item)
    -- Exact 42.20.3 SP perform() calls this once per actual batched item. Native
    -- transfer can replace self.item or put it on the floor when capacity changes.
    ISInventoryTransferAction.transferItem(self, item)
    if context ~= nil then
        events.observeLootTransfer(context, self.character, self.srcContainer, self.destContainer,
            item, self.item, wasPresent)
    end
    -- The receipt for a paid raid is written here, after the item is really in
    -- their hands, not when the player clicks the menu.
    if handover ~= nil and events ~= nil then
        events.observeHandoverTransfer(handover, self.character, self.srcContainer,
            self.destContainer, item, self.item, handoverPresent)
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
-- contract. An admission raise is converted to this function's existing
-- <kind>_queue_refused refusal: the caller keeps the same release/retire and
-- named-failure contract without an exception unwind. Live 42.22.2 evidence
-- (f:5791/f:14326): the add path raised on return at
-- ISBaseTimedAction.begin:88 (ReturnValues.put:61 via LuaJavaInvoker.call:185).
-- The engine's own break dialog is not silenced here; root-cause attribution
-- waits on the ZombieBuddy-off discriminator boot.
local function admitAction(character, action, kind, result)
    local addOk, queue = pcall(ISTimedActionQueue.add, action)
    if not addOk then
        return nil, kind .. "_queue_refused"
    end
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, kind .. "_queue_refused"
    end
    return action, result
end

-- Execution uses carried containers; an optional read-only supply projection
-- lets the installed recipe select real nearby inputs before normal transfers.
function InventoryActions.craftPlan(character, recipeName, base, selectedItem, includeStorage, excludeContainer)
    local surfaceSquare
    local ok, logic, sourcePolicies = pcall(function()
        local recipe = getScriptManager():getCraftRecipe(recipeName)
        if recipe == nil or not character:isRecipeKnown(recipe, true)
            or not recipe:characterHasRequiredSkills(character) then return nil end
        local surface
        if recipe:isAnySurfaceCraft() then
            local origin = character:getCurrentSquare()
            local cell = getCell ~= nil and getCell() or nil
            if origin == nil or cell == nil then return nil end
            for x = origin:getX() - 1, origin:getX() + 1 do
                for y = origin:getY() - 1, origin:getY() + 1 do
                    local square = cell:getGridSquare(x, y, origin:getZ())
                    if square ~= nil and (base == nil or KnoxBaseManager.containsSquare(base, square)) then
                        local objects = square:getObjects()
                        for i = 0, objects:size() - 1 do
                            local object = objects:get(i)
                            if surface == nil and character:canUseAsGenericCraftingSurface(object) then
                                surface, surfaceSquare = object, square
                            end
                        end
                    end
                end
            end
            if surface == nil then return nil end
        end
        local containers, seen, policies = ArrayList.new(), {}, {}
        local function collect(container, depth, policy)
            if container == nil or seen[container] or depth > 4 then return end
            seen[container] = true
            containers:add(container)
            if policy ~= nil then policies[container] = policy end
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item:IsInventoryContainer() then collect(item:getInventory(), depth + 1, policy) end
            end
        end
        collect(character:getInventory(), 0)
        if includeStorage == true then
            local storage, origin = rawget(_G, "KnoxBaseStorage"), character:getCurrentSquare()
            if storage == nil or base == nil or origin == nil then return nil end
            -- Selection may see every loaded store in the base, including
            -- another floor of the same site. The projection is read-only: a
            -- remote container can name its exact input, but the task movement
            -- owner must walk there before the ordinary nearby permission
            -- admits any transfer.
            for _, policy in ipairs(storage.operationalPolicies(base)) do
                local resolved = storage.resolvePolicy(policy, true)
                local square = resolved ~= nil and resolved.square or nil
                if square ~= nil
                    and KnoxBaseManager.containsSquare(base, square)
                    and (excludeContainer == nil or resolved.container ~= excludeContainer) then
                    collect(resolved.container, 0, policy)
                end
            end
        end
        local candidate = HandcraftLogic.new(character, nil, surface)
        candidate:setContainers(containers)
        candidate:setRecipeFromContextClick(recipe, selectedItem)
        if (recipe:isAnySurfaceCraft() and not candidate:isCharacterInRangeOfWorkbench())
            or not candidate:canPerformCurrentRecipe() then return nil end
        return candidate, policies
    end)
    return ok and logic or nil, ok and sourcePolicies or nil, ok and surfaceSquare or nil
end

-- Permission alone, independent of which floor the resident stands on: base
-- membership, looting access, a real transferable exact item and the live
-- storage task check. Every retrieval path below uses this same gate.
local function supplySourceAccessible(base, character, transfer)
    local square = transfer.source.square
    local runtime, looting = rawget(_G, "KnoxSurvivorRuntime"), rawget(_G, "KnoxSurvivorLooting")
    local id = runtime ~= nil and runtime.idForCharacter ~= nil and runtime.idForCharacter(character) or nil
    return square ~= nil and KnoxBaseManager.containsSquare(base, square) and id ~= nil
        and looting ~= nil and looting.canLootSquare(id, square) == true
        and InventoryActions.canTakeWorldStock(character, transfer.source.container, character:getInventory())
        and KnoxBaseStorage.taskSupplyStillAvailable(base, transfer) == true
end

local function supplySourcePermitted(base, character, transfer, nearby)
    local origin, square = character:getCurrentSquare(), transfer.source.square
    return origin ~= nil and square ~= nil and origin:getZ() == square:getZ()
        and (nearby ~= true or (square:getX() - origin:getX())^2
            + (square:getY() - origin:getY())^2 <= 2)
        and supplySourceAccessible(base, character, transfer)
end

-- A source on another loaded floor of the same site: permission still has to
-- admit the exact item, and the existing approach owner must name a standable
-- neighbouring square on that floor inside the base. Reaching it stays the
-- movement owner's job, so no destination is faked and nothing moves early.
local function crossFloorApproach(base, character, transfer)
    local storage = rawget(_G, "KnoxBaseStorage")
    local origin = character:getCurrentSquare()
    local square = transfer.source.square
    if storage == nil or origin == nil or square == nil or square:getZ() == origin:getZ()
        or not supplySourceAccessible(base, character, transfer) then return nil end
    local approach = storage.approachSquare(transfer, character)
    if approach == nil or approach:getZ() ~= square:getZ()
        or not KnoxBaseManager.containsSquare(base, approach)
        or (approach:getX() - square:getX())^2
            + (approach:getY() - square:getY())^2 > 2 then return nil end
    return approach
end

function InventoryActions.craftSupplyStillAvailable(base, character, transfer)
    local ok, allowed = pcall(supplySourcePermitted, base, character, transfer, true)
    return ok and allowed == true
end

-- A distant in-base source is not transferable yet; it only authorizes the
-- task's existing movement owner to walk there, after which the same nearby
-- storage, access and filter checks must pass again before any transfer.
function InventoryActions.craftSupplyReachable(base, character, transfer)
    local ok, allowed = pcall(supplySourcePermitted, base, character, transfer, false)
    return ok and allowed == true
end

-- Classify one native selection: first nearby transfer, first distant
-- reachable transfer, and first stored input we may not retrieve at all.
local function classifySupplyInputs(logic, policies, character, base)
    if logic == nil or policies == nil then return nil end
    local selected = logic:getRecipeData():getAllInputItems()
    if selected == nil or selected:size() < 1 or selected:size() > 512 then return nil end
    local near, distant, cross, blocked
    for i = 0, selected:size() - 1 do
        local item = selected:get(i)
        local source = item:getContainer()
        if source == nil then return nil end
        if not source:isInCharacterInventory(character) then
            local policy = policies[source]
            if policy == nil then return nil end
            local resolved = KnoxBaseStorage.resolvePolicy(policy, true)
            local transfer = { item = item, itemType = item:getFullType(), sourcePolicy = policy,
                source = { container = source, square = resolved ~= nil and resolved.square,
                    object = resolved ~= nil and resolved.object } }
            if InventoryActions.craftSupplyStillAvailable(base, character, transfer) then
                near = near or transfer
            elseif InventoryActions.craftSupplyReachable(base, character, transfer) then
                distant = distant or transfer
            else
                local approach = crossFloorApproach(base, character, transfer)
                if approach ~= nil then
                    transfer.approach = approach
                    cross = cross or transfer
                else
                    -- Name the actual wall the trip hit: a source the
                    -- settlement will not release, or one on a floor the
                    -- approach owner cannot stand on at all.
                    transfer.reason = "recipe_input_forbidden"
                    local origin = character:getCurrentSquare()
                    if origin ~= nil and transfer.source.square ~= nil
                        and transfer.source.square:getZ() ~= origin:getZ()
                        and supplySourceAccessible(base, character, transfer) then
                        transfer.reason = "recipe_input_unreachable"
                    end
                    blocked = blocked or transfer
                end
            end
        end
    end
    return near, distant, cross, blocked
end

function InventoryActions.craftSupplyTransfer(character, recipeName, base)
    local ok, result = pcall(function()
        local logic, policies, surfaceSquare = InventoryActions.craftPlan(
            character, recipeName, base, nil, true)
        if logic == nil or policies == nil then return nil end
        local near, distant, cross, blocked = classifySupplyInputs(logic, policies, character, base)
        if near == nil and distant == nil and cross == nil and blocked == nil then return nil end
        if blocked ~= nil then
            -- The storage projection is a hint only, and this exact item may
            -- not be taken. Ask the installed recipe once more without that
            -- container: the recipe chooses any valid alternative itself, so
            -- nothing is swapped behind its back. Anything still blocked is a
            -- named refusal, never a silent substitution.
            local retryLogic, retryPolicies, retrySurface = InventoryActions.craftPlan(
                character, recipeName, base, nil, true, blocked.source.container)
            local retryNear, retryDistant, retryCross, retryBlocked
            if retryLogic ~= nil and retryPolicies ~= nil then
                retryNear, retryDistant, retryCross, retryBlocked = classifySupplyInputs(
                    retryLogic, retryPolicies, character, base)
            end
            if retryBlocked == nil and (retryNear ~= nil or retryDistant ~= nil
                or retryCross ~= nil) then
                near, distant, cross, surfaceSquare = retryNear, retryDistant, retryCross,
                    retrySurface
            else
                return { phase = "craft_blocked", itemType = blocked.itemType,
                    reason = blocked.reason or "recipe_input_forbidden" }
            end
        end
        if near ~= nil then near.phase = "craft_supply" return near end
        if distant == nil and cross ~= nil then
            -- Another loaded floor of the same site: the approach owner already
            -- named a standable square there, so the task movement owner walks.
            cross.phase, cross.approach, cross.surface = "craft_supply_move",
                cross.approach, surfaceSquare
            cross.crossFloor = true
            return cross
        end
        if distant == nil then return nil end
        -- The installed recipe named this exact item. Walking there uses the
        -- same storage approach the task movement owner already obeys; no
        -- actor coordinate is moved to make the recipe valid.
        local approach = KnoxBaseStorage.approachSquare(distant, character)
        if approach == nil or not KnoxBaseManager.containsSquare(base, approach)
            or approach:getZ() ~= distant.source.square:getZ() then return nil end
        distant.phase, distant.approach, distant.surface
            = "craft_supply_move", approach, surfaceSquare
        return distant
    end)
    return ok and result or nil
end

-- The return leg of a distant ingredient trip. The work surface is the one the
-- installed recipe selected at plan time; walking back uses the same free-tile
-- finder as storage approach instead of a synthetic character position.
function InventoryActions.craftSurfaceApproach(surfaceSquare, character, base)
    local ok, approach = pcall(function()
        local origin = character ~= nil and character:getCurrentSquare() or nil
        if surfaceSquare == nil or origin == nil or base == nil
            or not KnoxBaseManager.containsSquare(base, surfaceSquare) then return nil end
        local floor = surfaceSquare:getZ()
        if origin:getZ() == floor
            and (surfaceSquare:getX() - origin:getX())^2
                + (surfaceSquare:getY() - origin:getY())^2 <= 2 then return origin end
        -- The surface may be one floor away after a cross-floor ingredient trip;
        -- the approach owner names a standable square on the surface's own floor
        -- and the movement owner routes back across the stairs.
        local found = AdjacentFreeTileFinder ~= nil
            and AdjacentFreeTileFinder.Find(surfaceSquare, character) or nil
        if found == nil or not KnoxBaseManager.containsSquare(base, found)
            or found:getZ() ~= floor then return nil end
        return found
    end)
    return ok and approach or nil
end

function InventoryActions.queueCraft(character, recipeName, guard, base, selectedItem)
    if guard ~= nil and guard() ~= true then return nil, "craft_permission_lost" end
    local logic = InventoryActions.craftPlan(character, recipeName, base, selectedItem)
    if logic == nil then return nil, "recipe_unavailable" end
    local action = ISHandcraftAction.FromLogic(logic)
    if action == nil then return nil, "craft_action_unavailable" end
    local valid = action.isValid
    action.isValid = function(self)
        return (guard == nil or guard() == true) and valid(self)
            and (not self.craftRecipe:isAnySurfaceCraft() or (self.isoObject ~= nil
                and self.isoObject:getObjectIndex() >= 0
                and character:canUseAsGenericCraftingSurface(self.isoObject)))
    end
    local admitted, reason = admitAction(character, action, "craft", "queued")
    if admitted == nil then return nil, reason end
    logic:startCraftAction(action)
    return action, reason
end

function InventoryActions.queueBedPlacement(character, target, guard)
    if guard() ~= true or target == nil or target.item:getContainer() ~= character:getInventory()
        or not target.props:canPlaceMoveable(character, target.square, target.item) then
        return nil, "bed_placement_unavailable"
    end
    local action = ISMoveablesAction:new(character, target.square, "place",
        target.item:getWorldSprite(), nil, target.props.facing, target.item, nil)
    local valid = action.isValid
    action.isValid = function(self) return guard() == true and valid(self) end
    return admitAction(character, action, "bed_placement", "queued")
end

-- Native completion alone is not a receipt. Read only actual created outputs
-- still present in a real container or as a loose world item.
function InventoryActions.craftedOutput(action, fullType)
    local ok, result = pcall(function()
        if action == nil or action.logic == nil then return nil end
        local items = ArrayList.new()
        action.logic:getCreatedOutputItems(items)
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getFullType() == fullType
                and (item:getContainer() ~= nil or item:getWorldItem() ~= nil) then return item end
        end
    end)
    return ok and result or nil
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
    if events ~= nil then
        action.knoxEventContext = events.captureLootContext(character, source, destination)
        if action.knoxEventContext == nil and events.captureHandoverContext ~= nil then
            action.knoxHandoverContext = events.captureHandoverContext(character, source, destination)
        end
    end
    return admitAction(character, action, "transfer", "queued")
end

-- PROPERTY GATE (owner: this pickup action)
-- A world item the player protected is not free stock for any resident. The
-- refusal lives in the one pick-up owner so every caller (floor haul, bed
-- preparation, anything later) obeys the same rule instead of each caller
-- filtering candidates and hoping. A take never changes the marker.
function InventoryActions.propertyRefusal(item, character)
    if item == nil then return nil end
    local ok, favourite = pcall(function() return item:isFavorite() end)
    if ok and favourite == true then return "property_favourite_owned" end
    return nil
end

function InventoryActions.queueGrab(character, worldObject, guard, duration)
    if character == nil or worldObject == nil then return nil, "missing_grab_input" end
    local ok, item, square = pcall(function()
        return worldObject:getItem(), worldObject:getSquare()
    end)
    if not ok or item == nil or square == nil then return nil, "grab_unavailable" end
    local refusal = InventoryActions.propertyRefusal(item, character)
    if refusal ~= nil then return nil, refusal end
    local action = ISGrabItemAction.new(KnoxNpcGrabWorldItemAction, character, worldObject, duration or 50)
    action.knoxGrabCharacter, action.knoxWorldObject = character, worldObject
    action.knoxInventoryItem, action.knoxWorldSquare = item, square
    action.knoxGrabGuard = guard
    return admitAction(character, action, "grab", "queued")
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
