local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local oldFeed, oldSettings, oldPersistence = KnoxActivityFeed, KnoxSettings, KnoxPersistence
local spoken = {}
local accept = true
KnoxActivityFeed = { speak = function(_, line)
    if not accept then return false end
    spoken[#spoken + 1] = line
    return true
end }
KnoxSettings = { showSurvivorSpeech = function() return true end }
KnoxPersistence = nil
D.resetRuntime()

local lines = { "One.", "Two.", "Three." }
local actor = {}
local ok, first = D.sayLines(actor, "a", "test", lines, 0, 240)
assert(ok and spoken[#spoken] == first, "first accepted line is spoken")
local before = D.chooseLine("a", "test", lines, 0)
local refused, reason = D.sayLines(actor, "a", "test", lines, 1, 240)
assert(not refused and reason == "cooldown", "event cooldown refuses speech")
assert(D.chooseLine("a", "test", lines, 0) == before, "cooldown does not consume variation")
local _, second = D.sayLines(actor, "a", "test", lines, 240, 240)
local _, third = D.sayLines(actor, "a", "test", lines, 480, 240)
assert(first ~= second and first ~= third and second ~= third, "all lines precede a repeat")
local _, fourth = D.sayLines(actor, "a", "test", lines, 720, 240)
assert(fourth ~= third, "cycle boundary avoids immediate repeat")

local independent = D.chooseLine("b", "test", lines, 0)
local untouched = D.chooseLine("a", "other", lines, 0)
D.rememberLine("a", "test", "additional", false)
assert(D.chooseLine("b", "test", lines, 0) == independent, "speakers are independent")
assert(D.chooseLine("a", "other", lines, 0) == untouched, "events are independent")
local eventRefused, globalReason = D.sayLines(actor, "a", "other", lines, 721, 240)
assert(not eventRefused and globalReason == "cooldown", "global cooldown covers other events")

local _, singleton = D.sayLines(actor, "single", "solo", { "Only." }, 0, 240)
local _, singletonAgain = D.sayLines(actor, "single", "solo", { "Only." }, 240, 240)
assert(singleton == "Only." and singletonAgain == singleton, "singleton remains usable")
accept = false
local failed, failure = D.sayLines(actor, "failed", "test", lines, 0, 240)
local retry = D.chooseLine("failed", "test", lines, 0)
assert(not failed and failure == "unavailable", "rejected speech stays unavailable")
accept = true
local retried, actual = D.sayLines(actor, "failed", "test", lines, 0, 240)
assert(retried and actual == retry, "rejected speech consumes neither cooldown nor line")

KnoxPersistence = {
    getSurvivorPersonality = function() return { personality = "brave" } end,
    getSurvivorIdentity = function() return { forename = "Nora", firstName = "Wrong" } end,
}
local _, witnessOne = D.sayWitness(actor, "witness", "target", 0, 240)
local _, witnessTwo = D.sayWitness(actor, "witness", "target", 240, 240)
assert(witnessOne ~= witnessTwo, "witness uses the whole voiced bank")
for _, line in ipairs({ witnessOne, witnessTwo }) do
    assert(line:find("Nora", 1, true) and not line:find("Wrong", 1, true), "witness uses target forename")
    assert(line == "I saw that. Nora did nothing to deserve it."
        or line == "Say it to Nora again. See what happens.", "witness uses a real authored line")
end
KnoxPersistence.getSurvivorIdentity = function() return nil end
local _, anonymous = D.sayWitness(actor, "other-witness", "target", 0, 240)
assert(anonymous:find("them", 1, true), "missing name uses a neutral reference")

D.resetRuntime()
KnoxActivityFeed, KnoxSettings, KnoxPersistence = oldFeed, oldSettings, oldPersistence
