-- ISSelectCursor's Lua source is server-side in Build 42.  Do not require it
-- from the client; when the engine exposes a selection cursor it is already
-- available globally.  start() checks that capability before using it.
require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_BaseHighlights"
require "KS_Persistence"

local BaseZoneSelector = rawget(_G, "KnoxBaseZoneSelector") or {}
_G.KnoxBaseZoneSelector = BaseZoneSelector

-- Draft-cursor hues mirror KS_BaseHighlights one-to-one (same hues, softer
-- alpha) so a zone looks the same while drawing it and after placing it.
local ZONE_HIGHLIGHT = {
    guard       = { r = 0.88, g = 0.16, b = 0.16, a = 0.32 },
    patrol      = { r = 0.92, g = 0.55, b = 0.12, a = 0.32 },
    cooking     = { r = 0.80, g = 0.30, b = 0.50, a = 0.30 },
    farming     = { r = 0.22, g = 0.75, b = 0.22, a = 0.30 },
    woodcutting = { r = 0.55, g = 0.35, b = 0.15, a = 0.30 },
    log_processing = { r = 0.82, g = 0.68, b = 0.16, a = 0.30 },
    corpse      = { r = 0.50, g = 0.50, b = 0.58, a = 0.28 },
    repair      = { r = 0.30, g = 0.32, b = 0.88, a = 0.30 },
    general     = { r = 0.52, g = 0.52, b = 0.75, a = 0.28 },
}

local Selection = {}
Selection.__index = Selection

local activeSelection = nil
local tickHooked = false

local function newSelectionCursor(selection)
    local cursor = ISSelectCursor:new(selection.player, selection, selection.onSquareSelected)
    -- ISSelectCursor inherits ISBuildingObject:walkTo(). Build 42 calls that before
    -- create() even when skipBuildAction is set, so a plain selection cursor queues
    -- player movement toward the selected corner. skipWalk2 is the native opt-out.
    cursor.skipWalk2 = true
    return cursor
end

local function pickMouseSquare(player)
    if player == nil or getCell() == nil then return nil, nil, nil, nil end
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and require("KS_SurvivorUILayout").isPerspective() then
        local sq = compat.targetSquare(player)
        if sq ~= nil then return sq, sq:getX(), sq:getY(), sq:getZ() end
        return nil, nil, nil, player:getZ()
    end
    local z = player:getZ()
    local mx, my = getMouseX(), getMouseY()
    local ok1, wx = pcall(function() return screenToIsoX(player:getPlayerNum(), mx, my, z) end)
    local ok2, wy = pcall(function() return screenToIsoY(player:getPlayerNum(), mx, my, z) end)
    if not ok1 or not ok2 then return nil, nil, nil, z end
    local sq = getCell():getGridSquare(wx, wy, z)
    return sq, wx, wy, z
end

-- Work areas describe jobs, not ownership. They may be outside the home
-- territory or on another floor; native routing decides reachability.
-- Exclusive production areas cannot share tiles with another exclusive area.
-- Territory (border) and overlay duties (guard/patrol/...) remain
-- shareable, matching persistence overlap rules.
local WORK_OVERLAY_TYPES = {
    guard = true, patrol = true,
    general = true,
}

local function zonesOverlap(minX, minY, maxX, maxY, z, zone)
    if zone == nil or zone.x1 == nil or (tonumber(zone.z) or 0) ~= (tonumber(z) or 0) then
        return false
    end
    local zx1 = math.min(tonumber(zone.x1), tonumber(zone.x2))
    local zx2 = math.max(tonumber(zone.x1), tonumber(zone.x2))
    local zy1 = math.min(tonumber(zone.y1), tonumber(zone.y2))
    local zy2 = math.max(tonumber(zone.y1), tonumber(zone.y2))
    return minX <= zx2 and zx1 <= maxX and minY <= zy2 and zy1 <= maxY
end

local function isValidWorkArea(minX, minY, maxX, maxY, z, base, zoneType)
    if base == nil or minX > maxX or minY > maxY or z == nil then return false end
    if WORK_OVERLAY_TYPES[zoneType] == true then return true end
    if base.zones ~= nil then
        for _, zone in pairs(base.zones) do
            if zone ~= nil and zone.enabled ~= false
                and WORK_OVERLAY_TYPES[zone.type] ~= true
                and zonesOverlap(minX, minY, maxX, maxY, z, zone) then
                return false
            end
        end
    end
    return true
end

local function draftTick()
    if activeSelection == nil then return end
    local player = activeSelection.player
    if player == nil or (player.isDead ~= nil and player:isDead()) then
        activeSelection:onSquareSelectedCancel()
        return
    end
    if activeSelection.firstSquare == nil or activeSelection.pendingConfirm then return end
    if player == nil then return end
    -- Right-click and opening a world context menu clear IsoCell's drag cursor
    -- directly. Build 42 does not call our selection callback in that path, so
    -- detect the cleared cursor and release the preview on the next tick.
    if not activeSelection.perspective and getCell():getDrag(player:getPlayerNum()) ~= activeSelection.cursor then
        activeSelection:onSquareSelectedCancel()
        return
    end
    local _, wx, wy, z = pickMouseSquare(player)
    if wx == nil or wy == nil then return end
    local x1 = activeSelection.firstSquare:getX()
    local y1 = activeSelection.firstSquare:getY()
    local minX = math.min(x1, wx)
    local maxX = math.max(x1, wx)
    local minY = math.min(y1, wy)
    local maxY = math.max(y1, wy)
    local base = KnoxPersistence.getBase(activeSelection.baseId)
    local valid = isValidWorkArea(minX, minY, maxX, maxY, z, base, activeSelection.zoneType)
    local col = ZONE_HIGHLIGHT[activeSelection.zoneType] or ZONE_HIGHLIGHT.general
    -- Preview uses the same external-area policy as persisted work zones.
    if not valid then
        local bad = getCore() and getCore():getBadHighlitedColor() or nil
        if bad ~= nil then
            col = { r = bad:getR(), g = bad:getG(), b = bad:getB(), a = 0.38 }
        else
            col = { r = 0.90, g = 0.15, b = 0.15, a = 0.38 }
        end
    end
    pcall(function()
        if addAreaHighlightForPlayer ~= nil then
            addAreaHighlightForPlayer(player:getPlayerNum(), minX, minY, maxX + 1, maxY + 1, z, col.r, col.g, col.b, col.a)
        elseif addAreaHighlight ~= nil then
            addAreaHighlight(minX, minY, maxX + 1, maxY + 1, z, col.r, col.g, col.b, col.a)
        end
        -- Overlaps remain readable: draw intersect borders with thin contrasting outline
        -- over the subdued existing fills, instead of blending into one block.
        if base ~= nil and base.zones ~= nil then
            local pn = player:getPlayerNum()
            for _, zone in pairs(base.zones) do
                if zone ~= nil and zone.x1 ~= nil and (zone.z or 0) == z then
                    local zx1 = math.min(tonumber(zone.x1), tonumber(zone.x2))
                    local zx2 = math.max(tonumber(zone.x1), tonumber(zone.x2))
                    local zy1 = math.min(tonumber(zone.y1), tonumber(zone.y2))
                    local zy2 = math.max(tonumber(zone.y1), tonumber(zone.y2))
                    local ix1 = math.max(minX, zx1); local ix2 = math.min(maxX, zx2)
                    local iy1 = math.max(minY, zy1); local iy2 = math.min(maxY, zy2)
                    if ix1 <= ix2 and iy1 <= iy2 then
                        -- Contrast border over overlap — restrained white, not rainbow.
                        if addAreaHighlightForPlayer ~= nil then
                            addAreaHighlightForPlayer(pn, ix1, iy1, ix2 + 1, iy2 + 1, z, 0.92, 0.92, 0.88, 0.18)
                        end
                        -- Thin Bad tint on the overlap itself keeps conflicts obvious.
                        if addAreaHighlightForPlayer ~= nil then
                            addAreaHighlightForPlayer(pn, ix1, iy1, ix2 + 1, iy2 + 1, z, 0.90, 0.55, 0.15, 0.10)
                        end
                    end
                end
            end
        end
    end)
end

local function hookTick(instance)
    activeSelection = instance
    KnoxBaseHighlights.setDraft(instance.player:getPlayerNum(), true, instance.zoneType)
    if not tickHooked then
        Events.OnTick.Add(draftTick)
        tickHooked = true
    end
end

local function unhookTick(instance)
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil then compat.endSelection(instance) end
    if activeSelection == instance then
        activeSelection = nil
    end
    if activeSelection == nil and tickHooked then
        pcall(function() Events.OnTick.Remove(draftTick) end)
        tickHooked = false
    end
    if instance ~= nil and instance.player ~= nil then
        KnoxBaseHighlights.setDraft(instance.player:getPlayerNum(), false, nil)
    end
end

local function clearDraftHighlight(instance)
    if instance == nil or instance.firstSquare == nil then return end
    pcall(function()
        local x1 = instance.firstSquare:getX()
        local y1 = instance.firstSquare:getY()
        local _, wx, wy, z = pickMouseSquare(instance.player)
        if wx ~= nil then
            local minX = math.min(x1, wx)
            local minY = math.min(y1, wy)
            local maxX = math.max(x1, wx)
            local maxY = math.max(y1, wy)
            local pn = instance.player:getPlayerNum()
            if removeAreaHighlightForPlayer ~= nil then
                removeAreaHighlightForPlayer(pn, minX, minY, maxX + 1, maxY + 1, z)
            elseif removeAreaHighlight ~= nil then
                removeAreaHighlight(minX, minY, maxX + 1, maxY + 1, z)
            end
            if addAreaHighlightForPlayer ~= nil then
                -- push a transparent update to overwrite stale preview
                addAreaHighlightForPlayer(pn, minX, minY, maxX + 1, maxY + 1, z, 0, 0, 0, 0)
            end
        end
    end)
end

function Selection:confirmCreate(secondSquare)
    local x1 = self.firstSquare:getX()
    local y1 = self.firstSquare:getY()
    local x2 = secondSquare:getX()
    local y2 = secondSquare:getY()
    local w = math.abs(x2 - x1) + 1
    local h = math.abs(y2 - y1) + 1
    local total = w * h
    self.pendingSecond = secondSquare
    self.pendingConfirm = true

    -- Keep highlight visible while modal is up — tick continues to draw.
    local prompt = "Create " .. tostring(self.label) .. "  " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(total) .. " tiles)?"
    local modal = ISModalDialog:new(0, 0, 360, 150, prompt, true, nil, function(_, button)
        if self.cancelled or self.firstSquare == nil then return end
        self.confirmationModal = nil
        self.pendingConfirm = false
        unhookTick(self)
        clearDraftHighlight(self)
        if button.internal == "YES" then
            local zone, result = KnoxBaseManager.addZone(
                self.baseId,
                self.zoneType,
                { x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = self.firstSquare:getZ() },
                self.label
            )
            if zone ~= nil then
                KnoxActivityFeed.event(tostring(self.label) .. " saved — " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(total) .. " tiles).")
                if KnoxBaseHighlights ~= nil and KnoxBaseHighlights.refresh ~= nil then
                    local pn = self.player ~= nil and self.player:getPlayerNum() or 0
                    KnoxBaseHighlights.refresh(pn)
                end
            else
                KnoxActivityFeed.event("Could not save work area: " .. tostring(result) .. ".")
            end
        else
            KnoxActivityFeed.event(tostring(self.label) .. " not saved — cancelled at confirmation.")
        end
        self.cursor = nil
        self.firstSquare = nil
        self.pendingSecond = nil
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
    -- A guard post is a position, not a rectangle. Keep the existing zone
    -- record format so older saved areas remain readable by the job system.
    if self.zoneType == "guard" then
        local zone, result = KnoxBaseManager.addZone(self.baseId, "guard", {
            x1 = square:getX(), y1 = square:getY(),
            x2 = square:getX(), y2 = square:getY(), z = square:getZ(),
        }, self.label)
        unhookTick(self)
        if zone ~= nil then
            KnoxActivityFeed.event("Guard post saved at " .. tostring(square:getX())
                .. ", " .. tostring(square:getY()) .. ".")
        else
            KnoxActivityFeed.event("Could not save guard post: " .. tostring(result) .. ".")
        end
        return
    end
    if self.firstSquare == nil then
        self.firstSquare = square
        KnoxActivityFeed.event("First corner set for " .. tostring(self.label) .. " at " .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. ". Now click the opposite corner — highlighted area is preview. Right-click cancels.")
        hookTick(self)
        if not self.perspective then
            self.cursor = newSelectionCursor(self)
            getCell():setDrag(self.cursor, self.player:getPlayerNum())
        end
        return
    end
    -- Second corner — ask for confirmation (matches vanilla DesignationZone confirm).
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
    self.pendingSecond = nil
    KnoxActivityFeed.event(tostring(self.label) .. " selection cancelled. Right-click again if needed.")
end

function BaseZoneSelector.start(player, baseId, zoneType, label)
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
        zoneType = zoneType,
        label = label or zoneType,
        firstSquare = nil,
        cursor = nil,
        pendingConfirm = false,
        pendingSecond = nil,
    }, Selection)
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if perspective and compat ~= nil and compat.beginSelection(selection, label or zoneType) then return true end
    selection.cursor = newSelectionCursor(selection)
    getCell():setDrag(selection.cursor, player:getPlayerNum())
    if zoneType == "guard" then
        KnoxActivityFeed.event("Add Guard Post: click the tile to guard. Right-click cancels.")
    else
        KnoxActivityFeed.event("Add " .. tostring(selection.label) .. ": click first corner, then opposite corner. Highlighted rectangle is preview. Confirm size to save. Right-click cancels.")
    end
    return true
end

return BaseZoneSelector
