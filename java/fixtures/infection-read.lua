-- The engine already marks a bitten body as infected on the BodyDamage blob this
-- mod persists whole. That fact reached nothing: a dying resident still took the
-- heavy work. This drives the real reader, the real refusal rule and the real
-- eligibility gate that every scheduler and the task board use.
local N = assert(rawget(_G, "codecIllnessNeeds"), "the needs rule is loaded")
local B = assert(rawget(_G, "codecPainGate"), "the eligibility gate is loaded")

local function damage(infected, apparent)
    local body = { getPain = function() return 0 end,
        getNumPartsBleeding = function() return 0 end,
        getHealth = function() return 100 end }
    if infected ~= nil then
        body.IsInfected = function() return infected end
    end
    if apparent ~= nil then
        body.getApparentInfectionLevel = function() return apparent end
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
assert(N.infectionBand(person(damage(true))) == "bitten", "the band has one word")
assert(N.infectionBand(person(damage(false))) == "clear", "a clean body is clear")

-- The snapshot is what the card's Needs line reads. It must carry the flag, not
-- only the reader: that line already had a Bitten branch and no producer.
assert(N.snapshot(person(damage(true))).bitten == true, "the snapshot carries a bite")
assert(N.snapshot(person(damage(false))).bitten == false, "a clean snapshot is clean")
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
local bitten = person(damage(true))
assert(N.heavyWorkRefusal(bitten, "barricade") == "infected", "a bitten person does not board")
assert(N.heavyWorkRefusal(bitten, "haul_corpse") == "infected", "or haul a body")
assert(N.heavyWorkRefusal(bitten, "cook") == nil, "but still cooks")
assert(N.heavyWorkRefusal(bitten, "guard") == nil, "and still keeps watch")
assert(N.heavyWorkRefusal(person(damage(false)), "barricade") == nil,
    "a clean body takes the work")

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
