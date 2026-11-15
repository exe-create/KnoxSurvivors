local B = assert(codecBaseLayout, "base layout source is loaded")
local Persistence = assert(KnoxPersistence, "persistence is loaded")

local previousCell = getCell
local previousInstanceof = instanceof

local map = {}
local function key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function list(items)
    return {
        size = function() return #items end,
        get = function(_, index) return items[index + 1] end,
    }
end

local cell = {}
function cell:getGridSquare(x, y, z)
    return map[key(x, y, z)]
end
getCell = function() return cell end

local building = { id = "layout-building" }
local function makeRect(x, y, w, h)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getW = function() return w end,
        getH = function() return h end,
    }
end

local function makeRoom(name, x, y, w, h, z)
    local room = { name = name, x = x, y = y, w = w, h = h, z = z or 0 }
    function room:getName() return self.name end
    function room:getZ() return self.z end
    function room:getRects() return list({ makeRect(self.x, self.y, self.w, self.h) }) end
    return room
end

local function addSquare(x, y, z, room, objects)
    local square = { x = x, y = y, z = z, room = room, objects = list(objects or {}) }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return self.room end
    function square:getBuilding() return building end
    function square:getObjects() return self.objects end
    function square:canStand() return self.room == nil end
    map[key(x, y, z)] = square
    return square
end

local function addRoomSquares(room)
    for x = room.x, room.x + room.w - 1 do
        for y = room.y, room.y + room.h - 1 do
            addSquare(x, y, room.z, room, {})
        end
    end
end

local function makeCrate()
    local container = { kind = "crate" }
    function container:getType() return self.kind end
    function container:isExistYet() return true end
    local object = { containers = { container }, modData = {} }
    function object:getContainerCount() return #self.containers end
    function object:getContainerByIndex(index) return self.containers[index + 1] end
    function object:getSquare() return self.square end
    function object:getObjectIndex() return 0 end
    function object:getModData() return self.modData end
    function object:transmitModData() end
    return object
end

local kitchen = makeRoom("Kitchen", 100, 100, 3, 3)
local garage = makeRoom("Garage", 104, 100, 3, 3)
local office = makeRoom("Office", 107, 100, 2, 2)
local bedroom = makeRoom("Bedroom", 100, 104, 3, 3)
addRoomSquares(kitchen)
addRoomSquares(garage)
addRoomSquares(office)
addRoomSquares(bedroom)
-- An unknown non-residential room with a real container is the storage
-- fallback. The bedroom would be larger, so a general entry at the office
-- proves that the skip rule wins.
local officeCrate = makeCrate()
local officeSquare = addSquare(107, 100, 0, office, { officeCrate })
officeCrate.square = officeSquare

local door = { door = true }
addSquare(105, 105, 0, nil, { door })
addSquare(105, 106, 0, nil, {})
instanceof = function(object, class)
    return class == "IsoDoor" and object ~= nil and object.door == true
end

function building:getDef()
    return { getID = function() return self.id end }
end
function building:getRooms()
    return list({ kitchen, garage, office, bedroom })
end

local base, created = Persistence.createBase(
    "player", "base-layout-player",
    { minX = 100, minY = 100, width = 10, height = 10, z = 0,
        buildingId = "layout-building" },
    40
)
assert(base ~= nil and created == "created", "layout fixture base was created")
-- The claimed yard is larger than the home footprint; the tree is
-- outside the building but inside the territory.
base.territory = { minX = 100, minY = 100, maxX = 115, maxY = 115, z = 0 }
local treeSquare = addSquare(111, 110, 0, nil, {})
function treeSquare:HasTree() return true end
function treeSquare:getTree() return { tree = true } end

local previousStorage = rawget(_G, "KnoxBaseStorage")
local previousCupboard = rawget(_G, "KnoxToolCupboard")
_G.KnoxBaseStorage = {
    policies = function() end,
    syncContainerName = function() end,
    label = function(policy) return policy and policy.category or "Storage" end,
}
_G.KnoxToolCupboard = {
    isDryContainerType = function() return true end,
    applyInfinite = function() return true end,
}

local entries, reason = B.proposeLayout(base.id, building, 0)
assert(reason == "proposed", "the readable home building produces a proposal")
assert(#entries == 6, "cooking, repair, storage, woodcutting, log processing and guard are proposed")
assert(#(entries.storage or {}) == 1, "the office container adds one general storage assignment")

local byType = {}
for _, entry in ipairs(entries) do byType[entry.zoneType] = entry end
assert(byType.cooking ~= nil and byType.cooking.bounds.x1 == 100
    and byType.cooking.bounds.x2 == 102, "kitchen room becomes a cooking area")
assert(byType.repair ~= nil and byType.repair.bounds.x1 == 104,
    "garage room becomes a repair area")
assert(byType.general ~= nil and byType.general.bounds.x1 == 107,
    "unknown office with a container becomes storage, not the bedroom")
assert(byType.guard ~= nil and byType.guard.bounds.x1 == 105
    and byType.guard.bounds.y1 == 106,
    "the exterior side of a real door becomes an entry watch post")
assert(byType.woodcutting ~= nil and byType.woodcutting.bounds.x1 == 110
    and byType.woodcutting.bounds.y1 == 109
    and byType.woodcutting.bounds.x2 == 112 and byType.woodcutting.bounds.y2 == 111,
    "the real yard tree backs a three-by-three wood lot in territory")
assert(byType.log_processing ~= nil and byType.log_processing.bounds.x1 == 113
    and byType.log_processing.bounds.y1 == 109
    and byType.log_processing.bounds.x2 == 115 and byType.log_processing.bounds.y2 == 111,
    "log processing sits next to the wood lot without overlap")

local refused, why = B.applyLayout(base.id, entries, "someone-else")
assert(refused == nil and why == "not_your_base",
    "another player cannot apply a layout to this base")
local refusedZones = 0
for _ in pairs(base.zones) do refusedZones = refusedZones + 1 end
assert(refusedZones == 0, "a refused apply creates no zones")

local applied = assert(B.applyLayout(base.id, entries, "base-layout-player"),
    "the owner can apply the proposal")
assert(applied.added == 6 and #applied.skipped == 0,
    "apply creates six ordinary zones")
assert(applied.assigned == 1 and #applied.storageSkipped == 0,
    "apply also assigns the office container to general storage")
local stored = 0
for _, policy in pairs(base.storage or {}) do
    assert(policy.category == "general", "the office container keeps the general category")
    stored = stored + 1
end
assert(stored == 1, "one storage policy is written")
local zoneTypes = {}
for _, zone in pairs(base.zones) do zoneTypes[zone.type] = true end
assert(zoneTypes.cooking and zoneTypes.repair and zoneTypes.general
    and zoneTypes.woodcutting and zoneTypes.log_processing and zoneTypes.guard,
    "the applied zones preserve the proposed types")

local again = assert(B.applyLayout(base.id, entries, "base-layout-player"),
    "re-applying the same proposal is a no-op, not a failure")
assert(again.added == 0 and #again.skipped == 6,
    "re-apply refuses every already-covered type")
assert(again.assigned == 0 and #again.storageSkipped == 1,
    "re-apply refuses the already-assigned storage category")
local zoneCount = 0
for _ in pairs(base.zones) do zoneCount = zoneCount + 1 end
assert(zoneCount == 6, "re-apply creates no duplicate zone")

local empty, emptyReason = B.proposeLayout(base.id, building, 0)
assert(#empty == 0 and emptyReason == "no_new_rooms",
    "a fully covered base proposes nothing")

local wrong, wrongReason = B.proposeLayout(base.id, {
    getDef = function() return { getID = function() return "other-building" end } end,
    getRooms = function() return list({}) end,
}, 0)
assert(#wrong == 0 and wrongReason == "not_home_building",
    "a different building cannot be proposed for this base")

local unreadable, unreadableReason = B.proposeLayout(base.id, {
    getDef = function() return { getID = function() return "layout-building" end } end,
    getRooms = function() return nil end,
}, 0)
assert(#unreadable == 0 and unreadableReason == "no_rooms",
    "an unreadable room list is refused with a named reason")

local noEntries, noEntriesReason = B.applyLayout(base.id, {}, "base-layout-player")
assert(noEntries == nil and noEntriesReason == "no_entries",
    "an empty apply is refused rather than reported as success")

local savedZones,savedStorage=base.zones,base.storage
base.zones,base.storage={},{}
local starter=assert(B.applyStarterLayout(base.id,building,0,"base-layout-player"))
assert(starter.added==4 and starter.assigned==0,
    "the starter applies work areas and files no storage for the player")
local starterStorage=0
for _ in pairs(base.storage or {}) do starterStorage=starterStorage+1 end
assert(starterStorage==0,
    "containers stay the player's to assign; no automatic policy is written")
for _,zone in pairs(base.zones) do
    assert(zone.type~="woodcutting" and zone.type~="log_processing","starter does not start destructive tree work")
end
local repeatStarter=B.applyStarterLayout(base.id,building,0,"base-layout-player")
assert(repeatStarter.added==0 and repeatStarter.assigned==0,"starter cannot duplicate existing assignments")
base.zones,base.storage={},{}
local deniedStarter=B.applyStarterLayout(base.id,building,0,"someone-else")
local deniedZones=0
for _ in pairs(base.zones) do deniedZones=deniedZones+1 end
assert(deniedStarter.reason=="not_your_base" and deniedZones==0,"starter retains ownership checks")
base.zones,base.storage=savedZones,savedStorage

_G.KnoxBaseStorage = previousStorage
_G.KnoxToolCupboard = previousCupboard
getCell = previousCell
instanceof = previousInstanceof

print("Base layout proposal PASS rooms=4 zones=6 woodlot=true guard=true duplicate=refused owner=refused unknown=storage")
