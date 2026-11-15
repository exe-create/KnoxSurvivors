local N = assert(rawget(_G, "KnoxSurvivorNeeds"), "needs owner missing")
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local oldSnapshot, oldDisinfect, oldEat, oldQueue = N.snapshot, ISDisinfect, ISEatFoodAction, ISTimedActionQueue
local oldComponentType = ComponentType
local oldBandageNew = ISApplyBandage.new
local state = { bleedingParts = 0, thirst = 0, hunger = 0, endurance = 1, fatigue = 0 }
N.snapshot = function() return state end
local part = { injured = true, infected = false, covered = false, alcohol = 0, life = 0 }
function part:HasInjury() return self.injured end
function part:isInfectedWound() return self.infected end
function part:bandaged() return self.covered end
function part:getAlcoholLevel() return self.alcohol end
function part:getBandageLife() return self.life end
local otherPart = {injured=false, covered=false, alcohol=0}
function otherPart:HasInjury() return self.injured end
function otherPart:isInfectedWound() return false end
function otherPart:bandaged() return self.covered end
function otherPart:getAlcoholLevel() return self.alcohol end
function otherPart:getBandageLife() return 0 end
local parts = { size = function() return 2 end, get = function(_,i) if i==0 then return otherPart end return part end }
local contents = {}
local list = { size = function() return #contents end, get = function(_, i) return contents[i + 1] end }
local inventory = { getItems = function() return list end, contains = function(_, item)
    for _, candidate in ipairs(contents) do if candidate == item then return true end end
    return false
end }
local actor = { drug = 0 }
function actor:getBodyDamage() return { getBodyParts = function() return parts end } end
function actor:getInventory() return inventory end
function actor:isEquipped() return false end
function actor:getReduceInfectionPower() return self.drug end
local function item(kind)
    return { kind = kind, amount = 1, isFavorite = function() return false end,
        isBroken = function() return false end, IsInventoryContainer = function() return false end,
        getFullType = function(self) return self.kind end,
        getType = function(self) return self.kind end, getContainer = function() return inventory end,
        isCanBandage = function(self) return self.kind == "Bandage" end,
        isInfected = function() return false end,
        hasComponent = function(self) return self.kind == "disinfectant" end,
        getFluidContainer = function(self) return { getAmount = function() return self.amount end,
            getProperties = function() return { getAlcohol = function() return self.amount end } end } end,
        IsDrainable = function() return false end }
end
ComponentType = ComponentType or { FluidContainer = "fluid" }
local disinfectant, antibiotic = item("disinfectant"), item("Base.Antibiotics")
local bandage = item("Bandage")
local queue = { queue = {} }
ISTimedActionQueue = { queues = { [actor] = queue }, add = function(action)
    queue.queue = { action }
    return queue
end }
ISDisinfect = { new = function(_, character, patient, supply, wound)
    return { character = character, otherPlayer = patient, alcohol = supply, bodyPart = wound,
        isValid = function() return true end, complete = function()
            supply.amount = supply.amount - 0.15; wound.alcohol = 4; return true
        end }
end }
ISEatFoodAction = { new = function(_, character, supply)
    return { character = character, item = supply, isValid = function() return true end,
        complete = function() contents = {}; character.drug = 50; return true end }
end }
ISApplyBandage.new = function(_, character, patient, supply, wound, apply)
    return { character = character, otherPlayer = patient, item = supply, bodyPart = wound, doIt = apply,
        isValid = function() return true end, complete = function()
            if apply then
                for index, candidate in ipairs(contents) do
                    if candidate == supply then table.remove(contents, index); break end
                end
                wound.covered, wound.life = true, 5
            else wound.covered = false end
            return true
        end }
end
local ownership = { allowed = function() return true end }
contents = { disinfectant, antibiotic }
local decision = N.decide(actor, nil)
assert(decision.kind == "disinfect" and decision.bodyPart == part, "exposed wound selects real disinfectant")
local action, _, intent = N.execute(actor, decision, ownership)
assert(action and action:isValid(), "disinfect action admitted")
assert(action:complete() and N.verify(actor, intent), "disinfect receipt requires real supply and body change")
assert(N.decide(actor, nil).kind == "roam", "active wound alcohol prevents repeated use")

part.infected = true
local drugDecision = N.decide(actor, nil)
assert(drugDecision.kind == "antibiotic", "ordinary wound infection selects antibiotics")
local drugAction, _, drugIntent = N.execute(actor, drugDecision, { allowed = function() return true end })
assert(drugAction and drugAction:complete() and N.verify(actor, drugIntent), "antibiotic is consumed with native effect")
contents = { antibiotic }
assert(N.decide(actor, nil).kind == "roam", "active drug blocks another dose")
actor.drug, part.infected, part.covered, part.alcohol = 0, false, true, 0
assert(N.decide(actor, nil).kind == "roam", "covered healthy wound is not disinfected or medicated")
part.covered = false
contents = { disinfectant }
local cancelled = { allowed = function() return true end }
local pending, _, pendingIntent = N.execute(actor, N.decide(actor, nil), cancelled)
cancelled.cancelled = true
local amount = disinfectant.amount
assert(pending:complete() == false and disinfectant.amount == amount, "cancelled action cannot consume")
assert(not N.verify(actor, pendingIntent), "cancelled treatment has no receipt")
part.alcohol = 0
state.bleedingParts = 1
local oldUrgent, oldTreatment = M.mostUrgentInjury, KnoxMedicalSupplies.findTreatment
M.mostUrgentInjury = function() return part end
KnoxMedicalSupplies.findTreatment = function() return antibiotic end
assert(N.decide(actor, nil).kind == "bandage", "emergency bleeding outranks maintenance")
M.mostUrgentInjury, KnoxMedicalSupplies.findTreatment = oldUrgent, oldTreatment
state.bleedingParts = 0
part.covered, part.life, part.alcohol, part.infected = true, 3, 0, false
contents = { bandage, disinfectant }
assert(N.decide(actor, nil).kind == "roam", "serviceable dressing is kept")
part.life = 0
contents = { disinfectant }
assert(N.decide(actor, nil).kind == "roam", "old dressing remains when no clean replacement exists")
contents = { bandage, disinfectant }
local replacement = N.decide(actor, nil)
assert(replacement.kind == "replace_bandage", "spent dressing with clean replacement is selected")
local removalOwner = { allowed = function() return true end }
local removal, _, removalIntent = N.execute(actor, replacement, removalOwner)
assert(removal and part.covered, "removal is queued without changing the wound")
removalOwner.cancelled = true
assert(removal:complete() == false and part.covered, "cancelled removal retains old dressing")
removalOwner = { allowed = function() return true end }
removal, _, removalIntent = N.execute(actor, replacement, removalOwner)
assert(removal:complete() and not part.covered, "native removal opens the dressing")
assert(not N.verify(actor, removalIntent), "removal alone is not completed treatment")
otherPart.injured = true
local nextCare = N.replacementFollowup(actor, removalIntent)
assert(nextCare and nextCare.kind == "disinfect" and nextCare.bodyPart == part,
    "replacement cleans the just-uncovered wound even when another wound comes first")
local cleaning, _, cleaningIntent = N.execute(actor, nextCare, { allowed = function() return true end })
assert(cleaning and cleaning:complete() and N.verify(actor, cleaningIntent), "cleaning has a real receipt")
local applyDecision = N.replacementFollowup(actor, cleaningIntent)
assert(applyDecision and applyDecision.kind == "bandage" and applyDecision.item == bandage,
    "clean replacement remains the follow-up")
local apply, _, applyIntent = N.execute(actor, applyDecision, { allowed = function() return true end })
assert(apply and apply:complete() and N.verify(actor, applyIntent), "replacement receipt requires native apply")
assert(part.covered and part.life > 0 and otherPart.alcohol == 0,
    "the selected wound is cleaned and rebandaged without treating the other wound")
otherPart.injured = false

part.covered, part.life, part.alcohol = true, 0, 0
contents = { bandage }
removal, _, removalIntent = N.execute(actor, N.decide(actor, nil), { allowed = function() return true end })
contents = {}
assert(removal:complete() == false and part.covered, "missing replacement blocks removal")
contents = { bandage }
removal, _, removalIntent = N.execute(actor, N.decide(actor, nil), { allowed = function() return true end })
assert(removal:complete(), "second removal completes")
state.bleedingParts = 1
local urgent = N.replacementFollowup(actor, removalIntent)
assert(urgent and urgent.kind == "bandage", "bleeding outranks disinfection after removal")
state.bleedingParts = 0
part.alcohol = 4
assert(N.decide(actor, nil).kind == "bandage", "interrupted application remains eligible")
local applyOwner = { allowed = function() return true end }
local interrupted, _, interruptedIntent = N.execute(actor, N.decide(actor, nil), applyOwner)
applyOwner.cancelled = true
assert(interrupted:complete() == false and not part.covered, "cancelled application changes no wound")
assert(not N.verify(actor, interruptedIntent), "cancelled application has no success receipt")
assert(N.isMedicalCare("replace_bandage") and N.isMedicalCare("disinfect")
    and not N.isMedicalCare("roam"), "medical routing includes maintenance only")
-- The same native disinfection can treat a nearby player through the aid owner.
local square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
actor.getCurrentSquare=function() return square end;actor.isDead=function() return false end
local patient={getCurrentSquare=function() return square end,isDead=function() return false end,
 getBodyDamage=function() return {getBodyParts=function() return parts end} end}
part.covered,part.alcohol=false,0
contents={disinfectant};local permitted=true
local aid=M.queueAidDisinfect(actor,patient,disinfectant,part,function() return permitted end)
assert(aid and aid.otherPlayer==patient, "aid uses the distinct real patient in the native disinfection action")
local aidPlan={action=aid,item=disinfectant,source=inventory,recipient=patient,part=part,kind="disinfect"}
assert(not M.verifyAid(aidPlan), "queued disinfection is not a treatment receipt")
assert(aid:complete() and M.verifyAid(aidPlan), "aid receipt observes real alcohol gain and finite supply use")
part.alcohol=0
local stopped=M.queueAidDisinfect(actor,patient,disinfectant,part,function() return permitted end)
permitted=false
local before=disinfectant.amount
assert(stopped:complete()==false and disinfectant.amount==before,
 "revoked automatic permission cannot consume supplies or mutate another patient")
local dirty=item("Bandage");dirty.isInfected=function() return true end
contents={dirty,bandage}
assert(M.findBandageItem(actor)==bandage, "clean carried dressings outrank dirty alternatives")
-- The real planner selects a healed, covered body part without requiring supplies.
part.injured, part.covered, part.life = false, true, 4
otherPart.injured, otherPart.covered = false, false
contents = {}
local healed = N.decide(actor, nil)
assert(healed.kind == "remove_healed_bandage" and healed.bodyPart == part,
    "native healed reading selects covered part without supplies")
local healedAction, _, healedIntent = N.execute(actor, healed, { allowed = function() return true end })
assert(healedAction and healedAction:isValid(), "healed removal is admitted")
part.injured = true
assert(not healedAction:isValid() and healedAction:complete() == false and part.covered,
    "renewed injury before completion preserves dressing")
part.injured = false
healedAction, _, healedIntent = N.execute(actor, N.decide(actor, nil), { allowed = function() return true end })
assert(healedAction:complete() and N.verify(actor, healedIntent) and not part.covered,
    "native healed removal is confirmed by action receipt")
assert(not healedAction:complete(), "completed removal cannot execute twice")
otherPart.injured, otherPart.covered, otherPart.alcohol = true, false, 4
contents = { bandage }
assert(N.decide(actor, nil).kind == "bandage", "next exposed wound receives treatment")
assert(N.isMedicalCare("remove_healed_bandage"), "healed removal uses medical routing")
N.snapshot, ISDisinfect, ISEatFoodAction, ISTimedActionQueue = oldSnapshot, oldDisinfect, oldEat, oldQueue
ComponentType = oldComponentType
ISApplyBandage.new = oldBandageNew
