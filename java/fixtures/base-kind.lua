local Persistence = assert(KnoxPersistence, "persistence is loaded")
local Jobs = assert(KnoxBaseJobs, "base jobs are loaded")

for _, kind in ipairs({ "main", "outpost", "storage", "checkpoint" }) do
    assert(Persistence.validBaseKind(kind) == true, "known kind is valid: " .. kind)
end
assert(Persistence.validBaseKind(nil) == false, "nil kind is invalid")
assert(Persistence.validBaseKind("") == false, "empty kind is invalid")
assert(Persistence.validBaseKind("warehouse") == false, "unknown kind is invalid")

local owner = "base-kind-owner"
local home, homeResult = Persistence.createBase(
    "player", owner,
    { minX = 7000, minY = 7000, width = 4, height = 4, buildingId = "base-kind-home" },
    10
)
assert(home ~= nil and homeResult == "created", "home base was created")
assert(Persistence.getBaseKind(home.id) == "main",
    "the first base of an owner is its main base without any stored value")
assert(home.kind == nil, "main is derived, so nothing is written to the record")

local second, secondResult = Persistence.createBase(
    "player", owner,
    { minX = 7100, minY = 7100, width = 4, height = 4, buildingId = "base-kind-outpost" },
    11, nil, true
)
assert(second ~= nil and secondResult == "created", "a second base was created")
assert(Persistence.getBaseKind(second.id) == "outpost",
    "a later base defaults to outpost")

local ok, reason = Persistence.setBaseKind(second.id, owner, "storage", 12)
assert(ok == true and reason == "saved", "owner can name a storehouse")
assert(Persistence.getBaseKind(second.id) == "storage", "the stored kind is read back")

ok, reason = Persistence.setBaseKind(second.id, owner, "checkpoint", 13)
assert(ok == true and reason == "saved", "owner can rename to checkpoint")
assert(Persistence.getBaseKind(second.id) == "checkpoint", "rename is saved")

ok, reason = Persistence.setBaseKind(second.id, "someone-else", "storage", 14)
assert(ok == false and reason == "not_your_base",
    "another player cannot change the kind")
assert(Persistence.getBaseKind(second.id) == "checkpoint",
    "a refused owner leaves the kind intact")

ok, reason = Persistence.setBaseKind(second.id, owner, "warehouse", 15)
assert(ok == false and reason == "unknown_kind", "an unknown kind is refused by name")
assert(Persistence.getBaseKind(second.id) == "checkpoint",
    "a refused kind leaves the previous value intact")

ok, reason = Persistence.setBaseKind(second.id, owner, "main", 16)
assert(ok == false and reason == "main_is_first_base",
    "a later base cannot become the main base")

ok, reason = Persistence.setBaseKind(home.id, owner, "checkpoint", 17)
assert(ok == false and reason == "main_base_fixed",
    "the main base cannot stop being the main base")
assert(Persistence.getBaseKind(home.id) == "main", "the main base is still main")

ok, reason = Persistence.setBaseKind(home.id, owner, "main", 18)
assert(ok == true and reason == "main_derived",
    "asking for main on the main base is accepted as the derived value")

-- A corrupt saved value reads as an ordinary secondary base rather than
-- inventing a kind the scheduler cannot weigh.
second.kind = "warehouse"
assert(Persistence.getBaseKind(second.id) == "outpost",
    "a corrupt stored kind reads as outpost")
second.kind = "storage"
assert(Persistence.getBaseKind(second.id) == "storage",
    "a valid stored kind survives a read")

assert(Jobs.kindAffinity("checkpoint", "guard") == 12, "a checkpoint weights guard work")
assert(Jobs.kindAffinity("checkpoint", "patrol") == 12, "a checkpoint weights patrols")
assert(Jobs.kindAffinity("checkpoint", "cook") == 0, "a checkpoint does not weight cooking")
assert(Jobs.kindAffinity("storage", "saw_logs") == 6, "a storehouse weights stock work")
assert(Jobs.kindAffinity("storage", "guard") == 0, "a storehouse does not weight guard work")
assert(Jobs.kindAffinity("main", "guard") == 0, "the main base keeps the intent's own weights")
assert(Jobs.kindAffinity(nil, "guard") == 0, "no kind is inert")
assert(Jobs.kindAffinity("glory", "guard") == 0, "an unknown kind is inert")

-- Kind must not displace the leader intent: same tie, intent still decides.
local fakeBase = {
    id = "base-kind-tie",
    ownerKind = "player",
    ownerId = owner,
    kind = "checkpoint",
    intent = "health",
    tasks = {},
}
local original = {
    getBase = Persistence.getBase,
    getBaseKind = Persistence.getBaseKind,
    getBaseResidentIds = Persistence.getBaseResidentIds,
    getSurvivorDuty = Persistence.getSurvivorDuty,
    getSurvivorAffiliation = Persistence.getSurvivorAffiliation,
    getWorkPreferences = Persistence.getWorkPreferences,
}
Persistence.getBase = function(id)
    if id == fakeBase.id then return fakeBase end
    return original.getBase(id)
end
Persistence.getBaseKind = function() return "main" end
Persistence.getBaseResidentIds = function() return { "resident-tie" } end
Persistence.getSurvivorDuty = function()
    return { mode = "base", baseId = fakeBase.id, ownerId = owner, jobPreference = "auto" }
end
Persistence.getSurvivorAffiliation = function()
    return { kind = "player", ownerId = owner }
end
Persistence.getWorkPreferences = function() return nil end

local picked = Jobs.selectEligibleTask(
    { { id = "tie-guard", type = "guard", state = "queued", priority = 50 },
      { id = "tie-cook", type = "cook", state = "queued", priority = 50 } },
    "resident-tie", fakeBase.id, "auto", function() return true end)
assert(picked ~= nil and picked.type == "cook",
    "an intent weight still outranks a kind that is not being used")

Persistence.getBase = original.getBase
Persistence.getBaseKind = original.getBaseKind
Persistence.getBaseResidentIds = original.getBaseResidentIds
Persistence.getSurvivorDuty = original.getSurvivorDuty
Persistence.getSurvivorAffiliation = original.getSurvivorAffiliation
Persistence.getWorkPreferences = original.getWorkPreferences

print("Base kinds PASS kinds=4 affinities=8 main_guard=1")
