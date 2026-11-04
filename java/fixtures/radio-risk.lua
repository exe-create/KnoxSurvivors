-- D7.4: an unanswered call can be heard by someone else. The odds fall with a
-- practised operator and never reach zero, and the sentence said before the
-- switch is the same rule the tower rolls.
local R = codecRadioRisk

assert(R.radioRiskChance(0) == 0.30, "an untrained house is the loudest")
assert(R.radioRiskChance(nil) == 0.30)
assert(R.radioRiskChance(-2) == 0.30)
assert(R.radioRiskChance(1) == 0.26)
assert(R.radioRiskChance(3) == 0.18)
assert(R.radioRiskChance(6) == 0.06)
assert(R.radioRiskChance(9) == 0.06, "the risk is capped, never zero")

assert(R.radioRiskDue(nil, 500) == true, "a first call can always be heard")
assert(R.radioRiskDue(490, 500) == false, "the risk is checked once a day")
assert(R.radioRiskDue(476, 500) == true)
assert(R.radioRiskDue(nil, nil) == false)

assert(R.radioRiskRoll(0.05, 0.06) == true)
assert(R.radioRiskRoll(0.06, 0.06) == false, "the boundary is not a hit")
assert(R.radioRiskRoll(1.0, 0.5) == false, "a roll of one is not a probability")

local trained = R.radioRiskText(4)
local untrained = R.radioRiskText(nil)
assert(type(trained) == "string" and trained ~= "")
assert(type(untrained) == "string" and untrained ~= "")
assert(trained ~= untrained, "the line names who is working the set")
assert(string.find(untrained, "unfriendly", 1, true) ~= nil, "the line states the risk plainly")

print("Radio risk PASS chance=true interval=true roll=true text=true")
