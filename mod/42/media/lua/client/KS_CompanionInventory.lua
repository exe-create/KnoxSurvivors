-- Companion inventory deliberately uses the same player/loot pages that Project
-- Zomboid uses for nearby containers. That keeps drag/drop, transfer actions,
-- item context menus, and bag handling owned by the base game.
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISClothingExtraAction"
require "TimedActions/ISWearClothing"
require "KS_SurvivorRuntime"
require "KS_Persistence"

local CompanionInventory = rawget(_G, "KnoxCompanionInventory") or {}
_G.KnoxCompanionInventory = CompanionInventory

local MAX_DISTANCE_SQUARED = 16

-- Active survivor per playerNum whose inventory is currently exposed in the
-- vanilla loot window. Kept so OnRefreshInventoryWindowContainers can re-inject
-- the survivor's ItemContainer (and its equipped bags) after vanilla rebuilds the
-- button list. Without this the survivor container disappears on the next
-- dirtyUI / direction change because it is not a world container.
local active = CompanionInventory._active or {}
CompanionInventory._active = active

local function nearby(player, character)
    if player == nil or character == nil or player:getCurrentSquare() == nil
        or character:getCurrentSquare() == nil or player:getZ() ~= character:getZ() then
        return false
    end
    local dx, dy = player:getX() - character:getX(), player:getY() - character:getY()
    return dx * dx + dy * dy <= MAX_DISTANCE_SQUARED
end

-- Capture the real local-player lookup: vanilla menu rendering below temporarily
-- substitutes the survivor to draw native equipment controls.
local localPlayerFor = getSpecificPlayer
local exposedBodies = CompanionInventory._exposedBodies or {}
CompanionInventory._exposedBodies = exposedBodies
-- Remember only recognition of bodies exposed to a UI/action. Weak keys keep
-- stale callbacks rejectable after pane cleanup without retaining retired actors.
-- Runtime remains authoritative: canManage still requires its exact current body.
local knownBodies = CompanionInventory._knownBodies or setmetatable({}, {__mode="k"})
CompanionInventory._knownBodies = knownBodies

function CompanionInventory.canManage(playerNum, survivorId, expectedBody)
    local player = localPlayerFor(playerNum)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or player:isDead() then return false, "player_unavailable" end
    if character == nil or (expectedBody ~= nil and character ~= expectedBody)
        or character:isDead() or KnoxPersistence.isSurvivorAlive(survivorId) ~= true then
        return false, "survivor_unavailable"
    end
    if KnoxSurvivorRuntime.canInteract ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canInteract(survivorId)
        if not accepted then return false, reason or "survivor_unavailable" end
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    local ownerId = KnoxPersistence.ensurePlayerId(player)
    if affiliation == nil or affiliation.kind ~= "player" or affiliation.ownerId ~= ownerId then
        return false, "not_your_survivor"
    end
    if not nearby(player, character) then return false, "too_far_away" end
    return true, nil, character
end

-- Resolve through native container ownership and the existing runtime identity
-- lookup. This also recognizes stale callbacks after the loot pane was closed.
local function containerSurvivor(container)
    local current, seen = container, {}
    for depth = 1, 32 do
        if current == nil or seen[current] then break end
        seen[current] = true
        local ok, character = pcall(function() return current:getCharacter() end)
        if ok and character ~= nil and character.getPlayerNum ~= nil then
            local localOk, number = pcall(function() return character:getPlayerNum() end)
            if localOk and tonumber(number) ~= nil and number >= 0 and localPlayerFor(number) == character then
                return nil, nil
            end
        end
        local id = ok and character ~= nil and KnoxSurvivorRuntime.idForCharacter(character) or nil
        if id ~= nil then
            knownBodies[character] = id
            return character, id
        end
        if ok and character ~= nil and knownBodies[character] ~= nil then
            return character, knownBodies[character]
        end
        local found, bag = pcall(function() return current:getContainingItem() end)
        if not found or bag == nil then break end
        local parentOk, parent = pcall(function() return bag:getContainer() end)
        current = parentOk and parent or nil
    end
    return nil, nil
end

local function managementRefused()
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then
        feed.event("Inventory management is no longer available. Stay close to one of your available survivors.")
    end
end

-- Context-menu callbacks can outlive an inventory refresh. Do not queue a
-- native transfer for an item that has already been moved or consumed.
local function sourceHasItem(source, item)
    if source == nil or item == nil then return false end
    local ok, contains = pcall(function() return source:contains(item) end)
    return ok and contains == true
end

local function displayName(survivorId)
    local identity = KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    return name ~= "" and name or "Survivor"
end

local function setVisiblePage(page, visible)
    if page == nil then return end
    page:setVisible(visible)
    page.collapseCounter = 0
    if visible and page.isCollapsed then
        page.isCollapsed = false
        if page.clearMaxDrawHeight then page:clearMaxDrawHeight() end
        page.collapseCounter = -40
    end
end

local function onRefreshContainers(page, state)
    if state ~= "buttonsAdded" then return end
    if page == nil or page.onCharacter then return end
    local playerNum = page.player
    local survivorId = active[playerNum]
    if type(survivorId) ~= "string" or survivorId == "" then return end
    local player = getSpecificPlayer(playerNum)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not CompanionInventory.canManage(playerNum, survivorId, exposedBodies[playerNum]) then
        CompanionInventory.finish(playerNum)
        return
    end
    local inventory = character ~= nil and character:getInventory() or nil
    if inventory == nil then return end
    -- Ensure the survivor's main inventory is offered as a loot container.
    local hasMain = false
    for _, btn in ipairs(page.backpacks or {}) do
        if btn.inventory == inventory then hasMain = true; break end
    end
    if not hasMain then
        local title = displayName(survivorId) .. " - Inventory"
        local ok = pcall(function()
            page:addContainerButton(inventory, page.invbasic, title, title)
        end)
        if not ok then
            -- Fallback without texture if invbasic unavailable in this layout.
            pcall(function() page:addContainerButton(inventory, nil, title, title) end)
        end
    end
    -- Expose equipped bags so the loot window can switch bags exactly as the
    -- player inventory does. Vanilla player inventory only shows equipped
    -- containers; follow the same rule for the survivor.
    local items = inventory:getItems()
    if items ~= nil then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local itemInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
            if itemInv ~= nil then
                local shouldShow = false
                local ok, equipped = pcall(function() return character:isEquipped(item) end)
                if ok and equipped then shouldShow = true end
                if not shouldShow then
                    -- Also show containers that are not necessarily equipped but
                    -- still have an inventory (e.g. bag in main inventory). This
                    -- keeps drag/drop discoverable while staying close to vanilla
                    -- player behaviour. Clamp to Category == "Container" to avoid
                    -- polluting the button strip with non-bag items.
                    local catOk, cat = pcall(function() return item:getCategory() end)
                    if catOk and cat == "Container" then shouldShow = true end
                end
                if shouldShow then
                    local exists = false
                    for _, btn in ipairs(page.backpacks) do
                        if btn.inventory == itemInv then exists = true; break end
                    end
                    if not exists then
                        local texOk, tex = pcall(function() return item:getTex() end)
                        local nameOk, name = pcall(function() return item:getName() end)
                        pcall(function()
                            page:addContainerButton(itemInv, texOk and tex or nil, nameOk and name or "Bag", nameOk and name or "Bag")
                        end)
                    end
                end
            end
        end
    end
end

if Events ~= nil and Events.OnRefreshInventoryWindowContainers ~= nil then
    pcall(function() Events.OnRefreshInventoryWindowContainers.Remove(onRefreshContainers) end)
    Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
end

-- Vaulted patches so reload does not stack wrappers.
local function isSurvivorContainer(playerNum, container)
    local survivorId = active[playerNum]
    if type(survivorId) ~= "string" or survivorId == "" or container == nil then return false, nil, nil end
    local character = exposedBodies[playerNum] or KnoxSurvivorRuntime.getCharacter(survivorId)
    local inv = character ~= nil and character:getInventory() or nil
    if inv == nil then return false, nil, nil end
    if container == inv then return true, character, inv end
    local items = inv:getItems()
    if items ~= nil then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local itemInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
            if itemInv ~= nil and itemInv == container then
                return true, character, inv
            end
        end
    end
    return false, nil, nil
end

-- Render the survivor's inventory with the same equipped/worn line + red dot
-- that vanilla player inventory uses. Loot panes are normally onCharacter=false
-- and never set isEquipped, so the divider and icons are skipped. Temporarily
-- masquerade the loot pane as a character pane and provide the survivor as the
-- player object for just that refresh.
if ISInventoryPane ~= nil and ISInventoryPane.refreshContainer ~= nil then
    if CompanionInventory._origRefreshContainer == nil then
        CompanionInventory._origRefreshContainer = ISInventoryPane.refreshContainer
    end
    local origRefresh = CompanionInventory._origRefreshContainer
    ISInventoryPane.refreshContainer = function(self)
        local playerNum = self.player
        local survivorId = active[playerNum]
        if survivorId ~= nil and not CompanionInventory.canManage(playerNum, survivorId, exposedBodies[playerNum]) then
            local affected = isSurvivorContainer(playerNum, self.inventory)
            local owner, id = containerSurvivor(self.inventory)
            affected = affected or (id == survivorId and owner == exposedBodies[playerNum])
            CompanionInventory.finish(playerNum)
            if not affected then return origRefresh(self) end
            local floor = ISInventoryPage.GetFloorContainer ~= nil
                and ISInventoryPage.GetFloorContainer(playerNum) or nil
            if floor == nil then return end
            self.inventory = floor
            return origRefresh(self)
        end
        local character = type(survivorId) == "string" and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
        local survInv = character ~= nil and character:getInventory() or nil
        local isSurvivorPane = survInv ~= nil and self.inventory == survInv
        -- Also handle bag sub-containers of the survivor.
        if not isSurvivorPane and survInv ~= nil and self.inventory ~= nil then
            local ok, flag = pcall(function() return isSurvivorContainer(playerNum, self.inventory) end)
            if ok and flag then isSurvivorPane = true end
        end
        if isSurvivorPane and self.parent ~= nil then
            local savedOnCharacter = self.parent.onCharacter
            local savedGetSpecificPlayer = rawget(_G, "getSpecificPlayer")
            local savedGetPlayerHotbar = rawget(_G, "getPlayerHotbar")
            self.parent.onCharacter = true
            _G.getSpecificPlayer = function(p)
                if p == playerNum then return character end
                if savedGetSpecificPlayer ~= nil then return savedGetSpecificPlayer(p) end
                return nil
            end
            -- Survivor hotbar is not player hotbar; suppress it so only
            -- equipped/worn icons are used (matches live player visual).
            _G.getPlayerHotbar = function(p)
                if p == playerNum then return nil end
                if savedGetPlayerHotbar ~= nil then return savedGetPlayerHotbar(p) end
                return nil
            end
            local ok, result = pcall(function() return origRefresh(self) end)
            self.parent.onCharacter = savedOnCharacter
            _G.getSpecificPlayer = savedGetSpecificPlayer
            _G.getPlayerHotbar = savedGetPlayerHotbar
            if ok then return result else error(result, 0) end
        end
        return origRefresh(self)
    end
end

-- getContainers crashes for survivor shells because it does
-- getPlayerInventory(survivor:getPlayerNum()).inventoryPane on a non-local
-- player (-1). Wrap it once so any createMenu (including our survivor-
-- redirected one) falls back to the survivor's own ItemContainer.
if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.getContainers ~= nil then
    if CompanionInventory._origGetContainers == nil then
        CompanionInventory._origGetContainers = ISInventoryPaneContextMenu.getContainers
    end
    local origGetContainers = CompanionInventory._origGetContainers
    ISInventoryPaneContextMenu.getContainers = function(character)
        -- Survivor shells have playerNum -1 and no playerData; vanilla getContainers
        -- does getPlayerInventory(-1).inventoryPane → null deref (Kahlua RuntimeException
        -- not always pcall-catchable). Detect survivor first and bypass vanilla path.
        local isSurvivor = false
        for _, sid in pairs(active) do
            if KnoxSurvivorRuntime.getCharacter(sid) == character then isSurvivor = true; break end
        end
        if not isSurvivor then
            local ok, result = pcall(function() return origGetContainers(character) end)
            if ok and result ~= nil then return result end
        end
        local fallback = ArrayList.new()
        local ok2, inv = pcall(function() return character:getInventory() end)
        if ok2 and inv ~= nil then fallback:add(inv) end
        -- Include equipped bag inventories so recipes/equip checks see them.
        if ok2 and inv ~= nil then
            local ok3, items = pcall(function() return inv:getItems() end)
            if ok3 and items ~= nil then
                for i = 0, items:size() - 1 do
                    local item = items:get(i)
                    local bInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
                    if bInv ~= nil then
                        local ok4, cat = pcall(function() return item:getCategory() end)
                        local show = false
                        local ok5, eq = pcall(function() return character:isEquipped(item) end)
                        if ok5 and eq then show = true end
                        if not show and ok4 and cat == "Container" then show = true end
                        if show then fallback:add(bInv) end
                    end
                end
            end
        end
        return fallback
    end
end

-- Context menu: actions on the survivor side must target the survivor IsoPlayer,
-- not the local player. Vanilla builds the menu with getSpecificPlayer(player)
-- and tests playerObj:isEquipped / container:isInCharacterInventory. Redirect
-- that lookup when the clicked item lives in the active survivor inventory so
-- Wear/Equip/Unequip operate on the survivor and require the item to be in the
-- survivor's inventory (player must transfer first, as requested).
if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.createMenu ~= nil then
    if CompanionInventory._origCreateMenu == nil then
        CompanionInventory._origCreateMenu = ISInventoryPaneContextMenu.createMenu
    end
    local origCreate = CompanionInventory._origCreateMenu
    ISInventoryPaneContextMenu.createMenu = function(player, isInPlayerInventory, items, x, y, origin)
        local testItem = nil
        if type(items) == "table" and items[1] ~= nil then
            testItem = items[1]
            if testItem ~= nil and not instanceof(testItem, "InventoryItem") and testItem.items ~= nil then
                testItem = testItem.items[1]
            end
        end
        local container = testItem ~= nil and testItem.getContainer ~= nil and testItem:getContainer() or nil
        local nativeOwner, nativeId = containerSurvivor(container)
        if nativeId ~= nil and not CompanionInventory.canManage(player, nativeId, nativeOwner) then
            managementRefused()
            return
        end
        local isSurvivor = false
        local character = nil
        if container ~= nil then
            local ok, flag, ch = pcall(function() return isSurvivorContainer(player, container) end)
            if ok and flag then isSurvivor = true; character = ch end
        end
        if isSurvivor and character ~= nil then
            local savedGetSpecificPlayer = rawget(_G, "getSpecificPlayer")
            _G.getSpecificPlayer = function(p)
                if p == player then return character end
                if savedGetSpecificPlayer ~= nil then return savedGetSpecificPlayer(p) end
                return nil
            end
            -- Keep original isInPlayerInventory (false for loot) so Drop is not offered
            -- for survivor items — player must Take first. Wear branch is gated on
            -- tests.clothing, not isInPlayerInventory, so it still appears.
            local ok, result = pcall(function() return origCreate(player, isInPlayerInventory, items, x, y, origin) end)
            _G.getSpecificPlayer = savedGetSpecificPlayer
            if ok then return result else error(result, 0) end
        end
        return origCreate(player, isInPlayerInventory, items, x, y, origin)
    end
end

local function getSurvivorForItem(item, requester)
    if item == nil or item.getContainer == nil then return nil, nil end
    local ok, container = pcall(function() return item:getContainer() end)
    if not ok or container == nil then return nil, nil end
    local character, id = containerSurvivor(container)
    local playerNum = type(requester) == "number" and requester or nil
    if playerNum == nil and requester ~= nil then
        local found, number = pcall(function() return requester:getPlayerNum() end)
        if found and tonumber(number) ~= nil and number >= 0 then playerNum = number end
    end
    -- Active bindings also identify the exact old body during native replacement.
    for number, sid in pairs(active) do
        local belongs, body = isSurvivorContainer(number, container)
        if belongs then
            character, id = body, sid
            if playerNum == nil then playerNum = number end
            break
        end
    end
    if id == nil then return nil, nil end
    if playerNum == nil or not CompanionInventory.canManage(playerNum, id, character) then
        return nil, id, true, playerNum
    end
    return character, id, false, playerNum
end

-- Only manually queued actions receive this guard. Autonomous native equipment
-- and inventory work keep their existing owner and completion path.
local function queueManaged(action, playerNum, id, character)
    if action == nil then return nil end
    local function permitted(self)
        if CompanionInventory.canManage(playerNum, id, character) then return true end
        if not self.knoxManagementRefusal then self.knoxManagementRefusal=true; managementRefused() end
        return false
    end
    local originalValid = action.isValid
    local mutationMethod = action.complete ~= nil and "complete" or "perform"
    local originalMutation = action[mutationMethod]
    action.isValid = function(self)
        return permitted(self) and (originalValid == nil or originalValid(self))
    end
    if originalMutation ~= nil then
        action[mutationMethod] = function(self, ...)
            if not permitted(self) then return false end
            return originalMutation(self, ...)
        end
    end
    ISTimedActionQueue.add(action)
    return action
end

local function isActiveSurvivor(character)
    return character ~= nil
        and KnoxSurvivorRuntime.idForCharacter(character) ~= nil
end

-- Shared by inventory context actions. The active survivor inventory is a
-- vanilla loot pane backed by an off-slot IsoPlayer, so item ownership must be
-- resolved from the container rather than from the local player number.
function CompanionInventory.getSurvivorForItem(item, playerNum)
    return getSurvivorForItem(item, playerNum)
end

-- Build 42's player equip/wear actions correctly mutate the IsoPlayer shell,
-- but their terminal callbacks also refresh that character's local inventory
-- window. Knox survivors deliberately have no local player UI, so the refresh
-- is the only invalid part of the otherwise-native action.
local offslotInventoryPage = {
    refreshBackpacks = function() end,
    inventoryPane = nil,
}

local function withOffslotInventoryUi(character, callback)
    if not isActiveSurvivor(character) then return callback() end
    local playerNum = character:getPlayerNum()
    local originalGetPlayerInventory = rawget(_G, "getPlayerInventory")
    _G.getPlayerInventory = function(number)
        if number == playerNum then return offslotInventoryPage end
        return originalGetPlayerInventory ~= nil
            and originalGetPlayerInventory(number) or nil
    end
    local ok, result = pcall(callback)
    _G.getPlayerInventory = originalGetPlayerInventory
    if not ok then error(result, 0) end
    return result
end

local function wrapOffslotActionMethod(actionClass, methodName, originalKey)
    if actionClass == nil or actionClass[methodName] == nil then return end
    if CompanionInventory[originalKey] == nil then
        CompanionInventory[originalKey] = actionClass[methodName]
    end
    local original = CompanionInventory[originalKey]
    actionClass[methodName] = function(self, ...)
        local args = { ... }
        return withOffslotInventoryUi(self.character, function()
            return original(self, unpack(args))
        end)
    end
end

wrapOffslotActionMethod(ISEquipWeaponAction, "complete", "_origEquipComplete")
wrapOffslotActionMethod(ISEquipWeaponAction, "perform", "_origEquipPerform")
wrapOffslotActionMethod(ISWearClothing, "complete", "_origWearComplete")
wrapOffslotActionMethod(ISWearClothing, "perform", "_origWearPerform")
wrapOffslotActionMethod(ISUnequipAction, "perform", "_origUnequipPerform")

local function detachTransferredSurvivorItem(character, item)
    if character == nil or item == nil then return end
    pcall(function()
        if character:getPrimaryHandItem() == item
            or character:getSecondaryHandItem() == item then
            character:removeFromHands(item)
        end
    end)
    pcall(function()
        if character:isEquipped(item) then
            character:removeWornItem(item, false)
        end
    end)
    pcall(function() triggerEvent("OnClothingUpdated", character) end)
    pcall(function() character:resetModelNextFrame() end)
end

-- A loot-window transfer is performed by the real local player, so vanilla's
-- transfer detaches equipment from that player rather than from the survivor
-- who owns the source container. Decorate only survivor-source transfers.
-- Favorite is the existing explicit keep-allocation, including its bag
-- contents. A player can still rearrange the survivor's own inventory and
-- allocate ordinary gear without another approval UI.
local function personalTransferAllowed(owner, item, source, destination)
    local inside, sameOwner = pcall(function() return destination:isInCharacterInventory(owner) end)
    if inside and sameOwner then return true end
    local inventory = owner:getInventory()
    local current, container, seen = item, source, {}
    for depth = 1, 32 do
        local ok, favorite = pcall(function() return current:isFavorite() end)
        if not ok or favorite == true then return false end
        if container == inventory then return true end
        if container == nil or seen[container] then return false end
        seen[container] = true
        local found, bag = pcall(function() return container:getContainingItem() end)
        if not found or bag == nil then return false end
        current = bag
        local parentOk, parent = pcall(function() return bag:getContainer() end)
        if not parentOk then return false end
        container = parent
    end
    return false
end

if ISInventoryTransferUtil ~= nil
    and ISInventoryTransferUtil.newInventoryTransferAction ~= nil then
    if CompanionInventory._origNewInventoryTransferAction == nil then
        CompanionInventory._origNewInventoryTransferAction =
            ISInventoryTransferUtil.newInventoryTransferAction
    end
    local originalNewTransfer = CompanionInventory._origNewInventoryTransferAction
    ISInventoryTransferUtil.newInventoryTransferAction = function(character, item,
            srcContainer, destContainer, ...)
        local action = originalNewTransfer(character, item, srcContainer, destContainer, ...)
        local sourceSurvivor = nil
        for playerNum, _ in pairs(active) do
            local belongs, owner = isSurvivorContainer(playerNum, srcContainer)
            if belongs then sourceSurvivor = owner; break end
        end
        local playerNum
        if character ~= nil and character.getPlayerNum ~= nil then
            local ok, number = pcall(function() return character:getPlayerNum() end)
            if ok and tonumber(number) ~= nil and number >= 0 and localPlayerFor(number) == character then
                playerNum = number
            end
        end
        if action ~= nil and playerNum ~= nil then
            local sourceBody, sourceId = containerSurvivor(srcContainer)
            local targetBody, targetId = containerSurvivor(destContainer)
            if sourceBody ~= nil then sourceSurvivor = sourceBody end
            if sourceId ~= nil or targetId ~= nil then
                local function permitted(self)
                    local accepted = (sourceId == nil or CompanionInventory.canManage(playerNum, sourceId, sourceBody))
                        and (targetId == nil or CompanionInventory.canManage(playerNum, targetId, targetBody))
                    if not accepted and not self.knoxManagementRefusal then
                        self.knoxManagementRefusal=true; managementRefused()
                    end
                    return accepted
                end
                local nativeValid, nativeTransfer = action.isValid, action.transferItem
                action.isValid = function(self)
                    return permitted(self) and (nativeValid == nil or nativeValid(self))
                end
                if nativeTransfer ~= nil then
                    action.transferItem = function(self, ...)
                        if not permitted(self) then return end
                        return nativeTransfer(self, ...)
                    end
                end
            end
        end
        if action ~= nil and sourceSurvivor ~= nil
            and sourceSurvivor ~= character and action.transferItem ~= nil then
            local originalTransferItem = action.transferItem
            local function permitted(self, transferItem)
                if personalTransferAllowed(sourceSurvivor, transferItem, srcContainer, destContainer) then return true end
                if not self.knoxPersonalRefusal then
                    self.knoxPersonalRefusal = true
                    local feed = rawget(_G, "KnoxActivityFeed")
                    if feed ~= nil and feed.event ~= nil then feed.event("That survivor is keeping this personal item.") end
                end
                return false
            end
            local originalValid = action.isValid
            if originalValid ~= nil then
                action.isValid = function(self)
                    return permitted(self, self.item or item) and originalValid(self)
                end
            end
            action.transferItem = function(self, transferItem)
                if not permitted(self, transferItem) then return end
                local wasPresent = sourceHasItem(srcContainer, transferItem)
                local ok, result = pcall(originalTransferItem, self, transferItem)
                -- Vanilla may decline the transfer (favorite/dontAdd/already
                -- transferred). Only detach gear once it has actually left.
                -- Also reconcile a transfer that moved the item before a later
                -- native presentation callback raised an error.
                if wasPresent and not sourceHasItem(srcContainer, transferItem) then
                    detachTransferredSurvivorItem(sourceSurvivor, transferItem)
                end
                if not ok then error(result, 0) end
                return result
            end
        end
        return action
    end
end

local inventoryLogLast = {}
local function inventoryLog(action, sid, item, player)
    local now = getTimestampMs and getTimestampMs() or 0
    local key = tostring(sid) .. ":" .. tostring(action)
    if inventoryLogLast[key] and now - inventoryLogLast[key] < 800 then return end
    inventoryLogLast[key] = now
    local itemType = "unknown"
    pcall(function() itemType = tostring(item:getFullType()) end)
    local msg = "[KnoxSurvivors][Inventory] action=" .. tostring(action) .. " survivor=" .. tostring(sid) .. " item=" .. itemType .. " player=" .. tostring(player)
    -- Efficient diagnostics: throttle and only spam when developer diagnostics enabled, but always log wear/equip/finish
    local isDev = false
    pcall(function()
        if rawget(_G, "KnoxSettings") and KnoxSettings.showDeveloperDiagnostics then isDev = KnoxSettings.showDeveloperDiagnostics() == true end
        if not isDev and isDebugEnabled ~= nil and isDebugEnabled() then isDev = true end
    end)
    if isDev or action == "wear" or action == "equipWeapon" or action == "finish" then
        print(msg)
        local agent = rawget(_G, "KnoxAgent")
        if agent ~= nil and agent.writeLog ~= nil then pcall(function() agent.writeLog("Inventory " .. msg) end) end
    end
end

if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.wearItem ~= nil then
    if CompanionInventory._origWearItem == nil then CompanionInventory._origWearItem = ISInventoryPaneContextMenu.wearItem end
    local origWear = CompanionInventory._origWearItem
    ISInventoryPaneContextMenu.wearItem = function(item, player)
        local ch, sid, denied, requester = getSurvivorForItem(item, player)
        if denied then managementRefused(); return end
        if ch ~= nil then
            inventoryLog("wear", sid, item, player)
            -- Ensure survivor walk adj? vanilla transferIfNeeded will handle, but we bypass player transfer.
            local ok = pcall(function() ISInventoryPaneContextMenu.transferIfNeeded(ch, item) end)
            if not ok then pcall(function() print("[KnoxSurvivors][Inventory] transferIfNeeded failed") end) end
            queueManaged(ISWearClothing:new(ch, item, 50), requester, sid, ch)
            return
        end
        return origWear(item, player)
    end
end

if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.transferIfNeeded ~= nil then
    if CompanionInventory._origTransferIfNeeded == nil then CompanionInventory._origTransferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded end
    local origTransfer = CompanionInventory._origTransferIfNeeded
    ISInventoryPaneContextMenu.transferIfNeeded = function(playerObj, item, preventTransferWorldObjects)
        local ch, sid, denied, requester = getSurvivorForItem(item, playerObj)
        if denied then managementRefused(); return end
        if ch ~= nil and ch == playerObj then
            -- Already owned by this off-slot survivor. Vanilla's helper still
            -- asks for getPlayerInventory(ch:getPlayerNum()), which is nil for
            -- Knox shells and can crash while the item menu is closing. Move a
            -- nested-bag item to the survivor's main inventory through the
            -- real timed transfer, and make the already-correct case a true
            -- no-op.
            inventoryLog("transferIfNeeded-survivor-noop", sid, item, playerObj:getPlayerNum())
            local source = item ~= nil and item.getContainer ~= nil
                and item:getContainer() or nil
            local destination = ch.getInventory ~= nil and ch:getInventory() or nil
            if source ~= nil and destination ~= nil and source ~= destination
                and sourceHasItem(source, item) then
                local action = ISInventoryTransferUtil.newInventoryTransferAction(
                    ch, item, source, destination
                )
                if action ~= nil then
                    queueManaged(action, requester, sid, ch)
                    return action
                end
            end
            return nil
        end
        if ch ~= nil then
            inventoryLog("transferIfNeeded-survivor-redirect", sid, item, playerObj:getPlayerNum())
            local source = item ~= nil and item.getContainer ~= nil
                and item:getContainer() or nil
            local destination = ch.getInventory ~= nil and ch:getInventory() or nil
            if source ~= nil and destination ~= nil and source ~= destination
                and sourceHasItem(source, item) then
                local action = ISInventoryTransferUtil.newInventoryTransferAction(
                    ch, item, source, destination
                )
                if action ~= nil then
                    queueManaged(action, requester, sid, ch)
                    return action
                end
            end
            return nil
        end
        return origTransfer(playerObj, item, preventTransferWorldObjects)
    end
end

if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.equipWeapon ~= nil then
    if CompanionInventory._origEquipWeapon == nil then CompanionInventory._origEquipWeapon = ISInventoryPaneContextMenu.equipWeapon end
    local origEquip = CompanionInventory._origEquipWeapon
    ISInventoryPaneContextMenu.equipWeapon = function(weapon, primary, twoHands, player, alwaysTurnOn)
        local ch, sid, denied, requester = getSurvivorForItem(weapon, player)
        if denied then managementRefused(); return end
        if ch ~= nil then
            inventoryLog("equipWeapon", sid, weapon, player)
            local source = weapon:getContainer()
            if weapon:getWorldItem() then
                if not sourceHasItem(source, weapon) then
                    inventoryLog("equipWeapon-stale-item", sid, weapon, player)
                    return
                end
                local action = ISInventoryTransferUtil.newInventoryTransferAction(ch, weapon, source, ch:getInventory())
                action.maxTime = 20
                queueManaged(action, requester, sid, ch)
                queueManaged(ISEquipWeaponAction:new(ch, weapon, 1, primary, twoHands, alwaysTurnOn), requester, sid, ch)
                return
            end
            ISInventoryPaneContextMenu.transferIfNeeded(ch, weapon)
            queueManaged(ISEquipWeaponAction:new(ch, weapon, 50, primary, twoHands, alwaysTurnOn), requester, sid, ch)
            return
        end
        return origEquip(weapon, primary, twoHands, player, alwaysTurnOn)
    end
end

-- Vanilla builds the inventory menu for the local player and later receives
-- that same player number in the callback. For an off-slot survivor this made
-- Unequip silently fail its isEquipped check, and clothing attachment/hood
-- actions were queued against the wrong body. Resolve the item at callback
-- time and keep the native timed actions on the survivor shell.
if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.unequipItem ~= nil then
    if CompanionInventory._origUnequipItem == nil then
        CompanionInventory._origUnequipItem = ISInventoryPaneContextMenu.unequipItem
    end
    local originalUnequip = CompanionInventory._origUnequipItem
    ISInventoryPaneContextMenu.unequipItem = function(item, player)
        local ch, sid, denied, requester = getSurvivorForItem(item, player)
        if denied then managementRefused(); return end
        if ch ~= nil and ch:isEquipped(item) then
            inventoryLog("unequip", sid, item, player)
            queueManaged(ISUnequipAction:new(ch, item, 50), requester, sid, ch)
            return
        end
        return originalUnequip(item, player)
    end
end

if ISInventoryPaneContextMenu ~= nil
    and ISInventoryPaneContextMenu.onClothingItemExtra ~= nil then
    if CompanionInventory._origClothingItemExtra == nil then
        CompanionInventory._origClothingItemExtra =
            ISInventoryPaneContextMenu.onClothingItemExtra
    end
    local originalExtra = CompanionInventory._origClothingItemExtra
    ISInventoryPaneContextMenu.onClothingItemExtra = function(item, extra, playerObj)
        local ch, sid, denied, requester = getSurvivorForItem(item, playerObj)
        if denied then managementRefused(); return end
        if ch ~= nil then
            inventoryLog("attach", sid, item, playerObj)
            if ISInventoryPaneContextMenu.transferIfNeeded ~= nil then
                ISInventoryPaneContextMenu.transferIfNeeded(ch, item)
            end
            queueManaged(ISClothingExtraAction:new(ch, item, extra), requester, sid, ch)
            return
        end
        return originalExtra(item, extra, playerObj)
    end
end



function CompanionInventory.show(playerNum, survivorId)
    local accepted, reason, character = CompanionInventory.canManage(playerNum, survivorId)
    if not accepted then return false, reason end

    local loot = getPlayerLoot(playerNum)
    local playerInv = getPlayerInventory(playerNum)
    local inventory = character:getInventory()
    if loot == nil or playerInv == nil or inventory == nil then
        return false, "inventory_ui_unavailable"
    end

    active[playerNum] = survivorId
    exposedBodies[playerNum] = character
    knownBodies[character] = survivorId

    -- Vanilla loot flow: the survivor ItemContainer is presented as the loot
    -- container so all vanilla transfer actions, drag/drop, context menus and
    -- the bag button strip operate exactly as they do on a corpse or world
    -- container. The hook above keeps the button available after refresh.
    loot:setNewContainer(inventory)
    loot.title = displayName(survivorId) .. " - Inventory"

    -- Side-by-side: player inventory (left) + survivor loot (right), same as
    -- looting a nearby container. This keeps normal bag switching on the player
    -- side and bag switching for the survivor's equipped bags on the loot side.
    setVisiblePage(playerInv, true)
    setVisiblePage(loot, true)

    -- Ensure loot is the selected container before the next refresh. The
    -- re-injection hook will preserve this selection because the button will
    -- exist when refreshBackpacks decides the selected inventory.
    ISInventoryPage.dirtyUI()
    return true, "vanilla_loot_window"
end

function CompanionInventory.clear(playerNum)
    if active ~= nil then active[playerNum] = nil end
    exposedBodies[playerNum] = nil
end

function CompanionInventory.finish(playerNum)
    local sid = active[playerNum]
    if active ~= nil then active[playerNum] = nil end
    exposedBodies[playerNum] = nil
    local loot = getPlayerLoot(playerNum)
    if loot ~= nil then
        local floor = ISInventoryPage.GetFloorContainer and ISInventoryPage.GetFloorContainer(playerNum) or nil
        if floor ~= nil then
            pcall(function() loot:setNewContainer(floor) end)
            loot.title = nil
        else
            loot:setVisible(false)
        end
        ISInventoryPage.dirtyUI()
    end
    inventoryLog("finish", sid or tostring(playerNum), { getFullType = function() return "finish" end }, playerNum)
end

return CompanionInventory
