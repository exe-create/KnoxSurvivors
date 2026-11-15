-- Floor hauling exercises the production organizer, controller and native-action
-- wrappers. The world, inventory and native transfer methods are doubles.
local O,S,C,P=KnoxBaseOrganize,KnoxBaseStorage,KnoxAutonomyController,KnoxPersistence
local old={Cell=getCell,Queue=ISTimedActionQueue,Adjacent=AdjacentFreeTileFinder,Manager=KnoxBaseManager,
 Duty=P.getSurvivorDuty,Preference=P.getWorkPreference,Capabilities=P.getSurvivorCapabilities,
 Schedule=KnoxBaseJobs.scheduleAssignment,Decide=KnoxSurvivorNeeds.decide,
 Grab=ISGrabItemAction.transferItem,Valid=ISInventoryTransferAction.isValid,
 Transfer=ISInventoryTransferAction.transferItem,Cancel=ISInventoryTransferAction.forceCancel,
 Floor=ISInventoryTransferAction.getNotFullFloorSquare,Container=ItemContainer,Events=KnoxEventRuntime,Clock=getTimestampMs,DepotStock=S.depotStock}
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end,
 contains=function(_,item) for _,v in ipairs(t) do if v==item then return true end end return false end} end
local function inventory()
 local c={items={}}
 function c:getItems() return list(self.items) end
 function c:contains(item) return list(self.items):contains(item) end
 function c:add(item) self.items[#self.items+1]=item;item.container=self;item.world=nil end
 function c:remove(item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i);item.container=nil;return end end end
 function c:hasRoomFor() return not self.full end;function c:isItemAllowed() return true end
 function c:isExistYet() return true end;function c:getType() return "crate" end
 function c:isInCharacterInventory() return true end
 return c
end
local square,source,dest,base,actor,controller,q,item,world,mode,readCount,nativeCalls,failures
local function setup()
 mode=nil;readCount=0;nativeCalls=0;failures=0
 source={x=0,y=0,world={},objects={}};dest={x=1,y=0,world={},objects={}}
 for _,s in ipairs({source,dest}) do
  function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return 0 end
  function s:getWorldObjects() return list(self.world) end;function s:getObjects() return list(self.objects) end
  function s:getRoomDef() return nil end;function s:isFree() return true end
  function s:isSomethingTo() return false end
 end
 square=source
 item={id=17,getID=function(self) return self.id end,getFullType=function() return "Base.Hammer" end,
 getType=function() return "Hammer" end,getDisplayCategory=function() return "Tool" end,
 isFavorite=function() return false end,IsFood=function() return false end,
 getFluidContainer=function() return nil end,getContainer=function(self) return self.container end,
 getWorldItem=function(self) return self.world end}
 world={square=source,getSquare=function(self) return self.square end,getItem=function() return item end}
 item.world=world;source.world={world}
 local carried,shelf=inventory(),inventory()
 local object={getObjectIndex=function() return 0 end,getContainerByIndex=function() return shelf end,
 getContainerCount=function() return 1 end,getSquare=function() return dest end}
 dest.objects={object}
 local policy={key="shelf",x=1,y=0,z=0,objectIndex=0,containerIndex=0,containerType="crate",storageRole="supplies"}
 base={id="floor-home",home={minX=0,minY=0,width=2,height=1,z=0},storage={shelf=policy},zones={}}
 getCell=function() return {getGridSquare=function(_,x,y,z) readCount=readCount+1;if y~=0 or z~=0 then return nil end;if x==0 then return source elseif x==1 then return dest end end} end
 actor={getInventory=function() return carried end,getCurrentSquare=function() return square end,
 getSquare=function() return square end,getCharacterActions=function() return {isEmpty=function() return true end} end,
 isDead=function() return false end,getVehicle=function() return nil end}
 q={queue={},indexOf=function(self,a) for i,v in ipairs(self.queue) do if v==a then return i end end return -1 end,
 removeFromQueue=function(self,a) local i=self:indexOf(a);if i~=-1 then table.remove(self.queue,i) end end}
 ISTimedActionQueue={queues={[actor]=q},getTimedActionQueue=function() return q end,
 add=function(a) if mode=="refuse" then return nil end;q.queue[#q.queue+1]=a;return q end,
 clear=function() q.queue={};q.current=nil end}
 controller=setmetatable({id="floor-worker",base=base,baseId=base.id,character=actor,
 reservations={items={},containers={}},state="IDLE",bridge={moveNpc=function(_,_,target) square=target;return "MOVE_STARTED" end,
 tickNpc=function() return "Succeeded" end,cancelNpcMove=function() end},
 recordFailure=function() failures=failures+1 end,finishDecision=function(self) self.state="IDLE" end},C)
 return carried,shelf,policy
end
AdjacentFreeTileFinder={Find=function(s) return s end};KnoxEventRuntime=nil
KnoxBaseManager={containsSquare=function() return true end}
P.getSurvivorDuty=function() return {mode="base",baseId="floor-home"} end
P.getWorkPreference=function() return "normal" end;P.getSurvivorCapabilities=function() return {} end
KnoxBaseJobs.scheduleAssignment=function() return "work" end
KnoxSurvivorNeeds.decide=function() return {kind="roam"} end
ISInventoryTransferAction.isValid=function(a) return a.srcContainer:contains(a.item) end
ISInventoryTransferAction.forceCancel=function() end
ISInventoryTransferAction.transferItem=function(a,cargo)
 nativeCalls=nativeCalls+1;if mode=="no-deposit" then return end
 a.srcContainer:remove(cargo);a.destContainer:add(cargo)
end
ISGrabItemAction.transferItem=function(a,obj)
 nativeCalls=nativeCalls+1;if mode=="no-grab" then return end
 local s=obj:getSquare();for i,v in ipairs(s.world) do if v==obj then table.remove(s.world,i);break end end
 obj.square=nil;a.destContainer:add(obj:getItem())
end
local function popTransfer()
 local a=assert(q.queue[1],"native action admitted");assert(a:isValid(),"guarded native action remains valid")
 if a.knoxWorldObject then a:transferItem(a.knoxWorldObject) else a:transferItem(a.item) end
 q.queue={};q.current=nil
end
local carried,shelf=setup()
assert(controller:beginBaseOrganize(0,true),"floor item starts actual organizer")
assert(controller.floorHaulScan.squares<=64 and controller.floorHaulScan.items<=400
 and controller.floorHaulScan.destinations<=12,"floor scan budgets")
controller:updateBaseOrganize(1);assert(#q.queue==1 and item.world==world,"admission does not pick up")
popTransfer();assert(carried:contains(item) and item.world==nil and world.square==nil,"native grab moves exact world item")
controller:updateBaseOrganize(2);assert(#q.queue==1,"verified pickup queues filtered shelf transfer")
popTransfer();controller:updateBaseOrganize(3)
assert(shelf:contains(item) and not carried:contains(item) and failures==0,"floor cargo reaches actual filtered shelf")
carried,shelf=setup();assert(controller:beginBaseOrganize(0,true));controller:updateBaseOrganize(1)
mode="no-grab";popTransfer();controller:updateBaseOrganize(2)
assert(not carried:contains(item) and item.world==world and failures==1,"missing grab receipt cannot deposit")
carried,shelf=setup();assert(controller:beginBaseOrganize(0,true));controller:updateBaseOrganize(1)
local stale=q.queue[1];controller:releaseBaseOrganize();stale:transferItem(world)
assert(item.world==world and not carried:contains(item),"cancelled grab cannot mutate")
for _,change in ipairs({"order","need","taken","full"}) do
 carried,shelf=setup();assert(controller:beginBaseOrganize(0,true));controller:updateBaseOrganize(1)
 local a=q.queue[1]
 if change=="order" then controller.companionOrder="follow"
 elseif change=="need" then KnoxSurvivorNeeds.decide=function() return {kind="eat"} end
 elseif change=="taken" then source.world={}
 else carried.full=true end
 assert(not a:isValid(),"changed condition revokes pickup "..change)
 if change~="full" then a:transferItem(world) end
 assert(item.world==world and not carried:contains(item),"revoked pickup preserves item "..change)
 controller:releaseBaseOrganize();KnoxSurvivorNeeds.decide=function() return {kind="roam"} end
end
carried,shelf=setup();local contents=inventory();local inside={id=42,IsFood=function() return false end,
 getFullType=function() return "Base.Hammer" end,getDisplayCategory=function() return "Tool" end}
contents:add(inside);item.IsInventoryContainer=function() return true end;item.getInventory=function() return contents end
carried.full=true
assert(not controller:beginBaseOrganize(0,true) and item.world==world and contents:contains(inside),
 "full carried inventory leaves loaded floor bag and contents intact")
local bagCount=0;local readBag=S.walkFloorItems(base,function(found) if found==inside then bagCount=bagCount+1 end end)
assert(readBag and bagCount==1,"nested floor bag contributes its item once")
item.getInventory=function() error("unreadable bag") end
assert(not S.walkFloorItems(base,function() end),"unreadable floor bag makes traversal unknown")
carried,shelf=setup();P.getWorkPreference=function() return "disabled" end
assert(not controller:beginBaseOrganize(0,true),"disabled hauling refuses admission")
P.getWorkPreference=function() return "normal" end
carried,shelf=setup();mode="refuse";assert(controller:beginBaseOrganize(0,true));controller:updateBaseOrganize(1)
assert(item.world==world and #q.queue==0,"native refusal leaves world item")
-- A carried floor bag keeps its real contents through the same native path.
carried,shelf=setup();local nestedInv=inventory();local nestedItem={id=44,IsFood=function() return false end,
 getFullType=function() return "Base.Hammer" end,getDisplayCategory=function() return "Tool" end}
nestedInv:add(nestedItem);item.IsInventoryContainer=function() return true end;item.getInventory=function() return nestedInv end
assert(controller:beginBaseOrganize(0,true),"loaded floor bag starts haul")
controller:updateBaseOrganize(1);popTransfer();controller:updateBaseOrganize(2);popTransfer();controller:updateBaseOrganize(3)
assert(shelf:contains(item) and nestedInv:contains(nestedItem),"native bag haul retains its exact contents")
-- Two cursor sweeps inspect twice the squares of one, with a fixed per-pass cap.
carried,shelf=setup();base.home.width=128;base.storage={};local scanReads=0
local blank={getWorldObjects=function() return list({}) end,getRoomDef=function() return nil end}
getCell=function() return {getGridSquare=function() scanReads=scanReads+1;return blank end} end
local _,cursor,firstScan=O.findFloor(base,actor,0)
local oneReads=scanReads;local _,_,secondScan=O.findFloor(base,actor,cursor)
local twoReads=scanReads
assert(firstScan.squares==64 and secondScan.squares==64 and twoReads==2*oneReads,
 "two bounded empty sweeps use linear square reads")
-- Dense native lists may be collected in full; candidate and destination work
-- has independent caps after collection.
local function denseItem(id, favorite)
 local cargo={id=id,favorite=favorite}
 function cargo:getID() return self.id end
 function cargo:getFullType() return "Base.Hammer" end
 function cargo:getType() return "Hammer" end
 function cargo:getDisplayCategory() return "Tool" end
 function cargo:isFavorite() return self.favorite end
 function cargo:IsFood() return false end
 function cargo:getFluidContainer() return nil end
 function cargo:getContainer() return self.container end
 function cargo:getWorldItem() return self.world end
 local obj={square=source,cargo=cargo}
 function obj:getSquare() return self.square end
 function obj:getItem() return self.cargo end
 cargo.world=obj
 return obj
end
carried,shelf=setup();source.world={}
for i=1,450 do source.world[i]=denseItem(i,true) end
local _,_,favoriteStats=O.findFloor(base,actor,0)
assert(favoriteStats.items==400 and favoriteStats.destinations==0,
 "dense favorites cap candidate inspection at 400")
carried,shelf=setup();source.world={}
for i=1,20 do source.world[i]=denseItem(i,false) end
local _,_,eligibleStats=O.findFloor(base,actor,0)
assert(eligibleStats.destinations==12,"dense eligible roots cap destination checks at 12")
-- Bulky cargo uses the real depot drop owner and a world-object receipt.
carried,shelf=setup();base.storage={};dest.objects={}
item.getFullType=function() return "Base.Log" end;item.getType=function() return "Log" end
base.zones={yard={id="yard",type="log_processing",enabled=true,x1=1,x2=1,y1=0,y2=0,z=0}}
ItemContainer={new=function() return {setExplored=function() end,isInCharacterInventory=function() return false end} end}
ISInventoryTransferAction.getNotFullFloorSquare=function() return dest end
ISInventoryTransferAction.transferItem=function(a,cargo)
 nativeCalls=nativeCalls+1;a.srcContainer:remove(cargo)
 local placed={square=dest,getSquare=function(self) return self.square end,getItem=function() return cargo end}
 cargo.world=placed;dest.world[#dest.world+1]=placed
end
local depotReads=0
S.depotStock=function(...) depotReads=depotReads+1;return old.DepotStock(...) end
assert(controller:beginBaseOrganize(0,true),"bulky floor cargo starts depot haul")
controller:updateBaseOrganize(1);popTransfer();controller:updateBaseOrganize(2)
if controller.pendingOrganize and controller.pendingOrganize.phase=="deposit_move" then
 controller:updateBaseOrganize(3);controller:updateBaseOrganize(4)
end
local drop=assert(q.queue[1],"native depot drop queued")
local beforeGuard=depotReads
assert(drop:isValid() and drop:isValid(),"repeated depot validity remains true")
local guardReads=depotReads-beforeGuard
popTransfer();controller:updateBaseOrganize(5)
assert(item.world and item.world:getSquare()==dest and not carried:contains(item) and failures==0,
 "depot drop creates exact world receipt")
S.depotStock=old.DepotStock
-- The existing two-second summary cache should serve repeated resident reads.
carried,shelf=setup();base.id="floor-cache-fixture";local ms=100
getTimestampMs=function() return ms end
local beforeReads=readCount;S.summarize(base);local firstReads=readCount-beforeReads
S.summarize(base);local secondReads=readCount-beforeReads-firstReads
assert(secondReads==0,"summary cache avoids another floor read within two seconds")
ms=2201;S.summarize(base);local thirdReads=readCount-beforeReads-firstReads-secondReads
assert(thirdReads>0,"summary refreshes after two seconds")
floorHaulReceipt="scanLimits=64/400/12 summaryFirst="..tostring(firstReads)
 .." summaryCached="..tostring(secondReads).." summaryRefresh="..tostring(thirdReads)
 .." depotGuardReads="..tostring(guardReads).." sweepN="..tostring(oneReads).." sweep2N="..tostring(twoReads)
 .." denseItems="..tostring(favoriteStats.items).." denseDestinations="..tostring(eligibleStats.destinations)
getCell=old.Cell;ISTimedActionQueue=old.Queue;AdjacentFreeTileFinder=old.Adjacent;KnoxBaseManager=old.Manager
P.getSurvivorDuty=old.Duty;P.getWorkPreference=old.Preference;P.getSurvivorCapabilities=old.Capabilities
KnoxBaseJobs.scheduleAssignment=old.Schedule;KnoxSurvivorNeeds.decide=old.Decide
ISGrabItemAction.transferItem=old.Grab;ISInventoryTransferAction.isValid=old.Valid
ISInventoryTransferAction.transferItem=old.Transfer;ISInventoryTransferAction.forceCancel=old.Cancel
ISInventoryTransferAction.getNotFullFloorSquare=old.Floor;ItemContainer=old.Container;KnoxEventRuntime=old.Events
getTimestampMs=old.Clock;S.depotStock=old.DepotStock
print("Floor haul PASS nativeGameplay=false")
