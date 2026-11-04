-- Direct heating leaves safe recipe ingredients available for later meal work.
local function food(unsafe)
    return {
        IsFood=function() return true end,
        isCookable=function() return true end,
        isCooked=function() return false end,
        isBurnt=function() return false end,
        isRotten=function() return false end,
        isPoison=function() return false end,
        getPoisonPower=function() return 0 end,
        isFavorite=function() return false end,
        getHungerChange=function() return -0.2 end,
        getMetalValue=function() return 0 end,
        getOnCooked=function() return "" end,
        isbDangerousUncooked=function() return unsafe end,
        getMinutesToCook=function() return 30 end,
        getMinutesToBurn=function() return 60 end,
        getCookingTime=function() return 0 end,
    }
end
assert(not KnoxBaseCooking.canCook(food(false)), "safe eggplant-like ingredient is reserved")
assert(KnoxBaseCooking.canCook(food(true)), "unsafe raw protein may be cooked directly")
local ingredient=food(false)
local contents={ingredient}
local stored={getItems=function()
    return {size=function() return #contents end,
        get=function(_,index) return contents[index+1] end}
end}
KnoxBaseStorage={policies=function() return {{key="food"}} end,
    resolvePolicy=function() return {container=stored} end,
    filterAllowsItem=function() return true end}
KnoxSurvivorNeeds={isSafeFood=function() return true end}
assert(not KnoxBaseCooking.hasReadyMeal({}),
    "raw cookable ingredients must not count as a prepared meal")
ingredient.isCooked=function() return true end
assert(KnoxBaseCooking.hasReadyMeal({}), "a cooked meal is ready")
ingredient.isFavorite=function() return true end
assert(not KnoxBaseCooking.hasReadyMeal({}),
    "a protected favorite meal is not communal food")
ingredient.isFavorite=function() return false end
assert(not KnoxBaseCooking.hasReadyMeal({},function() return false end),
    "another worker's reserved meal must not suppress cooking")
print("Base cooking policy PASS ingredient_reserved=true unsafe_raw_direct_cook=true ready_meal=true")
