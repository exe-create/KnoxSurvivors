-- Production person-surface close predicate and wrapper; native actors are doubles.
local Layout=codecPersonSurface
assert(type(Layout)=="table" and type(Layout.personSurfaceState)=="function" and
    type(Layout.bindPersonSurface)=="function","person-surface production functions are loaded")
local savedRuntime,savedPlayer,savedTime=KnoxSurvivorRuntime,getSpecificPlayer,getTimestampMs
local savedService,savedFeed=KnoxCompanionService,KnoxActivityFeed
local persistence=KnoxPersistence
local savedAlive=persistence.isSurvivorAlive
local now=0
getTimestampMs=function() return now end

local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z end}
end
local body
local function makeBody(x,y)
    body={dead=false,x=x or 1,y=y or 1,
        isDead=function(self) return self.dead end,
        getCurrentSquare=function(self) return square(self.x,self.y,0) end}
    return body
end
local player={dead=false,aiming=false,vehicle=nil,sees=true,
    isDead=function(self) return self.dead end,
    isAiming=function(self) return self.aiming end,
    getVehicle=function(self) return self.vehicle end,
    CanSee=function(self) return self.sees end,
    getCurrentSquare=function() return square(0,0,0) end}
getSpecificPlayer=function() return player end

local controller={playerConversation={player=player}}
local currentBody=body
KnoxSurvivorRuntime={getCharacter=function() return currentBody end,
    getController=function() return controller end}
persistence.isSurvivorAlive=function() return true end
local hostile=false
KnoxCompanionService={getPlayerId=function() return "player-1" end,
    isSociallyHostileToPlayer=function() return hostile end}
local notices={}
KnoxActivityFeed={event=function(text) notices[#notices+1]=text end}

makeBody(1,1)
currentBody=body
local function state(context)
    return Layout.personSurfaceState(player,"survivor-1",context or {})
end
local ok,why=state({body=body})
assert(ok==true,"a close, visible, non-hostile person keeps the surface open")

player.dead=true
ok,why=state({body=body})
assert(not ok and why=="player_gone","the player's death closes every person surface")
player.dead=false
player.aiming=true
ok,why=state({body=body})
assert(not ok and why=="player_aiming","aiming closes a person surface")
ok=state({body=body,checkAiming=false})
assert(ok==true,"a loot surface keeps the pack open while the player holds aim")
player.aiming=false
player.vehicle={}
ok,why=state({body=body})
assert(not ok and why=="player_in_vehicle","entering a vehicle closes a person surface")
player.vehicle=nil

ok,why=state({body={}})
assert(not ok and why=="survivor_gone","a different body is not the person the surface opened on")
body.dead=true
ok,why=state({body=body})
assert(not ok and why=="survivor_gone","the opened body's death closes the surface")
body.dead=false
persistence.isSurvivorAlive=function() return false end
ok,why=state({body=body})
assert(not ok and why=="survivor_gone","a persisted death closes the surface even before the body updates")
persistence.isSurvivorAlive=function() return true end

local lease=controller.playerConversation
ok=state({body=body,controller=controller,lease=lease})
assert(ok==true,"the owning controller and lease keep the surface open")
controller.playerConversation={player=player}
ok,why=state({body=body,controller=controller,lease=lease})
assert(not ok and why=="attention_lost","a replaced conversation lease closes the surface")
controller.playerConversation=lease
ok=state({body=body,controller=controller,lease=lease})
assert(ok==true)

hostile=true
ok,why=state({body=body})
assert(not ok and why=="hostile","hostility closes the surface")
hostile=false

body.x=10
body.y=0
ok,why=state({body=body})
assert(not ok and why=="too_far","ten tiles is beyond the five-tile close bound")
ok=state({body=body,maximumDistanceSquared=100})
assert(ok==true,"a surface may carry its own bound")
body.x=1
body.y=1

local windowState={}
player.sees=false
now=1000
ok=state({body=body,state=windowState,now=1000})
assert(ok==true and windowState.knoxPersonLostSightAt==1000,"a short loss of sight does not close the surface")
ok=state({body=body,state=windowState,now=2499})
assert(ok==true,"the sight grace lasts 1.5 seconds")
ok,why=state({body=body,state=windowState,now=2500})
assert(not ok and why=="lost_sight","the grace expires into a close")
player.sees=true
ok=state({body=body,state=windowState,now=2600})
assert(ok==true and windowState.knoxPersonLostSightAt==nil,"sight clears the grace stamp")

-- The card's world-bound read: an offscreen resident has no live body, so only
-- their persisted life is observable.
currentBody=nil
ok=state({checkDistance=false,requireSight=false})
assert(ok==true,"an offscreen person does not close the card by absence")
persistence.isSurvivorAlive=function() return false end
ok,why=state({checkDistance=false,requireSight=false})
assert(not ok and why=="survivor_gone","an offscreen death still closes the card")
persistence.isSurvivorAlive=function() return true end
currentBody=body

local closed=0
local window={playerNum=0,survivorId="survivor-1",knoxPersonBody=body,visible=true,
    isVisible=function(self) return self.visible end,
    update=function() end,
    close=function(self) self.visible=false;closed=closed+1 end}
Layout.bindPersonSurface(window,{})
assert(window.knoxPersonBound==true,"the wrapper is installed once")
local bound=window.knoxPersonBound
Layout.bindPersonSurface(window,{})
assert(window.knoxPersonBound==bound,"re-binding does not nest a second poll")
now=0
window:update()
assert(closed==0)
player.aiming=true
now=100
window:update()
assert(closed==0,"the close rule polls four times a second, not every frame")
now=400
window:update()
assert(closed==1 and window.knoxPersonCloseReason=="player_aiming")
assert(#notices==0,"aiming is visible in the world and earns no feed line")
player.aiming=false

local second={playerNum=0,survivorId="survivor-1",knoxPersonBody=body,visible=true,
    isVisible=function(self) return self.visible end,update=function() end,
    close=function(self) self.visible=false end}
Layout.bindPersonSurface(second,{})
hostile=true
now=0
second:update()
assert(second.knoxPersonCloseReason=="hostile")
assert(#notices==1 and notices[1]=="They've turned on you.",
    "hostility is not visible in the world, so it earns one line")
hostile=false

local callbackCalls=0
local third={playerNum=0,survivorId="survivor-1",knoxPersonBody=body,visible=true,
    isVisible=function(self) return self.visible end,update=function() end,
    close=function(self) self.visible=false end}
Layout.bindPersonSurface(third,{onClose=function(self,reason)
    callbackCalls=callbackCalls+1;self.visible=false;self.closedBy=reason end})
player.dead=true
now=1000
third:update()
assert(callbackCalls==1 and third.closedBy=="player_gone","an adopter can own the close")
player.dead=false

KnoxSurvivorRuntime,getSpecificPlayer,getTimestampMs=savedRuntime,savedPlayer,savedTime
KnoxCompanionService,KnoxActivityFeed=savedService,savedFeed
persistence.isSurvivorAlive=savedAlive
print("Person surface close PASS reasons=true lease=true sight_grace=true offscreen_read=true notice=true")