-- Drives the real Positioning decisions for a human opponent. Zombie fights are
-- not touched by these rules, so nothing here changes the existing barrier path.
local P = assert(KnoxCombatPositioning)

-- An armed human at range is answered with geometry, not a charge.
assert(P.humanThreatPolicy({ armedHuman = true, distanceSquared = 100, hasCover = false }) == "cover",
    "an armed human at range makes the resident look for cover")
assert(P.humanThreatPolicy({ armedHuman = true, distanceSquared = 100, hasCover = true }) == "peek",
    "from cover the resident peeks rather than abandoning it")
assert(P.humanThreatPolicy({ armedHuman = true, distanceSquared = 2, hasCover = true }) == "melee",
    "at contact range cover is irrelevant")
assert(P.humanThreatPolicy({ armedHuman = false, distanceSquared = 100 }) == "advance",
    "an unarmed threat keeps the ordinary approach")

-- Two people do not reposition at once.
assert(P.pairRole({ selfReady = true, partnerReady = true, partnerHolding = true }) == "move",
    "one of a pair moves while the other holds")
assert(P.pairRole({ selfReady = true, partnerReady = false, partnerHolding = true }) == "hold",
    "nobody moves unless the partner is holding and ready")
assert(P.pairRole({ selfReady = false }) == "hold",
    "a resident who cannot shoot holds")

-- Breaking off is a reason, not a feeling.
local flee, reason = P.breakOff({ health = 20 })
assert(flee == true and reason == "wounded", "a badly wounded resident breaks off")
flee, reason = P.breakOff({ health = 90, armed = true, ammo = 0 })
assert(flee == true and reason == "no_ammo", "an empty weapon breaks off")
flee, reason = P.breakOff({ health = 90, allies = 1, enemies = 3 })
assert(flee == true and reason == "outnumbered", "one against three breaks off")
flee, reason = P.breakOff({ health = 90, allies = 3, enemies = 3 })
assert(flee == false and reason == "fight", "an even fight is still a fight")
