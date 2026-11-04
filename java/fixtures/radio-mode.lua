-- The radio's three modes, and what an unknown or missing mode reads as.
local R = codecRadioMode

assert(type(R.radioModeLabel) == "function", "radioModeLabel must exist")

assert(R.radioModeLabel("off") == "Off")
assert(R.radioModeLabel("listen") == "Listening")
assert(R.radioModeLabel("broadcast") == "Calling on the radio")

-- An old save, a typo or a mode from a later build is inert: the radio is off,
-- never silently treated as broadcasting.
assert(R.radioModeLabel(nil) == "Off")
assert(R.radioModeLabel("") == "Off")
assert(R.radioModeLabel("BROADCAST") == "Off", "modes are exact, not case-folded")
assert(R.radioModeLabel("shouting") == "Off")

-- The menu only offers a change away from the current mode.
assert(type(R.radioModeIsCurrent) == "function", "radioModeIsCurrent must exist")
assert(R.radioModeIsCurrent("off", "off") == true)
assert(R.radioModeIsCurrent("listen", "off") == false)
assert(R.radioModeIsCurrent(nil, "off") == true, "a missing mode is the off mode")

print("Radio mode PASS labels=true exact=true inert=true")
