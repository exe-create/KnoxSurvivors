local C = assert(KnoxAutonomyController)
local oldP, oldR, oldM, oldS = KnoxPersistence, KnoxSurvivorRuntime, KnoxMedicalActions, KnoxSettings
local oldCount, oldPlayer = getNumActivePlayers, getSpecificPlayer
local hostile, playerHostile, profile, allowPlayer, hasBandage = false, false, "doctors", true, true
local bandage, inventory = {}, {}
local function square(x) return {getX=function() return x end, getY=function() return 0 end, getZ=function() return 0 end} end
local function person(x, dead)
 local part = {bleeding=function() return true end, bandaged=function() return false end}
 local parts = {size=function() return 1 end, get=function() return part end}
 return {getCurrentSquare=function() return square(x) end, isDead=function() return dead == true end,
   getBodyDamage=function() return {getBodyParts=function() return parts end} end}, part
end
local physician = person(0)
physician.getInventory = function() return inventory end
local patient, part = person(2)
local player = person(3)
local ids = {[physician]="doctor", [patient]="stranger"}
KnoxPersistence = {
 getSurvivorCreatorRecord=function() return {profile=profile} end,
 getSurvivorServiceRole=function() return nil end,
 getSurvivorAffiliation=function(id) return {factionId=id == "doctor" and "a" or "b"} end,
 areSurvivorsHostile=function() return hostile end,
 ensurePlayerId=function() return "player" end,
 isSurvivorHostileToPlayer=function() return playerHostile end,
 getPlayerSocialDisposition=function() return "independent" end,
}
KnoxSurvivorRuntime = {activeIds=function() return {"doctor", "stranger"} end,
 getCharacter=function(id) if id == "stranger" then return patient end return physician end,
 idForCharacter=function(character) return ids[character] end}
KnoxMedicalActions = {findBandageItem=function() if hasBandage then return bandage end end,
 aidAllowed=function() return true end}
KnoxSettings = {allowSurvivorsTreatPlayer=function() return allowPlayer end}
getNumActivePlayers=function() return 1 end
getSpecificPlayer=function() return player end
local controller = setmetatable({id="doctor", character=physician, reservations={items={},supportRecipients={}},
 groupMembers={}, currentTicks=0, aidNeedsSelfCare=function() return false end}, {__index=C})
local found = controller:findAidPatient(0)
assert(found and found.patient == patient and found.part == part and found.bandage == bandage, "doctor selects unrelated neutral bleeding survivor")
hostile=true
found=controller:findAidPatient(0)
assert(found and found.patient == player, "hostile survivor skipped in favor of player")
allowPlayer=false
assert(controller:findAidPatient(0) == nil, "disabled player treatment excludes nearby player")
hostile=false; profile="household"
assert(controller:findAidPatient(0) == nil, "non-doctor does not treat unrelated survivor")
profile="doctors"; hasBandage=false
assert(controller:findAidPatient(0) == nil, "no bandage prevents treatment")
hasBandage=true
local plan={doctor=physician, recipient=patient, item=bandage, part=part, source=inventory}
controller.pendingAid=plan
controller.reservations.items[bandage]="doctor"
controller.reservations.supportRecipients[patient]="doctor"
assert(controller:aidPermission(plan), "neutral patient remains eligible during action")
hostile=true
assert(not controller:aidPermission(plan), "new hostility cancels pending action")
hostile=false; allowPlayer=true
plan.recipient=player
controller.reservations.supportRecipients[player]="doctor"
assert(controller:aidPermission(plan), "player treatment allowed")
playerHostile=true
assert(not controller:aidPermission(plan), "player hostility cancels pending action")
playerHostile=false; allowPlayer=false
assert(not controller:aidPermission(plan), "disabled player setting cancels pending action")
KnoxPersistence, KnoxSurvivorRuntime, KnoxMedicalActions, KnoxSettings = oldP, oldR, oldM, oldS
getNumActivePlayers, getSpecificPlayer = oldCount, oldPlayer
