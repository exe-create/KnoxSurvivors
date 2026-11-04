local P = assert(KnoxPersistence, "persistence owner is loaded")
local J = assert(KnoxBaseJobs, "base jobs owner is loaded")
local realGet = P.getBase
local base = { id = "home", ownerKind = "player", ownerId = "player", settings = {} }
P.getBase = function(id) return id == "home" and base or nil end

assert(J.automaticBarricadeAllowed(base) == false,
    "a player base is manual until the player opts in")
base.settings.autoBarricade = true
assert(J.automaticBarricadeAllowed(base) == true,
    "the player's stored opt-in permits automatic boarding")
base.settings.autoBarricade = false
assert(J.automaticBarricadeAllowed(base) == false,
    "an explicit off keeps the base manual")
assert(J.automaticBarricadeAllowed({ ownerKind = "faction" }) == true,
    "a faction base keeps its automatic defense")
assert(J.automaticBarricadeAllowed(nil) == false,
    "a missing base has no automatic boarding")

local ok, reason = P.setBaseAutoBarricade("home", "player", true)
assert(ok == true and base.settings.autoBarricade == true,
    "the player can consent for their own base")
ok, reason = P.setBaseAutoBarricade("home", "player", false)
assert(ok == true and base.settings.autoBarricade == false,
    "the player can withdraw consent")
ok, reason = P.setBaseAutoBarricade("missing", "player", true)
assert(ok == false and reason == "missing_base", "a missing base is refused")
ok, reason = P.setBaseAutoBarricade("home", "stranger", true)
assert(ok == false and reason == "not_your_base" and base.settings.autoBarricade == false,
    "another player's base is never changed")
base.settings = nil
ok = P.setBaseAutoBarricade("home", "player", true)
assert(ok == true and type(base.settings) == "table"
    and base.settings.autoBarricade == true,
    "an old base without settings gains only the existing field")

P.getBase = realGet
print("Auto barricade PASS defaultOff=true optIn=true ownerGate=true missing=true")
