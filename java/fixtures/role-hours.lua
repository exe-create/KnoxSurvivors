local Catalog = assert(KnoxOrderCatalog, "order catalogue is loaded")
local Persistence = assert(KnoxPersistence, "persistence is loaded")

local valid = {
    sleep = true, work = true, patrol = true, guard = true,
    recreation = true, anything = true,
}
local roles = { "guard", "patrol", "cooking", "farming", "woodwork", "barricade",
    "hauling", "repair" }

-- The UI presents six four-hour blocks, while the saved draft stays hourly.
-- Every block must start where the previous one ended, or a click would paint
-- the wrong hours.
assert(#Catalog.scheduleBlocks == 6, "six schedule blocks are defined")
for index, block in ipairs(Catalog.scheduleBlocks) do
    assert(block.startHour == (index - 1) * 4,
        "schedule block starts on its four-hour boundary: " .. tostring(index))
    assert(type(block.label) == "string" and block.label ~= "",
        "schedule block has a label: " .. tostring(index))
end
assert(Catalog.scheduleBlocks[1].label == "Night", "first block is night")
assert(Catalog.scheduleBlocks[6].label == "Dusk", "last block is dusk")

for _, role in ipairs(roles) do
    local hours = Catalog.roleScheduleHours(role)
    assert(type(hours) == "table" and #hours == 24,
        "role hours cover twenty-four hours: " .. role)
    local work, sleep = 0, 0
    for hour = 1, 24 do
        assert(valid[hours[hour]] == true,
            "role hours use a real assignment: " .. role .. ":" .. tostring(hour))
        if hours[hour] == "work" then work = work + 1 end
        if hours[hour] == "sleep" then sleep = sleep + 1 end
    end
    assert(work > 0, "role has work hours: " .. role)
    assert(sleep > 0, "role has sleep hours: " .. role)
end

-- Guard is the night role; cooking starts before the ordinary day. These are
-- the two design beats that must not collapse into the same generic rota.
local guard = Catalog.roleScheduleHours("guard")
assert(guard[1] == "guard", "guard is on watch at midnight")
assert(guard[21] == "guard", "guard takes the dusk watch")
assert(guard[5] == "sleep", "guard sleeps after the night watch")
assert(guard[9] == "sleep", "guard has a full sleep block before work")
assert(Catalog.scheduleBlockValue(guard, 1) == "guard",
    "night block reads as guard duty")
assert(Catalog.scheduleBlockValue(guard, 2) == "sleep",
    "dawn block reads as sleep")
assert(Catalog.scheduleBlockValue(guard, 4) == "work",
    "afternoon block reads as work")
assert(Catalog.scheduleBlockValue(guard, 6) == "guard",
    "dusk block reads as guard duty")
local mixed = {}
for hour = 1, 24 do mixed[hour] = guard[hour] end
mixed[2] = "work"
assert(Catalog.scheduleBlockValue(mixed, 1) == nil,
    "a block with crossing hours is reported as mixed, not guessed")
assert(Catalog.scheduleBlockValue(guard, 0) == nil,
    "an invalid block index has no value")
assert(Catalog.scheduleBlockValue(guard, 7) == nil,
    "a block beyond the six has no value")
assert(Catalog.scheduleHoursFromBlocks({ "sleep" }) == nil,
    "an incomplete block template is refused")
assert(Catalog.scheduleHoursFromBlocks({ "sleep", "sleep", "sleep", "sleep",
    "sleep", "sleep" }) ~= nil, "a complete block template expands")
local painted = {}
for hour = 1, 24 do painted[hour] = "anything" end
assert(Catalog.setScheduleBlock(painted, 2, "work") == true,
    "block paint accepts a real block")
for hour = 5, 8 do
    assert(painted[hour] == "work", "block paint writes its four hours: " .. hour)
end
assert(painted[4] == "anything", "block paint does not leak into the prior block")
assert(painted[9] == "anything", "block paint does not leak into the next block")
assert(Catalog.setScheduleBlock(painted, 7, "work") == false,
    "block paint refuses a block beyond the six")
assert(Catalog.setScheduleBlock(nil, 1, "work") == false,
    "block paint refuses a missing draft")
local cooking = Catalog.roleScheduleHours("cooking")
assert(cooking[1] == "sleep", "cook sleeps at midnight")
assert(cooking[5] == "work", "cook starts before dawn")
assert(cooking[21] == "sleep", "cook is asleep by dusk")
assert(cooking[5] ~= guard[5], "cook and guard do not share one rota")

assert(Catalog.roleScheduleHours("auto") == nil,
    "automatic has no imposed hours")
assert(Catalog.roleScheduleHours("rest") == nil,
    "rest has no imposed work rota")
assert(Catalog.roleScheduleHours("unknown") == nil,
    "unknown roles have no template")
assert(Catalog.roleScheduleHours("Patrol Area") ~= nil,
    "legacy patrol label resolves to the patrol template")

-- Copying is a scope query over the live roster, not a second rota store.
local copyRoster = {
    { id = "source", role = "guard" },
    { id = "guard2", role = "guard" },
    { id = "cook", role = "cooking" },
    { id = "legacy", role = "Patrol Area" },
    { id = "unknown", role = "removed_role" },
}
local everyone = Catalog.scheduleCopyTargets("source", copyRoster, "all")
assert(#everyone == 4, "copy-all excludes only the source resident")
local guards = Catalog.scheduleCopyTargets("source", copyRoster, "role", "guard")
assert(#guards == 1 and guards[1] == "guard2",
    "copy-role uses the stored role and excludes the source")
local patrol = Catalog.scheduleCopyTargets("source", copyRoster, "role", "Patrol Area")
assert(#patrol == 1 and patrol[1] == "legacy",
    "copy-role resolves the legacy patrol preference")
local one = Catalog.scheduleCopyTargets("source", copyRoster, "person", "cook")
assert(#one == 1 and one[1] == "cook", "copy-person selects exactly that resident")
assert(#Catalog.scheduleCopyTargets("source", copyRoster, "person", "source") == 0,
    "copy-person never copies back to the source")
assert(#Catalog.scheduleCopyTargets("source", copyRoster, "role", "nobody") == 0,
    "copy-role with no matching residents is empty")
assert(#Catalog.scheduleCopyTargets("source", copyRoster, "bogus", "guard") == 0,
    "copy rejects an unknown scope")
assert(#Catalog.scheduleCopyTargets(nil, copyRoster, "all") == 0,
    "copy needs a source resident")

-- The draft must survive the real schedule codec; a template that cannot be
-- saved would be presentation only.
local windows = Persistence.hoursToDutyWindows(guard)
assert(type(windows) == "table" and #windows > 0,
    "guard template compresses into duty windows")
local restored = Persistence.dutyWindowsToHours(windows)
assert(restored[1] == "guard" and restored[9] == "sleep"
    and restored[17] == "work" and restored[21] == "guard",
    "guard template round-trips through the real schedule codec")