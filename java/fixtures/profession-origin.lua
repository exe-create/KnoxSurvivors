local Origins = assert(KnoxSurvivorOrigins, "survivor origins are loaded")
local Capabilities = assert(KnoxSurvivorCapabilities, "survivor capabilities are loaded")

-- A facility profession wears that facility's clothing and carries its kit, so
-- it may only be produced where that facility is. This is the rule the ordinary
-- roll now consults; before it, a household survivor could roll a police
-- uniform from the full vanilla profession list.
local facilities = Origins.facilityProfessions()
assert(#facilities == 3, "three facility professions are named, got " .. tostring(#facilities))

assert(Origins.professionAllowedAtContext("base:policeofficer", "law_enforcement") == true,
    "a police station produces police officers")
assert(Origins.professionAllowedAtContext("base:veteran", "military") == true,
    "a military site produces soldiers")
assert(Origins.professionAllowedAtContext("base:fireofficer", "fire_service") == true,
    "a fire station produces fire officers")

assert(Origins.professionAllowedAtContext("base:policeofficer", "generic") == false,
    "a household origin may not be a police officer")
assert(Origins.professionAllowedAtContext("base:veteran", "law_enforcement") == false,
    "a police station does not produce soldiers")
assert(Origins.professionAllowedAtContext("base:fireofficer", "medical") == false,
    "a hospital does not produce fire officers")

assert(Origins.professionAllowedAtContext("base:farmer", "generic") == true,
    "ordinary professions belong anywhere")
assert(Origins.professionAllowedAtContext("base:carpenter", "military") == true,
    "an ordinary profession is never denied by place")
assert(Origins.professionAllowedAtContext("base:policeofficer", nil) == false,
    "a missing context is not facility evidence")

local denied = Capabilities.denySet(facilities)
assert(Capabilities.professionDenied("base:policeofficer", denied) == true,
    "the ordinary roll skips a facility profession")
assert(Capabilities.professionDenied("base:veteran", denied) == true,
    "the ordinary roll skips every facility profession")
assert(Capabilities.professionDenied("base:farmer", denied) == false,
    "the ordinary roll still offers ordinary professions")
assert(Capabilities.professionDenied("base:policeofficer", nil) == false,
    "no deny list means no denial")
assert(Capabilities.denySet(nil) == nil, "no list builds no set")

print("Profession origin PASS facility_only=true ordinary_anywhere=true")

local oldEnsure,oldProfile=Capabilities.ensure,KnoxPersistence.getSurvivorCapabilities
KnoxPersistence.getSurvivorCapabilities=function() return nil end
local preferred,denied
Capabilities.ensure=function(id,character,initialize,profession,deny)
    preferred,denied=profession,deny
    return {professionId=profession or "base:farmer"},"fixture"
end
local playerStart={source="player_spawn",context="law_enforcement",professionCandidates={"base:policeofficer"}}
local civilian=assert(Capabilities.ensureForOrigin("civilian-fixture",nil,false,nil,playerStart))
assert(preferred==nil and civilian.professionId=="base:farmer" and #denied==3,
    "a profession-specific player start cannot bypass the civilian origin gate")
local station={source="world_building",buildingId="station",context="law_enforcement",
    professionCandidates={"base:policeofficer"}}
local officer=assert(Capabilities.ensureForOrigin("officer-fixture",nil,false,nil,station))
assert(officer.professionId=="base:policeofficer","an actual matching station still produces an officer")
Capabilities.ensure,KnoxPersistence.getSurvivorCapabilities=oldEnsure,oldProfile
