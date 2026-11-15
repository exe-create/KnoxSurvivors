-- The native list dispatcher is extracted from the installed game, not mocked.
-- Only drawing, native labels and text/transition objects are boundary doubles.
local C=assert(KnoxCreator)
local priorTextManager=getTextManager
getTextManager=function() return {MeasureStringX=function(self,font,text) return #text*7 end, getFontHeight=function() return 14 end} end
local List={}
function List:new(x,y,w,h)
 return setmetatable({x=x,y=y,width=w,height=h,items={},draws={}}, {__index=self})
end
function List:initialise() end
function List:instantiate() end
function List:getYScroll() return 0 end
function List:drawRect(...) self.draws[#self.draws+1]={...} end
function List:drawText(...) self.draws[#self.draws+1]={...} end
local Label={}
function Label:new(x,y,h,name,r,g,b,a,font,left)
 return setmetatable({x=x,y=y,height=h,width=180,name=name,Type="ISLabel",visible=true}, {__index=self})
end
function Label:initialise() end
function Label:getY() return self.y end
function Label:getX() return self.x end
function Label:getHeight() return self.height end
function Label:getWidth() return self.width end
function Label:setY(y) self.y=y end
function Label:setWidth(w) self.width=w end
function Label:setVisible(v) self.visible=v end
function Label:isVisible() return self.visible end
local options=Label:new(0,100,32,"OPTIONS")
local mods=Label:new(0,170,32,"MODS")
local main={modsOption=mods,optionsOption=options,bottomPanel={children={options,mods},height=300}}
function main.bottomPanel:getChildren() return self.children end
function main.bottomPanel:addChild(c) self.children[#self.children+1]=c;c.parent=self end
function main.bottomPanel:getHeight() return self.height end
function main.bottomPanel:setHeight(h) self.height=h end
local W,P,Panel,syncVisibility=creatorUiFactory({List=List,Label=Label,Main={instance=main,prerenderBottomPanelLabel=function() end},
 Font={Small=1,Large=3},Transition={new=function() return {setFadeIn=function() end} end},
 textManager=function() return {MeasureStringX=function() return 180 end} end,
 soundManager=function() return {playUISound=function() end} end})
local win=setmetatable({roster={},group=C.newGroup(),dirty=false,refresh=function() end,
 addChild=function(self,c) c.parent=self end,setNote=function(self,v) self.note=v end}, {__index=W})
win:createFactionList(12,70,240,600,32)
local list=win.railList
list.items={{item={kind="faction",id="police"}}};list.selected=1
list:invokeOnMouseDownFunction()
assert(win.selectedFactionId=="police" and win:selected()~=nil,
 "native list dispatch selects the faction and shows a preset person")
assert(win.templateRoster and #win.templateRoster==C.profileFor("police",{}).memberCount and #win.roster==0 and not win.dirty,
 "viewing a preset shows planned loadouts without silently saving or spawning people")
assert(win:selected().look=="police", "police preset displays its authored outfit")
assert(C.encode(win.roster,win.group):find("\np|",1,true)==nil, "preview people never leak into saved roster")
local row={item={kind="faction",id="police",label="Police",count=3}}
list:doDrawItem(0,row,false)
assert(#list.draws>=3, "faction text and selection paint on the list surface")
local picked=nil
local picker=setmetatable({onPick=function(id) picked=id end,setVisible=function() end,
 removeFromUIManager=function() end,parent={removeChild=function() end}}, {__index=P})
list:setOnMouseDownFunction(picker,P.onRow)
list.items={{item={fullType="Base.Axe",label="Axe"}}};list.selected=1
list:invokeOnMouseDownFunction()
assert(picked=="Base.Axe", "native item picker callback applies the actual item, not a missing wrapper")
win.promptFor=function(self,caption,accept) accept("River Road Watch") end
win:onUsePreset()
assert(win.templateRoster==nil and win:selected()~=nil and win.dirty and #win.roster>0,
 "Use preset creates and selects real editable people in a personal faction")
assert(win:selectedFaction().user and win:selectedFaction().label=="River Road Watch",
 "personal preset copy keeps a separate stable identity")
local savedPerson=win:selected();local personalId=win.selectedFactionId
win:selectFaction("military")
assert(win.templateRoster and win:selected()~=savedPerson, "switching presets switches visible equipment")
win:selectFaction(personalId)
assert(win:selected()==savedPerson and not win.templateRoster, "returning to personal faction restores authored people")
-- New group asks what kind this group is before naming it, because the old flow
-- made every new faction a household without ever saying so. The chooser itself is
-- a boundary double; addFaction/populateFaction/selectFaction are the real ones.
win.openChooser=function(self,entries,caption,accept)
 assert(caption:find("group",1,true),"the create flow asks what kind of group this is")
 local offered={}
 for _,entry in ipairs(entries) do offered[entry.fullType]=entry.label end
 assert(offered["household"] and offered["looters"] and offered["robbers"] and offered["police"],
  "households, looters, robbers and police are all offered kinds")
 assert(offered["solo"]==nil,"solo is not offered as a group kind")
 local firstFive={}
 for i=1,5 do firstFive[entries[i].fullType]=true end
 assert(entries[1].fullType=="custom" and firstFive.household and firstFive.robbers and firstFive.looters
  and firstFive.cannibals,"the blank custom group and descriptors come before any template")
 assert(entries[6].fullType=="police","the police template follows the descriptors")
 -- Owner direction 2026-11-10: the chooser no longer lists shipped starting
 -- rosters. Police stays as a behaviour kind; it is simply not labelled a
 -- template, because that label is what made the chooser read as a preset menu.
 assert(offered["police"]:find("starting template",1,true)==nil,
  "a profession is offered as a behaviour, not labelled a shipped starting template")
 assert(offered["household"]:find("starting template",1,true)==nil,
  "a descriptor is not labelled a template")
 accept("robbers")
end
win.promptFor=function(self,caption,accept) accept("Creekside Robbers") end
win:onRailRow({kind="new"})
assert(win:selectedFaction() and win:selectedFaction().label=="Creekside Robbers",
 "New group row opens the create flow and names the group the player typed")
assert(win:selectedFaction().profile=="robbers","the chosen kind is stored on the group")
assert(win:selected() and not win.templateRoster,
 "the new group selects its real starter people, not a preview")
assert(C.profileFor(win.selectedFactionId,win.group.defs).attitude=="hostile",
 "a robber group starts from its kind's attitude")
-- The two creator crashes the console log recorded on opening. InventoryItemFactory
-- is a Java class the sandbox never exposes, and a cached miss came back as a Boolean
-- that drawTextureScaled refused (95 times in one session). A miss is nil, always.
local fakeTexture={id="tex"}
local realInstance=rawget(_G,"instanceItem")
_G.instanceItem=function(fullType) return {getTex=function() return fakeTexture end} end
assert(Panel.itemIcon("Base.Present")==fakeTexture,"a real item yields its own texture")
_G.instanceItem=function() return nil end
assert(Panel.itemIcon("Base.Missing")==nil,"an item the engine will not build has no icon")
assert(Panel.itemIcon("Base.Missing")==nil,
 "the cached miss is nil, not the Boolean that crashed drawTextureScaled")
assert(type(Panel.itemIcon("Base.Missing"))~="boolean","a miss is never a Boolean")
_G.instanceItem=realInstance

-- Closing must go through the commit/menu-restore path. The installed native close
-- control is ISCollapsableWindow:close(), which only hides the window
-- (ISCollapsableWindow.lua:55, :134) and left the menu it hid invisible.
local menu={};
menu.setVisible=function(self,v) self.visible=v end
Panel.hiddenMenu=menu
Panel.restoreMainMenu()
assert(menu.visible==true and Panel.hiddenMenu==nil,
 "restoring the menu shows the hidden column once and forgets it")
local priorClose=W.onClose
local routed=false
W.onClose=function() routed=true; return true end
W.close(win)
assert(routed,"the native close control routes through onClose, not a bare hide")
W.onClose=priorClose

local promptAccept
local closeWin=setmetatable({group=C.newGroup(),dirty=true,
 closeColourPicker=function() end,closePicker=function() end,
 commit=function() return false,"backup_failed" end,
 setNote=function(self,v) self.note=v end,
 promptFor=function(self,caption,accept) self.caption=caption;promptAccept=accept end,
 setVisible=function(self,v) self.visible=v end,
 removeFromUIManager=function(self) self.removed=true end}, {__index=W})
local closeMenu={setVisible=function(self,v) self.visible=v end}
Panel.hiddenMenu=closeMenu; Panel.window=closeWin
assert(not closeWin:onClose() and closeWin.dirty and not closeWin.removed,
 "failed save keeps changes open and offers discard")
assert(closeWin.caption:find("Discard changes and close",1,true), "discard choice is explicit")
promptAccept("cancel")
assert(closeWin.dirty and not closeWin.removed, "unconfirmed discard keeps the editor open")
closeWin:onClose();promptAccept("DISCARD")
assert(closeWin.removed and not closeWin.dirty and closeMenu.visible and Panel.window==nil,
 "confirmed discard closes and restores the menu without saving")

local first=Panel.installMenuButton()
assert(first and first.parent==main.bottomPanel and first.name=="KNOX CREATOR",
 "creator entry is a native main-menu label under bottomPanel")
assert(mods.y==202 and options.y==100 and main.bottomPanel.height==332,
 "menu insertion makes room without covering stock labels")
assert(Panel.installMenuButton()==first and mods.y==202 and #main.bottomPanel.children==3,
 "repeated menu checks do not duplicate labels or drift positions")
-- Installed MainScreen.termsOfService is the ordinary always-visible Legal
-- button; only termsOfServiceDialog is an overlaid screen.
main.termsOfService={isVisible=function() return true end}
assert(Panel.mainMenuVisible(), "the ordinary visible Legal button must not hide the creator entry")
syncVisibility()
assert(first:isVisible(), "visibility sync leaves the native creator label visible beside Mods")
main.termsOfServiceDialog={isVisible=function() return true end}
assert(not Panel.mainMenuVisible(), "the actual open legal dialog hides the creator entry")
syncVisibility()
assert(not first:isVisible(), "legal dialog overlay owns the screen while open")
main.termsOfServiceDialog=nil
Panel.window={isVisible=function() return true end}
syncVisibility()
assert(not first:isVisible(), "an open creator still hides its menu entry")
Panel.window=nil
syncVisibility()
assert(first:isVisible(), "closing overlays restores the same single creator entry")
main.inGame=true;main.knoxCreatorOption=nil
assert(Panel.installMenuButton()==nil, "creator is not added to the running-game pause menu")
-- FULL LIFECYCLE: several descriptors as separate groups, edited, saved,
-- reloaded and closed through the real window teardown. Only the widget edge is
-- doubled; group creation, editing, grouping, the codec and close are production
-- code.
local fresh=setmetatable({roster={},group=C.newGroup(),dirty=false,
 refresh=function() end, addChild=function(self,c) c.parent=self end,
 setNote=function(self,v) self.note=v end}, {__index=W})
fresh:createFactionList(12,70,240,600,32)
local kindQueue={"household","household","robbers","robbers","looters"}
local nameQueue={"Barley","Voss","Road Robbers","Bridge Robbers","Depot Scavengers"}
local kindAt, nameAt = 1, 1
fresh.openChooser=function(self,entries,caption,accept)
 local chosen=kindQueue[kindAt]; kindAt=kindAt+1
 for _,entry in ipairs(entries) do
  if entry.fullType==chosen then accept(chosen); return end
 end
 assert(false,"the kind is offered: "..tostring(chosen))
end
fresh.promptFor=function(self,caption,accept)
 local name=nameQueue[nameAt]; nameAt=nameAt+1; accept(name)
end
for _=1,5 do fresh:onRailRow({kind="new"}) end
assert(#fresh.group.defs==5,"five created groups are five records, not one shared faction")
local households, robberGroups, looterGroups = {}, {}, {}
for _,entry in ipairs(fresh.group.defs) do
 if entry.profile=="household" then households[#households+1]=entry
 elseif entry.profile=="robbers" then robberGroups[#robberGroups+1]=entry
 elseif entry.profile=="looters" then looterGroups[#looterGroups+1]=entry end
end
assert(#households==2 and #robberGroups==2 and #looterGroups==1,
 "two households, two robber groups and one looter group coexist as data")
assert(households[1].id~=households[2].id and robberGroups[1].id~=robberGroups[2].id,
 "rival groups of one descriptor keep separate identities")
assert(C.profileFor(robberGroups[1].id,fresh.group.defs).attitude=="hostile",
 "a robber group starts hostile from its kind")
assert(C.profileFor(looterGroups[1].id,fresh.group.defs).settlementPolicy=="mobile",
 "a looter group is mobile from its kind")
assert(C.updateFaction(fresh.group.defs,robberGroups[1].id,{attitude="neutral"})==true,
 "a group's stance is editable")
assert(C.profileFor(robberGroups[1].id,fresh.group.defs).attitude=="neutral",
 "the edit is what the group now answers")
assert(C.updateFaction(fresh.group.defs,robberGroups[1].id,{profile="robbers"})==true)
-- Appearance and loadout edits ride the same person record.
local someone=fresh.roster[1]
someone.look="police"
someone.kit="police"
someone.slots={torso="Base.Shirt_PoliceBlue"}
local someoneRecord=C.recordFor(someone,{defs=fresh.group.defs,factionId=someone.faction})
assert(someoneRecord.look=="police" and someoneRecord.kit=="police",
 "an appearance edit reaches the group record")
assert(type(someoneRecord.slots)=="string" and someoneRecord.slots:find("torso",1,true)~=nil,
 "a clothing edit reaches the group record")
-- A solo survivor belongs to no group at all.
local soloDraft=C.draftForFaction("solo",fresh.group.defs)
soloDraft.name="Wren Solo"
local okSolo, soloPerson=C.add(fresh.roster,soloDraft)
assert(okSolo,"the solo survivor is added")
assert(C.recordFor(soloPerson,{defs=fresh.group.defs}).profile=="solo",
 "a solo survivor is authored as a solo, not as a household")
assert(#C.peopleByFaction(fresh.roster,fresh.group,"solo")==1,
 "the solo survivor sits in no group")
-- Every group is reachable from the rail, and the solo bucket never preview-populates.
for _,entry in ipairs(fresh.group.defs) do
 fresh:selectFaction(entry.id)
 assert(fresh.selectedFactionId==entry.id,"every created group is selectable")
end
fresh:selectFaction("solo")
assert(fresh.templateRoster==nil,"the solo bucket never becomes a faction preview")
-- Save the roster file, then read it back.
local fileText=C.encode(fresh.roster,fresh.group)
local reloadedRoster, reloadedGroup=C.decode(fileText)
local reloadedHouseholds, reloadedRobbers=0,0
for _,entry in ipairs(reloadedGroup.defs) do
 if entry.profile=="household" then reloadedHouseholds=reloadedHouseholds+1
 elseif entry.profile=="robbers" then reloadedRobbers=reloadedRobbers+1 end
end
assert(reloadedHouseholds==2 and reloadedRobbers==2,
 "the saved file keeps separate groups with their descriptors as data")
assert(#C.peopleByFaction(reloadedRoster,reloadedGroup,"solo")==1,
 "the solo survivor is still ungrouped after the reload")
-- Close through the real teardown: no overlay, no retained state, menu back.
local closing=setmetatable({roster=fresh.roster,group=fresh.group,dirty=false,
 visible=true,inManager=true,detailPage="loadout",picker={},prompt={},
 setVisible=function(self,v) self.visible=v end,
 removeFromUIManager=function(self) self.inManager=false end,
 setNote=function(self,v) self.note=v end}, {__index=W})
Panel.hiddenMenu=menu
menu:setVisible(false)
Panel.window=closing
local closedOk=W.close(closing)
assert(closedOk==true,"close completes and reports success")
assert(closing.visible==false and closing.inManager==false,
 "the window leaves the screen and the UI manager")
assert(Panel.window==nil,"the panel no longer points at the closed window")
assert(menu.visible==true and Panel.hiddenMenu==nil,
 "closing restores the hidden main-menu column, so no black screen remains")
assert(closing.detailPage==nil and closing.picker==nil and closing.prompt==nil,
 "no page, picker or prompt state survives the close")
print("Creator lifecycle PASS groups=5 households=2 robbers=2 looters=1 solo=1 reloadGroups=4 closeClean=true")
print("Creator UI flow PASS nativeListDispatch=true presetPreview=true personalCopy=true kindFirstGroup=true nativeMenu=true")


getTextManager=priorTextManager
