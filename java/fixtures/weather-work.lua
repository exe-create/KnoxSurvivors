-- A soaked or out-of-temperature survivor does not start outdoor base work.
-- The fixture drives the real needs rule and the real eligibility gate every
-- scheduler uses; only the engine body, the base store and the grid are stubbed,
-- and each stub is put back before it returns.
local N = assert(rawget(_G, "codecPainNeeds"), "the needs rule is loaded")
local B = assert(rawget(_G, "codecPainGate"), "the eligibility gate is loaded")
local P = assert(KnoxPersistence, "persistence owner is loaded")
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")
KnoxSurvivorNeeds = N

-- Engine boundary: a body, a square and the sky. Nothing here is the rule.
local function body(opts)
    opts = opts or {}
    local thermo = { getCoreTemperature = function() return opts.core or 37 end }
    return {
        getCurrentSquare = function()
            return { isOutside = function() return opts.inside ~= true end }
        end,
        getStats = function() return { get = function() return 0 end } end,
        getBodyDamage = function()
            return {
                getPain = function() return opts.pain or 0 end,
                getNumPartsBleeding = function() return 0 end,
                getHealth = function() return 100 end,
                getThermoregulator = function() return thermo end,
            }
        end,
        getClothingWetness = function() return opts.wetness or 0 end,
        -- Moodle levels are asked for by native constant, so the stand-in
        -- answers every request with the one level this body is meant to have.
        getMoodles = function()
            return { getMoodleLevel = function(_, kind) return opts.moodle or 0 end }
        end,
    }
end
local unreadable = { getCurrentSquare = body().getCurrentSquare,
    getStats = body().getStats,
    getBodyDamage = function() return { getPain = function() return 0 end } end }

-- Harness shim only: the native moodle constants the rule asks for.
local realMoodleType = rawget(_G, "MoodleType")
if realMoodleType == nil then
    MoodleType = { HYPERTHERMIA = "hyperthermia", HYPOTHERMIA = "hypothermia" }
end

-- The rule itself: only a body fact refuses the job, never the sky alone.
assert(N.weatherWorkRefusal(body({ wetness = 60 }), true) == "wet",
    "a soaked survivor refuses outdoor work")
assert(N.weatherWorkRefusal(body({ wetness = 60 }), false) == nil,
    "the same survivor still works indoors")
assert(N.weatherWorkRefusal(body({ wetness = 10 }), true) == nil,
    "a dry survivor works outside")
assert(N.weatherWorkRefusal(body({ core = 34 }), true) == "cold",
    "a cold core refuses outdoor work")
assert(N.weatherWorkRefusal(body({ moodle = 1 }), true) == "heat",
    "overheating refuses outdoor work")
assert(N.weatherWorkRefusal(unreadable, true) == nil,
    "an unreadable body refuses nothing")

-- Rain alone turns a person around through the shelter walk; it is not a work
-- refusal, so the gate does not double it.
local realClimate = rawget(_G, "getClimateManager")
getClimateManager = function()
    return { getRainIntensity = function() return 0.9 end }
end
assert(N.shelterReason(body({})) == "rain", "heavy rain is a shelter reason")
assert(N.weatherWorkRefusal(body({}), true) == nil,
    "rain alone does not refuse the job")
getClimateManager = realClimate

-- The real gate: heavy-work pain still outranks weather, an outdoor task is
-- refused with its body fact, and the same person is not refused indoors.
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
local realGetBase = P.getBase
local realDuty = P.getSurvivorDuty
local realCaps = P.getSurvivorCapabilities
P.getBase = function(id) return id == "home" and { id = "home" } or nil end
P.getSurvivorDuty = function() return { mode = "base", baseId = "home" } end
P.getSurvivorCapabilities = function() return {} end
local realGetCharacter = runtime.getCharacter

local function gate(opts, taskType)
    KnoxSurvivorRuntime.getCharacter = function() return body(opts) end
    return B.canPerformTask("resident", "home", { type = taskType or "chop_tree" })
end

local passed, reason = gate({ wetness = 60 })
assert(passed == false and reason == "weather=wet",
    "the gate refuses outdoor work to a soaked survivor")
passed, reason = gate({ wetness = 60, inside = true })
assert(reason ~= "weather=wet", "indoor work is not refused for being wet")
passed, reason = gate({ wetness = 10 })
assert(reason ~= "weather=wet", "a dry survivor is not refused for weather")
passed, reason = gate({ wetness = 60, pain = 80 })
assert(reason == "in_pain", "pain still outranks weather at the same gate")

KnoxSurvivorRuntime.getCharacter = realGetCharacter
B.containsSquare = realContains
if jobs ~= nil and realAtWork ~= nil then jobs.containsWorkSquare = realAtWork end
P.getBase = realGetBase
P.getSurvivorDuty = realDuty
P.getSurvivorCapabilities = realCaps
KnoxBaseStorage = storage
if createdRuntime then KnoxSurvivorRuntime = nil end
KnoxSurvivorNeeds = previousNeeds
if realClimate ~= nil then getClimateManager = realClimate end
if realMoodleType == nil then MoodleType = nil end

print("Weather work PASS wet=true indoor=false rainAlone=false cold=true heat=true gate=true painFirst=true")
