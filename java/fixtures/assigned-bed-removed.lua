-- A claimed bed can disappear (picked up or scrapped). The assigned-bed
-- resolver must then resolve nothing at all - never a phantom spot - and the
-- existing fallbacks decide: the normal rest scan (with its named donor
-- refusal) or, on a player-owned base, the existing ambient rest. Reading a
-- claim never writes one, so a missing bed cannot hand ownership to anybody.
local C = assert(KnoxAutonomyController)
local previousCell, previousFinder = getCell, AdjacentFreeTileFinder
local previousPersistence = KnoxPersistence
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousManager = rawget(_G, "KnoxBaseManager")
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")

local claim = { x = 4, y = 4, z = 0, objectIndex = 3 }
local donorClaim = { x = 3, y = 5, z = 0, objectIndex = 9 }
local policies = { resident = { assignedBed = claim }, donor = { assignedBed = donorClaim } }
local claimWrites = 0
KnoxPersistence = {
    getBaseResidentIds = function(baseId)
        assert(baseId == "removed-bed-base", "the claims owner is asked about this resident's base")
        return { "resident", "donor" }
    end,
    getSurvivorPolicies = function(id) return policies[id] end,
    isSurvivorAlive = function() return true end,
    setFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
    clearFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
}
KnoxSurvivorNeeds = { snapshot = function() return {} end }
local bodies = {}
KnoxSurvivorRuntime = { getCharacter = function(id) return bodies[id] end }
KnoxBaseManager = { containsSquare = function(_, square) return square ~= nil end }

-- One entry per square; `present` is the furniture actually standing there, so
-- the same claim can be resolved before and after a pickup.
local squares = {}
local function square(x, y, present, index)
    local entry = { present = present }
    entry.object = { getObjectIndex = function() return index end,
        getProperties = function() return { get = function(_, key)
            return key == "BedType" and "averageBed" or nil end } end,
        isFurnitureOccupied = function() return false end }
    entry.square = { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end,
        getObjects = function() return { size = function() return entry.present and 1 or 0 end,
            get = function() return entry.object end } end }
    entry.object.getSquare = function() return entry.square end
    squares[x .. ":" .. y] = entry
    return entry
end
local origin = square(3, 4, false, 1).square
local claimed = square(4, 4, true, 3)    -- the resident's own bed
local free = square(5, 4, true, 5)       -- a real free bed in the same base
local donorBed = square(3, 5, false, 9)  -- another resident's bed
getCell = function() return { getGridSquare = function(_, x, y, z)
    if z ~= 0 then return nil end
    local entry = squares[x .. ":" .. y]
    return entry ~= nil and entry.square or nil
end } end
AdjacentFreeTileFinder = { Find = function(square) return square end }

local function resident(id, ticks, ownerKind)
    local self = { id = id, currentTicks = ticks,
        base = { id = "removed-bed-base", ownerKind = ownerKind or "faction" },
        character = { getCurrentSquare = function() return origin end },
        reservations = { restSpots = {} }, failedRestSpots = {},
        allowNeedDetour = function() return true end,
        roamForeignBase = function() return nil end }
    -- Assign the closures after the table exists so they capture this resident.
    self.bridge = { moveNpc = function(_, who, square)
        self.moved = square
        return "MOVE_STARTED"
    end }
    self.startRecoveryPosture = function(_, ticks2, here)
        self.postureHere = here ~= false
        return true
    end
    return setmetatable(self, { __index = C })
end

-- 1. The claimed bed is there: it wins over the free bed beside it, and the
--    real recovery path reserves and walks to that exact furniture.
local first = resident("resident", 100)
local spot = first:assignedBedSpot()
assert(spot ~= nil and spot.object == claimed.object and spot.approach == claimed.square,
    "a live claimed bed resolves to the real furniture and its approach")
assert(spot.bedType == "averageBed", "the resolved spot reports the native bed type")
assert(first:beginRecovery("sleep", 100) == true and first.pendingRest.object == claimed.object,
    "the recovery path reserves the resident's own claimed bed")
assert(first.moved == claimed.square and first.state == "MOVING_TO_REST",
    "the movement owner walks to the claimed bed")
assert(claimWrites == 0, "reading a claim never writes one")

-- 2. The bed is gone (picked up): the branch resolves nothing rather than a
--    phantom spot, and the normal scan finds a real free bed without taking
--    ownership of anything.
claimed.present = false
local second = resident("resident", 200)
assert(second:assignedBedSpot() == nil,
    "a removed claimed bed resolves to nothing, never a phantom spot")
assert(second:beginRecovery("sleep", 200) == true, "a missing bed does not stall the recovery decision")
assert(second.pendingRest ~= nil and second.pendingRest.object == free.object
    and second.moved == free.square,
    "the removed-bed branch falls through to a real free bed through the normal scan")
assert(second.pendingRest.object ~= claimed.object, "the survivor never sleeps on the removed bed")
assert(claimWrites == 0 and policies.resident.assignedBed == claim,
    "the fallback writes no claim and leaves the stored claim with its owner")

-- 3. Only a present donor's bed remains: the removed-bed branch defers to the
--    existing named refusal instead of silently taking that bed.
free.present = false
donorBed.present = true
bodies.donor = { getCurrentSquare = function() return donorBed.square end }
local third = resident("resident", 300)
assert(third:beginRecovery("sleep", 300) == true, "a refused recovery still settles the resident")
assert(third.pendingRest == nil and third.lastFailure ~= nil
    and third.lastFailure.reason == "rest_spot:donor_bed_claimed",
    "with only a present donor's bed left, the removed-bed fallback refuses by name")
assert(claimWrites == 0 and policies.donor.assignedBed == donorClaim,
    "the named refusal takes nothing and leaves the donor's claim alone")

-- 4. A player-owned base with a removed claimed bed keeps the documented
--    ambient rest instead of inventing a bed or a floor spot.
assert(C.scheduledSleepUsesBed("player", false) == false
    and C.scheduledSleepUsesBed("faction", false) == true,
    "the scheduled-sleep rule still depends on an actual assignment on a player base")
local fourth = resident("resident", 400, "player")
fourth.releaseLights = function() end
fourth.beginAmbientBaseRest = function() fourth.ambient = true return true end
fourth.beginRecovery = function() fourth.recovered = true return true end
assert(fourth:beginScheduledBaseSleep(400) == true and fourth.ambient == true
    and fourth.recovered == nil,
    "a player base with a removed claimed bed keeps the existing ambient rest")
assert(claimWrites == 0, "no fallback in this branch invents a claim")

getCell, AdjacentFreeTileFinder = previousCell, previousFinder
KnoxPersistence = previousPersistence
_G.KnoxSurvivorRuntime = previousRuntime
_G.KnoxBaseManager = previousManager
_G.KnoxSurvivorNeeds = previousNeeds
print("Assigned bed removed PASS liveBedWins=true removedBedNil=true freeBedFallback=true namedDonorRefusal=true playerBaseAmbient=true noClaimWrite=true nativeGameplay=false")
