local P = KnoxPersistence
local B = codecLeaderIntent

assert(type(B.chooseIntent) == "function", "chooseIntent must exist")
assert(type(B.applyFactionIntent) == "function", "applyFactionIntent must exist")
assert(type(B.factionIntentFacts) == "function", "factionIntentFacts must exist")

-- A raid outranks every other consideration.
local chosen, why = B.chooseIntent(
    { raidInbound = true, members = 1, minimumMembers = 4 }, "shelter"
)
assert(chosen == "security" and why == "raid_inbound", "an inbound raid means security")
assert(B.chooseIntent({ raidInbound = true }, nil) == "security",
    "a raid decides even with no current intent")

-- Below its own minimum strength, the group works on growth.
chosen, why = B.chooseIntent(
    { raidInbound = false, members = 2, minimumMembers = 4 }, "stockpile"
)
assert(chosen == "growth" and why == "under_strength", "an under-strength group grows")

-- At or above strength, the leader keeps what it already decided.
assert(B.chooseIntent({ members = 4, minimumMembers = 4 }, "trade") == "trade",
    "a group at strength keeps its intent")
assert(B.chooseIntent({ members = 9, minimumMembers = 4 }, "health") == "health")

-- No facts is not a signal, and neither is a missing count.
assert(B.chooseIntent({}, "trade") == "trade")
assert(B.chooseIntent({}, nil) == nil)
assert(B.chooseIntent(nil, "trade") == "trade")
assert(B.chooseIntent({ minimumMembers = 4 }, "trade") == "trade",
    "an unknown member count is never read as under strength")
assert(B.chooseIntent({ members = 2, minimumMembers = 0 }, "trade") == "trade",
    "a zero minimum is not a shortage")

-- One writer owns the one field, for both kinds of owner.
local factionBase = { id = "base-1", ownerKind = "faction", ownerId = "faction-1" }
assert(P.writeBaseIntentFor(factionBase, "faction", "faction-1", "security", 12) == true)
assert(factionBase.intent == "security", "the faction base records its intent")
assert(factionBase.intentChangedAtHours == 12, "the change is stamped")

assert(select(2, P.writeBaseIntentFor(factionBase, "faction", "faction-2", "growth", 13))
    == "not_your_base", "another faction cannot set this base")
assert(select(2, P.writeBaseIntentFor(factionBase, "player", "p1", "growth", 13))
    == "not_your_base", "a player cannot set a faction base")
assert(select(2, P.writeBaseIntentFor(factionBase, "faction", "faction-1", "nonsense", 13))
    == "unknown_intent", "an unknown intent is refused")
assert(factionBase.intent == "security", "a refusal never writes")

local playerBase = { id = "base-2", ownerKind = "player", ownerId = "p1" }
assert(P.writeBaseIntentFor(playerBase, "player", "p1", "shelter", 14) == true)
assert(playerBase.intent == "shelter", "the player writer still works")
assert(select(2, P.writeBaseIntentFor(nil, "player", "p1", "shelter", 14)) == "missing_base")

-- The applier changes nothing when the decision matches the record.
local applied, detail = B.applyFactionIntent(factionBase,
    { id = "faction-1" }, { members = 8, minimumMembers = 4 }, 20)
assert(applied == "security" and detail == "unchanged", "a matching decision writes nothing")
assert(factionBase.intentChangedAtHours == 12, "an unchanged decision does not restamp")

-- And it refuses records that are not ready rather than throwing.
assert(select(2, B.applyFactionIntent(nil, {}, {}, 20)) == "not_ready")
assert(select(2, B.applyFactionIntent(factionBase, nil, {}, 20)) == "not_ready")

print("Leader intent PASS raid=true growth=true neutral=true ownership=true writer=true no_invented_signals=true")
