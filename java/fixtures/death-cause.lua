-- A death recorded where and when, never why. The body still knows at the moment
-- it stops, and the hibernated state carries the facts it died with, so the cause
-- is read by the producer that has it and stored on the existing death evidence.
local N = assert(rawget(_G, "codecDeathNeeds"), "the needs rule is loaded")
local F = assert(rawget(_G, "KnoxActivityFeed"), "the notice owner is loaded")
local P = assert(rawget(_G, "KnoxPersistence"), "persistence owner is loaded")

if rawget(_G, "CharacterStat") == nil then
    -- Harness shim only: the real snapshot asks for native stat constants.
    CharacterStat = setmetatable({}, { __index = function(_, key) return key end })
end

local function body(health, bleeding, infected)
    local damage = {
        getNumPartsBleeding = function() return bleeding or 0 end,
        getHealth = function() return health or 100 end,
        getPain = function() return 0 end,
        IsInfected = function() return infected == true end,
    }
    return {
        getBodyDamage = function() return damage end,
        getStats = function() return { get = function() return 0 end } end,
    }
end

-- The body's own reasons, in the order the rule states.
assert(N.deathCause(body(100, 0, true)) == "infection", "an infected body died of it")
assert(N.deathCause(body(100, 2, false)) == "bled_out", "real bleeding is a cause")
assert(N.deathCause(body(0, 0, false)) == "wounds", "a body at zero died of its wounds")
assert(N.deathCause(body(100, 0, false)) == nil, "a healthy body has no cause")
assert(N.deathCause(body(100, 2, true)) == "infection", "infection outranks bleeding")
assert(N.deathCause(nil) == nil, "no body is no cause")

-- A named attacker is attributed by the death line, not by an invented cause.
assert(N.deathCause(body(100, 0, false), "zombie") == "killed", "a killer is a cause")
assert(N.deathCause(body(0, 0, false), "survivor") == "wounds",
    "the body's own state outranks the attribution")
assert(N.deathCause(body(100, 0, false), "other") == nil,
    "an unknown attacker invents nothing")

-- The line says the cause only when no killer is named, and the killer wording
-- it already had is unchanged.
assert(F.deathLine("Ada", { kind = "zombie" }) == "Ada was killed by the dead.",
    "a killer still gets the killer line")
assert(F.deathLine("Ada", { kind = "zombie", cause = "infection" })
    == "Ada was killed by the dead.", "a witnessed killing does not become a fever")
assert(F.deathLine("Ada", { kind = "survivor", name = "Owen" })
    == "Ada was killed by Owen.", "a named killer is still named")
assert(F.deathLine("Ada", { cause = "infection" }) == "Ada was taken by the fever.",
    "the fever is named")
assert(F.deathLine("Ada", { cause = "bled_out" }) == "Ada bled out.", "bleeding is named")
assert(F.deathLine("Ada", { cause = "wounds" }) == "Ada died of their wounds.",
    "wounds are named")
assert(F.deathLine("Ada", {}) == "Ada has passed away.", "an unknown cause stays plain")
assert(F.deathLine("", nil) == "Someone has passed away.", "no name still reads")

-- Where there is no room for a sentence, the cause is one or two words. An
-- unknown cause has no word at all, so no surface invents one.
assert(N.deathCauseLabel("infection") == "fever", "infection reads as fever")
assert(N.deathCauseLabel("bled_out") == "bled out", "bleeding reads as bled out")
assert(N.deathCauseLabel("wounds") == "wounds", "wounds read as wounds")
assert(N.deathCauseLabel("killed") == "killed", "a killing reads as killed")
assert(N.deathCauseLabel(nil) == nil, "an unknown cause has no word")
assert(N.deathCauseLabel("a_stubbed_cause") == nil, "a made-up cause has no word")

-- The record keeps what the producer supplied and invents nothing on its own.
assert(P.ensureSurvivorIdentity("death_cause_fixture", "Ada", "Voss", 12) ~= nil,
    "the fixture identity is real")
assert(P.markSurvivorDead("death_cause_fixture", 20, "world_death", {
    x = 10, y = 12, z = 0, cause = "bled_out",
}) == true, "the death is recorded")
local evidence = assert(P.getSurvivorDeathEvidence("death_cause_fixture"),
    "the death evidence exists")
assert(evidence.cause == "bled_out", "the cause is stored on the evidence")
assert(evidence.x == 10 and evidence.y == 12, "the place is still stored")

P.ensureSurvivorIdentity("death_cause_plain", "Owen", "Rae", 12)
assert(P.markSurvivorDead("death_cause_plain", 20, "world_death",
    { x = 11, y = 12, z = 0 }) == true, "a cause-less death is still recorded")
local plain = assert(P.getSurvivorDeathEvidence("death_cause_plain"),
    "the cause-less evidence exists")
assert(plain.cause == nil, "a death with no supplied cause stores none")

print("Death cause PASS infection=true bleeding=true wounds=true line=true stored=true label=true")
