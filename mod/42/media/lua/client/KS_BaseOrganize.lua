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
local function bestPolicyFor(base, character, item, excludeKey)
    if base == nil or character == nil or item == nil then return nil end
    local origin = call(character, "getCurrentSquare", nil)
    if origin == nil then return nil end
    local best, bestRank, bestExact, bestDistance = nil, nil, nil, nil
    for _, policy in ipairs(KnoxBaseStorage.operationalPolicies(base)) do
        -- An automatically discovered container is only a deposit fallback.
        -- Organizing should move misplaced items toward an explicit filter,
        -- never shuffle them between otherwise-unfiltered chests.
        if policy.key ~= excludeKey and policy.transientContainer ~= true
            and KnoxBaseStorage.acceptsDeposit(policy, item) then
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
function Organize.find(base, character, available, reserved)
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
                            local best = bestPolicyFor(base, character, item, policy.key)
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

function Organize.cancelAction(character, plan)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    if plan ~= nil and plan.action ~= nil and queue:indexOf(plan.action) ~= -1 then
        if queue.current == plan.action then ISTimedActionQueue.clear(character)
        else plan.action:forceCancel(); queue:removeFromQueue(plan.action) end
    end
    if plan ~= nil then plan.action = nil end
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
        if busy then return "failed", "organize_action_busy" end
        if not plan.source:contains(plan.item) then return "failed", "organize_item_taken" end
        local square = sourceSquare(base, plan)
        if square == nil then return "failed", "organize_source_unloaded" end
        local here = character:getCurrentSquare()
        if here == nil or here ~= square then
            return moveTo(plan, square, character, bridge, id, ticks, "borrow_move")
        end
        local action, reason = KnoxInventoryActions.queueTransfer(
            character, plan.item, plan.source, inventory, nil)
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
        if busy then return "failed", "organize_action_busy" end
        if not inventory:contains(plan.item) then return "failed", "organize_item_missing" end
        -- Re-resolve the destination at drop time: shelves fill, unload, or
        -- get reassigned while walking. A stale plan re-plans, never forces.
        local store = nil
        if KnoxBaseStorage.operationalPolicies ~= nil then
            for _, policy in ipairs(KnoxBaseStorage.operationalPolicies(base)) do
                if policy.key == plan.destinationPolicy.key then
                    local resolved = KnoxBaseStorage.resolvePolicy(policy)
                    if resolved ~= nil then store = resolved end
                    break
                end
            end
        end
        if store == nil then return "failed", "organize_destination_gone" end
        local origin = character:getCurrentSquare()
        local near = origin ~= nil and origin:getZ() == store.square:getZ()
            and (origin:getX() - store.square:getX()) ^ 2
                + (origin:getY() - store.square:getY()) ^ 2 <= 2
            and (origin == store.square or (origin.isSomethingTo ~= nil
                and not origin:isSomethingTo(store.square)))
        if not near then
            return moveTo(plan, store.square, character, bridge, id, ticks, "deposit_move")
        end
        local action, reason = KnoxInventoryActions.queueTransfer(
            character, plan.item, inventory, store.container, nil)
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
        if inventory:contains(plan.item) then
            -- Still carried (destination filled mid-walk): not lost, just
            -- pocketed for the next cleanup pass.
            return "done", "organize_shelf_full"
        end
        return "done", "organize_completed"
    end
    return "failed", "unknown_organize_phase"
end

return Organize
