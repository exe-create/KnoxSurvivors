local Info = assert(KnoxCreatorLoadoutInfo)
local oldProf, oldTrait, oldFactory = CharacterProfessionDefinition, CharacterTraitDefinition, instanceItem
local oldTransform, oldPerks = transformIntoKahluaTable, PerkFactory
local function list(t) return {size=function() return #t end, get=function(_, i) return t[i+1] end} end
local granted = {getType=function() return "base:grant" end, getLabel=function() return "Granted" end,
    getDescription=function() return "Native trait description" end, getTexture=function() return "trait texture" end,
    getGrantedTraits=function() return list({}) end, getXpBoosts=function() return {} end}
local job = {getType=function() return "base:doctor" end, getLabel=function() return "Doctor" end,
    getDescription=function() return "Native job description" end, getTexture=function() return "job texture" end,
    getGrantedTraits=function() return list({"base:grant"}) end, getXpBoosts=function() return {Medicine=2} end}
CharacterProfessionDefinition = {getProfessions=function() return list({job}) end}
CharacterTraitDefinition = {getTraits=function() return list({granted}) end}
transformIntoKahluaTable = function(map) return map end
PerkFactory = {getPerkName=function(perk) return perk end}
local count = 0
instanceItem = function(id)
    count = count + 1
    if id ~= "Base.Bag" then return nil end
    return {getDisplayName=function() return "Bag" end, getActualWeight=function() return 1.5 end,
        getCapacity=function() return 20 end, getWeightReduction=function() return 75 end,
        getBiteDefense=function() return 10 end, getScratchDefense=function() return 20 end,
        getBulletDefense=function() return 0 end, getBloodClothingType=function() return list({"Torso"}) end}
end
local person = Info.person({profession="base:doctor", traits={"base:grant"}})
assert(person.occupation.description == "Native job description" and person.occupation.texture == "job texture", "native occupation info")
assert(person.occupation.boosts[1].name == "Medicine" and person.occupation.boosts[1].level == 2, "native occupation boosts")
assert(#person.traits == 1 and person.traits[1].description == "Native trait description", "granted traits are deduplicated")
assert(person.mainCapacity == "Requires spawned body", "main capacity does not guess")
local item = assert(Info.item("Base.Bag"))
assert(item.weight == 1.5 and item.capacity == 20 and item.weightReduction == 75, "native item capacity and weight")
assert(item.bite == 10 and item.scratch == 20 and item.bullet == 0 and item.coverage[1] == "Torso", "separate item defense and coverage")
assert(item.effectiveCapacity == "Requires spawned body", "effective capacity does not guess")
assert(Info.backpackCapacity(item, {profession="base:doctor", traits={}}) == 20, "ordinary backpack capacity")
assert(Info.backpackCapacity(item, {profession="base:doctor"}) == nil, "automatic traits stay unknown")
assert(Info.backpackCapacity(item, {profession="base:doctor", traits={"base:missing"}}) == nil, "unknown trait stays unknown")
local organized = {getType=function() return "base:organized" end, getLabel=function() return "Organized" end,
    getGrantedTraits=function() return list({}) end}
CharacterTraitDefinition.getTraits = function() return list({granted, organized}) end
assert(Info.backpackCapacity(item, {profession="base:doctor", traits={"base:organized"}}) == 26, "organized backpack capacity")
assert(Info.backpackCapacity({capacity=90}, {profession="base:doctor",traits={"base:organized"}})==116,
    "capacity preview preserves installed Java float rounding before truncation")
assert(Info.item("Base.Bag") == item and count == 1, "item model is cached")
assert(Info.item("Base.Unknown") == nil and Info.occupation("base:missing") == nil, "unknown definitions stay unknown")
assert(Info.itemTooltip("Base.Bag",{profession="base:doctor",traits={}}):find("Bite 10",1,true),
    "hover information exposes native protection without a permanent row block")
local savedPcall=pcall
pcall=function(fn,...)
    assert(type(fn)=="function", "item information never invokes an absent subtype method")
    return savedPcall(fn,...)
end
instanceItem=function() return {getDisplayName=function() return "Plain weapon" end,getActualWeight=function() return 2 end} end
local ordinary=Info.item("Base.PlainWeapon")
pcall=savedPcall
assert(ordinary.weight==2 and ordinary.capacity==nil and ordinary.bite==nil,
    "ordinary items expose weight without fabricated container or clothing statistics")
CharacterProfessionDefinition, CharacterTraitDefinition, instanceItem = oldProf, oldTrait, oldFactory
transformIntoKahluaTable, PerkFactory = oldTransform, oldPerks
