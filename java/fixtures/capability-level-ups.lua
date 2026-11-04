-- A survivor's first capture is a baseline, not a level-up, and every real gain
-- is named. The rule is pure, so both halves are provable without a body.
local Capabilities = assert(rawget(_G, "codecLevelUps"), "level-up owner missing")
assert(type(Capabilities.levelUps) == "function", "levelUps missing")
assert(type(Capabilities.levelUpText) == "function", "levelUpText missing")

-- A first capture carries the whole starting sheet: Doctor 7, Fitness 5 and the
-- rest are what the survivor already knew, and announcing them was the bug the
-- player saw as "+5 more".
local starting = { Cooking = { level = 3 }, Doctor = { level = 7 }, Fitness = { level = 5 } }
assert(#Capabilities.levelUps(nil, starting) == 0, "no previous snapshot is not a level-up")
assert(#Capabilities.levelUps({}, starting) == 0, "an empty previous snapshot is a baseline")

local before = { Cooking = { level = 3 }, Doctor = { level = 7 } }
local after = { Cooking = { level = 4 }, Doctor = { level = 7 } }
local ups = Capabilities.levelUps(before, after)
assert(#ups == 1, "one perk went up, got " .. tostring(#ups))
assert(ups[1].perk == "Cooking" and ups[1].level == 4, "a gain names the perk and its new level")
assert(Capabilities.levelUpText("Ava", ups) == "Ava reached Cooking 4",
    "the line names the person and the perk")

-- A perk the previous snapshot never held has no history to compare, so it is a
-- baseline entry rather than a gain.
local appeared = { Cooking = { level = 4 }, Axe = { level = 1 } }
assert(#Capabilities.levelUps(before, appeared) == 1, "a perk with no history is not a gain")

-- Every gain is named. The line never ends in "+N more".
local was, now = {}, {}
for index = 1, 8 do
    was["Perk" .. index] = { level = 1 }
    now["Perk" .. index] = { level = 2 }
end
local wide = Capabilities.levelUps(was, now)
assert(#wide == 8, "eight gains are eight gains, got " .. tostring(#wide))
local text = Capabilities.levelUpText("Ava", wide)
assert(type(text) == "string" and #text > 0, "eight gains still make a line")
assert(string.find(text, "more", 1, true) == nil, "the line never says '+N more'")
assert(string.find(text, "Perk8 2", 1, true) ~= nil, "the last gain is named in the line")

-- A drop is not a gain, and a missing level reads as zero.
assert(#Capabilities.levelUps({ Cooking = { level = 5 } }, { Cooking = { level = 2 } }) == 0,
    "a lower level is not a level-up")
assert(#Capabilities.levelUps({ Cooking = { level = 0 } }, { Cooking = { level = 1 } }) == 1,
    "zero to one is a gain")
assert(#Capabilities.levelUps({ Cooking = { level = "3" } }, { Cooking = { level = 4 } }) == 1,
    "a numeric string level still compares")

-- Deterministic order: the biggest gain leads, ties break by name.
local ordered = Capabilities.levelUps(
    { A = { level = 1 }, B = { level = 1 }, C = { level = 1 } },
    { A = { level = 2 }, B = { level = 5 }, C = { level = 3 } }
)
assert(#ordered == 3, "three gains, got " .. tostring(#ordered))
assert(ordered[1].perk == "B" and ordered[2].perk == "C" and ordered[3].perk == "A",
    "the biggest gain leads")
assert(Capabilities.levelUpText("Ava", {}) == nil, "no gains is no line")
assert(Capabilities.levelUpText(nil, ordered) ~= nil, "an unnamed speaker still gets a line")
