require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "KS_BaseManager"
require "KS_BaseStorage"
require "KS_ActivityFeed"
local UILayout = require "KS_SurvivorUILayout"

local FilterUI = rawget(_G, "KnoxBaseStorageFilterUI") or {}
_G.KnoxBaseStorageFilterUI = FilterUI

local FilterWindow = ISCollapsableWindowJoypad:derive("KnoxBaseStorageFilterWindow")

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

-- Ten groups cover what a home actually sorts. Every remaining display
-- category is one button away, so the first list stays a decision instead of
-- a census.
local COMMON_FILTERS = {"food","water","medical","tools","weapons","ammunition",
    "building","farming","clothing","general"}
local COMMON_EXTRAS = { { key = "display:Literature", label = "Books & Maps" } }

-- MODE BUTTON AND WINDOW TITLE (pure)
-- The button names the view it opens, not the one it leaves: the exact-item
-- picker used to sit behind two presses of a button called "More filters".
function FilterUI.modeButtonTitle(mode)
    if mode == "groups" then return "Pick exact items" end
    if mode == "items" then return "All categories" end
    return "Common groups"
end

-- What the sheet currently keeps, counted on the title so a player can read the
-- result of a search-and-tick without counting rows themselves.
function FilterUI.selectionTitle(selected, room)
    local count = 0
    for _, enabled in pairs(type(selected) == "table" and selected or {}) do
        if enabled == true then count = count + 1 end
    end
    local base = "Container Item Filters"
    if type(room) == "string" and room ~= "" then base = base .. " - " .. room end
    if count == 0 then return base .. " \226\128\148 nothing kept" end
    return base .. " \226\128\148 " .. tostring(count)
        .. (count == 1 and " rule" or " rules")
end

-- A container's own name is the best hint the game gives us. A bookshelf gets
-- literature, a toolbox gets tools, and anything unremarkable becomes general
-- storage, which is what an ordinary cabinet or shelf is for.
local CONTAINER_SUGGESTIONS = {
    { match = {"book", "librar", "magazine"}, filters = { ["display:Literature"] = true } },
    { match = {"tool", "hardware", "workbench", "mechanic"}, filters = { tools = true } },
    { match = {"fridge", "freezer", "cooler", "icebox", "pantry", "kitchen"}, filters = { food = true } },
    { match = {"medic", "firstaid", "first aid", "drug", "pharmac", "clinic"}, filters = { medical = true } },
    { match = {"gun", "ammo", "weapon", "armory", "armoury"}, filters = { weapons = true, ammunition = true } },
    { match = {"wardrobe", "dresser", "locker", "closet", "laundry"}, filters = { clothing = true } },
    { match = {"fuel", "petrol", "generator"}, filters = { fuel = true } },
    { match = {"farm", "seed", "garden", "greenhouse"}, filters = { farming = true } },
}

local function editableFilterKey(key)
    return type(key) == "string" and KnoxBaseStorage.isValidFilterCategory(key)
end

local function editableFilters(policy)
    local filters, result = KnoxBaseStorage.filtersForPolicy(policy), {}
    for category, enabled in pairs(filters) do
        if enabled == true and editableFilterKey(category) then
            result[category] = true
        end
    end
    -- Preserve existing group, native and item selections when switching views.
    return result
end

local function nativeCategories()
    local categories, seen = {}, {}
    local ok, allItems = pcall(function()
        return getScriptManager():getAllItems()
    end)
    if not ok or allItems == nil then return categories end
    for index = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(index)
        local categoryOk, category = pcall(function()
            return scriptItem:getDisplayCategory()
        end)
        if categoryOk and type(category) == "string" and category ~= ""
            and KnoxBaseStorage.isValidFilterCategory("display:" .. category)
            and not seen[category] then
            seen[category] = true
            categories[#categories + 1] = category
        end
    end
    table.sort(categories, function(a, b) return string.lower(a) < string.lower(b) end)
    return categories
end

local function categoryLabel(category)
    if category == "perishable" then return "Perishable" end
    if category == "nonperishable" then return "Non-Perishable" end
    local key = "IGUI_ItemCat_" .. category
    local translated = getTextOrNull ~= nil and getTextOrNull(key) or nil
    return translated ~= nil and translated ~= "" and translated or category
end

local function containerHintText(object, containerIndex)
    local parts = {}
    local ok, name = pcall(function() return object:getName() end)
    if ok and type(name) == "string" and name ~= "" then parts[#parts + 1] = name end
    local index = tonumber(containerIndex) or 0
    local containerOk, container = pcall(function() return object:getContainerByIndex(index) end)
    if containerOk and container ~= nil then
        local typeOk, kind = pcall(function() return container:getType() end)
        if typeOk and type(kind) == "string" and kind ~= "" then parts[#parts + 1] = kind end
    end
    return string.lower(table.concat(parts, " "))
end

local function suggestedFilters(object, containerIndex)
    local text = object ~= nil and containerHintText(object, containerIndex) or ""
    for _, rule in ipairs(CONTAINER_SUGGESTIONS) do
        for _, word in ipairs(rule.match) do
            if string.find(text, word, 1, true) ~= nil then
                local copy = {}
                for key, value in pairs(rule.filters) do copy[key] = value end
                return copy
            end
        end
    end
    return { general = true }
end

local function itemFullType(scriptItem)
    local ok, value = pcall(function() return scriptItem:getFullName() end)
    if ok and type(value) == "string" and value ~= "" then return value end
    local moduleOk, moduleName = pcall(function() return scriptItem:getModuleName() end)
    local nameOk, name = pcall(function() return scriptItem:getName() end)
    if nameOk and type(name) == "string" and name ~= "" then
        if moduleOk and type(moduleName) == "string" and moduleName ~= "" then
            return moduleName .. "." .. name
        end
        return name
    end
    return nil
end

function FilterWindow:new(playerNum, baseId, object, containerIndex, policy)
    local screenW, screenH = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local screenX, screenY = getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum)
    local width = math.max(1, math.min(720, screenW - 24))
    local height = math.max(1, math.min(680, screenH - 24))
    local window = ISCollapsableWindowJoypad:new(
        screenX + (screenW - width) / 2, screenY + (screenH - height) / 2, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum, window.baseId, window.object = playerNum or 0, baseId, object
    window.containerIndex = tonumber(containerIndex) or 0
    window.policy = policy
    -- The window says which room the container is in when the policy knows.
    window.roomLabel = policy ~= nil and tostring(policy.roomLabel or "") or nil
    window.mode = "groups"
    if policy ~= nil then
        window.selectedFilters = editableFilters(policy)
    else
        -- A container nobody has sorted yet is pre-set from its own name, so
        -- saving an empty screen can never leave a shelf collecting junk.
        local suggested = suggestedFilters(object, window.containerIndex)
        window.selectedFilters = suggested
        window.isNew = true
        window.suggestedLabel = KnoxBaseStorage.label({
            storageFilterVersion = 1, storageFilters = suggested,
        })
    end
    window:setTitle("Container Item Filters")
    window:setResizable(true)
    UILayout.tintWindow(window)
    require("KS_SurvivorUILayout").bindInteractionWindow(window)
    return window
end

function FilterWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    UILayout.finishWindow(self, "Close filters")
    local pad = math.max(8, math.min(12, UILayout.scaled(8)))
    local titleHeight = self:titleBarHeight()
    local instruction = self.isNew
        and ("Suggested for this container: "
            .. tostring(self.suggestedLabel or "General Storage")
            .. ". Untick anything you do not want, then save.")
        or "Tick what this container keeps. The count is what it holds now."
    -- A label never wraps, so the instruction is measured into lines and the
    -- list starts below the last one. At a large interface scale the old single
    -- label ran past the list edge instead of reading as two calm lines.
    self.instructionText = instruction
    self.instructionLabels = {}
    local instructionH = math.max(16, UILayout.scaled(20))
    local instructionTop = titleHeight + math.max(4, UILayout.scaled(6))
    local instructionLines = UILayout.wrapLines(instruction, self.width - pad * 2,
        function(value) return getTextManager():MeasureStringX(UIFont.Small, value) end)

    -- Rows follow the interface font: a 26-pixel row clips the label at a
    -- large interface scale, so the list, the search box and the footer
    -- share one height.
    local rowH = math.max(22, UILayout.scaled(26))
    local buttonH = rowH
    local footer = buttonH + pad * 2 + 4
    self.listY = instructionTop + (#instructionLines * instructionH)
        + math.max(8, UILayout.scaled(10))
    local listY = self.listY

    self.searchBox = ISTextEntryBox:new("", pad, listY, self.width - pad * 2,
        math.max(20, UILayout.scaled(24)))
    self.searchBox:initialise()
    if self.searchBox.instantiate ~= nil then self.searchBox:instantiate() end
    self.searchBox:setClearButton(true)
    self.searchBox.tooltip = "Type part of an item name, or a type such as Base.BookCarpentry."
    self.searchBox:setVisible(false)
    self.searchBox.onTextChange = function() self:populateCategories() end
    self:addChild(self.searchBox)

    self.categoryList = ISScrollingListBox:new(pad, listY,
        self.width - pad * 2, self.height - listY - footer)
    self.categoryList:initialise()
    self.categoryList:instantiate()
    self.categoryList.itemheight = rowH
    self.categoryList.font = UIFont.Small
    self.categoryList.ownerWindow = self
    self.categoryList.doDrawItem = FilterWindow.drawCategory
    self.categoryList:setOnMouseDownFunction(self, FilterWindow.onToggleCategory)
    self.categoryList:setOverrideAButtonFunction(self, FilterWindow.onToggleCategory)
    self.categoryList.joypadParent = self
    self.categoryList.onJoypadDown = function(panel, button, joypadData)
        if button == Joypad.BButton then self:close()
        else ISScrollingListBox.onJoypadDown(panel, button, joypadData) end
    end
    self:addChild(self.categoryList)
    self.categoryList:setAnchorRight(true)
    self.categoryList:setAnchorBottom(true)

    self:populateCategories()

    local y = self.height - buttonH - pad
    self.modeButton = ISButton:new(pad,y,math.max(120, UILayout.scaled(170)),buttonH,FilterUI.modeButtonTitle(self.mode),self,FilterWindow.onCycleMode)
    self.modeButton:initialise(); UILayout.tintButton(self.modeButton)
    self.modeButton:setAnchorBottom(true)
    self.modeButton.tooltip = "Search the game's items and tick the exact types this container keeps. Unticked types are stored elsewhere."
    self:addChild(self.modeButton)
    self.saveButton = ISButton:new(self.width - 2 * pad - 184, y, 88, buttonH,
        "Save Filters", self, FilterWindow.onSave)
    self.saveButton:initialise(); UILayout.tintButton(self.saveButton)
    self:addChild(self.saveButton)
    self.cancelButton = ISButton:new(self.width - pad - 88, y, 88, buttonH,
        "Cancel", self, FilterWindow.close)
    self.cancelButton:initialise(); UILayout.tintButton(self.cancelButton)
    self:addChild(self.cancelButton)
    self.saveButton:setAnchorRight(true)
    self.saveButton:setAnchorBottom(true)
    self.cancelButton:setAnchorRight(true)
    self.cancelButton:setAnchorBottom(true)
    self:applyModeLayout()
    UILayout.trackWindow(self)
end

function FilterWindow:applyModeLayout()
    if self.categoryList == nil or self.searchBox == nil or self.modeButton == nil then return end
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local pad = math.max(8, math.min(12, UILayout.scaled(8)))
    local available = math.max(1, self.width - pad * 2)
    local lineH = fontH + 4
    local buttonH = math.max(24, fontH + 10)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local lines = UILayout.wrapLines(self.instructionText, available, measure)
    local labelTop = self:titleBarHeight() + math.max(4, UILayout.scaled(6))
    local controls = { self.modeButton, self.saveButton, self.cancelButton }
    local footer = UILayout.footerPlacements(controls, available,
        { spacing = 6, buttonHeight = buttonH, measure = measure })
    local footerTop = self.height - pad - footer.height
    local listGap = math.max(8, UILayout.scaled(10))
    local searchSpace = self.mode == "items" and buttonH + 4 or 0
    local rowHeight = math.max(1, tonumber(self.categoryList.itemheight) or buttonH)
    local lineBudget = math.max(0, math.floor((footerTop - 6 - rowHeight - searchSpace
        - labelTop - listGap) / lineH))
    local visibleLines = math.min(#lines, lineBudget)
    for index = 1, visibleLines do
        local line = lines[index]
        local label = self.instructionLabels[index]
        if label == nil then
            local muted = UILayout.theme.muted
            label = ISLabel:new(pad, 0, lineH, "", muted[1], muted[2], muted[3], 1, UIFont.Small, true)
            label:initialise(); self:addChild(label)
            self.instructionLabels[index] = label
        end
        if index == visibleLines and visibleLines < #lines then line = line .. "..." end
        label:setNameWithoutMoving(UILayout.fitText(UIFont.Small, line, available, measure))
        label:setX(pad); label:setY(labelTop + (index - 1) * lineH); label:setHeight(lineH)
        label.tooltip = self.instructionText
        label:setVisible(true)
    end
    for index = visibleLines + 1, #self.instructionLabels do self.instructionLabels[index]:setVisible(false) end
    self.categoryList.tooltip = self.instructionText
    local listY = labelTop + visibleLines * lineH + listGap
    for _, placement in ipairs(footer.placements) do
        local button = placement.control
        button:setX(pad + placement.x); button:setY(footerTop + placement.y)
        button:setWidth(placement.width); button:setHeight(placement.height)
    end
    self.searchBox:setX(pad); self.searchBox:setWidth(available)
    self.searchBox:setHeight(buttonH)
    self.searchBox:setVisible(self.mode == "items")
    local top = listY
    if self.mode == "items" then
        self.searchBox:setY(listY)
        top = self.searchBox:getBottom() + 4
    elseif self.knoxLayoutMode ~= self.mode and self.searchBox.setText ~= nil then
        pcall(function() self.searchBox:setText("") end)
    end
    self.categoryList:setX(pad); self.categoryList:setWidth(available)
    self.categoryList:setY(top); self.categoryList:setHeight(math.max(1, footerTop - top - 6))
    self.knoxLayoutWidth, self.knoxLayoutHeight, self.knoxLayoutMode = self.width, self.height, self.mode
end

function FilterWindow:prerender()
    if self.knoxLayoutWidth ~= self.width or self.knoxLayoutHeight ~= self.height then
        self:applyModeLayout()
    end
    ISCollapsableWindowJoypad.prerender(self)
end

local function matchesDisplayCategory(item, key)
    if type(key) ~= "string" or string.sub(key, 1, 8) ~= "display:" then return false end
    local wanted = string.sub(key, 9)
    local ok, value = pcall(function() return item:getDisplayCategory() end)
    return ok and tostring(value or "") == wanted
end

-- How many of each exact item type this container holds. The item picker
-- shows the same kept/held pair the group rows show, so one row answers both
-- "is this ticked" and "is any of it in here" without a second screen.
function FilterWindow:containerTypeCounts()
    local counts = {}
    local ok, container = pcall(function()
        return self.object ~= nil and self.object:getContainerByIndex(self.containerIndex) or nil
    end)
    if not ok or container == nil then return counts end
    local itemsOk, items = pcall(function() return container:getItems() end)
    if not itemsOk or items == nil then return counts end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local typeOk, fullType = false, nil
        if item ~= nil and item.getFullType ~= nil then
            typeOk, fullType = pcall(function() return item:getFullType() end)
        end
        if typeOk and type(fullType) == "string" and fullType ~= "" then
            counts[fullType] = (counts[fullType] or 0) + 1
        end
    end
    return counts
end

-- What the container holds right now, counted once per list build. Ten group
-- checks per item is only ever one container, and the numbers answer "how much
-- is in here" as plainly as they answer "is this row ticked".
function FilterWindow:containerCounts()
    -- A depot area has no container: its counts are the floor stock of the
    -- painted zone, collected by the storage owner when the window opened.
    if self.zoneId ~= nil then return self.zoneCounts or {} end
    local counts = {}
    for _, key in ipairs(COMMON_FILTERS) do
        -- General storage means "anything", so a count would just be the size
        -- of the container and tell the player nothing.
        if key ~= "general" then counts[key] = 0 end
    end
    for _, extra in ipairs(COMMON_EXTRAS) do counts[extra.key] = 0 end
    local ok, container = pcall(function()
        return self.object ~= nil and self.object:getContainerByIndex(self.containerIndex) or nil
    end)
    local items = nil
    if ok and container ~= nil then
        local itemsOk, list = pcall(function() return container:getItems() end)
        if itemsOk then items = list end
    end
    if items == nil then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil then
            for key, count in pairs(counts) do
                local matchOk, matched = pcall(KnoxBaseStorage.matchesCategory, item, key)
                if matchOk and matched == true then counts[key] = count + 1
                elseif matchesDisplayCategory(item, key) then counts[key] = count + 1 end
            end
        end
    end
    return counts
end

function FilterWindow:addRow(key, label, seen, counts)
    if seen[key] then return end
    seen[key] = true
    local text = label or KnoxBaseStorage.filterLabel(key)
    local total = type(counts) == "table" and counts[key] or nil
    if type(total) == "number" then
        local accepted = self.selectedFilters ~= nil
            and self.selectedFilters[key] == true and total or 0
        text = KnoxBaseStorage.countedLabel(text, accepted, total)
    end
    self.categoryList:addItem(text, { key = key })
end

function FilterWindow:addSelectedExtras(seen, counts)
    -- Whatever the player already chose stays on the first screen, so a rule
    -- can never become invisible just because its group is folded away.
    local extras = {}
    for key, enabled in pairs(self.selectedFilters or {}) do
        if enabled == true and not seen[key] then extras[#extras + 1] = key end
    end
    table.sort(extras)
    for _, key in ipairs(extras) do
        self:addRow(key, KnoxBaseStorage.filterLabel(key), seen, counts)
    end
end

function FilterWindow:itemEntries()
    if FilterUI.itemEntries ~= nil then return FilterUI.itemEntries end
    local entries = {}
    local ok, allItems = pcall(function() return getScriptManager():getAllItems() end)
    if ok and allItems ~= nil then
        for index = 0, allItems:size() - 1 do
            local scriptItem = allItems:get(index)
            local fullType = itemFullType(scriptItem)
            local key = fullType ~= nil and KnoxBaseStorage.itemFilterKey(fullType) or nil
            if key ~= nil then
                local nameOk, display = pcall(function() return scriptItem:getDisplayName() end)
                entries[#entries + 1] = {
                    fullType = fullType,
                    key = key,
                    label = nameOk and tostring(display or fullType) or fullType,
                }
            end
        end
    end
    table.sort(entries, function(a, b)
        local left, right = string.lower(a.label), string.lower(b.label)
        if left == right then return a.key < b.key end
        return left < right
    end)
    FilterUI.itemEntries = entries
    return entries
end

function FilterWindow:populateCategories()
    if self.categoryList == nil then return end
    self:setTitle(FilterUI.selectionTitle(self.selectedFilters, self.roomLabel))
    self.categoryList:clear()
    local seen = {}
    if self.mode == "items" then
        local query = ""
        if self.searchBox ~= nil and self.searchBox.getText ~= nil then
            local ok, text = pcall(function() return self.searchBox:getText() end)
            if ok and type(text) == "string" then query = string.lower(text) end
        end
        local shown = 0
        local held = self:containerTypeCounts()
        for _, entry in ipairs(self:itemEntries()) do
            local matches = query == "" or string.find(string.lower(entry.label), query, 1, true) ~= nil
                or string.find(string.lower(entry.key), query, 1, true) ~= nil
            if matches then
                local total = entry.fullType ~= nil and held[entry.fullType] or nil
                local counts = total ~= nil and { [entry.key] = total } or nil
                self:addRow(entry.key, entry.label, seen, counts)
                shown = shown + 1
                -- The catalogue is the whole game; a bounded list stays usable.
                if shown >= 500 then break end
            end
        end
        self:addSelectedExtras(seen)
        return
    end
    if self.mode == "categories" then
        self.nativeCategoryOptions = self.nativeCategoryOptions or nativeCategories()
        for _, category in ipairs(self.nativeCategoryOptions) do
            self:addRow("display:" .. category, categoryLabel(category), seen)
        end
        self:addSelectedExtras(seen)
        return
    end
    local counts = self:containerCounts()
    for _, key in ipairs(COMMON_FILTERS) do self:addRow(key, nil, seen, counts) end
    for _, extra in ipairs(COMMON_EXTRAS) do
        self:addRow(extra.key, extra.label, seen, counts)
    end
    self:addSelectedExtras(seen, counts)
end

function FilterWindow:setMode(mode)
    self.mode = mode or "groups"
    if self.modeButton ~= nil then
        self.modeButton:setTitle(FilterUI.modeButtonTitle(self.mode))
    end
    self:applyModeLayout()
    self:populateCategories()
end

function FilterWindow:onCycleMode()
    if self.mode == "groups" then self:setMode("categories")
    elseif self.mode == "categories" then self:setMode("items")
    else self:setMode("groups") end
end

-- The button cycles three views; the old name keeps the two-view toggle it
-- always had, so an existing caller still lands back on the common list.
function FilterWindow:onAdvanced()
    self:setMode(self.mode == "categories" and "groups" or "categories")
end

function FilterWindow:drawCategory(y, entry, alt)
    if (y + self:getYScroll() + entry.height < 0) or y + self:getYScroll() >= self.height then
        return y + entry.height
    end
    local data = entry.item or {}
    local window = self.ownerWindow
    local selected = window ~= nil and type(window.selectedFilters) == "table"
        and window.selectedFilters[data.key] == true
    local theme = UILayout.theme
    self:drawRect(8, y + 5, 16, 16, 0.92,
        theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
    self:drawRectBorder(8, y + 5, 16, 16, 0.9,
        theme.border[1], theme.border[2], theme.border[3])
    if selected then
        -- Use a plain Latin glyph and a filled state indicator. Some installed
        -- Build 42 fonts do not render the Unicode check mark consistently;
        -- the filled box keeps the saved/selected state visible regardless.
        self:drawRect(10, y + 7, 12, 12, 1,
            theme.green[1], theme.green[2], theme.green[3])
        self:drawText("X", 11, y + 3, theme.charcoal[1], theme.charcoal[2],
            theme.charcoal[3], 1, self.font)
    end
    self:drawText(entry.text or "", 34, y + 5,
        theme.bone[1], theme.bone[2], theme.bone[3], 1, self.font)
    -- One hairline per row, as the notebook lists draw: the filter list should
    -- read like the rest of the mod, not like a second checkbox table.
    self:drawRect(0, y + entry.height - 1, self:getWidth(), 1, 0.35,
        theme.border[1], theme.border[2], theme.border[3])
    return y + entry.height
end

function FilterWindow.onToggleCategory(target, entry)
    -- ISScrollingListBox callbacks receive the full row record:
    -- { text = ..., item = { key = ... } }. Accept the payload shape used by
    -- direct callers too, but always unwrap native rows before toggling.
    local data = type(entry) == "table" and (entry.item or entry) or nil
    local key = type(data) == "table" and data.key or nil
    if target == nil or not editableFilterKey(key) then return end
    target.selectedFilters[key] = not target.selectedFilters[key] or nil
    if target.categoryList ~= nil and type(target.categoryList.setDirty) == "function" then
        target.categoryList:setDirty()
    end
end

function FilterWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if JoypadState ~= nil and JoypadState.players[self.playerNum + 1] ~= nil then
        local focus = JoypadState.players[self.playerNum + 1].focus
        if focus == self or focus == self.categoryList or focus == self.saveButton
            or focus == self.cancelButton then
            setJoypadFocus(self.playerNum, self.previousJoypadFocus)
        end
    end
    FilterUI.window = nil
end

function FilterWindow:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then self:close()
    elseif button == Joypad.YButton then self:onSave()
    else ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData) end
end

function FilterWindow:onSave()
    if self.zoneId ~= nil then
        local zone, reason = KnoxBaseManager.setZoneFilters(self.baseId, self.zoneId,
            self.selectedFilters)
        if zone ~= nil then
            KnoxActivityFeed.event("Saved depot filters: "
                .. KnoxBaseStorage.label(KnoxBaseStorage.zoneFilters(zone)) .. ".")
        else
            KnoxActivityFeed.event("Could not save depot filters: " .. tostring(reason) .. ".")
        end
        self:close()
        return
    end
    local base = KnoxBaseManager.get(self.baseId)
    local square = self.object ~= nil and self.object.getSquare ~= nil
        and self.object:getSquare() or nil
    if base == nil or square == nil or not KnoxBaseManager.containsSquare(base, square) then
        KnoxActivityFeed.event("Could not save container filters: this container is no longer inside the selected base.")
        self:close()
        return
    end
    local reference = KnoxBaseManager.containerReference(self.object, self.containerIndex, self.baseId)
    if reference == nil then
        KnoxActivityFeed.event("Could not save container filters: the container is unavailable.")
        self:close()
        return
    end
    if not hasEntries(self.selectedFilters) then
        if base.storage ~= nil and base.storage[reference.key] ~= nil then
            KnoxBaseContextMenu.removeStorage(self.baseId, reference.key,
                self.object, self.containerIndex)
        else
            KnoxActivityFeed.event("Filters cleared. This real container remains available as fallback storage.")
        end
        self:close()
        return
    end
    local policy, reason = KnoxBaseManager.setStorageFilters(self.baseId, self.object,
        self.selectedFilters, self.containerIndex)
    if policy ~= nil then
        KnoxActivityFeed.event("Saved container filters: " .. KnoxBaseStorage.label(policy) .. ".")
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
    else
        KnoxActivityFeed.event("Could not save container filters: " .. tostring(reason) .. ".")
    end
    self:close()
end

function FilterUI.open(baseId, object, containerIndex, playerNum)
    if FilterUI.window ~= nil then FilterUI.window:close() end
    local base = KnoxBaseManager.get(baseId)
    local reference = base ~= nil and KnoxBaseManager.containerReference(
        object, containerIndex, baseId) or nil
    if base == nil or reference == nil or not KnoxBaseManager.containsSquare(base, object:getSquare()) then
        KnoxActivityFeed.event("Could not open container filters: select a container inside an owned base.")
        return nil
    end
    local policy = base.storage ~= nil and base.storage[reference.key] or nil
    playerNum = tonumber(playerNum) or 0
    local window = FilterWindow:new(playerNum, baseId, object, containerIndex, policy)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    if JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil then
        window.previousJoypadFocus = JoypadState.players[playerNum + 1].focus
        setJoypadFocus(playerNum, window.categoryList)
    end
    FilterUI.window = window
    return window
end

-- The same window, pointed at an area instead of a container. Nothing about
-- the filter vocabulary changes: a depot is a policy-shaped zone.
function FilterUI.openZone(baseId, zoneId, playerNum)
    if FilterUI.window ~= nil then FilterUI.window:close() end
    local base = KnoxBaseManager.get(baseId)
    local zone = base ~= nil and base.zones ~= nil and base.zones[zoneId] or nil
    if base == nil or zone == nil or KnoxBaseStorage.isDepotZone(zone) ~= true then
        KnoxActivityFeed.event("Could not open depot filters: that area is not a depot.")
        return nil
    end
    local policy = KnoxBaseStorage.zoneFilters(zone)
    playerNum = tonumber(playerNum) or 0
    local window = FilterWindow:new(playerNum, baseId, nil, 0, policy)
    window.zoneId = zoneId
    window.zoneCounts = KnoxBaseStorage.depotStock(base, zone).totals
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    window:setTitle("Depot Filters - "
        .. tostring(KnoxPersistence.zoneDisplayLabel(zone, "Drop Point")))
    if JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil then
        window.previousJoypadFocus = JoypadState.players[playerNum + 1].focus
        setJoypadFocus(playerNum, window.categoryList)
    end
    FilterUI.window = window
    return window
end

FilterUI.FilterWindow = FilterWindow
FilterUI.nativeCategories = nativeCategories
FilterUI.categoryLabel = categoryLabel
FilterUI.editableFilters = editableFilters
FilterUI.suggestedFilters = suggestedFilters
FilterUI.filterCategoryKeys = function()
    local result = {}
    for _,key in ipairs(COMMON_FILTERS) do result[#result+1]=key end
    for _,extra in ipairs(COMMON_EXTRAS) do result[#result+1]=extra.key end
    for _, category in ipairs(nativeCategories()) do
        result[#result + 1] = "display:" .. category
    end
    return result
end
return FilterUI
