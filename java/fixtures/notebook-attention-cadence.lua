-- NotebookWindow is the production Window with its real prerender method extracted.
local Window=assert(NotebookWindow, "production notebook window methods are loaded")
local clock=0
local oldClock,oldNative=getTimestampMs,ISCollapsableWindowJoypad
getTimestampMs=function() return clock end
ISCollapsableWindowJoypad={prerender=function() end}
local pageA,pageB={},{}
local active=pageA
local updates,refreshes=0,0
local button={visible=false,setVisible=function(self,value) self.visible=value end}
local window={panel={getActiveView=function() return active end},homeAttentionBtn=button,
    playerNum=0,knoxBaseId="one",isCollapsed=false,
    isVisible=function() return true end,
    refreshContent=function(self) refreshes=refreshes+1; self.refreshedView=active;
        self.nextRefreshAt=clock+2000; self.homeAttentionDirty=true end,
    updateHomeAttention=function(self) updates=updates+1; button.visible=true end,
    layoutSheetHeader=function() end,syncResizeGeometry=function() return false end}
setmetatable(window,{__index=Window})
window:prerender()
assert(updates==1 and refreshes==1, "initial render refreshes both")
clock=1999; window:prerender(); window:prerender()
assert(updates==1 and refreshes==1, "render frames inside cadence do not rescan")
clock=2000; window:prerender()
assert(updates==2 and refreshes==2, "the two-second page cadence refreshes the pill")
active=pageB; window:prerender()
assert(updates==3 and refreshes==3, "switching view refreshes immediately")
window.knoxBaseId="two"; window:prerender()
assert(updates==4 and refreshes==3, "switching base refreshes attention immediately")
window.playerNum=1; window:prerender()
assert(updates==5, "switching player refreshes immediately")
window.homeAttentionDirty=true; window:prerender()
assert(updates==6, "explicit page refresh invalidates the pill")
window.isCollapsed=true; window:prerender()
assert(not button.visible and updates==6, "collapsed windows hide without scanning")
window.isCollapsed=false; window:prerender()
assert(updates==7, "reopening restores attention immediately")
getTimestampMs,ISCollapsableWindowJoypad=oldClock,oldNative
print("Notebook attention cadence PASS frame=throttled base=view=immediate collapsed=hidden")
