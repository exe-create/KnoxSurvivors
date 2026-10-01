require "KS_ThreatClassifier"
local function isCorpseProxy(character)
    local threats = rawget(_G, "KnoxThreatClassifier")
    return threats ~= nil and threats.isCorpseProxy(character) or false
end

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISRestAction"
require "TimedActions/ISSitOnGround"
require "TimedActions/ISSmashWindow"
require "Util/AdjacentFreeTileFinder"
require "KS_TravelRouting"
require "KS_SurvivorNeeds"
require "KS_FirearmSupport"
require "KS_SurvivorInventoryActions"
require "KS_Persistence"
require "KS_ActivityFeed"
require "KS_SurvivorDialogue"
require "KS_GroupSupport"
require "KS_SurvivorLooting"
require "KS_EquipmentIntelligence"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_BaseManager"
require "KS_BaseTaskBoard"
require "KS_BaseJobs"
require "KS_BaseSupplyPlanner"
require "KS_BaseStorage"
require "KS_JobTestSupplies"
require "KS_BaseRecreation"
require "KS_BaseHygiene"
require "KS_BaseOrganize"
require "KS_BaseCooking"
require "KS_OrderSignals"
require "KS_BaseBarricades"
require "KS_BaseFarming"
require "KS_BaseWoodcutting"
require "KS_BaseCorpseHandling"
-- animal care retired (vanilla zones later)
require "KS_BaseRepairs"
-- construction retired
require "KS_CompanionPatrol"
require "KS_AwayTeamExecutor"
require "KS_FactionCamps"
require "KS_SurvivorRuntime"
require "KS_NightShelter"
require "KS_SurvivorMedicalActions"
require "KS_NpcVehicleTravel"
pcall(function() require "KS_DebugLog" end)

local Controller = rawget(_G, "KnoxAutonomyController") or {}
_G.KnoxAutonomyController = Controller
Controller.__index = Controller
Controller.TUNING = Controller.TUNING or {}

-- A Lua action may be turning, waiting to start, or between native actions.
-- An empty Java list alone does not mean its transfer/work has finished.
local function hasPendingTimedActions(character)
    if character == nil then return false end
    local actions = character:getCharacterActions()
    if actions ~= nil and not actions:isEmpty() then return true end
    local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
    local queue = queues ~= nil and queues[character] or nil
    return queue ~= nil and type(queue.queue) == "table" and #queue.queue > 0
end

local function sayDialogue(character, survivorId, event, ticks, cooldown, lines)
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if dialogue == nil then return false end
    if lines ~= nil and dialogue.sayLines ~= nil then
        return dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
    end
    if dialogue.say ~= nil then
        return dialogue.say(character, survivorId, event, ticks, cooldown)
    end
    return false
end

-- A task can enter the loaded controller from an older save, a restored claim,
-- or a direct developer/UI call. Persistence normally migrates these records,
-- but the controller is the final execution boundary and must never dispatch
-- legacy vocabulary to the concrete executors below. Normalize the existing
-- task in place so every downstream branch continues to use one authoritative
-- task object and no second task manager is needed.
local function canonicalBaseTask(task)
    if type(task) ~= "table" then return task end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        local normalized = catalog.normalizeTaskType(task.type)
        if normalized ~= nil then task.type = normalized end
    end
    return task
end

local THINK_MIN_TICKS = 30
Controller.TUNING.THINK_JITTER_TICKS = 45
local THREAT_SCAN_TICKS = 15
local COMBAT_RETARGET_COOLDOWN_TICKS = 90
-- Stickier retargeting: frequent 15-tick re-evaluation with a small margin makes
-- two nearby zombies trade ownership every scan, restarting native combat and
-- looking like sporadic kiting/spinning. Require a clear improvement instead.
-- While chasing, 1-2 tile steps swing scores by tens of points, so margins stay
-- above that footwork noise.
Controller.TUNING.COMBAT_RETARGET_SCORE_MARGIN = 72
Controller.TUNING.COMBAT_EMERGENCY_SCORE_MARGIN = 120
-- Reuse the previous approach tile while the same target holds still. Re-picking
-- the nearest of 8 neighbours every beginCombat shifts the destination 1-2
-- tiles even when nothing moved, which native combat turns into sidesteps.
Controller.TUNING.COMBAT_APPROACH_REUSE_DISTANCE_SQUARED = 2
-- Let a reloaded firearm finish before the next combat attempt. Yielding and
-- instantly re-engaging produces run-stop-run stutter.
local COMBAT_RANGED_YIELD_DELAY_TICKS = 45
-- After a kill, followers sprint back to a slot that drifted during the fight.
-- A short settle window keeps the next zombie from interrupting mid-sprint.
local COMBAT_POST_KILL_FORMATION_DELAY_TICKS = 60
local THREAT_IMMEDIATE_RADIUS = 3.5
local THREAT_VISIBLE_RADIUS = 16
local THREAT_MEMORY_TICKS = 120
Controller.TUNING.THREAT_MEMORY_SCORE_PENALTY = 48
local THREAT_SELF_TARGET_RADIUS = 20
local THREAT_GROUP_ASSIST_RADIUS = 10
Controller.TUNING.GROUP_COMBAT_LEASH_RADIUS = 12
local COMBAT_DISENGAGE_RADIUS = 18
local THREAT_MAX_DISTANCE_SQUARED = math.max(THREAT_VISIBLE_RADIUS,
    THREAT_SELF_TARGET_RADIUS, THREAT_GROUP_ASSIST_RADIUS, COMBAT_DISENGAGE_RADIUS) ^ 2
local THREAT_FAILURE_COOLDOWN_TICKS = 900
-- Dawn sweep: a survivor that slept under a roof wakes up and clears the
-- yard first. While the window holds, the engagement radius widens so the
-- dead that gathered overnight are fought instead of walked past. Attacker
-- limits and retarget margins still apply; humans are unaffected.
Controller.TUNING.NIGHT_SWEEP_TICKS = 3600
Controller.TUNING.NIGHT_SWEEP_RADIUS = 10
Controller.TUNING.SUPPLY_SCAN_RADIUS = 12
local SUPPLY_RETRY_TICKS = 600
-- A native action that refuses to queue (or a work target that went stale
-- between claim and arrival) must not be reclaimed on the next think. The
-- failure log line this installs is also the field diagnosis for
-- window-to-window walks that never barricade.
local BASE_TASK_ACTION_FAILURE_TICKS = 900
local EXPLORATION_SCAN_RADIUS = 12
local EXPLORATION_RETRY_TICKS = 180
Controller.TUNING.CONVENIENT_INSPECTION_RADIUS = 2
-- Reconsider the next container promptly after a successful search. The old
-- delay made a building look abandoned after one container even though the
-- exploration scan was still valid.
local LOOT_TRAVEL_COOLDOWN_TICKS = 360
Controller.TUNING.LOOT_CONTAINER_ITEM_LIMIT = 4
local EMPTY_SEARCH_COOLDOWN_TICKS = 1800
local BLOCKED_AREA_COOLDOWN_TICKS = 3600
local LOCKED_DOOR_MIN_ENDURANCE = 0.40
local ROAM_MIN_RADIUS = 6
local ROAM_MAX_RADIUS = 48
Controller.TUNING.ROAM_GOAL_COOLDOWN_TICKS = 7200
Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS = 7200
Controller.TUNING.ROAM_MEMORY_LIMIT = 12
Controller.TUNING.ROAM_NO_GOAL_RETRY_TICKS = 90
Controller.TUNING.ROAM_NEEDS_RECHECK_TICKS = 90
Controller.TUNING.ROAM_DANGER_RADIUS = 6
Controller.TUNING.ROAM_DANGER_LIMIT = 2
Controller.TUNING.RECOVERY_RECHECK_TICKS = 180
Controller.TUNING.RECOVERY_TIMEOUT_TICKS = 900
Controller.TUNING.SLEEP_RECOVERY_TIMEOUT_TICKS = 36000
Controller.TUNING.RECOVERY_SEAT_SCAN_RADIUS = 8
Controller.TUNING.RECOVERY_POSTURE_TIMEOUT_TICKS = 180
Controller.TUNING.SELF_CARE_RETRY_TICKS = 300
-- Direct orders may defer ordinary tiredness, but not a body that is close to
-- exhaustion. Recovery still uses the normal completion thresholds, providing
-- enough hysteresis that an ordered survivor does not bounce in and out of rest.
Controller.TUNING.ORDER_CRITICAL_ENDURANCE = 0.12
Controller.TUNING.ORDER_CRITICAL_FATIGUE = 0.90
Controller.TUNING.CORPSE_DEFENSE_RELEASE_TICKS = 90
Controller.TUNING.BASE_AMBIENT_REST_TICKS = 1800
Controller.TUNING.CAMP_DECISION_TICKS = 180
Controller.TUNING.CAMP_EXCURSION_COOLDOWN_TICKS = 1800
Controller.TUNING.CAMP_POSITION_FAILURE_TICKS = 300
Controller.TUNING.MOVEMENT_TIMEOUT_TICKS = 1500
Controller.TUNING.ACTION_TIMEOUT_TICKS = 1200
Controller.TUNING.GROUP_SOFT_LEASH_SQUARED = 100
Controller.TUNING.GROUP_RETRIEVE_LEASH_SQUARED = 196
-- Arrival within ~1 tile counts as arrived; exact-square equality repaths on
-- every footstep while following a moving anchor.
Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED = 1
Controller.PARTY_SUPPORT_FOOD_LEASH_SQUARED = 9
Controller.PLAYER_PARTY_FORMATION = {
    runDistanceSquared = 25,
    sprintDistanceSquared = 144,
    anchorFallbackTicks = 60,
    compressRadius = 3,
    destinationToleranceSquared = 2.25,
}
Controller.PARTY_DESTINATION_APPROACH_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 },
    { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 },
}
Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED = 64
Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RETRY_TICKS = 300
Controller.TUNING.GROUP_OBJECTIVE_ASSIST_COOLDOWN_TICKS = 1800
Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS = 600
Controller.TUNING.GROUP_SUPPORT_COOLDOWN_TICKS = 1800
-- Keep a follower committed to its route while a moving leader's slot drifts;
-- replanning after a one-tile adjustment causes visible direction thrashing.
-- A leader turning at the edge of the camera should not make a follower
-- reverse once just because the ideal formation tile moved one square. Keep
-- the current route until the anchor has created a real gap or the target
-- moved several tiles.
Controller.TUNING.FORMATION_REPATH_SHIFT_SQUARED = 3.5
Controller.TUNING.FORMATION_REFRESH_TICKS = 45
-- Native path requests are expensive and can make a follower oscillate through
-- doorways when its anchor is moving. Hold a route briefly and require a real
-- slot change before replacing it.
Controller.TUNING.FORMATION_ROUTE_COMMIT_TICKS = 90
Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS = 90
Controller.TUNING.FORMATION_FAILURE_COOLDOWN_TICKS = 180
local FORMATION_FAILURE_MAX_COOLDOWN_TICKS = 720
local MOVEMENT_FAILURE_COOLDOWN_TICKS = 180
local MOVEMENT_FAILURE_MAX_COOLDOWN_TICKS = 1440
-- Hang watchdog for job travel: zero displacement for a sustained window
-- fails fast instead of riding out the full state timeout and re-queuing
-- the same unreachable approach forever.
local TASK_TRAVEL_STALL_TICKS = 300
local TASK_TRAVEL_STALL_DISTANCE_SQUARED = 2.25
local ENTRY_SCAN_RADIUS = 16
local FLEE_SCAN_RADIUS = 12
local FLEE_TARGET_DISTANCE = 12
local FLEE_RECHECK_TICKS = 45
local FLEE_PLAN_TICKS = 240
local FLEE_SAFE_CONFIRM_SCANS = 2
local FLEE_CLEAR_DISTANCE_SQUARED = 64
local FLEE_DISENGAGE_TICKS = 600

-- Short-lived, loaded-world coordination only.  This is deliberately not
-- persistence: a flee route is a reaction to the zombies visible right now,
-- not a mission or a world-state change that should survive save/load.
local fleePlans = rawget(_G, "KnoxFleePlans") or {}
_G.KnoxFleePlans = fleePlans

-- Supply-search leases coordinate loaded controllers only. The survivor duty's
-- `activeSupplyRun` is the durable owner; container reservations, lease expiry,
-- and which loaded controller currently searches must never enter base ModData.
local baseSupplyClaimsByBase = {}

local function supplyClaimsFor(baseId)
    local key = tostring(baseId or "")
    if key == "" then return nil end
    local claims = baseSupplyClaimsByBase[key]
    if type(claims) ~= "table" then
        claims = {}
        baseSupplyClaimsByBase[key] = claims
    end
    return claims
end

-- Base alarms rally off-duty residents to an intruder inside home territory.
-- Set when any resident starts combat there; idle members converge through
-- their normal movement and threat scans, then resume base life on expiry.
-- Loaded-world only, like supply leases.
local baseAlarmsByBase = {}
local BASE_ALARM_TICKS = 1800

function Controller.baseAlarmFor(baseId)
    return baseAlarmsByBase[tostring(baseId or "")]
end

-- Called when this resident starts combat: an intruder inside home
-- or camp raises an alarm so off-duty members converge.
function Controller:soundBaseAlarm(targetSquare)
    if targetSquare == nil then
        return false
    end
    local inside = false
    if self.baseId == nil or self.base == nil then
        return Controller.soundCampAlarm(self, targetSquare, self.currentTicks or 0)
    end
    if KnoxBaseManager ~= nil and KnoxBaseManager.containsSquare ~= nil then
        local ok, result = pcall(function()
            return KnoxBaseManager.containsSquare(self.base, targetSquare)
        end)
        inside = ok and result == true
    end
    if not inside then
        return Controller.soundCampAlarm(self, targetSquare, self.currentTicks or 0)
    end
    local ticks = self.currentTicks or 0
    baseAlarmsByBase[tostring(self.baseId)] = {
        x = targetSquare:getX(),
        y = targetSquare:getY(),
        z = targetSquare:getZ(),
        untilTick = ticks + BASE_ALARM_TICKS,
    }
    return true
end

-- Camp twin of the base alarm: an intruder inside camp bounds rallies idle
-- camp members the same way. Kept separate so base keys never collide.
function Controller.soundCampAlarm(self, targetSquare, ticks)
    if self == nil or self.campId == nil or self.camp == nil or targetSquare == nil then
        return false
    end
    local camps = rawget(_G, "KnoxFactionCamps")
    if camps == nil or camps.contains == nil then
        return false
    end
    local ok, inside = pcall(function()
        return camps.contains(self.camp, targetSquare)
    end)
    if not ok or inside ~= true then
        return false
    end
    baseAlarmsByBase["camp:" .. tostring(self.campId)] = {
        x = targetSquare:getX(),
        y = targetSquare:getY(),
        z = targetSquare:getZ(),
        untilTick = (tonumber(ticks) or 0) + BASE_ALARM_TICKS,
    }
    return true
end

-- Off-duty rally: walk toward a live home alarm. Arrival re-decides, so the
-- normal threat scan engages anything still there and expiry resumes base
-- life. Guards, patrols, and tasked residents keep their posts.
function Controller:answerBaseAlarm(ticks)
    local key = nil
    if self.baseId ~= nil and self.base ~= nil and self.baseTask == nil then
        key = tostring(self.baseId)
    elseif self.campId ~= nil and self.camp ~= nil then
        key = "camp:" .. tostring(self.campId)
    else
        return false
    end
    local alarm = baseAlarmsByBase[key]
    if type(alarm) ~= "table" then
        return false
    end
    if ticks > (tonumber(alarm.untilTick) or 0) then
        baseAlarmsByBase[key] = nil
        return false
    end
    local current = self.character ~= nil and self.character:getCurrentSquare() or nil
    if current == nil then
        return false
    end
    local dx = (tonumber(alarm.x) or 0) - current:getX()
    local dy = (tonumber(alarm.y) or 0) - current:getY()
    if dx * dx + dy * dy <= 9 then
        return false
    end
    local cell = getCell ~= nil and getCell() or nil
    local goal = cell ~= nil and cell:getGridSquare(
        tonumber(alarm.x) or 0, tonumber(alarm.y) or 0, current:getZ()) or nil
    if goal == nil then
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, goal))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    self.activeDecision = "base_defend"
    self.state = "BASE_DEFEND"
    self.stateStartedAt = ticks
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " base-defend "
        .. tostring(alarm.x) .. "," .. tostring(alarm.y))
    return true
end

local function restoreSupplyClaim(baseId, kind, survivorId)
    if kind == nil or survivorId == nil then return false end
    local claims = supplyClaimsFor(baseId)
    if claims == nil then return false end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local current = claims[kind]
    if type(current) ~= "table" or current.survivorId == survivorId
        or current.durable ~= true
        or (tonumber(current.untilHours) or 0) <= now then
        claims[kind] = {
            survivorId = survivorId,
            untilHours = now + 1.5,
            durable = true,
        }
        return true
    end
    return false
end

function Controller.activeBaseSupplyRun(duty, baseId, survivorId)
    if type(duty) ~= "table" or duty.mode ~= "base"
        or tostring(duty.baseId or "") ~= tostring(baseId or "")
        or (KnoxPersistence ~= nil and KnoxPersistence.isSurvivorAlive ~= nil
            and KnoxPersistence.isSurvivorAlive(survivorId) == false)
        or type(duty.activeSupplyRun) ~= "table" then
        return nil
    end
    local kind = tostring(duty.activeSupplyRun.kind or "")
    if kind ~= "find_food" and kind ~= "find_water" and kind ~= "find_medical" then
        return nil
    end
    return kind
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function navigationDistanceSquared(first, second)
    if first == nil or second == nil or first:getZ() ~= second:getZ() then
        return math.huge
    end
    return distanceSquared(first, second)
end

local function travelPaceFor(distance, sameBuilding, context)
    local kind = tostring(context or "")
    -- Ordered looting moves container-to-container inside/around buildings.
    -- Walking keeps formation natural and avoids sprinting past doorways.
    if kind == "loot" then
        return "walk"
    end
    local settings = rawget(_G, "KnoxSettings")
    if settings == nil or settings.cautiousTravel == nil or settings.cautiousTravel() then
        return "cautious"
    end
    if sameBuilding or distance == math.huge then
        return "walk"
    end
    -- Arrival steps stay a walk so survivors do not sprint past doorways.
    if (tonumber(distance) or math.huge) <= 4 then
        return "walk"
    end
    local thresholds = {
        urgent = 8,
        directed = 12,
        return_home = 12,
        travel = 14,
    }
    local threshold = thresholds[tostring(context or "")]
    if threshold ~= nil and distance >= threshold * threshold then
        -- Build 42 exposes walk/run/sprint, not a separate jog state. A long
        -- ordinary route therefore requests native run, which reads as a jog;
        -- the Java locomotion policy drops it back to walking near arrival or
        -- when endurance, fatigue, or health make running inappropriate.
        -- Urgent legs (threat response, flee recovery, combat approach) may
        -- sprint; the same native policy still gates on fitness.
        if tostring(context or "") == "urgent" then
            return "sprint"
        end
        return "run"
    end
    return "walk"
end

local roadFinalById = {}

local function moveWithTravelPace(bridge, id, character, target, context)
    local current = character ~= nil and character:getCurrentSquare() or nil
    local targetSquare = target
    local distance = navigationDistanceSquared(current, targetSquare)
    local sameBuilding = false
    if current ~= nil and targetSquare ~= nil then
        local ok, currentBuilding, targetBuilding = pcall(function()
            return current:getBuilding(), targetSquare:getBuilding()
        end)
        sameBuilding = ok and currentBuilding ~= nil and currentBuilding == targetBuilding
    end
    -- Far travel favors roads/buildings over straight woods lines. Stage via
    -- a road-like midpoint and remember the final destination for resume.
    local routing = rawget(_G, "KnoxTravelRouting")
    if routing ~= nil and routing.findRoadWaypoint ~= nil
        and current ~= nil and targetSquare ~= nil and id ~= nil
        and (context == "travel" or context == "directed" or context == "return_home"
            or context == "urgent") then
        local waypoint = routing.findRoadWaypoint(current, targetSquare)
        if waypoint ~= nil and waypoint ~= targetSquare then
            roadFinalById[id] = { square = targetSquare, context = context }
            targetSquare = waypoint
            target = waypoint
            distance = navigationDistanceSquared(current, targetSquare)
        else
            roadFinalById[id] = nil
        end
    end
    local pace = travelPaceFor(distance, sameBuilding, context)
    if bridge.moveNpcWithPace ~= nil then
        return bridge:moveNpcWithPace(id, target, pace), pace
    end
    return bridge:moveNpc(id, target), pace
end

function Controller.travelPaceFor(distance, sameBuilding, context)
    return travelPaceFor(distance, sameBuilding, context)
end

-- Called on intermediate arrival: resume the stored final destination via a
-- fresh road-biased leg. Returns true when the Succeeded event was consumed
-- by onward travel (caller must return without running arrival logic).
function Controller:continueRoadTravel(ticks)
    local final = self.travelFinalSquare
    local context = self.travelFinalContext
    local pending = roadFinalById[self.id]
    if final == nil and pending ~= nil then
        final = pending.square
        context = pending.context or context
    end
    if final == nil then return false end
    local current = self.character ~= nil and self.character:getCurrentSquare() or nil
    if current == nil then
        self.travelFinalSquare = nil
        self.travelFinalContext = nil
        roadFinalById[self.id] = nil
        return false
    end
    if navigationDistanceSquared(current, final) <= 4 then
        self.travelFinalSquare = nil
        self.travelFinalContext = nil
        roadFinalById[self.id] = nil
        return false
    end
    context = context or "travel"
    -- moveWithTravelPace re-stages automatically for remaining far distance.
    local result, _ = moveWithTravelPace(self.bridge, self.id, self.character, final, context)
    if string.find(tostring(result), "MOVE_STARTED", 1, true) == 1 then
        self.stateStartedAt = ticks
        return true
    end
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    return false
end

local function nativeTraversalBusy(character)
    if character == nil then
        return false
    end
    local ok, stateName, actionName = pcall(function()
        return tostring(character:getCurrentStateName() or ""),
            tostring(character:getCurrentActionContextStateName() or "")
    end)
    if not ok then
        return false
    end
    local state = string.lower(stateName .. " " .. actionName)
    return string.find(state, "climb", 1, true) ~= nil
        or string.find(state, "vault", 1, true) ~= nil
        or string.find(state, "openwindow", 1, true) ~= nil
        or string.find(state, "smashwindow", 1, true) ~= nil
end

local function combatApproachSquare(character, target)
    local current = character ~= nil and character:getCurrentSquare() or nil
    local targetSquare = target ~= nil and target:getCurrentSquare() or nil
    local cell = getCell()
    if current == nil or targetSquare == nil or cell == nil then
        return nil
    end
    local best, bestDistance = nil, math.huge
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local square = cell:getGridSquare(
                    targetSquare:getX() + dx,
                    targetSquare:getY() + dy,
                    targetSquare:getZ()
                )
                if square ~= nil and (square == current or square:canStand()) then
                    local distance = navigationDistanceSquared(current, square)
                    if distance < bestDistance then
                        best = square
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best or AdjacentFreeTileFinder.Find(targetSquare, character)
end

function Controller.isNativeTraversalBusy(character)
    return nativeTraversalBusy(character)
end

function Controller.combatApproachSquare(character, target)
    return combatApproachSquare(character, target)
end

-- Doors: survivors open closed unlocked doors on entry/exit and close them
-- behind in base territory. All native calls are pcall-guarded for B42 API drift.
local function safeDoorFlag(door, ...)
    if door == nil then return nil end
    for _, method in ipairs({ ... }) do
        if door[method] ~= nil then
            local ok, value = pcall(door[method], door)
            if ok then return value end
        end
    end
    return nil
end

local function doorIsOpen(door)
    local v = safeDoorFlag(door, "IsOpen", "isOpen", "isOpened")
    return v == true
end

local function doorIsLocked(door)
    if safeDoorFlag(door, "isLocked", "IsLocked") == true then return true end
    if safeDoorFlag(door, "isLockedByKey", "IsLockedByKey") == true then return true end
    return false
end

local function doorIsBarricaded(door)
    return safeDoorFlag(door, "isBarricaded", "IsBarricaded") == true
end

local function tryToggleDoor(character, door, open)
    if door == nil or character == nil then return false end
    local ok, changed = pcall(function()
        if door.ToggleDoor ~= nil then door:ToggleDoor(character); return true end
        if door.toggleDoor ~= nil then door:toggleDoor(character); return true end
        if door.setOpen ~= nil then door:setOpen(open == true); return true end
        return false
    end)
    return ok and changed == true
end

function Controller:openNearbyClosedDoor()
    -- Per-companion door permission first (nil = inherit), sandbox default
    -- second. The synced controller field already folds both.
    if self.allowDoorWindowOpening == false then
        return false
    end
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.allowSurvivorDoorWindowOpening ~= nil
        and not settings.allowSurvivorDoorWindowOpening() then
        return false
    end
    local current = self.character ~= nil and self.character:getCurrentSquare() or nil
    local cell = getCell ~= nil and getCell() or nil
    if current == nil or cell == nil then return false end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(current:getX() + dx, current:getY() + dy, current:getZ())
            if square ~= nil and square.getObjects ~= nil then
                local objects = square:getObjects()
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local isDoor = false
                    if instanceof ~= nil then
                        local ok, result = pcall(function() return instanceof(object, "IsoDoor") end)
                        isDoor = ok and result == true
                    end
                    if isDoor and not doorIsOpen(object) and not doorIsLocked(object)
                        and not doorIsBarricaded(object) then
                        -- Toggle once only. The native state may not refresh
                        -- within this tick; a second toggle would immediately
                        -- close the door we just opened.
                        local toggled = tryToggleDoor(self.character, object, true)
                        if toggled then
                            self.openedDoors = self.openedDoors or {}
                            self.openedDoors[object] = true
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function Controller:closeOpenedDoors()
    if self.openedDoors == nil then return end
    local base = self.base
    -- Companions and pair/group members travel with the player: leaving
    -- doors open behind the party invites wanderers in. Everyone else only
    -- auto-closes inside owned territory to avoid trapping others.
    local roamsWithPlayer = self.companionOrder ~= nil or self.groupLeaderId ~= nil
    local stillOpen = nil
    for door in pairs(self.openedDoors) do
        local valid = door ~= nil
        local isOpen = false
        if valid then
            local ok, result = pcall(function() return doorIsOpen(door) end)
            isOpen = ok and result == true
            -- Stale/unloaded door handles report closed; drop them quietly.
            if not ok then valid = false end
        end
        if valid and isOpen then
            local closeIt = true
            if base ~= nil and KnoxBaseManager ~= nil and KnoxBaseManager.containsSquare ~= nil then
                local sq = nil
                pcall(function()
                    if door.getSquare ~= nil then sq = door:getSquare() end
                end)
                if sq ~= nil then
                    local ok, inside = pcall(function()
                        return KnoxBaseManager.containsSquare(base, sq)
                    end)
                    closeIt = roamsWithPlayer or (not ok) or inside == true
                end
            end
            if closeIt then
                -- Never slam a door another actor is crossing.
                local blocked = false
                pcall(function()
                    local sq = door.getSquare ~= nil and door:getSquare() or nil
                    if sq ~= nil and sq.getMovingObjects ~= nil then
                        local movers = sq:getMovingObjects()
                        blocked = movers ~= nil and movers:size() > 1
                    end
                end)
                if not blocked then
                    pcall(function() tryToggleDoor(self.character, door, false) end)
                end
                local ok, nowOpen = pcall(function() return doorIsOpen(door) end)
                if (not ok) or nowOpen ~= true then
                    -- Closed or stale: drop tracking.
                else
                    -- Still open (toggle lag or blocked): retry next tick.
                    stillOpen = stillOpen or {}
                    stillOpen[door] = true
                end
            else
                stillOpen = stillOpen or {}
                stillOpen[door] = true
            end
        end
    end
    self.openedDoors = stillOpen
end

local function directionComponent(value)
    if value > 0.35 then
        return 1
    end
    if value < -0.35 then
        return -1
    end
    return 0
end

local function findFormationTarget(anchor, follower, slotIndex, survivorId, options)
    local anchorSquare = anchor ~= nil and anchor:getCurrentSquare() or nil
    local followerSquare = follower ~= nil and follower:getCurrentSquare() or nil
    local cell = getCell()
    if anchorSquare == nil or followerSquare == nil or cell == nil then
        return nil
    end

    options = type(options) == "table" and options or nil
    local forwardX = directionComponent(options ~= nil and options.forwardX
        or anchor:getForwardDirectionX())
    local forwardY = directionComponent(options ~= nil and options.forwardY
        or anchor:getForwardDirectionY())
    if forwardX == 0 and forwardY == 0 then
        forwardY = 1
    end
    local slot = math.max(1, tonumber(slotIndex) or 1)
    local row = math.floor((slot - 1) / 2) + 1
    local side = slot % 2 == 1 and -1 or 1
    local spacing = KnoxSettings ~= nil and KnoxSettings.followerSpacing ~= nil
        and KnoxSettings.followerSpacing() or 1
    local formation = KnoxSettings ~= nil and KnoxSettings.followerFormation ~= nil
        and KnoxSettings.followerFormation() or "paired"
    local duty = survivorId ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    if duty ~= nil and duty.mode == "companion" then
        if duty.followerFormation == "paired" or duty.followerFormation == "single_file" then
            formation = duty.followerFormation
        end
        if duty.followerSpacing == 1 or duty.followerSpacing == 2 or duty.followerSpacing == 3 then
            spacing = duty.followerSpacing
        end
    end
    if formation == "single_file" then
        row, side = slot, 0
    end
    local lateralX = -forwardY
    local lateralY = forwardX
    local target = cell:getGridSquare(
        anchorSquare:getX() + (-forwardX * row + lateralX * side) * spacing,
        anchorSquare:getY() + (-forwardY * row + lateralY * side) * spacing,
        anchorSquare:getZ()
    )
    if target ~= nil and target ~= anchorSquare
        and (target == followerSquare or target:canStand()) then
        return target
    end
    if options ~= nil and options.noFallback == true then return nil end
    local fallback = AdjacentFreeTileFinder.Find(anchorSquare, follower)
    if fallback ~= nil and (fallback:getX() ~= anchorSquare:getX()
        or fallback:getY() ~= anchorSquare:getY()
        or fallback:getZ() ~= anchorSquare:getZ()) then
        return fallback
    end
    return nil
end

function Controller.squareCanStand(square)
    if square == nil then return false end
    if square.canStand == nil then return true end
    local ok, standable = pcall(function() return square:canStand() end)
    return ok and standable == true
end

function Controller.squareOccupiedByOther(square, character)
    if square == nil or square.getMovingObjects == nil then return false end
    local ok, objects = pcall(function() return square:getMovingObjects() end)
    if not ok or objects == nil then return false end
    local count = 0
    pcall(function() count = objects:size() end)
    for index = 0, count - 1 do
        local success, object = pcall(function() return objects:get(index) end)
        if success and object ~= nil and object ~= character then return true end
    end
    return false
end

function Controller.playerPartyBottleneck(anchorSquare, partySize)
    if anchorSquare == nil then return false end
    local openDirections = 0
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or cell.getGridSquare == nil then return true end
    for _, offset in ipairs(Controller.PARTY_DESTINATION_APPROACH_OFFSETS) do
        local candidate = cell:getGridSquare(
            anchorSquare:getX() + offset[1],
            anchorSquare:getY() + offset[2], anchorSquare:getZ()
        )
        if Controller.squareCanStand(candidate) then
            local blocked = false
            if anchorSquare.isBlockedTo ~= nil then
                local ok, result = pcall(function() return anchorSquare:isBlockedTo(candidate) end)
                blocked = ok and result == true
            end
            if not blocked then openDirections = openDirections + 1 end
        end
    end
    local required = math.min(#Controller.PARTY_DESTINATION_APPROACH_OFFSETS,
        math.max(1, math.floor(tonumber(partySize) or 1)))
    return openDirections < required
end

function Controller:releasePlayerFormationTarget()
    local target = self.playerFormationTargetSquare
    local reservations = self.reservations
    local bucket = reservations ~= nil and reservations.playerFormationTargets or nil
    if target ~= nil and bucket ~= nil and bucket[target] == self.id then
        bucket[target] = nil
    end
    self.playerFormationTargetSquare = nil
    self.playerFormationCompressed = nil
end

function Controller:reservePlayerFormationTarget(target, compressed)
    if target == nil then return false end
    self.reservations = self.reservations or {}
    local bucket = self.reservations.playerFormationTargets
    if bucket == nil then
        bucket = {}
        self.reservations.playerFormationTargets = bucket
    end
    local owner = bucket[target]
    if owner ~= nil and owner ~= self.id then return false end
    local previous = self.playerFormationTargetSquare
    bucket[target] = self.id
    if previous ~= nil and previous ~= target and bucket[previous] == self.id then
        bucket[previous] = nil
    end
    self.playerFormationTargetSquare = target
    self.playerFormationCompressed = compressed == true
    return true
end

function Controller:findPlayerPartyFormationTarget(anchor, anchorSquare, preserveRouteLease)
    local slot = math.max(1, tonumber(self.companionFormationSlot) or 1)
    anchorSquare = anchorSquare
        or (anchor ~= nil and anchor:getCurrentSquare() or nil)
    local bottleneck = Controller.playerPartyBottleneck(
        anchorSquare,
        self.companionPartySize
    )
    local preferred = not bottleneck and findFormationTarget(
        anchor, self.character, slot, self.id, {
            forwardX = self.companionFormationForwardX,
            forwardY = self.companionFormationForwardY,
            noFallback = true,
        }
    ) or nil
    local function available(square)
        if square == nil or not Controller.squareCanStand(square)
            or Controller.squareOccupiedByOther(square, self.character) then
            return false
        end
        local bucket = self.reservations ~= nil
            and self.reservations.playerFormationTargets or nil
        local owner = bucket ~= nil and bucket[square] or nil
        if owner ~= nil and owner ~= self.id then return false end
        if anchorSquare ~= nil and navigationDistanceSquared(anchorSquare, square) <= 1
            and anchorSquare.isBlockedTo ~= nil then
            local ok, blocked = pcall(function() return anchorSquare:isBlockedTo(square) end)
            if ok and blocked == true then return false end
        end
        return true
    end
    if not bottleneck and available(preferred) then
        if preserveRouteLease == true
            and self.playerFormationTargetSquare ~= preferred then
            return preferred, false
        end
        if self:reservePlayerFormationTarget(preferred, false) then
            return preferred, false
        end
    end
    local cell = getCell ~= nil and getCell() or nil
    if anchorSquare == nil or cell == nil then return nil, true end
    local offsets = Controller.PARTY_DESTINATION_APPROACH_OFFSETS
    local startIndex = (slot - 1) % #offsets
    local spacing = KnoxSettings ~= nil and KnoxSettings.followerSpacing ~= nil
        and tonumber(KnoxSettings.followerSpacing()) or 1
    local maxRadius = math.min(Controller.PLAYER_PARTY_FORMATION.compressRadius,
        math.max(2, math.floor(spacing) + 1))
    local formation = KnoxSettings ~= nil and KnoxSettings.followerFormation ~= nil
        and KnoxSettings.followerFormation() or "paired"
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    if duty ~= nil and duty.mode == "companion"
        and (duty.followerFormation == "paired" or duty.followerFormation == "single_file") then
        formation = duty.followerFormation
    end
    if formation == "single_file" then
        local forwardX = tonumber(self.companionFormationForwardX) or 0
        local forwardY = tonumber(self.companionFormationForwardY) or 1
        if forwardX == 0 and forwardY == 0 then forwardY = 1 end
        local lineRadius = math.min(12, math.max(slot, maxRadius))
        for radius = slot, lineRadius do
            local candidate = cell:getGridSquare(
                anchorSquare:getX() - forwardX * radius,
                anchorSquare:getY() - forwardY * radius,
                anchorSquare:getZ()
            )
            if available(candidate)
                and self:reservePlayerFormationTarget(candidate, true) then
                return candidate, true
            end
        end
    end
    for radius = 1, maxRadius do
        for offset = 0, #offsets - 1 do
            local index = (startIndex + offset) % #offsets + 1
            local candidate = cell:getGridSquare(
                anchorSquare:getX() + offsets[index][1] * radius,
                anchorSquare:getY() + offsets[index][2] * radius,
                anchorSquare:getZ()
            )
            if candidate ~= anchorSquare and available(candidate) then
                if preserveRouteLease == true
                    and self.playerFormationTargetSquare ~= candidate then
                    return candidate, true
                end
                if self:reservePlayerFormationTarget(candidate, true) then
                    return candidate, true
                end
            end
        end
    end
    if preserveRouteLease == true and self.playerFormationTargetSquare ~= nil then
        return self.playerFormationTargetSquare, self.playerFormationCompressed == true
    end
    return nil, true
end

function Controller:findPartyDestinationTarget(directive, destinationSquare)
    if directive == nil or destinationSquare == nil then return nil end
    local revision = tonumber(directive.partyDestinationRevision)
    local slot = math.max(1, math.floor(tonumber(
        directive.partyDestinationSlot or self.companionFormationSlot
    ) or 1))
    self.reservations = self.reservations or {}
    local bucket = self.reservations.partyDestinationTargets
    if bucket == nil then
        bucket = {}
        self.reservations.partyDestinationTargets = bucket
    end
    local existing = self.partyDestinationTargetSquare
    if self.partyDestinationFinalLeg ~= true
        and self.partyDestinationTargetRevision == revision and existing ~= nil
        and bucket[existing] == self.id and Controller.squareCanStand(existing)
        and not Controller.squareOccupiedByOther(existing, self.character) then
        return existing
    end
    if existing ~= nil and bucket[existing] == self.id then bucket[existing] = nil end
    self.partyDestinationTargetSquare = nil

    if self.partyDestinationFinalLeg == true then
        local owner = bucket[destinationSquare]
        if owner == nil or owner == self.id then
            bucket[destinationSquare] = self.id
            self.partyDestinationTargetSquare = destinationSquare
            self.partyDestinationTargetRevision = revision
            return destinationSquare
        end
        -- A larger-than-normal party can exhaust distinct arrival squares.
        -- Reuse the canonical point rather than strand members until expiry;
        -- the existing native pathing owner handles the occupied approach.
        self.partyDestinationTargetSquare = destinationSquare
        self.partyDestinationTargetRevision = revision
        return destinationSquare
    end

    local offsets = Controller.PARTY_DESTINATION_APPROACH_OFFSETS
    local startIndex = (slot - 1) % #offsets
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return nil end
    for offset = 0, #offsets - 1 do
        local index = (startIndex + offset) % #offsets + 1
        -- Resolve each candidate from the current loaded cell; the command
        -- destination itself remains the canonical arrival point.
        local candidate = cell:getGridSquare(
            destinationSquare:getX() + offsets[index][1],
            destinationSquare:getY() + offsets[index][2],
            destinationSquare:getZ()
        )
        local dx = candidate ~= nil and candidate:getX() - destinationSquare:getX() or math.huge
        local dy = candidate ~= nil and candidate:getY() - destinationSquare:getY() or math.huge
        local owner = candidate ~= nil and bucket[candidate] or nil
        local blockedToDestination = false
        if candidate ~= nil and destinationSquare.isBlockedTo ~= nil then
            local ok, blocked = pcall(function()
                return destinationSquare:isBlockedTo(candidate)
            end)
            blockedToDestination = ok and blocked == true
        end
        if candidate ~= nil and candidate ~= destinationSquare
            and dx * dx + dy * dy <= Controller.PLAYER_PARTY_FORMATION.destinationToleranceSquared
            and Controller.squareCanStand(candidate)
            and not Controller.squareOccupiedByOther(candidate, self.character)
            and not blockedToDestination
            and (owner == nil or owner == self.id) then
            bucket[candidate] = self.id
            self.partyDestinationTargetSquare = candidate
            self.partyDestinationTargetRevision = revision
            return candidate
        end
    end
    local owner = bucket[destinationSquare]
    if owner == nil or owner == self.id then
        bucket[destinationSquare] = self.id
        self.partyDestinationTargetSquare = destinationSquare
        self.partyDestinationTargetRevision = revision
        return destinationSquare
    end
    self.partyDestinationTargetSquare = destinationSquare
    self.partyDestinationTargetRevision = revision
    return destinationSquare
end

local function formationPace(anchor, follower)
    if anchor == nil or follower == nil
        or anchor:getCurrentSquare() == nil or follower:getCurrentSquare() == nil then
        return "normal"
    end
    local distance = navigationDistanceSquared(
        anchor:getCurrentSquare(), follower:getCurrentSquare()
    )
    local ok, sneaking = pcall(function() return anchor:isSneaking() end)
    if ok and sneaking == true then return "sneak" end
    -- A player who is deliberately sprinting must not need to open a huge gap
    -- before their companions are allowed to match pace.  The native adapter
    -- still checks endurance, fatigue, health, and native sprint eligibility.
    local sprintOk, sprinting = pcall(function() return anchor:isSprinting() end)
    if sprintOk and sprinting == true and distance >= 4 then return "sprint" end
    -- Keep ordinary formation walking calm, but let a follower close a real gap
    -- instead of asking the engine to walk one tile at a time behind a running anchor.
    if distance >= Controller.PLAYER_PARTY_FORMATION.sprintDistanceSquared then
        return "sprint"
    end
    if distance >= Controller.PLAYER_PARTY_FORMATION.runDistanceSquared then
        return "run"
    end
    return "normal"
end

local function moveWithFormationPace(bridge, id, target, anchor, follower)
    local pace = formationPace(anchor, follower)
    return bridge:moveNpcWithPace(
        id,
        target,
        pace
    ), pace
end

local function formationRefreshDelay(slot)
    -- Followers already receive different spatial slots. A small, deterministic
    -- time offset also keeps a tight group from refreshing into the same doorway
    -- or window edge on one controller tick. It is spacing, not a new formation.
    return ((math.max(1, tonumber(slot) or 1) - 1) % 3) * 4
end

local function reservedByOther(reservations, kind, value, id)
    local owner = reservations[kind][value]
    return owner ~= nil and owner ~= id
end

local function reserve(reservations, kind, value, id)
    if value == nil or reservedByOther(reservations, kind, value, id) then
        return false
    end
    reservations[kind][value] = id
    return true
end

local function release(reservations, kind, value, id)
    if value ~= nil and reservations[kind][value] == id then
        reservations[kind][value] = nil
    end
end

local function ambientSpotKey(square)
    if square == nil or square.getX == nil or square.getY == nil then
        return nil
    end
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square.getZ ~= nil and square:getZ() or 0)
end

local function threatUnavailable(self, zombie, ticks)
    if self.unarmedRejectedTarget == zombie and self.unarmedRetryUntil ~= nil
        and self.character:getPrimaryHandItem() ~= self.rejectedCombatItem then
        self.failedThreats[zombie] = nil
        return false
    end
    local unavailableUntil = self.failedThreats[zombie]
    if unavailableUntil ~= nil and unavailableUntil <= ticks then
        self.failedThreats[zombie] = nil
        return false
    end
    return unavailableUntil ~= nil
end

local function threatReservationCount(reservations, zombie, excludeId)
    local owners = reservations.threats[zombie]
    if type(owners) ~= "table" then
        return owners ~= nil and owners ~= excludeId and 1 or 0
    end
    local count = 0
    for id in pairs(owners) do
        if id ~= excludeId then
            count = count + 1
        end
    end
    return count
end

local function threatAttackerLimit(reason)
    if reason == "active_target" then
        return 3
    end
    if reason == "group_target" or reason == "immediate"
        or reason == "player_target" then
        return 2
    end
    return 1
end

local function reserveThreat(reservations, zombie, id, limit)
    if zombie == nil or threatReservationCount(reservations, zombie, id)
        >= math.max(1, tonumber(limit) or 1) then
        return false
    end
    local owners = reservations.threats[zombie]
    if type(owners) ~= "table" then
        owners = {}
        reservations.threats[zombie] = owners
    end
    owners[id] = true
    return true
end

local function releaseThreat(reservations, zombie, id)
    local owners = zombie ~= nil and reservations.threats[zombie] or nil
    if type(owners) ~= "table" then
        if owners == id then
            reservations.threats[zombie] = nil
        end
        return
    end
    owners[id] = nil
    local occupied = false
    for _ in pairs(owners) do
        occupied = true
        break
    end
    if not occupied then
        reservations.threats[zombie] = nil
    end
end

local function targetsGroupMember(self, target)
    if target == nil then
        return false
    end
    if target == self.character or target == self.groupLeader
        or target == self.companionTarget then
        return true
    end
    for _, member in ipairs(self.groupMembers or {}) do
        if target == member then
            return true
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local targetId = runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(target)
        or nil
    if targetId ~= nil and KnoxPersistence.areSurvivorsAllied ~= nil then
        return KnoxPersistence.areSurvivorsAllied(self.id, targetId)
    end
    return false
end

local function targetsAnyPlayer(target, distance)
    if target == nil then
        return false
    end
    local maxDist2 = THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
    if distance > maxDist2 then
        return false
    end
    local count = getNumActivePlayers and getNumActivePlayers() or 1
    for pIdx = 0, math.max(0, tonumber(count) or 1) - 1 do
        local p = getSpecificPlayer(pIdx)
        if p ~= nil and target == p then
            return true
        end
    end
    return false
end

local function targetOf(character)
    if character == nil or character.getTarget == nil then return nil end
    local ok, target = pcall(function() return character:getTarget() end)
    return ok and target or nil
end

local function allowSurvivorPlayerCombat()
    local settings = rawget(_G, "KnoxSettings")
    return settings == nil or settings.allowSurvivorPlayerCombat == nil
        or settings.allowSurvivorPlayerCombat()
end

local function hostileHuman(self, character, knownSurvivorId)
    if character == nil or character == self.character then return false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local survivorId = knownSurvivorId or (runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(character) or nil)
    if survivorId ~= nil then
        local now = self.currentTicks or self.nextThreatScan or 0
        -- A threatened survivor may comply briefly while a live robbery
        -- transfer resolves. This is a bounded pause, not a relationship
        -- change: danger, expiry or failed robbery returns normal hostility.
        local hold = self.pendingRobberyHold
        if hold ~= nil and hold.robber == character then
            if now < (tonumber(hold.expiresAt) or 0) then return false end
            self:releaseRobberyHold(character, now, "expired")
        end
        local robbery = self.pendingRobbery
        if robbery ~= nil and robbery.victim == character then
            if now < (tonumber(robbery.expiresAt) or 0) then return false end
            self:cancelRobbery(now, "expired")
        end
        local defenseUntil = self.allyDefenseThreats ~= nil
            and self.allyDefenseThreats[survivorId] or nil
        if defenseUntil ~= nil then
            if now < defenseUntil then return true end
            self.allyDefenseThreats[survivorId] = nil
        end
        return KnoxPersistence.areSurvivorsHostile ~= nil
            and KnoxPersistence.areSurvivorsHostile(self.id, survivorId) or false
    end
    if not allowSurvivorPlayerCombat() then return false end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
                and KnoxPersistence.getSurvivorAffiliation(self.id) or nil
            -- Player-owned companions and residents never acquire a hostile
            -- player target through the personality system.
            if affiliation ~= nil and affiliation.kind == "player" then return false end
            local playerId = KnoxPersistence.ensurePlayerId ~= nil
                and KnoxPersistence.ensurePlayerId(player) or nil
            if playerId == nil then return false end
            if KnoxPersistence.isSurvivorHostileToPlayer ~= nil
                and KnoxPersistence.isSurvivorHostileToPlayer(self.id, playerId) then
                return true
            end
            if affiliation ~= nil and affiliation.factionId ~= nil
                and KnoxPersistence.getPlayerFaction ~= nil
                and KnoxPersistence.getFactionRelationship ~= nil then
                local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
                if playerFaction ~= nil and affiliation.factionId == playerFaction.id then
                    return false
                end
                local relation = playerFaction ~= nil
                    and KnoxPersistence.getFactionRelationship(affiliation.factionId, playerFaction.id)
                    or nil
                if relation ~= nil and relation.disposition == "allied" then return false end
            end
            -- Predatory survivors can initiate a fight when they actually
            -- perceive the player. The threat evaluator still supplies the
            -- same distance, floor, and line-of-sight boundary used for every
            -- other human target, so this is not a map-wide hostility scan.
            if KnoxPersistence.getPlayerSocialDisposition ~= nil
                and KnoxPersistence.getPlayerSocialDisposition(playerId, self.id) == "attack_on_sight" then
                if KnoxPersistence.setSurvivorHostileToPlayer ~= nil then
                    KnoxPersistence.setSurvivorHostileToPlayer(self.id, playerId, true)
                end
                return true
            end
            return false
        end
    end
    return false
end

local function combatAnchor(self)
    if self.companionOrder ~= nil then
        return self.companionTarget
    end
    return self.groupLeader
end

local function withinDutyCombatLeash(self, threat)
    local current, other = self.character:getCurrentSquare(), threat:getCurrentSquare()
    if current == nil or other == nil or current:getZ() ~= other:getZ() then return false end
    local distance = distanceSquared(current, other)
    -- Contact defense remains possible even while returning to a displaced post.
    if distance <= 4 then return true end
    local task = self.baseTask
    local directive = self.companionDirective
    local kind, area
    if directive ~= nil and (directive.kind == "guard" or directive.kind == "patrol_area") then
        kind, area = directive.kind, directive
    elseif task ~= nil and (task.type == "guard" or task.type == "patrol") then
        kind, area = task.type, task.target
    elseif self.base ~= nil then
        kind, area = "resident", self.base.territory or self.base.home
    end
    if kind == nil and task == nil then return true end
    if area ~= nil then
        local minX, minY = tonumber(area.minX or area.x1 or area.x), tonumber(area.minY or area.y1 or area.y)
        local maxX, maxY = tonumber(area.maxX or area.x2) or minX, tonumber(area.maxY or area.y2) or minY
        if kind == "guard" and minX ~= nil and minY ~= nil then
            local patrol = rawget(_G, "KnoxCompanionPatrol")
            local post = task ~= nil and patrol ~= nil and patrol.guardPost ~= nil
                and patrol.guardPost(area, task.id or task.claimedBy) or nil
            local x = post ~= nil and post.x or math.floor((minX + maxX) / 2)
            local y = post ~= nil and post.y or math.floor((minY + maxY) / 2)
            minX, maxX, minY, maxY = x - 4, x + 4, y - 4, y + 4
        end
        if minX ~= nil and minY ~= nil and (other:getX() < math.min(minX, maxX)
            or other:getX() > math.max(minX, maxX) or other:getY() < math.min(minY, maxY)
            or other:getY() > math.max(minY, maxY)) then return false end
        if area.allFloors ~= true and other:getZ() ~= (tonumber(area.z) or 0) then return false end
    end
    local target = targetOf(threat)
    local attackingDuty = target == self.character or targetsGroupMember(self, target)
    -- A worker seeing trouble is not an order to clear the surrounding streets.
    -- Nearby attacks can interrupt; the durable job/post survives that interruption.
    return attackingDuty and distance <= 16
end

local function withinCombatRoleLeash(self, threat)
    if threat == nil or not withinDutyCombatLeash(self, threat) then
        return false
    end
    local target = targetOf(threat)
    if target == self.character then
        return true
    end
    if targetsGroupMember(self, target) then
        local survivorSquare = self.character:getCurrentSquare()
        local threatSquare = threat:getCurrentSquare()
        if survivorSquare ~= nil and threatSquare ~= nil
            and navigationDistanceSquared(survivorSquare, threatSquare)
                <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS then
            return true
        end
    end
    local anchor = combatAnchor(self)
    if anchor == nil then
        return true
    end
    local anchorSquare = anchor:getCurrentSquare()
    local targetSquare = threat:getCurrentSquare()
    return anchorSquare ~= nil and targetSquare ~= nil
        and navigationDistanceSquared(anchorSquare, targetSquare)
            <= Controller.TUNING.GROUP_COMBAT_LEASH_RADIUS * Controller.TUNING.GROUP_COMBAT_LEASH_RADIUS
end

local function threatReasonAndBonus(
    targetingSelf, targetingGroup, targetingPlayer, immediate
)
    if targetingSelf then
        return "active_target", immediate and 240 or 160, 5
    end
    if targetingGroup then
        return "group_target", immediate and 190 or 120, 4
    end
    if immediate then
        return "immediate", 90, 3
    end
    if targetingPlayer then
        return "player_target", 55, 2
    end
    return "visible", 0, 1
end

local function withinZombieEngagement(self, zombie, distance, targetingSelf, targetingGroup)
    if self.companionOrder ~= nil and self.companionCombatStance == "aggressive" then return true end
    local settings = rawget(_G, "KnoxSettings")
    local radius = settings ~= nil and settings.zombieEngagementDistance ~= nil
        and settings.zombieEngagementDistance() or 4
    if targetingSelf or targetingGroup then radius = math.max(radius, 8) end
    if zombie == self.combatTarget then radius = math.max(radius, 6) end
    if (self.nightSweepUntil or 0) > (self.currentTicks or 0) then
        radius = math.max(radius, Controller.TUNING.NIGHT_SWEEP_RADIUS)
    end
    return distance <= radius * radius
end

-- Reservations are loaded-world leases. Error recovery must not depend on the
-- controller remembering which local pointer acquired each lease: an exception
-- can occur between the reservation and that pointer being assigned.
function Controller.hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function releaseAllReservationsForOwner(reservations, id)
    if type(reservations) ~= "table" then return 0 end
    local released = 0
    for kind, bucket in pairs(reservations) do
        if type(bucket) == "table" then
            if kind == "threats" then
                for target, owners in pairs(bucket) do
                    if type(owners) == "table" then
                        if owners[id] ~= nil then
                            owners[id] = nil
                            released = released + 1
                        end
                        if not Controller.hasEntries(owners) then bucket[target] = nil end
                    elseif owners == id then
                        bucket[target] = nil
                        released = released + 1
                    end
                end
            else
                for key, owner in pairs(bucket) do
                    if owner == id then
                        bucket[key] = nil
                        released = released + 1
                    end
                end
            end
        end
    end
    return released
end

local function safeMethod(object, methodName, fallback, ...)
    if object == nil then
        return fallback
    end
    local lookupOk, method = pcall(function() return object[methodName] end)
    if not lookupOk or type(method) ~= "function" then
        return fallback
    end
    local ok, value = pcall(method, object, ...)
    if not ok or value == nil then
        return fallback
    end
    return value
end

local function separatedByImmediateBarrier(first, second)
    if first == nil or second == nil or first:getZ() ~= second:getZ() then return true end
    local dx = math.abs(first:getX() - second:getX())
    local dy = math.abs(first:getY() - second:getY())
    if dx > 1 or dy > 1 or (dx == 0 and dy == 0) then return false end
    return safeMethod(first, "isBlockedTo", false, second)
        or safeMethod(first, "isHoppableTo", false, second)
end

-- (wall/window gate inlined at evaluateThreat call site; see below)

local function evaluateThreat(self, zombie, ticks)
    local square = self.character:getCurrentSquare()
    local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
    local distance = square ~= nil and zombieSquare ~= nil
        and distanceSquared(square, zombieSquare) or math.huge
    if square == nil or zombie == nil or zombie:isDead() or isCorpseProxy(zombie) or zombieSquare == nil
        or zombieSquare:getZ() ~= square:getZ()
        or distance > THREAT_MAX_DISTANCE_SQUARED
        or threatUnavailable(self, zombie, ticks)
        or not withinCombatRoleLeash(self, zombie) then
        if self.perceivedThreats ~= nil and zombie ~= nil then
            self.perceivedThreats[zombie] = nil
        end
        return nil
    end
    -- Escaping a crowd must not immediately become a fresh five-tile chase.
    -- Nearby self-defense remains available, but distant acquisition waits.
    if ticks < (self.combatDisengageUntil or 0) and distance > 3.0625 then
        return nil
    end
    local humanThreat = hostileHuman(self, zombie)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local isHuman = humanThreat or (runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(zombie) ~= nil)
    for playerNum = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
        if getSpecificPlayer(playerNum) == zombie then isHuman = true; break end
    end
    if isHuman and not humanThreat then return nil end
    local target = targetOf(zombie)
    local targetingSelf = target == self.character
        and distance <= THREAT_SELF_TARGET_RADIUS * THREAT_SELF_TARGET_RADIUS
    local targetingGroup = target ~= self.character
        and targetsGroupMember(self, target)
        and distance <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
    local targetingPlayer = targetsAnyPlayer(target, distance)
    local immediate = distance <= THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS
    if not isHuman and separatedByImmediateBarrier(square, zombieSquare) then
        if self.perceivedThreats ~= nil then self.perceivedThreats[zombie] = nil end
        return nil
    end
    local visible = false
    if distance <= THREAT_VISIBLE_RADIUS * THREAT_VISIBLE_RADIUS then
        local success, result = pcall(function()
            return self.character:CanSee(zombie)
        end)
        visible = success and result == true
    end
    -- Wall/window gate (inlined to respect Lua 5.1's 200-locals limit):
    -- A never-seen zed with no native LOS must not be acquired through a
    -- wall/window (exterior zeds behind glass). Recently-seen memory still
    -- flows to the bounded remembered path below for avoidance; it expires
    -- on its normal timer and carries a score penalty so it cannot drive a
    -- fresh back-and-forth chase. Adjacent self-defense stays responsive.
    do
        local blocked = false
        if square == nil or zombieSquare == nil then
            blocked = true
        elseif square:getZ() ~= zombieSquare:getZ() then
            blocked = true
        elseif visible == true then
            blocked = false
        elseif (tonumber(distance) or math.huge) <= 2.25 and target == self.character then
            blocked = false
        else
            local memory = self.perceivedThreats ~= nil and self.perceivedThreats[zombie] or nil
            local fresh = memory ~= nil
                and ticks - (memory.lastSeen or -THREAT_MEMORY_TICKS - 1) <= THREAT_MEMORY_TICKS
                and distance <= COMBAT_DISENGAGE_RADIUS * COMBAT_DISENGAGE_RADIUS
            blocked = not fresh
        end
        if not isHuman and blocked then
            if self.perceivedThreats ~= nil then self.perceivedThreats[zombie] = nil end
            return nil
        end
    end
    self.perceivedThreats = self.perceivedThreats
        or setmetatable({}, { __mode = "k" })
    local perceived = visible or targetingSelf or targetingGroup or targetingPlayer
    local remembered = false
    if perceived then
        self.perceivedThreats[zombie] = { lastSeen = ticks }
    else
        local memory = self.perceivedThreats[zombie]
        remembered = memory ~= nil
            and ticks - (memory.lastSeen or -THREAT_MEMORY_TICKS - 1)
                <= THREAT_MEMORY_TICKS
            and distance <= COMBAT_DISENGAGE_RADIUS * COMBAT_DISENGAGE_RADIUS
        if not remembered then
            self.perceivedThreats[zombie] = nil
            return nil
        end
    end
    -- Perception is not permission to hunt. Keep sightings for avoidance, while
    -- only nearby danger can interrupt a routine route or start an automatic fight.
    if not isHuman and not withinZombieEngagement(self, zombie, distance, targetingSelf, targetingGroup) then
        return nil
    end
    local reason, bonus, priority
    if remembered then
        reason, bonus, priority = "remembered", -Controller.TUNING.THREAT_MEMORY_SCORE_PENALTY, 0
    else
        reason, bonus, priority = threatReasonAndBonus(
            targetingSelf, targetingGroup, targetingPlayer, immediate and visible
        )
    end
    local onFloor, crawling = false, false
    if zombie.isOnFloor ~= nil then
        local ok, value = pcall(function() return zombie:isOnFloor() end)
        onFloor = ok and value == true
    end
    if zombie.isCrawling ~= nil then
        local ok, value = pcall(function() return zombie:isCrawling() end)
        crawling = ok and value == true
    end
    local downed = onFloor and not crawling
    if downed then
        -- A knocked-down zombie remains a valid target, but it must not hide a
        -- standing attacker that is already reaching the survivor or an ally.
        priority = math.max(0, priority - 2)
    end
    local reservationCount = threatReservationCount(self.reservations, zombie, self.id)
    return {
        reason = reason,
        priority = priority,
        distance = math.sqrt(distance),
        distanceSquared = distance,
        reservationCount = reservationCount,
        attackerLimit = threatAttackerLimit(reason),
        score = distance - bonus + reservationCount * 24 + (downed and 120 or 0)
            + (humanThreat and -35 or 0),
        downed = downed,
        human = humanThreat,
    }
end

local function nearestThreat(self, ticks)
    local cell = getCell()
    if self.character:getCurrentSquare() == nil or cell == nil then
        return nil
    end
    local nearest, nearestAwareness = nil, nil
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local scenarioOwner = rawget(_G, "KnoxCombatTestScenarios") ~= nil
            and KnoxCombatTestScenarios.preferredNpcId ~= nil
            and KnoxCombatTestScenarios.preferredNpcId(zombie) or nil
        if scenarioOwner == nil or scenarioOwner == self.id then
            local awareness = evaluateThreat(self, zombie, ticks)
            if awareness ~= nil
                and awareness.reservationCount < awareness.attackerLimit
                and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                nearest = zombie
                nearestAwareness = awareness
            end
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.activeIds ~= nil and runtime.getCharacter ~= nil then
        for _, otherId in ipairs(runtime.activeIds()) do
            if otherId ~= self.id then
                local human = runtime.getCharacter(otherId)
                local awareness = hostileHuman(self, human) and evaluateThreat(self, human, ticks) or nil
                if awareness ~= nil
                    and awareness.reservationCount < awareness.attackerLimit
                    and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                    nearest, nearestAwareness = human, awareness
                end
            end
        end
    end
    if allowSurvivorPlayerCombat() then
        local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
        for playerNum = 0, math.max(0, count - 1) do
            local human = getSpecificPlayer(playerNum)
            local awareness = hostileHuman(self, human) and evaluateThreat(self, human, ticks) or nil
            if awareness ~= nil
                and awareness.reservationCount < awareness.attackerLimit
                and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                nearest, nearestAwareness = human, awareness
            end
        end
    end
    self.pendingThreatAwareness = nearestAwareness
    return nearest
end

function Controller:selectCombatThreat(ticks)
    return nearestThreat(self, ticks)
end

local function shouldReplaceCombatTarget(self, candidate, awareness, ticks)
    if candidate == nil or candidate == self.combatTarget then
        return false
    end
    local current = self.combatTarget
    local candidateAwareness = awareness or evaluateThreat(self, candidate, ticks)
    if candidateAwareness == nil then
        return false
    end
    local currentAwareness = current ~= nil and evaluateThreat(self, current, ticks) or nil
    if currentAwareness == nil then
        return true
    end
    local improvement = currentAwareness.score - candidateAwareness.score
    local inCooldown = ticks - (self.lastCombatRetarget
        or -COMBAT_RETARGET_COOLDOWN_TICKS) < COMBAT_RETARGET_COOLDOWN_TICKS
    if inCooldown then
        return candidateAwareness.priority > currentAwareness.priority
            and improvement >= Controller.TUNING.COMBAT_EMERGENCY_SCORE_MARGIN
    end
    return improvement >= Controller.TUNING.COMBAT_RETARGET_SCORE_MARGIN
end

local function shouldDropCombatTarget(self, ticks)
    local target = self.combatTarget
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local human = target ~= nil and runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(target) ~= nil
    for playerNum = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
        if target ~= nil and getSpecificPlayer(playerNum) == target then human = true; break end
    end
    -- Recruitment/peace or a sandbox change can invalidate hostility mid-fight.
    -- Check before the target's stale attack intent grants continued self-defense.
    if human and not hostileHuman(self, target) then return true end
    local survivorSquare = self.character:getCurrentSquare()
    local targetSquare = target ~= nil and target:getCurrentSquare() or nil
    if target == nil or target:isDead() or isCorpseProxy(target) or survivorSquare == nil or targetSquare == nil
        or targetSquare:getZ() ~= survivorSquare:getZ()
        or not withinCombatRoleLeash(self, target) then
        return true
    end
    local targetObject = targetOf(target)
    if not human and not withinZombieEngagement(self, target,
        distanceSquared(survivorSquare, targetSquare), targetObject == self.character,
        targetsGroupMember(self, targetObject)) then return true end
    -- An enemy can retain an old target after separation. That reference is
    -- not permission to abandon a base/group and chase across the map.
    local leash = targetObject == self.character
        and THREAT_SELF_TARGET_RADIUS or COMBAT_DISENGAGE_RADIUS
    if distanceSquared(survivorSquare, targetSquare) > leash * leash then return true end
    if targetObject == self.character or targetsGroupMember(self, targetObject) then
        return false
    end
    return evaluateThreat(self, target, ticks) == nil
end

function Controller:evaluateCombatThreat(zombie, ticks)
    return evaluateThreat(self, zombie, ticks)
end

function Controller:shouldReplaceCombatTarget(candidate, awareness, ticks)
    return shouldReplaceCombatTarget(self, candidate, awareness, ticks)
end

function Controller:shouldDropCombatTarget(ticks)
    return shouldDropCombatTarget(self, ticks)
end

local function nearbyHostileHumans(self, radius)
    local square = self.character:getCurrentSquare()
    local found, seen = {}, {}
    if square == nil then return found end
    local function include(character, survivorId)
        if character == nil or character == self.character or seen[character] then return end
        seen[character] = true
        local other = safeMethod(character, "getCurrentSquare", nil)
        -- Range/floor checks precede relationship lookups for distant residents.
        if other ~= nil and other:getZ() == square:getZ()
            and distanceSquared(square, other) <= radius * radius
            and safeMethod(character, "isDead", false) ~= true
            and hostileHuman(self, character, survivorId) then
            found[#found + 1] = character
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.activeIds ~= nil and runtime.getCharacter ~= nil then
        for _, id in ipairs(runtime.activeIds()) do
            if id ~= self.id then include(runtime.getCharacter(id), id) end
        end
    end
    if allowSurvivorPlayerCombat() and getSpecificPlayer ~= nil then
        local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
        for index = 0, math.max(0, count - 1) do include(getSpecificPlayer(index)) end
    end
    return found
end

local function nearbyRetreatThreats(self, radius)
    local square = self.character:getCurrentSquare()
    local cell = getCell()
    local found, humans = {}, {}
    if square == nil or cell == nil then return found, humans end
    local zombies = cell:getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z ~= nil and not z:isDead() and not isCorpseProxy(z) and z:getCurrentSquare() ~= nil and z:getCurrentSquare():getZ() == square:getZ() then
            if distanceSquared(square, z:getCurrentSquare()) <= radius * radius then
                found[#found + 1] = z
            end
        end
    end
    for _, human in ipairs(nearbyHostileHumans(self, radius)) do
        found[#found + 1], humans[human] = human, true
    end
    return found, humans
end

local function shouldRemainStealthy(self)
    if self.companionOrder ~= nil and self.companionCombatStance == "aggressive" then return false end
    local square = self.character ~= nil and self.character:getCurrentSquare() or nil
    local cell = getCell()
    if square == nil or cell == nil then return false end
    local settings = rawget(_G, "KnoxSettings")
    local cautious = settings == nil or settings.cautiousTravel == nil or settings.cautiousTravel()
    local minimum = cautious and 1 or 3
    local nearby = 0
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombieSquare ~= nil
            and zombieSquare:getZ() == square:getZ() then
            local distance = distanceSquared(square, zombieSquare)
            if distance <= 144 then
                local target = zombie:getTarget()
                if distance <= 64 and (target == self.character or targetsGroupMember(self, target)
                    or targetsAnyPlayer(target, distance)) then return false end
                -- Spotted means fight: a targetless zombie inside 6 tiles
                -- that can geometrically see us has our scent and is
                -- closing. Sneaking past it only delays the bite to arm's
                -- length, so drop stealth and let threat handling engage.
                if target == nil and distance <= 36 then
                    local okSeen, seen = pcall(function()
                        return zombie:CanSee(self.character)
                    end)
                    if okSeen and seen == true then return false end
                end
                -- Continue through the entire nearby set: a later attacker or
                -- contact-range zombie must override an earlier quiet sighting.
                if nearby < minimum or distance <= 4 then
                    local ok, visible = pcall(function() return self.character:CanSee(zombie) end)
                    if ok and visible == true then
                        if distance <= 4 then return false end
                        nearby = nearby + 1
                    end
                end
            end
        end
    end
    if nearby < minimum then return false end
    for _, human in ipairs(nearbyHostileHumans(self, 12)) do
        local target = targetOf(human)
        if target == self.character or targetsGroupMember(self, target)
            or safeMethod(self.character, "CanSee", false, human) == true then return false end
    end
    return true
end

function Controller.shouldRemainStealthy(self)
    return shouldRemainStealthy(self)
end

local function nearbyAllyCount(self, radius)
    local square = self.character:getCurrentSquare()
    if square == nil then return 1 end
    local seen = { [self.character] = true }
    local count = 1
    local function include(character)
        local dead = false
        if character ~= nil then
            local ok, result = pcall(function() return character:isDead() end)
            dead = ok and result == true
        end
        if character ~= nil and not dead and not seen[character]
            and character:getCurrentSquare() ~= nil
            and character:getCurrentSquare():getZ() == square:getZ()
            and distanceSquared(square, character:getCurrentSquare()) <= radius * radius then
            seen[character] = true
            count = count + 1
        end
    end
    include(self.groupLeader)
    include(self.companionTarget)
    for _, member in ipairs(self.groupMembers or {}) do include(member) end
    return count
end

local function injuryRisk(character)
    local bleeding, severe = 0, 0
    local bodyDamage = safeMethod(character, "getBodyDamage", nil)
    local parts = safeMethod(bodyDamage, "getBodyParts", nil)
    if parts == nil then
        return bleeding, severe
    end
    local size = tonumber(safeMethod(parts, "size", 0)) or 0
    for index = 0, size - 1 do
        local part = safeMethod(parts, "get", nil, index)
        local bandaged = safeMethod(part, "bandaged", false) == true
        if safeMethod(part, "bleeding", false) == true and not bandaged then
            bleeding = bleeding + 1
        end
        if safeMethod(part, "bitten", false) == true
            or safeMethod(part, "isDeepWounded", false) == true
            or safeMethod(part, "isCut", false) == true
            or (tonumber(safeMethod(part, "getFractureTime", 0)) or 0) > 0 then
            severe = severe + 1
        end
    end
    return bleeding, severe
end

local function weaponCapacity(character)
    local weapon = safeMethod(character, "getPrimaryHandItem", nil)
    if weapon == nil then
        return 0, 0, false
    end
    local broken = safeMethod(weapon, "isBroken", false) == true
    local condition = tonumber(safeMethod(weapon, "getCondition", 0)) or 0
    local conditionMax = math.max(1,
        tonumber(safeMethod(weapon, "getConditionMax", 1)) or 1)
    if broken or condition <= 0 then
        return 0, 0, false
    end
    local reach = math.max(0,
        tonumber(safeMethod(weapon, "getMaxRange", 0, character)) or 0)
    local skill = math.max(0,
        tonumber(safeMethod(weapon, "getWeaponSkill", 0, character)) or 0)
    return reach, skill, condition / conditionMax
end

-- A standable destination behind a wall is not an immediately usable escape lane.
-- This checks only a short loaded segment; native routing/traversal still own movement.
local function fleeLaneClear(origin, target)
    local cell = getCell()
    if origin == nil or target == nil or cell == nil or origin:getZ() ~= target:getZ() then return false end
    local dx, dy = target:getX() - origin:getX(), target:getY() - origin:getY()
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps > FLEE_TARGET_DISTANCE + 2 then return false end
    local previous = origin
    for step = 1, steps do
        local nextSquare = cell:getGridSquare(
            math.floor(origin:getX() + dx * step / steps + 0.5),
            math.floor(origin:getY() + dy * step / steps + 0.5), origin:getZ())
        if nextSquare == nil or not nextSquare:canStand()
            or safeMethod(previous, "isBlockedTo", true, nextSquare)
            or safeMethod(previous, "isHoppableTo", true, nextSquare) then return false end
        previous = nextSquare
    end
    return true
end

local function fleeRouteSafety(origin, target, threats)
    if origin == nil or target == nil then return nil end
    local dx, dy = target:getX() - origin:getX(), target:getY() - origin:getY()
    local length2 = dx * dx + dy * dy
    if length2 == 0 then return nil end
    local nearest, nearestStart = math.huge, math.huge
    for _, zombie in ipairs(threats) do
        local square = zombie:getCurrentSquare()
        local zx, zy = square:getX() - origin:getX(), square:getY() - origin:getY()
        local startDistance = zx * zx + zy * zy
        nearestStart = math.min(nearestStart, startDistance)
        local progress = math.max(0, math.min(1, (zx * dx + zy * dy) / length2))
        local clearance = (zx - dx * progress)^2 + (zy - dy * progress)^2
        -- Already-touching attackers must not prevent movement away, but a safe
        -- endpoint across a zombie is not a safe route through that zombie.
        if clearance < math.min(startDistance, 1.5625) - 0.01 then return nil end
        nearest = math.min(nearest, distanceSquared(target, square))
    end
    if nearest < math.huge and nearest <= nearestStart + 0.25 then return nil end
    return nearest
end

local function fleeDestinationAvailable(self, square, ticks)
    local failed = self.failedFleeTarget
    if failed ~= nil and ticks < failed.untilTick and square ~= nil
        and square:getZ() == failed.z
        and (square:getX() - failed.x)^2 + (square:getY() - failed.y)^2 <= 9 then return false end
    return fleeLaneClear(self.character:getCurrentSquare(), square)
end

local function openEscapeLaneCount(origin, threats)
    local cell = getCell()
    if origin == nil or cell == nil or #threats == 0 then return 0 end
    local currentNearest = math.huge
    for _, zombie in ipairs(threats) do
        currentNearest = math.min(currentNearest,
            distanceSquared(origin, zombie:getCurrentSquare()))
    end
    local count = 0
    for _, direction in ipairs({
        { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
    }) do
        local candidate = cell:getGridSquare(
            origin:getX() + direction[1] * 3,
            origin:getY() + direction[2] * 3,
            origin:getZ()
        )
        if candidate ~= nil and candidate:canStand() and fleeLaneClear(origin, candidate) then
            local nearest = math.huge
            for _, zombie in ipairs(threats) do
                nearest = math.min(nearest,
                    distanceSquared(candidate, zombie:getCurrentSquare()))
            end
            if nearest >= currentNearest + 1 then
                count = count + 1
            end
        end
    end
    return count
end

local function fleeAssessment(self)
    local origin = self.character ~= nil and self.character:getCurrentSquare() or nil
    if origin == nil then
        return false, { reason = "no_square", zombies = 0, humans = 0, allies = 1,
            health = 100, endurance = 1, risk = 0, immediate = 0,
            escapeLanes = 0, nearestDistanceSquared = math.huge }
    end
    local threats, humans = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS)
    local health = tonumber(safeMethod(self.character, "getHealth", 100)) or 100
    if health <= 1 then health = health * 100 end
    local stats = safeMethod(self.character, "getStats", nil)
    local enduranceStat = CharacterStat ~= nil and CharacterStat.ENDURANCE or "endurance"
    local endurance = tonumber(safeMethod(stats, "get", 1, enduranceStat)) or 1
    local bleeding, severe = injuryRisk(self.character)
    local reach, skill, condition = weaponCapacity(self.character)
    condition = tonumber(condition) or 0
    local allies = nearbyAllyCount(self, FLEE_SCAN_RADIUS)
    local observed, humansObserved, immediate, close, targeting = 0, 0, 0, 0, 0
    local nearest = math.huge
    for _, threat in ipairs(threats) do
        local square = safeMethod(threat, "getCurrentSquare", nil)
        if square ~= nil then
            local distance = distanceSquared(origin, square)
            local target = targetOf(threat)
            local targetsUs = target == self.character or targetsGroupMember(self, target)
            local visible = safeMethod(self.character, "CanSee", false, threat) == true
            -- Do not retreat from an unseen non-attacker behind a wall. A real
            -- attacker still counts even if the survivor has not yet acquired
            -- visual confirmation.
            if visible or targetsUs then
                observed = observed + 1
                if humans[threat] then humansObserved = humansObserved + 1 end
                nearest = math.min(nearest, distance)
                if distance <= THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS then
                    immediate = immediate + 1
                end
                if distance <= 36 then close = close + 1 end
                if targetsUs then targeting = targeting + 1 end
            end
        end
    end
    local escapeLanes = openEscapeLaneCount(origin, threats)
    local outnumbered = observed >= math.max(3, allies * 3)
    local vulnerable = health <= 55 or endurance <= 0.25 or bleeding > 0 or severe > 0
    local critical = health <= 25 or severe >= 3
    -- A good real weapon and nearby allies buy room for a small fight; they do
    -- not make a surrounded or injured survivor fearless.
    local defence = (reach > 0 and 1 or 0) + math.min(1, skill / 4)
        + (condition >= 0.5 and 0.5 or 0)
    local pressure = immediate * 3 + close + targeting * 3
        + math.max(0, observed - allies * 2) + bleeding * 2 + severe * 3
        + (endurance <= 0.25 and 2 or 0) + (health <= 55 and 2 or 0) - defence
    local threatened = immediate > 0 or targeting > 0
    local retreat = escapeLanes > 0 and threatened and (
        (outnumbered and pressure >= 7)
        or (vulnerable and pressure >= 5)
        or (critical and observed > 0)
        or (immediate >= 3 and observed > allies * 2)
    )
    local reason = nil
    if retreat then
        if critical then reason = "critical_health"
        elseif outnumbered then reason = "outnumbered"
        elseif endurance <= 0.25 then reason = "exhausted"
        elseif bleeding > 0 or severe > 0 then reason = "injured"
        else reason = "overwhelmed" end
    end
    return retreat, {
        reason = reason, zombies = observed - humansObserved, humans = humansObserved,
        allies = allies, health = health, endurance = endurance, bleeding = bleeding,
        severe = severe, weaponReach = reach, weaponSkill = skill, weaponCondition = condition,
        risk = pressure, immediate = immediate, close = close, targeting = targeting,
        escapeLanes = escapeLanes, nearestDistanceSquared = nearest,
    }
end

-- Kept as a controller method so the policy can be verified without starting a
-- move or mutating combat state. Runtime decisions still use the same helper.
function Controller:assessFlee()
    return fleeAssessment(self)
end

local function retreatIsSafelyClear(self, stillUnsafe, assessment, ticks)
    local pursued = assessment ~= nil and ((assessment.immediate or 0) > 0
        or (assessment.close or 0) > 0 or (assessment.targeting or 0) > 0
        or (assessment.nearestDistanceSquared or math.huge) < FLEE_CLEAR_DISTANCE_SQUARED)
    if stillUnsafe or pursued then
        self.fleeSafeScans = 0
        self.fleeLastSafeScan = nil
        return false
    end
    if ticks ~= nil and self.fleeLastSafeScan == ticks then return false end
    self.fleeLastSafeScan = ticks
    self.fleeSafeScans = (self.fleeSafeScans or 0) + 1
    return self.fleeSafeScans >= FLEE_SAFE_CONFIRM_SCANS
end

function Controller:retreatIsSafelyClear(stillUnsafe, assessment, ticks)
    return retreatIsSafelyClear(self, stillUnsafe, assessment, ticks)
end

local function appendFleeDirection(directions, x, y)
    local length = math.sqrt(x * x + y * y)
    if length < 0.01 then return end
    x, y = x / length, y / length
    for _, direction in ipairs(directions) do
        if direction.x * x + direction.y * y > 0.985 then
            return
        end
    end
    directions[#directions + 1] = { x = x, y = y }
end

local function findFleeTarget(self, ticks)
    local origin = self.character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then return nil end
    local awayX, awayY = 0, 0
    local threats = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)
    for _, zombie in ipairs(threats) do
        local zs = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zs ~= nil
            and zs:getZ() == origin:getZ() then
            local dx = origin:getX() - zs:getX()
            local dy = origin:getY() - zs:getY()
            local distance2 = dx * dx + dy * dy
            if distance2 <= (FLEE_SCAN_RADIUS + 4) ^ 2 and distance2 > 0 then
                -- Nearby bodies matter more than the edge of the horde. This
                -- points the escape route away from the actual pressure instead
                -- of letting several distant zombies cancel one close threat.
                local weight = 1 / distance2
                awayX = awayX + dx * weight
                awayY = awayY + dy * weight
            end
        end
    end
    local length = math.sqrt(awayX * awayX + awayY * awayY)
    local directions = {}
    if self.lastFleeDirectionX ~= nil and ticks <= (self.fleeDirectionUntil or -1) then
        appendFleeDirection(directions, self.lastFleeDirectionX, self.lastFleeDirectionY)
    end
    if length >= 0.01 then
        awayX, awayY = awayX / length, awayY / length
        appendFleeDirection(directions, awayX, awayY)
        appendFleeDirection(directions, awayX - awayY, awayY + awayX)
        appendFleeDirection(directions, awayX + awayY, awayY - awayX)
        appendFleeDirection(directions, -awayY, awayX)
        appendFleeDirection(directions, awayY, -awayX)
    end
    do
        -- Also consider tangents/backtracking when the away-vector hits a wall.
        -- Fixed candidates keep recovery deterministic, not random pacing.
        for _, direction in ipairs({
            { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
            { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
        }) do
            appendFleeDirection(directions, direction[1], direction[2])
        end
    end
    local best, bestScore = nil, -math.huge
    for _, direction in ipairs(directions) do
        for distance = FLEE_TARGET_DISTANCE, 2, -1 do
            local x = math.floor(origin:getX() + direction.x * distance + 0.5)
            local y = math.floor(origin:getY() + direction.y * distance + 0.5)
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:canStand() and fleeDestinationAvailable(self, square, ticks) then
                local nearest = fleeRouteSafety(origin, square, threats)
                local alignment = 0
                if self.lastFleeDirectionX ~= nil
                    and ticks <= (self.fleeDirectionUntil or -1) then
                    alignment = (direction.x * self.lastFleeDirectionX
                        + direction.y * self.lastFleeDirectionY) * 8
                end
                if nearest ~= nil then
                    local score = nearest + distance * 0.5 + alignment
                    if score > bestScore then best, bestScore = square, score end
                end
            end
        end
    end
    return best
end

function Controller:findFleeTarget(ticks)
    return findFleeTarget(self, ticks)
end

-- If a survivor is forbidden from fighting, waiting for a perfectly clear
-- lane is equivalent to standing still while the horde closes.  This is a
-- last-resort panic route only: normal fleeing still requires a checked lane,
-- and an armed survivor gets the existing adjacent-combat fallback.  The
-- native mover owns the actual traversal, so this target is deliberately short
-- and chosen by threat distance rather than by a long speculative route.
local function findEmergencyFleeTarget(self, ticks)
    local origin = self.character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then return nil end
    local threats = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)
    if #threats == 0 then return nil end
    local currentNearest = math.huge
    for _, zombie in ipairs(threats) do
        currentNearest = math.min(currentNearest,
            distanceSquared(origin, zombie:getCurrentSquare()))
    end
    local best, bestScore = nil, -math.huge
    local directions = {
        { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
    }
    for distance = math.min(FLEE_TARGET_DISTANCE, 8), 1, -1 do
        for _, direction in ipairs(directions) do
            local square = cell:getGridSquare(
                origin:getX() + direction[1] * distance,
                origin:getY() + direction[2] * distance,
                origin:getZ()
            )
            local failed = self.failedFleeTarget
            local recentlyFailed = failed ~= nil and ticks < failed.untilTick
                and square ~= nil and square:getZ() == failed.z
                and (square:getX() - failed.x)^2 + (square:getY() - failed.y)^2 <= 9
            if square ~= nil and square:canStand() and not recentlyFailed then
                local nearest = math.huge
                local occupied = false
                for _, zombie in ipairs(threats) do
                    local threatSquare = zombie:getCurrentSquare()
                    local threatDistance = distanceSquared(square, threatSquare)
                    nearest = math.min(nearest, threatDistance)
                    if threatDistance <= 2.25 then occupied = true end
                end
                if not occupied and nearest > currentNearest + 0.25 then
                    local score = nearest + distance * 0.25
                    if score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
        if best ~= nil then return best end
    end
    return nil
end

function Controller:findEmergencyFleeTarget(ticks)
    return findEmergencyFleeTarget(self, ticks)
end

local function groupFleeKey(self)
    if self.groupLeaderId ~= nil then
        return self.groupLeaderId
    end
    if #(self.groupMembers or {}) > 1 then
        return self.id
    end
    return nil
end

local function groupFleeTarget(self, ticks)
    local key = groupFleeKey(self)
    if key == nil then return nil, false end
    local plan = fleePlans[key]
    if plan == nil or (tonumber(plan.expiresAt) or -1) < ticks then
        fleePlans[key] = nil
        return nil, false
    end
    local cell = getCell()
    if cell == nil then return nil, true end
    -- Members use small, deterministic offsets around their leader's safe
    -- destination.  That keeps a fleeing group together without stacking every
    -- body on one tile or forcing a second, contradictory threat calculation.
    local slot = math.max(1, tonumber(self.groupFormationSlot) or 1)
    local offsets = {
        { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }
    local offset = offsets[((slot - 1) % #offsets) + 1]
    local square = cell:getGridSquare(
        plan.x + offset[1], plan.y + offset[2], plan.z
    )
    if square ~= nil and square:canStand() then
        local current = self.character:getCurrentSquare()
        if current ~= nil and navigationDistanceSquared(current, square) <= 2.25 then
            return nil, true
        end
        if fleeDestinationAvailable(self, square, ticks)
            and fleeRouteSafety(current, square,
                nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)) ~= nil then
            return square, true
        end
    end
    local center = cell:getGridSquare(plan.x, plan.y, plan.z)
    return center ~= nil and center:canStand() and fleeDestinationAvailable(self, center, ticks)
        and fleeRouteSafety(self.character:getCurrentSquare(), center,
            nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)) ~= nil
        and center or nil, true
end

local function itemMatchesGoal(item, goal, character)
    if goal == "find_food" then
        return KnoxSurvivorNeeds.isSafeFood(item)
    end
    if goal == "find_water" then
        local thirst = character:getStats():get(CharacterStat.THIRST)
        return KnoxSurvivorNeeds.isWaterItem(item, thirst >= 0.90)
    end
    if goal == "find_medical" then
        return (KnoxSurvivorLooting ~= nil
                and KnoxSurvivorLooting.isMedicalSupply ~= nil
                and KnoxSurvivorLooting.isMedicalSupply(item) == true)
            or item:getFullType() == "Base.Sheet"
            or (item:IsClothing() and item:getFabricType() == "Cotton")
    end
    if goal == "find_weapon" then
        return KnoxEquipmentIntelligence ~= nil
            and KnoxEquipmentIntelligence.isMeaningfulWeaponUpgrade ~= nil
            and KnoxEquipmentIntelligence.isMeaningfulWeaponUpgrade(character, item) == true
    end
    if goal == "find_tools" then
        return KnoxSurvivorLooting ~= nil
            and KnoxSurvivorLooting.isEssentialTool ~= nil
            and KnoxSurvivorLooting.isEssentialTool(item) == true
    end
    -- Settlement categories reuse the typed storage matchers so fetched
    -- items always have an assigned store waiting for them.
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage ~= nil and storage.matchesCategory ~= nil then
        if goal == "find_wood" then
            local ok, match = pcall(function()
                return storage.matchesCategory(item, "logs")
            end)
            return ok and match == true
        end
        if goal == "find_materials" then
            local ok, match = pcall(function()
                return storage.matchesCategory(item, "building")
            end)
            return ok and match == true
        end
        if goal == "find_clothing" then
            local ok, match = pcall(function()
                return storage.matchesCategory(item, "clothing")
            end)
            return ok and match == true
        end
        if goal == "find_ammo" then
            local ok, match = pcall(function()
                return storage.matchesCategory(item, "ammunition")
            end)
            return ok and match == true
        end
    end
    return false
end

local function containerUnavailable(self, container, ticks)
    local value = self.inspectedContainers[container]
    if type(value) == "number" and value <= ticks then
        self.inspectedContainers[container] = nil
        return false
    end
    return value ~= nil
end

local function containerArea(container)
    local square = container ~= nil and container:getSourceGrid() or nil
    if square == nil then
        return nil
    end
    return square:getRoom() or square
end

local function areaUnavailable(self, container, ticks)
    local area = containerArea(container)
    local unavailableUntil = area ~= nil and self.blockedAreas[area] or nil
    if type(unavailableUntil) == "number" and unavailableUntil <= ticks then
        self.blockedAreas[area] = nil
        return false
    end
    return unavailableUntil ~= nil
end

local function markPendingAreaBlocked(self, ticks, reason)
    local container = self.pendingSupply ~= nil and self.pendingSupply.container or nil
    local area = containerArea(container)
    if area ~= nil then
        self.blockedAreas[area] = ticks + BLOCKED_AREA_COOLDOWN_TICKS
    end
    self.forceTravel = true
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " blocked-area=" .. tostring(reason)
            .. " retry=" .. tostring(BLOCKED_AREA_COOLDOWN_TICKS)
    )
end

function Controller:hasNeedEscort()
    if self.baseId ~= nil or self.baseTask ~= nil then return false end
    return self.companionOrder ~= nil and self.companionDirective == nil
        or self.groupLeaderId ~= nil or self.groupLeader ~= nil
end

function Controller:allowNeedDetour(square, ticks, checkRoute)
    if not self:hasNeedEscort() then return true end
    if self.companionOrder == "hold" then return false end
    local leader = self.companionOrder ~= nil and self.companionTarget or self.groupLeader
    local anchor = leader ~= nil and leader:getCurrentSquare() or nil
    local origin = self.character:getCurrentSquare()
    if square == nil or anchor == nil or origin == nil
        or square:getZ() ~= anchor:getZ() or square:getZ() ~= origin:getZ()
        or distanceSquared(origin, square) > 16
        or distanceSquared(anchor, square) > 36
        or safeMethod(leader, "isDead", true) then return false end
    -- Reuse short-lived perceptions; do not add a population scan per container.
    for threat, memory in pairs(self.perceivedThreats or {}) do
        local threatSquare = safeMethod(threat, "getCurrentSquare", nil)
        if ticks - (memory.lastSeen or 0) <= THREAT_MEMORY_TICKS
            and not safeMethod(threat, "isDead", true)
            and threatSquare ~= nil and threatSquare:getZ() == square:getZ()
            and (distanceSquared(threatSquare, square) <= 36
                or distanceSquared(threatSquare, origin) <= 36) then return false end
    end
    return checkRoute == false or fleeLaneClear(origin, square)
end

Controller.waterSourceBoundaryContains = function(self, square)
    if square == nil then return false end
    if self ~= nil and self.baseId ~= nil then
        if self.base ~= nil and KnoxBaseManager ~= nil
            and KnoxBaseManager.containsSquare ~= nil
            and KnoxBaseManager.containsSquare(self.base, square) == true then
            return true
        end
    end
    local camps = rawget(_G, "KnoxFactionCamps")
    return self ~= nil and self.campId ~= nil and self.camp ~= nil
        and camps ~= nil and camps.contains ~= nil
        and camps.contains(self.camp, square) == true
end

local function findSupply(self, goal, ticks, matcher)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then return nil end
    local storage = rawget(_G, "KnoxBaseStorage")
    local policies = self.base ~= nil and storage ~= nil and storage.policies ~= nil
        and storage.policies(self.base) or {}
    local assigned = {}
    for _, policy in ipairs(policies) do
        local resolved = storage.resolvePolicy(policy)
        if resolved ~= nil then assigned[resolved.container] = resolved end
    end
    local restocking = self.baseSupplyTrip == true and goal ~= "base_supply"
    local boundedBaseWaterSearch = goal == "find_water"
        and self.baseId ~= nil and self.baseSupplyTrip ~= true
    local boundedCampWaterSearch = goal == "find_water"
        and self.baseId == nil and self.campId ~= nil and self.baseSupplyTrip ~= true
    local currentWaterNeeds = goal == "find_water"
        and KnoxSurvivorNeeds.snapshot(self.character) or nil
    local allowTaintedWater = currentWaterNeeds ~= nil
        and (tonumber(currentWaterNeeds.thirst) or 0) >= 0.90
    local function waterSourceAllowed(square)
        if square == nil or goal ~= "find_water" or self.baseSupplyTrip == true then
            return false
        end
        return Controller.waterSourceBoundaryContains(self, square)
    end
    local function findWaterSource(square)
        if not waterSourceAllowed(square) then return nil end
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local source = objects:get(index)
            local state = KnoxSurvivorNeeds.waterSourceState(source)
            if state ~= nil and state.available == true
                and (not state.tainted or allowTaintedWater)
                and not reservedByOther(self.reservations, "waterSources", source, self.id) then
                local approach = AdjacentFreeTileFinder.Find(square, self.character)
                if approach ~= nil and self:allowNeedDetour(approach, ticks) then
                    return { goal = goal, waterSource = source,
                        waterSourceAmount = state.amount, tainted = state.tainted,
                        approach = approach }
                end
            end
        end
        return nil
    end
    local function inspect(container, square, seen)
        if container == nil or (restocking and assigned[container] ~= nil) or not container:isExistYet()
            or containerUnavailable(self, container, ticks) or areaUnavailable(self, container, ticks)
            or not self:allowNeedDetour(square, ticks, false) then return nil end
        seen = seen or {}
        if seen[container] then return nil end
        seen[container] = true
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if (matcher ~= nil and matcher(item) == true
                    or matcher == nil and itemMatchesGoal(item, goal, self.character))
                and not reservedByOther(self.reservations, "items", item, self.id) then
                local approach = AdjacentFreeTileFinder.Find(square, self.character)
                if approach ~= nil and self:allowNeedDetour(approach, ticks) then
                    return {goal=goal, item=item, container=container, approach=approach}
                end
            end
            local nested = false
            if item ~= nil and item.IsInventoryContainer ~= nil then
                local ok, value = pcall(function() return item:IsInventoryContainer() end)
                nested = ok and value == true
            end
            if nested and item.getInventory ~= nil then
                local ok, inventory = pcall(function() return item:getInventory() end)
                if ok and inventory ~= nil then
                    local nestedSupply = inspect(inventory, square, seen)
                    if nestedSupply ~= nil then return nestedSupply end
                end
            end
        end
        return nil
    end
    if not restocking then
        -- Meals/drinks use the kitchen first, then any actual supplies at home.
        -- This also allows native routes to a pantry on another loaded floor.
    for pass = 1, 2 do
            for _, policy in ipairs(policies) do
                -- Food searches prefer the kitchen; water searches prefer
                -- assigned water stores (jugs, buckets, cans) before food.
                local role = policy.storageRole
                local supplyKind = goal == "find_food" and "food"
                    or goal == "find_water" and "water" or nil
                local filtered = policy.storageFilterVersion == 1
                local allowed = not filtered or (supplyKind ~= nil
                    and storage.filterAllowsKind ~= nil
                    and storage.filterAllowsKind(policy, supplyKind))
                local preferred = filtered and allowed
                    or (goal == "find_food" and role == "food")
                    or (goal == "find_water" and (role == "water" or role == "food"))
                if allowed and (pass == 1 and preferred or pass == 2 and not preferred)
                    and math.abs((tonumber(policy.z) or 0) - origin:getZ()) <= 2
                    and ((tonumber(policy.x) or math.huge) - origin:getX()) ^ 2
                        + ((tonumber(policy.y) or math.huge) - origin:getY()) ^ 2 <= 128 * 128 then
                    local resolved = storage.resolvePolicy(policy)
                    local supply = resolved ~= nil and inspect(resolved.container, resolved.square) or nil
                    if supply ~= nil then return supply end
                end
            end
        end
    end
    -- A base resident's personal need may retrieve a real item from assigned
    -- storage, but must never fall through into a neighborhood search. Explicit
    -- base supply orders set baseSupplyTrip and are allowed to use world search.
    if self.baseId ~= nil and self.baseSupplyTrip ~= true
        and not boundedBaseWaterSearch then
        return nil
    end
    if self.campId ~= nil and self.baseId == nil and self.baseSupplyTrip ~= true
        and goal ~= "find_water" then return nil end
    for radius = 0, Controller.TUNING.SUPPLY_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = getCell():getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    local inBoundedWaterArea = not (boundedBaseWaterSearch or boundedCampWaterSearch)
                        or waterSourceAllowed(square)
                    if square ~= nil and inBoundedWaterArea then
                        local objects = square:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local supply = inspect(object:getContainerByIndex(containerIndex), square)
                                if supply ~= nil then return supply end
                            end
                        end
                        if boundedBaseWaterSearch or boundedCampWaterSearch then
                            local source = findWaterSource(square)
                            if source ~= nil then return source end
                        end
                    end
                end
            end
        end
    end
    return nil
end

Controller.findSupplyCandidate = findSupply

local function directiveAllowsSquare(directive, square, object)
    if directive == nil then
        return true
    end
    if square == nil or square:getZ() ~= (tonumber(directive.z) or 0) then
        return false
    end
    local kind = tostring(directive.kind or "")
    if kind == "loot_building" then
        local building = square:getBuilding()
        local definition = building ~= nil and building:getDef() or nil
        return definition ~= nil
            and tostring(definition:getID()) == tostring(directive.buildingId)
    end
    local x, y = square:getX(), square:getY()
    local inside = x >= (tonumber(directive.minX) or x)
        and x <= (tonumber(directive.maxX) or x)
        and y >= (tonumber(directive.minY) or y)
        and y <= (tonumber(directive.maxY) or y)
    if not inside then
        return false
    end
    return kind ~= "loot_corpses" or instanceof(object, "IsoDeadBody")
end

local function findExploration(self, ticks, directive, options)
    options = type(options) == "table" and options or nil
    local partySupport = options ~= nil and options.partySupport == true
    local origin = self.character:getCurrentSquare()
    local playerAnchor = partySupport and options.playerAnchor or nil
    if origin == nil or getCell() == nil
        or (partySupport and playerAnchor == nil) then
        return nil
    end
    local fallback = nil
    local nearestLoot = nil
    local preferredLoot = nil
    local function buildingKey(square)
        local building = safeMethod(square, "getBuilding", nil)
        local definition = safeMethod(building, "getDef", nil)
        return definition ~= nil and tostring(safeMethod(definition, "getID", "")) or nil
    end
    local preferredBuilding = self.scavengeBuildingId or buildingKey(origin)
    local scanRadius = directive ~= nil and 30 or EXPLORATION_SCAN_RADIUS
    for radius = 0, scanRadius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local withinPlayerRadius = true
                    if partySupport then
                        withinPlayerRadius = square ~= nil
                            and square:getZ() == playerAnchor:getZ()
                            and navigationDistanceSquared(square, playerAnchor)
                                <= EXPLORATION_SCAN_RADIUS * EXPLORATION_SCAN_RADIUS
                    end
                    if square ~= nil and withinPlayerRadius then
                        local objects = square:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local container = object:getContainerByIndex(containerIndex)
                                if container ~= nil and container:isExistYet()
                                    and directiveAllowsSquare(directive, square, object)
                                    and not containerUnavailable(self, container, ticks)
                                    and not areaUnavailable(self, container, ticks)
                                    and not reservedByOther(
                                        self.reservations,
                                        "containers",
                                        container,
                                        self.id
                                    ) then
                                    local corpse = partySupport
                                        and instanceof(object, "IsoDeadBody")
                                    local approach = not corpse
                                        and AdjacentFreeTileFinder.Find(
                                            square,
                                            self.character
                                        ) or nil
                                    if approach ~= nil then
                                        local inPartyRadius = not partySupport
                                            or (approach:getZ() == playerAnchor:getZ()
                                                and navigationDistanceSquared(
                                                    approach, playerAnchor
                                                ) <= EXPLORATION_SCAN_RADIUS
                                                    * EXPLORATION_SCAN_RADIUS)
                                        -- Ordered takes (loot directives, raid/event
                                        -- takes) and settlement scavenging plan
                                        -- for the group; idle self-scavenging
                                        -- stays personal.
                                        local candidates = inPartyRadius
                                            and KnoxSurvivorLooting.plan(
                                                self.character,
                                                container,
                                                partySupport and 1
                                                    or Controller.TUNING.LOOT_CONTAINER_ITEM_LIMIT,
                                                directive ~= nil
                                                    or self:scavengingForSettlement(),
                                                partySupport and { foodOnly = true } or nil
                                            ) or {}
                                        local available = {}
                                        for _, candidate in ipairs(candidates) do
                                            if not reservedByOther(
                                                self.reservations,
                                                "items",
                                                candidate.item,
                                                self.id
                                            ) then
                                                available[#available + 1] = candidate
                                            end
                                        end
                                        if #available > 0 then
                                            local candidate = {
                                                goal = "explore",
                                                items = available,
                                                container = container,
                                                approach = approach,
                                                buildingId = buildingKey(square),
                                                partySupport = partySupport or nil,
                                                playerAnchorX = partySupport
                                                    and playerAnchor:getX() or nil,
                                                playerAnchorY = partySupport
                                                    and playerAnchor:getY() or nil,
                                                playerAnchorZ = partySupport
                                                    and playerAnchor:getZ() or nil,
                                            }
                                            nearestLoot = nearestLoot or candidate
                                            if preferredBuilding ~= nil
                                                and candidate.buildingId == preferredBuilding then
                                                preferredLoot = preferredLoot or candidate
                                            end
                                        end
                                        if not partySupport
                                            and radius <= Controller.TUNING.CONVENIENT_INSPECTION_RADIUS then
                                            fallback = fallback or {
                                                goal = "inspect",
                                                container = container,
                                                approach = approach,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return preferredLoot or nearestLoot or fallback
end

-- (bounded follower-loot reach check is inlined at the formation call site)

local function roamDestinationKey(square)    if square == nil then
        return nil
    end
    local building = square:getBuilding()
    local definition = building ~= nil and building:getDef() or nil
    if definition ~= nil then
        return "building:" .. tostring(definition:getID())
    end
    return "area:" .. tostring(math.floor(square:getX() / 6))
        .. ":" .. tostring(math.floor(square:getY() / 6))
        .. ":" .. tostring(square:getZ())
end

local function roamMemoryAvailable(memory, key, ticks)
    if key == nil then
        return true
    end
    local unavailableUntil = (memory or {})[key]
    if unavailableUntil == nil then
        return true
    end
    if unavailableUntil <= (ticks or 0) then
        memory[key] = nil
        return true
    end
    return false
end

local function rememberRoamDestination(self, key, ticks, cooldown)
    if key == nil then
        return
    end
    self.recentRoamGoals[key] = math.max(
        self.recentRoamGoals[key] or 0,
        ticks + cooldown
    )
    for index = #self.roamGoalOrder, 1, -1 do
        if self.roamGoalOrder[index] == key then
            table.remove(self.roamGoalOrder, index)
        end
    end
    self.roamGoalOrder[#self.roamGoalOrder + 1] = key
    while #self.roamGoalOrder > Controller.TUNING.ROAM_MEMORY_LIMIT do
        local oldest = table.remove(self.roamGoalOrder, 1)
        self.recentRoamGoals[oldest] = nil
    end
end

local function zombiePressureAt(square, radius)
    local cell = getCell()
    if square == nil or cell == nil then
        return 0
    end
    local count = 0
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombieSquare ~= nil
            and zombieSquare:getZ() == square:getZ()
            and distanceSquared(square, zombieSquare) <= radius * radius then
            count = count + 1
        end
    end
    return count
end

function Controller.selectRoamCandidate(candidates, recentGoals, ticks)
    local best = nil
    for _, candidate in ipairs(candidates or {}) do
        if candidate.square ~= nil
            and roamMemoryAvailable(recentGoals, candidate.key, ticks)
            and (candidate.danger or 0) <= Controller.TUNING.ROAM_DANGER_LIMIT
            and (best == nil or candidate.score > best.score
                or (candidate.score == best.score
                    and candidate.distance < best.distance)) then
            best = candidate
        end
    end
    return best
end

function Controller.roamMemoryAvailable(memory, key, ticks)
    return roamMemoryAvailable(memory, key, ticks)
end

function Controller.shouldInterruptRoamingForNeed(kind)
    return kind ~= nil and kind ~= "roam" and kind ~= "fight"
end

local CARDINAL_OFFSETS = {
    { x = 1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = 1 },
    { x = 0, y = -1 },
}

-- Keep roaming destination selection useful without scanning inventories or
-- creating a second planner. Optional native building metadata is queried
-- defensively so modded/partial building objects fail back to distance only.
local function roamingBuildingValue(building)
    if building == nil then return 0 end
    local value = 0
    local definition = building.getDef ~= nil and building:getDef() or nil
    if definition ~= nil then
        local okRooms, rooms = pcall(function() return definition:getRoomsNumber() end)
        if okRooms then value = value + math.min(18, math.max(0, tonumber(rooms) or 0) * 2) end
        local okArea, area = pcall(function() return definition:getArea() end)
        if okArea then value = value + math.min(14, math.max(0, tonumber(area) or 0) / 40) end
    end
    local okResidential, residential = pcall(function() return building:isResidential() end)
    if okResidential and residential == true then value = value + 12 end
    local okWater, hasWater = pcall(function() return building:hasWater() end)
    if okWater and hasWater == true then value = value + 10 end
    return value
end

-- Outsiders keep out of foreign bases while roaming: no wandering into a
-- player or NPC settlement without a reason. Reasons that still admit:
-- resident/duty there, owner-led companion travel, an active event (raid)
-- assignment, or an overnight shelter objective. Need-driven supply trips
-- are intentionally NOT filtered here (survival need plus the existing
-- theft-consequence system owns that boundary).
function Controller:roamForeignBase(square)
    if square == nil then return nil end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getBaseAtSquare == nil then return nil end
    local okCoords, sx, sy, sz = pcall(function()
        return square:getX(), square:getY(), square:getZ()
    end)
    if not okCoords then return nil end
    local okBase, base = pcall(function()
        return persistence.getBaseAtSquare(sx, sy, sz)
    end)
    if not okBase or base == nil then return nil end
    if self.baseId ~= nil and tostring(base.id) == tostring(self.baseId) then
        return nil
    end
    if persistence.getSurvivorDuty ~= nil then
        local okDuty, duty = pcall(function()
            return persistence.getSurvivorDuty(self.id)
        end)
        if okDuty and type(duty) == "table" and duty.mode == "base"
            and tostring(duty.baseId or "") == tostring(base.id) then
            return nil
        end
    end
    if self.companionOrder ~= nil then return nil end
    if self.eventAssignment ~= nil then return nil end
    if self.groupObjective ~= nil
        and self.groupObjective.kind == "night_shelter" then
        return nil
    end
    return base
end

local function findRoamTarget(self, ticks)
    local character = self.character
    local origin = character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    local candidates = {}
    local seenBuildings = {}
    local skippedForeign = 0
    -- Sample loaded squares every two tiles, rather than growing nested square
    -- scans. This reaches the next block without per-tick world searching.
    for dx = -ROAM_MAX_RADIUS, ROAM_MAX_RADIUS, 2 do
        for dy = -ROAM_MAX_RADIUS, ROAM_MAX_RADIUS, 2 do
                local radius = math.max(math.abs(dx), math.abs(dy))
                if radius >= ROAM_MIN_RADIUS then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local building = square ~= nil and square:getBuilding() or nil
                    if square ~= nil and self:roamForeignBase(square) ~= nil then
                        skippedForeign = skippedForeign + 1
                    elseif square ~= nil and square:canStand() and square:getRoom() ~= nil
                        and (self.blockedAreas[square:getRoom()] or 0) <= ticks
                        and building ~= nil
                        and (seenBuildings[building] == nil or radius < seenBuildings[building].distance) then
                        local key = roamDestinationKey(square)
                        seenBuildings[building] = {
                            square = square,
                            key = key,
                            kind = "building",
                            distance = radius,
                            score = 100 - radius + roamingBuildingValue(building),
                        }
                    end
                end
        end
    end
    for _, candidate in pairs(seenBuildings) do
        if roamMemoryAvailable(self.recentRoamGoals, candidate.key, ticks) then
            candidate.danger = zombiePressureAt(candidate.square, Controller.TUNING.ROAM_DANGER_RADIUS)
            candidates[#candidates + 1] = candidate
        end
    end
    local selected = Controller.selectRoamCandidate(
        candidates,
        self.recentRoamGoals,
        ticks
    )
    if selected ~= nil then
        return selected.square, selected.key, selected.kind
    end
    local heading = self.roamHeading
    if heading == nil then
        heading = CARDINAL_OFFSETS[ZombRand(#CARDINAL_OFFSETS) + 1]
        self.roamHeading = { x = heading.x, y = heading.y }
    end
    local onward, onwardKey, onwardScore = nil, nil, -math.huge
    for _ = 1, 40 do
        local radius = ROAM_MIN_RADIUS + ZombRand(ROAM_MAX_RADIUS - ROAM_MIN_RADIUS + 1)
        local dx = ZombRand(radius * 2 + 1) - radius
        local dy = ZombRand(radius * 2 + 1) - radius
        if math.max(math.abs(dx), math.abs(dy)) >= ROAM_MIN_RADIUS then
            local square = getCell():getGridSquare(
                origin:getX() + dx,
                origin:getY() + dy,
                origin:getZ()
            )
            local key = roamDestinationKey(square)
            if square ~= nil and self:roamForeignBase(square) ~= nil then
                skippedForeign = skippedForeign + 1
            elseif square ~= nil and square:canStand()
                and roamMemoryAvailable(self.recentRoamGoals, key, ticks)
                and zombiePressureAt(square, Controller.TUNING.ROAM_DANGER_RADIUS) <= Controller.TUNING.ROAM_DANGER_LIMIT then
                local progress = dx * heading.x + dy * heading.y
                if progress > onwardScore then
                    onward, onwardKey, onwardScore = square, key, progress
                end
            end
        end
    end
    if skippedForeign > 0 then
        self:diag("movement", "roam_foreign_base_skipped", { skipped = skippedForeign })
    end
    return onward, onwardKey, onward ~= nil and "nearby_area" or nil
end

local REST_QUALITY = {
    goodBed = 5,
    averageBed = 4,
    averageChair = 3,
    badBed = 2,
    badChair = 1,
}

local function furnitureQuality(object, sleeping)
    local properties = object ~= nil and object:getProperties() or nil
    local bedType = properties ~= nil and properties:get("BedType") or nil
    local quality = REST_QUALITY[tostring(bedType)] or 3
    if not sleeping then
        local name = properties ~= nil and string.lower(tostring(properties:get("CustomName") or "")) or ""
        if string.find(name, "sofa", 1, true) or string.find(name, "couch", 1, true) then
            quality = quality + 4
        elseif string.find(string.lower(tostring(bedType)), "bed", 1, true) then
            quality = quality - 3
        end
    end
    return quality, tostring(bedType or "seat")
end

local function usableSeat(self, object)
    if object == nil or object:getObjectIndex() == -1
        or reservedByOther(self.reservations, "restSpots", object, self.id) then
        return false
    end
    local success, count = pcall(function()
        return SeatingManager.getInstance():getTilePositionCount(object)
    end)
    if not success or count <= 0 then
        return false
    end
    local occupiedSuccess, occupied = pcall(function()
        return object:isFurnitureOccupied(self.character)
    end)
    return not occupiedSuccess or not occupied
end

local function usableBed(self, object)
    if object == nil or object:getObjectIndex() == -1
        or reservedByOther(self.reservations, "restSpots", object, self.id) then
        return false
    end
    local properties = object:getProperties()
    local bedType = properties ~= nil and tostring(properties:get("BedType") or "") or ""
    if string.find(string.lower(bedType), "bed", 1, true) == nil then
        return false
    end
    local occupiedSuccess, occupied = pcall(function()
        return object:isFurnitureOccupied(self.character)
    end)
    return not occupiedSuccess or not occupied
end

local function usableRestFurniture(self, object, sleeping)
    if sleeping then
        return usableBed(self, object)
    end
    return usableSeat(self, object)
end

-- Assigned-bed resolution: a survivor with a valid assigned bed uses it
-- before any generic search. Invalid, unloaded, removed, occupied, or
-- reserved beds return nil so the normal search (and ultimately the
-- ground-sleep fallback) proceeds untouched.
local function assignedBedSpot(self, squareAllowed)
    local persistence = rawget(_G, "KnoxPersistence")
    local ref = nil
    if persistence ~= nil and persistence.getSurvivorPolicies ~= nil then
        local ok, policies = pcall(function()
            return persistence.getSurvivorPolicies(self.id)
        end)
        if ok and type(policies) == "table" then ref = policies.assignedBed end
    end
    if type(ref) ~= "table" or getCell == nil or getCell() == nil then
        return nil
    end
    local square = getCell():getGridSquare(
        tonumber(ref.x) or 0, tonumber(ref.y) or 0, tonumber(ref.z) or 0
    )
    if square == nil or square.getObjects == nil then return nil end
    if squareAllowed ~= nil and not squareAllowed(square) then return nil end
    local wanted = tonumber(ref.objectIndex)
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local matches = false
        pcall(function()
            matches = object ~= nil and object:getObjectIndex() == wanted
        end)
        if matches and usableBed(self, object) then
            local approach = AdjacentFreeTileFinder.Find(
                square,
                self.character,
                nil
            )
            if approach ~= nil
                and (squareAllowed == nil or squareAllowed(approach)) then
                return {
                    object = object,
                    approach = approach,
                    quality = 6,
                    bedType = "assignedBed",
                    distance = 0,
                }
            end
            return nil
        end
    end
    return nil
end

-- Test seam: assigned-bed resolution without running the full rest search.
function Controller:assignedBedSpot(squareAllowed)
    return assignedBedSpot(self, squareAllowed)
end

local function findBestRestSpot(self, sleeping, squareAllowed)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    -- An assigned bed wins over every generic option, including a closer or
    -- better one. Anything invalid falls through to the normal search below.
    if sleeping then
        local assigned = assignedBedSpot(self, squareAllowed)
        if assigned ~= nil then return assigned end
    end
    local best = nil    for radius = 0, Controller.TUNING.RECOVERY_SEAT_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    if square ~= nil and (squareAllowed == nil or squareAllowed(square)) then
                        local objects = square:getObjects()
                        for index = 0, objects:size() - 1 do
                            local object = objects:get(index)
                            if usableRestFurniture(self, object, sleeping) then
                                local approach = AdjacentFreeTileFinder.Find(
                                    square,
                                    self.character,
                                    nil
                                )
                                if approach ~= nil
                                    and (squareAllowed == nil or squareAllowed(approach)) then
                                    local quality, bedType = furnitureQuality(object, sleeping)
                                    local sleepFurniture = string.find(
                                        string.lower(bedType),
                                        "bed",
                                        1,
                                        true
                                    ) ~= nil
                                    local distance = distanceSquared(origin, approach)
                                    if (not sleeping or sleepFurniture)
                                        and (best == nil or quality > best.quality
                                            or (quality == best.quality
                                                and distance < best.distance)) then
                                        best = {
                                            object = object,
                                            approach = approach,
                                            quality = quality,
                                            bedType = bedType,
                                            distance = distance,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function safeObjectBoolean(object, methodName, fallback)
    if object == nil then
        return fallback
    end
    local ok, value = pcall(function()
        return object[methodName](object)
    end)
    if not ok then
        return fallback
    end
    return value == true
end

local function safeWindowCanClimb(window, character)
    local ok, value = pcall(function()
        return window:canClimbThrough(character)
    end)
    return ok and value == true
end

function Controller.entryCandidateScore(
    kind,
    open,
    smashed,
    barricaded,
    locked,
    permaLocked,
    canClimb,
    allowForcedEntry
)
    if barricaded then
        return nil
    end
    if kind == "door" then
        if open then
            return 0
        end
        if not locked then return 1 end
        return allowForcedEntry and 4 or nil
    end
    if kind == "window" then
        if open or smashed then
            return canClimb and 2 or nil
        end
        if not locked and not permaLocked then return 3 end
        return allowForcedEntry and 4 or nil
    end
    return nil
end

local function canForceEntry(self, square)
    if self == nil or square == nil or KnoxBaseManager.canDamageStructure == nil
        or not KnoxBaseManager.canDamageStructure(self.id, square) then
        return false
    end
    local decision = tostring(self.activeDecision or "")
    local allowedIntent = decision == "scavenge"
        or decision == "inspect_container"
        or decision:find("loot", 1, true) == 1
        or decision:find("find_", 1, true) == 1
        or decision:find("base_task_", 1, true) == 1
        or decision == "return_to_base"
        or decision == "patrol_base"
    if not allowedIntent then return false end
    local weapon = safeMethod(self.character, "getPrimaryHandItem", nil)
    if weapon == nil or tostring(weapon) == "null"
        or safeMethod(weapon, "IsWeapon", false) ~= true
        or safeMethod(weapon, "isBroken", true) == true then
        return false
    end
    local ranged = safeMethod(weapon, "isRanged", false) == true
    if ranged then return false end
    local snapshot = KnoxSurvivorNeeds.snapshot(self.character)
    return snapshot ~= nil
        and (tonumber(snapshot.endurance) or 0) >= LOCKED_DOOR_MIN_ENDURANCE
end

local function findAlternateEntry(self, supply, ticks)
    local targetSquare = supply ~= nil and supply.targetSquare or nil
    targetSquare = targetSquare or (supply ~= nil and supply.container ~= nil
        and supply.container:getSourceGrid() or nil)
    if targetSquare == nil and supply ~= nil and supply.container ~= nil
        and supply.container:getParent() ~= nil then
        targetSquare = supply.container:getParent():getSquare()
    end
    local targetRoom = targetSquare ~= nil and targetSquare:getRoom() or nil
    local origin = self.character:getCurrentSquare()
    if targetRoom == nil or origin == nil or getCell() == nil then
        return nil
    end

    local best = nil
    local bestScore = math.huge
    local bestDistance = math.huge
    local allowForcedEntry = canForceEntry(self, targetSquare)
    local roomSquares = targetRoom:getSquares()
    local attempts = supply.entryAttempts or {}
    for index = 0, roomSquares:size() - 1 do
        local inside = roomSquares:get(index)
        if inside ~= nil and inside:getZ() == origin:getZ()
            and math.abs(inside:getX() - targetSquare:getX()) <= ENTRY_SCAN_RADIUS
            and math.abs(inside:getY() - targetSquare:getY()) <= ENTRY_SCAN_RADIUS then
            for _, offset in ipairs(CARDINAL_OFFSETS) do
                local outside = getCell():getGridSquare(
                    inside:getX() + offset.x,
                    inside:getY() + offset.y,
                    inside:getZ()
                )
                if outside ~= nil and outside:getRoom() ~= targetRoom and outside:canStand() then
                    local isFailedEdge = outside:getX() == origin:getX()
                        and outside:getY() == origin:getY()
                        and outside:getZ() == origin:getZ()
                    local candidate = nil
                    local score = math.huge

                    local door = inside:getDoorTo(outside)
                    if door == nil then
                        door = outside:getDoorTo(inside)
                    end
                    local doorOpen = door ~= nil
                        and safeObjectBoolean(door, "IsOpen", false)
                    local doorLocked = safeObjectBoolean(door, "isLocked", true)
                        or safeObjectBoolean(door, "isLockedByKey", false)
                    local doorScore = door ~= nil and Controller.entryCandidateScore(
                        "door",
                        doorOpen,
                        false,
                        safeObjectBoolean(door, "isBarricaded", true),
                        doorLocked,
                        false,
                        allowForcedEntry
                    ) or nil
                    if not isFailedEdge and doorScore ~= nil and attempts[door] == nil then
                        score = doorScore
                        candidate = {
                            outside = outside,
                            inside = inside,
                            object = door,
                            kind = "door",
                        }
                    end

                    local window = inside:getWindowTo(outside)
                    if window == nil then
                        window = outside:getWindowTo(inside)
                    end
                    local windowOpen = window ~= nil
                        and safeObjectBoolean(window, "IsOpen", false)
                    local windowSmashed = window ~= nil
                        and safeObjectBoolean(window, "isSmashed", false)
                    local windowScore = window ~= nil and Controller.entryCandidateScore(
                        "window",
                        windowOpen,
                        windowSmashed,
                        safeObjectBoolean(window, "isBarricaded", true),
                        safeObjectBoolean(window, "isLocked", true),
                        safeObjectBoolean(window, "isPermaLocked", true),
                        not (windowOpen or windowSmashed)
                            or safeWindowCanClimb(window, self.character),
                        allowForcedEntry
                    ) or nil
                    -- Lock metadata is not permission to skip trying the handle.
                    -- Each distinct window gets a non-destructive attempt first.
                    if window ~= nil and not safeObjectBoolean(window, "isBarricaded", true)
                        and not windowOpen and not windowSmashed and attempts[window] == nil then
                        windowScore = 3
                    end
                    local forceWindow = attempts[window] == "closed" and allowForcedEntry
                        and not windowOpen and not windowSmashed and windowScore ~= nil
                    if windowScore ~= nil
                        and ((not isFailedEdge and attempts[window] == nil) or forceWindow) then
                        -- After a failed entrance, try usable windows first;
                        -- smashing remains after every non-destructive option.
                        -- Do not let a forceable locked door mask an open or
                        -- unlockable window on the same room edge.
                        -- Keep forced windows after every quiet option (0-3),
                        -- but ahead of forcing a locked door (4).
                        local windowCandidateScore = forceWindow and 3.5 or windowScore
                        if candidate == nil or windowCandidateScore < score then
                            score = windowCandidateScore
                            candidate = {
                                outside = outside,
                                inside = inside,
                                object = window,
                                kind = "window",
                                force = forceWindow,
                            }
                        end
                    end

                    if candidate ~= nil and self:allowNeedDetour(outside, ticks or 0) then
                        local distance = distanceSquared(origin, outside)
                        if score < bestScore
                            or (score == bestScore and distance < bestDistance) then
                            best = candidate
                            bestScore = score
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end
    return best
end

local function beginFormationWindowDetour(self, ticks)
    local target = self.state == "COMPANION_FOLLOW"
        and self.companionTarget or self.groupLeader
    local targetSquare = target ~= nil and target:getCurrentSquare() or nil
    if targetSquare == nil or getCell() == nil then return false end
    self.pendingSupply = {
        targetSquare = targetSquare,
        approach = targetSquare,
        entryAttempts = {},
    }
    local resumeState = self.state
    if not self:beginWindowDetour(ticks, resumeState) then
        self.pendingSupply = nil
        return false
    end
    return true
end

function Controller.isEntryTraversalFailure(movement)
    movement = tostring(movement or "")
    return string.find(movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
        or string.find(movement, "FAILED_BARRICADED_DOOR", 1, true) ~= nil
        or string.find(movement, "FAILED_DOOR_OPENING_DISABLED", 1, true) ~= nil
        or string.find(movement, "FAILED_LOCKED_OR_UNUSABLE_WINDOW", 1, true) ~= nil
        or string.find(movement, "FAILED_BARRICADED_WINDOW", 1, true) ~= nil
        or string.find(movement, "FAILED_BLOCKED_WINDOW", 1, true) ~= nil
        or string.find(movement, "FAILED_WINDOW_OPENING_DISABLED", 1, true) ~= nil
end

function Controller.selfCareReady(retryAt, kind, ticks)
    return ((retryAt or {})[kind] or 0) <= (ticks or 0)
end

function Controller.isCriticalOrderedRecovery(decision)
    if type(decision) ~= "table" or type(decision.state) ~= "table" then
        return false
    end
    if decision.kind == "rest" then
        return (tonumber(decision.state.endurance) or 1) <= Controller.TUNING.ORDER_CRITICAL_ENDURANCE
            or (tonumber(decision.state.fatigue) or 0) >= Controller.TUNING.ORDER_CRITICAL_FATIGUE
    end
    if decision.kind == "sleep" then
        return (tonumber(decision.state.fatigue) or 0) >= Controller.TUNING.ORDER_CRITICAL_FATIGUE
    end
    return false
end

local function perceptionScanOffset(id)
    local value = 0
    local text = tostring(id or "")
    for index = 1, #text do
        value = (value + string.byte(text, index)) % THREAT_SCAN_TICKS
    end
    return value
end

local function carriedItemByType(character, fullType)
    if character == nil or type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    local inventory = character:getInventory()
    local items = inventory ~= nil and inventory:getItems() or nil
    if items == nil then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and tostring(value or "") == fullType then
            return item
        end
    end
    return nil
end

function Controller.perceptionScanOffset(id)
    return perceptionScanOffset(id)
end

function Controller.new(id, character, bridge, reservations, ticks)
    local self = setmetatable({}, Controller)
    self.id = id
    self.character = character
    self.bridge = bridge
    self.reservations = reservations
    if self.reservations ~= nil then
        self.reservations.waterSources = self.reservations.waterSources or {}
    end
    self.state = "IDLE"
    self.pendingSupply = nil
    self.pendingDepositTrip = nil
    self.pendingBaseSupplyDeposit = nil
    self.baseSupplyOrder = nil
    self.baseSupplyOrderAttempts = 0
    self.baseSupplyKind = nil
    self.activeDecision = nil
    self.lifeIntent = KnoxPersistence ~= nil
        and KnoxPersistence.getSurvivorLifeIntent ~= nil
        and KnoxPersistence.getSurvivorLifeIntent(id) or nil
    if self.lifeIntent ~= nil and self.lifeIntent.kind == "base_supply_deposit" then
        local recovered = carriedItemByType(self.character, self.lifeIntent.targetKey)
        if recovered ~= nil then
            self.pendingBaseSupplyDeposit = { item = recovered }
        else
            self:clearLifeIntent()
        end
    end
    self.combatTarget = nil
    self.failedThreats = {}
    self.rangedFallbackUntil = setmetatable({}, { __mode = "k" })
    self.perceivedThreats = setmetatable({}, { __mode = "k" })
    -- Firearm encounter transients. Native Build 42 owns weapon/ammo/reload
    -- state; these only bound Knox's own retry/preference decisions and are
    -- cleared together at every terminal combat boundary.
    self.reloadYieldStreak = 0
    self.reloadPreparationStartedAt = nil
    self.reloadYieldTarget = nil
    self.reloadYieldWeaponKey = nil
    self.rangedEncounterTarget = nil
    self.rangedCombatFailureStreak = 0
    self.nextThink = ticks + 15 + ZombRand(30)
    -- Spread independent survivor scans across the interval so a group does not
    -- traverse the loaded zombie list on one shared tick.
    self.nextThreatScan = ticks + perceptionScanOffset(id)
    self.lastCombatRetarget = -COMBAT_RETARGET_COOLDOWN_TICKS
    self.nextWorldSearch = 0
    self.nextBaseSupplySearch = 0
    self.nextExplorationSearch = 0
    self.recoveryStarted = 0
    self.recoveryPostureStarted = 0
    self.pendingRest = nil
    self.selfCareIntent = nil
    self.selfCareRetryAt = {}
    self.selfCareInterrupted = nil
    self.inspectedContainers = {}
    self.scavengeBuildingId = nil
    self.blockedAreas = {}
    self.recentRoamGoals = {}
    self.roamGoalOrder = {}
    self.roamGoalKey = nil
    self.roamGoalKind = nil
    self.nextRoamNeedsCheck = ticks
    self.campId = nil
    self.camp = nil
    self.campSlot = 1
    self.campPositionCycle = 0
    self.campPosition = nil
    self.campExcursion = false
    self.campExcursionExplored = false
    self.nextCampExcursion = ticks
    self.reservations.campPositions = self.reservations.campPositions or {}
    self.forceTravel = false
    self.stateStartedAt = ticks
    self.observedState = self.state
    self.entryDetour = nil
    self.nextNeedCallout = 0
    self.nextActionCallout = 0
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
    self.groupMembers = {}
    self.groupObjective = nil
    self.groupObjectiveRevision = nil
    self.groupObjectiveChanged = false
    self.nextGroupObjectiveAssist = 0
    self.pendingGroupSupport = nil
    self.nextGroupSupportAt = 0
    self.companionOwnerId = nil
    self.companionTarget = nil
    self.companionOrder = nil
    self.companionCombatStance = "defensive"
    self.companionFormationSlot = 1
    self.companionDirective = nil
    self.directiveMisses = 0
    self.allowClimbing = true
    self.allowAutoEquipment = true
    self.failureReasons = {}
    self.formationTargetX = nil
    self.formationTargetY = nil
    self.formationTargetZ = nil
    self.formationMovementPace = nil
    self.nextFormationRefresh = 0
    self.formationCommitUntil = 0
    self.formationTraversalBusy = nil
    self.formationFailureCount = 0
    self.movementFailureCount = 0
    self.regroupMember = nil
    self.nextRegroupCallout = 0
    self.baseId = nil
    self.base = nil
    self.baseTask = nil
    self.baseTaskStartedAt = nil
    self.baseTaskSupplyTransfer = nil
    self.baseResupplyAttempts = 0
    self.baseTaskRetryAt = 0
    self.baseTaskMoveRetryIssued = false
    self.baseTaskActionQueued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.pendingCorpseDefenseTarget = nil
    self.corpseDefenseReleaseUntil = nil
    self.nextCorpseDefenseReleaseAttempt = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.factionId = nil
    self.awayTeamId = nil
    self.awayCollected = false
    self.awaySearchMisses = 0
    self.factionBaseCandidate = nil
    self.announcedFactionBaseCandidate = nil
    self.pendingRobbery = nil
    self.pendingThreatAwareness = nil
    self.fleeSafeScans = 0
    self.lastFleeDirectionX = nil
    self.lastFleeDirectionY = nil
    self.fleeDirectionUntil = 0
    self.counts = {
        roam = 0,
        loot = 0,
        search = 0,
        needs = 0,
        combat = 0,
        groupTravel = 0,
        baseScout = 0,
        robberies = 0,
        failures = 0,
    }
    character:setZombiesDontAttack(false)
    return self
end

local function currentWorldAgeHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
end

function Controller.roamIntentKind(destinationKind, existingKind)
    if existingKind == "find_food" or existingKind == "find_water"
        or existingKind == "find_medical" then
        return existingKind
    end
    return destinationKind == "building" and "investigate_building" or "travel_area"
end

function Controller:setLifeIntent(kind, phase, square, targetKey)
    local nextIntent = {
        kind = kind,
        phase = phase,
        targetKey = targetKey,
        targetX = square ~= nil and square:getX() or nil,
        targetY = square ~= nil and square:getY() or nil,
        targetZ = square ~= nil and square:getZ() or nil,
        startedAtHours = self.lifeIntent ~= nil
            and self.lifeIntent.kind == kind
            and self.lifeIntent.startedAtHours or currentWorldAgeHours(),
    }
    local current = self.lifeIntent
    if current ~= nil and current.kind == nextIntent.kind
        and current.phase == nextIntent.phase
        and current.targetKey == nextIntent.targetKey
        and current.targetX == nextIntent.targetX
        and current.targetY == nextIntent.targetY
        and current.targetZ == nextIntent.targetZ then
        return false
    end
    self.lifeIntent = nextIntent
    if KnoxPersistence ~= nil and KnoxPersistence.setSurvivorLifeIntent ~= nil then
        KnoxPersistence.setSurvivorLifeIntent(
            self.id, nextIntent, currentWorldAgeHours()
        )
    end
    return true
end

function Controller:clearLifeIntent()
    if self.lifeIntent == nil then return false end
    self.lifeIntent = nil
    if KnoxPersistence ~= nil and KnoxPersistence.clearSurvivorLifeIntent ~= nil then
        KnoxPersistence.clearSurvivorLifeIntent(self.id)
    end
    return true
end

function Controller:diagnosticScalar(value, limit)
    local text = tostring(value or "none"):gsub("[%c]", " ")
    if #text > limit then text = text:sub(1, limit) end
    return text
end

function Controller:recordRecentFailure(reason, ticks)
    local history = self.recentFailureHistory
    if type(history) ~= "table" then
        history = {}
        self.recentFailureHistory = history
    end
    local point = nil
    if self.diagPos ~= nil then
        local ok, value = pcall(function() return self:diagPos() end)
        if ok then point = value end
    end
    local now = tonumber(ticks)
    if now == nil or now ~= now or now == math.huge or now == -math.huge then now = 0 end
    local retryAt = tonumber(self.nextThink)
    if retryAt ~= nil and (retryAt ~= retryAt or retryAt == math.huge or retryAt == -math.huge) then
        retryAt = nil
    end
    history[#history + 1] = {
        tick = now,
        reason = self:diagnosticScalar(reason, 160),
        state = self:diagnosticScalar(self.state, 64),
        decision = self:diagnosticScalar(self.activeDecision, 96),
        retryAt = retryAt,
        x = point ~= nil and tonumber(point.x) or nil,
        y = point ~= nil and tonumber(point.y) or nil,
        z = point ~= nil and tonumber(point.z) or nil,
    }
    if #history > 12 then table.remove(history, 1) end
end

-- Return scalar copies only. Diagnostics must never expose mutable controller
-- history or retain native characters, items, targets, or reservation tables.
function Controller:recentFailureEvidence()
    local result = {}
    for index, entry in ipairs(self.recentFailureHistory or {}) do
        result[index] = {
            tick = entry.tick, reason = entry.reason, state = entry.state,
            decision = entry.decision, retryAt = entry.retryAt,
            x = entry.x, y = entry.y, z = entry.z,
        }
    end
    return result
end

function Controller:recordFailure(reason, ticks, cooldown)
    local key = tostring(reason or "unknown")
    self.lastFailure={reason=key,ticks=ticks}
    self.counts = self.counts or {}
    self.counts.failures = (self.counts.failures or 0) + 1
    self.failureReasons = self.failureReasons or {}
    self.failureReasons[key] = (self.failureReasons[key] or 0) + 1
    self.nextThink = math.max(
        self.nextThink or 0,
        (ticks or 0) + (cooldown or THINK_MIN_TICKS)
    )
    self:recordRecentFailure(key, ticks)
    local count = self.failureReasons[key]
    if count == 1 or count % 10 == 0 then
        print("[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " action-failed=" .. key .. " count=" .. tostring(count)
            .. " retryAt=" .. tostring(self.nextThink))
    end
    -- Structured mirror of every failure (movement, combat, jobs, needs):
    -- throttled inside KnoxDebugLog, with a plain-language brief, so future
    -- hunts start from categorized evidence instead of raw console text.
    local category = "autonomy"
    if string.find(key, "^movement") == 1 or string.find(key, "Failed", 1, true) ~= nil
        or string.find(key, "MOVE", 1, true) ~= nil then
        category = "movement"
    elseif string.find(key, "^combat") == 1 then
        category = "combat"
    elseif string.find(key, "^base_task") == 1 then
        category = "jobs"
    elseif string.find(key, "eat", 1, true) ~= nil or string.find(key, "drink", 1, true) ~= nil
        or string.find(key, "sleep", 1, true) ~= nil or string.find(key, "rest", 1, true) ~= nil
        or string.find(key, "need", 1, true) ~= nil then
        category = "needs"
    end
    local snapshot = { reason = key, state = self.state, decision = self.activeDecision }
    local pos = self:diagPos()
    if pos ~= nil then snapshot.charX, snapshot.charY = pos.x, pos.y end
    self:diag(category, "action_failed", snapshot)
end

-- Structured job/combat/firearm diagnostics. Failures and transitions log
-- through KnoxDebugLog (1st + every 10th); per-tick detail stays behind
-- ShowDeveloperDiagnostics. Keeps console.txt readable during long playtests.
function Controller:diag(category, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log(category, self.id, event, details) end)
    end
end

function Controller:diagOnce(category, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.once ~= nil then
        pcall(function() log.once(category, self.id, event, details) end)
    end
end

local function diagSquare(square)
    if square == nil then return nil end
    local ok, x, y, z = pcall(function() return square:getX(), square:getY(), square:getZ() end)
    if not ok then return nil end
    return { x = x, y = y, z = z }
end

function Controller:diagPos()
    local ok, square = pcall(function()
        return self.character ~= nil and self.character:getCurrentSquare() or nil
    end)
    if not ok then return nil end
    return diagSquare(square)
end

function Controller:diagTaskSnapshot(task)
    if type(task) ~= "table" then return {} end
    local target = task.target or {}
    return {
        task = task.id, type = task.type,
        tx = target.x or target.x1, ty = target.y or target.y1, tz = target.z,
        objectIndex = target.objectIndex,
        streak = task.failureStreak,
    }
end

-- Compact native-action verdict for non-barricade jobs (barricade has its
-- own detailed variant). Before/after come from the module's own snapshot
-- readers; failures already carry the queue reason via failBaseTaskAction.
function Controller:diagActionVerdict(kind, complete, before, after)
    local function flat(value)
        if type(value) == "table" then
            local parts = {}
            for k, v in pairs(value) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return value
    end
    self:diag("jobs", complete and "action_completed" or "action_not_completed", {
        kind = tostring(kind), before = flat(before), after = flat(after),
    })
end

local function movementFailureKind(result)
    local text = tostring(result or "unknown")
    return string.match(text, "^[^%s:]+") or "unknown"
end

-- Progress anchor for the job-travel watchdog, recorded at every work and
-- supply move start. Displacement refreshes the anchor; stillness past the
-- stall window fails the move fast.
function Controller:noteTaskTravelStart(ticks)
    local ok, square = pcall(function()
        return self.character ~= nil and self.character:getCurrentSquare() or nil
    end)
    if not ok then
        square = nil
    end
    local x, y, z
    if square ~= nil then
        local coordsOk, cx, cy, cz = pcall(function()
            return square:getX(), square:getY(), square:getZ()
        end)
        if coordsOk then
            x, y, z = cx, cy, cz
        end
    end
    self.moveProgressX, self.moveProgressY, self.moveProgressZ = x, y, z
    self.moveProgressTick = ticks
end

function Controller:taskTravelStalled(ticks)
    if self.moveProgressX == nil or self.character == nil then
        return false
    end
    local ok, square = pcall(function() return self.character:getCurrentSquare() end)
    if not ok or square == nil then
        return false
    end
    local coordsOk, sx, sy, sz = pcall(function()
        return square:getX(), square:getY(), square:getZ()
    end)
    if not coordsOk then
        return false
    end
    local dx = sx - self.moveProgressX
    local dy = sy - self.moveProgressY
    local dz = ((sz or 0) - (self.moveProgressZ or 0)) * 2
    if dx * dx + dy * dy + dz * dz >= TASK_TRAVEL_STALL_DISTANCE_SQUARED then
        self.moveProgressX, self.moveProgressY, self.moveProgressZ = sx, sy, sz
        self.moveProgressTick = ticks
        return false
    end
    return ticks - (self.moveProgressTick or ticks) > TASK_TRAVEL_STALL_TICKS
end

function Controller:recordMovementFailure(scope, result, ticks, baseCooldown, maxCooldown)    self.movementFailureCount = (self.movementFailureCount or 0) + 1
    local exponent = math.min(self.movementFailureCount - 1, 3)
    local cooldown = math.min(
        (baseCooldown or MOVEMENT_FAILURE_COOLDOWN_TICKS) * (2 ^ exponent),
        maxCooldown or MOVEMENT_FAILURE_MAX_COOLDOWN_TICKS
    )
    self:recordFailure(
        tostring(scope or "movement") .. ":" .. movementFailureKind(result),
        ticks,
        cooldown
    )
    return cooldown
end

function Controller:resetMovementRecovery()
    self.movementFailureCount = 0
    self.formationFailureCount = 0
end

function Controller:handleFormationMovementFailure(movement, ticks, companionFollow)
    -- Native climb/vault owns the body: never cancel, count, or replan while
    -- the native traversal action is active. Landing resolves on its own tick;
    -- treating it as failure is what produced the visible fast reset snap.
    if nativeTraversalBusy(self.character) then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        self.nextFormationRefresh = math.max(self.nextFormationRefresh or 0,
            ticks + THINK_MIN_TICKS)
        return
    end
    if Controller.isEntryTraversalFailure(movement)
        and (self.state == "GROUP_FOLLOW" or self.state == "COMPANION_FOLLOW") then
        if beginFormationWindowDetour(self, ticks) then return end
    end
    self.bridge:cancelNpcMove(self.id)
    self.formationFailureCount = (self.formationFailureCount or 0) + 1
    local cooldown = math.min(
        Controller.TUNING.FORMATION_FAILURE_COOLDOWN_TICKS * self.formationFailureCount,
        FORMATION_FAILURE_MAX_COOLDOWN_TICKS
    )
    self:recordFailure(
        "formation_movement:" .. movementFailureKind(movement),
        ticks,
        cooldown
    )
    if companionFollow == nil then
        companionFollow = self.state == "COMPANION_FOLLOW"
    end
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.activeDecision = companionFollow and "follow_player" or "follow_group"
    self.state = companionFollow and "COMPANION_WAIT" or "GROUP_WAIT"
    -- recordFailure owns the retry time. Do not let the ordinary grouped
    -- finishDecision fast path replace this with its five-tick refresh.
    self.nextFormationRefresh = self.nextThink
end

function Controller:waitForFormationBottleneck(movement, ticks)
    if nativeTraversalBusy(self.character) then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        self.nextFormationRefresh = math.max(self.nextFormationRefresh or 0,
            ticks + THINK_MIN_TICKS)
        return
    end
    self.bridge:cancelNpcMove(self.id)
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.activeDecision = "follow_group"
    self.state = "GROUP_WAIT"
    self:recordFailure(
        "formation_bottleneck:" .. movementFailureKind(movement),
        ticks,
        Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS
    )
    self.nextFormationRefresh = self.nextThink
end

function Controller:updateFormationMovementPace(anchor)
    local pace = formationPace(anchor, self.character)
    if pace == self.formationMovementPace then
        return false
    end
    if self.bridge.setNpcMovementPace == nil
        or not self.bridge:setNpcMovementPace(self.id, pace) then
        return false
    end
    self.formationMovementPace = pace
    return true
end


function Controller:setGroupLeader(
    id, character, formationSlot, groupSize, objective, leaderOrder, preserveLifeIntent
)
    self.groupLeaderId = id
    self.groupLeader = character
    self.groupFormationSlot = math.max(1, tonumber(formationSlot) or 1)
    self.groupSize = math.max(1, tonumber(groupSize) or 1)
    local objectiveRevision = objective ~= nil and objective.revision or nil
    if objectiveRevision ~= self.groupObjectiveRevision then
        self.groupObjectiveChanged = true
        self.groupObjectiveRevision = objectiveRevision
    end
    self.groupObjective = objective
    self:setGroupLeaderOrder(leaderOrder)
    if id ~= nil and not preserveLifeIntent then self:clearLifeIntent() end
end

function Controller:clearGroupLeader()
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
    self.groupObjective = nil
    self:setGroupLeaderOrder(nil)
    self.groupObjectiveRevision = nil
    self.groupObjectiveChanged = false
    self.nextGroupObjectiveAssist = 0
end

function Controller:setGroupMembers(members)
    self.groupMembers = members or {}
end

function Controller:setGroupObjective(objective, suppressSignals)
    local previousKind = self.groupObjective ~= nil
        and tostring(self.groupObjective.kind or "") or nil
    local nextKind = objective ~= nil and tostring(objective.kind or "") or nil
    local changed = nextKind ~= previousKind
        or (objective ~= nil and objective.revision or nil)
            ~= self.groupObjectiveRevision
    self.groupObjective = objective
    self.groupObjectiveRevision = objective ~= nil and objective.revision or nil
    local objectiveKey = objective ~= nil and table.concat({
        tostring(objective.kind or ""), tostring(objective.buildingId or ""),
        tostring(math.floor(tonumber(objective.x) or 0)),
        tostring(math.floor(tonumber(objective.y) or 0)),
        tostring(math.floor(tonumber(objective.z) or 0)),
    }, ":") or nil
    local nowTicks = self.currentTicks or 0
    local announce = changed and objectiveKey ~= self.lastGroupObjectiveAnnouncement
        and nowTicks >= (self.nextGroupObjectiveAnnouncementAt or 0)
    if not suppressSignals and announce and self.groupLeaderId == nil and objective ~= nil
        and KnoxOrderSignals ~= nil and KnoxOrderSignals.group ~= nil then
        local lines = {
            scavenge = "We'll search this area.",
            investigate_building = "Check that building.",
            find_food = "We'll find food.", find_water = "We'll find water.",
            find_medical = "We'll find medical supplies.",
        }
        if KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
            KnoxActivityFeed.speak(self.character,
                lines[tostring(objective.kind or "")] or "Stay together and keep moving.")
        end
        KnoxOrderSignals.group(
            self.character,
            self.groupMembers,
            tostring(objective.kind or "")
        )
        self.lastGroupObjectiveAnnouncement = objectiveKey
        self.nextGroupObjectiveAnnouncementAt = nowTicks + 1800
    end
end

function Controller:setGroupLeaderOrder(order)
    local previous = self.groupLeaderOrder
    local changed = (previous ~= nil) ~= (order ~= nil)
        or (previous ~= nil and order ~= nil and (
            previous.groupId ~= order.groupId or previous.leaderId ~= order.leaderId
            or previous.kind ~= order.kind or previous.revision ~= order.revision))
    self.groupLeaderOrder = order
    if changed then self.groupLeaderOrderPending = true end
end

-- Delivery is not permission to cancel a native action. Consume the changed
-- directive only in formation-owned states, after the existing danger scan.
function Controller:applyGroupLeaderOrder(ticks)
    local order = self.groupLeaderOrder
    if order ~= nil and (order.leaderId ~= self.groupLeaderId
        or tonumber(order.expiresAtHours) == nil
        or currentWorldAgeHours() >= tonumber(order.expiresAtHours)) then
        self:setGroupLeaderOrder(nil)
    end
    if not self.groupLeaderOrderPending then return false end
    if self.state ~= "GROUP_FOLLOW" and self.state ~= "GROUP_WAIT"
        and self.state ~= "IDLE" then return false end
    if self.state ~= "GROUP_FOLLOW" and self.activeDecision ~= "leader_hold"
        and ticks < (self.nextThink or 0) then return false end
    if nativeTraversalBusy(self.character) then return false end
    local actions = safeMethod(self.character, "getCharacterActions", nil)
    if actions ~= nil and not actions:isEmpty() then return false end
    local hold = self.groupLeaderOrder ~= nil and self.groupLeaderOrder.kind == "hold"
    if self.state == "GROUP_FOLLOW" then
        -- A new follow lease must not stop an already-correct native route.
        if not hold then
            self.groupLeaderOrderPending = nil
            self.nextGroupOrderRetry = nil
            return false
        end
        if ticks < (self.nextGroupOrderRetry or 0) then return false end
        local ok, result = pcall(function() return self.bridge:cancelNpcMove(self.id) end)
        if not ok or string.find(tostring(result), "MOVE_CANCELLED", 1, true) ~= 1 then
            self.nextGroupOrderRetry = ticks + 60
            self:diag("movement", "leader_order_cancel_failed", { result = tostring(result) })
            return false
        end
    end
    self.groupLeaderOrderPending = nil
    self.nextGroupOrderRetry = nil
    self.formationMovementPace = nil
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = ticks
    self.nextFormationRefresh = ticks
    return true
end

function Controller:issueGroupLeaderOrder(kind, ticks, expiresAtHours)
    if KnoxPersistence == nil or KnoxPersistence.getTravelGroupFor == nil
        or KnoxPersistence.issueTravelGroupLeaderOrder == nil then
        return nil, "group_orders_unavailable"
    end
    if safeMethod(self.character, "getCurrentSquare", nil) == nil
        or safeMethod(self.character, "isDead", false) == true then
        return nil, "leader_unavailable"
    end
    local group = KnoxPersistence.getTravelGroupFor(self.id)
    if group == nil or group.leaderId ~= self.id then
        return nil, "not_group_leader"
    end
    return KnoxPersistence.issueTravelGroupLeaderOrder(
        group.id, self.id, kind, currentWorldAgeHours(), expiresAtHours
    )
end

function Controller.shouldAssistGroupObjective(objective, leaderDistanceSquared)
    if type(objective) ~= "table"
        or tonumber(leaderDistanceSquared) == nil
        or leaderDistanceSquared > Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED then
        return false
    end
    if objective.kind == "scavenge" then
        return objective.phase == "seeking" or objective.phase == "traveling"
            or objective.phase == "arrived" or objective.phase == "reassess"
    end
    return objective.kind == "investigate_building"
        and (objective.phase == "arrived" or objective.phase == "reassess")
end

function Controller.shouldDelegateNeedToGroup(kind, leaderDistanceSquared)
    return (kind == "find_food" or kind == "find_water" or kind == "find_medical")
        and tonumber(leaderDistanceSquared) ~= nil
        and leaderDistanceSquared <= Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED
end

function Controller:interruptForDirective()
    self.securityRoute=nil
    self:releaseBaseCooking()
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if vehicles ~= nil and vehicles.cancel ~= nil then vehicles.cancel(self.character) end
    self:cancelTrade("directive_changed")
    local safe = self.state == "IDLE" or self.state == "ROAMING"
        or self.state == "EVENT_TRAVEL" or self.state == "EVENT_WAIT"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_WAIT"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "COMPANION_WAIT" or self.state == "COMPANION_HOLD"
        or self.state == "COMPANION_GUARD" or self.state == "COMPANION_RELAX"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "COMPANION_PATROL_WAIT"
        or self.state == "COMPANION_DUTY_WAIT" or self.state == "BASE_SECURITY_WAIT"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_IDLE" or self.state == "BASE_AMBIENT_REST"
        or self.state == "CAMP_IDLE" or self.state == "CAMP_AMBIENT_REST"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "BASE_DEFEND"
        or self.state == "BASE_TASK_MOVE" or self.state == "BASE_TASK_WORK"
        or self.state == "BASE_TASK_PATROL_WAIT"
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "MOVING_TO_REST"
        or self.state == "SLEEPING_RECOVERY"
        or self.state == "NIGHT_SHELTER_MOVE"
        or self.state == "AID_MOVE" or self.state == "AID_ACTION"
        or self.state == "INVENTORY_CLEANUP"
        or self.state == "MOVING_TO_DEPOSIT"
    if self.state == "LOOTING" and self.pendingSupply ~= nil
        and self.pendingSupply.partySupport == true then
        safe = true
    end
    if self.state == "PLAYER_CONVERSATION" or self.state == "BASE_RECREATION" or self.state == "BASE_COOKING" then safe = true end
    if self.state == "BASE_ORGANIZE" then
        self:releaseBaseOrganize()
        safe = true
    end
    if not safe then
        return false
    end
    self.playerConversation = nil
    self:releaseBaseRecreation()
    -- These states own native/Lua actions independently of a base-task claim.
    -- Stop them before releasing their pointers or issuing replacement movement.
    if self.state == "INVENTORY_CLEANUP" or self.state == "AID_ACTION"
        or self.state == "WAITING_TO_RECOVER" or self.state == "SLEEPING_RECOVERY"
        or self.state == "COMPANION_RELAX" or self.state == "BASE_AMBIENT_REST"
        or self.state == "BASE_ORGANIZE"
        or self.state == "CAMP_AMBIENT_REST"
        or (self.state == "LOOTING" and self.pendingSupply ~= nil
            and self.pendingSupply.partySupport == true) then
        if hasPendingTimedActions(self.character) then
            ISTimedActionQueue.clear(self.character)
        end
    end
    self.pendingCleanup = nil
    self.bridge:cancelNpcMove(self.id)
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    self:releaseAmbientMovement()
    self:releaseCampPosition()
    self.pendingDepositTrip = nil
    self:abandonBaseTask("directive_changed")
    self:releaseSupply()
    self:releaseRestSpot()
    self:releaseAid()
    self:leaveRecoveryPosture()
    self.ambientRest = nil
    self.selfCareInterrupted = self.selfCareIntent ~= nil
        and self.activeDecision or self.selfCareInterrupted
    self.selfCareIntent = nil
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = 0
    return true
end

function Controller:setCompanionOrder(
    ownerId, player, order, formationSlot, formationForwardX, formationForwardY,
    formationMemberCount
)
    local normalized = order == "hold" and "hold"
        or (order == "relax" and "relax" or "follow")
    local normalizedSlot = math.max(1, tonumber(formationSlot) or 1)
    local changed = self.companionOwnerId ~= ownerId
        or self.companionTarget ~= player
        or self.companionOrder ~= normalized
    if self.companionOwnerId ~= ownerId or self.companionTarget ~= player
        or normalized ~= "follow" then
        self:releasePlayerFormationTarget()
    end
    -- Runtime-stable slot/heading projection may update during an action. Only
    -- an actual order or owner change interrupts that higher-priority activity.
    self.companionOwnerId = ownerId
    self.companionTarget = player
    self.companionOrder = normalized
    self.companionFormationSlot = normalizedSlot
    self.companionFormationForwardX = tonumber(formationForwardX)
    self.companionFormationForwardY = tonumber(formationForwardY)
    self.companionPartySize = math.max(1, math.floor(
        tonumber(formationMemberCount) or 1
    ))
    if changed then
        self:clearLifeIntent()
        self:interruptForDirective()
    end
end

function Controller:setCompanionCombatStance(stance)
    local normalized = stance == "passive" and "passive"
        or (stance == "aggressive" and "aggressive" or "defensive")
    if self.companionCombatStance == normalized then
        return
    end
    self.companionCombatStance = normalized
    if normalized == "passive" and self.state == "COMBAT" then
        self.bridge:resetNpcCombat(self.id)
        self:releaseCombat()
        self:clearFirearmCombatState()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:setWeaponPreference(preference)
    local normalized = (preference == "melee" or preference == "ranged") and preference or "auto"
    if self.weaponPreference == normalized then return end
    self.weaponPreference = normalized
    -- Persistent policies remain authoritative; this mirror only detects a
    -- changed order. End native attack/reload ownership before another weapon.
    local cancelledReload = KnoxFirearmSupport.cancelPreparation(self.character)
    if self.state == "COMBAT" then
        self.bridge:resetNpcCombat(self.id)
        self:releaseCombat()
        self:clearFirearmCombatState()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    elseif cancelledReload then
        self.bridge:cancelNpcMove(self.id)
        self:abandonBaseTask("weapon_preference_changed")
        self:releaseSupply()
        self:clearFirearmCombatState()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:allowsCompanionThreat(target)
    if target == nil then
        return false
    end
    if not withinCombatRoleLeash(self, target) then
        return false
    end
    if self.companionOrder == nil then
        return true
    end
    if self.companionCombatStance == "passive" then
        return false
    end
    if self.companionCombatStance == "aggressive" then
        return true
    end
    local square = self.character:getCurrentSquare()
    local targetSquare = target:getCurrentSquare()
    -- Human shells do not expose the zombie getTarget contract reliably. A
    -- survivor already classified as hostile to this companion/player faction
    -- is enough for a defensive companion to protect its nearby owner and party.
    if square ~= nil and targetSquare ~= nil and hostileHuman(self, target)
        and distanceSquared(square, targetSquare)
            <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS then
        return true
    end
    -- getTarget is zombie-only and throws through pcall on human shells;
    -- use the guarded helper so hostile humans never crash assist checks.
    if square == nil or targetSquare == nil
        or not targetsGroupMember(self, targetOf(target)) then
        return false
    end
    return distanceSquared(square, targetSquare) <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
end

function Controller:setCompanionPolicy(allowClimbing)
    self.allowClimbing = allowClimbing ~= false
    self.bridge:setNpcClimbingAllowed(self.id, self.allowClimbing)
end

function Controller:setDoorWindowOpeningPolicy(allowed)
    self.allowDoorWindowOpening = allowed ~= false
    if self.bridge ~= nil and self.bridge.setNpcDoorWindowOpeningAllowed ~= nil then
        self.bridge:setNpcDoorWindowOpeningAllowed(self.id, self.allowDoorWindowOpening)
    end
end

-- Auto-loot while following. Lua-side only: nil means enabled (historical
-- behavior), explicit false disables the idle formation pickup below.
function Controller:setAutoLootPolicy(allowed)
    if allowed == nil then
        self.allowAutoLoot = nil
    else
        self.allowAutoLoot = allowed == true
    end
end

-- This preference gates only opportunistic inventory upgrades. Explicit
-- equipment commands and combat weapon selection keep their existing owners.
function Controller:setAutoEquipmentPolicy(allowed)
    self.allowAutoEquipment = allowed ~= false
end

function Controller:reconsiderEquipment(ticks, force)
    if self.allowAutoEquipment == false then
        return false, "equipment_disabled"
    end
    return KnoxEquipmentIntelligence.reconsider(
        self.id, self.character, self.bridge, ticks, force
    )
end

function Controller:setCompanionDirective(directive)
    if directive ~= nil and KnoxPersistence.isValidCompanionDirective ~= nil
        and not KnoxPersistence.isValidCompanionDirective(directive) then
        -- A malformed directive may exist only in an old/corrupt save. Clear
        -- its durable copy once, then let the primary Follow/Hold duty resume.
        KnoxPersistence.clearCompanionDirective(
            self.id,
            self.companionOwnerId,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
        directive = nil
    end
    local current = self.companionDirective
    local changed = (current == nil) ~= (directive == nil)
        or (current ~= nil and directive ~= nil
            and (current.kind ~= directive.kind
                or current.issuedAtHours ~= directive.issuedAtHours
                or current.minX ~= directive.minX
                or current.minY ~= directive.minY
                or current.maxX ~= directive.maxX
                or current.maxY ~= directive.maxY
                or current.z ~= directive.z
                or current.partyDestinationRevision ~= directive.partyDestinationRevision
                or current.partyDestination ~= directive.partyDestination
                or current.partyDestinationArrived ~= directive.partyDestinationArrived))
    local currentDestinationRevision = current ~= nil
        and current.partyDestinationRevision or nil
    local nextDestinationRevision = directive ~= nil
        and directive.partyDestinationRevision or nil
    if current ~= nil and current.partyDestination == true
        and (directive == nil or directive.partyDestination ~= true
            or nextDestinationRevision ~= currentDestinationRevision) then
        self:releasePartyDestinationTarget()
        self.partyDestinationFinalLeg = nil
    end
    if directive ~= nil then self:releasePlayerFormationTarget() end
    if currentDestinationRevision ~= nextDestinationRevision then
        self:releasePartyDestinationTarget()
        self.partyDestinationFinalLeg = nil
    end
    self.companionDirective = directive
    if changed then
        self.directiveMisses = 0
        self.securityContext,self.securityRoute,self.securityRetryAt=nil,nil,nil
        self:interruptForDirective()
    end
end

function Controller:clearCompanionOrder()
    local changed = self.companionOrder ~= nil or self.companionDirective ~= nil
    if changed then
        self:interruptForDirective()
    end
    self:releasePlayerFormationTarget()
    self:releasePartyDestinationTarget()
    self.companionOwnerId = nil
    self.companionTarget = nil
    self.companionOrder = nil
    self.companionCombatStance = "defensive"
    self.companionFormationSlot = 1
    self.companionFormationForwardX = nil
    self.companionFormationForwardY = nil
    self.companionDirective = nil
end

function Controller:syncBaseSupplyOrder()
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local request = duty ~= nil and duty.mode == "base"
        and tostring(duty.baseId or "") == tostring(self.baseId or "")
        and type(duty.baseSupplyOrder) == "table"
        and duty.baseSupplyOrder or nil
    local current = self.baseSupplyOrder
    local changed = (current == nil) ~= (request == nil)
        or (current ~= nil and request ~= nil
            and (current.kind ~= request.kind
                or current.issuedAtHours ~= request.issuedAtHours
                or current.expiresAtHours ~= request.expiresAtHours))
    if changed then
        self.baseSupplyOrder = request
        self.baseSupplyOrderAttempts = request ~= nil
            and math.max(0, math.floor(tonumber(request.attempts) or 0)) or 0
        self.nextThink = 0
    elseif request ~= nil then
        self.baseSupplyOrderAttempts = math.max(
            tonumber(self.baseSupplyOrderAttempts) or 0,
            math.max(0, math.floor(tonumber(request.attempts) or 0))
        )
    end
    return changed
end

function Controller:syncBaseSupplyRun()
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local active = duty ~= nil and duty.mode == "base"
        and tostring(duty.baseId or "") == tostring(self.baseId or "")
        and type(duty.activeSupplyRun) == "table"
        and duty.activeSupplyRun or nil
    local kind = active ~= nil and tostring(active.kind or "") or nil
    local changed = kind ~= self.baseSupplyKind
        or (active ~= nil) ~= (self.baseSupplyTrip == true)
    if active ~= nil then
        self.baseSupplyTrip = true
        self.baseSupplyKind = kind
        restoreSupplyClaim(self.baseId, kind, self.id)
    elseif self.pendingBaseSupplyDeposit == nil then
        self.baseSupplyTrip = nil
        self.baseSupplyKind = nil
    end
    return changed
end

function Controller:setBaseAssignment(baseId, base)
    local changed = self.baseId ~= baseId or self.base ~= base
    self.baseId = baseId
    self.base = base
    local supplyOrderChanged = self:syncBaseSupplyOrder()
    self:syncBaseSupplyRun()
    local continuingSupplyOrder = self.baseSupplyOrder ~= nil
        and self.baseSupplyTrip == true
        and self.baseSupplyOrder.kind == self.baseSupplyKind
    if supplyOrderChanged and not continuingSupplyOrder then
        self:releaseSupply()
        self:clearLifeIntent()
        self:interruptForDirective()
    end
    if changed then
        -- Travel formations are temporary. Once a faction becomes a resident
        -- settlement, keeping the old leader/member route makes the whole base
        -- repeatedly reconsider that journey instead of accepting jobs.
        if baseId ~= nil then
            self:clearGroupLeader()
            self:setGroupMembers({})
            -- A travel group usually reaches its new home in one tight knot.
            -- Give every new resident one immediate, reserved base-life move so
            -- they fan out instead of idling on the scout's exterior anchor.
            self.settlementArrivalPending = true
            self.nextAmbientMoveAt = 0
        else
            self.settlementArrivalPending = nil
        end
        if baseId ~= nil and self.baseSupplyTrip ~= true
            and self.pendingBaseSupplyDeposit == nil then
            self:clearLifeIntent()
        end
        self:interruptForDirective()
    end
end

function Controller:clearBaseAssignment()
    if self.baseId ~= nil then
        self:interruptForDirective()
    end
    if self.baseSupplyKind ~= nil then
        self:releaseBaseSupplyClaim(self.baseSupplyKind)
    end
    self.baseId = nil
    self.base = nil
    self.baseSupplyTrip = nil
    self.baseSupplyKind = nil
end

-- Persistence is authoritative when an order or base preference changes. The
-- runtime notification clears only a stale automatic task pointer immediately;
-- manual Notebook work remains active until its normal completion/cancellation
-- boundary. This keeps the loaded controller aligned with the task board in the
-- same tick as the player-facing change.
function Controller:onDutyChanged()
    if self.pendingRecreation ~= nil then self:interruptForDirective() end
    local companionVehicles = rawget(_G, "KnoxCompanionVehicles")
    if companionVehicles ~= nil and self.character ~= nil then
        -- Vehicle leases are transient ownership held outside the controller.
        -- Any duty or order change must route them through the existing
        -- directive-interruption owner (which cancels the lease and, for a
        -- driver run, rolls back its passenger roster). isBusy both queries
        -- and expires stale leases; driverStatus covers a live run whose
        -- boarding lease already cleared. A lease-free survivor is untouched.
        local leaseBusy = companionVehicles.isBusy ~= nil
            and companionVehicles.isBusy(self.character) == true
        local driving = not leaseBusy and companionVehicles.driverStatus ~= nil
            and companionVehicles.driverStatus(self.character) ~= nil
        if leaseBusy or driving then self:interruptForDirective() end
    end
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local organizeNoLongerOwned = self.pendingOrganize ~= nil and (
        duty == nil or duty.mode ~= "base"
        or tostring(duty.baseId or "") ~= tostring(self.baseId or ""))
    local organizeInterrupted = false
    if organizeNoLongerOwned then
        -- Ambient organize rounds are not task-board claims. Retire their real
        -- item/container reservations and native action/route when the duty or
        -- hauling preference changes, just as an active base directive does.
        self:interruptForDirective()
        organizeInterrupted = true
    end
    if duty == nil or duty.mode ~= "base" then
        local hadBaseSupply = self.baseSupplyOrder ~= nil
            or self.baseSupplyTrip == true
            or self.pendingBaseSupplyDeposit ~= nil
        -- Manual work is protected from preference changes while the resident
        -- remains in the same base, but ownership ends when the survivor leaves
        -- base duty altogether. Never carry a stale base task into companion or
        -- independent autonomy.
        if self.baseTask ~= nil then
            self:releaseSupply()
            self.baseTask = nil
            self.baseTaskStartedAt = nil
            self.baseTaskRetryAt = 0
            if not organizeInterrupted then self:interruptForDirective() end
        end
        self.baseSupplyOrder = nil
        self.baseSupplyOrderAttempts = 0
        if hadBaseSupply then
            if self.baseSupplyKind ~= nil then
                self:releaseBaseSupplyClaim(self.baseSupplyKind)
            end
            self:releaseSupply()
            self.pendingBaseSupplyDeposit = nil
            self:clearLifeIntent()
            if not organizeInterrupted then self:interruptForDirective() end
        end
        return true
    end
    local supplyOrderChanged = self:syncBaseSupplyOrder()
    self:syncBaseSupplyRun()
    local continuingSupplyOrder = self.baseSupplyOrder ~= nil
        and self.baseSupplyTrip == true
        and self.baseSupplyOrder.kind == self.baseSupplyKind
    if supplyOrderChanged and not continuingSupplyOrder then
        self:releaseSupply()
        self:clearLifeIntent()
        self:interruptForDirective()
    end
    if self.baseTask ~= nil and self.baseTask.manual ~= true then
        local claimed = KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
            and KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, duty.baseId) or nil
        if claimed == nil or tostring(claimed.id or "") ~= tostring(self.baseTask.id or "") then
            self:releaseSupply()
            self.baseTask = nil
            self.baseTaskStartedAt = nil
            self.baseTaskRetryAt = 0
            self:interruptForDirective()
        end
    end
    self.nextThink = 0
    return true
end

function Controller:setEventAssignment(assignment)
    local old = self.eventAssignment
    local a, b = old ~= nil and old.destination or nil, assignment ~= nil and assignment.destination or nil
    local changed = (old == nil) ~= (assignment == nil)
        or (old ~= nil and assignment ~= nil and (old.id ~= assignment.id or old.phase ~= assignment.phase))
        or (a == nil) ~= (b == nil)
        or (a ~= nil and b ~= nil and (a.x ~= b.x or a.y ~= b.y or a.z ~= b.z))
    self.eventAssignment = assignment
    if changed then
        self.eventMoveFailures = 0
        self:interruptForDirective()
        if assignment == nil then self:clearGroupLeader(); self:setGroupMembers({}) end
    end
end

function Controller:beginEventTravel(ticks)
    local assignment = self.eventAssignment
    if assignment == nil then return false end
    -- Events outrank base work, but the claim survives: suspend it so the
    -- resident resumes the same task when the event releases them.
    if self.baseTask ~= nil and self.baseTask.type ~= "cook" then
        self:suspendBaseTaskForThreat("event_travel")
    end
    if assignment.phase == "objective" then
        return KnoxEventRuntime.beginObjectiveWork(self, ticks)
    end
    local goal, cell, current = assignment.destination, getCell(), self.character:getCurrentSquare()
    self.activeDecision = assignment.phase == "withdrawing" and "event_return" or "event_travel"
    if goal == nil or cell == nil or current == nil then
        self.state, self.nextThink = "EVENT_WAIT", math.max(self.nextThink or 0, ticks + 120)
        return true
    end
    local dx, dy = goal.x - current:getX(), goal.y - current:getY()
    local distance = dx * dx + dy * dy
    if current:getZ() == goal.z and distance <= 9 then
        self:resetMovementRecovery()
        self.eventMoveFailures = 0
        self.state, self.nextThink = "EVENT_WAIT", ticks + 90
        return true
    end
    local vehicleTravel = rawget(_G, "KnoxNpcVehicleTravel")
    if vehicleTravel ~= nil and vehicleTravel.tryBegin ~= nil
        and vehicleTravel.tryBegin(self, goal, ticks) then return true end
    if self.groupLeader ~= nil and distance > 36 then
        self:beginGroupFollow(ticks)
        return true
    end
    local distant, separation = self:findDistantGroupMember()
    if distant ~= nil and separation > Controller.TUNING.GROUP_RETRIEVE_LEASH_SQUARED then
        self:beginGroupRegroup(distant, ticks)
        return true
    end
    local target = cell:getGridSquare(math.floor(goal.x), math.floor(goal.y), goal.z)
    local x, y, z = goal.x, goal.y, goal.z
    if target == nil then
        -- Native movement toward the next loaded segment; the population
        -- lifecycle still owns capture and hibernation at the streaming edge.
        local fraction = math.min(1, 12 / math.max(1, math.sqrt(distance)))
        x, y, z = current:getX() + dx * fraction, current:getY() + dy * fraction, current:getZ()
    end
    target = nil
    for radius = 0, 2 do
        for ox = -radius, radius do
            for oy = -radius, radius do
                local square = cell:getGridSquare(math.floor(x) + ox, math.floor(y) + oy, z)
                if square ~= nil and square:canStand() then target = square; break end
            end
            if target ~= nil then break end
        end
        if target ~= nil then break end
    end
    local result = target ~= nil and tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "directed"))) or "event_route_unloaded"
    if string.find(result, "MOVE_STARTED", 1, true) == 1 then
        self.state = "EVENT_TRAVEL"
    else
        self.eventMoveFailures = (self.eventMoveFailures or 0) + 1
        self:recordMovementFailure("event_travel", result, ticks, 120)
        self.state = "EVENT_WAIT"
    end
    return true
end

function Controller:releaseCampPosition()
    release(
        self.reservations,
        "campPositions",
        self.campPosition,
        self.id
    )
    self.campPosition = nil
end

function Controller:setCampAssignment(campId, camp, slot)
    local normalizedSlot = math.max(1, tonumber(slot) or 1)
    local changed = self.campId ~= campId or self.camp ~= camp
        or self.campSlot ~= normalizedSlot
    if changed then
        self:releaseCampPosition()
    end
    self.campId = campId
    self.camp = camp
    self.campSlot = normalizedSlot
    if changed then
        self.campPositionCycle = 0
        self.campExcursion = false
        self.campExcursionExplored = false
        self.nextCampExcursion = 0
        if campId ~= nil then self:clearLifeIntent() end
        self:interruptForDirective()
    end
end

function Controller:clearCampAssignment()
    if self.campId == nil then
        return
    end
    self:releaseCampPosition()
    self.campId = nil
    self.camp = nil
    self.campSlot = 1
    self.campPositionCycle = 0
    self.campExcursion = false
    self.campExcursionExplored = false
    self:interruptForDirective()
end

function Controller:setAwayTeam(teamId)
    self.awayTeamId = type(teamId) == "string" and teamId ~= "" and teamId or nil
    self.awayCollected = false
    self.awaySearchMisses = 0
    if self.awayTeamId ~= nil then
        self.activeDecision = "away_mission"
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:beginAwayReturn(ticks)
    if self.awayTeamId == nil then return false end
    local target = KnoxAwayTeamExecutor.returnDestination(self.awayTeamId)
    if target == nil or getCell == nil or getCell() == nil then
        self:recordFailure("away_return_target_unavailable", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local square = getCell():getGridSquare(
        math.floor(tonumber(target.x) or 0),
        math.floor(tonumber(target.y) or 0),
        math.floor(tonumber(target.z) or 0)
    )
    local canStand = square ~= nil
    if canStand and square.canStand ~= nil then
        local ok, value = pcall(square.canStand, square)
        canStand = ok and value == true
    end
    if not canStand then
        self:recordFailure("away_return_square_unloaded", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local current = self.character:getCurrentSquare()
    if current ~= nil and navigationDistanceSquared(current, square) <= 2.25 then
        local result = KnoxPersistence.completeAwayTeamMember(
            self.awayTeamId, self.id, true, "returned_to_owner", currentWorldAgeHours()
        )
        if result ~= nil then
            self.awayTeamId = nil
            self.awayCollected = false
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks + THINK_MIN_TICKS
            return true
        end
    end
    local movement = tostring(moveWithTravelPace(
        self.bridge, self.id, self.character, square, "return_home"
    ))
    if string.find(movement, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordMovementFailure("away_return", movement, ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    self.activeDecision = "away_return"
    self.state = "AWAY_RETURN"
    return true
end

function Controller:beginAwayMission(ticks)
    if self.awayTeamId == nil then return false end
    local team = KnoxPersistence.getAwayTeam(self.awayTeamId)
    if team == nil then
        self.awayTeamId = nil
        return false
    end
    if team.state == "returning" then
        return self:beginAwayReturn(ticks)
    end
    if team.state ~= "awaiting_collection" and team.state ~= "collecting" then
        return false
    end
    if self.awayCollected then
        self.activeDecision = "away_waiting_for_team"
        self.state = "GROUP_WAIT"
        self.nextThink = ticks + 120
        return true
    end
    local _, beginResult = KnoxAwayTeamExecutor.beginCollection(
        self.awayTeamId, currentWorldAgeHours()
    )
    if beginResult == "not_collectible" then return false end
    local directive = KnoxAwayTeamExecutor.destinationDirective(team)
    if directive == nil then
        self:recordFailure("away_destination_unavailable", ticks, EXPLORATION_RETRY_TICKS)
        return true
    end
    if self:beginExploration(ticks, directive) then
        self.awaySearchMisses = 0
        return true
    end
    self.awaySearchMisses = (self.awaySearchMisses or 0) + 1
    if self.awaySearchMisses >= 3 then
        KnoxAwayTeamExecutor.recordCollection(
            self.awayTeamId, self.id, {}, self.character, currentWorldAgeHours()
        )
        self.awayCollected = true
        self.awaySearchMisses = 0
        self.nextThink = ticks + 120
    end
    return true
end

-- A loaded away member acknowledges a destination only after the ordinary
-- search/transfer action has finished.  This keeps mission results tied to
-- real inventory state and lets the persistence layer hold the group until
-- every member has completed the same boundary.
function Controller:finishAwayCollection(ticks)
    if self.awayTeamId == nil then return false end
    local supply = self.pendingSupply
    local recorded, detail = KnoxAwayTeamExecutor.recordCollection(
        self.awayTeamId,
        self.id,
        supply,
        self.character,
        currentWorldAgeHours()
    )
    self:releaseSupply()
    if recorded == nil then
        self:recordFailure(
            "away_collection_record:" .. tostring(detail),
            ticks,
            EXPLORATION_RETRY_TICKS
        )
        self.state = "IDLE"
        self.activeDecision = "away_collection_retry"
        self.nextThink = ticks + EXPLORATION_RETRY_TICKS
        return true
    end
    self.awayCollected = true
    self.awaySearchMisses = 0
    if KnoxAwayTeamExecutor.collectionReady(self.awayTeamId) then
        local _, returnResult = KnoxAwayTeamExecutor.beginReturn(
            self.awayTeamId,
            currentWorldAgeHours()
        )
        if returnResult == "returning" then
            self.awayCollected = false
            self.activeDecision = "away_return_pending"
            self.state = "IDLE"
            self.nextThink = ticks
            return true
        end
        self:recordFailure(
            "away_return_begin:" .. tostring(returnResult),
            ticks,
            EXPLORATION_RETRY_TICKS
        )
    end
    self.activeDecision = "away_waiting_for_team"
    self.state = "GROUP_WAIT"
    self.nextThink = ticks + 120
    return true
end

function Controller:setFactionBaseCandidate(factionId, candidate)
    self.factionId = factionId
    self.factionBaseCandidate = candidate
end

function Controller:clearFactionBaseCandidate()
    self.factionId = nil
    self.factionBaseCandidate = nil
end

function Controller:rejectFactionBaseCandidate(ticks, reason)
    local candidate = self.factionBaseCandidate
    local worldAge = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if candidate ~= nil then
        KnoxPersistence.rejectFactionBaseCandidate(
            self.factionId,
            candidate.buildingId,
            worldAge
        )
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " faction-base-rejected reason=" .. tostring(reason)
    )
    self:clearFactionBaseCandidate()
end

function Controller:findDistantGroupMember()
    local square = self.character:getCurrentSquare()
    if square == nil then
        return nil, nil
    end
    local farthest = nil
    local farthestDistance = Controller.TUNING.GROUP_SOFT_LEASH_SQUARED
    for _, member in ipairs(self.groupMembers or {}) do
        local dead = member ~= nil and member.isDead ~= nil and member:isDead()
        if member ~= nil and not dead and member ~= self.character
            and member:getCurrentSquare() ~= nil then
            local memberSquare = member:getCurrentSquare()
            local distance = memberSquare:getZ() == square:getZ()
                and distanceSquared(square, memberSquare)
                or Controller.TUNING.GROUP_RETRIEVE_LEASH_SQUARED + 1
            if distance > farthestDistance then
                farthest = member
                farthestDistance = distance
            end
        end
    end
    return farthest, farthest ~= nil and farthestDistance or nil
end

local function needCalloutIsCurrent(character, decision)
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    return character ~= nil and needs ~= nil and needs.isNeedCurrent ~= nil
        and needs.isNeedCurrent(character, decision) == true
end

function Controller:sayNeedIfGrouped(decision, ticks)
    local grouped = self.companionTarget ~= nil
        or self.groupLeader ~= nil
        or #(self.groupMembers or {}) > 1
    if not grouped or ticks < self.nextNeedCallout
        or not needCalloutIsCurrent(self.character, decision) then
        return
    end
    local lines = {
        find_food = "I'm nearly out of food.",
        find_water = "I need water soon.",
        find_medical = "I need something for this wound.",
        eat = "Give me a second to eat.",
        drink = "I need a second to drink.",
        bandage = "Hold on, I need to patch this up.",
        improvise_medical = "I need to make something for this wound.",
        rest = "I need to sit down for a minute.",
        sleep = "I need to get some sleep.",
    }
    local line = lines[decision]
    if line ~= nil then
        KnoxActivityFeed.speak(self.character, line)
        self.nextNeedCallout = ticks + 1800
    end
end

function Controller:sayAction(lines, ticks, cooldown)
    local spoken = sayDialogue(self.character, self.id, "action",
        ticks, cooldown, lines)
    if spoken then
        self.nextActionCallout = ticks + math.max(900, tonumber(cooldown) or 1800)
    end
    return spoken
end

function Controller:canInterruptForMeeting()
    if self.character == nil or self.baseTask ~= nil or self.tradeAction ~= nil
        or nativeTraversalBusy(self.character) then return false end
    local resting = (self.state == "WAITING_TO_RECOVER" or self.state == "BASE_AMBIENT_REST")
        and (self.activeDecision == "rest" or self.activeDecision == "sleep"
            or self.activeDecision == "base_ambient_rest")
    if not self.character:getCharacterActions():isEmpty() and not resting then return false end
    return self.state == "IDLE"
        or self.state == "ROAMING"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "GROUP_WAIT"
        or self.state == "GROUP_FOLLOW"
        or self.state == "BASE_IDLE"
        or self.state == "BASE_AMBIENT_REST"
end

-- Player conversation takes a short, interruptible attention lease. It does
-- not rewrite Follow/Hold/base/group duty or take over an active native job.
function Controller:beginPlayerConversation(player)
    local ticks = self.currentTicks or 0
    local currentConversation = self.playerConversation
    local extraState = self.state == "COMPANION_FOLLOW" or self.state == "COMPANION_WAIT"
        or self.state == "COMPANION_HOLD" or self.state == "COMPANION_GUARD"
        or self.state == "CAMP_IDLE" or self.state == "CAMP_REPOSITION"
        or self.state == "BASE_PATROL"
    if player == nil or self.character == nil or self.baseTask ~= nil
        or self.tradeAction ~= nil or nativeTraversalBusy(self.character)
        or not self.character:getCharacterActions():isEmpty()
        or safeMethod(self.character, "getVehicle", nil) ~= nil
        or safeMethod(player, "getVehicle", nil) ~= nil then return false, "survivor_busy" end
    local current, target = self.character:getCurrentSquare(), player:getCurrentSquare()
    if current == nil or target == nil or current:getZ() ~= target:getZ()
        or distanceSquared(current, target) > 16 then return false, "too_far_away" end
    if safeMethod(self.character, "CanSee", false, player) ~= true then
        return false, "not_visible"
    end
    if fleeAssessment(self) or nearestThreat(self, ticks) ~= nil then return false, "danger" end
    -- A second Talk/social action from the same player continues the existing
    -- attention lease instead of trying to admit PLAYER_CONVERSATION as a new
    -- idle state. Other players cannot take over that short lease.
    if currentConversation ~= nil then
        if currentConversation.player ~= player then return false, "survivor_busy" end
        currentConversation.untilTick = ticks + 600
        self.nextThreatScan = 0
        safeMethod(self.character, "faceThisObject", nil, player)
        return true, "talking"
    end
    if not (self:canInterruptForMeeting() or extraState) then
        return false, "survivor_busy"
    end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    self:leaveRecoveryPosture()
    self.playerConversation = { player = player, untilTick = ticks + 600 }
    self.state, self.activeDecision = "PLAYER_CONVERSATION", "talk_to_player"
    self.nextThreatScan = 0
    safeMethod(self.character, "faceThisObject", nil, player)
    return true, "talking"
end

function Controller:endPlayerConversation(player)
    if self.playerConversation == nil or self.playerConversation.player ~= player then return false end
    self.playerConversation = nil
    if self.state == "PLAYER_CONVERSATION" then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
    end
    return true
end

function Controller:updatePlayerConversation(ticks)
    local conversation = self.playerConversation
    if conversation == nil then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
        return
    end
    local player = conversation.player
    local square = player ~= nil and player:getCurrentSquare() or nil
    local current = self.character:getCurrentSquare()
    local ended = ticks >= conversation.untilTick or square == nil or current == nil
        or safeMethod(player, "isDead", true) == true
        or safeMethod(player, "getVehicle", nil) ~= nil
        or square:getZ() ~= current:getZ() or distanceSquared(current, square) > 25
    if not ended and ticks >= (conversation.nextNeedsCheck or 0) then
        conversation.nextNeedsCheck = ticks + 60
        local decision = KnoxSurvivorNeeds.decide(self.character, nil)
        ended = decision ~= nil and decision.kind ~= "roam"
    end
    if ended then self:endPlayerConversation(player) end
end

function Controller:beginTrade(action)
    if type(action) ~= "table" or action.npc ~= self.character
        or self.tradeAction ~= nil or self.character == nil or nativeTraversalBusy(self.character)
        or not self.character:getCharacterActions():isEmpty() or self.baseTask ~= nil
        or not (self:canInterruptForMeeting() or self.state == "BASE_IDLE" or self.state == "CAMP_IDLE") then
        return false
    end
    if fleeAssessment(self) or nearestThreat(self, self.nextThreatScan or 0) ~= nil then return false end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    self:leaveRecoveryPosture()
    self.tradeAction, self.tradeTicksRemaining = action, action.browsing and 7200 or 1800
    self.state, self.activeDecision = "TRADING", "trade"
    self.nextThreatScan = 0
    return true
end

function Controller:releaseTrade(action)
    if self.tradeAction ~= action then return false end
    self.tradeAction, self.tradeTicksRemaining = nil, nil
    if self.state == "TRADING" then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
    end
    return true
end

function Controller:cancelTrade(reason)
    local action = self.tradeAction
    if action == nil then return end
    self:releaseTrade(action)
    action.cancelled = reason
end

function Controller:interruptForMeeting()
    if not self:canInterruptForMeeting() then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    if self.activeDecision == "rest" or self.activeDecision == "sleep"
        or self.activeDecision == "base_ambient_rest" then
        -- This state owns the queued rest action. Stop it before releasing its
        -- furniture reservation, so the subsequent approach can actually move.
        if not self.character:getCharacterActions():isEmpty() then
            ISTimedActionQueue.clear(self.character)
        end
        self:leaveRecoveryPosture()
    end
    self.selfCareInterrupted = self.selfCareIntent ~= nil
        and self.activeDecision or self.selfCareInterrupted
    self.selfCareIntent = nil
    self.activeDecision = "meet_survivor"
    self.state = "MEETING_WAIT"
    return true
end

function Controller:beginMeetingApproach(otherCharacter)
    if self.state ~= "MEETING_WAIT" or otherCharacter == nil
        or otherCharacter:getCurrentSquare() == nil then
        return false
    end
    local approach = AdjacentFreeTileFinder.Find(
        otherCharacter:getCurrentSquare(),
        self.character
    )
    if approach == nil then
        return false
    end
    local result = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    self.state = "MEETING_APPROACH"
    return true
end

function Controller:beginGreeting()
    self.bridge:cancelNpcMove(self.id)
    self.state = "GREETING"
end

function Controller:resumeAfterGreeting(ticks)
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = ticks + THINK_MIN_TICKS
end

function Controller:registerAllyDefenseThreat(hostileId, expiresAt)
    if type(hostileId) ~= "string" or hostileId == "" then return false end
    self.allyDefenseThreats = self.allyDefenseThreats or {}
    self.allyDefenseThreats[hostileId] = math.max(
        tonumber(self.allyDefenseThreats[hostileId]) or 0,
        tonumber(expiresAt) or 0
    )
    return true
end

function Controller:holdForRobbery(robber, ticks)
    local robberController = robber ~= nil and robber.character ~= nil and robber or nil
    local robberCharacter = robberController ~= nil and robberController.character or robber
    if robberCharacter == nil then return false end
    self.pendingRobberyHold = {
        robber = robberCharacter,
        robberController = robberController,
        expiresAt = (tonumber(ticks) or 0) + 300,
    }
    self.activeDecision = "robbery_hold"
    self.state = "GROUP_WAIT"
    self.nextThink = (tonumber(ticks) or 0) + 300
    return true
end

function Controller:releaseRobberyHold(robber, ticks, reason)
    local hold = self.pendingRobberyHold
    if hold == nil or (robber ~= nil and hold.robber ~= robber) then return false end
    self.pendingRobberyHold = nil
    if reason == "combat_interrupt" and hold.robberController ~= nil
        and hold.robberController.cancelRobbery ~= nil then
        hold.robberController:cancelRobbery(
            tonumber(ticks) or 0, "victim_combat_interrupt"
        )
    end
    if self.state == "GROUP_WAIT" and self.activeDecision == "robbery_hold" then
        self:resumeAfterGreeting(tonumber(ticks) or 0)
    end
    return true
end

function Controller:cancelRobbery(ticks, reason)
    local robbery = self.pendingRobbery
    if robbery == nil then return false end
    self:diag("social", "robbery_cancelled", { reason = tostring(reason or "cancelled") })
    self.pendingRobbery = nil
    if robbery.victimController ~= nil
        and robbery.victimController.releaseRobberyHold ~= nil then
        robbery.victimController:releaseRobberyHold(
            self.character, tonumber(ticks) or 0, reason or "cancelled"
        )
    end
    return true
end

function Controller:beginRobbery(victim, ticks)
    local victimController = victim ~= nil and victim.character ~= nil and victim or nil
    local victimCharacter = victimController ~= nil and victimController.character or victim
    if victimCharacter == nil or victimCharacter:getInventory() == nil then
        return false
    end
    local candidates = {}
    -- Robbers use the same needs/upgrades filter as ordinary looting. This keeps
    -- the encounter grounded and prevents filler such as grass or trash from
    -- winning a transfer slot merely because the victim happened to carry it.
    for _, candidate in ipairs(KnoxSurvivorLooting.plan(
        self.character,
        victimCharacter:getInventory(),
        4
    )) do
        if not victimCharacter:isEquipped(candidate.item) and not candidate.item:isFavorite() then
            candidates[#candidates + 1] = candidate
        end
    end
    local queued = {}
    for index = 1, math.min(2, #candidates) do
        local candidate = candidates[index]
        local action = KnoxInventoryActions.queueTransfer(
            self.character,
            candidate.item,
            victimCharacter:getInventory(),
            self.character:getInventory(),
            nil
        )
        if action ~= nil then
            queued[#queued + 1] = candidate.item:getFullType()
        end
    end
    if #queued == 0 then
        return false
    end
    self.pendingRobbery = {
        victim = victimCharacter,
        victimController = victimController,
        items = queued,
        expiresAt = (tonumber(ticks) or 0) + 300,
    }
    self.activeDecision = "rob_survivor"
    self.state = "ROBBING"
    self.stateStartedAt = ticks
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROBBING items=" .. table.concat(queued, ",")
    )
    self:diag("social", "robbery_started", { items = #queued })
    return true
end

function Controller:beginGroupFollow(ticks)
    if self.groupLeader == nil or self.groupLeader:getCurrentSquare() == nil then
        return false
    end
    local approach = findFormationTarget(
        self.groupLeader,
        self.character,
        self.groupFormationSlot, self.id
    )
    if approach == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local moveResult, pace = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        self.groupLeader,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, false)
        return false
    end
    self.activeDecision = "follow_group"
    self.state = "GROUP_FOLLOW"
    self.stateStartedAt = ticks
    self.formationTargetX = approach:getX()
    self.formationTargetY = approach:getY()
    self.formationTargetZ = approach:getZ()
    self.formationMovementPace = pace
    self.formationCommitUntil = ticks + Controller.TUNING.FORMATION_ROUTE_COMMIT_TICKS
    self.nextFormationRefresh = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
        + formationRefreshDelay(self.groupFormationSlot)
    return true
end

-- Native route success only means the follower reached the last requested
-- formation tile. The leader may already have moved again, so do not impose a
-- full formation-refresh wait here. Re-enter normal decision arbitration on
-- the next controller tick; that path keeps urgent needs, threats, combat,
-- traversal and route-commit suppression authoritative.
function Controller:resumeGroupFollowAfterSuccess(ticks)
    self:resetMovementRecovery()
    self.formationMovementPace = nil
    self.activeDecision = "follow_group"
    self.state = "IDLE"
    self.nextThink = ticks
    self.nextFormationRefresh = ticks
end

function Controller:beginGroupRegroup(member, ticks)
    local memberSquare = member ~= nil and member:getCurrentSquare() or nil
    if memberSquare == nil then
        return false
    end
    local approach = AdjacentFreeTileFinder.Find(memberSquare, self.character)
    if approach == nil then
        return false
    end
    local moveResult = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        member,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, false)
        return false
    end
    self:issueGroupLeaderOrder("follow", ticks)
    self:signalFollowers("comehere", ticks)
    self.regroupMember = member
    self.activeDecision = "retrieve_group_member"
    self.state = "GROUP_REGROUP"
    self.stateStartedAt = ticks
    if ticks >= self.nextRegroupCallout then
        sayDialogue(self.character, self.id, "regroup", ticks, 1800)
        self.nextRegroupCallout = ticks + 1800
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=GROUP_REGROUP target=" .. tostring(member)
    )
    return true
end

function Controller:resolvePlayerPartyAnchor(ticks)
    local player = self.companionTarget
    if player == nil then return nil, nil, "player_unavailable" end
    local deadOk, dead = pcall(function() return player:isDead() end)
    if deadOk and dead == true then
        self:releasePlayerFormationTarget()
        self:releasePartyDestinationTarget()
        local service = rawget(_G, "KnoxCompanionService")
        if service ~= nil and service.cancelPartyDestination ~= nil then
            service.cancelPartyDestination(player)
        end
        return nil, nil, "player_dead"
    end
    local vehicle = nil
    pcall(function() vehicle = player:getVehicle() end)
    if vehicle ~= nil then
        local speedOk, speed = pcall(function()
            return math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 0)
        end)
        if speedOk and speed > 1 then
            return nil, nil, "player_vehicle_moving"
        end
    end
    if nativeTraversalBusy(player) then
        return nil, nil, "player_traversal"
    end
    local okSquare, square = pcall(function() return player:getCurrentSquare() end)
    if okSquare and square ~= nil then
        self.companionAnchorUnavailableSince = nil
        return player, square, nil
    end
    local since = self.companionAnchorUnavailableSince
    if since == nil then
        since = ticks
        self.companionAnchorUnavailableSince = since
    end
    if ticks - since > Controller.PLAYER_PARTY_FORMATION.anchorFallbackTicks then
        self:releasePlayerFormationTarget()
        return nil, nil, "player_anchor_streamed_out"
    end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return nil, nil, "player_anchor_streamed_out" end
    local coordsOk, x, y, z = pcall(function()
        return player:getX(), player:getY(), player:getZ()
    end)
    if not coordsOk or tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil then
        return nil, nil, "player_anchor_position_missing"
    end
    local fallback = nil
    pcall(function()
        fallback = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    end)
    if not Controller.squareCanStand(fallback) then
        return nil, nil, "player_anchor_square_unavailable"
    end
    return player, fallback, "player_anchor_spatial_fallback"
end

function Controller.partyFoodSupportEligible(context)
    context = type(context) == "table" and context or {}
    return context.autoLootAllowed == true
        and context.playerOwned == true
        and context.baseResident ~= true
        and context.order == "follow"
        and context.formationSettled == true
        and context.explicitDirective ~= true
        and context.supplyActive ~= true
        and context.combatActive ~= true
        and context.threatActive ~= true
        and context.urgentNeed == nil
end

function Controller.partyFoodSupportAnchorWithinLeash(pending, anchor)
    if type(pending) ~= "table" or pending.partySupport ~= true or anchor == nil then
        return false
    end
    local x, y, z = tonumber(pending.playerAnchorX), tonumber(pending.playerAnchorY),
        tonumber(pending.playerAnchorZ)
    if x == nil or y == nil or z == nil or anchor.getX == nil
        or anchor.getY == nil or anchor.getZ == nil then
        return false
    end
    if anchor:getZ() ~= z then return false end
    local dx, dy = anchor:getX() - x, anchor:getY() - y
    return dx * dx + dy * dy <= Controller.PARTY_SUPPORT_FOOD_LEASH_SQUARED
end

function Controller.hasPartyFoodReceipt(inventory, item)
    if inventory == nil or item == nil or inventory.contains == nil then return false end
    local ok, contains = pcall(function() return inventory:contains(item) end)
    return ok and contains == true
end

function Controller:abandonPartyFoodForFollow(ticks, reason)
    local pending = self.pendingSupply
    if pending == nil or pending.partySupport ~= true then return false end
    if pending.container ~= nil then
        self.inspectedContainers[pending.container] = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
    end
    self.nextExplorationSearch = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
    self.bridge:cancelNpcMove(self.id)
    self:recordFailure("party_support_" .. tostring(reason), ticks,
        LOOT_TRAVEL_COOLDOWN_TICKS)
    self:releaseSupply()
    self:finishDecision(ticks)
    self.nextThink = ticks + THINK_MIN_TICKS
    return true
end

function Controller:beginCompanionFollow(ticks)
    if self.companionOrder ~= "follow" then
        return false
    end
    -- Do not issue a fresh route while the native climb/vault action owns the
    -- body; the follow refresh retries once the landing tick settles.
    if nativeTraversalBusy(self.character) then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local anchor, anchorSquare, anchorReason = self:resolvePlayerPartyAnchor(ticks)
    if anchor == nil or anchorSquare == nil then
        self.companionAnchorWaitReason = anchorReason
        self.activeDecision = "wait_for_party_anchor"
        self.state = "COMPANION_WAIT"
        self.nextThink = ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS
        return false
    end
    self.companionAnchorWaitReason = anchorReason
    local approach, compressed = self:findPlayerPartyFormationTarget(anchor, anchorSquare)
    if approach == nil then
        self:releasePlayerFormationTarget()
        self.state = "COMPANION_WAIT"
        self.activeDecision = "party_regrouping"
        self.nextThink = math.max(self.nextThink or 0,
            ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS)
        return false
    end
    local moveResult, pace = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        anchor,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, true)
        return false
    end
    local distance = navigationDistanceSquared(
        self.character:getCurrentSquare(), anchorSquare
    )
    if compressed then self.activeDecision = "party_regrouping"
    elseif distance >= Controller.PLAYER_PARTY_FORMATION.runDistanceSquared then
        self.activeDecision = "party_catching_up"
    else self.activeDecision = "follow_player" end
    self.state = "COMPANION_FOLLOW"
    self.stateStartedAt = ticks
    self.formationTargetX = approach:getX()
    self.formationTargetY = approach:getY()
    self.formationTargetZ = approach:getZ()
    self.formationMovementPace = pace
    self.formationCommitUntil = ticks + Controller.TUNING.FORMATION_ROUTE_COMMIT_TICKS
    self.nextFormationRefresh = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
    return true
end

-- A following companion treats a parked player vehicle as the formation
-- anchor. Boarding remains a native vehicle action; this only avoids issuing
-- a ground route behind a car that the companion is meant to ride in.
function Controller:tryBoardFollowVehicle(ticks)
    local target = self.companionTarget
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if self.companionOrder ~= "follow" or target == nil or vehicles == nil
        or vehicles.board == nil or self.character:getVehicle() ~= nil
        or ticks < (self.nextVehicleBoardAttempt or 0) then return false end
    local vehicle, origin = target:getVehicle(), self.character:getCurrentSquare()
    if vehicle == nil or origin == nil or vehicle:getSquare() == nil
        or origin:getZ() ~= vehicle:getZ()
        or distanceSquared(self.character, vehicle) > 30 * 30
        or math.abs(vehicle:getCurrentSpeedKmHour()) > 1 then return false end
    self.nextVehicleBoardAttempt = ticks + 180
    local started, reason = vehicles.board(self.character, vehicle)
    if started then
        self:diag("vehicle", "boarded", nil)
        self.activeDecision, self.state = "board_companion_vehicle", "COMPANION_WAIT"
        return true
    end
    self:diag("vehicle", "board_failed", { reason = tostring(reason) })
    if reason == "no_free_passenger_seat" then self.nextVehicleBoardAttempt = ticks + 900 end
    return false
end

function Controller:refreshFormationFollow(ticks)
    -- Hold the current route while climbing/vaulting instead of cancelling
    -- and immediately re-issuing it (the pre/post-climb snap). Check this
    -- before the normal refresh cadence so the busy -> landed edge cannot be
    -- hidden behind a timer that was scheduled before the climb began.
    local traversalBusy = nativeTraversalBusy(self.character)
    if traversalBusy then
        if not self.formationTraversalBusy then
            self.formationTraversalBusy = true
            self:diag("movement", "traversal_started", {
                state = tostring(self.state),
            })
        end
        self.nextFormationRefresh = ticks + THINK_MIN_TICKS
        return false
    end
    if self.formationTraversalBusy then
        self.formationTraversalBusy = nil
        self.nextFormationRefresh = ticks
        self:diag("movement", "traversal_completed", {
            state = tostring(self.state),
        })
    end
    if self.state == "GROUP_FOLLOW" and self:applyGroupLeaderOrder(ticks) then
        return true
    end
    if ticks < self.nextFormationRefresh then
        return false
    end
    local groupFollow = self.state == "GROUP_FOLLOW"
    local slot = groupFollow and self.groupFormationSlot or self.companionFormationSlot
    if not groupFollow and self.companionOrder ~= "follow" then
        self.bridge:cancelNpcMove(self.id)
        self.formationMovementPace = nil
        self.activeDecision = self.companionOrder == "hold"
            and "hold_position" or nil
        self.state = self.companionOrder == "hold"
            and "COMPANION_HOLD" or "COMPANION_WAIT"
        self.nextThink = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
            + formationRefreshDelay(slot)
        return true
    end
    local anchor = groupFollow and self.groupLeader or self.companionTarget
    local partyAnchorSquare = nil
    if not groupFollow then
        local resolvedAnchor, resolvedSquare = self:resolvePlayerPartyAnchor(ticks)
        if resolvedAnchor == nil or resolvedSquare == nil then
            self.activeDecision = "wait_for_party_anchor"
            self.nextFormationRefresh = ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS
            self.nextThink = math.max(self.nextThink or 0, self.nextFormationRefresh)
            return false
        end
        anchor, partyAnchorSquare = resolvedAnchor, resolvedSquare
    end
    local target, compressed
    if groupFollow then
        -- The autonomous NPC group formation path is intentionally unchanged.
        target = findFormationTarget(anchor, self.character, slot, self.id)
    else
        target, compressed = self:findPlayerPartyFormationTarget(
            anchor, partyAnchorSquare, true
        )
    end
    local current = self.character:getCurrentSquare()
    self.nextFormationRefresh = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
        + (groupFollow and formationRefreshDelay(slot) or 0)
    if target == nil or current == nil then
        if not groupFollow then
            self.bridge:cancelNpcMove(self.id)
            self:releasePlayerFormationTarget()
            self.formationMovementPace = nil
            self.activeDecision = "party_regrouping"
            self.state = "COMPANION_WAIT"
            self.nextThink = math.max(self.nextThink or 0,
                ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS)
            return true
        end
        return false
    end
    if not groupFollow then
        local distance = navigationDistanceSquared(current, partyAnchorSquare)
        if compressed then self.activeDecision = "party_regrouping"
        elseif distance >= Controller.PLAYER_PARTY_FORMATION.runDistanceSquared then
            self.activeDecision = "party_catching_up"
        elseif self.activeDecision == "party_regrouping"
            or self.activeDecision == "party_catching_up" then
            self.activeDecision = "follow_player"
        end
    end
    self:updateFormationMovementPace(anchor)
    if navigationDistanceSquared(current, target)
        <= Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED then
        -- Same-zone arrival only: if the anchor is across a wall/doorway
        -- (one of us inside a room, the other outside or in another
        -- building), keep moving into their space instead of parking on the
        -- wrong side until the player moves. Adjacent rooms in one building
        -- (kitchen/living open arches) count as arrived. Bounded by the
        -- normal route-commit window so this cannot spam moves.
        local crossZone = false
        do
            local anchorSquare = partyAnchorSquare
            if anchorSquare == nil and anchor ~= nil then
                local ok, sq = pcall(function() return anchor:getCurrentSquare() end)
                if ok then anchorSquare = sq end
            end
            if anchorSquare ~= nil and current ~= nil and anchorSquare ~= current then
                local okR1, room1 = pcall(function() return current:getRoom() end)
                local okR2, room2 = pcall(function() return anchorSquare:getRoom() end)
                if okR1 and okR2 then
                    if (room1 == nil) ~= (room2 == nil) then
                        crossZone = true
                    else
                        local okB1, b1 = pcall(function() return current:getBuilding() end)
                        local okB2, b2 = pcall(function() return anchorSquare:getBuilding() end)
                        if okB1 and okB2 and b1 ~= nil and b2 ~= nil and b1 ~= b2 then
                            crossZone = true
                        end
                    end
                end
                if crossZone then
                    local dd = navigationDistanceSquared(current, anchorSquare)
                    if (tonumber(dd) or math.huge) > 121 then
                        crossZone = false
                    end
                end
            end
        end
        if crossZone then
            if ticks >= (self.formationCommitUntil or 0) then
                local moved = false
                if groupFollow then moved = self:beginGroupFollow(ticks)
                else moved = self:beginCompanionFollow(ticks) end
                if moved then return true end
            end
            self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
            return true
        end
        self.bridge:cancelNpcMove(self.id)
        self:resetMovementRecovery()
        self.formationMovementPace = nil
        self.formationCommitUntil = 0
        self.activeDecision = groupFollow and "follow_group" or "follow_player"
        self.state = groupFollow and "GROUP_WAIT" or "COMPANION_WAIT"
        self.nextThink = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
            + (groupFollow and formationRefreshDelay(slot) or 0)
        return true
    end
    local shifted = self.formationTargetZ ~= target:getZ()
        or self.formationTargetX == nil or self.formationTargetY == nil
        or (self.formationTargetX - target:getX()) ^ 2
            + (self.formationTargetY - target:getY()) ^ 2
                > Controller.TUNING.FORMATION_REPATH_SHIFT_SQUARED
    if not shifted then
        return false
    end
    if ticks < (self.formationCommitUntil or 0) and self.formationTargetZ == target:getZ() then
        return false
    end
    local restarted
    if groupFollow then
        restarted = self:beginGroupFollow(ticks)
    else
        restarted = self:beginCompanionFollow(ticks)
    end
    if not restarted then
        self.state = groupFollow and "GROUP_WAIT" or "COMPANION_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
    end
    return true
end

function Controller:findBaseMovementTarget(returning, ticks)
    local home = self.base ~= nil and self.base.home or nil
    local cell = getCell()
    if home == nil or cell == nil then
        return nil
    end
    local z = tonumber(home.z) or 0
    if returning then
        local centerX = math.floor((tonumber(home.minX) or 0)
            + (tonumber(home.width) or 1) / 2)
        local centerY = math.floor((tonumber(home.minY) or 0)
            + (tonumber(home.height) or 1) / 2)
        self.reservations = self.reservations or {}
        self.reservations.ambientSpots = self.reservations.ambientSpots or {}
        local anchors = {
            { x = centerX, y = centerY },
            { x = math.floor(tonumber(home.x) or centerX),
                y = math.floor(tonumber(home.y) or centerY) },
        }
        -- Prefer a real indoor tile in the claimed building, then any valid
        -- tile inside the home bounds. The old scout square can be outside at
        -- a wall corner and caused every resident to select that same point.
        for _, requireIndoor in ipairs({ true, false }) do
            for _, anchor in ipairs(anchors) do
                for radius = 0, 8 do
                    for dx = -radius, radius do
                        for dy = -radius, radius do
                            if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                                local square = cell:getGridSquare(
                                    anchor.x + dx,
                                    anchor.y + dy,
                                    z
                                )
                                local moving = safeMethod(square, "getMovingObjects", nil)
                                local unoccupied = moving == nil or moving:size() == 0
                                local key = ambientSpotKey(square)
                                local inHome = square ~= nil
                                    and square:getX() >= (tonumber(home.minX) or centerX)
                                    and square:getX() < (tonumber(home.minX) or centerX)
                                        + math.max(1, tonumber(home.width) or 1)
                                    and square:getY() >= (tonumber(home.minY) or centerY)
                                    and square:getY() < (tonumber(home.minY) or centerY)
                                        + math.max(1, tonumber(home.height) or 1)
                                local indoors = safeMethod(square, "getRoom", nil) ~= nil
                                if inHome and square:canStand() and unoccupied
                                    and (not requireIndoor or indoors)
                                    and key ~= nil
                                    and not reservedByOther(
                                        self.reservations, "ambientSpots", key, self.id
                                    ) then
                                    return square
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end
    local current = self.character:getCurrentSquare()
    if current==nil or not KnoxBaseManager.containsSquare(self.base,current) then return nil end
    local hour = getGameTime ~= nil and getGameTime():getTimeOfDay() or 12
    local daylight = hour >= 7 and hour < 20
    local area = self.base.territory or home
    local minX,minY=tonumber(area.minX),tonumber(area.minY)
    if minX==nil or minY==nil then return nil end
    local maxX=tonumber(area.maxX) or (minX+math.max(1,tonumber(area.width) or 1)-1)
    local maxY=tonumber(area.maxY) or (minY+math.max(1,tonumber(area.height) or 1)-1)
    z=current:getZ()
    self.ambientMovementArea={minX=minX,minY=minY,maxX=maxX,maxY=maxY,z=z}
    -- A leisure walk is a short change of spot. It must not choose the other
    -- side of a large territory or use a different floor just to pass time.
    minX,maxX=math.max(minX,current:getX()-6),math.min(maxX,current:getX()+6)
    minY,maxY=math.max(minY,current:getY()-6),math.min(maxY,current:getY()+6)
    local width,height=math.floor(maxX-minX+1),math.floor(maxY-minY+1)
    if width<1 or height<1 then return nil end
    ticks=tonumber(ticks) or 0
    -- Keep the indoor/yard preference for two minutes, staggered per resident.
    -- It is a preference: a blocked yard does not force repeated door attempts.
    local preferOutside=daylight and (math.floor(ticks/7200)+Controller.baseIdleJitter(self.id))%4==0
    local currentOutside=safeMethod(current,"getRoom",nil)==nil
    local best,bestScore=nil,-math.huge
    for _=1,24 do
        local square=cell:getGridSquare(minX+ZombRand(width),minY+ZombRand(height),z)
        local distance=square~=nil and navigationDistanceSquared(current,square) or math.huge
        local moving=safeMethod(square,"getMovingObjects",nil)
        local outside=safeMethod(square,"getRoom",nil)==nil
        local suitable=square~=nil and square:canStand() and distance>=4 and distance<=36
            and KnoxBaseManager.containsSquare(self.base,square)
            and moving~=nil and moving:size()==0 and (daylight or not outside)
        if suitable and self.lastAmbientOrigin~=nil and ticks<(self.lastAmbientOriginUntil or 0)
            and navigationDistanceSquared(square,self.lastAmbientOrigin)==0 then suitable=false end
        if suitable then
            -- Reuse perceived danger; no extra world/zombie scan per idle tile.
            for threat,memory in pairs(self.perceivedThreats or {}) do
                local threatSquare=safeMethod(threat,"getCurrentSquare",nil)
                if ticks-(memory.lastSeen or 0)<=THREAT_MEMORY_TICKS
                    and not safeMethod(threat,"isDead",true)
                    and navigationDistanceSquared(square,threatSquare)<=36 then suitable=false;break end
            end
        end
        if suitable then
            local score=(outside==preferOutside and 100 or 0)+(outside==currentOutside and 20 or 0)
                - math.abs(distance-16)
            if score>bestScore then best,bestScore=square,score end
        end
    end
    return best
end

function Controller:beginBaseMovement(ticks, returning)
    if not returning and ticks < (self.nextAmbientMoveAt or 0) then
        self.activeDecision, self.state = "base_idle", "BASE_IDLE"
        self.nextThink = ticks + 180
        return false
    end
    if not returning then self.nextAmbientMoveAt = ticks + 1800 end
    local target = self:findBaseMovementTarget(returning,ticks)
    if target == nil then
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    self.reservations = self.reservations or {}
    self.reservations.ambientSpots = self.reservations.ambientSpots or {}
    local spotKey = ambientSpotKey(target)
    if spotKey == nil or not reserve(
        self.reservations, "ambientSpots", spotKey, self.id
    ) then
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    self.ambientMovementTarget = spotKey
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        self:leaveRecoveryPosture()
    end
    local result
    if returning then
        result=tostring((moveWithTravelPace(self.bridge,self.id,self.character,target,"return_home")))
    else
        result=tostring(KnoxCompanionPatrol.move(self.bridge,self.id,target,self.ambientMovementArea))
    end
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        release(self.reservations, "ambientSpots",
            self.ambientMovementTarget, self.id)
        self.ambientMovementTarget = nil
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    if not returning then
        self.lastAmbientOrigin=self.character:getCurrentSquare()
        self.lastAmbientOriginUntil=ticks+7200
    end
    self.activeDecision = returning and "return_to_base" or "patrol_base"
    self.state = returning and "BASE_RETURN" or "BASE_PATROL"
    return true
end

function Controller:releaseAmbientMovement()
    if self.ambientMovementTarget ~= nil then
        self.reservations = self.reservations or {}
        self.reservations.ambientSpots = self.reservations.ambientSpots or {}
        release(self.reservations, "ambientSpots",
            self.ambientMovementTarget, self.id)
        self.ambientMovementTarget = nil
    end
end

-- Base patrol/return movement owns a transient ambient reservation.  A failed
-- native route must release it immediately, otherwise the failed tile remains
-- blocked for this resident's lifetime and other residents can never claim it.
function Controller:handleBaseMovementFailure(movement, ticks)
    if self.bridge ~= nil and self.bridge.cancelNpcMove ~= nil then
        self.bridge:cancelNpcMove(self.id)
    end
    self:releaseAmbientMovement()
    self:recordMovementFailure("base_movement", movement, ticks)
    self.activeDecision = "base_idle"
    self.state = "BASE_IDLE"
    self.nextThink = math.max(self.nextThink or 0, (ticks or 0) + THINK_MIN_TICKS)
    return true
end

-- A route that never reports an outcome still owns the same base-life choice
-- as an explicit native failure. Stop that route, release its furniture claim,
-- and use the existing real ground-rest fallback rather than abandoning rest.
function Controller:handleRestMovementFailure(movement, ticks)
    if self.bridge ~= nil and self.bridge.cancelNpcMove ~= nil then
        self.bridge:cancelNpcMove(self.id)
    end
    self:recordMovementFailure("rest_move", movement, ticks)
    self:startRecoveryPosture(ticks, false, self.ambientRest == true)
    return true
end

-- A native route can fail after the target was valid and loaded: a door can
-- change state, a streamed square can disappear, or the pathfinder can leave
-- the survivor on a bad side of an opening. Give a claimed physical task one
-- fresh target/route before blocking it. This is deliberately bounded; retrying
-- a corpse while it is attached would make the survivor drag forever, so the
-- drop phase remains fail-closed and releases the body through the existing
-- action failure path.
function Controller:retryBaseTaskMovement(ticks, movement)
    local task = self.baseTask
    if task == nil or self.baseTaskMoveRetryIssued == true then
        return false
    end
    if task.type == "haul_corpse" and self.baseTaskCorpsePhase == "drop" then
        return false
    end
    self.baseTaskMoveRetryIssued = true
    if self.bridge ~= nil and self.bridge.cancelNpcMove ~= nil then
        self.bridge:cancelNpcMove(self.id)
    end
    if task.type == "barricade" then
        self.baseTaskBarricadeTarget = nil
    elseif task.type == "haul_corpse" then
        self.baseTaskCorpseTarget = nil
        self.baseTaskCorpsePhase = "grab"
        self.baseTaskCorpseGrabVerifyUntil = nil
        self.baseTaskCorpseGrabRetryIssued = nil
    end
    self:recordMovementFailure(
        "base_task_move_retry",
        movement,
        ticks,
        30,
        240
    )
    local started = self:beginBaseTaskWorkMove(ticks)
    if not started and self.baseTask == nil then
        self:finishDecision(ticks)
    end
    return true
end

function Controller:clearBaseTaskRuntimeState()
    self:releaseBaseTaskSupplyTransfer()
    self.baseTask = nil
    self.baseTaskStartedAt = nil
    self.baseTaskSupplyTransfer = nil
    self.baseResupplyAttempts = 0
    self.baseTaskActionQueued = false
    self.baseTaskActionQueueTicks = nil
    self.baseTaskMoveRetryIssued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
end

-- Claimed job supplies are a short-lived runtime reservation. The timed
-- inventory action remains the only code that moves the real item, while this
-- lease stops two workers from walking toward the same hammer/plank/container.
function Controller:reserveBaseTaskSupplyTransfer(transfer)
    if transfer == nil or transfer.item == nil then return false end
    self.reservations = self.reservations or {}
    self.reservations.items = self.reservations.items or {}
    self.reservations.containers = self.reservations.containers or {}
    local container = transfer.source ~= nil and transfer.source.container or nil
    if not reserve(self.reservations, "items", transfer.item, self.id) then
        return false
    end
    if container ~= nil and not reserve(self.reservations, "containers", container, self.id) then
        release(self.reservations, "items", transfer.item, self.id)
        return false
    end
    self.baseTaskSupplyTransfer = transfer
    return true
end

function Controller:releaseBaseTaskSupplyTransfer()
    local transfer = self.baseTaskSupplyTransfer
    if transfer ~= nil then
        local reservations = self.reservations or {}
        reservations.items = reservations.items or {}
        reservations.containers = reservations.containers or {}
        release(reservations, "items", transfer.item, self.id)
        release(reservations, "containers",
            transfer.source ~= nil and transfer.source.container or nil, self.id)
    end
    self.baseTaskSupplyTransfer = nil
end

function Controller:finishBaseTask(succeeded, reason)
    self.securityRoute=nil
    self:releaseBaseCooking()
    local task = self.baseTask
    if task == nil then
        return false
    end
    local snapshot = self:diagTaskSnapshot(task)
    snapshot.reason = tostring(reason)
    local baseId = task.baseId or self.baseId
    local finished, result = KnoxBaseTaskBoard.finish(
        baseId,
        task.id,
        self.id,
        succeeded == true,
        reason
    )
    if finished == nil then
        -- The physical action may already have happened, but the authoritative
        -- task owner rejected this survivor's completion (for example after a
        -- duty/claim change). Keep that result distinct from task success.
        snapshot.ok = false
        snapshot.reason = tostring(reason) .. ":" .. tostring(result or "rejected")
        self:diag("jobs", "task_finish_rejected", snapshot)
        print("[KnoxSurvivors][BaseJobs] finish-failed id=" .. tostring(self.id)
            .. " task=" .. tostring(task.id) .. " result=" .. tostring(result))
        self:recordFailure("base_task_finish_rejected:" .. tostring(result or "unknown"),
            tonumber(self.currentTicks) or 0, BASE_TASK_ACTION_FAILURE_TICKS)
    else
        snapshot.ok = succeeded == true
        self:diag("jobs", succeeded == true and "task_finished_ok" or "task_finished_fail", snapshot)
    end
    -- RimWorld "anything" pacing: consecutive automatic successes earn one
    -- ambient leisure round so marathon work (endless cooking while the
    -- pantry is full) cannot crowd out company time. Manual player orders
    -- never accrue debt and reset the streak without forcing a break.
    if finished ~= nil and succeeded == true and task.auto == true and task.manual ~= true then
        local streak = (tonumber(self.consecutiveAutoTasks) or 0) + 1
        if streak >= 3 then
            self.consecutiveAutoTasks = 0
            self.leisureBreakDue = true
        else
            self.consecutiveAutoTasks = streak
        end
    elseif finished ~= nil and task.manual == true then
        self.consecutiveAutoTasks = 0
    end
    self:clearBaseTaskRuntimeState()
    return finished ~= nil
end

-- Native-action refusal or a stale work target at the work site. Records the
-- reason visibly and installs a retry delay so the same resident does not
-- reclaim-and-walk the same failing task on the next think.
function Controller:failBaseTaskAction(ticks, reason)
    if self.baseTask ~= nil and self.baseTask.type == "haul_corpse"
        and KnoxBaseCorpseHandling ~= nil and KnoxBaseCorpseHandling.isDragging ~= nil
        and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    local snapshot = self:diagTaskSnapshot(self.baseTask)
    snapshot.reason = tostring(reason)
    local pos = self:diagPos()
    if pos ~= nil then snapshot.charX, snapshot.charY = pos.x, pos.y end
    self:diag("jobs", "task_action_failed", snapshot)
    self:finishBaseTask(false, reason)
    self:recordFailure("base_task_action:" .. tostring(reason), ticks,
        BASE_TASK_ACTION_FAILURE_TICKS)
    self:finishDecision(ticks)
end

function Controller:abandonBaseTask(reason)
    self:releaseBaseCooking()
    if self.baseTask == nil then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.character ~= nil and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    local abandoned = self:finishBaseTask(false, reason or "interrupted")
    self.activeDecision = nil
    return abandoned
end

-- Combat and retreat are temporary preemptions, not task failures. Keep the
-- claimed task attached to this controller so the resident can resume it once
-- danger clears; the persisted claim is still recovered normally if the body
-- unloads or dies. Explicit cancellation, invalid targets, and real action
-- failures continue through abandonBaseTask/finishBaseTask as before.
function Controller:suspendBaseTaskForThreat(reason)
    local preserveBaseSupplyRun = self.baseId ~= nil
        and (self.baseSupplyTrip == true
            or self.baseSupplyOrder ~= nil
            or self.pendingBaseSupplyDeposit ~= nil)
    self.securityRoute=nil
    self:releaseBaseCooking()
    self:releaseAid()
    if self.character ~= nil then
        self:leaveRecoveryPosture()
    end
    if self.baseTask == nil then return false end
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseSupply(preserveBaseSupplyRun)
    self.baseTaskRetryAt = 0
    self.baseTaskStartedAt = nil
    self.baseTaskActionQueued = false
    self.baseTaskActionQueueTicks = nil
    if self.character ~= nil and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    self.baseTaskBarricadeTarget = nil
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    if self.baseTask ~= nil then
        self.baseTask.interruptedReason = tostring(reason or "threat")
    end
    return true
end

-- Long-running base work must periodically yield to the same urgent needs as
-- guard, patrol, and cooking. Keep the original persisted task claim attached;
-- its existing task owner resumes it after self-care succeeds. Native actions
-- are cancelled through the existing interruption owner, and supply transfers
-- release their exact item/container lease before self-care takes ownership.
function Controller:yieldBaseTaskForNeed(ticks)
    local state = self.state
    if self.baseTask == nil
        or (state ~= "BASE_TASK_MOVE" and state ~= "BASE_TASK_SUPPLY_MOVE"
            and state ~= "BASE_TASK_SUPPLY_WAIT" and state ~= "BASE_TASK_WORK"
            and state ~= "BASE_TASK_ACTION" and state ~= "BASE_TASK_SUPPLY_TRANSFER") then
        return false
    end
    if (state == "BASE_TASK_MOVE" or state == "BASE_TASK_SUPPLY_MOVE")
        and nativeTraversalBusy(self.character) then
        return false
    end
    if state == "BASE_TASK_WORK" then
        if self.baseTask.type == "guard" then return false end
        local started = self.baseTaskStartedAt or ticks
        if ticks - started >= KnoxBaseJobs.workDuration(self.baseTask) then
            return false
        end
    end
    if ticks < (self.nextBaseTaskNeedCheck or 0) then return false end
    self.nextBaseTaskNeedCheck = ticks + 90
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs == nil or needs.decide == nil then return false end
    local need = needs.decide(self.character, nil)
    if need == nil or need.kind == "roam"
        or not Controller.selfCareReady(self.selfCareRetryAt, need.kind, ticks) then
        return false
    end
    if state == "BASE_TASK_MOVE" or state == "BASE_TASK_SUPPLY_MOVE" then
        self.bridge:cancelNpcMove(self.id)
    end
    self:suspendBaseTaskForThreat("needs_interrupt")
    self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
    return true
end

function Controller:updateBaseSecurityDuty(ticks)
    local task = self.baseTask
    if task == nil or (task.type ~= "guard" and task.type ~= "patrol") then return end
    if ticks < (self.nextSecurityCheck or 0) then return end
    self.nextSecurityCheck = ticks + 90
    local target = task.target or {}
    local zoneId = target.autoZoneId or target.zoneId
    local zone = zoneId ~= nil and self.base ~= nil and self.base.zones ~= nil
        and self.base.zones[zoneId] or nil
    if task.state ~= "claimed" or task.claimedBy ~= self.id then
        self.bridge:cancelNpcMove(self.id)
        self.baseTask = nil
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    if zoneId ~= nil and (zone == nil or zone.enabled == false) then
        self:abandonBaseTask("security_area_released")
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    if decision ~= nil and decision.kind ~= "roam" then
        self:suspendBaseTaskForThreat("needs_interrupt")
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    if task.type == "guard" and self.state~="BASE_SECURITY_WAIT" then
        local post = KnoxBaseJobs.resolveTaskSquare(task, self.character)
        local current = self.character:getCurrentSquare()
        if post ~= nil and navigationDistanceSquared(current, post) > 2.25 then
            self:beginBaseTaskWorkMove(ticks)
        end
    end
end

function Controller:beginBaseTaskWorkMove(ticks)
    local task = canonicalBaseTask(self.baseTask)
    self.baseTask = task
    if task~=nil and (task.type=="guard" or task.type=="patrol") then
        return self:beginSecurityRoute(ticks,task,true)
    end
    local target = nil
    local targetReason = nil
    if task ~= nil and task.type == "barricade"
        and self.baseTaskBarricadeTarget ~= nil
        and KnoxBaseBarricades ~= nil
        and KnoxBaseBarricades.approachResolved ~= nil then
        target, targetReason = KnoxBaseBarricades.approachResolved(
            self.baseTaskBarricadeTarget,
            self.character
        )
        if target == nil and KnoxBaseBarricades.isTargetComplete ~= nil
            and KnoxBaseBarricades.isTargetComplete(self.base, task.target, self.character) then
            self:finishBaseTask(true, "barricade_already_secured")
            self:finishDecision(ticks)
            return true
        end
        if target == nil then
            target = self:retargetBarricadeTask()
            if target ~= nil then
                target, targetReason = KnoxBaseBarricades.approachResolved(target, self.character)
            end
        end
    elseif task ~= nil then
        target = KnoxBaseJobs.resolveTaskSquare(task, self.character)
        if target == nil and task.type == "barricade" and KnoxBaseBarricades ~= nil
            and KnoxBaseBarricades.isTargetComplete ~= nil
            and KnoxBaseBarricades.isTargetComplete(self.base, task.target, self.character) then
            self:finishBaseTask(true, "barricade_already_secured")
            self:finishDecision(ticks)
            return true
        end
    end
    if target == nil then
        local snapshot = self:diagTaskSnapshot(task)
        snapshot.reason = tostring(targetReason or "unresolved")
        local pos = self:diagPos()
        if pos ~= nil then snapshot.charX, snapshot.charY = pos.x, pos.y end
        self:diag("jobs", "task_move_no_square", snapshot)
        self:finishBaseTask(false, "no_loaded_work_square:" .. tostring(targetReason or "unresolved"))
        self:recordFailure("base_task_target", ticks, 180)
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        local snapshot = self:diagTaskSnapshot(task)
        snapshot.reason = tostring(moveResult)
        self:diag("jobs", "task_move_start_failed", snapshot)
        self:finishBaseTask(false, "task_move_start_failed:" .. moveResult)
        self:recordMovementFailure("base_task_move", moveResult, ticks)
        return false
    end
    self.baseTaskStartedAt = nil
    self:noteTaskTravelStart(ticks)
    self.activeDecision = "base_task_" .. tostring(task.type)
    self.state = "BASE_TASK_MOVE"
    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
        .. " task=" .. tostring(task.id) .. " type=" .. tostring(task.type)
        .. " target=" .. tostring(target:getX()) .. "," .. tostring(target:getY()))
    return true
end

-- Ignore-mode still fetches real stored items first: gating is bypassed,
-- but native actions need carried hammers, planks, seeds and water. Returns
-- a fetch transfer, or nil when storage has nothing left to give (the worker
-- then walks over and the native action fails closed).
function Controller:fetchStoredTaskSupplies()
    local settings = rawget(_G, "KnoxSettings")
    if settings == nil or settings.ignoreJobResourceRequirements == nil
        or not settings.ignoreJobResourceRequirements() then
        return nil
    end
    if KnoxBaseStorage == nil or KnoxBaseStorage.findFetchTransfer == nil then
        return nil
    end
    return KnoxBaseStorage.findFetchTransfer(
        self.base,
        self.character,
        self.baseTask ~= nil and self.baseTask.requirements or nil
    )
end

-- Requirement lookup for a claimed task: normal gated transfer first, then an
-- ignore-mode real fetch so workers carry stored materials to the work site.
function Controller:findTaskSupplyTransfer()
    local transfer, result = KnoxBaseStorage.findRequiredTransfer(
        self.base,
        self.character,
        self.baseTask ~= nil and self.baseTask.requirements or nil
    )
    if transfer == nil and result == "requirements_ready" then
        transfer = self:fetchStoredTaskSupplies()
    end
    return transfer, result
end

-- Cheap claim-time gate: re-resolve the work target before fetching supplies
-- or walking. A window barricaded by the player, a harvested plant, or a
-- hauled corpse between queue and claim used to send the resident walking to
-- every stale site before failing at the native action.
function Controller:validateBaseTaskTarget(ticks)
    local task = self.baseTask
    if task == nil then return true end
    local kind = tostring(task.type or "")
    local resolved, reason = nil, "unsupported_base_action"
    if kind == "barricade" and KnoxBaseBarricades ~= nil
        and KnoxBaseBarricades.resolveTarget ~= nil then
        resolved, reason = KnoxBaseBarricades.resolveTarget(self.base, task.target, self.character)
    elseif (kind == "farm_water" or kind == "farm_harvest" or kind == "farm_plow"
        or kind == "farm_seed") and KnoxBaseFarming ~= nil
        and KnoxBaseFarming.resolveTarget ~= nil then
        resolved, reason = KnoxBaseFarming.resolveTarget(self.base, task.target, self.character)
    elseif kind == "repair" and KnoxBaseRepairs ~= nil
        and KnoxBaseRepairs.resolveTarget ~= nil then
        resolved, reason = KnoxBaseRepairs.resolveTarget(self.base, task.target, self.character)
    elseif (kind == "chop_tree" or kind == "saw_logs") and KnoxBaseWoodcutting ~= nil
        and KnoxBaseWoodcutting.resolveTarget ~= nil then
        resolved, reason = KnoxBaseWoodcutting.resolveTarget(self.base, task.target, self.character)
    elseif kind == "haul_corpse" and KnoxBaseCorpseHandling ~= nil
        and KnoxBaseCorpseHandling.resolveTarget ~= nil then
        resolved, reason = KnoxBaseCorpseHandling.resolveTarget(self.base, task.target, self.character)
    else
        return true
    end
    if resolved ~= nil then
        if kind == "barricade" then
            self.baseTaskBarricadeTarget = resolved
        end
        return true
    end
    if kind == "barricade" and KnoxBaseBarricades ~= nil
        and KnoxBaseBarricades.isTargetComplete ~= nil
        and KnoxBaseBarricades.isTargetComplete(self.base, task.target, self.character) then
        self:finishBaseTask(true, "barricade_already_secured")
        self:finishDecision(ticks)
        return false
    end
    self:finishBaseTask(false, kind .. "_target_stale:" .. tostring(reason))
    self:recordFailure("base_task_stale:" .. kind, ticks, BASE_TASK_ACTION_FAILURE_TICKS)
    self:finishDecision(ticks)
    return false
end

-- A resident first gathers one required item at a time from assigned, currently
-- loaded base storage.  The actual move remains a normal inventory transfer;
-- missing or streamed-out material blocks the task instead of inventing stock.
-- Ignore mode skips the fetch trips: real engine-minted items go straight
-- into the worker's pockets, and the native timed actions still validate,
-- animate, and consume them normally.
function Controller:beginBaseTaskSupplyOrWork(ticks)
    local settings = rawget(_G, "KnoxSettings")
    local ignore = settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() == true
    if self.baseTask ~= nil and self.baseTask.type == "cook" then
        if self:beginBaseCooking(ticks,self.baseTask.target,false) then return true end
        self:finishBaseTask(false,"cooking_start_unavailable")
        self:recordFailure("base_task_action:cook:cooking_start_unavailable", ticks,
            BASE_TASK_ACTION_FAILURE_TICKS)
        return false
    end
    if not self:validateBaseTaskTarget(ticks) then return true end
    if ignore and rawget(_G, "KnoxJobTestSupplies") ~= nil
        and KnoxJobTestSupplies.topUp ~= nil then
        local ok, added, supplyResult = pcall(function()
            return KnoxJobTestSupplies.topUp(
                self.character,
                self.baseTask ~= nil and self.baseTask.requirements or nil
            )
        end)
        if not ok or supplyResult ~= "topped_up" then
            local reason = "free_job_supplies:" .. tostring(ok and supplyResult or added)
            self:finishBaseTask(false, reason)
            self:recordFailure(reason, ticks, BASE_TASK_ACTION_FAILURE_TICKS)
            KnoxActivityFeed.event("Base job blocked: " .. reason .. ".")
            self:finishDecision(ticks)
            return true
        end
        return self:beginBaseTaskWorkMove(ticks)
    end
    local transfer, result = self:findTaskSupplyTransfer()
    if transfer == nil then
        if result == "requirements_ready" then
            return self:beginBaseTaskWorkMove(ticks)
        end
        if self:beginBaseResourceRun(ticks, tostring(result)) then
            return true
        end
        if (self.baseResupplyAttempts or 0) < 3 then
            self.baseTaskRetryAt = ticks + SUPPLY_RETRY_TICKS
            self.activeDecision = "base_task_supply_wait"
            self.state = "BASE_TASK_SUPPLY_WAIT"
            self.nextThink = self.baseTaskRetryAt
            return true
        end
        self:finishBaseTask(false, tostring(result))
        KnoxActivityFeed.speak(self.character, "We're missing supplies for that job.")
        KnoxActivityFeed.event("Base job blocked: " .. tostring(result) .. ".")
        self:recordFailure("base_task_supply:" .. tostring(result), ticks, 300)
        return false
    end
    local approach = KnoxBaseStorage.approachSquare(transfer, self.character)
    if approach == nil then
        self:finishBaseTask(false, "storage_approach_unavailable")
        self:recordFailure("base_task_supply:storage_approach_unavailable", ticks, 300)
        return false
    end
    if not self:reserveBaseTaskSupplyTransfer(transfer) then
        -- Another job owns this exact real item/container. Keep this task's
        -- durable claim briefly and retry instead of racing the transfer or
        -- marking a genuine shared cupboard shortage as a failed barricade.
        self.baseTaskRetryAt = ticks + 60
        self.activeDecision = "base_task_supply_wait"
        self.state = "BASE_TASK_SUPPLY_WAIT"
        self.nextThink = self.baseTaskRetryAt
        return true
    end
    -- Keep the exact real-storage approach with this runtime lease so an
    -- alternate-entry detour resumes the same pickup route, rather than
    -- choosing a different tile after crossing a window.
    self.baseTaskSupplyTransfer.approach = approach
    local moveResult = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        self:releaseBaseTaskSupplyTransfer()
        self:finishBaseTask(false, "storage_move_start_failed:" .. moveResult)
        self:recordMovementFailure("base_task_supply_move", moveResult, ticks, 300)
        return false
    end
    self.baseTaskStartedAt = nil
    self:noteTaskTravelStart(ticks)
    self.activeDecision = "base_task_collect_supplies"
    self.state = "BASE_TASK_SUPPLY_MOVE"
    return true
end

-- A blocked base task must not become a generic world scavenging mission.
-- Supplies for a claimed base job come from the assigned central storage; if
-- they are absent, keep the claim briefly and let the normal retry window give
-- the player or another worker time to stock it.  Sending the worker to the
-- nearest matching container was a major source of apparently random trips,
-- especially when a tool or part was missing from the cupboard.
function Controller:beginBaseResourceRun(ticks, reason)
    local task = self.baseTask
    if task == nil or self.base == nil or (self.baseResupplyAttempts or 0) >= 3 then
        return false
    end
    self.baseResupplyAttempts = (self.baseResupplyAttempts or 0) + 1
    self.baseTaskRetryAt = ticks + SUPPLY_RETRY_TICKS
    self.activeDecision = "base_task_supply_wait"
    self.state = "BASE_TASK_SUPPLY_WAIT"
    self.nextThink = self.baseTaskRetryAt
    if ticks >= (self.nextSupplySpeech or 0) then
        KnoxActivityFeed.speak(self.character, "I need the supplies brought to the base cupboard first.")
        self.nextSupplySpeech = ticks + 3600
    end
    return true
end

-- Window object indexes can change after the square is streamed or another
-- worker secures the original opening. Keep the claimed barricade task useful
-- by selecting another valid window in the same base instead of abandoning
-- the whole job loop on a stale target.
function Controller:retargetBarricadeTask()
    if self.base == nil or self.baseTask == nil
        or self.baseTask.type ~= "barricade"
        or KnoxBaseBarricades == nil
        or KnoxBaseBarricades.findTarget == nil then
        return nil
    end
    local oldId = self.baseTask.target ~= nil and self.baseTask.target.id or nil
    local replacement = KnoxBaseBarricades.findTarget(
        self.base,
        self.character,
        function(candidate)
            if oldId ~= nil and candidate.id == oldId then return false end
            for otherId, other in pairs(self.base.tasks or {}) do
                if otherId ~= self.baseTask.id and other ~= nil
                    and other.type == "barricade"
                    and (other.state == "queued" or other.state == "claimed")
                    and other.target ~= nil and other.target.id == candidate.id then
                    return false
                end
            end
            return true
        end
    )
    if replacement == nil then return nil end
    local saved, result = KnoxPersistence.retargetClaimedBaseTask(
        self.base.id, self.baseTask.id, self.id, replacement
    )
    if saved == nil then
        print("[KnoxSurvivors][BaseJobs] barricade-retarget-rejected id="
            .. tostring(self.id) .. " result=" .. tostring(result))
        return nil
    end
    self.baseTask = saved
    local resolved = KnoxBaseBarricades.resolveTarget(
        self.base, replacement, self.character
    )
    self.baseTaskBarricadeTarget = resolved
    return resolved
end

function Controller:continueBaseResourceRun(ticks, succeeded)
    self:releaseSupply()
    if not succeeded then
        self.baseResupplyAttempts = (self.baseResupplyAttempts or 0) + 1
    end
    if self.baseTask == nil then
        self:finishDecision(ticks)
        return false
    end
    if (self.baseResupplyAttempts or 0) >= 3 then
        self:finishBaseTask(false, "missing_required_materials_after_search")
        KnoxActivityFeed.speak(self.character, "I couldn't find the supplies for that job.")
        self:finishDecision(ticks)
        return false
    end
    if self:beginBaseTaskSupplyOrWork(ticks) then return true end
    self:finishDecision(ticks)
    return false
end

-- Resume the same duty after danger, or chain work while already in a work
-- area. Pending deliveries and explicit supply orders retain their home trip.
function Controller:resumeExternalBaseWork(ticks)
    if self.pendingBaseSupplyDeposit ~= nil or self.baseSupplyOrder ~= nil then return false end
    local claimed = self.baseTask
    if claimed == nil and KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil then
        claimed = KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, self.baseId)
    end
    if claimed == nil and (KnoxBaseJobs.containsWorkSquare == nil
        or not KnoxBaseJobs.containsWorkSquare(self.base, self.character:getCurrentSquare())) then
        return false
    end
    if self:beginBaseTask(ticks) then return true end
    -- A failed start may install a retry deadline. Do not replace that recovery
    -- with a fresh home route in the very same decision.
    return (self.nextThink or 0) > ticks
end

function Controller:claimQueuedManualOrderTask()
    if self.baseTask ~= nil or self.base == nil or self.baseId == nil
        or KnoxBaseTaskBoard == nil
        or KnoxBaseTaskBoard.claimBestManualOrder == nil then
        return false
    end
    local ordered = KnoxBaseTaskBoard.claimBestManualOrder(self.baseId, self.id)
    if ordered == nil then return false end
    self.baseTask = canonicalBaseTask(ordered)
    self.baseTask.baseId = self.baseId
    self.baseTask.manual = true
    self.baseTaskRetryAt = 0
    self.baseTaskMoveRetryIssued = false
    self.baseResupplyAttempts = 0
    return true
end

function Controller:beginBaseTask(ticks)
    if self.base == nil or self.baseId == nil
        or self.base.settings == nil
        then
        return false
    end
    -- Work, sleep and explicit rest all preempt the television immediately.
    self:releaseWatch()
    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
    local profile = KnoxPersistence.getSurvivorCapabilities(self.id) or {}
    local preference = KnoxBaseJobs.effectivePreference ~= nil
        and KnoxBaseJobs.effectivePreference(duty, profile)
        or duty.jobPreference
    -- Restore an existing claim before evaluating Rest. Explicit player
    -- assignments carry `manual=true` and remain authoritative; automatic
    -- claims are still released when the resident is intentionally rested.
    if self.baseTask == nil then
        local restored = KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
            and KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, self.baseId) or nil
        if restored ~= nil then
            self.baseTask = canonicalBaseTask(restored)
            self.baseTask.baseId = self.baseId
            -- The resident is loaded again, so the physical task has a fresh
            -- opportunity to run natively. Do not carry an old streamed-out
            -- wait budget into the next unload cycle.
            self.baseTask.offscreenWaitHours = 0
            self.baseResupplyAttempts = 0
            self.baseTaskRetryAt = 0
            self.baseTaskMoveRetryIssued = false
        end
    end
    -- Continue per-target work created by an explicit player order through the
    -- existing task board even when autonomous job election is disabled. This
    -- point is reached only after higher-priority arbitration has admitted
    -- base work, and matches the priority of an already-claimed manual task.
    if self.baseTask == nil then self:claimQueuedManualOrderTask() end
    -- Duty schedule windows bypass selection exactly like explicit rest:
    -- sleep and recreation release any automatic claim and yield to ambient
    -- life; work defers to the preference machinery below; patrol and guard
    -- bias election toward watch tasks through that same machinery (with
    -- ordinary fallback when no watch task is queued). Manual player
    -- assignments always survive the window flip.
    local assignment = KnoxBaseJobs.scheduleAssignment ~= nil
        and KnoxBaseJobs.scheduleAssignment(self.id) or "anything"
    if assignment ~= self.lastScheduleAssignment then
        self.lastScheduleAssignment = assignment
        self:diag("jobs", "scheduled_assignment", { assignment = tostring(assignment) })
    end
    if assignment == "patrol" or assignment == "guard" then
        preference = assignment
    end
    local scheduledRest = (assignment == "sleep" or assignment == "recreation")
        and not (self.baseTask ~= nil and self.baseTask.manual == true)
    if preference == "rest" and not (self.baseTask ~= nil and self.baseTask.manual == true)
        or scheduledRest then
        if self.baseTask ~= nil then
            self:releaseSupply()
            self:interruptForDirective()
            self.baseTask = nil
        end
        -- A resident can be switched to Rest while a persisted task claim is
        -- still present (for example after a menu change or a reload).  Do
        -- not merely drop the loaded pointer: that would leave the task
        -- permanently owned by a resting survivor.  Requeue the claim through
        -- the existing persistence boundary so another resident can perform
        -- it and the original task identity/requirements remain intact.
        local requeueRestTask = KnoxPersistence.requeueAutomaticBaseTasksForSurvivor
            or KnoxPersistence.requeueBaseTasksForSurvivor
        if requeueRestTask ~= nil then
            requeueRestTask(
                self.id,
                self.baseId,
                "resident_requested_rest"
            )
        end
        self.activeDecision = "base_recover"
        return false
    end
    if self.baseTask ~= nil then
        if ticks >= (self.baseTaskRetryAt or 0) then
            return self:beginBaseTaskSupplyOrWork(ticks)
        end
        -- A claimed task can survive a threat, failed supply transfer, or
        -- streamed-out target with a future retry deadline. Keep the state
        -- explicit while waiting; returning true from the old path without
        -- changing state left the controller free to re-enter decision logic
        -- against the same deferred task.
        self.activeDecision = "base_task_supply_wait"
        self.state = "BASE_TASK_SUPPLY_WAIT"
        self.nextThink = self.baseTaskRetryAt
        return true
    end
    -- Automatic scheduling is optional, but it must not block a task the
    -- player explicitly assigned through the Notebook. At this point there is
    -- no restored/active claim, so only automatic selection should be gated.
    if self.base.settings.automaticJobs == false then
        return false
    end
    local task, result = KnoxBaseJobs.ensureAutomaticTask(
        self.base,
        self.character,
        self.id,
        preference
    )
    if task == nil then
        return false
    end
    if task.state == "queued" then
        task.baseId = self.baseId
        local eligible, eligibilityResult = KnoxBaseManager.canPerformTask(
            self.id,
            self.baseId,
            task
        )
        if not eligible then
            return false
        end
        task, result = KnoxPersistence.claimBaseTask(
            self.baseId,
            task.id,
            self.id,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
    elseif task.state ~= "claimed" or task.claimedBy ~= self.id then
        return false
    end
    if task == nil then
        return false
    end
    self.baseTask = canonicalBaseTask(task)
    task.baseId = self.baseId
    task.offscreenWaitHours = 0
    self.baseTaskMoveRetryIssued = false
    sayDialogue(self.character, self.id, "base_work", ticks, 2400)
    return self:beginBaseTaskSupplyOrWork(ticks)
end

-- A resident with no executable base task may still be useful outside the
-- property when shared stores are genuinely short on essentials. Keep this a
-- small bridge into the existing real-item search rather than creating a
-- second mission system: the survivor searches nearby containers, takes only
-- an actual matching item, and returns to the same persisted base duty.
-- Player-owned residents require the existing per-resident player opt-in.
-- Faction residents answer their own settlement shortages through this same
-- pipeline when their persisted affiliation matches the faction base.
function Controller:baseSupplyNeed(ticks)
    if self.base == nil or self.baseId == nil
        or ticks < (self.nextBaseSupplySearch or 0) then
        return nil
    end
    if KnoxBaseStorage == nil or KnoxBaseStorage.summarize == nil then
        return nil
    end
    local success, summary = pcall(function()
        return KnoxBaseStorage.summarize(self.base)
    end)
    if not success or type(summary) ~= "table" then
        self.nextBaseSupplySearch = ticks + SUPPLY_RETRY_TICKS
        return nil
    end
    local totals = summary.totals or {}
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(self.baseId) or {}
    local residents = math.max(1, type(residentIds) == "table" and #residentIds or 1)
    local nowHours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    -- Remove a development-era persisted copy if this base came from an older
    -- save. Loaded lease ownership lives only in `baseSupplyClaimsByBase`.
    self.base.supplySearchClaims = nil
    local claims = supplyClaimsFor(self.baseId)
    if claims == nil then return nil end
    -- Supply trips are shared settlement work. A lease covers an uncommitted
    -- election, but once the run is persisted it remains the owner until its
    -- existing terminal path clears activeSupplyRun. Rebuild that transient
    -- lease before allowing a second resident to answer the same shortage;
    -- unloaded residents still own their persisted runs.
    for kind, claim in pairs(claims) do
        local claimantDuty = type(claim) == "table"
            and KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(claim.survivorId) or nil
        local durableKind = Controller.activeBaseSupplyRun(
            claimantDuty, self.baseId,
            type(claim) == "table" and claim.survivorId or nil
        )
        local claimantStillBelongs = claimantDuty ~= nil
            and claimantDuty.mode == "base"
            and tostring(claimantDuty.baseId or "") == tostring(self.baseId or "")
            and claimantDuty.eventId == nil
            and (KnoxPersistence.isSurvivorPresent == nil
                or KnoxPersistence.isSurvivorPresent(claim.survivorId))
            and (KnoxPersistence.getAwayTeamForSurvivor == nil
                or KnoxPersistence.getAwayTeamForSurvivor(claim.survivorId) == nil)
            and (KnoxPersistence.isSurvivorAlive == nil
                or KnoxPersistence.isSurvivorAlive(claim.survivorId))
        if type(claim) ~= "table" or not claimantStillBelongs then
            claims[kind] = nil
        elseif durableKind == kind then
            claim.untilHours = nowHours + 1.5
            claim.durable = true
        elseif claim.durable == true or (tonumber(claim.untilHours) or 0) <= nowHours then
            claims[kind] = nil
        end
    end
    -- The in-memory lease table can be empty after load, or an old lease can
    -- expire while its persisted trip is still searching/returning. Restore
    -- active runs from the existing duty owner before shortage election.
    if KnoxPersistence.getSurvivorDuty ~= nil then
        for _, residentId in ipairs(residentIds) do
            local duty = KnoxPersistence.getSurvivorDuty(residentId)
            local kind = Controller.activeBaseSupplyRun(duty, self.baseId, residentId)
            if kind ~= nil then
                local claim = claims[kind]
                if type(claim) ~= "table" or claim.durable ~= true
                    or claim.survivorId == residentId then
                    claims[kind] = {
                        survivorId = residentId,
                        untilHours = nowHours + 1.5,
                        durable = true,
                    }
                end
            end
        end
    end
    local goal = nil
    if KnoxBaseSupplyPlanner.chooseAvailableShortage ~= nil then
        goal = KnoxBaseSupplyPlanner.chooseAvailableShortage(
            totals, residents, claims, self.id
        )
    elseif KnoxBaseSupplyPlanner.chooseShortage ~= nil then
        goal = KnoxBaseSupplyPlanner.chooseShortage(totals, residents)
    end
    if goal ~= nil then
        local claim = claims[goal]
        if claim ~= nil and claim.survivorId ~= self.id then
            self.nextBaseSupplySearch = ticks + 600
            return nil
        end
        if claim == nil and KnoxBaseSupplyPlanner.chooseWorker ~= nil
            and KnoxSurvivorRuntime ~= nil then
            local candidates = {}
            for _, residentId in ipairs(residentIds) do
                local duty = KnoxPersistence.getSurvivorDuty ~= nil
                    and KnoxPersistence.getSurvivorDuty(residentId) or nil
                local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
                    and KnoxPersistence.getSurvivorAffiliation(residentId) or nil
                local character = KnoxSurvivorRuntime.getCharacter ~= nil
                    and KnoxSurvivorRuntime.getCharacter(residentId) or nil
                local snapshot = KnoxSurvivorRuntime.snapshot ~= nil
                    and KnoxSurvivorRuntime.snapshot(residentId) or nil
                local square = character ~= nil and character:getCurrentSquare() or nil
                local state = snapshot ~= nil and tostring(snapshot.state or "") or ""
                local claimedTask = duty ~= nil
                    and KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
                    and KnoxPersistence.getClaimedBaseTaskForSurvivor(
                        residentId, self.baseId
                    ) or nil
                local groupScavenge = rawget(_G, "KnoxGroupScavenge")
                local groupLeaseClear = true
                if groupScavenge ~= nil and groupScavenge.ownsSurvivor ~= nil then
                    local ok, owns = pcall(groupScavenge.ownsSurvivor, residentId)
                    groupLeaseClear = ok and owns ~= true
                end
                local factionBaseId = self.base.ownerKind == "faction"
                    and tostring(self.base.ownerId or "") or ""
                local factionResident = factionBaseId ~= ""
                    and affiliation ~= nil and affiliation.kind == "faction"
                    and tostring(affiliation.factionId or "") == factionBaseId
                    and (duty == nil or duty.jobPreference == nil
                        or duty.jobPreference == "auto")
                candidates[#candidates + 1] = {
                    id = residentId,
                    ready = duty ~= nil and duty.mode == "base"
                        and tostring(duty.baseId or "") == tostring(self.baseId or "")
                        and duty.eventId == nil
                        and (KnoxPersistence.isSurvivorPresent == nil
                            or KnoxPersistence.isSurvivorPresent(residentId))
                        and (KnoxPersistence.getAwayTeamForSurvivor == nil
                            or KnoxPersistence.getAwayTeamForSurvivor(residentId) == nil)
                        and snapshot ~= nil and snapshot.loaded == true
                        and (state == "IDLE" or state == "BASE_IDLE")
                        and square ~= nil
                        and groupLeaseClear
                        and KnoxBaseManager.containsSquare(self.base, square),
                    willing = duty ~= nil and (duty.allowLootRuns == true
                        or factionResident),
                    resting = duty ~= nil and duty.jobPreference == "rest",
                    hasTask = claimedTask ~= nil,
                    explicitOrder = duty ~= nil
                        and type(duty.baseSupplyOrder) == "table",
                    lastSupplyRunAtHours = duty ~= nil
                        and duty.lastSupplyRunAtHours or nil,
                    lastSupplyKind = duty ~= nil and duty.lastSupplyKind or nil,
                }
            end
            local selected = KnoxBaseSupplyPlanner.chooseWorker(candidates, goal)
            if selected ~= self.id then
                self.nextBaseSupplySearch = ticks + 600
                return nil
            end
        end
        claims[goal] = {
            survivorId = self.id,
            untilHours = nowHours + 1.5,
            durable = false,
        }
        self.baseSupplyTrip = true
        self.baseSupplyKind = goal
        if KnoxPersistence.recordBaseSupplyRun ~= nil then
            KnoxPersistence.recordBaseSupplyRun(
                self.id, self.baseId, goal, "selected", nowHours
            )
        end
    else
        -- Once the stores are healthy, let another shortage claim immediately
        -- instead of waiting for the previous worker's lease to expire.
        for kind, claim in pairs(claims) do
            if type(claim) == "table" and claim.survivorId == self.id then
                claims[kind] = nil
            end
        end
    end
    self.nextBaseSupplySearch = ticks + (goal ~= nil and 1800 or 600)
    return goal
end

function Controller:releaseBaseSupplyClaim(kind)
    local claims = supplyClaimsFor(self.baseId)
    local claim = type(claims) == "table" and claims[kind] or nil
    if type(claim) == "table" and claim.survivorId == self.id then
        claims[kind] = nil
        return true
    end
    return false
end

function Controller:beginBaseSupplyRun(kind)
    self.baseSupplyTrip = true
    self.baseSupplyKind = kind
    if KnoxPersistence.beginBaseSupplyRun ~= nil then
        return KnoxPersistence.beginBaseSupplyRun(
            self.id, self.baseId, kind, currentWorldAgeHours()
        )
    end
    return true
end

function Controller:finishBaseSupplyRun(outcome)
    local kind = self.baseSupplyKind
        or (self.baseSupplyOrder ~= nil and self.baseSupplyOrder.kind or nil)
    if kind == nil then return false end
    self:releaseBaseSupplyClaim(kind)
    local saved = KnoxPersistence.finishBaseSupplyRun ~= nil
        and KnoxPersistence.finishBaseSupplyRun(
            self.id, self.baseId, kind, outcome, currentWorldAgeHours()
        ) or false
    self.baseSupplyTrip = nil
    self.baseSupplyKind = nil
    return saved
end

-- Finding a real item is progress, not completion. Keep the shared and durable
-- shortage ownership while that item is carried home so another resident does
-- not launch a duplicate run before the typed-storage transfer is confirmed.
function Controller:handoffBaseSupplyDelivery(item)
    if item == nil or self.baseSupplyTrip ~= true or self.baseSupplyKind == nil then
        return false
    end
    self.pendingBaseSupplyDeposit = { item = item }
    local ok, itemType = pcall(function() return item:getFullType() end)
    if ok and type(itemType) == "string" and itemType ~= "" then
        self:setLifeIntent("base_supply_deposit", "returning", nil, itemType)
    end
    if KnoxPersistence ~= nil and KnoxPersistence.recordBaseSupplyRun ~= nil then
        KnoxPersistence.recordBaseSupplyRun(
            self.id, self.baseId, self.baseSupplyKind, "collected_returning",
            currentWorldAgeHours()
        )
    end
    self:releaseSupply(true)
    return true
end

function Controller:clearExplicitBaseSupplyOrder()
    if self.baseSupplyOrder == nil then return false end
    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
    local cleared = KnoxPersistence.clearBaseSupplyOrder ~= nil
        and KnoxPersistence.clearBaseSupplyOrder(
            self.id, duty.ownerId, self.baseId, currentWorldAgeHours()
        ) or false
    if cleared then
        self.baseSupplyOrder = nil
        self.baseSupplyOrderAttempts = 0
    end
    return cleared
end

function Controller:recordExplicitBaseSupplyFailure(ticks)
    if self.baseSupplyOrder == nil then return false end
    local attempts = KnoxPersistence.recordBaseSupplyOrderAttempt ~= nil
        and KnoxPersistence.recordBaseSupplyOrderAttempt(
            self.id, self.baseId, currentWorldAgeHours()
        ) or nil
    self.baseSupplyOrderAttempts = tonumber(attempts)
        or ((tonumber(self.baseSupplyOrderAttempts) or 0) + 1)
    if self.baseSupplyOrderAttempts < 3 then
        self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        return false
    end
    self:clearExplicitBaseSupplyOrder()
    self.baseSupplyTrip = nil
    self:clearLifeIntent()
    sayDialogue(self.character, self.id, "base_supply_failed", ticks, 2400)
    return true
end

function Controller:releaseSupply(preserveBaseSupplyRun)
    self:releaseBaseRecreation()
    -- A base-task pickup may be interrupted through the generic supply/need
    -- path before it reaches the timed transfer state. Release its exact
    -- source lease here too; this is deliberately idempotent with task and
    -- controller cleanup.
    self:releaseBaseTaskSupplyTransfer()
    if self.pendingSupply ~= nil then
        release(self.reservations, "items", self.pendingSupply.item, self.id)
        release(self.reservations, "waterSources", self.pendingSupply.waterSource, self.id)
        for _, candidate in ipairs(self.pendingSupply.items or {}) do
            release(self.reservations, "items", candidate.item, self.id)
        end
        release(self.reservations, "containers", self.pendingSupply.container, self.id)
        self.pendingSupply = nil
    end
    if preserveBaseSupplyRun ~= true then
        self.baseSupplyTrip = nil
        self.baseSupplyKind = nil
    end
    self.entryDetour = nil
    self.windowResumeRetryUntil = nil
end

-- Generic exploration plans are advisory until every selected native item
-- transfer is visible in the survivor's real inventory. Special owners
-- (needs, party support, base resupply, and away teams) verify their own
-- receipts and deliberately do not use this generic completion gate.
function Controller:verifyGenericLootReceipt()
    local pending = self.pendingSupply
    if pending == nil or pending.items == nil or #pending.items == 0 then
        return false, 0, 0
    end
    local inventory = self.character ~= nil and self.character.getInventory ~= nil
        and self.character:getInventory() or nil
    if inventory == nil or inventory.contains == nil then
        return false, 0, #pending.items
    end
    local received = 0
    for _, candidate in ipairs(pending.items) do
        local item = candidate ~= nil and candidate.item or nil
        local ok, present = pcall(function() return item ~= nil and inventory:contains(item) end)
        if ok and present == true then received = received + 1 end
    end
    return received == #pending.items, received, #pending.items
end

function Controller:rejectUnreceivedGenericLoot(ticks, receivedCount, selectedCount)
    local container = self.pendingSupply ~= nil and self.pendingSupply.container or nil
    if container ~= nil then
        self.inspectedContainers[container] = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
    end
    self:recordFailure(
        receivedCount > 0 and "loot_transfer_partial_receipt"
            or "loot_transfer_not_received",
        ticks,
        LOOT_TRAVEL_COOLDOWN_TICKS
    )
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " loot-receipt-incomplete=" .. tostring(self.activeDecision)
            .. " received=" .. tostring(receivedCount)
            .. "/" .. tostring(selectedCount)
    )
    self:releaseSupply()
    self:finishDecision(ticks)
end

function Controller:releaseGroupSupport()
    local plan = self.pendingGroupSupport
    if plan ~= nil then
        release(self.reservations, "supportRecipients", plan.recipient, self.id)
        release(self.reservations, "supportItems", plan.item, self.id)
    end
    self.pendingGroupSupport = nil
end

function Controller:beginGroupSupport(ticks)
    if ticks < (self.nextGroupSupportAt or 0) or self.companionOrder ~= nil
        or self.baseId ~= nil or self.campId ~= nil
        or (self.groupLeader == nil and #(self.groupMembers or {}) <= 1)
        or not self.character:getCharacterActions():isEmpty() then
        return false
    end
    self.reservations.supportRecipients = self.reservations.supportRecipients or {}
    self.reservations.supportItems = self.reservations.supportItems or {}
    local recipients = {}
    if self.groupLeader ~= nil then recipients[#recipients + 1] = self.groupLeader end
    for _, member in ipairs(self.groupMembers or {}) do
        recipients[#recipients + 1] = member
    end
    local plan = KnoxGroupSupport.plan(
        self.character,
        recipients,
        self.reservations.supportRecipients,
        self.reservations.supportItems
    )
    if plan == nil
        or not reserve(self.reservations, "supportRecipients", plan.recipient, self.id)
        or not reserve(self.reservations, "supportItems", plan.item, self.id) then
        if plan ~= nil then
            release(self.reservations, "supportRecipients", plan.recipient, self.id)
        end
        self.nextGroupSupportAt = ticks + Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS
        return false
    end
    local action, result = KnoxGroupSupport.queue(self.character, plan)
    if action == nil then
        release(self.reservations, "supportRecipients", plan.recipient, self.id)
        release(self.reservations, "supportItems", plan.item, self.id)
        self.nextGroupSupportAt = ticks + Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS
        self:recordFailure("group_support:" .. tostring(result), ticks,
            Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS)
        return false
    end
    self.pendingGroupSupport = plan
    self.activeDecision = "share_" .. tostring(plan.kind)
    self.state = "GROUP_SUPPORT"
    self.stateStartedAt = ticks
    self.nextGroupSupportAt = ticks + Controller.TUNING.GROUP_SUPPORT_COOLDOWN_TICKS
    sayDialogue(self.character, self.id, "share_supply", ticks, 1800)
    return true
end

function Controller:completeGroupSupport(ticks)
    local plan = self.pendingGroupSupport
    local completed = KnoxGroupSupport.verify(plan)
    if not completed then
        self.nextGroupSupportAt = ticks + Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS
        self:recordFailure("group_support_no_transfer", ticks,
            Controller.TUNING.GROUP_SUPPORT_RETRY_TICKS)
    else
        self:diag("social", "support_completed", {
            kind = plan ~= nil and tostring(plan.kind) or nil,
        })
    end
    self:releaseGroupSupport()
    self:finishDecision(ticks)
    return completed
end

function Controller:beginWindowDetour(ticks, resumeState)
    if self.pendingSupply == nil or (self.pendingSupply.entryAttemptCount or 0) >= 8 then
        return false
    end
    self.pendingSupply.entryAttempts = self.pendingSupply.entryAttempts or {}
    local entry = findAlternateEntry(self, self.pendingSupply, ticks)
    if entry == nil then
        return false
    end
    self.pendingSupply.entryAttemptCount = (self.pendingSupply.entryAttemptCount or 0) + 1
    self.pendingSupply.entryAttempts[entry.object] = "attempted"
    self.bridge:cancelNpcMove(self.id)
    local result = tostring(self.bridge:moveNpc(self.id, entry.outside))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    entry.resumeState = resumeState
    self.entryDetour = entry
    self.state = "MOVING_TO_WINDOW_ENTRY"
    self.stateStartedAt = ticks
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " alternate-entry=" .. tostring(entry.kind) .. " outside="
            .. entry.outside:getX() .. "," .. entry.outside:getY()
    )
    return true
end

function Controller:beginLockedDoorBreak(ticks, resumeState, preserveBaseTaskSupply)
    if self.pendingSupply == nil or self.pendingSupply.doorBreakAttempted == true then
        return false
    end
    local endurance = KnoxSurvivorNeeds.snapshot(self.character).endurance
    local structureSquare = self.pendingSupply.container ~= nil
        and self.pendingSupply.container:getSourceGrid()
        or self.pendingSupply.targetSquare
    if not KnoxBaseManager.canDamageStructure(self.id, structureSquare) then
        markPendingAreaBlocked(self, ticks, "protected_player_base")
        return false
    end
    if preserveBaseTaskSupply ~= true then
        self:releaseBaseTaskSupplyTransfer()
    end
    if not canForceEntry(self, structureSquare) or endurance < LOCKED_DOOR_MIN_ENDURANCE then
        markPendingAreaBlocked(
            self,
            ticks,
            endurance < LOCKED_DOOR_MIN_ENDURANCE
                and "too_tired_for_forced_entry" or "no_melee_weapon_for_forced_entry"
        )
        return false
    end
    self.pendingSupply.doorBreakAttempted = true
    local result = tostring(self.bridge:beginNpcLockedDoorCombat(self.id))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        markPendingAreaBlocked(self, ticks, "door_break_failed:" .. tostring(result))
        return false
    end
    self.entryDetour = { resumeState = resumeState, doorFallback = true }
    self.state = "BREAKING_LOCKED_DOOR"
    self.stateStartedAt = ticks
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " alternate-entry=break-door")
    return true
end

function Controller:crossWindowDetour(ticks)
    if self.entryDetour == nil then
        return false
    end
    if self.entryDetour.force then
        -- Revalidate protection and the real world object at the action boundary.
        local window = self.entryDetour.object
        if not KnoxBaseManager.canDamageStructure(self.id, self.entryDetour.inside)
            or KnoxSurvivorNeeds.snapshot(self.character).endurance < LOCKED_DOOR_MIN_ENDURANCE
            or safeObjectBoolean(window, "isBarricaded", true) then return false end
        self.entryDetour.force = false
        if not safeObjectBoolean(window, "IsOpen", false)
            and not safeObjectBoolean(window, "isSmashed", false) then
            self.bridge:cancelNpcMove(self.id)
            ISTimedActionQueue.add(ISSmashWindow:new(self.character, window))
            self.state = "OPENING_ENTRY_WINDOW"
            self.stateStartedAt = ticks
            return true
        end
    end
    local result = tostring(self.bridge:crossNpc(self.id, self.entryDetour.inside))
    if string.find(result, "CROSS_STARTED", 1, true) ~= 1 then
        return false
    end
    self.windowResumeRetryUntil = nil
    self.state = "CROSSING_WINDOW_ENTRY"
    self.stateStartedAt = ticks
    return true
end

function Controller:retryWindowDetour(ticks, movement)
    local entry = self.entryDetour
    if entry == nil or self.pendingSupply == nil then return false end
    local attempts = self.pendingSupply.entryAttempts or {}
    self.pendingSupply.entryAttempts = attempts
    if entry.kind == "window" and not entry.smashedAttempt
        and string.find(tostring(movement), "FAILED_LOCKED_OR_UNUSABLE_WINDOW", 1, true)
        and not safeObjectBoolean(entry.object, "IsOpen", false)
        and not safeObjectBoolean(entry.object, "isSmashed", false) then
        attempts[entry.object] = "closed"
    end
    return self:beginWindowDetour(ticks, entry.resumeState)
end

function Controller:updateEntryWindow(ticks)
    if not self.character:getCharacterActions():isEmpty() then return end
    local entry = self.entryDetour
    if entry ~= nil and safeObjectBoolean(entry.object, "isSmashed", false) then
        entry.smashedAttempt = true
        if self:crossWindowDetour(ticks) then return end
    end
    if not self:retryWindowDetour(ticks, "smash_failed") then
        self:abandonCurrentDecision(ticks, "window_smash_failed")
    end
end

function Controller:resumeAfterWindowDetour(ticks)
    if self.entryDetour == nil or self.pendingSupply == nil then
        return false
    end
    local resumeState = self.entryDetour.resumeState
    local result = tostring(self.bridge:moveNpc(self.id, self.pendingSupply.approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        -- The native vault animation can still own the body on the first tick
        -- after the crossing reports done. Hold the crossing state briefly and
        -- retry instead of abandoning into a seconds-long stand.
        if self.windowResumeRetryUntil == nil then
            self.windowResumeRetryUntil = ticks + 150
        end
        if ticks < self.windowResumeRetryUntil then
            self.nextThink = ticks + THINK_MIN_TICKS
            return true
        end
        self.windowResumeRetryUntil = nil
        return false
    end
    self.windowResumeRetryUntil = nil
    self.entryDetour = nil
    if self.pendingSupply.taskEntry == true
        or self.pendingSupply.taskSupplyEntry == true then
        self.pendingSupply = nil
    end
    self.state = resumeState
    self.stateStartedAt = ticks
    if resumeState == "BASE_TASK_SUPPLY_MOVE" then
        self:noteTaskTravelStart(ticks)
    end
    if resumeState == "GROUP_FOLLOW" or resumeState == "COMPANION_FOLLOW" then
        self.pendingSupply = nil
    end
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " alternate-entry=completed")
    return true
end

-- A failed door break against a standing companion directive counts as a
-- directive miss under the same 3-strike rule as exploration misses.
-- Without this, abandoning clears pendingSupply and the directive simply
-- re-attempts the same locked door forever.
function Controller:countDoorBreakDirectiveMiss(ticks)
    if self.companionDirective == nil then return end
    self.directiveMisses = (tonumber(self.directiveMisses) or 0) + 1
    if self.directiveMisses >= 3 then
        if KnoxPersistence ~= nil and KnoxPersistence.clearCompanionDirective ~= nil then
            local hours = 0
            if getGameTime ~= nil and getGameTime() ~= nil then
                local ok, value = pcall(function()
                    return getGameTime():getWorldAgeHours()
                end)
                if ok then hours = tonumber(value) or 0 end
            end
            KnoxPersistence.clearCompanionDirective(
                self.id, self.companionOwnerId, hours
            )
        end
        self.companionDirective = nil
        self.directiveMisses = 0
    end
end

function Controller:abandonCurrentDecision(ticks, reason)    if self.pendingDepositTrip ~= nil then self:deferDepositTrip(ticks) end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    self:resetMovementRecovery()
    self:releaseAmbientMovement()
    self:releaseAid()
    self:abandonBaseTask(reason or "decision_abandoned")
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    -- Clearing a sit/rest timed action without waking leaves the survivor
    -- seated on furniture with no action and no decision: visibly stuck.
    if self.character ~= nil then
        self:leaveRecoveryPosture()
    end
    if self.selfCareIntent ~= nil then
        local kind = tostring(self.selfCareIntent.kind or self.activeDecision)
        self.selfCareRetryAt[kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
    end
    if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
        self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
    end
    if self.state == "ROAMING" then
        rememberRoamDestination(
            self,
            self.roamGoalKey,
            ticks,
            Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS
        )
        self.roamGoalKey = nil
        self.roamGoalKind = nil
    end
    if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
        self:releaseCampPosition()
    end
    self:releaseCombat()
    self:clearFirearmCombatState()
    self:cancelRobbery(ticks, reason or "decision_abandoned")
    self:releaseSupply()
    self.counts.failures = self.counts.failures + 1
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " abandoned=" .. tostring(self.activeDecision)
            .. " reason=" .. tostring(reason)
    )
    self:finishDecision(ticks)
end

-- Last-resort boundary for a controller exception. Each step is isolated so a
-- broken native action cannot prevent later leases from being released. Durable
-- assignment state (orders, group/base membership and life intent) is retained.
function Controller:recoverFromControllerError(ticks, reason)
    ticks = tonumber(ticks) or 0
    local failures = {}
    local function cleanup(label, action)
        local ok, failure = pcall(action)
        if not ok then
            failures[#failures + 1] = label .. "=" .. tostring(failure)
        end
    end

    if self.selfCareIntent ~= nil then
        local kind = tostring(self.selfCareIntent.kind or self.activeDecision or "unknown")
        self.selfCareRetryAt = self.selfCareRetryAt or {}
        self.selfCareRetryAt[kind] = math.max(
            self.selfCareRetryAt[kind] or 0,
            ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
        )
    end
    if self.pendingDepositTrip ~= nil then
        cleanup("defer_deposit", function() self:deferDepositTrip(ticks) end)
    end
    cleanup("trade", function() self:cancelTrade("controller_error") end)
    cleanup("robbery", function() self:cancelRobbery(ticks, "controller_error") end)
    cleanup("cancel_move", function()
        if self.bridge ~= nil and self.bridge.cancelNpcMove ~= nil then
            self.bridge:cancelNpcMove(self.id)
        end
    end)
    cleanup("reset_combat", function()
        if self.bridge ~= nil and self.bridge.resetNpcCombat ~= nil then
            self.bridge:resetNpcCombat(self.id)
        end
    end)
    cleanup("timed_actions", function()
        if hasPendingTimedActions(self.character) then
            ISTimedActionQueue.clear(self.character)
        end
    end)
    cleanup("corpse_release", function()
        if self.character ~= nil and KnoxBaseCorpseHandling ~= nil
            and KnoxBaseCorpseHandling.isDragging ~= nil
            and KnoxBaseCorpseHandling.isDragging(self.character) then
            self.character:setDoGrappleLetGo()
        end
    end)
    cleanup("base_task", function()
        self:abandonBaseTask(reason or "controller_error")
    end)
    if self.baseTask ~= nil then
        cleanup("base_task_fallback", function()
            local task = self.baseTask
            local finishOk, finished, detail = pcall(
                KnoxBaseTaskBoard.finish,
                task.baseId or self.baseId,
                task.id,
                self.id,
                false,
                reason or "controller_error"
            )
            if not finishOk or finished == nil then
                -- The claimed table is the persisted task object. Release its
                -- owner even if the normal board wrapper is the failing code;
                -- leave it blocked for the scheduler's existing retry policy.
                if task.state == "claimed" and task.claimedBy == self.id then
                    local nowHours = currentWorldAgeHours()
                    task.state = "blocked"
                    task.result = "controller_error_fallback"
                    task.completedAtHours = nowHours
                    task.lastBlockedAtHours = nowHours
                    task.lastClaimedBy = task.claimedBy
                    task.claimedBy = nil
                    task.claimedAtHours = nil
                    task.manual = nil
                    task.auto = nil
                    task.failureStreak = math.min(
                        6,
                        (tonumber(task.failureStreak) or 0) + 1
                    )
                    task.retryAtHours = nowHours + math.min(
                        8,
                        0.25 * (2 ^ (task.failureStreak - 1))
                    )
                end
            end
            self:clearBaseTaskRuntimeState()
            if not finishOk or finished == nil then
                error(tostring(finishOk and detail or finished))
            end
        end)
    end
    cleanup("recovery_posture", function() self:leaveRecoveryPosture() end)
    cleanup("rest", function() self:releaseRestSpot() end)
    cleanup("combat", function()
        self:releaseCombat()
        self:clearFirearmCombatState()
    end)
    cleanup("supply", function() self:releaseSupply() end)
    cleanup("base_supply_claim", function()
        if self.baseSupplyKind ~= nil then self:releaseBaseSupplyClaim(self.baseSupplyKind) end
    end)
    cleanup("group_support", function() self:releaseGroupSupport() end)
    cleanup("aid", function() self:releaseAid() end)
    cleanup("ambient", function() self:releaseAmbientMovement() end)
    cleanup("camp_position", function() self:releaseCampPosition() end)
    cleanup("base_cooking", function() self:releaseBaseCooking() end)
    cleanup("base_recreation", function() self:releaseBaseRecreation() end)
    cleanup("base_hygiene", function() self:releaseBaseHygiene() end)
    cleanup("base_organize", function() self:releaseBaseOrganize() end)
    cleanup("opened_doors", function() self:closeOpenedDoors() end)
    cleanup("reservation_sweep", function() self:releaseAllTransientReservations() end)
    cleanup("movement_recovery", function() self:resetMovementRecovery() end)

    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    self.securityContext = nil
    self.securityRoute = nil
    self.securityRetryAt = nil
    self.pendingCleanup = nil
    self.pendingDepositTrip = nil
    self.pendingRobbery = nil
    self.pendingRobberyHold = nil
    self.allyDefenseThreats = {}
    self.pendingThreatAwareness = nil
    self.pendingCorpseDefenseTarget = nil
    self.corpseDefenseReleaseUntil = nil
    self.entryDetour = nil
    self.windowResumeRetryUntil = nil
    self.regroupMember = nil
    self.fleeRecoveryUntil = nil
    self.fleeTarget = nil
    self.failedFleeTarget = nil
    self.selfCareIntent = nil
    self.selfCareInterrupted = nil
    self.ambientRest = nil
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = ticks + THINK_MIN_TICKS
    self.nextThreatScan = math.max(self.nextThreatScan or 0, ticks + THREAT_SCAN_TICKS)
    self.stateStartedAt = ticks
    self.observedState = self.state
    self.counts = self.counts or {}
    self.counts.failures = (self.counts.failures or 0) + 1
    return #failures == 0, table.concat(failures, " | ")
end


function Controller:beginExploration(ticks, directive, options)
    if ticks < self.nextExplorationSearch then
        return false
    end
    local target = findExploration(self, ticks, directive, options)
    if target == nil then
        self.nextExplorationSearch = ticks + (options ~= nil
            and options.partySupport == true
            and EMPTY_SEARCH_COOLDOWN_TICKS or EXPLORATION_RETRY_TICKS)
        if options ~= nil and options.partySupport == true then
            self:recordFailure(
                "party_support_food_unavailable",
                ticks,
                EMPTY_SEARCH_COOLDOWN_TICKS
            )
        end
        if directive ~= nil and directive.eventId ~= nil then
            KnoxEvents.recordEmptySearch(directive.eventId, self.id)
        elseif directive ~= nil then
            self.directiveMisses = self.directiveMisses + 1
            if self.directiveMisses >= 3 then
                KnoxPersistence.clearCompanionDirective(
                    self.id,
                    self.companionOwnerId,
                    getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                )
                self.companionDirective = nil
                self.directiveMisses = 0
                KnoxActivityFeed.speak(self.character, "I've checked the area.")
            end
        end
        return false
    end
    if not reserve(self.reservations, "containers", target.container, self.id) then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local reservedItems = {}
    for _, candidate in ipairs(target.items or {}) do
        if not reserve(self.reservations, "items", candidate.item, self.id) then
            for _, reservedItem in ipairs(reservedItems) do
                release(self.reservations, "items", reservedItem, self.id)
            end
            release(self.reservations, "containers", target.container, self.id)
            self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
            return false
        end
        reservedItems[#reservedItems + 1] = candidate.item
    end
    local directiveKind = directive ~= nil and tostring(directive.kind or "") or ""
    local context = "travel"
    if directive ~= nil and directiveKind == "go_to" then
        context = "directed"
    elseif directive ~= nil and (directiveKind == "loot_area" or directiveKind == "loot_building"
        or directiveKind == "loot_corpses" or directiveKind == "loot_room"
        or string.find(directiveKind, "^find_", 1) == 1) then
        context = "loot"
    elseif directive == nil then
        -- Self-directed container checks are also loot legs: walk them.
        context = "loot"
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target.approach, context
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        for _, candidate in ipairs(target.items or {}) do
            release(self.reservations, "items", candidate.item, self.id)
        end
        release(self.reservations, "containers", target.container, self.id)
        self.inspectedContainers[target.container] = ticks + EXPLORATION_RETRY_TICKS
        self:recordFailure(
            "exploration_move:" .. result,
            ticks,
            EXPLORATION_RETRY_TICKS
        )
        return false
    end
    self.pendingSupply = target
    if directive == nil and self.companionOrder == nil
        and self.groupLeaderId == nil and self.baseId == nil and self.campId == nil then
        self.scavengeBuildingId = target.buildingId or self.scavengeBuildingId
    end
    target.eventId = directive ~= nil and directive.eventId or nil
    self.activeDecision = directive ~= nil and tostring(directive.kind)
        or target.partySupport == true and "party_support_food"
        or (target.items ~= nil and #target.items > 0
            and "loot_useful_items_" .. tostring(#target.items)
            or "inspect_container")
    if directive == nil and self.companionOrder == nil
        and self.groupLeaderId == nil and self.baseId == nil and self.campId == nil then
        self:setLifeIntent(
            "scavenge",
            "traveling",
            target.approach,
            target.buildingId or roamDestinationKey(target.container:getSourceGrid())
        )
    end
    self.state = "MOVING_TO_EXPLORE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_EXPLORE goal=" .. tostring(self.activeDecision)
    )
    return true
end

function Controller:prepareSecurityContext(duty)
    if self.securityContext~=duty then
        self.securityContext,self.securityRoute,self.securityRetryAt=duty,nil,0
        self.securityFailedSquares,self.securityMisses={},0
    end
end

function Controller:advanceSecurityPatrol(route,arrived)
    if route==nil or not route.patrol then return false end
    local duty=route.duty
    if route.base then
        duty.patrolStep=route.step
        if arrived then
            local complete=KnoxCompanionPatrol.recordTaskArrival(duty)
            if complete then duty.patrolLaps=math.min(1000000,(tonumber(duty.patrolLaps) or 0)+1) end
        else duty.patrolStep=(route.step+1)%math.max(1,route.count) end
        return true
    end
    return KnoxPersistence.advanceCompanionPatrol(self.id,self.companionOwnerId,duty,route.step,arrived)
end

function Controller:deferSecurityRoute(ticks,reason,base)
    local route=self.securityRoute
    self.bridge:cancelNpcMove(self.id)
    self.securityFailedSquares=self.securityFailedSquares or {}
    if route~=nil and route.square~=nil then
        self.securityFailedSquares[KnoxCompanionPatrol.squareKey(route.square)]=ticks+1800
        self:advanceSecurityPatrol(route,false)
    end
    self.securityMisses=math.min(4,(self.securityMisses or 0)+1)
    local delay=math.min(1800,150*2^self.securityMisses)
    self.securityRetryAt,self.nextThink=ticks+delay,ticks+delay
    self.lastFailure={reason="security_route:"..tostring(reason)
        .." destination="..(route~=nil and route.square~=nil and KnoxCompanionPatrol.squareKey(route.square) or "unavailable"),ticks=ticks}
    self.state=base and "BASE_SECURITY_WAIT" or "COMPANION_DUTY_WAIT"
    self.activeDecision="security_route_blocked"
    self.securityRoute=nil
    if ticks>=(self.nextSecuritySpeech or 0) then
        KnoxActivityFeed.speak(self.character,"The route is blocked. I'll keep watch and try again.")
        self.nextSecuritySpeech=ticks+3600
    end
    return true
end

function Controller:beginSecurityRoute(ticks,duty,base)
    self:prepareSecurityContext(duty)
    if ticks<(self.securityRetryAt or 0) then
        self.state=base and "BASE_SECURITY_WAIT" or "COMPANION_DUTY_WAIT"
        self.activeDecision="security_route_blocked"
        return true
    end
    for key,untilTick in pairs(self.securityFailedSquares) do
        if untilTick<=ticks then self.securityFailedSquares[key]=nil end
    end
    local area=base and duty.target or duty
    local patrol=(base and duty.type=="patrol") or (not base and duty.kind=="patrol_area")
    local identity=base and (duty.id or self.id) or self.id
    local square,step,count=KnoxCompanionPatrol.resolveWaypoint(area,identity,duty.patrolStep,
        getCell(),self.character:getCurrentSquare(),self.securityFailedSquares,ticks,not patrol)
    if square==nil then return self:deferSecurityRoute(ticks,"no_loaded_standing_tile",base) end
    self.securityRoute={duty=duty,base=base==true,patrol=patrol,step=step,count=count,square=square}
    if not patrol and KnoxCompanionPatrol.contains(area,self.character:getCurrentSquare())
        and navigationDistanceSquared(self.character:getCurrentSquare(),square)<=2.25 then
        self.securityMisses=0
        self.state=base and "BASE_TASK_WORK" or "COMPANION_GUARD"
        self.activeDecision=base and "base_task_guard" or "guard_location"
        self.nextThink=ticks+90
        return true
    end
    local result=KnoxCompanionPatrol.move(self.bridge,self.id,square,area)
    if result:find("MOVE_STARTED",1,true)~=1 then return self:deferSecurityRoute(ticks,result,base) end
    self.state=base and "BASE_TASK_MOVE" or (patrol and "MOVING_TO_COMPANION_PATROL" or "MOVING_TO_COMPANION_POINT")
    self.activeDecision=base and ("base_task_"..duty.type) or (patrol and "patrol_area" or "guard_location")
    self.baseTaskStartedAt=nil
    return true
end

function Controller:completeSecurityArrival(ticks,base)
    local route=self.securityRoute
    if route==nil then return false end
    local area=base and route.duty.target or route.duty
    if not KnoxCompanionPatrol.contains(area,self.character:getCurrentSquare())
        or navigationDistanceSquared(self.character:getCurrentSquare(),route.square)>(route.patrol and 0 or 2.25) then
        return self:deferSecurityRoute(ticks,"arrival_outside_post",base)
    end
    if route.patrol and not self:advanceSecurityPatrol(route,true) then
        self.securityRoute=nil
        self:finishDecision(ticks)
        return true
    end
    self.securityMisses,self.securityRetryAt=0,0
    self.state=base and (route.patrol and "BASE_TASK_PATROL_WAIT" or "BASE_TASK_WORK")
        or (route.patrol and "COMPANION_PATROL_WAIT" or "COMPANION_GUARD")
    self.activeDecision=base and ("base_task_"..route.duty.type) or (route.patrol and "patrol_area" or "guard_location")
    self.baseTaskStartedAt=ticks
    self.nextThink=ticks+(route.patrol and 180 or 90)
    return true
end

function Controller:updateSecurityRouteWait(ticks,base)
    if base then
        self:updateBaseSecurityDuty(ticks)
        if self.state~="BASE_SECURITY_WAIT" then return end
    elseif ticks>=(self.nextSecurityNeedCheck or 0) then
        self.nextSecurityNeedCheck=ticks+90
        local decision=KnoxSurvivorNeeds.decide(self.character,nil)
        if decision~=nil and decision.kind~="roam" then
            self.state,self.activeDecision,self.nextThink="IDLE",nil,ticks
            return
        end
    end
    if ticks>=(self.securityRetryAt or 0) then
        if base and self.baseTask~=nil then self:beginBaseTaskWorkMove(ticks)
        else self.state,self.nextThink="IDLE",ticks end
    end
end

function Controller:completeCompanionPointDirective(ticks, directive)
    if directive ~= nil and directive.partyDestination == true then
        local service = rawget(_G, "KnoxCompanionService")
        local marked = service ~= nil and service.markPartyDestinationArrived ~= nil
            and service.markPartyDestinationArrived(
                self.id, directive.partyDestinationRevision
            ) == true
        if not marked then
            self.companionDirective = nil
            self:releasePartyDestinationTarget()
            return false
        end
        local waitingDirective = service ~= nil
            and service.getPartyDestinationFor ~= nil
            and service.getPartyDestinationFor(self.id) or nil
        if waitingDirective ~= nil and waitingDirective.partyDestinationArrived == true then
            -- Keep the participant's distinct arrival tile claimed while the
            -- remaining party members finish the same destination order.
            self.companionDirective = waitingDirective
        else
            self.companionDirective = nil
            self:releasePartyDestinationTarget()
        end
        KnoxActivityFeed.speak(self.character, "I'm here.")
        return true
    end
    if directive ~= nil and directive.kind == "go_to" then
        KnoxPersistence.clearCompanionDirective(
            self.id, self.companionOwnerId,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
        self.companionDirective = nil
        KnoxActivityFeed.speak(self.character, "I'm here.")
        return true
    end
    return false
end

function Controller:beginCompanionPointDirective(ticks, directive)
    if directive~=nil and directive.kind=="guard" then return self:beginSecurityRoute(ticks,directive,false) end
    local cell = getCell()
    local x = tonumber(directive ~= nil and directive.minX)
    local y = tonumber(directive ~= nil and directive.minY)
    local z = tonumber(directive ~= nil and directive.z) or 0
    if cell == nil or x == nil or y == nil then
        return false
    end
    local destination = cell:getGridSquare(x, y, z)
    if destination == nil then
        self:recordFailure("companion_point_unloaded", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local target = destination
    if directive.partyDestination == true then
        target = self:findPartyDestinationTarget(directive, destination)
    end
    if target == nil then
        self:recordFailure("party_destination_approach_unavailable", ticks,
            Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS)
        return false
    end
    local current = self.character:getCurrentSquare()
    local atPartyDestination = directive.partyDestination == true
        and current ~= nil
        and navigationDistanceSquared(current, destination)
            <= Controller.PLAYER_PARTY_FORMATION.destinationToleranceSquared
    if directive.partyDestination == true and current ~= nil
        and navigationDistanceSquared(current, target) <= Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED
        and not atPartyDestination then
        self.partyDestinationFinalLeg = true
        target = self:findPartyDestinationTarget(directive, destination)
        if target == nil then return false end
    end
    if current ~= nil and (atPartyDestination
        or (directive.partyDestination ~= true
            and navigationDistanceSquared(current, target) <= 2.25)) then
        self.activeDecision = directive.kind == "guard" and "guard_location" or "go_to_location"
        self.state = directive.kind == "guard" and "COMPANION_GUARD" or "COMPANION_WAIT"
        self.nextThink = ticks + 90
        if directive.kind == "go_to" then self:completeCompanionPointDirective(ticks, directive) end
        return true
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "directed"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordMovementFailure(
            "companion_point_move", result, ticks, EXPLORATION_RETRY_TICKS
        )
        return false
    end
    self.activeDecision = directive.kind == "guard" and "guard_location" or "go_to_location"
    self.state = "MOVING_TO_COMPANION_POINT"
    return true
end

function Controller:beginCompanionPatrolDirective(ticks,directive)
    return self:beginSecurityRoute(ticks,directive,false)
end

function Controller:releaseCombat()
    releaseThreat(self.reservations, self.combatTarget, self.id)
    self.combatTarget = nil
end

-- Terminal firearm-encounter cleanup. Native reload/attack actions are owned
-- by their own queues and canceled through KnoxFirearmSupport.cancelPreparation
-- where required; this only drops Knox's bounded retry/preference transients so
-- a later encounter cannot inherit a stale preparation clock, a stale committed
-- weapon class, or a stale ranged-failure streak.
function Controller:clearFirearmCombatState()
    self.reloadYieldStreak = 0
    self.reloadPreparationStartedAt = nil
    self.reloadYieldTarget = nil
    self.reloadYieldWeaponKey = nil
    self.rangedEncounterTarget = nil
    self.rangedCombatFailureStreak = 0
end

-- Bounded ranged-failure accounting. A gun that keeps failing to approach or
-- pursue its target is a non-viable ranged encounter. Returns true once the
-- consecutive native ranged failures reach the bounded threshold, so the caller
-- can release firearm ownership and use the existing melee-fallback owner. Any
-- melee/other primary, or a successful shot, resets the streak.
function Controller:noteRangedCombatFailure(primaryItem)
    if primaryItem ~= nil and KnoxFirearmSupport ~= nil
        and KnoxFirearmSupport.isFunctionalGun ~= nil
        and KnoxFirearmSupport.isFunctionalGun(primaryItem) == true then
        self.rangedCombatFailureStreak = (self.rangedCombatFailureStreak or 0) + 1
    else
        self.rangedCombatFailureStreak = 0
    end
    return self.rangedCombatFailureStreak
        >= Controller.RANGED_COMBAT_FAILURE_FALLBACK_STREAK
end

function Controller:releaseRestSpot()
    if self.pendingRest ~= nil and self.pendingRest.object ~= nil then
        release(self.reservations, "restSpots", self.pendingRest.object, self.id)
    end
    self.pendingRest = nil
end

function Controller:releaseAllTransientReservations()
    local released = releaseAllReservationsForOwner(self.reservations, self.id)
    self.playerFormationTargetSquare = nil
    self.partyDestinationTargetSquare = nil
    self.partyDestinationTargetRevision = nil
    self.partyDestinationFinalLeg = nil
    return released
end

function Controller:releasePartyDestinationTarget()
    local target = self.partyDestinationTargetSquare
    local bucket = self.reservations ~= nil
        and self.reservations.partyDestinationTargets or nil
    if target ~= nil and bucket ~= nil and bucket[target] == self.id then
        bucket[target] = nil
    end
    self.partyDestinationTargetSquare = nil
    self.partyDestinationTargetRevision = nil
end

function Controller:leaveRecoveryPosture()
    -- Minimal unit-test shells do not implement the posture API; live
    -- characters always do. Fail closed here so danger interrupts never
    -- depend on which mock actor is installed.
    if self.character == nil or type(self.character.isSitOnGround) ~= "function" then
        return
    end
    KnoxSurvivorNeeds.wakeForDanger(self.character)
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        -- Momentary pulse only: the tick loop drops this latch the instant
        -- the body is standing again, so a later knockdown keeps the native
        -- player-like timer instead of standing instantly.
        self.character:setVariable("forceGetUp", true)
        self.forceGetUpLatched = true
    end
    self.character:setIsResting(false)
    self.character:setBed(nil)
    self:releaseRestSpot()
end

function Controller:startRecoveryPosture(ticks, useFurniture, ambient)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.activeDecision == "sleep" and ambient ~= true then
        local bed = useFurniture and self.pendingRest ~= nil
            and self.pendingRest.object or nil
        local bedType = bed ~= nil and self.pendingRest.bedType or "floor"
        if bed == nil then
            self:releaseRestSpot()
        end
        local sleeping, result = KnoxSurvivorNeeds.startSleep(
            self.character,
            bed,
            bedType
        )
        if sleeping then
            self.state = "SLEEPING_RECOVERY"
            self.recoveryStarted = ticks
            self.recoveryPostureStarted = ticks
            self.nextThink = ticks + Controller.TUNING.RECOVERY_RECHECK_TICKS
            self.selfCareIntent = self.selfCareIntent or {
                kind = "sleep",
                before = KnoxSurvivorNeeds.snapshot(self.character),
            }
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " recovery-posture=sleep:" .. tostring(bedType)
                    .. " result=" .. tostring(result)
            )
            return true
        end
        self.selfCareRetryAt.sleep = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
        self:recordFailure("needs_action:sleep:" .. tostring(result), ticks,
            Controller.TUNING.SELF_CARE_RETRY_TICKS)
        self:finishDecision(ticks)
        return false
    end
    local action = nil
    local posture = "ground"
    if useFurniture and self.pendingRest ~= nil and self.pendingRest.object ~= nil
        and usableRestFurniture(
            self,
            self.pendingRest.object,
            self.activeDecision == "sleep"
        ) then
        action = ISRestAction:new(self.character, self.pendingRest.object, true)
        posture = "furniture:" .. tostring(self.pendingRest.bedType)
    else
        self:releaseRestSpot()
        action = ISSitOnGround:new(self.character, nil)
    end
    ISTimedActionQueue.add(action)
    self.state = ambient == true
        and (self.activeDecision == "camp_ambient_rest" and "CAMP_AMBIENT_REST"
            or (self.activeDecision == "companion_relax" and "COMPANION_RELAX"
                or "BASE_AMBIENT_REST"))
        or "WAITING_TO_RECOVER"
    self.recoveryStarted = ticks
    self.recoveryPostureStarted = ticks
    self.nextThink = ticks + (ambient == true
        and Controller.TUNING.BASE_AMBIENT_REST_TICKS or Controller.TUNING.RECOVERY_RECHECK_TICKS)
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " recovery-posture=" .. posture
            .. " endurance=" .. tostring(KnoxSurvivorNeeds.snapshot(self.character).endurance)
    )
end

function Controller:releaseBaseCooking()
    local plan=self.pendingCooking
    if plan==nil then return end
    KnoxBaseCooking.cancel(plan,self.character)
    if plan.phase=="move" then self.bridge:cancelNpcMove(self.id) end
    self.pendingCooking=nil
end

function Controller:beginBaseCooking(ticks,target,personal)
    if KnoxBaseCooking==nil or self.base==nil or self.pendingCooking~=nil
        or ticks<(self.nextCookingAt or 0) or not self.character:getCharacterActions():isEmpty() then return false end
    if personal then
        if self:hasNeedEscort() or not KnoxBaseManager.containsSquare(self.base,self.character:getCurrentSquare())
            or KnoxBaseCooking.hasReadyMeal(self.base) then return false end
        target=KnoxBaseCooking.findTask(self.base,self.character)
    end
    if target==nil then self.nextCookingAt=ticks+1800;return false end
    local plan,reason=KnoxBaseCooking.begin(self.base,target,self.character,self.id)
    if plan==nil then
        self.nextCookingAt=ticks+1800
        self.lastFailure={reason=tostring(reason),ticks=ticks}
        return false
    end
    plan.personal=personal==true
    self.pendingCooking,self.cookingStartedAt=plan,ticks
    self.state,self.activeDecision="BASE_COOKING","cooking_collect"
    return true
end

function Controller:updateBaseCooking(ticks)
    local plan=self.pendingCooking
    if plan==nil then self:finishDecision(ticks);return end
    if ticks>=(self.nextCookingNeedCheck or 0) then
        self.nextCookingNeedCheck=ticks+90
        local decision=KnoxSurvivorNeeds.decide(self.character,nil)
        -- Cooking is a real response to missing meals. Do not interrupt it every
        -- second because the same hunger still needs the food being prepared.
        if decision~=nil and decision.kind~="roam" and decision.kind~="find_food" then
            local mealReady=decision.kind=="eat" and self.character:getInventory():contains(plan.item)
                and plan.item:isCooked() and KnoxSurvivorNeeds.isSafeFood(plan.item)
                and not plan.object:getContainer():contains(plan.item)
            if mealReady and not plan.personal then
                self:finishBaseTask(true,"meal_prepared_for_resident")
            else
                self:suspendBaseTaskForThreat("cooking_needs_interrupt")
            end
            self:finishDecision(ticks)
            return
        end
    end
    local outcome,reason=KnoxBaseCooking.step(plan,self.character,self.base,self.bridge,ticks)
    if ticks-(self.cookingStartedAt or ticks)>10800 then outcome,reason="failed","cooking_session_timeout" end
    self.activeDecision="cooking_"..tostring(plan.phase)
    if outcome~="working" then
        local personal=plan.personal
        self:releaseBaseCooking()
        if not personal then self:finishBaseTask(outcome=="done",reason) end
        self.nextCookingAt=ticks+(outcome=="done" and 0 or 1800)
        if outcome=="failed" then self.lastFailure={reason=tostring(reason),ticks=ticks} end
        self:finishDecision(ticks)
    end
end

function Controller:releaseBaseRecreation()
    local plan=self.pendingRecreation
    if plan==nil then return end
    if KnoxBaseRecreation~=nil then KnoxBaseRecreation.cancelAction(self.character,plan) end
    if plan.phase=="borrow_move" or plan.phase=="return_move" then self.bridge:cancelNpcMove(self.id) end
    release(self.reservations,"items",plan.item,self.id)
    self.pendingRecreation=nil
end

function Controller:beginBaseRecreation(ticks)
    if KnoxBaseRecreation==nil or self.base==nil or self.baseTask~=nil
        or not KnoxBaseManager.containsSquare(self.base,self.character:getCurrentSquare())
        or ticks<(self.nextRecreationAt or 0) or not self.character:getCharacterActions():isEmpty()
        or ISTimedActionQueue.getTimedActionQueue(self.character).current~=nil then return false end
    self.nextRecreationAt=ticks+1800
    self.recentReading=self.recentReading or setmetatable({}, {__mode="k"})
    local readingEnabled=KnoxSettings==nil or KnoxSettings.baseReadingEnabled==nil or KnoxSettings.baseReadingEnabled()
    local plan=KnoxBaseRecreation.find(self.character,self.base,function(item,returning)
        return (returning or (self.recentReading[item] or 0)<=ticks) and not reservedByOther(self.reservations,"items",item,self.id)
    end,readingEnabled)
    if plan==nil or not reserve(self.reservations,"items",plan.item,self.id) then return false end
    self.pendingRecreation=plan
    self.recreationStartedAt=ticks
    self.nextRecreationNeedsCheck=ticks
    self.state,self.activeDecision="BASE_RECREATION","reading"
    return true
end

function Controller:updateBaseRecreation(ticks)
    if self.pendingRecreation==nil then self:finishDecision(ticks);return end
    if ticks>=(self.nextRecreationNeedsCheck or 0) then
        self.nextRecreationNeedsCheck=ticks+90
        local need=KnoxSurvivorNeeds.decide(self.character,nil)
        if need~=nil and need.kind~="roam" then
            self:releaseBaseRecreation()
            self:finishDecision(ticks)
            self.nextThink=math.max(self.nextThink or 0,ticks+THINK_MIN_TICKS)
            return
        end
    end
    local plan=self.pendingRecreation
    local outcome,reason=KnoxBaseRecreation.step(plan,self.character,self.base,self.bridge,self.id,ticks)
    if ticks-(self.recreationStartedAt or ticks)>7200 then outcome,reason="failed","recreation_timeout" end
    self.activeDecision=(plan.phase=="borrow_move" or plan.phase=="borrowing") and "collecting_book"
        or ((plan.phase=="return_move" or plan.phase=="returning" or plan.phase=="return") and "returning_book" or "reading")
    if outcome~="working" then
        self.recentReading[plan.item]=ticks+(outcome=="done" and 18000 or 1800)
        self:releaseBaseRecreation()
        self.nextRecreationAt=ticks+1800
        if outcome=="failed" then self:recordFailure("recreation:"..tostring(reason),ticks,1800) end
        self:finishDecision(ticks)
    end
end

function Controller:releaseBaseOrganize()
    local plan = self.pendingOrganize
    if plan == nil then return end
    if KnoxBaseOrganize ~= nil and KnoxBaseOrganize.cancelAction ~= nil then
        KnoxBaseOrganize.cancelAction(self.character, plan)
    end
    if plan.item ~= nil then
        release(self.reservations, "items", plan.item, self.id)
    end
    if plan.destinationPolicy ~= nil then
        release(self.reservations, "containers", plan.destinationPolicy, self.id)
    end
    self.pendingOrganize = nil
end

-- Ambient re-shelving for idle base residents: carry one misplaced or
-- demoted item to its best shelf through the shared reservation and
-- transfer machinery. Honors hauling=Never, work windows only (never
-- sleep/recreation), threats and needs preempt like any idle round.
function Controller:beginBaseOrganize(ticks)
    if KnoxBaseOrganize == nil or self.base == nil or self.baseTask ~= nil
        or self.pendingOrganize ~= nil
        or not KnoxBaseManager.containsSquare(self.base, self.character:getCurrentSquare())
        or ticks < (self.nextOrganizeAt or 0)
        or not self.character:getCharacterActions():isEmpty()
        or ISTimedActionQueue.getTimedActionQueue(self.character).current ~= nil then
        return false
    end
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local preference = KnoxPersistence.getWorkPreference ~= nil
        and KnoxPersistence.getWorkPreference(self.id, "hauling") or "normal"
    if preference == "disabled" then
        return false
    end
    self.nextOrganizeAt = ticks + 1800
    local recent = self.recentOrganized or {}
    local plan, reason = KnoxBaseOrganize.find(self.base, self.character,
        function(item) return (recent[item] or 0) <= ticks end,
        function(item) return reservedByOther(self.reservations, "items", item, self.id) end)
    if plan == nil then
        self.nextOrganizeAt = ticks + 3600
        return false
    end
    if not reserve(self.reservations, "items", plan.item, self.id) then
        self.nextOrganizeAt = ticks + 900
        return false
    end
    if not reserve(self.reservations, "containers", plan.destinationPolicy, self.id) then
        release(self.reservations, "items", plan.item, self.id)
        self.nextOrganizeAt = ticks + 900
        return false
    end
    self.pendingOrganize = plan
    self.organizeStartedAt = ticks
    self.nextOrganizeNeedsCheck = ticks
    self.state, self.activeDecision = "BASE_ORGANIZE", "organizing"
    return true
end

function Controller:updateBaseOrganize(ticks)
    if self.pendingOrganize == nil then self:finishDecision(ticks); return end
    if ticks >= (self.nextOrganizeNeedsCheck or 0) then
        self.nextOrganizeNeedsCheck = ticks + 90
        local need = KnoxSurvivorNeeds.decide(self.character, nil)
        if need ~= nil and need.kind ~= "roam" then
            self:releaseBaseOrganize()
            self:finishDecision(ticks)
            self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
            return
        end
    end
    local plan = self.pendingOrganize
    local outcome, reason = KnoxBaseOrganize.step(
        plan, self.character, self.base, self.bridge, self.id, ticks)
    if ticks - (self.organizeStartedAt or ticks) > 9000 then
        outcome, reason = "failed", "organize_timeout"
    end
    self.activeDecision = (plan.phase == "borrow_move" or plan.phase == "borrowing")
        and "collecting_item"
        or ((plan.phase == "deposit_move" or plan.phase == "depositing")
            and "shelving_item" or "organizing")
    if outcome ~= "working" then
        self.recentOrganized = self.recentOrganized or {}
        if plan.item ~= nil then
            self.recentOrganized[plan.item] = ticks + 3600
        end
        self:releaseBaseOrganize()
        self.nextOrganizeAt = ticks + (outcome == "done" and 900 or 1800)
        if outcome == "failed" then
            self:recordFailure("organize:" .. tostring(reason), ticks, 1800)
        end
        self:finishDecision(ticks)
    end
end

-- Ambient snack: eat or drink carried supplies through the real native
-- consume actions (hunger/thirst genuinely drop, verified by the shared
-- self-care completion path). Only below the comfort line and only from
-- the hip pocket, never a supply run: this is company time, not logistics.
-- Mild 0.30 thresholds keep it strictly under urgent need satisfaction.
function Controller:beginAmbientSnack(ticks)
    local state = KnoxSurvivorNeeds.snapshot(self.character)
    local kind, item = nil, nil
    if (tonumber(state.thirst) or 0) >= 0.30 then
        item = KnoxSurvivorNeeds.findBestWater(self.character, false)
        if item ~= nil then kind = "drink" end
    end
    if kind == nil and (tonumber(state.hunger) or 0) >= 0.30 then
        item = KnoxSurvivorNeeds.findBestFood(self.character)
        if item ~= nil then kind = "eat" end
    end
    if kind == nil or item == nil then return false end
    local action, _, intent = KnoxSurvivorNeeds.execute(self.character, {
        kind = kind, item = item, state = state,
    })
    if action == nil or action == false then return false end
    self.selfCareIntent = intent
    self.activeDecision = "base_ambient_snack"
    self.state = "TIMED_ACTION"
    self.stateStartedAt = ticks
    sayDialogue(self.character, self.id, "base_snack", ticks, 1800)
    self:diag("social", "ambient_snack", { kind = kind })
    return true
end

-- Ambient social: face a nearby resident, trade a line each, drift on.
-- No relationship model is touched (that belongs to the encounter system);
-- the value is visible company plus a speech-cooldown-respecting chat.
-- One shared cooldown per survivor so pairs do not chatter every think.
function Controller:beginAmbientSocial(ticks)
    if ticks < (self.nextSocialAt or 0) then return false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(self.baseId) or {}
    if type(residentIds) ~= "table" or #residentIds < 2 then return false end
    local here = self.character ~= nil and self.character:getCurrentSquare() or nil
    if here == nil then return false end
    local partner, partnerChar = nil, nil
    for _, otherId in ipairs(residentIds) do
        if tostring(otherId) ~= tostring(self.id) and runtime ~= nil
            and runtime.getCharacter ~= nil then
            local otherChar = runtime.getCharacter(otherId)
            local there = otherChar ~= nil and otherChar:getCurrentSquare() or nil
            if otherChar ~= nil and there ~= nil and there:getZ() == here:getZ()
                and (there:getX() - here:getX()) ^ 2
                    + (there:getY() - here:getY()) ^ 2 <= 16 then
                local alive = true
                if KnoxPersistence.isSurvivorAlive ~= nil then
                    alive = KnoxPersistence.isSurvivorAlive(otherId) ~= false
                end
                if alive then
                    partner, partnerChar = otherId, otherChar
                    break
                end
            end
        end
    end
    if partner == nil or partnerChar == nil then return false end
    pcall(function() self.character:faceThisObject(partnerChar) end)
    pcall(function() partnerChar:faceThisObject(self.character) end)
    local signals = rawget(_G, "KnoxOrderSignals")
    if signals ~= nil and signals.play ~= nil then
        pcall(function() signals.play(self.character, "wavehi") end)
        pcall(function() signals.play(partnerChar, "yes") end)
    end
    sayDialogue(self.character, self.id, "base_social", ticks, 1800)
    sayDialogue(partnerChar, partner, "base_social", ticks, 1800)
    self.nextSocialAt = ticks + 1800
    self.activeDecision = "base_ambient_social"
    self.state = "BASE_IDLE"
    self.nextThink = ticks + 300 + Controller.baseIdleJitter(self.id)
    self:diag("social", "ambient_social", { partner = tostring(partner) })
    return true
end

-- Living-room television scan for ambient watching. Same-Z home squares
-- near the resident only. Sets without zone power are skipped outright: no
-- staring at a dead screen, the caller falls back to other leisure.
-- Verified against this build's game jar: IsoTelevision extends
-- IsoWaveSignal, power state lives on zombie.radio.devices.DeviceData.
function Controller:findBaseTelevision()
    local character, base = self.character, self.base
    if character == nil or base == nil or getCell == nil or getCell() == nil then
        return nil
    end
    local origin = character:getCurrentSquare()
    local home = base.territory or base.home
    if origin == nil or home == nil then return nil end
    local z = origin:getZ()
    local minX = math.max(origin:getX() - 20, tonumber(home.minX) or -math.huge)
    local minY = math.max(origin:getY() - 20, tonumber(home.minY) or -math.huge)
    local maxX = math.min(origin:getX() + 20, tonumber(home.maxX) or math.huge)
    local maxY = math.min(origin:getY() + 20, tonumber(home.maxY) or math.huge)
    for x = minX, maxX do
        for y = minY, maxY do
            local square = getCell():getGridSquare(x, y, z)
            if square ~= nil and KnoxBaseManager ~= nil
                and KnoxBaseManager.containsSquare ~= nil
                and KnoxBaseManager.containsSquare(base, square) then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    local ok, isTv = pcall(function()
                        return instanceof(object, "IsoTelevision")
                    end)
                    if ok and isTv == true and self:isTelevisionPowered(object) then
                        return { square = square, object = object }
                    end
                end
            end
        end
    end
    return nil
end

-- Television power state read. Method names verified against this build's
-- game jar: IsoTelevision extends IsoWaveSignal, whose
-- zombie.radio.devices.DeviceData exposes getIsTurnedOn. Returns
-- true/false, or nil when no readable power API answers (the caller then
-- treats the set as dark).
function Controller:isTelevisionOn(object)
    if object == nil then return nil end
    local deviceData = nil
    pcall(function() deviceData = object:getDeviceData() end)
    if deviceData ~= nil then
        local readOk, isOn = pcall(function() return deviceData:getIsTurnedOn() end)
        if readOk and isOn ~= nil then return isOn == true end
    end
    return nil
end

-- Zone-power gate, same verified DeviceData (canBePoweredHere). Anything
-- but an explicit true means skip the set: unpowered, unreadable, or
-- unloaded all fall back to other leisure instead of a dead screen.
function Controller:isTelevisionPowered(object)
    if object == nil then return false end
    local deviceData = nil
    pcall(function() deviceData = object:getDeviceData() end)
    if deviceData == nil then return false end
    local ok, powered = pcall(function() return deviceData:canBePoweredHere() end)
    return ok and powered == true
end

-- Television power write through the verified DeviceData only
-- (setIsTurnedOn, re-read to confirm). No guessed fallbacks: if this
-- build ever stops answering, the call returns false and the watcher
-- falls back to other leisure instead of erroring.
function Controller:setTelevisionPower(object, on)
    if object == nil then return false end
    local deviceData = nil
    pcall(function() deviceData = object:getDeviceData() end)
    if deviceData == nil then return false end
    local readOk, isOn = pcall(function() return deviceData:getIsTurnedOn() end)
    if readOk and isOn == on then return true end
    if not pcall(function() deviceData:setIsTurnedOn(on == true) end) then
        return false
    end
    local verifyOk, nowOn = pcall(function() return deviceData:getIsTurnedOn() end)
    if verifyOk then return nowOn == on end
    return true
end

-- Release a light switch this survivor turned on. Only our own sets are
-- ever touched; a player's lit room is never killed under them.
function Controller:releaseLights()
    local lights = self.pendingLights
    self.pendingLights = nil
    if lights == nil or lights.turnedOn ~= true or lights.object == nil then return end
    pcall(function() lights.object:setActivated(false) end)
end

-- Nearby dark-room switch scan for ambient lighting. Same square area
-- only (a couple of tiles, same floor, inside the base): no walking, no
-- movement state, just a reachable switch flipped while settling in.
-- Class and power methods verified against this build's game jar
-- (IsoLightSwitch: isActivated/setActivated/canSwitchLight); darkness
-- comes from the native tooDarkToRead check the reading behavior uses.
function Controller:findDarkLightSwitch(here)
    local base = self.base
    if here == nil or base == nil or getCell == nil or getCell() == nil then
        return nil
    end
    local z = here:getZ()
    for x = here:getX() - 2, here:getX() + 2 do
        for y = here:getY() - 2, here:getY() + 2 do
            local square = getCell():getGridSquare(x, y, z)
            if square ~= nil and KnoxBaseManager ~= nil
                and KnoxBaseManager.containsSquare ~= nil
                and KnoxBaseManager.containsSquare(base, square) then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    local ok, isSwitch = pcall(function()
                        return instanceof(object, "IsoLightSwitch")
                    end)
                    if ok and isSwitch == true then
                        local okPower, canSwitch = pcall(function()
                            return object:canSwitchLight()
                        end)
                        local okState, isOn = pcall(function()
                            return object:isActivated()
                        end)
                        if okPower and canSwitch == true and okState and isOn ~= true then
                            return object
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Ambient lights: flip a nearby dark room's switch while idling through
-- company time, and switch it back off when the watch expires or sleep
-- takes over. Instant and decision-free; threats and needs preempt
-- normally since no state changes hands.
function Controller:maintainBaseLights(ticks)
    if self.base == nil or self.character == nil then return false end
    if self.pendingLights ~= nil then return true end
    if ticks < (self.nextLightsAt or 0) then return false end
    local dark = false
    local ok, tooDark = pcall(function() return self.character:tooDarkToRead() end)
    if ok then dark = tooDark == true end
    if not dark then return false end
    local found = self:findDarkLightSwitch(self.character:getCurrentSquare())
    if found == nil then
        self.nextLightsAt = ticks + 1800
        return false
    end
    local setOk = pcall(function() found:setActivated(true) end)
    local readOk, isOn = pcall(function() return found:isActivated() end)
    if not (setOk and readOk and isOn == true) then
        self.nextLightsAt = ticks + 1800
        return false
    end
    self.nextLightsAt = ticks + 3600
    self.pendingLights = { object = found, turnedOn = true, untilTick = ticks + 1800 }
    self:diag("social", "ambient_lights", nil)
    return true
end

-- Release a television this survivor switched on. Only the set we powered
-- is ever touched, so a player's already-running TV is never switched off
-- under them. Idempotent; safe to call from every preemption path.
function Controller:releaseWatch()
    local watch = self.pendingWatch
    self.pendingWatch = nil
    if watch == nil or watch.turnedOn ~= true or watch.object == nil then return end
    self:setTelevisionPower(watch.object, false)
end

-- Ambient TV: face a nearby in-base television and watch a while. Switches
-- a dark set on for the watch and back off afterwards; threats and needs
-- preempt on the next think exactly like any other idle round, and the
-- pending set is released on expiry or the moment work/sleep takes over.
-- Returns false when no set is near so the caller falls back to rest.
function Controller:beginAmbientWatch(ticks)
    if self.base == nil or self.character == nil
        or ticks < (self.nextWatchAt or 0) then
        return false
    end
    if not self.character:getCharacterActions():isEmpty() then return false end
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    if queue ~= nil and queue.current ~= nil then return false end
    local here = self.character:getCurrentSquare()
    if here == nil then return false end
    local set = self:findBaseTelevision()
    if set == nil then
        self.nextWatchAt = ticks + 1800
        return false
    end
    local dx = set.square:getX() - here:getX()
    local dy = set.square:getY() - here:getY()
    if set.square:getZ() ~= here:getZ() or dx * dx + dy * dy > 36 then
        self.nextWatchAt = ticks + 1800
        return false
    end
    local wasOn = self:isTelevisionOn(set.object)
    -- Only the set we switch on ourselves is ever switched back off, so a
    -- television the player left running is never killed under them.
    local turnedOn = false
    if wasOn ~= true then
        turnedOn = self:setTelevisionPower(set.object, true)
    end
    if wasOn ~= true and turnedOn ~= true then
        -- Still dark (broken set, power died mid-scan): no staring at a
        -- dead screen, take other leisure instead.
        self.nextWatchAt = ticks + 1800
        return false
    end
    pcall(function() self.character:faceThisObject(set.object) end)
    self.consecutiveAutoTasks = 0
    self.nextWatchAt = ticks + 3600
    self.activeDecision = "base_ambient_watch"
    self.state = "BASE_IDLE"
    self.nextThink = ticks + 1200 + Controller.baseIdleJitter(self.id)
    self.pendingWatch = { object = set.object, turnedOn = turnedOn,
        untilTick = self.nextThink }
    sayDialogue(self.character, self.id, "base_idle", ticks, 1800)
    self:diag("social", "ambient_watch", nil)
    return true
end

-- Follower company: idle survivors in formation (or holders, or grouped
-- survivors at a halt) turn toward their leader and keep light company
-- instead of flat-standing. Player-bound company trades the
-- personality-aware player_talk lines (dead content after recruitment);
-- NPC-bound company stays silent facing. Cosmetic only: no movement, no
-- actions, no state changes beyond facing, so stealth, combat and
-- directives skip entirely and the caller's wait state still owns the
-- next think. Only settled company counts: the leader must have held the
-- same square since the previous think, otherwise they are mid-stride and
-- facing would snap.
function Controller:beginFollowerCompany(ticks, targetChar, withLines)
    if targetChar == nil or self.character == nil then return false end
    if self.combatTarget ~= nil or self.companionDirective ~= nil then return false end
    if shouldRemainStealthy(self) then return false end
    if not self.character:getCharacterActions():isEmpty() then return false end
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    if queue ~= nil and queue.current ~= nil then return false end
    local here = self.character:getCurrentSquare()
    local there = targetChar:getCurrentSquare()
    if here == nil or there == nil or there:getZ() ~= here:getZ() then return false end
    local dx = there:getX() - here:getX()
    local dy = there:getY() - here:getY()
    if dx * dx + dy * dy > 64 then return false end
    local key = tostring(there:getX()) .. "," .. tostring(there:getY())
        .. "," .. tostring(there:getZ())
    local settled = self.lastCompanyLeaderKey == key
    self.lastCompanyLeaderKey = key
    if settled ~= true then return true end
    pcall(function() self.character:faceThisObject(targetChar) end)
    if withLines ~= true or ticks < (self.nextCompanyAt or 0) then return true end
    self.nextCompanyAt = ticks + 1800
    local phase = math.floor((tonumber(ticks) or 0) / 900)
        + Controller.baseIdleJitter(self.id)
    if phase % 3 == 0 then
        sayDialogue(self.character, self.id, "player_talk", ticks, 2400)
    end
    self:diag("social", "follower_company", nil)
    return true
end

-- Native rest remains the fallback when there is no suitable readable book.
-- Use the best available chair or bed through the game's sit/rest actions.
function Controller:beginAmbientBaseRest(ticks)
    if self:beginBaseRecreation(ticks) then return true end
    -- Smoke break first for smokers and stressed survivors: the native eat
    -- action owns stress/unhappiness relief exactly like the player, then
    -- the next think settles them into their seat.
    if ticks >= (self.nextSmokeAt or 0) and KnoxSurvivorNeeds.smokeMotive ~= nil
        and KnoxSurvivorNeeds.smokeMotive(self.character) then
        local smoke = KnoxSurvivorNeeds.findSmokeItem ~= nil
            and KnoxSurvivorNeeds.findSmokeItem(self.character) or nil
        if smoke ~= nil then
            local state = KnoxSurvivorNeeds.snapshot(self.character)
            local action, _, intent = KnoxSurvivorNeeds.execute(self.character, {
                kind = "smoke", item = smoke, state = state,
            })
            if action ~= nil and action ~= false then
                self.selfCareIntent = intent
                self.activeDecision = "base_ambient_smoke"
                self.state = "TIMED_ACTION"
                self.stateStartedAt = ticks
                self.nextSmokeAt = ticks + 3600
                sayDialogue(self.character, self.id, "base_snack", ticks, 1800)
                self:diag("social", "ambient_smoke", nil)
                return true
            end
        end
        self.nextSmokeAt = ticks + 1800
    end
    self.activeDecision = "base_ambient_rest"
    self.ambientRest = true
    local spot = findBestRestSpot(self)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:beginCompanionRelax(ticks)
    self.activeDecision = "companion_relax"
    self.ambientRest = true
    local spot = findBestRestSpot(self)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:updateCompanionRelax(ticks)
    if self.companionOrder ~= "relax" then
        self:finishDecision(ticks)
        return
    end
    if ticks < self.nextThink then return end
    self.nextThink = ticks + Controller.TUNING.RECOVERY_RECHECK_TICKS
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    local kind = decision.kind
    if (kind == "eat" or kind == "drink" or kind == "bandage"
        or kind == "improvise_medical" or kind == "sleep")
        and Controller.selfCareReady(self.selfCareRetryAt, kind, ticks) then
        self:finishDecision(ticks)
        self.nextThink = ticks
    end
    -- Sitting is persistent native posture, not a timed action to restart.
    -- Combat is checked before this state; ordinary rechecks leave it intact.
end

function Controller:beginRecovery(decision, ticks)
    self.activeDecision = decision
    self.recoveryStarted = ticks
    self.selfCareIntent = {
        kind = decision,
        before = KnoxSurvivorNeeds.snapshot(self.character),
    }
    local spot = findBestRestSpot(self, decision == "sleep", function(square)
        return self:allowNeedDetour(square, ticks, false)
    end)
    if spot ~= nil and not self:allowNeedDetour(spot.approach, ticks) then spot = nil end
    if spot ~= nil and reserve(
        self.reservations,
        "restSpots",
        spot.object,
        self.id
    ) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=MOVING_TO_REST furniture=" .. spot.bedType
                    .. " quality=" .. tostring(spot.quality)
            )
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false)
    return true
end

-- Faction residents use the shared duty schedule, but their scheduled sleep
-- must reach the native sleep/assigned-bed path. Player-owned base schedules
-- retain their existing ambient-rest behavior in this bounded correction.
function Controller:beginScheduledBaseSleep(ticks)
    self:releaseLights()
    if self.base ~= nil and self.base.ownerKind == "faction" then
        return self:beginRecovery("sleep", ticks)
    end
    return self:beginAmbientBaseRest(ticks)
end

function Controller:finishDecision(ticks)
    self:closeOpenedDoors()
    self:releaseBaseCooking()
    self:releaseBaseRecreation()
    self:releaseBaseHygiene()
    self:releaseGroupSupport()
    self:releaseAmbientMovement()
    self.pendingCleanup = nil
    self.pendingDepositTrip = nil
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    if self.activeDecision == "rest" or self.activeDecision == "sleep"
        or self.activeDecision == "base_ambient_rest"
        or self.activeDecision == "camp_ambient_rest"
        or self.activeDecision == "companion_relax" then
        self:leaveRecoveryPosture()
    end
    self.ambientRest = nil
    self.selfCareIntent = nil
    KnoxPersistence.captureActiveSurvivor(self.id)
    self.regroupMember = nil
    self.activeDecision = nil
    self.state = "IDLE"
    local stayingWithGroup = self.companionOrder == "follow"
        or self.groupLeader ~= nil
        or #(self.groupMembers or {}) > 1
    -- Grouped survivors re-decide quickly, but never faster than a full think
    -- interval, or success paths flap follow->combat->follow every few ticks.
    local proposedThink = stayingWithGroup
        and (ticks + THINK_MIN_TICKS)
        or (ticks + THINK_MIN_TICKS + ZombRand(Controller.TUNING.THINK_JITTER_TICKS))
    -- A failure handler may already have installed a longer retry delay. Keep
    -- that delay so a group route cannot hammer the same cooled-down edge.
    self.nextThink = math.max(self.nextThink or 0, proposedThink)
    self:resetMovementRecovery()
end

-- Streaming can briefly remove a shell's current square before the population
-- owner captures it. If the square returns first, do not leave the controller in
-- DETACHED with stale route/combat/action ownership. Persistent duty is held in
-- the companion/group/base/camp fields and is deliberately not changed here.
function Controller:recoverFromDetached(ticks)
    if self.state ~= "DETACHED" or self.character == nil
        or self.character:getCurrentSquare() == nil then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.selfCareIntent ~= nil then
        local kind = tostring(self.selfCareIntent.kind or self.activeDecision or "unknown")
        self.selfCareRetryAt = self.selfCareRetryAt or {}
        self.selfCareRetryAt[kind] = math.max(
            self.selfCareRetryAt[kind] or 0,
            ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
        )
    end
    self:abandonBaseTask("detached_recovered")
    self:releaseCombat()
    self:clearFirearmCombatState()
    self:cancelRobbery(ticks, "detached_recovered")
    self:releaseSupply()
    self:releaseGroupSupport()
    self:releaseRestSpot()
    self.selfCareIntent = nil
    self.pendingCleanup = nil
    self.pendingDepositTrip = nil
    self.activeDecision = nil
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.state = "IDLE"
    self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " detached-recovered=true")
    return true
end

function Controller:interruptSelfCareForDanger(ticks)
    if self.pendingHygiene ~= nil then
        self:releaseBaseHygiene()
        self.activeDecision,self.state=nil,"IDLE"
        return true
    end
    if self.pendingOrganize ~= nil then
        self:releaseBaseOrganize()
        self.activeDecision,self.state=nil,"IDLE"
        return true
    end
    if self.pendingRecreation~=nil then
        self:releaseBaseRecreation()
        self.activeDecision,self.state=nil,"IDLE"
        return true
    end
    if self.state == "INVENTORY_CLEANUP" or self.state == "MOVING_TO_DEPOSIT" then
        if self.state == "MOVING_TO_DEPOSIT" then self.bridge:cancelNpcMove(self.id) end
        ISTimedActionQueue.clear(self.character)
        self.pendingCleanup = nil
        self.pendingDepositTrip = nil
        self.nextCleanupAt = ticks + 600
        self.activeDecision = nil
        self.state = "IDLE"
        return true
    end
    local selfCare = self.state == "TIMED_ACTION"
        or self.state == "MOVING_TO_REST"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "SLEEPING_RECOVERY"
    if not selfCare then
        return false
    end
    local interrupted = self.activeDecision
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:cancelNpcMove(self.id)
    self:leaveRecoveryPosture()
    self.selfCareInterrupted = interrupted
    self.selfCareIntent = nil
    self.activeDecision = nil
    self.state = "IDLE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " self-care-interrupted=" .. tostring(interrupted)
            .. " reason=immediate_danger tick=" .. tostring(ticks)
    )
    return true
end

-- Standing through a native reload while a zombie closes to biting range gets
-- survivors bitten. Point-blank threats fight hands-on; a reload that never
-- resolves (no compatible magazine, jammed gun) falls back after a bounded
-- number of yields instead of looping shoot-empty/reload forever.
-- Native magazine loading is animation-driven (duration=-1), and several
-- preparation checks can occur in one update. Budget elapsed controller ticks,
-- never call count. This also bounds a native action that never completes.
local RELOAD_PREPARATION_TIMEOUT_TICKS = 1800
-- Bounded consecutive native ranged COMBAT_FAILED results (approach/pursuit
-- failure) before the encounter falls back to melee through the existing owner.
Controller.RANGED_COMBAT_FAILURE_FALLBACK_STREAK = 2

local function reloadThreatClose(character, target)
    if character == nil or target == nil then return false end
    local ok, close = pcall(function()
        if character:getZ() ~= target:getZ() then return false end
        local dx = character:getX() - target:getX()
        local dy = character:getY() - target:getY()
        return dx * dx + dy * dy <= THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS
    end)
    return ok and close == true
end

-- Feed every reloading/needs_preparation yield through here. Returns a melee
-- reason when standing through preparation is wrong, nil to keep yielding.
function Controller:reloadYieldDecision(ticks, target, firearmState)
    if firearmState ~= "reloading" and firearmState ~= "needs_preparation" then
        self.reloadYieldStreak = 0
        self.reloadPreparationStartedAt = nil
        self.reloadYieldTarget = nil
        self.reloadYieldWeaponKey = nil
        return nil
    end
    if reloadThreatClose(self.character, target) then
        return "close_threat"
    end
    -- Key the bounded budget to the exact encounter weapon and target. A new
    -- target, a different gun, or a fresh engagement after teardown starts a
    -- new preparation window instead of inheriting a stale elapsed clock from
    -- an earlier reload that already ended.
    local weapon = nil
    pcall(function() weapon = self.character:getPrimaryHandItem() end)
    local weaponKey = weapon ~= nil
        and safeMethod(weapon, "getID", nil) or nil
    if weaponKey == nil and weapon ~= nil then
        weaponKey = safeMethod(weapon, "getFullType", nil)
    end
    weaponKey = weaponKey ~= nil and tostring(weaponKey) or nil
    if self.reloadYieldTarget ~= target or self.reloadYieldWeaponKey ~= weaponKey then
        self.reloadYieldTarget = target
        self.reloadYieldWeaponKey = weaponKey
        self.reloadPreparationStartedAt = nil
        self.reloadYieldStreak = 0
    end
    ticks = tonumber(ticks) or self.currentTicks or 0
    if self.reloadYieldStreak == 0 or self.reloadPreparationStartedAt == nil then
        self.reloadPreparationStartedAt = ticks
    end
    self.reloadYieldStreak = 1
    if ticks - self.reloadPreparationStartedAt >= RELOAD_PREPARATION_TIMEOUT_TICKS then
        return "reload_stalled"
    end
    return nil
end

function Controller:forceMeleeFallback(ticks, target, reason)
    if KnoxFirearmSupport.cancelPreparation ~= nil then
        KnoxFirearmSupport.cancelPreparation(self.character)
    end
    local fallbackResult = KnoxFirearmSupport.fallbackToMelee ~= nil
        and KnoxFirearmSupport.fallbackToMelee(self.id, self.bridge, self.character)
        or "melee_bridge_unavailable"
    self.reloadYieldStreak = 0
    self.reloadPreparationStartedAt = nil
    self.rangedEncounterTarget = nil
    self.rangedCombatFailureStreak = 0
    if target ~= nil then
        self.rangedFallbackUntil = self.rangedFallbackUntil
            or setmetatable({}, { __mode = "k" })
        self.rangedFallbackUntil[target] = ticks + THREAT_FAILURE_COOLDOWN_TICKS
    end
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " reload-fallback reason=" .. tostring(reason)
        .. " result=" .. tostring(fallbackResult))
    return fallbackResult
end

-- An armed survivor must never enter the native loop empty-handed: misses the
-- equip and the engine shoves instead of swinging. Pulls bagged melee to the
-- top-level inventory first so the equip bridge can see it.
function Controller:ensureMeleeHands(target)
    local armed = false
    if self.character ~= nil then
        local ok, primary = pcall(function() return self.character:getPrimaryHandItem() end)
        if not ok then
            -- No hand slot to inspect (unit mocks only). Fail open: live
            -- characters always expose the primary hand.
            return true, "primary_unverifiable"
        end
        if primary ~= nil then
            local valid, usable = pcall(function()
                return primary:IsWeapon() and not primary:isRanged() and not primary:isBroken()
            end)
            armed = valid == true and usable == true
        end
    end
    if armed then return true, "already_armed" end
    if KnoxFirearmSupport.pullMeleeToHands == nil then
        return false, "melee_pull_unavailable"
    end
    local ok, result = KnoxFirearmSupport.pullMeleeToHands(self.id, self.character, self.bridge)
    if ok then return true, result end
    if KnoxFirearmSupport.findCarriedMelee ~= nil
        and KnoxFirearmSupport.findCarriedMelee(self.character) ~= nil then
        return false, "melee_equip_failed:" .. tostring(result)
    end
    return false, "unarmed_no_carried_melee"
end

function Controller:beginCombat(target)
    local awareness = self.pendingThreatAwareness
    if target == nil or target:getCurrentSquare() == nil then
        return false
    end
    -- A threat makes a temporary overnight stop unsafe. The group keeps its
    -- membership, but the leader releases this one shelter objective before
    -- normal combat ownership takes over.
    if self.groupLeaderId == nil and self.groupObjective ~= nil
        and self.groupObjective.kind == "night_shelter" then
        local group = KnoxPersistence.getTravelGroupFor(self.id)
        if group ~= nil and group.leaderId == self.id then
            KnoxPersistence.clearTravelGroupObjective(group.id, self.id)
            self:clearLifeIntent()
            self.groupObjective = nil
        end
    end
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    local now = self.currentTicks or self.nextThreatScan or 0
    -- A zombie or a different hostile survivor interrupts the robbery. The
    -- victim's bounded hold is released before ordinary combat takes ownership.
    if self.pendingRobbery ~= nil and target ~= self.pendingRobbery.victim then
        self:cancelRobbery(now, "combat_interrupt")
    end
    if self.pendingRobberyHold ~= nil then
        self:releaseRobberyHold(nil, now, "combat_interrupt")
    end
    local heldItem = self.character:getPrimaryHandItem()
    if self.unarmedRetryUntil ~= nil then
        if heldItem == self.rejectedCombatItem and now < self.unarmedRetryUntil then
            return false
        end
        self.unarmedRetryUntil = nil
        self.rejectedCombatItem = nil
        if self.unarmedRejectedTarget ~= nil then
            self.failedThreats[self.unarmedRejectedTarget] = nil
            self.unarmedRejectedTarget = nil
        end
    end
    self:cancelTrade("combat")
    if awareness == nil then
        awareness = evaluateThreat(self, target, self.nextThreatScan or 0)
    end
    if awareness == nil or not reserveThreat(
        self.reservations,
        target,
        self.id,
        awareness.attackerLimit
    ) then
        return false
    end
    self:interruptSelfCareForDanger(self.nextThreatScan or 0)
    -- Firearms use the game's timed reload action.  Do this before clearing other
    -- actions so an already-running reload is allowed to finish instead of being
    -- cancelled and restarted every threat scan.
    local retainRanged = self.rangedEncounterTarget == target
    local firearmState, firearmResult
    if self.rangedFallbackUntil ~= nil
        and (self.rangedFallbackUntil[target] or 0) > (self.currentTicks or 0) then
        -- Keep the close-range fallback long enough to finish a melee attempt.
        -- Otherwise the next threat scan immediately selects the same gun again.
        firearmState = "melee"
        firearmResult = KnoxFirearmSupport.fallbackToMelee(
            self.id, self.bridge, self.character
        )
    else
        firearmState, firearmResult = KnoxFirearmSupport.prepareForThreat(
            self.id, self.character, self.bridge, target, retainRanged
        )
    end
    if firearmState == "reloading" then
        local fallbackReason = self:reloadYieldDecision(
            self.currentTicks or 0, target, firearmState
        )
        if fallbackReason ~= nil then
            firearmState = "melee"
            firearmResult = self:forceMeleeFallback(
                self.currentTicks or 0, target, fallbackReason
            )
        else
            releaseThreat(self.reservations, target, self.id)
            self.nextThreatScan = (self.nextThreatScan or 0) + COMBAT_RANGED_YIELD_DELAY_TICKS
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " firearm=" .. tostring(firearmState)
                    .. " result=" .. tostring(firearmResult)
            )
            return false
        end
    end
    if firearmState == "melee" then
        self.rangedEncounterTarget = nil
        local armed, armResult = self:ensureMeleeHands(target)
        if not armed and armResult ~= "unarmed_no_carried_melee" then
            releaseThreat(self.reservations, target, self.id)
            self.failedThreats[target] = (self.nextThreatScan or 0)
                + THREAT_FAILURE_COOLDOWN_TICKS
            self:recordFailure("combat:" .. tostring(armResult),
                self.nextThreatScan or 0, THREAT_FAILURE_COOLDOWN_TICKS)
            return false
        end
        if not armed then
            print("[KnoxSurvivors][Autonomy] id=" .. self.id
                .. " combat_unarmed_last_resort target=" .. tostring(target))
        end
    else
        -- A ready firearm commits this encounter to the ranged class until a
        -- real invalidation; a fresh ranged-failure streak is recorded.
        self.reloadYieldStreak = 0
        self.rangedEncounterTarget = target
        self.rangedCombatFailureStreak = 0
    end
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseGroupSupport()
    self:suspendBaseTaskForThreat("combat_interrupt")
    self:leaveRecoveryPosture()
    local approach = nil
    -- Reuse the last approach tile when re-engaging the same stationary
    -- target (e.g. after a reload yield). Recomputing the nearest neighbour
    -- each time shifts the destination even when nothing moved.
    if target == self.lastCombatTarget and self.lastCombatApproachX ~= nil then
        local targetSquare = target:getCurrentSquare()
        local cachedTargetX = tonumber(self.lastCombatTargetX)
        local cachedTargetY = tonumber(self.lastCombatTargetY)
        if targetSquare ~= nil and cachedTargetX ~= nil and cachedTargetY ~= nil then
            local moved2 = (targetSquare:getX() - cachedTargetX) ^ 2
                + (targetSquare:getY() - cachedTargetY) ^ 2
            if moved2 <= Controller.TUNING.COMBAT_APPROACH_REUSE_DISTANCE_SQUARED
                and targetSquare:getZ() == (tonumber(self.lastCombatTargetZ) or targetSquare:getZ()) then
                local cell = getCell ~= nil and getCell() or nil
                local cached = cell ~= nil and cell:getGridSquare(
                    self.lastCombatApproachX, self.lastCombatApproachY, self.lastCombatApproachZ) or nil
                local current = self.character:getCurrentSquare()
                if cached ~= nil and (cached == current or cached:canStand()) then
                    approach = cached
                end
            end
        end
    end
    if approach == nil then
        approach = combatApproachSquare(self.character, target)
    end
    if approach == nil then
        releaseThreat(self.reservations, target, self.id)
        return false
    end
    local aimSettleTicks = 18
    if KnoxFirearmSupport.aimSettleTicks ~= nil then
        aimSettleTicks = KnoxFirearmSupport.aimSettleTicks(self.id, self.character)
    end
    local result
    if self.bridge.beginNpcLiveCombatWithAim ~= nil then
        result = tostring(self.bridge:beginNpcLiveCombatWithAim(
            self.id, target, approach, aimSettleTicks
        ))
    else
        result = tostring(self.bridge:beginNpcLiveCombat(self.id, target, approach))
    end
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        self.bridge:resetNpcCombat(self.id)
        local noWeapon = string.find(result, "NO_EQUIPPED_WEAPON", 1, true) ~= nil
        if noWeapon then
            self.unarmedCombatBlocked = true
            self.rejectedCombatItem = self.character:getPrimaryHandItem()
            self.unarmedRejectedTarget = target
            self.unarmedRetryUntil = now + THREAT_FAILURE_COOLDOWN_TICKS
        end
        local retry = THREAT_FAILURE_COOLDOWN_TICKS
        self.failedThreats[target] = self.nextThreatScan + retry
        releaseThreat(self.reservations, target, self.id)
        self:diag("combat", "combat_start_failed", {
            reason = tostring(result),
            firearm = tostring(firearmState),
        })
        self:recordFailure(
            "combat_start:" .. result,
            self.nextThreatScan,
            retry
        )
        -- An unarmed survivor must immediately change survival mode after the
        -- native combat bridge rejects the attack. Waiting for another threat
        -- scan leaves them stationary in the bite zone.
        if noWeapon then
            local flee, assessment = self:assessFlee()
            if flee then
                self:beginFlee(now, assessment)
            end
        end
        return false
    end
    self.unarmedCombatBlocked = nil
    self:releaseSupply()
    self.combatTarget = target
    self:soundBaseAlarm(targetSquare)
    -- Remember the approach for the reuse check above on the next engagement.
    local targetSquare = target:getCurrentSquare()
    if targetSquare ~= nil and approach ~= nil and approach.getX ~= nil then
        self.lastCombatTarget = target
        self.lastCombatTargetX = targetSquare:getX()
        self.lastCombatTargetY = targetSquare:getY()
        self.lastCombatTargetZ = targetSquare:getZ()
        self.lastCombatApproachX = approach:getX()
        self.lastCombatApproachY = approach:getY()
        self.lastCombatApproachZ = approach:getZ()
    end
    self.activeDecision = "fight"
    self.state = "COMBAT"
    self.reloadYieldStreak = 0
    sayDialogue(self.character, self.id, "combat", self.nextThreatScan or 0, 900)
    awareness = awareness or {}
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id .. " state=COMBAT " .. result
            .. " awareness=" .. tostring(awareness.reason or "unknown")
            .. " distance=" .. tostring(awareness.distance or "unknown")
    )
    local targetKind = "unknown"
    pcall(function()
        if instanceof ~= nil and instanceof(target, "IsoZombie") then
            targetKind = "zombie"
        elseif rawget(_G, "KnoxSurvivorRuntime") ~= nil
            and KnoxSurvivorRuntime.idForCharacter ~= nil
            and KnoxSurvivorRuntime.idForCharacter(target) ~= nil then
            targetKind = "survivor"
        elseif target ~= nil and target.isZombie ~= nil and target:isZombie() then
            targetKind = "zombie"
        end
    end)
    self:diag("combat", "combat_started", {
        targetKind = targetKind,
        firearm = tostring(firearmState),
        detail = tostring(firearmResult),
        distance = awareness.distance,
        reason = awareness.reason,
    })
    self.pendingThreatAwareness = nil
    return true
end

function Controller:beginWorldSearch(goal, ticks)
    self:setLifeIntent(goal, "seeking", nil, nil)
    if ticks < self.nextWorldSearch then
        return false
    end
    local supply = findSupply(self, goal, ticks)
    if supply == nil then
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        if goal == "find_water" then
            self.waterSearchMisses = (self.waterSearchMisses or 0) + 1
            if self.waterSearchMisses >= 3 then
                self.waterSearchMisses = 0
                local line = "I can't find drinkable water here."
                if not self:sayAction({ line }, ticks, 1800) then
                    KnoxActivityFeed.speak(self.character, line)
                end
                self:recordFailure("water_source_unavailable", ticks, SUPPLY_RETRY_TICKS)
            end
        end
        return false
    end
    self.waterSearchMisses = 0
    local reservationKind = supply.waterSource ~= nil and "waterSources" or "items"
    local reservationTarget = supply.waterSource or supply.item
    if not reserve(self.reservations, reservationKind, reservationTarget, self.id) then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, supply.approach, "urgent"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        release(self.reservations, reservationKind, reservationTarget, self.id)
        if supply.container ~= nil then
            self.inspectedContainers[supply.container] = ticks + SUPPLY_RETRY_TICKS
        end
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        self:recordMovementFailure("supply_move", result, ticks, SUPPLY_RETRY_TICKS)
        return false
    end
    self.pendingSupply = supply
    self.activeDecision = goal
    self.state = "MOVING_TO_SUPPLY"
    self:setLifeIntent(
        goal,
        "traveling",
        supply.approach,
        roamDestinationKey(supply.waterSource ~= nil
            and supply.waterSource:getSquare()
            or supply.container:getSourceGrid())
    )
    local dialogueEvent = goal == "find_food" and "need_food"
        or (goal == "find_water" and "need_water"
            or (goal == "find_medical" and "need_medical" or "search"))
    if (goal == "find_food" or goal == "find_water")
        and not needCalloutIsCurrent(self.character, goal) then
        dialogueEvent = "search"
    end
    sayDialogue(self.character, self.id, dialogueEvent, ticks, 1800)
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " state=MOVING_TO_SUPPLY goal=" .. goal
        .. (supply.waterSource ~= nil and " source=world_water"
            or " item=" .. tostring(supply.item:getFullType())))
    return true
end

function Controller:beginWorldWaterAction(ticks)
    local pending = self.pendingSupply
    local source = pending ~= nil and pending.waterSource or nil
    local sourceSquare = source ~= nil and source:getSquare() or nil
    local approach = pending ~= nil and pending.approach or nil
    local currentSquare = self.character ~= nil and self.character:getCurrentSquare() or nil
    if source == nil or sourceSquare == nil or approach == nil or currentSquare == nil
        or sourceSquare:getZ() ~= currentSquare:getZ()
        or approach:getZ() ~= currentSquare:getZ()
        or distanceSquared(approach, currentSquare) > 2
        or self.combatTarget ~= nil or self.pendingThreatAwareness ~= nil
        or self.baseSupplyTrip == true or self.baseSupplyOrder ~= nil
        or self.companionOrder ~= nil or self.companionDirective ~= nil
        or self.groupLeaderId ~= nil or self.groupObjective ~= nil
        or nearestThreat(self, ticks) ~= nil
        or not Controller.waterSourceBoundaryContains(self, sourceSquare)
        or not self:allowNeedDetour(approach, ticks) then
        self:releaseSupply()
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        self:finishDecision(ticks)
        return false
    end
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    local state = KnoxSurvivorNeeds.snapshot(self.character)
    if decision == nil or decision.kind ~= "find_water" or state == nil then
        self:releaseSupply()
        self:finishDecision(ticks)
        return false
    end
    local action, result, intent = KnoxSurvivorNeeds.execute(self.character, {
        kind = "drink_world", source = source, state = state,
    })
    if action == nil or action == false then
        self:recordFailure("world_water_action:" .. tostring(result),
            ticks, Controller.TUNING.SELF_CARE_RETRY_TICKS)
        self.selfCareRetryAt.drink_world = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
        local line = result == "native_water_action_refused_full_inventory"
            and "I can't drink from that source right now."
            or "I couldn't use that water source."
        if not self:sayAction({ line }, ticks, 1800) then
            KnoxActivityFeed.speak(self.character, line)
        end
        self:releaseSupply()
        self:finishDecision(ticks)
        return false
    end
    self:sayNeedIfGrouped("drink", ticks)
    self.activeDecision = "drink_world"
    self.selfCareIntent = intent
    self.selfCareInterrupted = nil
    self.state = "TIMED_ACTION"
    self.stateStartedAt = ticks
    return true
end

function Controller:releaseBaseHygiene()
    local plan = self.pendingHygiene
    if plan == nil then return end
    if KnoxBaseHygiene ~= nil and KnoxBaseHygiene.cancel ~= nil then
        KnoxBaseHygiene.cancel(self.character, plan, self.bridge, self.id)
    end
    self.pendingHygiene = nil
end

-- Field hygiene for followers: wash up at a nearby sink, tub or barrel
-- when visibly filthy and the party is idle. Same dirt bar, plan/step
-- machinery and BASE_HYGIENE state as base washing, so threats, timeouts
-- and danger interrupts behave identically; only the water search is a
-- field radius instead of base territory. Never roams for water: a dry
-- area simply falls through to other idle.
function Controller:beginFollowerHygiene(ticks)
    if KnoxBaseHygiene == nil or KnoxBaseHygiene.beginNear == nil
        or self.baseTask ~= nil or self.pendingHygiene ~= nil
        or ticks < (self.nextHygieneAt or 0) then return false end
    if self.combatTarget ~= nil or self.companionDirective ~= nil then return false end
    if shouldRemainStealthy(self) then return false end
    if self.character == nil then return false end
    if not self.character:getCharacterActions():isEmpty() then return false end
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    if queue ~= nil and queue.current ~= nil then return false end
    self.nextHygieneAt = ticks + 3600
    local plan = KnoxBaseHygiene.beginNear(self.character, 16, self.bridge, self.id, ticks)
    if plan == nil then
        self.nextHygieneAt = ticks + 7200
        return false
    end
    self.pendingHygiene = plan
    self.hygieneStartedAt = ticks
    self.activeDecision, self.state = "washing", "BASE_HYGIENE"
    return true
end

function Controller:beginBaseHygiene(ticks)
    if KnoxBaseHygiene == nil or self.base == nil or self.baseTask ~= nil
        or ticks < (self.nextHygieneAt or 0)
        or not KnoxBaseManager.containsSquare(self.base, self.character:getCurrentSquare())
        or not self.character:getCharacterActions():isEmpty() then return false end
    self.nextHygieneAt = ticks + 3600
    local plan = KnoxBaseHygiene.begin(self.character, self.base, self.bridge, self.id, ticks)
    if plan == nil then
        self.nextHygieneAt = ticks + 7200
        return false
    end
    self.pendingHygiene = plan
    self.hygieneStartedAt = ticks
    self.activeDecision, self.state = "washing", "BASE_HYGIENE"
    return true
end

function Controller:updateBaseHygiene(ticks)
    local plan = self.pendingHygiene
    if plan == nil then self:finishDecision(ticks); return end
    local outcome, reason = KnoxBaseHygiene.step(plan, self.character, self.bridge, self.id, ticks)
    if ticks - (self.hygieneStartedAt or ticks) > 9000 then outcome, reason = "failed", "wash_session_timeout" end
    if outcome ~= "working" then
        self:releaseBaseHygiene()
        self.nextHygieneAt = ticks + (outcome == "complete" and 10800 or 3600)
        if outcome == "failed" then self:recordFailure("base_hygiene:" .. tostring(reason), ticks, 3600) end
        self:finishDecision(ticks)
    end
end

local function baseTaskTargetSquare(self)
    local task = self.baseTask
    local target = task ~= nil and task.target or nil
    local cached = self.baseTaskBarricadeTarget or self.baseTaskCorpseTarget
        or self.baseTaskRepairTarget or self.baseTaskWoodcuttingTarget
        or self.baseTaskFarmingTarget
    local square = cached ~= nil and (cached.approach or cached.square
        or cached.dropSquare or cached.corpseSquare) or nil
    if square ~= nil then return square end
    if target == nil or getCell == nil or getCell() == nil then return nil end
    local x = tonumber(target.x or target.corpseX or target.dropX or target.x1)
    local y = tonumber(target.y or target.corpseY or target.dropY or target.y1)
    local z = tonumber(target.z or target.corpseZ or target.dropZ) or 0
    return x ~= nil and y ~= nil and getCell():getGridSquare(x, y, z) or nil
end

-- A work move blocked by a locked door tries a nearby window first via the
-- shared alternate-entry machinery (open, climb, smash as a last resort),
-- then falls back to door breaking. The synthetic pendingSupply carries only
-- the task destination for entry search and is cleared on resume/failure so
-- real supply trips never see it.
function Controller:beginBaseTaskWindowDetour(ticks)
    if self.baseTask == nil or self.entryDetour ~= nil then return false end
    if self.baseTask.type == "haul_corpse"
        and self.baseTaskCorpsePhase == "drop" then
        return false
    end
    if self.pendingSupply ~= nil then return false end
    local targetSquare = baseTaskTargetSquare(self)
    local approach = KnoxBaseJobs.resolveTaskSquare(self.baseTask, self.character)
    if targetSquare == nil or approach == nil then return false end
    self.pendingSupply = {
        targetSquare = targetSquare,
        approach = approach,
        entryAttempts = {},
        entryAttemptCount = 0,
        taskEntry = true,
    }
    if not self:beginWindowDetour(ticks, "BASE_TASK_MOVE") then
        self.pendingSupply = nil
        return false
    end
    self:diag("jobs", "task_window_detour", self:diagTaskSnapshot(self.baseTask))
    return true
end

-- Assigned job materials follow a real container approach, not the work-site
-- target used by beginBaseTaskWindowDetour. Reuse the same bounded entry
-- search while keeping this exact item/container lease through a quiet entry.
function Controller:beginBaseTaskSupplyWindowDetour(ticks)
    local transfer = self.baseTaskSupplyTransfer
    local source = transfer ~= nil and transfer.source or nil
    local container = source ~= nil and source.container or nil
    local approach = transfer ~= nil and transfer.approach or nil
    local targetSquare = source ~= nil and source.square or nil
    if targetSquare == nil and container ~= nil
        and type(container.getSourceGrid) == "function" then
        targetSquare = container:getSourceGrid()
    end
    if self.state ~= "BASE_TASK_SUPPLY_MOVE" or self.baseTask == nil
        or container == nil or targetSquare == nil or approach == nil
        or self.pendingSupply ~= nil or self.entryDetour ~= nil then
        return false
    end
    self.pendingSupply = {
        container = container,
        targetSquare = targetSquare,
        approach = approach,
        entryAttempts = {},
        entryAttemptCount = 0,
        taskSupplyEntry = true,
    }
    if self:beginWindowDetour(ticks, "BASE_TASK_SUPPLY_MOVE") then
        self:diag("jobs", "task_supply_window_detour", self:diagTaskSnapshot(self.baseTask))
        return true
    end
    return false
end

-- Window options exhausted (or the crossing failed): clear the synthetic
-- entry context and try the door break before giving up on the task.
function Controller:fallbackTaskEntryToDoorBreak(ticks)
    if self.pendingSupply ~= nil and self.pendingSupply.taskSupplyEntry == true then
        if self.baseTask == nil then
            self.pendingSupply = nil
            return false
        end
        local resumeState = self.entryDetour ~= nil
            and self.entryDetour.resumeState or "BASE_TASK_SUPPLY_MOVE"
        self.entryDetour = nil
        if self:beginLockedDoorBreak(ticks, resumeState, true) then
            return true
        end
        self.pendingSupply = nil
        self:failBaseTaskAction(ticks, "assigned_supply_entry_unavailable")
        return true
    end
    if self.pendingSupply == nil or self.pendingSupply.taskEntry ~= true then
        return false
    end
    self.entryDetour = nil
    self.pendingSupply = nil
    if self.baseTask == nil then return false end
    return self:beginBaseTaskLockedDoorBreak(ticks)
end

-- A resident working inside its own settlement must not stare at a locked
-- door forever. Reuse the native door-combat transition for the current
-- blocked route, then resolve the task target again after the door is gone.
-- Structure ownership, melee weapon, endurance, and protected-safehouse gates
-- remain authoritative through canForceEntry.
function Controller:beginBaseTaskLockedDoorBreak(ticks)
    if self.baseTask == nil or self.entryDetour ~= nil then return false end
    if self.baseTask.type == "haul_corpse"
        and self.baseTaskCorpsePhase == "drop" then
        return false
    end
    local structureSquare = baseTaskTargetSquare(self)
    if not canForceEntry(self, structureSquare) then return false end
    local result = tostring(self.bridge:beginNpcLockedDoorCombat(self.id))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        return false
    end
    self.entryDetour = {
        resumeState = "BASE_TASK_MOVE",
        baseTask = true,
    }
    self.state = "BREAKING_LOCKED_DOOR"
    self.stateStartedAt = ticks
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " base-task-entry=break-door task=" .. tostring(self.baseTask.type))
    return true
end

function Controller:resumeAfterBaseTaskDoorBreak(ticks)
    if self.entryDetour == nil or self.entryDetour.baseTask ~= true
        or self.baseTask == nil then
        return false
    end
    self.entryDetour = nil
    self.baseTaskMoveRetryIssued = false
    if self:beginBaseTaskWorkMove(ticks) then return true end
    self:failBaseTaskAction(ticks, "door_break_resume_failed")
    return true
end

-- A need search may have been a short trip to assigned base storage.  Once the
-- real transfer finishes, start the native consume action in the same decision
-- cycle so a resident cannot end up carrying the answer while remaining in a
-- stale `find_food`/`find_water` state.
function Controller:beginImmediateNeedAction(kind, ticks)
    if kind ~= "find_food" and kind ~= "find_water" then return false end
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    if decision == nil
        or (kind == "find_food" and decision.kind ~= "eat")
        or (kind == "find_water" and decision.kind ~= "drink") then
        return false
    end
    if not Controller.selfCareReady(self.selfCareRetryAt, decision.kind, ticks) then
        return false
    end
    local action, result, intent = KnoxSurvivorNeeds.execute(
        self.character,
        decision
    )
    if action == nil or action == false then
        self.selfCareRetryAt[decision.kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
        self:recordFailure(
            "retrieved_need_action:" .. tostring(result),
            ticks,
            Controller.TUNING.SELF_CARE_RETRY_TICKS
        )
        return false
    end
    self:sayNeedIfGrouped(decision.kind, ticks)
    self.activeDecision = decision.kind
    self.selfCareIntent = intent
    self.selfCareInterrupted = nil
    self.state = "TIMED_ACTION"
    self.stateStartedAt = ticks
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=TIMED_ACTION kind=" .. decision.kind
            .. " source=retrieved_supply"
    )
    return true
end

function Controller:beginCompanionNeedDirective(ticks, directive)
    local kind = tostring(directive ~= nil and directive.kind or "")
    if kind ~= "find_food" and kind ~= "find_water" and kind ~= "find_medical"
        and kind ~= "find_weapon" and kind ~= "find_tools" and kind ~= "find_wood"
        and kind ~= "find_materials" and kind ~= "find_clothing" and kind ~= "find_ammo"
        and kind ~= "clean_inventory" then
        return false
    end
    if kind == "clean_inventory" then
        if self:beginInventoryCleanup(ticks) then return true end
        self.directiveMisses = (self.directiveMisses or 0) + 1
        if self.directiveMisses >= 3 then
            KnoxPersistence.clearCompanionDirective(
                self.id, self.companionOwnerId, currentWorldAgeHours()
            )
            self.companionDirective = nil
            self.directiveMisses = 0
            KnoxActivityFeed.speak(self.character, "My pack is in order.")
        else
            self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        end
        return true
    end
    if self:beginWorldSearch(kind, ticks) then
        return true
    end
    if ticks >= (self.nextWorldSearch or 0) then
        self.directiveMisses = (self.directiveMisses or 0) + 1
        if self.directiveMisses >= 3 then
            KnoxPersistence.clearCompanionDirective(
                self.id,
                self.companionOwnerId,
                currentWorldAgeHours()
            )
            self.companionDirective = nil
            self.directiveMisses = 0
            KnoxActivityFeed.speak(self.character,
                kind == "find_food" and "I couldn't find food here."
                    or (kind == "find_water" and "I couldn't find water here."
                        or (kind == "find_medical"
                            and "I couldn't find medical supplies here."
                            or (kind == "find_tools"
                                and "I couldn't find any useful tools here."
                                or (kind == "find_wood"
                                    and "I couldn't find any wood out there."
                                    or (kind == "find_materials"
                                        and "I couldn't find building materials."
                                        or (kind == "find_clothing"
                                            and "I couldn't find any clothing."
                                            or (kind == "find_ammo"
                                                and "I couldn't find any ammunition."
                                                or "I couldn't find a better weapon here."))))))))
        else
            self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        end
    end
    return true
end

function Controller.campIdleChoice(ticks, slot, canExcursion)
    local phase = (math.floor((ticks or 0) / Controller.TUNING.CAMP_DECISION_TICKS)
        + math.max(1, tonumber(slot) or 1) * 3) % 10
    if phase <= 1 then
        return "rest"
    end
    if phase <= 3 then
        return "reposition"
    end
    if phase <= 5 and canExcursion then
        return "excursion"
    end
    return "wait"
end

-- Keep idle residents from making identical random choices on the same tick.
-- The phase is deterministic per survivor, so save/load and controller refresh
-- do not synchronize an entire base into simultaneous pacing or resting.
function Controller.baseIdleJitter(id)
    local value = 17
    local text = tostring(id or "")
    for index = 1, #text do
        value = (value * 31 + string.byte(text, index)) % 2147483647
    end
    return value % 120
end

function Controller.baseIdleChoice(ticks, id, residentCount, mode)
    local phase = math.floor((tonumber(ticks) or 0) / 900)
        + Controller.baseIdleJitter(id)
        + math.max(0, tonumber(residentCount) or 0) * 2
    phase = phase % 12
    -- Scheduled recreation stays inside company time: stroll, sit, snack,
    -- chat, television. It never flat-stands through the window.
    if mode == "recreation" then
        if phase <= 2 then return "move" end
        if phase <= 5 then return "rest" end
        if phase <= 7 then return "snack" end
        if phase <= 9 then return "tv" end
        return "socialize"
    end
    if phase <= 3 then return "move" end
    if phase <= 5 then return "rest" end
    if phase <= 6 then return "snack" end
    if phase == 7 then return "tidy" end
    if phase <= 9 then return "socialize" end
    return "wait"
end

function Controller:beginCampMovement(ticks, returning)
    if self.camp == nil then
        return false
    end
    self:releaseCampPosition()
    local target = KnoxFactionCamps.positionFor(
        self.camp,
        self.campSlot + (self.campPositionCycle or 0),
        function(square)
            return reservedByOther(
                self.reservations,
                "campPositions",
                square,
                self.id
            )
        end
    )
    if target == nil or not reserve(
        self.reservations,
        "campPositions",
        target,
        self.id
    ) then
        self:recordFailure("camp_position_unavailable", ticks, Controller.TUNING.CAMP_POSITION_FAILURE_TICKS)
        return false
    end
    self.campPosition = target
    local current = self.character:getCurrentSquare()
    if current == target then
        self.activeDecision = "camp_idle"
        self.state = "CAMP_IDLE"
        self.nextThink = ticks + Controller.TUNING.CAMP_DECISION_TICKS
        return true
    end
    local result = tostring((moveWithTravelPace(
        self.bridge,
        self.id,
        self.character,
        target,
        returning and "return_home" or "local"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:releaseCampPosition()
        self:recordMovementFailure(
            returning and "camp_return" or "camp_reposition",
            result,
            ticks,
            Controller.TUNING.CAMP_POSITION_FAILURE_TICKS
        )
        return false
    end
    self.activeDecision = returning and "return_to_camp" or "camp_reposition"
    self.state = returning and "CAMP_RETURN" or "CAMP_REPOSITION"
    if returning then
        sayDialogue(self.character, self.id, "camp", ticks, 3600)
    end
    return true
end

function Controller:beginCampAmbientRest(ticks)
    self:releaseCampPosition()
    self.activeDecision = "camp_ambient_rest"
    self.ambientRest = true
    local spot = findBestRestSpot(self, false, function(square)
        return KnoxFactionCamps.contains(self.camp, square)
    end)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:beginCampExcursion(ticks)
    self:releaseCampPosition()
    self.campExcursion = true
    self.campExcursionExplored = false
    self.nextCampExcursion = ticks + Controller.TUNING.CAMP_EXCURSION_COOLDOWN_TICKS
    if self:beginRoam(ticks) then
        return true
    end
    self.campExcursion = false
    self.nextThink = math.max(
        self.nextThink or 0,
        ticks + Controller.TUNING.CAMP_POSITION_FAILURE_TICKS
    )
    return false
end

function Controller:signalFollowers(emote, ticks)
    if self.groupLeader ~= nil or #(self.groupMembers or {}) == 0
        or ticks < (self.nextLeaderEmoteAt or 0)
        or self.character.playEmote == nil
        or not self.character:getCharacterActions():isEmpty() then return false end
    local signals = rawget(_G, "KnoxOrderSignals")
    -- Keep autonomous leader orders readable too: nearby followers acknowledge
    -- the leader's existing gesture, but no signal changes durable AI state.
    local ok = signals ~= nil and signals.play(self.character, emote) == true
    if ok then
        local leaderSquare = safeMethod(self.character, "getCurrentSquare", nil)
        for _, member in ipairs(self.groupMembers or {}) do
            local memberSquare = member ~= nil and member ~= self.character
                and safeMethod(member, "getCurrentSquare", nil) or nil
            if leaderSquare ~= nil and memberSquare ~= nil
                and leaderSquare:getZ() == memberSquare:getZ()
                and navigationDistanceSquared(leaderSquare, memberSquare) <= 49 then
                signals.play(member, "yes")
            end
        end
        if emote == "followme" then
            self:sayAction({ "Stay close.", "Move out." }, ticks, 1800)
        elseif emote == "comehere" then
            self:sayAction({ "Regroup on me.", "With me." }, ticks, 1800)
        end
    end
    if ok then self.nextLeaderEmoteAt = ticks + 900 end
    return ok
end

function Controller:beginRoam(ticks, inheritedIntent)
    local current = self.character:getCurrentSquare()
    if current ~= nil then
        rememberRoamDestination(
            self,
            roamDestinationKey(current),
            ticks,
            Controller.TUNING.ROAM_GOAL_COOLDOWN_TICKS
        )
    end
    local target, key, kind = findRoamTarget(self, ticks)
    if target == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + Controller.TUNING.ROAM_NO_GOAL_RETRY_TICKS)
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "travel"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        rememberRoamDestination(self, key, ticks, Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS)
        self:recordMovementFailure("roam_move", result, ticks)
        return false
    end
    self:issueGroupLeaderOrder("follow", ticks)
    self:signalFollowers("followme", ticks)
    self.activeDecision = "roam"
    self.state = "ROAMING"
    self.roamGoalKey = key
    self.roamGoalKind = kind
    self:setLifeIntent(
        Controller.roamIntentKind(
            kind,
            inheritedIntent or (self.lifeIntent ~= nil and self.lifeIntent.kind or nil)
        ),
        "traveling",
        target,
        key
    )
    self.nextRoamNeedsCheck = ticks + Controller.TUNING.ROAM_NEEDS_RECHECK_TICKS
    self.forceTravel = false
    local dx, dy = target:getX() - current:getX(), target:getY() - current:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then self.roamHeading = { x = dx / length, y = dy / length } end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROAMING goal=" .. tostring(kind)
            .. " target=" .. target:getX() .. "," .. target:getY()
    )
    sayDialogue(self.character, self.id,
        kind == "building" and "roam_building" or "roam_area", ticks, 3600)
    return true
end

-- Night sheltering for unbased survivors: at night they head for the nearest
-- roof and sleep till dawn instead of roaming in the dark. Group leaders stay
-- with their people; based, camped, tasked, and ordered survivors are owned
-- by their own routines. Dawn wakes oversleepers so the day resumes.
-- Ordered takes, pair sorties, and paired followers loot for the settlement;
-- idle self-scavenging stays personal so survivors do not hoard.
function Controller:scavengingForSettlement()
    if (tonumber(self.scavengeSortieUntilHours or 0) or 0) > 0 then
        return true
    end
    return self.groupLeaderId ~= nil and self.groupObjective ~= nil
        and tostring(self.groupObjective.kind or "") == "scavenge"
end

local SCAVENGE_RETURN_BUFFER_HOURS = 0.25
local SCAVENGE_RETURN_RETRY_TICKS = 180

local function homeContainsCharacter(controller)
    local square = controller.character ~= nil
        and controller.character:getCurrentSquare() or nil
    if square == nil then return false end
    if controller.baseId ~= nil and controller.base ~= nil
        and KnoxBaseManager ~= nil and KnoxBaseManager.containsSquare ~= nil then
        return KnoxBaseManager.containsSquare(controller.base, square)
    end
    if controller.campId ~= nil and controller.camp ~= nil
        and KnoxFactionCamps ~= nil and KnoxFactionCamps.contains ~= nil then
        return KnoxFactionCamps.contains(controller.camp, square)
    end
    return false
end

local function returnScavengeSortie(controller, ticks)
    if homeContainsCharacter(controller) then
        controller.scavengeSortieUntilHours = nil
        controller.scavengeSortieReturning = nil
        controller.scavengeSortieReturnRetryAt = nil
        return false
    end
    controller.scavengeSortieReturning = true
    local retryAt = tonumber(controller.scavengeSortieReturnRetryAt or 0) or 0
    if ticks < retryAt then
        controller.nextThink = math.max(controller.nextThink or 0, retryAt)
        return true
    end
    if controller.state == "BASE_RETURN" or controller.state == "CAMP_RETURN" then
        return true
    end
    if controller.baseId ~= nil and controller.beginBaseMovement ~= nil then
        if controller:beginBaseMovement(ticks, true) then
            controller.scavengeSortieReturnRetryAt = nil
            return true
        end
    end
    if controller.campId ~= nil and controller.beginCampMovement ~= nil then
        if controller:beginCampMovement(ticks, true) then
            controller.scavengeSortieReturnRetryAt = nil
            return true
        end
    end
    -- A failed return is still an active sortie obligation. Consume this
    -- decision and retry later instead of falling through to roaming or new
    -- base work while the resident is still away from home.
    controller.scavengeSortieReturnRetryAt = ticks + SCAVENGE_RETURN_RETRY_TICKS
    controller.nextThink = math.max(
        controller.nextThink or 0,
        controller.scavengeSortieReturnRetryAt
    )
    return true
end

-- Scavenging-pair follow: a drafted follower holds formation on its pair
-- leader instead of doing base/camp work. Event and away-team leadership
-- keep their own owners and never route through here.
function Controller:followScavengeParty(ticks)
    if self.groupLeader == nil or self.eventAssignment ~= nil
        or self.awayTeamId ~= nil then
        return false
    end
    -- A claimed task owns this resident until it completes or fails; the
    -- pair moves on without them rather than orphaning the claim.
    if self.baseTask ~= nil then
        return false
    end
    local ok, square = pcall(function() return self.groupLeader:getCurrentSquare() end)
    if not ok or square == nil then
        self:clearGroupLeader()
        self:setGroupMembers({})
        return false
    end
    local current = self.character:getCurrentSquare()
    if current ~= nil
        and navigationDistanceSquared(current, square) > Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED then
        self:beginGroupFollow(ticks)
        return true
    end
    self:resetMovementRecovery()
    self.formationMovementPace = nil
    -- In formation, loot nearby containers like any group member: shared
    -- reservations split the building across the pair instead of doubling up.
    if ticks >= (self.nextGroupObjectiveAssist or 0)
        and Controller.shouldAssistGroupObjective(
            self.groupObjective,
            navigationDistanceSquared(current, square)
        ) then
        self.nextGroupObjectiveAssist = ticks + Controller.TUNING.GROUP_OBJECTIVE_ASSIST_COOLDOWN_TICKS
        if self:beginExploration(ticks) then
            return true
        end
        self.nextGroupObjectiveAssist = ticks + Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RETRY_TICKS
    end
    self.activeDecision = "follow_group"
    self.state = "GROUP_WAIT"
    self.nextThink = ticks + 60
    return true
end

-- Scavenging-pair sortie: the drafted leader keeps roaming/looting while the
-- lease holds instead of recalling home or idling at base. Expiry clears the
-- flag so the ordinary recall resumes.
function Controller:runScavengeSortie(ticks)
    if self.scavengeSortieReturning == true then
        return returnScavengeSortie(self, ticks)
    end
    local untilHours = tonumber(self.scavengeSortieUntilHours or 0) or 0
    if untilHours <= 0 then
        return false
    end
    local nowHours = currentWorldAgeHours()
    if nowHours >= untilHours
        or untilHours - nowHours <= SCAVENGE_RETURN_BUFFER_HOURS then
        return returnScavengeSortie(self, ticks)
    end
    if self.baseTask ~= nil then
        return false
    end
    if not self:beginExploration(ticks) then
        -- A settlement sortie has a concrete purpose. If no useful loaded
        -- container remains, end the outing and use the ordinary return path
        -- instead of turning a failed search into random neighborhood roaming.
        return returnScavengeSortie(self, ticks)
    end
    return true
end

-- Battlefield aid: a survivor carrying bandages patches up a nearby bleeding
-- ally (same base, camp, group, or party) instead of idling past them. The
-- native bandage action owns animation and consumption; Lua only lines up
-- the patient, the bandage, and adjacency, then verifies the bleed stopped.
local AID_RANGE_SQUARED = 144
local AID_RETRY_TICKS = 1800

function Controller:releaseAid()
    self.pendingAidPatient = nil
    self.pendingAidPart = nil
    self.pendingAidBandage = nil
end

local function bleedingPart(character)
    if character == nil or character.isDead == nil then
        return nil
    end
    local alive, part = pcall(function()
        if character:isDead() then return nil end
        local parts = character:getBodyDamage():getBodyParts()
        for index = 0, parts:size() - 1 do
            local candidate = parts:get(index)
            if candidate:bleeding() and not candidate:bandaged() then
                return candidate
            end
        end
        return nil
    end)
    return alive and part or nil
end

function Controller:findAidPatient(ticks)
    local medical = rawget(_G, "KnoxMedicalActions")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local persistence = rawget(_G, "KnoxPersistence")
    if medical == nil or medical.findBandageItem == nil
        or self.character == nil then
        return nil
    end
    local bandage = medical.findBandageItem(self.character)
    if bandage == nil then
        return nil
    end
    local origin = self.character:getCurrentSquare()
    if origin == nil then
        return nil
    end
    local candidates = {}
    if self.baseId ~= nil and persistence ~= nil
        and persistence.getBaseResidentIds ~= nil
        and runtime ~= nil and runtime.getCharacter ~= nil then
        for _, residentId in ipairs(persistence.getBaseResidentIds(self.baseId) or {}) do
            if residentId ~= self.id then
                local ally = runtime.getCharacter(residentId)
                if ally ~= nil then
                    candidates[#candidates + 1] = ally
                end
            end
        end
    end
    for _, member in ipairs(self.groupMembers or {}) do
        if member ~= nil and member ~= self.character then
            candidates[#candidates + 1] = member
        end
    end
    -- Party mates travel together, so they patch each other up: fellow
    -- companions of the same owner, plus the player beside this companion.
    local ownerId = self.companionOwnerId
        or (self.base ~= nil and self.base.ownerKind == "player"
            and self.base.ownerId or nil)
    local allowPlayerAid = KnoxSettings == nil
        or KnoxSettings.allowSurvivorsTreatPlayer == nil
        or KnoxSettings.allowSurvivorsTreatPlayer()
    if ownerId ~= nil and allowPlayerAid then
        local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
        for playerNum = 0, math.max(0, count - 1) do
            local player = getSpecificPlayer(playerNum)
            local playerId = player ~= nil and persistence ~= nil
                and persistence.ensurePlayerId ~= nil
                and persistence.ensurePlayerId(player) or nil
            if player ~= nil and playerId == ownerId then
                candidates[#candidates + 1] = player
            end
        end
    end
    if ownerId ~= nil and persistence ~= nil and persistence.getCompanionIds ~= nil
        and runtime ~= nil and runtime.getCharacter ~= nil then
        local okIds, companionIds = pcall(function()
            return persistence.getCompanionIds(ownerId)
        end)
        if okIds and type(companionIds) == "table" then
            for _, companionId in ipairs(companionIds) do
                if companionId ~= self.id then
                    local ally = runtime.getCharacter(companionId)
                    if ally ~= nil then
                        candidates[#candidates + 1] = ally
                    end
                end
            end
        end
    end
    if self.companionTarget ~= nil then
        candidates[#candidates + 1] = self.companionTarget
    end
    -- Same-faction survivors (camp mates, settlement members) patch each
    -- other up. Distance first, identity after: duty and affiliation lookups
    -- only run for survivors already standing nearby.
    if runtime ~= nil and runtime.activeIds ~= nil and persistence ~= nil then
        local myAffiliation = persistence.getSurvivorAffiliation ~= nil
            and persistence.getSurvivorAffiliation(self.id) or {}
        local myFaction = myAffiliation ~= nil and myAffiliation.factionId or nil
        if myFaction ~= nil then
            local okIds, otherIds = pcall(function() return runtime.activeIds() end)
            if okIds and type(otherIds) == "table" then
                for _, otherId in ipairs(otherIds) do
                    if otherId ~= self.id and runtime.getCharacter ~= nil then
                        local ally = runtime.getCharacter(otherId)
                        local square = ally ~= nil and ally.getCurrentSquare ~= nil
                            and ally:getCurrentSquare() or nil
                        if square ~= nil and (square:getZ() or 0) == (origin:getZ() or 0) then
                            local dx = square:getX() - origin:getX()
                            local dy = square:getY() - origin:getY()
                            if dx * dx + dy * dy <= AID_RANGE_SQUARED then
                                local otherAffiliation = persistence.getSurvivorAffiliation ~= nil
                                    and persistence.getSurvivorAffiliation(otherId) or {}
                                if otherAffiliation ~= nil
                                    and otherAffiliation.factionId == myFaction then
                                    local hostile = persistence.areSurvivorsHostile ~= nil
                                        and persistence.areSurvivorsHostile(self.id, otherId)
                                        or false
                                    if not hostile then
                                        candidates[#candidates + 1] = ally
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local best, bestDistance = nil, nil
    for _, ally in ipairs(candidates) do
        local square = ally.getCurrentSquare ~= nil and ally:getCurrentSquare() or nil
        if square ~= nil and (square:getZ() or 0) == (origin:getZ() or 0) then
            local distance = navigationDistanceSquared(origin, square)
            if distance <= AID_RANGE_SQUARED
                and (bestDistance == nil or distance < bestDistance) then
                local part = bleedingPart(ally)
                if part ~= nil then
                    best, bestDistance = { patient = ally, part = part }, distance
                end
            end
        end
    end
    if best ~= nil then
        best.bandage = bandage
    end
    return best
end

function Controller:beginBattlefieldAid(ticks)
    if ticks < (self.nextAidAt or 0) then
        return false
    end
    -- Aid never steals live work: claimed tasks, active cooks, deposits, and
    -- ordered supply runs all outrank patching someone up right now.
    if self.baseTask ~= nil or self.pendingCooking ~= nil
        or self.pendingDepositTrip ~= nil or self.baseSupplyOrder ~= nil then
        return false
    end
    if self.character == nil or not self.character:getCharacterActions():isEmpty() then
        return false
    end
    local medical = rawget(_G, "KnoxMedicalActions")
    if medical == nil or medical.queueAidBandage == nil then
        return false
    end
    local found = self:findAidPatient(ticks)
    if found == nil then
        return false
    end
    local current = self.character:getCurrentSquare()
    local patientSquare = found.patient:getCurrentSquare()
    if current == nil or patientSquare == nil then
        return false
    end
    if navigationDistanceSquared(current, patientSquare) <= 2 then
        local action, result = medical.queueAidBandage(
            self.character, found.patient, found.bandage, found.part)
        if action == nil then
            self.nextAidAt = ticks + AID_RETRY_TICKS
            return false
        end
        self.pendingAidPatient = found.patient
        self.pendingAidPart = found.part
        self.activeDecision = "aid_ally"
        self.state = "AID_ACTION"
        self.stateStartedAt = ticks
        return true
    end
    local approach = AdjacentFreeTileFinder ~= nil
        and AdjacentFreeTileFinder.Find(patientSquare, self.character) or nil
    if approach == nil then
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    self.pendingAidPatient = found.patient
    self.pendingAidPart = nil
    self.pendingAidBandage = found.bandage
    self.activeDecision = "aid_ally"
    self.state = "AID_MOVE"
    self.stateStartedAt = ticks
    return true
end

function Controller:beginNightShelter(ticks)
    local shelter = rawget(_G, "KnoxNightShelter")
    if shelter == nil then
        return false
    end
    local groupShelter = self.groupObjective ~= nil
        and self.groupObjective.kind == "night_shelter"
    local autonomous = self.baseId == nil and self.campId == nil
        and self.companionOrder == nil and (self.groupLeaderId == nil or groupShelter)
        and self.eventAssignment == nil and self.awayTeamId == nil
        and self.factionBaseCandidate == nil
    if not autonomous then
        return false
    end
    if not shelter.isNight() then
        if self.state == "SLEEPING_RECOVERY" then
            self.shelteredOvernight = nil
            if self.groupLeaderId == nil and groupShelter then
                local group = KnoxPersistence.getTravelGroupFor(self.id)
                if group ~= nil and group.leaderId == self.id then
                    KnoxPersistence.clearTravelGroupObjective(group.id, self.id)
                    self:clearLifeIntent()
                    self.groupObjective = nil
                end
            end
            self.nightSweepUntil = ticks + Controller.TUNING.NIGHT_SWEEP_TICKS
            print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " dawn-sweep")
            KnoxSurvivorNeeds.wakeForDanger(self.character)
            self:finishDecision(ticks)
            self.nextThink = ticks
            return true
        end
        if self.shelteredOvernight then
            self.shelteredOvernight = nil
            if self.groupLeaderId == nil and groupShelter then
                local group = KnoxPersistence.getTravelGroupFor(self.id)
                if group ~= nil and group.leaderId == self.id then
                    KnoxPersistence.clearTravelGroupObjective(group.id, self.id)
                    self:clearLifeIntent()
                    self.groupObjective = nil
                end
            end
            self.nightSweepUntil = ticks + Controller.TUNING.NIGHT_SWEEP_TICKS
            print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " dawn-sweep")
        end
        return false
    end
    -- Followers retain formation until they arrive at their leader's refuge.
    -- They never choose a competing shelter, but can sleep once inside.
    if self.groupLeaderId ~= nil and groupShelter
        and not shelter.isSheltered(self.character) then
        return false
    end
    if #(self.groupMembers or {}) > 1 and self.groupLeaderId ~= nil
        and not groupShelter then
        return false
    end
    if shelter.isSheltered(self.character) then
        if self.state == "SLEEPING_RECOVERY" or self.state == "WAITING_TO_RECOVER"
            or self.state == "MOVING_TO_REST" then
            return true
        end
        self.shelteredOvernight = true
        self:beginRecovery("sleep", ticks)
        return true
    end
    if self.state == "NIGHT_SHELTER_MOVE" then
        return true
    end
    local refuge = shelter.findShelter(
        self.character,
        nil,
        #(self.groupMembers or {}) > 1 and shelter.isUnclaimedTemporaryShelter or nil
    )
    if refuge == nil then
        self:diag("shelter", "no_refuge_found", nil)
        return false
    end
    local result = tostring(self.bridge:moveNpc(self.id, refuge))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordMovementFailure("night_shelter_move", result, ticks)
        return false
    end
    self.activeDecision = "night_shelter"
    self.state = "NIGHT_SHELTER_MOVE"
    self.stateStartedAt = ticks
    if #(self.groupMembers or {}) > 1 then
        local group = KnoxPersistence.getTravelGroupFor(self.id)
        if group ~= nil and group.leaderId == self.id then
            self:setLifeIntent("night_shelter", "traveling", refuge,
                "night-shelter:" .. tostring(refuge:getX()) .. ":" .. tostring(refuge:getY())
            )
            KnoxPersistence.setTravelGroupObjective(
                group.id, self.id, self.lifeIntent, currentWorldAgeHours()
            )
            self.groupObjective = KnoxPersistence.getTravelGroupObjective(group.id)
        end
    end
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " night-shelter=" .. refuge:getX() .. "," .. refuge:getY())
    return true
end

function Controller:recoverFleeMovement(result, ticks)
    self.bridge:cancelNpcMove(self.id)
    if self.fleeTarget ~= nil then
        self.failedFleeTarget = { x = self.fleeTarget:getX(), y = self.fleeTarget:getY(),
            z = self.fleeTarget:getZ(), untilTick = ticks + FLEE_PLAN_TICKS }
    end
    self.fleeTarget = nil
    self.fleeDirectionUntil = 0
    -- Normal travel's long backoff is unsafe while being pursued. Still bounded,
    -- but retry another clear escape lane rather than standing for many seconds.
    local cooldown = self:recordMovementFailure("flee_move", result, ticks, 15, 60)
    self.fleeRecoveryUntil = ticks + cooldown
    self.activeDecision = "flee"
    self.state = "FLEEING"
    self.stateStartedAt = ticks
end

function Controller.fleePace(assessment)
    if assessment == nil then return "run" end
    -- Sprint only to break close contact; sustained sprinting through a distant
    -- crowd burns the endurance needed when a real escape becomes urgent.
    return (assessment.endurance or 0) >= 0.48 and (assessment.health or 0) > 25
        and ((assessment.immediate or 0) > 0 or (assessment.close or 0) > 0)
        and "sprint" or "run"
end

function Controller:beginFlee(ticks, assessment)
    if self.companionOwnerId ~= nil then
        return false
    end
    -- The sandbox option controls admission to a new autonomous retreat. An
    -- active retreat may still need to reacquire a failed route or finish its
    -- existing safe-scan recovery if the option changes while it is underway.
    if self.state ~= "FLEEING" and KnoxSettings ~= nil
        and KnoxSettings.allowAutonomousRetreat ~= nil
        and not KnoxSettings.allowAutonomousRetreat() then
        return false, "retreat_disabled"
    end
    self.travelFinalSquare = nil
    self.travelFinalContext = nil
    roadFinalById[self.id] = nil
    self:cancelTrade("danger")
    self.combatDisengageUntil = ticks + FLEE_DISENGAGE_TICKS
    local target, hadGroupPlan = groupFleeTarget(self, ticks)
    local emergency = false
    if target == nil then
        target = findFleeTarget(self, ticks)
        local key = groupFleeKey(self)
        if target ~= nil and key ~= nil and (not hadGroupPlan or key == self.id) then
            fleePlans[key] = {
                x = target:getX(), y = target:getY(), z = target:getZ(),
                expiresAt = ticks + FLEE_PLAN_TICKS,
            }
        end
    end
    if target == nil then
        -- Passive followers and other non-combat survivors need a final
        -- movement attempt when every checked lane is blocked.  Do not use
        -- this branch for a survivor who can legally engage the adjacent
        -- attacker; that existing combat handoff is safer than forcing a
        -- route through an obstruction.
        local threat = nearestThreat(self, ticks)
        if threat == nil or not self:allowsCompanionThreat(threat) then
            target = findEmergencyFleeTarget(self, ticks)
            emergency = target ~= nil
        end
    end
    if target == nil then
        self.nextThink = ticks + FLEE_RECHECK_TICKS
        if self.state == "FLEEING" then self.fleeRecoveryUntil = self.nextThink end
        self.nextThreatScan = math.max(
            self.nextThreatScan or 0,
            ticks + FLEE_RECHECK_TICKS
        )
        -- If every escape lane is blocked, do not wait helplessly for a bite.
        -- Reuse native combat against an adjacent reachable threat only; this
        -- is not permission to chase a target back into the crowd.
        if self.state ~= "COMBAT" then
            local threat = nearestThreat(self, ticks)
            local origin = self.character:getCurrentSquare()
            local threatSquare = threat ~= nil and threat:getCurrentSquare() or nil
            if threatSquare ~= nil and origin ~= nil
                and distanceSquared(origin, threatSquare) <= 3.0625
                and fleeLaneClear(origin, threatSquare)
                and self:allowsCompanionThreat(threat) then
                if self:beginCombat(threat) then
                    self.fleeRecoveryUntil = nil
                    self.fleeTarget = nil
                end
            end
        end
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:suspendBaseTaskForThreat("survival_flee")
    self:interruptSelfCareForDanger(ticks)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseCombat()
    self:clearFirearmCombatState()
    local preserveBaseSupplyRun = self.baseId ~= nil
        and (self.baseSupplyTrip == true
            or self.baseSupplyOrder ~= nil
            or self.pendingBaseSupplyDeposit ~= nil)
    self:releaseSupply(preserveBaseSupplyRun)
    self:leaveRecoveryPosture()
    local origin = self.character:getCurrentSquare()
    if origin ~= nil then
        local dx = target:getX() - origin:getX()
        local dy = target:getY() - origin:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length >= 0.01 then
            self.lastFleeDirectionX = dx / length
            self.lastFleeDirectionY = dy / length
            self.fleeDirectionUntil = ticks + FLEE_PLAN_TICKS
        end
    end
    self.fleeSafeScans = 0
    self.fleeTarget = target
    self.fleeRecoveryUntil = nil
    local pace = emergency and "sprint" or Controller.fleePace(assessment)
    local result = tostring(self.bridge:moveNpcWithPace(self.id, target, pace))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recoverFleeMovement(result, ticks)
        return false
    end
    self.activeDecision = "flee"
    self.state = "FLEEING"
    self.stateStartedAt = ticks
    self.nextThink = ticks + FLEE_RECHECK_TICKS
    sayDialogue(self.character, self.id, "flee", ticks, 900)
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " state=FLEEING reason=" .. tostring(assessment and assessment.reason)
        .. " zombies=" .. tostring(assessment and assessment.zombies or 0)
        .. " humans=" .. tostring(assessment and assessment.humans or 0)
        .. " allies=" .. tostring(assessment and assessment.allies or 1)
        .. " health=" .. tostring(assessment and assessment.health or 100)
        .. " risk=" .. tostring(assessment and assessment.risk or 0)
        .. " immediate=" .. tostring(assessment and assessment.immediate or 0)
        .. " escapeLanes=" .. tostring(assessment and assessment.escapeLanes or 0)
        .. " pace=" .. pace
        .. " target=" .. target:getX() .. "," .. target:getY())
    return true
end

-- Corpse dragging occupies the hands and native grapple state. Suspend the
-- claim, release the body, then defend; do not route this through retired flee
-- behavior. The claimed task remains attached and is reconsidered after combat.
function Controller:interruptCorpseHaulForDefense(threat, ticks)
    if threat == nil or self.baseTask == nil
        or self.baseTask.type ~= "haul_corpse" then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self:resetMovementRecovery()
    self:suspendBaseTaskForThreat("corpse_defense")
    self.pendingCorpseDefenseTarget = threat
    self.corpseDefenseReleaseUntil = ticks + Controller.TUNING.CORPSE_DEFENSE_RELEASE_TICKS
    self.activeDecision = "corpse_defense_release"
    self.state = "CORPSE_DEFENSE_RELEASE"
    self.stateStartedAt = ticks
    if self.character ~= nil then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    return self:updateCorpseDefenseRelease(ticks)
end

function Controller:updateCorpseDefenseRelease(ticks)
    local dragging = self.character ~= nil and KnoxBaseCorpseHandling ~= nil
        and KnoxBaseCorpseHandling.isDragging ~= nil
        and KnoxBaseCorpseHandling.isDragging(self.character)
    if dragging and ticks < (self.corpseDefenseReleaseUntil or ticks) then
        -- Native grapple release may take more than one frame. Reassert it at
        -- the normal threat-scan cadence without starting a conflicting attack.
        if ticks >= (self.nextCorpseDefenseReleaseAttempt or 0) then
            self.nextCorpseDefenseReleaseAttempt = ticks + THREAT_SCAN_TICKS
            pcall(function() self.character:setDoGrappleLetGo() end)
        end
        return true
    end

    if dragging then
        -- A native release that never completes cannot retain the task claim
        -- forever. Fail this attempt so the board may offer fresh work later.
        self:abandonBaseTask("corpse_defense_release_timeout")
        self:recordFailure(
            "corpse_defense_release_timeout",
            ticks,
            THREAT_FAILURE_COOLDOWN_TICKS
        )
    end
    local target = self.pendingCorpseDefenseTarget
    self.pendingCorpseDefenseTarget = nil
    self.corpseDefenseReleaseUntil = nil
    self.nextCorpseDefenseReleaseAttempt = nil
    self.activeDecision = nil
    self.state = "IDLE"
    self.stateStartedAt = ticks
    if target ~= nil and target:getCurrentSquare() ~= nil
        and self:allowsCompanionThreat(target)
        and self:beginCombat(target) then
        return true
    end
    self.nextThink = ticks
    return true
end

function Controller:beginFactionBaseScout(ticks)
    local candidate = self.factionBaseCandidate
    local target = KnoxFactionBaseScouting.resolveTarget(candidate)
    if candidate == nil then
        return false
    end
    if target == nil then
        self:rejectFactionBaseCandidate(ticks, "target_unloaded")
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "travel"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:rejectFactionBaseCandidate(ticks, result)
        return false
    end
    self.activeDecision = "scout_faction_base"
    self.state = "MOVING_TO_BASE_CANDIDATE"
    if self.announcedFactionBaseCandidate ~= candidate.buildingId then
        self.announcedFactionBaseCandidate = candidate.buildingId
        KnoxActivityFeed.speak(self.character, "Let's check that place out.")
        KnoxActivityFeed.event(
            "Possible base near " .. tostring(candidate.x) .. ", "
                .. tostring(candidate.y) .. ". Not claimed yet."
        )
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_BASE_CANDIDATE faction=" .. tostring(self.factionId)
            .. " building=" .. tostring(candidate.buildingId)
            .. " score=" .. tostring(candidate.score)
    )
    return true
end

local function cleanupContext(self)
    local base, requirements = nil, {}
    local duty = KnoxPersistence.getSurvivorDuty(self.id)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(self.id) or {}
    if duty ~= nil and duty.baseId ~= nil then base = KnoxPersistence.getBase(duty.baseId)
    elseif affiliation.kind == "player" and affiliation.ownerId ~= nil then
        base = KnoxPersistence.getBaseForOwner("player", affiliation.ownerId)
    elseif affiliation.factionId ~= nil then
        base = KnoxPersistence.getBaseForOwner("faction", affiliation.factionId)
    end
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task.state == "queued" or task.state == "claimed" then
            for itemType, count in pairs(task.requirements ~= nil and task.requirements.items or {}) do
                requirements[itemType] = math.max(requirements[itemType] or 0, tonumber(count) or 0)
            end
        end
    end
    return base, requirements, duty
end

function Controller:canMakeDepositTrip(duty)
    if self.baseTask ~= nil or self.companionOrder ~= nil or self.companionDirective ~= nil then return false end
    -- Faction membership does not bind a resident to the leader during base life.
    if duty ~= nil and duty.mode == "base" and duty.baseId == self.baseId then return true end
    return self.groupLeader == nil and #(self.groupMembers or {}) <= 1
        and (duty == nil or duty.mode == "base" or duty.mode == "autonomous")
end

function Controller:deferDepositTrip(ticks)
    self.depositRetryAt = self.depositRetryAt or {}
    for key, deadline in pairs(self.depositRetryAt) do
        if deadline <= ticks then self.depositRetryAt[key] = nil end
    end
    local trip = self.pendingDepositTrip
    if trip ~= nil then self.depositRetryAt[trip.policyKey] = ticks + 1800 end
    -- Bounded transient memory, even for bases with many assigned containers.
    local count, oldest, deadline = 0, nil, math.huge
    for key, expires in pairs(self.depositRetryAt) do
        count = count + 1
        if expires < deadline then oldest, deadline = key, expires end
    end
    if count > 16 then self.depositRetryAt[oldest] = nil end
    self.nextCleanupAt = ticks + 600
end

function Controller:beginDepositTrip(base, plan, duty, ticks)
    if base == nil or not self:canMakeDepositTrip(duty)
        or KnoxBaseStorage.findDepositTrip == nil then return false end
    for _, entry in ipairs(plan) do
        if not entry.canDrop or entry.value >= 15 then
            local storage = KnoxBaseStorage.findDepositTrip(base, self.character, entry.item,
                self.depositRetryAt, ticks)
            if storage ~= nil then
                self.pendingDepositTrip = { baseId = base.id, policyKey = storage.policy.key,
                    item = entry.item, baseSupply = entry.baseSupply == true }
                self:leaveRecoveryPosture()
                local result = tostring(moveWithTravelPace(self.bridge, self.id, self.character,
                    storage.approach, "return_home"))
                if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
                    self.bridge:cancelNpcMove(self.id)
                    self:deferDepositTrip(ticks)
                    self.pendingDepositTrip = nil
                    self:recordMovementFailure("deposit_move", result, ticks)
                    return false
                end
                self.activeDecision = entry.baseSupply == true and "base_supply_deposit" or "deposit_surplus"
                self.state = "MOVING_TO_DEPOSIT"
                self.stateStartedAt = ticks
                return true
            end
        end
    end
    return false
end

function Controller:completeDepositTrip(ticks)
    local trip = self.pendingDepositTrip
    local base, requirements, duty = cleanupContext(self)
    -- Recompute utility and ownership at arrival. Equipment, jobs, the base,
    -- container capacity and even the item may have changed during travel.
    if trip ~= nil and base ~= nil and base.id == trip.baseId and self:canMakeDepositTrip(duty) then
        local plan
        if trip.baseSupply == true then
            local inventory = self.character:getInventory()
            plan = {}
            if self.pendingBaseSupplyDeposit ~= nil and self.pendingBaseSupplyDeposit.item == trip.item
                and inventory ~= nil and inventory:contains(trip.item) then
                plan[1] = {item=trip.item, source=inventory, reason="base_supply", baseSupply=true}
            end
        else
            plan = KnoxSurvivorLooting.cleanupPlan(self.character, requirements, true, true)
        end
        for _, entry in ipairs(plan) do
            if entry.item == trip.item then
                local storage = KnoxBaseStorage.findNearbyDeposit(base, self.character, entry.item, trip.policyKey)
                if storage ~= nil then
                    local action = KnoxInventoryActions.queueTransfer(self.character, entry.item,
                        entry.source, storage.container, nil)
                    if action ~= nil then
                        self.pendingCleanup = { item = entry.item, source = entry.source,
                            destination = storage.container, reason = entry.reason,
                            baseSupply = entry.baseSupply == true }
                        self.state = "INVENTORY_CLEANUP"
                        self.stateStartedAt = ticks
                        return true
                    end
                end
                break
            end
        end
    end
    self:deferDepositTrip(ticks)
    self:finishDecision(ticks)
    return false
end

-- A base-supply run is different from ordinary inventory cleanup: the item was
-- deliberately recovered for the settlement, so it must be handed to the
-- assigned storage even when it is not considered personal surplus. Keep the
-- transfer on the same native inventory path and clear the marker only after
-- the destination contains the real item.
function Controller:beginBaseSupplyDeposit(ticks)
    local pending = self.pendingBaseSupplyDeposit
    local base = self.base
    if pending == nil or pending.item == nil or base == nil
        or self.baseId == nil or self.character == nil
        or not KnoxBaseManager.containsSquare(base, self.character:getCurrentSquare())
        or not self.character:getCharacterActions():isEmpty()
        or KnoxBaseStorage.findNearbyDeposit == nil then
        return false
    end
    local item = pending.item
    local inventory = self.character:getInventory()
    if inventory == nil or not inventory:contains(item) then
        self:finishBaseSupplyRun("delivery_item_missing")
        self.pendingBaseSupplyDeposit = nil
        self:clearLifeIntent()
        return false
    end
    local target = KnoxBaseStorage.findDepositTrip(base, self.character, item, self.depositRetryAt, ticks)
    local storage = target ~= nil and KnoxBaseStorage.findNearbyDeposit(base, self.character, item, target.policy.key) or nil
    if storage == nil then
        local duty = KnoxPersistence.getSurvivorDuty(self.id)
        if target ~= nil and self:beginDepositTrip(base,
            {{item=item, source=inventory, canDrop=false, baseSupply=true}}, duty, ticks) then return true end
        self.nextThink = math.max(self.nextThink or 0, ticks + 600)
        return false
    end
    local action, result = KnoxInventoryActions.queueTransfer(
        self.character, item, inventory, storage.container, nil
    )
    if action == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + 180)
        self:recordFailure("base_supply_deposit:" .. tostring(result), ticks, 180)
        return false
    end
    self.pendingCleanup = {
        item = item,
        source = inventory,
        destination = storage.container,
        reason = "base_supply",
        baseSupply = true,
    }
    self.activeDecision = "base_supply_deposit"
    self.state = "INVENTORY_CLEANUP"
    self.stateStartedAt = ticks
    return true
end

function Controller:beginInventoryCleanup(ticks)
    if rawget(_G, "KnoxSurvivorLooting") == nil or KnoxSurvivorLooting.cleanupPlan == nil then return false end
    if self.state ~= "IDLE" or ticks < (self.nextCleanupAt or 0) or self.baseTask ~= nil
        or not self.character:getCharacterActions():isEmpty() then return false end
    self.nextCleanupAt = ticks + 300
    local base, requirements, duty = cleanupContext(self)
    local atBase = base ~= nil and KnoxBaseManager ~= nil
        and KnoxBaseManager.containsSquare(base, self.character:getCurrentSquare())
    local plan, result = KnoxSurvivorLooting.cleanupPlan(self.character, requirements, self.cleanupInProgress, atBase)
    self.cleanupInProgress = result == "heavy_load"
    if #plan == 0 then return false end
    local candidate, destination
    -- Prefer a real nearby deposit for any surplus before dropping a lower-value
    -- item. No autonomous detour may override Follow/Hold/Guard or a base job.
    for _, entry in ipairs(plan) do
        local preferred = self:canMakeDepositTrip(duty) and KnoxBaseStorage.findDepositTrip ~= nil
            and KnoxBaseStorage.findDepositTrip(base, self.character, entry.item, self.depositRetryAt, ticks) or nil
        local storage = KnoxBaseStorage.findNearbyDeposit(base, self.character, entry.item,
            preferred ~= nil and preferred.policy.key or nil)
        if storage ~= nil then candidate, destination = entry, storage.container break end
    end
    if candidate == nil and self:beginDepositTrip(base, plan, duty, ticks) then return true end
    if candidate == nil and atBase then return false end
    if candidate == nil then
        for _, entry in ipairs(plan) do
            if entry.canDrop then candidate = entry break end
        end
    end
    if candidate == nil then return false end
    local action, reason
    if destination ~= nil then
        action, reason = KnoxInventoryActions.queueTransfer(self.character, candidate.item,
            candidate.source, destination, nil)
    else action, reason = KnoxInventoryActions.queueDrop(self.character, candidate.item) end
    if action == nil then
        self.nextCleanupAt = ticks + 600
        return false
    end
    self.pendingCleanup = { item = candidate.item, source = candidate.source,
        destination = destination, reason = candidate.reason }
    self.activeDecision = destination ~= nil and "deposit_surplus" or "drop_surplus"
    self.state = "INVENTORY_CLEANUP"
    self.stateStartedAt = ticks
    return true
end

function Controller:updateInventoryCleanup(ticks)
    if not self.character:getCharacterActions():isEmpty() then return end
    local transfer = self.pendingCleanup
    local completed = transfer ~= nil and not transfer.source:contains(transfer.item)
        and ((transfer.destination ~= nil and transfer.destination:contains(transfer.item))
            or (transfer.destination == nil and transfer.item:getWorldItem() ~= nil))
    if not completed then
        if self.pendingDepositTrip ~= nil then self:deferDepositTrip(ticks) end
        self.nextCleanupAt = ticks + 600
        self:recordFailure("cleanup_transfer_not_completed", ticks, 60)
    else
        if transfer ~= nil and transfer.baseSupply == true then
            self.pendingBaseSupplyDeposit = nil
            self:finishBaseSupplyRun("deposited")
            self:clearLifeIntent()
        end
        print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " inventory-cleanup="
            .. tostring(self.activeDecision) .. " reason=" .. tostring(transfer.reason))
    end
    if self.companionDirective ~= nil
        and self.companionDirective.kind == "clean_inventory" then
        KnoxPersistence.clearCompanionDirective(
            self.id, self.companionOwnerId, currentWorldAgeHours()
        )
        self.companionDirective = nil
        self.directiveMisses = 0
    end
    self:finishDecision(ticks)
end

function Controller:think(ticks)
    -- The decision boundary agrees with the intervening threat scans: unseen-by-
    -- zombies travel can continue quietly, but contact/active danger always wins.
    local quiet = shouldRemainStealthy(self)
    if not quiet then
        local flee, assessment = fleeAssessment(self)
        if flee and self:beginFlee(ticks, assessment) then return end
    end
    local threat = not quiet and nearestThreat(self, ticks) or nil
    if not self:allowsCompanionThreat(threat) then
        threat = nil
    end
    local decision = KnoxSurvivorNeeds.decide(self.character, threat)
    -- Base residents stay on settlement duty. They may consume supplies they
    -- already carry or retrieve them from assigned storage. An explicit
    -- Survival Order can send them out, but a shortage alone must never turn
    -- into an autonomous neighborhood search. findSupply() fails closed after
    -- assigned storage for ordinary base residents.
    if self.baseId ~= nil and self.baseSupplyOrder == nil
        and (decision.kind == "find_food" or decision.kind == "find_water"
            or decision.kind == "find_medical") then
        if self:beginWorldSearch(decision.kind, ticks) then return end
        -- A hungry resident with no reachable supply must never convert the
        -- need into roaming or patrol duty. Hold and retry on the normal
        -- supply throttle instead of working to death.
        self:clearLifeIntent()
        self.nextThink = math.max(self.nextThink or 0,
            (self.nextWorldSearch or ticks) + THINK_MIN_TICKS)
        return
    end
    if decision.kind == "fight" then
        if not self:beginCombat(decision.target) then
            self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
            self.nextThreatScan = math.max(self.nextThreatScan or 0, ticks + THREAT_SCAN_TICKS)
        end
        return
    end
    -- Ordinary rest yields to a direct player order, but actual sleep is a
    -- survival need for every survivor, including owned companions. Recovery
    -- keeps the durable order intact so it resumes after the native sleep
    -- transition; only the lower-priority endurance-rest decision is deferred.
    local hasDirectOrder = self.companionOrder ~= nil or self.companionDirective ~= nil
    if hasDirectOrder and decision.kind == "rest"
        and not Controller.isCriticalOrderedRecovery(decision) then
        decision = { kind = "roam", state = decision.state }
    end
    if (decision.kind == "eat" or decision.kind == "drink"
        or decision.kind == "bandage" or decision.kind == "improvise_medical"
        or decision.kind == "rest" or decision.kind == "sleep"
        or decision.kind == "find_food" or decision.kind == "find_water"
        or decision.kind == "find_medical")
        and not Controller.selfCareReady(
            self.selfCareRetryAt,
            decision.kind,
            ticks
        ) then
        -- The need remains real, but a failed native action must not monopolize
        -- every think cycle. Preserve the underlying Follow/Hold/roam activity
        -- until this one bounded retry expires.
        decision = { kind = "roam", state = decision.state }
    end
    if decision.kind == "eat" or decision.kind == "drink"
        or decision.kind == "bandage" or decision.kind == "improvise_medical" then
        local action, result, intent = KnoxSurvivorNeeds.execute(
            self.character,
            decision
        )
        if action ~= nil and action ~= false then
            self:sayNeedIfGrouped(decision.kind, ticks)
            self.activeDecision = decision.kind
            self.selfCareIntent = intent
            self.selfCareInterrupted = nil
            self.state = "TIMED_ACTION"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=TIMED_ACTION kind=" .. decision.kind
            )
        else
            self.selfCareRetryAt[decision.kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_action:" .. decision.kind .. ":" .. tostring(result),
                ticks,
                Controller.TUNING.SELF_CARE_RETRY_TICKS
            )
        end
        return
    end
    if decision.kind == "find_food" and (self.baseTask == nil or self.baseTask.type ~= "cook")
        and self:beginBaseCooking(ticks,nil,true) then return end
    if decision.kind == "find_food" or decision.kind == "find_water"
        or decision.kind == "find_medical" then
        -- A live claim survives the search: suspend it cleanly so the route
        -- is cancelled once and the task restarts from its work phase.
        -- Cook claims feed the need themselves via the cooking update.
        if self.baseTask ~= nil and self.baseTask.type ~= "cook" then
            self:suspendBaseTaskForThreat("needs_interrupt")
        end
        self:sayNeedIfGrouped(decision.kind, ticks)
        if self:hasNeedEscort() then
            -- Only a short clear detour is automatic. If none is safe, retain
            -- the real shortage and regroup instead of starting a roam search.
            if self:beginWorldSearch(decision.kind, ticks) then return end
            self.selfCareRetryAt[decision.kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
            decision = { kind = "roam", state = decision.state }
        else
        if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil
            and Controller.shouldDelegateNeedToGroup(
                decision.kind,
                navigationDistanceSquared(
                self.character:getCurrentSquare(),
                self.groupLeader:getCurrentSquare()
                )
            ) then
            -- The leader will either share a real spare or own one group search.
            -- A nearby follower must not split off and create a competing route.
            -- A live claim is suspended first so it resumes instead of orphaning.
            if self.baseTask ~= nil and self.baseTask.type ~= "cook" then
                self:suspendBaseTaskForThreat("needs_interrupt")
            end
            self.activeDecision = "await_group_" .. decision.kind
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
            return
        end
        if not self:beginWorldSearch(decision.kind, ticks) then
            self:beginRoam(ticks, decision.kind)
        end
        return
        end
    end
    if decision.kind == "rest" or decision.kind == "sleep" then
        if self.baseTask ~= nil and self.baseTask.type ~= "cook" then
            self:suspendBaseTaskForThreat("needs_interrupt")
        end
        self:sayNeedIfGrouped(decision.kind, ticks)
        self:beginRecovery(decision.kind, ticks)
        return
    end
    if self.lifeIntent ~= nil
        and (self.lifeIntent.kind == "find_food"
            or self.lifeIntent.kind == "find_water"
            or self.lifeIntent.kind == "find_medical") then
        -- The real need evaluator no longer requests this resource. End the
        -- durable purpose here instead of letting a satisfied survivor keep
        -- searching because an older intent survived an interruption/reload.
        self:clearLifeIntent()
    end
    if self:beginGroupSupport(ticks) then return end
    if self.groupLeader == nil and #(self.groupMembers or {}) > 1 then
        local groupNeed = KnoxGroupSupport.mostUrgentNeed(
            self.character,
            self.groupMembers
        )
        if groupNeed ~= nil then
            if not self:beginWorldSearch(groupNeed.kind, ticks) then
                self:beginRoam(ticks, groupNeed.kind)
            end
            return
        end
    end
    if self:beginInventoryCleanup(ticks) then return end
    if self:beginEventTravel(ticks) then return end
    if self.awayTeamId ~= nil then
        local awayTeam = KnoxPersistence.getAwayTeam(self.awayTeamId)
        if awayTeam ~= nil and (awayTeam.state == "awaiting_collection"
            or awayTeam.state == "collecting" or awayTeam.state == "returning") then
            if self:beginAwayMission(ticks) then
                return
            end
            -- A mission-owned survivor must not fall through into roaming,
            -- companion or base logic when its destination is temporarily
            -- unavailable. Keep the durable away duty authoritative and retry
            -- through this same bounded boundary.
            self.nextThink = math.max(self.nextThink or 0,
                ticks + EXPLORATION_RETRY_TICKS)
            return
        end
    end
    if self.companionOrder ~= nil then
        if self.companionDirective ~= nil then
            local kind = self.companionDirective.kind
            if self.companionDirective.partyDestinationArrived == true then
                self.activeDecision = "party_destination_regroup"
                self.state = "COMPANION_WAIT"
                self.nextThink = ticks + 90
                return
            end
            if kind == "go_to" or kind == "guard" then
                if self:beginCompanionPointDirective(ticks, self.companionDirective) then
                    return
                end
                self.nextThink = math.max(self.nextThink or 0, ticks + EXPLORATION_RETRY_TICKS)
                return
            end
            if kind == "patrol_area" then
                if self:beginCompanionPatrolDirective(ticks, self.companionDirective) then
                    return
                end
                self.nextThink = math.max(self.nextThink or 0,
                    ticks + EXPLORATION_RETRY_TICKS)
                return
            end
            if kind == "find_food" or kind == "find_water" or kind == "find_medical"
                or kind == "find_weapon" or kind == "find_tools" or kind == "find_wood"
                or kind == "find_materials" or kind == "find_clothing" or kind == "find_ammo" then
                self:beginCompanionNeedDirective(ticks, self.companionDirective)
                return
            end
            if self:beginExploration(ticks, self.companionDirective) then
                return
            end
            if self.companionDirective ~= nil then
                self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                return
            end
        end
        if self.companionOrder == "hold" then
            if self:beginFollowerHygiene(ticks) then return end
            self:beginFollowerCompany(ticks, self.companionTarget, true)
            self.activeDecision = "hold_position"
            self.state = "COMPANION_HOLD"
            self.nextThink = ticks + 90
            return
        end
        if self.companionOrder == "relax" then
            -- Real downtime: wash when filthy, hip-pocket snack when
            -- peckish, rest after. The field context is stationary by
            -- definition, same as base ambient.
            if self:beginFollowerHygiene(ticks) then return end
            if not self:beginAmbientSnack(ticks) then
                self:beginCompanionRelax(ticks)
            end
            return
        end
        local anchor, anchorSquare, anchorReason = self:resolvePlayerPartyAnchor(ticks)
        if anchor == nil or anchorSquare == nil then
            self.companionAnchorWaitReason = anchorReason
            self.activeDecision = "wait_for_party_anchor"
            self.state = "COMPANION_WAIT"
            self.nextThink = ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS
            return
        end
        self.companionAnchorWaitReason = anchorReason
        local formationTarget = self:findPlayerPartyFormationTarget(anchor, anchorSquare)
        if formationTarget == nil then
            self.activeDecision = "party_regrouping"
            self.state = "COMPANION_WAIT"
            self.nextThink = ticks + Controller.TUNING.FORMATION_BOTTLENECK_WAIT_TICKS
            return
        end
        local distance = formationTarget ~= nil and navigationDistanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED then
            self:beginCompanionFollow(ticks)
        else
            -- Idle in formation: opportunistically take nearby need-relevant
            -- loot (corpses/containers within a few tiles) without roaming.
            -- Gated by the auto-loot permission (nil = enabled) and defers
            -- to combat, explicit directives, and needs (handled above).
            if self.combatTarget == nil and self.companionDirective == nil
                and self.allowAutoLoot ~= false
                and ticks >= (self.nextExplorationSearch or 0) then
                local peek = findExploration(self, ticks, nil)
                local inReach = false
                do
                    -- Bounded: need-relevant items only (Looting.plan filters),
                    -- within ~6 tiles of self and ~7 of the player. Inspect-only
                    -- fallbacks (no items) are ignored so followers never roam.
                    if peek ~= nil and peek.approach ~= nil
                        and peek.items ~= nil and #peek.items > 0 then
                        local mySquare = self.character ~= nil
                            and self.character:getCurrentSquare() or nil
                        local playerSquare = anchorSquare
                        if mySquare ~= nil and playerSquare ~= nil
                            and navigationDistanceSquared(mySquare, peek.approach) <= 36
                            and navigationDistanceSquared(playerSquare, peek.approach) <= 49 then
                            inReach = true
                        end
                    end
                end
                if inReach then
                    if self:beginExploration(ticks, nil) then
                        return
                    end
                else
                    -- Optional party support extends only the settled-Follow
                    -- case: one safe food item from a loaded nearby container.
                    -- The same reservation, movement, transfer and result path
                    -- remains authoritative. It never searches corpses or
                    -- chains containers, and the player anchor bounds the detour.
                    local supportNeed = KnoxSurvivorNeeds.decide(self.character, nil)
                    local actionableSupportNeed = supportNeed ~= nil
                        and supportNeed.kind ~= nil and supportNeed.kind ~= "roam"
                        and Controller.selfCareReady(
                            self.selfCareRetryAt, supportNeed.kind, ticks
                        ) and supportNeed.kind or nil
                    if Controller.partyFoodSupportEligible({
                        autoLootAllowed = self.allowAutoLoot ~= false,
                        playerOwned = self.companionOwnerId ~= nil,
                        baseResident = self.baseId ~= nil,
                        order = self.companionOrder,
                        formationSettled = true,
                        explicitDirective = self.companionDirective ~= nil,
                        supplyActive = self.pendingSupply ~= nil
                            or self.pendingBaseSupplyDeposit ~= nil
                            or self.pendingDepositTrip ~= nil
                            or self.baseSupplyTrip == true,
                        combatActive = self.combatTarget ~= nil,
                        threatActive = Controller.hasEntries(self.perceivedThreats),
                        urgentNeed = actionableSupportNeed,
                    }) then
                        if self:beginExploration(ticks, nil, {
                            partySupport = true,
                            playerAnchor = anchorSquare,
                        }) then
                            return
                        end
                    else
                        -- Nothing worth taking: throttle the next inspect scan
                        -- instead of re-walking containers every idle think.
                        self.nextExplorationSearch = ticks + EMPTY_SEARCH_COOLDOWN_TICKS
                    end
                end
            end
            self:resetMovementRecovery()
            self.formationMovementPace = nil
            if self:beginFollowerHygiene(ticks) then return end
            self:beginFollowerCompany(ticks, self.companionTarget, true)
            self.activeDecision = "follow_player"
            self.state = "COMPANION_WAIT"
            -- Settled cadence: needs and orders still arrive through the
            -- normal think, but a parked follower must not re-scan loot,
            -- water and company every few seconds (visible rethink stutter).
            self.nextThink = ticks + 90
        end
        return
    end
    if self.baseId ~= nil and self.base ~= nil then
        self:syncBaseSupplyRun()
        if self:followScavengeParty(ticks) then
            return
        end
        local atBase = KnoxBaseManager.containsSquare(
            self.base,
            self.character:getCurrentSquare()
        )
        if self.baseSupplyTrip == true and self.pendingBaseSupplyDeposit == nil
            and self.baseSupplyKind ~= nil then
            local resumedKind = self.baseSupplyKind
            if self:beginWorldSearch(resumedKind, ticks) then
                self:beginBaseSupplyRun(resumedKind)
                return
            end
            self:finishBaseSupplyRun("unavailable")
            if self.baseSupplyOrder ~= nil then
                self:recordExplicitBaseSupplyFailure(ticks)
            end
            self:releaseSupply()
            if not atBase then
                self:beginBaseMovement(ticks, true)
            else
                self.activeDecision = "base_supply_retry"
                self.state = "BASE_IDLE"
                self.nextThink = ticks + SUPPLY_RETRY_TICKS
            end
            return
        elseif not atBase then
            if self:runScavengeSortie(ticks) then
                return
            end
            if not self:resumeExternalBaseWork(ticks) then
                self:beginBaseMovement(ticks, true)
            end
        elseif self.pendingBaseSupplyDeposit ~= nil
            and self:beginBaseSupplyDeposit(ticks) then
            return
        elseif self.baseTask == nil then
            -- A finished watch switches its set back off before the next
            -- decision; an interrupted one keeps burning until this expiry.
            -- Lit rooms follow the same rule through pendingLights.
            if self.pendingWatch ~= nil
                and ticks >= (self.pendingWatch.untilTick or 0) then
                self:releaseWatch()
            end
            if self.pendingLights ~= nil
                and ticks >= (self.pendingLights.untilTick or 0) then
                self:releaseLights()
            end
            local explicit = self.baseSupplyOrder
            local explicitKind = explicit ~= nil and tostring(explicit.kind or "") or nil
            local explicitExpired = explicit ~= nil
                and tonumber(explicit.expiresAtHours) ~= nil
                and tonumber(explicit.expiresAtHours) <= currentWorldAgeHours()
            if explicitExpired then
                if KnoxPersistence.clearBaseSupplyOrder ~= nil then
                    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
                    KnoxPersistence.clearBaseSupplyOrder(
                        self.id, duty.ownerId, self.baseId, currentWorldAgeHours()
                    )
                end
                self.baseSupplyOrder = nil
                self.baseSupplyOrderAttempts = 0
                explicit = nil
                explicitKind = nil
            end
            if explicitKind ~= nil and explicitKind ~= "" then
                self.baseSupplyTrip = true
                self.baseSupplyKind = explicitKind
                if self:beginWorldSearch(explicitKind, ticks) then
                    self:beginBaseSupplyRun(explicitKind)
                    return
                end
                self:recordExplicitBaseSupplyFailure(ticks)
                self:releaseSupply()
                self.nextThink = ticks + SUPPLY_RETRY_TICKS
                return
            end
            if self.settlementArrivalPending == true then
                self.settlementArrivalPending = nil
                if self:beginBaseMovement(ticks, false) then
                    return
                end
            end
            -- Automatic settlement scavenging: an idle resident answers a real
            -- storage shortage (food/water/medical/tools/weapons) with a
            -- bounded neighborhood fetch before accepting ordinary work. The
            -- election, one-claimant lease, and rotation live in
            -- baseSupplyNeed; claimed native tasks are never interrupted.
            -- Player residents still need the existing per-resident opt-in;
            -- a faction resident may answer its own faction base's shortage.
            -- Existing group-sortie leases remain separate and are not stolen.
            local need = self:baseSupplyNeed(ticks)
            if need ~= nil and self.baseSupplyTrip == true and self.baseSupplyKind ~= nil then
                if self:beginWorldSearch(self.baseSupplyKind, ticks) then
                    self:beginBaseSupplyRun(self.baseSupplyKind)
                    return
                end
                self:finishBaseSupplyRun("unavailable")
                self:releaseSupply()
                self.nextThink = ticks + SUPPLY_RETRY_TICKS
                return
            end
            -- A resident without an already-claimed native task should answer
            -- a real settlement shortage before accepting ordinary work. This
            -- keeps food/water/medical recovery aligned with the existing
            -- priority model without interrupting a job already in progress.
            -- A drafted pair leader leaves on sortie instead of idling.
            if self:runScavengeSortie(ticks) then
                return
            end
            -- Earned leisure break: one ambient round instead of another
            -- automatic claim. Shortages and sorties above already ran, so
            -- genuine need still preempts; sleep/recreation windows already
            -- idle and simply clear the debt.
            local forceLeisure = false
            if self.leisureBreakDue == true then
                self.leisureBreakDue = false
                self.consecutiveAutoTasks = 0
                local breakAssignment = self.lastScheduleAssignment
                if breakAssignment == nil and KnoxBaseJobs.scheduleAssignment ~= nil then
                    breakAssignment = KnoxBaseJobs.scheduleAssignment(self.id)
                end
                if breakAssignment == "anything" or breakAssignment == "work" then
                    forceLeisure = true
                end
            end
            if forceLeisure ~= true then
                if self:beginBaseTask(ticks) then
                    return
                end
            end
            if self:beginBaseHygiene(ticks) then
                return
            end
            local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
                and KnoxPersistence.getBaseResidentIds(self.baseId) or {}
            -- Scheduled sleep rests through the night; scheduled recreation
            -- stays inside the ambient set (rest/snack/socialize/stroll) and
            -- never flat-stands through the window.
            local idleAssignment = self.lastScheduleAssignment
            if idleAssignment == nil and KnoxBaseJobs.scheduleAssignment ~= nil then
                idleAssignment = KnoxBaseJobs.scheduleAssignment(self.id)
            end
            if idleAssignment == "sleep" then
                self:beginScheduledBaseSleep(ticks)
                return
            end
            -- Company time keeps the lights on: flip a nearby dark room's
            -- switch while settling into leisure, never while working.
            if idleAssignment == "recreation" or forceLeisure
                or idleAssignment == "anything" then
                self:maintainBaseLights(ticks)
            end
            local choice = Controller.baseIdleChoice(
                ticks,
                self.id,
                type(residentIds) == "table" and #residentIds or 1,
                (idleAssignment == "recreation" or forceLeisure) and "recreation" or nil
            )
            if self:answerBaseAlarm(ticks) then
                return
            end
            if self:beginBattlefieldAid(ticks) then
                return
            end
            if choice == "move" then
                self:beginBaseMovement(ticks, false)
            elseif choice == "rest" then
                self:beginAmbientBaseRest(ticks)
            elseif choice == "snack" then
                if not self:beginAmbientSnack(ticks) then
                    self.activeDecision = "base_idle"
                    self.state = "BASE_IDLE"
                    self.nextThink = ticks + 600 + Controller.baseIdleJitter(self.id)
                    sayDialogue(self.character, self.id, "base_idle", ticks, 1800)
                end
            elseif choice == "socialize" then
                if not self:beginAmbientSocial(ticks) then
                    self.activeDecision = "base_idle"
                    self.state = "BASE_IDLE"
                    self.nextThink = ticks + 600 + Controller.baseIdleJitter(self.id)
                    sayDialogue(self.character, self.id, "base_idle", ticks, 1800)
                end
            elseif choice == "tv" then
                if not self:beginAmbientWatch(ticks) then
                    self:beginAmbientBaseRest(ticks)
                end
            elseif choice == "tidy" then
                if not self:beginBaseOrganize(ticks) then
                    self.activeDecision = "base_idle"
                    self.state = "BASE_IDLE"
                    self.nextThink = ticks + 600 + Controller.baseIdleJitter(self.id)
                    sayDialogue(self.character, self.id, "base_idle", ticks, 1800)
                end
            else
                self.activeDecision = "base_idle"
                self.state = "BASE_IDLE"
                self.nextThink = ticks + 600 + Controller.baseIdleJitter(self.id)
                sayDialogue(self.character, self.id, "base_idle", ticks, 1800)
            end
        elseif self:beginBaseTask(ticks) then
            return
        end
        return
    end
    if self.factionBaseCandidate ~= nil then
        if not self:beginFactionBaseScout(ticks) then
            self.nextThink = ticks + THINK_MIN_TICKS
        end
        return
    end
    if self.campId ~= nil and self.camp ~= nil then
        if self:followScavengeParty(ticks) then
            return
        end
        local atCamp = KnoxFactionCamps.contains(
            self.camp,
            self.character:getCurrentSquare()
        )
        if not atCamp then
            if self:runScavengeSortie(ticks) then
                return
            end
            if self.campExcursion and not self.campExcursionExplored then
                self.campExcursionExplored = true
                if self:beginExploration(ticks) then
                    return
                end
            end
            if not self:beginCampMovement(ticks, true) then
                self.nextThink = math.max(
                    self.nextThink or 0,
                    ticks + Controller.TUNING.CAMP_POSITION_FAILURE_TICKS
                )
            end
            return
        end
        if self.campExcursion then
            self.campExcursion = false
            self.campExcursionExplored = false
        end
        if self:runScavengeSortie(ticks) then
            return
        end
        if self.campPosition == nil then
            if not self:beginCampMovement(ticks, false) then
                self.nextThink = math.max(
                    self.nextThink or 0,
                    ticks + Controller.TUNING.CAMP_POSITION_FAILURE_TICKS
                )
            end
            return
        end
        local choice = Controller.campIdleChoice(
            ticks,
            self.campSlot,
            ticks >= (self.nextCampExcursion or 0)
        )
        if self:answerBaseAlarm(ticks) then
            return
        end
        if self:beginBattlefieldAid(ticks) then
            return
        end
        if choice == "rest" then
            self:beginCampAmbientRest(ticks)
        elseif choice == "reposition" then
            self.campPositionCycle = (self.campPositionCycle or 0) + 1
            self:beginCampMovement(ticks, false)
        elseif choice == "excursion" then
            self:beginCampExcursion(ticks)
        else
            self.activeDecision = "camp_idle"
            self.state = "CAMP_IDLE"
            self.nextThink = ticks + Controller.TUNING.CAMP_DECISION_TICKS
        end
        return
    end
    if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil then
        self:applyGroupLeaderOrder(ticks)
        if self.groupLeaderOrder ~= nil and self.groupLeaderOrder.kind == "hold" then
            -- This explicit leader directive is below threat/need/combat scans
            -- (which run before think) and does not own a native action. A
            -- later follow/cancel/expiry simply returns the follower to the
            -- existing formation branch below.
            self.activeDecision = "leader_hold"
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
            return
        end
        if self.groupObjective ~= nil and self.groupObjective.kind == "night_shelter"
            and self:beginNightShelter(ticks) then
            return
        end
        local formationTarget = findFormationTarget(
            self.groupLeader,
            self.character,
            self.groupFormationSlot, self.id
        )
        local distance = formationTarget ~= nil and navigationDistanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > Controller.TUNING.FORMATION_ARRIVAL_TOLERANCE_SQUARED then
            self:beginGroupFollow(ticks)
        else
            self:resetMovementRecovery()
            self.formationMovementPace = nil
            if self.groupObjectiveChanged then
                self.groupObjectiveChanged = false
                self.nextGroupObjectiveAssist = math.max(
                    self.nextGroupObjectiveAssist or 0,
                    ticks + self.groupFormationSlot * 45
                )
            elseif ticks >= (self.nextGroupObjectiveAssist or 0)
                and Controller.shouldAssistGroupObjective(
                    self.groupObjective,
                    navigationDistanceSquared(
                        self.character:getCurrentSquare(),
                        self.groupLeader:getCurrentSquare()
                    )
                ) then
                self.nextGroupObjectiveAssist = ticks
                    + Controller.TUNING.GROUP_OBJECTIVE_ASSIST_COOLDOWN_TICKS
                    + self.groupFormationSlot * 120
                if self:beginExploration(ticks) then
                    return
                end
                self.nextGroupObjectiveAssist = ticks
                    + Controller.TUNING.GROUP_OBJECTIVE_ASSIST_RETRY_TICKS
                    + self.groupFormationSlot * 30
            end
            if self:beginBattlefieldAid(ticks) then
                return
            end
            if self:beginFollowerHygiene(ticks) then return end
            self:beginFollowerCompany(ticks, self.groupLeader, false)
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
        end
        return
    end
    local distantMember, distantDistance = self:findDistantGroupMember()
    if distantMember ~= nil then
        if distantDistance > Controller.TUNING.GROUP_RETRIEVE_LEASH_SQUARED
            and self:beginGroupRegroup(distantMember, ticks) then
            return
        end
        self.state = "GROUP_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + 90)
        return
    end
    if self.forceTravel then
        if not self:beginRoam(ticks) then
            self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        end
        return
    end
    if self:beginNightShelter(ticks) then
        return
    end
    if not self:beginExploration(ticks) then
        self:beginRoam(ticks)
    end
end

function Controller:updateBaseTaskAction(ticks)
    if self.state == "BASE_TASK_ACTION" then
        if self.baseTask == nil
            or (self.baseTask.type ~= "barricade"
                and self.baseTask.type ~= "farm_water"
                and self.baseTask.type ~= "farm_harvest"
                and self.baseTask.type ~= "farm_plow"
                and self.baseTask.type ~= "farm_seed"
                and self.baseTask.type ~= "chop_tree"
                and self.baseTask.type ~= "saw_logs"
                and self.baseTask.type ~= "haul_corpse"
                and self.baseTask.type ~= "burn_corpse"
                and self.baseTask.type ~= "repair") then
            self:finishBaseTask(false, "unsupported_base_action")
            self:finishDecision(ticks)
            return true
        end
        if hasPendingTimedActions(self.character) then return end
        if self.baseTask.type == "barricade" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskBarricadeTarget
                if target == nil or not KnoxBaseBarricades.isTargetValid(
                    target,
                    self.character
                ) then
                    local targetReason
                    target, targetReason = KnoxBaseBarricades.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskBarricadeTarget = target
                    if target == nil then
                        target = self:retargetBarricadeTask()
                        self.baseTaskBarricadeTarget = target
                    end
                    if target == nil then
                        if KnoxBaseBarricades.isTargetComplete ~= nil
                            and KnoxBaseBarricades.isTargetComplete(self.base, self.baseTask.target, self.character) then
                            self:finishBaseTask(true, "barricade_already_secured")
                            self:finishDecision(ticks)
                            return true
                        end
                        self:failBaseTaskAction(
                            ticks,
                            "barricade_target_invalid:" .. tostring(targetReason)
                        )
                        return true
                    end
                end
                local queueBefore = nil
                pcall(function()
                    local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
                    local queue = queues ~= nil and queues[self.character] or nil
                    if queue ~= nil and type(queue.queue) == "table" then queueBefore = #queue.queue end
                end)
                local action, actionResult = KnoxBaseBarricades.queueAction(
                    self.character,
                    target,
                    self.base
                )
                if action == nil then
                    local pos = self:diagPos()
                    local tsquare = target ~= nil and target.square or nil
                    local tpos = diagSquare(tsquare)
                    local dist2 = nil
                    if pos ~= nil and tpos ~= nil then
                        dist2 = (pos.x - tpos.x) ^ 2 + (pos.y - tpos.y) ^ 2
                    end
                    self:diag("barricade", "queue_failed", {
                        reason = tostring(actionResult),
                        queueBefore = queueBefore,
                        dist2 = dist2,
                        before = self.baseTaskBarricadeBefore,
                    })
                    self:failBaseTaskAction(ticks, "barricade_queue:" .. tostring(actionResult))
                    return true
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                self.baseTaskActionQueueTicks = ticks
                self:diagOnce("barricade", "action_queued", {
                    queueBefore = queueBefore,
                    before = self.baseTaskBarricadeBefore,
                })
                return true
            end
            if not self.character:getCharacterActions():isEmpty() then
                return true
            end
            local target = self.baseTaskBarricadeTarget
            local complete = KnoxBaseBarricades.isComplete(
                target,
                self.character,
                self.baseTaskBarricadeBefore
            )
            local after = KnoxBaseBarricades.plankCount(target, self.character)
            local stillValid = false
            pcall(function()
                stillValid = KnoxBaseBarricades.isTargetValid(target, self.character) == true
            end)
            local queueDepth = nil
            pcall(function()
                local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
                local queue = queues ~= nil and queues[self.character] or nil
                if queue ~= nil and type(queue.queue) == "table" then queueDepth = #queue.queue end
            end)
            local pos = self:diagPos()
            local tsquare = target ~= nil and target.square or nil
            local tpos = diagSquare(tsquare)
            local dist2 = nil
            if pos ~= nil and tpos ~= nil then
                dist2 = (pos.x - tpos.x) ^ 2 + (pos.y - tpos.y) ^ 2
            end
            self:diag("barricade", complete and "completed" or "not_completed", {
                before = self.baseTaskBarricadeBefore, after = after,
                queueDepth = queueDepth, stillValid = stillValid,
                dist2 = dist2, waitTicks = ticks - (self.baseTaskActionQueueTicks or ticks),
            })
            self:finishBaseTask(
                complete,
                complete and "barricade_plank_added" or "barricade_not_completed"
            )
            if complete then
                KnoxActivityFeed.speak(self.character, "One more layer on the windows.")
            end
            self:finishDecision(ticks)
            return true
        end
        if self.baseTask.type == "haul_corpse" then
            -- Drop-destination cooldown: after a failed drop at these coords,
            -- do not touch the body again until it expires. This converts a
            -- grab→carry→release→regrab loop (e.g. fence-separated disposal)
            -- into one bounded attempt per cooldown window.
            do
                local cd = self.corpseDropCooldown
                local tgt = self.baseTask ~= nil and self.baseTask.target or nil
                if cd ~= nil and tgt ~= nil and ticks < (cd.untilTick or 0)
                    and tostring(tgt.dropX) == tostring(cd.x)
                    and tostring(tgt.dropY) == tostring(cd.y)
                    and tostring(tgt.dropZ) == tostring(cd.z) then
                    self.baseTaskCorpseTarget = nil
                    self:failBaseTaskAction(ticks, "corpse_drop_cooldown")
                    return true
                end
            end
            if not self.baseTaskActionQueued then
                local target = self.baseTaskCorpseTarget
                if target == nil then
                    target = KnoxBaseCorpseHandling.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskCorpseTarget = target
                end
                if target == nil then
                    self:failBaseTaskAction(ticks, "corpse_target_invalid")
                    return true
                end
                local action, actionResult
                if self.baseTaskCorpsePhase == "drop" then
                    action, actionResult = KnoxBaseCorpseHandling.queueDrop(
                        self.character,
                        target
                    )
                else
                    -- The native grab settles asynchronously: never stack a
                    -- second grab while a body is already attached.
                    local dragging = false
                    if KnoxBaseCorpseHandling ~= nil
                        and KnoxBaseCorpseHandling.isDragging ~= nil then
                        local ok, value = pcall(function()
                            return KnoxBaseCorpseHandling.isDragging(self.character)
                        end)
                        dragging = ok and value == true
                    end
                    if dragging then
                        self.nextThink = math.max(self.nextThink or 0,
                            ticks + THINK_MIN_TICKS)
                        return true
                    end
                    self.baseTaskCorpsePhase = "grab"
                    action, actionResult = KnoxBaseCorpseHandling.queueGrab(
                        self.character,
                        target
                    )
                end
                if action == nil then
                    self:failBaseTaskAction(ticks, "corpse_queue:" .. tostring(actionResult))
                    return true
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return true
            end
            if not self.character:getCharacterActions():isEmpty() then
                return true
            end
            if self.baseTaskCorpsePhase == "grab" then
                local step, transition, verifyUntil =
                    KnoxBaseCorpseHandling.nextGrabStep(
                        self.character,
                        self.baseTaskCorpseGrabRetryIssued,
                        self.baseTaskCorpseGrabVerifyUntil,
                        ticks
                    )
                self.baseTaskCorpseGrabVerifyUntil = verifyUntil
                if step == "wait" then
                    return true
                end
                if step == "retry" then
                    local requested, retryResult =
                        KnoxBaseCorpseHandling.requestGrabRetry(
                            self.character,
                            self.baseTaskCorpseTarget
                        )
                    if not requested then
                        self:failBaseTaskAction(ticks,
                            "corpse_grab_retry:" .. tostring(retryResult))
                        return true
                    end
                    self.baseTaskCorpseGrabRetryIssued = true
                    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                        .. " corpse-grab-retry=" .. tostring(retryResult)
                        .. " transition=" .. tostring(transition))
                    return true
                end
                if step ~= "ready" then
                    self:failBaseTaskAction(ticks,
                        "corpse_grab_not_attached:" .. tostring(transition))
                    return true
                end
                local target = self.baseTaskCorpseTarget
                if target == nil or target.dropSquare == nil then
                    pcall(function() self.character:setDoGrappleLetGo() end)
                    self:failBaseTaskAction(ticks, "corpse_drop_square_unavailable")
                    return true
                end
                local moveResult = tostring(self.bridge:moveNpc(
                    self.id,
                    target.dropSquare
                ))
                if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
                    pcall(function() self.character:setDoGrappleLetGo() end)
                    do
                        local tgt = self.baseTask ~= nil and self.baseTask.target or nil
                        self.corpseDropCooldown = {
                            x = tgt ~= nil and tgt.dropX or nil,
                            y = tgt ~= nil and tgt.dropY or nil,
                            z = tgt ~= nil and tgt.dropZ or nil,
                            untilTick = ticks + BLOCKED_AREA_COOLDOWN_TICKS,
                        }
                    end
                    self:failBaseTaskAction(ticks, "corpse_drop_move:" .. moveResult)
                    return true
                end
                self.baseTaskCorpsePhase = "drop"
                self.baseTaskActionQueued = false
                self.baseTaskCorpseDropVerifyUntil = nil
                self.baseTaskCorpseDropRetryIssued = nil
                self.baseTaskStartedAt = ticks
                self:noteTaskTravelStart(ticks)
                self.state = "BASE_TASK_MOVE"
                return true
            end
            local step, transition, verifyUntil =
                KnoxBaseCorpseHandling.nextDropStep(
                    self.character,
                    self.baseTaskCorpseDropRetryIssued,
                    self.baseTaskCorpseDropVerifyUntil,
                    ticks
                )
            self.baseTaskCorpseDropVerifyUntil = verifyUntil
            if step == "wait" then
                return true
            end
            if step == "retry" then
                local requested, retryResult =
                    KnoxBaseCorpseHandling.requestDropRetry(self.character)
                if not requested then
                    self:failBaseTaskAction(ticks,
                        "corpse_drop_retry:" .. tostring(retryResult))
                    return true
                end
                self.baseTaskCorpseDropRetryIssued = true
                print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                    .. " corpse-drop-retry=" .. tostring(retryResult)
                    .. " transition=" .. tostring(transition))
                return true
            end
            if step ~= "ready" then
                pcall(function() self.character:setDoGrappleLetGo() end)
                self:failBaseTaskAction(ticks,
                    "corpse_drop_not_released:" .. tostring(transition))
                return true
            end
            local accepted = self:finishBaseTask(true, "corpse_hauled")
            if accepted then
                KnoxActivityFeed.speak(self.character, "The body is out of the way.")
            end
            self:finishDecision(ticks)
            return true
        end
        if self.baseTask.type == "burn_corpse" then
            -- Burning is instant once on site with a lighter: delete piled
            -- corpses via native removal. No grab/drag needed.
            local zoneId = self.baseTask.target ~= nil and self.baseTask.target.zoneId or nil
            local removed, result = KnoxBaseCorpseHandling.burnZoneCorpses(self.base, zoneId)
            if removed ~= nil and removed > 0 then
                local accepted = self:finishBaseTask(true, "corpses_burned:" .. tostring(removed))
                if accepted then KnoxActivityFeed.speak(self.character, "Burned the pile.") end
            else
                self:failBaseTaskAction(ticks, tostring(result or "nothing_to_burn"))
                return true
            end
            self:finishDecision(ticks)
            return true
        end
        if self.baseTask.type == "repair" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskRepairTarget
                if target == nil then
                    target = KnoxBaseRepairs.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskRepairTarget = target
                    self.baseTaskRepairBefore = target ~= nil
                        and KnoxBaseRepairs.snapshot(target) or nil
                end
                if target == nil then
                    self:failBaseTaskAction(ticks, "repair_target_invalid")
                    return true
                end
                local action, actionResult = KnoxBaseRepairs.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    self:failBaseTaskAction(ticks,
                        "repair_queue:" .. tostring(actionResult))
                    return true
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return true
            end
            if not self.character:getCharacterActions():isEmpty() then
                return true
            end
            local complete = KnoxBaseRepairs.isComplete(
                self.baseTaskRepairTarget,
                self.baseTaskRepairBefore
            )
            local afterRepair = nil
            pcall(function()
                afterRepair = KnoxBaseRepairs.snapshot(self.baseTaskRepairTarget)
            end)
            self:diagActionVerdict("repair", complete,
                self.baseTaskRepairBefore, afterRepair)
            local accepted = self:finishBaseTask(
                complete,
                complete and "structure_repaired" or "repair_not_completed"
            )
            if complete and accepted then
                KnoxActivityFeed.speak(self.character, "That should hold now.")
            end
            self:finishDecision(ticks)
            return true
        end
        if self.baseTask.type == "chop_tree" or self.baseTask.type == "saw_logs" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskWoodcuttingTarget
                if target == nil then
                    target = KnoxBaseWoodcutting.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskWoodcuttingTarget = target
                end
                if target == nil then
                    self:failBaseTaskAction(ticks, "tree_target_invalid")
                    return true
                end
                local action, actionResult = KnoxBaseWoodcutting.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    self:failBaseTaskAction(ticks, "tree_queue:" .. tostring(actionResult))
                    return true
                end
                if self.baseTask.type == "chop_tree" then
                    self.baseTaskWoodcuttingBefore = target.tree:getObjectIndex()
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return true
            end
            if not self.character:getCharacterActions():isEmpty() then
                return true
            end
            local complete = KnoxBaseWoodcutting.isComplete(
                self.baseTaskWoodcuttingTarget,
                self.baseTaskWoodcuttingBefore
            )
            local afterTree = nil
            pcall(function()
                afterTree = self.baseTaskWoodcuttingTarget ~= nil
                    and self.baseTaskWoodcuttingTarget.tree ~= nil
                    and self.baseTaskWoodcuttingTarget.tree:getObjectIndex() or nil
            end)
            self:diagActionVerdict(self.baseTask.type, complete,
                self.baseTaskWoodcuttingBefore, afterTree)
            local taskType = self.baseTask.type
            local finishReason = complete
                and (taskType == "saw_logs" and "logs_sawn" or "tree_chopped")
                or (taskType == "saw_logs" and "logs_not_sawn" or "tree_not_chopped")
            local accepted = self:finishBaseTask(
                complete,
                finishReason
            )
            if complete and accepted then
                KnoxActivityFeed.speak(self.character,
                    taskType == "saw_logs"
                        and "The logs are ready." or "That tree is down."
                )
            end
            self:finishDecision(ticks)
            return true
        end
        if self.baseTask.type == "farm_water"
            or self.baseTask.type == "farm_harvest"
            or self.baseTask.type == "farm_plow"
            or self.baseTask.type == "farm_seed" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskFarmingTarget
                if target == nil then
                    target = KnoxBaseFarming.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskFarmingTarget = target
                end
                if target == nil then
                    self:failBaseTaskAction(ticks, "farming_target_invalid")
                    return true
                end
                local water = nil
                if self.baseTask.type == "farm_water" then
                    local item, uses = KnoxBaseFarming.findWaterItem(
                        self.character,
                        self.baseTask.target.waterItemType
                    )
                    if item ~= nil then
                        water = {
                            item = item,
                            uses = math.min(
                                tonumber(uses) or 0,
                                tonumber(self.baseTask.target.waterUses) or 0
                            ),
                        }
                    end
                end
                local action, actionResult = KnoxBaseFarming.queueAction(
                    self.character,
                    target,
                    water
                )
                if action == nil then
                    self:failBaseTaskAction(ticks, "farming_queue:" .. tostring(actionResult))
                    return true
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return true
            end
            if not self.character:getCharacterActions():isEmpty() then
                return true
            end
            local complete = KnoxBaseFarming.isComplete(
                self.baseTaskFarmingTarget,
                self.baseTaskFarmingBefore
            )
            local afterFarm = nil
            pcall(function()
                afterFarm = KnoxBaseFarming.snapshot(self.baseTaskFarmingTarget)
            end)
            self:diagActionVerdict(self.baseTask.type, complete,
                self.baseTaskFarmingBefore, afterFarm)
            local taskType = self.baseTask.type
            local accepted = self:finishBaseTask(
                complete,
                complete and "farming_action_complete" or "farming_action_not_completed"
            )
                if complete and accepted then
                    KnoxActivityFeed.speak(self.character,
                        taskType == "farm_harvest" and "Harvest is in."
                        or taskType == "farm_water" and "Crops are watered."
                        or taskType == "farm_seed" and "Seeds are in."
                        or "The furrow is ready."
                    )
            end
            self:finishDecision(ticks)
            return true
        end
    end

    return false
end

function Controller:tick(ticks)
    self.currentTicks = ticks
    if self.state ~= "PLAYER_CONVERSATION" then self.playerConversation = nil end
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if self.character ~= nil and vehicles ~= nil and vehicles.isBusy ~= nil then
        -- Native passenger actions own their route and inputs until completion.
        local busy, result = vehicles.isBusy(self.character)
        if busy then
            -- A boarding lease must not hold the survivor deaf: retreat-worthy
            -- danger or a critical need releases the lease through the existing
            -- owner, and the normal arbitration below runs on the next tick
            -- with fresh scans. Fightable danger can wait out the short
            -- boarding window; fleeing cannot. Either check failing safe
            -- preserves today's behavior instead of erroring the tick.
            local flee = false
            if fleeAssessment ~= nil then
                local assessed, verdict = pcall(fleeAssessment, self)
                flee = assessed and verdict == true
            end
            local need = nil
            if KnoxSurvivorNeeds ~= nil and KnoxSurvivorNeeds.decide ~= nil then
                local decided, decision = pcall(KnoxSurvivorNeeds.decide, self.character, nil)
                if decided then need = decision end
            end
            if flee or (need ~= nil and need.kind ~= nil and need.kind ~= "roam") then
                vehicles.cancel(self.character)
                self.nextThreatScan = 0
                self.nextThink = 0
                return
            end
            return
        end
        if result == "interrupted" then self.nextThreatScan = 0; self.nextThink = 0 end
        if self.character.getVehicle ~= nil and self.character:getVehicle() ~= nil then return end
    end
    if self:tryBoardFollowVehicle(ticks) then return end
    -- Disarm the one-shot rest-exit get-up pulse once the body is back on
    -- its feet and not knocked down. Without this the latch survives until
    -- the next knockdown and stands the survivor up instantly, unlike a
    -- player whose flag is pulsed only by discrete input. Knockdown timing
    -- itself is logged so parity stays visible instead of assumed.
    if self.character ~= nil then
        local sitting = safeMethod(self.character, "isSitOnGround", true)
            or safeMethod(self.character, "isSittingOnFurniture", true)
        local down = safeMethod(self.character, "isKnockedDown", true)
            or safeMethod(self.character, "isOnFloor", true)
        if self.forceGetUpLatched == true and not sitting and not down then
            pcall(function() self.character:setVariable("forceGetUp", false) end)
            self.forceGetUpLatched = nil
        end
        if down and self.knockedDownSince == nil then
            self.knockedDownSince = ticks
            self:diag("combat", "knocked_down", nil)
        elseif not down and self.knockedDownSince ~= nil then
            self:diag("combat", "stood_up", {
                downTicks = (tonumber(ticks) or 0) - self.knockedDownSince,
            })
            self.knockedDownSince = nil
        end
    end
    if self.tradeAction ~= nil and self.state ~= "TRADING" then self:cancelTrade("behavior_changed") end
    if self.character == nil or self.character:getCurrentSquare() == nil then
        self:cancelTrade("detached")
        -- Freeze ownership on entry so a streamed-out shell cannot keep stale
        -- move/combat leases while detached.
        if self.bridge ~= nil then
            if self.bridge.cancelNpcMove ~= nil then
                pcall(function() self.bridge:cancelNpcMove(self.id) end)
            end
            if self.bridge.resetNpcCombat ~= nil then
                pcall(function() self.bridge:resetNpcCombat(self.id) end)
            end
        end
        -- The population owner, not the behavior controller, decides when an NPC is
        -- actually stored. A streamed-out shell can temporarily lose its square before
        -- the hibernation pass captures/removes it, so keep that state explicit.
        self.state = "DETACHED"
        self.knockedDownSince = nil
        return
    end

    if self:recoverFromDetached(ticks) then
        return
    end

    -- Direct player companions remain excluded from autonomous retreat. Base
    -- residents may now keep the same bounded retreat until danger clears; the
    -- interrupted base task or durable supply run resumes through its owner.
    if self.state == "FLEEING"
        and self.companionOwnerId ~= nil then
        self.bridge:cancelNpcMove(self.id)
        self:resetMovementRecovery()
        self.fleeRecoveryUntil = nil
        self.fleeTarget = nil
        self.failedFleeTarget = nil
        self.fleeSafeScans = 0
        self.combatDisengageUntil = 0
        self:finishDecision(ticks)
        self.nextThink = ticks + 5
        return
    end

    if self.observedState ~= self.state then
        self.observedState = self.state
        self.stateStartedAt = ticks
    end

    if self.state == "CORPSE_DEFENSE_RELEASE" then
        self:updateCorpseDefenseRelease(ticks)
        return
    end

    if self.state == "BASE_TASK_MOVE" and self.baseTask ~= nil
        and (self.baseTask.type == "guard" or self.baseTask.type == "patrol")
        and (self.baseTask.state ~= "claimed" or self.baseTask.claimedBy ~= self.id) then
        self.nextSecurityCheck = ticks
        self:updateBaseSecurityDuty(ticks)
        return
    end

    -- Gear is reconsidered only while the survivor is otherwise idle. Combat owns
    -- firearm/melee transitions, and timed actions must never be interrupted just
    -- to swap a marginal item.
    if self.state == "IDLE" then
        self:reconsiderEquipment(ticks, false)
    end

    local stateAge = ticks - (self.stateStartedAt or ticks)
    local movementState = self.state == "MOVING_TO_SUPPLY"
        or self.state == "EVENT_TRAVEL"
        or self.state == "MOVING_TO_DEPOSIT"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "ROAMING"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_DEFEND"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY"
        or self.state == "MOVING_TO_REST"
        or self.state == "MOVING_TO_BASE_CANDIDATE"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "AWAY_RETURN"
        or self.state == "FLEEING"
    local actionState = self.state == "LOOTING"
        or self.state == "OPENING_ENTRY_WINDOW"
        or self.state == "INVENTORY_CLEANUP"
        or self.state == "SEARCHING"
        or self.state == "TIMED_ACTION"
        or self.state == "ROBBING"
        or (self.state == "BASE_TASK_WORK"
            and (self.baseTask == nil or self.baseTask.type ~= "guard"))
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
        or self.state == "AID_ACTION"
        or self.state == "GROUP_SUPPORT"
    if (movementState and stateAge > Controller.TUNING.MOVEMENT_TIMEOUT_TICKS)
        or (actionState and stateAge > Controller.TUNING.ACTION_TIMEOUT_TICKS)
        or (self.state == "BREAKING_LOCKED_DOOR"
            and stateAge > Controller.TUNING.MOVEMENT_TIMEOUT_TICKS) then
        if self.securityRoute~=nil and (self.state=="BASE_TASK_MOVE"
            or self.state=="MOVING_TO_COMPANION_PATROL" or self.state=="MOVING_TO_COMPANION_POINT") then
            self:deferSecurityRoute(ticks,"state_timeout",self.securityRoute.base)
            return
        end
        if self.state == "FLEEING" then
            self:recoverFleeMovement("state_timeout", ticks)
            return
        elseif self.state == "BASE_RETURN" or self.state == "BASE_PATROL" then
            self:handleBaseMovementFailure("state_timeout", ticks)
            return
        elseif self.state == "MOVING_TO_REST" then
            self:handleRestMovementFailure("state_timeout", ticks)
            return
        elseif self.state == "COMPANION_FOLLOW" or self.state == "AWAY_RETURN" then
            self.bridge:cancelNpcMove(self.id)
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        elseif self.state == "MOVING_TO_BASE_CANDIDATE" then
            self:rejectFactionBaseCandidate(ticks, "state_timeout")
        end
        self:abandonCurrentDecision(ticks, "state_timeout_" .. tostring(self.state))
        return
    end

    local traversalBusy = movementState and nativeTraversalBusy(self.character)
    -- Both danger evaluation and active-combat decisions consume this scheduled
    -- observation. Advancing the deadline must not starve the combat branch.
    local threatScanDue = ticks >= self.nextThreatScan and not traversalBusy
    if threatScanDue then
        self.nextThreatScan = ticks + THREAT_SCAN_TICKS
        local stealthCrowd = self.state ~= "COMBAT" and self.state ~= "FLEEING"
            and shouldRemainStealthy(self)
        if not stealthCrowd then
            local flee, assessment = fleeAssessment(self)
            if self.state ~= "FLEEING" and flee then
                local admitted, reason = self:beginFlee(ticks, assessment)
                -- Whether route acquisition succeeded or entered bounded recovery,
                -- do not reacquire an attack in this same danger scan. When the
                -- player explicitly disables retreat, keep ordinary combat
                -- arbitration on this same scan instead of delaying it.
                if admitted or reason ~= "retreat_disabled" then return end
            end
            if self.state == "FLEEING" and flee and self.fleeTarget == nil
                and ticks >= (self.fleeRecoveryUntil or 0) then
                self:beginFlee(ticks, assessment)
                return
            end
            if self.state == "FLEEING" and retreatIsSafelyClear(self, flee, assessment, ticks) then
                self.bridge:cancelNpcMove(self.id)
                self:resetMovementRecovery()
                self.fleeRecoveryUntil = nil
                self.fleeTarget = nil
                self.failedFleeTarget = nil
                self.combatDisengageUntil = ticks + FLEE_DISENGAGE_TICKS
                self:finishDecision(ticks)
                self.nextThink = ticks + 5
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " retreat-complete safe_scans=" .. tostring(self.fleeSafeScans)
                )
                return
            end
            if self.state ~= "COMBAT" and self.state ~= "FLEEING" then
                local threat = nearestThreat(self, ticks)
                if not self:allowsCompanionThreat(threat) then
                    threat = nil
                end
                -- A corpse carrier cannot safely attack while the native
                -- grapple owns both hands. Release first, then hand off to
                -- defense while retaining the task for later reconsideration.
                local haulingCorpse = self.baseTask ~= nil
                    and self.baseTask.type == "haul_corpse"
                    and KnoxBaseCorpseHandling ~= nil
                    and KnoxBaseCorpseHandling.isDragging ~= nil
                    and KnoxBaseCorpseHandling.isDragging(self.character)
                if threat ~= nil and haulingCorpse then
                    local origin = self.character:getCurrentSquare()
                    local threatSquare = threat:getCurrentSquare()
                    if origin ~= nil and threatSquare ~= nil
                        and distanceSquared(origin, threatSquare) <= 36 then
                        self:interruptCorpseHaulForDefense(threat, ticks)
                        return
                    end
                end
                if threat ~= nil and self:beginCombat(threat) then
                    return
                end
            end
        end
    end

    if self:yieldBaseTaskForNeed(ticks) then return end

    -- A party-food detour is the only autonomous work allowed to take a
    -- settled follower briefly away from formation. Recheck its anchor and
    -- needs before movement updates; native item actions may finish normally.
    if self.state == "MOVING_TO_EXPLORE" and self.pendingSupply ~= nil
        and self.pendingSupply.partySupport == true then
        if self.allowAutoLoot == false then
            self:abandonPartyFoodForFollow(ticks, "disabled")
            return
        end
        local need = KnoxSurvivorNeeds.decide(self.character, nil)
        if need ~= nil and need.kind ~= nil and need.kind ~= "roam"
            and Controller.selfCareReady(self.selfCareRetryAt, need.kind, ticks) then
            self:abandonPartyFoodForFollow(ticks, "urgent_need")
            return
        end
        local _, anchorSquare, anchorReason = self:resolvePlayerPartyAnchor(ticks)
        if anchorSquare == nil then
            self:abandonPartyFoodForFollow(ticks, anchorReason or "anchor_unavailable")
            return
        end
        if not Controller.partyFoodSupportAnchorWithinLeash(
            self.pendingSupply, anchorSquare
        ) then
            self:abandonPartyFoodForFollow(ticks, "player_moved")
            return
        end
    end

    if self.state == "PLAYER_CONVERSATION" then
        self:updatePlayerConversation(ticks)
        return
    end

    if self.state == "TRADING" then
        self.tradeTicksRemaining = (self.tradeTicksRemaining or 0) - 1
        if self.tradeAction == nil then
            self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
        elseif self.tradeTicksRemaining <= 0 or not self.tradeAction:isValid() then
            self:cancelTrade("trade_interrupted_or_expired")
        end
        return
    end

    if self.state == "MEETING_WAIT" or self.state == "MEETING_READY"
        or self.state == "GREETING" then
        return
    end

    if self.state == "ROAMING" and ticks >= (self.nextRoamNeedsCheck or 0) then
        self.nextRoamNeedsCheck = ticks + Controller.TUNING.ROAM_NEEDS_RECHECK_TICKS
        local roamingNeed = KnoxSurvivorNeeds.decide(self.character, nil)
        if Controller.shouldInterruptRoamingForNeed(roamingNeed.kind)
            and Controller.selfCareReady(
                self.selfCareRetryAt,
                roamingNeed.kind,
                ticks
            ) then
            self.bridge:cancelNpcMove(self.id)
            self.roamGoalKey = nil
            self.roamGoalKind = nil
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks
            return
        end
    end

    if self.state == "GROUP_WAIT" then
        if self:applyGroupLeaderOrder(ticks) then return end
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "COMPANION_HOLD" or self.state == "COMPANION_GUARD" then
        -- Keep the persistent order. Ordinary fatigue is deferred, while a
        -- critical body state re-enters think and takes the bounded recovery
        -- exception without clearing the post or directive.
        if ticks >= self.nextThink then
            self.nextThink = ticks + 90
            local need = KnoxSurvivorNeeds.decide(self.character, nil)
            if need ~= nil and need.kind ~= "roam"
                and ((need.kind ~= "rest" and need.kind ~= "sleep")
                    or Controller.isCriticalOrderedRecovery(need)) then
                self.state = "IDLE"
                self.nextThink = ticks
            elseif self.state == "COMPANION_GUARD" and self.companionDirective ~= nil then
                -- Re-resolve the assigned post after a shove or displacement.
                self:beginCompanionPointDirective(ticks, self.companionDirective)
            end
        end
        return
    end

    if self.state == "COMPANION_DUTY_WAIT" or self.state == "BASE_SECURITY_WAIT" then
        self:updateSecurityRouteWait(ticks,self.state=="BASE_SECURITY_WAIT")
        return
    end

    if self.state == "COMPANION_WAIT" or self.state == "COMPANION_PATROL_WAIT" then
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_IDLE" or self.state == "EVENT_WAIT" then
        if ticks >= self.nextThink then
            self.activeDecision = nil
            self.state = "IDLE"
        end
        return
    end

    if self.state == "CAMP_IDLE" then
        if ticks >= self.nextThink then
            self.activeDecision = nil
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_RECREATION" then
        self:updateBaseRecreation(ticks)
        return
    end

    if self.state == "BASE_HYGIENE" then
        self:updateBaseHygiene(ticks)
        return
    end

    if self.state == "BASE_ORGANIZE" then
        self:updateBaseOrganize(ticks)
        return
    end

    if self.state == "BASE_AMBIENT_REST" then
        if ticks >= self.nextThink then
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "CAMP_AMBIENT_REST" then
        if ticks >= self.nextThink then
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "COMPANION_RELAX" then
        self:updateCompanionRelax(ticks)
        return
    end

    if self.state == "BASE_TASK_SUPPLY_WAIT" then
        if self.baseTask == nil then
            self:finishDecision(ticks)
        elseif ticks >= (self.nextThink or 0) then
            self:beginBaseTaskSupplyOrWork(ticks)
        end
        return
    end

    if self.state == "BASE_TASK_PATROL_WAIT" then
        self:updateBaseSecurityDuty(ticks)
        if self.state ~= "BASE_TASK_PATROL_WAIT" then return end
        if self.baseTask == nil then
            self:finishDecision(ticks)
        elseif ticks >= (self.nextThink or 0) then
            self:beginBaseTaskWorkMove(ticks)
        end
        return
    end

    if self.state == "BASE_TASK_WORK" then
        if self.baseTask == nil then
            self.state = "IDLE"
            self.activeDecision = nil
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        end
        if self.baseTask.type == "guard" then
            self:updateBaseSecurityDuty(ticks)
            return
        end
        local started = self.baseTaskStartedAt or ticks
        if ticks - started >= KnoxBaseJobs.workDuration(self.baseTask) then
            local taskType = self.baseTask.type
            local accepted = self:finishBaseTask(true, "completed_" .. tostring(taskType))
            local completionLines = {
                guard = "All clear here.", patrol = "Patrol route is clear.",
                barricade = "That opening is secured.",
                repair = "That repair is finished.",
                haul_corpse = "The body is out of the way.", farm_water = "The crops are watered.",
                farm_harvest = "The harvest is gathered.", farm_plow = "The soil is ready.",
                farm_seed = "The plot is planted.", chop_tree = "The tree is down.",
                saw_logs = "The logs are cut.",
            }
            if accepted then
                KnoxActivityFeed.speak(self.character,
                    completionLines[taskType] or "That job is finished."
                )
            end
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "BASE_COOKING" then
        self:updateBaseCooking(ticks)
        return
    end

    if self.state == "BASE_TASK_SUPPLY_TRANSFER" then
        if self.baseTask == nil or self.baseTaskSupplyTransfer == nil then
            self.state = "IDLE"
            self.activeDecision = nil
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        end
        if hasPendingTimedActions(self.character) then
            return
        end
        local transfer = self.baseTaskSupplyTransfer
        local inventory = self.character ~= nil and self.character:getInventory() or nil
        local received = inventory ~= nil and transfer.item ~= nil
            and inventory:contains(transfer.item)
        if not received then
            -- An empty timed-action queue is not proof that native transfer
            -- succeeded.  The action can be rejected after it was queued, or
            -- the item can be placed somewhere other than the worker's
            -- inventory when capacity/validity changes.  Do not send the
            -- resident to a native job without the real tool/material.
            self:failBaseTaskAction(ticks, "assigned_supply_transfer_not_completed")
            return
        end
        self:releaseBaseTaskSupplyTransfer()
        self:beginBaseTaskSupplyOrWork(ticks)
        return
    end

    if self.state == "AID_ACTION" then
        if hasPendingTimedActions(self.character) then
            return
        end
        local patient = self.pendingAidPatient
        local helped = false
        if patient ~= nil then
            local ok, healed = pcall(function()
                local parts = patient:getBodyDamage():getBodyParts()
                for index = 0, parts:size() - 1 do
                    local part = parts:get(index)
                    if part == self.pendingAidPart then
                        return part:bandaged() or not part:bleeding()
                    end
                end
                return true
            end)
            helped = ok and healed == true
        end
        self:releaseAid()
        self.nextAidAt = ticks + AID_RETRY_TICKS
        self:diag("medical", helped and "aid_completed" or "aid_no_effect", nil)
        if helped then
            KnoxActivityFeed.speak(self.character, "Hold still, I've got you.")
        end
        self:finishDecision(ticks)
        return
    end

    if self:updateBaseTaskAction(ticks) then return end

    if (self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_REST") and self:hasNeedEscort()
        and ticks >= (self.nextNeedEscortCheck or 0) then
        self.nextNeedEscortCheck = ticks + 30
        local destination = self.state == "MOVING_TO_SUPPLY" and self.pendingSupply or self.pendingRest
        if destination ~= nil and not self:allowNeedDetour(destination.approach, ticks) then
            self.bridge:cancelNpcMove(self.id)
            if self.state == "MOVING_TO_SUPPLY" then self:releaseSupply()
            else self:releaseRestSpot() end
            self:finishDecision(ticks)
            self.nextThink = ticks + 1
            return
        end
    end
    if self.state == "OPENING_ENTRY_WINDOW" then
        self:updateEntryWindow(ticks)
        return
    end
    if self.state == "COMBAT" then
        if threatScanDue then
            -- A dead/peaceful/unloaded target must release native firearm
            -- ownership before reload or aim state is reconsidered. Otherwise
            -- a completed target can keep a timed reload alive until its long
            -- preparation timeout expires.
            if shouldDropCombatTarget(self, ticks) then
                if KnoxFirearmSupport.cancelPreparation ~= nil then
                    KnoxFirearmSupport.cancelPreparation(self.character)
                end
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                self:clearFirearmCombatState()
                self.pendingThreatAwareness = nil
                self:finishDecision(ticks)
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " combat-disengaged reason=invalid_or_irrelevant"
                )
                return
            end
            local replacement = nearestThreat(self, ticks)
            if not self:allowsCompanionThreat(replacement) then
                replacement = nil
            end
            local replacementAwareness = self.pendingThreatAwareness
            if shouldReplaceCombatTarget(self, replacement, replacementAwareness, ticks) then
                local previous = self.combatTarget
                self.lastCombatRetarget = ticks
                -- An emergency human/zombie replacement owns the next native
                -- combat action. Cancel only now, rather than cancelling a
                -- valid reload on every ordinary combat refresh.
                if KnoxFirearmSupport.cancelPreparation ~= nil then
                    KnoxFirearmSupport.cancelPreparation(self.character)
                end
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                self:clearFirearmCombatState()
                self.state = "IDLE"
                self.activeDecision = nil
                if self:beginCombat(replacement) then
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " combat-retarget reason="
                            .. tostring(replacementAwareness ~= nil
                                and replacementAwareness.reason or "closer")
                    )
                    return
                end
                self.failedThreats[replacement] = ticks + THREAT_SCAN_TICKS
                self.state = "IDLE"
                self.nextThink = ticks + THINK_MIN_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " combat-retarget-failed previous=" .. tostring(previous)
                )
                return
            end
            local firearmState, firearmResult = KnoxFirearmSupport.currentCombatState(
                self.character
            )
            if firearmState == "needs_preparation" or firearmState == "reloading" then
                local preparationTarget = self.combatTarget
                local fallbackReason = self:reloadYieldDecision(
                    ticks, preparationTarget, firearmState
                )
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                if fallbackReason ~= nil then
                    self:forceMeleeFallback(ticks, preparationTarget, fallbackReason)
                    firearmState = "melee"
                elseif firearmState == "needs_preparation" then
                    firearmState, firearmResult = KnoxFirearmSupport.prepareForThreat(
                        self.id,
                        self.character,
                        self.bridge,
                        preparationTarget
                    )
                    if firearmState == "reloading" then
                        fallbackReason = self:reloadYieldDecision(
                            ticks, preparationTarget, firearmState
                        )
                        if fallbackReason ~= nil then
                            self:forceMeleeFallback(ticks, preparationTarget, fallbackReason)
                            firearmState = "melee"
                        end
                    end
                end
                self:finishDecision(ticks)
                -- Give a queued rack/reload time to finish. Re-scanning in 15
                -- ticks re-engages the same target and restarts native combat.
                self.nextThreatScan = ticks + COMBAT_RANGED_YIELD_DELAY_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " ranged-combat-yield state=" .. tostring(firearmState)
                        .. " result=" .. tostring(firearmResult)
                )
                return
            end
            self.pendingThreatAwareness = nil
        end
        local result = tostring(self.bridge:tickNpcCombat(self.id))
        if string.find(result, "COMBAT_FIREARM_REQUEST", 1, true) == 1 then
            local fired, fireResult = KnoxFirearmSupport.fireNative(self.character)
            if fired then
                -- One native request was handed to the real Build 42 hook. Keep
                -- the encounter committed to the gun and clear the bounded
                -- ranged-failure streak so ordinary cadence continues.
                self.rangedCombatFailureStreak = 0
                self.rangedEncounterTarget = self.combatTarget
            else
                local preparationTarget = self.combatTarget
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                local preparation, preparationResult = KnoxFirearmSupport.prepareForThreat(
                    self.id,
                    self.character,
                    self.bridge,
                    preparationTarget
                )
                if preparation == "reloading" then
                    local fallbackReason = self:reloadYieldDecision(
                        ticks, preparationTarget, preparation
                    )
                    if fallbackReason ~= nil then
                        self:forceMeleeFallback(ticks, preparationTarget, fallbackReason)
                        preparation = "melee"
                    end
                else
                    self.reloadYieldStreak = 0
                end
                self:finishDecision(ticks)
                self.nextThreatScan = ticks + COMBAT_RANGED_YIELD_DELAY_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " firearm-request-yield result=" .. tostring(fireResult)
                        .. " preparation=" .. tostring(preparation)
                        .. " detail=" .. tostring(preparationResult)
                )
            end
        elseif string.find(result, "COMBAT_FIREARM_FALLBACK", 1, true) == 1 then
            if self.combatTarget ~= nil then
                self.rangedFallbackUntil = self.rangedFallbackUntil
                    or setmetatable({}, { __mode = "k" })
                self.rangedFallbackUntil[self.combatTarget] = ticks
                    + THREAT_FAILURE_COOLDOWN_TICKS
            end
            self.bridge:resetNpcCombat(self.id)
            local fallbackResult = KnoxFirearmSupport.fallbackToMelee(
                self.id,
                self.bridge,
                self.character
            )
            self:releaseCombat()
            self:clearFirearmCombatState()
            self:finishDecision(ticks)
            self.nextThreatScan = ticks + COMBAT_RANGED_YIELD_DELAY_TICKS
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " firearm-close-fallback result=" .. tostring(result)
                    .. " melee=" .. tostring(fallbackResult)
            )
        elseif string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            self.counts.combat = self.counts.combat + 1
            self.bridge:resetNpcCombat(self.id)
            self:releaseCombat()
            self:clearFirearmCombatState()
            self:finishDecision(ticks)
            self.nextThreatScan = math.max(self.nextThreatScan or 0, ticks + COMBAT_RANGED_YIELD_DELAY_TICKS)
            -- Hold formation repath briefly so the follower walks instead of
            -- sprinting to a slot that drifted mid-fight.
            self.nextFormationRefresh = ticks + COMBAT_POST_KILL_FORMATION_DELAY_TICKS
            self.formationCommitUntil = ticks + COMBAT_POST_KILL_FORMATION_DELAY_TICKS
        elseif string.find(result, "COMBAT_FAILED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            self.counts.failures = self.counts.failures + 1
            local fallbackTarget = self.combatTarget
            local primary = nil
            if self.character ~= nil then
                pcall(function() primary = self.character:getPrimaryHandItem() end)
            end
            local rangedFallback = self:noteRangedCombatFailure(primary)
            if fallbackTarget ~= nil then
                self.failedThreats[fallbackTarget] = ticks
                    + THREAT_FAILURE_COOLDOWN_TICKS
            end
            self:releaseCombat()
            if rangedFallback and fallbackTarget ~= nil then
                -- Bounded approach/pursuit retries are exhausted. Release firearm
                -- ownership through the same melee-fallback owner the close-range
                -- token uses. The target stays a valid encounter: its generic
                -- failure cooldown is cleared so a melee attempt can re-engage
                -- immediately instead of being cooled down as unreachable.
                self:forceMeleeFallback(ticks, fallbackTarget, "ranged_combat_failed")
                self.failedThreats[fallbackTarget] = nil
            else
                self:clearFirearmCombatState()
            end
            self:finishDecision(ticks)
            self.nextThreatScan = math.max(self.nextThreatScan or 0, ticks + COMBAT_RANGED_YIELD_DELAY_TICKS)
            self.nextFormationRefresh = ticks + COMBAT_POST_KILL_FORMATION_DELAY_TICKS
        end
        return
    end


    if self.state == "BREAKING_LOCKED_DOOR" then
        -- Leash: never spend a siege on a locked door the player has walked
        -- away from. A companion whose owner is streets away abandons the
        -- break and rejoins instead of retrying indefinitely.
        do
            local anchor = self.companionTarget
            if anchor ~= nil and self.companionDirective ~= nil then
                local okA, aSq = pcall(function() return anchor:getCurrentSquare() end)
                local okM, mSq = pcall(function()
                    return self.character:getCurrentSquare()
                end)
                if okA and okM and aSq ~= nil and mSq ~= nil then
                    local dd = navigationDistanceSquared(aSq, mSq)
                    if (tonumber(dd) or 0) > 225 then
                        self.bridge:resetNpcCombat(self.id)
                        self:countDoorBreakDirectiveMiss(ticks)
                        self:abandonCurrentDecision(ticks, "door_break_player_left")
                        return
                    end
                end
            end
        end
        local result = tostring(self.bridge:tickNpcCombat(self.id))
        if string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            if self.entryDetour ~= nil and self.entryDetour.baseTask == true then
                self:resumeAfterBaseTaskDoorBreak(ticks)
            elseif not self:resumeAfterWindowDetour(ticks) then
                self:abandonCurrentDecision(ticks, "door_break_resume_failed")
            end
        elseif string.find(result, "COMBAT_FAILED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            if self.entryDetour ~= nil and self.entryDetour.baseTask == true then
                self.entryDetour = nil
                self:failBaseTaskAction(ticks, "door_break_failed")
            else
                markPendingAreaBlocked(self, ticks, "door_break_failed")
                self:countDoorBreakDirectiveMiss(ticks)
                self:abandonCurrentDecision(ticks, "door_break_failed")
            end
        end
        return
    end

    if self.state == "INVENTORY_CLEANUP" then
        self:updateInventoryCleanup(ticks)
        return
    end

    if self.state == "GROUP_SUPPORT" then
        if not hasPendingTimedActions(self.character) then
            self:completeGroupSupport(ticks)
        end
        return
    end

    if self.state == "TIMED_ACTION" then
        if not hasPendingTimedActions(self.character) then
            local completed, detail = KnoxSurvivorNeeds.verify(
                self.character,
                self.selfCareIntent
            )
            -- A meal or bottle in a bag requires a native transfer first.
            -- Chain the real eat/drink action immediately after that transfer;
            -- otherwise the survivor reports hunger forever while carrying the
            -- food that the planner already fetched.
            if completed and self.selfCareIntent ~= nil
                and self.selfCareIntent.kind == "prepare_supply" then
                local intent = self.selfCareIntent
                local followup = {
                    kind = intent.needKind,
                    state = KnoxSurvivorNeeds.snapshot(self.character),
                    item = intent.item,
                }
                local action, result, nextIntent = KnoxSurvivorNeeds.execute(
                    self.character, followup)
                if action ~= nil and action ~= false then
                    self.selfCareIntent = nextIntent
                    self.activeDecision = intent.needKind
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " self-care-supply-ready kind=" .. tostring(intent.needKind)
                    )
                    return
                end
                completed = false
                detail = "supply_ready_action=" .. tostring(result)
            end
            local kind = self.selfCareIntent ~= nil
                and self.selfCareIntent.kind or tostring(self.activeDecision)
            if kind == "drink_world" then
                self:releaseSupply()
            end
            if completed then
                self.counts.needs = self.counts.needs + 1
                self.selfCareRetryAt[kind] = nil
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " self-care-complete=" .. tostring(kind)
                        .. " " .. tostring(detail)
                )
            else
                self.selfCareRetryAt[kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
                self:recordFailure(
                    "needs_no_change:" .. tostring(kind) .. ":" .. tostring(detail),
                    ticks,
                    Controller.TUNING.SELF_CARE_RETRY_TICKS
                )
                if kind == "drink_world" then
                    local line = "I couldn't use that water source."
                    if not self:sayAction({ line }, ticks, 1800) then
                        KnoxActivityFeed.speak(self.character, line)
                    end
                end
            end
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "ROBBING" then
        if self.character:getCharacterActions():isEmpty() then
            self.counts.robberies = self.counts.robberies + 1
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " robbery-complete items="
                    .. table.concat(self.pendingRobbery ~= nil
                        and self.pendingRobbery.items or {}, ",")
            )
            self:cancelRobbery(ticks, "completed")
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE"
        or self.state == "EVENT_TRAVEL"
        or self.state == "MOVING_TO_DEPOSIT"
        or self.state == "ROAMING" or self.state == "GROUP_FOLLOW"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_DEFEND"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY"
        or self.state == "MOVING_TO_REST"
        or self.state == "NIGHT_SHELTER_MOVE"
        or self.state == "AID_MOVE"
        or self.state == "MOVING_TO_BASE_CANDIDATE"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "AWAY_RETURN"
        or self.state == "FLEEING" then
        if (self.state == "GROUP_FOLLOW" or self.state == "COMPANION_FOLLOW")
            and self:refreshFormationFollow(ticks) then
            return
        end
        local movement = tostring(self.bridge:tickNpc(self.id))
        -- Hang watchdog for job travel (see noteTaskTravelStart): a route
        -- that holds position with no climb/entry action running is failed
        -- fast with a visible reason instead of timing out and retrying the
        -- same unreachable approach forever.
        if (self.state == "BASE_TASK_SUPPLY_MOVE" or self.state == "BASE_TASK_MOVE")
            and ticks - (self.stateStartedAt or 0) > TASK_TRAVEL_STALL_TICKS
            and not nativeTraversalBusy(self.character)
            and self:taskTravelStalled(ticks) then
            self.bridge:cancelNpcMove(self.id)
            if self.baseTask ~= nil and self.baseTask.type == "haul_corpse"
                and self.baseTaskCorpsePhase == "drop"
                and KnoxBaseCorpseHandling.isDragging(self.character) then
                pcall(function() self.character:setDoGrappleLetGo() end)
            end
            self:failBaseTaskAction(ticks,
                self.state == "BASE_TASK_SUPPLY_MOVE"
                    and "assigned_supply_no_progress" or "task_move_no_progress")
            return
        end
        if movement == "Succeeded" then
            self:resetMovementRecovery()
            -- Road-biased intermediate arrival: continue to the stored final
            -- destination instead of running arrival logic for a midpoint.
            -- moveWithTravelPace stashes finals in roadFinalById, so check it
            -- directly; self.travelFinalSquare is only set by explicit callers.
            if roadFinalById[self.id] ~= nil and self:continueRoadTravel(ticks) then
                return
            end
            if self.state == "EVENT_TRAVEL" then
                self.eventMoveFailures = 0
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_DEPOSIT" then
                self:completeDepositTrip(ticks)
                return
            end
            if self.state == "MOVING_TO_REST" then
                self:startRecoveryPosture(ticks, true, self.ambientRest == true)
                return
            end
            if self.state == "NIGHT_SHELTER_MOVE" then
                -- Arrival just re-decides: still night and indoors means
                -- sleep, dawn means roam. Never strand the move state.
                self:finishDecision(ticks)
                self.nextThink = ticks
                return
            end
            if self.state == "BASE_DEFEND" then
                -- Arrival just re-decides: the threat scan engages anything
                -- still there, a live alarm re-issues, expiry resumes base
                -- life. Never strand the move state.
                self:finishDecision(ticks)
                self.nextThink = ticks
                return
            end
            if self.state == "AID_MOVE" then
                local medical = rawget(_G, "KnoxMedicalActions")
                local patient = self.pendingAidPatient
                local part = patient ~= nil and bleedingPart(patient) or nil
                local bandage = medical ~= nil and medical.findBandageItem ~= nil
                    and medical.findBandageItem(self.character) or nil
                self.pendingAidPatient = nil
                self.pendingAidPart = nil
                self.pendingAidBandage = nil
                if medical == nil or medical.queueAidBandage == nil
                    or patient == nil or part == nil or bandage == nil then
                    self.nextAidAt = ticks + AID_RETRY_TICKS
                    self:finishDecision(ticks)
                    return
                end
                local action, result = medical.queueAidBandage(
                    self.character, patient, bandage, part)
                if action == nil then
                    self.nextAidAt = ticks + AID_RETRY_TICKS
                    self:finishDecision(ticks)
                    return
                end
                self.pendingAidPatient = patient
                self.pendingAidPart = part
                self.activeDecision = "aid_ally"
                self.state = "AID_ACTION"
                self.stateStartedAt = ticks
                return
            end
            if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
                self.campExcursion = false
                self.campExcursionExplored = false
                self.activeDecision = "camp_idle"
                self.state = "CAMP_IDLE"
                self.nextThink = ticks + Controller.TUNING.CAMP_DECISION_TICKS
                return
            end
            if self.state == "AWAY_RETURN" then
                local completed, detail = KnoxPersistence.completeAwayTeamMember(
                    self.awayTeamId,
                    self.id,
                    true,
                    "returned_to_owner",
                    currentWorldAgeHours()
                )
                if completed ~= nil then
                    KnoxActivityFeed.speak(self.character, "Back home.")
                    self.awayTeamId = nil
                    self.awayCollected = false
                    self.awaySearchMisses = 0
                    self.activeDecision = nil
                    self:finishDecision(ticks)
                    self.nextThink = ticks
                else
                    self:recordFailure(
                        "away_return_complete:" .. tostring(detail),
                        ticks,
                        EXPLORATION_RETRY_TICKS
                    )
                    self.state = "IDLE"
                    self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                end
                return
            end
            if self.state == "MOVING_TO_BASE_CANDIDATE" then
                local candidate = self.factionBaseCandidate
                local worldAge = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                local home, result = KnoxPersistence.confirmFactionHomeBase(
                    self.factionId,
                    candidate ~= nil and candidate.buildingId or nil,
                    worldAge
                )
                if home ~= nil then
                    self.counts.baseScout = self.counts.baseScout + 1
                    KnoxActivityFeed.speak(self.character, "This place could work.")
                    KnoxActivityFeed.event(
                        "Home base claimed near " .. tostring(home.x)
                            .. ", " .. tostring(home.y) .. "."
                    )
                    local _, safehouseResult = KnoxFactionSafehouse.ensure(
                        KnoxPersistence.getFaction(self.factionId)
                    )
                    local base, baseResult = KnoxBaseManager.ensureFactionBase(
                        KnoxPersistence.getFaction(self.factionId)
                    )
                    -- The persistence notification is authoritative for every
                    -- resident. Adopt the new assignment immediately for this
                    -- loaded scout so it cannot spend a decision cycle standing
                    -- in its retired travel formation at the claimed building.
                    if base ~= nil then
                        self:setBaseAssignment(base.id, base)
                    end
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " faction-base-selected=" .. tostring(self.factionId)
                            .. " building=" .. tostring(home.buildingId)
                            .. " bounds=" .. tostring(home.minX) .. "," .. tostring(home.minY)
                                .. "," .. tostring(home.width) .. "," .. tostring(home.height)
                            .. " safehouse=" .. tostring(safehouseResult)
                            .. " base=" .. tostring(base ~= nil and base.id or baseResult)
                    )
                else
                    self.counts.failures = self.counts.failures + 1
                    -- Confirmation can fail after the route itself succeeds
                    -- (ownership conflict, stale building metadata, or a
                    -- changed safehouse). Keep this candidate in the existing
                    -- bounded rejection memory so the next scouting pass does
                    -- not immediately select the same unusable shelter.
                    self:rejectFactionBaseCandidate(ticks, result)
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " faction-base-selection-failed=" .. tostring(result)
                    )
                end
                self:clearFactionBaseCandidate()
                self:finishDecision(ticks)
                return
            end
            if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
                self:releaseCampPosition()
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_WINDOW_ENTRY" then
                if not self:crossWindowDetour(ticks) then
                    if not self:retryWindowDetour(ticks, "cross_start_failed")
                        and not self:fallbackTaskEntryToDoorBreak(ticks) then
                        self:abandonCurrentDecision(ticks, "window_cross_failed")
                    end
                end
                return
            end
            if self.state == "CROSSING_WINDOW_ENTRY" then
                if not self:resumeAfterWindowDetour(ticks) then
                    if not self:fallbackTaskEntryToDoorBreak(ticks) then
                        self:abandonCurrentDecision(ticks, "window_resume_failed")
                    end
                end
                return
            end
            if self.state == "MEETING_APPROACH" then
                self.state = "MEETING_READY"
                return
            end
            if self.state == "GROUP_FOLLOW" then
                self.counts.groupTravel = self.counts.groupTravel + 1
                self:resumeGroupFollowAfterSuccess(ticks)
                return
            end
            if self.state == "GROUP_REGROUP" then
                self.counts.groupTravel = self.counts.groupTravel + 1
                self:resetMovementRecovery()
                self.formationMovementPace = nil
                self:finishDecision(ticks)
                return
            end
            if self.state == "COMPANION_FOLLOW" then
                self:resetMovementRecovery()
                self.formationMovementPace = nil
                self.activeDecision = "follow_player"
                self.state = "COMPANION_WAIT"
                self.nextThink = ticks + Controller.TUNING.FORMATION_REFRESH_TICKS
                return
            end
            if self.state == "FLEEING" then
                self.fleeTarget = nil
                self.fleeRecoveryUntil = nil
                self.nextThreatScan = math.min(self.nextThreatScan or ticks, ticks)
                return
            end
            if self.securityRoute~=nil and (self.state=="BASE_TASK_MOVE"
                or self.state=="MOVING_TO_COMPANION_PATROL" or self.state=="MOVING_TO_COMPANION_POINT") then
                if self:completeSecurityArrival(ticks,self.securityRoute.base) then return end
            end
            if self.state == "MOVING_TO_COMPANION_POINT" then
                local directive = self.companionDirective
                if directive == nil then
                    self:finishDecision(ticks)
                    return
                end
                if directive.partyDestination == true then
                    local cell = getCell ~= nil and getCell() or nil
                    local target = cell ~= nil and cell:getGridSquare(
                        directive.minX, directive.minY, directive.z or 0
                    ) or nil
                    local current = self.character:getCurrentSquare()
                    if target == nil or current == nil
                        or navigationDistanceSquared(current, target) > 2.25 then
                        -- A native route success is not itself arrival. Keep
                        -- the shared order and let the ordinary order owner
                        -- retry until the actor is physically in tolerance.
                        self.partyDestinationFinalLeg = true
                        self.state, self.nextThink = "IDLE", ticks
                        return
                    end
                end
                self.state = directive.kind == "guard" and "COMPANION_GUARD"
                    or "COMPANION_WAIT"
                self.nextThink = ticks + 90
                if directive.kind == "go_to" then
                    self:completeCompanionPointDirective(ticks, directive)
                else
                    KnoxActivityFeed.speak(self.character, "I'll keep watch.")
                end
                return
            end
            if self.state == "MOVING_TO_COMPANION_PATROL" then
                self.activeDecision = "patrol_area"
                self.state = "COMPANION_PATROL_WAIT"
                self.nextThink = ticks + 120
                return
            end
            if self.state == "AWAY_RETURN" then
                self:recordMovementFailure("away_return", movement, ticks,
                    EXPLORATION_RETRY_TICKS)
                self.bridge:cancelNpcMove(self.id)
                self.state = "IDLE"
                self.activeDecision = "away_return_retry"
                self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                return
            end
            if self.state == "BASE_RETURN" or self.state == "BASE_PATROL" then
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                local transfer = self.baseTaskSupplyTransfer
                local source = transfer ~= nil and transfer.source ~= nil
                    and transfer.source.container or nil
                if self.baseTask == nil or transfer == nil or source == nil
                    or source:contains(transfer.item) == false then
                    self:failBaseTaskAction(ticks, "assigned_supply_no_longer_available")
                    return
                end
                local action, actionResult = KnoxInventoryActions.queueTransfer(
                    self.character,
                    transfer.item,
                    source,
                    self.character:getInventory(),
                    nil
                )
                if action == nil then
                    self:failBaseTaskAction(ticks,
                        "assigned_supply_transfer_queue:" .. tostring(actionResult))
                    return
                end
                self.baseTaskStartedAt = ticks
                self.activeDecision = "base_task_collect_supplies"
                self.state = "BASE_TASK_SUPPLY_TRANSFER"
                return
            end
            if self.state == "BASE_TASK_MOVE" then
                if self.baseTask ~= nil and self.baseTask.type == "patrol" then
                    local complete, _, stopCount = KnoxCompanionPatrol.recordTaskArrival(
                        self.baseTask
                    )
                    if complete then
                        self.baseTask.patrolLaps = (tonumber(self.baseTask.patrolLaps) or 0) + 1
                    end
                    self.activeDecision = "base_task_patrol"
                    self.state = "BASE_TASK_PATROL_WAIT"
                    self.nextThink = ticks + (complete and 180 or 90)
                    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                        .. " patrol-stop=" .. tostring(self.baseTask.patrolStopsCompleted)
                        .. "/" .. tostring(stopCount)
                        .. " laps=" .. tostring(self.baseTask.patrolLaps or 0))
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "haul_corpse" then
                    if self.baseTaskCorpsePhase == "drop" then
                        local dropSquare = self.baseTaskCorpseTarget ~= nil
                            and self.baseTaskCorpseTarget.dropSquare or nil
                        if not KnoxBaseCorpseHandling.isAtDropSquare(
                            self.character, dropSquare
                        ) then
                            -- A successful bridge tick can still end on a
                            -- nearby fallback tile. Never start the native
                            -- drop action from there: that leaves the grapple
                            -- attached while the controller keeps walking in
                            -- one direction. Release, cool down this
                            -- destination, and retry from discovery.
                            pcall(function() self.character:setDoGrappleLetGo() end)
                            do
                                local tgt = self.baseTask ~= nil and self.baseTask.target or nil
                                self.corpseDropCooldown = {
                                    x = tgt ~= nil and tgt.dropX or nil,
                                    y = tgt ~= nil and tgt.dropY or nil,
                                    z = tgt ~= nil and tgt.dropZ or nil,
                                    untilTick = ticks + BLOCKED_AREA_COOLDOWN_TICKS,
                                }
                            end
                            self.baseTaskCorpseTarget = nil
                            self:failBaseTaskAction(ticks, "corpse_drop_arrival_mismatch")
                            return
                        end
                        self.baseTaskStartedAt = ticks
                        self.baseTaskActionQueued = false
                        self.activeDecision = "base_task_haul_corpse_drop"
                        self.state = "BASE_TASK_ACTION"
                        return
                    end
                    self.baseTaskCorpseTarget = KnoxBaseCorpseHandling.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskCorpseTarget == nil then
                        self:failBaseTaskAction(ticks, "corpse_target_invalid")
                        return
                    end
                    self.baseTaskCorpsePhase = "grab"
                    self.baseTaskCorpseGrabVerifyUntil = nil
                    self.baseTaskCorpseGrabRetryIssued = nil
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_haul_corpse_grab"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "barricade" then
                    local target = self.baseTaskBarricadeTarget
                    if target == nil or not KnoxBaseBarricades.isTargetValid(
                        target,
                        self.character
                    ) then
                        local targetReason
                        target, targetReason = KnoxBaseBarricades.resolveTarget(
                            self.base,
                            self.baseTask.target,
                            self.character
                    )
                    self.baseTaskBarricadeTarget = target
                    if target == nil then
                        target = self:retargetBarricadeTask()
                        self.baseTaskBarricadeTarget = target
                    end
                    if target == nil then
                        if KnoxBaseBarricades.isTargetComplete ~= nil
                            and KnoxBaseBarricades.isTargetComplete(self.base, self.baseTask.target, self.character) then
                            self:finishBaseTask(true, "barricade_already_secured")
                            self:finishDecision(ticks)
                            return
                        end
                        self:failBaseTaskAction(
                            ticks,
                            "barricade_target_invalid:" .. tostring(targetReason)
                            )
                            return
                        end
                    end
                    self.baseTaskBarricadeBefore = KnoxBaseBarricades.plankCount(
                        self.baseTaskBarricadeTarget,
                        self.character
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_barricade"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and self.baseTask.type == "repair" then
                    self.baseTaskRepairTarget = KnoxBaseRepairs.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskRepairTarget == nil then
                        self:failBaseTaskAction(ticks, "repair_target_invalid")
                        return
                    end
                    self.baseTaskRepairBefore = KnoxBaseRepairs.snapshot(
                        self.baseTaskRepairTarget
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_repair"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and (self.baseTask.type == "farm_water"
                        or self.baseTask.type == "farm_harvest"
                        or self.baseTask.type == "farm_plow"
                        or self.baseTask.type == "farm_seed") then
                    self.baseTaskFarmingTarget = KnoxBaseFarming.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskFarmingTarget == nil then
                        self:failBaseTaskAction(ticks, "farming_target_invalid")
                        return
                    end
                    self.baseTaskFarmingBefore = KnoxBaseFarming.snapshot(
                        self.baseTaskFarmingTarget
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_" .. tostring(self.baseTask.type)
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and (self.baseTask.type == "chop_tree"
                        or self.baseTask.type == "saw_logs") then
                    self.baseTaskWoodcuttingTarget = KnoxBaseWoodcutting.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskWoodcuttingTarget == nil then
                        self:failBaseTaskAction(ticks, "tree_target_invalid")
                        return
                    end
                    if self.baseTask.type == "chop_tree" then
                        self.baseTaskWoodcuttingBefore =
                            self.baseTaskWoodcuttingTarget.tree:getObjectIndex()
                    end
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_chop_tree"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "sort_depot" then
                    self:finishBaseTask(false, "central_cupboard_storage_retired")
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskStartedAt = ticks
                self.activeDecision = "base_task_work"
                self.state = "BASE_TASK_WORK"
                KnoxActivityFeed.speak(self.character,
                    self.baseTask ~= nil and self.baseTask.type == "guard"
                        and "I'll keep watch here." or "I'll make a patrol."
                )
                return
            end
            if (self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE")
                and self.pendingSupply ~= nil then
                local supply = self.pendingSupply
                if supply.waterSource ~= nil then
                    self:beginWorldWaterAction(ticks)
                    return
                end
                self.inspectedContainers[supply.container] = ticks
                    + (supply.items ~= nil and #supply.items > 0
                        and LOOT_TRAVEL_COOLDOWN_TICKS or EMPTY_SEARCH_COOLDOWN_TICKS)
                local action = nil
                if supply.items ~= nil and #supply.items > 0 then
                    for _, candidate in ipairs(supply.items) do
                        if supply.container:contains(candidate.item) then
                            local queued = KnoxInventoryActions.queueTransfer(
                                self.character,
                                candidate.item,
                                supply.container,
                                self.character:getInventory(),
                                nil
                            )
                            action = action or queued
                        end
                    end
                elseif supply.item ~= nil and supply.container:contains(supply.item) then
                    action = KnoxInventoryActions.queueTransfer(
                        self.character,
                        supply.item,
                        supply.container,
                        self.character:getInventory(),
                        nil
                    )
                else
                    action = KnoxInventoryActions.queueSearch(
                        self.character,
                        supply.container,
                        90
                    )
                end
                if action ~= nil then
                    self.state = (supply.item ~= nil
                        or (supply.items ~= nil and #supply.items > 0))
                        and "LOOTING"
                        or "SEARCHING"
                    if self.state == "LOOTING" then
                        self:sayAction({ "I'll take what we can use.",
                            "Found something useful.", "I'll grab a few things." }, ticks, 1800)
                    else
                        self:sayAction({ "Let me check this.", "I'll have a quick look.",
                            "Give me a second to search this." }, ticks, 1800)
                    end
                else
                    self:recordFailure("loot_action_queue", ticks, 180)
                    self:releaseSupply()
                    self:finishDecision(ticks)
                end
            else
                if self.state == "ROAMING" then
                    if self.lifeIntent ~= nil then
                        self:setLifeIntent(
                            self.lifeIntent.kind,
                            "arrived",
                            nil,
                            self.roamGoalKey
                        )
                    end
                    rememberRoamDestination(
                        self,
                        self.roamGoalKey,
                        ticks,
                        Controller.TUNING.ROAM_GOAL_COOLDOWN_TICKS
                    )
                    self.roamGoalKey = nil
                    self.roamGoalKind = nil
                end
                self.counts.roam = self.counts.roam + 1
                self:finishDecision(ticks)
            end
        elseif string.find(movement, "Failed", 1, true) == 1
            or string.find(movement, "TICK_FAILED", 1, true) == 1 then
            if self.state == "GROUP_FOLLOW"
                or self.state == "GROUP_REGROUP"
                or self.state == "COMPANION_FOLLOW" then
                if (self.state == "GROUP_FOLLOW" or self.state == "GROUP_REGROUP")
                    and Controller.isEntryTraversalFailure(movement) then
                    self:waitForFormationBottleneck(movement, ticks)
                    return
                end
                self:handleFormationMovementFailure(movement, ticks)
                return
            end
            if self.state == "FLEEING" then
                self:recoverFleeMovement(movement, ticks)
                return
            end
            if (self.state=="BASE_TASK_MOVE" and self.baseTask~=nil
                and (self.baseTask.type=="guard" or self.baseTask.type=="patrol"))
                or self.state=="MOVING_TO_COMPANION_PATROL"
                or (self.state=="MOVING_TO_COMPANION_POINT" and self.companionDirective~=nil
                    and self.companionDirective.kind=="guard") then
                if self.state == "BASE_TASK_MOVE"
                    and string.find(movement, "FAILED_LOCKED_DOOR", 1, true)
                    and self:beginBaseTaskLockedDoorBreak(ticks) then
                    return
                end
                self:deferSecurityRoute(ticks,movement,self.state=="BASE_TASK_MOVE")
                return
            end
            self:recordMovementFailure("movement", movement, ticks)
            if self.state == "EVENT_TRAVEL" then
                self.eventMoveFailures = (self.eventMoveFailures or 0) + 1
                self.bridge:cancelNpcMove(self.id)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_DEPOSIT" then
                self.bridge:cancelNpcMove(self.id)
                self:deferDepositTrip(ticks)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_COMPANION_POINT"
                or self.state == "MOVING_TO_COMPANION_PATROL" then
                self.directiveMisses = self.directiveMisses + 1
                if self.directiveMisses >= 3 then
                    KnoxPersistence.clearCompanionDirective(
                        self.id, self.companionOwnerId,
                        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                    )
                    self.companionDirective = nil
                    self.directiveMisses = 0
                    KnoxActivityFeed.speak(self.character, "I can't get there from here.")
                end
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_REST" then
                self:handleRestMovementFailure(movement, ticks)
                return
            end
            if self.state == "MOVING_TO_BASE_CANDIDATE" then
                self:rejectFactionBaseCandidate(ticks, movement)
                self.counts.failures = self.counts.failures + 1
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_RETURN" or self.state == "BASE_PATROL" then
                -- Base residents may encounter a door that changed state after
                -- target selection. Recover the entry locally before releasing
                -- the ambient reservation and falling back to idle.
                if not string.find(movement, "FAILED_LOCKED_DOOR", 1, true)
                    and self:openNearbyClosedDoor() then
                    return
                end
                if string.find(movement, "FAILED_LOCKED_DOOR", 1, true) then
                    self.pendingSupply = self.pendingSupply or {
                        targetSquare = self.character:getCurrentSquare(),
                        entryAttempts = {},
                    }
                    if self:beginLockedDoorBreak(ticks, self.state) then
                        return
                    end
                end
                self:handleBaseMovementFailure(movement, ticks)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                if Controller.isEntryTraversalFailure(movement) then
                    local lockedDoor = string.find(
                        movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
                    if not lockedDoor and self:openNearbyClosedDoor() then
                        return
                    end
                    if self:beginBaseTaskSupplyWindowDetour(ticks) then
                        return
                    end
                    if lockedDoor and self:fallbackTaskEntryToDoorBreak(ticks) then
                        return
                    end
                    if self.pendingSupply ~= nil
                        and self.pendingSupply.taskSupplyEntry == true then
                        self.pendingSupply = nil
                    end
                end
                self:finishBaseTask(false, "assigned_supply_movement_failed:" .. movement)
                self:recordMovementFailure("base_task_supply_move", movement, ticks)
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_TASK_MOVE" then
                if string.find(movement, "FAILED_LOCKED_DOOR", 1, true) then
                    -- Quiet entry first: try a nearby window before smashing
                    -- the door down. Break remains the fallback below and in
                    -- the window-detour exhaustion path.
                    if self:beginBaseTaskWindowDetour(ticks) then
                        return
                    end
                    if self:beginBaseTaskLockedDoorBreak(ticks) then
                        return
                    end
                end
                if self.baseTask ~= nil and self.baseTask.type == "haul_corpse" then
                    if self.baseTaskCorpsePhase == "drop"
                        and KnoxBaseCorpseHandling.isDragging(self.character) then
                        pcall(function() self.character:setDoGrappleLetGo() end)
                        do
                            local tgt = self.baseTask ~= nil and self.baseTask.target or nil
                            self.corpseDropCooldown = {
                                x = tgt ~= nil and tgt.dropX or nil,
                                y = tgt ~= nil and tgt.dropY or nil,
                                z = tgt ~= nil and tgt.dropZ or nil,
                                untilTick = ticks + BLOCKED_AREA_COOLDOWN_TICKS,
                            }
                        end
                        self:finishBaseTask(false, "corpse_movement_failed:" .. movement)
                        self:recordMovementFailure("base_task_move_corpse", movement, ticks)
                        self:finishDecision(ticks)
                        return
                    end
                    if self:retryBaseTaskMovement(ticks, movement) then return end
                    self:finishBaseTask(false, "corpse_movement_failed:" .. movement)
                    self:recordMovementFailure("base_task_move_corpse", movement, ticks)
                    self:finishDecision(ticks)
                    return
                end
                if self:retryBaseTaskMovement(ticks, movement) then
                    return
                end
                self:finishBaseTask(false, "movement_failed:" .. movement)
                self:recordMovementFailure("base_task_move", movement, ticks)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_SUPPLY" and self.pendingSupply ~= nil
                and self.pendingSupply.baseResupply == true then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                self:continueBaseResourceRun(ticks, false)
                return
            end
            if (self.state == "MOVING_TO_WINDOW_ENTRY" or self.state == "CROSSING_WINDOW_ENTRY")
                and self:retryWindowDetour(ticks, movement) then return end
            if (self.state == "MOVING_TO_WINDOW_ENTRY" or self.state == "CROSSING_WINDOW_ENTRY")
                and self:fallbackTaskEntryToDoorBreak(ticks) then return end
            if Controller.isEntryTraversalFailure(movement)
                and (self.state == "MOVING_TO_SUPPLY"
                    or self.state == "MOVING_TO_EXPLORE") then
                local resumeState = self.state
                if string.find(movement, "OPENING_DISABLED", 1, true) then
                    self:sayAction({
                        "I can't open that without permission.",
                        "The door is closed and opening is disabled.",
                    }, ticks, 3600)
                    markPendingAreaBlocked(self, ticks, "opening_permission_disabled")
                    self:finishDecision(ticks)
                    return
                end
                local lockedDoor = string.find(
                    movement,
                    "FAILED_LOCKED_DOOR",
                    1,
                    true
                ) ~= nil
                -- Closed unlocked doors are opened, not smashed: try ToggleDoor
                -- before falling back to window detours or forced entry.
                if not lockedDoor and self:openNearbyClosedDoor() then
                    self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
                    return
                end
                if self:beginWindowDetour(ticks, resumeState)
                    or (lockedDoor and self:beginLockedDoorBreak(ticks, resumeState)) then
                    return
                end
                markPendingAreaBlocked(self, ticks, "alternate_entry_unavailable")
            end
            if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                local failedSquare = self.pendingSupply.container:getSourceGrid()
                rememberRoamDestination(self, roamDestinationKey(failedSquare), ticks, Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS)
                markPendingAreaBlocked(self, ticks, "unreachable_supply")
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " skipped-unreachable-container movement=" .. movement
                )
            end
            if self.state == "ROAMING" then
                rememberRoamDestination(
                    self,
                    self.roamGoalKey,
                    ticks,
                    Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS
                )
                self.roamGoalKey = nil
                self.roamGoalKind = nil
                if self.lifeIntent ~= nil then
                    self:setLifeIntent(self.lifeIntent.kind, "reassess", nil, nil)
                end
            end
            if self.state == "AID_MOVE" then
                self:releaseAid()
                self.nextAidAt = ticks + AID_RETRY_TICKS
            end
            self:releaseSupply()
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "LOOTING" then
        if self.character:getCharacterActions():isEmpty() then
            local retrievedNeedKind = (self.activeDecision == "find_food"
                or self.activeDecision == "find_water") and self.activeDecision or nil
            local retrievedNeedItem = self.pendingSupply ~= nil
                and self.pendingSupply.item or nil
            local retrievedNeedVerified = retrievedNeedKind == nil
            if retrievedNeedKind ~= nil and retrievedNeedItem ~= nil then
                local inventory = self.character:getInventory()
                retrievedNeedVerified = inventory ~= nil
                    and inventory:contains(retrievedNeedItem)
                if not retrievedNeedVerified then
                    self.selfCareRetryAt[retrievedNeedKind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
                    self:recordFailure(
                        "need_supply_transfer_not_completed",
                        ticks,
                        Controller.TUNING.SELF_CARE_RETRY_TICKS
                    )
                end
            end
            local partyFoodItem = self.pendingSupply ~= nil
                and self.pendingSupply.partySupport == true
                and self.pendingSupply.items ~= nil
                and self.pendingSupply.items[1] ~= nil
                and self.pendingSupply.items[1].item or nil
            if self.pendingSupply ~= nil
                and self.pendingSupply.partySupport == true
                and not Controller.hasPartyFoodReceipt(
                    self.character:getInventory(), partyFoodItem
                ) then
                local container = self.pendingSupply.container
                if container ~= nil then
                    self.inspectedContainers[container] = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
                end
                self:recordFailure(
                    "party_support_food_transfer_not_received",
                    ticks,
                    LOOT_TRAVEL_COOLDOWN_TICKS
                )
                self:releaseSupply()
                self:finishDecision(ticks)
                return
            end
            if retrievedNeedKind == nil
                and self.pendingSupply ~= nil
                and self.pendingSupply.partySupport ~= true
                and self.pendingSupply.baseResupply ~= true
                and self.awayTeamId == nil
                and self.pendingSupply.items ~= nil
                and #self.pendingSupply.items > 0 then
                local received, receivedCount, selectedCount = self:verifyGenericLootReceipt()
                if not received then
                    self:rejectUnreceivedGenericLoot(ticks, receivedCount, selectedCount)
                    return
                end
            end
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, true)
                return
            end
            if self.awayTeamId ~= nil then
                self:finishAwayCollection(ticks)
                return
            end
            self.counts.loot = self.counts.loot + 1
            local changed, equipment = self:reconsiderEquipment(ticks, true)
            if changed then
                -- The replaced weapon/garment stays carried until the existing
                -- inventory-cleanup pass applies its own rules (typed base
                -- storage deposit first, native tear-to-rags only when rags
                -- are actually needed, drop last). Hastening that pass creates
                -- no trips and never interrupts follow, hold, or orders.
                local at = self.nextCleanupAt
                if at == nil or at > ticks + 300 then
                    self.nextCleanupAt = ticks + 300
                end
            end
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " loot-complete=" .. tostring(self.activeDecision)
                    .. " equipmentChanged=" .. tostring(changed)
                    .. " equipment=" .. tostring(equipment)
            )
            -- Bounded multi-container chaining: one container rarely covers a
            -- need, so keep searching the same building/area while an explicit
            -- loot directive stands (or a scavenge intent runs), capped at 3
            -- chained containers so this always ends. Real transfers only;
            -- combat, base-supply, and away-team duties never chain.
            do
                local directive = self.companionDirective
                local kind = directive ~= nil and tostring(directive.kind or "") or ""
                local lootDirective = kind == "loot_area" or kind == "loot_building"
                    or kind == "loot_corpses"
                local scavenging = self.lifeIntent ~= nil
                    and self.lifeIntent.kind == "scavenge"
                if (lootDirective or scavenging)
                    and not (self.pendingSupply ~= nil
                        and self.pendingSupply.partySupport == true)
                    and self.combatTarget == nil
                    and self.baseSupplyTrip ~= true
                    and self.awayTeamId == nil
                    and (self.scavengeChainCount or 0) < 3 then
                    local used = self.pendingSupply ~= nil
                        and self.pendingSupply.container or nil
                    if used ~= nil then
                        self.inspectedContainers[used] = ticks + EXPLORATION_RETRY_TICKS
                    end
                    local searchDirective = lootDirective and directive or nil
                    local peek = findExploration(self, ticks, searchDirective)
                    if peek ~= nil and peek.items ~= nil and #peek.items > 0 then
                        self.scavengeChainCount = (self.scavengeChainCount or 0) + 1
                        self:releaseSupply()
                        -- Advisory hint only: room-derived, never claims an
                        -- item exists before the transfer verifies it.
                        local hint = nil
                        do
                            local roomName = nil
                            local ok, name = pcall(function()
                                local grid = peek.container ~= nil
                                    and peek.container:getSourceGrid() or nil
                                local room = grid ~= nil and grid:getRoom() or nil
                                return room ~= nil and room:getName() or nil
                            end)
                            if ok and type(name) == "string" then
                                roomName = string.lower(name)
                            end
                            local function has(sub)
                                return roomName ~= nil
                                    and string.find(roomName, sub, 1, true) ~= nil
                            end
                            if kind == "find_medical" or has("bath") or has("medic")
                                or has("toilet") then
                                hint = "Checking the bathroom for meds."
                            elseif kind == "find_weapon" then
                                hint = "Looking for a better weapon."
                            elseif kind == "find_food" or has("kitchen") then
                                hint = "Checking the kitchen for food."
                            elseif kind == "find_water" then
                                hint = "Looking for something to drink."
                            elseif kind == "find_tools" or has("garage")
                                or has("shed") or has("storage") or has("utility") then
                                hint = "Checking for useful tools."
                            elseif kind == "loot_corpses" then
                                hint = "Checking these bodies while it's quiet."
                            elseif has("bedroom") then
                                hint = "Checking the bedroom for clothes and gear."
                            else
                                hint = "Moving on to the next room."
                            end
                        end
                        if hint ~= nil then
                            self:sayAction({ hint }, ticks, 1800)
                        end
                        if self:beginExploration(ticks, searchDirective) then
                            return
                        end
                    end
                    self.scavengeChainCount = 0
                else
                    self.scavengeChainCount = 0
                end
            end
            self.nextExplorationSearch = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
            self.forceTravel = true
            if self.lifeIntent ~= nil and self.lifeIntent.kind == "scavenge" then
                self.scavengeBuildingId = self.pendingSupply ~= nil
                    and self.pendingSupply.buildingId or self.scavengeBuildingId
                self:setLifeIntent(
                    "scavenge", "searching", nil, self.scavengeBuildingId
                )
            elseif self.lifeIntent ~= nil then
                self:setLifeIntent(self.lifeIntent.kind, "reassess", nil, nil)
            end
            if self.companionDirective ~= nil
                and (self.companionDirective.kind == "find_food"
                    or self.companionDirective.kind == "find_water"
                    or self.companionDirective.kind == "find_medical"
                    or self.companionDirective.kind == "find_weapon"
                    or self.companionDirective.kind == "find_tools"
                    or self.companionDirective.kind == "find_wood"
                    or self.companionDirective.kind == "find_materials"
                    or self.companionDirective.kind == "find_clothing"
                    or self.companionDirective.kind == "find_ammo") then
                KnoxPersistence.clearCompanionDirective(
                    self.id, self.companionOwnerId, currentWorldAgeHours()
                )
                self.companionDirective = nil
                self.directiveMisses = 0
            end
            local returnToBase = self.baseSupplyTrip == true
            local explicitBaseSupply = self.baseSupplyOrder ~= nil
            local recoveredBaseItem = returnToBase
                and self.pendingSupply ~= nil and self.pendingSupply.item or nil
            if returnToBase then
                if recoveredBaseItem == nil then
                    self:finishBaseSupplyRun("empty")
                else
                    self:handoffBaseSupplyDelivery(recoveredBaseItem)
                end
            end
            -- An explicit owner order repeats until expiry, failure budget,
            -- or cancellation: after deposit the base loop starts the next
            -- trip. Only empty searches count against the attempt budget.
            if explicitBaseSupply and recoveredBaseItem == nil then
                self:recordExplicitBaseSupplyFailure(ticks)
            end
            if not (returnToBase and recoveredBaseItem ~= nil) then
                self:releaseSupply()
            end
            self:finishDecision(ticks)
            if retrievedNeedVerified and retrievedNeedKind ~= nil
                and self:beginImmediateNeedAction(retrievedNeedKind, ticks) then
                return
            end
            if returnToBase then
                -- The next normal decision sees the resident outside its
                -- assigned territory and uses the existing native base-return
                -- movement path. No second mission/order is created.
                self.nextThink = ticks
            end
        end
        return
    end


    if self.state == "SEARCHING" then
        if self.character:getCharacterActions():isEmpty() then
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, false)
                return
            end
            if self.awayTeamId ~= nil then
                self:finishAwayCollection(ticks)
                return
            end
            if self.pendingSupply ~= nil and self.pendingSupply.eventId ~= nil then
                KnoxEvents.recordEmptySearch(self.pendingSupply.eventId, self.id)
            end
            self.counts.search = self.counts.search + 1
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " search-complete=container_no_upgrade"
            )
            self.nextExplorationSearch = ticks + EMPTY_SEARCH_COOLDOWN_TICKS
            self.forceTravel = true
            if self.lifeIntent ~= nil and self.lifeIntent.kind == "scavenge" then
                self.scavengeBuildingId = nil
                self:clearLifeIntent()
            end
            if self.companionDirective ~= nil
                and (self.companionDirective.kind == "find_food"
                    or self.companionDirective.kind == "find_water"
                    or self.companionDirective.kind == "find_medical"
                    or self.companionDirective.kind == "find_weapon"
                    or self.companionDirective.kind == "find_tools"
                    or self.companionDirective.kind == "find_wood"
                    or self.companionDirective.kind == "find_materials"
                    or self.companionDirective.kind == "find_clothing"
                    or self.companionDirective.kind == "find_ammo") then
                KnoxPersistence.clearCompanionDirective(
                    self.id, self.companionOwnerId, currentWorldAgeHours()
                )
                self.companionDirective = nil
                self.directiveMisses = 0
            end
            local returnToBase = self.baseSupplyTrip == true
            local explicitBaseSupply = self.baseSupplyOrder ~= nil
            if returnToBase then
                self:finishBaseSupplyRun("empty")
            end
            if explicitBaseSupply then
                self:recordExplicitBaseSupplyFailure(ticks)
            end
            self:releaseSupply()
            self:finishDecision(ticks)
            if returnToBase then
                self.nextThink = ticks
            end
        end
        return
    end

    if self.state == "SLEEPING_RECOVERY" then
        if self.character:isAsleep() then
            if ticks - self.recoveryStarted < Controller.TUNING.SLEEP_RECOVERY_TIMEOUT_TICKS then
                return
            end
            KnoxSurvivorNeeds.wakeForDanger(self.character)
        end
        local recovered, detail = KnoxSurvivorNeeds.verifyRecovery(
            self.character,
            self.selfCareIntent
        )
        if recovered then
            self.counts.needs = self.counts.needs + 1
            self.selfCareRetryAt.sleep = nil
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " self-care-complete=sleep " .. tostring(detail)
            )
        else
            self.selfCareRetryAt.sleep = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_no_change:sleep:" .. tostring(detail),
                ticks,
                Controller.TUNING.SELF_CARE_RETRY_TICKS
            )
        end
        self:finishDecision(ticks)
        return
    end

    if self.state == "WAITING_TO_RECOVER" then
        local sitting = self.character:isSitOnGround()
            or self.character:isSittingOnFurniture()
        if self.pendingRest ~= nil and not sitting
            and ticks - self.recoveryPostureStarted >= Controller.TUNING.RECOVERY_POSTURE_TIMEOUT_TICKS then
            self:startRecoveryPosture(ticks, false)
            return
        end
        -- Vanilla IsoPlayer checks sitting before its isPlayerMoving flag when it
        -- updates endurance. Entering a real sitting state therefore restores the
        -- native recovery path without maintaining a second Knox stamina formula.
        if ticks < self.nextThink then
            return
        end
        local snapshot = KnoxSurvivorNeeds.snapshot(self.character)
        local recovered = snapshot.endurance > KnoxSurvivorNeeds.thresholds.lowEndurance
            and (self.activeDecision ~= "sleep"
                or snapshot.fatigue < KnoxSurvivorNeeds.thresholds.fatigue)
        print(
            "[KnoxSurvivors][Autonomy] id=" .. self.id
                .. " recovery-progress endurance=" .. tostring(snapshot.endurance)
                .. " posture=" .. (self.character:isSittingOnFurniture()
                    and "furniture" or (self.character:isSitOnGround() and "ground" or "standing"))
        )
        if recovered then
            local changed, detail = KnoxSurvivorNeeds.verifyRecovery(
                self.character,
                self.selfCareIntent
            )
            if changed then
                self.counts.needs = self.counts.needs + 1
                self.selfCareRetryAt.rest = nil
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " self-care-complete=rest " .. tostring(detail)
                )
            end
            self:finishDecision(ticks)
        elseif ticks - self.recoveryStarted >= Controller.TUNING.RECOVERY_TIMEOUT_TICKS then
            local _, detail = KnoxSurvivorNeeds.verifyRecovery(
                self.character,
                self.selfCareIntent
            )
            self.selfCareRetryAt.rest = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_no_change:rest:" .. tostring(detail),
                ticks,
                Controller.TUNING.SELF_CARE_RETRY_TICKS
            )
            self:finishDecision(ticks)
        else
            self.nextThink = ticks + Controller.TUNING.RECOVERY_RECHECK_TICKS
        end
        return
    end

    if self.state == "IDLE" and ticks >= self.nextThink then
        self:think(ticks)
    end
end

local function statusPoint(value)
    if value == nil then return "none" end
    local source = type(value) == "table" and (value.square or value.approach or value.target or value) or value
    local x, y, z
    if source ~= nil and source.getX ~= nil then
        local ok
        ok, x = pcall(source.getX, source)
        if not ok then x = nil end
        ok, y = pcall(source.getY, source)
        if not ok then y = nil end
        ok, z = pcall(source.getZ, source)
        if not ok then z = nil end
    elseif type(source) == "table" then
        x, y, z = source.x or source.minX, source.y or source.minY, source.z
    end
    if x == nil or y == nil then return "none" end
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z or 0)
end

local function statusDestination(self)
    if self.combatTarget ~= nil then return statusPoint(self.combatTarget) end
    if self.fleeTarget ~= nil then return statusPoint(self.fleeTarget) end
    if self.securityRoute ~= nil then return statusPoint(self.securityRoute.square) end
    if self.pendingSupply ~= nil then return statusPoint(self.pendingSupply.approach or self.pendingSupply.container) end
    if self.pendingBaseSupplyDeposit ~= nil then return statusPoint(self.pendingBaseSupplyDeposit.square) end
    if self.pendingDepositTrip ~= nil then return statusPoint(self.pendingDepositTrip.square) end
    if self.baseTask ~= nil then return statusPoint(self.baseTask.target) end
    return statusPoint(self.companionTarget)
end

function Controller:status()
    return "id=" .. self.id
        .. " state=" .. tostring(self.state)
        .. " decision=" .. tostring(self.activeDecision or "none")
        .. " destination=" .. statusDestination(self)
        .. " base=" .. tostring(self.baseId or "none")
        .. " supplyAttempts=" .. tostring(self.baseResupplyAttempts or 0)
        .. " lastFailure=" .. tostring(self.lastFailure~=nil and self.lastFailure.reason or "none")
        .. " failureTick=" .. tostring(self.lastFailure~=nil and self.lastFailure.ticks or "none")
        .. " roam=" .. tostring(self.counts.roam)
        .. " loot=" .. tostring(self.counts.loot)
        .. " search=" .. tostring(self.counts.search)
        .. " needs=" .. tostring(self.counts.needs)
        .. " combat=" .. tostring(self.counts.combat)
        .. " groupTravel=" .. tostring(self.counts.groupTravel)
        .. " baseScout=" .. tostring(self.counts.baseScout)
        .. " robberies=" .. tostring(self.counts.robberies)
        .. " failures=" .. tostring(self.counts.failures)
        .. " recentFailures=" .. tostring(#(self.recentFailureHistory or {}))
        .. " baseTask=" .. tostring(self.baseTask ~= nil
            and self.baseTask.type or "none")
        .. " camp=" .. tostring(self.campId or "none")
        .. " groupLeader=" .. tostring(self.groupLeaderId)
        .. " formationSlot=" .. tostring(self.groupFormationSlot)
        .. " formationFailures=" .. tostring(self.formationFailureCount or 0)
        .. " retryAt=" .. tostring(self.nextThink or 0)
        .. " " .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(self.character))
end

function Controller:shutdown()
    self:cancelTrade("shutdown")
    self.pendingDepositTrip = nil
    self.pendingCleanup = nil
    self:abandonBaseTask("shutdown")
    self:releaseCampPosition()
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:releaseCombat()
    self:clearFirearmCombatState()
    self:releaseSupply()
    self:releasePlayerFormationTarget()
    self:releasePartyDestinationTarget()
    return KnoxPersistence.captureActiveSurvivor(self.id)
end

-- A hibernation teardown can fail after shutdown and the stored-ledger commit.
-- The native shell is still the same survivor, but shutdown intentionally
-- released its transient actions and leases. Re-enter ordinary arbitration only
-- after the caller has durably rolled the ledger back to loaded ownership.
function Controller:resumeAfterHibernateRollback(ticks, reason)
    ticks = tonumber(ticks) or tonumber(self.currentTicks) or 0
    self.currentTicks = ticks
    self.state = "IDLE"
    self.activeDecision = nil
    self.nextThink = ticks + THINK_MIN_TICKS
    self.nextThreatScan = math.min(self.nextThreatScan or ticks, ticks)
    if self.resetMovementRecovery ~= nil then
        pcall(function() self:resetMovementRecovery() end)
    end
    self:diag("lifecycle", "hibernate_rollback_resumed", {
        reason = tostring(reason or "native_remove_failed"),
        retryAt = self.nextThink,
    })
    return true, "same_shell_resumed"
end
