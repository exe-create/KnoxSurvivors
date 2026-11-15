local C = KnoxAutonomyController
local room, otherRoom, building = {}, {}, {}
local function square(r, b, z)
    return {getRoom = function() return r end, getBuilding = function() return b end,
        getZ = function() return z or 0 end}
end
local anchor = square(room, building)
assert(C.formationSharesInterior(anchor, square(room, building)))
assert(not C.formationSharesInterior(anchor, square(nil, nil)), "formation must not pull indoors follower outside")
assert(not C.formationSharesInterior(anchor, square(otherRoom, building)), "room wall invalidates rigid slot")
assert(not C.formationSharesInterior(anchor, square(room, building, 1)), "formation cannot skip floor connection")
assert(C.formationSharesInterior(square(nil, nil), square(nil, nil)), "outdoor spacing remains available")
assert(not C.formationSharesInterior(square(nil, nil), anchor), "outdoor formation must not route into a house")
local priorCell = getCell
local function tile(x, y, inside)
    local result = square(inside and room or nil, inside and building or nil)
    result.getX = function() return x end
    result.getY = function() return y end
    result.canStand = function() return true end
    result.TreatAsSolidFloor = function() return true end
    result.isSolid = function() return false end
    result.isSolidTrans = function() return false end
    result.isBlockedTo = function() return false end
    result.getMovingObjects = function() return {size = function() return 0 end} end
    return result
end
local anchorTile = tile(10, 10, true)
getCell = function() return { getGridSquare = function(_, x, y)
    return tile(x, y, x == 10 and y == 9)
end } end
local leader = { getCurrentSquare = function() return anchorTile end,
    getForwardDirectionX = function() return 0 end, getForwardDirectionY = function() return 1 end }
local follower = setmetatable({ id = "formation-boundary-test", companionFormationSlot = 1,
    companionPartySize = 1, character = {getCurrentSquare = function() return anchorTile end} }, C)
local target, compressed = follower:findPlayerPartyFormationTarget(leader, anchorTile)
assert(target ~= nil and target:getRoom() == room and compressed,
    "actual target selector must replace exterior ideal slot with a compressed indoor slot")
assert(follower.playerFormationTargetSquare == target, "compressed slot uses existing shared reservations")

-- Native canStand permits solid-trans furniture next to windows and fences.
-- That supports traversal, but does not make it a final formation slot.
local tiles = {}
getCell = function() return {getGridSquare = function(_, x, y)
    local key = tostring(x) .. ":" .. tostring(y)
    if tiles[key] == nil then tiles[key] = tile(x, y, true) end
    return tiles[key]
end} end
local ideal = getCell():getGridSquare(11, 9)
ideal.isSolidTrans = function() return true end
follower:releasePlayerFormationTarget()
target, compressed = follower:findPlayerPartyFormationTarget(leader, anchorTile)
assert(target ~= nil and target ~= ideal and compressed,
    "a window-adjacent furniture square is replaced by a clear formation slot")
ideal.isSolidTrans = function() return false end
ideal.TreatAsSolidFloor = function() return false end
follower:releasePlayerFormationTarget()
target = follower:findPlayerPartyFormationTarget(leader, anchorTile)
assert(target ~= nil and target ~= ideal, "a missing floor cannot become a formation destination")
ideal.TreatAsSolidFloor = function() return true end
ideal.isSolid = function() return true end
follower:releasePlayerFormationTarget()
target = follower:findPlayerPartyFormationTarget(leader, anchorTile)
assert(target ~= nil and target ~= ideal, "solid furniture cannot become a formation destination")
ideal.isSolid = function() error("square unloaded") end
follower:releasePlayerFormationTarget()
target = follower:findPlayerPartyFormationTarget(leader, anchorTile)
assert(target ~= nil and target ~= ideal, "unreadable furniture cannot establish a safe destination")
ideal.isSolid = function() return false end

local priorFinder = AdjacentFreeTileFinder
local fallback = getCell():getGridSquare(10, 9)
AdjacentFreeTileFinder = {Find = function() return fallback end}
local requested
local group = setmetatable({id = "formation-group-safety", groupLeader = leader,
    groupFormationSlot = 1, character = follower.character, nextThink = 0,
    bridge = {moveNpcWithPace = function(_, _, destination)
        requested = destination
        return "MOVE_STARTED"
    end}}, C)
group.beginPreferredGroupEntry = function() return false end
ideal.isSolidTrans = function() return true end
assert(group:beginGroupFollow(100) and requested == fallback,
    "group follow replaces window-adjacent furniture with its existing clear fallback")
fallback.isSolidTrans = function() return true end
requested = nil
assert(not group:beginGroupFollow(101) and requested == nil,
    "group follow refuses when its fallback is also furniture")
fallback.isSolidTrans = function() return false end
ideal.isSolidTrans = function() return false end
local otherBody = {}
ideal.getMovingObjects = function()
    return {size = function() return 1 end, get = function() return otherBody end}
end
assert(group:beginGroupFollow(102) and requested == fallback,
    "group follow avoids a destination occupied by another body")
ideal.getMovingObjects = function()
    return {size = function() return 1 end, get = function() return group.character end}
end
assert(group:beginGroupFollow(103) and requested == ideal,
    "the follower's own standing square remains available")
AdjacentFreeTileFinder = priorFinder
getCell = priorCell
print("Formation boundaries PASS same_room=true no_exterior_slot=true same_floor=true outdoors=true")
