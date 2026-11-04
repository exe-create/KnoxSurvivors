local M = assert(KnoxSurvivorViewModel, "the survivor view model is loaded")
assert(type(M.partyProblemCount) == "function", "the party summary projection is loaded")

local healthy = {
    alive = true, activity = "Following", health = 1,
    needSummary = "Last reported (3 min ago): All right",
}
local unknown = {
    alive = true, activity = "Out of contact", health = nil,
    needSummary = "Needs not reported",
}
local hurt = { alive = true, activity = "Following", health = 0.5 }
local need = { alive = true, activity = "Following", health = 1,
    needSummary = "Last reported (5 min ago): Water" }
local falling = { alive = true, activity = "Falling back", health = 1,
    needSummary = "Last reported (2 min ago): All right" }
local dead = { alive = false, activity = "Dead", health = 0,
    needSummary = "Last reported (1 min ago): Bitten!" }
local bitten = { alive = true, activity = "Following", health = 1,
    needSummary = "Last reported (4 min ago): Bitten!" }
local dry = { alive = true, loaded = true, activity = "Fighting", health = 1,
    ammoName = "Empty", needSummary = "Last reported (1 min ago): All right" }
local dryFalling = { alive = true, loaded = true, activity = "Falling back",
    health = 1, ammoName = "Empty" }
local dryHurt = { alive = true, loaded = true, activity = "Fighting",
    health = 0.5, ammoName = "Empty" }
local holstered = { alive = true, loaded = true, activity = "Standing by",
    health = 1, ammoName = "Empty",
    needSummary = "Last reported (1 min ago): All right" }
local dryOffscreen = { alive = true, loaded = false,
    activity = "Last seen: Fighting", ammoName = "Empty" }

assert(M.partyProblemCount({}) == 0, "an empty party has no problem")
assert(M.partyProblemCount({ healthy, unknown }) == 0,
    "a healthy or unknown member is not a problem")
assert(M.partyProblemCount({ healthy, hurt }) == 1,
    "low health is one problem")
assert(M.partyProblemCount({ healthy, need, falling }) == 2,
    "reported needs and a visible fallback are separate problems")
assert(M.partyProblemCount({ healthy, dead, bitten }) == 2,
    "death and a bitten report are problems")
assert(M.partyProblemCount({ healthy, dry }) == 1,
    "a dry gun in a fight is one problem")
assert(M.partyProblemCount(nil) == 0, "a missing party is quiet")

local function label(snapshot)
    local condition = assert(M.partyCondition(snapshot), "a condition is available")
    return condition.label, condition.tone
end
assert(label(healthy) == "Fine", "a reported all-clear reads Fine")
assert(select(2, label(healthy)) == "good", "Fine is a good tone")
assert(label(unknown) == "Unknown", "an unknown report reads Unknown")
assert(label(hurt) == "Hurt", "low health reads Hurt")
assert(label(need) == "Thirsty", "a water report reads Thirsty")
assert(label(falling) == "Withdrawing", "a fallback reads Withdrawing")
assert(label(dry) == "Out of ammo",
    "a visible fighter with an empty gun reads Out of ammo")
assert(select(2, label(dry)) == "warn", "an empty gun is a warning, not a death")
assert(label(dryFalling) == "Out of ammo",
    "a dry fallback names the gun before the withdrawal")
assert(label(dryHurt) == "Hurt", "a wound outranks the empty gun")
assert(label(holstered) == "Fine",
    "a holstered empty gun is not a combat condition")
assert(label(dryOffscreen) == "Unknown",
    "an offscreen memory cannot claim a current empty gun")
assert(label(dead) == "Dead" and select(2, label(dead)) == "critical",
    "death stays critical")

assert(M.partyHeadline({}) == "No one with you", "an empty party is quiet")
assert(M.partyHeadline({ healthy, unknown }, false) == "2 · 1 unreported",
    "an unreported member is named instead of claiming all clear")
assert(M.partyHeadline({ healthy, hurt }, false) == "2 · 1 needs you",
    "one trouble reads as one person needing you")
assert(M.partyHeadline({ healthy, dry }, false) == "2 · 1 needs you",
    "a dry fighter joins the same one-line problem count")
assert(M.partyHeadline({ healthy, dead, bitten }, false) == "3 · 2 need you",
    "plural trouble reads as people, not a count of bars")
assert(M.partyHeadline({ healthy, hurt }, true) == "2 with you · 1 problem",
    "the compact row keeps its existing one-line summary")
assert(M.partyTone({ healthy, unknown }) == "muted",
    "an unreported member keeps the header from claiming all clear")
assert(M.partyTone({ unknown }) == "muted",
    "an all-unknown party never claims an all-clear")
assert(M.partyTone({ healthy, hurt }) == "warn",
    "a hurt person raises the compact accent")
assert(M.partyTone({ healthy, dead }) == "critical",
    "a death outranks every other condition")

assert(M.rosterCondition(healthy) == nil, "a healthy roster row spends no condition")
assert(M.rosterCondition(need) == "Thirsty", "a need names the roster row")
assert(M.rosterCondition(bitten) == "Bitten", "a bite names the roster row")
assert(M.rosterCondition(dry) == "Out of ammo",
    "a dry fighter names the roster row")
assert(M.rosterCondition(holstered) == nil,
    "a holstered empty gun spends no roster column")
assert(M.rosterCondition(dead) == "Dead", "death names the roster row")
assert(M.rosterCondition(unknown) == nil, "an unknown row says nothing")
assert(M.rosterCondition(nil) == nil, "a missing row says nothing")

local wary = assert(M.partyRefusal("wary"), "a wary companion earns a badge")
assert(wary.label == "Wary", "the wary badge has one word")
assert(wary.tone == "warn", "the wary badge is amber")
local hostile = assert(M.partyRefusal("hostile"), "a hostile companion earns a badge")
assert(hostile.label == "Hostile", "the hostile badge has one word")
assert(hostile.tone == "critical", "the hostile badge is red")
assert(M.partyRefusal("steady") == nil, "a willing companion has no badge")
assert(M.partyRefusal(nil) == nil, "an unknown willingness has no badge")
assert(M.partyRefusal("") == nil, "an empty willingness has no badge")
print("Party summary PASS healthy=true needs=true falling=true dead=true ammo=true roster=true refusal=true")
