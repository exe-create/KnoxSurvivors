local Menu, Targets, P = assert(KnoxSurvivorContextMenu), assert(KnoxMissionTargets), assert(KnoxPersistence)
local oldPlayer, oldCell, oldMenu = getSpecificPlayer, getCell, ISContextMenu
local oldPicker, oldAutonomy, oldBaseMenu = KnoxBasePicker, KnoxSurvivorAutonomy, KnoxBaseContextMenu
local oldView, oldIds, oldDuty = KnoxSurvivorViewModel, P.getBaseResidentIds, P.getSurvivorDuty
local oldService, oldFeed = KnoxCompanionService, KnoxActivityFeed
local building = { getIDString = function() return "roster-shed" end,
    getDef = function() return { getID = function() return "roster-shed" end } end }
local target = { getX = function() return 1 end, getY = function() return 0 end,
    getZ = function() return 0 end, getBuilding = function() return building end }
local player = { getCurrentSquare = function() return { getX = function() return 0 end,
    getY = function() return 0 end, getZ = function() return 0 end } end }
getSpecificPlayer = function() return player end
local visible = true
getCell = function() return { getGridSquare = function(_, x, y, z)
    return visible and x == 1 and y == 0 and z == 0 and target or nil
end } end
P.getBaseResidentIds = function() return { "roster-runner" } end
P.getSurvivorDuty = function() return { mode = "base" } end
KnoxSurvivorViewModel = { getSurvivor = function() return { displayName = "Runner" } end }
KnoxCompanionService = {}
KnoxActivityFeed = { event = function() end }
KnoxSurvivorAutonomy = { baseMissionAvailability = function() return 1 end,
    missionCrewIds = function() return { "roster-runner" } end,
    missionCrewExclusions = function() return {} end }
local calls = {}
KnoxBaseContextMenu = { dispatchScout = function(p, base, square, size, kind, radius, label, members)
    calls[#calls + 1] = { player = p, base = base, square = square, size = size, kind = kind, members = members }
end }
local answers = { "roster-shed", "food", "pick:roster-runner", "done", "send" }
KnoxBasePicker = { choose = function(_, _, _, callback)
    local answer = table.remove(answers, 1)
    if answer ~= nil and answer ~= "cancel" then callback(answer) end
    return true
end }
local function menu()
    local m = { options = {} }
    function m:addOption(label, receiver, callback, a, b)
        local o = { label = label, receiver = receiver, callback = callback, a = a, b = b }
        self.options[#self.options + 1] = o
        return o
    end
    function m:addSubMenu() end
    function m:setOptionChecked() end
    return m
end
ISContextMenu = { getNew = function() return menu() end }
local base = { id = "dispatch-roster-base", home = { buildingId = "own-home" } }
local roster = menu()
Menu.populateRoster(roster, 0, base)
local option = roster.options[1]
assert(option.label == "Send a Gather / Scavenge Crew" and type(option.callback) == "function",
    "the base roster wires a real crew-order callback")
option.callback(option.receiver, option.a, option.b)
assert(#calls == 1 and calls[1].player == player and calls[1].base == base
    and calls[1].square == target and calls[1].kind == "food"
    and calls[1].members[1] == "roster-runner",
    "the roster chooser sends the selected crew through the existing dispatch owner without a map")
answers = { "cancel" }
option.callback(option.receiver, option.a, option.b)
assert(#calls == 1, "cancelling the base-side chooser dispatches nobody")
visible = false
option.callback(option.receiver, option.a, option.b)
assert(#calls == 1, "no real destination means no base-side dispatch")
getSpecificPlayer, getCell, ISContextMenu = oldPlayer, oldCell, oldMenu
KnoxBasePicker, KnoxSurvivorAutonomy, KnoxBaseContextMenu = oldPicker, oldAutonomy, oldBaseMenu
KnoxSurvivorViewModel, P.getBaseResidentIds, P.getSurvivorDuty = oldView, oldIds, oldDuty
KnoxCompanionService, KnoxActivityFeed = oldService, oldFeed
print("Base roster dispatch PASS menu=true realChooser=true selectedCrew=true cancel=true noMap=true nativeGameplay=false")
