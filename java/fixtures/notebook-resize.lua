local Window=assert(NotebookWindow)
local oldLeft,oldTop,oldWidth,oldHeight=getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight
getPlayerScreenLeft=function() return 100 end;getPlayerScreenTop=function() return 50 end
getPlayerScreenWidth=function() return 800 end;getPlayerScreenHeight=function() return 600 end
local function control(w,h)
    local c={width=w,height=h}
    for _,key in ipairs({"Width","Height","X","Y"}) do
        c["set"..key]=function(self,value) self[key:lower()]=value end
    end
    return c
end
local page=control(760,450)
function page:getScrollHeight() return self.scrollHeight or 0 end
function page:getScrollWidth() return self.scrollWidth or 0 end
function page:setScrollHeight(n) self.scrollHeight=n end
function page:setScrollWidth(n) self.scrollWidth=n end
function page:getYScroll() return self.scroll or 0 end
function page:setYScroll(n) self.scroll=n end
local layouts=0
function page:layoutPage() layouts=layouts+1 end
local panel=control(760,500);panel.tabHeight=30;panel.viewList={{view=page}};page.parent=panel
function panel:getActiveView() return page end
local window=control(760,560)
window.playerNum=0;window.minimumWidth=320;window.minimumHeight=280;window.panel=panel;window.x=120;window.y=70
function window:getX() return self.x end;function window:getY() return self.y end
function window:sheetHeaderHeight() return 80 end;function window:resizeWidgetHeight() return 16 end
setmetatable(window,{__index=Window})
window:resizeToViewport(2000,2000)
assert(window.width==780 and window.height==580,"native drag is bounded to the player's viewport")
window:resizeToViewport(10,10)
assert(window.width==320 and window.height==280,"native drag respects minimum usable dimensions")
assert(window:syncResizeGeometry(1000) and panel.width==320 and panel.height==184 and panel.y==80,
    "resized tab panel clears the actual header and native grip")
assert(page.width==320 and page.height==154 and layouts==1,"all page bounds refit and active controls relayout")
assert(window.knoxResizeRefreshAt==1150 and not window:syncResizeGeometry(1050),
    "unchanged frames preserve one deferred refresh instead of rescanning")
window.width=640;window.height=440
assert(window:syncResizeGeometry(1100) and page.width==640 and page.height==314
    and layouts==2 and window.knoxResizeRefreshAt==1250,"continued dragging postpones the expensive refresh")
window.x=890;window.y=640;window:resizeToViewport(320,280)
assert(window.width==10 and window.height==10,"viewport clamp wins when the window was moved near the edge")
getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight=oldLeft,oldTop,oldWidth,oldHeight
print("Notebook resize PASS nativeDragBounds=true pageBounds=true debounce=true")
