-- County balance is proportional and player-independent, and the per-pass
-- building index must be reused instead of rebuilt for every allocation.
local W = assert(KnoxWorldPopulation, "population owner is loaded")
local choose = assert(W.chooseBalancedOrigin, "balancer is reachable")

local function region(key, originCount, buildingPrefix)
    local made = { key = key, name = key, origins = {} }
    for i = 1, originCount do
        made.origins[i] = {
            key = key .. ":" .. i,
            source = "world_building",
            buildingId = buildingPrefix .. tostring(i),
            context = "residential",
        }
    end
    made.opportunityCount = originCount
    return made
end

-- A crowded small county and a thin large one: share decides, not distance.
local near, far = region("near", 4, "a"), region("far", 8, "b")
local catalog = { regions = { near, far } }
local usedA = {}
local chosen = choose(catalog, usedA, { near = 2, far = 1 }, 0, nil)
assert(chosen ~= nil and string.sub(chosen.key, 1, 3) == "far",
    "the thinnest county by share is chosen, not the well-filled one")
assert(W.originIndex ~= nil and W.originIndex.used == usedA,
    "the per-pass building index is reused instead of rebuilt per allocation")

-- A new population pass brings a new `used` table, so the index rebuilds.
local usedB = {}
choose(catalog, usedB, { near = 0, far = 0 }, 1, nil)
assert(W.originIndex.used == usedB, "a new pass rebuilds the index")

-- Equal shares rotate on the persisted cursor instead of repeating a county.
local first, second = region("first", 2, "c"), region("second", 2, "d")
local tied = { regions = { first, second } }
local one = choose(tied, {}, {}, 0, nil)
local two = choose(tied, {}, {}, 1, nil)
assert(one ~= nil and two ~= nil and one.key ~= two.key,
    "equal shares rotate instead of repeating one county")

-- A county with no unused origin never wins a pick, however thin its share.
local spent, open = region("spent", 1, "e"), region("open", 1, "f")
local mixed = { regions = { spent, open } }
local picked = choose(mixed, { ["spent:1"] = true }, { spent = 9, open = 0 }, 0, nil)
assert(picked ~= nil and string.sub(picked.key, 1, 5) == "open:",
    "an exhausted county is skipped even when its share looks thin")

print("Population spread PASS thinnest_first=true tie_rotation=true exhausted_skipped=true index_reused=true")
