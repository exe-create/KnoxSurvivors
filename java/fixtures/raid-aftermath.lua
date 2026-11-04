-- A finished raid reports what it cost instead of a stale ETA, and the report is
-- written once. The sentence is pure; the stamp is driven through the real
-- KS_KnoxEvents module with stubbed persistence reads.
local E = assert(KnoxEvents, "raid event owner is loaded")
local text = assert(E.raidAftermathText, "aftermath copy lives in the event owner")

local function receipts(count)
    local map = {}
    for index = 1, count do map["r" .. index] = { atHours = 10, item = "food" } end
    return map
end
local function raid(phase, count, kind)
    return {
        id = "raid-1", kind = kind or "faction_raid", phase = phase,
        objective = {
            kind = "take_supplies", requiredItems = 3, receipts = receipts(count),
            misses = {}, startedAtHours = 9, deadlineHours = 11, outcome = "partial_supplies",
        },
    }
end

-- SILENT UNTIL IT ENDS.
assert(text(raid("scheduled", 0)) == nil, "a scheduled raid has no aftermath")
assert(text(raid("approaching", 0)) == nil, "a warning is not an aftermath")
assert(text(raid("active", 2)) == nil, "a raid still fighting has no aftermath")
assert(text(raid("objective", 2)) == nil, "a raid still working has no aftermath")
assert(text({ kind = "faction_entry", phase = "completed" }) == nil,
    "a faction entry is not a raid")
assert(text(nil) == nil, "no record, no report")

-- WHAT IT COST, in the words the record supports.
assert(text(raid("withdrawing", 0)) == "They are pulling out empty-handed.",
    "an empty-handed withdrawal says so: " .. tostring(text(raid("withdrawing", 0))))
assert(text(raid("withdrawing", 1)) == "They are pulling out with 1 item.",
    "one item is singular")
assert(text(raid("withdrawing", 2)) == "They are pulling out with 2 items.",
    "the withdrawal carries the real count")
assert(text(raid("completed", 0)) == "The raid is over: they left empty-handed.",
    "a completed raid with nothing taken says so")
assert(text(raid("completed", 1)) == "The raid is over: they carried off 1 item.",
    "one carried item is singular")
assert(text(raid("completed", 3)) == "The raid is over: they carried off 3 items.",
    "a completed raid reports the real count")
assert(text(raid("failed", 2)) == "The raid broke before it reached your gate.",
    "a failed raid never got in, whatever its receipts say")
assert(text({ kind = "faction_raid", phase = "completed" }) == "The raid is over: they left empty-handed.",
    "a raid with no objective reads as nothing taken")

-- THE STALE THREAT this pass repairs: the warning stamp outlives the raid, and
-- its ETA would still read as imminent long after the column left.
local warned = raid("completed", 2)
warned.revision = 5
warned.warning = {
    factionName = "Northside Crew", direction = "south-east", strength = "a few armed",
    cause = "grievance", etaHours = 12.5, hours = 12,
}
local threat = E.raidThreatText(warned.warning, 30)
assert(threat ~= nil and threat:find("arriving now", 1, true) ~= nil,
    "the stamp alone still reads as arriving: " .. tostring(threat))
assert(text(warned, 30) == "The raid is over: they carried off 2 items.",
    "the aftermath is what the row shows instead: " .. tostring(text(warned, 30)))

-- ONE DURABLE REPORT.
local persistence = KnoxPersistence
local saved = { getKnoxEventState = persistence.getKnoxEventState }
local record = raid("withdrawing", 2)
record.revision = 4
local state = { records = { ["raid-1"] = record }, cooldowns = {}, automatic = {} }
persistence.getKnoxEventState = function() return state end

local stamp, why = E.markRaidAftermath("raid-1", 4, 20)
assert(stamp ~= nil and stamp.items == 2 and stamp.outcome == "partial_supplies",
    "the report records the real cost: " .. tostring(why))
assert(record.aftermath ~= nil and record.aftermath.saidAtHours == 20,
    "the stamp is durable on the record the save already carries")
stamp, why = E.markRaidAftermath("raid-1", 4, 21)
assert(stamp == nil and why == "already_recorded", "the report is said once, not every tick")
stamp, why = E.markRaidAftermath("raid-1", 3, 20)
assert(stamp == nil and why == "stale_revision", "a stale revision cannot rewrite the record")
record.phase = "active"
stamp, why = E.markRaidAftermath("raid-1", 4, 20)
assert(stamp == nil and why == "not_finished", "a live raid has no aftermath to record")
record.phase = "withdrawing"
record.objective = nil
record.aftermath = nil
stamp, why = E.markRaidAftermath("raid-1", 4, 20)
assert(stamp == nil and why == "no_objective",
    "a column that never got inside has nothing to report")
stamp, why = E.markRaidAftermath("missing", 4, 20)
assert(stamp == nil and why == "not_a_raid", "an unknown id is refused")

persistence.getKnoxEventState = saved.getKnoxEventState
assert(persistence.getKnoxEventState == saved.getKnoxEventState, "persistence reads are restored")
