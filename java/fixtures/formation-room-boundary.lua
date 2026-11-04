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
getCell = priorCell
print("Formation boundaries PASS same_room=true no_exterior_slot=true same_floor=true outdoors=true")
