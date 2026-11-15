-- A label never wraps, so every paragraph a Knox window draws is measured into
-- lines first. This fixture holds the rule with a one-unit-per-character measure,
-- and counts the measurements so the fast path is a fact rather than a hope.
local Layout = assert(rawget(_G, "codecTextWrap"), "text wrap owner missing")
assert(type(Layout.wrapLines) == "function", "wrapLines missing")

local function measure(value) return #value end

local lines = Layout.wrapLines("aaa bbb ccc", 7, measure)
assert(#lines == 2, "seven columns hold two words, got " .. tostring(#lines))
assert(lines[1] == "aaa bbb", "the first line fills the width, got " .. tostring(lines[1]))
assert(lines[2] == "ccc", "the remainder starts the second line, got " .. tostring(lines[2]))

-- No line may be wider than the sheet it is drawn on.
local wide = Layout.wrapLines(
    "one two three four five six seven eight nine ten eleven twelve", 12, measure)
assert(#wide > 1, "a long sentence wraps, got " .. tostring(#wide))
for index, line in ipairs(wide) do
    assert(#line <= 12, "line " .. tostring(index) .. " is wider than the sheet: " .. tostring(line))
end
assert(table.concat(wide, " ") == "one two three four five six seven eight nine ten eleven twelve",
    "wrapping loses no word and invents none")

-- An explicit newline is a deliberate break and is never merged.
local broken = Layout.wrapLines("aa\nbb", 80, measure)
assert(#broken == 2 and broken[1] == "aa" and broken[2] == "bb",
    "an explicit break stays a break")

-- A word longer than the line is split without discarding its ending.
local longWord = Layout.wrapLines("abcdefgh", 3, measure)
assert(#longWord == 3 and table.concat(longWord, "") == "abcdefgh",
    "an oversized word wraps without losing any characters")
for _, line in ipairs(longWord) do assert(measure(line) <= 3, "long word stays inside its sheet") end

-- Runs of spaces do not leave empty lines behind.
local spaced = Layout.wrapLines("aa   bb", 40, measure)
assert(#spaced == 1 and spaced[1] == "aa bb", "extra spaces collapse, got " .. tostring(#spaced))

assert(#Layout.wrapLines("", 10, measure) == 0, "no text is no lines")
assert(#Layout.wrapLines(nil, 10, measure) == 0, "a missing message is no lines")
assert(#Layout.wrapLines("aa bb", nil, measure) == 1, "no limit is one line")
assert(#Layout.wrapLines("aa bb", 4) == 2, "a missing measure still wraps by width")

-- The fast path: text that already fits costs one measurement and one line.
local calls = 0
local function counted(value) calls = calls + 1 return #value end
local fits = Layout.wrapLines("short line", 100, counted)
assert(#fits == 1 and fits[1] == "short line", "text that fits stays one line")
assert(calls == 1, "text that fits is measured once, got " .. tostring(calls))
calls = 0
local wrapped = Layout.wrapLines("aaa bbb ccc", 7, counted)
assert(#wrapped == 2, "the wrapped case still breaks")
assert(calls > 1, "a text that must wrap is measured more than once, got " .. tostring(calls))

-- The real notice sentence must fit a 428-pixel sheet in more than one line and
-- in no line wider than the sheet: this is the defect the player reported.
local notice = "You are not alone any more. Press F1 and open the Knox Survivors page"
    .. " of the Survival Guide for how to build a home, give orders and keep your people fed."
local function pixels(value) return #value * 7 end
local shaped = Layout.wrapLines(notice, 428, pixels)
assert(#shaped > 1, "the notice needs more than one line at 428, got " .. tostring(#shaped))
for index, line in ipairs(shaped) do
    assert(pixels(line) <= 428, "notice line " .. tostring(index) .. " leaves the sheet")
end
assert(table.concat(shaped, " "):find(notice, 1, true) == 1,
    "the wrapped notice is the same sentence")

-- The filter window's new-container instruction is the other reader of the rule.
local suggested = "Suggested for this container: General Storage."
    .. " Untick anything you do not want, then save."
local filterLines = Layout.wrapLines(suggested, 300, pixels)
for index, line in ipairs(filterLines) do
    assert(pixels(line) <= 300, "filter line " .. tostring(index) .. " leaves the sheet")
end
assert(#filterLines > 1, "the suggested-filter line wraps at 300")
