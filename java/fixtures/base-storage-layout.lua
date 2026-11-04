local B = assert(codecBaseLayout, "base layout source is loaded")
local Persistence = assert(KnoxPersistence, "persistence is loaded")

local previousCell = getCell
local previousInstanceof = instanceof
local previousStorage = rawget(_G, "KnoxBaseStorage")
local previousCupboard = rawget(_G, "KnoxToolCupboard")

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
instanceof = function(object, class)
    return class == "IsoStove" and object ~= nil and object.isStove == true
end

local nextObjectIndex = 1
local function makeContainer(kind)
    local container = { kind = kind }
    function container:getType() return self.kind end
    function container:isExistYet() return true end
    return container
end

local function makeObject(square, kind, options)
    options = options or {}
    local object = {
        containers = options.noContainer == true and {} or { makeContainer(kind) },
        modData = {},
        square = square,
        objectIndex = nextObjectIndex,
        isStove = options.stove == true,
    }
    nextObjectIndex = nextObjectIndex + 1
    function object:getContainerCount() return #self.containers end
    function object:getContainerByIndex(index) return self.containers[index + 1] end
    function object:getSquare() return self.square end
    function object:getObjectIndex() return self.objectIndex end
    function object:getModData() return self.modData end
    function object:transmitModData() end
    square.rawObjects[#square.rawObjects + 1] = object
    return object
end

local function makeAppliance(square)
    return makeObject(square, "stove", { noContainer = true, stove = true })
end

local function makeSquare(x, y, z, room, building)
    local raw = {}
    local square = {
        x = x, y = y, z = z, room = room, building = building,
        rawObjects = raw,
    }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return self.room end
    function square:getBuilding() return self.building end
    function square:getObjects() return list(raw) end
    function square:canStand() return self.room == nil end
    map[key(x, y, z)] = square
    return square
end

local function addDoor(x, y, z, locked, keyId)
    local square = map[key(x, y, z)]
    assert(square ~= nil, "the door square exists")
    local door = { isDoor = true, locked = locked == true, keyId = keyId }
    function door:isLocked() return self.locked end
    function door:isLockedByKey() return self.locked end
    function door:getKeyId() return self.keyId end
    square.rawObjects[#square.rawObjects + 1] = door
    return door
end

local function makeLeader(ids)
    return {
        getInventory = function()
            return {
                haveThisKeyId = function(_, id)
                    for _, expected in ipairs(ids or {}) do
                        if tonumber(id) == expected then return true end
                    end
                    return false
                end,
            }
        end,
    }
end

local leaderWithKey = makeLeader({ 42 })
local leaderWithoutKey = makeLeader({})

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
    function room:getRects()
        return list({ makeRect(self.x, self.y, self.w, self.h) })
    end
    return room
end

local function addRoomSquares(room, building)
    for x = room.x, room.x + room.w - 1 do
        for y = room.y, room.y + room.h - 1 do
            makeSquare(x, y, room.z, room, building)
        end
    end
end

local function createBase(owner, buildingId, x, y, w, h, rooms)
    local building = { id = buildingId, rooms = rooms }
    function building:getDef()
        return { getID = function() return self.id end }
    end
    function building:getRooms() return list(self.rooms) end
    for _, room in ipairs(rooms) do addRoomSquares(room, building) end
    local base, created = Persistence.createBase("player", owner, {
        minX = x, minY = y, width = w, height = h, z = 0,
        buildingId = buildingId,
    }, 40)
    assert(base ~= nil and created == "created", "storage fixture base was created")
    return base, building
end

local function isDryContainer(kind)
    kind = string.lower(tostring(kind or ""))
    return kind ~= "fridge" and not kind:find("freezer", 1, true)
        and not kind:find("water", 1, true) and not kind:find("rain", 1, true)
        and kind ~= "corpse"
end

_G.KnoxBaseStorage = {
    policies = function() end,
    syncContainerName = function() end,
    label = function(policy) return policy and policy.category or "Storage" end,
}
_G.KnoxToolCupboard = {
    isDryContainerType = isDryContainer,
    applyInfinite = function() return true end,
}

-- Kitchen: food prefers the fridge, water takes the dry crate.
-- Bathroom: medical storage is proposed even though it is not a work area.
-- Garage: tools and materials share the two containers.
-- Garden: farming uses its crate. The larger bedroom crate must stay unassigned.
local kitchen = makeRoom("Kitchen", 200, 200, 3, 3)
local bathroom = makeRoom("Bathroom", 204, 200, 2, 2)
local garage = makeRoom("Garage", 207, 200, 3, 3)
local garden = makeRoom("Garden", 211, 200, 2, 2)
local bedroom = makeRoom("Bedroom", 200, 204, 3, 3)
local baseA, buildingA = createBase(
    "storage-a-player", "storage-a-building", 200, 200, 13, 7,
    { kitchen, bathroom, garage, garden, bedroom }
)
makeObject(map[key(200, 200, 0)], "fridge")
makeObject(map[key(201, 200, 0)], "crate")
makeObject(map[key(204, 200, 0)], "cabinet")
makeObject(map[key(207, 200, 0)], "crate")
makeObject(map[key(208, 200, 0)], "shelf")
makeObject(map[key(209, 200, 0)], "crate")
makeObject(map[key(211, 200, 0)], "crate")
makeObject(map[key(200, 204, 0)], "crate")

local entries, reason = B.proposeLayout(baseA.id, buildingA, 0)
assert(reason == "proposed", "the multi-room base produces a proposal")
assert(#entries == 3, "cooking, repair and farming are the only proposed work areas")
local storage = assert(entries.storage, "the proposal carries storage assignments")
assert(#storage == 7, "seven storage categories are proposed")
local byCategory = {}
for _, entry in ipairs(storage) do byCategory[entry.category] = entry end
assert(byCategory.food ~= nil and byCategory.food.kind:find("fridge", 1, true) ~= nil,
    "food uses the real fridge")
assert(byCategory.water ~= nil and byCategory.water.roomLabel == "Kitchen",
    "water uses the dry kitchen crate")
assert(byCategory.medical ~= nil and byCategory.medical.roomLabel == "Bathroom",
    "bathroom storage becomes medical")
assert(byCategory.tools ~= nil and byCategory.tools.roomLabel == "Garage",
    "garage storage becomes tools")
assert(byCategory.building ~= nil and byCategory.building.roomLabel == "Garage",
    "the second garage container becomes materials")
assert(byCategory.farming ~= nil and byCategory.farming.roomLabel == "Garden",
    "garden storage becomes farming")
assert(byCategory.fuel ~= nil and byCategory.fuel.roomLabel == "Garage",
    "the third garage container becomes fuel")
assert(byCategory.weapons == nil and byCategory.ammunition == nil,
    "weapons and ammunition are not invented")
for _, entry in ipairs(storage) do
    assert(entry.roomLabel ~= "Bedroom", "a bedroom container is never assigned")
end

local refused, why = B.applyLayout(baseA.id, entries, "someone-else")
assert(refused == nil and why == "not_your_base",
    "another player cannot apply storage assignments")
local refusedStorage = 0
for _ in pairs(baseA.storage or {}) do refusedStorage = refusedStorage + 1 end
assert(refusedStorage == 0, "a refused apply writes no storage policy")

local applied = assert(B.applyLayout(baseA.id, entries, "storage-a-player"),
    "the owner applies the proposal")
assert(applied.added == 3 and applied.assigned == 7,
    "three work areas and seven storage assignments are added")
assert(#applied.skipped == 0 and #applied.storageSkipped == 0,
    "the complete proposal is accepted")
local stored, storedCategories = 0, {}
for _, policy in pairs(baseA.storage or {}) do
    stored = stored + 1
    storedCategories[policy.category] = true
end
assert(stored == 7, "seven ordinary storage policies are written")
assert(storedCategories.food and storedCategories.water and storedCategories.medical
    and storedCategories.tools and storedCategories.building and storedCategories.farming
    and storedCategories.fuel,
    "the applied policies keep their real categories")

local again = assert(B.applyLayout(baseA.id, entries, "storage-a-player"),
    "re-applying is a no-op")
assert(again.added == 0 and again.assigned == 0 and #again.skipped == 3
    and #again.storageSkipped == 7,
    "re-apply refuses every existing zone and storage category")
stored = 0
for _ in pairs(baseA.storage or {}) do stored = stored + 1 end
assert(stored == 7, "re-apply creates no duplicate storage policy")

local empty, emptyReason = B.proposeLayout(baseA.id, buildingA, 0)
assert(#empty == 0 and #(empty.storage or {}) == 0 and emptyReason == "no_new_rooms",
    "a fully covered base proposes no storage assignment")

-- A storage-only proposal must still be applicable.
local storeRoom = makeRoom("Store Room", 250, 250, 2, 2)
local baseB, buildingB = createBase(
    "storage-b-player", "storage-b-building", 250, 250, 2, 2, { storeRoom }
)
makeObject(map[key(250, 250, 0)], "crate")
assert(Persistence.addBaseZone(baseB.id, "general", {
    x1 = 250, y1 = 250, x2 = 251, y2 = 251, z = 0,
}, "Store Room") ~= nil, "the storage-only fixture already has its work area")
local storageOnly, storageOnlyReason = B.proposeLayout(baseB.id, buildingB, 0)
assert(#storageOnly == 0 and #(storageOnly.storage or {}) == 1
    and storageOnlyReason == "proposed",
    "a covered zone still yields its missing storage assignment")
local appliedB = assert(B.applyLayout(baseB.id, storageOnly, "storage-b-player"),
    "a storage-only proposal applies")
assert(appliedB.added == 0 and appliedB.assigned == 1,
    "storage-only apply writes one policy without a zone")

-- An existing category must not be proposed again.
local kitchenC = makeRoom("Kitchen", 280, 280, 2, 2)
local baseC, buildingC = createBase(
    "storage-c-player", "storage-c-building", 280, 280, 2, 2, { kitchenC }
)
local fridgeC = makeObject(map[key(280, 280, 0)], "fridge")
local foodPolicy = assert(B.setStoragePolicy(baseC.id, fridgeC, "food", 0),
    "the existing food policy is written through the storage owner")
assert(foodPolicy.category == "food", "the existing policy keeps food")
local existing, existingReason = B.proposeLayout(baseC.id, buildingC, 0)
assert(#(existing.storage or {}) == 0, "an existing category is not proposed again")
assert(existingReason == "proposed", "the kitchen work area is still proposed")

-- A container moved outside the base between proposal and apply must refuse.
local kitchenD = makeRoom("Kitchen", 310, 310, 2, 2)
local baseD, buildingD = createBase(
    "storage-d-player", "storage-d-building", 310, 310, 2, 2, { kitchenD }
)
local fridgeD = makeObject(map[key(310, 310, 0)], "fridge")
local moved, movedReason = B.proposeLayout(baseD.id, buildingD, 0)
assert(movedReason == "proposed" and #(moved.storage or {}) == 1,
    "the moved-container fixture starts with one storage proposal")
local outside = makeSquare(330, 330, 0, nil, buildingD)
fridgeD.square = outside
local appliedD = assert(B.applyLayout(baseD.id, moved, "storage-d-player"),
    "the work area still applies")
assert(appliedD.added == 1 and appliedD.assigned == 0,
    "the moved container cannot be assigned")
assert(#appliedD.storageSkipped == 1
    and appliedD.storageSkipped[1].reason == "outside_base",
    "the moved container is refused with a named reason")

-- A named secure room needs a real locked door before weapons/ammunition
-- are proposed. The same room with an unlocked door stays unassigned.
local armory = makeRoom("Armory", 350, 350, 2, 2)
local baseE, buildingE = createBase(
    "storage-e-player", "storage-e-building", 350, 350, 2, 2, { armory }
)
makeObject(map[key(350, 350, 0)], "locker")
makeObject(map[key(351, 350, 0)], "crate")
makeSquare(349, 350, 0, nil, buildingE)
addDoor(349, 350, 0, true, 42)
local secure, secureReason = B.proposeLayout(baseE.id, buildingE, 0, leaderWithKey)
assert(secureReason == "proposed" and #(secure.storage or {}) == 2,
    "a locked armory proposes weapons and ammunition")
local secureByCategory = {}
for _, entry in ipairs(secure.storage) do secureByCategory[entry.category] = entry end
assert(secureByCategory.weapons ~= nil and secureByCategory.ammunition ~= nil,
    "the locked armory proposes both secure categories")
local appliedE = assert(B.applyLayout(baseE.id, secure, "storage-e-player", leaderWithKey),
    "the locked armory applies")
assert(appliedE.added == 1 and appliedE.assigned == 2,
    "the locked armory applies one zone and two storage policies")

local openArmory = makeRoom("Armory", 360, 350, 2, 2)
local baseF, buildingF = createBase(
    "storage-f-player", "storage-f-building", 360, 350, 2, 2, { openArmory }
)
makeObject(map[key(360, 350, 0)], "locker")
makeObject(map[key(361, 350, 0)], "crate")
makeSquare(359, 350, 0, nil, buildingF)
addDoor(359, 350, 0, false)
local open, openReason = B.proposeLayout(baseF.id, buildingF, 0)
assert(openReason == "proposed" and #(open.storage or {}) == 2,
    "an unlocked but reachable armory proposes weapons and ammunition")

-- A locked armory the owner cannot open is not a reachable container.
local sealedArmory = makeRoom("Gun Room", 400, 350, 2, 2)
local baseJ, buildingJ = createBase(
    "storage-j-player", "storage-j-building", 400, 350, 2, 2, { sealedArmory }
)
makeObject(map[key(400, 350, 0)], "locker")
makeObject(map[key(401, 350, 0)], "crate")
makeSquare(399, 350, 0, nil, buildingJ)
addDoor(399, 350, 0, true, 99)
local sealed, sealedReason = B.proposeLayout(baseJ.id, buildingJ, 0, leaderWithoutKey)
assert(sealedReason == "proposed" and #(sealed.storage or {}) == 0,
    "a locked armory without the key proposes no secure storage")
local reachableSealed, reachableSealedReason = B.proposeLayout(
    baseJ.id, buildingJ, 0, makeLeader({ 99 }))
assert(reachableSealedReason == "proposed" and #(reachableSealed.storage or {}) == 2,
    "the same armory proposes storage when the owner has its key")
local blocked = assert(B.applyLayout(baseJ.id, reachableSealed, "storage-j-player", leaderWithoutKey),
    "losing the key still returns an apply result")
assert(blocked.added == 1 and blocked.assigned == 0
    and #blocked.storageSkipped == 2
    and blocked.storageSkipped[1].reason == "secure_room_unreachable",
    "apply refuses a secure room the owner can no longer open")
local appliedJ = assert(B.applyLayout(baseJ.id, reachableSealed, "storage-j-player", makeLeader({ 99 })),
    "the keyed owner can still apply the storage")
assert(appliedJ.added == 0 and appliedJ.assigned == 2,
    "the reachable secure storage applies through the existing writer")

-- A reachable storage room is the non-secure fallback. General storage must
-- leave a locker/cabinet free, and losing the door key must refuse the
-- fallback at apply time without rewriting the general policy.
local fallbackStore = makeRoom("Storage Room", 420, 350, 2, 2)
local baseK, buildingK = createBase(
    "storage-k-player", "storage-k-building", 420, 350, 2, 2, { fallbackStore }
)
makeObject(map[key(420, 350, 0)], "locker")
makeObject(map[key(421, 350, 0)], "crate")
makeObject(map[key(420, 351, 0)], "cabinet")
makeSquare(419, 350, 0, nil, buildingK)
local fallbackDoor = addDoor(419, 350, 0, false)
local fallback, fallbackReason = B.proposeLayout(baseK.id, buildingK, 0)
assert(fallbackReason == "proposed" and #(fallback.storage or {}) == 3,
    "a reachable storage room proposes general, weapons and ammunition")
local fallbackByCategory = {}
for _, entry in ipairs(fallback.storage) do fallbackByCategory[entry.category] = entry end
assert(fallbackByCategory.general ~= nil
    and fallbackByCategory.general.kind == "crate",
    "general storage leaves the lockable containers for the fallback")
assert(fallbackByCategory.weapons ~= nil
    and fallbackByCategory.weapons.roomLabel == "Storage Room"
    and fallbackByCategory.weapons.kind == "locker",
    "weapons use the reachable storage-room locker")
assert(fallbackByCategory.ammunition ~= nil
    and fallbackByCategory.ammunition.kind == "cabinet",
    "ammunition uses the second reachable lockable container")
fallbackDoor.locked = true
fallbackDoor.keyId = 77
local blockedFallback = assert(B.applyLayout(
    baseK.id, fallback, "storage-k-player", leaderWithoutKey),
    "losing the storage-room key still returns an apply result")
assert(blockedFallback.added == 1 and blockedFallback.assigned == 1
    and #blockedFallback.storageSkipped == 2
    and blockedFallback.storageSkipped[1].reason == "storage_room_unreachable",
    "a sealed storage room keeps general storage but refuses weapons and ammunition")
fallbackDoor.locked = false
local appliedK = assert(B.applyLayout(baseK.id, fallback, "storage-k-player"),
    "the reopened storage room can apply the fallback")
assert(appliedK.added == 0 and appliedK.assigned == 2
    and #appliedK.storageSkipped == 1,
    "reopening the door applies only the two missing fallback categories")

-- A locked storage room is not a fallback when the leader has no key. Its
-- ordinary crate may still be general storage; no weapons are proposed.
local sealedStore = makeRoom("Storage Room", 430, 350, 2, 2)
local baseL, buildingL = createBase(
    "storage-l-player", "storage-l-building", 430, 350, 2, 2, { sealedStore }
)
makeObject(map[key(430, 350, 0)], "locker")
makeObject(map[key(431, 350, 0)], "crate")
makeSquare(429, 350, 0, nil, buildingL)
addDoor(429, 350, 0, true, 88)
local sealedStoreProposal, sealedStoreReason = B.proposeLayout(
    baseL.id, buildingL, 0, leaderWithoutKey)
assert(sealedStoreReason == "proposed"
    and #(sealedStoreProposal.storage or {}) == 1,
    "a sealed storage room proposes only its ordinary general container")
assert(sealedStoreProposal.storage[1].category == "general",
    "a sealed storage room does not invent weapons storage")

-- A named indoor log store uses the existing logs category; it does not
-- invent fuel or outdoor work areas.
local logStore = makeRoom("Log Store", 370, 350, 2, 2)
local baseG, buildingG = createBase(
    "storage-g-player", "storage-g-building", 370, 350, 2, 2, { logStore }
)
makeObject(map[key(370, 350, 0)], "crate")
local logs, logsReason = B.proposeLayout(baseG.id, buildingG, 0)
assert(logsReason == "proposed" and #(logs.storage or {}) == 1,
    "a log store proposes one logs container")
assert(logs.storage[1].category == "logs", "the log store keeps the logs category")
local appliedG = assert(B.applyLayout(baseG.id, logs, "storage-g-player"),
    "the log store applies")
assert(appliedG.added == 1 and appliedG.assigned == 1,
    "the log store applies one zone and one logs policy")

-- A named fuel room uses the same dry-container path and must not become a
-- workshop merely because its name contains "store".
local fuelStore = makeRoom("Fuel Store", 380, 350, 2, 2)
local baseH, buildingH = createBase(
    "storage-h-player", "storage-h-building", 380, 350, 2, 2, { fuelStore }
)
makeObject(map[key(380, 350, 0)], "crate")
local fuel, fuelReason = B.proposeLayout(baseH.id, buildingH, 0)
assert(fuelReason == "proposed" and #(fuel.storage or {}) == 1,
    "a fuel store proposes one fuel container")
assert(fuel.storage[1].category == "fuel", "the fuel store keeps the fuel category")
local appliedH = assert(B.applyLayout(baseH.id, fuel, "storage-h-player"),
    "the fuel store applies")
assert(appliedH.added == 1 and appliedH.assigned == 1,
    "the fuel store applies one zone and one fuel policy")

-- A named room with no room-name rule and a real IsoStove is a cooking area.
-- The appliance is a location fact; this does not claim it is powered.
local study = makeRoom("Study", 390, 350, 2, 2)
local baseI, buildingI = createBase(
    "storage-i-player", "storage-i-building", 390, 350, 2, 2, { study }
)
makeAppliance(map[key(390, 350, 0)])
local appliance, applianceReason = B.proposeLayout(baseI.id, buildingI, 0)
assert(applianceReason == "proposed" and #appliance == 1,
    "the stove room produces one work area")
assert(appliance[1].zoneType == "cooking",
    "the unrecognized room is classified by its stove")
assert(#(appliance.storage or {}) == 0,
    "the stove room proposes no storage")
local appliedI = assert(B.applyLayout(baseI.id, appliance, "storage-i-player"),
    "the appliance room applies")
assert(appliedI.added == 1 and appliedI.assigned == 0,
    "the appliance room applies one cooking area and no storage")

_G.KnoxBaseStorage = previousStorage
_G.KnoxToolCupboard = previousCupboard
getCell = previousCell
instanceof = previousInstanceof

print("Base storage layout PASS categories=7 secure=2 unlocked=2 sealed=0 recheck=2 fallback=2 fallback_recheck=2 logs=1 fuel=2 appliance=1 storage-only=1 existing=skipped moved=outside_base")
