-- Score-led voicing must not lose a line just because the chosen voice has no words
-- for that moment. The chain is: the voice, then the archetype it was read from,
-- then the shared bank.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function withRecord(record)
    KnoxPersistence = { getSurvivorPersonality = function() return record end }
end

local function count(line)
    local n = 0
    for _ in tostring(line):gmatch("%S+") do n = n + 1 end
    return n
end

KnoxPersistence = nil
local sharedCombat = D.linesFor("s1", "combat")
assert(type(sharedCombat) == "table", "the shared combat bank exists")

-- A voice that has the event speaks it, and reports itself.
withRecord({ personality = "guarded", courage = 60, sociability = 90, aggression = 20 })
local lines, voice = D.linesFor("s1", "camp")
assert(voice == "sociable", "the score voice speaks camp")
assert(lines ~= nil and count(lines[1]) <= 10, "camp lines stay short")

-- The same person on an event their voice does not carry falls back to the
-- archetype's own words for it, not to a generic line.
local fallback, who = D.linesFor("s1", "need_medical")
assert(who == "guarded", "the archetype bank answers when the voice has no words")
assert(fallback ~= nil, "a medical line is still spoken")

-- Fear outranks the label here too, and still finds words for a moment the
-- frightened bank carries.
withRecord({ personality = "brave", courage = 20, sociability = 50, aggression = 40 })
local scared, scaredVoice = D.linesFor("s1", "need_medical")
assert(scaredVoice == "frightened", "fear still selects the voice")
assert(scared ~= nil, "the frightened medical line exists")

-- An event no personalised bank covers keeps the shared bank and reports the
-- archetype, so a caller can explain who was speaking.
withRecord({ personality = "sociable", courage = 56, sociability = 84, aggression = 22 })
local generic, key = D.linesFor("s1", "no_such_event")
assert(generic == nil and key == "sociable", "an unknown event has no lines")

-- A record with no scores uses its label directly, exactly as before.
withRecord({ personality = "gunner" })
local gunner, gunnerVoice = D.linesFor("s1", "player_talk")
assert(gunnerVoice == "gunner" and type(gunner) == "table",
    "a scoreless record still speaks its archetype")

-- Every line reachable this way stays inside a human budget, and the events each
-- voice is expected to have must actually be there: a sweep that silently skips a
-- missing bank would pass while proving nothing.
local events = { "player_talk", "combat", "camp", "need_medical", "cant_lift" }
local required = { player_talk = true, combat = true, camp = true }
local checked = 0
for _, archetype in ipairs({ "frightened", "guarded", "brave", "loner", "sociable" }) do
    withRecord({ personality = archetype })
    for _, event in ipairs(events) do
        local bank = D.linesFor("s1", event)
        if required[event] then
            assert(bank ~= nil, "every voice has " .. event .. " for " .. archetype)
        end
        if bank ~= nil then
            checked = checked + 1
            for _, line in ipairs(bank) do
                assert(count(line) <= 18, "line over budget: " .. tostring(line))
            end
        end
    end
end
assert(checked >= 15, "the sweep checked real banks, got " .. tostring(checked))

KnoxPersistence = realPersistence
print("Voice coverage PASS voice=true archetype=true shared=true budget=true")
