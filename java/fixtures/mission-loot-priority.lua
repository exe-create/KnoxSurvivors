local L=assert(KnoxSurvivorLooting)
local oldNeeds,oldInstance=KnoxSurvivorNeeds,instanceof
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
KnoxSurvivorNeeds={isSafeFood=function(item) return item.food==true end,isWaterItem=function() return false end}
instanceof=function(item,kind) return kind=="Clothing" and item.clothing==true
    or kind=="InventoryContainer" and item.bag==true end
local function item(name,food,clothing)
    return {food=food,clothing=clothing,getFullType=function() return name end,
        getUnequippedWeight=function() return 1 end,isBroken=function() return false end,
        IsWeapon=function() return false end,IsInventoryContainer=function() return false end,
        isCanBandage=function() return false end,getAmmoType=function() return nil end}
end
local medicine=item("Base.Pills")
local food=item("Base.CannedBeans",true)
local shirt=item("Base.Shirt",false,true)
local decoration=item("Base.Ball")
local stock={food,decoration,shirt,medicine}
local source={getItems=function() return list(stock) end}
local bag={getItems=function() return list({}) end,getFreeCapacity=function() return 3 end}
local pack=item("Base.Bag")
pack.bag=true
pack.IsInventoryContainer=function() return true end
pack.getInventory=function() return bag end
local inventory={getItems=function() return list({pack}) end,getFreeCapacity=function() return 20 end}
local actor={getInventory=function() return inventory end}
local selected=L.plan(actor,source,4,true,{purpose="medicine"})
assert(#selected==1 and selected[1].item==medicine,"the preferred sweep takes only requested supplies")
selected=L.plan(actor,source,4,true,{purpose="medicine",allowFallback=true})
assert(#selected==3 and selected[1].item==medicine and selected[2].item==food
    and selected[3].item==shirt,"scarcity preserves requested priority, then food and clothing")
for _,entry in ipairs(selected) do
    assert(entry.destination==bag and entry.item~=decoration,"use real available bag space and refuse useless filler")
end
assert(#stock==4,"planning neither transfers nor creates any item")
KnoxSurvivorNeeds,instanceof=oldNeeds,oldInstance
print("Mission loot priority PASS requestedFirst=true usefulFallback=true bagCapacity=true noItemCreation=true")
