-- The one text-fitting rule, proven with an injected measure so the arithmetic
-- is checked without a font atlas. Every Knox surface that draws a single line
-- into a measured slot goes through Layout.fitText; the copies it replaced are
-- gone, so this fixture is the only place the rule can be wrong.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.fitText) == "function", "the layout owns text fitting, not a caller")

-- One unit of width per character: exact bounds, no font metrics.
local function measure(value) return #value end

-- A text that fits is handed back untouched: no suffix, no rebuild.
assert(L.fitText(nil, "Short", 40, measure) == "Short", "a fitting text is unchanged")
assert(L.fitText(nil, "", 40, measure) == "", "an empty text stays empty")
assert(L.fitText(nil, nil, 40, measure) == "", "nil reads as an empty text")
assert(L.fitText(nil, 12, 40, measure) == "12", "a non-string reads as its tostring")

-- A text that does not fit loses characters from the end until it does, and the
-- suffix tells the player it was cut.
local long = "Tools [Normal] (toolbox) in Workshop"
assert(#long == 36, "fixture text is the expected length, got " .. #long)
local fitted = L.fitText(nil, long, 16, measure)
assert(#fitted <= 16,
    "a fitted text must stay inside its width, got " .. #fitted .. " for '" .. fitted .. "'")
assert(string.sub(fitted, -3) == "...",
    "a cut text must show it was cut, got '" .. fitted .. "'")
assert(string.sub(fitted, 1, 5) == "Tools",
    "a cut text keeps the head of the row, got '" .. fitted .. "'")
assert(string.sub(fitted, 1, 5) ~= string.sub(long, 1, 5) or #fitted < #long,
    "a cut text is shorter than the original")

-- A slot too narrow even for the suffix returns the suffix alone rather than
-- drawing characters past the edge.
assert(L.fitText(nil, "Workshop", 2, measure) == "...",
    "a slot narrower than the suffix shows only the suffix")

-- No width means no fitting rule: the caller asked for the whole text.
assert(L.fitText(nil, "Workshop", 0, measure) == "Workshop", "no width keeps the text")
assert(L.fitText(nil, "Workshop", nil, measure) == "Workshop", "no width keeps the text")

-- The fitted result is always a prefix of the original followed by the suffix,
-- which is what makes it safe to fit a row that carries meaning at its end.
local tail = L.fitText(nil, long, 24, measure)
assert(string.sub(long, 1, #tail - 3) == string.sub(tail, 1, #tail - 3),
    "the fitted text is a prefix of the original, got '" .. tail .. "'")
