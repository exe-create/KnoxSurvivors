-- The radio mode is a field on the base table, so the only honest proof is a
-- real save and reload through the B42 codec. This creates its own base far from
-- anything else, sets one mode before the save, and asserts it after the reload.
local p = KnoxPersistence

local home = {
    minX = 5000, minY = 5000, width = 8, height = 8, z = 0,
    buildingId = "codec-radio-building",
}
local base, createReason = p.createBase("player", "codec-radio-owner", home, 12)
assert(base ~= nil, "a base exists for the radio fixture: " .. tostring(createReason))
radioBaseId = base.id
radioOtherBaseId = nil

local ok, writeReason = p.setBaseRadioMode(radioBaseId, "codec-radio-owner", "broadcast", 12)
assert(ok == true, "the radio mode is written before the save: " .. tostring(writeReason))

-- A second owner may not set the mode on this base: the gate is the same one
-- every base writer uses, and it must survive the reload too.
local refused, refuseReason = p.setBaseRadioMode(radioBaseId, "someone-else", "listen", 12)
assert(refused == false and refuseReason == "not_your_base",
    "another owner cannot change the radio mode")

-- An unknown mode is refused at the writer, not silently stored.
local invalid, invalidReason = p.setBaseRadioMode(radioBaseId, "codec-radio-owner", "shouting", 12)
assert(invalid == false and invalidReason == "invalid_mode",
    "an unknown mode is refused by the writer")

function verifyRadioModeReload()
    local current = KnoxPersistence
    assert(current.getBaseRadioMode(radioBaseId) == "broadcast",
        "the radio mode survives the save and reload")
    -- The second pass proves the same record again rather than assuming the
    -- first pass left it intact.
    local baseNow = current.getBase(radioBaseId)
    assert(baseNow ~= nil, "the base survives the reload")
    assert(type(baseNow.radioTower) == "table"
        and tonumber(baseNow.radioTower.changedAtHours) == 12,
        "the mode keeps the time it was set")
    assert(current.setBaseRadioMode(radioBaseId, "codec-radio-owner", "off", 13) == true,
        "a reloaded mode can be changed")
    assert(current.getBaseRadioMode(radioBaseId) == "off",
        "the changed mode reads back")
    assert(current.setBaseRadioMode(radioBaseId, "codec-radio-owner", "broadcast", 12) == true,
        "the session's mode is restored for the second pass")
end
