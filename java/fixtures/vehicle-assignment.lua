-- Rebuilt 2026-11-02 after this file was overwritten by an agent. The original
-- content is not recoverable. What is certain from its caller is the contract:
-- line 348 of KnoxPersistenceCodecVerifier runs `verifyVehicleAssignmentReload()`
-- inside the `verify` chunk, after `loadedHook()`. So this file writes an
-- assignment before the save and then proves it survived the reload.
local p = KnoxPersistence

local written, writeReason = p.setVehicleAssignment({
    vehicleKey = "3110", ownerKind = "player", ownerId = "codec-owner",
    driverId = "codec-person", passengerIds = {}, role = "transport",
    createdAtHours = 12,
}, 12)
assert(written ~= nil, "an assignment is written before the save: "
    .. tostring(writeReason))

function verifyVehicleAssignmentReload()
    local current = KnoxPersistence
    local record, reason = current.getVehicleAssignment("3110")
    assert(record ~= nil, "an assignment survives the reload: " .. tostring(reason))
    assert(record.vehicleKey == "3110", "the native vehicle key survives")
    assert(record.role == "transport", "the role survives")
    assert(record.driverId == "codec-person", "the driver survives")
    assert(type(record.passengerIds) == "table" and #record.passengerIds == 0,
        "an empty passenger list survives as a list")
    local bySurvivor, seat = current.getVehicleAssignmentForSurvivor("codec-person")
    assert(bySurvivor ~= nil and seat == "driver",
        "the survivor still resolves to the vehicle after a reload")
    -- The codec runs this chunk once per pass. Clearing the real assignment here
    -- would make the second pass read an empty record, so releasing is proved on
    -- a scratch key that every pass creates for itself.
    assert(current.setVehicleAssignment({
        vehicleKey = "3111", ownerKind = "player", ownerId = "codec-owner",
        driverId = "codec-scratch", role = "cargo",
    }, 12) ~= nil, "a scratch assignment can be written")
    assert(current.clearVehicleAssignment("3111", "reload_checked") == true,
        "a reloaded assignment can be released")
    assert(current.getVehicleAssignment("3111") == nil)
end
