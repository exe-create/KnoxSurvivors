require "KS_Persistence"
require "KS_ToolCupboard"
require "KS_BaseSupplyPlanner"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"
require "Util/AdjacentFreeTileFinder"

local Storage = rawget(_G, "KnoxBaseStorage") or {}
_G.KnoxBaseStorage = Storage
local loadedContainerCache = {}

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
    return success and value == true or nil
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
            -- Unmigrated records without any category are preserved on disk but
            -- never treated as assigned storage (legacy fridge check).
            if policy.category == nil and policy.storageRole == nil then
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

local function loadedContainerCacheKey(base, area)
    return table.concat({ tostring(base.id), tostring(area.minX), tostring(area.minY),
        tostring(area.maxX), tostring(area.maxY), tostring(area.z),
        tostring(area.allFloors) }, ":")
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
    local cacheKey = loadedContainerCacheKey(base, area)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
    local cached = now ~= nil and loadedContainerCache[cacheKey] or nil
    local found = cached ~= nil and now - cached.at < 10000 and cached.entries or nil
    if found == nil then
        found = {}
        local firstZ, lastZ = tonumber(area.minZ), tonumber(area.maxZ)
        if firstZ == nil or lastZ == nil then
            if area.allFloors == true then
                -- Build 42 loaded building levels, including basement floors.
                firstZ, lastZ = -1, 7
                local homeZ = tonumber(base.home ~= nil and base.home.z)
                if homeZ ~= nil then firstZ, lastZ = math.min(firstZ, homeZ), math.max(lastZ, homeZ) end
            else
                firstZ = tonumber(area.z) or tonumber(base.home ~= nil and base.home.z) or 0
                lastZ = firstZ
            end
        end
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
        if now ~= nil then loadedContainerCache[cacheKey] = { at = now, entries = found } end
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

-- Transient, read-only migration for pre-typed-storage saves. Returns a
-- food-role view of a legacy record when it still resolves to a loaded
-- fridge/freezer, else nil. Never mutates the persisted record.
function Storage.legacyFridgePolicy(policy)
    if policy == nil or getCell == nil or getCell() == nil then return nil end
    local ok, resolved = pcall(function() return Storage.resolvePolicy(policy) end)
    if not ok or type(resolved) ~= "table" or resolved.container == nil then
        return nil
    end
    local okType, containerType = pcall(function()
        return resolved.container:getType()
    end)
    if not okType or type(containerType) ~= "string" then return nil end
    local lower = string.lower(containerType)
    if string.find(lower, "fridg", 1, true) == nil
        and string.find(lower, "freez", 1, true) == nil then
        return nil
    end
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
        building = "Materials", farming = "Farming",
        clothing = "Clothing", junk = "Junk",
}
local STORAGE_FILTER_ORDER = {
    "food", "water", "medical", "weapons", "ammunition", "tools",
    "logs", "building", "farming", "clothing", "junk", "general",
}

local function nativeFilterCategory(key)
    if type(key) ~= "string" or string.sub(key, 1, 8) ~= "display:" then return nil end
    local category = string.sub(key, 9)
    if category == "" or #category > 64 or not string.match(category, "^[%w_%-]+$") then
        return nil
    end
    return category
end

function Storage.isValidFilterCategory(category)
    return STORAGE_FILTER_LABELS[category] ~= nil or nativeFilterCategory(category) ~= nil
end

function Storage.filtersForPolicy(policy)
    if policy == nil then return {} end
    if policy.storageFilterVersion == 1 and type(policy.storageFilters) == "table" then
        local result = {}
        for _, category in ipairs(STORAGE_FILTER_ORDER) do
            if policy.storageFilters[category] == true then result[category] = true end
        end
        for category, enabled in pairs(policy.storageFilters) do
            if enabled == true and nativeFilterCategory(category) ~= nil then
                result[category] = true
            end
        end
        return result
    end
    local role = policy.storageRole or policy.category or "supplies"
    if role == "supplies" or role == "depot" then role = "general" end
    return STORAGE_FILTER_LABELS[role] ~= nil and { [role] = true } or {}
end

function Storage.filterLabel(category)
    local nativeCategory = nativeFilterCategory(category)
    if nativeCategory ~= nil then return nativeCategory end
    return STORAGE_FILTER_LABELS[category] or "Storage"
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
    if #labels == 0 then return "Storage" end
    return table.concat(labels, " + ")
end

local function filteredCategoryMatchesDeposit(item, category)
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
    return false
end

function Storage.filterAllowsKind(policy, kind)
    if policy == nil then return false end
    if policy.storageFilterVersion ~= 1 then return true end
    local filters = Storage.filtersForPolicy(policy)
    if filters.general == true or filters[kind] == true
        or (kind == "water" and filters.food == true)
    then return true end
    for category, enabled in pairs(filters) do
        if enabled == true and nativeFilterCategory(category) ~= nil then return true end
    end
    return false
end

-- RimWorld-style priority rank for deposit ordering. Lower sorts first:
-- critical shelves fill before preferred, normal, then low. Missing or
-- legacy records read as normal so old saves behave unchanged.
local STORAGE_PRIORITY_RANKS = {
    critical = 0, preferred = 1, normal = 2, low = 3,
}

function Storage.priorityRank(policy)
    local rank = policy ~= nil and STORAGE_PRIORITY_RANKS[policy.priority] or nil
    if rank == nil then return STORAGE_PRIORITY_RANKS.normal end
    return rank
end

function Storage.priorityLabel(policy)
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

function Storage.matchesCategory(item, category)
    if item == nil then
        return false
    end
    local full = fullType(item)
    category = tostring(category or "general")
    if category == "general" then
        return true
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
local function walkContainerItems(container, visitor, seen)
    if container == nil or type(visitor) ~= "function" then return end
    seen = seen or {}
    if seen[container] then return end
    seen[container] = true
    local items = container:getItems()
    if items == nil then return end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item, container)
        local nested = false
        if item ~= nil and item.IsInventoryContainer ~= nil then
            local ok, value = pcall(function() return item:IsInventoryContainer() end)
            nested = ok and value == true
        end
        if nested and item.getInventory ~= nil then
            local ok, inventory = pcall(function() return item:getInventory() end)
            if ok and inventory ~= nil then
                walkContainerItems(inventory, visitor, seen)
            end
        end
    end
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
function Storage.findSurvivalSupply(base, character, kind)
    if kind ~= "food" and kind ~= "water" then return nil, "invalid_kind" end
    for _, policy in ipairs(orderedPoliciesByDistance(base, character)) do
        local resolved = Storage.filterAllowsKind(policy, kind)
            and Storage.resolvePolicy(policy) or nil
        if resolved ~= nil then
            local found = nil
            walkContainerItems(resolved.container, function(candidate, sourceContainer)
                if found == nil and survivalKind(candidate) == kind
                    and Storage.filterAllowsItem(policy, candidate) then
                    found = {
                        kind = kind,
                        item = candidate,
                        source = sourceContainer,
                        policy = policy,
                    }
                end
            end)
            if found ~= nil then return found, "found" end
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

-- Returns an honest snapshot of assigned storage that is currently available in
-- the loaded cell.  Unloaded/missing containers are reported separately rather
-- than assumed empty or treated as an abstract stockpile.
function Storage.summarize(base)
    local summary = {
        totals = emptyResourceTotals(),
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
    return summary
end

local function hasRoom(container, item, character)
    if container == nil then
        return false
    end
    -- Real native capacity: assigned storage fills like any Project Zomboid
    -- container, and deposits overflow to the next-best shelf through the
    -- ranked candidates above. Full shelves reject; nothing is lost, the
    -- item stays carried until room exists.
    if container.hasRoomFor ~= nil then
        local success, result = pcall(function()
            return container:hasRoomFor(character, item)
        end)
        return success and result == true
    end
    return false
end

-- Cleanup deposits never target arbitrary nearby homes or foreign storage.
-- The caller supplies only this survivor's canonical assigned/owned base.
local function findDeposit(base, character, item, trip, excluded, ticks, policyKey)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if base == nil or origin == nil then return nil, "no_owned_storage" end
    local candidates = {}
    for _, policy in ipairs(Storage.operationalPolicies(base)) do
        local dx, dy = (tonumber(policy.x) or math.huge) - origin:getX(),
            (tonumber(policy.y) or math.huge) - origin:getY()
        local category = tostring(policy.category or "general")
        local floorDifference = math.abs((tonumber(policy.z) or math.huge) - origin:getZ())
        -- Typed stores stay authoritative, but anything assigned with room
        -- works as overflow: a surplus the settlement cannot shelve anywhere
        -- just bounces between pockets and cleanup forever. Consumable
        -- stores (food, water, medical) are the last resort so the kitchen
        -- and the medicine cabinet stay clean while any other shelf exists.
        local role = tostring(policy.storageRole or "")
        local unassigned = policy.transientContainer == true
        local exact = not unassigned and Storage.acceptsDeposit(policy, item)
        local overflow = not unassigned and not exact and policy.storageFilterVersion ~= 1
            and (role ~= "food" and role ~= "water" and role ~= "medical")
        local lastResort = not unassigned and not exact and not overflow
            and policy.storageFilterVersion ~= 1
        if (floorDifference == 0 or (trip and floorDifference <= 2))
            and dx * dx + dy * dy <= (trip and 128 * 128 or 2)
            and (policyKey == nil or policy.key == policyKey)
            and (excluded == nil or (excluded[policy.key] or 0) <= (ticks or 0))
            and (exact or overflow or lastResort or unassigned) then
            local resolved = Storage.resolvePolicy(policy)
            if resolved ~= nil and hasRoom(resolved.container, item, character)
                and safeBoolean(resolved.container, "isItemAllowed", item) == true then
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
                    local classified = Storage.classifyItem(item)
                    local exactCategory = policy.storageFilterVersion == 1
                        and exact or policy.storageRole == classified
                        or (policy.storageRole == "food" and Storage.acceptsDeposit(policy, item))
                    -- RimWorld order: highest-priority valid shelf first,
                    -- then exact-type matches, then distance. A critical
                    -- overflow shelf beats a normal exact one by design.
                    resolved.priorityRank = Storage.priorityRank(policy)
                    resolved.preference = unassigned and 4
                        or exactCategory and 0
                        or policy.storageRole == "supplies" and 1
                        or exact and 2
                        or overflow and 3 or 4
                    -- Use live square coords for closest-relative sorting so a
                    -- moved/replaced container does not win on stale ModData.
                    local rdx = resolved.square:getX() - origin:getX()
                    local rdy = resolved.square:getY() - origin:getY()
                    resolved.distance = rdx * rdx + rdy * rdy
                    candidates[#candidates + 1] = resolved
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.preference ~= b.preference then return a.preference < b.preference end
        if a.priorityRank ~= b.priorityRank then return a.priorityRank < b.priorityRank end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.policy.key < b.policy.key
    end)
    return candidates[1], candidates[1] ~= nil and "nearby_storage" or "no_reachable_storage"
end

function Storage.findNearbyDeposit(base, character, item, policyKey)
    return findDeposit(base, character, item, false, nil, nil, policyKey)
end

-- Only loaded owned containers within a practical local trip. The native
-- adjacent-square finder picks the interaction side; existing movement owns routing.
function Storage.findDepositTrip(base, character, item, excluded, ticks)
    return findDeposit(base, character, item, true, excluded, ticks)
end

local function firstMatchingItem(container, category)
    local found = nil
    walkContainerItems(container, function(item)
        if found == nil and Storage.matchesCategory(item, category) then
            found = item
        end
    end)
    return found
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
orderedPoliciesByDistance = function(base, character)
    local policies = Storage.operationalPolicies(base)
    local origin = character ~= nil and character.getCurrentSquare ~= nil
        and character:getCurrentSquare() or nil
    if origin == nil then return policies end
    local ox, oy, oz = origin:getX(), origin:getY(), origin:getZ()
    table.sort(policies, function(a, b)
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
    return policies
end

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
            for _, policy in ipairs(orderedPoliciesByDistance(base, character)) do
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
                        if found ~= nil then
                            return found, "found"
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

-- Real inventory-vs-storage comparison that ignores the ignore-resources
-- sandbox flag. Lets workers fetch what is actually stored even when gating
-- is bypassed; native job actions still need carried items.
function Storage.findFetchTransfer(base, character, requirements)
    return findRequiredTransferReal(base, character, requirements)
end

-- Discovery may inspect loaded base containers to name a concrete requirement.
-- The normal transfer action still owns moving the selected item to the resident.
-- Uses closest-relative ordering so multiple storages do not cause cross-base walks.
function Storage.findItemType(base, predicate, character)
    if type(predicate) ~= "function" then return nil end
    local policies = orderedPoliciesByDistance(base, character)
    for _, policy in ipairs(policies) do
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
    return nil
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

function Storage.queueTransfer(character, transfer)
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
        nil
    )
end

return Storage
