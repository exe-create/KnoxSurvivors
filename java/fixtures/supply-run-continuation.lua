local p = KnoxPersistence
local e = KnoxAwayTeamExecutor

assert(e ~= nil, "away executor must be loaded")
assert(type(e.runContinues) == "function", "runContinues must exist")
assert(type(e.packFull) == "function", "packFull must exist")
assert(e.RUN_SEARCH_LIMIT == 3, "the bounded chain limit is three searches")

-- The decision that used to be missing: a run does not stop after one crate.
local continues, why = e.runContinues({ searches = 1, maxSearches = 3, packFull = false })
assert(continues == true and why == "continue", "a second container is still allowed")
continues, why = e.runContinues({ searches = 2, maxSearches = 3, packFull = false })
assert(continues == true and why == "continue", "the third container is still allowed")
continues, why = e.runContinues({ searches = 3, maxSearches = 3, packFull = false })
assert(continues == false and why == "search_budget", "the budget is a real stop")
continues, why = e.runContinues({ searches = 1, maxSearches = 3, packFull = true })
assert(continues == false and why == "pack_full", "a full pack is a real stop")
continues, why = e.runContinues({ searches = 1, packFull = false })
assert(continues == true, "a missing limit falls back to the shipped one")
continues, why = e.runContinues({ searches = nil, maxSearches = 1, packFull = false })
assert(continues == false and why == "search_budget", "an unknown count is not a free search")
continues, why = e.runContinues(nil)
assert(continues == false and why == "no_state", "no state never authorises a search")

-- Real weight against real capacity, and an unreadable body is not "full".
local function withInventory(weight, capacity)
    return {
        getInventory = function()
            return {
                getWeight = function() return weight end,
                getCapacityWeight = function() return capacity end,
            }
        end,
    }
end
assert(e.packFull(nil) == false)
assert(e.packFull({}) == false)
assert(e.packFull(withInventory(50, 100)) == false)
assert(e.packFull(withInventory(94, 100)) == false)
assert(e.packFull(withInventory(95, 100)) == true)
assert(e.packFull(withInventory(10, 0)) == false, "unknown capacity is not full")
assert(e.packFull({ getInventory = function() error("no inventory") end }) == false)

-- The ledger accumulates each container's real transfer and only then reports
-- the member as ready to return.
assert(p.setRecord("run-person", expectedRecord))
assert(p.setPlayerCompanion("run-person", "run-owner", "follow", 10))
assert(p.setRecord("run-legacy", expectedRecord))
assert(p.setPlayerCompanion("run-legacy", "run-owner", "follow", 10))
local team = assert(p.createAwayTeam(
    "player", "run-owner", { "run-person" }, "food",
    { x = 10, y = 10, z = 0, label = "Pantry" },
    12, 13, { x = 0, y = 0, z = 0, label = "Home" }
))
assert(team.state == "outbound")
assert(p.beginAwayTeamLiveArrival(team.id, 13))
assert(p.beginAwayTeamCollection(team.id, 13))

local collection, detail = p.recordAwayTeamCollection(
    team.id, "run-person", { "Base.CannedBeans" }, 13, false
)
assert(collection ~= nil and detail == "recorded", "the first container is recorded")
assert(collection.resources["Base.CannedBeans"] == 1)
assert(p.awayTeamCollectionReady(team.id) == false,
    "one container must not finish the run")

collection, detail = p.recordAwayTeamCollection(
    team.id, "run-person", { "Base.Potato", "Base.Potato" }, 14, false
)
assert(detail == "recorded" and collection.resources["Base.Potato"] == 2,
    "a second container adds to the same member's haul")
assert(p.awayTeamCollectionReady(team.id) == false,
    "two containers still do not finish the run")

collection, detail = p.recordAwayTeamCollection(
    team.id, "run-person", { "Base.Bandage" }, 15, true
)
assert(detail == "recorded" and collection.resources["Base.Bandage"] == 1)
assert(collection.byMember["run-person"].searches == 3, "every search is counted")
assert(p.awayTeamCollectionReady(team.id) == true,
    "the last acknowledged container makes the team ready to return")

local duplicate = p.recordAwayTeamCollection(team.id, "run-person", { "Base.Bandage" }, 15, true)
assert(duplicate ~= nil and duplicate.resources["Base.Bandage"] == 1,
    "a repeated acknowledgement never double counts")

local returned, returnDetail = p.beginAwayTeamReturn(team.id, 16)
assert(returned ~= nil and returnDetail == "returning",
    "the recorded run can hand off to the ordinary return leg")

-- The older one-shot contract is unchanged: a caller that passes no `final`
-- argument acknowledges its destination immediately.
local legacy = assert(p.createAwayTeam(
    "player", "run-owner", { "run-legacy" }, "tools",
    { x = 20, y = 20, z = 0, label = "Shed" },
    18, 19, { x = 0, y = 0, z = 0, label = "Home" }
))
assert(p.beginAwayTeamLiveArrival(legacy.id, 19))
assert(p.beginAwayTeamCollection(legacy.id, 19))
local oneShot = p.recordAwayTeamCollection(legacy.id, "run-legacy", { "Base.Hammer" }, 19)
assert(oneShot ~= nil and p.awayTeamCollectionReady(legacy.id) == true,
    "an omitted final argument keeps the old one-container contract")

print("Supply run continuation PASS continues=true pack_full=true budget=true accumulate=true final_only=true legacy_one_shot=true")
