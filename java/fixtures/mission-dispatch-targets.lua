-- The Missions tab can now issue a base mission without the world context menu.
-- The dispatch owner needs a real loaded square, so the chooser offers the
-- buildings the player can see: this fixture proves the destination scan (dedupe,
-- nearest first, own home skipped, radius and limit honoured) and that the
-- place → mission → party chain calls the one existing dispatch owner with the
-- chosen place's nearest square, and issues nothing when any step is cancelled.
local T = KnoxMissionTargets
assert(type(T) == "table" and type(T.scan) == "function",
    "the mission target owner must be loaded")

local function building(id, name)
    return {
        getIDString = function() return id end,
        getDef = function() return { getName = function() return name end } end,
    }
end

local function square(x, y, owner)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
        getBuilding = function() return owner end,
    }
end

local homes = building("home-1", "house")
local shed = building("shed-1", "shed")
local store = building("store-1", "general store")
local barn = building("barn-1", "barn")
local layout = {
    ["0:0"] = square(0, 0, nil),
    ["1:0"] = square(1, 0, shed),
    ["2:0"] = square(2, 0, shed),
    ["5:0"] = square(5, 0, store),
    ["0:-3"] = square(0, -3, homes),
    ["60:0"] = square(60, 0, barn),
}
local cell = {
    getGridSquare = function(_, x, y) return layout[x .. ":" .. y] end,
}

-- One destination per building, nearest part of it, own home and far places out.
local places = T.scan(cell, 0, 0, 0, { skipBuildingId = "home-1" })
assert(#places == 2, "two visible buildings besides the player's own home, got " .. tostring(#places))
assert(places[1].id == "shed-1" and places[1].distance == 1,
    "the nearest building comes first")
assert(places[1].square:getX() == 1,
    "a building is represented by its nearest square, not a later one")
assert(places[1].name == "Shed (1, 0)", "the label names the building and where it is")
assert(places[2].id == "store-1" and places[2].name == "General store (5, 0)",
    "the far building keeps its own name")
for _, place in ipairs(places) do
    assert(place.id ~= "home-1", "the player's own home is never a mission destination")
end

assert(#T.scan(cell, 0, 0, 0, { skipBuildingId = "home-1", radius = 3 }) == 1,
    "the radius is a real bound")
assert(#T.scan(cell, 0, 0, 0, { skipBuildingId = "home-1", limit = 1 }) == 1,
    "the chooser list is bounded")
assert(#T.scan(nil, 0, 0, 0) == 0 and #T.scan(cell, nil, 0, 0) == 0,
    "a missing cell or origin gives no destinations rather than guessing")
assert(#T.scan(cell, 0, 0, 0) == 3, "without the home filter the home building is offered")

local player = { getCurrentSquare = function() return square(0, 0, nil) end }
assert(#T.visibleBuildings(0, { player = player, cell = cell, skipBuildingId = "home-1" }) == 2,
    "the player-facing list starts from the player's own square")

-- The order is place, then mission, then party size, then the dispatch owner.
local base = { id = "base-1", home = { buildingId = "home-1" } }
local prompts, entryCounts, calls, notices = {}, {}, {}, {}
local answers = { { "shed-1" }, { "food" }, { "2" } }
local function choose(prompt, entries, callback)
    prompts[#prompts + 1] = prompt
    entryCounts[#prompts] = #(entries or {})
    local answer = table.remove(answers, 1)
    assert(answer ~= nil, "an unexpected chooser opened: " .. tostring(prompt))
    if answer[1] ~= "cancel" then callback(answer[1]) end
    return true
end
local function dispatch(targetBase, targetSquare, size, kind)
    calls[#calls + 1] = { base = targetBase, square = targetSquare, size = size, kind = kind }
    return true
end
local function run(options)
    prompts, entryCounts, calls, notices = {}, {}, {}, {}
    -- Explicit nil assignment: `flag and nil or base` can never produce nil.
    local playerOption = player
    if options.noPlayer then playerOption = nil end
    local baseOption = base
    if options.noBase then baseOption = nil end
    if options.base ~= nil then baseOption = options.base end
    -- A standing crew unless a case is about the crew itself. Real availability
    -- needs loaded bodies, which this harness has none of; `realAvailability`
    -- leaves the check to whatever the dispatch owner currently is.
    local availabilityOption = options.availability
    if availabilityOption == nil and not options.realAvailability then
        availabilityOption = function() return 3, nil end
    end
    return T.dispatchFlow(0, {
        player = playerOption,
        base = baseOption,
        cell = options.cell or cell,
        anchor = options.anchor,
        choose = choose,
        dispatch = dispatch,
        availability = availabilityOption,
        notice = function(text) notices[#notices + 1] = text end,
    })
end

assert(run({}) == true, "the flow opens its first chooser")
assert(#prompts == 3, "place, mission and party are asked in that order")
assert(#calls == 1, "exactly one dispatch is issued")
assert(calls[1].base == base and calls[1].kind == "food" and calls[1].size == 2,
    "the chosen mission and party size reach the dispatch owner")
assert(calls[1].square:getX() == 1 and calls[1].square:getY() == 0,
    "the dispatch receives the chosen building's nearest real square")
assert(#notices == 0, "a completed order says nothing extra; the dispatch owner reports it")

answers = { { "shed-1" }, { "cancel" } }
assert(run({}) == true and #calls == 0,
    "cancelling the mission type issues nothing")
answers = { { "shed-1" }, { "food" }, { "cancel" } }
assert(run({}) == true and #calls == 0,
    "cancelling the party size issues nothing")
answers = { { "cancel" } }
assert(run({}) == true and #calls == 0 and #prompts == 1,
    "cancelling the destination issues nothing")
answers = { { "no-such-building" } }
assert(run({}) == true and #calls == 0 and #prompts == 1,
    "an unknown destination id issues nothing")

-- Nobody free to send: the refusal arrives with the question, not after it.
answers = { { "shed-1" }, { "food" } }
assert(run({ availability = function() return 0, "need_settled_resident" end }) == true,
    "the flow stops once the crew check refuses")
assert(#prompts == 2, "the party size is never asked when nobody can go")
assert(#calls == 0, "a refused order dispatches nothing")
assert(#notices == 1 and string.find(notices[1], "busy", 1, true) ~= nil,
    "the refusal says why, in the player's words")

-- The party question offers only the crew that could actually go.
answers = { { "shed-1" }, { "scout" }, { "1" } }
run({ availability = function() return 1, nil end })
assert(entryCounts[3] == 1, "one available resident means one party choice")
assert(#calls == 1 and calls[1].size == 1,
    "the only offered size is the size dispatched")

answers = { { "shed-1" }, { "food" }, { "2" } }
run({ availability = function() return 2, nil end })
assert(entryCounts[3] == 2, "two available residents mean two choices")
assert(calls[1].size == 2, "the second choice is still a real size")

answers = { { "shed-1" }, { "scout" }, { "3" } }
run({ availability = function() return 9, nil end })
assert(entryCounts[3] == 3, "the list never grows past the three-resident cap")
assert(calls[1].size == 3, "a larger available crew still dispatches the chosen size")

assert(#T.partyChoices(0) == 0 and #T.partyChoices(nil) == 0,
    "nobody available means no party question at all")
local twoChoices = T.partyChoices(2)
assert(#twoChoices == 2 and twoChoices[1].id == T.PARTY_CHOICES[1].id
    and twoChoices[2].name == T.PARTY_CHOICES[2].name,
    "trimmed choices keep the real labels in their real order")
assert(#T.partyChoices(2.9) == 2, "a fractional count is floored, not rounded up")
assert(#T.partyChoices(99) == #T.PARTY_CHOICES, "a huge count is still capped")

-- The check is asked after the mission type, with that type and the chosen place.
local asked = nil
answers = { { "shed-1" }, { "tools" } }
run({ availability = function(targetBase, kind, squareChoice)
    asked = { base = targetBase, kind = kind, x = squareChoice:getX() }
    return 0, "need_loaded_base_resident"
end })
assert(asked ~= nil and asked.base == base and asked.kind == "tools" and asked.x == 1,
    "the crew check receives the chosen base, mission type and destination square")
assert(string.find(notices[1], "loaded world", 1, true) ~= nil,
    "an unloaded base is explained as such")

-- A refusal never depends on the caller remembering to check it.
for reason, text in pairs(T.AVAILABILITY_TEXT) do
    assert(type(text) == "string" and text ~= "",
        "every refusal reason has player wording: " .. tostring(reason))
    assert(string.find(text, reason, 1, true) == nil,
        "the wording is prose, not the internal code: " .. tostring(reason))
end
assert(string.find(T.availabilityText("need_settled_resident"), "need_", 1, true) == nil,
    "a known reason never leaks its code")
assert(string.find(T.availabilityText("something_new"), "something new", 1, true) ~= nil,
    "an unknown reason is still readable")

-- With no dispatch owner loaded, the default check refuses instead of guessing.
local previousAutonomy = KnoxSurvivorAutonomy
KnoxSurvivorAutonomy = nil
local count, reason = T.availability(base, "scout", places[1].square, { player = player })
assert(count == 0 and reason == "dispatch_unavailable",
    "a missing dispatch owner is an explained refusal")
-- The real check is the dispatch owner's, not a second copy of its rules.
local forwarded = nil
KnoxSurvivorAutonomy = { baseMissionAvailability = function(passedPlayer, baseId, kind, squareChoice)
    forwarded = { player = passedPlayer, baseId = baseId, kind = kind, x = squareChoice:getX() }
    return 2, nil
end }
count, reason = T.availability(base, "medicine", places[1].square, { player = player })
assert(count == 2 and reason == nil, "the real availability answer is passed through")
assert(forwarded.player == player and forwarded.baseId == "base-1"
    and forwarded.kind == "medicine" and forwarded.x == 1,
    "the dispatch owner receives the player, base, type and destination")
KnoxSurvivorAutonomy = previousAutonomy

-- The player the flow resolves is the player the crew check asks about, even
-- when the caller left the player implicit.
local previousLookup = getSpecificPlayer
getSpecificPlayer = function() return player end
local checkedPlayer = nil
KnoxSurvivorAutonomy = { baseMissionAvailability = function(passedPlayer)
    checkedPlayer = passedPlayer
    return 1, nil
end }
answers = { { "shed-1" }, { "scout" }, { "1" } }
run({ noPlayer = true, realAvailability = true })
assert(checkedPlayer == player,
    "the resolved player reaches the crew check instead of nil")
assert(#calls == 1, "a resolved player can still issue the order")
KnoxSurvivorAutonomy = previousAutonomy
getSpecificPlayer = previousLookup

-- Blocked setups explain themselves instead of opening a chooser.
answers = {}
local previousManager = KnoxBaseManager
KnoxBaseManager = nil
assert(run({ noBase = true }) == false and #prompts == 0 and #notices == 1,
    "a player without a base is told so")
assert(string.find(notices[1], "no base", 1, true) ~= nil, "the refusal names the missing base")
KnoxBaseManager = previousManager
answers = {}
local emptyCell = { getGridSquare = function() return nil end }
assert(run({ cell = emptyCell }) == false and #prompts == 0 and #notices == 1
    and string.find(notices[1], "sight", 1, true) ~= nil,
    "no visible building is explained instead of guessing a destination")
answers = {}
local previousPlayerLookup = getSpecificPlayer
getSpecificPlayer = function() return nil end
assert(run({ noPlayer = true }) == false and #notices == 1
    and string.find(notices[1], "player", 1, true) ~= nil,
    "no player is explained")
getSpecificPlayer = previousPlayerLookup

-- The choices are the dispatch owner's real mission types and party sizes.
local missionIds = {}
for _, choice in ipairs(T.MISSION_CHOICES) do missionIds[#missionIds + 1] = choice.id end
local expected = { "scout", "food", "medicine", "tools", "weapons", "building" }
assert(#missionIds == #expected, "every supported mission type is offered once")
for index, id in ipairs(expected) do
    assert(missionIds[index] == id, "mission type " .. id .. " is offered in order")
end
assert(#T.PARTY_CHOICES == 3, "one, two or three residents")


-- A map click names the destination. The flow then asks only the order and the
-- party, and dispatches the clicked square itself instead of a scanned building.
local anchorSquare = square(7, 3, store)
answers = { { "food" }, { "2" } }
assert(run({ anchor = anchorSquare }) == true, "an anchored order still dispatches")
assert(#prompts == 2, "a clicked destination asks only the mission and the party, got "
    .. tostring(#prompts))
assert(prompts[1] == "What should they do there?",
    "the place chooser is skipped when the map already chose the place")
assert(#calls == 1, "an anchored order dispatches exactly once")
assert(calls[1].square == anchorSquare,
    "the clicked square is the destination, not a nearby scan result")
assert(calls[1].kind == "food" and calls[1].size == 2,
    "the chosen order and party reach the dispatch owner from a click")

answers = { { "cancel" } }
assert(run({ anchor = anchorSquare }) == true and #calls == 0 and #prompts == 1,
    "cancelling the order at a clicked destination issues nothing")

-- Open ground is a real destination too: no building means the square is the
-- place, and the click still needs no explanation.
local openGround = square(9, 4, nil)
answers = { { "scout" }, { "1" } }
run({ anchor = openGround })
assert(#calls == 1 and calls[1].square == openGround, "open ground is a valid destination")
assert(#notices == 0, "a clicked destination needs no explanation")

-- The clicked path never consults the surroundings scan, so an empty cell is
-- not a refusal when the player pointed at a real square.
answers = { { "scout" }, { "1" } }
run({ anchor = openGround, cell = emptyCell })
assert(#calls == 1, "a clicked destination does not depend on a visible building list")

print("Mission dispatch targets PASS scan=true dedupe=true homeSkipped=true order=true "
    .. "crewChecked=true blocked=true anchor=true")
