-- Two survivor groups meet. The decisions come from Positioning.engageDecision
-- and the real humanCombatStep; ammo is read from whatever is carried, not just
-- the hand item.
local P = assert(KnoxCombatPositioning)
local Persistence = assert(KnoxPersistence)
local previousIds = Persistence.getBaseResidentIds
Persistence.getBaseResidentIds = function() return { "one", "two", "three" } end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
        isBlockedTo = function() return false end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
    }
end

local function list(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

-- A magazine in a carried bag is still rounds that can be fired.
local magazine = { getCurrentAmmoCount = function() return 24 end }
local bag = {
    getInventory = function() return { getItems = function() return list({ magazine }) end } end,
}
local carrier = {
    getInventory = function() return { getItems = function() return list({ bag }) end } end,
}
local ammo, armed = P.carriedAmmo(carrier)
assert(armed == true and ammo == 24, "ammo is read from a magazine inside a carried bag")

-- Numbers decide before courage does.
local policy, reason = P.engageDecision({ enemies = 3, allies = 1 })
assert(policy == "rally" and reason == "outnumbered", "one against three goes to the rally")
policy, reason = P.engageDecision({ enemies = 2, allies = 1 })
assert(policy == "withdraw" and reason == "outnumbered", "one against two withdraws")
policy, reason = P.engageDecision({ enemies = 3, allies = 3 })
assert(policy == "engage" and reason == "fight", "even numbers still fight")
policy, reason = P.engageDecision({ enemies = 1, allies = 3, armed = true, ammo = 0 })
assert(policy == "rally" and reason == "no_ammo", "an empty gun ends the fight")
policy, reason = P.engageDecision({ enemies = 1, allies = 3, health = 20 })
assert(policy == "rally" and reason == "wounded", "a wounded fighter goes to the rally")
policy, reason = P.engageDecision({ enemies = 1, allies = 3, armedHuman = true, hasCover = false })
assert(policy == "hold" and reason == "exposed", "standing in the open against a gun is not an advance")

-- The real step, driven both ways: outnumbered goes to the rally, group against
-- group engages from cover.
local previousGetCell = getCell
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            local s = square(x, y, z)
            s.isBlockedTo = function(_, other)
                return other ~= nil and other:getX() == 8703
            end
            return s
        end,
    }
end
local free = function() return true end

local moves, rallies = {}, 0
local controller = {
    id = "defender",
    perceivedThreats = { a = {}, b = {}, c = {} },
    character = {
        getCurrentSquare = function() return square(8700, 8700, 0) end,
        getHealth = function() return 1.0 end,
        getInventory = function() return { getItems = function() return list({ bag }) end } end,
    },
    bridge = {
        moveNpc = function(_, id, target)
            moves[#moves + 1] = target
            return "MOVE_STARTED"
        end,
    },
    withdrawToRally = function() rallies = rallies + 1; return true end,
}
local attacker = {
    isZombie = function() return false end,
    getCurrentSquare = function() return square(8705, 8700, 0) end,
    isArmed = true,
}
assert(P.humanCombatStep(controller, attacker, 100, { free = free }) == true,
    "the outnumbered defender takes a decision")
assert(rallies == 1 and controller.breakOffReason == "outnumbered",
    "a solo survivor against a group falls back to the rally")

local even = {
    id = "even",
    baseId = "base-even",
    perceivedThreats = { a = {}, b = {}, c = {} },
    character = controller.character,
    bridge = controller.bridge,
}
assert(P.humanCombatStep(even, attacker, 200, { free = free }) == true,
    "an even fight takes a cover decision")
assert(even.activeDecision == "combat_take_cover",
    "the group fight moves through cover rather than straight in")

getCell = previousGetCell
Persistence.getBaseResidentIds = previousIds
