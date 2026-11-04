-- A plate should say who someone is to you before it says what they are doing.
-- The standing word is pure, and this drives the real order gate to prove the two
-- owners agree rather than each keeping its own threshold.
local N = assert(rawget(_G, "KnoxSurvivorNameplates"), "nameplate owner missing")
local Orders = assert(rawget(_G, "codecOrders"), "order owner missing")

-- 1. Only the refusal the plate can still warn about has words. A hostile person
--    is already drawn in red, so spending a line on them would say it twice.
assert(N.standingWord(nil) == nil, "ordinary standing says nothing")
assert(N.standingWord("wary") == "wary of you", "a refusing companion is named")
assert(N.standingWord("hostile") == nil, "hostility is carried by colour, not words")
assert(N.standingWord("something_new") == nil, "an unknown verdict says nothing")
assert(N.standingWord(3) == nil, "a number is not a verdict")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end
assert(wordCount(N.standingWord("wary")) <= 3, "the plate word stays short")

-- 2. The plate and the order gate agree, because the plate asks the gate. Three
--    bands, one reading: below the floor, refusing, and ordinary.
local realPersistence = rawget(_G, "KnoxPersistence")
local function atTrust(value)
    KnoxPersistence = { getPlayerRelationship = function() return { trust = value } end }
    return N.standingWord(Orders.orderWillingness("s1", "p1"))
end
assert(atTrust(8) == nil, "a hostile companion is not given a second label")
assert(atTrust(20) == "wary of you", "twenty is the warning the player needs")
assert(atTrust(25) == "wary of you", "the band edge warns")
assert(atTrust(26) == nil, "one point of trust and the plate is quiet again")
assert(atTrust(60) == nil, "a loyal companion is not labelled")
KnoxPersistence = realPersistence

-- 3. With no relationship at all the plate stays quiet rather than guessing.
KnoxPersistence = { getPlayerRelationship = function() return nil end }
assert(N.standingWord(Orders.orderWillingness("s1", "p1")) == nil, "no record is no warning")
KnoxPersistence = realPersistence

print("Nameplate standing PASS word=true colour_rule=true bands_agree=true")
