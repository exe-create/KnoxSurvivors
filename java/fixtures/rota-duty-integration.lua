local C, P, Jobs = assert(KnoxAutonomyController), assert(KnoxPersistence), assert(KnoxBaseJobs)
local oldData, oldTime, oldCell, oldShelter = data, getGameTime, getCell, KnoxNightShelter
local oldRuntime, oldGroups, oldNeeds = KnoxSurvivorRuntime, KnoxGroupScavenge, KnoxSurvivorNeeds
local oldPrepare, oldSummary = Jobs.prepareWorkforce, KnoxBaseStorage.summarize
data = {}
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
getCell = function() return nil end
KnoxNightShelter = { currentHour = function() return 0 end }
KnoxGroupScavenge = nil
local ids = { "a-rota-sleeper", "z-rota-worker" }
local owner = "rota-duty-owner"
local base = assert(P.createBase("player", owner, { minX = 0, minY = 0, width = 3, height = 3, z = 0 }, 10))
local sq = { getX = function() return 1 end, getY = function() return 1 end, getZ = function() return 0 end }
local body = { getCurrentSquare = function() return sq end }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, expectedRecord))
    assert(P.setPlayerCompanion(id, owner, "hold", 10))
    assert(P.setPlayerBaseResident(id, owner, base.id, 10))
    assert(P.setResidentLootRuns(id, owner, base.id, true, 10))
end
local function hours(id, assignment)
    assert(P.setBaseDutySchedule(id, owner, base.id, { { from = 0, to = 24, assignment = assignment } }, 10))
end
hours(ids[1], "sleep")
hours(ids[2], "work")
local bodies = {}
KnoxSurvivorRuntime = { getCharacter = function(id) return bodies[id] end,
    snapshot = function() return { loaded = true, state = "BASE_IDLE" } end }
bodies[ids[1]], bodies[ids[2]] = body, body
Jobs.prepareWorkforce = function() return true, {} end
KnoxBaseStorage.summarize = function() return { loadedPolicies = 1, totals = {} } end
local sleeper = setmetatable({ id = ids[1], baseId = base.id, base = base }, { __index = C })
assert(sleeper:baseSupplyNeed(100) == nil and sleeper.nextBaseSupplySearch == nil,
    "scheduled sleep refuses a fresh supply election without starting its search cooldown")
hours(ids[1], "recreation")
assert(sleeper:baseSupplyNeed(101) == nil and sleeper.nextBaseSupplySearch == nil,
    "scheduled recreation also refuses fresh supply work")
hours(ids[1], "sleep")
local worker = setmetatable({ id = ids[2], baseId = base.id, base = base }, { __index = C })
assert(worker:baseSupplyNeed(100) == "find_food" and worker.baseSupplyTrip == true,
    "the awake resident wins supply election over the earlier-named sleeping resident")

-- Reach the real think entry. Native world/needs and unrelated early owners
-- are doubled, retaining actual at-home arbitration and explicit-order flow.
KnoxSurvivorNeeds = { decide = function() return { kind = "roam" } end,
    isMedicalCare = function() return false end }
local alarms, sleeps, searches = 0, 0, 0
local alarm = false
local thinker = setmetatable({ id = ids[1], character = body, base = base, baseId = base.id,
    state = "BASE_IDLE", nextThreatScan = 1000000, counts = {}, failedThreats = {},
    selfCareRetryAt = {}, perceivedThreats = {}, reservations = {},
}, { __index = C })
for _, method in ipairs({ "beginGroupSupport", "beginInventoryCleanup", "beginEventTravel", "followScavengeParty" }) do
    thinker[method] = function() return false end
end
thinker.allowsCompanionThreat = function() return false end
thinker.syncBaseSupplyRun = function() end
thinker.applyResidentStayHome = function() end
thinker.raiseStructuralAlarm = function() alarms = alarms + 1 end
thinker.answerBaseAlarm = function() return alarm end
thinker.beginScheduledBaseSleep = function() sleeps = sleeps + 1 end
thinker.baseSupplyNeed = function() searches = searches + 1 return nil end
thinker.runScavengeSortie = function() searches = searches + 1 return true end
thinker.beginWorldSearch = function() searches = searches + 1 return true end
thinker.beginBaseSupplyRun = function() return true end
thinker:think(200)
assert(alarms == 1 and sleeps == 1 and searches == 0,
    "the real think answers structural danger then sleeps before fresh automatic work")
alarm = true
thinker:think(201)
assert(alarms == 2 and sleeps == 1 and searches == 0,
    "a base alarm still interrupts a scheduled sleep window")
alarm = false
thinker.baseSupplyOrder = { kind = "find_food" }
thinker:think(202)
assert(searches == 1 and sleeps == 1, "an explicit supply order retains its existing priority")

-- P4: a faction resident that streams in at its own faction base answers the
-- same shortage facts through the same owner, and departs through it. No new
-- election, no new field, no second simulation.
local factionId, fbaseId = "rota-duty-faction", "rota-duty-faction-base"
local fid = "m-rota-faction-runner"
local root = data.KnoxSurvivors_IsoPlayer
root.factions[factionId] = { id = factionId, name = "Rota Faction", kind = "npc",
    leaderId = fid, memberIds = { fid } }
local fbase = { id = fbaseId, ownerKind = "faction", ownerId = factionId,
    home = { minX = 20, minY = 20, width = 4, height = 4, z = 0 },
    territory = { minX = 20, minY = 20, maxX = 23, maxY = 23, z = 0 } }
root.bases[fbaseId] = fbase
assert(P.setRecord(fid, expectedRecord))
root.survivors[fid].affiliation = { kind = "faction", factionId = factionId }
assert(P.setFactionBaseResident(fid, factionId, fbaseId, 10),
    "the real persistence writer seats the faction resident through its own gate")
-- The first attempt was refused for a real reason: the default rota put this
-- resident asleep at the tested hour. A wake resident is the ordinary loaded
-- state the election is meant to answer, so give them a work window.
assert(P.setDutySchedule(fid, { { from = 0, to = 24, assignment = "work" } }, 10))
assert(Jobs.isRestWindow(fid) ~= true, "the seated runner is awake for the tested hour")
local fsq = { getX = function() return 21 end, getY = function() return 21 end,
    getZ = function() return 0 end }
local fbody = { getCurrentSquare = function() return fsq end }
bodies[fid] = fbody
KnoxBaseStorage.summarize = function() return { loadedPolicies = 1, totals = {} } end -- P4-PROVABLE-STOCK

local function countTasks(board)
    local total = 0
    for _ in pairs(type(board) == "table" and board.tasks or {}) do total = total + 1 end
    return total
end
local factionRunner = setmetatable({ id = fid, baseId = fbaseId, base = fbase }, { __index = C })
local elected = factionRunner:baseSupplyNeed(100)
assert(elected == "find_food",
    "a faction resident at its own base answers a provable shortage: " .. tostring(elected)
    .. " roster=" .. #P.getBaseResidentIds(fbaseId)
    .. " inside=" .. tostring(KnoxBaseManager.containsSquare(fbase, fsq))
    .. " present=" .. tostring(P.isSurvivorPresent(fid)))
assert(factionRunner.baseSupplyTrip == true and factionRunner.baseSupplyKind == "find_food",
    "the existing election hands the trip to the same loaded think")
assert(countTasks(fbase) == 0, "the election creates no task and completes none")
assert(P.getSurvivorDuty(fid).baseSupplyOrder == nil, "the election writes no order field")

local departures = { searches = 0, runs = 0, kind = nil }
local factionThinker = setmetatable({ id = fid, character = fbody, base = fbase, baseId = fbaseId,
    state = "BASE_IDLE", nextThreatScan = 1000000, counts = {}, failedThreats = {},
    selfCareRetryAt = {}, perceivedThreats = {}, reservations = {} }, { __index = C })
for _, method in ipairs({ "beginGroupSupport", "beginInventoryCleanup", "beginEventTravel", "followScavengeParty" }) do
    factionThinker[method] = function() return false end
end
factionThinker.allowsCompanionThreat = function() return false end
factionThinker.syncBaseSupplyRun = function() end
factionThinker.applyResidentStayHome = function() end
factionThinker.raiseStructuralAlarm = function() end
factionThinker.answerBaseAlarm = function() return false end
factionThinker.beginScheduledBaseSleep = function() return false end
factionThinker.beginWorldSearch = function(self, kind)
    departures.searches = departures.searches + 1
    departures.kind = kind
    return true
end
factionThinker.beginBaseSupplyRun = function(self, kind)
    departures.runs = departures.runs + 1
    departures.runKind = kind
    return true
end
local needCalls, needResult = 0, nil
local realNeed = C.baseSupplyNeed
factionThinker.baseSupplyNeed = function(self, ticks)
    needCalls = needCalls + 1
    needResult = realNeed(self, ticks)
    return needResult
end
factionThinker:think(300)
assert(departures.searches == 1 and departures.runs == 1 and departures.kind == "find_food",
    "the streamed-in resident departs on load through beginWorldSearch then beginBaseSupplyRun"
    .. " needCalls=" .. needCalls .. " need=" .. tostring(needResult)
    .. " searches=" .. departures.searches .. " runs=" .. departures.runs
    .. " kind=" .. tostring(departures.kind))

-- The same owner must refuse when the stock cannot be proven, exactly as P2
-- refuses labour: no fact means no election, and nothing is created to fill it.
KnoxBaseStorage.summarize = function() return { loadedPolicies = 0, totals = {} } end
local unknownRunner = setmetatable({ id = fid, baseId = fbaseId, base = fbase }, { __index = C })
assert(unknownRunner:baseSupplyNeed(400) == nil and unknownRunner.baseSupplyTrip ~= true,
    "unknown stored stock elects nobody")
assert(countTasks(fbase) == 0, "a refused election creates no task and completes none")
assert(P.getSurvivorDuty(fid).baseSupplyOrder == nil, "a refused election writes no order field")

Jobs.prepareWorkforce, KnoxBaseStorage.summarize = oldPrepare, oldSummary
data, getGameTime, getCell, KnoxNightShelter = oldData, oldTime, oldCell, oldShelter
KnoxSurvivorRuntime, KnoxGroupScavenge, KnoxSurvivorNeeds = oldRuntime, oldGroups, oldNeeds
print("Rota duty integration PASS selfRest=true candidateRest=true realThink=true alarmPriority=true explicitOrder=true factionElected=true factionDeparts=true unknownNoElection=true nativeGameplay=false")
