require "KS_Persistence"
require "KS_EventFactions"
pcall(function() require "KS_DebugLog" end)

-- Faction-vs-faction raid telemetry: proposals are frequent background
-- evaluations, so only verdicts log (throttled), never the scan itself.
local function diagRaid(event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("faction", "raid", event, details) end)
    end
end

local KnoxEvents = rawget(_G, "KnoxEvents") or {}
_G.KnoxEvents = KnoxEvents

-- Durable event bookkeeping only. The runtime dispatcher will own travel and
-- objectives through existing NPC controllers; this service never spawns gear,
-- allocates survivors, simulates raid victories, or overwrites a survivor duty.
local NEXT = {
    scheduled = { spawning = true, failed = true },
    spawning = { approaching = true, withdrawing = true, failed = true },
    approaching = { active = true, withdrawing = true, failed = true },
    active = { objective = true, withdrawing = true, failed = true },
    objective = { withdrawing = true, failed = true },
    withdrawing = { completed = true, failed = true },
    completed = {}, failed = {},
}
local RAID_COOLDOWN_HOURS = 24
local RETAIN_HOURS = 168
local HISTORY_LIMIT = 128
local AUTOMATIC_RETRY_HOURS = 6
local AUTOMATIC_MAX_DISTANCE = 600
local MAX_SERIAL = 9007199254740990 -- leave room for an exact integer increment

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function serial(value)
    return finite(value) and value >= 1 and value <= MAX_SERIAL and value % 1 == 0
end

local function memberList(value)
    if type(value) ~= "table" or #value == 0 then return false end
    local count, seen = 0, {}
    for index, id in pairs(value) do
        if not serial(index) or index > #value or type(id) ~= "string" or id == "" or seen[id] then
            return false
        end
        count, seen[id] = count + 1, true
    end
    return count == #value
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function terminal(event)
    return event.phase == "completed" or event.phase == "failed"
end

local function records()
    return KnoxPersistence.getKnoxEventState().records
end

local function retainCooldown(event)
    if event.kind ~= "faction_raid" then return end
    if type(event.sourceFactionId) ~= "string" or not finite(event.lastChangedAtHours) then return end
    local cooldowns = KnoxPersistence.getKnoxEventState().cooldowns
    local untilHours = event.lastChangedAtHours + RAID_COOLDOWN_HOURS
    cooldowns[event.sourceFactionId] = math.max(untilHours,
        finite(cooldowns[event.sourceFactionId]) and cooldowns[event.sourceFactionId] or 0)
end

local function point(value)
    if type(value) ~= "table" then return false end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z) or 0
    return finite(x) and finite(y) and finite(z) and math.abs(x) <= 1000000
        and math.abs(y) <= 1000000 and z % 1 == 0 and z >= 0 and z <= 7
end

local function emptyList(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return false end
    return true
end

local function allocateEventId(state)
    local number = serial(state.nextId) and state.nextId or 1
    while state.records["knox-event-" .. string.format("%.0f", number)] ~= nil do
        number = number < MAX_SERIAL and number + 1 or 1
    end
    state.nextId = number < MAX_SERIAL and number + 1 or 1
    return "knox-event-" .. string.format("%.0f", number)
end

local function targetFaction(base)
    if base == nil then return nil end
    if base.ownerKind == "faction" then return KnoxPersistence.getFaction(base.ownerId) end
    if base.ownerKind == "player" then return KnoxPersistence.getPlayerFaction(base.ownerId) end
end

local function locationKey(base)
    local home = base ~= nil and base.home or nil
    if type(home) ~= "table" then return nil end
    for _, key in ipairs({ "minX", "minY", "width", "height" }) do
        if not finite(home[key]) then return nil end
    end
    if home.width <= 0 or home.height <= 0 or not finite(home.z or 0)
        or not finite(base.relocatedAtHours or 0) then return nil end
    return table.concat({ home.minX, home.minY, home.width, home.height,
        home.z or 0, base.relocatedAtHours or 0 }, ":")
end

local function raidOwners(factionId, baseId)
    local faction = KnoxPersistence.getFaction(factionId)
    local target = KnoxPersistence.getBase(baseId)
    local other = targetFaction(target)
    if faction == nil or faction.kind == "player" or other == nil or faction.id == other.id then
        return nil, "invalid_raid_owners"
    end
    if KnoxPersistence.getFactionDisposition(faction.id, other.id) ~= "hostile" then
        return nil, "not_hostile"
    end
    local home = KnoxPersistence.getBaseForOwner("faction", faction.id)
    if locationKey(home) == nil or locationKey(target) == nil then return nil, "missing_base" end
    return { faction = faction, home = home, target = target, targetFactionId = other.id }
end

local function livingRoster(faction)
    local result, seen = {}, {}
    for _, id in ipairs(faction.memberIds or {}) do
        if type(id) == "string" and not seen[id] and KnoxPersistence.isSurvivorAlive(id) then
            local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
            if affiliation ~= nil and affiliation.kind == "faction" and affiliation.factionId == faction.id then
                result[#result + 1], seen[id] = id, true
            end
        end
    end
    table.sort(result)
    return result
end

local function availableMember(id, home)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if duty == nil or duty.mode ~= "base" or duty.baseId ~= home.id
        or duty.eventId ~= nil
        or KnoxPersistence.getAwayTeamForSurvivor(id) ~= nil then return false end
    -- Do not silently steal a worker's in-progress task at the proposal boundary.
    for _, task in pairs(home.tasks or {}) do
        if type(task) == "table" and task.state == "claimed" and task.claimedBy == id then return false end
    end
    local snapshot = KnoxPersistence.getRecord(id)
    return type(snapshot) == "string" and snapshot ~= ""
end

function KnoxEvents.get(id)
    local event = type(id) == "string" and records()[id] or nil
    return type(event) == "table" and copy(event) or nil
end

function KnoxEvents.activeIds()
    local ids = {}
    for id, event in pairs(records()) do
        if type(id) == "string" and type(event) == "table" and not terminal(event) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxEvents.saveUnloadedTravel(id, revision, travel)
    local event = records()[id]
    if type(event) ~= "table" or terminal(event) or event.revision ~= revision
        or type(travel) ~= "table" then return false end
    event.unloadedTravel = copy(travel)
    return true
end

function KnoxEvents.beginRaidObjective(id, revision, hours)
    local event = records()[id]
    if type(event) ~= "table" or event.phase ~= "active" or event.revision ~= revision then
        return nil, "event_changed"
    end
    local changed, reason = KnoxEvents.transition(id, revision, "objective", hours, "searching_for_supplies")
    if changed == nil then return nil, reason end
    event.objective = { kind = "take_supplies", requiredItems = math.min(6, #event.memberIds * 2),
        startedAtHours = hours, deadlineHours = hours + 2, receipts = {}, misses = {} }
    return copy(event), "started"
end

function KnoxEvents.objectiveCount(event)
    local objective = type(event) == "table" and event.objective or nil
    local count = 0
    for _ in pairs(type(objective) == "table" and type(objective.receipts) == "table" and objective.receipts or {}) do
        count = count + 1
    end
    return count
end

local function validSupplyObjective(event, objective, kind)
    local valid = type(objective) == "table" and objective.kind == kind
        and type(objective.receipts) == "table" and type(objective.misses) == "table"
        and serial(objective.requiredItems) and objective.requiredItems <= 6
        and finite(objective.startedAtHours) and finite(objective.deadlineHours)
        and objective.deadlineHours > objective.startedAtHours
        and objective.deadlineHours <= objective.startedAtHours + 2
    if not valid or not memberList(event.memberIds) then return false end
    local members, count = {}, 0
    for _, id in ipairs(event.memberIds) do members[id] = true end
    for key, receipt in pairs(objective.receipts) do
        count = count + 1
        if count > objective.requiredItems or type(key) ~= "string" or key == ""
            or type(receipt) ~= "table" or receipt.itemId ~= key or not members[receipt.memberId]
            or type(receipt.fullType) ~= "string" or receipt.fullType == ""
            or not finite(receipt.x) or not finite(receipt.y) or not finite(receipt.z)
            or not finite(receipt.atHours) or receipt.atHours < objective.startedAtHours
            or receipt.atHours >= objective.deadlineHours then return false end
    end
    for id, misses in pairs(objective.misses) do
        if not members[id] or not finite(misses) or misses < 0 or misses > 3 or misses % 1 ~= 0 then return false end
    end
    return true
end

function KnoxEvents.isValidRaidObjective(event)
    return validSupplyObjective(event,
        type(event) == "table" and event.objective or nil, "take_supplies")
end

local function objectiveMember(id, memberId)
    local event = records()[id]
    local valid = type(event) == "table" and event.phase == "objective"
        and (event.kind == "faction_raid" and KnoxEvents.isValidRaidObjective(event)
            or event.kind == "faction_entry" and event.policyId == "scavengers"
                and KnoxEvents.isValidFactionEntryObjective(event))
    if not valid then return nil end
    if type(memberId) ~= "string" or not KnoxPersistence.isSurvivorAlive(memberId) then return nil end
    local duty = KnoxPersistence.getSurvivorDuty(memberId)
    if duty == nil or duty.eventId ~= id then return nil end
    for _, member in ipairs(event.memberIds or {}) do if member == memberId then return event end end
end

-- The native-action observer supplies evidence after a real container transfer.
-- These receipts describe that operation; they never create or restore an item.
function KnoxEvents.recordLoot(id, memberId, receipt, hours)
    local event = objectiveMember(id, memberId)
    if event == nil or type(receipt) ~= "table" or type(receipt.itemId) ~= "string"
        or receipt.itemId == "" or type(receipt.fullType) ~= "string" or receipt.fullType == ""
        or not finite(receipt.x) or not finite(receipt.y) or not finite(receipt.z)
        or not finite(hours) or hours < event.objective.startedAtHours
        or hours >= event.objective.deadlineHours then return false end
    if event.objective.receipts[receipt.itemId] ~= nil then return false end
    if KnoxEvents.objectiveCount(event) >= event.objective.requiredItems then return false end
    local value = { itemId = receipt.itemId, fullType = receipt.fullType,
        x = receipt.x, y = receipt.y, z = receipt.z, memberId = memberId, atHours = hours }
    event.objective.receipts[receipt.itemId] = value
    event.objective.misses[memberId] = 0
    return true
end

function KnoxEvents.recordEmptySearch(id, memberId)
    local event = objectiveMember(id, memberId)
    if event == nil then return false end
    event.objective.misses[memberId] = math.min(3, (tonumber(event.objective.misses[memberId]) or 0) + 1)
    return true
end

function KnoxEvents.finishRaidObjective(id, revision, hours, outcome)
    local event = records()[id]
    if type(event) ~= "table" or event.phase ~= "objective" or event.revision ~= revision
        or not KnoxEvents.isValidRaidObjective(event) then return nil, "event_changed" end
    if outcome ~= "supplies_taken" and outcome ~= "partial_supplies" and outcome ~= "no_supplies" then
        return nil, "invalid_outcome"
    end
    local count = KnoxEvents.objectiveCount(event)
    if (outcome == "supplies_taken" and count < event.objective.requiredItems)
        or (outcome == "partial_supplies" and count == 0) or (outcome == "no_supplies" and count > 0) then
        return nil, "missing_outcome_evidence"
    end
    local changed, reason = KnoxEvents.transition(id, revision, "withdrawing", hours, outcome)
    if changed == nil then return nil, reason end
    event.objective.outcome, event.objective.finishedAtHours = outcome, hours
    return copy(event), "finished"
end

function KnoxEvents.memberEvent(id)    for _, event in pairs(records()) do
        if type(event) == "table" and not terminal(event) then
            for _, member in pairs(type(event.memberIds) == "table" and event.memberIds or {}) do
                if member == id then return copy(event) end
            end
        end
    end
    return nil
end

-- Planning does not change duties or inventories. Eligibility must be checked
-- again by dispatch when live loadout/health and actual entrance space are known.
function KnoxEvents.proposeRaid(factionId, baseId, hours)
    if not finite(hours) or hours < 0 then return nil, "invalid_time" end
    local owners, reason = raidOwners(factionId, baseId)
    if owners == nil then
        diagRaid("proposal_rejected", {
            source = tostring(factionId), target = tostring(baseId),
            reason = tostring(reason),
        })
        return nil, reason
    end
    local cooldown = KnoxPersistence.getKnoxEventState().cooldowns[factionId]
    if finite(cooldown) and hours < cooldown then
        diagRaid("proposal_rejected", {
            source = tostring(factionId), target = tostring(baseId),
            reason = "faction_event_cooldown",
        })
        return nil, "faction_event_cooldown"
    end
    for _, event in pairs(records()) do
        if type(event) == "table" and event.sourceFactionId == factionId then
            if not terminal(event) then
                diagRaid("proposal_rejected", {
                    source = tostring(factionId), target = tostring(baseId),
                    reason = "faction_event_active",
                })
                return nil, "faction_event_active"
            end
            if finite(event.lastChangedAtHours) and hours < event.lastChangedAtHours + RAID_COOLDOWN_HOURS then
                diagRaid("proposal_rejected", {
                    source = tostring(factionId), target = tostring(baseId),
                    reason = "faction_event_cooldown",
                })
                return nil, "faction_event_cooldown"
            end
        end
    end
    local living, available = livingRoster(owners.faction), {}
    for _, id in ipairs(living) do
        if availableMember(id, owners.home) and KnoxEvents.memberEvent(id) == nil then
            available[#available + 1] = id
        end
    end
    -- Five established residents may send two, never all five. Two available
    -- residents stay home even if most of the faction is already away working.
    local count = math.min(math.floor(#living * 0.4), #available - 2)
    if count < 1 then
        diagRaid("proposal_rejected", {
            source = tostring(factionId), target = tostring(baseId),
            reason = "insufficient_home_strength",
            living = #living, available = #available,
        })
        return nil, "insufficient_home_strength"
    end
    local members = {}
    for index = 1, count do members[index] = available[index] end
    diagRaid("proposal_accepted", {
        source = tostring(factionId), target = tostring(baseId),
        raiders = #members, living = #living,
        targetFaction = tostring(owners.targetFactionId),
    })
    return { kind = "faction_raid", sourceFactionId = factionId, targetBaseId = baseId,
        sourceBaseId = owners.home.id, targetFactionId = owners.targetFactionId,
        sourceLocation = locationKey(owners.home), targetLocation = locationKey(owners.target),
        memberIds = members, livingAtProposal = #living, defendersAtProposal = #available - count }
end

function KnoxEvents.scheduleRaid(factionId, baseId, hours, delayHours)
    delayHours = delayHours == nil and 1 or delayHours
    if not finite(delayHours) or delayHours < 0 or delayHours > 168 then return nil, "invalid_delay" end
    local proposal, reason = KnoxEvents.proposeRaid(factionId, baseId, hours)
    if proposal == nil then return nil, reason end
    local state = KnoxPersistence.getKnoxEventState()
    proposal.id = allocateEventId(state)
    proposal.phase, proposal.revision = "scheduled", 1
    proposal.createdAtHours, proposal.lastChangedAtHours = hours, hours
    proposal.dueAtHours, proposal.deadlineHours = hours + delayHours, hours + delayHours + 24
    proposal.reason = "awaiting_dispatch"
    state.records[proposal.id] = proposal
    return copy(proposal), "scheduled"
end

-- Named arrivals are scheduled as bookkeeping first. No survivor, body, item,
-- faction relationship or hostility is created until the due event is claimed
-- by the runtime through the atomic persistence entry transaction.
function KnoxEvents.scheduleFactionEntry(policyId, objectiveKind, target, partySize, hours, delayHours)
    hours, delayHours = tonumber(hours), delayHours == nil and 1 or tonumber(delayHours)
    partySize = math.floor(tonumber(partySize) or 0)
    local policy = KnoxEventFactions ~= nil and KnoxEventFactions.get(policyId) or nil
    if policy ~= nil and policy.disabled == true then return nil, "event_faction_disabled" end
    if not finite(hours) or hours < 0 or not finite(delayHours) or delayHours < 0 or delayHours > 168
        or not point(target) or partySize < 2 or partySize > 6
        or not KnoxEventFactions.isWorldAgeEligible(policyId, hours)
        or not KnoxEventFactions.allowsObjective(policyId, objectiveKind) then
        return nil, "invalid_faction_entry"
    end
    local state = KnoxPersistence.getKnoxEventState()
    local id = allocateEventId(state)
    local due = hours + delayHours
    local event = {
        id = id,
        kind = "faction_entry",
        policyId = policyId,
        objectiveKind = objectiveKind,
        partySize = partySize,
        memberIds = {},
        targetLocation = {
            x = math.floor(tonumber(target.x)),
            y = math.floor(tonumber(target.y)),
            z = math.floor(tonumber(target.z) or 0),
        },
        phase = "scheduled",
        revision = 1,
        createdAtHours = hours,
        lastChangedAtHours = hours,
        dueAtHours = due,
        deadlineHours = due + 24,
        nextAttemptAtHours = due,
        entryAttempts = 0,
        reason = "awaiting_event_entry",
    }
    state.records[id] = event
    return copy(event), "scheduled"
end

function KnoxEvents.deferFactionEntry(id, revision, hours, reason)
    local event = records()[id]
    if type(event) ~= "table" or event.kind ~= "faction_entry" or event.phase ~= "spawning"
        or event.revision ~= revision or not finite(hours) or hours < event.lastChangedAtHours then
        return nil, "event_changed"
    end
    event.entryAttempts = math.min(96, math.max(0, math.floor(tonumber(event.entryAttempts) or 0)) + 1)
    event.nextAttemptAtHours = math.min(event.deadlineHours, hours + 0.25)
    event.lastChangedAtHours = hours
    event.reason = string.sub(tostring(reason or "event_entry_deferred"), 1, 120)
    return copy(event), "deferred"
end

function KnoxEvents.commitFactionEntry(id, revision, factionId, hours)
    local event, reason = KnoxPersistence.commitEventFactionEntry(id, revision, factionId, hours)
    return event ~= nil and copy(event) or nil, reason
end

function KnoxEvents.beginFactionEntryObjective(id, revision, hours)
    local event = records()[id]
    if type(event) ~= "table" or event.kind ~= "faction_entry" or event.phase ~= "active"
        or event.revision ~= revision then return nil, "event_changed" end
    local changed, reason = KnoxEvents.transition(id, revision, "objective", hours, "event_objective_active")
    if changed == nil then return nil, reason end
    event.objective = { kind = event.objectiveKind, startedAtHours = hours,
        deadlineHours = math.min(event.deadlineHours,
            hours + (event.objectiveKind == "scavenge_world" and 2 or 1)) }
    if event.objectiveKind == "secure_area" then
        event.objective.nextScanAtHours = hours
        event.objective.lastThreatCount = 0
    elseif event.objectiveKind == "scavenge_world" then
        event.objective.requiredItems = math.min(6, #event.memberIds * 2)
        event.objective.receipts = {}
        event.objective.misses = {}
    end
    return copy(event), "started"
end

function KnoxEvents.isValidFactionEntryObjective(event)
    local objective = type(event) == "table" and event.objective or nil
    local valid = event ~= nil and event.kind == "faction_entry" and type(objective) == "table"
        and objective.kind == event.objectiveKind
        and KnoxEventFactions.allowsObjective(event.policyId, objective.kind)
        and finite(objective.startedAtHours) and finite(objective.deadlineHours)
        and objective.deadlineHours > objective.startedAtHours
        and objective.deadlineHours <= event.deadlineHours
    if not valid then return false end
    if objective.kind == "secure_area" then
        local threatCount = tonumber(objective.lastThreatCount)
        return finite(objective.nextScanAtHours)
            and objective.nextScanAtHours >= objective.startedAtHours
            and objective.nextScanAtHours <= objective.deadlineHours
            and threatCount ~= nil and threatCount % 1 == 0
            and threatCount >= 0 and threatCount <= 24
            and (objective.clearSinceHours == nil
                or finite(objective.clearSinceHours)
                    and objective.clearSinceHours >= objective.startedAtHours
                    and objective.clearSinceHours <= objective.deadlineHours)
    elseif objective.kind == "scavenge_world" then
        return event.policyId == "scavengers"
            and validSupplyObjective(event, objective, "scavenge_world")
    end
    return true
end

function KnoxEvents.recordSecureAreaScan(id, revision, hours, threatCount)
    local event = records()[id]
    threatCount = math.floor(tonumber(threatCount) or -1)
    if type(event) ~= "table" or event.phase ~= "objective" or event.revision ~= revision
        or not KnoxEvents.isValidFactionEntryObjective(event)
        or event.objective.kind ~= "secure_area" or not finite(hours)
        or hours < event.objective.nextScanAtHours or hours >= event.objective.deadlineHours
        or threatCount < 0 or threatCount > 24 then return nil, "secure_scan_rejected" end
    event.objective.lastThreatCount = threatCount
    event.objective.lastScanAtHours = hours
    event.objective.nextScanAtHours = math.min(event.objective.deadlineHours, hours + 0.02)
    if threatCount == 0 then
        event.objective.clearSinceHours = event.objective.clearSinceHours or hours
    else
        event.objective.clearSinceHours = nil
    end
    return copy(event), "recorded"
end

function KnoxEvents.finishFactionEntryObjective(id, revision, hours, outcome)
    local event = records()[id]
    if type(event) ~= "table" or event.phase ~= "objective" or event.revision ~= revision
        or not finite(hours) or not KnoxEvents.isValidFactionEntryObjective(event) then
        return nil, "missing_objective_evidence"
    end
    outcome = outcome or "elapsed"
    if event.objective.kind == "scavenge_world" then
        local count = KnoxEvents.objectiveCount(event)
        local exhausted = true
        for _, memberId in ipairs(event.memberIds) do
            if (tonumber(event.objective.misses[memberId]) or 0) < 3 then exhausted = false end
        end
        if (count < event.objective.requiredItems and not exhausted
                and hours < event.objective.deadlineHours)
            or (outcome == "supplies_taken" and count < event.objective.requiredItems)
            or (outcome == "partial_supplies" and count == 0)
            or (outcome == "no_supplies" and count > 0)
            or (outcome ~= "supplies_taken" and outcome ~= "partial_supplies"
                and outcome ~= "no_supplies") then
            return nil, "missing_objective_evidence"
        end
    elseif outcome == "area_secure" then
        if event.objective.kind ~= "secure_area"
            or event.objective.lastThreatCount ~= 0
            or not finite(event.objective.clearSinceHours)
            or hours - event.objective.clearSinceHours < 0.05 then
            return nil, "missing_objective_evidence"
        end
    elseif outcome ~= "elapsed" or hours < event.objective.deadlineHours then
        return nil, "missing_objective_evidence"
    end
    event.objective.outcome = outcome
    event.objective.finishedAtHours = hours
    local changed, reason = KnoxEvents.transition(id, revision, "withdrawing", hours,
        outcome == "area_secure" and "area_secured"
            or outcome == "supplies_taken" and "supplies_taken"
            or outcome == "partial_supplies" and "partial_supplies"
            or outcome == "no_supplies" and "no_supplies"
            or "event_objective_elapsed")
    -- Deserters leave the patrol as recruitable independents only after the
    -- objective transition succeeds; releasing before would fail validation.
    if changed ~= nil then KnoxPersistence.releaseDeserters(id, hours) end
    return changed, reason
end

function KnoxEvents.isTravelEvent(event)
    return type(event) == "table"
        and (event.kind == "faction_raid" or event.kind == "faction_entry")
end
local function baseCenter(base)
    local home = type(base) == "table" and base.home or nil
    if type(home) ~= "table" or not finite(home.minX) or not finite(home.minY)
        or not finite(home.width) or not finite(home.height) then return nil end
    return home.minX + (home.width - 1) / 2, home.minY + (home.height - 1) / 2
end

local function automaticCandidates(hours)
    local candidates = {}
    for factionId, faction in pairs(KnoxPersistence.getFactions()) do
        if type(factionId) == "string" and type(faction) == "table" and faction.kind ~= "player" then
            local home = KnoxPersistence.getBaseForOwner("faction", factionId)
            local homeX, homeY = baseCenter(home)
            if homeX ~= nil then
                for baseId, target in pairs(KnoxPersistence.getBases()) do
                    if type(baseId) == "string" and type(target) == "table"
                        and not (target.ownerKind == "faction" and target.ownerId == factionId) then
                        local targetX, targetY = baseCenter(target)
                        local proposal = targetX ~= nil and KnoxEvents.proposeRaid(factionId, baseId, hours) or nil
                        if proposal ~= nil then
                            local dx, dy = targetX - homeX, targetY - homeY
                            local distance = math.sqrt(dx * dx + dy * dy)
                            if distance <= AUTOMATIC_MAX_DISTANCE then
                                candidates[#candidates + 1] = {
                                    sourceFactionId = factionId,
                                    targetBaseId = baseId,
                                    distance = distance,
                                    key = factionId .. ":" .. baseId,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates, function(first, second)
        if first.distance ~= second.distance then return first.distance < second.distance end
        return first.key < second.key
    end)
    return candidates
end

local function automaticActive()
    for _, event in pairs(records()) do
        if type(event) == "table" and event.trigger == "automatic" and not terminal(event) then return true end
    end
    return false
end

-- This chooses from already-hostile, already-based factions only. It never creates
-- people, hostility, bases or equipment; scheduleRaid revalidates the real roster.
function KnoxEvents.scheduleAutomaticRaid(hours, enabled, minimumDays, intervalDays, force)
    if enabled ~= true then return nil, "automatic_raids_disabled" end
    if not finite(hours) or hours < 0 or not finite(minimumDays) or not finite(intervalDays)
        or minimumDays < 0 or minimumDays > 90 or intervalDays < 1 or intervalDays > 30 then
        return nil, "invalid_automatic_policy"
    end
    local automatic = KnoxPersistence.getKnoxEventState().automatic
    if type(automatic) ~= "table" then return nil, "automatic_state_unavailable" end
    local earliest = minimumDays * 24
    if hours < earliest then
        automatic.nextCheckHours = math.max(tonumber(automatic.nextCheckHours) or 0, earliest)
        return nil, "world_too_young"
    end
    if force ~= true and hours < (tonumber(automatic.nextCheckHours) or 0) then
        return nil, "automatic_check_not_due"
    end
    if automaticActive() then
        automatic.nextCheckHours = math.max(tonumber(automatic.nextCheckHours) or 0, hours + 1)
        return nil, "automatic_event_active"
    end
    local candidates = automaticCandidates(hours)
    local intervalHours = intervalDays * 24
    if #candidates == 0 then
        automatic.nextCheckHours = hours + math.min(AUTOMATIC_RETRY_HOURS, intervalHours)
        return nil, "no_eligible_raid"
    end
    local cursor = math.max(0, math.floor(tonumber(automatic.cursor) or 0))
    for offset = 1, #candidates do
        local index = (cursor + offset - 1) % #candidates + 1
        local candidate = candidates[index]
        local delay = force == true and 0 or 1 + ((math.floor(hours) + index) % 4)
        local event = KnoxEvents.scheduleRaid(candidate.sourceFactionId, candidate.targetBaseId, hours, delay)
        if event ~= nil then
            local stored = records()[event.id]
            stored.trigger = "automatic"
            stored.triggerDistance = candidate.distance
            automatic.cursor = index
            automatic.nextCheckHours = hours + intervalHours
            return KnoxEvents.get(event.id), "automatic_raid_scheduled"
        end
    end
    automatic.nextCheckHours = hours + math.min(AUTOMATIC_RETRY_HOURS, intervalHours)
    return nil, "eligibility_changed"
end

-- Automatic police/military/scientist patrols. Unlike raids these need no
-- source base: they stage near loaded players, work their first policy
-- objective, then leave the county. Disabled policies never schedule.
local ENTRY_AUTO_POLICIES = { "police", "military", "scientists" }
local ENTRY_RETRY_HOURS = 6

local function loadedPlayerSquares()
    local squares = {}
    if getSpecificPlayer == nil then return squares end
    local count = 4
    if getNumActivePlayers ~= nil then
        local ok, n = pcall(getNumActivePlayers)
        if ok and tonumber(n) ~= nil then count = math.max(1, math.floor(tonumber(n))) end
    end
    for index = 0, math.max(0, count - 1) do
        local ok, player = pcall(getSpecificPlayer, index)
        local square = ok and player ~= nil and player.getCurrentSquare ~= nil
            and player:getCurrentSquare() or nil
        if square ~= nil then squares[#squares + 1] = square end
    end
    return squares
end

local function entryEligiblePolicies(hours)
    local eligible = {}
    for _, policyId in ipairs(ENTRY_AUTO_POLICIES) do
        local policy = KnoxEventFactions ~= nil and KnoxEventFactions.get(policyId) or nil
        if policy ~= nil and policy.disabled ~= true
            and KnoxEventFactions.isWorldAgeEligible(policyId, hours) then
            eligible[#eligible + 1] = policyId
        end
    end
    return eligible
end

-- Weighted deterministic pick over the expanded weight list, so scientists
-- stay rare and police stay common without random scheduler state.
local function pickEntryPolicy(eligible, cursor)
    local bag = {}
    for _, policyId in ipairs(eligible) do
        local policy = KnoxEventFactions.get(policyId)
        local weight = math.max(1, math.floor(tonumber(policy.schedulerWeight) or 1))
        for _ = 1, weight do bag[#bag + 1] = policyId end
    end
    if #bag == 0 then return nil end
    return bag[(math.max(0, math.floor(tonumber(cursor) or 0)) % #bag) + 1]
end

function KnoxEvents.scheduleAutomaticEntry(hours, enabled, minimumDays, intervalDays, force)
    if enabled ~= true then return nil, "automatic_entries_disabled" end
    if not finite(hours) or hours < 0 or not finite(minimumDays) or not finite(intervalDays)
        or minimumDays < 0 or minimumDays > 90 or intervalDays < 1 or intervalDays > 30 then
        return nil, "invalid_automatic_policy"
    end
    local automatic = KnoxPersistence.getKnoxEventState().automatic
    if type(automatic) ~= "table" then return nil, "automatic_state_unavailable" end
    local earliest = minimumDays * 24
    if hours < earliest then
        automatic.entryNextCheckHours = math.max(tonumber(automatic.entryNextCheckHours) or 0, earliest)
        return nil, "world_too_young"
    end
    if force ~= true and hours < (tonumber(automatic.entryNextCheckHours) or 0) then
        return nil, "automatic_check_not_due"
    end
    if automaticActive() then
        automatic.entryNextCheckHours = math.max(tonumber(automatic.entryNextCheckHours) or 0, hours + 1)
        return nil, "automatic_event_active"
    end
    local players = loadedPlayerSquares()
    if #players == 0 then
        automatic.entryNextCheckHours = hours + math.min(ENTRY_RETRY_HOURS, intervalDays * 24)
        return nil, "no_loaded_players"
    end
    local eligible = entryEligiblePolicies(hours)
    if #eligible == 0 then
        automatic.entryNextCheckHours = hours + math.min(ENTRY_RETRY_HOURS, intervalDays * 24)
        return nil, "no_eligible_entry"
    end
    local cursor = math.max(0, math.floor(tonumber(automatic.entryCursor) or 0))
    local policyId = pickEntryPolicy(eligible, cursor)
    local policy = KnoxEventFactions.get(policyId)
    local sizeMin = tonumber(policy.partySize ~= nil and policy.partySize[1]) or 2
    local sizeMax = tonumber(policy.partySize ~= nil and policy.partySize[2]) or sizeMin
    local partySize = sizeMin + (cursor % math.max(1, sizeMax - sizeMin + 1))
    local square = players[(cursor % #players) + 1]
    -- Deterministic offset near (never on top of) a loaded player; dispatch
    -- validates real world anchors 100-600 tiles out before anyone spawns.
    local angle = (cursor + 1) * 2.399963
    local distance = 200 + ((cursor * 137) % 200)
    local target = {
        x = math.floor(square:getX() + math.cos(angle) * distance),
        y = math.floor(square:getY() + math.sin(angle) * distance),
        z = math.max(0, math.min(7, square:getZ())),
    }
    local delay = force == true and 0 or 1 + ((math.floor(hours) + cursor) % 4)
    local event = KnoxEvents.scheduleFactionEntry(policyId, policy.objectives[1],
        target, partySize, hours, delay)
    if event == nil then
        automatic.entryNextCheckHours = hours + math.min(ENTRY_RETRY_HOURS, intervalDays * 24)
        return nil, "eligibility_changed"
    end
    local stored = records()[event.id]
    stored.trigger = "automatic"
    automatic.entryCursor = cursor + 1
    automatic.entryNextCheckHours = hours + intervalDays * 24
    return KnoxEvents.get(event.id), "automatic_entry_scheduled"
end

function KnoxEvents.isValidRecord(event)
    if type(event) ~= "table" or not KnoxEvents.isTravelEvent(event) or NEXT[event.phase] == nil
        or not serial(event.revision)
        or not finite(event.dueAtHours) or not finite(event.lastChangedAtHours)
        or not finite(event.deadlineHours) or event.deadlineHours < event.dueAtHours then
        return false
    end
    if event.kind == "faction_raid" then return memberList(event.memberIds) end
    if type(event.policyId) ~= "string" or type(event.objectiveKind) ~= "string"
        or not serial(event.partySize) or event.partySize < 2 or event.partySize > 6
        or not point(event.targetLocation) or not finite(event.createdAtHours)
        or not finite(event.nextAttemptAtHours) or not finite(event.entryAttempts)
        or event.nextAttemptAtHours < event.dueAtHours or event.nextAttemptAtHours > event.deadlineHours
        or event.entryAttempts < 0 or event.entryAttempts > 96 or event.entryAttempts % 1 ~= 0 then
        return false
    end
    if event.sourceFactionId == nil then
        return (event.phase == "scheduled" or event.phase == "spawning") and emptyList(event.memberIds)
            and event.entryLocation == nil and event.sourceGroupId == nil
    end
    return type(event.sourceFactionId) == "string" and event.sourceFactionId ~= ""
        and type(event.sourceGroupId) == "string" and event.sourceGroupId ~= ""
        and memberList(event.memberIds) and #event.memberIds == event.partySize and point(event.entryLocation)
end

function KnoxEvents.validate(event)
    if not KnoxEvents.isValidRecord(event) then return false, "invalid_event_record" end
    if event.kind == "faction_entry" then
        if not KnoxEventFactions.isWorldAgeEligible(event.policyId, event.createdAtHours)
            or not KnoxEventFactions.allowsObjective(event.policyId, event.objectiveKind) then
            return false, "invalid_event_policy"
        end
        if event.sourceFactionId == nil then return true, "valid" end
        local faction = KnoxPersistence.getFaction(event.sourceFactionId)
        local identity = faction ~= nil and faction.eventIdentity or nil
        if identity == nil or identity.policyId ~= event.policyId
            or identity.sourceEventId ~= event.id then return false, "event_faction_changed" end
        local roster = {}; for _, id in ipairs(faction.memberIds or {}) do roster[id] = true end
        for _, id in ipairs(event.memberIds) do
            local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
            local group = KnoxPersistence.getTravelGroupFor(id)
            if not roster[id] or not KnoxPersistence.isSurvivorAlive(id)
                or affiliation == nil or affiliation.factionId ~= faction.id
                or group == nil or group.id ~= event.sourceGroupId then return false, "member_lost" end
        end
        if event.phase == "objective" and not KnoxEvents.isValidFactionEntryObjective(event) then
            return false, "objective_state_missing"
        end
        return true, "valid"
    end
    local owners, reason = raidOwners(event.sourceFactionId, event.targetBaseId)
    if owners == nil then return false, reason end
    if owners.targetFactionId ~= event.targetFactionId or owners.home.id ~= event.sourceBaseId
        or locationKey(owners.home) ~= event.sourceLocation
        or locationKey(owners.target) ~= event.targetLocation then return false, "base_changed" end
    local roster, members, living = {}, {}, livingRoster(owners.faction)
    for _, id in ipairs(living) do roster[id] = true end
    local available = 0
    for id in pairs(roster) do if availableMember(id, owners.home) then available = available + 1 end end
    for _, id in ipairs(event.memberIds) do
        if members[id] or not roster[id] then return false, "member_lost" end
        members[id] = true
        if event.phase == "scheduled" and not availableMember(id, owners.home) then
            return false, "member_unavailable"
        end
    end
    if event.phase == "scheduled" and (available - #event.memberIds < 2
        or #event.memberIds > math.floor(#living * 0.4)) then
        return false, "insufficient_home_strength"
    end
    return true, "valid"
end

-- Compare-and-set transitions prevent a late callback from overwriting a newer
-- phase. The dispatcher (not a timer) must report arrival/objective/return results.
function KnoxEvents.transition(id, revision, phase, hours, reason)
    local event = records()[id]
    if type(event) ~= "table" or event.id ~= id or NEXT[event.phase] == nil then return nil, "unknown_event" end
    if not serial(event.revision) then return nil, "invalid_event_record" end
    if not finite(hours) or not finite(event.lastChangedAtHours)
        or hours < event.lastChangedAtHours then return nil, "invalid_time" end
    if event.phase == phase then return copy(event), "unchanged" end
    if event.revision ~= revision then return nil, "stale_revision" end
    if not NEXT[event.phase][phase] then return nil, "invalid_transition" end
    if phase ~= "failed" and phase ~= "withdrawing" and phase ~= "completed" then
        local valid, why = KnoxEvents.validate(event)
        if not valid then return nil, why end
    end
    if event.phase == "scheduled" and phase == "spawning" and hours < event.dueAtHours then
        return nil, "not_due"
    end
    event.phase, event.revision = phase, event.revision + 1
    event.lastChangedAtHours = hours
    event.reason = type(reason) == "string" and string.sub(reason, 1, 120) or phase
    if terminal(event) then retainCooldown(event) end
    return copy(event), "changed"
end

function KnoxEvents.maintain(hours, budget)
    if not finite(hours) or hours < 0 then return 0 end
    local state = KnoxPersistence.getKnoxEventState()
    local ids, history = {}, {}
    for id, event in pairs(state.records) do
        if type(id) == "string" then
            ids[#ids + 1] = id
            if type(event) == "table" and terminal(event) then
                history[#history + 1] = id
                retainCooldown(event)
            end
        else
            state.records[id] = nil
        end
    end
    table.sort(ids)
    table.sort(history, function(a, b)
        local first, second = state.records[a].lastChangedAtHours, state.records[b].lastChangedAtHours
        first, second = finite(first) and first or 0, finite(second) and second or 0
        return first == second and a < b or first < second
    end)
    budget = finite(budget) and math.max(1, math.min(32, math.floor(budget))) or 16
    local cursor, processed = finite(state.cursor) and math.max(0, math.floor(state.cursor)) or 0, 0
    for step = 1, math.min(budget, #ids) do
        cursor = cursor % #ids + 1
        local id = ids[cursor]
        local event = state.records[id]
        if type(event) ~= "table" or event.id ~= id or NEXT[event.phase] == nil
            or not serial(event.revision) or not finite(event.lastChangedAtHours)
            or (not terminal(event) and not finite(event.deadlineHours)) then
            -- Corrupt deployed bookkeeping must not erase a possibly live party.
            -- Retain its roster/owners for the dispatcher's actual return cleanup.
            local recovered = type(event) == "table" and event or {}
            local deployed = not terminal(recovered) and recovered.phase ~= "scheduled"
                and type(recovered.memberIds) == "table" and not emptyList(recovered.memberIds)
            recovered.id, recovered.phase = id, deployed and "withdrawing" or "failed"
            recovered.revision, recovered.lastChangedAtHours = 1, hours
            recovered.deadlineHours, recovered.reason = hours, "invalid_event_record"
            state.records[id] = recovered
            if terminal(recovered) then retainCooldown(recovered) end
        elseif not terminal(event) then
            local valid, reason = KnoxEvents.validate(event)
            if not valid or hours >= event.deadlineHours then
                local undeployedEntry = event.kind == "faction_entry" and event.sourceFactionId == nil
                local phase = (event.phase == "scheduled" or undeployedEntry)
                    and "failed" or "withdrawing"
                if event.phase ~= "withdrawing" then
                    KnoxEvents.transition(id, event.revision, phase, hours,
                        valid and "event_deadline" or reason)
                end
            end
        elseif hours - (event.lastChangedAtHours or hours) >= RETAIN_HOURS then
            state.records[id] = nil
        end
        processed = processed + 1
    end
    state.cursor = cursor
    -- Prune only finished history. Never discard an active withdrawal to hide a
    -- stalled dispatcher or recreate its members as a fresh event.
    for index = 1, math.min(budget, math.max(0, #history - HISTORY_LIMIT)) do
        state.records[history[index]] = nil
    end
    local expired = 0
    for factionId, untilHours in pairs(state.cooldowns) do
        if not finite(untilHours) or hours >= untilHours or KnoxPersistence.getFaction(factionId) == nil then
            state.cooldowns[factionId] = nil
            expired = expired + 1
            if expired >= budget then break end
        end
    end
    return processed
end

return KnoxEvents
