-- Aiding survivor replaces a spent dressing on someone else: the removal half
-- hands the spent bandage back, the apply half covers the wound it leaves, and
-- plain bandaging still refuses a part that is not uncovered and bleeding.
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local oldBandage, oldQueue, oldComponent = ISApplyBandage, ISTimedActionQueue, ComponentType

local built = {}
local base = {}
function base:derive() return setmetatable({}, {__index=self}) end
function base.isValid() return true end
function base.complete() return true end
function base:new(character) return setmetatable({character=character},{__index=self}) end
ISApplyBandage = base
ISApplyBandage.new = function(self, character, otherPlayer, item, bodyPart, doIt)
 local action = setmetatable({character=character, otherPlayer=otherPlayer, item=item,
  bodyPart=bodyPart, doIt=doIt}, {__index=self})
 built[#built + 1] = action
 return action
end

local queue = {}
local added = {}
ISTimedActionQueue = {queues={}, add=function(action)
 added[#added + 1] = action
 ISTimedActionQueue.queues[action.character] = queue
 return queue
end}

local spent, healedLife, open = {injured=true, covered=true, life=0, alcohol=0},
 {injured=true, covered=true, life=40, alcohol=0}, {injured=true, covered=false, life=0, alcohol=0}
local function shape(part)
 part.HasInjury = function(self) return self.injured end
 part.bandaged = function(self) return self.covered end
 part.getBandageLife = function(self) return self.life end
 part.getAlcoholLevel = function(self) return self.alcohol end
 part.isInfectedWound = function() return false end
 part.bleeding = function(self) return self.bleeds == true end
end
shape(spent); shape(healedLife); shape(open)
local currentPart = spent
local parts = {size=function() return 1 end, get=function(_, i) if i == 0 then return currentPart end return nil end}

local contents = {}
local inventory
local function bandage()
 local item = {isFavorite=function() return false end, isBroken=function() return false end,
  isInfected=function() return false end, isCanBandage=function() return true end,
  getType=function() return "Bandage" end, getFullType=function() return "Base.Bandage" end,
  hasComponent=function() return false end,
  getContainer=function() return inventory end}
 contents[1] = item
 return item
end
inventory = {contains=function(_, item) return contents[1] == item end,
 getItems=function() return {size=function() return #contents end,
  get=function(_, i) return contents[i + 1] end} end}
local item = bandage()

local square = {getX=function() return 0 end, getY=function() return 0 end, getZ=function() return 0 end}
local function person()
 return {isDead=function() return false end, getCurrentSquare=function() return square end,
  getInventory=function() return inventory end, isEquipped=function() return false end,
  getBodyDamage=function() return {getBodyParts=function() return parts end} end}
end
local doctor, patient = person(), person()

-- 1. Another survivor's spent dressing is a real plan for this owner.
local plan = M.maintenancePlan(doctor, patient)
assert(plan and plan.kind == "replace_bandage" and plan.bodyPart == spent and plan.item == item,
 "spent dressing on another survivor yields a replace_bandage plan")

-- 2. The pair's halves: removal needs the spent dressing, apply needs it gone.
assert(M.aidAllowed(doctor, patient, item, spent, "replace_bandage", "remove"),
 "removal half accepts a spent dressing")
assert(not M.aidAllowed(doctor, patient, item, healedLife, "replace_bandage", "remove"),
 "removal half refuses a dressing still doing its job")
currentPart = open
assert(not M.aidAllowed(doctor, patient, item, open, "replace_bandage", "remove"),
 "removal half refuses an uncovered wound")
assert(M.aidAllowed(doctor, patient, item, open, "replace_bandage", "apply"),
 "apply half accepts the open wound removal leaves")
assert(not M.aidAllowed(doctor, patient, item, spent, "replace_bandage", "apply"),
 "apply half refuses a still-covered wound")
currentPart = spent

-- 3. The plain-bandage guard did not loosen.
currentPart = open
assert(not M.aidAllowed(doctor, patient, item, open, "bandage"),
 "plain bandaging still refuses a part that is uncovered but not bleeding")
open.bleeding = function(self) return self.bleeds == true end
open.bleeds = true
assert(M.aidAllowed(doctor, patient, item, open, "bandage"),
 "plain bandaging still accepts an uncovered bleeding wound")
open.bleeds = false
currentPart = spent

-- 4. The queue receives a removal then an apply, on the real path.
built, added = {}, {}
local result, reason = M.queueAidReplacement(doctor, patient, item, spent, nil)
assert(result ~= nil and reason == "queued", "replacement is admitted to the real action queue")
assert(#added == 2, "replacement queues exactly two actions, got " .. tostring(#added))
assert(added[1].doIt == false and added[1].item == nil and added[1].otherPlayer == patient,
 "first action removes the spent dressing from the patient")
assert(added[2].doIt == true and added[2].item == item and added[2].otherPlayer == patient,
 "second action applies the carried bandage to the patient")
assert(added[1].aidPhase == "remove" and added[2].aidPhase == "apply",
 "each half carries its own permission phase")

-- 5. Completion is verified from the wound, not from the queue.
local afterPart = {bandaged=function() return true end, getBandageLife=function() return 30 end}
local afterParts = {size=function() return 1 end, get=function() return afterPart end}
local completed = {action={knoxAidCompleted=true, knoxAidBandageLifeBefore=0}, kind="replace_bandage",
 item=item, source=inventory, recipient=patient, part=afterPart}
completed.recipient = {isDead=function() return false end,
 getBodyDamage=function() return {getBodyParts=function() return afterParts end} end}
inventory.contains = function() return false end
assert(M.verifyAid(completed), "a fresh dressing on the same part verifies")
afterPart.getBandageLife = function() return 0 end
assert(not M.verifyAid(completed), "an unchanged spent dressing cannot claim the pair succeeded")

ISApplyBandage, ISTimedActionQueue, ComponentType = oldBandage, oldQueue, oldComponent
print("Aided dressing PASS plan=replace_bandage pair=remove+apply plainBandageStrict=true")
