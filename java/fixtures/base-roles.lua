local Catalog = assert(KnoxOrderCatalog, "the order catalogue is loaded")

assert(#Catalog.baseRoleOrder == 9, "there are exactly nine role bundles")
local seen = {}
for _, role in ipairs(Catalog.baseRoleOrder) do
    assert(not seen[role], "each role appears once")
    seen[role] = true
    local definition = assert(Catalog.baseRoles[role], "the role has a definition")
    assert(definition.label ~= nil and definition.label ~= "",
        "the role has a player-facing label")
    assert(type(definition.tasks) == "table", "the role has task metadata")
    assert(Catalog.basePreferences[role] ~= nil,
        "the role is a saved base preference")
    assert(Catalog.isBasePreference(role) == true,
        "the role passes the existing preference gate")
    assert(#(Catalog.baseRoleBlocks[role]) == 6,
        "the role has six four-hour blocks")
    local hours = Catalog.roleScheduleHours(role)
    assert(hours ~= nil and #hours == 24,
        "the role expands into a 24-hour schedule draft")
    local gear = Catalog.roleGear(role)
    assert(gear ~= nil and #gear > 0,
        "the role has a tag-based kit vocabulary")
    for _, tag in ipairs(gear) do
        assert(type(tag) == "string" and tag ~= "",
            "the kit contains tags, not item ids")
    end
end

assert(Catalog.preferenceMatchesTask("guard", "guard"),
    "a guard matches guard work")
assert(Catalog.preferenceMatchesTask("guard", "patrol"),
    "a guard also matches patrol work")
assert(Catalog.preferenceMatchesTask("cook", "cook"),
    "a cook matches cooking")
assert(Catalog.preferenceMatchesTask("farmer", "farm_seed"),
    "a farmer matches planting")
assert(Catalog.preferenceMatchesTask("builder", "barricade"),
    "a builder matches barricades")
assert(Catalog.preferenceMatchesTask("builder", "repair"),
    "a builder matches repair")
assert(Catalog.preferenceMatchesTask("mechanic", "repair"),
    "a mechanic matches repair")
assert(not Catalog.preferenceMatchesTask("medic", "repair"),
    "a medic does not invent a medical task")

assert(Catalog.roleForPreference("cooking") == "cook",
    "the old cooking preference displays as cook")
assert(Catalog.roleForPreference("farming") == "farmer",
    "the old farming preference displays as farmer")
assert(Catalog.roleForPreference("woodwork") == "builder",
    "the old woodwork preference displays as builder")
assert(Catalog.roleForPreference("hauling") == "quartermaster",
    "the old hauling preference displays as quartermaster")
assert(Catalog.roleForPreference("repair") == "mechanic",
    "the old repair preference displays as mechanic")
assert(Catalog.roleForPreference("patrol") == "guard",
    "the old patrol preference displays as guard")
assert(Catalog.roleForPreference("auto") == nil,
    "automatic has no role bundle")
assert(Catalog.roleForPreference("rest") == nil,
    "rest has no role bundle")

for _, legacy in ipairs({
    "auto", "guard", "patrol", "cooking", "farming", "woodwork",
    "barricade", "hauling", "repair", "rest",
}) do
    assert(Catalog.isBasePreference(legacy) == true,
        "legacy preference " .. legacy .. " remains valid")
end

print("Base roles PASS roles=9 schedules=24 gear=9 legacy=10")
