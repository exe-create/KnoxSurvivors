local control = assert(codecGuardControl, "the guard control rule is loaded")

local open = control(true)
assert(open.available == true, "dusk and night allow the temporary block")
assert(open.title == "Guard Tonight", "an available control uses its action name")
assert(string.find(open.tooltip, "Expires at the next block", 1, true) ~= nil,
    "an available control states when it ends")

local closed = control(false)
assert(closed.available == false, "day and afternoon refuse the temporary block")
assert(closed.title ~= open.title, "a refused control does not look like an available one")
assert(string.find(closed.title, "night only", 1, true) ~= nil,
    "the refused control names its own restriction")
assert(string.find(closed.tooltip, "Saved hours still apply", 1, true) ~= nil,
    "the refusal says the schedule is unaffected")

local unknown = control(nil)
assert(unknown.available == false, "a missing window is not availability")
assert(unknown.title == closed.title, "a missing window reads like any other refusal")

print("Notebook guard PASS available_named=true refusal_named=true")
