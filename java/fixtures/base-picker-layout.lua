local picker = assert(basePickerFixture)
local function check(screenW, screenH, scale, font, title, count)
    local g = picker.layout(screenW, screenH, scale, font, title, count)
    assert(g.width <= screenW and g.height <= screenH, "window remains inside viewport")
    assert(g.labelY >= title and g.listY >= g.labelY + font, "question clears title and list")
    assert(g.listHeight > 0 and g.cancelY >= g.listY + g.listHeight, "cancel follows list")
    assert(g.cancelY + g.rowHeight <= g.height and g.rowHeight >= font, "cancel and font fit")
    assert(g.contentWidth <= g.width and g.contentWidth > 0, "content fits width")
    return g
end
for _, count in ipairs({ 0, 1, 30, 100 }) do
    check(1280, 720, 0.8, 14, 22, count)
    check(320, 240, 1, 24, 28, count)
end
local many = check(1280, 720, 0.8, 14, 22, 100)
assert(many.listHeight < 100 * many.rowHeight, "large roster is scrollable")
local few = check(1280, 720, 0.8, 14, 22, 1)
assert(few.listHeight >= few.rowHeight, "a single choice is visible")
local result, calls = nil, 0
local function window()
    local w = setmetatable({ choiceCallback = function(value) result = value; calls = calls + 1 end },
        {__index=picker.window})
    function w:setVisible(value) self.visible = value end
    function w:removeFromUIManager() self.removed = true;self.removals=(self.removals or 0)+1 end
    w.finish = picker.window.finish
    return w
end
local chosen = window()
picker.owner.window = chosen
picker.window.onPick(chosen, { id = "private-id" })
assert(calls == 1 and result == "private-id" and chosen.removed and picker.owner.window == nil,
    "selection returns the internal id once and closes")
picker.window.onCancel(chosen)
assert(calls == 1 and chosen.removals==1, "a repeated close cannot invoke the callback or native removal twice")
local canceled = window()
picker.owner.window = canceled
picker.window.close(canceled)
assert(calls == 2 and result == nil and canceled.removed and picker.owner.window == nil,
    "window close reports cancellation once")
print("Base picker layout PASS counts=true viewport=true scroll=true one_shot=true")
