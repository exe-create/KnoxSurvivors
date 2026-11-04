-- A companion who has seen enough stops obeying. The rule reads the trust the
-- ledger already holds, so it is pure and can be driven here; the refusal line is
-- checked for the properties a line in a mouth must keep.
local Orders = assert(rawget(_G, "codecOrders"), "the order owner is loaded")
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")

local realPersistence = rawget(_G, "KnoxPersistence")
local rows = {}
KnoxPersistence = { getPlayerRelationship = function(_, survivorId) return rows[survivorId] end }

local function trustOf(value) rows.s1 = value == nil and nil or { trust = value } end

-- 1. An order follows the same ladder as everything else: a hostile person is
--    not asked, a wary one refuses, and a stranger's row that does not exist is
--    read as "no opinion" rather than as a refusal.
trustOf(nil)
assert(Orders.orderWillingness("s1", "p1") == nil, "no relationship row is no refusal")
rows.s1 = {}
assert(Orders.orderWillingness("s1", "p1") == nil, "a row with no trust is no refusal")
trustOf(8)
assert(Orders.orderWillingness("s1", "p1") == "hostile", "eight is hostile")
trustOf(10)
assert(Orders.orderWillingness("s1", "p1") == "hostile", "ten is still hostile")
trustOf(16)
assert(Orders.orderWillingness("s1", "p1") == "wary", "sixteen refuses but still speaks")
trustOf(25)
assert(Orders.orderWillingness("s1", "p1") == "wary", "twenty-five is the top of the refusal")
trustOf(26)
assert(Orders.orderWillingness("s1", "p1") == nil, "twenty-six takes orders again")
trustOf(90)
assert(Orders.orderWillingness("s1", "p1") == nil, "trust does not refuse")
trustOf("30")
assert(Orders.orderWillingness("s1", "p1") == nil, "a numeric string is not a low score")
assert(Orders.orderWillingness(nil, "p1") == nil, "no survivor is no verdict")
assert(Orders.orderWillingness("s1", nil) == nil, "no player is no verdict")
assert(Orders.orderWillingness("unknown", "p1") == nil, "an unknown survivor is no verdict")

-- 2. The two refusals are different: a hostile person has decided about you, a
--    wary one is still speaking, so the surface can say which happened.
assert(Orders.orderWillingness and true, "the gate is a function")
trustOf(9)
local hostile = Orders.orderWillingness("s1", "p1")
trustOf(20)
local wary = Orders.orderWillingness("s1", "p1")
assert(hostile ~= wary and hostile == "hostile" and wary == "wary", "the two refusals stay distinct")

KnoxPersistence = realPersistence

-- 3. The refusal is spoken in the first person, stays short, and never explains
--    the machinery or offers a bargain.
local lines = D.lines("order_refused_wary")
assert(type(lines) == "table" and #lines >= 2, "the order refusal bank exists")
local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end
for _, line in ipairs(lines) do
    assert(wordCount(line) <= 12, "an order refusal is short: " .. line)
    local lower = line:lower()
    assert(lower:find("trust", 1, true) == nil and lower:find("mod ", 1, true) == nil
        and lower:find("reputation", 1, true) == nil and lower:find("system", 1, true) == nil,
        "an order refusal never names the machinery: " .. line)
    assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
        or lower:find("me", 1, true) ~= nil, "an order refusal is first person: " .. line)
end

print("Order willingness PASS bands=true distinct=true lines=" .. tostring(#lines))
