require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISLabel"
local UILayout = require "KS_SurvivorUILayout"

-- Compact "which base?" prompt. Used whenever a send-home flow has more
-- than one player base: single-base callers skip the prompt entirely and
-- go straight to the primary. The pick callback receives a base id, or
-- nil on cancel/close. One-shot: the window destroys itself either way.
local BasePicker = rawget(_G, "KnoxBasePicker") or {}
_G.KnoxBasePicker = BasePicker

local BUTTON_HGT = 24
local PADDING = 10
local WIDTH = 300
local Window = ISCollapsableWindowJoypad:derive("KnoxBasePickerWindow")

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)
    local y = self:titleBarHeight() + PADDING
    local label = ISLabel:new(PADDING, y, BUTTON_HGT, self.prompt or "Send to which base?",
        UILayout.theme.bone[1], UILayout.theme.bone[2], UILayout.theme.bone[3], 1, UIFont.Small, true)
    label:initialise()
    self:addChild(label)
    y = y + BUTTON_HGT + 6
    for _, entry in ipairs(self.bases or {}) do
        local btn = ISButton:new(PADDING, y, self.width - PADDING * 2, BUTTON_HGT,
            tostring(entry.name or entry.id), self, Window.onPick)
        btn:initialise(); UILayout.tintButton(btn)
        btn.knoxBaseId = entry.id
        self:addChild(btn)
        y = y + BUTTON_HGT + 4
    end
    local cancel = ISButton:new(PADDING, y, self.width - PADDING * 2, BUTTON_HGT,
        "Cancel", self, Window.onCancel)
    cancel:initialise(); UILayout.tintButton(cancel)
    self:addChild(cancel)
    UILayout.trackWindow(self)
end

function Window:finish(baseId)
    local callback = self.onPick
    self.onPick = nil
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

function Window:onPick(button)
    self:finish(button ~= nil and button.knoxBaseId or nil)
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
    local count = 0
    for _ in ipairs(bases or {}) do count = count + 1 end
    -- Font-relative like the other windows so base names never clip.
    local scale = UILayout.uiScale()
    local width = math.floor(WIDTH * scale)
    local screenW = UILayout.screenSize()
    if screenW ~= nil and screenW > 0 then
        width = math.min(width, screenW - 24)
    end
    local height = 60 + (count + 1) * (BUTTON_HGT + 4) + PADDING
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum or 0
    window.prompt = prompt
    window.bases = bases
    window.onPick = onPick
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
