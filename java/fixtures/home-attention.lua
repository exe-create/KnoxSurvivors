-- The Home attention band is a pure projection over facts the Work tab already
-- reads. This fixture drives the real production projection; it does not
-- pretend to render a window or prove that a base problem was fixed.
local A = assert(codecHomeAttention, "home attention source is loaded")

local counts = A.homeCounts({
    { alive = true, present = true },
    { alive = true, present = true, away = true },
    { alive = true, present = false },
    { alive = false },
    { alive = true, present = true, event = true },
})
assert(counts.home == 1 and counts.away == 3 and counts.dead == 1,
    "home, away and dead are distinct resident states")
local missingCounts = A.homeCounts({ { alive = true, missing = true } })
assert(missingCounts.missing == 1 and missingCounts.home == 0,
    "a future missing state remains separate from away")

local function facts(overrides)
    local value = {
        residents = 4,
        zones = 2,
        tasks = { blocked = 2, queued = 1, claimed = 1 },
        security = { guardPosts = 0, patrolRoutes = 0, understaffed = 0 },
        unshelved = 1,
        storageAssigned = 2,
        bedsWithout = 2,
        kitShort = 2,
        kitUnknown = 1,
        stockKnown = true,
        shortage = { category = "food", label = "Food", missing = 4 },
    }
    for key, replacement in pairs(overrides or {}) do value[key] = replacement end
    return value
end

local items = A.attentionItems(facts())
assert(#items == 3, "the band shows at most three problems")
assert(items[1].key == "blocked" and items[1].title == "2 tasks are blocked",
    "blocked work is the first attention item")
assert(items[1].action == "review_tasks" and items[1].actionLabel == "Review tasks",
    "blocked work points at the existing task queue")
assert(items[2].key == "unshelved" and items[2].title == "1 haul still unshelved",
    "an unshelved haul is named in plain language")
assert(items[2].action == "review_storage",
    "an unshelved haul points at the existing storage list")
assert(items[3].key == "security" and items[3].title == "No security posts",
    "missing security is surfaced before lower-priority readiness items")

local singular = A.attentionItems(facts({
    tasks = { blocked = 1 }, unshelved = 2,
    security = { guardPosts = 0, patrolRoutes = 0, understaffed = 0 },
}))
assert(singular[1].title == "1 task is blocked", "one blocked task is singular")
assert(singular[2].title == "2 hauls still unshelved", "two hauls are plural")
assert(singular[3].action == "add_guard",
    "the no-security action offers the real guard-area flow")

local unstaffed = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 1,
    bedsWithout = 0, kitShort = 0, kitUnknown = 0, stockKnown = false,
    security = { guardPosts = 2, patrolRoutes = 0, understaffed = 1 },
}))
assert(#unstaffed == 1 and unstaffed[1].key == "security_unstaffed",
    "an existing but unstaffed post is a separate problem from no post")
assert(unstaffed[1].title == "1 security post is unstaffed",
    "an unstaffed post is singular and specific")
assert(unstaffed[1].action == "review_security",
    "an unstaffed post points at the existing area list")

local zones = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 0, security = { guardPosts = 1 }, storageAssigned = 1,
    bedsWithout = 0, kitShort = 0, kitUnknown = 0, stockKnown = false,
}))
assert(zones[1].key == "zones" and zones[1].action == "choose_area",
    "a base with no work areas offers the area picker")

local storage = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 0,
    bedsWithout = 0, kitShort = 0, kitUnknown = 0, stockKnown = false,
    security = { guardPosts = 1 },
}))
assert(storage[1].key == "storage" and storage[1].action == "review_storage",
    "a base with no assigned storage is surfaced")

local beds = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 1,
    bedsWithout = 1, kitShort = 0, kitUnknown = 0, stockKnown = false,
    security = { guardPosts = 1 },
}))
assert(beds[1].key == "beds" and beds[1].title == "1 resident has no bed",
    "a missing bed is surfaced with the existing roster action")
assert(beds[1].action == "review_beds", "the bed action points at the bed roster")

local kits = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 1,
    bedsWithout = 0, kitShort = 3, kitUnknown = 0, stockKnown = false,
    security = { guardPosts = 1 },
}))
assert(kits[1].key == "kits" and kits[1].title == "3 role kits are short",
    "role-kit shortages are plural and concrete")
assert(kits[1].action == "review_kits", "the kit action points at the existing list")

local reserve = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 1,
    bedsWithout = 0, kitShort = 0, kitUnknown = 0, stockKnown = true,
    security = { guardPosts = 1 }, waterSource = "dry",
    shortage = { category = "water", label = "water", missing = 6,
        current = 2, target = 8 },
}))
assert(reserve[1].key == "reserve" and reserve[1].title == "Water: 6 below target (2 / 8)",
    "a reserve shortage leads with its count and keeps its amounts")
assert(reserve[1].detail == "The taps are dry; stored water is the whole supply.",
    "a dry water shortage says why the target is raised")
assert(reserve[1].stockKey == "water",
    "the reserve action can target the existing stock control")

local unknown = A.attentionItems(facts({
    tasks = {}, unshelved = 0, zones = 1, storageAssigned = 1,
    bedsWithout = 0, kitShort = 0, kitUnknown = 1, stockKnown = false,
    security = { guardPosts = 1 },
}))
assert(unknown[1].key == "kits_unknown" and unknown[1].title == "1 resident is out of contact",
    "out-of-contact readiness is a separate honest state")

local clear = A.attentionItems(facts({
    tasks = {}, unshelved = 0, security = { guardPosts = 1 }, storageAssigned = 1,
    bedsWithout = 0, kitShort = 0, kitUnknown = 0, stockKnown = true,
    shortage = { category = "food", label = "Food", missing = 0 },
}))
assert(#clear == 0, "a complete, staffed, supplied base has no invented problem")

local emptyRoster = A.attentionItems(facts({
    residents = 0, zones = 0, security = { guardPosts = 0, patrolRoutes = 0 },
    tasks = {}, unshelved = 0, storageAssigned = 0, bedsWithout = 0,
    kitShort = 0, kitUnknown = 0, stockKnown = false,
}))
assert(#emptyRoster == 0, "an empty base does not invent resident problems")

assert(#A.attentionItems(nil) == 0, "missing facts produce an empty band")
assert(#A.attentionItems({}) == 0, "empty facts produce an empty band")

local overflow = facts({
    tasks = { blocked = 1 }, unshelved = 1, zones = 0, storageAssigned = 0,
    bedsWithout = 3, kitShort = 3, kitUnknown = 3,
    security = { guardPosts = 0, patrolRoutes = 0, understaffed = 0 },
})
local capped = A.attentionItems(overflow)
assert(#capped == 3, "the band stays bounded when many problems exist")
assert(overflow.tasks.blocked == 1 and overflow.zones == 0,
    "the projection never rewrites the facts it reads")

-- WHO IS OUT OF THE WAY. The base projection measures it from the residents'
-- own decisions, so the raid line can name it instead of the player watching a
-- corner. Only the fallback decisions count; an armed defender answering the
-- alarm is doing the opposite of standing clear.
local function resident(decision, extra)
    local row = { alive = true, present = true, decision = decision }
    for key, value in pairs(extra or {}) do row[key] = value end
    return row
end
assert(A.fallbackCount({
    resident("base_withdraw"), resident("base_hold"),
    resident("base_defend"), resident("flee"), resident(nil),
}) == 2, "only the fallback decisions are residents out of the way")
assert(A.fallbackCount({}) == 0, "an empty roster has nobody out of the way")
assert(A.fallbackCount(nil) == 0, "missing rows are not invented residents")
assert(A.fallbackCount({ resident("base_hold", { alive = false }) }) == 0,
    "a dead resident is not standing at the fallback")
assert(A.fallbackCount({ resident("base_hold", { away = true }) }) == 0,
    "a resident away from home is not holding a corner here")
assert(A.fallbackCount({ resident("base_hold", { present = false }) }) == 0,
    "an absent resident is not counted as holding")
assert(A.fallbackCount({ "base_hold" }) == 0, "a bare word is not a resident row")
assert(A.fallbackCount({ resident("BASE_HOLD") }) == 0,
    "the decision is read exactly, not fuzzily")
assert(A.fallbackCount({ resident("base_withdraw", { alive = true }) }) == 1,
    "a single civilian falling back is one resident")

print("Home attention PASS priority=true singular=true cap=true actions=true fallback=true")
