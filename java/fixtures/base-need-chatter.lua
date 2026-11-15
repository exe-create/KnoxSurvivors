-- Base-needs chatter: a resident standing at their own base with another
-- resident speaks the existing need callout through the real speech owner.
-- Runs the production Controller:sayNeedIfGrouped; only engine/world edges and
-- the settings-gated feed sink are doubled. Every unchanged case must stay
-- silent: no peers, no base, threat, rest, timed action, cooldown, stale need.
local C = assert(KnoxAutonomyController)
local oldFeed, oldNeeds, oldBase, oldStore, oldQueue =
    KnoxActivityFeed, KnoxSurvivorNeeds, KnoxBaseManager, KnoxPersistence, ISTimedActionQueue
local spoken = {}
local base = { id = "chatterBase", territory = { minX = 0, minY = 0, width = 10, height = 10, z = 0 } }
local inside = { getX = function() return 5 end, getY = function() return 5 end, getZ = function() return 0 end }
local outside = { getX = function() return 50 end, getY = function() return 50 end, getZ = function() return 0 end }
local ids = { "speaker", "peer" }
local current = true
local function actorAt(square, busy)
    return {
        getCurrentSquare = function() return square end,
        getCharacterActions = function()
            if busy then return { isEmpty = function() return false end } end
            return nil
        end,
    }
end
KnoxActivityFeed = { speak = function(character, text) spoken[#spoken + 1] = text; return true end }
KnoxSurvivorNeeds = { isNeedCurrent = function() return current end }
KnoxBaseManager = assert(KnoxBaseManager, "a base manager must exist for the base test")
-- Base membership is a world read. When the harness carries the real manager,
-- the fixture uses it; when an earlier fixture left a stub, this restores the
-- rect rule the real BaseManager.containsSquare applies to a single building.
if KnoxBaseManager.containsSquare == nil
    or KnoxBaseManager.containsSquare(base, outside) ~= false then
    KnoxBaseManager = { containsSquare = function(b, s)
        local home = b ~= nil and (b.territory or b.home) or nil
        if home == nil or s == nil then return false end
        local maxX = home.maxX or (home.minX + home.width - 1)
        local maxY = home.maxY or (home.minY + home.height - 1)
        return (home.allFloors == true or s:getZ() == (home.z or 0))
            and s:getX() >= home.minX and s:getX() <= maxX
            and s:getY() >= home.minY and s:getY() <= maxY
    end }
end
assert(KnoxBaseManager.containsSquare(base, inside) == true, "fixture: base must contain the inside square")
assert(KnoxBaseManager.containsSquare(base, outside) == false, "fixture: base must reject the outside square")
KnoxPersistence = { getBaseResidentIds = function(id)
    assert(id == "chatterBase", "resident read must use the controller's own base id")
    return ids
end }
ISTimedActionQueue = nil
-- Callers pass decision.kind, so the parameter is the kind string.
local decision = "find_water"
local function controller(opts)
    opts = opts or {}
    local c = setmetatable({
        -- Must match the roster entry in `ids`, or the alone case would see
        -- itself as a peer.
        id = "speaker", base = base, baseId = "chatterBase",
        character = actorAt(opts.square or inside, opts.busy),
        state = "IDLE", activeDecision = opts.decision, nextNeedCallout = opts.cooldown or 0,
        companionTarget = opts.companion, groupLeader = opts.leader,
        groupMembers = opts.members, combatTarget = opts.threat,
        pendingThreatAwareness = opts.threatAwareness,
    }, C)
    return c
end
local function speaks(opts)
    spoken = {}
    current = not (opts ~= nil and opts.current == false)
    local c = controller(opts)
    c:sayNeedIfGrouped(decision, (opts ~= nil and opts.ticks) or 100)
    return #spoken, spoken[1], c
end
local count, line, speaker = speaks()
assert(count == 1, "chatter: in-base resident with a peer must speak (spoke " .. count .. ")")
assert(line == "I need water soon.", "chatter: must speak the existing need line, got " .. tostring(line))
assert(speaker.nextNeedCallout == 1900, "chatter: the existing 1800-tick cooldown must be armed, got "
    .. tostring(speaker.nextNeedCallout))
count = speaks({ cooldown = 1900, ticks = 100 })
assert(count == 0, "chatter: an armed cooldown must stay silent")
ids = { "speaker" }
count = speaks()
assert(count == 0, "chatter: a resident alone at their base must stay silent")
ids = { "speaker", "peer" }
count = speaks({ square = outside })
assert(count == 0, "chatter: a resident outside their base must stay silent")
count = speaks({ threat = {} })
assert(count == 0, "chatter: an active combat target must keep the resident silent")
count = speaks({ threatAwareness = {} })
assert(count == 0, "chatter: pending threat awareness must keep the resident silent")
count = speaks({ decision = "rest" })
assert(count == 0, "chatter: the rest decision must stay silent")
count = speaks({ decision = "sleep" })
assert(count == 0, "chatter: the sleep decision must stay silent")
count = speaks({ busy = true })
assert(count == 0, "chatter: an owning timed action must stay silent")
count = speaks({ current = false })
assert(count == 0, "chatter: a stale need must stay silent")
-- The pre-existing companion audience is untouched by this widening.
count = speaks({ square = outside, companion = {} })
assert(count == 1, "chatter: the existing companion audience must still speak outside a base")
KnoxActivityFeed, KnoxSurvivorNeeds, KnoxBaseManager, KnoxPersistence, ISTimedActionQueue =
    oldFeed, oldNeeds, oldBase, oldStore, oldQueue
