-- A player who sees a warning on the plate and hears a refusal from an order
-- should be able to ask instead. The answer must come from the same ladder both
-- of those read, so nobody is told two different standings in one afternoon.
local Orders = assert(rawget(_G, "codecOrders"), "companion owner missing")
assert(type(Orders.answerStanding) == "function", "standing answer missing")
assert(type(Orders.witnessLadder) == "function", "ladder missing")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

-- 1. Every bank is speakable, short and outside the machinery.
local banks, lines = 0, 0
for name, list in pairs(Orders.STANDING_ANSWERS) do
    banks = banks + 1
    assert(type(list) == "table" and #list >= 2, name .. " needs two answers")
    for _, line in ipairs(list) do
        lines = lines + 1
        assert(type(line) == "string" and line ~= "", name .. " has an empty line")
        assert(wordCount(line) <= 18, name .. " exceeds the sentence budget")
        local spoken = line:find("I ") or line:find(" me") or line:find(" my")
            or line:find("We ") or line:find("we ")
        assert(spoken ~= nil, name .. " line is not spoken: " .. line)
        local lowered = line:lower()
        for _, banned in ipairs({ "trust", "reputation", "witness", "score",
            "mod", "system", "relationship" }) do
            assert(not lowered:find(banned, 1, true), name .. " names the machinery")
        end
    end
end
assert(banks == 3, "wary, steady and nothing yet are all answered")

-- 2. The answer follows the record the pair already has: a number and a count.
local realPersistence = rawget(_G, "KnoxPersistence")
local function ask(trust, meetings)
    KnoxPersistence = {
        getPlayerRelationship = function()
            return { trust = trust, meetings = meetings }
        end,
    }
    return Orders.answerStanding("s1", "p1")
end
assert(ask(20, 1) == Orders.STANDING_ANSWERS.wary[1], "a wary person says so")
assert(ask(20, 2) == Orders.STANDING_ANSWERS.wary[2], "and does not repeat it")
assert(ask(25, 1) == Orders.STANDING_ANSWERS.wary[1], "the band edge is wary")
assert(ask(26, 1) == Orders.STANDING_ANSWERS.steady[1], "one point above is steady")
assert(ask(60, 2) == Orders.STANDING_ANSWERS.steady[2], "steady rotates")
assert(ask(8, 1) == nil, "a hostile person is not answered at all")
assert(ask(10, 1) == nil, "the hostile edge is not answered")
assert(ask(11, 1) == Orders.STANDING_ANSWERS.wary[1], "eleven still answers")

-- 3. No record at all is answered honestly instead of guessed as friendly.
KnoxPersistence = { getPlayerRelationship = function() return nil end }
assert(Orders.answerStanding("s1", "p1") == Orders.STANDING_ANSWERS.stranger[1],
    "a stranger is not called a friend")
KnoxPersistence = { getPlayerRelationship = function() return { meetings = 3 } end }
assert(Orders.answerStanding("s1", "p1") == Orders.STANDING_ANSWERS.stranger[1],
    "a record without standing is still not a friend")
KnoxPersistence = realPersistence

-- 4. Asking never invents a meeting count: no count reads as the first answer.
assert(ask(20, nil) == Orders.STANDING_ANSWERS.wary[1], "no count is the first")
KnoxPersistence = realPersistence

print("Ask standing PASS banks=" .. banks .. " lines=" .. lines
    .. " bands_agree=true stranger_honest=true")
