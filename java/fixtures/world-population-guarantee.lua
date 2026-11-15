-- Guaranteed opening cohorts (2026-11-05)
-- Drives the production WorldPopulation planners through plain origins: no
-- world, no body, no spawn. Room-name and household evidence belongs to the
-- origins owner, so this fixture uses its documented flags.
local P = assert(WorldPopulation, "the production planner source is loaded")
local realOrigins = KnoxSurvivorOrigins
KnoxSurvivorOrigins = { isHouseholdRooms = function(rooms) return rooms == "home" end }
stableHash = function(value)
    local result = 5381
    local text = tostring(value or "")
    for index = 1, #text do
        result = (result * 33 + string.byte(text, index)) % 2147483647
    end
    return result
end

local function origin(context, buildingId, regionKey, household)
    return { source = "world_building", context = context, buildingId = buildingId,
        regionKey = regionKey, roomNames = household == false and { "shop" } or "home",
        household = household == true or nil }
end
local function row(id, context, buildingId, regionKey, household)
    return { id = id, origin = origin(context, buildingId, regionKey, household) }
end

local rows = {
    row("police-a", "law_enforcement", "station_b", "rosewood"),
    row("police-b", "law_enforcement", "station_b", "rosewood"),
    row("police-c", "law_enforcement", "station_b", "rosewood"),
    row("police-d", "law_enforcement", "station_b", "rosewood"),
    row("police-e", "law_enforcement", "station_a", "rosewood"),
    row("police-f", "law_enforcement", "station_a", "rosewood"),
    row("police-g", "law_enforcement", "station_a", "rosewood"),
    row("police-h", "law_enforcement", "station_a", "rosewood"),
    row("military-a", "military", "fort_knox", "muldraugh"),
    row("military-b", "military", "fort_knox", "muldraugh"),
    row("military-c", "military", "fort_knox", "muldraugh"),
    row("military-d", "military", "fort_knox", "muldraugh"),
    row("home-a", "generic", "barley_house", "rosewood"),
    row("home-b", "generic", "barley_house", "rosewood"),
    -- Runtime origins keep no room names; allocation stores this flag instead.
    { id = "home-c", origin = { source = "world_building", context = "generic",
        buildingId = "barley_house", regionKey = "rosewood", household = true } },
}

local plan = P.guaranteedCohortPlan(rows, 3, 4, "county-seed")
assert(#plan == 3, "one military, one police and one household are guaranteed")
assert(plan[1].context == "military" and plan[2].context == "police"
    and plan[3].context == "household", "the order is military, police, household")
assert(plan[1].buildingId == "fort_knox" and plan[2].buildingId == "station_a",
    "equal sites break the tie on the building id")
assert(#plan[1].memberIds == 4 and #plan[2].memberIds == 4,
    "the plan carries only real members")
assert(plan[3].minimum == 2 and #plan[3].memberIds == 3
    and plan[3].memberIds[3] == "home-c",
    "a household needs two people, and stored household evidence is enough")
assert(plan[1].regionKey == "muldraugh" and plan[2].regionKey == "rosewood",
    "each choice carries its region for the one-faction guard")

local deterministic = P.guaranteedCohortPlan(rows, 3, 4, "county-seed")
assert(#deterministic == 3 and deterministic[3].buildingId == plan[3].buildingId,
    "the same county seed chooses the same household")

-- More than one real home can open as a household. Military and police remain
-- first, then the remaining faction slots are distributed across homes rather
-- than always taking the largest one.
local manyHomes = {}
for index, entry in ipairs(rows) do manyHomes[index] = entry end
local householdRows = {
    row("trailer-a", "generic", "trailer_home", "rosewood"),
    row("trailer-b", "generic", "trailer_home", "rosewood"),
    row("trailer-c", "generic", "trailer_home", "rosewood"),
    row("shelter-a", "generic", "shelter_home", "rosewood"),
    row("shelter-b", "generic", "shelter_home", "rosewood"),
    row("shelter-c", "generic", "shelter_home", "rosewood"),
    row("cabin-a", "generic", "cabin_home", "muldraugh"),
    row("cabin-b", "generic", "cabin_home", "muldraugh"),
    row("cabin-c", "generic", "cabin_home", "muldraugh"),
}
for _, entry in ipairs(householdRows) do manyHomes[#manyHomes + 1] = entry end
local many = P.guaranteedCohortPlan(manyHomes, 7, 4, "county-seed")
local seenHomes = {}
local homeCount = 0
for _, site in ipairs(many) do
    if site.context == "household" then
        homeCount = homeCount + 1
        assert(not seenHomes[site.buildingId], "a home is planned only once")
        seenHomes[site.buildingId] = true
        assert(#site.memberIds >= 2, "a household still needs real people")
    end
end
assert(#many == 7 and homeCount == 4,
    "both stations and four homes fit alongside the military")
assert(seenHomes["barley_house"] ~= nil and seenHomes["trailer_home"] ~= nil
    and seenHomes["shelter_home"] ~= nil and seenHomes["cabin_home"] ~= nil,
    "houses, trailers, shelters and cabins are all eligible households")

-- The faction limit caps the plan, and the fixed priority survives a limit of one.
local one = P.guaranteedCohortPlan(rows, 1, 4, "county-seed")
assert(#one == 1 and one[1].context == "military", "limit one still staffs the facility first")
assert(#P.guaranteedCohortPlan(rows, 2, 4, "county-seed") == 2,
    "the faction limit caps the plan")

-- Short of the faction minimum, a station is not guaranteed and nothing is invented.
local thin = P.guaranteedCohortPlan({
    row("police-a", "law_enforcement", "station_a", "rosewood"),
    row("police-b", "law_enforcement", "station_a", "rosewood"),
    row("police-c", "law_enforcement", "station_a", "rosewood"),
}, 3, 4, "county-seed")
assert(#thin == 0, "three police cannot guarantee a fourth")

-- Factions disabled means no guaranteed faction plan at all.
assert(#P.guaranteedCohortPlan(rows, 0, 4, "county-seed") == 0,
    "faction limit zero plans nothing")

-- Only world buildings with a real building id qualify.
local noBuilding = P.guaranteedCohortPlan({
    { id = "x", origin = { source = "world_building", context = "military", regionKey = "r" } },
}, 3, 4, "county-seed")
assert(#noBuilding == 0, "a missing building id is not evidence")

-- Ordinary homes with two or more people can become named household groups. The
-- plan is capped, deterministic, one entry per building, and never invents a
-- resident for a shop or a player start.
local householdPlanRows = {
    row("house-a", "generic", "house_one", "rosewood"),
    row("house-b", "generic", "house_one", "rosewood"),
    row("house-c", "generic", "house_one", "rosewood"),
    row("house-d", "generic", "house_two", "rosewood"),
    row("house-e", "generic", "house_two", "rosewood"),
    { id = "shop-a", origin = { source = "world_building", context = "generic",
        buildingId = "shop", regionKey = "rosewood", roomNames = { "shop" } } },
    { id = "start-a", origin = { source = "player_spawn", context = "generic" } },
}
local homes = P.householdCohortPlan(householdPlanRows, 2, "county-seed")
assert(#homes == 2, "the household group budget is a cap")
local homeIds = {}
for _, home in ipairs(homes) do
    assert(home.buildingId == "house_one" or home.buildingId == "house_two",
        "only a real household building is selected")
    assert(#home.memberIds >= 2, "a household needs at least two people")
    homeIds[home.buildingId] = true
end
assert(homeIds["house_one"] and homeIds["house_two"],
    "two different homes are selected, not the same building twice")
local sameHomes = P.householdCohortPlan(householdPlanRows, 2, "county-seed")
assert(#sameHomes == 2 and sameHomes[1].buildingId == homes[1].buildingId
    and sameHomes[2].buildingId == homes[2].buildingId,
    "the same seed produces the same household order")

-- A real facility and station must hold their people before the opening group is
-- formed. The seeding plan uses distinct catalog positions and no invented tile.
local origins = {}
local function addOrigins(buildingId, context, count, regionKey, household)
    for index = 1, count do
        origins[#origins + 1] = { source = "world_building", context = context,
            buildingId = buildingId, regionKey = regionKey,
            key = buildingId .. ":" .. tostring(index), x = index, y = index,
            household = household == true or nil,
            roomNames = household == true and "home" or nil }
    end
end
addOrigins("fort_knox", "military", 4, "muldraugh")
addOrigins("station_a", "law_enforcement", 4, "rosewood")
addOrigins("house_one", "generic", 3, "rosewood", true)
addOrigins("house_two", "generic", 3, "rosewood", true)
addOrigins("house_three", "generic", 3, "rosewood", true)
local seeded = P.openingSitePlan(origins, 4, 4, "county-seed")
assert(#seeded == 4, "two facilities and two homes fit the faction limit")
assert(seeded[1].kind == "military" and seeded[2].kind == "police",
    "military and police are seeded before civilian homes")
assert(seeded[3].kind == "household" and seeded[4].kind == "household",
    "the remaining slots seed real households")
assert(seeded[1].required == 4 and seeded[2].required == 4
    and seeded[3].required == 3 and seeded[4].required == 3,
    "a facility needs its faction minimum and a household needs three")
assert(#seeded[1].origins == 4 and #seeded[2].origins == 4
    and #seeded[3].origins == 3 and #seeded[4].origins == 3,
    "each site carries exactly the real positions it will occupy")
local seededHomes = {}
for index = 3, 4 do
    local buildingId = seeded[index].buildingId
    assert(not seededHomes[buildingId], "a seeded home is not repeated")
    seededHomes[buildingId] = true
end

local stations=0
for _,site in ipairs(many) do if site.context=="police" then stations=stations+1 end end
assert(stations==2,"two stations in the same town remain separate eligible sites")
addOrigins("second_barracks","military",4,"rosewood")
addOrigins("second_station","law_enforcement",4,"rosewood")
local allSites=P.openingSitePlan(origins,7,4,"county-seed")
local facilities={}
for _,site in ipairs(allSites) do facilities[site.buildingId]=true end
assert(facilities.second_barracks and facilities.second_station and facilities.house_one,
    "remaining military and police facilities share the plan with households")
KnoxSurvivorOrigins = realOrigins
print("world_population_guarantee PASS order=military,police,households"
    .. " homes=4 trailer=1 shelter=1 cabin=1 site_seed=fort_knox,station_a")
