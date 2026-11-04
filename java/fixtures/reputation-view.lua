-- PT-29: the card needs a personal standing bar and a separate faction
-- relationship. This drives the real read-out: bands, fill geometry, next
-- threshold, the honest last-change chip, the signed faction bar, and the
-- rule that an unknown faction is never rendered as a fabricated neutral.
local view = assert(KnoxReputationView, "the reputation read-out must be loaded")

-- 1. Personal bands keep the card's existing boundaries.
assert(view.personalLabel(nil) == "Unknown", "a missing relationship is unknown")
assert(view.personalLabel(0) == "Wary", "zero trust is wary")
assert(view.personalLabel(39) == "Wary", "just under 40 is wary")
assert(view.personalLabel(40) == "Cautious", "40 starts cautious")
assert(view.personalLabel(69) == "Cautious", "just under 70 is cautious")
assert(view.personalLabel(70) == "Trusting", "70 starts trusting")
assert(view.personalLabel(100) == "Trusting", "100 stays trusting")
assert(view.personalLabel(90) == "Trusting", "the personal band is not a faction verdict")

-- 2. The personal row carries everything the card draws, and no private score
-- is needed to describe it.
local cautious = view.personal({ trust = 50, lastTrustDelta = 4, lastTrustCause = "defense" })
assert(cautious.known == true and cautious.label == "Cautious", "50 trust is cautious")
assert(cautious.fill > 0.499 and cautious.fill < 0.501, "50 trust fills half the bar")
assert(cautious.nextLabel == "Trusting" and cautious.nextAt == 70, "next band is trusting")
assert(cautious.nextText == "20 to Trusting", "threshold in words: " .. tostring(cautious.nextText))
assert(cautious.delta == 4 and cautious.deltaText == "+4 · defended them",
    "the last real change is named: " .. tostring(cautious.deltaText))

local trusted = view.personal({ trust = 85 })
assert(trusted.nextText == "Fully trusted", "the top band has no invented next step")
assert(trusted.deltaText == nil, "no recorded change means no chip")

local hostile = view.personal({ trust = 90 }, true)
assert(hostile.label == "Trusting" and hostile.tone == "friendly",
    "hostility does not rewrite the personal record")
assert(hostile.hostile == true and hostile.hostileText == "Hostile right now",
    "current hostility is its own state line")
assert(hostile.nextText == "Fully trusted", "the personal threshold is unchanged")

-- 3. The chip never claims a change the save did not record.
assert(view.personal({ trust = 30, lastTrustDelta = 0 }).deltaText == nil,
    "a zero delta is not a change")
assert(view.personal({ trust = 30, lastTrustCause = "defense" }).deltaText == nil,
    "a cause without a delta does not invent a number")
local unknown = view.personal({ trust = 30, lastTrustDelta = 3, lastTrustCause = "??" })
assert(unknown.deltaText == "+3 · their trust changed",
    "an unknown cause never leaks an internal code")
assert(view.personal({ trust = 30, lastTrustDelta = -12, lastTrustCause = "insult" }).deltaText
    == "-12 · was insulted", "a negative change keeps its sign and cause")
assert(view.personal({ trust = 0 }).fill == 0, "zero fills none of the bar")
assert(view.personal({ trust = 100 }).fill == 1, "full trust fills the bar")
assert(view.personal({ trust = 140 }).fill == 1, "a legacy out-of-range score clamps")

-- 4. Faction standing is a separate signed bar with the disposition as its
-- authority, and no relationship is shown as no contact rather than neutral.
local none = view.faction(nil, "Riverside Watch")
assert(none.known == false and none.label == "No contact recorded",
    "no diplomacy row is not a neutral relationship")
assert(none.shortLabel == "No contact", "the row-sized wording is separate from the card's")
assert(none.name == "Riverside Watch" and none.fill == 0.5,
    "an unknown faction still keeps its name and a centred bar")

local neutral = view.faction({ disposition = "neutral", reputation = 0,
    lastReputationDelta = 2, lastReputationCause = "defense" }, "Watch")
assert(neutral.label == "Neutral" and neutral.shortLabel == "Neutral"
    and neutral.fill == 0.5 and neutral.zero == 0.5,
    "zero faction reputation sits on the zero tick")
assert(neutral.deltaText == "+2 · you helped defend them",
    "faction chip uses the faction side's wording: " .. tostring(neutral.deltaText))

local allied = view.faction({ disposition = "allied", reputation = 40 }, "Watch")
assert(allied.label == "Allied" and allied.tone == "friendly", "allied is friendly")
assert(allied.fill > 0.699 and allied.fill < 0.701, "40 reputation is 70% of a signed bar")

local enemy = view.faction({ disposition = "hostile", reputation = -100,
    lastReputationDelta = -20, lastReputationCause = "aggression" }, "Watch")
assert(enemy.label == "Hostile" and enemy.tone == "hostile" and enemy.fill == 0,
    "hostile reputation fills the far left")
assert(enemy.deltaText == "-20 · you attacked one of them",
    "hostile action is named on the faction bar")

local capped = view.faction({ disposition = "allied", reputation = 250 }, "Watch")
assert(capped.score == 100 and capped.fill == 1, "legacy reputation clamps to the bar")

local oldReason = view.faction({ disposition = "hostile", reputation = -20,
    reason = "player_aggression" }, "Watch")
assert(oldReason.deltaText == nil,
    "an old save with only a reason does not invent a delta")
local legacyDelta = view.faction({ disposition = "hostile", reputation = -20,
    lastReputationDelta = -20, reason = "player_aggression" }, "Watch")
assert(legacyDelta.deltaText == "-20 · you attacked one of them",
    "a legacy reason still worded through the current cause table")

-- 5. Personal and faction never merge. One trusting person in a hostile
-- faction keeps both truths visible.
local pair = {
    personal = view.personal({ trust = 80 }, false),
    faction = view.faction({ disposition = "hostile", reputation = -60 }, "Watch"),
}
assert(pair.personal.label == "Trusting" and pair.faction.label == "Hostile",
    "personal trust and faction standing are independent")

-- 6. factionFor reads only real records: it skips a player-owned faction,
-- returns no contact when no diplomacy row exists, and never writes.
local realPersistence = _G.KnoxPersistence
local reads = 0
_G.KnoxPersistence = {
    getSurvivorAffiliation = function() return { kind = "faction", factionId = "f1" } end,
    getFaction = function(id)
        if id == "f1" then return { id = "f1", kind = "npc", name = "Riverside Watch" } end
        return { id = id, kind = "player" }
    end,
    getPlayerFaction = function() return { id = "p1" } end,
    getFactionRelationship = function(first, second)
        reads = reads + 1
        assert(first == "p1" and second == "f1", "the player faction is asked first")
        return { disposition = "neutral", reputation = 12,
            lastReputationDelta = 2, lastReputationCause = "defense" }
    end,
}
local found = assert(view.factionFor("p1", "s1"), "an npc faction resolves")
assert(found.known == true and found.label == "Neutral" and found.name == "Riverside Watch",
    "the real faction row is used")
assert(reads == 1, "one read of the diplomacy row")
_G.KnoxPersistence.getFactionRelationship = function() return nil end
assert(view.factionFor("p1", "s1").known == false,
    "a faction with no diplomacy row is no contact")
_G.KnoxPersistence.getSurvivorAffiliation = function()
    return { kind = "player", factionId = "p1" }
end
assert(view.factionFor("p1", "s1") == nil,
    "the player's own faction is not a foreign relationship")
_G.KnoxPersistence = nil
assert(view.factionFor("p1", "s1") == nil, "no persistence is no guess")
_G.KnoxPersistence = realPersistence

print("Reputation view PASS personal=bands faction=signed separate=true noContact=true")
