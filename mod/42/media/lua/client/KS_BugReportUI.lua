require "KS_BugReport"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTickBox"
require "KS_SurvivorUILayout"

local R = KnoxBugReport
local Report = ISPanel:derive("KS_BugReportWindow")
local lastDraft

local function diagnostics()
    local d = {}
    pcall(function() d.gameVersion = getCore():getVersion() end)
    -- Both runtime adapters can expose the same API; no identity is inferred.
    pcall(function() d.living = #KnoxPersistence.getLivingWorldSurvivorIds() end)
    pcall(function() d.maxActive = KnoxSettings.maxActiveSurvivors() end)
    pcall(function() d.active = KnoxJavaBridge:getActiveNpcCount() end)
    return R.diagnostics(d)
end

function Report:createChildren()
    ISPanel.createChildren(self)
    local width = self.width - 24
    self.entries = {}
    local names = { "summary", "steps", "expected", "actual" }
    local g = self.geometry
    local limits = { 120, 1000, 500, 500 }
    for i, name in ipairs(names) do
        local entry = ISTextEntryBox:new("", 12, g.entries[i].y, width, g.entries[i].h)
        entry:initialise(); entry:instantiate(); self:addChild(entry)
        entry:setMaxTextLength(limits[i])
        if i > 1 then entry:setMultipleLine(true) end
        self.entries[name] = entry
    end
    self.ack = ISTickBox:new(12, g.ack, width, g.row, "", self, nil)
    self.ack:initialise(); self.ack:instantiate(); self.ack:addOption("I understand the report will be public.")
    self:addChild(self.ack)
    local function button(x, label, action, w)
        local b = ISButton:new(x, g.buttons, w, g.row, label, self, action)
        b:initialise(); b:instantiate(); pcall(KnoxSurvivorUILayout.tintButton, b); self:addChild(b); return b
    end
    local m = getTextManager()
    local exportWidth = m:MeasureStringX(UIFont.Small, "Export diagnostics") + 24
    local draftWidth = m:MeasureStringX(UIFont.Small, "Open GitHub draft") + 24
    local closeWidth = m:MeasureStringX(UIFont.Small, "Close") + 24
    button(12, "Export diagnostics", Report.export, exportWidth)
    button(20 + exportWidth, "Open GitHub draft", Report.openDraft, draftWidth)
    button(self.width - 12 - closeWidth, "Close", Report.close, closeWidth)
end

function Report:render()
    ISPanel.render(self)
    local g = self.geometry
    self:drawText("Report a Knox Survivors bug", 12, g.title, 1, 1, 1, 1, UIFont.Medium)
    self:drawText("Review your text in GitHub before posting publicly.", 12, g.notice, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Optional: attach the exported diagnostics file yourself.", 12, g.notice + g.small, 1, 1, 1, 1, UIFont.Small)
    for i, label in ipairs({ "Summary", "Steps to reproduce", "Expected", "Actual" }) do
        self:drawText(label, 12, g.labels[i], 1, 1, 1, 1, UIFont.Small)
    end
    if self.message then
        self:drawText(KnoxSurvivorUILayout.fitText(UIFont.Small, self.message, self.width - 24), 12, g.message, 1, 0.8, 0.4, 1, UIFont.Small)
    end
end

function Report:close()
    self:setVisible(false)
end

function Report:export()
    local ok = pcall(function()
        local writer = getFileWriter("KnoxSurvivors-diagnostics.txt", true, false)
        if not writer then error("file unavailable") end
        writer:write(diagnostics()); writer:close()
    end)
    self.message = ok and "Saved in Zomboid/Lua/KnoxSurvivors-diagnostics.txt" or "Could not write diagnostics."
end

function Report:openDraft()
    local fields = {}
    for name, entry in pairs(self.entries) do fields[name] = entry:getText() end
    local now = getTimestampMs()
    local valid, err = R.validate(fields, self.ack:isSelected(1), now, lastDraft)
    if not valid then self.message = err; return end
    local url; url, err = R.url(valid, diagnostics())
    if not url then self.message = err; return end
    local ok = pcall(function() openUrl(url) end)
    if ok then lastDraft = now; self.message = "Draft opened. Review it before posting."
    else self.message = "Could not open the browser." end
end

local function sync()
    local main = MainScreen and MainScreen.instance
    if not main or not main.inGame then return end
    if not main:isVisible() or not main.bottomPanel or not main.bottomPanel:isVisible() then
        if main.knoxBugButton then main.knoxBugButton:setVisible(false) end
        if main.knoxBugWindow then main.knoxBugWindow:setVisible(false) end
        return
    end
    local manager = getTextManager()
    local small = KnoxSurvivorUILayout.fontHeight() or manager:getFontHeight(UIFont.Small)
    local medium = manager:getFontHeight(UIFont.Medium)
    local buttonWidth = manager:MeasureStringX(UIFont.Small, "Report a bug") + 24
    local requiredWidth = math.max(
        manager:MeasureStringX(UIFont.Small, "Optional: attach the exported diagnostics file yourself.") + 24,
        manager:MeasureStringX(UIFont.Small, "I understand the report will be public.") + 60,
        manager:MeasureStringX(UIFont.Medium, "Report a Knox Survivors bug") + 24,
        manager:MeasureStringX(UIFont.Small, "Export diagnostics") + manager:MeasureStringX(UIFont.Small, "Open GitHub draft") + manager:MeasureStringX(UIFont.Small, "Close") + 112)
    local geometry = R.layout(main.width, main.height, small, medium, requiredWidth)
    if geometry then geometry.small = small end
    main.knoxBugGeometry = geometry
    if not main.knoxBugButton then
        local button = ISButton:new(0, 0, buttonWidth, math.max(26, small + 8), "Report a bug", nil, function()
            if main.knoxBugWindow then main.knoxBugWindow:setVisible(true); main.knoxBugWindow:bringToTop(); return end
            local current = main.knoxBugGeometry
            if not current then return end
            local w, h = current.width, current.height
            local window = Report:new(math.floor((main.width - w) / 2), math.floor((main.height - h) / 2), w, h)
            window.geometry = current
            window:initialise(); window:instantiate(); main:addChild(window)
            main.knoxBugWindow = window
        end)
        button:initialise(); button:instantiate(); pcall(KnoxSurvivorUILayout.tintButton, button); main:addChild(button); main.knoxBugButton = button
    end
    local button = main.knoxBugButton
    button:setWidth(buttonWidth); button:setHeight(math.max(26, small + 8))
    if main.knoxBugWindow and (not geometry or main.knoxBugWindow.width ~= geometry.width or main.knoxBugWindow.height ~= geometry.height) then
        main:removeChild(main.knoxBugWindow)
        main.knoxBugWindow = nil
    elseif main.knoxBugWindow then
        main.knoxBugWindow:setX(math.floor((main.width - geometry.width) / 2))
        main.knoxBugWindow:setY(math.floor((main.height - geometry.height) / 2))
    end
    local visible = geometry and main:isVisible() and main.bottomPanel and main.bottomPanel:isVisible()
    if not visible then
        button:setVisible(false)
        if main.knoxBugWindow then main.knoxBugWindow:setVisible(false) end
        return
    end
    local obstacles = {}
    for _, child in pairs(main:getChildren()) do
        if child ~= button and child ~= main.knoxBugWindow and child:isVisible() then
            obstacles[#obstacles + 1] = { x = child:getX(), y = child:getY(), w = child:getWidth(), h = child:getHeight() }
        end
    end
    -- Other mods may have top-level windows outside MainScreen's child list.
    -- If inspection is unavailable, do not guess that the screen is clear.
    local inspected = pcall(function()
        local ui = UIManager.getUI()
        local found = false
        for i = 0, ui:size() - 1 do
            local element = ui:get(i)
            if element == main.javaObject then found = true
            elseif found and element:isVisible() then
                obstacles[#obstacles + 1] = { x = element:getX(), y = element:getY(), w = element:getWidth(), h = element:getHeight() }
            end
        end
        if not found then error("pause menu is not registered") end
    end)
    if not inspected then button:setVisible(false); return end
    if main.knoxBugWindow and main.knoxBugWindow:isVisible() then
        local w = main.knoxBugWindow
        obstacles[#obstacles + 1] = { x = w:getX(), y = w:getY(), w = w:getWidth(), h = w:getHeight() }
    end
    local x, y = R.place(main.width, main.height, button.width, button.height, obstacles)
    button:setVisible(x ~= nil)
    if x then button:setX(x); button:setY(y) end
end

-- UI draw continues while the game is paused; simulation ticks need not.
Events.OnPreUIDraw.Add(sync)
