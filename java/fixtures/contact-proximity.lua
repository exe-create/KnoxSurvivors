-- Leaders never need to be seen (owner direction 2026-11-12): a follower
-- reads the live square whenever it is readable, sight or not, so going
-- around a corner or through a door no longer freezes the breadcrumb while
-- the player keeps walking. The RequireCloseContact option still gates order
-- admission; it no longer blinds followers. Drives the real
-- resolvePlayerPartyAnchor with the option ON, which is the case that used
-- to strand followers.
local C = assert(KnoxAutonomyController)
local oldSettings, oldGameTime = rawget(_G, "KnoxSettings"), rawget(_G, "getGameTime")
KnoxSettings = { requireCloseContact = function() return true end }
rawset(_G, "getGameTime", function()
    return { getWorldAgeHours = function() return 0 end }
end)

local function sq(x, y, z, extra)
    local square = { getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end }
    if extra ~= nil then
        for key, value in pairs(extra) do square[key] = value end
    end
    return square
end
local selfSq = sq(0, 10, 0)
local function control(see, playerSq, playerOpts, contact)
    local opts = playerOpts or {}
    local player
    if playerSq ~= nil then
        player = {
            getCurrentSquare = function() return playerSq end,
            isDead = function() return opts.dead == true end,
            getVehicle = function() return opts.vehicle end,
            getCurrentStateName = function() return "idle" end,
            getCurrentActionContextStateName = function() return "idle" end,
        }
        if opts.climbing then
            player.isClimbing = function() return true end
        end
    end
    return setmetatable({
        id = "contact-1",
        character = {
            getCurrentSquare = function() return selfSq end,
            CanSee = function() return see end,
        },
        companionTarget = player,
        companionOwnerId = nil,
        playerLastContact = contact,
        playerContactAnchor = nil,
        playerContactFailures = 2,
    }, { __index = C }), player
end

local seen, seenPlayer = control(true, sq(5, 10, 0))
local liveAnchor, _, liveReason = seen:resolvePlayerPartyAnchor(100)
assert(liveAnchor == seenPlayer and liveReason == nil,
    "real sight still takes the live read with the observation record")
local c, player = control(false, sq(5, 10, 0))
local anchor, square, reason = c:resolvePlayerPartyAnchor(100)
assert(anchor == player and square ~= nil and square:getX() == 5
    and reason == nil and c.playerContactFailures == 0
    and c.playerContactAnchor == nil,
    "an unseen player five tiles away is still followed live")
local far = control(false, sq(15, 10, 0))
assert(far:resolvePlayerPartyAnchor(100) ~= nil,
    "fifteen tiles and out of sight still routes instead of freezing")
local otherFloor = control(false, sq(5, 10, 1))
assert(otherFloor:resolvePlayerPartyAnchor(100) ~= nil,
    "the player upstairs is still tracked; routing owns the stairs")
local dead = control(false, sq(5, 10, 0), { dead = true })
local deadAnchor, _, deadReason = dead:resolvePlayerPartyAnchor(100)
assert(deadAnchor == nil and deadReason == "player_contact_unknown",
    "a dead player is never a live anchor")
local climbing = control(false, sq(5, 10, 0), { climbing = true })
local climbAnchor, _, climbReason = climbing:resolvePlayerPartyAnchor(100)
assert(climbAnchor == nil and climbReason == "player_traversal",
    "a climbing player holds the follow instead of routing into the climb")
local vehicle = { getCurrentSpeedKmHour = function() return 30 end }
local driving = control(false, sq(5, 10, 0), { vehicle = vehicle })
local driveAnchor, _, driveReason = driving:resolvePlayerPartyAnchor(100)
assert(driveAnchor == nil and driveReason == "player_vehicle_moving",
    "a fast-moving vehicle is not followed on foot")
-- The durable breadcrumb survives only for a genuinely unreadable square:
-- it is a fallback, not the follow path.
local oldGetCell = rawget(_G, "getCell")
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x == 20 and y == 10 and z == 0 then return sq(20, 10, 0) end
    end }
end
local saved = control(false, nil)
saved.playerLastContact = nil
local lostAnchor, _, lostReason = saved:resolvePlayerPartyAnchor(100)
assert(lostAnchor == nil and lostReason == "player_contact_unknown",
    "with no square and no contact there is nothing to route to")
local stale = control(false, nil)
stale.playerLastContact = { x = 20, y = 10, z = 0, atHours = 0, source = "observation" }
local crumbAnchor, crumbSquare, crumbReason = stale:resolvePlayerPartyAnchor(100)
assert(crumbAnchor ~= nil and crumbSquare ~= nil and crumbReason == "last_known_contact"
    and crumbAnchor.knownContact == true,
    "an unreadable square still falls back to the frozen breadcrumb")
if oldGetCell == nil then rawset(_G, "getCell", nil) else getCell = oldGetCell end

KnoxSettings = oldSettings
rawset(_G, "getGameTime", oldGameTime)
print("Contact proximity PASS leadersTrackedLive=true unreadableFallsBack=true")
