-- The creator's marked cast walks in with a new character: the spawn path hands
-- the reconcile pass fresh ids (a pending marked spouse reservation, a
-- companion stash), and the spouse pass places each one on a free tile beside
-- the player exactly once. A reload never yanks anyone anywhere.
local C = assert(KnoxCreator)
local S = assert(KnoxSpouseStart)
local oldP, oldWorld = KnoxPersistence, KnoxWorldPopulation
local oldCell, oldSpecific, oldSettings, oldRuntime = getCell, getSpecificPlayer,
    rawget(_G, "KnoxSettings"), KnoxSurvivorRuntime
local oldLoad, oldPrepared = C.load, C.preparedPopulation
local state, origins, records, alive, nextId = {}, {}, {}, {}, 0
local modData = {}
local originSquare = { getX = function() return 100 end, getY = function() return 100 end,
    getZ = function() return 0 end, isSomethingTo = function() return false end }
local function fakeSquare()
    return { canStand = function() return true end,
        getMovingObjects = function() return { size = function() return 0 end } end }
end
getCell = function()
    return { getGridSquare = function(_, x, y, z) return fakeSquare() end }
end
local player = {
    getCurrentSquare = function() return originSquare end,
    isDead = function() return false end,
    getHoursSurvived = function() return 0 end,
    getModData = function() return modData end,
    getDescriptor = function() return nil end,
    isFemale = function() return false end,
}
getSpecificPlayer = function() return player end
KnoxSettings = { spawnWithSpouse = function() return false end }
KnoxSurvivorRuntime = { getCharacter = function() return nil end }
KnoxWorldPopulation = { spawnCatalog = function() return { origins = {
    { source = "world_building", buildingId = "starthome", key = "starthome1",
        x = 50, y = 50, z = 0, household = true, residential = true },
    { source = "world_building", buildingId = "starthome", key = "starthome2",
        x = 51, y = 50, z = 0, household = true, residential = true },
} } end }
KnoxPersistence = {
    getPopulationState = function() return state end,
    getAllWorldSurvivorIds = function() local ids = {} for id in pairs(origins) do ids[#ids + 1] = id end return ids end,
    getLivingWorldSurvivorIds = function() local ids = {} for id in pairs(alive) do if alive[id] then ids[#ids + 1] = id end end return ids end,
    getUsedWorldOriginKeys = function() return {} end,
    getSurvivorOrigin = function(id) return origins[id] end,
    getSurvivorCreatorRecord = function(id) return records[id] end,
    getRecord = function(id) return state[id] end,
    isSurvivorAlive = function(id) return alive[id] == true end,
    allocateWorldSurvivor = function(origin)
        nextId = nextId + 1
        local id = "start-" .. nextId
        origins[id], alive[id] = origin, true
        state[id] = { origin = origin, alive = true }
        return id
    end,
    setSurvivorCreatorRecord = function(id, record) records[id] = record return true end,
    setPlayerCompanion = function() return true end,
    ensurePlayerId = function() return "player-1" end,
    getPlayerRelationship = function() return nil end,
}
local defs = {}
assert(C.addFaction(defs, "Start Home", "household"))
local roster = {}
assert(C.add(roster, { name = "Wedded Wilma" }))
assert(C.add(roster, { name = "Chum Charlie" }))
roster[1].faction, roster[1].startSpouse = defs[1].id, true
roster[2].faction, roster[2].startCompanion = defs[1].id, true
local group = C.newGroup()
group.defs = defs
C.load = function() return roster, group end
C.preparedPopulation = nil
local count, degraded, reason = C.spawnPending()
assert(count == 2 and degraded == 0 and reason == "ready",
    "the marked cast allocates, got " .. tostring(reason))
local spouseId = state.creatorRoster[defs[1].id .. ":Wedded Wilma"]
local chumId = state.creatorRoster[defs[1].id .. ":Chum Charlie"]
assert(spouseId ~= nil and chumId ~= nil, "both marks have receipts")
local reservation = modData.KnoxSurvivors.spouseStart
assert(type(reservation) == "table" and reservation.status == "pending"
    and reservation.id == spouseId and reservation.marked == true,
    "a fresh marked spouse stays pending for the spouse pass")
local stash = modData.KnoxSurvivors.creatorStart
assert(type(stash) == "table" and #stash.companionIds == 1
    and stash.companionIds[1] == chumId,
    "a fresh marked companion is stashed for the reconcile pass")
-- A reload with the same file allocates nothing new and stashes nothing: the
-- world already holds these people, so nobody is walked anywhere twice.
C.preparedPopulation = nil
modData.KnoxSurvivors.spouseStart, modData.KnoxSurvivors.creatorStart = nil, nil
count = C.spawnPending()
assert(count == 0 and modData.KnoxSurvivors.creatorStart == nil
    and modData.KnoxSurvivors.spouseStart.status == "complete",
    "a reload writes no new stash and closes the spouse marker")
-- Placement replays the fresh-run output proven above (the reload run cleared
-- it): the sandbox spouse flag is off, so only the marks may place.
modData.KnoxSurvivors.spouseStart = { status = "pending", id = spouseId, marked = true }
modData.KnoxSurvivors.creatorStart = { companionIds = { chumId } }
local placed = {}
local function activate(id, square, record)
    placed[#placed + 1] = { id = id, square = square, record = record }
    return true
end
assert(S.update(player, activate) == true, "the marked spouse is placed")
assert(#placed == 1 and placed[1].id == spouseId and placed[1].square ~= nil
    and placed[1].record ~= nil,
    "the spouse lands beside the player with their record")
assert(modData.KnoxSurvivors.spouseStart.status == "complete",
    "placement closes the reservation")
assert(S.updateMarkedCompanions(player, activate) == true,
    "the marked companion is placed")
assert(#placed == 2 and placed[2].id == chumId and placed[2].square ~= nil,
    "the companion lands beside the player")
assert(modData.KnoxSurvivors.creatorStart == nil, "the stash is cleared")
assert(S.updateMarkedCompanions(player, activate) == false,
    "an empty stash places nothing")
-- A body the world woke first is kept, not moved.
modData.KnoxSurvivors.spouseStart = { status = "pending", id = spouseId, marked = true }
KnoxSurvivorRuntime = { getCharacter = function(id)
    return id == spouseId and {} or nil
end }
placed = {}
assert(S.update(player, activate) == true, "a standing spouse is adopted")
assert(#placed == 0 and modData.KnoxSurvivors.spouseStart.status == "complete",
    "nobody already standing is moved")
-- A failed companion placement stays stashed for the next tick.
modData.KnoxSurvivors.creatorStart = { companionIds = { chumId } }
KnoxSurvivorRuntime = { getCharacter = function() return nil end }
assert(S.updateMarkedCompanions(player, function() return false end) == false,
    "a refused placement reports nothing placed")
assert(#modData.KnoxSurvivors.creatorStart.companionIds == 1,
    "a refused placement stays stashed")
-- The random reservation still needs the sandbox flag.
modData.KnoxSurvivors.spouseStart = { status = "pending", id = "random-x" }
placed = {}
assert(S.update(player, activate) == false and #placed == 0,
    "no flag, no random spouse")
-- A fresh random reservation waits a pass: the creator's spawn pass runs
-- later in the same pass and adopts a marked spouse first, so placing now
-- would stand a random spouse beside the marked one.
KnoxSettings = { spawnWithSpouse = function() return true end }
modData.KnoxSurvivors.spouseStart = nil
placed = {}
assert(S.update(player, activate) == false and #placed == 0,
    "a fresh random reservation waits a pass")
assert(type(modData.KnoxSurvivors.spouseStart) == "table"
    and modData.KnoxSurvivors.spouseStart.status == "pending"
    and modData.KnoxSurvivors.spouseStart.marked ~= true,
    "the random reservation is still written")
assert(S.update(player, activate) == true and #placed == 1,
    "the random reservation acts on the next pass")
C.load, C.preparedPopulation = oldLoad, oldPrepared
KnoxPersistence, KnoxWorldPopulation = oldP, oldWorld
getCell, getSpecificPlayer, KnoxSurvivorRuntime = oldCell, oldSpecific, oldRuntime
rawset(_G, "KnoxSettings", oldSettings)
print("Creator start placement PASS markedSpouse=true markedCompanion=true noRejoinYank=true flagIndependent=true")
