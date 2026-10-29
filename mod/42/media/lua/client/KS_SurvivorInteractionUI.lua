require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ISUI/ISCollapsableWindowJoypad"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_Settings"
local UILayout = require "KS_SurvivorUILayout"

local InteractionUI = rawget(_G, "KnoxSurvivorInteractionUI") or {}
_G.KnoxSurvivorInteractionUI = InteractionUI

local INTERACTION_RANGE_SQUARED = 16
local RETAINED_RANGE_SQUARED = 25 -- Existing controller departure boundary.
local CONTACT_GRACE_MS = 1500
local SCAN_INTERVAL_MS = 180
local INTERACTION_KEY_BINDING = "KnoxSurvivorInteract"
local INTERACTION_KEY_DEFAULT = "F"
local PROMPT_WIDTH = 410
local PROMPT_HEIGHT = 28
local WINDOW_WIDTH = 456
local WINDOW_HEIGHT = 342
local PADDING = 10
local BUTTON_HEIGHT = 25

local prompts = {}
local windows = {}
local nextScanAt = 0

local CATEGORIES = {
    friendly = {
        label = "Friendly",
        description = "Show a little trust and see how they respond.",
        actions = {
            { id = "talk", label = "Talk" },
            { id = "joke", label = "Tell a Joke" },
            { id = "compliment", label = "Compliment" },
            { id = "funny_face", label = "Make a Funny Face" },
            { id = "ask_needs", label = "Ask About Needs" },
        },
    },
    neutral = {
        label = "Neutral",
        description = "Talk, ask what they need, or make a real offer.",
        actions = {
            { id = "talk", label = "Talk" },
            { id = "ask_needs", label = "Ask About Needs" },
            { id = "trade", label = "Trade" },
            { id = "give_item", label = "Give an Item" },
            { id = "recruit", label = "Ask to Join You" },
        },
    },
    mean = {
        label = "Mean",
        description = "This can damage trust and change how they see you.",
        actions = {
            { id = "insult", label = "Insult" },
        },
    },
    hostile = {
        label = "Hostile",
        description = "This can turn the encounter against you.",
        actions = {
            { id = "slap", label = "Slap" },
        },
    },
}

local CATEGORY_ORDER = { "friendly", "neutral", "mean", "hostile" }
local CONVERSATION_STATES = {
    COMPANION_FOLLOW = true, COMPANION_WAIT = true, COMPANION_HOLD = true,
    COMPANION_GUARD = true, CAMP_IDLE = true, CAMP_REPOSITION = true,
    BASE_PATROL = true,
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function playerNumber(player)
    local number = nil
    pcall(function() number = player:getPlayerNum() end)
    return tonumber(number) or 0
end

local function keyLabel()
    local label = INTERACTION_KEY_DEFAULT
    pcall(function()
        local core = getCore()
        if core ~= nil and core.getKey ~= nil then
            local key = core:getKey(INTERACTION_KEY_BINDING)
            if getKeyName ~= nil then label = getKeyName(key)
            elseif Keyboard ~= nil and Keyboard.getKeyName ~= nil then
                label = Keyboard.getKeyName(key)
            end
        end
    end)
    if label == nil or label == "" or label == "NONE" then
        return INTERACTION_KEY_DEFAULT
    end
    return tostring(label)
end

local function registerInteractionKeyBinding()
    local bindings = rawget(_G, "keyBinding")
    if type(bindings) ~= "table" then return false end
    for _, binding in ipairs(bindings) do
        if type(binding) == "table" and binding.value == INTERACTION_KEY_BINDING then
            return true
        end
    end
    local hasSection = false
    for _, binding in ipairs(bindings) do
        if type(binding) == "table" and binding.value == "[Knox Survivors]" then
            hasSection = true
            break
        end
    end
    if not hasSection then
        table.insert(bindings, { value = "[Knox Survivors]" })
    end
    local key = Keyboard ~= nil and Keyboard.KEY_F or nil
    table.insert(bindings, { value = INTERACTION_KEY_BINDING, key = key })
    return true
end

local function identityName(survivorId, playerNum)
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.getSurvivor ~= nil then
        local ok, view = safeCall(viewModel.getSurvivor, survivorId, playerNum)
        if ok and type(view) == "table" and view.displayName ~= nil
            and tostring(view.displayName) ~= "" then
            return tostring(view.displayName)
        end
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil then
        local ok, identity = safeCall(persistence.getSurvivorIdentity, survivorId)
        if ok and type(identity) == "table" then
            local first = tostring(identity.forename or identity.firstName or "")
            local last = tostring(identity.surname or identity.lastName or "")
            local name = (first .. " " .. last):gsub("^%s*(.-)%s*$", "%1")
            if name ~= "" then return name end
        end
    end
    return "Survivor"
end

local function liveCharacter(survivorId)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.getCharacter == nil then return nil end
    local ok, character = safeCall(runtime.getCharacter, survivorId)
    return ok and character or nil
end

local function alive(survivorId, character)
    if character == nil then return false end
    local dead = false
    pcall(function() dead = character:isDead() end)
    if dead then return false end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.isSurvivorAlive ~= nil then
        local ok, result = safeCall(persistence.isSurvivorAlive, survivorId)
        if ok and result == false then return false end
    end
    return true
end

local function currentSquare(character)
    local square = nil
    pcall(function() square = character:getCurrentSquare() end)
    return square
end

local function inInteractionRange(player, character, maximumDistanceSquared, checkSight)
    if player == nil or character == nil then return false end
    local playerSquare, survivorSquare = currentSquare(player), currentSquare(character)
    if playerSquare == nil or survivorSquare == nil then return false end
    local ok, near = pcall(function()
        if playerSquare:getZ() ~= survivorSquare:getZ() then return false end
        local dx = (player.getX ~= nil and player:getX() or playerSquare:getX())
            - (character.getX ~= nil and character:getX() or survivorSquare:getX())
        local dy = (player.getY ~= nil and player:getY() or playerSquare:getY())
            - (character.getY ~= nil and character:getY() or survivorSquare:getY())
        return dx * dx + dy * dy <= (maximumDistanceSquared or INTERACTION_RANGE_SQUARED)
    end)
    if not ok or not near then return false end
    if checkSight == false then return true end
    -- The prompt is for the player's interaction affordance. Testing the
    -- survivor's sight in the opposite direction made it flicker with NPC
    -- facing/vision even when the player could clearly see them.
    local okSee, canSee = pcall(function() return player:CanSee(character) end)
    return okSee and canSee == true
end

local function controllerAvailable(player, survivorId)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.getController == nil then return true end
    local okController, controller = safeCall(runtime.getController, survivorId)
    if not okController or controller == nil then return true end
    local lease = controller.playerConversation
    if lease ~= nil then return lease.player == player end
    if controller.canInterruptForMeeting ~= nil then
        local ok, allowed = safeCall(controller.canInterruptForMeeting, controller)
        if ok and allowed == true then return true end
    end
    return CONVERSATION_STATES[tostring(controller.state or "")] == true
end

local function candidateFor(player)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if player == nil or runtime == nil or runtime.activeIds == nil then return nil end
    local vpui = rawget(_G, "ViewpointUI")
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and compat.usesNativeAdapter ~= nil and compat.usesNativeAdapter()
        and vpui ~= nil and vpui.Interactions ~= nil
        and vpui.Interactions.current ~= nil and runtime.idForCharacter ~= nil then
        local ok, aimed = safeCall(vpui.Interactions.current)
        local character = ok and aimed ~= nil and aimed.object or nil
        local survivorId = character ~= nil and runtime.idForCharacter(character) or nil
        if survivorId ~= nil and alive(survivorId, character)
            and inInteractionRange(player, character) and controllerAvailable(player, survivorId) then
            return { id = survivorId, character = character,
                name = identityName(survivorId, playerNumber(player)) }
        end
        return nil -- Never replace an aimed stranger/wall with a nearby companion.
    end
    local ok, ids = safeCall(runtime.activeIds)
    if not ok or type(ids) ~= "table" then return nil end
    local best, bestDistance = nil, math.huge
    local playerSquare = currentSquare(player)
    if playerSquare == nil then return nil end
    for _, survivorId in ipairs(ids) do
        local character = liveCharacter(survivorId)
        if alive(survivorId, character) and inInteractionRange(player, character)
            and controllerAvailable(player, survivorId) then
            local square = currentSquare(character)
            local distance = math.huge
            pcall(function()
                local dx = playerSquare:getX() - square:getX()
                local dy = playerSquare:getY() - square:getY()
                distance = dx * dx + dy * dy
            end)
            if distance < bestDistance then
                bestDistance = distance
                best = {
                    id = survivorId,
                    name = identityName(survivorId, playerNumber(player)),
                    character = character,
                }
            end
        end
    end
    return best
end

local Prompt = ISPanel:derive("KnoxSurvivorInteractionPrompt")

function Prompt:new(playerNum)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.min(math.floor(PROMPT_WIDTH * scale),
        math.max(1, getPlayerScreenWidth(playerNum) - 20))
    local panel = ISPanel:new(0, 0, width, math.floor(PROMPT_HEIGHT * scale))
    setmetatable(panel, self)
    self.__index = self
    panel.playerNum = playerNum
    panel.uiScale = scale
    panel.targetName = ""
    panel.keyName = keyLabel()
    if panel.noBackground ~= nil then panel:noBackground() end
    panel:setWantMouseEvents(false)
    panel:setRenderThisPlayerOnly(playerNum)
    return panel
end

function Prompt:prerender()
    ISPanel.prerender(self)
    local font = UIFont.Medium or UIFont.Small
    local label = "Press " .. tostring(self.keyName or INTERACTION_KEY_DEFAULT)
        .. " to talk to " .. tostring(self.targetName or "Survivor")
    self:drawTextCentre(label, self.width / 2,
        (self.height - getTextManager():getFontHeight(font)) / 2,
        1, 1, 0.96, 1, font)
end

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorInteractionWindow")

local function playerIsOwner(player, survivorId)
    local service = rawget(_G, "KnoxCompanionService")
    local persistence = rawget(_G, "KnoxPersistence")
    if service == nil or service.getPlayerId == nil or persistence == nil
        or persistence.getSurvivorAffiliation == nil then return false end
    local okPlayer, playerId = safeCall(service.getPlayerId, player)
    local okAff, affiliation = safeCall(persistence.getSurvivorAffiliation, survivorId)
    return okPlayer and okAff and type(affiliation) == "table"
        and affiliation.kind == "player" and affiliation.ownerId == playerId
end

local function isHostile(player, survivorId)
    local service = rawget(_G, "KnoxCompanionService")
    local persistence = rawget(_G, "KnoxPersistence")
    if service == nil or service.getPlayerId == nil or persistence == nil
        or persistence.isSurvivorHostileToPlayer == nil then return false end
    local okId, playerId = safeCall(service.getPlayerId, player)
    if not okId or playerId == nil then return false end
    local check = service.isSociallyHostileToPlayer or persistence.isSurvivorHostileToPlayer
    local ok, hostile = safeCall(check, survivorId, playerId)
    return ok and hostile == true
end

local function singlePlayer()
    local client, server = false, false
    pcall(function() client = isClient() end)
    pcall(function() server = isServer() end)
    return not client and not server
end

local ACTION_REASON_TEXT = {
    already_with_group = "They are already travelling with a group.",
    busy = "They are busy right now.",
    character_dead = "They are no longer available.",
    companion_limit = "Your party is full.",
    cooldown = "Give them a little time before trying again.",
    danger = "It is not safe to approach right now.",
    dangerous = "It is not safe to approach right now.",
    hostile = "They will not speak with you.",
    low_reputation = "They need more trust before they join you.",
    lure = "They suggested going somewhere quieter.",
    mod_disabled = "Survivor interactions are disabled.",
    needs_time = "They need more time before travelling with you.",
    needs_unavailable = "Their needs are unavailable right now.",
    not_independent = "Only independent survivors can be recruited.",
    not_visible = "They cannot see you right now.",
    player_unavailable = "You cannot interact right now.",
    prefers_alone = "They prefer to travel alone.",
    survivor_busy = "They are busy right now.",
    survivor_unavailable = "They are temporarily unavailable.",
    too_far_away = "Move closer to interact.",
    unknown_social_act = "That interaction is unavailable.",
}

local function actionReasonText(reason, fallback)
    if type(reason) == "string" and ACTION_REASON_TEXT[reason] ~= nil then
        return ACTION_REASON_TEXT[reason]
    end
    return fallback or "That interaction could not be completed."
end

local function tradeWindowIsOpen(window, playerNum, survivorId)
    if type(window) ~= "table" or window.playerNum ~= playerNum
        or tostring(window.survivorId or "") ~= tostring(survivorId or "")
        or type(window.isVisible) ~= "function" or window.closed == true then
        return false
    end
    local ok, visible = safeCall(window.isVisible, window)
    return ok and visible == true
end

local function releaseInteractionAttention(window)
    if window.attentionStarted ~= true then return true, false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.endPlayerConversation == nil then return false end
    local ok, released = safeCall(runtime.endPlayerConversation,
        window.survivorId, window.player)
    if not ok or released ~= true then return false end
    window.attentionStarted = false
    return true, true
end

local function resumeInteractionAttention(window, shouldResume)
    if not shouldResume then return false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.beginPlayerConversation == nil then return false end
    local ok, attentive = safeCall(runtime.beginPlayerConversation,
        window.survivorId, window.player)
    window.attentionStarted = ok and attentive == true
    return window.attentionStarted
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    if self.pinButton ~= nil then self.pinButton:setVisible(false) end
    if self.collapseButton ~= nil then self.collapseButton:setVisible(false) end

    local scale = self.uiScale or 1
    local padding = PADDING * scale
    local buttonHeight = BUTTON_HEIGHT * scale
    local titleHeight = self:titleBarHeight()
    self.portrait = ISUI3DModel:new(padding, titleHeight + 10 * scale,
        100 * scale, 132 * scale)
    self.portrait:initialise()
    -- addChild instantiates ISUI3DModel's native UI3DModel. Configure only
    -- after that boundary exists; setState/setCharacter dereference it.
    self:addChild(self.portrait)
    self.portrait:setWantMouseEvents(false)
    self.portrait:setState("idle")
    self.portrait:setDirection(IsoDirections.S)
    self.portrait:setIsometric(false)
    self.portrait:setDoRandomExtAnimations(false)
    self.portrait:setZoom(14)
    self.portrait:setYOffset(-0.85)
    self.portrait:setCharacter(self.character)

    local contentX = 122 * scale
    local contentWidth = self.width - contentX - padding
    local tabGap = 4 * scale
    local tabWidth = math.floor((contentWidth - tabGap * 3) / 4)
    local tabY = titleHeight + 10 * scale
    self.categoryButtons = {}
    for index, key in ipairs(CATEGORY_ORDER) do
        local x = contentX + (index - 1) * (tabWidth + tabGap)
        local button = ISButton:new(x, tabY, tabWidth, buttonHeight,
            CATEGORIES[key].label, self, Window.onCategory)
        button:initialise()
        button.knoxCategory = key
        self:addChild(button)
        self.categoryButtons[key] = button
    end

    self.descriptionY = tabY + buttonHeight + 6 * scale
    self.actionStartY = self.descriptionY + 28 * scale
    self.actionButtons = {}
    local buttonWidth = math.floor((contentWidth - 6 * scale) / 2)
    for index = 1, 5 do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local button = ISButton:new(contentX + col * (buttonWidth + 6 * scale),
            self.actionStartY + row * (buttonHeight + 5 * scale), buttonWidth,
            buttonHeight, "", self, Window.onAction)
        button:initialise()
        button:setVisible(false)
        self:addChild(button)
        self.actionButtons[index] = button
    end

    self.feedbackY = titleHeight + 10 * scale + 150 * scale
    self:selectCategory(self.category or "neutral")
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local contentX = 122 * (self.uiScale or 1)
    if self.description ~= nil then
        self:drawText(self.description, contentX, self.descriptionY,
            0.70, 0.70, 0.67, 1, UIFont.Small)
    end
    local feedback = self.contactFeedback or self.feedback
    if feedback ~= nil and feedback ~= "" then
        self:drawText(feedback, contentX, self.feedbackY,
            0.84, 0.82, 0.75, 1, UIFont.Small)
    end
end

function Window:setCharacter(character)
    if character == nil or self.character == character then return end
    self.character = character
    if self.portrait ~= nil then self.portrait:setCharacter(character) end
end

function Window:selectCategory(category)
    if CATEGORIES[category] == nil then return end
    self.category = category
    self.description = CATEGORIES[category].description
    self.feedback = nil
    for key, button in pairs(self.categoryButtons or {}) do
        local active = key == category
        button.backgroundColor = active
            and { r = 0.31, g = 0.35, b = 0.26, a = 0.95 }
            or { r = 0.12, g = 0.12, b = 0.11, a = 0.88 }
    end
    self:refreshActions()
end

local function actionAvailability(window, action)
    local player, id = window.player, window.survivorId
    local service = rawget(_G, "KnoxCompanionService")
    if player == nil or not inInteractionRange(player, liveCharacter(id)) then
        return false, "Too far away"
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.canInteract ~= nil and not runtime.canInteract(id) then
        return false, "Temporarily unavailable"
    end
    if isHostile(player, id) then
        return false, "They will not speak with you"
    end
    if action == "trade" or action == "give_item" then
        if playerIsOwner(player, id) then return false, "For independent survivors" end
        if not singlePlayer() then return false, "Single-player only" end
        local trade = rawget(_G, "KnoxTradeUI")
        local method = nil
        if trade ~= nil then
            if action == "give_item" then method = trade.showGift
            else method = trade.show end
        end
        if type(method) ~= "function" then
            return false, action == "give_item"
                and "Give Item is unavailable." or "Trade is unavailable."
        end
        return true
    end
    if action == "recruit" then
        if service == nil or service.canRecruit == nil then return false, "Unavailable" end
        local ok, available, reason = safeCall(service.canRecruit, player, id)
        if not ok or available ~= true then
            return false, actionReasonText(reason, "Not available")
        end
    end
    return true
end

local function actionVisible(window, action)
    if action ~= "trade" and action ~= "give_item" and action ~= "recruit" then
        return true
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getSurvivorAffiliation == nil then return false end
    local ok, affiliation = safeCall(persistence.getSurvivorAffiliation, window.survivorId)
    if not ok or type(affiliation) ~= "table"
        or affiliation.kind ~= "independent" then return false end
    if persistence.getTravelGroupFor ~= nil then
        local groupOk, group = safeCall(persistence.getTravelGroupFor, window.survivorId)
        if not groupOk or group ~= nil then return false end
    end
    if persistence.getFactionForSurvivor ~= nil then
        local factionOk, faction = safeCall(persistence.getFactionForSurvivor, window.survivorId)
        if not factionOk or faction ~= nil then return false end
    end
    if action == "recruit" then return true end
    if not singlePlayer() then return false end
    return true
end

function Window:refreshActions()
    local category = CATEGORIES[self.category or "neutral"]
    local actions = category ~= nil and category.actions or {}
    self.description = category ~= nil and category.description or ""
    local visibleActions = {}
    for _, action in ipairs(actions) do
        if actionVisible(self, action.id) then
            visibleActions[#visibleActions + 1] = action
        end
    end
    for index, button in ipairs(self.actionButtons or {}) do
        local action = visibleActions[index]
        button.knoxAction = action ~= nil and action.id or nil
        if action ~= nil then
            local available, reason = actionAvailability(self, action.id)
            button:setTitle(action.label)
            button.tooltip = not available and tostring(reason) or nil
            button:setEnable(available)
            button:setVisible(true)
        else
            button:setVisible(false)
        end
    end
end

function Window:onCategory(button)
    if button ~= nil then self:selectCategory(button.knoxCategory) end
end

function Window:close()
    if windows[tonumber(self.playerNum) or 0] ~= self then return end
    InteractionUI.close(self.playerNum)
end

function Window:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:close()
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Window:onAction(button)
    if self.closed then return end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if self.attentionController ~= nil and runtime ~= nil and runtime.getController ~= nil
        and runtime.getController(self.survivorId) ~= self.attentionController then
        InteractionUI.close(self.playerNum)
        return
    end
    local action = button ~= nil and button.knoxAction or nil
    if type(action) ~= "string" then return end
    local available, unavailableReason = actionAvailability(self, action)
    if not available then
        self.feedback = unavailableReason
        self:refreshActions()
        return
    end
    if action == "trade" or action == "give_item" then
        local trade = rawget(_G, "KnoxTradeUI")
        local method = nil
        if trade ~= nil then
            if action == "give_item" then method = trade.showGift
            else method = trade.show end
        end
        if type(method) ~= "function" then
            self.feedback = action == "give_item"
                and "Give Item is unavailable." or "Trade is unavailable."
            self:refreshActions()
            return
        end
        local canOpen, resumeAttention = releaseInteractionAttention(self)
        if not canOpen then
            self.feedback = "They are busy right now."
            self:refreshActions()
            return
        end
        local called, tradeWindow = pcall(method, self.playerNum, self.survivorId)
        if called and tradeWindowIsOpen(tradeWindow, self.playerNum, self.survivorId) then
            -- Only retire this panel after the trade owner confirms that its
            -- player-scoped window is actually present. Failed opening keeps
            -- the panel and may resume attention through the existing owner.
            if windows[tonumber(self.playerNum) or 0] == self then
                InteractionUI.close(self.playerNum)
            end
            return
        end
        resumeInteractionAttention(self, resumeAttention)
        self.feedback = action == "give_item"
            and "Give Item could not be opened. Try again."
            or "Trade could not be opened. Try again."
        self:refreshActions()
        return
    end
    local service = rawget(_G, "KnoxCompanionService")
    local ok, result = false, "unavailable"
    local called, first, second = pcall(function()
        if action == "talk" and service ~= nil and service.talk ~= nil then
            return service.talk(self.player, self.survivorId)
        elseif action == "ask_needs" and service ~= nil and service.askNeeds ~= nil then
            return service.askNeeds(self.player, self.survivorId)
        elseif action == "joke" or action == "compliment" or action == "funny_face"
            or action == "insult" or action == "slap" then
            if service ~= nil and service.socialAct ~= nil then
                return service.socialAct(self.player, self.survivorId, action)
            end
        elseif action == "recruit" and service ~= nil and service.recruit ~= nil then
            return service.recruit(self.player, self.survivorId)
        end
        return false, "unavailable"
    end)
    if called then ok, result = first == true, second
    else result = tostring(first) end
    if result == "opened" then return end
    if ok then
        self.feedback = action == "talk" and "You speak with them."
            or action == "recruit" and "They joined you."
            or "They heard you."
        if action == "talk" or action == "joke" or action == "compliment"
            or action == "funny_face" or action == "insult" or action == "slap" then
            self.attentionStarted = true
        end
        if action == "recruit" then
            InteractionUI.close(self.playerNum)
            return
        end
    else
        self.feedback = actionReasonText(result)
    end
    local character = liveCharacter(self.survivorId)
    if character ~= nil then self:setCharacter(character) end
    self:refreshActions()
end

function Window:new(playerNum, target, player)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.floor(WINDOW_WIDTH * scale)
    local height = math.floor(WINDOW_HEIGHT * scale)
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.player = player
    window.survivorId = target.id
    window.character = target.character
    window.name = target.name
    window.category = "neutral"
    window.feedback = nil
    window.uiScale = scale
    window:setTitle(target.name)
    UILayout.bindInteractionWindow(window)
    return window
end

function InteractionUI.open(playerNum, target, player)
    if type(target) ~= "table" or target.id == nil or player == nil then return false end
    InteractionUI.close(playerNum)
    local window = Window:new(playerNum, target, player)
    window:initialise()
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    window:setX(getPlayerScreenLeft(playerNum) + math.max(0, (sw - window.width) / 2))
    window:setY(getPlayerScreenTop(playerNum) + math.max(0, (sh - window.height) / 2))
    window:setRenderThisPlayerOnly(playerNum)
    window:addToUIManager()
    window:bringToTop()
    windows[playerNum] = window
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.beginPlayerConversation ~= nil then
        local ok, attentive, reason = safeCall(runtime.beginPlayerConversation, target.id, player)
        window.attentionStarted = ok and attentive == true
        if window.attentionStarted and runtime.getController ~= nil then
            window.attentionController = runtime.getController(target.id)
        end
        if not window.attentionStarted then
            InteractionUI.close(playerNum)
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then feed.event(actionReasonText(ok and reason or nil)) end
            return false
        end
    end
    if JoypadState ~= nil and JoypadState.players ~= nil and JoypadState.players[playerNum + 1] then
        window.previousJoypadFocus = JoypadState.players[playerNum + 1].focus
        pcall(function() setJoypadFocus(playerNum, window) end)
    end
    return true
end

function InteractionUI.close(playerNum)
    local key = tonumber(playerNum) or 0
    local window = windows[key]
    if window == nil then return false end
    windows[key] = nil
    window.closed = true
    if window.attentionStarted then
        window.attentionStarted = false
        local runtime = rawget(_G, "KnoxSurvivorRuntime")
        if runtime ~= nil and runtime.endPlayerConversation ~= nil
            and (window.attentionController == nil or (runtime.getController ~= nil
                and runtime.getController(window.survivorId) == window.attentionController)) then
            pcall(runtime.endPlayerConversation, window.survivorId, window.player)
        end
    end
    pcall(function() window:setVisible(false); window:removeFromUIManager() end)
    local joypad = JoypadState ~= nil and JoypadState.players ~= nil and JoypadState.players[key + 1] or nil
    local focus = joypad ~= nil and joypad.focus or nil
    while focus ~= nil do
        if focus == window then
            -- A trade/health panel may already own focus. Only retire our own
            -- window/children, following the existing inventory/card convention.
            pcall(function() setJoypadFocus(key, window.previousJoypadFocus) end)
            break
        end
        focus = focus.parent
    end

    return true
end

local function anotherUIHasFocus(playerNum)
    if UIManager == nil then return false end
    local modal = false
    pcall(function()
        modal = UIManager.isModalVisible ~= nil and UIManager.isModalVisible() == true
    end)
    if modal then return true end
    local uis = nil
    pcall(function() uis = UIManager.getUI ~= nil and UIManager.getUI() or nil end)
    if uis == nil or uis.size == nil or uis.get == nil then return false end
    local own = {}
    for _, entry in pairs(prompts) do
        if type(entry) == "table" and entry.javaObject ~= nil then
            own[entry.javaObject] = true
        end
    end
    for _, entry in pairs(windows) do
        if type(entry) == "table" and entry.javaObject ~= nil then
            own[entry.javaObject] = true
        end
    end
    local ok, size = pcall(function() return uis:size() end)
    if not ok then return false end
    for index = 0, size - 1 do
        local ui = nil
        pcall(function() ui = uis:get(index) end)
        if ui ~= nil and own[ui] ~= true then
            local visible, mouseOver = false, false
            pcall(function()
                visible = ui:isVisible() == true
                mouseOver = ui.isMouseOver ~= nil and ui:isMouseOver() == true
            end)
            if visible and mouseOver then return true end
        end
    end
    return false
end

local function promptFor(playerNum)
    local prompt = prompts[playerNum]
    if prompt ~= nil then return prompt end
    if getPlayerScreenWidth == nil or getPlayerScreenHeight == nil then return nil end
    local ok, panel = pcall(function()
        local created = Prompt:new(playerNum)
        created:initialise()
        created:addToUIManager()
        return created
    end)
    if not ok or panel == nil then return nil end
    prompts[playerNum] = panel
    return panel
end

local function setPrompt(playerNum, target)
    local prompt = promptFor(playerNum)
    if prompt == nil then return end
    local open = windows[playerNum] ~= nil
    if target == nil or open then
        prompt:setVisible(false)
        prompt.targetId = nil
        return
    end
    local left, top = getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum)
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local width = math.min(math.floor(PROMPT_WIDTH * (prompt.uiScale or 1)),
        math.max(1, sw - 20))
    prompt:setWidth(width)
    prompt:setX(left + (sw - width) / 2)
    prompt:setY(top + math.max(0, sh - 112))
    prompt.targetId = target.id
    prompt.targetName = target.name
    prompt.keyName = keyLabel()
    prompt:setVisible(true)
end

function InteractionUI.nearest(player)
    return candidateFor(player)
end

function InteractionUI.onContextKey(player, timePressedContext)
    if player == nil then return end
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and compat.ownsInteractionInput ~= nil and compat.ownsInteractionInput() then return end
    if tonumber(timePressedContext) ~= nil
        and tonumber(timePressedContext) > 700 then return end
    local playerNum = playerNumber(player)
    if windows[playerNum] ~= nil or anotherUIHasFocus(playerNum) then return end
    local dead, vehicle, aiming = false, nil, false
    pcall(function()
        dead, vehicle = player:isDead(), player:getVehicle()
        aiming = player:isAiming()
    end)
    if dead or vehicle ~= nil or aiming then return end
    local target = candidateFor(player)
    if target == nil then return end
    InteractionUI.open(playerNum, target, player)
end

function InteractionUI.onKeyPressed(key)
    local core = getCore ~= nil and getCore() or nil
    if core == nil or core.isKey == nil then return end
    local ok, matched = pcall(function()
        return core:isKey(INTERACTION_KEY_BINDING, key)
    end)
    if not ok or matched ~= true then return end
    -- Keep native Interact/OnContextKey available for PZ/controller behavior;
    -- this adds the Knox-configurable F shortcut without rebinding vanilla.
    local player = getSpecificPlayer ~= nil and getSpecificPlayer(0) or nil
    if player ~= nil then InteractionUI.onContextKey(player, 0) end
end

function InteractionUI.update()
    local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    if now ~= nil and now < nextScanAt then return end
    if now ~= nil then nextScanAt = now + SCAN_INTERVAL_MS end
    local count = getNumActivePlayers ~= nil and tonumber(getNumActivePlayers()) or 1
    for playerNum = 0, math.max(0, math.min(3, (count or 1) - 1)) do
        local player = getSpecificPlayer ~= nil and getSpecificPlayer(playerNum) or nil
        local target = nil
        local settings = rawget(_G, "KnoxSettings")
        local enabled = settings == nil or settings.enabled == nil
        if not enabled then
            local ok, value = safeCall(settings.enabled)
            enabled = ok and value == true
        end
        local playerAvailable = false
        if player ~= nil then
            local dead, vehicle, aiming = false, nil, false
            local readable = pcall(function()
                dead, vehicle = player:isDead(), player:getVehicle()
                aiming = player:isAiming()
            end)
            playerAvailable = readable and enabled and not dead and vehicle == nil and not aiming
            local compat = rawget(_G, "KnoxViewpointCompatibility")
            local nativePrompt = compat ~= nil and compat.ownsInteractionInput ~= nil and compat.ownsInteractionInput()
            if playerAvailable and not nativePrompt and not anotherUIHasFocus(playerNum) then
                target = candidateFor(player)
            end
        end
        setPrompt(playerNum, target)
        local window = windows[playerNum]
        if window ~= nil then
            local attentionOkay = true
            local character = liveCharacter(window.survivorId)
            local retainedRange = inInteractionRange(player, character, RETAINED_RANGE_SQUARED, false)
            local seen, visible = pcall(function() return player:CanSee(character) end)
            local contact = seen and visible == true
            if contact then
                window.lostSightAt = nil
                window.contactFeedback = nil
            else
                window.lostSightAt = window.lostSightAt or now
                window.contactFeedback = "Lost sight of them. Move back into view."
            end
            local contactRetained = contact or (now ~= nil and window.lostSightAt ~= nil
                and now - window.lostSightAt < CONTACT_GRACE_MS)
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            if window.attentionStarted then
                local ok, attentive = false, false
                if playerAvailable and player == window.player
                    and runtime ~= nil and runtime.beginPlayerConversation ~= nil
                    and runtime.getController ~= nil then
                    local found, owner = safeCall(runtime.getController, window.survivorId)
                    local lease = found and owner ~= nil and owner.playerConversation or nil
                    -- Refresh retains attention; it must not reacquire it after
                    -- needs, danger, expiry or a new order released the lease.
                    if lease ~= nil and lease.player == window.player
                        and owner == window.attentionController
                        and owner.state == "PLAYER_CONVERSATION" then
                        if retainedRange and contact and not anotherUIHasFocus(playerNum) then
                            ok, attentive = safeCall(runtime.beginPlayerConversation,
                                window.survivorId, window.player)
                        else
                            -- Keep the existing short lease; a focus/LOS blip
                            -- cannot restart it or extend it indefinitely.
                            ok, attentive = true, true
                        end
                    end
                end
                attentionOkay = ok and attentive == true
            end
            local stillAvailable = attentionOkay and playerAvailable and player == window.player
                and alive(window.survivorId, character)
                and retainedRange and contactRetained
                and controllerAvailable(player, window.survivorId)
                and not isHostile(player, window.survivorId)
            local controller = runtime ~= nil and runtime.getController ~= nil
                and runtime.getController(window.survivorId) or nil
            if stillAvailable and window.attentionStarted and controller ~= nil
                and (controller.playerConversation == nil
                    or controller.playerConversation.player ~= window.player) then
                stillAvailable = false
            end
            if stillAvailable then
                window:setCharacter(character)
                window:refreshActions()
            else
                local feed = rawget(_G, "KnoxActivityFeed")
                if feed ~= nil and feed.event ~= nil then
                    local message = not alive(window.survivorId, character) and "Survivor unavailable."
                        or not playerAvailable and "Conversation interrupted."
                        or not retainedRange and "Too far away to continue talking."
                        or not contactRetained and "Conversation ended: contact lost."
                        or "Conversation interrupted; they need to act."
                    feed.event(message)
                end
                InteractionUI.close(playerNum)
            end
        end
    end
end

function InteractionUI.reset()
    for playerNum in pairs(windows) do InteractionUI.close(playerNum) end
    for playerNum, prompt in pairs(prompts) do
        pcall(function() prompt:removeFromUIManager() end)
        prompts[playerNum] = nil
    end
    nextScanAt = 0
end

if Events ~= nil then
    registerInteractionKeyBinding()
    if Events.OnGameBoot ~= nil and Events.OnGameBoot.Add ~= nil then
        Events.OnGameBoot.Add(registerInteractionKeyBinding)
    end
    if Events.OnTick ~= nil and Events.OnTick.Add ~= nil then
        Events.OnTick.Add(InteractionUI.update)
    end
    if Events.OnKeyPressed ~= nil and Events.OnKeyPressed.Add ~= nil then
        Events.OnKeyPressed.Add(InteractionUI.onKeyPressed)
    end
    if Events.OnContextKey ~= nil and Events.OnContextKey.Add ~= nil then
        Events.OnContextKey.Add(InteractionUI.onContextKey)
    end
    if Events.OnGameStart ~= nil and Events.OnGameStart.Add ~= nil then
        Events.OnGameStart.Add(InteractionUI.reset)
    end
end

return InteractionUI
