require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
local SurvivorNames = require "KS_SurvivorNames"

local Nameplates = rawget(_G, "KnoxSurvivorNameplates") or {}
_G.KnoxSurvivorNameplates = Nameplates

local COLORS = {
    hostile = { 0.92, 0.18, 0.18 },
    neutral = { 0.92, 0.92, 0.92 },
    friendly = { 0.30, 0.58, 0.95 },
    ally = { 0.25, 0.86, 0.34 },
}

local labels = {}
-- What is actually showing, so the off path and clear() are bounded by the tags
-- that exist rather than by every active survivor. Build 42's Kahlua has no
-- global next(), so "is anything showing" is a counter, not a scan.
local tagged = {}
local taggedCount = 0

local function fullName(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    local _, _, name = SurvivorNames.resolve(id, identity, KnoxSurvivorRuntime.getCharacter(id))
    return name
end

function Nameplates.classify(survivorId, playerId)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId) or {}
    if affiliation.kind == "player" and affiliation.ownerId == playerId then return "ally" end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return "hostile" end
    local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
    if playerFaction ~= nil and affiliation.factionId ~= nil then
        if affiliation.factionId == playerFaction.id then return "ally" end
        local relationship = KnoxPersistence.getFactionRelationship(
            affiliation.factionId, playerFaction.id
        )
        if relationship ~= nil and relationship.disposition == "allied" then return "friendly" end
    end
    local personal = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if personal ~= nil and (tonumber(personal.trust) or 0) >= 30 then return "friendly" end
    return "neutral"
end

-- One sentence for the second line: who they are with, and - only when the
-- household shared a named facility - where they belong.
local function companyLine(company)
    if type(company) ~= "table" or type(company.headline) ~= "string"
        or company.headline == "" then return nil end
    if type(company.place) == "string" and company.place ~= "" then
        return company.headline .. " · " .. company.place
    end
    return company.headline
end

local function setVisible(character, visible)
    pcall(function() character:setShowTag(visible == true) end)
end

local function nearestVisiblePlayer(character, maximumDistanceSquared)
    local square = character ~= nil and character:getCurrentSquare() or nil
    if square == nil then return nil, nil end
    local best, bestDistance = nil, maximumDistanceSquared
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        local playerSquare = player ~= nil and player:getCurrentSquare() or nil
        if playerSquare ~= nil and playerSquare:getZ() == square:getZ() then
            local dx, dy = playerSquare:getX() - square:getX(), playerSquare:getY() - square:getY()
            local distance = dx * dx + dy * dy
            if distance <= bestDistance then
                local ok, canSee = pcall(function() return player:CanSee(character) end)
                if ok and canSee == true then best, bestDistance = player, distance end
            end
        end
    end
    return best, bestDistance
end

-- Both writes are hoisted out of the survivor loop so pcall can receive a
-- function plus arguments instead of a freshly built closure for every
-- survivor on every pass.
local function applyTag(character, name, color)
    character:setUsername(name)
    character:setDisplayName(name)
    character:setTagColor(ColorInfo.new(color[1], color[2], color[3], 1))
    character:setShowTag(true)
end

local function recordProximity(playerId, id, hours)
    KnoxPersistence.recordPlayerProximity(playerId, id, hours)
end

function Nameplates.update(ticks)
    if tonumber(ticks) ~= nil and ticks % 15 ~= 0 then return end
    local enabled = KnoxSettings.showSurvivorNameplates()
    -- Switched off is the common case, and it used to cost a full pass: one
    -- identity read, one name and one native tag write per survivor, four times
    -- a second, to decide that nothing should be drawn. With nothing showing and
    -- nothing to clear there is no work to do.
    if not enabled and taggedCount <= 0 and #labels == 0 then return end
    local distance = KnoxSettings.survivorNameplateDistance()
    labels = {}
    local viewerIds = {}
    if enabled then
        for number = 0, math.max(0, getNumActivePlayers() - 1) do
            local viewer = getSpecificPlayer(number)
            if viewer ~= nil then viewerIds[number] = KnoxPersistence.ensurePlayerId(viewer) end
        end
    end
    -- One clock read and one name per survivor for the whole pass; the old
    -- version asked for the world age once per visible survivor and rebuilt a
    -- closure for each write.
    local time = getGameTime ~= nil and getGameTime() or nil
    local hours = time ~= nil and time:getWorldAgeHours() or nil
    -- One name lookup per household, not one per member: a pass over three
    -- people who came together must not resolve the same leader three times.
    local companyNames = {}
    for _, id in ipairs(KnoxSurvivorRuntime.activeIds()) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        if character ~= nil then
            local name
            if enabled then
                name = fullName(id)
                local colors = {}
                for number, viewerId in pairs(viewerIds) do
                    colors[number] = COLORS[Nameplates.classify(id, viewerId)] or COLORS.neutral
                end
                local company = nil
                if KnoxPersistence.survivorCompany ~= nil then
                    local facts = KnoxPersistence.survivorCompany(id)
                    if facts ~= nil then
                        local cached = companyNames[facts.leaderId]
                        if cached == nil then
                            local leaderName = SurvivorNames.companyName ~= nil
                                and SurvivorNames.companyName(facts) or nil
                            local size = math.floor(tonumber(facts.memberCount) or 0)
                            local headline = nil
                            if facts.isLeader == true and size >= 2 then
                                headline = "Household of " .. tostring(size)
                            elseif leaderName ~= nil then
                                headline = "With " .. leaderName
                            end
                            cached = headline ~= nil and {
                                headline = headline,
                                place = SurvivorNames.companyPlace ~= nil
                                    and SurvivorNames.companyPlace(facts) or nil,
                            } or false
                            companyNames[facts.leaderId] = cached
                        end
                        company = cached or nil
                    end
                end
                labels[#labels + 1] = { id = id, character = character, name = name,
                    company = company, colors = colors }
            end
            local player = enabled and nearestVisiblePlayer(character, distance * distance) or nil
            if player == nil then
                if tagged[character] == true then
                    tagged[character] = nil
                    taggedCount = taggedCount - 1
                    setVisible(character, false)
                end
            else
                local playerId = viewerIds[player:getPlayerNum()]
                    or KnoxPersistence.ensurePlayerId(player)
                -- Spending time nearby builds reputation passively.
                if playerId ~= nil and hours ~= nil then
                    pcall(recordProximity, playerId, id, hours)
                end
                local relation = Nameplates.classify(id, playerId)
                local color = COLORS[relation] or COLORS.neutral
                if tagged[character] ~= true then
                    tagged[character] = true
                    taggedCount = taggedCount + 1
                end
                pcall(applyTag, character, name, color)
            end
        end
    end
end

-- Viewpoint exposes the NEXT view as a read-only enum: next first means
-- current ISO. Installed Viewpoint_Pad.lua uses this same nested Lua API.
-- DENSITY RULE
-- Two survivors standing together used to paint their second lines into the same
-- pixels, which reads as noise rather than as people. A plate that would overlap
-- one already drawn keeps its name and gives up the extra line; the first plate
-- keeps its word. The rule is a pure test so it can be checked without a screen.
function Nameplates.crowdedBy(drawn, x, y, halfWidth, fontHeight)
    if type(drawn) ~= "table" then return false end
    if tonumber(x) == nil or tonumber(y) == nil then return false end
    local width = tonumber(halfWidth) or 0
    local height = tonumber(fontHeight) or 0
    for _, spot in ipairs(drawn) do
        if type(spot) == "table"
            and math.abs((tonumber(spot.y) or 0) - y) <= height
            and math.abs((tonumber(spot.x) or 0) - x) <= (tonumber(spot.halfWidth) or 0) + width then
            return true
        end
    end
    return false
end

local function cameraMode()
    local viewpoint = rawget(_G, "Viewpoint")
    if viewpoint ~= nil then
        local view = viewpoint.View
        if view == nil or view.next == nil then return nil end
        local ok, nextView = pcall(view.next)
        if not ok then return nil end
        if nextView == "first" then return "iso" end
        if nextView == "third" or nextView == "isometric" then return "perspective" end
        return nil
    end
    -- The published global is ViewpointUI; isActive() is the camera signal its
    -- public API promises. Reading only Viewpoint laid nameplates out for the
    -- isometric camera in every perspective session.
    viewpoint = rawget(_G, "ViewpointUI") or rawget(_G, "VPUI")
    if viewpoint == nil or type(viewpoint.isActive) ~= "function" then return "iso" end
    local ok, active = pcall(viewpoint.isActive, viewpoint)
    if not ok then return "iso" end
    return active == true and "perspective" or "iso"
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function projectHead(character, playerNum, left, top, zoom, mode)
    if mode == "iso" then
        -- Preserve the native isometric anchor; perspective pixels already
        -- include camera projection and must never receive these offsets.
        return (IsoUtils.XToScreen(character:getX(), character:getY(), character:getZ(), 0)
            - character:getOffsetX() - IsoCamera.getOffX(playerNum)) / zoom + left,
            (IsoUtils.YToScreen(character:getX(), character:getY(), character:getZ(), 0)
            - character:getOffsetY() - 64 * Core.getTileScale()
            - IsoCamera.getOffY(playerNum)) / zoom + top
    end
    if mode ~= "perspective" or playerNum ~= 0 or getNumActivePlayers() ~= 1 then return nil end
    local ui = rawget(_G, "ViewpointUI")
    local native = ui ~= nil and ui.Native or nil
    if native == nil or native.viewOn == nil or native.project == nil
        or native.projectedX == nil or native.projectedY == nil then return nil end
    local ok, x, y = pcall(function()
        -- viewOn also rejects FreeCam; false never means fallback to ISO.
        if native.viewOn() ~= true then return nil end
        -- Exact head lift used by the installed ViewpointUI NPC renderer.
        if native.project(character:getX(), character:getY(), character:getZ(), 0.62) ~= true then
            return nil
        end
        return native.projectedX() + left, native.projectedY() + top
    end)
    if ok and finite(x) and finite(y) then return x, y end
    return nil
end

-- One renderer, with only the projection boundary differing by camera mode.
-- ONE WORD OF WHAT THEY ARE DOING
-- A nameplate said who someone was and, at talking distance, whose household
-- they travel with. It never said what they were up to, so the only way to know
-- whether a resident was boarding a window, cooking or lying down was to open a
-- panel. This reads the same durable facts the scheduler already acts on: asleep,
-- in real pain, or holding a claimed base task. It invents nothing - an unknown
-- task type, a task held by somebody else or an unreadable body all stay silent.
Nameplates.taskWords = {
    barricade = "boarding", repair = "repairing", chop_tree = "chopping",
    saw_logs = "sawing", cook = "cooking", guard = "on watch",
    patrol = "patrolling", haul_corpse = "moving a body",
    burn_corpse = "burning a body", pile_corpses = "piling bodies",
    farm_seed = "sowing", farm_water = "watering", farm_harvest = "harvesting",
    farm_plow = "ploughing", storage_sorting = "sorting stores",
}
-- A companion's errand, in the same short words. Keys are the directive kinds
-- the persistence layer already validates, so a word cannot outlive its order.
Nameplates.dutyWords = {
    loot_area = "searching", loot_building = "searching",
    loot_corpses = "checking bodies", go_to = "on the way",
    guard = "on watch", patrol_area = "patrolling",
    find_food = "looking for food", find_water = "looking for water",
    find_medical = "looking for supplies", find_weapon = "looking for a weapon",
    find_tools = "looking for tools", clean_inventory = "sorting their pack",
}

local STATUS_TTL_MS = 750
local STATUS_CACHE_LIMIT = 64
local statusCache = {}

local function clockMs()
    local read = rawget(_G, "getTimestampMs")
    if read == nil then return nil end
    local ok, value = pcall(read)
    if not ok or tonumber(value) == nil then return nil end
    return tonumber(value)
end

-- Standing outranks the job. A plate exists to tell the player who somebody
-- is to them, so a companion who has stopped taking orders says that before the
-- plate reports what they are working on. A hostile person is already red, so
-- the colour carries that verdict and no word is spent on it.
Nameplates.standingWords = { wary = "wary of you" }

-- One word for a body the engine has already decided about. It is not a job and
-- not a mood, and the player should be able to read it without a panel.
Nameplates.illnessWords = { bitten = "bitten" }

function Nameplates.standingWord(stance)
    if stance == nil then return nil end
    return Nameplates.standingWords[tostring(stance)]
end

local function computeStatus(survivorId, character)
    if character ~= nil and character.isAsleep ~= nil then
        local ok, asleep = pcall(function() return character:isAsleep() end)
        if ok and asleep == true then return "asleep" end
    end
    -- Bitten outranks standing, pain and work. A dying person is the fact the
    -- player can still act on; everything else about them is secondary.
    local illness = rawget(_G, "KnoxSurvivorNeeds")
    if illness ~= nil and illness.infectionBand ~= nil and character ~= nil then
        local ok, band = pcall(illness.infectionBand, character)
        if ok and band ~= nil and Nameplates.illnessWords[band] ~= nil then
            return Nameplates.illnessWords[band]
        end
    end
    -- Standing comes next: it is the one thing the player can still act on, and
    -- discovering it by having an order refused is the wrong order to learn it in.
    local service = rawget(_G, "KnoxCompanionService")
    if service ~= nil and service.orderWillingness ~= nil then
        local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
        if type(affiliation) == "table" and affiliation.kind == "player" then
            local ok, stance = pcall(service.orderWillingness, survivorId, affiliation.ownerId)
            local word = ok and Nameplates.standingWord(stance) or nil
            if word ~= nil then return word end
        end
    end
    -- Pain outranks the task: somebody working through a bad wound is telling
    -- the player something more urgent than which job they hold.
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs ~= nil and needs.painBand ~= nil and needs.snapshot ~= nil
        and character ~= nil then
        local ok, snapshot = pcall(needs.snapshot, character)
        if ok and snapshot ~= nil then
            local band = needs.painBand(snapshot)
            if band == "bad" or band == "severe" then return "hurt" end
        end
    end
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    local baseId = duty ~= nil and duty.mode == "base" and duty.baseId or nil
    if duty ~= nil and duty.mode == "companion" and baseId == nil then
        -- The controlling order speaks first: somebody told to hold is holding,
        -- even if a search order is still on the record. This is the same
        -- duty.order the party strip reads, so plate and strip cannot disagree.
        local order = tostring(duty.order or "")
        if order == "hold" then return "holding" end
        if order == "relax" then return "relaxing" end
        -- Otherwise the errand names itself, and a follower with nothing on is
        -- following - the real default, not a guess.
        local kind = type(duty.directive) == "table"
            and tostring(duty.directive.kind or "") or ""
        return Nameplates.dutyWords[kind] or "with you"
    end
    local base = baseId ~= nil and KnoxPersistence.getBase ~= nil
        and KnoxPersistence.getBase(baseId) or nil
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if type(task) == "table" and task.state == "claimed"
            and tostring(task.claimedBy or "") == tostring(survivorId) then
            local word = Nameplates.taskWords[tostring(task.type or "")]
            if word ~= nil then return word end
        end
    end
    return nil
end

-- Cached briefly: the plate repaints every frame and walking a base's task table
-- per frame is not something a label is allowed to cost.
function Nameplates.statusWord(survivorId, character)
    if survivorId == nil then return nil end
    local now = clockMs()
    local cached = statusCache[survivorId]
    if now ~= nil and cached ~= nil and now - cached.at < STATUS_TTL_MS then
        return cached.word
    end
    local word = computeStatus(survivorId, character)
    if now ~= nil then
        local size = 0
        for _ in pairs(statusCache) do size = size + 1 end
        if size >= STATUS_CACHE_LIMIT then statusCache = {} end
        statusCache[survivorId] = { at = now, word = word }
    end
    return word
end

-- Core-only Viewpoint has no public projector: omit spatial labels there.
-- IsoGameCharacter.renderlast draws usernames only in the multiplayer client
-- branch. showTag is faction-tag metadata, not a single-player nameplate switch.
-- Draw native text with each real viewer's camera/LOS; never borrow an NPC slot.
function Nameplates.render()
    if isClient ~= nil and isClient() then return end
    if not KnoxSettings.showSurvivorNameplates() then return end
    local distance = KnoxSettings.survivorNameplateDistance()
    local mode = cameraMode()
    if mode == nil then return end
    -- Plates already painted this pass, so a neighbour can tell it is crowded.
    local drawn = {}
    for playerNum = 0, math.max(0, getNumActivePlayers() - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player:getCurrentSquare() ~= nil then
            local left, top = IsoCamera.getScreenLeft(playerNum), IsoCamera.getScreenTop(playerNum)
            local width, height = IsoCamera.getScreenWidth(playerNum), IsoCamera.getScreenHeight(playerNum)
            local zoom = getCore():getZoom(playerNum)
            for _, label in ipairs(labels) do
                local character = label.character
                if KnoxSurvivorRuntime.getCharacter(label.id) == character
                    and character:getCurrentSquare() ~= nil and not character:isDead()
                    and math.floor(character:getZ()) == math.floor(player:getZ()) then
                    local dx, dy = character:getX() - player:getX(), character:getY() - player:getY()
                    if dx * dx + dy * dy <= distance * distance and player:CanSee(character) then
                        local alpha = character:getAlpha(playerNum)
                        local x, y = projectHead(character, playerNum, left, top, zoom, mode)
                        local text = getTextManager()
                        local halfWidth = text:MeasureStringX(UIFont.Small, label.name) / 2
                        local fontHeight = text:getFontHeight(UIFont.Small)
                        local companyText = companyLine(label.company)
                        -- The second line is recognition, not a marker: activity
                        -- reads only at talking distance, like company does.
                        local statusText = dx * dx + dy * dy <= 16
                            and Nameplates.statusWord(label.id, character) or nil
                        if statusText ~= nil then
                            local statusWidth = text:MeasureStringX(UIFont.Small, statusText) / 2
                            if statusWidth > halfWidth then halfWidth = statusWidth end
                        end
                        if companyText ~= nil then
                            -- The wider of the two lines decides whether the
                            -- label fits on screen, so a long household name
                            -- cannot draw past the viewport edge.
                            local companyWidth = text:MeasureStringX(UIFont.Small, companyText) / 2
                            if companyWidth > halfWidth then halfWidth = companyWidth end
                        end
                        if alpha > 0 and finite(x) and finite(y) and x - halfWidth >= left and x + halfWidth <= left + width
                            and y >= top and y + fontHeight <= top + height then
                            local color = label.colors[playerNum] or COLORS.neutral
                            local crowded = Nameplates.crowdedBy(drawn, x, y, halfWidth, fontHeight)
                            drawn[#drawn + 1] = { x = x, y = y, halfWidth = halfWidth }
                            text:DrawStringCentre(UIFont.Small, x + 1, y + 1, label.name, 0, 0, 0, alpha)
                            text:DrawStringCentre(UIFont.Small, x, y, label.name, color[1], color[2], color[3], alpha)
                            -- A faction introduces itself the first time one of
                            -- its people is actually seen, then stays quiet.
                            -- A faction is introduced the first time one of
                            -- its people is seen. Afterwards it is recognised
                            -- only within conversation distance, so a known
                            -- group reads as a group without becoming a label.
                            local faction = KnoxPersistence.getFactionForSurvivor ~= nil
                                and KnoxPersistence.getFactionForSurvivor(label.id) or nil
                            local tag = faction ~= nil and type(faction.name) == "string"
                                and faction.name ~= "" and faction.name or nil
                            local known = faction ~= nil and faction.formationNoticed == true
                            if tag ~= nil and (not known or dx * dx + dy * dy <= 16) then
                                faction.formationNoticed = true
                                -- The name keeps the disposition colour, so
                                -- friend and foe stay readable; the faction's
                                -- own accent marks its people as one group.
                                local tr, tg, tb = color[1], color[2], color[3]
                                local accent = faction.accent
                                if type(accent) == "table" then
                                    tr, tg, tb = accent[1] or tr, accent[2] or tg, accent[3] or tb
                                end
                                text:DrawStringCentre(UIFont.Small, x + 1,
                                    y + fontHeight + 1, tag, 0, 0, 0, alpha)
                                text:DrawStringCentre(UIFont.Small, x,
                                    y + fontHeight, tag, tr, tg, tb, alpha)
                            elseif not crowded and statusText ~= nil then
                                -- What someone is doing right now outranks which
                                -- household they belong to; both are quiet bone
                                -- and neither uses the name's disposition colour.
                                text:DrawStringCentre(UIFont.Small, x + 1,
                                    y + fontHeight + 1, statusText, 0, 0, 0, alpha)
                                text:DrawStringCentre(UIFont.Small, x,
                                    y + fontHeight, statusText, 0.72, 0.69, 0.64, alpha)
                            elseif not crowded and companyText ~= nil
                                and dx * dx + dy * dy <= 16 then
                                -- Company is recognition, not a marker: it reads
                                -- only at conversation distance, in quiet bone,
                                -- and never replaces the name's disposition
                                -- colour. A faction line always wins the slot.
                                text:DrawStringCentre(UIFont.Small, x + 1,
                                    y + fontHeight + 1, companyText, 0, 0, 0, alpha)
                                text:DrawStringCentre(UIFont.Small, x,
                                    y + fontHeight, companyText, 0.72, 0.69, 0.64, alpha)
                            end
                        end
                    end
                end
            end
        end
    end
end

function Nameplates.clear()
    labels = {}
    for character in pairs(tagged) do setVisible(character, false) end
    tagged, taggedCount = {}, 0
end

if Events ~= nil and Events.OnPreUIDraw ~= nil and Events.OnPreUIDraw.Add ~= nil then
    Events.OnPreUIDraw.Add(Nameplates.render)
end
if Events ~= nil and Events.OnGameStart ~= nil and Events.OnGameStart.Add ~= nil then
    Events.OnGameStart.Add(Nameplates.clear)
end

return Nameplates
