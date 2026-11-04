-- Player-led house clearing (PT-12).
--
-- This is a coordinator, not a second looter. Each searcher receives the
-- existing `loot_building` directive narrowed to one room's real bounds; the
-- autonomy controller finds containers, walks there and transfers real items.
-- A guard holds the player's entry point through the existing `guard`
-- directive. The sweep only adds transient party state: room assignment,
-- reassignment when a room is finished, and one honest ending line.
--
-- Nothing here is persisted. A reload drops the sweep and every member keeps
-- ordinary duty, exactly as the design requires. Finds are announced from
-- verified native receipts in the controller, never from a planner guess.

local House = rawget(_G, "KnoxHouseClearing") or {}
_G.KnoxHouseClearing = House

House.MAX_PARTY = 4
House.MAX_HOURS = 0.75
House.MAX_FIND_LINES = 8
House.MAX_PACK_LINES = 3
House.COORDINATE_INTERVAL_TICKS = 15
House.PLAYER_LEASH = 30

local sweeps = {}

local function clean(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function feed(text)
    local activity = rawget(_G, "KnoxActivityFeed")
    if activity ~= nil and activity.event ~= nil then
        pcall(activity.event, text)
    end
end

local function worldAge()
    if getGameTime == nil then return 0 end
    local ok, value = pcall(function()
        return getGameTime():getWorldAgeHours()
    end)
    return ok and (tonumber(value) or 0) or 0
end

local function resolvePlayer(playerId)
    local service = rawget(_G, "KnoxCompanionService")
    if service ~= nil and service.resolvePlayer ~= nil then
        local ok, player = pcall(service.resolvePlayer, playerId)
        if ok and player ~= nil then return player end
    end
    if getNumActivePlayers ~= nil and getSpecificPlayer ~= nil then
        local count = tonumber(getNumActivePlayers()) or 0
        for playerNum = 0, math.max(0, count - 1) do
            local player = getSpecificPlayer(playerNum)
            if player ~= nil and service ~= nil and service.getPlayerId ~= nil
                and service.getPlayerId(player) == playerId then
                return player
            end
        end
    end
    return nil
end

local function playerIdFor(player)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.getPlayerId == nil then return nil end
    local ok, id = pcall(service.getPlayerId, player)
    return ok and id or nil
end

local function nameFor(survivorId)
    local persistence = rawget(_G, "KnoxPersistence")
    local identity = persistence ~= nil and persistence.getSurvivorIdentity ~= nil
        and persistence.getSurvivorIdentity(survivorId) or nil
    if type(identity) == "table" then
        local name = clean(tostring(identity.forename or "") .. " "
            .. tostring(identity.surname or ""))
        if name ~= "" then return name end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(survivorId) or nil
    if character ~= nil and character.getFullName ~= nil then
        local ok, name = pcall(function() return character:getFullName() end)
        name = ok and clean(name) or ""
        if name ~= "" then return name end
    end
    return "A survivor"
end

local function joinNames(names)
    if type(names) ~= "table" or #names == 0 then return "No one" end
    if #names == 1 then return names[1] end
    local head = {}
    for index = 1, #names - 1 do head[#head + 1] = names[index] end
    return table.concat(head, ", ") .. " and " .. names[#names]
end

local function buildingAt(square)
    if square == nil or square.getBuilding == nil then return nil end
    local ok, building = pcall(function() return square:getBuilding() end)
    return ok and building or nil
end

local function buildingInfo(square)
    local building = buildingAt(square)
    local definition = nil
    if building ~= nil and building.getDef ~= nil then
        local ok, value = pcall(function() return building:getDef() end)
        if ok then definition = value end
    end
    local buildingId = nil
    if definition ~= nil and definition.getID ~= nil then
        local ok, value = pcall(function() return definition:getID() end)
        if ok and value ~= nil then buildingId = tostring(value) end
    end
    if buildingId == nil and building ~= nil and building.getID ~= nil then
        local ok, value = pcall(function() return building:getID() end)
        if ok and value ~= nil then buildingId = tostring(value) end
    end
    local label = nil
    if definition ~= nil and definition.getName ~= nil then
        local ok, value = pcall(function() return definition:getName() end)
        if ok then label = clean(value) end
    end
    if label == nil or label == "" or string.lower(label) == "none" then
        if square ~= nil then
            label = "the building at " .. tostring(square:getX()) .. ", "
                .. tostring(square:getY())
        else
            label = "this building"
        end
    end
    return building, definition, buildingId, label
end

local function isOwnBase(square)
    if square == nil then return false end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getBaseAtSquare == nil then return false end
    local ok, base = pcall(function()
        return persistence.getBaseAtSquare(
            square:getX(), square:getY(), square:getZ(), "player")
    end)
    return ok and type(base) == "table" and base.ownerKind == "player"
end

local function roomName(room)
    if room == nil or room.getName == nil then return nil end
    local ok, value = pcall(function() return room:getName() end)
    value = ok and clean(value) or ""
    if value == "" or string.lower(value) == "none" then return nil end
    return value
end

local function boundsForRoom(room, fallbackZ)
    if room == nil or room.getRects == nil then return nil end
    local minX, minY, maxX, maxY, z = nil, nil, nil, nil, nil
    local ok = pcall(function()
        local rects = room:getRects()
        for index = 0, rects:size() - 1 do
            local rect = rects:get(index)
            local x = tonumber(rect:getX())
            local y = tonumber(rect:getY())
            local w = tonumber(rect:getW())
            local h = tonumber(rect:getH())
            if x ~= nil and y ~= nil and w ~= nil and h ~= nil and w > 0 and h > 0 then
                minX = minX == nil and x or math.min(minX, x)
                minY = minY == nil and y or math.min(minY, y)
                maxX = maxX == nil and (x + w - 1) or math.max(maxX, x + w - 1)
                maxY = maxY == nil and (y + h - 1) or math.max(maxY, y + h - 1)
            end
        end
        if room.getZ ~= nil then z = tonumber(room:getZ()) end
    end)
    if not ok or minX == nil then return nil end
    return {
        minX = minX, minY = minY, maxX = maxX, maxY = maxY,
        z = z ~= nil and z or (tonumber(fallbackZ) or 0),
    }
end

-- Count only containers that can actually hold household loot. Water and
-- rain collectors are storage, but searching them is not house clearing and
-- the native planner already refuses them.
local function countContainers(bounds)
    if bounds == nil or getCell == nil then return 0 end
    local cell = getCell()
    if cell == nil then return 0 end
    local count = 0
    for x = bounds.minX, bounds.maxX do
        for y = bounds.minY, bounds.maxY do
            local square = cell:getGridSquare(x, y, bounds.z)
            if square ~= nil and square.getObjects ~= nil then
                local objects = square:getObjects()
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local containerCount = object ~= nil and object.getContainerCount ~= nil
                        and object:getContainerCount() or 0
                    for containerIndex = 0, containerCount - 1 do
                        local container = object.getContainerByIndex ~= nil
                            and object:getContainerByIndex(containerIndex) or nil
                        if container ~= nil then
                            local exists = container.isExistYet == nil
                                or container:isExistYet() ~= false
                            local kind = container.getType ~= nil
                                and string.lower(tostring(container:getType() or "")) or ""
                            local unusable = kind == "corpse"
                                or string.find(kind, "water", 1, true) ~= nil
                                or string.find(kind, "rain", 1, true) ~= nil
                            if exists and not unusable then count = count + 1 end
                        end
                    end
                end
            end
        end
    end
    return count
end

local function collectRooms(building, z)
    if building == nil or building.getRooms == nil then return {} end
    local list = nil
    local ok = pcall(function() list = building:getRooms() end)
    if not ok or list == nil then return {} end
    local rooms, seen = {}, {}
    for index = 1, list:size() do
        local room = list:get(index - 1)
        local bounds = boundsForRoom(room, z)
        if bounds ~= nil and bounds.z == z then
            local name = roomName(room)
            local key = (name or "room") .. ":" .. tostring(bounds.minX) .. ":"
                .. tostring(bounds.minY) .. ":" .. tostring(bounds.maxX) .. ":"
                .. tostring(bounds.maxY) .. ":" .. tostring(bounds.z)
            if not seen[key] then
                local containers = countContainers(bounds)
                if containers > 0 then
                    seen[key] = true
                    rooms[#rooms + 1] = {
                        key = key, name = name, bounds = bounds,
                        containers = containers,
                    }
                end
            end
        end
    end
    return rooms
end

local function distanceToRoom(room, square)
    if room == nil or square == nil then return math.huge end
    local cx = (room.bounds.minX + room.bounds.maxX) / 2
    local cy = (room.bounds.minY + room.bounds.maxY) / 2
    local dx, dy = cx - square:getX(), cy - square:getY()
    return dx * dx + dy * dy
end

local function healthOf(character)
    if character == nil or character.getHealth == nil then return 100 end
    local ok, value = pcall(function() return character:getHealth() end)
    return ok and (tonumber(value) or 100) or 100
end

local function companionCandidates(player)
    local service = rawget(_G, "KnoxCompanionService")
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local origin = player ~= nil and player.getCurrentSquare ~= nil
        and player:getCurrentSquare() or nil
    local candidates = {}
    if service == nil or service.getCompanionIds == nil
        or runtime == nil or runtime.getCharacter == nil or origin == nil then
        return candidates
    end
    local ok, ids = pcall(service.getCompanionIds, player)
    if not ok or type(ids) ~= "table" then return candidates end
    for _, id in ipairs(ids) do
        local character = runtime.getCharacter(id)
        if character ~= nil then
            local dead = false
            if character.isDead ~= nil then
                local read, value = pcall(function() return character:isDead() end)
                dead = read and value == true
            end
            if not dead then
                local square = character.getCurrentSquare ~= nil
                    and character:getCurrentSquare() or nil
                local dx, dy = 0, 0
                if square ~= nil then
                    dx, dy = square:getX() - origin:getX(), square:getY() - origin:getY()
                end
                candidates[#candidates + 1] = {
                    id = id, character = character,
                    distance = dx * dx + dy * dy,
                }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return tostring(a.id) < tostring(b.id)
    end)
    return candidates
end

-- Pure planning surface used by the menu, the issue path and fixtures. It
-- reads real bodies and real room bounds but changes nothing.
function House.plan(player, square)
    if player == nil or player.getCurrentSquare == nil then
        return nil, "player_unavailable"
    end
    local origin = player:getCurrentSquare()
    if origin == nil then return nil, "player_unavailable" end
    local target = square or origin
    local baseSquare = target
    local building, definition, buildingId, label = buildingInfo(target)
    if building == nil then
        building, definition, buildingId, label = buildingInfo(origin)
        -- The clicked square can be open ground beside the player; the plan
        -- then falls back to the building the player is standing in. Check
        -- ownership of that real building, not the empty click.
        baseSquare = origin
    end
    if building == nil or buildingId == nil then return nil, "no_building" end
    if isOwnBase(baseSquare) then return nil, "own_base" end
    local z = tonumber(target:getZ()) or tonumber(origin:getZ()) or 0
    local rooms = collectRooms(building, z)
    if #rooms == 0 then return nil, "no_searchable_interior" end
    table.sort(rooms, function(a, b)
        local da, db = distanceToRoom(a, origin), distanceToRoom(b, origin)
        if da ~= db then return da < db end
        return a.key < b.key
    end)
    local candidates = companionCandidates(player)
    if #candidates == 0 then return nil, "no_companions" end
    -- Do not order more people than the house can usefully absorb. One room
    -- needs one searcher and at most one guard; sending four people into a
    -- single bedroom makes the party look busy without clearing faster.
    local useful = math.min(#candidates, House.MAX_PARTY, #rooms + 1)
    local selected = {}
    for index = 1, useful do
        selected[#selected + 1] = candidates[index]
    end
    -- Two survivors both search; three or more leave one healthy person on the
    -- entrance. That keeps a two-person sweep useful without pretending a
    -- single guard can clear a house alone.
    local guard = nil
    if #selected >= 3 then
        local guardIndex = 1
        for index = 2, #selected do
            if healthOf(selected[index].character) > healthOf(selected[guardIndex].character) then
                guardIndex = index
            end
        end
        guard = table.remove(selected, guardIndex)
    end
    local searchers, guards = {}, {}
    if guard ~= nil then guards[#guards + 1] = guard end
    for _, candidate in ipairs(selected) do
        if #searchers < #rooms then
            searchers[#searchers + 1] = candidate
        else
            -- More people than rooms: the extra pair of eyes holds the
            -- entrance instead of queueing on one container.
            guards[#guards + 1] = candidate
        end
    end
    local roomQueue = {}
    for index = #searchers + 1, #rooms do roomQueue[#roomQueue + 1] = rooms[index] end
    local plan = {
        building = building,
        definition = definition,
        buildingId = buildingId,
        label = label,
        z = z,
        originX = origin:getX(),
        originY = origin:getY(),
        originZ = origin:getZ(),
        rooms = rooms,
        searchers = searchers,
        guards = guards,
        roomQueue = roomQueue,
        leftBehind = math.max(0, #candidates - #selected),
    }
    return plan
end

local function roomDirective(plan, room)
    return {
        kind = "loot_building",
        buildingId = plan.buildingId,
        minX = room.bounds.minX,
        minY = room.bounds.minY,
        maxX = room.bounds.maxX,
        maxY = room.bounds.maxY,
        z = room.bounds.z,
    }
end

local function guardDirective(plan)
    return {
        kind = "guard",
        minX = plan.originX,
        minY = plan.originY,
        maxX = plan.originX,
        maxY = plan.originY,
        z = plan.originZ,
    }
end

local function directiveIssuedAt(survivorId)
    local persistence = rawget(_G, "KnoxPersistence")
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(survivorId) or nil
    local directive = duty ~= nil and duty.directive or nil
    return directive ~= nil and tonumber(directive.issuedAtHours) or nil
end

local function issueMember(player, survivorId, directive)
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.issueDirective == nil then
        return false, "order_service_unavailable"
    end
    local ok, accepted, reason = pcall(service.issueDirective, player, survivorId, directive)
    if not ok then return false, "order_error" end
    if accepted ~= true then return false, reason or "order_refused" end
    local issuedAt = directiveIssuedAt(survivorId)
    return true, issuedAt
end

local function currentDirective(survivorId)
    local persistence = rawget(_G, "KnoxPersistence")
    local duty = persistence ~= nil and persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(survivorId) or nil
    return duty ~= nil and duty.directive or nil
end

local function matchesSweep(sweep, member, directive)
    if directive == nil or member == nil then return false end
    if tostring(directive.issuedAtHours) ~= tostring(member.issuedAt)
        or tostring(directive.kind or "") ~= member.kind then
        return false
    end
    if member.kind == "loot_building"
        and tostring(directive.buildingId or "") ~= tostring(sweep.buildingId) then
        return false
    end
    -- A same-hour replacement can carry the same issuedAtHours. The room
    -- bounds make the sweep's exact order distinguishable from any new one.
    if member.minX ~= nil then
        return tonumber(directive.minX) == member.minX
            and tonumber(directive.minY) == member.minY
            and tonumber(directive.maxX) == member.maxX
            and tonumber(directive.maxY) == member.maxY
    end
    return true
end

local function releaseMember(sweep, member)
    local player = resolvePlayer(sweep.playerId)
    if player == nil then return end
    local directive = currentDirective(member.id)
    if not matchesSweep(sweep, member, directive) then return end
    local service = rawget(_G, "KnoxCompanionService")
    local cleared = false
    if service ~= nil and service.clearDirective ~= nil then
        local ok, value = pcall(service.clearDirective, player, member.id)
        cleared = ok and value == true
    end
    if not cleared then
        local persistence = rawget(_G, "KnoxPersistence")
        if persistence ~= nil and persistence.clearCompanionDirective ~= nil then
            pcall(persistence.clearCompanionDirective, member.id, sweep.playerId, worldAge())
        end
    end
end

local function packFull(survivorId)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(survivorId) or nil
    if character == nil or character.getInventory == nil then return false end
    local ok, full = pcall(function()
        local inventory = character:getInventory()
        if inventory == nil or inventory.getWeight == nil
            or inventory.getCapacityWeight == nil then return false end
        local weight = tonumber(inventory:getWeight()) or 0
        local capacity = tonumber(inventory:getCapacityWeight()) or 0
        return capacity > 0 and weight / capacity >= 0.95
    end)
    return ok and full == true
end

local REASON_TEXT = {
    no_building = "stand inside a building",
    own_base = "this is your own base",
    no_searchable_interior = "no searchable rooms here",
    no_companions = "no companion is with you",
    already_clearing = "a sweep is already running",
    no_takers = "no companion could take the order",
    player_unavailable = "your character is unavailable",
    order_service_unavailable = "orders are unavailable",
}

function House.shortReason(reason)
    return REASON_TEXT[tostring(reason or "")] or "not available here"
end

function House.endText(sweep, reason, detail)
    local searched = tonumber(sweep.roomsSearched) or 0
    local total = tonumber(sweep.roomCount) or 0
    local found = tonumber(sweep.foundItems) or 0
    local progress = tostring(searched) .. " of " .. tostring(total)
        .. " rooms searched, " .. tostring(found) .. " items taken"
    if reason == "searched" then
        if found == 0 then
            return "House swept: " .. progress .. ". No items taken."
        end
        return "House swept: " .. progress .. "."
    end
    local phrase = "stopped"
    if reason == "packs_full" then
        phrase = "stopped: packs are full"
    elseif reason == "orders_changed" then
        phrase = "stopped: a new order took over"
    elseif reason == "player_left" then
        -- The boundary is the 30-tile leash, not the doorway; the player may
        -- stand outside and watch the sweep without ending it.
        phrase = "stopped: you moved too far away"
    elseif reason == "timed_out" then
        phrase = "stopped: it took too long"
    elseif reason == "member_lost" then
        phrase = "stopped: " .. tostring(detail or "a member") .. " was lost"
    elseif reason == "contact_lost" then
        phrase = "stopped: the party lost contact"
    elseif reason == "blocked" then
        phrase = "stopped: some rooms could not be reached"
    elseif reason == "cancelled" then
        phrase = "cancelled"
    end
    return "House sweep " .. phrase .. ". " .. progress .. "."
end

local function finish(sweep, reason, detail)
    if sweep == nil or sweep.finished == true then return end
    sweep.finished = true
    sweeps[sweep.playerId] = nil
    for _, member in pairs(sweep.members or {}) do
        releaseMember(sweep, member)
    end
    if reason == "searched" then
        local full = false
        for id, member in pairs(sweep.searchers or {}) do
            if member ~= nil and not member.failed and packFull(id) then full = true end
        end
        if full and (tonumber(sweep.roomsSearched) or 0)
            < (tonumber(sweep.roomCount) or 0) then
            reason = "packs_full"
        end
    end
    feed(House.endText(sweep, reason, detail))
    print("[KnoxSurvivors][House] ended reason=" .. tostring(reason)
        .. " rooms=" .. tostring(sweep.roomsSearched or 0) .. "/"
        .. tostring(sweep.roomCount or 0)
        .. " items=" .. tostring(sweep.foundItems or 0))
end

function House.canIssue(player, square)
    local plan, reason = House.plan(player, square)
    return plan ~= nil, reason, plan
end

function House.activeFor(player)
    local playerId = playerIdFor(player)
    return playerId ~= nil and sweeps[playerId] ~= nil
end

function House.status(player)
    local playerId = playerIdFor(player)
    local sweep = playerId ~= nil and sweeps[playerId] or nil
    if sweep == nil then return nil end
    return {
        buildingLabel = sweep.buildingLabel,
        roomCount = sweep.roomCount,
        roomsSearched = sweep.roomsSearched,
        foundItems = sweep.foundItems,
    }
end

function House.issue(player, square)
    local plan, reason = House.plan(player, square)
    if plan == nil then
        feed("Cannot clear the house: " .. House.shortReason(reason) .. ".")
        return false, reason
    end
    local playerId = playerIdFor(player)
    if playerId == nil then
        feed("Cannot clear the house: your character is unavailable.")
        return false, "player_unavailable"
    end
    if sweeps[playerId] ~= nil then
        feed("A house sweep is already under way.")
        return false, "already_clearing"
    end
    local sweep = {
        playerId = playerId,
        buildingId = plan.buildingId,
        buildingLabel = plan.label,
        originX = plan.originX, originY = plan.originY, originZ = plan.originZ,
        z = plan.z,
        startedAtHours = worldAge(),
        roomCount = #plan.rooms,
        roomsSearched = 0,
        foundItems = 0,
        findLines = 0,
        members = {},
        searchers = {},
        guards = {},
        roomQueue = plan.roomQueue,
        containerReported = {},
        finished = false,
    }
    local guardNames, searcherNames = {}, {}
    for _, candidate in ipairs(plan.guards) do
        local ok, issuedAt = issueMember(player, candidate.id, guardDirective(plan))
        if ok then
            local member = {
                id = candidate.id, kind = "guard", role = "guard",
                issuedAt = issuedAt, minX = plan.originX, minY = plan.originY,
                maxX = plan.originX, maxY = plan.originY,
            }
            sweep.members[candidate.id] = member
            sweep.guards[candidate.id] = member
            guardNames[#guardNames + 1] = nameFor(candidate.id)
        end
    end
    for index, candidate in ipairs(plan.searchers) do
        local room = plan.rooms[index]
        local ok, issuedAt = issueMember(player, candidate.id, roomDirective(plan, room))
        if ok then
            local member = {
                id = candidate.id, kind = "loot_building", role = "searcher",
                issuedAt = issuedAt, room = room, done = false,
                minX = room.bounds.minX, minY = room.bounds.minY,
                maxX = room.bounds.maxX, maxY = room.bounds.maxY,
            }
            sweep.members[candidate.id] = member
            sweep.searchers[candidate.id] = member
            searcherNames[#searcherNames + 1] = nameFor(candidate.id)
        else
            -- A companion who could not hear the first order must not cost
            -- the party that room; it joins the queue for an active searcher.
            sweep.roomQueue[#sweep.roomQueue + 1] = room
        end
    end
    if #searcherNames == 0 then
        for _, member in pairs(sweep.members) do releaseMember(sweep, member) end
        feed("Cannot clear the house: no companion could take the order.")
        return false, "no_takers"
    end
    sweeps[playerId] = sweep
    local line = "Clearing " .. tostring(plan.label) .. ": " .. joinNames(searcherNames)
        .. (#searcherNames == 1 and " searches" or " search")
    if #guardNames > 0 then
        line = line .. "; " .. joinNames(guardNames)
            .. (#guardNames == 1 and " guards the entrance" or " guard the entrance")
    end
    line = line .. "."
    if #sweep.roomQueue > 0 then
        line = line .. " " .. tostring(#sweep.roomQueue) .. " more rooms queued."
    end
    if (plan.leftBehind or 0) > 0 then
        line = line .. " " .. tostring(plan.leftBehind)
            .. (plan.leftBehind == 1 and " stays with you." or " stay with you.")
    end
    feed(line)
    print("[KnoxSurvivors][House] started building=" .. tostring(plan.buildingId)
        .. " rooms=" .. tostring(#plan.rooms)
        .. " searchers=" .. tostring(#searcherNames)
        .. " guards=" .. tostring(#guardNames))
    return true, sweep
end

function House.cancel(player, reason)
    local playerId = playerIdFor(player)
    local sweep = playerId ~= nil and sweeps[playerId] or nil
    if sweep == nil then
        feed("No house sweep is running.")
        return false, "not_running"
    end
    finish(sweep, reason or "cancelled")
    return true
end

-- Called only by the controller's exhausted-room path (three missed
-- searches), never by a player-cleared order. The next coordinate pass owns
-- the actual reassignment so no native move is started from inside a think.
function House.onRoomFinished(controller)
    if controller == nil or controller.id == nil then return false end
    local sweep = controller.companionOwnerId ~= nil
        and sweeps[controller.companionOwnerId] or nil
    local member = sweep ~= nil and sweep.searchers ~= nil
        and sweep.searchers[controller.id] or nil
    if member == nil or member.done then return false end
    member.finished = true
    return true
end

local function beginNextRoom(sweep, member, player)
    if #sweep.roomQueue == 0 then return false end
    local room = table.remove(sweep.roomQueue, 1)
    local ok, issuedAt = issueMember(player, member.id, roomDirective(sweep, room))
    if not ok then
        -- Put the room back so another searcher can try it; this member is
        -- finished rather than silently credited with a room it never entered.
        table.insert(sweep.roomQueue, 1, room)
        member.failed = true
        return false
    end
    member.room = room
    member.issuedAt = issuedAt
    member.minX, member.minY = room.bounds.minX, room.bounds.minY
    member.maxX, member.maxY = room.bounds.maxX, room.bounds.maxY
    member.done = false
    return true
end

local function advance(sweep)
    local player = resolvePlayer(sweep.playerId)
    if player == nil then
        finish(sweep, "player_unavailable")
        return
    end
    local now = worldAge()
    if now - (tonumber(sweep.startedAtHours) or now) > House.MAX_HOURS then
        finish(sweep, "timed_out")
        return
    end
    local origin = player.getCurrentSquare ~= nil and player:getCurrentSquare() or nil
    if origin == nil then
        finish(sweep, "player_unavailable")
        return
    end
    local dx = origin:getX() - sweep.originX
    local dy = origin:getY() - sweep.originY
    if origin:getZ() ~= sweep.originZ
        or dx * dx + dy * dy > House.PLAYER_LEASH * House.PLAYER_LEASH then
        finish(sweep, "player_left")
        return
    end
    for _, member in pairs(sweep.guards) do
        local directive = currentDirective(member.id)
        if not matchesSweep(sweep, member, directive) then
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            local character = runtime ~= nil and runtime.getCharacter ~= nil
                and runtime.getCharacter(member.id) or nil
            if character == nil then
                finish(sweep, "member_lost", nameFor(member.id))
            elseif directive == nil then
                -- A cleared guard order is either the player cancelling or a
                -- controller failure; neither is a replacement order, so stop
                -- without claiming which one it was.
                finish(sweep, "cancelled")
            else
                finish(sweep, "orders_changed")
            end
            return
        end
    end
    for _, member in pairs(sweep.searchers) do
        if not member.done then
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            local character = runtime ~= nil and runtime.getCharacter ~= nil
                and runtime.getCharacter(member.id) or nil
            if character == nil then
                finish(sweep, "member_lost", nameFor(member.id))
                return
            end
            local directive = currentDirective(member.id)
            if matchesSweep(sweep, member, directive) then
                -- The room is still being searched by its assigned member.
            elseif directive == nil then
                -- A nil directive can mean the controller exhausted the room
                -- or the player cleared the order. Only the explicit hook may
                -- advance; anything else is a new player order and stops the
                -- sweep without clearing that new order.
                if member.finished ~= true then
                    finish(sweep, "orders_changed")
                    return
                end
                member.finished = nil
                sweep.roomsSearched = (tonumber(sweep.roomsSearched) or 0) + 1
                member.done = true
                -- A full pack is a real reason to stop, not a reason to walk
                -- into another room and fail to pick anything up. Release this
                -- member now and let the remaining searchers take the queue.
                if packFull(member.id) then
                    sweep.packReleased = (tonumber(sweep.packReleased) or 0) + 1
                    if (tonumber(sweep.packLines) or 0) < House.MAX_PACK_LINES then
                        sweep.packLines = (tonumber(sweep.packLines) or 0) + 1
                        feed(nameFor(member.id)
                            .. "'s pack is full; they stopped searching.")
                    end
                else
                    beginNextRoom(sweep, member, player)
                end
            else
                finish(sweep, "orders_changed")
                return
            end
        end
    end
    local active, queued = false, #sweep.roomQueue
    for _, member in pairs(sweep.searchers) do
        if not member.done then active = true end
    end
    if not active then
        if queued > 0 then
            -- An empty queue with nobody able to carry more is a pack limit,
            -- not an unreachable house.
            finish(sweep, (tonumber(sweep.packReleased) or 0) > 0 and "packs_full" or "blocked")
        else
            finish(sweep, "searched")
        end
    end
end

function House.coordinate(controllers, activeIds, ticks)
    -- The autonomy pass runs every tick; room transitions only need a few
    -- checks a second. No sweep means no work at all.
    if ticks == nil or ticks % House.COORDINATE_INTERVAL_TICKS ~= 0 then return end
    local any = false
    for _ in pairs(sweeps) do any = true; break end
    if not any then return end
    local ids = {}
    for playerId in pairs(sweeps) do ids[#ids + 1] = playerId end
    for _, playerId in ipairs(ids) do
        local sweep = sweeps[playerId]
        if sweep ~= nil then advance(sweep) end
    end
end

local function containerLabel(container)
    if container == nil then return "container" end
    local kind = ""
    if container.getType ~= nil then
        local ok, value = pcall(function() return container:getType() end)
        kind = ok and clean(value) or ""
    end
    kind = string.lower(kind):gsub("_", " "):gsub("%s+", " ")
    if kind == "" or kind == "none" then return "container" end
    return kind
end

local function sourceLabel(container)
    local room = nil
    if container ~= nil and container.getSourceGrid ~= nil then
        pcall(function()
            local grid = container:getSourceGrid()
            local value = grid ~= nil and grid.getRoom ~= nil and grid:getRoom() or nil
            if value ~= nil and value.getName ~= nil then room = clean(value:getName()) end
        end)
    end
    if room == "" or string.lower(room or "") == "none" then room = nil end
    local label = containerLabel(container)
    if room ~= nil and string.find(label, string.lower(room), 1, true) == nil then
        return "the " .. room .. " " .. label
    end
    if room ~= nil then return "the " .. label end
    return "a " .. label
end

local function itemLabel(item)
    if item == nil then return "an item" end
    local ok, name = pcall(function() return item:getName() end)
    name = ok and clean(name) or ""
    if name ~= "" then return name end
    if item.getFullType ~= nil then
        local typed, fullType = pcall(function() return item:getFullType() end)
        if typed and clean(fullType) ~= "" then return clean(fullType) end
    end
    return "an item"
end

function House.onLootVerified(controller, pending)
    if controller == nil or pending == nil or pending.container == nil then return false end
    local playerId = controller.companionOwnerId
    local sweep = playerId ~= nil and sweeps[playerId] or nil
    if sweep == nil then return false end
    local member = sweep.members[controller.id]
    if member == nil or member.role ~= "searcher" then return false end
    local container = pending.container
    if sweep.containerReported[container] then return false end
    local candidates = pending.items
    if candidates == nil or #candidates == 0 then
        candidates = pending.item ~= nil and { { item = pending.item } } or {}
    end
    local counts, names = {}, {}
    local received = 0
    for _, candidate in ipairs(candidates) do
        local item = candidate ~= nil and candidate.item or nil
        if item ~= nil and controller.collectionItemReceived ~= nil then
            local ok, got = pcall(controller.collectionItemReceived, controller, pending, item)
            if ok and got == true then
                local label = itemLabel(item)
                if counts[label] == nil then
                    counts[label] = 0
                    names[#names + 1] = label
                end
                counts[label] = counts[label] + 1
                received = received + 1
            end
        end
    end
    if received == 0 then return false end
    sweep.containerReported[container] = true
    sweep.foundItems = (tonumber(sweep.foundItems) or 0) + received
    if (tonumber(sweep.findLines) or 0) >= House.MAX_FIND_LINES then return true end
    -- Lead with the largest real haul, then alphabetical for a stable line.
    table.sort(names, function(a, b)
        local ca, cb = counts[a] or 0, counts[b] or 0
        if ca ~= cb then return ca > cb end
        return a < b
    end)
    local parts = {}
    for index = 1, math.min(#names, 3) do
        local label = names[index]
        local count = counts[label] or 1
        parts[#parts + 1] = (count > 1 and tostring(count) .. " " or "") .. label
    end
    if #names > 3 then
        parts[#parts + 1] = tostring(#names - 3) .. " more"
    end
    sweep.findLines = (tonumber(sweep.findLines) or 0) + 1
    feed(nameFor(controller.id) .. " took " .. table.concat(parts, ", ")
        .. " from " .. sourceLabel(container) .. ".")
    return true
end

-- Fixture seam: drop transient state without touching bodies. Production never
-- calls this; a reload naturally starts with an empty coordinator.
function House.reset()
    sweeps = {}
end

function House.runtimeSize()
    local count = 0
    for _ in pairs(sweeps) do count = count + 1 end
    return count
end

return House
