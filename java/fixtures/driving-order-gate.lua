-- Every driving entry point must agree with EnableExperimentalNpcDriving.
-- Off: no driving row in context/radial, and the shared refusal text exists.
-- On: context, radial and map expose the order and the context callback reaches
-- the companion service with the real driving kind.
local catalog = assert(KnoxOrderCatalog, "order catalogue missing")
local contextMenu = assert(KnoxSurvivorContextMenu, "survivor context menu missing")
local radial = assert(KnoxRadialOrders, "radial orders missing")
local mapOrders = assert(KnoxMapOrders, "map orders missing")

local prior = {
    KnoxSettings = KnoxSettings, KnoxSurvivorRuntime = KnoxSurvivorRuntime,
    KnoxCompanionService = KnoxCompanionService, KnoxActivityFeed = KnoxActivityFeed,
    KnoxPersistence = KnoxPersistence, KnoxCompanionVehicles = KnoxCompanionVehicles,
    ISContextMenu = ISContextMenu, getSpecificPlayer = getSpecificPlayer,
}

local setting = false
local issued = {}
local feed = {}
local car = {}
local player = {
    getVehicle = function() return car end,
    getZ = function() return 0 end,
    getCurrentSquare = function()
        return { getX = function() return 0 end, getY = function() return 0 end }
    end,
}
car.driver = player
car.isDriver = function(self, who) return self.driver == who end
local companion = { getVehicle = function() return nil end, isDead = function() return false end }

KnoxSettings = {
    enabled = function() return true end,
    enableExperimentalNpcDriving = function() return setting end,
    showLegacyContextCommands = function() return true end,
}
KnoxSurvivorRuntime = {
    getCharacter = function() return companion end,
    nearestToSquare = function() return nil end,
}
KnoxCompanionService = {
    getCompanionIds = function() return { "c1" } end,
    getPlayerId = function() return "p1" end,
    issueOrder = function(_, id, kind)
        issued[#issued + 1] = { id = id, kind = kind }
        return true
    end,
    drivePlayerVehicleTo = function(_, id, x, y)
        issued[#issued + 1] = { id = id, kind = "drive_to", x = x, y = y }
        return true
    end,
    issueOrderAll = function(_, kind)
        issued[#issued + 1] = { kind = kind }
        return true
    end,
}
KnoxPersistence = {
    getSurvivorIdentity = function() return { forename = "Ada", surname = "Reyes" } end,
}
KnoxCompanionVehicles = { driverStatus = function() return nil end }
ISContextMenu = { getNew = function()
    return { addOption = function() return {} end, addSubMenu = function() end }
end }
getSpecificPlayer = function() return player end
KnoxActivityFeed = {
    event = function(text) feed[#feed + 1] = tostring(text) end,
    speak = function() end,
}

local function menu()
    local value = { options = {}, slices = {} }
    function value:addOption(label, target, method, ...)
        local option = { label = tostring(label), target = target, method = method, args = { ... } }
        self.options[#self.options + 1] = option
        return option
    end
    function value:addSlice(label, icon, callback, ...)
        local slice = { label = tostring(label), callback = callback, args = { ... } }
        self.slices[#self.slices + 1] = slice
        return slice
    end
    function value:addSubMenu() end
    function value:setOptionChecked() end
    return value
end
local function hasOption(value, fragment)
    for _, option in ipairs(value.options) do
        if option.label:find(fragment, 1, true) ~= nil then return true end
    end
    return false
end
local function hasSlice(value, fragment)
    for _, slice in ipairs(value.slices) do
        if slice.label:find(fragment, 1, true) ~= nil then return true end
    end
    return false
end

-- Off: no driving row anywhere. Passenger boarding and leaving stay available.
setting = false
assert(contextMenu.drivingOrdersEnabled() == false, "context gate must read the setting")
local contextOff = menu()
contextMenu.addVehicleOrderOptions(contextOff, player, 0, "c1")
assert(not hasOption(contextOff, "Drive"), "context menu hides driving while the setting is off")
assert(hasOption(contextOff, "Passenger"), "context menu keeps passenger boarding")

local radialOff = menu()
radial.addFollowerVehicleSlices(radialOff, { playerNum = 0 }, "c1")
assert(not hasSlice(radialOff, "Drive"), "radial follower page hides driving while off")
assert(hasSlice(radialOff, "Passenger"), "radial follower page keeps passenger boarding")
for _, entry in ipairs(radial.partyVehicleOrders()) do
    assert(entry.kind ~= "let_companion_drive" and entry.kind ~= "take_wheel",
        "party vehicle page hides handoff orders while off")
end

local mapOff = {
    added = 0,
    addOption = function(self, label) self.added = self.added + 1; return { label = label } end,
    addSubMenu = function() end,
}
assert(mapOrders.fill(mapOff, player, 0, 0) == false, "map driving orders stay closed while off")
assert(mapOff.added == 0, "map menu adds no driving entry while off")

local refusal = catalog.failureText("npc_driving_disabled")
assert(type(refusal) == "string" and refusal:find("NPC driving", 1, true) ~= nil,
    "the shared failure text names the disabled setting")
local spoke = 0
local accepted = catalog.withFeedback("Survivor request", function()
    spoke = spoke + 1
    return false, "npc_driving_disabled"
end)
assert(accepted == false and spoke == 1, "the shared feedback path receives the refusal")
assert(#feed > 0 and feed[#feed]:find("NPC driving", 1, true) ~= nil,
    "the shared feedback path speaks the refusal instead of failing silently")

-- On: the same entry points expose the driving order.
setting = true
assert(contextMenu.drivingOrdersEnabled() == true, "context gate opens when the setting is on")
local contextOn = menu()
contextMenu.addVehicleOrderOptions(contextOn, player, 0, "c1")
assert(hasOption(contextOn, "Take Driver Seat & Drive"), "context menu exposes drive ahead")
local driveOption = nil
for _, option in ipairs(contextOn.options) do
    if option.label:find("Take Driver Seat", 1, true) ~= nil then driveOption = option break end
end
assert(driveOption ~= nil and driveOption.method ~= nil, "drive row has a real executor")
driveOption.method(driveOption.target, driveOption.args[1], driveOption.args[2])
assert(#issued == 1 and issued[1].kind == "drive_ahead",
    "the context row reaches the companion driving order")

-- A row built while the setting was on must still refuse, visibly, if the
-- setting is switched off before the click.
setting = false
local issuedBeforeStale = #issued
feed = {}
driveOption.method(driveOption.target, driveOption.args[1], driveOption.args[2])
assert(#issued == issuedBeforeStale, "a stale context drive row does not issue an order while off")
assert(#feed > 0 and feed[#feed]:find("NPC driving", 1, true) ~= nil,
    "a stale context drive row speaks the disabled refusal")
setting = true

player.getVehicle = function() return nil end
local onFoot = menu()
contextMenu.addVehicleOrderOptions(onFoot, player, 0, "c1")
assert(hasOption(onFoot, "Drive Nearest Vehicle"), "context menu exposes drive nearest on foot")
player.getVehicle = function() return car end

local radialOn = menu()
radial.addFollowerVehicleSlices(radialOn, { playerNum = 0 }, "c1")
local driveSlice = nil
for _, slice in ipairs(radialOn.slices) do
    if slice.label:find("Take Driver Seat", 1, true) ~= nil then driveSlice = slice break end
end
assert(driveSlice ~= nil and driveSlice.callback == radial.orderOne,
    "radial drive slice uses the real order callback")
assert(driveSlice.args[3] == "drive_ahead", "radial drive slice carries the driving kind")
local radialFill = radial.fillKnox
radial.fillKnox = function() end
local issuedBeforeRadial = #issued
driveSlice.callback(driveSlice.args[1], driveSlice.args[2], driveSlice.args[3])
assert(#issued == issuedBeforeRadial + 1 and issued[#issued].kind == "drive_ahead",
    "the radial drive slice reaches the companion driving order")
local issuedBeforeParty = #issued
radial.orderParty(radialOn, "let_companion_drive")
assert(#issued == issuedBeforeParty + 1 and issued[#issued].kind == "let_companion_drive",
    "the party vehicle page reaches the handoff order")
radial.fillKnox = radialFill

local partyKinds = {}
for _, entry in ipairs(radial.partyVehicleOrders()) do partyKinds[entry.kind] = true end
assert(partyKinds.let_companion_drive == true and partyKinds.take_wheel == true,
    "party vehicle page exposes handoff orders when on")
setting = false
local issuedBeforePartyOff = #issued
feed = {}
radial.orderParty(radialOn, "let_companion_drive")
assert(#issued == issuedBeforePartyOff, "a stale party driving row does not issue an order while off")
assert(#feed > 0 and feed[#feed]:find("NPC driving", 1, true) ~= nil,
    "a stale party driving row speaks the disabled refusal")
setting = true

local mapSub = menu()
local mapOn = {
    added = 0,
    addOption = function(self, label) self.added = self.added + 1; return { label = label } end,
    addSubMenu = function() end,
}
local mapMenu = ISContextMenu
ISContextMenu = { getNew = function() return mapSub end }
assert(mapOrders.fill(mapOn, player, 0, 0) == true, "map driving orders open when the setting is on")
assert(mapOn.added > 0, "map menu adds the driving entry when on")
local mapOption = nil
for _, option in ipairs(mapSub.options) do
    if option.label == "Ada Reyes" then mapOption = option break end
end
assert(mapOption ~= nil and mapOption.method ~= nil, "map menu lists the resident drive option")
local issuedBeforeMap = #issued
mapOption.method(mapOption.target, mapOption.args[1], mapOption.args[2], mapOption.args[3])
assert(#issued == issuedBeforeMap + 1 and issued[#issued].kind == "drive_to",
    "the map drive option reaches the companion drive-to order")
ISContextMenu = mapMenu

KnoxSettings, KnoxSurvivorRuntime, KnoxCompanionService, KnoxActivityFeed =
    prior.KnoxSettings, prior.KnoxSurvivorRuntime, prior.KnoxCompanionService, prior.KnoxActivityFeed
KnoxPersistence, KnoxCompanionVehicles, ISContextMenu, getSpecificPlayer =
    prior.KnoxPersistence, prior.KnoxCompanionVehicles, prior.ISContextMenu, prior.getSpecificPlayer
print("Driving order gate PASS off=hidden refusal=spoken on=context+radial+map")
