-- A rally corner that cannot be walked to is not a fallback. The base owner
-- ranks every corner it can offer; one pure screen decides which of them a body
-- can actually reach, from evidence the caller gathered. This drives both
-- production functions: the ranking must keep the old best corner first, and no
-- square may be admitted on a missing proof.
local R = assert(codecBaseRally, "the base owner is extracted")
local ranked = assert(R.rallyCandidates, "the base ranks its corners")
local A = assert(codecRallyAdmission, "the rally screen is extracted")
local admit = assert(A.rallyAdmission, "the screen decides which square is taken")
local DEFAULT_CLEARANCE2 = A.RALLY_DEFAULT_CLEARANCE2
assert(type(DEFAULT_CLEARANCE2) == "number", "the default clearance is a number")

local walls = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0 }
local threat = { x = 11, y = 15, z = 0 }

-- EVERY CORNER, BEST FIRST, AND THE OLD CHOICE IS STILL THE FIRST ENTRY.
local corners = assert(ranked(walls, threat))
assert(#corners == 4, "a rectangular base offers four corners")
assert(corners[1].x == 19 and corners[1].y == 11,
    "the ranking opens with the corner the base would have picked")
assert(corners[1].distance2 == 64 + 16, "the first distance is the real one")
assert(corners[2].distance2 <= corners[1].distance2
    and corners[3].distance2 <= corners[2].distance2
    and corners[4].distance2 <= corners[3].distance2,
    "the list is ordered farthest first")
assert(corners[1].z == 0, "every corner is on the intruder's floor")
assert(corners[1].reason == "away_from_threat"
    and corners[1].cornered == false,
    "a far corner is not reported as cornered")

-- THE TIE STILL RESOLVES WHERE IT ALWAYS DID.
local wide = { minX = 0, minY = 0, width = 41, height = 41, z = 2 }
local tied = assert(ranked(wide, { x = 20, y = 20, z = 2 }))
assert(tied[1].x == 1 and tied[1].y == 1 and tied[1].distance2 == 722,
    "a symmetric threat keeps the historical corner at the head of the list")
assert(tied[2].x == 39 and tied[2].y == 1,
    "equal scores keep the corner order instead of shuffling")

-- A BASE WITH NOWHERE TO RUN SAYS SO ON EVERY CORNER.
local tiny = assert(ranked({ minX = 10, minY = 10, maxX = 10, maxY = 10, z = 0 },
    { x = 10, y = 10, z = 0 }))
assert(#tiny == 4 and tiny[1].x == 10 and tiny[1].y == 10,
    "a one-tile base still offers its own tile")
assert(tiny[1].cornered == true and tiny[1].reason == "cornered",
    "the head of the list admits there is no room left")

-- REFUSALS AND OPTIONS BELONG TO THE SAME OWNER.
assert(ranked(nil, threat) == nil, "no walls, no ranked corner")
assert(ranked({ minX = 20, minY = 10, maxX = 10, maxY = 20 }, threat) == nil,
    "an inverted rectangle is not a wall")
assert(ranked(walls, { x = 11 }) == nil, "half a threat ranks nothing")
assert(ranked(walls, nil) == nil, "no threat ranks nothing")
local deep = assert(ranked(walls, threat, { inset = 3 }))
assert(deep[1].x == 17 and deep[1].y == 13, "a deeper inset still ranks first")

-- THE SCREEN. The caller ranks, so the first admissible square wins.
local function square(x, y, extra)
    local entry = { x = x, y = y, standable = true, laneClear = true,
        routeSafe = true, threatDistance2 = 100 }
    for key, value in pairs(extra or {}) do entry[key] = value end
    return entry
end

local chosen, reason = admit({ square(19, 11, { laneClear = false }), square(11, 19) })
assert(chosen ~= nil and chosen.x == 11 and chosen.y == 19,
    "a blocked best corner yields to the next one instead of losing the fallback")
assert(reason == nil, "an admitted square is not reported as a refusal")

local same, _, index = admit({ square(19, 11) })
assert(same ~= nil and index == 1, "the screen returns the entry and its rank")

-- EVERY REFUSAL SHAPE.
local function refusal(list, options)
    local none, why = admit(list, options)
    return none == nil and why or "admitted"
end
assert(refusal({}) == "no_candidates", "an empty list is not a destination")
assert(refusal(nil) == "no_candidates", "no list is not a destination")
assert(refusal({ square(19, 11, { standable = false }) }) == "not_standable",
    "a square a body cannot stand on is not a fallback")
local unproven = square(19, 11)
unproven.standable = nil
assert(refusal({ unproven }) == "not_standable",
    "an unproven stance is refused rather than assumed")
assert(refusal({ square(19, 11, { laneClear = false }) }) == "lane_blocked",
    "a walk that cannot be taken is not a fallback")
assert(refusal({ square(19, 11, { routeSafe = false }) }) == "through_threat",
    "a walk through the intruder is not a fallback")
assert(refusal({ square(19, 11, { threatDistance2 = 9 }) }) == "too_close",
    "a corner beside the intruder is not a fallback")
assert(refusal({ square(19, 11, { threatDistance2 = DEFAULT_CLEARANCE2 }) }) == "admitted",
    "the clearance bound is inclusive, not one tile short")
assert(refusal({ square(19, 11, { threatDistance2 = 4 }) },
    { minimumClearance2 = 4 }) == "admitted",
    "the caller can relax the clearance for a small home")
assert(refusal({ { standable = true, laneClear = true, routeSafe = true } })
    == "no_square", "evidence without coordinates is not a square")
assert(refusal({ "corner" }) == "no_square", "a word is not a square")
assert(refusal({ square(19, 11, { standable = false }),
    square(11, 19, { laneClear = false }) }) == "not_standable",
    "the best square's refusal is the answer when none survives")
assert(refusal({ square(19, 11, { standable = false, laneClear = false }) })
    == "not_standable", "one square reports its first refusal, not a guess")
assert(refusal({ square(19, 11, { threatDistance2 = "100" }) }) == "admitted",
    "numeric strings still compare as distances")
