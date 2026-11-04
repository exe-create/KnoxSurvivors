-- Arming state and the defence report. No world, no native actor: item and body
-- shapes are minimal tables that answer only the questions under test.
local e = KnoxEquipmentIntelligence
local function melee(broken)
    return {
        IsWeapon = function() return true end,
        isRanged = function() return false end,
        isBroken = function() return broken end,
        getConditionMax = function() return 10 end,
        getCondition = function() return 10 end,
        getMinDamage = function() return .5 end,
        getMaxDamage = function() return .7 end,
        getMaxRange = function() return 1 end,
        getBaseSpeed = function() return 1 end,
        getCriticalChance = function() return 10 end,
    }
end
local function gun(broken)
    return {
        IsWeapon = function() return true end,
        isRanged = function() return true end,
        isBroken = function() return broken end,
    }
end
local knife, brokenKnife = melee(false), melee(true)
local pistol, brokenPistol = gun(false), gun(true)
assert(e.isArmedWeapon(knife), "a usable melee weapon is armed")
assert(not e.isArmedWeapon(brokenKnife), "a broken melee weapon is not armed")
assert(e.isArmedWeapon(pistol), "a working firearm is armed")
assert(not e.isArmedWeapon(brokenPistol), "a broken firearm is not armed")
assert(not e.isArmedWeapon(nil), "empty hands are not armed")
assert(not e.isArmedWeapon({}), "a plain item is not a weapon")
local function body(primary)
    return { getPrimaryHandItem = function() return primary end }
end
assert(e.isArmed(body(knife)))
assert(not e.isArmed(body(nil)))
assert(not e.isArmed(body(brokenPistol)))
assert(not e.isArmed(nil), "a missing body cannot be armed")

-- The report is the only player-facing evidence that an alarm was answered
-- without a weapon, so it must fire once, name the place, and stay quiet on a
-- faction base whose people are not the player's to worry about.
local c = KnoxAutonomyController
local lines = {}
KnoxActivityFeed = { event = function(line) lines[#lines + 1] = line end }
local function defender(primary, ownerKind)
    return { id = "codec-person", character = body(primary), base = { name = "Farm", ownerKind = ownerKind } }
end
assert(c.reportDefendingUnarmed(defender(knife, "player"), 0) == false,
    "an armed resident does not report")
local unarmed = defender(nil, "player")
assert(c.reportDefendingUnarmed(unarmed, 0) == true)
assert(#lines == 1, "one line for one unarmed alarm answer")
assert(string.find(lines[1], "unarmed", 1, true) ~= nil)
assert(string.find(lines[1], "Farm", 1, true) ~= nil)
assert(c.reportDefendingUnarmed(unarmed, 600) == false,
    "the same resident does not repeat inside the window")
assert(c.reportDefendingUnarmed(unarmed, 1200) == true,
    "the report resumes after the window")
assert(c.reportDefendingUnarmed(defender(nil, "faction"), 5000) == false,
    "faction bases do not speak into the player feed")
assert(c.reportDefendingUnarmed(defender(brokenPistol, "player"), 9000) == true,
    "a broken firearm still reports as unarmed")
assert(#lines == 3, "exactly the player-facing lines were raised")
