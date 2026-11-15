local C=assert(codecMissionComposer)
local rows={}
for i=1,100 do rows[i]={item="composer-"..tostring(i)} end
local scroll,changes=0,0
local view={missionCrew={items=rows},missionSelected={},
    getYScroll=function() return scroll end,
    setYScroll=function(_,value) scroll=value;changes=changes+1 end}
C.selectAll(view)
assert(#C.members(view)==100,"select all has no crew-size ceiling")
view.missionSelected["composer-50"]=false
assert(#C.members(view)==99,"individual choices survive without substitution")
C.selectAll(view)
assert(#C.members(view)==100,"select all completes a partial selection")
C.selectAll(view)
assert(#C.members(view)==0,"the same control clears the full selection")
assert(C.scrollPage(view,-1) and scroll==30 and changes==1,
    "a child wheel event moves the page once instead of a nested list")
print("Mission composer PASS hundredCrew=true exactSelection=true allClear=true singleScroller=true")
