-- Companion leash (2026-11-04)
-- Drives the production Controller:withinFollowerLeash and the tuning value it
-- reads. Climb ranking lives inside the file-local evaluateThreat, which this
-- harness does not export, so it is compile-checked and native-unverified only.
local C = assert(KnoxAutonomyController, "the autonomy controller is loaded")
local R = C.TUNING.FOLLOWER_LEASH_RADIUS
assert(type(R) == "number" and R == 10, "the follower leash is ten tiles")

local function square(x, y)
    return { getX = function() return x end, getY = function() return y end }
end
local function body(x, y)
    return { getCurrentSquare = function() return square(x, y) end }
end

local leader = body(0, 0)
-- The production methods call self:followerLeaderSquare(), so the stub has to
-- share the controller's metatable rather than being a bare table.
local follower = setmetatable({ companionOrder = "follow", companionTarget = leader },
    { __index = C })
assert(C.followerLeaderSquare(follower) ~= nil, "a follower resolves the leader square")
assert(C.followerLeaderSquare({ companionOrder = "hold", companionTarget = leader }) == nil,
    "a holder has no leader leash")

-- 25 is the squared distance to a zombie five tiles from the player.
assert(C.withinFollowerLeash(follower, body(5, 0), 25) == true,
    "a fight beside the player is allowed")
assert(C.withinFollowerLeash(follower, body(40, 0), 1600) == false,
    "a fight far from the player is refused")
assert(C.withinFollowerLeash(follower, body(40, 0), 4) == true,
    "contact defence inside two tiles is never refused")
assert(C.withinFollowerLeash(setmetatable({ companionOrder = "follow" }, { __index = C }),
    body(40, 0), 1600) == true, "a follower with no leader keeps its old behaviour")
assert(C.withinFollowerLeash(setmetatable({ companionOrder = "hold", companionTarget = leader },
    { __index = C }), body(40, 0), 1600) == true, "holding is not leashed to the player")

print("companion_leash PASS radius=10 near=true far=false contact=true")
