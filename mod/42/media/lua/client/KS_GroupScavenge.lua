-- Scavenging pairs for NPC faction bases and camps. On a slow cadence during
-- the day, a settlement with enough idle members sends two of them out as a
-- group: the leader roams/loots with the normal exploration machinery while
-- the follower holds formation, exactly like the player with companions.
-- Pairs dissolve at nightfall or after two hours; members then resume base
-- life through their ordinary recall. Nothing is invented: loot comes from
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
    if controller.baseId ~= nil then
        local base = controller.base
        return base ~= nil and base.ownerKind == "faction"
    end
    return controller.campId ~= nil and controller.camp ~= nil
end

local function idleState(controller)
    return controller.state == "BASE_IDLE" or controller.state == "CAMP_IDLE"
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
    if not alive(persistence, id) or not present(persistence, id)
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
            and duty.baseSupplyOrder == nil
    end
    return duty.mode == nil or duty.mode == "autonomous"
end

local function eligible(controllers, id, persistence)
    local controller = controllers[id]
    if controller == nil or controller.character == nil then
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
    return availableDuty(controller, id, persistence)
end

local function livePair(key, controllers, nowHours)
    local lease = leasesBySettlement[key]
    if type(lease) ~= "table" then
        return nil
    end
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
    if settlementKey(leader) ~= key or settlementKey(follower) ~= key
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
    local leader = controllers[lease.leaderId]
    if leader ~= nil then
        leader.scavengeSortieUntilHours = nil
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
    print("[KnoxSurvivors][Scavenge] dissolved settlement=" .. tostring(key)
        .. " reason=" .. tostring(reason))
end

function Parties.leases()
    return leasesBySettlement
end

function Parties.ownsController(id, controller, controllers)
    local key = controller ~= nil and settlementKey(controller) or nil
    if key == nil or not isDay() then return false end
    local lease = livePair(key, controllers, worldAgeHours())
    return lease ~= nil and (lease.leaderId == id or lease.followerId == id)
end

-- Read-only reservation query for other base-life selectors. A supply run
-- must not elect someone already committed to this generic settlement outing.
function Parties.ownsSurvivor(id)
    if type(id) ~= "string" or id == "" or not isDay() then return false end
    local nowHours = worldAgeHours()
    for _, lease in pairs(leasesBySettlement) do
        if type(lease) == "table"
            and (tonumber(lease.untilHours) or 0) > nowHours
            and (lease.leaderId == id or lease.followerId == id) then
            return true
        end
    end
    return false
end

function Parties.coordinate(controllers, activeIds, ticks)
    local nowHours = worldAgeHours()
    local day = isDay()
    -- Release invalid ownership promptly; expensive candidate selection stays
    -- on its slow cadence. This also covers settlements absent from activeIds.
    for key in pairs(leasesBySettlement) do
        if not day or livePair(key, controllers, nowHours) == nil then
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
        if controller ~= nil and isFactionSettlement(controller) then
            local key = settlementKey(controller)
            if key ~= nil then
                buckets[key] = buckets[key] or {}
                buckets[key][#buckets[key] + 1] = id
            end
        end
    end
    if not day then
        return
    end
    for key, memberIds in pairs(buckets) do
        if leasesBySettlement[key] == nil and #memberIds >= Parties.PAIR_MIN_MEMBERS then
            local candidates = {}
            for _, id in ipairs(memberIds) do
                if eligible(controllers, id, persistence) then
                    candidates[#candidates + 1] = id
                end
            end
            if #candidates >= Parties.PAIR_SIZE then
                local leaderId, followerId = candidates[1], candidates[2]
                local leader = controllers[leaderId]
                local follower = controllers[followerId]
                local leaderChar = leader.character
                leasesBySettlement[key] = {
                    leaderId = leaderId,
                    followerId = followerId,
                    untilHours = nowHours + Parties.PAIR_LEASE_HOURS,
                }
                leader.scavengeSortieUntilHours = nowHours + Parties.PAIR_LEASE_HOURS
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
                print("[KnoxSurvivors][Scavenge] pair-out settlement=" .. tostring(key)
                    .. " leader=" .. tostring(leaderId)
                    .. " follower=" .. tostring(followerId))
            end
        end
    end
end

return Parties
