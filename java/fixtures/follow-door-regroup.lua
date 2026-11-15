-- A follower that loses sight at a door falls back to the frozen last-contact
-- point. That breadcrumb is not the player: standing near it on the wrong
-- side of the door must route to the point (so door recovery can engage),
-- not park the survivor. Only standing ON the point waits for contact, and
-- the repeated-failure latch still settles a genuinely blocked regroup.
local C = assert(KnoxAutonomyController)
local saved = {}
for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    saved[name] = rawget(_G, name)
end
local previousRecoveryBusy, previousAttackBusy =
    C.isNativeRecoveryBusy, C.isNativeAttackBusy
C.isNativeRecoveryBusy = function() return false end
C.isNativeAttackBusy = function() return false end
KnoxCompanionVehicles = nil

local insideRoom, insideBuilding = {}, {}
local outside = {
    getX = function() return 10 end,
    getY = function() return 10 end,
    getZ = function() return 0 end,
    getRoom = function() return nil end,
    getBuilding = function() return nil end,
}
local doorway = {
    getX = function() return 10 end,
    getY = function() return 11 end,
    getZ = function() return 0 end,
    getRoom = function() return insideRoom end,
    getBuilding = function() return insideBuilding end,
}
local player = {
    getCurrentSquare = function() return nil end,
    isDead = function() return false end,
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if z ~= 0 then return nil end
            if x == 10 and y == 10 then return outside end
            if x == 10 and y == 11 then return doorway end
            return nil
        end,
    }
end
instanceof = function() return false end

local movedTo = nil
local function drive(followerSquare, failures)
    movedTo = nil
    local controller = setmetatable({
        id = "follow-door-fixture",
        state = "COMPANION_FOLLOW",
        observedState = "COMPANION_FOLLOW",
        companionOrder = "follow",
        companionTarget = player,
        companionOwnerId = nil,
        companionFormationSlot = 1,
        playerLastContact = { x = 10, y = 11, z = 0, atHours = 1 },
        playerContactFailures = failures,
        activeDecision = "follow_player",
        stateStartedAt = 100,
        formationCommitUntil = 0,
        nextThink = math.huge,
        nextFormationRefresh = 0,
        nextThreatScan = math.huge,
        nextIdleLatchCheck = math.huge,
        nextRoamNeedsCheck = math.huge,
        counts = { search = 0, failures = 0 },
        selfCareRetryAt = {},
        blockedAreas = {},
        character = {
            getCurrentSquare = function() return followerSquare end,
            CanSee = function() return false end,
            getCharacterActions = function()
                return { isEmpty = function() return true end }
            end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
            getVehicle = function() return nil end,
            isDead = function() return false end,
        },
        bridge = {
            tickNpc = function() return "MOVE_RUNNING" end,
            moveNpcWithPace = function(_, _, target)
                movedTo = target
                return "MOVE_STARTED"
            end,
            setNpcMovementPace = function() return true end,
            cancelNpcMove = function() end,
        },
    }, C)
    for _, name in ipairs({
        "applyPendingCombatPolicy", "checkSharedMeal", "observeGroupEntry",
        "recoverIdleAnimationLatch", "recoverFromDetached", "isSettlementSupplyEntry",
        "tryAutomaticPlayerAid", "yieldBaseTaskForNeed", "yieldInventoryCleanupForNeed",
        "yieldAidForNeed", "yieldCollectionForNeed", "waitingForTransferActions",
        "sharedMealPostureReady", "prepareRouteWindowGlass",
    }) do
        controller[name] = function() return false end
    end
    controller.applyPendingCombatPolicy = function() return true end
    controller.recordMovementFailure = function() end
    controller.releaseSupply = function() end
    controller.finishDecision = function(self, ticks)
        self.finishedAt = ticks
    end
    controller:tick(100)
    return controller
end

local c = drive(outside, 0)
assert(movedTo == doorway,
    "a follower parked by a door routes to the last-contact point instead of waiting")
assert(c.state == "COMPANION_FOLLOW" and c.activeDecision == "regroup_last_contact",
    "the regroup route owns follow through the doorway, got state=" .. tostring(c.state))

c = drive(doorway, 0)
assert(movedTo == nil,
    "a follower standing on the last-contact point waits instead of re-routing")
assert(c.state == "COMPANION_WAIT" and c.activeDecision == "awaiting_player_contact",
    "contact wait keeps its reason on the point, got " .. tostring(c.activeDecision))

c = drive(outside, 3)
assert(movedTo == nil,
    "the repeated-failure latch still settles a blocked regroup without routing")
assert(c.state == "COMPANION_WAIT" and c.activeDecision == "regroup_route_blocked",
    "the blocked-regroup reason survives the fix, got " .. tostring(c.activeDecision))

for _, name in ipairs({ "getCell", "instanceof", "KnoxCompanionVehicles" }) do
    _G[name] = saved[name]
end
C.isNativeRecoveryBusy, C.isNativeAttackBusy = previousRecoveryBusy, previousAttackBusy
print("Follow door regroup PASS regroup_routes=true on_point_waits=true latch_held=true")
