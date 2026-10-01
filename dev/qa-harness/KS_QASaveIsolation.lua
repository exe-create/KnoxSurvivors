-- Run-scoped, fail-closed QA save declaration. Build 42 exposes a current save
-- label to Knox, but no Lua API here creates or safely discards a save. Human
-- declaration is therefore necessary, but never represented as engine proof.
local Isolation = {}

Isolation.STATUSES = {
    APPROVED_QA_SAVE = true,
    ORDINARY_SAVE = true,
    UNKNOWN_SAVE = true,
    SAVE_IDENTITY_UNAVAILABLE = true,
    STALE_OR_MISMATCHED_QA_RUN = true,
}

Isolation.QA_SAVE_PREFIX = "KSQA-"
Isolation.DISPOSABLE_ACKNOWLEDGEMENT = "I CONFIRM THIS IS A DISPOSABLE QA SAVE"
Isolation.ORDINARY_ACKNOWLEDGEMENT = "I CONFIRM THIS IS AN ORDINARY PLAYER SAVE"

local function nonEmptyString(value)
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed ~= "" and value or nil
end

function Isolation.capture(coreGetter)
    if type(coreGetter) ~= "function" then
        return { identity = nil, source = "unavailable" }
    end
    local ok, core = pcall(coreGetter)
    if not ok or core == nil or core.getGameSaveWorld == nil then
        return { identity = nil, source = "unavailable" }
    end
    local valueOk, value = pcall(function() return core:getGameSaveWorld() end)
    local identity = valueOk and nonEmptyString(value) or nil
    return {
        identity = identity,
        source = identity ~= nil and "core.getGameSaveWorld" or "unavailable",
    }
end

local function hasQaPrefix(identity)
    return type(identity) == "string"
        and identity:sub(1, #Isolation.QA_SAVE_PREFIX):lower()
            == Isolation.QA_SAVE_PREFIX:lower()
end

function Isolation.arm(capture, expectedIdentity, acknowledgement, nextRunSequence)
    local identity = type(capture) == "table" and nonEmptyString(capture.identity) or nil
    if identity == nil then
        return false, "SAVE_IDENTITY_UNAVAILABLE"
    end
    if capture.source ~= "core.getGameSaveWorld" then
        return false, "UNKNOWN_SAVE"
    end
    expectedIdentity = nonEmptyString(expectedIdentity)
    if expectedIdentity == nil or expectedIdentity ~= identity then
        return false, "STALE_OR_MISMATCHED_QA_RUN"
    end
    if not hasQaPrefix(identity) then
        return false, "ORDINARY_SAVE"
    end
    if acknowledgement ~= Isolation.DISPOSABLE_ACKNOWLEDGEMENT then
        return false, "UNKNOWN_SAVE"
    end
    return true, {
        identity = identity,
        source = capture.source or "unavailable",
        nextRunSequence = tonumber(nextRunSequence),
    }
end

function Isolation.classify(capture, arm, runId, runSequence)
    local identity = type(capture) == "table" and nonEmptyString(capture.identity) or nil
    if identity == nil then
        return "SAVE_IDENTITY_UNAVAILABLE", "native_save_identity_unavailable"
    end
    if arm == nil then
        return hasQaPrefix(identity) and "UNKNOWN_SAVE" or "ORDINARY_SAVE",
            hasQaPrefix(identity) and "qa_save_not_armed" or "no_qa_save_declaration"
    end
    if type(arm) ~= "table" or arm.identity ~= identity
        or tonumber(arm.nextRunSequence) ~= tonumber(runSequence)
        or type(runId) ~= "string" or runId == "" then
        return "STALE_OR_MISMATCHED_QA_RUN", "save_arm_run_or_identity_mismatch"
    end
    if not hasQaPrefix(identity) or arm.source ~= "core.getGameSaveWorld" then
        return "UNKNOWN_SAVE", "qa_save_identity_not_authoritative"
    end
    return "APPROVED_QA_SAVE", "explicit_run_scoped_owner_declaration"
end

function Isolation.sameSave(boundIdentity, currentCapture)
    local current = type(currentCapture) == "table"
        and nonEmptyString(currentCapture.identity) or nil
    if current == nil then return false, "SAVE_IDENTITY_UNAVAILABLE" end
    if type(boundIdentity) ~= "string" or boundIdentity == ""
        or current ~= boundIdentity then
        return false, "STALE_OR_MISMATCHED_QA_RUN"
    end
    return true, "same_save_identity"
end

function Isolation.encode(value)
    if value == nil then return "unavailable" end
    return (tostring(value):gsub(".", function(character)
        if character:match("[%w%-%._:]") then return character end
        return string.format("%%%02X", string.byte(character))
    end))
end

_G.KnoxQASaveIsolation = Isolation
return Isolation
