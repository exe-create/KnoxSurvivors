-- Constructs and opens the real creator window, drives every page's populate
-- entry, creates groups of several descriptors, changes one group's descriptor
-- through the page control, saves through the real commit, decodes the saved
-- file and closes through the real teardown. Widget classes and the user
-- directory file handle are the boundary doubles; the panel and roster model are
-- production code.
local C=assert(KnoxCreator)
local prior={
 print=print,text=getTextManager,reader=getFileReader,writer=getFileWriter,panel=ISPanel,
 button=ISButton,combo=ISComboBox,model=ISUI3DModel,frame=ISCollapsableWindowJoypad,
 cards=Cards,detail=Detail,cell=Cell,directions=IsoDirections,
 screenW=getPlayerScreenWidth,screenH=getPlayerScreenHeight,
 screenL=getPlayerScreenLeft,screenT=getPlayerScreenTop}
print=function() end
-- Font metrics are a boundary: the layout module asks the engine for the width.
getTextManager=function() return {
 MeasureStringX=function(self,font,text) return #tostring(text)*7 end,
 getFontHeight=function() return 14 end} end

local function widget(props)
 local o=props or {}
 o.children={}
 o.visible=true
 o.applies=0
 function o:initialise() end
 function o:addChild(c) self.children[#self.children+1]=c; c.parent=self end
 function o:setVisible(v) self.visible=v end
 function o:isVisible() return self.visible end
 function o:setX(v) self.x=v end
 function o:setY(v) self.y=v end
 function o:getX() return self.x or 0 end
 function o:getY() return self.y or 0 end
 function o:setWidth(v) self.width=v end
 function o:setHeight(v) self.height=v end
 function o:getWidth() return self.width or 0 end
 function o:getHeight() return self.height or 0 end
 function o:setTitle(v) self.title=v end
 function o:setName(v) self.name=v end
 function o:setEnable(v) self.enabled=v end
 function o:applyScroll() self.applies=self.applies+1 end
 function o:addScrollChild(c,y) c.knoxBaseY=y end
 function o:drawRect() self.draws=(self.draws or 0)+1 end
 function o:drawText() self.draws=(self.draws or 0)+1 end
 function o:drawTextureScaled() end
 function o:drawRectBorder() end
 function o:clear() self.items={} end
 function o:addItem(text,item) self.items[#self.items+1]={text=text,item=item} end
 function o:getYScroll() return 0 end
 function o:titleBarHeight() return 24 end
 function o:addToUIManager() self.inManager=true end
 function o:removeFromUIManager() self.inManager=false end
 function o:bringToTop() end
 return o
end

local List={}
function List:new(x,y,w,h)
 return setmetatable({x=x,y=y,width=w,height=h,items={},draws={}}, {__index=self})
end
function List:initialise() end
function List:instantiate() end
function List:getYScroll() return 0 end
function List:clear() self.items={} end
function List:addItem(text,item) self.items[#self.items+1]={text=text,item=item} end
function List:drawRect() end
function List:drawText() end
local Label={}
function Label:new(x,y,h,name,r,g,b,a,font,left)
 return setmetatable({x=x,y=y,height=h,width=180,name=name,visible=true}, {__index=self})
end
function Label:initialise() end
function Label:setName(v) self.name=v end
function Label:setVisible(v) self.visible=v end
function Label:isVisible() return self.visible end

local main={instance=nil,bottomPanel={children={},height=300}}
main.instance=main
function main.bottomPanel:setVisible(v) self.visible=v end
function main.bottomPanel:isVisible() return self.visible~=false end
function main.bottomPanel:getHeight() return self.height end
function main.bottomPanel:setHeight(h) self.height=h end

local Button={}
function Button:new(x,y,w,h,label,target,callback)
 return widget({x=x,y=y,width=w,height=h,label=label,target=target,callback=callback})
end
local Combo={}
function Combo:new(x,y,w,h,target,callback)
 local o=widget({x=x,y=y,width=w,height=h,target=target,callback=callback,options={},selected=1})
 function o:clear() self.options={}; self.selected=1 end
 function o:addOptionWithData(label,data) self.options[#self.options+1]={text=label,data=data} end
 function o:getOptionData(index) return self.options[index].data end
 return o
end
ISComboBox=Combo
local Cards={}
function Cards:new(x,y,w,h,win)
 local o=widget({x=x,y=y,width=w,height=h,window=win,renders=0})
 o.render=Cards.render
 return o
end
function Cards:render() self.renders=(self.renders or 0)+1 end
local Detail={}
function Detail:new(x,y,w,h) return widget({x=x,y=y,width=w,height=h,scrollY=0,page="person"}) end
local Cell={}
function Cell:new(x,y,w,h,slot) return widget({x=x,y=y,width=w,height=h,slot=slot}) end
local Model={}
function Model:new(x,y,w,h) return widget({x=x,y=y,width=w,height=h}) end
local Frame={}
function Frame:new(x,y,w,h)
 local o=widget({x=x,y=y,width=w,height=h})
 -- The engine window's initialise builds the children; the generic widget's own
 -- no-op must not shadow it.
 o.initialise=function(self) self:createChildren() end
 return o
end
function Frame:createChildren() end

ISButton,ISUI3DModel,ISCollapsableWindowJoypad=Button,Model,Frame
ISPanel={new=function(self,x,y,w,h) return widget({x=x,y=y,width=w,height=h}) end}
-- The fixture's locals shadow the names the panel resolves as globals.
_G.Cards,_G.Detail,_G.Cell=Cards,Detail,Cell
IsoDirections={S=1}
getPlayerScreenWidth=function() return 1920 end
getPlayerScreenHeight=function() return 1080 end
getPlayerScreenLeft=function() return 0 end
getPlayerScreenTop=function() return 0 end

local files={}
getFileReader=function(path)
 local content=files[path]
 if not content then return nil end
 local lines={}
 for line in string.gmatch(content,"[^\r\n]+") do lines[#lines+1]=line end
 local i=0
 return {readLine=function() i=i+1; return lines[i] end,close=function() end}
end
getFileWriter=function(path)
 return {write=function(_,value) files[path]=value end,close=function() end}
end

local W,P,Panel=creatorUiFactory({List=List,Label=Label,
 Main={instance=main,prerenderBottomPanelLabel=function() end},
 Font={Small=1,Medium=2,Large=3},
 Transition={new=function() return {setFadeIn=function() end} end},
 textManager=function() return {MeasureStringX=function() return 180 end,
  getFontHeight=function() return 14 end} end,
 soundManager=function() return {playUISound=function() end} end})
assert(Panel~=nil and W~=nil,"the panel source under test is loaded")

-- The item list opens with a bounded number of rows and always has a way out.
local many={}
for i=1,250 do many[i]={fullType="Base.Item"..i,label="Item "..i} end
local fakeList={items={},clear=function(self) self.items={} end,
 addItem=function(self,text,item) self.items[#self.items+1]={text=text,item=item} end}
local fakeSearch={text="",getText=function(self) return self.text end}
local picker={entries=many,list=fakeList,search=fakeSearch}
P.populate(picker)
assert(#fakeList.items==P.MAX_ROWS,"the picker adds only its row cap")
assert(picker.matchCount==250 and picker.shownCount==P.MAX_ROWS,
 "the picker counts every match and shows the cap")
fakeSearch.text="Item 25"
P.populate(picker)
assert(#fakeList.items==4,"word search matches Item 25, 125, 225 and 250")
fakeSearch.text="250 Item"
P.populate(picker)
assert(picker.shownCount==1 and picker.matchCount==1 and fakeList.items[1].item.fullType=="Base.Item250",
 "search words work in either order against names and item IDs")
local parent={picker=picker}
picker.parent=parent
parent.removeChild=function() end
picker.setVisible=function() end
picker.removeFromUIManager=function() end
P.close(picker)
assert(parent.picker==nil,"the picker's own close releases the window's handle")

-- Escape backs out the list before the editor.
_G.Keyboard={KEY_ESCAPE=27}
local escPick={closed=false,close=function(self) self.closed=true end}
local escWin=setmetatable({closed=false,picker=escPick,
 onClose=function(self) self.closed=true end},{__index=W})
assert(W.onKeyDown(escWin,27)==true and escPick.closed and not escWin.closed,
 "Escape closes the open list, not the editor")
local escWin2=setmetatable({closed=false,picker=nil,
 onClose=function(self) self.closed=true end},{__index=W})
W.onKeyDown(escWin2,27)
assert(escWin2.closed,"with no list open, Escape closes the editor")

local priorHair,priorBeard=getAllHairStyles,getAllBeardStyles
getAllHairStyles=function(female)
 local list=female and {"","Long"} or {"","Short"}
 return {size=function() return #list end,get=function(self,n) return list[n+1] end}
end
getAllBeardStyles=function() return {size=function() return 2 end,get=function(self,n) return ({"","Full"})[n+1] end} end

Panel.window=nil
Panel.hiddenMenu=nil
local win=Panel.open()
assert(win~=nil,"the real open path returns a window")
assert(win.hideDefaults==true and win.hideCustom==false,"creator opens with defaults hidden and custom groups shown")
assert(Panel.window==win,"the open path installs the window on the panel")
assert(win.visible==true and win.inManager==true,"the opened window is visible and in the UI manager")
assert(main.bottomPanel.visible==false,"open hides the menu column it must restore")
assert(#win.pageButtons==4,"the window built its four page controls")
assert(#win.cells>0 and #win.groupButtons==11,"the window built its slot cells, default edit/reset and group controls")
for _, combo in ipairs(win.fieldCombos) do assert(combo.knoxKind~="kit","creator has no Kit control") end

local tabCounts={}
for _,button in ipairs(win.pageButtons) do
 local before=win.detail.applies
 win:onPage(button)
 win.cards:render()
 local after=win.detail.applies
 assert(after>before,"tab "..tostring(button.knoxPage).." populates its page")
 tabCounts[#tabCounts+1]=tostring(button.knoxPage).."="..tostring(after-before)
end
assert(#tabCounts==4,"all four tabs were driven")

local kinds={"household","household","robbers","robbers","looters","cannibals"}
local names={"Barley","Voss","Road Robbers","Bridge Robbers","Depot Crew","Meat House"}
local kindAt,nameAt=1,1
win.openChooser=function(self,entries,caption,accept)
 local chosen=kinds[kindAt]
 kindAt=kindAt+1
 for _,entry in ipairs(entries) do
  if entry.fullType==chosen then accept(chosen); return end
 end
 assert(false,"the kind is offered: "..tostring(chosen))
end
win.promptFor=function(self,caption,accept)
 local name=names[nameAt]
 nameAt=nameAt+1
 accept(name)
end
for _=1,6 do win:onRailRow({kind="new"}) end
assert(#win.group.defs==6,"six created groups are six records")

local target=win.group.defs[#win.group.defs]
assert(C.profileFor(target.id,win.group.defs).profile=="cannibals",
 "the sixth group starts as a cannibal group")
win:selectFaction(target.id)
local profileButton=nil
for _,button in ipairs(win.groupButtons) do
 if button.knoxKind=="profile" then profileButton=button end
end
assert(profileButton~=nil,"the group page has a descriptor control")
local offeredKinds=nil
local function chooseKind(value)
 win.openChooser=function(self,entries,caption,accept)
  offeredKinds={}
  for _,entry in ipairs(entries) do offeredKinds[#offeredKinds+1]=entry.fullType end
  accept(value)
 end
 win:onGroupPolicy(profileButton)
end
for _,descriptor in ipairs({"household","looters","robbers"}) do
 chooseKind(descriptor)
 assert(C.profileFor(target.id,win.group.defs).profile==descriptor,
  "the kind control stores "..descriptor.." on the group record")
end
local function offered(id)
 for _,value in ipairs(offeredKinds or {}) do if value==id then return true end end
 return false
end
assert(offered("household") and offered("robbers") and offered("looters") and offered("cannibals"),
 "the kind control offers every group descriptor")
assert(not offered("solo"),"solo is not offered as a group kind")
assert(not offered("police") and not offered("military"),
 "shipped default factions are starting templates, not group kinds")
assert(win.dirty==true,"the descriptor change marks the file unsaved")

-- Every group gets its own name, zone and hostility through the Group page, so
-- groups sharing a descriptor stay distinguishable records.
local byDescriptor={}
for _,entry in ipairs(win.group.defs) do
 local profile=C.profileFor(entry.id,win.group.defs).profile
 byDescriptor[profile]=byDescriptor[profile] or {}
 byDescriptor[profile][#byDescriptor[profile]+1]=entry
end
local households,robberGroups,looterGroups=
 byDescriptor.household,byDescriptor.robbers,byDescriptor.looters
assert(#households==2 and #robberGroups==3 and #looterGroups==1,
 "the created groups resolve to their descriptors before editing")
local function policyButton(kind)
 for _,button in ipairs(win.groupButtons) do
  if button.knoxKind==kind then return button end
 end
 assert(false,"the group page has a "..kind.." control")
end
local function setPolicy(groupId,kind,value)
 win:selectFaction(groupId)
 win.openChooser=function(self,entries,caption,accept)
  local found=false
  for _,entry in ipairs(entries) do if entry.fullType==value then found=true end end
  assert(found,"the "..kind.." control offers "..value)
  accept(value)
 end
 win:onGroupPolicy(policyButton(kind))
 assert(C.profileFor(groupId,win.group.defs)[kind]==value,
  "the "..kind.." control stores "..value)
end
setPolicy(households[1].id,"spawnContext","household")
setPolicy(households[1].id,"attitude","friendly")
setPolicy(households[2].id,"spawnContext","any")
setPolicy(households[2].id,"attitude","neutral")
setPolicy(robberGroups[1].id,"spawnContext","any")
setPolicy(robberGroups[1].id,"attitude","hostile")
setPolicy(robberGroups[2].id,"spawnContext","law_enforcement")
setPolicy(robberGroups[2].id,"attitude","random")
setPolicy(target.id,"spawnContext","military")
setPolicy(target.id,"attitude","neutral")
setPolicy(looterGroups[1].id,"spawnContext","medical")
setPolicy(looterGroups[1].id,"attitude","friendly")
assert(C.profileFor(households[1].id,win.group.defs).spawnContext
  ~=C.profileFor(households[2].id,win.group.defs).spawnContext
 and C.profileFor(households[1].id,win.group.defs).attitude
  ~=C.profileFor(households[2].id,win.group.defs).attitude,
 "two households share a descriptor but differ in zone and hostility")
assert(C.profileFor(robberGroups[1].id,win.group.defs).spawnContext
  ~=C.profileFor(robberGroups[2].id,win.group.defs).spawnContext,
 "two robber groups differ in zone")

local function policyRow(entry,defs)
 local policy=C.profileFor(entry.id,defs) or {}
 return tostring(entry.label).."|"..tostring(policy.profile).."|"
  ..tostring(policy.spawnContext).."|"..tostring(policy.attitude)
end
local expectedRows,expectedList={},{}
for _,entry in ipairs(win.group.defs) do
 local row=policyRow(entry,win.group.defs)
 expectedRows[entry.id]=row
 expectedList[#expectedList+1]=row
end

-- The Add person control, not the roster model, must make the ungrouped person.
win:selectFaction("solo")
assert(win.templateRoster==nil,"the solo bucket is not a preview of a group")
win.detailPage="group";win:refresh()
assert(not win.groupButtons[1].enabled and win.groupButtons[2].knoxHidden,"solo page replaces shared policies with a quiet independent-survivor explanation")
local beforeAdd=#win.roster
win.promptFor=function(self,caption,accept) accept("Wren Solo") end
win:onAddPerson()
assert(#win.roster==beforeAdd+1,"the Add person control adds exactly one person")
local soloPerson=win.roster[#win.roster]
assert(soloPerson.name=="Wren Solo","the typed name is the added person's name")
assert(C.personFactionId(soloPerson,win.group)=="solo",
 "the Add person control makes an ungrouped person")
assert(C.recordFor(soloPerson,{defs=win.group.defs}).profile=="solo",
 "the added person records as a solo survivor")
assert(#C.peopleByFaction(win.roster,win.group,"solo")==1,
 "the solo survivor belongs to no group")
-- Drive the real native-dropdown callback, including sex-specific validity.
soloPerson.hair="Short";soloPerson.beard="Full";soloPerson.skin=3
win:refresh()
local fields={}
for _,combo in ipairs(win.fieldCombos) do fields[combo.knoxKind]=combo end
assert(fields.sex and fields.hair and fields.beard and fields.look,"appearance uses native dropdown controls")
assert(#fields.faction.options==#win.group.defs+1,"membership offers actual groups and independence, not uncreated templates")
fields.sex.selected=2
fields.sex.callback(fields.sex.target,fields.sex)
assert(soloPerson.female and soloPerson.hair=="" and soloPerson.beard=="" and soloPerson.skin==3,
 "changing sex clears incompatible styles without randomizing skin")
fields.hair.selected=2
fields.hair.callback(fields.hair.target,fields.hair)
assert(soloPerson.hair=="Long" and soloPerson.skin==3 and fields.beard.disabled,
 "the hair dropdown applies an available female style and disables beard selection")
getAllHairStyles,getAllBeardStyles=priorHair,priorBeard
win.dirty=true

local saved=win:commit()
assert(saved==true,"the panel commit writes the roster file")
assert(type(files[C.FILE])=="string","the saved file exists in the user directory")
local reloaded,reloadedGroup=C.decode(files[C.FILE])
assert(C.profileFor(target.id,reloadedGroup.defs).profile=="robbers",
 "the decoded file carries the changed descriptor")
local households,robbers=0,0
for _,entry in ipairs(reloadedGroup.defs) do
 if entry.profile=="household" then households=households+1
 elseif entry.profile=="robbers" then robbers=robbers+1 end
end
assert(households==2 and robbers==3,"several groups share descriptors as independent records")
local decodedSolo=nil
for _,person in ipairs(reloaded) do
 if person.name=="Wren Solo" then decodedSolo=person end
end
assert(decodedSolo~=nil,"the saved file holds the person the Add person control made")
assert(decodedSolo.faction=="solo","the decoded solo person belongs to no group")
assert(#C.peopleByFaction(reloaded,reloadedGroup,"solo")==1,
 "the decoded solo belongs to no group")
local soloGroupRecord=nil
for _,entry in ipairs(reloadedGroup.defs) do
 if entry.id=="solo" then soloGroupRecord=entry end
end
assert(soloGroupRecord==nil,"no group record was made for the solo person")
local decodedRows,decodedList={},{}
for _,entry in ipairs(reloadedGroup.defs) do
 decodedRows[entry.id]=policyRow(entry,reloadedGroup.defs)
end
for _,entry in ipairs(win.group.defs) do
 assert(decodedRows[entry.id]==expectedRows[entry.id],
  "the decoded group keeps its descriptor, name, zone and hostility: "
  ..tostring(expectedRows[entry.id]).." vs "..tostring(decodedRows[entry.id]))
 decodedList[#decodedList+1]=decodedRows[entry.id]
end

-- New loadout/default interactions execute the production window methods.
local oldPrompt,oldChooser=win.promptFor,win.openChooser
local accepted,offered
win.promptFor=function(self,caption,callback) accepted=callback end
win.openChooser=function(self,entries,caption,callback) offered=entries;accepted=callback end
for _,row in ipairs(win.railRows) do assert(row.solo or row.kind~="faction" or not C.isDefault(row.id),"default filter hides every default") end
win:onToggleDefaults({setTitle=function() end})
local regionalFound=false
for _,row in ipairs(win.railRows) do if row.id=="template_rosewood_police" then regionalFound=true end end
assert(regionalFound,"regional defaults are visible without adding them")
win:selectFaction("police");win:refresh()
local beforeDefault=#win.roster
win:onGroupPolicy({knoxKind="editDefault"})
assert(win.templateRoster and #win.roster==beforeDefault,"default warning precedes mutation")
accepted("WRONG");assert(#win.roster==beforeDefault,"incorrect confirmation changes nothing")
-- Another edit may take a preview name while the confirmation is open.
local takenDraft=C.newDraft();takenDraft.name=win.templateRoster[1].name;takenDraft.faction="solo"
assert(C.add(win.roster,takenDraft));beforeDefault=#win.roster
win:selectFaction("police");win:refresh()
for _,person in ipairs(win.templateRoster) do assert(C.nameKey(person.name)~=C.nameKey(takenDraft.name),"preview respects saved names") end
win:onGroupPolicy({knoxKind="editDefault"});accepted("EDIT")
assert(not win.templateRoster and #win.roster>beforeDefault and C.factionIndexIn(win.group.defs,"police").user,"confirmed default becomes editable")
local names={}
for _,person in ipairs(win.roster) do
 local key=C.nameKey(person.name)
 assert(not names[key],"confirmed default import rechecks names against the whole roster")
 names[key]=true
end
win:onGroupPolicy({knoxKind="resetDefault"});accepted("RESET")
assert(#win.roster==beforeDefault and win.templateRoster,"reset replaces only that default's authored roster")
-- A full library must not create an override or partially append a default.
local originalRoster=win.roster
win.roster={};for i=1,C.MAX_PEOPLE do win.roster[i]={name="Existing "..i,faction="solo"} end
win:selectFaction("police")
win:onGroupPolicy({knoxKind="editDefault"});accepted("EDIT")
assert(#win.roster==C.MAX_PEOPLE and not C.factionIndexIn(win.group.defs,"police").user,
 "full library refuses default edit without storing an override")
win.roster=originalRoster
win:selectFaction(win.group.defs[1].id);win:refresh()
local cargoPerson=assert(win:selected())
cargoPerson.slots.backpack="Base.Bag_Schoolbag"
win:openCargo(cargoPerson,"backpack");accepted("Base.Bandage",{label="Bandage"});accepted("2")
assert(cargoPerson.bagCargo["Base.Bandage"]==2,"backpack editor changes its own destination")
win:openCargo(cargoPerson,"main");accepted("Base.Bandage",{label="Bandage"});accepted("3")
assert(cargoPerson.cargo["Base.Bandage"]==3 and cargoPerson.bagCargo["Base.Bandage"]==2,"main editor preserves backpack contents")
win:onCycleSkill({knoxPerk="Aiming"});accepted("0")
assert(cargoPerson.skills.Aiming==0,"zero skill is explicit")
win:onCycleSkill({knoxPerk="Aiming"});accepted("automatic")
assert(cargoPerson.skills.Aiming==nil,"automatic clears only the chosen override")
win:refresh()
assert(win.infoRows and #win.infoRows>0,"selected loadout exposes scrollable native information")
for _,row in ipairs(win.infoRows) do if not row.knoxHidden then
 assert(row.knoxBaseY+row.height<=win.pageHeights[row.knoxPage],"information rows stay inside their page extent")
end end
win.promptFor,win.openChooser=oldPrompt,oldChooser
win.dirty=false
win:close()
assert(win.visible==false and win.inManager==false,
 "the window leaves the screen and the UI manager")
assert(Panel.window==nil,"the panel forgets the closed window")
assert(main.bottomPanel.visible==true and Panel.hiddenMenu==nil,
 "the hidden menu column is restored")
assert(win.detailPage==nil and win.picker==nil and win.prompt==nil,
 "no page, picker or prompt state survives the close")

print=prior.print
ISPanel=prior.panel
getTextManager=prior.text
getFileReader,getFileWriter=prior.reader,prior.writer
ISButton,ISComboBox,ISUI3DModel,ISCollapsableWindowJoypad=prior.button,prior.combo,prior.model,prior.frame
_G.Cards,_G.Detail,_G.Cell=prior.cards,prior.detail,prior.cell
IsoDirections=prior.directions
getPlayerScreenWidth,getPlayerScreenHeight=prior.screenW,prior.screenH
getPlayerScreenLeft,getPlayerScreenTop=prior.screenL,prior.screenT

return "tabs="..table.concat(tabCounts,",")
 .." addPerson="..tostring(soloPerson.name).." faction="..tostring(soloPerson.faction)
 .." record="..tostring(C.recordFor(soloPerson,{defs=reloadedGroup.defs}).profile)
 .." kindOffers="..table.concat(offeredKinds or {},",")
 .." kindSwitch=cannibals>household>looters>robbers"
 .." groups=household:2,robbers:3,looters:1 records=6"
 .." groupsDetail="..table.concat(expectedList,";")
 .." decodedDetail="..table.concat(decodedList,";")
 .." decodedMatch=true"
 .." decodedDescriptor="..tostring(C.profileFor(target.id,reloadedGroup.defs).profile)
 .." decodedSolo="..tostring(decodedSolo and decodedSolo.faction)
 .." savedPeople="..tostring(#reloaded)
 .." soloUngrouped=1 close=menuRestored"
