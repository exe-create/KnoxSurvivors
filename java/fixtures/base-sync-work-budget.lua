local duty={mode="companion",ownerId="player",order="follow"}
local policies={weaponPreference="auto"}
local base={id="home"};local player={};local ride={}
local gets,assigns,weapons,exits=0,0,0,0
local c={baseSupplyTrip=true,character={getVehicle=function() return ride end}}
function c:setWeaponPreference(value) weapons=weapons+1;self.weapon=value end
function c:clearBaseAssignment() end
function c:clearCompanionOrder() end
function c:setCompanionOrder() end
function c:setCompanionCombatStance() end
function c:setCompanionPolicy() end
function c:setCompanionDirective() end
function c:setBaseAssignment(id,value)
 assert(id=="home");assigns=assigns+1;self.projectedBase=value
end
local b={persistence={getSurvivorDuty=function() return duty end,
 getSurvivorPolicies=function() return policies end,getCompanionIds=function() return {} end},
 settings={allowSurvivorDoorWindowOpening=function() return true end},
 manager={get=function(id) assert(id=="home");gets=gets+1;return base end},
 bridge={setNpcPartyVisible=function() end},vehicles={exitAfterPlayer=function() exits=exits+1 end}}
local service,cache=syncProjectionFactory(b)
service.resolvePlayer=function() return player end
service.getPlayerPartyFormationContext=function() return nil end
service.removePlayerPartyFormationMember=function() end
service.getPartyDestination=function() return nil end
service.syncController("resident",c)
duty={mode="base",baseId="home"}
local previousConcat=table.concat
local fingerprints=0
table.concat=function(parts,separator)
 if #parts>=20 then fingerprints=fingerprints+1 end
 return previousConcat(parts,separator)
end
for i=1,120 do service.syncController("resident",c) end
table.concat=previousConcat
assert(assigns==120 and gets==120 and c.baseSupplyTrip,
 "every base tick still reconciles the current base and active supply run")
assert(fingerprints==0,"base ticks do not allocate unused large fingerprints")
assert(exits==1 and cache(c).ownerId==nil,"companion-to-base transition retires ride intent once")
base={id="home",replacement=true};policies.weaponPreference="melee"
service.syncController("resident",c)
assert(c.projectedBase==base and c.weapon=="melee" and assigns==121 and weapons==122,
 "base replacement and changed policies remain immediately visible")
duty={mode="autonomous"};service.syncController("resident",c)
assert(exits==1,"later independent duty does not replay an old party exit")
-- Counting harness for the per-tick duty and policy reads.
local revision, dutyReads, policyReads = 7, 0, 0
local duty3 = {mode="companion",ownerId="player",order="follow"}
local b3 = {persistence={getSurvivorDuty=function() dutyReads=dutyReads+1 return duty3 end,
 getSurvivorDutyRevision=function() return revision end,
 getSurvivorPolicies=function() policyReads=policyReads+1 return policies end,
 getCompanionIds=function() return {} end},
 settings={allowSurvivorDoorWindowOpening=function() return true end},
 manager={get=function() return base end},
 bridge={setNpcPartyVisible=function() end},vehicles={exitAfterPlayer=function() end}}
local service3=syncProjectionFactory(b3)
service3.resolvePlayer=function() return player end
service3.removePlayerPartyFormationMember=function() end
service3.getPartyDestination=function() return nil end
local forwardX=0
service3.getPlayerPartyFormationContext=function()
 forwardX=forwardX+1
 return {slots={},memberIds={},memberCount=1,forwardX=forwardX,forwardY=0}
end
local c3={character={}}
function c3:setWeaponPreference() end
function c3:clearBaseAssignment() end
function c3:clearCompanionOrder() end
function c3:setCompanionOrder() end
function c3:setCompanionCombatStance() end
function c3:setCompanionPolicy() end
function c3:setCompanionDirective() end
for i=1,20 do service3.syncController("companion",c3) end
assert(dutyReads==1,"an unchanged revision reuses the duty copy, got "..tostring(dutyReads))
assert(policyReads==20,"one policy copy per sync, got "..tostring(policyReads))
-- Old path: no revision stamp, so every sync allocates a fresh duty copy.
local oldDutyReads = 0
local b4 = {persistence={getSurvivorDuty=function() oldDutyReads=oldDutyReads+1 return duty3 end,
 getSurvivorPolicies=function() return policies end,
 getCompanionIds=function() return {} end},
 settings={allowSurvivorDoorWindowOpening=function() return true end},
 manager={get=function() return base end},
 bridge={setNpcPartyVisible=function() end},vehicles={exitAfterPlayer=function() end}}
local service4=syncProjectionFactory(b4)
service4.resolvePlayer=function() return player end
service4.removePlayerPartyFormationMember=function() end
service4.getPartyDestination=function() return nil end
local oldForward=0
service4.getPlayerPartyFormationContext=function()
 oldForward=oldForward+1
 return {slots={},memberIds={},memberCount=1,forwardX=oldForward,forwardY=0}
end
for i=1,20 do service4.syncController("companion",c3) end
assert(oldDutyReads==20,"the pre-cache path copies duty every tick, got "..tostring(oldDutyReads))
-- Lazy sync key: an unchanged companion tick compares parts and composes no
-- 25-piece string; the first tick and a real component change each build one.
local keyBuilds = 0
local concatForKeys = table.concat
table.concat = function(parts, separator)
 if type(parts) == "table" and #parts >= 20 then keyBuilds = keyBuilds + 1 end
 return concatForKeys(parts, separator)
end
local stableDuty = {mode="companion",ownerId="player",order="follow",revision=7}
local stablePolicy = {weaponPreference="melee"}
local stableContext = {slots={},memberIds={},memberCount=1,forwardX=1,forwardY=2}
local b5 = {persistence={getSurvivorDuty=function() return stableDuty end,
 getSurvivorDutyRevision=function() return 7 end,
 getSurvivorPolicies=function() return stablePolicy end,
 getCompanionIds=function() return {} end},
 settings={allowSurvivorDoorWindowOpening=function() return true end},
 manager={get=function() return base end},
 bridge={setNpcPartyVisible=function() end},vehicles={exitAfterPlayer=function() end}}
local service5=syncProjectionFactory(b5)
service5.resolvePlayer=function() return player end
service5.removePlayerPartyFormationMember=function() end
service5.getPartyDestination=function() return nil end
service5.getPlayerPartyFormationContext=function() return stableContext end
local c5={character={}}
function c5:setWeaponPreference() end
function c5:clearBaseAssignment() end
function c5:clearCompanionOrder() end
function c5:setCompanionOrder() end
function c5:setCompanionCombatStance() end
function c5:setCompanionPolicy() end
function c5:setCompanionDirective() end
for i=1,20 do service5.syncController("companion",c5) end
assert(keyBuilds==1,"an unchanged companion tick composes no key, got "..tostring(keyBuilds))
stableDuty.order="hold"
service5.syncController("companion",c5)
assert(keyBuilds==2,"a changed component composes exactly one key, got "..tostring(keyBuilds))
table.concat=concatForKeys
KS_SYNC_RECEIPT = "duty_reads_old="..tostring(oldDutyReads)
 .. " duty_reads_new="..tostring(dutyReads)
 .. " policy_reads_new="..tostring(policyReads)
 .. " policy_sites_old=2 ticks=20"
 .. " key_builds_unchanged=1 key_builds_changed=2"

print("Base sync budget PASS unused_fingerprints=0 projections=121 replacement=true ride_exit_once=true")
