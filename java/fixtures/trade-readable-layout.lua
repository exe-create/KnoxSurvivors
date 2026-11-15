local factory = assert(tradeReadableFactory)
local function test(font, width)
    local item = { getName = function() return "Heavy Reinforced Very Long Field Medical Supply Bag" end,
        getTex = function() return nil end }
    local short = { getName = function() return "Bandage" end, getTex = function() return nil end }
    local view = factory(font, { playerItems = {item, short}, survivorItems = {} })
    local function list()
        local l = { width = width, height = 600, itemheight = font + 8, items = {}, selected = 1,
            scroll = -4, scrollHeight = 0, offerKey = "giving" }
        function l:getYScroll() return self.scroll end
        function l:setYScroll(v) self.scroll = v end
        function l:getScrollHeight() return self.scrollHeight end
        function l:setScrollHeight(v) self.scrollHeight = v end
        function l:clear() self.items = {}; self.selected = 1 end
        function l:addItem(name, object, tooltip)
            local row = { text = name, item = object, tooltip = tooltip, height = self.itemheight }
            self.items[#self.items + 1] = row; self.scrollHeight = self.scrollHeight + row.height
            return row
        end
        return l
    end
    local playerList, survivorList = list(), list()
    local window = { player = {}, survivorId = "a", playerList = playerList, survivorList = survivorList,
        giving = {}, taking = {}, refreshQuote = function(self) self.quoted = true end }
    playerList.parent, survivorList.parent = window, window
    playerList.items = {{item = short}}; playerList.selected = 1
    view.refreshStock(window)
    assert(playerList.selected == 2 and playerList.scroll == -4, "refresh preserves selection and scroll")
    local row = playerList.items[1]
    assert(row.tooltip == item:getName(), "tooltip retains the complete item name")
    assert(row.height > playerList.itemheight and playerList.scrollHeight == row.height + playerList.items[2].height,
        "wrapped names increase real row and scroll heights")
    row.index = 1
    local rendered = {}
    function playerList:drawRect() end
    function playerList:drawText(text, x, y)
        assert(x >= 49 and x + #text * font * 0.55 <= width - 20, "name avoids icon and scrollbar")
        assert(y + font <= row.height, "name stays inside its row")
        rendered[#rendered + 1] = text
    end
    function playerList:drawTextureScaledAspect() end
    assert(view.drawStock(playerList, 0, row) == row.height, "renderer advances by the actual row height")
    assert(table.concat(rendered, ""):gsub("%s+", "") == row.text:gsub("%s+", ""),
        "all item name characters are rendered")
    assert(window.quoted, "refresh still updates the trade quote")
end
test(14, 180)
test(24, 200)
print("Trade readable rows PASS full_name=true tooltip=true scroll=true selection=true")
local layoutFactory = assert(tradeMessageLayoutFactory)
local function checkMessage(font, width, height)
    local view = layoutFactory(font)
    local function widget(w, h, title)
        local o = { x = 0, y = 0, width = w, height = h, title = title,
            knoxFullTitle = title, items = {}, itemheight = font + 8, scroll = 0 }
        function o:setX(v) self.x = v end
        function o:setY(v) self.y = v end
        function o:setWidth(v) self.width = v end
        function o:setHeight(v) self.height = v end
        function o:setTitle(v) self.title = v end
        function o:getYScroll() return self.scroll end
        function o:setYScroll(v) self.scroll = v end
        function o:setScrollHeight(v) self.scrollHeight = v end
        return o
    end
    local offered = {}
    local w = { width = width, height = height, playerList = widget(10, 10), survivorList = widget(10, 10),
        giveButton = widget(10, 10, "Toggle offer"), takeButton = widget(10, 10, "Toggle offer"),
        tradeButton = widget(10, 10, "Trade"), clearButton = widget(10, 10, "Clear Offer"),
        doneButton = widget(10, 10, "Close"), giving = offered, taking = {},
        survivorName = "Alexandria Stonebridge Robertson",
        status = "An item cannot be transferred. Clear the offer and try again when it is safe." }
    function w:titleBarHeight() return font + 2 end
    view.layoutTrade(w)
    local function joined(lines) return table.concat(lines, ""):gsub("%s+", "") end
    assert(joined(w.tradeLayout.headers[2]) == w.survivorName:gsub("%s+", ""), "full heading is retained")
    assert(joined(w.tradeLayout.status) == w.status:gsub("%s+", ""), "full refusal status is retained")
    assert(w.playerList.height >= w.playerList.itemheight, "at least one item row remains visible")
    assert(w.playerList.y + w.playerList.height <= w.giveButton.y, "list clears the action row")
    for _, button in ipairs({w.giveButton, w.takeButton, w.tradeButton, w.clearButton, w.doneButton}) do
        assert(button.title == button.knoxFullTitle, "complete action caption fits: " .. button.knoxFullTitle)
        assert(#button.title * font * 0.55 <= button.width - 12, "caption stays inside its button")
    end
    assert(joined(w.tradeLayout.counts) == "Youoffer0items;theyoffer0items.", "zero counts use plural")
    local endOfStatus = w.statusY + (#w.tradeLayout.status + #w.tradeLayout.counts
        + #w.tradeLayout.help + #w.tradeLayout.hidden) * font
    for _, button in ipairs({w.tradeButton, w.clearButton, w.doneButton}) do
        assert(endOfStatus <= button.y and button.x >= 0 and button.x + button.width <= width
            and button.y + button.height <= height, "full feedback clears footer buttons")
    end
    local oldSelection = w.giving
    local one = { getID = function() return 1 end }
    local two = { getID = function() return 2 end }
    w.giving[one] = true
    w.taking[one], w.taking[two] = true, true
    w.width = width + 100
    w.status = "The offer has changed. Review the items."
    view.layoutTrade(w)
    assert(w.giving == oldSelection and joined(w.tradeLayout.status) == w.status:gsub("%s+", ""),
        "resize and status change retain the offer and update the message")
    assert(joined(w.tradeLayout.counts) == "Youoffer1item;theyoffer2items.",
        "counts use singular and plural as appropriate")
end
checkMessage(14, 380, 480)
checkMessage(24, 380, 480)
print("Trade message layout PASS status=true heading=true footer=true resize=true")
