-- Hold means the order-time post, not wherever the last fight ended. A held
-- survivor walks back after displacement the way a guard re-resolves its
-- post; with no post recorded (old saves) holding still means freezing.
local C = assert(KnoxAutonomyController)
local oldCell = rawget(_G, "getCell")
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end, canStand = function() return true end }
end
getCell = function()
    return { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
end
local function actor(x)
    local a = { x = x, y = 200, z = 0 }
    function a:getCurrentSquare() return square(self.x, self.y, self.z) end
    function a:isClimbing() return false end
    function a:getCurrentStateName() return "idle" end
    function a:getCurrentActionContextStateName() return "idle" end
    function a:getCharacterActions() return { isEmpty = function() return true end } end
    function a:isDead() return false end
    return a
end
ISTimedActionQueue = { clear = function() end }
local moves = 0
local bridge = {
    moveNpc = function() moves = moves + 1 return "MOVE_STARTED" end,
    cancelNpcMove = function() end,
}
local body = actor(100)
local c = setmetatable({ id = "hold-person", character = body, bridge = bridge,
    companionOwnerId = "hold-owner", companionTarget = nil, companionOrder = "follow",
    companionFormationSlot = 1, companionPartySize = 1, state = "COMPANION_HOLD",
    nextThink = 0, nextThreatScan = 0, nextFormationRefresh = 0, formationFailureCount = 0,
    failureReasons = {}, failedThreats = {}, groupMembers = {}, counts = { failures = 0 },
    reservations = { threats = {}, items = {}, restSpots = {} } }, { __index = C })
-- Taking the hold order records the post.
c:setCompanionOrder("hold-owner", nil, "hold", 1)
assert(c.holdPost ~= nil and c.holdPost.x == 100 and c.holdPost.y == 200,
    "taking hold records the post")
-- Displacement walks back instead of adopting the battlefield.
body.x = 110
assert(c:holdPostReached() == false, "ten tiles out is not the post")
assert(c:returnToHoldPost(1000) == true and moves == 1 and c.state == "COMPANION_HOLD",
    "a displaced hold walks back to its post")
-- Arrival re-holds without another walk.
body.x = 100
assert(c:holdPostReached() == true, "the post is home again")
-- Old saves recorded no post: holding still means freezing in place.
c.holdPost = nil
body.x = 130
assert(c:holdPostReached() == true and c:returnToHoldPost(2000) == false and moves == 1,
    "no post means no walk")
-- Standing down clears the post with the order.
c:setCompanionOrder("hold-owner", nil, "follow", 1)
assert(c.holdPost == nil, "leaving hold clears the post")
rawset(_G, "getCell", oldCell)
print("Hold post PASS record=true return=true noPost=still")
