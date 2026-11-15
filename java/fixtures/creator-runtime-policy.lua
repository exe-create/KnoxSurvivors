local P, T = assert(KnoxPersistence), assert(KnoxNpcVehicleTravel)
-- Real persistence functions get their own ModData graph; their allocated
-- people must not change another fixture's saved population contract.
local priorData = data
data = {}
local id = "creator-policy-fixture"
local slots = string.rep("x", 500)
assert(P.setSurvivorCreatorRecord(id, {name="Fixture", faction="user_police", groupName="Local Police", profile="police", attitude="neutral", spawnContext="default", vehiclePolicy="default", settlementPolicy="default", slots=slots, cargo="Base.Bandage=2"}))
local record = assert(P.getSurvivorCreatorRecord(id))
assert(record.profile == "police" and record.attitude == "neutral" and record.faction == "user_police" and record.groupName == "Local Police", "creator identity and attitude survive")
assert(record.spawnContext == "default" and record.vehiclePolicy == "default" and record.settlementPolicy == "default" and record.slots == slots and record.cargo == "Base.Bandage=2", "creator policies and expanded storage survive")
assert(P.getPlayerSocialDisposition("creator-player", id) == "independent", "neutral creator starts independent")
assert(P.setSurvivorCreatorRecord(id, {name="Fixture", profile="police", attitude="hostile"}))
assert(P.getPlayerSocialDisposition("creator-player", id) == "independent", "existing disposition is retained")
local bad = "creator-policy-invalid"
assert(P.setSurvivorCreatorRecord(bad, {name="Bad", profile="invalid", attitude="invalid", spawnContext="bad|value"}))
local invalid = P.getSurvivorCreatorRecord(bad)
assert(invalid.profile == nil and invalid.attitude == nil and invalid.spawnContext == nil, "invalid policy fields rejected")
assert(P.setSurvivorCreatorRecord("creator-custom-fixture", {name="Custom Person",faction="user_custom",profile="custom",
    attitude="neutral",settlementPolicy="mobile",kit="none",pack="none"}))
local custom=assert(P.getSurvivorCreatorRecord("creator-custom-fixture"))
assert(custom.profile=="custom" and custom.faction=="user_custom" and custom.settlementPolicy=="mobile",
    "custom purpose survives the real world-record writer and reader")
local oldRuntime, oldCount, oldSpecific = KnoxSurvivorRuntime, getNumActivePlayers, getSpecificPlayer
KnoxSurvivorRuntime = {idForCharacter=function() return id end}
getNumActivePlayers = function() return 0 end
getSpecificPlayer = function() return nil end
local square = {getX=function() return 0 end, getY=function() return 0 end, getZ=function() return 0 end}
local driver = {getCurrentSquare=function() return square end}
local function vehicle(x, script, locked)
 return {getX=function() return x end, getY=function() return 0 end, getZ=function() return 0 end,
 getSquare=function() return square end, getScriptName=function() return script end,
 getDriver=function() return nil end, isKeysInIgnition=function() return true end,
 isHotwired=function() return false end, getKeyId=function() return 1 end,
 isEngineRunning=function() return true end, isDriveable=function() return true end,
 getCurrentSpeedKmHour=function() return 0 end, getRemainingFuelPercentage=function() return 50 end,
 areAllDoorsLocked=function() return locked end}
end
local civilian, police, locked = vehicle(1,"Base.CarNormal",false), vehicle(5,"Base.CarLightsPolice",false), vehicle(2,"Base.CarLightsPolice",true)
assert(T.readyVehicleNear(driver,{civilian,police}) == police, "ready police car preferred")
assert(T.readyVehicleNear(driver,{civilian,locked}) == civilian, "locked preferred car falls back")
assert(T.readyVehicleNear(driver,{locked}) == nil, "locked car remains unavailable")
KnoxSurvivorRuntime, getNumActivePlayers, getSpecificPlayer = oldRuntime, oldCount, oldSpecific
local friendly = "creator-policy-friendly"
assert(P.setSurvivorCreatorRecord(friendly, {name="Friendly", profile="police", attitude="friendly"}))
assert(P.getPlayerSocialDisposition("creator-player", friendly) == "warm_up", "friendly creator starts receptive")
local random = "creator-policy-random"
assert(P.setSurvivorCreatorRecord(random, {name="Random", faction="user_random", profile="looters", attitude="random"}))
local chosen = P.getPlayerSocialDisposition("creator-player", random)
assert(chosen == "warm_up" or chosen == "independent" or chosen == "attack_on_sight", "random chooses a real disposition")
assert(P.getPlayerSocialDisposition("creator-player", random) == chosen, "random disposition persists")
local savedRuntime, savedCount, savedSpecific = KnoxSurvivorRuntime, getNumActivePlayers, getSpecificPlayer
KnoxSurvivorRuntime = {idForCharacter=function() return id end}
getNumActivePlayers = function() return 0 end
getSpecificPlayer = function() return nil end
assert(P.setSurvivorCreatorRecord(id, {name="Fixture", profile="military", attitude="hostile"}))
local army = vehicle(5,"Mod.ArmyTruck",false)
assert(T.readyVehicleNear(driver,{civilian,army}) == army, "explicit army script preferred")
assert(T.readyVehicleNear(driver,{civilian}) == civilian, "military fallback uses an available car")
KnoxSurvivorRuntime, getNumActivePlayers, getSpecificPlayer = savedRuntime, savedCount, savedSpecific
local applyCargo = assert(creatorApplyCargoProbe, "cargo production helper missing")
local oldGear = KnoxSurvivorStartingGear
local received = nil
KnoxSurvivorStartingGear = {applyItems=function(_, items) received=items; return true, "added" end}
local ok = applyCargo({}, {cargo="Base.Bandage=2;Base.Axe=1"})
assert(ok and #received == 3, "finite cargo counts reach real gear boundary")
KnoxSurvivorStartingGear = {applyItems=function() return false, "add_failed" end}
local failed, reason = applyCargo({}, {cargo="Base.Axe=1"})
assert(not failed and reason == "add_failed", "cargo errors are reported")
KnoxSurvivorStartingGear = oldGear
-- Real persistence records and travel groups exercise the initial NPC boundary.
local function personAt(x)
 local allocated = assert(P.allocateWorldSurvivor({x=x,y=9291,z=0,key="creator-policy-"..x,region="Fixture"},0))
 return allocated
end
local robber, mate, stranger, friend, history = personAt(9291),personAt(9292),personAt(9293),personAt(9294),personAt(9295)
assert(P.setSurvivorCreatorRecord(robber,{name="Robber",profile="robbers",attitude="hostile"}))
assert(P.setSurvivorCreatorRecord(mate,{name="Mate",profile="robbers",attitude="hostile"}))
assert(P.setSurvivorCreatorRecord(friend,{name="Friend",profile="police",attitude="friendly"}))
assert(P.createTravelGroup({robber,mate},0))
assert(P.getSurvivorDisposition(robber,mate)=="allied", "same actual group stays allied")
assert(P.getSurvivorDisposition(robber,stranger)=="hostile", "hostile creator has hostile initial NPC boundary")
assert(P.getRelationship(robber,stranger)==nil, "initial boundary creates no encounter")
assert(P.setRelationshipDisposition(robber,stranger,"allied",0))
assert(P.getSurvivorDisposition(robber,stranger)=="allied", "real alliance outranks creator hostility")
assert(P.setRelationshipDisposition(friend,history,"hostile",0))
assert(P.getSurvivorDisposition(friend,history)=="hostile", "real hostility outranks friendly creator")
assert(P.setRelationshipDisposition(robber,history,"neutral",0))
assert(P.getSurvivorDisposition(robber,history)=="neutral", "recorded neutral history outranks initial hostility")
local soldier, soldierMate, outsider = personAt(9301),personAt(9302),personAt(9303)
assert(P.setSurvivorCreatorRecord(soldier,{name="Soldier",profile="military",attitude="hostile"}))
assert(P.setSurvivorCreatorRecord(soldierMate,{name="Soldier mate",profile="military",attitude="hostile"}))
assert(P.createTravelGroup({soldier,soldierMate},0))
assert(P.getSurvivorDisposition(soldier,outsider)=="neutral", "two living military group members start receptive")
assert(P.getPlayerSocialDisposition("weak-military-player",soldier)=="warm_up", "two living military group members start receptive to player")
local solo = personAt(9304)
assert(P.setSurvivorCreatorRecord(solo,{name="Solo soldier",profile="military",attitude="hostile"}))
assert(P.getPlayerSocialDisposition("solo-military-player",solo)=="warm_up", "solo military survivor starts receptive")
local randomNpc = personAt(9305)
assert(P.setSurvivorCreatorRecord(randomNpc,{name="Random",profile="looters",attitude="random",faction="user_random"}))
local disposition = P.getSurvivorDisposition(randomNpc,outsider)
assert(disposition == "hostile" or disposition == "neutral", "random NPC baseline is real disposition")
assert(P.getSurvivorDisposition(outsider,randomNpc)==disposition, "random baseline stable across order")
-- Explicit custom military stance and recorded neutral history remain real.
local unitIds={personAt(9321),personAt(9322),personAt(9323),personAt(9324)}
local unit=assert(P.createTravelGroup(unitIds,0), 'military fixture group must form');unit.background="military"
local unitFaction=assert(P.promoteTravelGroupToFaction(unit.id,1,3), 'military fixture faction must form')
local unitLeader=unitFaction.leaderId
assert(P.setSurvivorCreatorRecord(unitLeader,{name="June Voss",profile="military",attitude="friendly"}))
local identity=P.getSurvivorIdentity(unitLeader)
assert(identity.forename=="June" and identity.surname=="Voss", "creator name reaches durable identity before materialization")
assert(P.getSurvivorDisposition(unitLeader,outsider)=="neutral", "friendly custom military is not forced hostile by the default doctrine")
assert(P.setSurvivorCreatorRecord(unitLeader,{name="June Voss",profile="military",attitude="hostile"}))
assert(P.setRelationshipDisposition(unitLeader,outsider,"neutral",2))
assert(P.getSurvivorDisposition(unitLeader,outsider)=="neutral", "actual neutral history beats a military starting policy")
local mobileIds={personAt(9331),personAt(9332),personAt(9333)}
local mobile=assert(P.createTravelGroup(mobileIds,0))
assert(P.setSurvivorCreatorRecord(mobile.leaderId,{name="Mobile leader",profile="looters",attitude="neutral",settlementPolicy="mobile"}))
local permanent,reason=P.promoteTravelGroupToFaction(mobile.id,1,3)
assert(permanent==nil and reason=="mobile_group", "mobile looters cannot silently become a permanent settlement")
data = priorData
