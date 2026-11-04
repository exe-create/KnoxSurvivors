-- Personality traits must change behaviour, not just labels. Courage moves the
-- retreat threshold and deception feeds the ambush chance; both drive the real
-- production functions rather than a copy of them.
local P = KnoxPersistence
local C = codecCourage

assert(type(C.courageRetreatThreshold) == "function", "courage threshold must exist")
assert(type(C.retreatAdmission) == "function", "retreat admission must exist")
assert(type(P.deceptionLureChance) == "function", "deception chance must exist")

local realIdentity = P.getSurvivorIdentity
local function thresholdWith(courage, base, id)
    P.getSurvivorIdentity = function()
        if courage == nil then return nil end
        return { courage = courage }
    end
    local value = C.courageRetreatThreshold(id or "sim", base)
    P.getSurvivorIdentity = realIdentity
    return value
end

assert(math.abs(thresholdWith(50, 12) - 12) < 1e-9, "average courage keeps the base threshold")
assert(thresholdWith(82, 12) < 12, "higher courage lowers the threshold")
assert(math.abs(thresholdWith(82, 12) - (12 - 32 / 25)) < 1e-9, "brave survivors use the narrow band")
assert(thresholdWith(20, 12) > 12, "frightened survivors leave earlier")
assert(math.abs(thresholdWith(500, 12) - 10) < 1e-9, "courage is clamped at 100")
assert(math.abs(thresholdWith(-50, 12) - 14) < 1e-9, "courage is clamped at 0")
assert(thresholdWith(nil, 12) == 12, "a missing identity leaves the threshold alone")
assert(C.courageRetreatThreshold(nil, 12) == 12, "no id leaves the threshold alone")
assert(C.courageRetreatThreshold("sim", nil) == nil, "no base returns nothing to compare")
P.getSurvivorIdentity = nil
assert(C.courageRetreatThreshold("sim", 12) == 12, "a missing reader leaves the threshold alone")
P.getSurvivorIdentity = realIdentity

-- The same threat, admitted or refused only because of temperament. A hurt
-- body uses the 5-point threshold; a healthy but outnumbered one uses 12.
local function admits(courage, pressure, vulnerable, outnumbered, contact)
    P.getSurvivorIdentity = function() return { courage = courage } end
    local admitted = C.retreatAdmission(3, true, false, vulnerable or false,
        outnumbered or false, contact or 0, 6, 1, pressure, "sim")
    P.getSurvivorIdentity = realIdentity
    return admitted
end
assert(admits(100, 11, false, true, 2) == true, "a bold survivor holds at pressure 11")
assert(admits(0, 11, false, true, 2) == false, "a frightened survivor leaves at the same pressure")
assert(admits(100, 5.5, true, false, 0) == true, "a bold wounded survivor holds at the hurt band")
assert(admits(0, 5.5, true, false, 0) == false, "a frightened wounded survivor leaves at the hurt band")

-- A closed route still refuses everyone, whatever their courage.
P.getSurvivorIdentity = function() return { courage = 100 } end
local blocked = C.retreatAdmission(0, true, false, true, false, 1, 2, 1, 99, "sim")
P.getSurvivorIdentity = realIdentity
assert(blocked == false, "no escape lane refuses admission regardless of courage")

-- Deception: the pair value comes from the stored trait, not a personality name.
local function lure(firstDeception, secondDeception)
    P.getSurvivorIdentity = function(id)
        return { deception = id == "deceptive" and firstDeception or secondDeception }
    end
    local chance = P.deceptionLureChance("deceptive", "other")
    P.getSurvivorIdentity = realIdentity
    return chance
end
assert(lure(76, 10) > 0, "one deceptive member can lure")
assert(math.abs(lure(76, 10) - (76 - 45) * 0.35) < 1e-9, "the chance follows the trait")
assert(lure(10, 10) == 0, "honest pairs never lure")
assert(lure(100, 10) == 18, "the lure chance is capped")
assert(lure("76", 10) > 0, "a numeric string reads as a number")
assert(lure(nil, nil) == 0, "an unknown trait never lures")
assert(P.deceptionLureChance(nil, nil) == 0, "no identities never lure")

-- The archetypes are the source of those numbers.
local opportunist = P.getPersonalityProfile("opportunist")
local frightened = P.getPersonalityProfile("frightened")
assert(opportunist.deception == 76 and opportunist.deception > 45, "an opportunist is deceptive")
assert(frightened.courage == 20 and frightened.courage < 50, "a frightened survivor is timid")

print("personality traits PASS courage=true threshold=true admission=true deception=true profile=true")
