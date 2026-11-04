local Catalog = assert(KnoxOrderCatalog, "order catalogue is loaded")
local Persistence = assert(KnoxPersistence, "persistence is loaded")
local Jobs = assert(KnoxBaseJobs, "base jobs are loaded")

local playerId = "override-player"
local residentId = "ks-override"
local home = { minX = 10, minY = 10, width = 4, height = 4 }

-- A real persisted survivor and player-owned base exercise the ownership gate
-- rather than writing the duty record directly.
assert(Persistence.setRecord(residentId, assert(expectedRecord, "encoded victim record is available")),
    "fixture survivor record is seeded")
assert(Persistence.setPlayerCompanion(residentId, playerId, "follow", 12),
    "fixture survivor becomes a player companion")
local base = assert(Persistence.createBase("player", playerId, home, 12),
    "fixture player base is created")
assert(Persistence.setPlayerBaseResident(residentId, playerId, base.id, 12),
    "fixture survivor becomes a base resident")
local rota = { { from = 0, to = 24, assignment = "sleep" } }
assert(Persistence.setBaseDutySchedule(residentId, playerId, base.id, rota, 12),
    "fixture saved rota is written through the owner")
local revisionBefore = assert(Persistence.getSurvivorDuty(residentId)).revision

-- The block window is the one boundary owner used by the override writer and
-- the Crew control. Test clear, midnight, and wrapping clock values.
local window = assert(Catalog.scheduleBlockWindow(0), "midnight has a block")
assert(window.index == 1 and window.key == "night" and window.hoursRemaining == 4,
    "midnight is the start of the Night block")
window = assert(Catalog.scheduleBlockWindow(23.5), "late evening has a block")
assert(window.index == 6 and window.key == "dusk"
    and math.abs(window.hoursRemaining - .5) < .000001,
    "the Dusk block expires at midnight")
window = assert(Catalog.scheduleBlockWindow(24), "exactly 24 wraps to midnight")
assert(window.index == 1 and window.hoursRemaining == 4,
    "24:00 is the next day's Night block start")
assert(Catalog.scheduleBlockWindow(-1) == nil,
    "a negative clock hour is not a block")

-- Setting at noon creates a guard-only block ending at 16:00. The saved rota
-- is not rewritten, and the getter expires exactly on the boundary.
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, base.id, "guard", 12
), "owner can set a temporary block override")
local override = assert(Persistence.getDutyScheduleOverride(residentId, 12),
    "override is active at its start")
assert(override.assignment == "guard" and override.block == 4
    and override.expiresAtHours == 16, "override carries guard and the noon block")
assert(Persistence.getDutyScheduleOverride(residentId, 15.999) ~= nil,
    "override is active until the next boundary")
assert(Persistence.getDutyScheduleOverride(residentId, 16) == nil,
    "override expires exactly at the next block")
local saved = assert(Persistence.getDutySchedule(residentId), "saved rota still exists")
assert(#saved == 1 and saved[1].assignment == "sleep",
    "temporary override does not rewrite the saved rota")

local before = KnoxNightShelter
KnoxNightShelter = { currentHour = function() return 12 end }
assert(Jobs.scheduleAssignment(residentId) == "guard",
    "the scheduler honors the active temporary block")
local previousClock = getGameTime
getGameTime = function() return { getWorldAgeHours = function() return 16 end } end
KnoxNightShelter = { currentHour = function() return 16 end }
assert(Jobs.scheduleAssignment(residentId) == "sleep",
    "the scheduler returns to the saved rota after the boundary")
getGameTime = previousClock
KnoxNightShelter = before

local duty = assert(Persistence.getSurvivorDuty(residentId))
assert(duty.revision == revisionBefore + 1,
    "one override write bumps the existing duty revision once")

assert(Persistence.setBaseDutyScheduleOverride(
    residentId, "other-player", base.id, "guard", 12
) == false, "another player cannot set the override")
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, "other-base", "guard", 12
) == false, "another base cannot receive the override")
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, base.id, "bogus", 12
) == false, "an unknown assignment is refused")
assert(Persistence.getDutyScheduleOverride(residentId, 12).assignment == "guard",
    "refused writes leave the active override untouched")

assert(Persistence.clearBaseDutyScheduleOverride(
    residentId, "other-player", base.id, 12
) == false, "another player cannot clear the override")
assert(Persistence.clearBaseDutyScheduleOverride(
    residentId, playerId, base.id, 12
), "the owner can clear the override")
assert(Persistence.getDutyScheduleOverride(residentId, 12) == nil,
    "cleared override is inactive")
assert(Persistence.clearBaseDutyScheduleOverride(
    residentId, playerId, base.id, 12
) == false, "an absent override cannot be cleared twice")

-- A late-evening override gets only the remaining fraction of the Dusk block;
-- the absolute world-age expiry is used by the scheduler, not a wrapped clock.
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, base.id, "guard", 23.5
), "late-evening override is accepted")
override = assert(Persistence.getDutyScheduleOverride(residentId, 23.75))
assert(override.block == 6 and override.expiresAtHours == 24,
    "late-evening override is in Dusk and expires at midnight")
assert(Persistence.getDutyScheduleOverride(residentId, 24) == nil,
    "late-evening override does not leak into Night")

-- The Night block itself still gets its own four-hour clock. 03:30 is the
-- final half hour of Night, so the same absolute expiry rule ends it at 04:00.
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, base.id, "guard", 3.5
), "Night-block override is accepted")
override = assert(Persistence.getDutyScheduleOverride(residentId, 3.75))
assert(override.block == 1 and override.expiresAtHours == 4,
    "Night-block override expires at dawn")
assert(Persistence.getDutyScheduleOverride(residentId, 4) == nil,
    "Night-block override does not leak into Dawn")

-- Leave a real active override on the graph so the B42 codec reload verifies
-- both the record shape and the scheduler read after restoration.
assert(Persistence.setBaseDutyScheduleOverride(
    residentId, playerId, base.id, "guard", 12
), "final override is written for the reload check")
function verifyScheduleOverrideReload()
    local restored = assert(Persistence.getDutyScheduleOverride(residentId, 12),
        "temporary override survives the B42 codec")
    assert(restored.assignment == "guard" and restored.expiresAtHours == 16,
        "reloaded override keeps its assignment and boundary")
    assert(Persistence.getDutySchedule(residentId)[1].assignment == "sleep",
        "reloaded saved rota is still independent")
    assert(Jobs.scheduleAssignment(residentId) == "guard",
        "scheduler still honors the override after reload")
end
