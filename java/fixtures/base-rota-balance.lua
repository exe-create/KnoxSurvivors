local Catalog, P, Jobs = assert(KnoxOrderCatalog), assert(KnoxPersistence), assert(KnoxBaseJobs)
local function assertCoverage(roster)
    local rota = Catalog.rotaFor(roster, 10)
    for block = 0, 5 do
        local asleep, working = 0, 0
        for _, row in ipairs(roster) do
            local a = rota[row.id][block * 4 + 1]
            if a == "sleep" then asleep = asleep + 1 end
            if a == "work" or a == "guard" or a == "patrol" then working = working + 1 end
        end
        assert(asleep <= 2, "six residents never put more than two on sleep together")
        assert(working >= 1, "every block has a worker or watch resident")
    end
    local again = Catalog.rotaFor(roster, 10000)
    for _, row in ipairs(roster) do
        for hour = 1, 24 do
            assert(rota[row.id][hour] == again[row.id][hour], "world time never flips a resident's shift")
        end
    end
    return rota
end
local roster = {}
for i, role in ipairs({ "guard", "hauling", "repair", "farming", "cook", "scavenger" }) do
    roster[i] = { id = "rota-" .. i, role = role }
end
local expected = assertCoverage(roster)
for role in pairs(Catalog.baseRoleBlocks) do
    local same = {}
    for i = 1, 6 do same[i] = { id = "same-" .. i, role = role } end
    assertCoverage(same)
end
assert(Catalog.rotaFor(nil)["none"] == nil, "an absent roster creates no schedule")
for size = 2, 5 do
    local small = {}
    for i = 1, size do small[i] = { id = "small-" .. i, role = "hauling" } end
    local rota = Catalog.rotaFor(small)
    for block = 0, 5 do
        local workers = 0
        for _, row in ipairs(small) do
            local a = rota[row.id][block * 4 + 1]
            if a == "guard" or a == "patrol" or a == "work" then workers = workers + 1 end
        end
        assert(workers >= 1, "small crews keep an awake worker without removing sleep")
    end
    for _, row in ipairs(small) do
        local sleepHours = 0
        for _, a in ipairs(rota[row.id]) do if a == "sleep" then sleepHours = sleepHours + 1 end end
        assert(sleepHours == 8, "small-crew coverage preserves eight hours of scheduled sleep")
    end
end

-- Seed a saved NPC roster. This fixture tests schedule writing and resolution,
-- not faction membership or home admission. Restore the entire saved graph.
local priorData, priorTime, priorShelter = data, getGameTime, KnoxNightShelter
data = {}
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
local hour = 0
KnoxNightShelter = { currentHour = function() return hour end }
for _, row in ipairs(roster) do
    assert(P.setRecord(row.id, expectedRecord))
    local survivor = data.KnoxSurvivors_IsoPlayer.survivors[row.id]
    survivor.affiliation = { kind = "faction", factionId = "rota-faction" }
    survivor.duty = { mode = "base", baseId = "rota-base", jobPreference = row.role, revision = 0 }
end
data.KnoxSurvivors_IsoPlayer.bases["rota-base"] = { id = "rota-base", ownerKind = "faction", ownerId = "rota-faction" }
Jobs.scheduleAssignment(roster[1].id)
for _, row in ipairs(roster) do
    local duty = assert(P.getSurvivorDuty(row.id))
    assert(duty.scheduleAuto == true and duty.schedule ~= nil,
        "schedule resolution writes a balanced default through persistence")
    for h = 0, 23 do
        assert(P.scheduleAssignmentFor(duty.schedule, h) == expected[row.id][h + 1],
            "the written rota matches the pure roster decision")
    end
end
local revision = P.getSurvivorDuty(roster[1].id).revision
Jobs.scheduleAssignment(roster[1].id)
assert(P.getSurvivorDuty(roster[1].id).revision == revision,
    "an unchanged roster never rewrites its schedules")

assert(P.setRecord("rota-added", expectedRecord))
data.KnoxSurvivors_IsoPlayer.survivors["rota-added"].affiliation = { kind = "independent" }
data.KnoxSurvivors_IsoPlayer.survivors["rota-added"].duty = { mode = "base", baseId = "rota-base", jobPreference = "hauling" }
Jobs.scheduleAssignment(roster[1].id)
assert(P.getSurvivorDuty("rota-added").scheduleAuto == true, "a roster addition receives the recomputed rota")

local manual = { { from = 0, to = 24, assignment = "recreation" } }
assert(P.setDutySchedule(roster[1].id, manual, 11))
Jobs.scheduleAssignment(roster[2].id)
assert(P.getSurvivorDuty(roster[1].id).scheduleAuto == nil
    and P.getDutySchedule(roster[1].id)[1].assignment == "recreation",
    "an explicit schedule retires automatic ownership and survives rebalancing")
assert(P.setRecord("rota-player", expectedRecord))
data.KnoxSurvivors_IsoPlayer.survivors["rota-player"].affiliation = { kind = "player", ownerId = "owner" }
data.KnoxSurvivors_IsoPlayer.survivors["rota-player"].duty = { mode = "base", baseId = "rota-base" }
assert(Jobs.scheduleAssignment("rota-player") == "anything"
    and P.getDutySchedule("rota-player") == nil, "a player's unscheduled resident keeps anything")
data, getGameTime, KnoxNightShelter = priorData, priorTime, priorShelter
print("Base rota PASS sixResidents=true allRoleTemplates=true clockStable=true writer=true rosterChange=true manualPreserved=true playerUntouched=true nativeGameplay=false")
