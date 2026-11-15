require "KS_Persistence"
require "KS_ToolCupboard"
require "KS_BaseSupplyPlanner"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"
require "Util/AdjacentFreeTileFinder"

local Storage = rawget(_G, "KnoxBaseStorage") or {}
_G.KnoxBaseStorage = Storage
local loadedContainerCache = {}
local LOADED_CONTAINER_CACHE_MS = 10000

local MEDICAL_TYPES = {
    ["Base.AlcoholWipes"] = true,
    ["Base.BottleDisinfectant"] = true,
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.SutureNeedle"] = true,
    ["Base.Tweezers"] = true,
}

local TOOL_TYPES = {
    ["Base.Axe"] = true,
    ["Base.HandAxe"] = true,
    ["Base.Hammer"] = true,
    ["Base.Saw"] = true,
    ["Base.Screwdriver"] = true,
    ["Base.Wrench"] = true,
    ["Base.LugWrench"] = true,
    ["Base.Jack"] = true,
    ["Base.TirePump"] = true,
}

local BUILDING_TYPES = {
    ["Base.Plank"] = true,
    ["Base.SheetMetal"] = true,
    ["Base.SmallSheetMetal"] = true,
    ["Base.Nails"] = true,
    ["Base.Glue"] = true,
    ["Base.Woodglue"] = true,
    ["Base.Screws"] = true,
    ["Base.DuctTape"] = true,
}

-- Raw timber has its own role so log piles stay separate from processed
-- building supplies. Anything already shelved under building stays valid;
-- only new classification prefers logs.
local LOG_TYPES = {
    ["Base.Log"] = true,
    ["Base.TreeBranch"] = true,
    ["Base.Twigs"] = true,
    ["Base.Firewood"] = true,
}

-- Fuel cans are real fluid containers, not generic vehicle-maintenance
-- materials. Keep the known Build 42 types here so a gas can cannot fall
-- through to building storage just because its DisplayCategory is
-- VehicleMaintenance.
local FUEL_TYPES = {
    ["Base.PetrolCan"] = true,
    ["Base.EmptyPetrolCan"] = true,
    ["Base.JerryCan"] = true,
}

local FARMING_TYPES = {
    ["Base.WateredCan"] = true,
    ["Base.WaterCan"] = true,
    ["Base.HandShovel"] = true,
    ["Base.GardeningSprayEmpty"] = true,
    ["Base.Fertilizer"] = true,
}

-- Keep the base-facing categories aligned with in-game DisplayCategory names
-- (Materials, Junk, etc.) and the storage context menu.
Storage.RESOURCE_CATEGORIES = {
    "food",
    "water",
    "medical",
    "weapons",
    "ammunition",
    "tools",
    "logs",
    "fuel",
    "building",
    "farming",
    "clothing",
    "junk",
}

local function fullType(item)
    if item == nil or item.getFullType == nil then
        return ""
    end
    return tostring(item:getFullType() or "")
end

local function safeBoolean(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    if success and type(value) == "boolean" then return value end
    return nil
end

function Storage.resolvePolicy(policy, readOnly)
    if policy == nil or getCell == nil or getCell() == nil then
        return nil, "cell_unavailable"
    end
    -- Automatically discovered containers are transient candidates, never
    -- persisted policies. Revalidate their native identity and base bounds,
    -- and deliberately skip policy naming/capacity side effects.
    if policy.transientContainer == true then
        local object = policy.object
        local square = object ~= nil and object.getSquare ~= nil
            and object:getSquare() or nil
        local area = policy.base ~= nil
            and (policy.base.territory or policy.base.home) or nil
        local maxX = area ~= nil and (area.maxX
            or (area.minX + (area.width or 1) - 1)) or nil
        local maxY = area ~= nil and (area.maxY
            or (area.minY + (area.height or 1) - 1)) or nil
        if square == nil or area == nil
            or square:getX() ~= policy.x or square:getY() ~= policy.y
            or square:getZ() ~= policy.z
            or square:getX() < area.minX or square:getX() > maxX
            or square:getY() < area.minY or square:getY() > maxY
            or (area.allFloors ~= true and square:getZ() ~= (area.z or 0)) then
            return nil, "transient_container_moved"
        end
        local container = object.getContainerByIndex ~= nil
            and object:getContainerByIndex(policy.containerIndex) or nil
        if container == nil or container ~= policy.container
            or (container.isExistYet ~= nil and not container:isExistYet()) then
            return nil, "transient_container_unavailable"
        end
        local objects = square.getObjects ~= nil and square:getObjects() or nil
        local present = false
        if objects ~= nil then
            for index = 0, objects:size() - 1 do
                if objects:get(index) == object then present = true; break end
            end
        end
        if not present then return nil, "transient_object_missing" end
        return { policy = policy, square = square, object = object,
            container = container }, "resolved"
    end
    local square = getCell():getGridSquare(
        tonumber(policy.x) or 0,
        tonumber(policy.y) or 0,
        tonumber(policy.z) or 0
    )
    if square == nil or square.getObjects == nil then
        return nil, "storage_square_unloaded"
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local objectIndex = object ~= nil and object:getObjectIndex() or -1
        local stablePolicy = type(policy.key) == "string" and string.find(policy.key, ":container:", 1, true) ~= nil
        local matches = not stablePolicy and objectIndex == tonumber(policy.objectIndex)
        if stablePolicy and object ~= nil and object.getModData ~= nil then
            local data = object:getModData()
            local ids = data ~= nil and data.KnoxSurvivors ~= nil and data.KnoxSurvivors.storageIds or {}
            for _, id in pairs(ids or {}) do
                if id == policy.key then matches = true; break end
            end
        end
        if object ~= nil and matches then
            local containerIndex = tonumber(policy.containerIndex) or 0
            local container = object:getContainerByIndex(containerIndex)
            if container ~= nil and container:isExistYet() then
                local actualType = tostring(container:getType() or "container")
                local expectedType = tostring(policy.containerType or actualType)
                if expectedType == actualType or expectedType == "container" then
                    if readOnly ~= true then
                    local legacyToolCupboardApplied = false
                    if policy.toolCupboard == true and object.getModData ~= nil
                        and container.getCapacity ~= nil and container.setCapacity ~= nil then
                        local data = object:getModData()
                        if data.KnoxToolCupboard == nil then
                            data.KnoxToolCupboard = { key = policy.key,
                                originalCapacity = container:getCapacity() }
                        end
                    end
                    if policy.toolCupboard == true and KnoxToolCupboard ~= nil
                        and KnoxToolCupboard.apply(object, container, policy.key) then
                        policy.toolCupboard = true
                        legacyToolCupboardApplied = true
                    end
                    -- Legacy cupboard records keep their configured capacity.
                    -- Current typed storage temporarily uses the Build 42
                    -- native limit and records the original value for removal.
                    if not legacyToolCupboardApplied and KnoxToolCupboard ~= nil
                        and KnoxToolCupboard.applyInfinite ~= nil then
                        pcall(function()
                            KnoxToolCupboard.applyInfinite(
                                object, container, policy.key, containerIndex
                            )
                        end)
                    end
                    -- Keep the world container title in sync with its assigned
                    -- storage type so the loot window shows organization.
                    Storage.syncContainerName(policy, container)
                    end
                    return {
                        policy = policy,
                        square = square,
                        object = object,
                        container = container,
                    }, "resolved"
                end
            end
        end
    end
    return nil, "storage_object_missing"
end

-- World container titles mirror the assigned storage type for organization.
-- Uses ItemContainer custom names; safe when the native API is unavailable.
function Storage.syncContainerName(policy, container)
    if policy == nil or container == nil or container.setCustomName == nil then return end
    local expected = Storage.label(policy)
    if expected == nil or expected == "" or expected == "Storage" then return end
    local ok, current = pcall(function() return container:getCustomName() end)
    if ok and current ~= expected then
        pcall(function() container:setCustomName(expected) end)
    end
end

function Storage.clearContainerName(policy, container)
    if container == nil or container.setCustomName == nil then return end
    local expected = nil
    if policy ~= nil then
        local okLabel, label = pcall(function() return Storage.label(policy) end)
        if okLabel then expected = label end
    end
    local ok, current = pcall(function() return container:getCustomName() end)
    if not ok then return end
    -- Only clear names we own; never wipe a player-renamed container.
    if expected == nil or current == expected or current == "Main Supplies" then
        pcall(function() container:setCustomName("") end)
    end
end

-- Typed storages are the canonical assignments. Legacy Main Supplies records
-- are retained read-only so old saves keep working until the player removes
-- or converts them; no new Main Supplies can be created.
function Storage.policies(base)
    if base == nil then return {} end
    local result = {}
    for key, policy in pairs(base.storage or {}) do
        if type(policy) == "table" and type(policy.key) == "string" then
            if policy.storageFilterVersion == 1 then
                -- A versioned filter record is authoritative even if an older
                -- or partially migrated save lacks the compatibility role.
                if policy.storageRole == nil then
                    policy.storageRole = policy.category or "supplies"
                end
                result[#result + 1] = policy
            -- Unmigrated records without any category are preserved on disk but
            -- never treated as assigned storage (legacy fridge check).
            elseif policy.category == nil and policy.storageRole == nil then
                -- Transient legacy-fridge migration: an old-save record that
                -- still resolves to a loaded fridge/freezer is surfaced as
                -- food storage so residents can eat from a stocked fridge.
                -- Nothing is written back; the save record is untouched.
                local migrated = Storage.legacyFridgePolicy(policy)
                if migrated ~= nil then
                    result[#result + 1] = migrated
                end
                -- else: preserve, do not include
            else
                if policy.storageRole == nil then
                    policy.storageRole = policy.category == "depot" and "supplies"
                        or policy.category or "supplies"
                end
                result[#result + 1] = policy
            end
        end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

local function storageArea(base)
    return base ~= nil and (base.territory or base.home) or nil
end

local function loadedContainerCacheKey(base, minX, minY, maxX, maxY, firstZ, lastZ)
    return table.concat({ tostring(base.id), tostring(minX), tostring(minY),
        tostring(maxX), tostring(maxY), tostring(firstZ), tostring(lastZ) }, ":")
end

-- Discover real containers in loaded base squares without assigning them,
-- changing their names/capacity, or persisting a second storage ledger.
-- Configured policies are returned first; these transient entries are fallback
-- candidates only and are revalidated before any native transfer is queued.
function Storage.operationalPolicies(base)
    local result, seen = {}, {}
    for _, policy in ipairs(Storage.policies(base)) do
        local resolved = Storage.resolvePolicy(policy, true)
        if resolved ~= nil then
            result[#result + 1] = policy
            seen[resolved.object] = seen[resolved.object] or {}
            seen[resolved.object][tonumber(policy.containerIndex) or 0] = true
        end
    end
    local area = storageArea(base)
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil or cell.getGridSquare == nil then return result end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local maxX = tonumber(area.maxX) or (minX and minX + (tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY and minY + (tonumber(area.height) or 1) - 1)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return result end
    local firstZ, lastZ = tonumber(area.minZ), tonumber(area.maxZ)
    if firstZ == nil or lastZ == nil then
        if area.allFloors == true then
            local ok, nativeMin, nativeMax = pcall(function() return cell:getMinZ(), cell:getMaxZ() end)
            nativeMin, nativeMax = tonumber(nativeMin), tonumber(nativeMax)
            if ok and nativeMin ~= nil and nativeMax ~= nil and nativeMin > -math.huge
                and nativeMax < math.huge and nativeMin <= nativeMax
                and nativeMin == math.floor(nativeMin) and nativeMax == math.floor(nativeMax) then
                firstZ, lastZ = nativeMin, nativeMax
            else
                firstZ = tonumber(area.z) or tonumber(base.home ~= nil and base.home.z)
                if firstZ == nil then return result end
                lastZ = firstZ
            end
        else
            firstZ = tonumber(area.z) or tonumber(base.home ~= nil and base.home.z) or 0
            lastZ = firstZ
        end
    end
    local cacheKey = loadedContainerCacheKey(base, minX, minY, maxX, maxY, firstZ, lastZ)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
    local cached = now ~= nil and loadedContainerCache[cacheKey] or nil
    -- Compare the live cell itself. A diagnostic tostring may include mutable
    -- fields and must not become part of a cache identity.
    local found = cached ~= nil and cached.cell == cell and now >= cached.at
        and now - cached.at < LOADED_CONTAINER_CACHE_MS and cached.entries or nil
    if found == nil then
        if now ~= nil then
            for key, entry in pairs(loadedContainerCache) do
                if now < entry.at or now - entry.at >= LOADED_CONTAINER_CACHE_MS then
                    loadedContainerCache[key] = nil
                end
            end
        end
        found = {}
        for z = firstZ, lastZ do
            for x = minX, maxX do
                for y = minY, maxY do
                    local square = cell:getGridSquare(x, y, z)
                    local objects = square ~= nil and square.getObjects ~= nil
                        and square:getObjects() or nil
                    if objects ~= nil then
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            local count = object ~= nil and object.getContainerCount ~= nil
                                and object:getContainerCount() or 0
                            for containerIndex = 0, count - 1 do
                                local container = object:getContainerByIndex(containerIndex)
                                local kind = string.lower(tostring(container ~= nil
                                    and container:getType() or ""))
                                if container ~= nil and container:isExistYet()
                                    and kind ~= "corpse" and kind ~= "floor"
                                    and kind:find("water", 1, true) == nil
                                    and kind:find("rain", 1, true) == nil then
                                    found[#found + 1] = {
                                        object = object, container = container,
                                        containerIndex = containerIndex, square = square,
                                        objectIndex = object:getObjectIndex(),
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
        if now ~= nil then loadedContainerCache[cacheKey] = { at = now, cell = cell, entries = found } end
    end
    for _, entry in ipairs(found) do
        local containerIndex = tonumber(entry.containerIndex) or 0
        if not (seen[entry.object] ~= nil and seen[entry.object][containerIndex]) then
            local kind = string.lower(tostring(entry.container:getType() or "container"))
            local policy = {
                key = table.concat({ "unassigned", tostring(base.id), tostring(entry.square:getX()),
                    tostring(entry.square:getY()), tostring(entry.square:getZ()),
                    tostring(entry.objectIndex), tostring(containerIndex), tostring(entry.object),
                    tostring(entry.container) }, ":"),
                x = entry.square:getX(), y = entry.square:getY(), z = entry.square:getZ(),
                objectIndex = entry.objectIndex, containerIndex = containerIndex,
                containerType = kind, transientContainer = true, base = base,
                object = entry.object, container = entry.container,
            }
            result[#result + 1] = policy
        end
    end
    return result
end

-- Classify only live native container state; unknown is not a cold claim.
function Storage.coldContainer(container)
    if container == nil then return nil end
    local okF, fridge = pcall(function() return container:isFridge() end)
    local okZ, freezer = pcall(function() return container:isFreezer() end)
    local okP, powered = pcall(function() return container:isPowered() end)
    if not okF or type(fridge) ~= "boolean" or not okZ or type(freezer) ~= "boolean"
        or not okP or type(powered) ~= "boolean" then return nil end
    local electricity = false
    if powered and (fridge or freezer) then
        local okGrid, grid = pcall(function() return container:getSourceGrid() end)
        if not okGrid or grid == nil then return nil end
        local okElec, value = pcall(function() return grid:haveElectricity() end)
        if not okElec or type(value) ~= "boolean" then return nil end
        electricity = value
    end
    return { fridge = fridge, freezer = freezer, powered = powered, electricity = electricity }
end

-- Transient, read-only migration for pre-typed-storage saves. Returns a
-- food-role view of a legacy record when it still resolves to a loaded
-- fridge/freezer, else nil. Never mutates the persisted record.
function Storage.legacyFridgePolicy(policy)
    if policy == nil or getCell == nil or getCell() == nil then return nil end
    local ok, resolved = pcall(function() return Storage.resolvePolicy(policy) end)
    if not ok or type(resolved) ~= "table" or resolved.container == nil then
        return nil
    end
    local okF, fridge = pcall(function() return resolved.container:isFridge() end)
    local okZ, freezer = pcall(function() return resolved.container:isFreezer() end)
    if not okF or not okZ or type(fridge) ~= "boolean" or type(freezer) ~= "boolean"
        or not (fridge or freezer) then return nil end
    return {
        key = policy.key,
        storageRole = "food",
        x = policy.x,
        y = policy.y,
        z = policy.z,
        objectIndex = policy.objectIndex,
        containerIndex = policy.containerIndex,
        containerType = policy.containerType,
    }
end

function Storage.mainPolicy(base)
    -- Legacy accessor kept for old saves and fallbacks. New assignments never
    -- create a main policy; callers should use policies() instead.
    for _, policy in ipairs(Storage.policies(base)) do
        if policy.storageRole == "supplies" or policy.toolCupboard == true then return policy end
    end
    return nil
end

local STORAGE_FILTER_LABELS = {
        supplies = "Main Supplies", food = "Food & Drink", water = "Water",
        medical = "Medical", weapons = "Weapons", ammunition = "Ammunition",
        tools = "Tools", logs = "Logs & Lumber", general = "General Storage",
        fuel = "Fuel", building = "Materials", farming = "Farming",
        clothing = "Clothing", junk = "Junk",
        perishable = "Perishable", nonperishable = "Non-Perishable",
        canned = "Canned / Preserved Food",
}
local STORAGE_FILTER_ORDER = {
    "perishable", "nonperishable", "canned",
    "food", "water", "medical", "weapons", "ammunition", "tools",
    "logs", "fuel", "building", "farming", "clothing", "junk", "general",
}

local function nativeFilterCategory(key)
    if type(key) ~= "string" or string.sub(key, 1, 8) ~= "display:" then return nil end
    local category = string.sub(key, 9)
    if category == "" or #category > 64 or not string.match(category, "^[%w_%-]+$") then
        return nil
    end
    return category
end

-- One item type is a storage rule of its own: item:Base.BookCarpentry. It is
-- an addition to the group filters, not a second filter system, so one policy
-- may hold both and the same deposit checks read them.
local function itemFilterType(key)
    if type(key) ~= "string" or string.sub(key, 1, 5) ~= "item:" then return nil end
    local fullType = string.sub(key, 6)
    if fullType == "" or #fullType > 64 or not string.match(fullType, "^[%w_%.%-]+$") then
        return nil
    end
    return fullType
end

local function itemDisplayName(fullType)
    local ok, scriptItem = pcall(function()
        return getScriptManager():getItem(tostring(fullType))
    end)
    if ok and scriptItem ~= nil then
        local nameOk, name = pcall(function() return scriptItem:getDisplayName() end)
        if nameOk and type(name) == "string" and name ~= "" then return name end
    end
    -- Fall back to the type without its module so the row still reads.
    return (string.match(tostring(fullType), "%.(.+)$") or tostring(fullType))
end

function Storage.itemFilterKey(fullType)
    if type(fullType) ~= "string" or fullType == "" or #fullType > 64
        or not string.match(fullType, "^[%w_%.%-]+$") then
        return nil
    end
    return "item:" .. fullType
end

function Storage.isItemFilterKey(key)
    return itemFilterType(key) ~= nil
end

function Storage.isValidFilterCategory(category)
    return STORAGE_FILTER_LABELS[category] ~= nil or nativeFilterCategory(category) ~= nil
        or itemFilterType(category) ~= nil
end

function Storage.filtersForPolicy(policy)
    if policy == nil then return {} end
    if policy.storageFilterVersion == 1 and type(policy.storageFilters) == "table" then
        local result = {}
        for _, category in ipairs(STORAGE_FILTER_ORDER) do
            if policy.storageFilters[category] == true then result[category] = true end
        end
        for category, enabled in pairs(policy.storageFilters) do
            if enabled == true and (nativeFilterCategory(category) ~= nil
                or itemFilterType(category) ~= nil) then
                result[category] = true
            end
        end
        return result
    end
    local role = policy.storageRole or policy.category or "supplies"
    if role == "supplies" or role == "depot" then role = "general" end
    return STORAGE_FILTER_LABELS[role] ~= nil and { [role] = true } or {}
end

function Storage.hasActiveFilters(policy)
    if policy == nil or policy.storageFilterVersion ~= 1 then return false end
    local filters = Storage.filtersForPolicy(policy)
    for _, enabled in pairs(filters) do
        if enabled == true then return true end
    end
    return false
end

function Storage.filterLabel(category)
    local itemType = itemFilterType(category)
    if itemType ~= nil then return itemDisplayName(itemType) end
    local nativeCategory = nativeFilterCategory(category)
    if nativeCategory ~= nil then return nativeCategory end
    return STORAGE_FILTER_LABELS[category] or "Storage"
end

-- One number pair a player can read at a glance: how many of this container's
-- items the row accepts, out of how many are in it. A group that is off accepts
-- none, so the left number is zero without a second explanation needed.
function Storage.countedLabel(label, accepted, total)
    if type(label) ~= "string" or label == "" then return "" end
    local count = tonumber(total)
    if count == nil or count ~= count then return label end
    count = math.max(0, math.floor(count))
    local keeps = math.max(0, math.floor(tonumber(accepted) or 0))
    if keeps > count then keeps = count end
    return label .. " (" .. tostring(keeps) .. "/" .. tostring(count) .. ")"
end

-- One row a storage list can print: what the container keeps, its priority,
-- what it is, the room it stands in, and where it is. The room is the
-- readable address; the coordinates stay because they are what loads.
function Storage.policyRowText(policy, available)
    if type(policy) ~= "table" then return "" end
    local room = type(policy.roomLabel) == "string" and policy.roomLabel ~= ""
        and (" in " .. policy.roomLabel) or ""
    local text = Storage.label(policy) .. " [" .. Storage.priorityLabel(policy) .. "]"
        .. " (" .. tostring(policy.containerType) .. ")" .. room .. " at "
        .. tostring(policy.x) .. ", " .. tostring(policy.y)
        .. ", floor " .. tostring(policy.z)
    if available == false then text = text .. " - unavailable" end
    return text
end
function Storage.label(policy)
    if policy ~= nil and policy.storageFilterVersion ~= 1
        and (policy.storageRole == "supplies" or policy.category == "depot") then
        return "Main Supplies"
    end
    local filters = Storage.filtersForPolicy(policy)
    local labels = {}
    for _, category in ipairs(STORAGE_FILTER_ORDER) do
        if filters[category] then labels[#labels + 1] = STORAGE_FILTER_LABELS[category] end
    end
    local native = {}
    for category in pairs(filters) do
        if nativeFilterCategory(category) ~= nil then native[#native + 1] = category end
    end
    table.sort(native)
    for _, category in ipairs(native) do labels[#labels + 1] = Storage.filterLabel(category) end
    local items = {}
    for category in pairs(filters) do
        if itemFilterType(category) ~= nil then items[#items + 1] = category end
    end
    table.sort(items)
    for _, category in ipairs(items) do labels[#labels + 1] = Storage.filterLabel(category) end
    if #labels == 0 then return "Storage" end
    -- A container set to dozens of item types would otherwise produce a line
    -- no notification can carry. The full set stays in the policy.
    if #labels > 4 then
        local shown = {}
        for index = 1, 3 do shown[index] = labels[index] end
        return table.concat(shown, " + ") .. " +" .. tostring(#labels - 3) .. " more"
    end
    return table.concat(labels, " + ")
end

local function filteredCategoryMatchesDeposit(item, category)
    if category == "canned" then
        return safeBoolean(item, "hasTag", ItemTag ~= nil and ItemTag.PRESERVED_FOOD or nil) == true
    end
    if category == "food" then
        local isFood = safeBoolean(item, "IsFood") == true
        if not isFood and item.getDisplayCategory ~= nil then
            local ok, value = pcall(item.getDisplayCategory, item)
            isFood = ok and value == "Food"
        end
        return isFood or KnoxSurvivorNeeds.isWaterItem(item, false)
    end
    return Storage.matchesCategory(item, category)
end

function Storage.filterAllowsItem(policy, item)
    if policy == nil or item == nil then return false end
    if policy.storageFilterVersion ~= 1 then return true end
    local filters = Storage.filtersForPolicy(policy)
    -- An empty selection is ordinary fallback storage. This keeps the
    -- player-facing "no categories" rule consistent across deposits,
    -- organizing, needs, and job-material retrieval.
    if not Storage.hasActiveFilters(policy) then return true end
    if filters.general then return true end
    for _, category in ipairs(STORAGE_FILTER_ORDER) do
        if filters[category] and filteredCategoryMatchesDeposit(item, category) then
            return true
        end
    end
    local displayCategory = ""
    if item.getDisplayCategory ~= nil then
        local ok, value = pcall(item.getDisplayCategory, item)
        if ok then displayCategory = tostring(value or "") end
    end
    for category, enabled in pairs(filters) do
        local nativeCategory = nativeFilterCategory(category)
        if enabled == true and nativeCategory ~= nil and displayCategory == nativeCategory then
            return true
        end
    end
    -- An explicit item rule only adds its own type: it never overrides a
    -- group the player already chose above.
    local itemFullType = nil
    if item.getFullType ~= nil then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok then itemFullType = tostring(value or "") end
    end
    if itemFullType ~= nil and itemFullType ~= "" then
        for category, enabled in pairs(filters) do
            if enabled == true and itemFilterType(category) == itemFullType then
                return true
            end
        end
    end
    return false
end

function Storage.filterAllowsKind(policy, kind)
    if policy == nil then return false end
    if policy.storageFilterVersion ~= 1 then return true end
    local filters = Storage.filtersForPolicy(policy)
    if not Storage.hasActiveFilters(policy) then return true end
    if filters.general == true or filters[kind] == true
        or (kind == "water" and filters.food == true)
    then return true end
    return false
end

-- RimWorld-style priority rank for deposit ordering. Lower sorts first:
-- critical shelves fill before preferred, normal, then low. Missing or
-- legacy records read as normal so old saves behave unchanged.
local STORAGE_PRIORITY_RANKS = {
    critical = 0, preferred = 1, normal = 2, low = 3,
}

-- Owner-set fill order: 1 is drawn from first, 9 last. The order lives on the
-- same stored policy record as its filters, under one fresh key, so a save
-- contract nothing else reads is not disturbed.
local STORAGE_ORDER_MAX = 9

-- The single read accessor every walk and label consults. A stored numeric
-- order wins; a record without one keeps the legacy named level; a record with
-- neither reads as normal, which is today's behaviour.
function Storage.storageOrder(policy)
    local order = policy ~= nil and tonumber(policy.priorityOrder) or nil
    if order == nil or order ~= math.floor(order)
        or order < 1 or order > STORAGE_ORDER_MAX then
        return nil
    end
    return order
end

-- The single write boundary for a storage's fill order. Numeric orders are
-- validated here; the legacy named level is still accepted and clears any
-- numeric order so one record can never carry two answers.
function Storage.setStoragePriority(policy, value)
    if type(policy) ~= "table" or type(policy.key) ~= "string" or policy.key == "" then
        return nil, "unknown_storage"
    end
    if value == nil then
        policy.priorityOrder = nil
        return policy, "cleared"
    end
    if type(value) == "number" then
        if value ~= math.floor(value) or value < 1 or value > STORAGE_ORDER_MAX then
            return nil, "invalid_order"
        end
        policy.priorityOrder = value
        policy.priority = nil
        return policy, "saved"
    end
    if type(value) ~= "string" or STORAGE_PRIORITY_RANKS[value] == nil then
        return nil, "invalid_order"
    end
    policy.priority = value
    policy.priorityOrder = nil
    return policy, "saved"
end

function Storage.priorityRank(policy)
    local order = Storage.storageOrder(policy)
    if order ~= nil then return order - 1 end
    local rank = policy ~= nil and STORAGE_PRIORITY_RANKS[policy.priority] or nil
    if rank == nil then return STORAGE_PRIORITY_RANKS.normal end
    return rank
end

function Storage.priorityLabel(policy)
    local order = Storage.storageOrder(policy)
    if order ~= nil then return "Order " .. tostring(order) end
    local labels = {
        critical = "Critical", preferred = "Preferred",
        normal = "Normal", low = "Low",
    }
    return labels[policy ~= nil and policy.priority or nil] or "Normal"
end

function Storage.acceptsDeposit(policy, item)
    if policy == nil or item == nil then return false end
    if policy.storageFilterVersion == 1 then
        local filters = Storage.filtersForPolicy(policy)
        for _, category in ipairs(STORAGE_FILTER_ORDER) do
            if filters[category] and (category == "general"
                or filteredCategoryMatchesDeposit(item, category)) then
                return true
            end
        end
        return Storage.filterAllowsItem(policy, item)
    end
    if policy.storageRole == "supplies" then return true end
    -- Raw ingredients belong in the kitchen too; edibility is checked separately
    -- when choosing a meal. Keep unsafe food out of the ready-to-eat stock count.
    if policy.storageRole == "food" then return safeBoolean(item, "IsFood") == true
        or (item.getDisplayCategory ~= nil and item:getDisplayCategory() == "Food")
        or KnoxSurvivorNeeds.isWaterItem(item, false) end
    return Storage.matchesCategory(item, policy.storageRole)
end

local function hasPrefix(value, prefix)
    return string.sub(value, 1, #prefix) == prefix
end

local function displayCategory(item)
    if item == nil or item.getDisplayCategory == nil then return "" end
    local ok, value = pcall(function() return item:getDisplayCategory() end)
    return ok and tostring(value or "") or ""
end

local function isFuelItem(item, full)
    full = full or fullType(item)
    if FUEL_TYPES[full] == true then return true end
    if rawget(_G, "ItemTag") ~= nil and ItemTag.FUEL ~= nil
        and safeBoolean(item, "hasTag", ItemTag.FUEL) == true then
        return true
    end
    return displayCategory(item) == "Fuel"
end

-- REAL PETROL PROOF (pure)
-- A fuel tag or display category says where a container belongs, not what is
-- inside it. Vanilla refuelling hands the generator a container holding
-- Fluid.Petrol; this is the same proof, and the only fuel proof this owner
-- offers a generator maintenance caller.
function Storage.hasPetrol(item)
    if item == nil or item.getFluidContainer == nil then return false end
    local ok, container = pcall(function() return item:getFluidContainer() end)
    if not ok or container == nil then return false end
    local okContains, contains = pcall(function() return container:contains(Fluid.Petrol) end)
    if not okContains or contains ~= true then return false end
    local okAmount, amount = pcall(function() return container:getAmount() end)
    return okAmount and tonumber(amount) ~= nil and tonumber(amount) > 0
end
-- END REAL PETROL PROOF

function Storage.matchesCategory(item, category)
    if item == nil then
        return false
    end
    local full = fullType(item)
    category = tostring(category or "general")
    if category == "general" then
        return true
    end
    if category == "fuel" then
        return isFuelItem(item, full)
    end
    if category == "perishable" or category == "nonperishable" then
        -- Food:canAge() owns this distinction. Build 42 uses 1,000,000,000
        -- as its never-rots sentinel, not zero. InventoryItem also exposes
        -- spoilage fields on non-food: those are not pantry supplies.
        if safeBoolean(item, "IsFood") ~= true then return false end
        local canAge = safeBoolean(item, "canAge")
        if canAge ~= nil then
            return category == "perishable" and canAge
                or category == "nonperishable" and not canAge
        end
        -- Retain compatibility with food wrappers exposing only the lifetime.
        -- Unknown or invalid values must not become shelf-stable by default.
        if item.getOffAgeMax == nil then return false end
        local ok, value = pcall(function() return item:getOffAgeMax() end)
        local days = ok and tonumber(value) or nil
        if days == nil or days ~= days or days == math.huge or days == -math.huge then return false end
        if category == "perishable" then return days ~= 1000000000 end
        return days == 1000000000
    end
    if category == "canned" then
        return safeBoolean(item, "hasTag", ItemTag ~= nil and ItemTag.PRESERVED_FOOD or nil) == true
    end
    if category == "food" then
        return KnoxSurvivorNeeds.isSafeFood(item)
    end
    if category == "water" then
        return KnoxSurvivorNeeds.isWaterItem(item, false)
    end
    if category == "medical" then
        return (item.isCanBandage ~= nil and item:isCanBandage())
            or MEDICAL_TYPES[full] == true
            or displayCategory(item) == "Medical"
    end
    if category == "weapons" then
        return item.IsWeapon ~= nil and item:IsWeapon()
            or displayCategory(item) == "Weapon"
    end
    if category == "ammunition" then
        return (rawget(_G, "ItemTag") ~= nil and ItemTag.AMMO ~= nil
                and safeBoolean(item, "hasTag", ItemTag.AMMO) == true)
            or hasPrefix(full, "Base.Bullets")
            or hasPrefix(full, "Base.ShotgunShells")
            or displayCategory(item) == "Ammo"
    end
    if category == "tools" then
        return TOOL_TYPES[full] == true
            or displayCategory(item) == "Tool"
    end
    if category == "building" then
        -- A fuel can reports VehicleMaintenance, which is also the native
        -- category for bulky vehicle parts. Fuel owns its can before the
        -- broader materials rule can claim it.
        if isFuelItem(item, full) then return false end
        -- Native Build 42 vehicle parts (e.g. Base.NormalTire1 at 15.0,
        -- Base.CarBattery1 at 5.0) report DisplayCategory VehicleMaintenance
        -- with MechanicsItem set. They are bulky workshop materials for base
        -- and vehicle work, so the Materials shelf owns them; mechanic hand
        -- tools already resolve to Tools through TOOL_TYPES above.
        return BUILDING_TYPES[full] == true
            or displayCategory(item) == "Material"
            or displayCategory(item) == "VehicleMaintenance"
    end
    if category == "logs" then
        return LOG_TYPES[full] == true
    end
    if category == "farming" then
        return FARMING_TYPES[full] == true
            or hasPrefix(full, "Base.Seed")
            or hasPrefix(full, "Base.Fertilizer")
            or displayCategory(item) == "Gardening"
    end
    if category == "clothing" then
        return item.IsClothing ~= nil and item:IsClothing()
            or item.IsInventoryContainer ~= nil and item:IsInventoryContainer()
            or displayCategory(item) == "Clothing"
    end
    if category == "junk" then
        return displayCategory(item) == "Junk"
    end
    return false
end

function Storage.classifyItem(item)
    -- Hammers, axes, and screwdrivers are also native weapons. Classify their
    -- work role before the broad IsWeapon predicate so base stock and automatic
    -- deposits agree with the explicitly assigned Tools containers.
    if Storage.matchesCategory(item, "tools") then return "tools" end
    for _, category in ipairs(Storage.RESOURCE_CATEGORIES) do
        if Storage.matchesCategory(item, category) then
            return category
        end
    end
    return "other"
end

local function itemQuantity(item)
    if item ~= nil and item.getCount ~= nil then
        local success, count = pcall(item.getCount, item)
        if success and tonumber(count) ~= nil then
            return math.max(1, math.floor(tonumber(count)))
        end
    end
    return 1
end

local orderedPoliciesByDistance

-- Assigned storage may contain a bag, crate insert, or another native
-- inventory container. Walk those real nested containers without inventing
-- stock or counting the same ItemContainer twice if a malformed save loops
-- back to an already visited container.
local function walkContainerItems(container, visitor, seen, strict, allowContainer)
    if container == nil or type(visitor) ~= "function" then return false end
    if container.getItems == nil then return false end
    seen = seen or {}
    if seen[container] then return true end
    if allowContainer ~= nil then
        local ok, allowed = pcall(allowContainer, container)
        if not ok or allowed ~= true then return false end
    end
    seen[container] = true
    local items = container:getItems()
    if items == nil or items.size == nil or items.get == nil then return false end
    local count = items:size()
    if type(count) ~= "number" or count < 0 or count ~= math.floor(count) then return false end
    for index = 0, count - 1 do
        local item = items:get(index)
        if item == nil then
            if strict then return false end
        else
            visitor(item, container)
            local nested = false
            if item.IsInventoryContainer ~= nil then
                local ok, value = pcall(function() return item:IsInventoryContainer() end)
                if strict and (not ok or type(value) ~= "boolean") then return false end
                nested = ok and value == true
            end
            if nested then
                if item.getInventory == nil then
                    if strict then return false end
                else
                    local ok, inventory = pcall(function() return item:getInventory() end)
                    if strict and (not ok or inventory == nil) then return false end
                    if ok and inventory ~= nil then
                        local complete = walkContainerItems(inventory, visitor, seen, strict, allowContainer)
                        if strict and not complete then return false end
                    end
                end
            end
        end
    end
    return true
end

-- A floor bag and its contents are one identity-deduplicated read. The root
-- collector remains root-only for callers that need the world object itself.
local function walkLooseItemTree(rootItem, visitor, seenContainers, seenItems)
    local ok, complete = pcall(function()
        if rootItem == nil then return false end
        local function add(item)
            if not seenItems[item] then
                seenItems[item] = true
                visitor(item)
            end
        end
        add(rootItem)
        if rootItem.IsInventoryContainer ~= nil then
            local isBag = rootItem:IsInventoryContainer()
            if type(isBag) ~= "boolean" then return false end
            if isBag then
                if rootItem.getInventory == nil then return false end
                local inventory = rootItem:getInventory()
                if inventory == nil then return false end
                return walkContainerItems(inventory, add, seenContainers, true)
            end
        end
        return true
    end)
    return ok and complete == true
end

local function containerContains(container, item)
    if container == nil or item == nil then return false end
    local items = container.getItems ~= nil and container:getItems() or nil
    if items ~= nil and items.contains ~= nil then
        local ok, present = pcall(items.contains, items, item)
        if ok then return present == true end
    end
    if container.contains ~= nil then
        local ok, present = pcall(container.contains, container, item)
        return ok and present == true
    end
    return false
end

local function survivalKind(item)
    if KnoxSurvivorNeeds.isWaterItem(item, false) then return "water" end
    if KnoxSurvivorNeeds.isSafeFood(item) then return "food" end
    return nil
end

function Storage.countPersonalSurvivalSupplies(character)
    local counts = { food = 0, water = 0 }
    local inventory = character ~= nil and character.getInventory ~= nil
        and character:getInventory() or nil
    walkContainerItems(inventory, function(candidate)
        local kind = survivalKind(candidate)
        if kind ~= nil then
            counts[kind] = counts[kind] + itemQuantity(candidate)
        end
    end)
    return counts
end

-- Locate a real consumable in the base's assigned containers. This does not
-- use summaries or item factories: the returned instance is the same object
-- that will enter the survivor inventory and later serialized record.
function Storage.findSurvivalSupply(base, character, kind, options)
    if kind ~= "food" and kind ~= "water" then return nil, "invalid_kind" end
    local policies = options ~= nil and options.policies or orderedPoliciesByDistance(base, character)
    for pass = 1, 2 do
        for _, policy in ipairs(policies) do
            local selectedPolicy = options ~= nil and options.policy or nil
            local matchesPolicy = selectedPolicy == nil or policy == selectedPolicy
                or (policy.key ~= nil and policy.key == selectedPolicy.key
                    and policy.transientContainer == selectedPolicy.transientContainer
                    and (policy.transientContainer ~= true
                        or policy.container == selectedPolicy.container))
            local filtered = Storage.hasActiveFilters(policy)
            if matchesPolicy and ((pass == 1 and filtered) or (pass == 2 and not filtered)) then
                local resolved = Storage.resolvePolicy(policy)
                if resolved ~= nil then
                    local found = nil
                    walkContainerItems(resolved.container, function(candidate, sourceContainer)
                        if found ~= nil then return end
                        local function eligible()
                            return (options ~= nil and kind == "food"
                                    and KnoxSurvivorNeeds.isSafeFood(candidate)
                                or (options == nil or kind ~= "food") and survivalKind(candidate) == kind)
                                and Storage.filterAllowsItem(policy, candidate)
                                and (options == nil or options.acceptItem == nil
                                    or options.acceptItem(candidate, sourceContainer, resolved) == true)
                        end
                        local ok, accepted
                        if options ~= nil then ok, accepted = pcall(eligible)
                        else ok, accepted = true, eligible() end
                        if ok and accepted then
                            found = { kind = kind, item = candidate,
                                source = sourceContainer, policy = policy }
                        end
                    end, nil, false, options ~= nil and options.acceptContainer or nil)
                    if found ~= nil then return found, "found" end
                end
            end
        end
    end
    return nil, "assigned_" .. kind .. "_unavailable"
end

local function transferSupplyInstance(character, transfer)
    local inventory = character ~= nil and character.getInventory ~= nil
        and character:getInventory() or nil
    local source = transfer ~= nil and transfer.source or nil
    local item = transfer ~= nil and transfer.item or nil
    if inventory == nil or source == nil or item == nil then
        return false, "missing_transfer_state"
    end
    if source == inventory or containerContains(inventory, item) then
        return true, "already_carried"
    end
    if not containerContains(source, item) then return false, "source_changed" end
    if inventory.hasRoomFor ~= nil then
        local roomOk, hasRoom = pcall(inventory.hasRoomFor, inventory, character, item)
        if roomOk and hasRoom ~= true then return false, "inventory_full" end
    end
    local movedOk, moveResult = pcall(inventory.AddItem, inventory, item)
    if movedOk and moveResult ~= false and containerContains(inventory, item)
        and not containerContains(source, item) then
        return true, "transferred"
    end
    -- AddItem(instance) normally detaches atomically. If a modded container
    -- moved the item but failed verification, restore the original owner.
    if not containerContains(source, item) and source.AddItem ~= nil then
        pcall(source.AddItem, source, item)
    end
    return false, "transfer_failed=" .. tostring(moveResult)
end

-- Hibernation converts a bounded amount of real loaded base stock into carried
-- stock before the body is serialized. Offscreen survival then consumes only
-- that record, so there is one economy and no deferred world-container debt.
function Storage.provisionSurvivalSupplies(base, character, targets)
    targets = type(targets) == "table" and targets or {}
    local desired = {
        food = math.max(0, math.floor(tonumber(targets.food) or 0)),
        water = math.max(0, math.floor(tonumber(targets.water) or 0)),
    }
    local counts = Storage.countPersonalSurvivalSupplies(character)
    local report = {
        before = { food = counts.food, water = counts.water },
        after = counts,
        transferred = { food = 0, water = 0 },
        shortages = {},
    }
    for _, kind in ipairs({ "water", "food" }) do
        local attempts = 0
        while counts[kind] < desired[kind] and attempts < 8 do
            attempts = attempts + 1
            local transfer, result = Storage.findSurvivalSupply(base, character, kind)
            if transfer == nil then
                report.shortages[kind] = result
                break
            end
            local quantity = itemQuantity(transfer.item)
            local moved, moveResult = transferSupplyInstance(character, transfer)
            if not moved then
                report.shortages[kind] = moveResult
                break
            end
            -- Native item provenance survives the existing inventory snapshot.
            -- Mark only an exact completed withdrawal from assigned communal
            -- storage; carried personal food is never retroactively communal.
            if type(base.id) == "string" and transfer.item.getModData ~= nil then
                local ok, data = pcall(function() return transfer.item:getModData() end)
                if ok and data ~= nil then data.KnoxBaseProvision = base.id end
            end
            counts[kind] = counts[kind] + quantity
            report.transferred[kind] = report.transferred[kind] + quantity
        end
        if counts[kind] < desired[kind] and report.shortages[kind] == nil then
            report.shortages[kind] = "bounded_provision_limit"
        end
    end
    report.after = { food = counts.food, water = counts.water }
    return true, report
end

local function emptyResourceTotals()
    local totals = { other = 0 }
    for _, category in ipairs(Storage.RESOURCE_CATEGORIES) do
        totals[category] = 0
    end
    return totals
end

-- Every resident's decision pass asks the same settlement for its stock, and a
-- full walk of each assigned container and its nested bags is not free. The
-- snapshot is read-only for every caller, so a short window can serve all of
-- them; a miss still returns the honest per-call result. The key carries the
-- policy count so assigning or removing a container is never served stale, and
-- callers receive a copy so nobody can poison the stored snapshot.
local summarizeCache = {}
local SUMMARIZE_CACHE_MS = 2000
local SUMMARIZE_CACHE_ENTRIES = 16

local function copySummary(summary)
    local totals = {}
    for category, quantity in pairs(summary.totals or {}) do
        totals[category] = quantity
    end
    local floorTotals = {}
    for category, quantity in pairs(summary.floorTotals or {}) do
        floorTotals[category] = quantity
    end
    return {
        totals = totals,
        floorTotals = floorTotals,
        floorSquares = summary.floorSquares,
        loadedPolicies = summary.loadedPolicies,
        unavailablePolicies = summary.unavailablePolicies,
        misplacedItems = summary.misplacedItems,
    }
end

local function summarizeCacheKey(base)
    if type(base) ~= "table" or base.id == nil then return nil end
    local count = 0
    for _ in pairs(base.storage or {}) do count = count + 1 end
    return tostring(base.id) .. ":" .. tostring(count)
end

-- FLOOR STOCK (read-only)
-- Loose items on the floor of the assigned storage area are real stock: a
-- resident can pick them up, and a base that says it has no nails while a pile
-- sits two tiles away is lying to the player. They are not a shelf, though. The
-- base files nothing there, nothing is deposited there, and a category with no
-- assigned container still reads as unassigned. The summary keeps the two
-- apart for exactly that reason; the planner decides where they add up.
-- One native collection seam. A missing/malformed read is never an empty floor.
local function squareLooseItems(square)
    if square==nil then return {},false end
    local ok,items=pcall(function()
        local objects=square:getWorldObjects()
        local count=objects:size()
        if type(count)~="number" or count<0 or count>4096 or count~=math.floor(count) then return nil end
        local result={}
        for index=0,count-1 do
            local object=objects:get(index)
            if object==nil then return nil end
            local item=object:getItem()
            if item==nil then return nil end
            result[#result+1]=item
        end
        return result
    end)
    if not ok or items==nil then return {},false end
    return items,true
end
Storage.collectSquareLooseItems=squareLooseItems

-- Exported: the same floor read this owner counts for its summary, pointed at a
-- home's own squares. `visitor(item)` sees each root and nested bag item once.
-- Returns true only when every square and nested inventory in the area
-- was readable, so a caller can tell unknown from a readable empty floor. An
-- area larger than the bounded footprint is not read: unknown, not smaller.
function Storage.walkFloorItems(base, visitor)
    if base == nil or type(visitor) ~= "function" then return false end
    local area = storageArea(base)
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil or cell.getGridSquare == nil then return false end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local maxX = tonumber(area.maxX) or (minX and minX + (tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY and minY + (tonumber(area.height) or 1) - 1)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return false end
    if (maxX - minX + 1) * (maxY - minY + 1) > 4096 then return false end
    local z = tonumber(area.z) or tonumber(base.home ~= nil and base.home.z) or 0
    local readable = true
    local seenContainers, seenItems = {}, {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            if square == nil then
                readable = false
            else
                local loose,known = squareLooseItems(square)
                if not known then readable=false
                else
                    for index = 1, #loose do
                        if not walkLooseItemTree(loose[index], visitor, seenContainers, seenItems) then readable = false end
                    end
                end
            end
        end
    end
    return readable
end

function Storage.floorStock(base)
    local result = { totals = {}, squares = 0, loaded = false }
    local area = storageArea(base)
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil or cell.getGridSquare == nil or base == nil then
        return result
    end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local maxX = tonumber(area.maxX) or (minX and minX + (tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY and minY + (tonumber(area.height) or 1) - 1)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return result end
    local z = tonumber(area.z) or tonumber(base.home ~= nil and base.home.z) or 0
    local seenContainers, seenItems = {}, {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local loose,known = squareLooseItems(square)
            if not known then result.unreadable=(result.unreadable or 0)+1 end
            if known then result.loaded=true end
            if known and #loose > 0 then
                result.squares = result.squares + 1
                result.loaded = true
                local function add(item)
                    if item == nil then return end
                    local category = Storage.classifyItem(item)
                    result.totals[category] = (result.totals[category] or 0)
                        + itemQuantity(item)
                end
                for index = 1, #loose do
                    if not walkLooseItemTree(loose[index], add, seenContainers, seenItems) then
                        result.unreadable = (result.unreadable or 0) + 1
                    end
                end
            end
        end
    end
    return result
end

-- Returns an honest snapshot of assigned storage that is currently available in
-- the loaded cell.  Unloaded/missing containers are reported separately rather
-- than assumed empty or treated as an abstract stockpile.
-- Exported so other owners measure real stock through this single traversal,
-- nested-container and identity dedup included, instead of writing a second one.
Storage.walkItems = walkContainerItems

function Storage.summarize(base)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
    local key = now ~= nil and summarizeCacheKey(base) or nil
    if key ~= nil then
        local cached = summarizeCache[key]
        if cached ~= nil and now - cached.at < SUMMARIZE_CACHE_MS then
            return copySummary(cached.summary)
        end
    end
    local floor = Storage.floorStock(base)
    local summary = {
        totals = emptyResourceTotals(),
        -- Reported, never merged: the player must be able to see that a
        -- category is standing on the floor instead of on a shelf.
        floorTotals = floor.totals,
        floorSquares = floor.squares,
        loadedPolicies = 0,
        unavailablePolicies = 0,
        misplacedItems = 0,
    }
    for _, policy in ipairs(Storage.policies(base)) do
        local resolved = Storage.resolvePolicy(policy)
        if resolved == nil then
            summary.unavailablePolicies = summary.unavailablePolicies + 1
        else
            summary.loadedPolicies = summary.loadedPolicies + 1
            walkContainerItems(resolved.container, function(item)
                local category = Storage.classifyItem(item)
                local quantity = itemQuantity(item)
                if Storage.acceptsDeposit(policy, item) then
                    summary.totals[category] = (summary.totals[category] or 0) + quantity
                else
                    summary.misplacedItems = summary.misplacedItems + quantity
                end
            end)
        end
    end
    if key ~= nil then
        local entries = 0
        for _ in pairs(summarizeCache) do entries = entries + 1 end
        if entries >= SUMMARIZE_CACHE_ENTRIES then summarizeCache = {} end
        summarizeCache[key] = { at = now, summary = copySummary(summary) }
    end
    return summary
end

-- Read-only native eligibility, shared by deposit discovery and organizing.
-- Filters and exact transfer receipts remain separate caller-owned checks.
function Storage.canReceiveItem(container, character, item)
    if container == nil or character == nil or item == nil then
        return false, "storage_unavailable"
    end
    -- Real native capacity: assigned storage fills like any Project Zomboid
    -- container, and deposits overflow to the next-best shelf through the
    -- ranked candidates above. Full shelves reject; nothing is lost, the
    -- item stays carried until room exists.
    if container.hasRoomFor ~= nil then
        local success, result = pcall(function()
            return container:hasRoomFor(character, item)
        end)
        if not success then return false, "storage_unavailable" end
        if result ~= true then return false, "storage_full" end
        if safeBoolean(container, "isItemAllowed", item) ~= true then
            return false, "storage_item_disallowed"
        end
        return true
    end
    return false, "storage_unavailable"
end

function Storage.depositBlockerText(reason)
    local labels = {
        no_owned_storage = "I need a home storage destination for these supplies.",
        no_reachable_storage = "There's no storage close enough for these supplies.",
        no_matching_storage = "The storage filters don't allow these supplies.",
        storage_unavailable = "The matching storage isn't available right now.",
        storage_full = "The matching storage is full. I'll keep carrying the supplies.",
        storage_item_disallowed = "Those containers can't hold these supplies.",
        storage_inaccessible = "I can't reach the matching storage.",
        storage_retry_cooldown = "The storage route was blocked. I'll try again later.",
    }
    return labels[reason] or labels.no_reachable_storage
end

-- Short nominative wording for the same failures, shared by panels that list
-- a settlement's open problems instead of speaking in the resident's voice.
local DEPOSIT_PROBLEM_LABELS = {
    no_owned_storage = "the settlement has no storage set up",
    no_reachable_storage = "no storage is close enough",
    no_matching_storage = "no storage filter allows these supplies",
    storage_unavailable = "the matching storage is not available",
    storage_full = "the permitted storage is full",
    storage_item_disallowed = "those containers cannot hold these items",
    storage_inaccessible = "the matching storage cannot be reached",
    storage_retry_cooldown = "the storage route is blocked",
}

function Storage.depositProblemLabel(reason)
    return DEPOSIT_PROBLEM_LABELS[tostring(reason or "")]
        or DEPOSIT_PROBLEM_LABELS.storage_unavailable
end

-- Cleanup deposits never target arbitrary nearby homes or foreign storage.
-- Destination classes whose stores are deliberately kept to their own stock.
-- Food, water and medicine never become a dumping ground for something the
-- player filed elsewhere; the kitchen and the medicine cabinet stay clean.
local CONSUMABLE_STORAGE_ROLES = {
    food = true, water = true, medical = true,
    canned = true, perishable = true, nonperishable = true,
}

-- Matching filters precede fallback storage (D-037). Within a preference tier
-- use configured priority, then live distance; discovery never proves receipt.
-- Preserve policy priority; cold preference breaks ties before distance.
local function depositOrder(a, b)
    if a.preference ~= b.preference then return a.preference < b.preference end
    if a.priorityRank ~= b.priorityRank then return a.priorityRank < b.priorityRank end
    if (a.coldRank or 1) ~= (b.coldRank or 1) then return (a.coldRank or 1) < (b.coldRank or 1) end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.policy.key < b.policy.key
end

-- Cold-storage preference asks for isFrozen()/isRotten(). The installed
-- zombie.inventory.InventoryItem has hasTag and IsRotten only; isFrozen() and
-- isRotten() live on zombie.inventory.types.Food. Calling them on a plain item
-- threw once per item on every cleanup, which is what buried the log in stack
-- dumps while the preference itself never engaged. safeBoolean() reads the
-- method before calling it, the same way deposit filters already do.
function Storage.isColdPerishable(item)
    if item == nil then return false, nil end
    local tag = ItemTag ~= nil and ItemTag.PRESERVED_FOOD or nil
    -- A false hasTag() result must stay false: `false or nil` would turn it
    -- back into nil and quietly disable the whole cold-storage preference.
    local preserved = nil
    if tag ~= nil then preserved = safeBoolean(item, "hasTag", tag) end
    local frozen = safeBoolean(item, "isFrozen")
    local rotten = safeBoolean(item, "isRotten")
    if preserved == false and rotten == false and type(frozen) == "boolean"
        and Storage.matchesCategory(item, "perishable") then
        return true, frozen
    end
    return false, nil
end

-- The caller supplies only this survivor's canonical assigned/owned base.
local function findDeposit(base, character, item, trip, excluded, ticks, policyKey)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if base == nil or origin == nil then return nil, "no_owned_storage" end
    local candidates, capacityFallbacks = {}, {}
    local coldFood, frozen = Storage.isColdPerishable(item)
    -- A pinned lookup revalidates a decision another owner already made (the
    -- planned shelf for a deposit trip), so it is not a new discovery.
    local pinned = policyKey ~= nil
    local failure, failureRank = "no_reachable_storage", 0
    local function blocked(reason, rank)
        -- Prefer the explanation from the furthest validated candidate,
        -- independent of container discovery order.
        if rank > failureRank then failure, failureRank = reason, rank end
    end
    for _, policy in ipairs(Storage.operationalPolicies(base)) do
        local dx, dy = (tonumber(policy.x) or math.huge) - origin:getX(),
            (tonumber(policy.y) or math.huge) - origin:getY()
        local floorDifference = math.abs((tonumber(policy.z) or math.huge) - origin:getZ())
        -- Typed stores stay authoritative, but anything assigned with room
        -- works as overflow: a surplus the settlement cannot shelve anywhere
        -- just bounces between pockets and cleanup forever. Consumable stores
        -- stay reserved for their own stock.
        local role = tostring(policy.storageRole or policy.category or "")
        local unassigned = policy.transientContainer == true
        local exact = not unassigned and Storage.acceptsDeposit(policy, item)
        local overflow = not unassigned and not exact and policy.storageFilterVersion ~= 1
            and not CONSUMABLE_STORAGE_ROLES[role]
        local lastResort = not unassigned and not exact and not overflow
            and policy.storageFilterVersion ~= 1
        -- Every policy the game saves carries its own filter list, so the two
        -- literal tiers above cannot apply to one. Capacity overflow is the
        -- case that actually happens: the shelves that name this category are
        -- full, and an assigned shelf that names a different one still has
        -- room. Filing a haul there beats carrying it forever, so long as the
        -- real cause was capacity and not a filter refusal or a wall.
        local capacityFallback = not unassigned and not exact
            and not CONSUMABLE_STORAGE_ROLES[role]
        if (floorDifference == 0 or (trip and floorDifference <= 2))
            and dx * dx + dy * dy <= (trip and 128 * 128 or 2)
            and (policyKey == nil or policy.key == policyKey) then
            if not (exact or overflow or lastResort or unassigned or capacityFallback) then
                blocked("no_matching_storage", 1)
            elseif excluded ~= nil and (excluded[policy.key] or 0) > (ticks or 0) then
                -- A cooled-down overflow shelf must not rewrite the cause; the
                -- matching shelf that is full still owns the explanation.
                if not capacityFallback then blocked("storage_retry_cooldown", 6) end
            else
            local resolved = Storage.resolvePolicy(policy)
            local accepts, reason = false, "storage_unavailable"
            if resolved ~= nil then
                accepts, reason = Storage.canReceiveItem(resolved.container, character, item)
            end
            if not accepts then
                -- Only a destination that would otherwise have matched owns the
                -- reported cause; a rejected overflow candidate never hides it.
                if not capacityFallback then
                    blocked(reason, reason == "storage_full" and 4
                        or reason == "storage_item_disallowed" and 3 or 2)
                end
            else
                -- Native transfer validity does not itself reject every wall
                -- between two containers. Require a clear adjacent interaction.
                local approach = trip and AdjacentFreeTileFinder.Find(resolved.square, character) or origin
                local clear = approach ~= nil and approach:getZ() == resolved.square:getZ()
                    and (approach:getX() - resolved.square:getX()) ^ 2
                        + (approach:getY() - resolved.square:getY()) ^ 2 <= 2
                    and (approach == resolved.square or (approach.isSomethingTo ~= nil
                        and not approach:isSomethingTo(resolved.square)))
                if clear then
                    resolved.approach = approach
                    -- Use live square coords for closest-relative sorting so a
                    -- moved/replaced container does not win on stale ModData.
                    local rdx = resolved.square:getX() - origin:getX()
                    local rdy = resolved.square:getY() - origin:getY()
                    resolved.distance = rdx * rdx + rdy * rdy
                    resolved.priorityRank = Storage.priorityRank(policy)
                    local cold = nil
                    if coldFood and exact and role == "food" then
                        cold = Storage.coldContainer(resolved.container)
                    end
                    if capacityFallback and not pinned then
                        -- Held back until every matching shelf has refused.
                        resolved.preference = 3
                        resolved.overflow = true
                        capacityFallbacks[#capacityFallbacks + 1] = resolved
                        -- Reaching here means filters alone hold the item back
                        -- when no matching shelf is full, which is the honest
                        -- reason to report in that case.
                        blocked("no_matching_storage", 1)
                    else
                        local classified = Storage.classifyItem(item)
                        local exactCategory = policy.storageFilterVersion == 1
                            and exact or policy.storageRole == classified
                            or (policy.storageRole == "food" and Storage.acceptsDeposit(policy, item))
                        resolved.preference = unassigned and 4
                            or exactCategory and 0
                            or policy.storageRole == "supplies" and 1
                            or exact and 2
                            or overflow and 3 or 4
                        resolved.overflow = capacityFallback or nil
                        if cold ~= nil and cold.powered and cold.electricity
                            and ((not frozen and cold.fridge and not cold.freezer) or (frozen and cold.freezer)) then
                            resolved.coldRank = 0
                        end
                        candidates[#candidates + 1] = resolved
                    end
                elseif not capacityFallback then
                    blocked("storage_inaccessible", 5)
                end
            end
            end
        end
    end
    table.sort(candidates, depositOrder)
    local best = candidates[1]
    -- Overflow only answers a full shelf, and only outranks the existing
    -- discovered-container stopgap (preference 4). A filter refusal, an
    -- unreachable container or a cooldown is a different problem with a
    -- different fix and never justifies overflow.
    if failure == "storage_full" and capacityFallbacks[1] ~= nil
        and (best == nil or best.preference > 3) then
        table.sort(capacityFallbacks, depositOrder)
        return capacityFallbacks[1], "nearby_storage"
    end
    return best, best ~= nil and "nearby_storage" or failure
end

function Storage.findNearbyDeposit(base, character, item, policyKey, excluded, ticks)
    return findDeposit(base, character, item, false, excluded, ticks, policyKey)
end

-- Only loaded owned containers within a practical local trip. The native
-- adjacent-square finder picks the interaction side; existing movement owns routing.
function Storage.findDepositTrip(base, character, item, excluded, ticks)
    return findDeposit(base, character, item, true, excluded, ticks)
end

local function sourceForItem(resolved, sourceContainer)
    if resolved == nil or sourceContainer == nil then return nil end
    return {
        policy = resolved.policy,
        square = resolved.square,
        object = resolved.object,
        container = sourceContainer,
    }
end

-- Withdrawal follows actual contents, including a misplaced tool in a fridge.
-- Never fabricate an item from its type: native food/fluid methods need a real item.
local function policyCanSupply(policy)
    return policy ~= nil
end

-- Multiple same-category storages must use the closest relative option.
-- Sorts assigned policies by distance to the worker so withdrawals favor near
-- containers instead of key order.
-- The player's fill order comes first, then live distance, then key. A base
-- whose shelves carry no order at all ties on rank and falls back to distance,
-- exactly as it sorted before the order key existed.
function Storage.sortByPriorityAndDistance(policies, character)
    local list = policies or {}
    local origin = character ~= nil and character.getCurrentSquare ~= nil
        and character:getCurrentSquare() or nil
    if origin == nil then return list end
    local ox, oy, oz = origin:getX(), origin:getY(), origin:getZ()
    table.sort(list, function(a, b)
        local ar, br = Storage.priorityRank(a), Storage.priorityRank(b)
        if ar ~= br then return ar < br end
        local adx = (tonumber(a.x) or ox) - ox
        local ady = (tonumber(a.y) or oy) - oy
        local adz = math.abs((tonumber(a.z) or oz) - oz) * 4
        local bdx = (tonumber(b.x) or ox) - ox
        local bdy = (tonumber(b.y) or oy) - oy
        local bdz = math.abs((tonumber(b.z) or oz) - oz) * 4
        local da = adx * adx + ady * ady + adz * adz
        local db = bdx * bdx + bdy * bdy + bdz * bdz
        if da ~= db then return da < db end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

orderedPoliciesByDistance = function(base, character)
    return Storage.sortByPriorityAndDistance(
        Storage.operationalPolicies(base), character)
end
Storage.orderedPoliciesByDistance = orderedPoliciesByDistance

-- Finds one real item needed by a claimed base task.  It deliberately searches
-- only assigned base storage and returns one transfer at a time, allowing the
-- normal timed-action queue to remain the sole owner of the inventory change.
-- Set skipIgnoreCheck to run the real inventory-vs-storage comparison even
-- when IgnoreJobResourceRequirements is on: gating is bypassed, but fetching
-- real items is not, because native job actions need carried items.
local function findRequiredTransferReal(base, character, requirements)
    local inventory = character ~= nil and character:getInventory() or nil
    local requiredItems = requirements ~= nil and requirements.items or {}
    for itemType, required in pairs(requiredItems) do
        local needed = math.max(0, math.floor(tonumber(required) or 0))
        if needed > KnoxBaseSupplyPlanner.inventoryCount(inventory, itemType, requirements) then
            local policies = orderedPoliciesByDistance(base, character)
            for pass = 1, 2 do
                for _, policy in ipairs(policies) do
                    local filtered = Storage.hasActiveFilters(policy)
                    if (pass == 1 and filtered) or (pass == 2 and not filtered) then
                        if policyCanSupply(policy, tostring(itemType)) then
                            local resolved = Storage.resolvePolicy(policy)
                            if resolved ~= nil then
                                local found = nil
                                walkContainerItems(resolved.container, function(item, sourceContainer)
                                    if found == nil and fullType(item) == tostring(itemType)
                                        and Storage.filterAllowsItem(policy, item)
                                        and KnoxBaseSupplyPlanner.matchesRequirement(item, requirements) then
                                        found = {
                                            sourcePolicy = policy,
                                            source = sourceForItem(resolved, sourceContainer),
                                            item = item,
                                            itemType = tostring(itemType),
                                            required = needed,
                                        }
                                    end
                                end)
                                if found ~= nil then return found, "found" end
                            end
                        end
                    end
                end
            end
            return nil, "missing_assigned_item=" .. tostring(itemType)
        end
    end
    return nil, "requirements_ready"
end

function Storage.findRequiredTransfer(base, character, requirements)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() then
        return nil, "requirements_ready"
    end
    return findRequiredTransferReal(base, character, requirements)
end

-- Recheck a selected cupboard at the native transfer boundary. Policy removal,
-- changed filters and moving a bag out of the cupboard revoke the old pickup.
-- This visits configured policies and the selected container only, never a
-- fresh scan of every square in the base on each timed-action validity check.
function Storage.taskSupplyStillAvailable(base, transfer)
    if base == nil or transfer == nil or transfer.sourcePolicy == nil then return false end
    local selected, current, resolved = transfer.sourcePolicy, nil, nil
    local original = Storage.resolvePolicy(selected, true)
    if original == nil then return false end
    for _, policy in ipairs(Storage.policies(base)) do
        if policy.key == selected.key then
            current, resolved = policy, Storage.resolvePolicy(policy, true)
            break
        elseif selected.transientContainer == true then
            local candidate = Storage.resolvePolicy(policy, true)
            if candidate ~= nil and candidate.container == original.container then
                current, resolved = policy, candidate
                break
            end
        end
    end
    if current == nil and selected.transientContainer == true and selected.base == base then
        current, resolved = selected, original
    end
    if current == nil or resolved == nil or resolved.container ~= original.container
        or not Storage.filterAllowsItem(current, transfer.item) then return false end
    local source = transfer.source ~= nil and transfer.source.container or nil
    if source == nil or transfer.item:getContainer() ~= source
        or source:contains(transfer.item) ~= true then return false end
    -- Follow only the selected bag's ancestry. Scanning every nested item on
    -- every native validity call would make a large pantry needlessly costly.
    local seen = {}
    while source ~= resolved.container do
        if seen[source] then return false end
        seen[source] = true
        local bag = source:getContainingItem()
        if bag == nil or bag:getInventory() ~= source then return false end
        local parent = bag:getContainer()
        if parent == nil or parent:contains(bag) ~= true then return false end
        source = parent
    end
    return true
end

-- Real inventory-vs-storage comparison that ignores the ignore-resources
-- sandbox flag. Lets workers fetch what is actually stored even when gating
-- is bypassed; native job actions still need carried items.
function Storage.findFetchTransfer(base, character, requirements)
    return findRequiredTransferReal(base, character, requirements)
end

-- Walk assigned stock once for role-kit candidates. The visitor returns true
-- to stop the scan. Favourites, settlement delivery cargo and filtered items
-- are never eligible; no item is reserved or moved here.
local function scanRoleKitCandidates(base, character, tags, matcher, available, visit)
    if base == nil or character == nil or type(tags) ~= "table"
        or type(matcher) ~= "function" or type(visit) ~= "function" then
        return false
    end
    for _, policy in ipairs(orderedPoliciesByDistance(base, character)) do
        local resolved = Storage.resolvePolicy(policy)
        if resolved ~= nil then
            local stopped = false
            walkContainerItems(resolved.container, function(item, sourceContainer)
                if stopped or item == nil then return end
                if safeBoolean(item, "isFavorite") == true then return end
                local dataOk, data = pcall(function() return item:getModData() end)
                if dataOk and data ~= nil and data.KnoxBaseSupplyDelivery ~= nil then return end
                for _, tag in ipairs(tags) do
                    local matches = false
                    local ok, result = pcall(matcher, tag, item)
                    if ok then matches = result == true end
                    if matches and Storage.filterAllowsItem(policy, item)
                        and (available == nil or available(tag, item) == true) then
                        local candidate = {
                            tag = tag, item = item,
                            source = sourceForItem(resolved, sourceContainer),
                            sourcePolicy = policy,
                        }
                        if visit(candidate) == true then stopped = true end
                        if stopped then return end
                    end
                end
            end)
            if stopped then return true end
        end
    end
    return false
end

-- Find one real item for a role-kit tag. The caller owns the decision to
-- withdraw and the native timed action; this function only resolves an
-- assigned container and returns its exact instance.
function Storage.findRoleKitTransfer(base, character, tags, matcher, available)
    if base == nil or character == nil or type(tags) ~= "table"
        or type(matcher) ~= "function" then return nil, "role_kit_unavailable" end
    local found = nil
    scanRoleKitCandidates(base, character, tags, matcher, available, function(candidate)
        found = candidate
        return true
    end)
    if found ~= nil then return found, "found" end
    return nil, "role_kit_stock_unavailable"
end

-- Read-only role-kit stock for the Crew detail line. The first eligible item
-- for each missing tag is enough to say the shelf can replace it; this never
-- reserves or removes that item.
function Storage.roleKitStock(base, character, tags, matcher, available)
    local stock, pending, count = {}, {}, 0
    if type(tags) ~= "table" then return stock end
    for _, tag in ipairs(tags) do
        if type(tag) == "string" and stock[tag] == nil and not pending[tag] then
            pending[tag] = true
            count = count + 1
        end
    end
    if count == 0 then return stock end
    local remaining = count
    scanRoleKitCandidates(base, character, tags, matcher, available, function(candidate)
        if stock[candidate.tag] == nil then
            stock[candidate.tag] = candidate.item
            remaining = remaining - 1
        end
        return remaining <= 0
    end)
    return stock
end

-- Base-wide, read-only role-kit readiness. The caller supplies the roster
-- rows and the equipment/storage owners supply every fact; this helper only
-- resolves each preference and groups the real missing tags. It never
-- reserves, withdraws or moves an item.
function Storage.roleKitShortages(base, residents, available)
    local result = {}
    if base == nil then return result end
    local equipment = rawget(_G, "KnoxEquipmentIntelligence")
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if equipment == nil or catalog == nil
        or equipment.roleKitMissing == nil or catalog.roleForPreference == nil
        or catalog.roleGear == nil then return result end
    for _, resident in ipairs(type(residents) == "table" and residents or {}) do
        if type(resident) == "table" and resident.id ~= nil then
            local role = resident.role
            if role == nil and resident.preference ~= nil then
                role = catalog.roleForPreference(resident.preference)
            elseif role ~= nil then
                role = catalog.roleForPreference(role)
            end
            local gear = role ~= nil and catalog.roleGear(role) or nil
            local entry = { id = resident.id, role = role, status = "unknown",
                missing = {}, stock = {}, gear = gear }
            if role == nil or type(gear) ~= "table" or #gear == 0 then
                entry.status = "no_role"
            elseif not resident.character then
                entry.status = "unknown"
            else
                local missing = equipment.roleKitMissing(
                    resident.character, gear, available)
                if type(missing) ~= "table" then
                    entry.status = "unknown"
                elseif #missing == 0 then
                    entry.status = "ready"
                else
                    entry.status = "shortage"
                    entry.missing = missing
                    if equipment.roleKitMatches ~= nil and Storage.roleKitStock ~= nil then
                        entry.stock = Storage.roleKitStock(base, resident.character,
                            missing, equipment.roleKitMatches, available)
                    end
                end
            end
            result[#result + 1] = entry
        end
    end
    return result
end

-- Discovery may inspect loaded base containers to name a concrete requirement.
-- The normal transfer action still owns moving the selected item to the resident.
-- Uses closest-relative ordering so multiple storages do not cause cross-base walks.
function Storage.findItemType(base, predicate, character)
    if type(predicate) ~= "function" then return nil end
    local policies = orderedPoliciesByDistance(base, character)
    for pass = 1, 2 do
        for _, policy in ipairs(policies) do
            local filtered = Storage.hasActiveFilters(policy)
            if (pass == 1 and filtered) or (pass == 2 and not filtered) then
                local resolved = Storage.resolvePolicy(policy)
                local found = nil
                walkContainerItems(resolved ~= nil and resolved.container or nil, function(item)
                    if found == nil then
                        local success, matches = pcall(predicate, item)
                        if success and matches == true and Storage.filterAllowsItem(policy, item) then
                            found = item
                        end
                    end
                end)
                if found ~= nil then
                    return fullType(found), found
                end
            end
        end
    end
    return nil
end

-- Counts a real exact item already in operational assigned storage, honoring
-- the same policy filters used by task transfers. Used only to describe shared
-- job demand before a real world search; it never moves or creates stock.
function Storage.countAssignedItem(base, itemType, requirements)
    local count = 0
    for _, policy in ipairs(Storage.operationalPolicies(base)) do
        if policyCanSupply(policy, tostring(itemType)) then
            local resolved = Storage.resolvePolicy(policy)
            if resolved ~= nil then
                walkContainerItems(resolved.container, function(item)
                    if fullType(item) == tostring(itemType)
                        and Storage.filterAllowsItem(policy, item)
                        and KnoxBaseSupplyPlanner.matchesRequirement(item, requirements) then
                        count = count + itemQuantity(item)
                    end
                end)
            end
        end
    end
    return count
end

-- On-hand count for one player-named item minimum. Same assigned shelves,
-- same policy filters and the same intact-item rule as countAssignedItem, so
-- the number a player reads in Stores is the number the supply run works to.
function Storage.goalItemCount(base, fullType)
    if base == nil then return 0 end
    -- The planner owns the key shape; without it there is no rule to read and
    -- no count to report, so this never invents one.
    local planner = rawget(_G, "KnoxBaseSupplyPlanner")
    local key = planner ~= nil and planner.itemTargetKey ~= nil
        and planner.itemTargetKey(tostring(fullType)) or nil
    if key == nil then return 0 end
    return Storage.countAssignedItem(base, fullType, { items = { [fullType] = 1 } })
end

function Storage.requirementsAvailable(base, character, requirements)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() then
        return true, "requirements_disabled"
    end
    local inventory = character ~= nil and character:getInventory() or nil
    local requiredItems = requirements ~= nil and requirements.items or {}
    for itemType, required in pairs(requiredItems) do
        local remaining = math.max(0, math.floor(tonumber(required) or 0))
            - KnoxBaseSupplyPlanner.inventoryCount(inventory, itemType, requirements)
        if remaining > 0 then
            for _, policy in ipairs(orderedPoliciesByDistance(base, character)) do
                if policyCanSupply(policy, tostring(itemType)) then
                    local resolved = Storage.resolvePolicy(policy)
                    if resolved ~= nil then
                        walkContainerItems(resolved.container, function(item)
                            if remaining <= 0 then return end
                            if fullType(item) == tostring(itemType)
                                and Storage.filterAllowsItem(policy, item)
                                and KnoxBaseSupplyPlanner.matchesRequirement(item, requirements) then
                                remaining = remaining - itemQuantity(item)
                            end
                        end)
                    end
                end
                if remaining <= 0 then break end
            end
        end
        if remaining > 0 then
            return false, "missing_assigned_item=" .. tostring(itemType)
        end
    end
    return true, "available"
end

function Storage.approachSquare(transfer, character)
    local square = transfer ~= nil and transfer.source ~= nil and transfer.source.square or nil
    if square == nil then return nil end
    local approach = AdjacentFreeTileFinder ~= nil
        and AdjacentFreeTileFinder.Find(square, character) or nil
    if approach ~= nil then return approach end
    return square.canStand ~= nil and square:canStand() and square or nil
end

-- Old saved task targets must fail closed, never resume container sorting.
function Storage.findTransfer(base) return nil, "sorting_retired" end
function Storage.transferTarget(transfer) return nil, "sorting_retired" end
function Storage.resolveTransfer(base, target) return nil, "sorting_retired" end

function Storage.queueTransfer(character, transfer, guard)
    if character == nil or transfer == nil then
        return nil, "missing_transfer"
    end
    local parent = transfer.source.container:getParent()
    if parent ~= nil then
        character:faceThisObject(parent)
        if character:shouldBeTurning() then
            return nil, "turning_to_storage"
        end
    end
    return KnoxInventoryActions.queueTransfer(
        character,
        transfer.item,
        transfer.source.container,
        transfer.destination.container,
        nil, guard
    )
end

-- ===== DEPOT AREA (the tile-drop yard) =====
-- A depot area uses the painted floor as a stockpile; no container is created.
-- The yard takes any item: the player's filter set says what the yard is for,
-- not what may be set down. Deliveries stop at the target or when the floor is
-- full, and bulky loads are the ones routed here first.
Storage.DEPOT_ZONE_TYPES = { log_processing = true }
Storage.DEPOT_LABEL = "Drop Point"

-- What a new yard is for, shown and edited through the same filter window a
-- container uses. These defaults shape the yard's purpose, not admission.
Storage.DEPOT_DEFAULT_FILTERS = { logs = true, building = true }

-- Reuse the settlement supply targets to limit items left on the floor.
Storage.DEPOT_TARGETS = { logs = 60, building = 40 }

local function depotCopyFilters(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if value == true then result[key] = true end
    end
    return result
end

function Storage.isDepotZone(zone)
    return type(zone) == "table" and zone.enabled ~= false
        and Storage.DEPOT_ZONE_TYPES[zone.type] == true
end

-- The zone record speaks the same shape a container policy does, so the same
-- `acceptsDeposit`, `label` and filter window read it unchanged. A zone with no
-- filters yet reports the defaults without writing them: a getter never edits a
-- save.
function Storage.zoneFilters(zone)
    if not Storage.isDepotZone(zone) then return nil end
    local filters = type(zone.storageFilters) == "table"
        and depotCopyFilters(zone.storageFilters)
        or depotCopyFilters(Storage.DEPOT_DEFAULT_FILTERS)
    return {
        storageFilterVersion = 1,
        storageFilters = filters,
        depot = true,
        zoneId = zone.id,
        zoneType = zone.type,
    }
end

-- Called when the area is created and when the player saves filters. A depot
-- with no stored filters starts on the default set; an empty set the player
-- chose stays empty. Either way admission is universal: the yard takes any
-- item, and the set only describes what it is for.
function Storage.ensureDepotFilters(zone)
    if not Storage.isDepotZone(zone) then return nil end
    if type(zone.storageFilters) ~= "table" then
        zone.storageFilters = depotCopyFilters(Storage.DEPOT_DEFAULT_FILTERS)
    end
    zone.storageFilterVersion = 1
    zone.depot = true
    return zone
end

function Storage.depotZone(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if Storage.isDepotZone(zone) and (zoneType == nil or zone.type == zoneType) then
            return zone
        end
    end
    return nil
end

function Storage.depotZoneAt(base, x, y, z)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if Storage.isDepotZone(zone) and (tonumber(zone.z) or 0) == (tonumber(z) or 0) then
            local minX = math.min(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
            local maxX = math.max(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
            local minY = math.min(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
            local maxY = math.max(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
            if x >= minX and x <= maxX and y >= minY and y <= maxY then return zone end
        end
    end
    return nil
end

-- A yard is a dumping ground, not a shelf: any real item may be set down on it.
-- What the player selected still reads in the filter window and still sets the
-- per-category targets; it never turns the yard away.
function Storage.depotAccepts(zone, item)
    if item == nil then return false end
    return Storage.isDepotZone(zone) == true
end

-- Heavy or large loads are the yard's business. Native items report their
-- weight; the optional heavy flag is used when the item has one, and an
-- unreadable weight never turns an item into a bulk load.
local DEPOT_BULK_WEIGHT = 2.0

function Storage.depotBulkRank(item)
    if item == nil then return 2 end
    if safeBoolean(item, "isHeavy") == true then return 1 end
    local read, weight = pcall(function() return item:getActualWeight() end)
    weight = read and tonumber(weight) or nil
    if weight == nil then
        local ok, baseWeight = pcall(function() return item:getWeight() end)
        weight = ok and tonumber(baseWeight) or nil
    end
    if weight == nil then return 2 end
    return weight >= DEPOT_BULK_WEIGHT and 1 or 2
end

function Storage.depotTarget(zone, category)
    local targets = type(zone) == "table" and type(zone.depotTargets) == "table"
        and zone.depotTargets or Storage.DEPOT_TARGETS
    return tonumber(targets[category]) or 0
end

-- PLACEMENT DECISION (pure)
-- One answer, one reason. `accepted` is the filter result, `held` what the
-- floor already carries for that category, `freeTiles` a free spot inside the
-- area. A target of zero means "no ceiling", not "refuse everything".
function Storage.depotPlacementDecision(facts)
    if type(facts) ~= "table" or facts.depot ~= true then return "no_depot" end
    if facts.accepted ~= true then return "not_allowed" end
    local target = tonumber(facts.target) or 0
    local held = tonumber(facts.held) or 0
    if target > 0 and held >= target then return "target_reached" end
    if (tonumber(facts.freeTiles) or 0) <= 0 then return "no_free_tile" end
    return "place"
end

Storage.DEPOT_REFUSALS = {
    stock_unreadable = "Cannot check the Drop Point stock right now",
    no_depot = "There is no depot area at this base.",
    not_allowed = "The depot filters do not allow that.",
    target_reached = "The depot already holds what it wants of that.",
    no_free_tile = "There is no free floor left in the depot.",
}

function Storage.depotRefusalText(reason)
    return Storage.DEPOT_REFUSALS[tostring(reason or "")]
        or "That cannot go in the depot right now."
end

-- What the depot floor already holds, per storage category. This is the same
-- read `floorStock` makes for the assigned storage area, pointed at the zone.
function Storage.depotStock(base, zone)
    local result = { totals = {}, squares = 0, loaded = false }
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or zone == nil or cell == nil or cell.getGridSquare == nil then
        return result
    end
    local minX = math.min(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local maxX = math.max(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local minY = math.min(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local maxY = math.max(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local z = tonumber(zone.z) or tonumber(base.home ~= nil and base.home.z) or 0
    local function add(item)
        if item == nil then return end
        local category = Storage.classifyItem(item)
        result.totals[category] = (result.totals[category] or 0) + itemQuantity(item)
    end
    local seenContainers, seenItems = {}, {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local loose,known = squareLooseItems(square)
            if not known then result.unreadable=(result.unreadable or 0)+1 end
            if known then result.loaded=true end
            if known and #loose > 0 then
                result.squares = result.squares + 1
                result.loaded = true
                for index = 1, #loose do
                    if not walkLooseItemTree(loose[index], add, seenContainers, seenItems) then
                        result.unreadable = (result.unreadable or 0) + 1
                    end
                end
            end
        end
    end
    return result
end

-- A depot is real loaded world floor, never a terrain-object inventory.
local function depotSquareAvailable(square)
    if square == nil or square.isFree == nil then return false end
    local ok,free=pcall(function() return square:isFree(false) end)
    local loose,known=squareLooseItems(square)
    return ok and free==true and known and #loose==0
end

-- A spot a survivor can actually set something down on: standable, on the
-- zone's floor, and not already carrying loose stock. The scan is bounded
-- because a depot is a yard, not the county.
function Storage.depotFreeTiles(base, zone, limit)
    local cell = getCell ~= nil and getCell() or nil
    if zone == nil or cell == nil or cell.getGridSquare == nil then return 0 end
    local minX = math.min(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local maxX = math.max(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local minY = math.min(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local maxY = math.max(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local z = tonumber(zone.z) or tonumber(base ~= nil and base.home ~= nil and base.home.z) or 0
    local cap = tonumber(limit) or 400
    local scanned, free = 0, 0
    for x = minX, maxX do
        for y = minY, maxY do
            scanned = scanned + 1
            if scanned > cap then return free end
            local square = cell:getGridSquare(x, y, z)
            if depotSquareAvailable(square) then free = free + 1 end
        end
    end
    return free
end

-- The one question a haul asks: where does this go now? The cheap checks run
-- before any tile scan, so a refused item never walks the yard.
function Storage.depotDestination(base, item, zone)
    local depot = zone or Storage.depotZone(base)
    if depot == nil then return nil, "no_depot" end
    local accepted = Storage.depotAccepts(depot, item)
    local category = item ~= nil and Storage.classifyItem(item) or nil
    local held = 0
    if accepted and category ~= nil then
        local stock = Storage.depotStock(base, depot)
        if (stock.unreadable or 0)>0 then return nil,"stock_unreadable" end
        held = tonumber(stock.totals[category]) or 0
    end
    local preliminary = Storage.depotPlacementDecision({
        depot = true, accepted = accepted,
        target = Storage.depotTarget(depot, category),
        held = held, freeTiles = 1,
    })
    if preliminary ~= "place" then return nil, preliminary end
    local decision = Storage.depotPlacementDecision({
        depot = true, accepted = true,
        target = Storage.depotTarget(depot, category),
        held = held, freeTiles = Storage.depotFreeTiles(base, depot),
    })
    if decision ~= "place" then return nil, decision end
    return depot, "place"
end

-- The first spot in the yard a survivor can set something down on. Kept
-- separate from the count because a haul needs the tile, not the number.
function Storage.depotFreeSquare(base, zone)
    local cell = getCell ~= nil and getCell() or nil
    if zone == nil or cell == nil or cell.getGridSquare == nil then return nil end
    local minX = math.min(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local maxX = math.max(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local minY = math.min(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local maxY = math.max(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local z = tonumber(zone.z) or tonumber(base ~= nil and base.home ~= nil and base.home.z) or 0
    local scanned = 0
    for x = minX, maxX do
        for y = minY, maxY do
            scanned = scanned + 1
            if scanned > 400 then return nil end
            local square = cell:getGridSquare(x, y, z)
            if depotSquareAvailable(square) then return square end
        end
    end
    return nil
end

-- The destination is a real square. The existing Organize owner walks there
-- and uses its native queueDrop; terrain has no inventory container.
function Storage.depotStore(base, item, zone)
    local depot = zone or Storage.depotZone(base)
    if depot == nil then return nil, "no_depot" end
    if item == nil then return nil, "not_allowed" end
    if not Storage.depotAccepts(depot, item) then return nil, "not_allowed" end
    local category = Storage.classifyItem(item)
    local stock=Storage.depotStock(base,depot)
    if (stock.unreadable or 0)>0 then return nil,"stock_unreadable" end
    local held = tonumber(stock.totals[category]) or 0
    local target = Storage.depotTarget(depot, category)
    if target > 0 and held >= target then return nil, "target_reached" end
    local square = Storage.depotFreeSquare(base, depot)
    if square == nil then return nil, "no_free_tile" end
    return { zone = depot, square = square, category = category }
end

-- Re-read the same yard's current policy/target and world floor before dropping.
-- Filters describe intent; the approved drop-point policy still admits any item.
function Storage.depotDropAllowed(base,item,square,zoneId)
    if base==nil or square==nil or zoneId==nil then return false end
    local zone=Storage.depotZoneAt(base,square:getX(),square:getY(),square:getZ())
    if zone==nil or zone.id~=zoneId then return false end
    local destination=Storage.depotStore(base,item,zone)
    return destination~=nil and depotSquareAvailable(square)
end
-- DEPOT STATUS LINE (pure)
-- One sentence the home band can show: what the yard wants, what stands on
-- it, and whether there is any floor left. No world reads here.
local function depotEntryText(entry)
    local held = math.max(0, math.floor(tonumber(entry.held) or 0))
    local target = math.max(0, math.floor(tonumber(entry.target) or 0))
    local category = tostring(entry.category or "stock")
    if target > 0 then return category .. " " .. tostring(held) .. "/" .. tostring(target) end
    return category .. " " .. tostring(held)
end

function Storage.depotStatusLine(facts)
    if type(facts) ~= "table" then return nil end
    local entries = type(facts.entries) == "table" and facts.entries or {}
    if #entries == 0 then return nil end
    local parts = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then parts[#parts + 1] = depotEntryText(entry) end
    end
    if #parts == 0 then return nil end
    local text = tostring(facts.label or "Log yard") .. ": " .. table.concat(parts, ", ")
    local free = tonumber(facts.freeTiles)
    if free ~= nil and free <= 0 then text = text .. " (floor full)" end
    return text
end

-- The live projection behind that line. Called by the home status owner, not
-- by a panel, so there is one answer for the band and the base line.
function Storage.depotStatus(base)
    local zone = Storage.depotZone(base)
    if zone == nil then return nil end
    local stock = Storage.depotStock(base, zone)
    local categories = {}
    for category in pairs(Storage.DEPOT_TARGETS) do categories[#categories + 1] = category end
    table.sort(categories)
    local entries = {}
    for _, category in ipairs(categories) do
        local target = Storage.depotTarget(zone, category)
        local held = tonumber(stock.totals[category]) or 0
        if target > 0 or held > 0 then
            entries[#entries + 1] = { category = category, held = held, target = target }
        end
    end
    local free = Storage.depotFreeTiles(base, zone)
    -- The save keeps its own label; a name written before the rename still
    -- reads as the current one, so the band and the panel agree.
    local label = tostring(zone.label or "Log yard")
    local naming = rawget(_G, "KnoxPersistence")
    if naming ~= nil and type(naming.zoneDisplayLabel) == "function" then
        label = tostring(naming.zoneDisplayLabel(zone, label))
    end
    return {
        zone = zone, label = label, entries = entries,
        freeTiles = free, full = free <= 0,
        line = Storage.depotStatusLine({ label = label, entries = entries, freeTiles = free }),
    }
end
-- The notebook reads the yard even when it is empty: an empty floor is not a
-- problem, so the band stays quiet, but the player still needs to see that the
-- yard exists and what it holds. The band's line is reused rather than composed
-- a second time, so a stocked yard reads identically in both places.
function Storage.depotSummaryLine(status)
    if type(status) ~= "table" then return nil end
    if status.line ~= nil then return status.line end
    local label = status.label
    if type(label) ~= "string" or label == "" then return nil end
    return label .. ": empty"
end
function Storage.depotLabel(zone)
    local policy = Storage.zoneFilters(zone)
    if policy == nil then return "Depot" end
    return Storage.label(policy)
end
return Storage
