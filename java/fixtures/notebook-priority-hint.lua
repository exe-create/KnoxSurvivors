local hint = assert(codecPriorityHint, "the priority hint is loaded")

local function says(value, phrase, label)
    local text = hint(label or "Guard", value)
    assert(string.find(text, phrase, 1, true) ~= nil,
        tostring(value) .. " should read: " .. phrase .. " (got: " .. tostring(text) .. ")")
    return text
end

-- Every real state in the cycle must explain itself, not fall through.
says("high", "picked for this before other work")
says("normal", "takes this like any other job")
says("low", "nothing better is left")
says("disabled", "does not take this at all")

local named = says("high", "Guard", "Guard")
assert(string.find(named, "Guard: H", 1, true) ~= nil, "the cell label and its token are both named")

-- An unknown state names itself instead of borrowing another state's meaning.
local odd = hint("Guard", "sometime")
assert(string.find(odd, "sometime", 1, true) ~= nil, "unknown state is named as it is")
assert(string.find(odd, "no stated preference", 1, true) ~= nil, "unknown state has no invented meaning")

print("Notebook priority PASS four_states=true unknown_named=true")
