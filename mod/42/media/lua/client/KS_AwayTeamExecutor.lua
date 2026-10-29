require "KS_Persistence"

local Executor = rawget(_G, "KnoxAwayTeamExecutor") or {}
_G.KnoxAwayTeamExecutor = Executor

local SEARCH_RADIUS = 18

local function number(value, fallback)
    local result = tonumber(value)
    return result ~= nil and result or fallback
end

function Executor.destinationDirective(team)
    local destination = type(team) == "table" and team.destination or nil
    if type(destination) ~= "table" or number(destination.x) == nil
        or number(destination.y) == nil then
        return nil, "destination_unavailable"
    end
    local radius = number(team.searchRadius, SEARCH_RADIUS)
    radius = math.max(4, math.min(40, math.floor(radius)))
    return {
        kind = "loot_area",
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

function Executor.recordCollection(teamId, survivorId, supply, character, now)
    local itemTypes = Executor.transferredItemTypes(supply, character)
    if type(supply) == "table" and (supply.item ~= nil
        or type(supply.items) == "table" and #supply.items > 0) and #itemTypes == 0 then
        return nil, "collection_transfer_not_received"
    end
    return KnoxPersistence.recordAwayTeamCollection(
        teamId, survivorId, itemTypes, now
    )
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

return Executor
