require "KS_Settings"
local Cupboard = {}
KnoxToolCupboard = Cupboard

-- Build 42.20.3 enforces 100 for ordinary world ItemContainers.  A vehicle
-- container can use the larger native vehicle limit; nested item containers
-- have the smaller native bag limit.  Never ask the engine to apply a value it
-- will reject and warn about.
local WORLD_CONTAINER_MAX = 100
local BAG_CONTAINER_MAX = 50
local VEHICLE_CONTAINER_MAX = 1000

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function safe(call, fallback)
    local ok, value = pcall(call)
    return ok and value or fallback
end

function Cupboard.nativeCapacityLimit(container)
    if container == nil then return WORLD_CONTAINER_MAX end
    if container.isVehiclePart ~= nil then
        local ok, vehiclePart = pcall(container.isVehiclePart, container)
        if ok and vehiclePart == true then return VEHICLE_CONTAINER_MAX end
    end
    if container.getContainingItem ~= nil then
        local ok, containingItem = pcall(container.getContainingItem, container)
        if ok and containingItem ~= nil then return BAG_CONTAINER_MAX end
    end
    return WORLD_CONTAINER_MAX
end

function Cupboard.effectiveCapacity(container)
    local requested = KnoxSettings.toolCupboardCapacity()
    return math.max(1, math.min(requested, Cupboard.nativeCapacityLimit(container)))
end

function Cupboard.isDryContainerType(containerType)
    local kind = string.lower(tostring(containerType or "container"))
    return kind ~= "corpse" and not kind:find("fridge", 1, true)
        and not kind:find("freezer", 1, true) and not kind:find("water", 1, true)
        and not kind:find("rain", 1, true)
end

function Cupboard.apply(object, container, key)
    local data = object ~= nil and object.getModData ~= nil and object:getModData() or nil
    local marker = data ~= nil and data.KnoxToolCupboard or nil
    if type(marker) ~= "table" or marker.key ~= key or container == nil
        or container.setCapacity == nil then return false end
    local capacity = Cupboard.effectiveCapacity(container)
    if container:getCapacity() ~= capacity then container:setCapacity(capacity) end
    return true
end

local function objectData(object)
    if object == nil or object.getModData == nil then return nil end
    local ok, data = pcall(function() return object:getModData() end)
    return ok and data or nil
end

local function containerIndexKey(containerIndex)
    return tostring(math.max(0, math.floor(tonumber(containerIndex) or 0)))
end

local function hasOtherAssignedPolicy(object, key, containerIndex, capacityState)
    local wantedIndex = containerIndexKey(containerIndex)
    for otherKey, assignment in pairs(capacityState.assignments or {}) do
        if tostring(otherKey) ~= tostring(key)
            and type(assignment) == "table"
            and tostring(assignment.containerIndex) == wantedIndex then
            return true
        end
    end
    -- A different base may reference the same world container under its own
    -- stable policy key. Consult the existing base-policy owner rather than
    -- treating this object ModData marker as another storage authority.
    local persistence = rawget(_G, "KnoxPersistence")
    local getBases = persistence ~= nil and persistence.getBases or nil
    local bases = type(getBases) == "function"
        and safe(function() return getBases() end, nil) or nil
    local square = object ~= nil and object.getSquare ~= nil
        and safe(function() return object:getSquare() end, nil) or nil
    local objectIndex = object ~= nil and object.getObjectIndex ~= nil
        and safe(function() return object:getObjectIndex() end, nil) or nil
    if type(bases) == "table" and square ~= nil and objectIndex ~= nil then
        local sx = safe(function() return square:getX() end, nil)
        local sy = safe(function() return square:getY() end, nil)
        local sz = safe(function() return square:getZ() end, nil)
        for _, base in pairs(bases) do
            for policyKey, policy in pairs(base.storage or {}) do
                if tostring(policyKey) ~= tostring(key) and type(policy) == "table"
                    and tostring(math.floor(tonumber(policy.containerIndex) or 0)) == wantedIndex
                    and tonumber(policy.objectIndex) == tonumber(objectIndex)
                    and tonumber(policy.x) == tonumber(sx)
                    and tonumber(policy.y) == tonumber(sy)
                    and tonumber(policy.z) == tonumber(sz) then
                    return true
                end
            end
        end
    end
    return false
end

-- Historical function name retained for save/runtime compatibility. This
-- applies only Build 42's native capacity ceiling plus an assignment marker;
-- it does not create an unlimited-weight bypass. Preserve the pre-assignment
-- capacity per native container index so removal can restore it without
-- deleting any contents.
function Cupboard.applyInfinite(object, container, key, containerIndex)
    if object == nil or container == nil or container.setCapacity == nil then return false end
    local data = objectData(object)
    if data == nil then return false end
    local index = containerIndexKey(containerIndex)
    local policyKey = tostring(key or "assigned")
    local state = data.KnoxStorageCapacity
    if type(state) ~= "table" then state = {}; data.KnoxStorageCapacity = state end
    state.originalByContainerIndex = state.originalByContainerIndex or {}
    state.assignments = state.assignments or {}
    if state.originalByContainerIndex[index] == nil then
        local legacy = data.KnoxToolCupboard
        local legacyKey = type(legacy) == "table" and tostring(legacy.key or "") or ""
        local sameLegacyCompartment = legacyKey == policyKey
            or legacyKey == "" or legacyKey:sub(-#(":" .. index)) == ":" .. index
        local original = sameLegacyCompartment and type(legacy) == "table"
            and tonumber(legacy.originalCapacity) or nil
        local alreadyAssigned = type(data.KnoxInfiniteStorage) == "table"
            and data.KnoxInfiniteStorage[policyKey] ~= nil
        if original == nil and not alreadyAssigned then
            original = safe(function() return container:getCapacity() end, nil)
        end
        -- Old typed assignments did not retain an original. Their current
        -- boosted capacity is not evidence of the value before assignment.
        state.originalByContainerIndex[index] = tonumber(original)
    end
    state.assignments[policyKey] = { containerIndex = index }
    data.KnoxInfiniteStorage = data.KnoxInfiniteStorage or {}
    data.KnoxInfiniteStorage[policyKey] = true
    local capacity = Cupboard.nativeCapacityLimit(container)
    local ok = pcall(function()
        if container:getCapacity() ~= capacity then container:setCapacity(capacity) end
    end)
    if object.transmitModData ~= nil then
        pcall(function() object:transmitModData() end)
    end
    return ok
end

function Cupboard.clearInfinite(object, container, key, containerIndex)
    if object == nil or container == nil or container.setCapacity == nil then
        return false, "container_unavailable"
    end
    local data = objectData(object)
    if data == nil then return false, "container_moddata_unavailable" end
    local policyKey = tostring(key or "assigned")
    local state = type(data.KnoxStorageCapacity) == "table"
        and data.KnoxStorageCapacity or {}
    state.originalByContainerIndex = state.originalByContainerIndex or {}
    state.assignments = state.assignments or {}
    local assignment = state.assignments[policyKey]
    local legacy = data.KnoxToolCupboard
    local legacyMatches = type(legacy) == "table"
        and (legacy.key == nil or tostring(legacy.key) == policyKey)
    local marker = type(data.KnoxInfiniteStorage) == "table"
        and data.KnoxInfiniteStorage or nil
    if assignment == nil and (marker == nil or marker[policyKey] == nil)
        and not legacyMatches then
        return false, "capacity_assignment_marker_missing"
    end
    local index = containerIndexKey(assignment ~= nil
        and assignment.containerIndex or containerIndex)
    local original = tonumber(state.originalByContainerIndex[index])
    if original == nil and legacyMatches then original = tonumber(legacy.originalCapacity) end

    local otherAssigned = hasOtherAssignedPolicy(object, policyKey, index, state)
    if otherAssigned then
        -- Keep the first pre-assignment capacity while another base policy on
        -- this exact native compartment remains active.
        state.originalByContainerIndex[index] = original
    end
    if not otherAssigned then
        if original ~= nil then
            -- Restore only a capacity actually observed before assignment.
            -- Other mods may own larger values; do not replace their value
            -- with our assignment ceiling or treat a silent native rejection
            -- as success. Keep the rollback metadata when readback disagrees.
            local restored, matches = pcall(function()
                if container:getCapacity() ~= original then
                    container:setCapacity(original)
                end
                return container:getCapacity() == original
            end)
            if not restored or not matches then return false, "capacity_restore_failed" end
        end
        state.originalByContainerIndex[index] = nil
    end

    state.assignments[policyKey] = nil
    if marker ~= nil then
        marker[policyKey] = nil
        if not hasEntries(marker) then data.KnoxInfiniteStorage = nil end
    end
    if legacyMatches and not otherAssigned then data.KnoxToolCupboard = nil end
    if not hasEntries(state.assignments) and not hasEntries(state.originalByContainerIndex) then
        data.KnoxStorageCapacity = nil
    else
        data.KnoxStorageCapacity = state
    end
    if object.transmitModData ~= nil then
        pcall(function() object:transmitModData() end)
    end
    return true, original ~= nil and "capacity_restored" or "original_capacity_unknown"
end

function Cupboard.isInfiniteContainer(container)
    if container == nil then return false end
    -- World containers expose their parent object; bags expose containing item.
    -- This legacy query only observes assignment metadata; it does not bypass
    -- native capacity or weight limits.
    local parent = nil
    if container.getParent ~= nil then
        local ok, value = pcall(function() return container:getParent() end)
        if ok then parent = value end
    end
    if parent ~= nil and parent.getModData ~= nil then
        local ok, data = pcall(function() return parent:getModData() end)
        if ok and data ~= nil then
            if type(data.KnoxInfiniteStorage) == "table"
                and hasEntries(data.KnoxInfiniteStorage) then return true end
            if data.KnoxToolCupboard ~= nil then return true end
        end
    end
    return false
end

function Cupboard.designate(base, object, containerIndex, manager)
    -- Main Supplies retired: typed storages set via other menus are canonical.
    -- Kept for legacy saves; always fails for new assignments.
    return nil, "main_supplies_retired"
end
return Cupboard
