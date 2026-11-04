require "KS_Persistence"

local Executor = rawget(_G, "KnoxAwayTeamExecutor") or {}
_G.KnoxAwayTeamExecutor = Executor

local SEARCH_RADIUS = 18

local function number(value, fallback)
    local result = tonumber(value)
    return result ~= nil and result or fallback
end

-- What each ordered mission looks for. Scout sweeps everything, so it keeps
-- no purpose and the ordinary planner decides. Every other stored type names
-- real cargo the existing loot planner can recognise; an unknown type also
-- keeps no purpose rather than searching for something that does not exist.
local MISSION_PURPOSES = {
    food = "food",
    medicine = "medicine",
    tools = "tools",
    weapons = "weapons",
    building = "building",
}

function Executor.destinationDirective(team)
    local destination = type(team) == "table" and team.destination or nil
    if type(destination) ~= "table" or number(destination.x) == nil
        or number(destination.y) == nil then
        return nil, "destination_unavailable"
    end
    -- A saved team carries its search radius on the destination; the team-level
    -- field still wins when a caller sets one explicitly.
    local radius = number(team.searchRadius, number(destination.radius, SEARCH_RADIUS))
    radius = math.max(4, math.min(40, math.floor(radius)))
    return {
        kind = "loot_area",
        purpose = type(team) == "table" and MISSION_PURPOSES[team.missionType] or nil,
        minX = math.floor(number(destination.x) - radius),
        minY = math.floor(number(destination.y) - radius),
        maxX = math.floor(number(destination.x) + radius),
        maxY = math.floor(number(destination.y) + radius),
        z = math.floor(number(destination.z, 0)),
        awayTeamId = team.id,
        awayMission = true,
    }, "ready"
end

function Executor.beginCollection(teamId, now)
    local team = KnoxPersistence.getAwayTeam(teamId)
    if team == nil then return nil, "unknown_team" end
    if team.state == "awaiting_collection" then
        return KnoxPersistence.beginAwayTeamCollection(teamId, now)
    end
    if team.state == "collecting" then return team, "collecting" end
    return nil, "not_collectible"
end

local function itemReceived(supply, character, item)
    if character == nil or item == nil or supply.container == nil then return false end
    local ok, received = pcall(function()
        local inventory = character:getInventory()
        return inventory ~= nil and supply.container ~= inventory
            and supply.container:contains(item) == false
            and inventory:contains(item) == true and item:getContainer() == inventory
    end)
    return ok and received == true
end

local function itemType(item)
    if item == nil or item.getFullType == nil then return nil end
    local ok, value = pcall(item.getFullType, item)
    return ok and type(value) == "string" and value ~= "" and value or nil
end

-- Read back only real transfers.  A candidate that is still in the source
-- container, or is not present in the survivor inventory, never enters the
-- persistent mission ledger.
function Executor.transferredItemTypes(supply, character)
    local types, seenItems = {}, {}
    if type(supply) ~= "table" then return types end
    local candidates = supply.items
    if type(candidates) ~= "table" and supply.item ~= nil then
        candidates = { { item = supply.item } }
    end
    for _, candidate in ipairs(candidates or {}) do
        local item = type(candidate) == "table" and candidate.item or candidate
        local fullType = itemType(item)
        -- Two real items may share a full type. Deduplicate by object identity
        -- so a mission records every item actually moved, while repeated
        -- references to the same object cannot inflate the result.
        if fullType ~= nil and itemReceived(supply, character, item) and not seenItems[item] then
            seenItems[item] = true
            types[#types + 1] = fullType
        end
    end
    return types
end

function Executor.recordCollection(teamId, survivorId, supply, character, now, final)
    local itemTypes = Executor.transferredItemTypes(supply, character)
    if type(supply) == "table" and (supply.item ~= nil
        or type(supply.items) == "table" and #supply.items > 0) and #itemTypes == 0 then
        return nil, "collection_transfer_not_received"
    end
    return KnoxPersistence.recordAwayTeamCollection(
        teamId, survivorId, itemTypes, now, final
    )
end

-- A supply run does not end because one container was opened. Three searches is
-- the same bound the ordinary loot chain uses, and a full pack is the other
-- real stop; a search area with nothing left ends the run through the existing
-- miss budget instead of a second exhaustion check. Pure, so the decision can
-- be driven offline without a body.
Executor.RUN_SEARCH_LIMIT = 3

function Executor.runContinues(state)
    if type(state) ~= "table" then return false, "no_state" end
    if state.packFull == true then return false, "pack_full" end
    local limit = math.max(1, math.floor(
        tonumber(state.maxSearches) or Executor.RUN_SEARCH_LIMIT
    ))
    -- The caller asks this after a search finished, so an unknown count is one
    -- completed search rather than zero: bad input can never buy extra searches.
    local searches = math.max(1, math.floor(tonumber(state.searches) or 1))
    if searches >= limit then return false, "search_budget" end
    return true, "continue"
end

-- Real carried weight against real native capacity, never a guess. An
-- unreadable inventory is not "full": the run continues and the search bounds
-- still end it.
function Executor.packFull(character)
    if character == nil or character.getInventory == nil then return false end
    local ok, full = pcall(function()
        local inventory = character:getInventory()
        if inventory == nil or inventory.getWeight == nil
            or inventory.getCapacityWeight == nil then return false end
        local weight = tonumber(inventory:getWeight()) or 0
        local capacity = tonumber(inventory:getCapacityWeight()) or 0
        return capacity > 0 and weight / capacity >= 0.95
    end)
    return ok and full == true
end

function Executor.collectionReady(teamId)
    return KnoxPersistence.awayTeamCollectionReady(teamId)
end

function Executor.beginReturn(teamId, now)
    return KnoxPersistence.beginAwayTeamReturn(teamId, now)
end

function Executor.returnDestination(teamId)
    return KnoxPersistence.getAwayTeamReturnDestination(teamId)
end

local MISSION_LABELS = {
    scout = "Scouting",
    food = "Food run",
    medicine = "Medical run",
    weapons = "Weapons run",
    tools = "Tools run",
    building = "Building run",
}

local function displayName(id)
    local identity = KnoxPersistence.getSurvivorIdentity ~= nil
        and KnoxPersistence.getSurvivorIdentity(id) or nil
    if type(identity) == "table" then
        local name = (tostring(identity.forename or "")
            .. " " .. tostring(identity.surname or ""))
            :gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then return name end
    end
    return tostring(id)
end

-- Names come from the durable identity, never from a currently loaded body:
-- a returned mission must describe the same person while off-screen.
function Executor.memberLabel(team)
    local names = {}
    for _, id in ipairs(type(team) == "table" and team.memberIds or {}) do
        names[#names + 1] = displayName(id)
    end
    if #names == 0 then return "No one" end
    if #names <= 2 then return table.concat(names, " and ") end
    return names[1] .. " and " .. tostring(#names - 1) .. " others"
end

function Executor.missionLabel(team)
    local mission = type(team) == "table" and team.missionType or nil
    return MISSION_LABELS[mission] or "Mission"
end

local function collectedCount(team)
    if type(team) ~= "table" or type(team.collection) ~= "table" then return 0 end
    local resources = team.collection.resources
    if type(resources) ~= "table" then return 0 end
    local total = 0
    for _, count in pairs(resources) do
        total = total + math.max(0, math.floor(tonumber(count) or 0))
    end
    return total
end

-- One-line player-facing outcome. Reads only the persisted team, so a blocked
-- trip is never described as a success merely because some items were found.
function Executor.resultSummary(team)
    if type(team) ~= "table" then return nil end
    local place = type(team.destination) == "table"
        and tostring(team.destination.label or "the destination") or "the destination"
    local label = Executor.missionLabel(team)
    local who = Executor.memberLabel(team)
    if team.state == "blocked" then
        local reason = type(team.result) == "table" and team.result.reason or nil
        return label .. ": " .. who .. " could not complete the trip to " .. place
            .. (reason ~= nil and (" (" .. tostring(reason):gsub("_", " ") .. ")") or "")
            .. "."
    end
    local collected = collectedCount(team)
    local outcome = team.missionType == "scout" and "scouted" or "searched"
    return label .. ": " .. who .. " " .. outcome .. " " .. place
        .. (collected > 0 and (" and brought back " .. tostring(collected) .. " item(s)") or "")
        .. "."
end

-- Completed and blocked player missions, reported at most once each. The
-- durable marker is written through the persistence owner; the read-only team
-- copies must never be used to assume a notice was delivered.
function Executor.takePlayerNotices(ownerId, worldAgeHours, limit)
    if type(ownerId) ~= "string" or KnoxPersistence.getAwayTeams == nil then
        return {}
    end
    local finished = {}
    for id, team in pairs(KnoxPersistence.getAwayTeams() or {}) do
        if type(team) == "table" and team.ownerKind == "player"
            and team.ownerId == ownerId and type(team.result) == "table"
            and (team.state == "complete" or team.state == "blocked")
            and team.resultSeenAtHours == nil then
            finished[#finished + 1] = {
                id = id,
                team = team,
                atHours = tonumber(team.completedAtHours or team.blockedAtHours) or 0,
            }
        end
    end
    table.sort(finished, function(first, second)
        if first.atHours ~= second.atHours then
            return first.atHours < second.atHours
        end
        return tostring(first.id) < tostring(second.id)
    end)
    local notices = {}
    local maximum = math.max(0, math.floor(tonumber(limit) or 3))
    for _, entry in ipairs(finished) do
        if #notices >= maximum then break end
        local marked = KnoxPersistence.markAwayTeamResultSeen ~= nil
            and KnoxPersistence.markAwayTeamResultSeen(entry.id, worldAgeHours)
        if marked then
            local summary = Executor.resultSummary(entry.team)
            if summary ~= nil then notices[#notices + 1] = summary end
        end
    end
    return notices
end

return Executor
