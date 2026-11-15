local C, Cap = assert(KnoxCreator), assert(KnoxSurvivorCapabilities)
local oldProf, oldTraits, oldP = CharacterProfessionDefinition, CharacterTraitDefinition, KnoxPersistence
local function list(values)
    return {size=function() return #values end, get=function(_, i) return values[i+1] end}
end
local function trait(id, cost, granted, exclusive)
    return {getType=function() return id end, getCost=function() return cost end,
        isFree=function() return cost == 0 end,
        getGrantedTraits=function() return list(granted or {}) end,
        isMutuallyExclusive=function(_, other) return other:getType() == exclusive end}
end
local grant = trait("base:grant", 0)
local good = trait("base:good", 2, {}, "base:bad")
local bad = trait("base:bad", -2, {}, "base:good")
local defs = {grant, good, bad}
CharacterTraitDefinition = {getTraits=function() return list(defs) end,
    getCharacterTraitDefinition=function(id) for _, d in ipairs(defs) do if d:getType() == id then return d end end end}
local profession = {getType=function() return "base:doctor" end,
    getGrantedTraits=function() return list({"base:grant"}) end}
CharacterProfessionDefinition = {getProfessions=function() return list({profession}) end}
local p = assert(Cap.authoredProfile({profession="base:doctor", traits="base:good;base:bad", skills="Aiming=0"}, nil))
assert(p.professionId == "base:doctor" and #p.traitIds == 2, "profession grant and one compatible optional trait")
assert(p.skills.Aiming.level == 0, "authored zero skill reaches profile")
assert(Cap.creatorTraitChoices("base:doctor", {"base:good"}, "base:bad") == nil, "conflicting choice refused")
local empty = assert(Cap.authoredProfile({profession="base:doctor", traits="", skills=""}, nil))
assert(#empty.traitIds == 1 and empty.traitIds[1] == "base:grant", "empty optional choices keep profession trait")
local prior = {professionId="base:doctor", traitIds={"base:good"}, skills={Aiming={level=7,xp=9}}, capturedAtHours=2}
local saved = prior
KnoxPersistence = {getSurvivorCapabilities=function() return saved end,
    setSurvivorCapabilities=function(_, value) saved=value; return true end,
    getSurvivorCreatorRecord=function() return {profession="base:doctor",traits="",skills="Aiming=0"} end}
local restored = assert(Cap.ensure("creator-test", nil, true))
assert(restored.skills.Aiming.level == 7 and restored.traitIds[1] == "base:good", "captured profile is never reset")
saved = {professionId="base:doctor", traitIds={"base:good"}, skills={}}
local initialized = assert(Cap.ensure("creator-fresh", nil, true))
assert(initialized.creatorInitialized and initialized.skills.Aiming.level == 0
    and #initialized.traitIds == 1 and initialized.traitIds[1] == "base:grant",
    "new body replaces an uncaptured preliminary roll with authored capabilities")
initialized.skills.Aiming.level = 4
local repeated = assert(Cap.ensure("creator-fresh", nil, true))
assert(repeated.skills.Aiming.level == 4, "a repeated initialization does not reset learned levels")
CharacterProfessionDefinition, CharacterTraitDefinition, KnoxPersistence = oldProf, oldTraits, oldP
