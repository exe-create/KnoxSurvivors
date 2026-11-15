local sync=assert(KnoxBugReportSync)
local oldMain,oldUI,oldText,oldFont=MainScreen,UIManager,getTextManager,UIFont
UIFont={Small=1,Medium=2}
local fontReads,uiReads=0,0
getTextManager=function() fontReads=fontReads+1;return {
    getFontHeight=function(_,font) return 14 end,MeasureStringX=function(_,font,text) return #text*7 end} end
local function rectangle(x,y,w,h)
    local c={x=x,y=y,width=w,height=h,visible=true}
    function c:isVisible() return self.visible end
    function c:setVisible(v) self.visible=v end
    for _,key in ipairs({"X","Y","Width","Height"}) do
        c["get"..key]=function(self) return self[key:lower()] end
        c["set"..key]=function(self,v) self[key:lower()]=v end
    end
    return c
end
local button=rectangle(0,0,100,26)
local main=rectangle(0,0,1024,768);main.visible=false;main.inGame=true;main.javaObject={}
main.knoxBugButton=button;main.bottomPanel=rectangle(100,200,200,300)
function main:getChildren() return {button,self.bottomPanel} end
local top=rectangle(0,0,1024,70)
UIManager={getUI=function() uiReads=uiReads+1
    local list={rectangle(0,0,1024,768),main.javaObject,top}
    return {size=function() return #list end,get=function(_,i) return list[i+1] end}
end}
MainScreen={instance=main}
sync()
assert(not button.visible and fontReads==0 and uiReads==0,"gameplay performs no report geometry or overlay scans")
main.visible=true;sync()
assert(button.visible and button.y>=70 and button.x+button.width<=main.width,
    "pause button avoids later overlays and ignores the underlying full-screen HUD")
UIManager.getUI=function() error("unreadable registry") end;sync()
assert(not button.visible,"unknown overlay state hides the report button")
main.bottomPanel.visible=false;local before=fontReads;sync()
assert(not button.visible and fontReads==before,"a pause submenu hides without doing layout work")
MainScreen,UIManager,getTextManager,UIFont=oldMain,oldUI,oldText,oldFont
print("Bug report pause PASS gameplay=idle collision=avoided unreadable=hidden")
