require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_CompanionVehicles"
require "KS_OrderCatalog"
require "KS_OrderSignals"

local CompanionService = rawget(_G, "KnoxCompanionService") or {}
_G.KnoxCompanionService = CompanionService
local orderSignalCooldowns = setmetatable({}, { __mode = "k" })
-- One session-scoped player command; individual duty directives remain the
-- durable owner and take precedence. No party leader or second route owner is
-- introduced, and reload retires this order safely.
local partyDestinations = {}
local nextPartyDestinationRevision = 0
-- Runtime-only slot and heading projection derived from the current recruited
-- roster. The controller remains the sole movement owner.
local partyFormationRuntime = {}
local lastPlayerVehicle = setmetatable({}, { __mode = "k" })
local PARTY_DESTINATION_TTL_HOURS = 1
local PARTY_HEADING_CONFIRM_DISTANCE = 1.5
if Events ~= nil and Events.OnGameStart ~= nil and Events.OnGameStart.Add ~= nil then
    Events.OnGameStart.Add(function()
        -- Lua may remain resident when returning to the main menu and loading
        -- another save; never carry this transient command across worlds.
        partyDestinations = {}
        nextPartyDestinationRevision = 0
        partyFormationRuntime = {}
        lastPlayerVehicle = setmetatable({}, { __mode = "k" })
    end)
end

local function signalOrder(player, survivorId, kind)
    local signals = rawget(_G, "KnoxOrderSignals")
    if signals == nil or signals.order == nil then return false end
    -- Delivery may already have played the leader's gesture. A successful
    -- recipient can still acknowledge it without replaying that gesture.
    if signals.acknowledge ~= nil then
        signals.acknowledge(player, KnoxSurvivorRuntime.getCharacter(survivorId))
    end
    -- Some party routes still resolve per survivor because each member can be
    -- in a different place. Keep that useful routing while coalescing the
    -- visible leader gesture and acknowledgements for one repeated order.
    local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    if now == nil then
        now = getGameTime ~= nil and getGameTime():getWorldAgeHours() * 3600000 or 0
    end
    local previous = player ~= nil and orderSignalCooldowns[player] or nil
    if previous ~= nil and previous.kind == kind and now >= previous.at
        and now - previous.at < 3000 then
        return false
    end
    local played = signals.order(player, kind, KnoxSurvivorRuntime.getCharacter(survivorId))
    if played and player ~= nil then
        orderSignalCooldowns[player] = { kind = kind, at = now }
    end
    return played
end

local TALK_GAIN = 8
local TALK_COOLDOWN_HOURS = 0.5
local INTERACTION_DISTANCE_SQUARED = 16
local syncCache = setmetatable({}, { __mode = "k" })

local TALK_LINES = {
    "Been keeping out of trouble?",
    "Found anywhere safe yet?",
    "Keep your voice down. Sound carries.",
    "If you find clean water, remember where it was.",
    "I haven't seen many living people lately.",
    "We should check our supplies before we move on.",
    "Doors first. Windows only if we have to.",
    "I could use a quiet night for once.",
    "Let me know if you need me to carry anything.",
    "We should keep an eye out for medicine.",
    "This place still feels too exposed.",
    "I'm good to keep moving when you are.",
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

-- Search-style orders are useful from more than the ground-selection menu
-- (Notebook, party shortcuts, and future controller callers may only provide
-- the order name).  Give those orders a small, bounded area around the person
-- instead of making every caller duplicate square/radius construction.  Point
-- and guard orders still require an explicit destination so an accidental
-- click cannot send a survivor somewhere arbitrary.
local SEARCH_DIRECTIVES = {
    loot_area = true, loot_corpses = true, find_food = true, find_water = true,
    find_medical = true, find_weapon = true, find_tools = true,
    clean_inventory = true,
}

local BASE_SUPPLY_ORDERS = {
    find_food = true,
    find_water = true,
    find_medical = true,
    find_weapon = true,
    find_tools = true,
    find_wood = true,
    find_materials = true,
    find_clothing = true,
    find_ammo = true,
    find_fuel = true,
}

local function isPlayerCompanion(player, survivorId)
    if player == nil or survivorId == nil then return false end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or KnoxPersistence.getCompanionIds == nil then return false end
    for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
        if tostring(id) == tostring(survivorId) then return true end
    end
    return false
end

local function defaultCompanionArea(player, survivorId, kind)
    if kind ~= "guard" and kind ~= "patrol_area" and kind ~= "patrol" then
        return nil
    end
    if not isPlayerCompanion(player, survivorId) then return nil end
    local character = KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.getCharacter ~= nil
        and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
    local square = character ~= nil and character:getCurrentSquare() or nil
    square = square or (player ~= nil and player:getCurrentSquare() or nil)
    if square == nil then return nil end
    local radius = kind == "guard" and 3 or 8
    return {
        kind = kind == "patrol" and "patrol_area" or kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

local function defaultSearchDirective(player, survivorId, kind)
    if not SEARCH_DIRECTIVES[kind] then return nil end
    local character = KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.getCharacter ~= nil
        and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
    local square = character ~= nil and character:getCurrentSquare() or nil
    square = square or (player ~= nil and player:getCurrentSquare() or nil)
    if square == nil then return nil end
    local radius = 12
    return {
        kind = kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

local function displayName(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    return name ~= "" and name or "Survivor"
end

local function playerSocialDisposition(playerId, survivorId)
    if KnoxPersistence.getPlayerSocialDisposition ~= nil then
        return KnoxPersistence.getPlayerSocialDisposition(playerId, survivorId)
    end
    -- Test fixtures and old hot-loaded worlds may not have the social
    -- extension yet. Preserve the existing safe recruitment behavior there.
    return "join"
end

local function socialRelation(playerId, survivorId)
    if KnoxPersistence.getPlayerRelationship ~= nil then
        return KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    end
    return nil
end

local function socialSpeech(character, survivorId, event, fallback, recognitionEvent, subjectId)
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local controller = runtime ~= nil and runtime.getController ~= nil and runtime.getController(survivorId) or nil
    local ticks = controller ~= nil and controller.currentTicks or nil
    if type(ticks) == "number" and ticks == ticks and ticks >= 0 and ticks < math.huge
        and dialogue ~= nil then
        local said, line
        if recognitionEvent ~= nil and dialogue.sayRecognition ~= nil then
            said, line = dialogue.sayRecognition(character, survivorId, "player:" .. tostring(subjectId),
                ticks, nil, recognitionEvent)
        elseif recognitionEvent == nil and dialogue.say ~= nil then
            said, line = dialogue.say(character, survivorId, event, ticks, 1800)
        end
        if said then return line end
    end
    KnoxActivityFeed.speak(character, fallback)
    return fallback
end

local function recordSocialEvent(playerId, survivorId, event)
    if KnoxPersistence.recordPlayerSocialEvent ~= nil then
        KnoxPersistence.recordPlayerSocialEvent(playerId, survivorId, event, worldAge())
    end
end

local function validateInteraction(player, survivorId, maximumDistanceSquared)
    if KnoxSurvivorRuntime.canInteract ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canInteract(survivorId)
        if not accepted then return nil, reason end
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local playerSquare = player ~= nil and player:getCurrentSquare() or nil
    local survivorSquare = character ~= nil and character:getCurrentSquare() or nil
    if player == nil or playerSquare == nil then
        return nil, "player_unavailable"
    end
    if character == nil or survivorSquare == nil then
        return nil, "survivor_unavailable"
    end
    if (character.isDead ~= nil and character:isDead())
        or (player.isDead ~= nil and player:isDead()) then
        return nil, "character_dead"
    end
    if playerSquare:getZ() ~= survivorSquare:getZ() then
        return nil, "too_far_away"
    end
    local dx = playerSquare:getX() - survivorSquare:getX()
    local dy = playerSquare:getY() - survivorSquare:getY()
    if dx * dx + dy * dy > (maximumDistanceSquared or INTERACTION_DISTANCE_SQUARED) then
        return nil, "too_far_away"
    end
    return character, "ready"
end

function CompanionService.getPlayerId(player)
    return KnoxPersistence.ensurePlayerId(player)
end

-- Read-only contact admission. No stored ledger, global position or merely
-- carried radio establishes delivery. The shared native bridge supplies normal
-- speech intelligibility; visual commands use the existing seven-tile gesture.
local function contactChannel(player, character)
    local ready, available = pcall(function()
        return player ~= nil and character ~= nil and not player:isDead()
            and not character:isDead() and not character:isAsleep()
            and player:getCurrentSquare() ~= nil and character:getCurrentSquare() ~= nil
    end)
    if ready and available then
        local bridge = rawget(_G, "KnoxJavaBridge")
        local heard, audible = pcall(function() return bridge:canHearOrder(player, character) end)
        if heard and audible == true then return true, "voice" end
        local seen, visible = pcall(function()
            local a, b = player:getCurrentSquare(), character:getCurrentSquare()
            return a:getZ() == b:getZ() and (a:getX()-b:getX())^2+(a:getY()-b:getY())^2 <= 49
                and character:CanSee(player) == true
        end)
        if seen and visible then return true, "visual" end
    end
    return false, "order_not_delivered"
end

-- Whether this person will take an order right now, read from the trust the
-- same ledger already holds. A target only turns hostile when an act is aimed at
-- them; a bystander who has watched enough reaches the same place through
-- witnessing, so both arrive at one answer. No new field, no second score.
function CompanionService.orderWillingness(survivorId, playerId)
    if survivorId == nil or playerId == nil then return nil end
    if KnoxPersistence.getPlayerRelationship == nil then return nil end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if type(relation) ~= "table" then return nil end
    return CompanionService.witnessLadder(relation.trust)
end

function CompanionService.orderContact(player, survivorId)
    local owner = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if owner == nil or affiliation == nil or affiliation.kind ~= "player"
        or affiliation.ownerId ~= owner then return false, "not_your_survivor" end
    -- Willingness is asked before reachability: a person who has decided about
    -- you does not become willing because you managed to shout loud enough.
    local willingness = CompanionService.orderWillingness(survivorId, owner)
    if willingness == "hostile" then return false, "hostile" end
    if willingness == "wary" then return false, "unwilling" end
    if KnoxSurvivorRuntime.canAcceptOrders ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canAcceptOrders(survivorId)
        if not accepted then return false, reason end
    end
    return contactChannel(player, KnoxSurvivorRuntime.getCharacter(survivorId))
end

-- Batch receipts live only for one synchronous party dispatch. Each recipient
-- still needs its own contact check; one real utterance/gesture can reach several.
local ORDER_SPEECH = {
    medical_help = "I need medical help", enable_auto_medical = "Help us with injuries when you can",
    disable_auto_medical = "Wait until I ask for medical help",
    allow_climbing = "Vault and climb when needed", disallow_climbing = "Avoid vaulting and climbing",
    allow_doors = "Use doors and windows", disallow_doors = "Leave doors and windows alone",
    enable_auto_equipment = "Improve your gear when you can", disable_auto_equipment = "Keep your current gear",
}
function CompanionService.deliverOrder(player, survivorId, kind, batch, detail)
    local ready, channel = CompanionService.orderContact(player, survivorId)
    local function receiptContact()
        if KnoxPersistence.rememberSurvivorPlayerContact ~= nil then
            local square = player:getCurrentSquare()
            KnoxPersistence.rememberSurvivorPlayerContact(survivorId, CompanionService.getPlayerId(player),
                {x=square:getX(),y=square:getY(),z=square:getZ(),atHours=worldAge(),source=channel})
        end
        return true, channel
    end
    if ready then
        local receipt = batch or {}
        if channel == "voice" then
            if receipt.voice then return receiptContact() end
            local label = ORDER_SPEECH[kind] or (KnoxOrderCatalog ~= nil and KnoxOrderCatalog.label ~= nil
                and KnoxOrderCatalog.label(kind, tostring(kind)) or tostring(kind))
            if detail ~= nil then label = label .. ": " .. tostring(detail) end
            local sent = pcall(function() player:Say(label .. ".") end)
            if sent then receipt.voice = true; return receiptContact() end
        else
            local signals = rawget(_G, "KnoxOrderSignals")
            if receipt.visual then return receiptContact() end
            if signals ~= nil and signals.send ~= nil and signals.send(player, kind) then
                receipt.visual = true; return receiptContact()
            end
        end
        channel = "order_not_delivered"
    end
    -- A refusal is spoken, not a silent failure to reach them, and it says who
    -- is refusing rather than blaming the radio.
    if channel == "unwilling" or channel == "hostile" then
        local dialogue = rawget(_G, "KnoxSurvivorDialogue")
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if channel == "unwilling" and dialogue ~= nil and dialogue.say ~= nil and character ~= nil then
            dialogue.say(character, survivorId, "order_refused_wary",
                getTimestamp ~= nil and getTimestamp() or 0, 1800)
        end
        if KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
            KnoxActivityFeed.event(channel == "hostile"
                and displayName(survivorId) .. " has no intention of taking your orders."
                or displayName(survivorId) .. " will not take an order from you right now.")
        end
        return false, channel
    end
    if channel == "order_not_delivered" and KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("No contact with " .. displayName(survivorId) .. ". Existing orders continue.")
    end
    return false, channel
end

function CompanionService.rememberCommitment(player, survivorId)
    if KnoxPersistence.rememberObserverKnowledge == nil then return end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil then return end
    KnoxPersistence.rememberObserverKnowledge(CompanionService.getPlayerId(player), survivorId,
        "commitment", {role=duty.mode == "companion" and "companion" or (duty.mode == "base" and "resident" or "independent"),
        duty=duty, order=duty.order}, worldAge())
end

function CompanionService.resolvePlayer(playerId)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and CompanionService.getPlayerId(player) == playerId then
            return player
        end
    end
    return nil
end

function CompanionService.getCompanionIds(player)
    local playerId = CompanionService.getPlayerId(player)
    return playerId ~= nil and KnoxPersistence.getCompanionIds(playerId) or {}
end

-- Effective tactical settings for one survivor, read from the durable fields
-- the setters above write (duty + policies). Menus ask this instead of
-- re-deriving a default of their own, so the wheel, the right-click menu and
-- the Crew tab cannot disagree about what is currently set for a person.
-- Returns nil when the survivor has no durable record, never a guessed state.
local TACTIC_DEFAULTS = {
    order = "follow",
    stance = "defensive",
    formation = "paired",
    spacing = 2,
    weapon = "auto",
    work = "auto",
}

function CompanionService.survivorTactics(survivorId)
    if type(survivorId) ~= "string" or survivorId == "" then return nil end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getSurvivorDuty == nil then return nil end
    -- Duty reads create a record for an unknown id, so a menu asking about a
    -- stale or foreign survivor must not invent one; existence is checked on
    -- the read-only accessor first.
    if persistence.isSurvivorAlive ~= nil
        and persistence.isSurvivorAlive(survivorId) ~= true then
        return nil
    end
    local duty = persistence.getSurvivorDuty(survivorId)
    if duty == nil then return nil end
    local policies = persistence.getSurvivorPolicies ~= nil
        and persistence.getSurvivorPolicies(survivorId) or nil
    policies = type(policies) == "table" and policies or {}
    -- Door handling has a sandbox default that the persisted policy may not
    -- set; resolve it here once so every caller reads the same answer.
    local doors = policies.allowDoorOpening
    if doors == nil then
        local settings = rawget(_G, "KnoxSettings")
        doors = not (settings ~= nil and settings.allowSurvivorDoorWindowOpening ~= nil
            and settings.allowSurvivorDoorWindowOpening() == false)
    end
    local spacing = math.floor(tonumber(duty.followerSpacing) or TACTIC_DEFAULTS.spacing)
    if spacing < 1 then spacing = 1 elseif spacing > 3 then spacing = 3 end
    return {
        mode = duty.mode,
        order = duty.order or TACTIC_DEFAULTS.order,
        stance = duty.combatStance or TACTIC_DEFAULTS.stance,
        formation = duty.followerFormation or TACTIC_DEFAULTS.formation,
        spacing = spacing,
        climbing = policies.allowClimbing ~= false,
        doors = doors == true,
        weapon = policies.weaponPreference or TACTIC_DEFAULTS.weapon,
        loot = policies.autoLoot == true,
        equipment = policies.autoEquipment ~= false,
        medical = policies.autoMedical ~= false,
        lootRuns = duty.allowLootRuns == true,
        work = duty.jobPreference or TACTIC_DEFAULTS.work,
    }
end

-- The settings every companion currently shares. A mixed setting is simply
-- absent from the result, so a menu marks a choice only when the whole party
-- really has it instead of showing the first member's value for everyone.
-- Returns (commonSettings, membersRead, membersOwned).
function CompanionService.commonTactics(player)
    local ids = CompanionService.getCompanionIds(player) or {}
    local common, read = nil, 0
    for _, survivorId in ipairs(ids) do
        local values = CompanionService.survivorTactics(survivorId)
        if values ~= nil then
            read = read + 1
            if common == nil then
                common = {}
                for key, value in pairs(values) do common[key] = value end
            else
                for key, value in pairs(common) do
                    if values[key] ~= value then common[key] = nil end
                end
            end
        end
    end
    return common or {}, read, #ids
end

local function playerPartyMemberIds(playerId)
    local ids = {}
    if type(playerId) ~= "string" or playerId == ""
        or KnoxPersistence.getCompanionIds == nil then
        return ids
    end
    for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(id) or nil
        -- Follow is the party-travel role. Hold, Relax, base duty, and any
        -- explicit per-person directive remain authoritative exclusions.
        if duty ~= nil and duty.mode == "companion"
            and (duty.order == nil or duty.order == "follow")
            and duty.directive == nil then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

local function partyDirectionComponent(value)
    value = tonumber(value) or 0
    if value > 0.35 then return 1 end
    if value < -0.35 then return -1 end
    return 0
end

function CompanionService.getPlayerPartyFormationContext(playerId, player)
    if type(playerId) ~= "string" or playerId == "" then return nil end
    if player ~= nil then
        local deadOk, dead = pcall(function() return player:isDead() end)
        if deadOk and dead == true then
            partyFormationRuntime[playerId] = nil
            if CompanionService.cancelPartyDestination ~= nil then
                CompanionService.cancelPartyDestination(player)
            end
            return nil
        end
    end
    local memberIds = playerPartyMemberIds(playerId)
    local state = partyFormationRuntime[playerId]
    if state == nil then
        state = {
            slots = {}, forwardX = nil, forwardY = nil,
            pendingHeadingDistance = 0,
        }
        partyFormationRuntime[playerId] = state
    end
    local current = {}
    for _, id in ipairs(memberIds) do current[tostring(id)] = true end
    local used = {}
    for id, slot in pairs(state.slots) do
        if not current[id] then
            state.slots[id] = nil
        else
            used[slot] = true
        end
    end
    for _, id in ipairs(memberIds) do
        local key = tostring(id)
        if state.slots[key] == nil then
            local slot = 1
            while used[slot] do slot = slot + 1 end
            state.slots[key], used[slot] = slot, true
        end
    end

    local x, y = nil, nil
    if player ~= nil then
        local ok, px, py = pcall(function() return player:getX(), player:getY() end)
        if ok and tonumber(px) ~= nil and tonumber(py) ~= nil then
            x, y = tonumber(px), tonumber(py)
        end
    end
    if state.forwardX == nil or state.forwardY == nil then
        local fx, fy = 0, 1
        if player ~= nil then
            pcall(function()
                fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY()
            end)
        end
        state.forwardX = partyDirectionComponent(fx)
        state.forwardY = partyDirectionComponent(fy)
        if state.forwardX == 0 and state.forwardY == 0 then state.forwardY = 1 end
        state.lastSampleX, state.lastSampleY = x, y
    elseif x ~= nil and y ~= nil then
        local lastX, lastY = state.lastSampleX, state.lastSampleY
        if lastX == nil or lastY == nil then
            state.lastSampleX, state.lastSampleY = x, y
        else
            local dx, dy = x - lastX, y - lastY
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 0.1 then
                local fx, fy = partyDirectionComponent(dx), partyDirectionComponent(dy)
                if fx == state.forwardX and fy == state.forwardY then
                    state.pendingHeadingX, state.pendingHeadingY = nil, nil
                    state.pendingHeadingDistance = 0
                elseif fx ~= 0 or fy ~= 0 then
                    if state.pendingHeadingX == fx and state.pendingHeadingY == fy then
                        state.pendingHeadingDistance = state.pendingHeadingDistance + distance
                    else
                        state.pendingHeadingX, state.pendingHeadingY = fx, fy
                        state.pendingHeadingDistance = distance
                    end
                    if state.pendingHeadingDistance >= PARTY_HEADING_CONFIRM_DISTANCE then
                        state.forwardX, state.forwardY = fx, fy
                        state.pendingHeadingX, state.pendingHeadingY = nil, nil
                        state.pendingHeadingDistance = 0
                    end
                end
                state.lastSampleX, state.lastSampleY = x, y
            end
        end
    end
    local slots = {}
    local loadedMemberCount = 0
    for _, id in ipairs(memberIds) do
        slots[tostring(id)] = state.slots[tostring(id)]
        local character = KnoxSurvivorRuntime ~= nil
            and KnoxSurvivorRuntime.getCharacter ~= nil
            and KnoxSurvivorRuntime.getCharacter(id) or nil
        if character ~= nil then
            local okSquare, square = pcall(function() return character:getCurrentSquare() end)
            if okSquare and square ~= nil then loadedMemberCount = loadedMemberCount + 1 end
        end
    end
    return {
        memberIds = memberIds,
        slots = slots,
        slot = slots[tostring(memberIds[1])],
        memberCount = math.max(1, loadedMemberCount),
        forwardX = state.forwardX or 0,
        forwardY = state.forwardY or 1,
    }
end

function CompanionService.removePlayerPartyFormationMember(playerId, survivorId)
    if type(playerId) ~= "string" or survivorId == nil then return false end
    local state = partyFormationRuntime[playerId]
    if state == nil then return false end
    local key = tostring(survivorId)
    local existed = state.slots[key] ~= nil
    state.slots[key] = nil
    return existed
end

local function hasPlayerAffiliation(survivorId)
    local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
        and KnoxPersistence.getSurvivorAffiliation(survivorId) or nil
    return affiliation ~= nil and affiliation.kind == "player"
end

-- Social admission must honor the same protected-team boundary as combat.
-- Keep legacy hostility history; it is not an executable fight while affiliated.
function CompanionService.isSociallyHostileToPlayer(survivorId, playerId)
    return not hasPlayerAffiliation(survivorId)
        and KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
end

function CompanionService.talk(player, survivorId)
    local character, availability = validateInteraction(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    if character == nil or playerId == nil then
        return false, availability
    end
    local social = playerSocialDisposition(playerId, survivorId)
    local protectedTeam = hasPlayerAffiliation(survivorId)
    if not protectedTeam and social == "attack_on_sight" then
        KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        socialSpeech(character, survivorId, "player_attack_warning", "Back away.")
        KnoxActivityFeed.event("A survivor attacked without warning.")
        return false, "hostile"
    end
    if CompanionService.isSociallyHostileToPlayer(survivorId, playerId) then return false, "hostile" end
    local attentive, attentionReason = KnoxSurvivorRuntime.beginPlayerConversation(survivorId, player)
    if not attentive then
        KnoxActivityFeed.speak(character, attentionReason == "danger"
            and "Not safe to talk here." or "Give me a moment to finish this.")
        return false, attentionReason
    end
    local previousRelation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local previousMeetings = previousRelation == nil and 0 or tonumber(previousRelation.meetings)
    local previousTrust = previousRelation ~= nil and (tonumber(previousRelation.trust) or 30) or 30
    local relation, result = KnoxPersistence.recordPlayerConversation(
        playerId,
        survivorId,
        TALK_GAIN,
        worldAge(),
        TALK_COOLDOWN_HOURS
    )
    if relation == nil then
        KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
        return false, result
    end
    if result == "cooldown" then
        -- A reward cooldown is not the end of the encounter. Keep the
        -- admitted attention lease so the player can ask about needs, trade,
        -- or choose another response. Danger/needs/expiry still own release.
        KnoxActivityFeed.speak(character, "Give me a minute.")
        return false, result
    end
    -- The meeting count picks the line, and the pair remembers the last one so
    -- the same sentence never lands twice in a row.
    local lineIndex = ((relation.meetings - 1) % #TALK_LINES) + 1
    if TALK_LINES[lineIndex] == relation.lastTalkLine then
        lineIndex = (lineIndex % #TALK_LINES) + 1
    end
    local line = TALK_LINES[lineIndex]
    relation.lastTalkLine = line
    KnoxActivityFeed.event("Talked to " .. displayName(survivorId) .. ".")
    if KnoxActivityFeed.reputation ~= nil then
        KnoxActivityFeed.reputation(character, (tonumber(relation.trust) or previousTrust) - previousTrust)
    end
    if protectedTeam then
        socialSpeech(character, survivorId, "player_talk", line)
    elseif social == "lure" then
        if (tonumber(relation.lureAttempts) or 0) == 0 then
            recordSocialEvent(playerId, survivorId, "lure_attempt")
            socialSpeech(character, survivorId, "player_lure",
                "I know a place nearby. Come on, I can show you.")
        else
            KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
            socialSpeech(character, survivorId, "player_attack_warning", "You should have kept walking.")
            KnoxActivityFeed.event("A survivor tried to lure you into an ambush.")
            KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
            if KnoxSurvivorRuntime.beginRobbery ~= nil then
                KnoxSurvivorRuntime.beginRobbery(
                    survivorId, player, math.floor(worldAge() * 3600)
                )
            end
            return false, "hostile"
        end
    elseif social == "warn_then_attack" then
        -- Gunners warn once, then shoot. The first talk is the warning;
        -- coming back starts a fight. They never lure or rob: the gun IS
        -- the conversation.
        if previousRelation ~= nil and previousRelation.warnIssued == true then
            KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
            socialSpeech(character, survivorId, "player_attack_warning", "I warned you.")
            KnoxActivityFeed.event("A gunner opened fire after warning you off.")
            KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
            return false, "hostile"
        end
        if previousRelation ~= nil then previousRelation.warnIssued = true end
        socialSpeech(character, survivorId, "player_attack_warning",
            "Back off. Next time I do not talk first.")
    elseif social == "volatile" then
        -- Volatile survivors can hold a conversation, then decide that the
        -- meeting itself was a threat. Hostility is persisted before the
        -- attention lease ends so the existing combat owner can retaliate.
        KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        socialSpeech(character, survivorId, "player_attack_warning", "Do not come any closer.")
        KnoxActivityFeed.event("The conversation turned hostile.")
        KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
        return false, "hostile"
    else
        local stillWarmingUp = social == "warm_up"
            and (tonumber(relation.meetings) or 0) < 2
            and (tonumber(relation.recruitmentAttempts) or 0) < 2
        local event = stillWarmingUp and "player_warm_up"
            or social == "independent" and "player_independent"
            or "player_talk"
        local recognitionEvent = nil
        if event == "player_talk" and previousMeetings ~= nil and previousMeetings == previousMeetings
            and previousMeetings >= 0 and previousMeetings < math.huge then
            local seen, visible = pcall(function() return character:CanSee(player) end)
            if seen and visible == true then
                recognitionEvent = previousMeetings == 0 and "player_first" or "player_known"
            end
        end
        socialSpeech(character, survivorId, event, line, recognitionEvent, playerId)
    end
    print(
        "[KnoxSurvivors][Companions] talk survivor=" .. survivorId
            .. " player=" .. playerId
            .. " meetings=" .. tostring(relation.meetings)
            .. " trust=" .. tostring(relation.trust)
    )
    return true, relation
end

function CompanionService.askNeeds(player, survivorId)
    local character, availability = validateInteraction(player, survivorId)
    if character == nil then return false, availability end
    local bridge = rawget(_G, "KnoxJavaBridge")
    local reached, heard = pcall(function() return bridge:canHearOrder(player, character) end)
    local answered, replyHeard = pcall(function() return bridge:canHearOrder(character, player) end)
    if not reached or heard ~= true or not answered or replyHeard ~= true then
        KnoxActivityFeed.event("Cannot discuss needs without clear contact.")
        return false, "order_not_delivered"
    end
    local spoken = pcall(function() player:Say("How are you holding up?") end)
    if not spoken then
        KnoxActivityFeed.event("Could not ask about their needs. Try speaking to them again.")
        return false, "order_not_delivered"
    end
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs == nil then
        pcall(require, "KS_SurvivorNeeds")
        needs = rawget(_G, "KnoxSurvivorNeeds")
    end
    if needs == nil then return false, "needs_unavailable" end
    local state = needs.snapshot(character)
    local line
    if state.bleedingParts > 0 then
        line = "I'm bleeding. I need something clean for it."
    elseif state.health < 65 then
        line = "I'm hurt. I could use a safe place to recover."
    elseif state.thirst >= needs.thresholds.thirst then
        line = needs.findBestWater(character, false) ~= nil
            and "I'm thirsty, but I have water." or "I need clean water."
    elseif state.hunger >= needs.thresholds.hunger then
        line = needs.findBestFood(character) ~= nil
            and "I'm hungry. I have something to eat." or "I need food."
    elseif state.fatigue >= needs.thresholds.fatigue then
        line = "I need somewhere safe to sleep."
    elseif state.endurance <= needs.thresholds.lowEndurance then
        line = "I just need a minute to catch my breath."
    else
        -- Mood and vice expression: survivors name what they cannot fix
        -- alone, exactly like a player would call it out.
        local motive = needs.smokeMotive ~= nil
            and needs.smokeMotive(character) or false
        local hasSmoke = needs.findSmokeItem ~= nil
            and needs.findSmokeItem(character) ~= nil or false
        if motive and not hasSmoke then
            line = "I could really use a smoke. Got any cigarettes?"
        elseif motive then
            line = "I am going to step aside for a smoke."
        else
            local stressed, unhappy = 0, 0
            pcall(function()
                local moodles = character:getMoodles()
                if moodles ~= nil and MoodleType ~= nil then
                    stressed = tonumber(moodles:getMoodleLevel(MoodleType.STRESS)) or 0
                    unhappy = tonumber(moodles:getMoodleLevel(MoodleType.UNHAPPY)) or 0
                end
            end)
            if unhappy >= 2 then
                line = "I am feeling low. I could use some company or a drink."
            elseif stressed >= 2 then
                line = "I am wound up. I need a quiet minute."
            else
                line = "I'm all right for now."
            end
        end
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    local ok, heard = pcall(function() return bridge:canHearOrder(character, player) end)
    if ok and heard == true and KnoxPersistence.rememberObserverKnowledge ~= nil then
        KnoxPersistence.rememberObserverKnowledge(CompanionService.getPlayerId(player), survivorId,
            "report", {state=state, line=line}, worldAge())
    end
    KnoxActivityFeed.speak(character, line)
    return true, line
end

function CompanionService.askNeedsAll(player)
    local answered, firstFailure = 0, nil
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.askNeeds(player, survivorId)
        if not success and firstFailure == nil then firstFailure = reason end
        answered = answered + (success and 1 or 0)
    end
    if answered > 0 then
        KnoxActivityFeed.event("Party needs check.")
    end
    return answered > 0, answered, answered > 0 and "checked" or firstFailure or "no_companions"
end

-- Questions a survivor can actually answer, used by the Talk panel's Ask tab.
-- Every answer is composed from state that really exists: the clock, the
-- weather, their affiliation, their group, their own body and the encounter
-- history already recorded in their ledger. Asking never moves trust, so a
-- player cannot farm standing by interrogating somebody about the weather.
local ASK_TOPICS = { day = true, home = true, group = true, health = true,
    need = true, travels = true, standing = true }
local ASK_QUESTIONS = {
    day = "How's the day treating you?",
    home = "Where are you staying?",
    group = "Who are you with?",
    health = "How are you holding up?",
    need = "What do you need?",
    travels = "What have you seen or heard out there?",
    standing = "Where do we stand?",
}
-- Group-home wording (design/SOCIETY_AND_AUTONOMY.md, group-home feedback).
-- The keys are the reasons `groupHomeAuthorization` itself returns, so the
-- refusal said in conversation is always the refusal the write boundary gives.
local GROUP_HOME_LINES = {
    requires_2_members = "We still need people.",
    leader_unavailable = "We still need people.",
    mobile_group = "We are not staying here yet.",
    no_residents = "We are not staying here yet.",
    beds_unverified = "We are not staying here yet.",
    defence_unverified = "We cannot defend this place yet.",
    provisions_food_short = "We need food.",
    provisions_water_short = "We need water.",
    provisions_unreadable = "Our stores are unverified.",
}

local function groupHomeLine(reason)
    local key = tostring(reason or "")
    local line = GROUP_HOME_LINES[key]
    if line ~= nil then return line end
    if key:find("food", 1, true) ~= nil then return "We need food." end
    if key:find("water", 1, true) ~= nil then return "We need water." end
    if key:find("provisions", 1, true) == 1 then return "Our stores are unverified." end
    return nil
end

local STORAGE_PROBLEM_LINES = {
    full = "Our stores are full and there is still a haul in somebody's pack.",
    filtered = "The shelves will not take what we are carrying.",
    unreachable = "We cannot get to our own storage.",
    unavailable = "The storage is right there and we cannot use it.",
    no_storage = "Nobody has set up storage at our base yet.",
}

local function clockHour()
    local hour = nil
    pcall(function() hour = tonumber(getGameTime():getHour()) end)
    return hour
end

local function weatherLine()
    local raining, snowy = false, false
    pcall(function()
        local climate = getClimateManager()
        raining = climate:isRaining() == true
        snowy = climate:isSnowing() == true
    end)
    if raining then return "The rain makes every step loud." end
    if snowy then return "Snow covers the noise, which cuts both ways." end
    return nil
end

local function answerDay()
    local hour = clockHour()
    local text = "Hard to keep track of time lately."
    if hour ~= nil then
        if hour < 5 then
            text = "Middle of the night. I keep my back to a wall."
        elseif hour < 11 then
            text = "Morning. The light is on my side for a few hours."
        elseif hour < 15 then
            text = "Afternoon. It is a long walk to dark from here."
        elseif hour < 19 then
            text = "Evening. I want four walls and a door before it gets dark."
        else
            text = "Late. Anything out there hears you before it sees you."
        end
    end
    local weather = weatherLine()
    return weather ~= nil and (text .. " " .. weather) or text
end

local function answerHome(survivorId, playerId)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if type(affiliation) ~= "table" then
        return "No walls of my own. I move when I have to."
    end
    if affiliation.kind == "player" then
        local base = affiliation.baseId ~= nil and KnoxPersistence.getBase ~= nil
            and KnoxPersistence.getBase(affiliation.baseId) or nil
        if base ~= nil and base.ownerKind == "player"
            and base.ownerId == playerId then
            local manager = rawget(_G, "KnoxBaseManager")
            local status = manager ~= nil and manager.homeStatus ~= nil
                and manager.homeStatus(base, playerId) or nil
            local name = tostring(base.name or "The base")
            if status == nil or manager.standingOrderText == nil then
                return "I stay at " .. name .. ". I cannot read the house from here."
            end
            local intent = KnoxPersistence.getBaseIntent ~= nil
                and KnoxPersistence.getBaseIntent(base.id) or nil
            local catalog = rawget(_G, "KnoxBaseContextMenu")
            local labels = catalog ~= nil and catalog.BASE_INTENT_LABELS or nil
            local label = intent ~= nil
                and ((labels ~= nil and labels[intent]) or intent) or nil
            return manager.standingOrderText(label, status, name)
        end
        return "I am with you. That is the plan as long as it holds."
    end
    -- A group home answers through the transaction's own authorization, so a
    -- survivor can never claim a home the write boundary would refuse, and a
    -- refusal can never appear for a state it would accept.
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(survivorId) or nil
    if group ~= nil and group.factionId == nil
        and KnoxPersistence.groupHomeAuthorization ~= nil then
        local authorized, reason = KnoxPersistence.groupHomeAuthorization(group.id, 0)
        if authorized ~= nil then
            local name = authorized.base ~= nil and tostring(authorized.base.name or "") or ""
            if name ~= "" then return "We are staying here at " .. name .. "." end
            return "We are staying here."
        end
        local line = groupHomeLine(reason)
        if line ~= nil then return line end
    end
    if affiliation.baseId ~= nil then
        local base = KnoxPersistence.getBase(affiliation.baseId)
        local name = base ~= nil and tostring(base.name or "") or ""
        if name ~= "" then
            return "I stay at " .. name .. ". Better than the open road."
        end
        return "We hold a place down the road. Not home, but it is walls."
    end
    local faction = KnoxPersistence.getFactionForSurvivor ~= nil
        and KnoxPersistence.getFactionForSurvivor(survivorId) or nil
    if faction ~= nil then
        return "No fixed address. I run with " .. tostring(faction.name or "my people") .. "."
    end
    return "Nowhere. A house just makes you a target if you cannot hold it."
end

-- Exported for the offline fixture, like the standing answer beside it.
CompanionService.answerHome = answerHome

local function answerGroup(survivorId)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if type(affiliation) == "table" and affiliation.kind == "player" then
        return "I am with you. That is enough for now."
    end
    local faction = KnoxPersistence.getFactionForSurvivor ~= nil
        and KnoxPersistence.getFactionForSurvivor(survivorId) or nil
    if faction ~= nil then
        local count = type(faction.memberIds) == "table" and #faction.memberIds or 0
        if count > 1 then
            return tostring(count) .. " of us under "
                .. tostring(faction.name or "one name") .. "."
        end
        return "It is just " .. tostring(faction.name or "me") .. " most days."
    end
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(survivorId) or nil
    if type(group) == "table" and type(group.memberIds) == "table"
        and #group.memberIds > 1 then
        return "Travelling with " .. tostring(#group.memberIds) .. " others. It is temporary."
    end
    return "On my own. Fewer people, fewer arguments."
end

local function statValue(character, stat)
    local value = nil
    pcall(function() value = tonumber(character:getStats():get(stat)) end)
    return value
end

local function answerHealth(character)
    -- An observed bite is reported before an ache. The shared legacy band reads
    -- real bite wounds, without inferring them from systemic infection.
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs ~= nil and needs.infectionBand ~= nil then
        local ok, band = pcall(needs.infectionBand, character)
        if ok and band == "bitten" then
            return "I got bit. I am not going to pretend it is nothing."
        end
    end
    local health = nil
    pcall(function() health = tonumber(character:getHealth()) end)
    if health ~= nil and health < 35 then
        return "Not good. I am hurt and I need to sit down."
    end
    local hunger = statValue(character, CharacterStat.HUNGER)
    if hunger ~= nil and hunger > 0.75 then
        return "Hungry. I have been putting it off too long."
    end
    local thirst = statValue(character, CharacterStat.THIRST)
    if thirst ~= nil and thirst > 0.75 then
        return "Thirsty. I would trade almost anything for clean water."
    end
    local fatigue = statValue(character, CharacterStat.FATIGUE)
    if fatigue ~= nil and fatigue > 0.85 then
        return "Tired. I have been awake longer than I should."
    end
    return "Still standing. That is the whole report."
end

local function answerNeed(character, survivorId)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if type(affiliation) == "table" and affiliation.baseId ~= nil
        and KnoxPersistence.getBaseStorageProblems ~= nil then
        local problems = KnoxPersistence.getBaseStorageProblems(affiliation.baseId)
        local first = problems[1]
        local cause = first ~= nil and first.cause ~= nil and tostring(first.cause) or nil
        if cause ~= nil and STORAGE_PROBLEM_LINES[cause] ~= nil then
            return STORAGE_PROBLEM_LINES[cause]
        end
    end
    local health = nil
    pcall(function() health = tonumber(character:getHealth()) end)
    if health ~= nil and health < 50 then return "A medic. Soon." end
    local hunger = statValue(character, CharacterStat.HUNGER)
    if hunger ~= nil and hunger > 0.6 then return "Food. Anything with calories in it." end
    local thirst = statValue(character, CharacterStat.THIRST)
    if thirst ~= nil and thirst > 0.6 then return "Water. Clean water." end
    return "Nothing right now. Ask me again after dark."
end

-- Only recorded encounters are retold. The wording comes from the dialogue
-- owner's recount formatter, so a spoken memory and the campfire version of
-- the same ledger entry cannot disagree, and an empty ledger is honest. A
-- hearsay entry keeps the name of the person who told them, so a second-hand
-- event is never passed off as something they saw themselves.
local function answerTravels(survivorId)
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    local lines = {}
    if dialogue and dialogue.recountLines then
        local ok, recorded = pcall(dialogue.recountLines, survivorId)
        if ok and type(recorded) == "table" then
            for _, fact in ipairs(recorded) do
                if type(fact) == "string" and fact ~= "" then lines[#lines + 1] = fact end
            end
        end
    end
    local event = "ask_travels_history"
    if #lines == 0 then
        event = "ask_travels_unknown"
        lines = {"Nothing worth telling. Not yet.", "I haven't got any news I can vouch for.",
            "I don't know enough to send you chasing rumors.", "Nothing I can tell you for certain.",
            "No news from me. I'd rather say that than guess.", "I haven't heard anything I can trust."}
    end
    if dialogue and dialogue.chooseLine then
        local line, reset = dialogue.chooseLine(survivorId, event, lines, math.floor(worldAge() * 3600))
        return line, {event=event, line=line, reset=reset}
    end
    return lines[1]
end

local ASK_ANSWERS = {
    day = function(_, _) return answerDay() end,
    standing = function(_, survivorId, playerId)
        return CompanionService.answerStanding(survivorId, playerId)
    end,
    home = function(_, survivorId, playerId) return answerHome(survivorId, playerId) end,
    group = function(_, survivorId) return answerGroup(survivorId) end,
    health = function(character) return answerHealth(character) end,
    need = function(character, survivorId) return answerNeed(character, survivorId) end,
    travels = function(_, survivorId) return answerTravels(survivorId) end,
}

function CompanionService.askAbout(player, survivorId, topic)
    if type(topic) ~= "string" or ASK_TOPICS[topic] ~= true then
        return false, "unknown_question"
    end
    local character, availability = validateInteraction(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    if character == nil or playerId == nil then return false, availability end
    if CompanionService.isSociallyHostileToPlayer(survivorId, playerId) then
        return false, "hostile"
    end
    -- A question needs the same clear contact an order does; asking through a
    -- wall would answer with knowledge that was never spoken.
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil and bridge.canHearOrder ~= nil then
        local reached, heard = pcall(function() return bridge:canHearOrder(player, character) end)
        if not reached or heard ~= true then return false, "too_far_away" end
    end
    local question = ASK_QUESTIONS[topic]
    if question ~= nil then
        pcall(function() player:Say(question) end)
        local feed = rawget(_G, "KnoxActivityFeed")
        if feed ~= nil and feed.playerSays ~= nil then
            feed.playerSays(player, question)
        end
    end
    local answer, variation = ASK_ANSWERS[topic](character, survivorId, playerId)
    local spoken = socialSpeech(character, survivorId, "player_ask_" .. topic, answer)
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if variation and spoken == answer and dialogue and dialogue.rememberLine then
        dialogue.rememberLine(survivorId, variation.event, variation.line, variation.reset)
    end
    return true, answer
end

-- Sims-style social menu. Trust deltas run through the shared reputation
-- ledger; emotes use only vanilla radial-menu keys. Hostile acts on a
-- stranger with low trust can turn them hostile, exactly like a bad lure.
local SOCIAL_ACTS = {
    healed = { trust = 5, cooldown = 1, receiptOnly = true,
        lines = { "Thanks for helping me.", "I appreciate you taking care of that.", "Thank you. That was kind of you." } },
    joke = { trust = 4, cooldown = 0.5, emote = "clap",
        lines = { "Okay, that was actually funny.", "Ha! Tell that one again sometime.", "I needed that laugh." } },
    compliment = { trust = 5, cooldown = 1, emote = "thumbsup",
        lines = { "That means a lot, genuinely.", "You are all right, you know that?", "I will remember you said that." } },
    funny_face = { trust = 3, cooldown = 0.5, emote = "shrug",
        lines = { "What was that face?! Okay, that got me.", "You are ridiculous. I like it.", "Ha! Do it again." } },
    insult = { trust = -12, cooldown = 1, emote = "insult",
        lines = { "Say that again and we have a problem.", "You just made an enemy.",
            "Watch your mouth.", "Do not talk to me like that.",
            "I have buried people for less.", "You are not worth the breath.",
            "Keep it up and see what happens." } },
    slap = { trust = -20, cooldown = 2, emote = "thumbsdown",
        lines = { "You just earned a fight.", "That is the last mistake you make near me.",
            "Now we settle this.", "Try that again. I dare you.",
            "You picked the wrong person.", "I will remember your face." } },
    mock = { trust = -9, cooldown = 1, emote = "insult",
        lines = { "Go on then, say it to my face.", "You think that was clever?",
            "Laugh it up. See how far that gets you.",
            "One day that mouth writes a cheque you cannot cash." } },
    blame = { trust = -11, cooldown = 1, emote = "thumbsdown",
        lines = { "You were not there. Do not put that on me.",
            "Everything is my fault now?", "I did what you asked. Remember that.",
            "Say it again in front of the others." } },
    threaten = { trust = -15, cooldown = 2, emote = "stop",
        lines = { "Take a step back.", "You want to rethink that?",
            "Try it. See what it costs you.",
            "I have killed for less and slept fine." } },
}

-- A social choice is interpreted by the person hearing it. Keep reactions
-- stable for an identity so the same survivor does not change personality
-- between conversations or across a save/load.
local SOCIAL_REACTIONS = {
    frightened = { mock = { -19, "Please stop. Please." },
        blame = { -15, "I did not do anything. I swear it." },
        threaten = { -20, "Do not. Please do not." },
        joke = { -2, "I cannot laugh about this right now." },
        compliment = { 2, "Thanks. I needed to hear that." },
        insult = { -16, "Please leave me alone." },
        slap = { -22, "Do not touch me. Do not come near me again." } },
    guarded = { joke = { 0, "Maybe another time." },
        compliment = { 0, "I will believe it when I see it." },
        funny_face = { -2, "What are you trying to do?" },
        insult = { -14, "I was right about you." },
        slap = { -20, "That is how it is going to be, then." } },
    loner = { joke = { -1, "I prefer some quiet." },
        compliment = { 1, "Thanks. I still need my space." },
        insult = { -13, "We are done talking." },
        slap = { -19, "Touch me again and you will regret it." } },
    sociable = { joke = { 6, "That was good. Tell me another." },
        funny_face = { 5, "You made me laugh." },
        insult = { -10, "That was uncalled for. I was being friendly." },
        slap = { -18, "I did not deserve that." } },
    predatory = { mock = { -15, "Keep talking. I am counting." },
        blame = { -12, "Careful who you accuse." },
        threaten = { -13, "Wrong person to say that to." },
        compliment = { -2, "Flattery will not get you far." },
        insult = { -18, "Careful what you say next." },
        slap = { -24, "You have made this simple." },
        joke = { -1, "You are wasting my time." } },
    gunner = { funny_face = { -1, "Keep your eyes on the street." },
        insult = { -15, "Say it where I can hear you properly." },
        slap = { -21, "Hands off the weapon and hands off me." } },
    brutal = { joke = { -3, "Nothing about this is funny." },
        compliment = { -1, "I do not need your approval." },
        insult = { -18, "One more word and I will end it." },
        mock = { -16, "Say one more word. Please." },
        blame = { -15, "I do not answer to you." },
        threaten = { -20, "Then do it. Stop talking about it." },
        slap = { -25, "You just chose how this ends." } },
    deserter = { joke = { 1, "I could use a reason to smile." },
        compliment = { 3, "You are not like the others." },
        insult = { -14, "I left one army already. Do not make me your enemy too." },
        mock = { -11, "I have been laughed at by better men than you." },
        blame = { -13, "I followed orders once. Never again." },
        threaten = { -17, "Threats. That is all any of you have." },
        slap = { -22, "I will not be hit again. Not by anyone." } },
}

local function socialReaction(survivorId, act, definition)
    local identity = KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local personality = SOCIAL_REACTIONS[tostring(identity.personality or "")]
    local reaction = personality ~= nil and personality[act] or nil
    return reaction ~= nil and reaction[1] or definition.trust,
        reaction ~= nil and reaction[2] or nil
end

-- A mean act does not stop at the person it was aimed at. Anyone the player
-- has brought along remembers it, through the same ledger and the same kind of
-- record: the target always minds most, and a second and third witness care
-- less. Nobody who merely walks past the county remembers anything, because a
-- stranger did not see it and no position is guessed to pretend they did.
local WITNESS_CAP = 6
local WITNESS_LIMIT = 3

function CompanionService.witnessReaction(act, trustDelta, index)
    if type(act) ~= "string" or act == "" then return nil end
    local delta = tonumber(trustDelta) or 0
    if delta >= 0 then return nil end
    local place = tonumber(index) or 0
    if place < 1 or place > WITNESS_LIMIT then return nil end
    local shared = math.min(WITNESS_CAP, math.floor(-delta * 0.4))
    return -math.max(1, math.floor(shared / place))
end

-- A ladder, not a cliff. One bad afternoon costs standing; a person who has
-- watched the player be cruel once too often decides the same way a badly
-- handled stranger does, through the hostility the rest of the mod already
-- reads. The bands match the ones Talk uses, so nothing new is stored.
function CompanionService.witnessLadder(trust)
    local value = tonumber(trust)
    if value == nil then return nil end
    if value <= 10 then return "hostile" end
    if value <= 25 then return "wary" end
    return nil
end

-- The same words land differently on somebody the player has already hurt. This
-- reads the standing the ledger already keeps - the same bands the order gate
-- uses - and answers over the archetype's line, so a compliment from a wary
-- companion is not the compliment from a friendly one. It changes an act's
-- wording, never its cost, so a bad history cannot be talked away.
CompanionService.STANDING_REACTIONS = {
    joke = { "I am not laughing. Not at anything you say.",
        "I will pass. Jokes need the right company." },
    compliment = { "I do not believe a word of it.",
        "Kind words do not undo what you did to me." },
    funny_face = { "I am not in the mood.", "Do not do that. Not at me." },
    insult = { "I am past words with you.",
        "I already know what you think of me." },
    mock = { "I heard you the first time.", "Say it. I am listening." },
    blame = { "You have blamed me for less than this.",
        "I know how this goes with you." },
}

function CompanionService.standingReaction(trust, act)
    if CompanionService.witnessLadder(trust) ~= "wary" then return nil end
    return CompanionService.STANDING_REACTIONS[tostring(act or "")]
end

-- A body in pain answers before personality does. The band comes from the same
-- reading the plate uses, so a person whose second line says hurt also speaks
-- like somebody hurt. Mean acts keep their own weight: being wounded does not
-- make an insult land softer.
CompanionService.HURT_REACTIONS = {
    joke = { "Not now. Laughing hurts me.",
        "I cannot. It pulls at something." },
    compliment = { "That is kind. I am not much use right now.",
        "Thank you. I ache all over." },
    funny_face = { "Do not make me laugh. It hurts.",
        "Not now. I am barely holding on." },
}

function CompanionService.hurtReaction(band, act)
    if band ~= "bad" and band ~= "severe" then return nil end
    return CompanionService.HURT_REACTIONS[tostring(act or "")]
end

-- Remembered history (2026-11-06): what the pair have actually done together,
-- kept as a plain tally on the relationship record under one fresh key. A pair
-- with the same trust speaks differently after help than after quarrels, which
-- is the difference between a number and a history.
CompanionService.HISTORY_KINDS = {
    helped = true, fed = true, healed = true, argued = true, fought = true,
}
CompanionService.HISTORY_WARM_LINES = {
    joke = { "You have earned a laugh. Go on.", "That one lands better because it is you." },
    compliment = { "From you, that means something. Thank you.",
        "You have been good to me. I remember it." },
}
CompanionService.HISTORY_GUARDED_LINES = {
    "I remember how you have spoken to me. Keep it short.",
    "We are not there yet. Say what you need.",
}

-- The single write boundary for a remembered exchange. A relationship record is
-- the only thing that owns it; an unknown kind never invents a bucket.
function CompanionService.rememberExchange(relation, kind, amount)
    if type(relation) ~= "table" then return nil, "unknown_relation" end
    if CompanionService.HISTORY_KINDS[kind] ~= true then return nil, "unknown_history" end
    local count = math.floor(tonumber(amount) or 1)
    if count < 1 then count = 1 end
    local history = type(relation.history) == "table" and relation.history or {}
    history[kind] = (tonumber(history[kind]) or 0) + count
    relation.history = history
    return relation, "saved"
end

-- The single read accessor. No history, an unreadable history, or an even tally
-- reads neutral, which is exactly how the pair answered before this key existed.
function CompanionService.historyTone(relation)
    local history = type(relation) == "table" and type(relation.history) == "table"
        and relation.history or nil
    if history == nil then return "neutral" end
    local warm = (tonumber(history.helped) or 0) + (tonumber(history.fed) or 0)
        + (tonumber(history.healed) or 0)
    local cold = (tonumber(history.argued) or 0) + (tonumber(history.fought) or 0)
    if warm > cold then return "warmer" end
    if cold > warm then return "guarded" end
    return "neutral"
end

-- One rule for choosing the sentence: remembered history, then what the pair
-- is, then what the body is, then the archetype's answer. Kept separate from the
-- call site so a fixture can drive the same decision the conversation makes.
function CompanionService.socialResponse(trust, act, meetings, fallback, hurt, relation)
    local place = math.max(1, tonumber(meetings) or 1)
    local tone = CompanionService.historyTone(relation)
    if tone == "warmer" then
        local warm = CompanionService.HISTORY_WARM_LINES[tostring(act or "")]
        if warm ~= nil then return warm[((place - 1) % #warm) + 1] end
    elseif tone == "guarded" then
        local guarded = CompanionService.HISTORY_GUARDED_LINES
        return guarded[((place - 1) % #guarded) + 1]
    end
    local lines = CompanionService.standingReaction(trust, act)
    if lines == nil then lines = CompanionService.hurtReaction(hurt, act) end
    if lines == nil then return fallback end
    return lines[((place - 1) % #lines) + 1]
end

-- A player who can see the warning and hear the refusal should also be able to
-- ask. The answer comes from the same ladder the plate and the order gate read,
-- so no surface can claim a standing the others deny. A hostile person is not
-- answered at all: askAbout refuses before this is reached.
CompanionService.STANDING_ANSWERS = {
    wary = { "I am still here. That is not the same as forgiving you.",
        "I am watching. That is all I will say." },
    steady = { "We are good. I would tell you if we were not.",
        "No complaints. Ask me again when it matters." },
    stranger = { "We have not spoken enough for me to say.",
        "Ask me again once we have been through something." },
}

function CompanionService.answerStanding(survivorId, playerId)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local trust = relation ~= nil and tonumber(relation.trust) or nil
    if trust == nil then return CompanionService.STANDING_ANSWERS.stranger[1] end
    local band = CompanionService.witnessLadder(trust)
    if band == "hostile" then return nil end
    local lines = CompanionService.STANDING_ANSWERS[band == "wary" and "wary" or "steady"]
    local meetings = math.max(1, tonumber(relation.meetings) or 1)
    return lines[((meetings - 1) % #lines) + 1]
end

local function recordWitnesses(playerId, targetId, act, trustDelta, now)
    local ids = KnoxPersistence.getSurvivorIds ~= nil
        and KnoxPersistence.getSurvivorIds() or {}
    local seen, spoken = 0, 0
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    for _, id in ipairs(ids) do
        if seen >= WITNESS_LIMIT then break end
        if tostring(id) ~= tostring(targetId) and hasPlayerAffiliation(id)
            and KnoxPersistence.isSurvivorAlive(id) then
            local delta = CompanionService.witnessReaction(act, trustDelta, seen + 1)
            if delta ~= nil then
                local recorded = KnoxPersistence.recordPlayerSocialAct(
                    playerId, id, "witnessed_" .. act, delta, 1, now)
                if recorded ~= nil then
                    seen = seen + 1
                    -- A witness with a body says it to the player's face; the
                    -- ledger entry is the same either way, so an offscreen
                    -- companion still remembers what it did not get to say.
                    local body = runtime ~= nil and runtime.getCharacter ~= nil
                        and runtime.getCharacter(id) or nil
                    local ticks = getTimestamp ~= nil and getTimestamp()
                        or math.floor(now * 3600)
                    if CompanionService.witnessLadder(recorded.trust) == "hostile" then
                        -- The same decision a bad lure reaches, so orders, trade
                        -- and the talk panel all read it without new wiring.
                        KnoxPersistence.setSurvivorHostileToPlayer(id, playerId, true)
                        KnoxActivityFeed.event("One of yours has had enough of you.")
                        if dialogue ~= nil and dialogue.sayWitness ~= nil and body ~= nil
                            and dialogue.sayWitness(body, id, targetId, ticks, 1800,
                                "witness_enough") then
                            spoken = spoken + 1
                        end
                    elseif dialogue ~= nil and dialogue.sayWitness ~= nil and body ~= nil
                        and dialogue.sayWitness(body, id, targetId, ticks, 1800) then
                        spoken = spoken + 1
                    end
                end
            end
        end
    end
    -- Only report it on the notice rail when nobody was there to say it, so the
    -- player never reads the same moment twice.
    if spoken == 0 and seen > 0 then
        KnoxActivityFeed.event(seen == 1 and "Someone you brought along saw that."
            or "The people you brought along saw that.")
    end
    return seen
end

function CompanionService.socialActs()
    local names = {}
    for name,definition in pairs(SOCIAL_ACTS) do
        if not definition.receiptOnly then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

function CompanionService.socialAct(player, survivorId, act)
    local definition = SOCIAL_ACTS[tostring(act)]
    if definition == nil then return false, "unknown_social_act" end
    local character, availability = validateInteraction(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    if character == nil or playerId == nil then
        return false, availability
    end
    local protectedTeam = hasPlayerAffiliation(survivorId)
    if CompanionService.isSociallyHostileToPlayer(survivorId, playerId) then
        return false, "hostile"
    end
    local attentive, attentionReason = KnoxSurvivorRuntime.beginPlayerConversation(survivorId, player)
    if not attentive then
        KnoxActivityFeed.speak(character, attentionReason == "danger"
            and "Not safe to talk here." or "Give me a moment to finish this.")
        return false, attentionReason
    end
    local relation = socialRelation(playerId, survivorId) or {}
    local before = tonumber(relation.trust) or 30
    local trustDelta, personalLine = socialReaction(survivorId, act, definition)
    local recorded, result = KnoxPersistence.recordPlayerSocialAct(
        playerId, survivorId, act, trustDelta, definition.cooldown, worldAge()
    )
    if recorded == nil then
        KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
        return false, result
    end
    if result == "cooldown" then
        -- Cooldowns only bite while upset; otherwise this is a quiet pass.
        -- Retain attention just as Talk does; this refuses the reward, not
        -- every other interaction in the open conversation.
        if act~="healed" then
            KnoxActivityFeed.speak(character, before < 25 and "Give me a minute." or "We just did that one.")
        end
        return false, result
    end
    local after = tonumber(recorded.trust) or before
    signalOrder(player, survivorId, act)
    local witnessed = definition.trust < 0
        and recordWitnesses(playerId, survivorId, act, trustDelta, worldAge()) or 0
    local line = personalLine or definition.lines[((recorded.meetings - 1) % #definition.lines) + 1]
    -- A wary or wounded companion answers the act, not the archetype: the same
    -- joke comes back from the person the player actually made.
    local hurt = nil
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs ~= nil and needs.painBand ~= nil and needs.snapshot ~= nil then
        local ok, snapshot = pcall(needs.snapshot, character)
        if ok and snapshot ~= nil then hurt = needs.painBand(snapshot) end
    end
    -- A real exchange becomes remembered history before the sentence is chosen,
    -- so the same moment already speaks with what the pair have been through.
    if trustDelta ~= nil and trustDelta ~= 0 then
        CompanionService.rememberExchange(recorded,
            act=="healed" and "healed" or (trustDelta > 0 and "helped" or "argued"), math.abs(trustDelta))
    end
    line = CompanionService.socialResponse(before, act, recorded.meetings, line, hurt, recorded)
    if protectedTeam and (act == "insult" or act == "slap") then
        line = act == "slap" and "Do not touch me." or "Do not speak to me like that."
    end
    KnoxActivityFeed.speak(character, line)
    if KnoxActivityFeed.reputation ~= nil then
        KnoxActivityFeed.reputation(character, after - before)
    end
    if not protectedTeam and (act == "insult" or act == "slap") and after < 10 then
        KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        socialSpeech(character, survivorId, "player_attack_warning", line)
        KnoxActivityFeed.event("The conversation turned hostile.")
        KnoxSurvivorRuntime.endPlayerConversation(survivorId, player)
        return false, "hostile"
    end
    print("[KnoxSurvivors][Companions] social survivor=" .. survivorId
        .. " player=" .. playerId        .. " act=" .. tostring(act)
        .. " trust=" .. tostring(before) .. "->" .. tostring(after)
        .. " witnessed=" .. tostring(witnessed))
    return true, recorded
end

-- A refusal by the survivor has a durable cost: the same person will not be
-- asked again for a couple of game hours. Capacity and mod-state refusals are
-- not personal choices, so they are not recorded and never impose a wait.
local RECRUIT_REFUSAL_COOLDOWN_HOURS = 2
-- Joining is a decision about the player, not a coin flip on first sight. The
-- gate sits above the starting trust of 30, so a recruit needs real contact.
local RECRUIT_TRUST_MINIMUM = 45
local RECRUIT_COOLDOWN_REASONS = {
    needs_time = true, low_reputation = true, prefers_alone = true,
    dangerous = true, hostile = true,
}

-- A homeless travel group is one household looking for a roof. It joins
-- through the same eligibility gate and the same affiliation writer as a
-- solo recruit; a second membership path would drift from the resident and
-- follower owners (design/SOCIETY_AND_AUTONOMY.md, implementation order 3).
local function groupMemberIds(group)
    local ids = {}
    for _, id in ipairs(type(group) == "table" and group.memberIds or {}) do
        if type(id) == "string" and id ~= "" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

-- Structural admissibility only: is this household reachable by the one
-- gate at all? Contact, mood and room are the caller's business.
function CompanionService.recruitableGroup(survivorId)
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(survivorId) or nil
    if type(group) ~= "table" then return nil, "no_group" end
    if KnoxPersistence.getBaseForOwner ~= nil and KnoxPersistence.getBaseForOwner("group",group.id) ~= nil then
        return nil,"homed_group"
    end
    local ids = groupMemberIds(group)
    if #ids < 2 then return nil, "no_group" end
    if group.factionId ~= nil then return nil, "faction_group" end
    for _, id in ipairs(ids) do
        if not KnoxPersistence.isSurvivorAlive(id) then return nil, "member_dead" end
        local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
            and KnoxPersistence.getSurvivorAffiliation(id) or nil
        if type(affiliation) == "table" and affiliation.kind ~= nil
            and affiliation.kind ~= "independent" then
            return nil, "member_affiliated"
        end
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(id) or nil
        if type(duty) == "table" and duty.mode == "base" then
            return nil, "homed_group"
        end
    end
    return { group = group, memberIds = ids }, "homeless_group"
end

-- Room is counted for the whole household: admitting three of five and
-- leaving two behind is not the invitation the player made.
function CompanionService.groupHasRoom(playerId, count, options)
    if options ~= nil and options.forBase == true then return true end
    local free = KnoxSettings.companionLimit() - #KnoxPersistence.getCompanionIds(playerId)
    return free >= count
end
function CompanionService.canRecruit(player, survivorId, options)
    if not KnoxSettings.enabled() then
        return false, "mod_disabled"
    end
    local playerId = CompanionService.getPlayerId(player)
    local character, availability = validateInteraction(player, survivorId)
    if not KnoxPersistence.isSurvivorAlive(survivorId) then
        return false, "character_dead"
    end
    if playerId == nil then
        return false, "player_unavailable"
    end
    if character == nil then
        return false, availability
    end
    if not contactChannel(player, character) then return false, "no_contact" end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return false, "hostile" end
    -- A homeless travel group arrives as one household: the contacted member
    -- speaks for it, every member must be willing, and room is counted once
    -- for all of them.
    local recruitGroup = CompanionService.recruitableGroup(survivorId)
    if recruitGroup ~= nil then
        for _, memberId in ipairs(recruitGroup.memberIds) do
            if KnoxPersistence.isSurvivorHostileToPlayer(memberId, playerId) then
                return false, "hostile"
            end
        end
        if not CompanionService.groupHasRoom(
            playerId, #recruitGroup.memberIds, options) then
            return false, "companion_limit_group"
        end
    end
    if recruitGroup == nil
        and (KnoxPersistence.getTravelGroupFor(survivorId) ~= nil
            or KnoxPersistence.getFactionForSurvivor(survivorId) ~= nil) then
        return false, "already_with_group"
    end
    if recruitGroup == nil
        and not KnoxPersistence.isIndependentSurvivor(survivorId) then
        return false, "not_independent"
    end
    -- A base resident is not a follower, so the party cap must not decide who
    -- may move in. Every other recruitment gate still applies.
    if (options == nil or options.forBase ~= true)
        and #KnoxPersistence.getCompanionIds(playerId) >= KnoxSettings.companionLimit() then
        return false, "companion_limit"
    end
    local social = playerSocialDisposition(playerId, survivorId)
    local relation = socialRelation(playerId, survivorId) or {}
    -- The other half of recordPlayerRecruitRefusal: the wait it writes is
    -- enforced here, so a refused ask is not instantly re-askable.
    local nowHours = getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or nil
    if nowHours ~= nil
        and (tonumber(relation.nextRecruitHours) or 0) > nowHours then
        return false, "cooling_off"
    end
    if social == "attack_on_sight" then return false, "dangerous" end
    if social == "independent" then return false, "prefers_alone" end
    if social == "warm_up"
        and (tonumber(relation.meetings) or 0) < 2
        and (tonumber(relation.recruitmentAttempts) or 0) < 2 then
        return false, "needs_time"
    end
    if social == "lure" and (tonumber(relation.lureAttempts) or 0) == 0 then
        return false, "lure"
    end
    if social == "lure" then return false, "dangerous" end
    -- Reputation gates recruiting when the sandbox switch is on (default).
    -- Strangers who distrust the player refuse; friends join freely. Off
    -- means contact rules alone decide, as before.
    if KnoxSettings.useReputation ~= nil and KnoxSettings.useReputation() then
        local trust = tonumber(relation.trust) or 30
        if trust < RECRUIT_TRUST_MINIMUM then return false, "low_reputation" end
    end
    return true, "ready"
end

function CompanionService.recruit(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local ready, reason, trust = CompanionService.canRecruit(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not ready then
        if reason == "no_contact" then return false, reason end
        -- Only a personal refusal is remembered. A full party or a dead mod is
        -- not the survivor's decision, and storing it would punish the player
        -- for a limit they can fix.
        if playerId ~= nil and RECRUIT_COOLDOWN_REASONS[reason] == true
            and KnoxPersistence.recordPlayerRecruitRefusal ~= nil
            and getGameTime ~= nil and getGameTime() ~= nil then
            pcall(KnoxPersistence.recordPlayerRecruitRefusal, playerId, survivorId,
                getGameTime():getWorldAgeHours(), RECRUIT_REFUSAL_COOLDOWN_HOURS)
        end
        if character ~= nil then
            local line = reason == "already_with_group"
                and "I'm already travelling with people."
                or reason == "hostile"
                and "Keep your distance."
                or reason == "needs_time"
                and "I need more time before I travel with you."
                or reason == "prefers_alone"
                and "I am staying on my own."
                or reason == "lure"
                and "I know somewhere quiet. Come with me."
                or reason == "dangerous"
                and "You should have kept walking."
                or reason == "cooling_off"
                and "Ask me again in a while. Not now."
                or "I can't come with you right now."
            if reason == "low_reputation" then
                recordSocialEvent(playerId, survivorId, "recruit_attempt")
                line = "You have not exactly earned my trust yet."
                KnoxActivityFeed.speak(character, line)
            elseif reason == "needs_time" then
                recordSocialEvent(playerId, survivorId, "recruit_attempt")
                socialSpeech(character, survivorId, "player_warm_up", line)
            elseif reason == "lure" then
                recordSocialEvent(playerId, survivorId, "lure_attempt")
                socialSpeech(character, survivorId, "player_lure", line)
            elseif reason == "dangerous" then
                KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
                socialSpeech(character, survivorId, "player_attack_warning", line)
                if KnoxSurvivorRuntime.beginRobbery ~= nil then
                    KnoxSurvivorRuntime.beginRobbery(
                        survivorId, player, math.floor(worldAge() * 3600)
                    )
                end
            else
                KnoxActivityFeed.speak(character, line)
            end
        end
        return false, reason, trust
    end
    local social = playerSocialDisposition(playerId, survivorId)
    if social == "volatile" then
        KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        if character ~= nil then
            socialSpeech(character, survivorId, "player_attack_warning", "Do not come any closer.")
        end
        KnoxActivityFeed.event("The survivor turned on you.")
        return false, "hostile", trust
    end
    local saved, result = KnoxPersistence.setPlayerCompanion(
        survivorId,
        playerId,
        "follow",
        worldAge()
    )
    if not saved then
        return false, result
    end
    if character ~= nil then
        KnoxActivityFeed.speak(character, "All right. I'll come with you.")
    end
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    KnoxActivityFeed.event(displayName(survivorId) .. " joined you.")
    print(
        "[KnoxSurvivors][Companions] recruited survivor=" .. survivorId
            .. " player=" .. playerId
    )
    return true, "recruited"
end

-- One contacted member speaks for the household. Every admission uses the
-- solo writer; the group record is released just before its member joins, so
-- a mid-way refusal leaves the rest of the household still travelling.
function CompanionService.admitGroup(player, playerId, recruitGroup)
    local admitted, refused = 0, 0
    local limit = KnoxSettings.companionLimit()
    for _, id in ipairs(recruitGroup.memberIds) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local room = #KnoxPersistence.getCompanionIds(playerId) < limit
        if room and KnoxPersistence.isSurvivorAlive(id)
            and not KnoxPersistence.isSurvivorHostileToPlayer(id, playerId) then
            if KnoxPersistence.removeTravelGroupMember ~= nil then
                KnoxPersistence.removeTravelGroupMember(id)
            end
            local saved = KnoxPersistence.setPlayerCompanion(
                id, playerId, "follow", worldAge()
            )
            if saved then
                admitted = admitted + 1
                CompanionService.rememberCommitment(player, id)
                KnoxSurvivorRuntime.notifyDutyChanged(id)
                if character ~= nil then
                    KnoxActivityFeed.speak(character, "All right. I'll come with you.")
                end
            else
                refused = refused + 1
                -- A failed write must not strand the person: put them back in
                -- the household they were travelling with.
                if KnoxPersistence.addTravelGroupMember ~= nil
                    and recruitGroup.group ~= nil then
                    pcall(KnoxPersistence.addTravelGroupMember,
                        recruitGroup.group.id, id)
                end
            end
        else
            refused = refused + 1
        end
    end
    local lead = recruitGroup.memberIds[1]
    if admitted > 0 and lead ~= nil then
        KnoxActivityFeed.event(displayName(lead)
            .. (admitted > 1 and " and " .. tostring(admitted - 1)
                .. " others joined you." or " joined you."))
    end
    return admitted > 0,
        refused == 0 and "recruited_group" or "recruited_group_partial",
        admitted
end
-- What a resident says when a base invitation is refused. The panel carries
-- the player-facing sentence; this is the person's own voice, and both read the
-- same reason string so they cannot disagree.
local BASE_INVITE_REFUSALS = {
    already_with_group = "I'm already staying with people.",
    ambiguous_base = "Which place do you mean? I'm not guessing.",
    busy = "Not now.",
    character_dead = "...",
    dangerous = "Keep your distance.",
    hostile = "Keep your distance.",
    low_reputation = "You have not earned that kind of trust yet.",
    lure = "I know somewhere quieter. Come with me.",
    already_resident = "I already live at your place.",
    needs_time = "I need more time before I move in with anyone.",
    no_base = "Where would I even stay?",
    not_companion = "I don't travel with you.",
    no_contact = "...",
    not_independent = "I'm not looking to settle down.",
    prefers_alone = "I am staying on my own.",
    too_far_away = "Say that to my face.",
    unknown_base = "That isn't one of your homes.",
}

-- The homes this player may offer a newcomer. One base needs no question;
-- two or more is the player's choice to make, so every caller asks through
-- KnoxBasePicker instead of letting the mod resolve it. Another owner's
-- settlement is never offered, whichever square the player stands on.
function CompanionService.baseChoicesFor(player, playerId)
    if KnoxPersistence == nil or KnoxPersistence.getBasesForOwner == nil then
        return {}
    end
    local id = playerId
    if id == nil and player ~= nil then id = CompanionService.getPlayerId(player) end
    if id == nil then return {} end
    local ok, bases = pcall(KnoxPersistence.getBasesForOwner, "player", id)
    if not ok or type(bases) ~= "table" then return {} end
    local list = {}
    for _, base in ipairs(bases) do
        if type(base) == "table" and base.id ~= nil then list[#list + 1] = base end
    end
    return list
end

-- The base a newcomer would move into. `baseId` is the player's answer; without
-- one a single home needs no question, and several homes are never resolved by
-- guessing -- not even the one the player happens to be standing in, because
-- that is how a move-in landed at the wrong settlement.
function CompanionService.inviteBaseFor(player, playerId, baseId)
    local bases = CompanionService.baseChoicesFor(player, playerId)
    if #bases == 0 then return nil, "no_base" end
    if baseId ~= nil then
        for _, base in ipairs(bases) do
            if tostring(base.id) == tostring(baseId) then return base, "chosen" end
        end
        return nil, "unknown_base"
    end
    if #bases > 1 then return nil, "ambiguous_base" end
    return bases[1], "only_base"
end

-- `baseId` is the player's explicit choice. Without one, one home resolves
-- directly and several homes answer `choose_base`, which tells the caller to
-- ask (KnoxBasePicker) rather than treating the question as a refusal.
function CompanionService.canInviteToBase(player, survivorId, baseId)
    local available, reason = CompanionService.canRecruit(player, survivorId, { forBase = true })
    if not available then return false, reason end
    local base, baseReason = CompanionService.inviteBaseFor(player, nil, baseId)
    if base ~= nil then return true, "ready", base end
    if baseId == nil and baseReason == "ambiguous_base" then return true, "choose_base" end
    return false, baseReason
end

-- Base invitations are the second half of the talk direction: recruiting was
-- the only way to gain a member, so a survivor who joined became a follower and
-- a settlement could only grow through followers. This reuses the one
-- affiliation writer (setPlayerCompanion) and the one resident-duty writer
-- (setPlayerBaseResident) rather than inventing a membership path, so the new
-- resident is immediately an ordinary resident to every other owner.
function CompanionService.inviteToBase(player, survivorId, baseId)
    local available, reason, base = CompanionService.canInviteToBase(player, survivorId, baseId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not available then
        if character ~= nil then
            if reason == "low_reputation" or reason == "needs_time" then
                recordSocialEvent(
                    CompanionService.getPlayerId(player), survivorId, "recruit_attempt"
                )
            elseif reason == "dangerous" then
                KnoxPersistence.setSurvivorHostileToPlayer(
                    survivorId, CompanionService.getPlayerId(player), true
                )
                socialSpeech(character, survivorId, "player_attack_warning", "Keep your distance.")
                return false, "dangerous"
            end
            KnoxActivityFeed.speak(
                character, BASE_INVITE_REFUSALS[reason] or "I can't do that right now."
            )
        end
        return false, reason
    end
    -- A caller that skipped the chooser gets a refusal instead of a posting to
    -- whichever base happened to be first.
    if base == nil then return false, "ambiguous_base" end
    local playerId = CompanionService.getPlayerId(player)
    local saved, result = KnoxPersistence.setPlayerCompanion(
        survivorId, playerId, "follow", worldAge()
    )
    if not saved then return false, result end
    local homed = KnoxPersistence.setPlayerBaseResident(
        survivorId, playerId, base.id, worldAge()
    )
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local place = type(base.name) == "string" and base.name ~= "" and base.name or "your base"
    if character ~= nil then
        KnoxActivityFeed.speak(character, "All right. I'll move in.")
    end
    if homed then
        KnoxActivityFeed.event(displayName(survivorId) .. " moved into " .. place .. ".")
        print("[KnoxSurvivors][Companions] base invite survivor=" .. survivorId
            .. " player=" .. playerId .. " base=" .. tostring(base.id))
        return true, "resident"
    end
    -- They accepted the invitation; only the posting failed. Saying so keeps a
    -- follower rather than a silent half-membership.
    KnoxActivityFeed.event(displayName(survivorId)
        .. " joined you, but has no place at " .. place .. " yet.")
    return true, "companion_only"
end

-- A follower who already travels with the player can be offered a home. The
-- affiliation is already correct, so this is only the resident-duty write; the
-- gates are the ones a companion order needs plus the same base resolution.
function CompanionService.canMoveIntoBase(player, survivorId, baseId)
    if not KnoxSettings.enabled() then return false, "mod_disabled" end
    local playerId = CompanionService.getPlayerId(player)
    local character, availability = validateInteraction(player, survivorId)
    if not KnoxPersistence.isSurvivorAlive(survivorId) then return false, "character_dead" end
    if playerId == nil then return false, "player_unavailable" end
    if character == nil then return false, availability end
    if not contactChannel(player, character) then return false, "no_contact" end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if type(affiliation) ~= "table" or affiliation.kind ~= "player"
        or tostring(affiliation.ownerId) ~= tostring(playerId) then
        return false, "not_companion"
    end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if type(duty) == "table" and duty.mode == "base" then
        return false, "already_resident"
    end
    local base, baseReason = CompanionService.inviteBaseFor(player, nil, baseId)
    if base ~= nil then return true, "ready", base end
    if baseId == nil and baseReason == "ambiguous_base" then return true, "choose_base" end
    return false, baseReason
end

function CompanionService.moveIntoBase(player, survivorId, baseId)
    local available, reason, base = CompanionService.canMoveIntoBase(player, survivorId, baseId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not available then
        if character ~= nil then
            KnoxActivityFeed.speak(character, BASE_INVITE_REFUSALS[reason] or "I can't do that right now.")
        end
        return false, reason
    end
    if base == nil then return false, "ambiguous_base" end
    local playerId = CompanionService.getPlayerId(player)
    local saved, result = KnoxPersistence.setPlayerBaseResident(
        survivorId, playerId, base.id, worldAge()
    )
    if not saved then return false, result end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local place = type(base.name) == "string" and base.name ~= "" and base.name or "your base"
    if character ~= nil then
        KnoxActivityFeed.speak(character, "All right. I'll settle in.")
    end
    KnoxActivityFeed.event(displayName(survivorId) .. " moved into " .. place .. ".")
    print("[KnoxSurvivors][Companions] moved in survivor=" .. survivorId
        .. " player=" .. playerId .. " base=" .. tostring(base.id))
    return true, "resident"
end

function CompanionService.command(player, survivorId, order, suppressSignal, batch)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxOrderCatalog.isPrimaryOrder(order)
        or (order ~= "follow" and order ~= "hold" and order ~= "relax") then
        return false, "invalid_command"
    end
    if KnoxSurvivorRuntime.canAcceptOrders ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canAcceptOrders(survivorId)
        if not accepted then return false, reason end
    end
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, order, batch)
    if not delivered then return false, delivery end
    if not KnoxPersistence.updateCompanionOrder(
        survivorId,
        playerId,
        order,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    CompanionService.excludePartyDestinationRecipient(player, survivorId)
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        KnoxActivityFeed.speak(
            character,
            order == "follow" and "Right behind you."
                or (order == "relax" and "I'll take a breather." or "I'll stay here.")
        )
    end
    signalOrder(player, survivorId, order)
    return true, order
end

function CompanionService.commandAll(player, order)
    local batch = {}
    local ids = CompanionService.getCompanionIds(player)
    local changed, firstFailure = 0, nil
    local members = {}
    for _, survivorId in ipairs(ids) do
        local success, reason = CompanionService.command(player, survivorId, order, true, batch)
        changed = changed + (success and 1 or 0)
        if not success and firstFailure == nil then firstFailure = reason end
        if success then
            local character = KnoxSurvivorRuntime.getCharacter(survivorId)
            if character ~= nil then members[#members + 1] = character end
        end
    end
    if changed > 0 then
        local messages = {
            follow = "Party order: regroup and follow.",
            hold = "Party order: hold position.",
            relax = "Party order: rest and recover.",
        }
        local message = messages[order] or "Party order updated."
        if changed < #ids then
            message = message .. " " .. tostring(changed) .. " of " .. tostring(#ids)
                .. " companions received it."
        end
        KnoxActivityFeed.event(message)
        local signals = rawget(_G, "KnoxOrderSignals")
        if signals ~= nil and signals.group ~= nil then
            signals.group(player, members, order)
        end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

-- Single player-facing dispatch point.  The catalogue describes the order;
-- existing persistence/directive services still own execution and state.
-- Keeping this boundary small lets menus and future notebook controls use the
-- same validation without introducing another task manager.
-- ORDER CONTACT (pure)
-- Owner option, off by default: an order does not require standing near the
-- survivor. On: the old close-contact admission returns, read through the
-- same body squares the interaction prompt uses.
local ORDER_CONTACT_RANGE_SQUARED = 36
local function closeContactRequired()
    local settings = KnoxSettings
    return settings ~= nil and settings.requireCloseContact ~= nil
        and settings.requireCloseContact() == true
end

function CompanionService.orderAdmitted(player, survivorId)
    if not closeContactRequired() then return true end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(survivorId) or nil
    if player == nil or character == nil then return false, "no_contact" end
    local ok, near = pcall(function()
        local here = player:getCurrentSquare()
        local there = character:getCurrentSquare()
        if here == nil or there == nil or here:getZ() ~= there:getZ() then
            return false
        end
        local dx = (player.getX ~= nil and player:getX() or here:getX())
            - (character.getX ~= nil and character:getX() or there:getX())
        local dy = (player.getY ~= nil and player:getY() or here:getY())
            - (character.getY ~= nil and character:getY() or there:getY())
        return dx * dx + dy * dy <= ORDER_CONTACT_RANGE_SQUARED
    end)
    if not ok or near ~= true then return false, "too_far_to_order" end
    return true
end
-- END ORDER CONTACT
function CompanionService.issueOrder(player, survivorId, kind, payload)
    local resolved, resolveResult
    if KnoxOrderCatalog.resolve ~= nil then
        resolved, resolveResult = KnoxOrderCatalog.resolve(kind)
    end
    local normalizedKind = resolved ~= nil and resolved.kind
        or KnoxOrderCatalog.normalize(kind)
    if normalizedKind == nil or (resolved == nil and not KnoxOrderCatalog.isKnown(normalizedKind)) then
        return false, resolveResult or "unknown_order"
    end
    -- The option's executor: with Require Close Contact on, an order needs
    -- the player standing near the survivor; off (default) keeps today's
    -- no-proximity ordering.
    if normalizedKind ~= "dismiss" then
        local admitted, admission = CompanionService.orderAdmitted(player, survivorId)
        if not admitted then return false, admission end
    end
    -- Dismissal is a persistence ownership change and remains safe while a
    -- shell is detached. Native companion orders wait for lifecycle recovery.
    if normalizedKind ~= "dismiss" and KnoxSurvivorRuntime.canAcceptOrders ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canAcceptOrders(survivorId)
        if not accepted then return false, reason end
    end
    -- Base residents use the same human-facing search labels as companions,
    -- but their request must remain a durable base duty rather than becoming
    -- a companion directive.  This branch deliberately precedes default area
    -- construction, which would otherwise route the order through the wrong
    -- ownership model.
    if BASE_SUPPLY_ORDERS[normalizedKind]
        and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.setBaseSupplyOrder ~= nil then
        local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
        if duty.mode == "base" and duty.baseId ~= nil then
            return CompanionService.setBaseSupplyOrder(player, survivorId, normalizedKind)
        end
    end
    -- `patrol` is also the resident base preference.  When a caller supplies
    -- an area payload, it is the concrete companion directive; converge that
    -- familiar label here so the payload cannot be silently discarded by the
    -- preference branch below.
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end
    if normalizedKind == "follow" or normalizedKind == "hold" or normalizedKind == "relax" then
        return CompanionService.command(player, survivorId, normalizedKind)
    end
    if normalizedKind == "return_to_base" then
        return CompanionService.sendToBase(player, survivorId)
    end
    if normalizedKind == "resume_normal_duty" then
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(survivorId) or {}
        if duty.mode == "base" then
            return CompanionService.clearBaseSupplyOrder(player, survivorId)
        end
        return CompanionService.clearDirective(player, survivorId)
    end
    -- Catalogue actions are thin adapters to their existing service owners.
    -- Keeping them here gives every player-facing entry point one validation
    -- boundary without introducing another executor or state store.
    if normalizedKind == "recruit" then
        return CompanionService.recruit(player, survivorId)
    end
    if normalizedKind == "dismiss" then
        return CompanionService.dismiss(player, survivorId)
    end
    if normalizedKind == "medical_help" then return CompanionService.requestMedicalHelp(player, survivorId) end
    if normalizedKind == "enable_auto_medical" or normalizedKind == "disable_auto_medical" then
        return CompanionService.setAutoMedical(player, survivorId, normalizedKind == "enable_auto_medical")
    end
    if normalizedKind == "check_needs" then
        return CompanionService.askNeeds(player, survivorId)
    end
    if normalizedKind == "enter_vehicle" then
        return CompanionService.boardPlayerVehicle(player, survivorId)
    end
    if normalizedKind == "drive_ahead" then
        return CompanionService.drivePlayerVehicle(player, survivorId)
    end
    if normalizedKind == "let_companion_drive" then
        return CompanionService.letCompanionDrive(player, survivorId)
    end
    if normalizedKind == "drive_nearest_vehicle" then
        return CompanionService.driveNearestVehicle(player, survivorId)
    end
    if normalizedKind == "exit_vehicle" then
        return CompanionService.exitVehicle(player, survivorId)
    end
    if normalizedKind == "allow_climbing"
        or normalizedKind == "disallow_climbing" then
        return CompanionService.setClimbing(
            player,
            survivorId,
            normalizedKind == "allow_climbing"
        )
    end
    if normalizedKind == "allow_doors"
        or normalizedKind == "disallow_doors" then
        return CompanionService.setDoorOpening(
            player,
            survivorId,
            normalizedKind == "allow_doors"
        )
    end
    if normalizedKind == "enable_autoloot"
        or normalizedKind == "disable_autoloot" then
        return CompanionService.setAutoLoot(
            player,
            survivorId,
            normalizedKind == "enable_autoloot"
        )
    end
    if normalizedKind == "combat_stance" then
        local stance = type(payload) == "table" and payload.stance or payload
        return CompanionService.setCombatStance(player, survivorId, stance)
    end
    if normalizedKind == "weapon_preference" then
        local preference = type(payload) == "table" and payload.preference or payload
        return CompanionService.setWeaponPreference(player, survivorId, preference)
    end
    -- A concrete task assignment is still owned by the existing task board.
    -- Route it through the same catalogue boundary as every other player
    -- order, but require the explicit base/task payload so a malformed menu
    -- call cannot silently turn into an automatic preference change.
    if normalizedKind == "assign_base_task" then
        if type(payload) ~= "table" or payload.baseId == nil or payload.taskId == nil then
            return false, "task_target_required"
        end
        local assigned, result = CompanionService.assignBaseTask(
            player, survivorId, payload.baseId, payload.taskId
        )
        return assigned ~= nil, result
    end
    if payload == nil then
        payload = defaultCompanionArea(player, survivorId, normalizedKind)
            or defaultSearchDirective(player, survivorId, normalizedKind)
    end
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end
    -- `guard` is intentionally shared by the catalogue as a base preference
    -- and as a location directive. A payload means the player selected a
    -- concrete guard post, so route it to the directive executor before the
    -- preference branch; a payload-less order still sets the resident role.
    if payload ~= nil and KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, directiveResult = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, directiveResult == "invalid_directive"
                and "directive_target_required" or directiveResult
        end
        return CompanionService.issueDirective(player, survivorId, directive)
    end
    if KnoxOrderCatalog.isBasePreference(normalizedKind) then
        return CompanionService.setBaseJobPreference(player, survivorId, normalizedKind)
    end
    -- Concrete settlement task names are valid player-facing order vocabulary,
    -- but the resident scheduler owns their execution. Route them to the
    -- matching persisted preference instead of creating a second task path.
    local taskPreference = KnoxOrderCatalog.preferenceForTask ~= nil
        and KnoxOrderCatalog.preferenceForTask(normalizedKind) or nil
    if taskPreference ~= nil then
        return CompanionService.setBaseJobPreference(player, survivorId, taskPreference)
    end
    if KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, directiveResult = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, directiveResult == "invalid_directive"
                and "directive_target_required" or directiveResult
        end
        return CompanionService.issueDirective(player, survivorId, directive)
    end
    return false, "order_not_companion_executable"
end

-- Concrete settlement work is still a task-board concern, but the player-facing
-- assignment enters through the same service boundary as every other order.
-- This keeps ownership validation and runtime refresh in one place without
-- creating a second command or scheduling system.
function CompanionService.assignBaseTask(player, survivorId, baseId, taskId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "job")
    if not delivered then return nil, delivery end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or baseId == nil or taskId == nil or survivorId == nil then
        return nil, "invalid_assignment"
    end
    local taskBoard = rawget(_G, "KnoxBaseTaskBoard")
    if taskBoard == nil then
        taskBoard = require "KS_BaseTaskBoard"
    end
    local assigned, result = taskBoard.claimSpecific(
        baseId, taskId, survivorId, playerId
    )
    if assigned == nil then return nil, result end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll handle that job.")
    end
    signalOrder(player, survivorId, "job")
    return assigned, result
end

-- Group-level counterpart to issueOrder.  Party commands used to call a
-- mixture of commandAll(), issueDirectiveAll(), and direct persistence helpers,
-- which meant the visible order vocabulary and validation could diverge.  Keep
-- the same catalogue boundary for a whole party while preserving the existing
-- per-system ownership rules.
local function clearPartyDestinationRecord(playerId, reason)
    local record = partyDestinations[playerId]
    if record == nil then return false, 0 end
    partyDestinations[playerId] = nil
    local notified = 0
    for _, id in ipairs(record.recipientIds or {}) do
        if KnoxSurvivorRuntime ~= nil and KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
            KnoxSurvivorRuntime.notifyDutyChanged(id)
        end
        notified = notified + 1
    end
    if reason == "expired" and KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("Party destination expired.")
    elseif reason == "roster_invalid" and KnoxActivityFeed ~= nil
        and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("Party destination cleared: no eligible companions remain.")
    end
    return true, notified, reason
end

local function finiteDestinationCoordinate(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge
        and value ~= -math.huge and math.abs(value) <= 30000
end

local function validPartyDestination(directive)
    if type(directive) ~= "table" or directive.kind ~= "go_to" then return false end
    local x, y, z = tonumber(directive.minX), tonumber(directive.minY), tonumber(directive.z)
    local maxX, maxY = tonumber(directive.maxX) or x, tonumber(directive.maxY) or y
    if not finiteDestinationCoordinate(x) or not finiteDestinationCoordinate(y)
        or not finiteDestinationCoordinate(z) or x ~= maxX or y ~= maxY
        or x ~= math.floor(x) or y ~= math.floor(y) or z ~= math.floor(z) then
        return false
    end
    local okCell, cell = pcall(function() return getCell ~= nil and getCell() or nil end)
    if not okCell or cell == nil or cell.getGridSquare == nil then return false end
    local okSquare, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    if not okSquare or square == nil then return false end
    if square.canStand ~= nil then
        local ok, canStand = pcall(function() return square:canStand() end)
        if not ok or canStand ~= true then return false end
    end
    return true
end

function CompanionService.hasPartyDestination(player)
    local playerId = CompanionService.getPlayerId(player)
    return playerId ~= nil and CompanionService.getPartyDestination(playerId) ~= nil or false
end

function CompanionService.getPartyDestination(playerId)
    if type(playerId) ~= "string" or playerId == "" then return nil end
    local record = partyDestinations[playerId]
    if record == nil then return nil end
    if worldAge() >= record.expiresAtHours then
        clearPartyDestinationRecord(playerId, "expired")
        return nil
    end
    local current = {}
    for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
        current[tostring(id)] = true
    end
    local retained = {}
    for _, id in ipairs(record.recipientIds) do
        if current[tostring(id)] then
            local duty = KnoxPersistence.getSurvivorDuty ~= nil
                and KnoxPersistence.getSurvivorDuty(id) or nil
            if duty ~= nil and duty.mode == "companion"
                and (duty.order == nil or duty.order == "follow")
                and duty.directive == nil then
                retained[#retained + 1] = id
            end
        end
    end
    record.recipientIds = retained
    for id in pairs(record.arrived) do
        if not current[tostring(id)] then record.arrived[id] = nil end
    end
    if #retained == 0 then
        clearPartyDestinationRecord(playerId, "roster_invalid")
        return nil
    end
    return record
end

function CompanionService.getPartyDestinationFor(survivorId)
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    if duty == nil or duty.mode ~= "companion" or type(duty.ownerId) ~= "string"
        or (duty.order ~= nil and duty.order ~= "follow") or duty.directive ~= nil then
        return nil
    end
    local record = CompanionService.getPartyDestination(duty.ownerId)
    if record == nil then return nil end
    local included = false
    for _, id in ipairs(record.recipientIds) do
        if tostring(id) == tostring(survivorId) then included = true break end
    end
    if not included then return nil end
    local directive = {}
    for key, value in pairs(record.destination) do directive[key] = value end
    directive.partyDestination = true
    directive.partyDestinationRevision = record.revision
    directive.partyDestinationArrived = record.arrived[tostring(survivorId)] == true
    return directive, record.revision
end

function CompanionService.excludePartyDestinationRecipient(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local record = playerId ~= nil and partyDestinations[playerId] or nil
    if record == nil then return false end
    local retained = {}
    local changed = false
    for _, id in ipairs(record.recipientIds) do
        if tostring(id) == tostring(survivorId) then changed = true
        else retained[#retained + 1] = id end
    end
    if not changed then return false end
    record.recipientIds = retained
    record.arrived[tostring(survivorId)] = nil
    if #retained == 0 then clearPartyDestinationRecord(playerId, "superseded") end
    return true
end

function CompanionService.issuePartyDestination(player, directive)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil then return false, 0, "invalid_player" end
    if not validPartyDestination(directive) then
        return false, 0, "destination_unavailable"
    end
    local recipients = playerPartyMemberIds(playerId)
    if #recipients == 0 then
        return false, 0, "no_eligible_companions"
    end
    local checked, contactIds = {}, {}
    local old = partyDestinations[playerId]
    for _, roster in ipairs({recipients, old ~= nil and old.recipientIds or {}}) do
        for _, id in ipairs(roster) do
            if not checked[id] then
                local contact, reason = CompanionService.orderContact(player, id)
                if not contact then
                    if KnoxActivityFeed.event ~= nil then KnoxActivityFeed.event("Cannot reach every party member. Existing destination continues.") end
                    return false, 0, reason
                end
                checked[id] = true
                contactIds[#contactIds+1] = id
            end
        end
    end
    local batch = {}
    for _, id in ipairs(contactIds) do
        local delivered, reason = CompanionService.deliverOrder(player, id, "go_to", batch)
        if not delivered then return false, 0, reason end
    end
    local x, y, z = tonumber(directive.minX), tonumber(directive.minY), tonumber(directive.z)
    local destination = { kind = "go_to", minX = x, minY = y,
        maxX = x, maxY = y, z = z }
    nextPartyDestinationRevision = nextPartyDestinationRevision + 1
    local now = worldAge()
    local record = {
        ownerId = playerId, destination = destination, recipientIds = recipients,
        arrived = {}, issuedAtHours = now,
        expiresAtHours = now + PARTY_DESTINATION_TTL_HOURS,
        revision = nextPartyDestinationRevision,
    }
    clearPartyDestinationRecord(playerId, "replaced")
    partyDestinations[playerId] = record
    for _, id in ipairs(recipients) do
        signalOrder(player, id, "go_to")
        if KnoxSurvivorRuntime ~= nil and KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
            KnoxSurvivorRuntime.notifyDutyChanged(id)
        end
    end
    if KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("Party destination set for " .. tostring(#recipients) .. " companions.")
    end
    return true, #recipients, "destination_set"
end

function CompanionService.cancelPartyDestination(player)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil then return false, 0, "invalid_player" end
    local record = partyDestinations[playerId]
    if record ~= nil then
        for _, id in ipairs(record.recipientIds) do
            local contact, reason = CompanionService.orderContact(player, id)
            if not contact then
                if reason == "order_not_delivered" and KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
                    KnoxActivityFeed.event("Cannot reach every party member. Existing destination continues.")
                end
                return false, 0, reason
            end
        end
        local batch = {}
        for _, id in ipairs(record.recipientIds) do
            local delivered, reason = CompanionService.deliverOrder(player, id, "follow", batch)
            if not delivered then return false, 0, reason end
        end
    end
    local cleared, notified = clearPartyDestinationRecord(playerId, "cancelled")
    if cleared then
        for _, id in ipairs(record.recipientIds) do signalOrder(player, id, "follow") end
    end
    if cleared and KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("Party destination cancelled.")
    end
    return cleared, notified, cleared and "cancelled" or "no_destination"
end

function CompanionService.markPartyDestinationArrived(survivorId, revision)
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    local playerId = duty ~= nil and duty.mode == "companion" and duty.ownerId or nil
    local record = playerId ~= nil and CompanionService.getPartyDestination(playerId) or nil
    if record == nil or tonumber(revision) ~= record.revision then return false end
    local included = false
    for _, id in ipairs(record.recipientIds) do
        if tostring(id) == tostring(survivorId) then included = true break end
    end
    if not included then return false end
    local character = KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.getCharacter ~= nil
        and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
    if character == nil then return false end
    local ok, x, y, z = pcall(function()
        return character:getX(), character:getY(), character:getZ()
    end)
    if not ok or tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil
        or tonumber(z) ~= record.destination.z then
        return false
    end
    local dx, dy = tonumber(x) - record.destination.minX,
        tonumber(y) - record.destination.minY
    if dx * dx + dy * dy > 2.25 then return false end
    record.arrived[tostring(survivorId)] = true
    for _, id in ipairs(record.recipientIds) do
        if not record.arrived[tostring(id)] then return true end
    end
    clearPartyDestinationRecord(playerId, "arrived")
    if KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("All eligible companions reached the party destination.")
    end
    return true
end

function CompanionService.issueOrderAll(player, kind, payload)
    local companionFailure
    local resolved, resolveResult
    if KnoxOrderCatalog.resolve ~= nil then
        resolved, resolveResult = KnoxOrderCatalog.resolve(kind)
    end
    local normalizedKind = resolved ~= nil and resolved.kind
        or KnoxOrderCatalog.normalize(kind)
    if normalizedKind == nil or (resolved == nil and not KnoxOrderCatalog.isKnown(normalizedKind)) then
        return false, 0, resolveResult or "unknown_order"
    end
    -- Keep payload-bearing patrol calls on the area-directive path.  Without
    -- this, the shared `patrol` label is treated as a base preference and the
    -- selected patrol area never reaches the party directive executor.
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end

    if normalizedKind == "follow" or normalizedKind == "hold" or normalizedKind == "relax" then
        return CompanionService.commandAll(player, normalizedKind)
    end
    if normalizedKind == "return_to_base" then
        local changed, firstFailure = 0, nil
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success, reason = CompanionService.sendToBase(player, survivorId)
            if not success and firstFailure == nil then firstFailure = reason end
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "returned" or firstFailure or "no_companions"
    end
    if normalizedKind == "resume_normal_duty" then
        local _, changed, firstFailure = CompanionService.clearDirectiveAll(player)
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base ~= nil and KnoxPersistence.getBaseResidentIds ~= nil then
            for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
                local success, reason = CompanionService.clearBaseSupplyOrder(player, residentId)
                if not success and firstFailure == nil then firstFailure = reason end
                if success then changed = changed + 1 end
            end
        end
        return changed > 0, changed, changed > 0 and "cleared" or firstFailure or "no_directives"
    end
    -- Party actions reuse the existing per-member service methods. Recruit and
    -- dismiss intentionally remain individual-only so a broad click cannot
    -- change ownership for the whole party accidentally.
    if normalizedKind == "check_needs" then
        return CompanionService.askNeedsAll(player)
    end
    if normalizedKind == "go_to" and payload ~= nil then
        return CompanionService.issuePartyDestination(player, payload)
    end
    if normalizedKind == "enter_vehicle" then
        local success, changed, waiting, reason = CompanionService.boardAllPlayerVehicle(player)
        return success, changed, reason
    end
    if normalizedKind == "let_companion_drive" then
        local success, reason = CompanionService.letCompanionDrive(player)
        return success, success and 1 or 0, reason
    end
    if normalizedKind == "take_wheel" then
        local success, reason = CompanionService.takeWheel(player)
        return success, success and 1 or 0, reason
    end
    if normalizedKind == "exit_vehicle" then
        return CompanionService.exitAllVehicles(player)
    end
    if normalizedKind == "allow_climbing"
        or normalizedKind == "disallow_climbing" then
        local success, changed, reason = CompanionService.setClimbingAll(
            player,
            normalizedKind == "allow_climbing"
        )
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    if normalizedKind == "allow_doors"
        or normalizedKind == "disallow_doors" then
        local success, changed, reason = CompanionService.setDoorOpeningAll(
            player,
            normalizedKind == "allow_doors"
        )
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    if normalizedKind == "enable_autoloot"
        or normalizedKind == "disable_autoloot" then
        local success, changed, reason = CompanionService.setAutoLootAll(
            player,
            normalizedKind == "enable_autoloot"
        )
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    if normalizedKind == "combat_stance" then
        local stance = type(payload) == "table" and payload.stance or payload
        local success, changed, reason = CompanionService.setCombatStanceAll(player, stance)
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    if normalizedKind == "weapon_preference" then
        local preference = type(payload) == "table" and payload.preference or payload
        local success, changed, reason = CompanionService.setWeaponPreferenceAll(player, preference)
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    -- Without a selected area, resolve search orders per companion so each
    -- survivor searches near its own current body.  A shared player-centred
    -- directive would make a separated party converge on one stale square.
    if payload == nil and SEARCH_DIRECTIVES[normalizedKind] then
        local changed, firstFailure = 0, nil
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success, reason = CompanionService.issueOrder(player, survivorId, normalizedKind)
            if not success and firstFailure == nil then firstFailure = reason end
            if success then changed = changed + 1 end
        end
        -- A party-wide resource order also reaches the player's base
        -- residents. Their service path persists a base supply request rather
        -- than converting them into companions, so both populations keep
        -- their existing ownership models.
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base ~= nil and KnoxPersistence.getBaseResidentIds ~= nil
            and KnoxPersistence.getSurvivorDuty ~= nil then
            for _, survivorId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
                local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
                if duty.mode == "base" then
                    local success, reason = CompanionService.issueOrder(player, survivorId, normalizedKind)
                    if not success and firstFailure == nil then firstFailure = reason end
                    if success then changed = changed + 1 end
                end
            end
        end
        return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
    end
    -- Guard/Patrol are also valid base preferences, but a party-wide command
    -- with no selected area should still reach travelling companions. Resolve
    -- each companion locally; base residents continue through the preference
    -- path below and keep their persistent settlement duty.
    if payload == nil and (normalizedKind == "guard"
        or normalizedKind == "patrol" or normalizedKind == "patrol_area") then
        local changed, firstFailure = 0, nil
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success, reason = CompanionService.issueOrder(player, survivorId, normalizedKind)
            if not success and firstFailure == nil then firstFailure = reason end
            if success then changed = changed + 1 end
        end
        if changed > 0 then
            return true, changed, "updated"
        end
        companionFailure = firstFailure
    end
    if payload ~= nil and KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, result = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, 0, result
        end
        local success, changed, reason = CompanionService.issueDirectiveAll(player, directive)
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    if KnoxOrderCatalog.isBasePreference(normalizedKind) then
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base == nil or KnoxPersistence.getBaseResidentIds == nil then
            return false, 0, companionFailure or "no_player_base"
        end
        local changed, firstFailure = 0, nil
        for _, survivorId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
            local success, reason = CompanionService.setBaseJobPreference(
                player, survivorId, normalizedKind
            )
            if not success and firstFailure == nil then firstFailure = reason end
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "updated" or firstFailure or companionFailure or "no_residents"
    end
    local taskPreference = KnoxOrderCatalog.preferenceForTask ~= nil
        and KnoxOrderCatalog.preferenceForTask(normalizedKind) or nil
    if taskPreference ~= nil then
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base == nil or KnoxPersistence.getBaseResidentIds == nil then
            return false, 0, companionFailure or "no_player_base"
        end
        local changed, firstFailure = 0, nil
        for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
            local success, reason = CompanionService.setBaseJobPreference(
                player, residentId, taskPreference
            )
            if not success and firstFailure == nil then firstFailure = reason end
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "updated" or firstFailure or companionFailure or "no_residents"
    end
    if companionFailure ~= nil and payload == nil then
        return false, 0, companionFailure
    end
    if KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, result = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, 0, result
        end
        local success, changed, reason = CompanionService.issueDirectiveAll(player, directive)
        return success, changed, reason or (success and "updated" or "no_companions")
    end
    return false, 0, "order_not_party_executable"
end

function CompanionService.boardAllPlayerVehicle(player)
    local boarded, waiting, firstFailure = 0, 0, nil
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, result = CompanionService.boardPlayerVehicle(player, survivorId)
        if not success and firstFailure == nil then firstFailure = result end
        boarded = boarded + (success and 1 or 0)
        waiting = waiting + (result == "no_free_passenger_seat" and 1 or 0)
    end
    if boarded > 0 then
        KnoxActivityFeed.event("Party order: get in the vehicle.")
    elseif waiting > 0 then
        KnoxActivityFeed.event("No passenger seats are available.")
    end
    return boarded > 0, boarded, waiting, boarded > 0 and "boarded" or firstFailure or "no_companions"
end

function CompanionService.exitAllVehicles(player)
    local exited, firstFailure = 0, nil
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.exitVehicle(player, survivorId)
        if not success and firstFailure == nil then firstFailure = reason end
        exited = exited + (success and 1 or 0)
    end
    if exited > 0 then
        KnoxActivityFeed.event("Party order: get out of the vehicle.")
    end
    return exited > 0, exited, exited > 0 and "exited" or firstFailure or "no_companions"
end

function CompanionService.setFormation(player, survivorId, formation, spacing, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "formation", batch, formation)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionFormation(
        survivorId, playerId, formation, spacing, worldAge()) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    signalOrder(player, survivorId, "formation")
    return true, "formation_updated"
end

function CompanionService.setCombatStance(player, survivorId, stance, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "combat_stance", batch, stance)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionCombatStance(
        survivorId, playerId, stance, worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        local lines = {
            passive = "I'll stay close and keep my head down.",
            defensive = "I'll cover us, but I won't chase them.",
            aggressive = "I'll clear anything I see.",
        }
        KnoxActivityFeed.speak(character, lines[stance] or "I'll adjust.")
    end
    signalOrder(player, survivorId, "combat_stance")
    return true, stance
end

function CompanionService.setCombatStanceAll(player, stance)
    local batch = {}
    local firstFailure
    if stance ~= "passive" and stance ~= "defensive" and stance ~= "aggressive" then
        return false, 0, "invalid_stance"
    end
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setCombatStance(player, survivorId, stance, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        local labels = {
            passive = "stay close",
            defensive = "protect the party",
            aggressive = "clear threats",
        }
        KnoxActivityFeed.event("Party combat stance: " .. (labels[stance] or stance) .. ".")
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.setWeaponPreference(player, survivorId, preference, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "weapon_preference", batch, preference)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionWeaponPreference(
        survivorId, playerId, preference, worldAge()
    ) then return false, "invalid_companion_weapon_preference" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    signalOrder(player, survivorId, "weapon_preference")
    return true, preference
end

function CompanionService.setWeaponPreferenceAll(player, preference)
    local batch = {}
    local firstFailure
    if preference ~= "melee" and preference ~= "ranged" and preference ~= "auto" then
        return false, 0, "invalid_weapon_preference"
    end
    local changed = 0
    for _, id in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setWeaponPreference(player, id, preference, batch)
        if success then changed = changed + 1
        elseif firstFailure == nil then firstFailure = reason end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.setAutoEquipment(player, survivorId, allowed, quiet, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId,
        allowed == true and "enable_auto_equipment" or "disable_auto_equipment", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or (allowed ~= true and allowed ~= false)
        or KnoxPersistence.setPlayerAutoEquipment == nil
        or not KnoxPersistence.setPlayerAutoEquipment(
            survivorId, playerId, allowed, worldAge()
        ) then
        return false, "not_your_survivor"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    pcall(function()
        local controller = KnoxSurvivorRuntime.getController ~= nil
            and KnoxSurvivorRuntime.getController(survivorId) or nil
        if controller ~= nil and controller.setAutoEquipmentPolicy ~= nil then
            controller:setAutoEquipmentPolicy(allowed)
        end
    end)
    signalOrder(player, survivorId,
        allowed and "enable_auto_equipment" or "disable_auto_equipment")
    if not quiet then
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, allowed
                and "I'll improve my gear when I find something better."
                or "I'll keep the gear I'm using.")
        end

    end
    return true, allowed and "auto_equipment_enabled" or "auto_equipment_disabled"
end

function CompanionService.setAutoEquipmentAll(player, allowed)
    local batch = {}
    local firstFailure
    if allowed ~= true and allowed ~= false then
        return false, 0, "invalid_auto_equipment_policy"
    end
    local changed, members = 0, {}
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setAutoEquipment(player, survivorId, allowed, true, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        if success then
            changed = changed + 1
            local character = KnoxSurvivorRuntime.getCharacter(survivorId)
            if character ~= nil then members[#members + 1] = character end
        end
    end
    if changed > 0 then
        KnoxActivityFeed.event(allowed
            and "Party automatic equipment upgrades enabled."
            or "Party automatic equipment upgrades disabled.")
        local signals = rawget(_G, "KnoxOrderSignals")
        if signals ~= nil and signals.group ~= nil then
            signals.group(player, members,
                allowed and "enable_auto_equipment" or "disable_auto_equipment")
        end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.boardPlayerVehicle(player, survivorId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "enter_vehicle")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player, survivorId) then return false, "not_companion" end
    local character, reason = validateInteraction(player, survivorId, 30 * 30)
    if character == nil then return false, reason end
    local vehicle = player:getVehicle()
    if vehicle == nil then return false, "player_not_in_vehicle" end
    local success, result = KnoxCompanionVehicles.board(character, vehicle)
    if success then
        CompanionService.excludePartyDestinationRecipient(player, survivorId)
        local seat = tostring(result or ""):match("boarding_seat=(%d+)")
        KnoxActivityFeed.speak(character, seat ~= nil
            and "Taking passenger seat " .. seat .. "." or "Taking a passenger seat.")
        signalOrder(player, survivorId, "enter_vehicle")
    elseif result == "no_free_passenger_seat" then
        KnoxActivityFeed.speak(character, "I'll wait here. No more seats.")
    end
    return success, result
end

-- DRIVING SETTING GATE
local function speakDrivingRefusal(result)
    if result ~= "npc_driving_disabled" then return end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    local text = catalog ~= nil and catalog.failureText ~= nil
        and catalog.failureText(result)
        or "Experimental NPC driving is off. Enable it in Sandbox Options, Vehicles page."
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then feed.event(text) end
end

local function drivingEnabled()
    local settings = rawget(_G, "KnoxSettings")
    return settings ~= nil and settings.enableExperimentalNpcDriving ~= nil
        and settings.enableExperimentalNpcDriving() == true
end

local function refuseDriving()
    speakDrivingRefusal("npc_driving_disabled")
    return false, "npc_driving_disabled"
end

function CompanionService.drivePlayerVehicle(player, survivorId)
    if not drivingEnabled() then return refuseDriving() end
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "drive_ahead")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player, survivorId) then return false, "not_companion" end
    local character, reason = validateInteraction(player, survivorId, 30 * 30)
    if character == nil then return false, reason end
    local vehicle = player:getVehicle()
    if vehicle == nil then return false, "player_not_in_vehicle" end
    if vehicle.isDriver ~= nil and vehicle:isDriver(player) then
        KnoxActivityFeed.speak(character, "You need to leave the driver's seat first.")
        return false, "player_must_vacate_driver_seat"
    end
    local success, result = KnoxCompanionVehicles.driveAhead(character, vehicle)
    if success then
        CompanionService.excludePartyDestinationRecipient(player, survivorId)
        KnoxActivityFeed.speak(character, "Taking the driver's seat. I'll drive us ahead.")
    else
        speakDrivingRefusal(result)
    end
    return success, result
end

function CompanionService.drivePlayerVehicleTo(player,survivorId,x,y)
    if not drivingEnabled() then return refuseDriving() end
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "drive_ahead")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player,survivorId) then return false,"not_companion" end
    local character,reason=validateInteraction(player,survivorId,30*30)
    if character==nil then return false,reason end
    local vehicle=player:getVehicle()
    if vehicle==nil then return false,"player_not_in_vehicle" end
    if vehicle:getDriver()==player then
        KnoxActivityFeed.speak(character,"You need to leave the driver's seat first.")
        return false,"player_must_vacate_driver_seat"
    end
    local square=vehicle:getSquare()
    if square==nil then return false,"vehicle_unavailable" end    local success,result=KnoxCompanionVehicles.driveTo(character,vehicle,x,y,square:getZ())
    if success then
        CompanionService.excludePartyDestinationRecipient(player,survivorId) KnoxActivityFeed.speak(character,"Taking the driver's seat. I'll drive us there.")
    else
        speakDrivingRefusal(result)
    end
    return success,result
end

-- Fetch order: the player is on foot, so there is no car to take the wheel of.
-- A companion brings the nearest car they can actually drive to the point the
-- player picked, using the same drive run and admission as every other trip.
-- No vehicle is spawned, moved or unlocked here.
function CompanionService.sendVehicleTo(player,survivorId,x,y,z)
    if not drivingEnabled() then return refuseDriving() end
    if player==nil or player:getVehicle()~=nil then return false,"player_in_vehicle" end
    local ok,delivered,delivery=pcall(CompanionService.deliverOrder,player,survivorId,"drive_ahead")
    if not ok then return false,"order_unavailable" end
    if not delivered then return false,delivery end
    if not isPlayerCompanion(player,survivorId) then return false,"not_companion" end
    local character=KnoxSurvivorRuntime.getCharacter(survivorId)
    if character==nil or character:isDead() then return false,"survivor_unavailable" end
    local travel=rawget(_G,"KnoxNpcVehicleTravel")
    if travel==nil or travel.readyVehicleNear==nil then return false,"vehicle_state_unknown" end
    local vehicle,reason=travel.readyVehicleNear(character)
    if vehicle==nil then return false,reason end
    local square=vehicle:getSquare()
    if square==nil then return false,"vehicle_unavailable" end
    local success,result=KnoxCompanionVehicles.driveTo(character,vehicle,x,y,tonumber(z) or square:getZ())
    if success and KnoxActivityFeed~=nil then
        KnoxActivityFeed.speak(character,"I'm bringing a car over.")
    end
    return success,result
end

function CompanionService.driveNearestVehicle(player, survivorId)
    if not drivingEnabled() then return refuseDriving() end
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "drive_nearest_vehicle")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player, survivorId) then return false, "not_companion" end
    if player == nil or player:getVehicle() ~= nil then return false, "player_in_vehicle" end
    local character, reason = validateInteraction(player, survivorId, 30 * 30)
    if character == nil then return false, reason end
    local success, result, vehicle = KnoxCompanionVehicles.driveNearest(character, 30)
    if success then
        CompanionService.excludePartyDestinationRecipient(player, survivorId)
        KnoxActivityFeed.speak(character, "I'll take the nearest usable car and drive ahead.")
        signalOrder(player, survivorId, "drive_nearest_vehicle")
    else
        speakDrivingRefusal(result)
    end
    return success, result, vehicle
end

-- The player keeps the seat decision. This service only asks a real companion
-- to wait for the driver seat and records the order; the companion boards only
-- after the player switches to a passenger seat with the native control.
function CompanionService.letCompanionDrive(player, survivorId)
    if not drivingEnabled() then return refuseDriving() end
    if player == nil or player:getVehicle() == nil then
        return false, "player_not_in_vehicle"
    end
    local vehicle = player:getVehicle()
    if vehicle.isDriver ~= nil and not vehicle:isDriver(player) then
        return false, "player_not_driving"
    end
    local batch = {}
    if survivorId ~= nil then
        if not isPlayerCompanion(player, survivorId) then return false, "not_companion" end
        local character, reason = validateInteraction(player, survivorId, 18 * 18)
        if character == nil then return false, reason end
        local delivered, delivery = CompanionService.deliverOrder(
            player, survivorId, "drive_ahead", batch)
        if not delivered then return false, delivery end
        local success, result = KnoxCompanionVehicles.beginHandoff(player, character, vehicle)
        if success then
            CompanionService.excludePartyDestinationRecipient(player, survivorId)
            signalOrder(player, survivorId, "drive_ahead")
        else
            speakDrivingRefusal(result)
        end
        return success, result
    end
    local firstFailure
    for _, id in ipairs(CompanionService.getCompanionIds(player)) do
        local character, reason = validateInteraction(player, id, 18 * 18)
        if character ~= nil then
            local success, result = KnoxCompanionVehicles.beginHandoff(player, character, vehicle)
            if success then
                CompanionService.excludePartyDestinationRecipient(player, id)
                signalOrder(player, id, "drive_ahead")
                return true, result
            end
            if firstFailure == nil then firstFailure = result end
        elseif firstFailure == nil then
            firstFailure = reason
        end
    end
    return false, firstFailure or "no_companions"
end

-- The companion releases the wheel through the native seat switch. This owner
-- only accepts a driver the player already owns; a stranger's car is not
-- commandeered by a party order.
function CompanionService.takeWheel(player)
    if not drivingEnabled() then return refuseDriving() end
    if player == nil then return false, "invalid_player" end
    local vehicle = player:getVehicle()
    if vehicle == nil and KnoxCompanionVehicles.findDrivenVehicleNear ~= nil then
        vehicle = KnoxCompanionVehicles.findDrivenVehicleNear(player, 5)
    end
    if vehicle == nil then return false, "vehicle_unavailable" end
    local driver = vehicle.getDriver ~= nil and vehicle:getDriver() or nil
    if driver == nil then return false, "no_driver" end
    if driver == player then return false, "already_driving" end
    local driverId = KnoxSurvivorRuntime.idForCharacter(driver)
    local playerId = CompanionService.getPlayerId(player)
    local duty = driverId ~= nil and KnoxPersistence.getSurvivorDuty(driverId) or nil
    if driverId == nil or playerId == nil or duty == nil or duty.ownerId ~= playerId
        or (duty.mode ~= "companion" and duty.mode ~= "base") then
        return false, "not_your_survivor"
    end
    local success, result = KnoxCompanionVehicles.beginTakeover(player, driver, vehicle)
    if not success then speakDrivingRefusal(result) end
    if success and KnoxActivityFeed ~= nil and KnoxActivityFeed.event ~= nil then
        KnoxActivityFeed.event("The driver is moving over. Take the wheel.")
    end
    return success, result
end

-- END DRIVING SETTING GATE
function CompanionService.stopPlayerVehicle(player,survivorId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "hold")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player,survivorId) then return false,"not_companion" end
    local character,reason=validateInteraction(player,survivorId,30*30)
    if character==nil then return false,reason end
    local vehicle=player:getVehicle()
    if vehicle==nil or character:getVehicle()~=vehicle then return false,"vehicle_unavailable" end
    return KnoxCompanionVehicles.stopDriving(character)
end

-- Unstick: teleport a stuck companion/resident to the nearest free tile by
-- the player (falling back to the survivor's own neighbourhood). Uses the
-- same setX/setY + setMovingSquareNow placement the persistence restore
-- path relies on; the autonomy movement watchdog re-decides from there.
function CompanionService.unstick(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if playerId == nil or affiliation == nil or affiliation.kind ~= "player"
        or (affiliation.ownerId ~= playerId and affiliation.ownerId ~= nil) then
        return false, "not_your_survivor"
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or character == nil or getCell == nil or getCell() == nil then
        return false, "unavailable"
    end
    local fromSquare = character:getCurrentSquare()
    local anchor = player:getCurrentSquare()
    local fx, fy, fz = nil, nil, nil
    if anchor ~= nil then
        for radius = 0, 6 do
            local found = nil
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if found == nil
                        and math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = getCell():getGridSquare(
                            anchor:getX() + dx, anchor:getY() + dy, anchor:getZ())
                        if square ~= nil and square:canStand() then
                            found = square
                        end
                    end
                end
            end
            if found ~= nil then
                fx, fy, fz = found:getX(), found:getY(), found:getZ()
                break
            end
        end
    end
    if fx == nil and fromSquare ~= nil then
        for radius = 0, 6 do
            local found = nil
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if found == nil
                        and math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = getCell():getGridSquare(
                            fromSquare:getX() + dx, fromSquare:getY() + dy,
                            fromSquare:getZ())
                        if square ~= nil and square:canStand() then
                            found = square
                        end
                    end
                end
            end
            if found ~= nil then
                fx, fy, fz = found:getX(), found:getY(), found:getZ()
                break
            end
        end
    end
    if fx == nil then return false, "no_free_tile" end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil and bridge.cancelNpcMove ~= nil then
        pcall(function() bridge:cancelNpcMove(survivorId) end)
    end
    local placed, placeError = pcall(function()
        character:setX(fx + 0.5)
        character:setY(fy + 0.5)
        character:setMovingSquareNow()
    end)
    if not placed then return false, "teleport_failed:" .. tostring(placeError) end
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("movement", survivorId, "unstuck", {
            x = fx, y = fy, z = fz,
        }) end)
    end
    -- Unstick is a reset, not only a reposition. The decision that put her
    -- here still owns her posture, her queued actions and her reservations, so
    -- moving the body without dropping it leaves her just as stuck two tiles
    -- over. The controller's existing abandon path owns that cleanup: it
    -- cancels the move, clears the timed-action queue, wakes a seated
    -- survivor and releases the rest spot. Identity, clothing, needs, skills
    -- and inventory are untouched.
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local controller = runtime ~= nil and runtime.getController ~= nil
        and runtime.getController(survivorId) or nil
    if controller ~= nil and controller.abandonCurrentDecision ~= nil then
        pcall(function()
            controller:abandonCurrentDecision(controller.currentTicks or 0, "unstuck")
        end)
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    if KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "Thanks, I was stuck.")
    end
    signalOrder(player, survivorId, "signalok")
    return true, "unstuck"
end

function CompanionService.exitVehicle(player, survivorId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "exit_vehicle")
    if not delivered then return false, delivery end
    if not isPlayerCompanion(player, survivorId) then return false, "not_companion" end
    local character, reason = validateInteraction(player, survivorId)
    if character == nil then return false, reason end
    local success, result = KnoxCompanionVehicles.exit(character)
    if success then
        CompanionService.excludePartyDestinationRecipient(player, survivorId)
        KnoxActivityFeed.speak(character, "Getting out.")
        signalOrder(player, survivorId, "exit_vehicle")
    end
    return success, result
end

local MEDICAL_REPLIES = {
    automatic_medical_off="Automatic help is off. Ask me directly.",
    patient_unavailable="I can't find you.", medical_busy="I'm already tending to something. Give me a moment.",
    treatment_not_allowed="I can't treat you with the current medical permissions.",
    unsafe_to_treat="It's not safe to treat you right now.", own_needs_first="I need to take care of myself first.",
    medical_too_far="Come closer, on this floor.", no_treatable_bleeding="I don't have a treatment I can use on that injury.",
    treatment_unavailable="I can't provide that treatment right now.", no_bandage="I haven't got a bandage or usable cloth.",
    work_step_finishing="Let me finish this step first.", medical_route_blocked="I can't get to you from here.",
    medical_help_started="Stay still. I'll help with that wound.",
}

function CompanionService.requestMedicalHelp(player, survivorId)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "medical_help")
    if not delivered then return false, reason end
    local controller = KnoxSurvivorRuntime.getController and KnoxSurvivorRuntime.getController(survivorId)
    if controller == nil or controller.requestMedicalAid == nil then return false, "survivor_unavailable" end
    local accepted, result = controller:requestMedicalAid(player, controller.currentTicks or 0, false)
    local line = MEDICAL_REPLIES[result] or "I can't help with that wound right now."
    socialSpeech(controller.character, survivorId, "medical_help", line)
    return accepted, line
end

function CompanionService.setAutoMedical(player, survivorId, allowed)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId,
        allowed and "enable_auto_medical" or "disable_auto_medical")
    if not delivered then return false, reason end
    local owner = CompanionService.getPlayerId(player)
    if not KnoxPersistence.setSurvivorAutoMedical(survivorId, owner, allowed, worldAge()) then
        return false, "not_your_survivor"
    end
    return true, allowed and "Auto Medical: On" or "Auto Medical: Off"
end

function CompanionService.setClimbing(player, survivorId, allowed, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId,
        allowed == true and "allow_climbing" or "disallow_climbing", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionClimbing(
        survivorId,
        playerId,
        allowed,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    signalOrder(player, survivorId,
        allowed == true and "allow_climbing" or "disallow_climbing")
    return true, allowed == true and "climbing_allowed" or "climbing_disabled"
end

function CompanionService.setClimbingAll(player, allowed)
    local batch = {}
    local firstFailure
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setClimbing(player, survivorId, allowed, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        KnoxActivityFeed.event(allowed
            and "Party traversal: vaulting and climbing allowed."
            or "Party traversal: vaulting and climbing disabled.")
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.setDoorOpening(player, survivorId, allowed, quiet, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId,
        allowed == true and "allow_doors" or "disallow_doors", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionDoorOpening(
        survivorId,
        playerId,
        allowed,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    -- Apply immediately to the live controller so the toggle changes behavior
    -- on this tick, not just after the next duty sync (which the sync cache
    -- could otherwise delay). Persistence remains the authority on reload.
    pcall(function()
        local controller = KnoxSurvivorRuntime.getController ~= nil
            and KnoxSurvivorRuntime.getController(survivorId) or nil
        if controller ~= nil and controller.setDoorWindowOpeningPolicy ~= nil then
            controller:setDoorWindowOpeningPolicy(allowed == true)
        end
    end)
    signalOrder(player, survivorId,
        allowed == true and "allow_doors" or "disallow_doors")
    if not quiet then
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, allowed == true
                and "I'll use doors and windows."
                or "I won't touch doors or windows.")
        end

    end
    return true, allowed == true and "doors_allowed" or "doors_disabled"
end

function CompanionService.setAutoLoot(player, survivorId, allowed, quiet, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId,
        allowed == true and "enable_autoloot" or "disable_autoloot", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionAutoLoot(
        survivorId,
        playerId,
        allowed,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    -- Same immediate-apply pattern as door permission: the toggle changes
    -- behavior on this tick. Persistence remains the authority on reload.
    pcall(function()
        local controller = KnoxSurvivorRuntime.getController ~= nil
            and KnoxSurvivorRuntime.getController(survivorId) or nil
        if controller ~= nil and controller.setAutoLootPolicy ~= nil then
            controller:setAutoLootPolicy(allowed == true)
        end
    end)
    signalOrder(player, survivorId,
        allowed == true and "enable_autoloot" or "disable_autoloot")
    if not quiet then
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, allowed == true
                and "I'll pick up useful things nearby and look for food when we're settled."
                or "I won't pick anything up.")
        end

    end
    return true, allowed == true and "autoloot_enabled" or "autoloot_disabled"
end

function CompanionService.setAutoLootAll(player, allowed)
    local batch = {}
    local firstFailure
    local changed, members = 0, {}
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setAutoLoot(player, survivorId, allowed, true, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        if success then
            changed = changed + 1
            local character = KnoxSurvivorRuntime.getCharacter(survivorId)
            if character ~= nil then members[#members + 1] = character end
        end
    end
    if changed > 0 then
        KnoxActivityFeed.event(allowed
            and "Party auto-loot enabled."
            or "Party auto-loot disabled.")
        local signals = rawget(_G, "KnoxOrderSignals")
        if signals ~= nil and signals.group ~= nil then
            signals.group(player, members,
                allowed == true and "enable_autoloot" or "disable_autoloot")
        end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.setDoorOpeningAll(player, allowed)
    local batch = {}
    local firstFailure
    local changed, members = 0, {}
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.setDoorOpening(player, survivorId, allowed, true, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        if success then
            changed = changed + 1
            local character = KnoxSurvivorRuntime.getCharacter(survivorId)
            if character ~= nil then members[#members + 1] = character end
        end
    end
    if changed > 0 then
        KnoxActivityFeed.event(allowed
            and "Party doors: opening doors and windows allowed."
            or "Party doors: opening doors and windows disabled.")
        local signals = rawget(_G, "KnoxOrderSignals")
        if signals ~= nil and signals.group ~= nil then
            signals.group(player, members,
                allowed == true and "allow_doors" or "disallow_doors")
        end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.issueDirective(player, survivorId, directive, suppressSignal, batch)
    local playerId = CompanionService.getPlayerId(player)
    if type(directive) ~= "table" then
        return false, "invalid_directive"
    end
    -- Keep direct callers on the same canonical boundary as issueOrder. This
    -- accepts familiar legacy labels while persisting only the current Knox
    -- directive vocabulary and preserves all caller-supplied target fields.
    local normalizedKind = KnoxOrderCatalog.normalize(directive.kind)
    if not KnoxOrderCatalog.isDirective(normalizedKind) then
        return false, "invalid_directive"
    end
    if normalizedKind ~= directive.kind then
        local canonical = {}
        for key, value in pairs(directive) do canonical[key] = value end
        canonical.kind = normalizedKind
        directive = canonical
    end
    if KnoxSurvivorRuntime.canAcceptOrders ~= nil then
        local accepted, reason = KnoxSurvivorRuntime.canAcceptOrders(survivorId)
        if not accepted then return false, reason end
    end
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, directive.kind, batch)
    if not delivered then return false, delivery end
    if playerId == nil or not KnoxPersistence.setCompanionDirective(
        survivorId,
        playerId,
        directive,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    CompanionService.excludePartyDestinationRecipient(player, survivorId)
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        local lines = {
            go_to = "I'm heading there.", guard = "I'll hold that position.",
            patrol_area = "I'll patrol it.", loot_area = "I'll search the area.",
            loot_building = "I'll search the building.", loot_corpses = "I'll check the bodies.",
            find_food = "I'll look for food.", find_water = "I'll look for water.",
            find_medical = "I'll look for medical supplies.", find_weapon = "I'll look for a weapon.",
            find_tools = "I'll look for tools.", clean_inventory = "I'll sort my pack.",
        }
        KnoxActivityFeed.speak(character, lines[directive.kind] or "I'll take care of it.")
    end
    signalOrder(player, survivorId, directive.kind)
    return true, tostring(directive.kind)
end

function CompanionService.issueDirectiveAll(player, directive)
    local batch = {}
    local firstFailure
    local changed = 0
    local members = {}
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.issueDirective(player, survivorId, directive, true, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        changed = changed + (success and 1 or 0)
        if success then
            local character = KnoxSurvivorRuntime.getCharacter(survivorId)
            if character ~= nil then members[#members + 1] = character end
        end
    end
    if changed > 0 then
        local label = KnoxOrderCatalog.label(directive.kind, "New task.")
        KnoxActivityFeed.event("Party order: " .. label .. ".")
        local signals = rawget(_G, "KnoxOrderSignals")
        if signals ~= nil and signals.group ~= nil then
            signals.group(player, members, directive.kind)
        end
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.clearDirective(player, survivorId, batch)
    local playerId = CompanionService.getPlayerId(player)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "follow", batch)
    if not delivered then return false, reason end
    if playerId == nil or not KnoxPersistence.clearCompanionDirective(
        survivorId, playerId, worldAge()
    ) then
        return false, "not_your_companion"
    end
    CompanionService.excludePartyDestinationRecipient(player, survivorId)
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        KnoxActivityFeed.speak(character, "I'll get back to my usual orders.")
    end
    signalOrder(player, survivorId, "follow")
    return true, "cleared"
end

function CompanionService.clearDirectiveAll(player)
    local batch = {}
    local firstFailure
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, reason = CompanionService.clearDirective(player, survivorId, batch)
        if not success and firstFailure == nil then firstFailure = reason end
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        KnoxActivityFeed.event("Party order cleared: resume normal duty.")
    end
    return changed > 0, changed, changed > 0 and "updated" or firstFailure or "no_companions"
end

function CompanionService.sendToBase(player, survivorId, baseId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "return_to_base")
    if not delivered then return false, delivery end
    local playerId = CompanionService.getPlayerId(player)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = nil
    if type(baseId) == "string" and KnoxPersistence.getBase ~= nil then
        base = KnoxPersistence.getBase(baseId)
        if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
            return false, "not_your_base"
        end
    else
        base = manager ~= nil and manager.getForOwner ~= nil
            and manager.getForOwner("player", playerId)
            or nil
    end
    if base == nil then
        return false, "no_player_base"
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local saved, result = KnoxPersistence.setPlayerBaseResident(
        survivorId,
        playerId,
        base.id,
        worldAge()
    )
    if saved then
        CompanionService.excludePartyDestinationRecipient(player, survivorId)
        CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, "I'll head back and help out there.")
        end
        signalOrder(player, survivorId, "return_to_base")
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        if character ~= nil and autonomy ~= nil and autonomy.beginVirtualBaseReturn ~= nil then
            local handedOff, handoffResult = autonomy.beginVirtualBaseReturn(survivorId, base.id)
            if handedOff then
                KnoxActivityFeed.event("A companion started the trip back to base.")
                return true, handoffResult
            end
        end
    end
    return saved, result
end

local function resolveOwnedPlayerBase(playerId, requestedBaseId)
    if playerId == nil then return nil end
    local manager = rawget(_G, "KnoxBaseManager")
    if manager == nil then return nil end
    local base
    if requestedBaseId ~= nil then
        base = manager.get ~= nil and manager.get(requestedBaseId) or nil
    else
        base = manager.getForOwner ~= nil
            and manager.getForOwner("player", playerId) or nil
    end
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
        return nil
    end
    return base
end

function CompanionService.setBaseJobPreference(player, survivorId, preference, requestedBaseId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "job")
    if not delivered then return false, delivery end
    local normalizedPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(preference)
        or KnoxOrderCatalog.normalize(preference)
    if normalizedPreference == nil or not KnoxOrderCatalog.isBasePreference(normalizedPreference) then
        return false, "unknown_base_preference"
    end
    local playerId = CompanionService.getPlayerId(player)
    local base = resolveOwnedPlayerBase(playerId, requestedBaseId)
    local previousDuty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local previousPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(previousDuty.jobPreference)
        or KnoxOrderCatalog.normalize(previousDuty.jobPreference)
    if base == nil or not KnoxPersistence.setBaseJobPreference(
        survivorId, playerId, base.id, normalizedPreference, worldAge()
    ) then
        return false, "not_your_base_resident"
    end
    if previousPreference ~= normalizedPreference
        and normalizedPreference ~= "rest"
        and KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, base.id, "resident_preference_changed"
        )
    end
    if normalizedPreference == "rest"
        and KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, base.id, "resident_requested_rest"
        )
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        local lines = {
            auto = "I'll help wherever the base needs me.",
            guard = "I'll keep watch.",
            patrol = "I'll patrol the area.",
            farming = "I'll take care of the garden.",
            woodwork = "I'll handle timber and repairs.",
            barricade = "I'll board up the windows.",
            hauling = "I'll move the bodies to the drop area.",

            repair = "I'll handle maintenance.",
            scavenger = "I'll find what we need.",
            cook = "I'll keep the kitchen going.",
            farmer = "I'll tend the crops.",
            builder = "I'll fix what's broken.",
            medic = "I'll keep the bandages ready.",
            mechanic = "I'll keep the engines running.",
            quartermaster = "I'll keep the stores counted.",
            runner = "I'll carry word and supplies.",
            rest = "I'll rest and recover for now.",
        }
        KnoxActivityFeed.speak(character, lines[normalizedPreference]
            or ("I'll take the " .. KnoxOrderCatalog.label(normalizedPreference, "new") .. " duty."))
    end
    signalOrder(player, survivorId, normalizedPreference)
    return true, normalizedPreference
end

-- Duty-schedule write boundary for the base-tab UI. Ownership and shape are
-- enforced by persistence; a nil schedule clears back to "anything".
function CompanionService.setBaseDutySchedule(player, survivorId, schedule, requestedBaseId, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "job", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    local base = resolveOwnedPlayerBase(playerId, requestedBaseId)
    if base == nil or not KnoxPersistence.setBaseDutySchedule(
        survivorId, playerId, base.id, schedule, worldAge()
    ) then
        return false, "not_your_base_resident"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, schedule == nil
            and "I'll work whenever I'm needed."
            or "I'll keep to the new hours.")
    end
    return true, "schedule_updated"
end

-- Temporary current-block override. The saved rota is untouched; nil clears it.
function CompanionService.setBaseDutyScheduleOverride(player, survivorId, assignment, requestedBaseId)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "job")
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    local base = resolveOwnedPlayerBase(playerId, requestedBaseId)
    local saved
    if assignment == nil then
        saved = base ~= nil and KnoxPersistence.clearBaseDutyScheduleOverride(
            survivorId, playerId, base.id, worldAge()
        )
    else
        saved = base ~= nil and KnoxPersistence.setBaseDutyScheduleOverride(
            survivorId, playerId, base.id, assignment, worldAge()
        )
    end
    if not saved then return false, "not_your_base_resident" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, assignment == nil
            and "Back on the saved hours."
            or "I'll take the watch until the next block.")
    end
    return true, assignment == nil and "schedule_override_cleared" or "schedule_override_set"
end

-- Work-priority write boundary for the priorities-tab UI. Ownership and
-- shape are enforced by persistence; a nil map clears back to automatic.
function CompanionService.setBaseWorkPreferences(player, survivorId, preferences, requestedBaseId, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "job", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    local base = resolveOwnedPlayerBase(playerId, requestedBaseId)
    if base == nil or not KnoxPersistence.setBaseWorkPreferences(
        survivorId, playerId, base.id, preferences, worldAge()
    ) then
        return false, "not_your_base_resident"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, "preferences_updated"
end

CompanionService.setBaseWorkPriorities = CompanionService.setBaseWorkPreferences

function CompanionService.setBaseSupplyOrder(player, survivorId, kind)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "base_supply")
    if not delivered then return false, delivery end
    local normalized = KnoxOrderCatalog.normalize(kind)
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if not BASE_SUPPLY_ORDERS[normalized] or playerId == nil
        or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.setBaseSupplyOrder == nil then
        return false, "not_your_base_resident"
    end
    local saved = KnoxPersistence.setBaseSupplyOrder(
        survivorId, playerId, duty.baseId, normalized, worldAge(), 24
    )
    if not saved then return false, "not_your_base_resident" end
    if KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, duty.baseId, "resident_supply_ordered"
        )
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll look for "
            .. string.gsub(KnoxOrderCatalog.label(normalized), "^Find ", "") .. ".")
    end
    signalOrder(player, survivorId, normalized)
    return true, "base_supply_ordered"
end

function CompanionService.clearBaseSupplyOrder(player, survivorId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "follow")
    if not delivered then return false, delivery end
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if playerId == nil or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.clearBaseSupplyOrder == nil then
        return false, "not_your_base_resident"
    end
    if duty.baseSupplyOrder == nil then return false, "no_supply_order" end
    local cleared = KnoxPersistence.clearBaseSupplyOrder(
        survivorId, playerId, duty.baseId, worldAge()
    )
    if not cleared then return false, "not_your_base_resident" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll get back to my normal work.")
    end
    return true, "base_supply_cleared"
end

-- Per-resident loot-run permission: the player decides who may leave the
-- base on automatic shortage runs. There is no global switch; residents
-- stay home unless explicitly allowed here.
-- One named item, ordered through the supply-order field that already exists so
-- the resident leaves on the ordinary supply trip and the ordinary cancel path
-- clears it. Nothing about permission or ownership is re-implemented here.
function CompanionService.requestItemFetch(player, survivorId, fullType)
    local item = KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeItemType ~= nil
        and KnoxOrderCatalog.normalizeItemType(fullType) or nil
    if item == nil then return false, "invalid_item_type" end
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "base_supply")
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if playerId == nil or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.setBaseSupplyOrder == nil then
        return false, "not_your_base_resident"
    end
    local saved = KnoxPersistence.setBaseSupplyOrder(
        survivorId, playerId, duty.baseId, "find_materials", worldAge(), 24, item)
    if not saved then return false, "not_your_base_resident" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll look for a " .. item .. ".")
    end
    return true, "item_fetch_ordered"
end

function CompanionService.setResidentLootRuns(player, survivorId, allowed, batch)
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "base_supply", batch)
    if not delivered then return false, reason end
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if playerId == nil or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.setResidentLootRuns == nil then
        return false, "not_your_base_resident"
    end
    local saved = KnoxPersistence.setResidentLootRuns(
        survivorId, playerId, duty.baseId, allowed == true, worldAge()
    )
    if not saved then return false, "not_your_base_resident" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, allowed == true
            and "I'll run supplies when the base needs them."
            or "I'll stay home from now on.")
    end
    return true, allowed == true and "loot_runs_allowed" or "loot_runs_stay_home"
end

-- Base-to-base transfer for multi-home owners (Missions callbacks, base
-- picker flows). The existing persistence boundary validates the destination
-- before replacing duty (including supply intent) and requeueing old claims.
-- A rejected destination must leave current work intact.
function CompanionService.transferBaseResident(player, survivorId, baseId)
    local delivered, delivery = CompanionService.deliverOrder(player, survivorId, "return_to_base")
    if not delivered then return false, delivery end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or type(baseId) ~= "string" then
        return false, "invalid_transfer"
    end
    local now = worldAge()
    local saved, result = KnoxPersistence.setPlayerBaseResident(
        survivorId, playerId, baseId, now
    )
    if not saved then return false, result end
    CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, "transferred"
end
function CompanionService.recallToParty(player, survivorId)
    if KnoxSettings.enabled ~= nil and KnoxSettings.enabled() ~= true then
        return false, "mod_disabled"
    end
    local playerId = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if playerId == nil or affiliation == nil or affiliation.kind ~= "player"
        or affiliation.ownerId ~= playerId then
        return false, "not_your_survivor"
    end
    if KnoxPersistence.isSurvivorAlive(survivorId) ~= true then
        return false, "character_dead"
    end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil or duty.mode ~= "base" or duty.ownerId ~= playerId then
        return false, "not_base_resident"
    end
    if #CompanionService.getCompanionIds(player) >= KnoxSettings.companionLimit() then
        return false, "companion_limit"
    end
    -- A resident out on a base supply order is still yours to call back. The
    -- order was left open, which is why she kept reporting a supply run she
    -- never finished and why every order menu offered only Cancel Supply Order.
    -- Recall outranks routine work, so the order is closed before she is asked
    -- to follow, and the claim it held goes back to the queue.
    if type(duty.baseSupplyOrder) == "table" and KnoxPersistence.clearBaseSupplyOrder ~= nil then
        KnoxPersistence.clearBaseSupplyOrder(survivorId, playerId, duty.baseId, worldAge())
    end
    local delivered, reason = CompanionService.deliverOrder(player, survivorId, "follow")
    if not delivered then return false, reason end
    local saved, result = KnoxPersistence.setPlayerCompanion(
        survivorId,
        playerId,
        "follow",
        worldAge()
    )
    if saved then
        CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, "I'm joining your party.")
            signalOrder(player, survivorId, "follow")
        end
        KnoxActivityFeed.event(displayName(survivorId) .. " joined your party.")
    end
    return saved, saved and "joined_party" or result
end

-- Compatibility for callers that used the old internal name.  The public
-- recall boundary above adds ownership, duty, life-state and capacity checks.
-- STRANDED COMPANIONS
-- A companion who falls behind stays behind because nobody is simulating them
-- once they are unloaded. Two exits exist and both are real: if the player and
-- the survivor each carry a walkie, the survivor hears the call and walks back
-- to the player; if not, they survive where they were left and eventually make
-- their own way to the nearest base, where they stay as a resident rather than
-- remaining a companion nobody can reach.
CompanionService.STRANDED_DISTANCE = 80      -- tiles before "left behind"
CompanionService.STRANDED_WALKIE_HOURS = 2   -- hearing the radio
CompanionService.STRANDED_ALONE_HOURS = 36   -- day and a half alone
local RADIO_PREFIX = "Base.WalkieTalkie"
local function strandedCharacter(id)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil then return nil end
    for _, name in ipairs({ "getCharacter", "characterFor", "get" }) do
        local lookup = runtime[name]
        if type(lookup) == "function" then
            local ok, value = pcall(lookup, id)
            if ok and value ~= nil then return value end
        end
    end
    return nil
end

local function say(text)
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then feed.event(tostring(text)) end
end

function CompanionService.hasRadio(character)
    if character == nil then return false end
    local ok, inventory = pcall(function() return character:getInventory() end)
    if not ok or inventory == nil then return false end
    local found = false
    pcall(function()
        local items = inventory:getItems()
        if items == nil then return end
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local fullType = item ~= nil and tostring(item:getFullType()) or ""
            if fullType:sub(1, #RADIO_PREFIX) == RADIO_PREFIX then
                found = true
                return
            end
        end
    end)
    return found
end

-- Pure rule: what, if anything, should happen to a companion this far away for
-- this long. Nil means "still within reach, leave them alone".
function CompanionService.strandedPlan(distance, hoursApart, playerRadio, survivorRadio)
    local gap = tonumber(distance)
    if gap == nil or gap <= CompanionService.STRANDED_DISTANCE then return nil end
    local hours = tonumber(hoursApart) or 0
    if playerRadio == true and survivorRadio == true then
        if hours >= CompanionService.STRANDED_WALKIE_HOURS then return "call_back" end
        return nil
    end
    if hours >= CompanionService.STRANDED_ALONE_HOURS then return "go_home" end
    return nil
end

-- Called on a slow cadence from the service's own tick. Every write goes
-- through the existing persistence setters; this decides, it does not store.
function CompanionService.reconcileStranded(player)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil then return 0 end
    local now = worldAge()
    local playerRadio = CompanionService.hasRadio(player)
    local handled = 0
    for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
        local character = strandedCharacter(id)
        local distance = nil
        if character ~= nil then
            local dx = player:getX() - character:getX()
            local dy = player:getY() - character:getY()
            distance = math.sqrt(dx * dx + dy * dy)
        end
        if distance == nil then
            -- Unloaded is the case this exists for: no body is being simulated,
            -- so distance is unknown and the survivor counts as left behind.
            distance = math.huge
        end
        if distance <= CompanionService.STRANDED_DISTANCE then
            KnoxPersistence.clearCompanionStranded(id)
        else
            local since = KnoxPersistence.getCompanionStrandedSince(id)
                or KnoxPersistence.noteCompanionStranded(id, now) or now
            local duty = KnoxPersistence.getSurvivorDuty(id)
            local plan = CompanionService.strandedPlan(distance, now - since, playerRadio,
                character ~= nil and CompanionService.hasRadio(character) or false)
            if plan == "call_back" then
                if duty == nil or duty.order ~= "follow" then
                    KnoxPersistence.setPlayerCompanion(id, playerId, "follow", now)
                    say(displayName(id) .. " heard the radio and is coming back to you.")
                    handled = handled + 1
                end
                KnoxPersistence.clearCompanionStranded(id)
            elseif plan == "go_home" then
                local bases = KnoxPersistence.getBasesForOwner("player", playerId) or {}
                local base = bases[1]
                if base ~= nil then
                    local saved = KnoxPersistence.setPlayerBaseResident(id, playerId, base.id, now)
                    if saved then
                        KnoxPersistence.clearCompanionStranded(id)
                        say(displayName(id) .. " made it back to "
                            .. tostring(base.name or "the base") .. " and is living there now.")
                        handled = handled + 1
                    end
                end
            end
        end
    end
    return handled
end

local strandedNextCheck = 0
local function strandedTick()
    local clock = getTimestampMs ~= nil and getTimestampMs() or 0
    if clock < strandedNextCheck then return end
    strandedNextCheck = clock + 30000
    local player = getSpecificPlayer(0)
    if player ~= nil and KnoxSettings ~= nil and KnoxSettings.enabled ~= nil
        and KnoxSettings.enabled() == true then
        pcall(CompanionService.reconcileStranded, player)
    end
end
if Events ~= nil and Events.OnTick ~= nil then Events.OnTick.Add(strandedTick) end

function CompanionService.activateFromBase(player, survivorId)
    return CompanionService.recallToParty(player, survivorId)
end

function CompanionService.dismiss(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if playerId == nil or affiliation == nil or affiliation.kind ~= "player"
        or affiliation.ownerId ~= playerId then
        return false, "not_your_survivor"
    end
    local saved = KnoxPersistence.setSurvivorIndependent(
        survivorId,
        "dismissed",
        worldAge()
    )
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if saved and character ~= nil then
        KnoxActivityFeed.speak(character, "Understood. Take care of yourself.")
    end
    if saved then
        CompanionService.rememberCommitment(player, survivorId)
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
        signalOrder(player, survivorId, "dismiss")
    end
    return saved, saved and "dismissed" or "save_failed"
end

function CompanionService.syncController(survivorId, controller)
    if controller == nil then
        return
    end
    if controller.canApplyDutyChange ~= nil and not controller:canApplyDutyChange() then
        return false
    end
    -- Retire the old task/action in its original base context before setters
    -- project a newly accepted role or base. Persistence remains authoritative.
    if controller.pendingDutyChange and controller.onDutyChanged ~= nil then
        if controller:onDutyChanged() == false then return false end
    end
    local previous = syncCache[controller]
    -- A duty read allocates a copy. When the persisted revision still matches the
    -- one this sync already projected, that copy is identical to the one in hand:
    -- reuse it and skip the allocation. Any duty write bumps the revision, so a
    -- changed duty is always read fresh; without the revision API this falls back
    -- to the old unconditional read.
    local dutyRevision = KnoxPersistence.getSurvivorDutyRevision ~= nil
        and KnoxPersistence.getSurvivorDutyRevision(survivorId) or nil
    local duty
    if dutyRevision ~= nil and previous ~= nil
        and previous.dutyRevision == dutyRevision and previous.duty ~= nil then
        duty = previous.duty
    else
        duty = KnoxPersistence.getSurvivorDuty(survivorId)
    end
    local previousPlayerId = previous ~= nil and previous.ownerId or nil
    -- Mission expiry changes canonical duty without a direct player command.
    -- Retire its old route/actions before projection or a cache can hide it.
    if controller.awayTeamId ~= nil and (duty == nil or duty.mode ~= "away"
        or duty.awayTeamId ~= controller.awayTeamId) and controller.onDutyChanged ~= nil then
        if controller:onDutyChanged() == false then return false end
    end
    if duty == nil or duty.mode ~= "companion" then
        local priorOwnerId = previousPlayerId
            or (duty ~= nil and duty.ownerKind == "player" and duty.ownerId or nil)
        if priorOwnerId ~= nil then
            CompanionService.removePlayerPartyFormationMember(priorOwnerId, survivorId)
            if CompanionService.getPartyDestination ~= nil then
                -- Reconcile dismiss/base reassignment immediately without
                -- mutating canonical affiliation or the remaining order.
                CompanionService.getPartyDestination(priorOwnerId)
            end
        end
    end
    local eventRuntime = rawget(_G, "KnoxEventRuntime")
    if eventRuntime ~= nil and controller.setEventAssignment ~= nil then
        local stampBefore = KnoxPersistence.getSurvivorDutyRevision ~= nil
            and KnoxPersistence.getSurvivorDutyRevision(survivorId) or nil
        eventRuntime.syncController(survivorId, controller)
        -- Re-read only when the event runtime actually rewrote the duty: every
        -- read allocates a copy, and this path runs for every active survivor on
        -- every tick.
        local stampAfter = KnoxPersistence.getSurvivorDutyRevision ~= nil
            and KnoxPersistence.getSurvivorDutyRevision(survivorId) or nil
        if stampBefore == nil or stampAfter == nil or stampAfter ~= stampBefore then
            duty = KnoxPersistence.getSurvivorDuty(survivorId)
            dutyRevision = stampAfter or dutyRevision
        end
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = duty ~= nil and duty.mode == "companion"
        and CompanionService.resolvePlayer(duty.ownerId) or nil
    -- Both the fingerprint and the projection read the same policies; one copy
    -- per sync replaces the two identical copies this path used to allocate.
    local policies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
    local partyFormationContext = duty ~= nil and duty.mode == "companion"
        and CompanionService.getPlayerPartyFormationContext(duty.ownerId, player) or nil
    local partyDestination = nil
    if duty ~= nil and duty.mode == "companion" and duty.directive == nil
        and CompanionService.getPartyDestinationFor ~= nil then
        partyDestination = CompanionService.getPartyDestinationFor(survivorId)
    end
    local formationSlot = partyFormationContext ~= nil
        and partyFormationContext.slots[tostring(survivorId)] or 1
    if partyDestination ~= nil then
        partyDestination.partyDestinationSlot = formationSlot
    end
    -- Compare canonical travel intent, excluding presentation, policies and
    -- formation churn. A ground order must not strand a former party rider.
    local vehicleIntent = table.concat({
        tostring(duty ~= nil and duty.mode or "independent"),
        tostring(duty ~= nil and duty.ownerId or ""),
        tostring(duty ~= nil and duty.baseId or ""),
        tostring(duty ~= nil and duty.order or ""),
        tostring(duty ~= nil and duty.directive or ""),
    }, "|")
    local exitsPartyRide = previous ~= nil and previous.ownerId ~= nil
        and previous.vehicleIntent ~= vehicleIntent
        and (duty == nil or duty.mode ~= "companion" or duty.order ~= "follow"
            or duty.directive ~= nil or duty.ownerId ~= previous.ownerId)
    local ridingCharacter = controller.character
    local ridingVehicle = exitsPartyRide and ridingCharacter ~= nil
        and ridingCharacter.getVehicle ~= nil and ridingCharacter:getVehicle() or nil
    local cacheKey, keyParts
    if controller.setWeaponPreference ~= nil then
        local mode = duty ~= nil and duty.mode or "independent"
        local owner = duty ~= nil and duty.ownerId or ""
        local order = duty ~= nil and duty.order or ""
        local stance = duty ~= nil and duty.combatStance or ""
        local directive = duty ~= nil and tostring(duty.directive) or ""
        local partyDestinationRevision = partyDestination ~= nil
            and tostring(partyDestination.partyDestinationRevision or "") or ""
        local partyDestinationArrived = partyDestination ~= nil
            and (partyDestination.partyDestinationArrived == true and "arrived" or "travel") or ""
        local baseId = duty ~= nil and duty.baseId or ""
        local jobPreference = duty ~= nil and duty.jobPreference or ""
        local revision = duty ~= nil and duty.revision or ""
        local supplyOrder = duty ~= nil and tostring(duty.baseSupplyOrder) or ""
        local climbing = policies.allowClimbing ~= false and "1" or "0"
        -- Companion policy wins; nil inherits the sandbox default. The old
        -- `...() or true` chain forced open even when the sandbox said off.
        local sandboxOpening = true
        if KnoxSettings ~= nil
            and KnoxSettings.allowSurvivorDoorWindowOpening ~= nil then
            sandboxOpening = KnoxSettings.allowSurvivorDoorWindowOpening() ~= false
        end
        local opening = policies.allowDoorOpening
        if opening == nil then
            opening = sandboxOpening
        else
            opening = opening ~= false
        end
        local autoLoot = policies.autoLoot
        if autoLoot == nil then
            autoLoot = true
        else
            autoLoot = autoLoot ~= false
        end
        local roster = ""
        local formationRoster = ""
        if duty ~= nil and duty.mode == "companion" then
            local ids = KnoxPersistence.getCompanionIds(duty.ownerId) or {}
            local parts = {}
            for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
            roster = table.concat(parts, ",")
            local formationParts = partyFormationContext ~= nil
                and partyFormationContext.memberIds or {}
            local activeParts = {}
            for _, id in ipairs(formationParts) do
                activeParts[#activeParts + 1] = tostring(id)
            end
            formationRoster = table.concat(activeParts, ",")
        end
        if mode ~= "base" then
            -- Compare the parts, not their concatenation: an unchanged companion
            -- tick needs no 25-piece string. The key string is still composed in
            -- the identical order when a part really differs, and the previous key
            -- is reused while nothing has moved.
            keyParts = {
                controller, mode, owner, order, stance, directive, baseId,
                jobPreference, revision, supplyOrder, roster, formationRoster,
                formationSlot,
                partyFormationContext ~= nil and partyFormationContext.forwardX or "",
                partyFormationContext ~= nil and partyFormationContext.forwardY or "",
                partyFormationContext ~= nil and partyFormationContext.memberCount or "",
                partyDestinationRevision, partyDestinationArrived,
                policies.weaponPreference or "auto", climbing,
                policies.allowDoorOpening, opening,
                policies.autoLoot, autoLoot,
                policies.autoEquipment ~= false,
            }
            local previousParts = previous ~= nil and previous.keyParts or nil
            -- Nil parts are meaningful here ("nil" in the old key), so the
            -- count is fixed: the length operator is undefined across holes.
            local partCount = 25
            local unchanged = previousParts ~= nil
            if unchanged then
                for index = 1, partCount do
                    if previousParts[index] ~= keyParts[index] then
                        unchanged = false
                        break
                    end
                end
            end
            if unchanged then
                cacheKey = previous.key
            else
                local text = {}
                for index = 1, partCount do
                    text[index] = tostring(keyParts[index])
                end
                cacheKey = table.concat(text, "|")
            end
        end
        -- Base assignment also reconciles an active supply trip. Its runtime
        -- progress is not represented by the persisted duty fingerprint.
        if mode ~= "base" and previous ~= nil and previous.key == cacheKey
            and previous.player == player and previous.bridge == bridge then
            return
        end
        -- A failed setter must be retried, including when reverting to an older
        -- duty after a partially applied update.
        -- Keep only the prior ownership/intent for a failed projection retry;
        -- no key remains that could skip partially applied setters.
        syncCache[controller] = previous ~= nil and {
            ownerId = previous.ownerId, vehicleIntent = previous.vehicleIntent,
            duty = previous.duty, dutyRevision = previous.dutyRevision,
        } or nil
        controller:setWeaponPreference(policies.weaponPreference)
        if controller.setDoorWindowOpeningPolicy ~= nil then
            controller:setDoorWindowOpeningPolicy(opening)
        end
        if controller.setAutoLootPolicy ~= nil then
            controller:setAutoLootPolicy(autoLoot)
        end
        if controller.setAutoEquipmentPolicy ~= nil then
            controller:setAutoEquipmentPolicy(policies.autoEquipment ~= false)
        end
    else
        syncCache[controller] = nil
    end
    if bridge ~= nil and bridge.setNpcPartyVisible ~= nil then
        bridge:setNpcPartyVisible(survivorId, duty ~= nil and duty.mode == "companion")
    end
    if duty ~= nil and duty.mode == "companion" then
        if controller.clearBaseAssignment ~= nil then
            controller:clearBaseAssignment()
        end
        controller:setCompanionOrder(
            duty.ownerId,
            player,
            duty.order,
            formationSlot,
            partyFormationContext ~= nil and partyFormationContext.forwardX or nil,
            partyFormationContext ~= nil and partyFormationContext.forwardY or nil,
            partyFormationContext ~= nil and partyFormationContext.memberCount or nil
        )
        if controller.setCompanionCombatStance ~= nil then
            controller:setCompanionCombatStance(duty.combatStance)
        end
        if controller.setCompanionPolicy ~= nil then
            controller:setCompanionPolicy(policies.allowClimbing ~= false)
        end
        if controller.setCompanionDirective ~= nil then
            controller:setCompanionDirective(duty.directive or partyDestination)
        end
    elseif duty ~= nil and duty.mode == "base" then
        if controller.clearCompanionOrder ~= nil then
            controller:clearCompanionOrder()
        end
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and manager.get ~= nil
            and manager.get(duty.baseId)
            or nil
        if controller.setBaseAssignment ~= nil then
            controller:setBaseAssignment(duty.baseId, base)
        end
    else
        if controller.clearCompanionOrder ~= nil then
            controller:clearCompanionOrder()
        end
        if controller.clearBaseAssignment ~= nil then
            controller:clearBaseAssignment()
        end
        if controller.setCompanionDirective ~= nil then
            controller:setCompanionDirective(nil)
        end
    end
    -- Projection setters above may cancel native leases. Publish exit intent
    -- only afterwards, through the existing vehicle receipt/retry owner.
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if ridingVehicle ~= nil and ridingCharacter:getVehicle() == ridingVehicle
        and vehicles ~= nil and vehicles.exitAfterPlayer ~= nil then
        vehicles.exitAfterPlayer(ridingCharacter, ridingVehicle)
    end
    if cacheKey ~= nil or (duty ~= nil and duty.mode == "base") then
        syncCache[controller] = {
            key = cacheKey, keyParts = keyParts, player = player, bridge = bridge,
            vehicleIntent = vehicleIntent,
            duty = duty, dutyRevision = dutyRevision,
            ownerId = duty ~= nil and duty.mode == "companion" and duty.ownerId or nil,
        }
    end
end

local function currentPlayerPartyCharacters(player)
    local characters = {}
    local playerId = CompanionService.getPlayerId(player)
    for _, survivorId in ipairs(playerPartyMemberIds(playerId)) do
        local character = KnoxSurvivorRuntime.getCharacter(survivorId)
        if character ~= nil then characters[#characters + 1] = character end
    end
    return characters
end

local function resolveLocalPlayer(character)
    if character == nil or character.getPlayerNum == nil
        or getSpecificPlayer == nil then return nil end
    local ok, playerNum = pcall(character.getPlayerNum, character)
    if not ok or type(playerNum) ~= "number" or playerNum < 0 then return nil end
    local player = getSpecificPlayer(playerNum)
    return player == character and player or nil
end

local function rememberPlayerVehicle(player)
    if player == nil then return nil end
    local vehicle = player.getVehicle ~= nil and player:getVehicle() or nil
    if vehicle ~= nil then lastPlayerVehicle[player] = vehicle end
    return vehicle
end

function CompanionService.onPlayerEnteredVehicle(character)
    local player = resolveLocalPlayer(character)
    if player == nil then return false, "not_local_player" end
    local vehicle = rememberPlayerVehicle(player)
    if vehicle == nil then return false, "player_not_in_vehicle" end
    local ok, result = KnoxCompanionVehicles.syncPlayerEntered(
        player, currentPlayerPartyCharacters(player)
    )
    if not ok then return false, result end
    local rejected = result ~= nil and result.rejected or nil
    if rejected ~= nil and #rejected > 0 then
        KnoxActivityFeed.event("Some following companions could not enter the vehicle: "
            .. tostring(rejected[1]) .. ".")
    end
    return true, result
end

function CompanionService.onPlayerExitedVehicle(character)
    local player = resolveLocalPlayer(character)
    if player == nil then return false, "not_local_player" end
    local vehicle = lastPlayerVehicle[player]
    lastPlayerVehicle[player] = nil
    if vehicle == nil then return false, "previous_vehicle_unavailable" end
    local ok, result = KnoxCompanionVehicles.syncPlayerExited(
        player, vehicle, currentPlayerPartyCharacters(player)
    )
    if ok and result ~= nil and result.rejected ~= nil and #result.rejected > 0 then
        KnoxActivityFeed.event("Some following companions could not exit the vehicle: "
            .. tostring(result.rejected[1]) .. ".")
    end
    return ok, result
end

if Events ~= nil then
    if Events.OnPlayerUpdate ~= nil and Events.OnPlayerUpdate.Add ~= nil then
        Events.OnPlayerUpdate.Add(function(character)
            local player = resolveLocalPlayer(character)
            if player ~= nil then rememberPlayerVehicle(player) end
        end)
    end
    if Events.OnEnterVehicle ~= nil and Events.OnEnterVehicle.Add ~= nil then
        Events.OnEnterVehicle.Add(CompanionService.onPlayerEnteredVehicle)
    end
    if Events.OnExitVehicle ~= nil and Events.OnExitVehicle.Add ~= nil then
        Events.OnExitVehicle.Add(CompanionService.onPlayerExitedVehicle)
    end
end

return CompanionService
