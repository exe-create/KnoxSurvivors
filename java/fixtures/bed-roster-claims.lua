-- A stored bed claim can outlive its furniture. The roster must stop showing a
-- picked-up bed as one the resident has, while an unloaded square stays
-- unknown (the claim is real, the furniture is just not streamed). The
-- controller's own reader is asserted beside it so the two cannot quietly
-- disagree about a bed that is actually gone.
local B = assert(codecBedRoster, "bed roster source is loaded")
local C = assert(KnoxAutonomyController)
local previousCell, previousFinder = getCell, AdjacentFreeTileFinder
local previousPersistence = KnoxPersistence

local claim = { x = 4, y = 4, z = 0, objectIndex = 3 }
local policies = { resident = { assignedBed = claim } }
local claimWrites = 0
KnoxPersistence = {
    getBaseResidentIds = function(baseId)
        assert(baseId == "roster-home", "the roster asks about the selected base")
        return { "resident" }
    end,
    getCompanionIds = function() return {} end,
    isSurvivorAlive = function() return true end,
    getSurvivorIdentity = function() return { forename = "Bed", surname = "Holder" } end,
    getSurvivorPolicies = function(id) return policies[id] end,
    setFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
    clearFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
}

local bedPresent, loaded, bedSquare = true, true, nil
local bedObject = { getObjectIndex = function() return 3 end,
    getProperties = function() return { get = function(_, key)
        return key == "BedType" and "averageBed" or nil end } end,
    isFurnitureOccupied = function() return false end }
local originSquare = { getX = function() return 3 end, getY = function() return 4 end,
    getZ = function() return 0 end,
    getObjects = function() return { size = function() return 0 end } end }
bedSquare = { getX = function() return 4 end, getY = function() return 4 end,
    getZ = function() return 0 end,
    getObjects = function() return { size = function() return bedPresent and 1 or 0 end,
        get = function() return bedObject end } end }
bedObject.getSquare = function() return bedSquare end
getCell = function() return { getGridSquare = function(_, x, y, z)
    if not loaded or z ~= 0 or x ~= 4 or y ~= 4 then return nil end
    return bedSquare
end } end
AdjacentFreeTileFinder = { Find = function(square) return square end }

local base = { id = "roster-home", ownerKind = "player", ownerId = "player" }
local resident = setmetatable({ id = "resident", currentTicks = 100, base = base,
    character = { getCurrentSquare = function() return originSquare end },
    reservations = { restSpots = {} } }, C)

-- 1. The bed stands: the roster reports it and the controller can use it.
local rows = B.bedRoster(base, "player")
assert(#rows == 1 and rows[1].bed ~= nil and rows[1].bed.x == 4
    and rows[1].bed.objectIndex == 3,
    "a claim whose bed still stands is reported by the roster")
assert(resident:assignedBedSpot() ~= nil,
    "the controller resolves the same live claim, so the two agree")

-- 2. The bed is picked up: neither reader may keep reporting it as usable, and
--    the claim record itself is never rewritten.
bedPresent = false
rows = B.bedRoster(base, "player")
assert(#rows == 1 and rows[1].bed == nil,
    "a picked-up bed is not reported as this resident's bed")
assert(resident:assignedBedSpot() == nil,
    "the controller resolves the same removed bed to nothing, so the two agree")
assert(claimWrites == 0 and policies.resident.assignedBed == claim,
    "reporting a missing bed writes no claim and leaves the record with its owner")

-- 3. The square is out of stream: unknown is not gone, so the recorded claim
--    is still reported, while the controller cannot sleep on unloaded
--    furniture. Neither case invents or takes a bed.
bedPresent, loaded = true, false
rows = B.bedRoster(base, "player")
assert(#rows == 1 and rows[1].bed ~= nil and rows[1].bed.x == 4,
    "an unloaded claimed bed stays reported instead of being read as lost")
assert(resident:assignedBedSpot() == nil,
    "the controller cannot use unloaded furniture, and the claim is not dropped for it")
assert(claimWrites == 0, "no liveness read writes a claim")

getCell, AdjacentFreeTileFinder = previousCell, previousFinder
KnoxPersistence = previousPersistence
print("Bed roster claims PASS live=true removed=nil unloaded=kept controllerAgrees=true claimWrites=0 nativeGameplay=false")
