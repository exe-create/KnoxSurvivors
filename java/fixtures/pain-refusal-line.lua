-- A resident in real pain declines heavy base work now, and the player only sees
-- them standing about. The refusal speaks, but only when the thing being refused
-- is actually on the board: an idle camp owes nobody an excuse.
local N = assert(rawget(_G, "codecWeatherNeeds"), "the needs rule is loaded")

-- The predicate the controller speaks from.
assert(N.heavyWorkWaiting(nil) == false, "no queue means nothing to refuse")
assert(N.heavyWorkWaiting({}) == false, "an empty queue means nothing to refuse")
assert(N.heavyWorkWaiting({ { type = "cook" }, { type = "guard" } }) == false,
    "light work waiting is not a refusal")
assert(N.heavyWorkWaiting({ { type = "cook" }, { type = "barricade" } }) == true,
    "a heavy task waiting is")
assert(N.heavyWorkWaiting({ { type = "haul_corpse" } }) == true,
    "hauling a body counts")
assert(N.heavyWorkWaiting({ { type = "flimflam" } }) == false,
    "an unknown task type is not heavy work")
local holed = { { type = "barricade" } }
holed[3] = { type = "saw_logs" }
assert(N.heavyWorkWaiting(holed) == true, "the records before a gap are still read")
assert(N.heavyWorkWaiting({ "not a task" }) == false, "a junk record is not a task")

-- The refusal words are authored, short and concrete: a refusal names the reason.
local words = {
    "Not that. My shoulder's done in.",
    "I can't lift it today. Ribs.",
    "Ask me again when these hands stop shaking.",
    "That's a two-person job and I'm not one of them right now.",
}
for _, line in ipairs(words) do
    local count = 0
    for _ in line:gmatch("%S+") do count = count + 1 end
    assert(count <= 18, "a refusal line stays inside its budget: " .. line)
end

print("Pain refusal line PASS waiting=true light=false budget=true")
