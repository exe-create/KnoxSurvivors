-- A bitten person says it in their own voice. This drives the real selection
-- rule over the new bank and holds the rules every spoken line obeys: short,
-- first person, and never explaining the system.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "cant_lift_bitten")
assert(type(shared) == "table" and #shared >= 3, "the shared bite bank exists")

local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
    local lines, voice = D.linesFor("s1", "cant_lift_bitten")
    assert(voice == key, "the voice answers: " .. key)
    assert(lines ~= shared, "a voice does not reuse the shared words: " .. key)
    local signature = table.concat(lines, "|")
    assert(signatures[signature] == nil, "two voices do not share a refusal")
    signatures[signature] = key
    for _, line in ipairs(lines) do
        assert(wordCount(line) <= 18, "inside the budget (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil or lower:find("my", 1, true) ~= nil,
            "spoken in the first person (" .. key .. "): " .. line)
        assert(lower:find("task", 1, true) == nil and lower:find("mod", 1, true) == nil,
            "never explains the system: " .. line)
    end
end
for _, line in ipairs(shared) do
    assert(wordCount(line) <= 18, "shared line inside the budget: " .. line)
end

-- The bite is a different moment from a bad back, so the two banks cannot share
-- their copy: a player must not read a wound where there is an infection.
local painBank = D.linesFor("s1", "cant_lift")
assert(table.concat(shared, "|") ~= table.concat(painBank or {}, "|"),
    "a bite is not a bad shoulder")

-- The scores still choose the mouth, away from the label too.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "brave", courage = 20, sociability = 58, aggression = 42 }
end }
assert(select(2, D.linesFor("s1", "cant_lift_bitten")) == "frightened",
    "fear selects the bite voice")

-- An unknown label falls back to the shared words rather than going silent.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "unknown_type" }
end }
local fallback, voice = D.linesFor("s1", "cant_lift_bitten")
assert(fallback == shared and voice == "unknown_type", "an unknown label falls back")

KnoxPersistence = realPersistence
print("Bite voice PASS five_voices=true budget=true scores=true fallback=true")
