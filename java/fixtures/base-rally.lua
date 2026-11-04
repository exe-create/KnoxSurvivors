-- A home under raid needs a square to fall back to, not just a direction to run
-- in. The base owner already knows its own walls, so it owns the choice: this
-- drives the real resolver, then the real alarm answer that now uses it, so an
-- unarmed civilian withdraws instead of standing in the room a raider works.
local R = assert(codecBaseRally, "the base owner is extracted")
local rally = assert(R.defenceRally, "the base can name a rally square")
local C = assert(codecAlarmAnswer, "the alarm answer is extracted")
local answer = assert(C.baseAlarmAnswer, "the alarm asks one question")
local WITHDRAW = assert(C.ALARM_ANSWER_WITHDRAW, "the fourth answer is named")
local CLEAR, CONVERGE, NONE = C.ALARM_ANSWER_STAND_CLEAR,
    C.ALARM_ANSWER_CONVERGE, C.ALARM_ANSWER_NONE

local walls = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0 }

-- THE CORNER FARTHEST FROM THE INTRUDER, INSET ONE TILE.
local west = rally(walls, { x = 11, y = 15, z = 0 })
assert(west ~= nil, "a threat inside the walls still names a corner")
assert(west.x == 19 and west.y == 11,
    "the far corner from a western intruder is the eastern one")
assert(west.z == 0, "the rally square is on the intruder's floor")
assert(west.reason == "away_from_threat",
    "a corner far from the fight is not reported as cornered")

local east = rally(walls, { x = 19, y = 11, z = 0 })
assert(east.x == 11 and east.y == 19,
    "the choice follows the intruder instead of being fixed")
assert(east.distance2 == 64 + 64,
    "the recorded distance is the real squared distance")

-- A BASE WITH NO ROOM LEFT SAYS SO.
local tiny = { minX = 10, minY = 10, maxX = 10, maxY = 10, z = 0 }
local cornered = rally(tiny, { x = 10, y = 10, z = 0 })
assert(cornered ~= nil and cornered.x == 10 and cornered.y == 10,
    "a one-tile base offers its own tile")
assert(cornered.cornered == true and cornered.reason == "cornered",
    "a base with nowhere to run says so instead of pretending it is safe")

-- TERRITORY SHAPES THE BASE OWNER ALREADY STORES.
local wide = { minX = 0, minY = 0, width = 41, height = 41, z = 2 }
local sized = rally(wide, { x = 20, y = 20, z = 2 })
assert(sized ~= nil and sized.x == 1 and sized.y == 1,
    "a width/height territory is honoured and a symmetric threat is deterministic")
assert(sized.distance2 == 722, "the squared distance is real arithmetic")
assert(sized.z == 2, "the floor comes from the threat when the base stores one")

local deeper = rally(walls, { x = 11, y = 15, z = 0 }, { inset = 3 })
assert(deeper.x == 17 and deeper.y == 13,
    "the caller can ask for a deeper inset")
local noInset = rally(walls, { x = 11, y = 15, z = 0 }, { inset = -4 })
assert(noInset.x == 20 and noInset.y == 10,
    "a negative inset is not a hole in the wall")

-- REFUSALS. No guessed walls, no guessed direction.
assert(rally(nil, { x = 1, y = 1 }) == nil, "no walls, no rally")
assert(rally({}, { x = 1, y = 1 }) == nil, "empty bounds are not a wall")
assert(rally({ minX = 20, minY = 10, maxX = 10, maxY = 20 }, { x = 1, y = 1 }) == nil,
    "an inverted rectangle is not a wall")
assert(rally(walls, nil) == nil, "no threat, no direction to fall back from")
assert(rally(walls, { x = 11 }) == nil, "half a threat is not a direction")
assert(rally(walls, "west") == nil, "a word is not a direction")
assert(rally(walls, { x = "11", y = "15", z = 0 }).x == 19,
    "numeric strings still compare as coordinates")

-- THE ALARM USES IT.
local alarm = { x = 12, y = 12, z = 0, untilTick = 1800 }
local goal = rally(walls, { x = alarm.x, y = alarm.y, z = alarm.z })
assert(goal ~= nil, "the alarm's own square can seed the rally")
assert(answer({ alarm = alarm, ticks = 0, armed = false, guard = false, rally = goal })
    == WITHDRAW, "an unarmed civilian with somewhere to go withdraws")
assert(answer({ alarm = alarm, ticks = 0, armed = false, guard = false }) == CLEAR,
    "with no rally the unarmed civilian still stays clear")
assert(answer({ alarm = alarm, ticks = 0, armed = false, guard = false, rally = "corner" })
    == CLEAR, "a rally that is not a square is not a destination")
assert(answer({ alarm = alarm, ticks = 0, armed = true, rally = goal }) == CONVERGE,
    "an armed resident still answers the intruder")
assert(answer({ alarm = alarm, ticks = 0, armed = false, guard = true, rally = goal })
    == CONVERGE, "a scheduled guard still holds the post")
assert(answer({ alarm = alarm, ticks = 1801, armed = false, rally = goal }) == NONE,
    "an expired alarm sends nobody anywhere")
assert(answer({ alarm = alarm, ticks = 0, armed = false, onDuty = true, rally = goal })
    == NONE, "a tasked civilian is not pulled off their work by a fallback")
assert(answer({ alarm = { x = 1, y = 1 }, ticks = 0, armed = false, rally = goal })
    == WITHDRAW, "an unstamped alarm is still live rather than expired by nil arithmetic")
