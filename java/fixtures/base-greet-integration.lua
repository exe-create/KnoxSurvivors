-- Drives the real Controller:beginAmbientSocial, not just the pure decision, so
-- the greeting is proven to be reachable from the idle social owner.
local C = assert(KnoxAutonomyController)

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

local previousPlayer = getSpecificPlayer
local player = { getCurrentSquare = function() return square(8701, 8701, 0) end }
getSpecificPlayer = function() return player end

local resident = setmetatable({
    id = "greeter",
    baseId = "base-greet",
    state = "BASE_IDLE",
    character = {
        getCurrentSquare = function() return square(8700, 8700, 0) end,
        faceThisObject = function() end,
    },
}, { __index = C })

assert(resident:beginAmbientSocial(1000) == true, "a resident near the player greets them")
assert(resident.activeDecision == "base_greet_player", "the greeting is the decision it takes")
assert((resident.nextPlayerGreet or 0) > 1000, "the greeting starts its own cooldown")

-- Inside the cooldown nothing greets again, and no partner is nearby.
assert(resident:beginAmbientSocial(1100) == false, "the greeting respects its cooldown")

-- Distance silences it.
local far = setmetatable({
    id = "far-one",
    baseId = "base-greet",
    state = "BASE_IDLE",
    character = {
        getCurrentSquare = function() return square(8760, 8760, 0) end,
        faceThisObject = function() end,
    },
}, { __index = C })
assert(far:beginAmbientSocial(2000) == false, "a distant resident does not wave")

-- Combat silences it, even at close range.
local fighter = setmetatable({
    id = "fighter",
    baseId = "base-greet",
    state = "BASE_IDLE",
    combatTarget = {},
    character = {
        getCurrentSquare = function() return square(8700, 8700, 0) end,
        faceThisObject = function() end,
    },
}, { __index = C })
assert(fighter:beginAmbientSocial(3000) == false, "a resident in combat does not wave")

getSpecificPlayer = previousPlayer
