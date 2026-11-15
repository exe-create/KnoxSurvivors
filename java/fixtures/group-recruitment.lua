-- A homeless travel group is one household: the contacted member speaks for
-- all of them, and every member is admitted through the same writer a solo
-- recruit uses. Drives the production gate and transaction from
-- KS_CompanionService (loaded as group_recruitment_source).
local C = assert(KnoxCompanionService, "companion service missing")

-- This fixture replaces shared globals; hand them back exactly as found so a
-- later fixture in the same harness run sees the real owners.
local prior = { P = KnoxPersistence, S = KnoxSettings, R = KnoxSurvivorRuntime,
    F = KnoxActivityFeed, D = displayName, W = worldAge }

local groups, affiliations, duties, alive, hostile = {}, {}, {}, {}, {}
local household = { id = "g1", leaderId = "a", memberIds = { "b", "a", "c" } }
local companions, released, admittedCalls = {}, {}, {}
local failId

KnoxPersistence = {
    getTravelGroupFor = function(id)
        for _, group in ipairs(groups) do
            for _, member in ipairs(group.memberIds) do
                if member == id then return group end
            end
        end
        return nil
    end,
    getSurvivorAffiliation = function(id)
        return affiliations[id] or { kind = "independent" }
    end,
    getSurvivorDuty = function(id) return duties[id] or { mode = "autonomous" } end,
    isSurvivorAlive = function(id) return alive[id] ~= false end,
    isSurvivorHostileToPlayer = function(id) return hostile[id] == true end,
    getCompanionIds = function() return companions end,
    removeTravelGroupMember = function(id)
        released[id] = (released[id] or 0) + 1
        for index, member in ipairs(household.memberIds) do
            if member == id then table.remove(household.memberIds, index) break end
        end
    end,
    addTravelGroupMember = function(groupId, id)
        for _, member in ipairs(household.memberIds) do
            if member == id then return true end
        end
        household.memberIds[#household.memberIds + 1] = id
        return true
    end,
    setPlayerCompanion = function(id)
        admittedCalls[#admittedCalls + 1] = id
        if failId ~= nil and id == failId then return false, "write_failed" end
        companions[#companions + 1] = id
        return true
    end,
}
KnoxSettings = { companionLimit = function() return 5 end }
KnoxSurvivorRuntime = {
    getCharacter = function(id) return { id = id } end,
    notifyDutyChanged = function() end,
}
KnoxActivityFeed = { speak = function() end, event = function() end }
displayName = function(id) return "survivor-" .. tostring(id) end
worldAge = function() return 1 end

function C.rememberCommitment() end

groups[1] = household

-- 1. A homeless household is structurally admissible, members sorted once.
local group, kind = C.recruitableGroup("b")
assert(group ~= nil and kind == "homeless_group",
    "a homeless household is admitted as a whole")
assert(#group.memberIds == 3 and group.memberIds[1] == "a" and group.memberIds[3] == "c",
    "the household is admitted in a stable order")

-- 2. The houses that are not homeless, or not independent, are refused.
household.factionId = "f1"
local blocked, why = C.recruitableGroup("a")
assert(blocked == nil and why == "faction_group", "a faction-linked group is not a household")
household.factionId = nil

duties = { b = { mode = "base", baseId = "home" } }
blocked, why = C.recruitableGroup("a")
assert(blocked == nil and why == "homed_group", "a resident household already has a roof")
duties = {}

affiliations = { b = { kind = "player", ownerId = "p1" } }
blocked, why = C.recruitableGroup("a")
assert(blocked == nil and why == "member_affiliated",
    "a member who already belongs to someone refuses the whole household")
affiliations = {}

alive = { c = false }
blocked, why = C.recruitableGroup("a")
assert(blocked == nil and why == "member_dead", "a dead member is not admitted")
alive = {}

-- 3. Room is counted for the household, not per head.
KnoxSettings.companionLimit = function() return 2 end
assert(C.groupHasRoom("p1", 3) == false, "three people need room for three")
assert(C.groupHasRoom("p1", 2) == true, "two fit in two free slots")
assert(C.groupHasRoom("p1", 9, { forBase = true }) == true,
    "a base invitation is not a follower slot")
KnoxSettings.companionLimit = function() return 5 end

-- 4. Admission admits the whole household through the real writer, releasing
-- each member from the group only as they join.
local ok, result, count = C.admitGroup({}, "p1", group)
assert(ok == true and result == "recruited_group" and count == 3,
    "all three members are admitted as one household")
assert(#admittedCalls == 3, "each member is admitted through the affiliation writer")
assert(released.a == 1 and released.b == 1 and released.c == 1,
    "each member is released from the travel group as they join")

-- 5. A mid-way refusal leaves the rest of the household travelling together.
companions, released, admittedCalls = {}, {}, {}
failId = "c"
local partialOk, partialResult, partialCount = C.admitGroup({}, "p1", group)
assert(partialOk == true and partialResult == "recruited_group_partial" and partialCount == 2,
    "a refused member is reported instead of being hidden")
local stranded = true
for _, member in ipairs(household.memberIds) do
    if member == "c" then stranded = false end
end
assert(released.c == 1 and not stranded,
    "the refused member is put back in the household, not stranded")

failId = nil

-- 6. A full party refuses the household before anyone is released.
companions, released = { "x", "y", "z", "w", "v" }, {}
KnoxSettings.companionLimit = function() return 5 end
assert(C.groupHasRoom("p1", 3) == false, "a full party has no room for a household")
local emptyOk, emptyResult = C.admitGroup({}, "p1", group)
assert(emptyOk == false and emptyResult == "recruited_group_partial",
    "no room admits nobody")
local releasedAny = false
for _ in pairs(released) do releasedAny = true end
assert(not releasedAny, "nobody is released when there is no room")

KnoxPersistence, KnoxSettings = prior.P, prior.S
KnoxSurvivorRuntime, KnoxActivityFeed = prior.R, prior.F
displayName, worldAge = prior.D, prior.W
prior = nil

print("Group recruitment PASS homeless=whole faction=refused homed=refused room=household partial=intact")
