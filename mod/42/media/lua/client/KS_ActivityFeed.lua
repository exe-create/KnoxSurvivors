require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SpeechIndicators"
local SurvivorNames = require "KS_SurvivorNames"
local UILayout = require "KS_SurvivorUILayout"
-- One palette: the shared theme is read, never copied. A second table here is
-- how three windows end up a shade apart after one palette change.
if type(UILayout) ~= "table" then
    UILayout = rawget(_G, "KnoxSurvivorUILayout") or {}
end
local THEME = type(UILayout.theme) == "table" and UILayout.theme or {}

local ActivityFeed = rawget(_G, "KnoxActivityFeed") or {}
_G.KnoxActivityFeed = ActivityFeed

local DIGEST_WIDTH = 420
local DIGEST_HEIGHT = 260
local RAIL_WIDTH = 320
local RAIL_INSET = 18

-- NOTICE POLICY (pure): priority, collapse and the bounded digest. No widgets.
-- The UI below reads this state; nothing here knows a window exists.
local TOAST_LIMIT = 3
local TOAST_MS = 6000
local DIGEST_LIMIT = 50
local DANGER_SPACING_MS = 2000
local COLLAPSE_MS = 30000
local PRIORITY_ORDER = { danger = 1, refusal = 2, outcome = 3, routine = 4 }
-- The priority tones are the shared palette, not a second copy of it: bone and
-- muted were restated here as literals, which is how a palette change leaves one
-- surface behind.
local PRIORITY_RGB = {
    danger = THEME.red,
    refusal = THEME.amber,
    outcome = THEME.bone,
    routine = THEME.muted,
}
local DEFAULT_GROUP = { danger = "Danger", refusal = "Blocked", outcome = "Events", routine = "Routine" }

ActivityFeed.digest = ActivityFeed.digest or {}
ActivityFeed.toasts = ActivityFeed.toasts or {}
ActivityFeed.lastDangerAt = ActivityFeed.lastDangerAt or nil

local function colourTag(rgb)
    rgb = rgb or PRIORITY_RGB.outcome
    return "<RGB:" .. string.format("%.2f", rgb[1]) .. ","
        .. string.format("%.2f", rgb[2]) .. ","
        .. string.format("%.2f", rgb[3]) .. ">"
end

local function noticeNow(options)
    local now = type(options) == "table" and tonumber(options.now) or nil
    if now ~= nil then return now end
    if getTimestampMs == nil then return 0 end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or 0
end

local function cleanText(text)
    local value = tostring(text or ""):gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

-- Presentation only: wording picks the accent and the urgency. It never
-- changes what happened, and every line still reaches the digest.
function ActivityFeed.classify(text)
    local value = cleanText(text)
    local lower = value:lower()
    if lower:find("passed away", 1, true) ~= nil
        or lower:find("attacked", 1, true) ~= nil
        or lower:find("was killed", 1, true) ~= nil
        or lower:find("turned on you", 1, true) ~= nil
        or lower:find("is hostile", 1, true) ~= nil
        or lower:find("are now hostile", 1, true) ~= nil then
        return "danger"
    end
    local refusals = {
        "could not", "cannot ", "can't ", "no contact ", "base job blocked",
        "that building ", "that survivor ", "select ", "move closer ",
        "not enough ", "too far ", "storage full",
    }
    for _, prefix in ipairs(refusals) do
        if lower:sub(1, #prefix) == prefix then return "refusal" end
    end
    return "outcome"
end

function ActivityFeed.pruneToasts(now)
    now = tonumber(now) or noticeNow(nil)
    local kept = {}
    for _, toast in ipairs(ActivityFeed.toasts) do
        if now - (tonumber(toast.at) or 0) < TOAST_MS then
            kept[#kept + 1] = toast
        end
    end
    ActivityFeed.toasts = kept
    return kept
end

-- Calm 120 ms entrance and exit. This is presentation only: an expired toast
-- has already been pruned by the policy above, and the rail never delays the
-- event or changes its priority.
function ActivityFeed.toastAlpha(toast, now)
    now = tonumber(now) or noticeNow(nil)
    local at = tonumber(type(toast) == "table" and toast.at) or 0
    local age = now - at
    if age < 0 then return 1 end
    if age >= TOAST_MS then return 0 end
    if age < 120 then return 0.35 + 0.65 * (age / 120) end
    local remaining = TOAST_MS - age
    if remaining < 650 then return 0.35 + 0.65 * (remaining / 650) end
    return 1
end

-- One event in, one digest row (or one more count on the row it repeats) and,
-- unless it is routine, one rail candidate. `options` may carry priority,
-- group, key, now, collapseMs.
function ActivityFeed.note(text, options)
    options = type(options) == "table" and options or {}
    local value = cleanText(text)
    if value == "" then return nil end
    local now = noticeNow(options)
    local priority = options.priority or ActivityFeed.classify(value)
    local rgb = PRIORITY_RGB[priority] or PRIORITY_RGB.outcome
    local key = options.key or value
    local collapseMs = tonumber(options.collapseMs) or COLLAPSE_MS

    ActivityFeed.pruneToasts(now)

    -- Repetition is not always adjacent: a routine line can land between two
    -- copies of the same event. Collapse the newest matching row inside the
    -- window, not only the last row.
    local entry = nil
    for index = #ActivityFeed.digest, 1, -1 do
        local candidate = ActivityFeed.digest[index]
        if candidate.key == key
            and now - (tonumber(candidate.at) or 0) <= collapseMs then
            candidate.count = (tonumber(candidate.count) or 1) + 1
            candidate.at = now
            candidate.text = value
            entry = candidate
            break
        end
    end
    if entry == nil then
        entry = {
            text = value,
            priority = priority,
            group = options.group or DEFAULT_GROUP[priority] or "Events",
            rgb = rgb,
            colour = colourTag(rgb),
            key = key,
            at = now,
            count = 1,
        }
        ActivityFeed.digest[#ActivityFeed.digest + 1] = entry
        while #ActivityFeed.digest > DIGEST_LIMIT do
            table.remove(ActivityFeed.digest, 1)
        end
    end

    if priority ~= "routine" then
        local existing = nil
        for _, toast in ipairs(ActivityFeed.toasts) do
            if toast.key == key then existing = toast; break end
        end
        if existing ~= nil then
            existing.count = (tonumber(existing.count) or 1) + 1
            existing.at = now
        elseif priority ~= "danger" or ActivityFeed.lastDangerAt == nil
            or now - ActivityFeed.lastDangerAt >= DANGER_SPACING_MS then
            local toast = {
                text = value,
                priority = priority,
                rgb = rgb,
                key = key,
                at = now,
                count = 1,
            }
            ActivityFeed.toasts[#ActivityFeed.toasts + 1] = toast
            table.sort(ActivityFeed.toasts, function(a, b)
                local pa = PRIORITY_ORDER[a.priority] or 9
                local pb = PRIORITY_ORDER[b.priority] or 9
                if pa ~= pb then return pa < pb end
                return (tonumber(a.at) or 0) > (tonumber(b.at) or 0)
            end)
            while #ActivityFeed.toasts > TOAST_LIMIT do
                table.remove(ActivityFeed.toasts)
            end
            if priority == "danger" then ActivityFeed.lastDangerAt = now end
        end
    end

    if ActivityFeed.refreshRail ~= nil then ActivityFeed.refreshRail() end
    return entry
end

-- Newest group first, newest row first inside a group. A group is what changed
-- when the caller supplied one (for example `Scavenging`), otherwise the
-- priority's own name.
function ActivityFeed.digestGroups()
    local groups, byName = {}, {}
    for index = #ActivityFeed.digest, 1, -1 do
        local entry = ActivityFeed.digest[index]
        local name = entry.group or DEFAULT_GROUP[entry.priority] or "Events"
        local group = byName[name]
        if group == nil then
            group = { name = name, entries = {}, count = 0 }
            byName[name] = group
            groups[#groups + 1] = group
        end
        group.entries[#group.entries + 1] = entry
        group.count = group.count + (tonumber(entry.count) or 1)
    end
    return groups
end

-- Engine markup needs the numbers inline, so this one colour directive is built
-- from the theme instead of restating a grey. It lives inside the policy section
-- because that section is what the fixture loads.
local function mutedMarkup()
    local muted = type(THEME) == "table" and THEME.muted or nil
    if muted == nil then
        return ""
    end
    return "<RGB:" .. tostring(muted[1]) .. "," .. tostring(muted[2]) .. ","
        .. tostring(muted[3]) .. ">"
end

function ActivityFeed.digestText()
    local groups = ActivityFeed.digestGroups()
    if #groups == 0 then
        return mutedMarkup() .. " Nothing to report."
    end
    local rows = {}
    for _, group in ipairs(groups) do
        rows[#rows + 1] = "<RGB:0.72,0.70,0.64> " .. group.name
            .. " · " .. tostring(group.count)
        for _, entry in ipairs(group.entries) do
            local count = tonumber(entry.count) or 1
            rows[#rows + 1] = entry.colour .. " " .. entry.text
                .. (count > 1 and (" ×" .. tostring(count)) or "")
        end
    end
    return table.concat(rows, " <LINE> ")
end

function ActivityFeed.clear()
    ActivityFeed.digest = {}
    ActivityFeed.toasts = {}
    ActivityFeed.lastDangerAt = nil
end
-- END NOTICE POLICY

local function fitText(text, maximumWidth)
    return UILayout.fitText(UIFont.Small, text, maximumWidth)
end

local DigestWindow = ISCollapsableWindow:derive("KnoxNoticeDigestWindow")

function DigestWindow:new(x, y)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.min(math.floor(DIGEST_WIDTH * scale),
        math.max(1, getCore():getScreenWidth() - 20))
    local height = math.min(math.floor(DIGEST_HEIGHT * scale),
        math.max(1, getCore():getScreenHeight() - 20))
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window:setTitle("Recent events")
    window:setResizable(true)
    window.backgroundColor = { r = THEME.charcoal[1], g = THEME.charcoal[2],
        b = THEME.charcoal[3], a = 0.94 }
    window.borderColor = { r = THEME.border[1], g = THEME.border[2],
        b = THEME.border[3], a = 0.94 }
    return window
end

function DigestWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    if self.closeButton ~= nil then
        self.closeButton:setVisible(true)
        self.closeButton:setEnable(true)
        self.closeButton.target = self
        self.closeButton.onclick = DigestWindow.close
    end
    local titleHeight = self:titleBarHeight()
    local pad = 10
    self.messagePanel = ISRichTextPanel:new(pad, titleHeight + 4,
        self.width - pad * 2, self.height - titleHeight - pad - 2)
    self.messagePanel:initialise()
    self.messagePanel.background = false
    self.messagePanel.autosetheight = false
    self.messagePanel.clip = true
    self.messagePanel:setMargins(6, 4, 6, 4)
    self.messagePanel:setAnchorLeft(true)
    self.messagePanel:setAnchorRight(true)
    self.messagePanel:setAnchorTop(true)
    self.messagePanel:setAnchorBottom(true)
    self:addChild(self.messagePanel)
end

function DigestWindow:close()
    ActivityFeed.hide()
end

local NoticeRail = ISPanel:derive("KnoxNoticeRail")

local function layoutRail(rail)
    if rail == nil or getCore == nil then return end
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local rowHeight = getTextManager():getFontHeight(UIFont.Small) + 8
    -- The rail used to be a fixed 320 and every longer line was cut with an
    -- ellipsis, which is why names and reasons lost their ends. It is measured
    -- from the rows it actually holds, up to half the screen, so a sentence fits
    -- without covering the play area.
    local measured = math.floor(RAIL_WIDTH * scale)
    for _, toast in ipairs(ActivityFeed.toasts) do
        measured = math.max(measured, getTextManager():MeasureStringX(
            UIFont.Small, tostring(toast.text or "")) + 44)
    end
    local width = math.min(measured,
        math.max(1, math.floor(getCore():getScreenWidth() * 0.5)),
        math.max(1, getCore():getScreenWidth() - RAIL_INSET * 2))
    local height = rowHeight * math.max(1, #ActivityFeed.toasts) + 8
    rail:setX(RAIL_INSET)
    rail:setY(math.max(RAIL_INSET, getCore():getScreenHeight() - RAIL_INSET - height))
    rail:setWidth(width)
    rail:setHeight(height)
end

function NoticeRail:new()
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.min(math.floor(RAIL_WIDTH * scale),
        math.max(1, getCore():getScreenWidth() - RAIL_INSET * 2))
    local rowHeight = getTextManager():getFontHeight(UIFont.Small) + 8
    local panel = ISPanel:new(RAIL_INSET, RAIL_INSET, width, rowHeight)
    setmetatable(panel, self)
    self.__index = self
    panel.background = false
    panel.border = false
    panel.moveWithMouse = false
    -- Enable only while visible; a hidden rail must not capture the cursor.
    panel:setWantMouseEvents(false) -- Build 42 API; there is no setMouseEnabled.
    panel:setVisible(false)
    return panel
end

function NoticeRail:update()
    ActivityFeed.pruneToasts()
    local visible = KnoxSettings.showActivityFeed() and #ActivityFeed.toasts > 0
    if visible then layoutRail(self) end
    self:setVisible(visible)
    if self.setWantMouseEvents ~= nil then self:setWantMouseEvents(visible) end
end

function NoticeRail:render()
    if not KnoxSettings.showActivityFeed() then return end
    local rowHeight = getTextManager():getFontHeight(UIFont.Small) + 8
    local now = noticeNow(nil)
    self:drawRect(0, 0, self.width, self.height, 0.90,
        THEME.charcoal[1], THEME.charcoal[2], THEME.charcoal[3])
    self:drawRectBorder(0, 0, self.width, self.height, 0.62,
        THEME.border[1], THEME.border[2], THEME.border[3])
    for index, toast in ipairs(ActivityFeed.toasts) do
        local top = 4 + (index - 1) * rowHeight
        local rgb = toast.rgb or PRIORITY_RGB.outcome
        local alpha = ActivityFeed.toastAlpha(toast, now)
        if index > 1 then
            self:drawRect(4, top, self.width - 8, 1, 0.35 * alpha,
                THEME.border[1], THEME.border[2], THEME.border[3])
        end
        self:drawRect(0, top, 2, rowHeight - 2, alpha,
            rgb[1], rgb[2], rgb[3])
        local count = tonumber(toast.count) or 1
        local countWidth = count > 1
            and (getTextManager():MeasureStringX(UIFont.Small,
                "×" .. tostring(count)) + 8) or 0
        local textWidth = self.width - 16 - countWidth
        self:drawText(fitText(toast.text, textWidth), 10, top + 4,
            THEME.bone[1], THEME.bone[2], THEME.bone[3], alpha, UIFont.Small)
        if count > 1 then
            self:drawTextRight("×" .. tostring(count), self.width - 8, top + 4,
                THEME.muted[1], THEME.muted[2], THEME.muted[3], alpha,
                UIFont.Small)
        end
    end
end

function NoticeRail:onMouseDown(x, y)
    ActivityFeed.show()
    return true
end

local function ensureRail()
    if ActivityFeed.rail ~= nil then return ActivityFeed.rail end
    if ISPanel == nil or getCore == nil then return nil end
    local rail = NoticeRail:new()
    rail:initialise()
    rail:addToUIManager()
    rail:setVisible(false)
    ActivityFeed.rail = rail
    return rail
end

function ActivityFeed.refreshRail()
    local rail = ensureRail()
    if rail == nil then return end
    layoutRail(rail)
    local visible = KnoxSettings.showActivityFeed() and #ActivityFeed.toasts > 0
    rail:setVisible(visible)
    if rail.setWantMouseEvents ~= nil then rail:setWantMouseEvents(visible) end
end

local function ensureDigest()
    if ActivityFeed.window ~= nil then return ActivityFeed.window end
    if getCore == nil then return nil end
    local x = 18
    local y = math.max(18, getCore():getScreenHeight() - DIGEST_HEIGHT - 42)
    local window = DigestWindow:new(x, y)
    window:initialise()
    window:addToUIManager()
    window:setVisible(false)
    ActivityFeed.window = window
    return window
end

local function refreshDigest()
    local window = ensureDigest()
    if window == nil or window.messagePanel == nil then return end
    window.messagePanel.text = ActivityFeed.digestText()
    window.messagePanel:paginate()
    window.messagePanel:setYScroll(-math.max(0,
        window.messagePanel:getScrollHeight() - window.messagePanel:getHeight()))
end

ActivityFeed.userHidden = ActivityFeed.userHidden == true

local function characterName(character)
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    local identity = id ~= nil and KnoxPersistence.getSurvivorIdentity(id) or nil
    local _, _, name = SurvivorNames.resolve(id, identity, character)
    return name
end

-- One pure line for a witnessed death. The world supplies the attacker; this
-- projection never guesses a cause and never names somebody the caller could
-- not identify. An unknown attacker keeps the old neutral sentence.
function ActivityFeed.deathLine(victimName, attribution)
    local victim = cleanText(victimName)
    if victim == "" then victim = "Someone" end
    local kind = type(attribution) == "table"
        and tostring(attribution.kind or "") or ""
    if kind == "survivor" then
        local killer = cleanText(attribution.name or "")
        if killer ~= "" then
            return victim .. " was killed by " .. killer .. "."
        end
        return victim .. " was killed by another survivor."
    end
    if kind == "player" then return victim .. " was killed by you." end
    if kind == "zombie" then return victim .. " was killed by the dead." end
    -- With nobody to name, the body still has an answer. A killer outranks the
    -- cause because the player watched that happen; the cause is for the deaths
    -- that came on slowly.
    local cause = type(attribution) == "table"
        and tostring(attribution.cause or "") or ""
    if cause == "infection" then return victim .. " was taken by the fever." end
    if cause == "bled_out" then return victim .. " bled out." end
    if cause == "wounds" then return victim .. " died of their wounds." end
    return victim .. " has passed away."
end

-- One bounded, non-persisted line for a question the player actually asked.
-- The answer is cleaned and capped; the rail never receives it.
function ActivityFeed.conversationLine(question, answer)
    local reply = cleanText(answer)
    if reply == "" then return nil end
    if #reply > 240 then reply = reply:sub(1, 237) .. "..." end
    local topic = cleanText(question)
    topic = topic ~= "" and topic:lower() or "it"
    return "asked about " .. topic .. ': "' .. reply .. '"'
end

-- Called only when the canonical living record transitions to dead, before
-- corpse teardown can detach its body. Corpse cleanup retries do not repeat it.
function ActivityFeed.survivorDied(id, character, attribution)
    local witnessed = false
    if character ~= nil and getSpecificPlayer ~= nil then
        for index = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
            local ok, seen = pcall(function()
                return getSpecificPlayer(index):CanSee(character) == true
            end)
            if ok and seen then
                witnessed = true
                if KnoxPersistence.rememberObserverKnowledge ~= nil then
                    local observerId = KnoxPersistence.ensurePlayerId(getSpecificPlayer(index))
                    local known = KnoxPersistence.getObserverKnowledge(observerId, id)
                    local value = known ~= nil and known.seen ~= nil and known.seen.value or {}
                    value.alive, value.activity = false, "Dead (witnessed)"
                    local sq = character:getCurrentSquare()
                    if sq ~= nil then
                        value.position = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                        value.deathEvidence = {
                            x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                            locationSource = "observed",
                            cause = type(attribution) == "table"
                                and attribution.cause or nil,
                        }
                    end
                    KnoxPersistence.rememberObserverKnowledge(observerId, id, "seen",
                        value, getGameTime():getWorldAgeHours())
                end
            end
        end
    end
    if not witnessed then return end
    local _, _, name = SurvivorNames.resolve(id, KnoxPersistence.getSurvivorIdentity(id), character)
    local killerName = nil
    if type(attribution) == "table" and attribution.kind == "survivor"
        and attribution.character ~= nil then
        local ok, resolved = pcall(characterName, attribution.character)
        if ok and resolved ~= nil and tostring(resolved) ~= "" then
            killerName = resolved
        end
    end
    ActivityFeed.note(ActivityFeed.deathLine(name, {
        kind = type(attribution) == "table" and attribution.kind or nil,
        name = killerName,
    }), { priority = "danger", group = "Deaths" })
end

-- Returns whether the line was actually rendered. Callers that spend a
-- one-off line (a camp's warning rung, a household's greeting) must not spend it
-- while survivor speech is switched off, or the player turns the setting on to
-- find every place already talked out.
function ActivityFeed.speak(character, text)
    if not KnoxSettings.showSurvivorSpeech() then return false end
    if character ~= nil then
        pcall(function()
            -- Build 42's native ChatElement owns overhead speech rendering.
            character:addLineChatElement(tostring(text), 1.0, 1.0, 1.0)
        end)
    end
    -- Speech stays overhead. It is not a toast and is not transcribed into the
    -- digest; only a nearby/edge indicator is added when a player can hear it.
    local heard = false
    local bridge = rawget(_G, "KnoxJavaBridge")
    if character ~= nil and bridge ~= nil and getSpecificPlayer ~= nil then
        for index = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
            local ok, audible = pcall(function()
                return bridge:canHearOrder(character, getSpecificPlayer(index))
            end)
            if ok and audible == true then heard = true; break end
        end
    end
    if not heard then return true end
    if character ~= nil and KnoxSpeechIndicators ~= nil
        and KnoxSpeechIndicators.noteSpeech ~= nil then
        pcall(function()
            local square = character:getCurrentSquare()
            local id = KnoxSurvivorRuntime ~= nil
                and KnoxSurvivorRuntime.idForCharacter(character) or nil
            local party = false
            if id ~= nil and KnoxPersistence.getSurvivorAffiliation ~= nil then
                local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
                party = type(affiliation) == "table" and affiliation.kind == "player"
            end
            KnoxSpeechIndicators.noteSpeech(square, id, party)
        end)
    end
    return true
end

-- The player's own words need the same native overhead renderer survivors use.
-- Say() is the chat/console path and does not paint above the head in a
-- single-player session, so a line the player picked disappeared the moment the
-- panel closed.
function ActivityFeed.playerSays(character, text)
    if character == nil or text == nil then return false end
    if KnoxSettings ~= nil and KnoxSettings.showSurvivorSpeech ~= nil
        and not KnoxSettings.showSurvivorSpeech() then return false end
    local ok = pcall(function()
        character:addLineChatElement(tostring(text), 0.94, 0.93, 0.86)
    end)
    return ok
end

function ActivityFeed.event(text)
    return ActivityFeed.note(text)
end

-- The on-demand digest keeps a readable summary of a real exchange: one row
-- per question, grouped under the speaker. The rail is untouched and nothing
-- here is persisted, so this is not a chat history.
function ActivityFeed.conversation(character, question, answer)
    if character == nil then return nil end
    local line = ActivityFeed.conversationLine(question, answer)
    if line == nil then return nil end
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    local name = characterName(character)
    return ActivityFeed.note(line, {
        priority = "routine",
        group = "Talked with " .. tostring(name),
        key = "talk:" .. tostring(id or name) .. ":" .. cleanText(question),
    })
end

function ActivityFeed.reputation(character, change)
    change = tonumber(change) or 0
    if change == 0 then return end
    local amount = (change > 0 and "+" or "") .. tostring(change)
    ActivityFeed.note(amount .. " reputation with " .. characterName(character), {
        priority = change > 0 and "outcome" or "refusal",
        group = "Standing",
    })
end

function ActivityFeed.show()
    if not KnoxSettings.showActivityFeed() then return nil end
    ActivityFeed.userHidden = false
    local window = ensureDigest()
    if window == nil then return nil end
    refreshDigest()
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
    ActivityFeed.clear()
    ActivityFeed.userHidden = false
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:removeFromUIManager()
        ActivityFeed.window = nil
    end
    if ActivityFeed.rail ~= nil then
        ActivityFeed.rail:removeFromUIManager()
        ActivityFeed.rail = nil
    end
end

function ActivityFeed.applySettings()
    if not KnoxSettings.showActivityFeed() then
        if ActivityFeed.window ~= nil then ActivityFeed.window:setVisible(false) end
        if ActivityFeed.rail ~= nil then ActivityFeed.rail:setVisible(false) end
        ActivityFeed.toasts = {}
    end
end

-- The digest opens from the Party Orders context menu and nowhere else. A key
-- binding used to open it too, but L is the game's own skills key, so the
-- menu is the only door and this file registers no key.
Events.OnGameStart.Add(reset)

return ActivityFeed
