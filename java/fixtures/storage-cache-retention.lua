local probe = assert(storageCacheProbe)
local storage, cache = probe.storage, probe.cache
local oldGetCell, oldClock = getCell, getTimestampMs
local now, scans = 0, 0
getTimestampMs = function() return now end
local container = { getType = function() return "crate" end, isExistYet = function() return true end }
local object = {
    getContainerCount = function() return 1 end,
    getContainerByIndex = function() return container end,
    getObjectIndex = function() return 0 end,
}
local objects = { size = function() return 1 end, get = function() return object end }
local cell = { getGridSquare = function(self, x, y, z)
    scans = scans + 1
    return { getObjects = function() return objects end,
        getX = function() return x end, getY = function() return y end, getZ = function() return z end }
end }
getCell = function() return cell end
local function baseAt(x)
    return { id = "cache-test", territory = { minX = x, maxX = x, minY = 0, maxY = 0, z = 0 } }
end
local function count()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end
local first, second, third = baseAt(1), baseAt(2), baseAt(3)
local firstResult = storage.operationalPolicies(first)
assert(scans == 1 and #firstResult == 1 and firstResult[1].container == container,
    "first geometry scans and returns its real container")
now = 5000
storage.operationalPolicies(second)
assert(scans == 2 and count() == 2, "two fresh geometries remain cached")
local again = storage.operationalPolicies(first)
assert(scans == 2 and #again == 1 and again[1].container == firstResult[1].container,
    "fresh hit preserves the container without a scan")
now = 10000
storage.operationalPolicies(third)
assert(scans == 3 and count() == 2, "a miss prunes expired geometry and preserves fresh entries")
now = 14999
storage.operationalPolicies(second)
assert(scans == 3, "entry remains fresh just before TTL")
now = 15000
storage.operationalPolicies(second)
assert(scans == 4 and count() == 2, "TTL boundary rescans and replaces expired entry")
now = 25000
storage.operationalPolicies(first)
assert(scans == 5 and count() == 1, "a later miss clears all expired geometries")
now = 26000
storage.operationalPolicies(second)
assert(scans == 6 and count() == 2, "two recent geometries are cached before rewind")
now = 24000
storage.operationalPolicies(first)
assert(scans == 7 and count() == 1, "clock rewind rescans and removes future-dated entries")
for _, entry in pairs(cache) do
    assert(entry.at == 24000, "only the new clock baseline remains")
end
now = 24001
storage.operationalPolicies(first)
assert(scans == 7, "the new baseline supports fresh hits after rewind")
getCell, getTimestampMs = oldGetCell, oldClock
print("Storage cache retention PASS fresh=true expiry=true boundary=true rewind=true")
