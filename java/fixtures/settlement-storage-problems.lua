local Persistence = assert(KnoxPersistence, "persistence is loaded")
local Jobs = assert(KnoxBaseJobs, "base jobs are loaded")
local Storage = assert(KnoxBaseStorage, "base storage is loaded")

local base = Persistence.createBase("player", "settlement-storage-problems-player",
    { minX = 6400, minY = 6400, width = 3, height = 3, buildingId = "settlement-storage-problems-building" }, 30)
assert(base ~= nil, "fixture base was created")

-- Nothing has failed to shelve yet. The Work tab iterates this list on every
-- refresh, so the summary must carry an empty table rather than nil.
local clean = Jobs.settlementSummary(base, 20)
assert(type(clean.storageProblems) == "table" and #clean.storageProblems == 0,
    "a base with no unshelvable haul reports an empty list")

-- Two real problems, written through the writer the controller itself calls.
assert(Persistence.recordBaseStorageProblem(base.id, "ks-problem-a",
    "canned beans", "storage_full", 18) == true, "the first problem is recorded")
assert(Persistence.recordBaseStorageProblem(base.id, "ks-problem-b",
    "planks", "no_matching_storage", 22) == true, "the second problem is recorded")

local summary = Jobs.settlementSummary(base, 20)
assert(#summary.storageProblems == 2,
    "both recorded problems reach the settlement summary: " .. tostring(#summary.storageProblems))
assert(summary.storageProblems[1].survivorId == "ks-problem-b",
    "the newest problem is listed first: " .. tostring(summary.storageProblems[1].survivorId))
assert(summary.storageProblems[2].survivorId == "ks-problem-a",
    "the older problem follows it: " .. tostring(summary.storageProblems[2].survivorId))
assert(summary.storageProblems[1].itemLabel == "planks"
    and summary.storageProblems[1].reason == "no_matching_storage"
    and summary.storageProblems[1].atHours == 22,
    "the cargo label, cause and time survive the summary")

-- The overview is a read. A panel that edits its copy must not edit the base.
summary.storageProblems[1].reason = "tampered"
summary.storageProblems[1].itemLabel = nil
summary.storageProblems[2] = nil
local reread = Persistence.getBaseStorageProblems(base.id)
assert(#reread == 2, "the summary hands out a copy, not the ledger")
assert(reread[1].reason == "no_matching_storage" and reread[1].itemLabel == "planks",
    "the stored cause and cargo survive a reader's edits")

-- The wiring under test: this list is built outside the stockKnown guard, so a
-- base whose containers cannot be read still reports hauls that are not shelved.
-- Reserves and shortages must stay silent in the same call, because they would
-- otherwise claim a shortage nobody can see.
local oldSummarize = Storage.summarize
Storage.summarize = function()
    return { loadedPolicies = 0, unavailablePolicies = 2, misplacedItems = 0, totals = {} }
end
local unloaded = Jobs.settlementSummary(base, 20)
Storage.summarize = oldSummarize
assert(unloaded.stockKnown == false, "unreadable containers mean stock is unknown")
assert(#unloaded.storageProblems == 2, "an unloaded base still reports its unshelved hauls")
assert(#unloaded.shortages == 0, "an unloaded base claims no shortage it cannot see")

assert(#Jobs.settlementSummary(base, 20).storageProblems == 2,
    "reading the summary neither records nor clears a problem")

assert(Persistence.clearBaseStorageProblem(base.id, "ks-problem-b") == true,
    "the real delivery path clears the problem")
local cleared = Jobs.settlementSummary(base, 20)
assert(#cleared.storageProblems == 1
    and cleared.storageProblems[1].survivorId == "ks-problem-a",
    "a cleared problem leaves the settlement summary")

print("Settlement storage problems PASS newest-first=true copy=true unknown-stock=true cleared=true")
