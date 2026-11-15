local P = KnoxPersistence
local old = { bases = P.getBases, residents = P.getBaseResidentIds, allocate = P.allocateWorldSurvivor,
    manager = KnoxBaseManager, runtime = KnoxSurvivorRuntime, settings = KnoxSettings,
    events = KnoxEvents, random = ZombRand, perks = Perks }
local base = assert(P.createBase("player", "radio-cadence-owner",
    { minX = 8100, minY = 8100, maxX = 8104, maxY = 8104, z = 0,
        width = 5, height = 5, buildingId = "radio-cadence-building" }, 100))
assert(P.setBaseRadioMode(base.id, "radio-cadence-owner", "broadcast", 100))
P.getBases = function() return { [base.id] = base } end
P.getBaseResidentIds = function() return { "radio-operator" } end
Perks = { Electricity = "electricity" }
KnoxSurvivorRuntime = { getCharacter = function() return {
    isDead = function() return false end, getPerkLevel = function() return 3 end } end }
KnoxBaseManager = codecRadioArrival
local raids, raider, scheduled = true, nil, 0
KnoxSettings = { allowFactionRaids = function() return raids end }
KnoxEvents = { radioRaider = function() return raider end,
    scheduleRaid = function() scheduled = scheduled + 1; return {} end }
local rolls, index = { 990, 990 }, 0
ZombRand = function() index = index + 1; return rolls[index] or 990 end
assert(codecRadioTick(100) == 0)
assert((P.getBaseRadioArrival(base.id) or {}).lastCallHours == 100,
    "a quiet radio call consumes the daily arrival attempt")
assert((P.getBaseRadioRisk(base.id) or {}).lastRiskHours == 100,
    "a missed risk roll consumes the daily risk attempt")
assert(P.getBaseRadioArrival(base.id).survivorId == nil,
    "an unanswered attempt does not invent an arrival")
assert(codecRadioTick(100.1) == 0 and P.getBaseRadioArrival(base.id).lastCallHours == 100,
    "the population cadence cannot retry the quiet call inside the same day")
rolls, index = { 990, 0 }, 0
assert(codecRadioTick(124) == 0 and scheduled == 0)
assert(P.getBaseRadioRisk(base.id).lastRiskHours == 124
    and P.getBaseRadioRisk(base.id).factionId == nil,
    "no eligible raider still spends the day without inventing a faction")
local allocations = 0
P.allocateWorldSurvivor = function() allocations = allocations + 1; return nil end
rolls, index = { 0 }, 0
assert(codecRadioTick(148) == 0 and allocations == 5,
    "a refused arrival tries only the existing bounded origin offsets")
assert(P.getBaseRadioArrival(base.id).lastCallHours == 148
    and P.getBaseRadioArrival(base.id).survivorId == nil,
    "refused allocation records the attempt without a fictitious survivor")
codecRadioTick(148.1)
assert(allocations == 5, "allocation refusal cannot reroll the same day")
P.allocateWorldSurvivor = old.allocate
rolls, index = { 0 }, 0
assert(codecRadioTick(172) == 1, "the next daily call can allocate a real world survivor")
local arrived = P.getBaseRadioArrival(base.id).survivorId
assert(arrived ~= nil and P.isSurvivorAlive(arrived), "a successful arrival names its real record")
rolls, index, raider = { 990, 0 }, 0, "fixture-eligible-faction"
assert(codecRadioTick(196) == 1 and scheduled == 1, "an eligible hostile answer schedules once")
assert(P.getBaseRadioRisk(base.id).factionId == raider, "risk records only the scheduled faction")
raids, rolls, index = false, { 990, 0 }, 0
assert(codecRadioTick(220) == 0 and scheduled == 1, "raids disabled stays authoritative")
P.getBases, P.getBaseResidentIds, P.allocateWorldSurvivor = old.bases, old.residents, old.allocate
KnoxBaseManager, KnoxSurvivorRuntime, KnoxSettings, KnoxEvents, ZombRand, Perks =
    old.manager, old.runtime, old.settings, old.events, old.random, old.perks
print("Radio attempt cadence PASS quiet=true allocationRefusal=true noRaider=true daily=true")
