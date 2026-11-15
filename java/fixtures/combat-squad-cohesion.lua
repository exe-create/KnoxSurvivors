-- Drives the real Controller:squadStep, which the combat tick calls. Members walk
-- their own formation slots behind the leader and re-form after a break-off.
local C = assert(KnoxAutonomyController)
local P = assert(KnoxCombatPositioning)
local Persistence = assert(KnoxPersistence)

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
        getMovingObjects = function() return { size = function() return 0 end } end,
    }
end

local previousGetCell = getCell
local previousIds = Persistence.getBaseResidentIds
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")

getCell = function()
    return { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
end
Persistence.getBaseResidentIds = function() return { "leader", "member" } end
_G.KnoxSurvivorRuntime = {
    getCharacter = function(id)
        if id == "leader" then
            return { getCurrentSquare = function() return square(8700, 8700, 0) end }
        end
        return nil
    end,
}

local moves = {}
local function member(x, y)
    return setmetatable({
        id = "member",
        baseId = "base-squad",
        state = "BASE_IDLE",
        breakOffReason = "wounded",
        character = { getCurrentSquare = function() return square(x, y, 0) end },
        bridge = {
            moveNpc = function(_, id, target)
                moves[#moves + 1] = target
                return "MOVE_STARTED"
            end,
        },
    }, { __index = C })
end

-- 1. A member out of position walks to its slot, not onto the leader.
local far = member(8700, 8710)
assert(far:squadStep(100) == true, "an out-of-position member moves to its slot")
local walked = moves[1]
assert(walked ~= nil and walked:getX() == 8700 and walked:getY() == 8702,
    "the member takes slot two behind the leader")
assert(far.activeDecision == "squad_formation", "the move is a formation move")
assert(not (walked:getX() == 8700 and walked:getY() == 8700),
    "no member paths onto the leader's tile")

-- 2. A member already in slot does not shuffle.
moves = {}
local placed = member(8700, 8702)
assert(placed:squadStep(200) == false, "a member in slot holds position")
assert(#moves == 0, "holding position issues no movement")

-- 3. Spacing widens under fire.
moves = {}
local pressed = member(8700, 8710)
pressed.baseUnderFire = true
assert(pressed:squadStep(300) == true, "a pressed member still takes its slot")
assert(moves[1]:getY() == 8704, "spacing widens under fire")

-- 3b. The same widening comes from the threat memory the controller already
-- keeps, so a resident that has seen an enemy spreads out without a new flag.
moves = {}
local watched = member(8700, 8710)
watched.perceivedThreats = { zed = {} }
assert(watched:squadStep(350) == true, "a resident that has seen an enemy still moves")
assert(moves[1]:getY() == 8704, "seeing a threat widens spacing without a new flag")

-- 4. Re-forming after a break-off: no fight left, still belongs to the squad.
moves = {}
local broke = member(8700, 8740)
broke.combatTarget = nil
broke.breakOffReason = "outnumbered"
assert(broke:squadStep(400) == true, "a broken-off member re-forms")
assert(#moves == 1, "re-forming is one move, not a chase")

-- 5. Slots themselves are pure offsets in the same module.
local x, y = P.squadSlot(100, 100, 1, 2, "column")
assert(x == 100 and y == 100, "the leader slot is the leader")
x, y = P.squadSlot(100, 100, 2, 2, "column")
assert(x == 100 and y == 102, "column slot two is one step behind")
x, y = P.squadSlot(100, 100, 3, 4, "line")
assert(x == 108 and y == 100, "line slots are side by side at the given spacing")
assert(P.squadSpacing(true, false) > P.squadSpacing(false, true),
    "under fire is wider than on the approach")

getCell = previousGetCell
Persistence.getBaseResidentIds = previousIds
_G.KnoxSurvivorRuntime = previousRuntime

-- 6. A party answers a fight as one body, and an idle body never freezes.
local fighter = {
    getCurrentSquare = function() return square(8703, 8700, 0) end,
    isAttacking = function() return true end,
    isDead = function() return false end,
}
local idle = member(8700, 8700)
assert(idle:combatGroupPresent() == false, "a survivor alone is not a party")
idle.groupMembers = { fighter }
assert(idle:combatGroupPresent() == true, "a living ally makes the party present")
assert(idle:groupCombatRallyMember(500) == fighter,
    "a nearby fighting ally is the rally point")
idle.groupMembers = {}
assert(idle:groupCombatRallyMember(500) == nil,
    "no fighting ally means no rally call")
moves = {}
local previousFinder = AdjacentFreeTileFinder
AdjacentFreeTileFinder = { Find = function() return square(8701, 8700, 0) end }
assert(idle:beginIdleReposition(1000) == true,
    "an idle survivor shifts position instead of standing still")
assert(#moves == 1 and idle.activeDecision == "idle_reposition",
    "the shift is one bounded move, not a patrol")
assert(idle:beginIdleReposition(1001) == false,
    "the idle shift holds its cooldown")
AdjacentFreeTileFinder = previousFinder
