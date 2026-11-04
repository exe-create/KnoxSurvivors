-- A broken weapon is said in the speaker's own voice. This drives the real
-- selection rule over the new bank and holds the rules every spoken line obeys:
-- short, first person, and never explaining the system.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "weapon_broken")
assert(type(shared) == "table" and #shared >= 3, "the shared weapon bank exists")
assert(shared[1] == "My weapon's done. I need another.",
    "the shared weapon bank has its own words")

local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
    local lines, voice = D.linesFor("s1", "weapon_broken")
    assert(voice == key, "the voice answers: " .. key)
    assert(lines ~= shared, "a voice does not reuse the shared words: " .. key)
    local signature = table.concat(lines, "|")
    assert(signatures[signature] == nil, "two voices do not share a break")
    signatures[signature] = key
    for _, line in ipairs(lines) do
        assert(wordCount(line) <= 18, "inside the budget (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil or lower:find("my", 1, true) ~= nil,
            "spoken in the first person (" .. key .. "): " .. line)
        assert(lower:find("durab", 1, true) == nil and lower:find("condition", 1, true) == nil
            and lower:find("mod", 1, true) == nil,
            "never explains the system: " .. line)
    end
end

-- The break is not a refusal and not an illness; the banks cannot share copy.
local painBank = D.linesFor("s1", "cant_lift")
local biteBank = D.linesFor("s1", "cant_lift_bitten")
assert(table.concat(shared, "|") ~= table.concat(painBank or {}, "|"),
    "a broken weapon is not a bad shoulder")
assert(table.concat(shared, "|") ~= table.concat(biteBank or {}, "|"),
    "a broken weapon is not a bite")

-- An unknown label falls back to the shared words rather than going silent.
KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "unknown_type" }
end }
local fallback, voice = D.linesFor("s1", "weapon_broken")
assert(fallback == shared and voice == "unknown_type", "an unknown label falls back")

KnoxPersistence = realPersistence
print("WeaponBroken voice PASS five_voices=true budget=true separate=true fallback=true")
