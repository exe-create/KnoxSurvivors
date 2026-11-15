-- Production raid intent and warning owner. The pure section is injected as
-- codecRaidIntent; the durable stamp is driven through the real
-- KS_KnoxEvents module with stubbed persistence reads.
local I = assert(codecRaidIntent, "raid intent source is loaded")
local E = assert(KnoxEvents, "raid event owner is loaded")
assert(type(I.raidCause) == "function" and type(E.warnRaid) == "function",
    "both raid halves are present")

-- CAUSE: one cause from recorded facts, most specific first.
local cause, why = I.raidCause({ retaliation = true, need = true, grievance = true })
assert(cause == "retaliation", "a repayment outranks hunger and a grudge")
cause, why = I.raidCause({ need = true, grievance = true })
assert(cause == "need", "a measured shortage outranks a standing grudge")
cause, why = I.raidCause({ grievance = true })
assert(cause == "grievance", "a hostile diplomacy row is itself the cause")
cause, why = I.raidCause({})
assert(cause == nil and why == "no_cause", "no evidence means no invented cause")
cause, why = I.raidCause({ need = "true" })
assert(cause == nil and why == "no_cause", "a truthy non-boolean is not evidence")
cause, why = I.raidCause(nil)
assert(cause == nil and why == "no_evidence", "a missing evidence table is refused")

-- STRENGTH: a band, never a headcount.
assert(I.raidStrength(1) == "one of them", "a lone raider is not a party")
assert(I.raidStrength(2) == "a few armed", "two raiders are a few")
assert(I.raidStrength(3) == "a few armed", "three raiders are still a few")
assert(I.raidStrength(4) == "several armed", "four raiders are several")
assert(I.raidStrength(6) == "several armed", "six raiders are still several")
assert(I.raidStrength(7) == "a strong party", "seven raiders are a strong party")
assert(I.raidStrength(0) == nil, "an empty party has no strength")
assert(I.raidStrength(nil) == nil, "a missing party size has no strength")

-- DIRECTION: the compass word of the attacker's home from the defended home.
local function dir(fromX, fromY)
    return I.raidDirection({ x = fromX, y = fromY }, { x = 0, y = 0 })
end
assert(dir(0, -100) == "north", "a smaller y is north")
assert(dir(0, 100) == "south", "a larger y is south")
assert(dir(100, 0) == "east", "a larger x is east")
assert(dir(-100, 0) == "west", "a smaller x is west")
assert(dir(100, -100) == "north-east", "a square corner is a diagonal")
assert(dir(100, 100) == "south-east", "a southern corner is south-east")
assert(dir(-100, 100) == "south-west", "a south-western corner is south-west")
assert(dir(-100, -100) == "north-west", "a north-western corner is north-west")
assert(dir(100, 30) == "east", "a shallow approach stays a cardinal word")
assert(dir(30, 100) == "south", "a steep approach stays a cardinal word")
local same, sameWhy = I.raidDirection({ x = 5, y = 5 }, { x = 5, y = 5 })
assert(same == nil and sameWhy == "same_place", "two homes on one tile have no direction")
local noPoint, noPointWhy = I.raidDirection({ x = 5 }, { x = 0, y = 0 })
assert(noPoint == nil and noPointWhy == "no_points", "an incomplete point has no direction")

-- ETA: plain language, no false precision.
assert(I.raidEtaText(0.1) == "under an hour out", "minutes away reads as under an hour")
assert(I.raidEtaText(0.99) == "under an hour out", "just under an hour stays under")
assert(I.raidEtaText(1) == "about an hour out", "one hour reads as about an hour")
assert(I.raidEtaText(1.4) == "about an hour out", "an hour and a bit rounds down")
assert(I.raidEtaText(2.4) == "about 2 h out", "two hours and a half rounds to two")
assert(I.raidEtaText(0) == "arriving now", "a reached ETA is not a future warning")
assert(I.raidEtaText(nil) == nil, "an unknown ETA is not invented")

-- ONE SENTENCE: faction, direction, band and cause, and no exclamation.
local warning = {
    factionName = "Northside Crew", direction = "south-east",
    strength = "a few armed", cause = "retaliation",
    etaHours = 12.15, hours = 12,
}
local sentence = I.raidWarningText(warning)
assert(sentence == "Northside Crew is coming from the south-east: a few armed, and they want it back.",
    "the warning names who, from where, how many and why: " .. tostring(sentence))
assert(sentence:find("!", 1, true) == nil, "a warning is a sentence, not an exclamation")
assert(sentence:sub(-1) == ".", "the warning ends with a full stop")
local noDirection = I.raidWarningText({ factionName = "Northside Crew", strength = "several armed" })
assert(noDirection == "Northside Crew is coming: several armed.",
    "an unreadable origin drops the direction instead of guessing: " .. tostring(noDirection))
assert(I.raidWarningText({ strength = "several armed" }) == nil,
    "a warning without a faction name is not spoken")
assert(I.raidWarningText({ factionName = "Northside Crew" }) == nil,
    "a warning without a strength band is not spoken")

-- The World row: cause and ETA, in one line.
local threat = I.raidThreatText(warning, 12)
assert(threat == "Raid on your home - from the south-east, a few armed, they want it back; under an hour out",
    "the threat line carries direction, band, cause and ETA: " .. tostring(threat))
assert(I.raidThreatText({ direction = "north" }, 12) == "Raid on your home - from the north",
    "a bare warning still names the direction it has")

-- The attention item: one title, one detail, one existing action.
local item = I.raidAttention(warning)
assert(item.title == "A raid is coming from the south-east", "the attention title names the approach")
assert(item.detail == "A few armed; they want it back.", "the detail names the band and the cause")
assert(item.action == "review_world" and item.actionLabel == "Review threat",
    "the raid row routes to the existing World tab")
local bare = I.raidAttention({ strength = "several armed" })
assert(bare.title == "A raid is coming" and bare.detail == "Several armed.",
    "an unknown origin and cause invent nothing")

-- DURABLE STAMP: written once on the event record, refused afterwards.
local persistence = KnoxPersistence
local saved = {
    getKnoxEventState = persistence.getKnoxEventState,
    getFaction = persistence.getFaction,
    getBase = persistence.getBase,
    getRaidHistory = persistence.getRaidHistory,
    getFactionRelationship = persistence.getFactionRelationship,
}
local state = { records = {}, cooldowns = {}, automatic = {} }
persistence.getKnoxEventState = function() return state end
local factions = {
    ["faction-north"] = { id = "faction-north", kind = "npc", name = "Northside Crew",
        memberIds = { "raider-1", "raider-2", "raider-3" } },
}
local bases = {
    ["base-home"] = { id = "base-home", ownerKind = "player", ownerId = "player-1",
        home = { minX = 0, minY = 0, width = 4, height = 4, z = 0 } },
    ["base-north"] = { id = "base-north", ownerKind = "faction", ownerId = "faction-north",
        home = { minX = 100, minY = 100, width = 4, height = 4, z = 0 } },
}
local history = {
    { sourceFactionId = "player-faction", targetBaseId = "base-north", atHours = 4 },
}
persistence.getFaction = function(id) return factions[id] end
persistence.getBase = function(id) return bases[id] end
persistence.getRaidHistory = function() return history end
persistence.getFactionRelationship = function()
    return { disposition = "hostile", reason = "hit one of ours", changedAtHours = 3 }
end
local function raid(id, revision, phase, members)
    return {
        id = id, kind = "faction_raid", phase = phase, revision = revision,
        sourceFactionId = "faction-north", sourceBaseId = "base-north",
        targetBaseId = "base-home", targetFactionId = "player-faction",
        memberIds = members or { "raider-1", "raider-2", "raider-3" },
        dueAtHours = 10, deadlineHours = 34, lastChangedAtHours = 10,
    }
end
state.records["raid-1"] = raid("raid-1", 3, "scheduled")
local stamped = E.warnRaid("raid-1", 3, 12)
assert(stamped ~= nil, "an inbound raid is warned once")
assert(stamped.cause == "retaliation", "our own earlier raid is the recorded cause")
assert(stamped.direction == "south-east", "the warning reads the two real homes")
assert(stamped.strength == "a few armed", "three named members are a few armed")
assert(stamped.etaHours ~= nil and math.abs(stamped.etaHours - 12.15) < 1e-9,
    "the ETA uses the shared travel pace: " .. tostring(stamped.etaHours))
assert(stamped.factionName == "Northside Crew", "the warning carries the real faction name")
local stored = state.records["raid-1"].warning
assert(type(stored) == "table" and stored.cause == "retaliation",
    "the warning lives on the event record, so a reload is silent")
local again, againWhy = E.warnRaid("raid-1", 3, 12)
assert(again == nil and againWhy == "already_warned", "a warning is never repeated")

state.records["raid-2"] = raid("raid-2", 5, "scheduled")
local stale, staleWhy = E.warnRaid("raid-2", 4, 12)
assert(stale == nil and staleWhy == "stale_revision", "a late callback cannot stamp a newer event")
state.records["raid-2"].phase = "active"
local late, lateWhy = E.warnRaid("raid-2", 5, 12)
assert(late == nil and lateWhy == "not_inbound", "an assault already under way is not warned")
assert(state.records["raid-2"].warning == nil, "a refused warning writes nothing")

state.records["raid-3"] = raid("raid-3", 1, "scheduled")
local savedFaction = factions["faction-north"]
factions["faction-north"] = nil
local nameless, namelessWhy = E.warnRaid("raid-3", 1, 12)
assert(nameless == nil and namelessWhy == "warning_facts_unavailable",
    "an unreadable faction produces no invented name")
factions["faction-north"] = savedFaction

-- READ-ONLY PROJECTION: the home line sees the same raid without silencing it.
state.records["raid-1"].phase = "completed"
state.records["raid-2"].phase = "completed"
state.records["raid-3"].phase = "completed"
state.records["raid-4"] = raid("raid-4", 1, "approaching")
local projected = E.inboundRaidForBase("base-home", 12)
assert(projected ~= nil and projected.eventId == "raid-4",
    "the home projection reports the inbound raid")
assert(projected.title == "A raid is coming from the south-east",
    "the home projection uses the one copy owner: " .. tostring(projected.title))
assert(projected.threatText ~= nil, "the projection carries the World-row line")
assert(state.records["raid-4"].warning == nil,
    "a projection never stamps the warning, so the rail still speaks once")
assert(E.inboundRaidForBase("base-other", 12) == nil, "another base is not warned")
state.records["raid-4"].phase = "active"
assert(E.inboundRaidForBase("base-home", 12) == nil, "a fight under way is not a warning")
state.records["raid-4"].phase = "approaching"

-- Two inbound raids: the home line names the sooner one.
state.records["raid-5"] = raid("raid-5", 1, "scheduled")
bases["base-far"] = { id = "base-far", ownerKind = "faction", ownerId = "faction-north",
    home = { minX = 900, minY = 900, width = 4, height = 4, z = 0 } }
state.records["raid-5"].sourceBaseId = "base-far"
local soonest = E.inboundRaidForBase("base-home", 12)
assert(soonest ~= nil and soonest.eventId == "raid-4",
    "the nearer raid is the one the home line names: " .. tostring(soonest and soonest.eventId))

-- WHO IS OUT OF THE WAY, IN THE SAME SENTENCE. The base projection counts
-- the residents; this owner only says it, so the band, the pill and the
-- in-world line cannot disagree about who is hiding.
assert(I.raidFallbackClause(nil) == nil, "no watch facts, no claim about anybody")
assert(I.raidFallbackClause({}) == nil, "an empty watch makes no claim")
assert(I.raidFallbackClause({ holding = 0 }) == nil,
    "nobody out of the way is not a sentence")
assert(I.raidFallbackClause({ holding = 1 }) == "1 resident is out of the way.",
    "one resident is singular")
assert(I.raidFallbackClause({ holding = 3 }) == "3 residents are out of the way.",
    "three residents are plural")
assert(I.raidFallbackClause({ holding = 2.7 }) == "2 residents are out of the way.",
    "a fractional count floors instead of inventing a person")
assert(I.raidFallbackClause({ holding = "2" }) == "2 residents are out of the way.",
    "a numeric string is still a count")
assert(I.raidFallbackClause({ holding = -1 }) == nil, "a negative count is not a fact")
assert(I.raidFallbackClause({ holding = "many" }) == nil, "a word is not a count")

local held = I.raidAttention(warning, { posts = 2, staffed = 1, holding = 2 })
assert(held.detail == "A few armed; they want it back. 1 of 2 posts staffed. 2 residents are out of the way.",
    "the raid row says who is watching and who is out of the way: " .. tostring(held.detail))
local quiet = I.raidAttention(warning, { posts = 2, staffed = 2 })
assert(quiet.detail == "A few armed; they want it back. Every post is staffed.",
    "a home with nobody holding reads exactly as before")
local holdingOnly = I.raidAttention(warning, { holding = 1 })
assert(holdingOnly.detail == "A few armed; they want it back. 1 resident is out of the way.",
    "a count without a watch still speaks: " .. tostring(holdingOnly.detail))

-- RESTORE.
for key, value in pairs(saved) do persistence[key] = value end
assert(persistence.getKnoxEventState == saved.getKnoxEventState, "persistence reads are restored")
