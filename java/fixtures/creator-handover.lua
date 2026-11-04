-- The creator's choices must survive the wire between the roster file and the
-- body, not just encode/decode. The pack was dropped in exactly this handover once
-- and every existing assertion still passed.
local Creator = rawget(_G, "KnoxCreator")
assert(Creator ~= nil, "creator model missing")
local prevPersistence, prevPlayer, prevTime = KnoxPersistence, getPlayer, getGameTime
local prevReader, prevWriter = getFileReader, getFileWriter

local NEWLINE = string.char(10)
local function linesOf(text)
    local result, start = {}, 1
    while true do
        local at = string.find(text, NEWLINE, start, true)
        if at == nil then
            if start <= #text then result[#result + 1] = string.sub(text, start) end
            return result
        end
        result[#result + 1] = string.sub(text, start, at - 1)
        start = at + 1
    end
end

local pendingLines, savedText, captured = nil, nil, nil
local allocated, grouped = {}, nil
local recordOk, allocateOk = true, true
KnoxPersistence = {
    allocateWorldSurvivor = function(origin)
        if origin == nil or origin.x == nil or origin.y == nil then
            return nil, "invalid_origin"
        end
        allocated[#allocated + 1] = origin
        if not allocateOk then return nil, "origin_already_used" end
        return "ks-world-" .. tostring(#allocated), {}
    end,
    setSurvivorCreatorRecord = function(id, record)
        captured = record
        if not recordOk then return false, "invalid_name" end
        return true, "set"
    end,
    createTravelGroup = function(ids) grouped = ids; return "group-1" end,
}
getPlayer = function()
    return { getSquare = function()
        return { getX = function() return 100 end, getY = function() return 200 end,
            getZ = function() return 0 end }
    end }
end
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
getFileReader = function()
    if pendingLines == nil then return nil end
    return { readLine = function() return table.remove(pendingLines, 1) end,
        close = function() end }
end
getFileWriter = function()
    return { write = function(_, text) savedText = text end, close = function() end }
end

local function roster(name)
    return Creator.encode({ { name = name, look = "police", kit = "police",
        weapon = "Base.BaseballBat", weaponId = "bat",
        profession = "base:policeofficer", pack = "medical", spawned = false } },
        { name = "Millers", faction = 3 })
end

pendingLines = linesOf(roster("Ann"))
local count, degraded = Creator.spawnPending()
assert(count == 1, "one unspawned person is allocated, got " .. tostring(count))
assert(degraded == 0, "a written record is not degraded, got " .. tostring(degraded))
assert(captured ~= nil, "the record reached the writer")
assert(captured.pack == "medical", "the pack reaches the record, got "
    .. tostring(captured.pack))
assert(captured.look == "police" and captured.kit == "police"
    and captured.weapon == "Base.BaseballBat", "look, kit and weapon reach the record")
assert(captured.faction == "military", "the faction intent reaches the record, got " .. tostring(captured.faction))
assert(captured.groupName == "Millers", "the group name reaches the record")
local resaved = Creator.decode(savedText)
assert(#resaved == 1 and resaved[1].spawned == true,
    "the roster is written back as spawned so the next start does not duplicate them")

-- A refused record still leaves a real body, so it must be counted, not hidden.
captured = nil
pendingLines = linesOf(roster("Ben"))
recordOk = false
count, degraded = Creator.spawnPending()
assert(count == 1, "the body is still allocated, got " .. tostring(count))
assert(degraded == 1, "a refused record is reported, got " .. tostring(degraded))
recordOk = true

-- A refused allocation leaves the person for the next start.
pendingLines = linesOf(roster("Cara"))
allocateOk = false
count = Creator.spawnPending()
assert(count == 0, "nothing is allocated when the origin is refused")
assert(Creator.decode(savedText)[1].spawned == false,
    "a refused allocation is retried next start, not marked done")
allocateOk = true

KnoxPersistence, getPlayer, getGameTime = prevPersistence, prevPlayer, prevTime
getFileReader, getFileWriter = prevReader, prevWriter
assert(grouped == nil, "a single created person forms no group")
print("creator_handover: fields=7 degraded=reported retry=kept")
