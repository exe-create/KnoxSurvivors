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

local BaseContextMenu = rawget(_G, "KnoxBaseContextMenu") or {}
_G.KnoxBaseContextMenu = BaseContextMenu

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function contextOrdersEnabled()
    if KnoxSettings == nil or KnoxSettings.showLegacyContextCommands == nil then return false end
    local ok, enabled = pcall(KnoxSettings.showLegacyContextCommands)
    return ok and enabled == true
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
    if base ~= nil then
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

function BaseContextMenu.openSetup(_, playerNum)
    if KnoxSurvivorNotebook and KnoxSurvivorNotebook.show then
        KnoxSurvivorNotebook.show(playerNum)
    end
end

function BaseContextMenu.dispatchScout(player, base, square)
    local success, result = KnoxSurvivorAutonomy.dispatchBaseScout(player, base.id, square)
    KnoxActivityFeed.event(success and ("Scout departed: " .. tostring(result) .. ".")
        or ("Could not send scout: " .. tostring(result) .. "."))
end

function BaseContextMenu.toggleDoorLock(player, base, door)
    if player == nil or base == nil or door == nil then
        KnoxActivityFeed.event("Could not lock door: missing target.")
        return
    end
    local locked = false
    pcall(function()
        if door.isLockedByKey ~= nil then locked = door:isLockedByKey() == true end
        if not locked and door.isLocked ~= nil then locked = door:isLocked() == true end
    end)
    local ok = pcall(function()
        if door.setLockedByKey ~= nil then
            door:setLockedByKey(not locked)
        end
        if door.setLocked ~= nil then
            door:setLocked(not locked)
        end
        if door.setKeyId ~= nil and not locked then
            door:setKeyId(tostring(base.id))
        end
        if door.transmitCompleteItemToServer ~= nil then
            door:transmitCompleteItemToServer()
        elseif door.transmitModData ~= nil then
            door:transmitModData()
        end
    end)
    if ok then
        -- Persist locked doors so they survive reloads.
        if KnoxPersistence.setBaseDoorLock ~= nil then
            local sq = door.getSquare ~= nil and door:getSquare() or nil
            if sq ~= nil then
                KnoxPersistence.setBaseDoorLock(base.id,
                    sq:getX(), sq:getY(), sq:getZ(), not locked)
            end
        end
        KnoxActivityFeed.event(not locked and "Door locked at base."
            or "Door unlocked at base.")
    else
        KnoxActivityFeed.event("Could not lock door.")
    end
end

-- Direct base orders for specific windows/build sites. Queues the concrete
-- task (if needed) and assigns it to the best available resident. If nobody
-- can take it right now the queued task remains for automatic pickup.
local function bestResidentForTask(player, base, taskType)
    if KnoxPersistence.getBaseResidentIds == nil then return nil end
    local candidates = KnoxPersistence.getBaseResidentIds(base.id) or {}
    local preferred = {}
    local fallback = {}
    for _, survivorId in ipairs(candidates) do
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(survivorId) or {}
        local pref = tostring(duty.jobPreference or "auto")
        if pref == taskType or pref == "woodwork" or pref == "auto" then
            preferred[#preferred + 1] = survivorId
        else
            fallback[#fallback + 1] = survivorId
        end
    end
    for _, list in ipairs({ preferred, fallback }) do
        for _, survivorId in ipairs(list) do
            -- Eligibility (at base, skills, materials) is enforced by claimSpecific.
            return survivorId
        end
    end
    return nil
end

local function assignTaskToBestResident(player, base, task)
    if task == nil then return nil end
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.assignBaseTask == nil then return nil end
    local preference = task.type == "barricade" and "barricade" or "woodwork"
    local survivorId = bestResidentForTask(player, base, preference)
    if survivorId == nil then return nil end
    local assigned = service.assignBaseTask(player, survivorId, base.id, task.id)
    return assigned
end

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
    local targets = {}
    if barricades.findTargetsInBuilding ~= nil then
        targets = barricades.findTargetsInBuilding(base, square, nil, 24) or {}
    end
    if #targets == 0 then
        local tx, ty, tz = square:getX(), square:getY(), square:getZ()
        local single = barricades.findTarget ~= nil and barricades.findTarget(base, nil,
            function(candidate)
                return tonumber(candidate.x) == tx and tonumber(candidate.y) == ty
                    and tonumber(candidate.z) == tz
            end) or nil
        if single ~= nil then targets = { single } end
    end
    if #targets == 0 then
        KnoxActivityFeed.event("Nothing here needs barricading.")
        return
    end
    local hammer = barricades.findHammer ~= nil and barricades.findHammer(nil, base) or nil
    local hammerType = hammer ~= nil and hammer.getFullType ~= nil
        and hammer:getFullType() or "Base.Hammer"
    local queued, assigned = 0, nil
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
            if assigned == nil then
                assigned = assignTaskToBestResident(player, base, task)
            end
        end
    end
    if queued == 0 then
        KnoxActivityFeed.event("Could not queue barricade work.")
        return
    end
    KnoxActivityFeed.event(assigned ~= nil
        and ("Resident ordered to barricade " .. tostring(queued) .. " windows.")
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

function BaseContextMenu.onFill(playerNum, context, worldobjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    local player = getSpecificPlayer(playerNum)
    local square = firstSquare(worldobjects)
    if player == nil or square == nil then
        return
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxBaseManager.getForOwner("player", playerId)
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
        end
    end
    if base ~= nil then
        menu:addOption("Open Base Management", BaseContextMenu, BaseContextMenu.openSetup, playerNum)
        if contextOrdersEnabled() then
            local ordersOption = menu:addOption("Resident Orders", nil, nil)
            local ordersMenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(ordersOption, ordersMenu)
            ordersMenu:addOption("Scout Here", player,
                BaseContextMenu.dispatchScout, base, square)
            ordersMenu:addOption("Barricade Building Windows", player,
                BaseContextMenu.orderBarricadeHere, base, square)
        end
        -- Door locks at base/safehouse.
        for _, object in ipairs(worldobjects or {}) do
            local isDoor = false
            if instanceof ~= nil and object ~= nil then
                local ok, result = pcall(function() return instanceof(object, "IsoDoor") end)
                isDoor = ok and result == true
            end
            if isDoor and KnoxBaseManager.containsSquare(base, square) then
                local locked = false
                pcall(function()
                    if object.isLockedByKey ~= nil then locked = object:isLockedByKey() == true end
                end)
                menu:addOption(locked and "Unlock Door at Base" or "Lock Door at Base", player,
                    BaseContextMenu.toggleDoorLock, base, object)
                break
            end
        end
    end
    -- Storage filter access is a direct world-object action by design: players
    -- should not need to discover and open the broader Knox submenu first.
    for _, entry in ipairs(containers) do
        addStorageMenu(context, entry.base, entry.object, playerNum)
    end
    addBedMenu(menu, base, player, playerId, worldobjects)
end

Events.OnFillWorldObjectContextMenu.Add(BaseContextMenu.onFill)

return BaseContextMenu
