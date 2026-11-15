local factory = assert(talkReadableFactory)
local function list()
    local l = { items = {}, scroll = 0, clearCount = 0 }
    function l:setX(v) self.x = v end; function l:setY(v) self.y = v end
    function l:setWidth(v) self.width = v end; function l:setHeight(v) self.height = v end
    function l:getYScroll() return self.scroll end; function l:setYScroll(v) self.scroll = v end
    function l:setScrollHeight(v) self.scrollHeight = v end
    function l:clear() self.items = {}; self.clearCount = self.clearCount + 1 end
    function l:addItem(text, data) self.items[#self.items + 1] = {text = text, item = data} end
    return l
end
local function button()
    local b = {}
    function b:setX(v) self.x = v end; function b:setY(v) self.y = v end
    function b:setWidth(v) self.width = v end
    return b
end
local function content(list)
    local parts = {}
    for _, row in ipairs(list.items) do parts[#parts + 1] = row.item.text end
    return table.concat(parts, ""):gsub("%s+", "")
end
local function check(font, width, height, scale)
    local window = factory(font)
    local description = "What they do when nobody is watching."
    local state = "Following you - Defensive - Paired with the other resident"
    local answer = "They cannot accept that order while their current work is finishing and the route to the base is not available. Please try again once they are ready. The current work must finish before the route can be checked again, and the resident will explain if the destination remains unavailable."
    local w = {width=width,height=height,uiScale=scale,tabY=30,tabHeight=font+8,tabCount=3,
        description=description,stateLine=state,feedback=answer,
        contextTextList=list(),feedbackTextList=list(),actionButtons={}}
    w.portrait={setWidth=function(self,v) self.width=v end,setHeight=function(self,v) self.height=v end}
    for i=1,6 do w.actionButtons[i]=button() end
    function w:layoutTabs() end
    window.layoutTalkText(w)
    assert(content(w.contextTextList) == (description..state):gsub("%s+", ""), "context keeps all text")
    assert(content(w.feedbackTextList) == answer:gsub("%s+", ""), "response keeps all text")
    local paints=0
    function w.feedbackTextList:drawText(text,x,y)
        assert(x+#text*font*0.55<=self.width-18,"response text leaves the scrollbar clear")
        paints=paints+1
    end
    for _,row in ipairs(w.feedbackTextList.items) do
        assert(window.drawTalkText(w.feedbackTextList,0,row)==w.feedbackTextList.itemheight,
            "native callback receives list,y,row and advances a full line")
    end
    assert(paints==#w.feedbackTextList.items,"real response renderer paints every wrapped line")
    assert(w.contextTextList.y + w.contextTextList.height <= w.actionButtons[1].y,
        "context clears the actions")
    assert(w.actionButtons[6].y + w.tabHeight <= w.feedbackTextList.y,
        "feedback follows the actions")
    assert(w.feedbackTextList.y + w.feedbackTextList.height <= height, "feedback remains in the window")
    assert(w.feedbackTextList.height>=font+2,"at least one whole response line remains readable")
    assert(w.portrait.width+20*scale<=w.contextTextList.x,"portrait clears the text rail")
    assert(#w.feedbackTextList.items * w.feedbackTextList.itemheight > w.feedbackTextList.height,
        "long response remains accessible as scrollable rows")
    w.feedbackTextList.scroll = -12
    w.width = width - 10
    window.layoutTalkText(w)
    assert(w.feedbackTextList.scroll == -12, "resize keeps scroll for unchanged response")
    w.feedback = "A different response."
    window.layoutTalkText(w)
    assert(w.feedbackTextList.scroll == 0 and content(w.feedbackTextList) == "Adifferentresponse.",
        "new response replaces old content and resets scroll")
end
check(14,500,300,1)
check(24,650,500,24/14)
check(14,320,300,1)
check(24,620,460,24/14)
print("Talk readable feedback PASS wrapped=true scroll=true bounds=true replacement=true")
