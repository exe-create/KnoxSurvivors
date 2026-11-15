-- KS_BaseStorage cold-food classification. The installed InventoryItem
-- (zombie.inventory.InventoryItem) carries hasTag and IsRotten; isFrozen() and
-- isRotten() belong to zombie.inventory.types.Food. A plain item is therefore
-- never cold food, and the classification must not ask it for either method.
local S = assert(KnoxBaseStorage)
local priorNeeds = KnoxSurvivorNeeds
KnoxSurvivorNeeds = {
    isSafeFood = function() return false end,
    isWaterItem = function() return false end,
}
local priorTag = rawget(_G, "ItemTag")
_G.ItemTag = { PRESERVED_FOOD = "preserved_food" }

local function plain(fullType)
    return {
        getFullType = function() return fullType end,
        getDisplayCategory = function() return "Base" end,
        IsFood = function() return false end,
    }
end
local function food(frozen, rotten)
    return {
        getFullType = function() return "Base.Meat" end,
        getDisplayCategory = function() return "Food" end,
        IsFood = function() return true end,
        canAge = function() return true end,
        hasTag = function() return false end,
        isFrozen = function() return frozen end,
        isRotten = function() return rotten end,
    }
end

local cold, frozen = S.isColdPerishable(plain("Base.Log"))
assert(cold == false and frozen == nil, "a plain item is not cold food")
cold, frozen = S.isColdPerishable(nil)
assert(cold == false and frozen == nil, "a missing item is not cold food")
cold, frozen = S.isColdPerishable(food(true, false))
assert(cold == true and frozen == true, "a frozen perishable is cold food")
cold, frozen = S.isColdPerishable(food(false, false))
assert(cold == true and frozen == false, "a chilled perishable is cold food")
cold, frozen = S.isColdPerishable(food(true, true))
assert(cold == false, "rotten food is never cold food")

_G.ItemTag = priorTag
KnoxSurvivorNeeds = priorNeeds
