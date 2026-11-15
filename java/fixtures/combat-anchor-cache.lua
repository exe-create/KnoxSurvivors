-- The combat leash anchor is one answer per controller tick (2026-11-05).
-- Drives the production accessor and its cache key, not a copied formula.
local C = assert(KnoxAutonomyController, "the autonomy controller is loaded")
local leader, other = { name = "leader" }, { name = "other" }

local controller = setmetatable({
    currentTicks = 10, companionOrder = "follow", companionTarget = leader,
}, { __index = C })
local calls = 0
function controller:resolvePlayerPartyAnchor(ticks)
    calls = calls + 1
    return self.companionTarget
end

assert(controller:combatAnchor() == leader and calls == 1,
    "the first threat resolves the party anchor")
assert(controller:combatAnchor() == leader and calls == 1,
    "a second threat in the same tick reuses the anchor")
controller.currentTicks = 11
assert(controller:combatAnchor() == leader and calls == 2,
    "a new tick resolves the anchor again")
controller.companionTarget = other
assert(controller:combatAnchor() == other and calls == 3,
    "a changed companion target invalidates the cache")
controller.currentTicks = 12
controller.companionOrder = "hold"
assert(controller:combatAnchor() == other and calls == 4,
    "a changed order invalidates the cache")
controller.currentTicks = nil
assert(controller:combatAnchor() == other and calls == 5,
    "without a tick there is no cache")
assert(controller:combatAnchor() == other and calls == 6,
    "without a tick every call resolves")

local group = setmetatable({ currentTicks = 20, groupLeader = leader }, { __index = C })
assert(group:combatAnchor() == leader, "a group uses its leader without the player resolver")
group.groupLeader = other
assert(group:combatAnchor() == other, "a changed group leader invalidates the cache")

print("combat_anchor_cache PASS tick=true target=true order=true no_tick=true group=true")
