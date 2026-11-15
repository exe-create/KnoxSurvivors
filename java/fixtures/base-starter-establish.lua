local oldP=KnoxPersistence
local building={}
local square={getBuilding=function() return building end,getZ=function() return 2 end}
local current,created,applied=nil,0,0
local area={buildingId="starter-building",minX=10,minY=10,width=4,height=4,z=2}
local B={getForOwner=function() return current end,syncStructureProtection=function() end,
 applyStarterLayout=function(id,b,z,pid,leader)
    assert(id=="starter-base" and b==building and z==2 and pid=="starter-player" and leader~=nil)
    applied=applied+1;return {added=2,assigned=1}
 end}
KnoxPersistence={ensurePlayerId=function() return "starter-player" end,
 createBase=function(kind,id,home) created=created+1;current={id="starter-base",home=home};return current,"created" end,
 ensurePlayerFaction=function() return {} end}
local establish=starterEstablishFactory(B,area)
local player={}
local base,result,starter=establish(player,square)
assert(base==current and result=="created" and starter.added==2 and created==1 and applied==1,
 "first establishment hands the actual building/floor and owner to starter setup")
base,result=establish(player,square)
assert(result=="existing" and created==1 and applied==1,"reopening an established base does not redo starter work")
current.home={buildingId="elsewhere"}
base,result=establish(player,square)
assert(result=="move_confirmation_required" and applied==1,"a move request cannot silently reassign existing work")
assert(establish(nil,square)==nil,"invalid owner cannot establish or assign")
KnoxPersistence=oldP
