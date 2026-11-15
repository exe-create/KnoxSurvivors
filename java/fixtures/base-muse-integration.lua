-- Drives the real Controller:runBaseIdleChoice so the muse idle is proven to be
-- routed and to fall back, not just selected by the rotation.
local C = assert(KnoxAutonomyController)

local function mockAmbient(museResult, restResult, calls)
    local c = setmetatable({ calls = calls }, C)
    c.beginAmbientMusing = function()
        calls[#calls + 1] = "muse"
        return museResult
    end
    c.beginAmbientBaseRest = function()
        calls[#calls + 1] = "rest"
        return restResult
    end
    return c
end

-- 1. A muse choice starts the musing owner and nothing else.
local started = {}
local walker = mockAmbient(true, true, started)
assert(C.runBaseIdleChoice(walker, 100, "muse") == true, "the muse idle runs")
assert(#started == 1 and started[1] == "muse",
    "the muse path starts its own owner without a second activity")

-- 2. A missing spot or failed walk falls back to the existing rest owner.
local fell = {}
local blocked = mockAmbient(false, true, fell)
assert(C.runBaseIdleChoice(blocked, 100, "muse") == true, "a failed muse still owns an activity")
assert(#fell == 2 and fell[1] == "muse" and fell[2] == "rest",
    "a failed muse walk falls back to the existing rest path")

-- 3. The row is a moodle-derived line, not a fixed sentence.
assert(C.musingEvent({ pain = 3 }) == "base_musing_hurt")
assert(C.musingEvent({ hungry = 4 }) == "base_musing_hungry")
assert(C.musingEvent({ tired = 2 }) == "base_musing_tired")
assert(C.musingEvent({ panic = 2 }) == "base_musing_frightened")
-- 4. The real musing owner, not a mock: it walks, and when no walk is available
-- it hands over to the existing rest owner rather than standing still.
local realCalls = {}
local muser = setmetatable({
    id = "muser",
    baseId = "base-muse",
    base = { home = { minX = 8700, minY = 8700, maxX = 8705, maxY = 8705 } },
    character = {
        getCurrentSquare = function()
            return { getX = function() return 8702 end, getY = function() return 8702 end,
                getZ = function() return 0 end }
        end,
    },
}, { __index = C })
muser.feelState = function() return {} end
muser.beginBaseMovement = function()
    realCalls[#realCalls + 1] = "move"
    return false
end
muser.beginAmbientBaseRest = function()
    realCalls[#realCalls + 1] = "rest"
    return true
end
assert(C.beginAmbientMusing(muser, 500) == true,
    "a resident with nowhere to walk still takes an activity")
assert(realCalls[1] == "move" and realCalls[2] == "rest",
    "the real musing owner falls back to the existing rest path")
