-- Self-defense answers at the same distance as player defense: a zombie that
-- has acquired the survivor engages out to twelve tiles, not just inside
-- the old eight. Ambient zombies beyond the base radius stay ignored, so
-- this grants no map-wide aggression. Drives the real evaluateCombatThreat.
local C = assert(KnoxAutonomyController)
local oldSettings, oldRuntime = rawget(_G, "KnoxSettings"), rawget(_G, "KnoxSurvivorRuntime")
local oldSpecific, oldNum = getSpecificPlayer, getNumActivePlayers
KnoxSettings = { zombieEngagementDistance = function() return 4 end }
KnoxSurvivorRuntime = { idForCharacter = function() return nil end }
getSpecificPlayer = function() return nil end
getNumActivePlayers = function() return 0 end

local function sq(x)
    return { getX = function() return x end, getY = function() return 10 end, getZ = function() return 0 end }
end
local bodySq = sq(0)
local body = { getCurrentSquare = function() return bodySq end,
    isDead = function() return false end,
    CanSee = function() return true end }
local function control()
    return setmetatable({ id = "defense-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = nil, groupLeader = nil, groupMembers = {} },
        { __index = C })
end
local function zombieAt(x, target)
    return { getCurrentSquare = function() return sq(x) end,
        isDead = function() return false end,
        getTarget = function() return target end }
end

local acquired = control():evaluateCombatThreat(zombieAt(10, body), 100)
assert(acquired ~= nil and acquired.reason == "active_target" and acquired.priority == 5,
    "a zombie targeting the survivor ten tiles out is answered")
local edge = control():evaluateCombatThreat(zombieAt(12, body), 100)
assert(edge ~= nil,
    "twelve tiles is still self-defense")
assert(control():evaluateCombatThreat(zombieAt(13, body), 100) == nil,
    "thirteen tiles waits instead of hunting")
local ambient = control():evaluateCombatThreat(zombieAt(10, nil), 100)
assert(ambient == nil,
    "an unbothered zombie ten tiles out is still ignored")
local close = control():evaluateCombatThreat(zombieAt(3, nil), 100)
assert(close ~= nil and close.reason == "immediate",
    "the base radius still answers what is close")

KnoxSettings, KnoxSurvivorRuntime = oldSettings, oldRuntime
getSpecificPlayer, getNumActivePlayers = oldSpecific, oldNum
print("Self defense range PASS selfTwelve=true ambientIgnored=true closeKept=true")
