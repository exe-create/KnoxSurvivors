local M = assert(KnoxActivityFeed, "the notice feed is loaded")
assert(type(M.deathLine) == "function", "the death line projection is loaded")

local function line(attribution) return M.deathLine("Nora", attribution) end

assert(line({ kind = "survivor", name = "Owen" }) == "Nora was killed by Owen.",
    "a survivor killer is named")
assert(line({ kind = "survivor" }) == "Nora was killed by another survivor.",
    "an unidentified survivor killer is not invented")
assert(line({ kind = "player" }) == "Nora was killed by you.",
    "a player kill names the player")
assert(line({ kind = "zombie" }) == "Nora was killed by the dead.",
    "a zombie kill names the dead")
assert(line(nil) == "Nora has passed away.", "an unknown cause stays neutral")
assert(line({ kind = "other" }) == "Nora has passed away.",
    "an unrelated attacker does not fabricate a cause")
assert(M.deathLine("  Nora  ", { kind = "zombie" }) == "Nora was killed by the dead.",
    "names are trimmed")
assert(M.deathLine(nil, { kind = "zombie" }) == "Someone was killed by the dead.",
    "a missing name stays readable")
print("Death killfeed PASS survivor=true player=true zombie=true unknown=true")
