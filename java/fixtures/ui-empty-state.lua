-- The empty state: copy wrapped to the page, plus the one action that ends it.
-- A state with no action stays visibly actionless rather than offering a button
-- that does nothing. Pure, with the measure injected.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.emptyState) == "function", "the layout owns the empty state")

local function measure(value) return #value end

local state = L.emptyState(
    "No trips out. Dispatch a survivor to gather supplies, scout a building or check on a neighbour.",
    "Dispatch...", 20, { measure = measure })
assert(state.showsAction == true, "an action is offered when one exists")
assert(state.action == "Dispatch...", "the action keeps its label")
assert(#state.lines > 1, "long copy wraps instead of running off the page, got " .. #state.lines)
for _, line in ipairs(state.lines) do
    assert(#line <= 20, "every wrapped line fits the page, got '" .. line .. "'")
end

local short = L.emptyState("Nothing here", nil, 200, { measure = measure })
assert(short.showsAction == false, "no action means no button")
assert(short.action == nil, "no action means no label")
assert(#short.lines == 1, "fitting copy stays one line, got " .. #short.lines)

local silent = L.emptyState("", nil, 200, { measure = measure })
assert(#silent.lines == 0, "empty copy draws nothing")

local wordy = L.emptyState("one two three four five six", nil, 10, { measure = measure })
assert(#wordy.lines > 1, "narrow copy wraps")
for _, line in ipairs(wordy.lines) do
    assert(#line <= 10, "no line exceeds the page, got '" .. line .. "'")
end
