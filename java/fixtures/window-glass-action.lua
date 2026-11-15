local C=assert(KnoxAutonomyController)
local oldAction,oldQueue,oldServer=ISRemoveBrokenGlass,ISTimedActionQueue,isServer
local Base={derive=function() return {} end,new=function(self,character)
 return setmetatable({character=character},{__index=self}) end}
ISRemoveBrokenGlass=nativeGlassActionFactory(Base)
isServer=function() return false end
local character={isTimedActionInstant=function() return false end,
 getCharacterActions=function() return {isEmpty=function() return true end} end}
local window={removed=false,index=1,isGlassRemoved=function(self) return self.removed end,
 isSmashed=function() return true end,getObjectIndex=function(self) return self.index end,
 removeBrokenGlass=function(self) self.removed=true end}
local added=0
ISTimedActionQueue={queues={}}
ISTimedActionQueue.add=function(action)
 added=added+1
 local q={queue={action}};ISTimedActionQueue.queues[character]=q;return q
end
local c=setmetatable({id="glass-person",character=character,bridge={getNpcWindowForGlassRemoval=function(_,id)
 assert(id=="glass-person");return window end}},C)
assert(c:prepareRouteWindowGlass("Transition:WINDOW_GLASS_REQUIRED",10)=="waiting" and added==1 and not window.removed,
 "glass crossing queues the installed native action without instantly clearing the window")
assert(c:prepareRouteWindowGlass(nil,11)=="waiting" and added==1,
 "pending native action is not duplicated or crossed while unfinished")
local action=c.windowGlassAction.action
assert(action.window==window and action.character==character and action:isValid(), "action uses exact route window and real actor")
assert(action:complete() and window.removed, "installed native completion produces real glass removal")
ISTimedActionQueue.queues[character]=nil
assert(c:prepareRouteWindowGlass(nil,120)=="ready" and c.windowGlassAction==nil,
 "movement resumes only after queue completes and glass receipt is observed")
window.removed=false
assert(c:prepareRouteWindowGlass("Transition:WINDOW_GLASS_REQUIRED",130)=="waiting", "second damaged window can queue")
ISTimedActionQueue.queues[character]=nil
assert(c:prepareRouteWindowGlass(nil,131)=="failed" and not window.removed,
 "cancelled glass removal reaches ordinary route failure instead of climbing or silently repeating")
window.index=-1
assert(c:prepareRouteWindowGlass("Transition:WINDOW_GLASS_REQUIRED",140)=="failed" and added==2,
 "removed window refuses action and cannot invent success")
ISRemoveBrokenGlass,ISTimedActionQueue,isServer=oldAction,oldQueue,oldServer
print("Window glass PASS installedNativeAction=true exactWindow=true pendingUnique=true receipt=true cancelledRefused=true")
