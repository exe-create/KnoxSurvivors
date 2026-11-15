local Duty = rawget(_G, "KnoxBaseDutySimulation") or {}
_G.KnoxBaseDutySimulation = Duty

local SHIFT_HOURS = 4

local function canonicalTaskType(taskType)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        return catalog.normalizeTaskType(taskType) or taskType
    end
    return taskType
end

function Duty.canAdvanceOffscreen(task)
    local kind = task ~= nil and tostring(canonicalTaskType(task.type) or "") or ""
    return kind == "guard" or kind == "patrol"
end

-- Labour against stock is a different question from a watch shift, so it gets
-- its own predicate: a claimed job may accumulate worked hours unloaded only
-- when every item it needs is already counted in the base's assigned storage.
-- Anything unproven fails closed: no hours, no consumption, no completion.
-- canAdvanceOffscreen keeps its watch-only meaning because its result also
-- gates the return walk in KS_UnloadedSurvival.
function Duty.canAdvanceLaborOffscreen(base, task, countAssigned)
    if base == nil or task == nil or task.state ~= "claimed" then
        return false, "not_claimed"
    end
    if Duty.canAdvanceOffscreen(task) then return false, "watch_shift" end
    if type(countAssigned) ~= "function" then return false, "storage_unavailable" end
    local requirements = type(task.requirements) == "table" and task.requirements or nil
    local items = requirements ~= nil and requirements.items or nil
    if type(items) ~= "table" then return false, "no_requirement" end
    local checked = 0
    for fullType, required in pairs(items) do
        local need = tonumber(required) or 0
        if need > 0 then
            local ok, have = pcall(countAssigned, fullType, requirements)
            if not ok or (tonumber(have) or 0) < need then
                return false, "material_missing:" .. tostring(fullType)
            end
            checked = checked + 1
        end
    end
    if checked == 0 then return false, "no_requirement" end
    return true, "stored_materials"
end

-- Worked hours only, using the field this module already keeps on a claimed
-- task. The shift counter stays the watch's own record, and no branch here can
-- complete a task, consume stock or move the resident.
function Duty.advanceLabor(base, task, elapsed, countAssigned)
    local allowed, reason = Duty.canAdvanceLaborOffscreen(base, task, countAssigned)
    if allowed ~= true then return false, 0, reason end
    local hours = math.max(0, tonumber(elapsed) or 0)
    task.offscreenWorkHours = math.min(1000000,
        (tonumber(task.offscreenWorkHours) or 0) + hours)
    return true, hours, "stored_materials"
end

-- Only abstractable watch shifts advance here.  World-changing jobs remain
-- claimed and resume in the loaded engine where their native action can run.
function Duty.advance(task, elapsed)
    if task == nil or task.state ~= "claimed" or not Duty.canAdvanceOffscreen(task) then
        return false, 0
    end
    local hours = math.max(0, tonumber(elapsed) or 0)
    local accumulated = (tonumber(task.offscreenWorkHours) or 0) + hours
    local completedShifts = math.floor(accumulated / SHIFT_HOURS)
    task.offscreenWorkHours = accumulated - completedShifts * SHIFT_HOURS
    if completedShifts <= 0 then
        return false, task.offscreenWorkHours
    end
    -- This records time on duty, not permission to finish the order. Keep the
    -- claim and actual waypoint evidence until the player releases the watch.
    -- Streaming cannot invent a patrol arrival or a replacement guard.
    task.offscreenShiftsCompleted = math.min(1000000,
        (tonumber(task.offscreenShiftsCompleted) or 0) + completedShifts)
    return true, completedShifts * SHIFT_HOURS
end

return Duty
