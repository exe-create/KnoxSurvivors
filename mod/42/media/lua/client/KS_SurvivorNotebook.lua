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
    local bone = inert and UILayout.theme.muted or UILayout.theme.bone
    list:drawText(trimText(list.font, item.text or "", list:getWidth() - 20 - reserve),
        10, y + 2, bone[1], bone[2], bone[3], alpha, list.font)
end

-- Rows are one hairline, not a stack of boxes: the design's geometry is one
-- rule between regions and a 2 px accent on the active row. Every notebook
-- list draws through this, so a row cannot drift away from the HUD's material.
-- A row's own category colour (a work area's kind) takes the accent while the
-- row is not the selected one; the words in the row still carry the meaning,
-- because colour is never the only signal.
local function drawListRow(list, y, item, accent)
    local theme = UILayout.theme
    local border, amber = theme.border, theme.amber
    local height = math.max(1, list.itemheight - 1)
    -- Guidance gets no rule and no accent: an empty-list row must not look like
    -- selectable content, because there is nothing behind it to select.
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

local function readableReason(value)
    local reason=tostring(value or "")
    if reason=="" then return nil end
    reason=string.gsub(reason,"_"," ")
    return string.upper(string.sub(reason,1,1))..string.sub(reason,2)
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
    return label.." — "..detail.." — priority "..tostring(task.priority or 0)
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
    self.renameBaseBtn:initialise(); self.renameBaseBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.renameBaseBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.renameBaseBtn)
    y=y+BUTTON_HGT+4
    self.infoLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y=y+FONT_HGT_SMALL+4
    self.workforceLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true); self.workforceLabel:initialise(); self:addChild(self.workforceLabel)
    y=y+FONT_HGT_SMALL+2
    self.securityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true); self.securityLabel:initialise(); self:addChild(self.securityLabel)
    y=y+FONT_HGT_SMALL+4
    self.boundaryLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.6,0.6,0.8,1,UIFont.Small,true); self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y=y+FONT_HGT_SMALL+6
    self.showHighlights=ISTickBox:new(UI_BORDER_SPACING,y,170,BUTTON_HGT,"",self,BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption("Show Highlights"); self:addChild(self.showHighlights)
    self.editBoundaryBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Edit Boundary",self,BaseView.onEditBoundary); self.editBoundaryBtn:initialise(); self.editBoundaryBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.editBoundaryBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.editBoundaryBtn)
    self.autoBoardBtn=ISButton:new(self.showHighlights:getRight()+6,y,130,BUTTON_HGT,"Board Up: Off",self,BaseView.onToggleAutoBoard); self.autoBoardBtn:initialise(); self.autoBoardBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.autoBoardBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self.autoBoardBtn.tooltip="Automatically board windows using real planks and nails from base storage. Off by default because it spends supplies."; self:addChild(self.autoBoardBtn)
    y=y+BUTTON_HGT+6
    self.zoneHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Work Areas",1,1,1,1,UIFont.Small,true); self.zoneHeading:initialise(); self:addChild(self.zoneHeading)
    y=y+FONT_HGT_SMALL+4
    self.zoneList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.NewSmall; self.zoneList.doDrawItem=BaseView.drawZone; self.zoneList.drawBorder=true; self:addChild(self.zoneList)
    y=self.zoneList:getBottom()+UI_BORDER_SPACING
    self.zonePicker=ISComboBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,self,nil); self.zonePicker:initialise()
    for _,d in ipairs(ZONE_TYPES) do self.zonePicker:addOption(d.label) end; self.zonePicker.selected=1; self:addChild(self.zonePicker)
    self.addAreaBtn=ISButton:new(self.zonePicker:getRight()+6,y,100,BUTTON_HGT,"Add Area",self,BaseView.onAddArea); self.addAreaBtn:initialise(); self.addAreaBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.addAreaBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.addAreaBtn)
    self.removeBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Remove Selected",self,BaseView.onRemove); self.removeBtn:initialise(); self.removeBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.removeBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.removeBtn)
    y=y+BUTTON_HGT+6
    self.taskHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Task Queue",1,1,1,1,UIFont.Small,true); self.taskHeading:initialise(); self:addChild(self.taskHeading)
    y=y+FONT_HGT_SMALL+4
    self.taskList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*4)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.NewSmall; self.taskList.doDrawItem=BaseView.drawTask; self.taskList.drawBorder=true; self:addChild(self.taskList)
    y=self.taskList:getBottom()+6
    self.cancelTaskBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Cancel",self,BaseView.onCancelTask)
    self.cancelTaskBtn:initialise(); self.cancelTaskBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.cancelTaskBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.cancelTaskBtn)
    self.resumeTaskBtn=ISButton:new(self.cancelTaskBtn:getRight()+6,y,110,BUTTON_HGT,"Resume",self,BaseView.onResumeTask)
    self.resumeTaskBtn:initialise(); self.resumeTaskBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.resumeTaskBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.resumeTaskBtn)
    self.residentPicker=ISComboBox:new(self.resumeTaskBtn:getRight()+6,y,160,BUTTON_HGT,self,nil); self.residentPicker:initialise(); self:addChild(self.residentPicker)
    self.assignTaskBtn=ISButton:new(self.residentPicker:getRight()+6,y,96,BUTTON_HGT,"Assign",self,BaseView.onAssignTask)
    self.assignTaskBtn:initialise(); self.assignTaskBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.assignTaskBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.assignTaskBtn)
    y=y+BUTTON_HGT+6
    self.taskDetailsBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Details",self,BaseView.onTaskDetails)
    self.taskDetailsBtn:initialise(); self.taskDetailsBtn.tooltip="Full job status and requirements. Controller: X."; self:addChild(self.taskDetailsBtn)
    self.taskList.joypadParent=self
    self.taskList:setISButtonForX(self.taskDetailsBtn)
    y=y+BUTTON_HGT+6
    self.storageLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Storage",1,1,1,1,UIFont.Small,true); self.storageLabel:initialise(); self:addChild(self.storageLabel)
    y=y+FONT_HGT_SMALL+4
    self.storageList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.storageList:initialise(); self.storageList:instantiate(); self.storageList.itemheight=BUTTON_HGT; self.storageList.font=UIFont.NewSmall; self.storageList.doDrawItem=BaseView.drawStorage; self.storageList.drawBorder=true; self:addChild(self.storageList)
    y=self.storageList:getBottom()+6
    self.bedsLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,
        "Beds",0.72,0.72,0.70,1,UIFont.NewSmall,true)
    self.bedsLabel:initialise(); self:addChild(self.bedsLabel)
    y=y+FONT_HGT_SMALL+2
    self.bedsList=ISScrollingListBox:new(UI_BORDER_SPACING,y,
        self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.bedsList:initialise(); self.bedsList:instantiate()
    self.bedsList.itemheight=BUTTON_HGT; self.bedsList.font=UIFont.NewSmall
    self.bedsList.doDrawItem=BaseView.drawStorage; self.bedsList.drawBorder=true
    self:addChild(self.bedsList)
    y=self.bedsList:getBottom()+6
    self.kitShortageLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,
        "Role kit shortages",0.72,0.72,0.70,1,UIFont.NewSmall,true)
    self.kitShortageLabel:initialise(); self:addChild(self.kitShortageLabel)
    y=y+FONT_HGT_SMALL+2
    self.kitShortageList=ISScrollingListBox:new(UI_BORDER_SPACING,y,
        self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.kitShortageList:initialise(); self.kitShortageList:instantiate()
    self.kitShortageList.itemheight=BUTTON_HGT; self.kitShortageList.font=UIFont.NewSmall
    self.kitShortageList.doDrawItem=BaseView.drawStorage
    self.kitShortageList.drawBorder=true; self:addChild(self.kitShortageList)
    y=self.kitShortageList:getBottom()+6
    -- Hours and priorities moved to the Crew tab; the Base tab keeps
    -- boundary, areas, queue and storage.
    self.hintLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true); self.hintLabel:initialise(); self.hintLabel.name="Hours and work priorities live in Crew & Schedule; stock targets and the yard live in Stores & Stock."; self:addChild(self.hintLabel)
    -- The fixed arrangement is taller than short/split-screen viewports.
    -- Let the existing tab layout adapter scroll the whole page instead of
    -- placing storage and its hint beyond the visible tab bounds.
    self.knoxContentHeight=self.hintLabel:getBottom()+UI_BORDER_SPACING
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
    local theme = UILayout.theme
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
        FONT_HGT_SMALL, "", 0.68, 0.66, 0.62, 1, UIFont.NewSmall, true)
    self.attentionSummary:initialise()
    panel:addChild(self.attentionSummary)

    self.attentionEmpty = ISLabel:new(ATTENTION_PAD,
        ATTENTION_PAD + FONT_HGT_SMALL + 6, FONT_HGT_SMALL, "",
        0.72, 0.72, 0.70, 1, UIFont.NewSmall, true)
    self.attentionEmpty:initialise()
    panel:addChild(self.attentionEmpty)

    self.attentionRows = {}
    for index = 1, 3 do
        local y = ATTENTION_PAD + FONT_HGT_SMALL + 4
            + (index - 1) * ATTENTION_ROW_HEIGHT
        local label = ISLabel:new(ATTENTION_PAD, y, ATTENTION_ROW_HEIGHT,
            "", 1, 1, 1, 1, UIFont.NewSmall, true)
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
    self.attentionSummary.name = trimText(UIFont.NewSmall,
        self.attentionSummaryText or "", summaryLimit)
    local summaryWidth = getTextManager():MeasureStringX(
        UIFont.NewSmall, self.attentionSummary.name)
    self.attentionSummary:setX(width - ATTENTION_PAD - summaryWidth)
    self.attentionSummary:setY(ATTENTION_PAD)
    self.attentionEmpty:setWidth(width - ATTENTION_PAD * 2)
    self.attentionEmpty.name = trimText(UIFont.NewSmall,
        self.attentionEmptyText or "", width - ATTENTION_PAD * 2)
    for index, row in ipairs(self.attentionRows or {}) do
        local y = ATTENTION_PAD + FONT_HGT_SMALL + 4
            + (index - 1) * ATTENTION_ROW_HEIGHT
        row.label:setX(ATTENTION_PAD)
        row.label:setY(y)
        row.label:setWidth(labelWidth)
        row.label.name = trimText(UIFont.NewSmall,
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
        summary = tostring(base.name or "Home") .. " · empty"
        empty = "No residents are staying here."
    elseif count == 0 then
        summary = tostring(base.name or "Home") .. " · all clear"
        empty = tostring(residents) .. (residents == 1 and " resident · " or " residents · ")
            .. tostring(zones) .. (zones == 1 and " work area · " or " work areas · ")
            .. tostring(posts) .. (posts == 1 and " security post" or " security posts")
    else
        summary = tostring(base.name or "Home") .. " · " .. tostring(count)
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
        if self.knoxOpenStores ~= nil then
            self.knoxOpenStores()
        else
            self:revealAttentionList(self.storageList)
        end
        return
    end
    local list, predicate
    if item.action == "review_tasks" then
        list = self.taskList
        predicate = function(row)
            local task = row ~= nil and row.item or nil
            return type(task) == "table" and task.state == "blocked"
        end
    elseif item.action == "review_storage" then
        list = self.storageList
        predicate = function(row)
            local key = tostring(row ~= nil and row.knoxKey or "")
            return string.sub(key, 1, 10) == "unshelved:"
                or key == "warn" or key == "misfiled"
        end
    elseif item.action == "review_beds" then
        list = self.bedsList
        predicate = function(row)
            return string.find(tostring(row ~= nil and row.text or ""),
                "no bed assigned", 1, true) ~= nil
        end
    elseif item.action == "review_kits" then
        list = self.kitShortageList
        predicate = function(row)
            return string.sub(tostring(row ~= nil and row.knoxKey or ""),
                1, 4) == "kit:"
        end
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
        { self.zoneList, self.taskList, self.storageList, self.bedsList, self.kitShortageList })
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
    local win = self:getWindow()
    local baseId = notebookBaseId(win, playerNum, pid)
    if baseId == nil then return nil end
    return KnoxPersistence.getBase(baseId)
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
        and "Automatic boarding on — residents will use planks and nails."
        or "Automatic boarding off — order barricades from the base menu.")
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
    self.taskList:clear(); self.storageList:clear(); self.bedsList:clear(); self.kitShortageList:clear()
    self.residentIds = {}
    self.residentPicker:clear(); self.residentPicker.selected = 1
    if not base then
        self.infoLabel.name=trimText(UIFont.Small,
            "No home base — right-click inside a building to establish one.", self.width-UI_BORDER_SPACING*2)
        self.workforceLabel.name=""; self.securityLabel.name=""; self.boundaryLabel.name=""
        self.zoneList:clear(); addRow(self.zoneList,"none","No base established"); self.showHighlights:setSelected(1,false)
        -- ISTickBox exposes `enable` directly in Build 42; setEnable belongs
        -- to ISButton only.
        self.showHighlights.enable=false; self.editBoundaryBtn:setEnable(false); self.addAreaBtn:setEnable(false); self.removeBtn:setEnable(false)
        self.renameBaseBtn:setEnable(false)
        self.autoBoardBtn:setEnable(false); self.autoBoardBtn:setTitle("Board Up: Off")
        self.residentPicker:addOption("No residents")
        addRow(self.taskList,"none","No base"); addRow(self.storageList,"none","No base")
        self.bedsLabel.name="Beds"; addRow(self.bedsList,"none","No base")
        self.kitShortageLabel.name="Role kit shortages"; addRow(self.kitShortageList,"none","No base")
        self.taskHeading.name="No base"; self.storageLabel.name="No base"
        self.infoLabel.name=""
        self:refreshAttention(nil, {})
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
    local queued,claimed=0,0
    for _,t in pairs(base.tasks or {}) do
        if t.state=="queued" then queued=queued+1
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
    self.infoLabel.name=trimText(UIFont.Small,
        "Kind: " .. tostring(kindLabel) .. "  |  Order: " .. tostring(orderLabel)
        .. "  |  Residents: " .. #residents .. "  |  Work areas: " .. zones
        .. "  |  Tasks: " .. queued .. " waiting, " .. claimed .. " active",
        self.width-UI_BORDER_SPACING*2)
    self.workforceLabel.name=trimText(UIFont.NewSmall,
        "Workforce: " .. tostring(workforce.working or 0) .. " working, "
        .. tostring(workforce.idle or 0) .. " idle, "
        .. tostring(workforce.resting or 0) .. " resting",
        self.width-UI_BORDER_SPACING*2)
    local guardPosts, patrolRoutes = tonumber(security.guardPosts) or 0, tonumber(security.patrolRoutes) or 0
    if guardPosts + patrolRoutes == 0 then
        self.securityLabel.name=trimText(UIFont.NewSmall,
            "Security: no guard posts — mark Guard and Patrol areas below",
            self.width-UI_BORDER_SPACING*2)
    else
        self.securityLabel.name=trimText(UIFont.NewSmall,
            "Security: " .. tostring(security.activeGuard) .. "/" .. guardPosts .. " guard posts, "
            .. tostring(security.activePatrol) .. "/" .. patrolRoutes .. " patrols"
            .. " (" .. tostring(security.staffed) .. "/" .. tostring(security.required) .. " staffed)",
            self.width-UI_BORDER_SPACING*2)
    end
    local area=base.territory or base.home or {}
    self.boundaryLabel.name=trimText(UIFont.Small,
        "Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?")
            .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?")
            .. "  (all floors)", self.width-UI_BORDER_SPACING*2)
    self.showHighlights:setSelected(1, KnoxBaseHighlights.isEnabled(playerNum))
    self.showHighlights.enable=true; self.editBoundaryBtn:setEnable(true); self.addAreaBtn:setEnable(true); self.removeBtn:setEnable(self.zoneList.selected and self.zoneList.selected > 0)
    self.zoneList:clear()
    local list={}; for _,z in pairs(base.zones or {}) do if z and z.enabled~=false then list[#list+1]=z end end
    table.sort(list, function(a,b) if tostring(a.type)==tostring(b.type) then return tostring(a.label or a.type) < tostring(b.label or b.type) end return tostring(a.type) < tostring(b.type) end)
    if #list==0 then addRow(self.zoneList,"none","No work areas — pick a type and Add Area, then drag rectangle") else
        for _,z in ipairs(list) do local w,h,total=zoneSize(z); local sz=w and ("  " .. w .. "x" .. h .. " (" .. total .. ")  at " .. z.x1 .. "," .. z.y1) or ""; addRow(self.zoneList,z.id, "  " .. tostring(KnoxPersistence.zoneDisplayLabel(z, z.type)) .. " [" .. tostring(z.type) .. "]" .. sz); self.zoneList.items[#self.zoneList.items].item={type=z.type, id=z.id} end
    end
    self:populateWork(base)
end

-- Task queue + storage for the selected base (merged old Work tab).
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
    self.taskHeading.name=trimText(UIFont.Small,
        "Tasks: " .. tostring(tasksSummary.queued or 0) .. " waiting | "
        .. tostring(tasksSummary.claimed or 0) .. " active | "
        .. tostring(tasksSummary.blocked or 0) .. " blocked",
        self.width-UI_BORDER_SPACING*2)
    local tasks={}; for _,t in pairs(base.tasks or {}) do tasks[#tasks+1]=t end
    table.sort(tasks, function(a,b) local ap=tonumber(a.priority) or 0; local bp=tonumber(b.priority) or 0; if ap==bp then return tostring(a.id) < tostring(b.id) end return ap>bp end)
    if #tasks==0 then addRow(self.taskList,"none","No work waiting — mark work areas") else for _,t in ipairs(tasks) do
        addRow(self.taskList,t.id, taskRowText(t, now))
        self.taskList.items[#self.taskList.items].item=t
    end end
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
    self.storageLabel.name=trimText(UIFont.Small,
        "Storage: " .. tostring(#filteredContainers) .. " filtered | "
        .. tostring(#usableContainers) .. " usable containers | " .. stockState
        .. (tapsDry and " | taps dry" or "")
        .. (unshelvedCount > 0 and (" | " .. tostring(unshelvedCount) .. " unshelved") or "")
        .. (misfiledCount > 0 and (" | " .. tostring(misfiledCount) .. " misfiled") or ""),
        self.width-UI_BORDER_SPACING*2)
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
    -- The yard is a storage destination like any other, so it belongs in the
    -- same list; the owner decides the words, including when it is empty.
    local depotLine = KnoxBaseStorage.depotSummaryLine(KnoxBaseStorage.depotStatus(base))
    if depotLine ~= nil then addRow(self.storageList, "depot", depotLine) end
    addRow(self.storageList,"food-help","Residents route real items using each container's filters")
    local reserveByCategory={}
    for _,reserve in ipairs(settlement~=nil and settlement.reserves or {}) do reserveByCategory[reserve.category]=reserve end
    for _,cat in ipairs(KnoxBaseStorage.RESOURCE_CATEGORIES) do
        local c=tonumber(summary.totals[cat]) or 0
        local reserve=reserveByCategory[cat]
        if c>0 or reserve~=nil then
            local text=tostring(RESOURCE_LABELS[cat] or cat)..": "..tostring(c)
            if reserve~=nil then
                text=text.." / "..tostring(reserve.target)
                if reserve.missing>0 then text=text.." — needs "..tostring(reserve.missing) end
            end
            if cat=="water" and tapsDry then text=text.." — taps dry" end
            addRow(self.storageList,cat,text); any=true
        end
    end
    local other=tonumber(summary.totals.other) or 0; if other>0 then addRow(self.storageList,"other","Other: "..other); any=true end
    if not any then addRow(self.storageList,"none","No supplies in loaded containers") end
    if summary.unavailablePolicies>0 then addRow(self.storageList,"warn", tostring(summary.unavailablePolicies) .. " container(s) outside loaded area") end
    -- A haul that reached base but could not be shelved, with the real cause, so
    -- the leader sees it without having caught the feed line at the time.
    for _, problem in ipairs(type(unshelved) == "table" and unshelved or {}) do
        local identity=KnoxPersistence.getSurvivorIdentity(problem.survivorId) or {}
        local who=(tostring(identity.forename or "") .. " " .. tostring(identity.surname or ""))
            :gsub("^%s+", ""):gsub("%s+$", "")
        if who == "" then who = "A resident" end
        addRow(self.storageList, "unshelved:" .. tostring(problem.survivorId),
            who .. " can't shelve " .. tostring(problem.itemLabel or "the supplies") .. " — "
            .. KnoxBaseStorage.depositProblemLabel(problem.reason))
    end
    -- Supplies filed outside their category are not a problem: the matching
    -- shelf was full. The count is where the player sees the workaround.
    if misfiledCount > 0 then
        addRow(self.storageList, "misfiled", tostring(misfiledCount)
            .. " item(s) sit where their filters don't name them — a full shelf put them there")
    end
    self.bedsList:clear()
    local bedRows=KnoxBaseManager.bedRoster ~= nil
        and KnoxBaseManager.bedRoster(base, base.ownerId) or {}
    local bedAssigned=0
    for _, row in ipairs(bedRows) do
        local bed=row.bed
        local text
        if bed ~= nil then
            bedAssigned=bedAssigned+1
            local room = row.room ~= nil and row.room ~= ""
                and (" in " .. tostring(row.room)) or ""
            text=row.name.." — bed at "..tostring(bed.x)..","..tostring(bed.y)
                ..", floor "..tostring(bed.z)..room
        else
            text=row.name.." — no bed assigned"
        end
        addRow(self.bedsList,"bed:"..tostring(row.id),text)
    end
    if #bedRows == 0 then
        addRow(self.bedsList,"none","No residents to assign.")
        self.bedsLabel.name="Beds: no residents to assign."
    else
        self.bedsLabel.name=trimText(UIFont.NewSmall,
            "Beds: "..tostring(bedAssigned).." assigned | "
            ..tostring(#bedRows-bedAssigned).." without",
            self.width-UI_BORDER_SPACING*2)
    end
    self.kitShortageList:clear()
    local kitEntries=KnoxBaseStorage.roleKitShortages ~= nil
        and KnoxBaseStorage.roleKitShortages(base, kitRoster) or {}
    local kitShown=0
    local kitUnknown=0
    table.sort(kitEntries, function(first, second)
        local firstRank=first.status == "shortage" and 1 or 2
        local secondRank=second.status == "shortage" and 1 or 2
        if firstRank ~= secondRank then return firstRank < secondRank end
        return tostring(first.id) < tostring(second.id)
    end)
    for _, entry in ipairs(kitEntries) do
        if entry.status == "shortage" or entry.status == "unknown" then
            local roleDefinition=entry.role ~= nil and KnoxOrderCatalog.baseRoles
                and KnoxOrderCatalog.baseRoles[entry.role] or nil
            local roleLabel=roleDefinition ~= nil and roleDefinition.label
                or tostring(entry.role or "Resident")
            local name=residentDisplayName(entry.id)
            local text
            if entry.status == "unknown" then
                text=name .. " (" .. roleLabel .. "): out of contact — readiness unknown."
            else
                local sentence=KnoxOrderCatalog.roleKitStatusText ~= nil
                    and KnoxOrderCatalog.roleKitStatusText(entry.role, entry.gear,
                        entry.missing, entry.stock) or "Kit: readiness unavailable."
                text=name .. ": " .. sentence
            end
            addRow(self.kitShortageList, "kit:" .. tostring(entry.id), text)
            if entry.status == "shortage" then
                kitShown=kitShown+1
            else
                kitUnknown=kitUnknown+1
            end
        end
    end
    if kitShown + kitUnknown == 0 then
        addRow(self.kitShortageList, "none", "No assigned role-kit shortages.")
    end
    self.kitShortageLabel.name="Role kit shortages: " .. tostring(kitShown)
        .. (kitUnknown > 0 and (" | unknown: " .. tostring(kitUnknown)) or "")
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
function BaseView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Crew panel: party and residents. The roster is split in two so a
-- survivor sent home visibly changes sections: party travels with you,
-- residents live at the selected base. The selected entry from either
-- list gets a priority row, a 24-hour schedule strip, role and party
-- controls below. Priorities and hours save immediately; job roles still
-- apply where automatic.
local CrewView = ISPanelJoypad:derive("KnoxNotebookCrewView")
function CrewView:initialise() ISPanelJoypad.initialise(self) end
function CrewView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y = UI_BORDER_SPACING
    self.partyLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Party — traveling with you",1,1,1,1,UIFont.Small,true); self.partyLabel:initialise(); self:addChild(self.partyLabel)
    y = y + FONT_HGT_SMALL + 2
    self.partyList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*2)
    self.partyList:initialise(); self.partyList:instantiate(); self.partyList.itemheight=BUTTON_HGT; self.partyList.font=UIFont.NewSmall; self.partyList.doDrawItem=self.drawEntry; self.partyList.drawBorder=true; self.partyList.joypadParent=self; self:addChild(self.partyList)
    y = self.partyList:getBottom() + 4
    self.residentsLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Base residents — select one to edit work and schedule",1,1,1,1,UIFont.Small,true); self.residentsLabel:initialise(); self:addChild(self.residentsLabel)
    y = y + FONT_HGT_SMALL + 2
    self.resList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.resList:initialise(); self.resList:instantiate(); self.resList.itemheight=BUTTON_HGT; self.resList.font=UIFont.NewSmall; self.resList.doDrawItem=self.drawEntry; self.resList.drawBorder=true; self.resList.joypadParent=self; self:addChild(self.resList)
    y = self.resList:getBottom() + 6
    self.priorityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.priorityLabel:initialise(); self.priorityLabel.name="Work preferences — High / Normal / Low / Disabled"; self:addChild(self.priorityLabel)
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
        btn.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
            b = UILayout.theme.border[3], a = 0.80 }; self:addChild(btn)
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
        btn.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
            b = UILayout.theme.border[3], a = 0.80 }
        local color = SCHEDULE_COLORS[tool.key]
        setPersistentButtonFill(btn, color, 0.9)
        btn.knoxTool = tool.key
        self:addChild(btn)
        self.scheduleTools[tool.key] = btn
    end
    y = y + math.ceil(#SCHEDULE_TOOLS / toolColumns) * (BUTTON_HGT + 2) + 4
    self.scheduleBlockBtns = {}
    -- Measure the real labels instead of assuming 120px: "Afternoon
    -- (12pm–4pm)" is wider than the word it replaced, and a fixed minimum
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
        btn.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
            b = UILayout.theme.border[3], a = 0.80 }
        btn.knoxBlock = index
        self:addChild(btn)
        self.scheduleBlockBtns[index] = btn
    end
    y = y + blockRows * (BUTTON_HGT + 2) + 4
    self.saveScheduleBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Save Hours",self,CrewView.onSaveSchedule); self.saveScheduleBtn:initialise(); self.saveScheduleBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.saveScheduleBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.saveScheduleBtn)
    self.colonyPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Colony Day",self,CrewView.onPresetColony); self.colonyPresetBtn:initialise(); self.colonyPresetBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.colonyPresetBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.colonyPresetBtn)
    self.nightPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Night Shift",self,CrewView.onPresetNight); self.nightPresetBtn:initialise(); self.nightPresetBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.nightPresetBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.nightPresetBtn)
    self.roleHoursBtn=ISButton:new(0,y,110,BUTTON_HGT,"Role Hours",self,CrewView.onPresetRole); self.roleHoursBtn:initialise(); self.roleHoursBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.roleHoursBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.roleHoursBtn)
    self.copyPicker=ISComboBox:new(0,y,170,BUTTON_HGT,self,nil); self.copyPicker:initialise(); self:addChild(self.copyPicker)
    self.copyScheduleBtn=ISButton:new(0,y,64,BUTTON_HGT,"Copy",self,CrewView.onCopySchedule); self.copyScheduleBtn:initialise(); self.copyScheduleBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.copyScheduleBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self.copyScheduleBtn.tooltip="Copy this resident's saved hours to everyone, one role or one other resident."; self:addChild(self.copyScheduleBtn)
    self.guardOverrideBtn=ISButton:new(0,y,116,BUTTON_HGT,"Guard Tonight",self,CrewView.onGuardTonight); self.guardOverrideBtn:initialise(); self.guardOverrideBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.guardOverrideBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.guardOverrideBtn)
    self.clearPresetBtn=ISButton:new(0,y,80,BUTTON_HGT,"Clear Draft",self,CrewView.onPresetClear); self.clearPresetBtn:initialise(); self.clearPresetBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.clearPresetBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.clearPresetBtn)
    self.resetPrioritiesBtn=ISButton:new(0,y,120,BUTTON_HGT,"Reset Work",self,CrewView.onResetPriorities); self.resetPrioritiesBtn:initialise(); self.resetPrioritiesBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.resetPrioritiesBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.resetPrioritiesBtn)
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
    local function groupCaption(text, top)
        local caption = ISLabel:new(UI_BORDER_SPACING, top, FONT_HGT_SMALL, text,
            UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3], 1, UIFont.NewSmall, true)
        caption:initialise()
        self:addChild(caption)
        return top + FONT_HGT_SMALL + 2
    end
    y = groupCaption("Hours (draft) — Save Hours applies them.", y)
    y = flowControls({ self.colonyPresetBtn, self.nightPresetBtn, self.roleHoursBtn,
        self.clearPresetBtn, self.saveScheduleBtn }, y) + 2
    self.scheduleStatus=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true); self.scheduleStatus:initialise(); self:addChild(self.scheduleStatus)
    y = y + FONT_HGT_SMALL + 4
    -- One control per meaning. They are created here and placed by the
    -- captioned groups below, so a button cannot drift into the wrong section.
    local function crewButton(label, handler, width, hint)
        local button=ISButton:new(0,0,width,BUTTON_HGT,label,self,handler)
        button:initialise(); button.tooltip=hint
        button.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}
        button.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}
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
        "Kit: no resident selected.",0.72,0.72,0.70,1,UIFont.NewSmall,true)
    self.kitStatus:initialise(); self:addChild(self.kitStatus)
    y = self.kitStatus:getBottom() + 2
    self.knoxContentHeight = self.kitStatus:getBottom() + UI_BORDER_SPACING
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
    if #self.partyIds==0 then addRow(self.partyList,"none","No party — recruit survivors") end
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
    for index, block in ipairs(KnoxOrderCatalog.scheduleBlocks) do
        local btn = self.scheduleBlockBtns ~= nil and self.scheduleBlockBtns[index] or nil
        if btn ~= nil then
            local assignment = type(draft) == "table"
                and KnoxOrderCatalog.scheduleBlockValue(draft, index) or nil
            local color = SCHEDULE_COLORS[assignment] or SCHEDULE_COLORS.anything
            setPersistentButtonFill(btn, color, 0.85)
            local title = draft == nil and "—"
                or (SCHEDULE_BLOCK_LABELS[assignment] or "Mixed")
            local current = now ~= nil and now >= block.startHour
                and now < block.startHour + 4
            if current and draft ~= nil then
                btn.borderColor = { r = UILayout.theme.green[1], g = UILayout.theme.green[2], b = UILayout.theme.green[3], a = 0.95 }
                title = title .. "*"
            else
                btn.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
            b = UILayout.theme.border[3], a = 0.80 }
            end
            btn:setTitle(KnoxOrderCatalog.scheduleBlockLabel(block) .. ": " .. title)
            btn:setEnable(draft ~= nil)
        end
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
        return "Kit: out of contact — readiness unknown."
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
            return "Unsaved changes — select Save Hours."
        end
    end
    if activeOverride ~= nil then
        local label = SCHEDULE_ASSIGNMENT_LABELS[activeOverride.assignment] or "Temporary"
        return "Temporary " .. string.lower(label) .. " until "
            .. string.format("%02d:00", math.floor(activeOverride.expiresAtHours) % 24)
            .. " — saved hours unchanged."
    end
    return saved == nil and "Default schedule — Anything." or "Saved schedule."
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
    for _, col in ipairs(PRIORITY_COLUMNS) do
        local btn = self.crewCells[col.key]
        local value = map ~= nil and map[col.key] or "normal"
        local title = PRIORITY_STATE_LABELS[value] or "N"
        local color = PRIORITY_COLORS[value] or PRIORITY_COLORS.normal
        btn:setTitle(col.label .. ":" .. title)
        btn.tooltip = CrewView.priorityHint(col.label, value)
        setPersistentButtonFill(btn, color, 0.9)
        btn:setEnable(resident)
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
            btn.borderColor = { r = UILayout.theme.border[1], g = UILayout.theme.border[2],
            b = UILayout.theme.border[3], a = 0.80 }
        end
        btn:setEnable(resident)
    end
    self:paintScheduleStrip(draft)
    if id == nil then
        self.scheduleResidentLabel.name = "Resident: none selected"
        self.scheduleLabel.name = "Select a base resident to edit a schedule."
        self.scheduleStatus.name = ""
    else
        self.scheduleResidentLabel.name = trimText(UIFont.Small,
            "Resident: " .. self:crewDisplayName(id),
            self.width - UI_BORDER_SPACING * 2)
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
            and ("NOW " .. string.format("%02d", hour) .. ": "
                .. tostring(SCHEDULE_ASSIGNMENT_LABELS[assignment] or assignment))
            or "IN-GAME TIME UNAVAILABLE"
        self.scheduleLabel.name = trimText(UIFont.Small,
            nowLabel .. "  |  Paint: " .. selectedTool,
            self.width - UI_BORDER_SPACING * 2)
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
        local amber = UILayout.theme.amber
        local pending = resident == true and id ~= nil and copyClean ~= true
        pcall(function()
            if pending then
                self.scheduleStatus:setColour(amber[1], amber[2], amber[3], 1)
            else
                self.scheduleStatus:setColour(UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3], 1)
            end
        end)
    end
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
        self.kitStatus.name = trimText(UIFont.NewSmall, kitText,
            self.width - UI_BORDER_SPACING * 2)
    end
end

function CrewView:onCrewPriorityCell(button)
    local group = button ~= nil and button.knoxGroup or nil
    local residentId = self:selectedCrewId()
    if group == nil or residentId == nil then return end
    local map = KnoxPersistence.getWorkPreferences ~= nil
        and KnoxPersistence.getWorkPreferences(residentId) or {}
    if type(map) ~= "table" then map = {} end
    local current = map[group] or "normal"
    local nextState = PRIORITY_STATE_NEXT[current] or "high"
    if nextState == "normal" then map[group] = nil else map[group] = nextState end
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
local MissionsView = ISPanelJoypad:derive("KnoxNotebookMissionsView")
function MissionsView:initialise() ISPanelJoypad.initialise(self) end
function MissionsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2-BUTTON_HGT-UI_BORDER_SPACING)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    self.toPartyBtn=ISButton:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Party",self,MissionsView.onSupplyToParty); self.toPartyBtn:initialise(); self.toPartyBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.toPartyBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.toPartyBtn)
    self.toPartyBtn.tooltip = "Send the selected mission's supplies to the party, not to the base."
    self.toBaseBtn=ISButton:new(self.toPartyBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Base",self,MissionsView.onSupplyToBase); self.toBaseBtn:initialise(); self.toBaseBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.toBaseBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.toBaseBtn)
    self.toBaseBtn.tooltip = "Send the selected mission's supplies to this base's storage."
    self.resumeBtn=ISButton:new(self.toBaseBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,120,BUTTON_HGT,"Resume Duty",self,MissionsView.onSupplyResume); self.resumeBtn:initialise(); self.resumeBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.resumeBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.resumeBtn)
    self.resumeBtn.tooltip = "Return this survivor to normal duty once their mission is done."
    -- Dispatching was only reachable from the world menu. A destination is
    -- picked from the buildings the player can actually see, because the
    -- dispatch owner needs a loaded square for the label, watchability and ETA.
    local dispatchX=math.min(self.resumeBtn:getRight()+6, self.width-UI_BORDER_SPACING-116)
    self.dispatchBtn=ISButton:new(dispatchX,self.list:getBottom()+UI_BORDER_SPACING,116,BUTTON_HGT,"Dispatch...",self,MissionsView.onDispatch); self.dispatchBtn:initialise(); self.dispatchBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.dispatchBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.dispatchBtn)
    self.dispatchBtn.tooltip = "Send a survivor or squad away on a mission. Opens the existing dispatch picker."
end
function MissionsView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; drawListRow(self,y,item); drawListText(self,y,item,a); return y+self.itemheight
end
function MissionsView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear()
    local player = getSpecificPlayer(playerNum)
    local ownerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if ownerId == nil then return end
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
                local text = tostring(progress.missionType or "mission")
                    .. " | " .. tostring(progress.statusLabel or progress.state or "unknown")
                    .. " | " .. tostring(#(progress.memberIds or {})) .. " member(s)"
                    .. " | " .. tostring(progress.destination and progress.destination.label or "unknown")
                if progress.state == "outbound" then
                    text = text .. " | " .. string.format("%.1fh remaining", remaining)
                end
                addRow(self.list,id, text)
            end
        end
    end
    if count == 0 and #finished == 0 then
        addRow(self.list,"none", "No active trips. Give survival orders from the Crew tab or a survivor's Orders menu.")
    end
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
                addRow(self.list, "supply:" .. tostring(id),
                    name .. "  |  Supply run: " .. tostring(kind)
                    .. "  |  " .. tostring(base.name or base.id)
                    .. "  |  " .. string.format("%.1fh left", remaining))
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
                    addRow(self.list,id, snapshot.displayName .. " | "
                        .. snapshot.roleLabel .. " | " .. snapshot.activity)
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
            addRow(self.list, "result:" .. tostring(entry.id), text)
        end
    end
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
    local targets = rawget(_G, "KnoxMissionTargets")
    if targets == nil or targets.dispatchFlow == nil then return end
    targets.dispatchFlow(self.playerNum or 0)
end

function MissionsView:prerender()
    ISPanelJoypad.prerender(self)
    local id = self:selectedSupplyId()
    if self.toPartyBtn then self.toPartyBtn:setEnable(id ~= nil) end
    if self.toBaseBtn then self.toBaseBtn:setEnable(id ~= nil) end
    if self.resumeBtn then self.resumeBtn:setEnable(id ~= nil) end
    if self.dispatchBtn then
        self.dispatchBtn:setEnable(rawget(_G, "KnoxMissionTargets") ~= nil)
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
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    local cardY = self.list:getBottom() + UI_BORDER_SPACING
    self.cardPortrait=ISImage:new(UI_BORDER_SPACING,cardY,44,44,nil); self.cardPortrait:initialise(); self:addChild(self.cardPortrait)
    self.cardLine1=ISLabel:new(UI_BORDER_SPACING+52,cardY,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.cardLine1:initialise(); self:addChild(self.cardLine1)
    self.cardLine2=ISLabel:new(UI_BORDER_SPACING+52,cardY+FONT_HGT_SMALL+4,BUTTON_HGT,"",UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true); self.cardLine2:initialise(); self:addChild(self.cardLine2)
    self.memberList=ISScrollingListBox:new(UI_BORDER_SPACING,cardY+52,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.memberList:initialise(); self.memberList:instantiate(); self.memberList.itemheight=BUTTON_HGT; self.memberList.font=UIFont.NewSmall; self.memberList.doDrawItem=self.drawEntry; self.memberList.drawBorder=true; self:addChild(self.memberList)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.memberList:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,WorldView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}; self.viewBtn.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}; self:addChild(self.viewBtn)
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
                    other = outward and raid.targetBaseId or raid.sourceFactionId
                end
                entries[#entries + 1] = {
                    at = tonumber(raid.atHours) or 0,
                    text = (outward and "Raided " or "Raid on ")
                        .. tostring(other or "unknown")
                        .. " — " .. tostring(raid.outcome or "unknown"),
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
                        -- with a cause and an ETA, not as a raw event phase —
                        -- and once it has ended, as what it cost instead of a
                        -- stale "arriving now" the warning stamp would give.
                        local warning = type(event.warning) == "table" and event.warning or nil
                        local aftermath = events.raidAftermathText ~= nil
                            and events.raidAftermathText(event, now) or nil
                        local threat = aftermath or (warning ~= nil and events.raidThreatText ~= nil
                            and events.raidThreatText(warning, now) or nil)
                        entries[#entries + 1] = {
                            at = tonumber(event.lastChangedAtHours) or 0,
                            text = threat or (tostring(event.kind or "event") .. " — "
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
    return table.concat(lines, "  ·  ")
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
    if name == "" then name = tostring(memberId) end
    return name
end

function WorldView:factionHome(faction)
    local base = faction.homeBaseId and KnoxPersistence.getBase(faction.homeBaseId) or nil
    local camp = KnoxPersistence.getFactionCamp ~= nil and KnoxPersistence.getFactionCamp(faction.id) or nil
    if base ~= nil then return "Base: " .. tostring(base.name or base.id) end
    if camp ~= nil then return "Shelter: " .. tostring(camp.name or camp.id) end
    return "No home yet"
end

function WorldView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear(); self.memberList:clear(); self.memberIds = {}
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local playerFaction = playerId ~= nil and KnoxPersistence.getPlayerFaction ~= nil
        and KnoxPersistence.getPlayerFaction(playerId) or nil
    -- Non-player factions first, then unaffiliated known survivors.
    local factions = {}
    for _, faction in pairs(KnoxPersistence.getFactions() or {}) do
        if faction ~= nil and faction.kind ~= "player" then factions[#factions + 1] = faction end
    end
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
        local row = addRow(self.list, faction.id, tostring(faction.name or faction.id)
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
            .. tostring(#drifters) .. " known" .. "  |  —")
    end
    if #factions == 0 and #drifters == 0 then
        addRow(self.list, "none", "No other factions yet — survivors you meet will appear here")
    end
    self.factions = factions
    self.drifters = drifters
    self.playerFaction = playerFaction
    self:populateMembers()
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
        self.cardLine1.name = "Select a faction above"
        self.cardLine2.name = ""
        addRow(self.memberList, "none", "Select a faction above")
        return
    end
    if faction == "drifters" then
        self.cardPortrait.texture = nil
        self.cardLine1.name = "Drifters — unaffiliated survivors you have met"
        self.cardLine2.name = tostring(#(self.drifters or {})) .. " known"
    else
        local standing = "neutral"
        if self.playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(self.playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
        end
        local members, residents, guards = self:factionStats(faction)
        local leaderName = faction.leaderId ~= nil and self:memberName(faction.leaderId) or "Unknown"
        self.cardPortrait.texture = self:leaderPortrait(faction.leaderId, self.playerNum)
        self.cardLine1.name = trimText(UIFont.Small,
            "Leader: " .. leaderName .. "  |  " .. standing .. "  |  " .. self:factionHome(faction),
            self.width - UI_BORDER_SPACING * 2 - 60)
        self.cardLine2.name = trimText(UIFont.NewSmall,
            tostring(members) .. " members (" .. tostring(residents) .. " settled, "
            .. tostring(guards) .. " watch)  |  " .. self:factionHistory(faction, now),
            self.width - UI_BORDER_SPACING * 2 - 60)
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
local StoresView = ISPanelJoypad:derive("KnoxNotebookStoresView")
function StoresView:initialise() ISPanelJoypad.initialise(self) end
function StoresView:getWindow() return self:getParent():getParent() end
function StoresView:createChildren()
    local y=UI_BORDER_SPACING
    self.targetsLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,
        "Stock targets - what this home keeps on hand ( * = your number )",
        0.72,0.72,0.70,1,UIFont.NewSmall,true)
    self.targetsLabel:initialise(); self:addChild(self.targetsLabel)
    y=y+FONT_HGT_SMALL+4
    self.targetList=ISScrollingListBox:new(UI_BORDER_SPACING,y,
        self.width-UI_BORDER_SPACING*2,BUTTON_HGT*9)
    self.targetList:initialise(); self.targetList:instantiate()
    self.targetList.itemheight=BUTTON_HGT; self.targetList.font=UIFont.NewSmall
    self.targetList.doDrawItem=BaseView.drawStorage
    self.targetList.drawBorder=true; self:addChild(self.targetList)
    y=self.targetList:getBottom()+6
    self.raiseBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Raise",self,StoresView.onRaise)
    self.raiseBtn:initialise(); self.raiseBtn.tooltip="Keep more of the selected supply on hand."
    self:addChild(self.raiseBtn)
    self.lowerBtn=ISButton:new(self.raiseBtn:getRight()+6,y,110,BUTTON_HGT,"Lower",self,StoresView.onLower)
    self.lowerBtn:initialise(); self.lowerBtn.tooltip="Keep less of the selected supply on hand."
    self:addChild(self.lowerBtn)
    self.clearBtn=ISButton:new(self.lowerBtn:getRight()+6,y,118,BUTTON_HGT,"Clear Targets",self,StoresView.onClear)
    self.clearBtn:initialise(); self.clearBtn.tooltip="Drop every number you set and use the planner defaults again."
    self:addChild(self.clearBtn)
    for _, button in ipairs({self.raiseBtn,self.lowerBtn,self.clearBtn}) do
        button.borderColor={r=UILayout.theme.border[1],g=UILayout.theme.border[2],b=UILayout.theme.border[3],a=0.8}
        button.backgroundColor={r=UILayout.theme.charcoal[1],g=UILayout.theme.charcoal[2],b=UILayout.theme.charcoal[3],a=0.92}
    end
    y=y+BUTTON_HGT+6
    self.yardLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",
        0.72,0.72,0.70,1,UIFont.NewSmall,true)
    self.yardLabel:initialise(); self:addChild(self.yardLabel)
    y=y+FONT_HGT_SMALL+2
    self.hintLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,
        "Pick a line, then raise or lower it. A target asks a resident to fetch; it never caps the shelves.",
        UILayout.theme.muted[1],UILayout.theme.muted[2],UILayout.theme.muted[3],1,UIFont.NewSmall,true)
    self.hintLabel:initialise(); self:addChild(self.hintLabel)
end
function StoresView:selectedBase(playerNum, pid)
    local baseId=notebookBaseId(self:getWindow(), playerNum, pid)
    if baseId == nil then return nil end
    return KnoxPersistence.getBase(baseId)
end
function StoresView:populate(playerNum)
    local playerNum=playerNum or self.playerNum or 0
    local player=getSpecificPlayer(playerNum)
    local pid=player~=nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base=pid~=nil and self:selectedBase(playerNum,pid) or nil
    self.baseId=base~=nil and base.id or nil
    self.playerId=pid
    self.targetList:clear()
    self.rows={}
    if base==nil then
        self.targetsLabel.name="Stock targets - no home base yet"
        self.yardLabel.name=""
        self.raiseBtn:setEnable(false); self.lowerBtn:setEnable(false); self.clearBtn:setEnable(false)
        addRow(self.targetList,"none","Establish a base first")
        return
    end
    local overrides=KnoxPersistence.getBaseReserveTargets ~= nil
        and KnoxPersistence.getBaseReserveTargets(base.id) or nil
    local now=getGameTime()~=nil and getGameTime():getWorldAgeHours() or 0
    local settlement=KnoxBaseJobs ~= nil and KnoxBaseJobs.settlementSummary ~= nil
        and KnoxBaseJobs.settlementSummary(base, now) or nil
    local summary=settlement~=nil and settlement.storage or KnoxBaseStorage.summarize(base)
    local totals=summary~=nil and summary.totals or {}
    local residents=settlement~=nil and settlement.workforce~=nil
        and tonumber(settlement.workforce.residents) or 1
    local statuses=KnoxBaseSupplyPlanner~=nil and KnoxBaseSupplyPlanner.reserveStatus~=nil
        and KnoxBaseSupplyPlanner.reserveStatus(totals,residents,overrides,
            settlement~=nil and settlement.waterSource or nil) or {}
    local hasOverride=false
    for _, status in ipairs(statuses) do
        local label=tostring(RESOURCE_LABELS[status.category] or status.category)
        local text=label..": "..tostring(status.current).." / "..tostring(status.target)
        if status.missing>0 then text=text.." - needs "..tostring(status.missing) end
        if overrides~=nil and overrides[status.category]~=nil then
            text=text.." *"; hasOverride=true
        end
        self.rows[#self.rows+1]={text=text,knoxKey=status.category,target=status.target,current=status.current}
        self.targetList:addItem(text,self.rows[#self.rows])
    end
    if self.selectedCategory~=nil then
        for index,row in ipairs(self.rows) do
            if row.knoxKey==self.selectedCategory then self.targetList.selected=index break end
        end
    end
    self.raiseBtn:setEnable(true); self.lowerBtn:setEnable(true)
    self.clearBtn:setEnable(hasOverride)
    -- The yard is where stock leaves the shelves, so its line belongs here
    -- beside the targets rather than on the page read every morning.
    local depotLine=KnoxBaseStorage.depotSummaryLine ~= nil
        and KnoxBaseStorage.depotSummaryLine(KnoxBaseStorage.depotStatus(base)) or nil
    self.yardLabel.name=depotLine or "No yard painted yet: a log area becomes one."
end
function StoresView:changeTarget(direction)
    local row=self.rows~=nil and self.rows[self.targetList.selected or 0] or nil
    if row==nil or self.baseId==nil or self.playerId==nil then return end
    local key=row.knoxKey
    local targets=KnoxPersistence.getBaseReserveTargets ~= nil
        and KnoxPersistence.getBaseReserveTargets(self.baseId) or nil
    targets=targets or {}
    local current=tonumber(targets[key]) or tonumber(row.target) or 0
    local value=direction<0 and previousStockTarget(current) or nextStockTarget(current)
    targets[key]=value
    local ok,reason=KnoxPersistence.setBaseReserveTargets(self.baseId,self.playerId,targets,
        getGameTime()~=nil and getGameTime():getWorldAgeHours() or 0)
    if ok then
        self.selectedCategory=key
        KnoxActivityFeed.event("Stock target "..tostring(RESOURCE_LABELS[key] or key)
            ..": "..tostring(value)..".")
        local win=self:getWindow()
        if win~=nil and win.refreshContent~=nil then win:refreshContent() end
    else
        KnoxActivityFeed.event("Stock target not saved: "..tostring(reason)..".")
    end
end
function StoresView:onRaise() self:changeTarget(1) end
function StoresView:onLower() self:changeTarget(-1) end
function StoresView:onClear()
    if self.baseId==nil or self.playerId==nil then return end
    local ok,reason=KnoxPersistence.setBaseReserveTargets(self.baseId,self.playerId,nil,
        getGameTime()~=nil and getGameTime():getWorldAgeHours() or 0)
    if ok then
        KnoxActivityFeed.event("Stock targets reset to planner defaults.")
        local win=self:getWindow()
        if win~=nil and win.refreshContent~=nil then win:refreshContent() end
    else
        KnoxActivityFeed.event("Stock targets not cleared: "..tostring(reason)..".")
    end
end
function StoresView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    UILayout.trackWindow(self)
    self.panel=ISTabPanel:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    -- ISTabPanel:addView adds the child and invokes createChildren once. Calling
    -- it here as well duplicates every label/list/button and breaks page layout.
    self.baseView=BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.panel:addView("Base & Work", self.baseView); UILayout.bindView(self.baseView)
    self.crewView=CrewView:new(0, 8, self.panel.width, self.panel.height-8); self.crewView:initialise(); self.panel:addView("Crew & Schedule", self.crewView); UILayout.bindView(self.crewView)
    self.storesView=StoresView:new(0, 8, self.panel.width, self.panel.height-8); self.storesView:initialise(); self.panel:addView("Stores & Stock", self.storesView); UILayout.bindView(self.storesView)
    self.missionsView=MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.panel:addView("Missions", self.missionsView)
    self.worldView=WorldView:new(0, 8, self.panel.width, self.panel.height-8); self.worldView:initialise(); self.panel:addView("World", self.worldView)
    -- The Work-tab band's raid row lands on the World tab, where the live
    -- threat is described; the title-bar pill uses the same route.
    self.baseView.knoxOpenStores = function()
        if self.panel ~= nil then self.panel:activateView("Stores & Stock") end
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
    local amber, charcoal = UILayout.theme.amber, UILayout.theme.charcoal
    self.homeAttentionBtn.borderColor = { r = amber[1], g = amber[2], b = amber[3], a = 0.75 }
    self.homeAttentionBtn.backgroundColor = { r = charcoal[1], g = charcoal[2],
        b = charcoal[3], a = 0.92 }
    self.homeAttentionBtn.tooltip = "Open Base & Work on the first home problem."
    self:addChild(self.homeAttentionBtn)
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
    if base ~= nil then
        local residents = #(KnoxPersistence.getBaseResidentIds(base.id) or {})
        title = tostring(base.name or "Home base") .. " · " .. tostring(residents)
            .. (residents == 1 and " resident" or " residents")
    end
    if self.knoxTitle ~= title then
        self.knoxTitle = title
        self:setTitle(title)
    end
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
    local label = tostring(base.name or "Home") .. " · " .. tostring(model.title or "")
        .. "  " .. tostring(model.actionLabel or "Review")
    button.knoxAttentionKey = model.itemKey
    button:setWidth(math.min(330, math.max(140, self.width - 180)))
    button:setX(math.max(8, self.width - button:getWidth() - 30))
    button:setTitle(trimText(UIFont.Small, label, button:getWidth() - 12))
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

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.isCollapsed or not self:isVisible() then
        if self.homeAttentionBtn ~= nil then self.homeAttentionBtn:setVisible(false) end
        return
    end
    self:updateHomeAttention()
    local active = self.panel and self.panel:getActiveView() or nil
    if active ~= self.refreshedView or getTimestampMs() >= (self.nextRefreshAt or 0) then
        self:refreshContent()
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
    window.playerNum=playerNum; UILayout.tintWindow(window)
    window:setTitle("Knox Survivors"); window:setResizable(false); UILayout.bindInteractionWindow(window); window:updateTitle(); return window
end

function Window:fitToPlayerViewport(playerNum)
    local scale = math.max(1, getTextManager():getFontHeight(UIFont.Small) / 14)
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local width = math.min(math.floor(760*scale), math.max(1, sw - 40))
    local height = math.min(math.floor(600*scale), math.max(1, sh - 40))
    self:setWidth(width)
    self:setHeight(height)
    self:setX(getPlayerScreenLeft(playerNum) + (sw - width) / 2)
    self:setY(getPlayerScreenTop(playerNum) + (sh - height) / 2)
end

-- The notebook is usually opened for one page, and a player who lives on Crew
-- & Schedule should not walk back from Base & Work every time. The last page
-- read is remembered on the module for this session only — never written to a
-- save — and an explicit viewName (an attention jump, a card button, the world
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
