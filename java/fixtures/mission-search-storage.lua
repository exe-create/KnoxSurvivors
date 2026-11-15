local E=assert(KnoxAwayTeamExecutor)
local oldInstance=instanceof
instanceof=function(item,kind) return kind=="InventoryContainer" and item.bag~=nil end
local bagWeight=10
local bag={getCapacityWeight=function() return bagWeight end,getMaxWeight=function() return 20 end}
local bagItem={bag=bag,getInventory=function() return bag end}
local inventory={getCapacityWeight=function() return 5 end,getMaxWeight=function() return 20 end,
    getItems=function() return {size=function() return 1 end,get=function() return bagItem end} end}
local actor={getInventory=function() return inventory end}
assert(not E.packFull(actor),"an actual half-empty bag keeps the mission going")
bagWeight=19
assert(E.packFull(actor),"full actual bag space ends collection without filling pockets too")
assert(E.ownsContainer(actor,bag) and not E.ownsContainer(actor,{}),"only actual carried bags qualify")
local received={getContainer=function() return bag end,getFullType=function() return "Base.CannedBeans" end}
bag.contains=function(_,item) return item==received end
local source={contains=function() return false end}
local haul=E.transferredItemTypes({container=source,items={{item=received},{item=received}}},actor)
assert(#haul==1 and haul[1]=="Base.CannedBeans","real bag receipt counts one physical item once")
local radius=80
local first=E.searchWave(radius,0)
assert(first.dx==0 and first.dy==0 and first.radius==16 and not first.fallback,"first bounded window searches the marked point")
local seen={}
for step=0,first.count-1 do
    local wave=E.searchWave(radius,step)
    assert(not wave.fallback and wave.radius==16,"the full preferred sweep precedes fallback")
    seen[tostring(wave.dx)..":"..tostring(wave.dy)]=true
end
local count=0 for _ in pairs(seen) do count=count+1 end
assert(count==first.count,"every search window is visited without duplicate windows")
assert(E.searchWave(radius,first.count).fallback,"observed area scarcity opens useful alternative supplies")
assert(not E.searchWave(radius,first.count*2).fallback,"the next sweep retries the requested supplies first")
instanceof=oldInstance
print("Mission search storage PASS realBags=true physicalReceipts=true boundedWindows=true fallback=true")
