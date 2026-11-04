-- A fallback square is only a fallback if a body can walk to it. A straight
-- line says no the moment a wall is in it, even when the room continues around
-- that wall, so the base owns a reach test over its own territory and the
-- screen measures the walk it produces against the fight. Both are pure and
-- both are driven here from a drawn floor plan.
local R = assert(codecBaseReach, "the base owner is extracted")
local reach = assert(R.rallyReach, "the base can walk its own rooms")
local A = assert(codecRallyAdmission, "the rally screen is extracted")
local clearance = assert(A.rallyPathClearance, "a walk is measured against the fight")
local CONTACT2 = A.RALLY_CONTACT2
assert(type(CONTACT2) == "number", "the contact bound is a number")

-- Rows of a floor plan; '#' is a wall, '.' is floor, 'D' is a doorway.
local function floorPlan(rows)
    local grid, height, width = {}, #rows, 0
    for index = 1, #rows do
        local row = rows[index]
        width = math.max(width, #row)
        for column = 1, #row do
            grid[(index - 1) * 100 + (column - 1)] = row:sub(column, column)
        end
    end
    local bounds = { minX = 0, minY = 0, maxX = width - 1, maxY = height - 1, z = 0 }
    local function passable(_, _, toX, toY)
        local cell = grid[toY * 100 + toX]
        return cell == "." or cell == "D"
    end
    return grid, bounds, passable
end

-- Two rooms joined by one doorway. The direct line between them crosses a wall.
local grid, bounds, passable = floorPlan({
    "#######",
    "#..#..#",
    "#..D..#",
    "#######",
})
assert(grid[1 * 100 + 3] == "#", "the fixture really has a wall on the direct line")
local route = assert(reach(bounds, { x = 1, y = 1 }, { x = 5, y = 1 }, passable),
    "a room around a wall is still reachable")
assert(route.steps == 6, "the walk is the real cardinal distance through the door")
assert(#route.path == route.steps + 1, "the path is one point per step")
assert(route.path[1].x == 1 and route.path[1].y == 1, "the path starts where the body stands")
assert(route.path[#route.path].x == 5 and route.path[#route.path].y == 1,
    "the path ends on the rally corner")
local throughDoor = false
for index = 2, #route.path do
    local previous, current = route.path[index - 1], route.path[index]
    local dx, dy = current.x - previous.x, current.y - previous.y
    assert(math.abs(dx) + math.abs(dy) == 1,
        "every step is one tile on one axis, never a diagonal squeeze")
    if current.x == 3 and current.y == 2 then throughDoor = true end
end
assert(throughDoor, "the walk goes through the doorway instead of the wall")

-- A windowless room is not a fallback.
local _, sealedBounds, sealedPassable = floorPlan({
    "#####",
    "#.#.#",
    "#####",
})
local none, why = reach(sealedBounds, { x = 1, y = 1 }, { x = 3, y = 1 }, sealedPassable)
assert(none == nil and why == "unreachable",
    "a sealed room refuses instead of pretending the wall is a door")

-- BUDGETS, BOUNDS AND REFUSALS.
local shortNone, shortWhy = reach(bounds, { x = 1, y = 1 }, { x = 5, y = 1 },
    passable, { maxSteps = 2 })
assert(shortNone == nil and shortWhy == "too_far",
    "a walk longer than the caller's budget says why, not that the wall is solid")
assert(reach(bounds, { x = 1, y = 1 }, { x = 1, y = 1 }, passable).steps == 0,
    "a body already on the square takes no step")
assert(reach(bounds, { x = 1, y = 1 }, { x = 1, y = 1 }, passable).path[1].x == 1,
    "a zero-step walk still has a path")
assert(reach(bounds, { x = 1, y = 1 }, { x = 9, y = 1 }, passable) == nil,
    "a corner outside the territory is not a walk inside it")
assert(reach(nil, { x = 1, y = 1 }, { x = 1, y = 1 }, passable) == nil,
    "no walls, no walk")
assert(reach(bounds, { x = 1, y = 1 }, { x = 1, y = 1 }, nil) == nil,
    "no passability test, no walk")
assert(reach(bounds, nil, { x = 1, y = 1 }, passable) == nil,
    "no start, no walk")
assert(reach(bounds, { x = 1, y = 1 }, { x = 1 }, passable) == nil,
    "half a square is not a destination")
assert(reach(bounds, { x = "1", y = "1" }, { x = "5", y = "1" }, passable).steps == 6,
    "numeric strings still walk")

-- THE WALK IS MEASURED AGAINST THE FIGHT.
local nearest = assert(clearance(route.path, { { x = 0, y = 3 } }),
    "a raider away from the walk does not forbid it")
assert(nearest == 5, "the nearest point on the walk is a real squared distance")
assert(clearance(route.path, { { x = 0, y = 0 } }) == nil,
    "a raider one tile off the first step is too close, not merely far")
assert(clearance(route.path, { { x = 2, y = 1 } }) == nil,
    "a raider standing on the walk is refused, not skipped")
assert(clearance(route.path, { { x = 2, y = 1 } }, { contact2 = 0 }) == 0,
    "an allowed tile still reports the true distance")
local blocked, blockedWhy = clearance(route.path, { { x = 2, y = 2 } })
assert(blocked == nil and blockedWhy == "through_threat",
    "a walk past the intruder's tile is refused")
assert(clearance(route.path, { { x = 50, y = 50 } }) ~= nil,
    "a distant raider leaves the walk clear")
assert(clearance(route.path, {}) == nil, "no threats is not a clear walk")
local _, emptyWhy = clearance(route.path, {})
assert(emptyWhy == "no_threat", "an empty threat list says so instead of claiming safety")
assert(clearance({}, { { x = 0, y = 0 } }) == nil, "no walk has no clearance")
assert(clearance(route.path, { { x = 2, y = 2 } }, { contact2 = 4 }) == nil,
    "a caller can widen the contact bound")
assert(clearance(route.path, { { x = 2, y = 2 } }, { contact2 = 0 }) == 0,
    "a caller can allow walking over the tile, and the distance is still reported")
assert(clearance({ { x = "1", y = "1" } }, { { x = "3", y = "1" } }) == 4,
    "numeric strings still compare as coordinates")
