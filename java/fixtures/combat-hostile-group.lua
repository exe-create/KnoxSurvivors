-- A hostile survivor group is a party the controller already carries: leader
-- plus members. It moves through the same squadStep and fights through the same
-- humanCombatStep as a resident group, with no second formation or defence state.
local C = assert(KnoxAutonomyController)
local P = assert(KnoxCombatPositioning)
local Persistence = assert(KnoxPersistence)
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousGetCell = getCell
local previousIds = Persistence.getBaseResidentIds

local rosterReads = 0
Persistence.getBaseResidentIds = function() rosterReads = rosterReads + 1 return {} end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return x ~= 8630 end,
        isBlockedTo = function(_, other)
            return x == 8630 or (other ~= nil and other:getX() == 8630)
        end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
    }
end
getCell = function()
    return { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
end
local free = function() return true end

local leaderCharacter = { getCurrentSquare = function() return square(8600, 8600, 0) end }
_G.KnoxSurvivorRuntime = {
    idForCharacter = function(character) return character ~= nil and character.id or nil end,
    getController = function(id) return rawget(_G, "__combatControl" .. tostring(id)) end,
}

local moves = {}
local function hostileGroupMember(x, y)
    return setmetatable({
        id = "raider-2",
        state = "BASE_IDLE",
        breakOffReason = "outnumbered",
        groupLeader = leaderCharacter,
        groupFormationSlot = 1,
        groupSize = 2,
        character = { getCurrentSquare = function() return square(x, y, 0) end },
        bridge = {
            moveNpc = function(_, id, target)
                moves[#moves + 1] = target
                return "MOVE_STARTED"
            end,
        },
    }, { __index = C })
end

-- 1. The group's own ids drive the slot: no base roster involved.
local raider = hostileGroupMember(8600, 8612)
raider.groupMembers = { leaderCharacter, raider.character }
assert(raider:squadStep(100) == true, "a hostile group member walks to its slot")
assert(moves[1] ~= nil and moves[1]:getY() == 8602, "the raider takes slot two behind its leader")
assert(not (moves[1]:getX() == 8600 and moves[1]:getY() == 8600),
    "a raider never paths onto the leader's tile")
assert(rosterReads == 0, "a hostile group is not read through the base roster")

-- 2. In slot: hold.
moves = {}
local placed = hostileGroupMember(8600, 8602)
placed.groupMembers = { leaderCharacter, placed.character }
assert(placed:squadStep(200) == false, "a raider in slot holds position")
assert(#moves == 0, "holding issues no movement")

-- 3. Under fire the group spreads; on the approach it closes up.
moves = {}
local pressed = hostileGroupMember(8600, 8612)
pressed.groupMembers = { leaderCharacter, pressed.character }
pressed.perceivedThreats = { enemy = {} }
assert(pressed:squadStep(300) == true, "a pressed raider still takes its slot")
assert(moves[1]:getY() == 8604, "a raider group widens under fire")

moves = {}
local closing = hostileGroupMember(8600, 8603)
closing.groupMembers = { leaderCharacter, closing.character }
closing.combatTarget = { getCurrentSquare = function() return square(8604, 8600, 0) end }
assert(closing:squadStep(400) == true, "a closing raider still takes its slot")
assert(moves[1]:getY() == 8601, "the group closes up on the approach")

-- 4. After a break-off the group re-forms.
moves = {}
local broke = hostileGroupMember(8600, 8660)
broke.groupMembers = { leaderCharacter, broke.character }
assert(broke:squadStep(500) == true, "a broken-off raider re-forms")
assert(#moves == 1, "re-forming is one move, not a chase")

-- 5. Group against group: both sides move to cover that faces the threat, and
-- the target's group is counted, so a lone raider falls back instead of walking in.
local survivorLeader = { getCurrentSquare = function() return square(8620, 8620, 0) end }
local hostileLeader = { getCurrentSquare = function() return square(8640, 8620, 0) end }

local function items()
    return { size = function() return 0 end }
end

local survivorSquare, hostileSquare = square(8620, 8620, 0), square(8640, 8620, 0)
local survivorMoves, hostileMoves = {}, {}
local survivorCharacter = {
    id = "survivor-1",
    getCurrentSquare = function() return square(8620, 8620, 0) end,
    getHealth = function() return 1.0 end,
    getInventory = function() return { getItems = items } end,
}
local hostileCharacter = {
    id = "raider-1",
    getCurrentSquare = function() return square(8640, 8620, 0) end,
    getHealth = function() return 1.0 end,
    getInventory = function() return { getItems = items } end,
}
local survivor = {
    id = "survivor-1", groupSize = 3, perceivedThreats = {},
    character = survivorCharacter,
    bridge = { moveNpc = function(_, id, target) survivorMoves[#survivorMoves + 1] = target return "MOVE_STARTED" end },
    withdrawToRally = function() return true end,
}
local hostile = {
    id = "raider-1", groupSize = 3, perceivedThreats = {},
    character = hostileCharacter,
    bridge = { moveNpc = function(_, id, target) hostileMoves[#hostileMoves + 1] = target return "MOVE_STARTED" end },
    withdrawToRally = function() return true end,
}
_G["__combatControlraider-1"] = hostile
_G["__combatControlsurvivor-1"] = survivor
local survivorTarget = {
    id = "survivor-1", isZombie = function() return false end,
    getCurrentSquare = function() return hostileSquare end, isArmed = true,
}
local hostileTarget = { isZombie = function() return false end, getCurrentSquare = function() return survivorSquare end, isArmed = true }
survivor.character.id = "survivor-1"
hostile.character.id = "raider-1"

assert(P.humanCombatStep(survivor, survivorTarget, 600, { free = free }) == true,
    "the survivor side takes a cover decision against a hostile group")
assert(P.humanCombatStep(hostile, hostileTarget, 600, { free = free }) == true,
    "the hostile side takes a cover decision against the survivor group")
assert(#survivorMoves == 1 and P.coverFaces(survivorMoves[1], hostileSquare),
    "the survivor moves to cover facing the hostile group")
assert(#hostileMoves == 1 and P.coverFaces(hostileMoves[1], survivorSquare),
    "the hostile group moves to cover facing the survivors")

-- 6. A lone raider against a group of three uses the enemy group count.
local rallied = 0
local lone = {
    id = "raider-lone", groupSize = 1, perceivedThreats = {},
    character = {
        id = "raider-lone",
        getCurrentSquare = function() return square(8620, 8620, 0) end,
        getHealth = function() return 1.0 end,
        getInventory = function() return { getItems = items } end,
    },
    bridge = { moveNpc = function() return "MOVE_STARTED" end },
    withdrawToRally = function() rallied = rallied + 1 return true end,
}
_G["__combatControlsurvivor-1"] = { groupSize = 3 }
assert(P.humanCombatStep(lone, survivorTarget, 700, { free = free }) == true,
    "a lone raider still takes a decision")
assert(rallied == 1 and lone.breakOffReason == "outnumbered",
    "a lone raider against three falls back to the rally")

getCell = previousGetCell
Persistence.getBaseResidentIds = previousIds
_G.KnoxSurvivorRuntime = previousRuntime
_G["__combatControlraider-1"] = nil
_G["__combatControlsurvivor-1"] = nil
