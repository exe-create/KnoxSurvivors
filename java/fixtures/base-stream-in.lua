-- P1/P5: a settlement that streams back in discovers a current board from real
-- state, completes nothing, and reports the return through the existing notices
-- owner. Drives the production section, not a copy. Stubbed globals are restored
-- so later fixtures see the real owners again.
local C = assert(codecBaseStreamIn, "the stream-in discovery section is extracted")
local savedPersistence, savedFeed = rawget(_G, "KnoxPersistence"), rawget(_G, "KnoxActivityFeed")
local calls = 0
C.prepareWorkforce = function(base, character, now)
    calls = calls + 1
    return true, {}
end
local notices = {}
_G.KnoxActivityFeed = { event = function(text) notices[#notices + 1] = text end }
local tasks = {
    a = { state = "queued", type = "woodcutting" },
    b = { state = "claimed", type = "guard", offscreenShiftsCompleted = 3 },
    c = { state = "cancelled" },
}
local base = { id = "b1", name = "Pine Camp", tasks = tasks }
local duty = { mode = "base", baseId = "b1" }

local due, reason = C.streamInSeedDue(base, duty)
assert(due == true and reason == "base_resident", "a resident's own base is seeded on stream-in")
assert(not C.streamInSeedDue(nil, duty), "no board cannot be seeded")
assert(not C.streamInSeedDue(base, { mode = "autonomous" }), "a traveller is not a resident")
assert(not C.streamInSeedDue(base, { mode = "base", baseId = "other" }),
    "another base's board is not seeded")

local report = C.streamInReport(base)
assert(report.queued == 1 and report.claimed == 1 and report.offscreenShifts == 3,
    "the report counts only the states the board really carries")
local text = C.streamInNoticeText(base, report)
assert(text == "Pine Camp while you were away: 1 queued, 1 in hand, 3 watches stood.",
    "the existing feed gets one legible line from real counts: " .. tostring(text))
assert(C.streamInNoticeText(base, { queued = 0, claimed = 0, offscreenShifts = 0 }) == nil,
    "nothing happened, nothing is announced")

_G.KnoxPersistence = {
    getSurvivorDuty = function(id)
        return id == "s1" and duty or { mode = "autonomous" }
    end,
    getBase = function() return base end,
}
local ok, seedReason = C.seedStreamedBase("s1", {}, 100)
assert(ok == true and seedReason == "streamed", "a resident stream-in runs the real discovery")
assert(calls == 1, "discovery runs exactly once for the stream-in")
assert(notices[1] == text, "the return is reported through the existing notices owner")
assert(tasks.a.state == "queued" and tasks.b.state == "claimed",
    "stream-in discovery completes nothing")
assert(tasks.b.claimedBy == nil, "stream-in discovery claims nothing")
assert(tasks.b.offscreenShiftsCompleted == 3, "stream-in discovery rewrites no real fact")

assert(not C.seedStreamedBase("s2", {}, 100), "a non-resident stream-in seeds nothing")
assert(calls == 1, "no discovery runs for a non-resident")

_G.KnoxPersistence, _G.KnoxActivityFeed = savedPersistence, savedFeed
print("Base stream-in PASS seeded=true notice=true noCompletion=true noConsumption=true")
