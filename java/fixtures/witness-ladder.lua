-- Cruelty in front of your own people has a floor. The ladder itself is pure and
-- comes from the social owner's source section; the enough-line is the bank a
-- person uses when they have decided. This checks the bands, not the wiring.
local Companion = assert(rawget(_G, "codecWitness"), "the social owner is loaded")
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")

-- 1. The bands match the ones Talk already uses, so one story is told twice.
assert(Companion.witnessLadder(0) == "hostile", "bottomed out is hostile")
assert(Companion.witnessLadder(10) == "hostile", "ten is still hostile")
assert(Companion.witnessLadder(11) == "wary", "eleven is wary, not hostile")
assert(Companion.witnessLadder(25) == "wary", "twenty-five is the top of wary")
assert(Companion.witnessLadder(26) == nil, "twenty-six is ordinary standing")
assert(Companion.witnessLadder(100) == nil, "trusted is not a warning")
assert(Companion.witnessLadder(nil) == nil, "no number, no verdict")
assert(Companion.witnessLadder("40") == nil, "a string is not a trust value")

-- 2. The verdict is a ladder: a witness who is merely wary still speaks to you,
--    and only the floor changes what the rest of the mod lets them do.
assert(Companion.witnessLadder(25) ~= Companion.witnessLadder(10),
    "wary and hostile are different decisions")

-- 3. The last line is short and plain, because a person leaving does not give a
--    speech, and it never explains the machinery.
local enough = D.lines("witness_enough")
assert(type(enough) == "table" and #enough >= 2, "the enough-line bank exists")
local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end
for _, line in ipairs(enough) do
    assert(wordCount(line) <= 14, "the last line stays short: " .. line)
    local lower = line:lower()
    assert(lower:find("trust", 1, true) == nil and lower:find("reputation", 1, true) == nil
        and lower:find("mod ", 1, true) == nil and lower:find("system", 1, true) == nil,
        "the machinery stays out of a goodbye: " .. line)
    assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
        or lower:find("me", 1, true) ~= nil, "a goodbye is first person: " .. line)
end

-- 4. An unknown voice still gets the line rather than silence.
local realPersistence = rawget(_G, "KnoxPersistence")
KnoxPersistence = nil
local shared = D.linesFor("s1", "witness_enough")
assert(shared == enough, "without an identity the enough-line is the shared bank")
KnoxPersistence = realPersistence

print("Witness ladder PASS bands=true distinct=true enough=" .. tostring(#enough))
