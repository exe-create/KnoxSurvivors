local probe = assert(storageCacheProbe)
local storage = probe.storage
local oldGetCell, oldClock = getCell, getTimestampMs
getTimestampMs = function() return 100 end
local function makeCell(minZ, maxZ, available)
    local cell = { scans = 0 }
    cell.getMinZ = function() return minZ end
    cell.getMaxZ = function() return maxZ end
    cell.getGridSquare = function(self, x, y, z)
        self.scans = self.scans + 1
        local container = available[x .. ":" .. y .. ":" .. z]
        if container == nil then return nil end
        local object = { getContainerCount = function() return 1 end,
            getContainerByIndex = function() return container end, getObjectIndex = function() return 0 end }
        local objects = { size = function() return 1 end, get = function() return object end }
        return { getObjects = function() return objects end,
            getX = function() return x end, getY = function() return y end, getZ = function() return z end }
    end
    return cell
end
local function container()
    return { getType = function() return "crate" end, isExistYet = function() return true end }
end
local c1, c2, bottom, top = container(), container(), container(), container()
local cell = makeCell(-3, 12, { ["0:0:0"] = c1, ["1:0:0"] = c2,
    ["10:0:-3"] = bottom, ["10:0:12"] = top })
getCell = function() return cell end
local base = { id = "bounds-width", territory = { minX = 0, minY = 0, width = 1, height = 1, z = 0 } }
local first = storage.operationalPolicies(base)
assert(#first == 1 and first[1].container == c1 and cell.scans == 1, "width one sees first container")
base.territory.width = 2
local wider = storage.operationalPolicies(base)
assert(#wider == 2 and cell.scans == 3, "width change rescans effective bounds")
local before = cell.scans
storage.operationalPolicies(base)
assert(cell.scans == before, "unchanged effective bounds use cache")
local floors = { id = "bounds-floors", territory = { minX = 10, maxX = 10, minY = 0, maxY = 0,
    minZ = -3, maxZ = -3 } }
local low = storage.operationalPolicies(floors)
assert(#low == 1 and low[1].container == bottom, "explicit lower floor is scanned")
floors.territory.minZ, floors.territory.maxZ = 12, 12
local high = storage.operationalPolicies(floors)
assert(#high == 1 and high[1].container == top, "changed explicit floor range rescans")
floors.territory.minZ, floors.territory.maxZ, floors.territory.allFloors = nil, nil, true
local all = storage.operationalPolicies(floors)
assert(#all == 2 and all[1].container == bottom and all[2].container == top,
    "native floor bounds discover only the two actual containers")
local replacementContainer = container()
cell = makeCell(-3, 12, { ["0:0:0"] = replacementContainer })
base.territory.width = 1
local replacement = storage.operationalPolicies(base)
assert(cell.scans == 1 and #replacement == 1 and replacement[1].container == replacementContainer,
    "a replacement cell cannot reuse old cell objects")
local fallbackContainer = container()
cell = makeCell(nil, nil, { ["7:0:4"] = fallbackContainer })
cell.getMinZ = function() error("not available") end
local fallback = { id = "bounds-fallback", territory = { minX = 7, maxX = 7, minY = 0, maxY = 0,
    z = 4, allFloors = true } }
local known = storage.operationalPolicies(fallback)
assert(cell.scans == 1 and #known == 1 and known[1].container == fallbackContainer,
    "unavailable native bounds scan only the known floor")
fallback.territory.z = nil
assert(#storage.operationalPolicies(fallback) == 0 and cell.scans == 1,
    "no known floor does not guess a range")
getCell, getTimestampMs = oldGetCell, oldClock
print("Storage native bounds PASS width=true floors=true native=true cell=true fallback=true")
