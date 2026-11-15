-- Drives the real Controller:raiseStructuralAlarm. A zombie working on the
-- building is the alarm condition; a zombie standing near it is not; another
-- home's thumper is not this site's problem; and the scan is throttled so a
-- horde cannot raise an alarm on every resident tick.
local C = assert(KnoxAutonomyController)

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

local function zombie(x, y, z, target)
    return {
        getCurrentSquare = function() return square(x, y, z) end,
        getThumpTarget = function() return target end,
    }
end

local function zombieList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

local current = {}
-- The fixture environment is shared with every other fixture this verifier runs:
-- the world binding is saved here and put back at the end of the file.
local previousGetCell = getCell
getCell = function()
    return { getZombieList = function() return zombieList(current) end }
end

local raised = 0
local controller = setmetatable({
    id = "alarm-one",
    baseId = "base-one",
    base = { home = { minX = 8700, minY = 8700, maxX = 8705, maxY = 8705 } },
    character = { getCurrentSquare = function() return square(8702, 8702, 0) end },
    soundBaseAlarm = function(self, at)
        raised = raised + 1
        self.alarmAt = at
        return true
    end,
}, { __index = C })

-- 1. A thumper against this home's wall raises the alarm that already answers.
current = { zombie(8707, 8702, 0, { id = "window" }) }
assert(controller:raiseStructuralAlarm(100) == true, "a thumping zombie raises the alarm")
assert(raised == 1, "the alarm is written once")
assert(controller.alarmAt ~= nil, "the alarm names the thumper's square")
assert(controller.nextStructuralAlarm == 160, "the scan is throttled after a detection")

-- 2. Throttled: a second detection inside the window changes nothing.
assert(controller:raiseStructuralAlarm(120) == false, "the scan is throttled per site")
assert(raised == 1, "no second alarm inside the throttle window")

-- 3. Near but not thumping is not an attack.
raised = 0
current = { zombie(8706, 8702, 0, nil) }
assert(controller:raiseStructuralAlarm(200) == false, "walking near the base is not an attack")
assert(raised == 0, "a zombie that is not thumping raises nothing")

-- 4. A thump far from this home belongs to another site.
current = { zombie(9000, 9000, 0, { id = "far" }) }
assert(controller:raiseStructuralAlarm(300) == false, "a distant thumper is not this base's alarm")
assert(raised == 0, "distance spares this site's alarm")

-- 5. A resident of no base raises nothing, and never crashes.
local wanderer = setmetatable({
    id = "alarm-two",
    baseId = nil,
    character = { getCurrentSquare = function() return square(1, 1, 0) end },
}, { __index = C })
assert(wanderer:raiseStructuralAlarm(400) == false, "a resident of no base raises nothing")

getCell = previousGetCell
