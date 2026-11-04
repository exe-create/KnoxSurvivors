-- A refusal is one measured cause in five different mouths. The archetype alone
-- made two brave survivors sound identical; the identity already carries
-- sociability, courage and aggression, so the voice is now read from those.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")

local realPersistence = rawget(_G, "KnoxPersistence")
local function withRecord(record)
    if record == nil then
        KnoxPersistence = nil
        return
    end
    KnoxPersistence = { getSurvivorPersonality = function() return record end }
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "cant_lift")
assert(type(shared) == "table" and #shared >= 3, "the shared refusal bank exists")
assert(D.voiceFor(nil) == nil, "no identity is no voice")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

-- Each archetype's own scores keep its own bank, so nothing regressed.
local archetypeScores = {
    frightened = { courage = 20, sociability = 34, aggression = 14 },
    guarded = { courage = 42, sociability = 30, aggression = 24 },
    brave = { courage = 82, sociability = 58, aggression = 42 },
    loner = { courage = 62, sociability = 18, aggression = 30 },
    sociable = { courage = 56, sociability = 84, aggression = 22 },
}
for archetype, scores in pairs(archetypeScores) do
    withRecord({ personality = archetype, courage = scores.courage,
        sociability = scores.sociability, aggression = scores.aggression })
    local lines, voice = D.linesFor("s1", "cant_lift")
    assert(voice == archetype, "an archetype's own scores keep its voice: " .. archetype)
    assert(type(lines) == "table" and #lines >= 2, "the voice has lines: " .. archetype)
end

-- The scores outrank the label: the same archetype can speak in two voices.
withRecord({ personality = "guarded", courage = 60, sociability = 90, aggression = 20 })
local lines, voice = D.linesFor("s1", "cant_lift")
assert(voice == "sociable", "an open survivor speaks warmly whatever their label")
local sociableLines = lines

withRecord({ personality = "guarded", courage = 60, sociability = 30, aggression = 24 })
lines, voice = D.linesFor("s1", "cant_lift")
assert(voice == "guarded", "the same label with a closed manner stays guarded")
assert(lines ~= sociableLines, "two survivors of one label can sound different")

-- Fear is loudest: a brave label with low courage still sounds frightened.
withRecord({ personality = "brave", courage = 20, sociability = 58, aggression = 42 })
lines, voice = D.linesFor("s1", "cant_lift")
assert(voice == "frightened", "fear outranks the label")

-- Closed and hard is blunt; closed and soft is the loner.
withRecord({ personality = "brave", courage = 50, sociability = 10, aggression = 80 })
assert(select(2, D.linesFor("s1", "cant_lift")) == "guarded", "a hard closed voice is blunt")
withRecord({ personality = "brave", courage = 50, sociability = 10, aggression = 20 })
assert(select(2, D.linesFor("s1", "cant_lift")) == "loner", "a soft closed voice keeps to itself")

-- Middle scores and banks we do not have fall back rather than invent a mouth.
withRecord({ personality = "unstable", courage = 48, sociability = 42, aggression = 58 })
lines, voice = D.linesFor("s1", "cant_lift")
assert(lines == shared and voice == "unstable", "a middle voice falls back to the shared bank")
withRecord({ personality = "unknown_type" })
lines, voice = D.linesFor("s1", "cant_lift")
assert(lines == shared and voice == "unknown_type", "an unknown label falls back")
withRecord({ personality = "brave" })
lines, voice = D.linesFor("s1", "cant_lift")
assert(voice == "brave", "a record with no scores still uses its label")

-- Every voice keeps the refusal budget and the human rules.
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    withRecord({ personality = key })
    local bank = D.linesFor("s1", "cant_lift")
    for _, line in ipairs(bank) do
        assert(wordCount(line) <= 18, "refusal inside its budget (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil or lower:find("my", 1, true) ~= nil,
            "a refusal is spoken in the first person: " .. line)
        assert(lower:find("task", 1, true) == nil and lower:find("mod", 1, true) == nil,
            "a refusal never explains the system: " .. line)
    end
end

KnoxPersistence = nil
local fallback, key = D.linesFor("s1", "cant_lift")
assert(fallback == shared and key == nil, "no identity means the shared bank")
assert(D.linesFor("s1", "no_such_event") == nil, "an unknown event has no lines")

KnoxPersistence = realPersistence
print("Refusal personality PASS five_voices=true scores=true fear=true budget=true fallback=true")
