-- Developer spectator.
--
-- The player body remains the engine's simulation anchor, but it is made
-- invisible, non-colliding and unkillable and is moved with the watched survivor
-- so the world around that person stays loaded. The camera follows the survivor,
-- never the body. One watched person dying selects the next loaded survivor in
-- the configured category; if none is loaded, it moves the anchor to the nearest
-- living record's last saved position and waits for that person to load. The
-- debug browser can choose any living record: a loaded body is followed now, an
-- unloaded one is reached the same way as the death handoff.
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorNames"
require "KS_ActivityFeed"
local UILayout = require "KS_SurvivorUILayout"
require "KS_DevSpectateCatalog"

local Spectate = rawget(_G, "KnoxDevSpectate") or {}
_G.KnoxDevSpectate = Spectate
local Catalog = rawget(_G, "KnoxDevSpectateCatalog")
local TAG = "[KnoxSurvivors][DevSpectate]"

local state = {
    active = false,
    id = nil,
    body = nil,
    category = "any",
    previous = nil,
    pendingStart = false,
    ticker = false,
    nextUpdate = 0,
    nextSearch = 0,
    nextAnchor = 0,
    lostAt = nil,
    nextLostSearch = 0,
    jump = nil,
    waitingAnnounced = false,
    window = nil,
    lastKnownName = nil,
}
local ticks = 0
local installTicker
local TICK_STEP = 15
local ANCHOR_DISTANCE_SQ = 12 * 12
local ANCHOR_INTERVAL = 30
local LOST_GRACE_TICKS = 60
local START_SEARCH_INTERVAL = 180
local JUMP_TIMEOUT_TICKS = 900

local function settings()
    return rawget(_G, "KnoxSettings")
end

local function feed(text)
    local activity = rawget(_G, "KnoxActivityFeed")
    if activity ~= nil and activity.event ~= nil then
        pcall(activity.event, text)
    end
end

local function engineDebug()
    if type(isDebugEnabled) ~= "function" then return false end
    local ok, value = pcall(isDebugEnabled)
    return ok and value == true
end

function Spectate.enabled()
    local config = settings()
    if config == nil or config.devSpectateEnabled == nil then return false end
    local ok, value = pcall(config.devSpectateEnabled)
    return ok and value == true
end

function Spectate.category()
    local config = settings()
    if config == nil or config.devSpectateCategory == nil then return "any" end
    local ok, value = pcall(config.devSpectateCategory)
    return ok and type(value) == "string" and value or "any"
end

function Spectate.debugBrowserAvailable()
    if not Spectate.enabled() then return false end
    local config = settings()
    if config == nil or config.debugSpectateBrowserEnabled == nil then return false end
    local ok, value = pcall(config.debugSpectateBrowserEnabled)
    return ok and value == true and engineDebug()
end

local function currentPlayer()
    if type(getSpecificPlayer) ~= "function" then return nil end
    local ok, player = pcall(getSpecificPlayer, 0)
    return ok and player or nil
end

local function playerDead(player)
    if player == nil then return true end
    local ok, dead = pcall(function() return player:isDead() end)
    return ok and dead == true
end

local function positionOf(entity)
    if entity == nil then return nil, nil, nil end
    local okX, x = pcall(function() return entity:getX() end)
    local okY, y = pcall(function() return entity:getY() end)
    local okZ, z = pcall(function() return entity:getZ() end)
    if not okX or not okY then return nil, nil, nil end
    return x, y, okZ and z or nil
end

local function bodyFor(id)
    if type(id) ~= "string" or id == "" then return nil end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.getCharacter ~= nil then
        local ok, body = pcall(runtime.getCharacter, id)
        if ok and body ~= nil then return body end
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil and bridge.getNpcCharacter ~= nil then
        local ok, body = pcall(bridge.getNpcCharacter, bridge, id)
        if ok then return body end
    end
    return nil
end

local function bodyDead(body, id)
    if body == nil then return true end
    local ok, dead = pcall(function() return body:isDead() end)
    if ok and dead == true then return true end
    local okAlive, alive = pcall(function() return body:isAlive() end)
    if okAlive and alive == false then return true end
    if id ~= nil then
        local persistence = rawget(_G, "KnoxPersistence")
        if persistence ~= nil and persistence.isSurvivorAlive ~= nil then
            local okPersist, living = pcall(persistence.isSurvivorAlive, id)
            if okPersist and living == false then return true end
        end
    end
    return false
end

local function livingIds()
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getActivatableSurvivorIds == nil then return {} end
    local ok, ids = pcall(persistence.getActivatableSurvivorIds)
    if ok and type(ids) == "table" then return ids end
    return {}
end

local function loadedIds()
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.activeIds == nil then return {} end
    local ok, ids = pcall(runtime.activeIds)
    if ok and type(ids) == "table" then return ids end
    return {}
end

local function memberCount(group)
    if group == nil or type(group.memberIds) ~= "table" then return 0 end
    return #group.memberIds
end

local function describeEntry(id, body)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return nil end
    local function read(name)
        local reader = persistence[name]
        if type(reader) ~= "function" then return nil end
        local ok, value = pcall(reader, id)
        return ok and value or nil
    end
    local group = read("getTravelGroupFor")
    local faction = read("getFactionForSurvivor")
    local creator = read("getSurvivorCreatorRecord")
    local origin = read("getSurvivorOrigin")
    local affiliation = read("getSurvivorAffiliation")
    local identity = read("getSurvivorIdentity")
    local facts = {
        creatorProfile = creator ~= nil and creator.profile or nil,
        originContext = origin ~= nil and origin.context or nil,
        factionBackground = faction ~= nil and faction.background or nil,
        groupBackground = group ~= nil and group.background or nil,
        eventPolicy = faction ~= nil and faction.eventIdentity ~= nil
            and faction.eventIdentity.policyId or nil,
        factionId = affiliation ~= nil and affiliation.factionId or nil,
        inFaction = faction ~= nil,
        groupMembers = memberCount(group),
        groupName = group ~= nil and group.name or nil,
        factionName = faction ~= nil and faction.name or nil,
    }
    local name = "Survivor"
    local names = rawget(_G, "KnoxSurvivorNames")
    if names ~= nil and names.resolve ~= nil then
        local ok, first, last, resolved = pcall(names.resolve, id, identity or {}, body)
        if ok and type(resolved) == "string" and resolved ~= "" then name = resolved end
    end
    local described = Catalog.describe(facts)
    local isGroupLeader = group ~= nil and group.leaderId == id
    local isFactionLeader = faction ~= nil and faction.leaderId == id
    local leaderKey = (isGroupLeader or isFactionLeader) and "0" or "1"
    return {
        id = id,
        name = name,
        body = body,
        loaded = body ~= nil,
        facts = facts,
        described = described,
        category = described.primary,
        label = Catalog.kindLabel(described, facts),
        isGroupLeader = isGroupLeader,
        isFactionLeader = isFactionLeader,
        sortKey = tostring(Catalog.primaryOrder(described.primary)) .. ":"
            .. leaderKey .. ":" .. name,
    }
end

function Spectate.entries(filter)
    filter = filter or "any"
    local loaded = {}
    for _, id in ipairs(loadedIds()) do
        loaded[id] = bodyFor(id)
    end
    local result = {}
    for _, id in ipairs(livingIds()) do
        local entry = describeEntry(id, loaded[id])
        if entry ~= nil and Catalog.matches(filter, entry.described) then
            result[#result + 1] = entry
        end
    end
    table.sort(result, function(first, second) return first.sortKey < second.sortKey end)
    return result
end

local function selectCandidate(filter, excludeId, anchorBody)
    local anchorX, anchorY = positionOf(anchorBody)
    local best, bestDistance = nil, nil
    for _, id in ipairs(loadedIds()) do
        if id ~= excludeId then
            local body = bodyFor(id)
            local previous = state.previous
            local player = previous ~= nil and previous.player or nil
            if body ~= nil and body ~= player and not bodyDead(body, id) then
                local entry = describeEntry(id, body)
                if entry ~= nil and Catalog.matches(filter, entry.described) then
                    local bodyX, bodyY = positionOf(body)
                    local distance = 0
                    if anchorX ~= nil and anchorY ~= nil and bodyX ~= nil and bodyY ~= nil then
                        distance = (bodyX - anchorX) * (bodyX - anchorX)
                            + (bodyY - anchorY) * (bodyY - anchorY)
                    end
                    if best == nil or distance < bestDistance then
                        best, bestDistance = entry, distance
                    end
                end
            end
        end
    end
    return best
end

local function validCoordinate(value)
    return type(value) == "number" and value == value
        and value > -1000000 and value < 1000000
end

local function farLocation(id)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return nil end
    if persistence.getUnloadedSurvivalState ~= nil then
        local ok, saved = pcall(persistence.getUnloadedSurvivalState, id)
        if ok and type(saved) == "table" then
            local x, y, z = tonumber(saved.virtualX), tonumber(saved.virtualY),
                tonumber(saved.virtualZ)
            if validCoordinate(x) and validCoordinate(y) and (x ~= 0 or y ~= 0) then
                return x, y, validCoordinate(z) and z or 0
            end
        end
    end
    if persistence.getSurvivorOrigin ~= nil then
        local ok, origin = pcall(persistence.getSurvivorOrigin, id)
        if ok and type(origin) == "table" then
            local x, y, z = tonumber(origin.x), tonumber(origin.y), tonumber(origin.z)
            if validCoordinate(x) and validCoordinate(y) and (x ~= 0 or y ~= 0) then
                return x, y, validCoordinate(z) and z or 0
            end
        end
    end
    return nil
end

local function selectDistantCandidate(filter, excludeId, anchorBody)
    local loaded = {}
    for _, id in ipairs(loadedIds()) do loaded[id] = true end
    local anchorX, anchorY = positionOf(anchorBody)
    local best, bestDistance = nil, nil
    for _, id in ipairs(livingIds()) do
        if id ~= excludeId and not loaded[id] then
            local entry = describeEntry(id, nil)
            if entry ~= nil and Catalog.matches(filter, entry.described) then
                local x, y, z = farLocation(id)
                if x ~= nil then
                    local distance = 0
                    if anchorX ~= nil and anchorY ~= nil then
                        distance = (x - anchorX) * (x - anchorX)
                            + (y - anchorY) * (y - anchorY)
                    end
                    if best == nil or distance < bestDistance then
                        best = { id = id, name = entry.name, x = x, y = y, z = z }
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best
end

local function followCamera(character)
    if character == nil then return false end
    local camera = rawget(_G, "IsoCamera")
    if camera == nil then return false end
    if camera.SetCharacterToFollow ~= nil then
        local ok = pcall(camera.SetCharacterToFollow, character)
        if ok then return true end
    end
    if camera.setCameraCharacter ~= nil then
        local ok = pcall(camera.setCameraCharacter, character)
        return ok
    end
    return false
end

local function capturePlayer(player)
    local x, y, z = positionOf(player)
    local function flag(name)
        local reader = player[name]
        if reader == nil then return nil end
        local ok, value = pcall(reader, player)
        return ok and value or nil
    end
    state.previous = {
        player = player,
        god = flag("isGodMod"),
        ghost = flag("isGhostMode"),
        invisible = flag("isInvisible"),
        invulnerable = flag("isInvulnerable"),
        zombies = flag("isZombiesDontAttack"),
        healthCheat = flag("isHealthCheat"),
        x = x, y = y, z = z,
    }
end

local function setFlag(player, method, value)
    if player == nil or player[method] == nil then return end
    pcall(function() player[method](player, value) end)
end

local function applySpectator(player)
    setFlag(player, "setGodMod", true)
    setFlag(player, "setGhostMode", true)
    setFlag(player, "setInvisible", true)
    setFlag(player, "setInvulnerable", true)
    setFlag(player, "setZombiesDontAttack", true)
    setFlag(player, "setHealthCheat", true)
end

local function restorePlayer()
    local previous = state.previous
    if previous == nil then return end
    local player = previous.player
    if player ~= nil then
        setFlag(player, "setGodMod", previous.god == true)
        setFlag(player, "setGhostMode", previous.ghost == true)
        setFlag(player, "setInvisible", previous.invisible == true)
        setFlag(player, "setInvulnerable", previous.invulnerable == true)
        setFlag(player, "setZombiesDontAttack", previous.zombies == true)
        setFlag(player, "setHealthCheat", previous.healthCheat == true)
        if previous.x ~= nil and previous.y ~= nil and player.teleportTo ~= nil then
            pcall(function()
                player:teleportTo(previous.x, previous.y, previous.z or 0)
            end)
        end
        followCamera(player)
    end
    state.previous = nil
end

local function ensureSpectator(player)
    if player == nil then return end
    if state.previous == nil or state.previous.player ~= player then
        if state.previous ~= nil then restorePlayer() end
        capturePlayer(player)
    end
    applySpectator(player)
end

local function beginJump(target)
    if target == nil then return false end
    local player = currentPlayer()
    if player == nil or playerDead(player) then return false end
    local vehicle = nil
    pcall(function() vehicle = player:getVehicle() end)
    if vehicle ~= nil then return false end
    ensureSpectator(player)
    local camera = rawget(_G, "IsoCamera")
    if camera ~= nil then
        if camera.clearCameraCharacter ~= nil then
            pcall(camera.clearCameraCharacter)
        elseif camera.setCameraCharacter ~= nil then
            pcall(camera.setCameraCharacter, nil)
        end
    end
    local moved = false
    if player.teleportTo ~= nil then
        moved = pcall(function() player:teleportTo(target.x, target.y, target.z or 0) end)
    end
    if not moved then
        moved = pcall(function()
            player:setX(target.x)
            player:setY(target.y)
            player:setZ(target.z or 0)
        end)
    end
    if not moved then return false end
    if installTicker ~= nil then installTicker() end
    state.jump = { id = target.id, name = target.name, started = ticks }
    state.pendingStart = false
    state.lostAt = nil
    state.nextLostSearch = 0
    state.waitingAnnounced = false
    feed("Moving to watch " .. tostring(target.name) .. ".")
    print(TAG .. " id=" .. tostring(target.id) .. " state=MOVING x="
        .. tostring(target.x) .. " y=" .. tostring(target.y))
    return true
end

local function anchorPlayer(player, body, force)
    if player == nil or body == nil then return false end
    local vehicle = nil
    pcall(function() vehicle = player:getVehicle() end)
    if vehicle ~= nil then return false end
    local bodyX, bodyY, bodyZ = positionOf(body)
    local playerX, playerY = positionOf(player)
    if not force and bodyX ~= nil and bodyY ~= nil
        and playerX ~= nil and playerY ~= nil then
        local dx, dy = bodyX - playerX, bodyY - playerY
        if dx * dx + dy * dy <= ANCHOR_DISTANCE_SQ then return true end
    end
    local square = nil
    pcall(function() square = body:getCurrentSquare() end)
    local moved = false
    if bodyX ~= nil and bodyY ~= nil and player.teleportTo ~= nil then
        moved = pcall(function() player:teleportTo(bodyX, bodyY, bodyZ or 0) end)
    end
    if not moved and bodyX ~= nil and bodyY ~= nil then
        pcall(function()
            player:setX(bodyX)
            player:setY(bodyY)
            player:setZ(bodyZ or 0)
        end)
        moved = true
    end
    if moved and square ~= nil and player.setCurrentSquare ~= nil then
        pcall(function() player:setCurrentSquare(square) end)
    end
    return moved
end

function Spectate.follow(id)
    if not Spectate.enabled() then return false, "disabled" end
    if type(id) ~= "string" or id == "" then return false, "invalid_id" end
    local body = bodyFor(id)
    if body == nil then return false, "not_loaded" end
    if bodyDead(body, id) then return false, "dead" end
    local player = currentPlayer()
    if player == nil then return false, "player_not_ready" end
    if playerDead(player) then return false, "player_dead" end
    state.jump = nil
    state.pendingStart = false
    state.nextLostSearch = 0
    ensureSpectator(player)
    state.active = true
    state.id = id
    state.body = body
    state.category = Spectate.category()
    state.lostAt = nil
    state.waitingAnnounced = false
    if installTicker ~= nil then installTicker() end
    anchorPlayer(player, body, true)
    followCamera(body)
    local entry = describeEntry(id, body)
    local name = entry ~= nil and entry.name or "Survivor"
    local label = entry ~= nil and entry.label or "Survivor"
    state.lastKnownName = name
    feed("Watching " .. name .. " (" .. label .. ").")
    print(TAG .. " id=" .. tostring(id) .. " state=WATCHING name=" .. name)
    return true, "watching"
end

function Spectate.watch(id)
    if not Spectate.enabled() then return false, "disabled" end
    if type(id) ~= "string" or id == "" then return false, "invalid_id" end
    local body = bodyFor(id)
    if body ~= nil and bodyDead(body, id) then return false, "dead" end
    if body ~= nil then return Spectate.follow(id) end
    local entry = describeEntry(id, nil)
    if entry == nil then return false, "missing" end
    local x, y, z = farLocation(id)
    if x == nil then return false, "no_location" end
    if beginJump({ id = id, name = entry.name, x = x, y = y, z = z }) then
        return true, "moving"
    end
    return false, "player_not_ready"
end

function Spectate.next()
    if not Spectate.enabled() then return false, "disabled" end
    local anchor = state.body or currentPlayer()
    local choice = selectCandidate(Spectate.category(), state.id, anchor)
    if choice == nil then choice = selectCandidate("any", state.id, anchor) end
    if choice ~= nil then return Spectate.follow(choice.id) end
    local target = selectDistantCandidate(Spectate.category(), state.id, anchor)
    if target == nil then target = selectDistantCandidate("any", state.id, anchor) end
    if target ~= nil and beginJump(target) then return true, "moving" end
    feed("No other living survivor is available to watch.")
    return false, "none"
end

local update

installTicker = function()
    if state.ticker or Events == nil or Events.OnTick == nil then return end
    local ok = pcall(function() Events.OnTick.Add(update) end)
    if ok then
        state.ticker = true
        state.nextUpdate = 0
    end
end

local function removeTicker()
    if not state.ticker then return end
    if Events ~= nil and Events.OnTick ~= nil and Events.OnTick.Remove ~= nil then
        pcall(function() Events.OnTick.Remove(update) end)
    end
    state.ticker = false
end

function Spectate.stop()
    local wasActive = state.active
    if not wasActive and state.previous == nil then return false, "not_watching" end
    state.active = false
    state.pendingStart = false
    state.id = nil
    state.body = nil
    state.lostAt = nil
    state.nextLostSearch = 0
    state.jump = nil
    state.waitingAnnounced = false
    state.lastKnownName = nil
    restorePlayer()
    removeTicker()
    if wasActive then feed("Spectating stopped. You are back in control.") end
    return true, "stopped"
end

function Spectate.status()
    return {
        enabled = Spectate.enabled(),
        active = state.active,
        id = state.id,
        category = state.category,
        debugBrowser = Spectate.debugBrowserAvailable(),
    }
end

update = function()
    if not state.ticker then return end
    ticks = ticks + 1
    if ticks < state.nextUpdate then return end
    state.nextUpdate = ticks + TICK_STEP

    if state.jump ~= nil then
        local target = state.jump
        local player = currentPlayer()
        if player ~= nil and playerDead(player) then
            state.jump = nil
            state.active = false
            state.id = nil
            state.body = nil
            state.previous = nil
            state.pendingStart = Spectate.enabled()
            return
        end
        local body = bodyFor(target.id)
        if body ~= nil and not bodyDead(body, target.id) then
            Spectate.follow(target.id)
            return
        end
        if ticks - target.started < JUMP_TIMEOUT_TICKS then return end
        state.jump = nil
        local nextTarget = nil
        if player ~= nil and not playerDead(player) then
            nextTarget = selectDistantCandidate(Spectate.category(), target.id, body or player)
            if nextTarget == nil then
                nextTarget = selectDistantCandidate("any", target.id, body or player)
            end
            if nextTarget ~= nil and beginJump(nextTarget) then return end
        end
        state.active = false
        state.id = nil
        state.body = nil
        state.lostAt = nil
        state.waitingAnnounced = true
        state.pendingStart = Spectate.enabled()
        state.nextSearch = ticks + START_SEARCH_INTERVAL
        feed("No other survivor is reachable yet. Waiting.")
        return
    end
    if state.pendingStart then
        if ticks < state.nextSearch then return end
        state.nextSearch = ticks + START_SEARCH_INTERVAL
        local player = currentPlayer()
        if player == nil or playerDead(player) then return end
        local choice = selectCandidate(Spectate.category(), nil, player)
        if choice == nil then choice = selectCandidate("any", nil, player) end
        if choice ~= nil then
            state.pendingStart = false
            Spectate.follow(choice.id)
            return
        end
        local target = selectDistantCandidate(Spectate.category(), nil, player)
        if target == nil then target = selectDistantCandidate("any", nil, player) end
        if target ~= nil then
            state.pendingStart = false
            if not beginJump(target) then state.pendingStart = true end
        end
        return
    end
    if not state.active then return end
    local player = currentPlayer()
    if player == nil then return end
    if playerDead(player) then
        state.active = false
        state.id = nil
        state.body = nil
        state.previous = nil
        state.pendingStart = Spectate.enabled()
        return
    end
    local body = state.body
    if body == nil then
        body = bodyFor(state.id)
        state.body = body
    end
    if body == nil or bodyDead(body, state.id) then
        if state.lostAt == nil then
            state.lostAt = ticks
            if state.lastKnownName ~= nil then
                feed(state.lastKnownName .. " is gone. Choosing another survivor.")
            end
        elseif ticks - state.lostAt >= LOST_GRACE_TICKS
            and ticks >= (state.nextLostSearch or 0) then
            state.nextLostSearch = ticks + START_SEARCH_INTERVAL
            local choice = selectCandidate(Spectate.category(), state.id, body or player)
            if choice == nil then choice = selectCandidate("any", state.id, body or player) end
            if choice ~= nil then
                Spectate.follow(choice.id)
            else
                local target = selectDistantCandidate(Spectate.category(), state.id, body or player)
                if target == nil then
                    target = selectDistantCandidate("any", state.id, body or player)
                end
                if target ~= nil and beginJump(target) then return end
                if not state.waitingAnnounced then
                    state.waitingAnnounced = true
                    feed("No other survivor is reachable yet. Waiting for one to appear.")
                end
            end
        end
        return
    end
    state.lostAt = nil
    state.waitingAnnounced = false
    if ticks >= state.nextAnchor then
        anchorPlayer(player, body, false)
        state.nextAnchor = ticks + ANCHOR_INTERVAL
    end
    local camera = rawget(_G, "IsoCamera")
    if camera ~= nil and camera.getCameraCharacter ~= nil then
        local ok, current = pcall(camera.getCameraCharacter)
        if not ok or current ~= body then followCamera(body) end
    end
end

local Window = ISCollapsableWindow:derive("KnoxDevSpectateWindow")
Window.__index = Window

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = math.max(8, UILayout.scaled(10))
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local rowH = math.max(20, fontH + 8)
    local titleH = self:titleBarHeight()
    local filterY = titleH + pad
    local filters = Catalog.filters()
    local gap = 4
    local available = math.max(1, self.width - pad * 2)
    local buttonWidth = math.max(1, math.floor((available - gap * (#filters - 1)) / #filters))
    self.filterButtons = {}
    for index, key in ipairs(filters) do
        local x = pad + (index - 1) * (buttonWidth + gap)
        local button = ISButton:new(x, filterY, buttonWidth, rowH,
            Catalog.filterLabel(key), self, function() Window.setFilter(self, key) end)
        button:initialise()
        UILayout.tintButton(button)
        self:addChild(button)
        self.filterButtons[key] = button
    end
    local statusY = filterY + rowH + 6
    local listTop = statusY + fontH + 6
    local footerY = self.height - pad - rowH
    local listHeight = math.max(rowH, footerY - 6 - listTop)
    self.listWidth = available
    self.listHeight = listHeight
    self.countLabel = ISLabel:new(pad, statusY, fontH, "", UILayout.theme.bone[1],
        UILayout.theme.bone[2], UILayout.theme.bone[3], 1, UIFont.Small, true)
    self.countLabel:initialise()
    self:addChild(self.countLabel)
    local list = ISScrollingListBox:new(pad, listTop, available, listHeight)
    list:initialise()
    list:instantiate()
    list.itemheight = rowH
    list.font = UIFont.Small
    list.fontHgt = fontH
    list.itemPadY = math.max(0, math.floor((rowH - fontH) / 2))
    list.textColor = { r = UILayout.theme.bone[1], g = UILayout.theme.bone[2],
        b = UILayout.theme.bone[3], a = 1 }
    list.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
        b = UILayout.theme.border[3], a = 0.8 }
    list.selectionColor = { r = UILayout.theme.amber[1], g = UILayout.theme.amber[2],
        b = UILayout.theme.amber[3], a = 0.3 }
    list.target = self
    list.onMouseDown = function(widget, x, y)
        if widget:isMouseOverScrollBar() then return end
        local row = widget:rowAt(x, y)
        if row >= 1 and widget.items[row] ~= nil then
            widget.selected = row
            Window.onPick(widget.target, widget.items[row].item)
        end
    end
    self.list = list
    self:addChild(list)
    local footerGap = 6
    local footerWidth = math.max(1, math.floor((available - footerGap * 2) / 3))
    local refresh = ISButton:new(pad, footerY, footerWidth, rowH, "Refresh", self,
        function() Window.refresh(self) end)
    refresh:initialise(); UILayout.tintButton(refresh); self:addChild(refresh)
    local nextButton = ISButton:new(pad + footerWidth + footerGap, footerY, footerWidth, rowH,
        "Watch Next", self, function()
            local ok = Spectate.next()
            if ok then Window.close(self) end
        end)
    nextButton:initialise(); UILayout.tintButton(nextButton); self:addChild(nextButton)
    local stopButton = ISButton:new(pad + (footerWidth + footerGap) * 2, footerY, footerWidth, rowH,
        "Stop Watching", self, function()
            Spectate.stop()
            Window.close(self)
        end)
    stopButton:initialise(); UILayout.tintButton(stopButton); self:addChild(stopButton)
    UILayout.finishWindow(self, "Close spectator")
    self:refresh()
end

function Window:refresh()
    if self.list == nil then return end
    local filter = self.filter or "any"
    local entries = Spectate.entries(filter)
    self.list:clear()
    for _, entry in ipairs(entries) do
        local label = entry.name .. " - " .. entry.label
        if entry.isGroupLeader or entry.isFactionLeader then label = label .. " [Leader]" end
        if not entry.loaded then label = label .. " [not loaded]" end
        local shown = UILayout.fitText(UIFont.Small, label, math.max(1, self.listWidth - 18))
        self.list:addItem(shown, entry, label)
    end
    if self.countLabel ~= nil then
        self.countLabel:setName(tostring(#entries) .. " living survivors - "
            .. Catalog.filterLabel(filter))
    end
end

function Window.setFilter(self, filter)
    if self == nil then return end
    self.filter = filter or "any"
    self:refresh()
end

function Window.onPick(self, entry)
    if self == nil or entry == nil then return end
    local ok, reason = Spectate.watch(entry.id)
    if ok then
        Window.close(self)
    elseif reason == "no_location" then
        feed(entry.name .. " has no saved position yet.")
    elseif reason == "dead" then
        feed(entry.name .. " is no longer alive.")
    else
        feed("Could not watch that survivor: " .. tostring(reason) .. ".")
    end
end

function Window:close()
    if self.knoxSpectateClosed then return end
    self.knoxSpectateClosed = true
    self:setVisible(false)
    self:removeFromUIManager()
    if state.window == self then state.window = nil end
end

function Window:new(playerNum)
    local player = playerNum or 0
    local screenW = type(getPlayerScreenWidth) == "function"
        and getPlayerScreenWidth(player) or 1280
    local screenH = type(getPlayerScreenHeight) == "function"
        and getPlayerScreenHeight(player) or 720
    local width = math.max(1, math.min(UILayout.scaled(620), screenW - 40))
    local height = math.max(1, math.min(UILayout.scaled(500), screenH - 40))
    local window = ISCollapsableWindow:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = player
    window.filter = "any"
    window:setTitle("Knox Survivor Spectator")
    pcall(function() window:setResizable(false) end)
    UILayout.tintWindow(window)
    return window
end

function Spectate.openBrowser(playerNum)
    if not Spectate.enabled() then return false, "disabled" end
    if not Spectate.debugBrowserAvailable() then
        feed("The survivor browser needs a debug launch, Developer Spectate and the debug browser option.")
        return false, "debug_required"
    end
    if state.window ~= nil then state.window:close() end
    local window = Window:new(playerNum or 0)
    window:initialise()
    local screenW = type(getPlayerScreenWidth) == "function"
        and getPlayerScreenWidth(window.playerNum) or window.width
    local screenH = type(getPlayerScreenHeight) == "function"
        and getPlayerScreenHeight(window.playerNum) or window.height
    local left = type(getPlayerScreenLeft) == "function" and getPlayerScreenLeft(window.playerNum) or 0
    local top = type(getPlayerScreenTop) == "function" and getPlayerScreenTop(window.playerNum) or 0
    window:setX(left + math.max(0, math.floor((screenW - window.width) / 2)))
    window:setY(top + math.max(0, math.floor((screenH - window.height) / 2)))
    if window.setRenderThisPlayerOnly ~= nil then
        window:setRenderThisPlayerOnly(window.playerNum)
    end
    window:addToUIManager()
    window:bringToTop()
    state.window = window
    return true, "browser"
end

local function onGameStart()
    state.pendingStart = Spectate.enabled()
    state.nextSearch = 0
    state.nextLostSearch = 0
    state.jump = nil
    state.lostAt = nil
    state.waitingAnnounced = false
    if state.pendingStart then installTicker() end
end

local function onCreatePlayer(playerNum, player)
    if Spectate.enabled() then
        state.pendingStart = true
        state.nextSearch = 0
        state.nextLostSearch = 0
        state.jump = nil
        state.lostAt = nil
        state.waitingAnnounced = false
        installTicker()
    end
end

local function onMainMenuEnter()
    removeTicker()
    if state.window ~= nil then state.window:close() end
    restorePlayer()
    state.active = false
    state.pendingStart = false
    state.id = nil
    state.body = nil
    state.lostAt = nil
    state.nextLostSearch = 0
    state.jump = nil
    state.waitingAnnounced = false
    state.lastKnownName = nil
end

if Events ~= nil then
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onGameStart) end
    if Events.OnCreatePlayer ~= nil then Events.OnCreatePlayer.Add(onCreatePlayer) end
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(onMainMenuEnter) end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not Spectate.enabled() then return end
    if test then
        if ISWorldObjectContextMenu.Test then return true end
        return ISWorldObjectContextMenu.setTest()
    end
    local root = context:addOption("Knox Survivors - Spectate", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption("Watch Next Survivor (" .. Catalog.filterLabel(Spectate.category()) .. ")",
        playerNum, Spectate.next)
    local browser = menu:addOption("Choose Survivor (Debug Browser)", playerNum,
        Spectate.openBrowser)
    browser.notAvailable = not Spectate.debugBrowserAvailable()
    menu:addOption("Stop Watching", playerNum, Spectate.stop)
end

if Events ~= nil and Events.OnFillWorldObjectContextMenu ~= nil then
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
end

return Spectate
