-- A household's place must answer the player the way a camp does, without a
-- saved warning ladder and without spending a line nobody could say.
local C = assert(rawget(_G, "KnoxFactionCamps"), "camps owner missing")

assert(type(C.householdLine) == "function", "household line must exist")
assert(type(C.reactionFor) == "function", "camp reaction must exist")

local home = { buildingId = "bld-police", context = "law_enforcement" }
local company = { groupId = "travel-group-7", leaderId = "s1", memberCount = 3, home = home }

-- Inside eight tiles a stranger's household warns; a trusted one welcomes.
local kind, text = C.householdLine(company, 9, "neutral", false, 100, 0)
assert(kind == "warning" and type(text) == "string" and text ~= "",
    "a stranger at the door is warned")
assert(C.householdLine(company, 64, "neutral", false, 100, 0) == "warning",
    "eight tiles is still the doorstep")
assert(C.householdLine(company, 65, "neutral", false, 100, 0) == nil,
    "one tile past the doorstep is silence")
local welcome = C.householdLine(company, 4, "friendly", false, 100, 0)
assert(welcome == "welcome", "a trusted visitor is welcomed")

-- It is said once, and never into a fight.
assert(C.householdLine(company, 4, "neutral", true, 100, 0) == nil,
    "a household speaks once per session")
assert(C.householdLine(company, 4, "hostile", false, 100, 0) == nil,
    "a hostile household is combat's business")
assert(C.householdLine(company, 4, "neutral", false, 100, 200) == nil,
    "a cooldown still in the future keeps it quiet")

-- The acknowledgement is time-based, not once for ever: a household living
-- beside a road you use is quiet for a while, then says hello again.
assert(type(C.householdCooldownHours) == "function", "a household cooldown exists")
assert(C.householdCooldownHours() > 0 and C.householdCooldownHours() <= 24,
    "the cooldown is a real, bounded interval")
assert(C.householdLine(company, 4, "neutral", false, 100, 106) == nil,
    "the line stays quiet inside the cooldown")
assert(C.householdLine(company, 4, "neutral", false, 107, 106) == "warning",
    "the line returns once the cooldown has passed")

-- Speech comes from the nearest body in sight, not from a leader or a first
-- match: a guard in front of the player must answer before someone at the edge.
assert(type(C.nearestSpeaker) == "function", "a speaker selector exists")
local near = { id = "near", character = {}, x = 103, y = 100, visible = true }
local far = { id = "far", character = {}, x = 110, y = 100, visible = true }
local blind = { id = "blind", character = {}, x = 101, y = 100, visible = false }
local chosen = C.nearestSpeaker({ far, blind, near }, 100, 100)
assert(chosen == near, "the nearest visible member answers")
assert(C.nearestSpeaker({ blind }, 100, 100) == nil,
    "nobody in sight means nobody speaks")
assert(C.nearestSpeaker({ far }, 100, 100) ~= nil, "twelve tiles is still audible")
assert(C.nearestSpeaker({ { id = "x", character = {}, x = 200, y = 200, visible = true } },
    100, 100) == nil, "a distant member is not the voice at your shoulder")
assert(C.nearestSpeaker({}, 100, 100) == nil, "an empty camp says nothing")
assert(C.nearestSpeaker(nil, 100, 100) == nil, "no candidates, no speaker")
assert(C.nearestSpeaker({ near }, nil, nil) == nil, "no player position, no speaker")
assert(C.nearestSpeaker({ near }, 100, 100, 2) == nil,
    "the caller's bound is respected")

-- A trusted place uses the player's name; a stranger is never addressed by it,
-- and an unusable name falls back to the plain line rather than an empty gap.
local camp = { id = "f", kind = "npc", name = "The Ravens" }
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, "  Nora  "))
    == "You are welcome here, Nora. Mind the door.",
    "a trusted household greets the player by name")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, "Nora"))
    == "Good to see you, Nora. Make yourself at home.",
    "a friendly camp greets the player by name")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, "Nora"))
    == "This is where we live. Say what you want.",
    "a stranger is not addressed by name")
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, "   "))
    == "You are welcome here. Mind the door.", "a blank name is no name")
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, "Nor\na"))
    == "You are welcome here. Mind the door.", "a broken name is no name")

-- A home at night speaks differently: the same door at a different hour.
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 12))
    == "This is where we live. Say what you want.", "daytime keeps the daytime line")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 23))
    == "It is late. Say what you want, then move on.", "night changes the line")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 3))
    == "It is late. Say what you want, then move on.", "the small hours are night")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 6))
    == "This is where we live. Say what you want.", "six in the morning is day")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 21))
    == "It is late. Say what you want, then move on.", "nine at night is night")
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, "Nora", 23))
    == "You are out late, Nora. Mind the door.", "a trusted household names late arrivals")
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, nil, 23))
    == "You are out late. Mind the door.", "an unnamed late arrival is still greeted")
assert(select(2, C.householdLine(company, 4, "friendly", false, 0, nil, "Nora", nil))
    == "You are welcome here, Nora. Mind the door.", "no clock means the daytime line")
assert(select(2, C.householdLine(company, 4, "neutral", false, 0, nil, nil, 25))
    == "It is late. Say what you want, then move on.", "an hour past midnight wraps")

-- A camp reads the same clock: the first warning after dark is about the
-- hour, but the ladder itself never changes with it.
assert(select(2, C.reactionFor(camp, 4, "neutral", 100, 0, 0, nil, 12))
    == "Keep your distance. This is our camp.", "daytime keeps the first warning")
assert(select(2, C.reactionFor(camp, 4, "neutral", 100, 0, 0, nil, 2))
    == "Late to be walking in. This is our camp.", "a night-time stranger is warned about the hour")
assert(select(2, C.reactionFor(camp, 4, "neutral", 100, 0, 1, nil, 2))
    == "I said keep back. We are not asking twice.",
    "the ladder does not change with the hour")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, "Nora", 23))
    == "You are out late, Nora. Make yourself at home.",
    "a friendly camp names the late arrival")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, nil, 12))
    == "Good to see you. Make yourself at home.", "daytime welcome is unchanged")

-- Coming back is its own beat, and only the first rung hears it.
assert(C.reactionDistanceSq() == 64, "the camp doorstep is eight tiles")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, "Nora", 12, true))
    == "Back again, Nora. Make yourself at home.", "a returning friend is named")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, nil, 12, true))
    == "Back again. Make yourself at home.", "a returning stranger is still recognised")
assert(select(2, C.reactionFor(camp, 4, "neutral", 100, 0, 0, nil, 12, true))
    == "Back again. Mind how close you come.", "a returning stranger is warned about returning")
assert(select(2, C.reactionFor(camp, 4, "neutral", 100, 0, 1, nil, 12, true))
    == "I said keep back. We are not asking twice.",
    "once told off, a return is not a fresh start")
assert(select(3, C.reactionFor(camp, 4, "neutral", 100, 0, 0, nil, 12, true)) == 1,
    "a return visit still advances the ladder")
assert(select(2, C.reactionFor(camp, 4, "friendly", 100, 0, 0, nil, 12, false))
    == "Good to see you. Make yourself at home.", "a first arrival is not a return")

-- A household's place becomes the camp assignment its people are held to:
-- derived from the shared home, never invented when there is no place.
local home = { buildingId = "b42", context = "police station" }
local house = { groupId = "g1", leaderId = "nora", memberCount = 3, home = home }
local place = { x = 100, y = 200, z = 0, buildingId = "b42",
    minX = 98, maxX = 104, minY = 198, maxY = 202 }
assert(C.homeCampFor(house, nil, { "nora" }) == nil, "no loaded place, no home camp")
assert(C.homeCampFor({ groupId = "g1", home = nil }, place, { "nora" }) == nil,
    "a household without a shared place holds nothing")
assert(C.homeCampFor({ groupId = "", home = home }, place, { "nora" }) == nil,
    "a nameless household cannot own a place")
local campHome = C.homeCampFor(house, place, { "nora", "", 7, "moss" })
assert(campHome ~= nil, "a shared home becomes a camp assignment")
assert(campHome.id == "home:g1", "the place is keyed by its household")
assert(campHome.kind == "household" and campHome.buildingId == "b42",
    "the place is the building the household was allocated in")
assert(campHome.x == 100 and campHome.y == 200 and campHome.z == 0,
    "the place is where the house is")
assert(campHome.minX == 98 and campHome.maxY == 202, "the place keeps its bounds")
assert(#campHome.memberIds == 2 and campHome.memberIds[2] == "moss",
    "only real members hold the place")
assert(C.memberSlot(campHome, "moss") == 2, "members keep a stable slot")
local loose = C.homeCampFor(house, { x = 5, y = 6 }, nil)
assert(loose.minX == 1 and loose.maxY == 10 and #loose.memberIds == 0,
    "a place with no bounds still stands around its own square")

-- Stepping inside the home changes the sentence, and outranks the hour.
assert(select(2, C.householdLine(company, 2, "neutral", false, 0, nil, nil, 12, true))
    == "You are in our home. Say what you want.", "inside a home is not the street")
assert(select(2, C.householdLine(company, 2, "friendly", false, 0, nil, "Nora", 12, true))
    == "Come in, Nora. Mind the door.", "a trusted visitor is invited in by name")
assert(select(2, C.householdLine(company, 2, "friendly", false, 0, nil, nil, 12, true))
    == "Come in. Mind the door.", "an unnamed trusted visitor is still invited in")
assert(select(2, C.householdLine(company, 2, "neutral", false, 0, nil, nil, 12, false))
    == "This is where we live. Say what you want.", "outside keeps the street line")

-- A home assignment is recognised by its key, so leaving can release it
-- without releasing a faction camp the same person might belong to.
assert(C.isHomeCampId("home:g1") == true, "a home assignment is recognisable")
assert(C.isHomeCampId("camp-17") == false, "a faction camp is not a home")
assert(C.isHomeCampId(nil) == false and C.isHomeCampId("") == false,
    "no assignment is not a home")
assert(C.isHomeCampId("home:") == true, "the key alone identifies the place")

-- The street and the doorstep do not consume each other's line.
assert(C.householdSpeechKey("g1", true) == "g1:in", "inside has its own key")
assert(C.householdSpeechKey("g1", false) == "g1:out", "outside has its own key")
assert(C.householdSpeechKey("g1", false) ~= C.householdSpeechKey("g1", true),
    "crossing the wall is a new moment")
assert(C.householdSpeechKey("g1", true) == C.householdSpeechKey("g1", true),
    "the same side is the same moment")
assert(C.householdSpeechKey(nil, true) == nil, "no household, no key")
assert(C.householdSpeechKey("", false) == nil, "an empty household has no key")

-- A line does not pass through a floor: reach is the same storey only.
assert(C.placeDistanceSq(100, 100, 0, 103, 104, 0) == 25, "same floor measures")
assert(C.placeDistanceSq(100, 100, 0, 100, 100, 1) == nil,
    "a floor between them is no distance at all")
assert(C.placeDistanceSq(nil, 100, 0, 100, 100, 0) == nil, "no position, no reach")
assert(C.placeDistanceSq(100, 100, nil, 100, 100, nil) == 0,
    "missing storeys are treated as the ground floor")
local upstairs = { id = "up", character = {}, x = 101, y = 100, z = 1, visible = true }
local downstairs = { id = "down", character = {}, x = 105, y = 100, z = 0, visible = true }
assert(C.nearestSpeaker({ upstairs, downstairs }, 100, 100, nil, 0) == downstairs,
    "the person on your own floor answers, not the one above")
assert(C.nearestSpeaker({ upstairs }, 100, 100, nil, 0) == nil,
    "nobody on your floor means nobody speaks")
assert(C.nearestSpeaker({ upstairs, downstairs }, 100, 100) == upstairs,
    "without a player storey the nearest wins as before")

-- A home yields to real work and sleep, and holds the idle.
assert(C.homeHeldByIntent(false) == true, "an idle member is held by their home")
assert(C.homeHeldByIntent(nil) == true, "no intent is still no reason to leave")
assert(C.homeHeldByIntent(true) == false, "a member with work to do is not held")

-- The sentence belongs to the building, not to the person.
assert(C.speaksForPlace(house, "b42") == true, "the household speaks at home")
assert(C.speaksForPlace(house, "b99") == false, "another building is not their door")
assert(C.speaksForPlace(house, nil) == false, "no building, no sentence")
assert(C.speaksForPlace({ groupId = "g1", home = nil }, "b42") == false,
    "a household with no place says nothing")
assert(C.speaksForPlace({ groupId = "g1", home = { buildingId = "" } }, "") == false,
    "an unnamed building is no place")

-- Met away from home, a household talks about the road, never about a place.
assert(select(2, C.awayLine(4, "neutral", 100, 0, nil, 12))
    == "Road is no place to chat. Keep moving.", "a stranger on the road is warned")
assert(select(2, C.awayLine(4, "neutral", 100, 0, nil, 23))
    == "Not a night to be out. Keep moving.", "the road at night says so")
assert(select(2, C.awayLine(4, "friendly", 100, 0, "Nora", 12))
    == "Good to see you out here, Nora.", "a friend on the road is named")
assert(select(2, C.awayLine(4, "allied", 100, 0, nil, 12))
    == "Good to see you out here.", "an allied faction on the road is friendly")
assert(select(2, C.awayLine(4, "friendly", 100, 0, nil, 23))
    == "Good to see you out here. Careful now.", "a friend on the road at night is warned")
assert(C.awayLine(4, "hostile", 100, 0, nil, 12) == nil, "a hostile household says nothing")
assert(C.awayLine(9 * 9, "neutral", 100, 0, nil, 12) == nil, "past eight tiles there is no line")
assert(C.awayLine(4, "neutral", 100, 106, nil, 12) == nil, "the cooldown still applies")
assert(select(2, C.awayLine(4, "neutral", 100, 0, nil, 12)):find("live", 1, true) == nil,
    "the road line never claims a home")

-- No shared place, no line.
assert(C.householdLine({ groupId = "g", leaderId = "s1", home = nil }, 4, "neutral",
    false, 100, 0) == nil, "a household with no shared place says nothing")
assert(C.householdLine(nil, 4, "neutral", false, 100, 0) == nil, "no facts, no line")
assert(C.householdLine(company, nil, "neutral", false, 100, 0) == nil,
    "an unreadable distance says nothing")

-- The camp ladder still behaves, and the caller now decides when it is spent.
local faction = { kind = "npc", name = "Millers" }
assert(select(1, C.reactionFor(faction, 4, "neutral", 100, 0, 0)) == "warning")
assert(select(1, C.reactionFor(faction, 4, "neutral", 100, 0, 1)) == "warning")
assert(select(1, C.reactionFor(faction, 4, "neutral", 100, 0, 2)) == "final")
assert(C.reactionFor(faction, 4, "neutral", 100, 0, 9) ~= nil,
    "the ladder is bounded, not extended")
assert(C.reactionFor(faction, 4, "hostile", 100, 0, 0) == nil)
assert(C.reactionFor(faction, 65, "neutral", 100, 0, 0) == nil)

print("household place line PASS warning=true welcome=true once=true door=true ladder=true")
