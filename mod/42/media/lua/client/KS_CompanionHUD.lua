require "ISUI/ISPanel"
require "ISUI/ISUI3DModel"
require "KS_SurvivorContextMenu"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_Settings"
require "KS_PartyCommands"
require "KS_CompanionInventoryMenu"
require "KS_SurvivorUILayout"

local UILayout = require "KS_SurvivorUILayout"
-- One palette: the shared theme is read, never copied. A second table here is
-- how three windows end up a shade apart after one palette change.
if type(UILayout) ~= "table" then
    UILayout = rawget(_G, "KnoxSurvivorUILayout") or {}
end
local THEME = type(UILayout.theme) == "table" and UILayout.theme or {}

local CompanionHUD = rawget(_G, "KnoxCompanionHUD") or {}
_G.KnoxCompanionHUD = CompanionHUD

local Panel = ISPanel:derive("KnoxCompanionHUDPanel")

local MAX_PORTRAITS = 6
local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 400
local OUTER_PADDING = 8
local ROW_GAP = 3
local AVATAR_TEXTURE = getTexture("media/ui/avatarBackgroundWhite.png")

local panels = {}
local baseLines = {}
local nextRefreshAt = 0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function timestampMs()
    if getTimestampMs == nil then return 0 end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or 0
end

local function sidebarPixels()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end
    local sizes = { 48, 64, 80, 96, 128 }
    return sizes[clamp(tonumber(size) or 1, 1, 5)]
end

local function trimText(font, text, maximumWidth)
    return UILayout.fitText(font, text, maximumWidth)
end

local function initials(snapshot)
    local first = string.sub(tostring(snapshot.forename or ""), 1, 1)
    local last = string.sub(tostring(snapshot.surname or ""), 1, 1)
    local result = string.upper(first .. last)
    return result ~= "" and result or "--"
end

local function screenBounds(playerNum)
    return getPlayerScreenLeft(playerNum),
        getPlayerScreenTop(playerNum),
        getPlayerScreenWidth(playerNum),
        getPlayerScreenHeight(playerNum)
end

-- The vanilla clock and speed controls own the top-right corner. Read their
-- real bounds so the auto-placed strip never hides the time controls. Only
-- widgets in the top half count; a bottom-edge speed widget is not a reason
-- to push the strip down.
local function visibleTopRightBottom(screenTop, screenHeight)
    if UIManager == nil or tonumber(screenHeight) == nil then return nil end
    local limit = screenTop + screenHeight * 0.5
    local bottom = nil
    local function include(element)
        if element == nil then return end
        local okVisible, visible = pcall(function()
            return element:isVisible()
        end)
        if not okVisible or not visible then return end
        local okY, y = pcall(function() return element:getAbsoluteY() end)
        local okHeight, elementHeight = pcall(function()
            return element:getHeight()
        end)
        y, elementHeight = tonumber(y), tonumber(elementHeight)
        if y == nil or elementHeight == nil
            or y < screenTop or y > limit then return end
        bottom = math.max(bottom or 0, y + elementHeight)
    end
    local okClock, clock = pcall(function() return UIManager.getClock() end)
    if okClock then include(clock) end
    local okSpeed, speed = pcall(function() return UIManager.getSpeedControls() end)
    if okSpeed then include(speed) end
    return bottom
end

local function autoTop(screenTop, screenHeight, panelHeight, reservedBottom)
    local available = math.max(0, screenHeight - panelHeight)
    local centered = screenTop + available / 2
    local safe = screenTop + OUTER_PADDING
    if reservedBottom ~= nil then
        safe = math.max(safe, reservedBottom + OUTER_PADDING)
    end
    return math.min(screenTop + available, math.max(safe, centered))
end

local function activePlayer(playerNum)
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then
        return nil
    end
    return player
end

local function playerPreferences(playerNum)
    local player = getSpecificPlayer(playerNum)
    if player == nil then
        return nil
    end
    local modData = player:getModData()
    local ui = modData.KnoxSurvivorsUI
    return type(ui) == "table" and ui.companionHud or nil
end

local function savePlayerPreferences(panel, keepAutoPosition)
    local player = getSpecificPlayer(panel.playerNum)
    if player == nil then
        return
    end
    local left, top, width, height = screenBounds(panel.playerNum)
    local rangeX = math.max(1, width - panel:getWidth())
    local rangeY = math.max(1, height - panel:getHeight())
    local modData = player:getModData()
    modData.KnoxSurvivorsUI = modData.KnoxSurvivorsUI or {}
    local stored = { collapsed = panel.collapsed == true }
    if keepAutoPosition ~= true or panel.manualPosition then
        stored.x = clamp((panel:getX() - left) / rangeX, 0, 1)
        stored.y = clamp((panel:getY() - top) / rangeY, 0, 1)
    end
    modData.KnoxSurvivorsUI.companionHud = stored
    if keepAutoPosition ~= true then panel.manualPosition = true end
end

function Panel:calculateMetrics()
    local small = getTextManager():getFontHeight(UIFont.Small)
    local medium = getTextManager():getFontHeight(UIFont.Medium)
    local portrait = clamp(sidebarPixels(), 46, 50)
    self.smallFontHeight = small
    self.mediumFontHeight = medium
    self.portraitSize = portrait
    self.headerHeight = medium + 12
    self.rowHeight = math.max(62, medium + small * 2 + 16)
    self.compactRowHeight = math.max(24, small + 10)
    self.chevronWidth = 16
    -- Font-relative width (same factor as the card and notebook): fixed
    -- pixels clip names and bars on large-font displays and big TVs.
    local fontScale = math.max(1, small / 14)
    self.panelWidth = math.floor(188 * fontScale)
    self.sidebarOption = getCore():getOptionSidebarSize()
end

function Panel:createChildren()
    self.portraits = {}
    self.portraitAvailable = {}
    for index = 1, MAX_PORTRAITS do
        local portrait = ISUI3DModel:new(0, 0, 1, 1)
        portrait:initialise()
        self:addChild(portrait)
        portrait:setWantMouseEvents(false)
        portrait:setState("idle")
        portrait:setDirection(IsoDirections.S)
        portrait:setIsometric(false)
        portrait:setDoRandomExtAnimations(false)
        portrait:setZoom(14)
        portrait:setYOffset(-0.85)
        portrait:setVisible(false)
        portrait.boundCharacter = nil
        self.portraits[index] = portrait
        self.portraitAvailable[index] = false
    end
end

function Panel:releasePortrait(index)
    local portrait = self.portraits ~= nil and self.portraits[index] or nil
    if portrait == nil then
        return
    end
    portrait.boundCharacter = nil
    self.portraitAvailable[index] = false
    portrait:setVisible(false)
end

function Panel:releaseAllPortraits()
    for index = 1, MAX_PORTRAITS do
        self:releasePortrait(index)
    end
end

function Panel:visibleRowCount()
    return math.min(#self.snapshots, self.visibleCapacity)
end

function Panel:maximumScrollOffset()
    return math.max(0, #self.snapshots - self.visibleCapacity)
end

function Panel:partyProblemCount()
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    return viewModel ~= nil and viewModel.partyProblemCount ~= nil
        and viewModel.partyProblemCount(self.snapshots) or 0
end

function Panel:compactSummary()
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.partyHeadline ~= nil then
        return viewModel.partyHeadline(self.snapshots, true)
    end
    return tostring(#(self.snapshots or {})) .. " with you"
end

function Panel:headline()
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.partyHeadline ~= nil then
        return viewModel.partyHeadline(self.snapshots, false)
    end
    return tostring(#(self.snapshots or {})) .. ", all clear"
end

function Panel:partyTone()
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.partyTone ~= nil then
        return viewModel.partyTone(self.snapshots)
    end
    return "muted"
end

function Panel:toggleCollapsed()
    self.collapsed = not self.collapsed
    self.draggingHeader = false
    self.hoverSlot = nil
    self:layout(true)
    self:refreshPortraits()
    savePlayerPreferences(self, true)
    self:setVisible(#self.snapshots > 0)
end

function Panel:clampToViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setX(clamp(self:getX(), left, left + width - self:getWidth()))
    self:setY(clamp(self:getY(), top, top + height - self:getHeight()))
    self:stayOnSplitScreen(self.playerNum)
end

function Panel:applyPosition()
    local left, top, width, height = screenBounds(self.playerNum)
    local stored = playerPreferences(self.playerNum)
    if self.manualPosition and type(stored) == "table" then
        local rangeX = math.max(1, width - self:getWidth())
        local rangeY = math.max(1, height - self:getHeight())
        self:setX(left + clamp(tonumber(stored.x) or 1, 0, 1) * rangeX)
        self:setY(top + clamp(tonumber(stored.y) or 0, 0, 1) * rangeY)
    else
        local rightEdge = left + width - OUTER_PADDING
        local moodles = UIManager.getMoodleUI(self.playerNum)
        if moodles ~= nil and moodles:isVisible() then
            rightEdge = math.min(rightEdge, moodles:getAbsoluteX() - OUTER_PADDING)
        end
        self:setX(rightEdge - self:getWidth())
        self:setY(autoTop(top, height, self:getHeight(),
            visibleTopRightBottom(top, height)))
    end
    self:clampToViewport()
end

function Panel:layout(forcePosition)
    local previousOption = self.sidebarOption
    self:calculateMetrics()
    local left, top, screenWidth, screenHeight = screenBounds(self.playerNum)
    local availableHeight = math.max(self.rowHeight, screenHeight - OUTER_PADDING * 2 - self.headerHeight)
    self.visibleCapacity = clamp(
        math.floor((availableHeight + ROW_GAP) / (self.rowHeight + ROW_GAP)),
        1,
        MAX_PORTRAITS
    )
    self.scrollOffset = clamp(self.scrollOffset, 0, self:maximumScrollOffset())

    local rows = self:visibleRowCount()
    local height = self.headerHeight
    if self.collapsed and #self.snapshots > 0 then
        height = height + OUTER_PADDING + self.compactRowHeight + OUTER_PADDING
    elseif rows > 0 then
        height = height + OUTER_PADDING + rows * self.rowHeight + (rows - 1) * ROW_GAP
            + OUTER_PADDING
    end
    self:setWidth(math.min(self.panelWidth, math.max(140, screenWidth - OUTER_PADDING * 2)))
    self:setHeight(height)

    local boundsSignature = table.concat({
        tostring(left), tostring(top), tostring(screenWidth), tostring(screenHeight),
        tostring(self:getWidth()), tostring(self:getHeight()), tostring(rows),
    }, ":")
    if forcePosition or previousOption ~= self.sidebarOption
        or self.lastBoundsSignature ~= boundsSignature then
        self.lastBoundsSignature = boundsSignature
        self:applyPosition()
    else
        self:clampToViewport()
    end

    for slot = 1, MAX_PORTRAITS do
        local portrait = self.portraits[slot]
        if portrait ~= nil then
            local rowY = self.headerHeight + OUTER_PADDING
                + (slot - 1) * (self.rowHeight + ROW_GAP)
            portrait:setX(OUTER_PADDING + 3)
            portrait:setY(rowY + 3)
            portrait:setWidth(self.portraitSize - 6)
            portrait:setHeight(self.rowHeight - 6)
        end
    end
end

function Panel:refreshPortraits()
    if self.collapsed then
        for slot = 1, MAX_PORTRAITS do self:releasePortrait(slot) end
        return
    end
    local rows = self:visibleRowCount()
    for slot = 1, MAX_PORTRAITS do
        if slot > rows then
            self:releasePortrait(slot)
        else
            local snapshot = self.snapshots[self.scrollOffset + slot]
            local character = snapshot ~= nil
                and KnoxSurvivorViewModel.resolveLiveCharacter(snapshot.id)
                or nil
            local portrait = self.portraits[slot]
            if character == nil then
                self:releasePortrait(slot)
            else
                if portrait.boundCharacter ~= character then
                    local success = pcall(function()
                        portrait:setCharacter(character)
                        portrait:setState("idle")
                    end)
                    if success then
                        portrait.boundCharacter = character
                        self.portraitAvailable[slot] = true
                    else
                        portrait.boundCharacter = nil
                        self:releasePortrait(slot)
                    end
                end
                portrait:setVisible(self.portraitAvailable[slot] == true)
            end
        end
    end
end

function Panel:refresh(forcePosition)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then
        self.snapshots = {}
        self:releaseAllPortraits()
        self:setVisible(false)
        return
    end
    self.snapshots = KnoxSurvivorViewModel.getForPlayer(self.playerNum)
    self.scrollOffset = clamp(self.scrollOffset, 0, self:maximumScrollOffset())
    if self.selectedId ~= nil then
        local found = false
        for _, snapshot in ipairs(self.snapshots) do
            if snapshot.id == self.selectedId then
                found = true
                break
            end
        end
        if not found then
            self.selectedId = nil
        end
    end
    self:layout(forcePosition == true)
    self:refreshPortraits()
    self:setVisible(#self.snapshots > 0)
end

function Panel:rowAt(y)
    if self.collapsed then return nil end
    local relative = y - self.headerHeight - OUTER_PADDING
    if relative < 0 then
        return nil
    end
    local stride = self.rowHeight + ROW_GAP
    local slot = math.floor(relative / stride) + 1
    if slot < 1 or slot > self:visibleRowCount()
        or relative % stride >= self.rowHeight then
        return nil
    end
    return slot, self.snapshots[self.scrollOffset + slot]
end

local BAR_HEIGHT = 6

local BAR_COLOURS = {
    health = { r = 0.72, g = 0.22, b = 0.18 },
    hunger = { r = 0.78, g = 0.54, b = 0.14 },
    thirst = { r = 0.22, g = 0.50, b = 0.82 },
    fatigue = { r = 0.68, g = 0.34, b = 0.72 },
}

function Panel:drawBar(x, y, width, value, colour, label)
    if tonumber(value) == nil then
        self:drawRect(x, y, width, BAR_HEIGHT, 0.92, 0.10, 0.10, 0.10)
        self:drawRectBorder(x, y, width, BAR_HEIGHT, 0.70, 0.36, 0.36, 0.36)
        if label ~= nil then
            self:drawTextCentre(label .. " unknown", x + width / 2, y - 3,
                0.58, 0.58, 0.56, 1, UIFont.Small)
        end
        return
    end
    local amount = clamp(tonumber(value) or 0, 0, 1)
    self:drawRect(x, y, width, BAR_HEIGHT, 0.92, 0.10, 0.10, 0.10)
    local c = colour or BAR_COLOURS.health
    local fade = 0.55 + amount * 0.45
    self:drawRect(x, y, math.floor(width * amount), BAR_HEIGHT,
        0.92, c.r * fade, c.g * fade, c.b * fade)
    -- Critically low needs read at a glance: amber label plus a red frame
    -- so a starving/thirsty/exhausted companion pops without reading bars.
    local critical = tonumber(value) ~= nil and amount < 0.30
    if critical then
        self:drawRectBorder(x - 1, y - 1, width + 2, BAR_HEIGHT + 2,
            0.95, 0.85, 0.25, 0.25)
    end
    if label ~= nil then
        if critical then
            self:drawTextCentre(label .. "!", x + width / 2, y - 3,
                1.0, 0.85, 0.40, 1, UIFont.Small)
        else
            self:drawTextCentre(label, x + width / 2, y - 3,
                0.96, 0.96, 0.94, 1, UIFont.Small)
        end
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    local bone, muted, amber = THEME.bone, THEME.muted, THEME.amber
    self:drawRect(0, 0, self.width, self.headerHeight, 0.94,
        THEME.charcoal[1], THEME.charcoal[2], THEME.charcoal[3])
    self:drawText("WITH YOU", OUTER_PADDING,
        math.floor((self.headerHeight - self.mediumFontHeight) / 2),
        bone[1], bone[2], bone[3], 1, UIFont.Medium)
    local right = self.width - OUTER_PADDING - self.chevronWidth - 4
    if not self.collapsed and #self.snapshots > self.visibleCapacity then
        local first = self.scrollOffset + 1
        local last = math.min(#self.snapshots, self.scrollOffset + self.visibleCapacity)
        local pageText = tostring(first) .. "-" .. tostring(last)
        self:drawTextRight(pageText, right,
            math.floor((self.headerHeight - self.smallFontHeight) / 2) + 1,
            muted[1], muted[2], muted[3], 0.9, UIFont.Small)
        right = right - getTextManager():MeasureStringX(UIFont.Small, pageText) - 6
    end
    if not self.collapsed and #self.snapshots > 0 then
        local tone = self:partyTone()
        local colour = tone == "critical" and THEME.red
            or (tone == "warn" and amber or muted)
        local labelWidth = getTextManager():MeasureStringX(UIFont.Medium, "WITH YOU")
        local available = math.max(20, right - OUTER_PADDING - labelWidth - 6)
        local summary = trimText(UIFont.Small, self:headline(), available)
        self:drawTextRight(summary, right,
            math.floor((self.headerHeight - self.smallFontHeight) / 2) + 1,
            colour[1], colour[2], colour[3], 1, UIFont.Small)
    end
    self:drawTextRight(self.collapsed and "+" or "-",
        self.width - OUTER_PADDING,
        math.floor((self.headerHeight - self.smallFontHeight) / 2) + 1,
        muted[1], muted[2], muted[3], 1, UIFont.Small)
    self:drawRect(0, self.headerHeight - 1, self.width, 1, 0.55,
        THEME.border[1], THEME.border[2], THEME.border[3])

    if self.collapsed then
        local y = self.headerHeight + OUTER_PADDING
        local rowWidth = self.width - OUTER_PADDING * 2
        local tone = THEME[self:partyTone()] or THEME.muted
        self:drawRect(OUTER_PADDING, y, rowWidth, self.compactRowHeight, 0.62,
            THEME.charcoal[1], THEME.charcoal[2], THEME.charcoal[3])
        self:drawRect(OUTER_PADDING, y, 2, self.compactRowHeight, 0.95,
            tone[1], tone[2], tone[3])
        local text = trimText(UIFont.Small, self:compactSummary(), rowWidth - 16)
        self:drawText(text, OUTER_PADDING + 10,
            y + math.floor((self.compactRowHeight - self.smallFontHeight) / 2),
            0.90, 0.90, 0.86, 1, UIFont.Small)
        return
    end

    local rows = self:visibleRowCount()
    for slot = 1, rows do
        local snapshot = self.snapshots[self.scrollOffset + slot]
        local y = self.headerHeight + OUTER_PADDING
            + (slot - 1) * (self.rowHeight + ROW_GAP)
        local selected = snapshot.id == self.selectedId
        local hovered = slot == self.hoverSlot
        local condition = KnoxSurvivorViewModel ~= nil
            and KnoxSurvivorViewModel.partyCondition ~= nil
            and KnoxSurvivorViewModel.partyCondition(snapshot) or nil
        local conditionLabel = condition ~= nil and condition.label or "Unknown"
        local conditionTone = condition ~= nil and condition.tone or "muted"
        local tone = THEME[conditionTone] or THEME.muted
        local rowX = OUTER_PADDING
        local rowWidth = self.width - OUTER_PADDING * 2
        local fillAlpha = selected and 0.10 or (hovered and 0.06 or 0)
        if fillAlpha > 0 then
            self:drawRect(rowX, y, rowWidth, self.rowHeight, fillAlpha,
                THEME.bone[1], THEME.bone[2], THEME.bone[3])
        end
        if selected or hovered then
            self:drawRect(rowX, y, 2, self.rowHeight, 0.95,
                tone[1], tone[2], tone[3])
        end
        self:drawRect(rowX, y + self.rowHeight - 1, rowWidth, 1, 0.38,
            THEME.border[1], THEME.border[2], THEME.border[3])

        local portraitX = OUTER_PADDING + 3
        local portraitY = y + 3
        local portraitWidth = self.portraitSize - 6
        local portraitHeight = self.rowHeight - 6
        self:drawRect(portraitX, portraitY, portraitWidth, portraitHeight, 0.82,
            THEME.charcoal[1], THEME.charcoal[2], THEME.charcoal[3])
        if AVATAR_TEXTURE ~= nil then
            self:drawTextureScaled(AVATAR_TEXTURE, portraitX, portraitY,
                portraitWidth, portraitHeight, 0.30, 0.38, 0.38, 0.38)
        end
        if not snapshot.loaded or not self.portraitAvailable[slot] then
            self:drawTextCentre(initials(snapshot), portraitX + portraitWidth / 2,
                portraitY + (portraitHeight - self.mediumFontHeight) / 2,
                0.80, 0.80, 0.80, 1, UIFont.Medium)
        end

        local textX = OUTER_PADDING + self.portraitSize + 5
        local textRight = self.width - OUTER_PADDING - 5
        local textWidth = math.max(30, textRight - textX)
        local order = snapshot.order == "hold" and "Holding"
            or (snapshot.order == "relax" and "Relaxing" or "Following")
        local orderWidth = getTextManager():MeasureStringX(UIFont.Small, order)
        self:drawTextRight(order, textRight, y + 5,
            0.68, 0.66, 0.61, 1, UIFont.Small)

        local nameWidth = math.max(20, textWidth - orderWidth - 8)
        self:drawText(trimText(UIFont.Medium, snapshot.displayName, nameWidth),
            textX, y + 5, 0.95, 0.93, 0.88, 1, UIFont.Medium)

        local status = tostring(snapshot.activity or "Unknown")
        if snapshot.distanceTiles ~= nil then
            status = status .. ", " .. tostring(math.floor(snapshot.distanceTiles + 0.5)) .. " tiles"
        end
        self:drawText(trimText(UIFont.Small, status, textWidth), textX,
            y + 8 + self.mediumFontHeight, 0.70, 0.68, 0.63, 1, UIFont.Small)
        -- One line the row has no space for: while a row is hovered its
        -- condition word is replaced by the most actionable fact the
        -- snapshot already carries. The dot keeps the condition's own tone,
        -- so the replacement never changes what the strip reports.
        local conditionText, conditionColour = conditionLabel, tone
        local viewModel = rawget(_G, "KnoxSurvivorViewModel")
        -- Hover replaces the word with a lower-priority detail. A critical
        -- condition is already the answer to "what is wrong?", so it stays.
        local keepCondition = viewModel ~= nil and viewModel.hoverKeepsCondition ~= nil
            and viewModel.hoverKeepsCondition(conditionTone) or false
        if hovered and not keepCondition then
            local detail = viewModel ~= nil and viewModel.partyDetail ~= nil
                and viewModel.partyDetail(snapshot) or nil
            if detail ~= nil then
                conditionText, conditionColour = tostring(detail), THEME.bone
            end
        end
        local conditionY = y + 9 + self.mediumFontHeight + self.smallFontHeight
        self:drawRect(textX, conditionY + 5, 4, 4, 0.95,
            tone[1], tone[2], tone[3])
        local trimmedCondition = trimText(UIFont.Small, conditionText, textWidth - 9)
        self:drawText(trimmedCondition, textX + 9, conditionY,
            conditionColour[1], conditionColour[2], conditionColour[3], 1, UIFont.Small)
        -- One badge for the person who will refuse the next order. It reads the
        -- same gate the order commands do and disappears when the row cannot
        -- spare the width rather than pushing the condition word off the strip.
        local refusal = viewModel ~= nil and viewModel.partyRefusal ~= nil
            and viewModel.partyRefusal(snapshot.orderWillingness) or nil
        if refusal ~= nil then
            local badgeX = textX + 9
                + getTextManager():MeasureStringX(UIFont.Small, trimmedCondition) + 6
            local badgeWidth = getTextManager():MeasureStringX(UIFont.Small, refusal.label)
            if badgeX + badgeWidth <= textRight then
                local badgeTone = THEME[refusal.tone] or THEME.muted
                self:drawText(refusal.label, badgeX, conditionY,
                    badgeTone[1], badgeTone[2], badgeTone[3], 1, UIFont.Small)
            end
        end
    end
end

function Panel:onMouseDown(x, y)
    if y <= self.headerHeight and x >= self.width - self.chevronWidth - 4 then
        self.chevronPressed = true
        return true
    end
    if y <= self.headerHeight then
        self.draggingHeader = true
        self.dragMoved = false
        self:setCapture(true)
        self:bringToTop()
        return true
    end
    return true
end

function Panel:moveHeader(dx, dy)
    if not self.draggingHeader then
        return
    end
    self:setX(self:getX() + dx)
    self:setY(self:getY() + dy)
    self:clampToViewport()
    self.dragMoved = self.dragMoved or dx ~= 0 or dy ~= 0
end

function Panel:onMouseMove(dx, dy)
    self:moveHeader(dx, dy)
    local slot = self:rowAt(self:getMouseY())
    self.hoverSlot = slot
    return true
end

function Panel:onMouseMoveOutside(dx, dy)
    self:moveHeader(dx, dy)
    self.hoverSlot = nil
end

function Panel:onMouseUp(x, y)
    if self.chevronPressed then
        self.chevronPressed = false
        self:toggleCollapsed()
        return true
    end
    if self.collapsed and y > self.headerHeight then
        self:toggleCollapsed()
        return true
    end
    if self.draggingHeader then
        self.draggingHeader = false
        self:setCapture(false)
        if self.dragMoved then
            savePlayerPreferences(self)
        end
        return true
    end
    local _, snapshot = self:rowAt(y)
    if snapshot ~= nil then
        local now = timestampMs()
        if now > 0 and self.lastClickAt > 0 and self.lastClickId == snapshot.id
            and now - self.lastClickAt <= 350 then
            self.lastClickAt, self.lastClickId = 0, nil
            local card = rawget(_G, "KnoxSurvivorCard")
            if card ~= nil and card.show ~= nil then
                pcall(card.show, self.playerNum, snapshot.id)
            end
        else
            self.selectedId = snapshot.id
            self.lastClickAt, self.lastClickId = now, snapshot.id
        end
    end
    return true
end

function Panel:onMouseUpOutside(x, y)
    self.chevronPressed = false
    if self.draggingHeader then
        self.draggingHeader = false
        self:setCapture(false)
        if self.dragMoved then
            savePlayerPreferences(self)
        end
    end
    return true
end

function Panel:onRightMouseUp(x, y)
    if y <= self.headerHeight then
        KnoxPartyCommands.openMenu(
            self.playerNum,
            self:getAbsoluteX() + x,
            self:getAbsoluteY() + y,
            getSpecificPlayer(self.playerNum) ~= nil
                and getSpecificPlayer(self.playerNum):getCurrentSquare() or nil
        )
        return true
    end
    local _, snapshot = self:rowAt(y)
    if snapshot == nil then
        return false
    end
    self.selectedId = snapshot.id
    KnoxSurvivorContextMenu.open(
        self.playerNum,
        snapshot.id,
        self:getAbsoluteX() + x,
        self:getAbsoluteY() + y
    )
    return true
end

function Panel:onMouseWheel(delta)
    if self.collapsed or #self.snapshots <= self.visibleCapacity then
        return false
    end
    local nextOffset = clamp(self.scrollOffset - delta, 0, self:maximumScrollOffset())
    if nextOffset ~= self.scrollOffset then
        self.scrollOffset = nextOffset
        self:refreshPortraits()
    end
    return true
end

function Panel:new(playerNum)
    local panel = ISPanel.new(self, 0, 0, 224, 40)
    panel.playerNum = playerNum
    panel.snapshots = {}
    panel.portraits = {}
    panel.portraitAvailable = {}
    panel.scrollOffset = 0
    panel.visibleCapacity = MAX_PORTRAITS
    panel.compactRowHeight = 24
    panel.chevronWidth = 16
    panel.chevronPressed = false
    panel.selectedId = nil
    panel.hoverSlot = nil
    panel.lastClickAt = 0
    panel.lastClickId = nil
    panel.draggingHeader = false
    panel.dragMoved = false
    panel.backgroundColor = { r = THEME.charcoal[1], g = THEME.charcoal[2],
        b = THEME.charcoal[3], a = 0.94 }
    panel.borderColor = { r = THEME.border[1], g = THEME.border[2],
        b = THEME.border[3], a = 0.92 }
    panel:calculateMetrics()
    local stored = playerPreferences(playerNum)
    panel.manualPosition = type(stored) == "table"
        and stored.x ~= nil and stored.y ~= nil
    panel.collapsed = type(stored) == "table" and stored.collapsed == true
    return panel
end

-- The base line is deliberately not a second window. It is one strip that
-- exists only while the player is inside an owned territory, and it opens the
-- existing Base & Work surface. The world stays the primary interface.
-- The base strip wears the same material as the notice rail: one charcoal
-- sheet, one hairline border, bone text and the amber accent only where
-- something needs the player. Reading the shared tokens instead of typing
-- colours here is what keeps the two surfaces from drifting apart.
local function themeColour(token, fallback)
    local layout = rawget(_G, "KnoxSurvivorUILayout")
    local theme = type(layout) == "table" and layout.theme or nil
    local value = type(theme) == "table" and theme[token] or nil
    return type(value) == "table" and value or fallback
end

local BaseLine = ISPanel:derive("KnoxBaseLinePanel")

function BaseLine:calculateMetrics()
    local small = getTextManager():getFontHeight(UIFont.Small)
    self.smallFontHeight = small
    local scale = math.max(1, small / 14)
    self:setWidth(math.min(math.floor(300 * scale),
        math.max(1, getPlayerScreenWidth(self.playerNum) - OUTER_PADDING * 2)))
    self.rowHeight = math.max(24, small + 10)
    self:setHeight(self.rowHeight
        + (self.expanded == true and math.max(20, small + 8) or 0))
end

function BaseLine:layout()
    local left, top, width, height = screenBounds(self.playerNum)
    local lineWidth = self:getWidth()
    local lineHeight = self:getHeight()
    local x, y
    local party = panels[self.playerNum]
    if party ~= nil and party:isVisible() then
        x = party:getX() + party:getWidth() - lineWidth
        y = party:getY() + party:getHeight() + 6
        if y + lineHeight > top + height - OUTER_PADDING then
            y = party:getY() - lineHeight - 6
        end
    else
        x = left + width - OUTER_PADDING - lineWidth
        y = top + OUTER_PADDING
        local reserved = visibleTopRightBottom(top, height)
        if reserved ~= nil then
            y = math.max(y, reserved + 6)
        end
        local moodles = UIManager.getMoodleUI(self.playerNum)
        if moodles ~= nil and moodles:isVisible() then
            y = math.max(y, moodles:getAbsoluteY()
                + moodles:getHeight() + 6)
        end
    end
    self:setX(clamp(x, left, left + width - lineWidth))
    self:setY(clamp(y, top, top + height - lineHeight))
    self:stayOnSplitScreen(self.playerNum)
end

function BaseLine:refresh(force)
    local player = activePlayer(self.playerNum)
    if player == nil or not KnoxSettings.showCompanionHUD() then
        self.base, self.status = nil, nil
        self:setVisible(false)
        return false
    end
    local notebook = rawget(_G, "KnoxSurvivorNotebook")
    if notebook ~= nil and notebook.window ~= nil
        and notebook.window:isVisible() then
        self:setVisible(false)
        return false
    end
    self.playerId = KnoxPersistence.ensurePlayerId(player)
    local square = player:getCurrentSquare()
    local base = square ~= nil and KnoxBaseManager.playerBaseAtSquare(square) or nil
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= self.playerId then
        self.base, self.status = nil, nil
        self:setVisible(false)
        return false
    end
    local status = KnoxBaseManager.homeStatus ~= nil
        and KnoxBaseManager.homeStatus(base, self.playerId, force == true) or nil
    if status == nil or (status.home + status.away + status.dead
        + (status.missing or 0)) == 0 then
        self.base, self.status = nil, nil
        self:setVisible(false)
        return false
    end
    local small = getTextManager():getFontHeight(UIFont.Small)
    local model = KnoxBaseManager.baseLineModel ~= nil
        and KnoxBaseManager.baseLineModel(status) or nil
    local expanded = model ~= nil and model.expanded == true
    if self.smallFontHeight ~= small or self.expanded ~= expanded then
        self.expanded = expanded
        self:calculateMetrics()
    end
    self.base, self.status, self.model = base, status, model
    self:setVisible(true)
    self:layout()
    return true
end

function BaseLine:prerender()
    ISPanel.prerender(self)
    if self.base == nil or self.status == nil then return end
    local model = self.model
    local attention = model ~= nil and model.attention
        or tonumber(self.status.attention) or 0
    local dead = model ~= nil and model.dead
        or tonumber(self.status.dead) or 0
    local charcoal = themeColour("charcoal", THEME.charcoal)
    local bone = themeColour("bone", THEME.bone)
    local muted = themeColour("muted", THEME.muted)
    local border = themeColour("border", { 0.290, 0.275, 0.247 })
    local amber = themeColour("amber", { 0.851, 0.643, 0.255 })
    local red = themeColour("red", { 0.769, 0.333, 0.247 })
    self:drawRect(0, 0, self:getWidth(), self:getHeight(), 0.90,
        charcoal[1], charcoal[2], charcoal[3])
    self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(),
        self.hovered and 0.90 or 0.62, border[1], border[2], border[3])
    if attention > 0 then
        self:drawRect(0, 0, 2, self:getHeight(), 0.95,
            amber[1], amber[2], amber[3])
    end
    local textY = math.floor(((self.rowHeight or self:getHeight())
        - self.smallFontHeight) / 2)
    local name = trimText(UIFont.Small, tostring(self.base.name or "Base"),
        math.floor(self:getWidth() * 0.42))
    self:drawText(name, OUTER_PADDING, textY, bone[1], bone[2], bone[3], 1,
        UIFont.Small)
    local parts = { tostring(self.status.home or 0) .. " home" }
    if (self.status.away or 0) > 0 then
        parts[#parts + 1] = tostring(self.status.away) .. " away"
    end
    if (self.status.missing or 0) > 0 then
        parts[#parts + 1] = tostring(self.status.missing) .. " missing"
    end
    if dead > 0 then parts[#parts + 1] = tostring(dead) .. " dead" end
    if attention > 0 then
        parts[#parts + 1] = attention == 1 and "1 needs you"
            or (tostring(attention) .. " need you")
    else
        parts[#parts + 1] = model ~= nil and model.quietLabel or "no known issues"
    end
    -- "4 home, 2 away" with a middle dot rendered as nothing on some fonts is
    -- the same defect the hour ranges had, so the strip uses the ASCII form.
    local summary = table.concat(parts, " - ")
    local nameWidth = getTextManager():MeasureStringX(UIFont.Small, name)
    summary = trimText(UIFont.Small, summary,
        math.max(1, self:getWidth() - OUTER_PADDING * 2 - nameWidth - 8))
    local r, g, b = muted[1], muted[2], muted[3]
    if dead > 0 then
        r, g, b = red[1], red[2], red[3]
    elseif attention > 0 then
        r, g, b = amber[1], amber[2], amber[3]
    end
    self:drawTextRight(summary, self:getWidth() - OUTER_PADDING, textY,
        r, g, b, 1, UIFont.Small)
    if model ~= nil and model.expanded then
        local action = tostring(model.actionLabel or "Review")
        local actionWidth = getTextManager():MeasureStringX(UIFont.Small, action)
        local titleLimit = math.max(1, self:getWidth() - OUTER_PADDING * 2
            - actionWidth - 8)
        local title = trimText(UIFont.Small, model.title or "", titleLimit)
        local rowTop = self.rowHeight or 24
        local rowY = rowTop + math.floor((self:getHeight() - rowTop
            - self.smallFontHeight) / 2)
        self:drawRect(0, rowTop, self:getWidth(), 1, 0.55,
            border[1], border[2], border[3])
        self:drawText(title, OUTER_PADDING, rowY, amber[1], amber[2], amber[3], 1,
            UIFont.Small)
        self:drawTextRight(action, self:getWidth() - OUTER_PADDING, rowY,
            amber[1], amber[2], amber[3], 1, UIFont.Small)
    end
end

function BaseLine:onMouseDown(x, y)
    return true
end

function BaseLine:onMouseUp(x, y)
    local notebook = rawget(_G, "KnoxSurvivorNotebook")
    if notebook ~= nil and notebook.show ~= nil then
        local model = self.model
        local actionRow = model ~= nil and model.expanded == true
            and (tonumber(y) or 0) >= (self.rowHeight or self:getHeight())
        self:setVisible(false)
        if actionRow and model.itemKey ~= nil then
            notebook.show(self.playerNum, "Base & Work", model.itemKey)
        else
            notebook.show(self.playerNum, "Base & Work")
        end
    end
    return true
end

function BaseLine:onMouseMove(dx, dy)
    self.hovered = true
    return true
end

function BaseLine:onMouseMoveOutside(dx, dy)
    self.hovered = false
end

function BaseLine:new(playerNum)
    local line = ISPanel.new(self, 0, 0, 300, 24)
    line.playerNum = playerNum
    line.playerId = nil
    line.base = nil
    line.status = nil
    line.model = nil
    line.expanded = false
    line.rowHeight = 24
    line.hovered = false
    line.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.88 }
    line.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.92 }
    line:calculateMetrics()
    line:setVisible(false)
    return line
end

local function destroyBaseLine(playerNum)
    local line = baseLines[playerNum]
    if line == nil then return end
    line:setVisible(false)
    line:removeFromUIManager()
    baseLines[playerNum] = nil
end

local function ensureBaseLine(playerNum)
    if not KnoxSettings.showCompanionHUD() then
        destroyBaseLine(playerNum)
        return nil
    end
    local player = activePlayer(playerNum)
    if player == nil then
        destroyBaseLine(playerNum)
        return nil
    end
    local line = baseLines[playerNum]
    if line == nil then
        line = BaseLine:new(playerNum)
        line:initialise()
        line:setRenderThisPlayerOnly(playerNum)
        line:addToUIManager()
        baseLines[playerNum] = line
    end
    return line
end

local function refreshBaseLine(playerNum, force)
    local line = ensureBaseLine(playerNum)
    if line ~= nil then line:refresh(force == true) end
end

local function destroyPanel(playerNum)
    local panel = panels[playerNum]
    if panel == nil then
        return
    end
    panel:releaseAllPortraits()
    panel:setVisible(false)
    panel:removeFromUIManager()
    panels[playerNum] = nil
end

local function ensurePanel(playerNum)
    if not KnoxSettings.showCompanionHUD() then
        destroyPanel(playerNum)
        return nil
    end
    local player = activePlayer(playerNum)
    if player == nil then
        destroyPanel(playerNum)
        return nil
    end
    local panel = panels[playerNum]
    if panel == nil then
        panel = Panel:new(playerNum)
        panel:initialise()
        panel:setRenderThisPlayerOnly(playerNum)
        panel:addToUIManager()
        panels[playerNum] = panel
    end
    return panel
end

function CompanionHUD.refresh(playerNum)
    if playerNum ~= nil then
        local n = tonumber(playerNum)
        if n == nil then return end
        local panel = ensurePanel(n)
        if panel ~= nil then
            panel:refresh(false)
        end
        refreshBaseLine(n, false)
        return
    end
    for index = 0, MAX_LOCAL_PLAYERS - 1 do
        local panel = ensurePanel(index)
        if panel ~= nil then
            panel:refresh(false)
        end
        refreshBaseLine(index, false)
    end
end

function CompanionHUD.destroyAll()
    local ids, seen = {}, {}
    for playerNum in pairs(panels) do
        if not seen[playerNum] then
            seen[playerNum] = true
            ids[#ids + 1] = playerNum
        end
    end
    for playerNum in pairs(baseLines) do
        if not seen[playerNum] then
            seen[playerNum] = true
            ids[#ids + 1] = playerNum
        end
    end
    for _, playerNum in ipairs(ids) do
        destroyPanel(playerNum)
        destroyBaseLine(playerNum)
    end
end

local function onTick()
    local now = getTimestampMs()
    if now < nextRefreshAt then
        return
    end
    nextRefreshAt = now + REFRESH_MS
    if not KnoxSettings.showCompanionHUD() then
        CompanionHUD.destroyAll()
        return
    end
    CompanionHUD.refresh()
end

local function onCreatePlayer(playerNum)
    for index = 0, MAX_LOCAL_PLAYERS - 1 do
        local panel = ensurePanel(index)
        if panel ~= nil then
            panel:refresh(true)
        end
        refreshBaseLine(index, true)
    end
end

local function onPlayerDeath(player)
    if player ~= nil then
        destroyPanel(player:getPlayerNum())
        destroyBaseLine(player:getPlayerNum())
    end
end

local function onResolutionChange()
    for _, panel in pairs(panels) do
        panel:refresh(true)
    end
    for _, line in pairs(baseLines) do
        line:refresh(true)
    end
end

local function onGameStart()
    CompanionHUD.destroyAll()
    nextRefreshAt = 0
    CompanionHUD.refresh()
end

local function onMainMenuEnter()
    CompanionHUD.destroyAll()
    nextRefreshAt = 0
end

Events.OnTick.Add(onTick)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnResolutionChange.Add(onResolutionChange)
Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

return CompanionHUD
