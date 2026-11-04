-- Pain is already captured from the native body, and until now the only thing
-- that listened was sleep. A person with a bad shoulder should sort a shelf, not
-- swing an axe. This drives the decision owner (Needs) and the real eligibility
-- gate (BaseManager.canPerformTask) that every scheduler and the Notebook use.
local N = assert(rawget(_G, "codecPainNeeds"), "the needs rule is loaded")
local B = assert(rawget(_G, "codecPainGate"), "the eligibility gate is loaded")
local P = assert(KnoxPersistence, "persistence owner is loaded")
-- The gate asks the global, so the fixture lends it the real rule and puts back
-- whatever was there. Later fixtures must not inherit a needs module.
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")
KnoxSurvivorNeeds = N

if rawget(_G, "CharacterStat") == nil then
    -- Harness shim only: snapshot asks for the native stat constants.
    CharacterStat = setmetatable({}, { __index = function(_, key) return key end })
end

local function body(pain)
    return {
        -- The gate reads the square first, so the stand-in body needs one.
        getCurrentSquare = function() return {} end,
        getStats = function()
            return { get = function(_, key) return 0 end }
        end,
        getBodyDamage = function()
            return {
                getPain = function() return pain end,
                getNumPartsBleeding = function() return 0 end,
                getHealth = function() return 100 end,
            }
        end,
    }
end

-- The bands, including "we cannot read this body", which is not "clear".
assert(N.painBand({ pain = 0 }) == "clear", "no pain is clear")
assert(N.painBand({ pain = 10 }) == "clear", "a small ache is not a band")
assert(N.painBand({ pain = 25 }) == "hurting", "hurting starts where the band says")
assert(N.painBand({ pain = 45 }) == "bad", "bad starts where the band says")
assert(N.painBand({ pain = 65 }) == "severe", "severe starts where the band says")
assert(N.painBand({ pain = nil }) == nil, "an unread body is not painless")
assert(N.painBand(nil) == nil, "no snapshot is not painless")

-- The reader path itself: real snapshot, fake body.
assert(N.heavyWorkRefusal(body(0), "barricade") == nil, "a healthy person boards a window")
assert(N.heavyWorkRefusal(body(30), "chop_tree") == nil, "a twinge does not stop an axe")
assert(N.heavyWorkRefusal(body(50), "barricade") == "in_pain", "real pain refuses boarding")
assert(N.heavyWorkRefusal(body(80), "haul_corpse") == "in_pain", "severe pain refuses a body")
assert(N.heavyWorkRefusal(body(80), "saw_logs") == "in_pain", "severe pain refuses the saw")
assert(N.heavyWorkRefusal(body(80), "farm_plow") == "in_pain", "severe pain refuses a plough")

-- Light work stays open, and so does a task nobody has classified.
assert(N.heavyWorkRefusal(body(80), "cook") == nil, "a hurt person still cooks")
assert(N.heavyWorkRefusal(body(80), "guard") == nil, "a hurt person can still keep watch")
assert(N.heavyWorkRefusal(body(80), "storage_sorting") == nil, "sorting is not heavy work")
assert(N.heavyWorkRefusal(body(80), nil) == nil, "an unclassified task is not refused")

-- A body whose pain cannot be read must not idle the settlement.
local unreadable = { getStats = body(0).getStats,
    getBodyDamage = function() return { getNumPartsBleeding = function() return 0 end,
        getHealth = function() return 100 end } end }
assert(N.heavyWorkRefusal(unreadable, "barricade") == nil,
    "unreadable pain refuses nothing")

-- The real gate: heavy work is refused with a cause, light work passes the pain
-- question. The heavy task never reaches the later requirement checks, which is
-- the point - pain is decided at the same boundary as every other question.
local runtime = rawget(_G, "KnoxSurvivorRuntime")
local createdRuntime = false
if runtime == nil then
    runtime = { getCharacter = function() return nil end }
    KnoxSurvivorRuntime = runtime
    createdRuntime = true
end
local storage = rawget(_G, "KnoxBaseStorage")
KnoxBaseStorage = { requirementsAvailable = function() return true, "eligible" end }

local realGetCharacter = runtime.getCharacter
local realContains = B.containsSquare
B.containsSquare = function() return true end
-- The work-area question needs a real grid square; the stand-in body has none.
local jobs = rawget(_G, "KnoxBaseJobs")
local realAtWork = jobs ~= nil and jobs.containsWorkSquare or nil
if jobs ~= nil then jobs.containsWorkSquare = function() return false end end

local realGetBase = P.getBase
local realDuty = P.getSurvivorDuty
local realCaps = P.getSurvivorCapabilities
P.getBase = function(id) return id == "home" and { id = "home" } or nil end
P.getSurvivorDuty = function() return { mode = "base", baseId = "home" } end
P.getSurvivorCapabilities = function() return {} end

local function gate(pain, taskType, action)
    KnoxSurvivorRuntime.getCharacter = function() return body(pain) end
    return B.canPerformTask("resident", "home",
        { type = taskType, target = action ~= nil and { action = action } or nil })
end

local passed, reason = gate(80, "barricade")
assert(passed == false and reason == "in_pain",
    "the gate refuses boarding to a person in real pain")
passed, reason = gate(80, nil, "haul_corpse")
assert(passed == false and reason == "in_pain",
    "a task named only by its action is refused too")
passed, reason = gate(0, "barricade")
assert(reason ~= "in_pain", "a healthy person is not refused for pain")
passed, reason = gate(80, "cook")
assert(reason ~= "in_pain", "light work is never refused for pain")

-- The refusal reason survives the assignment boundary instead of becoming a
-- generic "not eligible". This calls the real canClaimSpecific, loaded from its
-- source section: a fixture that skipped this because the module was absent would
-- be claiming proof it never had.
local Board = assert(rawget(_G, "codecClaimBoard"), "the assignment gate is loaded")
local previousManager = rawget(_G, "KnoxBaseManager")
KnoxBaseManager = B
local realAffiliation = P.getSurvivorAffiliation
local realClaimGet = P.getBase
P.getBase = function(id) return id == "home" and {
    id = "home", ownerKind = "player", ownerId = "player",
    tasks = { t1 = { id = "t1", state = "queued", type = "barricade" } },
} or nil end
P.getSurvivorAffiliation = function()
    return { kind = "player", ownerId = "player" }
end
KnoxSurvivorRuntime.getCharacter = function() return body(80) end
local allowed, refusal = Board.canClaimSpecific("home", "t1", "resident", "player")
assert(allowed == false and refusal == "in_pain",
    "the assignment surface keeps the real reason")
P.getBase = realClaimGet
P.getSurvivorAffiliation = realAffiliation
KnoxBaseManager = previousManager
KnoxSurvivorRuntime.getCharacter = realGetCharacter
B.containsSquare = realContains
if jobs ~= nil and realAtWork ~= nil then jobs.containsWorkSquare = realAtWork end
P.getBase = realGetBase
P.getSurvivorDuty = realDuty
P.getSurvivorCapabilities = realCaps
KnoxBaseStorage = storage
if createdRuntime then KnoxSurvivorRuntime = nil end
KnoxSurvivorNeeds = previousNeeds

print("Pain work PASS bands=true heavy=true light=true gate=true reason=true")
