require "ISUI/ISContextMenu"
require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_ToolCupboard"
require "KS_BaseTerritorySelector"
require "KS_BaseZoneSelector"
require "KS_SurvivorAutonomy"
require "KS_BaseBarricades"
require "KS_BaseTaskBoard"
require "KS_BaseStorageFilterUI"
require "KS_BaseCompound"

local BaseContextMenu = rawget(_G, "KnoxBaseContextMenu") or {}
_G.KnoxBaseContextMenu = BaseContextMenu

BaseContextMenu.BASE_INTENTS = {
    { key = "security", label = "Security" },
    { key = "stockpile", label = "Stockpile" },
    { key = "shelter", label = "Shelter" },
    { key = "health", label = "Health" },
    { key = "growth", label = "Growth" },
    { key = "trade", label = "Trade" },
    { key = "vengeance", label = "Vengeance" },
}
local BASE_INTENTS = BaseContextMenu.BASE_INTENTS
BaseContextMenu.BASE_INTENT_LABELS = {}
local BASE_INTENT_LABELS = BaseContextMenu.BASE_INTENT_LABELS
for _, entry in ipairs(BASE_INTENTS) do BASE_INTENT_LABELS[entry.key] = entry.label end

-- Base kind: what the place is for. Identity, unlike the weekly intent, and it
-- only ever changes the owner's own record.
BaseContextMenu.BASE_KINDS = {
    { key = "main", label = "Main Base" },
    { key = "outpost", label = "Outpost" },
    { key = "storage", label = "Storage Base" },
    { key = "checkpoint", label = "Checkpoint" },
}
local BASE_KINDS = BaseContextMenu.BASE_KINDS
BaseContextMenu.BASE_KIND_LABELS = {}
local BASE_KIND_LABELS = BaseContextMenu.BASE_KIND_LABELS
for _, entry in ipairs(BASE_KINDS) do BASE_KIND_LABELS[entry.key] = entry.label end

local LAYOUT_REASONS = {
    base_missing = "No base record to lay out.",
    not_player_base = "Only a player-owned base can take a layout proposal.",
    no_building = "This square is not inside a readable building.",
    not_home_building = "This building is not the home of this base.",
    no_rooms = "This floor of this building reports no rooms; try another floor or a different building.",
    no_new_rooms = "No new work areas or storage assignments were suggested; existing choices are kept.",
    no_entries = "No proposed work areas or storage assignments to apply.",
    invalid_entry = "A proposed area was invalid and was skipped.",
    invalid_storage_entry = "A proposed storage assignment was invalid and was skipped.",
    existing = "That work area already exists.",
    existing_storage = "That storage category is already assigned.",
    overlaps_existing_work_area = "That area overlaps an existing work area.",
    unknown_zone_type = "That kind of work area is not supported.",
    unknown_storage_category = "That storage category is not supported.",
    not_a_container = "That object has no storage container.",
    outside_base = "That container is outside the base now.",
    use_item_storage = "That container holds water or corpses and cannot be assigned.",
    main_supplies_retired = "Main Supplies is retired; use a typed storage category.",
}

local function layoutReasonText(reason)
    return LAYOUT_REASONS[tostring(reason or "")]
        or "No layout was suggested for this building."
end

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function firstSquare(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if square ~= nil then
            return square
        end
    end
    return nil
end

local function containerObjects(worldobjects, bases)
    local found = {}
    local seen = {}
    if bases ~= nil and bases.id ~= nil then bases = { bases } end
    for _, object in ipairs(worldobjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        local count = object ~= nil and object.getContainerCount ~= nil
            and object:getContainerCount()
            or 0
        -- worldobjects often contains the same IsoObject twice (multi-square
        -- crates, object + inventory proxy). Dedupe so crates get one menu.
        local ownerBase = nil
        if square ~= nil and count > 0 then
            for _, base in ipairs(bases or {}) do
                if base ~= nil and KnoxBaseManager.containsSquare(base, square) then
                    ownerBase = base
                    break
                end
            end
        end
        if ownerBase ~= nil and seen[object] == nil then
            seen[object] = true
            found[#found + 1] = { object = object, base = ownerBase }
        end
    end
    return found
end

function BaseContextMenu.establish(player, square)
    local base, result = KnoxBaseManager.establishPlayerBase(player, square)
    if base ~= nil and result == "existing" then
        KnoxActivityFeed.event("This building is already your home base.")
    elseif base ~= nil and result == "move_confirmation_required" then
        KnoxActivityFeed.event("You already have a home base. Use Move Home Base Here to confirm a move.")
    elseif base ~= nil then
        KnoxActivityFeed.event("Home base established.")
    else
        KnoxActivityFeed.event("Could not establish a base here: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.establishOutpost(player, square)
    local base, result = KnoxBaseManager.establishOutpost(player, square)
    if base ~= nil and result ~= "existing" then
        KnoxActivityFeed.event("Outpost established: " .. tostring(base.name or base.id) .. ".")
    elseif base ~= nil then
        KnoxActivityFeed.event("That building is already one of your bases.")
    else
        KnoxActivityFeed.event("Could not establish an outpost here: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.confirmMove(_, button, player, square)
    if button == nil or button.internal ~= "YES" then
        KnoxActivityFeed.event("Home base move cancelled.")
        return
    end
    local base, result = KnoxBaseManager.movePlayerBase(player, square)
    if base ~= nil then
        KnoxActivityFeed.event("Home base moved. Items at the previous location were left untouched.")
    else
        KnoxActivityFeed.event("Could not move the base here: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.requestMove(player, square)
    local prompt = "Move your home base here? Existing items will stay at the old location, while old work areas, storage assignments, and queued jobs will be cleared."
    local modal = ISModalDialog:new(0, 0, 430, 170, prompt, true,
        BaseContextMenu, BaseContextMenu.confirmMove, player:getPlayerNum(), player, square)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
end

function BaseContextMenu.setStorage(baseId, object, containerIndex, category)
    local policy, result = KnoxBaseManager.setStoragePolicy(
        baseId,
        object,
        category,
        containerIndex
    )
    if policy ~= nil then
        KnoxActivityFeed.event("Assigned " .. KnoxBaseStorage.label(policy) .. ". Residents will use this container automatically.")
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
    else
        KnoxActivityFeed.event("Could not set storage: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.toggleStorageFilter(baseId, object, containerIndex, category)
    local base = KnoxBaseManager.get(baseId)
    if base == nil or object == nil
        or not KnoxBaseManager.containsSquare(base, object:getSquare()) then
        KnoxActivityFeed.event("Could not update storage filters: container is outside this base.")
        return
    end
    local reference = base ~= nil
        and KnoxBaseManager.containerReference(object, containerIndex, baseId) or nil
    if reference == nil then
        KnoxActivityFeed.event("Could not update storage filters: container is unavailable.")
        return
    end
    local current = base.storage ~= nil and base.storage[reference.key] or nil
    local filters = KnoxBaseStorage.filtersForPolicy(current)
    if category == "general" then
        filters = filters.general and {} or { general = true }
    else
        filters.general = nil
        filters[category] = not filters[category] or nil
    end
    if not hasEntries(filters) then
        if current ~= nil then
            BaseContextMenu.removeStorage(baseId, reference.key, object, containerIndex)
        else
            KnoxActivityFeed.event("Storage filters cleared.")
        end
        return
    end
    local policy, result = KnoxBaseManager.setStorageFilters(
        baseId, object, filters, containerIndex)
    if policy ~= nil then
        KnoxActivityFeed.event("Storage filters: " .. KnoxBaseStorage.label(policy) .. ".")
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
    else
        KnoxActivityFeed.event("Could not update storage filters: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.openStorageFilters(baseId, object, containerIndex, playerNum)
    if KnoxBaseStorageFilterUI == nil then
        KnoxActivityFeed.event("Container filter window is unavailable.")
        return
    end
    KnoxBaseStorageFilterUI.open(baseId, object, containerIndex, playerNum)
end

function BaseContextMenu.setStoragePriority(baseId, key, priority)
    local ok, result = KnoxPersistence.setBaseStoragePriority(baseId, key, priority)
    if ok then
        KnoxActivityFeed.event("Storage priority set to "
            .. KnoxBaseStorage.priorityLabel({ priority = priority }) .. ".")
    else
        KnoxActivityFeed.event("Could not set priority: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.removeStorage(baseId, key, object, containerIndex)
    -- Resolve the exact assigned compartment before dropping its canonical
    -- policy. Native capacity/ModData cleanup is only committed if persistence
    -- accepts removal; a rejected removal must leave the live store unchanged.
    local base = KnoxBaseManager.get(baseId)
    local policy = base ~= nil and base.storage ~= nil and base.storage[key] or nil
    local resolved = nil
    if policy ~= nil and KnoxBaseStorage ~= nil and KnoxBaseStorage.resolvePolicy ~= nil then
        resolved = KnoxBaseStorage.resolvePolicy(policy, true)
    end
    local success, reason = KnoxPersistence.removeBaseStoragePolicy(baseId, key)
    local restoreResult = nil
    if success and policy ~= nil then
        local cleanupObject = resolved ~= nil and resolved.object or object
        local container = resolved ~= nil and resolved.container or nil
        if container == nil and object ~= nil and object.getContainerByIndex ~= nil then
            local ok, direct = pcall(function()
                return object:getContainerByIndex(tonumber(containerIndex) or 0)
            end)
            if ok then container = direct end
        end
        if KnoxToolCupboard ~= nil and KnoxToolCupboard.clearInfinite ~= nil
            and cleanupObject ~= nil and container ~= nil then
            local restored, restoreReason = KnoxToolCupboard.clearInfinite(
                cleanupObject, container, key, policy.containerIndex or containerIndex
            )
            if not restored or restoreReason == "original_capacity_unknown" then
                restoreResult = restoreReason
            end
        else
            restoreResult = "container_unavailable"
        end
        if container ~= nil and KnoxBaseStorage ~= nil
            and KnoxBaseStorage.clearContainerName ~= nil then
            KnoxBaseStorage.clearContainerName(policy, container)
        end
    end
    local message = success and (restoreResult == nil
        and "Storage assignment removed. Contents stay here."
        or "Storage assignment removed, but native capacity restoration could not be confirmed.")
        or ("Could not remove storage: " .. tostring(reason))
    KnoxActivityFeed.event(message)
    if success and KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
end

local function displayNameFor(id)
    local identity = nil
    pcall(function()
        if KnoxPersistence.getSurvivorIdentity ~= nil then
            identity = KnoxPersistence.getSurvivorIdentity(id)
        end
    end)
    if type(identity) == "table" then
        local name = tostring(identity.forename or "")
        if identity.surname ~= nil and tostring(identity.surname) ~= "" then
            name = name .. " " .. tostring(identity.surname)
        end
        if name ~= "" then return name end
    end
    return tostring(id)
end

local function bedReference(object)
    if object == nil or object.getSquare == nil then return nil end
    local square, objectIndex = nil, nil
    local okSquare = pcall(function() square = object:getSquare() end)
    local okIndex = pcall(function() objectIndex = object:getObjectIndex() end)
    if not okSquare or not okIndex or square == nil or objectIndex == nil then
        return nil
    end
    return {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = objectIndex,
    }
end

local function isBedObject(object)
    if object == nil or object.getProperties == nil then return false end
    local ok, properties = pcall(function() return object:getProperties() end)
    if not ok or properties == nil then return false end
    local okType, bedType = pcall(function() return properties:get("BedType") end)
    return okType and string.find(string.lower(tostring(bedType or "")),
        "bed", 1, true) ~= nil
end

local function bedCandidates(base, playerId)
    local found, seen = {}, {}
    local function add(id)
        if id == nil or seen[tostring(id)] then return end
        local alive = true
        pcall(function()
            if KnoxPersistence.isSurvivorAlive ~= nil then
                alive = KnoxPersistence.isSurvivorAlive(id) ~= false
            end
        end)
        if not alive then return end
        seen[tostring(id)] = true
        found[#found + 1] = { id = id, name = displayNameFor(id) }
    end
    if KnoxPersistence.getCompanionIds ~= nil then
        local ok, ids = pcall(function()
            return KnoxPersistence.getCompanionIds(playerId)
        end)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do add(id) end
        end
    end
    if base ~= nil and base.id ~= nil
        and KnoxPersistence.getBaseResidentIds ~= nil then
        local ok, ids = pcall(function()
            return KnoxPersistence.getBaseResidentIds(base.id)
        end)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do add(id) end
        end
    end
    table.sort(found, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.id) < tostring(b.id)
    end)
    return found
end

local function bedAssignee(bedRef, candidates)
    if bedRef == nil then return nil end
    for _, candidate in ipairs(candidates) do
        local policies = nil
        pcall(function()
            if KnoxPersistence.getSurvivorPolicies ~= nil then
                policies = KnoxPersistence.getSurvivorPolicies(candidate.id)
            end
        end)
        local assigned = type(policies) == "table" and policies.assignedBed or nil
        if type(assigned) == "table"
            and tonumber(assigned.x) == tonumber(bedRef.x)
            and tonumber(assigned.y) == tonumber(bedRef.y)
            and tonumber(assigned.z) == tonumber(bedRef.z)
            and tonumber(assigned.objectIndex) == tonumber(bedRef.objectIndex) then
            return candidate
        end
    end
    return nil
end

function BaseContextMenu.assignBed(target, object)
    local survivorId = type(target) == "table" and target.survivorId or nil
    local playerId = type(target) == "table" and target.playerId or nil
    local ref = bedReference(object)
    if survivorId == nil or ref == nil then
        KnoxActivityFeed.event("Could not assign bed: invalid bed.")
        return
    end
    local ok, reason = KnoxPersistence.setSurvivorBed(
        survivorId, playerId, ref, getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    KnoxActivityFeed.event(ok and "Bed assigned. They will use it when sleeping here."
        or ("Could not assign bed: " .. tostring(reason)))
end

function BaseContextMenu.unassignBed(target)
    local survivorId = type(target) == "table" and target.survivorId or nil
    local playerId = type(target) == "table" and target.playerId or nil
    if survivorId == nil then
        KnoxActivityFeed.event("Could not unassign bed.")
        return
    end
    local ok, reason = KnoxPersistence.clearSurvivorBed(
        survivorId, playerId, getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    KnoxActivityFeed.event(ok and "Bed assignment cleared."
        or ("Could not unassign bed: " .. tostring(reason)))
end

local function addBedMenu(parent, base, player, playerId, worldobjects)
    local bed = nil
    for _, object in ipairs(worldobjects or {}) do
        if isBedObject(object) then bed = object break end
    end
    if bed == nil then return end
    local candidates = bedCandidates(base, playerId)
    if #candidates == 0 then return end
    local ref = bedReference(bed)
    local current = bedAssignee(ref, candidates)
    local root = parent:addOption("Assign Bed", nil, nil)
    local menu = ISContextMenu:getNew(parent)
    parent:addSubMenu(root, menu)
    if current ~= nil then
        local status = menu:addOption("Assigned: " .. current.name, nil, nil)
        status.notAvailable = true
        menu:addOption("Unassign Bed",
            { survivorId = current.id, playerId = playerId },
            BaseContextMenu.unassignBed)
    end
    for _, candidate in ipairs(candidates) do
        if current == nil or tostring(candidate.id) ~= tostring(current.id) then
            menu:addOption("Assign to " .. candidate.name,
                { survivorId = candidate.id, playerId = playerId },
                BaseContextMenu.assignBed, bed)
        end
    end
end

function BaseContextMenu.selectTerritory(player, baseId)
    KnoxBaseTerritorySelector.start(player, baseId)
end

function BaseContextMenu.selectZone(player, baseId, zoneType, label)
    KnoxBaseZoneSelector.start(player, baseId, zoneType, label)
end

function BaseContextMenu.removeZone(_, baseId, zoneId)
    local removed, result = KnoxPersistence.removeBaseZone(baseId, zoneId)
    if removed then
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
        KnoxActivityFeed.event("Work area removed.")
    else
        KnoxActivityFeed.event("Could not remove work area: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.applyLayout(player, base, entries)
    if player == nil or base == nil then
        KnoxActivityFeed.event("Could not apply layout: missing base or player.")
        return
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local result, reason = KnoxBaseManager.applyLayout(base.id, entries, playerId, player)
    if result == nil then
        KnoxActivityFeed.event("Could not apply layout: " .. layoutReasonText(reason))
        return
    end
    local changes = {}
    if result.added > 0 then
        changes[#changes + 1] = tostring(result.added) .. " work area"
            .. (result.added == 1 and "" or "s") .. " added"
    end
    if result.assigned > 0 then
        changes[#changes + 1] = tostring(result.assigned) .. " storage assignment"
            .. (result.assigned == 1 and "" or "s") .. " added"
    end
    local text = #changes > 0
        and ("Layout applied: " .. table.concat(changes, ", ") .. ".")
        or "Layout applied: nothing changed."
    local kept = #(result.skipped or {}) + #(result.storageSkipped or {})
    if kept > 0 then
        text = text .. " " .. tostring(kept) .. " kept or refused."
    end
    KnoxActivityFeed.event(text)
    if (result.added > 0 or result.assigned > 0) and KnoxBaseHighlights ~= nil
        and KnoxBaseHighlights.refresh ~= nil then
        pcall(function() KnoxBaseHighlights.refresh(player:getPlayerNum()) end)
    end
end

function BaseContextMenu.dismissLayout(_, base)
    KnoxActivityFeed.event("Layout proposal dismissed; no work areas or storage assignments changed.")
end

function BaseContextMenu.openSetup(_, playerNum)
    if KnoxSurvivorNotebook and KnoxSurvivorNotebook.show then
        KnoxSurvivorNotebook.show(playerNum)
    end
end

local SCOUT_FAILURES = {
    dispatch_unavailable = "no loaded base or destination was available",
    need_loaded_base_resident = "no resident of this base is loaded nearby",
    invalid_mission = "that order is not a supported mission",
    checkpoint_base = "a checkpoint holds its road instead of sending people away",
    need_visible_destination = "that place is out of sight for a supply run",
    need_settled_resident = "a free resident who can be seen is needed for a supply run",
    live_arrival_failed = "the mission could not start in the loaded world",
    team_create_failed = "the mission record could not be created",
    missing_active_member = "that resident is no longer loaded nearby",
}

local function scoutFailureText(result)
    local message = SCOUT_FAILURES[tostring(result)]
    if message ~= nil then return message end
    return (tostring(result or "unknown reason"):gsub("_", " "))
end

function BaseContextMenu.dispatchScout(player, base, square, partySize, missionType,
    radius, label, members)
    local success, result = KnoxSurvivorAutonomy.dispatchBaseScout(
        player, base.id, square, partySize, missionType, radius, label, members
    )
    if not success then
        KnoxActivityFeed.event("Could not issue that order: "
            .. scoutFailureText(result) .. ".")
        return
    end
    -- Report the persisted team, not an optimistic departure: the dispatch
    -- can still have rolled back a partially removed body. Names come from the
    -- durable identity so the message matches the Mission tab later.
    local team = KnoxPersistence.getAwayTeam(result)
    local executor = rawget(_G, "KnoxAwayTeamExecutor")
    local who = team ~= nil and executor ~= nil and executor.memberLabel ~= nil
        and executor.memberLabel(team) or "The scout"
    local place = team ~= nil and team.destination ~= nil
        and tostring(team.destination.label or "the destination") or "the destination"
    local going = type(team) == "table" and type(team.memberIds) == "table"
        and #team.memberIds > 1 and "are" or "is"
    local label = team ~= nil and team.missionType ~= "scout" and executor ~= nil
        and executor.missionLabel ~= nil and executor.missionLabel(team) or "Scout"
    KnoxActivityFeed.event(tostring(label) .. " departed: " .. tostring(who)
        .. " " .. going .. " heading to " .. place .. ".")
end

function BaseContextMenu.toggleKeepOpen(player, object)
    local barricades = rawget(_G, "KnoxBaseBarricades")
    if player == nil or object == nil or barricades == nil
        or barricades.setKeepOpen == nil or barricades.isKeepOpen == nil then
        KnoxActivityFeed.event("Could not mark that opening.")
        return
    end
    local keep = barricades.isKeepOpen(object)
    if not barricades.setKeepOpen(object, not keep) then
        KnoxActivityFeed.event("Could not mark that opening.")
        return
    end
    KnoxActivityFeed.event(not keep and "This opening will stay clear."
        or "This opening can be boarded again.")
end

-- A building beside the base is part of that base, not a new one. The claim
-- goes through KnoxBaseCompound so the distance and overlap rules stay in one
-- place, and the refusal is spoken on the feed instead of hidden.
function BaseContextMenu.renameRoomHere(player, name)
    local roomApi = rawget(_G, "KnoxBaseCompound")
    local square = player ~= nil and player:getCurrentSquare() or nil
    if roomApi == nil or square == nil then return end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxPersistence.getBaseForOwner("player", playerId)
    if base == nil then
        KnoxActivityFeed.event("Establish a base before naming its rooms.")
        return
    end
    local ok, reason = roomApi.renameRoomAt(base,
        square:getX(), square:getY(), square:getZ(), name)
    if ok then
        KnoxActivityFeed.event("Room renamed to " .. tostring(name) .. ".")
    else
        KnoxActivityFeed.event("Could not rename this room: " .. tostring(reason) .. ".")
    end
end

function BaseContextMenu.openDepotFilters(player, zone)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxPersistence.getBaseForOwner ~= nil
        and KnoxPersistence.getBaseForOwner("player", playerId) or nil
    if player == nil or base == nil or zone == nil then
        KnoxActivityFeed.event("Could not open depot filters: that area is not yours.")
        return
    end
    KnoxBaseStorageFilterUI.openZone(base.id, zone.id, player:getPlayerNum())
end

function BaseContextMenu.claimBuilding(player, square)
    local compound = rawget(_G, "KnoxBaseCompound")
    if player == nil or square == nil or compound == nil then return end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxPersistence.getBaseForOwner("player", playerId)
    if base == nil then
        KnoxActivityFeed.event("Establish a base before adding a second building to it.")
        return
    end
    local building = square.getBuilding ~= nil and square:getBuilding() or nil
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local establishment, reason, gap = compound.claim(base, building, square, hours)
    if establishment == nil then
        KnoxActivityFeed.event("Could not add that building: "
            .. compound.refusalText(reason, gap) .. ".")
        return
    end
    local roomCount = #(establishment.rooms or {})
    KnoxActivityFeed.event(tostring(base.name or "Base") .. " now includes "
        .. tostring(establishment.name) .. " (" .. tostring(roomCount)
        .. (roomCount == 1 and " room" or " rooms") .. ").")
end

function BaseContextMenu.setBaseIntent(player, base, intent)
    if player == nil or base == nil or KnoxPersistence.setBaseIntent == nil then
        KnoxActivityFeed.event("Could not set base intent.")
        return
    end
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local ok, reason = KnoxPersistence.setBaseIntent(
        base.id, KnoxPersistence.ensurePlayerId(player), intent, hours)
    if not ok then
        KnoxActivityFeed.event("Could not set base intent: " .. tostring(reason) .. ".")
        return
    end
    KnoxActivityFeed.event("Base intent: "
        .. tostring(BASE_INTENT_LABELS[intent] or intent) .. ".")
end

-- Refusals are named because each one is a different fact: a second base
-- cannot become the home, and the home cannot stop being the home.
local BASE_KIND_REFUSALS = {
    main_is_first_base = "Your first base is the main base; a later one cannot take that place.",
    main_base_fixed = "The main base stays the main base. Establish another base for an outpost, storehouse or checkpoint.",
    unknown_kind = "That is not a kind of base.",
    not_your_base = "That is not your base.",
    missing_base = "That base no longer exists.",
}

function BaseContextMenu.setBaseKind(player, base, kind)
    if player == nil or base == nil or KnoxPersistence.setBaseKind == nil then
        KnoxActivityFeed.event("Could not set the base kind.")
        return
    end
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local ok, reason = KnoxPersistence.setBaseKind(
        base.id, KnoxPersistence.ensurePlayerId(player), kind, hours)
    if not ok then
        KnoxActivityFeed.event(BASE_KIND_REFUSALS[tostring(reason)]
            or ("Could not set the base kind: " .. tostring(reason) .. "."))
        return
    end
    KnoxActivityFeed.event("Base kind: "
        .. tostring(BASE_KIND_LABELS[kind] or kind) .. ".")
end

-- Direct base orders for specific windows/build sites. Queues the concrete
-- task (if needed) and assigns it to the best available resident. If nobody
-- can take it right now the queued task remains for automatic pickup.
local function residentsForTask(base, taskType)
    if KnoxPersistence.getBaseResidentIds == nil then return {} end
    local candidates = KnoxPersistence.getBaseResidentIds(base.id) or {}
    local preferred = {}
    local fallback = {}
    for _, survivorId in ipairs(candidates) do
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(survivorId) or {}
        local pref = tostring(duty.jobPreference or "auto")
        if pref == "auto" or KnoxOrderCatalog.preferenceMatchesTask(pref, taskType) then
            preferred[#preferred + 1] = survivorId
        else
            fallback[#fallback + 1] = survivorId
        end
    end
    for _, survivorId in ipairs(fallback) do preferred[#preferred + 1] = survivorId end
    return preferred
end

local function assignTaskToBestResident(player, base, task)
    if task == nil then return nil end
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.assignBaseTask == nil then return nil end
    local playerId = service.getPlayerId(player)
    for _, survivorId in ipairs(residentsForTask(base, task.type)) do
        local eligible = KnoxBaseTaskBoard.canClaimSpecific(base.id, task.id, survivorId, playerId)
        -- A queued order is not permission to command an unseen resident.
        -- Read-only admission avoids repeated failed-order speech/feed spam.
        if eligible and service.orderContact(player, survivorId) then
            local assigned = service.assignBaseTask(player, survivorId, base.id, task.id)
            if assigned ~= nil then return assigned end
        end
    end
    return nil
end

-- BARRICADE REFUSAL COPY (pure)
-- The finder answers with a reason code. Every code it can return gets its own
-- sentence, because a player told "Nothing here needs barricading" after the
-- building could not even be read is being told the opposite of what happened.
-- Only `no_unbarricaded_window` and an unknown code fall back to that sentence.
local BARRICADE_REFUSAL_COPY = {
    only_usable_exit = "That would seal the only way out.",
    no_way_out = "That room has no usable exit of its own.",
    keep_open = "Every usable opening there is marked to stay clear.",
    barricade_room_busy = "Barricade work is already queued for that room.",
    entrance_unverified = "I can't verify a safe exit there.",
    room_audit_too_large = "That room has too many openings to audit safely.",
    missing_building = "I can't tell which building this is.",
    building_unavailable = "I can't read this building.",
    base_or_cell_unavailable = "I can't read this base's surroundings.",
    target_unloaded = "That window is not loaded any more.",
    target_no_longer_valid = "That window no longer needs boarding.",
}
local function barricadeRefusalText(reason)
    local text = reason ~= nil and BARRICADE_REFUSAL_COPY[tostring(reason)] or nil
    return text or "Nothing here needs barricading."
end
BaseContextMenu.barricadeRefusalText = barricadeRefusalText
-- END BARRICADE REFUSAL COPY

function BaseContextMenu.orderBarricadeHere(player, base, square)
    if player == nil or base == nil or square == nil then
        KnoxActivityFeed.event("Could not order barricade: missing target.")
        return
    end
    local barricades = rawget(_G, "KnoxBaseBarricades")
    local board = rawget(_G, "KnoxBaseTaskBoard")
    if barricades == nil or board == nil then
        KnoxActivityFeed.event("Could not order barricade: unavailable.")
        return
    end
    -- Board the windows of the clicked building, skipping doors so residents
    -- can still use them. Falls back to the single clicked square outside.
    local targets, reason = {}, nil
    if barricades.findTargetsInBuilding ~= nil then
        targets, reason = barricades.findTargetsInBuilding(base, square, player, 24)
        targets = targets or {}
    end
    if #targets == 0 then
        local tx, ty, tz = square:getX(), square:getY(), square:getZ()
        local single, singleReason = nil, nil
        if barricades.findTarget ~= nil then
            single, singleReason = barricades.findTarget(base, player,
                function(candidate)
                    return tonumber(candidate.x) == tx and tonumber(candidate.y) == ty
                        and tonumber(candidate.z) == tz
                end)
        end
        reason = reason or singleReason
        if single ~= nil then targets = { single } end
    end
    if #targets == 0 then
        KnoxActivityFeed.event(barricadeRefusalText(reason))
        return
    end
    local hammer = barricades.findHammer ~= nil and barricades.findHammer(nil, base) or nil
    local hammerType = hammer ~= nil and hammer.getFullType ~= nil
        and hammer:getFullType() or "Base.Hammer"
    local queued, assigned = 0, 0
    for _, target in ipairs(targets) do
        -- Reuse existing queued task for the same window when present.
        local task = nil
        for _, existing in pairs(base.tasks or {}) do
            if existing ~= nil and existing.target ~= nil
                and tostring(existing.target.id) == tostring(target.id)
                and (existing.state == "queued" or existing.state == "claimed") then
                task = existing
                break
            end
        end
        if task == nil then
            task = board.queue(base.id, "barricade", target, {
                items = { [hammerType] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 },
            }, 98)
        end
        if task ~= nil then
            -- Every window in this player order must remain eligible after the
            -- first assignment, even when autonomous base jobs are disabled.
            if task.state == "queued" then
                task.manualOrder = true
                task.auto = nil
            end
            queued = queued + 1
            if task.state == "queued" and assignTaskToBestResident(player, base, task) ~= nil then
                assigned = assigned + 1
            end
        end
    end
    if queued == 0 then
        KnoxActivityFeed.event("Could not queue barricade work.")
        return
    end
    KnoxActivityFeed.event(assigned > 0
        and (tostring(assigned) .. (assigned == 1 and " resident assigned; " or " residents assigned; ")
            .. tostring(queued) .. " window jobs ordered.")
        or ("Barricade work queued (" .. tostring(queued) .. ") — residents will take it."))
end

function BaseContextMenu.burnCorpsesHere(player, base, square)
    -- Retired: the corpse drop area is the burn order point. Full piles
    -- auto-queue burn work (KS_BaseJobs.ensureBurnTask) and the Notebook Work
    -- tab assigns it; a separate here-menu only duplicated that path.
    if player == nil or base == nil or square == nil then
        KnoxActivityFeed.event("Mark a Corpse Drop Area instead: full piles burn automatically.")
        return
    end
    KnoxActivityFeed.event("Mark a Corpse Drop Area instead: full piles burn automatically.")
end

local function addStorageMenu(parent, base, object, playerNum)
    local count = object:getContainerCount()
    -- Most world objects expose one usable container. Put the requested filter
    -- editor directly on the first right-click menu for that common case;
    -- only multi-compartment objects need an intermediate selector.
    if count == 1 then
        local container = object:getContainerByIndex(0)
        local kind = container ~= nil and string.lower(tostring(container:getType() or "")) or ""
        local unusable = kind == "corpse" or kind:find("water", 1, true) ~= nil
            or kind:find("rain", 1, true) ~= nil
        local option = parent:addOption("Set Filters…", base.id,
            BaseContextMenu.openStorageFilters, object, 0, playerNum)
        option.notAvailable = unusable
        return
    end
    local objectOption = parent:addOption(
        "Set Container Filters",
        object,
        nil
    )
    local objectMenu = ISContextMenu:getNew(parent)
    parent:addSubMenu(objectOption, objectMenu)
    for containerIndex = 0, count - 1 do
        local container = object:getContainerByIndex(containerIndex)
        if container ~= nil then
            local targetMenu = objectMenu
            if count > 1 then
                local containerOption = objectMenu:addOption(
                    tostring(container:getType() or "Container")
                        .. " " .. tostring(containerIndex + 1),
                    container,
                    nil
                )
                targetMenu = ISContextMenu:getNew(objectMenu)
                objectMenu:addSubMenu(containerOption, targetMenu)
            end
            local reference = KnoxBaseManager.containerReference(object, containerIndex, base.id)
            local policy = reference ~= nil and base.storage ~= nil and base.storage[reference.key] or nil
            if policy ~= nil then
                local status = targetMenu:addOption("Filters: " .. KnoxBaseStorage.label(policy), nil, nil)
                status.notAvailable = true
                targetMenu:addOption("Clear Container Filters", base.id,
                    BaseContextMenu.removeStorage, policy.key, object, containerIndex)
                -- RimWorld-style priority: Critical shelves fill first, Low
                -- last. Current level is checked; changing it re-ranks every
                -- future deposit without moving existing contents.
                local priorityOption = targetMenu:addOption("Priority: "
                    .. KnoxBaseStorage.priorityLabel(policy), nil, nil)
                local priorityMenu = ISContextMenu:getNew(targetMenu)
                targetMenu:addSubMenu(priorityOption, priorityMenu)
                for _, level in ipairs({ "critical", "preferred", "normal", "low" }) do
                    local current = (policy.priority == nil and level == "normal")
                        or policy.priority == level
                    local entry = priorityMenu:addOption(
                        KnoxBaseStorage.priorityLabel({ priority = level }),
                        base.id, BaseContextMenu.setStoragePriority, policy.key, level)
                    if current then priorityMenu:setOptionChecked(entry, true) end
                end
            end
            local kind = string.lower(tostring(container:getType() or ""))
            local unusable = kind == "corpse" or kind:find("water", 1, true) ~= nil
                or kind:find("rain", 1, true) ~= nil
            local filtersOption = targetMenu:addOption("Set Filters…", base.id,
                BaseContextMenu.openStorageFilters, object, containerIndex, playerNum)
            filtersOption.notAvailable = unusable
        end
    end
end

local function buildingId(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    return definition ~= nil and tostring(definition:getID()) or nil
end

-- Declared ahead of the menu body: the definition sits below it, and a local
-- declared there would leave this name resolving to a nil global at the call.
local addRadioMenu

function BaseContextMenu.onFill(playerNum, context, worldobjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    local player = getSpecificPlayer(playerNum)
    local square = firstSquare(worldobjects)
    if player == nil or square == nil then
        return
    end
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and compat.hasSelection ~= nil and compat.hasSelection(player) then
        -- Interface already supplies the aimed corner action. Its world-object
        -- harvester must not turn the fallback option into a second choice.
        if compat.usesNativeAdapter ~= nil and compat.usesNativeAdapter() then return end
        if test then return ISWorldObjectContextMenu.setTest() end
        context:addOption("Select corner here", player, compat.selectionAction, square)
        return
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxBaseManager.getForOwner("player", playerId)
    local layoutBase = base
    if KnoxPersistence.getBaseAtSquare ~= nil then
        local ok, found = pcall(function()
            return KnoxPersistence.getBaseAtSquare(
                square:getX(), square:getY(), square:getZ(), "player")
        end)
        if ok and found ~= nil then layoutBase = found end
    end
    local ownedBases = KnoxPersistence.getBasesForOwner ~= nil
        and KnoxPersistence.getBasesForOwner("player", playerId) or (base ~= nil and { base } or {})
    local containers = #ownedBases > 0 and containerObjects(worldobjects, ownedBases) or {}
    local clickedBuildingId = buildingId(square)
    local canEstablish = base == nil and clickedBuildingId ~= nil
    local canMove = base ~= nil and clickedBuildingId ~= nil
        and (base.home == nil or base.home.buildingId ~= clickedBuildingId)
    -- A resident may mark a work area on open ground, so a base menu must not
    -- depend on the clicked object being a container.
    if base == nil and not canEstablish and #containers == 0 then
        return
    end
    if test then
        if ISWorldObjectContextMenu.Test then
            return true
        end
        return ISWorldObjectContextMenu.setTest()
    end
    local rootOption = context:addOption("Knox Survivors", worldobjects, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)
    if canEstablish then
        menu:addOption("Establish Home Base", player, BaseContextMenu.establish, square)
    elseif canMove then
        menu:addOption("Move Home Base Here", player, BaseContextMenu.requestMove, square)
        -- A second (or third) home in another building: residents, jobs and
        -- storage stay per base, and send-home flows ask which base.
        -- Not offered inside your own territory (it would overlap).
        local insideOwn = false
        if KnoxPersistence.getBaseAtSquare ~= nil then
            local ok, found = pcall(function()
                return KnoxPersistence.getBaseAtSquare(
                    square:getX(), square:getY(), square:getZ(), "player")
            end)
            insideOwn = ok and found ~= nil and found.ownerId == playerId
        end
        if not insideOwn then
            menu:addOption("Establish Outpost Here", player, BaseContextMenu.establishOutpost, square)
            -- Closer than a walk, same base: the option is offered only when the
            -- compound rules accept this building, and says why when they do not.
            local compound = rawget(_G, "KnoxBaseCompound")
            local owned = playerId ~= nil and KnoxPersistence.getBaseForOwner ~= nil
                and KnoxPersistence.getBaseForOwner("player", playerId) or nil
            local candidate = compound ~= nil and compound.candidateFor(square) or nil
            if compound ~= nil and owned ~= nil and candidate ~= nil then
                local refusal, gap = compound.claimRefusal(compound.ensure(owned), candidate)
                if refusal == nil then
                    menu:addOption("Add This Building to " .. tostring(owned.name or "Base"),
                        player, BaseContextMenu.claimBuilding, square)
                elseif refusal ~= "already_in_base" then
                    local line = menu:addOption(compound.refusalText(refusal, gap), nil, nil)
                    line.notAvailable = true
                end
            end
        end
    end
    if base ~= nil then
        menu:addOption("Open Base Management", BaseContextMenu, BaseContextMenu.openSetup, playerNum)
        -- A depot is edited where it is painted: stand in the yard and open the
        -- same filter window a container uses.
        local depotZone = KnoxBaseStorage.depotZoneAt ~= nil
            and KnoxBaseStorage.depotZoneAt(base, square:getX(), square:getY(), square:getZ()) or nil
        if depotZone ~= nil then
            menu:addOption("Depot Filters — " .. tostring(depotZone.label or "Depot"),
                player, BaseContextMenu.openDepotFilters, depotZone)
        end
        local currentIntent = KnoxPersistence.getBaseIntent ~= nil
            and KnoxPersistence.getBaseIntent(base.id) or nil
        local intentOption = menu:addOption("Base Intent: "
            .. tostring(BASE_INTENT_LABELS[currentIntent] or "Not set"), nil, nil)
        local intentMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(intentOption, intentMenu)
        for _, entry in ipairs(BASE_INTENTS) do
            if entry.key ~= currentIntent then
                intentMenu:addOption(entry.label, player,
                    BaseContextMenu.setBaseIntent, base, entry.key)
            end
        end
        -- Kind and Intent were two menus for one question. Kind is now derived
        -- from the record (first base = main, a later one = outpost) and the
        -- weekly preference is the single Intent menu above. Legacy `base.kind`
        -- values still read through KnoxPersistence.baseKindFor; nothing is
        -- written to that field by the player any more.
        -- A room is renamed where it is: the menu offers the short list the
        -- compound owner defines, so no text box is needed for a two-word name.
        local roomApi = rawget(_G, "KnoxBaseCompound")
        if roomApi ~= nil and roomApi.roomNameAt ~= nil then
            local roomName, roomEntry = roomApi.roomNameAt(
                base, square:getX(), square:getY(), square:getZ())
            if roomEntry ~= nil then
                local roomOption = menu:addOption("Room: " .. tostring(roomName or "unnamed"), nil, nil)
                local roomMenu = ISContextMenu:getNew(menu)
                menu:addSubMenu(roomOption, roomMenu)
                for _, preset in ipairs(roomApi.ROOM_PRESETS or {}) do
                    if preset ~= roomName then
                        roomMenu:addOption(preset, player, BaseContextMenu.renameRoomHere, preset)
                    end
                end
            end
        end
        -- A proposal is read-only until the player applies it. It never edits
        -- an existing zone or assigns a storage policy.
        local layoutBuilding = nil
        if layoutBase ~= nil then
            local ok, found = pcall(function() return square:getBuilding() end)
            if ok then layoutBuilding = found end
        end
        if layoutBase ~= nil and layoutBuilding ~= nil then
            local entries, layoutReason = KnoxBaseManager.proposeLayout(
                layoutBase.id, layoutBuilding, square:getZ(), player)
            entries = type(entries) == "table" and entries or {}
            local storageEntries = type(entries.storage) == "table" and entries.storage or {}
            local proposedCount = #entries + #storageEntries
            local layoutOption = menu:addOption("Layout Proposal"
                .. (proposedCount > 0 and (" (" .. tostring(proposedCount) .. ")") or ""), nil, nil)
            local layoutMenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(layoutOption, layoutMenu)
            if proposedCount == 0 then
                local status = layoutMenu:addOption(layoutReasonText(layoutReason), nil, nil)
                status.notAvailable = true
            else
                for _, entry in ipairs(entries) do
                    local bounds = entry.bounds or {}
                    local width = math.abs((tonumber(bounds.x2) or 0) - (tonumber(bounds.x1) or 0)) + 1
                    local height = math.abs((tonumber(bounds.y2) or 0) - (tonumber(bounds.y1) or 0)) + 1
                    local line = layoutMenu:addOption(
                        tostring(entry.label or entry.zoneType) .. " — "
                            .. tostring(entry.zoneType) .. " ("
                            .. tostring(width) .. "x" .. tostring(height) .. ")",
                        nil, nil)
                    line.notAvailable = true
                end
                for _, entry in ipairs(storageEntries) do
                    local line = layoutMenu:addOption(
                        "Storage: " .. tostring(entry.label or entry.category)
                            .. " (" .. tostring(entry.category) .. ") — "
                            .. tostring(entry.roomLabel or "container"),
                        nil, nil)
                    line.notAvailable = true
                end
                layoutMenu:addOption("Apply Layout", player,
                    BaseContextMenu.applyLayout, layoutBase, entries)
                layoutMenu:addOption("Edit Work Areas…", BaseContextMenu,
                    BaseContextMenu.openSetup, playerNum)
                layoutMenu:addOption("Dismiss", player,
                    BaseContextMenu.dismissLayout, layoutBase)
            end
        end
        -- Base-scoped, location-bound orders exist only in this world menu; the
        -- emote radial deliberately has no position-bound commands. Hiding them
        -- behind the legacy right-click option left scouting and barricading
        -- unreachable with default settings, so they stay available here.
        local ordersOption = menu:addOption("Base Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(ordersOption, ordersMenu)
        -- Party size is a property of the same order, so it is a nested choice
        -- rather than peer entries. Fewer available residents than asked for is
        -- not an error: the departure line names who actually went.
        local PARTY_LABELS = { "One resident", "Two residents", "Three residents" }
        local function addMissionOrder(parentMenu, label, missionType)
            local option = parentMenu:addOption(label, nil, nil)
            local partyMenu = ISContextMenu:getNew(parentMenu)
            parentMenu:addSubMenu(option, partyMenu)
            for size = 1, #PARTY_LABELS do
                partyMenu:addOption(PARTY_LABELS[size], player,
                    BaseContextMenu.dispatchScout, base, square, size, missionType)
            end
        end
        addMissionOrder(ordersMenu, "Send Scout Here", "scout")
        addMissionOrder(ordersMenu, "Send Food Run Here", "food")
        addMissionOrder(ordersMenu, "Send Medical Run Here", "medicine")
        addMissionOrder(ordersMenu, "Send Tool Run Here", "tools")
        addMissionOrder(ordersMenu, "Send Weapon Run Here", "weapons")
        addMissionOrder(ordersMenu, "Send Material Run Here", "building")
        ordersMenu:addOption("Barricade Building Windows", player,
            BaseContextMenu.orderBarricadeHere, base, square)
        local barricades = rawget(_G, "KnoxBaseBarricades")
        if barricades ~= nil and barricades.canKeepOpen ~= nil
            and KnoxBaseManager.containsSquare(base, square) then
            for _, object in ipairs(worldobjects or {}) do
                if barricades.canKeepOpen(object) then
                    local keep = barricades.isKeepOpen(object)
                    menu:addOption(keep and "Allow Boarding This Opening"
                        or "Keep This Opening Clear", player,
                        BaseContextMenu.toggleKeepOpen, object)
                end
            end
        end
    end
    -- Storage filter access is a direct world-object action by design: players
    -- should not need to discover and open the broader Knox submenu first.
    for _, entry in ipairs(containers) do
        addStorageMenu(context, entry.base, entry.object, playerNum)
    end
    addBedMenu(menu, base, player, playerId, worldobjects)
    addRadioMenu(menu, base, player, worldobjects)
end

-- RADIO STATUS (pure)
-- One line about the set the player is pointing at. Power is named from the
-- source that actually feeds it (object grid, generator, device battery), in
-- that order, and a reader that does not answer is reported as no power rather
-- than assumed. The transmit figure is the script's own number, never a
-- survivor-scale radius.
function BaseContextMenu.radioStatusText(parts)
    local source = type(parts) == "table" and parts or {}
    local power
    if source.grid == true then power = "grid"
    elseif source.generator == true then power = "generator"
    elseif source.battery == true then power = "battery"
    else power = "no power" end
    local line = "Radio: " .. (source.on == true and "switched on" or "switched off")
        .. " · " .. power
    local range = tonumber(source.range)
    if range ~= nil and range > 0 then
        line = line .. " · transmit " .. tostring(math.floor(range))
    end
    return line
end
-- END RADIO STATUS

-- The tower's first slice, and only its first: a real wave-signal device inside
-- the player's own territory is read through the audited object/device surface,
-- and the one write is the same setIsTurnedOn the television owner already uses.
-- There is no broadcast, no arrival and no record here.
local function baseRadioObject(worldobjects, base)
    if base == nil or type(worldobjects) ~= "table" then return nil end
    for _, object in ipairs(worldobjects) do
        local ok, isRadio = pcall(function()
            return instanceof(object, "IsoWaveSignal")
        end)
        if ok and isRadio == true then
            local square = nil
            pcall(function() square = object:getSquare() end)
            if square ~= nil and (KnoxBaseManager.containsSquare == nil
                or KnoxBaseManager.containsSquare(base, square)) then
                return object
            end
        end
    end
    return nil
end

function BaseContextMenu.toggleRadio(radio, player, on)
    if radio == nil then return end
    local device = nil
    pcall(function() device = radio:getDeviceData() end)
    if device == nil then return end
    local ok, nowOn = pcall(function()
        device:setIsTurnedOn(on == true)
        return device:getIsTurnedOn()
    end)
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed == nil or feed.event == nil then return end
    if ok and nowOn == on then
        feed.event(on == true and "Radio switched on." or "Radio switched off.")
    else
        feed.event("The radio will not switch on here.")
    end
end

-- RADIO MODE (pure)
-- The three modes, and the rule that anything else is the off mode. An unknown
-- value must never read as broadcasting: a save from a later build, a typo in a
-- debug call or a nil record would then put words in the county's mouth.
function BaseContextMenu.radioModeLabel(mode)
    if mode == "listen" then return "Listening" end
    if mode == "broadcast" then return "Calling on the radio" end
    return "Off"
end

function BaseContextMenu.radioModeIsCurrent(mode, current)
    local function normalize(value)
        if value == "listen" then return "listen" end
        if value == "broadcast" then return "broadcast" end
        return "off"
    end
    return normalize(mode) == normalize(current)
end
-- END RADIO MODE

-- The operator is the living resident with the best real Electrical skill, read
-- from the perk the game already tracks. No assignment is stored: it is answered
-- when the radio is used, so a dead or departed operator cannot leave a stale id.
local function radioOperatorLevel(base)
    local persistence = rawget(_G, "KnoxPersistence")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if base == nil or persistence == nil or runtime == nil
        or persistence.getBaseResidentIds == nil then
        return nil
    end
    local levels = {}
    for _, id in ipairs(persistence.getBaseResidentIds(base.id) or {}) do
        local character = runtime.getCharacter ~= nil and runtime.getCharacter(id) or nil
        if character ~= nil and character:isDead() ~= true then
            local ok, level = pcall(function() return character:getPerkLevel(Perks.Electricity) end)
            if ok then levels[#levels + 1] = tonumber(level) end
        end
    end
    -- One authority for "the strongest resident answers": the base manager's
    -- pure rule, shared with the arrival roll so the menu and the tower cannot
    -- disagree about who operates the set.
    local baseManager = rawget(_G, "KnoxBaseManager")
    if baseManager == nil or baseManager.radioOperatorLevel == nil then return nil end
    return baseManager.radioOperatorLevel(levels)
end

-- Setting a mode writes the one record and moves the real device with it: on to
-- listen or call, off to off. A call also puts one line through the audited
-- device text so the set visibly transmits, and says plainly that no answer has
-- come back — the arrival roll is a later pass, not an invented reply here.
function BaseContextMenu.setRadioMode(radio, base, playerId, mode, worldAgeHours)
    if radio == nil or base == nil then return end
    local persistence = rawget(_G, "KnoxPersistence")
    local feed = rawget(_G, "KnoxActivityFeed")
    if persistence == nil or persistence.setBaseRadioMode == nil then return end
    local ok, detail = persistence.setBaseRadioMode(base.id, playerId, mode, worldAgeHours)
    if ok ~= true then
        if feed ~= nil and feed.event ~= nil then
            feed.event("Only the owner can set this radio.")
        end
        return
    end
    local device = nil
    pcall(function() device = radio:getDeviceData() end)
    if device ~= nil then
        pcall(function() device:setIsTurnedOn(mode ~= "off") end)
    end
    if mode == "broadcast" then
        local square = nil
        pcall(function() square = radio:getSquare() end)
        local level = radioOperatorLevel(base)
        local line = "Is anyone out there? This is " .. tostring(base.name or "the house") .. "."
        if square ~= nil then
            pcall(function()
                radio:AddDeviceText(line, square:getX(), square:getY(), square:getZ(),
                    "radio", "broadcast", 0)
            end)
        end
        if feed ~= nil and feed.event ~= nil then
            feed.event(level ~= nil and level > 0
                and "Calling on the radio. Nobody has answered yet."
                or "Calling on the radio, though nobody here knows how to run it well. Nobody has answered yet.")
        end
        return
    end
    if feed ~= nil and feed.event ~= nil then
        feed.event(mode == "listen" and "Listening on the radio." or "Radio off.")
    end
end

addRadioMenu = function(menu, base, player, worldobjects)
    local radio = baseRadioObject(worldobjects, base)
    if radio == nil then return end
    local device = nil
    pcall(function() device = radio:getDeviceData() end)
    local on = false
    if device ~= nil then
        local ok, value = pcall(function() return device:getIsTurnedOn() end)
        on = ok and value == true
    end
    local grid, generator, battery, range = false, false, false, nil
    pcall(function() grid = radio:hasGridPower() == true end)
    pcall(function() generator = radio:couldBePoweredByGenerator() == true end)
    if device ~= nil then
        pcall(function() battery = device:getHasBattery() == true end)
        local ok, value = pcall(function() return device:getTransmitRange() end)
        if ok then range = tonumber(value) end
    end
    local status = menu:addOption(BaseContextMenu.radioStatusText({
        on = on, grid = grid, generator = generator, battery = battery, range = range,
    }), nil, nil)
    status.notAvailable = true
    menu:addOption(on and "Switch Radio Off" or "Switch Radio On", player,
        BaseContextMenu.toggleRadio, radio, not on)
    local persistence = rawget(_G, "KnoxPersistence")
    local playerId = persistence ~= nil and persistence.ensurePlayerId ~= nil
        and persistence.ensurePlayerId(player) or nil
    local mode = persistence ~= nil and persistence.getBaseRadioMode ~= nil
        and persistence.getBaseRadioMode(base.id) or "off"
    local worldAgeHours = 0
    pcall(function() worldAgeHours = getGameTime():getWorldAgeHours() end)
    local modeOption = menu:addOption("Mode: " .. BaseContextMenu.radioModeLabel(mode), nil, nil)
    local modeMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(modeOption, modeMenu)
    for _, entry in ipairs({ { "off", "Off" }, { "listen", "Listen" },
        { "broadcast", "Call on the radio" } }) do
        if not BaseContextMenu.radioModeIsCurrent(entry[1], mode) then
            modeMenu:addOption(entry[2], player, BaseContextMenu.setRadioMode,
                radio, base, playerId, entry[1], worldAgeHours)
        end
    end
    -- The cost of being heard is stated before the switch, in the menu the
    -- switch lives in. It is a sentence from the base manager's pure rule, so
    -- the wording and the odds cannot drift apart.
    local baseManager = rawget(_G, "KnoxBaseManager")
    if baseManager ~= nil and baseManager.radioRiskText ~= nil and mode ~= "broadcast" then
        local line = modeMenu:addOption(baseManager.radioRiskText(radioOperatorLevel(base)), nil, nil)
        line.notAvailable = true
    end
end

Events.OnFillWorldObjectContextMenu.Add(BaseContextMenu.onFill)

return BaseContextMenu
