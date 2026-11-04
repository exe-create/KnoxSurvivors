-- The map overlay reads patrol zones, never a second route record. This drives
-- the real waypoint module and selector; it does not draw a map.
local O = assert(codecPatrolOverlay, "patrol overlay source is loaded")

local routes = O.patrolRoutes({ zones = {
    north = { type = "patrol", minX = 0, minY = 0, maxX = 9, maxY = 9, z = 0,
        name = "North loop" },
    guard = { type = "guard", minX = 20, minY = 20, maxX = 29, maxY = 29, z = 0,
        name = "Guard post" },
    south = { type = "patrol_area", minX = 40, minY = 40, maxX = 49, maxY = 49,
        z = 0, name = "South loop" },
    broken = { type = "patrol", minX = 0, name = "Broken route" },
} })

assert(#routes == 2, "only patrol areas are routes")
local byName = {}
for _, route in ipairs(routes) do byName[route.name] = route end
assert(byName["North loop"] ~= nil, "a patrol zone becomes a route")
assert(byName["South loop"] ~= nil, "a legacy patrol_area also becomes a route")
assert(byName["Guard post"] == nil, "a guard post is not a patrol route")
assert(byName["Broken route"] == nil, "an unreadable zone is skipped")
assert(#byName["North loop"].points == 4, "the real waypoint owner gives four stops")

local empty = O.patrolRoutes(nil)
assert(#empty == 0, "no base draws no route")

local function near(a, b) return math.abs(a - b) < 0.001 end
local tx, ty, lx, ly, rx, ry = O.routeArrow(0, 0, 100, 0, 10)
assert(near(tx, 50) and near(ty, 0), "the arrow points along the segment")
assert(near(lx, 40) and near(ly, 5.5), "the left wing sits behind the tip")
assert(near(rx, 40) and near(ry, -5.5), "the right wing sits behind the tip")
assert(O.routeArrow(0, 0, 0, 0, 10) == nil, "a zero-length segment has no arrow")

local persistence = {
    getBaseResidentIds = function() return { "nora", "eli", "gone" } end,
    getSurvivorIdentity = function(id)
        if id == "nora" then return { forename = "Nora", surname = "Vale" } end
        if id == "eli" then return { forename = "Eli", surname = "Moss" } end
        return nil
    end,
}
local runtime = { getController = function(id)
    if id == "nora" then return { securityRoute = { patrol = true,
        square = { getX = function() return 12 end, getY = function() return 8 end,
            getZ = function() return 0 end }, step = 2, count = 4 } } end
    if id == "eli" then return { securityRoute = { patrol = false,
        square = { x = 1, y = 2, z = 0 } } } end
    return nil
end }
local live = O.livePatrolStops({ id = "base" }, runtime, persistence)
assert(#live == 1, "only an active patrol route has a next stop")
assert(live[1].name == "Nora Vale", "the next stop names the patroller")
assert(live[1].x == 12.5 and live[1].y == 8.5, "the square is centred for the map")
assert(live[1].step == 2 and live[1].count == 4, "the live route keeps its progress")
assert(#O.livePatrolStops({ id = "base" }, runtime, nil) == 0, "no persistence has no stop")

local legend = O.patrolLegendRows(routes, live)
assert(#legend == 2, "a route and a live stop both earn a legend row")
assert(legend[1].kind == "route" and legend[1].label == "Patrol route",
    "the first row names the route")
assert(legend[2].kind == "stop" and legend[2].label == "Next stop",
    "the second row names the live stop")
assert(#O.patrolLegendRows({}, {}) == 0, "nothing drawn means no legend")

print("PatrolOverlay PASS routes=2 stops=4 guard=excluded live=1 legend=2")
