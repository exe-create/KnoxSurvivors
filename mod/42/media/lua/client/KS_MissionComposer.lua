require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "KS_MissionTargets"

-- Notebook-owned controls; no saved mission state or separate dispatch service.
local Composer = {}

function Composer.create(view, ui, height)
    view.missionSelected = {}
    view.missionLayout=ui
    view.missionPurpose = ISComboBox:new(0,0,200,height,view,nil)
    view.missionPurpose:initialise()
    for _,choice in ipairs(KnoxMissionTargets.MISSION_CHOICES) do
        view.missionPurpose:addOption(choice.name)
    end
    view:addChild(view.missionPurpose)
    view.missionCrew = ISScrollingListBox:new(0,0,200,height)
    view.missionCrew:initialise(); view.missionCrew:instantiate()
    view.missionCrew.font=UIFont.Small
    view.missionCrew.ownerView=view
    view.missionCrew.doDrawItem=function(list,y,item)
        local selected=list.ownerView.missionSelected[item.item]==true
        local theme=ui.theme
        local tone=selected and theme.bone or theme.dim
        local marker=selected and "[x]" or "[ ]"
        local manager=getTextManager()
        local nameX=10+manager:MeasureStringX(UIFont.Small,"[x]  ")
        local lines=ui.wrapLines(item.text,math.max(1,list.width-nameX-10),function(text)
            return manager:MeasureStringX(UIFont.Small,text)
        end)
        local fontH=manager:getFontHeight(UIFont.Small)
        local rowH=item.height or list.itemheight
        if selected then list:drawRect(0,y,2,rowH,0.9,
            theme.amber[1],theme.amber[2],theme.amber[3]) end
        list:drawText(marker,10,y+4,tone[1],tone[2],tone[3],1,UIFont.Small)
        for index,line in ipairs(lines) do
            list:drawText(line,nameX,y+4+(index-1)*(fontH+2),tone[1],tone[2],tone[3],1,UIFont.Small)
        end
        return y+rowH
    end
    view.missionCrew:setOnMouseDownFunction(view,function(self,id)
        self.missionSelected[id]=not self.missionSelected[id]
        Composer.summary(self)
    end)
    -- Native lists consume wheel events even when all rows fit. Route them to
    -- the sole notebook page scroller instead of swallowing the wheel.
    view.missionCrew.onMouseWheel=function(_,delta) return Composer.scrollPage(view,delta) end
    view.list.onMouseWheel=function(_,delta) return Composer.scrollPage(view,delta) end
    view:addChild(view.missionCrew)
    view.missionHint=ISLabel:new(0,0,height,"Choose the crew. No group-size limit.",
        ui.theme.dim[1],ui.theme.dim[2],ui.theme.dim[3],1,UIFont.Small,true)
    view.missionHint:initialise(); view:addChild(view.missionHint)
    view.missionAll=ISButton:new(0,0,100,height,"Select all",view,function(self)
        Composer.selectAll(self)
        Composer.summary(self)
    end)
    view.missionAll:initialise(); view:addChild(view.missionAll)
end

function Composer.scrollPage(view,delta)
    view:setYScroll(view:getYScroll()-delta*30)
    return true
end

function Composer.selectAll(view)
    local all=#Composer.members(view)==#(view.missionCrew.items or {})
    for _,row in ipairs(view.missionCrew.items or {}) do view.missionSelected[row.item]=not all end
end

function Composer.summary(view)
    local count=#Composer.members(view)
    local available=#(view.missionCrew.items or {})
    local text=available>0 and (tostring(count).." selected / "..tostring(available).." available")
        or view.missionEmptyReason or "No crew available."
    view.missionHint.knoxFullText=text
    view.missionHint.name=text
    view.missionHint.tooltip=text
    view.missionAll:setTitle(available>0 and count==available and "Clear selection" or "Select all")
    view.missionAll:setEnable(available>0)
end

function Composer.refresh(view)
    local player=getSpecificPlayer(view.playerNum or 0)
    local owner=player and KnoxPersistence.ensurePlayerId(player)
    local base=owner and KnoxBaseManager.getForOwner("player",owner)
    view.missionBaseId=base and base.id
    local autonomy=rawget(_G,"KnoxSurvivorAutonomy")
    local crew=base and autonomy and autonomy.missionCrewIds
        and autonomy.missionCrewIds(player,base.id,"scout",nil) or {}
    local reason
    if base and autonomy and autonomy.baseMissionAvailability then
        local available
        available,reason=autonomy.baseMissionAvailability(player,base.id,"scout",nil)
        if available==0 then crew={} end
    end
    local selected={}
    view.missionCrew:clear()
    for _,id in ipairs(crew) do
        selected[id]=view.missionSelected[id]==true
        view.missionCrew:addItem(KnoxMissionTargets.crewName(id),id,KnoxMissionTargets.crewName(id))
    end
    view.missionSelected=selected
    local excluded=base and autonomy and autonomy.missionCrewExclusions
        and autonomy.missionCrewExclusions(player,base.id,"scout",nil) or {}
    view.missionExclusions={}
    for _,entry in ipairs(excluded) do
        view.missionExclusions[#view.missionExclusions+1]=KnoxMissionTargets.exclusionText({entry},KnoxMissionTargets.crewName)
    end
    view.missionEmptyReason=base==nil and "Establish a base before sending a crew."
        or KnoxMissionTargets.availabilityText(reason or "dispatch_unavailable")
    Composer.summary(view)
end

function Composer.members(view)
    local ids={}
    for _,row in ipairs(view.missionCrew.items or {}) do
        if view.missionSelected[row.item] then ids[#ids+1]=row.item end
    end
    return ids
end

-- Reuse label children as the page reflows; important feedback is visible in
-- the sole page scroller, rather than attached to an unsupported list tooltip.
local function layoutText(view, key, first, texts, x, y, width, fontH)
    local ui=view.missionLayout
    local manager=getTextManager()
    local lines={}
    for _,text in ipairs(texts) do
        for _,line in ipairs(ui.wrapLines(text,width,function(value)
            return manager:MeasureStringX(UIFont.Small,value)
        end)) do lines[#lines+1]=line end
    end
    local labels=view[key] or {};view[key]=labels
    if first then labels[1]=first end
    for index,line in ipairs(lines) do
        local label=labels[index]
        if label==nil then
            label=ISLabel:new(x,y,fontH+2,"",ui.theme.dim[1],ui.theme.dim[2],ui.theme.dim[3],1,UIFont.Small,true)
            label:initialise();view:addChild(label);labels[index]=label
        end
        label:setNameWithoutMoving(line);label:setX(x);label:setY(y)
        label:setHeight(fontH+2);label:setVisible(true)
        y=y+fontH+2
    end
    for index=#lines+1,#labels do labels[index]:setVisible(false) end
    return y
end

function Composer.layout(view, margin, height)
    local ui=view.missionLayout
    local manager=getTextManager()
    local fontH=manager:getFontHeight(UIFont.Small)
    local measure=function(text) return manager:MeasureStringX(UIFont.Small,text) end
    local width=math.max(1,view.width-margin*2)
    view.missionPurpose:setX(margin);view.missionPurpose:setY(margin)
    view.missionPurpose:setWidth(width)
    Composer.summary(view)
    local top=view.missionPurpose:getBottom()+6
    local allWidth=math.min(width,measure("Clear selection")+24)
    local beside=measure(view.missionHint.knoxFullText)+allWidth+8<=width
    local hintWidth=beside and width-allWidth-8 or width
    local y=layoutText(view,"missionHintLines",view.missionHint,
        {view.missionHint.knoxFullText},margin,top,hintWidth,fontH)
    view.missionAll:setX(beside and view.width-margin-allWidth or margin)
    view.missionAll:setY(beside and top or y+4);view.missionAll:setWidth(allWidth)
    y=math.max(y,view.missionAll:getBottom())+4
    view.missionCrew:setX(margin);view.missionCrew:setY(y);view.missionCrew:setWidth(width)
    view.missionCrew.itemheight=math.max(height,fontH+10)
    local contentH=4
    local nameWidth=math.max(1,width-20-measure("[x]  "))
    for _,row in ipairs(view.missionCrew.items) do
        local lines=ui.wrapLines(row.text,nameWidth,measure)
        row.height=math.max(view.missionCrew.itemheight,#lines*(fontH+2)+8)
        contentH=contentH+row.height
    end
    if #view.missionCrew.items==0 then contentH=contentH+view.missionCrew.itemheight end
    -- Expand into the notebook's single page scroller. No nested crew scroller.
    view.missionCrew:setHeight(contentH)
    y=view.missionCrew:getBottom()+margin
    return layoutText(view,"missionExclusionLines",nil,view.missionExclusions or {},
        margin,y,width,fontH)+margin
end

function Composer.confirm(view)
    local choice=KnoxMissionTargets.MISSION_CHOICES[view.missionPurpose.selected or 1]
    local ok,reason=KnoxMissionTargets.armMap(view.playerNum or 0,view.missionBaseId,
        choice and choice.id,Composer.members(view))
    if not ok then
        KnoxActivityFeed.event(reason)
        return false
    end
    KnoxActivityFeed.event("Right-click the world map and choose Send crew here. Remote looting waits for the area to load.")
    return true
end

return Composer
