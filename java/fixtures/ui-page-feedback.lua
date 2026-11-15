local factory = assert(uiPageFeedbackFactory)
local function widget()
    local w = { x = 0, y = 0, width = 100, height = 24, items = {}, name = "", r = 1, g = 1, b = 1, a = 1 }
    function w:setX(v) self.x = v end; function w:setY(v) self.y = v end
    function w:setWidth(v) self.width = v end; function w:setHeight(v) self.height = v end
    function w:setVisible(v) self.visible = v end; function w:getWidth() return self.width end
    function w:getBottom() return self.y + self.height end
    function w:setNameWithoutMoving(v) self.name = v end
    function w:contentHeight() return 100 end
    return w
end
local function text(page, label, key)
    local lines = {label.name}
    for _, extra in ipairs(page[key] or {}) do if extra.visible then lines[#lines + 1] = extra.name end end
    return table.concat(lines, ""):gsub("%s+", "")
end
local function test(font, width)
    local base, world, stores = factory(font)
    local function page(names)
        local p = {width = width}
        function p:addChild() end
        for _, name in ipairs(names) do p[name] = widget() end
        return p
    end
    local b = page({"basePicker","renameBaseBtn","boundaryLabel","showHighlights","autoBoardBtn",
        "editBoundaryBtn","zoneList","taskList","zoneHeading","taskHeading","zonePicker","addAreaBtn",
        "removeBtn","taskDetailsBtn","cancelTaskBtn","resumeTaskBtn","assignTaskBtn","residentPicker",
        "detailsBtn","storageLabel","storageList","bedsLabel","bedsList","kitShortageLabel",
        "kitShortageList","hintLabel","reasonLabel"})
    b.hintLabel.name = "Hours and work priorities live in Crew and Schedule; stock targets live in Stores."
    local reason = "This action is unavailable until the resident has finished their current work and the home is ready."
    function b:actionReason() return reason end
    base.layoutPage(b)
    assert(text(b,b.reasonLabel,"baseReasonLines") == reason:gsub("%s+", ""), "base reason remains complete")
    local lastBase = b.baseReasonLines[#b.baseReasonLines] or b.reasonLabel
    assert(lastBase:getBottom() <= b.knoxContentHeight, "base reason remains inside scroll extent")
    local s = page({"targetsLabel","captionLabel","itemsHeading","itemTargets","addItemBtn",
        "removeItemBtn","itemReason","categoriesHeading","cardsPanel","clearBtn",
        "storageHeading","storageLabel","storageList","yardLabel","kitHeading",
        "kitShortageLabel","kitShortageList","hintLabel"})
    s.yardLabel.knoxFullText = "No yard painted yet: a log area becomes one."
    s.hintLabel.knoxFullText = "Planner defaults. Clear Targets is off until you set a number."
    stores.layoutPage(s)
    assert(text(s,s.hintLabel,"storesHintLines") == s.hintLabel.knoxFullText:gsub("%s+", ""),
        "stores explanation remains complete")
    local lastStore = s.storesHintLines[#s.storesHintLines] or s.hintLabel
    assert(lastStore:getBottom() <= s.knoxContentHeight, "stores explanation remains scrollable")
    assert(s.storageList.y >= s.storageLabel:getBottom(), "the container list follows its line")
    assert(s.kitShortageList.y >= s.kitShortageLabel:getBottom(), "the kit list follows its line")
    assert(s.itemReason:getBottom() <= s.knoxContentHeight, "the item reason stays scrollable")
    local w = page({"list","cardPortrait","cardLine1","cardLine2","memberList","viewBtn","viewReason"})
    w.cardLine1.knoxFullText = "Leader: Alexandria Stonebridge | friendly | Home at the old farmhouse"
    w.cardLine2.knoxFullText = "Six members, three settled and two on watch | A raid ended near the riverside."
    w.viewReason.knoxFullText="View Card opens the selected survivor's sheet with their full condition and history."
    world.layoutPage(w)
    assert(text(w,w.cardLine1,"worldCardFirstLines") == w.cardLine1.knoxFullText:gsub("%s+", ""), "faction home remains complete")
    assert(text(w,w.cardLine2,"worldCardSecondLines") == w.cardLine2.knoxFullText:gsub("%s+", ""), "faction history remains complete")
    local lastCard = w.worldCardSecondLines[#w.worldCardSecondLines] or w.cardLine2
    assert(w.memberList.y >= lastCard:getBottom(), "member list follows the full faction card")
    assert(text(w,w.viewReason,"worldViewReasonLines")==w.viewReason.knoxFullText:gsub("%s+",""),
        "card action explanation remains complete")
    local previous = w.knoxContentHeight
    world.layoutPage(w)
    assert(w.knoxContentHeight == previous, "repeated layout does not drift")
end
for _, font in ipairs({14,24}) do for _, width in ipairs({320,600}) do test(font,width) end end
print("UI page feedback PASS base=true stores=true faction=true reflow=true")
