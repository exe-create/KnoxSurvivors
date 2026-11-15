local C = assert(KnoxAutonomyController)
local function square(x, room)
    return {getX=function() return x end, getY=function() return 0 end,
        getZ=function() return 0 end, getRoom=function() return room end,
        getBuilding=function() return nil end}
end
local current, anchorSquare = square(0, nil), square(1, {})
local c = setmetatable({state="COMPANION_FOLLOW", companionOrder="follow", id="formation-fixture",
    nextFormationRefresh=0, formationCommitUntil=200, nextThink=0,
    character={getCurrentSquare=function() return current end,
        getCurrentStateName=function() return "idle" end,
        getCurrentActionContextStateName=function() return "idle" end},
    bridge={cancelNpcMove=function() error("existing route was canceled") end}}, C)
local anchor = {}
function c:resolvePlayerPartyAnchor() return anchor, anchorSquare end
function c:findPlayerPartyFormationTarget() return current, false end
function c:updateFormationMovementPace() end
local attempts, outcome = 0, false
function c:beginCompanionFollow()
    attempts = attempts + 1
    if outcome == "recovery" then self.state="COMPANION_WAIT"; return false end
    return outcome
end
assert(c:refreshFormationFollow(100) == false and attempts == 0, "committed cross-zone route receives movement tick")
c.nextFormationRefresh=0
assert(c:refreshFormationFollow(200) == false and attempts == 1, "refused replacement preserves existing movement tick")
c.nextFormationRefresh=0; outcome=true
assert(c:refreshFormationFollow(201) == true and attempts == 2, "accepted replacement owns tick")
c.nextFormationRefresh=0; outcome="recovery"
assert(c:refreshFormationFollow(202) == true and c.state == "COMPANION_WAIT", "recovery transition owns tick")

-- An internal door or partition is still a boundary when both rooms belong
-- to the same building. Distance alone must not cancel the native route.
local building, firstRoom, secondRoom = {}, {}, {}
local cancels = 0
c.bridge.cancelNpcMove = function() cancels = cancels + 1 end
current, anchorSquare = square(0, firstRoom), square(1, secondRoom)
current.getBuilding = function() return building end
anchorSquare.getBuilding = function() return building end
local forwardBlocked, reverseBlocked, unreadable = true, false, false
current.isBlockedTo = function()
    if unreadable then error("edge unavailable") end
    return forwardBlocked
end
anchorSquare.isBlockedTo = function() return reverseBlocked end
function c:findPlayerPartyFormationTarget() return anchorSquare, false end
c.state, c.nextFormationRefresh, c.formationCommitUntil = "COMPANION_FOLLOW", 0, 400
attempts, outcome = 0, false
assert(c:refreshFormationFollow(300) == false and attempts == 0
    and c.state == "COMPANION_FOLLOW" and cancels == 0,
    "a closed internal edge keeps the committed route instead of declaring arrival")
c.nextFormationRefresh = 0
assert(c:refreshFormationFollow(400) == false and attempts == 1,
    "a closed internal edge retries through the existing follow owner after commitment")
forwardBlocked, reverseBlocked = false, true
c.nextFormationRefresh, c.formationCommitUntil = 0, 500
assert(c:refreshFormationFollow(401) == false and c.state == "COMPANION_FOLLOW",
    "the reverse side of a blocked edge also prevents arrival")
reverseBlocked, unreadable = false, true
c.nextFormationRefresh = 0
assert(c:refreshFormationFollow(402) == false and c.state == "COMPANION_FOLLOW",
    "an unreadable adjacent edge never establishes arrival")
unreadable = false
c.nextFormationRefresh = 0
assert(c:refreshFormationFollow(403) == true and c.state == "COMPANION_WAIT" and cancels == 1,
    "a clear internal arch still settles normally")
function c:findPlayerPartyFormationTarget() return current, false end
current.isBlockedTo = function() error("same-square arrival has no connecting edge") end
c.state, c.nextFormationRefresh = "COMPANION_FOLLOW", 0
assert(c:refreshFormationFollow(404) == true and c.state == "COMPANION_WAIT" and cancels == 2,
    "standing on the requested square needs no edge lookup")
