local C, D, Signals = assert(KnoxAutonomyController), assert(KnoxSurvivorDialogue), assert(KnoxOrderSignals)
local oldCell, oldTime, oldSettings = getCell, getTimestampMs, KnoxSettings
getCell = function() return nil end
local now = 10000
getTimestampMs = function() return now end
KnoxSettings = { showSurvivorSpeech = function() return true end, orderGesturesEnabled = function() return true end }
local posture, moves, recreation = 0, 0, 0
local tired = setmetatable({ id = "quiet-muser", base = {},
    character = { getCurrentSquare = function() return nil end },
    feelState = function() return { tired = 2 } end,
    beginBaseMovement = function() moves = moves + 1 return true end,
    beginBaseRecreation = function() recreation = recreation + 1 return true end,
    startRecoveryPosture = function(_, _, furniture, ambient)
        assert(furniture == false and ambient == true, "no seat uses the existing ambient ground posture")
        posture = posture + 1
    end,
}, { __index = C })
assert(tired:beginAmbientMusing(10000) and posture == 1 and moves == 0 and recreation == 0,
    "a tired muser reaches the real quiet rest owner instead of walking")
assert(not tired:beginAmbientMusing(10001) and posture == 1,
    "the musing owner respects its existing next-musing window")
tired.combatTarget = {}
assert(not tired:beginAmbientMusing(20000), "a combat target prevents ambient musing")

local emotes = {}
local actor = { getCharacterActions = function() return { isEmpty = function() return true end } end,
    playEmote = function(_, emote) emotes[#emotes + 1] = emote end }
local delivered = function() return true end
for i, row in ipairs({ { "base_greet", "wavehi" }, { "base_social", "yes" },
    { "cant_lift", "thumbsdown" }, { "player_attack_warning", "stop" } }) do
    now = now + 4000
    local id = "gesture-" .. i
    local before = #emotes
    assert(D.sayLines(actor, id, row[1], { "fixture line" }, now, 3000, delivered))
    assert(#emotes == before + 1 and emotes[#emotes] == row[2],
        "accepted contextual speech plays its existing gesture")
    assert(not D.sayLines(actor, id, row[1], { "fixture line" }, now + 1, 3000, delivered)
        and #emotes == before + 1, "a dialogue cooldown suppresses the gesture too")
end
local before = #emotes
now = now + 4000
assert(not D.sayLines(actor, "gesture-refused", "base_greet", { "fixture line" }, now, 3000,
    function() return false end) and #emotes == before,
    "failed speech delivery never plays a gesture")
assert(not Signals.dialogue(actor, "unmapped-fixture"), "unmapped speech invents no gesture")
actor.isAiming = function() return true end
assert(not Signals.dialogue(actor, "player_attack_warning") and #emotes == before,
    "a warning does not interrupt native aiming")
getCell, getTimestampMs, KnoxSettings = oldCell, oldTime, oldSettings
print("Seated musing PASS realRest=true quiet=true cooldown=true combat=false contextualEmotes=true voiceGated=true aimingPreserved=true nativeGameplay=false")
