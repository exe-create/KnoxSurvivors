-- A raid names its members, so a member of a live raid at this home is an
-- intruder even when the relationship between two survivors reads neutral. That
-- is the difference between a resident defending his base and treating an armed
-- looter as a stranger. The pure predicate comes first, then the set a threat
-- scan asks for.
local E = assert(KnoxEvents, "raid event owner is loaded")
local applies = assert(E.raidDefenceApplies, "the raid record answers who is hostile")
local intruders = assert(E.raidIntrudersForBase, "the home asks for the whole set")

-- The harness sandbox has no `next`, so emptiness is counted by hand.
local function isEmpty(set)
    for _ in pairs(set or {}) do return false end
    return true
end

local function raid(phase, memberIds, baseId, deadline)
    return {
        id = "raid-7", kind = "faction_raid", phase = phase, revision = 3,
        targetBaseId = baseId or "base-home", sourceBaseId = "base-north",
        sourceFactionId = "faction-north", targetFactionId = "player-faction",
        memberIds = memberIds or { "a", "b", "c" },
        dueAtHours = 10, deadlineHours = deadline or 40, lastChangedAtHours = 10,
    }
end

-- WHO IS HOSTILE BY RECORD.
assert(applies(raid("approaching"), "base-home", "a", 12) == true,
    "a party on the road to this home is already hostile to it")
assert(applies(raid("active"), "base-home", "b", 12) == true, "an assault is hostile")
assert(applies(raid("objective"), "base-home", "c", 12) == true, "a looter inside is hostile")
assert(applies(raid("withdrawing"), "base-home", "a", 12) == true,
    "a column still carrying stock out is still hostile")
assert(applies(raid("scheduled"), "base-home", "a", 12) == false,
    "a scheduled raid has not left yet")
assert(applies(raid("spawning"), "base-home", "a", 12) == false, "a spawning party is not there")
assert(applies(raid("completed"), "base-home", "a", 12) == false, "a finished raid is over")
assert(applies(raid("failed"), "base-home", "a", 12) == false, "a broken raid took nobody")
assert(applies(raid("active"), "base-other", "a", 12) == false,
    "a raid against another home is not this home's fight")
assert(applies(raid("active"), "base-home", "z", 12) == false, "a stranger named by nothing")
assert(applies(raid("active"), "base-home", "", 12) == false, "an empty id is not a member")
assert(applies(raid("active"), "base-home", nil, 12) == false, "no id, no claim")
assert(applies({ kind = "faction_entry", phase = "objective", targetBaseId = "base-home",
    memberIds = { "e" } }, "base-home", "e", 12) == false, "a faction entry is not a raid")
assert(applies(nil, "base-home", "a", 12) == false, "no record, no intruder")
assert(applies(raid("active"), nil, "a", 12) == false, "no home, no claim")
assert(applies(raid("active", { "a" }, "base-home", 20), "base-home", "a", 20) == true,
    "the deadline itself is still inside the raid")
assert(applies(raid("active", { "a" }, "base-home", 20), "base-home", "a", 21) == false,
    "past its deadline the record no longer claims anyone")
local undated = raid("active")
undated.deadlineHours = nil
assert(applies(undated, "base-home", "a", 900) == true,
    "a record with no deadline cannot expire by guesswork")

-- THE SET THE SCAN READS.
local persistence = KnoxPersistence
local saved = { getKnoxEventState = persistence.getKnoxEventState }
local state = { records = {}, cooldowns = {}, automatic = {} }
persistence.getKnoxEventState = function() return state end

state.records["raid-7"] = raid("objective")
state.records["raid-8"] = raid("active", { "d" }, "base-other")
state.records["raid-9"] = raid("completed")
state.records["entry-1"] = {
    id = "entry-1", kind = "faction_entry", phase = "objective",
    targetBaseId = "base-home", memberIds = { "e" },
}

local home = intruders("base-home", 12)
assert(home["a"] == true and home["b"] == true and home["c"] == true,
    "every member of the live raid is an intruder at the home")
assert(home["d"] == nil, "a raid against another base is not this home's fight")
assert(home["e"] == nil, "a faction entry is not a raid")
assert(home["q"] == nil, "an id nobody named is not an intruder")
local other = intruders("base-other", 12)
assert(other["d"] == true and other["a"] == nil, "each home gets its own intruders")
assert(isEmpty(intruders("base-nobody", 12)), "an unwatched base has no intruders")
assert(isEmpty(intruders(nil, 12)), "no home, no set")
state.records["raid-7"].phase = "withdrawing"
assert(intruders("base-home", 12)["a"] == true, "a column still leaving is still inside")
state.records["raid-7"].phase = "completed"
assert(isEmpty(intruders("base-home", 12)), "a finished raid leaves nobody to fight")

persistence.getKnoxEventState = saved.getKnoxEventState
assert(persistence.getKnoxEventState == saved.getKnoxEventState, "persistence reads are restored")
