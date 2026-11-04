-- Paying a raid: the price is the objective's own count, and the answer is a
-- gate rather than a second outcome.
local E = codecRaidDemand

assert(type(E.raidDemandState) == "function", "raidDemandState must exist")

local function makeEvent(over)
    local event = {
        kind = "faction_raid",
        phase = "objective",
        memberIds = { "a", "b" },
        objective = {
            kind = "take_supplies", requiredItems = 3,
            startedAtHours = 100, deadlineHours = 102,
            receipts = {}, misses = {},
        },
    }
    for key, value in pairs(over or {}) do event[key] = value end
    return event
end

local state = E.raidDemandState(makeEvent(), 101)
assert(state.demandable == true and state.remaining == 3 and state.reason == "demanding")

local partly = makeEvent()
partly.objective.receipts["i1"] = {}
partly.objective.receipts["i2"] = {}
state = E.raidDemandState(partly, 101)
assert(state.demandable == true and state.remaining == 1, "paid items reduce the price")

local paid = makeEvent()
for index = 1, 3 do paid.objective.receipts["i" .. tostring(index)] = {} end
state = E.raidDemandState(paid, 101)
assert(state.demandable == false and state.remaining == 0 and state.reason == "already_paid")

state = E.raidDemandState(makeEvent(), 102)
assert(state.demandable == false and state.remaining == 3 and state.reason == "too_late",
    "the search window closes the offer")

state = E.raidDemandState(makeEvent({ phase = "approaching" }), 101)
assert(state.demandable == false and state.reason == "not_searching")
state = E.raidDemandState(makeEvent({ kind = "faction_entry" }), 101)
assert(state.demandable == false and state.reason == "not_a_raid")
state = E.raidDemandState(nil, 101)
assert(state.demandable == false and state.reason == "not_a_raid")
state = E.raidDemandState(makeEvent(), nil)
assert(state.demandable == false and state.reason == "invalid_objective")

print("Raid demand PASS price=true paid=true window=true phase=true guarded=true")
