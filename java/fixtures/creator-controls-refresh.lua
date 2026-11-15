local C=assert(KnoxCreator)
local reads={hair=0,beard=0}
local Panel={hairOptions=function(female)
    reads.hair=reads.hair+1;return female and {"","Long"} or {"","Short"}
end,beardOptions=function(female)
    reads.beard=reads.beard+1;return female and {""} or {"","Full"}
end}
local Window={}
KnoxCreatorAppearanceUI.install(Panel,Window,C,nil)
local defs={}
local ok,entry=C.addFaction(defs,"Controls Household","household")
assert(ok)
local person={name="June",female=false,hair="Short",beard="",skin=0,hairColour="brown",
    faction=entry.id,profession="base:unemployed",look="casual",kit="none",pack="meal"}
local fields={}
for _,kind in ipairs({"sex","hair","beard","profession","look","kit","pack","faction"}) do
    local combo={knoxKind=kind,options={},clears=0}
    function combo:clear() self.options={};self.clears=self.clears+1 end
    function combo:addOptionWithData(text,data) self.options[#self.options+1]={text=text,data=data} end
    function combo:getOptionData(index) return self.options[index].data end
    fields[#fields+1]=combo;fields[kind]=combo
end
local win=setmetatable({group={defs=defs},fieldCombos=fields},{__index=Window})
win:refreshFields(person)
assert(fields.sex:getOptionData(fields.sex.selected)==false and fields.hair:getOptionData(fields.hair.selected)=="Short",
    "native choice data retains false sex values and the selected hairstyle")
local hairOptions=fields.hair.options
for n=1,5 do person.skin=n%5;person.hairColour="red";win:refreshFields(person) end
assert(reads.hair==1 and reads.beard==1,"unrelated edits do not query installed styles again")
for _,combo in ipairs(fields) do assert(combo.clears==1,"unrelated edits preserve dropdown rows: "..combo.knoxKind) end
assert(fields.hair.options==hairOptions,"the native dropdown's unchanged option table stays intact")
person.female=true;person.hair="Long";win:refreshFields(person)
assert(fields.hair:getOptionData(fields.hair.selected)=="Long" and fields.beard.disabled,
    "female choices are independent and beard selection is disabled")
person.female=false;person.hair="Short";win:refreshFields(person)
assert(reads.hair==2 and reads.beard==2,"returning to male reuses that window's original style choices")
person.hair="UnavailableModStyle";win:refreshFields(person)
assert(fields.hair:getOptionData(fields.hair.selected)=="UnavailableModStyle" and #fields.hair.options==3,
    "a missing mod style is retained and displayed explicitly")
person.hair="Short";win:refreshFields(person)
assert(#fields.hair.options==2 and fields.hair:getOptionData(fields.hair.selected)=="Short",
    "choosing an available style removes the stale missing-style row")
local before=fields.faction.clears
entry.label="Renamed Household";win:refreshFields(person)
assert(fields.faction.clears==before+1 and fields.faction.options[fields.faction.selected].text==entry.label,
    "renaming a real group updates membership choices despite reusing its record")
entry.label=nil;win:refreshFields(person)
assert(fields.faction.options[fields.faction.selected].text=="Unnamed choice"
    and fields.faction:getOptionData(fields.faction.selected)==entry.id,
    "a missing label has a readable fallback while retaining its internal selection key")
win.group.readOnly=true;win:refreshFields(person)
for _,combo in ipairs(fields) do assert(combo.disabled,"read-only rosters disable every editable field") end
win:refreshFields(nil)
for _,combo in ipairs(fields) do assert(combo.disabled and #combo.options==1 and combo.options[1].text=="Choose a person",
    "empty selection clears the old person's fields") end
print("Creator controls PASS stableRows=true stylesPerSex=1 renameRefresh=true unknownStyleRetained=true readonly=true")
