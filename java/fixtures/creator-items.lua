-- Items a creator pack may hand over: the engine's own script manager answers,
-- so a modded item is as real as a vanilla one, and an id that no loaded script
-- provides is dropped rather than invented. The manager is stubbed here because
-- the harness has no engine; the code path under test is the real one.
local asked = {}
local known = {
    ["Base.Bandage"] = true,
    ["Base.Hammer"] = true,
    ["SomeMod.RatPoison"] = true,
}
getScriptManager = function()
    return {
        FindItem = function(self, fullType)
            asked[#asked + 1] = fullType
            if known[fullType] then return {} end
            return nil
        end,
    }
end

assert(Creator.itemKnown("Base.Hammer") == true, "a vanilla script is a real item")
assert(Creator.itemKnown("SomeMod.RatPoison") == true, "a modded script is a real item")
assert(Creator.itemKnown("Base.NoSuchThing") == false, "an absent script is not an item")
assert(Creator.itemKnown(nil) == false, "a missing id is not an item")
assert(Creator.itemKnown("") == false, "an empty id is not an item")

local askedBefore = #asked
assert(Creator.itemKnown("Base.Hammer") == true, "a cached answer is still true")
assert(#asked == askedBefore, "an answered id is cached instead of re-asked")

assert(#Creator.packItems("tools") == #Creator.PACKS[4].items,
    "the catalogue still declares the whole pack")
local tools = Creator.packItemsForPlacement("tools")
assert(#tools == 1 and tools[1] == "Base.Hammer",
    "placement keeps the real item and drops the one the engine cannot build")
assert(#Creator.packItems("none") == 0, "an empty pack stays empty")
local medical = Creator.packItemsForPlacement("medical")
assert(#medical == 1 and medical[1] == "Base.Bandage",
    "placement keeps the real item and drops the absent one rather than inventing it")
assert(#Creator.packItems("not_a_pack") == 0, "an unknown pack is empty")

print("Creator items PASS vanilla=true modded=true absent=false filtered=true cached=true")
