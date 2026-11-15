local P=assert(KnoxCombatPositioning)
local function square(x,y,room,blocked)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return 0 end,
        getRoom=function() return room end,isBlockedTo=function() return blocked==true end,
        isHoppableTo=function() return false end,canStand=function() return true end}
end
local inside,outside=square(0,0,"home",true),square(1,0,nil,false)
assert(P.blockedEdge(inside,outside),"intact window edge is not an attack lane")
assert(not P.blockedEdge(inside,square(3,0,nil,false)),"distant target is not a local edge")
assert(P.keepMeleeTarget(4,2,2),"keep a committed melee opponent at equal priority")
assert(not P.keepMeleeTarget(4,2,3),"an emergency opponent may interrupt")
assert(not P.keepMeleeTarget(5,2,2),"out of melee reach retains ordinary arbitration")
assert(P.barrierPolicy(2)=="exit" and P.barrierPolicy(3)=="hold","crowd holds inside")
local C={}
P.install(C,{canOpen=function() return false end})
local targetSquare=outside
local target={getCurrentSquare=function() return targetSquare end,isDead=function() return false end}
local controller=setmetatable({id="fixture",combatTarget=target,character={
    getCurrentSquare=function() return square(0,0,"home",false) end},
    combatBarrier={target=target,mode="hold"},cancels=0,attacks=0},{__index=C})
controller.bridge={cancelNpcMove=function() controller.cancels=controller.cancels+1 end}
controller.beginCombat=function() controller.attacks=controller.attacks+1 end
assert(controller:handleCombatBarrier(20) and controller.attacks==0,"blocked target is held without attacking")
targetSquare=square(1,0,"home",false)
assert(controller:handleCombatBarrier(21) and controller.attacks==1,"real crossing returns to native combat")
assert(controller.combatBarrier==nil and controller.cancels==1,"crossing retires the positioning route")

local oldCell=getCell
local room={}
local here=square(0,0,room,true)
local insideSquare=here
local outsideSquare=square(1,0,nil,false)
local doorSquare=square(0,1,nil,false)
local door={isBarricaded=function() return false end,IsOpen=function() return true end}
here.getDoorTo=function(_,other) return other==doorSquare and door or nil end
doorSquare.getDoorTo=function() return nil end
outsideSquare.getDoorTo=function() return nil end
room.getSquares=function() return {size=function() return 1 end,get=function() return insideSquare end} end
local zombie={getCurrentSquare=function() return outsideSquare end,isDead=function() return false end,
    getX=function() return 1 end,getY=function() return 0 end,getZ=function() return 0 end}
getCell=function() return {getGridSquare=function(_,x,y)
    if x==1 and y==0 then return outsideSquare end
    if x==0 and y==1 then return doorSquare end
end,getZombieList=function() return {size=function() return 1 end,get=function() return zombie end} end} end
local routeController={}
P.install(routeController,{canOpen=function() return false end,free=function(tile) return tile~=outsideSquare end})
local actor=setmetatable({id="door-fixture",combatTarget=zombie,moves=0,attacks=0,
    character={getCurrentSquare=function() return here end,CanSee=function() return true end}},
    {__index=routeController})
actor.bridge={resetNpcCombat=function() end,cancelNpcMove=function() end,
    moveNpc=function(_,id,destination)
        assert(destination==doorSquare,"safe engagement uses the real doorway instead of the window")
        actor.moves=actor.moves+1
        return "MOVE_STARTED"
    end,tickNpc=function() here=doorSquare;return "Succeeded" end}
actor.beginCombat=function() actor.attacks=actor.attacks+1 end
assert(actor:handleCombatBarrier(0) and actor.moves==1 and actor.attacks==0,
    "small threat count starts one native exit route without attacking through glass")
assert(actor:handleCombatBarrier(1) and actor.attacks==1,
    "completed doorway route hands back to the existing native combat owner")
getCell=oldCell

-- A held real edge becomes traversable while the actors remain in distinct rooms.
local edgeA=square(10,10,"inside",false)
local edgeB=square(11,10,nil,false)
local blockedForward,blockedBack,hopForward,hopBack=false,false,false,false
edgeA.isBlockedTo=function() return blockedForward end
edgeB.isBlockedTo=function() return blockedBack end
edgeA.isHoppableTo=function() return hopForward end
edgeB.isHoppableTo=function() return hopBack end
local actorSquare,targetTile=edgeA,edgeB
local edgeTarget={getCurrentSquare=function() return targetTile end,isDead=function() return false end}
local edgeController=setmetatable({id="edge",combatTarget=edgeTarget,character={getCurrentSquare=function() return actorSquare end},
 combatBarrier={target=edgeTarget,mode="hold",edgeInside=edgeA,edgeOutside=edgeB},attacks=0,cancels=0},{__index=C})
edgeController.bridge={cancelNpcMove=function() edgeController.cancels=edgeController.cancels+1 end}
edgeController.beginCombat=function() edgeController.attacks=edgeController.attacks+1 end
getCell=function() return {getGridSquare=function(_,x,y,z)
 if z~=0 or y~=10 then return nil end;if x==10 then return edgeA elseif x==11 then return edgeB end
end} end
blockedForward=true
assert(edgeController:handleCombatBarrier(29) and edgeController.attacks==0
 and edgeController.combatBarrier~=nil,"initial closed edge remains held")
blockedForward=false
assert(edgeController:handleCombatBarrier(30) and edgeController.attacks==1
 and edgeController.combatBarrier==nil and edgeController.cancels==1,
 "opened retained edge releases distinct-room hold once")
-- Every unknown, stale, blocked or hoppable edge holds; no geometry is guessed.
local function holdAgain()
 edgeController.combatBarrier={target=edgeTarget,mode="hold",edgeInside=edgeA,edgeOutside=edgeB}
 edgeController.attacks=0;edgeController.cancels=0
end
for _,case in ipairs({"blocked-forward","blocked-back","hop-forward","hop-back","missing",
 "diagonal","floor","unloaded","stale","throws","missing-query","unknown-query"}) do
 holdAgain();blockedForward=false;blockedBack=false;hopForward=false;hopBack=false
 local oldA,oldB=edgeController.combatBarrier.edgeInside,edgeController.combatBarrier.edgeOutside
 local previousCell=getCell
 if case=="blocked-forward" then blockedForward=true elseif case=="blocked-back" then blockedBack=true
 elseif case=="hop-forward" then hopForward=true elseif case=="hop-back" then hopBack=true
 elseif case=="missing" then edgeController.combatBarrier.edgeOutside=nil
 elseif case=="diagonal" then edgeController.combatBarrier.edgeOutside=square(11,11,nil,false)
 elseif case=="floor" then edgeController.combatBarrier.edgeOutside={getX=function() return 11 end,getY=function() return 10 end,getZ=function() return 1 end}
 elseif case=="unloaded" then getCell=function() return {getGridSquare=function() return nil end} end
 elseif case=="stale" then getCell=function() return {getGridSquare=function() return square(10,10,nil,false) end} end
 elseif case=="throws" then edgeB.isHoppableTo=function() error("unreadable") end
 elseif case=="missing-query" then edgeB.isHoppableTo=nil
 elseif case=="unknown-query" then edgeB.isHoppableTo=function() return nil end end
 assert(edgeController:handleCombatBarrier(31) and edgeController.attacks==0
     and edgeController.combatBarrier~=nil,"unverified retained edge stays held: "..case)
 getCell=previousCell;edgeB.isHoppableTo=function() return hopBack end
end
holdAgain();local previousTarget=edgeController.combatTarget
edgeController.combatTarget={getCurrentSquare=function() return edgeB end,isDead=function() return false end}
-- Target change must discard the previous target's edge instead of releasing it.
edgeA.isBlockedTo=function() return false end
assert(not edgeController:handleCombatBarrier(32) and edgeController.attacks==0,
 "changed target cannot release a stale hold")
edgeController.combatTarget=previousTarget
getCell=oldCell
