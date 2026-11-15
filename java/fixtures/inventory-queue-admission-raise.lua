-- Live play 2026-11-10 (42.22.2, f:5791/f:14326) showed the native timed-action
-- add path raise on its return (ReturnValues.put:61 via LuaJavaInvoker.call:185
-- through ISBaseTimedAction.begin:88) instead of returning a queue. After the
-- admission guard, a raise converts to the existing <kind>_queue_refused
-- refusal named by the controller, and a normal admission is unchanged. Runs
-- inside the gap04 scope where the real InventoryActions module is loaded
-- (gap04_inventory_source).
local Actions = assert(rawget(_G, "KnoxInventoryActions"),
    "inventory owner missing (needs gap04_inventory_source)")
assert(type(Actions.queueTransfer) == "function", "queueTransfer missing")

local character, item, source, destination = {}, {}, {}, {}
local savedQueue, savedEvents = rawget(_G, "ISTimedActionQueue"),
    rawget(_G, "KnoxEventRuntime")

-- Scenario 1: the native add raises on return -> named refusal, no unwind.
KnoxEventRuntime = nil
ISTimedActionQueue = {
    queues = {},
    add = function()
        error("kahlua_invoker_return_path_npe")
    end,
}
local action, reason = Actions.queueTransfer(character, item, source, destination, nil, nil)
assert(action == nil, "an admission raise must refuse, not return an action")
assert(reason == "transfer_queue_refused",
    "named refusal expected, got " .. tostring(reason))

-- Scenario 2: a normal admission keeps the action + result passthrough.
local queue = { name = "stub-queue" }
ISTimedActionQueue = {
    queues = { [character] = queue },
    add = function()
        return queue
    end,
}
local admitted, queued = Actions.queueTransfer(character, item, source, destination, nil, nil)
assert(admitted ~= nil and queued == "queued",
    "normal admission must stay the unchanged passthrough, got "
        .. tostring(admitted) .. ", " .. tostring(queued))

ISTimedActionQueue = savedQueue
KnoxEventRuntime = savedEvents
