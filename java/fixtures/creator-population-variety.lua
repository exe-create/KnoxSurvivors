local C = assert(KnoxCreator)
local oldHair, oldBeard, oldStyles = getAllHairStyles, getAllBeardStyles, getHairStylesInstance
local function list(values)
    return {size=function() return #values end, get=function(self,i) return values[i+1] end}
end
getAllHairStyles = function(female)
    assert(type(female)=="boolean", "native hair catalogue receives sex")
    return list(female and {"F0","F1","F2","F3","F4","Hidden"} or {"M0","M1","M2","M3","M4","Hidden"})
end
getHairStylesInstance=function()
    local function find(self,id) return {isNoChoose=function() return id=="Hidden" end} end
    return {FindFemaleStyle=find,FindMaleStyle=find}
end
getAllBeardStyles = function(...)
    assert(select("#",...)==0, "native beard catalogue receives no arguments")
    return list({"","B1","B2","B3"})
end
local function appearance(person)
    return tostring(person.female)..":"..person.skin..":"..person.hair..":"..person.beard..":"..person.hairColour
end
local group, roster = C.newGroup(), {}
local ok,a = C.addFaction(group.defs,"East Crew","police")
local okB,b = C.addFaction(group.defs,"West Crew","police")
assert(ok and okB)
assert(C.populateFaction(roster,group,a.id,24))
assert(C.populateFaction(roster,group,b.id,24))
local used, looks, beard, differences = {}, {}, false, 0
for i,person in ipairs(roster) do
    local key=C.nameKey(person.name)
    assert(not used[key], "generated people have unique full names across groups")
    used[key]=true
    looks[appearance(person)]=true
    if not person.female and person.beard~="" then beard=true end
    assert(not person.female or person.beard=="", "female defaults have no beard")
    assert(person.skin>=0 and person.skin<5, "skin uses installed zero-based range")
    assert(person.hair~="Hidden", "generated appearance excludes native no-choose hair styles")
    if i<=24 and appearance(person)~=appearance(roster[i+24]) then differences=differences+1 end
end
local uniqueLooks=0;for _ in pairs(looks) do uniqueLooks=uniqueLooks+1 end
assert(uniqueLooks>=30 and differences>=18 and beard, "default cosmetics vary within and across groups, including beards")
local repeatRoster={}
assert(C.populateFaction(repeatRoster,group,a.id,24))
for i=1,24 do
    assert(repeatRoster[i].name==roster[i].name and appearance(repeatRoster[i])==appearance(roster[i]),
        "unchanged group previews are deterministic")
end
local existing=roster[1]
assert(C.populateFaction(roster,group,a.id,1)==false and #roster==48 and roster[1]==existing,
    "a full group refuses the complete addition without changing existing people")
local spaced=C.newDraft();spaced.name="  "..existing.name:upper():gsub(" ","   ").."  "
assert(not C.add(roster,spaced), "name collision checks normalize case and spaces")

-- Default previews are separate empty rosters; their names still differ.
local defaultNames={}
for _,entry in ipairs(C.defaultEntries()) do
    if entry.group then
        local preview={}
        assert(C.populateFaction(preview,C.newGroup(),entry.id))
        for _,person in ipairs(preview) do
            local key=C.nameKey(person.name)
            assert(not defaultNames[key], "default previews have distinct names across groups: "..person.name)
            defaultNames[key]=true
            if entry.profile=="fire_service" or entry.id=="fire_service" then
                assert(person.profession=="base:fireofficer", "fire crews retain the vanilla fire-officer occupation")
            end
        end
    end
end
-- Same-surname households keep the surname even after the first given-name pool.
local homes=C.newGroup();local family={}
for i=1,3 do
    local made,home=C.addFaction(homes.defs,"Bennett Household "..i,"household")
    assert(made)
    -- Same display family, separate stable group IDs.
    home.label="Bennett Household"
    assert(C.populateFaction(family,homes,home.id,24))
end
local familyNames={}
for _,person in ipairs(family) do
    assert(person.name:match(" Bennett$"), "family surname is retained")
    assert(not familyNames[C.nameKey(person.name)], "same-surname households avoid full-name duplicates")
    familyNames[C.nameKey(person.name)]=true
end
local preview={}
assert(C.populateFaction(preview,group,"police",4,roster))
for _,person in ipairs(preview) do assert(not used[C.nameKey(person.name)], "preview excludes saved names") end
local read=C.decode(C.encode(roster,group))
for i,person in ipairs(read) do
    assert(person.name==roster[i].name and appearance(person)==appearance(roster[i]),
        "generated names and appearance survive creator save/reopen")
end
getAllHairStyles,getAllBeardStyles,getHairStylesInstance=oldHair,oldBeard,oldStyles
print("Creator population variety PASS names=unique looks="..uniqueLooks.." deterministic=true codec=true")
local previewCount=0;for _ in pairs(defaultNames) do previewCount=previewCount+1 end
return "PASS distinctLooks="..uniqueLooks.." alignedDifferences="..differences.." defaultNames="..previewCount.." codec=true nativeVisuals=false"
