local Parties = assert(KnoxGroupScavenge, "the group-scavenge owner is loaded")

local function pair(entries)
    local candidates = {}
    for index, entry in ipairs(entries) do
        candidates[index] = { id = entry.id or ("p" .. tostring(index)),
            role = entry.role }
    end
    return Parties.choosePair(candidates)
end

local leader, follower = pair({
    { id = "guard", role = "guard" },
    { id = "scout", role = "scavenger" },
})
assert(leader ~= nil and leader.role == "scavenger",
    "the scavenger leads the pair")
assert(follower ~= nil and follower.role == "guard",
    "the guard escorts the scavenger")

leader, follower = pair({
    { id = "cook", role = "cook" },
    { id = "medic", role = "medic" },
})
assert(leader.role == "cook" and follower.role == "medic",
    "a cook can lead a daylight pair when no better leader is available")

leader, follower = pair({
    { id = "auto", role = "auto" },
    { id = "runner", role = "runner" },
})
assert(leader.role == "runner" and follower.role == "auto",
    "a runner leads an automatic resident")

leader, follower = pair({
    { id = "b", role = "guard" },
    { id = "a", role = "guard" },
})
assert(leader.id == "a" and follower.id == "b",
    "equal roles resolve deterministically by id")

assert(Parties.choosePair({{ id = "only", role = "scavenger" }}) == nil,
    "one eligible resident cannot form a pair")
assert(Parties.choosePair({}) == nil, "an empty roster forms no pair")
assert(Parties.PAIR_SIZE == 2 and Parties.PAIR_MIN_MEMBERS == 3,
    "the existing two-person and three-member contract is unchanged")

print("Group scavenge roles PASS scavenger=leader guard=escort cook=fallback deterministic=true")
