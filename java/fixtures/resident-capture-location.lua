-- Run after companion-save-event: exercise the real capture with a stale
-- offscreen ledger and an unavailable needs snapshot.
local p = KnoxPersistence
local oldSnapshot = KnoxSurvivorNeeds.snapshot
local state = p.getUnloadedSurvivalState("codec-person")
state.status = "hibernated"
state.virtualX, state.virtualY, state.virtualZ = 900, 901, 0
assert(p.setUnloadedSurvivalState("codec-person", state))
KnoxSurvivorNeeds.snapshot = function() return nil end
local saved = p.captureActiveSurvivor("codec-person")
assert(saved and p.getRecord("codec-person") == expectedRecord,
    "the live body record must be retained when needs are unavailable")
state = p.getUnloadedSurvivalState("codec-person")
assert(state.status == "loaded",
    "a captured live body must supersede the stale offscreen route")
-- Run the real startup repair, then the real activation candidate selector.
-- The engine cell is the only world boundary doubled here. The selector must
-- read the captured record, not the previous hibernated position.
loadedHook()
local oldCell = getCell
local loaded = true
local savedSquare = {getX=function() return 105 end, getY=function() return 205 end,
    getZ=function() return 0 end, canStand=function() return true end,
    haveFire=function() return false end, getMovingObjects=function() return {size=function() return 0 end} end}
local oldSquare = {getX=function() return 900 end, getY=function() return 901 end,
    getZ=function() return 0 end}
local queried = {}
getCell = function() return {getGridSquare=function(_,x,y,z)
    queried[#queried+1] = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    if x == 105 and y == 205 and z == 0 then return loaded and savedSquare or nil end
    if x == 900 and y == 901 and z == 0 then return oldSquare end
    return nil
end} end
local options = {players={}}
local candidate, reason = codecResidentPopulation.activationCandidate(
    "codec-person", KnoxJavaBridge, options)
assert(candidate ~= nil and reason == "ready" and candidate.mode == "restore"
    and candidate.square == savedSquare and candidate.record == expectedRecord,
    "startup must plan restoration at the fresh record, not stale virtual coordinates")
savedSquare.canStand = function() return false end
candidate, reason = codecResidentPopulation.activationCandidate("codec-person", KnoxJavaBridge, options)
assert(candidate == nil and reason == "saved_square_not_safe",
    "a loaded but unsafe saved square must defer")
savedSquare.canStand = function() return true end
loaded = false
queried = {}
candidate, reason = codecResidentPopulation.activationCandidate(
    "codec-person", KnoxJavaBridge, options)
assert(candidate == nil and reason == "saved_square_not_loaded"
    and #queried == 1 and queried[1] == "105,205,0",
    "an unloaded saved square must wait without probing another location")
-- Owned companion, marker tile blocked: restore beside the marker on the
-- same floor instead of deferring forever behind it.
local freshRecord = p.getRecord("codec-person")
local blockedMarker={getX=function() return 105 end,getY=function() return 205 end,
    getZ=function() return 0 end,canStand=function() return true end,
    haveFire=function() return false end,getMovingObjects=function() return {size=function() return 1 end} end}
local besideMarker={getX=function() return 106 end,getY=function() return 205 end,
    getZ=function() return 0 end,canStand=function() return true end,
    haveFire=function() return false end,getMovingObjects=function() return {size=function() return 0 end} end}
getCell = function() return {getGridSquare=function(_,x,y,z)
    if x == 105 and y == 205 and z == 0 then return blockedMarker end
    if x == 106 and y == 205 and z == 0 then return besideMarker end
    return nil end} end
local oldBridgeRelocate = KnoxJavaBridge.relocateNpcRecord
KnoxJavaBridge.relocateNpcRecord = function(_, record, x, y, z)
    assert(record == freshRecord and x == 106 and y == 205 and z == 0,
        "relocation moves the owned record to the free tile beside the marker")
    return "relocated:106,205,0"
end
local oldDutyFn, oldAffilFn = p.getSurvivorDuty, p.getSurvivorAffiliation
p.getSurvivorDuty = function(sid)
    if sid == "codec-person" then return {mode="companion", ownerId="player"} end
    return oldDutyFn(sid)
end
p.getSurvivorAffiliation = function(sid)
    if sid == "codec-person" then return {kind="player", ownerId="player"} end
    return oldAffilFn(sid)
end
candidate, reason = codecResidentPopulation.activationCandidate(
    "codec-person", KnoxJavaBridge, {players={}})
assert(candidate ~= nil and reason == "ready" and candidate.mode == "restore"
    and candidate.x == 106 and candidate.y == 205 and candidate.z == 0
    and candidate.record == "relocated:106,205,0",
    "owned blocked marker restores beside it, same floor got=" .. tostring(reason))
KnoxJavaBridge.relocateNpcRecord = oldBridgeRelocate
p.getSurvivorDuty, p.getSurvivorAffiliation = oldDutyFn, oldAffilFn
assert(p.setRecord("codec-person", freshRecord))
getCell = oldCell
KnoxSurvivorNeeds.snapshot = oldSnapshot
assert(p.captureActiveSurvivor("codec-person"))
state = p.getUnloadedSurvivalState("codec-person")
assert(state.status == "loaded" and state.virtualX == 105 and state.virtualY == 205,
    "a later successful snapshot must refresh the real coordinates")
print("Resident capture location PASS unavailable_needs=true stale_route_superseded=true")
