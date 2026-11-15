local C,N,S,R=KnoxAutonomyController,KnoxSurvivorNeeds,KnoxGroupSupport,KnoxSurvivorRuntime
local oldQueue,oldEat,oldTag,oldStat,oldCell,oldBridge = ISTimedActionQueue,ISEatFoodAction,ItemTag,CharacterStat,getCell,KnoxJavaBridge
ItemTag={SMOKABLE="smoke"}; CharacterStat={HUNGER="hunger",THIRST="thirst",FATIGUE="fatigue",ENDURANCE="endurance",STRESS="stress",UNHAPPINESS="unhappy"}
getCell=function() return nil end; KnoxJavaBridge=nil
local square={x=0,getX=function(self) return self.x end,getY=function() return 0 end,getZ=function() return 0 end}
local function inventory()
 local inv={items={}}
 function inv:getItems() local t=self.items;return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
 function inv:contains(item) for _,x in ipairs(self.items) do if x==item then return true end end return false end
 function inv:remove(item) for i,x in ipairs(self.items) do if x==item then table.remove(self.items,i);item.container=nil;return end end end
 function inv:add(item) self.items[#self.items+1]=item;item.container=self end
 function inv:isInCharacterInventory() return true end
 return inv
end
local function cigarette()
 return {IsFood=function() return true end,hasTag=function(_,tag) return tag=="smoke" end,
  isFavorite=function() return false end,isBroken=function() return false end,
  IsInventoryContainer=function() return false end,getContainer=function(self) return self.container end,
  getFullType=function() return "Base.Cigarettes" end}
end
local function actor(inv)
 local stats={stress=0.5}
 local body={getNumPartsBleeding=function() return 0 end,getHealth=function() return 100 end,
  getBodyParts=function() return {size=function() return 0 end,get=function() end} end}
 local a={inv=inv,stats=stats,light=true,square=square}
 function a:getInventory() return self.inv end
 function a:getBodyDamage() return body end
 function a:getStats() return {get=function(_,k) if k=="endurance" then return 1 elseif k=="stress" then return stats.stress end return 0 end,
  getTimeSinceLastSmoke=function() return stats.stress*100 end} end
 function a:getTraits() return {contains=function(_,name) return name=="Smoker" end} end
 function a:isDead() return false end
 function a:isAsleep() return false end
 function a:isEquipped() return false end
 function a:getCurrentSquare() return self.square end
 function a:getCharacterActions() return nil end
 return a
end
local donorInv,recipientInv=inventory(),inventory()
local donor,recipient=actor(donorInv),actor(recipientInv)
local one,two=cigarette(),cigarette();donorInv:add(one);donorInv:add(two)
local queues={}; ISTimedActionQueue={queues=queues,add=function(action)
 local q=queues[action.character] or {queue={}};queues[action.character]=q;q.queue={action};return q end}
ISEatFoodAction={new=function(_,character,item)
 return {character=character,item=item,openFlame=false,carLighter=false,
  getRequiredItem=function() return character.light and {} or nil end,isValid=function() return true end,
  complete=function() character.inv:remove(item);character.stats.stress=0;return true end}
end}
local reservations={};local d=setmetatable({id="gap04-donor",character=donor,state="IDLE",groupMembers={recipient,donor},reservations=reservations},C)
local r=setmetatable({id="gap04-recipient",character=recipient,state="IDLE",groupMembers={donor,recipient},reservations=reservations},C)
for _,c in ipairs({d,r}) do
 function c:waitingForTransferActions() return false end
 function c:releaseTransferActions() end
 function c:recordFailure() end
 function c:finishDecision() self.state="IDLE" end
 function c:diag() end
end
R.register(d.id,d);R.register(r.id,r)
recipient.light=false
assert(not d:beginGroupSupport(0),"no ignition refuses offer")
recipient.light=true;d.nextGroupSupportAt=0;r.combatTarget={}
assert(not d:beginGroupSupport(0),"recipient danger refuses offer")
r.combatTarget=nil;d.nextGroupSupportAt=0
assert(d:beginGroupSupport(0),"offer queues before transfer loss")
local lostPlan=d.pendingGroupSupport
recipient.light=false
lostPlan.action:transferItem(lostPlan.item)
assert(not S.verify(lostPlan),"lost ignition before transfer refuses handoff")
recipient.light=true
donorInv:remove(lostPlan.item)
lostPlan.action:transferItem(lostPlan.item)
queues[donor].queue={}
assert(not d:completeGroupSupport(1) and r.pendingSelfCare==nil,"lost item has no receipt or smoking action")
donorInv:add(lostPlan.item);d.nextGroupSupportAt=0
assert(d:beginGroupSupport(2),"willing group member accepts spare")
local plan=d.pendingGroupSupport;local transfer=assert(plan.action)
assert(not S.verify(plan),"queued offer does not fabricate transfer")
r.pendingThreatAwareness={}
transfer:transferItem(plan.item)
assert(not S.verify(plan),"danger before transfer blocks handoff")
r.pendingThreatAwareness=nil
transfer:transferItem(plan.item)
assert(S.verify(plan),"physical transfer is receipted")
queues[donor].queue={}
donor.square={getX=function() return 50 end,getY=function() return 0 end,getZ=function() return 0 end}
assert(d:completeGroupSupport(1),"receipted gift completes even after donor leaves")
local smoke=assert(r.pendingSelfCare and r.pendingSelfCare.action,"recipient queues native smoke")
assert(smoke:isValid(),"recipient may smoke after donor leaves")
r.combatTarget={}
assert(not smoke:isValid() and smoke:complete()==false,"recipient danger cancels consumption")
r.combatTarget=nil
assert(smoke:complete() and N.verify(recipient,r.selfCareIntent),"native consumption and calm receipt complete")
assert(not smoke:complete(),"smoke consumption cannot repeat")
R.unregister(d.id,d);R.unregister(r.id,r)
ISTimedActionQueue,ISEatFoodAction,ItemTag,CharacterStat,getCell,KnoxJavaBridge=oldQueue,oldEat,oldTag,oldStat,oldCell,oldBridge
print("GAP04 cigarette offer PASS receipt=true refusal=true safety=true consumption=true")
