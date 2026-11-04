-- One palette owns every highlight colour. Two things matter and both are
-- computed from the tables the renderer actually reads, not from a copy: a colour
-- has to say something (relevance) and has to be tellable apart from its
-- neighbours (distance).
local H = assert(rawget(_G, "KnoxBaseHighlights"), "the highlight palette is loaded")
assert(type(H.workColour) == "function", "work colours are exported")
assert(type(H.storageColour) == "function", "storage colours are exported")

local WORK, STORAGE = H.WORK_COLOURS, H.STORAGE_COLOURS
assert(type(WORK) == "table" and type(STORAGE) == "table", "both families are tables")

local function distance(a, b)
    local dr, dg, db = a.r - b.r, a.g - b.g, a.b - b.b
    return math.sqrt(dr * dr + dg * dg + db * db)
end

local function pairMin(family)
    local names, worst, where = {}, 9, ""
    for name in pairs(family) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        for j = i + 1, #names do
            local d = distance(family[names[i]], family[names[j]])
            if d < worst then worst, where = d, names[i] .. "/" .. names[j] end
        end
    end
    return worst, where, #names
end

-- Every work area the planner can create has a colour, and the caller's alpha is
-- the one that is drawn.
for _, zoneType in ipairs({ "guard", "patrol", "farming", "woodcutting", "log_processing",
    "corpse", "cooking", "repair", "general" }) do
    local colour = H.workColour(zoneType, 0.85)
    assert(colour ~= nil, "work zone has a colour: " .. zoneType)
    assert(colour.a == 0.85, "the caller keeps control of alpha: " .. zoneType)
end

-- Every storage role the filter can hold has a colour of its own.
for _, role in ipairs({ "food", "water", "medical", "weapons", "ammunition", "tools",
    "building", "farming", "fuel", "clothing", "junk", "supplies" }) do
    local colour = H.storageColour(role, 0.85)
    assert(colour ~= nil, "storage role has a colour: " .. role)
    assert(colour.a == 0.85, "the caller keeps control of alpha: " .. role)
end

-- Distinguishable: nine work areas, twelve storage roles, and no two of either
-- family closer than 0.30, with the two families never closer than 0.25.
local workMin, workWhere, workCount = pairMin(WORK)
assert(workCount == 9, "nine work colours, got " .. tostring(workCount))
assert(workMin >= 0.30, "work areas are distinguishable, closest " .. workWhere
    .. " at " .. string.format("%.3f", workMin))

local storeMin, storeWhere, storeCount = pairMin(STORAGE)
assert(storeCount == 12, "twelve storage colours, got " .. tostring(storeCount))
assert(storeMin >= 0.30, "storage roles are distinguishable, closest " .. storeWhere
    .. " at " .. string.format("%.3f", storeMin))

local crossMin, crossWhere = 9, ""
for workName, workColour in pairs(WORK) do
    for storeName, storeColour in pairs(STORAGE) do
        local d = distance(workColour, storeColour)
        if d < crossMin then crossMin, crossWhere = d, workName .. "/" .. storeName end
    end
end
assert(crossMin >= 0.25, "an area is not mistakeable for a store square, closest " .. crossWhere
    .. " at " .. string.format("%.3f", crossMin))

-- Relevant: the colour says what the place is for before it says anything else.
assert(WORK.guard.r > 0.8 and WORK.guard.g < 0.25 and WORK.guard.b < 0.25,
    "a guard post reads as a threat colour")
assert(WORK.repair.b > 0.85 and WORK.repair.r < 0.2, "the workshop is blue")
assert(WORK.farming.g > 0.7 and WORK.farming.b < 0.1, "a crop area is lime")
assert(WORK.cooking.r > 0.8 and WORK.cooking.b > 0.4 and WORK.cooking.g < 0.3,
    "the kitchen is magenta")
local corpseSpread = math.max(WORK.corpse.r, WORK.corpse.g, WORK.corpse.b)
    - math.min(WORK.corpse.r, WORK.corpse.g, WORK.corpse.b)
assert(corpseSpread < 0.1, "the corpse zone is neutral, spread " .. string.format("%.3f", corpseSpread))

assert(STORAGE.water.b > 0.9 and STORAGE.water.b > STORAGE.water.g + 0.2, "water is azure")
assert(STORAGE.food.g > 0.9 and STORAGE.food.g > STORAGE.food.r + 0.4, "food is green")
assert(STORAGE.medical.r > 0.9 and STORAGE.medical.g > 0.5 and STORAGE.medical.g < 0.65,
    "medicine is rose")
assert(STORAGE.weapons.r < 0.5 and STORAGE.weapons.g < 0.1, "the weapon cupboard is dark maroon")
assert(STORAGE.ammunition.r > 0.9 and STORAGE.ammunition.g > 0.7 and STORAGE.ammunition.b < 0.2,
    "ammunition is brass")
assert(STORAGE.fuel.r > 0.65 and STORAGE.fuel.g < 0.35 and STORAGE.fuel.b < 0.1,
    "fuel is dark orange")
assert(STORAGE.clothing.b > 0.95 and STORAGE.clothing.r > 0.7, "clothing is violet")
assert(STORAGE.junk.r < 0.35 and math.abs(STORAGE.junk.r - STORAGE.junk.b) < 0.1,
    "junk is dark grey")

-- An unknown id still paints something: a renamed type is a wrong colour, never
-- no colour at all.
assert(H.storageColour("not_a_role", 0.5).r == STORAGE.supplies.r,
    "an unknown storage role falls back to supplies")
assert(H.workColour("not_a_zone", 0.5).r == WORK.general.r,
    "an unknown work type falls back to general")

-- The tokens the two selectors share are exported and opaque enough to see.
for _, token in ipairs({ "BOUNDARY_COLOUR", "OVERLAP_COLOUR", "CONFLICT_COLOUR",
    "INVALID_COLOUR" }) do
    local colour = H[token]
    assert(type(colour) == "table", "shared token is exported: " .. token)
    assert(colour.a ~= nil and colour.a > 0 and colour.a <= 1, "token has an alpha: " .. token)
end

print("zone_colours ok")
