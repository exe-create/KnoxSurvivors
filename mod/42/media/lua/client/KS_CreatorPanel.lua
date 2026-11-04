-- Knox Survivors - the faction creator.
--
-- One full-screen sheet: the factions and their people down the left, a card per
-- person in the middle, and the selected person's body, slots and choices on the
-- right. The roster model lives in KS_Creator; this file asks and shows. Nothing
-- is written until commit, and commit is the only writer.
--
-- Panel.ENABLED is the one switch, read by the two entry points and the menu tick.
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISUI3DModel"
local UILayout = require "KS_SurvivorUILayout"
local Creator = require "KS_Creator"

local Panel = rawget(_G, "KnoxCreatorPanel") or {}
_G.KnoxCreatorPanel = Panel
Creator.panel = Panel

-- The surface is switched off again: the roster model and its file stay live, so
-- people already created are still read and spawned, but nothing installs a menu
-- button and nothing opens the window. This one flag is the only switch; no other
-- file reads it.
Panel.ENABLED = false

Panel.WINDOW_TITLE = "Knox Survivors - Faction Creator"

-- Layout metrics, recomputed from the shared UI scale when the window is built.
local WIDTH, HEIGHT, PAD, ROW = 940, 566, 10, 26
local RAIL_W, DETAIL_W, TOOLBAR_H, FOOTER_H, CRUMB_H = 250, 360, 40, 24, 24
local CELL_H, CELL_GAP, ROW_H, SKILL_H = 54, 6, 24, 20
local INSET = 6

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
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
end
computeMetrics()

local function addButton(parent, x, y, width, height, label, target, callback)
    local button = ISButton:new(x, y, width, height, label, target, callback)
    button:initialise()
    if button.setVisible then button:setVisible(true) end
    pcall(UILayout.tintButton, button)
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
local iconCache = {}
local function itemIcon(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local cached = iconCache[fullType]
    if cached ~= nil then return cached == false and nil or cached end
    local texture = nil
    pcall(function()
        local item = InventoryItemFactory.CreateItem(fullType)
        if item ~= nil then texture = item:getTex() end
    end)
    iconCache[fullType] = texture or false
    return texture
end

local function accentFor(label)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.factionAccent ~= nil then
        local ok, accent = pcall(persistence.factionAccent, label)
        if ok and type(accent) == "table" then return accent end
    end
    return UILayout.theme.amber
end

-- Every item a card promises, from the tables the spawn path reads. Kit themes are
-- named, not itemised here: the starting-gear owner decides what a kit contains.
local function gearItems(person)
    local items = {}
    if type(person) ~= "table" then return items end
    for _, fullType in ipairs(Creator.lookItemsWithSlots(person.look, person.slots)) do
        items[#items + 1] = fullType
    end
    local bag = Creator.bagFromSlots(person.slots)
    if bag ~= nil then items[#items + 1] = bag.fullType end
    local primary, secondary = Creator.carriedFromSlots(person.slots)
    if primary ~= nil then items[#items + 1] = primary end
    if secondary ~= nil then items[#items + 1] = secondary end
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

function Picker:new(x, y, width, height, entries, onPick, caption)
    local picker = ISPanel:new(x, y, width, height)
    setmetatable(picker, self)
    self.__index = self
    picker.entries = entries or {}
    picker.onPick = onPick
    picker.caption = caption or "Search items"
    picker:initialise()
    local t = UILayout.theme
    picker.backgroundColor = { r = t.charcoal[1], g = t.charcoal[2], b = t.charcoal[3], a = 0.98 }
    picker.borderColor = { r = t.border[1], g = t.border[2], b = t.border[3], a = 0.95 }
    return picker
end

function Picker:createChildren()
    local pad = math.max(6, math.floor(PAD * 0.8))
    local fieldHeight = math.max(20, math.floor(ROW * 0.9))
    self.search = ISTextEntryBox:new("", pad, pad, self.width - pad * 2, fieldHeight)
    self.search:initialise()
    placeholder(self.search, self.caption)
    self.search.onTextChange = function() self:populate() end
    self:addChild(self.search)
    local listY = pad * 2 + fieldHeight
    self.list = ISScrollingListBox:new(pad, listY, self.width - pad * 2,
        self.height - listY - pad)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = math.max(24, math.floor(CELL_H * 0.62))
    self.list.font = UIFont.Small
    self.list.doDrawItem = Picker.drawRow
    self.list:setOnMouseDownFunction(self, Picker.onRow)
    self:addChild(self.list)
    self:populate()
end

function Picker:populate()
    if self.list == nil then return end
    self.list:clear()
    local query = ""
    pcall(function() query = string.lower(tostring(self.search:getText() or "")) end)
    for _, entry in ipairs(self.entries) do
        local label = string.lower(tostring(entry.label))
        local fullType = string.lower(tostring(entry.fullType))
        if query == "" or string.find(label, query, 1, true) ~= nil
            or string.find(fullType, query, 1, true) ~= nil then
            self.list:addItem(tostring(entry.label), entry)
        end
    end
end

function Picker:drawRow(y, item, alt)
    local t = UILayout.theme
    self:drawRect(0, y, self.width, self.itemheight, alt and 0.12 or 0.06,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    local entry = item.item
    local size = math.max(16, self.itemheight - 6)
    local texture = entry ~= nil and entry.fullType and itemIcon(entry.fullType) or nil
    if texture ~= nil then
        self:drawTextureScaled(texture, 6, y + 3, size, size, 1, 1, 1, 1)
    end
    self:drawText(tostring(item.text), size + 14, y + 4,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    return y + self.itemheight
end

function Picker:onRow(item)
    if item == nil or type(item.item) ~= "table" then return end
    local entry = item.item
    local parent = self.parent
    self:setVisible(false)
    pcall(function() self:removeFromUIManager() end)
    if parent ~= nil and parent.picker == self then parent.picker = nil end
    if self.onPick ~= nil then self.onPick(entry.fullType, entry) end
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
    local t = UILayout.theme
    self:drawRect(0, 0, self.width, self.height, 0.55,
        t.charcoal[1], t.charcoal[2], t.charcoal[3])
    self:setStencilRect(0, 0, self.width, self.height)
end

function Cards:drawCard(card, person)
    local t = UILayout.theme
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
    self:drawText(tostring(person.name or "?"), card.x + 8, card.y + 12,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Medium)
    self:drawText(label, card.x + 8, card.y + 34,
        t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
    local items = gearItems(person)
    local size, gap = 26, 4
    local y = card.y + 54
    for index = 1, math.min(#items, 6) do
        local texture = itemIcon(items[index])
        local x = card.x + 8 + (index - 1) * (size + gap)
        if texture ~= nil then
            self:drawTextureScaled(texture, x, y, size, size, 1, 1, 1, 1)
        else
            self:drawRect(x, y, size, size, 0.20, t.border[1], t.border[2], t.border[3])
        end
    end
    self:drawText("Kit: " .. labelOf(Creator.KITS, person.kit, "none"),
        card.x + 8, card.y + card.height - 46,
        t.label[1], t.label[2], t.label[3], 1, UIFont.Small)
    self:drawText("Pack: " .. labelOf(Creator.PACKS, person.pack, "none"),
        card.x + 8, card.y + card.height - 30,
        t.label[1], t.label[2], t.label[3], 1, UIFont.Small)
    self:drawText(labelOf(Creator.WEAPONS, person.weaponId, "No weapon"),
        card.x + 8, card.y + card.height - 14,
        t.dim[1], t.dim[2], t.dim[3], 1, UIFont.Small)
end

function Cards:render()
    local win = self.window
    if win == nil then
        self:clearStencilRect()
        return
    end
    local grid = Creator.cardGrid(#win.view, 0, 0, self.width, self.height, self.scroll)
    if #win.view == 0 then
        self:drawText(self.emptyText, 10, 10,
            UILayout.theme.muted[1], UILayout.theme.muted[2], UILayout.theme.muted[3],
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
            0.55, UILayout.theme.border[1], UILayout.theme.border[2],
            UILayout.theme.border[3])
    end
end

function Cards:clampScroll()
    local grid = Creator.cardGrid(#self.window.view, 0, 0, self.width, self.height, self.scroll)
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
    local grid = Creator.cardGrid(#self.window.view, 0, 0, self.width, self.height, self.scroll)
    for _, card in ipairs(grid.cards) do
        if x >= card.x and x <= card.x + card.width
            and y >= card.y and y <= card.y + card.height then
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
    for _, child in ipairs(self.children or {}) do
        if child.knoxBaseY ~= nil then
            local y = child.knoxBaseY - self.scrollY
            child:setY(y)
            child:setVisible(y + (child.height or 0) > 0 and y < self.height)
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
    local t = UILayout.theme
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
        self:drawTextureScaled(self.texture, pad, (self.height - size) / 2, size, size,
            1, 1, 1, 1)
        textX = pad + size + pad
    end
    self:drawText(self.title, textX, pad,
        t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    self:drawText(self.detail, textX, pad + math.floor((self.height - pad * 2) / 2),
        t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
end

function Cell:onMouseDown(x, y)
    if self.enabled and self.onStep ~= nil then self.onStep(self) end
    return true
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
    local t = UILayout.theme
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
    self.ok = addButton(self, PAD, self.height - ROW - PAD, width, ROW, "Create", self,
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
    if self.parent ~= nil and self.parent.prompt == self then self.parent.prompt = nil end
end

local Window = ISCollapsableWindowJoypad:derive("KnoxCreatorWindow")

function Window:createChildren()
    computeMetrics()
    ISCollapsableWindowJoypad.createChildren(self)
    self:setWidth(WIDTH)
    self:setHeight(HEIGHT)
    if self.pinButton ~= nil then self.pinButton:setVisible(false) end
    if self.collapseButton ~= nil then self.collapseButton:setVisible(false) end
    pcall(UILayout.tintWindow, self)

    local top = self:titleBarHeight() + PAD * 0.6
    local nameWidth = math.floor(WIDTH * 0.22)
    self.groupEntry = ISTextEntryBox:new("", PAD, top, nameWidth, TOOLBAR_H - 10)
    self.groupEntry:initialise()
    placeholder(self.groupEntry, "Group name")
    self:addChild(self.groupEntry)

    local buttonH = TOOLBAR_H - 10
    local labels = { "New faction", "Add person", "Rename", "Delete", "Save", "Close" }
    local callbacks = { Window.onNewFaction, Window.onAddPerson, Window.onRenameFaction,
        Window.onDeleteFaction, Window.onSave, Window.onClose }
    local x = PAD + nameWidth + PAD
    local width = math.floor((WIDTH - x - PAD) / #labels) - 4
    for index = 1, #labels do
        addButton(self, x, top, width, buttonH, labels[index], self, callbacks[index])
        x = x + width + 4
    end

    local bodyY = top + TOOLBAR_H
    local bodyH = HEIGHT - bodyY - FOOTER_H - PAD

    self.crumb = ISLabel:new(PAD, bodyY, CRUMB_H, "", UILayout.theme.bone[1],
        UILayout.theme.bone[2], UILayout.theme.bone[3], 1, UIFont.Small, true)
    self.crumb:initialise()
    self:addChild(self.crumb)

    self.railList = ISScrollingListBox:new(PAD, bodyY + CRUMB_H, RAIL_W, bodyH - CRUMB_H)
    self.railList:initialise()
    self.railList:instantiate()
    self.railList.itemheight = 24
    self.railList.font = UIFont.Small
    self.railList.drawBorder = true
    local win = self
    self.railList.doDrawItem = function(list, y, item, alt)
        return Window.drawRailRow(win, list, y, item, alt)
    end
    self.railList:setOnMouseDownFunction(self, function(target, item)
        if item ~= nil and item.item ~= nil then win:onRailRow(item.item) end
    end)
    self:addChild(self.railList)

    local detailX = WIDTH - PAD - DETAIL_W
    local cardsX = PAD + RAIL_W + PAD
    local cardsW = math.max(200, detailX - PAD - cardsX)
    self.cards = Cards:new(cardsX, bodyY + CRUMB_H, cardsW, bodyH - CRUMB_H, self)
    -- The two numbers the layout is checked against, kept so a verification
    -- harness can read the real geometry instead of re-deriving it.
    self.knoxDetailX = detailX
    self.knoxCardsRight = cardsX + cardsW
    self:addChild(self.cards)

    local previewH = clamp(math.floor(bodyH * 0.30), 150, 300)
    self.preview = ISUI3DModel:new(detailX, bodyY + CRUMB_H, DETAIL_W, previewH)
    self.preview.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    self:addChild(self.preview)
    self.previewSet = pcall(function()
        self.preview:setIsometric(false)
        self.preview:setDirection(IsoDirections.S)
        self.preview:setZoom(-3)
        self.preview:setState("idle")
        self.preview:setDoRandomExtAnimations(true)
    end)

    local detailY = bodyY + CRUMB_H + previewH + CELL_GAP
    self.detail = Detail:new(detailX, detailY, DETAIL_W,
        HEIGHT - detailY - FOOTER_H - PAD)
    self:addChild(self.detail)

    self.cells = {}
    local cellW = math.floor((DETAIL_W - CELL_GAP) / 2)
    for index, slot in ipairs(Creator.SLOTS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local cell = Cell:new(column * (cellW + CELL_GAP), row * (CELL_H + CELL_GAP),
            cellW, CELL_H, slot)
        cell.onStep = function(clicked) win:openPicker(clicked.slot) end
        self.detail:addScrollChild(cell, cell:getY())
        self.cells[#self.cells + 1] = cell
    end
    local afterCells = math.ceil(#Creator.SLOTS / 2) * (CELL_H + CELL_GAP) + CELL_GAP

    self.choiceButtons = {}
    local rows = {
        { kind = "look" }, { kind = "kit" }, { kind = "pack" },
        { kind = "profession" }, { kind = "faction" }, { kind = "sex" },
        { kind = "hair" }, { kind = "beard" }, { kind = "colour" },
    }
    for index, row in ipairs(rows) do
        local y = afterCells + (index - 1) * (ROW_H + 2)
        local button = addButton(self.detail, 0, y, DETAIL_W, ROW_H, "", self,
            Window.onCycleChoice)
        button.knoxKind = row.kind
        self.detail:addScrollChild(button, y)
        self.choiceButtons[#self.choiceButtons + 1] = button
    end
    local skillsY = afterCells + #rows * (ROW_H + 2) + CELL_GAP

    self.skillButtons = {}
    local skillW = math.floor((DETAIL_W - CELL_GAP) / 2)
    for index, perkId in ipairs(Creator.SKILLS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local y = skillsY + row * (SKILL_H + 2)
        local button = addButton(self.detail, column * (skillW + CELL_GAP), y, skillW,
            SKILL_H, perkId, self, Window.onCycleSkill)
        button.knoxPerk = perkId
        self.detail:addScrollChild(button, y)
        self.skillButtons[#self.skillButtons + 1] = button
    end
    self.detail.contentHeight = skillsY + math.ceil(#Creator.SKILLS / 2) * (SKILL_H + 2)

    self.note = ISLabel:new(PAD, HEIGHT - FOOTER_H, FOOTER_H, "", UILayout.theme.muted[1],
        UILayout.theme.muted[2], UILayout.theme.muted[3], 1, UIFont.Small, true)
    self.note:initialise()
    self:addChild(self.note)

    pcall(UILayout.trackWindow, self)
end

function Window:drawRailRow(list, y, item, alt)
    local t = UILayout.theme
    local row = item.item or {}
    local selected = self.railSelected == row
    if selected then
        self:drawRect(0, y, list.width, list.itemheight, 0.28,
            t.border[1], t.border[2], t.border[3])
    end
    if row.kind == "faction" then
        local accent = accentFor(tostring(row.label))
        self:drawRect(0, y, 3, list.itemheight, 0.95, accent[1], accent[2], accent[3])
        self:drawText(tostring(row.label), 10, y + 4,
            t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Medium)
        self:drawText(tostring(row.count or 0), list.width - 30, y + 6,
            t.muted[1], t.muted[2], t.muted[3], 1, UIFont.Small)
    elseif row.kind == "person" then
        self:drawText(tostring(row.label), 24, y + 4,
            selected and t.bone[1] or t.label[1],
            selected and t.bone[2] or t.label[2],
            selected and t.bone[3] or t.label[3], 1, UIFont.Small)
    elseif row.kind == "all" then
        self:drawText(tostring(row.label) .. " (" .. tostring(row.count or 0) .. ")",
            10, y + 4, t.bone[1], t.bone[2], t.bone[3], 1, UIFont.Small)
    else
        self:drawText(tostring(row.label), 10, y + 4,
            t.label[1], t.label[2], t.label[3], 1, UIFont.Small)
    end
    return y + list.itemheight
end
function Window:selected()
    if self.selectedIndex == nil then return nil end
    return self.roster[self.selectedIndex]
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
    if self.note ~= nil then pcall(function() self.note:setName(tostring(text or "")) end) end
end

function Window:selectCard(viewIndex)
    local entry = self.view[viewIndex]
    if entry == nil then return end
    self.selectedIndex = entry.index
    self.selectedFactionId = Creator.personFactionId(entry.person, self.group)
    self:refresh()
end

function Window:onRailRow(row)
    if row.kind == "all" then
        self.selectedFactionId = nil
    elseif row.kind == "faction" then
        self.selectedFactionId = row.id
    elseif row.kind == "person" then
        self.selectedIndex = row.index
        self.selectedFactionId = row.id
    elseif row.kind == "new" then
        self:onNewFaction()
        return
    end
    self.railSelected = row
    self:refresh()
end

function Window:openChooser(entries, caption, onPick)
    if self.picker ~= nil then
        pcall(function() self.picker:setVisible(false); self.picker:removeFromUIManager() end)
        self.picker = nil
    end
    local width = math.floor(WIDTH * 0.42)
    local height = math.min(HEIGHT - 120, math.floor(HEIGHT * 0.62))
    self.picker = Picker:new(math.floor((WIDTH - width) / 2), self:titleBarHeight() + PAD,
        width, height, entries, onPick, caption)
    self:addChild(self.picker)
    self.picker:bringToTop()
end

-- A slot lists exactly what that slot accepts: clothing for a clothing slot, a
-- container for the bag, a real weapon for either hand, and a way to clear it.
function Window:openPicker(slot)
    local person = self:selected()
    if slot == nil or person == nil then return end
    local entries = { { fullType = false,
        label = slot.kind == "clothing" and "From outfit" or "None" } }
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
        else
            person.slots[slot.id] = fullType
        end
        self.dirty = true
        self:refresh()
    end)
end

local function cycleId(list, current)
    local index = 1
    for position, entry in ipairs(list) do
        if entry.id == current then index = position end
    end
    return list[Creator.cycle(index, #list, 1)].id
end

function Window:onCycleChoice(button)
    local person = self:selected()
    if person == nil or button == nil then return end
    local kind = button.knoxKind
    if kind == "look" then
        person.look = cycleId(Creator.LOOKS, person.look)
    elseif kind == "kit" then
        person.kit = cycleId(Creator.KITS, person.kit)
    elseif kind == "pack" then
        person.pack = cycleId(Creator.PACKS, person.pack)
    elseif kind == "profession" then
        person.profession = cycleId(Creator.PROFESSIONS, person.profession)
    elseif kind == "faction" then
        local nextId = cycleId(Creator.allFactions(self.group.defs),
            Creator.personFactionId(person, self.group))
        person.faction = nextId
        self.selectedFactionId = nextId
    elseif kind == "sex" then
        person.female = not person.female
    elseif kind == "hair" then
        local options = Panel.hairOptions(person.female)
        local index = 1
        for position, value in ipairs(options) do
            if value == person.hair then index = position end
        end
        person.hair = options[(index % #options) + 1] or ""
    elseif kind == "beard" then
        local options = Panel.beardOptions(person.female)
        if #options == 0 then
            person.beard = ""
        else
            local index = 1
            for position, value in ipairs(options) do
                if value == person.beard then index = position end
            end
            person.beard = options[(index % #options) + 1] or ""
        end
    elseif kind == "colour" then
        person.hairColour = Creator.HAIR_COLOURS[Creator.cycle(
            Creator.colourIndexOf(person.hairColour), #Creator.HAIR_COLOURS, 1)].id
    end
    self.dirty = true
    self:refresh()
end

function Window:onCycleSkill(button)
    local person = self:selected()
    if person == nil or button == nil then return end
    person.skills = person.skills or {}
    Creator.cycleSkill(person.skills, button.knoxPerk)
    self.dirty = true
    self:refresh()
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

function Window:onNewFaction()
    self:promptFor("New faction name", function(text)
        local ok, entry = Creator.addFaction(self.group.defs, text)
        if not ok then self:setNote(entry) return end
        self.selectedFactionId = entry.id
        self.dirty = true
        self:refresh()
        self:setNote("Faction '" .. entry.label .. "' added. Save keeps it.")
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
    self.selectedFactionId = nil
    self.dirty = true
    self:refresh()
    self:setNote("Faction deleted.")
end

function Window:onAddPerson()
    local factionId = self.selectedFactionId or self.group.factionId
    self:promptFor("New person's name", function(text)
        local draft = Creator.draftForFaction(factionId, self.group.defs)
        draft.name = text
        local ok, person = Creator.add(self.roster, draft)
        if not ok then self:setNote(person) return end
        self.selectedIndex = #self.roster
        self.dirty = true
        self:refresh()
        self:setNote(tostring(person.name) .. " is on the list.")
    end)
end

-- The only writer. Save and closing both come through here, so a hand-built
-- faction is not lost by closing the window.
function Window:commit()
    if self.groupEntry ~= nil then
        pcall(function() self.group.name = tostring(self.groupEntry:getText() or "") end)
    end
    local ok, result = Creator.save(self.roster, self.group)
    self.dirty = not ok
    if ok then
        self:setNote("Saved " .. #self.roster .. " people and "
            .. #self.group.defs .. " own factions.")
    end
    return ok, result
end

function Window:onSave()
    local ok, result = self:commit()
    if not ok then self:setNote("Could not save: " .. tostring(result)) end
end

function Window:onKeyDown(key)
    if key == Keyboard.KEY_ESCAPE then
        self:onClose()
        return true
    end
end

function Window:onClose()
    if self.dirty then self:commit() end
    self:setVisible(false)
    self:removeFromUIManager()
    if Panel.window == self then Panel.window = nil end
end

-- The preview is the engine's own survivor descriptor, so hair, beard and colour
-- are applied to what the body will actually wear.
function Window:previewDesc()
    local screen = rawget(_G, "MainScreen")
    local instance = type(screen) == "table" and screen.instance or nil
    local desc = instance ~= nil and instance.desc or nil
    return type(desc) == "table" and desc or nil
end

function Window:refreshPreview()
    if self.preview == nil then return end
    local desc = self:previewDesc()
    local person = self:selected()
    if desc == nil or not self.previewSet or person == nil then
        pcall(function() self.preview:setVisible(false) end)
        return
    end
    local ok = pcall(function()
        self.preview:setVisible(true)
        local visual = desc:getHumanVisual()
        visual:setHairModel(type(person.hair) == "string" and person.hair ~= ""
            and person.hair or nil)
        visual:setBeardModel(type(person.beard) == "string" and person.beard ~= ""
            and person.beard or nil)
        if ImmutableColor ~= nil then
            local rgb = Creator.colourOf(person.hairColour)
            local colour = ImmutableColor.new(rgb[1], rgb[2], rgb[3])
            visual:setHairColor(colour)
            visual:setBeardColor(colour)
            visual:setNaturalHairColor(colour)
            visual:setNaturalBeardColor(colour)
        end
        self.preview:setSurvivorDesc(desc)
    end)
    if not ok then pcall(function() self.preview:setVisible(false) end) end
end

function Window:refreshRail()
    if self.railList == nil then return end
    self.railRows = Creator.railRows(self.roster, self.group, self.group.defs,
        self.selectedFactionId)
    self.railList:clear()
    for _, row in ipairs(self.railRows) do
        local suffix = row.kind == "faction"
            and (" (" .. tostring(row.count or 0) .. ")") or ""
        self.railList:addItem(tostring(row.label) .. suffix, row)
    end
end

function Window:refreshDetail()
    local person = self:selected()
    local faction = self:selectedFaction()
    for _, cell in ipairs(self.cells or {}) do
        local choice = person ~= nil and Creator.slotChoice(cell.slot.id, person.slots)
            or nil
        cell.title = cell.slot.label
        cell.detail = person == nil and "No person selected"
            or (choice ~= nil and choice.label
                or (cell.slot.kind == "clothing" and "From outfit" or "None"))
        cell.texture = itemIcon(choice ~= nil and choice.fullType or nil)
        cell.enabled = person ~= nil
        cell:setVisible(true)
    end
    local text = {}
    if person ~= nil then
        text.look = "Outfit: " .. labelOf(Creator.LOOKS, person.look)
        text.kit = "Kit: " .. labelOf(Creator.KITS, person.kit)
        text.pack = "Pack: " .. labelOf(Creator.PACKS, person.pack)
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
        text.look = label .. " - built-in default"
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
            button:setTitle(tostring(label))
            button:setEnable(person ~= nil)
        end
    end
    for _, button in ipairs(self.skillButtons or {}) do
        local level = person ~= nil
            and Creator.skillLevel(person.skills, button.knoxPerk) or 0
        button:setTitle(tostring(button.knoxPerk) .. ": " .. tostring(level))
        button:setEnable(person ~= nil)
        button:setVisible(true)
    end
    self.detail:applyScroll()
end

function Window:refresh()
    self.view = Creator.peopleByFaction(self.roster, self.group, self.selectedFactionId)
    if self.selectedIndex ~= nil and self.roster[self.selectedIndex] == nil then
        self.selectedIndex = nil
    end
    local faction = self:selectedFaction()
    local label = faction ~= nil and faction.label or "All factions"
    local people = self.selectedFactionId == nil and #self.roster or #self.view
    if self.crumb ~= nil then
        pcall(function()
            self.crumb:setName(label .. " / " .. tostring(people) .. " people / "
                .. tostring(#self.group.defs) .. " own factions")
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

Panel.hairOptions = Panel.hairOptions or function(female)
    local values = nil
    pcall(function()
        local list = getHairStylesInstance ~= nil and getHairStylesInstance() or nil
        if list ~= nil then
            values = {}
            for index = 0, list:size() - 1 do
                local style = list:get(index)
                local name = style ~= nil and tostring(style:getName()) or ""
                if name ~= "" then values[#values + 1] = name end
            end
        end
    end)
    return values or { "Bald" }
end

Panel.beardOptions = Panel.beardOptions or function(female)
    if female then return {} end
    local values = nil
    pcall(function()
        local list = getBeardStylesInstance ~= nil and getBeardStylesInstance() or nil
        if list ~= nil then
            values = {}
            for index = 0, list:size() - 1 do
                local style = list:get(index)
                local name = style ~= nil and tostring(style:getName()) or ""
                if name ~= "" then values[#values + 1] = name end
            end
        end
    end)
    return values or {}
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
    window:refresh()
    if (skipped or 0) > 0 then
        window:setNote(tostring(skipped) .. " saved entr"
            .. (skipped == 1 and "y" or "ies") .. " could not be read.")
    end
    print("[KnoxSurvivors][Creator] opened " .. tostring(window.width) .. "x"
        .. tostring(window.height) .. " at " .. tostring(window:getX()) .. ","
        .. tostring(window:getY()))
    Panel.window = window
    return window
end

-- Main-menu entry: one labelled button, drawn only on the menu itself.
Panel.BUTTON_LABEL = Creator.MENU_BUTTON_LABEL

local SUB_SCREENS = { "soloScreen", "loadScreen", "sandOptions", "worldSelect",
    "mapSpawnSelect", "charCreationMain", "charCreationProfession",
    "modSelect", "mainOptions", "multiplayer", "onlineCoopScreen",
    "creditsScreen", "lastStandPlayerSelect", "serverSettingsScreen",
    "workshopSubmit", "serverWorkshopItem", "inviteFriends", "termsOfService" }

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
    local show = Panel.mainMenuVisible()
    if Panel.menuButton ~= nil then
        pcall(function()
            if Panel.menuButton:isVisible() ~= show then
                Panel.menuButton:setVisible(show)
            end
        end)
    end
end

function Panel.buttonPosition(screenLeft, screenTop, screenWidth, screenHeight, width, height)
    return screenLeft + screenWidth - 28 - (width or 240),
        screenTop + math.max(0, (screenHeight - (height or 30)) / 2)
end

function Panel.installMenuButton()
    if not Panel.ENABLED then return nil end
    if Panel.menuButton ~= nil then
        pcall(function() Panel.menuButton:removeFromUIManager() end)
        Panel.menuButton = nil
    end
    local scale = UILayout.uiScale()
    local width = math.max(140, math.floor(240 * scale))
    local height = math.max(22, math.floor(30 * scale))
    local screenW = getPlayerScreenWidth(0)
    local screenH = getPlayerScreenHeight(0)
    local x, y = Panel.buttonPosition(getPlayerScreenLeft(0), getPlayerScreenTop(0),
        screenW, screenH, width, height)
    x = math.max(getPlayerScreenLeft(0) + 8, x)
    local button = ISButton:new(x, y, width, height, Panel.BUTTON_LABEL, Panel,
        function() return Panel.open() end)
    button:initialise()
    pcall(UILayout.tintButton, button)
    button:addToUIManager()
    button:setAlwaysOnTop(true)
    Panel.menuButton = button
    print("[KnoxSurvivors][Creator] menu button " .. tostring(x) .. "," .. tostring(y)
        .. " " .. tostring(width) .. "x" .. tostring(height))
    syncButtonVisibility()
    return button
end

local menuVisibilityTicks = 0
local menuInstallTicks = 0

if Events ~= nil then
    if Events.OnTick ~= nil then
        Events.OnTick.Add(function()
            if not Panel.ENABLED then return end
            if Panel.menuButton == nil then
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
                Panel.menuButton:removeFromUIManager()
                Panel.menuButton = nil
            end
            local ok, count, degraded = pcall(Creator.spawnPending)
            if not ok then
                print("[KnoxSurvivors][Creator] spawn failed: " .. tostring(count))
            elseif (count or 0) > 0 then
                print("[KnoxSurvivors][Creator] allocated " .. tostring(count)
                    .. " created survivor(s), " .. tostring(degraded or 0)
                    .. " without their saved choices")
            end
        end)
    end
end

return Panel
