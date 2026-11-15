-- Production storage destination, controller trip/guard/receipt and queueDrop.
-- Native movement, floor container, transfer mutation and queue are boundaries.
local S,C,P=KnoxBaseStorage,KnoxAutonomyController,KnoxPersistence
local old={Cell=getCell,Container=ItemContainer,Queue=ISTimedActionQueue,Events=KnoxEventRuntime,
 Routing=KnoxTravelRouting,Manager=KnoxBaseManager,Find=S.findDepositTrip,
 Duty=P.getSurvivorDuty,Base=P.getBase,Affiliation=P.getSurvivorAffiliation,
 Looting=KnoxSurvivorLooting,Valid=ISInventoryTransferAction.isValid,
 Transfer=ISInventoryTransferAction.transferItem,Floor=ISInventoryTransferAction.getNotFullFloorSquare,
 Cancel=ISInventoryTransferAction.forceCancel}
local function list(items) return {size=function() return #items end,get=function(_,i) return items[i+1] end} end
local square,other,base,zone,item,inventory,controller,actor,q,mode,failures,finished,nativeCalls
local function logItem()
 return {getFullType=function() return "Base.Log" end,getType=function() return "Log" end,
  getDisplayCategory=function() return "Base" end,IsFood=function() return false end,
  getFluidContainer=function() return nil end,getContainer=function(self) return self.container end,
  getWorldItem=function(self) return self.world end,isFavorite=function() return false end}
end
local function tile(x)
 local s={x=x,world={}}
 function s:getX() return self.x end;function s:getY() return 0 end;function s:getZ() return 0 end
 function s:getWorldObjects() if self.unknown then error("unloaded world list") end;return list(self.world) end
 function s:isFree() return not self.blocked end
 function s:getFloor() error("terrain must never be used as inventory") end
 return s
end
ItemContainer={new=function(kind)
 assert(kind=="floor","native drop creates its ordinary floor destination")
 return {setExplored=function() end,isInCharacterInventory=function() return false end}
end}
KnoxEventRuntime=nil;KnoxTravelRouting=nil
S.findDepositTrip=function() return nil,"storage_full" end
P.getSurvivorDuty=function() return {mode="base",baseId="depot-home"} end
P.getBase=function() return base end
P.getSurvivorAffiliation=function() return {kind="faction",factionId="depot-faction"} end
KnoxBaseManager={containsSquare=function() return true end}
KnoxSurvivorLooting={cleanupPlan=function() return {{item=item,source=inventory,canDrop=true,value=1}} end}
ISInventoryTransferAction.isValid=function(action) return action.srcContainer:contains(action.item) end
ISInventoryTransferAction.getNotFullFloorSquare=function() if mode=="adjacent" then return other end;return square end
ISInventoryTransferAction.forceCancel=function() end
ISInventoryTransferAction.transferItem=function(action,cargo)
 nativeCalls=nativeCalls+1
 if mode=="free" then return end
 inventory.present=false;cargo.container=nil
 if mode=="lost" then return end
 local destination=mode=="wrong-world" and other or square
 local world={getItem=function() return cargo end,getSquare=function() return destination end}
 cargo.world=world;destination.world[#destination.world+1]=world
end
local function setup()
 square,other=tile(0),tile(1)
 zone={id="yard",type="log_processing",enabled=true,x1=0,x2=0,y1=0,y2=0,z=0,depotTargets={logs=60}}
 base={id="depot-home",home={minX=0,minY=0,width=1,height=1,z=0},zones={yard=zone}}
 inventory={present=true,contains=function(self,cargo) return self.present and cargo==item end,
  isInCharacterInventory=function() return true end}
 item=logItem();item.container=inventory
 actor={getInventory=function() return inventory end,getCurrentSquare=function() return square end,
  getCharacterActions=function() return nil end,getVehicle=function(self) return self.vehicle end,
  isEquipped=function() return false end,isHandItem=function() return false end}
 q={queue={},indexOf=function(self,a) for i,x in ipairs(self.queue) do if x==a then return i end end return -1 end,
  removeFromQueue=function(self,a) for i,x in ipairs(self.queue) do if x==a then table.remove(self.queue,i);return end end end}
 ISTimedActionQueue={queues={[actor]=q},clear=function() q.queue={};q.current=nil end,add=function(action)
  if mode=="refuse" or not action:isValid() then return nil end
  q.queue[#q.queue+1]=action;return q
 end}
 failures,finished,nativeCalls=0,0,0;mode="normal"
 getCell=function() return {getGridSquare=function(_,x) if x==0 then return square end;return other end} end
 controller=setmetatable({id="depot-worker",baseId=base.id,base=base,character=actor,
  reservations={items={}},bridge={moveNpc=function(_,id,target)
   assert(id=="depot-worker" and target==square,"existing movement owner receives exact yard tile")
   return "MOVE_STARTED"
  end,cancelNpcMove=function() end},recordFailure=function() failures=failures+1 end,
  finishDecision=function(self)
   finished=finished+1;self:releaseInventoryCleanup();self.pendingDepositTrip=nil
  end},C)
 return controller
end
local function begin()
 local destination=assert(S.depotStore(base,item))
 assert(destination.square==square and destination.zone==zone and destination.container==nil,
  "real yard square admits destination without fictitious floor inventory")
 assert(controller:beginDepositTrip(base,{{item=item,source=inventory,canDrop=true,value=1}},
  {mode="base",baseId=base.id},100),"existing deposit trip starts for real floor")
 assert(controller.pendingDepositTrip.depotSquare==square and inventory.present and nativeCalls==0,
  "trip admission moves no item")
 return controller.pendingDepositTrip
end
local function arrive()
 local trip=begin()
 assert(controller:completeDepotTrip(trip,110),"arrival queues existing native drop")
 assert(#q.queue==1 and controller.pendingCleanup.action==q.queue[1],"registered queue action owns placement")
 return q.queue[1]
end
setup();local a=arrive();a:transferItem(item);q.queue={}
assert(not inventory.present and item.world:getSquare()==square and nativeCalls==1,
 "native guarded drop moves exact carried item onto yard")
assert(controller:cleanupReceiptMatches(controller.pendingCleanup),"same-square real world receipt accepted")
controller:updateInventoryCleanup(120)
assert(failures==0 and finished==1 and controller.pendingCleanup==nil
 and controller.reservations.items[item]==nil,"successful receipt retires exact lease")
-- Failed/free/wrong-destination effects never finish as a successful placement.
for _,failureMode in ipairs({"free","lost","wrong-world"}) do
 setup();a=arrive();mode=failureMode;a:transferItem(item);q.queue={}
 assert(not controller:cleanupReceiptMatches(controller.pendingCleanup),"wrong/free/absent world receipt refused")
 controller:updateInventoryCleanup(120)
 assert(failures==1 and controller.nextCleanupAt==720 and controller.pendingCleanup==nil,
  "missing placement receipt enters existing retry and release path")
end
-- Changes between admission and native transfer preserve the carried item.
for _,change in ipairs({"removed","replacement","target","occupied","unknown","adjacent","order","vehicle","moved"}) do
 setup();a=arrive()
 if change=="removed" then base.zones={} elseif change=="replacement" then zone.id="other-yard"
 elseif change=="target" then
  -- A neighbour fills this category target without occupying our selected tile.
  zone.x2=1;zone.depotTargets.logs=1
  other.world={{getItem=function() return logItem() end}}
 elseif change=="occupied" then square.world={{getItem=function() return item end}}
 elseif change=="unknown" then square.unknown=true elseif change=="adjacent" then mode="adjacent"
 elseif change=="order" then controller.companionOrder="follow"
 elseif change=="vehicle" then actor.vehicle={}
 elseif change=="moved" then actor.getCurrentSquare=function() return other end end
 a:transferItem(item)
 assert(inventory.present and nativeCalls==0,"changed yard/target/native destination refuses before mutation: "..change)
 q.queue={};controller:releaseInventoryCleanup()
 assert(controller.reservations.items[item]==nil,"refusal releases exact item lease")
end
for _,change in ipairs({"removed","occupied","unknown","order"}) do
 setup();local trip=begin()
 if change=="removed" then base.zones={} elseif change=="occupied" then square.world={{getItem=function() return item end}}
 elseif change=="unknown" then square.unknown=true else controller.companionOrder="follow" end
 assert(not controller:completeDepotTrip(trip,110) and #q.queue==0 and inventory.present,
  "arrival rechecks yard before admission: "..change)
end
setup();square.unknown=true
local destination,reason=S.depotStore(base,item)
assert(destination==nil and reason=="stock_unreadable","unknown stock cannot admit a depot placement")
setup();square.blocked=true
assert(S.depotStore(base,item)==nil,"blocked square cannot admit placement")
setup();a=arrive();controller:releaseInventoryCleanup();a:transferItem(item)
assert(inventory.present and nativeCalls==0,"cancelled exact action cannot later mutate")
setup();local trip=begin();mode="refuse"
assert(not controller:completeDepotTrip(trip,110) and inventory.present
 and controller.reservations.items[item]==nil,"native queue refusal retains cargo and releases lease")
-- Base-supply delivery can also finish at the drop point, only on its receipt.
setup();trip=begin();trip.baseSupply=true;controller.pendingBaseSupplyDeposit={item=item}
local supplyFinished=0
controller.finishBaseSupplyRun=function(_,why) assert(why=="deposited");supplyFinished=supplyFinished+1 end
controller.clearLifeIntent=function() end
assert(controller:completeDepotTrip(trip,110));a=q.queue[1]
assert(not controller:recordBaseSupplyDepositReceipt(),"supply arrival is not delivery")
a:transferItem(item);q.queue={}
assert(controller:recordBaseSupplyDepositReceipt() and supplyFinished==1
 and controller.pendingBaseSupplyDeposit==nil,"actual depot drop closes existing supply run")
assert(controller:recordBaseSupplyDepositReceipt() and supplyFinished==1,"supply depot receipt is one-shot")
getCell=old.Cell;ItemContainer=old.Container;ISTimedActionQueue=old.Queue;KnoxEventRuntime=old.Events
KnoxTravelRouting=old.Routing;KnoxBaseManager=old.Manager;S.findDepositTrip=old.Find
P.getSurvivorDuty=old.Duty;P.getBase=old.Base;P.getSurvivorAffiliation=old.Affiliation
KnoxSurvivorLooting=old.Looting;ISInventoryTransferAction.isValid=old.Valid
ISInventoryTransferAction.transferItem=old.Transfer;ISInventoryTransferAction.getNotFullFloorSquare=old.Floor
ISInventoryTransferAction.forceCancel=old.Cancel
print("Depot placement D1 PASS nativeGameplay=false")
