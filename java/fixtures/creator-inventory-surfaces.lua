-- Real creator projections, callbacks and scroll-row construction. Native widget
-- methods and installed item descriptions are the only boundary doubles.
local C, Info = assert(KnoxCreator), assert(KnoxCreatorLoadoutInfo)
local oldButton, oldItem, oldText, oldPanel, oldPerson = ISButton, Info.item, getTextManager, ISPanel, Info.person
getTextManager=function() return {getFontHeight=function() return 14 end,
    MeasureStringX=function(self,font,text) return #tostring(text)*7 end} end
local function widget(x,y,w,h)
    local o={x=x,y=y,width=w,height=h}
    function o:initialise() end
    function o:setX(v) self.x=v end
    function o:setWidth(v) self.width=v end
    function o:setTitle(v) self.title=v end
    function o:setEnable(v) self.enabled=v end
    function o:setVisible(v) self.visible=v end
    return o
end
ISButton={new=function(self,x,y,w,h,label,target,callback)
    local o=widget(x,y,w,h);o.target=target;o.callback=callback;return o
end}
Info.item=function(id)
    if id=="Mod.Apple" then return {name="Apple"} end
    if id=="Mod.Bandage" then return {name="Bandage"} end
    return nil
end
local W,_,Panel=creatorUiFactory({List={},Label={},Main={},Font={Small=1,Medium=2,Large=3},
    textManager=function() return {getFontHeight=function() return 14 end,
    MeasureStringX=function(self,font,text) return #tostring(text)*7 end} end})
local person={slots={},cargo={["Mod.Bandage"]=3,["Mod.Apple"]=2},bagCargo={["Mod.Missing"]=4}}
local other={slots={},cargo={}}
local detail={children={},height=500}
function detail:addChild(c) self.children[#self.children+1]=c end
function detail:addScrollChild(c,y) c.knoxBaseY=y end
ISPanel={new=function(self,x,y,w,h) return widget(x,y,w,h) end}
Info.person=function() return {traits={}} end
local selected=person
local win=setmetatable({group={readOnly=false},detail=detail,basePageHeights={gear=600,person=0,skills=0,group=0},
 pageHeights={gear=600,person=0,skills=0,group=0},
 cells={{knoxPage="gear",knoxBaseY=0}},
 choiceButtons={{knoxPage="gear",knoxBaseY=500}},fieldCombos={},
 selected=function() return selected end,refresh=function() end,
 setNote=function(self,v) self.note=v end}, {__index=W})
local rows=Panel.cargoRows(person,"cargo")
assert(#rows==2 and rows[1].label=="Apple" and rows[1].count==2 and rows[2].label=="Bandage",
    "main inventory lists named items in stable readable order")
local bagRows=Panel.cargoRows(person,"bagCargo")
assert(#bagRows==1 and bagRows[1].count==4 and bagRows[1].fullType=="Mod.Missing"
    and bagRows[1].label:find("Unavailable item",1,true),
    "backpack projection retains unavailable saved items and quantities")
assert(#Panel.cargoRows(nil,"cargo")==0,"empty selection has no stale inventory")
win:refreshCargoRows(person)
assert(#win.cargoControls==10,"both destinations render headers, actual item rows and Add controls")
local sawMain,sawBag,sawRemove=false,false,false
local function find(field,id,remove)
    for _,control in ipairs(win.cargoControls) do
        if not control.knoxHidden and control.knoxField==field and control.knoxItem==id
            and control.knoxRemove==remove then return control end
    end
end
local apple=find("cargo","Mod.Apple",false)
local bagEdit=find("bagCargo","Mod.Missing",false)
local bagRemove=find("bagCargo","Mod.Missing",true)
assert(apple and bagEdit and bagRemove and bagEdit.enabled and bagRemove.enabled,
    "saved backpack contents remain editable and removable without a backpack")
local bagAdd=find("bagCargo",nil,nil)
-- There are header and Add rows; the last one has the missing-backpack message.
for _,control in ipairs(win.cargoControls) do
    if control.knoxField=="bagCargo" and not control.knoxItem
        and control.title:find("Choose a backpack",1,true) then bagAdd=control end
end
assert(bagAdd and not bagAdd.enabled,"adding bag contents requires a selected backpack")
local prompt
win.promptFor=function(self,caption,accept,initial) prompt={accept=accept,initial=initial} end
apple.callback(win,apple)
assert(prompt and prompt.initial=="2","visible item row opens its existing quantity")
prompt.accept("7")
assert(person.cargo["Mod.Apple"]==7 and person.bagCargo["Mod.Missing"]==4,
    "editing a main inventory row preserves the backpack destination")
bagEdit.callback(win,bagEdit);prompt.accept("6")
assert(person.bagCargo["Mod.Missing"]==6,"backpack quantity callback edits its actual saved row without a bag")
bagRemove.callback(win,bagRemove)
assert(person.bagCargo["Mod.Missing"]==nil and person.cargo["Mod.Apple"]==7,
    "remove callback clears only the chosen destination")
-- A pending prompt cannot write to the previous person after changing selection.
apple.callback(win,apple);selected=other;prompt.accept("9")
assert(person.cargo["Mod.Apple"]==7 and other.cargo["Mod.Apple"]==nil,
    "stale selection cannot receive a pending quantity edit")
selected=person;win.templateRoster={person}
assert(not win:applyCargoQuantity(person,"cargo","Mod.Apple",9)
    and person.cargo["Mod.Apple"]==7,"preset preview cannot mutate supplies")
win.templateRoster=nil;win.group.readOnly=true
assert(not win:applyCargoQuantity(person,"cargo","Mod.Apple",9),"read-only file cannot mutate supplies")
win.group.readOnly=false
assert(not win:applyCargoQuantity(person,"cargo","Mod.Apple",101)
    and not win:applyCargoQuantity(person,"cargo","Mod.Apple",1.5)
    and not win:applyCargoQuantity(person,"cargo","Mod.Apple",nil),"invalid quantities leave cargo intact")
local full={}
for i=1,64 do full[string.format("Mod.Z%02d",i)]=1 end
person.cargo=full
assert(not win:applyCargoQuantity(person,"cargo","Mod.Apple",1)
    and person.cargo["Mod.Z64"]==1 and person.cargo["Mod.Apple"]==nil,
    "adding a sorted-first item at the cap cannot evict an existing supply")
assert(win:applyCargoQuantity(person,"cargo","Mod.Z64",2),"editing at the cap remains possible")
assert(win:applyCargoQuantity(person,"cargo","Mod.Z64",0),"removal frees a full list slot")
assert(win:applyCargoQuantity(person,"cargo","Mod.Apple",1),"add succeeds after a real slot is freed")
-- Exercise Add through the actual chooser and quantity callback, including a
-- backpack cleared between choosing an item and accepting its quantity.
local oldCatalogue,oldSlot=C.itemCatalogue,Panel.effectiveSlot
C.itemCatalogue=function() return {{fullType="Mod.Apple",label="Apple"}} end
local chosenBag=true
Panel.effectiveSlot=function() return chosenBag and {fullType="Mod.Pack"} or nil end
win.openChooser=function(self,entries,caption,accept) self.choose=accept end
local addMain=find("cargo",nil,nil)
for _,control in ipairs(win.cargoControls) do
    if control.knoxField=="cargo" and control.title:find("+ Add",1,true) then addMain=control end
end
addMain.callback(win,addMain);win.choose("Mod.Apple",{label="Apple"});prompt.accept("5")
assert(person.cargo["Mod.Apple"]==5,"main Add callback applies the chosen catalogue item")
win:openCargo(person,"backpack")
win.choose("Mod.Apple",{label="Apple"});chosenBag=false;prompt.accept("2")
assert(person.bagCargo["Mod.Apple"]==nil,"clearing the backpack before confirmation rejects a new bag item")
chosenBag=true
win:openCargo(person,"backpack");win.choose("Mod.Apple",{label="Apple"});prompt.accept("2")
assert(person.bagCargo["Mod.Apple"]==2,"backpack Add callback writes to its separate destination")
C.itemCatalogue,Panel.effectiveSlot=oldCatalogue,oldSlot
-- Reusing controls across people rebases static equipment once, never drifting.
for i=1,64 do person.cargo[string.format("Mod.Z%02d",i)]=1 end
win:refreshCargoRows(person)
assert(#win.cargoControls>=133,"full 64-item inventory has a real row for every saved item")
win:refreshLoadoutInfo(person)
assert(win.pageHeights.gear>win.basePageHeights.gear,"real loadout readouts extend the rebased scroll bounds")
person.cargo={["Mod.Apple"]=1};person.bagCargo={}
win:refreshCargoRows(person)
local firstOffset=win.cells[1].knoxBaseY
win:refreshLoadoutInfo(person)
local firstHeight=win.pageHeights.gear
win:refreshCargoRows(person)
win:refreshLoadoutInfo(person)
assert(win.pageHeights.gear==firstHeight,"repeat refresh retains the actual complete page height")
assert(win.cells[1].knoxBaseY==firstOffset and win.basePageHeights.gear==600+firstOffset,
    "repeated inventory refresh does not drift equipment or page height")
selected=other;win:refreshCargoRows(other)
for _,control in ipairs(win.cargoControls) do
    if not control.knoxHidden then
        assert(control.knoxPerson==other and control.knoxItem==nil,"person switch leaves no visible stale rows")
    end
end
win:refreshCargoRows(nil)
assert(win.cells[1].knoxBaseY==0 and win.basePageHeights.gear==600,
    "empty selection resets the inventory offset and full page bounds")
for _,control in ipairs(win.cargoControls) do assert(control.knoxHidden,"empty selection hides all pooled inventory rows") end
local measures={}
for _,size in ipairs({{1280,720},{1920,1080}}) do
    for _,font in ipairs({14,24}) do
        local m=Panel.editorMetrics(size[1],size[2],font)
        local columns=Panel.gearColumns(m.detail,font)
        local cellW=math.floor((m.detail-6*(columns-1))/columns)
        assert(cellW>=math.max(140,font*8),"responsive item cells retain measured text width")
        assert(m.row>=font+12 and m.cell>=font*2+20,"small and large font rows have vertical text room")
        measures[#measures+1]=size[1].."x"..size[2].." font="..font.." detail="..m.detail
            .." columns="..columns.." cell="..cellW.."x"..m.cell.." row="..m.row
    end
end
ISButton,Info.item,getTextManager,ISPanel,Info.person=oldButton,oldItem,oldText,oldPanel,oldPerson
return table.concat(measures,"; ")
