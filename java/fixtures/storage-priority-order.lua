-- Storage autonomy, slice 2: the player's fill order is one stored key on the
-- record that already holds the shelf's filters, one read accessor, and one
-- write boundary. The walk that already exists consults it before distance.
local S = KnoxBaseStorage
assert(type(S) == "table" and type(S.setStoragePriority) == "function",
    "the storage owner exposes the fill-order write boundary")
assert(type(S.sortByPriorityAndDistance) == "function",
    "the existing walk exposes the ordering rule it really uses")

local refused = 0
local function refusal(value, why)
    local saved, reason = S.setStoragePriority(value, 7)
    assert(saved == nil and reason == why, "refused: " .. tostring(why))
    refused = refused + 1
end
refusal(nil, "unknown_storage")
refusal({}, "unknown_storage")
refusal({ key = "" }, "unknown_storage")

-- Order values are validated at the boundary, never coerced.
local shelf = { key = "shelf-1" }
for _, bad in ipairs({ 0, 10, 1.5 }) do
    local saved, reason = S.setStoragePriority(shelf, bad)
    assert(saved == nil and reason == "invalid_order", "an out-of-range order is refused")
    refused = refused + 1
end
local saved, reason = S.setStoragePriority(shelf, "2")
assert(saved == nil and reason == "invalid_order", "a numeric string is not an order")
refused = refused + 1

-- An unset shelf keeps today's tier, and the label says so.
assert(S.storageOrder(shelf) == nil and S.priorityRank(shelf) == 2
    and S.priorityLabel(shelf) == "Normal",
    "an unset shelf stays in today's normal tier")

assert(S.setStoragePriority(shelf, 1))
assert(S.storageOrder(shelf) == 1 and S.priorityRank(shelf) == 0
    and S.priorityLabel(shelf) == "Order 1",
    "the label names the order the player set")

-- The named level is still accepted and leaves one answer on the record.
assert(S.setStoragePriority(shelf, "low"))
assert(shelf.priorityOrder == nil and shelf.priority == "low" and S.priorityRank(shelf) == 3,
    "the named level clears the numeric order: one record, one answer")

assert(S.setStoragePriority(shelf, 1))
local cleared, clearedWhy = S.setStoragePriority(shelf, nil)
assert(cleared == shelf and clearedWhy == "cleared" and shelf.priorityOrder == nil
    and S.priorityRank(shelf) == 2, "clearing returns the shelf to today's order")

-- Ordering: the player's choice outranks distance; unset shelves keep the
-- distance order they had before this key existed.
local function shelfAt(key, x, order)
    local policy = { key = key, x = x, y = 0 }
    if order ~= nil then assert(S.setStoragePriority(policy, order)) end
    return policy
end
local origin = { getCurrentSquare = function()
    return {
        getX = function() return 0 end,
        getY = function() return 0 end,
        getZ = function() return 0 end,
    }
end }
local list = { shelfAt("near-unset", 1), shelfAt("far-first", 40, 1), shelfAt("near-second", 2, 2) }
S.sortByPriorityAndDistance(list, origin)
assert(list[1].key == "far-first", "the player's first-choice shelf is drawn from first")
assert(list[2].key == "near-second", "the second choice follows before any unset shelf")
assert(list[3].key == "near-unset", "unset shelves keep today's distance order behind the choices")

local legacy = { { key = "b-low", x = 1, priority = "low" },
    { key = "a-critical", x = 9, priority = "critical" },
    { key = "c-normal", x = 2 } }
S.sortByPriorityAndDistance(legacy, origin)
assert(legacy[1].key == "a-critical" and legacy[3].key == "b-low",
    "named levels still rank critical before normal before low")
assert(S.priorityRank({ key = "n", priorityOrder = 2 })
    == S.priorityRank({ key = "p", priority = "preferred" }),
    "a numeric order ranks with the named level it replaces")

storagePriorityReceipt = "refused=" .. tostring(refused)
    .. " ordered=3 cleared=1 legacyRank=2 unsetFallback=1 sorted=3"
storagePriorityPass = true
