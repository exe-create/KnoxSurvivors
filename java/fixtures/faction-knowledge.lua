-- Knowledge-gated group visibility: drives the real
-- KnoxPersistence.factionKnownToPlayer and the real
-- WorldView.visibleFactions with only the save store and the faction map doubled.
-- Hidden: no record, storage-only id, member with no relation, commitment-only
-- knowledge, an unmet cult with a home base. Visible: a member's firstMetHours,
-- an observer "seen" note, an observer "report" note, a met cult.
local K = assert(codecFactionKnowledge)
local P, W = assert(K.P), assert(K.W)
local oldRoot = root
local factions, knowledge, survivors = {}, {}, {}
P.getFaction = function(id) return factions[id] end
P.getObserverKnowledge = function(playerId, memberId)
    return knowledge[tostring(playerId) .. "|" .. tostring(memberId)]
end
root = function() return { survivors = survivors } end
local function faction(id, kind, members, extra)
    factions[id] = { id = id, kind = kind or "npc", name = id, memberIds = members }
    if type(extra) == "table" then
        for key, value in pairs(extra) do factions[id][key] = value end
    end
    return factions[id]
end
local function member(id, metHours)
    survivors[id] = survivors[id] or { playerRelationships = {} }
    if metHours ~= nil then
        survivors[id].playerRelationships["player"] = { firstMetHours = metHours }
    end
end
local function known(id) return P.factionKnownToPlayer("player", id) end
-- No record at all: hidden.
faction("unmet", "npc", { "u1" }); member("u1")
assert(known("unmet") == false, "faction_knowledge: a group with no meeting record must stay hidden")
-- A real meeting with one member: visible.
faction("met", "npc", { "u2" }); member("u2", 10)
assert(known("met") == true, "faction_knowledge: a member's firstMetHours must make the group known")
-- Observer knowledge of what was seen: visible.
faction("seen", "npc", { "u3" }); member("u3")
knowledge["player|u3"] = { seen = { atHours = 5 } }
assert(known("seen") == true, "faction_knowledge: an observer-seen record must make the group known")
-- Observer knowledge from a report: visible.
faction("reported", "npc", { "u4" }); member("u4")
knowledge["player|u4"] = { report = { atHours = 6 } }
assert(known("reported") == true, "faction_knowledge: an observer report must make the group known")
-- An owner commitment alone is not a meeting.
faction("commitOnly", "npc", { "u5" }); member("u5")
knowledge["player|u5"] = { commitment = { atHours = 7 } }
assert(known("commitOnly") == false, "faction_knowledge: an owner commitment alone is not a meeting")
-- Storage alone is not knowledge: a faction record with no member record hides.
faction("empty", "npc", {})
assert(known("empty") == false, "faction_knowledge: a group with no members and no record stays hidden")
faction("idOnly", "npc", nil)
assert(known("idOnly") == false, "faction_knowledge: a stored faction id alone stays hidden")
-- A cult is an ordinary faction: members and a home base, no cult flag. The
-- predicate must not need an identity field, and owning property must not leak
-- knowledge. The identity value itself is still an owner decision; this case
-- proves only that visibility never depends on one.
faction("cult", "npc", { "c1" }, { homeBaseId = "cultCamp" })
member("c1")
assert(known("cult") == false,
    "faction_knowledge: an unmet cult with a home base must stay hidden")
member("c1", 20)
assert(known("cult") == true,
    "faction_knowledge: a met cult must become visible")
local cultRows = W.visibleFactions(factions, "player")
local cultListed = false
for _, row in ipairs(cultRows) do if row.id == "cult" then cultListed = true end end
assert(cultListed, "faction_knowledge: a met cult must appear in the world list")
assert(factions.cult.homeBaseId == "cultCamp" and #factions.cult.memberIds == 1,
    "faction_knowledge: visibility must not mutate the cult record")
-- A player-owned cult stays out of the world list even when its member is met.
faction("cultPlayer", "player", { "c1" })
local afterPlayer = W.visibleFactions(factions, "player")
local playerListed = false
for _, row in ipairs(afterPlayer) do if row.id == "cultPlayer" then playerListed = true end end
assert(not playerListed,
    "faction_knowledge: a player-owned cult stays out of the world list")
-- The display helper lists exactly the known non-player groups.
faction("playerGroup", "player", { "u2" })
local rows = W.visibleFactions(factions, "player")
local ids = {}
for _, row in ipairs(rows) do ids[row.id] = true end
assert(ids.met and ids.seen and ids.reported, "faction_knowledge: known groups must be listed")
assert(not ids.unmet and not ids.commitOnly and not ids.empty and not ids.idOnly,
    "faction_knowledge: unknown groups must be omitted")
assert(not ids.playerGroup, "faction_knowledge: player factions stay out of the world list")
assert(factions.unmet ~= nil and #factions.unmet.memberIds == 1,
    "faction_knowledge: filtering must not delete or mutate faction records")
-- Restore the real globals the source slice replaced, for later fixtures.
KnoxPersistence, WorldView = K.realP, K.realW
root = oldRoot
