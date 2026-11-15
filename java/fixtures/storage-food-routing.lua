local Storage=KnoxBaseStorage
local oldItemTag=ItemTag
local oldNeeds=KnoxSurvivorNeeds
ItemTag={PRESERVED_FOOD="preserved_food"}
KnoxSurvivorNeeds={isWaterItem=function() return false end,isSafeFood=function() return false end}
local function preserved()
    return {hasTag=function(_,tag) return tag==ItemTag.PRESERVED_FOOD end}
end
local canned={storageFilterVersion=1,storageFilters={canned=true}}
local freshFood={storageFilterVersion=1,storageFilters={food=true}}
assert(Storage.acceptsDeposit(canned,preserved()),"preserved foods use the explicit canned group")
assert(not Storage.acceptsDeposit(freshFood,preserved()),"preserved foods do not leak into ordinary fresh food")
assert(Storage.matchesCategory(preserved(),"canned"),"the common canned filter matches preserved-food tags")
local function food(days,canAge)
    return {IsFood=function() return true end,
        getFullType=function() return "Base.TestFood" end,
        getOffAgeMax=function() return days end,
        canAge=canAge}
end
local fresh=food(7,function() return true end)
local stable=food(1000000000,function() return false end)
local perishable={storageFilterVersion=1,storageFilters={perishable=true}}
local pantry={storageFilterVersion=1,storageFilters={nonperishable=true}}
assert(Storage.acceptsDeposit(perishable,fresh) and not Storage.acceptsDeposit(pantry,fresh))
assert(Storage.acceptsDeposit(pantry,stable) and not Storage.acceptsDeposit(perishable,stable),
    "native never-rots food belongs in shelf-stable storage")
local nativeOnly=food(nil,function() return false end)
nativeOnly.getOffAgeMax=function() error("native canAge must own the result") end
assert(Storage.acceptsDeposit(pantry,nativeOnly),"false is a valid native boolean, not an unavailable API")
for _,days in ipairs({0,7,1000000000}) do
    local wrapped=food(days,nil)
    assert(Storage.acceptsDeposit(pantry,wrapped)==(days==1000000000))
    assert(Storage.acceptsDeposit(perishable,wrapped)==(days~=1000000000))
end
for _,item in ipairs({{}, {IsFood=function() return false end,getOffAgeMax=function() return 1000000000 end},
    food(0/0,nil),food(math.huge,nil),food(-math.huge,nil),food(nil,nil)}) do
    assert(not Storage.acceptsDeposit(pantry,item) and not Storage.acceptsDeposit(perishable,item),
        "unknown values and non-food must not become pantry supplies")
end

local oldPolicies,oldResolve,oldClassify=Storage.operationalPolicies,Storage.resolvePolicy,Storage.classifyItem
local oldFinder=AdjacentFreeTileFinder
local policies={}
local function square(x)
    return {getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end,
        isSomethingTo=function() return false end}
end
local origin=square(0)
local actor={getCurrentSquare=function() return origin end}
local base={id="storage-test"}
local container={hasRoomFor=function() return true end,isItemAllowed=function() return true end}
Storage.operationalPolicies=function() return policies end
Storage.classifyItem=function() return "food" end
Storage.resolvePolicy=function(policy)
    if policy.unloaded then return nil end
    return {policy=policy,square=square(policy.x),container=policy.container or container}
end
AdjacentFreeTileFinder={Find=function(tile) return tile end}
local function policy(key,filters,x)
    return {key=key,x=x or 1,y=0,z=0,storageFilterVersion=1,storageFilters=filters or {general=true}}
end
local function expect(reason,excluded)
    local target,result=Storage.findDepositTrip(base,actor,stable,excluded,100)
    assert(target==nil and result==reason,"expected "..reason..", got "..tostring(result))
    assert(type(Storage.depositBlockerText(result))=="string")
end
expect("no_reachable_storage",nil)
policies={policy("medicine",{medical=true})};expect("no_matching_storage",nil)
policies={policy("unloaded")};policies[1].unloaded=true;expect("storage_unavailable",nil)
policies={policy("full")};policies[1].container={hasRoomFor=function() return false end};expect("storage_full",nil)
policies={policy("reject")};policies[1].container={hasRoomFor=function() return true end,
    isItemAllowed=function() return false end};expect("storage_item_disallowed",nil)
policies={policy("blocked",nil,3)}
AdjacentFreeTileFinder.Find=function() return nil end
expect("storage_inaccessible",nil)
expect("storage_retry_cooldown",{blocked=101})
AdjacentFreeTileFinder.Find=function(tile) return tile end
policies={policy("full"),policy("pantry",{nonperishable=true},4),policy("fallback")}
policies[1].container={hasRoomFor=function() return false end}
policies[3].transientContainer=true
local target,reason=Storage.findDepositTrip(base,actor,stable,nil,100)
assert(target.policy.key=="pantry" and reason=="nearby_storage",
    "a usable filtered destination wins despite another full container")
policies={policy("full"),policy("reject")}
policies[1].container={hasRoomFor=function() return false end}
policies[2].container={hasRoomFor=function() return true end,isItemAllowed=function() return false end}
expect("storage_full",nil)
policies={policies[2],policies[1]};expect("storage_full",nil)
-- D3a: exercise the real candidate ordering with live native-boundary reads.
local coldReads, resolutions = 0, 0
local function appliance(fridge, freezer, power, kind)
    return {isFridge=function() coldReads=coldReads+1; return fridge end,
        isFreezer=function() coldReads=coldReads+1; return freezer end,
        isPowered=function() coldReads=coldReads+1; return power end,
        getType=function() return kind end,
        getSourceGrid=function() return {haveElectricity=function() return true end} end,
        hasRoomFor=function() return true end,isItemAllowed=function() return true end}
end
local shelf=appliance(false,false,false,"shelf")
local fridge=appliance(true,false,true,"crate") -- native property, not type name
local freezer=appliance(false,true,true,"freezer")
local foodItem=food(7,function() return true end)
foodItem.hasTag=function() return false end
foodItem.isRotten=function() return false end
foodItem.isFrozen=function() return false end
local function foodPolicy(key,x,box,order)
    local p=policy(key,{food=true},x); p.storageRole="food"; p.container=box; p.priorityOrder=order
    return p
end
Storage.resolvePolicy=function(p)
    resolutions=resolutions+1
    return {policy=p,square=square(p.x),container=p.container}
end
local function selected(item,pinned,excluded)
    local result
    if pinned then result=Storage.findNearbyDeposit(base,actor,item,pinned,excluded,100)
    else result=Storage.findDepositTrip(base,actor,item,excluded,100) end
    return result and result.policy.key
end
policies={foodPolicy("shelf",1,shelf),foodPolicy("fridge",2,fridge)}
assert(selected(foodItem)=="fridge","d3a: powered fridge wins same-priority food tie")
assert(resolutions==2 and coldReads==6,"d3a: one resolution and three cold reads per candidate")
fridge.isPowered=function() return false end
assert(selected(foodItem)=="shelf","unpowered fridge falls back to distance")
fridge.isPowered=function() return true end
policies[1].priorityOrder=1; policies[2].priorityOrder=2
assert(selected(foodItem)=="shelf","player priority precedes cold preference")
policies[1].priorityOrder=nil; policies[2].priorityOrder=nil
assert(selected(foodItem,"shelf")=="shelf","pinned destination remains authoritative")
assert(selected(foodItem,nil,{fridge=101})=="shelf","cooldown is retained")
fridge.hasRoomFor=function() return false end
assert(selected(foodItem)=="shelf","full fridge falls back")
fridge.hasRoomFor=function() return true end
local named=appliance(false,false,true,"fridge")
assert(Storage.coldContainer(named).fridge==false,"type name does not make cold")
assert(Storage.coldContainer(fridge).fridge==true,"native property marks fridge")
assert(Storage.coldContainer({isFridge=function() error("bad") end})==nil,"unknown cold accessors")
policies={foodPolicy("shelf",1,shelf),foodPolicy("freezer",2,freezer)}
assert(selected(foodItem)=="shelf","unfrozen food does not prefer freezer")
policies={foodPolicy("freezer",2,freezer)}
assert(selected(foodItem)=="freezer","sole explicit freezer remains eligible")
policies={foodPolicy("shelf",1,shelf),foodPolicy("freezer",2,freezer)}
foodItem.isFrozen=function() return true end
assert(selected(foodItem)=="freezer","frozen food prefers powered freezer")
policies={foodPolicy("fridge",1,fridge),foodPolicy("freezer",2,freezer)}
assert(selected(foodItem)=="freezer","frozen food prefers freezer over fridge")
policies={foodPolicy("shelf",1,shelf),foodPolicy("freezer",2,freezer)}
foodItem.isFrozen=function() return false end
foodItem.hasTag=function() return true end
assert(selected(foodItem)=="shelf","preserved food does not prefer cold")
foodItem.hasTag=function() return false end
foodItem.canAge=function() return false end
assert(selected(foodItem)=="shelf","non-aging food does not prefer cold")
policies={foodPolicy("shelf",1,shelf),foodPolicy("fridge",2,fridge)}
foodItem.canAge=function() return true end
fridge.isPowered=function() error("unavailable") end
assert(selected(foodItem)=="shelf","unreadable power falls back")
fridge.isPowered=function() return true end
foodItem.isRotten=function() return true end
assert(selected(foodItem)=="shelf","rotten food has no cold preference")
foodItem.isRotten=nil
assert(selected(foodItem)=="shelf","unknown rotten state has no cold preference")
foodItem.isRotten=function() return false end
fridge.getSourceGrid=function() return {haveElectricity=function() return false end} end
assert(selected(foodItem)=="shelf","unpowered source grid falls back")
foodItem.isFrozen=nil
assert(selected(foodItem)=="shelf","unknown frozen state falls back")
foodItem.isFrozen=function() return false end
local oldCell=getCell
getCell=function() return {} end
fridge.isPowered=function() return false end
local legacy=Storage.legacyFridgePolicy(policies[2])
assert(legacy and legacy.storageRole=="food","native property permits legacy fridge even without power")
getCell=oldCell
print("D3a counts: initial candidates=2 resolved=2 cold_type_power_reads=6")
Storage.operationalPolicies,Storage.resolvePolicy,Storage.classifyItem=oldPolicies,oldResolve,oldClassify
AdjacentFreeTileFinder=oldFinder
ItemTag=oldItemTag
KnoxSurvivorNeeds=oldNeeds
print("Storage food/routing PASS native_spoilage=true unknown_rejected=true blockers=true valid_fallback=true")
