-- Planning uses real carried/stored instances, native recipe eligibility and
-- storage policy. A protected ingredient cannot silently enter a meal.
local function list(items)
    return {size=function() return #items end,
        get=function(_,index) return items[index+1] end,
        contains=function(_,wanted)
            for _,item in ipairs(items) do if item==wanted then return true end end
            return false
        end,
        add=function(_,item) items[#items+1]=item end}
end
ArrayList={new=function() return list({}) end}
local function item(kind,food,favorite)
    return {getFullType=function() return kind end,
        IsFood=function() return food end,
        isCookable=function() return food end,
        isCooked=function() return false end,
        isRotten=function() return false end,
        isPoison=function() return false end,
        getPoisonPower=function() return 0 end,
        isFavorite=function() return favorite==true end,
        getHungerChange=function() return food and -0.2 or 0 end}
end
local pan=item("Base.Pan",false,false)
local eggplant=item("Base.Eggplant",true,false)
local tomato=item("Base.Tomato",true,false)
local protected=item("Base.Carrots",true,false)
local favorite=item("Base.Broccoli",true,true)
local partial
local recipe={getUntranslatedName=function() return "Stir fry" end,
    isCookable=function() return true end,
    getItemsCanBeUse=function() return list({favorite,protected,eggplant,tomato}) end}
RecipeManager={getEvolvedRecipe=function(baseItem)
    if baseItem==pan or baseItem==partial then return list({recipe}) end
    return list({})
end}
local storeItems={pan,eggplant,tomato,protected,favorite}
local store={getItems=function() return list(storeItems) end}
KnoxBaseStorage={policies=function() return {{key="food",x=0,y=0,z=0}} end,
    resolvePolicy=function() return {container=store,square={}} end,
    filterAllowsItem=function(_,candidate) return candidate~=protected end}
KnoxSurvivorNeeds={isSafeFood=function(candidate) return candidate:IsFood() end}
local root={getItems=function() return list({}) end}
local square={getX=function() return 0 end,getY=function() return 0 end,
    getZ=function() return 0 end}
local character={getInventory=function() return root end,
    getCurrentSquare=function() return square end,
    getPrimaryHandItem=function() return nil end,
    getSecondaryHandItem=function() return nil end}
local result=KnoxBaseCooking.findRecipeMeal({},character)
assert(not KnoxBaseCooking.hasReadyMeal({}),
    "raw ingredients and protected food must not block a planned meal")
assert(result~=nil and result.recipe==recipe and #result.sources==3)
assert(result.sources[1].item==pan and result.sources[2].item==eggplant
    and result.sources[3].item==tomato,
    "recipe should select two permitted real ingredients and no protected item")
partial=item("Base.PanFriedVegetables",true,false)
partial.getExtraItems=function() return list({"Base.Eggplant"}) end
storeItems={partial,eggplant,tomato}
result=KnoxBaseCooking.findRecipeMeal({},character)
assert(result~=nil and #result.sources==2 and result.sources[2].item==tomato,
    "partly prepared meal should add a different ingredient")
print("Base recipe planning PASS real_items=true protected_skipped=true distinct_ingredients=true")
