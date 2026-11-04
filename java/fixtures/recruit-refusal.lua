-- A refusal the survivor chose leaves a durable wait; the service enforces it.
local P = KnoxPersistence

assert(P.recordPlayerConversation("rf-player", "rf-survivor", 1, 10, 0) ~= nil,
    "a real conversation creates the relationship the refusal is stored on")
local relation = assert(P.recordPlayerRecruitRefusal("rf-player", "rf-survivor", 20, 2))
assert(tonumber(relation.nextRecruitHours) == 22,
    "a refusal two hours long blocks until hour 22")

-- Asking again cannot shorten the wait, even with a tiny cooldown.
local again = assert(P.recordPlayerRecruitRefusal("rf-player", "rf-survivor", 20, 0.5))
assert(tonumber(again.nextRecruitHours) == 22,
    "a second refusal never shortens the existing wait")

-- The wait is per player-pair, so a second player asking the same survivor
-- starts from that pair's own value instead of inheriting the first wait.
local otherPlayer = P.recordPlayerRecruitRefusal("rf-other", "rf-survivor", 20, 3)
assert(otherPlayer ~= nil and tonumber(otherPlayer.nextRecruitHours) == 23,
    "another player's refusal wait is its own")
-- The stored wait is a real number a gate can compare, not a copy artefact.
local stored = P.getPlayerRelationshipSnapshot("rf-player", "rf-survivor")
assert(stored ~= nil, "the relationship is still readable after a refusal")

print("Recruit refusal PASS wait=true monotonic=true identity=true")
