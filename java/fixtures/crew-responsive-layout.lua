local factory = assert(crewLayoutFactory)
local function control(width, height)
    local c = { x = 0, y = 0, width = width or 100, height = height or 24, items = {} }
    function c:setX(value) self.x = value end
    function c:setY(value) self.y = value end
    function c:setWidth(value) self.width = value end
    function c:setHeight(value) self.height = value end
    function c:getBottom() return self.y + self.height end
    function c:setVisible(value) self.visible = value end
    function c:setNameWithoutMoving(value) self.name = value end
    function c:initialise() end
    function c:setRows(value) self.rows = value end
    function c:setBlocks(value) self.blocks = value end
    return c
end
local function run(font, button, width, expectedColumns)
    local labels={new=function(self,x,y,h,text)
        local label=control(100,h);label.x=x;label.y=y;label.name=text;return label
    end}
    local view, priorities, tools, blocks = factory(font, button,labels)
    local page = { width = width, crewCells = {}, scheduleTools = {}, scheduleBlockBtns = {}, crewCaptions = {} }
    local labels = { "partyLabel", "residentsLabel", "priorityLabel", "scheduleResidentLabel", "scheduleLabel", "scheduleStatus", "kitStatus", "bedsHeading", "bedsLabel" }
    for _, name in ipairs(labels) do page[name] = control(100, button) end
    function page:addChild() end
    page.scheduleStatus.knoxFullText="Unsaved changes. Save this resident's hours before copying the schedule."
    page.kitStatus.knoxFullText="Kit: bandages and drinking water are missing; supplies have not been transferred."
    page.partyList = control(100, button); page.partyList.items = { 1, 2, 3 }
    page.resList = control(100, button); page.resList.items = { 1, 2, 3, 4, 5 }
    page.prefTable = control(); page.timelinePanel = control()
    page.bedsList = control(100, button); page.bedsList.items = { 1, 2, 3 }
    for _, col in ipairs(priorities) do page.crewCells[col.key] = control() end
    for _, tool in ipairs(tools) do page.scheduleTools[tool.key] = control(100, button) end
    for i = 1, #blocks do page.scheduleBlockBtns[i] = control() end
    for i = 1, 6 do page.crewCaptions[i] = control(100, font) end
    local controls = { "colonyPresetBtn", "nightPresetBtn", "roleHoursBtn", "clearPresetBtn", "saveScheduleBtn",
        "copyPicker", "copyScheduleBtn", "resetPrioritiesBtn", "viewBtn", "joinPartyBtn", "sendHomeBtn",
        "inventoryBtn", "setRoleBtn", "rolePicker", "setJobBtn", "jobPicker", "standingOrderBtn",
        "guardOverrideBtn", "factionBtn" }
    for _, name in ipairs(controls) do page[name] = control(100, button) end
    view.layoutPage(page)
    if expectedColumns == 1 then
        assert(page.priorityLabel.y >= page.resList:getBottom(), "stacked detail follows the complete rail")
        assert(page.priorityLabel.x == page.resList.x, "stacked detail shares the rail width")
    else
        assert(page.priorityLabel.x >= page.resList.x + page.resList.width, "wide detail clears the rail")
        assert(page.priorityLabel.y == page.partyLabel.y, "wide columns start together")
    end
    assert(page.prefTable.y >= page.priorityLabel:getBottom(), "table follows its label")
    assert(page.scheduleResidentLabel.y >= page.prefTable:getBottom(), "schedule follows entire preference table")
    assert(page.scheduleLabel.y >= page.scheduleResidentLabel:getBottom(), "schedule labels do not overlap")
    for _, tool in ipairs(tools) do
        local widget = page.scheduleTools[tool.key]
        assert(widget.y >= page.scheduleLabel:getBottom() and widget:getBottom() <= page.timelinePanel.y,
            "schedule tools remain between heading and timeline")
    end
    assert(page.crewCaptions[1].y >= page.timelinePanel:getBottom()
        and page.crewCaptions[1].y >= page.resList:getBottom(), "footer follows both columns")
    assert(page.kitStatus:getBottom() <= page.knoxContentHeight, "footer is inside scroll extent")
    assert(page.bedsHeading.y >= page.kitStatus:getBottom(), "the bed roster follows the kit line")
    assert(page.bedsList.y >= page.bedsLabel:getBottom(), "the bed list follows its count")
    assert(page.bedsList:getBottom() <= page.knoxContentHeight, "the bed list stays inside scroll extent")
    for _,pool in ipairs({page.statusTextLines or {},page.kitTextLines or {}}) do
        for _,label in ipairs(pool) do
            if label.visible then
                assert(label:getBottom()<=page.knoxContentHeight,"complete kit/status feedback is scrollable")
                assert(label.x+#label.name*font*0.55<=width-10,"kit/status lines remain inside page")
            end
        end
    end
    for _, name in ipairs(controls) do
        local c = page[name]
        assert(c.x >= 0 and c.x + c.width <= width, name .. " stays inside page")
        assert(c:getBottom() <= page.knoxContentHeight, name .. " stays inside scroll extent")
    end
    local prior = page.knoxContentHeight
    view.layoutPage(page)
    assert(page.knoxContentHeight == prior, "repeated layout does not drift")
    return page, view
end
-- 608px page and the exact 642px content-width split on either side.
run(14, 24, 608, 1)
run(14, 24, 641 + 20, 1)
run(14, 24, 642 + 20, 2)
run(24, 34, 608, 1)
local page, view = run(24, 34, 662, 2)
page.width = 608; view.layoutPage(page)
assert(page.priorityLabel.y >= page.resList:getBottom(), "wide-to-narrow reflow stacks detail")
page.width = 662; view.layoutPage(page)
assert(page.priorityLabel.y == page.partyLabel.y, "narrow-to-wide reflow restores columns")
print("Crew responsive layout PASS narrow=true threshold=true large=true footer=true reflow=true")
