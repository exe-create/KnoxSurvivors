-- Wall-corner sidestep (user complaint: survivors stick on wall corners).
--
-- A corner-signature refusal (FAILED_BLOCKED_DIAGONAL / FAILED_STATIC_BLOCKAGE)
-- with no door to open used to re-issue the same corner-cutting route through
-- the bounded door retries, cancel it, and re-issue it: the visible stick.
-- The real handler must now step one tile orthogonally toward the goal inside
-- the same bounded budget and hold the follow; anything unavailable (no
-- bridge move, no free neighbor, combat, an unstarted move, an exhausted
-- budget) keeps the pre-existing path. Drives the real
-- handleFormationMovementFailure, not a restatement.
local C = assert(KnoxAutonomyController)
local saved = {}
for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    saved[name] = rawget(_G, name)
end
KnoxCompanionVehicles = nil

local DIAGONAL = "FailedObstacle:FAILED_BLOCKED_DIAGONAL"
local STATIC = "FailedObstacle:FAILED_STATIC_BLOCKAGE"

local geometry = {}
local function makeSquare(x, y, standable)
    local square = {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
        canStand = function() return standable and geometry[x .. "," .. y] ~= "solid" end,
        isSolid = function() return geometry[x .. "," .. y] == "solid_standable" end,
        isSolidTrans = function()
            if geometry[x .. "," .. y] == "unreadable_furniture" then error("unloaded square") end
            return geometry[x .. "," .. y] == "furniture"
        end,
        TreatAsSolidFloor = function() return geometry[x .. "," .. y] ~= "no_floor" end,
        HasStairs = function() return geometry[x .. "," .. y] == "stairs" end,
        isBlockedTo = function() return geometry[x .. "," .. y] == "wall" end,
        isWindowTo = function() return geometry[x .. "," .. y] == "window" end,
        isHoppableTo = function() return geometry[x .. "," .. y] == "fence" end,
        getRoom = function() return geometry[x .. "," .. y] == "other_room" and "other" or nil end,
        getMovingObjects = function() return {
            size = function() return geometry[x .. "," .. y] == "occupied" and 1 or 0 end,
            get = function() return {} end,
        } end,
    }
    if geometry[x .. "," .. y] == "unknown_edge" then square.isBlockedTo = nil end
    return square
end
-- Survivor at (10,10); the goal beyond the corner at (12,12). The (10,11)
-- edge is wall; the free orthogonal neighbors rank (11,10) first.
local standable = { ["11,10"] = true, ["9,10"] = true, ["10,9"] = true }
local function cellFor()
    return {
        getGridSquare = function(_, x, y, z)
            if z ~= 0 then return nil end
            if x == 10 and y == 10 then return makeSquare(x, y, true) end
            if x == 12 and y == 12 then return makeSquare(x, y, true) end
            if x == 8 and y == 12 then return makeSquare(x, y, true) end
            if standable[x .. "," .. y] then return makeSquare(x, y, true) end
            return nil
        end,
    }
end
getCell = function() return cellFor() end

local function sidestepController(state, opts)
    opts = opts or {}
    local selfSquare = makeSquare(10, 10, true)
    local moves, cancelled = {}, false
    local c = setmetatable({
        id = "contract-corner",
        state = state,
        observedState = state,
        stateStartedAt = 100,
        nextThink = math.huge,
        nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge,
        counts = { search = 0 },
        combatTarget = opts.combatTarget,
        character = {
            getCurrentSquare = function() return selfSquare end,
            getCharacterActions = function() return nil end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
        },
        bridge = {
            moveNpcWithPace = function(_, _, target, pace)
                moves[#moves + 1] = { x = target:getX(), y = target:getY(), pace = pace }
                return opts.moveResult or "MOVE_STARTED"
            end,
            cancelNpcMove = function() cancelled = true end,
        },
    }, C)
    c.applyPendingCombatPolicy = function() return true end
    c.recordFailure = function(self2, reason) self2.failure = reason end
    if opts.noBridgeMove then c.bridge.moveNpcWithPace = nil end
    return c, moves, function() return cancelled end
end
local goal = makeSquare(12, 12, true)

for _, state in ipairs({ "GROUP_FOLLOW", "COMPANION_FOLLOW" }) do
    local c, moves = sidestepController(state)
    assert(c:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100,
        state == "COMPANION_FOLLOW", goal) == true,
        "a corner refusal steps instead of stalling (" .. state .. ")")
    assert(#moves == 1 and moves[1].x == 11 and moves[1].y == 10,
        "the sidestep takes the free orthogonal neighbor toward the goal (" .. state .. ")")
    assert(c.state == state,
        "the sidestep holds the follow instead of parking in WAIT (" .. state .. ")")
    assert(c.formationDoorRetry ~= nil and c.formationDoorRetry.count == 1,
        "the sidestep consumes the same bounded budget (" .. state .. ")")
    assert(c.failure == "formation_corner:TICK_FAILED",
        "the sidestep is recorded as a corner, not a door (" .. state .. ")")
    assert(c.formationTargetX == 11 and c.formationTargetY == 10,
        "the sidestep becomes the formation target (" .. state .. ")")
end

local static, staticMoves = sidestepController("GROUP_FOLLOW")
static:handleFormationMovementFailure("TICK_FAILED:" .. STATIC, 100, false, goal)
assert(#staticMoves == 1 and staticMoves[1].x == 11 and staticMoves[1].y == 10
    and static.state == "GROUP_FOLLOW",
    "a static blockage steps around the corner the same way")

-- The real tick supplies only the failure text. The stored route must decide
-- the direction, including a western goal where an unconditional east step
-- would put the survivor on the wrong side of the corner again.
local west, westMoves = sidestepController("GROUP_FOLLOW")
west.formationTargetX, west.formationTargetY, west.formationTargetZ = 8, 12, 0
west:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100)
assert(#westMoves == 1 and westMoves[1].x == 9 and westMoves[1].y == 10,
    "a tick failure without a goal argument uses the accepted western destination")

for _, obstruction in ipairs({ "wall", "window", "fence", "no_floor", "stairs",
    "solid", "solid_standable", "furniture", "unreadable_furniture",
    "other_room", "occupied", "unknown_edge" }) do
    geometry["11,10"] = obstruction
    local c, moves = sidestepController("GROUP_FOLLOW")
    c:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, false, goal)
    assert(#moves == 1 and moves[1].x == 9 and moves[1].y == 10,
        "a standable neighbour behind " .. obstruction .. " is never a recovery step")
end
geometry["11,10"] = nil
local unknown, unknownMoves = sidestepController("GROUP_FOLLOW")
unknown:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100)
assert(#unknownMoves == 0, "a missing route goal never guesses a sidestep direction")

-- No free neighbor: the old bounded hold runs untouched.
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x == 10 and y == 10 and z == 0 then return makeSquare(x, y, true) end
        return nil
    end }
end
local boxed, boxedMoves = sidestepController("COMPANION_FOLLOW")
assert(boxed:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, true, goal) == true
    and #boxedMoves == 0 and boxed.state == "COMPANION_FOLLOW"
    and boxed.formationDoorRetry.count == 1 and boxed.failure == "formation_door:TICK_FAILED",
    "with no free neighbor the corner keeps the old bounded hold")
getCell = function() return cellFor() end

-- Combat never sidesteps: the existing handling owns a fighting body.
local fighting, fightingMoves = sidestepController("COMPANION_FOLLOW", { combatTarget = {} })
assert(fighting:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, true, goal) == true
    and #fightingMoves == 0 and fighting.state == "COMPANION_FOLLOW",
    "a fighting survivor keeps the existing handling, not a sidestep")

-- An unstarted sidestep move keeps the existing handling too.
local stall, stallMoves = sidestepController("GROUP_FOLLOW", { moveResult = "MOVE_FAILED" })
assert(stall:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, false, goal) == true
    and #stallMoves == 1 and stall.state == "GROUP_FOLLOW"
    and stall.formationDoorRetry.count == 1 and stall.failure == "formation_door:TICK_FAILED",
    "an unstarted sidestep falls back to the old bounded hold")

-- An exhausted budget still escalates instead of looping the corner.
local spent, spentMoves, spentCancelled = sidestepController("GROUP_FOLLOW")
spent.formationDoorRetry = { count = 3 }
assert(spent:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, false, goal) ~= true
    and #spentMoves == 0 and spent.state == "GROUP_WAIT" and spentCancelled(),
    "an exhausted corner budget still escalates instead of looping")

-- A welded-shut corner (no bridge move at all) is the pre-fix shape: hold,
-- budget, then escalate - never a crash, never a silent stall.
local legacy, legacyMoves = sidestepController("GROUP_FOLLOW", { noBridgeMove = true })
assert(legacy:handleFormationMovementFailure("TICK_FAILED:" .. DIAGONAL, 100, false, goal) == true
    and #legacyMoves == 0 and legacy.state == "GROUP_FOLLOW"
    and legacy.formationDoorRetry.count == 1,
    "without a bridge move the corner keeps the old bounded hold")

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    if saved[name] == nil then rawset(_G, name, nil) else _G[name] = saved[name] end
end
print("Corner sidestep PASS step=true hold=true budget=true record=true fallback=true combatKept=true escalate=true")
