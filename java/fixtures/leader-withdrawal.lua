local P = KnoxPersistence
local C = codecWithdrawal

assert(type(C.withdrawalDue) == "function", "withdrawalDue must exist")

-- A lone survivor answers to nobody: it keeps the ordinary retreat rules and
-- never issues a group order for itself.
assert(C.withdrawalDue({ members = 1, dead = 0, healthFraction = 0.05 }) == false,
    "a solo survivor never orders a group withdrawal")

-- A death in the group is the real loss that justifies leaving.
assert(C.withdrawalDue({ members = 3, dead = 1 }) == true, "a death means withdraw")
assert(C.withdrawalDue({ members = 2, dead = 1, healthFraction = 1 }) == true)

-- A badly hurt leader responsible for others is the other real reason.
assert(C.withdrawalDue({ members = 2, healthFraction = 0.35 }) == true,
    "a badly hurt leader withdraws the group")
assert(C.withdrawalDue({ members = 2, healthFraction = 0.36 }) == false,
    "the threshold is not met just above it")
assert(C.withdrawalDue({ members = 4, dead = 0, healthFraction = 1 }) == false,
    "an unhurt leader with no losses keeps fighting")

-- Bad input never orders a retreat.
assert(C.withdrawalDue({}) == false)
assert(C.withdrawalDue({ members = 5 }) == false,
    "an unknown health value is not treated as wounded")
assert(C.withdrawalDue(nil) == false)
assert(C.withdrawalDue({ members = "3", dead = 0, healthFraction = "0.2" }) == true,
    "numeric strings are read as numbers")

-- The order record carries the directive, and it expires.
local a = assert(P.allocateWorldSurvivor({ x = 31, y = 41, z = 0, key = "wd-a", region = "WD" }, 10))
local b = assert(P.allocateWorldSurvivor({ x = 32, y = 41, z = 0, key = "wd-b", region = "WD" }, 10))
local group = assert(P.createTravelGroup({ a, b }, 10))
assert(group.leaderId == a, "the first member leads")

local order, detail = P.issueTravelGroupLeaderOrder(group.id, a, "withdraw", 12, 12.5)
assert(order ~= nil and detail == "issued", "a leader can order a withdrawal")
assert(order.kind == "withdraw" and order.leaderId == a)
assert(P.getTravelGroupLeaderOrder(group.id, 12.1).kind == "withdraw",
    "members read the live order")

assert(P.getTravelGroupLeaderOrder(group.id, 12.6) == nil,
    "a withdrawal order expires instead of lasting for ever")

local reissued = P.issueTravelGroupLeaderOrder(group.id, a, "withdraw", 13, 13.5)
assert(reissued ~= nil and reissued.kind == "withdraw",
    "the leader can order it again after it expires")

assert(select(2, P.issueTravelGroupLeaderOrder(group.id, b, "withdraw", 14, 14.5))
    == "invalid_leader_order", "a member cannot order the group to leave")
assert(select(2, P.issueTravelGroupLeaderOrder(group.id, a, "panic", 14, 14.5))
    == "invalid_leader_order", "an unknown directive is refused")
assert(P.clearTravelGroupLeaderOrder(group.id, b) == false,
    "a member cannot clear the leader's order")
assert(P.clearTravelGroupLeaderOrder(group.id, a) == true,
    "the leader can cancel its own order")
assert(P.getTravelGroupLeaderOrder(group.id, 14.1) == nil)

print("Leader withdrawal PASS solo=false loss=true health=true order=true expiry=true authority=true")
