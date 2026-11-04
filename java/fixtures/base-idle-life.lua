local C = assert(KnoxAutonomyController, "the autonomy controller is loaded")
assert(type(C.baseIdleChoice) == "function", "the base idle selector is loaded")
assert(type(C.runBaseIdleChoice) == "function", "the base idle executor is loaded")

local allowed = {
    move = true, rest = true, snack = true, tidy = true, socialize = true, tv = true,
}
for round = 0, 80 do
    for _, id in ipairs({ "resident-a", "resident-b", "resident-c" }) do
        local choice = C.baseIdleChoice(round * 450, id, 3)
        assert(allowed[choice], "a base idle choice must be executable: " .. tostring(choice))
    end
end
assert(C.baseIdleChoice(0, "resident-a", 1, "recreation") ~= "wait",
    "a recreation window never falls back to a bare wait")

local function mock(flags)
    local calls = {}
    local c = setmetatable({ calls = calls }, C)
    local function method(name)
        return function()
            calls[#calls + 1] = name
            return flags[name] == true
        end
    end
    c.beginBaseMovement = method("move")
    c.beginAmbientSnack = method("snack")
    c.beginAmbientSocial = method("socialize")
    c.beginAmbientWatch = method("tv")
    c.beginBaseOrganize = method("tidy")
    c.beginAmbientBaseRest = method("rest")
    flags.rest = flags.rest ~= false
    return c
end

local function succeeds(choice)
    local flags = { rest = false }
    flags[choice] = true
    local c = mock(flags)
    assert(C.runBaseIdleChoice(c, 100, choice) == true,
        choice .. " starts through its existing owner")
    assert(#c.calls == 1 and c.calls[1] == choice,
        choice .. " does not start a second activity on success")
end
succeeds("move")
succeeds("snack")
succeeds("socialize")
succeeds("tv")
succeeds("tidy")

local function fallsBack(choice)
    local c = mock({})
    assert(C.runBaseIdleChoice(c, 100, choice) == true,
        choice .. " failure still owns a visible activity")
    assert(c.calls[1] == choice and c.calls[2] == "rest" and #c.calls == 2,
        choice .. " failure falls through to the existing rest/recreation owner")
end
fallsBack("move")
fallsBack("snack")
fallsBack("socialize")
fallsBack("tv")
fallsBack("tidy")

local rest = mock({})
assert(C.runBaseIdleChoice(rest, 100, "rest") == true)
assert(#rest.calls == 1 and rest.calls[1] == "rest", "rest is already the real owner")
local unknown = mock({})
assert(C.runBaseIdleChoice(unknown, 100, "wait") == true)
assert(#unknown.calls == 1 and unknown.calls[1] == "rest",
    "a legacy or unknown choice becomes real downtime, never flat standing")

print("Base idle life PASS choices=true fallback=true rest=true")
