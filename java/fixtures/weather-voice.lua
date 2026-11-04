-- Weather that turns a person around is worth one remark. This drives the
-- announcement rule and the two authored banks it selects.
local N = assert(rawget(_G, "codecWeatherNeeds"), "the needs rule is loaded")
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")

-- Only a change from one reason to another speaks; the same weather is silent.
assert(N.shelterAnnouncement(nil, nil) == nil, "clear weather says nothing")
assert(N.shelterAnnouncement(nil, "rain") == "rain", "the first rain is announced")
assert(N.shelterAnnouncement("rain", "rain") == nil, "the same rain is not repeated")
assert(N.shelterAnnouncement("rain", "cold") == "cold", "a change of reason is announced")
assert(N.shelterAnnouncement("cold", nil) == nil, "clearing says nothing")
assert(N.shelterAnnouncement("rain", nil) == nil, "going quiet says nothing")
assert(N.shelterAnnouncement(nil, "cold") == "cold", "the first cold is announced")

-- The banks exist, are short, and stay concrete.
local realPersistence = rawget(_G, "KnoxPersistence")
KnoxPersistence = nil
for _, event in ipairs({ "weather_rain", "weather_cold" }) do
    local lines = D.linesFor("s1", event)
    assert(type(lines) == "table" and #lines >= 2, "the bank exists: " .. event)
    for _, line in ipairs(lines) do
        local words = 0
        for _ in tostring(line):gmatch("%S+") do words = words + 1 end
        assert(words <= 12, "a weather line stays short: " .. line)
        assert(line:find("mod", 1, true) == nil, "no system talk: " .. line)
        assert(line:find("task", 1, true) == nil, "no system talk: " .. line)
    end
end

-- The two banks must not be interchangeable: rain and cold are different things.
local rain = D.linesFor("s1", "weather_rain")
local cold = D.linesFor("s1", "weather_cold")
assert(table.concat(rain, "|") ~= table.concat(cold, "|"),
    "rain and cold do not share lines")

-- Each voice has its own weather remark, so the same rain sounds like the
-- person noticing it rather than like a narrator reading a forecast.
local sharedRain = D.linesFor("s1", "weather_rain")
local sharedCold = D.linesFor("s1", "weather_cold")
local function withVoice(key)
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
end
local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    withVoice(key)
    local rain, rainVoice = D.linesFor("s1", "weather_rain")
    local cold, coldVoice = D.linesFor("s1", "weather_cold")
    assert(rainVoice == key and coldVoice == key, "the voice answers: " .. key)
    assert(rain ~= sharedRain and cold ~= sharedCold, "a voice has its own words: " .. key)
    assert(table.concat(rain, "|") ~= table.concat(cold, "|"),
        "rain and cold differ inside a voice: " .. key)
    local signature = table.concat(rain, "|")
    assert(signatures[signature] == nil, "two voices do not share a remark")
    signatures[signature] = key
    for _, bank in ipairs({ rain, cold }) do
        for _, line in ipairs(bank) do
            local words = 0
            for _ in tostring(line):gmatch("%S+") do words = words + 1 end
            assert(words <= 12, "a voiced weather line stays short: " .. line)
        end
    end
end

-- A voice with no weather bank of its own still speaks, in the shared words.
withVoice("gunner")
assert(D.linesFor("s1", "weather_rain") == sharedRain, "a voice without weather falls back")

-- The weather banks are score-led like every other bank: a brave label with low
-- courage speaks in the frightened voice, because that is what the scores say.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "brave", courage = 20, sociability = 58, aggression = 42 }
end }
local scaredRain, scaredVoice = D.linesFor("s1", "weather_rain")
assert(scaredVoice == "frightened", "the scores select the weather voice")

KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "guarded", courage = 60, sociability = 90, aggression = 20 }
end }
local warmRain, warmVoice = D.linesFor("s1", "weather_rain")
assert(warmVoice == "sociable", "an open manner selects the weather voice")
assert(scaredRain ~= warmRain, "two manners do not say the same thing about rain")

KnoxPersistence = realPersistence
print("Weather voice PASS once=true rain=true cold=true budget=true voices=true")
