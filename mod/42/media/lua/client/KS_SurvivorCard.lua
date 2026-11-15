require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISTabPanel"
require "ISUI/ISUI3DModel"
require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISHealthPanel"
require "XpSystem/ISUI/ISCharacterProtection"
require "ISUI/ISContextMenu"
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

-- The card is the same character sheet the player opens - same tabs, same
-- vanilla panels - so it takes the player's own window footprint when the
-- build exposes it. That keeps the health, protection and skills pages the same
-- size as the player's at any resolution, instead of one guessed constant that
-- is wrong on both a 1080p and a 1440p screen. A missing or absurd window falls
-- back to the tuned constants above.
local function playerWindowSize(playerNum)
    if type(getPlayerInfoPanel) ~= "function" then return nil end
    local ok, info = pcall(getPlayerInfoPanel, playerNum)
    if not ok or info == nil then return nil end
    local widthOk, width = pcall(function() return info:getWidth() end)
    local heightOk, height = pcall(function() return info:getHeight() end)
    if not (widthOk and heightOk) then return nil end
    if type(width) ~= "number" or type(height) ~= "number" then return nil end
    if width < 320 or height < 240 then return nil end
    return width, height
end
local PADDING = 10
local SECTION_GAP = 8

-- One material: the card reads the same charcoal/bone palette as the party
-- strip, notice rail and crosshair prompt instead of carrying a second grey
-- system of its own. Meaning-bearing colour (hostility, trust) still comes
-- from the reputation view; these are the neutrals around it.
if type(UILayout) ~= "table" then
    UILayout = rawget(_G, "KnoxSurvivorUILayout") or {}
end
local THEME = type(UILayout.theme) == "table" and UILayout.theme or {}
local COL_BG      = THEME.charcoal
local COL_BORDER  = THEME.border
local COL_SEC_BG  = { COL_BG[1] + 0.024, COL_BG[2] + 0.023, COL_BG[3] + 0.021 }
local COL_SEC_HDR = THEME.muted
local COL_LABEL   = THEME.label
local COL_VALUE   = THEME.bone
local COL_DIM     = THEME.dim
local COL_ACCENT  = THEME.green

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

-- Meaning-bearing colour only: red is hostile, amber is uneasy, bone is
-- neutral, and the one Knox accent marks earned trust. The value comes from
-- KS_ReputationView, so the band and the colour cannot disagree.
local function standingTone(tone)
    if tone == "hostile" then return { 0.86, 0.34, 0.30 } end
    if tone == "friendly" then return COL_ACCENT end
    if tone == "cautious" then return { 0.84, 0.76, 0.52 } end
    if tone == "wary" or tone == "neutral" then return { 0.70, 0.68, 0.62 } end
    return COL_VALUE
end

local function trimText(font, text, maximumWidth)
    return UILayout.fitText(font, text, maximumWidth)
end

-- Detail rows grow inside the existing scroller. A short value stays beside
-- its label; a long one gets the full line instead of losing its reason.
local function drawCardText(view, text, x, y, width, font, colour)
    local manager = getTextManager()
    local lines = UILayout.wrapLines(tostring(text or ""), math.max(1, width),
        function(value) return manager:MeasureStringX(font, value) end)
    local lineH = manager:getFontHeight(font)
    for _, line in ipairs(lines) do
        view:drawText(line, x, y, colour[1], colour[2], colour[3], 1, font)
        y = y + lineH + 2
    end
    return y
end

local function drawCardDetail(view, label, value, x, y, width, labelColour, valueColour)
    local manager = getTextManager()
    local font = UIFont.Small
    local title, text = tostring(label), tostring(value or "Unknown")
    if manager:MeasureStringX(font, title) + 12 + manager:MeasureStringX(font, text) <= width then
        view:drawText(title, x, y, labelColour[1], labelColour[2], labelColour[3], 1, font)
        view:drawTextRight(text, x + width, y, valueColour[1], valueColour[2], valueColour[3], 1, font)
        return y + manager:getFontHeight(font) + 4
    end
    y = drawCardText(view, title, x, y, width, font, labelColour)
    return drawCardText(view, text, x, y, width, font, valueColour) + 2
end

local function placeCardButtons(view, contentY, width, fontH)
    local manager = getTextManager()
    local measure = function(text) return manager:MeasureStringX(UIFont.Small, text) end
    local medical = view.medicalButton
    local title = medical.knoxLabel or "Medical Check"
    if measure(title) + 24 > width then title = "Medical" end
    if medical.title ~= title then medical:setTitle(title) end
    local footer = UILayout.footerPlacements({view.inventoryButton,medical}, width,
        {buttonHeight=fontH+10,spacing=6,measure=measure})
    local top = math.max(contentY + SECTION_GAP, view.height - footer.height - PADDING)
    for _, slot in ipairs(footer.placements) do
        local button = slot.control
        local x, y = PADDING + slot.x, top + slot.y
        if button.x ~= x then button:setX(x) end
        if button.y ~= y then button:setY(y) end
        if button.width ~= slot.width then button:setWidth(slot.width) end
        if button.height ~= slot.height then button:setHeight(slot.height) end
    end
    return top + footer.height + PADDING
end

local function dayLabel(value)
    local days = tonumber(value)
    if days == nil then
        return "Unknown"
    end
    days = math.max(0, math.floor(days))
    return tostring(days) .. (days == 1 and " day" or " days")
end

local function companionSnapshot(playerNum, survivorId)
    -- A character sheet needs one person, not a fresh projection of the whole
    -- companion roster on every half-second refresh.
    if KnoxSurvivorViewModel.getSurvivor ~= nil then
        local ok, snapshot = pcall(KnoxSurvivorViewModel.getSurvivor, survivorId, playerNum)
        if ok then return snapshot end
        return nil
    end
    for _, snapshot in ipairs(KnoxSurvivorViewModel.getForPlayer(playerNum) or {}) do
        if snapshot.id == survivorId then
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

-- Knox tab - misc history / current job only. Vanilla tabs now cover portrait, traits, skills, health, protection, temperature.
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
        -- The button keeps its one native handler; only its name follows the
        -- condition the card already shows, so a bleed is not a hidden second
        -- click target or a promised treatment.
        local label = snapshot.medicalActionLabel or "Medical Check"
        if self.medicalButton.knoxLabel ~= label then
            self.medicalButton.knoxLabel = label
            self.medicalButton:setTitle(label)
        end
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
        y = drawCardDetail(self, label, value, PADDING, y, w, COL_LABEL, col or COL_VALUE)
    end

    y = drawCardText(self, snapshot.displayName, PADDING, y, w, UIFont.Medium, COL_VALUE) + 2
    local age = snapshot.ageYears ~= nil and "Age " .. tostring(snapshot.ageYears) or ""
    if age ~= "" then
        self:drawText(age, PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
        y = y + smallH + 2
    end
    y = drawCardText(self, "Survived " .. dayLabel(snapshot.daysSurvived) .. "  |  Known " .. dayLabel(snapshot.daysKnown),
        PADDING, y, w, UIFont.Small, COL_DIM) + SECTION_GAP

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
                memory = memory .. " - " .. detail
            end
            y = drawCardText(self, memory, PADDING, y, w, UIFont.Small, COL_VALUE) + 1
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
    -- Only a dead survivor carries this, and only when the body or the ledger
    -- named a cause. A living card spends no row on it: `keyValue` renders a
    -- nil as "Unknown", so the guard is what keeps the row absent.
    if snapshot.deathCauseLabel ~= nil then
        keyValue("Died", snapshot.deathCauseLabel)
    end
    keyValue("Order", snapshot.orderDisplayLabel or snapshot.orderLabel)
    -- The card is often the only place a held weapon is named; a broken one
    -- says so here instead of waiting for the inventory to be opened. An
    -- unloaded body spends no row on "Equipment unavailable".
    if snapshot.loaded == true and snapshot.weaponName ~= nil
        and snapshot.weaponName ~= "" then
        keyValue("Weapon", snapshot.weaponName)
        -- Rounds are only known for a live body's ranged weapon. The engine's
        -- own count names the magazine; a chambered round is one more shot.
        if snapshot.ammoName ~= nil and snapshot.ammoName ~= "" then
            local empty = snapshot.ammoName == "Empty"
            keyValue("Ammo", snapshot.ammoName, empty and { 0.86, 0.34, 0.30 } or nil)
        end
    end
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
    -- A bite is the condition that changes the whole plan, so it gets its own
    -- row above the bleed. The word comes from the same engine flag the Needs
    -- line reads; a clean or unreadable body spends no row.
    if snapshot.infectionLabel ~= nil then
        keyValue("Infection", snapshot.infectionLabel, { 0.86, 0.34, 0.30 })
    end
    -- A bleed is a count, not a bar. The word comes from the view model's own
    -- projection, so the card and the Needs line cannot disagree about it.
    if snapshot.bleedingLabel ~= nil then
        keyValue("Bleeding", snapshot.bleedingLabel, { 0.86, 0.34, 0.30 })
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
        -- Pain is the one bar where more is worse; the needs above are reserves.
        needBar("Pain", vitals.pain, true)
    end
    y = y + 4
    sectionHeader("Relationship")
    local function standingRow(title, value, tone)
        local col = standingTone(tone)
        y = drawCardDetail(self, title, value, PADDING, y, w, COL_LABEL, col)
        return col
    end
    local function standingBar(fill, col, signedBar)
        local barW = math.max(20, w - 4)
        local fraction = clamp(tonumber(fill) or 0, 0, 1)
        self:drawRect(PADDING, y, barW, 7, 0.45, 0.02, 0.02, 0.02)
        if signedBar then
            -- A signed faction bar needs a zero tick, or a half-full bar reads
            -- as "good" when it is really a neutral no-contact score.
            local zeroX = PADDING + barW * 0.5
            self:drawRect(zeroX, y - 1, 1, 9, 0.55, 0.75, 0.75, 0.70)
            self:drawRect(PADDING, y, math.max(1, barW * fraction), 7, 0.9,
                col[1], col[2], col[3])
        else
            self:drawRect(PADDING, y, math.max(1, barW * fraction), 7, 0.9,
                col[1], col[2], col[3])
        end
        y = y + 9
    end
    local function standingDetail(text)
        if text == nil or text == "" then return end
        y = drawCardText(self, text, PADDING, y, w, UIFont.Small, COL_DIM)
    end
    -- The faction's own colour, derived from its name, so a card reads as the
    -- same group the nameplate above the person does.
    local factionColour = snapshot.factionName ~= nil
        and KnoxPersistence.factionAccent ~= nil
        and KnoxPersistence.factionAccent(snapshot.factionName) or nil
    keyValue("Faction", snapshot.factionName or "None", factionColour)
    -- The card spells out the same recognition the nameplate shows in the
    -- world, from the same resolver: a household is a household in both places.
    local names = rawget(_G, "KnoxSurvivorNames")
    local persistence = rawget(_G, "KnoxPersistence")
    local facts = persistence ~= nil and persistence.survivorCompany ~= nil
        and persistence.survivorCompany(snapshot.id) or nil
    local companyName = names ~= nil and names.companyName ~= nil
        and names.companyName(facts) or nil
    local companyPlace = names ~= nil and names.companyPlace ~= nil
        and names.companyPlace(facts) or nil
    local companySize = facts ~= nil and math.floor(tonumber(facts.memberCount) or 0) or 0
    if facts ~= nil and facts.isLeader == true and companySize >= 2 then
        local householdName = type(facts.name) == "string" and facts.name ~= ""
            and facts.name or "Household"
        local householdDetail = companyPlace ~= nil
            and (companySize .. " people, " .. companyPlace) or (companySize .. " people")
        keyValue("Household", householdName .. " - " .. householdDetail)
    elseif companyName ~= nil then
        keyValue("With", companyPlace ~= nil
            and (companyName .. ", " .. companyPlace) or companyName)
    end
    -- Personal standing and faction standing are always two rows. The person's
    -- trust is never presented as the faction's reputation, and an unknown
    -- faction row says so instead of showing a fabricated neutral.
    local standing = snapshot.standing
    if standing ~= nil and standing.known == true then
        local col = standingRow("Personal", standing.label, standing.tone)
        standingBar(standing.fill, col, false)
        if standing.hostile == true then
            -- Behaviour, not the personal band: a trusting person in a hostile
            -- faction is dangerous without their own history being rewritten.
            y = drawCardText(self, standing.hostileText or "Hostile right now",
                PADDING, y, w, UIFont.Small, {0.86, 0.34, 0.30})
        end
        standingDetail(standing.deltaText)
        standingDetail(standing.nextText)
        y = y + 2
    else
        keyValue("Trust", snapshot.trustLabel or "Unknown")
    end
    local factionStanding = snapshot.factionStanding
    if factionStanding ~= nil then
        if factionStanding.known == true then
            local col = standingRow("Faction standing", factionStanding.label,
                factionStanding.tone)
            standingBar(factionStanding.fill, col, true)
            standingDetail(factionStanding.deltaText)
            y = y + 2
        else
            keyValue("Faction standing", factionStanding.label or "No contact recorded",
                COL_DIM)
        end
    end
    keyValue("Meetings", snapshot.relationshipMeetings ~= nil
        and tostring(math.max(0, math.floor(snapshot.relationshipMeetings))) or nil)
    if snapshot.isSpouse then keyValue("Relationship", "Spouse", COL_ACCENT) end
    keyValue("Group", snapshot.affiliation and snapshot.affiliation.kind or "independent")
    local contentH = placeCardButtons(self, y, w, smallH)
    if self.knoxScrollH ~= contentH then
        self.knoxScrollH = contentH
        self:setScrollHeight(contentH)
    end
end

function KnoxPanel:onInventoryButton()
    if self.window == nil or self.window.snapshot == nil then return end
    -- request() explains a refusal in the shared vocabulary; the card's own
    -- button used to fail silently.
    local open = CompanionInventory ~= nil and (CompanionInventory.request
        or CompanionInventory.show) or nil
    if open == nil then return end
    open(self.window.playerNum, self.window.survivorId)
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
    self.inventoryButton:initialise(); UILayout.tintPrimary(self.inventoryButton)
    self:addChild(self.inventoryButton)
    self.medicalButton = ISButton:new(PADDING + 130, self.height - buttonH - PADDING, 122, buttonH,
        "Medical Check", self, KnoxPanel.onMedicalButton)
    self.medicalButton:initialise(); UILayout.tintButton(self.medicalButton)
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
    UILayout.finishWindow(self, "Close survivor card")

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    -- ISTabPanel matching ISCharacterInfoWindow:117 - tabPadX 10, equalTabWidth false
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

local function cardCharacter(window)
    local snapshot = window.snapshot
    if snapshot == nil then return nil end
    local body = KnoxSurvivorViewModel.resolveLiveCharacter(snapshot.id)
    if body == nil then return nil end
    if snapshot.loaded == true then return body end
    -- loaded on the knowledge snapshot means directly visible, not whether a
    -- native body exists. Nearby owned residents/companions remain inspectable
    -- under the same permission and reach checks as their inventory.
    if CompanionInventory and CompanionInventory.canManage then
        local accepted = CompanionInventory.canManage(window.playerNum,snapshot.id,body)
        if accepted then return body end
    end
    return nil
end

local function ensureViews(window)
    if window.panel == nil then return end
    -- Vanilla tab names come from the translation table. An unloaded or
    -- renamed table made every addView below index a nil global, so a missing
    -- entry now falls back to the plain word instead of aborting the card.
    local tabText = type(xpSystemText) == "table" and xpSystemText
        or { info = "Info", skills = "Skills", health = "Health",
             protection = "Protection", clothingIns = "Clothing" }
    local survivor = cardCharacter(window)

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

    -- The Knox tab is built before any vanilla panel: a vanilla view that fails
    -- to construct used to leave the whole card blank while the window stayed
    -- on screen, with the failure swallowed by the caller (2026-11-09 report).
    if window.knoxView == nil then
        local view = KnoxPanel:new(0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        view.window = window
        window.knoxView = view
        window.panel:addView("Knox", view)
        UILayout.bindView(view)
    end

    -- A persisted survivor can be known to the Notebook while its live shell
    -- is streamed out. Vanilla character views dereference `char` during
    -- addView/prerender, so keep the Knox tab available and wait for a real
    -- IsoPlayer before creating those views.
    -- A failing vanilla panel is named once instead of silently blanking the
    -- card; the Knox tab above already gives the card real content.
    local viewsOk, viewError = pcall(function()
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
        -- Hide vanilla change buttons for survivor - no haircut and no discovered media here.
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
                y = drawCardDetail(self, label, value, 10, y, w, COL_LABEL, COL_VALUE)
            end
            kv("Time Alive", dayLabel(snap.daysSurvived))
            kv("Known", dayLabel(snap.daysKnown))
            kv("Faction", snap.factionName or "None")
            kv("Trust", snap.standing ~= nil and snap.standing.label or snap.trustLabel or "Unknown")
            if snap.factionStanding ~= nil then
                kv("Faction standing", snap.factionStanding.known == true
                    and snap.factionStanding.label or "No contact")
            end
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
            -- The settings a follower or resident is actually running under:
            -- read through the same owner the wheel and Party Orders use, so
            -- this row cannot report a stance the orders do not have.
            local service = rawget(_G, "KnoxCompanionService")
            local tactics = service ~= nil and service.survivorTactics ~= nil
                and snap.id ~= nil and service.survivorTactics(snap.id) or nil
            if tactics ~= nil then
                if tactics.mode == "companion" then
                    local stance = tostring(tactics.stance)
                    kv("Stance", stance:sub(1,1):upper() .. stance:sub(2))
                    local shape = tactics.formation == "single_file" and "Single File" or "Paired"
                    kv("Formation", shape .. " " .. tostring(tactics.spacing))
                elseif tactics.mode == "base" then
                    kv("Supply Runs", tactics.lootRuns and "Joins" or "Stays home")
                end
            end
            kv("Base / Activity", (snap.locationLabel or "Unknown") .. " - " .. (snap.orderLabel or ""))
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
        window.panel:addView(tabText.info, view)
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
        window.panel:addView(tabText.skills, view)
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
        window.panel:addView(tabText.health, view)
        -- This embedded tab is inspection only; actual treatment uses the
        -- existing Medical Check action and its native doctor/patient window.
        view.doBodyPartContextMenu = function() end
        if view.listbox ~= nil then view.listbox.onRightMouseUp = function() end end
        if view.bodyPartPanel ~= nil then view.bodyPartPanel.onRightMouseUp = function() end end
        -- Vanilla's Fitness panel is the player's own exercise surface. It is
        -- hidden here, so its space is the honest place for the one control
        -- that asks THIS survivor to work out: the same native action, on their
        -- body, through the exercise owner.
        -- ISButton.new does arithmetic on height (`height - 2`). A height that
        -- arrives as a Java value raises "__sub not defined" and took the whole
        -- vanilla view build down with it (2026-11-10 console), so pass a plain
        -- number and keep the shared constant's value when it is numeric.
        local exerciseHeight = math.floor(tonumber(BUTTON_HGT) or 24)
        local exerciseBtn = ISButton:new(0, 0, 150, exerciseHeight, "Exercise", window, Window.onExercise)
        exerciseBtn:initialise()
        exerciseBtn:setVisible(false)
        exerciseBtn.tooltip = "Ask this survivor to exercise where they stand."
        view:addChild(exerciseBtn)
        view.exerciseBtn = exerciseBtn
        local healthRender = view.render
        view.render = function(self)
            healthRender(self)
            self.fitness:setVisible(false)
            local button = self.exerciseBtn
            if button ~= nil then
                -- Bottom-left is where vanilla puts its own panel buttons and
                -- where this inspection tab leaves room, unlike the hidden
                -- fitness block whose geometry belongs to the player's screen.
                local x, y = 12, math.max(8, self:getHeight() - button.height - 8)
                button:setX(x); button:setY(y)
                button:setVisible(self:isVisible() and self:getHeight() >= 80)
            end
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
        window.panel:addView(tabText.protection, view)
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
        window.panel:addView(tabText.clothingIns, view)
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

    end)
    if not viewsOk then
        print("[KnoxSurvivors][Card] vanilla view build failed: " .. tostring(viewError))
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

-- One button, one question: which bodyweight exercise. The picker is the
-- ordinary context menu, so no new window is introduced, and the exercise
-- owner keeps the gates and the native action queue.
function Window:onExercise(button)
    local exercise = rawget(_G, "KnoxSurvivorExercise")
    local player = getSpecificPlayer(self.playerNum)
    if exercise == nil or exercise.start == nil or player == nil or self.survivorId == nil then
        return
    end
    local blocked = exercise.refusal ~= nil and exercise.refusal(player, self.survivorId) or nil
    local function complain(reason)
        local text = exercise.refusalText ~= nil and exercise.refusalText(reason)
            or "They cannot exercise right now."
        if type(HaloTextHelper) == "table" and HaloTextHelper.addBadText ~= nil then
            HaloTextHelper.addBadText(player, text)
        end
    end
    if blocked ~= nil then
        complain(blocked)
        return
    end
    local rows = exercise.exercises ~= nil and exercise.exercises() or {}
    local menu = nil
    if #rows > 0 and type(ISContextMenu) == "table" and ISContextMenu.get ~= nil then
        local opened, value = pcall(ISContextMenu.get, self.playerNum, getMouseX(), getMouseY())
        if opened then menu = value end
    end
    if menu == nil then
        local started, reason = exercise.start(player, self.survivorId, "squats")
        if started ~= true then complain(reason) end
        return
    end
    for _, row in ipairs(rows) do
        local kind = row.type
        menu:addOption(tostring(row.label), player, function()
            local started, reason = exercise.start(player, self.survivorId, kind)
            if started ~= true then complain(reason) end
        end)
    end
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
    local layoutApi = rawget(_G, "KnoxSurvivorUILayout")
    if layoutApi ~= nil and layoutApi.releaseSurface ~= nil then
        pcall(layoutApi.releaseSurface, self.playerNum, "card")
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
    local infoWidth, infoHeight = playerWindowSize(playerNum)
    local width = math.min(infoWidth or math.floor(WINDOW_WIDTH * scale),
        math.max(1, screenWidth - 20))
    local height = math.min(infoHeight or math.floor(WINDOW_HEIGHT * scale),
        math.max(1, screenHeight - 20))
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    -- Install this class before anything touches the window. Any call that needs
    -- a javaObject instantiates the element, and `instantiate` calls
    -- `createChildren` through whatever metatable is installed at that moment.
    -- Tracking first therefore built the vanilla children only: this class's tab
    -- panel never existed and the card opened blank (2026-11-10 report).
    setmetatable(window, self)
    self.__index = self
    -- One scale rule, one clamp: the card is the largest Knox window and the
    -- first thing a small display loses.
    UILayout.trackWindow(window)
    window.playerNum = playerNum
    window.survivorId = nil
    window.snapshot = nil
    window.previousJoypadFocus = nil
    -- The card is a read, so it keeps its distance and sight: a resident on a
    -- far job is still worth reading about. It closes on the person's death or
    -- hostility, and on the player aiming, driving or dying.
    UILayout.bindPersonSurface(window, { checkDistance = false, requireSight = false })
    window.resizable = true
    window.minimumWidth = math.min(360, width)
    window.minimumHeight = math.min(260, height)
    window.pin = true
    UILayout.tintWindow(window)
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

    -- One Knox surface per player: the card replaces a notebook or trade
    -- window that was open. A failed lookup above closes nothing.
    local layoutApi = rawget(_G, "KnoxSurvivorUILayout")
    if layoutApi ~= nil and layoutApi.claimSurface ~= nil then
        pcall(layoutApi.claimSurface, playerNum, "card", SurvivorCard)
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
        local infoWidth, infoHeight = playerWindowSize(window.playerNum)
        local nw = math.min(infoWidth or math.floor(WINDOW_WIDTH * scale),
            math.max(1, sw - 20))
        local nh = math.min(infoHeight or math.floor(WINDOW_HEIGHT * scale),
            math.max(1, sh - 20))
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
