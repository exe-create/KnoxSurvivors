local oldP,oldWorld=KnoxPersistence,KnoxWorldPopulation
local intent={kind="find_water",phase="traveling",targetX=100,targetY=0,targetZ=0,targetKey="real-observed-water"}
local writes=0
local persistence={getSurvivorLifeIntent=function() return intent end,
 setSurvivorLifeIntent=function(id,value) writes=writes+1;intent=value;return true end,
 getSurvivorDuty=function() return {mode="autonomous"} end,getTravelGroupFor=function() return nil end}
local world=assert(intentTravelFactory(persistence))
KnoxPersistence,KnoxWorldPopulation=persistence,world
local activity=unloadedActivityFactory()
local state={virtualX=0,virtualY=0,virtualZ=0}
local moving=activity("independent",state,1,1)
assert(state.virtualX==40 and state.virtualY==0 and moving==1 and state.activity=="seeking_supplies",
 "real unloaded activity continues the captured water destination at finite travel speed")
activity("independent",state,2,3)
assert(state.virtualX==100 and intent.phase=="reassess" and writes==1 and state.departAtHours==5,
 "arrival commits reassessment through the existing intent owner")
assert(state.hunger==nil and state.inventory==nil,"travel cannot invent supplies or physiology")
intent={kind="find_food",phase="traveling",targetX=0,targetY=0,targetZ=1}
local before=state.virtualX
local handled=world.advanceIntentTravel("independent",state,3,4)
assert(not handled and state.virtualX==before,"coarse travel cannot teleport between floors")
intent={kind="scavenge",phase="traveling",targetX=200,targetY=0,targetZ=0}
handled=world.advanceIntentTravel("independent",state,4,4)
assert(not handled and state.virtualX==before,"zero elapsed time cannot move")
intent={kind="night_shelter",phase="arrived"}
persistence.clearSurvivorLifeIntent=function() intent=nil;return true end
local night={virtualX=10,virtualY=10,virtualZ=0}
handled=world.advanceIntentTravel("independent",night,24,26)
assert(handled and intent and night.virtualX==10,"arrived night shelter holds through the night")
handled=world.advanceIntentTravel("independent",night,26,32)
assert(handled and intent==nil and night.virtualX==10,"dawn releases shelter without inventing overnight travel")
intent=nil
persistence.getSurvivorDuty=function() return {mode="base",baseId="home"} end
persistence.getBase=function() return {home={minX=0,minY=0,width=100,height=100,z=0},tasks={}} end
local home={virtualX=50,virtualY=50,virtualZ=0}
moving=activity("resident",home,.001,6)
local distance=math.sqrt((home.virtualX-50)^2+(home.virtualY-50)^2)
assert(distance<=.040001 and moving<=.001,"base life walks gradually instead of selecting a new spawn tile")
KnoxPersistence,KnoxWorldPopulation=oldP,oldWorld
print("Offscreen purpose PASS real_destination=true gradual_home=true no_invented_loot=true")
