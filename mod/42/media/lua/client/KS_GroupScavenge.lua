-- Scavenging pairs for player/faction bases and camps. On a slow cadence during
-- the day, a settlement with enough idle members sends two of them out as a
-- group: the leader roams/loots with the normal exploration machinery while
-- the follower holds formation, exactly like the player with companions.
-- Base supply pairs keep their formation until both return home.
-- Other pairs dissolve at nightfall or after two hours. Loot comes from
-- real container transfers, and the lease table is loaded-world only.
local Parties = rawget(_G, "KnoxGroupScavenge") or {}
_G.KnoxGroupScavenge = Parties

Parties.PAIR_SIZE = 2
Parties.PAIR_MIN_MEMBERS = 3
Parties.PAIR_LEASE_HOURS = 2
Parties.COORDINATE_INTERVAL_TICKS = 3600

local leasesBySettlement = {}
local nextRun = 0

local function worldAgeHours()
    if getGameTime == nil then
        return 0
    end
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    return ok and (tonumber(hours) or 0) or 0
end

local function isDay()
    local shelter = rawget(_G, "KnoxNightShelter")
    if shelter == nil or shelter.isNight == nil then
        return true
    end
    return not shelter.isNight()
end

local function alive(persistence, id)
    if persistence == nil or persistence.isSurvivorAlive == nil then
        return true
    end
    return persistence.isSurvivorAlive(id) ~= false
end

local function present(persistence, id)
    if persistence == nil or persistence.isSurvivorPresent == nil then
        return true
    end
    return persistence.isSurvivorPresent(id) ~= false
end

local function hasClaim(persistence, id, baseId)
    if baseId == nil or persistence == nil
        or persistence.getClaimedBaseTaskForSurvivor == nil then
        return false
    end
    return persistence.getClaimedBaseTaskForSurvivor(id, baseId) ~= nil
end

local function settlementKey(controller)
    if controller.baseId ~= nil then
        return "base:" .. tostring(controller.baseId)
    end
    if controller.campId ~= nil then
        return "camp:" .. tostring(controller.campId)
    end
    return nil
end

local function isFactionSettlement(controller)
    if controller.baseId ~= nil then return controller.base ~= nil end
    return controller.campId ~= nil and controller.camp ~= nil
end

local function settlementSupplyNeeds(controller, residentCount)
    local base = controller ~= nil and controller.base or nil
    if base == nil or controller.baseId == nil then return nil end
    local storage = rawget(_G, "KnoxBaseStorage")
    local planner = rawget(_G, "KnoxBaseSupplyPlanner")
    if storage == nil or storage.summarize == nil or planner == nil
        or planner.reserveStatus == nil then return nil end
    local ok, summary = pcall(storage.summarize, base)
    if not ok or type(summary) ~= "table" then return nil end
    local needs = { baseId = controller.baseId, categories = {}, types = {}, typeRules = {} }
    for _, status in ipairs(planner.reserveStatus(summary.totals or {}, residentCount)) do
        if (tonumber(status.missing) or 0) > 0 then
            needs.categories[tostring(status.category)] = tonumber(status.missing)
        end
    end
    for _, task in pairs(base.tasks or {}) do
        if task.state == "queued" or task.state == "claimed" then
            local requirements = task.requirements
            for itemType, required in pairs(requirements ~= nil and requirements.items or {}) do
                itemType = tostring(itemType)
                local count = math.max(0, math.floor(tonumber(required) or 0))
                local exact = { items = { [itemType] = count },
                    itemRules = requirements.itemRules }
                local assigned = storage.countAssignedItem ~= nil
                    and storage.countAssignedItem(base, itemType, exact) or 0
                needs.types[itemType] = math.max(
                    tonumber(needs.types[itemType]) or 0,
                    count - math.max(0, math.floor(tonumber(assigned) or 0))
                )
                needs.typeRules[itemType] = needs.typeRules[itemType] or {}
                needs.typeRules[itemType][#needs.typeRules[itemType] + 1] = exact
            end
        end
    end
    for itemType, missing in pairs(needs.types) do
        if missing <= 0 then needs.types[itemType] = nil end
    end
    -- Build 42 Kahlua does not expose the global Lua next() function.
    -- Use its supported iterator without changing shortage admission.
    for _ in pairs(needs.categories) do return needs end
    for _ in pairs(needs.types) do return needs end
    return nil
end

local function isSupplyPartySettlement(controller)
    return controller ~= nil and controller.base ~= nil
        and controller.baseId ~= nil
end

local function belongsToSettlement(controller, id, persistence)
    local base = controller ~= nil and controller.base or nil
    if base == nil or base.ownerKind ~= "faction" then return true end
    if persistence ~= nil and persistence.getBase ~= nil then
        local ok, current = pcall(persistence.getBase, controller.baseId)
        if not ok or current == nil or current.ownerKind ~= "faction" then return false end
        base = current
    end
    local ownerId = tostring(base.ownerId or "")
    if ownerId == "" or persistence == nil or persistence.getSurvivorAffiliation == nil then
        return false
    end
    local ok, affiliation = pcall(persistence.getSurvivorAffiliation, id)
    return ok and type(affiliation) == "table" and affiliation.kind == "faction"
        and tostring(affiliation.factionId or "") == ownerId
end

local function idleState(controller)
    return controller.state == "BASE_IDLE" or controller.state == "CAMP_IDLE"
end

local function leaseAuthorized(lease)
    if lease.factionOwnerId == nil then return true end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getSurvivorAffiliation == nil then return false end
    if persistence.getBase ~= nil then
        local ok, base = pcall(persistence.getBase, lease.baseId)
        if not ok or base == nil or base.ownerKind ~= "faction"
            or tostring(base.ownerId or "") ~= lease.factionOwnerId then return false end
    end
    for _, id in ipairs({ lease.leaderId, lease.followerId }) do
        local ok, affiliation = pcall(persistence.getSurvivorAffiliation, id)
        if not ok or type(affiliation) ~= "table" or affiliation.kind ~= "faction"
            or tostring(affiliation.factionId or "") ~= lease.factionOwnerId then return false end
    end
    return true
end

local function readyForSortie(controller)
    -- A scavenging pair is a short base duty, not permission to ignore an
    -- urgent personal need.  Let the normal needs controller finish food,
    -- water, medical care, sleep, or recovery first; otherwise the pair is
    -- formed only to split apart a few seconds later and the resident appears
    -- to wander aimlessly.  Missing test/runtime APIs fail open because the
    -- ordinary duty and threat gates still apply.
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs == nil or needs.decide == nil or controller.character == nil then
        return true
    end
    local ok, decision = pcall(function()
        return needs.decide(controller.character, nil)
    end)
    if not ok or type(decision) ~= "table" then
        return true
    end
    local kind = tostring(decision.kind or "")
    -- `rest` is an actual endurance recovery decision, not ambient idle
    -- behavior. Sending that resident out creates a sortie that immediately
    -- yields to self-care and makes the pair look like aimless wandering.
    return kind == "" or kind == "roam"
end

local function availableDuty(controller, id, persistence)
    if not belongsToSettlement(controller, id, persistence)
        or not alive(persistence, id) or not present(persistence, id)
        or controller.eventAssignment ~= nil
        or controller.awayTeamId ~= nil or hasClaim(persistence, id, controller.baseId) then
        return false
    end
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or {}
    if duty.eventId ~= nil then return false end
    if controller.baseId ~= nil then
        return duty.mode == "base" and (duty.baseId == nil or duty.baseId == controller.baseId)
            and (duty.jobPreference == nil or duty.jobPreference == "auto")
            and duty.baseSupplyOrder == nil and duty.activeSupplyRun == nil
            and (controller.base ~= nil and controller.base.ownerKind == "faction"
                and duty.allowLootRuns ~= false or duty.allowLootRuns == true)
    end
    return duty.mode == nil or duty.mode == "autonomous"
end

local function eligible(controllers, id, persistence)
    local controller = controllers[id]
    if controller == nil or controller.character == nil or controller.pendingBaseSupplyDeposit ~= nil then
        return false
    end
    local square = controller.character.getCurrentSquare ~= nil
        and controller.character:getCurrentSquare() or nil
    if square == nil or not idleState(controller) then
        return false
    end
    local manager = rawget(_G, "KnoxBaseManager")
    if controller.baseId ~= nil and manager ~= nil and manager.containsSquare ~= nil
        and not manager.containsSquare(controller.base, square) then return false end
    if controller.eventAssignment ~= nil or controller.awayTeamId ~= nil then
        return false
    end
    if controller.groupLeaderId ~= nil then
        return false
    end
    if not alive(persistence, id) then
        return false
    end
    if not readyForSortie(controller) then
        return false
    end
    if hasClaim(persistence, id, controller.baseId) then
        return false
    end
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or {}
    if controller.baseId ~= nil and tostring(duty.mode or "") ~= "base" then
        return false
    end
    if controller.combatTarget ~= nil or controller.pendingThreatAwareness ~= nil then return false end
    return availableDuty(controller, id, persistence)
end

local function livePair(key, controllers, nowHours)
    local lease = leasesBySettlement[key]
    if type(lease) ~= "table" then
        return nil
    end
    local homeKey = lease.settlementKey or key
    if not leaseAuthorized(lease) then return nil end
    if (tonumber(lease.untilHours) or 0) <= nowHours then
        return nil
    end
    local leader = controllers[lease.leaderId]
    local follower = controllers[lease.followerId]
    if leader == nil or follower == nil
        or leader.character == nil or follower.character == nil then
        return nil
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if lease.purpose == "base_supply" and lease.returning == true then
        for _, id in ipairs({ lease.leaderId, lease.followerId }) do
            local member = controllers[id]
            local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
                and persistence.getSurvivorDuty(id) or nil
            if not alive(persistence, id) or not present(persistence, id)
                or not belongsToSettlement(member, id, persistence)
                or settlementKey(member) ~= homeKey or duty == nil or duty.mode ~= "base"
                or duty.baseId ~= member.baseId or member.eventAssignment ~= nil
                or member.awayTeamId ~= nil then return nil end
        end
        return lease
    end
    if settlementKey(leader) ~= homeKey or settlementKey(follower) ~= homeKey
        or not isFactionSettlement(leader) or not isFactionSettlement(follower)
        or not availableDuty(leader, lease.leaderId, persistence)
        or not availableDuty(follower, lease.followerId, persistence) then return nil end
    return lease
end

local function dissolve(key, controllers, reason)
    local lease = leasesBySettlement[key]
    leasesBySettlement[key] = nil
    if type(lease) ~= "table" then
        return
    end
    local homeKey = lease.settlementKey or key
    local function recall(controller, id)
        local persistence = rawget(_G, "KnoxPersistence")
        local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
            and persistence.getSurvivorDuty(id) or nil
        if lease.purpose == "base_supply" and reason ~= "returned_home"
            and controller ~= nil and controller.recallSettlementSortie ~= nil
            and duty ~= nil and duty.mode == "base" and duty.baseId == controller.baseId
            and settlementKey(controller) == homeKey and alive(persistence, id) then
            if not belongsToSettlement(controller, id, persistence) then return false end
            controller:recallSettlementSortie(0)
            return true
        end
        return false
    end
    local leader = controllers[lease.leaderId]
    if leader ~= nil then
        leader.scavengeSortieUntilHours = nil
        leader.scavengeSortieReturning = nil
        leader.baseSupplyParty = nil
        leader.baseSupplyPartyNeeds = nil
        leader.baseSupplyPartyInventories = nil
        leader.baseSupplyPartyReturning = nil
        recall(leader, lease.leaderId)
        if leader.setGroupMembers ~= nil then
            leader:setGroupMembers({})
        end
    end
    local follower = controllers[lease.followerId]
    if follower ~= nil and follower.groupLeaderId == lease.leaderId then
        if follower.clearGroupLeader ~= nil then
            follower:clearGroupLeader()
        end
        if follower.setGroupMembers ~= nil then
            follower:setGroupMembers({})
        end
    end
    if follower ~= nil then
        follower.baseSupplyParty = nil
        follower.baseSupplyPartyNeeds = nil
        follower.baseSupplyPartyInventories = nil
        follower.baseSupplyPartyReturning = nil
        recall(follower, lease.followerId)
    end
    print("[KnoxSurvivors][Scavenge] dissolved settlement=" .. tostring(key)
        .. " reason=" .. tostring(reason))
end

function Parties.leases()
    return leasesBySettlement
end

function Parties.ownsController(id, controller, controllers)
    local key = controller ~= nil and settlementKey(controller) or nil
    if key == nil then return false end
    for leaseKey, candidate in pairs(leasesBySettlement) do
        if (candidate.settlementKey or leaseKey) == key
            and (candidate.leaderId == id or candidate.followerId == id)
            and livePair(leaseKey, controllers, worldAgeHours()) ~= nil then return true end
    end
    return false
end

-- Read-only reservation query for other base-life selectors. A supply run
-- must not elect someone already committed to this generic settlement outing.
function Parties.ownsSurvivor(id)
    if type(id) ~= "string" or id == "" then return false end
    local nowHours = worldAgeHours()
    for _, lease in pairs(leasesBySettlement) do
        if type(lease) == "table"
            and leaseAuthorized(lease)
            and (tonumber(lease.untilHours) or 0) > nowHours
            and (lease.leaderId == id or lease.followerId == id) then
            return true
        end
    end
    return false
end

function Parties.hasSupplyParty(baseId)
    local homeKey = "base:" .. tostring(baseId or "")
    for key, lease in pairs(leasesBySettlement) do
        if (lease.settlementKey or key) == homeKey and lease.purpose == "base_supply"
            and leaseAuthorized(lease)
            and (tonumber(lease.untilHours) or 0) > worldAgeHours() then return true end
    end
    return false
end

-- A village waits for a safe partner rather than silently falling back to
-- several solo automatic runs when residents are resting or told Stay Home.
-- Explicit supply orders and already-persisted runs keep their own owner.
function Parties.prefersSupplyParty(base)
    local persistence = rawget(_G, "KnoxPersistence")
    if base == nil or persistence == nil or persistence.getBaseResidentIds == nil
        or persistence.getSurvivorDuty == nil then return false end
    local count = 0
    for _, id in ipairs(persistence.getBaseResidentIds(base.id) or {}) do
        local duty = persistence.getSurvivorDuty(id)
        if duty ~= nil and duty.mode == "base" and duty.baseId == base.id
            and alive(persistence, id) and present(persistence, id)
            and belongsToSettlement({base = base, baseId = base.id}, id, persistence) then
            count = count + 1
        end
    end
    return count >= Parties.PAIR_MIN_MEMBERS
end

function Parties.coordinate(controllers, activeIds, ticks)
    local nowHours = worldAgeHours()
    local day = isDay()
    -- Release invalid ownership promptly; expensive candidate selection stays
    -- on its slow cadence. This also covers settlements absent from activeIds.
    for key, lease in pairs(leasesBySettlement) do
        local leader = type(lease) == "table" and controllers[lease.leaderId] or nil
        local follower = type(lease) == "table" and controllers[lease.followerId] or nil
        local persistence = rawget(_G, "KnoxPersistence")
        local function canReturn(controller, id)
            local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
                and persistence.getSurvivorDuty(id) or nil
            return controller ~= nil and controller.character ~= nil
                and leaseAuthorized(lease)
                and alive(persistence, id) and present(persistence, id)
                and belongsToSettlement(controller, id, persistence)
                and settlementKey(controller) == (lease.settlementKey or key) and duty ~= nil
                and duty.mode == "base" and duty.baseId == controller.baseId
                and controller.eventAssignment == nil and controller.awayTeamId == nil
        end
        local supplyReturning = type(lease) == "table" and lease.purpose == "base_supply"
            and (lease.returning == true or not day
                or (tonumber(lease.untilHours) or 0) <= nowHours
                or leader ~= nil and (leader.scavengeSortieReturning == true
                    or not readyForSortie(leader) or leader.combatTarget ~= nil)
                or follower ~= nil and (not readyForSortie(follower) or follower.combatTarget ~= nil)
                or leader ~= nil and not availableDuty(leader, lease.leaderId, persistence)
                or follower ~= nil and not availableDuty(follower, lease.followerId, persistence))
        if supplyReturning and canReturn(leader, lease.leaderId)
            and canReturn(follower, lease.followerId) then
            lease.returning = true
            leader:recallSettlementSortie(ticks)
            follower:recallSettlementSortie(ticks)
            local manager = rawget(_G, "KnoxBaseManager")
            local leaderSquare = leader.character ~= nil and leader.character:getCurrentSquare() or nil
            local followerSquare = follower.character ~= nil and follower.character:getCurrentSquare() or nil
            local leaderHome = leaderSquare ~= nil and manager ~= nil
                and manager.containsSquare(leader.base, leaderSquare) == true
            local followerHome = followerSquare ~= nil and manager ~= nil
                and manager.containsSquare(follower.base, followerSquare) == true
            if leaderHome and followerHome then
                dissolve(key, controllers, "returned_home")
            else
                lease.untilHours = nowHours + 0.25
            end
        elseif not day or livePair(key, controllers, nowHours) == nil then
            dissolve(key, controllers, day and "lease_ended" or "nightfall")
        end
    end
    if ticks < nextRun then
        return
    end
    nextRun = ticks + Parties.COORDINATE_INTERVAL_TICKS
    local persistence = rawget(_G, "KnoxPersistence")
    -- Buckets of faction-settlement members by home base/camp.
    local buckets = {}
    for _, id in ipairs(activeIds or {}) do
        local controller = controllers[id]
        if controller ~= nil and isFactionSettlement(controller)
            and belongsToSettlement(controller, id, persistence)
            and alive(persistence, id) and present(persistence, id) then
            local key = settlementKey(controller)
            if key ~= nil then
                buckets[key] = buckets[key] or {}
                buckets[key][#buckets[key] + 1] = id
            end
        end
    end
    if not day then return end
    for key, memberIds in pairs(buckets) do
        local first = controllers[memberIds[1]]
        local residentCount = #memberIds
        local supplyNeeds = isSupplyPartySettlement(first)
            and settlementSupplyNeeds(first, residentCount) or nil
        local supplyParty = supplyNeeds ~= nil
        local existingCount, sharedNeeds = 0, nil
        for leaseKey, lease in pairs(leasesBySettlement) do
            if (lease.settlementKey or leaseKey) == key then
                existingCount = existingCount + 1
                sharedNeeds = sharedNeeds or lease.supplyNeeds
            end
        end
        -- A native pickup may still own its reservation after the last pair
        -- dissolves. Reuse that table rather than losing the pending claim
        -- when the next outing forms; releaseSupply still owns its removal.
        if sharedNeeds == nil then
            for _, id in ipairs(memberIds) do
                local pending = controllers[id].pendingSupply
                if pending ~= nil and pending.baseSupplyPartyBaseId == first.baseId
                    and pending.baseSupplyPartyReservationNeeds ~= nil then
                    sharedNeeds = pending.baseSupplyPartyReservationNeeds
                    break
                end
            end
        end
        -- Keep one shared table: pending native transfers retain their claims
        -- against it while storage demand is refreshed. All loaded residents'
        -- marked delivery cargo counts, including a pair already returning.
        local inventories = {}
        for _, id in ipairs(memberIds) do
            local character = controllers[id].character
            if character ~= nil then inventories[#inventories + 1] = character end
        end
        if sharedNeeds ~= nil then
            sharedNeeds.categories = supplyNeeds ~= nil and supplyNeeds.categories or {}
            sharedNeeds.types = supplyNeeds ~= nil and supplyNeeds.types or {}
            sharedNeeds.typeRules = supplyNeeds ~= nil and supplyNeeds.typeRules or {}
            supplyNeeds = sharedNeeds
        end
        for leaseKey, lease in pairs(leasesBySettlement) do
            if (lease.settlementKey or leaseKey) == key and lease.purpose == "base_supply" then
                for _, id in ipairs({lease.leaderId, lease.followerId}) do
                    controllers[id].baseSupplyPartyInventories = inventories
                end
            end
        end
        -- Three residents can send one pair. Larger villages retain at least
        -- half at home. The allowance scales with the settlement population.
        local pairLimit = supplyParty and math.max(1, math.floor(residentCount / 4)) or 1
        if supplyParty then
            local manager = rawget(_G, "KnoxBaseManager")
            local homeCount = 0
            for _, id in ipairs(memberIds) do
                local member = controllers[id]
                local square = member.character ~= nil and member.character:getCurrentSquare() or nil
                if not Parties.ownsSurvivor(id) and square ~= nil and manager ~= nil
                    and manager.containsSquare ~= nil and manager.containsSquare(member.base, square) then
                    homeCount = homeCount + 1
                end
            end
            local minimumHome = residentCount == 3 and 1 or math.ceil(residentCount / 2)
            pairLimit = math.min(pairLimit, existingCount
                + math.max(0, math.floor((homeCount - minimumHome) / Parties.PAIR_SIZE)))
        end
        if existingCount < pairLimit and #memberIds >= Parties.PAIR_MIN_MEMBERS
            and (not isSupplyPartySettlement(first) or supplyParty) then
            local candidates = {}
            for _, id in ipairs(memberIds) do
                if not Parties.ownsSurvivor(id) and eligible(controllers, id, persistence) then
                    candidates[#candidates + 1] = id
                end
            end
            local candidateIndex = 1
            while existingCount < pairLimit and #candidates - candidateIndex + 1 >= Parties.PAIR_SIZE do
                local leaderId, followerId = candidates[candidateIndex], candidates[candidateIndex + 1]
                candidateIndex = candidateIndex + Parties.PAIR_SIZE
                local leader = controllers[leaderId]
                local follower = controllers[followerId]
                local leaderChar = leader.character
                local leaseKey = key
                local slot = 1
                while leasesBySettlement[leaseKey] ~= nil do
                    slot = slot + 1
                    leaseKey = key .. ":pair:" .. tostring(slot)
                end
                leasesBySettlement[leaseKey] = {
                    settlementKey = key,
                    leaderId = leaderId,
                    followerId = followerId,
                    untilHours = nowHours + Parties.PAIR_LEASE_HOURS,
                    purpose = supplyParty and "base_supply" or "routine_scavenge",
                    supplyNeeds = supplyNeeds,
                    baseId = leader.baseId,
                    factionOwnerId = leader.base ~= nil and leader.base.ownerKind == "faction"
                        and tostring(leader.base.ownerId) or nil,
                }
                leader.scavengeSortieUntilHours = nowHours + Parties.PAIR_LEASE_HOURS
                leader.baseSupplyParty = supplyParty or nil
                leader.baseSupplyPartyNeeds = supplyParty and supplyNeeds or nil
                leader.baseSupplyPartyInventories = supplyParty
                    and inventories or nil
                if leader.setGroupMembers ~= nil then
                    leader:setGroupMembers({ follower.character })
                end
                if follower.setGroupLeader ~= nil then
                    follower:setGroupLeader(leaderId, leaderChar, 1, Parties.PAIR_SIZE,
                        { kind = "scavenge", phase = "traveling" })
                end
                if follower.setGroupMembers ~= nil then
                    follower:setGroupMembers({ leaderChar, follower.character })
                end
                follower.baseSupplyParty = supplyParty or nil
                follower.baseSupplyPartyNeeds = supplyParty and supplyNeeds or nil
                follower.baseSupplyPartyInventories = supplyParty
                    and inventories or nil
                existingCount = existingCount + 1
                print("[KnoxSurvivors][Scavenge] pair-out settlement=" .. tostring(key)
                    .. " leader=" .. tostring(leaderId)
                    .. " follower=" .. tostring(followerId))
            end
        end
    end
end

return Parties
