-- PT-27: a conversation can pass on one concrete event from the other
-- person's ledger, but only as attributed hearsay. This drives the real
-- recordLoadedEncounter and recount formatter with a stubbed canonical store.
local stories = assert(KnoxOffscreenStories, "the story owner must be loaded")
local dialogue = assert(KnoxSurvivorDialogue, "the dialogue owner must be loaded")

local states = {}
local identities = {
    a = { forename = "Ada", surname = "Vance" },
    b = { forename = "Nora", surname = "Vance" },
    c = { forename = "Cal", surname = "Reed" },
    d = { forename = "Dee", surname = "Reed" },
    e = { forename = "Eli", surname = "Moss" },
    f = { forename = "Fay", surname = "Moss" },
    g = { forename = "Gus", surname = "Moss" },
    m = { forename = "Myra", surname = "Lane" },
    n = { forename = "Neil", surname = "Lane" },
    o = { forename = "Owen", surname = "Lane" },
    q = { forename = "Quinn", surname = "Voss" },
    h = { forename = "Hale", surname = "Croft" },
    i = { forename = "Iris", surname = "Croft" },
    j = { forename = "Jon", surname = "Croft" },
    k = { forename = "Kit", surname = "Croft" },
    l = { forename = "Lena", surname = "Croft" },
}

local function stateWith(history)
    return { status = "hibernated", activity = "exploring", health = 90, history = history }
end

states.a = stateWith({ { kind = "close_call", outcome = "hurt", t = 5 } })
states.b = stateWith({ { kind = "meet", with = "c", outcome = "parted", t = 3 },
    { kind = "scar", detail = "came back to where weapons were drawn",
    outcome = "returned", t = 6 } })
states.c = stateWith({ { kind = "scar", outcome = "returned", t = 4 } })
states.d = stateWith({})
states.e = stateWith({ { kind = "heard", from = "f", heardKind = "scar",
    heardOutcome = "returned", heardAtHours = 2, t = 12 } })
states.g = stateWith({})
states.m = stateWith({ { kind = "meet", with = "o", outcome = "hostile", t = 8 },
    { kind = "meet", with = "n", outcome = "friendly", t = 9 } })
states.n = stateWith({})
states.q = stateWith({})
states.h = stateWith({})
for _, id in ipairs({ "i", "j", "k", "l" }) do
    states[id] = stateWith({ { kind = "scar", outcome = "returned", t = 1 } })
end

local realPersistence = KnoxPersistence
KnoxPersistence = {
    getUnloadedSurvivalState = function(id) return states[id] end,
    setUnloadedSurvivalState = function(id, state)
        states[id] = state
        return true
    end,
    getSurvivorIdentity = function(id) return identities[id] end,
}

-- 1. A friendly encounter copies one older, concrete event from the partner,
-- attributed to that partner and with its original time.
local recorded = stories.recordLoadedEncounter("a", "b", "friendly", 20)
assert(recorded == true, "a real friendly encounter is recorded")
-- Production calls the owner once per side; do the same here so the second
-- ledger's copy is real rather than assumed.
local recordedBack = stories.recordLoadedEncounter("b", "a", "friendly", 20)
assert(recordedBack == true, "the other side records the same encounter")
local aHistory = states.a.history
local aHeard = aHistory[#aHistory]
assert(aHeard.kind == "heard", "the newest entry is hearsay")
assert(aHeard.from == "b", "hearsay names the person who told them")
assert(aHeard.heardKind == "scar" and aHeard.heardAtHours == 6,
    "the copied fact keeps its kind and real time")
assert(aHeard.t == 20, "the copy is stamped with the conversation time")
local bHistory = states.b.history
local bHeard = bHistory[#bHistory]
assert(bHeard.kind == "heard" and bHeard.heardKind == "close_call"
    and bHeard.from == "a", "the conversation carries news both ways")

-- 2. A hostile meeting records the encounter and no news.
local hostile = stories.recordLoadedEncounter("c", "d", "hostile", 30)
assert(hostile == true, "the hostile encounter is still recorded")
for _, entry in ipairs(states.d.history) do
    assert(entry.kind ~= "heard", "hostility passes no story to the listener")
end

-- 3b. A real third-party meeting is news, but a meeting with the listener is
-- not repeated back to them and never becomes a story about themselves.
stories.recordLoadedEncounter("n", "m", "friendly", 30)
local nHistory = states.n.history
local nHeard = nHistory[#nHistory]
assert(nHeard.kind == "heard" and nHeard.heardKind == "meet",
    "a third-party meeting is shareable news")
assert(nHeard.heardWith == "o", "the story names the third person, not the listener")
local meetLine = assert(dialogue.recountEntry("n", nHeard),
    "a heard meeting renders")
assert(meetLine:find("crossing Owen", 1, true) ~= nil,
    "the third person is named: " .. tostring(meetLine))
assert(meetLine:find("hostile", 1, true) ~= nil,
    "the recorded outcome is carried: " .. tostring(meetLine))
assert(meetLine:find("Neil", 1, true) == nil,
    "the listener's own meeting is not told back to them: " .. tostring(meetLine))
local recentMeet = stories.recentHistoryFor("n", 1)[1]
assert(recentMeet.kind == "heard" and recentMeet.source == "m"
    and recentMeet.heardKind == "meet" and recentMeet.heardWith == "o",
    "the read-only history keeps the source and third person")

-- 3. The same finalized encounter never appends a second copy.
local before = #aHistory
local repeatResult = stories.recordLoadedEncounter("a", "b", "friendly", 20)
assert(repeatResult == true and #states.a.history == before,
    "a repeated completion is deduplicated before hearsay")

-- 4. Hearsay never becomes first-hand fact for the next listener.
stories.recordLoadedEncounter("g", "e", "friendly", 40)
for _, entry in ipairs(states.g.history) do
    assert(entry.kind ~= "heard", "a story already heard is not passed on again")
end

-- 5. The listener's own ledger is bounded to three hearsay entries. The
-- fourth conversation still records its meeting, but adds no more news.
for index, source in ipairs({ "i", "j", "k", "l" }) do
    stories.recordLoadedEncounter("h", source, "friendly", 50 + index)
end
local heard = 0
for _, entry in ipairs(states.h.history) do
    if entry.kind == "heard" then heard = heard + 1 end
end
assert(heard == 3, "hearsay is capped at three entries, got " .. tostring(heard))

-- 6. The formatter attributes the fact and never uses the listener's voice.
local line = assert(dialogue.recountEntry("a", aHeard), "the heard entry renders")
assert(line:find("Nora told me", 1, true) ~= nil,
    "the source is named: " .. tostring(line))
assert(line:find("weapons had been drawn", 1, true) ~= nil,
    "the fact itself is retold: " .. tostring(line))
assert(line:find("I ", 1, true) == nil or line:find("I ", 1, true) > 1,
    "a heard line is not written as the listener's own sighting")
local unnamed = assert(dialogue.recountEntry("a", {
    kind = "heard", from = "nobody", heardKind = "cache",
    heardAtHours = 10, t = 20,
}), "an unidentified source still renders")
assert(unnamed:find("Someone told me", 1, true) == 1,
    "an unknown source is named honestly: " .. tostring(unnamed))
local firsthand = assert(dialogue.recountEntry("a", { kind = "scar", t = 6 }),
    "the existing first-hand scar still renders")
assert(firsthand:find("Came back", 1, true) == 1,
    "first-hand memory keeps its old voice: " .. tostring(firsthand))

-- 7. Their Travels reads the newest line, which is now the attributed one.
local lines = dialogue.recountLines("a")
assert(type(lines) == "table" and #lines > 0, "the ledger retells something")
assert(lines[1]:find("Nora told me", 1, true) ~= nil,
    "the retold memory is the attributed one: " .. tostring(lines[1]))
local recent = stories.recentHistoryFor("a", 1)[1]
assert(recent.kind == "heard" and recent.source == "b"
    and recent.heardKind == "scar" and recent.heardWith == nil,
    "the bounded read-only history names the source of a scar")

-- 8. A measured wound is real history. A second hit inside two hours is
-- throttled; a later, larger wound records as severe.
assert(stories.recordSurvivorInjury("q", 4, 20) == true,
    "a real health loss records a close call")
local qHistory = states.q.history
assert(#qHistory == 1 and qHistory[1].kind == "close_call"
    and qHistory[1].outcome == "hurt", "the first wound is a hurt entry")
local qBefore = #qHistory
local throttled, throttleReason = stories.recordSurvivorInjury("q", 30, 21)
assert(throttled == false and throttleReason == "throttled",
    "a second wound inside two hours is throttled")
assert(#states.q.history == qBefore, "the throttled wound adds no entry")
assert(stories.recordSurvivorInjury("q", 30, 23) == true,
    "a later, larger wound records")
local severe = states.q.history[#states.q.history]
assert(severe.outcome == "severe", "a thirty-point loss is severe")
local severeLine = assert(dialogue.recountEntry("q", severe))
assert(severeLine:find("bad wound", 1, true) ~= nil,
    "a severe wound has its own first-hand wording: " .. tostring(severeLine))
assert(stories.recordSurvivorInjury("q", 0, 24) == false,
    "a zero loss is not an injury")

-- 9. The real controller hook only records a threatened, measured drop.
assert(KnoxAutonomyController ~= nil
    and KnoxAutonomyController.observeCombatConfidence ~= nil,
    "the controller combat observer must be loaded")
local realFeed = rawget(_G, "KnoxActivityFeed")
local feedLines = {}
KnoxActivityFeed = { event = function(text) feedLines[#feedLines + 1] = text end }
local controller = { id = "q", base = { ownerKind = "player", name = "Farm" },
    recentCombatConfidence = {
    hours = 23, health = 80, confidence = 0, shock = 0, threatened = true } }
setmetatable(controller, { __index = KnoxAutonomyController })
local beforeHook = #states.q.history
KnoxAutonomyController.observeCombatConfidence(controller, 70, 30, false, true)
assert(#states.q.history == beforeHook + 1,
    "the controller records a measured combat wound")
KnoxAutonomyController.observeCombatConfidence(controller, 60, 31, false, true)
assert(#states.q.history == beforeHook + 1,
    "the controller's second hit is throttled by the ledger")
KnoxAutonomyController.observeCombatConfidence(controller, 50, 33, false, false)
assert(#states.q.history == beforeHook + 1,
    "a non-threatened loss does not become a combat wound")
KnoxAutonomyController.observeCombatConfidence(controller, 10, 34, false, true)
assert(#states.q.history == beforeHook + 2,
    "a later severe combat wound records once")
local hookSevere = states.q.history[#states.q.history]
assert(hookSevere.kind == "close_call" and hookSevere.outcome == "severe",
    "the controller's forty-point loss is severe")
assert(#feedLines == 1 and feedLines[1]:find("Quinn", 1, true) ~= nil
    and feedLines[1]:find("Farm", 1, true) ~= nil
    and feedLines[1]:find("severe wound", 1, true) ~= nil,
    "the player's own severe wound is reported once: " .. tostring(feedLines[1]))

-- A faction defender's wound stays out of the player's feed even when it is
-- severe. A separate controller proves the ownership gate, not a missing ledger.
local factionController = { id = "q", base = { ownerKind = "faction", name = "Camp" },
    recentCombatConfidence = { hours = 37, health = 50, confidence = 0, shock = 0,
        threatened = true } }
setmetatable(factionController, { __index = KnoxAutonomyController })
KnoxAutonomyController.observeCombatConfidence(factionController, 10, 38, false, true)
assert(states.q.history[#states.q.history].outcome == "severe",
    "the faction wound is still measured")
assert(#feedLines == 1, "a faction defender's wound does not enter the player feed")

KnoxActivityFeed = realFeed
KnoxPersistence = realPersistence
print("Offscreen hearsay PASS attributed=true hostileSilent=true deduped=true "
    .. "noChain=true cap=3 firstHandUnchanged=true injuryMeasured=true")
