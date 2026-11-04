-- N2: loose items on the storage floor count toward a shortage, but they stay
-- reported separately so a base with no shelf still looks like a base with no
-- shelf.
local P = KnoxBaseSupplyPlanner

assert(type(P.stockTotals) == "function", "stockTotals must exist")

local summary = {
    totals = { food = 2, water = 0, building = 1 },
    floorTotals = { food = 3, building = 4, tools = 1 },
    floorSquares = 7,
    loadedPolicies = 2,
}
local merged = P.stockTotals(summary)
assert(merged.food == 5, "floor food adds to the shelf")
assert(merged.water == 0)
assert(merged.building == 5)
assert(merged.tools == 1, "a floor-only category is still stock")
assert(summary.totals.food == 2, "the summary itself is not mutated")
assert(summary.totals.building == 1)

-- A shortage that the floor already covers is not a shortage.
local targets = nil
local residents = 1
local before = P.chooseShortage({ food = 0 }, residents, targets)
local after = P.chooseShortage(merged, residents, targets)
assert(before == "find_food", "empty shelves do ask for a food run")
assert(after ~= "find_food", "a pile of food on the floor stops the run")

-- Missing or malformed input is empty stock, never a crash or a negative.
-- The harness has no global next(), so count pairs directly.
local function pairsIn(table_)
    local count = 0
    for _ in pairs(table_) do count = count + 1 end
    return count
end
assert(pairsIn(P.stockTotals(nil)) == 0)
assert(pairsIn(P.stockTotals({})) == 0)
local odd = P.stockTotals({ totals = { food = -4, water = "x" }, floorTotals = { water = 2 } })
assert(odd.food == 0, "a negative count is not stock")
assert(odd.water == 2, "a readable floor count survives an unreadable shelf count")

print("Floor stock PASS merge=true separate=true shortage=true guarded=true")
