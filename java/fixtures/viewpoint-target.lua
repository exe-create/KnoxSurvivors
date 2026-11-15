local prior=KnoxSurvivorRuntime
local C=codecViewpointTarget
local function body()
 return {isDead=function() return false end,getCurrentSquare=function() return {} end,
 getX=function() return 1 end,getY=function() return 0 end,getZ=function() return 0 end}
end
local npc=body()
local player=body();player.getPlayerNum=function() return 0 end
player.CanSee=function() return true end
local scans=0
KnoxSurvivorRuntime={idForCharacter=function(c) if c==npc then return "npc" end end,
 getCharacter=function(id) if id=="npc" then return npc end end,
 nearestToSquare=function(s,r) scans=scans+1;assert(r==0.75,"keep tight square fallback");return s.found and "npc" or nil end}
for _,d in ipairs({{object=npc},{character=npc},{player=npc},npc}) do
 local t=C.aimedTarget(player,d)
 assert(t and t.id=="npc" and t.character==npc,"sparse descriptor resolves its actual body")
end
assert(scans==0,"direct body avoids square scan")
local t=C.aimedTarget(player,{object={},square={found=true}})
assert(t and t.character==npc and scans==1,"unresolvable object retains square fallback")
assert(C.aimedTarget(player,{character={}})==nil,"unresolvable descriptor refuses")
assert(C.reportedRejectedTarget==true,"rejected aim is diagnosed")
player.CanSee=function() return false end
assert(C.aimedTarget(player,{character=npc})==nil,"hidden body rejected")
player.CanSee=function() return true end
npc.getX=function() return 10 end
assert(C.aimedTarget(player,{character=npc})==nil,"distant body rejected")
KnoxSurvivorRuntime=prior
codecViewpointTarget=nil
print("Viewpoint target PASS sparse=true bare=true squareFallback=true rejected=true visibility=true")
