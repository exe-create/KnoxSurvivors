local p = KnoxPersistence

assert(type(p.successorFor) == "function", "successorFor must exist")
assert(type(p.succeedDeadLeader) == "function", "succeedDeadLeader must exist")
assert(type(p.promoteSuccessorForSurvivor) == "function", "the death hook must exist")

-- Tenure decides, not list order: the earliest real join wins.
local ids = { "ks-person-c", "ks-person-a", "ks-person-b" }
local joined = { ["ks-person-a"] = 5, ["ks-person-b"] = 2, ["ks-person-c"] = 9 }
assert(p.successorFor(ids, joined, function() return true end) == "ks-person-b",
    "the earliest joined living member leads")

-- A tie is broken by id so the same roster cannot answer two ways.
assert(p.successorFor({ "ks-person-c", "ks-person-a" },
    { ["ks-person-a"] = 5, ["ks-person-c"] = 5 }, function() return true end) == "ks-person-a",
    "an equal tenure tie resolves deterministically")

-- The dead never lead, and the living member with no recorded join time counts
-- as the newest rather than the oldest.
assert(p.successorFor(ids, joined, function(id) return id ~= "ks-person-b" end) == "ks-person-a",
    "a dead member is never the successor")
assert(p.successorFor({ "ks-person-a", "ks-person-z" },
    { ["ks-person-a"] = 5 }, function() return true end) == "ks-person-a",
    "a missing join time is treated as the newest")
assert(p.successorFor({ "ks-person-z" }, {}, function() return true end) == "ks-person-z",
    "a sole surviving member leads")
assert(p.successorFor({}, joined, function() return true end) == nil)
assert(p.successorFor(nil, nil, nil) == nil)
assert(p.successorFor({ "ks-person-a" }, nil, nil) == "ks-person-a",
    "no live-check still answers from the roster")

-- One shared rule mutates one record.
local record = {
    id = "faction-x", leaderId = "ks-person-a",
    memberIds = { "ks-person-a", "ks-person-b", "ks-person-c" },
    memberJoinedAtHours = { ["ks-person-a"] = 1, ["ks-person-b"] = 3, ["ks-person-c"] = 7 },
}
local successor, detail = p.succeedDeadLeader(record, "ks-person-a",
    function(id) return id ~= "ks-person-a" end)
assert(successor == "ks-person-b" and detail == "succeeded", "the record hands over")
assert(record.leaderId == "ks-person-b", "the record now names the successor")

successor, detail = p.succeedDeadLeader(record, "ks-person-a", function() return true end)
assert(successor == nil and detail == "not_leader", "a non-leader death changes nothing")
assert(record.leaderId == "ks-person-b")

local doomed = {
    leaderId = "ks-person-a", memberIds = { "ks-person-a" },
    memberJoinedAtHours = { ["ks-person-a"] = 1 },
}
successor, detail = p.succeedDeadLeader(doomed, "ks-person-a", function() return false end)
assert(successor == nil and detail == "no_successor", "a leaderless group says so")
assert(doomed.leaderId == nil, "a dead person is never left in charge")

assert(select(2, p.succeedDeadLeader(nil, "ks-person-a")) == "invalid_record")
assert(select(2, p.succeedDeadLeader({ leaderId = "ks-person-a" }, nil)) == "invalid_record")

-- The real death path, through the real group record: the group keeps leading
-- itself and the dead member is not left as leader.
local a = assert(p.allocateWorldSurvivor({ x = 11, y = 11, z = 0, key = "ls-a", region = "LS" }, 10))
local b = assert(p.allocateWorldSurvivor({ x = 12, y = 11, z = 0, key = "ls-b", region = "LS" }, 10))
local c = assert(p.allocateWorldSurvivor({ x = 13, y = 11, z = 0, key = "ls-c", region = "LS" }, 10))
local group = assert(p.createTravelGroup({ a, b, c }, 10))
assert(group.leaderId == a, "the first member founds the group")
group.memberJoinedAtHours[b] = 11
group.memberJoinedAtHours[c] = 10
assert(p.issueTravelGroupLeaderOrder(group.id, a, "withdraw", 11, 13))
assert(p.setTravelGroupObjective(group.id, a, { kind = "travel_area", phase = "traveling" }, 11))
local promoted = p.markSurvivorDead(a, 12, "test_death")
assert(promoted == true, "the death is recorded")

local _, candidates = p.getTravelGroupsFor({ b, c })
local after = p.getTravelGroupFor(b, candidates)
assert(after ~= nil, "the group survives its leader")
assert(after.leaderId ~= a, "a dead member is never left in charge of a real group")
assert(after.leaderId == c, "the real death path selects tenure before roster order")
assert(p.isSurvivorAlive(after.leaderId) == true, "the successor is alive")
assert(after.leaderOrder == nil and after.objective == nil,
    "the deceased leader's directives do not survive succession")

local d = assert(p.allocateWorldSurvivor({ x = 21, y = 11, z = 0, key = "ls-d", region = "LS" }, 20))
local e = assert(p.allocateWorldSurvivor({ x = 22, y = 11, z = 0, key = "ls-e", region = "LS" }, 20))
local f = assert(p.allocateWorldSurvivor({ x = 23, y = 11, z = 0, key = "ls-f", region = "LS" }, 20))
local factionGroup = assert(p.createTravelGroup({ d, e, f }, 20))
local faction = assert(p.promoteTravelGroupToFaction(factionGroup.id, 22, 3))
faction.memberJoinedAtHours[e] = 21
faction.memberJoinedAtHours[f] = 20
factionGroup.memberJoinedAtHours[e] = 21
factionGroup.memberJoinedAtHours[f] = 20
assert(p.markSurvivorDead(d, 23, "test_death"))
assert(p.getFaction(faction.id).leaderId == f,
    "faction death succession uses tenure instead of the first roster ID")
assert(p.getTravelGroupFor(f).leaderId == f,
    "the faction's travel group follows the same succession rule")
assert(#p.getFaction(faction.id).memberIds == 2,
    "the deceased member is still removed from the faction")
assert(p.markSurvivorDead(e, 24, "test_death"))
assert(p.getFaction(faction.id).leaderId == f,
    "a non-leader death preserves the living leader")
assert(p.markSurvivorDead(f, 25, "test_death"))
assert(p.getFaction(faction.id) == nil,
    "the last member's death collapses the empty faction through existing cleanup")
assert(p.markSurvivorDead(d, 26, "duplicate_death"), "death handling remains idempotent")

print("Leader succession PASS tenure=true deterministic=true dead_excluded=true handover=true leaderless=true real_group=true")
