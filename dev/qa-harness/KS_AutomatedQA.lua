-- Opt-in unattended engine acceptance suite.
--
-- This coordinator deliberately reports BLOCKED when the game cannot provide a
-- real fixture. It never turns a missing window, floor, bridge, or native test
-- body into a false pass. Run it only in a disposable QA save.
require "KS_Settings"
require "KS_DevTestConfig"
require "KS_NpcSpawnProbe"
require "KS_CombatTestScenarios"
require "KS_EquipmentProbe"
require "KS_NeedsProbe"
require "KS_HealthProbe"
require "KS_MedicalProbe"
require "KS_LootProbe"
require "KS_CombatProbe"
require "KS_PopulationProbe"
require "KS_AutomatedJobMatrix"
require "KS_SurvivorAutonomy"
require "KS_SurvivorNeeds"
require "KS_BaseManager"
require "KS_BaseStorage"
require "KS_BaseJobs"
require "KS_BaseTaskBoard"
require "KS_QAManifest"
require "KS_QABaseTaskAdapter"
require "KS_QASaveIsolation"
pcall(function() require "KS_DebugLog" end)

local QA = rawget(_G, "KnoxAutomatedQA") or {}
_G.KnoxAutomatedQA = QA

local TAG = "[KnoxSurvivors][AutomatedQA]"
local START_DELAY = 90
local PREFLIGHT_TIMEOUT = 600
local SUITE_TIMEOUT = 3600
local NEEDS_TIMEOUT = 1800
local JOB_MATRIX_TIMEOUT = 18000
local MAX_STEP_ATTEMPTS = 3
-- Full-suite passes: after pass 1, passes 2-3 rerun only scenarios that did
-- not PASS, so a one-off flake (stuck path, missed swing, slow reload) gets
-- two more chances without re-running the whole green board.
local MAX_PASSES = 3
local GLOBAL_TIMEOUT_TICKS = 30000
local VERTICAL_STEP_TIMEOUT = 900
-- One declarative catalog backs the active smoke slice and the live acceptance
-- labels for the next representative system scenarios.
local VERTICAL_MANIFEST = KnoxQAManifest.scenarios
local VERTICAL_STATUSES = KnoxQAManifest.STATUSES
local runSequence = 0
local armedSaveDeclaration = nil
local armedSaveWatcher = nil

local state = nil
local update
local advanceStep
local cleanupActiveProbe
local cleanupVerticalFixtures
local verticalUpdate

local FULL_STEPS = {
    { name = "equipment_persistence", kind = "probe", module = "KnoxEquipmentProbe", scenario = "equipment", timeout = 1800 },
    { name = "needs_consumption", kind = "probe", module = "KnoxNeedsProbe", scenario = "needs", timeout = 2200 },
    { name = "health_injury", kind = "probe", module = "KnoxHealthProbe", scenario = "health", timeout = 2200 },
    { name = "medical_treatment", kind = "probe", module = "KnoxMedicalProbe", scenario = "medical", timeout = 2200 },
    { name = "loot_transfer", kind = "probe", module = "KnoxLootProbe", scenario = "loot", timeout = 2800 },
    { name = "npc_combat", kind = "probe", module = "KnoxCombatProbe", scenario = "combat", timeout = 2200 },
    { name = "population_autonomy", kind = "probe", module = "KnoxPopulationProbe", scenario = "population", timeout = 4200 },
    { name = "traversal", kind = "traversal", timeout = 3600 },
    { name = "firearm_combat", kind = "firearm", timeout = 3600 },
    { name = "base_storage_jobs", kind = "base", timeout = JOB_MATRIX_TIMEOUT },
    -- Keep the autonomous faction after the base matrix. It is intentionally
    -- allowed to claim and occupy a real shelter, so it must not influence
    -- traversal, combat, or player-base job measurements that precede it.
    -- The boundary checks after it only read shared records (relationships,
    -- raid planning, seats, shelter search, save capture) and never move the
    -- faction, so they cannot be contaminated by its doorway occupancy.
    { name = "faction_admission", kind = "faction", timeout = 3600 },
    { name = "hostile_encounter", kind = "encounter", timeout = 3600 },
    { name = "raid_eligibility", kind = "raid", timeout = 3600 },
    { name = "vehicle_boarding", kind = "vehicle", timeout = 3600 },
    { name = "night_shelter", kind = "shelter", timeout = 3600 },
    { name = "persistence_roundtrip", kind = "persistence", timeout = 3600 },
}

local function playerFor(playerNum)
    if getSpecificPlayer == nil then return nil end
    local ok, player = pcall(getSpecificPlayer, playerNum or 0)
    return ok and player or nil
end

local function squareText(square)
    if square == nil then return "none" end
    return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
end

local function result(scenario, status, reason, evidence)
    local entry = {
        scenario = tostring(scenario),
        status = tostring(status),
        reason = tostring(reason),
        evidence = tostring(evidence or "none"),
    }
    state.results[#state.results + 1] = entry
    -- Best-per-scenario memory across passes: a PASS is sticky, anything
    -- else keeps the latest verdict so the final report shows fresh evidence.
    if state.best == nil then state.best = {} end
    local prior = state.best[entry.scenario]
    if prior == nil or prior.status ~= "PASS" then
        state.best[entry.scenario] = entry
    end
    local brief = entry.reason
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.brief ~= nil then
        local okBrief, text = pcall(function() return log.brief(entry.reason) end)
        if okBrief and text ~= nil then brief = text end
    end
    print(TAG .. " RESULT scenario=" .. entry.scenario
        .. " status=" .. entry.status
        .. " reason=" .. entry.reason
        .. " brief=" .. tostring(brief)
        .. " evidence=" .. entry.evidence)
    -- Surface every step verdict in the activity feed while QA owns the
    -- save. Console-only results looked like "no progress" during long runs.
    -- FAIL/BLOCKED always carry the one-line why, not just the code.
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then
        pcall(function()
            if entry.status == "FAIL" or entry.status == "BLOCKED" then
                feed.event("QA " .. entry.scenario .. ": " .. entry.status
                    .. " — " .. tostring(brief))
            else
                feed.event("QA " .. entry.scenario .. ": " .. entry.status
                    .. " (" .. entry.reason .. ").")
            end
        end)
    end
end

-- Policy: Knox never writes player protection state (god/ghost/invisible or
-- zombie-ignore). Those flags are 100% vanilla/user-controlled, so no test or
-- QA path can ever leave a player invincible. QA damage scenarios therefore
-- require god mode OFF before starting; that is stated in the start log below.

-- Retired legacy helper. Ordinary zombies are never QA-owned, so even an
-- accidental call must not alter the player's world.
local function clearQaArea(player)
    print(TAG .. " cleanup_skipped reason=ordinary_world_ownership_unproven")
    return 0
end

local function stop()
    if update ~= nil and Events.OnTick ~= nil then
        pcall(function() Events.OnTick.Remove(update) end)
    end
end

-- A step is done when it PASSed on any pass. Faction admission is the one
-- exception: settlement arrival depends on a freshly spawned faction, so it
-- is re-admitted until the arrival itself passes.
local function stepDoneThisSuite(step)
    if state.best == nil then return false end
    local best = state.best[step.name]
    if best == nil or best.status ~= "PASS" then return false end
    if step.name == "faction_admission"
        and (state.best["faction_settlement_arrival"] or {}).status ~= "PASS" then
        return false
    end
    return true
end

local function openScenarioCount()
    local open, seen = 0, {}
    for _, step in ipairs(FULL_STEPS) do
        if not stepDoneThisSuite(step) and not seen[step.name] then
            seen[step.name] = true
            open = open + 1
        end
    end
    return open
end

local function finish()
    -- Final report uses best-per-scenario across all passes: one line per
    -- scenario, no triple-counting from retries and reruns.
    local counts = { PASS = 0, FAIL = 0, BLOCKED = 0, SKIP = 0 }
    for _, entry in pairs(state.best or {}) do
        counts[entry.status] = (counts[entry.status] or 0) + 1
    end
    local status = counts.FAIL > 0 and "FAIL"
        or (counts.BLOCKED > 0 and "BLOCKED" or "PASS")
    print(TAG .. " SUITE status=" .. status
        .. " pass=" .. tostring(counts.PASS)
        .. " fail=" .. tostring(counts.FAIL)
        .. " blocked=" .. tostring(counts.BLOCKED)
        .. " skip=" .. tostring(counts.SKIP)
        .. " passes=" .. tostring(state.pass or 1)
        .. " ticks=" .. tostring(state.ticks))
    print(TAG .. " COMPLETE manual_review=visual_feel_only"
        .. " pending=live_raid_combat,native_driving,long_faction_lifecycle,player_death_succession"
        .. " report=DebugLog_lines_parse_with_tools/parse-live-qa.ps1")
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then
        pcall(function()
            feed.event("QA FINISHED: " .. tostring(status)
                .. " (pass=" .. tostring(counts.PASS)
                .. " fail=" .. tostring(counts.FAIL)
                .. " blocked=" .. tostring(counts.BLOCKED)
                .. " skip=" .. tostring(counts.SKIP)
                .. " after " .. tostring(state.pass or 1) .. " pass(es)).")
        end)
    end
    state.phase = "FINISHED"
    armedSaveDeclaration = nil
    stop()
end

local function failCurrent(reason, evidence)
    local name = state.currentStep ~= nil and state.currentStep.name
        or state.phase:lower()
    if state.currentAttempt < MAX_STEP_ATTEMPTS then
        print(TAG .. " RETRY scenario=" .. tostring(name)
            .. " attempt=" .. tostring(state.currentAttempt + 1)
            .. "/" .. tostring(MAX_STEP_ATTEMPTS)
            .. " reason=" .. tostring(reason))
        local feed = rawget(_G, "KnoxActivityFeed")
        if feed ~= nil and feed.event ~= nil then
            pcall(function()
                feed.event("QA " .. tostring(name) .. ": retry "
                    .. tostring(state.currentAttempt + 1)
                    .. "/" .. tostring(MAX_STEP_ATTEMPTS)
                    .. " (" .. tostring(reason) .. ").")
            end)
        end
        cleanupActiveProbe()
        local combat = rawget(_G, "KnoxCombatTestScenarios")
        if combat ~= nil and combat.cleanup ~= nil then pcall(function() combat.cleanup(true) end) end
        state.retryCurrent = true
        advanceStep()
        return
    end
    result(name, "FAIL", reason, evidence)
    cleanupActiveProbe()
    -- A single failed subsystem must not hide every later result. Preserve the
    -- failure in the final suite status, clean its fixture, and continue into
    -- base jobs/firearms so one disposable run still provides the full report.
    advanceStep()
end

cleanupActiveProbe = function()
    local active = state ~= nil and state.activeProbe or nil
    if active ~= nil and active.module ~= nil and active.module.cleanup ~= nil then
        pcall(function() active.module.cleanup() end)
    end
    -- Do not use the bridge's global test-NPC cleanup without a run-scoped
    -- ownership record. Scenario modules may clean their own proven fixtures.
    if state ~= nil then state.activeProbe = nil end
end

local function cleanupScenarioFixtures()
    local ids = state ~= nil and state.fixtureIds or nil
    if type(ids) ~= "table" or #ids == 0 then return end
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    local persistence = rawget(_G, "KnoxPersistence")
    if autonomy == nil or autonomy.cleanupDeveloperScenario == nil
        or persistence == nil or persistence.getDeveloperQaFixtureOwner == nil
        or state.ownerToken == nil then
        print(TAG .. " CLEANUP_ERROR reason=run_scoped_owner_unavailable ids=" .. table.concat(ids, ","))
        return
    end
    for _, id in ipairs(ids) do
        local owner = persistence.getDeveloperQaFixtureOwner(id)
        if not KnoxQAManifest.isOwnedFixture(state.runId, state.ownerToken, owner) then
            print(TAG .. " CLEANUP_ERROR reason=fixture_owner_unproven id=" .. tostring(id))
            return
        end
    end
    local ok, cleaned, evidence = pcall(function()
        return autonomy.cleanupDeveloperScenario(ids, "automated_qa_step_complete", {
            runId = state.runId, ownerToken = state.ownerToken,
        })
    end)
    if ok and cleaned == true then
        state.fixtureIds = {}
        print(TAG .. " fixture_cleanup ok=true ids=" .. table.concat(ids, ",")
            .. " evidence=" .. tostring(evidence))
    else
        print(TAG .. " CLEANUP_ERROR ids=" .. table.concat(ids, ",")
            .. " evidence=" .. tostring(ok and evidence or cleaned))
    end
end

local function beginProbe(step)
    local module = rawget(_G, step.module)
    if module == nil or module.start == nil or module.status == nil then
        result(step.name, "BLOCKED", "probe_unavailable", step.module)
        advanceStep()
        return
    end
    local config = rawget(_G, "KnoxDevTests")
    if config == nil then
        result(step.name, "BLOCKED", "developer_test_config_missing", "KS_DevTestConfig")
        advanceStep()
        return
    end
    -- KS_DevTestConfig is loaded before the sandbox values are guaranteed to
    -- be ready and therefore may have captured `enabled = false` even though
    -- this coordinator passed the live Automated QA gate. Refresh the runtime
    -- flag here, inside that gate, so child probes cannot reject a valid run.
    config.enabled = true
    config.activeScenario = step.scenario
    local ok, started, reason = pcall(function() return module.start() end)
    if not ok or started ~= true then
        result(step.name, "BLOCKED", "probe_start_rejected", tostring(reason or started))
        cleanupActiveProbe()
        advanceStep()
        return
    end
    state.activeProbe = { module = module, step = step }
    state.phase = "PROBE_WAIT"
    state.phaseTicks = state.ticks
    print(TAG .. " probe_start name=" .. step.name .. " scenario=" .. step.scenario)
end

local function pollProbe()
    local active = state.activeProbe
    if active == nil or active.module == nil then
        failCurrent("active_probe_missing", "none")
        return
    end
    local ok, status = pcall(function() return active.module.status() end)
    if not ok or status == nil then
        failCurrent("probe_status_failed", tostring(status))
        return
    end
    if status.result ~= nil then
        local outcome = tostring(status.result.status or "BLOCKED")
        if outcome ~= "PASS" and outcome ~= "FAIL" and outcome ~= "BLOCKED" and outcome ~= "SKIP" then
            outcome = "FAIL"
        end
        if outcome == "FAIL" and state.currentAttempt < MAX_STEP_ATTEMPTS then
            failCurrent(status.result.reason or "probe_failed",
                status.result.evidence or ("phase=" .. tostring(status.phase)))
            return
        end
        result(active.step.name, outcome, status.result.reason or "probe_completed",
            status.result.evidence or ("phase=" .. tostring(status.phase)))
        cleanupActiveProbe()
        advanceStep()
        return
    end
    if status.finished then
        result(active.step.name, "BLOCKED", "probe_finished_without_result",
            "phase=" .. tostring(status.phase) .. " ticks=" .. tostring(status.ticks))
        cleanupActiveProbe()
        advanceStep()
        return
    end
    if state.ticks - state.phaseTicks >= (active.step.timeout or SUITE_TIMEOUT) then
        result(active.step.name, "FAIL", "probe_timeout",
            "phase=" .. tostring(status.phase) .. " ticks=" .. tostring(status.ticks))
        cleanupActiveProbe()
        advanceStep()
    end
end

local function preflight()
    local player = playerFor(state.playerNum)
    local bridge = rawget(_G, "KnoxJavaBridge")
    local missing = {}
    for _, name in ipairs({
        "KnoxPersistence", "KnoxSurvivorAutonomy", "KnoxSurvivorNeeds",
        "KnoxNpcSpawnProbe", "KnoxCombatTestScenarios", "KnoxBaseManager",
        "KnoxBaseStorage", "KnoxBaseJobs", "KnoxBaseTaskBoard",
    }) do
        if rawget(_G, name) == nil then missing[#missing + 1] = name end
    end
    if player == nil or player:getCurrentSquare() == nil then
        return false, "player_not_ready", "waited=" .. tostring(state.ticks)
    end
    if bridge == nil then
        return false, "java_bridge_missing", "required_for_native_engine_tests"
    end
    local ok, ping = pcall(function() return bridge:ping() end)
    if not ok or type(ping) ~= "string" then
        return false, "java_bridge_ping_failed", tostring(ping)
    end
    if #missing > 0 then
        return false, "required_module_missing", table.concat(missing, ",")
    end
    return true, "ready", "playerSquare=" .. squareText(player:getCurrentSquare())
        .. " bridge=" .. tostring(ping)
end

local function beginTraversal()
    local probe = rawget(_G, "KnoxNpcSpawnProbe")
    if probe == nil or probe.start == nil or probe.status == nil then
        result("traversal", "BLOCKED", "probe_unavailable", "KS_NpcSpawnProbe")
        advanceStep()
        return
    end
    local config = rawget(_G, "KnoxDevTests")
    if config ~= nil then
        config.enabled = true
        config.activeScenario = "obstacle_suite"
    end
    state.phase = "TRAVERSAL_WAIT"
    state.phaseTicks = state.ticks
    probe.start()
end

local function pollTraversal()
    local probe = rawget(_G, "KnoxNpcSpawnProbe")
    local status = probe ~= nil and probe.status ~= nil and probe.status() or nil
    if status == nil then
        failCurrent("traversal_status_missing", "probe_status_unavailable")
        return
    end
    if status.finished then
        local outcome = status.failures > 0 and "FAIL"
            or (status.passes > 0 and "PASS" or "BLOCKED")
        local reason = status.failures > 0 and "one_or_more_cases_failed"
            or (status.passes > 0 and "native_cases_completed" or "no_native_fixture")
        if outcome == "FAIL" and state.currentAttempt < MAX_STEP_ATTEMPTS then
            failCurrent(reason, "passes=" .. tostring(status.passes)
                .. " failures=" .. tostring(status.failures))
            return
        end
        result("traversal", outcome, reason,
            "passes=" .. tostring(status.passes)
                .. " failures=" .. tostring(status.failures)
                .. " completed=" .. tostring(status.completed)
                .. " total=" .. tostring(status.total))
        advanceStep()
    elseif state.ticks - state.phaseTicks >= SUITE_TIMEOUT then
        failCurrent("traversal_timeout", "phase=" .. tostring(status.phase))
    end
end

local function parseFirstId(encoded)
    return tostring(encoded or ""):match("^([^, ]+)")
end

local function parseIds(encoded)
    local first = tostring(encoded or ""):match("^([^ ]+)") or ""
    local ids = {}
    for id in string.gmatch(first, "[^,]+") do
        if id ~= "" then ids[#ids + 1] = id end
    end
    return ids
end

local function worldHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
end

local function nearestBuildingSquare(player)
    local origin = player ~= nil and player:getCurrentSquare() or nil
    local cell = getCell ~= nil and getCell() or nil
    if origin == nil or cell == nil then return nil end
    if origin:getBuilding() ~= nil then return origin end
    local best, bestDistance = nil, nil
    for radius = 1, 24 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = cell:getGridSquare(
                        origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    if square ~= nil and square:getBuilding() ~= nil then
                        local distance = math.abs(dx) + math.abs(dy)
                        if best == nil or distance < bestDistance then
                            best, bestDistance = square, distance
                        end
                    end
                end
            end
        end
        if best ~= nil then return best end
    end
    return nil
end

local function findContainerInBase(base)
    local cell = getCell ~= nil and getCell() or nil
    local area = base ~= nil and (base.territory or base.home) or nil
    if cell == nil or area == nil then return nil, nil end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or (minX + (tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY + (tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    -- Do not scan unbounded territory. The fixture only needs one ordinary
    -- world container, and bounded discovery keeps QA from causing a hitch.
    maxX = math.min(maxX, minX + 32)
    maxY = math.min(maxY, minY + 32)
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and square.getObjects ~= nil
                and square:getObjects() or nil
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local count = object ~= nil and object.getContainerCount ~= nil
                        and object:getContainerCount() or 0
                    for containerIndex = 0, math.max(0, (tonumber(count) or 0) - 1) do
                        local container = object:getContainerByIndex(containerIndex)
                        local typeName = container ~= nil and tostring(container:getType() or "") or ""
                        if container ~= nil and typeName ~= "corpse"
                            and not string.find(string.lower(typeName), "water", 1, true)
                            and not string.find(string.lower(typeName), "rain", 1, true) then
                            return object, containerIndex
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function hasItem(container, fullType)
    if container == nil or container.getItems == nil then return false end
    local items = container:getItems()
    if items == nil then return false end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil and item.getFullType ~= nil
            and tostring(item:getFullType()) == fullType then
            return true
        end
    end
    return false
end

local function beginBase()
    local player = playerFor(state.playerNum)
    local manager = rawget(_G, "KnoxBaseManager")
    local storage = rawget(_G, "KnoxBaseStorage")
    local jobs = rawget(_G, "KnoxBaseJobs")
    local taskBoard = rawget(_G, "KnoxBaseTaskBoard")
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or manager == nil or storage == nil or jobs == nil
        or taskBoard == nil or autonomy == nil or persistence == nil or bridge == nil then
        result("base_storage_jobs", "BLOCKED", "base_modules_unavailable", "manager_storage_jobs")
        advanceStep()
        return
    end
    if persistence.purgeDeveloperQaBases ~= nil then
        pcall(persistence.purgeDeveloperQaBases)
    end
    local square = nearestBuildingSquare(player)
    if square == nil then
        result("base_storage_jobs", "BLOCKED", "no_loaded_building_fixture", "scanRadius=24")
        advanceStep()
        return
    end
    local base, baseResult = manager.establishPlayerBase(player, square)
    if base == nil then
        result("base_storage_jobs", "BLOCKED", "base_setup_failed", tostring(baseResult))
        advanceStep()
        return
    end
    local evidence = "base=" .. tostring(base.id) .. " result=" .. tostring(baseResult)
    local object, containerIndex = findContainerInBase(base)
    local policy = nil
    if object ~= nil then
        for _, candidate in ipairs(storage.policies(base)) do
            if tostring(candidate.category or "") == "tools" then
                policy = candidate
                break
            end
        end
        if policy == nil then
            policy = manager.setStoragePolicy(base.id, object, "tools", containerIndex)
        end
    end
    if policy == nil then
        result("base_storage_jobs", "BLOCKED", "no_assignable_storage_fixture", evidence)
        advanceStep()
        return
    end
    local resolved, resolveResult = storage.resolvePolicy(policy)
    if resolved == nil or resolved.container == nil then
        result("base_storage_jobs", "FAIL", "storage_policy_not_resolved",
            evidence .. " resolve=" .. tostring(resolveResult))
        advanceStep()
        return
    end
    if not hasItem(resolved.container, "Base.Hammer") then
        -- Some Build 42 containers reject the string overload while still
        -- accepting a native InventoryItem. Seed the disposable fixture through
        -- both supported paths and verify the item before measuring the policy.
        pcall(function() resolved.container:AddItem("Base.Hammer") end)
        if not hasItem(resolved.container, "Base.Hammer")
            and rawget(_G, "InventoryItemFactory") ~= nil
            and InventoryItemFactory.CreateItem ~= nil then
            local ok, item = pcall(function()
                return InventoryItemFactory.CreateItem("Base.Hammer")
            end)
            if ok and item ~= nil then
                pcall(function() resolved.container:AddItem(item) end)
            end
        end
    end
    local summary = storage.summarize(base)
    if (tonumber(summary.loadedPolicies) or 0) < 1
        or (tonumber(summary.totals.tools) or 0) < 1 then
        result("base_storage_jobs", "FAIL", "assigned_storage_receipt_missing",
            evidence .. " tools=" .. tostring(summary.totals.tools)
                .. " hasHammer=" .. tostring(hasItem(resolved.container, "Base.Hammer")))
        advanceStep()
        return
    end
    local guardZone = nil
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.type == "guard" and zone.enabled ~= false then
            guardZone = zone
            break
        end
    end
    if guardZone == nil then
        local x, y, z = square:getX(), square:getY(), square:getZ()
        guardZone = manager.addZone(base.id, "guard",
            { x1 = x, y1 = y, x2 = x, y2 = y, z = z }, "QA Guard Post")
    end
    if guardZone == nil then
        result("base_storage_jobs", "FAIL", "guard_zone_create_failed", evidence)
        advanceStep()
        return
    end
    -- Use a real developer survivor as the disposable resident fixture. This
    -- exercises affiliation, base-duty persistence, eligibility and the task
    -- board's atomic claim boundary instead of treating the player shell as a
    -- stand-in for an NPC workforce.
    local invoked, spawned, encoded = pcall(function()
        return autonomy.spawnDeveloperScenario(player, "companion")
    end)
    if not invoked or spawned ~= true then
        result("base_storage_jobs", "BLOCKED", "resident_fixture_unavailable", tostring(encoded))
        advanceStep()
        return
    end
    local residentId = parseFirstId(encoded)
    state.fixtureIds = parseIds(encoded)
    local playerId = persistence.ensurePlayerId(player)
    local residentSet, residentResult = persistence.setPlayerBaseResident(
        residentId, playerId, base.id, worldHours())
    if not residentSet then
        result("base_storage_jobs", "FAIL", "resident_assignment_failed",
            evidence .. " resident=" .. tostring(residentId)
                .. " result=" .. tostring(residentResult))
        advanceStep()
        return
    end
    local resident = nil
    if residentId ~= nil then
        local residentOk, residentValue = pcall(function()
            return bridge:getNpcCharacter(residentId)
        end)
        resident = residentOk and residentValue or nil
    end
    if resident == nil then
        result("base_storage_jobs", "BLOCKED", "resident_body_unavailable",
            evidence .. " resident=" .. tostring(residentId))
        advanceStep()
        return
    end
    -- Seed only the disposable QA resident with real engine items. These are
    -- prerequisites for discovery; the matrix still requires a real world
    -- target and a real task-board claim for every job.
    local residentInventory = resident:getInventory()
    for _, fullType in ipairs({
        "Base.Hammer", "Base.Plank", "Base.Nails", "Base.HandShovel",
        "Base.TomatoSeed", "Base.BucketWaterDebug", "Base.HandAxe",
        "Base.Saw", "Base.Log", "Base.FishFillet",
    }) do
        if residentInventory ~= nil and not hasItem(residentInventory, fullType) then
            pcall(function() residentInventory:AddItem(fullType) end)
        end
    end
    jobs.prepareWorkforce(base, resident, worldHours())
    local claimed, claimResult = taskBoard.claimBest(base.id, residentId, "guard")
    local queuedGuard = 0
    local residentState = "none"
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.type == "guard"
            and (task.state == "queued" or task.state == "claimed") then
            queuedGuard = queuedGuard + 1
            if task.claimedBy == residentId then residentState = task.state end
        end
    end
    if queuedGuard < 1 then
        result("base_storage_jobs", "FAIL", "guard_task_not_queued", evidence
            .. " resident=" .. tostring(residentId)
            .. " claim=" .. tostring(claimResult))
    else
        result("base_storage_jobs", "PASS", "storage_and_task_contract_verified",
            evidence .. " tools=" .. tostring(summary.totals.tools)
                .. " queuedGuard=" .. tostring(queuedGuard)
                .. " resident=" .. tostring(residentId)
                .. " residentTask=" .. tostring(residentState)
                .. " claim=" .. tostring(claimed ~= nil))
    end
    local matrix = rawget(_G, "KnoxAutomatedJobMatrix")
    if matrix == nil or matrix.start == nil or matrix.step == nil or matrix.status == nil then
        result("base_job_matrix", "BLOCKED", "job_matrix_unavailable", "KS_AutomatedJobMatrix")
        advanceStep()
        return
    end
    local matrixContext = {
        player = player,
        base = base,
        residentId = residentId,
        resident = resident,
    }
    local matrixStarted, matrixResult = matrix.start(matrixContext)
    if not matrixStarted then
        result("base_job_matrix", "BLOCKED", "job_matrix_start_failed", tostring(matrixResult))
        advanceStep()
        return
    end
    state.baseMatrix = matrix
    state.baseMatrixReported = 0
    state.phase = "JOB_MATRIX_WAIT"
    state.phaseTicks = state.ticks
end

local function beginFaction()
    local player = playerFor(state.playerNum)
    local settings = rawget(_G, "KnoxSettings")
    local persistence = rawget(_G, "KnoxPersistence")
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    if settings ~= nil and settings.allowNPCFactions ~= nil
        and not settings.allowNPCFactions() then
        result("faction_admission", "BLOCKED", "npc_factions_disabled", "sandbox_option")
        advanceStep()
        return
    end
    if player == nil or persistence == nil or autonomy == nil
        or autonomy.spawnDeveloperScenario == nil then
        result("faction_admission", "BLOCKED", "faction_fixture_unavailable",
            "player_persistence_autonomy")
        advanceStep()
        return
    end
    local ok, created, reason = pcall(function()
        return autonomy.spawnDeveloperScenario(player, "faction")
    end)
    if not ok or created ~= true then
        result("faction_admission", "BLOCKED", "faction_spawn_failed",
            tostring(reason or created))
        advanceStep()
        return
    end
    local ids = parseIds(reason)
    state.fixtureIds = ids
    local faction = #ids > 0 and persistence.getFactionForSurvivor(ids[1]) or nil
    local group = #ids > 0 and persistence.getTravelGroupFor(ids[1]) or nil
    local consistent = faction ~= nil and group ~= nil
        and faction.kind ~= "player"
        and faction.leaderId ~= nil
        and #faction.memberIds >= #ids
        and group.factionId == faction.id
    if consistent then
        for _, id in ipairs(ids) do
            local memberFaction = persistence.getFactionForSurvivor(id)
            if memberFaction == nil or memberFaction.id ~= faction.id then
                consistent = false
                break
            end
        end
    end
    if not consistent then
        result("faction_admission", "FAIL", "faction_membership_inconsistent",
            "ids=" .. table.concat(ids, ",")
                .. " faction=" .. tostring(faction ~= nil and faction.id or "none")
                .. " group=" .. tostring(group ~= nil and group.id or "none"))
        advanceStep()
        return
    end
    local autonomyStatus = autonomy.status ~= nil and autonomy.status() or {}
    local controllers = autonomyStatus.controllers or {}
    local active = 0
    for _, id in ipairs(ids) do
        if controllers[id] ~= nil then active = active + 1 end
    end
    result("faction_admission", "PASS", "group_promoted_to_faction",
        "members=" .. tostring(#faction.memberIds)
            .. " leader=" .. tostring(faction.leaderId)
            .. " group=" .. tostring(group.id)
            .. " activeControllers=" .. tostring(active))
    state.factionTest = { ids = ids, factionId = faction.id }
    state.phase = "FACTION_WAIT"
    state.phaseTicks = state.ticks
end

local function insideArea(square, area)
    if square == nil or area == nil then return false end
    local minX = tonumber(area.minX) or tonumber(area.x)
    local minY = tonumber(area.minY) or tonumber(area.y)
    if minX == nil or minY == nil then return false end
    local maxX = tonumber(area.maxX)
        or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY)
        or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    return square:getZ() == z
        and square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
        and (square.getBuilding == nil or square:getBuilding() ~= nil)
end

local function pollFaction()
    local context = state.factionTest
    local persistence = rawget(_G, "KnoxPersistence")
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    if context == nil or persistence == nil or autonomy == nil then
        result("faction_settlement_arrival", "FAIL", "faction_wait_state_missing", "none")
        advanceStep()
        return
    end
    local faction = persistence.getFaction(context.factionId)
    if faction == nil then
        result("faction_settlement_arrival", "FAIL", "faction_disappeared",
            "faction=" .. tostring(context.factionId))
        advanceStep()
        return
    end
    for _, id in ipairs(context.ids) do
        if persistence.isSurvivorAlive ~= nil and not persistence.isSurvivorAlive(id) then
            result("faction_settlement_arrival", "FAIL", "faction_member_lost",
                "faction=" .. tostring(context.factionId) .. " survivor=" .. tostring(id))
            advanceStep()
            return
        end
    end
    local base = faction.homeBaseId ~= nil and persistence.getBase(faction.homeBaseId) or nil
    local area = base ~= nil and (base.home or base.territory) or faction.homeBase
    local status = autonomy.status ~= nil and autonomy.status() or {}
    local controllers = status.controllers or {}
    local loaded, arrived, uniqueCount, positions = 0, 0, 0, {}
    for _, id in ipairs(context.ids) do
        local controller = controllers[id]
        local character = controller ~= nil and controller.character or nil
        local square = character ~= nil and character.getCurrentSquare ~= nil
            and character:getCurrentSquare() or nil
        if square ~= nil then
            loaded = loaded + 1
            if insideArea(square, area) then arrived = arrived + 1 end
            local key = tostring(square:getX()) .. "," .. tostring(square:getY())
                .. "," .. tostring(square:getZ())
            if positions[key] == nil then
                positions[key] = true
                uniqueCount = uniqueCount + 1
            end
        end
    end
    if base ~= nil and loaded == #context.ids and arrived == #context.ids
        and uniqueCount == #context.ids then
        result("faction_settlement_arrival", "PASS", "distinct_indoor_arrivals",
            "faction=" .. tostring(faction.id)
                .. " base=" .. tostring(base.id)
                .. " members=" .. tostring(#context.ids)
                .. " distinct=" .. tostring(uniqueCount))
        state.factionTest = nil
        advanceStep()
        return
    end
    local timeout = state.currentStep ~= nil and state.currentStep.timeout or 3600
    if state.ticks - state.phaseTicks >= timeout then
        local statusName = base == nil and "BLOCKED" or "FAIL"
        local reason = base == nil and "no_faction_home_fixture"
            or "faction_settlement_arrival_timeout"
        result("faction_settlement_arrival", statusName, reason,
            "faction=" .. tostring(faction.id)
                .. " base=" .. tostring(base ~= nil and base.id or "none")
                .. " loaded=" .. tostring(loaded)
                .. " arrived=" .. tostring(arrived)
                .. " distinct=" .. tostring(uniqueCount)
                .. " expected=" .. tostring(#context.ids))
        state.factionTest = nil
        advanceStep()
    end
end

local function pollJobMatrix()
    local matrix = state.baseMatrix
    if matrix == nil or matrix.status == nil or matrix.step == nil then
        result("base_job_matrix", "FAIL", "job_matrix_state_missing", "none")
        advanceStep()
        return
    end
    pcall(function() matrix.step(state.ticks) end)
    local status = matrix.status()
    for index = (state.baseMatrixReported or 0) + 1, #(status.results or {}) do
        local entry = status.results[index]
        result(entry.scenario, entry.status, entry.reason, entry.evidence)
        state.baseMatrixReported = index
    end
    if status.finished then
        if matrix.cleanup ~= nil then pcall(function() matrix.cleanup() end) end
        state.baseMatrix = nil
        advanceStep()
        return
    end
    if state.ticks - state.phaseTicks >= JOB_MATRIX_TIMEOUT then
        result("base_job_matrix", "FAIL", "job_matrix_timeout",
            "reported=" .. tostring(state.baseMatrixReported))
        if matrix.cleanup ~= nil then pcall(function() matrix.cleanup() end) end
        state.baseMatrix = nil
        advanceStep()
    end
end

local function beginNeeds()
    local player = playerFor(state.playerNum)
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or bridge == nil or player:getCurrentSquare() == nil then
        result("needs", "BLOCKED", "developer_spawn_unavailable", "player_or_bridge_missing")
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local origin = player:getCurrentSquare()
    local spawnSquare = nil
    local cell = getCell ~= nil and getCell() or nil
    if cell ~= nil then
        for radius = 1, 4 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius then
                        local candidate = cell:getGridSquare(
                            origin:getX() + dx, origin:getY() + dy, origin:getZ())
                        if candidate ~= nil and candidate:canStand()
                            and not origin:isBlockedTo(candidate) then
                            spawnSquare = candidate
                            break
                        end
                    end
                end
                if spawnSquare ~= nil then break end
            end
            if spawnSquare ~= nil then break end
        end
    end
    if spawnSquare == nil then
        result("needs", "BLOCKED", "no_standable_needs_fixture", "scanRadius=4")
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local spawned, encoded = pcall(function() return bridge:spawnTestNpc(spawnSquare) end)
    if not spawned or string.find(tostring(encoded), "SPAWNED", 1, true) ~= 1 then
        result("needs", "BLOCKED", "developer_spawn_failed", tostring(encoded))
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local character = bridge:getTestNpcCharacterForAction()
    if character == nil then
        result("needs", "BLOCKED", "developer_character_missing", tostring(encoded))
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local inventory = character:getInventory()
    local food = inventory:AddItem("Base.Apple")
    local water = inventory:AddItem("Base.WaterBottle")
    local stats = character:getStats()
    stats:set(CharacterStat.HUNGER, 0.70)
    stats:set(CharacterStat.THIRST, 0.70)
    stats:set(CharacterStat.FATIGUE, 0.10)
    stats:set(CharacterStat.ENDURANCE, 0.90)
    state.needs = {
        id = "bridge-test-npc",
        character = character,
        bridge = bridge,
        food = food,
        water = water,
        beforeHunger = stats:get(CharacterStat.HUNGER),
        beforeThirst = stats:get(CharacterStat.THIRST),
        observedAction = false,
        attempts = 0,
    }
    state.phase = "NEEDS_WAIT"
    state.phaseTicks = state.ticks
    print(TAG .. " needs_start id=bridge-test-npc"
        .. " food=" .. tostring(food ~= nil)
        .. " water=" .. tostring(water ~= nil))
end

local function cleanupNeeds()
    local test = state ~= nil and state.needs or nil
    local bridge = test ~= nil and test.bridge or nil
    if bridge ~= nil and bridge.removeTestNpc ~= nil then
        pcall(function() bridge:removeTestNpc() end)
    end
    if state ~= nil then state.needs = nil end
end

local function pollNeeds()
    local test = state.needs
    if test == nil or test.character == nil then
        result("needs", "FAIL", "test_state_missing", "no_character")
        cleanupNeeds()
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local character = test.character
    local stats = character:getStats()
    local hunger = tonumber(stats:get(CharacterStat.HUNGER)) or 0
    local thirst = tonumber(stats:get(CharacterStat.THIRST)) or 0
    local actions = character:getCharacterActions()
    if actions ~= nil and not actions:isEmpty() then
        test.observedAction = true
        return
    end
    if hunger < 0.55 and thirst < 0.55 and test.observedAction then
        result("needs", "PASS", "native_consumption_verified",
            "hunger=" .. tostring(hunger) .. " thirst=" .. tostring(thirst)
                .. " attempts=" .. tostring(test.attempts))
        cleanupNeeds()
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    if state.ticks - state.phaseTicks >= NEEDS_TIMEOUT then
        result("needs", "FAIL", "native_consumption_timeout",
            "hunger=" .. tostring(hunger) .. " thirst=" .. tostring(thirst)
                .. " observedAction=" .. tostring(test.observedAction)
                .. " attempts=" .. tostring(test.attempts))
        cleanupNeeds()
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    if test.attempts >= 8 then
        result("needs", "FAIL", "needs_action_retry_limit",
            "hunger=" .. tostring(hunger) .. " thirst=" .. tostring(thirst))
        cleanupNeeds()
        state.phase = "COMBAT_START"
        state.phaseTicks = state.ticks
        return
    end
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    local decision = needs ~= nil and needs.decide(character, nil) or nil
    if decision == nil or (decision.kind ~= "eat" and decision.kind ~= "drink") then
        return
    end
    local action = needs.execute(character, decision)
    test.attempts = test.attempts + 1
    print(TAG .. " needs_action kind=" .. tostring(decision.kind)
        .. " queued=" .. tostring(action ~= nil)
        .. " attempt=" .. tostring(test.attempts))
end

local function beginCombat()
    local combat = rawget(_G, "KnoxCombatTestScenarios")
    if combat == nil or combat.start == nil or combat.status == nil then
        result("firearm_combat", "BLOCKED", "combat_probe_unavailable", "KS_CombatTestScenarios")
        advanceStep()
        return
    end
    local ok = combat.start(state.playerNum, "firearm_duel")
    if not ok then
        failCurrent("combat_start_failed", "firearm_duel")
        return
    end
    state.phase = "COMBAT_WAIT"
    state.phaseTicks = state.ticks
end

local function pollCombat()
    local combat = rawget(_G, "KnoxCombatTestScenarios")
    local status = combat ~= nil and combat.status ~= nil and combat.status() or nil
    local outcome = status ~= nil and status.result or nil
    if outcome ~= nil then
        if outcome.status ~= "PASS" and state.currentAttempt < MAX_STEP_ATTEMPTS then
            if combat.cleanup ~= nil then combat.cleanup(true) end
            failCurrent(outcome.reason or "combat_failed", "scenario=" .. tostring(outcome.scenario))
            return
        end
        result("firearm_combat", outcome.status == "PASS" and "PASS" or "FAIL",
            outcome.reason or "combat_completed",
            "scenario=" .. tostring(outcome.scenario)
                .. " survivorHits=" .. tostring(outcome.survivorHits)
                .. " zombieDamage=" .. tostring(outcome.zombieDamage)
                .. " zombiesKilled=" .. tostring(outcome.zombiesKilled))
        if combat.cleanup ~= nil then combat.cleanup(true) end
        advanceStep()
        return
    end
    if state.ticks - state.phaseTicks >= SUITE_TIMEOUT then
        result("firearm_combat", "FAIL", "combat_timeout", "firearm_duel")
        if combat ~= nil and combat.cleanup ~= nil then combat.cleanup(true) end
        advanceStep()
    end
end

-- Hostile-survivor encounter boundary: two disposable independents become
-- durably hostile while both bodies stay loaded. This exercises the exact
-- relationship record that human combat, robbery and ally defense read.
local function beginEncounter()
    local player = playerFor(state.playerNum)
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    local persistence = rawget(_G, "KnoxPersistence")
    if player == nil or autonomy == nil or persistence == nil
        or autonomy.spawnDeveloperScenario == nil
        or persistence.setRelationshipDisposition == nil
        or persistence.getRelationship == nil then
        result("hostile_encounter", "BLOCKED", "encounter_fixture_unavailable",
            "player_persistence_autonomy")
        advanceStep()
        return
    end
    local firstOk, firstCreated, firstReason = pcall(function()
        return autonomy.spawnDeveloperScenario(player, "single")
    end)
    local secondOk, secondCreated, secondReason = nil, nil, nil
    if firstOk and firstCreated == true then
        secondOk, secondCreated, secondReason = pcall(function()
            return autonomy.spawnDeveloperScenario(player, "single")
        end)
    end
    if not firstOk or firstCreated ~= true or not secondOk or secondCreated ~= true then
        result("hostile_encounter", "BLOCKED", "encounter_spawn_failed",
            tostring(firstReason or firstCreated) .. " | " .. tostring(secondReason or secondCreated))
        advanceStep()
        return
    end
    local ids = parseIds(firstReason)
    for _, id in ipairs(parseIds(secondReason)) do ids[#ids + 1] = id end
    state.fixtureIds = ids
    if #ids < 2 then
        result("hostile_encounter", "BLOCKED", "encounter_spawn_short",
            "ids=" .. table.concat(ids, ","))
        advanceStep()
        return
    end
    local firstId, secondId = ids[#ids - 1], ids[#ids]
    local record = persistence.setRelationshipDisposition(
        firstId, secondId, "hostile", worldHours() + 24)
    local stored = persistence.getRelationship(firstId, secondId)
    if record ~= nil and stored ~= nil and stored.disposition == "hostile" then
        result("hostile_encounter", "PASS", "hostile_relationship_recorded",
            "pair=" .. tostring(firstId) .. "," .. tostring(secondId))
    else
        result("hostile_encounter", "FAIL", "hostile_record_rejected",
            "pair=" .. tostring(firstId) .. "," .. tostring(secondId))
    end
    advanceStep()
end

-- Raid planning boundary only: proposeRaid changes no duties or inventories
-- (see KS_KnoxEvents), so validating a real proposal is contamination-free.
-- Live raid travel, defender combat and withdrawal stay manual acceptance.
local function beginRaid()
    local events = rawget(_G, "KnoxEvents")
    local persistence = rawget(_G, "KnoxPersistence")
    if events == nil or persistence == nil or events.proposeRaid == nil
        or persistence.getFactions == nil or persistence.getBases == nil then
        result("raid_eligibility", "BLOCKED", "raid_modules_unavailable",
            "knox_events_persistence")
        advanceStep()
        return
    end
    local hours = worldHours()
    local factionsOk, factions = pcall(function() return persistence.getFactions() end)
    local basesOk, bases = pcall(function() return persistence.getBases() end)
    if not factionsOk or not basesOk
        or type(factions) ~= "table" or type(bases) ~= "table" then
        result("raid_eligibility", "BLOCKED", "faction_roster_unavailable", "none")
        advanceStep()
        return
    end
    local sources, targets = {}, {}
    for id, faction in pairs(factions) do
        if type(faction) == "table" and faction.kind ~= "player"
            and faction.homeBaseId ~= nil then
            sources[#sources + 1] = id
        end
    end
    for id, base in pairs(bases) do
        if type(base) == "table" then targets[#targets + 1] = id end
    end
    if #sources == 0 or #targets == 0 then
        result("raid_eligibility", "BLOCKED", "no_raid_fixture",
            "sources=" .. tostring(#sources) .. " targets=" .. tostring(#targets))
        advanceStep()
        return
    end
    local firstReason = "none"
    for _, sourceId in ipairs(sources) do
        for _, targetId in ipairs(targets) do
            local callOk, proposal, reason = pcall(function()
                return events.proposeRaid(sourceId, targetId, hours)
            end)
            if callOk and proposal ~= nil then
                result("raid_eligibility", "PASS", "raid_proposal_valid",
                    "source=" .. tostring(sourceId)
                        .. " target=" .. tostring(targetId)
                        .. " members=" .. tostring(#(proposal.memberIds or {}))
                        .. " defenders=" .. tostring(proposal.defendersAtProposal))
                advanceStep()
                return
            elseif callOk then
                firstReason = tostring(reason)
            end
        end
    end
    result("raid_eligibility", "BLOCKED", "no_valid_raid_proposal", firstReason)
    advanceStep()
end

local function findQaVehicle(player)
    if player == nil then return nil end
    local directOk, direct = pcall(function() return player:getVehicle() end)
    if directOk and direct ~= nil then return direct end
    -- Parked-vehicle scan without touching the live cell vehicle list:
    -- indexed get() on that mutating Java list throws past Kahlua pcall
    -- (39 dumps in one suite). Square getters are plain and null-safe.
    local cell = getCell ~= nil and getCell() or nil
    local okOrigin, origin = pcall(function() return player:getCurrentSquare() end)
    if cell == nil or not okOrigin or origin == nil then return nil end
    local okX, ox = pcall(function() return origin:getX() end)
    local okY, oy = pcall(function() return origin:getY() end)
    local okZ, oz = pcall(function() return origin:getZ() end)
    if not okX or not okY or not okZ then return nil end
    local best, bestDistance = nil, nil
    for radius = 0, 25 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local okSq, square = pcall(function()
                        return cell:getGridSquare(ox + dx, oy + dy, oz)
                    end)
                    if okSq and square ~= nil and square.getVehicleContainer ~= nil then
                        local okV, vehicle = pcall(function()
                            return square:getVehicleContainer()
                        end)
                        if okV and vehicle ~= nil then
                            local distance = dx * dx + dy * dy
                            if best == nil or distance < bestDistance then
                                best, bestDistance = vehicle, distance
                            end
                        end
                    end
                end
            end
        end
        if best ~= nil then return best end
    end
    return best
end

-- Boarding boundary without driving: a disposable passenger plus the real
-- free-seat selector. Seat discovery exercises locked doors, occupancy and
-- driver-seat reservation; native driving itself stays manual acceptance.
local function beginVehicle()
    local player = playerFor(state.playerNum)
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or vehicles == nil or autonomy == nil or bridge == nil
        or vehicles.findFreePassengerSeat == nil then
        result("vehicle_boarding", "BLOCKED", "vehicle_modules_unavailable",
            "companion_vehicles_autonomy_bridge")
        advanceStep()
        return
    end
    local vehicle = findQaVehicle(player)
    if vehicle == nil then
        result("vehicle_boarding", "BLOCKED", "no_vehicle_fixture", "scanRadius=25")
        advanceStep()
        return
    end
    local invoked, spawned, encoded = pcall(function()
        return autonomy.spawnDeveloperScenario(player, "single")
    end)
    if not invoked or spawned ~= true then
        result("vehicle_boarding", "BLOCKED", "passenger_fixture_unavailable",
            tostring(encoded))
        advanceStep()
        return
    end
    local ids = parseIds(encoded)
    state.fixtureIds = ids
    local passengerId = parseFirstId(encoded)
    local character = nil
    if passengerId ~= nil then
        local characterOk, characterValue = pcall(function()
            return bridge:getNpcCharacter(passengerId)
        end)
        character = characterOk and characterValue or nil
    end
    if character == nil then
        result("vehicle_boarding", "BLOCKED", "passenger_body_unavailable",
            "passenger=" .. tostring(passengerId))
        advanceStep()
        return
    end
    local seatOk, seat = pcall(function()
        return vehicles.findFreePassengerSeat(character, vehicle)
    end)
    if seatOk and seat ~= nil then
        result("vehicle_boarding", "PASS", "passenger_seat_available",
            "passenger=" .. tostring(passengerId) .. " seat=" .. tostring(seat))
    else
        result("vehicle_boarding", "BLOCKED", "no_free_passenger_seat",
            "passenger=" .. tostring(passengerId))
    end
    advanceStep()
end

-- Shelter search without claiming: the real indoor-square selector runs
-- against the loaded cell with the temporary-group territory filter.
local function beginShelter()
    local player = playerFor(state.playerNum)
    local shelter = rawget(_G, "KnoxNightShelter")
    if player == nil or shelter == nil or shelter.findShelter == nil then
        result("night_shelter", "BLOCKED", "shelter_modules_unavailable", "none")
        advanceStep()
        return
    end
    local filter = shelter.isUnclaimedTemporaryShelter
    local searchOk, square = pcall(function()
        return shelter.findShelter(player, 24, filter)
    end)
    if searchOk and square ~= nil then
        result("night_shelter", "PASS", "indoor_shelter_found",
            "square=" .. squareText(square))
    else
        result("night_shelter", "BLOCKED", "no_shelter_fixture", "scanRadius=24")
    end
    advanceStep()
end

-- Save-path simulation: run the real per-survivor capture pass mid-suite and
-- prove the living roster is unchanged afterwards. One survivor's failure
-- must report FAIL with evidence, never silently drop a record.
local function beginPersistenceCheck()
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if persistence == nil or bridge == nil
        or persistence.captureAllActiveSurvivors == nil
        or persistence.getLivingWorldSurvivorIds == nil then
        result("persistence_roundtrip", "BLOCKED", "persistence_modules_unavailable",
            "none")
        advanceStep()
        return
    end
    local beforeOk, beforeIds = pcall(function()
        return persistence.getLivingWorldSurvivorIds()
    end)
    local callOk, saved, evidence = pcall(function()
        return persistence.captureAllActiveSurvivors()
    end)
    if not callOk then
        result("persistence_roundtrip", "FAIL", "save_capture_threw", tostring(saved))
    elseif saved ~= true then
        result("persistence_roundtrip", "FAIL", "save_capture_failed",
            tostring(evidence))
    else
        local afterOk, afterIds = pcall(function()
            return persistence.getLivingWorldSurvivorIds()
        end)
        if beforeOk and afterOk
            and #(beforeIds or {}) ~= #(afterIds or {}) then
            result("persistence_roundtrip", "FAIL", "living_ids_changed",
                "before=" .. tostring(#beforeIds)
                    .. " after=" .. tostring(#afterIds))
        else
            result("persistence_roundtrip", "PASS", "save_capture_verified",
                tostring(evidence)
                    .. " living=" .. tostring(afterOk and #afterIds or "unknown"))
        end
    end
    advanceStep()
end

advanceStep = function()
    if state == nil or state.phase == "FINISHED" then return end
    cleanupScenarioFixtures()
    local retry = state.retryCurrent == true
    state.retryCurrent = nil
    if not retry then
        state.stepIndex = (state.stepIndex or 0) + 1
        state.currentAttempt = 1
    else
        state.currentAttempt = (state.currentAttempt or 1) + 1
    end
    local step = FULL_STEPS[state.stepIndex]
    while step ~= nil and stepDoneThisSuite(step) do
        state.stepIndex = (state.stepIndex or 0) + 1
        state.currentAttempt = 1
        step = FULL_STEPS[state.stepIndex]
    end
    if step == nil then
        -- Pass complete. Rerun open scenarios up to MAX_PASSES so flakes
        -- get a second and third chance; otherwise report best-of.
        local open = openScenarioCount()
        if (state.pass or 1) < MAX_PASSES and open > 0 then
            state.pass = (state.pass or 1) + 1
            state.stepIndex = 0
            state.currentAttempt = 0
            state.ticks = 0
            state.phaseTicks = 0
            print(TAG .. " PASS_START pass=" .. tostring(state.pass)
                .. "/" .. tostring(MAX_PASSES)
                .. " openScenarios=" .. tostring(open))
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then
                pcall(function()
                    feed.event("QA pass " .. tostring(state.pass)
                        .. "/" .. tostring(MAX_PASSES) .. ": retrying "
                        .. tostring(open) .. " open scenario(s).")
                end)
            end
            advanceStep()
            return
        end
        finish()
        return
    end
    state.currentStep = step
    state.phaseTicks = state.ticks
    clearQaArea(playerFor(state.playerNum))
    if step.kind == "probe" then
        beginProbe(step)
    elseif step.kind == "traversal" then
        beginTraversal()
    elseif step.kind == "base" then
        beginBase()
    elseif step.kind == "faction" then
        beginFaction()
    elseif step.kind == "firearm" then
        beginCombat()
    elseif step.kind == "encounter" then
        beginEncounter()
    elseif step.kind == "raid" then
        beginRaid()
    elseif step.kind == "vehicle" then
        beginVehicle()
    elseif step.kind == "shelter" then
        beginShelter()
    elseif step.kind == "persistence" then
        beginPersistenceCheck()
    else
        result(step.name, "BLOCKED", "unknown_step_kind", tostring(step.kind))
        advanceStep()
    end
end

-- -------------------------------------------------------------------------
-- QA vertical slice: manifest-driven, non-destructive in-game observation.

local function compact(value)
    return tostring(value == nil and "unavailable" or value):gsub("[%s|]", "_")
end

local function safeValue(callback)
    local ok, value = pcall(callback)
    return ok and value or nil
end

local function buildVersion()
    local core = getCore ~= nil and safeValue(getCore) or nil
    if core ~= nil and core.getVersionNumber ~= nil then
        return compact(safeValue(function() return core:getVersionNumber() end))
    end
    return "unavailable"
end

local function saveIdentity()
    return KnoxQASaveIsolation.capture(getCore)
end

local function clearArmedSave(reason)
    local declaration = armedSaveDeclaration
    armedSaveDeclaration = nil
    if armedSaveWatcher ~= nil and Events ~= nil and Events.OnTick ~= nil
        and Events.OnTick.Remove ~= nil then
        pcall(Events.OnTick.Remove, armedSaveWatcher)
    end
    armedSaveWatcher = nil
    if declaration ~= nil then
        print(TAG .. " SAVE_ARM status=" .. compact(reason or "CLEARED")
            .. " saveIdentity=" .. KnoxQASaveIsolation.encode(declaration.identity)
            .. " saveIdentitySource=" .. compact(declaration.source)
            .. " nextRunSequence=" .. tostring(declaration.nextRunSequence))
    end
end

local function watchArmedSaveIdentity()
    local declaration = armedSaveDeclaration
    if declaration == nil then return end
    local capture = saveIdentity()
    if capture.identity ~= declaration.identity
        or capture.source ~= declaration.source
        or tonumber(declaration.nextRunSequence) ~= runSequence + 1 then
        clearArmedSave("EXPIRED_IDENTITY_OR_RUN_CHANGED")
    end
end

local function encoded(value)
    return KnoxQASaveIsolation.encode(value)
end

local function saveEvidence()
    if state == nil then return "saveIdentity=unavailable saveIdentitySource=unavailable"
        .. " saveIsolation=UNKNOWN_SAVE" end
    return "saveIdentity=" .. encoded(state.metadata.saveIdentity)
        .. " saveIdentitySource=" .. compact(state.metadata.saveIdentitySource)
        .. " saveIsolation=" .. compact(state.saveIsolation.status)
        .. " saveDeclaration=" .. (state.saveIsolation.declared and "run_scoped" or "none")
end

local function runtimeStatus()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then return "bridge_missing" end
    if bridge.ping == nil then return "bridge_ping_unavailable" end
    local ping = safeValue(function() return bridge:ping() end)
    return ping ~= nil and ("bridge_" .. compact(ping)) or "bridge_ping_failed"
end

local function nextRunId()
    runSequence = runSequence + 1
    local stamp = getTimestampMs ~= nil and safeValue(getTimestampMs) or nil
    if stamp == nil then
        stamp = tostring(math.floor((worldHours() or 0) * 3600000)) .. "-" .. tostring(os.time())
    end
    return KnoxQAManifest.runId(compact(stamp), runSequence)
end

local function verticalCheckpoint(spec, phase)
    if state == nil then return false, "state_missing" end
    local checkpoint = {
        runId = state.runId,
        ownerToken = state.ownerToken,
        scenario = spec.id,
        category = spec.category,
        phase = phase,
        tick = state.ticks,
        save = encoded(state.metadata.saveIdentity),
        saveIdentity = encoded(state.metadata.saveIdentity),
        saveIdentitySource = compact(state.metadata.saveIdentitySource),
        saveIsolation = compact(state.saveIsolation.status),
        timestamp = tostring(getTimestampMs ~= nil and safeValue(getTimestampMs) or worldHours()),
        evidenceReference = "debuglog:" .. state.runId .. ":" .. spec.id .. ":" .. phase,
    }
    state.checkpoints[#state.checkpoints + 1] = checkpoint
    print(TAG .. " CHECKPOINT runId=" .. checkpoint.runId
        .. " scenario=" .. checkpoint.scenario
        .. " category=" .. compact(checkpoint.category)
        .. " phase=" .. checkpoint.phase
        .. " tick=" .. tostring(checkpoint.tick)
        .. " save=" .. checkpoint.save
        .. " saveIdentity=" .. checkpoint.saveIdentity
        .. " saveIdentitySource=" .. checkpoint.saveIdentitySource
        .. " saveIsolation=" .. checkpoint.saveIsolation
        .. " timestamp=" .. compact(checkpoint.timestamp)
        .. " ownerToken=" .. compact(checkpoint.ownerToken)
        .. " evidenceReference=" .. checkpoint.evidenceReference
        .. " evidenceType=offline")
    return true
end

local function verticalResult(spec, status, reason, evidence, evidenceType)
    status = VERTICAL_STATUSES[status] and status or "HARNESS_ERROR"
    local entry = {
        scenario = spec.id,
        status = status,
        reason = compact(reason),
        evidence = tostring(evidence or "none"),
        evidenceType = evidenceType or spec.evidenceType,
        runId = state.runId,
        humanConfirmation = spec.humanConfirmation,
        task = spec.task,
        category = spec.category,
        area = spec.area,
        ownerToken = state.ownerToken,
        timestamp = tostring(getTimestampMs ~= nil and safeValue(getTimestampMs) or worldHours()),
        evidenceReference = "debuglog:" .. state.runId .. ":" .. spec.id,
        humanRequired = spec.humanConfirmation == true,
        saveIdentity = encoded(state.metadata.saveIdentity),
        saveIdentitySource = state.metadata.saveIdentitySource,
        saveIsolation = state.saveIsolation.status,
    }
    state.results[#state.results + 1] = entry
    state.best[entry.scenario] = entry
    print(TAG .. " RESULT runId=" .. entry.runId
        .. " scenario=" .. entry.scenario
        .. " status=" .. entry.status
        .. " reason=" .. entry.reason
        .. " evidenceType=" .. compact(entry.evidenceType)
        .. " humanConfirmation=" .. compact(entry.humanConfirmation)
        .. " task=" .. compact(entry.task)
        .. " category=" .. compact(entry.category)
        .. " area=" .. compact(entry.area)
        .. " saveIdentity=" .. entry.saveIdentity
        .. " saveIdentitySource=" .. compact(entry.saveIdentitySource)
        .. " saveIsolation=" .. compact(entry.saveIsolation)
        .. " ownerToken=" .. compact(entry.ownerToken)
        .. " timestamp=" .. compact(entry.timestamp)
        .. " humanRequired=" .. tostring(entry.humanRequired)
        .. " evidenceReference=" .. entry.evidenceReference
        .. " evidence=" .. entry.evidence)
end

local function fixtureIdFrom(encoded)
    return tostring(encoded or ""):match("^([^, ]+)")
end

local function nativeFixtureEvidence(id)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local persistence = rawget(_G, "KnoxPersistence")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and safeValue(function() return runtime.getCharacter(id) end) or nil
    local square = character ~= nil and character.getCurrentSquare ~= nil
        and safeValue(function() return character:getCurrentSquare() end) or nil
    local origin = persistence ~= nil and persistence.getSurvivorOrigin ~= nil
        and safeValue(function() return persistence.getSurvivorOrigin(id) end) or nil
    local identity = persistence ~= nil and persistence.getSurvivorIdentity ~= nil
        and safeValue(function() return persistence.getSurvivorIdentity(id) end) or nil
    local group = persistence ~= nil and persistence.getTravelGroupFor ~= nil
        and safeValue(function() return persistence.getTravelGroupFor(id) end) or nil
    local faction = persistence ~= nil and persistence.getFactionForSurvivor ~= nil
        and safeValue(function() return persistence.getFactionForSurvivor(id) end) or nil
    local originText = origin ~= nil and (tostring(origin.x) .. "," .. tostring(origin.y)
        .. "," .. tostring(origin.z)) or "unavailable"
    local groupId = group ~= nil and tostring(group.id or "present") or "none"
    local factionId = faction ~= nil and tostring(faction.id or "present") or "none"
    local name = identity ~= nil and compact((identity.forename or "") .. "_" .. (identity.surname or ""))
        or "unavailable"
    return character, square,
        "id=" .. compact(id)
            .. " owner=" .. compact(type(state.fixtureOwners[id]) == "table"
                and state.fixtureOwners[id].runId or state.fixtureOwners[id])
            .. " identity=" .. name
            .. " origin=" .. originText
            .. " body=" .. tostring(character ~= nil)
            .. " square=" .. squareText(square)
            .. " group=" .. compact(groupId)
            .. " faction=" .. compact(factionId)
end

cleanupVerticalFixtures = function(reason)
    if state == nil or type(state.fixtureIds) ~= "table" or #state.fixtureIds == 0 then
        return true, "no_owned_fixture"
    end
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    if autonomy == nil or autonomy.cleanupDeveloperScenario == nil then
        return false, "cleanup_api_unavailable"
    end
    local persistence = rawget(_G, "KnoxPersistence")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local retained, failures, cleaned = {}, {}, 0
    for _, id in ipairs(state.fixtureIds) do
        local localOwner = state.fixtureOwners[id]
        local persistentOwner = persistence ~= nil and persistence.getDeveloperQaFixtureOwner ~= nil
            and persistence.getDeveloperQaFixtureOwner(id) or nil
        if not KnoxQAManifest.isOwnedFixture(state.runId, state.ownerToken, localOwner)
            or not KnoxQAManifest.isOwnedFixture(state.runId, state.ownerToken, persistentOwner) then
            retained[#retained + 1] = id
            failures[#failures + 1] = tostring(id) .. ":ownership_unproven"
        else
            local ok, removed, evidence = pcall(function()
                return autonomy.cleanupDeveloperScenario({ id }, reason, {
                    runId = state.runId, ownerToken = state.ownerToken,
                })
            end)
            if not ok or removed ~= true then
                retained[#retained + 1] = id
                failures[#failures + 1] = tostring(id) .. ":" .. tostring(evidence or removed)
            else
                local body = runtime ~= nil and runtime.getCharacter ~= nil
                    and safeValue(function() return runtime.getCharacter(id) end) or nil
                if body ~= nil then
                    retained[#retained + 1] = id
                    failures[#failures + 1] = tostring(id) .. ":body_remains"
                else
                    state.fixtureOwners[id] = nil
                    cleaned = cleaned + 1
                end
            end
        end
    end
    state.fixtureIds = retained
    if #failures > 0 then
        return false, "cleaned=" .. tostring(cleaned) .. " failures=" .. table.concat(failures, ";")
    end
    for _, id in ipairs(state.fixtureIds) do
        local body = runtime ~= nil and runtime.getCharacter ~= nil
            and safeValue(function() return runtime.getCharacter(id) end) or nil
        if body ~= nil then return false, "owned_body_remains:" .. tostring(id) end
    end
    state.fixtureOwners = {}
    return true, "removed=" .. tostring(cleaned)
end

local function runVerticalScenario(spec)
    local player = playerFor(state.playerNum)
    if spec.kind == "readiness" then
        if player == nil or player:getCurrentSquare() == nil then
            return "BLOCKED", "player_not_ready", "playerSquare=unavailable"
        end
        if not KnoxSettings.developerToolsEnabled() then
            return "BLOCKED", "developer_tools_disabled", "EnableDeveloperTools_required"
        end
        local runtime = runtimeStatus()
        if runtime == "bridge_missing" or runtime == "bridge_ping_failed" then
            return "BLOCKED", "native_bridge_unavailable", "runtime=" .. runtime
        end
        return "PASS", "ready", "build=" .. state.metadata.build
            .. " save=" .. state.metadata.save
            .. " mod=" .. state.metadata.mod
            .. " runtime=" .. runtime
            .. " duplicateRuntime=not_exposed"
    end

    if spec.kind == "survivor_snapshot" then
        local persistence = rawget(_G, "KnoxPersistence")
        local runtime = rawget(_G, "KnoxSurvivorRuntime")
        if persistence == nil or type(persistence.getSurvivorIds) ~= "function"
            or type(persistence.getSurvivorIdentity) ~= "function" then
            return "BLOCKED", "survivor_snapshot_api_unavailable", "persistence_identity_reader"
        end
        local ok, ids = pcall(persistence.getSurvivorIds)
        if not ok or type(ids) ~= "table" then
            return "HARNESS_ERROR", "survivor_identity_read_failed", tostring(ids)
        end
        local rows, loaded = {}, 0
        for _, id in ipairs(ids) do
            local identity = persistence.getSurvivorIdentity(id)
            local character = runtime ~= nil and type(runtime.getCharacter) == "function"
                and safeValue(function() return runtime.getCharacter(id) end) or nil
            local square = character ~= nil and character.getCurrentSquare ~= nil
                and safeValue(function() return character:getCurrentSquare() end) or nil
            if character ~= nil then loaded = loaded + 1 end
            local name = identity ~= nil
                and compact((identity.forename or "") .. "_" .. (identity.surname or ""))
                or "identity_unavailable"
            if #rows < 24 then
                rows[#rows + 1] = compact(id) .. ":" .. name
                    .. ":body=" .. tostring(character ~= nil)
                    .. ":square=" .. squareText(square)
            end
        end
        return "PASS", "read_only_survivor_snapshot",
            "count=" .. tostring(#ids) .. " loadedBodies=" .. tostring(loaded)
                .. " details=" .. (#rows > 0 and table.concat(rows, ";") or "none")
                .. (#ids > #rows and ";truncated=true" or "")
    end

    if spec.kind == "base_snapshot" then
        local persistence = rawget(_G, "KnoxPersistence")
        if persistence == nil or type(persistence.getBases) ~= "function"
            or type(persistence.getBaseResidentIds) ~= "function"
            or type(persistence.getBaseResidentWorkStatus) ~= "function" then
            return "BLOCKED", "base_snapshot_api_unavailable", "persistence_base_readers"
        end
        local ok, bases = pcall(persistence.getBases)
        if not ok or type(bases) ~= "table" then
            return "HARNESS_ERROR", "base_state_read_failed", tostring(bases)
        end
        local rows, baseCount, taskCount, queued, claimed, residentCount = {}, 0, 0, 0, 0, 0
        for baseId, base in pairs(bases) do
            if type(base) == "table" then
                baseCount = baseCount + 1
                local localTasks = 0
                for _, task in pairs(type(base.tasks) == "table" and base.tasks or {}) do
                    if type(task) == "table" then
                        taskCount, localTasks = taskCount + 1, localTasks + 1
                        if task.state == "queued" then queued = queued + 1 end
                        if task.state == "claimed" then claimed = claimed + 1 end
                    end
                end
                local residents = persistence.getBaseResidentIds(baseId) or {}
                residentCount = residentCount + #residents
                local work = {}
                for _, survivorId in ipairs(residents) do
                    local status = persistence.getBaseResidentWorkStatus(survivorId, baseId)
                    if #work < 24 then
                        work[#work + 1] = compact(survivorId) .. ":"
                            .. compact(status ~= nil and status.state or "status_unavailable")
                            .. ":" .. compact(status ~= nil and status.taskType or "none")
                    end
                end
                if #rows < 24 then
                    rows[#rows + 1] = compact(baseId) .. ":tasks=" .. tostring(localTasks)
                        .. ":residents=" .. (#work > 0 and table.concat(work, ",") or "none")
                end
            end
        end
        table.sort(rows)
        return "PASS", "read_only_base_task_duty_snapshot",
            "bases=" .. tostring(baseCount) .. " residents=" .. tostring(residentCount)
                .. " tasks=" .. tostring(taskCount) .. " queued=" .. tostring(queued)
                .. " claimed=" .. tostring(claimed)
                .. " details=" .. (#rows > 0 and table.concat(rows, ";") or "none")
                .. (baseCount > #rows and ";truncated=true" or "")
    end

    if spec.kind == "group_faction_snapshot" then
        local persistence = rawget(_G, "KnoxPersistence")
        if persistence == nil or type(persistence.getTravelGroups) ~= "function"
            or type(persistence.getFactions) ~= "function" then
            return "BLOCKED", "group_faction_snapshot_api_unavailable", "persistence_roster_readers"
        end
        local groupsOk, groups = pcall(persistence.getTravelGroups)
        local factionsOk, factions = pcall(persistence.getFactions)
        if not groupsOk or type(groups) ~= "table" then
            return "HARNESS_ERROR", "group_roster_read_failed", tostring(groups)
        end
        if not factionsOk or type(factions) ~= "table" then
            return "HARNESS_ERROR", "faction_roster_read_failed", tostring(factions)
        end
        local groupRows, factionRows, groupCount, factionCount = {}, {}, 0, 0
        for id, group in pairs(groups) do
            if type(group) == "table" then
                groupCount = groupCount + 1
                if #groupRows < 24 then
                    groupRows[#groupRows + 1] = compact(group.id or id)
                        .. ":leader=" .. compact(group.leaderId)
                        .. ":members=" .. compact(table.concat(group.memberIds or {}, ","))
                        .. ":faction=" .. compact(group.factionId)
                end
            end
        end
        for id, faction in pairs(factions) do
            if type(faction) == "table" then
                factionCount = factionCount + 1
                if #factionRows < 24 then
                    factionRows[#factionRows + 1] = compact(faction.id or id)
                        .. ":leader=" .. compact(faction.leaderId)
                        .. ":members=" .. compact(table.concat(faction.memberIds or {}, ","))
                end
            end
        end
        table.sort(groupRows)
        table.sort(factionRows)
        return "PASS", "read_only_group_faction_snapshot",
            "groups=" .. tostring(groupCount) .. " factions=" .. tostring(factionCount)
                .. " groupDetails=" .. (#groupRows > 0 and table.concat(groupRows, ";") or "none")
                .. " factionDetails=" .. (#factionRows > 0 and table.concat(factionRows, ";") or "none")
                .. ((groupCount > #groupRows or factionCount > #factionRows) and ";truncated=true" or "")
    end

    if spec.kind == "stale_cleanup" then
        if state.startReady ~= true then
            return "SKIPPED", "readiness_not_passed", "dependent=QA-START-001"
        end
        local persistence = rawget(_G, "KnoxPersistence")
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        if persistence == nil or persistence.listDeveloperQaFixtures == nil
            or autonomy == nil or autonomy.cleanupDeveloperScenario == nil then
            return "CLEANUP_ERROR", "stale_cleanup_api_unavailable", "persistence_or_autonomy"
        end
        local listed, fixtures = pcall(function()
            return persistence.listDeveloperQaFixtures()
        end)
        if not listed or type(fixtures) ~= "table" then
            return "CLEANUP_ERROR", "stale_fixture_listing_failed", tostring(fixtures)
        end
        local cleaned, failures = 0, {}
        for _, fixture in ipairs(fixtures) do
            local owner = fixture ~= nil and fixture.owner or nil
            if fixture ~= nil and type(fixture.id) == "string"
                and owner ~= nil and owner.runId ~= state.runId then
                local ok, removed, evidence = pcall(function()
                    return autonomy.cleanupDeveloperScenario({ fixture.id },
                        "stale_qa_run:" .. state.runId, owner)
                end)
                if ok and removed == true then
                    cleaned = cleaned + 1
                else
                    failures[#failures + 1] = fixture.id .. ":" .. tostring(evidence or removed)
                end
            end
        end
        if #failures > 0 then
            return "CLEANUP_ERROR", "stale_fixture_cleanup_incomplete",
                "cleaned=" .. cleaned .. " failures=" .. table.concat(failures, ";")
        end
        return "PASS", "stale_owned_fixtures_reconciled", "cleaned=" .. tostring(cleaned)
    end

    if spec.kind == "encounter_fixture" then
        if state.startReady ~= true then
            return "SKIPPED", "readiness_not_passed", "dependent=QA-START-001"
        end
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        if autonomy == nil or autonomy.spawnDeveloperScenario == nil then
            return "BLOCKED", "fixture_api_unavailable", "KnoxSurvivorAutonomy"
        end
        local ok, created, encoded, partialIds = pcall(function()
            return autonomy.spawnDeveloperScenario(player, "single", {
                runId = state.runId,
                ownerToken = state.ownerToken,
                scenarioId = spec.id,
            })
        end)
        if not ok then return "HARNESS_ERROR", "fixture_spawn_threw", tostring(created) end
        if created ~= true then
            for _, fixtureId in ipairs(parseIds(partialIds)) do
                local registered = KnoxQAManifest.registerFixture(
                    state.fixtureIds, state.fixtureOwners, fixtureId,
                    state.runId, state.ownerToken)
                if not registered then
                    return "HARNESS_ERROR", "partial_fixture_ownership_invalid", tostring(fixtureId)
                end
            end
            return "BLOCKED", "fixture_not_created", tostring(encoded)
        end
        local id = fixtureIdFrom(encoded)
        local registered, registration = KnoxQAManifest.registerFixture(
            state.fixtureIds, state.fixtureOwners, id, state.runId, state.ownerToken)
        if not registered then
            return "HARNESS_ERROR", registration, tostring(encoded)
        end
        local body, square, evidence = nativeFixtureEvidence(id)
        if body == nil or square == nil then
            return "BLOCKED", "native_fixture_not_materialized", evidence
        end
        return "PASS", "native_fixture_observed", evidence
    end

    if spec.kind == "recruitment_observation" then
        local id = state.fixtureIds ~= nil and state.fixtureIds[1] or nil
        if state.fixtureReady ~= true or id == nil then
            return "SKIPPED", "fixture_unavailable", "dependent=QA-ENCOUNTER-001"
        end
        local service = rawget(_G, "KnoxCompanionService")
        if service == nil or service.canRecruit == nil then
            return "BLOCKED", "recruitment_api_unavailable", "KnoxCompanionService"
        end
        local ok, eligible, reason, trust = pcall(function()
            return service.canRecruit(player, id)
        end)
        if not ok then return "HARNESS_ERROR", "recruitment_observation_threw", tostring(eligible) end
        return "PASS", "eligibility_observed", "id=" .. compact(id)
            .. " eligible=" .. tostring(eligible == true)
            .. " reason=" .. compact(reason)
            .. " trust=" .. compact(trust)
            .. " mutation=none"
    end

    if spec.kind == "checkpoint" then
        return "PASS", "checkpoint_recorded", "runId=" .. state.runId
            .. " fixtureCount=" .. tostring(#(state.fixtureIds or {}))
    end

    if spec.kind == "base_task_adapter_gate" then
        -- Fail closed until persistence, storage, and autonomy can roll back
        -- every fixture object by this run's exact ownership token. This path
        -- is read-only and must never fall through to legacy beginBase().
        return KnoxQABaseTaskAdapter.run({
            KnoxPersistence = rawget(_G, "KnoxPersistence"),
            KnoxBaseStorage = rawget(_G, "KnoxBaseStorage"),
            KnoxSurvivorAutonomy = rawget(_G, "KnoxSurvivorAutonomy"),
        })
    end

    if spec.kind == "save_isolation" then
        if state.saveIdentityChanged then
            return "HARNESS_ERROR", "save_identity_changed_during_run", saveEvidence()
        end
        if state.saveIsolation.status == "APPROVED_QA_SAVE" then
            return "PASS", "run_scoped_disposable_save_declaration_validated", saveEvidence()
        end
        return "BLOCKED", "save_isolation_" .. string.lower(state.saveIsolation.status),
            saveEvidence() .. " reason=" .. compact(state.saveIsolation.reason)
    end

    if spec.kind == "cleanup" then
        local clean, evidence = cleanupVerticalFixtures("qa_vertical_slice:" .. state.runId)
        if not clean then return "CLEANUP_ERROR", "owned_fixture_cleanup_failed", evidence end
        return "PASS", "owned_fixture_removed", evidence
    end
    if spec.kind == "human_required" then
        return "SKIPPED", "human_live_acceptance_required",
            "evidenceType=human_required expected=" .. table.concat(spec.expectedEvidence or {}, ",")
    end
    return "HARNESS_ERROR", "unknown_manifest_kind", tostring(spec.kind)
end

local function finishVertical()
    local counts = { PASS = 0, FAIL = 0, BLOCKED = 0, SKIPPED = 0,
        HARNESS_ERROR = 0, TIMEOUT = 0, CLEANUP_ERROR = 0 }
    for _, entry in ipairs(state.results) do counts[entry.status] = (counts[entry.status] or 0) + 1 end
    local status = counts.CLEANUP_ERROR > 0 and "CLEANUP_ERROR"
        or (counts.HARNESS_ERROR > 0 and "HARNESS_ERROR")
        or (counts.TIMEOUT > 0 and "TIMEOUT")
        or (counts.FAIL > 0 and "FAIL" or (counts.BLOCKED > 0 and "BLOCKED" or "PASS"))
    print(TAG .. " SUITE runId=" .. state.runId
        .. " status=" .. status
        .. " pass=" .. tostring(counts.PASS)
        .. " fail=" .. tostring(counts.FAIL)
        .. " blocked=" .. tostring(counts.BLOCKED)
        .. " skipped=" .. tostring(counts.SKIPPED)
        .. " harnessError=" .. tostring(counts.HARNESS_ERROR)
        .. " timeout=" .. tostring(counts.TIMEOUT)
        .. " cleanupError=" .. tostring(counts.CLEANUP_ERROR)
        .. " ticks=" .. tostring(state.ticks)
        .. " evidenceType=in_game_automated"
        .. " manifestVersion=" .. tostring(KnoxQAManifest.VERSION)
        .. " saveIdentity=" .. encoded(state.metadata.saveIdentity)
        .. " saveIdentitySource=" .. compact(state.metadata.saveIdentitySource)
        .. " saveIsolation=" .. compact(state.saveIsolation.status)
        .. " ownerToken=" .. compact(state.ownerToken)
        .. " humanRequired=" .. compact(table.concat(state.humanRequired or {}, ",")))
    state.phase = "FINISHED"
    clearArmedSave("RUN_COMPLETED")
    stop()
end

verticalUpdate = function()
    state.ticks = state.ticks + 1
    local spec = state.manifest[state.stepIndex]
    if spec == nil then finishVertical(); return end
    local currentSave = saveIdentity()
    local initialIdentity = state.metadata.saveIdentity
    local identityChanged = (initialIdentity ~= nil and currentSave.identity ~= initialIdentity)
        or (initialIdentity == nil and currentSave.identity ~= nil)
    if identityChanged and not state.saveIdentityChanged then
        clearArmedSave("SAVE_IDENTITY_CHANGED")
        state.saveIdentityChanged = true
        state.saveIsolation.status = "STALE_OR_MISMATCHED_QA_RUN"
        state.saveIsolation.reason = "save_identity_changed_during_run"
        local gate = KnoxQAManifest.byId["QA-SAVE-ISOLATION-001"]
        if gate ~= nil then
            local gateAlreadyPassed = state.best[gate.id] ~= nil
            state.best[gate.id] = { status = "HARNESS_ERROR", reason = state.saveIsolation.reason }
            if gateAlreadyPassed then
                verticalResult(gate, "HARNESS_ERROR", state.saveIsolation.reason,
                    "initialSave=" .. encoded(initialIdentity)
                        .. " currentSave=" .. encoded(currentSave.identity), "offline")
            end
        end
    end
    if state.stepStarted ~= spec.id then
        state.stepStarted = spec.id
        state.phaseTicks = state.ticks
        verticalCheckpoint(spec, "before_setup")
    end
    if spec.requiresDisposableSave == true and state.saveIdentityChanged then
        verticalResult(spec, "HARNESS_ERROR", "save_identity_changed_during_run", saveEvidence(), "offline")
    elseif spec.requiresDisposableSave == true
        and state.saveIsolation.status ~= "APPROVED_QA_SAVE" then
        verticalResult(spec, "BLOCKED", "disposable_save_not_validated", saveEvidence(), "offline")
    elseif state.ticks - state.phaseTicks > spec.timeout then
        local status, reason, evidence = KnoxQAManifest.timeoutResult(spec)
        verticalResult(spec, status, reason, evidence, "offline")
    else
        local status, reason, evidence = KnoxQAManifest.execute(
            spec, state.best, runVerticalScenario)
        verticalResult(spec, status, reason, evidence)
        if spec.id == "QA-START-001" then state.startReady = status == "PASS" end
        if spec.id == "QA-ENCOUNTER-001" then state.fixtureReady = status == "PASS" end
    end
    if spec.kind == "cleanup" then
        verticalCheckpoint(spec, "after_cleanup")
    end
    state.stepIndex = state.stepIndex + 1
    state.stepStarted = nil
end

update = function()
    if state == nil or state.phase == "FINISHED" then return end
    -- FULL_STEPS predates durable run-scoped ownership and is quarantined.
    -- Keep its historical implementation for traceability, but never execute
    -- it through this opt-in entry point until every fixture adapter is safe.
    if state.mode ~= "vertical_slice" then
        state.phase = "FINISHED"
        print(TAG .. " HARNESS_ERROR scenario=QA-MANIFEST-001 reason=legacy_coordinator_quarantined evidenceType=offline")
        stop()
        return
    end
    local ok, failure = pcall(verticalUpdate)
    if not ok then
        clearArmedSave("COORDINATOR_ERROR")
        local spec = state.manifest[state.stepIndex]
            or KnoxQAManifest.byId["QA-START-001"]
        print(TAG .. " HARNESS_ERROR scenario=" .. spec.id
            .. " reason=coordinator_exception runId=" .. compact(state.runId)
            .. " saveIdentity=" .. encoded(state.metadata.saveIdentity)
            .. " saveIsolation=" .. compact(state.saveIsolation.status)
            .. " error=" .. compact(failure))
        pcall(function()
            verticalResult(spec, "HARNESS_ERROR", "coordinator_exception",
                "error=" .. compact(failure) .. " " .. saveEvidence(), "in_game_automated")
        end)
        state.phase = "FINISHED"
        stop()
    end
end

function QA.status()
    return state
end

function QA.previewStatus()
    local capture = saveIdentity()
    local activeRun = state ~= nil and state.phase ~= "FINISHED"
    local runId = activeRun and state.runId or nil
    local sequence = activeRun and state.runSequence or runSequence + 1
    local isolation, reason = KnoxQASaveIsolation.classify(
        capture, armedSaveDeclaration, runId or "pending", sequence)
    if state ~= nil and state.phase ~= "FINISHED" then
        isolation, reason = state.saveIsolation.status, state.saveIsolation.reason
    end
    local scenarios = {}
    for _, spec in ipairs(VERTICAL_MANIFEST) do
        local previous = activeRun and state.best ~= nil and state.best[spec.id] or nil
        local disposition
        if previous ~= nil then
            disposition = previous.status
        elseif spec.humanConfirmation == true then
            disposition = spec.requiresDisposableSave == true
                and isolation ~= "APPROVED_QA_SAVE"
                and "BLOCKED_HUMAN_REQUIRED" or "HUMAN_REQUIRED"
        elseif spec.requiresDisposableSave == true and isolation ~= "APPROVED_QA_SAVE" then
            disposition = "BLOCKED"
        elseif spec.requiresDisposableSave == true then
            disposition = "DESTRUCTIVE_READY"
        else
            disposition = "READ_ONLY"
        end
        scenarios[#scenarios + 1] = {
            id = spec.id,
            disposition = disposition,
            humanRequired = spec.humanConfirmation == true,
            requiresDisposableSave = spec.requiresDisposableSave == true,
        }
    end
    return {
        saveIdentity = capture.identity,
        saveIdentitySource = capture.source,
        isolationStatus = isolation,
        isolationReason = reason,
        armed = armedSaveDeclaration ~= nil and (state == nil or state.phase == "FINISHED"),
        armedIdentity = armedSaveDeclaration ~= nil and armedSaveDeclaration.identity or nil,
        nextRunSequence = runSequence + 1,
        runId = runId,
        runPhase = state ~= nil and state.phase or "NONE",
        scenarios = scenarios,
    }
end

function QA.start(playerNum)
    -- Every start attempt consumes a pending approval, including refused
    -- starts, so an error cannot leave a reusable destructive capability.
    local startingArm = armedSaveDeclaration
    clearArmedSave("CONSUMED_BY_START_ATTEMPT")
    if state ~= nil and state.phase ~= "FINISHED" then
        return false, "already_running"
    end
    if KnoxSettings == nil or KnoxSettings.automatedQAMode == nil
        or not KnoxSettings.automatedQAMode() then
        print(TAG .. " DISABLED automated_q_a_mode=false")
        return false, "automated_qa_disabled"
    end
    local manifestValid, manifestResult = KnoxQAManifest.validate(VERTICAL_MANIFEST)
    if not manifestValid then
        print(TAG .. " HARNESS_ERROR scenario=QA-MANIFEST-001 reason="
            .. compact(manifestResult) .. " evidenceType=offline")
        return false, "manifest_invalid:" .. tostring(manifestResult)
    end
    local capture = saveIdentity()
    local runId = nextRunId()
    local ownerToken = runId .. "-fixture-owner"
    local isolationStatus, isolationReason = KnoxQASaveIsolation.classify(
        capture, startingArm, runId, runSequence)
    local declarationUsed = startingArm ~= nil
        and isolationStatus == "APPROVED_QA_SAVE"
    -- The declaration is one-run, process-memory state. Reloads never restore
    -- it and therefore cannot silently resume destructive QA.
    state = {
        mode = "vertical_slice",
        phase = "RUNNING",
        playerNum = tonumber(playerNum) or 0,
        ticks = 0,
        phaseTicks = 0,
        results = {},
        best = {},
        checkpoints = {},
        manifest = VERTICAL_MANIFEST,
        stepIndex = 1,
        stepStarted = nil,
        fixtureIds = {},
        fixtureOwners = {},
        runId = runId,
        runSequence = runSequence,
        ownerToken = ownerToken,
        saveIsolation = {
            status = isolationStatus,
            reason = isolationReason,
            declared = declarationUsed,
        },
        saveIdentityChanged = false,
        humanRequired = {},
        metadata = {
            build = buildVersion(),
            saveIdentity = capture.identity,
            saveIdentitySource = capture.source,
            save = encoded(capture.identity),
            mod = compact(rawget(_G, "KnoxSurvivors") ~= nil
                and rawget(_G, "KnoxSurvivors").VERSION or "unavailable"),
            runtime = runtimeStatus(),
            timestamp = tostring(getTimestampMs ~= nil and safeValue(getTimestampMs) or worldHours()),
        },
    }
    local scenarioNames = {}
    for _, spec in ipairs(VERTICAL_MANIFEST) do
        scenarioNames[#scenarioNames + 1] = spec.id
        if spec.humanConfirmation == true then
            state.humanRequired[#state.humanRequired + 1] = spec.id
        end
    end
    print(TAG .. " START runId=" .. state.runId
        .. " ownerToken=" .. state.ownerToken
        .. " saveIdentity=" .. encoded(state.metadata.saveIdentity)
        .. " saveIdentitySource=" .. compact(state.metadata.saveIdentitySource)
        .. " saveIsolation=" .. compact(state.saveIsolation.status)
        .. " saveDeclaration=" .. (state.saveIsolation.declared and "run_scoped" or "none")
        .. " runSequence=" .. tostring(runSequence)
        .. " player=" .. tostring(state.playerNum)
        .. " build=" .. state.metadata.build
        .. " save=" .. state.metadata.save
        .. " mod=" .. state.metadata.mod
        .. " runtime=" .. state.metadata.runtime
        .. " timestamp=" .. compact(state.metadata.timestamp)
        .. " scenarios=" .. table.concat(scenarioNames, ",")
        .. " manifestVersion=" .. tostring(KnoxQAManifest.VERSION)
        .. " evidenceType=in_game_automated"
        .. " scope=controlled_fixture_not_natural_encounter")
    stop()
    Events.OnTick.Add(update)
    return true, "started:" .. runId
end

function QA.armDisposableSave(expectedSaveIdentity, acknowledgement)
    if KnoxSettings == nil or KnoxSettings.automatedQAMode == nil
        or not KnoxSettings.automatedQAMode()
        or KnoxSettings.developerToolsEnabled == nil
        or not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_and_automated_qa_required"
    end
    local capture = saveIdentity()
    local armed, declaration = KnoxQASaveIsolation.arm(capture,
        expectedSaveIdentity, acknowledgement, runSequence + 1)
    if not armed then
        print(TAG .. " SAVE_ARM status=" .. compact(declaration)
            .. " saveIdentity=" .. encoded(capture.identity)
            .. " saveIdentitySource=" .. compact(capture.source)
            .. " expectedSaveIdentity=" .. encoded(expectedSaveIdentity)
            .. " nextRunSequence=" .. tostring(runSequence + 1))
        return false, declaration
    end
    armedSaveDeclaration = declaration
    if Events ~= nil and Events.OnTick ~= nil and Events.OnTick.Add ~= nil then
        armedSaveWatcher = watchArmedSaveIdentity
        Events.OnTick.Add(armedSaveWatcher)
    end
    print(TAG .. " SAVE_ARM status=ARMED_FOR_NEXT_RUN"
        .. " saveIdentity=" .. encoded(declaration.identity)
        .. " saveIdentitySource=" .. compact(declaration.source)
        .. " nextRunSequence=" .. tostring(declaration.nextRunSequence)
        .. " acknowledgement=explicit_owner_confirmation")
    return true, "armed_for_next_run"
end

local function onGameStart()
    if KnoxSettings == nil or KnoxSettings.automatedQAMode == nil
        or not KnoxSettings.automatedQAMode() then
        -- Foolproofing: the sandbox flag alone is not enough, and a silent
        -- no-start leaves an empty report that looks like a useless suite.
        local sandbox = rawget(_G, "SandboxVars")
        local qaRequested = sandbox ~= nil and sandbox.KnoxSurvivors ~= nil
            and sandbox.KnoxSurvivors.AutomatedQAMode == true
        if qaRequested then
            print(TAG .. " BLOCKED automated_q_a_requires_enable_developer_tools"
                .. " enable_both=EnableDeveloperTools,RunAutomatedKnoxQA"
                .. " scenario_must_be=None")
        end
        return
    end
    local playerNum = 0
    QA.start(playerNum)
end

local function onMainMenuEnter()
    stop()
    -- An armed declaration never survives a world/menu transition.
    clearArmedSave("MENU_OR_RELOAD_BOUNDARY")
    if state ~= nil and state.mode == "vertical_slice" and state.phase ~= "FINISHED" then
        local currentSave = saveIdentity()
        local sameSave = state.metadata.saveIdentity ~= nil
            and currentSave.identity == state.metadata.saveIdentity
        local cleaned, evidence
        if not sameSave or state.saveIsolation.status ~= "APPROVED_QA_SAVE" then
            cleaned, evidence = false, "cleanup_refused_save_identity_or_isolation_unverified"
        else
            cleaned, evidence = cleanupVerticalFixtures("qa_vertical_abort:" .. tostring(state.runId))
        end
        local cleanupSpec = KnoxQAManifest.byId["QA-CLEANUP-001"]
        verticalResult(cleanupSpec, cleaned and "PASS" or "CLEANUP_ERROR",
            cleaned and "aborted_run_cleanup_verified" or "abort_cleanup_failed",
            evidence, "in_game_automated")
    end
    -- The legacy full coordinator is quarantined. A menu transition must not
    -- invoke its global test-NPC, job-matrix, or combat cleanup paths.
    state = nil
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

return QA
