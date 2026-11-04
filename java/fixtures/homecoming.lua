-- The homecoming line is a pure projection over facts the base already owns.
-- This fixture does not move a player, read a native body or prove a greeting
-- appears in game; it proves the selection and wording boundaries.
local H = assert(codecHomecoming, "homecoming source is loaded")

local base = { tasks = {
    old_repair = { id = "old-repair", type = "repair", state = "complete",
        completedAtHours = 90 },
    barricade = { id = "barricade-a", type = "barricade", state = "complete",
        completedAtHours = 110, lastClaimedBy = "david" },
    farm = { id = "farm-water-a", type = "farm_water", state = "complete",
        completedAtHours = 120 },
    guard = { id = "guard-a", type = "guard", state = "complete",
        completedAtHours = 130, lastClaimedBy = "david" },
    pending = { id = "cook-a", type = "cook", state = "queued",
        completedAtHours = 140 },
    legacy = { id = "repair-b", type = "repair", state = "completed",
        completedAtHours = 105 },
} }

local work = assert(H.recentWork(base, 100), "a lasting completion is found")
assert(work.id == "farm-water-a", "the most recent lasting completion wins")
assert(work.lastClaimedBy == nil, "the task keeps its real claimant")
assert(H.recentWork(base, 121) == nil, "old and non-lasting work is not retold")
assert(H.recentWork(base, nil) == nil, "a missing departure time stays quiet")
assert(H.workPhrase("guard") == nil, "a finished shift is not a lasting change")
assert(H.workPhrase("farm_water") == "watered the crops",
    "the work has concrete wording")
assert(H.shortageLabel("ammo") == "ammunition", "the shortage has a player word")
assert(H.shortageLabel("unknown") == nil, "an unknown shortage is not invented")

assert(H.lineFor({ lost = 1 }) == "We lost someone while you were out.",
    "one death is named without a number")
assert(H.lineFor({ lost = 2 }) == "We lost 2 people while you were out.",
    "more than one death keeps the real count")
assert(H.lineFor({ lost = 1, work = { key = "barricade", workerName = "David" },
    hurtName = "Nora", shortage = "food" })
    == "We lost someone while you were out.",
    "loss outranks work, injury and shortage")
assert(H.lineFor({ work = { key = "barricade", workerName = "David" },
    speakerName = "David", hurtName = "Nora", shortage = "food" })
    == "I got the barricade up.",
    "the worker speaks in the first person")
assert(H.lineFor({ work = { key = "barricade", workerName = "David" },
    speakerName = "Nora" }) == "David got the barricade up.",
    "another resident names the worker")
assert(H.lineFor({ work = { key = "farm_water" }, speakerName = "Nora" })
    == "We watered the crops.", "work without a known worker stays plural")
assert(H.lineFor({ work = { key = "guard" }, speakerName = "Nora" })
    == "We're still here. That's the report.",
    "a guard shift does not become a homecoming claim")
assert(H.lineFor({ hurtName = "Nora", speakerName = "Iris" })
    == "Nora is hurt. Needs a look.", "an injury names the person")
assert(H.lineFor({ hurtName = "Nora", speakerName = "Nora" })
    == "I'm hurt. It needs a look.", "the hurt speaker owns the line")
assert(H.lineFor({ shortage = "food" }) == "We're low on food.",
    "a known shortage is named")
assert(H.lineFor({ shortage = "unknown" })
    == "We're still here. That's the report.",
    "an unknown shortage stays quiet")
assert(H.lineFor({}) == "We're still here. That's the report.",
    "an unchanged base says only what is true")
assert(H.lineFor(nil) == "We're still here. That's the report.",
    "missing facts do not invent a homecoming")

assert(H.LONG_ABSENCE_HOURS == 48, "a long absence has one threshold")
assert(H.MAX_REPORT_LINES == 3, "a report stays inside the attention budget")

local report = H.reportFor({
    lost = 2,
    work = { key = "barricade", workerName = "David" },
    hurtName = "Nora",
    shortage = "food",
    speakerName = "Iris",
})
assert(#report == 3, "a long report keeps three facts")
assert(report[1] == "We lost 2 people while you were out.",
    "loss leads the report")
assert(report[2] == "David got the barricade up.",
    "lasting work follows loss")
assert(report[3] == "Nora is hurt. Needs a look.",
    "injury is the third fact")

local twoFacts = H.reportFor({ hurtName = "Nora", shortage = "food",
    speakerName = "Iris" })
assert(#twoFacts == 2 and twoFacts[2] == "We're low on food.",
    "a shortage is named when there is room")
assert(H.reportFor({ work = { key = "farm_water", workerName = "Nora" },
    speakerName = "Nora" })[1] == "I watered the crops.",
    "the worker still speaks in the first person")
assert(H.reportFor({ work = { key = "guard" }, shortage = "unknown" })[1]
    == "We're still here. That's the report.",
    "work that is not lasting and an unknown shortage stay quiet")
assert(#H.reportFor({}) == 1
    and H.reportFor({})[1] == "We're still here. That's the report.",
    "an unchanged base still gives one honest line")
assert(#H.reportFor(nil) == 1, "missing facts do not invent a report")

assert(H.problemText({ kind = "beds", count = 1 })
    == "Someone's sleeping on the floor.", "one missing bed is a person, not a number")
assert(H.problemText({ kind = "beds", count = 3 }) == "We're short 3 beds.",
    "several missing beds keep the count")
assert(H.problemText({ kind = "kits", count = 1 }) == "One of us is short kit.",
    "one short kit is named")
assert(H.problemText({ kind = "kits", count = 2 }) == "2 of us are short kit.",
    "several short kits keep the count")
assert(H.problemText({ kind = "storage", count = 4 })
    == "4 things still need a home.", "unshelved storage is counted")
assert(H.problemText({ kind = "storage", count = 1 })
    == "Something still needs a home.", "one unshelved thing is singular")
assert(H.problemText({ kind = "beds", count = 0 }) == nil, "zero beds missing is quiet")
assert(H.problemText({ kind = "unknown", count = 2 }) == nil,
    "an unknown problem is not invented")
assert(H.problemText(nil) == nil, "a missing problem is quiet")

assert(H.lineFor({ problem = { kind = "beds", count = 2 } })
    == "We're short 2 beds.", "a lone problem can be the one line")
assert(H.lineFor({ shortage = "food", problem = { kind = "beds", count = 2 } })
    == "We're low on food.", "a shortage outranks a bed problem")


print("Homecoming PASS work=true worker=true loss=true hurt=true shortage=true quiet=true report=true")
