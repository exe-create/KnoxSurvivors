local O=assert(KnoxSurvivorOrigins)
assert(O.isHouseholdRooms({"bedroom","kitchen"}),"bedroom and kitchen form a civilian home")
assert(O.isHouseholdRooms({"bedroom","livingroom"}),"living room supports a home")
assert(O.isHouseholdRooms({"trailerbedroom","trailerkitchen"}),"a trailer is a real home")
assert(O.isHouseholdRooms({"bedroom","mobilehome"}),"a mobile home is a real home")
assert(O.isHouseholdRooms({"shelterbedroom","shelter"}),"a shelter with a bed is a real home")
assert(O.isHouseholdRooms({"cabinbedroom","cabinkitchen"}),"a cabin is a real home")
assert(O.isHouseholdRooms({"cabinbed","cabin"}),"a cabin bed without the word bedroom is a real home")
assert(O.isHouseholdRooms({"shelterbed","shelter"}),"a shelter bed without the word bedroom is a real home")
assert(not O.isHouseholdRooms({"bedroom","policeoffice","kitchen"}),"police quarters are not a civilian household")
assert(not O.isHouseholdRooms({"kitchen","shop"}),"a shop kitchen does not invent a family")
assert(not O.isHouseholdRooms(nil),"unknown rooms never create a household")
local first={source="world_building",buildingId="home",roomNames={"bedroom","kitchen"}}
local second={source="world_building",buildingId="home",roomNames={"bedroom","livingroom"}}
assert(O.isHouseholdRoster({first,second}),"two civilians at the same actual home can settle as a household")
local stored={source="world_building",buildingId="home",household=true}
assert(O.isHouseholdRoster({stored,stored}),"the stored household bit survives a missing room list")
local emptyBuilding={source="world_building",buildingId="",household=true}
assert(not O.isHouseholdRoster({emptyBuilding,emptyBuilding}),"an empty building id is not a household")
second.buildingId="other"
assert(not O.isHouseholdRoster({first,second}),"nearby strangers in different houses are not a family")
assert(O.classifyRooms({"armysurplus"})=="generic","retail surplus is not a military facility")
assert(not O.professionAllowedAtContext("base:veteran",O.classifyRooms({"armysurplus"})),"retail surplus cannot roll a soldier")
