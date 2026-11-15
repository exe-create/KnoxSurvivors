-- Activation candidate ordering and bounded selection (2026-11-05)
-- Drives the production comparator and cohort selector with plain candidates:
-- no cell, no body and no persistence record.
local P = assert(WorldPopulation, "the production population source is loaded")

local function candidate(id, priority, distance, mode)
    return { id = id, activationPriority = priority, distanceSquared = distance,
        mode = mode or "spawn" }
end
local function ids(selected)
    local out = {}
    for index, entry in ipairs(selected) do out[index] = entry.id end
    return table.concat(out, ",")
end

local restore = candidate("restore", 4, 4, "restore")
local spawn = candidate("spawn", 4, 4, "spawn")
assert(P.activationCandidateLess(restore, spawn),
    "a saved restore goes before a fresh spawn at the same priority and distance")
assert(not P.activationCandidateLess(spawn, restore),
    "the restore tie-break is one-way")
assert(P.activationCandidateLess(candidate("priority", 3, 999), restore),
    "priority still comes before distance")
assert(P.activationCandidateLess(candidate("near", 4, 4), candidate("far", 4, 9)),
    "nearer distance comes before farther distance")
assert(P.activationCandidateLess(candidate("a", 4, 4), candidate("b", 4, 4)),
    "the id keeps otherwise equal candidates deterministic")

local chosen = P.selectActivationCandidates({
    candidate("far", 4, 100), candidate("close", 4, 4), restore, candidate("near", 4, 9),
}, 2)
assert(ids(chosen) == "restore,close", "the budget keeps only the best two, restore first: "
    .. ids(chosen))
assert(#P.selectActivationCandidates({ spawn, restore }, 0) == 0,
    "a zero budget selects nothing")
assert(#P.selectActivationCandidates({ spawn, restore }, 10) == 2,
    "a budget above the candidate count selects every candidate")

-- A complete household can pull in a sibling outside the ranked prefix. The
-- ranked prefix is delta, alpha, bravo; charlie is fourth but belongs to alpha.
local alpha, charlie = candidate("alpha", 4, 5), candidate("charlie", 4, 7)
local groups = { alpha = { memberIds = { "alpha", "charlie" } } }
local cohort = P.selectActivationCandidates({
    candidate("delta", 4, 1), alpha, candidate("bravo", 4, 6), charlie,
}, 3, function(id) return groups[id] end)
assert(ids(cohort) == "delta,alpha,charlie",
    "a complete cohort may include a sibling outside the ranked prefix: " .. ids(cohort))

-- A missing sibling does not authorize a partial household. The selector falls
-- back to the candidate alone and never invents the missing body.
local missing = P.selectActivationCandidates({
    candidate("x", 4, 1), candidate("y", 4, 2),
}, 2, function(id)
    return id == "x" and { memberIds = { "x", "ghost" } } or nil
end)
assert(ids(missing) == "x,y",
    "an incomplete cohort falls back to the real candidate only: " .. ids(missing))

print("world_population_selection PASS order=true cap=true cohort=true missing=nil")
