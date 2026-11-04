-- The alarm used to fire only when a resident started a fight, so a raid could
-- work an empty room in silence. The home can now raise it from a sighting, and
-- the only new judgement is whether the body somebody can see is a raider the
-- record already names, standing inside the home's own walls. The set comes
-- from the raid owner; the rectangle comes from the base owner.
local E = assert(KnoxEvents, "raid event owner is loaded")
local inside = assert(E.raidIntruderInside, "the home can tell whether a body is inside its walls")
local intruders = assert(E.raidIntrudersForBase, "the set of raiders at this home")

local persistence = KnoxPersistence
local saved = { getKnoxEventState = persistence.getKnoxEventState }
local state = { records = {}, cooldowns = {}, automatic = {} }
persistence.getKnoxEventState = function() return state end
state.records["raid-7"] = {
    id = "raid-7", kind = "faction_raid", phase = "objective", revision = 1,
    targetBaseId = "base-home", sourceBaseId = "base-north",
    sourceFactionId = "faction-north", targetFactionId = "player-faction",
    memberIds = { "a", "b" }, dueAtHours = 10, deadlineHours = 40,
}

local set = intruders("base-home", 12)
local bounds = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0 }

-- WHO THE HOME CAN SEE. A named member, inside the rectangle, on this floor.
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 0 }, bounds) == true,
    "a named raider inside the walls is visible to the home")
assert(inside(set, { survivorId = "a", x = 10, y = 20, z = 0 }, bounds) == true,
    "the far corner is still inside")
assert(inside(set, { survivorId = "b", x = 12, y = 12, z = 0 }, bounds) == true,
    "any member of the raid counts, not just the first")

-- WHO IT CANNOT SEE.
assert(inside(set, { survivorId = "a", x = 9, y = 15, z = 0 }, bounds) == false,
    "one tile outside the walls is outside, whatever the record says")
assert(inside(set, { survivorId = "a", x = 15, y = 21, z = 0 }, bounds) == false,
    "the rectangle ends where the base says it ends")
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 1 }, bounds) == false,
    "a raider upstairs is not standing in this room")
assert(inside(set, { survivorId = "q", x = 15, y = 15, z = 0 }, bounds) == false,
    "a stranger inside the walls is not a raider")

-- TERRITORY SHAPES THE BASE OWNER ALREADY STORES.
local sized = { minX = 10, minY = 10, width = 11, height = 11, z = 0 }
assert(inside(set, { survivorId = "a", x = 20, y = 20, z = 0 }, sized) == true,
    "a width/height rectangle is honoured")
assert(inside(set, { survivorId = "a", x = 21, y = 20, z = 0 }, sized) == false,
    "a width/height rectangle ends on its last tile")
local allFloors = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0, allFloors = true }
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 1 }, allFloors) == true,
    "an all-floors territory counts every floor")

-- REFUSALS. No guessed walls, no guessed bodies, no guessed position.
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 0 }, nil) == false,
    "no walls, no sighting")
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 0 }, { minX = 20, minY = 10, maxX = 10 }) == false,
    "an inverted rectangle is not a wall")
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 0 }, { minX = 10, minY = 10 }) == false,
    "minX/minY alone cannot make a rectangle from nothing")
assert(inside(set, { survivorId = "a", x = 15, y = 15, z = 0 }, {}) == false,
    "empty bounds are not a wall")
assert(inside(nil, { survivorId = "a", x = 15, y = 15, z = 0 }, bounds) == false,
    "no intruder set, no sighting")
assert(inside(set, nil, bounds) == false, "no body, no sighting")
assert(inside(set, { x = 15, y = 15, z = 0 }, bounds) == false,
    "an unnamed body is not a raider")
assert(inside(set, { survivorId = 7, x = 15, y = 15, z = 0 }, bounds) == false,
    "a non-string id is not a member")
assert(inside(set, { survivorId = "a", x = 15 }, bounds) == false,
    "half a coordinate is not a position")
assert(inside(set, { survivorId = "a", x = "15", y = "15", z = 0 }, bounds) == true,
    "numeric strings still compare as positions")

-- THE SET FOLLOWS THE RAID. A finished raid leaves nobody to see, even if the
-- body is still standing in the room.
state.records["raid-7"].phase = "completed"
assert(inside(intruders("base-home", 12), { survivorId = "a", x = 15, y = 15, z = 0 }, bounds) == false,
    "a finished raid has nobody inside the walls")
state.records["raid-7"].phase = "objective"

persistence.getKnoxEventState = saved.getKnoxEventState
assert(persistence.getKnoxEventState == saved.getKnoxEventState, "persistence reads are restored")
