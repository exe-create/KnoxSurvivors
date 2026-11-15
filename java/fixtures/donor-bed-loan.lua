-- A bed another resident holds is a loan decided by the existing bed claim,
-- never a second claim: a resident without a bed may use the donor bed only
-- while the donor is away from the base, and is refused by name while the
-- donor is here to use it.
local C = assert(KnoxAutonomyController)
local previousCell, previousFinder = getCell, AdjacentFreeTileFinder
local previousPersistence = KnoxPersistence
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousManager = rawget(_G, "KnoxBaseManager")
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")

local donorBed = { x = 4, y = 4, z = 0, objectIndex = 3 }
local policies = { donor = { assignedBed = donorBed }, borrower = {}, second = {} }
local claimWrites = 0
KnoxPersistence = {
    getBaseResidentIds = function(baseId)
        assert(baseId == "donor-base", "the claims owner is asked about the resident's base")
        return { "donor", "borrower", "second" }
    end,
    getSurvivorPolicies = function(id) return policies[id] end,
    isSurvivorAlive = function() return true end,
    setFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
    clearFactionResidentBed = function() claimWrites = claimWrites + 1 return true end,
}
KnoxSurvivorNeeds = { snapshot = function() return {} end }

local base = { id = "donor-base" }
local bed
local bedSquare = { getX = function() return 4 end, getY = function() return 4 end,
    getZ = function() return 0 end,
    getObjects = function() return { size = function() return 1 end,
        get = function() return bed end } end }
local groundSquare = { getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
    getObjects = function() return { size = function() return 0 end } end }
bed = { getObjectIndex = function() return 3 end,
    getSquare = function() return bedSquare end,
    getProperties = function() return { get = function(_, key)
        return key == "BedType" and "averageBed" or nil
    end } end,
    isFurnitureOccupied = function() return false end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    if x == 4 and y == 4 and z == 0 then return bedSquare end
    return groundSquare
end } end
AdjacentFreeTileFinder = { Find = function(square) return square end }
local bodies = {}
KnoxSurvivorRuntime = { getCharacter = function(id) return bodies[id] end }
KnoxBaseManager = { containsSquare = function(_, square) return square == bedSquare end }

local function resident(id, ticks)
    local self = { id = id, base = base, currentTicks = ticks,
        character = { getCurrentSquare = function() return groundSquare end },
        reservations = { restSpots = {} }, failedRestSpots = {},
        allowNeedDetour = function() return true end,
        roamForeignBase = function() return nil end }
    -- Assign the closures after the table exists: a closure built inside the
    -- constructor would capture the global `self`, not this resident.
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

-- 1. The donor is away, so the claimed bed is loaned: used, never claimed.
local borrower = resident("borrower", 100)
assert(borrower:beginRecovery("sleep", 100) == true,
    "a resident with no bed still gets rest through the loan")
assert(borrower.pendingRest ~= nil and borrower.pendingRest.object == bed,
    "an absent donor's bed is loaned to a resident without one")
assert(borrower.moved == bedSquare and borrower.state == "MOVING_TO_REST",
    "the loan walks to the same bed through the existing movement owner")
assert(policies.borrower.assignedBed == nil and claimWrites == 0,
    "using a donor bed never writes a second claim")
assert(policies.donor.assignedBed == donorBed,
    "the donor still owns the only claim on that bed")

-- 2. The donor is at the base, so the same bed is refused by name.
bodies.donor = { getCurrentSquare = function() return bedSquare end }
policies.borrower = {}
local second = resident("second", 200)
assert(second:beginRecovery("sleep", 200) == true,
    "a refused loan still settles the resident instead of stalling")
assert(second.pendingRest == nil and second.postureHere == false,
    "a claimed donor bed is not taken while its owner is at the base")
assert(second.lastFailure ~= nil
    and second.lastFailure.reason == "rest_spot:donor_bed_claimed",
    "a refused donor bed is named, not a silent stall")
assert(claimWrites == 0 and policies.second.assignedBed == nil,
    "a refused loan creates no duplicate claim")

-- 3. The bed is already claimed and its owner is present for a third resident.
local third = resident("third", 300)
assert(third:beginRecovery("sleep", 300) == true and third.pendingRest == nil,
    "an already claimed donor bed stays with its owner")
assert(third.lastFailure ~= nil
    and third.lastFailure.reason == "rest_spot:donor_bed_claimed"
    and claimWrites == 0,
    "a second borrower adds no claim to an owned bed")

-- 4. With the donor dead the claim no longer blocks a loan.
bodies.donor = nil
policies.donor = { assignedBed = donorBed }
local before = claimWrites
local fourth = resident("borrower", 400)
assert(fourth:beginRecovery("sleep", 400) == true
    and fourth.pendingRest ~= nil and fourth.pendingRest.object == bed,
    "a claim released by the donor's absence still loans the bed")
assert(claimWrites == before, "the loan path never claims the bed")

getCell, AdjacentFreeTileFinder = previousCell, previousFinder
KnoxPersistence = previousPersistence
_G.KnoxSurvivorRuntime = previousRuntime
_G.KnoxBaseManager = previousManager
_G.KnoxSurvivorNeeds = previousNeeds
print("Donor bed loan PASS absentLoan=true presentRefusal=true named=true noDuplicateClaim=true")
