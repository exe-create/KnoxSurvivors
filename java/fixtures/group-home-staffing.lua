-- P3: a group home staffs itself from its own roster when a member streams back
-- in. The real admission owner (ensureGroupBase) and the real persistence writer
-- run here; only the world around them is stubbed. A member with no body at the
-- home never gains residency, so nothing is teleported or invented.
local P = assert(rawget(_G, "KnoxPersistence"), "the real persistence owner is loaded")
local M = assert(rawget(_G, "codecGroupStaffing"), "the group-home staffing owner is extracted")
local C = assert(rawget(_G, "codecBaseStreamIn"), "the stream-in section is extracted")
local savedData = data
local savedRuntime, savedManager = rawget(_G, "KnoxSurvivorRuntime"), rawget(_G, "KnoxBaseManager")
local savedCell, savedSafehouse = rawget(_G, "getCell"), rawget(_G, "SafeHouse")
data = {}
local ids = { "p3-lead", "p3-arrived", "p3-absent" }
for _, id in ipairs(ids) do assert(P.setRecord(id, expectedRecord)) end
-- Everyone starts at the home; the group elects its own leader, and only then
-- does the fixture send one member away.
local def = { getID = function() return "p3-home" end, getX = function() return 10 end,
    getY = function() return 10 end, getX2 = function() return 16 end, getY2 = function() return 16 end,
    getW = function() return 6 end, getH = function() return 6 end,
    getRoomsNumber = function() return 3 end, getArea = function() return 36 end }
local building = { getDef = function() return def end, isResidential = function() return true end,
    hasWater = function() return true end }
local physicalObjects = { size = function() return 0 end, get = function() return nil end }
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z or 0 end,
        getObjects = function() return physicalObjects end,
        RemoveTileObject = function() error("staffing must not remove world objects") end,
        canStand = function() return true end,
        isOutside = function() return not (x >= 10 and y >= 10 and x < 16 and y < 16) end,
        getBuilding = function()
            return (x >= 10 and y >= 10 and x < 16 and y < 16) and building or nil
        end }
end
local positions = {}
local characters = {}
for _, id in ipairs(ids) do
    positions[id] = square(10, 10)
    local key = id
    characters[id] = { getCurrentSquare = function() return positions[key] end,
        isDead = function() return false end }
end
getCell = function() return { getGridSquare = function(_, x, y, z) return square(x, y, z) end } end
SafeHouse = { getSafehouseOverlapping = function() return nil end }
_G.KnoxSurvivorRuntime = { getCharacter = function(id) return characters[id] end,
    notifyDutyChanged = function() end }
_G.KnoxBaseManager = M
M.containsSquare = function(base, tile)
    return tile:getX() >= base.home.minX and tile:getX() < base.home.minX + base.home.width
        and tile:getY() >= base.home.minY and tile:getY() < base.home.minY + base.home.height
end
local group = assert(P.createTravelGroup(ids, 20))
local leaderId = assert(group.leaderId, "the group elected a leader")
local absentId = ids[3] ~= leaderId and ids[3] or ids[1]
positions[absentId] = square(44, 44)
local present = {}
for _, id in ipairs(ids) do if id ~= absentId then present[#present + 1] = id end end
assert(P.setSurvivorCreatorRecord(leaderId, { name = "Group Home Lead", profile = "household",
    settlementPolicy = "home" }))
local candidate = { buildingId = "p3-home", minX = 10, minY = 10, width = 6, height = 6,
    x = 9, y = 12, z = 0, probeX = 11, probeY = 11, probeZ = 0, score = 50 }
group.homeBuildingId = candidate.buildingId
assert(P.recordFactionBaseCandidate(group.id, candidate, 20))
local home, homeWhy = P.confirmGroupHomeBase(group.id, candidate.buildingId, characters[leaderId], 20)
assert(home ~= nil, "the fixture seats a real group home: " .. tostring(homeWhy)
    .. " leader=" .. tostring(leaderId))
assert(#P.getBaseResidentIds(home.id) == 0, "a home that has never been staffed holds no residents")
C.prepareWorkforce = function() return true, {} end
local ok, why = C.seedStreamedBase(leaderId, characters[leaderId], 20)
local seated = #P.getBaseResidentIds(home.id)
assert(seated == 2, "the home reaches roster strength from real bodies on stream-in: seated="
    .. tostring(seated) .. " roster=" .. tostring(#group.memberIds) .. " absent=" .. tostring(absentId))
for _, id in ipairs(present) do
    assert(P.isGroupBaseMember(home, id, true), "a present member holds real residency: " .. tostring(id))
end
assert(not P.isGroupBaseMember(home, absentId, true), "the absent member is not seated")
assert(P.getSurvivorDuty(absentId).mode ~= "base", "the absent member keeps its own duty")
data = savedData
_G.KnoxSurvivorRuntime, _G.KnoxBaseManager = savedRuntime, savedManager
_G.getCell, _G.SafeHouse = savedCell, savedSafehouse
assert(ok == true and why == "streamed", "the stream-in runs for the arriving member: " .. tostring(why))
print("Group home staffing PASS seated=2 roster=3 absentExcluded=true streamedStaffing=true nativeGameplay=false")
