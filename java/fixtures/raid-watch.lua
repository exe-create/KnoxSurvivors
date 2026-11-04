-- The home's answer to an inbound raid: the readiness line that belongs to the
-- copy owner, and the existing job selector staffing real posts before routine
-- work. Both halves drive production functions; nothing here starts a raid.
local E = assert(KnoxEvents, "raid event owner is loaded")
local Jobs = assert(KnoxBaseJobs, "base job owner is loaded")
local clause = assert(E.raidWatchClause, "the readiness line lives in the copy owner")

-- READINESS LINE: counts the base really has, in words nobody else writes.
assert(clause({ posts = 3, staffed = 1 }) == "1 of 3 posts staffed.",
    "a partly staffed watch names both numbers")
assert(clause({ posts = 3, staffed = 0 }) == "3 posts are unmanned.",
    "three empty posts are plural")
assert(clause({ posts = 1, staffed = 0 }) == "The post is unmanned.",
    "one empty post is singular")
assert(clause({ posts = 2, staffed = 2 }) == "Every post is staffed.",
    "full coverage says so plainly")
assert(clause({ posts = 2, staffed = 5 }) == "Every post is staffed.",
    "a stale overcount still reads as staffed")
assert(clause({ posts = 3 }) == "3 posts are unmanned.",
    "a missing staffing count is not a staffed post")
assert(clause({ posts = 0, staffed = 0 }) == nil,
    "no posts is a layout gap, not a plan")
assert(clause({ posts = "3", staffed = 1 }) == "1 of 3 posts staffed.",
    "a numeric string still reads")
assert(clause({ posts = "many" }) == nil, "an unreadable count is not a plan")
assert(clause(nil) == nil, "no security facts, no claim")

-- THE ALARM IS UNCHANGED. Readiness is a second sentence, never a new alarm.
local warning = {
    factionName = "Northside Crew", direction = "south-east", strength = "a few armed",
    cause = "retaliation", etaHours = 12.15, hours = 12,
}
local plain = E.raidAttention(warning)
assert(plain.detail == "A few armed; they want it back.",
    "without watch facts the detail is unchanged: " .. tostring(plain.detail))
local watched = E.raidAttention(warning, { posts = 3, staffed = 1 })
assert(watched.detail == "A few armed; they want it back. 1 of 3 posts staffed.",
    "the watch facts extend the same sentence: " .. tostring(watched.detail))
assert(watched.title == plain.title, "readiness never rewrites the alarm")
assert(watched.action == "review_world" and watched.actionLabel == "Review threat",
    "the item still routes to the existing World tab")

-- SELECTOR: an inbound raid staffs the spare posts before routine work.
local state = { records = {}, cooldowns = {}, automatic = {} }
local base = {
    id = "base-home", ownerKind = "player", ownerId = "player-1",
    home = { minX = 0, minY = 0, width = 4, height = 4, z = 0 },
    zones = {
        { id = "z1", type = "guard", enabled = true },
        { id = "z2", type = "guard", enabled = true },
        { id = "z3", type = "patrol", enabled = true },
        { id = "z4", type = "farm", enabled = true },
    },
    tasks = { held = { id = "held", type = "guard", state = "claimed", claimedBy = "r2" } },
}
local persistence = KnoxPersistence
local saved = {
    getBase = persistence.getBase,
    getBaseResidentIds = persistence.getBaseResidentIds,
    getSurvivorDuty = persistence.getSurvivorDuty,
    getWorkPreferences = persistence.getWorkPreferences,
    getSurvivorAffiliation = persistence.getSurvivorAffiliation,
    getKnoxEventState = persistence.getKnoxEventState,
}
persistence.getBase = function(id) return id == base.id and base or nil end
persistence.getBaseResidentIds = function() return { "r1", "r2", "r3" } end
persistence.getSurvivorDuty = function() return nil end
persistence.getWorkPreferences = function() return nil end
persistence.getSurvivorAffiliation = function() return nil end
persistence.getKnoxEventState = function() return state end

local function queued(id, kind, priority)
    return { id = id, type = kind, state = "queued", priority = priority, baseId = base.id }
end
local function choose()
    return Jobs.selectEligibleTask(
        { queued("g1", "guard", 50), queued("w1", "wood", 90) },
        "r1", base.id, "auto", function() return true end
    )
end

local routine = choose()
assert(routine ~= nil and routine.id == "w1",
    "with no raid, one held post is enough and routine work keeps its lead: "
        .. tostring(routine and routine.id))

state.records["raid-9"] = {
    id = "raid-9", kind = "faction_raid", phase = "approaching", revision = 1,
    targetBaseId = base.id, sourceBaseId = "base-north", sourceFactionId = "faction-north",
    targetFactionId = "player-faction", memberIds = { "a", "b", "c" },
    dueAtHours = 10, deadlineHours = 34, lastChangedAtHours = 10,
    warning = { factionName = "Northside Crew", direction = "south-east",
        strength = "a few armed", cause = "grievance", etaHours = 12.5, hours = 12 },
}
local alerted = choose()
assert(alerted ~= nil and alerted.id == "g1",
    "an inbound raid fills the second and third posts before routine work: "
        .. tostring(alerted and alerted.id))

-- An assault already under way is not a warning: the plan stops claiming the
-- spare posts and the ordinary rotation resumes.
state.records["raid-9"].phase = "active"
local fighting = choose()
assert(fighting ~= nil and fighting.id == "w1",
    "once the assault starts the selector returns to routine work: "
        .. tostring(fighting and fighting.id))
state.records["raid-9"].phase = "approaching"

-- The projection the selector reads is the same one the home line shows.
base.tasks = { held = { id = "held", type = "guard", state = "claimed", claimedBy = "r2" } }
local projected = E.inboundRaidForBase(base.id, 12, { posts = 4, staffed = 1 })
assert(projected ~= nil and projected.detail == "A few armed; they hold a grudge. 1 of 4 posts staffed.",
    "one projection feeds both the home line and the scheduler: " .. tostring(projected and projected.detail))

for key, value in pairs(saved) do persistence[key] = value end
assert(persistence.getKnoxEventState == saved.getKnoxEventState, "persistence reads are restored")
