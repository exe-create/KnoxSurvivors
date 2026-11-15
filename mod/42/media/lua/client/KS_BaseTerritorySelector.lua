-- ISSelectCursor's Lua source is server-side in Build 42.  Do not require it
-- from the client; when the engine exposes a selection cursor it is already
-- available globally.  start() checks that capability before using it.
require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_BaseHighlights"
require "KS_Persistence"

local BaseTerritorySelector = rawget(_G, "KnoxBaseTerritorySelector") or {}
_G.KnoxBaseTerritorySelector = BaseTerritorySelector

local Selection = {}
Selection.__index = Selection

local activeSelection = nil
local tickHooked = false

local BOUNDARY_COLOR = KnoxBaseHighlights.BOUNDARY_COLOUR

local function newSelectionCursor(selection)
    local cursor = ISSelectCursor:new(selection.player, selection, selection.onSquareSelected)
    -- ISSelectCursor inherits ISBuildingObject:walkTo(). Build 42 calls that before
    -- create() even when skipBuildAction is set, so a plain selection cursor queues
    -- player movement toward the selected corner. skipWalk2 is the native opt-out.
    cursor.skipWalk2 = true
    return cursor
end



local function draftTick()
    if activeSelection == nil then return end
    local player = activeSelection.player
    if player == nil or (player.isDead ~= nil and player:isDead()) then
        activeSelection:onSquareSelectedCancel()
        return
    end
    if activeSelection.firstSquare == nil then return end
    if player == nil then return end
    if not activeSelection.pendingConfirm and not activeSelection.perspective
        and getCell():getDrag(player:getPlayerNum()) ~= activeSelection.cursor then
        activeSelection:onSquareSelectedCancel()
        return
    end
    local second = activeSelection.pendingConfirm and activeSelection.pendingSecond or nil
    local _, wx, wy, z
    if second ~= nil then wx, wy, z = second:getX(), second:getY(), second:getZ()
    else _, wx, wy, z = KnoxBaseHighlights.pickMouseSquare(player) end
    if wx == nil or wy == nil then return end
    local x1 = activeSelection.firstSquare:getX()
    local y1 = activeSelection.firstSquare:getY()
    local minX = math.min(x1, wx)
    local maxX = math.max(x1, wx)
    local minY = math.min(y1, wy)
    local maxY = math.max(y1, wy)
    local col = z == activeSelection.firstSquare:getZ() and BOUNDARY_COLOR
        or KnoxBaseHighlights.INVALID_COLOUR
    pcall(function()
        KnoxBaseHighlights.drawArea(player:getPlayerNum(), minX, minY, maxX, maxY, z,
            { r = col.r, g = col.g, b = col.b, a = 0.16 })
        KnoxBaseHighlights.drawArea(player:getPlayerNum(), wx, wy, wx, wy, z,
            { r = col.r, g = col.g, b = col.b, a = 0.8 })
    end)
end

local function hookTick(instance)
    activeSelection = instance
    KnoxBaseHighlights.setDraft(instance.player:getPlayerNum(), true, "boundary")
    if not tickHooked then
        Events.OnPreUIDraw.Add(draftTick)
        tickHooked = true
    end
end

local function unhookTick(instance)
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil then compat.endSelection(instance) end
    if activeSelection == instance then activeSelection = nil end
    if activeSelection == nil and tickHooked then
        pcall(function() Events.OnPreUIDraw.Remove(draftTick) end)
        tickHooked = false
    end
    if instance ~= nil and instance.player ~= nil then
        KnoxBaseHighlights.setDraft(instance.player:getPlayerNum(), false, nil)
    end
end

-- Native area highlights expire per render frame; there is no removal API.
local function clearDraftHighlight(instance)
end

function Selection:confirmCreate(secondSquare)
    local x1 = self.firstSquare:getX()
    local y1 = self.firstSquare:getY()
    local x2 = secondSquare:getX()
    local y2 = secondSquare:getY()
    local w = math.abs(x2 - x1) + 1
    local h = math.abs(y2 - y1) + 1
    self.pendingSecond = secondSquare
    self.pendingConfirm = true
    local prompt = "Set home boundary  " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(w * h) .. " tiles, all floors)?"
    local modal = ISModalDialog:new(0, 0, 380, 150, prompt, true, nil, function(_, button)
        if self.cancelled or self.firstSquare == nil then return end
        self.confirmationModal = nil
        self.pendingConfirm = false
        unhookTick(self)
        clearDraftHighlight(self)
        if button.internal == "YES" then
            local territory, result = KnoxBaseManager.setTerritory(self.player, self.baseId, self.firstSquare, secondSquare)
            if territory ~= nil then
                KnoxActivityFeed.event("Home boundary saved - " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(w * h) .. " tiles, all floors).")
            else
                KnoxActivityFeed.event("Could not set home boundary: " .. tostring(result) .. ".")
            end
        else
            KnoxActivityFeed.event("Home boundary not saved - cancelled at confirmation.")
        end
        self.cursor = nil
        self.firstSquare = nil
    end, self.player:getPlayerNum())
    self.confirmationModal = modal
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    local joypad = getJoypadData(self.player:getPlayerNum())
    if joypad then
        local previous = joypad.focus
        modal.prevFocus = previous ~= nil and previous.isVisible ~= nil and previous:isVisible() and previous or nil
        modal:centerOnScreen(self.player:getPlayerNum())
        setJoypadFocus(self.player:getPlayerNum(), modal)
    end
end

function Selection:onSquareSelected(square)
    self.cursor = nil
    if square == nil then
        unhookTick(self)
        return
    end
    if self.firstSquare == nil then
        self.firstSquare = square
        KnoxActivityFeed.event("First corner set at " .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. ". Now click opposite corner - highlighted area is preview. Right-click cancels.")
        hookTick(self)
        if not self.perspective then
            self.cursor = newSelectionCursor(self)
            getCell():setDrag(self.cursor, self.player:getPlayerNum())
        end
        return
    end
    if square:getZ() ~= self.firstSquare:getZ() then
        KnoxActivityFeed.event("Choose the opposite corner on the same floor.")
        if not self.perspective then
            self.cursor = newSelectionCursor(self)
            getCell():setDrag(self.cursor, self.player:getPlayerNum())
        end
        return
    end
    self:confirmCreate(square)
end

function Selection:onSquareSelectedCancel()
    self.cancelled = true
    local modal = self.confirmationModal
    self.confirmationModal = nil
    if modal ~= nil then modal:destroy() end
    unhookTick(self)
    clearDraftHighlight(self)
    self.cursor = nil
    self.firstSquare = nil
    self.pendingConfirm = false
    KnoxActivityFeed.event("Home boundary selection cancelled.")
end

function BaseTerritorySelector.start(player, baseId)
    local perspective = require("KS_SurvivorUILayout").isPerspective()
    if player == nil or getCell() == nil or (ISSelectCursor == nil and not perspective) then
        if KnoxActivityFeed ~= nil then
            KnoxActivityFeed.event("Area selection is not available in this game build.")
        end
        return false
    end
    local selection = setmetatable({
        player = player,
        baseId = baseId,
        firstSquare = nil,
        cursor = nil,
        pendingConfirm = false,
    }, Selection)
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if perspective and compat ~= nil and compat.beginSelection(selection, "Set home boundary") then return true end
    selection.cursor = newSelectionCursor(selection)
    getCell():setDrag(selection.cursor, player:getPlayerNum())
    KnoxActivityFeed.event("Set home boundary: click first corner, then opposite corner. Highlighted area is preview. Confirm size to save. Right-click cancels.")
    return true
end

return BaseTerritorySelector
