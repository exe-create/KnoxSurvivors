-- A nameplate said who someone was and whose household they travel with, never
-- what they were doing. This drives the production reader: asleep, real pain, or
-- a claimed base task, in that order, and silence for anything unreadable.
local Nameplates = assert(rawget(_G, "KnoxSurvivorNameplates"), "nameplate owner missing")

local STUBBED = { "KnoxPersistence", "KnoxSurvivorNeeds", "getTimestampMs" }
local saved = {}
for _, name in ipairs(STUBBED) do saved[name] = rawget(_G, name) end

local clock = 1000
getTimestampMs = function() return clock end

local tasks = {}
local duty = { mode = "base", baseId = "home" }
local painBand = "clear"
local infection = "clear"
local function base() return { id = "home", tasks = tasks } end

KnoxPersistence = {
    getSurvivorDuty = function() return duty end,
    getBase = function(id) return id == "home" and base() or nil end,
}
KnoxSurvivorNeeds = {
    snapshot = function() return { pain = painBand == "clear" and 0 or 70 } end,
    painBand = function() return painBand end,
    infectionBand = function() return infection end,
}

local function body(asleep)
    return { isAsleep = function() return asleep == true end }
end

-- Asleep outranks everything: the plate says the plainest true thing.
tasks = { t1 = { id = "t1", type = "cook", state = "claimed", claimedBy = "s1" } }
painBand = "bad"
assert(Nameplates.statusWord("s1", body(true)) == "asleep", "asleep is the first word")
painBand = "clear"

-- Bitten is the gravest fact a plate can carry: it outranks standing, pain and
-- whatever the person is carrying. A body we cannot read is not a diagnosis.
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "barricade", state = "claimed", claimedBy = "s1" } }
painBand = "severe"
infection = "bitten"
assert(Nameplates.statusWord("s1", body(false)) == "bitten",
    "a bitten resident reads bitten, over pain and work")
clock = clock + 10000
infection = nil
assert(Nameplates.statusWord("s1", body(false)) == "hurt",
    "an unread body falls back to pain instead of claiming health")
clock = clock + 10000
infection = "clear"
assert(Nameplates.statusWord("s1", body(false)) == "hurt",
    "a clean body does not hide pain")
clock = clock + 10000
infection = "clear"
painBand = "clear"
tasks = { t1 = { id = "t1", type = "barricade", state = "claimed", claimedBy = "s1" } }
assert(Nameplates.statusWord("s1", body(false)) == "boarding",
    "a clean, unhurt body reads the work")

-- Real pain outranks the job: working through a bad wound is the urgent fact.
tasks = { t1 = { id = "t1", type = "barricade", state = "claimed", claimedBy = "s1" } }
clock = clock + 10000
painBand = "severe"
assert(Nameplates.statusWord("s1", body(false)) == "hurt", "severe pain reads as hurt")
clock = clock + 10000
painBand = "bad"
assert(Nameplates.statusWord("s1", body(false)) == "hurt", "bad pain reads as hurt")
clock = clock + 10000
painBand = "hurting"
assert(Nameplates.statusWord("s1", body(false)) == "boarding", "a twinge does not outrank work")

-- The task words are real task types, and an unknown one invents nothing.
local expected = {
    barricade = "boarding", repair = "repairing", chop_tree = "chopping",
    saw_logs = "sawing", cook = "cooking", guard = "on watch",
    patrol = "patrolling", haul_corpse = "moving a body",
    burn_corpse = "burning a body", pile_corpses = "piling bodies",
    farm_seed = "sowing", farm_water = "watering", farm_harvest = "harvesting",
    farm_plow = "ploughing", storage_sorting = "sorting stores",
}
for taskType, word in pairs(expected) do
    clock = clock + 10000
    tasks = { t1 = { id = "t1", type = taskType, state = "claimed", claimedBy = "s1" } }
    assert(Nameplates.statusWord("s1", body(false)) == word, "wrong word for " .. taskType)
end
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "flibbertigibbet", state = "claimed", claimedBy = "s1" } }
assert(Nameplates.statusWord("s1", body(false)) == nil, "an unknown job has no word")

-- Somebody else's task, a queued task and no task at all are all silence.
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "cook", state = "claimed", claimedBy = "s2" } }
assert(Nameplates.statusWord("s1", body(false)) == nil, "another resident's job is not mine")
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "cook", state = "queued" } }
assert(Nameplates.statusWord("s1", body(false)) == nil, "queued work is not being done")
clock = clock + 10000
tasks = {}
assert(Nameplates.statusWord("s1", body(false)) == nil, "idle has no word")

-- A companion's errand is a real persisted directive kind, one word each, and
-- a follower with no order is following - the same default the HUD shows.
clock = clock + 10000
duty = { mode = "companion" }
assert(Nameplates.statusWord("s1", body(false)) == "with you",
    "a companion with no order is with you")

-- The controlling order outranks a stale errand, and uses the same words the
-- party strip shows.
clock = clock + 10000
duty = { mode = "companion", order = "hold" }
assert(Nameplates.statusWord("s1", body(false)) == "holding", "hold reads as holding")
clock = clock + 10000
duty = { mode = "companion", order = "hold", directive = { kind = "loot_area" } }
assert(Nameplates.statusWord("s1", body(false)) == "holding",
    "a search order does not talk over a hold")
clock = clock + 10000
duty = { mode = "companion", order = "relax" }
assert(Nameplates.statusWord("s1", body(false)) == "relaxing", "relax reads as relaxing")
clock = clock + 10000
duty = { mode = "companion", order = "follow", directive = { kind = "go_to" } }
assert(Nameplates.statusWord("s1", body(false)) == "on the way",
    "following with an errand names the errand")
local errands = {
    { kind = "go_to", word = "on the way" },
    { kind = "loot_building", word = "searching" },
    { kind = "loot_area", word = "searching" },
    { kind = "loot_corpses", word = "checking bodies" },
    { kind = "guard", word = "on watch" },
    { kind = "patrol_area", word = "patrolling" },
    { kind = "find_food", word = "looking for food" },
    { kind = "find_water", word = "looking for water" },
    { kind = "find_medical", word = "looking for supplies" },
    { kind = "find_weapon", word = "looking for a weapon" },
    { kind = "find_tools", word = "looking for tools" },
    { kind = "clean_inventory", word = "sorting their pack" },
}
for _, errand in ipairs(errands) do
    clock = clock + 10000
    duty = { mode = "companion", directive = { kind = errand.kind } }
    assert(Nameplates.statusWord("s1", body(false)) == errand.word,
        "wrong errand word for " .. errand.kind)
end
clock = clock + 10000
duty = { mode = "companion", directive = { kind = "not_a_real_order" } }
assert(Nameplates.statusWord("s1", body(false)) == "with you",
    "an unrecognised errand falls back to following, not to a made-up word")
clock = clock + 10000
duty = nil
assert(Nameplates.statusWord("s1", body(false)) == nil, "no duty is no word")
duty = { mode = "base", baseId = "home" }

-- A body whose pain cannot be read does not stop the job word.
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "cook", state = "claimed", claimedBy = "s1" } }
KnoxSurvivorNeeds.snapshot = function() error("unreadable body") end
assert(Nameplates.statusWord("s1", body(false)) == "cooking",
    "an unread body still lets the job speak")
KnoxSurvivorNeeds.snapshot = function() return { pain = 0 } end

-- The plate repaints every frame, so the reader is cached for a moment and
-- refreshed after it: a change of job must land once the window passes.
clock = clock + 10000
tasks = { t1 = { id = "t1", type = "cook", state = "claimed", claimedBy = "s1" } }
assert(Nameplates.statusWord("s1", body(false)) == "cooking", "the job is read")
local reads = 0
local realGetBase = KnoxPersistence.getBase
KnoxPersistence.getBase = function(id) reads = reads + 1; return realGetBase(id) end
tasks = { t1 = { id = "t1", type = "barricade", state = "claimed", claimedBy = "s1" } }
clock = clock + 100
assert(Nameplates.statusWord("s1", body(false)) == "cooking", "inside the window it is cached")
assert(reads == 0, "a cached word costs no task walk")
clock = clock + 1000
assert(Nameplates.statusWord("s1", body(false)) == "boarding", "after the window it is fresh")
assert(reads >= 1, "the refresh really reads")
KnoxPersistence.getBase = realGetBase

-- A clock we cannot read disables the cache instead of freezing the word.
getTimestampMs = function() error("no clock") end
tasks = { t1 = { id = "t1", type = "guard", state = "claimed", claimedBy = "s1" } }
assert(Nameplates.statusWord("s1", body(false)) == "on watch", "no clock still reads")
tasks = { t1 = { id = "t1", type = "patrol", state = "claimed", claimedBy = "s1" } }
assert(Nameplates.statusWord("s1", body(false)) == "patrolling", "no clock reads every time")

for _, name in ipairs(STUBBED) do _G[name] = saved[name] end
print("Nameplate status PASS asleep=true hurt=true work=true silent=true cache=true")
