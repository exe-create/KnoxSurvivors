-- Automatic aid discovery must see every wound it can actually treat, not only
-- bleeding, and it must never claim a supply the medic does not carry.
local C = assert(KnoxAutonomyController)
local oldP, oldR, oldM, oldS = KnoxPersistence, KnoxSurvivorRuntime, KnoxMedicalActions, KnoxSettings
local oldCount, oldPlayer = getNumActivePlayers, getSpecificPlayer

local bandage, disinfectant, inventory = {}, {}, {}
local maintenance = {}
local ids = {}

local function square(x)
 return {getX=function() return x end, getY=function() return 0 end, getZ=function() return 0 end}
end

local function body(opts)
 local part = {bleeding=function() return opts.bleeding == true end,
  bandaged=function() return false end}
 local parts = {size=function() return 1 end, get=function() return part end}
 local person = {getCurrentSquare=function() return square(opts.x) end,
  isDead=function() return opts.dead == true end,
  getBodyDamage=function() return {getBodyParts=function() return parts end} end}
 return person, part
end

local medic = body({x=0})
medic.getInventory = function() return inventory end
local bleedingAlly, bleedingPart = body({x=2, bleeding=true})
local exposedAlly, exposedPart = body({x=1})
local deadAlly = body({x=1, dead=true})
ids[medic], ids[bleedingAlly], ids[exposedAlly], ids[deadAlly] = "medic", "bleeding", "exposed", "dead"

KnoxPersistence = {
 getSurvivorCreatorRecord=function() return {profile="doctors"} end,
 getSurvivorServiceRole=function() return nil end,
 getSurvivorAffiliation=function() return {factionId="medics"} end,
 areSurvivorsHostile=function() return false end,
 ensurePlayerId=function() return "player" end,
 isSurvivorHostileToPlayer=function() return false end,
 getPlayerSocialDisposition=function() return "independent" end,
}
KnoxSurvivorRuntime = {
 activeIds=function() return {"medic", "bleeding", "exposed", "dead"} end,
 getCharacter=function(id)
  if id == "bleeding" then return bleedingAlly end
  if id == "exposed" then return exposedAlly end
  if id == "dead" then return deadAlly end
  return medic
 end,
 idForCharacter=function(person) return ids[person] end,
}
KnoxMedicalActions = {
 findBandageItem=function(doctor, filter)
  if bandage == nil then return nil end
  if filter ~= nil and not filter(bandage) then return nil end
  return bandage
 end,
 maintenancePlan=function(doctor, patient)
  local plan = maintenance[patient]
  if plan == nil then return nil end
  return {kind="disinfect", item=plan.item, bodyPart=plan.part}
 end,
 aidAllowed=function() return true end,
}
KnoxSettings = {allowSurvivorsTreatPlayer=function() return true end}
getNumActivePlayers=function() return 1 end
getSpecificPlayer=function() return nil end

local controller = setmetatable({id="medic", character=medic, groupMembers={},
 reservations={items={},supportRecipients={}},
 aidNeedsSelfCare=function() return false end}, {__index=C})

-- 1. A bleeding ally still needs the real carried bandage.
bandage = {}
local found = controller:findAidPatient(0)
assert(found and found.patient == bleedingAlly and found.part == bleedingPart
 and found.bandage == bandage and found.kind == "bandage",
 "bleeding ally is chosen with the carried bandage")

-- 2. With only disinfectant the medic finds the exposed wound it can treat
--    instead of the whole scan giving up.
bandage = nil
maintenance[exposedAlly] = {item=disinfectant, part=exposedPart}
found = controller:findAidPatient(0)
assert(found and found.patient == exposedAlly and found.part == exposedPart
 and found.bandage == disinfectant and found.kind == "disinfect",
 "disinfectant-only medic finds the exposed wound it can treat")

-- 3. Stopping a bleed outranks a nearer wound that is merely open.
bandage = {}
local mixed = controller:findAidPatient(0)
assert(mixed and mixed.patient == bleedingAlly and mixed.kind == "bandage",
 "a bleeding ally outranks a nearer open wound")
bandage = nil

-- 4. No supply, no invention.
maintenance[exposedAlly] = nil
assert(controller:findAidPatient(0) == nil, "no supply never invents a treatment")

-- 5. A supply another survivor already holds is not double booked.
maintenance[exposedAlly] = {item=disinfectant, part=exposedPart}
controller.reservations.items[disinfectant] = "other"
assert(controller:findAidPatient(0) == nil, "claimed disinfectant is not offered twice")
controller.reservations.items[disinfectant] = nil

-- 6. A corpse is never a patient.
maintenance[exposedAlly] = nil
maintenance[deadAlly] = {item=disinfectant, part=exposedPart}
assert(controller:findAidPatient(0) == nil, "dead ally is never selected for care")

KnoxPersistence, KnoxSurvivorRuntime, KnoxMedicalActions, KnoxSettings = oldP, oldR, oldM, oldS
getNumActivePlayers, getSpecificPlayer = oldCount, oldPlayer
print("Medical aid discovery PASS bleeding=true disinfect=true priority=true claims=true corpse=false")
