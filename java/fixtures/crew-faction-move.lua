-- Moving a survivor between groups is one press on the crew surface. The list
-- that press walks is pure; the writer still decides whether the move is
-- allowed. This drives both halves of that split.
local C = assert(codecCrewFaction, "crew faction helpers are loaded")

local factions = {
    { id = "f-b", name = "Millers" },
    { id = "f-a", name = "Rooks" },
    { id = "f-c", name = "The Narrows" },
    { id = "", name = "Nameless" },
    { id = "f-d", name = "" },
    { id = "f-e" },
}

-- No current group: every named group is offered in id order, and the
-- unnamed or nameless records are not offered at all.
local choices, current = C.factionChoices(factions, nil)
assert(#choices == 3, "only named groups are offered, got " .. tostring(#choices))
assert(choices[1].id == "f-a" and choices[2].id == "f-b" and choices[3].id == "f-c",
    "the list is ordered by id")
assert(current == nil, "a survivor with no group has no current label")

-- Standing in the middle: the next group comes first, the current one last, so
-- one press always changes the group while more than one exists.
choices, current = C.factionChoices(factions, "f-b")
assert(current == "Millers", "the current label is the group they are in")
assert(choices[1].id == "f-c", "the next group is offered first")
assert(choices[2].id == "f-a", "the list wraps around the end")
assert(choices[3].id == "f-b", "the current group is last, never first")

-- Standing in the last group still wraps to the first.
choices = C.factionChoices(factions, "f-c")
assert(choices[1].id == "f-a", "the last group wraps to the first")
assert(choices[3].id == "f-c", "and keeps itself last")

-- An unknown current id (a group that disbanded) offers the plain list.
choices, current = C.factionChoices(factions, "f-gone")
assert(#choices == 3 and choices[1].id == "f-a" and current == nil,
    "a stale group id does not reorder or label the list")

-- A single group is still one option: the caller has to decide what pressing
-- does when nothing would change.
local only = C.factionChoices({ { id = "f-a", name = "Rooks" } }, "f-a")
assert(#only == 1 and only[1].id == "f-a", "one group is one choice")

assert(#C.factionChoices(nil, nil) == 0, "no factions means no choices")
assert(#C.factionChoices({}, "f-a") == 0, "an empty table means no choices")
assert(#C.factionChoices({ { id = "f-a" }, { name = "x" } }, nil) == 0,
    "records without an id or a name are skipped")

-- Every reason the writer can return has a sentence; an unseen reason still
-- says something true instead of an empty line.
assert(C.factionRefusalText("player_affiliated") == "They answer to you, not to that group.",
    "the player-owned refusal is its own sentence")
assert(C.factionRefusalText("away_team") == "They are away on a job.")
assert(C.factionRefusalText("dead") == "They are dead.")
assert(C.factionRefusalText("missing_faction") == "That group is gone.")
assert(C.factionRefusalText(nil) == "They cannot join that group now.",
    "an unknown reason still answers with a sentence")

print("Crew faction move PASS rotate=true named=true stale=true copy=true")
