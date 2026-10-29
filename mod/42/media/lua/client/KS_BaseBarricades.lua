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
                            local target = targetFromObject(base, object, square)
                            if eligible == nil or eligible(target) then return target, "found" end
                        end
                    end
                end
            end
        end
    end
    return nil, "no_unbarricaded_window"
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
                            found[#found + 1] = targetFromObject(base, object, square)
                            if #found >= maxTargets then
                                return found, "found"
                            end
                        end
                    end
                end
            end
        end
    end
    return found, #found > 0 and "found" or "no_unbarricaded_window"
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
    if object ~= nil then return { object = object, square = square }, "resolved" end
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
