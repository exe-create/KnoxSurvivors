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

function Executor.destinationDirective(team, searchStep)
    local destination = type(team) == "table" and team.destination or nil
    if type(destination) ~= "table" or number(destination.x) == nil
        or number(destination.y) == nil then
        return nil, "destination_unavailable"
    end
    -- A saved team carries its search radius on the destination; the team-level
    -- field still wins when a caller sets one explicitly.
    local radius = number(team.searchRadius, number(destination.radius, SEARCH_RADIUS))
    radius = math.max(4, math.min(80, math.floor(radius)))
    local wave=Executor.searchWave(radius,searchStep)
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
        scanX = math.floor(number(destination.x)+wave.dx),
        scanY = math.floor(number(destination.y)+wave.dy),
        scanRadius = wave.radius,
        allowFallback = wave.fallback,
    }, "ready"
end

-- A large area is searched in bounded windows, not one huge square scan per
-- survivor. A full preferred sweep precedes fallback; each new sweep tries the
-- requested cargo first again. Only existing native squares supply evidence.
function Executor.searchWave(radius, step)
    radius=math.max(4,math.min(80,math.floor(number(radius,80))))
    local half=math.ceil(radius/32)
    local side=half*2+1
    local count=side*side
    local index=math.max(0,math.floor(number(step,0)))
    local offset=(index+math.floor(count/2))%count
    local stride=radius/half
    return {dx=(offset%side-half)*stride,dy=(math.floor(offset/side)-half)*stride,
        radius=16,fallback=math.floor(index/count)%2==1,count=count}
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
        local destination=item:getContainer()
        return inventory ~= nil and supply.container ~= destination
            and supply.container:contains(item) == false
            and Executor.ownsContainer(character,destination) and destination:contains(item)==true
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
    local recorded,reason=KnoxPersistence.recordAwayTeamCollection(
        teamId, survivorId, itemTypes, now, final
    )
    if recorded ~= nil and type(supply)=="table" then supply.awayReceiptCommitted=true end
    return recorded,reason
end

-- Resource trips stay assigned through scarcity. Scouting keeps its bounded
-- inspection result; resource runs return on actual storage/carrying limits.
function Executor.runContinues(state)
    if type(state) ~= "table" then return false, "no_state" end
    if state.packFull == true then return false, "pack_full" end
    if state.missionType == "scout" and (tonumber(state.searches) or 0)>=3 then
        return false,"scouted"
    end
    return true, "continue"
end

function Executor.carriedBags(character)
    local bags={}
    if character == nil then return bags end
    local inventory=character:getInventory()
    local items=inventory and inventory:getItems()
    if items == nil then return bags end
    for i=0,items:size()-1 do
        local item=items:get(i)
        if instanceof(item,"InventoryContainer") then
            local bag=item:getInventory()
            if bag then bags[#bags+1]=bag end
        end
    end
    return bags
end

function Executor.ownsContainer(character,container)
    if character == nil or container == nil then return false end
    if character:getInventory()==container then return true end
    for _,bag in ipairs(Executor.carriedBags(character)) do
        if bag==container then return true end
    end
    return false
end

-- Installed ItemContainer.getCapacityWeight is the CURRENT weight, not a
-- capacity. There is no getWeight getter. getMaxWeight supplies the limit.
function Executor.packFull(character)
    if character == nil or character.getInventory == nil then return false end
    local ok, full = pcall(function()
        local inventory = character:getInventory()
        if inventory == nil then return false end
        local function full(container)
            local weight=tonumber(container:getCapacityWeight()) or 0
            local capacity=tonumber(container:getMaxWeight()) or 0
            return capacity>0 and weight/capacity>=0.95
        end
        if full(inventory) then return true end
        local bags=Executor.carriedBags(character)
        if #bags==0 then return false end
        for _,bag in ipairs(bags) do if not full(bag) then return false end end
        return true
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
        .. (collected > 0 and ("; " .. tostring(collected) .. " item(s) collected during the trip") or "")
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
