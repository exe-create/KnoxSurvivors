-- The same act should not get the same sentence from somebody the player has
-- hurt. This drives the real selection rule the conversation uses, so the bands
-- and the wording cannot drift apart.
local Orders = assert(rawget(_G, "codecOrders"), "companion owner missing")
assert(type(Orders.standingReaction) == "function", "standing rule missing")
assert(type(Orders.socialResponse) == "function", "response rule missing")
assert(type(Orders.witnessLadder) == "function", "ladder missing")

-- 1. Standing decides whether there is an answer at all, and it is the ladder's
--    answer rather than a second set of thresholds.
assert(Orders.standingReaction(60, "joke") == nil, "a friend answers normally")
assert(Orders.standingReaction(26, "joke") == nil, "just above the band is quiet")
assert(Orders.standingReaction(25, "joke") ~= nil, "the band edge answers")
assert(Orders.standingReaction(11, "joke") ~= nil, "still wary, still answering")
assert(Orders.standingReaction(10, "joke") == nil, "hostile refuses before words")
assert(Orders.standingReaction(nil, "joke") == nil, "no record is no answer")
for _, trust in ipairs({ 8, 10, 20, 25, 40, 90 }) do
    local band = Orders.witnessLadder(trust)
    local answered = Orders.standingReaction(trust, "joke") ~= nil
    assert(answered == (band == "wary"), "standing and the ladder disagree at " .. trust)
end

-- 2. Every banked line is short, spoken by the person, and outside the system.
local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end
local bank = Orders.STANDING_REACTIONS
local acts, lines = 0, 0
for act, list in pairs(bank) do
    acts = acts + 1
    assert(type(list) == "table" and #list >= 2, act .. " needs two answers")
    for _, line in ipairs(list) do
        lines = lines + 1
        assert(type(line) == "string" and line ~= "", act .. " has an empty line")
        assert(wordCount(line) <= 18, act .. " exceeds the sentence budget")
        local spoken = line:find("I ") or line:find(" me") or line:find(" my")
            or line:find("^We") or line:find("We ")
        assert(spoken ~= nil, act .. " line is not spoken: " .. line)
        local lowered = line:lower()
        for _, banned in ipairs({ "trust", "reputation", "witness", "score",
            "mod", "system", "relationship" }) do
            assert(not lowered:find(banned, 1, true), act .. " names the machinery")
        end
    end
end
assert(acts >= 5, "the bank covers the words people actually use")
assert(lines >= 10, "every covered act has alternatives")

-- 3. Selection rotates by meeting so the same sentence never lands twice, and
--    it passes the archetype's answer straight through when standing is fine.
local joke = bank.joke
assert(Orders.socialResponse(20, "joke", 1, "base") == joke[1], "first meeting")
assert(Orders.socialResponse(20, "joke", 2, "base") == joke[2], "second meeting")
assert(Orders.socialResponse(20, "joke", 3, "base") == joke[1], "rotates back")
assert(Orders.socialResponse(20, "joke", nil, "base") == joke[1], "no meeting count")
assert(Orders.socialResponse(60, "joke", 4, "base") == "base", "a friend is untouched")
assert(Orders.socialResponse(nil, "joke", 1, "base") == "base", "no record is untouched")

-- 4. Physical acts and unknown acts keep their own copy: this pass adds words,
--    it does not rewrite the acts that already have a strong answer.
assert(Orders.socialResponse(20, "slap", 1, "base") == "base", "physical stays")
assert(Orders.socialResponse(20, "threaten", 1, "base") == "base", "threat stays")
assert(Orders.socialResponse(20, "dance", 1, "base") == "base", "unknown stays")

-- 5. A hurt body answers before personality does, but after the relationship:
--    what the pair is matters more than what today cost the body.
assert(Orders.socialResponse(60, "joke", 1, "base", "none") == "base", "a well body answers normally")
assert(Orders.socialResponse(60, "joke", 1, "base", "mild") == "base", "mild pain keeps the word")
local hurtJoke = Orders.HURT_REACTIONS.joke
assert(Orders.socialResponse(60, "joke", 1, "base", "bad") == hurtJoke[1], "bad pain answers")
assert(Orders.socialResponse(60, "joke", 2, "base", "severe") == hurtJoke[2], "severe pain rotates")
assert(Orders.socialResponse(25, "joke", 1, "base", "severe") == joke[1],
    "standing outranks the body")
assert(Orders.socialResponse(60, "insult", 1, "base", "severe") == "base",
    "a wound does not soften an insult")
assert(Orders.socialResponse(60, "slap", 1, "base", "severe") == "base",
    "a wound does not soften a slap")
assert(Orders.socialResponse(60, "dance", 1, "base", "severe") == "base",
    "an unknown act stays untouched when hurt")

local hurtActs, hurtLines = 0, 0
for act, list in pairs(Orders.HURT_REACTIONS) do
    hurtActs = hurtActs + 1
    assert(#list >= 2, act .. " needs two answers for a hurt body")
    for _, line in ipairs(list) do
        hurtLines = hurtLines + 1
        assert(wordCount(line) <= 18, act .. " hurt line exceeds the budget")
        assert(line:find("I ") or line:find(" me") or line:find(" my")
            or line:find("We "), act .. " hurt line is not spoken: " .. line)
        assert(not line:lower():find("hurt", 1, true) or act ~= "compliment",
            "a compliment does not recite the injury")
    end
end
assert(hurtActs == 3, "hurt covers the gentle acts only")

print("Social standing PASS acts=" .. acts .. " lines=" .. lines
    .. " hurt_acts=" .. hurtActs .. " hurt_lines=" .. hurtLines
    .. " bands_agree=true precedence=true")
