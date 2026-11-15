-- Theft warning: drives the production KnoxPersistence.recordPlayerFactionTheft.
-- The save root, base/faction lookups and the relationship write are boundary
-- doubles; the staging decision is the real function.
-- A first theft warns and leaves the faction non-hostile; a second theft by the
-- same player from the same faction flips hostile with reason player_theft. A
-- different player or faction gets its own warning; an independent survivor's
-- property is exempt; an already-hostile faction does not re-warn.
local K = assert(codecTheftWarning)
local P = assert(K.P)
local players = { p1 = { id = "p1" }, p2 = { id = "p2" } }
local factions = { f1 = { id = "f1", kind = "npc" }, f2 = { id = "f2", kind = "npc" } }
local relationships = {}
local bases = {
    f1 = { id = "baseF1", ownerKind = "faction", ownerId = "f1" },
    f2 = { id = "baseF2", ownerKind = "faction", ownerId = "f2" },
    solo = { id = "baseSolo", ownerKind = "survivor", ownerId = "s1" },
}
local hostileWrites = 0
P.getBase = function(id) return bases[id] end
P.getFaction = function(id) return factions[id] end
P.ensurePlayerFaction = function(playerId) return { id = "pf-" .. tostring(playerId) } end
P.getFactionRelationship = function(first, second) return relationships[first .. "|" .. second] end
P.setFactionRelationshipDisposition = function(first, second, disposition)
    hostileWrites = hostileWrites + 1
    local relation = { disposition = disposition, reason = "player_theft" }
    relationships[first .. "|" .. second] = relation
    return relation, "saved"
end
root = function() return { players = players, factions = factions, factionRelationships = relationships } end
local function theft(playerId, baseId, hours)
    return P.recordPlayerFactionTheft(playerId, baseId, hours)
end
local _, status = theft("p1", "f1", 10)
assert(status == "warning", "theft_warning: first theft must warn, got " .. tostring(status))
assert(hostileWrites == 0, "theft_warning: a first theft must not flip the faction hostile")
assert(type(factions.f1.theftWarnings) == "table" and factions.f1.theftWarnings.p1 == 10,
    "theft_warning: the warning must be recorded per player")
assert(factions.f1.lastPlayerWarning ~= nil
    and factions.f1.lastPlayerWarning.playerId == "p1"
    and factions.f1.lastPlayerWarning.atHours == 10,
    "theft_warning: the warning record must carry the player and hour")
local _, second = theft("p1", "f1", 20)
assert(second == "hostile", "theft_warning: a second theft must flip hostile, got " .. tostring(second))
assert(hostileWrites == 1, "theft_warning: hostility must be written once")
assert(factions.f1.lastPlayerHostileAction ~= nil
    and factions.f1.lastPlayerHostileAction.atHours == 20,
    "theft_warning: the existing hostile action record must still be written")
local _, third = theft("p1", "f1", 30)
assert(third == "already_hostile", "theft_warning: an already-hostile faction must not re-warn")
assert(hostileWrites == 1, "theft_warning: already-hostile must not write hostility again")
local _, otherPlayer = theft("p2", "f1", 40)
assert(otherPlayer == "warning", "theft_warning: a different player starts at warning")
local _, otherFaction = theft("p1", "f2", 50)
assert(otherFaction == "warning", "theft_warning: a different faction starts at warning")
local _, solo = theft("p1", "solo", 60)
assert(solo == "invalid_theft", "theft_warning: independent survivor property is exempt")
local realEnsure = P.ensurePlayerFaction
P.ensurePlayerFaction = function() return { id = "f2" } end
local _, same = theft("p1", "f2", 70)
assert(same == "same_faction", "theft_warning: a player faction cannot steal from itself")
P.ensurePlayerFaction = realEnsure
root = nil
KnoxPersistence = K.realP
