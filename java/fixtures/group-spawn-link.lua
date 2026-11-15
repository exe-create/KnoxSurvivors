-- A newly created travel group must receive its leader link immediately, not
-- wait for the next 60-tick social pass.  This drives the real persistence,
-- relationship coordinator and controller methods; no production assignment
-- is reproduced in the fixture.
local P, C, R = assert(KnoxPersistence), assert(KnoxAutonomyController), assert(KnoxSurvivorRelationships)
local oldData, oldTime, oldSettings, oldFeed, oldScavenge = data, getGameTime, KnoxSettings, KnoxActivityFeed, KnoxGroupScavenge
local oldRuntime = rawget(_G, "KnoxSurvivorRuntime")
data = {}
local age = 10
getGameTime = function() return { getWorldAgeHours = function() return age end } end
KnoxSettings = {
    allowNPCFactions = function() return false end,
    allowHostileEncounters = function() return false end,
}
KnoxActivityFeed = { event = function() end, speak = function() end }
KnoxGroupScavenge = nil

local ids = { "group-spawn-lead", "group-spawn-mate" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, expectedRecord))
    assert(P.ensureSurvivorIdentity(id, id, "Survivor", 10))
    local identity = data.KnoxSurvivors_IsoPlayer.survivors[id].identity
    identity.sociability, identity.aggression = 100, 0
end

local function body(x, y)
    local actor = { x = x, y = y }
    actor.getCurrentSquare = function()
        return {
            getX = function() return actor.x end,
            getY = function() return actor.y end,
            getZ = function() return 0 end,
        }
    end
    actor.isDead = function() return false end
    return actor
end

local function controller(id, x)
    local c = setmetatable({
        id = id,
        state = "IDLE",
        character = body(x, 0),
        groupMembers = {},
        counts = { roam = 0, loot = 0, combat = 0, groupTravel = 0 },
        bridge = { getNpcCharacter = function() return nil end },
    }, { __index = C })
    c.clearLifeIntent = function() end
    c.setGroupMembers = function(self, members) self.groupMembers = members end
    return c
end

R.resetRuntime()
-- Establish a recent assignment pass first.  A group created now would be
-- skipped by the ordinary cadence unless creation requests a refresh.
R.coordinate({}, {}, 100)
local group = assert(P.createTravelGroup(ids, age))
assert(group.leaderId == ids[1], "the group leader is the sorted first member")
local controllers = {
    [ids[1]] = controller(ids[1], 0),
    [ids[2]] = controller(ids[2], 4),
}
R.coordinate(controllers, ids, 110)
local follower = controllers[ids[2]]
assert(follower.groupLeaderId == ids[1], "a fresh group gets its leader id immediately")
assert(follower.groupLeader == controllers[ids[1]].character,
    "a fresh group gets its live leader character immediately")
assert(controllers[ids[1]].groupLeaderId == nil, "the leader does not follow itself")

-- A leader controller can be absent while the character is still live (for
-- example during a spawn/activation ordering gap).  The durable id plus the
-- runtime lookup must still wire the follower.
controllers[ids[1]] = nil
_G.KnoxSurvivorRuntime = {
    getCharacter = function(id)
        return id == ids[1] and follower.groupLeader or nil
    end,
}
R.requestGroupAssignmentRefresh()
R.coordinate(controllers, ids, 120)
assert(follower.groupLeaderId == ids[1], "the durable id survives an unloaded leader controller")
assert(follower.groupLeader ~= nil, "the runtime fallback supplies the live leader character")

_G.KnoxSurvivorRuntime = oldRuntime
data, getGameTime, KnoxSettings, KnoxActivityFeed, KnoxGroupScavenge =
    oldData, oldTime, oldSettings, oldFeed, oldScavenge
