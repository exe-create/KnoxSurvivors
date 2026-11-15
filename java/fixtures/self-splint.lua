-- A fractured survivor with a carried Base.Splint splints themselves, through
-- the same installed action the player uses with the survivor as both sides.
-- The maintenance plan already offered the splint; the queue refused the self
-- case, which is what this proves is gone.
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local oldSplint, oldQueue = ISSplint, ISTimedActionQueue
local oldPartTypes=BodyPartType
BodyPartType={Head="head",Torso_Upper="upper",Torso_Lower="lower",ForeArm_L="arm"}

local base = {}
function base:derive() return setmetatable({}, {__index=self}) end
function base.isValid() return true end
local completedCalls=0
function base.complete() completedCalls=completedCalls+1;return true end
ISSplint = base
ISSplint.new = function(self, character, otherPlayer, rippedSheet, plank, bodyPart, doIt)
    return setmetatable({character=character, otherPlayer=otherPlayer,
        rippedSheet=rippedSheet, plank=plank, bodyPart=bodyPart, doIt=doIt},
        {__index=self})
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
for _, part in ipairs({broken, splinted, whole}) do
    part.getFractureTime = function(self) return self.fracture end
    part.getSplintFactor = function(self) return self.splint end
    part.kind=BodyPartType.ForeArm_L
    part.getType=function(self) return self.kind end
    part.HasInjury=function(self) return self.fracture>0 end
    part.stitched=function(self) return self.sewn==true end
    part.bandaged=function() return false end
    part.isInfectedWound=function() return false end
    part.getAlcoholLevel=function() return 0 end
    part.getBandageLife=function() return 0 end
end
local currentPart = broken
local parts = {size=function() return 1 end,
    get=function(_, i) if i == 0 then return currentPart end return nil end}

local inventory
local splint = {full="Base.Splint"}
function splint:getFullType() return self.full end
function splint:isBroken() return false end
function splint:isFavorite() return false end
function splint:getContainer() return inventory end
local contents = {[1] = splint}
inventory = {contains=function(_, item)
        for _, c in ipairs(contents) do if c == item then return true end end
        return false
    end,
    getItems=function()
        return {size=function() return #contents end,
            get=function(_, i) return contents[i + 1] end}
    end}
local square = {getX=function() return 0 end, getY=function() return 0 end,
    getZ=function() return 0 end}
local survivor = {isDead=function() return false end,
    getCurrentSquare=function() return square end,
    getInventory=function() return inventory end,
    isEquipped=function() return false end,
    getBodyDamage=function() return {getBodyParts=function() return parts end} end}

-- 1. The engine's own fracture state decides admission, with no second opinion.
assert(M.selfSplintAllowed(survivor, splint, broken), "a fractured limb with a carried splint is splintable")
assert(not M.selfSplintAllowed(survivor, splint, splinted),
    "a limb that already carries a splint is not")
currentPart = whole
assert(not M.selfSplintAllowed(survivor, splint, whole), "an unbroken limb is not")
currentPart = broken
assert(not M.selfSplintAllowed(survivor, nil, broken), "no splint item is not")

-- 2. The queue receives the installed action with the survivor on both sides.
local result, reason = M.queueSelfSplint(survivor, splint, broken, nil)
assert(result ~= nil and reason == "queued", "the self splint reaches the real queue")
assert(#added == 1, "one splint action is queued")
assert(added[1].otherPlayer == survivor and added[1].character == survivor,
    "the survivor is both sides of the native self-splint path")
assert(added[1].doIt == true and added[1].plank == splint and added[1].rippedSheet == nil,
    "the action applies the carried Base.Splint and invents no sheet")

-- 3. The refusal is the engine state, not the caller's mood.
local refused, why = M.queueSelfSplint(survivor, splint, splinted, nil)
assert(refused == nil and why == "self_splint_not_allowed", "an already splinted limb is refused by the same rule")

-- 4. The guard is the queue's own permission and can stop the action.
local guarded = M.queueSelfSplint(survivor, splint, broken, function() return false end)
assert(guarded ~= nil, "the action is still admitted so the guard can answer at validity")
assert(guarded:isValid() == false, "a refusing guard fails validity before completion")

for _,excluded in ipairs({BodyPartType.Head,BodyPartType.Torso_Upper,BodyPartType.Torso_Lower}) do
 broken.kind=excluded
 assert(not M.selfSplintAllowed(survivor,splint,broken), "native anatomy refuses self cast")
 assert(M.maintenancePlan(survivor,survivor)==nil,"excluded fracture never becomes a self splint plan")
 assert(M.queueSelfSplint(survivor,splint,broken)==nil,"excluded fracture never queues self cast")
 assert(result:complete()==false and completedCalls==0,"changed anatomy blocks queued native mutation")
end
broken.kind=nil
assert(not M.selfSplintAllowed(survivor,splint,broken),"unavailable type never assumes a limb")
broken.kind=BodyPartType.ForeArm_L;broken.sewn=true
assert(not M.selfSplintAllowed(survivor,splint,broken),"stitched part is not eligible for a cast")
broken.sewn=false
assert(M.selfSplintAllowed(survivor,splint,broken),"valid arm remains eligible after refusals")

ISSplint, ISTimedActionQueue = oldSplint, oldQueue
BodyPartType=oldPartTypes
print("Self splint PASS allowed=true alreadySplinted=false queued=ISSplint guard=validity")
