local M = assert(codecBarricadeRefusal, "the barricade refusal copy is loaded")
local text = assert(M.barricadeRefusalText, "the refusal copy is callable")

-- Every refusal sentence the base barricade order can show. The finder answers
-- with a code; a code without its own sentence silently became "Nothing here
-- needs barricading", which is false whenever the world could not be read.
local expected = {
    { "only_usable_exit", "That would seal the only way out." },
    { "no_way_out", "That room has no usable exit of its own." },
    { "keep_open", "Every usable opening there is marked to stay clear." },
    { "barricade_room_busy", "Barricade work is already queued for that room." },
    { "entrance_unverified", "I can't verify a safe exit there." },
    { "room_audit_too_large", "That room has too many openings to audit safely." },
    { "missing_building", "I can't tell which building this is." },
    { "building_unavailable", "I can't read this building." },
    { "base_or_cell_unavailable", "I can't read this base's surroundings." },
    { "target_unloaded", "That window is not loaded any more." },
    { "target_no_longer_valid", "That window no longer needs boarding." },
}
for _, pair in ipairs(expected) do
    assert(text(pair[1]) == pair[2],
        "reason " .. pair[1] .. " reads as its own sentence, got " .. tostring(text(pair[1])))
end

-- The one code whose sentence is genuinely "nothing to do here".
assert(text("no_unbarricaded_window") == "Nothing here needs barricading.",
    "a building with nothing to board says so: " .. tostring(text("no_unbarricaded_window")))

-- An unknown code must not invent a promise that work exists.
assert(text("something_new") == "Nothing here needs barricading.",
    "an unknown reason falls back without claiming work is available")
assert(text(nil) == "Nothing here needs barricading.",
    "a nil reason falls back")
assert(text("") == "Nothing here needs barricading.",
    "an empty reason falls back")

-- No sentence may be a bare code, and no two distinct reasons share a sentence
-- by accident: a shared sentence would hide which condition actually blocked.
local seen = {}
for _, pair in ipairs(expected) do
    assert(not seen[pair[2]], "two reasons share the sentence: " .. pair[2])
    seen[pair[2]] = pair[1]
    assert(string.find(pair[2], "_", 1, true) == nil,
        "a sentence leaked a raw reason code: " .. pair[2])
    assert(string.sub(pair[2], -1) == ".",
        "a sentence ends in a full stop: " .. pair[2])
end

print("Barricade refusal copy PASS reasons=" .. tostring(#expected) .. " fallback=true")
