-- The raid log was defined, capped and read, and never written. These are the
-- guarantees the faction card and the retaliation cause now depend on.
local P = KnoxPersistence

local before = #P.getRaidHistory()
assert(P.recordRaidHistory({
    eventId = "raid-a", atHours = 30,
    sourceFactionId = "faction-raiders", sourceName = "The Farm",
    targetBaseId = "base-home", targetName = "Our Home",
    outcome = "supplies_taken",
}) == true, "a finished raid is recorded")

local after = P.getRaidHistory()
assert(#after == before + 1, "one raid adds one row")
local entry = after[#after]
assert(entry.eventId == "raid-a")
assert(entry.sourceName == "The Farm" and entry.targetName == "Our Home")
assert(entry.outcome == "supplies_taken")
assert(tonumber(entry.atHours) == 30)

-- The same raid can pass through withdrawing more than once.
local duplicate = P.recordRaidHistory({
    eventId = "raid-a", atHours = 31, outcome = "supplies_taken",
})
assert(duplicate == false, "the second write is refused")
assert(#P.getRaidHistory() == before + 1, "a raid stays one row")

-- The log is capped and newest last, so a reader taking the tail gets the most
-- recent raid.
for index = 1, 14 do
    P.recordRaidHistory({
        eventId = "raid-fill-" .. index, atHours = 40 + index,
        outcome = "no_supplies",
    })
end
local capped = P.getRaidHistory()
assert(#capped == 12, "the log stays capped at twelve rows")
assert(capped[#capped].eventId == "raid-fill-14", "the newest raid is last")
assert(capped[1].eventId ~= "raid-a", "the oldest rows are the ones dropped")

-- Readers get copies; a panel cannot rewrite history.
capped[1].outcome = "tampered"
assert(P.getRaidHistory()[1].outcome ~= "tampered")

-- A row without an event id is still honest about what it does not know.
assert(P.recordRaidHistory({ atHours = 99, outcome = "unknown" }) == true)
local anonymous = P.getRaidHistory()[#P.getRaidHistory()]
assert(anonymous.eventId == "" and anonymous.outcome == "unknown")

print("Raid history PASS once=true capped=true newest_last=true copies=true")
