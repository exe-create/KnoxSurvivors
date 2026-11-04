-- A squad order is one mission with several members, not several missions:
-- nobody heads home while a member is still searching, each arriving member is
-- released on its own, and the single result names everyone. Only durable
-- transitions are exercised here.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
local Executor = KnoxAwayTeamExecutor
assert(type(Executor) == "table", "away-team executor must be loaded")

local function seed(id, forename)
    assert(p.setRecord(id, expectedRecord))
    p.ensureSurvivorIdentity(id, forename, "Kell", 10, 34)
    assert(p.setPlayerCompanion(id, "squad-owner", "hold", 10))
end

seed("squad-a", "Iris")
seed("squad-b", "Jonah")
seed("squad-c", "Kit")
local base = assert(p.createBase("player", "squad-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "squad-home",
}, 10, nil, true))
for _, id in ipairs({ "squad-a", "squad-b", "squad-c" }) do
    assert(p.setPlayerBaseResident(id, "squad-owner", base.id, 10))
end

local destination = { x = 300, y = 320, z = 0, label = "School" }
local team = assert(p.createAwayTeam("player", "squad-owner",
    { "squad-a", "squad-b" }, "scout", destination, 10, 10.5, nil, false))
assert(assert(p.beginAwayTeamLiveArrival(team.id, 10)).state == "awaiting_collection",
    "a watched squad keeps every body in the world")
for _, id in ipairs({ "squad-a", "squad-b" }) do
    assert(p.getSurvivorDuty(id).mode == "away",
        "every squad member is owned by the one mission")
end
assert(p.getSurvivorDuty("squad-c").mode == "base",
    "a resident left out of the party keeps ordinary base duty")
assert(p.getAwayTeamProgress(team.id, 10.1).memberCount == 2,
    "the crew view sees the real party size")

assert(p.beginAwayTeamCollection(team.id, 10.2) ~= nil)
assert(p.recordAwayTeamCollection(team.id, "squad-a", { "Base.CannedSoup" }, 10.3) ~= nil)
assert(p.awayTeamCollectionReady(team.id) == false,
    "one member searching does not finish a squad")
assert(p.beginAwayTeamReturn(team.id, 10.4) == nil,
    "the squad cannot head home while a member is still searching")
local collecting = assert(p.getAwayTeam(team.id))
assert(collecting.state == "collecting",
    "the mission keeps collecting the remaining member")
assert(p.getAwayTeamProgress(team.id, 10.45).collectingMembers == 1,
    "the crew view reports one searched member of two")

assert(p.recordAwayTeamCollection(team.id, "squad-b", {}, 10.5) ~= nil)
assert(p.awayTeamCollectionReady(team.id) == true,
    "a real but empty search still counts as finished")
assert(assert(p.beginAwayTeamReturn(team.id, 10.6)).state == "returning",
    "the squad heads home once every member has searched")

local first = assert(p.completeAwayTeamMember(
    team.id, "squad-a", true, "returned_to_owner", 10.8
))
assert(first.state == "returning", "one arrival does not close the squad")
assert(p.getSurvivorDuty("squad-a").mode == "base",
    "an arrived member resumes ordinary base duty")
assert(p.getSurvivorDuty("squad-b").mode == "away",
    "a member still walking keeps its mission duty")
assert(#Executor.takePlayerNotices("squad-owner", 10.9, 3) == 0,
    "an open squad is not reported as finished")

local done = assert(p.completeAwayTeamMember(
    team.id, "squad-b", true, "returned_to_owner", 11
))
assert(done.state == "complete" and done.result.kind == "resource_run",
    "the last arrival closes the squad result")
assert(done.result.resources["Base.CannedSoup"] == 1,
    "the squad result keeps only the haul that was really recorded")
assert(done.result.members["squad-a"].success == true
    and done.result.members["squad-b"].success == true,
    "every member's own outcome is durable")
assert(p.getSurvivorDuty("squad-b").mode == "base",
    "the last arrival releases the remaining member")
assert(p.getSurvivorDuty("squad-c").mode == "base",
    "a resident outside the party is never touched by the mission")

local notices = Executor.takePlayerNotices("squad-owner", 11, 3)
assert(#notices == 1, "a squad produces one outcome, not one per member")
assert(string.find(notices[1], "Iris Kell", 1, true) ~= nil
    and string.find(notices[1], "Jonah Kell", 1, true) ~= nil,
    "the squad outcome names every member that went")
assert(#Executor.takePlayerNotices("squad-owner", 11.1, 3) == 0,
    "the squad outcome is reported once")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Away squad dispatch PASS one_mission=true all_members_required=true "
    .. "per_member_release=true single_notice=true")
