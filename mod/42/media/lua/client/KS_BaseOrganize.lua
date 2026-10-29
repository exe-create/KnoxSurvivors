require "KS_BaseStorage"
require "KS_SurvivorInventoryActions"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

-- Ambient re-shelving: idle residents carry one misplaced or demoted item
-- to its best shelf. This is deliberately NOT a task-board job (central
-- sorting stays retired): one bounded round per idle decision, chosen only
-- when the destination is meaningfully better, executed through the same
-- native transfers as cleanup deposits so nothing is fabricated,
-- duplicated, or deleted. An interrupted carry simply stays in the pocket
-- for the next cleanup pass.
local Organize = {}
KnoxBaseOrganize = Organize

local SCAN_RADIUS = 16
local MAX_INSPECT = 40
local STEP_TIMEOUT_TICKS = 1800

local function call(value, name, fallback, ...)
    if value == nil then return fallback end
    local method = value[name]
    if method == nil then return fallback end
    local ok, result = pcall(method, value, ...)
    if ok and result ~= nil then return result end
    return fallback
end

local function bounds(region)
    local x1 = tonumber(region.x1 or region.minX)
    local y1 = tonumber(region.y1 or region.minY)
    if x1 == nil or y1 == nil then return nil end
    local x2 = tonumber(region.x2 or region.maxX) or x1 + (tonumber(region.width) or 1) - 1
    local y2 = tonumber(region.y2 or region.maxY) or y1 + (tonumber(region.height) or 1) - 1
    return math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
end

local function itemIdentity(item)
    if item == nil then return nil end
    local ok, id = pcall(function() return item:getID() end)
    if ok and id ~= nil then return "id:" .. tostring(id) end
    return nil
end

-- Best shelf for an item among loaded filtered policies, ranked exactly
-- like deposits (priority, exactness, distance). Returns the policy key.
local function bestPolicyFor(base, character, item, excludeKey, destinationReserved)
    if base == nil or character == nil or item == nil then return nil end
    local origin = call(character, "getCurrentSquare", nil)
    if origin == nil then return nil end
    local best, bestRank, bestExact, bestDistance = nil, nil, nil, nil
    for _, policy in ipairs(KnoxBaseStorage.operationalPolicies(base)) do
        -- An automatically discovered container is only a deposit fallback.
        -- Organizing should move misplaced items toward an explicit filter,
        -- never shuffle them between otherwise-unfiltered chests.
        local destination = policy.key ~= excludeKey and policy.transientContainer ~= true
            and (destinationReserved == nil or not destinationReserved(policy))
            and KnoxBaseStorage.acceptsDeposit(policy, item)
            and KnoxBaseStorage.resolvePolicy(policy) or nil
        if destination ~= nil
            and KnoxBaseStorage.canReceiveItem(destination.container, character, item) then
            local rank = KnoxBaseStorage.priorityRank ~= nil
                and KnoxBaseStorage.priorityRank(policy) or 2
            local exact = KnoxBaseStorage.classifyItem ~= nil
                and KnoxBaseStorage.classifyItem(item) == policy.storageRole
            local dx = (tonumber(policy.x) or origin:getX()) - origin:getX()
            local dy = (tonumber(policy.y) or origin:getY()) - origin:getY()
            local distance = dx * dx + dy * dy
            if best == nil or rank < bestRank
                or (rank == bestRank and exact and not bestExact)
                or (rank == bestRank and exact == bestExact and distance < bestDistance) then
                best, bestRank, bestExact, bestDistance = policy, rank, exact, distance
            end
        end
    end
    return best
end

-- One organize round: scan nearby loaded base containers for an item whose best
-- shelf is meaningfully better. Meaningful means a strictly higher
-- priority tier, or a misplaced item (its shelf rejects it) moving to a
-- shelf that accepts it. Equal-tier shuffles never qualify, so settled
-- bases stay settled.
function Organize.find(base, character, available, reserved, destinationReserved)
    if base == nil or character == nil or getCell == nil or getCell() == nil then
        return nil, "organize_unavailable"
    end
    local origin = call(character, "getCurrentSquare", nil)
    if origin == nil then return nil, "organize_unavailable" end
    local oz = origin:getZ()
    local inspected = 0
    for _, policy in ipairs(KnoxBaseStorage.operationalPolicies(base)) do
        local dx = (tonumber(policy.x) or math.huge) - origin:getX()
        local dy = (tonumber(policy.y) or math.huge) - origin:getY()
        if (tonumber(policy.z) or 0) == oz and dx * dx + dy * dy <= SCAN_RADIUS * SCAN_RADIUS then
            local resolved = KnoxBaseStorage.resolvePolicy(policy)
            local container = resolved ~= nil and resolved.container or nil
            if container ~= nil then
                local items = call(container, "getItems", nil)
                if items ~= nil then
                    for i = 0, items:size() - 1 do
                        if inspected >= MAX_INSPECT then return nil, "shelves_settled" end
                        inspected = inspected + 1
                        local item = items:get(i)
                        local identity = itemIdentity(item)
                        local favorite = call(item, "isFavorite", false) == true
                        if item ~= nil and identity ~= nil and not favorite
                            and (available == nil or available(item))
                            and (reserved == nil or not reserved(item)) then
                            local misplaced = policy.transientContainer == true
                                or not KnoxBaseStorage.acceptsDeposit(policy, item)
                            local best = bestPolicyFor(base, character, item, policy.key, destinationReserved)
                            if best ~= nil then
                                local srcRank = KnoxBaseStorage.priorityRank ~= nil
                                    and KnoxBaseStorage.priorityRank(policy) or 2
                                local dstRank = KnoxBaseStorage.priorityRank ~= nil
                                    and KnoxBaseStorage.priorityRank(best) or 2
                                -- Meaningfully better only: a strictly higher
                                -- priority tier, or a misplaced item moving to
                                -- any shelf that accepts it. Equal-tier
                                -- shuffles never qualify, so settled bases
                                -- stay settled.
                                if dstRank < srcRank or misplaced then
                                    return {
                                        item = item,
                                        itemKey = identity,
                                        source = container,
                                        sourcePolicy = policy,
                                        destinationPolicy = best,
                                        baseId = base.id,
                                        phase = "prepare",
                                    }, "found"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, "shelves_settled"
end

function Organize.cancelAction(character, plan, retireActions)
    if plan ~= nil then plan.cancelled = true end
    if plan ~= nil and retireActions ~= nil then
        -- The controller owns mixed-queue cancellation and its drain latch.
        -- Revoke permission first, including actions whose begin() threw
        -- before admission could return their identity.
        retireActions({plan})
    else
        local queue = ISTimedActionQueue.getTimedActionQueue(character)
        if plan ~= nil and plan.action ~= nil and queue:indexOf(plan.action) ~= -1 then
            if queue.current == plan.action then ISTimedActionQueue.clear(character)
            else plan.action:forceCancel(); queue:removeFromQueue(plan.action) end
        end
    end
    if plan ~= nil then plan.action = nil; plan.guard = nil end
end

local function moveTo(plan, square, character, bridge, id, ticks, phase)
    local approach = AdjacentFreeTileFinder.Find(square, character)
    if approach == nil then return "failed", "organize_storage_unreachable" end
    local result = tostring(bridge:moveNpc(id, approach))
    if result:find("MOVE_STARTED", 1, true) ~= 1 then
        return "failed", "organize_route:" .. result
    end
    plan.phase, plan.moveStarted = phase, ticks
    return "working"
end

local function sourceSquare(base, plan)
    local policy = plan.sourcePolicy
    if policy == nil or getCell == nil or getCell() == nil then return nil end
    return getCell():getGridSquare(
        tonumber(policy.x) or 0, tonumber(policy.y) or 0, tonumber(policy.z) or 0)
end

-- Native storage movement ends beside furniture. Pickup and deposit must
-- agree on usable reach, otherwise arriving beside a cupboard restarts the
-- same route forever. Walls and different floors still require movement.
local function withinReach(character, square)
    local origin = character:getCurrentSquare()
    return origin ~= nil and square ~= nil and origin:getZ() == square:getZ()
        and (origin:getX() - square:getX()) ^ 2
            + (origin:getY() - square:getY()) ^ 2 <= 2
        and (origin == square or (origin.isSomethingTo ~= nil
            and not origin:isSomethingTo(square)))
end

local function depositDestination(base, plan)
    for _, policy in ipairs(KnoxBaseStorage.operationalPolicies(base)) do
        if policy.key == plan.destinationPolicy.key then
            if not KnoxBaseStorage.acceptsDeposit(policy, plan.item) then
                return nil, "organize_filter_changed"
            end
            local resolved = KnoxBaseStorage.resolvePolicy(policy)
            if resolved ~= nil then return resolved end
            break
        end
    end
    return nil, "organize_destination_gone"
end

function Organize.step(plan, character, base, bridge, id, ticks)
    if plan == nil or character == nil or base == nil or base.id ~= plan.baseId then
        return "failed", "organize_base_changed"
    end
    if ticks - (plan.startedAt or ticks) > STEP_TIMEOUT_TICKS * 2 then
        return "failed", "organize_timeout"
    end
    local inventory = character:getInventory()
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    local busy = not character:getCharacterActions():isEmpty()
        or queue.current ~= nil
        or (type(queue.queue) == "table" and #queue.queue > 0)
    local actionPending = plan.action ~= nil and queue:indexOf(plan.action) ~= -1
    if plan.phase == "borrow_move" or plan.phase == "deposit_move" then
        local result = tostring(bridge:tickNpc(id))
        if result == "Succeeded" then
            plan.phase = plan.phase == "borrow_move" and "prepare" or "deposit"
        elseif result:find("Failed", 1, true) or ticks - (plan.moveStarted or ticks) > STEP_TIMEOUT_TICKS then
            return "failed", "organize_route:" .. result
        end
        return "working"
    end
    if plan.phase == "prepare" then
        if busy then return "working" end
        if not plan.source:contains(plan.item) then return "failed", "organize_item_taken" end
        local readable, destination, refusal = pcall(depositDestination, base, plan)
        if not readable then return "failed", "organize_destination_unreadable" end
        if destination == nil then return "failed", refusal end
        if not KnoxBaseStorage.canReceiveItem(destination.container, character, plan.item) then
            return "failed", "organize_destination_unavailable"
        end
        local square = sourceSquare(base, plan)
        if square == nil then return "failed", "organize_source_unloaded" end
        if not withinReach(character, square) then
            return moveTo(plan, square, character, bridge, id, ticks, "borrow_move")
        end
        local intendedContainer = destination.container
        local function allowed(_, candidate)
            if plan.cancelled or candidate ~= plan.item then return false end
            local current = depositDestination(base, plan)
            return current ~= nil and current.container == intendedContainer
                and plan.source:contains(candidate)
                and KnoxBaseStorage.canReceiveItem(current.container, character, candidate)
        end
        -- Permission may change while native pickup is turning/waiting too.
        plan.guard = allowed
        local admitted, action, reason = pcall(KnoxInventoryActions.queueTransfer,
            character, plan.item, plan.source, inventory, nil, allowed)
        if not admitted then return "failed", "organize_transfer_queue_error" end
        if action == nil then return "failed", reason end
        plan.action, plan.phase, plan.actionStarted = action, "borrowing", ticks
        return "working"
    end
    if plan.phase == "borrowing" then
        if ticks - (plan.actionStarted or ticks) > STEP_TIMEOUT_TICKS then
            return "failed", "organize_transfer_timeout"
        end
        if busy or actionPending then return "working" end
        if not inventory:contains(plan.item) then return "failed", "organize_transfer_failed" end
        plan.phase, plan.action = "deposit", nil
    end
    if plan.phase == "deposit" then
        if busy then return "working" end
        if not inventory:contains(plan.item) then return "failed", "organize_item_missing" end
        -- Re-resolve and recheck the current filter after travel. A stale plan
        -- yields to the existing cleanup/retry owner with its actual carried item.
        local readable, store, refusal = pcall(depositDestination, base, plan)
        if not readable then return "failed", "organize_destination_unreadable" end
        if store == nil then return "failed", refusal end
        if not withinReach(character, store.square) then
            return moveTo(plan, store.square, character, bridge, id, ticks, "deposit_move")
        end
        plan.depositSource, plan.depositDestination = inventory, store.container
        local function allowed(_, candidate)
            if plan.cancelled or candidate ~= plan.item then return false end
            local current = depositDestination(base, plan)
            return current ~= nil and current.container == plan.depositDestination
                and inventory:contains(candidate)
                and KnoxBaseStorage.canReceiveItem(current.container, character, candidate)
        end
        plan.guard = allowed
        local admitted, action, reason = pcall(KnoxInventoryActions.queueTransfer,
            character, plan.item, inventory, store.container, nil, allowed)
        if not admitted then return "failed", "organize_transfer_queue_error" end
        if action == nil then return "failed", reason end
        plan.action, plan.phase, plan.actionStarted = action, "depositing", ticks
        return "working"
    end
    if plan.phase == "depositing" then
        if ticks - (plan.actionStarted or ticks) > STEP_TIMEOUT_TICKS then
            return "failed", "organize_transfer_timeout"
        end
        if busy or actionPending then return "working" end
        Organize.cancelAction(character, plan)
        local readable, received = pcall(function()
            return plan.depositSource ~= nil and plan.depositDestination ~= nil
                and not plan.depositSource:contains(plan.item)
                and plan.depositDestination:contains(plan.item)
        end)
        if not readable then return "failed", "organize_receipt_unreadable" end
        if not received then return "failed", "organize_transfer_failed" end
        return "done", "organize_completed"
    end
    return "failed", "unknown_organize_phase"
end

return Organize
