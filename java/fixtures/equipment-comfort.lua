local E=assert(KnoxEquipmentIntelligence)
local oldNeeds=KnoxSurvivorNeeds
local hot,cold=false,false
KnoxSurvivorNeeds={thermalMoodle=function(_,kind) return (kind=="heat" and hot or kind=="cold" and cold) and 2 or 0 end}
local function clothing(name,loc,insulation,condition)
 return {getFullType=function() return name end,getBodyLocation=function() return loc end,
 IsClothing=function() return true end,IsInventoryContainer=function() return false end,
 IsWeapon=function() return false end,getConditionMax=function() return 10 end,
 getCondition=function() return condition end,getInsulation=function() return insulation end,
 getBiteDefense=function() return 0 end,getScratchDefense=function() return 0 end}
end
local heavy=clothing("Heavy coat","coat",1,10)
local light=clothing("Light jacket","coat",0,10)
local boots=clothing("Fresh shoes","shoes",0,10)
local broken=clothing("Worn shoes","shoes",0,0)
local candidates={light}
local worn={coat=heavy,shoes=broken}
local actor={getInventory=function() return {getItems=function() return {
 size=function() return #candidates end,get=function(_,index) return candidates[index+1] end} end} end,
 getPrimaryHandItem=function() return nil end,getWornItem=function(_,loc) return worn[loc] end}
assert(E.choose(actor)==nil, "comfortable survivor keeps the serviceable protective coat")
hot=true
local plan=E.choose(actor)
assert(plan and plan.kind=="wear" and plan.item==light, "native overheating makes a carried cooler garment preferable")
hot=false;worn.coat=light;candidates={heavy}
assert(E.choose(actor)==nil, "cooling off does not immediately re-equip the overheating coat")
cold=true
assert(E.choose(actor).item==heavy, "actual native cold restores the preference for insulation")
cold=false;candidates={boots}
plan=E.choose(actor)
assert(plan and plan.kind=="wear" and plan.item==boots, "a better carried pair replaces exhausted footwear")
assert(E.choose(actor,function() return false end)==nil, "claimed/unavailable clothing cannot be selected")
KnoxSurvivorNeeds=oldNeeds
print("Equipment comfort PASS nativeHeat=true carriedOnly=true footwearCondition=true claims=true")
