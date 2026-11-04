local all = assert(codecDraftAllAnything, "the draft predicate is loaded")

assert(all(nil) == true, "no draft is already empty")
assert(all({}) == true, "an empty draft is already empty")

local anything = {}
for hour = 1, 24 do anything[hour] = "anything" end
assert(all(anything) == true, "a full Anything draft has nothing to clear")

local mixed = {}
for hour = 1, 24 do mixed[hour] = "anything" end
mixed[1] = "work"
assert(all(mixed) == false, "one worked hour means the draft is clearable")

local sparse = {}
sparse[24] = "sleep"
assert(all(sparse) == false, "a sparse draft with one entry is clearable")

assert(all({ 1, 2, 3 }) == false, "unknown values are treated as a real draft")

print("Notebook draft PASS empty_clearable=false single_hour=true")
