-- A haul the settlement cannot shelve must be reported to the player, once per
-- reason and in the resident's real name. The resident keeps carrying it; the
-- report is a notice, not a transfer.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local C, p = KnoxAutonomyController, KnoxPersistence
local captured = {}
local previousFeed = KnoxActivityFeed
KnoxActivityFeed = { event = function(text) captured[#captured + 1] = tostring(text) end }

assert(p.setRecord("cargo-report", expectedRecord))
p.ensureSurvivorIdentity("cargo-report", "Dana", "Kell", 10, 34)
assert(p.setPlayerCompanion("cargo-report", "report-owner", "hold", 10))
local base = assert(p.createBase("player", "report-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "report-home",
}, 10, nil, true))

local function fakeItem(name, fullType)
    return {
        getName = function() return name end,
        getFullType = function() return fullType end,
    }
end

local controller = setmetatable({
    id = "cargo-report", baseId = base.id,
}, C)

assert(controller:reportUnshelvedCargo(fakeItem("Canned Beans", "Base.CannedBeans"),
    "storage_full", 0) == true, "an unshelvable haul is reported")
assert(#captured == 1, "one haul produces one notice")
assert(string.find(captured[1], "Dana Kell", 1, true) ~= nil,
    "the notice names the resident holding the supplies")
assert(string.find(captured[1], "Canned Beans", 1, true) ~= nil,
    "the notice names the cargo")
assert(string.find(captured[1], "full", 1, true) ~= nil,
    "the notice names the real storage problem")
assert(string.find(captured[1], "still carrying", 1, true) ~= nil,
    "the notice says where the supplies are, not that they were lost")

-- The leader sees the same fact in the base record, not only in the feed.
local problems = p.getBaseStorageProblems(base.id)
assert(#problems == 1 and problems[1].survivorId == "cargo-report",
    "the unshelvable haul is recorded as an open base problem")
assert(problems[1].reason == "storage_full" and problems[1].itemLabel == "Canned Beans",
    "the recorded problem keeps the real cause and cargo")

assert(controller:reportUnshelvedCargo(fakeItem("Canned Beans", "Base.CannedBeans"),
    "storage_full", 0) == false, "the same problem is not repeated immediately")
assert(#captured == 1, "a repeated retry does not flood the feed")
assert(#p.getBaseStorageProblems(base.id) == 1, "a retry does not duplicate the problem")

assert(controller:reportUnshelvedCargo(fakeItem("Bandage", "Base.Bandage"),
    "no_matching_storage", 0) == true,
    "a different storage problem is still worth telling")
assert(#captured == 2 and string.find(captured[2], "filter", 1, true) ~= nil,
    "the second notice names its own problem")
problems = p.getBaseStorageProblems(base.id)
assert(#problems == 1 and problems[1].reason == "no_matching_storage",
    "a changed cause updates the same resident's open problem")

assert(controller:reportUnshelvedCargo(fakeItem("Nails", "Base.Nails"),
    "unknown_reason", 0) == true,
    "an unclassified failure still produces a notice")
assert(string.find(captured[3], "not available", 1, true) ~= nil,
    "an unclassified failure uses honest generic wording")

-- A resident whose identity was never stored still gets a readable notice.
local anonymous = setmetatable({ id = "cargo-anon", baseId = base.id }, C)
assert(anonymous:reportUnshelvedCargo(nil, "storage_inaccessible", 0) == true,
    "missing cargo and identity are handled")
assert(string.find(captured[4], "A resident", 1, true) ~= nil
    and string.find(captured[4], "mission supplies", 1, true) ~= nil
    and string.find(captured[4], "reached", 1, true) ~= nil,
    "the fallback notice is still specific about the problem")

-- Already-reported work never says anything twice in the same hour.
controller.cargoReportAt = { storage_full = 99 }
captured = {}
assert(controller:reportUnshelvedCargo(fakeItem("Canned Beans", "Base.CannedBeans"),
    "storage_full", 0) == false, "a future retry deadline suppresses the notice")
assert(#captured == 0, "a throttled retry writes nothing")

-- A resolved haul clears the open problem, and clearing is idempotent.
assert(p.clearBaseStorageProblem(base.id, "cargo-report") == true,
    "a shelved haul clears its open problem")
local remaining = p.getBaseStorageProblems(base.id)
assert(#remaining == 1 and remaining[1].survivorId == "cargo-anon",
    "another resident's open problem is untouched")
assert(p.clearBaseStorageProblem(base.id, "cargo-anon") == true)
assert(#p.getBaseStorageProblems(base.id) == 0,
    "a resolved haul leaves the settlement with no open problem")
assert(p.clearBaseStorageProblem(base.id, "cargo-report") == false,
    "clearing an absent problem is not an error")

-- A haul filed in another container is a delivery, not a failure: one line says
-- which container took it, and nothing stays open in the base record.
captured = {}
assert(controller:reportOverflowDeposit(fakeItem("Canned Beans", "Base.CannedBeans"),
    "Tool Storage") == true, "an overflowing haul is reported")
assert(#captured == 1, "one overflowing haul produces one notice")
assert(string.find(captured[1], "Dana Kell", 1, true) ~= nil
    and string.find(captured[1], "Canned Beans", 1, true) ~= nil
    and string.find(captured[1], "Tool Storage", 1, true) ~= nil
    and string.find(captured[1], "full", 1, true) ~= nil,
    "the overflow notice names the resident, the cargo and the container that took it")
assert(#p.getBaseStorageProblems(base.id) == 0,
    "a shelved haul leaves no open storage problem")
assert(controller:reportOverflowDeposit(fakeItem("Canned Beans", "Base.CannedBeans"),
    "Tool Storage") == false, "the same overflow is not repeated immediately")
assert(#captured == 1, "a repeated overflow deposit does not flood the feed")
controller.cargoReportAt = nil
assert(controller:reportOverflowDeposit(fakeItem("Nails", "Base.Nails"), nil) == true,
    "an unnamed container still reports")
assert(string.find(captured[2], "base storage", 1, true) ~= nil,
    "a missing container label falls back to honest wording")

-- Newest first, and bounded per base so a broken shelf cannot grow forever.
assert(p.recordBaseStorageProblem(base.id, "old", "Log", "storage_full", 10))
assert(p.recordBaseStorageProblem(base.id, "new", "Plank", "storage_full", 20))
local ordered = p.getBaseStorageProblems(base.id)
assert(ordered[1].survivorId == "new" and ordered[2].survivorId == "old",
    "the newest problem is listed first")
for index = 1, 10 do
    assert(p.recordBaseStorageProblem(base.id, "flood-" .. index,
        "Item " .. index, "storage_full", 20 + index))
end
assert(#p.getBaseStorageProblems(base.id) <= 8,
    "the open-problem list is bounded per base")
assert(p.recordBaseStorageProblem("missing-base", "x", "Y", "storage_full", 1) == false,
    "an unknown base records nothing")

KnoxActivityFeed = previousFeed
data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Unshelved cargo report PASS named=true specific=true throttled=true fallback=true")
