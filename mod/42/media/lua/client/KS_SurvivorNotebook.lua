require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISTabPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "ISUI/ISTextBox"
require "KS_Persistence"
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
    local text = tostring(value or "")
    local width = math.max(8, tonumber(availableWidth) or 8)
    if getTextManager():MeasureStringX(font, text) <= width then return text end
    local suffix = "..."
    while #text > 0 and getTextManager():MeasureStringX(font, text .. suffix) > width do
        text = string.sub(text, 1, #text - 1)
    end
    return text .. suffix
end

local function drawListText(list, y, item, alpha)
    list:drawText(trimText(list.font, item.text or "", list:getWidth() - 20),
        10, y + 2, 1, 1, 1, alpha, list.font)
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
    { label = "Log Processing Area", kind = "log_processing" },
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
}

-- Duty-schedule strip, RimWorld tool painting: pick a tool below, then
-- click hours to paint them. Sleep and recreation are no-work windows;
-- work, patrol and guard all work (patrol/guard bias election toward
-- watch tasks). The backend window list stays the sole persisted
-- authority; the strip expands windows to hours for display and compresses
-- back on save (see KnoxPersistence.dutyWindowsToHours/hoursToDutyWindows).
local SCHEDULE_ASSIGNMENT_LABELS = {
    sleep = "Sleep", work = "Work", patrol = "Patrol", guard = "Guard Duty",
    recreation = "Recreation", anything = "Anything",
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
        local reason=readableReason(task.result or task.lastResult)
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
    local y=UI_BORDER_SPACING
    self.basePicker=ISComboBox:new(UI_BORDER_SPACING,y,220,BUTTON_HGT,self,nil); self.basePicker:initialise(); self:addChild(self.basePicker)
    self.renameBaseBtn=ISButton:new(self.basePicker:getRight()+6,y,88,BUTTON_HGT,"Rename",self,BaseView.onRenameBase)
    self.renameBaseBtn:initialise(); self.renameBaseBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.renameBaseBtn)
    y=y+BUTTON_HGT+4
    self.infoLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y=y+FONT_HGT_SMALL+4
    self.workforceLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.workforceLabel:initialise(); self:addChild(self.workforceLabel)
    y=y+FONT_HGT_SMALL+2
    self.securityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.securityLabel:initialise(); self:addChild(self.securityLabel)
    y=y+FONT_HGT_SMALL+4
    self.boundaryLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.6,0.6,0.8,1,UIFont.Small,true); self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y=y+FONT_HGT_SMALL+6
    self.showHighlights=ISTickBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,"",self,BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption("Show Highlights"); self:addChild(self.showHighlights)
    self.editBoundaryBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Edit Boundary",self,BaseView.onEditBoundary); self.editBoundaryBtn:initialise(); self.editBoundaryBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.editBoundaryBtn)
    y=y+BUTTON_HGT+6
    self.zoneHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Work Areas",1,1,1,1,UIFont.Small,true); self.zoneHeading:initialise(); self:addChild(self.zoneHeading)
    y=y+FONT_HGT_SMALL+4
    self.zoneList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.NewSmall; self.zoneList.doDrawItem=BaseView.drawZone; self.zoneList.drawBorder=true; self:addChild(self.zoneList)
    y=self.zoneList:getBottom()+UI_BORDER_SPACING
    self.zonePicker=ISComboBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,self,nil); self.zonePicker:initialise()
    for _,d in ipairs(ZONE_TYPES) do self.zonePicker:addOption(d.label) end; self.zonePicker.selected=1; self:addChild(self.zonePicker)
    self.addAreaBtn=ISButton:new(self.zonePicker:getRight()+6,y,100,BUTTON_HGT,"Add Area",self,BaseView.onAddArea); self.addAreaBtn:initialise(); self.addAreaBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.addAreaBtn)
    self.removeBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Remove Selected",self,BaseView.onRemove); self.removeBtn:initialise(); self.removeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.removeBtn)
    y=y+BUTTON_HGT+6
    self.taskHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Task Queue",1,1,1,1,UIFont.Small,true); self.taskHeading:initialise(); self:addChild(self.taskHeading)
    y=y+FONT_HGT_SMALL+4
    self.taskList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*4)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.NewSmall; self.taskList.doDrawItem=BaseView.drawTask; self.taskList.drawBorder=true; self:addChild(self.taskList)
    y=self.taskList:getBottom()+6
    self.cancelTaskBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Cancel",self,BaseView.onCancelTask)
    self.cancelTaskBtn:initialise(); self.cancelTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.cancelTaskBtn)
    self.resumeTaskBtn=ISButton:new(self.cancelTaskBtn:getRight()+6,y,110,BUTTON_HGT,"Resume",self,BaseView.onResumeTask)
    self.resumeTaskBtn:initialise(); self.resumeTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resumeTaskBtn)
    self.residentPicker=ISComboBox:new(self.resumeTaskBtn:getRight()+6,y,160,BUTTON_HGT,self,nil); self.residentPicker:initialise(); self:addChild(self.residentPicker)
    self.assignTaskBtn=ISButton:new(self.residentPicker:getRight()+6,y,96,BUTTON_HGT,"Assign",self,BaseView.onAssignTask)
    self.assignTaskBtn:initialise(); self.assignTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.assignTaskBtn)
    y=y+BUTTON_HGT+6
    self.storageLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Storage",1,1,1,1,UIFont.Small,true); self.storageLabel:initialise(); self:addChild(self.storageLabel)
    y=y+FONT_HGT_SMALL+4
    self.storageList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*3)
    self.storageList:initialise(); self.storageList:instantiate(); self.storageList.itemheight=BUTTON_HGT; self.storageList.font=UIFont.NewSmall; self.storageList.doDrawItem=BaseView.drawStorage; self.storageList.drawBorder=true; self:addChild(self.storageList)
    y=self.storageList:getBottom()+6
    -- Hours and priorities moved to the Crew tab; the Base tab keeps
    -- boundary, areas, queue and storage.
    self.hintLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.hintLabel:initialise(); self.hintLabel.name="Set hours and work priorities per survivor in the Crew tab."; self:addChild(self.hintLabel)
    -- The fixed arrangement is taller than short/split-screen viewports.
    -- Let the existing tab layout adapter scroll the whole page instead of
    -- placing storage and its hint beyond the visible tab bounds.
    self.knoxContentHeight=self.hintLabel:getBottom()+UI_BORDER_SPACING
end
function BaseView:onMouseWheel(delta)
    -- Keep wheel input local to one bounded list.  The parent tab only moves
    -- when the pointer is outside Work Areas, Task Queue, and Storage.
    return UILayout.routeWheelToChildren(self, delta,
        { self.zoneList, self.taskList, self.storageList })
end
function BaseView:drawZone(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28)
    if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.28,0.45,0.42,0.36) end
    local color=ZONE_COLORS[item.item and item.item.type] or ZONE_COLORS.general
    self:drawRect(0,y,4,self.itemheight-1,0.9,color.r,color.g,color.b)
    drawListText(self, y, item, a); return y+self.itemheight
end
function BaseView:drawTask(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight
end
function BaseView:drawStorage(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight
end
function BaseView:onAssignTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    local residentId=self.residentIds and self.residentIds[self.residentPicker.selected or 0] or nil
    if task == nil or task.id == nil or task.state ~= "queued" or residentId == nil then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local assigned,result=KnoxCompanionService.assignBaseTask(player, residentId, base.id, task.id)
    if assigned ~= nil and result == "claimed" then
        KnoxActivityFeed.event("Assigned " .. KnoxOrderCatalog.label(task.type, "work") .. " to the selected resident.")
        self:populate(self.playerNum)
    end
end
function BaseView:onCancelTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil or task.state == "claimed" or task.state == "cancelled" then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local cancelled,result=KnoxPersistence.cancelBaseTask(base.id,task.id,now)
    if cancelled ~= nil and result == "cancelled" then
        KnoxActivityFeed.event("Base task cancelled: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
        self:populate(self.playerNum)
    end
end
function BaseView:onResumeTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil or task.state ~= "cancelled" then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=self:selectedBase(self.playerNum, playerId)
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local resumed,result=KnoxPersistence.resumeBaseTask(base.id,task.id,now)
    if resumed ~= nil and result == "resumed" then
        KnoxActivityFeed.event("Base task resumed: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
        self:populate(self.playerNum)
    end
end
function BaseView:selectedBase(playerNum, pid)
    local win = self:getWindow()
    local baseId = notebookBaseId(win, playerNum, pid)
    if baseId == nil then return nil end
    return KnoxPersistence.getBase(baseId)
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
    self.taskList:clear(); self.storageList:clear()
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
        self.residentPicker:addOption("No residents")
        addRow(self.taskList,"none","No base"); addRow(self.storageList,"none","No base")
        self.taskHeading.name="No base"; self.storageLabel.name="No base"
        return
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
    -- One fact per line: the old combined line clipped guard and patrol
    -- counts off the readable width.
    self.infoLabel.name=trimText(UIFont.Small,
        tostring(base.name or "Home Base")
        .. "  |  Residents: " .. #residents .. "  |  Zones: " .. zones
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
        for _,z in ipairs(list) do local w,h,total=zoneSize(z); local sz=w and ("  " .. w .. "x" .. h .. " (" .. total .. ")  at " .. z.x1 .. "," .. z.y1) or ""; addRow(self.zoneList,z.id, "  " .. tostring(z.label or z.type) .. " [" .. tostring(z.type) .. "]" .. sz); self.zoneList.items[#self.zoneList.items].item={type=z.type, id=z.id} end
    end
    self:populateWork(base)
end

-- Task queue + storage for the selected base (merged old Work tab).
function BaseView:populateWork(base)
    for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        local identity=KnoxPersistence.getSurvivorIdentity(residentId) or {}
        local name=(tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name="Resident " .. tostring(residentId) end
        self.residentIds[#self.residentIds+1]=residentId
        self.residentPicker:addOption(name)
    end
    if #self.residentIds == 0 then self.residentPicker:addOption("No residents") end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local settlement = KnoxBaseJobs ~= nil and KnoxBaseJobs.settlementSummary ~= nil
        and KnoxBaseJobs.settlementSummary(base, now) or nil
    local tasksSummary=settlement~=nil and settlement.tasks or {queued=0,claimed=0,blocked=0}
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
    local filteredContainers = KnoxBaseStorage.policies(base) or {}
    local usableContainers = KnoxBaseStorage.operationalPolicies ~= nil
        and KnoxBaseStorage.operationalPolicies(base) or filteredContainers
    self.storageLabel.name=trimText(UIFont.Small,
        "Storage: " .. tostring(#filteredContainers) .. " filtered | "
        .. tostring(#usableContainers) .. " usable containers | " .. stockState,
        self.width-UI_BORDER_SPACING*2)
    local any=false
    local assigned = KnoxBaseStorage.policies(base)
    if #assigned == 0 then addRow(self.storageList,"setup","Right-click any container inside this base to set item filters") end
    for _, policy in ipairs(assigned) do
        local resolved = KnoxBaseStorage.resolvePolicy(policy)
        local text = KnoxBaseStorage.label(policy) .. " [" .. KnoxBaseStorage.priorityLabel(policy) .. "]"
            .. " (" .. tostring(policy.containerType) .. ") at "
            .. tostring(policy.x) .. ", " .. tostring(policy.y) .. ", floor " .. tostring(policy.z)
        if resolved == nil then text = text .. " — unavailable" end
        addRow(self.storageList,policy.key,text)
    end
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
            addRow(self.storageList,cat,text); any=true
        end
    end
    local other=tonumber(summary.totals.other) or 0; if other>0 then addRow(self.storageList,"other","Other: "..other); any=true end
    if not any then addRow(self.storageList,"none","No supplies in loaded containers") end
    if summary.unavailablePolicies>0 then addRow(self.storageList,"warn", tostring(summary.unavailablePolicies) .. " container(s) outside loaded area") end
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
        btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }; self:addChild(btn)
        btn.knoxGroup = col.key
        self.crewCells[col.key] = btn
    end
    y = y + math.ceil(#PRIORITY_COLUMNS / priorityColumns) * (BUTTON_HGT + 2) + 4
    self.scheduleResidentLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.scheduleResidentLabel:initialise(); self:addChild(self.scheduleResidentLabel)
    y = y + FONT_HGT_SMALL + 2
    self.scheduleLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.scheduleLabel:initialise(); self:addChild(self.scheduleLabel)
    y = y + FONT_HGT_SMALL + 4
    -- Paint tools first (RimWorld order): pick one, then click hours.
    -- Selected tool gets the white border; it sticks until changed.
    self.scheduleTools = {}
    local toolColumns = responsiveControlColumns(
        availableW, #SCHEDULE_TOOLS, 40, 3)
    local toolW = math.max(1, math.floor((availableW - (toolColumns - 1) * 4) / toolColumns))
    for index, tool in ipairs(SCHEDULE_TOOLS) do
        local slot = (index - 1) % toolColumns
        local row = math.floor((index - 1) / toolColumns)
        local btn = ISButton:new(UI_BORDER_SPACING + slot * (toolW + 4), y + row * (BUTTON_HGT + 2), toolW, BUTTON_HGT,
            tool.label, self, CrewView.onSelectTool)
        btn:initialise(); btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
        local color = SCHEDULE_COLORS[tool.key]
        setPersistentButtonFill(btn, color, 0.9)
        btn.knoxTool = tool.key
        self:addChild(btn)
        self.scheduleTools[tool.key] = btn
    end
    y = y + math.ceil(#SCHEDULE_TOOLS / toolColumns) * (BUTTON_HGT + 2) + 4
    self.scheduleHourBtns = {}
    local hourColumns = responsiveControlColumns(availableW, 12, 28, 12)
    local hourRows = math.ceil(24 / hourColumns)
    local hourW = math.max(1, math.floor((availableW - (hourColumns - 1) * 2) / hourColumns))
    for row = 0, hourRows - 1 do
        for col = 0, hourColumns - 1 do
            local hour = row * hourColumns + col
            if hour < 24 then
            local btn = ISButton:new(UI_BORDER_SPACING + col * (hourW + 2), y + row * (BUTTON_HGT + 2),
                hourW, BUTTON_HGT, string.format("%02d", hour), self, CrewView.onPaintHour)
            btn:initialise(); btn.background = true; btn.isBaseBackgroundVisible = true
            btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
            btn.knoxHour = hour
            -- Paint begins only on an hour cell. Hover painting follows the
            -- held left-button stroke across adjacent cells; no capture is
            -- taken, so Notebook scrolling and other controls keep ownership.
            btn.onmousedown = function(target, pressedButton)
                if target ~= nil then target:beginSchedulePaintStroke(pressedButton) end
            end
            btn.onmouseover = function(target, hoveredButton)
                if target ~= nil then target:continueSchedulePaintStroke(hoveredButton) end
            end
            btn.onMouseUp = function(self, mouseX, mouseY)
                ISButton.onMouseUp(self, mouseX, mouseY)
                if self.target ~= nil then self.target:endSchedulePaintStroke() end
            end
            btn.onMouseUpOutside = function(self, mouseX, mouseY)
                ISButton.onMouseUpOutside(self, mouseX, mouseY)
                if self.target ~= nil then self.target:endSchedulePaintStroke() end
            end
            self:addChild(btn)
            self.scheduleHourBtns[hour + 1] = btn
            end
        end
    end
    y = y + hourRows * (BUTTON_HGT + 2) + 4
    self.saveScheduleBtn=ISButton:new(UI_BORDER_SPACING,y,110,BUTTON_HGT,"Save Hours",self,CrewView.onSaveSchedule); self.saveScheduleBtn:initialise(); self.saveScheduleBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.saveScheduleBtn)
    self.colonyPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Colony Day",self,CrewView.onPresetColony); self.colonyPresetBtn:initialise(); self.colonyPresetBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.colonyPresetBtn)
    self.nightPresetBtn=ISButton:new(0,y,110,BUTTON_HGT,"Night Shift",self,CrewView.onPresetNight); self.nightPresetBtn:initialise(); self.nightPresetBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.nightPresetBtn)
    self.clearPresetBtn=ISButton:new(0,y,80,BUTTON_HGT,"Clear",self,CrewView.onPresetClear); self.clearPresetBtn:initialise(); self.clearPresetBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.clearPresetBtn)
    self.resetPrioritiesBtn=ISButton:new(0,y,120,BUTTON_HGT,"Normal Work",self,CrewView.onResetPriorities); self.resetPrioritiesBtn:initialise(); self.resetPrioritiesBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resetPrioritiesBtn)
    local presetButtons = { self.saveScheduleBtn, self.colonyPresetBtn, self.nightPresetBtn,
        self.clearPresetBtn, self.resetPrioritiesBtn }
    local presetX, presetRow = 0, 0
    for _, button in ipairs(presetButtons) do
        local buttonW = math.min(button.width, availableW)
        if presetX > 0 and presetX + buttonW > availableW then
            presetX, presetRow = 0, presetRow + 1
        end
        button:setX(UI_BORDER_SPACING + presetX)
        button:setY(y + presetRow * (BUTTON_HGT + 2))
        button:setWidth(buttonW)
        presetX = presetX + buttonW + 4
    end
    y = y + (presetRow + 1) * (BUTTON_HGT + 2) + 2
    self.scheduleStatus=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.scheduleStatus:initialise(); self:addChild(self.scheduleStatus)
    y = y + FONT_HGT_SMALL + 4
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,y,95,BUTTON_HGT,"View Card",self,CrewView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
    self.joinPartyBtn=ISButton:new(self.viewBtn:getRight()+6,y,95,BUTTON_HGT,"Join Party",self,CrewView.onJoinParty); self.joinPartyBtn:initialise(); self.joinPartyBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.joinPartyBtn)
    self.sendHomeBtn=ISButton:new(self.joinPartyBtn:getRight()+6,y,120,BUTTON_HGT,"Send Party Home",self,CrewView.onSendHome); self.sendHomeBtn:initialise(); self.sendHomeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.sendHomeBtn)
    self.jobPicker=ISComboBox:new(self.sendHomeBtn:getRight()+6,y,125,BUTTON_HGT,self,nil); self.jobPicker:initialise(); for _,choice in ipairs(BASE_JOB_CHOICES) do self.jobPicker:addOption(choice.label) end; self.jobPicker.selected=1; self:addChild(self.jobPicker)
    self.setJobBtn=ISButton:new(self.jobPicker:getRight()+6,y,80,BUTTON_HGT,"Set Job",self,CrewView.onSetJob); self.setJobBtn:initialise(); self.setJobBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.setJobBtn)
    local actionButtons = { self.viewBtn, self.joinPartyBtn, self.sendHomeBtn,
        self.jobPicker, self.setJobBtn }
    local actionX, actionRow = 0, 0
    for _, control in ipairs(actionButtons) do
        local controlW = math.min(control.width, availableW)
        if actionX > 0 and actionX + controlW > availableW then
            actionX, actionRow = 0, actionRow + 1
        end
        control:setX(UI_BORDER_SPACING + actionX)
        control:setY(y + actionRow * (BUTTON_HGT + 2))
        control:setWidth(controlW)
        actionX = actionX + controlW + 4
    end
    self.knoxContentHeight = y + (actionRow + 1) * (BUTTON_HGT + 2) + UI_BORDER_SPACING
end
function CrewView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight
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
    for _,s in ipairs(snaps) do addRow(self.partyList,s.id, s.displayName .. "  |  " .. (s.professionLabel or "Survivor") .. "  |  " .. (s.orderLabel or "") .. "  |  " .. (s.activity or "")); self.partyIds[#self.partyIds+1]=s.id end
    if #self.partyIds==0 then addRow(self.partyList,"none","No party — recruit survivors") end
    if base then for _,id in ipairs(KnoxPersistence.getBaseResidentIds(base.id)) do
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
            local currentStatus = snapshot ~= nil and snapshot.activity or taskLabel
            local currentLocation = snapshot ~= nil and snapshot.locationLabel or nil
            if taskDetail == nil and work ~= nil and work.taskType ~= nil
                and snapshot ~= nil and currentStatus ~= taskLabel then
                taskDetail = "Task: " .. taskLabel
            end
            local jobPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or duty.jobPreference
            addRow(self.resList,id, name .. "  |  Job: "
                .. KnoxOrderCatalog.label(jobPreference or "auto", "Automatic") .. "  |  " .. profLabel
                .. "  |  Now: " .. tostring(currentStatus)
                .. (currentLocation ~= nil and "  |  " .. tostring(currentLocation) or "")
                .. (taskDetail ~= nil and "  |  " .. taskDetail or ""))
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
                KnoxCompanionService.sendToBase(p, id, baseId)
            end
            self:populate(self.playerNum)
        end)
        return
    end
    for _, id in ipairs(companions) do
        KnoxCompanionService.sendToBase(p, id)
    end
    self:populate(self.playerNum)
end
function CrewView:onJoinParty()
    local id=self:selectedCrewId(); local player=getSpecificPlayer(self.playerNum)
    if id == nil or player == nil then return end
    local changed, reason = KnoxCompanionService.recallToParty(player, id)
    if changed then
        self:populate(self.playerNum)
    elseif KnoxActivityFeed ~= nil then
        KnoxActivityFeed.event("Could not join party: " .. tostring(readableReason(reason) or "unavailable") .. ".")
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
    local changed = KnoxCompanionService.setBaseJobPreference(
        player, id, choice.value, base.id
    )
    if changed then
        KnoxActivityFeed.event("Base job preference set to " .. string.lower(choice.label) .. ".")
        self:populate(self.playerNum)
    end
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
    local draft = self.scheduleDrafts[residentId]
    if draft == nil then
        local saved = KnoxPersistence.getDutySchedule ~= nil
            and KnoxPersistence.getDutySchedule(residentId) or nil
        draft = KnoxPersistence.dutyWindowsToHours ~= nil
            and KnoxPersistence.dutyWindowsToHours(saved) or {}
        self.scheduleDrafts[residentId] = draft
    end
    return draft
end

function CrewView:paintScheduleStrip(draft)
    local hourNow = currentScheduleHour()
    local now = hourNow ~= nil and math.floor(hourNow) % 24 or nil
    for hour = 0, 23 do
        local btn = self.scheduleHourBtns ~= nil and self.scheduleHourBtns[hour + 1] or nil
        if btn ~= nil then
            local assignment = type(draft) == "table" and draft[hour + 1] or nil
            if SCHEDULE_COLORS[assignment] == nil then assignment = "anything" end
        local color = SCHEDULE_COLORS[assignment]
            setPersistentButtonFill(btn, color, 0.85)
            if now ~= nil and hour == now and draft ~= nil then
                btn.borderColor = { r = 1, g = 0.86, b = 0.18, a = 1 }
                btn:setTitle(string.format("%02d*", hour))
            else
                btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
                btn:setTitle(string.format("%02d", hour))
            end
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

function CrewView:paintCrewDetail()
    local id = self:selectedCrewId()
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
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
            btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
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
            local source = saved
            local baseline = KnoxPersistence.dutyWindowsToHours ~= nil
                and KnoxPersistence.dutyWindowsToHours(source) or {}
            local dirty = false
            for h = 1, 24 do
                if (draft or {})[h] ~= baseline[h] then dirty = true; break end
            end
            self.scheduleStatus.name = dirty and "Unsaved changes — select Save Hours."
                or (saved == nil and "Default schedule — Anything." or "Saved schedule.")
        end
    end
    -- Role picker follows the selected resident's stored preference.
    if resident then
        local pref = KnoxOrderCatalog.normalizeBasePreference ~= nil
            and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
            or duty.jobPreference
        for index, choice in ipairs(BASE_JOB_CHOICES) do
            if choice.value == pref then self.jobPicker.selected = index; break end
        end
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
    local player = getSpecificPlayer(self.playerNum or 0)
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    local player, base = self:schedulePlayerAndBase()
    if player ~= nil and base ~= nil and service ~= nil
        and service.setBaseWorkPreferences ~= nil then
        ok = service.setBaseWorkPreferences(
            player, residentId, any and map or nil, base.id
        )
    end
    if ok then
        KnoxActivityFeed.event("Base work preference saved.")
        self:populate(self.playerNum or 0)
    else
        KnoxActivityFeed.event("Could not set work preference.")
    end
end

function CrewView:onResetPriorities()
    local player, base = self:schedulePlayerAndBase()
    local residentId = self:selectedCrewId()
    if player == nil or base == nil or residentId == nil then return end
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    if service ~= nil and service.setBaseWorkPreferences ~= nil then
        ok = service.setBaseWorkPreferences(player, residentId, nil, base.id)
    end
    KnoxActivityFeed.event(ok and "Work preferences reset to Normal."
        or "Could not reset work preferences.")
    if ok then self:populate(self.playerNum or 0) end
end

function CrewView:onSelectTool(button)
    local tool = button ~= nil and button.knoxTool or nil
    if SCHEDULE_COLORS[tool] == nil then return end
    self:endSchedulePaintStroke()
    self.scheduleTool = tool
    self:paintCrewDetail()
end

function CrewView:paintScheduleHour(button, residentId, tool)
    local hour = button ~= nil and tonumber(button.knoxHour) or nil
    if hour == nil or hour < 0 or hour > 23 then return end
    residentId = residentId or self:selectedCrewId()
    if residentId == nil or self:selectedCrewId() ~= residentId then return end
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil then return end
    tool = tool or self.scheduleTool
    if SCHEDULE_COLORS[tool] == nil then tool = "sleep" end
    draft[hour + 1] = tool
    self:paintCrewDetail()
end

function CrewView:beginSchedulePaintStroke(button)
    if button == nil or button.knoxHour == nil then return end
    local residentId = self:selectedCrewId()
    if residentId == nil or self:scheduleDraftFor(residentId) == nil then return end
    local tool = SCHEDULE_COLORS[self.scheduleTool] ~= nil and self.scheduleTool or "sleep"
    self.schedulePaintStroke = { residentId = residentId, tool = tool }
    self:paintScheduleHour(button, residentId, tool)
end

function CrewView:continueSchedulePaintStroke(button)
    local stroke = self.schedulePaintStroke
    if stroke == nil then return end
    if self:selectedCrewId() ~= stroke.residentId then
        self:endSchedulePaintStroke()
        return
    end
    if button == nil or button.knoxHour == nil or button.mouseOver ~= true then
        return
    end
    self:paintScheduleHour(button, stroke.residentId, stroke.tool)
end

function CrewView:endSchedulePaintStroke()
    self.schedulePaintStroke = nil
end

function CrewView:onMouseWheel(delta)
    -- A scroll gesture is never a schedule-paint gesture, even if the mouse
    -- button is still held while the view is moving.
    self:endSchedulePaintStroke()
    local handler = ISPanelJoypad.onMouseWheel
    if handler ~= nil then return handler(self, delta) end
    return false
end

function CrewView:onPaintHour(button)
    -- Keep click/joypad activation as a one-cell paint; mouse strokes use the
    -- same authoritative draft mutation through begin/continue above.
    self:paintScheduleHour(button)
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
    -- Day sleep, night shift, small hours free.
    local hours = {}
    for h = 0, 23 do
        if h >= 6 and h <= 14 then hours[h + 1] = "sleep"
        elseif h >= 15 or h <= 5 then hours[h + 1] = "work"
        else hours[h + 1] = "anything" end
    end
    hours[12 + 1] = "recreation"
    self:paintPresetHours(hours)
end

function CrewView:onPresetClear()
    local hours = {}
    for hour = 1, 24 do hours[hour] = "anything" end
    self:paintPresetHours(hours)
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
    local ok = false
    if service ~= nil and service.setBaseDutySchedule ~= nil then
        ok = service.setBaseDutySchedule(player, residentId, windows, base.id)
    end
    KnoxActivityFeed.event(ok and "Schedule saved."
        or "Could not save schedule.")
    if ok then
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
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
    local resident = duty ~= nil and duty.mode == "base" and base ~= nil and duty.baseId == base.id
    self.viewBtn:setEnable(id ~= nil)
    self.joinPartyBtn:setEnable(resident)
    self.jobPicker:setEnabled(resident)
    self.setJobBtn:setEnable(resident)
    self.saveScheduleBtn:setEnable(resident)
    self.colonyPresetBtn:setEnable(resident)
    self.nightPresetBtn:setEnable(resident)
    self.clearPresetBtn:setEnable(resident)
    self.resetPrioritiesBtn:setEnable(resident)
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
    self.toPartyBtn=ISButton:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Party",self,MissionsView.onSupplyToParty); self.toPartyBtn:initialise(); self.toPartyBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.toPartyBtn)
    self.toBaseBtn=ISButton:new(self.toPartyBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,100,BUTTON_HGT,"To Base",self,MissionsView.onSupplyToBase); self.toBaseBtn:initialise(); self.toBaseBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.toBaseBtn)
    self.resumeBtn=ISButton:new(self.toBaseBtn:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,120,BUTTON_HGT,"Resume Duty",self,MissionsView.onSupplyResume); self.resumeBtn:initialise(); self.resumeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resumeBtn)
end
function MissionsView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight
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
    for id, team in pairs(teams) do
        if team ~= nil and team.ownerKind == "player" and team.ownerId == ownerId
            and team.state ~= "complete" and team.state ~= "blocked" then
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
    if count == 0 then addRow(self.list,"none", "No active trips. Give survival orders from the Crew tab or a survivor's Orders menu.") end
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
    local ok, reason = KnoxCompanionService.recallToParty(player, id)
    KnoxActivityFeed.event(ok and "Recalled to the party."
        or "Could not recall: " .. tostring(reason or "unavailable") .. ".")
    if ok then self:populate(self.playerNum) end
end

function MissionsView:onSupplyResume()
    local id = self:selectedSupplyId()
    local player = getSpecificPlayer(self.playerNum or 0)
    if id == nil or player == nil then return end
    local pid = KnoxPersistence.ensurePlayerId(player)
    local ok = KnoxPersistence.clearBaseSupplyOrder ~= nil
        and KnoxPersistence.clearBaseSupplyOrder(id, pid, nil, self:missionNow())
    KnoxActivityFeed.event(ok and "Supply order cleared — back to normal duty."
        or "Could not clear the order.")
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
        local ok, result = false, "unavailable"
        if service ~= nil and service.transferBaseResident ~= nil then
            ok, result = service.transferBaseResident(player, id, baseId)
        end
        local base = KnoxPersistence.getBase(baseId)
        KnoxActivityFeed.event(ok and ("Called back to " .. tostring(base ~= nil and base.name or baseId) .. ".")
            or "Could not send to that base: " .. tostring(result or "unavailable") .. ".")
        if ok then self:populate(self.playerNum) end
    end
    local picker = rawget(_G, "KnoxBasePicker")
    if #bases > 1 and picker ~= nil and picker.choose ~= nil then
        picker.choose(playerNum, "Call back to which base?", bases, send)
        return
    end
    send(bases[1] ~= nil and bases[1].id or nil)
end

function MissionsView:prerender()
    ISPanelJoypad.prerender(self)
    local id = self:selectedSupplyId()
    if self.toPartyBtn then self.toPartyBtn:setEnable(id ~= nil) end
    if self.toBaseBtn then self.toBaseBtn:setEnable(id ~= nil) end
    if self.resumeBtn then self.resumeBtn:setEnable(id ~= nil) end
end

-- World panel: everyone else. Non-player factions on top with standing and
-- home; the selected faction's members below with roles (leader, follower,
-- work role, drifter). Unaffiliated known survivors group under Drifters.
-- Read-only by design: standing moves through encounters, not buttons.
local WORLD_JOB_ROLES = {
    auto = "Worker", guard = "Guard", patrol = "Patrol", farming = "Farmer",
    cooking = "Cook", woodwork = "Woodcutter", barricade = "Builder",
    hauling = "Hauler", repair = "Repairer", rest = "Resting",
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
    self.cardLine2=ISLabel:new(UI_BORDER_SPACING+52,cardY+FONT_HGT_SMALL+4,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.cardLine2:initialise(); self:addChild(self.cardLine2)
    self.memberList=ISScrollingListBox:new(UI_BORDER_SPACING,cardY+52,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.memberList:initialise(); self.memberList:instantiate(); self.memberList.itemheight=BUTTON_HGT; self.memberList.font=UIFont.NewSmall; self.memberList.doDrawItem=self.drawEntry; self.memberList.drawBorder=true; self:addChild(self.memberList)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.memberList:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,WorldView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
end
function WorldView:drawEntry(y,item,alt)
    if not UILayout.listRowVisible(self, y, item) then return y+self.itemheight end
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight
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
                        entries[#entries + 1] = {
                            at = tonumber(event.lastChangedAtHours) or 0,
                            text = tostring(event.kind or "event") .. " — "
                                .. tostring(event.phase or event.state or "ongoing"),
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
        if playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
        end
        local members, residents, guards = self:factionStats(faction)
        addRow(self.list, faction.id, tostring(faction.name or faction.id)
            .. "  |  " .. standing .. "  |  " .. tostring(members)
            .. " (" .. tostring(residents) .. " settled, " .. tostring(guards) .. " watch)"
            .. "  |  " .. self:factionHome(faction))
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

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    self.panel=ISTabPanel:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    -- ISTabPanel:addView adds the child and invokes createChildren once. Calling
    -- it here as well duplicates every label/list/button and breaks page layout.
    self.baseView=BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.panel:addView("Base & Work", self.baseView); UILayout.bindView(self.baseView)
    self.crewView=CrewView:new(0, 8, self.panel.width, self.panel.height-8); self.crewView:initialise(); self.panel:addView("Crew & Schedule", self.crewView); UILayout.bindView(self.crewView)
    self.missionsView=MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.panel:addView("Missions", self.missionsView)
    self.worldView=WorldView:new(0, 8, self.panel.width, self.panel.height-8); self.worldView:initialise(); self.panel:addView("World", self.worldView)
end

function Window:refreshContent()
    local view = self.panel and self.panel:getActiveView() or nil
    if view == nil or view.populate == nil then return end
    local saved = {}
    local previousCrewSource = view.crewSelSource
    for _, field in ipairs({"list", "partyList", "resList", "memberList", "zoneList", "taskList", "storageList", "scheduleList"}) do
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
    self.refreshedView = view
    self.nextRefreshAt = getTimestampMs() + 2000
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.isCollapsed or not self:isVisible() then return end
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
    window.playerNum=playerNum; window.backgroundColor={r=0.06,g=0.06,b=0.06,a=0.94}; window.borderColor={r=0.28,g=0.28,b=0.28,a=0.95}
    window:setTitle("Knox Survivors"); window:setResizable(false); return window
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

function Notebook.show(playerNum)
    playerNum=tonumber(playerNum) or 0
    if Notebook.window==nil then Notebook.window=Window:new(playerNum); Notebook.window:initialise(); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:addToUIManager()
    else Notebook.window.playerNum=playerNum; Notebook.window:fitToPlayerViewport(playerNum); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:setVisible(true); Notebook.window:bringToTop() end
    Notebook.window:refreshContent(); return Notebook.window
end
function Notebook.toggle(playerNum) if Notebook.window~=nil and Notebook.window:isVisible() then Notebook.window:setVisible(false) else Notebook.show(playerNum) end end
Events.OnMainMenuEnter.Add(function() if Notebook.window~=nil then Notebook.window:removeFromUIManager(); Notebook.window=nil end end)
return Notebook
