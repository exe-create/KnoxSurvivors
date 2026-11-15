-- Drives the real Controller:raiseStructuralAlarm and the real alarm writer. The
-- bug this covers: the writer only admitted a square inside the building, so a
-- zombie thumping the outside wall, or a hostile person at the fence, raised
-- nothing and the residents sat until the barrier failed.
local C = assert(KnoxAutonomyController)
-- The base manager is not loaded in every fixture run; the alarm falls back to
-- the perimeter test when it is absent, so the stub is optional.
local BaseManager = rawget(_G, "KnoxBaseManager")

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

local function zed(x, y, z, target)
    return {
        getCurrentSquare = function() return square(x, y, z) end,
        getThumpTarget = function() return target end,
    }
end

local function zedList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

-- Save everything this fixture replaces, and put it back at the end.
local previousGetCell = getCell
local previousContains = BaseManager ~= nil and BaseManager.containsSquare or nil
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousRecord = KnoxPersistence.getSurvivorCreatorRecord
local previousDuty = KnoxPersistence.getSurvivorDuty

local zombies = {}
getCell = function()
    return { getZombieList = function() return zedList(zombies) end }
end
-- The base manager says a square outside the walls is not inside the home; the
-- perimeter test is what must admit it.
if BaseManager ~= nil then
    BaseManager.containsSquare = function() return false end
end

local function controller(home)
    return setmetatable({
        id = "defender-one",
        baseId = "base-perimeter",
        currentTicks = 1000,
        base = { home = home },
        character = { getCurrentSquare = function() return square(8702, 8702, 0) end },
    }, { __index = C })
end

local home = { minX = 8700, minY = 8700, maxX = 8705, maxY = 8705 }
local guard = controller(home)

-- 1. A zombie working on the outside wall raises the alarm.
zombies = { zed(8707, 8702, 0, { id = "window" }) }
assert(guard:raiseStructuralAlarm(1000) == true,
    "a thumper against the outside wall raises the base alarm")
assert(guard.nextStructuralAlarm == 1060, "the perimeter scan is throttled")

-- 2. The perimeter is the base bounds opened by a margin, and no wider.
assert(C.perimeterContains(home, square(8711, 8702, 0), 8) == true,
    "a square six tiles out is still the base perimeter")
assert(C.perimeterContains(home, square(8730, 8702, 0), 8) == false,
    "a square across the street is not the base perimeter")
assert(C.perimeterContains(home, nil, 8) == false, "no square is not a threat")
assert(C.basePerimeter(home, 8).minX == 8692, "the perimeter opens the bounds symmetrically")

-- 3. A hostile person at the fence raises the same alarm, without being inside.
zombies = {}
guard.nextStructuralAlarm = 0
local raider = { getCurrentSquare = function() return square(8711, 8702, 0) end }
_G.KnoxSurvivorRuntime = {
    activeIds = function() return { "defender-one", "raider" } end,
    getCharacter = function(id) return id == "raider" and raider or nil end,
}
KnoxPersistence.getSurvivorCreatorRecord = function(id)
    return id == "raider" and { attitude = "hostile" } or { attitude = "friendly" }
end
KnoxPersistence.getSurvivorDuty = function() return { mode = "base", baseId = "other-base" } end
assert(guard:raiseStructuralAlarm(1100) == true,
    "a hostile human at the fence raises the base alarm")

-- 4. A resident of the same base is not a threat, however close it stands.
guard.nextStructuralAlarm = 0
KnoxPersistence.getSurvivorDuty = function() return { mode = "base", baseId = "base-perimeter" } end
assert(guard:raiseStructuralAlarm(1200) == false,
    "the base's own resident never raises an alarm against itself")

getCell = previousGetCell
if BaseManager ~= nil then
    BaseManager.containsSquare = previousContains
end
_G.KnoxSurvivorRuntime = previousRuntime
KnoxPersistence.getSurvivorCreatorRecord = previousRecord
KnoxPersistence.getSurvivorDuty = previousDuty
