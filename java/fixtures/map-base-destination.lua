-- A base's centre is map geometry, so it is testable without a session: given
-- the same area shapes KS_BaseManager stores, the order must find one point.
local orders = rawget(_G, "KnoxMapOrders")
assert(orders ~= nil, "map orders owner missing")
assert(orders.areaCentre ~= nil, "base centre missing")

assert(orders.areaCentre(nil) == nil, "no area is no destination")
assert(orders.areaCentre({}) == nil, "an area without corners is no destination")

local corners = orders.areaCentre({ minX = 10, minY = 20, maxX = 30, maxY = 40, z = 1 })
assert(corners ~= nil and corners.x == 20 and corners.y == 30 and corners.z == 1,
    "corner bounds give the middle of the plot")

local sized = orders.areaCentre({ x = 10, y = 20, width = 11, height = 21 })
assert(sized ~= nil and sized.x == 15 and sized.y == 30 and sized.z == 0,
    "a width/height area is measured from its first square")

local point = orders.areaCentre({ x = 10, y = 20 })
assert(point ~= nil and point.x == 10 and point.y == 20, "a point area is its own centre")

local anchor = orders.areaCentre({ minX = 10, minY = 20, w = 1, h = 1, z = 2 })
assert(anchor ~= nil and anchor.x == 10 and anchor.y == 20 and anchor.z == 2,
    "a one-tile plot is not rounded away from itself")

-- One base, one owner: the destination follows the player's own record and
-- refuses when there is none, rather than guessing at the nearest building.
local savedManager, savedPersistence = rawget(_G, "KnoxBaseManager"), rawget(_G, "KnoxPersistence")
local player = {}
KnoxPersistence = { ensurePlayerId = function() return "player-1" end }
KnoxBaseManager = { getForOwner = function(kind, ownerId)
    if kind ~= "player" or ownerId ~= "player-1" then return nil end
    return { home = { minX = 100, minY = 200, maxX = 120, maxY = 220, z = 0 } }
end }
local home = orders.baseDestination(player)
assert(home ~= nil and home.x == 110 and home.y == 210, "the base is the destination")

KnoxBaseManager = { getForOwner = function() return nil end }
assert(orders.baseDestination(player) == nil, "no base means no home order")
assert(orders.baseDestination(nil) == nil, "no player means no home order")

KnoxPersistence = { ensurePlayerId = function() return nil end }
assert(orders.baseDestination(player) == nil, "an unowned player has no base")

KnoxBaseManager = { getForOwner = function() error("base record damaged") end }
KnoxPersistence = { ensurePlayerId = function() return "player-1" end }
assert(orders.baseDestination(player) == nil, "a broken base record refuses instead of raising")

KnoxBaseManager, KnoxPersistence = savedManager, savedPersistence
print("Map base destination PASS corners=true size=true point=true one=true refuse=true")
