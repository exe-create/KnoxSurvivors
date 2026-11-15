-- A short continuation of the existing base idle/rest/self-care owners.
-- Only the inviter holds a plan; the guest holds its controller reference.
local Meal = {}

function Meal.install(Controller, env)
    local function ownerOf(c)
        return c.sharedMeal ~= nil and c or c.sharedMealOwner
    end
    local function near(a, b)
        local here = a ~= nil and a:getCurrentSquare() or nil
        local there = b ~= nil and b:getCurrentSquare() or nil
        return here ~= nil and there ~= nil and here:getZ() == there:getZ()
            and env.distanceSquared(here, there) <= 16
            and env.safeMethod(a, "CanSee", false, b) == true
            and env.safeMethod(b, "CanSee", false, a) == true
    end
    local function seated(character)
        return env.safeMethod(character, "isSitOnGround", false)
            or env.safeMethod(character, "isSittingOnFurniture", false)
    end
    local function identity(c)
        local runtime = rawget(_G, "KnoxSurvivorRuntime")
        return runtime ~= nil and runtime.getController ~= nil
            and runtime.getController(c.id) == c and runtime.getCharacter(c.id) == c.character
            and runtime.canInteract(c.id) == true
    end
    local function recoveryBusy(a)
        if not Controller.isNativeRecoveryBusy(a) then return false end
        -- The shared recovery helper also recognizes "onground" inside the
        -- native sit-on-ground state. This continuation alone admits its real
        -- seated posture; a hit reaction, get-up or knockdown still wins.
        if not seated(a) or env.safeMethod(a, "isKnockedDown", true) then return true end
        local state = string.lower(tostring(env.safeMethod(a, "getCurrentStateName", "")))
        local action = string.lower(tostring(env.safeMethod(a, "getCurrentActionContextStateName", "")))
        return string.find(state .. action, "hitreaction", 1, true) ~= nil
            or string.find(state .. action, "getup", 1, true) ~= nil
    end
    local function safe(c, ticks, scanThreat)
        local a = c.character
        if not identity(c) or a == nil or a:getCurrentSquare() == nil or c.base == nil
            or c.baseId == nil or not KnoxBaseManager.containsSquare(c.base, a:getCurrentSquare())
            or c.baseTask ~= nil or c.combatTarget ~= nil or c.pendingThreatAwareness ~= nil
            or c.tradeAction ~= nil or c.playerConversation ~= nil or c.eventAssignment ~= nil
            or c.awayTeamId ~= nil or c.baseSupplyTrip == true or c.baseSupplyOrder ~= nil
            or c.companionOrder ~= nil or c.companionDirective ~= nil or c.groupLeaderId ~= nil
            or c.groupObjective ~= nil or env.safeMethod(a, "isDead", true)
            or env.safeMethod(a, "isAsleep", true) or env.safeMethod(a, "getVehicle", nil) ~= nil
            or env.nativeTraversalBusy(a) or recoveryBusy(a)
            or Controller.isNativeAttackBusy(a) or env.safeMethod(a, "isPlayerMoving", true)
            or (scanThreat or ticks >= (c.nextThreatScan or 0))
                and env.nearestThreat(c, ticks) ~= nil then return false end
        local duty = KnoxPersistence.getSurvivorDuty(c.id)
        if duty == nil or duty.mode ~= "base" or duty.baseId ~= c.baseId then return false end
        local assignment = KnoxBaseJobs.scheduleAssignment(c.id)
        if assignment == "sleep" or assignment == "work" or assignment == "guard"
            or assignment == "patrol" then return false end
        local need = KnoxSurvivorNeeds.decide(a, nil)
        if need ~= nil and need.kind ~= "roam" then return false end
        local state = KnoxSurvivorNeeds.snapshot(a)
        local stats, body = a:getStats(), a:getBodyDamage()
        return state.health >= 90 and state.bleedingParts == 0
            and state.fatigue < KnoxSurvivorNeeds.thresholds.fatigue
            and state.endurance > KnoxSurvivorNeeds.thresholds.lowEndurance
            and (state.pain == nil or state.pain < KnoxSurvivorNeeds.painBands.hurting)
            and body:getColdStrength() <= 0
            and stats:get(CharacterStat.SICKNESS) <= 0
            and stats:get(CharacterStat.FOOD_SICKNESS) <= 0
            and stats:get(CharacterStat.POISON) <= 0
    end
    local function food(c)
        return KnoxSurvivorNeeds.findBestFood(c.character, function(item)
            return c.reservations == nil or c.reservations.items == nil
                or c.reservations.items[item] == nil
        end)
    end
    local function entry(plan, c)
        return plan.first.controller == c and plan.first or plan.second.controller == c and plan.second or nil
    end
    local function linked(owner, plan)
        return not plan.closed and owner.sharedMeal == plan
            and plan.second.controller.sharedMealOwner == owner
    end
    local function valid(owner, plan, ticks, scanThreat)
        local first, second = plan.first.controller, plan.second.controller
        return linked(owner, plan) and ticks < plan.expiresAt
            and first.character == plan.first.character and second.character == plan.second.character
            and first.baseId == plan.baseId and second.baseId == plan.baseId
            and first.activeDecision == "base_shared_meal" and second.activeDecision == "base_shared_meal"
            and (first.state == "BASE_AMBIENT_REST" or first.state == "TIMED_ACTION")
            and (second.state == "BASE_AMBIENT_REST" or second.state == "TIMED_ACTION")
            and near(first.character, second.character)
            and safe(first, ticks, scanThreat) and safe(second, ticks, scanThreat)
    end

    function Controller:releaseSharedMeal(ticks)
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        if plan == nil or plan.closed then return false end
        -- Close before native cancellation: its callbacks may reenter this owner.
        plan.closed = true
        for _, e in ipairs({ plan.first, plan.second }) do
            local c = e.controller
            local owns = (c == owner and c.sharedMeal == plan) or c.sharedMealOwner == owner
            if owns then
                if c == owner then c.sharedMeal = nil else c.sharedMealOwner = nil end
                if e.care ~= nil then c:releaseSelfCare(e.care) end
                if c.character == e.character then
                    c:releaseTransferActions({ { action = e.seatAction } })
                    if e.seatAction ~= nil and c.pendingRest == e.rest then
                        -- Only the meal's posture is asked to stand. Another
                        -- owner's newer furniture reservation is never released.
                        if c.activeDecision == "base_shared_meal" then c:leaveRecoveryPosture() end
                    end
                end
                if e.rest ~= nil and c.pendingRest == e.rest then c:releaseRestSpot() end
                if c.activeDecision == "base_shared_meal" then
                    c.activeDecision, c.ambientRest = nil, nil
                    c.state, c.nextThink = "IDLE", (ticks or c.currentTicks or 0) + 180
                end
            end
        end
        return true
    end

    function Controller:canSharedMeal(ticks)
        if ownerOf(self) ~= nil or ticks < (self.nextSocialAt or 0)
            or self.pendingRest ~= nil or self.pendingSelfCare ~= nil
            or not self:canAmbientSocial(ticks) or not safe(self, ticks, true) then return false end
        return KnoxSurvivorNeeds.snapshot(self.character).hunger >= 0.30 and food(self) ~= nil
    end

    function Controller:trackSharedMealSeat(action)
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        local e = plan ~= nil and entry(plan, self) or nil
        if e == nil or plan.closed then return end
        e.seatAction = action
        -- A mixed queue may retain our current native action while another
        -- owner drains. Revoking this continuation must also revoke a seat
        -- that has not started yet, without clearing that other work.
        local function allowed()
            return linked(owner, plan) and self.character == e.character
                and self.activeDecision == "base_shared_meal"
        end
        local nativeValid = action.isValid
        action.isValid = function(candidate)
            return allowed() and nativeValid ~= nil and nativeValid(candidate)
        end
        for _, name in ipairs({ "waitToStart", "start" }) do
            local native = action[name]
            if native ~= nil then
                action[name] = function(candidate, ...)
                    if not allowed() then return false end
                    return native(candidate, ...)
                end
            end
        end
    end

    function Controller:sharedMealPostureReady()
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        return plan ~= nil and linked(owner, plan) and seated(self.character)
            and not recoveryBusy(self.character)
    end

    -- Giving food to a hungry resident is the same base-idle decision as the
    -- shared meal: one need read, one reserve check, the existing transfer
    -- action and one line. The giver never eats for the other survivor, and a
    -- refused transfer leaves nothing behind.
    function Controller:beginShareWithNeedy(ticks)
        if ticks < (self.nextShareAt or 0) or not safe(self, ticks, true) then return false end
        local runtime = KnoxSurvivorRuntime
        for _, id in ipairs(KnoxPersistence.getBaseResidentIds(self.baseId) or {}) do
            local c = runtime.getController(id)
            if c ~= nil and c ~= self and c.baseId == self.baseId
                and near(self.character, c.character)
                and env.safeMethod(c.character, "isDead", true) == false then
                -- Food first, then a spare bottle, then a dressing: one offer
                -- per check, each through the same transfer owner.
                local action = KnoxSurvivorNeeds.queueFoodShare(self.character, c.character,
                    self.id, ticks, 60)
                if action == nil then
                    action = KnoxSurvivorNeeds.queueWaterShare(self.character, c.character,
                        self.id, ticks, 60)
                end
                if action == nil then
                    action = KnoxSurvivorNeeds.queueMedicalShare(self.character, c.character,
                        self.id, ticks, 60)
                end
                if action ~= nil then
                    self.nextShareAt = ticks + 3600
                    return true
                end
            end
        end
        return false
    end

    function Controller:beginSharedMeal(ticks)
        if not self:canSharedMeal(ticks) then return false end
        local runtime = KnoxSurvivorRuntime
        local other
        for _, id in ipairs(KnoxPersistence.getBaseResidentIds(self.baseId) or {}) do
            local c = runtime.getController(id)
            if c ~= nil and c ~= self and c.baseId == self.baseId
                and near(self.character, c.character) and c:canSharedMeal(ticks) then other = c; break end
        end
        if other == nil then return false end
        local plan = { baseId = self.baseId, expiresAt = ticks + 1800,
            first = { controller = self, character = self.character, item = food(self) },
            second = { controller = other, character = other.character, item = food(other) } }
        self.sharedMeal, other.sharedMealOwner = plan, self
        for _, e in ipairs({ plan.first, plan.second }) do
            local c = e.controller
            c.activeDecision, c.ambientRest = "base_shared_meal", true
            c.state, c.nextSocialAt = "BASE_AMBIENT_REST", ticks + 3600
        end
        for _, e in ipairs({ plan.first, plan.second }) do
            local c = e.controller
            -- Recovery posture clears queues by design. Never let it acquire
            -- this meal unless both identities and the empty queue still hold.
            if not valid(self, plan, ticks) or env.hasPendingTimedActions(c.character) then
                self:releaseSharedMeal(ticks); return false
            end
            local spot = env.findBestRestSpot(c, false, function(square)
                return square == c.character:getCurrentSquare()
            end)
            if spot ~= nil and env.reserve(c.reservations, "restSpots", spot.object, c.id) then
                c.pendingRest = spot
            end
            e.rest = c.pendingRest
            local ok, action = pcall(c.startRecoveryPosture, c, ticks, c.pendingRest ~= nil, true)
            e.seatAction = action
            if not ok or action == nil or action == false or not linked(self, plan) then
                self:releaseSharedMeal(ticks)
                c:releaseTransferActions({ { action = e.seatAction } })
                return false
            end
            c.nextThink = plan.expiresAt
        end
        return true
    end

    function Controller:checkSharedMeal(ticks)
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        if plan == nil then return end
        local foreign = false
        for _, e in ipairs({ plan.first, plan.second }) do
            local c = e.controller
            local q = ISTimedActionQueue.queues ~= nil and ISTimedActionQueue.queues[e.character] or nil
            for _, action in ipairs(q ~= nil and q.queue or {}) do
                if action ~= e.seatAction and (e.care == nil or action ~= e.care.action
                    and action.knoxNeedGuard ~= e.care.guard) then foreign = true end
            end
            if c.pendingSelfCare ~= nil and c.pendingSelfCare ~= e.care then foreign = true end
        end
        if foreign or not valid(owner, plan, ticks) then owner:releaseSharedMeal(ticks) end
    end

    function Controller:updateSharedMeal(ticks)
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        if plan == nil then return false end
        if not valid(owner, plan, ticks) then owner:releaseSharedMeal(ticks); return true end
        local e = entry(plan, self)
        if e == nil then owner:releaseSharedMeal(ticks); return true end
        if env.hasPendingTimedActions(self.character) then return true end
        if not seated(self.character) then owner:releaseSharedMeal(ticks); return true end
        -- Both participants must physically sit before either starts consuming.
        for _, member in ipairs({ plan.first, plan.second }) do
            if not seated(member.character) or env.hasPendingTimedActions(member.character)
                and member.care == nil then return true end
        end
        if e.received then return true end
        if e.care ~= nil then return true end
        if not KnoxSurvivorNeeds.isSafeFood(e.item)
            or (self.reservations.items ~= nil and self.reservations.items[e.item] ~= nil) then
            owner:releaseSharedMeal(ticks); return true
        end
        local action, _, intent = self:executeNeedAction({ kind = "eat", item = e.item,
            state = KnoxSurvivorNeeds.snapshot(self.character), permission = function()
                return valid(owner, plan, self.currentTicks or ticks, true)
                    and seated(plan.first.character) and seated(plan.second.character)
            end }, ticks)
        e.care = self.pendingSelfCare
        if not linked(owner, plan) then
            local care = e.care
            if care ~= nil and action ~= nil and action ~= false and intent ~= nil
                and care.action == action and care.intent == intent then
                self:releaseSelfCare(care)
                if self.pendingSelfCare == nil and self.activeDecision == nil
                    and self.state == "TIMED_ACTION" then self.state = "IDLE" end
            end
            return true
        end
        if action == nil or action == false or intent == nil or intent.item ~= e.item
            or (intent.kind ~= "eat" and not (intent.kind == "prepare_supply" and intent.needKind == "eat"))
            or not linked(owner, plan) then
            owner:releaseSharedMeal(ticks); return true
        end
        e.intent = intent
        return true
    end

    -- Called by the existing TIMED_ACTION owner after Needs.verify, never by
    -- queue admission. A single person's real meal is still real if the pair
    -- breaks up, but it does not produce shared-meal speech.
    function Controller:completeSharedMeal(ticks, completed, intent)
        local owner = ownerOf(self)
        local plan = owner ~= nil and owner.sharedMeal or nil
        if plan == nil then return false end
        local e = entry(plan, self)
        if e ~= nil and ((e.received and e.intent == intent)
            or (e.preparedIntent ~= nil and e.preparedIntent == intent)) then return true end
        if not valid(owner, plan, ticks) or e == nil or e.intent ~= intent
            or not completed or intent == nil or intent.item ~= e.item or not seated(self.character) then
            owner:releaseSharedMeal(ticks); return true
        end
        if intent.kind == "prepare_supply" and intent.needKind == "eat" then
            if e.care == nil or self.pendingSelfCare ~= e.care
                or e.item:getContainer() ~= self.character:getInventory() then
                owner:releaseSharedMeal(ticks); return true
            end
            self:releaseSelfCare(e.care)
            if not linked(owner, plan) or self.character ~= e.character
                or self.activeDecision ~= "base_shared_meal" then return true end
            e.preparedIntent = intent
            e.care, e.intent = nil, nil
            self.state, self.nextThink = "BASE_AMBIENT_REST", plan.expiresAt
            return true
        end
        if intent.kind ~= "eat" then
            owner:releaseSharedMeal(ticks); return true
        end
        if e.received then return true end
        e.received = true
        if self.pendingSelfCare == e.care then self:releaseSelfCare(e.care) end
        self.state = "BASE_AMBIENT_REST"
        self.nextThink = plan.expiresAt
        if plan.first.received and plan.second.received then
            -- Final safe/proximity check and close before speech callbacks.
            if valid(owner, plan, ticks, true) then
                local a, b = plan.first, plan.second
                owner:releaseSharedMeal(ticks)
                if near(a.character, b.character) and safe(a.controller, ticks, true)
                    and safe(b.controller, ticks, true) then
                    env.sayDialogue(a.character, a.controller.id, "base_social", ticks, 1800)
                    if near(a.character, b.character) and safe(a.controller, ticks, true)
                        and safe(b.controller, ticks, true) then
                        env.sayDialogue(b.character, b.controller.id, "base_social", ticks, 1800)
                    end
                end
            else owner:releaseSharedMeal(ticks) end
        end
        return true
    end
end

return Meal
