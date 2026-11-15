-- Knox Survivors - the faction creator.
--
-- One full-screen sheet: faction presets, roster cards, an isolated character
-- preview and the selected person's equipment and choices beside it. The roster model lives in KS_Creator; this file asks and shows. Nothing
-- is written until commit, and commit is the only writer.
--
-- Panel.ENABLED is the one switch, read by the two entry points and the menu tick.
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISUI3DModel"
require "ISUI/ISComboBox"
require "ISUI/ISColorPicker"
local UILayout = require "KS_SurvivorUILayout"
local Creator = require "KS_Creator"
local AppearanceUI = require "KS_CreatorAppearanceUI"
local Capabilities = require "KS_SurvivorCapabilities"
local LoadoutInfo = require "KS_CreatorLoadoutInfo"

local Panel = rawget(_G, "KnoxCreatorPanel") or {}
_G.KnoxCreatorPanel = Panel
Creator.panel = Panel

-- The owner requested the creator rebuild. Availability is source-level;
-- native rendering and NPC behavior remain separate acceptance checks.
Panel.ENABLED = true

Panel.WINDOW_TITLE = "Knox Survivors - People & Factions"

-- Layout metrics, recomputed from the shared UI scale when the window is built.
local WIDTH, HEIGHT, PAD, ROW = 940, 566, 10, 26
local RAIL_W, DETAIL_W, TOOLBAR_H, FOOTER_H, CRUMB_H = 250, 360, 40, 24, 24
local CELL_H, CELL_GAP, ROW_H, SKILL_H = 60, 6, 28, 24
local INSET = 6

-- Dark slate sheet material, matching the owner's reference. The tokens
-- are owned by the shared layout helper so the creator and the
-- base-management sheet cannot drift apart.
local creatorTheme = UILayout.sheetTheme()

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- One geometry rule drives the real panel and the offline small/large-font gate.
function Panel.editorMetrics(screenW, screenH, fontH)
    local width, height = math.max(1, screenW - 12), math.max(1, screenH - 12)
    local row = math.max(28, (fontH or 16) + 12)
    local rail = clamp(math.floor(width * 0.18), math.min(180, math.floor(width * 0.18)), 240)
    local detail = clamp(math.floor(width * 0.34), math.min(330, math.floor(width * 0.40)), 460)
    local center = width - rail - detail - 40
    if center < 190 then rail = math.max(150, rail - (190 - center)) end
    return { width = width, height = height, rail = rail, detail = detail,
        row = row, cell = math.max(60, (fontH or 16) * 2 + 20) }
end

function Panel.gearColumns(width, fontH)
    local minimum = math.max(140, (fontH or 16) * 8)
    return clamp(math.floor((width + 6) / (minimum + 6)), 1, 3)
end

local function computeMetrics()
    local scale = UILayout.uiScale()
    local screenW, screenH = UILayout.screenSize()
    screenW = tonumber(screenW) or 1920
    screenH = tonumber(screenH) or 1080
    PAD = math.max(6, math.floor(10 * scale))
    ROW = math.max(18, math.floor(26 * scale))
    RAIL_W = clamp(math.floor(screenW * 0.21), 220, 320)
    DETAIL_W = clamp(math.floor(screenW * 0.30), 320, 460)
    TOOLBAR_H = math.max(32, math.floor(40 * scale))
    WIDTH = math.max(640, math.floor(screenW) - INSET * 2)
    HEIGHT = math.max(480, math.floor(screenH) - INSET * 2)
    local fontH = 16
    pcall(function() fontH = getTextManager():getFontHeight(UIFont.Small) end)
    local metrics = Panel.editorMetrics(screenW, screenH, fontH)
    WIDTH, HEIGHT, RAIL_W, DETAIL_W = metrics.width, metrics.height, metrics.rail, metrics.detail
    ROW_H, CELL_H, SKILL_H = metrics.row, metrics.cell, metrics.row
    TOOLBAR_H = metrics.row + 14
    ROW, FOOTER_H, CRUMB_H = metrics.row, metrics.row, metrics.row
end
computeMetrics()

local function addButton(parent, x, y, width, height, label, target, callback)
    local button = ISButton:new(x, y, width, height, label, target, callback)
    button:initialise()
    if button.setVisible then button:setVisible(true) end
    pcall(UILayout.tintButton, button)
    local function paint(control)
        UILayout.tintSheetButton(control)
    end
    paint(button)
    -- Stock B42 setEnable(false) paints a red error border. Read-only preview
    -- fields are ordinary information, so retain the creator's neutral material.
    local setEnable = button.setEnable
    button.setEnable = function(control, enabled)
        setEnable(control, enabled)
        if not enabled then paint(control) end
    end
    parent:addChild(button)
    return button
end

local function placeholder(entry, text)
    if entry ~= nil and entry.setPlaceholderText ~= nil then
        pcall(function() entry:setPlaceholderText(text) end)
    end
end

-- Real item thumbnails, built once per item. An item the engine will not build has
-- no icon and is drawn as text, never as a blank that looks like a broken card.
--
-- Two crashes lived here. `InventoryItemFactory` is a Java class the sandbox does
-- not expose (the only Lua mention in the install is a commented-out server line),
-- so every lookup threw "attempted index: CreateItem of non-table: null" on open.
-- The miss was then cached as `false`, and `cached == false and nil or cached`
-- evaluates to `false`, not nil, so the caller drew a Boolean as a texture 95 times
-- per session. Items are built with the same calls the inventory UI uses
-- (ISItemsListTable.lua:195, ISLootZed.lua:135-140), and a miss is a private
-- sentinel so it can never be mistaken for a texture.
local iconCache = {}
local NO_ICON = {}

local function scriptTexture(fullType)
    local texture = nil
    pcall(function()
        local script = getScriptManager():getItem(fullType)
        if script == nil then return end
        local icon = script:getIcon()
        if script.getIconsForTexture ~= nil then
            local icons = script:getIconsForTexture()
            if icons ~= nil and icons.isEmpty ~= nil and not icons:isEmpty() then
                icon = icons:get(0)
            end
        end
        if type(icon) == "string" and icon ~= "" then
            texture = getTexture("Item_" .. icon)
        end
    end)
    return texture
end

local function itemIcon(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local cached = iconCache[fullType]
    if cached ~= nil then
        -- Identity, not `cached == false and nil or cached`: that expression
        -- returns the sentinel itself, which is the Boolean crash.
        if cached == NO_ICON then return nil end
        return cached
    end
    local texture = nil
    pcall(function()
        local item = type(instanceItem) == "function" and instanceItem(fullType) or nil
        if item ~= nil and item.getTex ~= nil then texture = item:getTex() end
    end)
    if texture == nil then texture = scriptTexture(fullType) end
    -- Only a Boolean is certainly not a texture, and a Boolean is exactly what
    -- used to reach drawTextureScaled and abort the rest of the card.
    if type(texture) == "boolean" then texture = nil end
    iconCache[fullType] = texture or NO_ICON
    return texture
end
Panel.itemIcon = itemIcon

local function accentFor(label)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.factionAccent ~= nil then
        local ok, accent = pcall(persistence.factionAccent, label)
        if ok and type(accent) == "table" then return accent end
    end
    return creatorTheme.amber
end

-- Every item a card promises, from the tables the spawn path reads. Kit themes are
-- named, not itemised here: the starting-gear owner decides what a kit contains.
local function gearItems(person)
    local items, seen = {}, {}
    if type(person) ~= "table" then return items end
    -- Weapons and pack stay visible even on the narrow roster cards.
    for _, id in ipairs({"primary", "secondary", "backpack", "head", "torso", "vest", "legs", "feet"}) do
        local slot = Creator.slotById(id)
        local choice = slot and Panel.effectiveSlot(person, slot) or nil
        if choice and not seen[choice.fullType] then
            items[#items + 1] = choice.fullType; seen[choice.fullType] = true
        end
    end
    return items
end

local function labelOf(list, id, fallback)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry.label end
    end
    return fallback or tostring(id)
end

-- One picker for every slot and every carried item.
local Picker = ISPanel:derive("KnoxCreatorPicker")

-- A picker may be offered thousands of candidates. Only this many are added to
-- the list at once, so opening and typing cost the same whether the catalogue
-- holds 200 entries or 20,000; the footer says how many the search still hides.
Picker.MAX_ROWS = 200

function Picker:new(x, y, width, height, entries, onPick, caption)
    local picker = ISPanel:new(x, y, width, height)
    setmetatable(picker, self)
    self.__index = self
    picker.entries = entries or {}
    -- Lower-case the searchable text once, not on every keystroke.
    for _, entry in ipairs(picker.entries) do
        entry.search = string.lower(tostring(entry.label)) .. "|"
            .. string.lower(tostring(entry.fullType))
    end
    picker.onPick = onPick
    picker.caption = caption or "Search items"
    picker:initialise()
    local t = creatorTheme
    picker.backgroundColor = { r = t.charcoal[1], g = t.charcoal[2], b = t.charcoal[3], a = 0.98 }
    picker.borderColor = { r = t.border[1], g = t.border[2], b = t.border[3], a = 0.95 }
    return picker
end

function Picker:createChildren()
    local pad = math.max(6, math.floor(PAD * 0.8))
    local fieldHeight = math.max(20, math.floor(ROW * 0.9))
    local closeWidth = math.max(56, math.floor(self.width * 0.14))
    self.closeButton = ISButton:new(self.width - pad - closeWidth, pad, closeWidth,
        fieldHeight, "Close", self, function() self:close() end)
    self.closeButton:initialise()
    pcall(UILayout.tintSheetButton, self.closeButton)
    self:addChild(self.closeButton)
    self.search = ISTextEntryBox:new("", pad, pad,
        self.width - pad * 3 - closeWidth, fieldHeight)
    self.search:initialise()
    placeholder(self.search, self.caption)
    self.search.onTextChange = function() self:populate() end
    self:addChild(self.search)
    local listY = pad * 2 + fieldHeight
    self.list = ISScrollingListBox:new(pad, listY, self.width - pad * 2,
        self.height - listY - pad - 16)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = math.max(24, math.floor(CELL_H * 0.62))
    self.list.font = UIFont.Small
    self.list.doDrawItem = Picker.drawRow
    local nativeTooltip = self.list.updateTooltip
    self.list.updateTooltip = function(list)
        local row = list.items[list:rowAt(list:getMouseX(),list:getMouseY())]
        local entry = row and row.item
        if entry and type(entry.fullType)=="string" and entry.fullType:find(".",1,true) then
            row.tooltip = LoadoutInfo.itemTooltip(entry.fullType,self.person)
        end
        nativeTooltip(list)
    end
    self.list:setOnMouseDownFunction(self, Picker.onRow)
    self:addChild(self.list)
    self:populate()
end

function Picker:populate()
    if self.list == nil then return end
    local query = ""
    pcall(function() query = string.lower(tostring(self.search:getText() or "")) end)
    -- A keystroke that leaves the query unchanged must not rebuild the list.
    if self.lastQuery == query then return end
    self.lastQuery = query
    self.list:clear()
    local words = {}
    for word in query:gmatch("%S+") do words[#words+1]=word end
    local shown, matches = 0, 0
    for _, entry in ipairs(self.entries) do
        local haystack = entry.search
            or (string.lower(tostring(entry.label)) .. "|" .. string.lower(tostring(entry.fullType)))
        local matchesWords = true
        for _, word in ipairs(words) do
            if not haystack:find(word,1,true) then matchesWords=false; break end
        end
        if matchesWords then
            matches = matches + 1
            if shown < Picker.MAX_ROWS then
                self.list:addItem(tostring(entry.label), entry, entry.tooltip)
                shown = shown + 1
            end
        end
    end
    self.shownCount, self.matchCount = shown, matches
end

function Picker:render()
    ISPanel.render(self)
    if self.matchCount ~= nil and self.matchCount > self.shownCount then
        local t = creatorTheme
        self:drawText("Showing " .. tostring(self.shownCount) .. " of "
            .. tostring(self.matchCount) .. " matches - type to narrow",
            10, self.height - 15, t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
    end
end

-- Closing is an explicit affordance: the picker's own button and Escape both
-- land here, so an open list can never trap the window behind it.
function Picker:close()
    local parent = self.parent
    self:setVisible(false)
    pcall(function() self:removeFromUIManager() end)
    if parent ~= nil then
        if parent.picker == self then parent.picker = nil end
        pcall(function() parent:removeChild(self) end)
    end
end

function Picker:drawRow(y, item, alt)
    local t = creatorTheme
    self:drawRect(0, y, self.width, self.itemheight, alt and 0.12 or 0.06,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    local entry = item.item
    local size = math.max(16, self.itemheight - 6)
    local physical = entry and type(entry.fullType)=="string" and entry.fullType:match("^[%w_]+%.[%w_]+$")
    local texture = entry and entry.texture or (physical and itemIcon(entry.fullType) or nil)
    if texture ~= nil then
        self:drawTextureScaledAspect(texture, 6, y + 3, size, size, 1, 1, 1, 1)
    end
    self:drawText(UILayout.fitText(UIFont.Small, tostring(item.text), self.width - size - 24), size + 14, y + 4,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    return y + self.itemheight
end

function Picker:onRow(item)
    if type(item) ~= "table" then return end
    local entry, onPick = item, self.onPick
    self:close()
    if onPick ~= nil then onPick(entry.fullType, entry) end
end
-- The card grid: a clipped, wheel-scrolled area whose geometry comes from the
-- model's own cardGrid rule, so what is drawn and what a click hits agree.
local Cards = ISPanel:derive("KnoxCreatorCards")

function Cards:new(x, y, width, height, window)
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.window = window
    panel.scroll = 0
    panel.emptyText = "Nobody here yet."
    panel:initialise()
    return panel
end

function Cards:prerender()
    local t = creatorTheme
    self:drawRect(0, 0, self.width, self.height, 0.55,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    self:setStencilRect(0, 0, self.width, self.height)
end

-- The starting-cast toggles sit in the free row between outfit and weapon. This
-- one function is what both the drawing and the click use, so they cannot
-- disagree about where the boxes are.
-- Vanilla checkbox idiom: a small bordered box, a tick when set, the label to
-- the right. One function still owns both the drawing and the click geometry.
local tickTexture, tickTried = nil, false
local function checkTexture()
    if tickTried then return tickTexture end
    tickTried = true
    pcall(function()
        local tex = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
        if tex ~= nil then tickTexture = tex end
    end)
    return tickTexture
end

local function startRects(card)
    local box, gap = 14, 5
    local function labelW(text, fallback)
        local ok, w = pcall(function()
            return getTextManager():MeasureStringX(UIFont.Small, text)
        end)
        return (ok and math.ceil(tonumber(w) or fallback)) or fallback
    end
    local joinW = box + gap + labelW("Companion", 62)
    local spouseW = box + gap + labelW("Spouse", 44)
    local spawnW = box + gap + labelW("Spawn", 50)
    local height = 16
    local y = card.y + card.height - ROW_H * 2
    local join = { x = card.x + 8, y = y, w = joinW, h = height, box = box, gap = gap }
    local spouse = { x = card.x + 8 + joinW + 6, y = y, w = spouseW, h = height,
        box = box, gap = gap }
    -- The spawn-pool switch sits one row above the starting cast: it is the
    -- master switch so it reads first, and the card is not wide enough for
    -- three boxes in one row.
    local spawn = { x = card.x + 8, y = card.y + card.height - ROW_H * 3,
        w = spawnW, h = height, box = box, gap = gap }
    return join, spouse, spawn
end

local function companionLimit()
    local settings = rawget(_G, "KnoxSettings")
    -- The sandbox default is 3; a harness without settings answers the default
    -- instead of pretending companions are banned.
    if settings == nil or settings.companionLimit == nil then return 3 end
    local ok, value = pcall(settings.companionLimit)
    return ok and tonumber(value) or 3
end

function Cards:drawCard(card, person)
    local t = creatorTheme
    local win = self.window
    local selected = win ~= nil and win.selectedIndex == (win.view[card.index] or {}).index
    local factionId = Creator.personFactionId(person, win ~= nil and win.group or nil)
    local label = Creator.factionLabel(factionId,
        win ~= nil and win.group and win.group.defs or nil)
    local accent = accentFor(label)
    self:drawRect(card.x, card.y, card.width, card.height, 0.96,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    self:drawRect(card.x, card.y, card.width, 5, 0.95, accent[1], accent[2], accent[3])
    self:drawRectBorder(card.x, card.y, card.width, card.height,
        selected and 0.95 or 0.55, selected and t.bone[1] or t.border[1],
        selected and t.bone[2] or t.border[2], selected and t.bone[3] or t.border[3])
    if selected then
        self:drawRectBorder(card.x + 1, card.y + 1, card.width - 2, card.height - 2,
            0.75, accent[1], accent[2], accent[3])
    end
    self:drawText(UILayout.fitText(UIFont.Medium, tostring(person.name or "Unnamed"), card.width - 16), card.x + 8, card.y + 12,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Medium)
    self:drawText(UILayout.fitText(UIFont.Small, label, card.width - 16), card.x + 8, card.y + 12 + ROW_H,
        t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
    local items = gearItems(person)
    local size, gap = 26, 4
    local y = card.y + 12 + ROW_H * 2
    for index = 1, math.min(#items, math.floor((card.width - 16 + gap) / (size + gap))) do
        local texture = itemIcon(items[index])
        local x = card.x + 8 + (index - 1) * (size + gap)
        if texture ~= nil then
            self:drawTextureScaledAspect(texture, x, y, size, size, 1, 1, 1, 1)
        else
            self:drawRect(x, y, size, size, 0.20, t.border[1], t.border[2], t.border[3])
        end
    end
    -- The outfit line moves up under the gear icons to free its old row for
    -- the spawn-pool switch. Icons are a fixed 26 tall, so this clears them at
    -- any row height.
    self:drawText(UILayout.fitText(UIFont.Small, "Outfit: " .. labelOf(Creator.LOOKS, person.look, "Custom"), card.width - 16),
        card.x + 8, y + 30,
        t.label[1], t.label[2], t.label[3], 1, UIFont.Small)
    local joinBox, spouseBox, spawnBox = startRects(card)
    local boxes = {
        { rect = spawnBox, on = Creator.spawnIncluded(person), label = "Spawn" },
        { rect = joinBox, on = person.startCompanion == true, label = "Companion" },
        { rect = spouseBox, on = person.startSpouse == true, label = "Spouse" },
    }
    for _, spec in ipairs(boxes) do
        local rect = spec.rect
        local box, gap = rect.box or 14, rect.gap or 5
        local by = rect.y + math.max(0, math.floor((rect.h - box) / 2))
        self:drawRectBorder(rect.x, by, box, box, 0.85,
            t.border[1], t.border[2], t.border[3])
        if spec.on then
            local tex = checkTexture()
            local r, g, b = 1, 1, 1
            pcall(function()
                local c = getCore():getGoodHighlitedColor()
                r, g, b = c:getR(), c:getG(), c:getB()
            end)
            if tex ~= nil then
                self:drawTextureScaled(tex, rect.x + 2, by + 2, box - 4, box - 4,
                    1, r, g, b)
            else
                self:drawRect(rect.x + 3, by + 3, box - 6, box - 6, 0.9, r, g, b)
            end
        end
        self:drawText(UILayout.fitText(UIFont.Small, spec.label,
            math.max(1, rect.w - box - gap)), rect.x + box + gap, rect.y + 1,
            t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    end
    local carried = Panel.effectiveSlot(person, Creator.slotById("primary"))
    self:drawText(UILayout.fitText(UIFont.Small, carried and carried.label or "No weapon", card.width - 16),
        card.x + 8, card.y + card.height - ROW_H,
        t.dim[1], t.dim[2], t.dim[3], 1, UIFont.Small)
end

function Cards:render()
    local win = self.window
    if win == nil then
        self:clearStencilRect()
        return
    end
    local grid = Creator.cardGrid(#win.view, 0, 0, self.width, self.height, self.scroll, ROW_H)
    if #win.view == 0 then
        self:drawText(UILayout.fitText(UIFont.Small, self.emptyText, self.width - 20), 10, 10,
            creatorTheme.muted[1], creatorTheme.muted[2], creatorTheme.muted[3],
            1, UIFont.Small)
    end
    for _, card in ipairs(grid.cards) do
        local entry = win.view[card.index]
        if entry ~= nil then self:drawCard(card, entry.person) end
    end
    self:clearStencilRect()
    if grid.maxScroll > 0 then
        local ratio = grid.scroll / grid.maxScroll
        local trackH = self.height - 8
        local barH = math.max(24, trackH * (self.height / grid.contentHeight))
        self:drawRect(self.width - 6, 4 + (trackH - barH) * ratio, 3, barH,
            0.55, creatorTheme.border[1], creatorTheme.border[2],
            creatorTheme.border[3])
    end
end

function Cards:clampScroll()
    local grid = Creator.cardGrid(#self.window.view, 0, 0, self.width, self.height, self.scroll, ROW_H)
    self.scroll = grid.scroll
end

function Cards:onMouseWheel(delta)
    if self.window == nil then return false end
    self.scroll = self.scroll - (delta or 0) * 48
    self:clampScroll()
    return true
end

function Cards:onMouseDown(x, y)
    if self.window == nil then return false end
    local grid = Creator.cardGrid(#self.window.view, 0, 0, self.width, self.height, self.scroll, ROW_H)
    for _, card in ipairs(grid.cards) do
        if x >= card.x and x <= card.x + card.width
            and y >= card.y and y <= card.y + card.height then
            local joinBox, spouseBox, spawnBox = startRects(card)
            local function inside(rect)
                return x >= rect.x and x <= rect.x + rect.w
                    and y >= rect.y and y <= rect.y + rect.h
            end
            local field = nil
            if inside(joinBox) then field = "companion"
            elseif inside(spouseBox) then field = "spouse"
            elseif inside(spawnBox) then field = "spawn" end
            local entry = self.window.view[card.index]
            if field ~= nil and entry ~= nil then
                local ok, message, title
                if field == "spawn" then
                    ok, message = Creator.toggleSpawn(self.window.roster, entry.person)
                else
                    ok, message, title = Creator.toggleStart(self.window.roster,
                        entry.person, field, companionLimit())
                end
                self.window.dirty = true
                if self.window.setNote ~= nil then self.window:setNote(message) end
                if not ok and self.window.showStartRefusal ~= nil then
                    self.window:showStartRefusal(title, message)
                end
                self.window:refresh()
                return true
            end
            self.window:selectCard(card.index)
            return true
        end
    end
    return false
end

-- The detail column scrolls: at 720p there is not enough height for the preview,
-- seven slots, nine choices and fourteen skills at once.
local Detail = ISPanel:derive("KnoxCreatorDetail")

function Detail:new(x, y, width, height)
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.scrollY = 0
    panel.contentHeight = height
    panel:initialise()
    return panel
end

function Detail:addScrollChild(child, baseY)
    child.knoxBaseY = baseY
    self:addChild(child)
end

function Detail:applyScroll()
    for _, child in pairs(self.children or {}) do
        if child.knoxBaseY ~= nil then
            local y = child.knoxBaseY - self.scrollY
            child:setY(y)
            child:setVisible(not child.knoxHidden and child.knoxPage == (self.page or "person")
                and y >= 0 and y + (child.height or 0) <= self.height)
        end
    end
end

function Detail:onMouseWheel(delta)
    local maxScroll = math.max(0, self.contentHeight - self.height)
    self.scrollY = clamp(self.scrollY - (delta or 0) * 36, 0, maxScroll)
    self:applyScroll()
    return true
end
-- One slot cell: real icon, slot name and the chosen item's own name.
local Cell = ISPanel:derive("KnoxCreatorSlotCell")

function Cell:new(x, y, width, height, slot)
    local cell = ISPanel:new(x, y, width, height)
    setmetatable(cell, self)
    self.__index = self
    cell.slot = slot
    cell.title = ""
    cell.detail = ""
    cell.texture = nil
    cell.enabled = false
    return cell
end

function Cell:prerender()
    local t = creatorTheme
    local pad = 6
    self:drawRect(0, 0, self.width, self.height, self.enabled and 0.92 or 0.55,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    self:drawRectBorder(0, 0, self.width, self.height, 0.85,
        t.border[1], t.border[2], t.border[3])
    if self.enabled then
        self:drawRect(0, 0, 2, self.height, 0.95, t.amber[1], t.amber[2], t.amber[3])
    end
    local textX = pad + 4
    if self.texture ~= nil then
        local size = math.min(self.height - pad * 2, 30)
        self:drawTextureScaledAspect(self.texture, pad, (self.height - size) / 2, size, size,
            1, 1, 1, 1)
        textX = pad + size + pad
    end
    self:drawText(UILayout.fitText(UIFont.Small, self.title, self.width - textX - pad), textX, pad,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    self:drawText(UILayout.fitText(UIFont.Small, self.detail, self.width - textX - pad), textX, pad + math.floor((self.height - pad * 2) / 2),
        t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
end

function Cell:onMouseDown(x, y)
    if self.enabled and self.onStep ~= nil then self.onStep(self) end
    return true
end

-- Slot cells keep their established layout and share the installed button's
-- tooltip lifecycle instead of adding a second information panel.
function Cell:render()
    ISButton.updateTooltip(self)
end

-- A one-line prompt, used for a new faction and a new person.
local Prompt = ISPanel:derive("KnoxCreatorPrompt")

function Prompt:new(x, y, width, height, caption, onAccept)
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.caption = caption
    panel.onAccept = onAccept
    panel:initialise()
    return panel
end

function Prompt:createChildren()
    local t = creatorTheme
    self.backgroundColor = { r = t.charcoal[1], g = t.charcoal[2], b = t.charcoal[3], a = 0.98 }
    self.borderColor = { r = t.border[1], g = t.border[2], b = t.border[3], a = 0.95 }
    self.label = ISLabel:new(PAD, PAD, ROW, self.caption, t.bone[1], t.bone[2],
        t.bone[3], 1, UIFont.Small, true)
    self.label:initialise()
    self:addChild(self.label)
    self.entry = ISTextEntryBox:new("", PAD, PAD + ROW, self.width - PAD * 2, ROW)
    self.entry:initialise()
    self:addChild(self.entry)
    local width = math.floor((self.width - PAD * 3) / 2)
    self.ok = addButton(self, PAD, self.height - ROW - PAD, width, ROW, "Apply", self,
        Prompt.onOk)
    self.cancel = addButton(self, PAD * 2 + width, self.height - ROW - PAD, width, ROW,
        "Cancel", self, Prompt.onCancel)
end

function Prompt:onOk()
    local text = ""
    pcall(function() text = self.entry:getText() end)
    local accept = self.onAccept
    self:close()
    if accept ~= nil then accept(text) end
end

function Prompt:onCancel()
    self:close()
end

function Prompt:close()
    self:setVisible(false)
    pcall(function() self:removeFromUIManager() end)
    local parent = self.parent
    if parent ~= nil then
        if parent.prompt == self then parent.prompt = nil end
        parent:removeChild(self)
    end
end

local Window = ISCollapsableWindowJoypad:derive("KnoxCreatorWindow")
AppearanceUI.install(Panel, Window, Creator, UILayout)

function Window:createChildren()
    Creator.refreshSkillCatalogue()
    Creator.refreshProfessionCatalogue()
    computeMetrics()
    ISCollapsableWindowJoypad.createChildren(self)
    self:setWidth(WIDTH)
    self:setHeight(HEIGHT)
    if self.pinButton ~= nil then self.pinButton:setVisible(false) end
    if self.collapseButton ~= nil then self.collapseButton:setVisible(false) end
    pcall(UILayout.tintWindow, self)
    UILayout.finishWindow(self, "Close Creator")
    local material = creatorTheme.charcoal
    self.backgroundColor = {r=material[1], g=material[2], b=material[3], a=1}
    self.resizable = false

    local top = self:titleBarHeight() + PAD * 0.6
    local nameWidth = math.floor(WIDTH * 0.22)
    self.groupEntry = nil
    local heading = ISLabel:new(PAD, top, TOOLBAR_H - 10, "PEOPLE OF KNOX",
        creatorTheme.bone[1], creatorTheme.bone[2], creatorTheme.bone[3], 1, UIFont.Small, true)
    heading:initialise(); self:addChild(heading)

    local buttonH = TOOLBAR_H - 10
    -- "Use preset" is gone on purpose: a preset used to be the only way to make a
    -- group, so every new faction silently became a household. Choosing a kind is
    -- now part of New group, which is the same decision made in one place.
    local labels = { "Create...", "Add person", "Rename group", "Delete group", "Save", "Close", "Defaults: hidden", "Custom: show" }
    local callbacks = { Window.onNewFaction, Window.onAddPerson, Window.onRenameFaction,
        Window.onDeleteFaction, Window.onSave, Window.onClose,
        Window.onToggleDefaults, Window.onToggleCustom }
    local x = PAD + nameWidth + PAD
    local available = WIDTH - x - PAD
    local longest = 0
    for _, text in ipairs(labels) do
        longest = math.max(longest, getTextManager():MeasureStringX(UIFont.Small, text) + 20)
    end
    local columns = available / #labels >= longest and #labels or 4
    local rows = math.ceil(#labels / columns)
    local width = math.floor(available / columns) - 4
    for index = 1, #labels do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        addButton(self, x + column * (width + 4), top + row * (buttonH + 4),
            width, buttonH, labels[index], self, callbacks[index])
    end

    local bodyY = top + math.max(TOOLBAR_H, rows * (buttonH + 4) + 4)
    local bodyH = HEIGHT - bodyY - FOOTER_H - PAD

    self.crumb = ISLabel:new(PAD, bodyY, CRUMB_H, "", creatorTheme.bone[1],
        creatorTheme.bone[2], creatorTheme.bone[3], 1, UIFont.Small, true)
    self.crumb:initialise()
    self:addChild(self.crumb)

    self:createFactionList(PAD, bodyY + CRUMB_H, RAIL_W, bodyH - CRUMB_H, ROW_H)

    local detailX = WIDTH - PAD - DETAIL_W
    local cardsX = PAD + RAIL_W + PAD
    local centerW = detailX - PAD - cardsX
    local cardsW = math.min(220, math.max(80, math.floor(centerW * 0.38)))
    local previewX = cardsX + cardsW + PAD
    local previewW = detailX - PAD - previewX
    local contentY = bodyY + CRUMB_H
    self.cards = Cards:new(cardsX, contentY, cardsW, bodyH - CRUMB_H, self)
    self.knoxDetailX = detailX
    self.knoxCardsRight = cardsX + cardsW
    self:addChild(self.cards)

    self.previewName = ISLabel:new(previewX + PAD, contentY, ROW_H, "",
        0.9, 0.88, 0.8, 1, UIFont.Medium, true)
    self.previewName:initialise(); self:addChild(self.previewName)
    self.preview = ISUI3DModel:new(previewX, contentY + ROW_H, previewW,
        bodyH - CRUMB_H - ROW_H * 2)
    self.preview:initialise()
    self:addChild(self.preview)
    self.previewSet = pcall(function()
        self.preview:setIsometric(false)
        self.preview:setDirection(IsoDirections.S)
        self.preview:setZoom(-0.5)
        self.preview:setState("idle")
        self.preview:setDoRandomExtAnimations(false)
        self.preview:setAnimateWhilePaused(true)
    end)
    local hint = ISLabel:new(previewX + PAD, HEIGHT - FOOTER_H - ROW_H - PAD,
        ROW_H, "Drag to turn", 0.55, 0.55, 0.5, 1, UIFont.Small, true)
    hint:initialise(); self:addChild(hint)
    self.previewHint = hint
    local pageY = contentY
    self.pageButtons = {}
    local pageW = math.floor((DETAIL_W - 9) / 4)
    for index, page in ipairs({ {"person", "Person"}, {"gear", "Gear"},
        {"skills", "Skills"}, {"group", "Group"} }) do
        local button = addButton(self, detailX + (index - 1) * (pageW + 3), pageY,
            pageW, ROW_H, page[2], self, Window.onPage)
        button.knoxPage = page[1]
        self.pageButtons[#self.pageButtons + 1] = button
    end
    local detailY = pageY + ROW_H + CELL_GAP
    self.detail = Detail:new(detailX, detailY, DETAIL_W,
        HEIGHT - detailY - FOOTER_H - PAD)
    self:addChild(self.detail)
    self.detail.page = self.detailPage or "person"
    local function child(control, page, y)
        control.knoxPage = page
        self.detail:addScrollChild(control, y)
        return control
    end
    self.cells = {}
    local fontH = ROW_H - 12
    local columns = Panel.gearColumns(DETAIL_W, fontH)
    local cellW = math.floor((DETAIL_W - CELL_GAP * (columns - 1)) / columns)
    for index, slot in ipairs(Creator.SLOTS) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local y = row * (CELL_H + CELL_GAP)
        local cell = Cell:new(column * (cellW + CELL_GAP), y, cellW, CELL_H, slot)
        cell.onStep = function(clicked) self:openPicker(clicked.slot) end
        child(cell, "gear", y)
        self.cells[#self.cells + 1] = cell
    end
    local afterCells = math.ceil(#Creator.SLOTS / columns) * (CELL_H + CELL_GAP)
    self.choiceButtons = {}
    local rows = {
        {kind="name", page="person"}, {kind="skin", page="person"},
        {kind="colour", page="person"}, {kind="random", page="person"},
        {kind="clearPresets", page="gear"},
    }
    local pageRows = {person=0, gear=afterCells, group=0}
    for _, row in ipairs(rows) do
        local y = pageRows[row.page]
        local swatch = row.kind == "skin" or row.kind == "colour"
        if swatch then
            local label = ISLabel:new(0, y, ROW_H, row.kind == "skin" and "Skin tone" or "Hair colour",
                0.85, 0.85, 0.8, 1, UIFont.Small, true)
            label:initialise(); child(label, row.page, y)
        end
        local button = addButton(self.detail, swatch and math.floor(DETAIL_W * 0.55) or 0, y,
            swatch and ROW_H or DETAIL_W, ROW_H, "", self, Window.onCycleChoice)
        button.knoxKind = row.kind
        child(button, row.page, y)
        self.choiceButtons[#self.choiceButtons + 1] = button
        pageRows[row.page] = y + ROW_H + CELL_GAP
    end
    -- Use the same native dropdown class as player character creation. Labels
    -- and controls share a row, and the detail owner scrolls them together.
    self.fieldCombos = {}
    local labelW = math.floor(DETAIL_W * 0.31)
    for _, row in ipairs({{"sex","Sex","person"}, {"profession","Occupation","person"},
        {"hair","Hair","person"}, {"beard","Beard","person"},
        {"look","Outfit","gear"},
        {"faction","Group","group"}}) do
        local kind, caption, page = row[1], row[2], row[3]
        local y = pageRows[page]
        local label = ISLabel:new(0, y, ROW_H, UILayout.fitText(UIFont.Small, caption, labelW - 6),
            0.85, 0.85, 0.8, 1, UIFont.Small, true)
        label:initialise(); child(label, page, y)
        local combo = ISComboBox:new(labelW, y, DETAIL_W - labelW - 4, ROW_H,
            self, Window.onFieldSelected)
        combo:initialise()
        combo.knoxKind = kind
        child(combo, page, y)
        self.fieldCombos[#self.fieldCombos + 1] = combo
        pageRows[page] = y + ROW_H + CELL_GAP
    end
    local removeY = pageRows.person
    local remove = addButton(self.detail, 0, removeY, DETAIL_W, ROW_H, "", self, Window.onCycleChoice)
    remove.knoxKind = "remove"; child(remove, "person", removeY)
    self.choiceButtons[#self.choiceButtons + 1] = remove
    pageRows.person = removeY + ROW_H + CELL_GAP
    self.groupButtons = {}
    for _, kind in ipairs({"copy", "editDefault", "resetDefault", "profile", "attitude", "memberCount", "spawnContext",
        "vehiclePolicy", "settlementPolicy", "region", "populate"}) do
        local y = pageRows.group
        local button = addButton(self.detail, 0, y, DETAIL_W, ROW_H, "", self, Window.onGroupPolicy)
        button.knoxKind = kind
        child(button, "group", y)
        self.groupButtons[#self.groupButtons + 1] = button
        pageRows.group = y + ROW_H + CELL_GAP
    end
    local traitButton = addButton(self.detail, 0, 0, DETAIL_W, ROW_H,
        "Traits...", self, Window.onTraits)
    child(traitButton, "skills", 0)
    self.traitButton = traitButton
    self.skillButtons = {}
    local skillW = math.floor((DETAIL_W - CELL_GAP) / 2)
    for index, perkId in ipairs(Creator.SKILLS) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        local y = ROW_H + CELL_GAP + row * (SKILL_H + CELL_GAP)
        local button = addButton(self.detail, column * (skillW + CELL_GAP), y, skillW,
            SKILL_H, perkId, self, Window.onCycleSkill)
        button.knoxPerk = perkId
        child(button, "skills", y)
        self.skillButtons[#self.skillButtons + 1] = button
    end
    self.pageHeights = pageRows
    self.pageHeights.skills = ROW_H + CELL_GAP + math.ceil(#Creator.SKILLS / 2) * (SKILL_H + CELL_GAP)
    self.basePageHeights = {}
    for page, height in pairs(self.pageHeights) do self.basePageHeights[page] = height end
    self.detail.contentHeight = self.pageHeights[self.detail.page] or self.detail.height

    self.note = ISLabel:new(PAD, HEIGHT - FOOTER_H, FOOTER_H, "", creatorTheme.muted[1],
        creatorTheme.muted[2], creatorTheme.muted[3], 1, UIFont.Small, true)
    self.note:initialise()
    self:addChild(self.note)

    pcall(UILayout.trackWindow, self)
end

function Window:createFactionList(x, y, width, height, rowHeight)
    self.railList = ISScrollingListBox:new(x, y, width, height)
    self.railList:initialise()
    self.railList:instantiate()
    self.railList.itemheight = rowHeight * 2
    self.railList.font = UIFont.Small
    self.railList.drawBorder = true
    local win = self
    self.railList.doDrawItem = function(list, y, item, alt)
        return Window.drawRailRow(win, list, y, item, alt)
    end
    self.railList:setOnMouseDownFunction(self, function(target, item)
        if item ~= nil then win:onRailRow(item) end
    end)
    self:addChild(self.railList)

end

function Window:drawRailRow(list, y, item, alt)
    local t = creatorTheme
    local row = item.item or {}
    local selected = (row.kind == "faction" or row.kind == "cast") and self.selectedFactionId == row.id
    if y + list.itemheight < 0 or y > list.height - list:getYScroll() then return y + list.itemheight end
    list:drawRect(0, y, list.width, list.itemheight, 1, selected and 0.18 or 0.075,
        selected and 0.19 or 0.08, selected and 0.16 or 0.075)
    list:drawRect(6, y + list.itemheight - 1, list.width - 18, 1, 0.7,
        t.border[1], t.border[2], t.border[3])
    if selected then list:drawRect(0, y, 3, list.itemheight, 1, t.amber[1], t.amber[2], t.amber[3]) end
    list:drawText(UILayout.fitText(UIFont.Small, row.label or "", list.width - 30),
        12, y + 8, t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    -- The caption names the kind, because that is the decision the player made:
    -- a Household and a Robbers group behave differently even with equal counts.
    local caption
    if row.kind == "cast" then
        caption = row.caption or "Marked to join at save start"
    elseif row.kind == "faction" then
        -- A row inherited from a shipped kind is a starting point, not a group the
        -- player owns; saying so keeps a descriptor from reading as a ready-made
        -- faction. The player's own groups name their kind and their people.
        caption = row.template
            and ("DEFAULT - " .. tostring(row.count or 0) .. " planned people")
            or ((Creator.isDefault(row.id) and "EDITED DEFAULT - " or (row.solo and "" or "CUSTOM - "))
                .. tostring(row.kindLabel or "Group") .. " - " .. tostring(row.count or 0)
                .. (row.solo and " independent" or " people"))
    else
        caption = "A family, gang, crew or service you name"
    end
    list:drawText(UILayout.fitText(UIFont.Small, caption, list.width - 30), 12, y + 8 + math.floor(list.itemheight / 2),
        t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
    return y + list.itemheight
end

function Window:selected()
    if self.selectedIndex == nil then return nil end
    return (self.templateRoster or self.roster)[self.selectedIndex]
end

function Window:selectedFaction()
    local factionId = self.selectedFactionId
    if factionId == nil then
        local person = self:selected()
        factionId = Creator.personFactionId(person, self.group)
    end
    return Creator.factionIndexIn(self.group.defs, factionId)
end

function Window:setNote(text)
    if self.note ~= nil then pcall(function() self.note:setName(UILayout.fitText(UIFont.Small, tostring(text or ""), self.width - PAD * 2))
        self.note.tooltip = tostring(text or "") end) end
end

-- A refusal interrupts: the rule appears centered over the cards, titled with
-- the short rule name, while the note line keeps the full sentence. Success
-- stays quiet in the note line, so ticking through a cast never pops.
function Window:showStartRefusal(title, message)
    local modalClass = rawget(_G, "ISModalRichText")
    if modalClass == nil then return end
    local text = tostring(title or "Starting party") .. " <LINE> <LINE> "
        .. tostring(message or ""):gsub("<", "["):gsub(">", "]")
    local sw, sh = UILayout.screenSize()
    sw, sh = tonumber(sw) or 800, tonumber(sh) or 600
    local width = math.max(280, math.min(440, sw - 40))
    local height = 190
    local modal = modalClass:new(math.floor((sw - width) / 2),
        math.floor((sh - height) / 2), width, height, text, false, nil, nil, 0)
    modal.prevFocus = self
    local joyDown, keyRelease = modal.onJoypadDown, modal.onKeyRelease
    modal.onJoypadDown = function(dialog, button)
        if button == Joypad.BButton then dialog:destroy(); return end
        if joyDown ~= nil then joyDown(dialog, button) end
    end
    modal.onKeyRelease = function(dialog, key)
        if key == Keyboard.KEY_ESCAPE then dialog:destroy(); return true end
        if keyRelease ~= nil then return keyRelease(dialog, key) end
        return false
    end
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

function Window:selectCard(viewIndex)
    self:closeColourPicker()
    local entry = self.view[viewIndex]
    if entry == nil then return end
    self.selectedIndex = entry.index
    self.selectedFactionId = Creator.personFactionId(entry.person, self.group)
    self:refresh()
end

-- A shipped kind that still holds people is a real group; an empty one is an
-- unsaved preview. Solo is neither: it is the bucket for people with no group, so
-- it must never be preview-populated into a faction.
function Window:selectFaction(id)
    self:closeColourPicker()
    -- The companions view is a filter over the roster, not a faction, so it
    -- never previews or populates: it names the marked and the rule.
    if id == "starting" then
        self.selectedFactionId, self.selectedIndex, self.templateRoster = id, nil, nil
        local companions, spouse = Creator.startCounts(self.roster)
        local cast = Creator.markedCast(self.roster)
        if cast[1] then self.selectedIndex = cast[1].index end
        if self.cards then self.cards.scroll = 0 end
        self:setNote("Spouses and companions: tick Companion or Spouse on any card. "
            .. tostring(companions) .. " companion"
            .. (companions == 1 and "" or "s")
            .. " and " .. (spouse ~= nil and "1 spouse" or "no spouse")
            .. " marked - everyone unmarked is seeded instead.")
        return
    end
    self.selectedFactionId, self.selectedIndex, self.templateRoster = id, nil, nil
    local faction = Creator.factionIndexIn(self.group.defs, id)
    local solo = faction ~= nil and faction.group ~= true
    if faction and faction.user ~= true and not solo
        and #Creator.peopleByFaction(self.roster, self.group, id) == 0 then
        local preview = {}
        local policy = Creator.profileFor(id, self.group.defs)
        Creator.populateFaction(preview, self.group, id, policy.memberCount, self.roster)
        self.templateRoster = preview
    end
    local people = Creator.peopleByFaction(self.templateRoster or self.roster, self.group, id)
    if people[1] then self.selectedIndex = people[1].index end
    if self.cards then self.cards.scroll = 0 end
    if solo then
        self:setNote("Solo survivors belong to no group. Each one is independent. Add person puts somebody here.")
    elseif self.templateRoster then
        self:setNote("Kind preview, not your group. Copy it into a group of your own, then add people there.")
    else
        local where = faction ~= nil and faction.label or "All factions"
        self:setNote("Adding to: " .. where .. ". Select a person to customize their appearance, loadout and group.")
    end
end

function Window:onRailRow(row)
    if row.kind == "new" then self:onNewFaction(); return end
    if row.kind == "faction" or row.kind == "cast" then self:selectFaction(row.id) end
    self:refresh()
end

function Window:onToggleDefaults(button)
    self.hideDefaults = not self.hideDefaults
    button:setTitle(self.hideDefaults and "Defaults: hidden" or "Defaults: show")
    self:refreshRail()
end

function Window:onToggleCustom(button)
    self.hideCustom = not self.hideCustom
    button:setTitle(self.hideCustom and "Custom: hidden" or "Custom: show")
    self:refreshRail()
end

function Window:onUsePreset()
    local faction = self:selectedFaction()
    if not faction then self:setNote("Choose a kind on the left first."); return end
    if faction.group ~= true then
        self:setNote("Solo survivors are not a group, so there is nothing to copy.") return
    end
    self:promptFor("Name your group", function(text)
        local ok, entry = Creator.copyFaction(self.group.defs, faction.id, text)
        if not ok then self:setNote(entry); return end
        local policy = Creator.profileFor(entry.id, self.group.defs)
        local added, reason = Creator.populateFaction(self.roster, self.group, entry.id, policy.memberCount)
        self:selectFaction(entry.id)
        self.dirty = true
        self:refresh()
        self:setNote(added and "Your group is ready. Edit its people and loadouts, then Save."
            or ("Group copied; people could not be added: " .. tostring(reason)))
    end, faction.label .. " copy")
end

function Window:openChooser(entries, caption, onPick)
    self:closePicker()
    local width = math.floor(WIDTH * 0.42)
    local height = math.min(HEIGHT - 120, math.floor(HEIGHT * 0.62))
    self.picker = Picker:new(math.floor((WIDTH - width) / 2), self:titleBarHeight() + PAD,
        width, height, entries, onPick, caption)
    self.picker.person = self:selected()
    self:addChild(self.picker)
    self.picker:bringToTop()
end

-- A slot lists exactly what that slot accepts: clothing for a clothing slot, a
-- container for the bag, a real weapon for either hand, and a way to clear it.
function Window:openPicker(slot)
    if self.templateRoster or self.group.readOnly then return end
    local person = self:selected()
    if slot == nil or person == nil then return end
    if slot.id == "secondary" then
        local primary = Panel.effectiveSlot(person, Creator.slotById("primary"))
        if primary and Creator.isTwoHanded(primary.fullType) then
            self:setNote("This weapon occupies both hands. Change the primary weapon first.") return
        end
    end
    local entries = { { fullType = false,
        label = slot.kind == "clothing" and "From outfit" or "None" } }
    if slot.kind == "clothing" then entries[#entries + 1] = {fullType="__none",label="None - leave this slot empty"} end
    if slot.kind == "weapon" then
        for _, option in ipairs(Creator.weaponCatalogue()) do
            if type(option.fullType) == "string" and option.fullType ~= "" then
                entries[#entries + 1] = { fullType = option.fullType, label = option.label }
            end
        end
    else
        for _, option in ipairs(Creator.slotCatalogue(slot.id)) do
            entries[#entries + 1] = { fullType = option.fullType, label = option.label }
        end
    end
    local caption = (slot.kind == "weapon" and "Search weapons - " or "Search clothing - ")
        .. tostring(slot.label)
    self:openChooser(entries, caption, function(fullType)
        person.slots = person.slots or {}
        if fullType == false then
            person.slots[slot.id] = nil
            if slot.kind ~= "clothing" then person.slots[slot.id] = "__none" end
        else
            person.slots[slot.id] = fullType
        end
        self.dirty = true
        self:refresh()
    end)
end

function Window:onCycleChoice(button)
    if self.templateRoster or self.group.readOnly then return end
    local person = self:selected()
    if person == nil or button == nil then return end
    local kind = button.knoxKind
    if kind == "name" then
        self:promptFor("Person's name", function(text)
            local name = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if #name < 2 or #name > Creator.MAX_NAME or name:find("[|\r\n]") then
                self:setNote("Use a name between 2 and " .. Creator.MAX_NAME .. " characters.") return
            end
            for _, other in ipairs(self.roster) do
                if other ~= person and Creator.nameKey(other.name) == Creator.nameKey(name) then
                    self:setNote("Somebody here already has that name.") return
                end
            end
            person.name = name; self.dirty = true; self:refresh()
        end, person.name)
        return
    elseif kind == "remove" then
        self:promptFor("Type their name to remove them", function(text)
            if text ~= person.name then self:setNote("Name did not match. Nobody removed.") return end
            table.remove(self.roster, self.selectedIndex)
            self.selectedIndex = nil; self.dirty = true; self:refresh()
        end)
        return
    elseif kind == "cargo" or kind == "bagCargo" then
        self:openCargo(person, kind == "bagCargo" and "backpack" or "main")
        return
    elseif kind == "clearPresets" then
        person.kit, person.pack = "none", "none"
        self.dirty = true; self:refresh()
        return
    elseif kind == "skin" or kind == "colour" then
        self:openColourPicker(kind, person, button)
        return
    elseif kind == "random" then
        Creator.randomizeAppearance(person, Panel.hairOptions(person.female), Panel.beardOptions(person.female))
    else return end
    self.dirty = true
    self:refresh()
end

function Window:onPage(button)
    self:closeColourPicker()
    self.detailPage = button.knoxPage
    self.detail.page, self.detail.scrollY = self.detailPage, 0
    self:refreshDetail()
end

-- A visible list is a projection of the existing codec fields, never another
-- inventory authority. Unknown modded items remain named and removable.
function Panel.cargoRows(person, field)
    local rows = {}
    for fullType, count in pairs(person and person[field] or {}) do
        local info = LoadoutInfo.item(fullType)
        rows[#rows + 1] = {fullType=fullType, count=count,
            label=info and info.name or ("Unavailable item: " .. fullType)}
    end
    table.sort(rows, function(a,b)
        local left, right = string.lower(a.label), string.lower(b.label)
        return left == right and a.fullType < b.fullType or left < right
    end)
    return rows
end

function Window:canEditCargo(person)
    return person ~= nil and self:selected() == person and not self.templateRoster
        and not self.group.readOnly
end

function Window:applyCargoQuantity(person, field, fullType, count)
    if not self:canEditCargo(person) then
        self:setNote("Select the original editable person before changing supplies.") return false
    end
    if field ~= "cargo" and field ~= "bagCargo" then return false end
    if type(count) ~= "number" or count ~= math.floor(count) or count < 0 or count > 100 then
        self:setNote("Choose a whole number from 0 to 100.") return false
    end
    if field == "bagCargo" and count > 0 and not (person[field] or {})[fullType] then
        local bag = Panel.effectiveSlot(person, Creator.slotById("backpack"))
        if not bag or not bag.fullType then
            self:setNote("Choose a backpack before adding its supplies.") return false
        end
    end
    local candidate = {}
    for id, amount in pairs(person[field] or {}) do candidate[id] = amount end
    candidate[fullType] = count > 0 and count or nil
    local kept = Creator.decodeCargo(Creator.encodeCargo(candidate))
    if count > 0 and kept[fullType] ~= count then
        self:setNote("The carried-supply list is full.") return false
    end
    -- A sorted codec truncates at 64. Refuse additions that would evict a saved
    -- row, even when the new ID sorts ahead of the old final row.
    for id, amount in pairs(person[field] or {}) do
        if id ~= fullType and kept[id] ~= amount then
            self:setNote("The carried-supply list is full.") return false
        end
    end
    person[field] = kept
    self.dirty = true
    self:refresh()
    return true
end

function Window:editCargoQuantity(person, field, fullType, label)
    if not self:canEditCargo(person) then return end
    self:promptFor(tostring(label) .. " - quantity (0 removes, 0-100)", function(text)
        if self:applyCargoQuantity(person, field, fullType, tonumber(text)) then
            self:setNote(tostring(label) .. ": " .. tostring(tonumber(text)) .. " carried.")
        end
    end, tostring((person[field] or {})[fullType] or 1))
end

function Window:onCargoRow(button)
    local person = button.knoxPerson
    if button.knoxRemove then
        if self:applyCargoQuantity(person, button.knoxField, button.knoxItem, 0) then
            self:setNote("Removed " .. tostring(button.knoxLabel) .. ".")
        end
    elseif button.knoxItem then
        self:editCargoQuantity(person, button.knoxField, button.knoxItem, button.knoxLabel)
    else
        self:openCargo(person, button.knoxField == "bagCargo" and "backpack" or "main")
    end
end

function Window:refreshCargoRows(person)
    if not self.detail or not self.basePageHeights then return end
    self.cargoControls = self.cargoControls or {}
    for _, control in ipairs(self.cargoControls) do control.knoxHidden=true; control:setVisible(false) end
    local y, used = 0, 0
    local editable = self:canEditCargo(person)
    local function row(text, field, entry, remove, enabled)
        used = used + 1
        local control = self.cargoControls[used]
        local x, width = 0, DETAIL_W
        if entry then
            width = DETAIL_W - ROW_H - CELL_GAP
            if remove then x, width = DETAIL_W - ROW_H, ROW_H end
        end
        if not control then
            control = addButton(self.detail, x, y, width, ROW_H, "", self, Window.onCargoRow)
            self.detail:addScrollChild(control, y)
            self.cargoControls[used] = control
        end
        control:setX(x); control:setWidth(width)
        control.knoxBaseY, control.knoxPage, control.knoxHidden = y, "gear", false
        control.knoxPerson, control.knoxField = person, field
        control.knoxItem, control.knoxRemove = entry and entry.fullType, remove
        control.knoxLabel = entry and entry.label
        control:setTitle(UILayout.fitText(UIFont.Small, text, width - 12))
        control.tooltip = entry and (entry.label .. " x" .. tostring(entry.count) .. "\n" .. entry.fullType
            .. (remove and "\nRemove this item" or "\nChange quantity; 0 removes")) or text
        control:setEnable(enabled == true)
        return control
    end
    if person then
        for _, field in ipairs({"cargo", "bagCargo"}) do
            local bag = field == "bagCargo"
            local title = bag and "Backpack contents" or "Main inventory supplies"
            row(title, field, nil, nil, false); y = y + ROW_H + CELL_GAP
            local entries = Panel.cargoRows(person, field)
            if #entries == 0 then
                row("No additional supplies", field, nil, nil, false); y = y + ROW_H + CELL_GAP
            else
                for _, entry in ipairs(entries) do
                    row(tostring(entry.count) .. " x " .. entry.label, field, entry, false, editable)
                    row("X", field, entry, true, editable)
                    y = y + ROW_H + CELL_GAP
                end
            end
            local wornBag = bag and Panel.effectiveSlot(person, Creator.slotById("backpack")) or nil
            local canAdd = not bag or (wornBag and wornBag.fullType ~= nil)
            row(canAdd and ("+ Add to " .. (bag and "backpack" or "main inventory"))
                or "Choose a backpack to add supplies", field, nil, nil, editable and canAdd)
            y = y + ROW_H + CELL_GAP * 2
        end
    end
    -- Rebase only the established static gear controls. Info rows follow the
    -- revised basePageHeights in refreshLoadoutInfo; pooled cargo rows stay first.
    local function shift(controls)
        for _, control in ipairs(controls or {}) do
            if control.knoxPage == "gear" then
                control.knoxGearY = control.knoxGearY or control.knoxBaseY
                control.knoxBaseY = control.knoxGearY + y
            end
        end
    end
    shift(self.cells); shift(self.choiceButtons); shift(self.fieldCombos)
    self.gearBaseHeight = self.gearBaseHeight or self.basePageHeights.gear
    self.basePageHeights.gear = self.gearBaseHeight + y
end

function Window:openCargo(person, destination)
    if not self:canEditCargo(person) then return end
    local field = destination == "backpack" and "bagCargo" or "cargo"
    if field == "bagCargo" then
        local bag = Panel.effectiveSlot(person, Creator.slotById("backpack"))
        if not bag or not bag.fullType then self:setNote("Choose a backpack before adding its supplies.") return end
    end
    local entries, seen = Creator.itemCatalogue(), {}
    for _, entry in ipairs(entries) do seen[entry.fullType] = true end
    for fullType, count in pairs(person[field] or {}) do
        if not seen[fullType] then
            entries[#entries + 1] = {fullType=fullType, label="Saved supply: " .. fullType .. " (" .. count .. ")"}
        end
    end
    self:openChooser(entries, field == "bagCargo" and "Search backpack supplies" or "Search main inventory supplies", function(fullType, entry)
        self:editCargoQuantity(person, field, fullType, entry.label)
    end)
end

-- The kind control is the model's descriptor list, not a second hand-written
-- catalogue: shipped police/military/doctors/fire_service groups are starting
-- templates, and solo is the absence of a group.
local function descriptorChoices()
    local values = {}
    for _, entry in ipairs(Creator.descriptorKinds()) do values[#values + 1] = entry.id end
    return values
end

local POLICY_CHOICES = {
    profile = descriptorChoices(),
    attitude = {"dynamic", "friendly", "neutral", "hostile", "random"},
    spawnContext = {"default", "household", "law_enforcement", "military", "medical", "any"},
    vehiclePolicy = {"default", "any", "police", "military"},
    settlementPolicy = {"default", "home", "mobile", "independent"},
}
local function policyLabel(value)
    return tostring(value or "default"):gsub("_", " ")
end

function Window:onGroupPolicy(button)
    local faction = self:selectedFaction()
    if faction == nil then self:setNote("Choose a group on the left.") return end
    local kind = button.knoxKind
    if kind == "copy" then self:onUsePreset(); return end
    if kind == "editDefault" or kind == "resetDefault" then
        if not Creator.isDefault(faction.id) or faction.id == "solo" or self.group.readOnly then return end
        local resetting = kind == "resetDefault"
        self:setNote(resetting and "Warning: reset replaces only this default's planned roster and policies."
            or "Warning: editing this default changes its future authored spawns. Copy it to keep a separate variant.")
        self:promptFor(resetting and "Reset default? Type RESET" or "Edit default? Type EDIT", function(text)
            if text ~= (resetting and "RESET" or "EDIT") then self:setNote("No default changed.") return end
            if resetting then
                Creator.resetDefault(self.group.defs, faction.id)
                for i = #self.roster, 1, -1 do
                    if Creator.personFactionId(self.roster[i], self.group) == faction.id then table.remove(self.roster,i) end
                end
            else
                -- Recheck names and capacity against the current roster when
                -- the warning is accepted; a preview is never a raw import.
                local planned
                if self.templateRoster then
                    planned = {}
                    for i, person in ipairs(self.roster) do planned[i] = person end
                    local ok, reason = Creator.populateFaction(planned, self.group,
                        faction.id, #self.templateRoster)
                    if not ok then self:setNote(reason) return end
                end
                local ok, reason = Creator.editDefault(self.group.defs, faction.id)
                if not ok then self:setNote(reason) return end
                if planned then
                    for i = #self.roster + 1, #planned do self.roster[i] = planned[i] end
                end
            end
            self.dirty = true; self:selectFaction(faction.id); self:refresh()
            self:setNote(resetting and "Default restored. Existing world survivors are unchanged. Save to keep this reset."
                or "Editing a default. Changes affect its future authored spawns. Save a copy to keep a separate variant.")
        end)
        return
    end
    if kind == "populate" then
        local policy = Creator.profileFor(faction.id, self.group.defs)
        local count = Creator.factionCounts(self.roster, self.group, self.group.defs)[faction.id] or 0
        local needed = math.max(0, policy.memberCount - count)
        if needed == 0 then self:setNote("This group already has its planned people.") return end
        local ok, total = Creator.populateFaction(self.roster, self.group, faction.id, needed)
        if not ok then self:setNote(total) return end
        self.dirty = true; self:refresh()
        self:setNote("Added " .. tostring(needed) .. " people. Existing people kept.")
        return
    end
    if faction.id == "solo" then
        self:setNote("Solo survivors have no group settings. Each one is independent.") return
    end
    if faction.user ~= true then
        self:setNote("Save a copy first; your version can change without replacing the default.") return
    end
    local function apply(value)
        local ok, reason = Creator.updateFaction(self.group.defs, faction.id, {[kind] = value})
        if not ok then self:setNote(reason) return end
        self.dirty = true; self:refresh()
    end
    if kind == "region" then
        local entries = {{fullType="",label="Any mapped region"}}
        local seen = {}
        pcall(function()
            for _, region in pairs(SpawnRegionMgr.getSpawnRegions() or {}) do
                local name = tostring(region.name or ""):match("^%s*([^,]+)") or ""
                name = name:gsub("%s+$", "")
                if name ~= "" and not seen[name] then
                    entries[#entries + 1] = {fullType=name,label=name}; seen[name] = true
                end
            end
        end)
        self:openChooser(entries, "Starting region - mapped places only", apply)
    elseif kind == "memberCount" then
        self:promptFor("Planned people (1-24)", function(text)
            local n = tonumber(text)
            if n == nil or n ~= math.floor(n) or n < 1 or n > 24 then
                self:setNote("Choose a whole number from 1 to 24.") return
            end
            apply(n)
        end, tostring(Creator.profileFor(faction.id, self.group.defs).memberCount))
    else
        local entries = {}
        for _, value in ipairs(POLICY_CHOICES[kind] or {}) do
            entries[#entries + 1] = {fullType = value, label = policyLabel(value)}
        end
        self:openChooser(entries, "Choose " .. policyLabel(kind), function(value) apply(value) end)
    end
end

function Window:onCycleSkill(button)
    if self.templateRoster or self.group.readOnly then return end
    local person = self:selected()
    if person == nil or button == nil then return end
    local choices = {{fullType="automatic",label="From occupation and traits"}}
    for level = 0, Creator.MAX_SKILL do
        choices[#choices + 1] = {fullType=tostring(level), label="Level " .. tostring(level)}
    end
    self:openChooser(choices, button.knoxLabel or button.knoxPerk, function(value)
        person.skills = person.skills or {}
        person.skills[button.knoxPerk] = tonumber(value)
        self.dirty = true
        self:refresh()
    end)
end

function Window:onTraits()
    if self.templateRoster or self.group.readOnly then return end
    local person = self:selected()
    if person == nil or CharacterTraitDefinition == nil then return end
    local entries = {
        {fullType="__automatic", label="Automatic traits (legacy generation)"},
        {fullType="__none", label="No optional traits"},
    }
    local definitions = CharacterTraitDefinition.getTraits()
    for index = 0, definitions:size() - 1 do
        local definition = definitions:get(index)
        if definition ~= nil and not definition:isFree() and definition:getCost() ~= 0 then
            local id = tostring(definition:getType())
            local selected = false
            for _, chosen in ipairs(person.traits or {}) do if chosen == id then selected = true end end
            entries[#entries + 1] = {fullType=id, label=(selected and "[x] " or "[ ] ")
                .. tostring(definition:getLabel()) .. " (" .. tostring(definition:getCost()) .. ")",
                texture=definition:getTexture(), tooltip=definition:getDescription()}
        end
    end
    table.sort(entries, function(a,b) return a.label < b.label end)
    self:openChooser(entries, "Choose traits", function(id)
        if id == "__automatic" or id == "__none" then
            person.traits = id == "__none" and {} or nil
            self.dirty = true
            self:refresh()
            return
        end
        local chosen, removed = {}, false
        for _, value in ipairs(person.traits or {}) do
            if value == id then removed = true else chosen[#chosen + 1] = value end
        end
        local result, reason = Capabilities.creatorTraitChoices(person.profession, chosen,
            not removed and id or nil)
        if result == nil then self:setNote("Trait cannot be chosen: " .. tostring(reason)); return end
        person.traits = result
        self.dirty = true
        self:refresh()
    end)
end

function Window:promptFor(caption, onAccept, hint)
    if self.prompt ~= nil then
        pcall(function() self.prompt:close() end)
        self.prompt = nil
    end
    local width = math.min(420, math.floor(WIDTH * 0.4))
    self.prompt = Prompt:new(math.floor((WIDTH - width) / 2),
        math.floor((HEIGHT - 150) / 2), width, 150, caption, onAccept)
    self:addChild(self.prompt)
    self.prompt:bringToTop()
    if hint ~= nil then
        pcall(function() self.prompt.entry:setText(tostring(hint)) end)
    end
end

-- A group is one instance: these people, this purpose, this home. The kind comes
-- first because a household, a robber gang and a looter crew are different
-- behaviours, and the player may found as many of each as they like.
function Window:onNewFaction()
    local entries = {}
    -- The four descriptors come first, because they are the behaviours the player
    -- is choosing between. The shipped professions follow, named as complete
    -- starting templates, so a template never reads as a fifth kind of group.
    local descriptors = {}
    for _, kind in ipairs(Creator.descriptorKinds()) do
        descriptors[kind.id] = true
        entries[#entries + 1] = { fullType = kind.id,
            label = tostring(kind.label) .. " - " .. tostring(kind.note or "") }
    end
    -- Owner direction 2026-11-10: the chooser offers the behaviours and a blank
    -- group, not the shipped catalogue. Every kind and every template is still
    -- resolvable by id for a save that already stored one; it is simply not a
    -- row the player has to scroll past. This is the third time the presets were
    -- reported as still on screen, because earlier passes hid the roster ids
    -- while leaving the kinds and template rows in this list.
    -- Behaviours stay: police, military and fire are kinds the owner asked for
    -- (recruitment, gear, clearing infected), not town rosters. What is gone is
    -- the shipped catalogue of starting *rosters* - town-named police/medical/
    -- fire details and the solo presets - which is what read as "all those
    -- defaults". Every one of those ids still resolves for an old save; it is
    -- simply not a row in this chooser any more.
    for _, kind in ipairs(Creator.groupKinds()) do
        if not descriptors[kind.id] then
            entries[#entries + 1] = { fullType = kind.id,
                label = tostring(kind.label) .. " - " .. tostring(kind.note or "") }
        end
    end
    self:openChooser(entries, "Create a person or group", function(kindId)
        local template = Creator.startingTemplate(kindId)
        local kind = template or Creator.factionIndexIn(nil, kindId)
        if kind == nil then return end
        if template and template.profile == "solo" then
            self:promptFor("Survivor's first and last name", function(text)
                local ok, reason = Creator.addSoloTemplate(self.roster, text, template.id)
                if not ok then self:setNote(reason); return end
                self:selectFaction("solo"); self.selectedIndex = #self.roster
                self.dirty = true; self:refresh()
                self:setNote(template.note .. ". Save keeps this independent survivor.")
            end)
            return
        end
        self:promptFor("Name this " .. string.lower(kind.label), function(text)
            local ok, entry
            if template then ok, entry = Creator.addTemplateFaction(self.group.defs, text, kind.id)
            else ok, entry = Creator.addFaction(self.group.defs, text, kind.id) end
            if not ok then self:setNote(entry) return end
            local policy = Creator.profileFor(entry.id, self.group.defs)
            Creator.populateFaction(self.roster, self.group, entry.id, policy.memberCount)
            self.templateRoster = nil
            self:selectFaction(entry.id)
            self.dirty = true
            self:refresh()
            self:setNote(entry.label .. " is a " .. string.lower(kind.label)
                .. " group. Save keeps it.")
        end, kind.label)
    end)
end

function Window:onRenameFaction()
    local faction = self:selectedFaction()
    if faction == nil then self:setNote("Pick a faction first.") return end
    self:promptFor("Rename faction", function(text)
        local ok, result = Creator.renameFaction(self.group.defs, faction.id, text)
        if not ok then self:setNote(result) return end
        self.dirty = true
        self:refresh()
        self:setNote("Renamed to '" .. result.label .. "'.")
    end, faction.label)
end

function Window:onDeleteFaction()
    local faction = self:selectedFaction()
    if faction == nil then self:setNote("Pick a faction first.") return end
    local ok, result = Creator.deleteFaction(self.group.defs, faction.id, self.roster,
        self.group)
    if not ok then self:setNote(result) return end
    self:selectFaction(Creator.defaultFactionId())
    self.dirty = true
    self:refresh()
    self:setNote("Faction deleted.")
end

function Window:onAddPerson()
    if self.templateRoster then self:onUsePreset(); return end
    -- One explicit target: the selected row must be an owned group or Solo.
    -- The companions filter and a shipped preview are never add targets, so a
    -- new person can no longer land in a hidden fallback group.
    local okTarget, target = Creator.resolveAddTarget(self.selectedFactionId, self.group)
    if not okTarget then self:setNote(target); return end
    local factionId = target
    local faction = Creator.factionIndexIn(self.group.defs, factionId)
    local where = faction ~= nil and faction.label or "Solo survivors"
    self:promptFor("New person's name in " .. where, function(text)
        local draft = Creator.draftForFaction(factionId, self.group.defs)
        draft.name = text
        draft.faction = factionId
        local ok, person = Creator.add(self.roster, draft)
        if not ok then self:setNote(person) return end
        self.selectedIndex = #self.roster
        self.selectedFactionId = factionId
        self.dirty = true
        self:refresh()
        self:setNote(tostring(person.name) .. " joined " .. where .. ". Save keeps them there.")
    end)
end

-- The only writer. Save and closing both come through here, so a hand-built
-- faction is not lost by closing the window.
function Window:commit()
    if self.groupEntry ~= nil then
        pcall(function() self.group.name = tostring(self.groupEntry:getText() or "") end)
    end
    if self.group.readOnly and not self.group.needsRecovery then
        return false, "This file uses a newer format. Its saved data was not changed."
    end
    local ok, result = Creator.save(self.roster, self.group, self.group.needsRecovery == true)
    self.dirty = not ok
    if ok then
        self:setNote("Saved " .. #self.roster .. " people and "
            .. #self.group.defs .. " own groups.")
    end
    return ok, result
end

local function saveFailureMessage(reason)
    local messages = {
        backup_failed = "Could not secure a verified backup. The saved file was not overwritten.",
        write_failed = "Could not write the file. Check the recovery copy if one exists.",
        verification_failed = "Could not verify the saved file. Check the recovery copy if one exists.",
        read_failed = "Could not read the saved file. It was not overwritten.",
        invalid_file = "The saved file is unreadable. It was not overwritten.",
        unsupported_file = "The saved file was made by a newer version. It was not overwritten.",
    }
    return messages[reason] or tostring(reason)
end

function Window:onSave()
    local ok, result = self:commit()
    if not ok then self:setNote(saveFailureMessage(result) .. " Your edits remain open.") end
end

function Window:closePicker()
    local picker = self.picker
    self.picker = nil
    if picker ~= nil then pcall(function() picker:close() end) end
end

function Window:onKeyDown(key)
    if key == Keyboard.KEY_ESCAPE and self.colourPicker then self:closeColourPicker(); return true end
    if key == Keyboard.KEY_ESCAPE then
        -- Escape backs out one layer at a time: the item list, then a prompt,
        -- and only then the editor itself.
        if self.picker ~= nil then
            self:closePicker()
            return true
        end
        if self.prompt ~= nil then
            local prompt = self.prompt
            self.prompt = nil
            pcall(function() prompt:close() end)
            return true
        end
        self:onClose()
        return true
    end
end

-- One owner for putting back the main-menu column the editor hid. Closing used to
-- leave it hidden, which is why the screen went blank.
function Panel.restoreMainMenu()
    local panel = Panel.hiddenMenu
    Panel.hiddenMenu = nil
    if panel ~= nil then pcall(function() panel:setVisible(true) end) end
end

function Window:finishClose()
    self.detailPage, self.picker, self.prompt = nil, nil, nil
    self:setVisible(false)
    self:removeFromUIManager()
    if Panel.window == self then Panel.window = nil end
    Panel.restoreMainMenu()
    return true
end

function Window:offerDiscard(message)
    self:setNote(message .. " Type DISCARD to close without saving.")
    self:promptFor("Discard changes and close? Type DISCARD", function(text)
        if text == "DISCARD" then self.dirty = false; self:finishClose()
        else self:setNote("Changes remain open.") end
    end)
end

function Window:onClose()
    self:closeColourPicker()
    -- Drop the overlays first: a failed save must show its note, not hide behind
    -- a list that still covers the window.
    self:closePicker()
    if self.prompt ~= nil then
        local prompt = self.prompt
        self.prompt = nil
        pcall(function() prompt:close() end)
    end
    if self.group.needsRecovery and self.dirty then
        self:offerDiscard("Review the recovered people and press Save to keep your edits.")
        return false
    end
    if self.dirty then
        local ok, reason = self:commit()
        if not ok then self:offerDiscard(saveFailureMessage(reason)); return false end
    end
    return self:finishClose()
end

-- The native close control is `ISCollapsableWindow:close()`, which only hides the
-- window (install: ISCollapsableWindow.lua:55, :134). It never committed, never
-- removed the window from the UI manager and never restored the menu it hid, so
-- the X button left the main menu blank. Every close path lands here instead.
function Window:close()
    return self:onClose()
end

-- A private descriptor belongs only to this preview. Never borrow or mutate
-- MainScreen's player descriptor or create a world character for a thumbnail.
function Panel.previewSignature(person)
    if type(person) ~= "table" then return "" end
    return table.concat({ tostring(person.name), tostring(person.look), person.female and "1" or "0",
        tostring(person.hair), tostring(person.beard), tostring(person.hairColour), tostring(person.skin),
        tostring(person.weapon), tostring(person.weaponId),
        Creator.encodeSlots(person.slots) }, "|")
end

function Panel.effectiveSlot(person, slot)
    return slot and Creator.effectiveSlotChoice(person, slot.id) or nil
end

function Panel.createPreviewDescriptor(person, cache)
    if type(person) ~= "table" then return nil, "Choose a person to preview." end
    local ok, desc, unavailable = pcall(function()
        local descriptor = SurvivorFactory.CreateSurvivor()
        if descriptor == nil then return nil, "Character preview is unavailable." end
        descriptor:setFemale(person.female == true)
        local first, last = tostring(person.name or ""):match("^(.-)%s+([^%s]+)$")
        descriptor:setForename(first or tostring(person.name or ""))
        descriptor:setSurname(last or "")
        descriptor:getWornItems():clear()
        local missing = 0
        local items = Creator.lookItemsWithSlots(person.look, person.slots)
        local bag = Creator.bagFromSlots(person.slots)
        if bag ~= nil then items[#items + 1] = bag.fullType end
        for _, fullType in ipairs(items) do
            local item = cache and cache[fullType] or instanceItem(fullType)
            if cache and item then cache[fullType] = item end
            if item ~= nil then
                local location = item:IsClothing() and item:getBodyLocation() or item:canBeEquipped()
                if type(location) == "string" then
                    location = ItemBodyLocation.get(ResourceLocation.of(location))
                end
                if location ~= nil then descriptor:setWornItem(location, item) end
            else
                missing = missing + 1
            end
        end
        local visual = descriptor:getHumanVisual()
        visual:setSkinTextureIndex(Creator.skinIndex(person.skin) or 0)
        visual:setHairModel(type(person.hair) == "string" and person.hair ~= "" and person.hair or nil)
        visual:setBeardModel(not person.female and type(person.beard) == "string"
            and person.beard ~= "" and person.beard or nil)
        if ImmutableColor ~= nil then
            local rgb = Creator.colourOf(person.hairColour)
            local colour = ImmutableColor.new(rgb[1], rgb[2], rgb[3])
            visual:setHairColor(colour); visual:setBeardColor(colour)
            visual:setNaturalHairColor(colour); visual:setNaturalBeardColor(colour)
        end
        return descriptor, missing
    end)
    if not ok or desc == nil then return nil, "Character preview is unavailable." end
    return desc, unavailable
end

function Window:previewDesc()
    local person = self:selected()
    local signature = Panel.previewSignature(person)
    if self.previewPerson ~= person or self.previewSignature ~= signature then
        self.previewPerson = person
        self.previewCaches = self.previewCaches or {}
        local cache = person and self.previewCaches[person] or nil
        if person and not cache then cache = {}; self.previewCaches[person] = cache end
        self.previewDescriptor, self.previewMissing = Panel.createPreviewDescriptor(person, cache)
        self.previewSignature = signature
    end
    return self.previewDescriptor
end

-- One visible primary model even for a two-handed weapon. A saved spare remains
-- in inventory at spawn, so it must not appear as a second gun on this body.
function Panel.previewHandModels(person, cache)
    local choice = Creator.effectiveSlotChoice(person, "primary")
    local fullType = choice and choice.fullType
    if not fullType then return nil, nil, nil, false end
    local ok, model, weaponType = pcall(function()
        local item = cache and cache[fullType] or instanceItem(fullType)
        if not item then return nil, nil end
        if cache then cache[fullType] = item end
        local name = item:getStaticModel()
        local kind
        pcall(function()
            if WeaponType and instanceof and instanceof(item, "HandWeapon") then
                kind = WeaponType.getWeaponType(item):getType()
            end
        end)
        return name ~= "" and name or nil, kind
    end)
    return ok and model or nil, nil, ok and weaponType or nil, not ok or model == nil
end

function Window:refreshPreviewHands(person)
    local bridge = rawget(_G, "KnoxJavaBridge")
    if not bridge and KnoxRuntimeApi then
        pcall(function() bridge = KnoxRuntimeApi.getBridge() end)
    end
    local cache = self.previewCaches and self.previewCaches[person]
    local primary, secondary, weaponType, missing = Panel.previewHandModels(person, cache)
    self.previewHandsUnavailable = missing
    pcall(function()
        if weaponType then self.preview:setVariable("Weapon", weaponType)
        else self.preview:clearVariable("Weapon") end
    end)
    local ok, applied = pcall(function()
        return bridge and bridge:setCreatorPreviewHands(self.preview.javaObject, primary, secondary)
    end)
    if primary and (not ok or applied ~= true) then self.previewHandsUnavailable = true end
    if self.previewHint then
        self.previewHint:setName(self.previewHandsUnavailable and "Hand preview unavailable" or "Drag to turn")
    end
end

function Window:refreshPreview()
    local person = self:selected()
    if self.previewName then self.previewName:setName(UILayout.fitText(UIFont.Medium,
        person and person.name or "Choose a person", self.preview.width - PAD * 2)) end
    if self.preview == nil then return end
    local desc = self:previewDesc()
    if desc == nil or not self.previewSet then
        self.preview:setVisible(false)
        return
    end
    local ok = pcall(function()
        if self.previewAppliedDescriptor ~= desc then
            self.preview:setSurvivorDesc(desc)
            -- Set hand models before the new descriptor is rendered. Repeating
            -- this every refresh would rebuild work for unchanged selection.
            self:refreshPreviewHands(person)
            self.previewAppliedDescriptor = desc
        end
        self.preview:setVisible(true)
    end)
    if not ok then self.preview:setVisible(false) end
end

function Window:refreshRail()
    if self.railList == nil then return end
    self.railRows = {}
    local counts = Creator.factionCounts(self.roster, self.group, self.group.defs)
    local saved = {}
    -- The player's own groups, one row each, in the order they were made.
    for _, def in ipairs(self.group.defs or {}) do
        if type(def) == "table" and type(def.id) == "string" and def.id ~= "" then
            saved[def.id] = true
            if (Creator.isDefault(def.id) and not self.hideDefaults) or (not Creator.isDefault(def.id) and not self.hideCustom) then
            self.railRows[#self.railRows + 1] = { kind = "faction", id = def.id,
                label = def.label, user = true, count = counts[def.id] or 0,
                kindLabel = Creator.kindLabel(def.profile) }
            end
        end
    end
    -- A person still pointing at a shipped kind id (a file written before groups
    -- were instances) stays reachable instead of disappearing from the rail.
    for _, kind in ipairs(Creator.defaultEntries()) do
        if kind.group and not self.hideDefaults and not saved[kind.id] then
            self.railRows[#self.railRows + 1] = { kind = "faction", id = kind.id,
                label = kind.label, user = false, template = true,
                count = (counts[kind.id] or 0) > 0 and counts[kind.id]
                    or (Creator.profileFor(kind.id,self.group.defs) or {}).memberCount or 0,
                kindLabel = kind.label }
        end
    end
    -- Solo survivors are not a group and never become one: the row is a bucket
    -- for independent people, which is why it has no leader, home or kind choice.
    self.railRows[#self.railRows + 1] = { kind = "faction", id = "solo",
        label = "Solo survivors", user = false, solo = true,
        count = counts.solo or 0, kindLabel = "independent, no group" }
    -- The companions view sits above the create row: everyone the Companion and
    -- Spouse marks picked, whatever faction they belong to. Unticked people are
    -- not listed here; they are seeded into the world instead.
    local marked = Creator.markedCast(self.roster)
    self.railRows[#self.railRows + 1] = { kind = "cast", id = "starting",
        label = "Spouses & Companions", user = false, cast = true,
        count = #marked, kindLabel = "Companion and Spouse marks",
        caption = tostring(#marked) .. " marked to join; the rest are seeded" }
    self.railRows[#self.railRows + 1] = { kind = "new", label = "+ Create..." }
    self.railList:clear()
    for _, row in ipairs(self.railRows) do
        local suffix = row.kind == "faction"
            and (" (" .. tostring(row.count or 0) .. ")") or ""
        self.railList:addItem(tostring(row.label) .. suffix, row)
    end
end

local function boostText(model)
    local parts = {}
    for _, boost in ipairs(model and model.boosts or {}) do
        parts[#parts+1] = tostring(boost.name) .. " +" .. tostring(boost.level)
    end
    return #parts > 0 and ("Skill boosts: " .. table.concat(parts, ", ")) or "No skill boosts"
end

function Window:refreshLoadoutInfo(person)
    if not self.basePageHeights or not self.detail then return end
    self.infoRows = self.infoRows or {}
    for _, row in ipairs(self.infoRows) do row.knoxHidden=true; row:setVisible(false) end
    for page, height in pairs(self.basePageHeights) do self.pageHeights[page]=height end
    if not person then return end
    local count = 0
    local function add(page, text, texture)
        text = tostring(text or ""):gsub("<[^>]*>", " ")
        local lines = UILayout.wrapLines(text, DETAIL_W - ROW_H - 12,
            function(value) return getTextManager():MeasureStringX(UIFont.Small,value) end)
        for index, line in ipairs(lines) do
            count=count+1
            local row = self.infoRows[count]
            if not row then
                row = ISPanel:new(0,0,DETAIL_W,ROW_H)
                row:initialise()
                row.render=function(control)
                    local x=4
                    if control.texture then
                        control:drawTextureScaledAspect(control.texture,4,3,ROW_H-6,ROW_H-6,1,1,1,1)
                        x=ROW_H+4
                    end
                    local tone=creatorTheme.muted
                    control:drawText(control.text,x,4,tone[1],tone[2],tone[3],1,UIFont.Small)
                end
                self.detail:addScrollChild(row,0)
                self.infoRows[count]=row
            end
            row.knoxPage, row.knoxBaseY, row.knoxHidden = page,self.pageHeights[page],false
            row.text, row.texture, row.tooltip = line,index==1 and texture or nil,text
            self.pageHeights[page]=self.pageHeights[page]+ROW_H
        end
    end
    local model = LoadoutInfo.person(person)
    if model and model.occupation then
        local occupation=model.occupation
        add("person",occupation.name or "Occupation",occupation.texture)
        add("person",occupation.description or "")
        add("person",boostText(occupation))
    end
    add("skills",person.traits == nil and "Optional traits: automatic at spawn" or "Selected and occupation traits")
    for _, trait in ipairs(model and model.traits or {}) do
        add("skills",trait.name or "Unavailable trait",trait.texture)
        add("skills",trait.description or "")
        add("skills",boostText(trait))
    end
    add("gear","Main carrying limit: requires spawned body (Strength, traits and current condition).")
    if person.kit and person.kit ~= "none" then
        add("gear","Legacy preset supplies are retained. Use Clear preset supplies to build an entirely explicit loadout.")
    end
    add("gear","Hover an equipment slot for weight, capacity, coverage and item protection.")
    for _, field in ipairs({"cargo","bagCargo"}) do
        local weight, unknown = 0,false
        for id, amount in pairs(person[field] or {}) do
            local item=LoadoutInfo.item(id)
            if item and item.weight then weight=weight+item.weight*amount else unknown=true end
        end
        add("gear",(field=="cargo" and "Main supplies weight: " or "Backpack contents weight: ")
            .. string.format("%.2f",weight) .. (unknown and " + unavailable items" or ""))
    end
end

function Window:refreshDetail()
    local person = self:selected()
    local faction = self:selectedFaction()
    for _, cell in ipairs(self.cells or {}) do
        local choice = Panel.effectiveSlot(person, cell.slot)
        cell.title = cell.slot.label
        cell.detail = person == nil and "No person selected"
            or (choice ~= nil and choice.label
                or (cell.slot.kind == "clothing" and "From outfit" or "None"))
        local saved = person ~= nil and type(person.slots) == "table" and person.slots[cell.slot.id] or nil
        if choice == nil and type(saved) == "string" then cell.detail = "Unavailable item: " .. saved end
        cell.tooltip = choice and choice.fullType
            and LoadoutInfo.itemTooltip(choice.fullType,person) or cell.detail
        cell.texture = itemIcon(choice ~= nil and choice.fullType or nil)
        cell.enabled = person ~= nil and not self.templateRoster and not self.group.readOnly
        cell:setVisible(true)
    end
    local text = {}
    if person ~= nil then
        text.name = "Name: " .. tostring(person.name)
        text.remove = "Remove this person..."
        text.skin = "Skin tone..."
        text.random = "Randomize appearance"
        local cargoCount = 0
        for _, count in pairs(person.cargo or {}) do cargoCount = cargoCount + count end
        text.cargo = "Main inventory: " .. tostring(cargoCount) .. " supplies - edit..."
        local bagCount = 0
        for _, count in pairs(person.bagCargo or {}) do bagCount = bagCount + count end
        text.bagCargo = "Backpack: " .. tostring(bagCount) .. " supplies - edit..."
        text.clearPresets = "Clear preset supplies"
        text.look = "Outfit: " .. labelOf(Creator.LOOKS, person.look)
        text.profession = "Was: " .. labelOf(Creator.PROFESSIONS, person.profession,
            "Survivor")
        text.faction = "Faction: " .. Creator.factionLabel(
            Creator.personFactionId(person, self.group), self.group.defs)
        text.sex = "Sex: " .. (person.female and "Female" or "Male")
        text.hair = "Hair: " .. (type(person.hair) == "string" and person.hair ~= ""
            and person.hair or "None")
        text.beard = "Beard: " .. (type(person.beard) == "string" and person.beard ~= ""
            and person.beard or "None")
        text.colour = "Hair colour: " .. Creator.colourLabel(person.hairColour)
    else
        local label = faction ~= nil and faction.label or "No faction selected"
        text.name = "Choose a person from the cards."
        text.look = label .. " - choose a person"
        text.kit = "Pick a person to edit their loadout."
        text.pack = ""
        text.profession = ""
        text.faction = ""
        text.sex = ""
        text.hair = ""
        text.beard = ""
        text.colour = ""
    end
    for _, button in ipairs(self.choiceButtons or {}) do
        local label = text[button.knoxKind]
        if label == nil or label == "" then
            button:setVisible(false)
        else
            button:setVisible(true)
            button:setTitle(UILayout.fitText(UIFont.Small, tostring(label), DETAIL_W - 12))
            button.tooltip = tostring(label)
            button:setEnable(person ~= nil and not self.templateRoster and not self.group.readOnly)
            if person and (button.knoxKind == "skin" or button.knoxKind == "colour") then
                local rgb = button.knoxKind == "skin" and Creator.SKIN_COLOURS[(Creator.skinIndex(person.skin) or 0) + 1]
                    or Creator.colourOf(person.hairColour)
                button:setTitle("")
                button.backgroundColor = {r=rgb.r or rgb[1],g=rgb.g or rgb[2],b=rgb.b or rgb[3],a=1}
                button.backgroundColorMouseOver = button.backgroundColor
            end
        end
    end
    if self.traitButton then
        local count = person and person.traits and #person.traits or 0
        self.traitButton:setTitle(person and (person.traits == nil and "Traits: automatic..."
            or "Traits: " .. tostring(count) .. " selected...") or "Traits...")
        self.traitButton:setEnable(person ~= nil and not self.templateRoster and not self.group.readOnly)
    end
    for _, button in ipairs(self.skillButtons or {}) do
        local level = person and person.skills and person.skills[button.knoxPerk]
        local label = tostring(button.knoxPerk)
        pcall(function()
            local perk = Perks.FromString(button.knoxPerk)
            if perk ~= nil then label = tostring(PerkFactory.getPerkName(perk)) end
        end)
        button.knoxLabel = label
        button:setTitle(UILayout.fitText(UIFont.Small, label .. ": " .. (level ~= nil and tostring(level) or "Auto"), button.width - 12))
        button:setEnable(person ~= nil and not self.templateRoster and not self.group.readOnly)
        button:setVisible(true)
    end
    local policy = faction ~= nil and Creator.profileFor(faction.id, self.group.defs) or nil
    local labels = policy ~= nil and {
        region = "Region: " .. (policy.region and policy.region ~= "" and policy.region or "Any mapped region"),
        copy = "Save a personal copy...",
        editDefault = "Edit this default...",
        resetDefault = "Reset this default...",
        profile = "Kind: " .. policyLabel(policy.profile),
        attitude = "Starting attitude: " .. policyLabel(policy.attitude),
        memberCount = "Planned people: " .. tostring(policy.memberCount),
        spawnContext = "Starting place: " .. policyLabel(policy.spawnContext)
            .. (policy.region and policy.region ~= "" and (" / " .. policy.region) or ""),
        vehiclePolicy = "Vehicles: " .. policyLabel(policy.vehiclePolicy),
        settlementPolicy = "Home: " .. policyLabel(policy.settlementPolicy),
        populate = "Add planned people to this group",
    } or {}
    for _, button in ipairs(self.groupButtons or {}) do
        local label = labels[button.knoxKind] or "Choose a group on the left."
        button:setTitle(UILayout.fitText(UIFont.Small, label, DETAIL_W - 12))
        button.tooltip = label
        local solo = faction ~= nil and faction.id == "solo"
        local defaultControl = button.knoxKind == "editDefault" or button.knoxKind == "resetDefault"
        button.knoxHidden = (solo and button.knoxKind ~= "copy") or (defaultControl and not Creator.isDefault(faction and faction.id))
        if solo and button.knoxKind == "copy" then
            button:setTitle(UILayout.fitText(UIFont.Small, "Independent: no group or shared home", DETAIL_W - 12))
            button.tooltip = "Each solo survivor is independent. Select a group to edit shared policies."
        end
        button:setEnable(not self.group.readOnly and not solo and policy ~= nil
            and (not self.templateRoster or button.knoxKind == "copy" or defaultControl))
    end
    self:refreshFields(person)
    self:refreshCargoRows(person)
    self:refreshLoadoutInfo(person)
    self.detail.page = self.detailPage or "person"
    self.detail.contentHeight = self.pageHeights[self.detail.page] or self.detail.height
    if self.detail.page == "group" and faction and faction.id == "solo" then
        self.detail.contentHeight = self.groupButtons[1].knoxBaseY + ROW_H
    end
    self.detail.scrollY = clamp(self.detail.scrollY, 0, math.max(0, self.detail.contentHeight - self.detail.height))
    for _, button in ipairs(self.pageButtons or {}) do
        local active = button.knoxPage == self.detail.page
        button:setEnable(true)
        local border = active and creatorTheme.bone or creatorTheme.border
        button.borderColor = {r=border[1], g=border[2], b=border[3], a=1}
    end
    self.detail:applyScroll()
    if policy ~= nil and type(policy.capabilityLimit) == "string" then
        self:setNote(policy.capabilityLimit)
    end
end

function Window:refresh()
    if self.selectedFactionId == "starting" then
        self.view = Creator.markedCast(self.roster)
    else
        self.view = Creator.peopleByFaction(self.templateRoster or self.roster, self.group, self.selectedFactionId)
    end
    if self.selectedIndex ~= nil and (self.templateRoster or self.roster)[self.selectedIndex] == nil then
        self.selectedIndex = nil
    end
    local faction = self:selectedFaction()
    local label = faction ~= nil and faction.label or "All factions"
    local people = self.selectedFactionId == nil and #self.roster or #self.view
    if self.crumb ~= nil then
        pcall(function()
            local prefix = self.templateRoster and "PRESET / "
                or (faction and Creator.isDefault(faction.id) and "EDITED DEFAULT / " or "PERSONAL / ")
            local text = prefix .. label
                .. " / " .. tostring(people) .. " people"
            self.crumb:setName(UILayout.fitText(UIFont.Small, text, WIDTH - PAD * 2))
            self.crumb.tooltip = text
        end)
    end
    if self.groupEntry ~= nil then
        pcall(function()
            if (self.groupEntry:getText() or "") == "" and self.group.name ~= nil then
                self.groupEntry:setText(tostring(self.group.name))
            end
        end)
    end
    if self.cards ~= nil then self.cards.scroll = self.cards.scroll or 0 end
    self:refreshRail()
    self:refreshDetail()
    self:refreshPreview()
    if self.note ~= nil and (self.note.name == nil or self.note.name == "") then
        self:setNote(tostring(#self.roster) .. " people, "
            .. tostring(#Creator.allFactions(self.group.defs)) .. " factions")
    end
end

function Panel.hairOptions(female)
    return Creator.hairOptions(female)
end

function Panel.beardOptions(female)
    return Creator.beardOptions(female)
end

function Panel.open()
    if not Panel.ENABLED then return nil end
    if Panel.window ~= nil then
        Panel.window:setVisible(true)
        Panel.window:bringToTop()
        return Panel.window
    end
    local roster, group, skipped = Creator.load()
    local window = ISCollapsableWindowJoypad:new(0, 0, WIDTH, HEIGHT)
    setmetatable(window, Window)
    Window.__index = Window
    window:setTitle(Panel.WINDOW_TITLE)
    window.roster = roster
    window.group = group
    window.group.defs = group.defs or {}
    window.selectedIndex = nil
    window.selectedFactionId = nil
    window.hideDefaults = true
    window.hideCustom = false
    window.dirty = false
    window.view = {}
    window:initialise()
    local screenW = getPlayerScreenWidth(0)
    local screenH = getPlayerScreenHeight(0)
    window:setX(getPlayerScreenLeft(0) + math.max(0, math.floor((screenW - window.width) / 2)))
    window:setY(getPlayerScreenTop(0) + math.max(0, math.floor((screenH - window.height) / 2)))
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    -- Open on a group the player actually owns. Selecting the first shipped kind
    -- showed an empty preview as if it were their faction, which is the confusion
    -- this pass repairs.
    local owned = window.group.defs[1]
    window:selectFaction(owned ~= nil and owned.id or nil)
    window:refresh()
    if group.needsRecovery then
        window:setNote("Recovered the previous file. Review it and press Save to keep this recovery.")
    elseif group.readOnly then
        window:setNote("This file uses a newer format. Close without changing it.")
    elseif (skipped or 0) > 0 then
        window:setNote(tostring(skipped) .. " saved entr"
            .. (skipped == 1 and "y" or "ies") .. " could not be read.")
    end
    print("[KnoxSurvivors][Creator] opened " .. tostring(window.width) .. "x"
        .. tostring(window.height) .. " at " .. tostring(window:getX()) .. ","
        .. tostring(window:getY()))
    Panel.window = window
    local main = MainScreen and MainScreen.instance
    if main and main.bottomPanel then
        Panel.hiddenMenu = main.bottomPanel
        main.bottomPanel:setVisible(false)
    end
    return window
end

-- Main-menu entry: one labelled button, drawn only on the menu itself.
Panel.BUTTON_LABEL = Creator.MENU_BUTTON_LABEL

local SUB_SCREENS = { "soloScreen", "loadScreen", "sandOptions", "worldSelect",
    "mapSpawnSelect", "charCreationMain", "charCreationProfession",
    "modSelect", "mainOptions", "multiplayer", "onlineCoopScreen",
    "creditsScreen", "lastStandPlayerSelect", "serverSettingsScreen",
    "workshopSubmit", "serverWorkshopItem", "inviteFriends", "termsOfServiceDialog" }

local function panelShown(panel)
    if type(panel) ~= "table" then return false end
    for _, method in ipairs({ "isReallyVisible", "isVisible" }) do
        if type(panel[method]) == "function" then
            local ok, shown = pcall(function() return panel[method](panel) end)
            if ok then return shown == true end
        end
    end
    return false
end

function Panel.mainMenuFacts()
    local screen = rawget(_G, "MainScreen")
    local instance = type(screen) == "table" and screen.instance or nil
    local facts = { mainScreen = false, subScreen = false,
        inGame = getPlayer ~= nil and getPlayer() ~= nil }
    if type(instance) == "table" then
        facts.mainScreen = true
        for _, key in ipairs(SUB_SCREENS) do
            if panelShown(instance[key]) then facts.subScreen = true; break end
        end
    end
    return facts
end

function Panel.mainMenuVisible()
    return Creator.menuButtonVisible(Panel.mainMenuFacts())
end

local function syncButtonVisibility()
    local show = Panel.mainMenuVisible() and not panelShown(Panel.window)
    if Panel.menuButton ~= nil then
        pcall(function()
            if Panel.menuButton:isVisible() ~= show then
                Panel.menuButton:setVisible(show)
            end
        end)
    end
end

-- Native menu labels live under MainScreen.bottomPanel, alongside Options/Mods.
-- Use the installed MainScreen hover transition; no floating UI-manager button.
function Panel.installMenuButton()
    if not Panel.ENABLED then return nil end
    local main = MainScreen and MainScreen.instance
    if not main or main.inGame or not main.bottomPanel or not main.modsOption then return nil end
    if main.knoxCreatorOption then Panel.menuButton = main.knoxCreatorOption; return Panel.menuButton end
    local anchor = main.modsOption
    local height, y = anchor:getHeight(), anchor:getY()
    for _, child in pairs(main.bottomPanel:getChildren()) do
        if child.Type == "ISLabel" and child:getY() >= y then child:setY(child:getY() + height) end
    end
    local label = ISLabel:new(anchor:getX(), y, height, "KNOX CREATOR", 1, 1, 1, 1, UIFont.Large, true)
    label:initialise()
    label.internal = "KNOX_CREATOR"
    label.fade = UITransition.new()
    label.fade:setFadeIn(false)
    label.prerender = MainScreen.prerenderBottomPanelLabel
    label.onMouseDown = function()
        getSoundManager():playUISound("UIActivateMainMenuItem")
        Panel.open()
        return true
    end
    label:setWidth(math.max(anchor:getWidth(), getTextManager():MeasureStringX(UIFont.Large, "KNOX CREATOR")))
    label:setVisible(anchor:isVisible())
    main.bottomPanel:addChild(label)
    main.bottomPanel:setHeight(main.bottomPanel:getHeight() + height)
    main.knoxCreatorOption, Panel.menuButton = label, label
    if not MainScreen.knoxCreatorInputHook then
        MainScreen.knoxCreatorInputHook = true
        local click, gain = MainScreen.onMenuItemMouseDownMainMenu, MainScreen.onGainJoypadFocus
        if click then
            MainScreen.onMenuItemMouseDownMainMenu = function(item, x, y)
                if item and item.internal == "KNOX_CREATOR" then return item:onMouseDown(x, y) end
                return click(item, x, y)
            end
        end
        if gain then
            MainScreen.onGainJoypadFocus = function(screen, joypad)
                gain(screen, joypad)
                local option, rows = screen.knoxCreatorOption, screen.joypadButtonsY
                if not option or not option:isVisible() or not rows then return end
                for _, row in ipairs(rows) do if row[1] == option then return end end
                local position = #rows + 1
                for index, row in ipairs(rows) do
                    if row[1] and row[1]:getY() > option:getY() then position = index; break end
                end
                table.insert(rows, position, {option})
                if (screen.joypadIndexY or 0) >= position then screen.joypadIndexY = screen.joypadIndexY + 1 end
            end
        end
    end
    return label
end

local menuVisibilityTicks = 0
local menuInstallTicks = 0

if Events ~= nil then
    local menuTick = Events.OnFETick or Events.OnTick
    if menuTick ~= nil then
        menuTick.Add(function()
            if not Panel.ENABLED then return end
            if Panel.menuButton == nil or (MainScreen and MainScreen.instance and MainScreen.instance.knoxCreatorOption ~= Panel.menuButton) then
                menuInstallTicks = menuInstallTicks + 1
                if menuInstallTicks < 30 then return end
                menuInstallTicks = 0
                local inGame = false
                pcall(function() inGame = getPlayer ~= nil and getPlayer() ~= nil end)
                if not inGame and type(rawget(_G, "MainScreen")) == "table" then
                    pcall(Panel.installMenuButton)
                end
                return
            end
            menuVisibilityTicks = menuVisibilityTicks + 1
            if menuVisibilityTicks < 10 then return end
            menuVisibilityTicks = 0
            syncButtonVisibility()
        end)
    end
    if Events.OnMainMenuEnter ~= nil then
        Events.OnMainMenuEnter.Add(function()
            local ok, err = pcall(Panel.installMenuButton)
            if not ok then
                print("[KnoxSurvivors][Creator] menu button failed: " .. tostring(err))
            end
        end)
    end
    if Events.OnGameStart ~= nil then
        Events.OnGameStart.Add(function()
            if Panel.window ~= nil then
                pcall(function() Panel.window:onClose() end)
            end
            if Panel.menuButton ~= nil then
                Panel.menuButton:setVisible(false)
                Panel.menuButton = nil
            end
            local ok, count, degraded, spawnReason = pcall(Creator.spawnPending)
            if not ok then
                print("[KnoxSurvivors][Creator] spawn failed: " .. tostring(count))
            elseif (count or 0) > 0 then
                print("[KnoxSurvivors][Creator] allocated " .. tostring(count)
                    .. " created survivor(s), " .. tostring(degraded or 0)
                    .. " without their saved choices")
            else
                -- A silent no-spawn used to be indistinguishable from an empty
                -- roster. The reason names the branch: file needs review, no
                -- site, group conflict, or a repeat start with nothing new.
                print("[KnoxSurvivors][Creator] allocated 0 created survivor(s): "
                    .. tostring(spawnReason))
            end
        end)
    end
end

return Panel
