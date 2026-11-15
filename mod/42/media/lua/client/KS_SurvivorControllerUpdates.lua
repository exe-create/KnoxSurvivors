-- Installs update methods on the existing controller using its helpers and shared tables.
-- tick handles interruptions before calling the private state-completion handlers.
local Updates = {}

-- Shared read-only classification for the existing timeout/recovery gate.
-- Shelter travel keeps its separate dispatch admission below.
local MOVEMENT_STATES = {
    MOVING_TO_SUPPLY = true,
    EVENT_TRAVEL = true,
    MOVING_TO_DEPOSIT = true,
    MOVING_TO_EXPLORE = true,
    ROAMING = true,
    GROUP_FOLLOW = true,
    GROUP_REGROUP = true,
    COMPANION_FOLLOW = true,
    MOVING_TO_COMPANION_POINT = true,
    MOVING_TO_COMPANION_PATROL = true,
    BASE_RETURN = true,
    BASE_PATROL = true,
    BASE_DEFEND = true,
    BASE_TASK_MOVE = true,
    BASE_TASK_SUPPLY_MOVE = true,
    ROLE_KIT_MOVE = true,
    MEETING_APPROACH = true,
    MOVING_TO_WINDOW_ENTRY = true,
    CROSSING_WINDOW_ENTRY = true,
    MOVING_TO_REST = true,
    AID_MOVE = true,
    MOVING_TO_BASE_CANDIDATE = true,
    CAMP_RETURN = true,
    CAMP_REPOSITION = true,
    AWAY_RETURN = true,
    FLEEING = true,
}

-- A closed garage door can stop the native route as a plain obstacle rather
-- than as FAILED_LOCKED_DOOR. Keep that recovery on the existing door owner;
-- named window/door failures keep their own handling below.
local function isPlainObstacleFailure(movement)
    local text = tostring(movement or "")
    return string.find(text, "FailedObstacle", 1, true) ~= nil
        and string.find(text, "FAILED_", 1, true) == nil
end

-- A named edge refusal is the same shape as a plain obstacle: the engine
-- would not take that line to that square, not the room. Admit the two
-- wall-corner kinds (diagonal clip, blocked cardinal edge) to the existing
-- door owner and alternate entry before the generic retry, so the Java
-- corner screen recovers instead of re-issuing the same blocked line.
-- Cooldown and named door/window failures keep their own handling.
local function isCornerObstacleFailure(movement)
    local text = tostring(movement or "")
    return string.find(text, "FAILED_BLOCKED_DIAGONAL", 1, true) ~= nil
        or string.find(text, "FAILED_STATIC_BLOCKAGE", 1, true) ~= nil
end

function Updates.install(Controller, context)
    local AID_RETRY_TICKS = context.AID_RETRY_TICKS
    local BLOCKED_AREA_COOLDOWN_TICKS = context.BLOCKED_AREA_COOLDOWN_TICKS
    local COMBAT_POST_KILL_FORMATION_DELAY_TICKS = context.COMBAT_POST_KILL_FORMATION_DELAY_TICKS
    local COMBAT_RANGED_YIELD_DELAY_TICKS = context.COMBAT_RANGED_YIELD_DELAY_TICKS
    local EMPTY_SEARCH_COOLDOWN_TICKS = context.EMPTY_SEARCH_COOLDOWN_TICKS
    local EXPLORATION_RETRY_TICKS = context.EXPLORATION_RETRY_TICKS
    local LOOT_TRAVEL_COOLDOWN_TICKS = context.LOOT_TRAVEL_COOLDOWN_TICKS
    local SUPPLY_RETRY_TICKS = context.SUPPLY_RETRY_TICKS
    local TASK_TRAVEL_STALL_TICKS = context.TASK_TRAVEL_STALL_TICKS
    local THINK_MIN_TICKS = context.THINK_MIN_TICKS
    local THREAT_FAILURE_COOLDOWN_TICKS = context.THREAT_FAILURE_COOLDOWN_TICKS
    local THREAT_SCAN_TICKS = context.THREAT_SCAN_TICKS
    local currentWorldAgeHours = context.currentWorldAgeHours
    local diagSquare = context.diagSquare
    local distanceSquared = context.distanceSquared
    local findExploration = context.findExploration
    local findFormationTarget = context.findFormationTarget
    local findSupply = context.findSupply
    local fleeAssessment = context.fleeAssessment
    local hasPendingTimedActions = context.hasPendingTimedActions
    local markPendingAreaBlocked = context.markPendingAreaBlocked
    local moveWithTravelPace = context.moveWithTravelPace
    local nativeTraversalBusy = context.nativeTraversalBusy
    local navigationDistanceSquared = context.navigationDistanceSquared
    local nearestThreat = context.nearestThreat
    local release = context.release
    local rememberRoamDestination = context.rememberRoamDestination
    local retreatIsSafelyClear = context.retreatIsSafelyClear
    local roadFinalById = context.roadFinalById
    local roamDestinationKey = context.roamDestinationKey
    local safeMethod = context.safeMethod
    local shouldDropCombatTarget = context.shouldDropCombatTarget
    local shouldRemainStealthy = context.shouldRemainStealthy
    local shouldReplaceCombatTarget = context.shouldReplaceCombatTarget

    function Controller:nextThreatScanAfter(ticks)
        -- Shared interruptions may force an immediate scan for many people.
        -- Realign their next periodic scan instead of keeping the whole group
        -- synchronized forever. The delay never exceeds the existing interval.
        -- Keep the remainder input positive under installed Kahlua semantics.
        local delay = ((self.perceptionPhase or 0)-(ticks%THREAT_SCAN_TICKS)
            + THREAT_SCAN_TICKS)%THREAT_SCAN_TICKS
        return ticks+(delay==0 and THREAT_SCAN_TICKS or delay)
    end

    function Controller:think(ticks)
        -- The persisted leader id is the durable link. Resolve the live character
        -- before any need or support choice reads it; assignment still belongs
        -- to KnoxSurvivorRelationships. A temporarily unreadable link is held
        -- as GROUP_WAIT below rather than becoming an independent idler.
        if self.groupLeaderId ~= nil then
            self:resolveGroupLeader()
        end
        -- Use the same stealth check as threat scans; visible danger still takes priority.
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
        local equipmentNeed = decision
        -- Residents use carried or assigned supplies. Only an explicit supply order
        -- allows findSupply() to search outside the base.
        if self.baseId ~= nil and self.baseSupplyOrder == nil
            and (decision.kind == "find_food" or decision.kind == "find_water"
                or decision.kind == "find_medical") then
            if Controller.selfCareReady(self.selfCareRetryAt, decision.kind, ticks) then
                if self.baseTask ~= nil and self.baseTask.type ~= "cook" then
                    self:suspendBaseTaskForThreat("needs_interrupt")
                end
                if self:beginWorldSearch(decision.kind, ticks) then return end
                -- A missing safe meal is not a missing ingredient. Use the same
                -- kitchen owner after storage retrieval fails, retaining the
                -- resident's claim and the actual meal for native self-care.
                if decision.kind == "find_food" then
                    if self.baseTask ~= nil and self.baseTask.type == "cook" then
                        if self:beginBaseTask(ticks) then return end
                    elseif self:beginBaseCooking(ticks, nil, true) then return end
                end
            end
            -- A hungry resident with no reachable supply must never convert the
            -- need into roaming or patrol duty. Hold and retry on the normal
            -- supply throttle instead of working to death.
            self:clearLifeIntent()
            self.state = "BASE_IDLE"
            self.activeDecision = "waiting_for_" .. string.sub(decision.kind, 6)
            self.nextThink = math.max(self.nextThink or 0,
                (self.nextWorldSearch or ticks) + THINK_MIN_TICKS,
                tonumber((self.selfCareRetryAt or {})[decision.kind]) or 0)
            return
        end
        if decision.kind == "fight" then
            if not self:beginCombat(decision.target) then
                self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
                self.nextThreatScan = math.max(self.nextThreatScan or 0, ticks + THREAT_SCAN_TICKS)
            end
            return
        end
        -- Orders can defer ordinary rest, but not critical recovery or sleep.
        -- Keep the order so it can resume after recovery.
        local hasDirectOrder = self.companionOrder ~= nil or self.companionDirective ~= nil
        if hasDirectOrder and decision.kind == "rest"
            and not Controller.isCriticalOrderedRecovery(decision) then
            decision = { kind = "roam", state = decision.state }
        end
        if (decision.kind == "eat" or decision.kind == "drink"
            or KnoxSurvivorNeeds.isMedicalCare(decision.kind)
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
            or KnoxSurvivorNeeds.isMedicalCare(decision.kind) then
            local action, result, intent = self:executeNeedAction(decision, ticks)
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
        -- Equipment selection must respect the original need, even during its retry cooldown.
        if self.state == "IDLE" then
            local equipped, equipmentReason = self:reconsiderEquipment(ticks, false, equipmentNeed)
            -- A role-kit withdrawal owns the native inventory action until it
            -- drains. Keep the decision loop parked rather than starting a job or
            -- another pickup behind the same timed action.
            if equipped and (equipmentReason == "role_kit_pickup"
                or equipmentReason == "role_kit_move") then
                self.nextThink = ticks + 60
                return
            end
        end
        if self.groupLeaderId ~= nil
            and (self.groupLeader == nil
                or self.groupLeader:getCurrentSquare() == nil)
            and self.awayTeamId == nil
            and self.baseSupplyTrip ~= true
            and self.pendingBaseSupplyDeposit == nil then
            -- A grouped follower must not silently become independent when the
            -- leader id exists but the character is temporarily unreadable.
            -- Intentional away/supply/deposit priorities are not broken links.
            self.activeDecision = "follow_group"
            self.state = "GROUP_WAIT"
            self.nextThink = math.max(self.nextThink or 0, ticks + 30)
            return
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
            -- Completed or blocked: release the claim so this same pass can pick
            -- ordinary work back up for a member standing in front of the player.
            self:clearFinishedAwayTeam(ticks, awayTeam)
            if self.awayTeamId ~= nil and awayTeam ~= nil
                and (awayTeam.state == "awaiting_collection"
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
            if anchor.knownContact then
                self:beginCompanionFollow(ticks)
                return
            end
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
                -- A settled companion can use the same safe aid path as a camp
                -- or base resident. Travel and explicit orders retain priority;
                -- treating a nearby bleeding ally comes before optional looting.
                if self:beginBattlefieldAid(ticks) then return end
                -- Follow retains the destination. Explicit loot orders and urgent
                -- self-care are admitted above; idle opportunities cannot replace it.
                self:resetMovementRecovery()
                self.formationMovementPace = nil
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
        -- A member that joined a travel group follows its leader in the field.
        -- The base branch sends any non-resident home, so once the group's
        -- leader claimed a site every member was pulled indoors instead of
        -- following him, and a spawned party never formed up outdoors. Base
        -- work already in flight keeps its priority; nothing new is stored,
        -- the leader field already exists.
        local groupFollowing = self.groupLeader ~= nil
            and self.groupLeader:getCurrentSquare() ~= nil
            and self.awayTeamId == nil
            and self.baseSupplyTrip ~= true
            and self.pendingBaseSupplyDeposit == nil
        local groupTravelling = groupFollowing
            and not (self.base ~= nil and KnoxBaseManager.containsSquare(
                self.base,
                self.character:getCurrentSquare()
            ))
        if self.baseId ~= nil and self.base ~= nil and not groupTravelling then
            self:syncBaseSupplyRun()
            self:applyResidentStayHome(ticks)
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
            elseif self.pendingBaseSupplyDeposit ~= nil then
                if not self:beginBaseSupplyDeposit(ticks) then
                    self.activeDecision = "base_supply_delivery_wait"
                    self.state = "BASE_IDLE"
                    self.nextThink = math.max(self.nextThink or 0, ticks + 180)
                end
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
                -- Structural danger outranks the rota. Raise and answer it
                -- before scheduled sleep or any fresh automatic work.
                self:raiseStructuralAlarm(ticks)
                if self:answerBaseAlarm(ticks) then return end
                local homeAssignment = KnoxBaseJobs.scheduleAssignment ~= nil
                    and KnoxBaseJobs.scheduleAssignment(self.id) or "anything"
                self.lastScheduleAssignment = homeAssignment
                if homeAssignment == "sleep" then
                    self:beginScheduledBaseSleep(ticks)
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
                -- Missing player preference means Stay Home; only explicit permission
                -- permits automatic runs. A faction resident may answer only its
                -- own faction base's shortage.
                -- Existing group-sortie leases remain separate and are not stolen.
                local need = self:baseSupplyNeed(ticks)
                if need ~= nil and self.baseSupplyTrip == true and self.baseSupplyKind ~= nil then
                    local supplyKind = self.baseSupplyKind
                    if self:beginWorldSearch(supplyKind, ticks) then
                        self:beginBaseSupplyRun(self.baseSupplyKind)
                        return
                    end
                    if self.lastWorldSearchOutcome == "no_candidate" then
                        self:reportBaseSupplySearchMiss(supplyKind, ticks)
                        self:recordFailure(
                            "base_supply_no_nearby:" .. tostring(supplyKind),
                            ticks,
                            SUPPLY_RETRY_TICKS
                        )
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
                -- Existing claims and explicit player orders keep their normal
                -- priority over optional leisure. Use the same task owner, but
                -- do not elect fresh automatic work that would consume the break.
                if self.leisureBreakDue == true and self:beginBaseTask(ticks, true) then
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
                    if self:beginBaseTask(ticks,true) then return end
                    if self:beginBaseSurfaceCleaning(ticks) then return end
                    if self:beginBaseOrganize(ticks,true) then return end
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
                self:offerBaseAdvice(ticks)
                local choice = Controller.baseIdleChoice(
                    ticks,
                    self.id,
                    type(residentIds) == "table" and #residentIds or 1,
                    (idleAssignment == "recreation" or forceLeisure) and "recreation" or nil
                )
                if self:beginBattlefieldAid(ticks) then
                    return
                end
                self:runBaseIdleChoice(ticks, choice)
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
        -- A camp is a temporary party site, not a settled home. A loaded
        -- leader owns the member's decision there too, so a group does not
        -- leave its leader walking while every follower idles at the camp.
        -- Members with no live leader keep the existing camp loop.
        if self.campId ~= nil and self.camp ~= nil and not groupFollowing then
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
            self:raiseStructuralAlarm(ticks)
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
            -- A formation route that just failed owns its retry time.
            -- Re-issuing the same slot immediately walks into the same
            -- obstacle, counts another failure and parks the member until the
            -- ladder caps; honour the recorded retry and hold instead.
            if ticks < (tonumber(self.nextFormationRefresh) or 0) then
                self.activeDecision = "follow_group"
                self.state = "GROUP_WAIT"
                self.nextThink = math.max(self.nextThink or 0, self.nextFormationRefresh)
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
        -- A party answers a horde as one body. When a member is already
        -- fighting inside the rally radius, an idle survivor walks to that
        -- fight through the existing regroup owner; the normal threat scan
        -- then picks its own target, so nobody is handed an invented enemy.
        if self.combatTarget == nil and self.pendingThreatAwareness == nil
            and ticks >= (self.nextGroupCombatRally or 0) then
            local fightingMember = self:groupCombatRallyMember(ticks)
            if fightingMember ~= nil then
                self.nextGroupCombatRally = ticks
                    + Controller.TUNING.GROUP_COMBAT_RALLY_COOLDOWN_TICKS
                if self:beginGroupRegroup(fightingMember, ticks) then
                    self.activeDecision = "group_combat_rally"
                    return
                end
            end
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
            -- No owner holds a route: roam, and when roaming has no goal
            -- right now, shift position instead of standing frozen.
            if not self:beginRoam(ticks) then
                self:beginIdleReposition(ticks)
            end
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
                    and self.baseTask.type ~= "repair"
                    and self.baseTask.type ~= "craft_bed"
                    and self.baseTask.type ~= "prepare_bed") then
                self:finishBaseTask(false, "unsupported_base_action")
                self:finishDecision(ticks)
                return true
            end
            if hasPendingTimedActions(self.character) then return end
            if self.baseTask.type == "prepare_bed" then
                if not self.baseTaskActionQueued then
                    local plan = KnoxBaseManager.bedPreparationPlan(self.base, self.character)
                    if plan == nil then self:failBaseTaskAction(ticks, "bed_preparation_unavailable"); return true end
                    if plan.phase == "move" then return self:beginBaseTaskWorkMove(ticks) end
                    local claimed = self.baseTask
                    local function guard()
                        local duty = KnoxPersistence.getSurvivorDuty(self.id)
                        return self.baseTask == claimed and self:baseTaskStillOurs()
                            and duty ~= nil and duty.mode == "base" and duty.baseId == self.baseId
                            and KnoxBaseManager.containsSquare(self.base, self.character:getCurrentSquare())
                    end
                    local action, reason
                    if plan.phase == "grab" then
                        action, reason = KnoxInventoryActions.queueGrab(self.character, plan.object, function()
                            return guard() and KnoxBaseManager.bedFloorCollectionAllowed(
                                self.base, self.character, plan.object, plan.item)
                        end)
                    elseif plan.phase == "retrieve" then
                        action, reason = KnoxInventoryActions.queueTransfer(self.character, plan.item,
                            plan.item:getContainer(), self.character:getInventory(), nil, guard)
                    elseif plan.phase == "unpack" then
                        action, reason = KnoxInventoryActions.queueCraft(self.character,
                            "UnpackSleepingBag", guard, self.base, plan.item)
                    else
                        action, reason = KnoxInventoryActions.queueBedPlacement(self.character, plan, guard)
                    end
                    if action == nil then self:failBaseTaskAction(ticks, reason); return true end
                    self.baseTaskBedPlan, self.baseTaskActionQueued = plan, true
                    self:watchBaseTaskAction(action, ticks, nil)
                    return true
                end
                local plan = self.baseTaskBedPlan
                local action = self.baseTaskActionWatch ~= nil and self.baseTaskActionWatch.action
                local complete = plan ~= nil and ((plan.phase == "retrieve" or plan.phase == "grab")
                    and plan.item:getContainer() == self.character:getInventory()
                    or plan.phase == "unpack" and KnoxInventoryActions.craftedOutput(action, plan.outputType) ~= nil
                    or plan.phase == "place" and self:bedTaskReceipt())
                if complete and plan.phase ~= "place" then
                    self.baseTaskActionQueued, self.baseTaskBedPlan, self.baseTaskActionWatch = false, nil, nil
                    return true
                end
                self:finishBaseTask(complete == true, complete and "sleeping_bag_placed" or "bed_preparation_no_result")
                self:finishDecision(ticks)
                return true
            end
            if self.baseTask.type == "craft_bed" then
                local claimed = self.baseTask
                local function guard()
                    local duty = KnoxPersistence.getSurvivorDuty(self.id)
                    return self.baseTask == claimed and self:baseTaskStillOurs()
                        and duty ~= nil and duty.mode == "base" and duty.baseId == self.baseId
                        and KnoxBaseManager.containsSquare(self.base, self.character:getCurrentSquare())
                end
                -- A distant trip named this exact item before walking. At the
                -- source the same nearby storage/access permission must still
                -- hold; native selection runs again from the work surface.
                if not self.baseTaskActionQueued and self.baseTaskBedPlan ~= nil
                    and self.baseTaskBedPlan.phase == "craft_supply_move" then
                    local plan = self.baseTaskBedPlan
                    if plan.item:getContainer() ~= self.character:getInventory() then
                        local action, reason = KnoxInventoryActions.queueTransfer(self.character,
                            plan.item, plan.source.container, self.character:getInventory(), nil,
                            function()
                                return guard() and KnoxInventoryActions.craftSupplyStillAvailable(
                                    self.base, self.character, plan)
                            end)
                        if action == nil then self:failBaseTaskAction(ticks, reason); return true end
                        self.baseTaskBedApproach = nil
                        self.baseTaskActionQueued = true
                        self:watchBaseTaskAction(action, ticks, nil)
                        return true
                    end
                end
                if not self.baseTaskActionQueued then
                    local plan = self:planBedCraft()
                    if plan == nil then
                        self:failBaseTaskAction(ticks, "bed_recipe_unavailable"); return true
                    end
                    if plan.phase == "craft_blocked" then
                        self:refuseBedCraftInput(ticks, plan)
                        return true
                    end
                    if plan.phase == "craft_supply_move" or plan.phase == "craft_return" then
                        self.baseTaskBedPlan = plan
                        self.baseTaskBedApproach = plan.approach
                        self.baseTaskBedSurface = plan.surface or self.baseTaskBedSurface
                        self:beginBaseTaskWorkMove(ticks)
                        return true
                    end
                    local action, reason
                    if plan.phase == "craft_supply" then
                        action, reason = KnoxInventoryActions.queueTransfer(self.character, plan.item,
                            plan.source.container, self.character:getInventory(), nil, function()
                                return guard() and KnoxInventoryActions.craftSupplyStillAvailable(self.base, self.character, plan)
                            end)
                        self.baseTaskBedPlan = plan
                    else
                        action, reason = KnoxInventoryActions.queueCraft(self.character,
                            "SewHideSleepingBag", guard, self.base)
                        self.baseTaskBedPlan = nil
                    end
                    if action == nil then self:failBaseTaskAction(ticks, reason); return true end
                    self.baseTaskActionQueued = true
                    self:watchBaseTaskAction(action, ticks, nil)
                    return true
                end
                if self.baseTaskBedPlan ~= nil
                    and (self.baseTaskBedPlan.phase == "craft_supply"
                        or self.baseTaskBedPlan.phase == "craft_supply_move") then
                    local plan = self.baseTaskBedPlan
                    if plan.item:getContainer() ~= self.character:getInventory() then
                        self:failBaseTaskAction(ticks, "recipe_supply_transfer_not_completed"); return true
                    end
                    self.baseTaskActionQueued, self.baseTaskBedPlan, self.baseTaskActionWatch = false, nil, nil
                    -- Remember the surface for the return leg; the next update
                    -- clears it once native selection works from here again.
                    self.baseTaskBedSurface = plan.surface or self.baseTaskBedSurface
                    self.baseTaskBedReturn = true
                    return true
                end
                local complete, reason = self:bedTaskReceipt()
                self:finishBaseTask(complete, reason)
                self:finishDecision(ticks)
                return true
            end
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
                    self:watchBaseTaskAction(action, ticks, target)
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
                -- A finished action that changed nothing is a loop, not progress:
                -- the window will not take another board. Name it so the board
                -- stops the work instead of re-queuing the same trip.
                local changed = complete
                    or (tonumber(after) or 0) > (tonumber(self.baseTaskBarricadeBefore) or 0)
                local plankReason = complete and "barricade_plank_added"
                    or (changed and "barricade_not_completed" or "barricade_no_progress")
                local accepted = self:finishBaseTask(complete, plankReason)
                if complete and accepted then
                    KnoxActivityFeed.speak(self.character, "One more layer on the windows.")
                end
                self:finishDecision(ticks)
                return true
            end
            if self.baseTask.type == "haul_corpse" then
                -- Drop-destination cooldown: after a failed drop at these coords,
                -- do not touch the body again until it expires. This converts a
                -- grab->carry->release->regrab loop (e.g. fence-separated disposal)
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
                    if self.baseTaskCorpsePhase == "grab" and self.reportKnownCorpse ~= nil then
                        local ok, err = pcall(self.reportKnownCorpse, self, target)
                        if not ok then print("[KnoxSurvivors] corpse_recognition_error=" .. tostring(err)) end
                    end
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
                    if self.baseTaskRepairBefore == nil then
                        self:failBaseTaskAction(ticks, "repair_health_unavailable")
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
                    self:watchBaseTaskAction(action, ticks, target)
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
                    self:watchBaseTaskAction(action, ticks, target)
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
                        water,
                        {survivorId = self.id, taskId = self.baseTask.id, baseId = self.baseId}
                    )
                    if action == nil then
                        self:failBaseTaskAction(ticks, "farming_queue:" .. tostring(actionResult))
                        return true
                    end
                    self.baseTaskActionQueued = true
                    self.baseTaskStartedAt = ticks
                    self:watchBaseTaskAction(action, ticks, target)
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

    -- The route pauses at its exact smashed window. Only the native timed
    -- action removes glass; cancellation/failure returns to movement recovery.
    function Controller:prepareRouteWindowGlass(movement, ticks)
        local pending = self.windowGlassAction
        if pending ~= nil then
            if hasPendingTimedActions(self.character) then return "waiting" end
            self.windowGlassAction = nil
            local ok, cleared = pcall(function() return pending.window:isGlassRemoved() end)
            return ok and cleared == true and "ready" or "failed"
        end
        if movement ~= "Transition:WINDOW_GLASS_REQUIRED" then return "ready" end
        if not self.bridge or not self.bridge.getNpcWindowForGlassRemoval then return "failed" end
        local ok, window = pcall(function() return self.bridge:getNpcWindowForGlassRemoval(self.id) end)
        if not ok or window == nil then return "failed" end
        local valid, cleared = pcall(function() return window:isGlassRemoved() end)
        if valid and cleared == true then return "ready" end
        if hasPendingTimedActions(self.character) then return "waiting" end
        local action
        ok = pcall(function()
            action = ISRemoveBrokenGlass:new(self.character, window)
            if not action:isValid() then error("window_glass_action_invalid") end
            ISTimedActionQueue.add(action)
        end)
        if not ok or not hasPendingTimedActions(self.character) then return "failed" end
        self.windowGlassAction = {window=window, action=action, startedAt=ticks}
        return "waiting"
    end

    local function updateMovement(self, ticks)
        local glass = self:prepareRouteWindowGlass(nil, ticks)
        if glass == "waiting" then return end
        if (self.state == "GROUP_FOLLOW" or self.state == "COMPANION_FOLLOW")
            and self:refreshFormationFollow(ticks) then
            return
        end
        local movement = glass == "failed" and "FailedObstacle:FAILED_WINDOW_GLASS_REMOVAL"
            or tostring(self.bridge:tickNpc(self.id))
        if movement == "Transition:WINDOW_GLASS_REQUIRED" then
            glass = self:prepareRouteWindowGlass(movement, ticks)
            if glass ~= "failed" then return end
            movement = "FailedObstacle:FAILED_WINDOW_GLASS_REMOVAL"
        end
        if glass == "failed" then self.bridge:cancelNpcMove(self.id) end
        -- Fail stalled job travel unless a native climb or entry action is in progress.
        -- noteTaskTravelStart tracks progress so unreachable routes do not retry forever.
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
            if self:refuseUnreachableBedCraft(ticks) then return end
            self:failBaseTaskAction(ticks,
                self.state == "BASE_TASK_SUPPLY_MOVE"
                    and "assigned_supply_no_progress" or "task_move_no_progress")
            return
        end
        if movement == "Succeeded" then
            if self:resumeFormationCornerMovement(ticks) then return end
            if self:resumeBaseTaskCornerMovement(ticks) then return end
            self:resetMovementRecovery()
            self.formationDoorRetry = nil
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
                if hasPendingTimedActions(self.character) then return end
                local plan = self.pendingAid
                if plan == nil or not self:aidPermission(plan) then
                    self:releaseAid()
                    self.nextAidAt = ticks + AID_RETRY_TICKS
                    self:finishDecision(ticks)
                    return
                end
                if not self:queueBattlefieldAid(plan, ticks) then
                    self:finishDecision(ticks)
                end
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
                local candidate=self.factionBaseCandidate
                local worldAge=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                local ownerId=self.baseCandidateOwnerId or self.factionId
                local groupHome=self.baseCandidateOwnerKind=="group"
                local home,result
                if groupHome then
                    local base
                    base,result=KnoxPersistence.confirmGroupHomeBase(ownerId,candidate.buildingId,self.character,worldAge)
                    if base ~= nil then
                        home=base.home
                        KnoxBaseManager.ensureGroupBase(KnoxPersistence.getTravelGroups()[ownerId])
                        local duty=KnoxPersistence.getSurvivorDuty(self.id)
                        if duty ~= nil and duty.mode=="base" and duty.baseId==base.id then self:setBaseAssignment(base.id,base) end
                    end
                else
                    local arrivalVerified
                    arrivalVerified,result=KnoxFactionBaseScouting.validateArrival(self.character,candidate,ownerId,worldAge)
                    if arrivalVerified then home,result=KnoxPersistence.confirmFactionHomeBase(ownerId,candidate.buildingId,worldAge) end
                end
                if groupHome and home ~= nil then
                    self.counts.baseScout=self.counts.baseScout+1
                    KnoxActivityFeed.speak(self.character,"This place could work.")
                elseif home ~= nil then
                    self.counts.baseScout = self.counts.baseScout + 1
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
                    if base ~= nil and safehouseResult == "protected" then
                        KnoxActivityFeed.speak(self.character, "This place could work.")
                        KnoxActivityFeed.event(
                            "Home base established near " .. tostring(home.x)
                                .. ", " .. tostring(home.y) .. ".")
                    else
                        KnoxActivityFeed.event("Shelter found. We're still getting settled.")
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
                    if result == "safehouse_query_failed" and candidate ~= nil then
                        -- Transient native query failure is not evidence against
                        -- this building. Retain the lead with a bounded retry.
                        candidate.retryAtHours = worldAge + 1/60
                    else
                        self:rejectFactionBaseCandidate(ticks, result)
                    end
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
            if self.state == "ROLE_KIT_MOVE" then
                self:completeRoleKitMove(ticks)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                local queued, actionResult = self:queueBaseTaskSupplyTransfer(ticks)
                if not queued then
                    self:failBaseTaskAction(ticks,
                        "assigned_supply_transfer_queue:" .. tostring(actionResult))
                    return
                end
                return
            end
            if self.state == "BASE_TASK_MOVE" then
                if self.baseTask ~= nil and self.baseTask.type == "prepare_bed" then
                    self.state, self.activeDecision = "BASE_TASK_ACTION", "base_task_prepare_bed"
                    self.baseTaskStartedAt, self.baseTaskActionQueued = ticks, false
                    self.baseTaskBedPlan, self.baseTaskActionWatch = nil, nil
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "craft_bed" then
                    -- Keep the named ingredient source plan: the action loop
                    -- queues its transfer only after physical arrival.
                    self.state, self.activeDecision = "BASE_TASK_ACTION", "base_task_craft_bed"
                    self.baseTaskStartedAt, self.baseTaskActionQueued = ticks, false
                    self.baseTaskActionWatch, self.baseTaskBedApproach = nil, nil
                    return
                end
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
                local admitted, result = self:queueSupplyCollection(ticks)
                if admitted then
                    -- Refused admission did not inspect or loot this container.
                    -- Keep it eligible for the existing bounded retry path.
                    self.inspectedContainers[supply.container] = ticks
                        + (supply.items ~= nil and #supply.items > 0
                            and LOOT_TRAVEL_COOLDOWN_TICKS or EMPTY_SEARCH_COOLDOWN_TICKS)
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
                    self:finishSupplyCollectionRefusal(supply, result, ticks)
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
                self:handleFormationMovementFailure(movement, ticks)
                return
            end
            if self.state == "FLEEING" then
                self:recoverFleeMovement(movement, ticks)
                return
            end
            self.baseTaskCornerMove = nil
            if self:recoverBaseTaskObstacle(movement, ticks) then return end
            if (self.state=="BASE_TASK_MOVE" and self.baseTask~=nil
                and (self.baseTask.type=="guard" or self.baseTask.type=="patrol"))
                or self.state=="MOVING_TO_COMPANION_PATROL"
                or (self.state=="MOVING_TO_COMPANION_POINT" and self.companionDirective~=nil
                    and self.companionDirective.kind=="guard") then
                if self.state == "BASE_TASK_MOVE"
                    and string.find(movement, "FAILED_LOCKED_DOOR", 1, true)
                    and self:beginBaseTaskWindowDetour(ticks) then
                    return
                end
                self:deferSecurityRoute(ticks,movement,self.state=="BASE_TASK_MOVE")
                return
            end
            local needSource = self.state == "MOVING_TO_SUPPLY" and self.pendingSupply ~= nil
                and (self.pendingSupply.container or self.pendingSupply.waterSource) or nil
            local alternateNeed = needSource ~= nil
                and Controller.isOrdinaryNeedRoute(self, self.activeDecision)
            local retry = alternateNeed and Controller.TUNING.SELF_CARE_RETRY_TICKS or nil
            self:recordMovementFailure("movement", movement, ticks, retry, retry)
            if alternateNeed then
                self.inspectedContainers[needSource] = ticks + SUPPLY_RETRY_TICKS
                self.nextWorldSearch = math.max(self.nextWorldSearch or 0, ticks + retry)
            end
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
                    and self:recoverMovementThroughDoor(ticks) then
                    return
                end
                if string.find(movement, "FAILED_LOCKED_DOOR", 1, true) then
                    local target = self.ambientMovementSquare
                    if self.pendingSupply == nil and target ~= nil then
                        self.pendingSupply = {targetSquare=target, approach=target, ambientEntry=true}
                        if self:beginWindowDetour(ticks, self.state) then return end
                        self.pendingSupply = nil
                    end
                end
                self:handleBaseMovementFailure(movement, ticks)
                return
            end
            if self.state == "ROLE_KIT_MOVE" then
                self:failRoleKitMove(ticks, movement)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                -- A corner or an unclassified obstacle on the way to a job's
                -- supplies is the same blocked line as an entrance refusal:
                -- hand it to the door owner before giving up on the job. The
                -- entry kinds keep their window/break fallbacks below; the
                -- edge cooldown stays a wait.
                if Controller.isEntryTraversalFailure(movement)
                    or Controller.isDoorReachFailure(movement)
                    or isCornerObstacleFailure(movement)
                    or isPlainObstacleFailure(movement) then
                    local lockedDoor = string.find(
                        movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
                    if not lockedDoor and self.baseTaskMoveRetryIssued ~= true
                        and self:recoverMovementThroughDoor(ticks) then
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
                if self:refuseUnreachableBedCraft(ticks) then return true end
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
            if (self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE")
                and (isPlainObstacleFailure(movement) or isCornerObstacleFailure(movement)
                    or Controller.isDoorReachFailure(movement)
                    or Controller.isEntryTraversalFailure(movement)) then
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
                if not lockedDoor and self:recoverMovementThroughDoor(ticks) then
                    return
                end
                if not isPlainObstacleFailure(movement) then
                    if self:beginWindowDetour(ticks, resumeState) then return end
                    markPendingAreaBlocked(self, ticks, "alternate_entry_unavailable")
                end
            end
            if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                local failedSquare = self.pendingSupply.container:getSourceGrid()
                rememberRoamDestination(self, roamDestinationKey(failedSquare), ticks, Controller.TUNING.ROAM_FAILURE_COOLDOWN_TICKS)
                local transient = Controller.transientPathFailure(movement)
                if not alternateNeed and not transient then
                    markPendingAreaBlocked(self, ticks, "unreachable_supply")
                elseif transient then
                    -- One refused approach is retried against the same
                    -- container in SUPPLY_RETRY_TICKS; the area stays usable.
                    self.forceTravel = true
                end
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. (transient and " retried-container movement="
                            or " skipped-unreachable-container movement=") .. movement
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

    local function updateLooting(self, ticks)
        if not hasPendingTimedActions(self.character) then
            local retrievedNeedKind = (self.activeDecision == "find_food"
                or self.activeDecision == "find_water"
                or self.activeDecision == "find_medical") and self.activeDecision or nil
            local retrievedNeedItem = self.pendingSupply ~= nil
                and self.pendingSupply.item or nil
            local retrievedNeedVerified = retrievedNeedKind == nil
            if retrievedNeedKind ~= nil then
                retrievedNeedVerified = self:collectionItemReceived(self.pendingSupply, retrievedNeedItem)
                if not retrievedNeedVerified then
                    -- Do not immediately choose the same failed source after
                    -- the shorter need retry when another real store exists.
                    local source = self.pendingSupply ~= nil and self.pendingSupply.container or nil
                    if source ~= nil then
                        self.inspectedContainers[source] = ticks + SUPPLY_RETRY_TICKS
                    end
                    self.selfCareRetryAt[retrievedNeedKind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
                    self:recordFailure(
                        "need_supply_transfer_not_completed",
                        ticks,
                        Controller.TUNING.SELF_CARE_RETRY_TICKS
                    )
                    self:releaseSupply()
                    self:finishDecision(ticks)
                    return
                end
            end
            local partyFoodItem = self.pendingSupply ~= nil
                and self.pendingSupply.partySupport == true
                and self.pendingSupply.items ~= nil
                and self.pendingSupply.items[1] ~= nil
                and self.pendingSupply.items[1].item or nil
            if self.pendingSupply ~= nil
                and self.pendingSupply.partySupport == true
                and not self:collectionItemReceived(self.pendingSupply, partyFoodItem) then
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
                -- The sweep announces only after this exact receipt succeeds,
                -- so a planner guess can never become a false find line.
                local house = rawget(_G, "KnoxHouseClearing")
                if house ~= nil and house.onLootVerified ~= nil then
                    pcall(house.onLootVerified, self, self.pendingSupply)
                end
            end
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, true)
                return
            end
            if self.awayTeamId ~= nil and retrievedNeedKind == nil
                and self.pendingSupply ~= nil and self.pendingSupply.awayMission == true then
                self:finishAwayCollection(ticks)
                return
            end
            self.counts.loot = self.counts.loot + 1
            local settlementPickup = self.pendingSupply ~= nil
                and self.pendingSupply.baseSupplyPartyBaseId ~= nil
            local changed, equipment = false, nil
            if not settlementPickup then
                changed, equipment = self:reconsiderEquipment(ticks, true)
            end
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

    local function updateSearching(self, ticks)
        if not hasPendingTimedActions(self.character) then
            if self.pendingSupply == nil or self.pendingSupply.searchAction == nil
                or self.pendingSupply.searchAction.knoxSearchCompleted ~= true then
                self:recordFailure("container_search_not_completed", ticks, SUPPLY_RETRY_TICKS)
                self:releaseSupply()
                self:finishDecision(ticks)
                return
            end
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, false)
                return
            end
            if self.awayTeamId ~= nil and retrievedNeedKind == nil
                and self.pendingSupply ~= nil and self.pendingSupply.awayMission == true then
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
            -- One empty container is not an exhausted area. A companion or
            -- mission order already owns a three-miss budget (beginExploration
            -- clears it), so hand the search back for the next container
            -- instead of dropping the order at the first empty shelf. The
            -- container just searched is already in inspectedContainers, so
            -- the next candidate is a different one; a failed hand-back falls
            -- through to the existing single-container release below.
            local continuingOrder = self.companionDirective
            if continuingOrder ~= nil and (self.directiveMisses or 0) < 2
                and ticks >= (self.nextExplorationSearch or 0) then
                self.directiveMisses = (self.directiveMisses or 0) + 1
                self:releaseSupply()
                if self:beginExploration(ticks, continuingOrder) then
                    return
                end
            end
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

    -- Posture costs four native reads per survivor per frame, and it only feeds
    -- a get-up latch and a diagnostic stamp. A short cadence is enough; a latched
    -- get-up still probes immediately so the flag cannot linger while standing.
    local POSTURE_PROBE_TICKS = 6

    function Controller.postureProbeDue(ticks, nextProbe, latched)
        if latched == true then return true end
        return (tonumber(ticks) or 0) >= (tonumber(nextProbe) or 0)
    end

    function Controller:tick(ticks)
        self.currentTicks = ticks
        self:observeGroupEntry(ticks)
        self:checkSharedMeal(ticks)
        -- Check stale animation flags every 15 ticks. Recovery still requires
        -- 180 idle ticks; polling every frame would not release them sooner.
        if ticks >= (self.nextIdleLatchCheck or 0) then
            self.nextIdleLatchCheck = ticks + 15
            self:recoverIdleAnimationLatch(ticks)
        end
        -- Observe native traversal completion before handling pending orders.
        -- This reads the action result without advancing movement.
        if self.character ~= nil and nativeTraversalBusy(self.character)
            and self.bridge ~= nil and self.bridge.observeNpcNativeAction ~= nil then
            self.bridge:observeNpcNativeAction(self.id)
        end
        if self.pendingFleeAttack ~= nil then
            if self.state == "FLEEING" and self.character ~= nil
                and self.character:getCurrentSquare() ~= nil then
                if Controller.isNativeRecoveryBusy(self.character) then
                    if self.bridge ~= nil and self.bridge.observeNpcNativeRecovery ~= nil then
                        self.bridge:observeNpcNativeRecovery(self.id)
                    end
                    return
                end
                if Controller.isNativeAttackBusy(self.character) or nativeTraversalBusy(self.character) then return end
                local assessment = self.pendingFleeAttack
                self.pendingFleeAttack = nil
                -- Replan from the actual released position. Latest durable orders
                -- stay authoritative; no captured Follow/Hold is restored here.
                if not self:beginFlee(ticks, assessment) then
                    if self:waitingForTransferActions() then
                        self.pendingFleeAttack = assessment
                    elseif self.state == "FLEEING" then
                        -- No escape can legitimately hand off to cornered defense.
                        -- Preserve that new combat owner rather than overwriting it.
                        self:recoverFleeMovement("native_attack_released", ticks)
                    end
                end
                return
            end
            self.pendingFleeAttack = nil
        end
        if not self:applyPendingCombatPolicy() then return end
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
        -- Clear the rest-exit get-up flag after standing. Otherwise it can force an
        -- immediate get-up on the next knockdown. Keep the knockdown duration log.
        if self.character ~= nil then
            local probe = Controller.postureProbeDue(
                ticks, self.nextPostureProbe, self.forceGetUpLatched)
            if probe then
                self.nextPostureProbe = (tonumber(ticks) or 0) + POSTURE_PROBE_TICKS
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
        end
        if self.tradeAction ~= nil and self.state ~= "TRADING" then self:cancelTrade("behavior_changed") end
        if self.character == nil or self.character:getCurrentSquare() == nil then
            self:cancelTrade("detached")
            self:releaseSelfCare()
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

        if (self.state == "COMBAT" or self.state == "BREAKING_LOCKED_DOOR")
            and Controller.isNativeRecoveryBusy(self.character) then
            -- Keep injury inputs clear even while duty/policy projection waits.
            -- Observation must not consume a target/door's terminal combat receipt.
            if self.bridge ~= nil and self.bridge.observeNpcNativeRecovery ~= nil then
                self.bridge:observeNpcNativeRecovery(self.id)
            end
            return
        end

        -- Combat retargeting, reload yield and terminal cleanup also write native
        -- inputs. Keep the whole combat decision paused until a live crossing ends.
        if self.state == "COMBAT" and not safeMethod(self.character, "isDead", false)
            and nativeTraversalBusy(self.character) then return end

        if self.groupHomeRevoked ~= nil then
            -- Revocation never clears another owner's queue or interrupts a
            -- native traversal. Exact pending transfers are already retired.
            if not self:canApplyDutyChange() or hasPendingTimedActions(self.character) then return end
            self.groupHomeRevoked=nil
            self.bridge:cancelNpcMove(self.id)
            self.pendingSupply=nil
            self.activeDecision=nil
            self.state="IDLE"
            self.nextThink=ticks
            return
        end

        if self.pendingDutyChange then
            if not self:canApplyDutyChange() then return end
            self:onDutyChanged()
        end

        if self.companionOrderInterruptPending then
            if nativeTraversalBusy(self.character) then return end
            self.companionOrderInterruptPending = nil
            self:interruptForDirective(true)
            -- Ordinary arbitration applies the latest order on the next update;
            -- emergency states retain the same priority as an immediate handoff.
            return
        end

        -- A dissolved pair may have issued recall only once during a vault.
        -- Keep the native animation, then retire its old supply detour before
        -- another entry or source route can start, even without a live pair lease.
        if (self.baseSupplyPartyReturning == true or self.scavengeSortieReturning == true)
            and self:isSettlementSupplyEntry() then
            if not nativeTraversalBusy(self.character) then self:interruptForDirective() end
            return
        end

        -- Reset the timeout clock when the controller changes state.
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

        -- Finish tracking the previous transfer before the next decision queues work.
        if self.state == "IDLE" and not hasPendingTimedActions(self.character) then
            self:waitingForTransferActions()
        end

        local stateAge = ticks - (self.stateStartedAt or ticks)
        local movementState = MOVEMENT_STATES[self.state] == true
        local actionState = self.state == "LOOTING"
            or self.state == "OPENING_ENTRY_WINDOW"
            or self.state == "INVENTORY_CLEANUP"
            or self.state == "SEARCHING"
            or self.state == "TIMED_ACTION"
            or self.state == "ROBBING"
            or (self.state == "BASE_TASK_WORK"
                and (self.baseTask == nil or self.baseTask.type ~= "guard"))
            or self.state == "BASE_TASK_SUPPLY_TRANSFER"
            or self.state == "AID_ACTION"
            or self.state == "GROUP_SUPPORT"
        local recoveryBusy = Controller.isNativeRecoveryBusy(self.character)
            and not self:sharedMealPostureReady()
        if recoveryBusy and (movementState or actionState or self.state == "BASE_TASK_ACTION") then
            if self.state == "BASE_TASK_MOVE" or self.state == "BASE_TASK_SUPPLY_MOVE" then self:noteTaskTravelStart(ticks) end
            return
        end
        if (movementState and stateAge > Controller.TUNING.MOVEMENT_TIMEOUT_TICKS)
            or (actionState and stateAge > Controller.TUNING.ACTION_TIMEOUT_TICKS)
            or (self.state == "BASE_TASK_ACTION" and self:baseTaskActionTimedOut(ticks, stateAge))
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
            elseif self.state == "TIMED_ACTION" and self.pendingSelfCare ~= nil then
                local intent = self.selfCareIntent or self.pendingSelfCare.intent
                local kind = intent ~= nil and (intent.needKind or intent.kind) or self.activeDecision
                self.selfCareRetryAt[kind] = ticks + Controller.TUNING.SELF_CARE_RETRY_TICKS
                self:releaseSelfCare()
                if kind == "drink_world" then self:releaseSupply() end
                self:recordFailure("self_care_timeout:" .. tostring(kind), ticks,
                    Controller.TUNING.SELF_CARE_RETRY_TICKS)
                self:finishDecision(ticks)
                return
            elseif self.state == "COMPANION_FOLLOW" or self.state == "AWAY_RETURN" then
                self.bridge:cancelNpcMove(self.id)
                self.activeDecision = nil
                self.state = "IDLE"
                self.nextThink = ticks + THINK_MIN_TICKS
                return
            elseif self.state == "MOVING_TO_BASE_CANDIDATE" then
                self:rejectFactionBaseCandidate(ticks, "state_timeout")
            elseif self.state == "ROLE_KIT_MOVE" then
                self.bridge:cancelNpcMove(self.id)
                self.nextRoleKitAt = ticks + 600
            end
            self:abandonCurrentDecision(ticks, "state_timeout_" .. tostring(self.state))
            return
        end

        local traversalBusy = movementState and nativeTraversalBusy(self.character)
        if traversalBusy and (self.state == "BASE_TASK_MOVE" or self.state == "BASE_TASK_SUPPLY_MOVE") then
            -- Native opening/climbing is legitimate stationary work. Refresh the
            -- existing progress anchor so landing does not inherit a spent stall
            -- budget and immediately abandon an otherwise valid resident job.
            self:noteTaskTravelStart(ticks)
        end
        -- Both danger evaluation and active-combat decisions consume this scheduled
        -- observation. Advancing the deadline must not starve the combat branch.
        local observedCareThreat = nil
        local threatScanDue = ticks >= self.nextThreatScan and not traversalBusy and not recoveryBusy
        if threatScanDue then
            self.nextThreatScan = self:nextThreatScanAfter(ticks)
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
                if self:retryRetreatForDanger(ticks, flee, assessment) then return end
                if self.state == "FLEEING" and retreatIsSafelyClear(self, flee, assessment, ticks) then
                    self.bridge:cancelNpcMove(self.id)
                    self:resetMovementRecovery()
                    self.fleeRecoveryUntil = nil
                    self.fleeTarget = nil
                    self.failedFleeTarget = nil
                    self.combatDisengageUntil = nil
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
                    observedCareThreat = threat
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

        if self:tryAutomaticPlayerAid(ticks) then return end
        if self:yieldBaseTaskForNeed(ticks) then return end
        if self:yieldInventoryCleanupForNeed(ticks) then return end
        if self:yieldAidForNeed(ticks) then return end
        if self:yieldCollectionForNeed(ticks) then return end

        -- Recheck the follower's anchor and needs before continuing a food detour.
        -- Let any queued item actions finish normally.
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
            elseif not nativeTraversalBusy(self.character)
                and self:tradeNeedsSelfCare(ticks) then
                self:cancelTrade("survivor_needs_care")
            elseif self.tradeTicksRemaining <= 0 or not self.tradeAction:isValid() then
                self:cancelTrade("trade_interrupted_or_expired")
            end
            return
        end

        if self.state == "MEETING_WAIT" or self.state == "MEETING_READY"
            or self.state == "GREETING" then
            return
        end

        -- Follow and hold can otherwise remain settled indefinitely. Recheck only
        -- after native recovery, traversal and timed-action ownership release.
        if KnoxSurvivorNeeds ~= nil and (self.state == "COMPANION_FOLLOW" or self.state == "COMPANION_WAIT"
            or self.state == "COMPANION_HOLD" or self.state == "COMPANION_GUARD"
            or self.state == "GROUP_FOLLOW" or self.state == "GROUP_WAIT")
            and self.combatTarget == nil and self.pendingThreatAwareness == nil and observedCareThreat == nil
            and not traversalBusy and not recoveryBusy and not nativeTraversalBusy(self.character)
            and not Controller.isNativeAttackBusy(self.character)
            and not hasPendingTimedActions(self.character)
            and ticks >= (self.nextFollowerCareCheck or 0) then
            self.nextFollowerCareCheck = ticks + 90
            local need = KnoxSurvivorNeeds.decide(self.character, nil)
            if need ~= nil and KnoxSurvivorNeeds.isMedicalCare(need.kind)
                and Controller.selfCareReady(self.selfCareRetryAt, need.kind, ticks) then
                if self.state == "COMPANION_FOLLOW" or self.state == "GROUP_FOLLOW" then
                    self.bridge:cancelNpcMove(self.id)
                end
                self.activeDecision, self.state, self.nextThink = nil, "IDLE", ticks
                return
            end
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
            if self.pendingRobberyHold ~= nil
                and ticks >= (tonumber(self.pendingRobberyHold.expiresAt) or 0) then
                self:releaseRobberyHold(nil, ticks, "expired")
                return
            end
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
                elseif self.state == "COMPANION_HOLD" then
                    -- Same promise as the guard post: a fight moves the body,
                    -- the order moves it back. No post recorded (old saves)
                    -- means freezing in place, exactly as before.
                    self:returnToHoldPost(ticks)
                end
            end
            return
        end

        if self.state == "COMPANION_DUTY_WAIT" or self.state == "BASE_SECURITY_WAIT" then
            self:updateSecurityRouteWait(ticks,self.state=="BASE_SECURITY_WAIT")
            return
        end

        if self.state == "COMPANION_WAIT" or self.state == "COMPANION_PATROL_WAIT" then
            -- A settled follower can notice the player leaving without running the
            -- full needs/order decision loop every few ticks. Keep the normal wait
            -- for stationary players and only wake that loop for a real gap.
            if self.state == "COMPANION_WAIT" and self.companionOrder == "follow"
                and self.activeDecision == "follow_player"
                and ticks >= (self.nextFollowProbe or 0) then
                self.nextFollowProbe = ticks + 15
                local player = self.companionTarget
                local observed, visible = pcall(function()
                    return player ~= nil and self.character:CanSee(player) == true
                end)
                if observed and visible and not nativeTraversalBusy(player) then
                    local ok, anchorSquare = pcall(function() return player:getCurrentSquare() end)
                    local current = self.character:getCurrentSquare()
                    if ok and Controller.shouldWakeSettledFollower(
                        current, anchorSquare,
                        self.settledFollowAnchorX,
                        self.settledFollowAnchorY,
                        self.settledFollowAnchorZ) then
                        self.state = "IDLE"
                        self.nextThink = ticks
                        return
                    end
                end
            end
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
            if self:updateSharedMeal(ticks) then return end
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
                self:releaseBaseTaskSupplyTransfer()
                self.state = "IDLE"
                self.activeDecision = nil
                self.nextThink = ticks + THINK_MIN_TICKS
                return
            end
            if hasPendingTimedActions(self.character) then
                return
            end
            local transfer = self.baseTaskSupplyTransfer
            local received = self:baseTaskSupplyReceived(transfer)
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
            -- Lease retirement credits this verified receipt before resumption.
            self:beginBaseTaskSupplyOrWork(ticks)
            return
        end

        if self.state == "AID_ACTION" then
            if hasPendingTimedActions(self.character) then
                return
            end
            local helped = KnoxMedicalActions.verifyAid(self.pendingAid)
            self:releaseAid()
            self.nextAidAt = ticks + AID_RETRY_TICKS
            self:diag("medical", helped and "aid_completed" or "aid_no_effect", nil)
            if helped then
                KnoxActivityFeed.speak(self.character, "That should hold for now.")
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
            -- Danger arbitration above may request retreat, but target cleanup,
            -- retargeting and reload yield cannot cut native attack frames short.
            if not safeMethod(self.character, "isDead", false)
                and Controller.isNativeAttackBusy(self.character) then return end
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
                    self.failedThreats[replacement] = math.max(
                        self.failedThreats[replacement] or 0, ticks + THREAT_SCAN_TICKS)
                    if self:recoverFailedCombatRetarget(previous, ticks) then
                        print("[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " combat-retarget-recovered previous=" .. tostring(previous))
                        return
                    end
                    -- A refused attack can already have admitted an unarmed retreat.
                    -- Preserve that survival mode and any native failure retry delay.
                    if self.state == "IDLE" then
                        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
                    end
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " combat-retarget-failed previous=" .. tostring(previous)
                    )
                    return
                end
                local firearmState, firearmResult = KnoxFirearmSupport.currentCombatState(
                    self.character
                )
                self:speakDryFirearm(ticks, firearmState)
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
                            preparationTarget,
                            self:combatGroupPresent()
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
            if self:handleCombatBarrier(ticks) then return end
            local result = tostring(self.bridge:tickNpcCombat(self.id))
            if string.find(result, "COMBAT_FIREARM_REQUEST", 1, true) == 1 then
                -- A friendly in the corridor is a refusal, not a near miss. Stand
                -- down for this request and let the next scan try again; never hand
                -- the native hook a shot through a companion or the player.
                if self:friendlyBlockingShot(self.combatTarget) ~= nil then
                    self:speakNoClearShot(ticks)
                    self.nextThreatScan = ticks + COMBAT_RANGED_YIELD_DELAY_TICKS
                    print("[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " firearm-request-hold reason=friendly_in_line")
                    return
                end
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
                        preparationTarget,
                        self:combatGroupPresent()
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
                -- Native success includes observed damage, but can also represent
                -- an obstacle. Only a genuinely dead enemy is a combat victory.
                if self.combatTarget ~= nil
                    and safeMethod(self.combatTarget, "isDead", false) == true then
                    self:sampleCombatConfidence(true)
                    -- Its own kill, still at its feet: look at the body now, while
                    -- the corpse and its square are the ones this fight produced.
                    self:checkKilledBody(self.combatTarget, ticks)
                end
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
                self:diag("combat", "combat_failed", { reason = result })
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
                -- A failed approach or pursuit means the encounter never got into
                -- reach. Walk the survivor in through the ordinary movement owner
                -- instead of leaving it standing at range. An injury stall is the
                -- same failure at contact: chain-stunned, never swung, still in
                -- the bite zone. It takes the same walk-in (which clears the
                -- generic cooldown so the next scan can re-admit) rather than the
                -- unreachable-target blacklist below.
                if fallbackTarget ~= nil
                    and (string.find(result, "APPROACH", 1, true) ~= nil
                        or string.find(result, "PURSUIT", 1, true) ~= nil
                        or string.find(result, "INJURY_STALL", 1, true) ~= nil) then
                    if self:beginCombatPursuit(fallbackTarget, ticks, result) then
                        print(
                            "[KnoxSurvivors][Autonomy] id=" .. self.id
                                .. " combat-pursuit target=" .. tostring(fallbackTarget)
                        )
                    end
                end
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
                local anchor = self:resolvePlayerPartyAnchor(ticks)
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
                local prior = self.selfCareIntent
                local chaining = prior ~= nil and (prior.kind == "replace_bandage"
                    or (prior.kind == "disinfect" and prior.replacementItem ~= nil))
                local completed, detail
                if chaining then
                    local followup = KnoxSurvivorNeeds.replacementFollowup(self.character, prior)
                    self:releaseSelfCare()
                    if followup ~= nil then
                        local action, result, nextIntent = self:executeNeedAction(followup, ticks)
                        if action ~= nil and action ~= false then
                            self.selfCareIntent, self.activeDecision = nextIntent, followup.kind
                            return
                        end
                        detail = "dressing_followup:" .. tostring(result)
                    else detail = "dressing_followup_unavailable" end
                    completed = false
                else
                    completed, detail = KnoxSurvivorNeeds.verify(self.character, self.selfCareIntent)
                end
                if self:completeSharedMeal(ticks, completed, self.selfCareIntent) then return end
                -- A meal or bottle in a bag requires a native transfer first.
                -- Chain the real eat/drink action immediately after that transfer;
                -- otherwise the survivor reports hunger forever while carrying the
                -- food that the planner already fetched.
                if completed and self.selfCareIntent ~= nil
                    and self.selfCareIntent.kind == "prepare_supply" then
                    local intent = self.selfCareIntent
                    self:releaseSelfCare()
                    local followup = {
                        kind = intent.needKind,
                        state = KnoxSurvivorNeeds.snapshot(self.character),
                        item = intent.item,
                        bodyPart = intent.bodyPart,
                    }
                    local action, result, nextIntent = self:executeNeedAction(followup, ticks)
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
            if self.pendingRobbery ~= nil
                and ticks >= (tonumber(self.pendingRobbery.expiresAt) or 0) then
                self:completeRobbery(ticks)
            elseif not hasPendingTimedActions(self.character) then self:completeRobbery(ticks) end
            return
        end

        if MOVEMENT_STATES[self.state] == true or self.state == "NIGHT_SHELTER_MOVE" then
            return updateMovement(self, ticks)
        end

        if self.state == "LOOTING" then
            return updateLooting(self, ticks)
        end

        if self.state == "SEARCHING" then
            return updateSearching(self, ticks)
        end

        if self.state == "SLEEPING_RECOVERY" then
            if self.character:isAsleep() then
                -- Wake at the hour this sleep planned, the same hour the
                -- native player path sets. The engine's own wake runs only
                -- for a real player, so without this a resident sleeps past
                -- dawn and the next cycle finds it still asleep. The long
                -- timeout stays as the backstop for an unreadable clock.
                local nowHours = nil
                pcall(function()
                    nowHours = GameTime.getInstance():getTimeOfDay()
                end)
                local plannedWake = Controller.sleepWakeDue(
                    self.sleepStartedHours, self.sleepPlannedHours, nowHours
                )
                if not plannedWake
                    and ticks - self.recoveryStarted
                        < Controller.TUNING.SLEEP_RECOVERY_TIMEOUT_TICKS then
                    return
                end
                KnoxSurvivorNeeds.wakeForDanger(self.character)
                self.sleepPlannedHours, self.sleepStartedHours = nil, nil
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

        -- A member already committed to a slot keeps reaching it on the ticks
        -- between its thinks, so a leader that moves cannot leave it behind. The
        -- commit field and the slot arithmetic are the ones squadStep owns.
        if self.state == "IDLE" and self.activeDecision == "squad_formation"
            and ticks < (tonumber(self.formationCommitUntil) or 0)
            and self:squadStep(ticks) then
            return
        end

        if self.state == "IDLE" and ticks >= self.nextThink and not recoveryBusy then
            if hasPendingTimedActions(self.character) then return end
            -- Native movement can reject a route issued in the same update that
            -- forceGetUp releases a chair or bed. Let the body finish standing
            -- before an ordinary new job asks for movement. Danger was assessed
            -- above and can still interrupt immediately.
            if safeMethod(self.character, "isSitOnGround", false)
                or safeMethod(self.character, "isSittingOnFurniture", false) then
                self:leaveRecoveryPosture()
                self.nextThink = ticks + THINK_MIN_TICKS
                return
            end
            -- A party member takes its formation slot before any other idle
            -- choice, so a broken-off member re-forms on its next think.
            if self:squadStep(ticks) then return end
            if self:tryVerticalTraversal(ticks) then return end
            self:think(ticks)
        end
    end
end

return Updates
