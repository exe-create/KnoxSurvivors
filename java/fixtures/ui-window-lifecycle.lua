local L=assert(KnoxSurvivorUILayout)
local oldCore,oldWidth,oldHeight,oldEvents=getCore,getScreenWidth,getScreenHeight,Events
local oldTracked,oldHook=L.tracked,L.resolutionHookInstalled
local screenW,screenH=1280,720
getScreenWidth,getScreenHeight=nil,nil
getCore=function() return {getScreenWidth=function() return screenW end,
    getScreenHeight=function() return screenH end} end
local callback,subscriptions=nil,0
Events={OnResolutionChange={Add=function(fn) callback=fn;subscriptions=subscriptions+1 end}}
L.tracked={};L.resolutionHookInstalled=false
local width,height=L.screenSize()
assert(width==1280 and height==720,"window bounds use the installed Core screen API")
local function window(x,y,w,h)
    local value={x=x,y=y,width=w,height=h,visible=true,removed=0}
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:setX(v) self.x=v end
    function value:setY(v) self.y=v end
    function value:setWidth(v) self.width=v end
    function value:setHeight(v) self.height=v end
    function value:isVisible() return self.visible end
    function value:removeFromUIManager() self.removed=self.removed+1;return "removed" end
    return value
end
local first=window(1100,650,760,600)
local second=window(100,90,400,300)
L.trackWindow(first);L.trackWindow(first);L.trackWindow(second)
assert(subscriptions==1 and first.x+first.width<=1272 and first.y+first.height<=712,
    "tracking clamps each window and registers one resolution callback")
screenW,screenH=640,480
callback()
assert(first.x>=8 and first.y>=8 and first.x+first.width<=632 and first.y+first.height<=472,
    "resolution changes iterate window keys and clamp the real window")
assert(second:removeFromUIManager()=="removed" and second.removed==1 and L.tracked[second]==nil,
    "removed windows release tracking without losing native removal")
L.trackWindow(second)
assert(second:removeFromUIManager()=="removed" and second.removed==2 and L.tracked[second]==nil,
    "retracking does not stack removal wrappers")
L.tracked,L.resolutionHookInstalled=oldTracked,oldHook
getCore,getScreenWidth,getScreenHeight,Events=oldCore,oldWidth,oldHeight,oldEvents
print("UI window lifecycle PASS installedCore=true resolution=true bounds=true removedReleased=true noDuplicateHook=true")
