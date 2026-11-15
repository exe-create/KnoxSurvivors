-- Contact self-defense is never a policy decision. An ordered defensive
-- companion answers a zombie on top of it whether or not the zombie has
-- acquired a target yet, and a zombie actively chewing the survivor is never
-- hidden by a failure cooldown. Distant unbothered zombies stay vetoed.
local C = assert(KnoxAutonomyController)
local oldCell = rawget(_G, "getCell")
local oldSettings = rawget(_G, "KnoxSettings")
local oldNumPlayers = rawget(_G, "getNumActivePlayers")
local oldPlayer = rawget(_G, "getSpecificPlayer")
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end, canStand = function() return true end }
end
KnoxSettings = { allowSurvivorPlayerCombat = function() return false end }
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return nil end
local zombies = {}
getCell = function()
    return { getZombieList = function()
        return { size = function() return #zombies end,
            get = function(_, i) return zombies[i + 1] end }
    end }
end
local function actor(x)
    local a = { x = x, y = 200, z = 0, seen = true }
    function a:getCurrentSquare() return square(self.x, self.y, self.z) end
    function a:isDead() return false end
    function a:CanSee() return self.seen end
    function a:getCharacterActions() return { isEmpty = function() return true end } end
    return a
end
local function zed(x, victim)
    local z = actor(x)
    z.victim = victim
    function z:getTarget() return self.victim end
    return z
end
local body = actor(100)
local owner = actor(110)
local closeZed, midZed, farZed = zed(101, nil), zed(103, nil), zed(120, nil)
zombies = { closeZed, farZed }
local c = setmetatable({ id = "contact-person", character = body, bridge = {},
    companionOwnerId = "contact-owner", companionTarget = owner,
    companionOrder = "follow", companionFormationSlot = 1, companionPartySize = 1,
    state = "COMPANION_FOLLOW", nextThink = 0, nextThreatScan = 0,
    combatDisengageUntil = 0, failedThreats = {}, perceivedThreats = {},
    groupMembers = {}, counts = { failures = 0 },
    reservations = { threats = {}, items = {}, restSpots = {} } }, { __index = C })
-- A zombie one tile out with no target is answered, not watched.
assert(c:allowsCompanionThreat(closeZed) == true,
    "contact zombie is self-defense even before it acquires")
-- Three tiles out is answered too: two tiles of warning was not enough, and
-- the scan already calls this band nearby danger.
assert(c:allowsCompanionThreat(midZed) == true,
    "closing zombie inside the engagement radius is answered")
-- A distant unbothered zombie stays vetoed: no horde-aggro expansion.
assert(c:allowsCompanionThreat(farZed) == false,
    "distant non-targeting zombie stays a defensive veto")
-- An explicit passive order still holds inside the radius; flee answers first.
c.companionCombatStance = "passive"
assert(c:allowsCompanionThreat(midZed) == false,
    "passive order holds even inside the radius")
c.companionCombatStance = nil
-- A zombie actively chewing the survivor is never hidden by a cooldown.
closeZed.victim = body
c.failedThreats[closeZed] = 99999
assert(c:selectCombatThreat(1000) == closeZed,
    "active attacker pierces the failure cooldown")
-- The same cooldown still hides a zombie that is not attacking anyone.
closeZed.victim = nil
c.perceivedThreats = {}
assert(c:selectCombatThreat(1000) == nil,
    "cooldown still hides a non-attacking zombie")
rawset(_G, "getCell", oldCell)
rawset(_G, "KnoxSettings", oldSettings)
rawset(_G, "getNumActivePlayers", oldNumPlayers)
rawset(_G, "getSpecificPlayer", oldPlayer)
print("Contact defense PASS contact=true closing=true distant=false passive=holds pierce=true")
