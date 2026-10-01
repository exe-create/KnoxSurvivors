require "KS_Persistence"
require "KS_BaseTaskBoard"
require "KS_OrderCatalog"
require "KS_BaseStorage"
require "KS_BaseBarricades"
require "KS_BaseFarming"
require "KS_BaseWoodcutting"
require "KS_BaseCorpseHandling"
-- animal care retired (vanilla zones later)
require "KS_BaseCooking"
require "KS_BaseRepairs"
-- construction retired
require "KS_BaseNeeds"
require "KS_BaseSupplyPlanner"
require "KS_CompanionPatrol"
require "KS_JobTestSupplies"
require "KS_NightShelter"
require "KS_SurvivorOrigins"

local BaseJobs = rawget(_G, "KnoxBaseJobs") or {}
_G.KnoxBaseJobs = BaseJobs

-- Only jobs with a complete, reversible world executor belong here.  Keep this
-- list synchronized with the executors required by the automatic base loop:
-- zones may be persisted before their task exists, but once a supported task is
-- available it must be eligible for normal resident selection.
BaseJobs.AUTOMATIC_TYPES = {
    guard = true,
    patrol = true,
    barricade = true,
    farm_water = true,
    farm_harvest = true,
    farm_plow = true,
    farm_seed = true,
    chop_tree = true,
    saw_logs = true,
    haul_corpse = true,
    burn_corpse = true,
    repair = true,
    cook = true,
}

-- Work areas are duty destinations, never ownership or safehouse boundaries.
-- A resident already here may continue working instead of walking home between
-- every tree/crop. Disabled areas and other floors grant no such permission.
function BaseJobs.containsWorkSquare(base, square)
    if base == nil or square == nil then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and z == (tonumber(zone.z) or 0) then
            local x1, y1 = tonumber(zone.x1), tonumber(zone.y1)
            local x2, y2 = tonumber(zone.x2), tonumber(zone.y2)
            if x1 ~= nil and x2 ~= nil and y1 ~= nil and y2 ~= nil
                and x >= math.min(x1, x2) and x <= math.max(x1, x2)
                and y >= math.min(y1, y2) and y <= math.max(y1, y2) then
                return true
            end
        end
    end
    return false
end

-- Shared security accounting for the scheduler and player-facing settlement
-- views.  Keeping this beside task selection prevents migrated labels (for
-- example patrol_area) from making the Notebook disagree with the work board.
function BaseJobs.securityCoverage(base)
    local guardPosts, patrolRoutes = 0, 0
    local activeGuard, activePatrol = 0, 0
    if type(base) ~= "table" then
        return {
            guardPosts = 0, patrolRoutes = 0,
            activeGuard = 0, activePatrol = 0,
            staffed = 0, available = 0, required = 0, understaffed = 0,
        }
    end
    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" and zone.enabled ~= false then
            local zoneType = zone.type
            if zoneType == "patrol_area" then zoneType = "patrol" end
            if zoneType == "guard" then guardPosts = guardPosts + 1 end
            if zoneType == "patrol" then patrolRoutes = patrolRoutes + 1 end
        end
    end
    local residentIds = KnoxPersistence ~= nil
        and KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or nil
    local residents = {}
    if type(residentIds) == "table" then
        for _, residentId in ipairs(residentIds) do
            residents[tostring(residentId)] = true
        end
    end
    local function validClaimant(claimedBy)
        -- Focused early-load callers may not provide the persistence roster;
        -- retain their historical accounting. In the live runtime the roster
        -- exists, so only a living resident of this base counts as coverage.
        if residentIds == nil then return claimedBy ~= nil end
        if claimedBy == nil or not residents[tostring(claimedBy)] then
            return false
        end
        if KnoxPersistence.isSurvivorAlive ~= nil
            and not KnoxPersistence.isSurvivorAlive(claimedBy) then
            return false
        end
        if KnoxPersistence.isSurvivorPresent ~= nil
            and not KnoxPersistence.isSurvivorPresent(claimedBy) then
            return false
        end
        -- A resident can remain in the base roster while an event, away team,
        -- or duty handoff is in progress. Do not show that person as staffing
        -- a post until the durable duty record says they are back here.
        if KnoxPersistence.getSurvivorDuty ~= nil then
            local duty = KnoxPersistence.getSurvivorDuty(claimedBy)
            if duty ~= nil and (duty.mode ~= "base"
                or duty.baseId ~= base.id or duty.eventId ~= nil) then
                return false
            end
        end
        return true
    end
    local seenTasks = {}
    for fallbackId, task in pairs(base.tasks or {}) do
        if type(task) == "table" and task.state == "claimed"
            and validClaimant(task.claimedBy) then
            local taskId = tostring(task.id or fallbackId or "")
            if not seenTasks[taskId] then
                seenTasks[taskId] = true
                local taskType = task.type
                local catalog = rawget(_G, "KnoxOrderCatalog")
                if catalog ~= nil and catalog.normalizeTaskType ~= nil then
                    taskType = catalog.normalizeTaskType(taskType) or taskType
                end
                if taskType == "guard" then activeGuard = activeGuard + 1 end
                if taskType == "patrol" then activePatrol = activePatrol + 1 end
            end
        end
    end
    local staffed = activeGuard + activePatrol
    local available = math.max(0, guardPosts + patrolRoutes - staffed)
    local residentIds = KnoxPersistence ~= nil
        and KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or {}
    local residents = type(residentIds) == "table" and #residentIds or 0
    local required = residents >= 4 and 2 or (residents > 1 and 1 or 0)
    return {
        guardPosts = guardPosts, patrolRoutes = patrolRoutes,
        activeGuard = activeGuard, activePatrol = activePatrol,
        staffed = staffed, available = available,
        required = required, understaffed = math.max(0, required - staffed),
    }
end

-- Read-only settlement workforce projection.  The task board and survivor duty
-- records remain authoritative; this helper only gives the Notebook and other
-- player-facing views one consistent answer about who is working, resting, or
-- available.  It deliberately does not claim, release, or mutate a task.
function BaseJobs.workforceSummary(base)
    local summary = {
        residents = 0, working = 0, resting = 0, idle = 0,
        supplyRuns = 0,
        manual = 0, automatic = 0, queued = 0, claimed = 0,
        claimedBy = {}, taskTypes = {},
    }
    if type(base) ~= "table" then return summary end
    local residentIds = KnoxPersistence ~= nil
        and KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or {}
    local residentSet = {}
    for _, survivorId in ipairs(type(residentIds) == "table" and residentIds or {}) do
        residentSet[tostring(survivorId)] = true
    end
    local dutyByResident = {}
    local function validResident(survivorId)
        if not residentSet[tostring(survivorId)] then return false end
        if KnoxPersistence.isSurvivorAlive ~= nil
            and not KnoxPersistence.isSurvivorAlive(survivorId) then
            return false
        end
        if KnoxPersistence.isSurvivorPresent ~= nil
            and not KnoxPersistence.isSurvivorPresent(survivorId) then
            return false
        end
        local duty = dutyByResident[tostring(survivorId)]
        if duty == nil and KnoxPersistence.getSurvivorDuty ~= nil then
            duty = KnoxPersistence.getSurvivorDuty(survivorId)
            dutyByResident[tostring(survivorId)] = duty or false
        elseif duty == false then
            duty = nil
        end
        if duty ~= nil then
            if duty.eventId ~= nil then return false end
            if duty.mode ~= nil and duty.mode ~= "base" then return false end
            if duty.baseId ~= nil
                and tostring(duty.baseId) ~= tostring(base.id) then
                return false
            end
        end
        if KnoxPersistence.getAwayTeamForSurvivor ~= nil
            and KnoxPersistence.getAwayTeamForSurvivor(survivorId) ~= nil then
            return false
        end
        return true
    end
    local function taskTypeOf(taskType)
        local catalog = rawget(_G, "KnoxOrderCatalog")
        if catalog ~= nil and catalog.normalizeTaskType ~= nil then
            return catalog.normalizeTaskType(taskType) or taskType
        end
        return taskType
    end
    for _, task in pairs(base.tasks or {}) do
        if type(task) == "table" then
            if task.state == "queued" then
                summary.queued = summary.queued + 1
            elseif task.state == "claimed" then
                local claimant = task.claimedBy
                if claimant ~= nil and validResident(claimant) then
                    summary.claimed = summary.claimed + 1
                    local key = tostring(claimant)
                    summary.claimedBy[key] = task
                    local kind = tostring(taskTypeOf(task.type) or "task")
                    summary.taskTypes[kind] = (summary.taskTypes[kind] or 0) + 1
                    if task.manual == true then summary.manual = summary.manual + 1 end
                end
            end
        end
    end
    for _, survivorId in ipairs(type(residentIds) == "table" and residentIds or {}) do
        summary.residents = summary.residents + 1
        local key = tostring(survivorId)
        if validResident(survivorId) then
            local task = summary.claimedBy[key]
            if task ~= nil then
                summary.working = summary.working + 1
            else
                local duty = dutyByResident[key]
                local preference = duty ~= nil and tostring(duty.jobPreference or "") or ""
                if duty ~= nil and (type(duty.baseSupplyOrder) == "table"
                    or type(duty.activeSupplyRun) == "table") then
                    summary.working = summary.working + 1
                    summary.supplyRuns = summary.supplyRuns + 1
                elseif preference == "rest" then
                    summary.resting = summary.resting + 1
                else
                    summary.idle = summary.idle + 1
                end
            end
        end
    end
    summary.automatic = math.max(0, summary.claimed - summary.manual)
    return summary
end

-- Read-only settlement overview shared by management UI and diagnostics. All
-- values come from the existing task board, resident duties, security zones,
-- and real loaded containers. It never creates work, claims a task, or invents
-- stock for an unloaded container.
function BaseJobs.settlementSummary(base, worldAgeHours)
    local workforce = BaseJobs.workforceSummary(base)
    local security = BaseJobs.securityCoverage(base)
    local storage = KnoxBaseStorage ~= nil and KnoxBaseStorage.summarize ~= nil
        and KnoxBaseStorage.summarize(base)
        or { totals = {}, loadedPolicies = 0, unavailablePolicies = 0, misplacedItems = 0 }
    local result = {
        workforce = workforce,
        security = security,
        storage = storage,
        stockKnown = (tonumber(storage.loadedPolicies) or 0) > 0,
        reserves = {},
        shortages = {},
        tasks = {
            total = 0, queued = 0, claimed = 0, blocked = 0,
            cancelled = 0, complete = 0, retrying = 0,
        },
    }
    if result.stockKnown and KnoxBaseSupplyPlanner ~= nil then
        result.reserves = KnoxBaseSupplyPlanner.reserveStatus(
            storage.totals, workforce.residents)
        result.shortages = KnoxBaseSupplyPlanner.shortages(
            storage.totals, workforce.residents)
    end
    local now = tonumber(worldAgeHours)
    if now == nil and getGameTime ~= nil and getGameTime() ~= nil then
        now = tonumber(getGameTime():getWorldAgeHours()) or 0
    end
    now = now or 0
    for _, task in pairs(type(base) == "table" and base.tasks or {}) do
        if type(task) == "table" then
            local state = tostring(task.state or "queued")
            result.tasks.total = result.tasks.total + 1
            if result.tasks[state] ~= nil then
                result.tasks[state] = result.tasks[state] + 1
            end
            if state == "blocked" and (tonumber(task.retryAtHours) or 0) > now then
                result.tasks.retrying = result.tasks.retrying + 1
            end
        end
    end
    return result
end

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function zoneOf(task)
    local target = task ~= nil and task.target or nil
    local zoneId = target ~= nil and target.autoZoneId or nil
    return type(zoneId) == "string" and zoneId or nil
end

local function canonicalZoneType(zoneType)
    -- Work-area labels and executable task labels are not interchangeable in
    -- general: `farming`, for example, is a discovery area whose finder emits
    -- a concrete farm action. Only the historical patrol-area label is safe to
    -- converge here because it already represents the recurring patrol work.
    if zoneType == "patrol_area" then return "patrol" end
    return zoneType
end

local function sortedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        local zoneType = zone ~= nil and canonicalZoneType(zone.type) or nil
        local executableZone = zone ~= nil
        if executableZone and zone.enabled ~= false
            and BaseJobs.AUTOMATIC_TYPES[zoneType] == true then
            if zoneType == zone.type then
                zones[#zones + 1] = zone
            else
                -- Keep the persisted zone untouched. The scheduler uses a
                -- shallow runtime view so migrated labels cannot create a
                -- second zone or alter the player's saved work-area name.
                local runtimeZone = {}
                for key, value in pairs(zone) do runtimeZone[key] = value end
                runtimeZone.type = zoneType
                zones[#zones + 1] = runtimeZone
            end
        end
    end
    table.sort(zones, function(first, second)
        local firstPriority = tonumber(first.priority) or 50
        local secondPriority = tonumber(second.priority) or 50
        if firstPriority == secondPriority then
            return tostring(first.id) < tostring(second.id)
        end
        return firstPriority > secondPriority
    end)
    return zones
end

local function taskForZone(base, zone)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and zoneOf(task) == zone.id then
            return task
        end
    end
    return nil
end

local function taskForTargetId(base, targetId)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and task.target ~= nil
            and tostring(task.target.id or "") == tostring(targetId) then
            return task
        end
    end
    return nil
end

local function reopenWhenReady(task, now)
    if task ~= nil and task.state == "cancelled" then
        return nil
    end
    if task == nil or (task.state ~= "complete" and task.state ~= "blocked") then
        return task
    end
    local retryAt = tonumber(task.retryAtHours) or 0
    if now < retryAt then
        return nil
    end
    local reopened, result = KnoxPersistence.requeueBaseTask(
        task.baseId,
        task.id,
        now
    )
    if reopened ~= nil then
        return reopened
    end
    print("[KnoxSurvivors][BaseJobs] reopen-failed task=" .. tostring(task.id)
        .. " result=" .. tostring(result))
    return nil
end

local function taskTarget(zone)
    return {
        auto = true,
        autoZoneId = zone.id,
        zoneType = canonicalZoneType(zone.type),
        x1 = tonumber(zone.x1) or 0,
        y1 = tonumber(zone.y1) or 0,
        x2 = tonumber(zone.x2) or tonumber(zone.x1) or 0,
        y2 = tonumber(zone.y2) or tonumber(zone.y1) or 0,
        z = tonumber(zone.z) or 0,
    }
end

local function itemRequirements(...)
    local items = {}
    local hasItems = false
    -- Kahlua does not expose Lua's select(). pairs also preserves arguments
    -- after an optional nil requirement, unlike ipairs or a length loop.
    for _, fullType in pairs({ ... }) do
        if type(fullType) == "string" and fullType ~= "" then
            items[fullType] = (items[fullType] or 0) + 1
            hasItems = true
        end
    end
    return hasItems and { items = items } or {}
end


local function requireUsableItem(requirements, fullType, rule)
    if type(fullType) ~= "string" or fullType == "" then return end
    requirements.itemRules = requirements.itemRules or {}
    requirements.itemRules[fullType] = rule or { usable = true }
end

-- Discovery must move past a claimed or cooling-down target, otherwise one
-- blocked plot/trough prevents every other resident from finding useful work.
local function availableWorkFilter(base, now, family)
    local excluded, occupied = {}, {}
    local function location(target)
        if target == nil then return nil end
        if target.corpseItemId ~= nil then return "body:" .. tostring(target.corpseItemId) end
        if target.corpseX ~= nil and target.corpseY ~= nil then
            return "body:" .. tostring(target.corpseX) .. ":" .. tostring(target.corpseY)
                .. ":" .. tostring(target.corpseZ or 0) .. ":" .. tostring(target.corpseIndex or "unknown")
        end
        if target.x == nil or target.y == nil then return nil end
        return tostring(target.x) .. ":" .. tostring(target.y) .. ":" .. tostring(target.z or 0)
    end
    for _, task in pairs(base.tasks or {}) do
        local belongs = type(family) == "table" and family[task.type] == true
            or type(family) == "string" and string.sub(tostring(task.type), 1, #family) == family
        if task.target ~= nil and belongs then
            if task.state == "claimed" or task.state == "cancelled"
                or ((task.state == "blocked" or task.state == "complete")
                    and now < (tonumber(task.retryAtHours) or 0)) then
                if task.target.id ~= nil then excluded[tostring(task.target.id)] = true end
            end
            if task.state == "claimed" then
                local key = location(task.target)
                if key ~= nil then occupied[key] = true end
            end
        end
    end
    return function(target)
        local key = location(target)
        return not excluded[tostring(target.id)] and (key == nil or not occupied[key])
    end
end

local function ensureBarricadeTask(base, now, character)
    local priority = 95
    -- Player bases board windows only on player order (right-click order or
    -- Notebook assignment): automatic discovery would spend the player's
    -- planks/nails without being asked. NPC faction bases keep automatic
    -- defense boarding. Overridable per base via settings.autoBarricade.
    local autoSetting = base ~= nil and base.settings ~= nil
        and base.settings.autoBarricade or nil
    local allowAuto = (base == nil or base.ownerKind ~= "player")
    if autoSetting ~= nil then
        allowAuto = autoSetting == true
    end
    if not allowAuto then
        return nil, "manual_barricade_only"
    end
    if character == nil or not KnoxBaseBarricades.canPrepare(character, base) then
        return nil, "missing_barricade_materials"
    end
    local target = KnoxBaseBarricades.findTarget(base, character,
        availableWorkFilter(base, now, { repair = true, barricade = true }))
    if target == nil then
        return nil, "no_unbarricaded_window"
    end
    local hammer = KnoxBaseBarricades.findHammer(character, base)
    local hammerType = hammer ~= nil and hammer:getFullType() or "Base.Hammer"
    local requirements = itemRequirements(hammerType, "Base.Plank", "Base.Nails", "Base.Nails")
    requireUsableItem(requirements, hammerType)
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "claimed" or existing.manual == true then
            return existing, "existing"
        end
        if existing.state == "queued" then
            existing.target, existing.requirements = target, requirements
            existing.priority = priority
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target, reopened.requirements = target, requirements
            reopened.priority = priority
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "barricade",
        target,
        requirements,
        priority
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function farmingPriority(action)
    return action == "farm_harvest" and 100 or action == "farm_water" and 95
        or action == "farm_seed" and 85 or action == "farm_plow" and 80 or nil
end

local function ensureFarmingTask(base, now, character)
    local target = KnoxBaseFarming.findTask(base, character, availableWorkFilter(base, now, "farm_"))
    if target == nil then
        return nil, "no_farming_action_ready"
    end
    local priority = farmingPriority(target.action)
    local requirements = itemRequirements(target.waterItemType, target.plowToolType, target.seedItemType)
    requireUsableItem(requirements, target.plowToolType)
    requireUsableItem(requirements, target.waterItemType, { water = true })
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "claimed" or existing.manual == true then
            return existing, "existing"
        end
        if existing.state == "queued" then
            existing.target, existing.requirements = target, requirements
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target, reopened.requirements = target, requirements
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        target.action,
        target,
        requirements,
        priority
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureWoodcuttingTask(base, now, character)
    local target, discovery = KnoxBaseWoodcutting.findTask(base, character,
        availableWorkFilter(base, now, { chop_tree = true, saw_logs = true }))
    if target == nil then
        return nil, discovery or "no_tree_ready"
    end
    local requirements = itemRequirements(target.axeType, target.logType, target.sawType)
    requireUsableItem(requirements, target.axeType)
    requireUsableItem(requirements, target.sawType)
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "claimed" or existing.manual == true then
            return existing, "existing"
        end
        if existing.state == "queued" then
            existing.target, existing.requirements = target, requirements
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target, reopened.requirements = target, requirements
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        target.action,
        target,
        requirements,
        target.action == "saw_logs" and 78 or 75
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureCorpseTask(base, now, character)
    local target, discovery = KnoxBaseCorpseHandling.findTask(base, character,
        availableWorkFilter(base, now, "haul_corpse"))
    if target == nil then
        return nil, discovery or "no_corpse_ready"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "haul_corpse",
        target,
        {},
        92
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureBurnTask(base, now, character)
    if KnoxBaseCorpseHandling == nil or KnoxBaseCorpseHandling.findBurnTask == nil then
        return nil, "no_burn_ready"
    end
    local target, discovery = KnoxBaseCorpseHandling.findBurnTask(base, character,
        availableWorkFilter(base, now, { burn_corpse = true }))
    if target == nil then
        return nil, discovery or "no_burn_ready"
    end
    -- Burning needs a lighter in inventory or assigned storage.
    local requirements = { items = { ["Base.Lighter"] = 1 } }
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            reopened.requirements = requirements
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "burn_corpse",
        target,
        requirements,
        93
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureRepairTask(base, now, character)
    local target = KnoxBaseRepairs.findTask(base, character,
        availableWorkFilter(base, now, { repair = true, barricade = true }))
    if target == nil then
        return nil, "no_repair_ready"
    end
    local requirements = { items = target.requiredItems or {}, itemRules = target.requiredItemRules or {} }
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "claimed" then return existing, "existing" end
        if existing.state == "queued" then
            existing.target, existing.requirements = target, requirements
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            reopened.requirements = requirements
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "repair",
        target,
        requirements,
        94
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureCookingTask(base, now, character)
    local target,reason = KnoxBaseCooking.findTask(base,character)
    if target == nil then return nil,reason end
    local existing = taskForTargetId(base,target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then return existing,"existing" end
        local reopened = reopenWhenReady(existing,now)
        if reopened ~= nil then reopened.target,reopened.requirements=target,{};return reopened,"reopened" end
        return nil,"retry_not_ready"
    end
    local task,result=KnoxBaseTaskBoard.queue(base.id,"cook",target,{},85)
    if task ~= nil then task.baseId,task.auto,task.retryAtHours=base.id,true,now end
    return task,result
end

-- Player preferences only break otherwise equal selector choices. They never
-- replace queued task urgency, existing settlement scoring, eligibility, or
-- the task board's atomic claim. For overlapping groups, an allowed group
-- keeps the task eligible and the strongest state wins.
local WORK_PREFERENCE_RANK = { high = 3, normal = 2, low = 1 }
local function workPreferenceRank(preferences, taskType)
    if type(preferences) ~= "table" then return 2, false end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    local groups = catalog ~= nil and catalog.preferenceTaskGroups or nil
    if type(groups) ~= "table" then return 2, false end
    local key = tostring(taskType or "")
    local best, owned, allowed = nil, false, false
    for groupKey, set in pairs(groups) do
        if type(set) == "table" and set[key] == true then
            owned = true
            local state = preferences[groupKey] or "normal"
            if state ~= "disabled" then
                allowed = true
                local rank = WORK_PREFERENCE_RANK[state] or 2
                if best == nil or rank > best then best = rank end
            else
                -- A task can belong to more than one group. Disabled excludes
                -- it only when every owning group is disabled.
            end
        end
    end
    if owned and not allowed then return 2, true end
    return best or 2, false
end

local function matchesPreference(task, preference)
    local taskType = task ~= nil and task.type or nil
    if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeTaskType ~= nil then
        taskType = KnoxOrderCatalog.normalizeTaskType(taskType) or taskType
    end
    return KnoxOrderCatalog.preferenceMatchesTask(preference, taskType)
end

-- Task records can outlive the code that created them. Keep every scheduler
-- comparison on the same canonical type used by the order catalogue so legacy
-- labels do not split fairness, security coverage, or rotation accounting.
local function canonicalTaskType(taskType)
    if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeTaskType ~= nil then
        return KnoxOrderCatalog.normalizeTaskType(taskType) or taskType
    end
    return taskType
end

-- RimWorld-style duty schedule assignment for a base resident. Sleep and
-- recreation are no-work windows honored by the controller bypass (same as
-- explicit rest); work defers to preference/skill/rotation; anything (and
-- any non-base duty, missing record, or player survivor without a schedule)
-- preserves historical behavior exactly. NPC groups/factions receive the
-- default clock once, lazily, on first read.
function BaseJobs.scheduleAssignment(survivorId)
    local persistence = KnoxPersistence
    if survivorId == nil or persistence == nil
        or persistence.getSurvivorDuty == nil then
        return "anything"
    end
    local duty = persistence.getSurvivorDuty(survivorId)
    if type(duty) ~= "table" or duty.mode ~= "base" then
        return "anything"
    end
    local schedule = duty.schedule
    if schedule == nil and persistence.getSurvivorAffiliation ~= nil
        and persistence.ensureAutoDutySchedule ~= nil then
        local affiliation = persistence.getSurvivorAffiliation(survivorId)
        if type(affiliation) == "table" and affiliation.kind ~= "player" then
            if persistence.ensureAutoDutySchedule(survivorId, worldAge()) then
                schedule = persistence.getDutySchedule(survivorId)
            end
        end
    end
    if schedule == nil or persistence.scheduleAssignmentFor == nil then
        return "anything"
    end
    local hour = KnoxNightShelter ~= nil and KnoxNightShelter.currentHour ~= nil
        and KnoxNightShelter.currentHour() or 12
    return persistence.scheduleAssignmentFor(schedule, hour)
end

-- Skills are a bounded tie-breaker, not a new assignment system.  Hard task
-- requirements still belong to BaseManager.canPerformTask; this only lets an
-- eligible carpenter/farmer/medic/security worker win an otherwise comparable
-- duty instead of relying on queue order.
local TASK_SKILL_HINTS = {
    barricade = "Woodwork", repair = "Mechanics",
    chop_tree = "Axe", saw_logs = "Woodwork",
    farm_seed = "Farming", farm_water = "Farming", farm_harvest = "Farming",
    farm_plow = "Farming", guard = "Aiming", patrol = "Aiming",
    haul_corpse = "Strength", cook = "Cooking",
}

local function skillAffinity(survivorId, taskType)
    local canonicalType = KnoxOrderCatalog ~= nil
        and KnoxOrderCatalog.normalizeTaskType ~= nil
        and KnoxOrderCatalog.normalizeTaskType(taskType)
        or taskType
    local perkId = TASK_SKILL_HINTS[tostring(canonicalType or "")]
    if perkId == nil or survivorId == nil
        or KnoxPersistence == nil or KnoxPersistence.getSurvivorCapabilities == nil
        or KnoxSurvivorCapabilities == nil or KnoxSurvivorCapabilities.skillLevel == nil then
        return 0
    end
    local profile = KnoxPersistence.getSurvivorCapabilities(survivorId)
    local level = tonumber(KnoxSurvivorCapabilities.skillLevel(profile, perkId)) or 0
    return math.min(12, math.max(0, level * 2))
end

-- Player-selected roles stay authoritative.  For residents left on Auto, use
-- the already-persisted profession as a light hint so a carpenter naturally
-- gravitates toward woodwork and a police/veteran survivor toward security.
-- This is only a selection hint: eligibility, task priority, and fairness still
-- decide the actual job, and no duty record is rewritten.
function BaseJobs.effectivePreference(duty, profile)
    local selected = duty ~= nil and duty.jobPreference or nil
    -- Legacy/player-facing labels are normalized before the scheduler makes a
    -- role decision. This keeps migrated duty records on the same canonical
    -- vocabulary used by persistence and task matching.
    local normalized = KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(selected)
        or KnoxOrderCatalog.normalize(selected)
    if normalized ~= nil and KnoxOrderCatalog.isBasePreference(normalized) then
        selected = normalized
    end
    -- Retired preferences fall back to automatic instead of matching nothing.
    if selected == "construction" then return "auto" end
    if selected ~= nil and selected ~= "" and selected ~= "auto" then return selected end
    return KnoxSurvivorOrigins.jobPreference(
        profile ~= nil and profile.professionId or nil
    ) or "auto"
end

-- Pick one task for a resident without letting a recurring task monopolize the
-- whole settlement.  lastClaimedBy is persisted on the task, so this remains
-- stable across unload/reload without introducing another scheduler database.
-- Preference remains a hard first pass (with the existing fallback pass), while
-- the fairness penalty only breaks near-equal choices.
function BaseJobs.selectEligibleTask(tasks, survivorId, baseId, preference, canPerform)
    if tasks == nil then return nil, nil end
    -- Direct task-board callers may still pass a familiar legacy label. Keep
    -- selection on the same canonical vocabulary as the order service before
    -- calculating preferred passes or comparing task groups.
    preference = (KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(preference)
        or KnoxOrderCatalog.normalize(preference)) or preference
    canPerform = canPerform or function(id, targetBase, task)
        return KnoxBaseManager.canPerformTask(id, targetBase, task)
    end
    local preferredPasses = (preference ~= nil and preference ~= "auto") and 2 or 1
    local fairnessPenalty = 18
    -- Keep a settlement from assigning every resident to the same kind of
    -- work when several useful task types are available. This is only a
    -- bounded tie-break penalty; priority and eligibility still win.
    local activeByType = {}
    local seenTaskIds = {}
    local function countClaimed(task, fallbackKey)
        if task == nil or task.state ~= "claimed" then return end
        local key = tostring(task.id or fallbackKey or "")
        if seenTaskIds[key] then return end
        seenTaskIds[key] = true
        local taskType = tostring(canonicalTaskType(task.type) or "")
        activeByType[taskType] = (activeByType[taskType] or 0) + 1
    end
    for _, task in ipairs(tasks) do
        countClaimed(task)
    end
    -- Callers normally pass only the queued snapshot.  Read the persisted base
    -- task table as well so active security/work counts are not silently lost
    -- between scheduler ticks.  This affects only scoring; queued-task
    -- eligibility and the atomic claim remain unchanged.
    local persistedBase = KnoxPersistence ~= nil
        and KnoxPersistence.getBase ~= nil
        and KnoxPersistence.getBase(baseId) or nil
    for taskId, task in pairs(persistedBase ~= nil and persistedBase.tasks or {}) do
        countClaimed(task, taskId)
    end
    local residentCount = 0
    if KnoxPersistence.getBaseResidentIds ~= nil then
        local residentIds = KnoxPersistence.getBaseResidentIds(baseId)
        residentCount = type(residentIds) == "table" and #residentIds or 0
    end
    local activeSecurity = (activeByType.guard or 0) + (activeByType.patrol or 0)
    -- A resident's last completed/claimed duty is a soft rotation hint. It
    -- keeps an automatic workforce from handing the same person the same
    -- recurring job forever, while leaving explicit preferences and urgent
    -- settlement work authoritative.
    local previousJobType = nil
    if survivorId ~= nil and KnoxPersistence.getSurvivorDuty ~= nil then
        local duty = KnoxPersistence.getSurvivorDuty(survivorId)
        if type(duty) == "table" then
            previousJobType = tostring(canonicalTaskType(duty.lastJobType) or "")
            if previousJobType == "" then previousJobType = nil end
        end
    end
    -- Work preferences apply only to a player-owned resident at this exact
    -- base. Active companions, independent survivors, and faction residents
    -- keep their existing autonomous behavior.
    local workPreferences = nil
    if survivorId ~= nil and KnoxPersistence.getWorkPreferences ~= nil
        and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorAffiliation ~= nil then
        local duty = KnoxPersistence.getSurvivorDuty(survivorId)
        local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
        local base = KnoxPersistence.getBase ~= nil
            and KnoxPersistence.getBase(baseId) or nil
        if type(duty) == "table" and duty.mode == "base"
            and tostring(duty.baseId or "") == tostring(baseId or "")
            and type(affiliation) == "table" and affiliation.kind == "player"
            and affiliation.ownerId == duty.ownerId
            and base ~= nil and base.ownerKind == "player"
            and base.ownerId == affiliation.ownerId then
            workPreferences = KnoxPersistence.getWorkPreferences(survivorId)
        end
    end
    -- Keep the perimeter covered without turning every resident into a guard.
    -- Small camps need one watch; established bases get a second watcher so a
    -- single resident can take a break or handle another urgent task.
    local desiredSecurity = residentCount >= 4 and 2 or 1
    local preferredSecurityType = (activeByType.guard or 0) <= (activeByType.patrol or 0)
        and "guard" or "patrol"
    -- Automatic workers fill the settlement's minimum watch before taking
    -- routine work. Explicit non-security roles remain player-authoritative.
    -- This is a selection pass over the existing queue, not another scheduler:
    -- the task board still performs the one atomic claim.
    local currentNeedsRelief = false
    if residentCount > 1 and survivorId ~= nil then
        for _, task in ipairs(tasks) do
            local taskType = task ~= nil and canonicalTaskType(task.type) or nil
            if task ~= nil and (taskType == "guard" or taskType == "patrol")
                and task.lastClaimedBy == survivorId then
                currentNeedsRelief = true
                break
            end
        end
    end
    local mustFillSecurity = residentCount > 1 and activeSecurity < desiredSecurity
        and not currentNeedsRelief
        and (preference == nil or preference == "auto"
            or preference == "guard" or preference == "patrol")
    local selectionModes = mustFillSecurity and { true, false } or { false }
    for _, securityOnly in ipairs(selectionModes) do
        for pass = 1, preferredPasses do
            local best, bestScore, bestId, bestPreferenceRank = nil, nil, nil, nil
            for _, task in ipairs(tasks) do
            -- A stale or concurrently claimed record may still be present in a
            -- caller's snapshot. Count it for coverage/fairness above, but
            -- never hand ownership of it to another resident.
            local available = task.state == nil or task.state == "queued"
            local preferred = matchesPreference(task, preference)
            local taskType = canonicalTaskType(task.type)
            local securityTask = taskType == "guard" or taskType == "patrol"
            local preferenceRank, preferenceExcluded = workPreferenceRank(
                workPreferences, taskType
            )
            if available and (not securityOnly or securityTask)
                and ((pass == 1 and preferred) or (pass == 2 and not preferred)) then
                local eligible = survivorId == nil or canPerform(survivorId, baseId, task)
                if eligible and preferenceExcluded ~= true then
                    local score = tonumber(task.priority) or 0
                    local activeOfType = activeByType[tostring(taskType or "")] or 0
                    score = score - math.min(12, activeOfType * 4)
                    score = score + skillAffinity(survivorId, taskType)
                    -- Once the minimum-watch selection pass has admitted a
                    -- security task, prefer the less-covered kind. After the
                    -- minimum is filled, this remains only a bounded scoring
                    -- hint and ordinary settlement priorities take over.
                    if residentCount > 1 and activeSecurity < desiredSecurity
                        and (taskType == "guard" or taskType == "patrol") then
                        score = score + 15
                        if taskType == preferredSecurityType then
                            score = score + 3
                        end
                    end
                    if survivorId ~= nil and task.lastClaimedBy == survivorId then
                        local repeatPenalty = fairnessPenalty
                        if residentCount > 1
                            and (taskType == "guard" or taskType == "patrol") then
                            -- Prefer relief for recurring watch posts. This is
                            -- still a soft penalty: the same resident may take
                            -- the post when no other eligible worker exists.
                            repeatPenalty = repeatPenalty + 12
                        end
                        score = score - repeatPenalty
                    end
                    if previousJobType ~= nil
                        and previousJobType == tostring(taskType or "") then
                        -- Keep this deliberately smaller than priority,
                        -- security coverage, and an explicit role preference.
                        score = score - 8
                    end
                    local lastClaimed = tonumber(task.lastClaimedAtHours)
                    if lastClaimed ~= nil then
                        local recentHours = math.max(0, 12 - math.max(0, worldAge() - lastClaimed))
                        score = score - math.min(12, recentHours * 2)
                    end
                    local taskId = tostring(task.id or "")
                    if best == nil or score > bestScore
                        or (score == bestScore and preferenceRank > bestPreferenceRank)
                        or (score == bestScore and preferenceRank == bestPreferenceRank
                            and taskId < bestId) then
                        best, bestScore, bestId = task, score, taskId
                        bestPreferenceRank = preferenceRank
                    end
                end
            end
            end
            if best ~= nil then
                return best, pass == 1
                    and (survivorId == nil and "ready" or "preferred_ready")
                    or "fallback_ready"
            end
        end
    end
    return nil, nil
end

local workforcePreparation = setmetatable({}, { __mode = "k" })

local function workforceSignature(base)
    local parts = {}
    for key, zone in pairs(base ~= nil and base.zones or {}) do
        if type(zone) == "table" then
            parts[#parts + 1] = "z:" .. tostring(zone.id or key)
                .. ":" .. tostring(zone.type) .. ":" .. tostring(zone.enabled ~= false)
        end
    end
    for key, task in pairs(base ~= nil and base.tasks or {}) do
        if type(task) == "table" then
            parts[#parts + 1] = "t:" .. tostring(task.id or key)
                .. ":" .. tostring(task.type) .. ":" .. tostring(task.state)
                .. ":" .. tostring(task.claimedBy or "")
                .. ":" .. tostring(task.retryAtHours or "")
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- Discovery and stale-claim repair are settlement-wide work, not per-resident
-- decisions. Coalesce them for a short world-time window, invalidating the
-- window automatically when zones/tasks change. Atomic claiming still happens
-- below for each resident, so this cannot grant duplicate ownership.
function BaseJobs.prepareWorkforce(base, character, now)
    if base == nil then return false end
    now = tonumber(now) or worldAge()
    local jobTests = rawget(_G, "KnoxJobTestSupplies")
    local signature = workforceSignature(base)
    local cached = workforcePreparation[base]
    local recent = cached ~= nil and cached.signature == signature
        and now >= (cached.atHours or 0)
        and now - (cached.atHours or 0) < 0.25
    if not recent and KnoxPersistence.reconcileBaseTaskClaims ~= nil then
        KnoxPersistence.reconcileBaseTaskClaims(base.id, now)
    end
    -- Settlement-wide depot discovery and character-sensitive work discovery
    -- have a short real-time lease, not the long claim-reconciliation cadence.
    -- Different workers still inspect their own capabilities/resources. A new
    -- world object or inventory change becomes visible within two seconds.
    local discovery = cached ~= nil and cached.discovery
        or setmetatable({}, { __mode = "k" })
    local clock = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    local lastDiscovery = character ~= nil and discovery[character] or nil
    local discover = not recent or clock == nil or lastDiscovery == nil
        or clock < lastDiscovery or clock - lastDiscovery >= 2000
    for _, task in pairs(base.tasks or {}) do
        if task.auto == true and task.manual ~= true and task.state == "queued" then
            task.priority = farmingPriority(task.type) or task.priority
        end
        if task.type == "sort_depot" or task.type == "storage_sorting" or task.type == "sort_loot"
            or (type(task.target) == "table" and task.target.sourceKey ~= nil
                and task.target.destinationKey ~= nil) then
            task.state, task.claimedBy, task.reason = "cancelled", nil, "central_cupboard_replaced_sorting"
        end
    end
    if discover then
        if jobTests ~= nil and jobTests.prepareDiscovery ~= nil then
            jobTests.prepareDiscovery(base, character)
        end
        if KnoxBaseCooking ~= nil then ensureCookingTask(base, now, character) end
        ensureFarmingTask(base, now, character)
        ensureWoodcuttingTask(base, now, character)
        ensureCorpseTask(base, now, character)
        ensureBurnTask(base, now, character)
        ensureRepairTask(base, now, character)
        ensureBarricadeTask(base, now, character)
        if character ~= nil and clock ~= nil then discovery[character] = clock end
    end
    for _, zone in ipairs(sortedZones(base)) do
        local existing = taskForZone(base, zone)
        if existing ~= nil then
            existing.baseId = base.id
            if existing.state ~= "queued" and existing.state ~= "claimed" then
                reopenWhenReady(existing, now)
            end
        else
            local task, result = KnoxBaseTaskBoard.queue(
                base.id,
                zone.type,
                taskTarget(zone),
                {},
                tonumber(zone.priority) or 50
            )
            if task ~= nil then
                task.baseId = base.id
                task.auto = true
                task.retryAtHours = now + (zone.type == "guard" and 0.25 or 0.10)
            else
                print("[KnoxSurvivors][BaseJobs] queue-failed base=" .. tostring(base.id)
                    .. " zone=" .. tostring(zone.id) .. " result=" .. tostring(result))
            end
        end
    end
    workforcePreparation[base] = {
        signature = workforceSignature(base), atHours = recent and cached.atHours or now,
        discovery = discovery,
    }
    return true
end

function BaseJobs.ensureAutomaticTask(base, character, survivorId, preference)
    if base == nil or base.settings == nil or base.settings.automaticJobs == false then
        return nil, "automatic_jobs_disabled"
    end
    local now = worldAge()
    BaseJobs.prepareWorkforce(base, character, now)
    local queued = KnoxBaseTaskBoard.queued(base.id)
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or {}
    local summary = KnoxBaseStorage.summarize ~= nil
        and KnoxBaseStorage.summarize(base) or { totals = {}, misplacedItems = 0 }
    KnoxBaseNeeds.apply(queued, summary, #residentIds)
    -- A player preference is a strong first choice, not a hard lock. A resident
    -- still falls back to other eligible work if their preferred role has nothing
    -- useful to do, which prevents a healthy settlement from idling by accident.
    local selected, selectedResult = BaseJobs.selectEligibleTask(
        queued, survivorId, base.id, preference
    )
    if selected ~= nil then return selected, selectedResult end
    return nil, #queued > 0 and "no_eligible_task" or "no_ready_work_zone"
end

local function candidateSquare(cell, x, y, z, origin)
    local square = cell:getGridSquare(x, y, z)
    if square ~= nil and (square == origin or square:canStand()) then
        return square
    end
    return nil
end

local function searchAround(cell, x, y, z, origin, area, avoidOrigin)
    for radius = 0, 6 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = candidateSquare(cell, x + dx, y + dy, z, origin)
                    if square ~= nil and (not avoidOrigin or square ~= origin)
                        and (area == nil or KnoxCompanionPatrol.contains(area, square)) then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

function BaseJobs.resolveTaskSquare(task, character)
    local target = task ~= nil and task.target or nil
    local cell = getCell ~= nil and getCell() or nil
    if target == nil or cell == nil then
        return nil
    end
    -- Direct callers (including restored/developer tasks) may bypass the
    -- controller's normalization boundary. Resolve against the same canonical
    -- vocabulary so an old alias cannot select the generic fallback square.
    local taskType = canonicalTaskType(task.type)
    if taskType == "haul_corpse" or target.action == "haul_corpse" then
        local resolved = KnoxBaseCorpseHandling.resolveTarget(
            KnoxBaseManager.get(task.baseId),
            target,
            character
        )
        return resolved ~= nil and resolved.approach or nil
    end
    if taskType == "burn_corpse" or target.action == "burn_corpse" then
        local square = cell:getGridSquare(
            tonumber(target.x) or 0, tonumber(target.y) or 0, tonumber(target.z) or 0)
        if square == nil then return nil end
        if AdjacentFreeTileFinder ~= nil and character ~= nil then
            local ok, approach = pcall(function()
                return AdjacentFreeTileFinder.Find(square, character)
            end)
            if ok and approach ~= nil then return approach end
        end
        return square
    end
    if taskType == "barricade" then
        local base = KnoxBaseManager.get(task.baseId)
        local approach = KnoxBaseBarricades ~= nil
            and KnoxBaseBarricades.approachSquare ~= nil
            and KnoxBaseBarricades.approachSquare(base, target, character)
            or nil
        return approach
    end
    if taskType == "cook" then
        return KnoxBaseCooking.resolveTaskSquare(KnoxBaseManager.get(task.baseId),target,character)
    end
    if taskType == "repair" then
        return KnoxBaseRepairs.resolveTaskSquare(
            KnoxBaseManager.get(task.baseId),
            target,
            character
        )
    end
    local x1 = tonumber(target.x1 or target.x) or 0
    local y1 = tonumber(target.y1 or target.y) or 0
    local x2 = tonumber(target.x2 or x1) or x1
    local y2 = tonumber(target.y2 or y1) or y1
    local z = tonumber(target.z) or 0
    local centerX = math.floor((x1 + x2) / 2)
    local centerY = math.floor((y1 + y2) / 2)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if taskType == "patrol" or target.zoneType == "patrol" then
        local point, count = KnoxCompanionPatrol.waypointForStep(
            target,
            task.id or task.claimedBy,
            task.patrolStep
        )
        if point ~= nil then
            return searchAround(cell, point.x, point.y, point.z, origin, target, count > 1)
        end
        return nil
    end
    if taskType == "guard" or target.zoneType == "guard" then
        local point = KnoxCompanionPatrol.guardPost(
            target,
            task.id or task.claimedBy
        )
        if point ~= nil then
            return searchAround(cell, point.x, point.y, point.z, origin, target)
        end
        return nil
    end
    local candidates = {
        { centerX, centerY },
        { x1, y1 },
        { x2, y1 },
        { x1, y2 },
        { x2, y2 },
    }
    for _, point in ipairs(candidates) do
        local square = searchAround(cell, point[1], point[2], z, origin)
        if square ~= nil then
            return square
        end
    end
    return nil
end

function BaseJobs.workDuration(task)
    return task ~= nil and canonicalTaskType(task.type) == "guard" and 240 or 180
end

function BaseJobs.retryDelay(task)
    return task ~= nil and canonicalTaskType(task.type) == "guard" and 0.25 or 0.10
end

return BaseJobs
