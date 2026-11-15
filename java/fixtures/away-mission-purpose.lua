-- An ordered mission names what it came for. The directive the live member
-- receives must carry that purpose into the ordinary container planner, and a
-- scout (or an unknown/legacy type) must keep the existing sweep rather than
-- searching for something that does not exist.
local Executor = KnoxAwayTeamExecutor
assert(type(Executor) == "table", "away-team executor must be loaded")

local function directive(missionType, searchRadius)
    return Executor.destinationDirective({
        id = "purpose-1",
        missionType = missionType,
        destination = { x = 420, y = 430, z = 0 },
        searchRadius = searchRadius,
    })
end

assert(directive("scout").purpose == nil,
    "a scout sweeps the area instead of hunting one cargo")
assert(directive(nil).purpose == nil,
    "a legacy mission record keeps the ordinary sweep")
assert(directive("unknown").purpose == nil,
    "an unsupported type falls back to the ordinary sweep")

assert(directive("food").purpose == "food", "a food run searches for food and water")
assert(directive("medicine").purpose == "medicine", "a medical run searches for medical stock")
assert(directive("tools").purpose == "tools", "a tool run searches for tools")
assert(directive("weapons").purpose == "weapons", "a weapon run searches for weapons and ammunition")
assert(directive("building").purpose == "building", "a material run searches for building stock")

-- The purpose must not change where the member searches or how wide.
local area = directive("food", 60)
assert(area.kind == "loot_area" and area.z == 0,
    "a purposeful order keeps the same loaded-area search")
assert(area.maxX - area.minX == 120,
    "the search radius still uses the actual requested sixty tiles")
assert(area.minX == 420 - 60 and area.minY == 430 - 60,
    "the search stays centred on the ordered destination")

assert(Executor.missionLabel({ missionType = "food" }) == "Food run",
    "the order is described by its real purpose")
assert(Executor.missionLabel({ missionType = "scout" }) == "Scouting",
    "scouting keeps its own label")

local missing = Executor.destinationDirective({ id = "purpose-2", missionType = "food" })
assert(missing == nil, "a resource order without a destination is refused")

print("Away mission purpose PASS food=true medical=true tools=true "
    .. "weapons=true building=true scout_sweep=true area_unchanged=true")
