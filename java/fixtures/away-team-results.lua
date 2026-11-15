-- Base missions must report their persisted outcome exactly once, and a blocked
-- trip must never be described as a success. The fixture runs against a
-- temporary persistence root so the surrounding codec assertions keep their
-- exact cohort.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
local Executor = KnoxAwayTeamExecutor
assert(type(Executor) == "table", "away-team executor must be loaded")

local function seedSurvivor(id, forename, surname)
    assert(p.setRecord(id, expectedRecord))
    p.ensureSurvivorIdentity(id, forename, surname, 10, 34)
    assert(p.setPlayerCompanion(id, "codec-owner", "hold", 10))
end

seedSurvivor("notice-a", "Dana", "Reyes")
seedSurvivor("notice-b", "Milo", "Reyes")

local base = assert(p.createBase("player", "codec-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "notice-home",
}, 10, nil, true))
assert(p.setPlayerBaseResident("notice-a", "codec-owner", base.id, 10))
assert(p.setPlayerBaseResident("notice-b", "codec-owner", base.id, 10))

assert(Executor.memberLabel({ memberIds = { "notice-a", "notice-b" } })
    == "Dana Reyes and Milo Reyes", "notices use durable survivor names")

local scout = assert(p.createAwayTeam("player", "codec-owner", { "notice-a" },
    "scout", { x = 300, y = 310, z = 0, label = "Riverside" }, 10, 12, nil))
assert(#Executor.takePlayerNotices("codec-owner", 10.5, 3) == 0,
    "an outbound mission is not reported as finished")
p.advanceAwayTeams(12.5)
assert(p.getAwayTeam(scout.id).state=="awaiting_collection","elapsed travel is not a scout result")
assert(p.beginAwayTeamCollection(scout.id,12.5))
assert(p.recordAwayTeamCollection(scout.id,"notice-a",{},12.5,true))
assert(p.beginAwayTeamReturn(scout.id,12.5))
assert(p.completeAwayTeamMember(scout.id,"notice-a",true,"returned",12.5))
local scoutProgress = p.getAwayTeam(scout.id)
assert(scoutProgress.state == "complete" and type(scoutProgress.result) == "table",
    "the scout reaches its persisted completed state")
local notices = Executor.takePlayerNotices("codec-owner", 12.5, 3)
assert(#notices == 1, "one completed mission produces one notice")
assert(string.find(notices[1], "Dana Reyes", 1, true) ~= nil,
    "the notice names the real scout")
assert(string.find(notices[1], "scouted", 1, true) ~= nil
    and string.find(notices[1], "Riverside", 1, true) ~= nil,
    "the notice states the real outcome and destination")
assert(#Executor.takePlayerNotices("codec-owner", 12.6, 3) == 0,
    "a delivered notice is not repeated on the next tick")
assert(p.getAwayTeam(scout.id).resultSeenAtHours == 12.5,
    "the one-shot marker is durable")
assert(#Executor.takePlayerNotices("codec-other", 12.6, 3) == 0,
    "another player never receives a mission notice")

local food = assert(p.createAwayTeam("player", "codec-owner", { "notice-b" },
    "food", { x = 310, y = 320, z = 0, label = "West Point" }, 13, 14, nil))
p.advanceAwayTeams(15)
assert(p.getAwayTeam(food.id).state == "awaiting_collection",
    "a resource mission waits for a real collection")
assert(#Executor.takePlayerNotices("codec-owner", 15, 3) == 0,
    "an awaiting-collection mission is still active")
p.advanceAwayTeams(88)
local blocked = p.getAwayTeam(food.id)
assert(blocked.state == "blocked" and blocked.result.reason == "collection_timeout",
    "an uncollected resource mission registers a bounded failure")
local failed = Executor.takePlayerNotices("codec-owner", 88, 3)
assert(#failed == 1, "the blocked mission is reported once")
assert(string.find(failed[1], "could not complete", 1, true) ~= nil
    and string.find(failed[1], "West Point", 1, true) ~= nil,
    "a blocked trip is described as a failure at the real destination")
assert(p.getAwayTeam(food.id).resultSeenAtHours == 88,
    "the blocked result is acknowledged separately")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Away team results PASS scout_returned=true blocked_reported=true one_shot=true names_durable=true")
