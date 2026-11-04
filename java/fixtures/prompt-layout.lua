-- A strip that is clipped to the screen must be centred by the room it has left.
-- The rule is pure arithmetic, so a narrow display is provable without one.
local Prompt = assert(rawget(_G, "codecPromptLayout"), "prompt layout missing")
assert(type(Prompt.centreOffset) == "function", "centreOffset missing")

assert(Prompt.centreOffset(1920, 410) == 755, "a wide screen centres exactly")
assert(Prompt.centreOffset(240, 220) == 10, "a narrow screen leaves ten pixels a side")
assert(Prompt.centreOffset(200, 220) == 0, "a box wider than the screen starts at the edge")
assert(Prompt.centreOffset(0, 410) == 0, "no screen is no offset")
assert(Prompt.centreOffset(1920, 0) == 0, "no box is no offset")
assert(Prompt.centreOffset(nil, 410) == 0, "a missing screen is no offset")
assert(Prompt.centreOffset("1920", "410") == 755, "numeric strings count as numbers")
assert(Prompt.centreOffset(1001, 400) == 300, "an odd gap floors, so it never drifts right")

-- The centred box always fits: left edge plus width never passes the screen.
for _, case in ipairs({ { 1920, 410 }, { 240, 220 }, { 800, 500 }, { 1001, 400 } }) do
    local screen, width = case[1], case[2]
    local left = Prompt.centreOffset(screen, width)
    assert(left >= 0, "the offset is never negative")
    assert(left + width <= screen, "the box fits at " .. tostring(screen))
end
