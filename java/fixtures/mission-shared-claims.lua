-- A sortie shares one search area, so a container another member is already
-- walking to must not be planned twice. Two kinds of sortie exist: a mission
-- team (shared away-team id) and a settlement supply pair (shared base id, both
-- members flagged as the supply party). The claim is the partner's own
-- reservation, so this fixture drives the real extracted check with fake
-- controllers and plain table keys standing in for containers.
assert(type(sortiePeerClaimedContainer) == "function",
    "the sortie claim check must be loaded")

local crate = {}
local solo = {}
local locker = {}
local otherCrate = {}

local function member(id, teamId, claimed, baseId, supplyParty)
    local reservations = claimed ~= nil and { containers = claimed } or nil
    return {
        id = id,
        awayTeamId = teamId,
        reservations = reservations,
        baseId = baseId,
        baseSupplyParty = supplyParty or nil,
    }
end

local leader = member("res-a", "team-1", { [crate] = "res-a", [solo] = "res-a" })
local peer = member("res-b", "team-1", { [crate] = "res-b" })
local controllers = {
    ["res-a"] = leader,
    ["res-b"] = peer,
}

-- The mission teammate's chosen crate is not free for this member.
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, crate) == true,
    "a mission partner's reserved container is claimed")
-- The member's own reservation is its own business; the per-controller check
-- owns that, and this one must not report a resident's own crate as claimed.
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, solo) == false,
    "a resident never blocks itself")
assert(sortiePeerClaimedContainer(controllers, "res-b", "team-1", nil, crate) == true,
    "asking as the other member still sees the partner's claim")
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, locker) == false,
    "an unreserved container stays free")

-- A member of another mission is not a partner, even in the same loaded world.
local stranger = member("res-c", "team-2", { [locker] = "res-c" })
controllers["res-c"] = stranger
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, locker) == false,
    "another mission's claim does not block this one")
assert(sortiePeerClaimedContainer(controllers, "res-c", "team-2", nil, crate) == false,
    "the second mission is also free of the first mission's claims")

-- A settlement supply pair has no mission id at all; the shared base is what
-- makes its two members one sortie.
local supplyLeader = member("sup-a", nil, { [otherCrate] = "sup-a" }, "base-1", true)
local supplyFollower = member("sup-b", nil, {}, "base-1", true)
controllers["sup-a"] = supplyLeader
controllers["sup-b"] = supplyFollower
assert(sortiePeerClaimedContainer(controllers, "sup-b", nil, "base-1", otherCrate) == true,
    "a supply pair's chosen container is claimed for its partner")
assert(sortiePeerClaimedContainer(controllers, "sup-a", nil, "base-1", otherCrate) == false,
    "a supply member never blocks itself")

-- The base id alone is not a sortie: an ordinary resident of the same base, or a
-- supply member of a different base, must not be treated as a partner.
local householder = member("base-res", nil, { [locker] = "base-res" }, "base-1", false)
controllers["base-res"] = householder
assert(sortiePeerClaimedContainer(controllers, "sup-b", nil, "base-1", locker) == false,
    "an ordinary resident of the same base is not a sortie partner")
local otherBase = member("sup-c", nil, { [locker] = "sup-c" }, "base-2", true)
controllers["sup-c"] = otherBase
assert(sortiePeerClaimedContainer(controllers, "sup-b", nil, "base-1", locker) == false,
    "another base's supply party does not block this one")

-- Missing inputs refuse to invent a claim.
assert(sortiePeerClaimedContainer(controllers, "res-a", nil, nil, crate) == false,
    "no mission and no base means no claim")
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, nil) == false,
    "no container means no claim")
assert(sortiePeerClaimedContainer(nil, "res-a", "team-1", "base-1", crate) == false,
    "no loaded controllers means no claim")

-- A partner without a reservation table holds nothing.
local fresh = { id = "res-d", awayTeamId = "team-1" }
controllers["res-d"] = fresh
assert(sortiePeerClaimedContainer({ ["res-d"] = fresh }, "res-a", "team-1", nil, crate) == false,
    "a partner with no reservations blocks nothing")

-- The check reads live reservations, so releasing the claim frees the container.
peer.reservations.containers[crate] = nil
assert(sortiePeerClaimedContainer(controllers, "res-a", "team-1", nil, crate) == false,
    "a released container becomes free again immediately")
supplyLeader.reservations.containers[otherCrate] = nil
assert(sortiePeerClaimedContainer(controllers, "sup-b", nil, "base-1", otherCrate) == false,
    "a released supply claim frees the container too")

print("Sortie shared claims PASS mission=true supplyPair=true self=false "
    .. "otherBase=false released=true")
