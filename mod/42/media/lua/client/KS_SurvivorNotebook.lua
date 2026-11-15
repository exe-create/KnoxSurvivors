require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISTabPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "ISUI/ISTextBox"
require "ISUI/ISModalRichText"
require "KS_Persistence"
require "KS_AwayTeamExecutor"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_BaseTaskBoard"
require "KS_BaseJobs"
require "KS_BaseStorage"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_BaseHighlights"
require "KS_BaseZoneSelector"
require "KS_BaseTerritorySelector"
require "KS_CompanionService"
require "KS_SurvivorCard"
require "KS_ActivityFeed"
require "KS_OrderCatalog"
local UILayout = require "KS_SurvivorUILayout"
-- Base management wears the creator sheet material so its buttons and
-- list frames have an edge against the background.
local sheetTheme = UILayout.sheetTheme()

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorNotebookWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10

local function trimText(font, value, availableWidth)
    return UILayout.fitText(font, value, availableWidth)
end

local function drawListText(list, y, item, alpha)
    -- A faction row reserves the right edge for its standing bar; every other
    -- list keeps the full width.
    local reserve = item.knoxStanding ~= nil and 92 or 0
    -- A row that only exists to explain an empty list is guidance, not content.
    -- It reads in the muted tone so it can never be mistaken for a data row.
    local inert = item.knoxKey == "none" or item.knoxKey == "empty"
    local bone = inert and sheetTheme.muted or sheetTheme.bone
    list:drawText(trimText(list.font, item.text or "", list:getWidth() - 20 - reserve),
        10, y + 2, bone[1], bone[2], bone[3], alpha, list.font)
end

-- Draw a thin row divider and a 2 px accent, matching the HUD.
-- Selected rows use amber; other rows may use their category colour.
-- Keep text labels so colour is never the only identifier.
local function drawListRow(list, y, item, accent)
    local theme = UILayout.sheetTheme()
    local border, amber = theme.border, theme.amber
    local height = math.max(1, list.itemheight - 1)
    -- Empty-list hints have no divider or accent because they are not selectable.
    if item.knoxKey == "none" or item.knoxKey == "empty" then return end
    list:drawRect(0, y + height, list:getWidth(), 1, 0.35,
        border[1], border[2], border[3])
    local colour = list.selected == item.index and amber or accent
    if colour ~= nil then
        local r = colour.r or colour[1]
        local g = colour.g or colour[2]
        local b = colour.b or colour[3]
        list:drawRect(0, y, 2, height, 0.95, r, g, b)
    end
end

local function addRow(list, key, description)
    -- Vanilla addItem takes display text first, then the caller's data.
    -- Keep stable identity separately for selection across a refresh.
    local row = list:addItem(description, key, description)
    row.knoxKey = key
    return row
end

-- Multi-line page feedback keeps its full source text between reflows.
local function layoutPageFeedback(view, label, key, text, x, y, width)
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local lines = UILayout.wrapLines(tostring(text or ""), math.max(1, width), measure)
    if #lines == 0 then lines = { "" } end
    local extras = view[key] or {}
    view[key] = extras
    for index, line in ipairs(lines) do
        local target = index == 1 and label or extras[index - 1]
        if target == nil then
            target = ISLabel:new(x, y, fontH + 2, "", label.r, label.g, label.b, label.a, UIFont.Small, true)
            target:initialise(); view:addChild(target); extras[index - 1] = target
        end
        target:setNameWithoutMoving(line)
        target:setX(x); target:setY(y + (index - 1) * (fontH + 2))
        target:setHeight(fontH + 2); target:setVisible(true)
        target.tooltip = text
    end
    for index = #lines, #extras do extras[index]:setVisible(false) end
    return y + #lines * (fontH + 2)
end

local ZONE_TYPES = {
    { label = "Guard Post", kind = "guard" },
    { label = "Patrol Area", kind = "patrol" },
    { label = "Farming Area", kind = "farming" },
    -- No cooking area: survivors cook at any powered stove or microwave in
    -- home territory automatically, and eat/drink on their own needs.
    { label = "Woodcutting Area", kind = "woodcutting" },
    { label = "Log Yard", kind = "log_processing" },
    { label = "Corpse Drop Area", kind = "corpse" },
}
local ZONE_COLORS = {
    guard = { r=0.85, g=0.20, b=0.20 }, patrol = { r=0.85, g=0.55, b=0.15 },
    farming = { r=0.20, g=0.70, b=0.20 }, woodcutting = { r=0.55, g=0.35, b=0.15 },
    log_processing = { r=0.60, g=0.42, b=0.18 }, corpse = { r=0.55, g=0.55, b=0.55 },
    cooking = { r=0.75, g=0.35, b=0.30 },
    repair = { r=0.20, g=0.50, b=0.85 },
    general = { r=0.52, g=0.52, b=0.75 },
}
local ATTENTION_PAD = 8
local ATTENTION_ACTION_WIDTH = 108
local ATTENTION_ROW_HEIGHT = BUTTON_HGT + 2
local ATTENTION_HEIGHT = ATTENTION_PAD * 2 + FONT_HGT_SMALL + 4
    + ATTENTION_ROW_HEIGHT * 3
-- Keep the Notebook's resident-role picker on the same catalogue used by the
-- context menu and party orders. This prevents a new base preference from
-- silently appearing in one UI but not the other.
local function baseJobChoices()
    local choices = {}
    for _, value in ipairs(KnoxOrderCatalog.basePreferenceOrder or {}) do
        local entry = KnoxOrderCatalog.basePreferences[value]
        if entry ~= nil then
            choices[#choices + 1] = {
                label = value == "hauling" and "Move Corpses"
                    or entry.label or value,
                value = value,
            }
        end
    end
    return choices
end
local BASE_JOB_CHOICES = baseJobChoices()
local function baseRoleChoices()
    local choices = { { label = "No Role (Automatic)", value = "auto" } }
    for _, value in ipairs(KnoxOrderCatalog.baseRoleOrder or {}) do
        local entry = KnoxOrderCatalog.baseRoles ~= nil
            and KnoxOrderCatalog.baseRoles[value] or nil
        if entry ~= nil then
            choices[#choices + 1] = {
                label = entry.label or value,
                value = value,
            }
        end
    end
    return choices
end
local BASE_ROLE_CHOICES = baseRoleChoices()
local function zoneSize(z)
    if not z or not z.x1 then return nil,nil,nil end
    local w=math.abs(tonumber(z.x2)-tonumber(z.x1))+1
    local h=math.abs(tonumber(z.y2)-tonumber(z.y1))+1
    return w,h,w*h
end

local function workStatusFor(base, survivorId)
    if base == nil or survivorId == nil then return nil end
    if KnoxPersistence.getBaseResidentWorkStatus ~= nil then
        return KnoxPersistence.getBaseResidentWorkStatus(survivorId, base.id)
    end
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.state == "claimed"
            and tostring(task.claimedBy or "") == tostring(survivorId) then
            return { state = "claimed", taskType = task.type }
        end
    end
    return { state = "idle" }
end

local RESOURCE_LABELS = {
    food="Food", water="Water", medical="Medical", weapons="Weapons",
    ammunition="Ammo", tools="Tools", building="Materials",
    farming="Farming", clothing="Clothing", junk="Junk", other="Other",
    logs="Logs", fuel="Fuel",
}

-- Every reserve with a real supply executor can take a saved target; the
-- Stores page builds its rows from the same planner status the residents obey.
local STOCK_TARGET_STEPS = { 0, 1, 2, 3, 4, 5, 6, 8, 10, 12 }
local function residentDisplayName(residentId)
    local identity = KnoxPersistence.getSurvivorIdentity(residentId) or {}
    local name = (tostring(identity.forename or "") .. " "
        .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Resident " .. tostring(residentId) end
    return name
end
local function previousStockTarget(value)
    local current = tonumber(value) or 0
    local previous = 0
    for _, step in ipairs(STOCK_TARGET_STEPS) do
        if step >= current then break end
        previous = step
    end
    return previous
end
local function nextStockTarget(value)
    local current = tonumber(value) or 0
    for _, step in ipairs(STOCK_TARGET_STEPS) do
        if step > current then return step end
    end
    return 0
end

-- Duty-schedule strip: pick a tool, then click one of six four-hour blocks.
-- Sleep and leisure are no-work windows; work, patrol and guard all work
-- (patrol/guard bias election toward watch tasks). The backend window list
-- stays the sole persisted authority; the strip expands windows to hours for
-- display and compresses back on save (see KnoxPersistence).
local SCHEDULE_ASSIGNMENT_LABELS = {
    sleep = "Sleep", work = "Work", patrol = "Patrol", guard = "Guard Duty",
    recreation = "Leisure", anything = "Anything",
}
local SCHEDULE_TOOLS = {
    { key = "sleep", label = "Sleep" },
    { key = "work", label = "Work" },
    { key = "patrol", label = "Patrol" },
    { key = "guard", label = "Guard" },
    { key = "recreation", label = "Leisure" },
    { key = "anything", label = "Free" },
}
local SCHEDULE_COLORS = {
    sleep = { r = 0.22, g = 0.32, b = 0.78 },
    work = { r = 0.75, g = 0.50, b = 0.16 },
    patrol = { r = 0.95, g = 0.75, b = 0.25 },
    guard = { r = 0.85, g = 0.22, b = 0.22 },
    recreation = { r = 0.30, g = 0.70, b = 0.30 },
    anything = { r = 0.42, g = 0.42, b = 0.42 },
}
local SCHEDULE_BLOCK_LABELS = {
    sleep = "Sleep", work = "Work", patrol = "Patrol", guard = "Guard",
    recreation = "Leisure", anything = "Free",
}

-- One control per category already owned by the base task selector. Missing
-- entries display Normal; active companions never have these controls enabled.
local PRIORITY_COLUMNS = {
    { key = "guard", label = "Guard" },
    { key = "patrol", label = "Patrol" },
    { key = "cooking", label = "Cook" },
    { key = "farming", label = "Farm" },
    { key = "woodwork", label = "Wood" },
    { key = "barricade", label = "Build" },
    { key = "hauling", label = "Haul" },
    { key = "repair", label = "Repair" },
}
local PRIORITY_COLORS = {
    normal = { r = 0.42, g = 0.42, b = 0.42 },
    high = { r = 0.85, g = 0.30, b = 0.12 },
    low = { r = 0.78, g = 0.68, b = 0.22 },
    disabled = { r = 0.16, g = 0.16, b = 0.16 },
}
local PRIORITY_STATE_LABELS = { high = "H", normal = "N", low = "L", disabled = "D" }
-- The table draws one column per state, so the order is part of the shape.
local PRIORITY_STATES = { "high", "normal", "low", "disabled" }
local PRIORITY_STATE_TITLES = { high = "High", normal = "Normal", low = "Low", disabled = "Off" }
local PRIORITY_STATE_NEXT = { high = "low", low = "disabled", disabled = "normal", normal = "high" }

local function setPersistentButtonFill(button, color, alpha)
    if button == nil or color == nil then return end
    local fill = { r = color.r, g = color.g, b = color.b, a = alpha or 0.9 }
    button.background = true
    button.isBaseBackgroundVisible = true
    button.backgroundColor = fill
    button.backgroundColorMouseOver = {
        r = fill.r, g = fill.g, b = fill.b, a = fill.a,
    }
    -- ISButton:setEnable restores this cached value every time the view is
    -- refreshed. Keep it synchronized or the first/default color returns
    -- after a paint or preference change.
    button.backgroundColorEnabled = {
        r = fill.r, g = fill.g, b = fill.b, a = fill.a,
    }
end

local function currentScheduleHour()
    -- Read the same authoritative PZ clock used by autonomy. The older
    -- NightShelter helper falls back to noon when its optional global clock
    -- is absent, which made this marker stick at 12 even at 17:00.
    local gameTime
    if getGameTime ~= nil then
        local ok, value = pcall(getGameTime)
        if ok then gameTime = value end
    end
    if gameTime == nil then
        local gameTimeClass = rawget(_G, "GameTime")
        if gameTimeClass ~= nil and gameTimeClass.getInstance ~= nil then
            local ok, value = pcall(function() return gameTimeClass.getInstance() end)
            if ok then gameTime = value end
        end
    end
    if gameTime ~= nil and gameTime.getTimeOfDay ~= nil then
        local ok, hour = pcall(function() return gameTime:getTimeOfDay() end)
        hour = ok and tonumber(hour) or nil
        if hour ~= nil then return hour % 24 end
    end

    local shelter = rawget(_G, "KnoxNightShelter")
    if shelter ~= nil and shelter.currentHour ~= nil then
        local ok, hour = pcall(function() return shelter.currentHour() end)
        hour = ok and tonumber(hour) or nil
        if hour ~= nil then return hour % 24 end
    end
    return nil
end

local function responsiveControlColumns(availableWidth, count, minimumWidth, maximumColumns)
    local available = math.max(1, tonumber(availableWidth) or 1)
    local total = math.max(1, tonumber(count) or 1)
    local minimum = math.max(1, tonumber(minimumWidth) or 1)
    if available >= total * minimum + (total - 1) * 4 then return total end
    local maxColumns = math.max(1, tonumber(maximumColumns) or total)
    return math.max(1, math.min(maxColumns, math.floor((available + 4) / (minimum + 4))))
end

local function taskBlockerText(value)
    return KnoxBaseTaskBoard.blockerText(value)
end

local function taskRequirementsText(task)
    local items=task.requirements~=nil and task.requirements.items or nil
    if type(items)~="table" then return nil end
    local entries={}
    for fullType,count in pairs(items) do
        if tonumber(count)~=nil and tonumber(count)>0 then
            local label=tostring(fullType)
            if getScriptManager~=nil then
                local ok,name=pcall(function()
                    local item=getScriptManager():FindItem(fullType)
                    return item~=nil and item:getDisplayName() or nil
                end)
                if ok and name~=nil and tostring(name)~="" then label=tostring(name) end
            end
            entries[#entries+1]=tostring(count).." x "..label
        end
    end
    table.sort(entries)
    return #entries>0 and ("Job requires: "..table.concat(entries,", ")) or nil
end

local function claimantName(survivorId)
    if survivorId==nil then return nil end
    local identity=KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):gsub("^%s+",""):gsub("%s+$","")
    return name~="" and name or "Resident"
end

local function taskRowText(task, now)
    local taskKind=tostring(task.type or "task")
    local label=KnoxOrderCatalog.label(taskKind,taskKind)
    local state=tostring(task.state or "queued")
    local detail=state
    if state=="claimed" and task.claimedBy~=nil then
        detail="active: "..tostring(claimantName(task.claimedBy))
    elseif state=="blocked" then
        detail="blocked"
        local reason=taskBlockerText(task.result or task.lastResult)
        if task.result=="missing_required_materials_after_search"
            or (task.result==nil and task.lastResult=="missing_required_materials_after_search") then
            local requirements=taskRequirementsText(task)
            if requirements~=nil then detail=detail.." | "..requirements end
        end
        if reason~=nil then detail=detail..": "..reason end
        local retryAt=tonumber(task.retryAtHours)
        if retryAt~=nil and retryAt>(tonumber(now) or 0) then
            detail=detail..string.format(" (retry %.1fh)",retryAt-(tonumber(now) or 0))
        end
    elseif state=="queued" then
        detail="waiting"
    end
    return label.." - "..detail.." - priority "..tostring(task.priority or 0)
end

-- Selected-base plumbing for multi-base owners. Transient per window open
-- (defaults to the primary, oldest base); every base-scoped tab reads it
-- so residents, jobs and storage never mix across homes.
local function notebookBases(pid)
    if pid == nil or KnoxPersistence.getBasesForOwner == nil then return {} end
    return KnoxPersistence.getBasesForOwner("player", pid) or {}
end

local function notebookBaseId(window, playerNum, pid)
    local bases = notebookBases(pid)
    if #bases == 0 then return nil end
    if window ~= nil and window.knoxBaseId ~= nil then
        for _, base in ipairs(bases) do
            if base.id == window.knoxBaseId then return base.id end
        end
    end
    return bases[1].id
end

-- One resolution for both pages. Base & Work read the base object from the
-- owner's own list while Stores & Storage re-resolved the id through
-- KnoxPersistence.getBase; two lookups of one question is how a page can say
-- "no home base yet" beside another page's "Main Base". Both now ask this.
local function notebookBase(window, playerNum, pid)
    local bases = notebookBases(pid)
    if #bases == 0 then return nil end
    local wanted = window ~= nil and window.knoxBaseId or nil
    if wanted ~= nil then
        for _, base in ipairs(bases) do
            if base.id == wanted then return base end
        end
    end
    return bases[1]
end

local function refreshAllViews(window)
    if window == nil or window.panel == nil then return end
    for _, entry in ipairs(window.panel.viewList or {}) do
        local view = type(entry) == "table" and entry.view or nil
        if view ~= nil and view.populate ~= nil then
            pcall(function() view:populate(window.playerNum) end)
        end
    end
end

-- Base panel: home(s), areas, queue, storage. The old Work tab lives
-- here now; the base picker on top switches between multiple homes.
local BaseView = ISPanelJoypad:derive("KnoxNotebookBaseView")
function BaseView:initialise() ISPanelJoypad.initialise(self) end
function BaseView:createChildren()
    ISPanelJoypad.createChildren(self)
    self:createAttentionBand()
    local y=UI_BORDER_SPACING+ATTENTION_HEIGHT+8
    self.basePicker=ISComboBox:new(UI_BORDER_SPACING,y,220,BUTTON_HGT,self,nil); self.basePicker:initialise(); self:addChild(self.basePicker)
    self.renameBaseBtn=ISButton:new(self.basePicker:getRight()+6,y,88,BUTTON_HGT,"Rename",self,BaseView.onRenameBase)
    self.renameBaseBtn:initialise(); UILayout.tintSheetButton(self.renameBaseBtn); self:addChild(self.renameBaseBtn)
    y=y+BUTTON_HGT+4
    self.infoLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y=y+FONT_HGT_SMALL+4
    self.workforceLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true); self.workforceLabel:initialise(); self:addChild(self.workforceLabel)
    y=y+FONT_HGT_SMALL+2
    self.securityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true); self.securityLabel:initialise(); self:addChild(self.securityLabel)
    y=y+FONT_HGT_SMALL+4
    self.boundaryLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.6,0.6,0.8,1,UIFont.Small,true); self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y=y+FONT_HGT_SMALL+6
    self.showHighlights=ISTickBox:new(UI_BORDER_SPACING,y,170,BUTTON_HGT,"",self,BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption("Show Highlights"); self:addChild(self.showHighlights)
    self.editBoundaryBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Edit Boundary",self,BaseView.onEditBoundary); self.editBoundaryBtn:initialise(); UILayout.tintSheetButton(self.editBoundaryBtn); self:addChild(self.editBoundaryBtn)
    self.autoBoardBtn=ISButton:new(self.showHighlights:getRight()+6,y,130,BUTTON_HGT,"Board Up: Off",self,BaseView.onToggleAutoBoard); self.autoBoardBtn:initialise(); UILayout.tintSheetButton(self.autoBoardBtn); self.autoBoardBtn.tooltip="Automatically board windows using real planks and nails from base storage. Off by default because it spends supplies."; self:addChild(self.autoBoardBtn)
    y=y+BUTTON_HGT+6
    self.zoneHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Work areas",1,1,1,1,UIFont.Small,true); self.zoneHeading:initialise(); self:addChild(self.zoneHeading)
    y=y+FONT_HGT_SMALL+4
    self.zoneList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.Small; self.zoneList.doDrawItem=BaseView.drawZone; self.zoneList.drawBorder=true; UILayout.tintSheetBorder(self.zoneList); self:addChild(self.zoneList)
    y=self.zoneList:getBottom()+UI_BORDER_SPACING
    self.zonePicker=ISComboBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,self,nil); self.zonePicker:initialise()
    for _,d in ipairs(ZONE_TYPES) do self.zonePicker:addOption(d.label) end; self.zonePicker.selected=1; self:addChild(self.zonePicker)
    self.addAreaBtn=ISButton:new(self.zonePicker:getRight()+6,y,100,BUTTON_HGT,"Add Area",self,BaseView.onAddArea); self.addAreaBtn:initialise(); UILayout.tintSheetButton(self.addAreaBtn); self:addChild(self.addAreaBtn)
    self.removeBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Remove Selected",self,BaseView.onRemove); self.removeBtn:initialise(); UILayout.tintSheetButton(self.removeBtn); self:addChild(self.removeBtn)
    y=y+BUTTON_HGT+6
    self.taskHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Task Queue",1,1,1,1,UIFont.Small,true); self.taskHeading:initialise(); self:addChild(self.taskHeading)
    y=y+FONT_HGT_SMALL+4
    self.taskList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*4)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.Small; self.taskList.doDrawItem=BaseView.drawTask; self.taskList.drawBorder=true; UILayout.tintSheetBorder(self.taskList); self:addChild(self.taskList)
    y=self.taskList:getBottom()+6
    self.cancelTaskBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Cancel",self,BaseView.onCancelTask)
    self.cancelTaskBtn:initialise(); UILayout.tintSheetButton(self.cancelTaskBtn); self:addChild(self.cancelTaskBtn)
    self.resumeTaskBtn=ISButton:new(self.cancelTaskBtn:getRight()+6,y,110,BUTTON_HGT,"Resume",self,BaseView.onResumeTask)
    self.resumeTaskBtn:initialise(); UILayout.tintSheetButton(self.resumeTaskBtn); self:addChild(self.resumeTaskBtn)
    self.residentPicker=ISComboBox:new(self.resumeTaskBtn:getRight()+6,y,160,BUTTON_HGT,self,nil); self.residentPicker:initialise(); self:addChild(self.residentPicker)
    self.assignTaskBtn=ISButton:new(self.residentPicker:getRight()+6,y,96,BUTTON_HGT,"Assign",self,BaseView.onAssignTask)
    self.assignTaskBtn:initialise(); UILayout.tintSheetButton(self.assignTaskBtn); self:addChild(self.assignTaskBtn)
    y=y+BUTTON_HGT+6
    self.taskDetailsBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Details",self,BaseView.onTaskDetails)
    self.taskDetailsBtn:initialise(); self.taskDetailsBtn.tooltip="Full job status and requirements. Controller: X."; self:addChild(self.taskDetailsBtn)
    self.taskList.joypadParent=self
    self.taskList:setISButtonForX(self.taskDetailsBtn)
    y=y+BUTTON_HGT+6
    -- Hours and priorities moved to the Crew tab; the Base tab keeps
    -- boundary, areas, queue and storage.
    self.hintLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true); self.hintLabel:initialise(); self.hintLabel.name=""; self:addChild(self.hintLabel)
    -- The page lays out a reason line under this hint, so the label has to exist
    -- before the first layout runs: it did not, and opening the notebook raised
    -- "attempted index: setX of non-table: null" at layoutPage line 629.
    self.reasonLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",
        sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true)
    self.reasonLabel:initialise(); self:addChild(self.reasonLabel)
    -- The fixed arrangement is taller than short/split-screen viewports.
    -- Let the existing tab layout adapter scroll the whole page instead of
    -- placing storage and its hint beyond the visible tab bounds.
    -- The three fact lines become one count strip: the same numbers, laid out
    -- by the shared strip rule, so residents, areas, work and watch read as
    -- counts instead of three sentences competing for the same width. The old
    -- labels stay in the tree as the no-base fallback and are hidden once a
    -- strip exists.
    self.statY = self.infoLabel:getY() - 2
    self.statRowH = 34
    self.infoLabel:setVisible(false)
    self.workforceLabel:setVisible(false)
    self.securityLabel:setVisible(false)
    self.statCells = nil
    self:layoutPage()
end

-- The page geometry in one place. Columns come from the measured page width, so
-- a narrow sheet or a large interface font falls back to one column instead of
-- clipping the right side. Lists are sized to their rows: the page is the only
-- thing that scrolls.
function BaseView:layoutPage()
    local spacing = UI_BORDER_SPACING
    local available = math.max(1, self.width - spacing * 2)
    local y = spacing + ATTENTION_HEIGHT + 8
    self.basePicker:setX(spacing); self.basePicker:setY(y)
    local pickerW = math.min(220, math.max(120, available - 100))
    self.basePicker:setWidth(pickerW)
    self.renameBaseBtn:setX(math.max(spacing + 60, self.width - spacing - 88))
    self.renameBaseBtn:setY(y)
    y = y + BUTTON_HGT + 6
    local stripH = 34
    if self.statCells ~= nil then
        stripH = math.max(34, tonumber(self.statCells.height) or 34)
    end
    self.statY = y + math.max(0, math.floor((stripH
        - (self.statCells ~= nil and tonumber(self.statCells.height) or 17)) / 2))
    y = y + stripH + 6
    self.boundaryLabel:setX(spacing); self.boundaryLabel:setY(y)
    self.boundaryLabel:setWidth(available)
    y = y + FONT_HGT_SMALL + 6
    self.showHighlights:setX(spacing); self.showHighlights:setY(y)
    self.autoBoardBtn:setX(spacing + 176); self.autoBoardBtn:setY(y)
    self.editBoundaryBtn:setX(math.max(spacing, self.width - spacing - 118))
    self.editBoundaryBtn:setY(y)
    y = y + BUTTON_HGT + 10
    local columns = UILayout.columns(available, { gap = 12, minLeft = 300, minRight = 300 })
    local left, right = columns.cells[1], columns.cells[2]
    local zoneRows = math.max(3, #(self.zoneList.items or {}))
    local taskRows = math.max(3, #(self.taskList.items or {}))
    local zoneH = UILayout.stackHeight(zoneRows, BUTTON_HGT, 3, 8)
    local taskH = UILayout.stackHeight(taskRows, BUTTON_HGT, 3, 8)
    local stacked = columns.count ~= 2
    local zoneTop = y + FONT_HGT_SMALL + 4
    local taskTop = zoneTop
    self.zoneHeading:setX(spacing + left.x); self.zoneHeading:setY(y)
    self.zoneList:setX(spacing + left.x); self.zoneList:setWidth(left.width)
    self.zoneList:setY(zoneTop); self.zoneList:setHeight(zoneH)
    if stacked then
        taskTop = zoneTop + zoneH + FONT_HGT_SMALL + 12
    end
    self.taskHeading:setX(spacing + right.x)
    self.taskHeading:setY(not stacked and y or (taskTop - FONT_HGT_SMALL - 4))
    self.taskList:setX(spacing + right.x); self.taskList:setWidth(right.width)
    self.taskList:setY(taskTop); self.taskList:setHeight(taskH)
    local zoneBottom = zoneTop + zoneH + 6
    self.zonePicker:setX(spacing + left.x); self.zonePicker:setY(zoneBottom)
    self.zonePicker:setWidth(math.max(90, left.width - 112))
    self.addAreaBtn:setX(spacing + left.x + self.zonePicker:getWidth() + 6)
    self.addAreaBtn:setY(zoneBottom); self.addAreaBtn:setWidth(100)
    self.removeBtn:setX(spacing + left.x + left.width - 118)
    self.removeBtn:setY(zoneBottom + BUTTON_HGT + 4); self.removeBtn:setWidth(118)
    local zoneFoot = zoneBottom + BUTTON_HGT * 2 + 10
    local taskBottom = taskTop + taskH + 6
    local taskFooter = UILayout.footerPlacements(
        { self.taskDetailsBtn, self.cancelTaskBtn, self.resumeTaskBtn, self.assignTaskBtn },
        right.width, { spacing = 4, buttonHeight = BUTTON_HGT,
            measure = function(label)
                return getTextManager():MeasureStringX(UIFont.Small, label)
            end })
    for _, placement in ipairs(taskFooter.placements) do
        local control = placement.control
        control:setX(spacing + right.x + placement.x)
        control:setY(taskBottom + placement.y)
        control:setWidth(placement.width)
        control:setHeight(placement.height)
    end
    self.residentPicker:setX(spacing + right.x)
    self.residentPicker:setY(taskBottom + taskFooter.height + 6)
    self.residentPicker:setWidth(math.max(110, math.min(right.width - 4, 160)))
    self.assignTaskBtn:setX(spacing + right.x + self.residentPicker:getWidth() + 6)
    self.assignTaskBtn:setY(taskBottom + taskFooter.height + 6)
    local taskFoot = taskBottom + taskFooter.height + 6 + BUTTON_HGT + 10
    y = math.max(zoneFoot, taskFoot)
    if self.hintLabel.knoxFullText == nil then self.hintLabel.knoxFullText = self.hintLabel.name end
    y = layoutPageFeedback(self, self.hintLabel, "baseHintLines", self.hintLabel.knoxFullText,
        spacing, y, available) + 4
    y = layoutPageFeedback(self, self.reasonLabel, "baseReasonLines", self:actionReason(),
        spacing, y, available)
    self.knoxContentHeight = y + spacing
end

function BaseView:actionReason()
    if #(self.baseIds or {}) == 0 then
        return "No base yet: area, task and boundary actions need a home."
    end
    local off={}
    if self.removeBtn~=nil and self.removeBtn.enable~=true then off[#off+1]="Remove" end
    if self.cancelTaskBtn~=nil and self.cancelTaskBtn.enable~=true then off[#off+1]="Cancel" end
    if self.resumeTaskBtn~=nil and self.resumeTaskBtn.enable~=true then off[#off+1]="Resume" end
    if self.assignTaskBtn~=nil and self.assignTaskBtn.enable~=true then off[#off+1]="Assign" end
    if self.renameBaseBtn~=nil and self.renameBaseBtn.enable~=true then off[#off+1]="Rename" end
    if #off==0 then return "" end
    return "Select an area or a task to use "..table.concat(off,", ").."."
end
-- A small top strip, not a fifth screen. It reads only facts the tab already
-- gathered: the settlement summary, security coverage, role-kit scan and bed
-- roster. Each row scrolls the existing control to its real evidence.
function BaseView:createAttentionBand()
    local width = self.width - UI_BORDER_SPACING * 2
    local panel = ISPanel:new(UI_BORDER_SPACING, UI_BORDER_SPACING,
        width, ATTENTION_HEIGHT)
    panel:initialise()
    -- The attention strip is the same sheet, one shade quieter than the page.
    local theme = UILayout.sheetTheme()
    panel.backgroundColor = { r = theme.charcoal[1], g = theme.charcoal[2],
        b = theme.charcoal[3], a = 0.58 }
    panel.borderColor = { r = theme.border[1], g = theme.border[2],
        b = theme.border[3], a = 0.70 }
    self:addChild(panel)
    self.attentionPanel = panel

    self.attentionTitle = ISLabel:new(ATTENTION_PAD, ATTENTION_PAD,
        FONT_HGT_SMALL, "Home", 1, 1, 1, 1, UIFont.Small, true)
    self.attentionTitle:initialise()
    panel:addChild(self.attentionTitle)

    self.attentionSummary = ISLabel:new(ATTENTION_PAD, ATTENTION_PAD,
        FONT_HGT_SMALL, "", 0.68, 0.66, 0.62, 1, UIFont.Small, true)
    self.attentionSummary:initialise()
    panel:addChild(self.attentionSummary)

    self.attentionEmpty = ISLabel:new(ATTENTION_PAD,
        ATTENTION_PAD + FONT_HGT_SMALL + 6, FONT_HGT_SMALL, "",
        0.72, 0.72, 0.70, 1, UIFont.Small, true)
    self.attentionEmpty:initialise()
    panel:addChild(self.attentionEmpty)

    self.attentionRows = {}
    for index = 1, 3 do
        local y = ATTENTION_PAD + FONT_HGT_SMALL + 4
            + (index - 1) * ATTENTION_ROW_HEIGHT
        local label = ISLabel:new(ATTENTION_PAD, y, ATTENTION_ROW_HEIGHT,
            "", 1, 1, 1, 1, UIFont.Small, true)
        label:initialise()
        label:setVisible(false)
        panel:addChild(label)
        local button = ISButton:new(0, y - 2, ATTENTION_ACTION_WIDTH, BUTTON_HGT,
            "Review", self, BaseView.onAttentionAction)
        button:initialise()
        button.borderColor = { r = 0.72, g = 0.58, b = 0.28, a = 0.65 }
        button:setVisible(false)
        button.knoxAttentionIndex = index
        panel:addChild(button)
        self.attentionRows[index] = { label = label, button = button }
    end
    self.attentionItems = {}
    self.attentionSummaryText = ""
    self.attentionEmptyText = ""
    self:layoutAttentionBand()
end

function BaseView:layoutAttentionBand()
    local panel = self.attentionPanel
    if panel == nil then return end
    local width = panel:getWidth()
    local labelWidth = math.max(1, width - ATTENTION_PAD * 2
        - ATTENTION_ACTION_WIDTH - 8)
    local summaryLimit = math.max(1, width - ATTENTION_PAD * 3
        - getTextManager():MeasureStringX(UIFont.Small, "Home"))
    self.attentionSummary.name = trimText(UIFont.Small,
        self.attentionSummaryText or "", summaryLimit)
    local summaryWidth = getTextManager():MeasureStringX(
        UIFont.Small, self.attentionSummary.name)
    self.attentionSummary:setX(width - ATTENTION_PAD - summaryWidth)
    self.attentionSummary:setY(ATTENTION_PAD)
    self.attentionEmpty:setWidth(width - ATTENTION_PAD * 2)
    self.attentionEmpty.name = trimText(UIFont.Small,
        self.attentionEmptyText or "", width - ATTENTION_PAD * 2)
    for index, row in ipairs(self.attentionRows or {}) do
        local y = ATTENTION_PAD + FONT_HGT_SMALL + 4
            + (index - 1) * ATTENTION_ROW_HEIGHT
        row.label:setX(ATTENTION_PAD)
        row.label:setY(y)
        row.label:setWidth(labelWidth)
        row.label.name = trimText(UIFont.Small,
            row.label.knoxFullText or "", labelWidth)
        row.button:setX(width - ATTENTION_PAD - ATTENTION_ACTION_WIDTH)
        row.button:setY(y - 2)
    end
end

function BaseView:refreshAttention(base, facts)
    facts = type(facts) == "table" and facts or {}
    self.attentionItems = KnoxBaseManager.attentionItems ~= nil
        and KnoxBaseManager.attentionItems(facts) or {}
    local count = #self.attentionItems
    local residents = tonumber(facts.residents) or 0
    local zones = tonumber(facts.zones) or 0
    local security = type(facts.security) == "table" and facts.security or {}
    local posts = (tonumber(security.guardPosts) or 0)
        + (tonumber(security.patrolRoutes) or 0)
    local summary
    local empty
    if base == nil then
        summary = "No home"
        empty = "Right-click inside a building to establish one."
    elseif residents == 0 then
        summary = tostring(base.name or "Home") .. ", empty"
        empty = "No residents are staying here."
    elseif count == 0 then
        summary = tostring(base.name or "Home") .. ", all clear"
        empty = tostring(residents) .. (residents == 1 and " resident, " or " residents, ")
            .. tostring(zones) .. (zones == 1 and " work area, " or " work areas, ")
            .. tostring(posts) .. (posts == 1 and " security post" or " security posts")
    else
        summary = tostring(base.name or "Home") .. ", " .. tostring(count)
            .. (count == 1 and " thing needs you" or " things need you")
        empty = ""
    end
    self.attentionSummaryText = summary
    self.attentionEmptyText = empty
    for index, row in ipairs(self.attentionRows or {}) do
        local item = self.attentionItems[index]
        if item ~= nil then
            row.label.knoxFullText = item.title
            row.label:setVisible(true)
            row.button.title = item.actionLabel or "Review"
            row.button.tooltip = tostring(item.detail or "")
                .. " " .. tostring(item.title or "")
            row.button.knoxAttentionIndex = index
            row.button:setVisible(true)
        else
            row.label.knoxFullText = ""
            row.label:setVisible(false)
            row.button:setVisible(false)
        end
    end
    self:layoutAttentionBand()
end

function BaseView:revealAttentionList(list, predicate)
    if list == nil then return false end
    local selected = nil
    for index, row in ipairs(list.items or {}) do
        local matches = false
        if predicate ~= nil then
            local ok, result = pcall(predicate, row)
            matches = ok and result == true
        end
        if matches then selected = index; break end
    end
    if selected == nil and #(list.items or {}) > 0 then selected = 1 end
    if selected == nil then return false end
    list.selected = selected
    local itemHeight = tonumber(list.itemheight) or BUTTON_HGT
    local rowY = (selected - 1) * itemHeight
    local viewHeight = tonumber(list:getHeight()) or 0
    local scroll = tonumber(list:getYScroll()) or 0
    local top = -scroll
    if rowY < top then
        list:setYScroll(-rowY)
    elseif rowY + itemHeight > top + viewHeight then
        list:setYScroll(-(rowY + itemHeight - viewHeight))
    end
    UILayout.reveal(self, list, 12)
    return true
end

function BaseView:onAttentionAction(button)
    local index = tonumber(button ~= nil and button.knoxAttentionIndex or nil)
    local item = index ~= nil and self.attentionItems[index] or nil
    if item == nil then return end
    self:activateAttentionItem(item)
end

function BaseView:activateAttentionItem(item)
    if item == nil then return end
    if item.action == "review_world" then
        if self.knoxOpenWorld ~= nil then self.knoxOpenWorld() end
        return
    end
    if item.action == "add_guard" then
        for zoneIndex, definition in ipairs(ZONE_TYPES) do
            if definition.kind == "guard" then
                self.zonePicker.selected = zoneIndex
                break
            end
        end
        self:onAddArea()
        return
    end
    if item.action == "choose_area" then
        UILayout.reveal(self, self.zonePicker, 12)
        if setJoypadFocus ~= nil and self.playerNum ~= nil then
            pcall(setJoypadFocus, self.playerNum, self.zonePicker)
        end
        return
    end
    if item.action == "review_stock" then
        -- Targets are edited on their own page now, so the attention row goes
        -- there instead of hunting for a button that no longer exists.
        if self.knoxOpenStores ~= nil then self.knoxOpenStores() end
        return
    end
    local list, predicate
    if item.action == "review_tasks" then
        list = self.taskList
        predicate = function(row)
            local task = row ~= nil and row.item or nil
            return type(task) == "table" and task.state == "blocked"
        end
    elseif item.action == "review_storage" or item.action == "review_kits" then
        -- Containers and role kits are read where their rules are set.
        if self.knoxOpenStores ~= nil then self.knoxOpenStores() end
        return
    elseif item.action == "review_beds" then
        -- Beds are read beside the people who hold them.
        if self.knoxOpenCrew ~= nil then self.knoxOpenCrew() end
        return
    elseif item.action == "review_security" then
        list = self.zoneList
        predicate = function(row)
            local zone = row ~= nil and row.item or nil
            local kind = type(zone) == "table" and zone.type or nil
            return kind == "guard" or kind == "patrol"
        end
    end
    if list ~= nil then self:revealAttentionList(list, predicate) end
end

-- The world line can ask for the first attention item by key after the
-- notebook has populated. It does not open a second action path: it invokes
-- the same row action the band button uses.
function BaseView:focusAttentionKey(key)
    local wanted = tostring(key or "")
    if wanted == "" then return false end
    for _, item in ipairs(self.attentionItems or {}) do
        if tostring(item.key or "") == wanted then
            self:activateAttentionItem(item)
            return true
        end
    end
    return false
end

function BaseView:onMouseWheel(delta)
    -- Keep wheel input local to one bounded list.  The parent tab only moves
    -- when the pointer is outside Work Areas, Task Queue, and Storage.
    return UILayout.routeWheelToChildren(self, delta,
        { self.zoneList, self.taskList })
end
function BaseView:drawZone(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9
    local color=ZONE_COLORS[item.item and item.item.type] or ZONE_COLORS.general
    drawListRow(self,y,item,color)
    drawListText(self, y, item, a); return y+self.itemheight
end
function BaseView:drawTask(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; drawListRow(self,y,item); drawListText(self,y,item,a); return y+self.itemheight
end
function BaseView:drawStorage(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; drawListRow(self,y,item); drawListText(self,y,item,a); return y+self.itemheight
end
function BaseView:onAssignTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    local residentId=self.residentIds and self.residentIds[self.residentPicker.selected or 0] or nil
    if task == nil or task.id == nil or task.state ~= "queued" or residentId == nil then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local assigned,result
    local accepted=KnoxOrderCatalog.withFeedback("Assign job",function()
        assigned,result=KnoxCompanionService.assignBaseTask(player, residentId, base.id, task.id)
        -- Task assignment returns a task receipt, whereas shared feedback
        -- expects explicit acceptance. Preserve that distinction on success.
        return assigned ~= nil and result == "claimed",result
    end)
    if accepted and assigned ~= nil and result == "claimed" then
        KnoxActivityFeed.event("Assigned " .. KnoxOrderCatalog.label(task.type, "work") .. " to the selected resident.")
    end
    self:populate(self.playerNum)
end
function BaseView:onCancelTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil or task.state == "claimed" or task.state == "cancelled" then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local cancelled,result
    local accepted=KnoxOrderCatalog.withFeedback("Cancel job",function()
        cancelled,result=KnoxPersistence.cancelBaseTask(base.id,task.id,now)
        return cancelled ~= nil and result == "cancelled",result
    end)
    if accepted and cancelled ~= nil and result == "cancelled" then
        KnoxActivityFeed.event("Base task cancelled: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
    end
    self:populate(self.playerNum)
end
function BaseView:onResumeTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil
        or (task.state ~= "cancelled" and task.state ~= "blocked") then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local resumed,result
    local accepted=KnoxOrderCatalog.withFeedback("Resume job",function()
        resumed,result=KnoxPersistence.resumeBaseTask(base.id,task.id,now)
        return resumed ~= nil and result == "resumed",result
    end)
    if accepted and resumed ~= nil and result == "resumed" then
        KnoxActivityFeed.event("Base task resumed: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
    end
    self:populate(self.playerNum)
end
function BaseView:onTaskDetails()
    local entry=self.taskList.items[self.taskList.selected or 0]
    local selected=entry~=nil and entry.item or nil
    if type(selected)~="table" or selected.id==nil then return end
    local win=self:getWindow()
    local playerNum=win~=nil and win.playerNum or self.playerNum
    local player=playerNum~=nil and getSpecificPlayer(playerNum) or nil
    local playerId=player~=nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base=playerId~=nil and self:selectedBase(playerNum,playerId) or nil
    local task=base~=nil and base.tasks~=nil and base.tasks[selected.id] or nil
    if task==nil then return end
    local now=getGameTime():getWorldAgeHours()
    local text=taskRowText(task,now)
    local requirements=taskRequirementsText(task)
    if requirements~=nil and not text:find(requirements,1,true) then
        text=text.."\n\n"..requirements
    end
    -- Names and unknown reasons are plain data, never rich-text commands.
    text=text:gsub("<","["):gsub(">","]"):gsub("\n"," <LINE> ")
    local width=math.max(120,math.min(560,getCore():getScreenWidth()-40))
    local height=math.max(100,math.min(320,getCore():getScreenHeight()-40))
    local modal=ISModalRichText:new(20,20,width,height,text,false,nil,nil,playerNum)
    modal.prevFocus=self
    modal.onJoypadDirUp=function(dialog) dialog.chatText:onMouseWheel(-3) end
    modal.onJoypadDirDown=function(dialog) dialog.chatText:onMouseWheel(3) end
    modal.onJoypadDown=function(dialog,button)
        if button==Joypad.BButton then dialog:destroy()
        else ISModalRichText.onJoypadDown(dialog,button) end
    end
    modal.onKeyRelease=function(dialog,key)
        if key==Keyboard.KEY_ESCAPE then dialog:destroy();return true end
        return false
    end
    modal.isKeyConsumed=function(_,key) return key==Keyboard.KEY_ESCAPE end
    modal:setWantKeyEvents(true)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true)
    if self.joyfocus~=nil then setJoypadFocus(playerNum,modal) end
end

function BaseView:onJoypadDown(button,joypadData)
    if button==Joypad.XButton then self:onTaskDetails();return end
    ISPanelJoypad.onJoypadDown(self,button,joypadData)
end

function BaseView:selectedBase(playerNum, pid)
    return notebookBase(self:getWindow(), playerNum, pid)
end

function BaseView:onToggleAutoBoard()
    local playerNum = self.playerNum or 0
    local player = getSpecificPlayer(playerNum)
    local pid = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = self:selectedBase(playerNum, pid)
    if base == nil or pid == nil then
        KnoxActivityFeed.event("No home base to change.")
        return
    end
    local enabled = not (base.settings ~= nil and base.settings.autoBarricade == true)
    local ok, reason = KnoxPersistence.setBaseAutoBarricade(base.id, pid, enabled)
    if not ok then
        KnoxActivityFeed.event("Could not change boarding: " .. tostring(reason) .. ".")
        return
    end
    KnoxActivityFeed.event(enabled
        and "Automatic boarding on - residents will use planks and nails."
        or "Automatic boarding off - order barricades from the base menu.")
    self:populate(playerNum)
end

function BaseView:onRenameBase()
    local win = self:getWindow()
    local playerNum = win ~= nil and win.playerNum or self.playerNum
    local player = playerNum ~= nil and getSpecificPlayer(playerNum) or nil
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and self:selectedBase(playerNum, playerId) or nil
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
        KnoxActivityFeed.event("Select one of your bases before renaming it.")
        return
    end

    local prompt = "Rename " .. tostring(base.name or "base") .. " (32 characters maximum):"
    local modal = ISTextBox:new(0, 0, 360, 180, prompt, tostring(base.name or ""),
        self, BaseView.onRenameBaseConfirm, playerNum)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
    modal.knoxBaseId = base.id
    modal.knoxPlayerId = playerId
    modal.knoxPlayerNum = playerNum
    if modal.centerOnScreen ~= nil then modal:centerOnScreen(playerNum) end
end

function BaseView:onRenameBaseConfirm(button)
    if button == nil or button.internal ~= "OK" then return end
    local modal = button.parent
    if modal == nil or modal.knoxBaseId == nil or modal.knoxPlayerId == nil
        or modal.entry == nil or modal.entry.getText == nil then
        KnoxActivityFeed.event("Could not rename base: the name entry was unavailable.")
        return
    end

    local base, result = KnoxPersistence.renamePlayerBase(
        modal.knoxBaseId, modal.knoxPlayerId, modal.entry:getText())
    if base == nil then
        local messages = {
            invalid_base = "that base no longer exists",
            not_player_owned = "that base is not player-owned",
            invalid_owner_or_base = "the selected base is invalid",
            blank_name = "enter a name first",
            invalid_name = "the name contains unsupported control characters",
            invalid_name_encoding = "the name contains invalid text encoding",
            name_too_long = "names can contain at most 32 characters",
            duplicate_name = "another owned base already uses that name",
        }
        KnoxActivityFeed.event("Could not rename base: " .. tostring(messages[result] or result) .. ".")
        return
    end

    local win = self:getWindow()
    if win ~= nil then
        -- Keep selected identity stable while every Notebook view rereads the
        -- updated canonical base.name value.
        win.knoxBaseId = base.id
        refreshAllViews(win)
    end
    if result == "unchanged" then
        KnoxActivityFeed.event("Base name is unchanged: " .. tostring(base.name) .. ".")
    else
        KnoxActivityFeed.event("Base renamed to " .. tostring(base.name) .. ".")
    end
end

function BaseView:populate(playerNum)
    self.playerNum=playerNum
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil
    local bases = notebookBases(pid)
    self.baseIds = {}
    self.basePicker:clear()
    for _, b in ipairs(bases) do
        self.baseIds[#self.baseIds + 1] = b.id
        self.basePicker:addOption(tostring(b.name or b.id))
    end
    local base = #bases > 0 and self:selectedBase(playerNum, pid) or nil
    if base ~= nil then
        for index, id in ipairs(self.baseIds) do
            if id == base.id then self.basePicker.selected = index; break end
        end
    end
    self.basePicker:setVisible(#bases > 1)
    self.renameBaseBtn:setEnable(base ~= nil and base.ownerKind == "player" and base.ownerId == pid)
    self.taskList:clear()
    self.residentIds = {}
    self.residentPicker:clear(); self.residentPicker.selected = 1
    if not base then
        self.infoLabel.name=trimText(UIFont.Small,
            "No home base - right-click inside a building to establish one.", self.width-UI_BORDER_SPACING*2)
        self.workforceLabel.name=""; self.securityLabel.name=""; self.boundaryLabel.name=""
        self.zoneList:clear(); addRow(self.zoneList,"none","No base established"); self.showHighlights:setSelected(1,false)
        -- ISTickBox exposes `enable` directly in Build 42; setEnable belongs
        -- to ISButton only.
        self.showHighlights.enable=false; self.editBoundaryBtn:setEnable(false); self.addAreaBtn:setEnable(false); self.removeBtn:setEnable(false)
        self.renameBaseBtn:setEnable(false)
        self.autoBoardBtn:setEnable(false); self.autoBoardBtn:setTitle("Board Up: Off")
        self.residentPicker:addOption("No residents")
        addRow(self.taskList,"none","No base")
        self.taskHeading.name="No base"
        self.statCells = nil
        self.infoLabel.name=""
        self:refreshAttention(nil, {})
        self:layoutPage()
        return
    end
    local boarding = base.settings ~= nil and base.settings.autoBarricade == true
    if self.autoBoardBtn ~= nil then
        self.autoBoardBtn:setTitle("Board Up: " .. (boarding and "On" or "Off"))
        self.autoBoardBtn:setEnable(base.ownerKind == "player")
    end
    local residents=KnoxPersistence.getBaseResidentIds(base.id)
    local zones=0
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false then
            zones=zones+1
        end
    end
    local queued,claimed,blockedTasks=0,0,0
    for _,t in pairs(base.tasks or {}) do
        if t.state=="queued" then queued=queued+1
        elseif t.state=="blocked" then blockedTasks=blockedTasks+1
        elseif t.state=="claimed" then
            claimed=claimed+1
        end
    end
    local security = KnoxBaseJobs ~= nil and KnoxBaseJobs.securityCoverage ~= nil
        and KnoxBaseJobs.securityCoverage(base)
        or { guardPosts=0, patrolRoutes=0, activeGuard=0, activePatrol=0,
            staffed=0, available=0, required=0, understaffed=0 }
    local workforce = KnoxBaseJobs ~= nil and KnoxBaseJobs.workforceSummary ~= nil
        and KnoxBaseJobs.workforceSummary(base)
        or { residents=#residents, working=claimed, resting=0, idle=0 }
    self.knoxZoneCount = zones
    self.knoxResidentCount = tonumber(workforce.residents) or #residents
    self.knoxSecurity = security
    self.knoxWorkforce = workforce
    -- One fact per line: the old combined line clipped guard and patrol
    -- counts off the readable width.
    local intent = KnoxPersistence.getBaseIntent ~= nil
        and KnoxPersistence.getBaseIntent(base.id) or nil
    local intentUi = rawget(_G, "KnoxBaseContextMenu")
    local intentLabels = intentUi ~= nil and intentUi.BASE_INTENT_LABELS or nil
    local orderLabel = intent ~= nil
        and ((intentLabels ~= nil and intentLabels[intent]) or intent)
        or "Not set"

    -- Kind is identity, so it is read from persistence rather than from
    -- the weekly intent the base is currently working on.
    local kind = KnoxPersistence.getBaseKind ~= nil
        and KnoxPersistence.getBaseKind(base.id) or nil
    local kindLabels = intentUi ~= nil and intentUi.BASE_KIND_LABELS or nil
    local kindLabel = kind ~= nil
        and ((kindLabels ~= nil and kindLabels[kind]) or kind) or "Outpost"
    -- Counts lead and the words after each number are its unit, so the page can
    -- be read as four facts instead of a form dump. The field labels the old
    -- line carried (Kind:/Order:/Residents:/Tasks:) are gone; identity and the
    -- base's standing order moved to the line below, where coordinates already
    -- lived.
    local guardPosts, patrolRoutes = tonumber(security.guardPosts) or 0, tonumber(security.patrolRoutes) or 0
    local watchPosts = guardPosts + patrolRoutes
    local working = tonumber(workforce.working) or claimed
    -- Five counts, one strip: who lives here, where they can work, what is
    -- waiting, what is running and who is on watch. A page can hold all five in
    -- one glance where three wrapped sentences could not.
    self.statCells = UILayout.statStripCells({
        UILayout.valueRow(#residents, #residents == 1 and "resident" or "residents"),
        UILayout.valueRow(zones, zones == 1 and "work area" or "work areas"),
        UILayout.valueRow(queued, queued == 1 and "task waiting" or "tasks waiting"),
        UILayout.valueRow(working, "active"),
        UILayout.valueRow(blockedTasks, blockedTasks == 1 and "task blocked" or "tasks blocked",
            { tone = blockedTasks > 0 and "red" or "muted" }),
        UILayout.valueRow(watchPosts,
            watchPosts == 1 and "watch post" or "watch posts",
            { tone = watchPosts == 0 and "red" or "bone" }),
    }, math.max(1, self.width - UI_BORDER_SPACING * 2),
        { gap = 10, minCell = 130, rowH = self.statRowH,
            measure = function(text) return getTextManager():MeasureStringX(UIFont.Small, text) end })
    -- The strip is the read-out; the three labels would repeat it line for line.
    self.infoLabel.name = ""
    self.workforceLabel.name = ""
    self.securityLabel.name = ""
    local area=base.territory or base.home or {}
    -- Identity and the current standing order are one quiet line under the
    -- counts: they change rarely, so they do not compete with the numbers.
    self.boundaryLabel.name=trimText(UIFont.Small,
        tostring(kindLabel) .. ", " .. tostring(orderLabel) .. ", boundary "
            .. tostring(area.minX or "-") .. "," .. tostring(area.minY or "-")
            .. " to " .. tostring(area.maxX or "-") .. "," .. tostring(area.maxY or "-"),
        self.width-UI_BORDER_SPACING*2)
    self.showHighlights:setSelected(1, KnoxBaseHighlights.isEnabled(playerNum))
    self.showHighlights.enable=true; self.editBoundaryBtn:setEnable(true); self.addAreaBtn:setEnable(true); self.removeBtn:setEnable(self.zoneList.selected and self.zoneList.selected > 0)
    self.zoneList:clear()
    local list={}; for _,z in pairs(base.zones or {}) do if z and z.enabled~=false then list[#list+1]=z end end
    table.sort(list, function(a,b) if tostring(a.type)==tostring(b.type) then return tostring(a.label or a.type) < tostring(b.label or b.type) end return tostring(a.type) < tostring(b.type) end)
    if #list==0 then addRow(self.zoneList,"none","No work areas - pick a type and Add Area, then drag rectangle") else
        for _,z in ipairs(list) do local w,h,total=zoneSize(z); local sz=w and ("  " .. w .. " by " .. h .. ", " .. total .. " tiles at " .. z.x1 .. "," .. z.y1) or ""; addRow(self.zoneList,z.id, "  " .. tostring(KnoxPersistence.zoneDisplayLabel(z, z.type)) .. " [" .. tostring(z.type) .. "]" .. sz); self.zoneList.items[#self.zoneList.items].item={type=z.type, id=z.id} end
    end
    self:populateWork(base)
    self:layoutPage()
end

-- Task queue + storage for the selected base (merged old Work tab).
-- Storage presentation is separate from target cards; both consume the existing owners.
local function populateStorageSection(self, base, settlement)
    self.storageList:clear()
    local summary=settlement~=nil and settlement.storage or KnoxBaseStorage.summarize(base)
    local shortageCount=settlement~=nil and #(settlement.shortages or {}) or 0
    local stockState=settlement~=nil and settlement.stockKnown
        and (shortageCount>0 and (tostring(shortageCount).." shortage(s)") or "reserves covered")
        or "stock unavailable"
    local tapsDry=settlement~=nil and settlement.waterSource=="dry"
    local filteredContainers = KnoxBaseStorage.policies(base) or {}
    local usableContainers = KnoxBaseStorage.operationalPolicies ~= nil
        and KnoxBaseStorage.operationalPolicies(base) or filteredContainers
    local unshelved = settlement ~= nil and settlement.storageProblems or nil
    local unshelvedCount = type(unshelved) == "table" and #unshelved or 0
    local misfiledCount = tonumber(summary ~= nil and summary.misplacedItems) or 0
    self.storageLabel.knoxFullText=
        "Storage: " .. tostring(#filteredContainers) .. " filtered | "
        .. tostring(#usableContainers) .. " usable containers | " .. stockState
        .. (tapsDry and " | taps dry" or "")
        .. (unshelvedCount > 0 and (" | " .. tostring(unshelvedCount) .. " unshelved") or "")
        .. (misfiledCount > 0 and (" | " .. tostring(misfiledCount) .. " misfiled") or "")
    local any=false
    local assigned = KnoxBaseStorage.policies(base)
    if #assigned == 0 then addRow(self.storageList,"setup","Right-click any container inside this base to set item filters") end
    for _, policy in ipairs(assigned) do
        local resolved = KnoxBaseStorage.resolvePolicy(policy)
        -- The row is composed by the storage owner so the room, priority and
        -- coordinates cannot drift between this list and any other reader.
        local text = KnoxBaseStorage.policyRowText(policy, resolved ~= nil)
        addRow(self.storageList,policy.key,text)
    end
    -- Category stock is stated by the target cards above and the yard has its
    -- own row, so this list stays the containers themselves.
    addRow(self.storageList,"food-help","Residents route real items using each container's filters")
    if summary.unavailablePolicies>0 then addRow(self.storageList,"warn", tostring(summary.unavailablePolicies) .. " container(s) outside loaded area") end
    -- A haul that reached base but could not be shelved, with the real cause, so
    -- the leader sees it without having caught the feed line at the time.
    for _, problem in ipairs(type(unshelved) == "table" and unshelved or {}) do
        local identity=KnoxPersistence.getSurvivorIdentity(problem.survivorId) or {}
        local who=(tostring(identity.forename or "") .. " " .. tostring(identity.surname or ""))
            :gsub("^%s+", ""):gsub("%s+$", "")
        if who == "" then who = "A resident" end
        addRow(self.storageList, "unshelved:" .. tostring(problem.survivorId),
            who .. " can't shelve " .. tostring(problem.itemLabel or "the supplies") .. " - "
            .. KnoxBaseStorage.depositProblemLabel(problem.reason))
    end
    -- Supplies filed outside their category are not a problem: the matching
    -- shelf was full. The count is where the player sees the workaround.
    if misfiledCount > 0 then
        addRow(self.storageList, "misfiled", tostring(misfiledCount)
            .. " item(s) sit where their filters don't name them - a full shelf put them there")
    end
end

local function bedSummary(base)
    local rows = base ~= nil and KnoxBaseManager.bedRoster ~= nil
        and KnoxBaseManager.bedRoster(base, base.ownerId) or {}
    local assigned = 0
    for _, row in ipairs(rows) do if row.bed ~= nil then assigned = assigned + 1 end end
    return rows, assigned
end

local function kitCounts(entries)
    local shortage, unknown = 0, 0
    for _, entry in ipairs(entries or {}) do
        if entry.status == "shortage" then shortage = shortage + 1
        elseif entry.status == "unknown" then unknown = unknown + 1 end
    end
    return shortage, unknown
end

local function populateBedSection(view, base)
    view.bedsList:clear()
    local rows, assigned = bedSummary(base)
    for _, row in ipairs(rows) do
        local bed, text = row.bed, nil
        if bed ~= nil then
            local room = row.room ~= nil and row.room ~= "" and (" in " .. tostring(row.room)) or ""
            text = row.name .. " - bed at " .. tostring(bed.x) .. "," .. tostring(bed.y)
                .. ", floor " .. tostring(bed.z) .. room
        else text = row.name .. " - no bed assigned" end
        addRow(view.bedsList, "bed:" .. tostring(row.id), text)
    end
    if #rows == 0 then addRow(view.bedsList, "none", base == nil and "No home base yet." or "No residents to assign.") end
    view.bedsLabel.knoxFullText = "Beds: " .. tostring(assigned) .. " assigned | " .. tostring(#rows - assigned) .. " without"
end

local function kitRosterForBase(base)
    local roster = {}
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        local duty = KnoxPersistence.getSurvivorDuty ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
        local character = KnoxSurvivorRuntime ~= nil and KnoxSurvivorRuntime.getCharacter ~= nil
            and KnoxSurvivorRuntime.getCharacter(id) or nil
        roster[#roster + 1] = { id = id, preference = duty ~= nil and duty.jobPreference or nil, character = character }
    end
    return roster
end

local function populateKitSection(view, base)
    view.kitShortageList:clear()
    if base == nil then
        view.kitShortageLabel.knoxFullText = "Role kit shortages"
        addRow(view.kitShortageList, "none", "No home base yet.")
        return
    end
    local entries = KnoxBaseStorage.roleKitShortages ~= nil
        and KnoxBaseStorage.roleKitShortages(base, kitRosterForBase(base)) or {}
    table.sort(entries, function(first, second)
        local a, b = first.status == "shortage" and 1 or 2, second.status == "shortage" and 1 or 2
        if a ~= b then return a < b end
        return tostring(first.id) < tostring(second.id)
    end)
    local shortage, unknown = kitCounts(entries)
    for _, entry in ipairs(entries) do
        if entry.status == "shortage" or entry.status == "unknown" then
            local role = entry.role ~= nil and KnoxOrderCatalog.baseRoles and KnoxOrderCatalog.baseRoles[entry.role] or nil
            local roleLabel = role ~= nil and role.label or tostring(entry.role or "Resident")
            local name = residentDisplayName(entry.id)
            local text = entry.status == "unknown" and (name .. " (" .. roleLabel .. "): out of contact - readiness unknown.")
                or (name .. ": " .. (KnoxOrderCatalog.roleKitStatusText ~= nil
                    and KnoxOrderCatalog.roleKitStatusText(entry.role, entry.gear, entry.missing, entry.stock)
                    or "Kit: readiness unavailable."))
            addRow(view.kitShortageList, "kit:" .. tostring(entry.id), text)
        end
    end
    if shortage + unknown == 0 then addRow(view.kitShortageList, "none", "No assigned role-kit shortages.") end
    view.kitShortageLabel.knoxFullText = "Role kit shortages: " .. tostring(shortage)
        .. (unknown > 0 and (" | unknown: " .. tostring(unknown)) or "")
end


function BaseView:populateWork(base)
    local kitRoster={}
    for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        local name=residentDisplayName(residentId)
        self.residentIds[#self.residentIds+1]=residentId
        self.residentPicker:addOption(name)
        local duty=KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(residentId) or nil
        local character=KnoxSurvivorRuntime ~= nil
            and KnoxSurvivorRuntime.getCharacter ~= nil
            and KnoxSurvivorRuntime.getCharacter(residentId) or nil
        kitRoster[#kitRoster+1]={ id=residentId,
            preference=duty ~= nil and duty.jobPreference or nil,
            character=character }
    end
    if #self.residentIds == 0 then self.residentPicker:addOption("No residents") end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local settlement = KnoxBaseJobs ~= nil and KnoxBaseJobs.settlementSummary ~= nil
        and KnoxBaseJobs.settlementSummary(base, now) or nil
    local tasksSummary=settlement~=nil and settlement.tasks or {queued=0,claimed=0,blocked=0}
    local firstShortage=nil
    for _,reserve in ipairs(settlement~=nil and settlement.reserves or {}) do
        local missing=tonumber(reserve.missing) or 0
        if missing>0 and (firstShortage==nil or missing>firstShortage.missing) then
            firstShortage={ category=reserve.category,
                label=RESOURCE_LABELS[reserve.category] or reserve.category,
                missing=missing }
        end
    end
    -- The count strip already carries waiting, active and blocked. A heading
    -- that repeats them spends the row twice.
    self.taskHeading.name="Tasks"
    local tasks={}; for _,t in pairs(base.tasks or {}) do tasks[#tasks+1]=t end
    table.sort(tasks, function(a,b) local ap=tonumber(a.priority) or 0; local bp=tonumber(b.priority) or 0; if ap==bp then return tostring(a.id) < tostring(b.id) end return ap>bp end)
    if #tasks==0 then addRow(self.taskList,"none","No work waiting - mark work areas") else for _,t in ipairs(tasks) do
        addRow(self.taskList,t.id, taskRowText(t, now))
        self.taskList.items[#self.taskList.items].item=t
    end end
    local filteredContainers = KnoxBaseStorage.policies(base) or {}
    local unshelved = settlement ~= nil and settlement.storageProblems or nil
    local unshelvedCount = type(unshelved) == "table" and #unshelved or 0
    local bedRows, bedAssigned = bedSummary(base)
    local kitEntries = KnoxBaseStorage.roleKitShortages ~= nil
        and KnoxBaseStorage.roleKitShortages(base, kitRoster) or {}
    local kitShown, kitUnknown = kitCounts(kitEntries)
    self:refreshAttention(base, {
        residents=self.knoxResidentCount or #self.residentIds,
        zones=self.knoxZoneCount or 0,
        tasks=tasksSummary,
        security=self.knoxSecurity,
        unshelved=unshelvedCount,
        storageAssigned=#filteredContainers,
        bedsWithout=#bedRows-bedAssigned,
        kitShort=kitShown,
        kitUnknown=kitUnknown,
        stockKnown=settlement~=nil and settlement.stockKnown==true,
        shortage=firstShortage,
    })
end

function BaseView:getWindow() return self:getParent():getParent() end
function BaseView:onToggleHighlights(_, selected) KnoxBaseHighlights.setEnabled(self:getWindow().playerNum or self.playerNum or 0, selected == true) end
function BaseView:onEditBoundary()
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and self:selectedBase(win.playerNum, pid) or nil
    if base and pl and KnoxBaseTerritorySelector and KnoxBaseTerritorySelector.start(pl, base.id) then win:setVisible(false) end
end
function BaseView:onAddArea()
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and self:selectedBase(win.playerNum, pid) or nil; local def=ZONE_TYPES[self.zonePicker.selected or 1]
    if base and pl and def and KnoxBaseZoneSelector and KnoxBaseZoneSelector.start(pl, base.id, def.kind, def.label) then win:setVisible(false) end
end
function BaseView:onRemove()
    local index=self.zoneList.selected or 0; local it=index>0 and self.zoneList.items[index] or nil
    if not it or not it.item or not it.item.id then return end
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and self:selectedBase(win.playerNum, pid) or nil
    if base then local removed=KnoxPersistence.removeBaseZone(base.id, it.item.id); if removed then KnoxBaseHighlights.refresh(win.playerNum); KnoxActivityFeed.event("Work area removed."); self:populate(win.playerNum) end end
end
function BaseView:prerender()
    ISPanelJoypad.prerender(self)
    -- Combos are polled here. Commit a validated owned base ID before the
    -- shared views repopulate, so all base-scoped controls follow the picker.
    local win = self:getWindow()
    if win ~= nil and self.baseIds ~= nil and #self.baseIds > 1 then
        local id = self.baseIds[self.basePicker.selected or 0]
        if id ~= nil and win.knoxBaseId ~= id then
            win.knoxBaseId = id
            refreshAllViews(win)
            return
        end
    end
    if self.removeBtn and self.zoneList then
        local item=self.zoneList.selected and self.zoneList.items[self.zoneList.selected] or nil
        self.removeBtn:setEnable(item ~= nil and item.item ~= nil and item.item.id ~= nil)
    end
    if self.attentionPanel ~= nil then
        local targetWidth=math.max(1,self.width-UI_BORDER_SPACING*2)
        if math.abs(self.attentionPanel:getWidth()-targetWidth)>0.5 then
            self.attentionPanel:setWidth(targetWidth)
            self:layoutAttentionBand()
        end
    end
end
-- Base & Work owns the page's only count strip. It draws nothing until a base
-- exists, so the no-base state stays the attention band's one sentence.
function BaseView:render()
    ISPanelJoypad.render(self)
    if self.statCells ~= nil then
        UILayout.drawStatStrip(self, self.statCells, UI_BORDER_SPACING, self.statY)
    end
end

function BaseView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Crew panel: party and residents. The roster is split in two so a
-- survivor sent home visibly changes sections: party travels with you,
-- residents live at the selected base. The selected entry from either
-- list gets a priority row, a 24-hour schedule strip, role and party
-- controls below. Priorities and hours save immediately; job roles still
-- apply where automatic.
-- TWO DRAWING PANELS, NOT A SECOND FRAMEWORK
-- The work-preference table and the day timeline are painted surfaces with a
-- hit test that delegates to CrewView. They own no state, persist nothing and
-- decide nothing; every mutation still goes through the view's existing
-- handlers. Geometry comes from KS_SurvivorUILayout, so both panels measure
-- themselves exactly the way the page does.
local KnoxPrefTable = ISPanel:derive("KnoxPrefTable")
local PREF_HEADER_H = math.max(14, FONT_HGT_SMALL + 2)
local PREF_ROW_H = math.max(18, FONT_HGT_SMALL + 4)
function KnoxPrefTable:initialise() ISPanel.initialise(self) end
function KnoxPrefTable:setRows(rows)
    self.rows = type(rows) == "table" and rows or {}
    self.grid = UILayout.tableCells(#self.rows, #PRIORITY_STATES,
        math.max(1, self.width - 2), { gutter = 78, gap = 4, rowHeight = PREF_ROW_H })
end
function KnoxPrefTable:render()
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local theme = UILayout.sheetTheme()
    local grid = self.grid
    if grid ~= nil and self.enabled ~= true then
        self:drawText(UILayout.fitText(UIFont.Small,
                "Select a resident to change work.", math.max(1, self.width - 4),
                function(value) return manager:MeasureStringX(UIFont.Small, value) end),
            1, 1, theme.dim[1], theme.dim[2], theme.dim[3], 1, UIFont.Small)
    elseif grid ~= nil then
        for column, state in ipairs(PRIORITY_STATES) do
            local cell = grid.cells[column]
            if cell ~= nil then
                local title = PRIORITY_STATE_TITLES[state] or state
                local width = manager:MeasureStringX(UIFont.Small, title)
                self:drawText(title, 1 + cell.x + math.max(0, math.floor((cell.width - width) / 2)),
                    1, theme.dim[1], theme.dim[2], theme.dim[3], 1, UIFont.Small)
            end
        end
    end
    local gutter = grid ~= nil and grid.gutter or 78
    local rowHeight = grid ~= nil and grid.rowHeight or PREF_ROW_H
    for _, row in ipairs(self.rows or {}) do
        local tone = self.enabled == true and theme.bone or theme.dim
        local label = UILayout.fitText(UIFont.Small, row.label or "", math.max(1, gutter - 4),
            function(value) return manager:MeasureStringX(UIFont.Small, value) end)
        self:drawText(label, 1, 1 + PREF_HEADER_H + (row.index - 1) * rowHeight
                + math.max(0, math.floor((rowHeight - fontH) / 2)),
            tone[1], tone[2], tone[3], 1, UIFont.Small)
    end
    for _, cell in ipairs(grid ~= nil and grid.cells or {}) do
        local row = self.rows and self.rows[cell.row] or nil
        if row ~= nil then
            local x = 1 + cell.x
            local y = 1 + PREF_HEADER_H + cell.y
            if row.state == PRIORITY_STATES[cell.column] then
                local colour = PRIORITY_COLORS[row.state] or PRIORITY_COLORS.normal
                self:drawRect(x, y, cell.width, cell.height - 2, 0.92,
                    colour.r, colour.g, colour.b)
            else
                self:drawRectBorder(x, y, cell.width, cell.height - 2, 0.75,
                    theme.border[1], theme.border[2], theme.border[3])
            end
        end
    end
end
function KnoxPrefTable:onMouseDown(x, y)
    if self.owner == nil or self.grid == nil or self.enabled ~= true then return false end
    local cell = UILayout.tableCellAt(self.grid, x - 1, y - 1 - PREF_HEADER_H)
    if cell == nil then return false end
    local row = self.rows[cell.row]
    local state = PRIORITY_STATES[cell.column]
    if row == nil or state == nil then return false end
    self.owner:applyCrewPriority(row.key, state)
    return true
end

-- Preserve every character even when one time token is wider than a cell.
local function timelineTextLines(text, width, measure)
    return UILayout.wrapLines(tostring(text or ""), math.max(1, width), measure)
end

local KnoxTimeline = ISPanel:derive("KnoxTimeline")
function KnoxTimeline:initialise() ISPanel.initialise(self) end
function KnoxTimeline:setBlocks(blocks)
    self.blocks = type(blocks) == "table" and blocks or {}
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local minWidth = 1
    for _, block in ipairs(self.blocks) do
        minWidth = math.max(minWidth, measure(tostring(block.hours or "")) + 8,
            measure(tostring(block.label or "")) + 8)
    end
    local width = math.max(1, self.width - 2)
    local geometry = UILayout.timelineCells(#self.blocks, width,
        { gap = 3, height = fontH * 2 + 6, minCellWidth = minWidth })
    local maxLines = 2
    for _, cell in ipairs(geometry.cells) do
        local block = self.blocks[cell.index]
        if block ~= nil then
            local room = math.max(1, cell.width - 8)
            local lines = #timelineTextLines(block.hours, room, measure)
                + #timelineTextLines(block.label, room, measure)
            maxLines = math.max(maxLines, lines)
        end
    end
    self.cells = UILayout.timelineCells(#self.blocks, width,
        { gap = 3, height = maxLines * fontH + 6, minCellWidth = minWidth })
    self:setHeight(self.cells.height + 4)
end
function KnoxTimeline:render()
    local manager = getTextManager()
    local theme = UILayout.sheetTheme()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    if self.cells == nil then return end
    for _, cell in ipairs(self.cells.cells) do
        local block = self.blocks[cell.index]
        if block ~= nil then
            local colour = block.colour or { r = 0.42, g = 0.42, b = 0.42 }
            local top = 2 + (cell.y or 0)
            self:drawRect(1 + cell.x, top, cell.width, cell.height,
                self.enabled == true and 0.88 or 0.55, colour.r, colour.g, colour.b)
            if block.current == true then
                self:drawRect(1 + cell.x, top, cell.width, 2, 0.95,
                    theme.green[1], theme.green[2], theme.green[3])
            end
            local textY = top + 1
            for _, line in ipairs(timelineTextLines(block.hours, math.max(1, cell.width - 8), measure)) do
                self:drawText(line, 1 + cell.x + 4, textY, 0.70, 0.70, 0.68, 1, UIFont.Small)
                textY = textY + fontH
            end
            for _, line in ipairs(timelineTextLines(block.label, math.max(1, cell.width - 8), measure)) do
                self:drawText(line, 1 + cell.x + 4, textY, 0.96, 0.95, 0.93, 1, UIFont.Small)
                textY = textY + fontH
            end
        end
    end
end
function KnoxTimeline:onMouseDown(x, y)
    if self.owner == nil or self.cells == nil or self.enabled ~= true then return false end
    local index = UILayout.timelineIndexAt(self.cells, x - 1, y - 2)
    if index == nil then return false end
    self.owner:paintScheduleBlock({ knoxBlock = index })
    return true
end

local CrewView = ISPanelJoypad:derive("KnoxNotebookCrewView")
function CrewView:initialise() ISPanelJoypad.initialise(self) end
function CrewView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y = UI_BORDER_SPACING
    self.partyLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"With you",1,1,1,1,UIFont.Small,true); self.partyLabel:initialise(); self:addChild(self.partyLabel)
    y = y + FONT_HGT_SMALL + 2
    self.partyList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*2)
    self.partyList:initialise(); self.partyList:instantiate(); self.partyList.itemheight=BUTTON_HGT; self.partyList.font=UIFont.Small; self.partyList.doDrawItem=self.drawEntry; self.partyList.drawBorder=true; self.partyList.joypadParent=self; self:addChild(self.partyList)
    y = self.partyList:getBottom() + 4
    self.residentsLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"At this base - pick one",1,1,1,1,UIFont.Small,true); self.residentsLabel:initialise(); self:addChild(self.residentsLabel)
    y = y + FONT_HGT_SMALL + 2
    self.resList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.resList:initialise(); self.resList:instantiate(); self.resList.itemheight=BUTTON_HGT; self.resList.font=UIFont.Small; self.resList.doDrawItem=self.drawEntry; self.resList.drawBorder=true; self.resList.joypadParent=self; self:addChild(self.resList)
    y = self.resList:getBottom() + 6
    self.priorityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.priorityLabel:initialise(); self.priorityLabel.name="Work preferences"; self:addChild(self.priorityLabel)
    y = y + FONT_HGT_SMALL + 4
    local availableW = math.max(1, self.width - UI_BORDER_SPACING * 2)
    local priorityColumns = responsiveControlColumns(
        availableW, #PRIORITY_COLUMNS, 40, 4)
    local cellW = math.max(1, math.floor((availableW - (priorityColumns - 1) * 4) / priorityColumns))
    self.crewCells = {}
    for index, col in ipairs(PRIORITY_COLUMNS) do
        local slot = (index - 1) % priorityColumns
        local row = math.floor((index - 1) / priorityColumns)
        local btn = ISButton:new(UI_BORDER_SPACING + slot * (cellW + 4), y + row * (BUTTON_HGT + 2), cellW, BUTTON_HGT,
            col.label .. ":N", self, CrewView.onCrewPriorityCell)
        btn:initialise(); btn.background = true; btn.isBaseBackgroundVisible = true
        btn.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
            b = sheetTheme.border[3], a = 0.80 }; self:addChild(btn)
        btn.knoxGroup = col.key
        self.crewCells[col.key] = btn
    end
    y = y + math.ceil(#PRIORITY_COLUMNS / priorityColumns) * (BUTTON_HGT + 2) + 4
    self.scheduleResidentLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.scheduleResidentLabel:initialise(); self:addChild(self.scheduleResidentLabel)
    y = y + FONT_HGT_SMALL + 2
    self.scheduleLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.scheduleLabel:initialise(); self:addChild(self.scheduleLabel)
    y = y + FONT_HGT_SMALL + 4
    -- Paint tools first: pick one, then click a four-hour block. Selected
    -- tool gets the white border; it sticks until changed.
    self.scheduleTools = {}
    local toolColumns = responsiveControlColumns(
        availableW, #SCHEDULE_TOOLS, 40, 3)
    local toolW = math.max(1, math.floor((availableW - (toolColumns - 1) * 4) / toolColumns))
    for index, tool in ipairs(SCHEDULE_TOOLS) do
        local slot = (index - 1) % toolColumns
        local row = math.floor((index - 1) / toolColumns)
        local btn = ISButton:new(UI_BORDER_SPACING + slot * (toolW + 4), y + row * (BUTTON_HGT + 2), toolW, BUTTON_HGT,
            tool.label, self, CrewView.onSelectTool)
        btn:initialise()
        btn.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
            b = sheetTheme.border[3], a = 0.80 }
        local color = SCHEDULE_COLORS[tool.key]
        setPersistentButtonFill(btn, color, 0.9)
        btn.knoxTool = tool.key
        self:addChild(btn)
        self.scheduleTools[tool.key] = btn
    end
    y = y + math.ceil(#SCHEDULE_TOOLS / toolColumns) * (BUTTON_HGT + 2) + 4
    self.scheduleBlockBtns = {}
    -- Measure the real labels instead of assuming 120px: "Afternoon
    -- (12pm-4pm)" is wider than the word it replaced, and a fixed minimum
    -- would clip it on a small display.
    local blockMinWidth = 120
    for _, block in ipairs(KnoxOrderCatalog.scheduleBlocks) do
        local label = KnoxOrderCatalog.scheduleBlockLabel ~= nil
            and KnoxOrderCatalog.scheduleBlockLabel(block) or nil
        if label ~= nil then
            blockMinWidth = math.max(blockMinWidth,
                getTextManager():MeasureStringX(UIFont.Small, tostring(label)) + 18)
        end
    end
    local blockColumns = responsiveControlColumns(
        availableW, #KnoxOrderCatalog.scheduleBlocks, blockMinWidth, 6)
    local blockRows = math.ceil(#KnoxOrderCatalog.scheduleBlocks / blockColumns)
    local blockW = math.max(1, math.floor((availableW - (blockColumns - 1) * 4) / blockColumns))
    for index, block in ipairs(KnoxOrderCatalog.scheduleBlocks) do
        local slot = (index - 1) % blockColumns
        local row = math.floor((index - 1) / blockColumns)
        local btn = ISButton:new(UI_BORDER_SPACING + slot * (blockW + 4), y + row * (BUTTON_HGT + 2),
            blockW, BUTTON_HGT, KnoxOrderCatalog.scheduleBlockLabel(block), self, CrewView.onPaintBlock)
        btn:initialise(); btn.background = true; btn.isBaseBackgroundVisible = true
        btn.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
            b = sheetTheme.border[3], a = 0.80 }
        btn.knoxBlock = index
        self:addChild(btn)
        self.scheduleBlockBtns[index] = btn
    end
    y = y + blockRows * (BUTTON_HGT + 2) + 4
    self.saveScheduleBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Save Hours",self,CrewView.onSaveSchedule); self.saveScheduleBtn:initialise(); UILayout.tintSheetButton(self.saveScheduleBtn); self:addChild(self.saveScheduleBtn)
    self.colonyPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Colony Day",self,CrewView.onPresetColony); self.colonyPresetBtn:initialise(); UILayout.tintSheetButton(self.colonyPresetBtn); self:addChild(self.colonyPresetBtn)
    self.nightPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Night Shift",self,CrewView.onPresetNight); self.nightPresetBtn:initialise(); UILayout.tintSheetButton(self.nightPresetBtn); self:addChild(self.nightPresetBtn)
    self.roleHoursBtn=ISButton:new(0,y,110,BUTTON_HGT,"Role Hours",self,CrewView.onPresetRole); self.roleHoursBtn:initialise(); UILayout.tintSheetButton(self.roleHoursBtn); self:addChild(self.roleHoursBtn)
    self.copyPicker=ISComboBox:new(0,y,170,BUTTON_HGT,self,nil); self.copyPicker:initialise(); self:addChild(self.copyPicker)
    self.copyScheduleBtn=ISButton:new(0,y,64,BUTTON_HGT,"Copy",self,CrewView.onCopySchedule); self.copyScheduleBtn:initialise(); UILayout.tintSheetButton(self.copyScheduleBtn); self.copyScheduleBtn.tooltip="Copy this resident's saved hours to everyone, one role or one other resident."; self:addChild(self.copyScheduleBtn)
    self.guardOverrideBtn=ISButton:new(0,y,116,BUTTON_HGT,"Guard Tonight",self,CrewView.onGuardTonight); self.guardOverrideBtn:initialise(); UILayout.tintSheetButton(self.guardOverrideBtn); self:addChild(self.guardOverrideBtn)
    self.clearPresetBtn=ISButton:new(0,y,80,BUTTON_HGT,"Clear Draft",self,CrewView.onPresetClear); self.clearPresetBtn:initialise(); UILayout.tintSheetButton(self.clearPresetBtn); self:addChild(self.clearPresetBtn)
    self.resetPrioritiesBtn=ISButton:new(0,y,120,BUTTON_HGT,"Reset Work",self,CrewView.onResetPriorities); self.resetPrioritiesBtn:initialise(); UILayout.tintSheetButton(self.resetPrioritiesBtn); self:addChild(self.resetPrioritiesBtn)
    -- Two groups, because these controls do not do the same thing. The first
    -- only paints the unsaved draft, so nothing in the base changes until Save
    -- Hours. The second writes immediately. Flowed into one row under one set
    -- of labels, "Clear" beside "Normal Work" read like the same action twice:
    -- one empties a draft, the other replaces real saved work preferences.
    local function flowControls(controls, top)
        local cursorX, row = 0, 0
        for _, control in ipairs(controls) do
            local controlW = math.min(control.width, availableW)
            if cursorX > 0 and cursorX + controlW > availableW then
                cursorX, row = 0, row + 1
            end
            control:setX(UI_BORDER_SPACING + cursorX)
            control:setY(top + row * (BUTTON_HGT + 2))
            control:setWidth(controlW)
            cursorX = cursorX + controlW + 4
        end
        return top + (row + 1) * (BUTTON_HGT + 2)
    end
    self.crewCaptions = {}
    local function groupCaption(text, top)
        local caption = ISLabel:new(UI_BORDER_SPACING, top, FONT_HGT_SMALL, text,
            sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3], 1, UIFont.Small, true)
        caption:initialise()
        self:addChild(caption)
        self.crewCaptions[#self.crewCaptions + 1] = caption
        return top + FONT_HGT_SMALL + 2
    end
    y = groupCaption("Hours (draft) - Save Hours applies them.", y)
    y = flowControls({ self.colonyPresetBtn, self.nightPresetBtn, self.roleHoursBtn,
        self.clearPresetBtn, self.saveScheduleBtn }, y) + 2
    self.scheduleStatus=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true); self.scheduleStatus:initialise(); self:addChild(self.scheduleStatus)
    y = y + FONT_HGT_SMALL + 4
    -- One control per meaning. They are created here and placed by the
    -- captioned groups below, so a button cannot drift into the wrong section.
    local function crewButton(label, handler, width, hint)
        local button=ISButton:new(0,0,width,BUTTON_HGT,label,self,handler)
        button:initialise(); button.tooltip=hint
        button.borderColor={r=sheetTheme.border[1],g=sheetTheme.border[2],b=sheetTheme.border[3],a=0.8}
        button.backgroundColor={r=sheetTheme.charcoal[1],g=sheetTheme.charcoal[2],b=sheetTheme.charcoal[3],a=0.92}
        self:addChild(button)
        return button
    end
    local function crewPicker(choices)
        local picker=ISComboBox:new(0,0,165,BUTTON_HGT,self,nil)
        picker:initialise()
        for _, choice in ipairs(choices) do picker:addOption(choice.label) end
        picker.selected=1; self:addChild(picker)
        return picker
    end
    self.viewBtn=crewButton("View Card",CrewView.onView,95,"Open this resident's card: needs, traits, kit and history.")
    self.joinPartyBtn=crewButton("Join Party",CrewView.onJoinParty,95,"Take this resident with you now. Routine work they hold goes back to the queue.")
    self.sendHomeBtn=crewButton("Send Party Home",CrewView.onSendHome,120,"Send the whole party home to this base.")
    self.inventoryBtn=crewButton("Inventory",CrewView.onInventory,95,"Open this resident's pack - the same pane as the world menu.")
    self.setRoleBtn=crewButton("Apply Role",CrewView.onSetRole,90,"Apply the chosen role to this resident.")
    self.setJobBtn=crewButton("Apply Job",CrewView.onSetJob,90,"Apply the chosen preference to this resident.")
    self.factionBtn=crewButton("Faction: none",CrewView.onCycleFaction,150,"Move the selected survivor to the next group in the world.")
    self.standingOrderBtn=crewButton("Base order: Not set",CrewView.onCycleStandingOrder,170,"Cycle the base's standing order. Automatic work follows it.")
    self.rolePicker=crewPicker(BASE_ROLE_CHOICES)
    self.rolePicker.tooltip="A role is the work this resident prefers when they are free."
    self.jobPicker=crewPicker(BASE_JOB_CHOICES)
    self.jobPicker.tooltip="A preference decides which jobs they take when nothing else is ordered."
    y = groupCaption("Copy saved hours, or reset this resident's work", y)
    y = flowControls({ self.copyPicker, self.copyScheduleBtn, self.resetPrioritiesBtn }, y) + 4
    y = groupCaption("Take them with you", y)
    y = flowControls({ self.viewBtn, self.joinPartyBtn, self.sendHomeBtn, self.inventoryBtn }, y) + 4
    y = groupCaption("This resident's work", y)
    y = flowControls({ self.setRoleBtn, self.rolePicker, self.setJobBtn, self.jobPicker }, y) + 4
    y = groupCaption("This base's standing order", y)
    y = flowControls({ self.standingOrderBtn, self.guardOverrideBtn }, y) + 4
    y = groupCaption("Which group they belong to", y)
    y = flowControls({ self.factionBtn }, y) + 4
    y = y + 2
    self.kitStatus=ISLabel:new(UI_BORDER_SPACING,y,FONT_HGT_SMALL,
        "Kit: no resident selected.",0.72,0.72,0.70,1,UIFont.Small,true)
    self.kitStatus:initialise(); self:addChild(self.kitStatus)
    y = self.kitStatus:getBottom() + 6
    -- Beds belong to the people who sleep in them, so the roster, the saved day
    -- and the bed each resident holds are read on one page.
    self.bedsHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Beds",1,1,1,1,UIFont.Small,true)
    self.bedsHeading:initialise(); self:addChild(self.bedsHeading)
    y = y + FONT_HGT_SMALL + 2
    self.bedsLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",
        sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true)
    self.bedsLabel:initialise(); self:addChild(self.bedsLabel)
    y = y + FONT_HGT_SMALL + 2
    self.bedsList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.bedsList:initialise(); self.bedsList:instantiate(); self.bedsList.itemheight=BUTTON_HGT
    self.bedsList.font=UIFont.Small; self.bedsList.doDrawItem=self.drawEntry
    self.bedsList.drawBorder=true; self:addChild(self.bedsList)
    y = self.bedsList:getBottom() + 2
    -- Two painted panels replace the button grids: one table for work
    -- preferences and one timeline for the day. Both call the handlers that
    -- already existed.
    self.prefTable = KnoxPrefTable:new(0, 0, 1, 1)
    self.prefTable:initialise(); self.prefTable.owner = self; self:addChild(self.prefTable)
    self.timelinePanel = KnoxTimeline:new(0, 0, 1, 1)
    self.timelinePanel:initialise(); self.timelinePanel.owner = self; self:addChild(self.timelinePanel)
    self.knoxContentHeight = self.kitStatus:getBottom() + UI_BORDER_SPACING
    self:layoutPage()
end

-- Rail on the left, the selected resident's work and day on the right. The
-- split is measured: a page too narrow for both a readable rail and a readable
-- detail column stacks them instead of clipping the table.
local function layoutCrewText(view, label, key, x, y, width)
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local lines = timelineTextLines(label.knoxFullText or label.name or "", width, measure)
    if #lines == 0 then lines = { "" } end
    local extras = view[key] or {}
    view[key] = extras
    for index, line in ipairs(lines) do
        local target = index == 1 and label or extras[index - 1]
        if target == nil then
            target = ISLabel:new(x, y, fontH + 2, "", label.r, label.g, label.b, label.a, UIFont.Small, true)
            target:initialise(); view:addChild(target); extras[index - 1] = target
        end
        target:setNameWithoutMoving(line)
        target:setX(x); target:setY(y + (index - 1) * (fontH + 2))
        target:setHeight(fontH + 2); target:setVisible(true)
        if index > 1 and target.setColour ~= nil then target:setColour(label.r, label.g, label.b, label.a) end
    end
    for index = #lines, #extras do extras[index]:setVisible(false) end
    return y + #lines * (fontH + 2)
end

function CrewView:layoutPage()
    local spacing = UI_BORDER_SPACING
    local available = math.max(1, self.width - spacing * 2)
    local columns = UILayout.columns(available, { gap = 12, minLeft = 250, minRight = 380 })
    local rail, detail = columns.cells[1], columns.cells[2]
    local railX, detailX = spacing + rail.x, spacing + detail.x
    self.partyLabel:setX(railX); self.partyLabel:setY(spacing); self.partyLabel:setWidth(rail.width)
    self.partyList:setX(railX); self.partyList:setWidth(rail.width)
    self.partyList:setY(self.partyLabel:getBottom() + 2)
    self.partyList:setHeight(UILayout.stackHeight(#(self.partyList.items or {}), BUTTON_HGT, 2, 6))
    self.residentsLabel:setX(railX); self.residentsLabel:setWidth(rail.width)
    self.residentsLabel:setY(self.partyList:getBottom() + 6)
    self.resList:setX(railX); self.resList:setWidth(rail.width)
    self.resList:setY(self.residentsLabel:getBottom() + 2)
    self.resList:setHeight(UILayout.stackHeight(#(self.resList.items or {}), BUTTON_HGT, 3, 6))

    local detailTop = columns.count == 1 and self.resList:getBottom() + spacing or spacing
    self.priorityLabel:setX(detailX); self.priorityLabel:setY(detailTop); self.priorityLabel:setWidth(detail.width)
    self.prefTable:setX(detailX); self.prefTable:setY(self.priorityLabel:getBottom() + 2)
    self.prefTable:setWidth(detail.width)
    self.prefTable:setHeight(PREF_HEADER_H + PREF_ROW_H * #PRIORITY_COLUMNS + 4)
    self.prefTable:setRows(self.prefTable.rows)
    for _, column in ipairs(PRIORITY_COLUMNS) do
        local cell = self.crewCells[column.key]
        if cell ~= nil then cell:setVisible(false) end
    end
    local residentBottom = layoutCrewText(self, self.scheduleResidentLabel, "residentTextLines",
        detailX, self.prefTable:getBottom() + 4, detail.width)
    local scheduleBottom = layoutCrewText(self, self.scheduleLabel, "scheduleTextLines",
        detailX, residentBottom + 2, detail.width)
    local toolW = math.max(1, math.floor((detail.width - 8) / 3))
    local toolTop = scheduleBottom + 4
    for index, tool in ipairs(SCHEDULE_TOOLS) do
        local button = self.scheduleTools[tool.key]
        local slot = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        button:setX(detailX + slot * (toolW + 4))
        button:setY(toolTop + row * (BUTTON_HGT + 2))
        button:setWidth(toolW)
    end
    local toolRows = math.ceil(#SCHEDULE_TOOLS / 3)
    self.timelinePanel:setX(detailX)
    self.timelinePanel:setY(toolTop + toolRows * (BUTTON_HGT + 2) + 2)
    self.timelinePanel:setWidth(detail.width)
    self.timelinePanel:setBlocks(self.timelinePanel.blocks)
    for index = 1, #KnoxOrderCatalog.scheduleBlocks do
        local button = self.scheduleBlockBtns[index]
        if button ~= nil then button:setVisible(false) end
    end

    -- Footer groups span the page beneath both columns and wrap from their
    -- actual control widths. Captions move with the controls they describe.
    local y = math.max(self.resList:getBottom(), self.timelinePanel:getBottom()) + spacing
    local function caption(index)
        local label = self.crewCaptions[index]
        label:setX(spacing); label:setY(y); label:setWidth(available)
        y = label:getBottom() + 2
    end
    local function flow(controls)
        local cursor, row = 0, 0
        for _, control in ipairs(controls) do
            control.knoxCrewWidth = control.knoxCrewWidth or control.width
            local width = math.min(available, control.knoxCrewWidth)
            if cursor > 0 and cursor + width > available then cursor, row = 0, row + 1 end
            control:setX(spacing + cursor); control:setY(y + row * (BUTTON_HGT + 2))
            control:setWidth(width)
            cursor = cursor + width + 4
        end
        y = y + (row + 1) * (BUTTON_HGT + 2) + 4
    end
    caption(1); flow({ self.colonyPresetBtn, self.nightPresetBtn, self.roleHoursBtn,
        self.clearPresetBtn, self.saveScheduleBtn })
    y = layoutCrewText(self, self.scheduleStatus, "statusTextLines", spacing, y, available) + 4
    caption(2); flow({ self.copyPicker, self.copyScheduleBtn, self.resetPrioritiesBtn })
    caption(3); flow({ self.viewBtn, self.joinPartyBtn, self.sendHomeBtn, self.inventoryBtn })
    caption(4); flow({ self.setRoleBtn, self.rolePicker, self.setJobBtn, self.jobPicker })
    caption(5); flow({ self.standingOrderBtn, self.guardOverrideBtn })
    caption(6); flow({ self.factionBtn })
    y = layoutCrewText(self, self.kitStatus, "kitTextLines", spacing, y, available) + 4
    self.bedsHeading:setX(spacing); self.bedsHeading:setY(y); self.bedsHeading:setWidth(available)
    y = self.bedsHeading:getBottom() + 2
    -- The same measured text helper every other Crew line uses: this page keeps
    -- one label stack, so a long bed count cannot leave the sheet.
    y = layoutCrewText(self, self.bedsLabel, "crewBedLines", spacing, y, available) + 2
    self.bedsList:setX(spacing); self.bedsList:setY(y); self.bedsList:setWidth(available)
    self.bedsList:setHeight(UILayout.stackHeight(#(self.bedsList.items or {}), BUTTON_HGT, 2, 6))
    y = self.bedsList:getBottom()
    self.knoxContentHeight = y + spacing
end
function CrewView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; drawListRow(self,y,item); drawListText(self,y,item,a); return y+self.itemheight
end
function CrewView:populate(playerNum)
    local selectedId = self:selectedCrewId()
    local selectedSource = self.crewSelSource
    self.playerNum=playerNum
    self.partyList:clear(); self.resList:clear()
    self.partyIds={}; self.residentIds={}
    local snaps=KnoxSurvivorViewModel.getForPlayer(playerNum) or {}
    local pl=getSpecificPlayer(playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil
    local win = self:getWindow()
    local baseId = notebookBaseId(win, playerNum, pid)
    local base = baseId ~= nil and KnoxPersistence.getBase(baseId) or nil
    for _,s in ipairs(snaps) do
        local condition = KnoxSurvivorViewModel.rosterCondition ~= nil
            and KnoxSurvivorViewModel.rosterCondition(s) or nil
        local row = s.displayName .. "  |  " .. (s.professionLabel or "Survivor")
            .. "  |  " .. (s.orderLabel or "") .. "  |  " .. (s.activity or "")
        if condition ~= nil then row = row .. "  |  " .. condition end
        addRow(self.partyList,s.id,row)
        self.partyIds[#self.partyIds+1]=s.id
    end
    if #self.partyIds==0 then addRow(self.partyList,"none","No party - recruit survivors") end
    local residentRoster = base ~= nil and KnoxPersistence.getBaseResidentIds(base.id) or {}
    if base ~= nil and pid ~= nil and KnoxPersistence.getKnownSurvivorIds ~= nil then
        local included = {};for _,id in ipairs(residentRoster) do included[id]=true end
        for _,id in ipairs(KnoxPersistence.getKnownSurvivorIds(pid)) do
            local known=KnoxPersistence.getObserverKnowledge(pid,id)
            local last=known ~= nil and known.seen or nil
            if known ~= nil and known.commitment ~= nil and (last == nil or known.commitment.atHours >= last.atHours) then last=known.commitment end
            local value=last ~= nil and last.value or nil
            if value ~= nil and value.role=="resident" and value.duty ~= nil
                and value.duty.baseId==base.id and not included[id] then
                residentRoster[#residentRoster+1]=id; included[id]=true
            end
        end
    end
    if base then for _,id in ipairs(residentRoster) do
        local dup=false; for _,e in ipairs(self.partyIds) do if e==id then dup=true break end end
        if not dup then
            local ident=KnoxPersistence.getSurvivorIdentity(id) or {}
            local duty=KnoxPersistence.getSurvivorDuty(id) or {}
            local prof=KnoxPersistence.getSurvivorCapabilities(id) or {}
            local name=tostring(ident.forename or "").." "..tostring(ident.surname or "")
            local profLabel=KnoxSurvivorCapabilities.professionLabel(prof) or "Survivor"
            local work=workStatusFor(base, id)
            local taskLabel=work ~= nil and work.taskType ~= nil
                and KnoxOrderCatalog.label(work.taskType, work.taskType) or "Idle"
            local taskDetail = nil
            if work ~= nil and work.state == "claimed" and work.offscreen == true then
                taskLabel = taskLabel .. " (off-screen)"
            elseif work ~= nil and (work.state == "supply_order"
                or work.state == "supply_run") then
                taskLabel = "Supply run: " .. taskLabel
            elseif work ~= nil and work.state == "resting" then
                taskLabel = "Resting"
            elseif work ~= nil and work.state == "idle" and work.taskType ~= nil then
                taskDetail = "Last task: " .. taskLabel
            end
            local snapshot = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(id, playerNum) or nil
            if snapshot == nil or snapshot.knowledge == nil or snapshot.knowledge.current ~= true then
                taskLabel, taskDetail, work = "Unknown", nil, nil
            end
            local currentStatus = snapshot ~= nil and snapshot.activity or "Out of contact"
            local currentLocation = snapshot ~= nil and snapshot.locationLabel or nil
            if taskDetail == nil and work ~= nil and work.taskType ~= nil
                and snapshot ~= nil and currentStatus ~= taskLabel then
                taskDetail = "Task: " .. taskLabel
            end
            local jobPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or duty.jobPreference
            local condition = snapshot ~= nil and KnoxSurvivorViewModel.rosterCondition ~= nil
                and KnoxSurvivorViewModel.rosterCondition(snapshot) or nil
            addRow(self.resList,id, name .. "  |  Job: "
                .. KnoxOrderCatalog.label(jobPreference or "auto", "Automatic") .. "  |  " .. profLabel
                .. "  |  Now: " .. tostring(currentStatus)
                .. (currentLocation ~= nil and "  |  " .. tostring(currentLocation) or "")
                .. (taskDetail ~= nil and "  |  " .. taskDetail or "")
                .. (condition ~= nil and "  |  " .. condition or ""))
            self.residentIds[#self.residentIds+1]=id
        end
    end end
    if #self.residentIds==0 then addRow(self.resList,"none", base ~= nil and "No residents at this base" or "No home base yet"); end
    self:restoreCrewSelection(selectedId, selectedSource)
    self:paintCrewDetail()
    populateBedSection(self, base)
    self:layoutPage()
end
function CrewView:onView()
    local id = self:selectedCrewId()
    if id ~= nil then KnoxSurvivorCard.show(self.playerNum, id) end
end

-- Opens the selected resident's pack through the existing survivor-inventory
-- owner, so distance, ownership and the interaction lease are still its rules.
-- A refusal is explained instead of looking like a dead button, and the
-- notebook only steps aside once the pack really opened.
function CrewView:onInventory()
    local id = self:selectedCrewId()
    if id == nil then return end
    local inventory = rawget(_G, "KnoxCompanionInventory")
    if inventory == nil or inventory.show == nil then
        KnoxActivityFeed.event("Survivor inventory is not available on this build.")
        return
    end
    local win = self.getWindow ~= nil and self:getWindow() or nil
    local playerNum = (win ~= nil and win.playerNum) or self.playerNum or 0
    local accepted, reason = inventory.show(playerNum, id)
    if accepted then
        if win ~= nil then win:setVisible(false) end
        return
    end
    local text = inventory.refusalText ~= nil and inventory.refusalText(reason)
        or "That pack cannot be opened right now."
    KnoxActivityFeed.event(text)
end
local function crewRequest(label, callback, ...)
    if KnoxOrderCatalog.withFeedback ~= nil then
        return KnoxOrderCatalog.withFeedback(label, callback, ...)
    end
    return callback(...)
end

function CrewView:onSendHome()
    local p = getSpecificPlayer(self.playerNum)
    if not p then return end
    local companions = {}
    for _, s in ipairs(KnoxSurvivorViewModel.getForPlayer(self.playerNum) or {}) do
        companions[#companions + 1] = s.id
    end
    if #companions == 0 then return end
    -- Several homes: ask once, then send the whole party to the choice.
    local pid = KnoxPersistence.ensurePlayerId(p)
    local bases = notebookBases(pid)
    local picker = rawget(_G, "KnoxBasePicker")
    if #bases > 1 and picker ~= nil and picker.choose ~= nil then
        picker.choose(self.playerNum, "Send the party home to which base?", bases, function(baseId)
            if baseId == nil then return end
            for _, id in ipairs(companions) do
                crewRequest("Return to base", KnoxCompanionService.sendToBase, p, id, baseId)
            end
            self:populate(self.playerNum)
        end)
        return
    end
    for _, id in ipairs(companions) do
        crewRequest("Return to base", KnoxCompanionService.sendToBase, p, id)
    end
    self:populate(self.playerNum)
end
function CrewView:onJoinParty()
    local id=self:selectedCrewId(); local player=getSpecificPlayer(self.playerNum)
    if id == nil or player == nil then return end
    local changed = crewRequest("Join party", KnoxCompanionService.recallToParty, player, id)
    if changed then
        self:populate(self.playerNum)
    end
end
function CrewView:onSetJob()
    local id=self:selectedCrewId(); local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local duty=id and KnoxPersistence.getSurvivorDuty(id) or nil
    local win = self:getWindow()
    local baseId = notebookBaseId(win, self.playerNum, playerId)
    local base = baseId ~= nil and KnoxPersistence.getBase(baseId) or nil
    local choice=BASE_JOB_CHOICES[self.jobPicker.selected or 1]
    if id == nil or duty == nil or base == nil or duty.mode ~= "base" or duty.baseId ~= base.id or choice == nil then return end
    -- The notebook may be looking at a non-primary owned base. Pass that
    -- selected base through the existing service boundary so validation and
    -- persistence target the same resident context shown to the player.
    local changed = crewRequest("Base job preference", KnoxCompanionService.setBaseJobPreference,
        player, id, choice.value, base.id
    )
    if changed then
        KnoxActivityFeed.event("Base job preference set to " .. string.lower(choice.label) .. ".")
        self:populate(self.playerNum)
    end
end

function CrewView:onCycleStandingOrder()
    local player, base, playerNum = self:schedulePlayerAndBase()
    if player == nil or base == nil or base.ownerKind ~= "player" then
        KnoxActivityFeed.event("Select one of your bases first.")
        return
    end
    local catalog = rawget(_G, "KnoxBaseContextMenu")
    local choices = catalog ~= nil and catalog.BASE_INTENTS or nil
    if type(choices) ~= "table" or #choices == 0 then
        KnoxActivityFeed.event("Standing orders are unavailable on this build.")
        return
    end
    local current = KnoxPersistence.getBaseIntent ~= nil
        and KnoxPersistence.getBaseIntent(base.id) or nil
    local nextIndex = 1
    for index, entry in ipairs(choices) do
        if entry.key == current then nextIndex = index + 1 break end
    end
    if nextIndex > #choices then nextIndex = 1 end
    local entry = choices[nextIndex]
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local ok, reason = KnoxPersistence.setBaseIntent(
        base.id, playerId, entry.key, hours)
    if not ok then
        KnoxActivityFeed.event("Could not set the standing order: "
            .. tostring(reason) .. ".")
        return
    end
    KnoxActivityFeed.event("Standing order: "
        .. tostring(entry.label or entry.key) .. ".")
    self:populate(playerNum or self.playerNum or 0)
end

function CrewView:onSetRole()
    local id=self:selectedCrewId(); local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local duty=id and KnoxPersistence.getSurvivorDuty(id) or nil
    local win = self:getWindow()
    local baseId = notebookBaseId(win, self.playerNum, playerId)
    local base = baseId ~= nil and KnoxPersistence.getBase(baseId) or nil
    local choice=BASE_ROLE_CHOICES[self.rolePicker.selected or 1]
    if id == nil or duty == nil or base == nil or duty.mode ~= "base" or duty.baseId ~= base.id or choice == nil then return end
    local changed = crewRequest("Base role", KnoxCompanionService.setBaseJobPreference,
        player, id, choice.value, base.id
    )
    if changed then
        local label = choice.value == "auto" and "automatic" or string.lower(choice.label)
        KnoxActivityFeed.event("Base role set to " .. label .. ".")
        self:populate(self.playerNum)
    end
end

-- FACTION CHOICES (pure)
-- Where a crew member can be moved. The list is every named group in the world,
-- rotated so the first entry is the next one after where they stand now; the
-- current group is last, so one press always changes something unless there is
-- only one group. The persistence writer still decides whether the move is
-- allowed: this list only says what is possible, never what is permitted.
function CrewView.factionChoices(factions, currentId)
    local ordered, currentIndex = {}, nil
    if type(factions) ~= "table" then return ordered, nil end
    for _, faction in ipairs(factions) do
        if type(faction) == "table" and type(faction.id) == "string"
            and faction.id ~= ""
            and type(faction.name) == "string" and faction.name ~= "" then
            ordered[#ordered + 1] = { id = faction.id, label = faction.name }
        end
    end
    table.sort(ordered, function(first, second) return first.id < second.id end)
    for index, entry in ipairs(ordered) do
        if entry.id == currentId then currentIndex = index end
    end
    local rotated, currentLabel = {}, nil
    if currentIndex ~= nil then
        currentLabel = ordered[currentIndex].label
        for offset = 1, #ordered do
            rotated[offset] = ordered[((currentIndex - 1 + offset) % #ordered) + 1]
        end
    else
        for index = 1, #ordered do rotated[index] = ordered[index] end
    end
    return rotated, currentLabel
end

-- The writer's reasons, said in a sentence. Copy only: the decision stays in
-- `KnoxPersistence.addFactionMember`, which is why this table invents nothing.
local FACTION_REFUSALS = {
    missing_faction = "That group is gone.",
    missing_survivor = "That survivor is gone.",
    dead = "They are dead.",
    event_managed = "They belong to their own story.",
    departing = "They are already leaving.",
    away_team = "They are away on a job.",
    player_affiliated = "They answer to you, not to that group.",
}

function CrewView.factionRefusalText(reason)
    return FACTION_REFUSALS[reason] or "They cannot join that group now."
end
-- END FACTION CHOICES

function CrewView:onCycleFaction()
    local id = self:selectedCrewId()
    if id == nil then
        KnoxActivityFeed.event("No survivor selected.")
        return
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
        and KnoxPersistence.getSurvivorAffiliation(id) or nil
    local currentId = affiliation ~= nil and affiliation.factionId or nil
    local factions = KnoxPersistence.getFactions ~= nil
        and KnoxPersistence.getFactions() or {}
    local choices = CrewView.factionChoices(factions, currentId)
    local choice = choices[1]
    if choice == nil then
        KnoxActivityFeed.event("No group can take them right now.")
        return
    end
    -- One group in the world means the rotation offers the group they are
    -- already in. Say so; never report a move that did not happen.
    if currentId ~= nil and choice.id == currentId then
        KnoxActivityFeed.event("Already in " .. tostring(choice.label) .. ".")
        return
    end
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local ok, reason = KnoxPersistence.addFactionMember(choice.id, id, hours)
    if not ok then
        KnoxActivityFeed.event(CrewView.factionRefusalText(reason))
        return
    end
    KnoxActivityFeed.event("Moved into " .. tostring(choice.label) .. ".")
    self:populate(self.playerNum)
end

function CrewView:getWindow() return self:getParent():getParent() end

function CrewView:selectedCrewId()
    local psel = self.partyList ~= nil and (self.partyList.selected or 0) or 0
    local rsel = self.resList ~= nil and (self.resList.selected or 0) or 0
    -- Exactly one side moved: that list owns the selection. Both moving at
    -- once is the refresh-restore tick, so keep the previous owner.
    local pChanged = psel ~= (self.lastPartySel or 0)
    local rChanged = rsel ~= (self.lastResSel or 0)
    if pChanged and not rChanged then self.crewSelSource = "party"
    elseif rChanged and not pChanged then self.crewSelSource = "residents" end
    self.lastPartySel, self.lastResSel = psel, rsel
    if self.crewSelSource == "party" then
        local id = self.partyIds ~= nil and self.partyIds[psel] or nil
        if id ~= nil then return id end
    end
    if self.residentIds ~= nil and #self.residentIds > 0 then
        return self.residentIds[rsel] or self.residentIds[1]
    end
    return nil
end

function CrewView:restoreCrewSelection(preferredId, preferredSource)
    local partyIndex, residentIndex
    if preferredId ~= nil and preferredSource == "party" then
        for index, id in ipairs(self.partyIds or {}) do
            if id == preferredId then partyIndex = index; break end
        end
    elseif preferredId ~= nil and preferredSource == "residents" then
        for index, id in ipairs(self.residentIds or {}) do
            if id == preferredId then residentIndex = index; break end
        end
    end
    -- The resident roster is the context for work and schedule controls, so
    -- use it as the useful first selection when opening the page.
    if partyIndex == nil and residentIndex == nil then
        if #(self.residentIds or {}) > 0 then
            residentIndex = 1
        elseif #(self.partyIds or {}) > 0 then
            partyIndex = 1
        end
    end
    self.partyList.selected = partyIndex or 0
    self.resList.selected = residentIndex or 0
    self.crewSelSource = partyIndex ~= nil and "party"
        or (residentIndex ~= nil and "residents" or nil)
    self.lastPartySel = self.partyList.selected
    self.lastResSel = self.resList.selected
end

function CrewView:crewBase()
    local p = getSpecificPlayer(self.playerNum or 0)
    local pid = p ~= nil and KnoxPersistence.ensurePlayerId(p) or nil
    local baseId = notebookBaseId(self:getWindow(), self.playerNum, pid)
    if baseId == nil then return nil end
    return KnoxPersistence.getBase(baseId)
end

function CrewView:schedulePlayerAndBase()
    local win = self:getWindow()
    local playerNum = (win ~= nil and win.playerNum) or self.playerNum or 0
    local player = getSpecificPlayer(playerNum)
    local pid = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local baseId = notebookBaseId(win, playerNum, pid)
    local base = baseId ~= nil and KnoxPersistence.getBase(baseId) or nil
    return player, base, playerNum
end

-- Drafts are 24-entry hour arrays living on the view (never persisted)
-- until Save Hours compresses them to backend windows. A missing draft
-- expands the saved schedule; no saved schedule paints all-Free, because
-- that is the truth (anything goes until the player saves hours).
function CrewView:scheduleDraftFor(residentId)
    self.scheduleDrafts = self.scheduleDrafts or {}
    if residentId == nil then return nil end
    self.scheduleDraftBaselines = self.scheduleDraftBaselines or {}
    local saved = KnoxPersistence.getDutySchedule ~= nil
        and KnoxPersistence.getDutySchedule(residentId) or nil
    local hours = KnoxPersistence.dutyWindowsToHours ~= nil
        and KnoxPersistence.dutyWindowsToHours(saved) or {}
    local draft = self.scheduleDrafts[residentId]
    local baseline = self.scheduleDraftBaselines[residentId]
    local missing = draft == nil
    local untouched, matchesSaved = baseline ~= nil, draft ~= nil
    for hour = 1, 24 do
        if (draft or {})[hour] ~= (baseline or {})[hour] then untouched = false end
        if (draft or {})[hour] ~= hours[hour] then matchesSaved = false end
    end
    -- Opening a resident is not an edit. Refresh clean views from the current
    -- accepted schedule, while keeping genuine unsaved/rejected hours intact.
    if missing or untouched then
        draft = hours
        self.scheduleDrafts[residentId] = draft
    end
    if baseline == nil or missing or untouched or matchesSaved then
        local current = {}
        for hour = 1, 24 do current[hour] = hours[hour] end
        self.scheduleDraftBaselines[residentId] = current
    end
    return draft
end

function CrewView:paintScheduleStrip(draft)
    local hourNow = currentScheduleHour()
    local now = hourNow ~= nil and math.floor(hourNow) % 24 or nil
    local blocks = {}
    for index, block in ipairs(KnoxOrderCatalog.scheduleBlocks) do
        local assignment = type(draft) == "table"
            and KnoxOrderCatalog.scheduleBlockValue(draft, index) or nil
        local current = now ~= nil and now >= block.startHour
            and now < block.startHour + 4
        blocks[#blocks + 1] = {
            index = index,
            hours = KnoxOrderCatalog.scheduleBlockLabel(block),
            label = draft == nil and "No hours"
                or (SCHEDULE_BLOCK_LABELS[assignment] or "Mixed"),
            colour = SCHEDULE_COLORS[assignment] or SCHEDULE_COLORS.anything,
            current = current and draft ~= nil,
        }
    end
    if self.timelinePanel ~= nil then
        local oldHeight = self.timelinePanel.height
        self.timelinePanel:setBlocks(blocks)
        self.timelinePanel.enabled = draft ~= nil
        if self.timelinePanel.height ~= oldHeight then self:layoutPage() end
    end
end

function CrewView:crewDisplayName(residentId)
    local identity = KnoxPersistence.getSurvivorIdentity(residentId) or {}
    local name = (tostring(identity.forename or "") .. " "
        .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Resident " .. tostring(residentId) end
    return name
end

-- Read-only role-kit readiness for the selected resident. The equipment owner
-- decides what is carried, the storage owner resolves assigned stock, and this
-- function only composes their facts for the Crew detail line.
function CrewView.kitStatusFor(duty, character, base)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    local equipment = rawget(_G, "KnoxEquipmentIntelligence")
    local storage = rawget(_G, "KnoxBaseStorage")
    if catalog == nil or equipment == nil or storage == nil then
        return "Kit: readiness unavailable."
    end
    local role = duty ~= nil and catalog.roleForPreference ~= nil
        and catalog.roleForPreference(duty.jobPreference) or nil
    local gear = role ~= nil and catalog.roleGear ~= nil
        and catalog.roleGear(role) or {}
    if role == nil or type(gear) ~= "table" or #gear == 0 then
        return "Kit: no role assigned."
    end
    if character == nil then
        return "Kit: out of contact - readiness unknown."
    end
    local missing = equipment.roleKitMissing ~= nil
        and equipment.roleKitMissing(character, gear) or nil
    if type(missing) ~= "table" then
        return "Kit: readiness unavailable."
    end
    if #missing > 0 and (equipment.roleKitMatches == nil
        or storage.roleKitStock == nil) then
        return "Kit: readiness unavailable."
    end
    local stock = #missing > 0 and storage.roleKitStock(base, character,
        missing, equipment.roleKitMatches) or {}
    return catalog.roleKitStatusText ~= nil
        and catalog.roleKitStatusText(role, gear, missing, stock)
        or "Kit: readiness unavailable."
end

-- Copy targets come from the same live base roster the Crew tab displays,
-- including residents who are currently travelling with the player and so
-- appear in the party list rather than the resident list. Dead residents are
-- omitted before the writer is asked to refuse them.
function CrewView:scheduleCopyRoster(base)
    local roster = {}
    if base == nil then return roster end
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        local alive = KnoxPersistence.isSurvivorAlive == nil
            or KnoxPersistence.isSurvivorAlive(id) == true
        if alive then
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            local role = KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or "auto"
            roster[#roster + 1] = {
                id = id,
                role = role,
                name = self:crewDisplayName(id),
            }
        end
    end
    return roster
end

function CrewView:scheduleDraftClean(residentId)
    local draft = self.scheduleDrafts ~= nil
        and self.scheduleDrafts[residentId] or nil
    if draft == nil then return true end
    local saved = KnoxPersistence.getDutySchedule ~= nil
        and KnoxPersistence.getDutySchedule(residentId) or nil
    local baseline = KnoxPersistence.dutyWindowsToHours ~= nil
        and KnoxPersistence.dutyWindowsToHours(saved) or {}
    for hour = 1, 24 do
        if draft[hour] ~= baseline[hour] then return false end
    end
    return true
end

-- One flat list of concrete copy questions: everyone, each stored role that
-- has a target, then each other resident. Keeping the target ids inside the
-- entries lets the button act on the exact choice without a second picker.
function CrewView:scheduleCopyScopes(sourceId, roster)
    local scopes = {}
    local everyone = KnoxOrderCatalog.scheduleCopyTargets(sourceId, roster, "all")
    if #everyone == 0 then return scopes end
    scopes[#scopes + 1] = {
        key = "all", scope = "all", value = nil,
        label = "Everyone (" .. tostring(#everyone) .. ")",
    }
    for _, role in ipairs(KnoxOrderCatalog.basePreferenceOrder or {}) do
        local targets = KnoxOrderCatalog.scheduleCopyTargets(
            sourceId, roster, "role", role)
        if #targets > 0 then
            scopes[#scopes + 1] = {
                key = "role:" .. role, scope = "role", value = role,
                label = "Role: " .. KnoxOrderCatalog.label(role, role)
                    .. " (" .. tostring(#targets) .. ")",
            }
        end
    end
    for _, entry in ipairs(roster) do
        if tostring(entry.id) ~= tostring(sourceId) then
            scopes[#scopes + 1] = {
                key = "person:" .. tostring(entry.id), scope = "person",
                value = entry.id, label = "Only " .. entry.name,
            }
        end
    end
    return scopes
end

function CrewView:refreshCopyPicker(sourceId, roster)
    self.copyScopes = self:scheduleCopyScopes(sourceId, roster)
    if self.copyPicker == nil then return end
    local previous = self.copyScopeKey
    local current = self.copyScopes[self.copyPicker.selected or 0]
    if current ~= nil then previous = current.key end
    self.copyPicker:clear()
    local selected = 0
    for index, entry in ipairs(self.copyScopes) do
        self.copyPicker:addOption(entry.label)
        if selected == 0 and entry.key == previous then selected = index end
    end
    if #self.copyScopes == 0 then
        self.copyPicker:addOption("No other residents")
        self.copyPicker.selected = 1
        self.copyScopeKey = nil
        return
    end
    if selected == 0 then selected = 1 end
    self.copyPicker.selected = selected
    self.copyScopeKey = self.copyScopes[selected].key
end

function CrewView:copyScheduleTo(scope, value)
    local player, base = self:schedulePlayerAndBase()
    local sourceId = self:selectedCrewId()
    if player == nil or base == nil or sourceId == nil then return end
    local duty = KnoxPersistence.getSurvivorDuty(sourceId)
    if duty == nil or duty.mode ~= "base" or duty.baseId ~= base.id then
        KnoxActivityFeed.event("Schedules apply to base residents.")
        return
    end
    -- The copy is a saved-rota action. A dirty draft must be accepted through
    -- Save Hours first, so copying cannot persist hours the player never saw
    -- accepted for the source resident.
    if not self:scheduleDraftClean(sourceId) then
        KnoxActivityFeed.event("Save Hours before copying this rota.")
        return
    end
    local roster = self:scheduleCopyRoster(base)
    local targets = KnoxOrderCatalog.scheduleCopyTargets(sourceId, roster, scope, value)
    if #targets == 0 then
        KnoxActivityFeed.event("No other resident matches that copy.")
        return
    end
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.setBaseDutySchedule == nil then
        KnoxActivityFeed.event("Schedule writing is unavailable on this build.")
        return
    end
    local schedule = KnoxPersistence.getDutySchedule(sourceId)
    local batch = {}
    local copied, failed = 0, 0
    for _, id in ipairs(targets) do
        local ok = service.setBaseDutySchedule(player, id, schedule, base.id, batch)
        if ok == true then
            copied = copied + 1
            if self.scheduleDrafts ~= nil then self.scheduleDrafts[id] = nil end
        else
            failed = failed + 1
        end
    end
    if copied == 0 then
        KnoxActivityFeed.event("No hours copied: no other resident could be updated.")
        return
    end
    local text = "Hours copied to " .. tostring(copied)
        .. (copied == 1 and " resident" or " residents")
    if failed > 0 then
        text = text .. "; " .. tostring(failed) .. " could not be updated"
    end
    KnoxActivityFeed.event(text .. ".")
    self:populate(self.playerNum or 0)
end

function CrewView:onCopySchedule()
    local index = self.copyPicker ~= nil and (self.copyPicker.selected or 0) or 0
    local entry = self.copyScopes ~= nil and self.copyScopes[index] or nil
    if entry == nil then
        KnoxActivityFeed.event("No other residents at this base.")
        return
    end
    self:copyScheduleTo(entry.scope, entry.value)
end

-- True when every hour is already "Anything", so Clear Draft would be a
-- no-op. Pure: it reads only the draft it is shown.
function CrewView.draftAllAnything(draft)
    if type(draft) ~= "table" then return true end
    for hour = 1, 24 do
        local value = draft[hour]
        if value ~= nil and value ~= "anything" then return false end
    end
    return true
end

function CrewView.scheduleStatusText(saved, draft, activeOverride)
    local baseline = KnoxPersistence.dutyWindowsToHours ~= nil
        and KnoxPersistence.dutyWindowsToHours(saved) or {}
    for hour = 1, 24 do
        if (draft or {})[hour] ~= baseline[hour] then
            return "Unsaved changes - select Save Hours."
        end
    end
    if activeOverride ~= nil then
        local label = SCHEDULE_ASSIGNMENT_LABELS[activeOverride.assignment] or "Temporary"
        return "Temporary " .. string.lower(label) .. " until "
            .. string.format("%02d:00", math.floor(activeOverride.expiresAtHours) % 24)
            .. " - saved hours unchanged."
    end
    return saved == nil and "Default schedule - Anything." or "Saved schedule."
end

-- The priority cells print a short state token ("Guard:N") for width, which is
-- only legible if you already know the cycle. The hint says what the current
-- state means for that one column, so a player does not have to click to find
-- out. Unknown states fall back to naming the column, never to a guess.
-- These keys are the real cycle from PRIORITY_STATE_NEXT: normal to high to
-- low to disabled and back. A hint table that does not match it would send
-- every state down the fallback sentence.
local PRIORITY_STATE_HINTS = {
    high = "is picked for this before other work",
    normal = "takes this like any other job",
    low = "only takes this when nothing better is left",
    disabled = "does not take this at all",
}

function CrewView.priorityHint(label, value)
    local state = PRIORITY_STATE_LABELS[value] or tostring(value)
    local hint = PRIORITY_STATE_HINTS[value] or "has no stated preference"
    return tostring(label) .. ": " .. tostring(state)
        .. " - this resident " .. hint .. ". Click to cycle."
end

-- A refresh is not a reset (owner report, 2026-11-03). The crew panel repaints
-- on every tick and every status change, and it used to re-point both pickers at
-- the saved preference each time. A player who had just chosen Automatic in the
-- role picker watched it snap back to Woodworking before they could reach Set
-- Role. The picker now yields to the player: it follows the saved value only
-- while it still shows the index it was last synced to. Choosing another person
-- re-syncs both pickers, and applying a role re-syncs in the same pass, so the
-- control can never disagree with the duty it describes for longer than a frame.
function CrewView:syncCrewPicker(picker, field, choices, value, residentId)
    if picker == nil or type(choices) ~= "table" then return end
    local syncedField = field .. "Synced"
    local moved = self.pickerResidentId == residentId
        and type(self[syncedField]) == "number"
        and (picker.selected or 0) ~= self[syncedField]
    if moved then return end
    for index, choice in ipairs(choices) do
        if choice.value == value then
            picker.selected = index
            self[syncedField] = index
            return
        end
    end
    self[syncedField] = picker.selected
end

function CrewView:paintCrewDetail()
    local id = self:selectedCrewId()
    self.detailResidentId = id
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
    local intent = base ~= nil and KnoxPersistence.getBaseIntent ~= nil
        and KnoxPersistence.getBaseIntent(base.id) or nil
    local intentUi = rawget(_G, "KnoxBaseContextMenu")
    local intentLabels = intentUi ~= nil and intentUi.BASE_INTENT_LABELS or nil
    local orderLabel = intent ~= nil
        and ((intentLabels ~= nil and intentLabels[intent]) or intent)
        or "Not set"
    if self.standingOrderBtn ~= nil then
        self.standingOrderBtn:setTitle("Base order: " .. tostring(orderLabel))
        self.standingOrderBtn:setEnable(base ~= nil and base.ownerKind == "player")
    end
    local resident = duty ~= nil and duty.mode == "base"
        and base ~= nil and duty.baseId == base.id
    -- Priority row for the selected survivor.
    local map = id ~= nil and KnoxPersistence.getWorkPreferences ~= nil
        and KnoxPersistence.getWorkPreferences(id) or nil
    if self.prefTable ~= nil then
        local rows = {}
        for index, col in ipairs(PRIORITY_COLUMNS) do
            rows[index] = {
                index = index,
                key = col.key,
                label = col.label,
                state = map ~= nil and map[col.key] or "normal",
            }
        end
        self.prefTable:setRows(rows)
        self.prefTable.enabled = resident
        self.prefTable:setVisible(true)
    end
    -- Schedule strip for the selected resident.
    local draft = resident and self:scheduleDraftFor(id) or nil
    -- Painting tool sticks per view; it defaults to the displayed hour's
    -- assignment whenever the selected resident changes, never mid-stroke
    -- (repaints run on a timer but the default only applies on switch).
    if id == nil then
        self.scheduleTool, self.scheduleToolFor = "sleep", nil
    elseif self.scheduleToolFor ~= id then
        local hourNow = currentScheduleHour()
        local shown = draft ~= nil and hourNow ~= nil
            and draft[(math.floor(hourNow) % 24) + 1] or nil
        if SCHEDULE_COLORS[shown] == nil then shown = "sleep" end
        self.scheduleTool, self.scheduleToolFor = shown, id
    end
    for _, tool in ipairs(SCHEDULE_TOOLS) do
        local btn = self.scheduleTools[tool.key]
        if tool.key == self.scheduleTool and resident then
            btn.borderColor = { r = 1, g = 1, b = 1, a = 0.95 }
        else
            btn.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
            b = sheetTheme.border[3], a = 0.80 }
        end
        btn:setEnable(resident)
    end
    self:paintScheduleStrip(draft)
    if id == nil then
        self.scheduleResidentLabel.name = "Resident: none selected"
        self.scheduleLabel.name = "Select a base resident to edit a schedule."
        self.scheduleStatus.name = ""
    else
        self.scheduleResidentLabel.name = "Resident: " .. self:crewDisplayName(id)
        local hourNow = currentScheduleHour()
        local hour = hourNow ~= nil and math.floor(hourNow) % 24 or nil
        local saved = KnoxPersistence.getDutySchedule ~= nil
            and KnoxPersistence.getDutySchedule(id) or nil
        local selectedTool = SCHEDULE_ASSIGNMENT_LABELS[self.scheduleTool] or "Sleep"
        local assignment = draft ~= nil and hour ~= nil and draft[hour + 1] or nil
        if assignment == nil and hour ~= nil then
            assignment = KnoxPersistence.scheduleAssignmentFor ~= nil
                and KnoxPersistence.scheduleAssignmentFor(saved, hour) or "anything"
        end
        local nowLabel = hour ~= nil
            and ("Now: " .. string.format("%02d", hour) .. ": "
                .. tostring(SCHEDULE_ASSIGNMENT_LABELS[assignment] or assignment))
            or "Current time unavailable"
        self.scheduleLabel.name = nowLabel .. "  |  Assign: " .. selectedTool
        if not resident then
            self.scheduleStatus.name = "Schedules apply to base residents."
        else
            local activeOverride = KnoxPersistence.getDutyScheduleOverride ~= nil
                and KnoxPersistence.getDutyScheduleOverride(id) or nil
            self.scheduleStatus.name = CrewView.scheduleStatusText(saved, draft, activeOverride)
        end
    end
    local copyRoster = {}
    local copyClean = false
    if id ~= nil and resident and base ~= nil then
        copyRoster = self:scheduleCopyRoster(base)
        copyClean = self:scheduleDraftClean(id)
    end
    self:refreshCopyPicker(id, copyRoster)
    local copyCount = #(self.copyScopes or {})
    -- Two draft controls now say what state they are in. The status line
    -- already admits an unsaved draft in words, but Save Hours sat identically
    -- styled among five presets, so the one control that resolves the warning
    -- gave no sign it was the next step. Clear Draft is offered only when
    -- there is something to clear.
    if self.saveScheduleBtn ~= nil then
        local dirtyDraft = resident == true and id ~= nil and copyClean ~= true
        self.saveScheduleBtn:setTitle(dirtyDraft and "Save Hours *" or "Save Hours")
        self.saveScheduleBtn.tooltip = dirtyDraft
            and "These hours are not saved yet. Residents still follow the saved rota until you save."
            or "Save the hours shown above for this resident."
    end
    if self.clearPresetBtn ~= nil then
        local clearable = resident == true and id ~= nil
            and not CrewView.draftAllAnything(draft)
        self.clearPresetBtn:setEnable(clearable)
        self.clearPresetBtn.tooltip = clearable
            and "Empty the draft to Anything. Nothing is saved until Save Hours."
            or "The draft is already empty."
    end
    -- The status line is the only place that admits an unsaved draft, and it
    -- was drawn in the same quiet grey as the settled "Saved schedule" note, so
    -- the state that wants the player looked like the state that does not. It
    -- now takes the notebook's amber accent while a draft is pending, the same
    -- accent the commit button wears. Guarded: a label is not always an
    -- ISLabel here, and a cosmetic repaint must never break the page.
    if self.scheduleStatus ~= nil and self.scheduleStatus.setColour ~= nil then
        local amber = sheetTheme.amber
        local pending = resident == true and id ~= nil and copyClean ~= true
        pcall(function()
            if pending then
                self.scheduleStatus:setColour(amber[1], amber[2], amber[3], 1)
            else
                self.scheduleStatus:setColour(sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3], 1)
            end
        end)
    end
    self.scheduleResidentLabel.knoxFullText = self.scheduleResidentLabel.name
    self.scheduleLabel.knoxFullText = self.scheduleLabel.name
    self.scheduleStatus.knoxFullText = self.scheduleStatus.name

    self.scheduleCopyReady = resident and copyClean and copyCount > 0
    if self.copyPicker ~= nil then
        self.copyPicker:setEnabled(resident == true and copyCount > 0)
    end
    if self.copyScheduleBtn ~= nil then
        self.copyScheduleBtn:setEnable(self.scheduleCopyReady == true)
        if not copyClean then
            self.copyScheduleBtn.tooltip = "Save Hours before copying this rota."
        elseif copyCount == 0 then
            self.copyScheduleBtn.tooltip = "No other residents at this base."
        else
            self.copyScheduleBtn.tooltip = "Copy this resident's saved hours to everyone, one role or one other resident."
        end
    end
    -- Role picker follows the selected resident's stored preference, but only
    -- while the player has not moved it (see CrewView:syncCrewPicker).
    if resident then
        local pref = KnoxOrderCatalog.normalizeBasePreference ~= nil
            and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
            or duty.jobPreference
        local role = KnoxOrderCatalog.roleForPreference ~= nil
            and KnoxOrderCatalog.roleForPreference(duty.jobPreference) or nil
        role = role or "auto"
        self:syncCrewPicker(self.jobPicker, "jobPicker", BASE_JOB_CHOICES, pref, id)
        self:syncCrewPicker(self.rolePicker, "rolePicker", BASE_ROLE_CHOICES, role, id)
        self.pickerResidentId = id
    end
    -- The faction cycler names the group the selected person is actually in.
    if self.factionBtn ~= nil then
        local affiliation = id ~= nil and KnoxPersistence.getSurvivorAffiliation ~= nil
            and KnoxPersistence.getSurvivorAffiliation(id) or nil
        local factionId = affiliation ~= nil and affiliation.factionId or nil
        local faction = factionId ~= nil and KnoxPersistence.getFaction ~= nil
            and KnoxPersistence.getFaction(factionId) or nil
        self.factionBtn:setTitle("Faction: "
            .. tostring(faction ~= nil and faction.name or "none"))
    end
    self:refreshGuardOverrideControl(id, resident)
    if self.kitStatus ~= nil then
        local kitText
        if id == nil then
            kitText = "Kit: no resident selected."
        elseif not resident then
            kitText = "Kit: base residents only."
        else
            kitText = CrewView.kitStatusFor(duty,
                KnoxSurvivorRuntime.getCharacter(id), base)
        end
        self.kitStatus.knoxFullText = kitText
    end
    if self.partyList ~= nil and self.prefTable ~= nil then self:layoutPage() end
end

function CrewView:onCrewPriorityCell(button)
    local group = button ~= nil and button.knoxGroup or nil
    if group == nil then return end
    local residentId = self:selectedCrewId()
    if residentId == nil then return end
    local map = KnoxPersistence.getWorkPreferences ~= nil
        and KnoxPersistence.getWorkPreferences(residentId) or {}
    if type(map) ~= "table" then map = {} end
    local current = map[group] or "normal"
    self:applyCrewPriority(group, PRIORITY_STATE_NEXT[current] or "high")
end

-- One writer for a preference. A table cell names the state it sets, so this
-- path takes the state rather than cycling to it.
function CrewView:applyCrewPriority(group, state)
    local residentId = self:selectedCrewId()
    if group == nil or residentId == nil then return end
    if state ~= "high" and state ~= "normal" and state ~= "low"
        and state ~= "disabled" then return end
    local map = KnoxPersistence.getWorkPreferences ~= nil
        and KnoxPersistence.getWorkPreferences(residentId) or {}
    if type(map) ~= "table" then map = {} end
    if state == "normal" then map[group] = nil else map[group] = state end
    local any = false
    for _ in pairs(map) do any = true; break end
    local service = rawget(_G, "KnoxCompanionService")
    local player, base = self:schedulePlayerAndBase()
    local ok = crewRequest("Work preference", function()
        if player == nil then return false, "invalid_player" end
        if base == nil then return false, "no_base" end
        if service == nil or service.setBaseWorkPreferences == nil then return false, "service_unavailable" end
        return service.setBaseWorkPreferences(
            player, residentId, any and map or nil, base.id
        )
    end)
    if ok == true then
        KnoxActivityFeed.event("Base work preference saved.")
        self:populate(self.playerNum or 0)
    end
end

function CrewView:onResetPriorities()
    local player, base = self:schedulePlayerAndBase()
    local residentId = self:selectedCrewId()
    if player == nil or base == nil or residentId == nil then return end
    local service = rawget(_G, "KnoxCompanionService")
    local ok = crewRequest("Reset work preferences", function()
        if service == nil or service.setBaseWorkPreferences == nil then return false, "service_unavailable" end
        return service.setBaseWorkPreferences(player, residentId, nil, base.id)
    end)
    if ok == true then
        KnoxActivityFeed.event("Work preferences reset to Normal.")
        self:populate(self.playerNum or 0)
    end
end

function CrewView:onSelectTool(button)
    local tool = button ~= nil and button.knoxTool or nil
    if SCHEDULE_COLORS[tool] == nil then return end
    self.scheduleTool = tool
    self:paintCrewDetail()
end

function CrewView:paintScheduleBlock(button, residentId, tool)
    local index = button ~= nil and tonumber(button.knoxBlock) or nil
    local block = index ~= nil and KnoxOrderCatalog.scheduleBlocks[index] or nil
    if block == nil then return end
    residentId = residentId or self:selectedCrewId()
    if residentId == nil or self:selectedCrewId() ~= residentId then return end
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil then return end
    tool = tool or self.scheduleTool
    if SCHEDULE_COLORS[tool] == nil then tool = "sleep" end
    KnoxOrderCatalog.setScheduleBlock(draft, index, tool)
    self:paintCrewDetail()
end

function CrewView:onPaintBlock(button)
    self:paintScheduleBlock(button)
end

function CrewView:paintPresetHours(hours)
    local residentId = self:selectedCrewId()
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil or type(hours) ~= "table" then return end
    for hour = 1, 24 do draft[hour] = hours[hour] end
    self:paintCrewDetail()
end

function CrewView:onPresetColony()
    local rota = KnoxPersistence.defaultDutySchedule ~= nil
        and KnoxPersistence.defaultDutySchedule() or nil
    local hours = KnoxPersistence.dutyWindowsToHours ~= nil
        and KnoxPersistence.dutyWindowsToHours(rota) or nil
    if hours == nil then return end
    self:paintPresetHours(hours)
end

function CrewView:onPresetNight()
    -- Night shift on four-hour boundaries so every block stays legible.
    local hours = KnoxOrderCatalog.scheduleHoursFromBlocks({
        "work", "sleep", "sleep", "anything", "recreation", "work",
    })
    if hours == nil then return end
    self:paintPresetHours(hours)
end

function CrewView:onPresetRole()
    -- Use the role currently shown in the picker, not the last saved duty, so
    -- previewing a role's hours cannot silently describe a different job.
    local roleChoice = BASE_ROLE_CHOICES[self.rolePicker.selected or 1]
    local preference = roleChoice ~= nil and roleChoice.value or nil
    if preference == nil or preference == "auto" then
        local choice = BASE_JOB_CHOICES[self.jobPicker.selected or 1]
        preference = choice ~= nil and choice.value or nil
    end
    local hours = preference ~= nil and KnoxOrderCatalog.roleScheduleHours ~= nil
        and KnoxOrderCatalog.roleScheduleHours(preference) or nil
    local label = KnoxOrderCatalog.label(preference or "auto", "Automatic")
    if hours == nil then
        KnoxActivityFeed.event("No role hours for " .. string.lower(label) .. ".")
        return
    end
    -- This changes only the unsaved draft. The existing Save Hours action is
    -- still the one writer, so a custom schedule is never replaced silently.
    self:paintPresetHours(hours)
    KnoxActivityFeed.event("Role hours loaded for " .. string.lower(label) .. ".")
end

function CrewView:onPresetClear()
    local hours = {}
    for hour = 1, 24 do hours[hour] = "anything" end
    self:paintPresetHours(hours)
end

function CrewView:onGuardTonight()
    local player, base = self:schedulePlayerAndBase()
    local residentId = self:selectedCrewId()
    if player == nil or base == nil or residentId == nil then return end
    local active = KnoxPersistence.getDutyScheduleOverride ~= nil
        and KnoxPersistence.getDutyScheduleOverride(residentId) or nil
    local hourNow = currentScheduleHour()
    local window = hourNow ~= nil and KnoxOrderCatalog.scheduleBlockWindow ~= nil
        and KnoxOrderCatalog.scheduleBlockWindow(hourNow) or nil
    if active == nil and (window == nil
        or (window.key ~= "night" and window.key ~= "dusk")) then
        KnoxActivityFeed.event("Guard Tonight is available during the Night and Dusk blocks.")
        return
    end
    local service = rawget(_G, "KnoxCompanionService")
    local clearing = active ~= nil
    local assignment = "guard"
    if clearing then assignment = nil end
    local ok = crewRequest(clearing and "Clear guard override" or "Guard tonight", function()
        if service == nil or service.setBaseDutyScheduleOverride == nil then
            return false, "service_unavailable"
        end
        return service.setBaseDutyScheduleOverride(
            player, residentId, assignment, base.id
        )
    end)
    if ok == true then
        KnoxActivityFeed.event(clearing
            and "Temporary schedule override cleared."
            or "Guard tonight: temporary until the next block.")
        self:paintCrewDetail()
    end
end

-- The temporary guard block is only legal during Dusk and Night. A disabled
-- button with the reason in a tooltip is the one control nobody hovers, so the
-- state is named on the face of the button and the rule lives here, where it can
-- be held without a window.
function CrewView.guardControl(guardBlock)
    local available = guardBlock == true
    return {
        available = available,
        title = available and "Guard Tonight" or "Guard: night only",
        tooltip = available
            and "Take the current night or dusk block only. Expires at the next block and leaves saved hours unchanged."
            or "Available during the Night and Dusk blocks only. Saved hours still apply.",
    }
end

function CrewView:refreshGuardOverrideControl(id, resident)
    local button = self.guardOverrideBtn
    if button == nil then return end
    local active = nil
    if resident == true and id ~= nil
        and KnoxPersistence.getDutyScheduleOverride ~= nil then
        active = KnoxPersistence.getDutyScheduleOverride(id)
    end
    -- A block boundary can pass while Crew is open. Repaint only on an edge,
    -- so the status line and the button cannot disagree with the reader.
    local wasActive = self.guardOverrideStatusActive
    local activeNow = active ~= nil
    self.guardOverrideStatusActive = activeNow
    if resident == true and wasActive ~= nil and wasActive ~= activeNow then
        self:paintCrewDetail()
        return
    end
    if active ~= nil then
        local label = SCHEDULE_ASSIGNMENT_LABELS[active.assignment] or "Temporary"
        button:setTitle("Clear Override")
        button.tooltip = "Clear the temporary " .. string.lower(label)
            .. " and return to the saved hours."
        button:setEnable(resident == true)
        return
    end
    local hourNow = currentScheduleHour()
    local window = hourNow ~= nil and KnoxOrderCatalog.scheduleBlockWindow ~= nil
        and KnoxOrderCatalog.scheduleBlockWindow(hourNow) or nil
    local guardBlock = window ~= nil
        and (window.key == "night" or window.key == "dusk")
    local guard = CrewView.guardControl(guardBlock == true)
    button:setTitle(guard.title)
    button.tooltip = guard.tooltip
    button:setEnable(resident == true and guard.available == true)
end

function CrewView:onSaveSchedule()
    local player, base = self:schedulePlayerAndBase()
    if player == nil or base == nil then return end
    local residentId = self:selectedCrewId()
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil then return end
    -- All-anything compresses to nil: back to the default rota, unsaved.
    local windows = KnoxPersistence.hoursToDutyWindows ~= nil
        and KnoxPersistence.hoursToDutyWindows(draft) or nil
    local service = rawget(_G, "KnoxCompanionService")
    local ok = crewRequest("Save schedule", function()
        if service == nil or service.setBaseDutySchedule == nil then return false, "service_unavailable" end
        return service.setBaseDutySchedule(player, residentId, windows, base.id)
    end)
    if ok == true then
        KnoxActivityFeed.event("Schedule saved.")
        -- Drop the draft so the strip re-seeds from saved truth: display
        -- can never drift from what the scheduler honors.
        if self.scheduleDrafts ~= nil then
            self.scheduleDrafts[residentId] = nil
        end
        self:paintCrewDetail()
    end
end
function CrewView:prerender()
    ISPanelJoypad.prerender(self)
    local id = self:selectedCrewId()
    -- Selection changes must not wait for the expensive two-second roster refresh.
    if id ~= self.detailResidentId then self:paintCrewDetail() end
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
    local resident = duty ~= nil and duty.mode == "base" and base ~= nil and duty.baseId == base.id
    self.viewBtn:setEnable(id ~= nil)
    self.inventoryBtn:setEnable(id ~= nil)
    self.joinPartyBtn:setEnable(resident)
    self.jobPicker:setEnabled(resident)
    self.setJobBtn:setEnable(resident)
    self.saveScheduleBtn:setEnable(resident)
    self.colonyPresetBtn:setEnable(resident)
    self.nightPresetBtn:setEnable(resident)
    if self.roleHoursBtn ~= nil then self.roleHoursBtn:setEnable(resident) end
    if self.copyPicker ~= nil then self.copyPicker:setEnabled(resident == true and #(self.copyScopes or {}) > 0) end
    if self.copyScheduleBtn ~= nil then self.copyScheduleBtn:setEnable(self.scheduleCopyReady == true) end
    self.clearPresetBtn:setEnable(resident)
    self.resetPrioritiesBtn:setEnable(resident)
    self:refreshGuardOverrideControl(id, resident)
end
function CrewView:onJoypadDown(b,jd) if b==Joypad.AButton and ((self.partyList.selected or 0)>0 or (self.resList.selected or 0)>0) then self:onView() end; ISPanelJoypad.onJoypadDown(self,b,jd) end
function CrewView:new(x,y,w,h)
    local o=ISPanelJoypad.new(self,x,y,w,h)
    o:noBackground()
    return o
end

-- Window.refreshContent calls this after it has restored stable row identities.
-- Keep the crew-specific source/selection cursor in sync before repainting;
-- otherwise the rows can point at one resident while the controls still show
-- the first resident selected during populate().
function CrewView:onNotebookSelectionRestored(previousSource)
    local id
    if previousSource == "party" then
        id = self.partyIds ~= nil and self.partyIds[self.partyList.selected or 0] or nil
    elseif previousSource == "residents" then
        id = self.residentIds ~= nil and self.residentIds[self.resList.selected or 0] or nil
    end
    self:restoreCrewSelection(id, previousSource)
    self:paintCrewDetail()
end

-- Missions panel: away teams, durable survival orders, and unloaded crew.
-- Survival orders placed from the Crew tab or radial land here with
-- callbacks: back to the party, back to a base of your choice, or resume
-- normal duty. Teams remain display-only.
local MissionComposer = require "KS_MissionComposer"
local MissionsView = ISPanelJoypad:derive("KnoxNotebookMissionsView")
function MissionsView:initialise() ISPanelJoypad.initialise(self) end
function MissionsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2-BUTTON_HGT-UI_BORDER_SPACING)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.Small; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    self.toPartyBtn=ISButton:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Party",self,MissionsView.onSupplyToParty); self.toPartyBtn:initialise(); UILayout.tintSheetButton(self.toPartyBtn); self:addChild(self.toPartyBtn)
    self.toPartyBtn.tooltip = "Send the selected mission's supplies to the party, not to the base."
    self.toBaseBtn=ISButton:new(self.toPartyBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Base",self,MissionsView.onSupplyToBase); self.toBaseBtn:initialise(); UILayout.tintSheetButton(self.toBaseBtn); self:addChild(self.toBaseBtn)
    self.toBaseBtn.tooltip = "Send the selected mission's supplies to this base's storage."
    self.resumeBtn=ISButton:new(self.toBaseBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,120,BUTTON_HGT,"Resume Duty",self,MissionsView.onSupplyResume); self.resumeBtn:initialise(); UILayout.tintSheetButton(self.resumeBtn); self:addChild(self.resumeBtn)
    self.resumeBtn.tooltip = "Return this survivor to normal duty once their mission is done."
    -- The chosen crew is confirmed here; the existing map owns placement.
    local dispatchX=math.min(self.resumeBtn:getRight()+6, self.width-UI_BORDER_SPACING-116)
    self.dispatchBtn=ISButton:new(dispatchX,self.list:getBottom()+UI_BORDER_SPACING,116,BUTTON_HGT,"Confirm crew - choose on map",self,MissionsView.onDispatch); self.dispatchBtn:initialise(); UILayout.tintSheetButton(self.dispatchBtn); self:addChild(self.dispatchBtn)
    self.dispatchBtn.tooltip = "Choose any number of free residents, confirm, then right-click the world map to send them."
    UILayout.tintPrimary(self.dispatchBtn)
    -- One line that names what the buttons will do with the current selection,
    -- or why they have nothing to act on. Without it a page of buttons asks the
    -- player to guess.
    self.reasonLabel=ISLabel:new(UI_BORDER_SPACING,UI_BORDER_SPACING,BUTTON_HGT,"",
        sheetTheme.dim[1],sheetTheme.dim[2],sheetTheme.dim[3],1,UIFont.Small,true)
    self.reasonLabel:initialise(); self:addChild(self.reasonLabel)
    MissionComposer.create(self,UILayout,BUTTON_HGT)
    self:layoutFooter()
end

-- Footer placement comes from the shared rule instead of each x being derived
-- from the previous button's right edge, which overlapped on a narrow page.
function MissionsView:layoutFooter()
    local available=math.max(1,self.width-UI_BORDER_SPACING*2)
    local footer=UILayout.footerPlacements(
        {self.toPartyBtn,self.toBaseBtn,self.resumeBtn}, available,
        {spacing=6,buttonHeight=BUTTON_HGT,
         measure=function(text) return getTextManager():MeasureStringX(UIFont.Small,text) end})
    -- The list is sized to its rows, so the page keeps the only scroller; the
    -- footer follows the content instead of being pinned over it.
    local fontH=getTextManager():getFontHeight(UIFont.Small)
    self.list.itemheight=math.max(BUTTON_HGT,fontH*2+8)
    local composeBottom=MissionComposer.layout(self,UI_BORDER_SPACING,BUTTON_HGT)
    self.dispatchBtn:setX(UI_BORDER_SPACING); self.dispatchBtn:setY(composeBottom)
    self.dispatchBtn:setWidth(math.min(available,getTextManager():MeasureStringX(UIFont.Small,self.dispatchBtn.title)+24))
    self.list:setY(self.dispatchBtn:getBottom()+UI_BORDER_SPACING)
    self.list:setWidth(available)
    self.list:setHeight(UILayout.stackHeight(#(self.list.items or {}),
        self.list.itemheight, 3, 8))
    local top=math.max(self.list:getBottom()+6, UI_BORDER_SPACING+FONT_HGT_SMALL*2)
    self.reasonLabel:setY(top)
    top=top+FONT_HGT_SMALL+4
    for _,placement in ipairs(footer.placements) do
        local control=placement.control
        control:setX(UI_BORDER_SPACING+placement.x)
        control:setY(top+placement.y)
        control:setWidth(placement.width)
        control:setHeight(placement.height)
    end
    -- The footer is content now, not a pinned strip: the page scroll extent has
    -- to include it or the last row of buttons sits below the scroll limit.
    self.knoxContentHeight=top+footer.height+UI_BORDER_SPACING
end

function MissionsView:refreshMissionReason()
    local rows=self.list~=nil and #self.list.items or 0
    local selected=self.list~=nil and tonumber(self.list.selected) or nil
    local row=selected~=nil and self.list.items[selected] or nil
    local id=row~=nil and (row.item or row.knoxId) or nil
    local supply=id~=nil and string.sub(tostring(id),1,7)=="supply:"
    local reason
    if rows==0 then
        -- The body already draws the empty-state copy, so this line answers the
        -- other question: why the remaining three actions are off.
        reason="No active supply run selected."
    elseif row==nil then
        reason="Select a supply run to change its duty or destination."
    elseif supply then
        reason="This supply run can go to the party, to the base, or end its duty."
    else
        reason="The crew searches until full, then regroups and returns together."
    end
    self.reasonLabel.name=trimText(UIFont.Small, reason, self.width-UI_BORDER_SPACING*2)
end

-- A mission is a card, not a sentence: a title line, a quiet detail line and a
-- state chip on the right. The row text still carries the raw facts, so the card
-- adds no new data and states none of it twice.
function MissionsView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local theme=UILayout.sheetTheme()
    local manager=getTextManager()
    local fontH=manager:getFontHeight(UIFont.Small)
    local width=self:getWidth()
    local chip=item.knoxChip
    local chipW=chip~=nil and (manager:MeasureStringX(UIFont.Small,chip)+10) or 0
    local text=tostring(item.text or "")
    local split=string.find(text," | ",1,true)
    local title,detail=text,""
    if split~=nil then
        title=string.sub(text,1,split-1)
        detail=string.gsub(string.sub(text,split+3)," | "," - ")
    end
    local inert=item.knoxKey=="none" or item.knoxKey=="empty"
    local tone=inert and theme.muted or theme.bone
    self:drawRect(0,y+self.itemheight-1,width,1,0.32,
        theme.border[1],theme.border[2],theme.border[3])
    if self.selected==item.index and not inert then
        self:drawRect(0,y,2,math.max(1,self.itemheight-1),0.95,
            theme.amber[1],theme.amber[2],theme.amber[3])
    end
    local measure=function(value) return manager:MeasureStringX(UIFont.Small,value) end
    self:drawText(UILayout.fitText(UIFont.Small,title,math.max(1,width-20-chipW),measure),
        10,y+2,tone[1],tone[2],tone[3],0.95,UIFont.Small)
    if detail~="" then
        self:drawText(UILayout.fitText(UIFont.Small,detail,math.max(1,width-20-chipW),measure),
            10,y+2+fontH+2,theme.dim[1],theme.dim[2],theme.dim[3],0.95,UIFont.Small)
    end
    if chip~=nil then
        self:drawText(chip,width-10-manager:MeasureStringX(UIFont.Small,chip),y+2,
            theme.muted[1],theme.muted[2],theme.muted[3],0.95,UIFont.Small)
    end
    return y+self.itemheight
end

-- Empty is a state, not a blank field: the copy is wrapped by the shared rule and
-- the one primary action (Dispatch) is already in the footer.
function MissionsView:render()
    ISPanelJoypad.render(self)
    if self.empty~=true then return end
    local theme=UILayout.sheetTheme()
    local available=math.max(1,self.width-UI_BORDER_SPACING*2)
    local state=UILayout.emptyState(
        "No trips out. Select a purpose and crew above, then confirm to choose their destination on the world map.",
        "Dispatch...",available,
        {measure=function(value) return getTextManager():MeasureStringX(UIFont.Small,value) end})
    local fontH=getTextManager():getFontHeight(UIFont.Small)
    local y=self.list:getY()+4
    for _,line in ipairs(state.lines or {}) do
        self:drawText(line,UI_BORDER_SPACING,y,
            theme.bone[1],theme.bone[2],theme.bone[3],0.95,UIFont.Small)
        y=y+fontH+3
    end
end
function MissionsView:populate(playerNum)
    self.playerNum = playerNum
    MissionComposer.refresh(self)
    self.list:clear()
    local player = getSpecificPlayer(playerNum)
    local ownerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if ownerId == nil then
        self.empty=true
        self.list:setVisible(false)
        self:layoutFooter()
        self:refreshMissionReason()
        return
    end
    local teams = KnoxPersistence.getAwayTeams and KnoxPersistence.getAwayTeams() or {}
    local now = 0
    local gameTime = rawget(_G, "getGameTime")
    if gameTime ~= nil then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) ~= nil then now = tonumber(value) end
    end
    local count = 0
    local finished = {}
    for id, team in pairs(teams) do
        if team ~= nil and team.ownerKind == "player" and team.ownerId == ownerId then
            if team.state == "complete" or team.state == "blocked" then
                if type(team.result) == "table" then
                    finished[#finished + 1] = {
                        id = id,
                        team = team,
                        atHours = tonumber(team.completedAtHours
                            or team.blockedAtHours) or 0,
                    }
                end
            else
                count = count + 1
                local progress = KnoxPersistence.getAwayTeamProgress ~= nil
                    and KnoxPersistence.getAwayTeamProgress(id, now) or team
                local remaining = tonumber(progress.remainingHours) or 0
                local text = KnoxAwayTeamExecutor.missionLabel(progress)
                    .. " | " .. tostring(progress.statusLabel or progress.state or "unknown")
                    .. " | " .. tostring(#(progress.memberIds or {})) .. " member(s)"
                    .. " | " .. tostring(progress.destination and progress.destination.label or "unknown")
                if progress.state == "outbound" then
                    text = text .. " | " .. string.format("%.1fh remaining", remaining)
                end
                local row=addRow(self.list,id,text)
                row.knoxChip=tostring(progress.collectedItems or 0) .. " collected"
            end
        end
    end
    self.empty = (#self.list.items == 0)
    -- Durable survival orders across every home: kind, time left, callbacks.
    for _, base in ipairs(notebookBases(ownerId)) do
        for _, id in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
            local order = KnoxPersistence.getBaseSupplyOrder ~= nil
                and KnoxPersistence.getBaseSupplyOrder(id) or nil
            if order ~= nil then
                local remaining = math.max(0, (tonumber(order.expiresAtHours) or now) - now)
                local name = claimantName(id)
                local kind = KnoxOrderCatalog ~= nil and KnoxOrderCatalog.label ~= nil
                    and KnoxOrderCatalog.label(order.kind, order.kind) or tostring(order.kind)
                local row=addRow(self.list, "supply:" .. tostring(id),
                    name .. " | Supply run: " .. tostring(kind)
                    .. " | " .. tostring(base.name or base.id)
                    .. " | " .. string.format("%.1fh left", remaining))
                row.knoxChip="supply"
                count = count + 1
            end
        end
    end
    for _, id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        if KnoxPersistence.isSurvivorAlive(id) and KnoxSurvivorRuntime.getCharacter(id) == nil then
            local aff = KnoxPersistence.getSurvivorAffiliation(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            if aff.kind == "player" and aff.ownerId == ownerId and duty.awayTeamId == nil then
                local snapshot = KnoxSurvivorViewModel.getSurvivor(id, playerNum)
                if snapshot ~= nil then
                    local row=addRow(self.list,id, snapshot.displayName .. " | "
                        .. snapshot.roleLabel .. " | " .. snapshot.activity)
                    row.knoxChip="ready"
                end
            end
        end
    end
    -- Newest outcomes last, capped so old missions cannot crowd the roster.
    -- The same formatter feeds the one-shot activity notice; a blocked trip is
    -- never shown as a success.
    local executor = rawget(_G, "KnoxAwayTeamExecutor")
    table.sort(finished, function(first, second)
        return first.atHours > second.atHours
    end)
    for index = 1, math.min(3, #finished) do
        local entry = finished[index]
        local text = executor ~= nil and executor.resultSummary ~= nil
            and executor.resultSummary(entry.team) or nil
        if text ~= nil then
            local row=addRow(self.list, "result:" .. tostring(entry.id), text)
            row.knoxChip="outcome"
        end
    end
    self.empty = (#self.list.items == 0)
    self.list:setVisible(not self.empty)
    self:layoutFooter()
    self:refreshMissionReason()
end
function MissionsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

function MissionsView:missionNow()
    local gameTime = rawget(_G, "getGameTime")
    if gameTime ~= nil then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end
    return 0
end

function MissionsView:selectedSupplyId()
    local index = self.list.selected or 0
    local row = index > 0 and self.list.items[index] or nil
    local key = row ~= nil and tostring(row.knoxKey or "") or ""
    return string.match(key, "^supply:(.+)$")
end

function MissionsView:onSupplyToParty()
    local id = self:selectedSupplyId()
    local player = getSpecificPlayer(self.playerNum or 0)
    if id == nil or player == nil then return end
    local ok = crewRequest("Join party", KnoxCompanionService.recallToParty, player, id)
    if ok then KnoxActivityFeed.event("Recalled to the party.") end
    if ok then self:populate(self.playerNum) end
end

function MissionsView:onSupplyResume()
    local id = self:selectedSupplyId()
    local player = getSpecificPlayer(self.playerNum or 0)
    if id == nil or player == nil then return end
    local ok = crewRequest("Resume duty", KnoxCompanionService.clearBaseSupplyOrder, player, id)
    if ok then KnoxActivityFeed.event("Supply order cleared. Normal duty requested.") end
    if ok then self:populate(self.playerNum) end
end

function MissionsView:onSupplyToBase()
    local id = self:selectedSupplyId()
    local player = getSpecificPlayer(self.playerNum or 0)
    if id == nil or player == nil then return end
    local playerNum = self.playerNum or 0
    local pid = KnoxPersistence.ensurePlayerId(player)
    local bases = notebookBases(pid)
    local function send(baseId)
        if baseId == nil then return end
        local service = rawget(_G, "KnoxCompanionService")
        local ok = false
        if service ~= nil and service.transferBaseResident ~= nil then
            ok = crewRequest("Return to base", service.transferBaseResident, player, id, baseId)
        end
        local base = KnoxPersistence.getBase(baseId)
        if ok then KnoxActivityFeed.event("Called back to " .. tostring(base ~= nil and base.name or baseId) .. ".") end
        if ok then self:populate(self.playerNum) end
    end
    local picker = rawget(_G, "KnoxBasePicker")
    if #bases > 1 and picker ~= nil and picker.choose ~= nil then
        picker.choose(playerNum, "Call back to which base?", bases, send)
        return
    end
    send(bases[1] ~= nil and bases[1].id or nil)
end

function MissionsView:onDispatch()
    if MissionComposer.confirm(self) then Notebook.close(self.playerNum or 0) end
end

function MissionsView:prerender()
    ISPanelJoypad.prerender(self)
    local id = self:selectedSupplyId()
    if self.toPartyBtn then self.toPartyBtn:setEnable(id ~= nil) end
    if self.toBaseBtn then self.toBaseBtn:setEnable(id ~= nil) end
    if self.resumeBtn then self.resumeBtn:setEnable(id ~= nil) end
    if self.dispatchBtn then
        self.dispatchBtn:setEnable(self.missionBaseId ~= nil and #MissionComposer.members(self)>0)
    end
end

-- World panel: everyone else. Non-player factions on top with standing and
-- home; the selected faction's members below with roles (leader, follower,
-- work role, drifter). Unaffiliated known survivors group under Drifters.
-- Read-only by design: standing moves through encounters, not buttons.
local WORLD_JOB_ROLES = {
    auto = "Worker", guard = "Guard", patrol = "Patrol", farming = "Farmer",
    cooking = "Cook", woodwork = "Woodcutter", barricade = "Builder",
    hauling = "Hauler", repair = "Repairer", rest = "Resting",
    scavenger = "Scavenger", cook = "Cook", farmer = "Farmer",
    builder = "Builder", medic = "Medic", mechanic = "Mechanic",
    quartermaster = "Quartermaster", runner = "Runner",
}

local WorldView = ISPanelJoypad:derive("KnoxNotebookWorldView")
function WorldView:initialise() ISPanelJoypad.initialise(self) end
function WorldView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*4)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.Small; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    local cardY = self.list:getBottom() + UI_BORDER_SPACING
    self.cardPortrait=ISImage:new(UI_BORDER_SPACING,cardY,44,44,nil); self.cardPortrait:initialise(); self:addChild(self.cardPortrait)
    self.cardLine1=ISLabel:new(UI_BORDER_SPACING+52,cardY,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.cardLine1:initialise(); self:addChild(self.cardLine1)
    self.cardLine2=ISLabel:new(UI_BORDER_SPACING+52,cardY+FONT_HGT_SMALL+4,BUTTON_HGT,"",sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true); self.cardLine2:initialise(); self:addChild(self.cardLine2)
    self.memberList=ISScrollingListBox:new(UI_BORDER_SPACING,cardY+52,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.memberList:initialise(); self.memberList:instantiate(); self.memberList.itemheight=BUTTON_HGT; self.memberList.font=UIFont.Small; self.memberList.doDrawItem=self.drawEntry; self.memberList.drawBorder=true; self:addChild(self.memberList)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.memberList:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,WorldView.onView); self.viewBtn:initialise(); UILayout.tintSheetButton(self.viewBtn); self:addChild(self.viewBtn)
    -- A greyed control owes the player a sentence. This line says why View Card
    -- is off, and what it will do once a member is selected.
    self.viewReason=ISLabel:new(UI_BORDER_SPACING,self.viewBtn:getBottom()+4,BUTTON_HGT,
        "Select a member above to open their card.",
        sheetTheme.muted[1],sheetTheme.muted[2],sheetTheme.muted[3],1,UIFont.Small,true)
    self.viewReason:initialise(); self:addChild(self.viewReason)
    self:layoutPage()
end
function WorldView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; drawListRow(self,y,item); drawListText(self,y,item,a)
    local standing = item.knoxStanding
    if standing ~= nil then
        -- One bar per faction row, drawn from the same read-out the card uses.
        -- A faction with no diplomacy record keeps a hollow bar rather than a
        -- fabricated neutral fill.
        local barW = 64
        local bx = self:getWidth() - barW - 12
        local by = y + math.max(2, math.floor((self.itemheight - 7) / 2))
        self:drawRect(bx, by, barW, 6, 0.45, 0.02, 0.02, 0.02)
        if standing.known == true then
            local r, g, b = 0.70, 0.68, 0.62
            if standing.tone == "hostile" then
                r, g, b = 0.86, 0.34, 0.30
            elseif standing.tone == "friendly" then
                r, g, b = 0.48, 0.56, 0.38
            end
            self:drawRect(bx, by, math.max(1, barW * (tonumber(standing.fill) or 0.5)),
                6, 0.9, r, g, b)
        end
        -- A hollow bar alone can read as "the value is zero". The word says the
        -- faction has no diplomacy record instead of implying a measurement.
        if standing.known ~= true then
            local chip = "no contact"
            local manager = getTextManager()
            local chipW = manager:MeasureStringX(UIFont.Small, chip)
            local tone = sheetTheme.dim
            self:drawText(chip, math.max(4, bx - chipW - 6),
                y + math.max(2, math.floor((self.itemheight
                    - manager:getFontHeight(UIFont.Small)) / 2)),
                tone[1], tone[2], tone[3], 0.9, UIFont.Small)
        end
    end
    return y+self.itemheight
end

-- Headcount that matters at a glance: total members, settled residents,
-- and watch posts (guard/patrol roles) among them.
function WorldView:factionStats(faction)
    local members, residents, guards = 0, 0, 0
    for _, memberId in ipairs(faction ~= nil and faction.memberIds or {}) do
        members = members + 1
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(memberId) or nil
        if type(duty) == "table" and duty.mode == "base" then
            residents = residents + 1
            local pref = tostring(duty.jobPreference or "")
            if pref == "guard" or pref == "patrol" then guards = guards + 1 end
        end
    end
    return members, residents, guards
end

function WorldView:leaderPortrait(leaderId, playerNum)
    if leaderId == nil then return nil end
    local viewModel = rawget(_G, "KnoxSurvivorViewModel")
    if viewModel == nil or viewModel.getSurvivor == nil or getTexture == nil then
        return nil
    end
    local ok, view = pcall(function() return viewModel.getSurvivor(leaderId, playerNum) end)
    if not ok or type(view) ~= "table" or tostring(view.sex or "") == "" then return nil end
    local okTex, texture = pcall(function()
        return getTexture("media/ui/defense/" .. tostring(view.sex) .. "_base.png")
    end)
    if okTex and texture ~= nil then return texture end
    return nil
end

local function worldAgeLabel(hours, now)
    local age = math.max(0, (tonumber(now) or 0) - (tonumber(hours) or 0))
    if age < 1 then return "under an hour ago" end
    if age < 24 then return tostring(math.floor(age)) .. "h ago" end
    return tostring(math.floor(age / 24)) .. "d ago"
end

-- Brief conflict history: completed raids (both directions), live raid
-- events touching the faction, plus the last disposition change and its
-- reason. Newest first, capped at three.
function WorldView:factionHistory(faction, now)
    local entries = {}
    if faction ~= nil and KnoxPersistence.getRaidHistory ~= nil then
        for _, raid in ipairs(KnoxPersistence.getRaidHistory()) do
            local involved = tostring(raid.sourceFactionId or "") == tostring(faction.id)
            if not involved and tostring(raid.targetBaseId or "") ~= "" then
                local target = KnoxPersistence.getBase ~= nil
                    and KnoxPersistence.getBase(raid.targetBaseId) or nil
                involved = target ~= nil and target.ownerKind == "faction"
                    and tostring(target.ownerId or "") == tostring(faction.id)
            end
            if involved then
                local outward = tostring(raid.sourceFactionId or "") == tostring(faction.id)
                local other = outward and raid.targetName or raid.sourceName
                if tostring(other or "") == "" then
                    other = outward
                        and self:displayName("base", raid.targetBaseId, "an unnamed place")
                        or self:displayName("faction", raid.sourceFactionId, "an unknown group")
                end
                entries[#entries + 1] = {
                    at = tonumber(raid.atHours) or 0,
                    text = (outward and "Raided " or "Raid on ")
                        .. tostring(other or "an unknown place")
                        .. " - " .. tostring(raid.outcome or "unknown"),
                }
            end
        end
    end
    local events = rawget(_G, "KnoxEvents")
    if events ~= nil and events.activeIds ~= nil and events.get ~= nil and faction ~= nil then
        local okIds, ids = pcall(function() return events.activeIds() end)
        if okIds and type(ids) == "table" then
            for _, id in ipairs(ids) do
                local okEv, event = pcall(function() return events.get(id) end)
                if okEv and type(event) == "table" then
                    local involves = tostring(event.sourceFactionId or "") == tostring(faction.id)
                    if not involves and event.targetBaseId ~= nil
                        and KnoxPersistence.getBase ~= nil then
                        local target = KnoxPersistence.getBase(event.targetBaseId)
                        involves = target ~= nil and target.ownerKind == "faction"
                            and tostring(target.ownerId or "") == tostring(faction.id)
                    end
                    if involves then
                        -- A raid that has warned the player reads as a threat
                        -- with a cause and an ETA, not as a raw event phase -
                        -- and once it has ended, as what it cost instead of a
                        -- stale "arriving now" the warning stamp would give.
                        local warning = type(event.warning) == "table" and event.warning or nil
                        local aftermath = events.raidAftermathText ~= nil
                            and events.raidAftermathText(event, now) or nil
                        local threat = aftermath or (warning ~= nil and events.raidThreatText ~= nil
                            and events.raidThreatText(warning, now) or nil)
                        entries[#entries + 1] = {
                            at = tonumber(event.lastChangedAtHours) or 0,
                            text = threat or (tostring(event.kind or "event") .. " - "
                                .. tostring(event.phase or event.state or "ongoing")),
                        }
                    end
                end
            end
        end
    end
    if faction ~= nil and self.playerFaction ~= nil
        and KnoxPersistence.getFactionRelationship ~= nil then
        local saved = KnoxPersistence.getFactionRelationship(self.playerFaction.id, faction.id)
        if saved ~= nil then
            entries[#entries + 1] = {
                at = tonumber(saved.changedAtHours) or 0,
                text = "standing became " .. tostring(saved.disposition or "neutral")
                    .. (saved.reason ~= nil and " (" .. tostring(saved.reason) .. ")" or ""),
            }
        end
    end
    table.sort(entries, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local lines = {}
    for index = 1, math.min(3, #entries) do
        lines[#lines + 1] = entries[index].text .. " " .. worldAgeLabel(entries[index].at, now)
    end
    if #lines == 0 then return "No recorded conflicts" end
    return table.concat(lines, ", ")
end

function WorldView:memberRole(faction, memberId)
    if faction ~= nil and tostring(faction.leaderId or "") == tostring(memberId) then
        return "Leader"
    end
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(memberId) or nil
    local mode = type(duty) == "table" and tostring(duty.mode or "") or ""
    if mode == "companion" then return "Follower" end
    if mode == "away" then return "Away team" end
    if mode == "base" then
        local pref = duty.jobPreference
        if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeBasePreference ~= nil then
            pref = KnoxOrderCatalog.normalizeBasePreference(pref)
        end
        return WORLD_JOB_ROLES[tostring(pref or "auto")] or "Worker"
    end
    return "Drifter"
end

function WorldView:memberName(memberId)
    local identity = KnoxPersistence.getSurvivorIdentity(memberId) or {}
    local name = (tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    -- A raw internal id is not a name. A faction member the player has never
    -- met reads as unknown; the row still carries the id as its key, so the
    -- card, the portrait and every action keep working.
    if name == "" then name = "Unknown survivor" end
    return name
end

-- An internal id is never a name. Every row and detail line resolves an id
-- through whoever stores it; when no name exists the line says so instead of
-- printing the key a player cannot read.
function WorldView:displayName(kind, id, fallback)
    local value = id ~= nil and tostring(id) or ""
    if value == "" then return fallback end
    if kind == "base" then
        local base = KnoxPersistence.getBase ~= nil and KnoxPersistence.getBase(value) or nil
        local name = base ~= nil and tostring(base.name or "") or ""
        if name ~= "" then return name end
    elseif kind == "faction" then
        for _, faction in pairs(KnoxPersistence.getFactions() or {}) do
            if faction ~= nil and tostring(faction.id) == value then
                local name = tostring(faction.name or "")
                if name ~= "" then return name end
            end
        end
    elseif kind == "survivor" then
        return self:memberName(value)
    end
    return fallback
end

function WorldView:factionHome(faction)
    local base = faction.homeBaseId and KnoxPersistence.getBase(faction.homeBaseId) or nil
    local camp = KnoxPersistence.getFactionCamp ~= nil and KnoxPersistence.getFactionCamp(faction.id) or nil
    if base ~= nil then
        return "Base: " .. self:displayName("base", faction.homeBaseId, "unnamed base")
    end
    if camp ~= nil then
        local name = tostring(camp.name or "")
        return "Shelter: " .. (name ~= "" and name or "unnamed shelter")
    end
    return "No home yet"
end

-- Both lists are sized to their rows, and the page scroller carries the rest:
-- a long faction or member list must not create a second scrollbar inside the
-- first. Positions come from the measured content, not from creation order.
function WorldView:layoutPage()
    local spacing=UI_BORDER_SPACING
    local available=math.max(1,self.width-spacing*2)
    self.list:setX(spacing); self.list:setY(spacing); self.list:setWidth(available)
    self.list:setHeight(UILayout.stackHeight(#(self.list.items or {}),BUTTON_HGT,3,8))
    local cardY=self.list:getBottom()+6
    self.cardPortrait:setX(spacing); self.cardPortrait:setY(cardY)
    local cardWidth=math.max(1,available-52)
    local cardBottom=layoutPageFeedback(self,self.cardLine1,"worldCardFirstLines",
        self.cardLine1.knoxFullText or self.cardLine1.name,spacing+52,cardY,cardWidth)
    cardBottom=layoutPageFeedback(self,self.cardLine2,"worldCardSecondLines",
        self.cardLine2.knoxFullText or self.cardLine2.name,spacing+52,cardBottom+2,cardWidth)
    self.memberList:setX(spacing); self.memberList:setY(math.max(cardY+52,cardBottom+6))
    self.memberList:setWidth(available)
    self.memberList:setHeight(UILayout.stackHeight(#(self.memberList.items or {}),BUTTON_HGT,3,8))
    self.viewBtn:setX(spacing); self.viewBtn:setY(self.memberList:getBottom()+6)
    local bottom=layoutPageFeedback(self,self.viewReason,"worldViewReasonLines",
        self.viewReason.knoxFullText or self.viewReason.name,spacing,self.viewBtn:getBottom()+4,available)
    self.knoxContentHeight=bottom+spacing
end

-- A group the player has never met is not listed. The knowledge read is the
-- persistence owner's; a group with no real record stays out of the world list.
-- This only filters display: every simulation caller keeps the full list.
function WorldView.visibleFactions(factions, playerId)
    local visible = {}
    for _, faction in pairs(factions or {}) do
        if faction ~= nil and faction.kind ~= "player"
            and (playerId == nil or KnoxPersistence.factionKnownToPlayer == nil
                or KnoxPersistence.factionKnownToPlayer(playerId, faction.id) == true) then
            visible[#visible + 1] = faction
        end
    end
    return visible
end

function WorldView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear(); self.memberList:clear(); self.memberIds = {}
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local playerFaction = playerId ~= nil and KnoxPersistence.getPlayerFaction ~= nil
        and KnoxPersistence.getPlayerFaction(playerId) or nil
    -- Non-player factions first, then unaffiliated known survivors.
    local factions = WorldView.visibleFactions(KnoxPersistence.getFactions() or {}, playerId)
    table.sort(factions, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    local claimed = {}
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    for _, faction in ipairs(factions) do
        for _, memberId in ipairs(faction.memberIds or {}) do claimed[tostring(memberId)] = true end
        local standing = "neutral"
        local standingView = nil
        if playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
            local reputation = rawget(_G, "KnoxReputationView")
            if reputation ~= nil and reputation.faction ~= nil then
                standingView = reputation.faction(saved, faction.name)
            end
        end
        local members, residents, guards = self:factionStats(faction)
        local factionName = tostring(faction.name or "")
        local row = addRow(self.list, faction.id,
            (factionName ~= "" and factionName or "Unnamed faction")
            .. "  |  " .. (standingView ~= nil and standingView.shortLabel or standing)
            .. "  |  " .. tostring(members)
            .. " (" .. tostring(residents) .. " settled, " .. tostring(guards) .. " watch)"
            .. "  |  " .. self:factionHome(faction))
        row.knoxStanding = standingView
    end
    local drifters = {}
    for _, id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        local aff = KnoxPersistence.getSurvivorAffiliation ~= nil
            and KnoxPersistence.getSurvivorAffiliation(id) or {}
        if tostring(aff.kind or "") ~= "player" and claimed[tostring(id)] ~= true then
            local snap = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(id, playerNum) or nil
            if snap ~= nil then drifters[#drifters + 1] = id end
        end
    end
    if #drifters > 0 then
        addRow(self.list, "drifters", "Drifters  |  unaffiliated  |  "
            .. tostring(#drifters) .. " known" .. "  |  -")
    end
    if #factions == 0 and #drifters == 0 then
        addRow(self.list, "none", "No other factions yet - survivors you meet will appear here")
    end
    self.factions = factions
    self.drifters = drifters
    self.playerFaction = playerFaction
    self:populateMembers()
    self:layoutPage()
end

function WorldView:selectedFaction()
    local selected = self.list.selected or 0
    local row = selected > 0 and self.list.items[selected] or nil
    local key = row ~= nil and tostring(row.knoxKey or "") or ""
    if key == "drifters" then return "drifters" end
    for _, faction in ipairs(self.factions or {}) do
        if faction ~= nil and tostring(faction.id) == key then return faction end
    end
    return (self.factions or {})[1]
end

function WorldView:populateMembers()
    self.memberList:clear(); self.memberIds = {}
    local faction = self:selectedFaction()
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if faction == nil then
        self.cardPortrait.texture = nil
        self.cardLine1.knoxFullText = "Select a faction above"
        self.cardLine2.knoxFullText = ""
        addRow(self.memberList, "none", "Select a faction above")
        return
    end
    if faction == "drifters" then
        self.cardPortrait.texture = nil
        self.cardLine1.knoxFullText = "Drifters - unaffiliated survivors you have met"
        self.cardLine2.knoxFullText = tostring(#(self.drifters or {})) .. " known"
    else
        local standing = "neutral"
        if self.playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(self.playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
        end
        local members, residents, guards = self:factionStats(faction)
        local leaderName = faction.leaderId ~= nil and self:memberName(faction.leaderId) or "Unknown"
        self.cardPortrait.texture = self:leaderPortrait(faction.leaderId, self.playerNum)
        self.cardLine1.knoxFullText =
            "Leader: " .. leaderName .. "  |  " .. standing .. "  |  " .. self:factionHome(faction)
        self.cardLine2.knoxFullText =
            tostring(members) .. " members (" .. tostring(residents) .. " settled, "
            .. tostring(guards) .. " watch)  |  " .. self:factionHistory(faction, now)
    end
    local entries = {}
    if faction == "drifters" then
        for _, id in ipairs(self.drifters or {}) do entries[#entries + 1] = { id = id, faction = nil } end
    else
        for _, id in ipairs(faction.memberIds or {}) do entries[#entries + 1] = { id = id, faction = faction } end
    end
    if #entries == 0 then
        addRow(self.memberList, "empty", "  No members recorded")
        return
    end
    local rows = {}
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = { id = entry.id, name = self:memberName(entry.id),
            role = self:memberRole(entry.faction, entry.id) }
    end
    table.sort(rows, function(a, b)
        if a.role == "Leader" and b.role ~= "Leader" then return true end
        if b.role == "Leader" and a.role ~= "Leader" then return false end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        local text = "  " .. row.name .. "  |  " .. row.role
        local alive = KnoxPersistence.isSurvivorAlive ~= nil
            and KnoxPersistence.isSurvivorAlive(row.id) or nil
        if alive == false then
            text = text .. "  |  dead"
        else
            local snap = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(row.id, self.playerNum) or nil
            if snap ~= nil and snap.activity ~= nil and tostring(snap.activity) ~= "" then
                text = text .. "  |  " .. tostring(snap.activity)
            end
        end
        addRow(self.memberList, row.id, text)
        self.memberIds[#self.memberIds + 1] = row.id
    end
end

function WorldView:onView()
    local index = self.memberList.selected or 0
    local row = index > 0 and self.memberList.items[index] or nil
    local key = row ~= nil and tostring(row.knoxKey or "") or ""
    if key ~= "" and key ~= "standing" and key ~= "empty" and key ~= "none" then
        KnoxSurvivorCard.show(self.playerNum, key)
    end
end
function WorldView:prerender()
    ISPanelJoypad.prerender(self)
    if self.viewBtn then
        local index = self.memberList.selected or 0
        local row = index > 0 and self.memberList.items[index] or nil
        local key = row ~= nil and tostring(row.knoxKey or "") or ""
        self.viewBtn:setEnable(key ~= "" and key ~= "standing" and key ~= "empty" and key ~= "none")
        if self.viewReason ~= nil then
            local reason = self.viewBtn.enable
                and "View Card opens the selected survivor's sheet."
                or "Select a member above to open their card."
            if self.viewReason.knoxFullText ~= reason then
                self.viewReason.knoxFullText=reason
                self:layoutPage()
            end
        end
    end
end
function WorldView:onJoypadDown(b, jd)
    if b == Joypad.AButton and self.memberList.selected > 0 then self:onView() end
    ISPanelJoypad.onJoypadDown(self, b, jd)
end
function WorldView:new(x, y, w, h) local o = ISPanelJoypad.new(self, x, y, w, h); o:noBackground(); return o end

-- Stock targets are a seasonal decision rather than a morning one, so they live
-- on their own page beside Crew. Every number comes from the same planner the
-- residents obey, so a target raised here is the one a supply run works to; the
-- page never creates stock, it only states what this home wants to keep.
-- THE STORES CARDS
-- One painted card per stock target: what it is, how much is on hand against the
-- target, a level bar, and the two steppers that move that one number. The panel
-- owns no state and writes nothing; every change goes through StoresView's
-- existing save path. Geometry comes from Layout.cardGrid and Layout.cardParts.
local KnoxStoreCards = ISPanel:derive("KnoxStoreCards")
local STORE_CARD_H = 74
function KnoxStoreCards:initialise() ISPanel.initialise(self) end
function KnoxStoreCards:contentHeight(availableWidth)
    local grid = UILayout.cardGrid(#(self.rows or {}),
        math.max(1, availableWidth or self.width),
        { gap = 10, minWidth = 220, cardHeight = STORE_CARD_H, columns = 3 })
    return grid.height
end
function KnoxStoreCards:setCards(rows)
    self.rows = type(rows) == "table" and rows or {}
    self.grid = UILayout.cardGrid(#self.rows, math.max(1, self.width),
        { gap = 10, minWidth = 220, cardHeight = STORE_CARD_H, columns = 3 })
end
function KnoxStoreCards:render()
    if self.grid == nil then return end
    local theme = UILayout.sheetTheme()
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local red = UILayout.colour("red")
    for _, cell in ipairs(self.grid.cells or {}) do
        local row = self.rows[cell.index]
        if row ~= nil then
            local selected = self.selectedKey ~= nil and self.selectedKey == row.key
            self:drawRect(cell.x, cell.y, cell.width, cell.height, 0.55,
                theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
            self:drawRectBorder(cell.x, cell.y, cell.width, cell.height,
                selected and 0.95 or 0.55,
                selected and theme.amber[1] or theme.border[1],
                selected and theme.amber[2] or theme.border[2],
                selected and theme.amber[3] or theme.border[3])
            self:drawText(UILayout.fitText(UIFont.Small, row.label or "",
                    math.max(1, cell.width - 12), measure),
                cell.x + 6, cell.y + 6, theme.dim[1], theme.dim[2], theme.dim[3],
                1, UIFont.Small)
            self:drawText(tostring(row.current or 0) .. " / " .. tostring(row.target or 0),
                cell.x + 6, cell.y + 6 + fontH + 2,
                theme.bone[1], theme.bone[2], theme.bone[3], 1, UIFont.Small)
            local chip, tone = nil, theme.muted
            if tonumber(row.missing or 0) > 0 then
                chip = "needs " .. tostring(row.missing)
                tone = red
            elseif row.override == true then
                chip = "yours"
                tone = theme.amber
            end
            if chip ~= nil then
                self:drawText(chip, cell.x + cell.width - 6 - measure(chip),
                    cell.y + 6 + fontH + 2, tone[1], tone[2], tone[3], 0.95, UIFont.Small)
            end
            local parts = UILayout.cardParts(cell)
            local fill = 0
            local target = tonumber(row.target or 0)
            if target > 0 then
                fill = math.max(0, math.min(1, (tonumber(row.current) or 0) / target))
            end
            self:drawRect(cell.x + parts.bar.x, cell.y + parts.bar.y,
                parts.bar.width, parts.bar.height, 0.45, 0.02, 0.02, 0.02)
            self:drawRect(cell.x + parts.bar.x, cell.y + parts.bar.y,
                math.max(1, parts.bar.width * fill), parts.bar.height, 0.9,
                theme.bone[1] * 0.72, theme.bone[2] * 0.72, theme.bone[3] * 0.72)
            for _, stepper in ipairs({ { parts.minus, "-", -1 }, { parts.plus, "+", 1 } }) do
                local rect = stepper[1]
                self:drawRect(cell.x + rect.x, cell.y + rect.y,
                    rect.width, rect.height, 0.75,
                    theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
                self:drawRectBorder(cell.x + rect.x, cell.y + rect.y,
                    rect.width, rect.height, 0.8,
                    theme.border[1], theme.border[2], theme.border[3])
                local glyphW = measure(stepper[2])
                self:drawText(stepper[2],
                    cell.x + rect.x + math.floor((rect.width - glyphW) / 2),
                    cell.y + rect.y + math.max(0, math.floor((rect.height - fontH) / 2)),
                    theme.bone[1], theme.bone[2], theme.bone[3], 1, UIFont.Small)
            end
        end
    end
end
function KnoxStoreCards:onMouseDown(x, y)
    if self.owner == nil or self.grid == nil then return false end
    for _, cell in ipairs(self.grid.cells or {}) do
        if x >= cell.x and x < cell.x + cell.width
            and y >= cell.y and y < cell.y + cell.height then
            local row = self.rows[cell.index]
            if row == nil then return false end
            local parts = UILayout.cardParts(cell)
            local function inside(rect)
                return x >= cell.x + rect.x and x < cell.x + rect.x + rect.width
                    and y >= cell.y + rect.y and y < cell.y + rect.y + rect.height
            end
            self.selectedKey = row.key
            if self.owner.selectCategory ~= nil then self.owner:selectCategory(row.key) end
            if inside(parts.minus) then
                self.owner:changeTarget(row.key, -1)
            elseif inside(parts.plus) then
                self.owner:changeTarget(row.key, 1)
            end
            return true
        end
    end
    return false
end

local function stockItemLabel(fullType)
    local ok, scriptItem = pcall(function()
        return getScriptManager():getItem(tostring(fullType))
    end)
    if ok and scriptItem ~= nil then
        local nameOk, name = pcall(function() return scriptItem:getDisplayName() end)
        if nameOk and type(name) == "string" and name ~= "" then return name end
    end
    return (string.match(tostring(fullType), "%.(.+)$") or tostring(fullType))
end

-- ITEM MINIMUMS
-- A category target is a rule of thumb; a player who wants twenty bandages says
-- twenty bandages. Every saved item minimum is one row with the base's own
-- count beside it and two steppers. The panel owns no state and writes nothing:
-- StoresView reads the same persistence the supply planner obeys, and the
-- shelves are counted by KnoxBaseStorage.goalItemCount.
local ITEM_TARGET_ROW_H = 26
local ITEM_TARGET_ROW_GAP = 2
local KnoxItemTargets = ISPanel:derive("KnoxItemTargets")

function KnoxItemTargets:initialise() ISPanel.initialise(self) end
function KnoxItemTargets:setRows(rows)
    self.rows = type(rows) == "table" and rows or {}
end
function KnoxItemTargets:contentHeight()
    local rows = #(self.rows or {})
    return 8 + math.max(1, rows) * (ITEM_TARGET_ROW_H + ITEM_TARGET_ROW_GAP)
end
function KnoxItemTargets:render()
    local theme = UILayout.sheetTheme()
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local measure = function(value) return manager:MeasureStringX(UIFont.Small, value) end
    local parts = UILayout.itemTargetParts(self:getWidth(), ITEM_TARGET_ROW_H)
    local rows = self.rows or {}
    if #rows == 0 then
        self:drawText("No item minimums yet. Add Item names one thing this home keeps in stock.",
            parts.label.x, 4, theme.muted[1], theme.muted[2], theme.muted[3], 1, UIFont.Small)
        return
    end
    for index, row in ipairs(rows) do
        local top = 4 + (index - 1) * (ITEM_TARGET_ROW_H + ITEM_TARGET_ROW_GAP)
        local selected = self.selectedKey ~= nil and self.selectedKey == row.key
        if selected then
            self:drawRect(0, top, self:getWidth(), ITEM_TARGET_ROW_H, 0.22,
                theme.amber[1], theme.amber[2], theme.amber[3])
        end
        local textY = top + math.max(0, math.floor((ITEM_TARGET_ROW_H - fontH) / 2))
        self:drawText(UILayout.fitText(UIFont.Small, row.label or "", parts.label.width, measure),
            parts.label.x, textY, theme.bone[1], theme.bone[2], theme.bone[3], 1, UIFont.Small)
        if parts.count.width > 1 then
            local countText = tostring(row.current or 0) .. " / " .. tostring(row.target or 0)
            local tone = tonumber(row.missing or 0) > 0 and theme.red or theme.bone
            local countW = measure(countText)
            self:drawText(countText,
                parts.count.x + math.max(0, parts.count.width - countW), textY,
                tone[1], tone[2], tone[3], 1, UIFont.Small)
        end
        for _, stepper in ipairs({ { parts.minus, "-", -1 }, { parts.plus, "+", 1 } }) do
            local rect = stepper[1]
            self:drawRect(rect.x, top + rect.y, rect.width, rect.height, 0.75,
                theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
            self:drawRectBorder(rect.x, top + rect.y, rect.width, rect.height, 0.80,
                theme.border[1], theme.border[2], theme.border[3])
            local glyphW = measure(stepper[2])
            self:drawText(stepper[2],
                rect.x + math.max(0, math.floor((rect.width - glyphW) / 2)),
                top + rect.y + math.max(0, math.floor((rect.height - fontH) / 2)),
                theme.bone[1], theme.bone[2], theme.bone[3], 1, UIFont.Small)
        end
        if index < #rows then
            self:drawRect(0, top + ITEM_TARGET_ROW_H + 1, self:getWidth(), 1, 0.30,
                theme.border[1], theme.border[2], theme.border[3])
        end
    end
end
function KnoxItemTargets:onMouseDown(x, y)
    if self.owner == nil then return false end
    local parts = UILayout.itemTargetParts(self:getWidth(), ITEM_TARGET_ROW_H)
    for index, row in ipairs(self.rows or {}) do
        local top = 4 + (index - 1) * (ITEM_TARGET_ROW_H + ITEM_TARGET_ROW_GAP)
        if y >= top and y < top + ITEM_TARGET_ROW_H then
            local function inside(rect)
                return x >= rect.x and x < rect.x + rect.width
                    and y >= top + rect.y and y < top + rect.y + rect.height
            end
            if inside(parts.minus) then
                self.owner:changeItemTarget(row.fullType, -1)
            elseif inside(parts.plus) then
                self.owner:changeItemTarget(row.fullType, 1)
            elseif self.owner.selectItemTarget ~= nil then
                self.owner:selectItemTarget(row.key)
            end
            return true
        end
    end
    return false
end
function KnoxItemTargets:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    return o
end

-- ADD ITEM
-- The picker answers one question - which item type - and closes. The catalogue
-- is the storage filter owner's already-cached list of native items, read here
-- so a player naming a minimum sees the same names they see in a shelf filter.
-- Nothing here creates, moves or reserves an item.
local ItemGoalPicker = ISCollapsableWindowJoypad:derive("KnoxItemGoalPicker")

function ItemGoalPicker:new(playerNum, onPick)
    local screenW, screenH = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local width = math.max(1, math.min(520, screenW - 24))
    local height = math.max(1, math.min(520, screenH - 24))
    local window = ISCollapsableWindowJoypad:new(
        getPlayerScreenLeft(playerNum) + (screenW - width) / 2,
        getPlayerScreenTop(playerNum) + (screenH - height) / 2, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = tonumber(playerNum) or 0
    window.onPick = onPick
    window:setTitle("Add a stock item")
    window:setResizable(true)
    UILayout.tintSheetWindow(window)
    UILayout.trackWindow(window)
    return window
end

function ItemGoalPicker:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local titleH = self:titleBarHeight()
    self.hintLabel = ISLabel:new(UI_BORDER_SPACING, titleH + 4, FONT_HGT_SMALL,
        "A minimum is fetched by residents. It never caps what the shelves hold.",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.hintLabel:initialise()
    self:addChild(self.hintLabel)
    self.searchBox = ISTextEntryBox:new("", UI_BORDER_SPACING,
        self.hintLabel:getBottom() + 4, self.width - UI_BORDER_SPACING * 2,
        FONT_HGT_SMALL + 8)
    self.searchBox:initialise()
    if self.searchBox.instantiate ~= nil then self.searchBox:instantiate() end
    self.searchBox:setClearButton(true)
    self.searchBox.tooltip = "Type part of an item name, or a type such as Base.Bandage."
    self.searchBox.onTextChange = function() self:populate() end
    self:addChild(self.searchBox)
    local listTop = self.searchBox:getBottom() + 4
    -- The viewport is the rows that actually fit above the cancel button,
    -- measured through the shared stack rule like every other list here.
    local listSpace = math.max(1,
        self.height - listTop - BUTTON_HGT - UI_BORDER_SPACING * 3)
    local listRows = math.max(3, math.floor(listSpace / BUTTON_HGT))
    self.categoryList = ISScrollingListBox:new(UI_BORDER_SPACING, listTop,
        self.width - UI_BORDER_SPACING * 2, BUTTON_HGT)
    self.categoryList:initialise()
    self.categoryList:setHeight(UILayout.stackHeight(listRows, BUTTON_HGT, 3, 0))
    self.categoryList:instantiate()
    self.categoryList.itemheight = BUTTON_HGT
    self.categoryList.font = UIFont.Small
    self.categoryList.doDrawItem = BaseView.drawStorage
    self.categoryList.drawBorder = true
    self.categoryList.joypadParent = self
    self.categoryList:setAnchorRight(true)
    self.categoryList:setAnchorBottom(true)
    self.categoryList:setOnMouseDownFunction(self, ItemGoalPicker.onPickRow)
    self:addChild(self.categoryList)
    self.cancelBtn = ISButton:new(self.width - UI_BORDER_SPACING - 88,
        self.height - UI_BORDER_SPACING - BUTTON_HGT, 88, BUTTON_HGT,
        "Cancel", self, ItemGoalPicker.close)
    self.cancelBtn:initialise()
    UILayout.tintButton(self.cancelBtn)
    self.cancelBtn:setAnchorRight(true)
    self.cancelBtn:setAnchorBottom(true)
    self:addChild(self.cancelBtn)
    self:populate()
end

-- The catalogue is cached by the storage filter owner; this reads it instead of
-- walking the script manager a second time for the same list.
function ItemGoalPicker:entries()
    local filter = rawget(_G, "KnoxBaseStorageFilterUI")
    local filterWindow = filter ~= nil and filter.FilterWindow or nil
    if filterWindow ~= nil and filterWindow.itemEntries ~= nil then
        local ok, entries = pcall(filterWindow.itemEntries, filterWindow)
        if ok and type(entries) == "table" and #entries > 0 then return entries end
    end
    local entries = {}
    local ok, allItems = pcall(function() return getScriptManager():getAllItems() end)
    if not ok or allItems == nil then return entries end
    for index = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(index)
        local typeOk, fullType = pcall(function() return scriptItem:getFullName() end)
        if typeOk and type(fullType) == "string" and fullType ~= ""
            and KnoxBaseSupplyPlanner.itemTargetKey(fullType) ~= nil then
            local nameOk, display = pcall(function() return scriptItem:getDisplayName() end)
            entries[#entries + 1] = {
                fullType = fullType,
                label = nameOk and tostring(display or fullType) or fullType,
            }
        end
    end
    table.sort(entries, function(first, second)
        local left, right = string.lower(first.label), string.lower(second.label)
        if left == right then return first.fullType < second.fullType end
        return left < right
    end)
    return entries
end

function ItemGoalPicker:populate()
    if self.categoryList == nil then return end
    self.categoryList:clear()
    local query = ""
    if self.searchBox ~= nil and self.searchBox.getText ~= nil then
        local ok, text = pcall(function() return self.searchBox:getText() end)
        if ok and type(text) == "string" then query = string.lower(text) end
    end
    local shown = 0
    for _, entry in ipairs(self:entries()) do
        local matches = query == ""
            or string.find(string.lower(entry.label), query, 1, true) ~= nil
            or string.find(string.lower(entry.fullType), query, 1, true) ~= nil
        if matches then
            self.categoryList:addItem(entry.label, { fullType = entry.fullType })
            shown = shown + 1
            -- The catalogue is the whole game; a bounded list stays responsive.
            if shown >= 300 then break end
        end
    end
    if shown == 0 then
        self.categoryList:addItem("No item matches that search.", { none = true })
    end
end

function ItemGoalPicker.onPickRow(target, entry)
    local data = type(entry) == "table" and (entry.item or entry) or nil
    if target == nil or type(data) ~= "table" or data.fullType == nil then return end
    local pick = target.onPick
    target:close()
    if pick ~= nil then pick(data.fullType) end
end

function ItemGoalPicker:close()
    self:setVisible(false)
    self:removeFromUIManager()
    local stores = self.ownerStores
    if stores ~= nil then stores.picker = nil end
end

local StoresView = ISPanelJoypad:derive("KnoxNotebookStoresView")
function StoresView:initialise() ISPanelJoypad.initialise(self) end
function StoresView:getWindow() return self:getParent():getParent() end
function StoresView:createChildren()
    local y = UI_BORDER_SPACING
    self.targetsLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Stock targets - what this home keeps on hand",
        1, 1, 1, 1, UIFont.Small, true)
    self.targetsLabel:initialise(); self:addChild(self.targetsLabel)
    y = y + FONT_HGT_SMALL + 4
    self.captionLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Minimums are restock goals, not storage limits.",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.captionLabel:initialise(); self:addChild(self.captionLabel)
    y = y + FONT_HGT_SMALL + 8
    -- Named items lead. Categories stay below as the rule of thumb they are.
    self.itemsHeading = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Item minimums", 1, 1, 1, 1, UIFont.Small, true)
    self.itemsHeading:initialise(); self:addChild(self.itemsHeading)
    y = y + FONT_HGT_SMALL + 4
    self.itemTargets = KnoxItemTargets:new(UI_BORDER_SPACING, y,
        self.width - UI_BORDER_SPACING * 2, ITEM_TARGET_ROW_H + 8)
    self.itemTargets:initialise(); self.itemTargets.owner = self
    self:addChild(self.itemTargets)
    y = self.itemTargets:getBottom() + 6
    self.addItemBtn = ISButton:new(UI_BORDER_SPACING, y, 110, BUTTON_HGT,
        "Add Item", self, StoresView.onAddItem)
    self.addItemBtn:initialise(); self:addChild(self.addItemBtn)
    self.removeItemBtn = ISButton:new(self.addItemBtn:getRight() + 6, y, 120, BUTTON_HGT,
        "Remove Item", self, StoresView.onRemoveItem)
    self.removeItemBtn:initialise(); self:addChild(self.removeItemBtn)
    for _, button in ipairs({ self.addItemBtn, self.removeItemBtn }) do
        button.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
            b = sheetTheme.border[3], a = 0.80 }
        button.backgroundColor = { r = sheetTheme.charcoal[1], g = sheetTheme.charcoal[2],
            b = sheetTheme.charcoal[3], a = 0.92 }
    end
    self.addItemBtn.tooltip = "Name one exact item and set how much of it this home keeps."
    self.removeItemBtn.tooltip = "Drop the selected item minimum. Stored stock is untouched."
    y = y + BUTTON_HGT + 4
    -- Every control that can be greyed says why, from its real state.
    self.itemReason = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.itemReason:initialise(); self:addChild(self.itemReason)
    y = y + FONT_HGT_SMALL + 8
    self.categoriesHeading = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Category minimums", 1, 1, 1, 1, UIFont.Small, true)
    self.categoriesHeading:initialise(); self:addChild(self.categoriesHeading)
    y = y + FONT_HGT_SMALL + 4
    -- One card per category target, each with its own steppers. The page is the
    -- only scroller; there is no list nested inside it.
    self.cardsPanel = KnoxStoreCards:new(UI_BORDER_SPACING, y,
        self.width - UI_BORDER_SPACING * 2, STORE_CARD_H)
    self.cardsPanel:initialise(); self.cardsPanel.owner = self
    self:addChild(self.cardsPanel)
    y = self.cardsPanel:getBottom() + 8
    self.clearBtn = ISButton:new(UI_BORDER_SPACING, y, 128, BUTTON_HGT,
        "Clear Targets", self, StoresView.onClear)
    self.clearBtn:initialise()
    self.clearBtn.tooltip = "Drop every number you set and use the planner defaults again."
    self.clearBtn.borderColor = { r = sheetTheme.border[1], g = sheetTheme.border[2],
        b = sheetTheme.border[3], a = 0.80 }
    self.clearBtn.backgroundColor = { r = sheetTheme.charcoal[1], g = sheetTheme.charcoal[2],
        b = sheetTheme.charcoal[3], a = 0.92 }
    self:addChild(self.clearBtn)
    y = y + BUTTON_HGT + 10
    -- The containers, the yard and the kit scan are read here because this is
    -- where their rules are set. Base & Work keeps the counts that need a
    -- decision, not the shelves themselves.
    self.storageHeading = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Base storage", 1, 1, 1, 1, UIFont.Small, true)
    self.storageHeading:initialise(); self:addChild(self.storageHeading)
    y = y + FONT_HGT_SMALL + 4
    self.storageLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.storageLabel:initialise(); self:addChild(self.storageLabel)
    y = y + FONT_HGT_SMALL + 2
    self.storageList = ISScrollingListBox:new(UI_BORDER_SPACING, y,
        self.width - UI_BORDER_SPACING * 2, BUTTON_HGT * 3)
    self.storageList:initialise(); self.storageList:instantiate()
    self.storageList.itemheight = BUTTON_HGT; self.storageList.font = UIFont.Small
    self.storageList.doDrawItem = BaseView.drawStorage
    self.storageList.drawBorder = true; self:addChild(self.storageList)
    y = self.storageList:getBottom() + 4
    self.yardLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "",
        0.72, 0.72, 0.70, 1, UIFont.Small, true)
    self.yardLabel:initialise(); self:addChild(self.yardLabel)
    y = y + FONT_HGT_SMALL + 10
    self.kitHeading = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT,
        "Role kit shortages", 1, 1, 1, 1, UIFont.Small, true)
    self.kitHeading:initialise(); self:addChild(self.kitHeading)
    y = y + FONT_HGT_SMALL + 4
    self.kitShortageLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.kitShortageLabel:initialise(); self:addChild(self.kitShortageLabel)
    y = y + FONT_HGT_SMALL + 2
    self.kitShortageList = ISScrollingListBox:new(UI_BORDER_SPACING, y,
        self.width - UI_BORDER_SPACING * 2, BUTTON_HGT * 3)
    self.kitShortageList:initialise(); self.kitShortageList:instantiate()
    self.kitShortageList.itemheight = BUTTON_HGT; self.kitShortageList.font = UIFont.Small
    self.kitShortageList.doDrawItem = BaseView.drawStorage
    self.kitShortageList.drawBorder = true; self:addChild(self.kitShortageList)
    y = self.kitShortageList:getBottom() + 6
    self.hintLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "",
        sheetTheme.muted[1], sheetTheme.muted[2], sheetTheme.muted[3],
        1, UIFont.Small, true)
    self.hintLabel:initialise(); self:addChild(self.hintLabel)
    self:layoutPage()
end

-- Cards and rows flow from the measured width; the page scrolls if they do not
-- fit, and the reason lines say why a control is off when it is.
function StoresView:layoutPage()
    local spacing = UI_BORDER_SPACING
    local available = math.max(1, self.width - spacing * 2)
    local y = spacing
    self.targetsLabel:setX(spacing); self.targetsLabel:setY(y)
    self.targetsLabel:setWidth(available)
    y = y + FONT_HGT_SMALL + 4
    self.captionLabel:setX(spacing); self.captionLabel:setY(y)
    self.captionLabel:setWidth(available)
    y = y + FONT_HGT_SMALL + 8
    self.itemsHeading:setX(spacing); self.itemsHeading:setY(y)
    self.itemsHeading:setWidth(available)
    y = y + FONT_HGT_SMALL + 4
    self.itemTargets:setX(spacing); self.itemTargets:setY(y)
    self.itemTargets:setWidth(available)
    -- The panel measures itself: one empty-state line or one row per minimum.
    self.itemTargets:setHeight(math.max(40, self.itemTargets:contentHeight()))
    y = self.itemTargets:getBottom() + 6
    self.addItemBtn:setX(spacing); self.addItemBtn:setY(y)
    self.removeItemBtn:setX(spacing + 110 + 6); self.removeItemBtn:setY(y)
    y = y + BUTTON_HGT + 4
    y = layoutPageFeedback(self, self.itemReason, "storesItemLines",
        self.itemReason.knoxFullText or self.itemReason.name, spacing, y, available) + 8
    self.categoriesHeading:setX(spacing); self.categoriesHeading:setY(y)
    self.categoriesHeading:setWidth(available)
    y = y + FONT_HGT_SMALL + 4
    self.cardsPanel:setX(spacing); self.cardsPanel:setY(y)
    self.cardsPanel:setWidth(available)
    self.cardsPanel:setHeight(math.max(40, self.cardsPanel:contentHeight(available)))
    y = self.cardsPanel:getBottom() + 8
    self.clearBtn:setX(spacing); self.clearBtn:setY(y)
    y = y + BUTTON_HGT + 10
    self.storageHeading:setX(spacing); self.storageHeading:setY(y)
    self.storageHeading:setWidth(available)
    y = y + FONT_HGT_SMALL + 4
    y = layoutPageFeedback(self, self.storageLabel, "storesStorageLines",
        self.storageLabel.knoxFullText or self.storageLabel.name,
        spacing, y, available) + 2
    self.storageList:setX(spacing); self.storageList:setY(y)
    self.storageList:setWidth(available)
    self.storageList:setHeight(UILayout.stackHeight(
        #(self.storageList.items or {}), BUTTON_HGT, 2, 8))
    y = self.storageList:getBottom() + 4
    y = layoutPageFeedback(self, self.yardLabel, "storesYardLines",
        self.yardLabel.knoxFullText or self.yardLabel.name, spacing, y, available) + 10
    self.kitHeading:setX(spacing); self.kitHeading:setY(y)
    self.kitHeading:setWidth(available)
    y = y + FONT_HGT_SMALL + 4
    y = layoutPageFeedback(self, self.kitShortageLabel, "storesKitLines",
        self.kitShortageLabel.knoxFullText or self.kitShortageLabel.name,
        spacing, y, available) + 2
    self.kitShortageList:setX(spacing); self.kitShortageList:setY(y)
    self.kitShortageList:setWidth(available)
    self.kitShortageList:setHeight(UILayout.stackHeight(
        #(self.kitShortageList.items or {}), BUTTON_HGT, 2, 8))
    y = self.kitShortageList:getBottom() + 6
    y = layoutPageFeedback(self, self.hintLabel, "storesHintLines",
        self.hintLabel.knoxFullText or self.hintLabel.name, spacing, y, available)
    self.knoxContentHeight = y + spacing
end

function StoresView:selectCategory(key)
    self.selectedCategory = key
    if self.cardsPanel ~= nil then self.cardsPanel.selectedKey = key end
end
function StoresView:selectItemTarget(key)
    self.selectedItemKey = key
    if self.itemTargets ~= nil then self.itemTargets.selectedKey = key end
    self:populate(self.playerNum)
end
function StoresView:selectedBase(playerNum, pid)
    -- Same resolution as Base & Work, so the two pages cannot disagree about
    -- whether this player has a home.
    return notebookBase(self:getWindow(), playerNum, pid)
end

-- One save path for every number on this page, so clearing, stepping and
-- removing cannot drift apart in what they report.
function StoresView:saveTargets(targets, message)
    local ok, reason = KnoxPersistence.setBaseReserveTargets(self.baseId, self.playerId,
        targets, getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0)
    if ok then
        if message ~= nil then KnoxActivityFeed.event(message) end
        local win = self:getWindow()
        if win ~= nil and win.refreshContent ~= nil then win:refreshContent() end
    else
        KnoxActivityFeed.event("Stock targets not saved: " .. tostring(reason) .. ".")
    end
end

function StoresView:populate(playerNum)
    playerNum = playerNum or self.playerNum or 0
    self.playerNum = playerNum
    local player = getSpecificPlayer(playerNum)
    local pid = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = pid ~= nil and self:selectedBase(playerNum, pid) or nil
    self.baseId = base ~= nil and base.id or nil
    self.playerId = pid
    self.rows = {}
    self.itemRows = {}
    self.storageList:clear()
    self.kitShortageList:clear()
    self.storageLabel.knoxFullText = ""
    self.kitShortageLabel.knoxFullText = ""
    self.yardLabel.knoxFullText = ""
    if base == nil then
        -- Same verdict as Base & Work: one resolution of "does this player have
        -- a home", so the two pages cannot contradict each other.
        self.targetsLabel.name = "Stock targets - no home base yet"
        self.cardsPanel:setCards({})
        self.itemTargets:setRows({})
        self.itemTargets.selectedKey = nil
        self.clearBtn:setEnable(false)
        self.addItemBtn:setEnable(false)
        self.removeItemBtn:setEnable(false)
        self.selectedItemKey = nil
        self.itemReason.knoxFullText = "No home base yet. Item and category minimums need a home."
        self.hintLabel.knoxFullText = "No home base yet. Establish a base to set stock targets."
        addRow(self.storageList, "none", "No home base yet.")
        addRow(self.kitShortageList, "none", "No home base yet.")
        self:layoutPage()
        return
    end
    self.addItemBtn:setEnable(true)
    local overrides = KnoxPersistence.getBaseReserveTargets ~= nil
        and KnoxPersistence.getBaseReserveTargets(base.id) or nil
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local settlement = KnoxBaseJobs ~= nil and KnoxBaseJobs.settlementSummary ~= nil
        and KnoxBaseJobs.settlementSummary(base, now) or nil
    local summary = settlement ~= nil and settlement.storage or KnoxBaseStorage.summarize(base)
    local totals = summary ~= nil and summary.totals or {}
    local residents = settlement ~= nil and settlement.workforce ~= nil
        and tonumber(settlement.workforce.residents) or 1
    local statuses = KnoxBaseSupplyPlanner ~= nil and KnoxBaseSupplyPlanner.reserveStatus ~= nil
        and KnoxBaseSupplyPlanner.reserveStatus(totals, residents, overrides,
            settlement ~= nil and settlement.waterSource or nil) or {}
    local hasOverride = false
    for _, status in ipairs(statuses) do
        local label = tostring(RESOURCE_LABELS[status.category] or status.category)
        -- The card names the shortage as a chip and marks your own number with
        -- the word "yours", so nothing needs a "*" star to be decoded.
        local mine = overrides ~= nil and overrides[status.category] ~= nil
        if mine then hasOverride = true end
        self.rows[#self.rows + 1] = { key = status.category, label = label,
            target = status.target, current = status.current,
            missing = tonumber(status.missing) or 0, override = mine ~= false }
    end
    self.cardsPanel:setCards(self.rows)
    self.cardsPanel.selectedKey = self.selectedCategory
    -- Item minimums read the same assigned shelves the supply planner obeys.
    local goals = KnoxBaseSupplyPlanner ~= nil and KnoxBaseSupplyPlanner.itemGoalStatus ~= nil
        and KnoxBaseSupplyPlanner.itemGoalStatus(overrides, function(fullType)
            return KnoxBaseStorage.goalItemCount ~= nil
                and KnoxBaseStorage.goalItemCount(base, fullType) or 0
        end) or {}
    for _, goal in ipairs(goals) do
        hasOverride = true
        self.itemRows[#self.itemRows + 1] = { key = goal.key, fullType = goal.fullType,
            label = stockItemLabel(goal.fullType), current = goal.current,
            target = goal.target, missing = goal.missing }
    end
    self.itemTargets:setRows(self.itemRows)
    local selected = nil
    for _, row in ipairs(self.itemRows) do
        if row.key == self.selectedItemKey then selected = row; break end
    end
    if selected == nil then self.selectedItemKey = nil end
    self.itemTargets.selectedKey = self.selectedItemKey
    self.removeItemBtn:setEnable(selected ~= nil)
    if selected ~= nil then
        self.itemReason.knoxFullText = tostring(selected.label) .. ": keeps at least "
            .. tostring(selected.target) .. ", " .. tostring(selected.current)
            .. " on the shelves."
    elseif #self.itemRows == 0 then
        self.itemReason.knoxFullText =
            "No item minimums. Add Item names one thing this home keeps in stock."
    else
        self.itemReason.knoxFullText = tostring(#self.itemRows)
            .. (#self.itemRows == 1 and " item minimum." or " item minimums.")
    end
    self.clearBtn:setEnable(hasOverride)
    if hasOverride then
        self.hintLabel.knoxFullText = "Clear Targets restores default stock goals."
    else
        self.hintLabel.knoxFullText = "Using default stock goals."
    end
    populateStorageSection(self, base, settlement)
    populateKitSection(self, base)
    -- The yard is where stock leaves the shelves, so its line belongs beside the
    -- containers rather than on the page read every morning.
    local depotLine = KnoxBaseStorage.depotSummaryLine ~= nil
        and KnoxBaseStorage.depotSummaryLine(KnoxBaseStorage.depotStatus(base)) or nil
    self.yardLabel.knoxFullText = depotLine or "No yard painted yet: a log area becomes one."
    self:layoutPage()
end

function StoresView:changeTarget(key, direction)
    local row = nil
    for _, candidate in ipairs(self.rows or {}) do
        if candidate.key == key then row = candidate; break end
    end
    if row == nil or self.baseId == nil or self.playerId == nil then return end
    local targets = KnoxPersistence.getBaseReserveTargets(self.baseId) or {}
    local current = tonumber(targets[key]) or tonumber(row.target) or 0
    local value = direction < 0 and previousStockTarget(current) or nextStockTarget(current)
    targets[key] = value
    self.selectedCategory = key
    self:saveTargets(targets, "Stock target " .. tostring(RESOURCE_LABELS[key] or key)
        .. ": " .. tostring(value) .. ".")
end

function StoresView:changeItemTarget(fullType, direction)
    if self.baseId == nil or self.playerId == nil then return end
    local key = KnoxBaseSupplyPlanner.itemTargetKey ~= nil
        and KnoxBaseSupplyPlanner.itemTargetKey(tostring(fullType)) or nil
    if key == nil then return end
    local targets = KnoxPersistence.getBaseReserveTargets(self.baseId) or {}
    local current = tonumber(targets[key]) or 0
    local value = direction < 0 and previousStockTarget(current) or nextStockTarget(current)
    -- Zero is not a rule: the key goes, so a minimum the player stepped away is
    -- gone from the save instead of sitting there asking for nothing.
    targets[key] = value > 0 and value or nil
    self.selectedItemKey = value > 0 and key or nil
    self:saveTargets(targets, "Stock minimum " .. stockItemLabel(fullType)
        .. ": " .. tostring(value) .. ".")
end

function StoresView:addItemGoal(fullType)
    if self.baseId == nil or self.playerId == nil then return end
    local key = KnoxBaseSupplyPlanner.itemTargetKey ~= nil
        and KnoxBaseSupplyPlanner.itemTargetKey(tostring(fullType)) or nil
    if key == nil then
        KnoxActivityFeed.event("That item cannot carry a stock minimum.")
        return
    end
    local targets = KnoxPersistence.getBaseReserveTargets(self.baseId) or {}
    if targets[key] == nil then targets[key] = 1 end
    self.selectedItemKey = key
    self:saveTargets(targets, "Stock minimum added: " .. stockItemLabel(fullType)
        .. " (" .. tostring(targets[key]) .. ").")
end

function StoresView:onAddItem()
    if self.baseId == nil or self.playerId == nil then return end
    if self.picker ~= nil then self.picker:close() end
    local playerNum = (self:getWindow() ~= nil and self:getWindow().playerNum)
        or self.playerNum or 0
    local picker = ItemGoalPicker:new(playerNum, function(fullType)
        self:addItemGoal(fullType)
    end)
    picker.ownerStores = self
    picker:initialise()
    picker:addToUIManager()
    picker:setVisible(true)
    picker:bringToTop()
    self.picker = picker
end

function StoresView:onRemoveItem()
    if self.baseId == nil or self.playerId == nil or self.selectedItemKey == nil then return end
    local targets = KnoxPersistence.getBaseReserveTargets(self.baseId) or {}
    if targets[self.selectedItemKey] == nil then
        self.selectedItemKey = nil
        self:populate(self.playerNum)
        return
    end
    local fullType = KnoxBaseSupplyPlanner.itemTargetType ~= nil
        and KnoxBaseSupplyPlanner.itemTargetType(self.selectedItemKey) or nil
    targets[self.selectedItemKey] = nil
    self.selectedItemKey = nil
    self:saveTargets(targets, "Stock minimum removed: "
        .. tostring(fullType ~= nil and stockItemLabel(fullType) or "item") .. ".")
end

function StoresView:onClear()
    if self.baseId == nil or self.playerId == nil then return end
    self.selectedItemKey = nil
    self:saveTargets(nil, "Stock targets reset to planner defaults.")
end
function StoresView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- THE TAB STRIP (2026-11-04)
-- ISTabPanel paints its own tabs from `tabSelected`/`tabUnSelected` textures, so
-- the notebook wore the game's chrome no matter what we tinted around it. The
-- tab strip is therefore drawn by us. Geometry is not re-derived: labels sit on
-- `getTabX(index, 0)` with the same width the panel itself measures, so the
-- game's own `getTabIndexAtX` hit test still lands on the label a player sees.
-- Only drawing is replaced; addView, activateView, scrolling, drag and joypad
-- focus stay the panel's own.
local SheetTabs = ISTabPanel:derive("KnoxSheetTabs")

function SheetTabs:sheetTabWidth(entry)
    if self.equalTabWidth and self.maxLength ~= nil then return self.maxLength end
    return entry ~= nil and tonumber(entry.tabWidth) or 0
end

function SheetTabs:render()
    local theme = UILayout.sheetTheme()
    local tabH = tonumber(self.tabHeight) or 0
    -- The page keeps the same sheet and one hairline as every other Knox window.
    self:drawRect(0, tabH, self.width, math.max(0, self.height - tabH),
        0.94, theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
    self:drawRect(0, 0, self.width, math.max(0, tabH - 1),
        0.97, theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
    local manager = getTextManager()
    local fontH = manager:getFontHeight(UIFont.Small)
    local allTabsWidth = self:getWidthOfAllTabs()
    local overflow = allTabsWidth > self.width
    local overflowLeft = self.scrollX < 0
    local overflowRight = 1 + self.scrollX + allTabsWidth > self.width
    if overflow then self:setStencilRect(0, 0, self.width, tabH) end
    local activeIndex = 1
    if self.getActiveViewIndex ~= nil then
        local ok, index = pcall(function() return self:getActiveViewIndex() end)
        if ok and tonumber(index) ~= nil then activeIndex = tonumber(index) end
    end
    for index, entry in ipairs(self.viewList or {}) do
        local width = self:sheetTabWidth(entry)
        local x = 0
        if self.getTabX ~= nil then
            local ok, value = pcall(function() return self:getTabX(index) end)
            if ok and tonumber(value) ~= nil then x = tonumber(value) end
        end
        if width > 0 and x + width > 0 and x < self.width then
            local active = index == activeIndex
            local inner = math.max(1, width - 14)
            local label = UILayout.fitText(UIFont.Small, tostring(entry.name or ""), inner,
                function(candidate) return manager:MeasureStringX(UIFont.Small, candidate) end)
            local textWidth = manager:MeasureStringX(UIFont.Small, label)
            local textX = x + math.max(5, math.floor((width - textWidth) / 2))
            local textY = math.max(0, math.floor((tabH - fontH) / 2))
            -- Every tab is a box on the sheet; the active one is the same box
            -- filled and edged in the accent (owner reference, 2026-11-10), so
            -- selection is a state of one material rather than a second one.
            local boxH = math.max(2, tabH - 6)
            local box = active and theme.selected or theme.fill
            local edge = active and theme.accent or theme.border
            local boxW = math.max(1, width - 3)
            self:drawRect(x + 1, 3, boxW, boxH, 0.98, box[1], box[2], box[3])
            self:drawRect(x + 1, 3, boxW, 1, 0.90, edge[1], edge[2], edge[3])
            self:drawRect(x + 1, 3 + boxH - 1, boxW, 1, 0.90, edge[1], edge[2], edge[3])
            self:drawRect(x + 1, 3, 1, boxH, 0.90, edge[1], edge[2], edge[3])
            self:drawRect(x + boxW, 3, 1, boxH, 0.90, edge[1], edge[2], edge[3])
            local tone = active and theme.bone or theme.label
            self:drawText(label, textX, textY, tone[1], tone[2], tone[3], 1, UIFont.Small)
        end
    end
    local function arrow(path, right)
        local texture = getTexture(path)
        if texture == nil then return end
        local arrowWidth = texture:getWidth() + 6
        local left = right and self.width - 1 - arrowWidth or 1
        self:drawRect(left, 0, arrowWidth, tabH,
            1, theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
        self:drawTexture(texture, left + 3, (tabH - texture:getHeight()) / 2, 1, 1, 1, 1)
    end
    if overflowLeft then arrow("media/ui/ArrowLeft.png", false) end
    if overflowRight then arrow("media/ui/ArrowRight.png", true) end
    if overflow then self:clearStencilRect() end
    self:drawRect(0, math.max(0, tabH - 1), self.width, 1,
        0.90, theme.border[1], theme.border[2], theme.border[3])
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    -- The native resize widgets call this with proposed dimensions.
    if self.resizeWidget ~= nil then self.resizeWidget.resizeFunction = Window.resizeToViewport end
    if self.resizeWidget2 ~= nil then self.resizeWidget2.resizeFunction = Window.resizeToViewport end
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    -- Keep the native textured close button and its real hover/click target.
    -- Header layout moves it into the reserved top-right corner.
    UILayout.finishWindow(self, "Close Base Manager")
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    UILayout.trackWindow(self)
    -- Our own strip draws the tabs; the panel still owns view switching, drag,
    -- scroll and focus (see SheetTabs above).
    self.panel=SheetTabs:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    -- ISTabPanel:addView adds the child and invokes createChildren once. Calling
    -- it here as well duplicates every label/list/button and breaks page layout.
    self.baseView=BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.panel:addView("Base & Work", self.baseView); UILayout.bindView(self.baseView)
    self.crewView=CrewView:new(0, 8, self.panel.width, self.panel.height-8); self.crewView:initialise(); self.panel:addView("Crew & Schedule", self.crewView); UILayout.bindView(self.crewView)
    self.storesView=StoresView:new(0, 8, self.panel.width, self.panel.height-8); self.storesView:initialise(); self.panel:addView("Stores & Storage", self.storesView); UILayout.bindView(self.storesView)
    self.missionsView=MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.panel:addView("Missions", self.missionsView); UILayout.bindView(self.missionsView)
    self.worldView=WorldView:new(0, 8, self.panel.width, self.panel.height-8); self.worldView:initialise(); self.panel:addView("World", self.worldView); UILayout.bindView(self.worldView)
    -- The Work-tab band's raid row lands on the World tab, where the live
    -- threat is described; the title-bar pill uses the same route.
    self.baseView.knoxOpenStores = function()
        if self.panel ~= nil then self.panel:activateView("Stores & Storage") end
        self:refreshContent()
    end
    self.baseView.knoxOpenCrew = function()
        if self.panel ~= nil then self.panel:activateView("Crew & Schedule") end
        self:refreshContent()
    end
    self.baseView.knoxOpenWorld = function()
        if self.panel ~= nil then self.panel:activateView("World") end
        self:refreshContent()
    end
    self.homeAttentionBtn = ISButton:new(self.width - 360, 4, 330, BUTTON_HGT,
        "", self, Window.onHomeAttention)
    self.homeAttentionBtn:initialise()
    self.homeAttentionBtn:setVisible(false)
    local amber, charcoal = sheetTheme.amber, sheetTheme.charcoal
    self.homeAttentionBtn.borderColor = { r = amber[1], g = amber[2], b = amber[3], a = 0.75 }
    self.homeAttentionBtn.backgroundColor = { r = charcoal[1], g = charcoal[2],
        b = charcoal[3], a = 0.92 }
    self.homeAttentionBtn.tooltip = "Open Base & Work on the first home problem."
    self:addChild(self.homeAttentionBtn)
    -- Size the band from the real fonts now, not on the first prerender: the
    -- pages above were built against the inherited vanilla height and would
    -- otherwise be pulled up a frame later, which is the clipped look.
    self:layoutSheetHeader()
end

-- The title bar is the cheapest place to say where this notebook is open: the
-- home being managed and how many people live there. It reads the same
-- selected base the pages read and owns no state beyond the last title drawn.
function Window:updateTitle()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and self.baseView ~= nil
        and self.baseView:selectedBase(self.playerNum, playerId) or nil
    local title = "Knox Survivors"
    self.knoxName = "Knox Survivors"
    self.knoxDetail = ""
    if base ~= nil then
        local residents = #(KnoxPersistence.getBaseResidentIds(base.id) or {})
        self.knoxName = tostring(base.name or "Home base")
        self.knoxDetail = tostring(residents)
            .. (residents == 1 and " resident" or " residents")
        title = self.knoxName .. ", " .. self.knoxDetail
    end
    if self.knoxTitle ~= title then
        self.knoxTitle = title
        self:setTitle(title)
    end
end

-- THE SHEET (2026-11-04)
-- A Knox window used to be a vanilla sub-window with our content dropped
-- inside it: the game's own title strip, its close glyph and its resize grip
-- over a charcoal page. The window now repaints that strip as our header band -
-- home name in Medium, resident count in muted, a hairline under it and our own
-- close glyph. Presentation only: the title string, the drag behaviour and the
-- close path are the window's own and are untouched. Children (the home pill)
-- still draw above the band, so the one actionable chip in the header keeps its
-- button.
local function notebookHeaderLayout(width, name, detail, attention, manager)
    local room = math.max(1, width - 58)
    local mediumH, smallH = manager:getFontHeight(UIFont.Medium), manager:getFontHeight(UIFont.Small)
    local names = UILayout.wrapLines(tostring(name or "Knox Survivors"), room,
        function(value) return manager:MeasureStringX(UIFont.Medium, value) end)
    local details = UILayout.wrapLines(tostring(detail or ""), room,
        function(value) return manager:MeasureStringX(UIFont.Small, value) end)
    local height = 8 + #names * (mediumH + 2) + #details * (smallH + 2)
    local attentionY = height
    if attention then height = height + smallH + 14 end
    return {names=names,details=details,height=math.max(mediumH+8,height),attentionY=attentionY}
end

local inheritedTitleBarHeight = Window.titleBarHeight
function Window:titleBarHeight()
    if self.knoxHeaderHeight ~= nil then return self.knoxHeaderHeight end
    return inheritedTitleBarHeight(self)
end

function Window:layoutSheetHeader()
    if self.closeButton ~= nil then
        self.closeButton:setX(self.width - 32); self.closeButton:setY(4)
        self.closeButton:setWidth(26); self.closeButton:setHeight(26)
    end
    local attention = self.homeAttentionBtn ~= nil and self.homeAttentionBtn:isVisible()
    local manager = getTextManager()
    local smallH, mediumH = manager:getFontHeight(UIFont.Small), manager:getFontHeight(UIFont.Medium)
    local layout = self.knoxHeaderLayout
    if layout == nil or self.knoxHeaderWidth ~= self.width or self.knoxHeaderName ~= self.knoxName
        or self.knoxHeaderDetail ~= self.knoxDetail or self.knoxHeaderAttention ~= attention
        or self.knoxHeaderSmallH ~= smallH or self.knoxHeaderMediumH ~= mediumH then
        layout = notebookHeaderLayout(self.width,self.knoxName,self.knoxDetail,attention,manager)
        self.knoxHeaderLayout = layout
        self.knoxHeaderWidth, self.knoxHeaderName, self.knoxHeaderDetail = self.width, self.knoxName, self.knoxDetail
        self.knoxHeaderAttention, self.knoxHeaderSmallH, self.knoxHeaderMediumH = attention, smallH, mediumH
    end
    if self.knoxHeaderHeight ~= layout.height then
        self.knoxHeaderHeight = layout.height
        if self.panel ~= nil then
            self.panel:setY(layout.height)
            self.panel:setHeight(math.max(1,self.height-layout.height-self:resizeWidgetHeight()))
        end
    end
    if attention then
        local button = self.homeAttentionBtn
        button:setX(12);button:setY(layout.attentionY)
        button:setWidth(math.max(1,self.width-24));button:setHeight(getTextManager():getFontHeight(UIFont.Small)+10)
        local text = button.knoxFullText or "Review home"
        if getTextManager():MeasureStringX(UIFont.Small,text)>button.width-24 then text="Review home" end
        button:setTitle(text)
    end
end

local inheritedWindowRender = Window.render

function Window:sheetHeaderHeight()
    if self.titleBarHeight == nil then return 0 end
    local ok, height = pcall(function() return self:titleBarHeight() end)
    local value = ok and tonumber(height) or nil
    return value ~= nil and math.max(0, value) or 0
end

function Window:drawSheetHeader()
    local titleH = self:sheetHeaderHeight()
    if titleH <= 0 then return end
    local theme = UILayout.sheetTheme()
    local manager = getTextManager()
    self:drawRect(0, 0, self.width, titleH,
        0.97, theme.charcoal[1], theme.charcoal[2], theme.charcoal[3])
    self:drawRect(0, titleH - 1, self.width, 1,
        0.90, theme.border[1], theme.border[2], theme.border[3])
    local mediumH = manager:getFontHeight(UIFont.Medium)
    local smallH = manager:getFontHeight(UIFont.Small)
    local layout = self.knoxHeaderLayout or notebookHeaderLayout(self.width,self.knoxName,self.knoxDetail,false,manager)
    local y=4
    for _,line in ipairs(layout.names) do
        self:drawText(line,12,y,theme.bone[1],theme.bone[2],theme.bone[3],0.96,UIFont.Medium)
        y=y+mediumH+2
    end
    for _,line in ipairs(layout.details) do
        self:drawText(line,12,y,theme.muted[1],theme.muted[2],theme.muted[3],0.95,UIFont.Small)
        y=y+smallH+2
    end

end

function Window:render()
    if inheritedWindowRender ~= nil then inheritedWindowRender(self) end
    if self.isCollapsed or not self:isVisible() then return end
    self:drawSheetHeader()
end

-- The native close child owns its hit target; the header keeps native dragging.
function Window:onMouseDown(x, y)
    if ISCollapsableWindowJoypad.onMouseDown ~= nil then
        return ISCollapsableWindowJoypad.onMouseDown(self, x, y)
    end
    return false
end

function Window:refreshContent()
    local view = self.panel and self.panel:getActiveView() or nil
    if view == nil or view.populate == nil then return end
    local saved = {}
    local previousCrewSource = view.crewSelSource
    for _, field in ipairs({"list", "partyList", "resList", "memberList", "zoneList", "taskList", "storageList", "bedsList", "scheduleList"}) do
        local list = view[field]
        if list ~= nil then
            local row = list.items[list.selected or 0]
            saved[field] = { key = row and row.knoxKey, scroll = list:getYScroll() }
        end
    end
    local resident = view.residentIds and view.residentPicker
        and view.residentIds[view.residentPicker.selected or 0] or nil
    view:populate(self.playerNum)
    for field, state in pairs(saved) do
        local list = view[field]
        list.selected = 0
        for index, row in ipairs(list.items) do
            if state.key ~= nil and row.knoxKey == state.key then list.selected = index; break end
        end
        list:setYScroll(state.scroll)
    end
    if resident ~= nil and view.residentPicker ~= nil then
        view.residentPicker.selected = 0
        for index, id in ipairs(view.residentIds or {}) do
            if id == resident then view.residentPicker.selected = index; break end
        end
    end
    if view.onNotebookSelectionRestored ~= nil then
        view:onNotebookSelectionRestored(previousCrewSource)
    end
    self:updateTitle()
    self.refreshedView = view
    self.nextRefreshAt = getTimestampMs() + 2000
    self.homeAttentionDirty = true
end

function Window:updateHomeAttention()
    local button = self.homeAttentionBtn
    if button == nil or self.panel == nil or self.baseView == nil then return end
    local active = self.panel:getActiveView()
    if active == nil or active == self.baseView then
        button.knoxAttentionKey = nil
        button:setVisible(false)
        return
    end
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and self.baseView:selectedBase(self.playerNum, playerId) or nil
    local status = base ~= nil and KnoxBaseManager.homeStatus ~= nil
        and KnoxBaseManager.homeStatus(base, playerId) or nil
    local model = status ~= nil and KnoxBaseManager.baseLineModel ~= nil
        and KnoxBaseManager.baseLineModel(status) or nil
    if model == nil or model.expanded ~= true then
        button.knoxAttentionKey = nil
        button:setVisible(false)
        return
    end
    local label = tostring(base.name or "Home") .. ", " .. tostring(model.title or "")
        .. "  " .. tostring(model.actionLabel or "Review")
    button.knoxAttentionKey = model.itemKey
    button.knoxFullText=label
    button.tooltip=label .. ". Open the home problem."
    button:setVisible(true)
end

function Window:onHomeAttention()
    local key = self.homeAttentionBtn ~= nil
        and self.homeAttentionBtn.knoxAttentionKey or nil
    if key == "raid" and self.panel ~= nil then
        self.panel:activateView("World")
        self:refreshContent()
        return
    end
    if self.panel ~= nil then self.panel:activateView("Base & Work") end
    self:refreshContent()
    if key ~= nil and self.baseView ~= nil
        and self.baseView.focusAttentionKey ~= nil then
        self.baseView:focusAttentionKey(key)
    end
end

-- Keep minimums font-relative, but never larger than the player's viewport.
local function notebookMinimumSize(fontHeight, screenWidth, screenHeight)
    local scale = math.max(1, (tonumber(fontHeight) or 14) / 14)
    return math.min(math.floor(320 * scale), math.max(1, screenWidth - 40)),
        math.min(math.floor(280 * scale), math.max(1, screenHeight - 40))
end

function Window:resizeToViewport(width, height)
    local right = getPlayerScreenLeft(self.playerNum) + getPlayerScreenWidth(self.playerNum)
    local bottom = getPlayerScreenTop(self.playerNum) + getPlayerScreenHeight(self.playerNum)
    local availableWidth = math.max(1, right - self:getX())
    local availableHeight = math.max(1, bottom - self:getY())
    self:setWidth(math.min(availableWidth, math.max(math.min(self.minimumWidth, availableWidth), width)))
    self:setHeight(math.min(availableHeight, math.max(math.min(self.minimumHeight, availableHeight), height)))
end

function Window:syncResizeGeometry(now)
    if self.knoxLayoutWidth == self.width and self.knoxLayoutHeight == self.height
        and self.knoxLayoutHeader == self.knoxHeaderHeight then return false end
    self.knoxLayoutWidth, self.knoxLayoutHeight = self.width, self.height
    self.knoxLayoutHeader = self.knoxHeaderHeight
    local panel = self.panel
    if panel ~= nil then
        local top = self:sheetHeaderHeight()
        panel:setY(top)
        panel:setWidth(math.max(1, self.width))
        panel:setHeight(math.max(1, self.height - top - self:resizeWidgetHeight()))
        for _, entry in ipairs(panel.viewList or {}) do
            if entry.view ~= nil then UILayout.fitView(entry.view) end
        end
        local view = panel:getActiveView()
        if view ~= nil and view.layoutPage ~= nil then view:layoutPage()
        elseif view ~= nil and view.layoutFooter ~= nil then view:layoutFooter() end
    end
    self.knoxResizeRefreshAt = now + 150
    return true
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.isCollapsed or not self:isVisible() then
        if self.homeAttentionBtn ~= nil then self.homeAttentionBtn:setVisible(false) end
        self.homeAttentionDirty = true
        return
    end
    self:layoutSheetHeader()
    local now = getTimestampMs()
    self:syncResizeGeometry(now)
    local active = self.panel and self.panel:getActiveView() or nil
    local resizeReady = self.knoxResizeRefreshAt ~= nil and now >= self.knoxResizeRefreshAt
    local due = active ~= self.refreshedView or now >= (self.nextRefreshAt or 0) or resizeReady
    if due then
        self:refreshContent()
        if resizeReady then self.knoxResizeRefreshAt = nil end
    end
    -- Home status walks residents even on a cache hit. Share the page cadence,
    -- while switching page, selected base or player still updates immediately.
    if due or self.homeAttentionDirty or active ~= self.homeAttentionView
        or self.knoxBaseId ~= self.homeAttentionBaseId
        or self.playerNum ~= self.homeAttentionPlayerNum then
        self:updateHomeAttention()
        self.homeAttentionView = active
        self.homeAttentionBaseId = self.knoxBaseId
        self.homeAttentionPlayerNum = self.playerNum
        self.homeAttentionDirty = false
    end
end

function Window:onJoypadDown(button, joypadData)
    if button==Joypad.LBumper or button==Joypad.RBumper then
        if self.panel and self.panel.viewList and #self.panel.viewList>1 then
            local idx=self.panel:getActiveViewIndex()
            if button==Joypad.LBumper then idx= idx==1 and #self.panel.viewList or idx-1 else idx= idx==#self.panel.viewList and 1 or idx+1 end
            self.panel:activateView(self.panel.viewList[idx].name); setJoypadFocus(self.playerNum, self.panel:getActiveView()); return
        end
    end
    ISCollapsableWindowJoypad.onJoypadDown(self,button,joypadData)
end

function Window:new(playerNum)
    -- Font-relative sizing (same factor as the survivor card): larger UI
    -- fonts grow the window so rows and text keep their proportions on
    -- high-DPI displays and big TVs. Viewport clamp always wins.
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local rawW,rawH=math.floor(760*scale),math.floor(600*scale); local sw=getPlayerScreenWidth(playerNum); local sh=getPlayerScreenHeight(playerNum)
    local width=math.min(rawW, math.max(1, sw-40)); local height=math.min(rawH, math.max(1, sh-40))
    local left=getPlayerScreenLeft(playerNum); local top=getPlayerScreenTop(playerNum)
    local window=ISCollapsableWindowJoypad:new(left+(sw-width)/2, top+(sh-height)/2, width, height)
    setmetatable(window,self); self.__index=self
    window.playerNum=playerNum; UILayout.tintSheetWindow(window)
    window.minimumWidth, window.minimumHeight = notebookMinimumSize(getTextManager():getFontHeight(UIFont.Small), sw, sh)
    window:setTitle("Knox Survivors"); window:setResizable(true); UILayout.bindInteractionWindow(window); window:updateTitle(); return window
end

function Window:fitToPlayerViewport(playerNum)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local width = math.min(math.floor(760*scale), math.max(1, sw - 40))
    local height = math.min(math.floor(600*scale), math.max(1, sh - 40))
    self.minimumWidth, self.minimumHeight = notebookMinimumSize(getTextManager():getFontHeight(UIFont.Small), sw, sh)
    self:setWidth(width)
    self:setHeight(height)
    self:setX(getPlayerScreenLeft(playerNum) + (sw - width) / 2)
    self:setY(getPlayerScreenTop(playerNum) + (sh - height) / 2)
end

-- The notebook is usually opened for one page, and a player who lives on Crew
-- & Schedule should not walk back from Base & Work every time. The last page
-- read is remembered on the module for this session only - never written to a
-- save - and an explicit viewName (an attention jump, a card button, the world
-- line) always wins over the memory.
local function rememberedViewName(panel, name)
    if panel == nil or name == nil or panel.viewList == nil then return nil end
    for _, entry in ipairs(panel.viewList) do
        if tostring(entry.name) == tostring(name) then return tostring(entry.name) end
    end
    return nil
end

function Notebook.rememberActiveView()
    local window = Notebook.window
    if window == nil or window.panel == nil or window.panel.viewList == nil
        or window.panel.getActiveViewIndex == nil then return end
    local index = window.panel:getActiveViewIndex()
    local entry = index ~= nil and window.panel.viewList[index] or nil
    if entry ~= nil and entry.name ~= nil then
        Notebook.lastViewName = tostring(entry.name)
    end
end

function Notebook.show(playerNum, viewName, attentionKey)
    playerNum=tonumber(playerNum) or 0
    -- One Knox surface per player: the notebook replaces a card or a trade
    -- window that was open, and is itself replaced when either opens.
    if UILayout ~= nil and UILayout.claimSurface ~= nil then
        pcall(UILayout.claimSurface, playerNum, "notebook", Notebook)
    end
    if Notebook.window==nil then Notebook.window=Window:new(playerNum); Notebook.window:initialise(); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:addToUIManager()
    else Notebook.rememberActiveView(); Notebook.window.playerNum=playerNum; Notebook.window:fitToPlayerViewport(playerNum); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:setVisible(true); Notebook.window:bringToTop() end
    local wanted = viewName
    if wanted == nil and Notebook.window.panel ~= nil then
        wanted = rememberedViewName(Notebook.window.panel, Notebook.lastViewName)
    end
    if wanted ~= nil and Notebook.window.panel ~= nil then
        Notebook.window.panel:activateView(tostring(wanted))
    end
    Notebook.window:refreshContent()
    if attentionKey ~= nil and Notebook.window.panel ~= nil then
        local active = Notebook.window.panel:getActiveView()
        if active ~= nil and active.focusAttentionKey ~= nil then
            active:focusAttentionKey(attentionKey)
        end
    end
    return Notebook.window
end
function Notebook.close(playerNum)
    playerNum = tonumber(playerNum) or 0
    if Notebook.window ~= nil then
        Notebook.rememberActiveView()
        Notebook.window:setVisible(false)
    end
    if UILayout ~= nil and UILayout.releaseSurface ~= nil then
        pcall(UILayout.releaseSurface, playerNum, "notebook")
    end
    return true
end
function Notebook.toggle(playerNum) if Notebook.window~=nil and Notebook.window:isVisible() then Notebook.close(playerNum) else Notebook.show(playerNum) end end
Events.OnMainMenuEnter.Add(function() if Notebook.window~=nil then Notebook.window:removeFromUIManager(); Notebook.window=nil end end)
return Notebook
