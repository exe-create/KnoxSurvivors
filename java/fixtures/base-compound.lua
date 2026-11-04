local C = KnoxBaseCompound

local home = {minX = 10, minY = 10, width = 12, height = 10, z = 0}
local garage = {minX = 30, minY = 12, width = 6, height = 6, z = 0}
local barn = {minX = 400, minY = 400, width = 8, height = 8, z = 0}

assert(C.contains(home, 10, 10) and C.contains(home, 21, 19), "the home rectangle must contain its own corners")
assert(not C.contains(home, 22, 19), "a square outside the home must not be inside it")

-- A garage across the road is one base; a barn three hundred tiles away is not.
local gap = C.gapBetween(home, garage)
assert(gap == 9, "the garage gap must be measured between rectangles, got " .. tostring(gap))
local reason, measured = C.claimRefusal({{buildingId = "home", area = home}}, {buildingId = "garage", area = garage}, 40)
assert(reason == nil, "a building eight tiles away must be claimable, got " .. tostring(reason))

local far, farGap = C.claimRefusal({{buildingId = "home", area = home}}, {buildingId = "barn", area = barn}, 40)
assert(far == "too_far", "a building across the map must be refused, got " .. tostring(far))
assert(farGap == 381, "the refusal must name the real distance, got " .. tostring(farGap))
assert(string.find(C.refusalText(far, farGap), "outpost", 1, true) ~= nil,
    "a refused claim must point at the outpost instead of failing silently")

local again = C.claimRefusal({{buildingId = "home", area = home}}, {buildingId = "home", area = home}, 40)
assert(again == "already_in_base", "the building already in the base must not be added twice, got " .. tostring(again))

local overlap = C.claimRefusal({{buildingId = "home", area = home}},
    {buildingId = "shed", area = {minX = 12, minY = 12, width = 4, height = 4, z = 0}}, 40)
assert(overlap == "overlaps_establishment", "an overlapping outline must be refused, got " .. tostring(overlap))

-- Rooms: repeated native names become addressable labels.
local numbered = C.numberRooms({
    {native = "bedroom", label = "Bedroom"},
    {native = "kitchen", label = "Kitchen"},
    {native = "bedroom", label = "Bedroom"},
})
assert(numbered[1].name == "Bedroom 1", "the first bedroom must be numbered, got " .. tostring(numbered[1].name))
assert(numbered[3].name == "Bedroom 2", "the second bedroom must be numbered, got " .. tostring(numbered[3].name))
assert(numbered[2].name == "Kitchen 1", "a single room must still carry its label, got " .. tostring(numbered[2].name))

-- An older save with only a home area gains Building 1 without a migration.
local base = {id = "b1", home = home}
local list = C.ensure(base)
assert(#list == 1 and list[1].name == "Building 1", "an existing base must backfill one establishment")
assert(list[1].buildingId == nil, "the backfilled establishment keeps whatever building id the home had")
assert(C.ensure(base) == list and #list == 1, "backfill must be idempotent")

-- Room lookup answers by room, not by coordinates at the call site.
local entry = {id = "b2-building-1", area = home, rooms = {
    {key = "room-0", name = "Bedroom 1", bounds = {minX = 10, minY = 10, width = 4, height = 4, z = 0}},
}}
local stored = {id = "b2", establishments = {entry}}
local found, room = C.roomAt(stored, {getX = function() return 11 end,
    getY = function() return 11 end, getZ = function() return 0 end})
assert(found == entry and room ~= nil and room.name == "Bedroom 1",
    "a square inside a room must resolve to that room's label")

local renamed = C.renameRoom(stored, entry.id, "room-0", "  Kids Room  ")
assert(renamed == true and entry.rooms[1].name == "Kids Room" and entry.rooms[1].custom == true,
    "a player rename must be stored and marked custom")
local empty = C.renameRoom(stored, entry.id, "room-0", "   ")
assert(empty == false, "an empty rename must be refused instead of blanking the label")
-- A square's coordinates resolve to the room the player renamed, and a policy
-- can record that room without holding the square.
local named = C.roomNameAt(stored, 11, 11, 0)
assert(named == "Kids Room", "a coordinate lookup must read the renamed room, got " .. tostring(named))
local identity = C.roomIdentity(stored, 11, 11, 0)
assert(identity ~= nil and identity.roomLabel == "Kids Room" and identity.roomKey == "room-0",
    "a policy identity must carry the room key and its label")
local outside = C.roomNameAt(stored, 100, 100, 0)
assert(outside == nil, "a square outside every building has no room")

-- The surface a player gets: a short list of room names, settable from the
-- room, and refused where there is no room rather than silently ignored.
assert(type(C.ROOM_PRESETS) == "table" and #C.ROOM_PRESETS >= 6,
    "a handful of sensible room names must exist")
assert(C.renameRoomAt(stored, 11, 11, 0, "Office") == true,
    "a rename by coordinate must land")
assert(C.roomNameAt(stored, 11, 11, 0) == "Office", "the renamed room must read back")
assert(C.renameRoomAt(stored, 100, 100, 0, "Office") == false,
    "a square with no room cannot be renamed")

-- A rename must carry the labels already stored on containers in that room,
-- and leave a container in another room alone.
local policy = {key = "k1", roomKey = "room-0", establishmentId = entry.id, roomLabel = "Office"}
local elsewhere = {key = "k2", roomKey = "room-9", establishmentId = entry.id, roomLabel = "Store Room"}
stored.storage = {k1 = policy, k2 = elsewhere}
assert(C.renameRoom(stored, entry.id, "room-0", "Play Room") == true)
assert(policy.roomLabel == "Play Room", "a stored label must follow the rename, got " .. tostring(policy.roomLabel))
assert(elsewhere.roomLabel == "Store Room", "a container in another room must not change")
assert(C.roomNameAt(stored, 11, 11, 0) == "Play Room", "the room itself must read the new name")

print("base compound rules OK")
