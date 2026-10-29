require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "KS_TradeAction"
local UILayout = require "KS_SurvivorUILayout"

local UI = rawget(_G, "KnoxTradeUI") or {}
_G.KnoxTradeUI = UI
local windows = UI.windows or {}
UI.windows = windows
local Window = ISCollapsableWindowJoypad:derive("KnoxTradeWindow")
local PAD = 10

local MESSAGES = {
    both_sides_required = "Choose items on both sides.", fair_offer = "That looks fair.",
    gift_item_required = "Choose an item to give.", gift_ready = "Ready to give this item.",
    offer_too_low = "They want more for those items.", offer_no_longer_fair = "The offer has changed. Review the items.",
    food_reserve = "They need to keep that food.", water_reserve = "They need to keep that water.",
    bandage_reserve = "They need to keep those medical supplies.", best_melee_reserve = "They need a weapon at least as good in return.",
    medical_reserve = "They need to keep a reserve of that treatment.",
    compatible_ammunition_reserve = "They need that ammunition for their weapon.", task_resource = "Those supplies are needed at their base.",
    unsupported_item = "An item can no longer be traded. Clear the offer and try again.",
    equipped_or_favorite = "An offered item is now equipped, hidden or marked favorite.",
    item_not_owned = "An offered item has moved. Clear the offer and try again.",
    not_enough_capacity = "One of you needs more inventory space.",
    inventory_rules_or_id_conflict = "An item cannot be transferred. Clear the offer and try again.",
    inventory_unreadable_or_too_large = "That inventory cannot be safely inspected. Trading stopped.",
    shared_inventory = "The two inventories are not separate. Trading stopped.",
    player_busy = "Finish your current action first.", survivor_busy_or_threatened = "They are busy or dealing with a threat.",
    survivor_busy = "They need to finish what they are doing.", out_of_reach = "Stand beside them with nothing blocking the way.",
    too_far = "Move closer to trade.", hostile = "They will not trade with you.",
    player_owned = "Use Manage Inventory for your own survivors.",
    danger = "Trading stopped because of danger.", relationship_changed = "Your relationship changed. Trading stopped.",
    not_alive = "That survivor is no longer alive.", not_loaded = "That survivor is no longer here.",
    survivor_changed = "That survivor is no longer available.",
    survivor_unavailable = "They are temporarily unavailable. No items were exchanged.",
    trading_unavailable = "Trading is unavailable in this session.",
    browsing_expired = "The conversation ended. Speak to them again to trade.",
    trade_interrupted_or_expired = "The conversation ended. Speak to them again to trade.",
    capture_unavailable = "Their inventory could not be saved. No items were exchanged.",
    queue_failed = "The exchange could not start. Review the offer and try again.",
    queue_refused = "The exchange could not start. Review the offer and try again.",
    exchange_permission_changed = "Those items are no longer available for this exchange.",
    survivor_needs_care = "They need to take care of themselves first.",
    exchange_rolled_back = "The exchange failed. Both offers were returned.",
    recovery_required = "The exchange could not be safely restored. Trading is paused.",
    completed = "Trade complete.", gift_completed = "Gift delivered.", cancelled = "Trade cancelled.", closed = "Trade closed.",
    queue_cancelled = "Trade cancelled.", lease_lost = "Trading was interrupted.",
    combat = "Trading stopped because of combat.", danger_detected = "Trading stopped because of danger.",
    directive_changed = "They have new orders. Trading stopped.",
}

function UI.message(reason)
    return MESSAGES[reason] or "Trading stopped. Close this window and try again when it is safe."
end

local function trim(text, width)
    text = tostring(text or "")
    if getTextManager():MeasureStringX(UIFont.Small, text) <= width then return text end
    while #text > 0 and getTextManager():MeasureStringX(UIFont.Small, text .. "...") > width do
        text = text:sub(1, #text - 1)
    end
    return text .. "..."
end

local function itemName(item, player)
    return item:getName(player)
end

local function selectedItems(selection)
    local result = {}
    for item in pairs(selection) do result[#result + 1] = item end
    table.sort(result, function(a, b) return a:getID() < b:getID() end)
    return result
end

function Window:drawStock(y, row)
    local window, item = self.parent, row.item
    local offered = window[self.offerKey][item] == true
    if self.selected == row.index then self:drawRect(0, y, self.width, self.itemheight, .22, .7, .7, .7) end
    if offered then
        local color = getCore():getGoodHighlitedColor()
        self:drawTextureScaledAspect(window.tickTexture, 5, y + 4, 16, 16, 1, color:getR(), color:getG(), color:getB())
    end
    local texture = item:getTex()
    if texture ~= nil then self:drawTextureScaledAspect(texture, 24, y + 3, 20, 20, 1, 1, 1, 1) end
    self:drawText(trim(row.text, self.width - 70), 49, y + 4, .88, .88, .85, 1, UIFont.Small)
    return y + self.itemheight
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local line = getTextManager():getFontHeight(UIFont.Small)
    self.lineHeight, self.buttonHeight = line, line + 8
    local listY = self:titleBarHeight() + PAD + line + 4
    self.helpLines = self.height - listY - (line * 4 + self.buttonHeight * 2 + PAD * 5) >= line * 3 and 2 or 0
    local listHeight = math.max(line + 8, self.height - listY
        - (line * (2 + self.helpLines) + self.buttonHeight * 2 + PAD * 5))
    local column = (self.width - PAD * 3) / 2
    local function makeList(x, key)
        local list = ISScrollingListBox:new(x, listY, column, listHeight)
        list:initialise()
        list:setFont(UIFont.Small)
        list.itemheight = math.max(26, line + 8)
        list.doDrawItem, list.drawBorder, list.offerKey = Window.drawStock, true, key
        list.joypadParent = self
        list:setOnMouseDoubleClick(self, function(window, item) window:toggle(key, item) end)
        list.onJoypadDirLeft = function() setJoypadFocus(self.playerNum, self.playerList) end
        list.onJoypadDirRight = function() setJoypadFocus(self.playerNum, self.survivorList) end
        list.onJoypadDown = function(panel, button, joypadData)
            if button == Joypad.BButton then self:close()
            elseif button == Joypad.YButton then self:exchange()
            else ISScrollingListBox.onJoypadDown(panel, button, joypadData) end
        end
        self:addChild(list)
        return list
    end
    self.playerList, self.survivorList = makeList(PAD, "giving"), makeList(PAD * 2 + column, "taking")
    local function button(x, y, width, title, callback)
        local value = ISButton:new(x, y, width, self.buttonHeight, title, self, callback)
        value:initialise()
        self:addChild(value)
        return value
    end
    local toggleY = listY + listHeight + PAD
    self.giveButton = button(PAD, toggleY, column, "Offer / Remove", function(window)
        local row = window.playerList.items[window.playerList.selected]
        if row then window:toggle("giving", row.item) end
    end)
    self.takeButton = button(PAD * 2 + column, toggleY, column, "Offer / Remove", function(window)
        local row = window.survivorList.items[window.survivorList.selected]
        if row then window:toggle("taking", row.item) end
    end)
    self.statusY = toggleY + self.buttonHeight + PAD
    local footerY, footerWidth = self.height - PAD - self.buttonHeight, (self.width - PAD * 4) / 3
    self.tradeButton = button(PAD, footerY, footerWidth, "Trade", Window.exchange)
    self.clearButton = button(PAD * 2 + footerWidth, footerY, footerWidth, "Clear Offer", function(window)
        if window.action ~= nil then return end
        window.giving, window.taking = {}, {}
        window.actionError = nil
        window:refreshQuote()
    end)
    self.doneButton = button(PAD * 3 + footerWidth * 2, footerY, footerWidth, getText("UI_Close"), Window.close)
    if self.giftMode then
        self.survivorList:setVisible(false)
        self.takeButton:setVisible(false)
        self.tradeButton.title = "Give Item"
    end
    self.tradeButton:setEnable(false)
end

function Window:toggle(key, item)
    if self.action ~= nil or self.session == nil or not self.session:isValid() then return end
    local selection = self[key]
    if selection[item] then selection[item] = nil
    elseif #selectedItems(selection) < 32 then selection[item] = true
    else self.status = "Up to 32 items can be offered on each side." return end
    self.actionError = nil
    self:refreshQuote()
end

function Window:refreshQuote()
    if self.action ~= nil then return end
    local quote, reason
    if self.giftMode then
        quote, reason = KnoxTradeValuation.quoteGift(self.player, self.survivorId, selectedItems(self.giving))
    else
        quote, reason = KnoxTradeValuation.quote(self.player, self.survivorId,
            selectedItems(self.giving), selectedItems(self.taking))
    end
    self.quote = quote
    self.status = UI.message(self.actionError or (quote ~= nil and quote.reason or reason))
    self.tradeButton.tooltip = self.status
    self.tradeButton:setEnable(self.actionError == nil and self.session ~= nil
        and self.session:isValid() and quote ~= nil and quote.acceptable)
end

function Window:refreshStock()
    local stock, reason = KnoxTradeValuation.stock(self.player, self.survivorId)
    if stock == nil then self:stopBrowsing(reason) return end
    local function fill(list, items)
        local old = list.items[list.selected]
        local selected = old ~= nil and old.item or nil
        local scroll = list:getYScroll()
        list:clear()
        for index, item in ipairs(items) do
            list:addItem(itemName(item, self.player), item)
            if item == selected then list.selected = index end
        end
        list:setYScroll(scroll)
    end
    fill(self.playerList, stock.playerItems)
    if not self.giftMode then fill(self.survivorList, stock.survivorItems) end
    self:refreshQuote()
end

function Window:stopBrowsing(reason)
    self.browsingStopped = true
    KnoxTradeActions.endBrowse(self.session, reason)
    self.status = UI.message(reason)
    self.tradeButton:setEnable(false)
    self.giveButton:setEnable(false)
    self.takeButton:setEnable(false)
    self.clearButton:setEnable(false)
end

function Window:recoverOffer(reason)
    if self.closed then return false end
    if self.session == nil or not self.session:isValid() then
        KnoxTradeActions.endBrowse(self.session, reason)
        local session, failure = KnoxTradeActions.beginBrowse(self.player, self.survivorId)
        self.session = session
        if session == nil then
            self:stopBrowsing(reason or failure)
            return false
        end
    end
    -- A verified rollback or refused admission is reviewable in this same
    -- window. Never auto-submit the old offer or hide its failure message.
    self.browsingStopped, self.actionError = false, reason
    self.giveButton:setEnable(true)
    self.takeButton:setEnable(true)
    self.clearButton:setEnable(true)
    self:refreshStock()
    return not self.browsingStopped
end

function Window:exchange()
    if self.action ~= nil or self.session == nil or not self.session:isValid() then return end
    local action, reason = KnoxTradeActions.queue(self.player, self.survivorId,
        selectedItems(self.giving), selectedItems(self.taking), self.session, self.giftMode and "gift" or nil)
    if action == nil then
        self:recoverOffer(reason)
        return
    end
    self.action, self.status = action, "Exchanging items..."
    self.tradeButton:setEnable(false)
    self.giveButton:setEnable(false)
    self.takeButton:setEnable(false)
    self.clearButton:setEnable(false)
end

function Window:update()
    ISCollapsableWindowJoypad.update(self)
    if self.closed or self.playerList == nil then return end
    if self.action ~= nil then
        if self.action.finished then
            self.status = UI.message(self.action.result)
            if self.action.success then self:close()
            else
                local reason = self.action.result
                self.action = nil
                self:recoverOffer(reason)
            end
        end
        return
    end
    if self.session == nil or not self.session:isValid() then
        if not self.browsingStopped then
            self.browsingStopped = true
            self:stopBrowsing(self.session and self.session.cancelled or "browsing_expired")
        end
        return
    end
    local now = getTimestampMs()
    if now >= self.nextRefreshAt then
        self.nextRefreshAt = now + 1000
        self:refreshStock()
    end
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.isCollapsed or self.playerList == nil then return end
    local line, y = self.lineHeight, self:titleBarHeight() + PAD
    self:drawText("Your inventory", PAD, y, .88, .88, .85, 1, UIFont.Small)
    self:drawText(trim(self.survivorName, self.survivorList.width), self.survivorList.x, y, .88, .88, .85, 1, UIFont.Small)
    self:drawText(trim(self.status, self.width - PAD * 2), PAD, self.statusY, .88, .88, .85, 1, UIFont.Small)
    local counts = self.giftMode
        and ("You give " .. #selectedItems(self.giving) .. " item(s).")
        or ("You offer " .. #selectedItems(self.giving) .. " item(s); they offer " .. #selectedItems(self.taking) .. ".")
    self:drawText(trim(counts, self.width - PAD * 2), PAD, self.statusY + line, .65, .65, .65, 1, UIFont.Small)
    if self.helpLines > 0 then
        local help = self.giftMode and "Double-click / A: select item. Y: give item. B: close."
            or "Double-click / A: offer item. Y: trade. B: close."
        self:drawText(trim(help, self.width - PAD * 2), PAD,
            self.statusY + line * 2, .65, .65, .65, 1, UIFont.Small)
        self:drawText(trim("Equipped, favorite and unsupported items are hidden.", self.width - PAD * 2), PAD,
            self.statusY + line * 3, .65, .65, .65, 1, UIFont.Small)
    end
    self.doneButton.tooltip = self.status
end

function Window:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then self:close()
    elseif button == Joypad.YButton then self:exchange()
    elseif button == Joypad.AButton then setJoypadFocus(self.playerNum, self.playerList)
    else ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData) end
end

function Window:close()
    if self.closed then return end
    self.closed = true
    KnoxTradeActions.endBrowse(self.session, "closed")
    if self.action ~= nil and not self.action.finished then
        self.action.cancelled = "closed"
        self.action:finish(false, "cancelled")
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if windows[self.playerNum] == self then windows[self.playerNum] = nil end
    if JoypadState ~= nil and JoypadState.players[self.playerNum + 1] ~= nil then
        local focus = JoypadState.players[self.playerNum + 1].focus
        if focus == self or focus == self.playerList or focus == self.survivorList then
            setJoypadFocus(self.playerNum, self.previousJoypadFocus)
        end
    end
end

function UI.show(playerNum, survivorId, giftMode)
    local player = getSpecificPlayer(playerNum)
    if player == nil then return nil end
    if windows[playerNum] ~= nil then windows[playerNum]:close() end
    local session, reason = KnoxTradeActions.beginBrowse(player, survivorId)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local width = math.min(math.floor(680*scale), math.max(1, getPlayerScreenWidth(playerNum) - 20))
    local height = math.min(math.floor(500*scale), math.max(1, getPlayerScreenHeight(playerNum) - 20))
    local window = ISCollapsableWindowJoypad.new(Window,
        getPlayerScreenLeft(playerNum) + (getPlayerScreenWidth(playerNum) - width) / 2,
        getPlayerScreenTop(playerNum) + (getPlayerScreenHeight(playerNum) - height) / 2, width, height)
    window.player, window.playerNum, window.survivorId = player, playerNum, survivorId
    window.session, window.giving, window.taking, window.giftMode = session, {}, {}, giftMode == true
    local identity = KnoxPersistence.getSurvivorIdentity(survivorId)
    local name = identity ~= nil and ((identity.forename or "") .. " " .. (identity.surname or "")) or ""
    name = name:match("^%s*(.-)%s*$")
    window.survivorName = name ~= "" and name or "Survivor"
    window.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
    window.resizable, window.pin, window.nextRefreshAt = false, true, 0
    window.backgroundColor = { r = .06, g = .06, b = .06, a = .94 }
    window.borderColor = { r = .28, g = .28, b = .28, a = 1 }
    window:setTitle(trim((window.giftMode and "Give Item - " or "Trade - ") .. window.survivorName, width - 80))
    UILayout.bindInteractionWindow(window)
    window:initialise()
    window:setRenderThisPlayerOnly(playerNum)
    window:addToUIManager()
    windows[playerNum] = window
    if session == nil then window:stopBrowsing(reason) else window:refreshStock() end
    if JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil then
        window.previousJoypadFocus = JoypadState.players[playerNum + 1].focus
        setJoypadFocus(playerNum, window.playerList)
    end
    return window
end

function UI.showGift(playerNum, survivorId)
    return UI.show(playerNum, survivorId, true)
end

function UI.closeAll()
    for _, window in pairs(windows) do window:close() end
end

Events.OnGameStart.Add(UI.closeAll)
Events.OnMainMenuEnter.Add(UI.closeAll)
Events.OnResolutionChange.Add(UI.closeAll)
Events.OnPlayerDeath.Add(function(player)
    for _, window in pairs(windows) do if window.player == player then window:close() end end
end)
return UI
