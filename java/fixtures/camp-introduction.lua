-- A camp is a place the player can walk into, so it introduces its faction on
-- approach instead of waiting for a member to be visible. The rule is pure
-- arithmetic over the camp's centre and the player's position.
local Camps = assert(rawget(_G, "KnoxFactionCamps"), "camp owner missing")
assert(type(Camps.introductionFor) == "function", "introductionFor missing")

local camp = { id = "camp-1", x = 100, y = 100, z = 0 }
local faction = { id = "faction-1", name = "Millers" }

assert(Camps.introductionFor(camp, faction, 100, 100) == "This camp belongs to Millers.",
    "standing in it names the owners")
assert(Camps.introductionFor(camp, faction, 111, 100) ~= nil,
    "eleven tiles still counts as arriving")
assert(Camps.introductionFor(camp, faction, 113, 100) == nil,
    "thirteen tiles is not an arrival")
assert(Camps.introductionFor(camp, faction, 200, 100) == nil, "distance is respected")

local known = { id = "faction-2", name = "Millers", formationNoticed = true }
assert(Camps.introductionFor(camp, known, 100, 100) == nil,
    "a faction already introduced is not introduced again")

assert(Camps.introductionFor(camp, { id = "faction-3", name = "" }, 100, 100) == nil,
    "an unnamed faction says nothing")
assert(Camps.introductionFor(camp, nil, 100, 100) == nil, "no faction, no line")
assert(Camps.introductionFor(nil, faction, 100, 100) == nil, "no camp, no line")
assert(Camps.introductionFor({ id = "camp-2" }, faction, 100, 100) == nil,
    "a camp with no centre says nothing")
assert(Camps.introductionFor(camp, faction, nil, 100) == nil,
    "an unknown player position says nothing")

print("camp_introduction: near=line far=nil known=quiet malformed=quiet")
