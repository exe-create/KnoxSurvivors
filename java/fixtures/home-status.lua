-- The base line reads one shared status projection. This fixture stubs the
-- persistence/world owners and drives the real aggregation; it does not render
-- the HUD or prove a native player position.
local M = assert(codecHomeStatus, "home status source is loaded")
local A = assert(codecHomeAttention, "home attention source is loaded")
M.homeCounts = A.homeCounts
M.attentionItems = A.attentionItems
M.fallbackCount = A.fallbackCount
local previousPersistence = KnoxPersistence
local previousBaseJobs = KnoxBaseJobs
local previousBaseStorage = KnoxBaseStorage
local previousRuntime = KnoxSurvivorRuntime
local previousTimestampMs = getTimestampMs
local previousWorldAge = worldAge
local previousFeed = KnoxActivityFeed
local notices = {}
KnoxActivityFeed = { event = function(text) notices[#notices + 1] = text end }

local now = 1000
getTimestampMs = function() return now end
worldAge = function() return 12 end

M.bedRoster = function(base, playerId)
    assert(base.id == "home" and playerId == "player")
    return { { id = "resident-home", bed = nil },
        { id = "resident-away", bed = { x = 1, y = 2, z = 0, objectIndex = 1 } } }
end

local residentIds = { "resident-home", "resident-away", "resident-event", "resident-dead" }
KnoxPersistence = {
    getBaseResidentIds = function(baseId)
        assert(baseId == "home")
        return residentIds
    end,
    isSurvivorAlive = function(id) return id ~= "resident-dead" end,
    isSurvivorPresent = function(id) return id ~= "resident-away" end,
    getAwayTeamForSurvivor = function(id)
        return id == "resident-away" and { id = "team-a" } or nil
    end,
    getSurvivorDuty = function(id)
        return { jobPreference = "guard", eventId = id == "resident-event" and "raid" or nil }
    end,
}

local summary = {
    tasks = { blocked = 1 },
    security = { guardPosts = 1, patrolRoutes = 0, understaffed = 0 },
    storageProblems = { { survivorId = "resident-home", reason = "storage_full" } },
    reserves = { { category = "food", missing = 4 } },
    stockKnown = true,
    waterSource = "dry",
}
KnoxBaseJobs = {
    settlementSummary = function() return summary end,
    securityCoverage = function() return summary.security end,
}
KnoxBaseStorage = {
    roleKitShortages = function() return { { status = "shortage" } } end,
}
KnoxSurvivorRuntime = {
    getCharacter = function(id) return id ~= "resident-dead" and { id = id } or nil end,
}

local base = {
    id = "home", name = "Home", ownerKind = "player", ownerId = "player",
    tasks = {}, storage = { one = {}, two = {} },
    zones = { { enabled = true, type = "guard" } },
}
local status = assert(M.homeStatus(base, "player"), "the owned base has a status")
assert(#notices == 1 and notices[1] == M.waterShutNotice("Home"),
    "a dry tap raises one named notice")
assert(status.home == 1 and status.away == 2 and status.dead == 1,
    "home, away and dead residents stay distinct")
assert(status.missing == 0, "a living away resident is not called missing")
assert(status.facts.residents == 3, "the dead resident is not counted as living")
assert(status.facts.storageAssigned == 2 and status.facts.zones == 1,
    "the projection counts the existing storage and enabled zones")
assert(status.facts.unshelved == 1 and status.facts.bedsWithout == 1,
    "the storage problem and missing bed pass through")
assert(status.attention == 3 and status.items[1].key == "blocked",
    "the line uses the same prioritized attention projection")

local line = assert(M.baseLineModel(status), "the line model is available")
assert(line.expanded == true and line.itemKey == "blocked"
    and line.itemAction == "review_tasks",
    "the line names the top attention item and its existing action")
assert(line.actionLabel == "Review tasks" and line.title == "1 task is blocked +2",
    "the line carries the action label and the number behind it")
assert(line.attention == 3 and line.home == 1 and line.dead == 1,
    "the line preserves the resident counts")
local clear = assert(M.baseLineModel({ home = 2, away = 0, dead = 0,
    attention = 0, items = {} }), "a clear status has a model")
assert(clear.expanded == false and clear.title == "" and clear.attention == 0,
    "a clear line stays one row")
assert(clear.quietLabel == "supplies unverified", "no known shortage is not proof of stocked shelves")
local known = assert(M.baseLineModel({home=2,attention=0,items={},facts={stockKnown=true}}))
assert(known.quietLabel == "no urgent issues", "observed stock permits a bounded quiet status")
assert(M.baseLineModel(nil) == nil, "a missing status has no line model")

assert(M.standingOrderText("Shelter", status, "Miller Farm")
    == "Miller Farm is on Shelter; the first fix is 1 task is blocked.",
    "the order names the first real problem")
assert(M.standingOrderText(nil, status, "Miller Farm")
    == "Miller Farm has no standing order; the first fix is 1 task is blocked.",
    "a missing order is not invented")
assert(M.standingOrderText("Security", { items = {} }, "Miller Farm")
    == "Miller Farm is on Security; nothing pressing.",
    "a clear base says so")
assert(M.standingOrderText(nil, nil)
    == "The base has no standing order; nothing pressing.",
    "a missing status stays quiet")

now = 1100
summary = { tasks = {}, security = summary.security, storageProblems = {},
    reserves = {}, stockKnown = true }
M.bedRoster = function() return { { bed = { x = 1, y = 2, z = 0, objectIndex = 1 } } } end
KnoxBaseStorage.roleKitShortages = function() return {} end
local cached = assert(M.homeStatus(base, "player"), "the cached status is available")
assert(cached.attention == 3 and cached.items[1].key == "blocked",
    "the two-second cache prevents a second full read")
assert(#notices == 1, "the cache does not repeat the tap notice")

local refreshed = assert(M.homeStatus(base, "player", true), "force refreshes the status")
assert(refreshed.attention == 0, "a forced refresh sees the cleared base problems")
assert(#notices == 1, "the same dry state is not announced twice")

summary.waterSource = "running"
M.homeStatus(base, "player", true)
summary.waterSource = "dry"
M.homeStatus(base, "player", true)
assert(#notices == 2, "a later dry state can be announced once more")

assert(M.homeStatus(base, "someone-else") == nil,
    "another player's base is never described")
assert(M.homeStatus(nil, "player") == nil, "a missing base has no status")

KnoxPersistence = previousPersistence
KnoxActivityFeed = previousFeed
KnoxBaseJobs = previousBaseJobs
KnoxBaseStorage = previousBaseStorage
KnoxSurvivorRuntime = previousRuntime
getTimestampMs = previousTimestampMs
worldAge = previousWorldAge

print("Home status PASS home=true away=true dead=true cache=true")
