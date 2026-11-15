local policy=KnoxSurvivorLifecyclePolicy
local oldCell=getCell
local actor={getX=function() return 10.8 end,getY=function() return 20.2 end,getZ=function() return 0 end}
local sq,chunk={},{}
local squareReads,chunkReads=0,0
getCell=function() return {
 getGridSquare=function(_,x,y,z) squareReads=squareReads+1; assert(x==10 and y==20 and z==0); return sq end,
 getChunkForGridSquare=function() chunkReads=chunkReads+1; return chunk end,
} end
assert(policy.detachedTileLoaded(actor)==true and squareReads==1 and chunkReads==0,"loaded square wins")
sq=nil
assert(policy.detachedTileLoaded(actor)==true and chunkReads==1,"loaded chunk protects absent square")
chunk=nil
assert(policy.detachedTileLoaded(actor)==false and chunkReads==2,"both absent establish unloaded")
local function decision(tile,grace,transient,distance)
 return policy.detachedDecision(distance or 25,100,grace,3,tile,transient)
end
local yes,why=decision(policy.detachedTileLoaded(actor),2,true)
assert(not yes and why=="preserve-native-transient","transient before grace stays protected")
yes,why=decision(policy.detachedTileLoaded(actor),3,true)
assert(yes and why=="hibernate-unloaded-tile","unloaded_transient: expires at grace on absent tile and chunk")
yes,why=decision(false,4,true)
assert(yes and why=="hibernate-unloaded-tile","unloaded transient stays eligible after grace")
for _,tile in ipairs({true,"unknown"}) do
 local actual=tile=="unknown" and nil or tile
 -- Lua's and/or idiom cannot represent nil, so set it explicitly.
 if tile=="unknown" then actual=nil end
 yes,why=decision(actual,300,true,1000)
 assert(not yes and why=="preserve-native-transient","loaded or unknown transient remains protected")
end
getCell=function() return {getGridSquare=function() error("unknown") end} end
assert(policy.detachedTileLoaded(actor)==nil,"throwing square lookup is unknown")
getCell=function() return {getGridSquare=function() return nil end} end
assert(policy.detachedTileLoaded(actor)==nil,"missing chunk API is unknown")
getCell=function() return nil end
assert(policy.detachedTileLoaded(actor)==nil,"missing cell is unknown")
getCell=function() return {getGridSquare=function() error("must not query invalid position") end} end
local invalid={getX=function() return 0/0 end,getY=function() return 1 end,getZ=function() return 0 end}
assert(policy.detachedTileLoaded(invalid)==nil,"invalid coordinates are unknown")
invalid.getX=function() return 1 end; invalid.getZ=function() return 32 end
assert(policy.detachedTileLoaded(invalid)==nil,"invalid floor is unknown")
getCell=oldCell
assert(select(1,policy.detachedDecision(nil,100,1,3,true,false))==true,"nontransient no-distance unchanged")
yes,why=decision(true,1,false,101); assert(yes and why=="hibernate-far","nontransient far unchanged")
yes,why=decision(false,2,false); assert(not yes and why=="preserve-grace","nontransient grace unchanged")
yes,why=decision(false,3,false); assert(yes and why=="hibernate-unloaded-tile","nontransient unloaded unchanged")
yes,why=decision(nil,3,false); assert(not yes and why=="preserve-near-detached","nontransient unknown unchanged")
yes,why=policy.companionDetachedDecision(true,1000,100,300,3)
assert(not yes and why=="preserve-native-transient","companion transient remains protected")
yes,why=policy.companionDetachedDecision(false,25,100,2,3)
assert(not yes and why=="preserve-companion-grace","companion grace remains unchanged")
yes,why=policy.companionDetachedDecision(false,25,100,3,3)
assert(yes and why=="hibernate-stale-companion","companion expiry remains unchanged")
print("Unloaded transient expiry PASS native_boundary=true grace=2/3/4 companion_unchanged=true")
