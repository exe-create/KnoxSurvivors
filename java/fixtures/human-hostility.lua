local C = assert(KnoxAutonomyController)
local oldP, oldSettings, oldRuntime = KnoxPersistence, rawget(_G, "KnoxSettings"), rawget(_G, "KnoxSurvivorRuntime")
local oldSpecific, oldNum = getSpecificPlayer, getNumActivePlayers
local warDisposition, personalFlag = "hostile", false
local flags = {}
local function sq(x)
    return { getX = function() return x end, getY = function() return 10 end, getZ = function() return 0 end }
end
local bodySq, playerSq = sq(10), sq(12)
local body = { getCurrentSquare = function() return bodySq end,
    isDead = function() return false end,
    CanSee = function() return true end }
local player = { getCurrentSquare = function() return playerSq end,
    isDead = function() return false end,
    getTarget = function() return nil end }
KnoxPersistence = {
    getSurvivorAffiliation = function() return { factionId = "raiders" } end,
    ensurePlayerId = function() return "player-1" end,
    -- Pair-scoped like the real record: a companion now reads its owner's
    -- personal flag too, so a blanket true would leak one survivor's flag
    -- onto every other survivor the scan sees.
    isSurvivorHostileToPlayer = function(id, pid)
        return personalFlag and id == "raider-1" and pid == "player-1"
    end,
    setSurvivorHostileToPlayer = function(id, pid, v) flags[id .. ":" .. pid] = v return true end,
    getPlayerFaction = function() return { id = "player-faction" } end,
    getFactionRelationship = function() return { disposition = warDisposition } end,
    getPlayerSocialDisposition = function() return "independent" end,
}
KnoxSettings = { allowSurvivorPlayerCombat = function() return true end }
KnoxSurvivorRuntime = { idForCharacter = function() return nil end }
getSpecificPlayer = function(i) return i == 0 and player or nil end
getNumActivePlayers = function() return 1 end
local function control()
    return setmetatable({ id = "raider-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = nil, groupLeader = nil, groupMembers = {} },
        { __index = C })
end
-- A faction war on the ledger needs no personal blow: the raider takes the
-- player as a threat and records the same flag a witness would set, so the
-- player's own party reads the attacker through the normal assist path.
local seen = control():evaluateCombatThreat(player, 100)
assert(seen ~= nil and seen.reason ~= nil and seen.human == true
    and flags["raider-1:player-1"] == true,
    "a faction-hostile raider acquires the player")
-- Neutral and allied tables stay quiet.
flags, warDisposition = {}, "neutral"
assert(control():evaluateCombatThreat(player, 100) == nil
    and flags["raider-1:player-1"] == nil,
    "a neutral table leaves a non-attacking player alone")
flags, warDisposition = {}, "allied"
assert(control():evaluateCombatThreat(player, 100) == nil,
    "an allied table never admits the player")
-- The old personal-flag path still works when the table says nothing.
flags, warDisposition, personalFlag = {}, "neutral", true
assert(control():evaluateCombatThreat(player, 100) ~= nil,
    "a personally-flagged raider still acquires the player")
-- Survivor branch: a faction war between NPCs needs no personal row either.
-- Same table mirror as the player branch, same faction never matches.
local npcPersonal = false
KnoxPersistence.getSurvivorDisposition = function(selfId, otherId)
    if npcPersonal and otherId == "loner-1" then return "hostile" end
    return "neutral"
end
KnoxPersistence.getSurvivorAffiliation = function(id)
    if id == "raider-1" or id == "raider-2" then return { factionId = "raiders" } end
    return { factionId = "loners" }
end
KnoxPersistence.getFactionRelationship = function(a, b)
    if a == b then return { disposition = "allied" } end
    return { disposition = warDisposition }
end
local npcSq = sq(12)
local function npcTarget() return { getCurrentSquare = function() return npcSq end,
    isDead = function() return false end, getTarget = function() return nil end } end
local seenNpc = npcTarget()
KnoxSurvivorRuntime.idForCharacter = function(ch) return ch == seenNpc and "loner-1" or nil end
warDisposition = "hostile"
local warSeen = control():evaluateCombatThreat(seenNpc, 100)
assert(warSeen ~= nil and warSeen.human == true,
    "a faction-hostile survivor acquires the NPC")
seenNpc = npcTarget()
KnoxSurvivorRuntime.idForCharacter = function(ch) return ch == seenNpc and "raider-2" or nil end
assert(control():evaluateCombatThreat(seenNpc, 100) == nil,
    "the same faction never matches")
seenNpc = npcTarget()
KnoxSurvivorRuntime.idForCharacter = function(ch) return ch == seenNpc and "loner-1" or nil end
warDisposition = "neutral"
assert(control():evaluateCombatThreat(seenNpc, 100) == nil,
    "a neutral table leaves a non-attacking survivor alone")
warDisposition = "allied"
assert(control():evaluateCombatThreat(seenNpc, 100) == nil,
    "an allied table never admits the survivor")
npcPersonal, warDisposition = true, "neutral"
assert(control():evaluateCombatThreat(seenNpc, 100) ~= nil,
    "a personally-flagged survivor still acquires the NPC")
-- Player-initiated hostility: our own side drew first blood, so the party
-- backs the fight with no war or personal row. A player-affiliated candidate
-- stays exempt (friendly fire never turns the party), and a stranger's
-- brawl is none of our business.
local oldGameTime = rawget(_G, "getGameTime")
rawset(_G, "getGameTime", function()
    return { getWorldAgeHours = function() return 0 end }
end)
local victimPlayerAffiliated = false
KnoxPersistence.getSurvivorAffiliation = function(id)
    if victimPlayerAffiliated and id == "loner-1" then return { kind = "player" } end
    if id == "raider-1" or id == "raider-2" then return { factionId = "raiders" } end
    return { factionId = "loners" }
end
local backVictim = nil
local function npcVictim(hitBy)
    backVictim = { getCurrentSquare = function() return npcSq end,
        isDead = function() return false end, getTarget = function() return nil end,
        getAttackedBy = function() return hitBy end }
    return backVictim
end
KnoxSurvivorRuntime.idForCharacter = function(ch)
    if ch == player or backVictim == nil or ch ~= backVictim then return nil end
    return "loner-1"
end
local function followerControl()
    return setmetatable({ id = "raider-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = player, groupLeader = nil, groupMembers = {} },
        { __index = C })
end
local function partyControl()
    return setmetatable({ id = "raider-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = nil, groupLeader = nil, groupMembers = { player } },
        { __index = C })
end
warDisposition, npcPersonal = "neutral", false
local struck = npcVictim(player)
local seen = followerControl():evaluateCombatThreat(struck, 100)
assert(seen ~= nil and seen.human == true,
    "the party backs the player's fight")
struck = npcVictim(player)
seen = partyControl():evaluateCombatThreat(struck, 100)
assert(seen ~= nil and seen.human == true,
    "a party member's fight is backed")
struck = npcVictim(player)
victimPlayerAffiliated = true
assert(followerControl():evaluateCombatThreat(struck, 100) == nil
    and partyControl():evaluateCombatThreat(struck, 100) == nil,
    "friendly fire never turns the party")
victimPlayerAffiliated = false
local stranger = {}
struck = npcVictim(stranger)
assert(partyControl():evaluateCombatThreat(struck, 100) == nil,
    "a stranger's brawl is none of our business")
rawset(_G, "getGameTime", oldGameTime)
-- Answer their first blow: the attacker's live target does not exist on a
-- survivor shell, so the victim's latch is the record. Self, principal and
-- group all count; friendly fire stays forgiven here too.
rawset(_G, "getGameTime", function()
    return { getWorldAgeHours = function() return 0 end }
end)
warDisposition, npcPersonal, victimPlayerAffiliated = "neutral", false, false
local function plainVictim()
    backVictim = { getCurrentSquare = function() return npcSq end,
        isDead = function() return false end, getTarget = function() return nil end,
        getAttackedBy = function() return nil end }
    return backVictim
end
KnoxSurvivorRuntime.idForCharacter = function(ch)
    if ch == player or backVictim == nil or ch ~= backVictim then return nil end
    return "loner-1"
end
local opened = plainVictim()
body.getAttackedBy = function() return opened end
assert(control():evaluateCombatThreat(opened, 100) ~= nil,
    "a blow on us marks the striker")
body.getAttackedBy = nil
player.getAttackedBy = function() return opened end
opened = plainVictim()
assert(followerControl():evaluateCombatThreat(opened, 100) ~= nil,
    "a blow on our principal marks the striker")
player.getAttackedBy = nil
local ally = { getAttackedBy = function() return opened end }
local function guardedControl()
    return setmetatable({ id = "raider-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = nil, groupLeader = nil, groupMembers = { ally } },
        { __index = C })
end
opened = plainVictim()
assert(guardedControl():evaluateCombatThreat(opened, 100) ~= nil,
    "a blow on a group member marks the striker")
-- Native regression 2026-11-12 08:52: the victims scan invoked a missing
-- getter on breadcrumb anchor tables, escaping its pcall on the install.
-- Anchor-shaped tables and stray entries are skipped up front now while the
-- real latch beside them still reads.
opened = plainVictim()
local anchorVictim = { knownContact = true, atHours = 0,
    getCurrentSquare = function() return npcSq end,
    getX = function() return 12 end, getY = function() return 10 end,
    getZ = function() return 0 end }
local function mixedControl()
    return setmetatable({ id = "raider-1", character = body, currentTicks = 100,
        failedThreats = {}, reservations = { threats = {} },
        companionOrder = nil, companionTarget = nil, groupLeader = nil,
        groupMembers = { anchorVictim, ally, "stray-id" } },
        { __index = C })
end
assert(mixedControl():evaluateCombatThreat(opened, 100) ~= nil,
    "anchor tables and stray entries never break the victims scan")
opened = plainVictim()
body.getAttackedBy = function() return opened end
victimPlayerAffiliated = true
assert(control():evaluateCombatThreat(opened, 100) == nil
    and followerControl():evaluateCombatThreat(opened, 100) == nil,
    "friendly fire on our side stays forgiven")
victimPlayerAffiliated = false
body.getAttackedBy = nil
if player.getAttackedBy ~= nil then player.getAttackedBy = nil end
rawset(_G, "getGameTime", oldGameTime)
KnoxPersistence, KnoxSurvivorRuntime = oldP, oldRuntime
rawset(_G, "KnoxSettings", oldSettings)
getSpecificPlayer, getNumActivePlayers = oldSpecific, oldNum
print("Human hostility PASS factionWar=true neutral=allied=quiet personal=intact npcWar=true sameFaction=quiet backPlayer=true friendlyFire=quiet")
