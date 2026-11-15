-- A settlement is as large as its beds, food and water allow. Drives the
-- production owner loaded as settlement_capacity_source.
local C = assert(KnoxSettlementCapacity, "settlement capacity owner missing")
local priorManager = KnoxBaseManager
local priorCell = getCell
getCell = function() return { getGridSquare = function() return {} end } end
local area = { id = "b1", buildingId = "one", minX = 0, minY = 0, width = 1, height = 1 }

-- 1. Beds are the hard limit and are always read.
local bedsOnly = C.measure({ beds = 4 })
assert(bedsOnly ~= nil and bedsOnly.capacity == 4, "four beds hold four people")
assert(bedsOnly.food == nil and bedsOnly.water == nil,
    "a missing food or water read stays unknown instead of being invented")

-- 2. Food and water can only lower the capacity, never raise it.
assert(C.measure({ beds = 4, food = 2 }).capacity == 2,
    "two servings feed two, whatever the beds say")
assert(C.measure({ beds = 4, food = 9 }).capacity == 4,
    "a full pantry does not add beds")
assert(C.measure({ beds = 5, food = 9, water = 3 }).capacity == 3,
    "the scarcest fact decides")
assert(C.measure({ beds = 4, food = 0 }).capacity == 0,
    "an empty pantry admits nobody")
assert(C.measure({ beds = 0 }).capacity == 0, "no beds, no room")

-- 3. Unreadable input never becomes capacity.
assert(C.measure(nil) == nil, "no facts is not a capacity")
assert(C.measure({}) == nil, "unreadable beds is not a capacity")
assert(C.measure({ beds = "4" }) == nil, "a string is not a bed count")
assert(C.measure({ beds = 0 / 0 }) == nil, "a NaN bed count is not a capacity")
assert(C.measure({ beds = -3 }).capacity == 0, "a negative count never frees room")

-- 4. Room is what the residents have not already taken.
local home = C.measure({ beds = 4 })
local ok, why = C.admits(home, 1, 2)
assert(ok == true and why == "room", "one resident leaves room for two")
ok, why = C.admits(home, 3, 2)
assert(ok == false and why == "at_capacity", "three residents hold the last bed")
ok, why = C.admits(nil, 0, 1)
assert(ok == false and why == "no_capacity_read", "no read is not room")
ok, why = C.admits(home, 0, 0)
assert(ok == false and why == "no_arrivals", "nobody arriving is not growth")

-- 5. The gate reads the base's own beds and leaves unmeasured settlements alone.
local beds = { {}, {}, {} }
KnoxBaseManager = { discoverFactionBeds = function() return beds end }
local faction = { homeBase = area, memberIds = { "a", "b" } }
local measured = C.forBase(faction.homeBase, faction)
assert(measured ~= nil and measured.beds == 3, "the settlement's own beds are counted")
local allowed, reason = C.admitsMember(faction, 1)
assert(allowed == true and reason == "room", "one free bed admits one person")
allowed, reason = C.admitsMember(faction, 2)
assert(allowed == false and reason == "at_capacity", "two arrivals need two free beds")

local unsettled = { memberIds = { "a" } }
allowed, reason = C.admitsMember(unsettled, 1)
assert(allowed == true and reason == "unsettled",
    "a group without a home is not a settlement")

KnoxBaseManager = priorManager
priorManager = nil
local unknown = { homeBase = { id = "b2" }, memberIds = { "a" } }
allowed, reason = C.admitsMember(unknown, 1)
assert(allowed == true and reason == "capacity_unknown",
    "an unmeasured settlement keeps its previous behaviour")

-- 6. Expansion is earned by a settlement that has filled its own beds.
local priorBeds, priorJobs = KnoxBaseManager, KnoxBaseJobs
KnoxBaseManager = { discoverFactionBeds = function() return { {}, {}, {} } end }
KnoxBaseJobs = { workforceSummary = function() return { residents = 3 } end }
local settled = { homeBase = area, memberIds = { "a", "b", "c" } }
local earned, why = C.expansionEarned(settled.homeBase, settled)
assert(earned == true and why == "settlement_full",
    "a settlement that has filled its beds earns a second site")
KnoxBaseJobs = { workforceSummary = function() return { residents = 1 } end }
earned, why = C.expansionEarned(settled.homeBase, settled)
assert(earned == false and why == "settlement_has_room",
    "a settlement with room left expands nowhere")
KnoxBaseJobs = priorJobs
KnoxBaseManager = priorBeds
priorBeds, priorJobs = nil, nil

getCell = priorCell

print("Settlement capacity PASS beds=limit food=lower water=lower residents=occupied unknown=allowed expansion=earned")
