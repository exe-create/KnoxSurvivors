-- The status line for a base radio: what the audited device and object really
-- answer, and nothing assumed when a reader is missing.
local S = codecRadioStatus

assert(type(S.radioStatusText) == "function", "radioStatusText must exist")

local onGrid = S.radioStatusText({ on = true, grid = true, range = 7500 })
assert(string.find(onGrid, "switched on", 1, true) ~= nil, "a powered set reads as on")
assert(string.find(onGrid, "grid", 1, true) ~= nil, "grid power is named")
assert(string.find(onGrid, "transmit 7500", 1, true) ~= nil, "the script range is shown")

local offBattery = S.radioStatusText({ on = false, battery = true, range = "20000" })
assert(string.find(offBattery, "switched off", 1, true) ~= nil)
assert(string.find(offBattery, "battery", 1, true) ~= nil)
assert(string.find(offBattery, "transmit 20000", 1, true) ~= nil,
    "a numeric string range is read as a number")

-- Grid outranks a generator, and a generator outranks a battery: the line names
-- the source that is actually feeding the set.
local both = S.radioStatusText({ on = true, grid = true, generator = true, battery = true })
assert(string.find(both, "grid", 1, true) ~= nil)
assert(string.find(both, "generator", 1, true) == nil, "one power source is named")
local gen = S.radioStatusText({ on = true, generator = true, battery = true })
assert(string.find(gen, "generator", 1, true) ~= nil)

-- No reader answered: say no power rather than guess.
local dead = S.radioStatusText({ on = false })
assert(string.find(dead, "no power", 1, true) ~= nil)
assert(dead == "Radio: switched off · no power", "the empty case is one plain sentence")

-- A missing or zero range is omitted, not shown as a zero.
assert(string.find(S.radioStatusText({ on = true, grid = true, range = 0 }), "transmit", 1, true) == nil)
assert(string.find(S.radioStatusText({ on = true, grid = true, range = "far" }), "transmit", 1, true) == nil)

-- A missing table is the empty case, not an error.
assert(S.radioStatusText(nil) == "Radio: switched off · no power")

print("Radio status PASS on=true off=true power=grid-generator-battery range=true empty=true")
