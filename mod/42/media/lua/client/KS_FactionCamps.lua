require "KS_Persistence"

local Camps = rawget(_G, "KnoxFactionCamps") or {}
_G.KnoxFactionCamps = Camps

-- This file owns two kinds of place and the voice both of them have. Four
-- concerns live here, in this order, and each has exactly one owner:
--   1. A camp's ground - where a faction camp stands, what it contains, and
--      which member holds which slot (contains, memberSlot, positionFor, and
--      the assignment loop in reconcile).
--   2. A household's ground - the shared home already in the ledger, derived
--      into that same assignment and released when the member walks out
--      (homeLocationFor, homeCampFor, isHomeCampId, household loop).
--   3. What a place says - pure functions, one per kind of place: reactionFor
--      for a camp's bounded ladder, householdLine for a household's single
--      line, with shared helpers (addressedName, isNightHour, nearestSpeaker,
--      householdSpeechKey, playerInsideHome).
--   4. When it says it - reconcile, the one low-frequency pass that reads the
--      world and commits cooldowns, warning rungs and presence.
-- No other file should decide a place's wording or hold a survivor to a
-- building; extend the owner above instead of adding a second one beside it.

local function safehouseOccupied(building)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil or SafeHouse == nil then return false end
    local success, safehouse = pcall(function()
        return SafeHouse.getSafehouseOverlapping(
            definition:getX(), definition:getY(),
            definition:getX() + definition:getW(), definition:getY() + definition:getH()
        )
    end)
    return success and safehouse ~= nil
end

local function locationFor(character)
    local square = character ~= nil and character:getCurrentSquare() or nil
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    if definition ~= nil and (definition.getX == nil or definition.getY == nil
        or definition.getX2 == nil or definition.getY2 == nil
        or definition.getID == nil) then
        definition = nil
    end
    if square == nil or safehouseOccupied(building) then
        return nil
    end
    -- A faction can form before it has found a building. Preserve the same
    -- temporary-camp lifecycle outdoors rather than leaving the group homeless
    -- until a building happens to stream in. The radius-based camp geometry is
    -- intentionally modest; permanent shelter scouting still owns buildings.
    if definition == nil then
        local outside = square.isOutside ~= nil and square:isOutside()
            or (square.getRoom ~= nil and square:getRoom() == nil)
        if outside and square.canStand ~= nil and square:canStand() then
            return {
                x = square:getX(), y = square:getY(), z = square:getZ(),
                name = "Temporary Camp",
            }
        end
        return nil
    end
    return {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        buildingId = tostring(definition:getID()), name = "Temporary Shelter",
        minX = definition:getX(), minY = definition:getY(),
        maxX = definition:getX2(), maxY = definition:getY2(),
    }
end

local function buildingIdForSquare(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    return definition ~= nil and tostring(definition:getID()) or nil
end

function Camps.contains(camp, square)
    if type(camp) ~= "table" or square == nil
        or square:getZ() ~= (tonumber(camp.z) or 0) then
        return false
    end
    if camp.buildingId ~= nil then
        return buildingIdForSquare(square) == tostring(camp.buildingId)
    end
    return math.abs(square:getX() - (tonumber(camp.x) or 0)) <= 5
        and math.abs(square:getY() - (tonumber(camp.y) or 0)) <= 5
end

function Camps.memberSlot(camp, survivorId)
    for index, id in ipairs(type(camp) == "table" and camp.memberIds or {}) do
        if id == survivorId then
            return index
        end
    end
    return 1
end

-- A household already has a place in the ledger. This turns that place into
-- the same camp assignment the factions use, so its people keep to the building
-- they were allocated in instead of drifting. Pure: the caller supplies the
-- loaded location and membership; nothing is invented when the home is not
-- loaded or the character is standing somewhere else.
function Camps.homeLocationFor(character, home)
    if character == nil or type(home) ~= "table" or home.buildingId == nil then
        return nil
    end
    local square = character:getCurrentSquare()
    if square == nil then return nil end
    if buildingIdForSquare(square) ~= tostring(home.buildingId) then return nil end
    return locationFor(character)
end

-- A home is where somebody is when they have nothing else to do. A member with
-- real work or sleep in front of them is not held by their own house, which is
-- the difference between living somewhere and being shut in.
-- A household answers at its own door. Met on a road a hundred tiles from
-- home, it speaks through awayLine instead.
function Camps.speaksForPlace(company, buildingId)
    if type(company) ~= "table" or type(company.home) ~= "table" then return false end
    local home = company.home.buildingId
    if type(home) ~= "string" or home == "" then return false end
    return buildingId ~= nil and tostring(buildingId) == home
end

function Camps.homeHeldByIntent(busy)
    return busy ~= true
end

function Camps.isHomeCampId(campId)
    return type(campId) == "string" and campId:sub(1, 5) == "home:"
end

function Camps.homeCampFor(company, location, memberIds)
    if type(company) ~= "table" or type(company.home) ~= "table" then return nil end
    if type(location) ~= "table" then return nil end
    local groupId = tostring(company.groupId or "")
    if groupId == "" then return nil end
    local x, y = tonumber(location.x), tonumber(location.y)
    if x == nil or y == nil then return nil end
    local members = {}
    for _, memberId in ipairs(type(memberIds) == "table" and memberIds or {}) do
        if type(memberId) == "string" and memberId ~= "" then
            members[#members + 1] = memberId
        end
    end
    return {
        id = "home:" .. groupId,
        kind = "household",
        x = x, y = y, z = tonumber(location.z) or 0,
        buildingId = tostring(location.buildingId or company.home.buildingId),
        name = "Home",
        minX = tonumber(location.minX) or (x - 4),
        minY = tonumber(location.minY) or (y - 4),
        maxX = tonumber(location.maxX) or (x + 4),
        maxY = tonumber(location.maxY) or (y + 4),
        memberIds = members,
    }
end

-- Camp positions are ordinary standable world squares. The slot merely rotates
-- the deterministic candidate order; native movement/traversal still owns the
-- route, and the controller's short-lived reservation prevents active stacking.
function Camps.positionFor(camp, slot, unavailable)
    if type(camp) ~= "table" or getCell() == nil then
        return nil
    end
    local centerX = tonumber(camp.x)
    local centerY = tonumber(camp.y)
    local z = tonumber(camp.z) or 0
    if centerX == nil or centerY == nil then
        return nil
    end
    local minX = tonumber(camp.minX) or (centerX - 4)
    local minY = tonumber(camp.minY) or (centerY - 4)
    local maxX = tonumber(camp.maxX) or (centerX + 4)
    local maxY = tonumber(camp.maxY) or (centerY + 4)
    local candidates = {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = getCell():getGridSquare(x, y, z)
            if square ~= nil and square:canStand() and Camps.contains(camp, square) then
                candidates[#candidates + 1] = {
                    square = square,
                    distance = (x - centerX) ^ 2 + (y - centerY) ^ 2,
                    x = x,
                    y = y,
                }
            end
        end
    end
    table.sort(candidates, function(first, second)
        if first.distance ~= second.distance then
            return first.distance < second.distance
        end
        if first.y ~= second.y then
            return first.y < second.y
        end
        return first.x < second.x
    end)
    if #candidates == 0 then
        return nil
    end
    local start = ((math.max(1, tonumber(slot) or 1) - 1) % #candidates) + 1
    for offset = 0, #candidates - 1 do
        local candidate = candidates[((start + offset - 1) % #candidates) + 1]
        if unavailable == nil or not unavailable(candidate.square) then
            return candidate.square
        end
    end
    return nil
end

-- A camp answers the player. A stranger inside eight tiles is warned; someone
-- the faction trusts is welcomed; a hostile camp is combat's business. Bounded
-- and pure, so the wording and every boundary are provable without a body.
local REACTION_DISTANCE_SQ = 8 * 8
local REACTION_COOLDOWN_HOURS = 24

-- A place only uses a name for somebody it already trusts. A stranger greeted
-- by name is a lie about what the household actually knows.
local function addressedName(name)
    if type(name) ~= "string" then return nil end
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" or #trimmed > 40 then return nil end
    if trimmed:find("[%c]") ~= nil then return nil end
    return trimmed
end

-- A home at night is a different place: same door, different sentence. The
-- hour comes from the real game clock, and a missing clock keeps the daytime
-- line rather than guessing.
local function isNightHour(hour)
    local h = tonumber(hour)
    if h == nil or h ~= h then return false end
    h = h % 24
    return h < 6 or h >= 21
end
local function currentHourOfDay()
    local getter = rawget(_G, "getGameTime")
    if type(getter) ~= "function" then return nil end
    local ok, time = pcall(getter)
    if not ok or time == nil then return nil end
    local hour = nil
    pcall(function() hour = time:getHour() end)
    return tonumber(hour)
end

-- Read at the moment a line is about to be said, so a renamed character is
-- addressed by the name the player actually sees.
local function playerDisplayName()
    local getter = rawget(_G, "getPlayer")
    if type(getter) ~= "function" then return nil end
    local ok, player = pcall(getter)
    if not ok or player == nil then return nil end
    local name = nil
    pcall(function()
        if player.getFullName ~= nil then name = player:getFullName() end
        if (name == nil or name == "") and player.getDisplayName ~= nil then
            name = player:getDisplayName()
        end
    end)
    return addressedName(name)
end
-- Ignoring the same camp twice is a decision, so the third line is final. The
-- ladder is bounded: it never grows another rung however often the player comes
-- back, and a welcome never advances it.
local WARNING_LADDER = {
    { "warning", "Keep your distance. This is our camp." },
    { "warning", "I said keep back. We are not asking twice." },
    { "final", "You have been told. Next time we will not be talking." },
}
function Camps.reactionFor(faction, distanceSq, disposition, worldAgeHours,
    nextAllowedHours, warnings, playerName, hourOfDay, returning)
    if type(faction) ~= "table" or type(distanceSq) ~= "number"
        or distanceSq ~= distanceSq then return nil end
    if faction.kind == "player" then return nil end
    if disposition == "hostile" then return nil end
    if distanceSq > REACTION_DISTANCE_SQ then return nil end
    local hours = tonumber(worldAgeHours) or 0
    if (tonumber(nextAllowedHours) or 0) > hours then return nil end
    local night = isNightHour(hourOfDay)
    if disposition == "allied" or disposition == "friendly" then
        local known = addressedName(playerName)
        if returning == true and known ~= nil then
            return "welcome", "Back again, " .. known .. ". Make yourself at home.", nil
        end
        if returning == true then
            return "welcome", "Back again. Make yourself at home.", nil
        end
        if night and known ~= nil then
            return "welcome", "You are out late, " .. known .. ". Make yourself at home.", nil
        end
        if night then
            return "welcome", "You are out late. Make yourself at home.", nil
        end
        if known ~= nil then
            return "welcome", "Good to see you, " .. known .. ". Make yourself at home.", nil
        end
        return "welcome", "Good to see you. Make yourself at home.", nil
    end
    local served = math.max(0, math.floor(tonumber(warnings) or 0))
    -- Only the first rung hears the hour. Once a camp has told the player off,
    -- what it says next is about them, not about the time.
    if served == 0 and returning == true then
        return "warning", "Back again. Mind how close you come.", served + 1
    end
    if served == 0 and night then
        return "warning", "Late to be walking in. This is our camp.", served + 1
    end
    local rung = WARNING_LADDER[math.min(#WARNING_LADDER, served + 1)]
    return rung[1], rung[2], served + 1
end
function Camps.reactionCooldownHours() return REACTION_COOLDOWN_HOURS end
function Camps.reactionDistanceSq() return REACTION_DISTANCE_SQ end

-- A sentence does not pass through a floor. Camp and household reach is
-- horizontal only when both ends are on the same storey: a player upstairs is
-- not at the camp's doorstep, and a guard below the stairs is not in the room.
function Camps.placeDistanceSq(ax, ay, az, bx, by, bz)
    local x1, y1 = tonumber(ax), tonumber(ay)
    local x2, y2 = tonumber(bx), tonumber(by)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    if (tonumber(az) or 0) ~= (tonumber(bz) or 0) then return nil end
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
end

-- A household keeps no camp record, so its place answers through the same
-- rules without a saved warning count: one line per cooldown, only from a
-- member who is really standing there, and never once it has become a fight.
-- A home that is not shared says nothing at all.
-- Standing inside someone's home is a different thing from standing in the
-- street outside it, so it is said first: a household does not greet a visitor
-- and an intruder the same way at the same distance.
function Camps.playerInsideHome(player, home)
    if player == nil or type(home) ~= "table" or home.buildingId == nil then
        return false
    end
    local square = player:getCurrentSquare()
    if square == nil then return false end
    return buildingIdForSquare(square) == tostring(home.buildingId)
end

-- The street and the doorstep are two different moments, so they get two
-- different cooldown keys: greeting a visitor outside must not swallow the line
-- they were owed the moment they stepped in.
function Camps.householdSpeechKey(groupId, inside)
    local id = tostring(groupId or "")
    if id == "" then return nil end
    return id .. (inside == true and ":in" or ":out")
end

function Camps.householdLine(company, distanceSq, disposition, spoken,
    worldAgeHours, nextAllowedHours, playerName, hourOfDay, inside)
    if type(company) ~= "table" or company.home == nil then return nil end
    if type(distanceSq) ~= "number" or distanceSq ~= distanceSq then return nil end
    if distanceSq > REACTION_DISTANCE_SQ then return nil end
    if spoken == true or disposition == "hostile" then return nil end
    if (tonumber(nextAllowedHours) or 0) > (tonumber(worldAgeHours) or 0) then return nil end
    local night = isNightHour(hourOfDay)
    if disposition == "allied" or disposition == "friendly" then
        local known = addressedName(playerName)
        if inside == true and known ~= nil then
            return "welcome", "Come in, " .. known .. ". Mind the door."
        end
        if inside == true then
            return "welcome", "Come in. Mind the door."
        end
        if night and known ~= nil then
            return "welcome", "You are out late, " .. known .. ". Mind the door."
        end
        if night then
            return "welcome", "You are out late. Mind the door."
        end
        if known ~= nil then
            return "welcome", "You are welcome here, " .. known .. ". Mind the door."
        end
        return "welcome", "You are welcome here. Mind the door."
    end
    if inside == true then
        return "warning", "You are in our home. Say what you want."
    end
    if night then
        return "warning", "It is late. Say what you want, then move on."
    end
    return "warning", "This is where we live. Say what you want."
end

-- Long enough that the line stays an event, short enough that a household
-- living by a road you use is not silent for ever after the first visit.
function Camps.householdCooldownHours() return 6 end

-- A household met away from its building still has something to say about the
-- road. It claims no place and invents no destination: it is company, briefly.
-- Declared after the distance constant it reads, so the reach check is real.
function Camps.awayLine(distanceSq, disposition, worldAgeHours, nextAllowedHours,
    playerName, hourOfDay)
    if type(distanceSq) ~= "number" or distanceSq ~= distanceSq then return nil end
    if distanceSq > REACTION_DISTANCE_SQ then return nil end
    if disposition == "hostile" then return nil end
    if (tonumber(nextAllowedHours) or 0) > (tonumber(worldAgeHours) or 0) then return nil end
    local known = addressedName(playerName)
    local night = isNightHour(hourOfDay)
    if disposition == "allied" or disposition == "friendly" then
        if known ~= nil then
            return "welcome", night
                and ("Good to see you out here, " .. known .. ". Careful now.")
                or ("Good to see you out here, " .. known .. ".")
        end
        return "welcome", night and "Good to see you out here. Careful now."
            or "Good to see you out here."
    end
    if night then
        return "warning", "Not a night to be out. Keep moving."
    end
    return "warning", "Road is no place to chat. Keep moving."
end

-- Speech must come from the body the player is looking at. A camp used to be
-- answered by its leader wherever he happened to be, so a guard standing in
-- front of you stayed silent while a voice arrived from thirty tiles away.
-- Pure: the caller supplies only loaded, in-sight candidates.
local SPEAKER_DISTANCE_SQ = 12 * 12
function Camps.nearestSpeaker(candidates, playerX, playerY, maximumDistanceSq, playerZ)
    if type(candidates) ~= "table" then return nil end
    local px, py = tonumber(playerX), tonumber(playerY)
    if px == nil or py == nil then return nil end
    local limit = tonumber(maximumDistanceSq) or SPEAKER_DISTANCE_SQ
    local best, bestDistance = nil, nil
    for _, candidate in ipairs(candidates) do
        if type(candidate) == "table" and candidate.character ~= nil
            and candidate.visible == true
            and (tonumber(playerZ) == nil or candidate.z == nil
                or tonumber(candidate.z) == tonumber(playerZ)) then
            local x, y = tonumber(candidate.x), tonumber(candidate.y)
            if x ~= nil and y ~= nil then
                local distance = (x - px) ^ 2 + (y - py) ^ 2
                if distance <= limit and (bestDistance == nil or distance < bestDistance) then
                    best, bestDistance = candidate, distance
                end
            end
        end
    end
    return best
end

function Camps.speakerDistanceSq() return SPEAKER_DISTANCE_SQ end

-- A camp the player can walk into introduces its owners once. The rule is pure
-- arithmetic over the camp centre, so it is provable without a loaded cell.
local INTRO_DISTANCE_SQ = 12 * 12
function Camps.introductionFor(camp, faction, playerX, playerY)
    if type(camp) ~= "table" or type(faction) ~= "table" then return nil end
    if faction.formationNoticed == true then return nil end
    local name = faction.name
    if type(name) ~= "string" or name == "" then return nil end
    local cx, cy = tonumber(camp.x), tonumber(camp.y)
    local px, py = tonumber(playerX), tonumber(playerY)
    if cx == nil or cy == nil or px == nil or py == nil then return nil end
    local dx, dy = cx - px, cy - py
    if dx * dx + dy * dy > INTRO_DISTANCE_SQ then return nil end
    return "This camp belongs to " .. name .. "."
end

-- Called at the low-frequency population reconciliation boundary.  A camp is
-- only formed when the current faction leader is physically present in an
-- unclaimed building; it never teleports members or claims territory.
function Camps.reconcile(controllers, activeIds, worldAgeHours)
    for _, id in ipairs(activeIds or {}) do
        local faction = KnoxPersistence.getFactionForSurvivor(id)
        local controller = controllers ~= nil and controllers[id] or nil
        if faction ~= nil and faction.kind == "npc" and faction.homeBase == nil
            and faction.leaderId == id and controller ~= nil
            and controller.state ~= "COMBAT" and controller.state ~= "STOPPED" then
            local location = locationFor(controller.character)
            if location ~= nil then
                local camp, result = KnoxPersistence.createFactionCamp(
                    faction.id, location, worldAgeHours
                )
                if camp ~= nil and result == "created" then
                    print("[KnoxSurvivors][Camps] established faction=" .. tostring(faction.id)
                        .. " camp=" .. tostring(camp.id)
                        .. " building=" .. tostring(camp.buildingId))
                elseif camp ~= nil then
                    KnoxPersistence.touchFactionCamp(faction.id, worldAgeHours)
                end
            end
        end
    end
    for _, id in ipairs(activeIds or {}) do
        local controller = controllers ~= nil and controllers[id] or nil
        if controller ~= nil then
            local faction = KnoxPersistence.getFactionForSurvivor(id)
            local camp = faction ~= nil
                and KnoxPersistence.syncFactionCampMembers(faction.id) or nil
            if camp ~= nil and controller.setCampAssignment ~= nil then
                controller:setCampAssignment(
                    camp.id,
                    camp,
                    Camps.memberSlot(camp, id)
                )
            elseif controller.clearCampAssignment ~= nil then
                controller:clearCampAssignment()
            end
        end
    end
    -- Households hold the ground they live in. The assignment is derived from
    -- the shared home already in the ledger and cached per group, so the camp
    -- table keeps its identity between passes and nobody is re-interrupted by a
    -- rebuilt table. No camp record is saved and no faction is invented.
    local homes = rawget(_G, "KnoxHouseholdCamps")
    if homes == nil then
        homes = {}
        _G.KnoxHouseholdCamps = homes
    end
    for _, id in ipairs(activeIds or {}) do
        local controller = controllers ~= nil and controllers[id] or nil
        local company = KnoxPersistence.survivorCompany ~= nil
            and KnoxPersistence.survivorCompany(id) or nil
        if controller ~= nil and controller.setCampAssignment ~= nil
            and company ~= nil and company.home ~= nil then
            local busy = controller.hasLifeIntent ~= nil
                and controller:hasLifeIntent() or false
            local location = Camps.homeLocationFor(controller.character, company.home)
            if location ~= nil and Camps.homeHeldByIntent(busy) then
                local camp = homes[company.groupId]
                if type(camp) ~= "table"
                    or camp.buildingId ~= tostring(location.buildingId) then
                    local group = KnoxPersistence.getTravelGroupFor ~= nil
                        and KnoxPersistence.getTravelGroupFor(id) or nil
                    camp = Camps.homeCampFor(company, location,
                        type(group) == "table" and group.memberIds or nil)
                    if camp ~= nil then homes[company.groupId] = camp end
                end
                if camp ~= nil then
                    controller:setCampAssignment(camp.id, camp,
                        Camps.memberSlot(camp, id), true)
                end
            end
            -- A member who walks out is released: holding the home is a place
            -- to be, not a leash that stops them scavenging or working.
            if (location == nil or busy) and controller.clearCampAssignment ~= nil
                and Camps.isHomeCampId(controller.campId) then
                controller:clearCampAssignment()
            end
        end
    end
    -- Arriving at a camp introduces its owners once, through the existing
    -- notice rail: a place you can walk into is stronger evidence of a faction
    -- than a nameplate you may never have looked at.
    local player = getSpecificPlayer ~= nil and getSpecificPlayer(0) or nil
    if player ~= nil and KnoxPersistence.getCamps ~= nil then
        for _, camp in pairs(KnoxPersistence.getCamps() or {}) do
            local faction = KnoxPersistence.getFaction(camp.factionId)
            local line = Camps.introductionFor(camp, faction, player:getX(), player:getY())
            if line ~= nil then
                faction.formationNoticed = true
                local feed = rawget(_G, "KnoxActivityFeed")
                if feed ~= nil and feed.note ~= nil then pcall(feed.note, line) end
                print("[KnoxSurvivors][Camps] introduced faction=" .. tostring(faction.id))
            end
        end
        -- One place speaks per pass. A camp answers before a household, because
        -- a camp is the stronger claim on ground; whichever really speaks takes
        -- the pass, so the player never hears two places argue at once.
        local spokeThisPass = false
        -- The place speaks first; a resident answers. One speaker per camp, one
        -- line per cooldown, and nothing at all while the shooting has started.
        local playerId = KnoxPersistence.ensurePlayerId ~= nil
            and KnoxPersistence.ensurePlayerId(player) or nil
        local mine = playerId ~= nil and KnoxPersistence.getPlayerFaction ~= nil
            and KnoxPersistence.getPlayerFaction(playerId) or nil
        for _, camp in pairs(KnoxPersistence.getCamps() or {}) do
            local faction = KnoxPersistence.getFaction(camp.factionId)
            if faction ~= nil then
                local dx = (tonumber(camp.x) or 0) - player:getX()
                local dy = (tonumber(camp.y) or 0) - player:getY()
                local disposition = mine ~= nil
                    and KnoxPersistence.getFactionDisposition ~= nil
                    and KnoxPersistence.getFactionDisposition(faction.id, mine.id,
                        tonumber(worldAgeHours) or 0) or "neutral"
                local presence = rawget(_G, "KnoxCampPresence")
                if presence == nil then
                    presence = {}
                    _G.KnoxCampPresence = presence
                end
                local campHours = tonumber(worldAgeHours) or 0
                local distanceSq = Camps.placeDistanceSq(camp.x, camp.y, camp.z,
                    player:getX(), player:getY(), player:getZ())
                    or (Camps.reactionDistanceSq() + 1)
                local state = presence[camp.id]
                if type(state) ~= "table" then
                    state = {}
                    presence[camp.id] = state
                end
                local inside = distanceSq <= Camps.reactionDistanceSq()
                -- Leaving and coming back is a return visit, not a repetition,
                -- so it earns one fresh line before the camp's own day-long
                -- cooldown would allow another. A fifteen-minute floor stops a
                -- player who keeps stepping over the line from farming lines.
                if inside and state.inside ~= true and state.leftAtHours ~= nil
                    and campHours >= (tonumber(state.spokeAtHours) or 0) + 0.25 then
                    state.returning = true
                end
                if not inside and state.inside == true then
                    state.leftAtHours = campHours
                    state.returning = false
                end
                state.inside = inside
                local allowed = camp.reactionNextHours
                if state.returning == true then
                    allowed = (tonumber(state.spokeAtHours) or 0) + 0.25
                end
                local kind, text, advanced = Camps.reactionFor(faction,
                    distanceSq, disposition, worldAgeHours,
                    allowed, camp.warningCount, playerDisplayName(),
                    currentHourOfDay(), state.returning == true)
                -- Whoever is nearest and in sight answers, not the leader
                -- wherever he happens to be. The line is only spent when
                -- somebody says it: an unloaded leader used to burn the
                -- cooldown and climb the ladder in silence.
                local speaker = nil
                do
                    local candidates = {}
                    for _, memberId in ipairs(activeIds or {}) do
                        local memberFaction = KnoxPersistence.getFactionForSurvivor(memberId)
                        local memberController = controllers ~= nil
                            and controllers[memberId] or nil
                        local memberCharacter = memberController ~= nil
                            and memberController.character or nil
                        local memberSquare = memberCharacter ~= nil
                            and memberCharacter:getCurrentSquare() or nil
                        if memberFaction ~= nil and memberFaction.id == faction.id
                            and memberSquare ~= nil
                            and memberController.state ~= "COMBAT"
                            and memberController.state ~= "STOPPED" then
                            candidates[#candidates + 1] = {
                                id = memberId,
                                character = memberCharacter,
                                x = memberSquare:getX(),
                                y = memberSquare:getY(),
                                z = memberSquare:getZ(),
                                visible = player:CanSee(memberCharacter) == true,
                            }
                        end
                    end
                    local chosen = Camps.nearestSpeaker(candidates,
                        player:getX(), player:getY(), nil, player:getZ())
                    speaker = chosen ~= nil and chosen.character or nil
                    if kind == nil and chosen ~= nil then
                        -- Beyond its own doorstep a faction's people are company,
                        -- not a camp: the road line speaks, the ladder does not.
                        local speakerDistanceSq = Camps.placeDistanceSq(chosen.x,
                            chosen.y, chosen.z, player:getX(), player:getY(), player:getZ())
                        if speakerDistanceSq ~= nil then
                            local awayKind, awayText = Camps.awayLine(speakerDistanceSq,
                                disposition, worldAgeHours, camp.reactionNextHours,
                                playerDisplayName(), currentHourOfDay())
                            if awayKind ~= nil then
                                kind, text = awayKind, awayText
                                advanced = nil
                            end
                        end
                    end
                end
                if kind ~= nil and speaker ~= nil then
                    local feed = rawget(_G, "KnoxActivityFeed")
                    local said = false
                    if feed ~= nil and feed.speak ~= nil then
                        local ok, result = pcall(feed.speak, speaker, text)
                        said = ok and result == true
                    end
                    -- A line nobody could hear is not a line: with survivor
                    -- speech switched off the camp keeps its rung and its
                    -- cooldown until the player can actually hear it.
                    if said then
                        if advanced ~= nil then camp.warningCount = advanced end
                        camp.reactionNextHours = campHours
                            + Camps.reactionCooldownHours()
                        state.spokeAtHours = campHours
                        state.returning = false
                        spokeThisPass = true
                    end
                    print("[KnoxSurvivors][Camps] reaction=" .. tostring(kind)
                        .. " faction=" .. tostring(faction.id))
                end
            end
        end
        -- Households keep no camp record, so their place answers through the
        -- same rules: one line per cooldown, from the nearest member the player
        -- can actually see, and never while that member is already fighting.
        local spoken = rawget(_G, "KnoxHouseholdSpoken")
        if spoken == nil then
            spoken = {}
            _G.KnoxHouseholdSpoken = spoken
        end
        local hours = tonumber(worldAgeHours) or 0
        local order, companyByGroup, candidatesByGroup = {}, {}, {}
        for _, id in ipairs(activeIds or {}) do
            local company = KnoxPersistence.survivorCompany ~= nil
                and KnoxPersistence.survivorCompany(id) or nil
            if company ~= nil then
                local speechKey = Camps.householdSpeechKey(company.groupId,
                    Camps.playerInsideHome(player, company.home))
                local entry = speechKey ~= nil and spoken[speechKey] or nil
                local nextAllowed = type(entry) == "table" and tonumber(entry.nextHours) or nil
                if nextAllowed == nil or nextAllowed <= hours then
                    if companyByGroup[company.groupId] == nil then
                        companyByGroup[company.groupId] = company
                        candidatesByGroup[company.groupId] = {}
                        order[#order + 1] = company.groupId
                    end
                    local controller = controllers ~= nil and controllers[id] or nil
                    local character = controller ~= nil and controller.character or nil
                    local square = character ~= nil and character:getCurrentSquare() or nil
                    local okSee, canSee = false, false
                    if square ~= nil and player.CanSee ~= nil then
                        okSee, canSee = pcall(function()
                            return player:CanSee(character) == true
                        end)
                    end
                    if square ~= nil and okSee and canSee == true
                        and controller.state ~= "COMBAT" then
                        candidatesByGroup[company.groupId][#candidatesByGroup[company.groupId] + 1] = {
                            id = id,
                            character = character,
                            x = square:getX(),
                            y = square:getY(),
                            z = square:getZ(),
                            visible = true,
                        }
                    end
                end
            end
        end
        for _, groupId in ipairs(order) do
            if spokeThisPass then break end
            local company = companyByGroup[groupId]
            local chosen = Camps.nearestSpeaker(candidatesByGroup[groupId],
                player:getX(), player:getY(), nil, player:getZ())
            if chosen ~= nil then
                local character = chosen.character
                local disposition = "neutral"
                if playerId ~= nil
                    and KnoxPersistence.isSurvivorHostileToPlayer ~= nil
                    and KnoxPersistence.isSurvivorHostileToPlayer(chosen.id, playerId) then
                    disposition = "hostile"
                elseif playerId ~= nil
                    and KnoxPersistence.getPlayerRelationship ~= nil then
                    local relation = KnoxPersistence.getPlayerRelationship(playerId, chosen.id)
                    if relation ~= nil and (tonumber(relation.trust) or 0) >= 30 then
                        disposition = "friendly"
                    end
                end
                local speakerBuilding = buildingIdForSquare(character:getCurrentSquare())
                local distanceSq = Camps.placeDistanceSq(chosen.x, chosen.y,
                    chosen.z, player:getX(), player:getY(), player:getZ())
                    or (Camps.reactionDistanceSq() + 1)
                local atPlace = Camps.speaksForPlace(company, speakerBuilding)
                local inside = Camps.playerInsideHome(player, company.home)
                local speechKey = Camps.householdSpeechKey(groupId, inside)
                local kind, text
                if atPlace then
                    kind, text = Camps.householdLine(company,
                        distanceSq, disposition, false, hours, nil,
                        playerDisplayName(), currentHourOfDay(), inside)
                else
                    kind, text = Camps.awayLine(distanceSq, disposition, hours, nil,
                        playerDisplayName(), currentHourOfDay())
                end
                if kind ~= nil and speechKey ~= nil then
                    -- They look at you before they speak. A person who talks
                    -- to your back reads as a bug, not a neighbour.
                    pcall(function()
                        character:faceLocationF(player:getX(), player:getY())
                    end)
                    local feed = rawget(_G, "KnoxActivityFeed")
                    local said = false
                    if feed ~= nil and feed.speak ~= nil then
                        local ok, result = pcall(feed.speak, character, text)
                        said = ok and result == true
                    end
                    if said then
                        spoken[speechKey] = {
                            nextHours = hours + Camps.householdCooldownHours(),
                        }
                    end
                    print("[KnoxSurvivors][Camps] household=" .. tostring(kind)
                        .. " group=" .. tostring(groupId))
                end
            end
        end
    end
end

return Camps
