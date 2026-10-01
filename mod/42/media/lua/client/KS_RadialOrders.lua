-- Knox radial orders: a vanilla-style command hierarchy on the emote radial.
--
--   Knox Orders -> Party Orders  -> quick commands + categorized More pages
--               -> Followers     -> <companion> -> movement/survival/policies
--               -> Residents     -> <resident>  -> needs/work/supply/policies
--               -> Nearby Survivors -> <stranger> -> (talk/recruit)
--
-- Design rules that keep this conflict-safe:
--   * Hook ISEmoteRadialMenu:fillMenu (proven Build 42 API) only. The
--     original fill runs first every time; Knox appends a single base-level
--     "Knox Orders" slice. Submenus render through our own fill function,
--     never by mutating the vanilla menu table.
--   * Every callback carries (radialSelf, ...) and resolves the player from
--     radialSelf.playerNum, so splitscreen players command only their own.
--   * After any order the wheel rebuilds at the SAME level (vanilla closes
--     it first; our fill re-adds the same instance). Membership revalidates
--     on every fill, so recruit/recall transitions show up immediately.
--   * All dispatch reuses CompanionService verbs. No dismiss/recruit-outside
--     -nearby (recruit lives only in Nearby), no position-bound orders
--     (Movement, location directives, driving stay in the world/map menus).
--   * Absent/incompatible API (or any error) -> dormant one-line log and no
--     wrapping. Right-click order visibility remains a separate save option.

require "KS_Settings"

local Radial = rawget(_G, "KnoxRadialOrders") or {}
_G.KnoxRadialOrders = Radial

local installed = false
local loggedDormant = false
local previousFill = nil

local function featureEnabled()
    local settings = rawget(_G, "KnoxSettings")
    if type(settings) ~= "table" or type(settings.showRadialOrders) ~= "function" then
        return true
    end
    local ok, enabled = pcall(settings.showRadialOrders)
    return ok and enabled ~= false
end

-- Transients only: rebuilt on every fill, never persisted.
local NEARBY_TILES_SQUARED = 49

local PARTY_ORDERS = {
    { kind = "follow", label = "Follow", fallbackIcon = "followme" },
    { kind = "hold", label = "Hold", fallbackIcon = "stop" },
    { kind = "relax", label = "Relax", fallbackIcon = "signalok" },
    { kind = "return_to_base", label = "Return to Base", fallbackIcon = "comehere" },
    { kind = "check_needs", label = "Check Needs", fallbackIcon = "signalok" },
    { kind = "more", label = "More Orders", fallbackIcon = "group" },
}

-- Second party level: movements anchored on the player, combat stances,
-- and traversal permissions. All route through the existing
-- issueOrderAll boundary with the same payloads as the map menu.
local PARTY_MORE = {
    { kind = "movements", label = "Movements", fallbackIcon = "moveout" },
    { kind = "tactics", label = "Tactics", fallbackIcon = "stop" },
    { kind = "permissions", label = "Permissions", fallbackIcon = "signalok" },
    { kind = "vehicles", label = "Vehicles", fallbackIcon = "group" },
    { kind = "pickup", label = "Pickup", fallbackIcon = "moveout" },
    { kind = "formation", label = "Formation", fallbackIcon = "group" },
    { kind = "equipment", label = "Equipment", fallbackIcon = "signalok" },
}
local PARTY_MOVEMENTS = {
    { kind = "regroup", label = "Regroup on Me", fallbackIcon = "comehere" },
    { kind = "patrol_here", label = "Patrol Here", fallbackIcon = "moveout" },
    { kind = "guard_here", label = "Guard Here", fallbackIcon = "stop" },
}
local PARTY_TACTICS = {
    { kind = "aggressive", label = "Stance: Aggressive", fallbackIcon = "stop" },
    { kind = "defensive", label = "Stance: Defensive", fallbackIcon = "signalok" },
    { kind = "passive", label = "Stance: Passive", fallbackIcon = "followme" },
}
local PARTY_PERMISSIONS = {
    { kind = "allow_climbing", label = "Climbing On", fallbackIcon = "moveout" },
    { kind = "disallow_climbing", label = "Climbing Off", fallbackIcon = "signalok" },
    { kind = "allow_doors", label = "Doors On", fallbackIcon = "moveout" },
    { kind = "disallow_doors", label = "Doors Off", fallbackIcon = "signalok" },
    { kind = "weapon_melee", label = "Weapons: Melee", fallbackIcon = "stop" },
    { kind = "weapon_ranged", label = "Weapons: Ranged", fallbackIcon = "stop" },
    { kind = "weapon_auto", label = "Weapons: Choice", fallbackIcon = "signalok" },
}
local PARTY_VEHICLES = {
    { kind = "enter_vehicle", label = "Enter My Vehicle", fallbackIcon = "group" },
    { kind = "exit_vehicle", label = "Exit Vehicle", fallbackIcon = "back" },
}
local PARTY_PICKUP = {
    { kind = "enable_autoloot", label = "Pick Up Useful Items", fallbackIcon = "moveout" },
    { kind = "disable_autoloot", label = "Do Not Pick Up Items", fallbackIcon = "signalok" },
}
local PARTY_EQUIPMENT = {
    { kind = "enable_auto_equipment", label = "Upgrade Better Gear", fallbackIcon = "moveout" },
    { kind = "disable_auto_equipment", label = "Keep Current Equipment", fallbackIcon = "stop" },
}

local SOLO_ORDERS = {
    { kind = "movement", label = "Movement", fallbackIcon = "followme" },
    { kind = "survival", label = "Survival", fallbackIcon = "moveout" },
    { kind = "tactics", label = "Tactics", fallbackIcon = "stop" },
    { kind = "vehicles", label = "Vehicles", fallbackIcon = "group" },
    { kind = "more", label = "More Orders", fallbackIcon = "signalok" },
}

local FOLLOWER_MOVEMENTS = {
    { kind = "follow", label = "Follow", fallbackIcon = "followme" },
    { kind = "hold", label = "Hold", fallbackIcon = "stop" },
    { kind = "relax", label = "Relax", fallbackIcon = "signalok" },
    { kind = "go_to", label = "Come to Me", fallbackIcon = "comehere" },
    { kind = "more_movement", label = "More Movement", fallbackIcon = "group" },
}
local FOLLOWER_MOVEMENTS_MORE = {
    { kind = "guard", label = "Guard Here", fallbackIcon = "stop" },
    { kind = "patrol", label = "Patrol Here", fallbackIcon = "moveout" },
    { kind = "resume_normal_duty", label = "Clear Current Order", fallbackIcon = "back" },
    { kind = "return_to_base", label = "Return to Base", fallbackIcon = "group" },
}

local FOLLOWER_MORE = {
    { kind = "formation", label = "Formation", fallbackIcon = "group" },
    { kind = "gear", label = "Gear & Pickup", fallbackIcon = "moveout" },
    { kind = "check_needs", label = "Check Needs", fallbackIcon = "signalok" },
    { kind = "unstick", label = "Unstick", fallbackIcon = "back" },
    { kind = "dismiss", label = "Dismiss from Party", fallbackIcon = "shrug" },
}

local FOLLOWER_GEAR = {
    { kind = "weapon_melee", label = "Prefer Melee", fallbackIcon = "stop" },
    { kind = "weapon_ranged", label = "Prefer Ranged", fallbackIcon = "stop" },
    { kind = "weapon_auto", label = "Survivor Choice", fallbackIcon = "signalok" },
    { kind = "enable_autoequipment", label = "Upgrade Gear", fallbackIcon = "moveout" },
    { kind = "disable_autoequipment", label = "Keep Current Gear", fallbackIcon = "stop" },
    { kind = "enable_autoloot", label = "Pick Up Useful Items", fallbackIcon = "moveout" },
    { kind = "disable_autoloot", label = "Do Not Pick Up Items", fallbackIcon = "signalok" },
}

local FOLLOWER_FORMATION = {
    { label = "Paired - spacing 1", formation = "paired", spacing = 1 },
    { label = "Paired - spacing 2", formation = "paired", spacing = 2 },
    { label = "Paired - spacing 3", formation = "paired", spacing = 3 },
    { label = "Single File - spacing 1", formation = "single_file", spacing = 1 },
    { label = "Single File - spacing 2", formation = "single_file", spacing = 2 },
    { label = "Single File - spacing 3", formation = "single_file", spacing = 3 },
}

local RESIDENT_WORK = { "auto", "guard", "patrol", "rest" }
local RESIDENT_WORK_MORE = { "cooking", "farming", "woodwork", "barricade", "hauling", "repair" }

-- Follower tactics: stance, climbing and doors are companion policies, so
-- they are valid here (residents cannot take them; their wheel omits them).
local FOLLOWER_TACTICS = {
    { kind = "stance_aggressive", label = "Stance: Aggressive", fallbackIcon = "stop" },
    { kind = "stance_defensive", label = "Stance: Defensive", fallbackIcon = "signalok" },
    { kind = "stance_passive", label = "Stance: Passive", fallbackIcon = "followme" },
    { kind = "climb_on", label = "Climbing On", fallbackIcon = "moveout" },
    { kind = "climb_off", label = "Climbing Off", fallbackIcon = "signalok" },
    { kind = "doors_on", label = "Doors On", fallbackIcon = "moveout" },
    { kind = "doors_off", label = "Doors Off", fallbackIcon = "signalok" },
}

-- Base residents cannot take companion-only policies (follow/hold/relax,
-- autoloot, doors, vehicles). Their wheel includes needs, supplies, work,
-- resident policies, recall, and unstick. Survival kinds route to base supply
-- through the normal issueOrder boundary, never party-wide.
local RESIDENT_ORDERS = {
    { kind = "check_needs", label = "Check Needs", fallbackIcon = "signalok" },
    { kind = "survival", label = "Survival Orders", fallbackIcon = "moveout" },
    { kind = "recall_to_party", label = "Recall to Party", fallbackIcon = "comehere" },
    { kind = "work", label = "Work Preference", fallbackIcon = "group" },
    { kind = "resident_policies", label = "Resident Policies", fallbackIcon = "signalok" },
    { kind = "resume_normal_duty", label = "Cancel Supply Order", fallbackIcon = "back" },
    { kind = "unstick", label = "Unstick", fallbackIcon = "signalok" },
}

-- Survivor-specific survival orders. Followers get a bounded search around
-- themselves; residents get a durable base supply duty. Pages split supported
-- categories so the entire list is not placed on one ring.
local SURVIVAL_FOLLOWER = { "find_food", "find_water", "find_medical", "find_weapon", "find_tools" }
local SURVIVAL_FOLLOWER_MORE = { "find_wood", "find_materials", "find_clothing", "find_ammo", "clean_inventory" }
local SURVIVAL_RESIDENT = { "find_food", "find_water", "find_wood", "find_medical", "find_weapon", "find_tools" }
local SURVIVAL_RESIDENT_MORE = { "find_materials", "find_clothing", "find_ammo" }

-- Nearby survivors use the same eligibility-aware interaction window as the
-- F prompt. Do not maintain a second social action
-- list on the radial.
local NEARBY_ORDERS = {
    { kind = "interact", label = "Interact", fallbackIcon = "wavehi" },
}

local function dormant(reason)
    if not loggedDormant then
        loggedDormant = true
        print("[KnoxSurvivors][Radial] dormant reason=" .. tostring(reason)
            .. " context_menus_unchanged=true")
    end
    return false
end

local function playerFor(playerNum)
    local player = nil
    pcall(function()
        if getSpecificPlayer ~= nil then player = getSpecificPlayer(playerNum) end
    end)
    return player
end

local function radialMenuFor(playerNum)
    local menu = nil
    pcall(function()
        if getPlayerRadialMenu ~= nil then menu = getPlayerRadialMenu(playerNum) end
    end)
    return menu
end

local function orderLabel(kind, fallback)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.label ~= nil then
        local ok, value = pcall(function() return catalog.label(kind, fallback) end)
        if ok and value ~= nil and value ~= "" then return tostring(value) end
    end
    return fallback or tostring(kind)
end

local function iconFor(name)
    local emoteMenu = rawget(_G, "ISEmoteRadialMenu")
    if emoteMenu ~= nil and emoteMenu.icons ~= nil then
        local ok, icon = pcall(function() return emoteMenu.icons[name] end)
        if ok then return icon end
    end
    return nil
end

-- Custom Knox button art: drop a file at media/ui/knoxOrders.png in the mod
-- and it is picked up automatically, no code change. Falls back to the
-- vanilla group icon until then.
local function knoxButtonIcon()
    if getTexture ~= nil then
        local ok, texture = pcall(function()
            return getTexture("media/ui/knoxOrders.png")
        end)
        if ok and texture ~= nil then return texture end
    end
    return iconFor("group")
end

-- Per-survivor slice icon. There is no face Texture anywhere (HUD portraits
-- are live 3D models; faces are shader-driven), so slices use the same
-- sex-specific body outline the survivor card uses.
local function survivorIcon(id, playerNum)
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.getSurvivor ~= nil and getTexture ~= nil then
        local ok, view = pcall(function()
            return viewModel.getSurvivor(id, playerNum)
        end)
        if ok and type(view) == "table" and view.sex ~= nil
            and tostring(view.sex) ~= "" then
            local okTex, texture = pcall(function()
                return getTexture("media/ui/defense/"
                    .. tostring(view.sex) .. "_base.png")
            end)
            if okTex and texture ~= nil then return texture end
        end
    end
    return nil
end

local function backLabel()
    local ok, value = pcall(function() return getText("IGUI_Emote_Back") end)
    if ok and value ~= nil then return tostring(value) end
    return "Back"
end

local function survivorName(id, playerNum)
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel ~= nil and viewModel.getSurvivor ~= nil then
        local ok, view = pcall(function()
            return viewModel.getSurvivor(id, playerNum)
        end)
        if ok and type(view) == "table" and view.displayName ~= nil
            and tostring(view.displayName) ~= "" then
            return tostring(view.displayName)
        end
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil then
        local ok, identity = pcall(function()
            return persistence.getSurvivorIdentity(id)
        end)
        if ok and type(identity) == "table" then
            local name = tostring(identity.forename or "")
            if identity.surname ~= nil and tostring(identity.surname) ~= "" then
                name = name .. " " .. tostring(identity.surname)
            end
            if name ~= "" then return name end
        end
    end
    return tostring(id)
end

local function playerSquare(player)
    if player == nil then return nil end
    local ok, square = pcall(function() return player:getCurrentSquare() end)
    if ok then return square end
    return nil
end

local function squareNear(origin, square)
    if origin == nil or square == nil or square.getX == nil
        or origin.getX == nil then
        return false
    end
    if square:getZ() ~= origin:getZ() then return false end
    return (square:getX() - origin:getX()) ^ 2
        + (square:getY() - origin:getY()) ^ 2 <= NEARBY_TILES_SQUARED
end

local function characterSquare(character)
    if character == nil then return nil end
    local ok, square = pcall(function() return character:getCurrentSquare() end)
    if ok then return square end
    return nil
end

local function sortMembers(found)
    table.sort(found, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.id) < tostring(b.id)
    end)
    return found
end

local function companionIdSet(player)
    local service = rawget(_G, "KnoxCompanionService")
    local set, list = {}, {}
    if service == nil or service.getCompanionIds == nil or player == nil then
        return set, list
    end
    local ok, ids = pcall(function() return service.getCompanionIds(player) end)
    if ok and type(ids) == "table" then
        for _, id in ipairs(ids) do
            set[tostring(id)] = true
            list[#list + 1] = id
        end
    end
    return set, list
end

local function liveCharacter(id)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.getCharacter == nil then return nil end
    local ok, character = pcall(function() return runtime.getCharacter(id) end)
    if ok then return character end
    return nil
end

local function aliveCheck(id)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.isSurvivorAlive ~= nil then
        local ok, alive = pcall(function()
            return persistence.isSurvivorAlive(id)
        end)
        if ok then return alive ~= false end
    end
    return true
end

-- Owned companions near the player (the Followers tab).
local function followerMembers(playerNum)
    local player = playerFor(playerNum)
    if player == nil then return {} end
    local origin = playerSquare(player)
    if origin == nil then return {} end
    local _, list = companionIdSet(player)
    local found = {}
    for _, id in ipairs(list) do
        if aliveCheck(id) and squareNear(origin, characterSquare(liveCharacter(id))) then
            found[#found + 1] = { id = id, name = survivorName(id, playerNum) }
        end
    end
    return sortMembers(found)
end

-- The player's base residents near the player (the Residents tab).
-- Companion-roster members are companions, never residents here.
local function residentMembers(playerNum)
    local player = playerFor(playerNum)
    local service = rawget(_G, "KnoxCompanionService")
    local manager = rawget(_G, "KnoxBaseManager")
    local persistence = rawget(_G, "KnoxPersistence")
    if player == nil or service == nil or service.getPlayerId == nil
        or manager == nil or manager.getForOwner == nil
        or persistence == nil or persistence.getBaseResidentIds == nil then
        return {}
    end
    local origin = playerSquare(player)
    if origin == nil then return {} end
    local okId, playerId = pcall(function() return service.getPlayerId(player) end)
    if not okId or playerId == nil then return {} end
    local bases = {}
    if persistence.getBasesForOwner ~= nil then
        local okBases, list = pcall(function()
            return persistence.getBasesForOwner("player", playerId)
        end)
        if okBases and type(list) == "table" then bases = list end
    end
    if #bases == 0 then
        local okBase, base = pcall(function()
            return manager.getForOwner("player", playerId)
        end)
        if okBase and base ~= nil and base.id ~= nil then bases = { base } end
    end
    if #bases == 0 then return {} end
    local companions = companionIdSet(player)
    local found, seen = {}, {}
    for _, base in ipairs(bases) do
        if base ~= nil and base.id ~= nil then
            local okIds, ids = pcall(function()
                return persistence.getBaseResidentIds(base.id)
            end)
            if okIds and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local key = tostring(id)
                    if not seen[key] and companions[key] == nil and aliveCheck(id)
                        and squareNear(origin, characterSquare(liveCharacter(id))) then
                        seen[key] = true
                        found[#found + 1] = { id = id, name = survivorName(id, playerNum) }
                    end
                end
            end
        end
    end
    return sortMembers(found)
end

-- Loaded non-owned survivors near the player (the Nearby tab). Anyone
-- player-affiliated is excluded so there is no poaching confusion.
local function nearbyMembers(playerNum)
    local player = playerFor(playerNum)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local persistence = rawget(_G, "KnoxPersistence")
    if player == nil or runtime == nil or runtime.activeIds == nil then
        return {}
    end
    local origin = playerSquare(player)
    if origin == nil then return {} end
    local okIds, ids = pcall(function() return runtime.activeIds() end)
    if not okIds or type(ids) ~= "table" then return {} end
    local companions = companionIdSet(player)
    local found, seen = {}, {}
    for _, id in ipairs(ids) do
        local key = tostring(id)
        if seen[key] == nil and companions[key] == nil then
            seen[key] = true
            local owned = false
            if persistence ~= nil and persistence.getSurvivorAffiliation ~= nil then
                local okAff, affiliation = pcall(function()
                    return persistence.getSurvivorAffiliation(id)
                end)
                if okAff and type(affiliation) == "table"
                    and affiliation.kind == "player" then
                    owned = true
                end
            end
            if not owned and aliveCheck(id)
                and squareNear(origin, characterSquare(liveCharacter(id))) then
                found[#found + 1] = { id = id, name = survivorName(id, playerNum) }
            end
        end
    end
    return sortMembers(found)
end

local function memberIn(list, id)
    for _, member in ipairs(list or {}) do
        if tostring(member.id) == tostring(id) then return true end
    end
    return false
end

-- Party-level order slice callback: invoked as callback(radialSelf, kind).
-- The wheel rebuilds at the party level afterwards.
function Radial.orderParty(radialSelf, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueOrderAll == nil or type(kind) ~= "string" then
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    if kind == "more" then
        Radial.fillKnox(radialSelf, "knox_party_more")
        return
    end
    if kind == "return_to_base" then
        local ids = {}
        if service.getCompanionIds ~= nil then
            local ok, list = pcall(function() return service.getCompanionIds(player) end)
            if ok and type(list) == "table" then ids = list end
        end
        Radial.sendHomeWithPicker(radialSelf, ids, "knox_party")
        return
    end
    pcall(function() service.issueOrderAll(player, kind) end)
    Radial.fillKnox(radialSelf, "knox_party")
end

-- Send-home with a base choice. One home: direct, exactly as before.
-- Several: prompt once (base names + cancel) and send everyone to it.
function Radial.sendHomeWithPicker(radialSelf, ids, refillKey)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or type(ids) ~= "table" or #ids == 0 then
        if refillKey ~= nil then Radial.fillKnox(radialSelf, refillKey) end
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    local bases = {}
    if service.getPlayerId ~= nil then
        local persistence = rawget(_G, "KnoxPersistence")
        local okPid, pid = pcall(function() return service.getPlayerId(player) end)
        if okPid and pid ~= nil and persistence ~= nil
            and persistence.getBasesForOwner ~= nil then
            local okList, list = pcall(function()
                return persistence.getBasesForOwner("player", pid)
            end)
            if okList and type(list) == "table" then bases = list end
        end
    end
    local picker = rawget(_G, "KnoxBasePicker")
    if #bases > 1 and picker ~= nil and picker.choose ~= nil then
        local prompted = picker.choose(playerNum, "Send home to which base?", bases,
            function(baseId)
                if baseId == nil then return end
                pcall(function()
                    for _, survivorId in ipairs(ids) do
                        service.sendToBase(player, survivorId, baseId)
                    end
                end)
                Radial.fillKnox(radialSelf, refillKey)
            end)
        if prompted then return end
    end
    pcall(function()
        for _, survivorId in ipairs(ids) do
            service.sendToBase(player, survivorId)
        end
    end)
    Radial.fillKnox(radialSelf, refillKey)
end

-- Party submenu navigation: "pm:<level>" keys mirror the follower style.
function Radial.orderPartyMore(radialSelf, level)
    if type(level) == "string" and (level == "move" or level == "tactics"
        or level == "perms" or level == "vehicles" or level == "pickup"
        or level == "formation" or level == "equipment") then
        Radial.fillKnox(radialSelf, "pm:" .. level)
        return
    end
    Radial.fillKnox(radialSelf, "knox_party_more")
end

function Radial.orderPartyFormation(radialSelf, formation, spacing)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if service ~= nil and service.setFormation ~= nil and player ~= nil then
        for _, id in ipairs(service.getCompanionIds(player) or {}) do
            pcall(service.setFormation, player, id, formation, spacing)
        end
    end
    Radial.fillKnox(radialSelf, "pm:formation")
end

function Radial.orderPartyEquipment(radialSelf, allowed)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if service ~= nil and service.setAutoEquipmentAll ~= nil and player ~= nil then
        pcall(service.setAutoEquipmentAll, player, allowed == true)
    end
    Radial.fillKnox(radialSelf, "pm:equipment")
end

local function playerSquarePayload(player, radius)
    local square = player ~= nil and player:getCurrentSquare() or nil
    if square == nil then return nil end
    radius = tonumber(radius) or 0
    return {
        minX = square:getX() - radius, minY = square:getY() - radius,
        maxX = square:getX() + radius, maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

-- Player-anchored movements: regroup on the player, patrol or guard around
-- them. Same payload shape as the map location menu.
function Radial.orderPartyMove(radialSelf, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueOrderAll == nil or type(kind) ~= "string" then
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    local orderKind, payload = nil, nil
    if kind == "regroup" then
        orderKind = "go_to"
        payload = playerSquarePayload(player, 0)
        if payload ~= nil then payload.kind = "go_to" end
    elseif kind == "patrol_here" then
        orderKind = "patrol_area"
        payload = playerSquarePayload(player, 10)
        if payload ~= nil then payload.kind = "patrol_area" end
    elseif kind == "guard_here" then
        orderKind = "guard"
        payload = playerSquarePayload(player, 0)
        if payload ~= nil then payload.kind = "guard" end
    end
    if orderKind == nil or payload == nil then return end
    pcall(function() service.issueOrderAll(player, orderKind, payload) end)
    Radial.fillKnox(radialSelf, "pm:move")
end

function Radial.orderPartyStance(radialSelf, stance)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueOrderAll == nil or type(stance) ~= "string" then
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    pcall(function() service.issueOrderAll(player, "combat_stance", stance) end)
    Radial.fillKnox(radialSelf, "pm:tactics")
end

function Radial.orderPartyPerm(radialSelf, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueOrderAll == nil or type(kind) ~= "string" then
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    pcall(function() service.issueOrderAll(player, kind) end)
    Radial.fillKnox(radialSelf, "pm:perms")
end

function Radial.orderPartyWeapon(radialSelf, preference)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueOrderAll == nil or type(preference) ~= "string" then
        return
    end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    pcall(function() service.issueOrderAll(player, "weapon_preference", preference) end)
    Radial.fillKnox(radialSelf, "pm:perms")
end

-- Follower order slice callback: invoked as callback(radialSelf, id, kind).
function Radial.orderOne(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or survivorId == nil or type(kind) ~= "string" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    if kind == "movement" then
        Radial.fillKnox(radialSelf, "fm:" .. tostring(survivorId)); return
    elseif kind == "vehicles" then
        Radial.fillKnox(radialSelf, "fv:" .. tostring(survivorId)); return
    elseif kind == "more" then
        Radial.fillKnox(radialSelf, "fmore:" .. tostring(survivorId)); return
    elseif kind == "more_movement" then
        Radial.fillKnox(radialSelf, "fm2:" .. tostring(survivorId)); return
    end
    if kind == "survival" then
        Radial.fillKnox(radialSelf, "sf:" .. tostring(survivorId))
        return
    end
    if kind == "tactics" then
        Radial.fillKnox(radialSelf, "ft:" .. tostring(survivorId))
        return
    end
    if kind == "return_to_base" then
        Radial.sendHomeWithPicker(radialSelf, { survivorId }, "f:" .. tostring(survivorId))
        return
    end
    pcall(function()
        if kind == "unstick" and service.unstick ~= nil then
            service.unstick(player, survivorId)
        elseif service.issueOrder ~= nil then
            service.issueOrder(player, survivorId, kind)
        end
    end)
    Radial.fillKnox(radialSelf, "f:" .. tostring(survivorId))
end

function Radial.orderFormationF(radialSelf, survivorId, formation, spacing)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if service ~= nil and service.setFormation ~= nil and player ~= nil then
        pcall(service.setFormation, player, survivorId, formation, spacing)
    end
    Radial.fillKnox(radialSelf, "ff:" .. tostring(survivorId))
end

function Radial.orderGearF(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if service ~= nil and player ~= nil then
        pcall(function()
            if kind == "weapon_melee" or kind == "weapon_ranged" or kind == "weapon_auto" then
                if service.setWeaponPreference ~= nil then
                    service.setWeaponPreference(player, survivorId,
                        kind == "weapon_melee" and "melee" or kind == "weapon_ranged" and "ranged" or "auto")
                end
            elseif kind == "enable_autoequipment" or kind == "disable_autoequipment" then
                if service.setAutoEquipment ~= nil then
                    service.setAutoEquipment(player, survivorId, kind == "enable_autoequipment")
                end
            elseif service.issueOrder ~= nil then
                service.issueOrder(player, survivorId, kind)
            end
        end)
    end
    Radial.fillKnox(radialSelf, "fg:" .. tostring(survivorId))
end

function Radial.orderResidentPreference(radialSelf, survivorId, preference)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    local persistence = rawget(_G, "KnoxPersistence")
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(survivorId) or {}
    if service ~= nil and service.setBaseJobPreference ~= nil and player ~= nil
        and duty.baseId ~= nil then
        pcall(service.setBaseJobPreference, player, survivorId, preference, duty.baseId)
    end
    Radial.fillKnox(radialSelf, "rw:" .. tostring(survivorId))
end

function Radial.orderResidentPolicy(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if service ~= nil and player ~= nil then
        pcall(function()
            if kind == "loot_runs_on" and service.setResidentLootRuns ~= nil then
                service.setResidentLootRuns(player, survivorId, true)
            elseif kind == "loot_runs_off" and service.setResidentLootRuns ~= nil then
                service.setResidentLootRuns(player, survivorId, false)
            elseif kind == "equipment_on" and service.setAutoEquipment ~= nil then
                service.setAutoEquipment(player, survivorId, true)
            elseif kind == "equipment_off" and service.setAutoEquipment ~= nil then
                service.setAutoEquipment(player, survivorId, false)
            end
        end)
    end
    Radial.fillKnox(radialSelf, "rp:" .. tostring(survivorId))
end

-- Follower tactics slice: stance, climbing and doors through the
-- per-survivor service boundary (all companion-gated upstream).
function Radial.orderTacticsF(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or survivorId == nil or type(kind) ~= "string" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    pcall(function()
        if kind == "stance_aggressive" and service.setCombatStance ~= nil then
            service.setCombatStance(player, survivorId, "aggressive")
        elseif kind == "stance_defensive" and service.setCombatStance ~= nil then
            service.setCombatStance(player, survivorId, "defensive")
        elseif kind == "stance_passive" and service.setCombatStance ~= nil then
            service.setCombatStance(player, survivorId, "passive")
        elseif kind == "climb_on" and service.setClimbing ~= nil then
            service.setClimbing(player, survivorId, true)
        elseif kind == "climb_off" and service.setClimbing ~= nil then
            service.setClimbing(player, survivorId, false)
        elseif kind == "doors_on" and service.setDoorOpening ~= nil then
            service.setDoorOpening(player, survivorId, true)
        elseif kind == "doors_off" and service.setDoorOpening ~= nil then
            service.setDoorOpening(player, survivorId, false)
        end
    end)
    Radial.fillKnox(radialSelf, "ft:" .. tostring(survivorId))
end

-- Survival submenu slice: survivor-specific find_* through issueOrder.
function Radial.orderSurvivalF(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or survivorId == nil or type(kind) ~= "string" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    if kind == "more_supplies" then
        Radial.fillKnox(radialSelf, "sf2:" .. tostring(survivorId)); return
    end
    pcall(function()
        if service.issueOrder ~= nil then
            service.issueOrder(player, survivorId, kind)
        end
    end)
    Radial.fillKnox(radialSelf, "sf:" .. tostring(survivorId))
end

-- Resident order slice callback: invoked as callback(radialSelf, id, kind).
function Radial.orderResident(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or survivorId == nil or type(kind) ~= "string" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    if kind == "work" then
        Radial.fillKnox(radialSelf, "rw:" .. tostring(survivorId)); return
    elseif kind == "resident_policies" then
        Radial.fillKnox(radialSelf, "rp:" .. tostring(survivorId)); return
    end
    if kind == "survival" then
        Radial.fillKnox(radialSelf, "sr:" .. tostring(survivorId))
        return
    end
    pcall(function()
        if kind == "recall_to_party" and service.recallToParty ~= nil then
            service.recallToParty(player, survivorId)
        elseif kind == "unstick" and service.unstick ~= nil then
            service.unstick(player, survivorId)
        elseif service.issueOrder ~= nil then
            service.issueOrder(player, survivorId, kind)
        end
    end)
    Radial.fillKnox(radialSelf, "r:" .. tostring(survivorId))
end

-- Resident survival submenu slice: base supply orders through issueOrder.
function Radial.orderSurvivalR(radialSelf, survivorId, kind)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or survivorId == nil or type(kind) ~= "string" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    if kind == "more_supplies" then
        Radial.fillKnox(radialSelf, "sr2:" .. tostring(survivorId)); return
    end
    pcall(function()
        if service.issueOrder ~= nil then
            service.issueOrder(player, survivorId, kind)
        end
    end)
    Radial.fillKnox(radialSelf, "sr:" .. tostring(survivorId))
end

-- Nearby-stranger slice callback: invoked as callback(radialSelf, id, kind).
function Radial.orderNearby(radialSelf, survivorId, kind)
    if survivorId == nil or kind ~= "interact" then return end
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local player = playerFor(playerNum)
    if player == nil then return end
    local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if interaction == nil or interaction.open == nil or runtime == nil
        or runtime.getCharacter == nil then return end
    local character = runtime.getCharacter(survivorId)
    if character == nil then return end
    local view = viewModel ~= nil and viewModel.getSurvivor ~= nil
        and viewModel.getSurvivor(survivorId, playerNum) or nil
    local name = view ~= nil and view.displayName or survivorName(survivorId, playerNum)
    pcall(interaction.open, playerNum,
        { id = survivorId, character = character, name = name }, player)
    Radial.fillKnox(radialSelf, "n:" .. tostring(survivorId))
end

local function showMenu(playerNum)
    local menu = radialMenuFor(playerNum)
    if menu ~= nil then
        pcall(function() menu:addToUIManager() end)
    end
    return menu
end

local function addBack(menu, radialSelf, level)
    menu:addSlice(backLabel(), iconFor("back"), Radial.fillKnox,
        radialSelf, level)
end

-- Knox submenu fill. Key is "knox", "knox_party", "knox_party_more",
-- "pm:move", "pm:tactics", "pm:perms", "knox_followers", "knox_residents",
-- "knox_nearby", "f:<id>", "r:<id>", "n:<id>", and typed follower/resident
-- pages. Each level stays short and sends actions through existing services.
-- Mirrors the vanilla fill contract (clear, add slices, display).
function Radial.fillKnox(radialSelf, key)
    local playerNum = radialSelf ~= nil and radialSelf.playerNum or 0
    local menu = radialMenuFor(playerNum)
    if menu == nil or menu.clear == nil or menu.addSlice == nil then return nil end
    if not featureEnabled() then
        -- A wheel opened before Knox was disabled may still invoke an old
        -- callback. Restore the vanilla root instead of exposing Knox actions.
        if previousFill ~= nil then
            pcall(function() previousFill(radialSelf, nil) end)
            showMenu(playerNum)
        end
        return nil
    end
    local ok = pcall(function()
        menu:clear()
        if key == "knox_party" then
            for _, entry in ipairs(PARTY_ORDERS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderParty,
                    radialSelf, entry.kind)
            end
            addBack(menu, radialSelf, "knox")
        elseif key == "knox_party_more" then
            for _, entry in ipairs(PARTY_MORE) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderPartyMore,
                    radialSelf, entry.kind == "movements" and "move"
                        or entry.kind == "tactics" and "tactics"
                        or entry.kind == "permissions" and "perms" or entry.kind)
            end
            addBack(menu, radialSelf, "knox_party")
        elseif key == "pm:move" then
            for _, entry in ipairs(PARTY_MOVEMENTS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderPartyMove,
                    radialSelf, entry.kind)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:tactics" then
            for _, entry in ipairs(PARTY_TACTICS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderPartyStance,
                    radialSelf, entry.kind)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:perms" then
            for _, entry in ipairs(PARTY_PERMISSIONS) do
                local callback, arg = Radial.orderPartyPerm, entry.kind
                if entry.kind == "weapon_melee" or entry.kind == "weapon_ranged"
                    or entry.kind == "weapon_auto" then
                    callback = Radial.orderPartyWeapon
                    arg = entry.kind == "weapon_melee" and "melee"
                        or entry.kind == "weapon_ranged" and "ranged" or "auto"
                end
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), callback,
                    radialSelf, arg)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:vehicles" then
            for _, entry in ipairs(PARTY_VEHICLES) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderParty,
                    radialSelf, entry.kind)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:pickup" then
            for _, entry in ipairs(PARTY_PICKUP) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderParty,
                    radialSelf, entry.kind)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:formation" then
            for _, entry in ipairs(FOLLOWER_FORMATION) do
                menu:addSlice(entry.label, iconFor("group"), Radial.orderPartyFormation,
                    radialSelf, entry.formation, entry.spacing)
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "pm:equipment" then
            for _, entry in ipairs(PARTY_EQUIPMENT) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderPartyEquipment,
                    radialSelf, entry.kind == "enable_auto_equipment")
            end
            addBack(menu, radialSelf, "knox_party_more")
        elseif key == "knox_followers" or key == "knox_residents"
            or key == "knox_nearby" then
            local list = key == "knox_followers" and followerMembers(playerNum)
                or key == "knox_residents" and residentMembers(playerNum)
                or nearbyMembers(playerNum)
            local prefix = key == "knox_followers" and "f:"
                or key == "knox_residents" and "r:" or "n:"
            for _, member in ipairs(list) do
                menu:addSlice(member.name, survivorIcon(member.id, playerNum),
                    Radial.fillKnox, radialSelf, prefix .. tostring(member.id))
            end
            addBack(menu, radialSelf, "knox")
        elseif type(key) == "string" and string.sub(key, 1, 2) == "f:" then
            -- Follower level: revalidate membership at fill time so a stale
            -- wheel cannot command someone who left, died, or unloaded.
            local id = string.sub(key, 3)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers")
                return
            end
            for _, entry in ipairs(SOLO_ORDERS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderOne,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "knox_followers")
        elseif type(key) == "string" and string.sub(key, 3, 3) == ":"
            and string.sub(key, 1, 3) == "fm:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, entry in ipairs(FOLLOWER_MOVEMENTS) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderOne,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "f:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 4) == "fm2:" then
            local id = string.sub(key, 5)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, entry in ipairs(FOLLOWER_MOVEMENTS_MORE) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderOne,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "fm:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "fv:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            local player = playerFor(playerNum)
            local character = liveCharacter(id)
            if character ~= nil and character.getVehicle ~= nil and character:getVehicle() ~= nil then
                menu:addSlice("Exit Vehicle", iconFor("back"), Radial.orderOne,
                    radialSelf, id, "exit_vehicle")
            elseif player ~= nil and player.getVehicle ~= nil and player:getVehicle() ~= nil then
                menu:addSlice("Take Passenger Seat", iconFor("group"), Radial.orderOne,
                    radialSelf, id, "enter_vehicle")
                menu:addSlice("Take Driver Seat & Drive", iconFor("moveout"), Radial.orderOne,
                    radialSelf, id, "drive_ahead")
            else
                menu:addSlice("Drive Nearest Vehicle", iconFor("moveout"), Radial.orderOne,
                    radialSelf, id, "drive_nearest_vehicle")
            end
            addBack(menu, radialSelf, "f:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 6) == "fmore:" then
            local id = string.sub(key, 7)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, entry in ipairs(FOLLOWER_MORE) do
                local target = entry.kind == "formation" and "ff:" .. id
                    or entry.kind == "gear" and "fg:" .. id or nil
                if target ~= nil then
                    menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.fillKnox,
                        radialSelf, target)
                else
                    menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderOne,
                        radialSelf, id, entry.kind)
                end
            end
            addBack(menu, radialSelf, "f:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "ff:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, entry in ipairs(FOLLOWER_FORMATION) do
                menu:addSlice(entry.label, iconFor("group"), Radial.orderFormationF,
                    radialSelf, id, entry.formation, entry.spacing)
            end
            addBack(menu, radialSelf, "fmore:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "fg:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, entry in ipairs(FOLLOWER_GEAR) do
                menu:addSlice(entry.label, iconFor(entry.fallbackIcon), Radial.orderGearF,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "fmore:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 2) == "r:" then
            local id = string.sub(key, 3)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents")
                return
            end
            for _, entry in ipairs(RESIDENT_ORDERS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderResident,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "knox_residents")
        elseif type(key) == "string" and string.sub(key, 1, 3) == "rw:" then
            local id = string.sub(key, 4)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents"); return
            end
            for _, preference in ipairs(RESIDENT_WORK) do
                menu:addSlice(KnoxOrderCatalog.label(preference, preference), iconFor("group"),
                    Radial.orderResidentPreference, radialSelf, id, preference)
            end
            menu:addSlice("More Work", iconFor("moveout"), Radial.fillKnox,
                radialSelf, "rw2:" .. id)
            addBack(menu, radialSelf, "r:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 4) == "rw2:" then
            local id = string.sub(key, 5)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents"); return
            end
            for _, preference in ipairs(RESIDENT_WORK_MORE) do
                menu:addSlice(KnoxOrderCatalog.label(preference, preference), iconFor("group"),
                    Radial.orderResidentPreference, radialSelf, id, preference)
            end
            addBack(menu, radialSelf, "rw:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "rp:" then
            local id = string.sub(key, 4)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents"); return
            end
            for _, entry in ipairs({
                { "Allow Loot Runs", "loot_runs_on" }, { "Stay Home", "loot_runs_off" },
                { "Upgrade Gear", "equipment_on" }, { "Keep Current Gear", "equipment_off" },
            }) do
                menu:addSlice(entry[1], iconFor("signalok"), Radial.orderResidentPolicy,
                    radialSelf, id, entry[2])
            end
            addBack(menu, radialSelf, "r:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "sf:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers")
                return
            end
            for _, kind in ipairs(SURVIVAL_FOLLOWER) do
                menu:addSlice(orderLabel(kind, kind),
                    iconFor("moveout"), Radial.orderSurvivalF,
                    radialSelf, id, kind)
            end
            menu:addSlice("More Supplies", iconFor("group"), Radial.orderSurvivalF,
                radialSelf, id, "more_supplies")
            addBack(menu, radialSelf, "f:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 4) == "sf2:" then
            local id = string.sub(key, 5)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers"); return
            end
            for _, kind in ipairs(SURVIVAL_FOLLOWER_MORE) do
                menu:addSlice(orderLabel(kind, kind), iconFor("moveout"),
                    Radial.orderSurvivalF, radialSelf, id, kind)
            end
            addBack(menu, radialSelf, "sf:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "ft:" then
            local id = string.sub(key, 4)
            if not memberIn(followerMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_followers")
                return
            end
            for _, entry in ipairs(FOLLOWER_TACTICS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderTacticsF,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "f:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 3) == "sr:" then
            local id = string.sub(key, 4)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents")
                return
            end
            for _, kind in ipairs(SURVIVAL_RESIDENT) do
                menu:addSlice(orderLabel(kind, kind),
                    iconFor("moveout"), Radial.orderSurvivalR,
                    radialSelf, id, kind)
            end
            menu:addSlice("More Supplies", iconFor("group"), Radial.orderSurvivalR,
                radialSelf, id, "more_supplies")
            addBack(menu, radialSelf, "r:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 4) == "sr2:" then
            local id = string.sub(key, 5)
            if not memberIn(residentMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_residents"); return
            end
            for _, kind in ipairs(SURVIVAL_RESIDENT_MORE) do
                menu:addSlice(orderLabel(kind, kind), iconFor("moveout"),
                    Radial.orderSurvivalR, radialSelf, id, kind)
            end
            addBack(menu, radialSelf, "sr:" .. id)
        elseif type(key) == "string" and string.sub(key, 1, 2) == "n:" then
            local id = string.sub(key, 3)
            if not memberIn(nearbyMembers(playerNum), id) then
                Radial.fillKnox(radialSelf, "knox_nearby")
                return
            end
            for _, entry in ipairs(NEARBY_ORDERS) do
                menu:addSlice(orderLabel(entry.kind, entry.label),
                    iconFor(entry.fallbackIcon), Radial.orderNearby,
                    radialSelf, id, entry.kind)
            end
            addBack(menu, radialSelf, "knox_nearby")
        else
            local followers = followerMembers(playerNum)
            -- Party-wide orders target the durable player roster and remain
            -- useful while members are stored/offscreen. Keep the individual
            -- follower page proximity-gated because those actions target one
            -- live body.
            local _, ownedCompanions = companionIdSet(playerFor(playerNum))
            local partyOk = #ownedCompanions > 0
            if partyOk then
                menu:addSlice("Party Orders", iconFor("group"), Radial.fillKnox,
                    radialSelf, "knox_party")
            end
            if #followers > 0 then
                menu:addSlice("Followers", iconFor("followme"), Radial.fillKnox,
                    radialSelf, "knox_followers")
            end
            if #residentMembers(playerNum) > 0 then
                menu:addSlice("Residents", iconFor("comehere"), Radial.fillKnox,
                    radialSelf, "knox_residents")
            end
            if #nearbyMembers(playerNum) > 0 then
                menu:addSlice("Nearby Survivors", iconFor("shrug"), Radial.fillKnox,
                    radialSelf, "knox_nearby")
            end
            if previousFill ~= nil then
                menu:addSlice(backLabel(), iconFor("back"), previousFill,
                    radialSelf)
            end
        end
    end)
    if ok then
        showMenu(playerNum)
    elseif previousFill ~= nil then
        -- Never leave a blank wheel: restore the vanilla base level.
        pcall(function() previousFill(radialSelf) end)
        showMenu(playerNum)
    end
    return nil
end

function Radial.install()
    if installed then return true end
    local emoteMenu = rawget(_G, "ISEmoteRadialMenu")
    if type(emoteMenu) ~= "table" or type(emoteMenu.fillMenu) ~= "function" then
        return dormant("emote_radial_unavailable")
    end
    if emoteMenu.__knoxRadialWrapped == true then
        installed = true
        return true
    end
    local previous = emoteMenu.fillMenu
    local ok = pcall(function()
        emoteMenu.fillMenu = function(self, submenu)
            -- Original (and any foreign prior wrapper) first: vanilla menu
            -- always builds even if everything below fails.
            local okFill = pcall(function() previous(self, submenu) end)
            pcall(function()
                -- Base level only. Submenus (vanilla or Knox) render exactly
                -- what their own fill put there.
                if submenu == nil and okFill and self ~= nil
                    and featureEnabled() then
                    local player = playerFor(self.playerNum)
                    local _, ownedCompanions = companionIdSet(player)
                    local show = #ownedCompanions > 0
                        or #residentMembers(self.playerNum) > 0
                        or #nearbyMembers(self.playerNum) > 0
                    if show then
                        local menu = radialMenuFor(self.playerNum)
                        if menu ~= nil and menu.addSlice ~= nil then
                            menu:addSlice("Knox Orders", knoxButtonIcon(),
                                Radial.fillKnox, self, "knox")
                        end
                    end
                end
            end)
            -- fillMenu returns nothing in vanilla; preserve that contract.
            return nil
        end
        emoteMenu.__knoxRadialWrapped = true
        previousFill = previous
    end)
    if not ok then return dormant("wrap_failed") end
    installed = true
    print("[KnoxSurvivors][Radial] installed hook=ISEmoteRadialMenu.fillMenu hierarchy=knox")
    return true
end

function Radial.isInstalled()
    return installed == true
end

local function onGameStart()
    pcall(function() Radial.install() end)
end

if Events ~= nil and Events.OnGameStart ~= nil then
    pcall(function() Events.OnGameStart.Add(onGameStart) end)
end

return Radial
