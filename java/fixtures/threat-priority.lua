-- Two owner reports from 2026-11-12, both driven through the real threat scan:
-- 1. "properly prioritize closest/highest threats" - a zombie closing on the
--    survivor must outrank a distant zombie that merely has the player's name
--    on it, or the survivor walks off to help and gets caught from behind.
-- 2. "hostile I shoved only attacked me but didn't prio my companion" - a
--    factionless survivor made personally hostile to the player is answered
--    by the player's own companion, not read as neutral.
local C = assert(KnoxAutonomyController)
local oldPersistence, oldSettings, oldRuntime =
    KnoxPersistence, rawget(_G, "KnoxSettings"), rawget(_G, "KnoxSurvivorRuntime")
local oldSpecific, oldNum = getSpecificPlayer, getNumActivePlayers

local function sq(x, y, z)
    return { getX = function() return x end,
        getY = function() return y or 10 end,
        getZ = function() return z or 0 end }
end
local selfSq = sq(0)
local playerSq = sq(0)
local body = { getCurrentSquare = function() return selfSq end,
    isDead = function() return false end,
    CanSee = function() return true end }
local player = { getCurrentSquare = function() return playerSq end,
    isDead = function() return false end,
    getTarget = function() return nil end }

KnoxSettings = { zombieEngagementDistance = function() return 4 end }
KnoxSurvivorRuntime = { idForCharacter = function() return nil end }
getSpecificPlayer = function(i) return i == 0 and player or nil end
getNumActivePlayers = function() return 1 end
KnoxPersistence = {
    getSurvivorAffiliation = function() return nil end,
    ensurePlayerId = function() return "player-1" end,
    isSurvivorHostileToPlayer = function() return false end,
}
local function control()
    return setmetatable({ id = "companion-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = "follow", companionTarget = player,
        groupLeader = nil, groupMembers = {} },
        { __index = C })
end
local function zombieAt(x, target)
    return { getCurrentSquare = function() return sq(x) end,
        isDead = function() return false end,
        getTarget = function() return target end }
end

-- Priority: a zombie six tiles away closing on the survivor beats one twelve
-- tiles away that is chasing the player, for a survivor with no party of its
-- own (a resident, the ordinary case the owner reported).
local residentControl = function()
    local c = control()
    c.companionOrder, c.companionTarget = nil, nil
    return c
end
local closing = control():evaluateCombatThreat(zombieAt(6, nil), 100)
assert(closing ~= nil and closing.reason == "closing" and closing.priority == 4,
    "a zombie closing on the survivor is a closing threat")
local loneClose = residentControl():evaluateCombatThreat(zombieAt(6, nil), 100)
local assisting = residentControl():evaluateCombatThreat(zombieAt(12, player), 100)
assert(assisting ~= nil and assisting.reason == "player_target",
    "a zombie chasing the player is still an assist")
assert(loneClose.score < assisting.score,
    "the closer zombie outranks the distant one chasing the player")
-- A distant assist does not pull the companion past a zombie closing on it,
-- but an ally actually being attacked beside the companion still comes first.
local distantBacking = control():evaluateCombatThreat(zombieAt(9, player), 100)
assert(distantBacking ~= nil and distantBacking.reason == "group_target"
    and distantBacking.score > closing.score,
    "a distant ally assist does not outrank a zombie closing on the survivor")
local nearBacking = control():evaluateCombatThreat(zombieAt(2, player), 100)
assert(nearBacking ~= nil and nearBacking.score < closing.score,
    "an ally being attacked beside the survivor still comes first")
-- Past the closing band the settings radius is authoritative again: an
-- unbothered zombie keeps walking until it is either close or interested.
local outside = control():evaluateCombatThreat(zombieAt(9, nil), 100)
assert(outside == nil,
    "a zombie past the closing band with no party target waits")
-- A zombie targeting the survivor still outranks everything.
local targeted = control():evaluateCombatThreat(zombieAt(4, body), 100)
assert(targeted ~= nil and targeted.priority == 5
    and targeted.score < closing.score,
    "self defense still outranks a closing zombie")

-- Hostility: a factionless survivor flagged hostile to the player is
-- answered by the player's companion.
local hostileSq = sq(4)
local hostile = { getCurrentSquare = function() return hostileSq end,
    isDead = function() return false end,
    getTarget = function() return nil end }
local flagged = false
KnoxPersistence.isSurvivorHostileToPlayer = function(id) return flagged and id == "raider-9" end
KnoxSurvivorRuntime.idForCharacter = function(ch)
    return ch == hostile and "raider-9" or nil
end
assert(control():evaluateCombatThreat(hostile, 100) == nil,
    "a survivor who is not hostile to the owner stays neutral")
flagged = true
local answered = control():evaluateCombatThreat(hostile, 100)
assert(answered ~= nil and answered.human == true,
    "a survivor hostile to the owner is answered by the owner's companion")
-- A base resident with no live player link still reads the flag through the
-- first active player.
flagged = false
local resident = control()
resident.companionTarget, resident.companionOrder = nil, nil
flagged = true
assert(resident:evaluateCombatThreat(hostile, 100) ~= nil,
    "a resident answers through the active player as owner")

KnoxPersistence, KnoxSettings, KnoxSurvivorRuntime =
    oldPersistence, oldSettings, oldRuntime
getSpecificPlayer, getNumActivePlayers = oldSpecific, oldNum
print("Threat priority PASS closingFirst=true selfFirst=true ownerHostilityAnswered=true")
