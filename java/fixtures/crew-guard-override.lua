local Catalog = assert(KnoxOrderCatalog, "order catalogue is loaded")
local View = assert(codecCrewView, "CrewView source slice is loaded")
local statusText = assert(codecScheduleStatusText, "schedule status helper is loaded")
local scheduleHour = assert(codecCurrentScheduleHour, "schedule clock is loaded")

local previousPersistence = KnoxPersistence
local previousService = rawget(_G, "KnoxCompanionService")
local previousFeed = rawget(_G, "KnoxActivityFeed")
local previousRequest = rawget(_G, "crewRequest")
local previousClock = getGameTime

local clockHour = 12
getGameTime = function()
    return { getTimeOfDay = function() return clockHour end }
end

local baseline = {}
for hour = 1, 24 do baseline[hour] = "sleep" end
local activeOverride = nil
KnoxPersistence = {
    getDutyScheduleOverride = function(id) return activeOverride end,
    dutyWindowsToHours = function(rota)
        if rota == nil then return {} end
        return baseline
    end,
}

local events = {}
KnoxActivityFeed = { event = function(text) events[#events + 1] = text end }
local serviceCalls = {}
local serviceResult = true
KnoxCompanionService = {
    setBaseDutyScheduleOverride = function(player, id, assignment, baseId)
        serviceCalls[#serviceCalls + 1] = {
            player = player, id = id, assignment = assignment, baseId = baseId,
        }
        return serviceResult
    end,
}
crewRequest = function(label, callback)
    local ok = callback()
    return ok == true
end

local player = { name = "player" }
local base = { id = "home" }
local residentId = "resident"
local paintCount = 0
local function button()
    return {
        setTitle = function(self, value) self.title = value end,
        setEnable = function(self, value) self.enabled = value end,
        setEnabled = function(self, value) self.enabled = value end,
    }
end
local view = {
    guardOverrideBtn = button(),
    guardOverrideStatusActive = nil,
    selectedCrewId = function() return residentId end,
    schedulePlayerAndBase = function() return player, base end,
    paintCrewDetail = function(self) paintCount = paintCount + 1 end,
}

-- The button must be honest at noon and for a non-resident: the next Dusk
-- order is not silently available early, and no resident means no owner.
clockHour = 12
activeOverride = nil
view.guardOverrideStatusActive = nil
View.refreshGuardOverrideControl(view, residentId, true)
assert(view.guardOverrideBtn.title == "Guard: night only",
    "the idle control names its restriction on its face")
assert(view.guardOverrideBtn.enabled == false,
    "the control is disabled outside Night and Dusk")
assert(view.guardOverrideBtn.tooltip == "Available during the Night and Dusk blocks only. Saved hours still apply.",
    "the disabled tooltip names the window and the saved rota")
assert(view.guardOverrideStatusActive == false,
    "the idle state is recorded for the next edge")
assert(paintCount == 0, "the first idle refresh does not repaint")

clockHour = 23.5
View.refreshGuardOverrideControl(view, residentId, false)
assert(view.guardOverrideBtn.enabled == false,
    "a non-resident cannot take a guard block")
assert(view.guardOverrideBtn.title == "Guard Tonight",
    "the non-resident control still names the action")

-- Dusk and Night are the two accepted windows. The same helper owns both, so
-- the button must agree at the Dusk edge and at midnight.
View.refreshGuardOverrideControl(view, residentId, true)
assert(view.guardOverrideBtn.enabled == true,
    "a base resident can take the Dusk block")
assert(view.guardOverrideBtn.tooltip == "Take the current night or dusk block only. Expires at the next block and leaves saved hours unchanged.",
    "the enabled tooltip states the expiry and the saved-rota promise")
clockHour = 0
View.refreshGuardOverrideControl(view, residentId, true)
assert(view.guardOverrideBtn.enabled == true,
    "the Night block is also available")

-- An active override changes the same button into the clear action and keeps
-- the assignment label in the tooltip.
activeOverride = { assignment = "guard", expiresAtHours = 24 }
view.guardOverrideStatusActive = nil
View.refreshGuardOverrideControl(view, residentId, true)
assert(view.guardOverrideBtn.title == "Clear Override",
    "an active override turns the button into Clear Override")
assert(view.guardOverrideBtn.enabled == true,
    "an active override can always be cleared")
assert(view.guardOverrideBtn.tooltip == "Clear the temporary guard duty and return to the saved hours.",
    "the clear tooltip names the temporary duty")

-- Crossing the boundary must repaint once, then settle on the new state. The
-- production paint calls refresh again; this simulates that nested call.
activeOverride = nil
clockHour = 0
paintCount = 0
View.refreshGuardOverrideControl(view, residentId, true)
assert(paintCount == 1, "an active-to-expired boundary repaints once")
assert(view.guardOverrideStatusActive == false,
    "the expired edge is recorded before the repaint returns")
assert(view.guardOverrideBtn.title == "Clear Override",
    "the edge returns before mutating the stale button; the repaint owns it")
View.refreshGuardOverrideControl(view, residentId, true)
assert(paintCount == 1, "the boundary edge does not loop")
assert(view.guardOverrideBtn.title == "Guard Tonight",
    "the settled control returns to Guard Tonight")
assert(view.guardOverrideBtn.enabled == true,
    "the settled Night control is available")

-- A missing button is a no-op, not a crash on a partially built view.
view.guardOverrideBtn = nil
View.refreshGuardOverrideControl(view, residentId, true)
view.guardOverrideBtn = button()

-- The status helper owns the line's precedence: a dirty draft is the player's
-- first obligation, then the live temporary order, then the saved/default rota.
local saved = {}
local draft = {}
for hour = 1, 24 do draft[hour] = baseline[hour] end
assert(statusText(nil, nil, nil) == "Default schedule - Anything.",
    "no saved rota reads as the default")
assert(statusText(saved, draft, nil) == "Saved schedule.",
    "a clean draft reads as saved")
draft[5] = "work"
assert(statusText(saved, draft, nil) == "Unsaved changes - select Save Hours.",
    "a dirty draft warns before anything else")
assert(statusText(saved, draft, { assignment = "guard", expiresAtHours = 16 })
    == "Unsaved changes - select Save Hours.",
    "a dirty draft keeps its warning over an active temporary order")
draft[5] = "sleep"
assert(statusText(saved, draft, { assignment = "guard", expiresAtHours = 16 })
    == "Temporary guard duty until 16:00 - saved hours unchanged.",
    "the clean temporary line names the duty and boundary")
assert(statusText(saved, draft, { assignment = "guard", expiresAtHours = 4 })
    == "Temporary guard duty until 04:00 - saved hours unchanged.",
    "the Night boundary is rendered with two digits")
assert(statusText(saved, draft, { assignment = "guard", expiresAtHours = 24 })
    == "Temporary guard duty until 00:00 - saved hours unchanged.",
    "the Dusk boundary is rendered as midnight")

-- The click path must refuse early, set guard in the two accepted windows, and
-- clear through the same service entry. The service and feedback wrapper are
-- stubbed here; schedule-override.lua owns the persisted writer.
activeOverride = nil
clockHour = 12
events = {}
serviceCalls = {}
paintCount = 0
View.onGuardTonight(view)
assert(#serviceCalls == 0, "the click path refuses outside Night and Dusk")
assert(#events == 1 and events[1] == "Guard Tonight is available during the Night and Dusk blocks.",
    "the refusal names the available windows")
assert(paintCount == 0, "a refused click does not repaint the detail")

clockHour = 23.5
serviceResult = true
View.onGuardTonight(view)
assert(#serviceCalls == 1 and serviceCalls[1].id == residentId
    and serviceCalls[1].assignment == "guard" and serviceCalls[1].baseId == base.id,
    "Dusk sends one guard assignment through the existing service")
assert(events[#events] == "Guard tonight: temporary until the next block.",
    "the accepted guard order is acknowledged")
assert(paintCount == 1, "the accepted guard order repaints the detail")

activeOverride = { assignment = "guard", expiresAtHours = 24 }
View.onGuardTonight(view)
assert(#serviceCalls == 2 and serviceCalls[2].assignment == nil,
    "an active override is cleared through the same service entry")
assert(events[#events] == "Temporary schedule override cleared.",
    "the clear is acknowledged")
assert(paintCount == 2, "the clear repaints the detail")

events = {}
serviceCalls = {}
paintCount = 0
activeOverride = nil
clockHour = 23.5
serviceResult = false
View.onGuardTonight(view)
assert(#serviceCalls == 1, "a refused service call is still attempted")
assert(#events == 0 and paintCount == 0,
    "a refused service call is not reported as accepted")

serviceResult = true
local previousSchedule = view.schedulePlayerAndBase
view.schedulePlayerAndBase = function() return nil, base end
events = {}
serviceCalls = {}
View.onGuardTonight(view)
assert(#serviceCalls == 0 and #events == 0,
    "a missing player is refused before the service")
view.schedulePlayerAndBase = previousSchedule

previousSchedule = view.selectedCrewId
view.selectedCrewId = function() return nil end
events = {}
serviceCalls = {}
View.onGuardTonight(view)
assert(#serviceCalls == 0 and #events == 0,
    "a missing resident is refused before the service")
view.selectedCrewId = previousSchedule

-- The real clock reader must return the game hour used by both the button and
-- the status line, rather than a fixture-only substitute.
clockHour = 23.5
assert(math.abs(scheduleHour() - 23.5) < 0.000001,
    "the Crew clock reads the native time of day")
clockHour = 24
assert(scheduleHour() == 0, "the Crew clock wraps midnight")

KnoxPersistence = previousPersistence
KnoxCompanionService = previousService
KnoxActivityFeed = previousFeed
crewRequest = previousRequest
getGameTime = previousClock

print("Crew guard override control PASS noon_disabled=true dusk_night_enabled=true clear_title=true edge_repaint=true status_text=true")
