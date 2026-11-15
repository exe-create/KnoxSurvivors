local oldPersistence, oldCell = KnoxPersistence, getCell
local savedRecord, failSave, owned = "old", false, false
local intent={kind="supplies",phase="traveling",targetX=200,targetY=10,targetZ=0}
local state={status="hibernated",activity="seeking_supplies",virtualX=10.25,virtualY=10,virtualZ=0}
local p={
 isSurvivorPresent=function() return true end,
 getSurvivorDuty=function() return owned and {mode=owned=="base" and "base" or "companion",ownerId="player",baseId="base"} or nil end,
 getBase=function() return {ownerKind="player",ownerId="player"} end,
 getSurvivorAffiliation=function() return owned and {kind="player",ownerId="player"} or nil end,
 getUnloadedSurvivalState=function() return state end,
 getRecord=function() return savedRecord end,
 setRecord=function(_,record) if failSave then return false end savedRecord=record return true end,
 getSurvivorLifeIntent=function() return intent end,
 setSurvivorLifeIntent=function() return true end,
}
KnoxPersistence=p
local travel=intentTravelFactory(p)
assert(travel.advanceIntentTravel("person",state,0,1),"advance actual virtual travel")
assert(state.virtualX==50.25 and state.virtualY==10,"advance retains fractional location")
local seen,standable,fire,occupied,loaded=false,true,false,false,true
local square={getX=function() return 50 end,getY=function() return 10 end,getZ=function() return 0 end,
 canStand=function() return standable end,haveFire=function() return fire end,
 getMovingObjects=function() return {size=function() return occupied and 1 or 0 end} end,
 isCanSee=function() return seen end}
local calls={}
getCell=function() return {getGridSquare=function(_,x,y,z)
 calls[#calls+1]=tostring(x)..","..tostring(y)..","..tostring(z)
 if loaded and x==50 and y==10 and z==0 then return square end
 -- A tempting nearby tile must never be consulted.
 return {canStand=function() return true end}
end} end
local relocated=0
local bridge={relocateNpcRecord=function(_,record,x,y,z)
 relocated=relocated+1
 assert(type(record)=="string" and record~="" and z==0,"record relocates on the same floor")
 assert((x==50 and y==10) or (x==51 and y==10),"record uses the virtual tile or the tile beside it")
 if x==51 then return "updated-nearby" end
 return "updated"
end}
local player={getPlayerNum=function() return 0 end}
local function candidate() calls={} return codecResidentPopulation.activationCandidate("person",bridge,{players={player}}) end
local result,reason=candidate()
assert(result and reason=="ready" and result.square==square and result.record=="updated"
 and result.x==50 and result.y==10 and #calls==2 and calls[1]=="50,10,0" and calls[2]=="50,10,0",
 "true_location: advanced virtual tile is the only restore tile")
assert(state.virtualX==50.25,"restore leaves fractional virtual position unchanged")
savedRecord="old"; standable=false
result,reason=candidate()
assert(not result and reason=="virtual_square_not_loaded_or_visible" and #calls==1 and relocated==1,
 "unsafe tile defers without neighbor search or save")
standable=true; fire=true
result=candidate(); assert(not result,"fire defers")
fire=false; occupied=true
result=candidate(); assert(not result,"occupied square defers")
occupied=false; loaded=false
-- Missing tile, rather than the tempting neighbor.
getCell=function() return {getGridSquare=function(_,x,y,z) calls[#calls+1]=tostring(x)..","..tostring(y)..","..tostring(z); return nil end} end
result,reason=candidate(); assert(not result and #calls==1,"unloaded tile defers")
loaded=true
getCell=function() return {getGridSquare=function(_,x,y,z) calls[#calls+1]=tostring(x)..","..tostring(y)..","..tostring(z); return square end} end
seen=true
result,reason=candidate(); assert(not result and #calls==1,"independent visible position defers")
owned=true
result,reason=candidate(); assert(result and reason=="ready","owned companion may restore visibly")
savedRecord="old"; owned="base"
result,reason=candidate(); assert(result and reason=="ready","owned base resident may restore visibly")
-- Owned, marker tile occupied: restore on the tile beside the marker, same
-- floor, instead of vanishing behind the marker forever.
savedRecord="old"; owned=true; seen=false; occupied=false; standable=true; fire=false; loaded=true
local blockedTile={getX=function() return 50 end,getY=function() return 10 end,getZ=function() return 0 end,
 canStand=function() return true end,haveFire=function() return false end,
 getMovingObjects=function() return {size=function() return 1 end} end,
 isCanSee=function() return false end}
local besideTile={getX=function() return 51 end,getY=function() return 10 end,getZ=function() return 0 end,
 canStand=function() return true end,haveFire=function() return false end,
 getMovingObjects=function() return {size=function() return 0 end} end,
 isCanSee=function() return false end}
getCell=function() return {getGridSquare=function(_,x,y,z)
 calls[#calls+1]=tostring(x)..","..tostring(y)..","..tostring(z)
 if x==50 and y==10 and z==0 then return blockedTile end
 if x==51 and y==10 and z==0 then return besideTile end
 return nil end} end
calls={}
result,reason=candidate()
assert(result and reason=="ready" and result.x==51 and result.y==10 and result.z==0
 and result.record=="updated-nearby" and savedRecord=="updated-nearby",
 "owned occupied marker restores on the tile beside it")
savedRecord="old"; failSave=true; seen=false
result,reason=candidate(); assert(not result and reason=="record_relocation_save_failed" and savedRecord=="old",
 "failed record save cannot produce a restore")
state.activity="event_reserved"; failSave=false
result,reason=candidate(); assert(not result and reason=="virtual_activity_blocked" and #calls==0,
 "blocked virtual activity never falls back to stale record")
KnoxPersistence, getCell = oldPersistence, oldCell
print("True location restore PASS exact_tile=true fractional_ledger=true native_center_unverified=true")
