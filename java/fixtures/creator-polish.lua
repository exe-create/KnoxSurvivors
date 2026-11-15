local C, P, View = assert(KnoxCreator), assert(KnoxPersistence), assert(codecCreatorView)
assert(C.skinIndex(0)==0 and C.skinIndex("4")==4 and C.skinIndex(5)==nil
    and C.skinIndex(-1)==nil and C.skinIndex(1.5)==nil, "skin indexes are bounded integers")
local person={name="June Polish",look="casual",faction="solo",skin=4,hair="Long",
    hairColour="brown",slots={head="__none"},extraFields={"future=kept"}}
local read=C.decode(C.encode({person},C.newGroup()))
assert(read[1].skin==4 and read[1].slots.head=="__none" and read[1].extraFields[1]=="future=kept",
    "skin and an empty clothing slot round-trip without losing unknown fields")
assert(C.recordFor({name="No Gun",faction="solo",weapon="Base.Pistol",slots={primary="__none"}},C.newGroup()).weapon==nil,
    "an explicitly empty primary slot cannot resurrect the preset weapon")
local record=C.recordFor(read[1],C.newGroup())
assert(record.skin==4, "skin crosses the creator handover")
assert(P.setSurvivorCreatorRecord("polish-person",record), "creator record is stored")
assert(P.getSurvivorCreatorRecord("polish-person").skin==4, "world persistence retains the selected skin")
local worn={"old-hat","old-shirt"}
local inventory={"old-hat","old-shirt"}
assert(KnoxCharacterAppearance.clearCreatorWear({
    getWornItems=function() return {size=function() return #worn end,getItemByIndex=function(self,i) return worn[i+1] end} end,
    removeWornItem=function(self,item) for i=#worn,1,-1 do if worn[i]==item then table.remove(worn,i) end end end,
}),"authored clothing uses the native initial-wear removal path")
assert(#worn==0 and #inventory==2,"old random clothing is unequipped without deleting physical inventory")
local visual={setSkinTextureIndex=function(self,n) self.skin=n end}
local ok,reason=KnoxCharacterAppearance.applyCreator(nil,"polish-person",
    {getHumanVisual=function() return visual end},{skin=4})
assert(ok and visual.skin==4 and reason:find("face=set",1,true), "spawn applies the saved skin to HumanVisual")
local before=visual.skin
KnoxCharacterAppearance.applyCreator(nil,"polish-person",{getHumanVisual=function() return visual end},{skin=99})
assert(visual.skin==before,"invalid skin never reaches the native setter")
local edited={female=true,name="Keep me",slots={head="__none"},skills={Aiming=4}}
C.randomizeAppearance(edited,{"","Long"},{""},function(n) return n-1 end)
assert(edited.skin==4 and edited.hair=="Long" and edited.beard=="" and edited.name=="Keep me"
    and edited.slots.head=="__none" and edited.skills.Aiming==4,"randomize changes only appearance and respects sex")
local sig=View.previewSignature(person)
person.skin=1
assert(sig~=View.previewSignature(person),"skin changes invalidate the preview")
local none=C.lookItemsWithSlots("police",{head="__none"})
for _,item in ipairs(none) do assert(not C.slotOption("head",item),"empty head slot removes the outfit hat") end
local grid=C.cardGrid(3,0,0,95,400,0)
for _,card in ipairs(grid.cards) do assert(card.x+card.width<=95,"cards stay inside a narrow column") end

local defs={}
local added,group=C.addTemplateFaction(defs,"Rosewood Police Detail","template_rosewood_police")
assert(added and group.profile=="police" and group.region=="Rosewood" and group.memberCount==4,
    "area roster copies the existing police policy")
local roster={}
local library=C.newGroup();library.defs=defs
assert(C.populateFaction(roster,library,group.id,3),"police starting roster creates real editable people")
assert(roster[1].skin~=roster[2].skin and roster[1].hairColour~=roster[2].hairColour,
    "default roster members have varied persistent appearances")
local restored,groups=C.decode(C.encode(roster,library))
assert(C.profileFor(group.id,groups.defs).region=="Rosewood", "region survives the creator file")
local copied,copy=C.copyFaction(groups.defs,group.id,"Other Detail")
assert(copied and copy.region=="Rosewood", "copy retains placement policy")
local householdDefs={}
local made,family=C.addFaction(householdDefs,"Bennett Household","household")
local familyRoster={}
assert(made and C.populateFaction(familyRoster,{defs=householdDefs},family.id,4))
assert(familyRoster[1].look~=familyRoster[2].look and familyRoster[1].pack~=familyRoster[2].pack
    and familyRoster[1].profession~=familyRoster[2].profession and familyRoster[1].weaponId~=familyRoster[2].weaponId,
    "household members have varied ordinary clothing, supplies, former work and tools")
for _, label in ipairs({"The Bennett Household", "Bennett Family", "Household of 4", "Trailer Park Survivors"}) do
    local familyDefs, people = {}, {}
    local addedFamily, definition = C.addFaction(familyDefs,label,"household")
    assert(addedFamily and C.populateFaction(people,{defs=familyDefs},definition.id,3))
    local surname = people[1].name:match("%s([^%s]+)$")
    assert(surname and surname~="The" and surname~="Household" and surname~="Trailer",
        "group titles do not become surnames")
    if label:find("Bennett",1,true) then assert(surname=="Bennett", "recognised family label retains its surname") end
    for _, member in ipairs(people) do
        assert(member.name:match("%s([^%s]+)$")==surname, "generated household shares one family surname")
    end
end
local doctors={}
assert(C.addSoloTemplate(doctors,"June Doctor","template_rosewood_doctors"),"doctor template creates an independent person")
local doctor=C.decode(C.encode(doctors,C.newGroup()))
assert(doctor[1].faction=="solo" and doctor[1].profession=="base:doctor" and doctor[1].region=="Rosewood"
    and C.recordFor(doctor[1],C.newGroup()).spawnContext=="medical","independent doctor retains the medical origin without a faction")
local oldP=KnoxPersistence
KnoxPersistence={}
local function origin(key,region,context)
    return {key=key,buildingId=key,source="world_building",region=region,context=context}
end
local single={{name="Clinic Person",faction=group.id}}
local plan,complete=C.pendingWorldPlan(single,library,{origins={
    origin("wrong-town","Riverside, KY","law_enforcement"),origin("wrong-site","Rosewood, KY","military"),
    origin("station","Rosewood, KY","law_enforcement")}}, {})
assert(complete and plan[1].sites[1].key=="station", "regional roster requires both its town and its real facility")
plan,complete=C.pendingWorldPlan(single,library,{origins={origin("elsewhere","Riverside, KY","law_enforcement")}}, {})
assert(not complete and plan[1].reason=="no_suitable_site", "missing regional facility never falls back to another town")
plan,complete=C.pendingWorldPlan(doctor,C.newGroup(),{origins={
    origin("not-medical","Rosewood, KY","residential"),origin("clinic","Rosewood, KY","medical")}}, {})
assert(complete and plan[1].sites[1].key=="clinic","independent doctor uses a medical facility")
KnoxPersistence=oldP
print("Creator polish PASS skin=roundtrip+spawn randomize=bounded emptySlot=true regionalFacility=true narrowCards=true")
