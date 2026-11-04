-- Which base a newcomer would move into. Base selection is the only new policy
-- in the base invitation, so it is driven directly against a stubbed base list:
-- a wrong choice here would post somebody to the wrong settlement. Two or more
-- homes must always be asked about, never resolved by where the player happens
-- to stand.
local c = KnoxCompanionService
local ownedA = { id = "base-a", ownerKind = "player", ownerId = "codec-owner",
    name = "Farm", createdAtHours = 1 }
local ownedB = { id = "base-b", ownerKind = "player", ownerId = "codec-owner",
    name = "Depot", createdAtHours = 2 }
local foreign = { id = "base-x", ownerKind = "player", ownerId = "codec-other",
    name = "Theirs", createdAtHours = 1 }
local bases = {}
local standing = nil
KnoxPersistence = {
    getBasesForOwner = function(kind, id)
        local out = {}
        for _, base in ipairs(bases) do
            if base.ownerKind == kind and base.ownerId == id then out[#out + 1] = base end
        end
        return out
    end,
    getBaseAtSquare = function(x, y, z, kind)
        return standing
    end,
}
local function player(x, y, z)
    return {
        getCurrentSquare = function()
            return {
                getX = function() return x end,
                getY = function() return y end,
                getZ = function() return z end,
            }
        end,
    }
end

bases = { ownedA }
standing = nil
local base, reason = c.inviteBaseFor(player(0, 0, 0), "codec-owner")
assert(base == ownedA and reason == "only_base", "a single base needs no question")

-- Two homes: standing in one is not an answer, because the player may mean the
-- other. The old code resolved "here" and could post a newcomer to the wrong
-- settlement.
bases = { ownedA, ownedB }
standing = ownedB
base, reason = c.inviteBaseFor(player(1, 2, 0), "codec-owner")
assert(base == nil and reason == "ambiguous_base",
    "two homes are never resolved by standing in one")

-- The player's explicit answer resolves either home.
base, reason = c.inviteBaseFor(player(1, 2, 0), "codec-owner", "base-b")
assert(base == ownedB and reason == "chosen", "an explicit choice resolves the second base")
base, reason = c.inviteBaseFor(player(1, 2, 0), "codec-owner", "base-a")
assert(base == ownedA and reason == "chosen", "an explicit choice resolves the first base")

-- Somebody else's base is never offered, and a foreign id is never accepted.
standing = foreign
base, reason = c.inviteBaseFor(player(1, 2, 0), "codec-owner")
assert(base == nil and reason == "ambiguous_base",
    "somebody else's base is not the player's home to offer")
base, reason = c.inviteBaseFor(player(1, 2, 0), "codec-owner", "base-x")
assert(base == nil and reason == "unknown_base",
    "a base owned by somebody else is refused as a choice")

-- Only the owner's homes reach the chooser, in the owner's own order.
bases = { ownedA, ownedB, foreign }
local choices = c.baseChoicesFor(nil, "codec-owner")
assert(#choices == 2 and choices[1] == ownedA and choices[2] == ownedB,
    "the chooser lists exactly the owner's homes")
choices = c.baseChoicesFor(nil, "codec-other")
assert(#choices == 1 and choices[1] == foreign,
    "another owner's list is never mixed into this player's chooser")
choices = c.baseChoicesFor(nil, nil)
assert(#choices == 0, "a missing owner has no homes to offer")

bases = {}
standing = nil
base, reason = c.inviteBaseFor(player(0, 0, 0), "codec-owner")
assert(base == nil and reason == "no_base", "no base means the invitation cannot start")

bases = { ownedA }
base, reason = c.inviteBaseFor({}, "codec-owner")
assert(base == ownedA and reason == "only_base",
    "a player without a loaded square still resolves their only base")

base, reason = c.inviteBaseFor(nil, "codec-owner")
assert(base == ownedA and reason == "only_base", "a missing player cannot throw")

-- The invitation gate reports the open question as "choose_base", which is what
-- the talk panel turns into the base chooser. A refusal from recruitment still
-- wins over the base question, so a hostile survivor is never asked to pick.
bases = { ownedA, ownedB }
c.getPlayerId = function() return "codec-owner" end
c.canRecruit = function() return true, "ready" end
local ready, why = c.canInviteToBase({}, "survivor-1")
assert(ready == true and why == "choose_base",
    "two homes tell the caller to ask, not to refuse")
local chosen = nil
ready, why, chosen = c.canInviteToBase({}, "survivor-1", "base-b")
assert(ready == true and why == "ready" and chosen == ownedB,
    "the player's answer resolves the invitation gate")
ready, why = c.canInviteToBase({}, "survivor-1", "base-x")
assert(ready == false and why == "unknown_base",
    "a base the player does not own cannot be chosen")
c.canRecruit = function() return false, "hostile" end
ready, why = c.canInviteToBase({}, "survivor-1")
assert(ready == false and why == "hostile",
    "a hostile survivor is refused before any base question")
bases = { ownedA }
c.canRecruit = function() return true, "ready" end
ready, why, chosen = c.canInviteToBase({}, "survivor-1")
assert(ready == true and why == "ready" and chosen == ownedA,
    "a single home needs no question")
