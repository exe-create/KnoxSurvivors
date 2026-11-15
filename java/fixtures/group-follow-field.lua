-- A spawned party must follow its own leader in the field. The base branch in
-- think walked every member home the moment the group's leader claimed a site,
-- so a party that spawned outdoors only ever reunited indoors.
local C = assert(KnoxAutonomyController)
local Persistence = assert(KnoxPersistence)
local previousRecoveryBusy = C.isNativeRecoveryBusy
C.isNativeRecoveryBusy = function() return false end
local previousVehicles = rawget(_G, "KnoxCompanionVehicles")
_G.KnoxCompanionVehicles = nil
local previousIds = Persistence.getBaseResidentIds
Persistence.getBaseResidentIds = function() return {} end
local previousNeeds = KnoxSurvivorNeeds
KnoxSurvivorNeeds = setmetatable({
    decide = function() return { kind = "roam", state = "idle" } end,
    isMedicalCare = function() return false end,
    thresholds = { lowEndurance = 0.2, fatigue = 0.8 },
}, { __index = previousNeeds })
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousGroupSupport = rawget(_G, "KnoxGroupSupport")
KnoxGroupSupport = { mostUrgentNeed = function() return nil end }
local previousGetCell = getCell
local previousManager = rawget(_G, "KnoxBaseManager")
local previousCamps = rawget(_G, "KnoxFactionCamps")
local previousPlayerCount = rawget(_G, "getNumActivePlayers")
local previousPlayerAt = rawget(_G, "getSpecificPlayer")
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return nil end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
        isBlockedTo = function() return false end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
        getRoom = function() return nil end,
        getBuilding = function() return nil end,
    }
end
getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return square(x, y, z) end,
        getZombieList = function() return { size = function() return 0 end } end,
    }
end
local function body(x, y)
    return setmetatable({
        getCurrentSquare = function() return square(x, y, 0) end,
        getForwardDirectionX = function() return 0 end,
        getForwardDirectionY = function() return 1 end,
        getCharacterActions = function() return { isEmpty = function() return true end } end,
    }, { __index = function() return function() return false end end })
end

local moves, baseReturns, campReturns = {}, 0, 0
local function bridge()
    local function start(_, id, target)
        moves[#moves + 1] = target
        return "MOVE_STARTED"
    end
    return setmetatable({
        moveNpc = start,
        moveNpcWithPace = start,
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
        tickNpcCombat = function() return "COMBAT_WAITING" end,
        tickNpc = function() return "Succeeded" end,
    }, { __index = function() return function() return "" end end })
end

local function controller(fields, x, y)
    local c = {
        id = "group-field-fixture",
        state = "IDLE",
        nextThink = 0,
        nextThreatScan = 1000000,
        currentTicks = 0,
        counts = { needs = 0, combat = 0, failures = 0 },
        failedThreats = {},
        perceivedThreats = {},
        selfCareRetryAt = {},
        character = body(x, y),
        bridge = bridge(),
        baseId = "field-base",
        base = { id = "field-base", home = { minX = 0, minY = 0, width = 4, height = 4, z = 0 } },
    }
    for key, value in pairs(fields) do c[key] = value end
    setmetatable(c, { __index = C })
    -- Existing early owners, detached exactly as the combat tick fixture does.
    for _, name in ipairs({ "observeGroupEntry", "recoverIdleAnimationLatch", "recoverFromDetached",
        "updateBaseTaskAction", "waitingForTransferActions", "tryAutomaticPlayerAid",
        "yieldBaseTaskForNeed", "yieldInventoryCleanupForNeed", "yieldAidForNeed",
        "yieldCollectionForNeed", "isSettlementSupplyEntry", "sharedMealPostureReady",
        "reconsiderEquipment", "beginGroupSupport", "beginInventoryCleanup", "beginEventTravel",
        "hasNeedEscort", "beginBattlefieldAid", "beginFollowerHygiene", "beginFollowerCompany",
        "applyGroupLeaderOrder", "beginGroupRegroup" }) do
        c[name] = function() return false end
    end
    c.checkSharedMeal = function() return false end
    c.applyPendingCombatPolicy = function() return true end
    c.tryBoardFollowVehicle = function() return false end
    c.canApplyDutyChange = function() return true end
    c.diag = function() end
    c.recordFailure = function() end
    c.finishDecision = function() end
    c.sayNeedIfGrouped = function() end
    c.suspendBaseTaskForThreat = function() end
    c.clearLifeIntent = function() end
    c.syncBaseSupplyRun = function() end
    c.applyResidentStayHome = function() end
    c.followScavengeParty = function() return false end
    c.runScavengeSortie = function() return false end
    c.resumeExternalBaseWork = function() return false end
    c.beginBaseMovement = function() baseReturns = baseReturns + 1 return true end
    c.beginCampMovement = function() campReturns = campReturns + 1 return true end
    return c
end

local atHome = false
KnoxBaseManager = { containsSquare = function(_, sq) return atHome end }
_G.KnoxFactionCamps = { contains = function() return true end }

local leader = body(8700, 8700)

-- 1. A member out in the field with its base already claimed follows the
--    leader instead of being sent home. It stands on its squad slot so the
--    real squadStep declines and the real think branch order is the subject.
moves, baseReturns = {}, 0
atHome = false
local travelling = controller({ groupLeader = leader, groupFormationSlot = 1, groupSize = 2 }, 8700, 8704)
travelling.groupMembers = { leader, travelling.character }
travelling:tick(100)
assert(#moves == 1, "a travelling member in the field follows its leader")
assert(baseReturns == 0, "the base branch must not walk a travelling member home")
assert(tostring(travelling.activeDecision) == "follow_group", "the follow owns the decision")
assert(tostring(travelling.state) == "GROUP_FOLLOW", "the follow owns the movement state")

-- 2. An obstacle failure set a retry; the member holds instead of walking
--    the same slot into the same obstacle again.
moves, baseReturns = {}, 0
local blocked = controller({
    groupLeader = leader, groupFormationSlot = 1, groupSize = 2,
    groupLeaderOrder = nil, nextFormationRefresh = 900, formationCommitUntil = 0,
}, 8700, 8704)
blocked.groupMembers = { leader, blocked.character }
blocked:tick(800)
assert(#moves == 0, "a failed formation route owns its retry time")
assert(tostring(blocked.state) == "GROUP_WAIT", "the member waits out the retry")

-- 3. Once the retry expires the same member walks the slot again.
moves, baseReturns = {}, 0
local resumed = controller({
    groupLeader = leader, groupFormationSlot = 1, groupSize = 2,
    groupLeaderOrder = nil, nextFormationRefresh = 700, formationCommitUntil = 0,
}, 8700, 8704)
resumed.groupMembers = { leader, resumed.character }
resumed:tick(800)
assert(#moves == 1, "a member resumes following when the retry expires")

-- 4. A member with no travel group still answers to its base.
moves, baseReturns = {}, 0
local loner = controller({}, 8750, 8750)
loner:tick(300)
assert(baseReturns == 1, "a member without a group still heads home")

-- 5. A camp is a temporary party site, not a settled home. A member with a
--    live leader follows it even while standing on its camp instead of
--    entering the camp idle loop and letting the leader walk away alone.
moves, campReturns = {}, 0
local camped = controller({
    groupLeader = leader, groupFormationSlot = 1, groupSize = 2,
    baseId = nil, base = nil,
    campId = "field-camp",
    camp = { id = "field-camp", home = { minX = 0, minY = 0, width = 4, height = 4, z = 0 } },
    campPosition = nil,
}, 8700, 8704)
camped.groupMembers = { leader, camped.character }
camped:tick(100)
assert(#moves == 1, "a camped member with a live leader follows it")
assert(campReturns == 0, "the camp loop must not own a member with a live leader")
assert(tostring(camped.activeDecision) == "follow_group", "the leader owns the camped member's decision")
assert(tostring(camped.state) == "GROUP_FOLLOW", "the camped member reaches the follow state")

-- 6. A spawned party in open country has neither a camp nor a base to send
--    it home; every linked member still takes the leader-slot move.
moves, baseReturns = {}, 0
local spawned = controller({
    groupLeader = leader, groupFormationSlot = 1, groupSize = 2,
    baseId = nil, base = nil,
}, 8700, 8704)
spawned.groupMembers = { leader, spawned.character }
spawned:tick(100)
assert(#moves == 1, "a non-camp spawned member in the field follows its leader")
assert(baseReturns == 0, "a non-camp member has no base owner to preempt follow")
assert(tostring(spawned.activeDecision) == "follow_group", "the spawned member's decision is follow")
assert(tostring(spawned.state) == "GROUP_FOLLOW", "the spawned member reaches the follow state")

-- 7. The durable leader id is enough to recover a fresh spawn whose
--    character pointer has not been rebuilt yet.  Without recovery the real
--    group branch is skipped and the member looks like an independent idler.
moves = {}
local previousRuntimeNow = rawget(_G, "KnoxSurvivorRuntime")
_G.KnoxSurvivorRuntime = {
    getCharacter = function(id) return id == "field-leader" and leader or nil end,
}
local unlinked = controller({
    groupLeaderId = "field-leader", groupFormationSlot = 1, groupSize = 2,
}, 8700, 8704)
unlinked.groupMembers = { leader, unlinked.character }
unlinked:tick(100)
assert(#moves == 1, "a follower recovers the leader character from its durable id")
assert(unlinked.groupLeader == leader, "the recovered character is the actual leader")
assert(tostring(unlinked.activeDecision) == "follow_group", "the recovered link owns follow")

-- 8. A grouped follower with a dead/wrong id must wait as a group member, not
--    silently become an independent roamer or idler.
moves = {}
local orphan = controller({
    groupLeaderId = "field-missing-leader", groupFormationSlot = 1, groupSize = 2,
}, 8700, 8704)
orphan.groupMembers = {}
orphan:tick(100)
assert(#moves == 0, "a broken leader link must not issue independent movement")
assert(tostring(orphan.state) == "GROUP_WAIT", "a broken leader link waits for repair")
assert(tostring(orphan.activeDecision) == "follow_group", "a broken link remains follow-owned")
assert(orphan.groupLeaderId == "field-missing-leader", "the durable id is preserved for repair")
_G.KnoxSurvivorRuntime = previousRuntimeNow

KnoxGroupSupport = previousGroupSupport
KnoxBaseManager = previousManager
_G.KnoxFactionCamps = previousCamps
getCell = previousGetCell
getNumActivePlayers = previousPlayerCount
getSpecificPlayer = previousPlayerAt
_G.KnoxSurvivorRuntime = previousRuntime
KnoxSurvivorNeeds = previousNeeds
Persistence.getBaseResidentIds = previousIds
C.isNativeRecoveryBusy = previousRecoveryBusy
_G.KnoxCompanionVehicles = previousVehicles
