-- A map click names ground, not a house. The crew must be sent to search an
-- area, and that radius must reach the dispatcher so the executor sweeps the
-- buildings inside it instead of the one tile under the cursor.
local Targets = rawget(_G, "KnoxMissionTargets")
assert(Targets ~= nil, "mission targets owner missing")
assert(Targets.AREA_RADIUS ~= nil, "area radius missing")

local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end, getBuilding = function() return nil end }
end

local prompts, calls, notices, shown = {}, {}, {}, {}
local answers = {}
local function choose(prompt, entries, callback)
    prompts[#prompts + 1] = prompt
    local rowNames = {}
    for _, entry in ipairs(entries) do rowNames[#rowNames + 1] = tostring(entry.name) end
    shown[#shown + 1] = table.concat(rowNames, " | ")
    local queued = table.remove(answers, 1)
    if queued == nil then return false end
    local answer = queued[1]
    for _, entry in ipairs(entries) do
        if tostring(entry.id) == tostring(answer) then callback(entry.id, entry) return true end
    end
    return true
end

local base = { id = "base-1", home = { buildingId = "home-1" } }
local player = { getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
    getCurrentSquare = function() return square(0, 0, 0) end }

local function run(anchor, lastCrew, lastCrewAt, now)
    prompts, calls, notices, shown = {}, {}, {}, {}
    return Targets.dispatchFlow(0, {
        player = player, base = base, anchor = anchor,
        crew = { "a", "b" },
        crewName = function(id) return "N-" .. id end,
        lastCrew = lastCrew, lastCrewAt = lastCrewAt, now = now,
        excluded = { { id = "c", reason = "not_at_base" },
            { id = "d", reason = "not_loaded" } },
        choose = choose,
        notice = function(text) notices[#notices + 1] = tostring(text) end,
        availability = function() return 3, nil end,
        dispatch = function(targetBase, chosenSquare, partySize, missionType, radius, label,
            members)
            calls[#calls + 1] = { base = targetBase, square = chosenSquare, size = partySize,
                kind = missionType, radius = radius, label = label, members = members }
        end,
    })
end

answers = { { "food" }, { "pick:a" }, { "pick:b" }, { "done" }, { "send" } }
assert(run(square(120, 240, 0)) == true, "an area order still dispatches")
assert(#calls == 1, "an area order dispatches once, got " .. tostring(#calls))
assert(calls[1].radius == Targets.AREA_RADIUS,
    "the area radius reaches the dispatcher, got " .. tostring(calls[1].radius))
assert(type(calls[1].label) == "string" and calls[1].label:find("Search area", 1, true) ~= nil,
    "the order is labelled as an area, not a building, got " .. tostring(calls[1].label))
assert(prompts[2] == "Who should go?", "the crew question names people, got "
    .. tostring(prompts[2]))
assert(#prompts == 5, "a full crew gets a take-back round and a confirmation, got "
    .. tostring(#prompts))
assert(tostring(prompts[5]):find("Send N-a, N-b?", 1, true) ~= nil,
    "the confirmation names the crew, got " .. tostring(prompts[5]))
assert(tostring(prompts[4]):find("Remove one, or finish", 1, true) ~= nil,
    "the full round says what it offers, got " .. tostring(prompts[4]))
assert(tostring(prompts[3]):find("Anyone else?", 1, true) ~= nil,
    "the second round names the crew so far, got " .. tostring(prompts[3]))
assert(tostring(prompts[3]):find("N-a", 1, true) ~= nil,
    "the crew so far is named in the question, got " .. tostring(prompts[3]))
assert(calls[1].size == 2, "the chosen crew size reaches dispatch, got "
    .. tostring(calls[1].size))
assert(type(calls[1].members) == "table" and #calls[1].members == 2,
    "the named crew reaches dispatch")
assert(calls[1].members[1] == "a" and calls[1].members[2] == "b",
    "the picked order is kept")
assert(calls[1].square:getX() == 120 and calls[1].square:getY() == 240,
    "the clicked point stays the centre of the search")

-- One row per resident: after picking a, that row reads as going and no second
-- "Remove a" row appears beside it.
assert(tostring(shown[3]):find("N-a (going)", 1, true) ~= nil,
    "the picked row shows it is going, got " .. tostring(shown[3]))
assert(tostring(shown[3]):find("Remove", 1, true) == nil,
    "no duplicate remove row, got " .. tostring(shown[3]))
assert(tostring(shown[4]):find("N-b (going)", 1, true) ~= nil,
    "a full crew shows both as going, got " .. tostring(shown[4]))

-- Copy rules from UI.md: every row a player can click is a verb or a name, never
-- an internal code, and the finish row says what it does.
assert(tostring(shown[2]):find("Finish picking", 1, true) ~= nil,
    "the finish row is an action, got " .. tostring(shown[2]))
for _, rows in ipairs(shown) do
    assert(tostring(rows):find("_", 1, true) == nil,
        "no internal code reaches a row, got " .. tostring(rows))
end
answers = { { "food" }, { "pick:a" }, { "done" }, { "send" } }
run(square(120, 240, 0))
assert(calls[1].size == 1 and calls[1].members[1] == "a",
    "one name plus done sends one person")

-- A resident who cannot go is named with the reason, once, before picking.
assert(#notices == 1, "one line explains who stays behind, got " .. tostring(#notices))
local line = tostring(notices[1])
assert(line:find("N-c", 1, true) ~= nil, "the excluded resident is named, got " .. line)
assert(line:find("not at base", 1, true) ~= nil, "the reason is spoken, got " .. line)
assert(line:find("not in the world", 1, true) ~= nil, "every exclusion is listed, got " .. line)

-- Nobody excluded means no line at all.
assert(Targets.exclusionText({}) == nil, "a full roster says nothing")

-- A picked name can be taken back, and the remaining pick still goes.
answers = { { "food" }, { "pick:a" }, { "pick:b" }, { "remove:a" }, { "done" }, { "send" } }
run(square(120, 240, 0))
assert(#calls == 1, "one order after a take-back, got " .. tostring(#calls))
assert(calls[1].size == 1 and calls[1].members[1] == "b",
    "the remaining name goes alone, got " .. tostring(calls[1].members[1]))
assert(tostring(prompts[4]):find("Going: N-a, N-b", 1, true) ~= nil,
    "the take-back round names both, got " .. tostring(prompts[4]))
assert(tostring(prompts[5]):find("Going: N-b", 1, true) ~= nil,
    "the round after the take-back names one, got " .. tostring(prompts[5]))

-- Changing the crew at the confirmation keeps the picks and sends the new crew.
answers = { { "food" }, { "pick:a" }, { "done" }, { "change" },
    { "pick:b" }, { "done" }, { "send" } }
run(square(120, 240, 0))
assert(#calls == 1, "one order after changing at the confirmation, got " .. tostring(#calls))
assert(calls[1].size == 2, "the changed crew sends two, got " .. tostring(calls[1].size))
assert(calls[1].members[1] == "a" and calls[1].members[2] == "b",
    "the picks survived the change")

-- Emptying the crew issues nothing and says so rather than going silent.
answers = { { "food" }, { "pick:a" }, { "remove:a" }, { "done" } }
run(square(120, 240, 0))
assert(#calls == 0, "an emptied crew dispatches nobody, got " .. tostring(#calls))
local said = false
for _, text in ipairs(notices) do
    if tostring(text):find("Nobody is going", 1, true) ~= nil then said = true end
end
assert(said, "an emptied crew is explained")

-- A large base is trimmed: three names, then a count. The fourth name is never
-- spelled out, so the line cannot grow without bound.
local many = {}
for index = 1, 5 do
    many[index] = { id = "x" .. index, reason = "not_at_base" }
end
local trimmed = Targets.exclusionText(many, function(id) return "Name-" .. id end)
assert(trimmed:find("Name-x3", 1, true) ~= nil, "the first three are named, got " .. tostring(trimmed))
assert(trimmed:find("Name-x4", 1, true) == nil, "the fourth is only counted, got " .. tostring(trimmed))
assert(trimmed:find("and 2 more", 1, true) ~= nil, "the remainder is counted, got " .. tostring(trimmed))
local exactlyThree = {}
for index = 1, 3 do
    exactlyThree[index] = { id = "y" .. index, reason = "busy" }
end
local threeLine = Targets.exclusionText(exactlyThree, function(id) return id end)
assert(threeLine:find("more", 1, true) == nil,
    "exactly three names need no count, got " .. tostring(threeLine))
-- A repeat order offers the crew that last went: one row, then the confirm.
answers = { { "food" }, { "same" }, { "send" } }
run(square(120, 240, 0), { "a", "b" })
assert(#prompts == 3, "the shortcut replaces the picking rounds, got "
    .. tostring(#prompts))
assert(tostring(shown[2]):find("Same as last time: N-a, N-b (2)", 1, true) ~= nil,
    "the shortcut reads as an action and counts the crew, got " .. tostring(shown[2]))
assert(#calls == 1 and calls[1].size == 2,
    "the remembered crew is dispatched, got " .. tostring(#calls))
assert(calls[1].members[1] == "a" and calls[1].members[2] == "b",
    "the remembered order is kept")

-- A remembered name that can no longer go is never offered back.
answers = { { "food" }, { "pick:b" }, { "done" }, { "send" } }
run(square(120, 240, 0), { "gone", "b" })
assert(tostring(shown[2]):find("Same as last time: N-b (1 of 2)", 1, true) ~= nil,
    "the row says one of two can still go, got " .. tostring(shown[2]))
assert(tostring(shown[2]):find("N-gone", 1, true) == nil,
    "a stale name is never offered, got " .. tostring(shown[2]))
assert(calls[1].size == 1 and calls[1].members[1] == "b",
    "the stale name is not dispatched either")

-- The row says how old the crew is, in the shortest honest form.
assert(Targets.lastCrewAgeText(100, 100.5) == "just now",
    "a crew sent moments ago reads as just now, got "
    .. tostring(Targets.lastCrewAgeText(100, 100.5)))
assert(Targets.lastCrewAgeText(100, 105) == "5h ago",
    "hours are counted, got " .. tostring(Targets.lastCrewAgeText(100, 105)))
assert(Targets.lastCrewAgeText(100, 172) == "3d ago",
    "days replace hours, got " .. tostring(Targets.lastCrewAgeText(100, 172)))
assert(Targets.lastCrewAgeText(nil, 172) == nil,
    "an unrecorded age says nothing")
answers = { { "food" }, { "same" }, { "send" } }
run(square(120, 240, 0), { "a", "b" }, 100, 100 + 50)
assert(tostring(shown[2]):find("Same as last time: N-a, N-b (2), 2d ago", 1, true) ~= nil,
    "the row carries the age, got " .. tostring(shown[2]))

-- A remembered crew expires, so a save left for a season does not resurrect it.
answers = { { "food" }, { "pick:a" }, { "done" }, { "send" } }
run(square(120, 240, 0), { "a", "b" }, 100, 100 + Targets.LAST_CREW_HOURS + 1)
assert(tostring(shown[2]):find("Same as last time", 1, true) == nil,
    "an old crew is not offered, got " .. tostring(shown[2]))
assert(#calls == 1 and calls[1].size == 1, "the order still works without the shortcut")

-- Inside the window the shortcut is still there.
answers = { { "food" }, { "same" }, { "send" } }
run(square(120, 240, 0), { "a", "b" }, 100, 100 + Targets.LAST_CREW_HOURS - 1)
assert(tostring(shown[2]):find("Same as last time: N-a, N-b (2)", 1, true) ~= nil,
    "a recent crew is still offered, got " .. tostring(shown[2]))

print("Mission area dispatch PASS radius=true label=true chooser=true centre=true lastcrew=true expiry=true")
