-- Driving preferences live in KS_VehicleNavigation: which ground a step costs,
-- and how fast each surface may be driven. No vehicle is stubbed here; these are
-- the planner's own decisions, driven directly.
assert(KnoxVehicleNavigation ~= nil, "routing owner missing")

local nav = KnoxVehicleNavigation

local function squareWith(name, broken)
    return {
        getFloor = function()
            if broken then error("floor reader failed") end
            if name == nil then return nil end
            return { getSpriteName = function() return name end }
        end,
    }
end

-- Road before dirt before grass is the whole point: a sprite called
-- "dirtroad" must not be read as pavement just because it contains "road".
local cases = {
    { "street_01_0", "asphalt" },
    { "dirtroad_02_0", "dirt" },
    { "gravel_1_0", "gravel" },
    { "blends_trail_03_0", "trail" },
    { "vegetation_grass_01_0", "grass" },
    { "floors_interior_tilesandwood_01_0", "unknown" },
}
for _, case in ipairs(cases) do
    local name = nav.surface(squareWith(case[1]))
    assert(name == case[2], case[1] .. " read as " .. tostring(name))
end

assert(nav.surface(nil) == "unknown", "a missing square is unknown ground")
assert(nav.surface(squareWith(nil)) == "unknown", "a square without a floor is unknown")
assert(nav.surface(squareWith("street_01", true)) == "unknown",
    "a failing floor reader must not be read as good ground")
assert(nav.surface({}) == "unknown", "a square without a floor reader is unknown")

local asphalt, gravel = nav.speedFactor("asphalt"), nav.speedFactor("gravel")
local dirt, grass = nav.speedFactor("dirt"), nav.speedFactor("grass")
local unknown = nav.speedFactor("unknown")
assert(asphalt == 1, "pavement keeps the full cruise, got " .. tostring(asphalt))
assert(asphalt > gravel and gravel > dirt and dirt > grass and grass > 0,
    "loose ground lowers the cruise in order")
assert(unknown > 0 and unknown <= asphalt, "unknown ground is slower, never free")
assert(nav.speedFactor("not_a_surface") == unknown,
    "an unknown surface name falls back to the unknown rate")

local paved = nav.linkCost(4, 1.00, 1.00, 0)
local onGravel = nav.linkCost(4, 1.12, 1.12, 0)
local onGrass = nav.linkCost(4, 1.65, 1.65, 0)
assert(paved < onGravel and onGravel < onGrass, "paved ground is the cheapest step")

-- A detour is worth taking when it is paved: 45% longer on pavement must beat
-- the direct line over grass, or the preference would never change a route.
assert(nav.linkCost(40 * 1.45, 1.00, 1.00, 0) < nav.linkCost(40, 1.65, 1.65, 0),
    "a modest paved detour beats the direct line over grass")
-- ...but not any detour: an absurd one still loses.
assert(nav.linkCost(40 * 3, 1.00, 1.00, 0) > nav.linkCost(40, 1.65, 1.65, 0),
    "pavement preference is a preference, not a mandate")

assert(nav.linkCost(4, 1.00, 1.65, 0) > paved, "changing surface adds cost")
assert(nav.linkCost(4, 1.00, 1.00, 1) > paved, "a turn adds cost")
assert(nav.linkCost(4, 1.35, 1.35, 0) > paved, "unknown ground is not free ground")

-- Unread ground is recorded, once per distinct sprite, so a real session can
-- report the names the classifier does not know.
local savedLog = rawget(_G, "KnoxDebugLog")
local logged = {}
KnoxDebugLog = { once = function(category, id, event, details)
    logged[#logged + 1] = tostring(id) .. ":" .. tostring(event)
end }
nav.resetUnknownGround()
assert(nav.surface(squareWith("mystery_tile_01")) == "unknown", "probe reads as unknown")
assert(nav.surface(squareWith("mystery_tile_01")) == "unknown", "probe repeats")
assert(nav.surface(squareWith("street_02_0")) == "asphalt", "known ground stays known")
local report, distinct = nav.unknownGround()
assert(distinct == 1, "one distinct unknown sprite, got " .. tostring(distinct))
assert(string.find(report, "mystery_tile_01x2", 1, true) ~= nil,
    "the report carries the name and the count, got " .. tostring(report))
assert(#logged == 1, "each unknown sprite is reported once, got " .. tostring(#logged))
assert(string.find(report, "street_02_0", 1, true) == nil, "known ground is not recorded")
nav.resetUnknownGround()
assert(select(2, nav.unknownGround()) == 0, "the record can be cleared")
KnoxDebugLog = savedLog

print("Vehicle surface driving PASS asphalt=true order=true failclosed=true "
    .. "cost=true detour=true switch=true report=true")
