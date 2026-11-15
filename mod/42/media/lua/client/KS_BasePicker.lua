require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
local UILayout = require "KS_SurvivorUILayout"

-- Compact "which base?" prompt. Used whenever a send-home flow has more
-- than one player base: single-base callers skip the prompt entirely and
-- go straight to the primary. The pick callback receives a base id, or
-- nil on cancel/close. One-shot: the window destroys itself either way.
local BasePicker = rawget(_G, "KnoxBasePicker") or {}
_G.KnoxBasePicker = BasePicker

local PADDING = 10
local WIDTH = 300

-- The list owns the only scrollbar; Cancel remains below it and inside the viewport.
local function pickerLayout(screenW, screenH, scale, fontH, titleH, count)
    local width = math.max(1, math.min(math.floor(WIDTH * scale), screenW - PADDING * 2))
    local rowHeight = math.max(24, fontH + 8)
    local contentWidth = math.max(1, width - PADDING * 2)
    local labelY = titleH + PADDING
    local listY = labelY + fontH + 6
    local desiredList = math.max(rowHeight, count * rowHeight + 2)
    local maxHeight = math.max(1, screenH - PADDING * 2)
    local listHeight = math.max(1, math.min(desiredList,
        maxHeight - listY - rowHeight - PADDING * 2 - 6))
    local cancelY = listY + listHeight + 6
    return { width = width, height = cancelY + rowHeight + PADDING,
        contentWidth = contentWidth, labelY = labelY, listY = listY,
        listHeight = listHeight, cancelY = cancelY, rowHeight = rowHeight, fontH = fontH }
end

local Window = ISCollapsableWindowJoypad:derive("KnoxBasePickerWindow")

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)
    local geometry = self.pickerGeometry
    local prompt = tostring(self.prompt or "Send to which base?")
    local label = ISLabel:new(PADDING, geometry.labelY, geometry.fontH,
        UILayout.fitText(UIFont.Small, prompt, geometry.contentWidth),
        UILayout.theme.bone[1], UILayout.theme.bone[2], UILayout.theme.bone[3], 1, UIFont.Small, true)
    label:initialise(); label.tooltip = prompt; self:addChild(label)
    local list = ISScrollingListBox:new(PADDING, geometry.listY, geometry.contentWidth, geometry.listHeight)
    list:initialise(); list:instantiate()
    list.itemheight = geometry.rowHeight
    list.font = UIFont.Small
    list.fontHgt = geometry.fontH
    list.itemPadY = math.max(0, math.floor((geometry.rowHeight - geometry.fontH) / 2))
    list.textColor = { r = UILayout.theme.bone[1], g = UILayout.theme.bone[2], b = UILayout.theme.bone[3], a = 1 }
    list.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2], b = UILayout.theme.border[3], a = 0.8 }
    list.selectionColor = { r = UILayout.theme.amber[1], g = UILayout.theme.amber[2], b = UILayout.theme.amber[3], a = 0.3 }
    list.target = self
    list.joypadParent = self
    list.onMouseDown = function(widget, x, y)
        if widget:isMouseOverScrollBar() then return end
        local row = widget:rowAt(x, y)
        if row >= 1 and widget.items[row] ~= nil then
            widget.selected = row
            Window.onPick(widget.target, widget.items[row].item)
        end
    end
    list.overrideAButtonFunction = function(target, entry) Window.onPick(target, entry) end
    for _, entry in ipairs(self.bases or {}) do
        local name = tostring(entry.name or "Unnamed base")
        if name == "" then name = "Unnamed base" end
        list:addItem(UILayout.fitText(UIFont.Small, name, math.max(1, geometry.contentWidth - 40)), entry, name)
    end
    self.baseList = list
    self:addChild(list)
    local cancel = ISButton:new(PADDING, geometry.cancelY, geometry.contentWidth, geometry.rowHeight,
        "Cancel", self, Window.onCancel)
    cancel:initialise(); UILayout.tintButton(cancel)
    self:addChild(cancel)
    UILayout.tintSheetWindow(self)
    UILayout.finishWindow(self, "Cancel and close")
end

function Window:finish(baseId)
    if self.knoxFinished then return end
    self.knoxFinished=true
    -- Keep the external callback separate from Window:onPick's method lookup.
    local callback = self.choiceCallback
    self.choiceCallback = nil
    self:setVisible(false)
    self:removeFromUIManager()
    if BasePicker.window == self then BasePicker.window = nil end
    if callback ~= nil then
        local ok, err = pcall(callback, baseId)
        if not ok and err ~= nil then
            print("[KnoxSurvivors][BasePicker] callback failed: " .. tostring(err))
        end
    end
end

function Window:onPick(entry)
    self:finish(entry ~= nil and entry.id or nil)
end

function Window:close()
    self:finish(nil)
end

function Window:onCancel()
    self:finish(nil)
end

function Window:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:finish(nil)
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Window:new(playerNum, prompt, bases, onPick, title)
    local count = #(bases or {})
    local player = playerNum or 0
    local screenW = getPlayerScreenWidth(player)
    local screenH = getPlayerScreenHeight(player)
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local window = ISCollapsableWindowJoypad:new(0, 0, 1, 1)
    local geometry = pickerLayout(screenW, screenH, UILayout.uiScale(), fontH,
        window:titleBarHeight(), count)
    window:setWidth(geometry.width)
    window:setHeight(geometry.height)
    window.pickerGeometry = geometry
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum or 0
    window.prompt = prompt
    window.bases = bases
    window.choiceCallback = onPick
    -- The same compact chooser serves the base flows and the mission dispatch
    -- steps; the title says which question is being asked.
    if title ~= nil and tostring(title) ~= "" then
        window:setTitle(tostring(title))
    else
        window:setTitle("Choose Base")
    end
    return window
end

-- Returns true when a prompt was needed (caller must wait for the
-- callback); false when there is nothing to choose (caller proceeds).
-- Exactly one base resolves immediately through the callback.
function BasePicker.choose(playerNum, prompt, bases, onPick, title)
    local list = {}
    for _, base in ipairs(bases or {}) do
        if type(base) == "table" and base.id ~= nil then
            list[#list + 1] = { id = base.id, name = base.name }
        end
    end
    if onPick == nil then return false end
    if #list <= 1 then
        local ok, err = pcall(onPick, #list == 1 and list[1].id or nil)
        if not ok and err ~= nil then
            print("[KnoxSurvivors][BasePicker] callback failed: " .. tostring(err))
        end
        return false
    end
    if BasePicker.window ~= nil then
        BasePicker.window:finish(nil)
    end
    local window = Window:new(playerNum, prompt, list, onPick, title)
    window:initialise()
    local sw = getPlayerScreenWidth(playerNum)
    local sh = getPlayerScreenHeight(playerNum)
    -- Centre on the real window width: `width` is a local of Window:new, so
    -- reading it here used to be nil and threw before the chooser appeared.
    window:setX(getPlayerScreenLeft(playerNum) + math.max(0, (sw - window.width) / 2))
    window:setY(getPlayerScreenTop(playerNum) + math.max(0, (sh - window.height) / 2))
    window:setRenderThisPlayerOnly(playerNum)
    window:addToUIManager()
    window:bringToTop()
    BasePicker.window = window
    return true
end

return BasePicker
