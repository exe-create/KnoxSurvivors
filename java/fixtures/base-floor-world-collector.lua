local collect=assert(KnoxBaseStorage.collectSquareLooseItems)
local function list(items) return {size=function() return #items end,get=function(_,i) return items[i+1] end} end
local one,two={},{}
local square={getWorldObjects=function() return list({{getItem=function() return one end},{getItem=function() return two end}}) end,
 getFloor=function() error("terrain is not inventory") end,getObjects=function() error("static objects are not loose inventory") end}
local items,known=collect(square)
assert(known and #items==2 and items[1]==one and items[2]==two,"native collector preserves exact inventory references")
items,known=collect({getWorldObjects=function() return list({}) end})
assert(known and #items==0,"empty native collection is readable")
for _,s in ipairs({{}, {getWorldObjects=function() error("unreadable") end},
 {getWorldObjects=function() return {} end},
 {getWorldObjects=function() return list({{}}) end},
 {getWorldObjects=function() return list({{getItem=function() return nil end}}) end},
 {getWorldObjects=function() return {size=function() return -1 end} end}}) do
 items,known=collect(s);assert(not known and #items==0,"invalid collection is unknown, never empty success")
end
items,known=collect(nil);assert(not known and #items==0,"unloaded square is unknown")
local prior=getCell
local base={id="seam",home={minX=0,minY=0,width=1,height=1,z=0}}
local zone={x1=0,y1=0,x2=0,y2=0,z=0}
getCell=function() return {getGridSquare=function(_,x,y,z)
 assert(x==0 and y==0 and z==0,"reader stays in its owned footprint")
 return {isFree=function() return true end}
end} end
assert(KnoxBaseStorage.walkFloorItems(base,function() error("unknown floor credited") end)==false,"unknown collection refuses strict floor read")
assert(KnoxBaseStorage.depotFreeTiles(base,zone)==0 and KnoxBaseStorage.depotFreeSquare(base,zone)==nil,"unknown world list never claims usable depot space")
getCell=function() return {getGridSquare=function() return square end} end
local seen={};assert(KnoxBaseStorage.walkFloorItems(base,function(item) seen[#seen+1]=item end),"valid floor walks through shared collector")
assert(#seen==2 and seen[1]==one and seen[2]==two,"consumer receives exact native-collected items")
getCell=prior
print("Floor collector PASS native_world_objects=true identity=true empty=true unreadable=true")
