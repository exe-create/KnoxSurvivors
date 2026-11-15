-- Drives the real Controller.threatEngagementRadius. Who the zombie is already
-- attacking decides how far a companion answers; the player's fight counts.
assert(Controller ~= nil, "the controller slice defines the rule")
assert(Controller.threatEngagementRadius(4, false, false, false) == 4,
    "an ordinary sighting keeps the settings radius")
-- Self defense answers at the same distance as the player's fight: a zombie
-- that has acquired the survivor is not left unanswered until it is nearly
-- touching (owner report 2026-11-12: they won't defend themselves).
assert(Controller.threatEngagementRadius(4, true, false, false) == 12,
    "a zombie attacking this survivor is answered at twelve tiles")
assert(Controller.threatEngagementRadius(4, false, true, false) == 8,
    "a zombie attacking an ally is answered at eight tiles")
assert(Controller.threatEngagementRadius(4, false, false, true) == 12,
    "a zombie attacking the player is answered at twelve tiles")
assert(Controller.threatEngagementRadius(20, false, false, true) == 20,
    "a wider settings radius is never narrowed")
assert(Controller.threatEngagementRadius(nil, false, false, true) == 12,
    "a missing settings radius still answers the player's fight")
assert(Controller.threatEngagementRadius(nil, false, false, false) == 4,
    "a missing settings radius falls back to four")
