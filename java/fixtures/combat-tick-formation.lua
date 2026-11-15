-- The formation step is proved from the real per-tick entry point, not by
-- calling squadStep directly. A hostile group and a resident party both reach it
-- through Controller:tick, a zombie target never does, and the combat branch
-- still takes shared cover.
local C = assert(KnoxAutonomyController)
local P = assert(KnoxCombatPositioning)
-- Another fixture replaces this projection globally; pin it so the tick reaches
-- the idle decision this fixture is about.
local previousRecoveryBusy = C.isNativeRecoveryBusy
C.isNativeRecoveryBusy = function() return false end
-- The vehicle owner returns the whole tick when it thinks a body is boarding;
-- a fixture body is not in a vehicle, so the owner is detached here.
local previousVehicles = rawget(_G, "KnoxCompanionVehicles")
_G.KnoxCompanionVehicles = nil
local Persistence = assert(KnoxPersistence)
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousGetCell = getCell
local previousIds = Persistence.getBaseResidentIds

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return x ~= 8690 end,
        isBlockedTo = function(_, other)
            return x == 8690 or (other ~= nil and other:getX() == 8690)
        end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
        getRoom = function() return nil end,
    }
end
getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return square(x, y, z) end,
        getZombieList = function() return { size = function() return 0 end } end,
    }
end

local function body(x, y)
    return setmetatable({
        getCurrentSquare = function() return square(x, y, 0) end,
        -- An unreadable action list reads as pending work in the real helper, which
        -- would stop the tick before the idle decision. Give it an empty one.
        getCharacterActions = function() return { isEmpty = function() return true end } end,
    }, { __index = function() return function() return false end end })
end

local moves = {}
local function bridge()
    return setmetatable({
        moveNpc = function(_, id, target) moves[#moves + 1] = target return "MOVE_STARTED" end,
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
        tickNpcCombat = function() return "COMBAT_WAITING" end,
        tickNpc = function() return "Succeeded" end,
    }, { __index = function() return function() return "" end end })
end

local thoughts = 0
local function controller(fields, x, y)
    local c = {
        id = "tick-fixture",
        state = "IDLE",
        nextThink = 0,
        nextThreatScan = 1000000,
        currentTicks = 0,
        counts = { needs = 0, combat = 0, failures = 0 },
        failedThreats = {},
        selfCareRetryAt = {},
        character = body(x, y),
        bridge = bridge(),
    }
    for key, value in pairs(fields) do c[key] = value end
    setmetatable(c, { __index = C })
    c.observeGroupEntry = function() end
    c.checkSharedMeal = function() return false end
    c.recoverIdleAnimationLatch = function() end
    c.applyPendingCombatPolicy = function() return true end
    c.tryBoardFollowVehicle = function() return false end
    -- Early arbitration owners that need a live body; each one is a no-op so the
    -- tick reaches the idle decision this fixture is about.
    c.recoverFromDetached = function() return false end
    c.updateBaseTaskAction = function() return false end
    c.waitingForTransferActions = function() return false end
    c.tryAutomaticPlayerAid = function() return false end
    c.yieldBaseTaskForNeed = function() return false end
    c.yieldInventoryCleanupForNeed = function() return false end
    c.yieldAidForNeed = function() return false end
    c.yieldCollectionForNeed = function() return false end
    c.isSettlementSupplyEntry = function() return false end
    c.canApplyDutyChange = function() return true end
    c.sharedMealPostureReady = function() return false end
    c.diag = function() end
    c.recordFailure = function() end
    c.finishDecision = function() end
    c.think = function() thoughts = thoughts + 1 end
    return c
end

local leader = body(8700, 8700)

local function raider(x, y)
    return controller({
        id = "raider-tick",
        groupLeader = leader,
        groupFormationSlot = 1,
        groupSize = 2,
    }, x, y)
end

-- 1. Out of slot: the real tick walks the raider to its slot.
local out = raider(8700, 8712)
out.groupMembers = { leader, out.character }
out:tick(100)
assert(#moves == 1 and moves[1]:getX() == 8700 and moves[1]:getY() == 8702,
    "the tick puts an out-of-slot raider on slot two")
assert(out.activeDecision == "squad_formation", "the tick records a formation move")

-- 2. In slot: no move, and the ordinary idle decision still runs.
moves, thoughts = {}, 0
local placed = raider(8700, 8702)
placed.groupMembers = { leader, placed.character }
placed:tick(200)
assert(#moves == 0, "a raider already in slot is not moved by the tick")
assert(thoughts == 1, "an in-slot raider still reaches its idle decision")

-- 3. Under fire: the tick widens the slot.
moves, thoughts = {}, 0
local pressed = raider(8700, 8712)
pressed.groupMembers = { leader, pressed.character }
pressed.perceivedThreats = { enemy = {} }
pressed:tick(300)
assert(#moves == 1 and moves[1]:getY() == 8704, "the tick widens spacing under fire")

-- 4. Re-forming after a break-off, still through the tick.
moves, thoughts = {}, 0
local broke = raider(8700, 8760)
broke.groupMembers = { leader, broke.character }
broke.breakOffReason = "outnumbered"
broke:tick(400)
assert(#moves == 1, "a broken-off raider re-forms through the tick")

-- 5. A resident party reaches the same step through the same tick.
moves, thoughts = {}, 0
Persistence.getBaseResidentIds = function() return { "lead", "me" } end
_G.KnoxSurvivorRuntime = {
    getCharacter = function(id)
        return id == "lead" and leader or nil
    end,
}
local resident = controller({ id = "me", baseId = "base-tick" }, 8700, 8712)
resident:tick(500)
assert(#moves == 1 and moves[1]:getX() == 8700 and moves[1]:getY() == 8702,
    "a resident reaches the formation slot through the tick")

-- 6. A zombie target is left alone: no formation move, ordinary decision runs.
moves, thoughts = {}, 0
local zombieFighter = raider(8700, 8712)
zombieFighter.groupMembers = { leader, zombieFighter.character }
zombieFighter.combatTarget = { isZombie = function() return true end,
    getCurrentSquare = function() return square(8704, 8700, 0) end,
    isDead = function() return false end }
zombieFighter:tick(600)
assert(#moves == 0, "a zombie target never triggers a formation move")
assert(zombieFighter.activeDecision ~= "squad_formation", "the zombie path keeps its own decision")
assert(thoughts == 1, "a fighter facing a zombie still takes its ordinary decision")

-- 7. The combat branch is unchanged and still uses the shared cover step.
moves, thoughts = {}, 0
local humanTarget = { isZombie = function() return false end,
    getCurrentSquare = function() return square(8710, 8700, 0) end,
    isArmed = true, isDead = function() return false end }
local fighter = controller({ id = "fighter-tick", state = "COMBAT", combatTarget = humanTarget }, 8680, 8700)
fighter:tick(700)
assert(#moves == 1 and P.coverFaces(moves[1], square(8710, 8700, 0)),
    "the real combat tick still moves to cover that faces the threat")

-- 8. With a zombie target the combat tick issues no cover move either.
moves, thoughts = {}, 0
local zombie = { isZombie = function() return true end,
    getCurrentSquare = function() return square(8710, 8700, 0) end,
    isDead = function() return false end }
local zombieCombat = controller({ id = "zombie-tick", state = "COMBAT", combatTarget = zombie }, 8680, 8700)
zombieCombat:tick(800)
assert(#moves == 0, "the zombie combat path gains no new movement")

getCell = previousGetCell
Persistence.getBaseResidentIds = previousIds
_G.KnoxSurvivorRuntime = previousRuntime
C.isNativeRecoveryBusy = previousRecoveryBusy
_G.KnoxCompanionVehicles = previousVehicles
