-- The base roster is built from the same duty records the per-survivor menu
-- writes, so these assertions cover what the roster can expose and what the new
-- fetch order will accept.
local Catalog = assert(KnoxOrderCatalog)

-- One row per resident, carrying exactly the state the menu toggles.
local roster = Catalog.baseRosterModel({ "beta", "alpha" }, function(id)
    if id == "alpha" then
        return { mode = "base", jobPreference = "guard", allowLootRuns = false,
            baseSupplyOrder = { kind = "find_food" } }
    end
    return { mode = "base", allowLootRuns = true }
end)
assert(#roster == 2, "every resident gets a roster row")
assert(roster[1].id == "beta" and roster[1].jobPreference == nil,
    "a resident with no explicit role falls to auto")
assert(roster[1].stayHome == false, "surplus supply consent is readable")
assert(roster[2].id == "alpha" and roster[2].jobPreference == "guard",
    "job preference is exposed on the roster")
assert(roster[2].stayHome == true, "stay-home is exposed on the roster")
assert(roster[2].hasSupplyOrder == true, "an existing supply order is exposed so it can be cancelled")

-- The full role list is the one the menu already builds from.
assert(#Catalog.basePreferenceOrder > 5, "the roster offers the full role list")

-- A fetch order names one item type, and only the game's own shape is accepted.
assert(Catalog.normalizeItemType("Base.Axe") == "Base.Axe")
assert(Catalog.normalizeItemType("  Base.Axe  ") == "Base.Axe", "surrounding space is trimmed")
assert(Catalog.normalizeItemType("Axe") == nil, "a bare name is not a type")
assert(Catalog.normalizeItemType("") == nil)
assert(Catalog.normalizeItemType("Base. With Space") == nil)
assert(Catalog.normalizeItemType(42) == nil)

-- The fetch order travels through the supply-order writer that already owns
-- trips, permissions and cancel; it is not a second order store.
local persistence = assert(KnoxPersistence, "the persistence owner is loaded")
assert(type(persistence.setBaseSupplyOrder) == "function",
    "the fetch order is written through the existing supply-order writer")
assert(type(persistence.clearBaseSupplyOrder) == "function",
    "the existing cancel path clears it")
