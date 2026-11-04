-- The leader's own voice about the base's first real problem: one line from
-- the same attention projection the notebook and the in-world line read.
local B = codecBaseAdvice

assert(type(B.baseAdvice) == "function", "baseAdvice must exist")

local keys = { "raid", "blocked", "unshelved", "security", "security_unstaffed",
    "zones", "storage", "beds" }
local seen = {}
for _, key in ipairs(keys) do
    local line = B.baseAdvice({ key = key })
    assert(type(line) == "string" and #line > 0, key .. " needs its own sentence")
    assert(string.sub(line, -1) == ".", key .. " should read as a spoken sentence")
    assert(seen[line] == nil, key .. " must not reuse another problem's sentence")
    seen[line] = true
end

-- Raid advice is about the threat, not about housekeeping.
assert(string.find(B.baseAdvice({ key = "raid" }), "gate", 1, true) ~= nil,
    "the raid line tells the player where to be")

-- Unknown or absent problems get no invented advice.
assert(B.baseAdvice({ key = "kits" }) == nil, "an unknown problem has no line")
assert(B.baseAdvice({ key = "RAID" }) == nil, "keys are exact, not case-folded")
assert(B.baseAdvice({}) == nil, "an item without a key has no line")
assert(B.baseAdvice(nil) == nil)
assert(B.baseAdvice({ key = 7 }) == nil, "a non-string key has no line")

print("Base advice PASS keys=" .. tostring(#keys) .. " unknown=false exact=true")
