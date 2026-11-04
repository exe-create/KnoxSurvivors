-- The per-tick sync must be able to tell whether a duty changed without paying
-- for a copy first. This drives the real accessor against real persistence: the
-- stamp a survivor reports is the revision of the duty the sync would receive,
-- so comparing stamps can never disagree with comparing the records themselves.
local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local p = KnoxPersistence
assert(type(p.getSurvivorDutyRevision) == "function",
    "the duty owner exposes a change stamp")

-- Reading the duty is the same path that creates and normalises the survivor
-- state, so seed through it rather than assuming an identity implies a record.
local duty = assert(p.getSurvivorDuty("stamp-a"), "the duty is readable")
local stamp = p.getSurvivorDutyRevision("stamp-a")
assert(stamp ~= nil, "a survivor with a duty reports a stamp")
assert(tonumber(stamp) == tonumber(duty.revision),
    "the stamp is the revision of the duty the sync receives, got "
        .. tostring(stamp) .. " and " .. tostring(duty.revision))

-- The stamp is stable while nothing writes, so an unchanged tick can skip the
-- copy without missing an update, and reading it leaves the record alone.
assert(p.getSurvivorDutyRevision("stamp-a") == stamp,
    "an untouched duty keeps its stamp")
assert(tonumber(p.getSurvivorDuty("stamp-a").revision) == tonumber(stamp),
    "reading the stamp leaves the record alone")

-- Absent inputs answer honestly rather than inventing a revision.
assert(p.getSurvivorDutyRevision("stamp-missing") == nil,
    "an unknown survivor has no stamp")
assert(p.getSurvivorDutyRevision(nil) == nil, "a nil id has no stamp")
assert(p.getSurvivorDutyRevision(42) == nil, "a non-string id has no stamp")

data["KnoxSurvivors_IsoPlayer"] = previousRoot

print("Duty revision stamp PASS stamp=" .. tostring(stamp))
