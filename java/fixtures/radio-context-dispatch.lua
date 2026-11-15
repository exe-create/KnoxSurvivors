local P = KnoxPersistence
local old = { playerId = P.ensurePlayerId, residents = P.getBaseResidentIds,
    manager = KnoxBaseManager, runtime = KnoxSurvivorRuntime, feed = KnoxActivityFeed,
    context = ISContextMenu, instance = instanceof }
local base = assert(P.createBase("player", "radio-context-owner", {
    minX = 8200, minY = 8200, width = 4, height = 4, buildingId = "radio-context-building" }, 10))
P.ensurePlayerId = function() return "radio-context-owner" end
P.getBaseResidentIds = function() return {} end
KnoxSurvivorRuntime = {}
KnoxBaseManager = { containsSquare = function() return true end,
    radioOperatorLevel = codecRadioArrival.radioOperatorLevel }
local messages = {}
KnoxActivityFeed = { event = function(text) messages[#messages + 1] = text end }
local on, acceptsPower, announcements = false, true, 0
local device = { getIsTurnedOn = function() return on end,
    setIsTurnedOn = function(_, value) on = acceptsPower and value or false end,
    getHasBattery = function() return true end, getTransmitRange = function() return 1000 end }
local square = { getX = function() return 8200 end, getY = function() return 8200 end,
    getZ = function() return 0 end }
local radio = { getDeviceData = function() return device end,
    getSquare = function() return square end, hasGridPower = function() return true end,
    couldBePoweredByGenerator = function() return false end,
    AddDeviceText = function() announcements = announcements + 1 end }
instanceof = function(object, kind) return object == radio and kind == "IsoWaveSignal" end
local options = {}
local function menu()
    local result = {}
    function result:addOption(label, target, callback, ...)
        local option = { target = target, callback = callback, args = {...} }
        options[label] = option
        return option
    end
    function result:addSubMenu() end
    return result
end
ISContextMenu = { getNew = function() return menu() end }
local player = {}
local function click(label)
    local option = assert(options[label], label)
    -- Installed ISContextMenu invokes the target before stored parameters.
    return option.callback(option.target, unpack(option.args))
end
codecAddRadioMenu(menu(), base, player, {radio})
click("Switch Radio On")
assert(on == true, "the radio power menu dispatches player and radio in the native callback order")
click("Call on the radio")
assert(P.getBaseRadioMode(base.id) == "broadcast" and announcements == 1,
    "the mode menu reaches the real base writer and actual radio")
codecAddRadioMenu(menu(), base, player, {radio})
click("Off")
assert(P.getBaseRadioMode(base.id) == "off" and on == false, "off changes both device and saved mode")
acceptsPower = false
codecAddRadioMenu(menu(), base, player, {radio})
click("Call on the radio")
assert(P.getBaseRadioMode(base.id) == "off" and announcements == 1,
    "a device that refuses power cannot claim broadcasting or emit a call")
assert(string.find(messages[#messages], "will not switch on", 1, true) ~= nil,
    "a failed physical mode switch gives an honest refusal")
acceptsPower = true
click("Call on the radio")
codecAddRadioMenu(menu(), base, player, {radio})
click("Switch Radio Off")
assert(on == false and P.getBaseRadioMode(base.id) == "off",
    "the separate power-off command also stops durable broadcasting")
P.ensurePlayerId, P.getBaseResidentIds = old.playerId, old.residents
KnoxBaseManager, KnoxSurvivorRuntime, KnoxActivityFeed, ISContextMenu, instanceof =
    old.manager, old.runtime, old.feed, old.context, old.instance
print("Radio context dispatch PASS nativeCallbackOrder=true modeWriter=true powerReceipt=true")
