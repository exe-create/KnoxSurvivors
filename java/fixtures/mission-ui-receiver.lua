local oldText,oldFont=getTextManager,UIFont
UIFont={Small="small"}
getTextManager=function() return {
    getFontHeight=function() return 18 end,
    MeasureStringX=function(_,_,text) return #text*7 end,
} end
local drawn={}
local list={width=280,height=80,itemheight=48,selected=1,
    getWidth=function(self) return self.width end,
    drawRect=function() end,
    drawText=function(_,text) drawn[#drawn+1]=text end}
local row={text="Food run | Searching - 8 crew",index=1,knoxChip="4 items"}
assert(codecMissionRow.drawEntry(list,0,row,false)==48,
    "mission cards receive the native list, not its owning notebook panel")
assert(#drawn==3 and drawn[1]=="Food run","title, detail and cargo draw without a nonexistent list field")
drawn={}
codecMissionRow.drawEntry(list,120,row,false)
assert(#drawn==0,"offscreen mission rows are culled")
getTextManager,UIFont=oldText,oldFont
print("Mission UI receiver PASS nativeList=true card=true culling=true renderingNative=false")
