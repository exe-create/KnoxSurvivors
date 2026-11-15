-- Live harness for the shared zombie list at the three routed consumers:
-- nearbyRetreatThreats, shouldRemainStealthy and the combat-barrier scan.
-- KS_RETREAT / KS_STEALTH / KS_INSTALL are the real production functions; the
-- cell counts every direct getZombieList call.
local saved = {
    getCell = getCell, KnoxZombieAwareness = KnoxZombieAwareness,
    KnoxSettings = KnoxSettings, nearbyHostileHumans = nearbyHostileHumans,
    distanceSquared = distanceSquared, isCorpseProxy = isCorpseProxy,
    KnoxCombatPositioning = KnoxCombatPositioning,
}

local reads, list = 0, { size = function() return 0 end }
local cell = {
    getZombieList = function() reads = reads + 1 return list end,
    getGridSquare = function() return nil end,
}
getCell = function() return cell end
KnoxZombieAwareness = { zombieList = KS_ZOMBIE_LIST }
KnoxSettings = { cautiousTravel = function() return true end }
nearbyHostileHumans = function() return {} end
distanceSquared = function() return 0 end
isCorpseProxy = function() return false end

local origin = {
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
    isBlockedTo = function() return true end,
    isHoppableTo = function() return false end,
    getRoom = function() return nil end,
}
local destination = {
    getX = function() return 1 end, getY = function() return 0 end,
    getZ = function() return 0 end,
}
local self1 = {
    id = "s1", currentTicks = 7,
    character = { getCurrentSquare = function() return origin end },
}
local positioningSelf = {
    character = self1.character,
    combatTarget = {
        getCurrentSquare = function() return destination end,
        isDead = function() return false end,
    },
    combatBarrier = nil,
    bridge = {
        resetNpcCombat = function() end, cancelNpcMove = function() end,
        tickNpc = function() return "" end, moveNpc = function() return "" end,
    },
}
local Controller = {}
KnoxCombatPositioning.install(Controller, { canOpen = function() return true end,
    free = function() return true end })
KnoxCombatPositioning.blockedEdge = function() return true end
KnoxCombatPositioning.barrierPolicy = function() return "hold" end

KS_RETREAT(self1, 8)
KS_STEALTH(self1)
Controller.handleCombatBarrier(positioningSelf, 7)
local routed = reads
assert(routed == 1,
    "three consumers in one tick share a single cell read, got " .. tostring(routed))

self1.currentTicks = 8
KS_RETREAT(self1, 8)
local afterTick = reads
assert(afterTick == 2,
    "a new tick reads the cell again, got " .. tostring(afterTick))

KnoxZombieAwareness = nil
KS_STEALTH(self1)
local fallback = reads - afterTick
assert(fallback == 1,
    "the direct-read fallback still works without awareness, got " .. tostring(fallback))

local beforeOldPath = reads
cell:getZombieList()
cell:getZombieList()
cell:getZombieList()
local oldPath = reads - beforeOldPath
assert(oldPath == 3, "the pre-change shape reads the cell three times, got " .. tostring(oldPath))

getCell = saved.getCell
KnoxZombieAwareness = saved.KnoxZombieAwareness
KnoxSettings = saved.KnoxSettings
nearbyHostileHumans = saved.nearbyHostileHumans
distanceSquared = saved.distanceSquared
isCorpseProxy = saved.isCorpseProxy
KnoxCombatPositioning = saved.KnoxCombatPositioning

KS_SHARED_LIST_RECEIPT = "routed_reads=" .. tostring(routed)
    .. " new_tick_reads=" .. tostring(afterTick)
    .. " fallback_direct_reads=" .. tostring(fallback)
    .. " old_path_reads=" .. tostring(oldPath)
