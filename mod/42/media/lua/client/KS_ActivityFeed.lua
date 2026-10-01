require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SpeechIndicators"
local SurvivorNames = require "KS_SurvivorNames"

local ActivityFeed = rawget(_G, "KnoxActivityFeed") or {}
_G.KnoxActivityFeed = ActivityFeed

local MAX_LINES = 7
local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 172
local GROUP_COLOURS = {
    "<RGB:0.65,0.82,0.42>",
    "<RGB:0.45,0.72,0.90>",
    "<RGB:0.88,0.62,0.34>",
    "<RGB:0.78,0.52,0.86>",
    "<RGB:0.88,0.48,0.48>",
}

local FeedWindow = ISCollapsableWindow:derive("KnoxActivityFeedWindow")

function FeedWindow:new(x, y)
    -- Keep compact; clamp to viewport like other Knox windows. Width
    -- follows UI font scale so lines stop wrapping early on big fonts.
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local w = math.min(math.floor(WINDOW_WIDTH * scale), math.max(1, getCore():getScreenWidth() - 20))
    local h = math.min(WINDOW_HEIGHT, math.max(1, getCore():getScreenHeight() - 20))
    local window = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(window, self)
    self.__index = self
    window:setTitle("Knox Survivors")
    window:setResizable(true)
    window.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.88 }
    window.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.92 }
    return window
end

function FeedWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    if self.closeButton ~= nil then
        self.closeButton:setVisible(true)
        self.closeButton:setEnable(true)
        self.closeButton.target = self
        self.closeButton.onclick = FeedWindow.close
    end
    local titleHeight = self:titleBarHeight()
    local pad = 10
    self.messagePanel = ISRichTextPanel:new(
        pad,
        titleHeight + 4,
        self.width - pad * 2,
        self.height - titleHeight - pad - 2
    )
    self.messagePanel:initialise()
    self.messagePanel.background = true
    self.messagePanel.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.92 }
    self.messagePanel.autosetheight = false
    self.messagePanel.clip = true
    self.messagePanel:setMargins(6, 4, 6, 4)
    self.messagePanel:setAnchorLeft(true)
    self.messagePanel:setAnchorRight(true)
    self.messagePanel:setAnchorTop(true)
    self.messagePanel:setAnchorBottom(true)
    self:addChild(self.messagePanel)
end

-- Closing the window hides it without discarding the bounded activity history.
function FeedWindow:close()
    ActivityFeed.hide()
end

ActivityFeed.lines = ActivityFeed.lines or {}
ActivityFeed.window = ActivityFeed.window or nil
ActivityFeed.userHidden = ActivityFeed.userHidden == true

local function ensureWindow()
    if ActivityFeed.window ~= nil then
        return ActivityFeed.window
    end
    local x = 18
    local y = math.max(18, getCore():getScreenHeight() - WINDOW_HEIGHT - 42)
    local window = FeedWindow:new(x, y)
    window:initialise()
    window:addToUIManager()
    window:setVisible(false)
    ActivityFeed.window = window
    return window
end

local function refreshWindow()
    local window = ensureWindow()
    local formatted = {}
    for _, line in ipairs(ActivityFeed.lines) do
        formatted[#formatted + 1] = line.colour .. " " .. line.text
    end
    window.messagePanel.text = table.concat(formatted, " <LINE> ")
    window.messagePanel:paginate()
    window.messagePanel:setYScroll(-math.max(
        0,
        window.messagePanel:getScrollHeight() - window.messagePanel:getHeight()
    ))
    if KnoxSettings.showActivityFeed() and not ActivityFeed.userHidden then
        window:setVisible(true)
        window:bringToTop()
    end
end

local function addLine(text, colour)
    ActivityFeed.lines[#ActivityFeed.lines + 1] = {
        text = tostring(text),
        colour = colour,
    }
    while #ActivityFeed.lines > MAX_LINES do
        table.remove(ActivityFeed.lines, 1)
    end
    -- Visibility is presentation policy; retain bounded events while hidden.
    if KnoxSettings.showActivityFeed() then refreshWindow() end
end

local function stableColour(key)
    local hash = 0
    for index = 1, #tostring(key or "independent") do
        hash = (hash * 31 + string.byte(tostring(key), index)) % 2147483647
    end
    return GROUP_COLOURS[(hash % #GROUP_COLOURS) + 1]
end

local function speakerContext(character)
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    local affiliation = id ~= nil and KnoxPersistence.getSurvivorAffiliation(id) or nil
    if affiliation ~= nil and affiliation.kind == "player" then
        return "YOUR PARTY", "<RGB:0.68,0.84,0.43>"
    end
    if affiliation ~= nil and affiliation.factionId ~= nil then
        local faction = KnoxPersistence.getFaction(affiliation.factionId)
        local label = string.upper(tostring(faction ~= nil and faction.name
            or affiliation.factionId):gsub("%-", " "))
        return label, stableColour(affiliation.factionId)
    end
    local group = id ~= nil and KnoxPersistence.getTravelGroupFor(id) or nil
    if group ~= nil then
        local label = string.upper(tostring(group.id):gsub("travel%-group%-", "GROUP "))
        return label, stableColour(group.id)
    end
    return "SURVIVOR", "<RGB:0.82,0.82,0.76>"
end

local function characterName(character)
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    local identity = id ~= nil and KnoxPersistence.getSurvivorIdentity(id) or nil
    local _, _, name = SurvivorNames.resolve(id, identity, character)
    return name
end

-- Called only when the canonical living record transitions to dead, before
-- corpse teardown can detach its body. Corpse cleanup retries do not repeat it.
function ActivityFeed.survivorDied(id, character)
    local _, _, name = SurvivorNames.resolve(id, KnoxPersistence.getSurvivorIdentity(id), character)
    addLine(name .. " has passed away.", "<RGB:0.88,0.55,0.48>")
end

function ActivityFeed.speak(character, text)
    if not KnoxSettings.showSurvivorSpeech() then return end
    if character ~= nil then
        pcall(function()
            -- Say() is routed through local/network player chat state and is
            -- not reliably rendered for a contained off-slot IsoPlayer in
            -- single player. Build 42's native ChatElement is what actually
            -- owns overhead speech rendering, so add the line there directly.
            character:addLineChatElement(tostring(text), 1.0, 1.0, 1.0)
        end)
    end
    local groupLabel, colour = speakerContext(character)
    -- Close-but-offscreen voices get a screen-edge arrow (track them down)
    -- and a distance tag; distant lines stay feed-only.
    local tag = ""
    if character ~= nil and KnoxSpeechIndicators ~= nil
        and KnoxSpeechIndicators.noteSpeech ~= nil then
        local ok, info = pcall(function()
            local square = character:getCurrentSquare()
            local id = KnoxSurvivorRuntime ~= nil
                and KnoxSurvivorRuntime.idForCharacter(character) or nil
            local party = false
            if id ~= nil and KnoxPersistence.getSurvivorAffiliation ~= nil then
                local aff = KnoxPersistence.getSurvivorAffiliation(id)
                party = type(aff) == "table" and aff.kind == "player"
            end
            return KnoxSpeechIndicators.noteSpeech(square, id, party)
        end)
        if ok and type(info) == "table" then
            tag = " (~" .. tostring(info.dist) .. " tiles " .. tostring(info.dir) .. ")"
        end
    end
    addLine("[" .. groupLabel .. "] " .. characterName(character)
        .. ": " .. tostring(text) .. tag, colour)
end

function ActivityFeed.event(text)
    addLine(tostring(text), "<RGB:0.68,0.82,0.52>")
end

function ActivityFeed.reputation(character, change)
    change = tonumber(change) or 0
    if change == 0 then return end
    local amount = (change > 0 and "+" or "") .. tostring(change)
    addLine(amount .. " reputation with " .. characterName(character),
        change > 0 and "<RGB:0.68,0.82,0.52>" or "<RGB:0.92,0.40,0.35>")
end

function ActivityFeed.show()
    if not KnoxSettings.showActivityFeed() then return nil end
    ActivityFeed.userHidden = false
    local window = ensureWindow()
    refreshWindow()
    window:setVisible(true)
    window:bringToTop()
    return window
end

function ActivityFeed.hide()
    ActivityFeed.userHidden = true
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:setVisible(false)
    end
end

function ActivityFeed.toggle()
    if ActivityFeed.isVisible() then
        ActivityFeed.hide()
        return false
    end
    return ActivityFeed.show() ~= nil
end

function ActivityFeed.isVisible()
    local window = ActivityFeed.window
    if window == nil then return false end
    if window.isVisible ~= nil then
        local ok, visible = pcall(function() return window:isVisible() end)
        if ok then return visible == true end
    end
    return window.visible == true
end

local function reset()
    ActivityFeed.lines = {}
    ActivityFeed.userHidden = false
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:removeFromUIManager()
        ActivityFeed.window = nil
    end
end

function ActivityFeed.applySettings()
    if not KnoxSettings.showActivityFeed() and ActivityFeed.window ~= nil then
        ActivityFeed.window:setVisible(false)
    end
end

Events.OnGameStart.Add(reset)

return ActivityFeed
