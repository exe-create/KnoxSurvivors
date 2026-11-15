-- A failed native approach must not become a wall-grind loop. Pursuit picks an
-- approach square next to the target with no blocked-line check, and the
-- scan cooldown is cleared on every issue, so a wall-separated target
-- re-issues the same blocked line while the door beside the survivor is
-- never used. A bare wall between the fighters refuses the route (keeping
-- the caller's failure cooldown); doors, windows and fences keep their
-- owners; an identical in-flight pursuit is never stacked.
local C = assert(KnoxAutonomyController)
local P = assert(KnoxCombatPositioning)
local saved = {}
for _, name in ipairs({ "getCell", "instanceof" }) do
    saved[name] = rawget(_G, name)
end

local function square(x, y, opts)
    opts = opts or {}
    local edges = opts.edges or {}
    local self = {}
    self.getX = function() return x end
    self.getY = function() return y end
    self.getZ = function() return 0 end
    self.canStand = function() return true end
    self.isBlockedTo = function(_, other)
        return edges[other:getX() .. "," .. other:getY()] == true
    end
    self.isHoppableTo = function(_, other)
        return (opts.hop or {})[other:getX() .. "," .. other:getY()] == true
    end
    self.getDoorTo = function(_, other)
        local door = (opts.doors or {})[other:getX() .. "," .. other:getY()]
        return door
    end
    self.getWindowTo = function(_, other)
        return (opts.windows or {})[other:getX() .. "," .. other:getY()]
    end
    self.getWindowFrameTo = function() return nil end
    return self
end

-- Survivor at (5,5), zombie at (5,8). The straight line crosses (5,6).
local grid = {}
local function floorSquare(x, y)
    local key = x .. "," .. y
    if grid[key] == nil then grid[key] = square(x, y) end
    return grid[key]
end
local survivorSquare = floorSquare(5, 5)
local zombieSquare = floorSquare(5, 8)
for dx = -1, 1 do
    for dy = -1, 1 do
        floorSquare(5 + dx, 8 + dy)
    end
end
floorSquare(5, 6)
floorSquare(5, 7)
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if z ~= 0 then return nil end
            return grid[x .. "," .. y]
        end,
    }
end
instanceof = function() return false end

local zombie = {
    getCurrentSquare = function() return zombieSquare end,
    isDead = function() return false end,
}
local moves = 0
local movedTo = nil
local controller = setmetatable({
    id = "pursuit-fixture",
    character = {
        getCurrentSquare = function() return survivorSquare end,
    },
    bridge = {
        moveNpc = function(_, _, target)
            moves = moves + 1
            movedTo = target
            return "MOVE_STARTED"
        end,
    },
    failedThreats = {},
}, C)

-- Bare wall between the fighters: no route, cooldown kept, no grind.
grid["5,5"] = square(5, 5, { edges = { ["5,6"] = true } })
grid["5,6"] = square(5, 6, { edges = { ["5,5"] = true, ["5,7"] = true } })
survivorSquare = grid["5,5"]
controller.character.getCurrentSquare = function() return survivorSquare end
controller.failedThreats[zombie] = 4242
assert(P.wallBlockedLine(survivorSquare, zombieSquare),
    "a straight wall between the fighters reads as wall-blocked")
assert(controller:beginCombatPursuit(zombie, 100, "APPROACH") == false,
    "a wall-separated pursuit refuses the doomed route")
assert(moves == 0, "the refused pursuit issues no movement into the wall")
assert(controller.failedThreats[zombie] == 4242,
    "the refused pursuit keeps the scan backoff instead of clearing it")

-- Open line: unchanged, route issued and cooldown cleared for re-engage.
grid["5,5"] = square(5, 5)
grid["5,6"] = square(5, 6)
survivorSquare = grid["5,5"]
controller.failedThreats[zombie] = 4242
assert(not P.wallBlockedLine(survivorSquare, zombieSquare),
    "an open line reads as routable")
assert(controller:beginCombatPursuit(zombie, 300, "APPROACH") == true,
    "an open-line pursuit still walks the survivor in")
assert(moves == 1, "the open-line pursuit issues exactly one route")
assert(controller.failedThreats[zombie] == nil,
    "the issued pursuit clears the cooldown so the scan re-engages up close")
assert(movedTo ~= nil and math.abs(movedTo:getX() - 5) <= 1
    and math.abs(movedTo:getY() - 8) <= 1,
    "the pursuit destination stays next to the target")

-- A door on the blocked step keeps the door owner, not the refusal.
local door = { IsOpen = function() return false end }
grid["5,5"] = square(5, 5, { edges = { ["5,6"] = true }, doors = { ["5,6"] = door } })
survivorSquare = grid["5,5"]
controller.failedThreats[zombie] = 4242
assert(not P.wallBlockedLine(survivorSquare, zombieSquare),
    "a door on the line is not a wall")
assert(controller:beginCombatPursuit(zombie, 500, "APPROACH") == true,
    "a door-separated pursuit still routes so door recovery can engage")
assert(moves == 2, "the door-separated pursuit issues its route")

-- A fence on the line keeps the vault path: same routing, no refusal.
grid["5,5"] = square(5, 5, { edges = { ["5,6"] = true }, hop = { ["5,6"] = true } })
survivorSquare = grid["5,5"]
controller.failedThreats[zombie] = 4242
assert(not P.wallBlockedLine(survivorSquare, zombieSquare),
    "a hoppable edge on the line is not a wall")
assert(controller:beginCombatPursuit(zombie, 700, "APPROACH") == true,
    "a fence-separated pursuit still routes to the vault")

-- A window on the line keeps the climb path.
grid["5,5"] = square(5, 5, { edges = { ["5,6"] = true }, windows = { ["5,6"] = {} } })
survivorSquare = grid["5,5"]
controller.failedThreats[zombie] = 4242
assert(not P.wallBlockedLine(survivorSquare, zombieSquare),
    "a window on the line is not a wall")
assert(controller:beginCombatPursuit(zombie, 900, "APPROACH") == true,
    "a window-separated pursuit still routes to the climb")

-- An identical in-flight pursuit is never stacked.
grid["5,5"] = square(5, 5)
survivorSquare = grid["5,5"]
local before = moves
controller.failedThreats[zombie] = 4242
assert(controller:beginCombatPursuit(zombie, 901, "APPROACH") == false,
    "an identical pursuit inside its window does not restart the route")
assert(moves == before, "the stacked pursuit issues no second route")
assert(controller.failedThreats[zombie] == 4242,
    "the stacked pursuit keeps the backoff instead of clearing it")

for _, name in ipairs({ "getCell", "instanceof" }) do
    _G[name] = saved[name]
end
print("Combat pursuit door PASS wall_refused=true owners_kept=true stack_held=true")
