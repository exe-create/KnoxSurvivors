-- Counting harness for the three hoisted pcall sites in the threat/autonomy
-- path. KS_CLEAR / KS_LEADER / KS_ENGAGE are the real production functions; the
-- pcall stub counts function identities, so an inline closure shows up as one
-- new function per call while a hoisted helper is one identity in total.
local savedPcall = pcall
local savedGlobals = { KnoxPersistence = KnoxPersistence,
    KnoxSettings = KnoxSettings, KnoxCompanionPatrol = KnoxCompanionPatrol }
KnoxPersistence = {
    getSurvivorDuty = function() return { mode = "base", baseId = "b1" } end,
    getSurvivorAffiliation = function()
        return { kind = "faction", factionId = "f1" }
    end,
    getFaction = function()
        return { kind = "npc", background = "military" }
    end,
}
KnoxSettings = {
    militaryFacilityClearing = function() return true end,
    militaryClearanceDistance = function() return 8 end,
}
KnoxCompanionPatrol = { contains = function() return true end }
local seen, fresh, calls = setmetatable({}, { __mode = "k" }), 0, 0
pcall = function(fn, ...)
    calls = calls + 1
    if type(fn) == "function" and seen[fn] == nil then
        seen[fn] = true
        fresh = fresh + 1
    end
    return true, fn(...)
end
local function reset()
    seen = setmetatable({}, { __mode = "k" })
    fresh, calls = 0, 0
end

local square = {
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
}
local clearSelf = {
    id = "s1", currentTicks = 5,
    character = { getCurrentSquare = function() return square end },
    baseTask = { type = "guard", state = "claimed", claimedBy = "s1", target = {} },
    base = { id = "b1", ownerId = "f1", ownerKind = "faction" },
}
local threat = {
    getCurrentSquare = function() return square end,
    isZombie = function() return true end,
}
reset()
for i = 1, 5 do KS_CLEAR(clearSelf, threat) end
local clearFresh, clearCalls = fresh, calls

local leader = { getCurrentSquare = function() return square end }
local leaderSelf = { companionOrder = "follow", companionTarget = leader }
reset()
for i = 1, 5 do KS_LEADER(leaderSelf) end
local leaderFresh, leaderCalls = fresh, calls

local engageSelf = {
    isFacilityClearingTarget = function() return false end,
    isResidentHomeIntruder = function() return false end,
    withinFollowerLeash = function() return true end,
}
local zombie = { isClimbing = function() return true end }
reset()
for i = 1, 5 do KS_ENGAGE(engageSelf, zombie, 4, false, false) end
local engageFresh, engageCalls = fresh, calls

-- Pre-change shape, measured through the same counter: one fresh closure per call.
reset()
for i = 1, 5 do pcall(function() return nil end) end
local oldFresh, oldCalls = fresh, calls

pcall = savedPcall
KnoxPersistence = savedGlobals.KnoxPersistence
KnoxSettings = savedGlobals.KnoxSettings
KnoxCompanionPatrol = savedGlobals.KnoxCompanionPatrol

assert(clearFresh == 1 and clearCalls == 5,
    "the threat candidate site creates no function per call, got " .. tostring(clearFresh))
assert(leaderFresh == 1 and leaderCalls == 5,
    "the leader square site creates no function per call, got " .. tostring(leaderFresh))
assert(engageFresh == 1 and engageCalls == 5,
    "the isClimbing site creates no function per call, got " .. tostring(engageFresh))
assert(oldFresh == 5 and oldCalls == 5,
    "the pre-change inline closure is one new function per call, got " .. tostring(oldFresh))

KS_THREAT_PCALL_RECEIPT = "clear_calls=" .. tostring(clearCalls)
    .. " clear_fresh=" .. tostring(clearFresh)
    .. " leader_calls=" .. tostring(leaderCalls)
    .. " leader_fresh=" .. tostring(leaderFresh)
    .. " engage_calls=" .. tostring(engageCalls)
    .. " engage_fresh=" .. tostring(engageFresh)
    .. " old_inline_calls=" .. tostring(oldCalls)
    .. " old_inline_fresh=" .. tostring(oldFresh)
