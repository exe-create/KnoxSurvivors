local B = assert(KnoxBaseBarricades, "barricade owner is loaded")
local previousGetCell = getCell

local map = {}
local function key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function list(items)
    return {
        size = function() return #items end,
        get = function(self, index) return items[index + 1] end,
    }
end

local cell = {}
function cell:getGridSquare(x, y, z)
    return map[key(x, y, z)]
end

local function newWorld()
    map = {}
    getCell = function() return cell end
end

local function makeBuilding(id)
    local building = { id = id }
    function building:getDef()
        return { getID = function() return self.id end }
    end
    function building:getSquare()
        return self.anchor
    end
    return building
end

local function makeRoom(id)
    local room = { id = id, squares = {} }
    function room:getSquares()
        return list(self.squares)
    end
    function room:getRoomDef()
        return { getID = function() return self.id end }
    end
    return room
end

local function makeObject(kind, index)
    local object = {
        kind = kind,
        index = index,
        planks = 0,
        canAdd = true,
        open = false,
        modData = {},
    }
    function object:getModData()
        return self.modData
    end
    function object:isDoor()
        return self.kind == "door"
    end
    function object:IsOpen()
        return self.open
    end
    function object:getObjectIndex()
        return self.index
    end
    function object:isBarricadeAllowed()
        return true
    end
    function object:getSprite()
        return nil
    end
    function object:getSquare()
        return self.square
    end
    function object:getBarricadeForCharacter(character)
        if (tonumber(self.planks) or 0) <= 0 then return nil end
        return {
            getNumPlanks = function() return self.planks end,
            canAddPlank = function() return self.canAdd end,
        }
    end
    function object:setPlanks(count, canAdd)
        self.planks = count or 0
        self.canAdd = canAdd ~= false
    end
    return object
end

local function addSquare(x, y, z, room, building, objects)
    objects = objects or {}
    local square = {
        x = x, y = y, z = z,
        room = room,
        building = building,
        objects = list(objects),
    }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return self.room end
    function square:getBuilding() return self.building end
    function square:getObjects() return self.objects end
    for _, object in ipairs(objects) do object.square = square end
    map[key(x, y, z)] = square
    return square
end

local function addFloor(x, y, z, room, building)
    local square = addSquare(x, y, z, room, building, {})
    room.squares[#room.squares + 1] = square
    return square
end

local function makeBase(z)
    return {
        id = "base",
        home = { z = z or 0 },
        territory = { minX = 0, minY = 0, maxX = 6, maxY = 6 },
        tasks = {},
    }
end

-- A room whose wall openings are supplied by the caller. Floors are the room's
-- own native square list; windows and doors sit on adjacent wall squares, so
-- the audit has to walk loaded neighbors rather than infer a floor plan.
local function house(openings)
    newWorld()
    local building = makeBuilding("b1")
    local room = makeRoom("r1")
    local floor = addFloor(1, 1, 0, room, building)
    addFloor(2, 1, 0, room, building)
    addFloor(1, 2, 0, room, building)
    addFloor(2, 2, 0, room, building)
    building.anchor = floor
    local result = { building = building, room = room, base = makeBase(0) }
    for _, spec in ipairs(openings or {}) do
        local object = makeObject(spec.kind, spec.index)
        addSquare(spec.x, spec.y, 0, nil, building, { object })
        result[spec.name] = object
    end
    return result
end

local function windows()
    return {
        { name = "w1", kind = "window", index = 1, x = 1, y = 0 },
        { name = "w2", kind = "window", index = 2, x = 0, y = 1 },
    }
end

local function openingByIndex(stub, index)
    for _, name in ipairs({ "w1", "w2", "door" }) do
        local object = stub[name]
        if object ~= nil and object:getObjectIndex() == index then return object end
    end
    return nil
end

local function withDoor()
    local specs = windows()
    specs[#specs + 1] = { name = "door", kind = "door", index = 3, x = 2, y = 0 }
    return specs
end

-- One window, no door: the only way out is reserved.
local h = house({ windows()[1] })
assert(h.building ~= nil, "fixture building exists")
assert(h.building:getSquare() ~= nil, "fixture building has an anchor square")
assert(h.building:getSquare():getBuilding() ~= nil, "anchor square has a building")
assert(h.building:getSquare():getBuilding():getDef() ~= nil, "anchor building has a definition")
assert(h.building:getSquare():getBuilding():getDef():getID() ~= nil, "definition has an id")
local found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 0 and reason == "only_usable_exit",
    "a one-window room cannot be boarded: " .. tostring(reason))
local single, singleReason = B.findTarget(h.base, nil)
assert(single == nil and singleReason == "only_usable_exit",
    "automatic discovery keeps the same last-exit refusal")

-- Two windows, no door: one may be boarded, then the remaining window is the
-- reserved exit. This is the stale-target case the old building-wide count
-- would have allowed to close.
h = house(windows())
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 1 and reason == "found",
    "a two-window room permits work only up to its reserve")
local boarding = openingByIndex(h, found[1].objectIndex)
assert(boarding ~= nil, "the finder returned a concrete opening")
boarding:setPlanks(2, false)
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 0 and reason == "only_usable_exit",
    "after one window is boarded the last window is reserved: " .. tostring(reason))

-- A window plus a door: the door keeps the route, so the window is work.
h = house(withDoor())
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
local onlyWindows = #found == 2
for _, target in ipairs(found) do
    local opening = openingByIndex(h, target.objectIndex)
    if opening == nil or opening == h.door then onlyWindows = false end
end
assert(onlyWindows and reason == "found",
    "a door keeps the room traversable and is never a barricade target")

-- Two separate rooms with one window each: a building-wide count sees two
-- openings, but each room is independently one window away from being sealed.
newWorld()
local twoBuilding = makeBuilding("b1")
local roomA = makeRoom("ra")
local roomB = makeRoom("rb")
local anchor = addFloor(1, 1, 0, roomA, twoBuilding)
addFloor(1, 2, 0, roomA, twoBuilding)
addFloor(4, 1, 0, roomB, twoBuilding)
addFloor(4, 2, 0, roomB, twoBuilding)
twoBuilding.anchor = anchor
local wa = makeObject("window", 1)
local wb = makeObject("window", 2)
addSquare(1, 0, 0, nil, twoBuilding, { wa })
addSquare(4, 0, 0, nil, twoBuilding, { wb })
local twoBase = makeBase(0)
found, reason = B.findTargetsInBuilding(twoBase, twoBuilding, nil, 24)
assert(#found == 0 and reason == "only_usable_exit",
    "room scope beats a building-wide opening count")

-- A player mark reserves an opening without changing its physical state.
h = house(windows())
assert(B.setKeepOpen(h.w1, true), "keep-open mark is stored on the object")
assert(B.isKeepOpen(h.w1) == true, "keep-open mark reads back")
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
local markedTarget = #found == 1 and openingByIndex(h, found[1].objectIndex) or nil
assert(#found == 1 and markedTarget == h.w2,
    "a marked opening is skipped while an unmarked opening remains available")
assert(B.setKeepOpen(h.w2, true), "second keep-open mark is stored")
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 0 and reason == "keep_open",
    "all-marked room reports the mark, not a false clear path")
assert(B.setKeepOpen(h.w1, false), "keep-open mark can be cleared")
assert(B.isKeepOpen(h.w1) == false, "cleared mark reads false")

-- No usable opening: a partially boarded window is still workable, but the
-- room is already sealed and must report no_way_out rather than accepting it.
h = house(windows())
h.w1:setPlanks(2, false)
h.w2:setPlanks(1, true)
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 0 and reason == "no_way_out",
    "a sealed room reports no_way_out: " .. tostring(reason))

-- A queued job in the room prevents a second simultaneous boarder. After the
-- task is gone, the finder can offer the next safe opening.
h = house(windows())
h.base.tasks = {
    { type = "barricade", state = "queued",
      target = { x = 1, y = 0, z = 0, objectIndex = 1 } },
}
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 0 and reason == "barricade_room_busy",
    "a pending room job serializes barricade work")
h.base.tasks = {}
found, reason = B.findTargetsInBuilding(h.base, h.building, nil, 24)
assert(#found == 1 and reason == "found",
    "the next opening becomes available after the room job clears")

-- Upper-floor windows may be fully boarded and are exempt from the
-- ground-floor exit audit.
newWorld()
local upperBuilding = makeBuilding("b1")
local upperRoom = makeRoom("ru")
local upperFloor = addFloor(1, 1, 1, upperRoom, upperBuilding)
upperBuilding.anchor = upperFloor
local upperWindow = makeObject("window", 1)
addSquare(1, 0, 1, nil, upperBuilding, { upperWindow })
local upperBase = makeBase(0)
found, reason = B.findTargetsInBuilding(upperBase, upperBuilding, nil, 24)
assert(#found == 1 and found[1].objectIndex == upperWindow:getObjectIndex(),
    "an upper-floor window is not a ground-floor exit")
assert(B.findTarget(upperBase, nil) ~= nil,
    "automatic discovery also permits the upper-floor window")

-- A stale target resolved after the room lost its other exit must be refused.
h = house({ windows()[1] })
local stale = { x = 1, y = 0, z = 0, objectIndex = 1, id = "stale" }
local resolved, resolveReason = B.resolveTarget(h.base, stale, nil)
assert(resolved == nil and resolveReason == "only_usable_exit",
    "a stale target cannot board the reserved exit: " .. tostring(resolveReason))

-- The outside face is boarded first. This room has two windows and a door, so
-- the entrance invariant permits both windows; the street-side one must come
-- first even though the scan reaches the interior one first.
newWorld()
local orderBuilding = makeBuilding("b1")
local orderRoom = makeRoom("rorder")
local orderAnchor = addFloor(1, 1, 0, orderRoom, orderBuilding)
addFloor(1, 2, 0, orderRoom, orderBuilding)
orderBuilding.anchor = orderAnchor
local street = addSquare(1, -1, 0, nil, nil, {})
local outer = makeObject("window", 7)
local outerSquare = addSquare(1, 0, 0, nil, orderBuilding, { outer })
local inner = makeObject("window", 8)
local innerSquare = addSquare(0, 1, 0, nil, orderBuilding, { inner })
local orderDoor = makeObject("door", 9)
addSquare(1, 3, 0, nil, orderBuilding, { orderDoor })

assert(B.openingFacesOutside(outerSquare) == true,
    "a window with a loaded street neighbour faces outside")
assert(B.openingFacesOutside(innerSquare) == false,
    "a window whose loaded neighbours all have rooms is interior")
assert(B.openingFacesOutside(nil) == false, "a missing square faces nothing")

local orderBase = makeBase(0)
found, reason = B.findTargetsInBuilding(orderBase, orderBuilding, nil, 24)
assert(#found == 2 and reason == "found",
    "both windows are work while the room keeps a door: " .. tostring(reason))
assert(found[1].objectIndex == outer:getObjectIndex() and found[1].exterior == true,
    "the street-side window is offered first")
assert(found[2].objectIndex == inner:getObjectIndex() and found[2].exterior == false,
    "the interior window follows instead of leading")

-- Truncation must not throw the exterior window away.
local limited = B.findTargetsInBuilding(orderBase, orderBuilding, nil, 1)
assert(#limited == 1 and limited[1].objectIndex == outer:getObjectIndex(),
    "a one-target order keeps the street-side window")

-- The order is a stable sort: equal faces keep the scan order they arrived in.
local kept = B.orderTargets({ { exterior = false, id = "a" },
    { exterior = true, id = "b" }, { exterior = false, id = "c" } }, 10)
assert(kept[1].id == "b" and kept[2].id == "a" and kept[3].id == "c",
    "only the exterior flag reorders the list")
assert(B.orderTargets(nil) == nil, "a missing list is not an order")

print("Entrance outside-first PASS exterior=true flag=true stable=true limit=true")

getCell = previousGetCell
