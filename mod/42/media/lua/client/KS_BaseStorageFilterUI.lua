require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "KS_BaseManager"
require "KS_BaseStorage"
require "KS_ActivityFeed"

local FilterUI = rawget(_G, "KnoxBaseStorageFilterUI") or {}
_G.KnoxBaseStorageFilterUI = FilterUI

local FILTER_LABELS = {
    food = "Food & Drink", water = "Water", medical = "Medical",
    weapons = "Weapons", ammunition = "Ammunition", tools = "Tools",
    logs = "Logs & Lumber", building = "Materials", farming = "Farming",
    clothing = "Clothing", junk = "Junk", general = "General Storage (all items)",
}

local FilterWindow = ISCollapsableWindowJoypad:derive("KnoxBaseStorageFilterWindow")

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
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
    local key = "IGUI_ItemCat_" .. category
    local translated = getTextOrNull ~= nil and getTextOrNull(key) or nil
    return translated ~= nil and translated ~= "" and translated or category
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
    window.selectedFilters = KnoxBaseStorage.filtersForPolicy(policy)
    window:setTitle("Container Item Filters")
    window:setResizable(true)
    window.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.94 }
    window.borderColor = { r = 0.38, g = 0.38, b = 0.38, a = 0.95 }
    return window
end

function FilterWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local pad = 12
    local titleHeight = self:titleBarHeight()
    self.instructions = ISLabel:new(pad, titleHeight + 6, 20,
        "Choose vanilla item categories. Filtered containers are preferred; other base containers remain fallback storage.",
        0.9, 0.9, 0.9, 1, UIFont.Small, true)
    self.instructions:initialise()
    self:addChild(self.instructions)

    local buttonH = 26
    local footer = buttonH + pad * 2 + 4
    local listY = titleHeight + 32
    self.categoryList = ISScrollingListBox:new(pad, listY,
        self.width - pad * 2, self.height - listY - footer)
    self.categoryList:initialise()
    self.categoryList:instantiate()
    self.categoryList.itemheight = 26
    self.categoryList.font = UIFont.Small
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

    for _, key in ipairs({ "food", "water", "medical", "weapons", "ammunition",
            "tools", "logs", "building", "farming", "clothing", "junk", "general" }) do
        self.categoryList:addItem(FILTER_LABELS[key], { key = key })
    end
    for _, category in ipairs(nativeCategories()) do
        self.categoryList:addItem(categoryLabel(category), { key = "display:" .. category })
    end
    self.categoryList.doDrawItem = FilterWindow.drawCategory

    local y = self.height - buttonH - pad
    self.saveButton = ISButton:new(self.width - 2 * pad - 184, y, 88, buttonH,
        "Save Filters", self, FilterWindow.onSave)
    self.saveButton:initialise()
    self:addChild(self.saveButton)
    self.cancelButton = ISButton:new(self.width - pad - 88, y, 88, buttonH,
        "Cancel", self, FilterWindow.close)
    self.cancelButton:initialise()
    self:addChild(self.cancelButton)
    self.saveButton:setAnchorRight(true)
    self.saveButton:setAnchorBottom(true)
    self.cancelButton:setAnchorRight(true)
    self.cancelButton:setAnchorBottom(true)
end

function FilterWindow:drawCategory(y, entry, alt)
    if (y + self:getYScroll() + entry.height < 0) or y + self:getYScroll() >= self.height then
        return y + entry.height
    end
    local data = entry.item or {}
    local target = self.target
    local selected = target ~= nil and type(target.selectedFilters) == "table"
        and target.selectedFilters[data.key] == true
    self:drawRect(8, y + 5, 16, 16, 0.92, 0.05, 0.05, 0.05)
    self:drawRectBorder(8, y + 5, 16, 16, 0.9, 0.72, 0.72, 0.72)
    if selected then
        -- Use a plain Latin glyph and a filled state indicator. Some installed
        -- Build 42 fonts do not render the Unicode check mark consistently;
        -- the filled box keeps the saved/selected state visible regardless.
        self:drawRect(10, y + 7, 12, 12, 1, 0.34, 0.72, 0.34)
        self:drawText("X", 11, y + 3, 0.08, 0.12, 0.08, 1, self.font)
    end
    self:drawText(entry.text or "", 34, y + 5, 1, 1, 1, 1, self.font)
    return y + entry.height
end

function FilterWindow.onToggleCategory(target, entry)
    -- ISScrollingListBox callbacks receive the full row record:
    -- { text = ..., item = { key = ... } }. Accept the payload shape used by
    -- direct callers too, but always unwrap native rows before toggling.
    local data = type(entry) == "table" and (entry.item or entry) or nil
    local key = type(data) == "table" and data.key or nil
    if target == nil or key == nil then return end
    if key == "general" then
        target.selectedFilters = target.selectedFilters.general and {} or { general = true }
        return
    end
    target.selectedFilters.general = nil
    target.selectedFilters[key] = not target.selectedFilters[key] or nil
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

FilterUI.FilterWindow = FilterWindow
FilterUI.nativeCategories = nativeCategories
FilterUI.categoryLabel = categoryLabel
return FilterUI
