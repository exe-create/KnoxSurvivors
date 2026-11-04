-- A faction forms through one owner, so the world says it once. Three people
-- who have actually travelled together become a faction; the record carries a
-- name and an unserved notice. Nothing here invents the shared hour: promotion
-- itself refuses until the readiness rule is satisfied.
local P = assert(rawget(_G, "KnoxPersistence"), "persistence owner missing")

local a = assert(P.allocateWorldSurvivor({ x = 61, y = 71, z = 0, key = "fn-a", region = "FN" }, 10))
local b = assert(P.allocateWorldSurvivor({ x = 62, y = 71, z = 0, key = "fn-b", region = "FN" }, 10))
local c = assert(P.allocateWorldSurvivor({ x = 63, y = 71, z = 0, key = "fn-c", region = "FN" }, 10))
local group = assert(P.createTravelGroup({ a, b, c }, 10), "three independents form a group")

local tooFew, why = P.promoteTravelGroupToFaction(group.id, 11, 4)
assert(tooFew == nil and tostring(why) == "requires_4_members",
    "a roster below the configured minimum is refused, got " .. tostring(why))

local faction, reason = P.promoteTravelGroupToFaction(group.id, 12, 3)
assert(faction ~= nil and reason == "created", "the group becomes a faction")
assert(type(faction.name) == "string" and faction.name ~= "",
    "a faction is named, never a bare id")
assert(faction.formationNoticed ~= true,
    "a new faction's first sighting has not been served")
assert(faction.formedAtHours == 12, "the formation hour is the real world hour")

local again, second = P.promoteTravelGroupToFaction(group.id, 13, 3)
assert(second == "already_faction", "promotion is idempotent")
assert(again.id == faction.id, "the same faction is returned")
assert(again.formationNoticed ~= true, "re-promotion does not spend the notice")

-- The player has now seen a member: the notice is spent exactly once.
again.formationNoticed = true
assert(P.getFaction(faction.id).formationNoticed == true, "the flag is durable state")

assert(P.getFactionForSurvivor(a).id == faction.id, "a member resolves to its faction")

-- The accent is identity, not gear: three legible channels in range, stable
-- across reads, and never shared by reference with the palette it came from.
local accent = faction.accent
assert(type(accent) == "table" and #accent == 3, "a faction carries an accent")
for i = 1, 3 do
    local channel = accent[i]
    assert(type(channel) == "number" and channel >= 0 and channel <= 1,
        "accent channel " .. tostring(i) .. " is a colour, got " .. tostring(channel))
end
local reread = P.getFaction(faction.id).accent
assert(reread[1] == accent[1] and reread[3] == accent[3],
    "the accent is durable state, not recomputed noise")

-- The player's own group shares the mechanism, including on an old save.
local mine = assert(P.ensurePlayerFaction("you", 10), "the player has a group")
assert(type(mine.accent) == "table" and #mine.accent == 3,
    "the player's group carries an accent")
assert(type(mine.name) == "string" and mine.name ~= "", "and a name to derive it from")
assert(P.getFaction(mine.id).accent[1] == mine.accent[1],
    "the repair is written to the record, not computed per read")

-- Any surface holding only the name can ask for the colour, and gets the same
-- one the record carries.
local byName = assert(P.factionAccent(faction.name), "the name yields a colour")
assert(byName[1] == faction.accent[1] and byName[3] == faction.accent[3],
    "name and record agree on the same faction")
assert(P.factionAccent("") == nil, "an empty name has no colour")
assert(P.factionAccent(nil) == nil, "a missing name has no colour")

print("faction_formation_notice: refused=requires_4 created=named notice=once accent=rgb player=accent byname=shared")
