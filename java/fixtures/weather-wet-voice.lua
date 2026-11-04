-- Wet clothing outlasts the rain that caused it, and a soaked person says so.
-- This drives the real selection rule over the new bank and holds the spoken
-- rules every weather line obeys: short, first person, no system vocabulary.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function wordCount(line)
    local count = 0
    for _ = 1, select(2, tostring(line):gsub("%S+", "")) do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "weather_wet")
assert(type(shared) == "table" and #shared >= 3, "the shared wet bank exists")

-- Wet is not rain and not cold: the three reasons cannot share copy.
local rain = D.linesFor("s1", "weather_rain")
local cold = D.linesFor("s1", "weather_cold")
assert(table.concat(shared, "|") ~= table.concat(rain, "|"),
    "being soaked is not the same remark as falling rain")
assert(table.concat(shared, "|") ~= table.concat(cold, "|"),
    "being soaked is not the same remark as being cold")

-- Every voice has its own words for it, and none of them explains the system.
local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
    local lines, voice = D.linesFor("s1", "weather_wet")
    assert(voice == key, "the voice answers: " .. key)
    assert(type(lines) == "table" and #lines >= 2, "the voice has wet lines: " .. key)
    assert(lines ~= shared, "a voice does not reuse the shared words: " .. key)
    local signature = table.concat(lines, "|")
    assert(signatures[signature] == nil, "two voices do not share a wet remark")
    signatures[signature] = key
    for _, line in ipairs(lines) do
        assert(wordCount(line) <= 12, "a wet line stays short (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("mod", 1, true) == nil and lower:find("task", 1, true) == nil,
            "no system talk: " .. line)
    end
end

-- The scores still choose the mouth, away from the label too.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "brave", courage = 20, sociability = 58, aggression = 42 }
end }
assert(select(2, D.linesFor("s1", "weather_wet")) == "frightened",
    "fear selects the wet voice")

-- An unknown label falls back to the shared words rather than going silent.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "unknown_type" }
end }
local fallback, voice = D.linesFor("s1", "weather_wet")
assert(fallback == shared and voice == "unknown_type", "an unknown label falls back")

KnoxPersistence = realPersistence
print("Wet voice PASS five_voices=true budget=true scores=true fallback=true")
