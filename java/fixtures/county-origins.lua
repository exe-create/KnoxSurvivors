local C=assert(codecCountyOrigins)
local home={key="home-one",source="world_building",buildingId="home",context="generic",roomNames={"bedroom","kitchen"}}
local homeTwo={key="home-two",source="world_building",buildingId="home",context="generic",roomNames=home.roomNames}
local start={key="start",source="player_spawn",context="generic"}
local small={key="small",name="small",opportunityCount=2,origins={start,home,homeTwo}}
assert(C.next(small,{},0).source=="world_building","metadata buildings outrank player-start definitions")
assert(C.next(small,{[home.key]=true},0)==homeTwo,"finish an actual household instead of scattering its people")
assert(C.next(small,{[home.key]=true,[homeTwo.key]=true},0)==start,"player starts are only an exhausted-building fallback")
local distant={key="distant",source="world_building",buildingId="station",context="law_enforcement"}
local large={key="large",name="large",opportunityCount=6,origins={distant}}
local origin,region=C.choose({regions={small,large}},{},{small=1,large=1},0)
assert(origin==distant and region=="large","regional opportunity controls allocation rather than proximity to a player")
assert(C.choose({regions={large}},{distant=true},{},0)==nil,"exhausted origins never invent a new point")
local O=assert(KnoxSurvivorOrigins)
local bounds={minX=10,minY=20,maxX=11,maxY=21}
assert(O.inRoomBounds(10,20,bounds) and O.inRoomBounds(11,21,bounds),"room edges are real permitted origins")
assert(not O.inRoomBounds(12,21,bounds),"crew offset cannot spill beyond its actual room")
assert(not O.inRoomBounds(10,20,nil),"missing metadata does not invent a room")
