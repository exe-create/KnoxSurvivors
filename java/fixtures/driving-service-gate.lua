-- The service entry points are the last line before a driving run. With the
-- setting off every one must return npc_driving_disabled and speak the shared
-- text; with it on each must pass the gate and reach its normal first step.
local Service = assert(KnoxCompanionService, "driving service gate missing")
local prior = {
    KnoxSettings = KnoxSettings, KnoxActivityFeed = KnoxActivityFeed,
    KnoxOrderCatalog = KnoxOrderCatalog, KnoxCompanionVehicles = KnoxCompanionVehicles,
}

local feed = {}
local setting = false
KnoxActivityFeed = { event = function(text) feed[#feed + 1] = tostring(text) end, speak = function() end }
KnoxSettings = { enableExperimentalNpcDriving = function() return setting end }

local entryPoints = {
    { name = "drivePlayerVehicle", call = function() return Service.drivePlayerVehicle({}, "c1") end },
    { name = "drivePlayerVehicleTo", call = function() return Service.drivePlayerVehicleTo({}, "c1", 0, 0) end },
    { name = "sendVehicleTo", call = function() return Service.sendVehicleTo(nil, "c1", 0, 0, 0) end },
    { name = "driveNearestVehicle", call = function() return Service.driveNearestVehicle({}, "c1") end },
    { name = "letCompanionDrive", call = function() return Service.letCompanionDrive(nil, "c1") end },
    { name = "takeWheel", call = function() return Service.takeWheel(nil) end },
}

for _, entry in ipairs(entryPoints) do
    local ok, reason = entry.call()
    assert(ok == false and reason == "npc_driving_disabled",
        entry.name .. " must refuse while off, got " .. tostring(reason))
    assert(#feed > 0 and feed[#feed]:find("NPC driving", 1, true) ~= nil,
        entry.name .. " must speak the disabled refusal")
end

-- On: the gate opens; each function reaches its next real check instead of
-- stopping at the setting. deliverOrder is the first shared step for the two
-- direct drive orders and is stubbed here only to keep this fixture pure.
setting = true
Service.deliverOrder = function() return false, "fixture_reached_delivery" end
local onResults = {
    { name = "drivePlayerVehicle", call = function() return Service.drivePlayerVehicle({}, "c1") end, expected = "fixture_reached_delivery" },
    { name = "drivePlayerVehicleTo", call = function() return Service.drivePlayerVehicleTo({}, "c1", 0, 0) end, expected = "fixture_reached_delivery" },
    { name = "sendVehicleTo", call = function() return Service.sendVehicleTo(nil, "c1", 0, 0, 0) end, expected = "player_in_vehicle" },
    { name = "driveNearestVehicle", call = function() return Service.driveNearestVehicle({}, "c1") end, expected = "fixture_reached_delivery" },
    { name = "letCompanionDrive", call = function() return Service.letCompanionDrive(nil, "c1") end, expected = "player_not_in_vehicle" },
    { name = "takeWheel", call = function() return Service.takeWheel(nil) end, expected = "invalid_player" },
}
feed = {}
for _, entry in ipairs(onResults) do
    local ok, reason = entry.call()
    assert(ok == false and reason == entry.expected,
        entry.name .. " must pass the gate when on, got " .. tostring(reason))
end
assert(#feed == 0, "an open gate does not speak a disabled refusal")

-- With the gate open, each direct driving function must reach the real vehicle
-- owner: driveAhead, driveTo, driveNearest or beginHandoff. These stubs stand
-- in only for the native run, not for the order path under test.
local drove = {}
local character = {}
local square = { getZ = function() return 0 end }
local vehicle = {
    isDriver = function() return false end,
    getDriver = function() return nil end,
    getSquare = function() return square end,
}
local mounted = { getVehicle = function() return vehicle end }
local onFoot = { getVehicle = function() return nil end }
KnoxCompanionVehicles = {
    driveAhead = function() drove[#drove + 1] = "drive_ahead"; return true, "driving" end,
    driveTo = function() drove[#drove + 1] = "drive_to"; return true, "driving" end,
    driveNearest = function() drove[#drove + 1] = "drive_nearest"; return true, "driving", vehicle end,
    beginHandoff = function() drove[#drove + 1] = "handoff"; return true, "waiting_for_player_seat" end,
}
isPlayerCompanion = function() return true end
validateInteraction = function() return character, "" end
signalOrder = function() end
Service.deliverOrder = function() return true end
Service.excludePartyDestinationRecipient = function() end
KnoxActivityFeed.speak = function() end

local ok, result = Service.drivePlayerVehicle(mounted, "c1")
assert(ok == true and drove[#drove] == "drive_ahead",
    "drivePlayerVehicle reaches startDrive, got " .. tostring(result))
ok, result = Service.drivePlayerVehicleTo(mounted, "c1", 4, 5)
assert(ok == true and drove[#drove] == "drive_to",
    "drivePlayerVehicleTo reaches driveTo, got " .. tostring(result))
ok, result = Service.driveNearestVehicle(onFoot, "c1")
assert(ok == true and drove[#drove] == "drive_nearest",
    "driveNearestVehicle reaches driveNearest, got " .. tostring(result))
vehicle.isDriver = function() return true end
ok, result = Service.letCompanionDrive(mounted, "c1")
assert(ok == true and drove[#drove] == "handoff",
    "letCompanionDrive reaches the handoff path, got " .. tostring(result))

KnoxSettings, KnoxActivityFeed, KnoxOrderCatalog, KnoxCompanionVehicles =
    prior.KnoxSettings, prior.KnoxActivityFeed, prior.KnoxOrderCatalog, prior.KnoxCompanionVehicles
isPlayerCompanion, validateInteraction, signalOrder = nil, nil, nil
print("Driving service gate PASS off=refused spoken=yes on=driveAhead/driveTo/driveNearest/handoff")
