-- A plot centre is usually inside the house. The approach search picks an edge
-- square the car body actually fits on, using the same tile and pose checks the
-- planner trusts. Stubbed ground keeps this honest: no native session needed to
-- see which square wins.
assert(KnoxVehicleNavigation ~= nil, "routing owner missing")
local nav = KnoxVehicleNavigation
assert(nav.approach ~= nil, "approach search missing")

local function makeCell(blocked, floors)
    local squares = {}
    return {
        -- Called as a method, so self is the first argument.
        getGridSquare = function(self, x, y, z)
            local key = x .. ":" .. y
            local square = squares[key]
            if square == nil then
                local solid = blocked ~= nil and blocked[key] == true
                local sprite = floors ~= nil and floors[key] or nil
                square = {
                    getFloor = function()
                        if sprite == nil then return nil end
                        return { getSpriteName = function() return sprite end }
                    end,
                    canStand = function() return not solid end,
                    isOutside = function() return true end,
                    isSolid = function() return false end,
                    isSolidTrans = function() return false end,
                    HasTree = function() return false end,
                    getMovingObjects = function()
                        return { size = function() return 0 end, get = function() return nil end }
                    end,
                    isBlockedTo = function() return false end,
                }
                squares[key] = square
            end
            return square
        end,
    }
end

local geometry = { halfWidth = 0.4, halfLength = 0.5, centerX = 0, centerZ = 0,
    rearX = 0, rearZ = 0, wheelbase = 2.6, steeringLimit = 0.6, maxCurvature = 0.1 }
local function contextWith(blocked, floors)
    return { geometry = geometry, others = {}, squares = {}, cell = makeCell(blocked, floors) }
end

local plot = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0 }

-- Coming from the west, the west edge is the shortest drive.
local west = nav.approach(contextWith(nil), plot, 0, 0, 15)
assert(west ~= nil and west.x == 10 and west.y == 15,
    "the edge facing the car wins, got " .. tostring(west and west.x) .. "," .. tostring(west and west.y))

-- Blocked west edge: the search walks to the next usable square rather than
-- handing the driver a square it cannot occupy.
local detour = nav.approach(contextWith({ ["10:15"] = true }), plot, 0, 0, 15)
assert(detour ~= nil, "a blocked edge still finds ground")
assert(not (detour.x == 10 and detour.y == 15), "the blocked square is not chosen")
assert(detour.x == 10 and detour.y == 10,
    "the next nearest edge square wins, got " .. tostring(detour.x) .. "," .. tostring(detour.y))

-- Coming from the east mirrors it.
local east = nav.approach(contextWith(nil), plot, 0, 40, 15)
assert(east ~= nil and east.x == 20 and east.y == 15, "the search is not biased to one side")

assert(nav.approach(contextWith(nil), nil, 0, 0, 0) == nil, "no plot is no approach")
assert(nav.approach(nil, plot, 0, 0, 0) == nil, "no map context is no approach")
assert(nav.approach(contextWith(nil), {}, 0, 0, 0) == nil, "a plot without bounds is refused")

-- A tiny plot still offers its own single square.
local small = nav.approach(contextWith(nil), { minX = 5, minY = 5, maxX = 5, maxY = 5 }, 0, 0, 0)
assert(small ~= nil and small.x == 5 and small.y == 5, "a one-tile plot is its own approach")

-- A road-side stop beats a nearer field edge, but only when the ground can be
-- read: unread tiles fall back to the nearest edge so the order still exists.
local plotRoad = nav.approach(contextWith(nil, { ["20:15"] = "street_01_0" }), plot, 0, 40, 8)
assert(plotRoad ~= nil and plotRoad.x == 20 and plotRoad.y == 15,
    "pavement wins over a nearer field edge, got " .. tostring(plotRoad and plotRoad.x)
    .. "," .. tostring(plotRoad and plotRoad.y))
local plotUnread = nav.approach(contextWith(nil, nil), plot, 0, 40, 8)
assert(plotUnread ~= nil and plotUnread.x == 20 and plotUnread.y == 10,
    "unread ground takes the nearest edge, got " .. tostring(plotUnread and plotUnread.x)
    .. "," .. tostring(plotUnread and plotUnread.y))

print("Vehicle approach PASS facing=true detour=true mirrored=true refuse=true road=true")
