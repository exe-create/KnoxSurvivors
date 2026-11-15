local P, C, R = assert(KnoxPersistence), assert(KnoxAutonomyController), assert(KnoxSurvivorRelationships)
local oldData, oldTime, oldNeeds, oldSettings = data, getGameTime, KnoxSurvivorNeeds, KnoxSettings
local oldAdjacent, oldFeed, oldParties = AdjacentFreeTileFinder, KnoxActivityFeed, KnoxGroupScavenge
data = {}
local age = 10
getGameTime = function() return { getWorldAgeHours = function() return age end } end
local need = "roam"
KnoxSurvivorNeeds = { decide = function() return { kind = need } end }
KnoxSettings = { allowNPCFactions = function() return false end, allowHostileEncounters = function() return false end }
KnoxActivityFeed = { event = function() end, speak = function() end }
KnoxGroupScavenge = nil
local ids = { "a-company-lead", "b-company-mate", "z-company-solo" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, expectedRecord))
    P.ensureSurvivorIdentity(id, id, "Survivor", 10)
    local identity = data.KnoxSurvivors_IsoPlayer.survivors[id].identity
    identity.sociability, identity.aggression = 100, 0
end
local group = assert(P.createTravelGroup({ ids[1], ids[2] }, 10))
assert(group.leaderId == ids[1])
assert(P.setSurvivorCreatorRecord(ids[3], { name = "Company Seeker", settlementPolicy = "default" }))
for i = 1, 2 do P.recordEncounter(ids[1], ids[3], { worldAgeHours = 10, began = true, sharedRoam = 2 }) end
local moved = {}
local function controller(id, x)
    local actor = { x = x, visible = true }
    actor.getCurrentSquare = function()
        return { getX = function() return actor.x end, getY = function() return 0 end, getZ = function() return 0 end }
    end
    actor.getDescriptor = function() return { getForename = function() return id end, getSurname = function() return "Survivor" end } end
    actor.CanSee = function(_, other) return actor.visible and other.visible end
    local c = setmetatable({ id = id, character = actor, state = "IDLE",
        counts = { roam = 0, loot = 0, combat = 0, groupTravel = 0 },
        bridge = { moveNpc = function(_, movingId, square)
            moved[#moved + 1] = { id = movingId, x = square:getX() }
            return "MOVE_STARTED"
        end },
    }, { __index = C })
    c.canInterruptForMeeting = function() return true end
    c.interruptForMeeting = function(self) self.state = "MEETING_WAIT" return true end
    c.clearGroupLeader = function(self) self.groupLeaderId = nil end
    c.setGroupMembers = function(self, members) self.groupMembers = members end
    c.setGroupObjective = function() end
    c.setGroupLeaderOrder = function() end
    c.considerGroupWithdrawal = function() end
    return c
end
local lead, solo = controller(ids[1], 0), controller(ids[3], 28)
AdjacentFreeTileFinder = { Find = function(square) return square end }
assert(R.companySeeker(lead, solo) == solo, "a satisfied solo survivor can seek a visible group leader")
need = "find_food"
assert(R.companySeeker(lead, solo) == nil, "unmet basic needs block company seeking")
need = "roam"
solo.character.visible = false
assert(R.companySeeker(lead, solo) == nil, "a group not actually spotted supplies no travel destination")
solo.character.visible = true
solo.character.x = 40
assert(R.companySeeker(lead, solo) == nil, "general searching gives no map-wide group awareness")
solo.character.x = 28
local canJoin = false
for meetings = 2, 30 do
    if R.decideEncounterOutcome(ids[1], ids[3], { meetings = meetings, sharedRoam = 4 }) == "join" then canJoin = true end
end
assert(canJoin, "the existing encounter rules offer a genuine join opportunity for this compatible loner")
assert(P.setSurvivorCreatorRecord(ids[3], { name = "Independent", settlementPolicy = "independent" }))
assert(R.companySeeker(lead, solo) == nil, "independent creator policy never seeks a group")
for meetings = 2, 30 do
    assert(R.decideEncounterOutcome(ids[1], ids[3], { meetings = meetings, sharedRoam = 4 }) ~= "join",
        "independent policy also prevents the automatic join outcome")
end
assert(P.setSurvivorCreatorRecord(ids[3], { name = "Company Seeker", settlementPolicy = "default" }))

R.resetRuntime()
local controllers, ordered = { [lead.id] = lead, [solo.id] = solo }, { lead.id, solo.id }
R.observe(controllers, ordered, 0)
local intent = assert(P.getSurvivorLifeIntent(solo.id), "visible observation creates a real company intent")
assert(intent.kind == "seek_group" and intent.phase == "seeking" and intent.targetX == 0
    and intent.targetKey == "group:" .. group.id,
    "the observed group supplies the seek intent's actual last-seen destination")
assert(P.getTravelGroupFor(solo.id) == nil and #group.memberIds == 2,
    "approaching company invents no membership or successful recruitment")
R.coordinate(controllers, ordered, 0)
assert(#moved == 1 and moved[1].id == solo.id and moved[1].x == 0,
    "the real meeting coordinator moves the seeker toward the spotted group, even when roster order is reversed")
assert(P.getSurvivorLifeIntent(solo.id).phase == "traveling", "an accepted native route advances the existing intent phase")
solo.character.visible = false
R.coordinate(controllers, ordered, 1)
assert(#moved == 1 and P.getSurvivorLifeIntent(solo.id).targetX == 0 and P.getTravelGroupFor(solo.id) == nil,
    "an occluded approach retains only its last-seen route and invents no membership")
-- Double the native movement completion boundary, then let the real meeting
-- owner perform its required arrival visibility check.
solo.state = "MEETING_READY"
R.coordinate(controllers, ordered, 2)
assert(P.getSurvivorLifeIntent(solo.id) == nil and solo.lifeIntent == nil and solo.state == "IDLE",
    "lost visual contact on arrival aborts through the existing meeting owner and clears the seek purpose")
assert(P.getTravelGroupFor(solo.id) == nil, "an aborted approach never joins a group")
solo:setLifeIntent("seek_group", "seeking", lead.character:getCurrentSquare(), "group:" .. group.id)
solo:resumeAfterGreeting(3)
assert(P.getSurvivorLifeIntent(solo.id) == nil, "ordinary greeting completion clears the company intent too")
age = 12
solo.character.visible = true
R.resetRuntime()
R.observe(controllers, ordered, 4)
assert(P.getSurvivorLifeIntent(solo.id) ~= nil, "a later observed contact can request company again")
local leaderBody = lead.character
lead.character = nil
R.coordinate(controllers, ordered, 4)
assert(P.getSurvivorLifeIntent(solo.id) == nil,
    "a disappearing partner clears even a requested intent before movement starts")
lead.character = leaderBody
R.resetRuntime()
data, getGameTime, KnoxSurvivorNeeds, KnoxSettings = oldData, oldTime, oldNeeds, oldSettings
AdjacentFreeTileFinder, KnoxActivityFeed, KnoxGroupScavenge = oldAdjacent, oldFeed, oldParties
print("Solo visible company PASS actualSight=true needsFirst=true independent=true realObserve=true realMeetingMove=true noFakeJoin=true lostContactCleared=true nativeGameplay=false")
