local P = KnoxPersistence
local oldManager, oldCell, oldJobs = KnoxBaseManager, getCell, KnoxBaseJobs
local area = { buildingId = "1", minX = 0, minY = 0, width = 1, height = 1 }
local empty = { size = function() return 0 end }
local square = { getBuilding = function() return { getDef = function() return { getID = function() return 1 end } end } end,
    getObjects = function() return empty end }
getCell = function() return { getGridSquare = function(_, x, y, z) if z == 0 then return square end end } end
local manager = capacityGateFactory({syncStructureProtection = function() end}, area)
KnoxBaseManager = manager
assert(type(manager.discoverFactionBeds) == "function", "discovery exported on first load")
local a = assert(P.allocateWorldSurvivor({x=91,y=91,z=0,key="capacity-a",region="CA"}, 1))
local b = assert(P.allocateWorldSurvivor({x=92,y=91,z=0,key="capacity-b",region="CA"}, 1))
local c = assert(P.allocateWorldSurvivor({x=93,y=91,z=0,key="capacity-c",region="CA"}, 1))
local d = assert(P.allocateWorldSurvivor({x=94,y=91,z=0,key="capacity-d",region="CA"}, 1))
local e = assert(P.allocateWorldSurvivor({x=95,y=91,z=0,key="capacity-e",region="CA"}, 1))
local group = assert(P.createTravelGroup({a,b,c},1))
local faction = assert(P.promoteTravelGroupToFaction(group.id,1))
faction.homeBase = area
local travelers = assert(P.createTravelGroup({d,e},1))
local allowed, reason = P.addFactionMember(faction.id,d,2)
assert(not allowed and reason == "at_capacity", "real membership gate refuses full home")
assert(P.getTravelGroupFor(d).id == travelers.id, "refusal preserves travel group")
getCell = function() return {getGridSquare = function() return nil end} end
assert(P.addFactionMember(faction.id,d,2), "unknown capacity preserves admission")
assert(P.getTravelGroupFor(d) == nil, "successful admission leaves old group")
getCell = function() return { getGridSquare = function(_,x,y,z) if z==0 then return square end end } end
local oldEnsure, oldOwned = P.ensurePlayerId, P.getBasesForOwner
P.ensurePlayerId = function() return "owner" end
P.getBasesForOwner = function() return {{id="base",home=area}} end
KnoxBaseJobs = {workforceSummary=function() return {residents=0} end}
-- Drive the real outpost gate with one real discovered bed and no residents.
local bed = {getProperties=function() return {get=function(_,key) if key == "BedType" then return "goodBed" end end} end,
    getObjectIndex=function() return 0 end}
local bedObjects = {size=function() return 1 end, get=function() return bed end}
square.getObjects = function() return bedObjects end
square.getX=function() return 0 end; square.getY=function() return 0 end; square.getZ=function() return 0 end
local destination = {buildingId="2",minX=4,minY=4,width=1,height=1}
manager = capacityGateFactory({syncStructureProtection=function() end},destination)
KnoxBaseManager = manager
local outpost, outpostReason = manager.establishOutpost({}, square)
assert(outpost == nil and outpostReason == "settlement_has_room", "real outpost gate refuses while home has room")
square.getObjects = function() return empty end
-- A measured empty base is full; unreadable is unknown, not zero.
local measured = KnoxSettlementCapacity.forBase({home=area})
assert(measured and measured.capacity == 0, "loaded empty area measures zero")
getCell = function() return {getGridSquare=function() return nil end} end
assert(KnoxSettlementCapacity.forBase({home=area}) == nil, "unloaded area stays unknown")
P.ensurePlayerId, P.getBasesForOwner = oldEnsure, oldOwned
KnoxBaseManager, getCell, KnoxBaseJobs = oldManager, oldCell, oldJobs
print("Capacity gate PASS actual=membership discovery=first-load unknown=unloaded")
