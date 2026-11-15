local oldTexture=getTexture
getTexture=function(path) return {path=path,getWidth=function() return 8 end,getHeight=function() return 12 end} end
for _,font in ipairs({14,24}) do
    local layout,Header=notebookHeaderFactory(font)
    local name="A Very Long Faction Household Base"
    for _,width in ipairs({320,480,760}) do
        local h=layout(width,name,"100 residents",true)
        assert(table.concat(h.names," ")==name,"base identity is fully readable")
        for _,line in ipairs(h.names) do
            assert(#line*(font+4)*0.55<=width-58,"header text leaves close corner clear")
        end
        assert(table.concat(h.details," ")=="100 residents","resident count survives narrow layout")
        local contentBottom=4+#h.names*(font+6)+#h.details*(font+2)
        assert(h.attentionY>=contentBottom,"home action is below complete identity")
        assert(h.height>=h.attentionY+font+10,"header reserves the home action")
        assert(layout(width,name,"100 residents",false).height<h.height,"quiet header gives space back")
    end
    local close={}
    for _,key in ipairs({"X","Y","Width","Height"}) do
        close["set"..key]=function(self,value) self[key]=value end
    end
    local header=setmetatable({width=760,height=600,knoxName="Home",knoxDetail="3 residents",closeButton=close},{__index=Header})
    header:layoutSheetHeader()
    assert(close.X==728 and close.Y==4 and close.Width==26 and close.Height==26,
        "native close button has a real square hit target in the reserved corner")
    header.width=480;header:layoutSheetHeader()
    assert(close.X+close.Width<=header.width and close.Y+close.Height<=header.knoxHeaderHeight,
        "close target follows resize and stays inside the header")
    local tabs=notebookTabsFactory(font)
    local panel=setmetatable({width=300,height=400,tabHeight=font+10,scrollX=-170,
        viewList={{name="Base & Work",tabWidth=130},{name="Crew & Schedule",tabWidth=170},
            {name="Missions",tabWidth=100},{name="Stores & Stock",tabWidth=170},{name="World",tabWidth=90}}}, {__index=tabs})
    function panel:getWidth() return self.width end
    function panel:getWidthOfAllTabs() return 665 end
    function panel:getActiveViewIndex() return 3 end
    local rectangles=0
    function panel:drawRect(x,y,w,h,a,r,g,b)
        rectangles=rectangles+1
        if rectangles==1 then
            -- The strip wears the shared sheet material, not the cool HUD one.
            local theme=KnoxSurvivorUILayout.sheetTheme()
            assert(a==0.94 and r==theme.charcoal[1] and g==theme.charcoal[2] and b==theme.charcoal[3],
                "sheet background uses native alpha-first drawing arguments")
        end
    end
    local clipped,cleared,arrows=false,false,{}
    function panel:setStencilRect(x,y,w,h)
        assert(x==0 and y==0 and w==self.width and h==self.tabHeight,"tab clipping matches strip bounds")
        clipped=true
    end
    function panel:clearStencilRect() cleared=true end
    function panel:drawTexture(texture,x,y)
        local direction=texture.path:find("ArrowLeft",1,true) and "left" or "right"
        assert(self:getScrollButtonAtX(x+4)==direction,"visible arrow uses native scroll hit region")
        arrows[direction]=true
    end
    local drawn=0
    function panel:drawText(text,x,y)
        local centre=x+#text*font*0.55/2
        if centre>=0 and centre<self.width then
            local index=self:getTabIndexAtX(centre)
            assert(index>0 and self.viewList[index].name:sub(1,3)==text:sub(1,3),
                "painted label and native scroll-aware click target identify the same tab")
            drawn=drawn+1
        end
    end
    panel:render()
    assert(drawn>0,"scrolled tabs still draw reachable labels")
    assert(clipped and cleared,"overflow clipping is scoped to the tab strip")
    assert(arrows.left and arrows.right,"both overflow directions remain discoverable")
end
getTexture=oldTexture
print("Notebook header/tabs PASS identity=true attention=true scrolling=true nativeTabGeometry=true")
