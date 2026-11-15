local H,C=KnoxBaseHygiene,KnoxAutonomyController
local old={cell=getCell,adj=AdjacentFreeTileFinder,queue=ISTimedActionQueue,equip=ISEquipWeaponAction,
 clean=ISCleanBlood,fluid=Fluid,tag=ItemTag,z=ZomboidGlobals,instanceof=instanceof,
 schedule=KnoxBaseJobs.scheduleAssignment,decide=KnoxSurvivorNeeds.decide,
 basePerform=ISBaseTimedAction.perform,cancel=ISInventoryTransferAction.forceCancel,wash=ISWashYourself,parts=BloodBodyPartType}
Fluid={Bleach="bleach",CleaningLiquid="liquid"};ItemTag={CLEAN_STAINS="clean"}
ZomboidGlobals={CleanBloodBleachAmount=0.24999}
instanceof=function(item,class) return class=="HandWeapon" and item.both==true end
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local function inventory()
 local x={items={}}
 function x:getItems() return list(self.items) end
 function x:contains(item) for _,i in ipairs(self.items) do if i==item then return true end end return false end
 function x:isInCharacterInventory() return true end
 function x:containsEvalRecurse(f) return self:getFirstEvalRecurse(f)~=nil end
 function x:getFirstEvalRecurse(f)
  for _,i in ipairs(self.items) do
   if f(i) then return i end
   if i.bag then local v=i.bag:getFirstEvalRecurse(f);if v then return v end end
  end
 end
 function x:getFirstTagEvalRecurse(tag,f) return self:getFirstEvalRecurse(function(i) return i:hasTag(tag) and f(i) end) end
 function x:add(i) self.items[#self.items+1]=i;i.container=self end
 function x:remove(item) for n,i in ipairs(self.items) do if i==item then table.remove(self.items,n);item.container=nil;return end end end
 return x
end
local function item(inv,tool,fluid)
 local i={tool=tool,fluid=fluid}
 function i:getFluidContainer() return self.fluid end
 function i:hasTag() return self.tool==true end
 function i:isBroken() return self.broken==true end
 function i:getContainer() return self.container end
 function i:isTwoHandWeapon() return self.both==true end
 function i:IsInventoryContainer() return self.bag~=nil end
 function i:getInventory() return self.bag end
 inv:add(i);return i
end
local q,actor,square,reads,cleaned,mode,reentry
ISBaseTimedAction.perform=function(action) q:onCompleted(action) end
local function queueFor() return q end
ISTimedActionQueue={queues={},getTimedActionQueue=queueFor,
 add=function(a)
  q.queue[#q.queue+1]=a
  if reentry then reentry();reentry=nil end
  if mode=="refuse" then return nil end
  return q
 end,clear=function() q.queue={};q.current=nil end}
ISInventoryTransferAction.forceCancel=function() end
ISEquipWeaponAction={new=function(_,c,i,time,primary,both)
 return {character=c,isValid=function() return true end,forceCancel=function() end,
 perform=function(self) return ISBaseTimedAction.perform(self) end,
 complete=function() if primary then c.primary=i else c.secondary=i end;if both then c.secondary=i end;return true end}
end}
ISCleanBlood={new=function(_,c,s,cleaner)
 return {character=c,isValid=function() return true end,forceCancel=function() end,
 perform=function(self) return ISBaseTimedAction.perform(self) end,
 complete=function()
  if mode~="free" then cleaner.fluid.amount=cleaner.fluid.amount-ZomboidGlobals.CleanBloodBleachAmount end
  if mode~="stained" then s.dirty=false end
  cleaned=cleaned+1;return true
 end}
end}
AdjacentFreeTileFinder={Find=function(s) return s end}
KnoxBaseJobs.scheduleAssignment=function() return "work" end
KnoxSurvivorNeeds.decide=function() return {kind="roam"} end
local function setup(bagged)
 reads,cleaned,mode=0,0,nil
 square={dirty=true,x=0,y=0,z=0,name="kitchen"}
 function square:getX() return self.x end;function square:getY() return self.y end;function square:getZ() return self.z end
 function square:getRoomDef() if self.outdoors then return nil end;return {getName=function() return self.name end} end
 function square:haveBloodFloor() return self.dirty and not self.wall end
 function square:haveBloodWall() return self.dirty and self.wall end
 function square:haveGrimeFloor() return self.grime==true and self.dirty end
 function square:haveGrimeWall() return false end
 getCell=function() return {getGridSquare=function() reads=reads+1;if square.unloaded then return nil end;return square end} end
 local inv=inventory();local source=inv
 if bagged then source=inventory();local bag=item(inv,false);bag.bag=source end
 local fluid={amount=1,contains=function() return true end,getAmount=function(self) return self.amount end}
 local tool,cleaner=item(source,true),item(source,false,fluid)
 actor={inv=inv,getInventory=function(self) return self.inv end,getCurrentSquare=function() return square end,
 isDead=function() return false end,getCharacterActions=function() return {isEmpty=function() return true end} end,
 getPrimaryHandItem=function(self) return self.primary end,getSecondaryHandItem=function(self) return self.secondary end}
 q={queue={},indexOf=function(self,a) for n,x in ipairs(self.queue) do if a==x then return n end end return -1 end,
 removeFromQueue=function(self,a) local n=self:indexOf(a);if n~=-1 then table.remove(self.queue,n) end end}
 function q:onCompleted(action)
  self:removeFromQueue(action)
  if self.current==action then self.current=self.queue[1] end
 end
 ISTimedActionQueue.queues={[actor]=q}
 local c=setmetatable({id="cleaner",character=actor,base={id="home",home={minX=0,minY=0,width=1,height=1}},
 baseId="home",state="IDLE",reservations={items={}},bridge={moveNpc=function() return "MOVE_STARTED" end,
 tickNpc=function() return "Succeeded" end}},C)
 return c,tool,cleaner,fluid
end
local function nativeDone()
 local a=q.queue[1];assert(a,"action admitted")
 q.current=a
 if a.srcContainer then a:transferItem(a.item) else
  if a.isValid then assert(a:isValid(),"native validity precedes mutation") end
  assert(a:complete()~=false,"guarded native mutation admitted")
  if cleaned>0 then local before=cleaned;assert(a:complete()==false and cleaned==before,"duplicate clean cannot consume again") end
 end
 q:removeFromQueue(a);q.current=nil
end
local function run(c)
 for tick=1,12 do
  local outcome=H.stepSurface(c.pendingHygiene,actor,c.bridge,c.id,tick)
  if outcome~="working" then return outcome end
  if #q.queue>0 then nativeDone() end
 end
 error("surface lifecycle did not finish")
end
for _,wall in ipairs({false,true}) do
 local c,tool,cleaner,fluid=setup(true);square.wall=wall;square.grime=true;tool.both=wall
 assert(c:beginBaseSurfaceCleaning(0),"carried supplies admit surface chore")
 assert(cleaned==0 and square.dirty,"admission is not cleaning")
 assert(run(c)=="complete","native surface lifecycle completes")
 assert(not square.dirty and math.abs(fluid.amount-(1-0.24999))<0.0001,"cleaning consumes exact selected fluid")
 assert(tool:getContainer()==actor.inv and cleaner:getContainer()==actor.inv and actor.primary==tool and actor.secondary==(wall and tool or cleaner),
  "bag retrieval and both equipped hands precede cleaning")
 assert(H.stepSurface(c.pendingHygiene,actor,c.bridge,c.id,20)=="complete","completion receipt is idempotent")
 c:releaseBaseHygiene()
 assert(c.reservations.items[tool]==nil and c.reservations.items[cleaner]==nil,"leases released")
end
for _,failure in ipairs({"bathroom","empty","broken","reserved","clean","unloaded","automatic_disabled","recreation"}) do
 local c,tool,cleaner,fluid=setup(false)
 if failure=="bathroom" then square.name="bathroom"
 elseif failure=="empty" then fluid.amount=0
 elseif failure=="broken" then tool.broken=true
 elseif failure=="reserved" then c.reservations.items[tool]="other"
 elseif failure=="clean" then square.dirty=false
 elseif failure=="unloaded" then square.unloaded=true
 elseif failure=="automatic_disabled" then c.base.settings={automaticJobs=false}
 else KnoxBaseJobs.scheduleAssignment=function() return "recreation" end end
 assert(not c:beginBaseSurfaceCleaning(0),"refuses "..failure)
 assert(cleaned==0 and fluid.amount==(failure=="empty" and 0 or 1),"refusal never pays or cleans")
 KnoxBaseJobs.scheduleAssignment=function() return "work" end
end
for _,bad in ipairs({"free","stained"}) do
 local c=setup(false);mode=bad;assert(c:beginBaseSurfaceCleaning(0))
 assert(run(c)=="failed","partial native mutation is not success "..bad);c:releaseBaseHygiene()
end
local c,tool,cleaner=setup(false);assert(c:beginBaseSurfaceCleaning(0));H.stepSurface(c.pendingHygiene,actor,c.bridge,c.id,1)
local owned=q.queue[1];local foreign={forceCancel=function() error("foreign action canceled") end};q.queue[#q.queue+1]=foreign
c:releaseBaseHygiene();assert(#q.queue==1 and q.queue[1]==foreign and owned:complete()==false and square.dirty,"cancel preserves foreign work and stains")
c=setup(false);c.base.home.width=100;c.base.home.height=100;square.dirty=false
local _,cursor=H.findSurface(actor,c.base,0);assert(reads==64 and cursor==64,"surface scan budget and cursor")
for _,why in ipairs({"threat","order","need"}) do
 local c=setup(false);assert(c:beginBaseSurfaceCleaning(0));H.stepSurface(c.pendingHygiene,actor,c.bridge,c.id,1)
 local a=q.queue[1]
 if why=="threat" then c.combatTarget={}
 elseif why=="order" then c.companionOrder={}
 else KnoxSurvivorNeeds.decide=function() return {kind="rest"} end end
 assert(a:complete()==false and square.dirty and cleaned==0,"live preemption revokes commit "..why)
 c:releaseBaseHygiene();KnoxSurvivorNeeds.decide=function() return {kind="roam"} end
end
local reentered,rt,rc=setup(true)
assert(reentered:beginBaseSurfaceCleaning(0));local pending=reentered.pendingHygiene
reentry=function() reentered:releaseBaseHygiene() end
H.stepSurface(pending,actor,reentered.bridge,reentered.id,1)
assert(reentered.pendingHygiene==nil and #q.queue==0 and reentered.state=="IDLE"
 and rt:getContainer()~=actor.inv and square.dirty,"admission reentry retires exact transfer and leases")
local refused=setup(false);assert(refused:beginBaseSurfaceCleaning(0));mode="refuse"
assert(H.stepSurface(refused.pendingHygiene,actor,refused.bridge,refused.id,1)=="failed","native queue refusal is not success")
refused:releaseBaseHygiene();assert(#q.queue==0 and square.dirty,"refused action is retired")
for _,phase in ipairs({"equip","clean"}) do
 local current=setup(false);local fluid=actor.inv.items[2].fluid
 assert(current:beginBaseSurfaceCleaning(0))
 for tick=1,10 do
  H.stepSurface(current.pendingHygiene,actor,current.bridge,current.id,tick)
  if q.queue[1] and (phase=="equip" or actor.primary and actor.secondary) then break end
  if q.queue[1] then nativeDone() end
 end
 local action=q.queue[1];assert(action and action.perform,"current native action has drain path")
 q.current=action
 local foreign={forceCancel=function() error("foreign current successor canceled") end}
 q.queue[#q.queue+1]=foreign
 current:releaseBaseHygiene()
 assert(q.current==action,"mixed queue retains in-flight action until native drain")
 assert(action:complete()==false,"revoked current action cannot commit")
 action:perform()
 assert(q.current==foreign and #q.queue==1 and q.queue[1]==foreign,"canceled current action drains into preserved successor")
 assert(square.dirty and fluid.amount==1 and cleaned==0,"drain has no cleaning or fluid effect")
end
local unreadable=setup(false)
actor.inv.items[2].getFluidContainer=function() error("unreadable cleaner") end
assert(not unreadable:beginBaseSurfaceCleaning(0),"unreadable supply refuses without mutation")
-- The original body-wash path still queues its own action and verifies a real
-- body reading, independently of surface work.
c=setup(false)
local dirty=true
BloodBodyPartType={MAX={index=function() return 4 end},FromIndex=function(i) return i end}
actor.getHumanVisual=function() return {getBlood=function() return dirty and 1 or 0 end,getDirt=function() return 0 end} end
local water={getFluidAmount=function() return 10 end}
square.getObjects=function() return list({water}) end
ISWashYourself={new=function() return {complete=function() dirty=false;return true end} end}
local wash=assert(H.begin(actor,c.base,c.bridge,c.id,0))
assert(H.step(wash,actor,c.bridge,c.id,1)=="working","personal wash still admitted")
q.queue[1]:complete();q.queue={}
assert(H.step(wash,actor,c.bridge,c.id,2)=="complete","personal wash still has body receipt")
ISWashYourself,BloodBodyPartType=old.wash,old.parts
getCell,AdjacentFreeTileFinder,ISTimedActionQueue,ISEquipWeaponAction,ISCleanBlood=old.cell,old.adj,old.queue,old.equip,old.clean
Fluid,ItemTag,ZomboidGlobals,instanceof=old.fluid,old.tag,old.z,old.instanceof
KnoxBaseJobs.scheduleAssignment,KnoxSurvivorNeeds.decide=old.schedule,old.decide
ISInventoryTransferAction.forceCancel=old.cancel
ISBaseTimedAction.perform=old.basePerform
print("Surface cleaning PASS real_hygiene_owner=true bag_retrieval=true equipment=true fluid_receipt=true mixed_queue=true budget=64")
