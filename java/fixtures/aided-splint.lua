-- Aiding survivor splints another survivor's fracture through the existing
-- medical plan, guard, queue and verifier; earlier guards keep their shape.
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local oldSplint, oldQueue = ISSplint, ISTimedActionQueue
local oldPartTypes=BodyPartType
BodyPartType={Head="head",Torso_Upper="upper",Torso_Lower="lower",ForeArm_L="arm"}

local built = {}
local base = {}
function base:derive() return setmetatable({}, {__index=self}) end
function base.isValid() return true end
local completedCalls=0
function base.complete() completedCalls=completedCalls+1;return true end
ISSplint = base
ISSplint.new = function(self, character, otherPlayer, rippedSheet, plank, bodyPart, doIt)
 local action = setmetatable({character=character, otherPlayer=otherPlayer, rippedSheet=rippedSheet,
  plank=plank, bodyPart=bodyPart, doIt=doIt}, {__index=self})
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

local broken = {fracture=100, splint=0}
local splinted = {fracture=100, splint=3}
local whole = {fracture=0, splint=0}
local currentPart = broken
local function shape(part)
 part.HasInjury = function(self) return self.fracture>0 end
 part.kind=BodyPartType.ForeArm_L
 part.getType=function(self) return self.kind end
 part.stitched=function(self) return self.sewn==true end
 part.isInfectedWound = function() return false end
 part.bandaged = function() return false end
 part.getAlcoholLevel = function() return 0 end
 part.getBandageLife = function() return 0 end
 part.getFractureTime = function(self) return self.fracture end
 part.getSplintFactor = function(self) return self.splint end
 part.bleeding = function() return false end
end
shape(broken); shape(splinted); shape(whole)
local parts = {size=function() return 1 end, get=function(_, i) if i == 0 then return currentPart end return nil end}

local inventory
local contents = {}
local splint = {full="Base.Splint"}
function splint:getFullType() return self.full end
function splint:getType() return "Splint" end
function splint:isBroken() return false end
function splint:isFavorite() return false end
function splint:isInfected() return false end
function splint:isCanBandage() return false end
function splint:getContainer() return inventory end
contents[1] = splint
local bandageItem = {full="Base.Bandage"}
function bandageItem:getFullType() return self.full end
function bandageItem:getType() return "Bandage" end
function bandageItem:isBroken() return false end
function bandageItem:isFavorite() return false end
function bandageItem:isInfected() return false end
function bandageItem:isCanBandage() return true end
function bandageItem:getContainer() return inventory end
inventory = {contains=function(_, item) for _, c in ipairs(contents) do if c == item then return true end end return false end,
 getItems=function() return {size=function() return #contents end, get=function(_, i) return contents[i + 1] end} end}

local square = {getX=function() return 0 end, getY=function() return 0 end, getZ=function() return 0 end}
local function person()
 return {isDead=function() return false end, getCurrentSquare=function() return square end,
  getInventory=function() return inventory end, isEquipped=function() return false end,
  getBodyDamage=function() return {getBodyParts=function() return parts end} end}
end
local doctor, patient = person(), person()

-- 1. A fractured limb with a carried splint is a real plan for this owner.
local plan = M.maintenancePlan(doctor, patient)
assert(plan and plan.kind == "splint" and plan.bodyPart == broken and plan.item == splint,
 "unsplinted fracture on another survivor yields a splint plan")

-- 2. The guard reads the engine's own fracture and splint state.
assert(M.aidAllowed(doctor, patient, splint, broken, "splint"),
 "splinting accepts a fractured limb with no splint")
assert(not M.aidAllowed(doctor, patient, splint, splinted, "splint"),
 "splinting refuses a limb that already carries a splint")
currentPart = whole
assert(not M.aidAllowed(doctor, patient, splint, whole, "splint"),
 "splinting refuses an unbroken limb")
currentPart = broken

-- 3. Earlier guards did not loosen: plain bandaging still needs bleeding.
assert(not M.aidAllowed(doctor, patient, bandageItem, broken, "bandage"),
 "plain bandaging still refuses an uncovered, unbleeding wound")

-- 4. The queue receives the real ISSplint construction for this patient.
built, added = {}, {}
local result, reason = M.queueAidSplint(doctor, patient, splint, broken, nil)
assert(result ~= nil and reason == "queued", "splint is admitted to the real action queue")
assert(#added == 1 and added[1].doIt == true, "one applying splint action is queued")
assert(added[1].otherPlayer == patient and added[1].plank == splint and added[1].rippedSheet == nil,
 "splint action targets the patient with the carried Base.Splint and no invented sheet")

-- 5. Completion is verified from the limb, not from the queue.
for _,excluded in ipairs({BodyPartType.Head,BodyPartType.Torso_Upper,BodyPartType.Torso_Lower}) do
 broken.kind=excluded
 assert(not M.aidAllowed(doctor,patient,splint,broken,"splint"),"native anatomy refuses aided cast")
 assert(M.maintenancePlan(doctor,patient)==nil,"excluded fracture never becomes an aid splint plan")
 assert(M.queueAidSplint(doctor,patient,splint,broken)==nil,"excluded fracture never queues aided cast")
 assert(result:complete()==false and completedCalls==0,"changed anatomy blocks queued aid mutation")
 assert(M.triageKind(patient)=="fracture","diagnosis still reports excluded fracture")
end
broken.kind=BodyPartType.ForeArm_L
local afterPart = {getSplintFactor=function() return 3 end}
local afterParts = {size=function() return 1 end, get=function() return afterPart end}
local completed = {action={knoxAidCompleted=true, knoxAidSplintBefore=0}, kind="splint",
 item=splint, source=inventory, part=afterPart}
completed.recipient = {isDead=function() return false end,
 getBodyDamage=function() return {getBodyParts=function() return afterParts end} end}
inventory.contains = function() return false end
assert(M.verifyAid(completed), "a real splint factor on the same limb verifies")
afterPart.getSplintFactor = function() return 0 end
assert(not M.verifyAid(completed), "an unchanged limb cannot claim the splint succeeded")

ISSplint, ISTimedActionQueue = oldSplint, oldQueue
BodyPartType=oldPartTypes
print("Aided splint PASS plan=splint guard=engineState queue=ISSplint verified=byFactor")
