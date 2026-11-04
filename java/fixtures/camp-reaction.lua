-- A camp that has warned you twice should stop being polite. The rule is pure:
-- distance, disposition, cooldown and how many times this camp has already
-- spoken all decide the line, so the ladder is provable without a body.
local Camps = assert(rawget(_G, "KnoxFactionCamps"), "camp owner missing")
assert(type(Camps.reactionFor) == "function", "reactionFor missing")

local faction = { id = "faction-1", name = "Millers", kind = "npc" }

local kind, text, count = Camps.reactionFor(faction, 9, "neutral", 100, 0, 0)
assert(kind == "warning", "a stranger three tiles in is warned, got " .. tostring(kind))
assert(type(text) == "string" and text ~= "", "a warning has words")
assert(count == 1, "the first warning is counted, got " .. tostring(count))

local kind2, text2, count2 = Camps.reactionFor(faction, 9, "neutral", 100, 0, count)
assert(kind2 == "warning" and text2 ~= text, "the second warning is not the first one again")
assert(count2 == 2, "the second warning is counted")

local kind3, text3, count3 = Camps.reactionFor(faction, 9, "neutral", 100, 0, count2)
assert(kind3 == "final", "the third time is final, got " .. tostring(kind3))
assert(type(text3) == "string" and text3 ~= text2, "the final line is its own line")
assert(count3 == 3, "the final line is counted")

local kind4, text4 = Camps.reactionFor(faction, 9, "neutral", 100, 0, 99)
assert(kind4 == "final" and text4 == text3, "the ladder stops at its last rung")
assert(Camps.reactionFor(faction, 9, "neutral", 100, 0, "8") ~= nil,
    "a numeric string counts as a number")

local friendly, friendlyText, friendlyCount = Camps.reactionFor(faction, 9, "allied", 100, 0, 2)
assert(friendly == "welcome", "an allied player is welcomed")
assert(friendlyText ~= text, "a welcome is not the warning in disguise")
assert(friendlyCount == nil, "a welcome never advances the ladder")
assert(Camps.reactionFor(faction, 9, "friendly", 100, 0, 0) == "welcome",
    "friendly counts as welcome")
assert(Camps.reactionFor(faction, 9, "hostile", 100, 0, 0) == nil,
    "a hostile camp is combat's business, not a greeting")
assert(Camps.reactionFor(faction, 81, "neutral", 100, 0, 0) == nil,
    "nine tiles away is not arriving")
assert(Camps.reactionFor(faction, 64, "neutral", 100, 0, 0) == "warning",
    "eight tiles is the edge of arriving")
assert(Camps.reactionFor(faction, 9, "neutral", 100, 124, 0) == nil,
    "a camp that already spoke stays quiet until its cooldown ends")
assert(Camps.reactionFor(faction, 9, "neutral", 124, 124, 0) == "warning",
    "the cooldown ends at its hour")
assert(Camps.reactionFor({ id = "player-faction-1", kind = "player", name = "Your Group" },
    9, "neutral", 100, 0, 0) == nil, "your own camp does not greet you like a stranger")
assert(Camps.reactionFor(nil, 9, "neutral", 100, 0, 0) == nil, "no faction, no reaction")
assert(Camps.reactionFor(faction, nil, "neutral", 100, 0, 0) == nil,
    "an unknown distance says nothing")

print("camp_reaction: warning=ladder final=third welcome=true hostile=silent edge=8 cooldown=24")
