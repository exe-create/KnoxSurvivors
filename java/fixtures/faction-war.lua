local Persistence = assert(KnoxPersistence, "persistence is loaded")

assert(Persistence.FACTION_WAR_HOURS == 96, "a war has a fixed length")
assert(type(Persistence.setFactionRelationshipDisposition) == "function",
    "the diplomacy writer exists")

local first = Persistence.ensurePlayerFaction("war-first", 10)
local second = Persistence.ensurePlayerFaction("war-second", 10)
assert(first ~= nil and second ~= nil, "two factions exist for the war")
assert(first.id ~= second.id, "the two factions are different")

assert(Persistence.getFactionDisposition(first.id, second.id, 100) == "neutral",
    "two strangers start neutral")

local relation, result = Persistence.setFactionRelationshipDisposition(
    first.id, second.id, "hostile", 100, "fixture_war", Persistence.FACTION_WAR_HOURS)
assert(relation ~= nil and result == "saved", "the war was written")
assert(relation.hostileUntilHours == 100 + Persistence.FACTION_WAR_HOURS,
    "the row carries the hour the war lapses")
assert(Persistence.getFactionDisposition(first.id, second.id, 100) == "hostile",
    "the war is hostile the hour it starts")
assert(Persistence.getFactionDisposition(first.id, second.id,
    100 + Persistence.FACTION_WAR_HOURS - 1) == "hostile",
    "the war still holds just before the deadline")
assert(Persistence.getFactionDisposition(first.id, second.id,
    100 + Persistence.FACTION_WAR_HOURS) == "neutral",
    "the war lapses at its deadline")

local lapsed = Persistence.getFactionRelationship(first.id, second.id,
    100 + Persistence.FACTION_WAR_HOURS + 5)
assert(lapsed ~= nil and lapsed.disposition == "neutral",
    "a lapsed war reads as neutral")
assert(lapsed.lapsed == true, "the lapse is reported, not hidden")
assert(lapsed.reason == "fixture_war", "the cause survives the lapse")
assert(lapsed.hostileUntilHours ~= nil, "the window is kept as history")

local mirrored = Persistence.getFactionRelationship(second.id, first.id, 120)
assert(mirrored ~= nil and mirrored.disposition == "hostile",
    "the row is symmetric: either order reads the same war")

local refreshed = Persistence.setFactionRelationshipDisposition(
    second.id, first.id, "hostile", 150, "fixture_renewed", Persistence.FACTION_WAR_HOURS)
assert(refreshed ~= nil
    and refreshed.hostileUntilHours == 150 + Persistence.FACTION_WAR_HOURS,
    "renewing the war extends the same row")
assert(Persistence.getFactionDisposition(first.id, second.id, 200) == "hostile",
    "the renewed war is still running")

local peace = Persistence.setFactionRelationshipDisposition(
    first.id, second.id, "neutral", 210, "fixture_peace")
assert(peace ~= nil and peace.hostileUntilHours == nil,
    "a peace clears the war window")
assert(Persistence.getFactionDisposition(first.id, second.id, 240) == "neutral",
    "a cleared window cannot resurrect a war")

local policy = Persistence.setFactionRelationshipDisposition(
    first.id, second.id, "hostile", 300, "hostile_patrol")
assert(policy ~= nil and policy.hostileUntilHours == nil,
    "a policy war names no window")
assert(Persistence.getFactionDisposition(first.id, second.id, 5000) == "hostile",
    "a policy war does not lapse on the clock")

local bad = Persistence.setFactionRelationshipDisposition(
    "no-such-faction", second.id, "hostile", 10, "invalid")
assert(bad == nil, "a war needs two real factions")

print("Faction war PASS window=96 lapse=1 renew=1 peace=1 policy=1")
