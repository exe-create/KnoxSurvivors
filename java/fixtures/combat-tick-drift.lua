-- Formation must hold between thinks. A member already committed to a slot keeps
-- reaching it on ticks where it does not think, so a moving leader cannot leave
-- it behind. Only Controller:tick is driven here.
local C = assert(KnoxAutonomyController)
local Persistence = assert(KnoxPersistence)
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")
local previousGetCell = getCell
local previousIds = Persistence.getBaseResidentIds
local previousRecoveryBusy = C.isNativeRecoveryBusy
local previousVehicles = rawget(_G, "KnoxCompanionVehicles")
C.isNativeRecoveryBusy = function() return false end
_G.KnoxCompanionVehicles = nil

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
        getCharacterActions = function() return { isEmpty = function() return true end } end,
    }, { __index = function() return function() return false end end })
end

local moves = {}
local function bridge()
    return setmetatable({
        moveNpc = function(_, id, target) moves[#moves + 1] = target return "MOVE_STARTED" end,
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
        tickNpcCombat = function() return "COMBAT_WAITING" end,
        tickNpc = function() return "Succeeded" end,
    }, { __index = function() return function() return "" end end })
end

local thoughts = 0
local function controller(fields, x, y)
    local c = {
        id = "drift-fixture",
        state = "IDLE",
        nextThink = 0,
        nextThreatScan = 1000000,
        currentTicks = 0,
        counts = { needs = 0, combat = 0, failures = 0 },
        failedThreats = {},
        selfCareRetryAt = {},
        character = body(x, y),
        bridge = bridge(),
    }
    for key, value in pairs(fields) do c[key] = value end
    setmetatable(c, { __index = C })
    c.observeGroupEntry = function() end
    c.checkSharedMeal = function() return false end
    c.recoverIdleAnimationLatch = function() end
    c.applyPendingCombatPolicy = function() return true end
    c.tryBoardFollowVehicle = function() return false end
    c.recoverFromDetached = function() return false end
    c.updateBaseTaskAction = function() return false end
    c.waitingForTransferActions = function() return false end
    c.tryAutomaticPlayerAid = function() return false end
    c.yieldBaseTaskForNeed = function() return false end
    c.yieldInventoryCleanupForNeed = function() return false end
    c.yieldAidForNeed = function() return false end
    c.yieldCollectionForNeed = function() return false end
    c.isSettlementSupplyEntry = function() return false end
    c.canApplyDutyChange = function() return true end
    c.sharedMealPostureReady = function() return false end
    c.think = function() thoughts = thoughts + 1 end
    return c
end

local leaderX, leaderY = 8700, 8700
local leader = body(8700, 8700)
leader.getCurrentSquare = function() return square(leaderX, leaderY, 0) end

-- 1. Drift: the member takes its slot, then keeps reaching it while the leader
-- moves, on a tick where no idle decision runs.
local drifting = controller({ id = "drift", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8712)
drifting.groupMembers = { leader, drifting.character }
drifting:tick(100)
assert(#moves == 1 and moves[1]:getY() == 8702, "the first think takes the formation slot")
drifting.nextThink = 400
leaderX, leaderY = 8700, 8704
drifting:tick(115)
assert(#moves == 2, "a committed member re-slots on a tick it does not think on")
assert(moves[2]:getY() == 8706, "the re-issued slot follows the leader's new position")
assert(thoughts == 0, "the between-think hold happens without an idle decision")

-- 2. In slot: still no movement, and the ordinary decision runs.
moves, thoughts = {}, 0
local settled = controller({ id = "settled", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8706)
settled.groupMembers = { leader, settled.character }
settled:tick(200)
assert(#moves == 0, "a member in its slot is not moved")
assert(thoughts == 1, "an in-slot member still takes its ordinary decision")

-- 3. Under fire the party widens its slots.
moves, thoughts = {}, 0
local pressed = controller({ id = "pressed", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8720)
pressed.groupMembers = { leader, pressed.character }
pressed.perceivedThreats = { enemy = {} }
pressed:tick(300)
assert(#moves == 1 and moves[1]:getY() == leaderY + 4, "a pressed party widens its slot")

-- 4. A broken-off member still re-forms on its next think.
moves, thoughts = {}, 0
local broke = controller({ id = "broke", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8760)
broke.groupMembers = { leader, broke.character }
broke.breakOffReason = "outnumbered"
broke:tick(400)
assert(#moves == 1, "a broken-off member re-forms on its next think")

-- 5. A resident party holds the same way through the base roster.
moves, thoughts = {}, 0
Persistence.getBaseResidentIds = function() return { "lead", "me" } end
_G.KnoxSurvivorRuntime = {
    getCharacter = function(id) return id == "lead" and leader or nil end,
}
local resident = controller({ id = "me", baseId = "base-drift" }, 8700, 8760)
resident:tick(500)
assert(#moves == 1, "the resident takes its slot on its think")
resident.nextThink = 900
leaderX, leaderY = 8700, 8700
resident:tick(515)
assert(#moves == 2 and moves[2]:getY() == 8702,
    "a committed resident re-slots between its thinks")
assert(thoughts == 0, "the resident hold needs no idle decision")

-- 6. Sprint: the leader moves on every tick and the think never fires inside
-- the window, yet the member keeps its target on the leader's current slot.
moves, thoughts = {}, 0
leaderX, leaderY = 8700, 8700
local sprinter = controller({ id = "sprint", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8860)
sprinter.groupMembers = { leader, sprinter.character }
sprinter:tick(700)
assert(#moves == 1 and moves[1]:getY() == 8702, "the sprinter takes its first slot")
sprinter.nextThink = 1000000
for step = 1, 20 do
    leaderY = 8700 + step
    sprinter:tick(700 + step)
    local aimed = moves[#moves]
    assert(aimed ~= nil and aimed:getX() == 8700 and aimed:getY() == 8702 + step,
        "a committed member keeps its target on the leader's moving slot")
end
assert(thoughts == 0, "the sprint hold needs no idle decision")

-- 7. The same sprint through the base roster for a resident party.
moves, thoughts = {}, 0
leaderX, leaderY = 8700, 8700
local residentSprinter = controller({ id = "me", baseId = "base-drift" }, 8700, 8860)
residentSprinter:tick(800)
assert(#moves == 1 and moves[1]:getY() == 8702, "the resident takes its first slot")
residentSprinter.nextThink = 1000000
for step = 1, 20 do
    leaderY = 8700 + step
    residentSprinter:tick(800 + step)
    local aimed = moves[#moves]
    assert(aimed ~= nil and aimed:getX() == 8700 and aimed:getY() == 8702 + step,
        "a committed resident keeps its target on the leader's moving slot")
end
assert(thoughts == 0, "the resident sprint hold needs no idle decision")

-- Long follows cross several commit windows, with both a sleeping think clock
-- and ordinary think opportunities on unchanged-target ticks. The member's
-- physical progress is doubled; all formation decisions still enter via tick.
for _, residentParty in ipairs({ false, true }) do
    for _, dueThinks in ipairs({ false, true }) do
        moves, thoughts = {}, 0
        leaderX, leaderY = 8700, 8700
        local follower = controller(residentParty and { id = "me", baseId = "base-drift" }
            or { id = "long-follow", groupLeader = leader, groupSize = 2,
                groupFormationSlot = 1 }, 8700, 8860)
        if not residentParty then follower.groupMembers = { leader, follower.character } end
        follower:tick(1000)
        follower.nextThink = dueThinks and 1001 or 1000000
        for step = 1, 300 do
            leaderY = 8700 - math.floor(step / 3)
            follower:tick(1000 + step)
            local aimed = moves[#moves]
            assert(aimed ~= nil and aimed:getY() == leaderY + 2,
                "a long follow tracks the leader beyond the initial commit window")
            assert(thoughts == 0,
                "a long follow never returns a committed member to idle thinking")
        end
        assert(follower.formationCommitUntil > 1300,
            "a long follow renews the formation commitment")
        -- Reaching the slot releases the hold and lets ordinary work resume.
        follower.character = body(leaderX, leaderY + 2)
        follower.nextThink = 1301
        follower:tick(1301)
        assert(thoughts == 1, "arrival releases a long formation hold")
    end
end

-- 8. A zombie target still gains no formation movement.
moves, thoughts = {}, 0
local zombieFighter = controller({ id = "zed", groupLeader = leader,
    groupFormationSlot = 1, groupSize = 2 }, 8700, 8760)
zombieFighter.groupMembers = { leader, zombieFighter.character }
zombieFighter.combatTarget = {
    isZombie = function() return true end,
    getCurrentSquare = function() return square(8700, 8700, 0) end,
    isDead = function() return false end,
}
zombieFighter:tick(600)
assert(#moves == 0, "a zombie target never triggers a formation move")
assert(thoughts == 1, "a fighter facing a zombie still takes its ordinary decision")

getCell = previousGetCell
Persistence.getBaseResidentIds = previousIds
_G.KnoxSurvivorRuntime = previousRuntime
C.isNativeRecoveryBusy = previousRecoveryBusy
_G.KnoxCompanionVehicles = previousVehicles
