local Persistence = assert(KnoxPersistence, "persistence is loaded")
local Jobs = assert(KnoxBaseJobs, "base jobs are loaded")

for _, intent in ipairs({ "security", "stockpile", "shelter", "health",
    "growth", "trade", "vengeance" }) do
    assert(Persistence.validBaseIntent(intent) == true,
        "known base intent is valid: " .. intent)
end
assert(Persistence.validBaseIntent(nil) == false, "nil intent is invalid")
assert(Persistence.validBaseIntent("") == false, "empty intent is invalid")
assert(Persistence.validBaseIntent("glory") == false, "unknown intent is invalid")

local base, created = Persistence.createBase(
    "player",
    "base-intent-player",
    { minX = 5000, minY = 5000, width = 3, height = 3, buildingId = "base-intent-building" },
    12
)
assert(base ~= nil and created == "created", "fixture base was created")
assert(Persistence.getBaseIntent(base.id) == nil, "a new base has no standing intent")

local ok, reason = Persistence.setBaseIntent(base.id, "base-intent-player", "security", 13)
assert(ok == true and reason == "saved", "owner can set a known intent")
assert(Persistence.getBaseIntent(base.id) == "security",
    "the setter persists the intent on the existing base record")

ok, reason = Persistence.setBaseIntent(base.id, "someone-else", "health", 14)
assert(ok == false and reason == "not_your_base",
    "another owner cannot change the base intent")
assert(Persistence.getBaseIntent(base.id) == "security",
    "a rejected owner does not mutate the intent")

ok, reason = Persistence.setBaseIntent(base.id, "base-intent-player", "glory", 14)
assert(ok == false and reason == "unknown_intent", "unknown intent is refused by name")
assert(Persistence.getBaseIntent(base.id) == "security",
    "a refused intent leaves the previous value intact")

base.intent = "glory"
assert(Persistence.getBaseIntent(base.id) == nil,
    "a corrupt saved intent reads as no intent")
base.intent = "health"
assert(Persistence.getBaseIntent(base.id) == "health",
    "a valid intent survives a read")

assert(Jobs.intentAffinity("security", "guard") == 10,
    "security weights guard work")
assert(Jobs.intentAffinity("security", "patrol_area") == 10,
    "legacy patrol labels use the canonical task type")
assert(Jobs.intentAffinity("health", "cook") == 8, "health weights cooking")
assert(Jobs.intentAffinity("health", "guard") == 0,
    "an unrelated task gets no intent weight")
assert(Jobs.intentAffinity("glory", "guard") == 0,
    "an unknown intent is inert")
assert(Jobs.intentAffinity(nil, "guard") == 0, "no intent is inert")

-- Drive the real selection function with one resident so the minimum-watch
-- pass does not decide the result. The two tasks have equal priority; only the
-- leader intent breaks the tie.
local original = {
    getBase = Persistence.getBase,
    getBaseResidentIds = Persistence.getBaseResidentIds,
    getSurvivorDuty = Persistence.getSurvivorDuty,
    getSurvivorAffiliation = Persistence.getSurvivorAffiliation,
    getWorkPreferences = Persistence.getWorkPreferences,
}
local fakeBase = {
    id = "base-intent-selection",
    ownerKind = "player",
    ownerId = "base-intent-player",
    intent = "security",
    tasks = {},
}
Persistence.getBase = function(id)
    if id == fakeBase.id then return fakeBase end
    return original.getBase(id)
end
Persistence.getBaseResidentIds = function() return { "resident-intent" } end
Persistence.getSurvivorDuty = function()
    return {
        mode = "base",
        baseId = fakeBase.id,
        ownerId = "base-intent-player",
        jobPreference = "auto",
    }
end
Persistence.getSurvivorAffiliation = function()
    return { kind = "player", ownerId = "base-intent-player" }
end
Persistence.getWorkPreferences = function() return nil end

local tasks = {
    { id = "intent-guard", type = "guard", state = "queued", priority = 50 },
    { id = "intent-cook", type = "cook", state = "queued", priority = 50 },
}
local picked = Jobs.selectEligibleTask(
    tasks, "resident-intent", fakeBase.id, "auto", function() return true end)
assert(picked ~= nil and picked.type == "guard",
    "security intent breaks an equal-priority tie toward guard work")

fakeBase.intent = "health"
picked = Jobs.selectEligibleTask(
    tasks, "resident-intent", fakeBase.id, "auto", function() return true end)
assert(picked ~= nil and picked.type == "cook",
    "health intent breaks the same tie toward cooking")

Persistence.getBase = original.getBase
Persistence.getBaseResidentIds = original.getBaseResidentIds
Persistence.getSurvivorDuty = original.getSurvivorDuty
Persistence.getSurvivorAffiliation = original.getSurvivorAffiliation
Persistence.getWorkPreferences = original.getWorkPreferences
