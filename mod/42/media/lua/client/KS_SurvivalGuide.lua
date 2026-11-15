-- Knox Survivors - the mod's page in the vanilla Survival Guide (F1), plus the
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
    -- The vanilla guide's left-hand list is the tab strip; every entry below is
    -- one tab for one part of playing. Titles stay short enough for the list,
    -- and every line must name a control the mod really has: a guide page may
    -- not describe a system that has no executor.
    { id = "KnoxSurvivors_Guide", title = "Knox Survivors", lines = {
        "Knox Survivors adds persistent people to the county: people who travel with companions, live at a shared home, work with real supplies and act on their own.",
        "",
        "The left-hand list is the tab strip. Each part of life with your people has its own page: recruiting, setting up a base, beds, storage and hauling, orders and jobs, autonomy, and threats and factions.",
        "",
        "Start here",
        "1. Right-click a nearby survivor and choose Talk. In isometric view, you can also use F. With Viewpoint, use the crosshair interaction.",
        "2. Inside the building you want, right-click the floor, open Knox Survivors, and choose Establish Home Base.",
        "3. Open Orders in a companion's talk panel. The notebook runs the home while you are elsewhere.",
        "",
        "F1 opens and closes this guide; the key is rebindable in settings under Toggle Survival Guide.",
        "The vanilla pages below ours belong to the base game. If a vanilla page looks wrong or is missing, check the 'Show Survival Guide' tick box at the bottom of this window, and tell the team which page you expected and what it showed.",
    } },
    { id = "KnoxSurvivors_Guide_Recruit", title = "Recruiting", sub = true, lines = {
        "Right-click a nearby survivor and choose Talk. In isometric view, press F instead; with Viewpoint, use the crosshair interaction.",
        "",
        "Conversation builds trust. Recruitment also depends on the person, their group and the situation, and someone can refuse.",
        "A new join is part of your group: they can travel with you or live and work at home.",
        "When a group grows, it can move into one of the larger group homes.",
    } },
    { id = "KnoxSurvivors_Guide_Base", title = "Setting up a base", sub = true, lines = {
        "A base is a building you have entered, cleared and claimed. Right-click the floor inside it, open Knox Survivors and choose Establish Home Base.",
        "It has to be cleared: zombies inside are a problem, not a detail.",
        "",
        "What a base does",
        "- It stores what your people eat, drink and work with.",
        "- It provides work: cooking, farming, water, repairs, barricades and hauling.",
        "",
        "The notebook has five tabs:",
        "- Base & Work: boundary, areas, the job queue and storage.",
        "- Crew & Schedule: who lives here, their hours, roles and tonight's guard.",
        "- Stores & Stock: how much of each supply to keep, and the yard.",
        "- Missions: dispatch teams and review their results.",
        "- World: known people, groups and events.",
    } },
    { id = "KnoxSurvivors_Guide_Beds", title = "Beds", sub = true, lines = {
        "Right-click a real bed inside your base, open Knox Survivors and choose Assign Bed.",
        "Pick the person it belongs to: they use that bed when they sleep here. The menu shows who is assigned, and an Unassign entry frees the bed.",
        "If an assigned bed stops being sleepable, the menu names the problem and offers a way out instead of failing silently at night.",
    } },
    { id = "KnoxSurvivors_Guide_Storage", title = "Storage & hauling", sub = true, lines = {
        "Assign storage to your base, then check its category and filters. Residents move real items when a suitable job and destination are available.",
        "",
        "Container Item Filters adds a group, a native category, or one exact item type.",
        "Role kits show what a resident needs. Missing equipment must come from real supplies; assigning a role does not create items.",
        "Logs and building materials dropped on a yard floor become yard stock, and the yard is listed in the notebook.",
        "",
        "When residents organize at home, they pick up items lying loose on the floor and stock them where the filters and yards send them.",
        "A supply run that ends while carrying stock sets it down at the yard's drop square instead of scattering it.",
    } },
    { id = "KnoxSurvivors_Guide_Orders", title = "Orders & jobs", sub = true, lines = {
        "Talk to someone you lead and open Orders. Available actions depend on whether they are a companion or a resident.",
        "The emote radial also includes Knox orders when enabled. Extra right-click orders are optional.",
        "",
        "People refuse work they cannot do, and they say what is missing. Nothing is repaired or supplied silently.",
        "An away team leaves for supplies and brings back what it found - or it does not come back.",
        "A direct order outranks routine work: order someone to follow you and their base job returns to the queue.",
    } },
    { id = "KnoxSurvivors_Guide_Autonomy", title = "Autonomy", sub = true, lines = {
        "Your people act on their own when you are not commanding: they eat, drink, work and stop to rest when the body needs it instead of pushing through.",
        "",
        "A role is the work someone prefers when they are free; scheduled hours decide when they work. Either yields to a direct order.",
        "",
        "They treat themselves with what is at hand: bandages, disinfectant, stitches, splints and antibiotics when they carry them.",
        "Meeting a living stranger can be said out loud, once per remembered person, not repeated.",
        "",
        "People can die. The sandbox setting 'Your People Continue After Death' decides whether the rest of your people keep going.",
    } },
    { id = "KnoxSurvivors_Guide_Threats", title = "Threats & factions", sub = true, lines = {
        "Faction raids are experimental. Check Faction Raids in Sandbox; raids also need Knox Events, NPC Factions and hostile encounters. Prepare real weapons, supplies and guard posts; keep an exit usable.",
        "Reputation and trade decide whether a group is friendly, wary or hostile.",
        "A warning comes before a raid. The recent-events digest lists what happened afterwards.",
    } },
}

Guide.TEXT = table.concat(Guide.PAGES[1].lines, "<LINE>")

Guide.NOTICE_TEXT = "You are not alone anymore. Press F1 and open the Knox Survivors chapters"
    .. " of the Survival Guide: build a home, recruit people, assign beds and storage, give orders, and understand survivor autonomy."

-- The wrap is a layout rule, not a notice rule: it lives in the shared layout
-- module so the notice and every other paragraph break at one measurement.
Guide.wrapLines = UILayout.wrapLines

-- The guide reserves a 960x480 video area above the page text, so a text-only
-- page lived in a 150-pixel strip under a blank rectangle and needed a scrollbar
-- for four lines. Knox pages carry no video: the area is collapsed and the
-- description takes the whole right side.
function Guide.layoutPage(panel)
    if panel == nil or panel.videoRichText == nil or panel.descriptionRichText == nil
        or panel.listBox == nil then return end
    local video, text = panel.videoRichText, panel.descriptionRichText
    if panel.knoxOriginalLayout == nil then
        panel.knoxOriginalLayout = { videoHeight = video:getHeight(),
            width=panel.getWidth~=nil and panel:getWidth() or nil,
            height=panel.getHeight~=nil and panel:getHeight() or nil }
    end
    local page = panel.selectedItem
    local knox = page ~= nil and type(page.id) == "string"
        and page.id:find("KnoxSurvivors_Guide", 1, true) == 1
    local original = panel.knoxOriginalLayout
    if getCore~=nil and original.width~=nil and original.height~=nil then
        local screenWidth,screenHeight=getCore():getScreenWidth(),getCore():getScreenHeight()
        panel:setWidth(knox and math.min(original.width,screenWidth-32) or original.width)
        panel:setHeight(knox and math.min(original.height,screenHeight-32) or original.height)
        panel:setX(math.max(0,(screenWidth-panel:getWidth())/2))
        panel:setY(math.max(0,(screenHeight-panel:getHeight())/2))
    end
    video:setVisible(not knox)
    video:setHeight(knox and 0 or original.videoHeight)
    text:setY(panel.listBox:getY()+(knox and 0 or original.videoHeight))
    text:setHeight(math.max(1,panel.listBox:getHeight()-(knox and 0 or original.videoHeight)))
    -- The native list can grow when labels are measured. Reflow against the
    -- actual right-hand viewport, rather than retaining a stale paragraph width.
    if panel.getWidth ~= nil and panel.listBox.getRight ~= nil then
        text:setWidth(math.max(1, panel:getWidth() - panel.listBox:getRight()))
    end
    text:paginate()
    video:paginate()
end

local function installTextOnlyLayout(guide)
    if guide == nil or guide.knoxTextOnly == true then return end
    guide.knoxTextOnly = true
    local baseClick, baseRestore = guide.onClickList, guide.restorePosition
    function guide:onClickList()
        if baseClick ~= nil then baseClick(self) end
        Guide.layoutPage(self)
    end
    function guide:restorePosition()
        if baseRestore ~= nil then baseRestore(self) end
        if self.knoxOriginalLayout ~= nil then
            self.knoxOriginalLayout.width = self:getWidth()
        end
        Guide.layoutPage(self)
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
