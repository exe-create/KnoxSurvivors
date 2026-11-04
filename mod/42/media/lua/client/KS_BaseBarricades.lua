require "TimedActions/ISBarricadeAction"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"
pcall(function() require "KS_DebugLog" end)

local Barricades = rawget(_G, "KnoxBaseBarricades") or {}
_G.KnoxBaseBarricades = Barricades

-- Build 42's barricade action accepts the native hammer tag, not every item
-- that happens to look like a hammer or can be used as a blunt weapon. Keep a
-- small compatibility fallback only for the vanilla tagged tools, because the
-- ItemType/ItemTag enum is not present in early test harnesses.
local FALLBACK_HAMMER_TYPES = {
    ["Base.Hammer"] = true,
    ["Base.BallPeenHammer"] = true,
    ["Base.HammerForged"] = true,
    ["Base.BallPeenHammerForged"] = true,
    ["Base.HammerStone"] = true,
}

local function fullType(item)
    return item ~= nil and item.getFullType ~= nil
        and tostring(item:getFullType() or "") or ""
end

local function nativeHammerTag()
    -- B42 order matters: ItemTag.HAMMER is the live tag system (used by the
    -- build menu, moveables and farming). ItemType.HAMMER is a stale B41
    -- reference that resolves nil, which is exactly why the vanilla action
    -- gate below had to be shimmed.
    if ItemTag ~= nil and ItemTag.HAMMER ~= nil then return ItemTag.HAMMER end
    if ItemType ~= nil and ItemType.HAMMER ~= nil then return ItemType.HAMMER end
    return nil
end

-- Live-proven root cause (2026-09-21 trace): vanilla ISBarricadeAction
-- validates `hasEquippedTag(ItemType.HAMMER)`, but ItemType.HAMMER is nil in
-- Build 42 while the equipped hammer carries ItemTag.HAMMER. Every other
-- vanilla caller (build menu, moveables, farming) uses ItemTag.HAMMER, and
-- players barricade through the build system, so the old timed action path
-- can never validate for anyone. This subclass keeps the entire vanilla
-- action (anim, duration, plank/nail consumption, XP, net sync) and repairs
-- only the one stale tag lookup. Test harnesses without derive() fall back
-- to the injected mock action untouched.
local function barricadeActionClass()
    if rawget(_G, "KnoxBarricadeAction") ~= nil then
        return _G.KnoxBarricadeAction
    end
    if ISBarricadeAction == nil or ISBarricadeAction.derive == nil then
        return ISBarricadeAction
    end
    local fixed = ISBarricadeAction:derive("KnoxBarricadeAction")
    function fixed:isValid()
        if not instanceof(self.item, "BarricadeAble")
            or self.item:getObjectIndex() == -1 then
            return false
        end
        local barricade = self.item:getBarricadeForCharacter(self.character)
        if self.isMetal then
            if barricade then
                return false
            end
            if not self.character:hasEquipped("BlowTorch")
                or not self.character:hasEquipped("SheetMetal") then
                return false
            end
        elseif self.isMetalBar then
            if barricade then
                return false
            end
            if not self.character:hasEquipped("BlowTorch")
                or not self.character:hasEquipped("MetalBar") then
                return false
            end
            if self.character:getInventory():getItemCount("Base.MetalBar", true) < 3 then
                return false
            end
        else
            if barricade and not barricade:canAddPlank() then
                return false
            end
            local hammerTag = ItemTag ~= nil and ItemTag.HAMMER or nil
            if hammerTag == nil and ItemType ~= nil then
                hammerTag = ItemType.HAMMER
            end
            if hammerTag == nil or not self.character:hasEquippedTag(hammerTag) then
                return false
            end
            if not self.character:hasEquipped("Plank") then
                return false
            end
            if self.character:getInventory():getItemCount("Base.Nails", true) < 2 then
                return false
            end
        end
        if self.isStarted then
            if instanceof(self.item, "IsoDoor")
                or (instanceof(self.item, "IsoThumpable") and self.item:isDoor()) then
                if self.item:IsOpen() then
                    return false
                end
            end
        end
        return true
    end
    _G.KnoxBarricadeAction = fixed
    return fixed
end

local function isNativeHammer(item)
    if item == nil then return false end
    local tag = nativeHammerTag()
    if tag ~= nil and item.hasTag ~= nil then
        local ok, tagged = pcall(item.hasTag, item, tag)
        if ok then return tagged == true end
    end
    return FALLBACK_HAMMER_TYPES[fullType(item)] == true
end

local function walkItems(container, visitor)
    if container == nil or container.getItems == nil then
        return
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item)
        if item ~= nil and item.IsInventoryContainer ~= nil
            and item:IsInventoryContainer() then
            walkItems(item:getInventory(), visitor)
        end
    end
end

local function findItem(character, predicate)
    local found = nil
    walkItems(character ~= nil and character:getInventory() or nil, function(item)
        if found == nil and predicate(item) then
            found = item
        end
    end)
    return found
end

function Barricades.findHammer(character, base)
    local function usableHammer(item)
        if isNativeHammer(item) then
            return item.isBroken == nil or not item:isBroken()
        end
        return false
    end
    local found = findItem(character, usableHammer)
    local storage = rawget(_G, "KnoxBaseStorage")
    if found == nil and base ~= nil and storage ~= nil and storage.findItemType ~= nil then
        local _, stored = storage.findItemType(base, usableHammer)
        found = stored
    end
    return found
end

function Barricades.findPlank(character)
    return findItem(character, function(item)
        return fullType(item) == "Base.Plank"
    end)
end

function Barricades.canPrepare(character, base)
    if character == nil or character.getInventory == nil then
        return false
    end
    -- Discovery may admit free-resource jobs before any stock exists. Execution
    -- still requires the real items supplied after the task is claimed.
    local settings = rawget(_G, "KnoxSettings")
    if base ~= nil and settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() then return true end
    local hammer = Barricades.findHammer(character, base)
    if hammer == nil then return false end
    local storage = rawget(_G, "KnoxBaseStorage")
    if base ~= nil and storage ~= nil and storage.requirementsAvailable ~= nil then
        local hammerType = hammer:getFullType()
        return storage.requirementsAvailable(base, character, {
            items = { [hammerType] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 },
            itemRules = { [hammerType] = { usable = true } },
        })
    end
    local inventory = character:getInventory()
    return Barricades.findHammer(character) ~= nil
        and Barricades.findPlank(character) ~= nil
        and inventory:getItemCount("Base.Nails", true) >= 2
end

local function isBarricadeAble(object)
    if object == nil or object.getBarricadeForCharacter == nil then
        return false
    end
    if instanceof ~= nil then
        local success, result = pcall(function()
            return instanceof(object, "BarricadeAble")
        end)
        if success and not result then
            return false
        end
    end
    if object.isBarricadeAllowed ~= nil then
        local success, result = pcall(function()
            return object:isBarricadeAllowed()
        end)
        if success and result == false then
            return false
        end
    end
    return true
end

local function isOpen(object)
    if object == nil or object.IsOpen == nil then
        return false
    end
    local success, result = pcall(function() return object:IsOpen() end)
    return success and result == true
end

local function targetId(base, object, square)
    return "barricade:" .. tostring(base.id) .. ":"
        .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square:getZ()) .. ":" .. tostring(object:getObjectIndex())
end

local function targetFromObject(base, object, square)
    local spriteName = ""
    if object ~= nil and object.getSprite ~= nil then
        local ok, sprite = pcall(function() return object:getSprite() end)
        if ok and sprite ~= nil and sprite.getName ~= nil then
            local named, name = pcall(function() return sprite:getName() end)
            if named then spriteName = tostring(name or "") end
        end
    end
    return {
        id = targetId(base, object, square),
        auto = true,
        zoneType = "barricade",
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = object:getObjectIndex(),
        spriteName = spriteName,
    }
end

local function isDoor(object)
    if object == nil then return false end
    if instanceof ~= nil then
        local success, result = pcall(function() return instanceof(object, "IsoDoor") end)
        if success and result == true then return true end
        local thumpable, isThumpable = pcall(function()
            return instanceof(object, "IsoThumpable")
        end)
        if thumpable and isThumpable == true and object.isDoor ~= nil then
            local isDoorObject, door = pcall(function() return object:isDoor() end)
            if isDoorObject and door == true then return true end
        end
    end
    -- Keep target discovery fail-closed in early/modded load orders where the
    -- global instanceof helper is not ready but the native door predicate is.
    if object.isDoor ~= nil then
        local isDoorObject, door = pcall(function() return object:isDoor() end)
        return isDoorObject and door == true
    end
    return false
end

local function targetNeedsBarricade(object, character)
    if not isBarricadeAble(object) or isOpen(object) then
        return false
    end
    local success, barricade = pcall(function()
        return object:getBarricadeForCharacter(character)
    end)
    if not success then
        return false
    end
    return barricade == nil or barricade:canAddPlank()
end

-- The entrance invariant reads native room identity from loaded squares. It
-- does not build a room graph: a room's own squares and the wall objects next
-- to them answer which openings serve that room. An unreadable room fails
-- closed so a missing native reader cannot become permission to seal an exit.
local KEEP_OPEN_KEY = "KnoxBarricadeKeepOpen"
local MAX_ROOM_OPENINGS = 128

function Barricades.isKeepOpen(object)
    if object == nil or object.getModData == nil then return false end
    local ok, data = pcall(function() return object:getModData() end)
    return ok and type(data) == "table" and data[KEEP_OPEN_KEY] == true
end

function Barricades.setKeepOpen(object, keep)
    if object == nil or object.getModData == nil then return false end
    local ok, data = pcall(function() return object:getModData() end)
    if not ok or type(data) ~= "table" then return false end
    data[KEEP_OPEN_KEY] = keep == true or nil
    return true
end

function Barricades.canKeepOpen(object)
    return object ~= nil and (isDoor(object) or isBarricadeAble(object))
end

local function barricadePlanksOf(object, character)
    if object == nil or object.getBarricadeForCharacter == nil then return nil end
    local read, barricade = pcall(function()
        return object:getBarricadeForCharacter(character)
    end)
    if not read then return nil end
    if barricade == nil then return 0 end
    if barricade.getNumPlanks == nil then return nil end
    local counted, planks = pcall(function() return barricade:getNumPlanks() end)
    if not counted then return nil end
    return tonumber(planks) or 0
end

local function openingUsable(object, character)
    if object == nil then return false end
    if isOpen(object) then return true end
    -- A plain door with no barricade API is still a usable door. A window
    -- whose barricade state cannot be read is not proven usable.
    if object.getBarricadeForCharacter == nil then return true end
    return barricadePlanksOf(object, character) == 0
end

local OUTSIDE_STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- A wall opening faces the street when a *loaded* neighbour of its own square
-- has no room. An unloaded neighbour proves nothing, so it is never read as
-- outside: the flag stays false and the finder keeps its scan order. This is
-- the only place the side of an opening is decided.
local function openingFacesOutside(square)
    if square == nil or square.getX == nil or square.getY == nil
        or square.getZ == nil then return false end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or cell.getGridSquare == nil then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for _, step in ipairs(OUTSIDE_STEPS) do
        local ok, neighbour = pcall(function()
            return cell:getGridSquare(x + step[1], y + step[2], z)
        end)
        if ok and neighbour ~= nil and neighbour.getRoom ~= nil then
            local read, room = pcall(function() return neighbour:getRoom() end)
            if read and room == nil then return true end
        end
    end
    return false
end

Barricades.openingFacesOutside = openingFacesOutside

-- Exterior links first: the face a raider reaches is boarded before an
-- interior-to-interior opening. Pure ordering of the same work list, so the
-- entrance invariant's budget and reservations are untouched.
function Barricades.orderTargets(found, limit)
    if type(found) ~= "table" then return found end
    for index, target in ipairs(found) do
        target.scanOrder = index
    end
    table.sort(found, function(first, second)
        local firstOutside = first.exterior == true
        local secondOutside = second.exterior == true
        if firstOutside ~= secondOutside then return firstOutside end
        return (first.scanOrder or 0) < (second.scanOrder or 0)
    end)
    local keep = tonumber(limit) or #found
    while #found > keep do table.remove(found) end
    for _, target in ipairs(found) do target.scanOrder = nil end
    return found
end

local function roomKeyOf(room)
    if room == nil then return nil end
    if room.getRoomDef ~= nil then
        local read, definition = pcall(function() return room:getRoomDef() end)
        if read and definition ~= nil and definition.getID ~= nil then
            local identified, id = pcall(function() return definition:getID() end)
            if identified and id ~= nil then return "room:" .. tostring(id) end
        end
    end
    return room
end

local function roomsServedBy(square)
    local rooms, keys = {}, {}
    if square == nil then return rooms, keys end
    local cell = getCell ~= nil and getCell() or nil
    local function add(candidate)
        if candidate == nil or candidate.getRoom == nil then return end
        local read, room = pcall(function() return candidate:getRoom() end)
        if not read or room == nil then return end
        local key = roomKeyOf(room)
        if key ~= nil and keys[key] == nil then
            keys[key] = true
            rooms[#rooms + 1] = room
        end
    end
    add(square)
    if cell ~= nil and square.getX ~= nil and square.getY ~= nil
        and square.getZ ~= nil then
        local read, x, y, z = pcall(function()
            return square:getX(), square:getY(), square:getZ()
        end)
        if read then
            for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local found, neighbor = pcall(function()
                    return cell:getGridSquare(x + offset[1], y + offset[2], z)
                end)
                if found then add(neighbor) end
            end
        end
    end
    return rooms, keys
end

local function roomAudit(room, character, cache)
    local key = roomKeyOf(room)
    if cache ~= nil and key ~= nil and cache[key] ~= nil then
        return cache[key], nil
    end
    if room == nil or room.getSquares == nil then
        return nil, "entrance_unverified"
    end
    local listed, squares = pcall(function() return room:getSquares() end)
    if not listed or squares == nil or squares.size == nil or squares.get == nil then
        return nil, "entrance_unverified"
    end
    local counted, size = pcall(function() return squares:size() end)
    if not counted or tonumber(size) == nil then return nil, "entrance_unverified" end
    local result = { usableCount = 0, usable = {}, openings = {},
        noWayOut = false, overflow = false }
    local seen = {}
    local cell = getCell ~= nil and getCell() or nil
    local function consider(openingSquare)
        if openingSquare == nil or openingSquare.getObjects == nil then return end
        local objects = openingSquare:getObjects()
        if objects == nil or objects.size == nil or objects.get == nil then return end
        local sized, count = pcall(function() return objects:size() end)
        if not sized or tonumber(count) == nil then return end
        for index = 0, count - 1 do
            local object = objects:get(index)
            if object ~= nil and seen[object] == nil
                and (isDoor(object) or isBarricadeAble(object)) then
                seen[object] = true
                if #result.openings >= MAX_ROOM_OPENINGS then
                    result.overflow = true
                    return
                end
                result.openings[#result.openings + 1] = object
                if openingUsable(object, character) then
                    result.usableCount = result.usableCount + 1
                    result.usable[object] = true
                end
            end
        end
    end
    for index = 0, size - 1 do
        local roomSquare = squares:get(index)
        if roomSquare ~= nil then
            consider(roomSquare)
            if cell ~= nil and roomSquare.getX ~= nil and roomSquare.getY ~= nil
                and roomSquare.getZ ~= nil then
                local read, x, y, z = pcall(function()
                    return roomSquare:getX(), roomSquare:getY(), roomSquare:getZ()
                end)
                if read then
                    for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local found, neighbor = pcall(function()
                            return cell:getGridSquare(x + offset[1], y + offset[2], z)
                        end)
                        if found then consider(neighbor) end
                    end
                end
            end
        end
    end
    if result.overflow then return nil, "room_audit_too_large" end
    result.noWayOut = result.usableCount == 0
    if cache ~= nil and key ~= nil then cache[key] = result end
    return result, nil
end

-- A candidate opening is reserved when it is the only usable opening of any
-- native room it serves, when that room already has no usable opening, or when
-- the player marked it to stay clear. Upper-floor windows are exempt from the
-- ground-floor audit, matching the design's stair/balcony rule.
function Barricades.entranceReserved(base, object, square, character, cache)
    if object == nil or square == nil then return false, "entrance_unverified", nil, false end
    if Barricades.isKeepOpen(object) then return true, "keep_open", nil, true end
    local groundZ = tonumber(base ~= nil and base.home ~= nil and base.home.z or 0) or 0
    local squareZ = nil
    if square.getZ ~= nil then
        local read, value = pcall(function() return square:getZ() end)
        if read then squareZ = tonumber(value) end
    end
    if squareZ ~= nil and squareZ ~= groundZ then return false, nil, nil, false end
    local rooms = roomsServedBy(square)
    if #rooms == 0 then return false, "entrance_unverified", nil, false end
    local budget, candidateUsable = nil, false
    for _, room in ipairs(rooms) do
        local audit, reason = roomAudit(room, character, cache)
        if audit == nil then return false, reason or "entrance_unverified", nil, false end
        if budget == nil or audit.usableCount < budget then budget = audit.usableCount end
        if audit.usable[object] == true then candidateUsable = true end
        if audit.noWayOut then return true, "no_way_out", 0, false end
        if audit.usable[object] == true and audit.usableCount <= 1 then
            return true, "only_usable_exit", audit.usableCount, true
        end
    end
    return false, nil, budget, candidateUsable
end

function Barricades.pendingWorkRooms(base)
    local pending = {}
    if base == nil or type(base.tasks) ~= "table" then return pending end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return pending end
    for _, task in pairs(base.tasks) do
        if task ~= nil and task.type == "barricade"
            and (task.state == "queued" or task.state == "claimed") then
            local target = task.target
            if target ~= nil then
                local targetSquare = cell:getGridSquare(
                    tonumber(target.x) or 0, tonumber(target.y) or 0,
                    tonumber(target.z) or 0)
                if targetSquare ~= nil then
                    local _, keys = roomsServedBy(targetSquare)
                    for key in pairs(keys) do pending[key] = true end
                end
            end
        end
    end
    return pending
end

-- A window with planks already on it is the work in progress, so it is
-- finished before an untouched one is started. Reading the barricade is the
-- same native query the completion check uses.
local function planksOn(object, character)
    if object == nil or object.getBarricadeForCharacter == nil then return 0 end
    local ok, barricade = pcall(function()
        return object:getBarricadeForCharacter(character)
    end)
    if not ok or barricade == nil or barricade.getNumPlanks == nil then return 0 end
    local counted, planks = pcall(function() return barricade:getNumPlanks() end)
    return counted and tonumber(planks) or 0
end

function Barricades.findTarget(base, character, eligible)
    local territory = base ~= nil and (base.territory or base.home) or nil
    local cell = getCell ~= nil and getCell() or nil
    if territory == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local minX = tonumber(territory.minX) or 0
    local minY = tonumber(territory.minY) or 0
    local maxX = tonumber(territory.maxX)
        or minX + (tonumber(territory.width) or 1) - 1
    local maxY = tonumber(territory.maxY)
        or minY + (tonumber(territory.height) or 1) - 1
    -- Work scans are bounded per decision so a player-drawn large territory
    -- cannot turn a normal autonomy tick into a full-map object search.
    maxX = math.min(maxX, minX + 96)
    maxY = math.min(maxY, minY + 96)
    local startZ = tonumber((base.home or {}).z) or 0
    local pendingRooms = Barricades.pendingWorkRooms(base)
    local auditCache = {}
    local lastReason = nil
    local pending = nil
    for z = startZ, startZ + 3 do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                if square ~= nil and square.getObjects ~= nil then
                    local objects = square:getObjects()
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        -- Automatic defense boards windows only. Leaving doors
                        -- free preserves a stable route for residents, supply
                        -- runs, corpse carriers, and the player.
                        if not isDoor(object) and targetNeedsBarricade(object, character) then
                            local _, roomKeys = roomsServedBy(square)
                            local busy = false
                            for key in pairs(roomKeys) do
                                if pendingRooms[key] then busy = true; break end
                            end
                            if busy then
                                lastReason = "barricade_room_busy"
                            else
                                local reserved, why = Barricades.entranceReserved(
                                    base, object, square, character, auditCache)
                                if reserved then
                                    lastReason = why or "only_usable_exit"
                                elseif why ~= nil then
                                    lastReason = why
                                else
                                    local target = targetFromObject(base, object, square)
                                    if eligible == nil or eligible(target) then
                                        -- Finish a started window before opening
                                        -- another: one board on each of six
                                        -- windows is worse than two finished.
                                        if planksOn(object, character) > 0 then
                                            return target, "found"
                                        end
                                        if pending == nil then pending = target end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if pending ~= nil then return pending, "found" end
    return nil, lastReason or "no_unbarricaded_window"
end

local function buildingKeyOf(square)
    if square == nil or square.getBuilding == nil then
        return nil
    end
    local success, building = pcall(function() return square:getBuilding() end)
    if not success or building == nil or building.getDef == nil then
        return nil
    end
    local okDef, definition = pcall(function() return building:getDef() end)
    if not okDef or definition == nil or definition.getID == nil then
        return nil
    end
    local okId, id = pcall(function() return definition:getID() end)
    return okId and tostring(id) or nil
end

-- All unbarricaded windows belonging to one building. Doors are skipped:
-- barricade orders board windows so residents can still use doors.
function Barricades.findTargetsInBuilding(base, building, character, limit)
    local found = {}
    if base == nil or building == nil then
        return found, "missing_building"
    end
    local territory = base.territory or base.home
    local cell = getCell ~= nil and getCell() or nil
    if territory == nil or cell == nil then
        return found, "base_or_cell_unavailable"
    end
    local wanted = buildingKeyOf(building.getSquare ~= nil
        and building:getSquare() or building)
    if wanted == nil then
        local square = building.getX ~= nil and cell:getGridSquare(
            building:getX(), building:getY(), building:getZ() or 0) or nil
        wanted = buildingKeyOf(square)
    end
    if wanted == nil then
        return found, "building_unavailable"
    end
    local minX = tonumber(territory.minX) or 0
    local minY = tonumber(territory.minY) or 0
    local maxX = tonumber(territory.maxX)
        or minX + (tonumber(territory.width) or 1) - 1
    local maxY = tonumber(territory.maxY)
        or minY + (tonumber(territory.height) or 1) - 1
    maxX = math.min(maxX, minX + 96)
    maxY = math.min(maxY, minY + 96)
    local startZ = tonumber((base.home or {}).z) or 0
    local maxTargets = math.max(1, tonumber(limit) or 24)
    local pendingRooms = Barricades.pendingWorkRooms(base)
    local plannedCounts, auditCache = {}, {}
    local blockedReason = nil
    for z = startZ, startZ + 3 do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                if square ~= nil and square.getObjects ~= nil
                    and buildingKeyOf(square) == wanted then
                    local objects = square:getObjects()
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        if targetNeedsBarricade(object, character)
                            and not isDoor(object) then
                            local _, roomKeys = roomsServedBy(square)
                            local busy = false
                            for key in pairs(roomKeys) do
                                if pendingRooms[key] then
                                    busy = true; blockedReason = "barricade_room_busy"; break
                                end
                            end
                            if not busy then
                                local reserved, why, budget, candidateUsable = Barricades.entranceReserved(
                                    base, object, square, character, auditCache)
                                if reserved then
                                    blockedReason = why or "only_usable_exit"
                                elseif why ~= nil then
                                    blockedReason = why
                                else
                                    local allowed = true
                                    if candidateUsable and budget ~= nil then
                                        for key in pairs(roomKeys) do
                                            if (plannedCounts[key] or 0) >= budget - 1 then
                                                allowed = false
                                                blockedReason = "barricade_room_busy"
                                                break
                                            end
                                        end
                                    end
                                    if allowed then
                                        local target = targetFromObject(base, object, square)
                                        target.exterior = openingFacesOutside(square)
                                        found[#found + 1] = target
                                        for key in pairs(roomKeys) do
                                            plannedCounts[key] = (plannedCounts[key] or 0) + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    Barricades.orderTargets(found, maxTargets)
    return found, #found > 0 and "found" or (blockedReason or "no_unbarricaded_window")
end

local function spriteNameOf(object)
    if object == nil or object.getSprite == nil then return "" end
    local ok, sprite = pcall(function() return object:getSprite() end)
    if not ok or sprite == nil or sprite.getName == nil then return "" end
    local named, name = pcall(function() return sprite:getName() end)
    return named and tostring(name or "") or ""
end

local function resolvedObject(square, target, character, requireWork)
    if square == nil or square.getObjects == nil then return nil end
    local objects = square:getObjects()
    local fallback, fallbackCount = nil, 0
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local suitable = object ~= nil and not isDoor(object)
            and isBarricadeAble(object) and not isOpen(object)
        if suitable then
            local matchesIndex = object:getObjectIndex() == tonumber(target.objectIndex)
            local matchesSprite = target.spriteName ~= nil and target.spriteName ~= ""
                and spriteNameOf(object) == target.spriteName
            if matchesIndex or matchesSprite then
                if not requireWork or targetNeedsBarricade(object, character) then return object end
                -- Matched the exact opening but it no longer needs work
                -- (fully barricaded). Return nil so resolveTarget reports
                -- target_no_longer_valid and callers can take the
                -- already-secured/retarget path instead of treating a
                -- completed window as still workable.
                return nil
            end
            if targetNeedsBarricade(object, character) then
                fallback, fallbackCount = object, fallbackCount + 1
            end
        end
    end
    -- Streamed-square object indexes are not stable. A sole eligible opening
    -- is an unambiguous recovery; never guess on a square with two windows.
    if requireWork and fallbackCount == 1 then return fallback end
    return nil
end

function Barricades.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    if square == nil or square.getObjects == nil then
        return nil, "target_unloaded"
    end
    local object = resolvedObject(square, target, character, true)
    if object ~= nil then
        local reserved, why = Barricades.entranceReserved(
            base, object, square, character, nil)
        if reserved then return nil, why or "only_usable_exit" end
        if why ~= nil then return nil, why end
        return { object = object, square = square }, "resolved"
    end
    return nil, "target_no_longer_valid"
end

-- Another resident or the player may secure this exact window while the
-- claimant is fetching supplies. That fulfills the task; it is not a blocked
-- route or a reason to retry the same opening.
function Barricades.isTargetComplete(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then return false end
    local square = cell:getGridSquare(tonumber(target.x) or 0,
        tonumber(target.y) or 0, tonumber(target.z) or 0)
    local object = resolvedObject(square, target, character, false)
    if object == nil or object.getBarricadeForCharacter == nil then return false end
    local ok, barricade = pcall(function() return object:getBarricadeForCharacter(character) end)
    if not ok or barricade == nil or barricade.getNumPlanks == nil then return false end
    local counted, planks = pcall(function() return barricade:getNumPlanks() end)
    return counted and (tonumber(planks) or 0) > 0
end

function Barricades.isTargetValid(target, character)
    if target == nil or target.object == nil or target.square == nil then
        return false
    end
    local ok, index = pcall(function()
        return target.object:getObjectIndex()
    end)
    return ok and tonumber(index) ~= nil and tonumber(index) >= 0
        and targetNeedsBarricade(target.object, character)
end

function Barricades.approachResolved(resolved, character)
    if not Barricades.isTargetValid(resolved, character) then
        return nil, "target_no_longer_valid"
    end
    if AdjacentFreeTileFinder == nil
        or AdjacentFreeTileFinder.FindWindowOrDoor == nil then
        return nil, "window_approach_api_unavailable"
    end
    local ok, approach = pcall(function()
        return AdjacentFreeTileFinder.FindWindowOrDoor(
            resolved.square,
            resolved.object,
            character
        )
    end)
    if not ok or approach == nil then
        return nil, ok and "window_approach_unavailable"
            or ("window_approach_error:" .. tostring(approach))
    end
    return approach, "resolved"
end

-- Use the same side-aware destination as vanilla's
-- luautils.walkAdjWindowOrDoor. The window's own square can be standable while
-- still being separated from the worker by its wall edge; routing directly to
-- that square ends in FailedStuck and the action never starts.
function Barricades.approachSquare(base, target, character)
    local resolved, reason = Barricades.resolveTarget(base, target, character)
    if resolved == nil then return nil, reason end
    return Barricades.approachResolved(resolved, character)
end

local function diag(event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("barricade", "queue", event, details) end)
    end
end

local function charPos(character)
    local ok, square = pcall(function() return character ~= nil and character:getCurrentSquare() or nil end)
    if not ok or square == nil then return nil end
    local okX, x, y, z = pcall(function() return square:getX(), square:getY(), square:getZ() end)
    if not okX then return nil end
    return { x = x, y = y, z = z }
end

function Barricades.queueAction(character, target, base)
    if character == nil or target == nil or target.object == nil then
        diag("missing_target", nil)
        return nil, "missing_barricade_target"
    end
    local square = nil
    if target.object.getSquare ~= nil then
        local read, value = pcall(function() return target.object:getSquare() end)
        if read then square = value end
    end
    if square == nil and getCell ~= nil and getCell() ~= nil then
        square = getCell():getGridSquare(tonumber(target.x) or 0,
            tonumber(target.y) or 0, tonumber(target.z) or 0)
    end
    if square ~= nil then
        local reserved, why = Barricades.entranceReserved(
            base, target.object, square, character, nil)
        if reserved or why ~= nil then
            diag("entrance_reserved", { reason = why or "only_usable_exit" })
            return nil, why or "only_usable_exit"
        end
    end
    if not Barricades.canPrepare(character, base) then
        diag("missing_materials", nil)
        return nil, "missing_hammer_plank_or_nails"
    end
    -- Execution equips carried items only: the supply trip delivers stored
    -- materials into inventory first, and native actions cannot use items
    -- still sitting in a container.
    local hammer = Barricades.findHammer(character)
    local plank = Barricades.findPlank(character)
    if hammer == nil or plank == nil then
        diag("missing_carried", { hammer = hammer ~= nil, plank = plank ~= nil })
        return nil, "missing_carried_hammer_or_plank"
    end
    local inventory = character:getInventory()
    local nailCount = nil
    if inventory ~= nil and inventory.getItemCount ~= nil then
        local okCount, counted = pcall(function() return inventory:getItemCount("Base.Nails", true) end)
        if okCount then nailCount = tonumber(counted) or 0 end
    end
    if inventory == nil or (nailCount or 0) < 2 then
        diag("missing_nails", { nails = nailCount })
        return nil, "missing_carried_nails"
    end
    character:setPrimaryHandItem(hammer)
    character:setSecondaryHandItem(plank)
    -- The action validates the equipped item tags, not merely the presence
    -- of matching items somewhere in the inventory. Check the action after
    -- equipping so a worker cannot walk to a window, silently reject the
    -- action, and immediately claim another target. Uses the Knox shim
    -- class (stale ItemType.HAMMER reference repaired); vanilla animation,
    -- consumption, XP and net sync are inherited unchanged.
    local actionClass = barricadeActionClass()
    if actionClass == nil or actionClass.new == nil then
        diag("action_unavailable", nil)
        return nil, "barricade_action_unavailable"
    end
    local action = actionClass:new(character, target.object, false, false)
    if action == nil or action.isValid == nil then
        diag("action_unavailable", nil)
        return nil, "barricade_action_unavailable"
    end
    local valid, accepted = pcall(function() return action:isValid() end)
    if not valid or accepted ~= true then
        -- valid==false means isValid THREW: accepted holds the exception
        -- text. Step-trace each vanilla gate with vanilla-exact syntax so
        -- the next run names the throwing line instead of just failing.
        local trace = {}
        local function step(name, fn)
            local ok, value = pcall(fn)
            trace[#trace + 1] = name .. "=" .. (ok and tostring(value) or ("ERR:" .. tostring(value)))
        end
        step("able", function() return instanceof(target.object, "BarricadeAble") end)
        step("index", function() return target.object:getObjectIndex() end)
        step("barricade", function()
            local b = target.object:getBarricadeForCharacter(character)
            return b == nil and "none" or tostring(b:getNumPlanks())
        end)
        -- Vanilla-exact: ItemType.HAMMER with no fallback. Guard the
        -- global read first: indexing a nil ItemType would throw outside
        -- pcall protection, same class of crash as the null-body reads.
        step("itemTypeGlobal", function() return ItemType ~= nil end)
        if ItemType ~= nil then
            step("itemTypeHammer", function()
                return character:hasEquippedTag(ItemType.HAMMER)
            end)
        end
        step("plankEquipped", function() return character:hasEquipped("Plank") end)
        step("nails", function()
            return character:getInventory():getItemCount("Base.Nails", true)
        end)
        diag("native_validation_trace", { trace = table.concat(trace, " ") })
        local equippedTag = nativeHammerTag()
        local hammerReady = nil
        if equippedTag ~= nil and character.hasEquippedTag ~= nil then
            local checked, result = pcall(character.hasEquippedTag, character, equippedTag)
            hammerReady = checked and result == true
        end
        local equippedPlank = nil
        if character.hasEquipped ~= nil then
            local checkedPlank, resultPlank = pcall(character.hasEquipped, character, "Plank")
            if checkedPlank then equippedPlank = resultPlank == true end
        end
        local pos = charPos(character)
        local objectIndex = nil
        pcall(function() objectIndex = target.object:getObjectIndex() end)
        -- Object-side native gates: full barricade, non-barricadeable, or
        -- disallowed object. Each read is isolated: one throwing native
        -- getter must not hide the other three.
        local barricadePlanks, canAddPlank, allowed, able = nil, nil, nil, nil
        pcall(function()
            local b = target.object:getBarricadeForCharacter(character)
            if b ~= nil then
                barricadePlanks = tonumber(b:getNumPlanks())
                if b.canAddPlank ~= nil then canAddPlank = b:canAddPlank() == true end
            else
                barricadePlanks = 0
                canAddPlank = true
            end
        end)
        pcall(function()
            if target.object.isBarricadeAllowed ~= nil then
                allowed = target.object:isBarricadeAllowed() ~= false
            else
                allowed = true
            end
        end)
        pcall(function()
            if instanceof ~= nil then
                able = instanceof(target.object, "BarricadeAble") == true
            end
        end)
        diag("native_validation_failed", {
            hammer = fullType(hammer), hammerTag = hammerReady,
            plank = fullType(plank), plankEquipped = equippedPlank,
            nails = nailCount, objectIndex = objectIndex,
            barricadePlanks = barricadePlanks, canAddPlank = canAddPlank,
            allowed = allowed, able = able,
            charX = pos ~= nil and pos.x or nil,
            charY = pos ~= nil and pos.y or nil,
            targetX = target.x, targetY = target.y, targetZ = target.z,
        })
        local threw = (not valid) and tostring(accepted) or nil
        if threw ~= nil then
            diag("native_validation_threw", { error = threw })
        end
        return nil, "barricade_native_validation_failed:hammer=" .. tostring(fullType(hammer))
            .. ":hammerTag=" .. tostring(hammerReady)
            .. ":plank=" .. tostring(fullType(plank))
            .. ":nails=" .. tostring(nailCount)
            .. (threw ~= nil and (":threw=" .. threw) or "")
    end
    local queueDepth = nil
    pcall(function()
        local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
        local queue = queues ~= nil and queues[character] or nil
        if queue ~= nil and type(queue.queue) == "table" then queueDepth = #queue.queue end
    end)
    -- Native begin may complete synchronously, so use its registered queue
    -- return for admission rather than requiring action membership.
    local admittedQueue = ISTimedActionQueue.add(action)
    if admittedQueue == nil or ISTimedActionQueue.queues == nil
        or admittedQueue ~= ISTimedActionQueue.queues[character] then
        diag("queue_refused", { queueDepth = queueDepth })
        return nil, "barricade_queue_refused"
    end
    local pos = charPos(character)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.once ~= nil then
        pcall(function() log.once("barricade", "queue", "queued", {
            charX = pos ~= nil and pos.x or nil, charY = pos ~= nil and pos.y or nil,
            targetX = target.x, targetY = target.y, queueDepth = queueDepth,
            nails = nailCount,
        }) end)
    end
    return action, "queued"
end

function Barricades.isComplete(target, character, beforePlanks)
    if target == nil or target.object == nil then
        return false
    end
    local success, barricade = pcall(function()
        return target.object:getBarricadeForCharacter(character)
    end)
    if not success or barricade == nil then
        return false
    end
    local count = tonumber(barricade:getNumPlanks()) or 0
    return count > (tonumber(beforePlanks) or 0)
end

function Barricades.plankCount(target, character)
    if target == nil or target.object == nil then
        return 0
    end
    local success, barricade = pcall(function()
        return target.object:getBarricadeForCharacter(character)
    end)
    if not success or barricade == nil then
        return 0
    end
    return tonumber(barricade:getNumPlanks()) or 0
end

return Barricades
