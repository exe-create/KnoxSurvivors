require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISTabPanel"
require "ISUI/ISUI3DModel"
require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISHealthPanel"
require "XpSystem/ISUI/ISCharacterProtection"
require "XpSystem/ISUI/ISClothingInsPanel"
require "KS_SurvivorViewModel"
local CompanionInventory = require "KS_CompanionInventory"
local UILayout = require "KS_SurvivorUILayout"
-- Keep the card usable when the module was loaded earlier by another UI.
-- Lua's `require` returns the canonical table, while the global is only an
-- implementation detail of the inventory module.
if CompanionInventory == nil then
    CompanionInventory = rawget(_G, "KnoxCompanionInventory")
end

local SurvivorCard = rawget(_G, "KnoxSurvivorCard") or {}
_G.KnoxSurvivorCard = SurvivorCard

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorCardWindow")

local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 500
local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 540
local PADDING = 10
local SECTION_GAP = 8

local COL_BG      = { 0.06, 0.06, 0.06 }
local COL_BORDER  = { 0.28, 0.28, 0.28 }
local COL_SEC_BG  = { 0.10, 0.10, 0.10 }
local COL_SEC_HDR = { 0.70, 0.70, 0.68 }
local COL_LABEL   = { 0.62, 0.62, 0.60 }
local COL_VALUE   = { 0.88, 0.88, 0.85 }
local COL_DIM     = { 0.52, 0.52, 0.50 }
local COL_ACCENT  = { 0.48, 0.56, 0.38 }

-- Vanilla ISScrollBar is 17 wide. Custom-drawn scrollers always reserve it
-- so right-aligned values never slide under the bar when it appears, and
-- the layout never shifts by its width.
local VSCROLL_W = 18

local windows = {}
local nextRefreshAt = 0

local function developerDiagnosticsEnabled()
    local settings = rawget(_G, "KnoxSettings")
    if settings == nil or settings.showDeveloperDiagnostics == nil then return false end
    local ok, enabled = pcall(settings.showDeveloperDiagnostics)
    return ok and enabled == true
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function trimText(font, text, maximumWidth)
    local value = tostring(text or "")
    if getTextManager():MeasureStringX(font, value) <= maximumWidth then
        return value
    end
    local suffix = "..."
    while #value > 1
        and getTextManager():MeasureStringX(font, value .. suffix) > maximumWidth do
        value = string.sub(value, 1, #value - 1)
    end
    return value .. suffix
end

local function dayLabel(value)
    local days = tonumber(value)
    if days == nil then
        return "Unknown"
    end
    days = math.max(0, math.floor(days))
    return tostring(days) .. (days == 1 and " day" or " days")
end

local function compactList(values, maximum)
    local output = {}
    for _, value in ipairs(values or {}) do
        if type(value) == "string" and value ~= "" then
            output[#output + 1] = value
            if #output >= (maximum or 3) then break end
        end
    end
    return #output > 0 and table.concat(output, ", ") or "None"
end

local function compactSkills(values, maximum)
    local output = {}
    for id, saved in pairs(values or {}) do
        local level = type(saved) == "table" and tonumber(saved.level) or nil
        if level ~= nil and level > 0 then
            output[#output + 1] = { id = tostring(id), level = math.floor(level) }
        end
    end
    table.sort(output, function(a, b)
        if a.level == b.level then return a.id < b.id end
        return a.level > b.level
    end)
    local labels = {}
    for index = 1, math.min(#output, maximum or 3) do
        labels[#labels + 1] = output[index].id .. " " .. tostring(output[index].level)
    end
    return #labels > 0 and table.concat(labels, ", ") or "No trained skills yet"
end

local function companionSnapshot(playerNum, survivorId)
    for _, snapshot in ipairs(KnoxSurvivorViewModel.getForPlayer(playerNum) or {}) do
        if snapshot.id == survivorId then
            return snapshot
        end
    end
    -- Base residents and known survivors are listed by the Notebook but are
    -- not in the companion roster. Fall back to the full record so View Card
    -- works for them instead of silently doing nothing.
    if KnoxSurvivorViewModel.getSurvivor ~= nil then
        local ok, snapshot = pcall(function()
            return KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)
        end)
        if ok and snapshot ~= nil then
            return snapshot
        end
    end
    return nil
end

-- Vanilla (re)creates the appearance buttons in createChildren, which can run
-- after our first hide. Force them off every render: the card is read-only
-- and those menus crash for off-slot survivors.
local function hideAppearanceButtons(view)
    if view == nil then return end
    if view.hairButton ~= nil then view.hairButton:setVisible(false) end
    if view.beardButton ~= nil then view.beardButton:setVisible(false) end
    if view.literatureButton ~= nil then view.literatureButton:setVisible(false) end
end

local function screenBounds(playerNum)
    return getPlayerScreenLeft(playerNum),
        getPlayerScreenTop(playerNum),
        getPlayerScreenWidth(playerNum),
        getPlayerScreenHeight(playerNum)
end

-- Visible content bottom for views whose vanilla extent covers hidden
-- rows (the temperature panel pre-builds Simple and Advanced groups and
-- reports one constant height). Scrollbars and hidden children are
-- skipped so each style scrolls exactly to its own content.
local function visibleContentBottom(view, fallback)
    local content = tonumber(fallback) or 0
    if view == nil or view.children == nil then return content end
    for _, child in pairs(view.children) do
        if child ~= nil and child ~= view.vscroll and child ~= view.hscroll then
            local visible = true
            if child.getIsVisible ~= nil then
                local ok, flag = pcall(function() return child:getIsVisible() end)
                if ok then visible = flag ~= false end
            end
            if visible and child.getY ~= nil and child.getHeight ~= nil then
                local ok, bottom = pcall(function()
                    return (child:getY() or 0) + (child:getHeight() or 0)
                end)
                if ok and tonumber(bottom) ~= nil and bottom > content then
                    content = bottom
                end
            end
        end
    end
    return content
end

local function restoreJoypadFocus(window)
    local joypadData = JoypadState.players[window.playerNum + 1]
    if joypadData == nil or getJoypadFocus(window.playerNum) ~= window then
        return
    end
    local previous = window.previousJoypadFocus
    if previous == window then
        previous = nil
    end
    if previous ~= nil then
        local success, visible = pcall(function()
            if previous.isReallyVisible ~= nil then
                return previous:isReallyVisible()
            end
            return previous:getIsVisible()
        end)
        if not success or not visible then
            previous = nil
        end
    end
    setJoypadFocus(window.playerNum, previous)
end

local function fitViews(window)
    -- The window is user-resizable but tab views are sized at creation, so
    -- a manual resize otherwise leaves stale sizes behind: clipped content,
    -- floating rows and wrong scrollbars until a resolution change.
    if window.panel == nil then return end
    for _, v in ipairs(window.panel.viewList or {}) do
        if v.view ~= nil then
            UILayout.fitView(v.view)
        end
    end
end

-- Knox tab — misc history / current job only. Vanilla tabs now cover portrait, traits, skills, health, protection, temperature.
local KnoxPanel = ISPanelJoypad:derive("KnoxSurvivorKnoxPanel")

function KnoxPanel:prerender()
    ISPanelJoypad.prerender(self)
    local snapshot = self.snapshot
    if snapshot == nil then return end
    -- These are shortcuts into the same survivor interaction paths exposed by
    -- the world context menu. Keep the card informational; inventory transfer
    -- and treatment stay wholly owned by the vanilla inventory/medical UI.
    local survivorLoaded = snapshot.loaded == true
    if self.inventoryButton ~= nil then
        self.inventoryButton:setEnable(survivorLoaded)
        local tooltip = not survivorLoaded
            and "Inventory is available when this survivor is nearby." or nil
        if self.inventoryButton.tooltip ~= tooltip then self.inventoryButton:setTooltip(tooltip) end
    end
    if self.medicalButton ~= nil then
        self.medicalButton:setEnable(survivorLoaded)
        local tooltip = not survivorLoaded
            and "A medical check is available when this survivor is nearby." or nil
        if self.medicalButton.tooltip ~= tooltip then self.medicalButton:setTooltip(tooltip) end
    end
    local smallH = getTextManager():getFontHeight(UIFont.Small)
    local y = PADDING
    local w = self.width - PADDING * 2 - VSCROLL_W

    local function sectionHeader(title)
        self:drawRect(PADDING, y, w, smallH + 4, 0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
        self:drawText(title:upper(), PADDING + 6, y + 2, COL_SEC_HDR[1], COL_SEC_HDR[2], COL_SEC_HDR[3], 0.8, UIFont.Small)
        y = y + smallH + 8
    end
    local function keyValue(label, value, col)
        local c = col or COL_VALUE
        self:drawText(tostring(label), PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
        local labelWidth = getTextManager():MeasureStringX(UIFont.Small, tostring(label)) + PADDING
        self:drawTextRight(trimText(UIFont.Small, tostring(value or "Unknown"), math.max(1, w - labelWidth)), PADDING + w, y, c[1], c[2], c[3], 1, UIFont.Small)
        y = y + smallH + 4
    end

    self:drawText(trimText(UIFont.Medium, snapshot.displayName, w), PADDING, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Medium)
    local mediumH = getTextManager():getFontHeight(UIFont.Medium)
    y = y + mediumH + 4
    local age = snapshot.ageYears ~= nil and "Age " .. tostring(snapshot.ageYears) or ""
    if age ~= "" then
        self:drawText(age, PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
        y = y + smallH + 2
    end
    self:drawText("Survived " .. dayLabel(snapshot.daysSurvived) .. "  |  Known " .. dayLabel(snapshot.daysKnown), PADDING, y, COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
    y = y + smallH + SECTION_GAP

    sectionHeader("History")
    keyValue("Time Alive", dayLabel(snapshot.daysSurvived))
    keyValue("Known", dayLabel(snapshot.daysKnown))
    keyValue("Personality", snapshot.personalityLabel or "Unknown")
    local recentHistory = type(snapshot.recentHistory) == "table" and snapshot.recentHistory or {}
    if #recentHistory == 0 then
        keyValue("Recent Memory", "Not reported")
    else
        for index = 1, math.min(3, #recentHistory) do
            local entry = recentHistory[index]
            local memory = tostring(type(entry) == "table" and entry.label or "Survived offscreen")
            local detail = type(entry) == "table" and entry.detail or nil
            if type(detail) == "string" and detail ~= "" then
                detail = detail:gsub("[\r\n\t]", " ")
                memory = memory .. " — " .. detail
            end
            self:drawText(trimText(UIFont.Small, memory, w), PADDING, y,
                COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
            y = y + smallH + 3
        end
    end
    y = y + 4
    sectionHeader("Current Job")
    local job = snapshot.duty ~= nil and snapshot.duty.jobPreference or nil
    if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeBasePreference ~= nil then
        job = KnoxOrderCatalog.normalizeBasePreference(job)
    end
    if job ~= nil and job ~= "" and job ~= "auto" then
        keyValue("Job", job:sub(1,1):upper() .. job:sub(2))
    else
        keyValue("Job", "Automatic")
    end
    keyValue("Purpose", snapshot.lifeIntent ~= nil and snapshot.lifeIntent.label or nil)
    keyValue("Location", snapshot.locationLabel)
    keyValue("Order", snapshot.orderLabel)
    local status = snapshot.activity or "Idle"
    if snapshot.distanceTiles ~= nil then
        status = status .. " (" .. tostring(math.floor(snapshot.distanceTiles + 0.5)) .. " tiles)"
    end
    keyValue("Activity", status)
    keyValue("Needs", snapshot.needSummary or "Not reported")
    if snapshot.knowledge ~= nil and snapshot.knowledge.reportAtHours ~= nil then
        local age = math.max(0,getGameTime():getWorldAgeHours()-snapshot.knowledge.reportAtHours)
        keyValue("Needs report", tostring(math.floor(age*60)) .. " min ago (self-report)")
    end
    y = y + 4
    sectionHeader("Condition")
    if snapshot.knowledge ~= nil and snapshot.knowledge.reportAtHours ~= nil then
        keyValue("Values", "Last self-report; current condition unknown")
    end
    do
        local vitals = snapshot.vitals or {}
        local needs = snapshot.needs or {}
        local function needBar(label, fraction, higherIsWorse)
            local value = tonumber(fraction)
            self:drawText(tostring(label), PADDING, y,
                COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
            if value == nil then
                self:drawTextRight("Unknown", PADDING + w, y,
                    COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
            else
                value = math.max(0, math.min(1, value))
                local bad = higherIsWorse and value or (1 - value)
                local col = bad >= 0.65 and { 1, 0.3, 0.3 }
                    or (bad >= 0.35 and { 1, 0.85, 0.3 } or { 0.55, 0.85, 0.45 })
                local pct = tostring(math.floor(value * 100 + 0.5)) .. "%"
                self:drawTextRight(pct, PADDING + w, y, col[1], col[2], col[3], 1, UIFont.Small)
                local barW = math.max(20, w - 170)
                local bx = PADDING + 100
                self:drawRect(bx, y + 3, barW, 9, 0.4, 0.02, 0.02, 0.02)
                self:drawRect(bx, y + 3, math.max(1, barW * value), 9, 0.9,
                    col[1], col[2], col[3])
            end
            y = y + smallH + 4
        end
        local health = vitals.health
        if health == nil then health = snapshot.health end
        needBar("Health", health, false)
        needBar("Food", needs.food, false)
        needBar("Water", needs.water, false)
        needBar("Sleep", needs.sleep ~= nil and needs.sleep or needs.rest, false)
        needBar("Endurance", needs.endurance, false)
    end
    y = y + 4
    sectionHeader("Relationship")
    keyValue("Faction", snapshot.factionName or "None")
    local trustLabel = snapshot.trustLabel or "Unknown"
    local trustCol = trustLabel == "Trusting" and COL_ACCENT
        or (trustLabel == "Cautious" and COL_VALUE or COL_DIM)
    keyValue("Trust", trustLabel, trustCol)
    keyValue("Meetings", snapshot.relationshipMeetings ~= nil
        and tostring(math.max(0, math.floor(snapshot.relationshipMeetings))) or nil)
    if snapshot.isSpouse then keyValue("Relationship", "Spouse", COL_ACCENT) end
    keyValue("Group", snapshot.affiliation and snapshot.affiliation.kind or "independent")
    local buttonH = smallH + 10
    -- Pin the buttons to the content end, or the panel bottom when the
    -- content is short, so they never float mid-panel with dead space
    -- below. Scroll height and button position only rewrite on change:
    -- vanilla clamps the scroll offset on every setScrollHeight, so
    -- per-frame rewrites are what made the bar jump.
    local buttonY = y + SECTION_GAP
    local minButtonY = self.height - buttonH - PADDING
    if buttonY < minButtonY then buttonY = minButtonY end
    if self.knoxButtonY ~= buttonY then
        self.knoxButtonY = buttonY
        self.inventoryButton:setY(buttonY)
        self.medicalButton:setY(buttonY)
    end
    local contentH = buttonY + buttonH + PADDING
    if self.knoxScrollH ~= contentH then
        self.knoxScrollH = contentH
        self:setScrollHeight(contentH)
    end
end

function KnoxPanel:onInventoryButton()
    if self.window == nil or self.window.snapshot == nil then return end
    if CompanionInventory == nil or CompanionInventory.show == nil then return end
    CompanionInventory.show(self.window.playerNum, self.window.survivorId)
end

function KnoxPanel:onMedicalButton()
    if self.window == nil or self.window.snapshot == nil then return end
    -- KS_SurvivorContextMenu loads this card before it finishes defining its
    -- callbacks, so resolve the public service at click time rather than form a
    -- cyclic module dependency here.
    local context = rawget(_G, "KnoxSurvivorContextMenu")
    if context ~= nil and context.medicalCheck ~= nil then
        context.medicalCheck(self.window.playerNum, self.window.survivorId)
    end
end

function KnoxPanel:createChildren()
    ISPanelJoypad.createChildren(self)
    local buttonH = getTextManager():getFontHeight(UIFont.Small) + 10
    self.inventoryButton = ISButton:new(PADDING, self.height - buttonH - PADDING, 122, buttonH,
        "Inventory", self, KnoxPanel.onInventoryButton)
    self.inventoryButton:initialise()
    self:addChild(self.inventoryButton)
    self.medicalButton = ISButton:new(PADDING + 130, self.height - buttonH - PADDING, 122, buttonH,
        "Medical Check", self, KnoxPanel.onMedicalButton)
    self.medicalButton:initialise()
    self:addChild(self.medicalButton)
end

function KnoxPanel:new(x, y, width, height)
    local o = ISPanelJoypad.new(self, x, y, width, height)
    o:noBackground()
    o:setScrollChildren(true)
    o:addScrollBars()
    o:setScrollWithParent(false)
    o.snapshot = nil
    o.window = nil
    return o
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    -- ISTabPanel matching ISCharacterInfoWindow:117 — tabPadX 10, equalTabWidth false
    self.panel = ISTabPanel:new(0, th, self.width, self.height - th - rh)
    self.panel:initialise()
    self.panel.tabPadX = 10
    self.panel.equalTabWidth = false
    self.panel:setAnchorRight(true)
    self.panel:setAnchorBottom(true)
    self:addChild(self.panel)

    -- Views are created lazily when survivor is known so they can bind to the correct IsoPlayer.
    self.infoView = nil
    self.skillsView = nil
    self.healthView = nil
    self.knoxView = nil
end

local function ensureViews(window)
    if window.panel == nil then return end
    local survivor = window.snapshot ~= nil and window.snapshot.loaded
        and KnoxSurvivorViewModel.resolveLiveCharacter(window.snapshot.id) or nil

    -- Native body/portrait children retain the original character. Recreate on
    -- selection or shell changes, including unload, rather than showing stale data.
    local activeName = window.panel.activeView and window.panel.activeView.name
    if window.boundSurvivor ~= survivor then
        for _, field in ipairs({"infoView", "skillsView", "healthView", "protectionView", "clothingView"}) do
            local view = window[field]
            if view ~= nil then
                view:setVisible(false)
                window.panel:removeView(view)
                window[field] = nil
            end
        end
        window.boundSurvivor = survivor
    end

    -- A persisted survivor can be known to the Notebook while its live shell
    -- is streamed out. Vanilla character views dereference `char` during
    -- addView/prerender, so keep the Knox tab available and wait for a real
    -- IsoPlayer before creating those views.
    if survivor ~= nil and window.infoView == nil then
        local view = ISCharacterScreen:new(0, 8, window.panel.width, 400, window.playerNum)
        view:initialise()
        view:setScrollChildren(true)
        view:addScrollBars()
        view:setScrollWithParent(false)
        view.setWidthAndParentWidth = function(self, w) self:setWidth(math.min(w, self.parent and self.parent.width or w)) end
        view.setHeightAndParentHeight = function(self, h)
            self:setHeight(h)
            local avail = self.parent and self.parent:getHeight() or h
            self:setScrollHeight(math.max(h, avail))
        end
        view.char = survivor
        view.playerNum = survivor ~= nil and survivor:getPlayerNum() or -1
        view.knoxWindow = window
        -- The card is intentionally read-only.  Build 42's health context
        -- menu is local-player UI and calls ISContextMenu.get(playerNum);
        -- off-slot survivors have no valid menu slot, so suppress that path
        -- instead of allowing a vanilla nil-menu exception.
        view.doBodyPartContextMenu = function() end
        if view.listbox ~= nil then view.listbox.onRightMouseUp = function() end end
        if view.bodyPartPanel ~= nil then view.bodyPartPanel.onRightMouseUp = function() end end
        -- These vanilla menus own local-player UI panels and crash when their
        -- callback is invoked for an off-slot survivor. The survivor card is
        -- read-only; disable the callbacks as well as hiding their buttons.
        view.hairMenu = function() end
        view.beardMenu = function() end
        view.literatureMenu = function() end
        if survivor ~= nil then
            view.bFemale = survivor:isFemale()
            view.refreshNeeded = true
            pcall(function() view:loadTraits() end)
            pcall(function() view:loadProfession() end)
            view:loadBeardAndHairStyle()
        end
        -- Hide vanilla change buttons for survivor — no haircut and no discovered media here.
        if view.hairButton ~= nil then view.hairButton:setVisible(false); view.hairButton:setEnable(false) end
        if view.beardButton ~= nil then view.beardButton:setVisible(false); view.beardButton:setEnable(false) end
        if view.literatureButton ~= nil then view.literatureButton:setVisible(false); view.literatureButton:setEnable(false) end
        -- Augment vanilla Info with Knox fields (relationship/faction/base) using restrained style.
        local origRender = view.render
        view.render = function(self)
            hideAppearanceButtons(self)
            origRender(self)
            local snap = self.knoxWindow and self.knoxWindow.snapshot or nil
            if snap == nil then return end
            -- Measured metrics, not fixed pixels: at scaled UI fonts the
            -- old 16px rows overlapped each other.
            local smallH = getTextManager():getFontHeight(UIFont.Small)
            local rowH = smallH + 4
            local y = (self.knoxContentHeight or self:getHeight()) + 10
            local w = math.max(20, self.width - 20 - VSCROLL_W)
            self:drawRect(10, y, w, 1, 0.5, COL_BORDER[1], COL_BORDER[2], COL_BORDER[3])
            y = y + 8
            self:drawRect(10, y, w, rowH, 0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
            self:drawText("KNOX", 16, y + 2, COL_SEC_HDR[1], COL_SEC_HDR[2], COL_SEC_HDR[3], 0.8, UIFont.Small)
            y = y + rowH + 4
            local function kv(label, value)
                local vw = math.max(20, w - 70)
                self:drawText(tostring(label), 10, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
                self:drawTextRight(trimText(UIFont.Small, tostring(value or "Unknown"), vw), 10 + w, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
                y = y + rowH
            end
            kv("Time Alive", dayLabel(snap.daysSurvived))
            kv("Known", dayLabel(snap.daysKnown))
            kv("Faction", snap.factionName or "None")
            kv("Trust", snap.trustLabel or "Unknown")
            kv("Meetings", snap.relationshipMeetings ~= nil
                and tostring(math.max(0, math.floor(snap.relationshipMeetings))) or "Unknown")
            kv("Purpose", snap.lifeIntent and snap.lifeIntent.label or "Unknown")
            if snap.isSpouse then kv("Relationship", "Spouse") end
            kv("Group", snap.affiliation and snap.affiliation.kind or "independent")
            local job = snap.duty and snap.duty.jobPreference or nil
            if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeBasePreference ~= nil then
                job = KnoxOrderCatalog.normalizeBasePreference(job)
            end
            if job ~= nil and job ~= "" and job ~= "auto" then kv("Base Job", job:sub(1,1):upper()..job:sub(2)) end
            kv("Base / Activity", trimText(UIFont.Small, snap.locationLabel .. " — " .. (snap.orderLabel or ""), w - 70))
            local act = snap.activity or "Idle"
            if snap.distanceTiles ~= nil then act = act .. " (" .. tostring(math.floor(snap.distanceTiles+0.5)) .. " tiles)" end
            kv("Activity", act)
            local nh = y + 6
            -- Same clamp churn as the Knox tab: only rewrite when the
            -- appended block actually changed height.
            if self.knoxScrollH ~= nh then
                self.knoxScrollH = nh
                self:setScrollHeight(math.max(nh, self:getHeight()))
            end
        end
        window.infoView = view
        window.panel:addView(xpSystemText.info, view)
        UILayout.bindView(view)
    end
    if survivor ~= nil and window.skillsView == nil then
        local view = ISCharacterInfo:new(0, 8, window.panel.width, window.panel.height - 8, window.playerNum)
        view:initialise()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        view.char = survivor
        -- ISSkillProgressBar:new() resolves getSpecificPlayer(playerNum) inside
        -- its constructor. Keep the real local UI owner here, then bind every
        -- created vanilla bar to the selected off-slot survivor before child
        -- rendering. The panel itself already reads skill data from view.char.
        view.playerNum = window.playerNum
        view.knoxSnapshot = window.snapshot
        local vanillaSkillsRender = view.render
        view.render = function(self)
            vanillaSkillsRender(self)
            if self.char == nil then return end
            for _, progressBar in ipairs(self.progressBars or {}) do
                progressBar.char = self.char
                progressBar.level = self.char:getPerkLevel(progressBar.perk:getType())
                progressBar.xpForLvl = ISSkillProgressBar.getXpForLvl(
                    progressBar.perk,
                    progressBar.level
                )
            end
        end
        if survivor ~= nil then
            view.perks = ISCharacterInfo.loadPerk(view)
            view.progressBarLoaded = false
            view.reloadSkillBar = true
        end
        window.skillsView = view
        window.panel:addView(xpSystemText.skills, view)
        UILayout.bindView(view)
    end
    if window.healthView == nil and survivor ~= nil then
        local localPlayer = getSpecificPlayer(window.playerNum)
        local view = ISHealthPanel:new(survivor, 0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        if localPlayer ~= nil then
            view.character = survivor
            view.playerNum = localPlayer:getPlayerNum()
            view.doctorLevel = localPlayer:getPerkLevel(Perks.Doctor)
        end
        window.healthView = view
        -- addView/addChild instantiates the panel and calls createChildren once.
        -- Calling it manually here duplicated both vanilla body presentations.
        window.panel:addView(xpSystemText.health, view)
        -- This embedded tab is inspection only; actual treatment uses the
        -- existing Medical Check action and its native doctor/patient window.
        view.doBodyPartContextMenu = function() end
        if view.listbox ~= nil then view.listbox.onRightMouseUp = function() end end
        if view.bodyPartPanel ~= nil then view.bodyPartPanel.onRightMouseUp = function() end end
        local healthRender = view.render
        view.render = function(self)
            healthRender(self)
            self.fitness:setVisible(false)
        end
        view.onJoypadDown = function(self, button, joypadData)
            window:onJoypadDown(button, joypadData)
        end
        -- Vanilla's self-health focus selects Fitness when otherPlayer is nil.
        -- Fitness is hidden in this inspection tab, so retain panel focus only.
        view.onGainJoypadFocus = function(self, joypadData)
            ISPanel.onGainJoypadFocus(self, joypadData)
            self.parent.drawJoypadFocus = true
        end
        view.onLoseJoypadFocus = function(self, joypadData)
            ISPanel.onLoseJoypadFocus(self, joypadData)
            self.parent.drawJoypadFocus = false
        end
        UILayout.bindView(view)
    end
    if window.protectionView == nil and survivor ~= nil then
        local view = ISCharacterProtection:new(0, 8, window.panel.width, window.panel.height - 8, window.playerNum)
        view:initialise()
        view:setScrollChildren(true)
        view:addScrollBars()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        view.char = survivor
        view.playerNum = survivor:getPlayerNum()
        view.bFemale = survivor:isFemale()
        view.sex = view.bFemale and "female" or "male"
        view.bodyOutline = getTexture("media/ui/defense/" .. view.sex .. "_base.png")
        pcall(function() view:create() end)
        window.protectionView = view
        window.panel:addView(xpSystemText.protection, view)
        UILayout.bindView(view)
    end
    if window.clothingView == nil and survivor ~= nil then
        local view = ISClothingInsPanel:new(survivor, 0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        view:setScrollChildren(true)
        view:addScrollBars()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        view.player = survivor
        view.playerNum = survivor:getPlayerNum()
        view.char = survivor
        window.clothingView = view
        window.panel:addView(xpSystemText.clothingIns, view)
        UILayout.bindView(view)
        -- See visibleContentBottom: vanilla reports one constant height for
        -- both temperature styles, so this must run after bindView (which
        -- replaces the hooks below) and on every vanilla render call.
        view.setHeightAndParentHeight = function(self, h)
            self:setHeight(h)
            self.knoxContentHeight = math.max(h, visibleContentBottom(self, h) + 10)
            UILayout.fitView(self)
        end
    end
    if window.knoxView == nil then
        local view = KnoxPanel:new(0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        view.window = window
        window.knoxView = view
        window.panel:addView("Knox", view)
        UILayout.bindView(view)
    end

    -- Bind all vanilla views to the selected survivor (never local player)
    if survivor ~= nil then
        if window.infoView ~= nil and window.infoView.char ~= survivor then
            window.infoView.char = survivor
            window.infoView.playerNum = survivor:getPlayerNum()
            window.infoView.hairMenu = function() end
            window.infoView.beardMenu = function() end
            window.infoView.literatureMenu = function() end
            window.infoView.bFemale = survivor:isFemale()
            window.infoView.refreshNeeded = true
            pcall(function() window.infoView:loadTraits() end)
            pcall(function() window.infoView:loadProfession() end)
            window.infoView:loadBeardAndHairStyle()
            if window.infoView.hairButton ~= nil then window.infoView.hairButton:setVisible(false) end
            if window.infoView.beardButton ~= nil then window.infoView.beardButton:setVisible(false) end
            if window.infoView.literatureButton ~= nil then window.infoView.literatureButton:setVisible(false) end
        end
        if window.infoView ~= nil then
            window.infoView.knoxWindow = window
        end
        if window.skillsView ~= nil and window.skillsView.char ~= survivor then
            window.skillsView.char = survivor
            window.skillsView.playerNum = window.playerNum
            window.skillsView.perks = ISCharacterInfo.loadPerk(window.skillsView)
            window.skillsView.progressBarLoaded = false
            window.skillsView.reloadSkillBar = true
        end
        if window.skillsView ~= nil then
            window.skillsView.knoxSnapshot = window.snapshot
        end
        if window.healthView ~= nil and window.healthView ~= false
            and window.healthView.character ~= survivor then
            local localPlayer = getSpecificPlayer(window.playerNum)
            if localPlayer ~= nil then
                window.healthView.otherPlayer = localPlayer
                window.healthView.doctorLevel = localPlayer:getPerkLevel(Perks.Doctor)
            else
                window.healthView.otherPlayer = nil
            end
            window.healthView.character = survivor
            window.healthView.playerNum = localPlayer ~= nil and localPlayer:getPlayerNum() or survivor:getPlayerNum()
            window.healthView.characterX = survivor:getX()
            window.healthView.characterY = survivor:getY()
        end
        if window.protectionView ~= nil and window.protectionView.char ~= survivor then
            window.protectionView.char = survivor
            window.protectionView.playerNum = survivor:getPlayerNum()
            window.protectionView.bFemale = survivor:isFemale()
            window.protectionView.sex = window.protectionView.bFemale and "female" or "male"
            window.protectionView.bodyOutline = getTexture("media/ui/defense/" .. window.protectionView.sex .. "_base.png")
            pcall(function() window.protectionView:create() end)
        end
        if window.clothingView ~= nil and window.clothingView.player ~= survivor then
            window.clothingView.player = survivor
            window.clothingView.playerNum = survivor:getPlayerNum()
            window.clothingView.char = survivor
        end
    end
    if window.knoxView ~= nil then
        window.knoxView.snapshot = window.snapshot
    end
    if activeName ~= nil then window.panel:activateView(activeName) end
    if survivor == nil then window.panel:activateView("Knox") end
end

function Window:refreshSnapshot()
    local snapshot = companionSnapshot(self.playerNum, self.survivorId)
    if snapshot == nil then
        self:destroy(true)
        return false
    end
    self.snapshot = snapshot
    ensureViews(self)
    -- Nudge vanilla views to refresh when survivor moved / leveled
    if self.infoView ~= nil and self.infoView.char ~= nil then
        self.infoView.refreshNeeded = true
    end
    return true
end

function Window:setSurvivor(survivorId)
    self.survivorId = survivorId
    return self:refreshSnapshot()
end

function Window:clampToViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setWidth(math.min(self:getWidth(), math.max(1, width - 20)))
    self:setHeight(math.min(self:getHeight(), math.max(1, height - 20)))
    self:setX(clamp(self:getX(), left, left + math.max(0, width - self:getWidth())))
    self:setY(clamp(self:getY(), top, top + math.max(0, height - self:getHeight())))
    self:stayOnSplitScreen(self.playerNum)
end

function Window:centerInViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setX(left + math.max(0, width - self:getWidth()) / 2)
    self:setY(top + math.max(0, height - self:getHeight()) / 2)
    self:clampToViewport()
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    -- Tab content is drawn by ISTabPanel children; window just keeps title correct.
    if self.snapshot ~= nil then
        self:setTitle(trimText(UIFont.Medium, self.snapshot.displayName, self.width - 40))
    end
end

function Window:onMouseUp(x, y)
    ISCollapsableWindowJoypad.onMouseUp(self, x, y)
    self:clampToViewport()
    fitViews(self)
    return true
end

function Window:onMouseUpOutside(x, y)
    ISCollapsableWindowJoypad.onMouseUpOutside(self, x, y)
    self:clampToViewport()
    fitViews(self)
    return true
end

function Window:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:close()
        return
    end
    if button == Joypad.LBumper or button == Joypad.RBumper then
        if self.panel ~= nil and self.panel.viewList ~= nil and #self.panel.viewList > 1 then
            local idx = self.panel:getActiveViewIndex()
            if button == Joypad.LBumper then
                idx = idx == 1 and #self.panel.viewList or idx - 1
            else
                idx = idx == #self.panel.viewList and 1 or idx + 1
            end
            self.panel:activateView(self.panel.viewList[idx].name)
            setJoypadFocus(self.playerNum, self.panel:getActiveView())
        end
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Window:destroy(restoreFocus)
    self.snapshot = nil
    self:setVisible(false)
    self:removeFromUIManager()
    if windows[self.playerNum] == self then
        windows[self.playerNum] = nil
    end
    if restoreFocus then
        restoreJoypadFocus(self)
    end
    self.previousJoypadFocus = nil
end

function Window:close()
    self:destroy(true)
end

function Window:new(playerNum)
    local _, _, screenWidth, screenHeight = screenBounds(playerNum)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.min(math.floor(WINDOW_WIDTH * scale), math.max(1, screenWidth - 20))
    local height = math.min(math.floor(WINDOW_HEIGHT * scale), math.max(1, screenHeight - 20))
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.survivorId = nil
    window.snapshot = nil
    window.previousJoypadFocus = nil
    UILayout.bindInteractionWindow(window)
    window.resizable = true
    window.minimumWidth = math.min(360, width)
    window.minimumHeight = math.min(260, height)
    window.pin = true
    window.backgroundColor = { r = COL_BG[1], g = COL_BG[2], b = COL_BG[3], a = 0.94 }
    window.borderColor = { r = COL_BORDER[1], g = COL_BORDER[2], b = COL_BORDER[3], a = 0.95 }
    window:setTitle("Survivor")
    return window
end

local function createWindow(playerNum)
    local window = Window:new(playerNum)
    window:initialise()
    window:setRenderThisPlayerOnly(playerNum)
    window:addToUIManager()
    window:centerInViewport()
    windows[playerNum] = window
    return window
end

function SurvivorCard.show(playerNum, survivorId)
    playerNum = tonumber(playerNum) or 0
    -- Keep the temporary caller trace available for diagnosis without adding
    -- a full traceback to the ordinary player-facing log on every open.
    if developerDiagnosticsEnabled() then
        local trace = ""
        if debug ~= nil and debug.traceback ~= nil then
            local ok, result = pcall(debug.traceback, "", 2)
            if ok and type(result) == "string" then trace = result end
        end
        print("[KnoxSurvivors][Card] show survivor=" .. tostring(survivorId)
            .. " player=" .. tostring(playerNum) .. " trace=" .. tostring(trace))
    end
    if getSpecificPlayer(playerNum) == nil or type(survivorId) ~= "string" then
        return nil
    end
    local snapshot = companionSnapshot(playerNum, survivorId)
    if snapshot == nil then
        print("[KnoxSurvivors][Card] no snapshot for survivor=" .. tostring(survivorId))
        return nil
    end

    local window = windows[playerNum]
    local wasVisible = window ~= nil and window:isVisible()
    if window == nil then
        window = createWindow(playerNum)
    end
    if not wasVisible and JoypadState.players[playerNum + 1] ~= nil then
        window.previousJoypadFocus = getJoypadFocus(playerNum)
    end
    if not window:setSurvivor(survivorId) then
        return nil
    end
    window:setVisible(true)
    window:bringToTop()
    window:clampToViewport()
    if JoypadState.players[playerNum + 1] ~= nil then
        setJoypadFocus(playerNum, window.panel and window.panel:getActiveView() or window)
    end
    return window
end

function SurvivorCard.close(playerNum, restoreFocus)
    local window = windows[tonumber(playerNum) or 0]
    if window ~= nil then
        window:destroy(restoreFocus ~= false)
    end
end

function SurvivorCard.destroyAll(restoreFocus)
    local playerNums = {}
    for playerNum in pairs(windows) do
        playerNums[#playerNums + 1] = playerNum
    end
    for _, playerNum in ipairs(playerNums) do
        SurvivorCard.close(playerNum, restoreFocus)
    end
end

local function onTick()
    local now = getTimestampMs()
    if now < nextRefreshAt then
        return
    end
    nextRefreshAt = now + REFRESH_MS
    local active = {}
    for playerNum, window in pairs(windows) do
        if window:isVisible() then
            active[#active + 1] = playerNum
        end
    end
    for _, playerNum in ipairs(active) do
        local window = windows[playerNum]
        if window ~= nil then
            window:refreshSnapshot()
        end
    end
end

local function onPlayerDeath(player)
    if player ~= nil then
        SurvivorCard.close(player:getPlayerNum(), false)
    end
end

local function onResolutionChange()
    for _, window in pairs(windows) do
        local _, _, sw, sh = screenBounds(window.playerNum)
        local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
        local nw = math.min(math.floor(WINDOW_WIDTH * scale), math.max(1, sw - 20))
        local nh = math.min(math.floor(WINDOW_HEIGHT * scale), math.max(1, sh - 20))
        window:setWidth(nw)
        window:setHeight(nh)
        if window.panel ~= nil then
            local th = window:titleBarHeight()
            local rh = window:resizeWidgetHeight()
            window.panel:setWidth(nw)
            window.panel:setHeight(nh - th - rh)
            fitViews(window)
        end
        window:clampToViewport()
    end
end

Events.OnTick.Add(onTick)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnResolutionChange.Add(onResolutionChange)
Events.OnGameStart.Add(function()
    SurvivorCard.destroyAll(false)
    nextRefreshAt = 0
end)
Events.OnMainMenuEnter.Add(function()
    SurvivorCard.destroyAll(false)
    nextRefreshAt = 0
end)

return SurvivorCard
