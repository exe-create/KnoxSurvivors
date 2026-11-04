local Needs = rawget(_G, "KnoxBaseNeeds") or {}
_G.KnoxBaseNeeds = Needs

local function canonicalTaskType(taskType)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        return catalog.normalizeTaskType(taskType) or taskType
    end
    return taskType
end

local function total(summary, key)
    return tonumber(summary ~= nil and summary.totals ~= nil and summary.totals[key]) or 0
end

-- Priority is a small, explainable adjustment layered over the task board's
-- persisted priority. It never creates work or stock; it only lets real loaded
-- storage shortages influence which already-queued task a resident claims.
function Needs.priorityBonus(task, summary, residentCount)
    if task == nil then return 0 end
    local rawType = task.type
    if (type(rawType) ~= "string" or rawType == "")
        and type(task.target) == "table" then
        rawType = task.target.action
    end
    local taskType = tostring(canonicalTaskType(rawType) or "")
    local people = math.max(1, tonumber(residentCount) or 1)
    local bonus = 0
    if taskType == "haul_corpse" then
        bonus = 24
    elseif taskType == "burn_corpse" then
        bonus = 24
    elseif taskType == "sort_depot" and (tonumber(summary ~= nil and summary.misplacedItems) or 0) > 0 then
        bonus = 18
    elseif taskType == "cook" or taskType == "farm_harvest" or taskType == "farm_seed" then
        if total(summary, "food") < people * 3 then bonus = 20 end
    elseif taskType == "farm_water" then
        if total(summary, "water") < people * 2 then bonus = 16 end
    elseif taskType == "barricade" or taskType == "repair" then
        if total(summary, "building") < people * 2 then bonus = 12 end
    elseif taskType == "guard" or taskType == "patrol" then
        bonus = 6
    end
    return bonus
end

local function clampPriority(value)
    return math.max(0, math.min(100, tonumber(value) or 0))
end

function Needs.apply(tasks, summary, residentCount)
    -- Test doubles and older callers may not provide a storage snapshot.  In
    -- that case leave persisted priorities untouched rather than guessing.
    -- A summary with zero loaded policies is an unknown/streamed-out stock
    -- state, not proof that the base is short on supplies. Only apply shortage
    -- bonuses when at least one assigned container was actually inspected.
    local hasSnapshot = summary ~= nil
        and (tonumber(summary.loadedPolicies) or 0) > 0
    for _, task in ipairs(tasks or {}) do
        if task ~= nil then
            local current = clampPriority(task.priority)
            local applied = tonumber(task.appliedPriority)
            if task.basePriority == nil then
                task.basePriority = current
            elseif applied ~= nil and current ~= clampPriority(applied) then
                -- The board, a work-area edit or the player changed this job's
                -- priority after the last shortage pass. That edit is now the
                -- baseline; otherwise the cached base would silently restore
                -- the old value on the next decision.
                task.basePriority = current
            end
            local base = clampPriority(task.basePriority)
            local bonus = hasSnapshot and Needs.priorityBonus(task, summary, residentCount) or 0
            task.priority = clampPriority(base + bonus)
            -- Remember exactly what this pass wrote so the next pass can tell
            -- a real external edit from our own shortage adjustment.
            task.appliedPriority = task.priority
        end
    end
    return tasks
end

return Needs
