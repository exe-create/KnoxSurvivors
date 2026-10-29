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

function Nameplates.update(ticks)
    if tonumber(ticks) ~= nil and ticks % 15 ~= 0 then return end
    local enabled = KnoxSettings.showSurvivorNameplates()
    local distance = KnoxSettings.survivorNameplateDistance()
    labels = {}
    local viewerIds = {}
    if enabled then
        for number = 0, math.max(0, getNumActivePlayers() - 1) do
            local viewer = getSpecificPlayer(number)
            if viewer ~= nil then viewerIds[number] = KnoxPersistence.ensurePlayerId(viewer) end
        end
    end
    for _, id in ipairs(KnoxSurvivorRuntime.activeIds()) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        if character ~= nil then
            if enabled then
                local colors = {}
                for number, viewerId in pairs(viewerIds) do
                    colors[number] = COLORS[Nameplates.classify(id, viewerId)] or COLORS.neutral
                end
                labels[#labels + 1] = { id = id, character = character, name = fullName(id), colors = colors }
            end
            local player = enabled and nearestVisiblePlayer(character, distance * distance) or nil
            if player == nil then
                setVisible(character, false)
            else
                local playerId = KnoxPersistence.ensurePlayerId(player)
                -- Spending time nearby builds reputation passively.
                if playerId ~= nil and getGameTime ~= nil and getGameTime() ~= nil then
                    pcall(function()
                        KnoxPersistence.recordPlayerProximity(playerId, id,
                            getGameTime():getWorldAgeHours())
                    end)
                end
                local relation = Nameplates.classify(id, playerId)
                local color = COLORS[relation] or COLORS.neutral
                local name = fullName(id)
                pcall(function()
                    character:setUsername(name)
                    character:setDisplayName(name)
                    character:setTagColor(ColorInfo.new(color[1], color[2], color[3], 1))
                    character:setShowTag(true)
                end)
            end
        end
    end
end

-- Viewpoint exposes the NEXT view as a read-only enum: next first means
-- current ISO. Installed Viewpoint_Pad.lua uses this same nested Lua API.
local function cameraMode()
    local viewpoint = rawget(_G, "Viewpoint")
    if viewpoint == nil then return "iso" end
    local view = viewpoint.View
    if view == nil or view.next == nil then return nil end
    local ok, nextView = pcall(view.next)
    if not ok then return nil end
    if nextView == "first" then return "iso" end
    if nextView == "third" or nextView == "isometric" then return "perspective" end
    return nil
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
                        if alpha > 0 and finite(x) and finite(y) and x - halfWidth >= left and x + halfWidth <= left + width
                            and y >= top and y + fontHeight <= top + height then
                            local color = label.colors[playerNum] or COLORS.neutral
                            text:DrawStringCentre(UIFont.Small, x + 1, y + 1, label.name, 0, 0, 0, alpha)
                            text:DrawStringCentre(UIFont.Small, x, y, label.name, color[1], color[2], color[3], alpha)
                        end
                    end
                end
            end
        end
    end
end

function Nameplates.clear()
    labels = {}
    for _, id in ipairs(KnoxSurvivorRuntime.activeIds()) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        if character ~= nil then setVisible(character, false) end
    end
end

Events.OnPreUIDraw.Add(Nameplates.render)
Events.OnGameStart.Add(Nameplates.clear)

return Nameplates
