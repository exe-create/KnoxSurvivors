-- Drives the real Creator.visibleStartingTemplates and the kind catalogue.
-- Town-named rosters must stop being offered while their ids still resolve,
-- and the three services must remain creatable as behaviours.
local hidden = 0
for _, entry in ipairs(Creator.STARTING_TEMPLATES) do
    if entry.hidden == true then hidden = hidden + 1 end
end
assert(hidden > 0, 'some starting rosters are hidden')
local visible = Creator.visibleStartingTemplates()
assert(#visible == #Creator.STARTING_TEMPLATES - hidden, 'the visible list drops exactly the hidden ones')
for _, entry in ipairs(visible) do
    assert(entry.hidden ~= true, 'no hidden roster is offered')
    assert(not string.find(tostring(entry.id), 'template_rosewood_', 1, true),
        'Rosewood police is no longer offered')
    assert(not string.find(tostring(entry.id), 'template_household_', 1, true),
        'household defaults are no longer offered')
end
assert(Creator.startingTemplate('template_rosewood_police') ~= nil,
    'an old save still resolves the Rosewood police id')
assert(Creator.startingTemplate('template_household_3') ~= nil,
    'an old save still resolves a household id')
for _, kindId in ipairs({ 'police', 'military', 'fire_service' }) do
    local behaviour = Creator.behaviourFor(kindId)
    assert(behaviour ~= nil, kindId .. ' is still a real kind')
    assert(behaviour.settles == true, kindId .. ' still settles a home')
    assert(Creator.kindLabel(kindId) ~= 'Group', kindId .. ' still has its own label')
end
assert(Creator.behaviourFor('police').spawnContext == 'law_enforcement',
    'police still come from police stations')
assert(Creator.behaviourFor('military').spawnContext == 'military',
    'military still come from military facilities')
assert(Creator.behaviourFor('military').hostileToOutsiders == true,
    'military is still hostile to outsiders')
assert(Creator.behaviourFor('police').hostileToOutsiders == false,
    'police still help rather than hunt outsiders')

-- The creator's marks decide the starting cast: companions within the sandbox
-- cap, at most one spouse, and nobody marked means nobody joins.
local cast = { {name="Ada"}, {name="Bo"}, {name="Cy"}, {name="Di"}, {name="Ed"} }
local companions, spouse, others, cap = Creator.startingSplit(cast, 2)
assert(cap == 2 and #companions == 0 and spouse == nil and #others == 5,
    "nobody marked means nobody joins")
cast[2].startCompanion = true
cast[4].startSpouse = true
companions, spouse, others = Creator.startingSplit(cast, 2)
assert(#companions == 1 and companions[1].name == "Bo", "a marked companion walks in")
assert(spouse ~= nil and spouse.name == "Di", "a marked spouse walks in")
assert(#others == 3, "everyone unmarked is seeded")
-- Marked beyond the cap: the marks stay, the split simply stops at the limit.
cast[1].startCompanion = true
cast[3].startCompanion = true
companions, spouse, others = Creator.startingSplit(cast, 2)
assert(#companions == 2 and companions[1].name == "Ada" and companions[2].name == "Bo",
    "the cap holds the companion count in roster order")
local ok, message = Creator.toggleStart(cast, cast[5], "companion", 2)
assert(ok == false and string.find(message, "Untick one", 1, true) ~= nil,
    "a full party refuses with the rule")
ok, message = Creator.toggleStart(cast, cast[3], "companion", 2)
assert(ok == true and string.find(message, "seeded", 1, true) ~= nil, "unticking seeds them")
ok = Creator.toggleStart(cast, cast[1], "companion", 2)
assert(ok == true and cast[1].startCompanion == false, "a companion can be traded out")
ok, message = Creator.toggleStart(cast, cast[5], "companion", 2)
assert(ok == true and string.find(message, "2 of 2", 1, true) ~= nil,
    "a freed slot accepts another companion")
ok, message = Creator.toggleStart(cast, cast[3], "spouse", 2)
assert(ok == false and string.find(message, "Untick", 1, true) ~= nil,
    "a second spouse is refused")
ok = Creator.toggleStart(cast, cast[4], "spouse", 2)
assert(ok == true and cast[4].startSpouse == false, "the current spouse can be unticked")
cast[4].startSpouse = true
ok = Creator.toggleStart(cast, cast[4], "companion", 2)
assert(ok == false, "a spouse cannot also be marked as a companion")
local counts, picked = Creator.startCounts(cast)
assert(counts == 2 and picked ~= nil and picked.name == "Di", "counts agree with the marks")
-- One definition of each person's role, shared by the cards and the row.
assert(Creator.startingRole(cast[4]) == "spouse", "the spouse reads as spouse")
assert(Creator.startingRole(cast[2]) == "companion", "a companion reads as companion")
assert(Creator.startingRole(cast[1]) == nil, "an unticked person has no role")
local marked = Creator.markedCast(cast)
assert(#marked == 3 and marked[1].person == cast[2] and marked[1].index == 2
    and marked[2].person == cast[4] and marked[3].person == cast[5],
    "the marked cast reads back in roster order")
local startingView = Creator.peopleByFaction(cast, {}, "starting")
assert(#startingView == 3, "the companions view lists only marked people")

-- The centered popup names the rule; the note line keeps the sentence.
local _, _, fullTitle = Creator.toggleStart(cast, cast[1], "companion", 2)
assert(fullTitle == "Companions at max", "a full party titles its popup")
local _, _, spouseTitle = Creator.toggleStart(cast, cast[3], "spouse", 2)
assert(spouseTitle == "One spouse allowed", "a second spouse titles its popup")
local _, _, ownTitle = Creator.toggleStart(cast, cast[4], "companion", 2)
assert(ownTitle == "Already your spouse", "a spouse keeps their own title")
