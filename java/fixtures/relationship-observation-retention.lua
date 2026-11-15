local probe = assert(relationshipObservationProbe)
local oldPersistence, oldGameTime = KnoxPersistence, getGameTime
local age, records = 0, {}
KnoxPersistence = {
    getSurvivorAffiliation = function() return nil end,
    getSurvivorDuty = function() return nil end,
    ensureSurvivorIdentity = function() end,
    recordEncounter = function(first, second, event)
        records[#records + 1] = event
        return { meetings = 1 }
    end,
    getRelationship = function() return {} end,
}
getGameTime = function() return { getWorldAgeHours = function() return age end } end
local descriptor = { getForename = function() return "A" end, getSurname = function() return "Person" end }
local function survivor(id, x)
    local square = { getX = function() return x end, getY = function() return 0 end,
        getZ = function() return 0 end }
    return { id = id, counts = { roam = 0, groupTravel = 0, loot = 0, combat = 0 },
        character = { getCurrentSquare = function() return square end,
            getDescriptor = function() return descriptor end, CanSee = function() return true end } }
end
local a, b = survivor("a", 0), survivor("b", 25)
local controllers, roster = { a = a, b = b }, { "a", "b" }
probe.relationships.observe(controllers, roster, 0)
assert(#records == 1 and records[1].began and records[1].nearbyHours == 0, "first encounter begins")
age = 1
a.counts.roam, b.counts.roam = 2, 2
probe.relationships.observe(controllers, roster, 1)
assert(#records == 2 and not records[2].began and records[2].nearbyHours == 1
    and records[2].sharedRoam == 2, "continuing pair retains elapsed and shared counters")
age = 2
probe.relationships.observe({ a = a }, { "a" }, 2)
assert(probe.states["a::b"] == nil, "unobserved pair is removed")
age = 20
a.counts.roam, b.counts.roam = 20, 20
probe.relationships.observe(controllers, roster, 3)
assert(records[3].nearbyHours == 0 and records[3].sharedRoam == 0,
    "reunion does not credit unobserved elapsed or counters")
local meeting = { firstId = "a", secondId = "b" }
probe.meetings["a::b"] = meeting
local state = probe.states["a::b"]
age = 21
probe.relationships.observe({ a = a }, { "a" }, 4)
assert(probe.meetings["a::b"] == meeting and probe.states["a::b"] == state,
    "unobserved pending meeting and pair identity remain intact")
age = 50
a.counts.roam, b.counts.roam = 50, 50
probe.relationships.observe(controllers, roster, 5)
assert(probe.meetings["a::b"] == meeting and #records == 4 and not records[4].began
    and records[4].nearbyHours == 0 and records[4].sharedRoam == 0,
    "pending reunion does not begin another meeting or credit the gap")
age = 51
a.counts.roam, b.counts.roam = 51, 51
probe.relationships.observe(controllers, roster, 6)
assert(records[5].nearbyHours == 1 and records[5].sharedRoam == 1,
    "pending pair resumes ordinary cadence after rebaseline")
probe.states["a::b"].near = false
age = 52
probe.relationships.observe({ a = a }, { "a" }, 7)
age = 60
probe.relationships.observe(controllers, roster, 8)
assert(not records[6].began and records[6].nearbyHours == 0,
    "a suspended pending pair does not duplicate a previously separated meeting")
age = 61
probe.relationships.observe({ a = a }, { "a" }, 9)
probe.meetings["a::b"] = nil
age = 70
probe.relationships.observe(controllers, roster, 10)
assert(records[7].began and records[7].nearbyHours == 0 and records[7].sharedRoam == 0,
    "a meeting cleared during absence allows a fresh encounter without gap credit")
KnoxPersistence, getGameTime = oldPersistence, oldGameTime
print("Relationship observation retention PASS continuing=true prune=true reunion=true pending=true")
