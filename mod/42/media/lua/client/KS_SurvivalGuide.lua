-- Knox Survivors — the mod's page in the vanilla Survival Guide (F1), plus the
-- one-time notice that points at it. Guide.PAGES is the only copy of the help
-- text, so the pages and the greeting cannot disagree about how it is played.

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"

local UILayout = require "KS_SurvivorUILayout"

local Guide = rawget(_G, "KnoxSurvivorsGuide") or {}
_G.KnoxSurvivorsGuide = Guide

Guide.ENTRY_ID = "KnoxSurvivors_Guide"
Guide.ENTRY_NAME = "Knox Survivors"
Guide.SEEN_FIELD = "KnoxGuideSeen"

-- One page, short enough to read in a pause. Every line names something the
-- player can do now; no line describes a system that has no executor.
Guide.PAGES = {
    -- The list mirrors vanilla: one category row, then short indented pages. A
    -- title as long as a sentence is what clipped every row at the list edge.
    -- Every line names something the player can do, in the words the panel uses,
    -- so the guide and the notebook cannot describe the same thing twice.
    { id = "KnoxSurvivors_Guide", title = "Knox Survivors", lines = {
        "A few survivors, a county with other people in it, and a home you choose.",
        "",
        "Your people need food, water, beds, tools and a roof. They work, they travel for supplies, and they come back - or they do not.",
        "",
        "Start here",
        "1. Press F to talk to a survivor. Conversation builds trust, and trust is what lets you recruit.",
        "2. Right-click the floor inside a house you want, then Knox Survivors > Establish Home Base.",
        "3. Right-click a survivor you lead to give orders, or open the notebook to run the whole home.",
        "",
        "F1 opens this guide at any time. The pages below cover the base, orders, people, storage and threats.",
    } },
    { id = "KnoxSurvivors_Guide_Base", title = "Your base", sub = true, lines = {
        "A base is a building you have entered, cleared and claimed. Right-click the floor inside it and choose Establish Home Base.",
        "",
        "What a base does",
        "- It stores what your people eat, drink and work with.",
        "- It provides work: cooking, farming, water, repairs, barricades and hauling.",
        "- It has to be cleared. Zombies inside are a problem, not a detail.",
        "",
        "The notebook has four pages:",
        "- Base & Work: boundary, areas, the job queue and storage.",
        "- Crew & Schedule: who lives here, their hours, roles and tonight's guard.",
        "- Stores & Stock: how much of each supply to keep, and the yard.",
        "- Missions and World: trips away, and the county around you.",
    } },
    { id = "KnoxSurvivors_Guide_Orders", title = "Orders", sub = true, lines = {
        "Right-click a survivor you lead to see the orders: Follow, Guard, Scavenge, Hold Position, Return to Base, Resume Normal Duty and Dismiss.",
        "The talk panel (F) offers the same orders as buttons, along with conversation.",
        "",
        "People refuse work they cannot do, and they say what is missing. Nothing is repaired or supplied silently.",
        "An away team leaves for supplies and brings back what it found - or it does not come back.",
        "A direct order outranks routine work. Order someone to follow you and their base job goes back to the queue.",
    } },
    { id = "KnoxSurvivors_Guide_People", title = "People", sub = true, lines = {
        "Every survivor has needs, a mood, trust and a schedule.",
        "Talking raises trust. Hunger, thirst and exhaustion wear it down again.",
        "",
        "Crew & Schedule lists everyone who lives here and what they are doing right now.",
        "A role is the work someone prefers when they are free. A preference decides which jobs they take when nothing is ordered. Neither one replaces a direct order.",
        "Hours are painted, not typed: pick Sleep, Work, Patrol, Guard, Leisure or Free, then click the hour blocks. Save Hours applies the draft.",
    } },
    { id = "KnoxSurvivors_Guide_Storage", title = "Storage", sub = true, lines = {
        "Give a container to a base once and it sorts itself: books to shelves, tools to toolboxes, and everything else to general storage.",
        "",
        "Container Item Filters adds a group, a native category, or one exact item type.",
        "A survivor's pack is filled from base storage before they leave on a supply run.",
        "Logs and building materials can be dropped on a yard floor. A yard is a storage area with its own targets, and its stock is listed in the notebook.",
    } },
    { id = "KnoxSurvivors_Guide_Threats", title = "Threats", sub = true, lines = {
        "Other groups can raid an established base. Count your people, close the doors, and barricade the outside walls first.",
        "Reputation and trade decide whether a group is friendly, wary or hostile.",
        "A warning comes before a raid. The recent-events digest lists what happened afterwards.",
    } },
}

Guide.TEXT = table.concat(Guide.PAGES[1].lines, "<LINE>")

Guide.NOTICE_TEXT = "You are not alone anymore. Press F1 and open the Knox Survivors page"
    .. " of the Survival Guide to learn how to build a home, give orders and keep your people fed."

-- The wrap is a layout rule, not a notice rule: it lives in the shared layout
-- module so the notice and every other paragraph break at one measurement.
Guide.wrapLines = UILayout.wrapLines

-- The guide reserves a 960x480 video area above the page text, so a text-only
-- page lived in a 150-pixel strip under a blank rectangle and needed a scrollbar
-- for four lines. Knox pages carry no video: the area is collapsed and the
-- description takes the whole right side.
local function installTextOnlyLayout(guide)
    if guide == nil or guide.knoxTextOnly == true then return end
    guide.knoxTextOnly = true
    local baseClick = guide.onClickList
    local baseRestore = guide.restorePosition
    local function expand(panel)
        if panel == nil then return end
        if panel.videoRichText ~= nil then
            panel.videoRichText:setVisible(false)
            panel.videoRichText:setHeight(0)
        end
        if panel.descriptionRichText ~= nil and panel.listBox ~= nil then
            panel.descriptionRichText:setY(panel.listBox:getY())
            panel.descriptionRichText:setHeight(panel.listBox:getHeight())
            pcall(function() panel.descriptionRichText:paginate() end)
        end
    end
    function guide:onClickList()
        if baseClick ~= nil then baseClick(self) end
        expand(self)
    end
    function guide:restorePosition()
        if baseRestore ~= nil then baseRestore(self) end
        expand(self)
    end
end

-- The guide is rebuilt from the Java entry list on every open, so the section
-- is appended to the class method rather than to one window instance.
local function installGuideEntry()
    if Guide.installed then return end
    local guide = rawget(_G, "SurvivalGuide")
    if guide == nil or type(guide.populateList) ~= "function" then return end
    Guide.installed = true
    local basePopulate = guide.populateList
    -- One page per system, appended after the vanilla pages. The left list is
    -- the tab strip: a player reads the overview, then the page they need,
    -- instead of scrolling one long page.
    function guide:populateList()
        basePopulate(self)
        if self.listBox == nil then return end
        local medium = (self.smallResolution == true) and UIFont.NewSmall or UIFont.NewMedium
        for _, page in ipairs(Guide.PAGES) do
            -- A sub page is indented and drawn in the small font exactly as a
            -- vanilla guide sub-entry is, so the list reads as one category with
            -- pages under it instead of six long rows.
            local sub = page.sub == true
            local name = sub and ("    " .. page.title) or page.title
            local width = getTextManager():MeasureStringX(
                sub and UIFont.NewSmall or medium, name) + 35
            if width > self.listBox:getWidth() then self.listBox:setWidth(width) end
            self.listBox:addItem(name, {
                title = page.title,
                description = table.concat(page.lines, "<LINE>"),
                subCategory = sub or nil,
                id = page.id,
            })
        end
    end
    installTextOnlyLayout(guide)
    if guide.instance ~= nil then
        pcall(function()
            guide.instance:populateList()
            guide.instance:restorePosition()
            guide.instance:onClickList()
        end)
    end
end

function Guide.open()
    local guide = rawget(_G, "SurvivalGuide")
    if guide == nil then return false end
    if guide.instance == nil and type(rawget(_G, "createSurvivalGuide")) == "function" then
        pcall(createSurvivalGuide)
    end
    local instance = guide.instance
    if instance == nil then return false end
    pcall(function()
        instance:populateList()
        instance:restorePosition()
    end)
    instance:setVisible(true)
    instance:bringToTop()
    for index, option in ipairs(instance.listBox.items) do
        if option.item ~= nil and option.item.id == Guide.ENTRY_ID then
            instance.listBox.selected = index
            instance:onClickList()
            break
        end
    end
    return true
end

-- The flag lives on the player's own ModData, which is written with the save.
-- In a single-player save it is per save; on a server it is the player's own
-- record on that server. No new store is created for one boolean.
local function playerData()
    local player = getSpecificPlayer(0)
    return player ~= nil and player:getModData() or nil
end

local function hasSeen()
    local data = playerData()
    return data ~= nil and data[Guide.SEEN_FIELD] == true
end

local function markSeen()
    local data = playerData()
    if data ~= nil then data[Guide.SEEN_FIELD] = true end
end

local function closeNotice(panel, seen)
    if seen then markSeen() end
    if panel ~= nil then
        panel:setVisible(false)
        panel:removeFromUIManager()
    end
    Guide.notice = nil
    if JoypadState ~= nil and JoypadState.players[1] ~= nil then
        setJoypadFocus(0, nil)
    end
end

local function showNotice()
    if Guide.notice ~= nil or hasSeen() then return end
    local scale = UILayout.uiScale()
    local pad = math.max(12, math.floor(16 * scale))
    local buttonH = math.max(22, math.floor(28 * scale))
    local headingH = math.max(16, math.floor(22 * scale))
    local gap = math.max(6, math.floor(8 * scale))
    local width = math.max(320, math.floor(460 * scale))
    local screenW, screenH = UILayout.screenSize()
    if screenW ~= nil and screenH ~= nil and screenW > 0 and screenW > 16 then
        width = math.min(width, math.floor(screenW) - 16)
    end
    -- The sheet is built from what it has to contain. A longer message or a
    -- bigger font makes the box taller; it never pushes the last line past the
    -- edge, which is what a fixed 460x210 sheet did.
    local bodyWidth = width - pad * 2
    local smallH = getTextManager():getFontHeight(UIFont.Small)
    local lineH = math.max(smallH, math.floor(smallH * 1.25))
    local lines = Guide.wrapLines(Guide.NOTICE_TEXT, bodyWidth, function(value)
        return getTextManager():MeasureStringX(UIFont.Small, value)
    end)
    local tickH = math.max(18, math.floor(20 * scale))
    local tickGap = math.max(10, math.floor(14 * scale))
    local height = pad + headingH + gap + (#lines * lineH) + tickGap
        + tickH + tickGap + buttonH + pad
    if screenH ~= nil and screenH > 0 then
        height = math.min(height, math.floor(screenH) - 16)
    end
    local footerY = height - pad - buttonH
    local panel = ISPanel:new(
        (getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height)
    panel:initialise()
    panel:addToUIManager()
    panel:setAlwaysOnTop(true)
    -- One sheet, one palette: the notice is a Knox window like any other, so
    -- it takes the shared charcoal and hairline instead of its own greys.
    UILayout.tintWindow(panel)

    local bone, muted = UILayout.theme.bone, UILayout.theme.muted
    local heading = ISLabel:new(pad, math.max(8, math.floor(14 * scale)),
        math.max(16, math.floor(22 * scale)), "Knox Survivors",
        bone[1], bone[2], bone[3], 1, UIFont.Medium, true)
    heading:initialise()
    panel:addChild(heading)

    -- ISLabel draws one line and never wraps, which is why this paragraph ran
    -- off the right edge of the sheet: it had a width but no wrapping. One label
    -- per measured line keeps the text inside the box, at one weight, with no
    -- change of wording.
    local bodyY = pad + headingH + gap
    for index, line in ipairs(lines) do
        local label = ISLabel:new(pad, bodyY + (index - 1) * lineH, lineH, line,
            muted[1], muted[2], muted[3], 1, UIFont.Small, true)
        label:initialise()
        panel:addChild(label)
    end

    local tickY = footerY - tickGap - tickH

    local tick = ISTickBox:new(pad, tickY, 20, 20, "", panel, nil)
    tick:initialise()
    if tick.instantiate ~= nil then tick:instantiate() end
    tick:addOption("Don't show this again")
    panel:addChild(tick)

    local guideButton = ISButton:new(pad, footerY, math.max(110, math.floor(150 * scale)),
        buttonH, "Open the guide", nil,
        function() closeNotice(panel, true); Guide.open() end)
    guideButton:initialise()
    UILayout.tintPrimary(guideButton)
    panel:addChild(guideButton)

    local closeButton = ISButton:new(width - pad - math.max(72, math.floor(100 * scale)),
        footerY, math.max(72, math.floor(100 * scale)), buttonH, "Close", nil,
        function() closeNotice(panel, tick:isSelected(1)) end)
    closeButton:initialise()
    UILayout.tintButton(closeButton)
    panel:addChild(closeButton)

    Guide.notice = panel
end

local function onGameStart()
    installGuideEntry()
    if Guide.noticeQueued then return end
    Guide.noticeQueued = true
    if hasSeen() then return end
    -- Let the world finish loading and the first frame settle before a panel
    -- appears over it; OnTick is the existing frame hook, not a new timer.
    local ticks = 90
    local function tick()
        ticks = ticks - 1
        if ticks > 0 then return end
        Events.OnTick.Remove(tick)
        if hasSeen() then return end
        showNotice()
    end
    Events.OnTick.Add(tick)
end

Events.OnGameStart.Add(onGameStart)
