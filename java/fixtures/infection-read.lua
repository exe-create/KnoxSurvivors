-- Infection and a bite are separate native facts. Exercise both real readers,
-- the snapshot, the work refusal and the eligibility gate without inferring a
-- wound or dialogue from a systemic infection flag.
local N = assert(rawget(_G, "codecIllnessNeeds"), "the needs rule is loaded")
local B = assert(rawget(_G, "codecPainGate"), "the eligibility gate is loaded")

local function wounded(bitten)
    return {getBodyDamage=function() return {getBodyParts=function() return {
        size=function() return 1 end,get=function() return {bitten=function() return bitten end} end,
    } end} end}
end
assert(N.biteReading(wounded(true))==true,"actual bite wound is read through vanilla BodyPart:bitten")
assert(N.biteReading(wounded(false))==false,"examined clean body can qualify for enlistment")
assert(N.biteReading(wounded(nil))==nil,"unreadable wounds are not a clean examination")

local function damage(infected, apparent, bite)
    local body = { getPain = function() return 0 end,
        getNumPartsBleeding = function() return 0 end,
        getHealth = function() return 100 end }
    if infected ~= nil then
        body.IsInfected = function() return infected end
    end
    if apparent ~= nil then
        body.getApparentInfectionLevel = function() return apparent end
    end
    if bite ~= nil then
        body.getBodyParts = wounded(bite).getBodyDamage().getBodyParts
    end
    return body
end

local function person(body)
    return {
        getBodyDamage = function() return body end,
        getCurrentSquare = function() return {} end,
        getStats = function() return { get = function() return 0 end } end,
    }
end

-- The flag is the answer when the body states it.
assert(N.infectionReading(person(damage(true))) == true, "an infected body reads infected")
assert(N.infectionReading(person(damage(false))) == false, "a clean body reads clean")
assert(N.infectionBand(person(damage(false, nil, true))) == "bitten",
    "nameplates and health dialogue name an actual bite before infection")
assert(N.infectionBand(person(damage(true, nil, false))) == "clear",
    "infection without a bite cannot produce a bitten nameplate or health answer")
assert(N.deathCause(person(damage(true, nil, false))) == "infection",
    "death evidence still reads systemic infection independently of bite wounds")
assert(N.deathCause(person(damage(false, nil, true))) == nil,
    "a bite alone cannot invent infection as a cause of death")

-- A visible bite is not a diagnosis inferred from infection.
assert(N.snapshot(person(damage(true, nil, false))).bitten == false,
    "systemic infection without a bite cannot label the snapshot Bitten")
assert(N.snapshot(person(damage(false, nil, true))).bitten == true,
    "an actual bite is visible before any infection flag")
assert(N.snapshot(person(damage(false, nil, false))).bitten == false, "an examined clean snapshot is clean")
assert(N.snapshot(person(damage(nil, nil))).bitten == nil, "an unread body is not clean")

-- An older body states the apparent level instead. Anything above zero is the
-- engine saying the body is infected.
assert(N.infectionReading(person(damage(nil, 0))) == false, "a zero level is clean")
assert(N.infectionReading(person(damage(nil, 1))) == true, "any level is infected")
assert(N.infectionReading(person(damage(nil, 40))) == true, "a high level is infected")
assert(N.infectionReading(person(damage(nil, nil))) == nil, "no reading is unknown")

-- Silence is not health: a body we cannot read is never reported as clean.
assert(N.infectionReading(nil) == nil, "no body is unknown")
assert(N.infectionReading({}) == nil, "no body damage is unknown")
assert(N.infectionBand(person(damage(nil, nil))) == nil, "an unread band is silent")
local broken = damage(true)
broken.IsInfected = function() error("no flag here") end
assert(N.infectionReading(person(broken)) == nil, "a failing read is unknown")

-- Heavy work is refused with its own reason, and light work is untouched.
local bitten = person(damage(false, nil, true))
assert(N.heavyWorkRefusal(bitten, "barricade") == "infected", "a bitten person does not board")
assert(N.heavyWorkRefusal(bitten, "haul_corpse") == "infected", "or haul a body")
assert(N.heavyWorkRefusal(bitten, "cook") == nil, "but still cooks")
assert(N.heavyWorkRefusal(bitten, "guard") == nil, "and still keeps watch")
assert(N.heavyWorkRefusal(person(damage(false)), "barricade") == nil,
    "a clean body takes the work")
assert(N.heavyWorkRefusal(person(damage(true, nil, false)), "barricade") == nil,
    "systemic infection alone cannot produce a refusal claiming a bite")

-- Pain keeps its own word: the two causes do not collapse into one.
local hurt = damage(false)
hurt.getPain = function() return 70 end
assert(N.heavyWorkRefusal(person(hurt), "barricade") == "in_pain", "pain keeps its reason")

-- The real gate passes the reason through instead of flattening it to eligible.
local runtime = rawget(_G, "KnoxSurvivorRuntime")
local createdRuntime = false
if runtime == nil then
    runtime = { getCharacter = function() return nil end }
    KnoxSurvivorRuntime = runtime
    createdRuntime = true
end
local storage = rawget(_G, "KnoxBaseStorage")
KnoxBaseStorage = { requirementsAvailable = function() return true, "eligible" end }
local realContains = B.containsSquare
B.containsSquare = function() return true end
local jobs = rawget(_G, "KnoxBaseJobs")
local realAtWork = jobs ~= nil and jobs.containsWorkSquare or nil
if jobs ~= nil then jobs.containsWorkSquare = function() return false end end
local P = assert(rawget(_G, "KnoxPersistence"), "persistence owner is loaded")
local realGetBase = P.getBase
local realDuty = P.getSurvivorDuty
local realCaps = P.getSurvivorCapabilities
P.getBase = function(id) return id == "home" and { id = "home" } or nil end
P.getSurvivorDuty = function() return { mode = "base", baseId = "home" } end
P.getSurvivorCapabilities = function() return {} end
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")
KnoxSurvivorNeeds = N

local realGetCharacter = runtime.getCharacter
KnoxSurvivorRuntime.getCharacter = function() return bitten end
local passed, reason = B.canPerformTask("resident", "home", { type = "barricade" })
assert(passed == false and reason == "infected",
    "the gate names infection, not pain: " .. tostring(reason))

KnoxSurvivorRuntime.getCharacter = function() return person(hurt) end
local hurtPassed, hurtReason = B.canPerformTask("resident", "home", { type = "barricade" })
assert(hurtPassed == false and hurtReason == "in_pain",
    "the gate still names pain: " .. tostring(hurtReason))

KnoxSurvivorRuntime.getCharacter = function() return person(damage(false)) end
local cleanReason = select(2, B.canPerformTask("resident", "home", { type = "cook" }))
assert(cleanReason ~= "infected" and cleanReason ~= "in_pain",
    "a clean body cooking is not refused for illness: " .. tostring(cleanReason))

KnoxSurvivorNeeds = previousNeeds
KnoxSurvivorRuntime.getCharacter = realGetCharacter
B.containsSquare = realContains
if jobs ~= nil and realAtWork ~= nil then jobs.containsWorkSquare = realAtWork end
P.getBase = realGetBase
P.getSurvivorDuty = realDuty
P.getSurvivorCapabilities = realCaps
KnoxBaseStorage = storage
if createdRuntime then KnoxSurvivorRuntime = nil end

print("Infection read PASS flag=true level=true unknown=true refuse=true gate=true")
