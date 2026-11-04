-- A home alarm is not a command for everybody in the house. The design says a
-- resident with no weapon must not charge a rifle line, and the base already
-- had a report for the unarmed defender who did exactly that. This drives the
-- one decision that now sits between the alarm and the walk: who goes, who
-- keeps their post, and who stays clear.
local C = assert(codecAlarmAnswer, "the alarm answer section is extracted")
local answer = assert(C.baseAlarmAnswer, "the alarm asks one question of one resident")
local NONE, CONVERGE, CLEAR = C.ALARM_ANSWER_NONE, C.ALARM_ANSWER_CONVERGE,
    C.ALARM_ANSWER_STAND_CLEAR

local function alarm(untilTick)
    return { x = 10, y = 10, z = 0, untilTick = untilTick or 1800 }
end

assert(NONE == "none" and CONVERGE == "converge" and CLEAR == "stand_clear",
    "the three answers are named, not guessed")

-- WHO GOES.
assert(answer({ alarm = alarm(1800), ticks = 0, armed = true }) == CONVERGE,
    "an armed resident answers the alarm")
assert(answer({ alarm = alarm(1800), ticks = 0, armed = false, guard = true }) == CONVERGE,
    "a guard answers even with nothing in their hands")
assert(answer({ alarm = alarm(1800), ticks = 0, armed = false, guard = false }) == CLEAR,
    "an empty-handed civilian stays clear of the fight")

-- WHO DOES NOT.
assert(answer({ alarm = alarm(1800), ticks = 1799, armed = false }) == CLEAR,
    "one tick before expiry the alarm still asks")
assert(answer({ alarm = alarm(1800), ticks = 1801, armed = true }) == NONE,
    "an expired alarm asks nobody, armed or not")
assert(answer({ alarm = alarm(1800), ticks = 1800, armed = true }) == CONVERGE,
    "the alarm is live through its last tick")
assert(answer({ alarm = alarm(1800), ticks = 0, armed = true, onDuty = true }) == NONE,
    "a resident with a task keeps their post")
assert(answer({ alarm = alarm(1800), ticks = 0, armed = false, onDuty = true }) == NONE,
    "a tasked civilian is not re-tasked by the alarm either")

-- WHAT COUNTS AS ARMED.
assert(answer({ alarm = alarm(1800), ticks = 0, armed = nil, guard = nil }) == CLEAR,
    "unknown hands are not a weapon")
assert(answer({ alarm = alarm(1800), ticks = 0, armed = "yes", guard = "guard" }) == CLEAR,
    "a truthy non-boolean is not a decision")

-- NO ALARM AT ALL.
assert(answer({ alarm = nil, ticks = 0, armed = true }) == NONE, "no alarm asks nothing")
assert(answer(nil) == NONE, "no question asks nothing")
assert(answer("alarm") == NONE, "a non-table question asks nothing")
assert(answer({}) == NONE, "an empty question asks nothing")
assert(answer({ alarm = { x = 1, y = 1 }, ticks = 0, armed = true }) == CONVERGE,
    "an unstamped alarm is live rather than expired by nil arithmetic")
