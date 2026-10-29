require "KS_Persistence"
require "KS_BaseManager"
require "KS_OrderCatalog"

local TaskBoard = rawget(_G, "KnoxBaseTaskBoard") or {}
_G.KnoxBaseTaskBoard = TaskBoard

TaskBoard.TASK_TYPES = {
    haul = true,
    barricade = true,
    farm_seed = true,
    farm_water = true,
    farm_harvest = true,
    farm_plow = true,
    chop_tree = true,
    saw_logs = true,
    guard = true,
    patrol = true,
    haul_corpse = true, burn_corpse = true,



    repair = true,
    cook = true,
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

-- The notebook and activity feed describe the same work result. Keep exact
-- executor codes on the task record, and explain the practical next step here.
function TaskBoard.blockerText(value)
    local reason = tostring(value or "")
    if reason == "" then return nil end
    local stayingHome = reason:match("^stay_home_missing_supplies:(.*)$")
    if stayingHome ~= nil then
        return (TaskBoard.blockerText(stayingHome) or "Supplies unavailable") .. "; staying home"
    end
    local itemType = reason:match("^missing_assigned_item=(.+)$")
    if itemType ~= nil then
        local names = { ["Base.Nails"] = "nails", ["Base.Plank"] = "planks", ["Base.Log"] = "logs",
            ["Base.Hammer"] = "a hammer", ["Base.Saw"] = "a saw", ["Base.Axe"] = "an axe" }
        local name = names[itemType]
        if name == nil and getScriptManager ~= nil then
            local ok, displayName = pcall(function()
                local item = getScriptManager():FindItem(itemType)
                return item ~= nil and item:getDisplayName() or nil
            end)
            if ok and displayName ~= nil and tostring(displayName) ~= "" then name = tostring(displayName) end
        end
        return name ~= nil and ("Needs " .. name .. " in base storage")
            or "Required supply missing from base storage"
    end
    for _, prefix in ipairs({"barricade_queue:", "tree_queue:", "corpse_queue:", "repair_queue:", "farming_queue:"}) do
        if reason:sub(1, #prefix) == prefix then reason = reason:sub(#prefix + 1); break end
    end
    local labels = {
        missing_carried_nails = "Needs two nails in inventory",
        missing_carried_hammer_or_plank = "Needs a hammer and plank in inventory",
        missing_hammer_plank_or_nails = "Needs a hammer, plank and two nails",
        missing_axe = "Needs a usable axe", missing_saw = "Needs a usable saw", missing_log = "Needs a log to saw",
        repair_tool_unavailable = "Required repair tool unavailable",
        assigned_supply_entry_unavailable = "Cannot reach supplies; check storage access",
        assigned_supply_no_progress = "Cannot reach supplies; check the route to storage",
        task_move_no_progress = "Cannot reach the job; check the route",
        assigned_supply_no_longer_available = "Supplies unavailable; check base storage",
        assigned_supply_transfer_not_completed = "Supplies were not collected; check storage access",
        corpse_drop_square_unavailable = "No usable disposal tile; check the corpse area",
        cooking_heat_action_not_queued = "Could not start heating; will retry",
        missing_required_materials_after_search = "Supplies not found after searching",
    }
    if labels[reason] ~= nil then return labels[reason] end
    if reason:match("^assigned_supply_transfer_queue:") then
        return "Could not collect supplies; will retry"
    end
    if reason:match("^free_job_supplies:") then return "Test supplies unavailable; check the job requirements" end
    if reason:match("_queue_refused$") or reason:match("_queue_error$") then
        return "Could not start work; will retry"
    end
    reason = reason:gsub("_", " ")
    return reason:sub(1, 1):upper() .. reason:sub(2)
end

function TaskBoard.queue(baseId, taskType, target, requirements, priority)
    taskType = KnoxOrderCatalog.normalizeTaskType(taskType) or taskType
    if TaskBoard.TASK_TYPES[taskType] ~= true then
        return nil, "unknown_task_type"
    end
    return KnoxPersistence.queueBaseTask(
        baseId,
        taskType,
        target,
        requirements or {},
        priority
    )
end

function TaskBoard.queued(baseId)
    local base = KnoxPersistence.getBase(baseId)
    local tasks = {}
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task.state == "queued" then
            tasks[#tasks + 1] = task
        end
    end
    table.sort(tasks, function(first, second)
        local firstPriority = tonumber(first.priority) or 0
        local secondPriority = tonumber(second.priority) or 0
        if firstPriority == secondPriority then
            return tostring(first.id) < tostring(second.id)
        end
        return firstPriority > secondPriority
    end)
    return tasks
end

function TaskBoard.claimBest(baseId, survivorId, preference)
    -- Once the settlement job layer is loaded, defer to its single canonical
    -- selector.  The task board remains responsible for the atomic claim; it
    -- must not maintain a second, subtly different fairness/preference policy.
    local jobs = rawget(_G, "KnoxBaseJobs")
    if jobs ~= nil and type(jobs.selectEligibleTask) == "function" then
        local selected, result = jobs.selectEligibleTask(
            TaskBoard.queued(baseId), survivorId, baseId, preference
        )
        if selected ~= nil then
            return KnoxPersistence.claimBaseTask(
                baseId, selected.id, survivorId, worldAge()
            )
        end
        return nil, "no_eligible_task"
    end

    -- Compatibility path for early-load callers and focused tests that use the
    -- task board before KS_BaseJobs has been required.
    local selected, selectedScore = nil, nil
    local passes = (preference ~= nil and preference ~= "" and preference ~= "auto") and 2 or 1
    for pass = 1, passes do
        for _, task in ipairs(TaskBoard.queued(baseId)) do
            local preferred = KnoxOrderCatalog.preferenceMatchesTask(
                preference, task ~= nil and task.type or nil
            )
            if ((pass == 1 and preferred) or (pass == 2 and not preferred))
                and KnoxBaseManager.canPerformTask(survivorId, baseId, task) then
                local score = tonumber(task.priority) or 0
                if task.lastClaimedBy == survivorId then score = score - 18 end
                local lastClaimed = tonumber(task.lastClaimedAtHours)
                if lastClaimed ~= nil then
                    local recentHours = math.max(0, 12 - math.max(0, worldAge() - lastClaimed))
                    score = score - math.min(12, recentHours * 2)
                end
                local id = tostring(task.id or "")
                if selected == nil or score > selectedScore
                    or (score == selectedScore and id < tostring(selected.id or "")) then
                    selected, selectedScore = task, score
                end
            end
        end
        if selected ~= nil then break end
    end
    if selected ~= nil then
        return KnoxPersistence.claimBaseTask(
            baseId,
            selected.id,
            survivorId,
            worldAge()
        )
    end
    return nil, "no_eligible_task"
end

-- Continue targets created by an explicit player order without enabling
-- autonomous work. Every target still passes capability checks and the same
-- atomic persistence claim as other tasks.
function TaskBoard.claimBestManualOrder(baseId, survivorId)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return nil, "base_unavailable" end
    local now = worldAge()
    local candidates = {}
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.manualOrder == true then
            if task.state == "blocked" and now >= (tonumber(task.retryAtHours) or 0)
                and KnoxPersistence.requeueBaseTask ~= nil then
                KnoxPersistence.requeueBaseTask(baseId, task.id, now)
            end
            if task.state == "queued" then
                candidates[#candidates + 1] = task
            end
        end
    end
    table.sort(candidates, function(first, second)
        local firstPriority = tonumber(first.priority) or 0
        local secondPriority = tonumber(second.priority) or 0
        if firstPriority == secondPriority then
            return tostring(first.id) < tostring(second.id)
        end
        return firstPriority > secondPriority
    end)
    for _, task in ipairs(candidates) do
        if KnoxBaseManager.canPerformTask(survivorId, baseId, task) then
            local claimed, result = KnoxPersistence.claimBaseTask(
                baseId, task.id, survivorId, now
            )
            if claimed ~= nil and result == "claimed" then
                claimed.manual = true
                claimed.auto = nil
                claimed.manualOrder = true
                return claimed, result
            end
        end
    end
    return nil, "no_eligible_order_task"
end

-- Player-directed assignment uses the same atomic persistence boundary as
-- automatic work selection.  The notebook may choose a concrete queued task,
-- but it must not bypass base ownership, resident eligibility, skill gates, or
-- the one-active-task-per-resident invariant.
function TaskBoard.canClaimSpecific(baseId, taskId, survivorId, playerId)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if base == nil or base.ownerKind ~= "player"
        or tostring(base.ownerId or "") ~= tostring(playerId or "") then
        return false, "not_your_base"
    end
    -- Keep resident ownership authoritative at the task boundary as well as
    -- in the Notebook picker. Future callers must not assign a faction or
    -- independent survivor by knowing only a task and base id.
    local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
        and KnoxPersistence.getSurvivorAffiliation(survivorId) or nil
    if affiliation == nil or affiliation.kind ~= "player"
        or tostring(affiliation.ownerId or "") ~= tostring(playerId or "") then
        return false, "not_player_resident"
    end
    if task == nil or task.state ~= "queued" then
        return false, "unavailable"
    end
    for _, existing in pairs(base.tasks or {}) do
        if existing.state == "claimed" and existing.claimedBy == survivorId then
            return false, "already_claimed_task"
        end
    end
    if KnoxBaseManager.canPerformTask ~= nil
        and not KnoxBaseManager.canPerformTask(survivorId, baseId, task) then
        return false, "not_eligible"
    end
    return true, "eligible"
end

function TaskBoard.claimSpecific(baseId, taskId, survivorId, playerId)
    -- The picker may inspect candidates without speaking to each unavailable
    -- resident. Recheck here; persistence still owns the atomic claim.
    local allowed, reason = TaskBoard.canClaimSpecific(baseId, taskId, survivorId, playerId)
    if not allowed then return nil, reason end
    local assigned, result = KnoxPersistence.claimBaseTask(
        baseId,
        taskId,
        survivorId,
        worldAge()
    )
    if assigned ~= nil and result == "claimed" then
        -- Preserve the distinction between an explicit player assignment and
        -- an automatic duty claim only after the atomic claim succeeds. A
        -- rejected/concurrent claim must not mutate a queued task.
        assigned.manual = true
        assigned.auto = nil
        -- Failure clears the transient claim flags. Keep this explicit order
        -- eligible for the existing retry lane until success or cancellation.
        assigned.manualOrder = true
    end
    return assigned, result
end

function TaskBoard.finish(baseId, taskId, survivorId, succeeded, reason)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId then
        return nil, "not_claimed_by_survivor"
    end
    local finished, result = KnoxPersistence.finishBaseTask(
        baseId,
        taskId,
        survivorId,
        succeeded == true,
        reason,
        worldAge()
    )
    if finished == nil then
        return nil, result
    end
    return finished, succeeded and "complete" or "blocked"
end

return TaskBoard
