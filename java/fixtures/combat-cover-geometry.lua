-- Cover is chosen from geometry: the line between cover and threat must cross a
-- blocked edge. Room identity is no longer the test, and cover on the far side of
-- the threat is rejected because it does not block his line.
local P = assert(KnoxCombatPositioning)
local wall = { axis = "x", value = 8795 }

local previousGetCell = getCell

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function()
            if wall.axis == "x" then return x ~= wall.value end
            return y ~= wall.value
        end,
        isBlockedTo = function(_, other)
            local ox = other ~= nil and other:getX() or nil
            local oy = other ~= nil and other:getY() or nil
            if wall.axis == "x" then return x == wall.value or ox == wall.value end
            return y == wall.value or oy == wall.value
        end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
    }
end

getCell = function()
    return { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
end
local function free() return true end
local function actor(x, y) return { getCurrentSquare = function() return square(x, y, 0) end } end

-- 1. A wall between cover and threat is obstruction; open ground is not.
assert(P.lineBlocked(square(8794, 8790, 0), square(8800, 8790, 0)) == true,
    "a wall between cover and threat blocks the line")
assert(P.lineBlocked(square(8796, 8790, 0), square(8800, 8790, 0)) == false,
    "open ground beside the threat is not cover")

local threatSquare = square(8800, 8790, 0)
local cover = P.coverSquare(actor(8790, 8790), actor(8800, 8790), free)
assert(cover ~= nil, "a fighter on the threatened side finds cover")
assert(cover:getX() <= 8794, "cover never sits on the far side of the threat")
assert(P.coverFaces(cover, threatSquare) == true, "the chosen cover faces the actual threat")

local peek = P.peekSquare(cover, threatSquare, free)
wall = { axis = "x", value = 5000 }
assert(P.coverSquare(actor(8796, 8790), actor(8800, 8790), free) == nil,
    "flat ground offers no cover at all")
wall = { axis = "x", value = 8795 }
assert(peek ~= nil, "the fighter has a square to step out to")
assert(math.abs(peek:getX() - cover:getX()) + math.abs(peek:getY() - cover:getY()) == 1,
    "the peek is one step from cover, not a jump")

-- 2. The same rule applies to a fight inside a building.
wall = { axis = "y", value = 8793 }
local interiorCover = P.coverSquare(actor(8790, 8790), actor(8790, 8798), free)
assert(interiorCover ~= nil and interiorCover:getY() <= 8792,
    "an interior fight uses the same geometric cover rule")

-- 3. The real human step moves the fighter to cover against an armed human.
wall = { axis = "x", value = 8795 }
local moves = {}
local controller = {
    id = "fighter",
    perceivedThreats = {},
    character = {
        getCurrentSquare = function() return square(8790, 8790, 0) end,
        getHealth = function() return 1.0 end,
        getInventory = function() return { getItems = function() return { size = function() return 0 end } end } end,
    },
    bridge = {
        moveNpc = function(_, id, target)
            moves[#moves + 1] = target
            return "MOVE_STARTED"
        end,
    },
}
local human = {
    isZombie = function() return false end,
    getCurrentSquare = function() return square(8800, 8790, 0) end,
    isArmed = true,
}
assert(P.humanCombatStep(controller, human, 100, { free = free }) == true,
    "the human combat step takes a cover decision")
assert(#moves == 1 and P.coverFaces(moves[1], threatSquare),
    "the fighter moves to cover that faces the threat")

-- 4. One against three goes to the rally the alarm already picks.
local rallied = 0
controller.withdrawToRally = function() rallied = rallied + 1; return true end
controller.perceivedThreats = { a = {}, b = {}, c = {} }
assert(P.humanCombatStep(controller, human, 200, { free = free }) == true,
    "being outnumbered still takes a decision")
assert(rallied == 1 and controller.breakOffReason == "outnumbered",
    "one against three withdraws to the existing rally")

getCell = previousGetCell
