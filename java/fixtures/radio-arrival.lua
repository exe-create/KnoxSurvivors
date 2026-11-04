-- D7.3: a broadcast is answered by chance once a day, and only when a living
-- resident can work the set. The roll is handed in so the rule is checkable.
local R = codecRadioArrival

-- The operator is the strongest living resident, exactly as the menu decides.
assert(type(R.radioOperatorLevel) == "function", "radioOperatorLevel must exist")
assert(R.radioOperatorLevel({}) == nil, "an empty house has no operator")
assert(R.radioOperatorLevel(nil) == nil)
assert(R.radioOperatorLevel({ 0, 3, 1 }) == 3, "the strongest resident answers")
assert(R.radioOperatorLevel({ "4", 2 }) == 4, "levels may arrive as strings")

-- Electrical level sets the odds, and an untrained house has none.
assert(R.radioArrivalChance(nil) == 0)
assert(R.radioArrivalChance(0) == 0, "no operator, no chance")
assert(R.radioArrivalChance(1) == 0.15)
assert(R.radioArrivalChance(3) == 0.25)
assert(R.radioArrivalChance(6) == 0.40)
assert(R.radioArrivalChance(9) == 0.40, "the chance is capped")

-- Only a broadcast is a call; listening is not transmitting.
local due, why = R.radioArrivalDue("off", nil, 100)
assert(due == false and why == "not_broadcasting")
due, why = R.radioArrivalDue("listen", nil, 100)
assert(due == false and why == "not_broadcasting")
due, why = R.radioArrivalDue("broadcast", nil, 100)
assert(due == true, "a first call is due immediately")
due, why = R.radioArrivalDue("broadcast", nil, nil)
assert(due == false and why == "no_clock")

-- One call a day: a full day must pass before the next one is due.
due, why = R.radioArrivalDue("broadcast", 100, 123.5)
assert(due == false and why == "recent")
due = R.radioArrivalDue("broadcast", 100, 124)
assert(due == true, "a full day reopens the call")

-- The roll decides, and the boundary is exact rather than a rounding accident.
local answered, reason = R.radioArrivalRoll(0.24, 0.25)
assert(answered == true and reason == "answered")
answered, reason = R.radioArrivalRoll(0.25, 0.25)
assert(answered == false and reason == "quiet", "the boundary is not a hit")
answered = R.radioArrivalRoll(0.0, 0.25)
assert(answered == true)
answered = R.radioArrivalRoll(0.99, 0.40)
assert(answered == false)
answered, reason = R.radioArrivalRoll(1.0, 0.40)
assert(answered == false and reason == "invalid_roll", "a roll of one is not a probability")
answered, reason = R.radioArrivalRoll(-0.1, 0.40)
assert(answered == false and reason == "invalid_roll")
answered, reason = R.radioArrivalRoll(0.5, 0)
assert(answered == false and reason == "no_operator")

-- The plan composes the gates and names the one that stopped it.
local ok, how = R.radioArrivalPlan("listen", 5, nil, 500, 0.01)
assert(ok == false and how == "not_broadcasting")
ok, how = R.radioArrivalPlan("broadcast", 0, nil, 500, 0.01)
assert(ok == false and how == "no_operator")
ok, how = R.radioArrivalPlan("broadcast", 5, 490, 500, 0.01)
assert(ok == false and how == "recent")
local chance
ok, how, chance = R.radioArrivalPlan("broadcast", 5, nil, 500, 0.34)
assert(ok == true and how == "answered" and chance == 0.35)
ok, how = R.radioArrivalPlan("broadcast", 5, nil, 500, 0.36)
assert(ok == false and how == "quiet")

print("Radio arrival PASS chance=true interval=true roll=true gates=true")
