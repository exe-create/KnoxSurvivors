-- A witness is not a tally. Five voices say the same rebuke differently, and the
-- person it happened to is named, so the line is about Nora rather than about a
-- rule the mod applied. This drives the real banks and the real selection.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")
local function withRecord(record)
    if record == nil then
        KnoxPersistence = nil
        return
    end
    KnoxPersistence = { getSurvivorPersonality = function() return record end }
end

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "witnessed_mean")
assert(type(shared) == "table" and #shared >= 3, "the shared witness bank exists")

-- 1. Every voice has its own words, and they are not the shared ones: a quiet
--    person and a bold one do not give the same rebuke.
local archetypeScores = {
    frightened = { courage = 20, sociability = 34, aggression = 14 },
    guarded = { courage = 42, sociability = 30, aggression = 24 },
    brave = { courage = 82, sociability = 58, aggression = 42 },
    loner = { courage = 62, sociability = 18, aggression = 30 },
    sociable = { courage = 56, sociability = 84, aggression = 22 },
}
local spoken = {}
for archetype, scores in pairs(archetypeScores) do
    withRecord({ personality = archetype, courage = scores.courage,
        sociability = scores.sociability, aggression = scores.aggression })
    local lines, voice = D.linesFor("s1", "witnessed_mean")
    assert(voice == archetype, "the voice keeps its own words: " .. archetype)
    assert(type(lines) == "table" and #lines >= 2, "the voice has something to say: " .. archetype)
    assert(lines ~= shared, "a voice does not reuse the shared bank: " .. archetype)
    spoken[archetype] = tostring(lines[1])
end
assert(spoken.frightened ~= spoken.brave, "fear and nerve do not sound alike")

-- 2. The line is a person speaking, in the first person, within a breath, and
--    it never explains the system behind it.
for archetype, lines in pairs({ brave = D.linesFor("s1", "witnessed_mean") }) do
    assert(#lines >= 2, "brave keeps two lines")
end
for archetype, scores in pairs(archetypeScores) do
    withRecord({ personality = archetype, courage = scores.courage,
        sociability = scores.sociability, aggression = scores.aggression })
    for _, line in ipairs(D.linesFor("s1", "witnessed_mean")) do
        assert(wordCount(line) <= 18, "witness line inside its budget: " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil,
            "a witness speaks for themselves: " .. line)
        assert(lower:find("trust", 1, true) == nil and lower:find("mod ", 1, true) == nil
            and lower:find("reputation", 1, true) == nil,
            "a witness never names the machinery: " .. line)
    end
end

-- 3. The name is a placeholder the speaker fills, so the same bank can be about
--    anyone. Every personality line that mentions a person uses it.
local named = 0
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    withRecord({ personality = key })
    for _, line in ipairs(D.linesFor("s1", "witnessed_mean")) do
        if line:find("{name}", 1, true) ~= nil then named = named + 1 end
    end
end
assert(named >= 5, "the voices name the person they are defending, got " .. tostring(named))

-- 4. An unknown voice still speaks, because silence would read as indifference.
withRecord({ personality = "unstable", courage = 48, sociability = 42, aggression = 58 })
local fallback, voice = D.linesFor("s1", "witnessed_mean")
assert(fallback == shared and voice == "unstable", "a middle voice uses the shared bank")

KnoxPersistence = nil
local noIdentity = D.linesFor("s1", "witnessed_mean")
assert(noIdentity == shared, "no identity means the shared bank")

KnoxPersistence = realPersistence
print("Witness voice PASS five_voices=true named=true budget=true fallback=true")
