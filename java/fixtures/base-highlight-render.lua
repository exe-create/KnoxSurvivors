local oldEvents,oldHighlights,oldP,oldCell,oldCore,oldCompat=Events,KnoxBaseHighlights,KnoxPersistence,getCell,getCore,KnoxViewpointCompatibility
local callback,draws,draft= nil,{},false
Events={OnPreUIDraw={Add=function(fn) callback=fn end,Remove=function(fn) assert(fn==callback);callback=nil end},
    OnTick={Add=function() error("frame highlights cannot be tied to simulation ticks") end}}
local function square(x,y) return {getX=function() return x end,getY=function() return y end,getZ=function() return 0 end} end
local hovered=square(6,8)
KnoxBaseHighlights={BOUNDARY_COLOUR={r=.3,g=.6,b=.3},INVALID_COLOUR={r=1,g=0,b=0,a=.38},
    setDraft=function(_,value) draft=value end,workColour=function(_,a) return {r=.4,g=.6,b=.2,a=a} end,
    pickMouseSquare=function() return hovered,hovered:getX(),hovered:getY(),0 end,
    drawArea=function(...) draws[#draws+1]={...} end}
KnoxPersistence={getBase=function() return {zones={}} end}
getCore=function() return nil end
KnoxViewpointCompatibility=nil
for _,factory in ipairs({zoneRenderFactory,territoryRenderFactory}) do
    local hook,unhook=factory()
    local player={getPlayerNum=function() return 0 end,isDead=function() return false end}
    local selection={player=player,firstSquare=square(2,3),baseId="home",zoneType="farming",cursor={}}
    function selection:onSquareSelectedCancel() self.cancelled=true;unhook(self) end
    getCell=function() return {getDrag=function() return selection.cursor end} end
    hook(selection);assert(callback and draft,"selection registers one render callback")
    draws={};callback();callback()
    assert(#draws==4 and draws[1][2]==2 and draws[1][4]==6,
        "each rendered frame redraws the exact proposed area and cursor tile")
    assert(draws[1][7].a==.16 and draws[2][7].a==.8,"draft fill is subdued and cursor distinct")
    selection.pendingConfirm=true;selection.pendingSecond=square(5,7);hovered=square(90,90)
    getCell=function() return {getDrag=function() return nil end} end
    draws={};callback()
    assert(not selection.cancelled and #draws==2 and draws[1][4]==5 and draws[1][5]==7,
        "confirmation retains the chosen area even after the cursor moves or clears")
    unhook(selection);assert(callback==nil and not draft,"cancellation releases rendering and draft state")
    hovered=square(6,8)
end
Events,KnoxBaseHighlights,KnoxPersistence,getCell,getCore,KnoxViewpointCompatibility=oldEvents,oldHighlights,oldP,oldCell,oldCore,oldCompat
print("Highlight render PASS perFrame=true confirmation=fixed cleanup=true")
