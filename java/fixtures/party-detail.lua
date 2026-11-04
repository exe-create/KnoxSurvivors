local M = assert(KnoxSurvivorViewModel, "the survivor view model is loaded")
assert(type(M.partyDetail) == "function", "the hovered-row detail line is loaded")

-- The strip replaces a row's condition word with this line while the row is
-- hovered. Every case below is a shape the real snapshot producer writes:
-- a reported need behind the offscreen age prefix, an all-clear report that
-- carries no need at all, a body with unreadable vitals, and a survivor the
-- player cannot see.
local function detail(snapshot)
    return M.partyDetail(snapshot)
end

local bleeding = { alive = true, loaded = true,
    needSummary = "Last reported (4 min ago): Bitten, Bleeding" }
assert(detail(bleeding) == "Needs: Bitten, Bleeding",
    "a reported need reaches the row without its age prefix: "
        .. tostring(detail(bleeding)))

local thirsty = { alive = true, loaded = true,
    needSummary = "Last reported (2 min ago): Water" }
assert(detail(thirsty) == "Needs: Water",
    "one reported need reads as one word: " .. tostring(detail(thirsty)))

-- The offscreen projection writes "All right" when nothing crossed a
-- threshold, so a naive "Needs: " prefix would read "Needs: All right".
local clear = { alive = true, loaded = true,
    needSummary = "Last reported (5 min ago): All right" }
assert(detail(clear) == nil,
    "an all-clear report claims no need: " .. tostring(detail(clear)))

assert(detail({ alive = true, loaded = true }) == nil,
    "a live body with no report keeps its condition word")

assert(detail({ alive = true, loaded = true, needSummary = "Needs not reported" }) == nil,
    "an unreported body is not a need")

assert(detail({ alive = true, loaded = true,
    needSummary = "Condition unavailable" }) == nil,
    "unreadable vitals are not a need")

-- Out of contact. The snapshot producer overwrites locationLabel for an
-- unloaded survivor with its own framing ("Last seen - N min ago", or
-- "Location unknown" when no observation is stored), so the hovered line must
-- not add a second "Away" to it. These labels are the strings the producer
-- emits; each assertion pins the exact final text.
local lastSeen = { alive = true, loaded = false,
    needSummary = "Last reported (12 min ago): Food",
    locationLabel = "Last seen - 12 min ago" }
assert(detail(lastSeen) == "Last seen - 12 min ago",
    "an already-framed last-seen label is not framed twice: "
        .. tostring(detail(lastSeen)))

local noObservation = { alive = true, loaded = false,
    locationLabel = "Location unknown" }
assert(detail(noObservation) == "Location unknown",
    "an unknown place is not reported as an away place: "
        .. tostring(detail(noObservation)))

local assigned = { alive = true, loaded = false,
    locationLabel = "Away - assigned to Miller Farm" }
assert(detail(assigned) == "Away - assigned to Miller Farm",
    "the duty branch's own away label is not framed twice: "
        .. tostring(detail(assigned)))

-- A bare place can still reach the line from a record that stores only the
-- name; that is the one shape that needs the away framing.
local bareplace = { alive = true, loaded = false, locationLabel = "Miller Farm" }
assert(detail(bareplace) == "Away - Miller Farm",
    "a bare place takes the away framing: " .. tostring(detail(bareplace)))

local noPlace = { alive = true, loaded = false }
assert(detail(noPlace) == "Away",
    "an out-of-contact survivor with no label still says Away: "
        .. tostring(detail(noPlace)))

local emptyPlace = { alive = true, loaded = false, locationLabel = "" }
assert(detail(emptyPlace) == "Away",
    "an empty label says Away rather than a bare dash: "
        .. tostring(detail(emptyPlace)))

assert(detail({ alive = false, loaded = false, needSummary = "Last reported (1 min ago): Bitten" })
    == "Dead", "death outranks every other line")

assert(detail(nil) == nil, "a missing snapshot has no line")
assert(detail("Iris") == nil, "a non-table snapshot has no line")

assert(type(M.hoverKeepsCondition) == "function",
    "the critical-condition rule is loaded")
assert(M.hoverKeepsCondition("critical") == true,
    "a critical condition survives hover")
assert(M.hoverKeepsCondition("warn") == false,
    "a warning can yield to detail")
assert(M.hoverKeepsCondition("good") == false,
    "a good condition can yield")
assert(M.hoverKeepsCondition(nil) == false,
    "an unknown tone can yield")

print("Party detail PASS needs=true away=framed-once bare-place=true dead=true hover=true")
