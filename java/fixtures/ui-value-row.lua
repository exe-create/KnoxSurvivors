-- The one value-row rule: counts lead, the unit follows the number, and a tone
-- the palette does not own falls back instead of inventing a colour. Pure, so
-- this fixture needs no atlas and no page.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")
assert(type(L.valueRow) == "function", "the layout owns the value row")

local row = L.valueRow(3, "residents")
assert(row.text == "3 residents", "counts lead the unit, got '" .. row.text .. "'")
assert(row.value == "3", "the number is kept on its own")
assert(row.label == "residents", "the unit is kept on its own")
assert(row.tone == "bone", "an unspecified tone is the readable one")

assert(L.valueRow(1, "resident").text == "1 resident", "the caller supplies plurality")
assert(L.valueRow(0, "").text == "0", "a unitless count is just the number")
assert(L.valueRow(nil, "residents").text == "0 residents", "nil reads as zero")

local blocked = L.valueRow(2, "blocked", { tone = "red" })
assert(blocked.tone == "red", "a known tone is kept")
assert(blocked.text == "2 blocked", "the tone never changes the words")

local unknown = L.valueRow(1, "thing", { tone = "chartreuse" })
assert(unknown.tone == "bone", "an unknown tone falls back, got '" .. tostring(unknown.tone) .. "'")
