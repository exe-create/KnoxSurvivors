local p = KnoxPersistence
local e = KnoxAwayTeamExecutor

assert(e ~= nil, "away executor must be loaded")
assert(type(e.runContinues) == "function", "runContinues must exist")
assert(type(e.packFull) == "function", "packFull must exist")
-- Resource trips have no container-count deadline. Scouting is separate.
for _,searches in ipairs({1,3,30,300}) do
    local continues,why=e.runContinues({searches=searches,packFull=false,missionType="food"})
    assert(continues and why=="continue","resource runs stay out until actually full")
end
local continues,why=e.runContinues({searches=300,packFull=true,missionType="food"})
assert(not continues and why=="pack_full","a real carrying limit ends the search")
assert(e.runContinues({searches=3,missionType="scout"})==false,"scouting remains bounded")
assert(e.runContinues(nil)==false,"missing state refuses work")

-- Real weight against real capacity, and an unreadable body is not "full".
local function withInventory(weight, capacity)
    return {
        getInventory = function()
            return {
                getCapacityWeight = function() return weight end,
                getMaxWeight = function() return capacity end,
                getItems = function() return {size=function() return 0 end} end,
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

-- Restore the actual controller count from the durable member ledger, then
-- exercise its normal completion handoff into the real continuation decision.
local controller = setmetatable({id="resume-scout", awaySearches=99,
    releaseSupply=function() end, markAwayCargoDelivery=function() end},
    assert(KnoxAutonomyController))
local savedGet, savedRecord, savedReady = p.getAwayTeam, e.recordCollection, e.collectionReady
local teams = {
    resume={missionType="scout",searchProgress={["resume-scout"]={step=7}},
        collection={byMember={["resume-scout"]={searches=2,collected=false}}}},
    complete={missionType="scout",collection={byMember={["resume-scout"]={searches=3,collected=true}}}},
    empty={missionType="scout"},
    invalid={missionType="scout",collection={byMember={["resume-scout"]={searches=-4}}}},
}
p.getAwayTeam=function(id) return teams[id] end
controller:setAwayTeam("resume")
assert(controller.awaySearches==2 and controller.awaySearchStep==7 and not controller.awayCollected,
    "reactivation restores the member's two completed searches and existing phase")
local finalReceipt
e.recordCollection=function(_, _, _, _, _, final) finalReceipt=final; return {} end
e.collectionReady=function() return false end
assert(controller:finishAwayCollection(100) and finalReceipt==true and controller.awayCollected,
    "the next real completion reaches the scout limit using the restored count")
controller:setAwayTeam("complete")
assert(controller.awaySearches==3 and controller.awayCollected,
    "a completed scout restores all three searches and its completion flag")
controller.awaySearches=99
controller:setAwayTeam("empty")
assert(controller.awaySearches==0, "a new team without a member ledger clears stale searches")
controller:setAwayTeam("invalid")
assert(controller.awaySearches==0, "negative persisted searches normalize to zero")
controller.awaySearches=99
controller:setAwayTeam(nil)
assert(controller.awaySearches==0, "clearing the mission resets stale searches")
p.getAwayTeam, e.recordCollection, e.collectionReady = savedGet, savedRecord, savedReady

print("Supply run continuation PASS continues=true pack_full=true budget=true accumulate=true final_only=true legacy_one_shot=true")
