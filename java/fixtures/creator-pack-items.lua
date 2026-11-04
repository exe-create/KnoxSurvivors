-- The creator's pack is added through the starting-gear owner. The refusal paths
-- matter more than the success: a person promised bandages and given none must be
-- reported by item, not silently under-equipped.
local Gear = rawget(_G, "KnoxSurvivorStartingGear")
assert(Gear ~= nil, "starting gear owner missing")
assert(Gear.applyItems ~= nil, "applyItems missing")

local added, refusedType = {}, nil
local inventory = {
    AddItem = function(_, fullType)
        if fullType == refusedType then return nil end
        added[#added + 1] = fullType
        return { fullType = fullType }
    end,
}
local character = { getInventory = function() return inventory end }

local ok, result = Gear.applyItems(character, { "Base.Crisps", "Base.WaterBottle" })
assert(ok == true, "a real pack is added, got " .. tostring(result))
assert(#added == 2, "both items reached the inventory, got " .. tostring(#added))

added = {}
ok, result = Gear.applyItems(character, {})
assert(ok == true and result == "none", "an empty pack adds nothing and is not a failure")
assert(#added == 0, "an empty pack writes no item")

refusedType = "Base.Bandage"
added = {}
ok, result = Gear.applyItems(character, { "Base.Crisps", "Base.Bandage" })
assert(ok == false, "a refused item fails the pack")
assert(tostring(result) == "add_failed:Base.Bandage",
    "the refusal names the item, got " .. tostring(result))
assert(#added == 1, "the item before the refusal is still added, got " .. tostring(#added))
refusedType = nil

ok, result = Gear.applyItems(character, { "NotAnItem" })
assert(ok == false and result == "invalid_item", "a malformed id is refused before any write")
ok, result = Gear.applyItems(character, { "Base.Crisps" })
assert(ok == true, "a valid single item is added after the refusals")
ok, result = Gear.applyItems(nil, { "Base.Crisps" })
assert(ok == false and result == "inventory_unavailable", "no body means no pack")

print("creator_pack_items: added=2 empty=none refusal=named malformed=rejected")
