local Runtime = rawget(_G, "KnoxSurvivorRuntime") or {}
_G.KnoxSurvivorRuntime = Runtime

local entries = {}

local ACTIVITY_BY_STATE = {
    COMBAT = "fighting",
    FLEEING = "retreating",
    BASE_AMBIENT_REST = "resting",
    BASE_RECREATION = "reading",
    BASE_HYGIENE = "washing",
    BASE_ORGANIZE = "organizing",
    BASE_SECURITY_WAIT = "waiting_for_route", COMPANION_DUTY_WAIT = "waiting_for_route",
    BASE_TASK_MOVE = "working_at_base",
    BASE_TASK_WORK = "working_at_base",
    BASE_TASK_ACTION = "working_at_base",
    BASE_TASK_PATROL_WAIT = "patrolling",
    BASE_TASK_SUPPLY_MOVE = "collecting_job_supplies",
    BASE_TASK_SUPPLY_TRANSFER = "collecting_job_supplies",
    BASE_TASK_SUPPLY_WAIT = "waiting_for_materials",
    COMPANION_GUARD = "guarding",
    COMPANION_RELAX = "resting",
    COMPANION_PATROL_WAIT = "patrolling",
    MOVING_TO_COMPANION_PATROL = "patrolling",
    MOVING_TO_COMPANION_POINT = "travelling",
    INVENTORY_CLEANUP = "sorting_inventory",
    MOVING_TO_DEPOSIT = "storing_supplies",
    AWAY_RETURN = "returning_home",
    LOOTING = "looting",
    SEARCHING = "searching",
    MOVING_TO_SUPPLY = "seeking_supplies",
    MOVING_TO_EXPLORE = "exploring",
    ROAMING = "exploring",
    MOVING_TO_REST = "resting",
    WAITING_TO_RECOVER = "resting",
    SLEEPING_RECOVERY = "resting",
    TIMED_ACTION = "busy",
    GROUP_FOLLOW = "travelling",
    GROUP_WAIT = "travelling",
    GROUP_REGROUP = "travelling",
    COMPANION_FOLLOW = "following",
    COMPANION_WAIT = "following",
    COMPANION_HOLD = "holding",
    BASE_RETURN = "returning_home",
    EVENT_TRAVEL = "travelling",
    EVENT_WAIT = "waiting",
    BASE_PATROL = "walking_at_base",
    BASE_IDLE = "at_base",
    CAMP_RETURN = "returning_to_shelter",
    CAMP_REPOSITION = "at_shelter",
    CAMP_IDLE = "at_shelter",
    CAMP_AMBIENT_REST = "resting",
    MOVING_TO_BASE_CANDIDATE = "scouting_base",
    MEETING_APPROACH = "meeting",
    MEETING_WAIT = "meeting",
    MEETING_READY = "meeting",
    GREETING = "meeting",
    ROBBING = "fighting",
    STORED = "away",
    STOPPED = "stopped",
    IDLE = "idle",
    TRADING = "trading",
    PLAYER_CONVERSATION = "meeting",
}

local TASK_ACTIVITY = {
    barricade = "barricading",
    haul_corpse = "hauling_corpse",
    farm_seed = "farming", farm_water = "farming", farm_harvest = "farming",
    chop_tree = "woodcutting", saw_logs = "sawing_logs", cook = "cooking",
    repair = "repairing", guard = "guarding", patrol = "patrolling",
}

local DECISION_ACTIVITY = {
    regroup_last_contact = "regroup_last_contact",
    awaiting_player_contact = "awaiting_player_contact", regroup_route_blocked = "regroup_route_blocked",
    eat = "eating", drink = "drinking", rest = "resting", sleep = "sleeping",
    bandage = "treating_wounds", improvise_medical = "preparing_bandages",
    waiting_for_food = "waiting_for_food", waiting_for_water = "waiting_for_water",
    waiting_for_medical = "waiting_for_medical",
}

local function validId(id)
    return type(id) == "string" and id ~= ""
end

local function baseSupplyActivity(controller, state)
    if controller == nil or controller.baseId == nil then return nil end
    local deposit = controller.pendingBaseSupplyDeposit
    local hasCargo = deposit ~= nil and deposit.item ~= nil
    if state == "BASE_IDLE" and hasCargo
        and controller.activeDecision == "base_supply_delivery_wait" then
        return "waiting_to_store_base_supplies"
    end
    if state == "INVENTORY_CLEANUP" and controller.pendingCleanup ~= nil
        and controller.pendingCleanup.baseSupply == true then
        return "storing_base_supplies"
    end
    if state == "MOVING_TO_DEPOSIT" and hasCargo then
        return "taking_base_supplies_to_storage"
    end
    local party = controller.baseSupplyParty == true
    local returning = controller.baseSupplyPartyReturning == true
        or party and controller.scavengeSortieReturning == true
    if returning and (state == "BASE_RETURN" or state == "GROUP_FOLLOW"
        or state == "GROUP_WAIT" or state == "GROUP_REGROUP"
        or state == "BASE_IDLE" or state == "IDLE") then
        return hasCargo and "returning_with_base_supplies" or "returning_from_supply_run"
    end
    if not party then return nil end
    local pending = controller.pendingSupply
    local partyPickup = pending ~= nil and pending.baseSupplyPartyBaseId == controller.baseId
    if partyPickup and (state == "MOVING_TO_SUPPLY" or state == "SEARCHING") then
        return "seeking_base_supplies"
    end
    if partyPickup and state == "LOOTING" then return "collecting_base_supplies" end
    if state == "MOVING_TO_EXPLORE" or state == "ROAMING"
        or state == "GROUP_FOLLOW" or state == "GROUP_WAIT" or state == "GROUP_REGROUP"
        or state == "IDLE" or state == "BASE_IDLE" then return "on_supply_run" end
    return nil
end

function Runtime.register(id, controller)
    if not validId(id) or type(controller) ~= "table" then
        return false
    end
    local old = entries[id]
    if old ~= nil and old.controller ~= controller then
        -- Re-registration (respawn/restore/test reset) must not leak the old
        -- controller: shut it down before replacing so no duplicate shells run.
        pcall(function()
            if old.controller ~= nil and old.controller.shutdown ~= nil then
                old.controller:shutdown()
            end
        end)
    end
    entries[id] = {
        id = id,
        controller = controller,
        character = controller.character,
        lifecycleState = "active",
    }
    return true
end

local function getEntry(id)
    return validId(id) and entries[id] or nil
end

-- OnSave can run after a native transfer receives an item but before its
-- controller observes completion. Reconcile only that exact receipt before
-- inventory serialization; do not interrupt actions or release reservations.
function Runtime.prepareInventoryCapture(id, character)
    local entry = getEntry(id)
    local controller = entry ~= nil and entry.controller or nil
    if controller == nil or controller.recordSettlementLootReceipt == nil then
        return true, "no_pending_receipt_owner"
    end
    if controller.character ~= character then
        return false, "receipt_character_mismatch"
    end
    local ok, received = pcall(controller.recordSettlementLootReceipt, controller)
    if not ok or type(received) ~= "number" then
        return false, "receipt_reconcile_failed=" .. tostring(received)
    end
    if controller.recordBaseSupplyDepositReceipt ~= nil then
        local depositOk, deposited, detail = pcall(controller.recordBaseSupplyDepositReceipt, controller)
        if not depositOk or type(deposited) ~= "boolean" or detail == "receipt_unreadable" then
            return false, "deposit_receipt_reconcile_failed=" .. tostring(detail or deposited)
        end
    end
    return true, "receipts=" .. tostring(received)
end

function Runtime.setLifecycleState(id, state)
    local entry = getEntry(id)
    if entry == nil or type(state) ~= "string" or state == "" then return false end
    entry.lifecycleState = state
    return true
end

function Runtime.getLifecycleState(id)
    local entry = getEntry(id)
    return entry ~= nil and (entry.lifecycleState or "active") or nil
end

function Runtime.canAcceptOrders(id)
    local state = Runtime.getLifecycleState(id)
    if state == "detached_transient" or state == "detached_grace"
        or state == "detached_stale" or state == "hibernating"
        or state == "hibernate_recovery_pending" then
        return false, "companion_detached"
    end
    return true
end

-- Visible native bodies can still belong to an incomplete hibernation
-- transaction. Interaction uses the same lifecycle admission as commands.
function Runtime.canInteract(id)
    local accepted = Runtime.canAcceptOrders(id)
    if not accepted then return false, "survivor_unavailable" end
    return true
end

function Runtime.unregister(id, controller)
    local entry = validId(id) and entries[id] or nil
    if entry ~= nil and (controller == nil or entry.controller == controller) then
        local vehicles = rawget(_G, "KnoxCompanionVehicles")
        if vehicles ~= nil and vehicles.cancel ~= nil then vehicles.cancel(entry.character) end
        entries[id] = nil
        return true
    end
    return false
end

-- Read-only identity lookup for UI attention/availability. The registered
-- controller remains the sole action owner; never synthesize a second one.
function Runtime.getController(id)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller or nil
end

function Runtime.getCharacter(id)
    local entry = getEntry(id)
    if entry == nil then
        return nil
    end
    -- Validate against the live bridge so stale destroyed shells are not
    -- returned as live survivors after removeNpc/retire.
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil and bridge.getNpcCharacter ~= nil then
        local ok, live = pcall(bridge.getNpcCharacter, bridge, id)
        if ok then
            if live == nil then return nil end
            entry.character = live
            if entry.controller ~= nil then entry.controller.character = live end
            return live
        end
    end
    local controller = entry.controller
    local character = controller ~= nil and controller.character or entry.character
    entry.character = character
    return character
end

function Runtime.activeIds()
    local ids = {}
    for id in pairs(entries) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

function Runtime.idForCharacter(character)
    if character == nil then
        return nil
    end
    for id in pairs(entries) do
        if Runtime.getCharacter(id) == character then
            return id
        end
    end
    return nil
end

function Runtime.snapshot(id)
    local entry = getEntry(id)
    if entry == nil then
        return {
            id = id,
            loaded = false,
            activity = "away",
        }
    end
    local controller = entry.controller
    local character = Runtime.getCharacter(id)
    local square = character ~= nil and character:getCurrentSquare() or nil
    local state = controller ~= nil and tostring(controller.state or "IDLE") or "IDLE"
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    local vehicleActivity = character ~= nil and vehicles ~= nil and vehicles.activity ~= nil
        and vehicles.activity(character) or nil
    local task = controller ~= nil and controller.baseTask or nil
    local dutyActivity
    if task ~= nil and (state == "BASE_TASK_MOVE" or state == "BASE_TASK_WORK"
        or state == "BASE_TASK_ACTION" or state == "BASE_TASK_PATROL_WAIT") then
        dutyActivity = TASK_ACTIVITY[tostring(task.type or "")]
    end
    local decision = controller ~= nil and controller.activeDecision or nil
    local reloading = state == "COMBAT" and tonumber(controller ~= nil and controller.reloadYieldStreak) ~= nil
        and tonumber(controller.reloadYieldStreak) > 0
    -- A decision is a meaningful live activity only while its controller state
    -- owns that action.  An interrupted eat/rest decision must not hide a
    -- higher-priority flee/combat/pathing state that has already taken over.
    local decisionActivity = ((state == "COMPANION_FOLLOW" and decision == "regroup_last_contact")
        or state == "TIMED_ACTION" or state == "SLEEPING_RECOVERY"
        or state == "WAITING_TO_RECOVER"
        or (state == "COMPANION_WAIT" and (decision == "awaiting_player_contact" or decision == "regroup_route_blocked"))
        or (state == "BASE_IDLE" and (decision == "waiting_for_food"
            or decision == "waiting_for_water" or decision == "waiting_for_medical")))
        and DECISION_ACTIVITY[tostring(decision or "")] or nil
    return {
        id = id,
        loaded = square ~= nil,
        state = state,
        activity = vehicleActivity or (reloading and "reloading") or dutyActivity or decisionActivity
            or baseSupplyActivity(controller, state)
            or ((state == "BASE_RECREATION" or state == "BASE_COOKING") and decision)
            or ACTIVITY_BY_STATE[state] or "busy",
        decision = decision,
        driving = character ~= nil and vehicles ~= nil and vehicles.driverStatus ~= nil
            and vehicles.driverStatus(character) or nil,
        x = square ~= nil and square:getX() or nil,
        y = square ~= nil and square:getY() or nil,
        z = square ~= nil and square:getZ() or nil,
    }
end

function Runtime.notifyDutyChanged(id)
    local entry = getEntry(id)
    if entry == nil then return false end
    if entry.controller ~= nil and entry.controller.onDutyChanged ~= nil then
        entry.controller:onDutyChanged()
    end
    return true
end

function Runtime.prepareVehicle(id)
    local entry = getEntry(id)
    if entry == nil or entry.controller == nil then return false end
    local character = Runtime.getCharacter(id)
    local queue = ISTimedActionQueue.queues[character]
    if queue ~= nil and #queue.queue > 0 then return false end
    return entry.controller:interruptForDirective() == true
end

-- Transient action lease only. Identity, orders and inventory stay in their
-- existing owners; a replacement/detached controller cannot inherit this lease.
function Runtime.beginPlayerConversation(id, player)
    local accepted, reason = Runtime.canInteract(id)
    if not accepted then return false, reason end
    local entry = getEntry(id)
    if entry == nil or entry.controller.beginPlayerConversation == nil then
        return false, "survivor_unavailable"
    end
    return entry.controller:beginPlayerConversation(player)
end

function Runtime.endPlayerConversation(id, player)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:endPlayerConversation(player) or false
end

-- The partner's existing controller owns admission and its transient cooldown.
-- Never address an old body during a lifecycle/identity handoff.
function Runtime.acceptAmbientSocial(id, speaker, baseId, ticks)
    if not Runtime.canInteract(id) then return false end
    local entry = getEntry(id)
    local controller = entry ~= nil and entry.controller or nil
    if controller == nil or controller.acceptAmbientSocial == nil
        or Runtime.getCharacter(id) ~= controller.character then return false end
    return controller:acceptAmbientSocial(speaker, baseId, ticks) == true
end

function Runtime.beginTrade(id, action)
    local accepted, reason = Runtime.canInteract(id)
    if not accepted then return false, reason end
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:beginTrade(action) or false
end

function Runtime.ownsTrade(id, action)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller.tradeAction == action
        and entry.controller.state == "TRADING" and Runtime.getCharacter(id) == action.npc
end

function Runtime.releaseTrade(id, action)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:releaseTrade(action) or false
end

function Runtime.beginRobbery(id, victim, ticks)
    local entry = getEntry(id)
    if entry == nil or entry.controller == nil
        or entry.controller.beginRobbery == nil then
        return false
    end
    return entry.controller:beginRobbery(victim, ticks or 0) == true
end

function Runtime.nearestToSquare(square, maximumDistance)
    if square == nil then
        return nil, nil
    end
    local limit = math.max(0, tonumber(maximumDistance) or 3)
    local bestId = nil
    local bestDistance = limit * limit
    for id in pairs(entries) do
        local character = Runtime.getCharacter(id)
        local current = character ~= nil and character:getCurrentSquare() or nil
        if current ~= nil and current:getZ() == square:getZ() then
            local dx = current:getX() - square:getX()
            local dy = current:getY() - square:getY()
            local distance = dx * dx + dy * dy
            if distance <= bestDistance then
                bestId = id
                bestDistance = distance
            end
        end
    end
    return bestId, bestId ~= nil and math.sqrt(bestDistance) or nil
end

function Runtime.clear()
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if vehicles ~= nil and vehicles.cancel ~= nil then
        for _, entry in pairs(entries) do vehicles.cancel(entry.character) end
    end
    entries = {}
end

return Runtime
