-- Exercise native-action handoff: a pan and two distinct ingredients become
-- one cookable meal. A queued action that produces no meal must fail closed.
local function list(items)
    return {size=function() return #items end,
        get=function(_,index) return items[index+1] end,
        contains=function(_,wanted)
            for _,item in ipairs(items) do if item==wanted then return true end end
            return false
        end,
        isEmpty=function() return #items==0 end,
        add=function(_,item) items[#items+1]=item end,
        remove=function(_,wanted)
            for i,item in ipairs(items) do if item==wanted then table.remove(items,i);return end end
        end}
end
ArrayList={new=function() return list({}) end}
local inventoryItems={}
local inventory={getItems=function() return list(inventoryItems) end,
    contains=function(_,item)
        for _,value in ipairs(inventoryItems) do if item==value then return true end end
        return false
    end}
local function item(kind,food,extras)
    return {getFullType=function() return kind end,IsFood=function() return food end,
        getID=function() return kind end,
        isRotten=function() return false end,isPoison=function() return false end,
        getPoisonPower=function() return 0 end,isFavorite=function() return false end,
        getHungerChange=function() return food and -0.2 or 0 end,
        getExtraItems=function() return extras and list(extras) or nil end,
        isCookable=function() return food end,isCooked=function() return false end,
        isBurnt=function() return false end,getMinutesToCook=function() return 60 end,
        getMinutesToBurn=function() return 120 end}
end
local pan=item("Base.Pan",false)
local eggplant=item("Base.Eggplant",true)
local tomato=item("Base.Tomato",true)
inventoryItems={pan,eggplant,tomato}
local recipe={getUntranslatedName=function() return "Stir fry" end,
    isCookable=function() return true end,
    isResultItem=function(_,candidate)
        return candidate:getFullType()=="Base.PanFriedVegetables"
    end,
    getItemsCanBeUse=function(_,_,baseItem)
        local compatible={}
        for _,candidate in ipairs(inventoryItems) do
            if candidate~=baseItem and candidate:IsFood() then
                compatible[#compatible+1]=candidate
            end
        end
        return list(compatible)
    end}
RecipeManager={getEvolvedRecipe=function(baseItem)
    return list(baseItem==pan and {recipe} or {})
end}
KnoxBaseStorage={policies=function() return {} end}
local square={getX=function() return 0 end,getY=function() return 0 end,
    getZ=function() return 0 end,getObjects=function() return list({}) end}
local applianceItems={}
local applianceData={}
local applianceContainer={getItems=function() return list(applianceItems) end,
    contains=function(_,candidate) return list(applianceItems):contains(candidate) end,
    isPowered=function() return true end}
local appliance={getSquare=function() return square end,
    getObjectIndex=function() return 0 end,isBroken=function() return false end,
    getContainer=function() return applianceContainer end,
    getSprite=function() return {getName=function() return "test_stove" end} end,
    getModData=function() return applianceData end,Activated=function() return false end}
square.getObjects=function() return list({appliance}) end
getCell=function() return {getGridSquare=function() return square end} end
instanceof=function(_,class) return class=="IsoStove" end
KnoxBaseManager={containsSquare=function() return true end}
KnoxSurvivorNeeds={isSafeFood=function(candidate) return candidate:IsFood() end}
local character={getInventory=function() return inventory end,
    getCurrentSquare=function() return square end,
    getPrimaryHandItem=function() return nil end,
    getSecondaryHandItem=function() return nil end,
    getCharacterActions=function() return {isEmpty=function() return true end} end}
local queue={queue={},indexOf=function() return -1 end}
ISTimedActionQueue={queues={[character]=queue},
    getTimedActionQueue=function() return queue end,
    add=function(action)
        if not _G.suppressRecipeResult then
            local ingredients=action.baseItem:getExtraItems()
            local extras={}
            if ingredients~=nil then
                for i=0,ingredients:size()-1 do extras[#extras+1]=ingredients:get(i) end
            end
            extras[#extras+1]=action.usedItem:getFullType()
            local result=item("Base.PanFriedVegetables",true,extras)
            local items=inventory:getItems()
            items:remove(action.baseItem)
            items:remove(action.usedItem)
            items:add(result)
            action.baseItem=result
        end
        return queue
    end}
ISAddItemInRecipe={new=function(_,_,recipeArg,baseItem,used)
    return {baseItem=baseItem,usedItem=used,recipe=recipeArg}
end}
KnoxInventoryActions={queueTransfer=function(_,moved,source,destination)
    source:getItems():remove(moved)
    destination:getItems():add(moved)
    return {},"queued"
end}
local base={id="test",zones={}}
local target={x=0,y=0,z=0,objectIndex=0,spriteName="test_stove",mode="recipe"}
local plan=assert(KnoxBaseCooking.begin(base,target,character,"resident"))
local bridge={}
for tick=1,12 do
    local outcome,reason=KnoxBaseCooking.step(plan,character,base,bridge,tick)
    assert(outcome=="working",tostring(reason))
    if plan.item:getFullType()=="Base.PanFriedVegetables"
        and plan.item:getExtraItems():size()==2 then break end
end
assert(plan.item:getFullType()=="Base.PanFriedVegetables"
    and plan.item:getExtraItems():size()==2
    and (inventory:contains(plan.item) or list(applianceItems):contains(plan.item)),
    "two real ingredients should produce an owned native recipe result")
KnoxBaseCooking.cancel(plan,character)

inventoryItems={pan,eggplant,tomato}
suppressRecipeResult=true
local failed=assert(KnoxBaseCooking.begin(base,target,character,"resident"))
for tick=1,5 do
    local outcome,reason=KnoxBaseCooking.step(failed,character,base,bridge,tick)
    if outcome=="failed" then
        assert(reason=="recipe_action_no_result")
        break
    end
end
assert(failed.phase=="recipe_action","missing native result should stop at action receipt")
KnoxBaseCooking.cancel(failed,character)

-- A saved stove may still hold a raw ingredient marked by the old heating
-- rule. Recovery removes the actual item and releases the appliance marker.
inventoryItems={pan,tomato}
applianceItems={eggplant}
applianceData.KnoxCooking={baseId="test",itemId=tostring(eggplant:getID())}
local recovery=assert(KnoxBaseCooking.begin(base,target,character,"resident"))
assert(recovery.phase=="recover_raw","legacy raw ingredient needs a recovery path")
local outcome=KnoxBaseCooking.step(recovery,character,base,bridge,20)
assert(outcome=="working" and inventory:contains(eggplant)
    and list(applianceItems):isEmpty(),"raw ingredient transfers out of the stove")
local reason
outcome,reason=KnoxBaseCooking.step(recovery,character,base,bridge,21)
assert(outcome=="done" and reason=="raw_ingredient_recovered_to_inventory")
KnoxBaseCooking.cancel(recovery,character)
assert(applianceData.KnoxCooking==nil,"recovered ingredient clears the old mark")
print("Base recipe execution PASS two_ingredients=true native_result_owned=true missing_result_rejected=true legacy_raw_recovered=true")
