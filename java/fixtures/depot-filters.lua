-- N2 depot: a log yard is a stockpile floor with container-style filters, and
-- the placement rule answers one question with one reason.
local S = KnoxBaseStorage

-- The harness loads the needs owner later in the run, and item classification
-- reads it for food and water. Stand it up for this fixture only, then restore.
local priorNeeds = KnoxSurvivorNeeds
KnoxSurvivorNeeds = {
    isSafeFood = function() return false end,
    isWaterItem = function() return false end,
}

local logItem = {
    getFullType = function() return "Base.Log" end,
    getDisplayCategory = function() return "Base" end,
}

assert(S.isDepotZone({type = "log_processing", enabled = true}) == true,
    "a log processing area must be a depot")
assert(not S.isDepotZone({type = "log_processing", enabled = false}), "a disabled area is not a depot")
assert(not S.isDepotZone({type = "guard"}), "a guard post is not a depot")
assert(not S.isDepotZone(nil), "a missing zone is not a depot")

local zone = {id = "z1", type = "log_processing", label = "Log Yard", enabled = true}
local policy = S.zoneFilters(zone)
assert(policy ~= nil and policy.storageFilterVersion == 1 and policy.depot == true,
    "a depot zone must read as a container-shaped policy")
assert(policy.storageFilters.logs == true and policy.storageFilters.building == true,
    "a log yard defaults to timber and building stock")
assert(S.depotAccepts(zone, logItem) == true, "logs belong on a log yard floor")

local foodItem = {
    getFullType = function() return "Base.Beans" end,
    getDisplayCategory = function() return "Food" end,
    IsFood = function() return true end,
}
assert(S.depotAccepts(zone, foodItem) == false, "food must not be dumped on a log yard")

-- A player choice replaces the default set, and ensure must not undo it.
local chosen = {id = "z2", type = "log_processing", enabled = true}
S.ensureDepotFilters(chosen)
assert(chosen.storageFilters.logs == true, "a new depot starts with the default filters")
chosen.storageFilters = {fuel = true}
S.ensureDepotFilters(chosen)
assert(chosen.storageFilters.fuel == true and chosen.storageFilters.logs == nil,
    "saving filters must replace the defaults, not merge them back")

-- The getter never edits a save: a zone with no filters reports defaults only.
local untouched = {id = "z3", type = "log_processing", enabled = true}
assert(S.zoneFilters(untouched).storageFilters.logs == true)
assert(untouched.storageFilters == nil, "reading filters must not write them")

-- Placement decision: one answer, one reason.
local D = S.depotPlacementDecision
assert(D({depot = true, accepted = true, target = 60, held = 59, freeTiles = 2}) == "place")
assert(D({depot = true, accepted = true, target = 60, held = 60, freeTiles = 2}) == "target_reached")
assert(D({depot = true, accepted = false, target = 60, held = 0, freeTiles = 2}) == "not_allowed")
assert(D({depot = true, accepted = true, target = 60, held = 1, freeTiles = 0}) == "no_free_tile")
assert(D({depot = true, accepted = true, target = 0, held = 999, freeTiles = 1}) == "place",
    "no target means no ceiling")
assert(D({depot = false}) == "no_depot")
assert(D(nil) == "no_depot")
assert(S.depotRefusalText("target_reached") ~= "", "a refusal must have words")

-- Targets: known categories from the default table, overridable per area.
assert(S.depotTarget(zone, "logs") == 60)
assert(S.depotTarget({depotTargets = {logs = 5}}, "logs") == 5)
assert(S.depotTarget(zone, "medical") == 0, "a category with no target is uncapped")

-- The first enabled depot is the destination, and a base without one says so.
assert(S.depotZone({zones = {a = {id = "a", type = "cooking"}, z = zone}}) == zone)
assert(S.depotZone({zones = {}}) == nil)
assert(S.depotDestination({zones = {}}, logItem) == nil, "no depot means no destination")
local destination, reason = S.depotDestination({zones = {}}, foodItem)
assert(destination == nil and reason == "no_depot")

local foundZone = S.depotZoneAt({zones = {z = {id = "z", type = "log_processing", enabled = true,
    x1 = 10, y1 = 10, x2 = 20, y2 = 20, z = 0}}}, 15, 15, 0)
assert(foundZone ~= nil, "a square inside the yard must find the depot")
assert(S.depotZoneAt({zones = {z = {id = "z", type = "log_processing", enabled = true,
    x1 = 10, y1 = 10, x2 = 20, y2 = 20, z = 0}}}, 40, 40, 0) == nil,
    "a square outside the yard must not find it")


-- A depot destination names a tile and a floor container, or refuses clearly.
local noZone, noZoneReason = S.depotStore({zones = {}}, logItem)
assert(noZone == nil and noZoneReason == "no_depot", "a base without a yard has no destination")
local logBase = {zones = {z = {id = "z", type = "log_processing", enabled = true,
    x1 = 0, y1 = 0, x2 = 4, y2 = 4, z = 0}}}
local refused, refusedReason = S.depotStore(logBase, foodItem)
assert(refused == nil and refusedReason == "not_allowed", "food must never route to the log yard")
-- The harness has no loaded cell, so there is no free tile: the decision has to
-- refuse rather than invent a destination.
local noSpot, noSpotReason = S.depotStore(logBase, logItem)
assert(noSpot == nil and (noSpotReason == "no_free_tile" or noSpotReason == "no_floor_container"),
    "without a loaded cell a depot must refuse, got " .. tostring(noSpotReason))


-- The home band's depot line: held against target, then the floor.
local line = S.depotStatusLine({label = "Log Yard", freeTiles = 4, entries = {
    {category = "logs", held = 34, target = 60},
    {category = "building", held = 3, target = 0},
}})
assert(line == "Log Yard: logs 34/60, building 3", "got " .. tostring(line))
local fullLine = S.depotStatusLine({label = "Log Yard", freeTiles = 0, entries = {
    {category = "logs", held = 60, target = 60}}})
assert(string.find(fullLine, "floor full", 1, true) ~= nil, "a full floor must say so")
assert(S.depotStatusLine({entries = {}}) == nil, "a yard with nothing tracked has no line")
assert(S.depotStatusLine(nil) == nil, "no facts means no line")


-- The notebook storage row is composed by the storage owner, so the room
-- it prints is the room the policy recorded.
local rowPolicy = {storageFilterVersion = 1, storageFilters = {tools = true},
    priority = "normal", containerType = "toolbox", x = 5, y = 6, z = 0,
    roomLabel = "Workshop"}
local withRoom = S.policyRowText(rowPolicy, true)
assert(string.find(withRoom, "in Workshop", 1, true) ~= nil,
    "the row must name the room, got " .. tostring(withRoom))
assert(string.find(withRoom, "5, 6, floor 0", 1, true) ~= nil,
    "the row must keep its coordinates, got " .. tostring(withRoom))
local noRoom = S.policyRowText({storageRole = "tools", priority = "normal",
    containerType = "crate", x = 1, y = 2, z = 0}, true)
assert(string.find(noRoom, " on ", 1, true) == nil and string.find(noRoom, " in ", 1, true) == nil,
    "a policy without a room must not invent one, got " .. tostring(noRoom))
local gone = S.policyRowText(rowPolicy, false)
assert(string.find(gone, "unavailable", 1, true) ~= nil,
    "an unresolved container must say so")

KnoxSurvivorNeeds = priorNeeds

print("Depot filters PASS filters=true placement=true targets=true zone=true")

-- The notebook reads the yard through one composition: the band's line when the
-- floor holds something, and an honest "empty" when it does not. An empty yard is
-- not a problem, so this row is information rather than an attention item.
assert(S.depotSummaryLine({label = "Log Yard", line = "Log Yard: logs 34/60"}) == "Log Yard: logs 34/60",
    "the panel shows the same line as the band")
assert(S.depotSummaryLine({label = "Log Yard"}) == "Log Yard: empty",
    "an empty yard still names itself")
assert(S.depotSummaryLine({line = "Log Yard: logs 1/60"}) == "Log Yard: logs 1/60",
    "a status with a line does not need a label")
assert(S.depotSummaryLine(nil) == nil, "no status means no row")
assert(S.depotSummaryLine({}) == nil, "a nameless, lineless status draws nothing")
assert(S.depotSummaryLine({label = ""}) == nil, "an empty name draws nothing")
