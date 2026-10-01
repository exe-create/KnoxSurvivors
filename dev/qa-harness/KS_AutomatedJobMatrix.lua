-- Disposable live QA for base-job discovery and resident admission.
--
-- This matrix deliberately stops at the native task boundary. A queued and
-- claimed task proves that the work area, requirements, resident duty and
-- atomic task board agree. The actual timed action still has to report its
-- native end state before a job can be considered fully live-verified.
require "KS_BaseJobs"
require "KS_BaseTaskBoard"
require "KS_BaseManager"

local Matrix = rawget(_G, "KnoxAutomatedJobMatrix") or {}
_G.KnoxAutomatedJobMatrix = Matrix

local STEPS = {
    { name = "job_guard_admission", types = { guard = true }, preference = "guard", zone = "guard", persistent = true },
    { name = "job_patrol_admission", types = { patrol = true }, preference = "patrol", zone = "patrol", persistent = true },
    { name = "job_farming_admission", types = { farm_water = true, farm_harvest = true, farm_plow = true, farm_seed = true }, preference = "farming", zone = "farming" },
    { name = "job_woodcutting_admission", types = { chop_tree = true }, preference = "woodwork", zone = "woodcutting" },
    { name = "job_saw_logs_admission", types = { saw_logs = true }, preference = "woodwork", zone = "log_processing" },
    { name = "job_barricade_admission", types = { barricade = true }, preference = "barricade" },
    { name = "job_repair_admission", types = { repair = true }, preference = "repair" },
    { name = "job_cooking_admission", types = { cook = true }, preference = "auto", zone = "cooking" },
    { name = "job_corpse_haul_admission", types = { haul_corpse = true }, preference = "hauling", zone = "corpse" },
}

local ENTRY_TIMEOUT_TICKS = 600
local COMPLETION_TIMEOUT_TICKS = 3600

local EXECUTION_STATES = {
    BASE_TASK_MOVE = true,
    BASE_TASK_WORK = true,
    BASE_TASK_ACTION = true,
    BASE_TASK_PATROL_WAIT = true,
    BASE_SECURITY_WAIT = true,
    COMPANION_GUARD = true,
    COMPANION_PATROL_WAIT = true,
}

local state = nil

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
end

local function squareForContext(context)
    if context ~= nil and context.square ~= nil then return context.square end
    local home = context ~= nil and context.base ~= nil
        and (context.base.home or context.base.territory) or nil
    if home == nil or getCell == nil or getCell() == nil then return nil end
    return getCell():getGridSquare(
        tonumber(home.x) or 0, tonumber(home.y) or 0, tonumber(home.z) or 0)
end

local function hasZone(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and tostring(zone.type) == tostring(zoneType)
            and zone.enabled ~= false then
            return zone
        end
    end
    return nil
end

local function createZone(context, zoneType, index)
    local base = context.base
    local square = squareForContext(context)
    local manager = rawget(_G, "KnoxBaseManager")
    if base == nil or square == nil or manager == nil or manager.addZone == nil then
        return nil, "zone_fixture_unavailable"
    end
    local existing = hasZone(base, zoneType)
    if existing ~= nil then return existing, "existing" end
    local offset = tonumber(index) or 0
    local x, y, z = square:getX() + offset, square:getY(), square:getZ()
    return manager.addZone(base.id, zoneType,
        { x1 = x - 2, y1 = y - 2, x2 = x + 2, y2 = y + 2, z = z },
        "Automated QA " .. tostring(zoneType))
end

local function releaseResidentClaims(keepTypes)
    local base, id = state.base, state.residentId
    local board = rawget(_G, "KnoxBaseTaskBoard")
    if base == nil or id == nil or board == nil or board.finish == nil then return end
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.state == "claimed" and task.claimedBy == id
            and (keepTypes == nil or keepTypes[tostring(task.type)] ~= true) then
            pcall(function()
                board.finish(base.id, task.id, id, false, "automated_qa_matrix_next")
            end)
        end
    end
end

local function taskFor(step)
    local base = state.base
    local selected = nil
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and step.types[tostring(task.type)]
            and (task.state == "queued"
                or task.state == "claimed" and task.claimedBy == state.residentId) then
            if selected == nil or (tonumber(task.priority) or 0) > (tonumber(selected.priority) or 0) then
                selected = task
            end
        end
    end
    return selected
end

local function targetEvidence(task)
    local target = task ~= nil and task.target or nil
    if target == nil then return "target=none" end
    return "target=" .. tostring(target.id or target.action or task.type)
        .. " x=" .. tostring(target.x or target.corpseX or "none")
        .. " y=" .. tostring(target.y or target.corpseY or "none")
        .. " z=" .. tostring(target.z or target.corpseZ or "none")
end

local function emit(entry)
    state.results[#state.results + 1] = entry
end

function Matrix.start(context)
    if context == nil or context.base == nil or context.residentId == nil
        or context.resident == nil then
        return false, "base_resident_fixture_missing"
    end
    state = {
        base = context.base,
        resident = context.resident,
        residentId = context.residentId,
        player = context.player,
        index = 0,
        nextAt = 0,
        results = {},
        finished = false,
        awaiting = nil,
    }
    print("[KnoxSurvivors][AutomatedQA] job_matrix_start steps=" .. tostring(#STEPS))
    return true, "started"
end

function Matrix.step(tick)
    if state == nil or state.finished then return end
    tick = tonumber(tick) or 0
    if tick < state.nextAt then return end
    if state.awaiting ~= nil then
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        local controller = nil
        if autonomy ~= nil and autonomy.status ~= nil then
            local ok, status = pcall(function() return autonomy.status() end)
            controller = ok and status ~= nil and status.controllers ~= nil
                and status.controllers[state.residentId] or nil
        end
        local controllerState = controller ~= nil and tostring(controller.state or "") or "missing"
        local task = state.base.tasks ~= nil
            and state.base.tasks[state.awaiting.task.id] or nil
        local taskStillOwned = controller ~= nil and controller.baseTask ~= nil
            and tostring(controller.baseTask.id or "") == tostring(state.awaiting.task.id or "")
            and controller.baseTask.claimedBy == state.residentId
        if state.awaiting.phase == "enter" then
            -- A survivor fighting, eating, or wandering while merely retaining
            -- a claim is not proof that the job runs. Require one of the real
            -- base-work states and ownership of this exact task.
            if EXECUTION_STATES[controllerState] and taskStillOwned then
                emit({
                    scenario = state.awaiting.step.name .. "_execution",
                    status = "PASS",
                    reason = "native_work_state_entered",
                    evidence = "state=" .. controllerState
                        .. " task=" .. tostring(state.awaiting.task.id),
                })
                if state.awaiting.step.persistent == true then
                    state.awaiting = nil
                    state.nextAt = tick + 15
                else
                    state.awaiting.phase = "complete"
                    state.awaiting.deadline = tick + COMPLETION_TIMEOUT_TICKS
                end
                return
            end
            -- Very short actions can finish between two matrix polls. Their
            -- persisted successful end state is stronger evidence than the
            -- transient controller state that was missed.
            if task ~= nil and task.state == "complete" then
                emit({
                    scenario = state.awaiting.step.name .. "_execution",
                    status = "PASS",
                    reason = "native_task_completed_before_poll",
                    evidence = "task=" .. tostring(task.id)
                        .. " result=" .. tostring(task.result),
                })
                emit({
                    scenario = state.awaiting.step.name .. "_completion",
                    status = "PASS",
                    reason = "native_task_completed",
                    evidence = "task=" .. tostring(task.id)
                        .. " result=" .. tostring(task.result),
                })
                state.awaiting = nil
                state.nextAt = tick + 15
                return
            end
            if task ~= nil and task.state == "blocked" then
                emit({
                    scenario = state.awaiting.step.name .. "_execution",
                    status = "FAIL",
                    reason = "native_task_blocked_before_execution",
                    evidence = "state=" .. controllerState
                        .. " task=" .. tostring(task.id)
                        .. " result=" .. tostring(task.result),
                })
                state.awaiting = nil
                state.nextAt = tick + 15
                return
            end
            if tick >= state.awaiting.deadline then
                emit({
                    scenario = state.awaiting.step.name .. "_execution",
                    status = "FAIL",
                    reason = "native_work_state_timeout",
                    evidence = "state=" .. controllerState
                        .. " task=" .. tostring(state.awaiting.task.id)
                        .. " taskState=" .. tostring(task ~= nil and task.state or "missing")
                        .. " controller=" .. tostring(controller ~= nil),
                })
                state.awaiting = nil
                state.nextAt = tick + 15
            end
            return
        end
        if task ~= nil and task.state == "complete" then
            emit({
                scenario = state.awaiting.step.name .. "_completion",
                status = "PASS",
                reason = "native_task_completed",
                evidence = "task=" .. tostring(task.id)
                    .. " result=" .. tostring(task.result),
            })
            state.awaiting = nil
            state.nextAt = tick + 15
            return
        end
        if task == nil or task.state == "blocked" then
            emit({
                scenario = state.awaiting.step.name .. "_completion",
                status = "FAIL",
                reason = task == nil and "native_task_disappeared" or "native_task_blocked",
                evidence = "state=" .. controllerState
                    .. " task=" .. tostring(state.awaiting.task.id)
                    .. " result=" .. tostring(task ~= nil and task.result or "missing"),
            })
            state.awaiting = nil
            state.nextAt = tick + 15
            return
        end
        if tick >= state.awaiting.deadline then
            emit({
                scenario = state.awaiting.step.name .. "_completion",
                status = "FAIL",
                reason = "native_task_completion_timeout",
                evidence = "state=" .. controllerState
                    .. " task=" .. tostring(state.awaiting.task.id)
                    .. " taskState=" .. tostring(task.state),
            })
            state.awaiting = nil
            state.nextAt = tick + 15
        end
        return
    end
    state.index = state.index + 1
    local step = STEPS[state.index]
    if step == nil then
        state.finished = true
        print("[KnoxSurvivors][AutomatedQA] job_matrix_complete results="
            .. tostring(#state.results))
        return
    end
    local base, jobs = state.base, rawget(_G, "KnoxBaseJobs")
    local zoneEvidence = "zone=none"
    if step.zone ~= nil then
        local zone, zoneResult = createZone(state, step.zone, state.index)
        zoneEvidence = "zone=" .. tostring(zone ~= nil) .. " zoneResult=" .. tostring(zoneResult)
    end
    -- beginBase already claims the guard fixture while proving the storage/task
    -- contract. Preserve a claim when it is the exact job this matrix is about
    -- to execute; only retire a claim left by the preceding matrix step.
    releaseResidentClaims(step.types)
    local prepared, prepResult = false, "jobs_unavailable"
    if jobs ~= nil and jobs.prepareWorkforce ~= nil then
        prepared, prepResult = jobs.prepareWorkforce(base, state.resident, nowHours())
    end
    local task = taskFor(step)
    if task == nil then
        emit({ scenario = step.name, status = "BLOCKED",
            reason = "no_native_target_fixture",
            evidence = zoneEvidence .. " prepared=" .. tostring(prepared)
                .. " prepareResult=" .. tostring(prepResult) })
        state.nextAt = tick + 30
        return
    end
    local claim = task
    local claimResult = "already_claimed"
    if task.state == "queued" then
        local board = rawget(_G, "KnoxBaseTaskBoard")
        local service = rawget(_G, "KnoxCompanionService")
        local playerId = service ~= nil and service.getPlayerId ~= nil
            and service.getPlayerId(state.player) or nil
        if board == nil or board.claimSpecific == nil then
            claim = nil
            claimResult = "task_board_unavailable"
        else
            claim, claimResult = board.claimSpecific(
                base.id, task.id, state.residentId, playerId)
        end
    end
    if claim == nil then
        emit({ scenario = step.name, status = "BLOCKED",
            reason = "task_not_claimable",
            evidence = zoneEvidence .. " task=" .. tostring(task.id)
                .. " claimResult=" .. tostring(claimResult) })
    else
        emit({ scenario = step.name, status = "PASS",
            reason = "native_task_admitted",
            evidence = zoneEvidence .. " task=" .. tostring(claim.id)
                .. " state=" .. tostring(claim.state)
                .. " claimResult=" .. tostring(claimResult)
                .. " " .. targetEvidence(claim) })
        state.awaiting = {
            step = step,
            task = claim,
            phase = "enter",
            deadline = tick + ENTRY_TIMEOUT_TICKS,
        }
    end
    state.nextAt = tick + 30
end

function Matrix.status()
    return state
end

function Matrix.cleanup()
    if state ~= nil then releaseResidentClaims() end
    state = nil
end

return Matrix
