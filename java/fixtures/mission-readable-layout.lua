local C=assert(codecMissionComposer)
local oldFont,oldText,oldLabel,oldButton,oldCombo,oldList=UIFont,getTextManager,ISLabel,ISButton,ISComboBox,ISScrollingListBox
local oldPlayer,oldPersistence,oldBase,oldAutonomy=getSpecificPlayer,KnoxPersistence,KnoxBaseManager,KnoxSurvivorAutonomy
local oldName=KnoxMissionTargets.crewName
local function widget(x,y,w,h,title)
    local c={x=x,y=y,width=w,height=h or w,name=title or "",title=title or "",items={}}
    function c:initialise() end
    function c:instantiate() end
    function c:setX(v) self.x=v end
    function c:setY(v) self.y=v end
    function c:setWidth(v) self.width=v end
    function c:setHeight(v) self.height=v end
    function c:setVisible(v) self.visible=v end
    function c:setNameWithoutMoving(v) self.name=v end
    function c:setTitle(v) self.title=v end
    function c:setEnable(v) self.enabled=v end
    function c:getBottom() return self.y+self.height end
    function c:getY() return self.y end
    function c:addOption() end
    function c:setOnMouseDownFunction(owner,fn) self.click=function(id) fn(owner,id) end end
    function c:addItem(text,item,tooltip)
        local row={text=text,item=item,tooltip=tooltip};self.items[#self.items+1]=row;return row
    end
    function c:clear() self.items={} end
    return c
end
local class={new=function(self,...) return widget(...) end}
ISLabel={new=function(self,x,y,height,text) return widget(x,y,0,height,text) end}
ISButton,ISComboBox,ISScrollingListBox=class,class,class
UIFont={Small=1}
getSpecificPlayer=function() return {} end
KnoxPersistence={ensurePlayerId=function() return "player" end}
KnoxBaseManager={getForOwner=function() return {id="home"} end}
local crew,excluded={},{}
for i=1,100 do crew[i]="LongSurvivorNameWithoutSpaces"..tostring(i) end
for i=1,6 do excluded[i]={id="Unavailable person "..tostring(i),reason="away"} end
KnoxSurvivorAutonomy={missionCrewIds=function() return crew end,
    baseMissionAvailability=function() return 100 end,missionCrewExclusions=function() return excluded end}
KnoxMissionTargets.crewName=function(id) return id end
for _,font in ipairs({14,24}) do
    local measure=function(text) return #text*font*0.55 end
    getTextManager=function() return {getFontHeight=function() return font end,
        MeasureStringX=function(self,f,text) return measure(text) end} end
    for _,width in ipairs({320,600,1000}) do
        local view={width=width,list={},children={},addChild=function(self,c) self.children[#self.children+1]=c end}
        C.create(view,KnoxSurvivorUILayout,font+10)
        view.missionSelected[crew[1]]=true
        C.refresh(view)
        local bottom=C.layout(view,10,font+10)
        assert(#C.members(view)==1 and C.members(view)[1]==crew[1],"layout preserves exact chosen crew")
        assert(#view.missionExclusions==6,"every unavailable resident has a visible explanation")
        local reasonText={}
        for _,label in ipairs(view.missionExclusionLines) do
            if label.visible then
                reasonText[#reasonText+1]=label.name
                assert(label.x+measure(label.name)<=width-10,"exclusion reason fits page")
                assert(label:getBottom()<=bottom,"exclusions are in scroll extent")
            end
        end
        local shown=table.concat(reasonText," ")
        for i=1,6 do assert(shown:find("Unavailable person "..i,1,true),"unavailable name is readable") end
        assert(view.missionAll:getBottom()<=view.missionCrew.y,"selection action clears roster")
        local row=view.missionCrew.items[1]
        assert(row.tooltip==crew[1],"native row tooltip retains exact identity")
        local texts={}
        function view.missionCrew:drawRect() end
        function view.missionCrew:drawText(text,x,y)
            assert(x+measure(text)<=self.width-10,"crew name stays inside row")
            texts[#texts+1]=text
        end
        assert(view.missionCrew:doDrawItem(0,row)==row.height,"draw uses measured row height")
        table.remove(texts,1)
        assert(table.concat(texts,"")==crew[1],"full crew name renders without ellipsis")
        local count=#view.children
        C.layout(view,10,font+10)
        assert(#view.children==count,"unchanged reflow reuses label children")
    end
end
UIFont,getTextManager,ISLabel,ISButton,ISComboBox,ISScrollingListBox=oldFont,oldText,oldLabel,oldButton,oldCombo,oldList
getSpecificPlayer,KnoxPersistence,KnoxBaseManager,KnoxSurvivorAutonomy=oldPlayer,oldPersistence,oldBase,oldAutonomy
KnoxMissionTargets.crewName=oldName
print("Mission readable layout PASS exclusions=true names=true bounds=true hundredCrew=true reflow=true")
