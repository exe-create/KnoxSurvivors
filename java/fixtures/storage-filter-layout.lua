local factory = assert(storageFilterLayoutFactory)
local function control(width, height, title)
    local c = { x = 0, y = 0, width = width or 1, height = height or 1, title = title }
    function c:setX(v) self.x = v end
    function c:setY(v) self.y = v end
    function c:setWidth(v) self.width = v end
    function c:setHeight(v) self.height = v end
    function c:setVisible(v) self.visible = v end
    function c:getBottom() return self.y + self.height end
    function c:setText(v) self.text = v end
    return c
end
local function test(font, width, height, mode, instruction)
    local view = factory(font)
    local selected = { food = true, ["item:Base.Book"] = true }
    local w = { width = width, height = height, mode = mode, selectedFilters = selected,
        instructionText = instruction or "Tick what this container keeps. The count is what it holds now.", instructionLabels = {},
        categoryList = control(), searchBox = control(), modeButton = control(120, 24, "Pick exact items"),
        saveButton = control(88, 24, "Save Filters"), cancelButton = control(88, 24, "Cancel") }
    function w:titleBarHeight() return font + 4 end
    function w:addChild(child) end
    w.categoryList.itemheight = math.max(22, math.floor(26 * font / 14))
    view.applyModeLayout(w)
    local list = w.categoryList
    assert(list.height >= list.itemheight and list.x >= 0 and list.x + list.width <= width,
        "list fits width and shows at least one complete row")
    if instruction ~= nil then
        local last = nil
        for _, label in ipairs(w.instructionLabels) do if label.visible then last = label end end
        assert(last ~= nil and string.sub(last.name, -3) == "...", "long instruction ends with ellipsis")
        assert(last.tooltip == instruction and list.tooltip == instruction, "complete instruction remains available")
    end
    if mode == "items" then
        assert(w.searchBox.visible and list.y >= w.searchBox:getBottom(), "items list clears search")
    else
        assert(not w.searchBox.visible, "groups hide search")
    end
    for _, button in ipairs({w.modeButton, w.saveButton, w.cancelButton}) do
        assert(button.x >= 0 and button.x + button.width <= width and button:getBottom() <= height,
            "footer button remains inside window")
        assert(list:getBottom() <= button.y, "list clears footer")
    end
    local buttons = {w.modeButton, w.saveButton, w.cancelButton}
    for i = 1, #buttons do for j = i + 1, #buttons do
        local a, b = buttons[i], buttons[j]
        assert(a:getBottom() <= b.y or b:getBottom() <= a.y
            or a.x + a.width <= b.x or b.x + b.width <= a.x, "footer buttons do not overlap")
    end end
    w.width, w.height = width == 320 and 720 or 320, height == 480 and 720 or 480
    view.applyModeLayout(w)
    assert(w.selectedFilters == selected and selected.food and selected["item:Base.Book"],
        "reflow preserves selections")
end
for _, font in ipairs({14, 28}) do
    for _, size in ipairs({{320, 480}, {720, 720}}) do
        test(font, size[1], size[2], "groups")
        test(font, size[1], size[2], "items")
    end
end
local longInstruction = "Suggested for this container: Books and Maps and Medical Supplies and Building Materials and Farming Equipment and Tools and Ammunition and Food and Water and Clothing. Untick anything you do not want, then save."
test(28, 320, 480, "groups", longInstruction)
test(28, 320, 480, "items", longInstruction)
print("Storage filter layout PASS modes=true sizes=true large=true resize=true")
