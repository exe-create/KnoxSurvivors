-- Declarative QA catalog and pure coordinator contract.
-- Engine behavior remains owned by the scenario adapters; this module only
-- validates scenario metadata, dependencies, statuses, and fixture provenance.
local Manifest = {}

Manifest.VERSION = 2
Manifest.STATUSES = {
    PASS = true, FAIL = true, BLOCKED = true, SKIPPED = true,
    HARNESS_ERROR = true, TIMEOUT = true, CLEANUP_ERROR = true,
}

local function scenario(id, task, category, kind, prerequisites, setup, actions,
    timeout, expectedEvidence, cleanup, area, mutations, humanConfirmation, evidenceType)
    return {
        id = id,
        task = task,
        category = category,
        kind = kind,
        prerequisites = prerequisites or {},
        setup = setup,
        actions = actions,
        timeout = timeout,
        expectedEvidence = expectedEvidence,
        cleanup = cleanup,
        area = area,
        allowedMutations = mutations or {},
        evidenceType = evidenceType or (humanConfirmation and "human_required" or "in_game_automated"),
        humanConfirmation = humanConfirmation == true,
    }
end

-- The unattended set is intentionally limited to readiness and one isolated,
-- QA-owned survivor encounter. Broader native paths are visible in the same
-- manifest but remain human-required until fixture rollback is proven.
Manifest.scenarios = {
    scenario("QA-START-001", "KS-PROD-008", "foundation", "readiness", {},
        "Read current player, build, save and runtime readiness.",
        { "validate player square", "ping runtime bridge" }, 600,
        { "build", "save", "mod", "runtime" },
        "No world mutation.", "loaded_player_square", {}, false),
    scenario("QA-SAVE-ISOLATION-001", "KS-PROD-011", "foundation", "save_isolation",
        { "QA-START-001" },
        "Classify the exact current save and the current run's in-memory owner declaration.",
        { "verify native save identity", "verify one-run explicit QA-save arm" }, 120,
        { "saveIdentity", "saveIdentitySource", "isolationStatus", "runBinding" },
        "No world mutation; the arm is consumed by this run and never survives reload.",
        "report only", {}, false),
    scenario("QA-SURVIVOR-OBS-001", "KS-PROD-011", "population", "survivor_snapshot",
        { "QA-START-001" },
        "Read persisted survivor identities and currently materialized bodies without mutation.",
        { "enumerate canonical survivor IDs", "observe identity/body/square where loaded" }, 240,
        { "survivorIds", "identityNames", "loadedBodyCount", "coordinates" },
        "No world or persistence mutation.", "loaded_player_context", {}, false,
        "in_game_observation"),
    scenario("QA-BASE-STATE-OBS-001", "KS-PROD-011", "base", "base_snapshot",
        { "QA-START-001" },
        "Read existing base, task, resident duty/work status without changing ownership.",
        { "enumerate base/task state", "read resident work projections" }, 240,
        { "baseIds", "taskStates", "residentWorkStates" },
        "No world or persistence mutation.", "persisted_base_state", {}, false,
        "in_game_observation"),
    scenario("QA-GROUP-FACTION-OBS-001", "KS-PROD-011", "groups_factions", "group_faction_snapshot",
        { "QA-START-001" },
        "Read canonical travel-group and faction roster membership.",
        { "enumerate group IDs/leaders/members", "enumerate faction IDs/leaders/members" }, 240,
        { "groupIds", "groupMembers", "factionIds", "factionMembers" },
        "No world or persistence mutation.", "persisted_group_faction_state", {}, false,
        "in_game_observation"),
    scenario("QA-CLEANUP-STALE-001", "KS-PROD-008", "foundation", "stale_cleanup",
        { "QA-SAVE-ISOLATION-001" }, "Find only persistent Knox QA survivor ownership tags from prior runs.",
        { "remove exact tagged survivor fixtures", "verify no body remains" }, 900,
        { "runId", "ownerToken", "survivorId", "nativeRemovalReceipt" },
        "Remove only records whose persisted runId and ownerToken both match.",
        "current_loaded_cell", { "qa_owned_survivor" }, false),
    scenario("QA-BASE-ADAPTER-001", "KS-PROD-011", "base", "base_task_adapter_gate",
        { "QA-START-001" },
        "Inspect whether exact rollback exists for a disposable base, zones, tasks, reservations, native materials, and resident duty.",
        { "verify rollback contracts without creating or changing any world state" }, 120,
        { "missingOwnerContracts", "noWorldMutation", "baseScenarioDisposition" },
        "No fixture exists; no cleanup mutation is permitted.",
        "report only", {}, false),
    scenario("QA-ENCOUNTER-001", "KS-PROD-008", "encounters", "encounter_fixture",
        { "QA-SAVE-ISOLATION-001", "QA-CLEANUP-STALE-001" },
        "Spawn one native Knox developer survivor adjacent to the player.",
        { "materialize fixture", "observe identity and loaded body" }, 900,
        { "survivorId", "origin", "nativeBody", "square", "runId" },
        "Remove the exact current-run fixture after dependent observation.",
        "same-floor loaded area near player", { "qa_owned_survivor" }, false),
    scenario("QA-RECRUIT-001", "KS-PROD-008", "encounters", "recruitment_observation",
        { "QA-ENCOUNTER-001" }, "Use the encounter fixture created earlier in this run.",
        { "read recruitment eligibility without mutating relationship or membership" }, 900,
        { "survivorId", "eligibility", "reason", "relationshipBeforeAfter" },
        "No additional mutation; fixture remains owned by QA-ENCOUNTER-001.",
        "same fixture area", {}, false),
    scenario("QA-CHECKPOINT-001", "KS-PROD-008", "foundation", "checkpoint", {},
        "Write a scalar checkpoint for the active run.", { "record phase and evidence reference" }, 120,
        { "runId", "scenarioId", "timestamp", "evidenceReference" },
        "No world mutation.", "report only", {}, false),
    scenario("QA-CLEANUP-001", "KS-PROD-008", "foundation", "cleanup", {},
        "Close current run fixtures after all dependent observations.",
        { "remove only matching current-run survivor IDs", "verify no body remains" }, 900,
        { "survivorId", "nativeRemovalReceipt", "cleanupResult" },
        "Require persisted runId and ownerToken equality for every removed identity.",
        "same fixture area", { "qa_owned_survivor" }, false),
    scenario("QA-BASE-001", "BUG-KS-013", "base", "human_required",
        { "QA-START-001" }, "Use a disposable save and a player-owned base with a resident.",
        { "provide one real-resource task", "observe claim, route, native action, result, reassessment" }, 18000,
        { "residentId", "baseId", "taskId", "claim", "nativeAction", "worldResult", "reassessment" },
        "Human restores disposable save; no automated cleanup is approved yet.",
        "owner-designated disposable base", {}, true),
    scenario("QA-MELEE-001", "BUG-KS-029", "combat", "human_required",
        { "QA-START-001" }, "Use one QA-owned survivor and one QA-owned zombie in a bounded disposable area.",
        { "observe native melee attempt", "verify real hit, health or death state" }, 3600,
        { "survivorId", "zombieId", "weapon", "nativeAction", "beforeAfterHealth" },
        "Remove only exact QA-owned fixtures; unresolved ownership blocks cleanup.",
        "owner-designated disposable combat area", {}, true),
    scenario("QA-FIREARM-001", "BUG-KS-029", "combat", "human_required",
        { "QA-START-001" }, "Use a disposable save with an explicitly isolated armed survivor and target.",
        { "observe ready weapon and real ammunition", "reload and fire", "verify native hit/damage" }, 5400,
        { "survivorId", "targetId", "weapon", "ammoBeforeAfter", "nativeHitOrDamage" },
        "Remove only exact QA-owned fixtures and recover test equipment from the disposable save.",
        "owner-designated disposable combat area", {}, true),
    scenario("QA-GROUP-001", "BUG-KS-028", "groups_factions", "human_required",
        { "QA-START-001" }, "Use a disposable group or faction fixture with canonical member IDs.",
        { "issue one leader/follower or faction duty", "observe membership and native movement continuity" }, 5400,
        { "groupId", "factionId", "leaderId", "memberIds", "directive", "nativePositions" },
        "Remove only exact QA-owned members and their explicitly tagged fixture domain.",
        "owner-designated disposable group area", {}, true),
    scenario("QA-VEHICLE-001", "BUG-KS-030", "vehicles", "human_required",
        { "QA-START-001" }, "Use a disposable save with a QA-owned survivor and an isolated real vehicle.",
        { "observe driver/passenger entry and exit", "issue destination", "interrupt", "save and reload" }, 7200,
        { "survivorId", "vehicleId", "seatRole", "nativeMovement", "orders", "membership", "reloadState" },
        "Human restores the disposable save; no vehicle/world cleanup is approved yet.",
        "owner-designated disposable vehicle area", {}, true),
    scenario("QA-RELOAD-001", "KS-PROD-005", "persistence", "human_required",
        { "QA-START-001" }, "Save during a documented QA-owned survivor scenario and reload the same disposable save.",
        { "compare stable identity, body count, inventory, orders and membership" }, 7200,
        { "saveId", "survivorIds", "bodyCount", "inventory", "orders", "membership" },
        "Human keeps or restores the disposable save; harness never edits unrelated records.",
        "disposable save", {}, true),
    scenario("QA-UI-001", "KS-PROD-011", "ui", "human_required",
        { "QA-START-001" }, "Use the current Build 42 UI scale and a narrow viewport/joypad where applicable.",
        { "check Notebook, schedule, map markers, radial/context actions, feed and world-input pass-through" }, 1800,
        { "visibleControls", "selectedContext", "mapProjection", "mouseInput", "joypadInput", "worldInput" },
        "No world mutation; human closes test UI and records visual/input result.",
        "loaded player UI", {}, true),
    scenario("QA-HUMAN-FEEL-001", "KS-PROD-011", "experience", "human_required",
        { "QA-START-001" }, "Observe survivors during an ordinary disposable-save play session.",
        { "judge base usefulness", "movement naturalness", "conversation context", "combat readability", "survivor discoverability" }, 3600,
        { "humanNotes", "saveId", "build", "scenarioContext" },
        "No harness cleanup; retain only human notes and restore save if needed.",
        "owner-selected ordinary play area", {}, true),
}

-- Every scenario that can touch native/world state, or whose human replay
-- deliberately changes it, depends on the run-scoped save isolation verdict.
-- The read-only start, preflight, checkpoint, and UI observation remain
-- available when a player save is ordinary or cannot be classified.
local requireDisposableSave = {
    ["QA-CLEANUP-STALE-001"] = true,
    ["QA-ENCOUNTER-001"] = true,
    ["QA-CLEANUP-001"] = true,
    ["QA-BASE-001"] = true,
    ["QA-MELEE-001"] = true,
    ["QA-FIREARM-001"] = true,
    ["QA-GROUP-001"] = true,
    ["QA-VEHICLE-001"] = true,
    ["QA-RELOAD-001"] = true,
    ["QA-HUMAN-FEEL-001"] = true,
}
for _, spec in ipairs(Manifest.scenarios) do
    if requireDisposableSave[spec.id] then
        spec.requiresDisposableSave = true
        local hasGate = false
        for _, dependency in ipairs(spec.prerequisites) do
            if dependency == "QA-SAVE-ISOLATION-001" then hasGate = true; break end
        end
        if not hasGate then
            table.insert(spec.prerequisites, "QA-SAVE-ISOLATION-001")
        end
    else
        spec.requiresDisposableSave = false
    end
end

local byId = {}
for _, spec in ipairs(Manifest.scenarios) do
    if byId[spec.id] ~= nil then
        Manifest.validationError = "duplicate_scenario_id:" .. tostring(spec.id)
        break
    end
    byId[spec.id] = spec
end
Manifest.byId = byId

function Manifest.validate(scenarios)
    if type(scenarios) ~= "table" then return false, "manifest_not_table" end
    local seen = {}
    for _, spec in ipairs(scenarios) do
        if type(spec) ~= "table" then return false, "scenario_not_table" end
        if type(spec.id) ~= "string" or spec.id == "" or seen[spec.id] then
            return false, "scenario_id_missing_or_duplicate"
        end
        seen[spec.id] = true
        for _, key in ipairs({ "task", "category", "kind", "setup", "actions",
            "expectedEvidence", "cleanup", "area", "evidenceType" }) do
            if spec[key] == nil then return false, spec.id .. ":missing_" .. key end
        end
        if spec.humanConfirmation == nil then
            return false, spec.id .. ":missing_human_confirmation_requirement"
        end
        if spec.requiresDisposableSave ~= nil and type(spec.requiresDisposableSave) ~= "boolean" then
            return false, spec.id .. ":invalid_disposable_save_requirement"
        end
        if type(spec.prerequisites) ~= "table" or type(spec.actions) ~= "table"
            or type(spec.expectedEvidence) ~= "table" or type(spec.allowedMutations) ~= "table" then
            return false, spec.id .. ":invalid_list_field"
        end
        if tonumber(spec.timeout) == nil or tonumber(spec.timeout) <= 0 then
            return false, spec.id .. ":invalid_timeout"
        end
        if spec.humanConfirmation == true and spec.evidenceType ~= "human_required" then
            return false, spec.id .. ":human_evidence_mismatch"
        end
        for _, dependency in ipairs(spec.prerequisites) do
            if not seen[dependency] then return false, spec.id .. ":unknown_or_forward_dependency:" .. tostring(dependency) end
        end
        if spec.requiresDisposableSave == true
            and not seen["QA-SAVE-ISOLATION-001"] then
            return false, spec.id .. ":missing_save_isolation_dependency"
        end
    end
    return true, #scenarios
end

function Manifest.dependencyStatus(spec, results)
    for _, dependency in ipairs(spec.prerequisites or {}) do
        local result = results ~= nil and results[dependency] or nil
        if result == nil then return false, "BLOCKED", dependency end
        if result.status ~= "PASS" then
            return false, "BLOCKED", dependency .. ":" .. tostring(result.status)
        end
    end
    return true, "READY"
end

function Manifest.normalizeStatus(status)
    return Manifest.STATUSES[status] == true and status or "HARNESS_ERROR"
end

function Manifest.execute(spec, results, runner)
    local ready, status, dependency = Manifest.dependencyStatus(spec, results)
    if not ready then return status, "dependency_not_passed", dependency end
    if type(runner) ~= "function" then
        return "HARNESS_ERROR", "scenario_runner_unavailable", spec.id
    end
    local ok, resultStatus, reason, evidence = pcall(runner, spec)
    if not ok then return "HARNESS_ERROR", "scenario_exception", tostring(resultStatus) end
    return Manifest.normalizeStatus(resultStatus), reason, evidence
end

function Manifest.timeoutResult(spec)
    return Manifest.normalizeStatus("TIMEOUT"), "scenario_timeout",
        "timeoutTicks=" .. tostring(spec.timeout)
end

function Manifest.isOwnedFixture(runId, ownerToken, owner)
    return type(owner) == "table"
        and type(runId) == "string" and runId ~= ""
        and type(ownerToken) == "string" and ownerToken ~= ""
        and owner.runId == runId and owner.ownerToken == ownerToken
end

function Manifest.registerFixture(ids, owners, id, runId, ownerToken)
    if type(ids) ~= "table" or type(owners) ~= "table"
        or type(id) ~= "string" or string.find(id, "ks-dev-", 1, true) ~= 1
        or type(runId) ~= "string" or runId == ""
        or type(ownerToken) ~= "string" or ownerToken == "" then
        return false, "fixture_ownership_invalid"
    end
    if owners[id] ~= nil then return false, "fixture_already_registered" end
    owners[id] = { runId = runId, ownerToken = ownerToken }
    ids[#ids + 1] = id
    return true, "registered"
end

function Manifest.runId(timestamp, sequence)
    return "ksqa-" .. tostring(timestamp or "unavailable") .. "-" .. tostring(sequence or 1)
end

_G.KnoxQAManifest = Manifest
return Manifest
