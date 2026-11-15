require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISUI3DModel"
require "ISUI/ISCollapsableWindowJoypad"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_Settings"
local UILayout = require "KS_SurvivorUILayout"
-- The palette is read, never copied: a second table here would drift from the
-- one every other Knox window paints with.
if type(UILayout) ~= "table" then
    UILayout = rawget(_G, "KnoxSurvivorUILayout") or {}
end
local THEME = type(UILayout.theme) == "table" and UILayout.theme or {}

local InteractionUI = rawget(_G, "KnoxSurvivorInteractionUI") or {}
_G.KnoxSurvivorInteractionUI = InteractionUI

local INTERACTION_RANGE_SQUARED = 16
local RETAINED_RANGE_SQUARED = 25 -- Existing controller departure boundary.
local CONTACT_GRACE_MS = 1500
local SCAN_INTERVAL_MS = 180
local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 300
local PADDING = 10
local BUTTON_HEIGHT = 25

local windows = {}
local nextScanAt = 0
-- The one live key and the person's name, at the bottom of the screen. The
-- world, the context menu and Viewpoint's action list still identify who is
-- there; this strip only says what the key will do.

-- The panel's shape depends on who is standing in front of the player. A
-- stranger gets conversation; somebody who already follows or lives with the
-- player gets orders and policies, because "Trade" and "Ask to join" mean
-- nothing for a person who already works for you. Every list stays at six
-- entries or fewer: this is a compact bottom-centre rectangle, not a
-- management window, and detailed configuration still belongs to the wheel.
local ACTION_LIMIT = 6

-- The player's half of a social act. The survivor's reply was already spoken
-- overhead; the line the player delivered was not, so the two halves of one
-- exchange disagreed about who was talking. These are intentions, not dialogue
-- trees: one short line per act, in the same voice as the rest of the mod.
local PLAYER_SOCIAL_LINES = {
    talk = "Got a minute to talk?",
    joke = "Heard a good one on the way here. Want to hear it?",
    compliment = "You have been carrying your weight out here. I noticed.",
    funny_face = "Watch this face for a second.",
    insult = "You are not half the survivor you think you are.",
    mock = "And they let you carry a gun?",
    blame = "This is on you. Everyone here knows it.",
    threaten = "Say that again and we will have a problem.",
    slap = "That is for what you did.",
}

-- Controller states in which a person can still be spoken to. This is only the
-- last fallback in controllerAvailable(): an existing conversation lease and a
-- pausable work state are checked first. The table was referenced but never
-- defined, so asking over a waiting companion raised "index of non-table: null"
-- every frame and the prompt never reached the screen.
local CONVERSATION_STATES = {
    IDLE = true,
    PLAYER_CONVERSATION = true,
    COMPANION_WAIT = true,
    COMPANION_FOLLOW = true,
    COMPANION_GUARD = true,
    COMPANION_PATROL_WAIT = true,
    COMPANION_DUTY_WAIT = true,
}

local STANCE_OPTIONS = {
    { value = "aggressive", label = "Aggressive" },
    { value = "defensive", label = "Defensive" },
    { value = "passive", label = "Passive" },
}
local WEAPON_OPTIONS = {
    { value = "auto", label = "Any" },
    { value = "melee", label = "Melee" },
    { value = "ranged", label = "Ranged" },
}
-- Formation and spacing were always chosen as a pair, so one cycle keeps them
-- together instead of letting this panel invent combinations no other surface
-- offers.
local FORMATION_OPTIONS = {
    { formation = "paired", spacing = 1, label = "Paired 1" },
    { formation = "paired", spacing = 2, label = "Paired 2" },
    { formation = "paired", spacing = 3, label = "Paired 3" },
    { formation = "single_file", spacing = 1, label = "Single File 1" },
    { formation = "single_file", spacing = 2, label = "Single File 2" },
    { formation = "single_file", spacing = 3, label = "Single File 3" },
}
local TOGGLE_OPTIONS = {
    { value = true, label = "On" },
    { value = false, label = "Off" },
}
local WORK_LABELS = {
    auto = "Automatic", guard = "Guard", patrol = "Patrol", cooking = "Cooking",
    farming = "Farming", woodwork = "Woodworking", barricade = "Barricading",
    hauling = "Hauling", repair = "Repairs", rest = "Rest",
}
local WORK_PAGE_ONE = { "auto", "guard", "patrol", "cooking", "hauling" }
local WORK_PAGE_TWO = { "farming", "woodwork", "barricade", "repair", "rest" }
local ASK_ACTIONS = {
    { id = "ask", topic = "day", label = "Their Day" },
    { id = "ask", topic = "home", label = "Their Home" },
    { id = "ask", topic = "group", label = "Their Group" },
    { id = "ask", topic = "health", label = "How They're Doing" },
    { id = "ask", topic = "need", label = "What They Need" },
    { id = "ask", topic = "travels", label = "Their Travels" },
}

local function capitalised(value)
    value = tostring(value or "")
    if value == "" then return value end
    return value:sub(1, 1):upper() .. value:sub(2)
end

local function fitText(font, text, maximumWidth)
    return UILayout.fitText(font, text, maximumWidth)
end

local function formationLabel(tactics)
    local formation = tactics.formation or "paired"
    local spacing = math.floor(tonumber(tactics.spacing) or 2)
    for _, option in ipairs(FORMATION_OPTIONS) do
        if option.formation == formation and option.spacing == spacing then
            return option.label
        end
    end
    return capitalised(formation) .. " " .. tostring(spacing)
end

-- The one-line summary under the tabs. Pure, so the offline fixture can prove
-- the wording without a window existing.
function InteractionUI.stateLine(context)
    context = type(context) == "table" and context or {}
    if context.owned ~= true then
        return "Standing: " .. tostring(context.standing or "Unknown")
    end
    local tactics = type(context.tactics) == "table" and context.tactics or {}
    local parts = {}
    parts[#parts + 1] = capitalised(tactics.order or "no orders")
    parts[#parts + 1] = capitalised(tactics.stance or "defensive")
    if context.resident == true then
        parts[#parts + 1] = (WORK_LABELS[tactics.work] or "Automatic") .. " duty"
    else
        parts[#parts + 1] = formationLabel(tactics)
    end
    return table.concat(parts, "  -  ")
end

-- What this survivor can be asked or told. Pure data: the window renders it and
-- decides nothing about which tabs exist.
function InteractionUI.tabPlan(context)
    context = type(context) == "table" and context or {}
    local page = tonumber(context.jobPage) or 1
    if context.owned ~= true then
        return {
            { key = "friendly", label = "Friendly",
              description = "Warm words cost nothing.",
              actions = {
                  { id = "talk", label = "Talk" },
                  { id = "joke", label = "Tell a Joke" },
                  { id = "compliment", label = "Compliment" },
                  { id = "ask_needs", label = "Check Needs" },
                  { id = "ask", topic = "standing", label = "Where We Stand" },
                  { id = "funny_face", label = "Make a Funny Face" },
              } },
            -- Reachable from Talk, never a sibling button: one conversation,
            -- one entry point. Asking somebody something and talking to them
            -- were the same act offered twice under different words.
            { key = "ask", label = "Ask", hidden = true,
              description = "Questions they can actually answer.",
              actions = ASK_ACTIONS },
            { key = "neutral", label = "Neutral",
              description = "Make a real offer.",
              actions = {
                  { id = "trade", label = "Trade" },
                  { id = "give_item", label = "Give an Item" },
                  { id = "recruit", label = "Ask to Join You" },
                  { id = "invite_base", label = "Invite to Base" },
              } },
            { key = "mean", label = "Mean",
              description = "This can damage trust.",
              actions = {
              { id = "insult", label = "Insult" },
              { id = "mock", label = "Mock Them" },
              { id = "blame", label = "Blame Them" },
              { id = "threaten", label = "Threaten" },
              { id = "slap", label = "Slap" },
          } },
            { key = "hostile", label = "Hostile",
              description = "This can turn the encounter.",
              actions = { { id = "slap", label = "Slap" } } },
        }
    end
    local orders = nil
    if context.resident == true then
        -- Exercise is a home activity, not a marching order: a follower who is
        -- walking behind the player has no idle time to spend on it, and the
        -- orders tab is already at its six-row readable budget without it. A
        -- companion can still be asked to exercise from their card.
        orders = {
            { id = "order", kind = "recall_to_party", label = "Recall to Party" },
            { id = "order", kind = "return_to_base", label = "Return to Base" },
            { id = "order", kind = "resume_normal_duty", label = "Cancel Supply Order" },
            { id = "exercise", label = "Exercise" },
            { id = "unstick", label = "Unstick" },
            { id = "ask_needs", label = "Check Needs" },
        }
    else
        orders = {
            { id = "order", kind = "follow", label = "Follow" },
            { id = "order", kind = "hold", label = "Hold" },
            { id = "order", kind = "relax", label = "Relax" },
            { id = "order", kind = "return_to_base", label = "Return Home" },
            { id = "move_in", label = "Move Into Base" },
            { id = "dismiss", label = "Dismiss" },
        }
    end
    local tactics = nil
    if context.resident == true then
        -- Residents cannot take companion-only policies (doors, climbing,
        -- pickup). Their wheel omits them, so this panel must agree with it.
        tactics = {
            { id = "cycle", cycle = "stance", label = "Stance" },
            { id = "cycle", cycle = "weapon", label = "Weapon" },
            { id = "cycle", cycle = "supplyruns", label = "Supply Runs" },
        }
    else
        tactics = {
            { id = "cycle", cycle = "stance", label = "Stance" },
            { id = "cycle", cycle = "formation", label = "Formation" },
            { id = "cycle", cycle = "weapon", label = "Weapon" },
            { id = "cycle", cycle = "doors", label = "Doors" },
            { id = "cycle", cycle = "climbing", label = "Climbing" },
            { id = "cycle", cycle = "pickup", label = "Pick Up" },
        }
    end
    local jobs = nil
    if context.resident == true then
        jobs = {}
        local list = page == 2 and WORK_PAGE_TWO or WORK_PAGE_ONE
        for _, preference in ipairs(list) do
            jobs[#jobs + 1] = { id = "work", work = preference,
                label = WORK_LABELS[preference] or capitalised(preference) }
        end
        if page == 2 then
            jobs[#jobs + 1] = { id = "job_page", page = 1, label = "Back" }
        else
            jobs[#jobs + 1] = { id = "job_page", page = 2, label = "More..." }
        end
    else
        jobs = {
            { id = "order", kind = "find_food", label = "Find Food" },
            { id = "order", kind = "find_water", label = "Find Water" },
            { id = "order", kind = "find_medical", label = "Find Medical" },
            { id = "order", kind = "find_weapon", label = "Find Weapons" },
            { id = "order", kind = "find_tools", label = "Find Tools" },
        }
    end
    return {
        { key = "friendly", label = "Friendly",
          description = "Somebody you can rely on.",
          actions = {
              { id = "talk", label = "Talk" },
              { id = "joke", label = "Tell a Joke" },
              { id = "compliment", label = "Compliment" },
              { id = "ask_needs", label = "Check Needs" },
              { id = "ask", topic = "standing", label = "Where We Stand" },
              { id = "inventory", label = "Manage Inventory" },
          } },
        -- Talk opens these for a companion or resident exactly as it does for a
        -- stranger. Hidden: one conversation, one entry point.
        { key = "ask", label = "Ask", hidden = true,
          description = "Questions they can actually answer.",
          actions = ASK_ACTIONS },
        { key = "orders", label = "Orders",
          description = "Direct orders for right now.",
          actions = orders },
        { key = "tactics", label = "Tactics",
          description = "Click a setting to change it.",
          actions = tactics },
        { key = "jobs", label = "Jobs",
          description = context.resident == true
              and "What they do when nobody is watching."
              or "What they look for while out.",
          actions = jobs },
        { key = "mean", label = "Mean",
          description = "This can damage trust.",
          actions = {
              { id = "insult", label = "Insult" },
              { id = "mock", label = "Mock Them" },
              { id = "blame", label = "Blame Them" },
              { id = "threaten", label = "Threaten" },
              { id = "slap", label = "Slap" },
          } },
    }
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function playerNumber(player)
    local number = nil
    pcall(function() number = player:getPlayerNum() end)
    return tonumber(number) or 0
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
    if controller.canPauseWorkForInteraction ~= nil then
        local ok, allowed = safeCall(controller.canPauseWorkForInteraction, controller)
        if ok and allowed == true then return true end
    end
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
    already_with_group = "They are already staying with a group.",
    ambiguous_base = "Choose which base they should live at.",
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
    already_resident = "They already live at your base.",
    no_base = "You have no base for them to move into.",
    not_companion = "They do not travel with you.",
    not_independent = "Only independent survivors can be invited or recruited.",
    not_visible = "They cannot see you right now.",
    player_unavailable = "You cannot interact right now.",
    prefers_alone = "They prefer to travel alone.",
    survivor_busy = "They are busy right now.",
    -- The controller answers a mid-work-step pause with this code. It was not
    -- in this table, so every talk or social during base work fell through to
    -- the generic "could not be completed" line (owner report, 2026-11-10):
    -- the player could not tell whether the refusal was distance, danger or a
    -- job running. Wording mirrors the service's own order-failure table.
    work_step_finishing = "They are finishing this step. Ask again in a moment.",
    not_your_survivor = "They do not take orders from you.",
    order_not_delivered = "They did not hear that order.",
    unwilling = "They are not willing to do that yet.",
    survivor_unavailable = "They are temporarily unavailable.",
    too_far_away = "Move closer to interact.",
    unknown_base = "That base does not belong to you.",
    unknown_social_act = "That interaction is unavailable.",
}

local CONVERSATION_IDS = {
    talk = true, ask_needs = true, joke = true, compliment = true,
    funny_face = true, insult = true, mock = true, blame = true,
    threaten = true, slap = true,
}

local function nowMs()
    return getTimestampMs ~= nil and tonumber(getTimestampMs()) or 0
end

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
    if not InteractionUI.ownsAttention(window) then return false end
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
    if window.attentionStarted and runtime.getController ~= nil then
        window.attentionController = runtime.getController(window.survivorId)
        window.attentionLease = window.attentionController.playerConversation
    end
    return window.attentionStarted
end

-- Live tactics for the survivor in this window, or nil when the record cannot
-- be read. One read-out feeds the labels, the state line and the cycles, so
-- this panel and the radial wheel cannot describe the same person differently.
local function tacticsOf(window)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.survivorTactics == nil or window == nil
        or window.survivorId == nil then return nil end
    local ok, values = safeCall(service.survivorTactics, window.survivorId)
    if not ok or type(values) ~= "table" then return nil end
    return values
end

local function standingLabel(window)
    if isHostile(window.player, window.survivorId) then return "Hostile" end
    local service = rawget(_G, "KnoxCompanionService")
    local persistence = rawget(_G, "KnoxPersistence")
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if service == nil or service.getPlayerId == nil or persistence == nil
        or persistence.getPlayerRelationship == nil then return "Unknown" end
    local okId, playerId = safeCall(service.getPlayerId, window.player)
    if not okId or playerId == nil then return "Unknown" end
    local okRelation, relationship = safeCall(persistence.getPlayerRelationship,
        playerId, window.survivorId)
    if not okRelation then return "Unknown" end
    if viewModel ~= nil and viewModel.trustLabelFor ~= nil then
        local labelled, label = safeCall(viewModel.trustLabelFor, relationship)
        if labelled and type(label) == "string" and label ~= "" then return label end
    end
    return "Unknown"
end


-- The header says who this is and where they stand, in words. Presentation
-- only: the labels come from the same reads the state line already uses.
local function roleLabel(window)
    if window.resident == true then return "Resident" end
    if window.owned == true then return "Companion" end
    return "Stranger"
end

local function standingTone(window)
    if isHostile(window.player, window.survivorId) then return "red" end
    if window.owned == true then return "green" end
    return "muted"
end

local function cycleCurrent(tactics, cycle)
    if cycle == "stance" then return tactics.stance or "defensive" end
    if cycle == "weapon" then return tactics.weapon or "auto" end
    if cycle == "doors" then return tactics.doors == true end
    if cycle == "climbing" then return tactics.climbing ~= false end
    if cycle == "pickup" then return tactics.loot == true end
    if cycle == "supplyruns" then return tactics.lootRuns == true end
    return nil
end

local function cycleLabel(tactics, cycle)
    if cycle == "formation" then return "Formation: " .. formationLabel(tactics) end
    local current = cycleCurrent(tactics, cycle)
    if cycle == "stance" then return "Stance: " .. capitalised(current) end
    if cycle == "weapon" then
        for _, option in ipairs(WEAPON_OPTIONS) do
            if option.value == current then return "Weapon: " .. option.label end
        end
        return "Weapon: Any"
    end
    if cycle == "doors" then return "Doors: " .. (current and "Allowed" or "Closed") end
    if cycle == "climbing" then return "Climbing: " .. (current and "Allowed" or "Closed") end
    if cycle == "pickup" then return "Pick Up: " .. (current and "On" or "Off") end
    if cycle == "supplyruns" then return "Supply Runs: " .. (current and "On" or "Off") end
    return "Setting"
end

local function cycleSequence(cycle)
    if cycle == "stance" then return STANCE_OPTIONS end
    if cycle == "weapon" then return WEAPON_OPTIONS end
    if cycle == "formation" then return FORMATION_OPTIONS end
    if cycle == "doors" or cycle == "climbing" then
        return { { value = true }, { value = false } }
    end
    if cycle == "pickup" or cycle == "supplyruns" then return TOGGLE_OPTIONS end
    return {}
end

local function optionMatches(cycle, option, tactics)
    if cycle == "formation" then
        return option.formation == (tactics.formation or "paired")
            and option.spacing == math.floor(tonumber(tactics.spacing) or 2)
    end
    return option.value == cycleCurrent(tactics, cycle)
end

local function nextCycle(tactics, cycle)
    local options = cycleSequence(cycle)
    if #options == 0 then return nil end
    local current = nil
    for index, option in ipairs(options) do
        if optionMatches(cycle, option, tactics) then current = index; break end
    end
    return options[((current or 0) % #options) + 1]
end

local function cycleHint(tactics, action)
    if action.cycle == nil then return nil end
    local option = nextCycle(tactics, action.cycle)
    if option == nil then return nil end
    local nextLabel = option.label
        or (option.value == true and "Allowed" or false)
        or "Closed"
    return "Click to change: " .. tostring(nextLabel)
end

local function actionLabel(tactics, action)
    tactics = tactics or {}
    if action.cycle ~= nil then return cycleLabel(tactics, action.cycle) end
    local label = tostring(action.label or "")
    if action.kind ~= nil and tactics.order == action.kind then
        return label .. " (active)"
    end
    if action.work ~= nil and tactics.work == action.work then
        return label .. " (active)"
    end
    return label
end



-- One current answer, never a transcript. The two text regions scroll only
-- when their measured content cannot fit around the existing action buttons.
local function talkTextLayout(width, height, scale, fontH, tabY, tabHeight, description, state, feedback, measure)
    local padding = PADDING * scale
    local contentX = math.min(122 * scale, math.max(padding, math.floor(width * 0.36)))
    local contentWidth = math.max(1, width - contentX - padding)
    local textWidth = math.max(1, contentWidth - 18)
    local context, response = {}, {}
    local function append(target, value, tone)
        for _, line in ipairs(UILayout.wrapLines(tostring(value or ""), textWidth, measure)) do
            target[#target + 1] = { text = line, tone = tone }
        end
    end
    append(context, description, "description")
    append(context, state, "state")
    append(response, feedback, "feedback")
    local rowH = fontH + 2
    local contextY = tabY + tabHeight + 8 * scale
    local actionHeight = math.floor((ACTION_LIMIT + 1) / 2) * (tabHeight + 5 * scale)
    local available = math.max(2, height - padding - contextY - actionHeight - 2 * scale)
    local contextH = math.max(1, math.min(math.max(rowH, #context * rowH), math.max(1, available - rowH)))
    local actionY = contextY + contextH
    local feedbackY = actionY + actionHeight + 2 * scale
    local feedbackH = math.max(1, height - padding - feedbackY)
    return { x = contentX, width = contentWidth, rowH = rowH, contextY = contextY,
        contextH = contextH, actionY = actionY, feedbackY = feedbackY,
        feedbackH = feedbackH, context = context, response = response }
end

local function drawTalkText(self, y, row)
    local height = row.height or self.itemheight
    local item = row.item
    local r, g, b = 0.84, 0.82, 0.75
    if item.tone == "description" then r, g, b = 0.70, 0.70, 0.67 end
    if item.tone == "state" then r, g, b = 0.88, 0.85, 0.72 end
    self:drawText(item.text, 0, y, r, g, b, 1, UIFont.Small)
    return y + height
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    if self.pinButton ~= nil then self.pinButton:setVisible(false) end
    if self.collapseButton ~= nil then self.collapseButton:setVisible(false) end
    UILayout.finishWindow(self, "Close conversation")

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

    local contentX = math.min(122 * scale, math.max(padding, math.floor(self.width * 0.36)))
    local contentWidth = self.width - contentX - padding
    self.contentX = contentX
    local tabY = titleHeight + 10 * scale
    self.tabY = tabY
    self.tabHeight = buttonHeight
    self.tabWidth = contentWidth
    self.categoryButtons = {}
    -- Tab buttons are created lazily: the tab set depends on whether this
    -- survivor belongs to the player, and a recruited stranger must not leave
    -- dead tabs behind. layoutTabs() positions whatever the plan asks for.
    self:layoutTabs(0)

    self.descriptionY = tabY + buttonHeight + 8 * scale
    self.stateY = self.descriptionY + 15 * scale
    self.actionStartY = self.stateY + 21 * scale
    self.actionButtons = {}
    local buttonWidth = math.floor((contentWidth - 6 * scale) / 2)
    for index = 1, ACTION_LIMIT do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local button = ISButton:new(contentX + col * (buttonWidth + 6 * scale),
            self.actionStartY + row * (buttonHeight + 5 * scale), buttonWidth,
            buttonHeight, "", self, Window.onAction)
        button:initialise()
        UILayout.tintButton(button)
        button:setVisible(false)
        self:addChild(button)
        self.actionButtons[index] = button
    end

    self.feedbackY = self.actionStartY
        + math.floor((ACTION_LIMIT + 1) / 2) * (buttonHeight + 5 * scale) + 2 * scale
    local function textList()
        local list = ISScrollingListBox:new(contentX, 0, math.max(1, contentWidth), 1)
        list:initialise(); list:instantiate()
        list:setFont(UIFont.Small)
        list.joypadParent = self
        list.background = false; list.backgroundColor.a = 0; list.drawBorder = false
        list.doDrawItem = drawTalkText; list.autoAddJoypadButton = false
        self:addChild(list)
        return list
    end
    self.contextTextList = textList()
    self.feedbackTextList = textList()
    self:selectCategory(self.category)
end

-- One row of tabs, sized to the count the current plan needs. Extra buttons are
-- hidden rather than destroyed so switching a survivor's ownership mid-window
-- cannot leak a stale action.
function Window:layoutTabs(count)
    local scale = self.uiScale or 1
    local padding = PADDING * scale
    local buttonHeight = self.tabHeight or BUTTON_HEIGHT * scale
    local gap = 4 * scale
    local contentX = self.contentX or 122 * scale
    local contentWidth = self.width - contentX - padding
    count = math.max(0, math.min(ACTION_LIMIT, tonumber(count) or 0))
    self.tabCount = count
    if count == 0 then return end
    local tabWidth = math.floor((contentWidth - gap * (count - 1)) / count)
    for index = 1, count do
        local button = self.categoryButtons[index]
        if button == nil then
            button = ISButton:new(0, self.tabY or 0, tabWidth, buttonHeight,
                "", self, Window.onCategory)
            button:initialise(); UILayout.tintButton(button)
            self:addChild(button)
            self.categoryButtons[index] = button
        end
        button:setX(contentX + (index - 1) * (tabWidth + gap))
        button:setY(self.tabY or 0)
        button:setWidth(tabWidth)
        button:setHeight(buttonHeight)
        button:setVisible(true)
    end
    for index = count + 1, #self.categoryButtons do
        self.categoryButtons[index]:setVisible(false)
        self.categoryButtons[index].knoxCategory = nil
    end
end

-- THE SHEET HEADER
-- The panel used to open as a vanilla sub-window with the person's name in the
-- game's own title strip, next to a close glyph and a collapse arrow nobody
-- needed. It now repaints that strip as the same charcoal band the notebook
-- uses: name in Medium, role and standing as chips on the right, a hairline
-- under it and our own close glyph. The title string, the drag behaviour and
-- the close path stay the window's own; only the paint changes.
local inheritedSheetRender = Window.render
local SHEET_CLOSE_HIT = 34

function Window:sheetHeaderHeight()
    if self.titleBarHeight == nil then return 0 end
    local ok, height = pcall(function() return self:titleBarHeight() end)
    local value = ok and tonumber(height) or nil
    return value ~= nil and math.max(0, value) or 0
end

function Window:drawSheetHeader()
    local titleH = self:sheetHeaderHeight()
    if titleH <= 0 then return end
    local theme = UILayout.theme
    local manager = getTextManager()
    self:drawRect(0, 0, self.width, titleH,
        0.97, theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
    self:drawRect(0, titleH - 1, self.width, 1,
        0.90, theme.border[1], theme.border[2], theme.border[3])
    local mediumH = manager:getFontHeight(UIFont.Medium)
    local smallH = manager:getFontHeight(UIFont.Small)
    local chips, blockWidth = nil, 0
    if self.headerRole ~= nil or self.headerStanding ~= nil then
        local entries = {}
        if self.headerRole ~= nil then
            entries[#entries + 1] = { text = tostring(self.headerRole), tone = "green" }
        end
        if self.headerStanding ~= nil then
            entries[#entries + 1] = { text = tostring(self.headerStanding),
                tone = self.headerTone or "muted" }
        end
        chips = UILayout.chipCells(entries, math.max(1, self.width - 46), {
            gap = 6, pad = 7, height = math.max(14, smallH + 2),
            measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end,
        })
        -- Only the first row sits in the band; a third chip that wrapped would
        -- be clipped by the page below, so it is not painted at all.
        local visible = { cells = {}, rowHeight = chips.rowHeight, height = chips.rowHeight }
        for _, cell in ipairs(chips.cells or {}) do
            if cell.row == 0 then
                visible.cells[#visible.cells + 1] = cell
                blockWidth = math.max(blockWidth, cell.x + cell.width)
            end
        end
        chips = visible
    end
    if blockWidth > self.width - 58 then blockWidth = math.max(0, self.width - 58) end
    local chipX = self.width - 34 - blockWidth
    if chipX < 12 then chipX = 12 end
    if chips ~= nil then
        local chipY = math.max(0, math.floor((titleH - (chips.rowHeight or smallH)) / 2))
        UILayout.drawChips(self, chips, chipX, chipY, { font = UIFont.Small })
    end
    local name = tostring(self.knoxName or self.name or "Survivor")
    name = UILayout.fitText(UIFont.Medium, name,
        math.max(1, self.width - 34 - blockWidth - 20),
        function(value) return manager:MeasureStringX(UIFont.Medium, value) end)
    self:drawText(name, 12, math.max(0, math.floor((titleH - mediumH) / 2) - 1),
        theme.bone[1], theme.bone[2], theme.bone[3], 0.96, UIFont.Medium)
    self:drawText("X", self.width - 22, math.max(0, math.floor((titleH - mediumH) / 2) - 1),
        theme.muted[1], theme.muted[2], theme.muted[3], 0.90, UIFont.Medium)
end

function Window:render()
    if inheritedSheetRender ~= nil then inheritedSheetRender(self) end
    if self.isCollapsed or not self:isVisible() then return end
    self:drawSheetHeader()
end

-- The band covers the game's close glyph, so the same corner closes the panel.
function Window:onMouseDown(x, y)
    local titleH = self:sheetHeaderHeight()
    if titleH > 0 and y >= 0 and y <= titleH
        and x >= self.width - SHEET_CLOSE_HIT and x <= self.width then
        self:close()
        return true
    end
    if ISCollapsableWindowJoypad.onMouseDown ~= nil then
        return ISCollapsableWindowJoypad.onMouseDown(self, x, y)
    end
    return false
end
-- END SHEET HEADER

function Window:planFor()
    return InteractionUI.tabPlan({
        owned = self.owned == true,
        resident = self.resident == true,
        tactics = tacticsOf(self) or {},
        jobPage = self.jobPage or 1,
    })
end

function Window:layoutTalkText()
    if self.contextTextList == nil or self.feedbackTextList == nil then return end
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local feedback = self.contactFeedback or self.feedback
    local geometry = talkTextLayout(self.width, self.height, self.uiScale or 1, fontH,
        self.tabY, self.tabHeight, self.description, self.stateLine, feedback,
        function(value) return manager:MeasureStringX(UIFont.Small, value) end)
    local widthChanged = self.knoxTalkWidth ~= self.width
    self.contentX = geometry.x
    if self.portrait ~= nil then
        -- A viewport cap can shrink the text column without shrinking the
        -- font scale. Keep the model in its own rail on those narrow screens.
        local padding = PADDING * (self.uiScale or 1)
        self.portrait:setWidth(math.max(1, geometry.x - padding * 2))
        self.portrait:setHeight(math.max(1, math.min(132 * (self.uiScale or 1), self.height - self.tabY - padding)))
    end
    if widthChanged then self:layoutTabs(self.tabCount) end
    local function fill(list, rows, y, height, sameText)
        local oldScroll = sameText and list:getYScroll() or 0
        list:setX(geometry.x); list:setY(y); list:setWidth(geometry.width); list:setHeight(height)
        list.itemheight = geometry.rowH
        list:clear(); list:setScrollHeight(0)
        for _, row in ipairs(rows) do list:addItem(row.text, row) end
        list:setYScroll(oldScroll)
    end
    fill(self.contextTextList, geometry.context, geometry.contextY, geometry.contextH,
        self.knoxTalkDescription == self.description and self.knoxTalkState == self.stateLine)
    fill(self.feedbackTextList, geometry.response, geometry.feedbackY, geometry.feedbackH,
        self.knoxTalkFeedback == feedback)
    local scale = self.uiScale or 1
    local buttonWidth = math.max(1, math.floor((geometry.width - 6 * scale) / 2))
    for index, button in ipairs(self.actionButtons or {}) do
        button:setX(geometry.x + ((index - 1) % 2) * (buttonWidth + 6 * scale))
        button:setY(geometry.actionY + math.floor((index - 1) / 2) * (self.tabHeight + 5 * scale))
        button:setWidth(buttonWidth)
    end
    self.knoxTalkWidth, self.knoxTalkHeight, self.knoxTalkFont = self.width, self.height, fontH
    self.knoxTalkDescription, self.knoxTalkState, self.knoxTalkFeedback = self.description, self.stateLine, feedback
end

-- Player action waiting on a running work step. The controller answers
-- work_step_finishing while a native step is in flight; re-offering the same
-- refused action is the only retry that needs no new state owner, and a
-- delivered action has already cleared the row, so nothing is sent twice.
function Window:updatePendingAction()
    local pending = self.pendingAction
    if pending == nil then return end
    local now = nowMs()
    if now == 0 or now >= pending.untilMs then
        self.pendingAction = nil
        return
    end
    if now < pending.nextAt then return end
    pending.nextAt = now + 700
    self.pendingAction = nil
    self:onAction({ id = pending.id, label = pending.label, kind = pending.kind })
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    self:updatePendingAction()
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    if self.knoxTalkWidth ~= self.width or self.knoxTalkHeight ~= self.height or self.knoxTalkFont ~= fontH
        or self.knoxTalkDescription ~= self.description or self.knoxTalkState ~= self.stateLine
        or self.knoxTalkFeedback ~= (self.contactFeedback or self.feedback) then
        self:layoutTalkText()
    end
end

function Window:setCharacter(character)
    if character == nil or self.character == character then return end
    self.character = character
    if self.portrait ~= nil then self.portrait:setCharacter(character) end
end

function Window:selectCategory(category)
    local plan = self:planFor()
    local found = nil
    for _, entry in ipairs(plan) do
        if entry.key == category then found = entry; break end
    end
    if found == nil then found = plan[1] end
    if found == nil then return end
    self.category = found.key
    self.plan = plan
    self.feedback = nil
    self:refreshActions()
end

local function actionAvailability(window, action)
    local id = type(action) == "table" and tostring(action.id or "") or tostring(action)
    local player, survivorId = window.player, window.survivorId
    local service = rawget(_G, "KnoxCompanionService")
    if window.attentionPending then return false, "Finishing the current step..." end
    if player == nil or not inInteractionRange(player, liveCharacter(survivorId)) then
        return false, "Too far away"
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.canInteract ~= nil and not runtime.canInteract(survivorId) then
        return false, "Temporarily unavailable"
    end
    -- A hostile survivor refuses conversation, but the Hostile tab exists for
    -- exactly that person: their refusal must not also disarm the one action
    -- that tab offers.
    if id ~= "slap" and isHostile(player, survivorId) then
        return false, "They will not speak with you"
    end
    if id == "trade" or id == "give_item" then
        if playerIsOwner(player, survivorId) then return false, "Use Manage Inventory for your survivors" end
        if not singlePlayer() then return false, "Single-player only" end
        local trade = rawget(_G, "KnoxTradeUI")
        local method = nil
        if trade ~= nil then
            if id == "give_item" then method = trade.showGift
            else method = trade.show end
        end
        if type(method) ~= "function" then
            return false, id == "give_item"
                and "Give Item is unavailable." or "Trade is unavailable."
        end
        return true
    end
    if id == "recruit" then
        if service == nil or service.canRecruit == nil then return false, "Unavailable" end
        local ok, available, reason = safeCall(service.canRecruit, player, survivorId)
        if not ok or available ~= true then
            return false, actionReasonText(reason, "Not available")
        end
    end
    if id == "invite_base" then
        if service == nil or service.canInviteToBase == nil then return false, "Unavailable" end
        local ok, available, reason = safeCall(service.canInviteToBase, player, survivorId)
        if not ok or available ~= true then
            return false, actionReasonText(reason, "Not available")
        end
    end
    if id == "move_in" then
        if service == nil or service.canMoveIntoBase == nil then return false, "Unavailable" end
        local ok, available, reason = safeCall(service.canMoveIntoBase, player, survivorId)
        if not ok or available ~= true then
            return false, actionReasonText(reason, "Not available")
        end
    end
    if id == "exercise" then
        local exercise = rawget(_G, "KnoxSurvivorExercise")
        if exercise == nil or exercise.refusal == nil then
            return false, "Exercise is unavailable."
        end
        local checked, reason = safeCall(exercise.refusal, player, survivorId)
        if not checked then return false, "Exercise is unavailable." end
        if reason ~= nil then
            return false, exercise.refusalText ~= nil
                and exercise.refusalText(reason) or "They cannot exercise now."
        end
        return true
    end
    if id == "cycle" or id == "order" or id == "work" or id == "dismiss" or id == "unstick" then
        if window.owned ~= true then return false, "Not one of yours" end
    end
    if id == "cycle" and tacticsOf(window) == nil then
        return false, "Their settings are unavailable"
    end
    return true
end

local function actionVisible(window, action)
    local id = type(action) == "table" and tostring(action.id or "") or tostring(action)
    if id == "inventory" then return playerIsOwner(window.player, window.survivorId) end
    if id == "move_in" then
        return window.owned == true and window.resident ~= true
    end
    if id ~= "trade" and id ~= "give_item" and id ~= "recruit"
        and id ~= "invite_base" then return true end
    if id == "trade" or id == "give_item" then
        return singlePlayer() and not playerIsOwner(window.player, window.survivorId)
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
    if not singlePlayer() then return false end
    return true
end

-- One click moves a tactic to its next real option through the same setters the
-- wheel uses. The panel never writes a setting the wheel cannot also show.
local function applyCycle(window, cycle)
    local service = rawget(_G, "KnoxCompanionService")
    local tactics = tacticsOf(window)
    if service == nil or tactics == nil then return false, "unavailable" end
    local option = nextCycle(tactics, cycle)
    if option == nil then return false, "unavailable" end
    local player, survivorId = window.player, window.survivorId
    local setter, args = nil, nil
    if cycle == "stance" then
        setter, args = service.setCombatStance, { player, survivorId, option.value }
    elseif cycle == "weapon" then
        setter, args = service.setWeaponPreference, { player, survivorId, option.value }
    elseif cycle == "formation" then
        setter, args = service.setFormation,
            { player, survivorId, option.formation, option.spacing }
    elseif cycle == "doors" then
        setter, args = service.setDoorOpening, { player, survivorId, option.value }
    elseif cycle == "climbing" then
        setter, args = service.setClimbing, { player, survivorId, option.value }
    elseif cycle == "pickup" then
        setter, args = service.setAutoLoot, { player, survivorId, option.value }
    elseif cycle == "supplyruns" then
        setter, args = service.setResidentLootRuns, { player, survivorId, option.value }
    end
    if type(setter) ~= "function" then return false, "unavailable" end
    -- Project Zomboid's Lua is 5.1: the global unpack is the only one there.
    local called, applied, reason = pcall(setter, unpack(args))
    if not called or applied ~= true then return false, reason end
    local after = tacticsOf(window) or tactics
    return true, cycleLabel(after, cycle) .. "."
end

-- Ask which home the player means whenever they own more than one. The panel
-- never answers that question itself, not even by preferring the base they
-- happen to stand in: the player owns the choice, and a silent fallback would
-- post somebody to the wrong settlement. Returns true when the chooser took
-- the action over and the caller must stop.
local function openHomeChoice(window, prompt, deliver)
    local picker = rawget(_G, "KnoxBasePicker")
    local service = rawget(_G, "KnoxCompanionService")
    if picker == nil or picker.choose == nil or service == nil
        or service.baseChoicesFor == nil or type(deliver) ~= "function" then
        return false
    end
    local bases = service.baseChoicesFor(window.player) or {}
    if #bases < 2 then return false end
    local playerNum = window.playerNum
    return picker.choose(playerNum, prompt, bases, function(baseId)
        if baseId == nil then return end
        local called, accepted, result = safeCall(deliver, window.player, window.survivorId, baseId)
        local live = windows[tonumber(playerNum) or 0]
        if called and accepted == true then
            if live == window then InteractionUI.close(playerNum) end
            return
        end
        local text = actionReasonText(result, "That could not be arranged.")
        local feed = rawget(_G, "KnoxActivityFeed")
        if feed ~= nil and feed.event ~= nil then feed.event(text) end
        if live == window then
            window.feedback = text
            window:refreshActions()
        end
    end)
end

function Window:refreshActions()
    local plan = self:planFor()
    self.plan = plan
    local tab = nil
    for _, entry in ipairs(plan) do
        if entry.key == self.category then tab = entry; break end
    end
    if tab == nil then tab = plan[1] end
    if tab == nil then return end
    self.category = tab.key
    self.description = tab.description or ""
    local tactics = tacticsOf(self) or {}
    self.stateLine = InteractionUI.stateLine({
        owned = self.owned == true,
        resident = self.resident == true,
        standing = standingLabel(self),
        tactics = tactics,
    })
    -- A hidden tab keeps its actions selectable by key but never gets a
    -- button: the way in is the action that opens it.
    local tabButtons = {}
    for _, entry in ipairs(plan) do
        if entry.hidden ~= true then tabButtons[#tabButtons + 1] = entry end
    end

    self.headerRole = roleLabel(self)
    self.headerStanding = standingLabel(self)
    self.headerTone = standingTone(self)
    self:layoutTabs(#tabButtons)
    for index, entry in ipairs(tabButtons) do
        local button = self.categoryButtons[index]
        if button ~= nil then
            button.knoxCategory = entry.key
            button:setTitle(UILayout.fitText(UIFont.Small,entry.label,math.max(1,button.width-12)))
            button.tooltip=entry.label
            -- Selection is the shared green, muted through the charcoal so a
            -- category reads as chosen without becoming a second accent colour.
            button.backgroundColor = entry.key == self.category
                and { r = THEME.green[1] * 0.62, g = THEME.green[2] * 0.62,
                    b = THEME.green[3] * 0.62, a = 0.95 }
                or { r = THEME.charcoal[1] + 0.03, g = THEME.charcoal[2] + 0.03,
                    b = THEME.charcoal[3] + 0.03, a = 0.92 }
        end
    end
    local visibleActions = {}
    for _, action in ipairs(tab.actions or {}) do
        if actionVisible(self, action) then
            visibleActions[#visibleActions + 1] = action
        end
    end
    for index, button in ipairs(self.actionButtons or {}) do
        local action = visibleActions[index]
        button.knoxAction = action
        if action ~= nil then
            local available, reason = actionAvailability(self, action)
            local label=actionLabel(tactics,action)
            local fitted=UILayout.fitText(UIFont.Small,label,math.max(1,button.width-12))
            button:setTitle(fitted)
            local hint=not available and tostring(reason)
                or cycleHint(tactics, action)
            button.tooltip=fitted~=label and (label .. (hint and ("\n"..hint) or "")) or hint
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
    if type(action) ~= "table" then return end
    local available, unavailableReason = actionAvailability(self, action)
    if not available then
        self.feedback = unavailableReason
        self:refreshActions()
        return
    end
    local id = tostring(action.id or "")
    if id == "inventory" then
        local inventory = rawget(_G, "KnoxCompanionInventory")
        local canOpen, resumeAttention = releaseInteractionAttention(self)
        if not canOpen then return end
        local called, opened, reason = safeCall(inventory ~= nil and inventory.show,
            self.playerNum, self.survivorId)
        if called and opened == true then InteractionUI.close(self.playerNum); return end
        resumeInteractionAttention(self, resumeAttention)
        -- Same sentence as every other surface: the inventory owner owns the
        -- wording for its own refusal codes.
        self.feedback = inventory ~= nil and inventory.refusalText ~= nil
            and inventory.refusalText(reason)
            or actionReasonText(reason, "Inventory is unavailable.")
        return
    end
    if id == "trade" or id == "give_item" then
        local trade = rawget(_G, "KnoxTradeUI")
        local method = nil
        if trade ~= nil then
            if id == "give_item" then method = trade.showGift
            else method = trade.show end
        end
        if type(method) ~= "function" then
            self.feedback = id == "give_item"
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
        self.feedback = id == "give_item"
            and "Give Item could not be opened. Try again."
            or "Trade could not be opened. Try again."
        self:refreshActions()
        return
    end
    if id == "exercise" then
        -- The native fitness action the player's own button queues, on the
        -- survivor's body. One owner decides whether it can start; this panel
        -- only reports what it said.
        local exercise = rawget(_G, "KnoxSurvivorExercise")
        local called, started, reason = safeCall(exercise ~= nil and exercise.start or nil,
            self.player, self.survivorId, action.exercise or "squats")
        if called and started == true then
            self.attentionStarted = true
            self.feedback = "Exercise - they start on the spot."
        else
            self.feedback = exercise ~= nil and exercise.refusalText ~= nil
                and exercise.refusalText(reason) or actionReasonText(reason)
        end
        self:refreshActions()
        return
    end
    local service = rawget(_G, "KnoxCompanionService")
    if id == "job_page" then
        self.jobPage = tonumber(action.page) or 1
        self:refreshActions()
        return
    end
    if id == "invite_base" or id == "move_in" then
        -- Several homes is a question, not a refusal: ask before the service
        -- touches any affiliation or duty row, and let a cancel change nothing.
        local checker = service ~= nil
            and (id == "move_in" and service.canMoveIntoBase or service.canInviteToBase)
            or nil
        local deliver = service ~= nil
            and (id == "move_in" and service.moveIntoBase or service.inviteToBase)
            or nil
        local checked, available, reason = safeCall(checker, self.player, self.survivorId)
        if checked and available == true and reason == "choose_base" then
            local prompted = openHomeChoice(self,
                id == "move_in" and "Move them into which base?"
                    or "Invite them to which base?", deliver)
            if prompted then return end
            self.feedback = actionReasonText("ambiguous_base")
            self:refreshActions()
            return
        end
    end
    if id == "cycle" then
        local applied, message = applyCycle(self, action.cycle)
        self.feedback = applied and message
            or actionReasonText(message, "That setting could not be changed.")
        self:refreshActions()
        return
    end
    if id == "ask" then
        local called, answered, answer = safeCall(service ~= nil and service.askAbout,
            self.player, self.survivorId, action.topic)
        if called and answered == true and type(answer) == "string" then
            self.feedback = "\"" .. answer .. "\""
            self.attentionStarted = true
            local feed = rawget(_G, "KnoxActivityFeed")
            local speaker = rawget(_G, "KnoxSurvivorRuntime")
            speaker = speaker ~= nil and speaker.getCharacter ~= nil
                and speaker.getCharacter(self.survivorId) or nil
            if feed ~= nil and feed.conversation ~= nil and speaker ~= nil then
                feed.conversation(speaker, action.label, answer)
            end
        else
            self.feedback = actionReasonText(answer, "They did not answer.")
        end
        self:refreshActions()
        return
    end
    if id == "order" or id == "unstick" or id == "dismiss" or id == "work" then
        if id == "order" and (action.kind or id) == "return_to_base" then
            -- Sending somebody home has the same destination question as an
            -- invitation; a resident with two homes must not be sent to the
            -- first base just because no chooser was wired here.
            local home = service ~= nil and service.sendToBase or nil
            if openHomeChoice(self, "Send them home to which base?", home) then
                return
            end
        end
        local called, success, result
        if id == "work" then
            called, success, result = safeCall(service ~= nil and service.setBaseJobPreference,
                self.player, self.survivorId, action.work)
        elseif id == "unstick" then
            called, success, result = safeCall(service ~= nil and service.unstick,
                self.player, self.survivorId)
        else
            called, success, result = safeCall(service ~= nil and service.issueOrder,
                self.player, self.survivorId, action.kind or id)
        end
        if called and success == true then
            self.attentionStarted = true
            self.feedback = tostring(action.label or "Order") .. " - understood."
            if (action.kind or id) == "dismiss" then
                InteractionUI.close(self.playerNum)
                return
            end
        else
            self.feedback = actionReasonText(result)
        end
        local character = liveCharacter(self.survivorId)
        if character ~= nil then self:setCharacter(character) end
        self:refreshActions()
        return
    end
    local ok, result = false, "unavailable"
    local called, first, second = pcall(function()
        if id == "talk" and service ~= nil and service.talk ~= nil then
            return service.talk(self.player, self.survivorId)
        elseif id == "ask_needs" and service ~= nil and service.askNeeds ~= nil then
            return service.askNeeds(self.player, self.survivorId)
        elseif id == "joke" or id == "compliment" or id == "funny_face"
            or id == "insult" or id == "mock" or id == "blame"
            or id == "threaten" or id == "slap" then
            if service ~= nil and service.socialAct ~= nil then
                return service.socialAct(self.player, self.survivorId, id)
            end
        elseif id == "recruit" and service ~= nil and service.recruit ~= nil then
            return service.recruit(self.player, self.survivorId)
        elseif id == "invite_base" and service ~= nil and service.inviteToBase ~= nil then
            return service.inviteToBase(self.player, self.survivorId)
        elseif id == "move_in" and service ~= nil and service.moveIntoBase ~= nil then
            return service.moveIntoBase(self.player, self.survivorId)
        end
        return false, "unavailable"
    end)
    if called then ok, result = first == true, second
    else result = tostring(first) end
    if result == "opened" then return end
    -- A talk cooldown withholds the trust gain, not the conversation. Talk is
    -- the door to the questions, so closing it on a cooldown is why an owned
    -- survivor had nothing to ask.
    if id == "talk" and result == "cooldown" then
        self.attentionStarted = true
        self.feedback = "They have a minute. Ask them something."
        self.category = "ask"
        self:refreshActions()
        return
    end
    if ok then
        self.feedback = id == "talk" and "They are listening. Ask them something."
            or id == "recruit" and "They joined you."
            or id == "invite_base" and "They moved in with you."
            or id == "move_in" and "They will settle in at your base."
            or "They heard you."
        if id == "talk" or id == "joke" or id == "compliment"
            or id == "funny_face" or id == "insult" or id == "mock"
            or id == "blame" or id == "threaten" or id == "slap" then
            self.attentionStarted = true
            local feed = rawget(_G, "KnoxActivityFeed")
            local line = PLAYER_SOCIAL_LINES[id]
            if line ~= nil and feed ~= nil and feed.playerSays ~= nil then
                feed.playerSays(self.player, line)
            end
        end
        if id == "talk" then
            -- Talking opens the questions instead of repeating one sentence.
            self.category = "ask"
        end
        if id == "recruit" or id == "invite_base" or id == "move_in" then
            InteractionUI.close(self.playerNum)
            return
        end
    else
        self.feedback = actionReasonText(result)
        -- A work step is transient, so a player's word must not be dropped on
        -- it. The refusal is not a dead end: remember what was asked and repeat
        -- it until the step ends or the short window closes. Only conversation
        -- actions re-arm - a refused line or the talk opener - because they are
        -- safe to repeat and a delivered one clears the pending row first.
        if result == "work_step_finishing" and CONVERSATION_IDS[id] == true then
            self.pendingAction = { id = id, label = action.label, kind = action.kind,
                untilMs = nowMs() + 15000, nextAt = nowMs() + 700 }
        end
    end
    local character = liveCharacter(self.survivorId)
    if character ~= nil then self:setCharacter(character) end
    self:refreshActions()
end

local function interactionWindowSize(fontHeight,screenW,screenH)
    local scale=math.max(1,(tonumber(fontHeight) or 14)/14)
    local width,height=UILayout.fitRect(math.floor(WINDOW_WIDTH*scale),
        math.floor(WINDOW_HEIGHT*scale),0,0,screenW,screenH,10)
    return width,height,scale
end

function Window:new(playerNum, target, player)
    local width,height,scale=interactionWindowSize(getTextManager():getFontHeight(UIFont.Small),
        getPlayerScreenWidth(playerNum),getPlayerScreenHeight(playerNum))
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.player = player
    window.survivorId = target.id
    window.character = target.character
    window.name = target.name
    -- Ownership decides the whole tab set, so it is resolved once when the
    -- panel opens rather than guessed per page.
    window.owned = playerIsOwner(player, target.id)
    local tactics = tacticsOf(window)
    window.resident = window.owned and tactics ~= nil and tactics.mode == "base"
    -- Open on the category this relationship needs: orders for somebody who
    -- works for the player, conversation for a stranger.
    window.category = window.owned and "orders" or "friendly"
    window.jobPage = 1
    window.knoxName = tostring(target.name or "Survivor")

    window.feedback = nil
    window.uiScale = scale
    window:setTitle(UILayout.fitText(UIFont.Small, target.name,
        math.max(1, width - 80)))
    UILayout.bindInteractionWindow(window)
    return window
end

function InteractionUI.open(playerNum, target, player)
    if type(target) ~= "table" or target.id == nil or player == nil then return false end
    InteractionUI.close(playerNum)
    -- One Knox surface per player: the talk panel replaces a notebook, card or
    -- trade window, and any of those closes the conversation when it opens.
    if UILayout ~= nil and UILayout.claimSurface ~= nil then
        pcall(UILayout.claimSurface, playerNum, "talk", InteractionUI)
    end
    local window = Window:new(playerNum, target, player)
    window:initialise()
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    window:setX(getPlayerScreenLeft(playerNum) + math.max(0, (sw - window.width) / 2))
    window:setY(getPlayerScreenTop(playerNum) + math.max(0, sh - window.height - 20))
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
            window.attentionLease = window.attentionController.playerConversation
        end
        if not window.attentionStarted and ok and reason == "work_step_finishing" then
            window.attentionPending = true
            window.attentionPendingUntil = getTimestampMs() + 15000
            window.attentionController = runtime.getController(target.id)
            window.feedback = "Finishing the current step..."
            window:refreshActions()
        elseif not window.attentionStarted then
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
    if UILayout ~= nil and UILayout.releaseSurface ~= nil then
        pcall(UILayout.releaseSurface, key, "talk")
    end
    local window = windows[key]
    if window == nil then return false end
    windows[key] = nil
    window.closed = true
    if window.attentionStarted then
        window.attentionStarted = false
        local runtime = rawget(_G, "KnoxSurvivorRuntime")
        if runtime ~= nil and runtime.endPlayerConversation ~= nil and InteractionUI.ownsAttention(window) then
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


function InteractionUI.nearest(player)
    return candidateFor(player)
end

function InteractionUI.ownsAttention(window)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local owner = runtime ~= nil and runtime.getController ~= nil and runtime.getController(window.survivorId) or nil
    local lease = owner ~= nil and owner.playerConversation or nil
    return owner ~= nil and owner == window.attentionController and lease ~= nil
        and lease == window.attentionLease and lease.player == window.player
end

function InteractionUI.updatePendingAttention(window, now)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.getController == nil or runtime.beginPlayerConversation == nil
        or now == nil or now >= (window.attentionPendingUntil or 0)
        or runtime.getController(window.survivorId) ~= window.attentionController then return false end
    local ok, accepted, reason = safeCall(runtime.beginPlayerConversation,
        window.survivorId, window.player)
    if ok and accepted == true then
        window.attentionPending, window.attentionStarted, window.feedback = nil, true, nil
        window.attentionLease = window.attentionController.playerConversation
        window:refreshActions()
        return true
    end
    return ok and reason == "work_step_finishing"
end

function InteractionUI.update()
    local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    if now ~= nil and now < nextScanAt then return end
    if now ~= nil then nextScanAt = now + SCAN_INTERVAL_MS end
    local count = getNumActivePlayers ~= nil and tonumber(getNumActivePlayers()) or 1
    for playerNum = 0, math.max(0, math.min(3, (count or 1) - 1)) do
        local player = getSpecificPlayer ~= nil and getSpecificPlayer(playerNum) or nil
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
        end
        -- The aimed person is identified by the world and the context menu; the
        -- bottom strip below only names the key that would open them.
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
            if window.attentionPending then
                attentionOkay = playerAvailable and retainedRange and contact
                    and InteractionUI.updatePendingAttention(window, now)
            end
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
                        and lease == window.attentionLease
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
    nextScanAt = 0
end

if Events ~= nil then
    if Events.OnTick ~= nil and Events.OnTick.Add ~= nil then
        Events.OnTick.Add(InteractionUI.update)
    end
    if Events.OnGameStart ~= nil and Events.OnGameStart.Add ~= nil then
        Events.OnGameStart.Add(InteractionUI.reset)
    end
    if Events.OnResolutionChange ~= nil and Events.OnResolutionChange.Add ~= nil then
        -- Match Trade: close through the existing lease/focus handoff, then a
        -- reopened conversation is laid out for the new player viewport.
        Events.OnResolutionChange.Add(InteractionUI.reset)
    end
end

-- F TALK (isometric only)
-- The survival guide promised F for conversation, but no handler existed, so
-- the key did nothing in the isometric view. F now opens the ordinary talk
-- panel on the nearest survivor. It stands aside while a perspective session
-- owns the target (the crosshair surface is the pointer there) and while
-- another window is capturing input, so a typed F never opens a panel behind
-- the player's back.
local F_TALK_RADIUS = 2.5

local function fTalkBlockedByUI()
    if UIManager == nil or UIManager.getUI == nil then return false end
    local ok, blocked = pcall(function()
        local list = UIManager.getUI()
        for index = list:size() - 1, 0, -1 do
            local element = list:get(index)
            if element:isVisible() and (element:isCapture() or element:isWantKeyEvents()) then
                return true
            end
        end
        return false
    end)
    return ok and blocked == true
end

local function openTalkToNearest(player)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.nearestToSquare == nil
        or runtime.getCharacter == nil then return false end
    local id = runtime.nearestToSquare(player:getCurrentSquare(), F_TALK_RADIUS)
    if id == nil then return false end
    local character = runtime.getCharacter(id)
    if character == nil then return false end
    local view = rawget(_G, "KnoxSurvivorViewModel")
    local snapshot = view ~= nil and view.getSurvivor ~= nil
        and view.getSurvivor(id, player:getPlayerNum()) or nil
    return InteractionUI.open(player:getPlayerNum(), { id = id, character = character,
        name = snapshot ~= nil and snapshot.displayName or "Survivor" }, player)
end

local function onFTalkPressed(key)
    if key ~= Keyboard.KEY_F then return end
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.enabled ~= nil and not settings.enabled() then return end
    local layout = rawget(_G, "KnoxSurvivorUILayout")
    if layout ~= nil and layout.isPerspective ~= nil and layout.isPerspective() then return end
    if fTalkBlockedByUI() then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end
    local ok = pcall(openTalkToNearest, player)
    if not ok then return end
end

Events.OnKeyPressed.Add(onFTalkPressed)

return InteractionUI
