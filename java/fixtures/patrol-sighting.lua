-- A patrol report is one line about what the stop can actually see. This drives
-- the real word, compass and cooldown helpers; it does not run a patrol or read a
-- body.
local P = assert(codecPatrol, "patrol sighting source is loaded")
local C = assert(codecCompass, "compass source is loaded")

assert(C.compassWord(0, -5) == "north", "a zombie above is north")
assert(C.compassWord(5, 0) == "east", "a zombie right is east")
assert(C.compassWord(5, 5) == "southeast", "a zombie down-right is southeast")
assert(C.compassWord(0, 0) == nil, "a zombie on the same square has no direction")

assert(P.sightingWord(0) == nil, "an empty stop says nothing")
assert(P.sightingWord(-2) == nil, "a non-count says nothing")
assert(P.sightingWord(1) == "Movement near the patrol route.",
    "one shape is movement")
assert(P.sightingWord(2) == "A few near the patrol route.",
    "two shapes are a few")
assert(P.sightingWord(4) == "A few near the patrol route.",
    "four shapes stay a few")
assert(P.sightingWord(5) == "A crowd near the patrol route.",
    "five shapes are a crowd")
assert(P.sightingWord(1, "north") == "Movement to the north.",
    "a direction reaches the movement line")
assert(P.sightingWord(5, "southeast") == "A crowd to the southeast.",
    "a direction reaches the crowd line")

assert(P.contactWord({ kind = "player" }, "Calloway Family") == nil,
    "a player-owned person is not a patrol contact")
assert(P.contactWord({ kind = "faction" }, "Calloway Family")
    == "a member of Calloway Family", "a faction contact keeps its name")
assert(P.contactWord({ kind = "independent" }, nil) == "a stranger",
    "an independent contact is a stranger")
assert(P.contactWord({ kind = "independent" }, nil, "Nora Vale") == "Nora Vale",
    "observer knowledge gives the individual name")
assert(P.sightingWord(0, nil, "a stranger") == "I see a stranger nearby.",
    "a person speaks even without zombies")
assert(P.sightingWord(0, "north", "a member of Calloway Family")
    == "I see a member of Calloway Family to the north.",
    "a person uses the same compass word")
assert(P.feedLine("I see a stranger nearby.") == "Patrol: I see a stranger nearby.",
    "a contact report is prefixed for the rail")
assert(P.feedLine(nil) == nil, "an empty report is not added to the rail")

assert(P.sightingDue(nil, 0, 1800) == true, "a first stop is due")
assert(P.sightingDue(100, 1899, 1800) == false, "a retelling gap holds")
assert(P.sightingDue(100, 1900, 1800) == true, "the gap expires")

print("PatrolSighting PASS compass=north shape=crowd direction=spoken")
