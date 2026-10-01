-- Fail-closed readiness gate for future in-game base-task QA.
-- This module does not create bases, zones, tasks, items, or survivors. The
-- current persistence/storage owners cannot yet roll back a complete isolated
-- base fixture, so the coordinator must report BLOCKED before any mutation.
local Adapter = {}

Adapter.REQUIRED_CONTRACTS = {
    { owner = "KnoxPersistence", api = "beginQaBaseTaskFixture",
        reason = "run_owned_base_zone_task_and_resident_rollback" },
    { owner = "KnoxPersistence", api = "rollbackQaBaseTaskFixture",
        reason = "exact_base_zone_task_storage_policy_and_duty_restore" },
    { owner = "KnoxBaseStorage", api = "createQaMaterialFixture",
        reason = "run_owned_native_material_item_receipt" },
    { owner = "KnoxBaseStorage", api = "rollbackQaMaterialFixture",
        reason = "exact_native_item_cleanup_after_partial_transfer" },
    { owner = "KnoxSurvivorAutonomy", api = "cleanupQaBaseTaskReservations",
        reason = "release_task_and_storage_reservations_after_abort" },
    { owner = "KnoxQABaseTaskAdapter", api = "createIsolatedNativeTarget",
        reason = "native_work_target_owned_by_this_disposable_run" },
    { owner = "KnoxQABaseTaskAdapter", api = "rollbackIsolatedNativeTarget",
        reason = "restore_or_remove_exact_target_after_success_or_partial_action" },
}

function Adapter.inspect(owners)
    owners = type(owners) == "table" and owners or {}
    local missing = {}
    for _, contract in ipairs(Adapter.REQUIRED_CONTRACTS) do
        local owner = owners[contract.owner]
        if type(owner) ~= "table" or type(owner[contract.api]) ~= "function" then
            missing[#missing + 1] = contract.owner .. "." .. contract.api
                .. "(" .. contract.reason .. ")"
        end
    end
    if #missing > 0 then
        return false, "qa_base_fixture_rollback_unavailable", table.concat(missing, ";")
    end
    -- Presence of APIs alone must not activate a scenario whose complete
    -- native receipt and rollback semantics have not been implemented here.
    return false, "qa_base_task_adapter_not_implemented",
        "contract_present_but_no_native_scenario_executor"
end

function Adapter.run(owners)
    local ready, reason, evidence = Adapter.inspect(owners)
    return "BLOCKED", reason, evidence
end

_G.KnoxQABaseTaskAdapter = Adapter
return Adapter
