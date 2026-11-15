local Catalog = assert(KnoxDevSpectateCatalog)

local function check(facts, primary, ...)
    local described = Catalog.describe(facts)
    assert(described.primary == primary,
        "primary " .. tostring(described.primary) .. " expected " .. tostring(primary))
    assert(Catalog.matches("any", described), "any must match every survivor")
    for _, tag in ipairs({ ... }) do
        assert(Catalog.matches(tag, described),
            "filter " .. tag .. " missing from primary " .. tostring(primary))
    end
end

check({}, "solo", "solo")
check({ groupMembers = 1 }, "solo", "solo")
check({ creatorProfile = "police" }, "police", "solo", "police")
check({ originContext = "law_enforcement" }, "police", "police")
check({ factionBackground = "military", inFaction = true }, "military", "faction", "military")
check({ factionBackground = "law_enforcement", inFaction = true, groupMembers = 4 },
    "police", "faction", "group", "police")
check({ factionId = "faction-1", groupMembers = 3 }, "faction", "faction", "group")
check({ groupMembers = 2 }, "group", "group")
check({ eventPolicy = "scientists", inFaction = true }, "faction", "faction", "other")
assert(not Catalog.matches("military", Catalog.describe({})), "solo is not military")
assert(not Catalog.matches("other", Catalog.describe({ creatorProfile = "police" })),
    "police is not other")
assert(Catalog.filterLabel("police") == "Police", "police label")
assert(Catalog.filterLabel("missing") == "All", "unknown filter falls back to All")
assert(Catalog.kindLabel(Catalog.describe({}), {}) == "Solo", "solo kind label")
assert(Catalog.kindLabel(Catalog.describe({ groupMembers = 3 }), { groupMembers = 3 })
    == "Group of 3", "group count label")
assert(Catalog.kindLabel(Catalog.describe({ groupMembers = 3 }),
    { groupName = "Carter household", groupMembers = 3 }) == "Group: Carter household",
    "group name label")
assert(Catalog.kindLabel(Catalog.describe({ inFaction = true }),
    { factionName = "Rosewood Police" }) == "Faction: Rosewood Police",
    "faction name label")
assert(Catalog.kindLabel(Catalog.describe({ factionBackground = "military", inFaction = true }), {})
    == "Military", "military kind label")
print("DEV SPECTATE CATALOG OK")
