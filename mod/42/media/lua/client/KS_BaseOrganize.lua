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
-- A full shelf used to exhaust one shared inspection budget, so the misfiled
-- item behind it was never examined: the "re-files automatically" behaviour
-- existed on paper only for any real base. Cheap passes (is this item in a
-- shelf that rejects it?) now get a much larger bound, while the expensive
-- "is there a better tier for an accepted item?" comparison keeps a small one.
local MAX_SCANNED_ITEMS = 400
local MAX_DEMOTED_CHECKS = 12
local STEP_TIMEOUT_TICKS = 1800

local function call(value, name, fallback, ...)
    if value == nil then return fallback end
    local method = value[name]
    if method == nil then return fallback end
    local ok, result = pcall(method, value, ...)
    if ok and result ~= nil then return result end
    return fallback
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
    local scanned, demotedChecks = 0, 0
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
                        if scanned >= MAX_SCANNED_ITEMS then return nil, "shelves_settled" end
                        scanned = scanned + 1
                        local item = items:get(i)
                        local identity = itemIdentity(item)
                        local favorite = call(item, "isFavorite", false) == true
                        if item ~= nil and identity ~= nil and not favorite
                            and (available == nil or available(item))
                            and (reserved == nil or not reserved(item)) then
                            local misplaced = policy.transientContainer == true
                                or not KnoxBaseStorage.acceptsDeposit(policy, item)
                            -- A shelf that already accepts the item is only
                            -- interesting when a higher tier exists, which costs
                            -- a comparison per policy. A misfiled item is the
                            -- recovery case and is always worth the check, so
                            -- accepted items spend the small budget instead of
                            -- hiding everything behind them.
                            if misplaced then
                                local best = bestPolicyFor(base, character, item,
                                    policy.key, destinationReserved)
                                -- The yard takes any item and is preferred for
                                -- bulky loads; an ordinary item still tries a
                                -- shelf that wants it before the floor.
                                local bulk = KnoxBaseStorage.depotBulkRank ~= nil
                                    and KnoxBaseStorage.depotBulkRank(item) or 2
                                local store = nil
                                if KnoxBaseStorage.depotStore ~= nil
                                    and (best == nil or bulk == 1) then
                                    store = KnoxBaseStorage.depotStore(base, item)
                                end
                                if store ~= nil then
                                    return {
                                        item = item, itemKey = identity,
                                        source = container, sourcePolicy = policy,
                                        depotZoneId = store.zone.id,
                                        baseId = base.id, phase = "prepare",
                                    }, "found"
                                end
                                if best ~= nil then
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
                            elseif demotedChecks < MAX_DEMOTED_CHECKS then
                                demotedChecks = demotedChecks + 1
                                local best = bestPolicyFor(base, character, item,
                                    policy.key, destinationReserved)
                                if best ~= nil then
                                    local srcRank = KnoxBaseStorage.priorityRank ~= nil
                                        and KnoxBaseStorage.priorityRank(policy) or 2
                                    local dstRank = KnoxBaseStorage.priorityRank ~= nil
                                        and KnoxBaseStorage.priorityRank(best) or 2
                                    -- Meaningfully better only: a strictly
                                    -- higher priority tier, or a misplaced item
                                    -- moving to any shelf that accepts it.
                                    -- Equal-tier shuffles never qualify, so
                                    -- settled bases stay settled.
                                    if dstRank < srcRank then
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

-- One bounded loaded-floor sweep. The cursor belongs to the existing resident
-- controller; no county scan or second hauling queue is introduced.
function Organize.findFloor(base, character, cursor, available, reserved, destinationReserved)
    local stats={squares=0,items=0,destinations=0}
    local area=base and (base.territory or base.home)
    local origin=call(character,"getCurrentSquare",nil)
    local cell=getCell and getCell()
    if not area or not origin or not cell then return nil,cursor,stats end
    local x1,y1=tonumber(area.minX),tonumber(area.minY)
    local x2=tonumber(area.maxX) or (x1 and x1+(tonumber(area.width) or 1)-1)
    local y2=tonumber(area.maxY) or (y1 and y1+(tonumber(area.height) or 1)-1)
    if not x1 or not y1 or not x2 or not y2 then return nil,cursor,stats end
    local width,height=x2-x1+1,y2-y1+1
    local count=width*height
    if width<1 or height<1 or count>4096 then return nil,cursor,stats end
    local start=math.floor(tonumber(cursor) or 0)%count
    local best,bestRank,bestDistance
    for offset=0,math.min(64,count)-1 do
        local index=(start+offset)%count
        local x,y=x1+math.floor(index/height),y1+index%height
        local square=cell:getGridSquare(x,y,origin:getZ())
        stats.squares=stats.squares+1
        local room=call(square,"getRoomDef",nil)
        local depot=KnoxBaseStorage.depotZoneAt(base,x,y,origin:getZ())
        if square and not depot and call(room,"getName","")~="bathroom" then
            local items,known=KnoxBaseStorage.collectSquareLooseItems(square)
            if known then for _,item in ipairs(items) do
                if stats.items>=400 or stats.destinations>=12 then break end
                stats.items=stats.items+1
                local world=call(item,"getWorldItem",nil)
                if world and call(world,"getSquare",nil)==square and call(world,"getItem",nil)==item
                    and itemIdentity(item) and call(item,"isFavorite",true)==false
                    and (not available or available(item)) and (not reserved or not reserved(item))
                    and KnoxBaseStorage.canReceiveItem(character:getInventory(),character,item) then
                    stats.destinations=stats.destinations+1
                    local storage=KnoxBaseStorage.findDepositTrip(base,character,item)
                    if storage and destinationReserved and destinationReserved(storage.policy) then storage=nil end
                    local rank=KnoxBaseStorage.depotBulkRank(item)
                    local store=(rank==1 or not storage) and KnoxBaseStorage.depotStore(base,item) or nil
                    if storage or store then
                        local distance=(x-origin:getX())^2+(y-origin:getY())^2
                        if not best or rank<bestRank or (rank==bestRank and distance<bestDistance) then
                            best={item=item,itemKey=itemIdentity(item),worldObject=world,worldSquare=square,
                                baseId=base.id,phase="prepare",floorHaul=true,
                                destinationPolicy=not store and storage.policy or nil,
                                depotZoneId=store and store.zone.id or nil}
                            bestRank,bestDistance=rank,distance
                        end
                    end
                end
            end end
        end
        if stats.items>=400 or stats.destinations>=12 then break end
    end
    return best,(start+stats.squares)%count,stats
end

function Organize.floorItemPresent(plan)
    local ok,present=pcall(function()
        return plan.worldObject:getSquare()==plan.worldSquare
            and plan.worldObject:getItem()==plan.item and plan.item:getWorldItem()==plan.worldObject
            and plan.worldSquare:getWorldObjects():contains(plan.worldObject)
    end)
    return ok and present==true
end

local function permitted(plan)
    if plan.cancelled then return false end
    if plan.permission==nil then return true end
    local ok,allowed=pcall(plan.permission)
    return ok and allowed==true
end

local function moveTo(plan, square, character, bridge, id, ticks, phase, exact)
    local approach = exact and square or AdjacentFreeTileFinder.Find(square, character)
    if approach == nil then return "failed", "organize_storage_unreachable" end
    local result = tostring(bridge:moveNpc(id, approach))
    if result:find("MOVE_STARTED", 1, true) ~= 1 then
        return "failed", "organize_route:" .. result
    end
    plan.phase, plan.moveStarted = phase, ticks
    return "working"
end

local function sourceSquare(base, plan)
    if plan.floorHaul then return plan.worldSquare end
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
if plan.depotZoneId ~= nil then
    local zone = nil
    for _, candidate in pairs(base.zones or {}) do
        if candidate ~= nil and candidate.id == plan.depotZoneId then
            zone = candidate
            break
        end
    end
    if zone == nil then return nil, "depot_area_gone" end
    local store, refusal = KnoxBaseStorage.depotStore(base, plan.item, zone)
    if store == nil then return nil, refusal or "depot_unavailable" end
    return { container = store.container, square = store.square, zone = store.zone }
end
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
    if not permitted(plan) then return "failed","organize_permission_revoked" end
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
        if (plan.floorHaul and not Organize.floorItemPresent(plan))
            or (not plan.floorHaul and not plan.source:contains(plan.item)) then
            return "failed", "organize_item_taken"
        end
        local readable, destination, refusal = pcall(depositDestination, base, plan)
        if not readable then return "failed", "organize_destination_unreadable" end
        if destination == nil then return "failed", refusal end
        if plan.depotZoneId == nil
            and not KnoxBaseStorage.canReceiveItem(destination.container, character, plan.item) then
            return "failed", "organize_destination_unavailable"
        end
        local square = sourceSquare(base, plan)
        if square == nil then return "failed", "organize_source_unloaded" end
        if not withinReach(character, square) then
            return moveTo(plan, square, character, bridge, id, ticks, "borrow_move")
        end
        local intendedContainer = destination.container
        local function allowed(_, candidate)
            if not permitted(plan) or candidate ~= plan.item then return false end
            local current = depositDestination(base, plan)
            return current ~= nil and current.container == intendedContainer
                and withinReach(character,square)
                and ((plan.floorHaul and Organize.floorItemPresent(plan))
                    or (not plan.floorHaul and plan.source:contains(candidate)))
                and (plan.depotZoneId ~= nil
                    or KnoxBaseStorage.canReceiveItem(current.container, character, candidate))
        end
        -- Permission may change while native pickup is turning/waiting too.
        plan.guard = allowed
        local admitted, action, reason
        if plan.floorHaul then
            local grabGuard=function(_,_,candidate) return allowed(nil,candidate) end
            plan.guard=grabGuard
            admitted,action,reason=pcall(KnoxInventoryActions.queueGrab,character,plan.worldObject,
                grabGuard)
        else
            admitted,action,reason=pcall(KnoxInventoryActions.queueTransfer,
                character,plan.item,plan.source,inventory,nil,allowed)
        end
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
        if plan.floorHaul then
            local ok,received=pcall(function()
                return plan.item:getWorldItem()==nil and plan.worldObject:getSquare()==nil
                    and not plan.worldSquare:getWorldObjects():contains(plan.worldObject)
            end)
            if not ok or not received then return "failed","organize_pickup_receipt_failed" end
        elseif plan.source:contains(plan.item) then return "failed","organize_pickup_receipt_failed" end
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
        if (plan.depotZoneId and character:getCurrentSquare()~=store.square)
            or not withinReach(character, store.square) then
            return moveTo(plan,store.square,character,bridge,id,ticks,"deposit_move",plan.depotZoneId~=nil)
        end
        plan.depositSource, plan.depositDestination = inventory, store.container
        plan.depositSquare=store.square
        local function allowed(action, candidate)
            if not permitted(plan) or candidate ~= plan.item then return false end
            if plan.depotZoneId then
                return inventory:contains(candidate) and character:getCurrentSquare()==plan.depositSquare
                    and KnoxBaseStorage.depotDropAllowed(base,candidate,plan.depositSquare,plan.depotZoneId)
                    and character:getVehicle()==nil
                    and action:getNotFullFloorSquare(candidate)==plan.depositSquare
            end
            local current = depositDestination(base, plan)
            return current ~= nil and current.container == plan.depositDestination
                and withinReach(character,current.square) and inventory:contains(candidate)
                and KnoxBaseStorage.canReceiveItem(current.container, character, candidate)
        end
        plan.guard = allowed
        local admitted, action, reason
        if plan.depotZoneId then
            admitted,action,reason=pcall(KnoxInventoryActions.queueDrop,character,plan.item,allowed)
        else
            admitted,action,reason=pcall(KnoxInventoryActions.queueTransfer,
                character,plan.item,inventory,store.container,nil,allowed)
        end
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
            if plan.depositSource==nil or plan.depositSource:contains(plan.item) then return false end
            if plan.depotZoneId then
                local world=plan.item:getWorldItem()
                local square=world and world:getSquare()
                local zone=square and KnoxBaseStorage.depotZoneAt(base,square:getX(),square:getY(),square:getZ())
                return square==plan.depositSquare and zone~=nil and zone.id==plan.depotZoneId
                    and world:getItem()==plan.item and square:getWorldObjects():contains(world)
            end
            return plan.depositDestination~=nil and plan.depositDestination:contains(plan.item)
        end)
        if not readable then return "failed", "organize_receipt_unreadable" end
        if not received then return "failed", "organize_transfer_failed" end
        return "done", "organize_completed"
    end
    return "failed", "unknown_organize_phase"
end

return Organize
