-- Exercise production tile selection and native area bounds, including Viewpoint.
local highlights=assert(KnoxBaseHighlights)
local oldCell,oldX,oldY,oldIsoX,oldIsoY,oldCompat,oldRequire,oldAdd =
    getCell,getMouseX,getMouseY,screenToIsoX,screenToIsoY,KnoxViewpointCompatibility,require,addAreaHighlightForPlayer
local perspective=false
require=function(name)
    if name=="KS_SurvivorUILayout" then return {isPerspective=function() return perspective end} end
    return oldRequire(name)
end
local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z end}
end
local current=square(0,0,2)
local player={getCurrentSquare=function() return current end,getPlayerNum=function() return 0 end}
local requested, loaded
getCell=function() return {getGridSquare=function(_,x,y,z) requested={x,y,z}; return loaded end} end
getMouseX=function() return 10 end; getMouseY=function() return 20 end
screenToIsoX=function() return -1.2 end; screenToIsoY=function() return 3.8 end
loaded=square(-2,3,2)
local sq,x,y,z=highlights.pickMouseSquare(player)
assert(sq==loaded and x==-2 and y==3 and z==2, "preview returns the actual loaded tile")
assert(requested[1]==-2 and requested[2]==3 and requested[3]==2, "floor backprojected coordinates, including negatives")
loaded=nil
sq,x,y,z=highlights.pickMouseSquare(player)
assert(sq==nil and x==nil and y==nil and z==2, "unloaded tiles never produce a draft")
local viewpoint=square(7,8,4)
KnoxViewpointCompatibility={targetSquare=function() return viewpoint end}
perspective=true
sq,x,y,z=highlights.pickMouseSquare(player)
assert(sq==viewpoint and x==7 and y==8 and z==4, "Viewpoint supplies its actual target and floor")
local args
addAreaHighlightForPlayer=function(...) args={...} end
highlights.drawArea(0,-2,3,4,9,2,{r=1,g=0,b=0,a=0.5})
assert(args[2]==-2 and args[3]==3 and args[4]==5 and args[5]==10 and args[6]==2,
    "native area receives exclusive maximum bounds")
getCell,getMouseX,getMouseY,screenToIsoX,screenToIsoY,KnoxViewpointCompatibility,require,addAreaHighlightForPlayer =
    oldCell,oldX,oldY,oldIsoX,oldIsoY,oldCompat,oldRequire,oldAdd
print("Base highlight picking PASS coordinates=tile viewpoint=target unloaded=none bounds=exclusive")
