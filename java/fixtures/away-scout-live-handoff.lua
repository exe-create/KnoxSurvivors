-- A reconnaissance the player is watching stays live until a real search
-- resolves it; an unwatched one still resolves from the ledger, and duty
-- ownership is released exactly once. The fixture only exercises durable
-- transitions: no body, square, item or notice is invented.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
local Executor = KnoxAwayTeamExecutor
assert(type(Executor) == "table", "away-team executor must be loaded")

assert(p.setRecord("live-a", expectedRecord))
p.ensureSurvivorIdentity("live-a", "Nora", "Vance", 10, 34)
assert(p.setPlayerCompanion("live-a", "live-owner", "hold", 10))
local base = assert(p.createBase("player", "live-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "live-home",
}, 10, nil, true))
assert(p.setPlayerBaseResident("live-a", "live-owner", base.id, 10))

local destination = { x = 420, y = 430, z = 0, label = "Corner store" }
local watched = assert(p.createAwayTeam("player", "live-owner", { "live-a" },
    "scout", destination, 10, 10.5, nil))

local loadedMember = function() return true end
local watchedSite = function() return true end
p.advanceAwayTeams(10.5, {
    scoutSiteWatched = watchedSite,
    memberLoaded = loadedMember,
})
local live = assert(p.getAwayTeam(watched.id))
assert(live.state == "awaiting_collection",
    "a watched destination waits for the live member instead of resolving instantly")
assert(live.result.kind == "awaiting_live_scout",
    "the live handoff is named in the durable result")
assert(p.getSurvivorDuty("live-a").mode == "away",
    "duty stays with the mission while the site is live")
assert(#Executor.takePlayerNotices("live-owner", 10.6, 3) == 0,
    "a live reconnaissance is not reported as finished")

p.advanceAwayTeams(13, {
    scoutSiteWatched = watchedSite,
    memberLoaded = loadedMember,
})
assert(p.getAwayTeam(watched.id).state == "awaiting_collection",
    "a loaded member keeps the live sweep instead of being retired by the grace timer")

-- The player left: the member hibernated, so nothing is searching any more.
p.advanceAwayTeams(14, {
    scoutSiteWatched = function() return false end,
    memberLoaded = function() return false end,
})
local resolved = assert(p.getAwayTeam(watched.id))
assert(resolved.state=="awaiting_collection" and resolved.result.kind=="awaiting_live_scout",
    "leaving the area cannot invent reconnaissance or release mission duty")
assert(p.getSurvivorDuty("live-a").mode=="away","unobserved work remains assigned")
assert(#Executor.takePlayerNotices("live-owner",14,3)==0,"waiting is never announced as success")
assert(p.cancelAwayTeam(watched.id,"fixture_next_case",14))

-- Nobody was watching when the trip arrived: the old immediate completion
-- still applies, so an unwatched scout never waits for a live collection.
local unwatched = assert(p.createAwayTeam("player", "live-owner", { "live-a" },
    "scout", destination, 20, 20.5, nil))
p.advanceAwayTeams(20.5, {
    scoutSiteWatched = function() return false end,
    memberLoaded = function() return false end,
})
local immediate = assert(p.getAwayTeam(unwatched.id))
assert(immediate.state=="awaiting_collection" and immediate.result.kind=="awaiting_live_scout",
    "an unwatched arrival also requires real-world evidence")
assert(p.getSurvivorDuty("live-a").mode=="away","waiting retains the crew")
assert(p.cancelAwayTeam(unwatched.id,"fixture_next_case",21))

-- A resource mission keeps its own collection boundary: the scout grace must
-- never retire work that is still waiting for real loot.
local food = assert(p.createAwayTeam("player", "live-owner", { "live-a" },
    "food", destination, 30, 30.5, nil))
p.advanceAwayTeams(30.5, {
    scoutSiteWatched = function() return true end,
    memberLoaded = function() return false end,
})
assert(p.getAwayTeam(food.id).state == "awaiting_collection",
    "the scout grace does not retire a resource mission")

-- A mission the player watches is still the same durable roster; only the
-- native handoff is skipped. Its own setup failure must be reversible.
assert(p.setRecord("live-b", expectedRecord))
p.ensureSurvivorIdentity("live-b", "Owen", "Vance", 10, 34)
assert(p.setPlayerCompanion("live-b", "live-owner", "hold", 10))
assert(p.setPlayerBaseResident("live-b", "live-owner", base.id, 10))
local liveTeam = assert(p.createAwayTeam("player", "live-owner", { "live-b" },
    "scout", destination, 40, 40.5, nil, false))
assert(liveTeam.state == "outbound",
    "a live dispatch starts from the same durable outbound roster")
local arrived = assert(p.beginAwayTeamLiveArrival(liveTeam.id, 40))
assert(arrived.state == "awaiting_collection"
    and arrived.result.kind == "awaiting_live_scout",
    "a live arrival is recorded as a real mission at its destination")
assert(p.getSurvivorDuty("live-b").mode == "away",
    "the live member's duty is owned by the mission")

-- The player walked away from a live-dispatched mission: same grace as an
-- arrived scout, and the member's base duty comes back.
p.advanceAwayTeams(42.5, {
    scoutSiteWatched = function() return false end,
    memberLoaded = function() return false end,
})
local abandonedLive = assert(p.getAwayTeam(liveTeam.id))
assert(abandonedLive.state=="awaiting_collection" and abandonedLive.result.kind=="awaiting_live_scout",
    "a live-dispatched scout cannot become a success just because its body unloaded")
assert(p.getSurvivorDuty("live-b").mode=="away","unloaded scout keeps its mission duty")
assert(p.cancelAwayTeam(liveTeam.id,"fixture_next_case",43))

-- Setup failure before any native work: the roster and duty must roll back.
local failedSetup = assert(p.createAwayTeam("player", "live-owner", { "live-b" },
    "scout", destination, 50, 50.5, nil, false))
assert(p.beginAwayTeamLiveArrival(failedSetup.id, 50) ~= nil)
local cancelled = assert(p.cancelAwayTeam(failedSetup.id, "live_setup_failed", 50))
assert(cancelled.state == "blocked"
    and cancelled.result.kind == "dispatch_incomplete",
    "a cancelled live mission records an incomplete dispatch")
assert(p.getSurvivorDuty("live-b").mode == "base",
    "cancelling a live mission restores the member's duty")
assert(p.cancelAwayTeam("missing-team", "x", 50) == nil,
    "an unknown team cannot be cancelled")
assert(p.cancelAwayTeam(failedSetup.id, "again", 50) == nil,
    "a finished team cannot be cancelled twice")

data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Away scout live handoff PASS watched_live=true abandoned_waits=true unwatched_waits=true resources_untouched=true live_rollback=true")
