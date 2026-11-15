-- Storage autonomy, item 5: the yard is honestly named, takes any item, and is
-- preferred for bulky loads. One owner answers both questions.
local S = KnoxBaseStorage

assert(S.DEPOT_LABEL == "Drop Point", "the area's player-facing name says what it is")
assert(S.DEPOT_ZONE_TYPES.log_processing == true,
    "the saved area key is unchanged: log_processing stays a save contract")

local zone = { id = "z1", type = "log_processing", label = "Log Processing", enabled = true }
local food = { getFullType = function() return "Base.Beans" end,
    getDisplayCategory = function() return "Food" end, IsFood = function() return true end }
local junk = { getFullType = function() return "Base.Sheet" end,
    getDisplayCategory = function() return "Junk" end }
local medical = { getFullType = function() return "Base.Pills" end,
    getDisplayCategory = function() return "Medical" end }

assert(S.depotAccepts(zone, food) == true, "a drop point takes food")
assert(S.depotAccepts(zone, junk) == true, "a drop point takes junk")
assert(S.depotAccepts(zone, medical) == true, "a drop point takes medical stock")
assert(S.depotAccepts(zone, nil) == false, "nothing cannot be set down")
assert(S.depotAccepts({ id = "g", type = "guard", enabled = true }, food) == false,
    "a guard post is not a drop point")
assert(S.depotAccepts({ id = "z2", type = "log_processing", enabled = false }, food) == false,
    "a disabled area is not a drop point")

-- The player's filter set describes the yard's purpose and never admission.
zone.storageFilters = { fuel = true }
assert(S.depotAccepts(zone, food) == true,
    "an item outside the chosen set may still be set down")

-- Bulk ranking: heavy flag first, then weight; an unreadable weight is not bulk.
assert(S.depotBulkRank({ isHeavy = function() return true end }) == 1,
    "an item the game calls heavy is a bulk load")
assert(S.depotBulkRank({ getActualWeight = function() return 8.5 end }) == 1,
    "a heavy weight is a bulk load")
assert(S.depotBulkRank({ getWeight = function() return 3 end }) == 1,
    "base weight answers when actual weight is absent")
assert(S.depotBulkRank({ getActualWeight = function() return 0.3 end }) == 2,
    "a light item is ordinary")
assert(S.depotBulkRank({}) == 2, "an item with no weight reads as ordinary, never bulk")
assert(S.depotBulkRank(nil) == 2, "no item is ordinary")
assert(S.depotBulkRank({ getActualWeight = function() error("no weight") end,
    getWeight = function() return 4 end }) == 1,
    "a failing actual-weight read falls back to the base weight")

-- One placement decision, and a target of zero still means no ceiling.
local D = S.depotPlacementDecision
assert(D({ depot = true, accepted = true, target = 60, held = 59, freeTiles = 1 }) == "place")
assert(D({ depot = true, accepted = true, target = 60, held = 60, freeTiles = 1 }) == "target_reached")
assert(D({ depot = true, accepted = true, target = 0, held = 999, freeTiles = 1 }) == "place",
    "a yard with no ceiling still accepts")

-- The rename's save-compatibility map is proven by the zone_display_label
-- fixture, which owns that read; this pass owns the constant and the saved key.
depotReceipt = "accepted=4 refused=3 bulk=7 keyUnchanged=1"
depotPass = true
