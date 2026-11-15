require "TimedActions/ISApplyBandage"
require "TimedActions/ISSplint"
require "TimedActions/ISStitch"

require "TimedActions/ISDisinfect"
require "TimedActions/ISTimedActionQueue"

local MedicalActions = rawget(_G, "KnoxMedicalActions") or {}
_G.KnoxMedicalActions = MedicalActions

local function admitBandage(character, action, refusal)
    -- add may refuse, or begin may complete immediately. Registered returned
    -- queue identity proves admission without assuming treatment completion.
    local queue = ISTimedActionQueue.add(action)
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then
        return nil, refusal
    end
    return action, "queued"
end

local KnoxNpcApplyBandage = ISApplyBandage:derive("KnoxNpcApplyBandage")

function KnoxNpcApplyBandage:isValid()
    return self.item ~= nil
        and self.character:getInventory():contains(self.item)
        and self.bodyPart:HasInjury()
        and not self.bodyPart:bandaged()
end

function KnoxNpcApplyBandage:waitToStart()
    return false
end

function KnoxNpcApplyBandage:update()
    if self.item ~= nil then
        self.item:setJobDelta(self:getJobDelta())
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function KnoxNpcApplyBandage:start()
    ISApplyBandage.start(self)
    self.knoxBandageAnimationRequested = true
end

function KnoxNpcApplyBandage:stop()
    self:stopSound()
    if self.item ~= nil then
        self.item:setJobDelta(0.0)
    end
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.stop(self)
end

function KnoxNpcApplyBandage:complete()
    return ISApplyBandage.complete(self)
end

function KnoxNpcApplyBandage:perform()
    self:stopSound()
    if self.item ~= nil then
        self.item:setJobDelta(0.0)
    end
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.perform(self)
end

function KnoxNpcApplyBandage:new(character, item, bodyPart)
    return ISApplyBandage.new(self, character, character, item, bodyPart, true)
end

function MedicalActions.queueBandage(character, item, bodyPart, admit)
    if character == nil or item == nil or bodyPart == nil then
        return nil, "missing_treatment_input"
    end
    local action = KnoxNpcApplyBandage:new(character, item, bodyPart)
    return (admit or admitBandage)(character, action, "bandage_queue_refused")
end

local KnoxNpcRemoveBandage = ISApplyBandage:derive("KnoxNpcRemoveBandage")
function KnoxNpcRemoveBandage:isValid()
    return self.bodyPart ~= nil and self.bodyPart:bandaged()
end
function KnoxNpcRemoveBandage:waitToStart() return false end
function KnoxNpcRemoveBandage:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end
function KnoxNpcRemoveBandage:stop()
    self:stopSound()
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.stop(self)
end
function KnoxNpcRemoveBandage:perform()
    self:stopSound()
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.perform(self)
end
function MedicalActions.queueBandageRemoval(character, bodyPart, admit)
    if character == nil or bodyPart == nil then return nil, "missing_treatment_input" end
    local action = ISApplyBandage.new(KnoxNpcRemoveBandage, character, character, nil, bodyPart, false)
    return (admit or admitBandage)(character, action, "removal_queue_refused")
end

function MedicalActions.cleanBandageUsable(doctor, item)
    local ok, valid = pcall(function()
        return doctor ~= nil and item ~= nil and item:isCanBandage()
            and not item:isBroken() and not item:isFavorite() and not item:isInfected()
            and not doctor:isEquipped(item) and not string.find(item:getType(), "Dirty", 1, true)
            and doctor:getInventory():contains(item) and item:getContainer() == doctor:getInventory()
    end)
    return ok and valid == true
end

-- The installed Base.Splint is the only splint the game ships; a modded splint
-- has to claim the same full type rather than inventing a second reader.
local function splintCarriedUsable(doctor, item)
    local ok, usable = pcall(function()
        return doctor ~= nil and item ~= nil and item:getFullType() == "Base.Splint"
            and not item:isBroken() and not item:isFavorite() and not doctor:isEquipped(item)
    end)
    return ok and usable == true
end

function MedicalActions.splintUsable(doctor, item)
    local ok, usable = pcall(function()
        return splintCarriedUsable(doctor, item)
            and doctor:getInventory():contains(item)
            and item:getContainer() == doctor:getInventory()
    end)
    return ok and usable == true
end

-- Match installed ISHealthPanel.HSplint: a head/torso cast is never a
-- treatment. Diagnosis still reads those injuries; this gates splints only.
function MedicalActions.splintPartAllowed(part)
    local ok,allowed=pcall(function()
        if part==nil or BodyPartType==nil then return false end
        local kind=part:getType()
        return kind~=nil and BodyPartType.Head~=nil and BodyPartType.Torso_Upper~=nil
            and BodyPartType.Torso_Lower~=nil and kind~=BodyPartType.Head
            and kind~=BodyPartType.Torso_Upper and kind~=BodyPartType.Torso_Lower
            and part:HasInjury() and not part:stitched()
            and part:getFractureTime()>0 and part:getSplintFactor()<=0
    end)
    return ok and allowed==true
end

-- Only supplies held directly by the treating survivor can be handed to these
-- native actions. The game health panel uses the same alcohol strength/amount.
function MedicalActions.disinfectantUsable(item)
    local ok, usable = pcall(function()
        if item == nil or item:isFavorite() or item:isBroken() then return false end
        if item:hasComponent(ComponentType.FluidContainer) then
            local fluid = item:getFluidContainer()
            local amount = fluid:getAmount()
            return amount > 0.15 and fluid:getProperties():getAlcohol() / amount + 0.001 >= 0.4
        end
        return item:IsDrainable() and item:getAlcoholPower() == 4.0
            and item:getCurrentUsesFloat() > 0
    end)
    return ok and usable == true
end

-- A self-treating survivor may bring a bagged disinfectant to hand first;
-- companion aid stays direct-only because the native action needs the item in
-- the doctor's own inventory.
local function findDisinfectant(container, doctor, bagged)
    if container == nil then return nil end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if not doctor:isEquipped(item) and MedicalActions.disinfectantUsable(item) then
            return item
        end
    end
    if bagged ~= true then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:IsInventoryContainer() then
            local nested = findDisinfectant(item:getInventory(), doctor, true)
            if nested ~= nil then return nested end
        end
    end
    return nil
end

-- Self-treatment may bring a bagged splint to hand first; companion aid
-- stays direct-only because the native splint action needs the item in the
-- doctor's own inventory.
local function findSplint(container, doctor, bagged)
    if container == nil then return nil end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if splintCarriedUsable(doctor, item) then return item end
    end
    if bagged ~= true then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:IsInventoryContainer() then
            local nested = findSplint(item:getInventory(), doctor, true)
            if nested ~= nil then return nested end
        end
    end
    return nil
end

function MedicalActions.maintenancePlan(doctor, patient, preferredPart)
    local ok, plan = pcall(function()
        if doctor == nil or patient == nil then return nil end
        local parts, inventory = patient:getBodyDamage():getBodyParts(), doctor:getInventory()
        local exposed, infected, spent, healed, fractured = nil, false, nil, nil, nil
        for index = 0, parts:size() - 1 do
            local part = parts:get(index)
            if doctor == patient and part:bandaged() and not part:HasInjury() then
                healed = healed or part
            end
            if part:HasInjury() and part:isInfectedWound() then infected = true end
            if (preferredPart == nil or part == preferredPart)
                and part:HasInjury() and not part:bandaged() and part:getAlcoholLevel() <= 0 then
                exposed = exposed or part
            end
            if part:HasInjury() and part:bandaged() and part:getBandageLife() <= 0 then
                spent = spent or part
            end
            if MedicalActions.splintPartAllowed(part) then
                fractured = fractured or part
            end
        end
        if healed ~= nil and preferredPart == nil then
            return { kind = "remove_healed_bandage", bodyPart = healed }
        end
        local items = inventory:getItems()
        if exposed ~= nil then
            local item = findDisinfectant(inventory, doctor, doctor == patient)
            if item ~= nil then
                return { kind = "disinfect", item = item, bodyPart = exposed }
            end
        end
        -- Antibiotics are eaten by the patient, never administered to someone
        -- else with an invented action. Ordinary infected wounds only.
        if doctor == patient and infected and patient:getReduceInfectionPower() <= 0 then
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                if item:getFullType() == "Base.Antibiotics" and not item:isFavorite()
                    and not item:isBroken() and not doctor:isEquipped(item) then
                    return { kind = "antibiotic", item = item }
                end
            end
        end
        if doctor == patient then
            local uncovered
            for index = 0, parts:size() - 1 do
                local part = parts:get(index)
                if part:HasInjury() and not part:bandaged() then uncovered = part; break end
            end
            if spent ~= nil or uncovered ~= nil then
                for index = 0, items:size() - 1 do
                    local item = items:get(index)
                    if MedicalActions.cleanBandageUsable(doctor, item) then
                        return { kind = uncovered ~= nil and "bandage" or "replace_bandage",
                            item = item, bodyPart = uncovered or spent }
                    end
                end
            end
        end
        -- Someone else's spent dressing is changed by this same owner: remove
        -- it, then cover the wound it leaves. Never a bare second layer.
        if doctor ~= patient and spent ~= nil then
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                if MedicalActions.cleanBandageUsable(doctor, item) then
                    return { kind = "replace_bandage", item = item, bodyPart = spent }
                end
            end
        end
        -- An unsplinted fracture is the same kind of plan: the engine owns the
        -- fracture and the splint item, so this only points at what is carried.
        if fractured ~= nil then
            local item = findSplint(inventory, doctor, doctor == patient)
            if item ~= nil then
                return { kind = "splint", item = item, bodyPart = fractured }
            end
        end
        return nil
    end)
    if ok and plan ~= nil then return plan end
    return nil, "no_supported_maintenance"
end

function MedicalActions.queueDisinfect(character, item, bodyPart, admit)
    if character == nil or item == nil or bodyPart == nil then return nil, "missing_treatment_input" end
    local action = ISDisinfect:new(character, character, item, bodyPart)
    action.item = item -- shared need-action ownership guard; native uses alcohol
    return (admit or admitBandage)(character, action, "disinfect_queue_refused")
end

-- Survivor-to-survivor first aid: the same native bandage action with a
-- distinct doctor and patient. The engine owns approach validation,
-- animation, and bandage consumption; Lua only lines up a nearby bleeding
-- ally, a carried bandage, and adjacency. Constructor shape mirrors the
-- proven self-bandage path with only the patient swapped in.
local KnoxNpcAidBandage = ISApplyBandage:derive("KnoxNpcAidBandage")

function KnoxNpcAidBandage:isValid()
    local ok, valid = pcall(function()
        return self.patient == self.otherPlayer
            and MedicalActions.aidAllowed(self.character, self.patient, self.item, self.bodyPart,
                self.aidKind or "bandage", self.aidPhase)
            and (self.knoxAidGuard == nil or self.knoxAidGuard(self, self.item) == true)
            and ISApplyBandage.isValid(self) == true
    end)
    return ok and valid == true
end

function KnoxNpcAidBandage:waitToStart()
    return false
end

function KnoxNpcAidBandage:complete()
    -- Validity at queue start is not permission to treat later. Native complete
    -- alone changes the body and consumes the exact real bandage.
    if not self:isValid() then return false end
    local completed = ISApplyBandage.complete(self)
    self.knoxAidCompleted = completed == true
    return completed
end

function KnoxNpcAidBandage:new(doctor, patient, item, bodyPart)
    local action = ISApplyBandage.new(self, doctor, patient, item, bodyPart, true)
    action.patient = patient
    return action
end

function MedicalActions.findBandageItem(doctor, itemAvailable)
    if doctor == nil or doctor.getInventory == nil then
        return nil
    end
    local inventory = doctor:getInventory()
    if inventory == nil or inventory.getItems == nil then
        return nil
    end
    local items = inventory:getItems()
    local best, bestClean = nil, false
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil and item.isCanBandage ~= nil then
            local ok, usable = pcall(function()
                return item:isCanBandage() and not item:isBroken()
                    and not item:isFavorite() and not doctor:isEquipped(item)
                    and (itemAvailable == nil or itemAvailable(item) == true)
            end)
            if ok and usable then
                local clean = MedicalActions.cleanBandageUsable(doctor, item)
                if best == nil or (clean and not bestClean) then best, bestClean = item, clean end
            end
        end
    end
    return best
end

function MedicalActions.aidAllowed(doctor, patient, item, bodyPart, kind, phase)
    local ok, allowed = pcall(function()
        if doctor == nil or patient == nil or doctor == patient or item == nil or bodyPart == nil
            or doctor:isDead() ~= false or patient:isDead() ~= false
            or (kind ~= "disinfect" and kind ~= "splint" and not item:isCanBandage())
            or item:isBroken() or item:isFavorite()
            or doctor:isEquipped(item)
            or not doctor:getInventory():contains(item)
            or item:getContainer() ~= doctor:getInventory() then return false end
        local a, b = doctor:getCurrentSquare(), patient:getCurrentSquare()
        if a == nil or b == nil or a:getZ() ~= b:getZ() then return false end
        local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
        if dx * dx + dy * dy > 2 then return false end
        local parts = patient:getBodyDamage():getBodyParts()
        for index = 0, parts:size() - 1 do
            local part = parts:get(index)
            if part == bodyPart then
                if kind == "disinfect" then
                    return part:HasInjury() and not part:bandaged() and part:getAlcoholLevel() <= 0
                        and MedicalActions.disinfectantUsable(item)
                end
                if kind == "replace_bandage" then
                    -- A pair, never a bare re-cover: the removal half needs a
                    -- spent dressing, the apply half the open wound it leaves.
                    if phase == "remove" then
                        return part:HasInjury() and part:bandaged() and part:getBandageLife() <= 0
                    end
                    return part:HasInjury() and not part:bandaged()
                end
                if kind == "splint" then
                    -- The engine reports both the break and the existing splint.
                    return MedicalActions.splintPartAllowed(part)
                        and MedicalActions.splintUsable(doctor, item)
                end
                -- Plain bandaging stays strict: uncovered and still bleeding.
                return part:HasInjury() and part:bleeding() and not part:bandaged()
            end
        end
        return false
    end)
    return ok and allowed == true
end

function MedicalActions.verifyAid(plan)
    local ok, received = pcall(function()
        if plan == nil or plan.action == nil or plan.action.knoxAidCompleted ~= true
            or plan.source == nil or plan.item == nil
            or plan.recipient == nil or plan.recipient:isDead() ~= false then return false end
        if plan.kind ~= "disinfect" and plan.source:contains(plan.item) then return false end
        local parts = plan.recipient:getBodyDamage():getBodyParts()
        for index = 0, parts:size() - 1 do
            local part = parts:get(index)
            if part == plan.part then
                if plan.kind == "disinfect" then
                    return part:getAlcoholLevel() > plan.action.knoxAidAlcoholBefore
                        and MedicalActions.treatmentAmount(plan.item) < plan.action.knoxAidSupplyBefore
                end
                if plan.kind == "replace_bandage" then
                    return part:bandaged()
                        and part:getBandageLife() > (plan.action.knoxAidBandageLifeBefore or 0)
                end
                if plan.kind == "splint" then
                    return part:getSplintFactor() > (plan.action.knoxAidSplintBefore or 0)
                end
                return part:bandaged() or not part:bleeding()
            end
        end
        return false
    end)
    return ok and received == true
end

function MedicalActions.treatmentAmount(item)
    if item:hasComponent(ComponentType.FluidContainer) then return item:getFluidContainer():getAmount() end
    return item:getCurrentUsesFloat()
end

function MedicalActions.queueAidDisinfect(doctor, patient, item, bodyPart, guard)
    if not MedicalActions.aidAllowed(doctor, patient, item, bodyPart, "disinfect") then return nil, "aid_not_allowed" end
    local action = ISDisinfect:new(doctor, patient, item, bodyPart)
    action.item = item
    action.knoxAidAlcoholBefore = bodyPart:getAlcoholLevel()
    action.knoxAidSupplyBefore = MedicalActions.treatmentAmount(item)
    local valid, complete = action.isValid, action.complete
    action.isValid = function(candidate)
        return MedicalActions.aidAllowed(doctor, patient, item, bodyPart, "disinfect")
            and (guard == nil or guard(candidate, item) == true) and valid(candidate) == true
    end
    action.complete = function(candidate)
        if not candidate:isValid() then return false end
        local received = complete(candidate)
        candidate.knoxAidCompleted = received == true
        return received
    end
    return admitBandage(doctor, action, "aid_disinfect_queue_refused")
end

function MedicalActions.queueAidBandage(doctor, patient, item, bodyPart, guard)
    if doctor == nil or patient == nil or item == nil or bodyPart == nil then
        return nil, "missing_aid_input"
    end
    if doctor == patient then
        return MedicalActions.queueBandage(doctor, item, bodyPart)
    end
    local action = nil
    local ok, result = pcall(function()
        return KnoxNpcAidBandage:new(doctor, patient, item, bodyPart)
    end)
    if not ok or result == nil then
        return nil, "aid_action_unavailable"
    end
    action = result
    action.knoxAidGuard = guard
    return admitBandage(doctor, action, "aid_queue_refused")
end

-- Survivor-to-survivor dressing replacement. The installed ISApplyBandage
-- removes when item is nil and doIt is false, handing the spent bandage back
-- to the treater, and applies when an item is passed. Both halves queue in
-- order on the real health panel path and each re-checks permission.
local KnoxNpcAidBandageRemoval = ISApplyBandage:derive("KnoxNpcAidBandageRemoval")

function KnoxNpcAidBandageRemoval:isValid()
    local ok, valid = pcall(function()
        return self.patient == self.otherPlayer
            and MedicalActions.aidAllowed(self.character, self.patient, self.aidItem, self.bodyPart,
                "replace_bandage", "remove")
            and (self.knoxAidGuard == nil or self.knoxAidGuard(self, self.aidItem) == true)
            and ISApplyBandage.isValid(self) == true
    end)
    return ok and valid == true
end

function KnoxNpcAidBandageRemoval:waitToStart()
    return false
end

function KnoxNpcAidBandageRemoval:complete()
    if not self:isValid() then return false end
    local completed = ISApplyBandage.complete(self)
    self.knoxAidRemoved = completed == true
    return completed
end

function KnoxNpcAidBandageRemoval:new(doctor, patient, item, bodyPart)
    local action = ISApplyBandage.new(self, doctor, patient, nil, bodyPart, false)
    action.patient = patient
    action.aidItem = item
    action.aidPhase = "remove"
    action.knoxAidBandageLifeBefore = bodyPart:getBandageLife()
    return action
end

function MedicalActions.queueAidReplacement(doctor, patient, item, bodyPart, guard)
    if doctor == nil or patient == nil or item == nil or bodyPart == nil then
        return nil, "missing_aid_input"
    end
    if doctor == patient then return nil, "not_aid" end
    if not MedicalActions.aidAllowed(doctor, patient, item, bodyPart, "replace_bandage", "remove") then
        return nil, "aid_not_allowed"
    end
    local removal = KnoxNpcAidBandageRemoval:new(doctor, patient, item, bodyPart)
    removal.knoxAidGuard = guard
    local queue = ISTimedActionQueue.add(removal)
    if queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[doctor] then
        return nil, "replacement_queue_refused"
    end
    local apply = KnoxNpcAidBandage:new(doctor, patient, item, bodyPart)
    apply.aidKind = "replace_bandage"
    apply.aidPhase = "apply"
    apply.knoxAidBandageLifeBefore = bodyPart:getBandageLife()
    apply.knoxAidGuard = guard
    ISTimedActionQueue.add(apply)
    return apply, "queued"
end

-- Aiding survivor splints another survivor's fracture with the installed
-- ISSplint action: the engine removes the carried Base.Splint and sets the
-- real splint factor, so this only lines up patient, item and permission.
local KnoxNpcAidSplint = ISSplint:derive("KnoxNpcAidSplint")

function KnoxNpcAidSplint:isValid()
    local ok, valid = pcall(function()
        return self.patient == self.otherPlayer
            and MedicalActions.aidAllowed(self.character, self.patient, self.plank, self.bodyPart,
                "splint")
            and (self.knoxAidGuard == nil or self.knoxAidGuard(self, self.plank) == true)
            and ISSplint.isValid(self) == true
    end)
    return ok and valid == true
end

function KnoxNpcAidSplint:waitToStart()
    return false
end

function KnoxNpcAidSplint:complete()
    if not self:isValid() then return false end
    local completed = ISSplint.complete(self)
    self.knoxAidCompleted = completed == true
    return completed
end

function KnoxNpcAidSplint:new(doctor, patient, item, bodyPart)
    local action = ISSplint.new(self, doctor, patient, nil, item, bodyPart, true)
    action.patient = patient
    action.knoxAidSplintBefore = bodyPart:getSplintFactor()
    return action
end

-- Self-splinting is the same installed action with the survivor as both
-- sides: ISSplint:waitToStart returns false and ISSplint:start plays the
-- bandage animation when character == otherPlayer
-- (pzHome/media/lua/shared/TimedActions/ISSplint.lua:22-24, 42-48), so this
-- only reads the engine's own fracture state and the carried Base.Splint.
function MedicalActions.selfSplintAllowed(character, item, bodyPart)
    local ok, allowed = pcall(function()
        return character ~= nil and item ~= nil and bodyPart ~= nil
            and MedicalActions.splintUsable(character, item)
            and MedicalActions.splintPartAllowed(bodyPart)
    end)
    return ok and allowed == true
end

local KnoxNpcSelfSplint = ISSplint:derive("KnoxNpcSelfSplint")

function KnoxNpcSelfSplint:isValid()
    local ok, valid = pcall(function()
        return self.character == self.otherPlayer
            and MedicalActions.selfSplintAllowed(self.character, self.plank, self.bodyPart)
            and (self.knoxSelfGuard == nil
                or self.knoxSelfGuard(self, self.plank) == true)
            and ISSplint.isValid(self) == true
    end)
    return ok and valid == true
end

function KnoxNpcSelfSplint:waitToStart()
    return false
end

function KnoxNpcSelfSplint:complete()
    if not self:isValid() then return false end
    local completed = ISSplint.complete(self)
    self.knoxSelfSplintCompleted = completed == true
    return completed
end

function KnoxNpcSelfSplint:new(character, item, bodyPart)
    local action = ISSplint.new(self, character, character, nil, item, bodyPart, true)
    action.knoxSelfSplintBefore = bodyPart:getSplintFactor()
    return action
end

function MedicalActions.queueSelfSplint(character, item, bodyPart, guard)
    if character == nil or item == nil or bodyPart == nil then
        return nil, "missing_self_splint_input"
    end
    if not MedicalActions.selfSplintAllowed(character, item, bodyPart) then
        return nil, "self_splint_not_allowed"
    end
    local action = KnoxNpcSelfSplint:new(character, item, bodyPart)
    action.knoxSelfGuard = guard
    return admitBandage(character, action, "self_splint_queue_refused")
end
function MedicalActions.queueAidSplint(doctor, patient, item, bodyPart, guard)
    if doctor == nil or patient == nil or item == nil or bodyPart == nil then
        return nil, "missing_aid_input"
    end
    if doctor == patient then return nil, "not_aid" end
    if not MedicalActions.aidAllowed(doctor, patient, item, bodyPart, "splint") then
        return nil, "aid_not_allowed"
    end
    local action = KnoxNpcAidSplint:new(doctor, patient, item, bodyPart)
    action.knoxAidGuard = guard
    return admitBandage(doctor, action, "aid_splint_queue_refused")
end

function MedicalActions.mostUrgentInjury(character)
    if character == nil then
        return nil
    end
    local parts = character:getBodyDamage():getBodyParts()
    local fallback = nil
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part:HasInjury() then
            fallback = fallback or part
            if part:bleeding() and not part:bandaged() then
                return part
            end
        end
    end
    return fallback
end
-- TRIAGE
-- The same engine readings the maintenance plan already trusts, ordered by
-- what a person treats first. Decision only: no action, no store, and no
-- second plan - the treatment itself stays with maintenancePlan and the
-- queue that already owns it.
MedicalActions.TRIAGE_TIERS = { bleeding = 1, fracture = 2, infection = 3, wound = 4, dressing = 5 }
MedicalActions.TRIAGE_KINDS = { bleeding = true, fracture = true, infection = true,
    wound = true, dressing = true }
-- A person needs training to say what is wrong with someone else; below this
-- the survivor treats what they can see and says nothing clinical.
MedicalActions.TRIAGE_DOCTOR_LEVEL = 3

function MedicalActions.triageKind(patient)
    if patient == nil or patient.getBodyDamage == nil then return nil end
    local ok, kind, part = pcall(function()
        local parts = patient:getBodyDamage():getBodyParts()
        if parts == nil or parts.size == nil then return nil end
        local fallback, fracture, infection, dressing
        for index = 0, parts:size() - 1 do
            local part = parts:get(index)
            if part ~= nil then
                if part:HasInjury() and part:bleeding() and not part:bandaged() then
                    return "bleeding", part
                end
                if part.getFractureTime ~= nil and part.getSplintFactor ~= nil
                    and part:getFractureTime() > 0 and part:getSplintFactor() <= 0 then
                    fracture = fracture or part
                end
                if part:HasInjury() and part:isInfectedWound() then
                    infection = infection or part
                end
                if part:bandaged() and part.getBandageLife ~= nil
                    and part:getBandageLife() <= 0 then
                    dressing = dressing or part
                end
                if part:HasInjury() then fallback = fallback or part end
            end
        end
        if fracture ~= nil then return "fracture", fracture end
        if infection ~= nil then return "infection", infection end
        if fallback ~= nil then return "wound", fallback end
        if dressing ~= nil then return "dressing", dressing end
        return nil
    end)
    if ok and kind ~= nil then return kind, part end
    return nil
end

-- Stable: equal urgency keeps the order the scan found them in, so the same
-- team gives the same answer instead of reshuffling every pass.
function MedicalActions.triageOrder(casualties)
    local ranked = {}
    for index, patient in ipairs(type(casualties) == "table" and casualties or {}) do
        local kind, part = MedicalActions.triageKind(patient)
        if kind ~= nil then
            ranked[#ranked + 1] = { patient = patient, kind = kind, bodyPart = part,
                order = index }
        end
    end
    table.sort(ranked, function(left, right)
        local lt = MedicalActions.TRIAGE_TIERS[left.kind]
        local rt = MedicalActions.TRIAGE_TIERS[right.kind]
        if lt ~= rt then return lt < rt end
        return left.order < right.order
    end)
    return ranked
end

-- The briefing a trained survivor can actually give: nil without the
-- training or without a casualty, never a diagnosis of a healthy team.
function MedicalActions.triageBriefing(doctor, casualties)
    if doctor == nil or doctor.getPerkLevel == nil or Perks == nil then return nil end
    local ok, level = pcall(function() return doctor:getPerkLevel(Perks.Doctor) end)
    if not ok or (tonumber(level) or 0) < MedicalActions.TRIAGE_DOCTOR_LEVEL then
        return nil
    end
    local order = MedicalActions.triageOrder(casualties)
    if #order == 0 then return nil end
    local first = order[1]
    return { patient = first.patient, kind = first.kind, bodyPart = first.bodyPart,
        order = order, team = #order }
end

-- Vanilla player health actions bypass the NPC aid queue. Observe their real
-- completion here; never award standing when merely opening/queueing care.
do
    local function ownsPart(patient,part)
        local parts=patient:getBodyDamage():getBodyParts()
        for i=0,parts:size()-1 do
            if parts:get(i)==part then return true end
        end
        return false
    end
    local function quantity(item)
        if item.getFluidContainer then
            local f=item:getFluidContainer()
            if f then return f:getAmount() end
        end
        if item.getCurrentUsesFloat then return item:getCurrentUsesFloat() end
    end
    local function beforeCare(action,kind)
        local doctor,patient,part=action.character,action.otherPlayer,action.bodyPart
        if not doctor or not patient or doctor==patient or not part
            or getSpecificPlayer==nil or doctor:getPlayerNum()<0
            or getSpecificPlayer(doctor:getPlayerNum())~=doctor or patient:isDead()
            or (kind~="disinfect" and action.doIt~=true) or not part:HasInjury()
            or doctor:isDead() or not ownsPart(patient,part) then return nil end
        local runtime=rawget(_G,"KnoxSurvivorRuntime")
        local id=runtime and runtime.idForCharacter(patient)
        if not id or runtime.getCharacter(id)~=patient then return nil end
        if kind=="splint" and not MedicalActions.splintPartAllowed(part) then return nil end
        if kind=="stitch" and (part:stitched() or not part:isDeepWounded()
            or part:bandaged() or part:haveGlass()) then return nil end
        local item=action.item
        if kind=="disinfect" then item=action.alcohol
        elseif kind=="splint" then item=action.plank end
        local inventory=doctor:getInventory()
        if not item or not inventory:contains(item) then return nil end
        local costs={{item=item,amount=quantity(item)}}
        if kind=="splint" and action.rippedSheet~=nil then
            if action.rippedSheet==item or not inventory:contains(action.rippedSheet) then return nil end
            costs[#costs+1]={item=action.rippedSheet,amount=quantity(action.rippedSheet)}
        end
        return {doctor=doctor,patient=patient,id=id,part=part,item=item,inventory=inventory,
            costs=costs,covered=part:bandaged(),life=part:getBandageLife(),
            alcohol=part:getAlcoholLevel(),kind=kind}
    end
    local function afterCare(receipt)
        local r=receipt
        local runtime=rawget(_G,"KnoxSurvivorRuntime")
        if not runtime or runtime.getCharacter(r.id)~=r.patient or r.patient:isDead()
            or r.doctor:isDead() or getSpecificPlayer(r.doctor:getPlayerNum())~=r.doctor
            or not ownsPart(r.patient,r.part) then return false end
        for _,cost in ipairs(r.costs) do
            local after=quantity(cost.item)
            local spent=not r.inventory:contains(cost.item)
                or (type(cost.amount)=="number" and type(after)=="number" and after<cost.amount)
            if not spent then return false end
        end
        local effect
        if r.kind=="bandage" then
            effect=r.part:bandaged() and r.part:getBandageLife()>0
                and (not r.covered or r.part:getBandageLife()>r.life)
        elseif r.kind=="disinfect" then effect=r.part:getAlcoholLevel()>r.alcohol
        elseif r.kind=="splint" then effect=r.part:getSplintFactor()>0
        elseif r.kind=="stitch" then effect=r.part:stitched()==true end
        if not effect then return false end
        local service=rawget(_G,"KnoxCompanionService")
        if service and service.socialAct then return service.socialAct(r.doctor,r.id,"healed") end
        return false
    end
    function MedicalActions.installPlayerCareReceipts()
        for _,entry in ipairs({{ISApplyBandage,"bandage"},{ISDisinfect,"disinfect"},
            {ISSplint,"splint"},{ISStitch,"stitch"}}) do
            local class,kind=entry[1],entry[2]
            if class and class.complete and not class.knoxPlayerCareCompletion then
                local original=class.complete
                class.complete=function(self,...)
                    if self.knoxPlayerCareHandled then return self.knoxPlayerCareResult end
                    local readable,receipt=pcall(beforeCare,self,kind)
                    local result=original(self,...)
                    if result==true and readable and receipt then
                        -- Close before standing/speech callbacks can reenter.
                        self.knoxPlayerCareHandled,self.knoxPlayerCareResult=true,result
                        local ok,reason=pcall(afterCare,receipt)
                        if not ok then print("[KnoxSurvivors][Care] standing receipt failed: "..tostring(reason)) end
                    end
                    return result
                end
                class.knoxPlayerCareCompletion=true
            end
        end
    end
    MedicalActions.installPlayerCareReceipts()
end

return MedicalActions
