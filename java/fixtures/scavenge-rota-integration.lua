local P, Parties, Jobs = assert(KnoxPersistence), assert(KnoxGroupScavenge), assert(KnoxBaseJobs)
local saved = { data = data, getGameTime = getGameTime, getCell = getCell,
    KnoxNightShelter = KnoxNightShelter, KnoxSurvivorNeeds = KnoxSurvivorNeeds,
    KnoxBaseStorage = KnoxBaseStorage }
local savedLeases = {}
for key, lease in pairs(Parties.leases()) do savedLeases[key] = lease Parties.leases()[key] = nil end
data = {}
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
getCell = function() return nil end
KnoxNightShelter = { currentHour = function() return 12 end, isNight = function() return false end }
KnoxSurvivorNeeds = { decide = function() return { kind = "roam" } end }
-- Actual supply planner consumes a known, empty loaded storage snapshot.
-- Containers and native bodies are the boundary; schedule and lease owners are real.
KnoxBaseStorage = { summarize = function() return { loadedPolicies = 1, totals = {} } end }
local owner = "scavenge-rota-owner"
local base = assert(P.createBase("player", owner,
    { minX = 0, minY = 0, width = 4, height = 4, z = 0 }, 10))
local ids, controllers = {}, {}
local home = { getX = function() return 1 end, getY = function() return 1 end, getZ = function() return 0 end }
local away = { getX = function() return 20 end, getY = function() return 20 end, getZ = function() return 0 end }
for i = 1, 4 do
    local id = "scavenge-rota-" .. tostring(i)
    ids[i] = id
    assert(P.setRecord(id, expectedRecord))
    assert(P.setPlayerCompanion(id, owner, "hold", 10))
    assert(P.setPlayerBaseResident(id, owner, base.id, 10))
    assert(P.setResidentLootRuns(id, owner, base.id, true, 10))
    local body = { square = home }
    body.getCurrentSquare = function(self) return self.square end
    controllers[id] = { id = id, character = body, base = base, baseId = base.id, state = "BASE_IDLE",
        setGroupMembers = function(self, members) self.groupMembers = members end,
        setGroupLeader = function(self, leaderId) self.groupLeaderId = leaderId end,
        clearGroupLeader = function(self) self.groupLeaderId = nil end,
        recallSettlementSortie = function(self) self.recalled = true end }
end
local function schedule(index, assignment)
    assert(P.setBaseDutySchedule(ids[index], owner, base.id,
        { { from = 0, to = 24, assignment = assignment } }, 10))
end
local tick = 2000000
local function coordinate()
    tick = tick + Parties.COORDINATE_INTERVAL_TICKS
    Parties.coordinate(controllers, ids, tick)
end
local function clearLeases()
    for key in pairs(Parties.leases()) do Parties.leases()[key] = nil end
    for _, c in pairs(controllers) do
        c.groupLeaderId, c.groupMembers, c.baseSupplyParty = nil, nil, nil
        c.scavengeSortieUntilHours, c.scavengeSortieReturning = nil, nil
        c.character.square = home
    end
end
local key = "base:" .. tostring(base.id)
-- An all-rest roster must not form a pair, even with a real stock shortage.
for i = 1, 4 do schedule(i, "sleep") end
coordinate()
assert(Parties.leases()[key] == nil, "sleep schedules prevent a fresh automatic scavenging pair")
for i = 1, 4 do schedule(i, "recreation") end
coordinate()
assert(Parties.leases()[key] == nil, "recreation schedules also prevent a fresh pair")
-- Three working residents may send two, leaving a scheduled worker at home.
schedule(1, "sleep")
for i = 2, 4 do schedule(i, "work") end
coordinate()
local lease = assert(Parties.leases()[key], "three on-duty residents can send one pair")
assert(lease.purpose == "base_supply" and lease.leaderId ~= ids[1] and lease.followerId ~= ids[1],
    "the real coordinator selects working residents instead of the sleeping first candidate")
assert(controllers[lease.followerId].groupLeaderId == lease.leaderId,
    "the accepted pair retains the existing leader and follower projection")
-- The schedule boundary alone cannot tear apart a committed outing.
controllers[lease.leaderId].character.square = away
controllers[lease.followerId].character.square = away
for i = 1, 4 do schedule(i, "sleep") end
coordinate()
assert(Parties.leases()[key] == lease and not lease.returning,
    "a schedule change does not revoke an already committed supply pair")
-- Explicit stay-home still prevents fresh admission through existing duty owner.
clearLeases()
for i = 1, 4 do schedule(i, "work") end
for i = 1, 3 do assert(P.setResidentLootRuns(ids[i], owner, base.id, false, 10)) end
coordinate()
assert(Parties.leases()[key] == nil, "scheduled work cannot override a stay-home order")
for i = 1, 3 do assert(P.setResidentLootRuns(ids[i], owner, base.id, true, 10)) end
-- Total population alone is insufficient: two working residents must not both
-- depart while the only two residents left home are on scheduled breaks.
schedule(1, "sleep") schedule(2, "recreation")
coordinate()
assert(Parties.leases()[key] == nil, "two on-duty residents cannot leave only scheduled sleepers and recreation at home")
schedule(2, "work")
coordinate()
assert(Parties.leases()[key] ~= nil, "the outing becomes available when a third resident is on duty")
clearLeases()
-- Pairs must consume the same job goals as individual runners, through real
-- loaded-container counting, rather than duplicate per-task maximums.
local Storage, Planner = assert(saved.KnoxBaseStorage), assert(KnoxBaseSupplyPlanner)
local oldSummary = Storage.summarize
KnoxBaseStorage = Storage
local totals = { food = 50, water = 50, medical = 50, weapons = 50, tools = 50,
    logs = 50, building = 50, clothing = 50, ammunition = 50, fuel = 50 }
Storage.summarize = function() return { loadedPolicies = 1, totals = totals } end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local stock = {}
local container = { getType = function() return "crate" end, isExistYet = function() return true end,
    getItems = function() return list(stock) end }
local object = { getContainerCount = function() return 1 end,
    getContainerByIndex = function() return container end, getObjectIndex = function() return 0 end,
    getSquare = function() return home end }
home.getObjects = function() return list({ object }) end
getCell = function() return { getGridSquare = function(_, x, y, z)
    if x == 1 and y == 1 and z == 0 then return home end
end } end
for i = 1, 4 do schedule(i, "work") end
base.tasks = {
    { state = "queued", requirements = { items = { ["Base.Nails"] = 2 } } },
    { state = "queued", requirements = { items = { ["Base.Nails"] = 3 } } },
}
coordinate()
lease = assert(Parties.leases()[key], "queued job shortages alone can send a real pair")
assert(lease.supplyNeeds.types["Base.Nails"] == 5,
    "a pair adds both queued consumable demands instead of taking the largest task")
stock[1] = { getFullType = function() return "Base.Nails" end, getCount = function() return 2 end }
local sameNeeds = lease.supplyNeeds
coordinate()
assert(lease.supplyNeeds == sameNeeds and sameNeeds.types["Base.Nails"] == 3,
    "live pair demand refresh keeps its shared table and subtracts actual delivered stock")
stock[1].getCount = function() return 5 end
coordinate()
assert(sameNeeds.types["Base.Nails"] == nil, "delivered consumables clear the pair's job goal")
clearLeases()
stock = {}
base.tasks = {}
for i = 1, 5 do
    base.tasks[i] = { state = "queued", requirements = { items = { ["Base.Saw"] = 1 },
        itemRules = { ["Base.Saw"] = { usable = true, minUses = 2 } } } }
end
coordinate()
lease = assert(Parties.leases()[key])
local requirements = assert(lease.supplyNeeds.typeRules["Base.Saw"])[1]
assert(lease.supplyNeeds.types["Base.Saw"] == 1,
    "five queued jobs make one shared usable saw goal for the pair")
local saw = { getFullType = function() return "Base.Saw" end,
    isBroken = function() return false end, getCurrentUses = function() return 1 end }
assert(not Planner.matchesRequirement(saw, requirements),
    "the pair carries the job's minimum-uses rule into its exact-item matcher")
saw.getCurrentUses = function() return 2 end
assert(Planner.matchesRequirement(saw, requirements), "an intact usable saw meets the pair's job rule")
stock[1] = saw
coordinate()
assert(lease.supplyNeeds.types["Base.Saw"] == nil, "a delivered usable shared saw clears pair demand")
saw.isBroken = function() return true end
coordinate()
assert(lease.supplyNeeds.types["Base.Saw"] == 1, "a broken stocked saw cannot satisfy paired job demand")
for _, task in ipairs(base.tasks) do task.state = "complete" end
coordinate()
assert(lease.supplyNeeds.types["Base.Saw"] == nil, "completed jobs create no continuing pair demand")
clearLeases()
coordinate()
assert(Parties.leases()[key] == nil, "satisfied floors and completed jobs do not create a fresh pair")
Storage.summarize = oldSummary
for key, lease in pairs(savedLeases) do Parties.leases()[key] = lease end
data, getGameTime, getCell = saved.data, saved.getGameTime, saved.getCell
KnoxNightShelter, KnoxSurvivorNeeds = saved.KnoxNightShelter, saved.KnoxSurvivorNeeds
KnoxBaseStorage = saved.KnoxBaseStorage
print("Scavenge rota integration PASS realCoordinator=true persistedSchedules=true restAdmission=true onDutyReserve=true committedPair=true stayHome=true summedMaterials=true sharedTool=true actualStock=true nativeGameplay=false")
