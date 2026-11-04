-- A team walking home while nobody can see it must arrive on its own clock,
-- not by the three-day failure boundary, and a member whose body is loaded must
-- be left to its own controller. Nothing is teleported, invented or double
-- resolved: the results are the ones the live search already recorded.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
local Executor = KnoxAwayTeamExecutor
assert(type(Executor) == "table", "away-team executor must be loaded")

local function seed(id, forename)
    assert(p.setRecord(id, expectedRecord))
    p.ensureSurvivorIdentity(id, forename, "Marsh", 10, 34)
    assert(p.setPlayerCompanion(id, "return-owner", "hold", 10))
end

seed("return-a", "Ada")
seed("return-b", "Bo")
local base = assert(p.createBase("player", "return-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "return-home",
}, 10, nil, true))
assert(p.setPlayerBaseResident("return-a", "return-owner", base.id, 10))
assert(p.setPlayerBaseResident("return-b", "return-owner", base.id, 10))

-- One pace owner for both legs, bounded at each end.
assert(math.abs(p.awayTravelHours({ x = 0, y = 0 }, { x = 3000, y = 0 }) - 1) < 0.000001,
    "a 3000-tile leg is one hour")
assert(p.awayTravelHours({ x = 40, y = 40 }, { x = 40, y = 40 }) == 0.15,
    "a same-square leg still costs the minimum")
assert(p.awayTravelHours(nil, nil) == 1 and p.awayTravelHours({ x = "x" }, {}) == 1,
    "unknown geometry falls back to one bounded hour")
assert(p.awayTravelHours({ x = 0, y = 0 }, { x = 90000, y = 0 }) == 3,
    "no leg is open-ended")

local destination = { x = 9000, y = 9000, z = 0, label = "Far farm" }
local home = { x = 105, y = 204, z = 0, label = "Home" }

local team = assert(p.createAwayTeam("player", "return-owner", { "return-a" },
    "food", destination, 10, 13, home))
p.advanceAwayTeams(13)
assert(p.getAwayTeam(team.id).state == "awaiting_collection",
    "the resource run arrives at its destination first")
assert(p.awayTeamReturnProgress(team.id, 13) == nil,
    "a team still at the destination has no return progress")
assert(p.beginAwayTeamCollection(team.id, 13) ~= nil)
assert(p.recordAwayTeamCollection(team.id, "return-a", { "Base.CannedBeans" }, 13.5) ~= nil)
assert(assert(p.beginAwayTeamReturn(team.id, 14)).state == "returning",
    "the team enters the explicit return leg")
assert(p.getSurvivorDuty("return-a").mode == "away",
    "a member on the road is still owned by the mission")

local start = assert(p.awayTeamReturnProgress(team.id, 14))
assert(start.fraction == 0 and start.arrived == false,
    "the walk home begins at the mission site")
assert(math.abs(start.x - 9000) < 0.001 and math.abs(start.y - 9000) < 0.001,
    "the simulated body starts where the search happened")

local midway = assert(p.awayTeamReturnProgress(team.id, 15.5))
assert(math.abs(midway.fraction - 0.5) < 0.000001,
    "half the estimated walk is half the distance")
assert(math.abs(midway.x - (9000 + (105 - 9000) * 0.5)) < 0.01
    and math.abs(midway.y - (9000 + (204 - 9000) * 0.5)) < 0.01,
    "the simulated body is on the road, not at either end")
p.advanceAwayTeams(15.5)
assert(p.getAwayTeam(team.id).state == "returning",
    "an unfinished walk is not an arrival")
assert(p.getSurvivorDuty("return-a").mode == "away",
    "duty is not released while the member is still walking")

p.advanceAwayTeams(17.1)
local arrived = assert(p.getAwayTeam(team.id))
assert(arrived.state == "complete",
    "an unwatched return arrives on its own clock, not at the failure timeout")
assert(arrived.memberResults["return-a"].reason == "returned_offscreen",
    "the arrival names the off-screen walk that ended it")
assert(arrived.result.kind == "resource_run"
    and arrived.result.resources["Base.CannedBeans"] == 1,
    "the haul recorded by the live search survives the walk home")
assert(p.getSurvivorDuty("return-a").mode == "base",
    "the returned member resumes ordinary base duty")
local notices = Executor.takePlayerNotices("return-owner", 17.1, 3)
assert(#notices == 1 and string.find(notices[1], "Ada Marsh", 1, true) ~= nil
    and string.find(notices[1], "brought back 1", 1, true) ~= nil,
    "the completed trip reports the real person and haul once")

-- A body that is still loaded is walking home itself: elapsed time must not
-- complete the return underneath it, and the failure boundary still applies.
local guarded = assert(p.createAwayTeam("player", "return-owner", { "return-b" },
    "food", destination, 20, 23, home))
p.advanceAwayTeams(23)
assert(p.beginAwayTeamCollection(guarded.id, 23) ~= nil)
assert(p.recordAwayTeamCollection(guarded.id, "return-b", {}, 23.5) ~= nil)
assert(p.beginAwayTeamReturn(guarded.id, 24) ~= nil)
local loadedOnly = function(team, id) return id == "return-b" end
p.advanceAwayTeams(27, { returnMemberLoaded = loadedOnly })
assert(p.getAwayTeam(guarded.id).state == "returning",
    "a loaded member is not resolved from elapsed time")
assert(p.getSurvivorDuty("return-b").mode == "away",
    "the loaded member keeps its mission duty while it walks")
p.advanceAwayTeams(95.5, { returnMemberLoaded = loadedOnly })
assert(p.getAwayTeam(guarded.id).state == "returning",
    "a skipped member stays returning until the failure boundary")
p.advanceAwayTeams(96, { returnMemberLoaded = loadedOnly })
local expired = assert(p.getAwayTeam(guarded.id))
assert(expired.state == "blocked" and expired.result.reason == "return_timeout",
    "a body that never comes home still has the bounded failure boundary")
assert(p.getSurvivorDuty("return-b").mode == "base",
    "the expired member is released exactly once")

-- A mixed team resolves per member: the off-screen one walks home while the
-- loaded one keeps its own clock.
local mixed = assert(p.createAwayTeam("player", "return-owner",
    { "return-a", "return-b" }, "food", destination, 100, 103, home))
p.advanceAwayTeams(103)
assert(p.beginAwayTeamCollection(mixed.id, 103) ~= nil)
assert(p.recordAwayTeamCollection(mixed.id, "return-a", {}, 103.5) ~= nil)
assert(p.recordAwayTeamCollection(mixed.id, "return-b", {}, 103.5) ~= nil)
assert(p.beginAwayTeamReturn(mixed.id, 104) ~= nil)
p.advanceAwayTeams(108, { returnMemberLoaded = loadedOnly })
local partial = assert(p.getAwayTeam(mixed.id))
assert(partial.state == "returning",
    "the team waits for the member that is still walking")
assert(partial.memberResults["return-a"].reason == "returned_offscreen",
    "the off-screen member is recorded by the ledger")
assert(partial.memberResults["return-b"] == nil,
    "the loaded member is not recorded for it")
assert(p.getSurvivorDuty("return-a").mode == "base"
    and p.getSurvivorDuty("return-b").mode == "away",
    "only the member that actually arrived is released")
p.advanceAwayTeams(108.5)
local unified = assert(p.getAwayTeam(mixed.id))
assert(unified.state == "complete" and unified.result.kind == "resource_run",
    "the last member closes the same team result")
assert(p.getSurvivorDuty("return-b").mode == "base",
    "the final arrival releases the remaining member")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Away return travel PASS elapsed_walk=true no_teleport=true loaded_skipped=true "
    .. "mixed_team=true timeout_kept=true")
