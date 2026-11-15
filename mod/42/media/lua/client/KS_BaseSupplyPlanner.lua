local Planner = rawget(_G, "KnoxBaseSupplyPlanner") or {}
_G.KnoxBaseSupplyPlanner = Planner

local function safe(call, fallback)
    local ok, value = pcall(call)
    return ok and value or fallback
end

-- This deliberately answers only whether an existing world item can satisfy a
-- declared base-task requirement.  It does not count, create, reserve, or move
-- anything; the controller and native transfer action retain those ownership
-- boundaries.
function Planner.matchesRequirement(item, requirements)
    if item == nil or type(requirements) ~= "table" then return false end
    local items = requirements.items
    if type(items) ~= "table" then return false end
    local fullType = safe(function() return item:getFullType() end, nil)
    if type(fullType) ~= "string" or (tonumber(items[fullType]) or 0) <= 0 then return false end
    local rule = type(requirements.itemRules) == "table" and requirements.itemRules[fullType] or nil
    if type(rule) ~= "table" then return true end
    if rule.usable == true then
        -- Declared tool usability requires readable native state. A missing or
        -- throwing accessor is not evidence that an item is intact.
        local inspected, broken = pcall(function() return item:isBroken() end)
        if not inspected or broken ~= false then return false end
    end
    if rule.minUses ~= nil and (tonumber(safe(function() return item:getCurrentUses() end, 0)) or 0)
        < (tonumber(rule.minUses) or 0) then return false end
    if rule.minUsesFloat ~= nil and (tonumber(safe(function() return item:getCurrentUsesFloat() end, 0)) or 0)
        < (tonumber(rule.minUsesFloat) or 0) then return false end
    if rule.water == true then
        local uses = safe(function() return ISFarmingMenu.getWaterUsesInteger(item) end, 0)
        if (tonumber(uses) or 0) <= 0 then return false end
    end
    return true
end

-- Plain material counts retain the native recursive fast path. Tools and
-- water inspect real instances, so a broken/empty duplicate cannot satisfy work.
function Planner.inventoryCount(inventory, fullType, requirements)
    local rules = requirements ~= nil and requirements.itemRules or nil
    if type(rules) == "table" and type(rules[fullType]) == "table" then
        local count, seen = 0, {}
        local function walk(container)
            if container == nil or seen[container] then return end
            seen[container] = true
            local items = safe(function() return container:getItems() end, nil)
            if items == nil then return end
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                if safe(function() return item:getFullType() end, nil) == fullType
                    and Planner.matchesRequirement(item, requirements) then
                    count = count + math.max(1, math.floor(tonumber(safe(function()
                        return item:getCount()
                    end, 1)) or 1))
                end
                if safe(function() return item:IsInventoryContainer() end, false) == true then
                    walk(safe(function() return item:getInventory() end, nil))
                end
            end
        end
        walk(inventory)
        return count
    end
    if inventory == nil or inventory.getItemCount == nil then return 0 end
    return math.max(0, tonumber(safe(function()
        return inventory:getItemCount(tostring(fullType), true)
    end, 0)) or 0)
end

-- Return only the outstanding part of a task's declared item requirements.
-- A worker may already carry tools or part of a material stack when a base job
-- starts.  World search must not spend its bounded attempts collecting another
-- copy of an item that is already satisfied while a different requirement is
-- still missing.
function Planner.missingRequirements(requirements, inventory)
    local missing = {}
    for fullType, count in pairs(type(requirements) == "table"
        and type(requirements.items) == "table" and requirements.items or {}) do
        local required = math.max(0, math.floor(tonumber(count) or 0))
        local outstanding = required - Planner.inventoryCount(inventory, fullType, requirements)
        if type(fullType) == "string" and fullType ~= "" and outstanding > 0 then
            missing[fullType] = outstanding
        end
    end
    return missing
end

-- Live job demand is derived, never another saved stock ledger. Consumable
-- counts add; jobs share durable tools and require only the largest tool set.
function Planner.taskItemGoals(tasks, countFor)
    if type(countFor) ~= "function" then return {} end
    local demand = {}
    for _, task in pairs(type(tasks) == "table" and tasks or {}) do
        if type(task) == "table" and task.state == "queued" then
            local requirements = task.requirements or {}
            for fullType, count in pairs(requirements.items or {}) do
                local key = Planner.itemTargetKey(fullType)
                local required = math.max(0, math.floor(tonumber(count) or 0))
                if key ~= nil and required > 0 then
                    local row = demand[key]
                    if row == nil then
                        row = { key = key, fullType = fullType, durable = 0, consumable = 0,
                            requirements = { items = {}, itemRules = {} } }
                        demand[key] = row
                    end
                    local rule = (requirements.itemRules or {})[fullType]
                    if type(rule) == "table" and rule.usable == true then
                        row.durable = math.max(row.durable, required)
                    else
                        row.consumable = row.consumable + required
                    end
                    row.target = row.durable + row.consumable
                    row.requirements.items[fullType] = row.target
                    for name, value in pairs(type(rule) == "table" and rule or {}) do
                        local combined = row.requirements.itemRules[fullType] or {}
                        if type(value) == "number" then
                            combined[name] = math.max(tonumber(combined[name]) or 0, value)
                        elseif value == true then combined[name] = true end
                        row.requirements.itemRules[fullType] = combined
                    end
                end
            end
        end
    end
    local result = {}
    for _, row in pairs(demand) do
        local ok, count = pcall(countFor, row.fullType, row.requirements)
        local current = ok and tonumber(count) or nil
        if current ~= nil and current == current and current >= 0 and current < math.huge then
            row.current = math.floor(current)
            row.missing = math.max(0, row.target - row.current)
            if row.missing > 0 then result[#result + 1] = row end
        end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function Planner.matchesMissingRequirement(item, requirements, inventory)
    if not Planner.matchesRequirement(item, requirements) then return false end
    local fullType = safe(function() return item:getFullType() end, nil)
    if type(fullType) ~= "string" then return false end
    return (Planner.missingRequirements(requirements, inventory)[fullType] or 0) > 0
end

function Planner.requirementTypes(requirements)
    local result = {}
    for fullType, count in pairs(type(requirements) == "table"
        and type(requirements.items) == "table" and requirements.items or {}) do
        if type(fullType) == "string" and fullType ~= ""
            and (tonumber(count) or 0) > 0 then
            result[#result + 1] = fullType
        end
    end
    table.sort(result)
    return result
end

-- A saved per-base target wins only for its own category. The defaults below
-- remain the fallback; the existing categories keep their prior thresholds,
-- while fuel now has a two-can default and a real search kind.
local function targetOverride(targets, category)
    if type(targets) ~= "table" then return nil end
    local value = tonumber(targets[category])
    if value == nil then return nil end
    return math.max(0, math.min(50, math.floor(value)))
end

-- ITEM MINIMUMS
-- A category target is a rule of thumb. A player who wants twenty bandages
-- says twenty bandages, so one exact item can carry its own saved floor beside
-- the category defaults. The key is the same shape the container filters use
-- for one item type, so a shelf rule and a stock rule name a type the same way.
local ITEM_TARGET_PREFIX = "item:"

function Planner.itemTargetKey(fullType)
    if type(fullType) ~= "string" or fullType == "" or #fullType > 64 then return nil end
    if not string.match(fullType, "^[%w_%.%-]+$") then return nil end
    return ITEM_TARGET_PREFIX .. fullType
end

function Planner.itemTargetType(key)
    if type(key) ~= "string"
        or string.sub(key, 1, #ITEM_TARGET_PREFIX) ~= ITEM_TARGET_PREFIX then
        return nil
    end
    local fullType = string.sub(key, #ITEM_TARGET_PREFIX + 1)
    if fullType == "" or #fullType > 64 then return nil end
    if not string.match(fullType, "^[%w_%.%-]+$") then return nil end
    return fullType
end

-- The player's item floors, oldest rule first only in the sense of type order:
-- sorting by type keeps the list stable between refreshes so a stepper never
-- moves under the pointer. countFor(fullType) is the base's own on-hand count,
-- injected by the caller; this function reads no world and writes nothing.
function Planner.itemGoalStatus(targets, countFor)
    if type(targets) ~= "table" or type(countFor) ~= "function" then return {} end
    local keys = {}
    for key, value in pairs(targets) do
        local fullType = Planner.itemTargetType(key)
        if fullType ~= nil and (tonumber(value) or 0) > 0 then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do
        local fullType = Planner.itemTargetType(key)
        local target = math.max(0, math.min(50, math.floor(tonumber(targets[key]) or 0)))
        local ok, counted = pcall(countFor, fullType)
        local current = ok and math.max(0, math.floor(tonumber(counted) or 0)) or 0
        result[#result + 1] = {
            key = key,
            fullType = fullType,
            current = current,
            target = target,
            missing = math.max(0, target - current),
        }
    end
    return result
end

-- One shared reserve definition for both automatic supply decisions and the
-- player-facing settlement status. Keeping the thresholds here prevents the
-- Notebook from describing a base as healthy while the resident controller is
-- simultaneously sending somebody out for supplies.
function Planner.reserveStatus(totals, residentCount, targets, waterSource)
    totals = type(totals) == "table" and totals or {}
    local residents = math.max(1, math.floor(tonumber(residentCount) or 1))
    local definitions = {
        { kind = "find_food", category = "food", target = residents * 2 },
        { kind = "find_water", category = "water", target = residents * 2 },
        { kind = "find_medical", category = "medical", target = 1 },
        { kind = "find_weapon", category = "weapons", target = 1 },
        { kind = "find_tools", category = "tools", target = 1 },
        { kind = "find_wood", category = "logs", target = residents * 4 },
        { kind = "find_materials", category = "building", target = 4 },
        { kind = "find_clothing", category = "clothing", target = residents },
        { kind = "find_ammo", category = "ammunition", target = 2 },
        { kind = "find_fuel", category = "fuel", target = 2 },
    }
    local result = {}
    for _, definition in ipairs(definitions) do
        local current = math.max(0, tonumber(totals[definition.category]) or 0)
        local override = targetOverride(targets, definition.category)
        local target = override ~= nil and override or definition.target
        -- Once the taps are dry, stored water is the whole supply. Raise only
        -- the unreserved default; a player's saved target still wins.
        if definition.category == "water" and override == nil
            and waterSource == "dry" then
            target = math.max(target, residents * 4)
        end
        result[#result + 1] = {
            kind = definition.kind,
            category = definition.category,
            current = current,
            target = target,
            missing = math.max(0, target - current),
        }
    end
    return result
end

-- The sandbox's own shutoff day is the only water-source state this mod
-- reads. A non-positive modifier means the shutoff is disabled; an absent
-- clock or modifier stays unknown instead of claiming the taps are running.
function Planner.waterSourceState(worldAgeDays, waterShutModifier)
    local days = tonumber(worldAgeDays)
    local modifier = tonumber(waterShutModifier)
    if days == nil or modifier == nil or days ~= days or modifier ~= modifier
        or days == math.huge or modifier == math.huge then return "unknown" end
    if modifier <= 0 then return "running" end
    return days >= modifier and "dry" or "running"
end

-- Pick the first meaningful settlement shortage using the same conservative
-- per-resident reserve targets used by the loaded autonomy controller. This is
-- a pure decision helper; claims, movement, and item transfers remain owned by
-- their existing systems.
function Planner.shortages(totals, residentCount, targets, waterSource)
    local result = {}
    for _, status in ipairs(Planner.reserveStatus(totals, residentCount, targets, waterSource)) do
        if status.missing > 0 then result[#result + 1] = status.kind end
    end
    return result
end

function Planner.chooseShortage(totals, residentCount, targets, waterSource)
    return Planner.shortages(totals, residentCount, targets, waterSource)[1]
end

-- Assigned shelves and a floor pile are both stock a resident can pick up, so
-- a shortage must count both before it sends anyone out. This is the one place
-- they are added together; the summary keeps them apart so a missing shelf is
-- still visible as a missing shelf.
function Planner.stockTotals(summary)
    local totals = {}
    for category, quantity in pairs(type(summary) == "table"
        and type(summary.totals) == "table" and summary.totals or {}) do
        totals[category] = math.max(0, tonumber(quantity) or 0)
    end
    for category, quantity in pairs(type(summary) == "table"
        and type(summary.floorTotals) == "table" and summary.floorTotals or {}) do
        totals[category] = (totals[category] or 0) + math.max(0, tonumber(quantity) or 0)
    end
    return totals
end

-- A streamed-out or unassigned storage set is unknown stock, not an empty
-- pantry. Supply trips also require a real destination on return, so do not
-- elect a worker until at least one assigned container was inspected.
function Planner.hasKnownStorageSnapshot(summary)
    return type(summary) == "table"
        and (tonumber(summary.loadedPolicies) or 0) > 0
end

-- Claims are maintained by the base controller. Select the first shortage
-- that is either unowned or already owned by this resident, allowing food and
-- water runs to coexist without ever assigning two workers to the same kind.
function Planner.chooseAvailableShortage(totals, residentCount, claims, survivorId, targets, waterSource)
    claims = type(claims) == "table" and claims or {}
    local current = Planner.shortages(totals, residentCount, targets, waterSource)
    -- Reconstruction may evaluate the worker after another, higher-priority
    -- lease expires. Finish the worker's existing kind instead of letting one
    -- resident accumulate two simultaneous leases.
    for _, kind in ipairs(current) do
        local claim = claims[kind]
        if type(claim) == "table"
            and tostring(claim.survivorId or "") == tostring(survivorId or "") then
            return kind
        end
    end
    for _, kind in ipairs(current) do
        if claims[kind] == nil then return kind end
    end
    return nil
end

-- Select one ready resident for an automatic shortage run. Candidate discovery
-- remains owned by the loaded controller; this helper only provides stable,
-- persisted rotation so controller iteration order cannot always send the same
-- survivor. Explicit player orders are excluded by the caller.
function Planner.chooseWorker(candidates, shortageKind)
    local eligible = {}
    for _, candidate in ipairs(type(candidates) == "table" and candidates or {}) do
        if type(candidate) == "table" and candidate.ready == true
            and candidate.willing == true
            and candidate.resting ~= true and candidate.hasTask ~= true
            and candidate.explicitOrder ~= true then
            eligible[#eligible + 1] = candidate
        end
    end
    table.sort(eligible, function(first, second)
        local firstAt = tonumber(first.lastSupplyRunAtHours) or -math.huge
        local secondAt = tonumber(second.lastSupplyRunAtHours) or -math.huge
        if firstAt ~= secondAt then return firstAt < secondAt end
        local firstRepeated = first.lastSupplyKind == shortageKind and 1 or 0
        local secondRepeated = second.lastSupplyKind == shortageKind and 1 or 0
        if firstRepeated ~= secondRepeated then return firstRepeated < secondRepeated end
        return tostring(first.id or "") < tostring(second.id or "")
    end)
    return eligible[1] ~= nil and eligible[1].id or nil
end

return Planner
