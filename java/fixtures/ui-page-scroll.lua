-- Real shared page binding, including an inherited non-nil wheel no-op.
local L=assert(KnoxSurvivorUILayout)
local inherited={onMouseWheel=function() return false end}
local function page()
 local p=setmetatable({width=400,height=100,parent={width=400,height=220,tabHeight=20},scroll=0,extent=0,
  knoxContentHeight=600,prerender=function() end,render=function() end}, {__index=inherited})
 function p:setWidth(v) self.width=v end
 function p:setHeight(v) self.height=v end
 function p:getScrollHeight() return self.extent end
 function p:setScrollHeight(v) self.extent=v end
 function p:getScrollWidth() return self.scrollWidth end
 function p:setScrollWidth(v) self.scrollWidth=v end
 function p:getYScroll() return self.scroll end
 function p:setYScroll(v) self.scroll=v end
 function p:getScrollAreaHeight() return self.height end
 function p:setScrollChildren(v) self.scrollChildren=v end
 function p:setScrollWithParent(v) self.scrollWithParent=v end
 function p:addScrollBars() self.vscroll={setVisible=function(bar,v) bar.visible=v end} end
 function p:setStencilRect() end
 function p:clearStencilRect() end
 return p
end
for _,name in ipairs({"Base & Work","Crew & Schedule","Stores & Storage","Missions","World"}) do
 local p=page();L.bindView(p)
 assert(p.vscroll.visible and p.extent==600, name.." initially has real overflow")
 assert(p:onMouseWheel(1) and p.scroll==-30, name.." wheels despite inherited native no-op")
 p:onMouseWheel(100)
 assert(p.scroll==-400, name.." clamps at the actual page bottom")
 p.knoxContentHeight=120;p:prerender()
 assert(p.extent==200 and not p.vscroll.visible and p.scroll==0,
  name.." hides scrollbar and clears stale scroll when content fits")
 assert(p:onMouseWheel(1)==false and p.scroll==0, name.." does not scroll an already fitting page")
 p.knoxContentHeight=350;p:prerender()
 assert(p.vscroll.visible and p.extent==350, name.." overflow returning restores usable scroll")
end
local custom=page();local calls=0
custom.onMouseWheel=function() calls=calls+1;return true end
L.bindView(custom);custom:onMouseWheel(1)
assert(calls==1 and custom.scroll==0, "explicit child/custom handler is not scrolled a second time")
local native=page();native.knoxContentHeight=nil;native.extent=900
L.bindView(native);native:prerender()
assert(native.extent==900, "unmanaged native Skills-like page keeps its measured extent")
print("Page scroll PASS inheritedWheel=true fitsHidden=true dynamicExtent=true customPreserved=true nativeExtent=true")
