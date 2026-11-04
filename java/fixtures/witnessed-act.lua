-- A mean act is remembered by the people the player brought along. The rule is
-- pure, so this fixture drives the real CompanionService.witnessReaction from
-- the source section rather than a copy of it.
local Companion = assert(rawget(_G, "codecWitness"), "the social owner is loaded")
local function reaction(...) return Companion.witnessReaction(...) end

-- 1. Mean acts carry, and the person it was said to is not the yardstick for
--    everybody else: a witness cares about forty percent as much, capped so a
--    vicious act does not alienate the whole party at once.
assert(reaction("insult", -12, 1) == -4, "an insult costs a witness 4, got " .. tostring(reaction("insult", -12, 1)))
assert(reaction("slap", -20, 1) == -6, "a slap is capped at 6")
assert(reaction("threaten", -15, 1) == -6, "a threat reaches the cap")
assert(reaction("slap", -60, 1) == -6, "the cap holds however brutal the act")

-- 2. Later witnesses care less, in a strict order, and never jump back up.
local first, second, third = reaction("insult", -12, 1), reaction("insult", -12, 2), reaction("insult", -12, 3)
assert(first == -4 and second == -2 and third == -1, "witnesses taper: " .. tostring(first) .. "," .. tostring(second) .. "," .. tostring(third))
assert(first < second and second < third, "the second and third witness never outrank the first")
assert(reaction("insult", -12, 4) == nil, "a fourth witness does not exist")

-- 3. Kindness carries nowhere. Only what would hurt is remembered, and an act
--    that changed nothing is not a memory.
assert(reaction("compliment", 5, 1) == nil, "a compliment is not witnessed")
assert(reaction("joke", 4, 1) == nil, "a joke is not witnessed")
assert(reaction("insult", 0, 1) == nil, "an act that moved nothing is not witnessed")
assert(reaction("insult", -3, 1) == -1, "the smallest saw cut still costs one point")
assert(reaction(nil, -12, 1) == nil, "no act name, no memory")
assert(reaction("insult", nil, 1) == nil, "no delta, no memory")
assert(reaction("insult", -12, 0) == nil, "witnesses are counted from one")

-- 4. The floor is real: a witness never loses nothing and never gains.
for _, act in ipairs({ "insult", "slap", "mock", "blame", "threaten" }) do
    for index = 1, 3 do
        local delta = reaction(act, -40, index)
        assert(delta ~= nil and delta < 0, "a witness always loses something: " .. act .. " #" .. index)
    end
end
