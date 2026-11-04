-- Off-screen evidence: a real death leaves a findable trace, an abstract one
-- does not invent a place.
local P = KnoxPersistence

local function traceCount()
    return #P.getTraceSites()
end

local function lastTrace()
    local sites = P.getTraceSites()
    return sites[#sites]
end

local before = traceCount()

local loaded = assert(P.allocateWorldSurvivor(
    { x = 40, y = 50, z = 0, key = "trace-loaded", region = "TR" }, 20))
assert(P.markSurvivorDead(loaded, 21, "world_death",
    { x = 40.6, y = 50.2, z = 0, locationSource = "loaded", corpseState = "native_pending" }))
assert(traceCount() == before + 1, "a death at a known square records one trace")
local site = lastTrace()
assert(site.kind == "fight", "a death is a fight trace")
assert(site.x == 40 and site.y == 50 and site.z == 0, "the trace is floored to the tile")
assert(site.visited == false, "the trace starts unvisited so it can materialize")
assert(tonumber(site.atHours) == 21, "the trace carries the death time")

-- Recording the same death again must not litter the world.
assert(P.markSurvivorDead(loaded, 22, "world_death", { x = 41, y = 51 }) == true)
assert(traceCount() == before + 1, "a repeated death call records nothing new")

-- An unloaded death has no square. It must not guess one.
local logical = assert(P.allocateWorldSurvivor(
    { x = 60, y = 70, z = 0, key = "trace-logical", region = "TR" }, 20))
assert(P.markSurvivorDead(logical, 21, "unloaded_survival",
    { locationSource = "logical", corpseState = "logical_only" }))
assert(traceCount() == before + 1, "a logical death records no trace")

-- A caller with no evidence at all is also silent.
local bare = assert(P.allocateWorldSurvivor(
    { x = 80, y = 90, z = 0, key = "trace-bare", region = "TR" }, 20))
assert(P.markSurvivorDead(bare, 21, "died"))
assert(traceCount() == before + 1, "a death without evidence records no trace")

-- Only the two real trace kinds are accepted.
assert(P.recordTraceSite("blood", 1, 1, 0, 21) == nil)
assert(P.recordTraceSite("breach", 12.9, 14.2, 1, 21) ~= nil, "breach is a real kind")
local breach = lastTrace()
assert(breach.kind == "breach" and breach.x == 12 and breach.y == 14 and breach.z == 1)

-- Repeated evidence from one room in the same hour is one trace.
local stacked = traceCount()
assert(P.recordTraceSite("breach", 13, 15, 1, 21.4) ~= nil)
assert(traceCount() == stacked, "a second breach in the same room adds no site")
assert(P.recordTraceSite("breach", 40, 40, 1, 21) ~= nil)
assert(traceCount() == stacked + 1, "a breach elsewhere is its own site")
assert(P.recordTraceSite("breach", 13, 15, 1, 40) ~= nil)
assert(traceCount() == stacked + 2, "an hour later the same room is a new trace")

-- Existing sites stay readable copies, so a consumer cannot corrupt the store.
local copy = P.getTraceSites()
copy[1].visited = true
assert(P.getTraceSites()[1].visited ~= true, "trace readers get copies")

print("Death trace PASS loaded=true once=true logical=false breach=true")
