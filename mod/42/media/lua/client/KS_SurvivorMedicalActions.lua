require "TimedActions/ISApplyBandage"
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

-- Survivor-to-survivor first aid: the same native bandage action with a
-- distinct doctor and patient. The engine owns approach validation,
-- animation, and bandage consumption; Lua only lines up a nearby bleeding
-- ally, a carried bandage, and adjacency. Constructor shape mirrors the
-- proven self-bandage path with only the patient swapped in.
local KnoxNpcAidBandage = ISApplyBandage:derive("KnoxNpcAidBandage")

function KnoxNpcAidBandage:isValid()
    local ok, valid = pcall(function()
        return self.patient == self.otherPlayer
            and MedicalActions.aidAllowed(self.character, self.patient, self.item, self.bodyPart)
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
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil and item.isCanBandage ~= nil then
            local ok, usable = pcall(function()
                return item:isCanBandage() and not item:isBroken()
                    and not item:isFavorite() and not doctor:isEquipped(item)
                    and (itemAvailable == nil or itemAvailable(item) == true)
            end)
            if ok and usable then
                return item
            end
        end
    end
    return nil
end

function MedicalActions.aidAllowed(doctor, patient, item, bodyPart)
    local ok, allowed = pcall(function()
        if doctor == nil or patient == nil or doctor == patient or item == nil or bodyPart == nil
            or doctor:isDead() ~= false or patient:isDead() ~= false
            or not item:isCanBandage() or item:isBroken() or item:isFavorite()
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
            or plan.source == nil or plan.item == nil or plan.source:contains(plan.item)
            or plan.recipient == nil or plan.recipient:isDead() ~= false then return false end
        local parts = plan.recipient:getBodyDamage():getBodyParts()
        for index = 0, parts:size() - 1 do
            local part = parts:get(index)
            if part == plan.part then return part:bandaged() or not part:bleeding() end
        end
        return false
    end)
    return ok and received == true
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

return MedicalActions
