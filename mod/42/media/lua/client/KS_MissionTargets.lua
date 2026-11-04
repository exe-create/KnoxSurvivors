require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_Persistence"

-- Where a player-issued base mission can go, chosen from the Missions tab.
-- `KnoxSurvivorAutonomy.dispatchBaseScout` needs a real loaded square (the
-- destination label, the watchability test and the travel estimate all read it),
-- so this owner lists the buildings the player can actually see around them and
-- never invents a far target from the ledger. Building what the player already
-- sees keeps the order, the search area and the item results tied to real world
-- state.
local Targets = rawget(_G, "KnoxMissionTargets") or {}
_G.KnoxMissionTargets = Targets

-- Same radius the watchable-mission test uses, so a listed place can actually be
-- watched. The ring scan stops early once it has enough places near the player.
Targets.MAX_DISTANCE = 40
Targets.MAX_RESULTS = 8
-- A map click sends the crew to search ground, not one house. Twenty tiles each
-- way covers a row of houses and a yard; the executor clamps to 4..40.
Targets.AREA_RADIUS = 20
-- A hard bound on visited squares: the scan is one-off (on a menu action), not a
-- per-frame cost, and a dense town must not turn it into a full-cell walk.
Targets.MAX_SQUARES = 2600

-- Mission types the dispatch owner accepts, with the wording the base orders
-- menu already uses. Party size is a property of one order, not a new order.
Targets.MISSION_CHOICES = {
    { id = "scout", name = "Scout the area" },
    { id = "food", name = "Food run" },
    { id = "medicine", name = "Medical run" },
    { id = "tools", name = "Tool run" },
    { id = "weapons", name = "Weapon run" },
    { id = "building", name = "Material run" },
}

Targets.PARTY_CHOICES = {
    { id = "1", name = "One resident" },
    { id = "2", name = "Two residents" },
    { id = "3", name = "Three residents" },
}

-- Why a base cannot send anyone, in the player's words. The reasons come from
-- the dispatch owner's own availability check, so the tab never promises a crew
-- the order would then refuse.
-- Why a resident is not on the crew list. One sentence per predicate in the
-- dispatch owner, so the menu explains the same fact that excluded them.
Targets.EXCLUSION_TEXT = {
    not_at_base = "not at base",
    not_your_survivor = "not yours to send",
    not_loaded = "not in the world",
    busy = "busy",
}

Targets.AVAILABILITY_TEXT = {
    dispatch_unavailable = "That order could not be checked: no loaded base or player was available.",
    invalid_mission = "That is not a mission the base can be sent on.",
    no_base_residents = "No resident is at this base right now.",
    need_loaded_base_resident = "None of this base's residents are in the loaded world right now.",
    checkpoint_base = "A checkpoint holds its road instead of sending people away.",
    need_visible_destination = "A supply run needs a destination you can see.",
    need_settled_resident = "Everyone in sight is busy; a supply run needs a resident who is free.",
}

-- Party sizes are trimmed to the crew that could actually go. Asking for
-- three residents when one is at the base set the player up to watch a smaller
-- party leave, which reads as a silent failure; the dispatch still caps at three.
function Targets.partyChoices(available)
    local limit = math.floor(tonumber(available) or 0)
    if limit < 1 then return {} end
    if limit > #Targets.PARTY_CHOICES then limit = #Targets.PARTY_CHOICES end
    local choices = {}
    for index = 1, limit do choices[index] = Targets.PARTY_CHOICES[index] end
    return choices
end

function Targets.availabilityText(reason)
    local text = Targets.AVAILABILITY_TEXT[tostring(reason)]
    if text ~= nil then return text end
    return "Nobody could be sent: "
        .. (tostring(reason or "unknown reason"):gsub("_", " ")) .. "."
end

-- Injectable for the fixture; the real answer comes from the dispatch owner so
-- the pre-check and the order cannot disagree about who is free.
function Targets.availability(base, missionType, square, options)
    options = type(options) == "table" and options or {}
    if options.availability ~= nil then
        return options.availability(base, missionType, square)
    end
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    if autonomy == nil or autonomy.baseMissionAvailability == nil then
        return 0, "dispatch_unavailable"
    end
    return autonomy.baseMissionAvailability(options.player,
        base ~= nil and base.id or nil, missionType, square)
end

local function safe(call, fallback)
    local ok, value = pcall(call)
    if ok then return value end
    return fallback
end

local function trimmed(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function buildingOf(square)
    if square == nil or square.getBuilding == nil then return nil end
    return safe(function() return square:getBuilding() end, nil)
end

-- A stable identity for one building, so many of its squares collapse to one
-- destination. Native identity first; the coordinates are only a fallback shape.
local function buildingKey(building, square)
    if building ~= nil then
        local id = ""
        if type(building.getIDString) == "function" then
            id = trimmed(safe(function() return building:getIDString() end, ""))
        end
        if id ~= "" then return id end
        if type(building.getID) == "function" then
            local number = safe(function() return building:getID() end, nil)
            if tonumber(number) ~= nil then
                return "building:" .. tostring(number)
            end
        end
    end
    if square == nil then return nil end
    return "square:" .. tostring(square:getX()) .. ":" .. tostring(square:getY())
        .. ":" .. tostring(square:getZ())
end

local function buildingLabel(building, square)
    local name = ""
    if building ~= nil then
        local def = safe(function() return building:getDef() end, nil)
        if def ~= nil then name = trimmed(safe(function() return def:getName() end, "")) end
    end
    if name == "" then name = "Building" end
    name = name:sub(1, 1):upper() .. name:sub(2)
    if square == nil then return name end
    return name .. " (" .. tostring(square:getX()) .. ", " .. tostring(square:getY()) .. ")"
end

-- The area label is deliberately not a building name: the order covers ground,
-- and the crew decides which houses inside it are worth entering.
function Targets.areaLabel(square)
    if square == nil then return "Search area" end
    return "Search area (" .. tostring(square:getX()) .. ", "
        .. tostring(square:getY()) .. ")"
end

-- A mission names people, not a headcount. Names come from the durable
-- identity so the order, the departure line and the Missions tab agree.
function Targets.crewName(id)
    local identity = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorIdentity ~= nil
        and safe(function() return KnoxPersistence.getSurvivorIdentity(id) end, nil) or nil
    local forename = identity ~= nil and trimmed(identity.forename) or ""
    local surname = identity ~= nil and trimmed(identity.surname) or ""
    local name = trimmed(forename .. " " .. surname)
    return name ~= "" and name or "Survivor"
end

-- How long a remembered crew keeps its shortcut. Six game days covers a week's
-- worth of repeat errands without offering a team the player last sent a season
-- ago; past that the row is simply absent rather than wrong.
Targets.LAST_CREW_HOURS = 24 * 6

function Targets.lastCrewFresh(ids, atHours, nowHours)
    if type(ids) ~= "table" then return nil end
    local at, now = tonumber(atHours), tonumber(nowHours)
    if at ~= nil and now ~= nil and now - at > Targets.LAST_CREW_HOURS then return nil end
    return ids
end

-- How old the remembered crew is, in the shortest honest form. A shortcut that
-- will expire in a few hours should say so rather than vanish one day with no
-- warning; a crew from an older save has no recorded age and says nothing.
function Targets.lastCrewAgeText(atHours, nowHours)
    local at, now = tonumber(atHours), tonumber(nowHours)
    if at == nil or now == nil then return nil end
    local hours = now - at
    if hours < 1 then return "just now" end
    if hours < 24 then return tostring(math.floor(hours)) .. "h ago" end
    return tostring(math.floor(hours / 24)) .. "d ago"
end

-- Pick the crew by name, one person at a time. The picker answers a single
-- entry, so each round shows the remaining residents plus a finish entry, and the
-- prompt names the crew so far. The first pick is required; a later round stops
-- early when the player says so, so a two-person sweep does not need a
-- three-person roster.
function Targets.crewPick(crew, options, choose, finish)
    options = type(options) == "table" and options or {}
    local nameOf = options.crewName or Targets.crewName
    local order, names, selected = {}, {}, {}
    for _, id in ipairs(type(crew) == "table" and crew or {}) do
        names[id] = tostring(nameOf(id) or "Survivor")
        order[#order + 1] = id
    end
    local limit = math.min(#order, 3)
    -- The remembered crew, kept only for names this order could still send. A
    -- stale id is dropped rather than offered and then refused, and counting the
    -- drops lets the row say so instead of quietly shrinking.
    local previous, dropped = {}, 0
    local fresh = Targets.lastCrewFresh(options.lastCrew, options.lastCrewAt, options.now)
    for _, id in ipairs(type(fresh) == "table" and fresh or {}) do
        if names[id] == nil then
            dropped = dropped + 1
        elseif #previous < limit then
            local duplicate = false
            for _, other in ipairs(previous) do
                if tostring(other) == tostring(id) then duplicate = true break end
            end
            if not duplicate then previous[#previous + 1] = id end
        end
    end
    local confirmAndSend
    local function ask()
        -- A full crew does not end the flow: the last round offers only
        -- take-backs and finish, so a mistake is fixable without starting over.
        if limit == 0 then return finish(selected) end
        local isGoing, count = {}, 0
        for _, id in ipairs(selected) do isGoing[id] = true; count = count + 1 end
        local full = count >= limit
        -- One row per resident, not a pick list plus a duplicate remove list: the
        -- same row adds them, shows that they are going, and takes them back. A
        -- full crew keeps four rows instead of seven.
        local entries = {}
        if count == 0 and #previous > 0 then
            local remembered = {}
            for index, id in ipairs(previous) do remembered[index] = names[id] end
            -- Action first, then who, then how many: "Same as last time: Ann,
            -- Ben (2)". When someone from last time cannot go, the count becomes
            -- "1 of 2" so the row admits the drop, and the exclusion line above
            -- already says why.
            local suffix = dropped > 0
                and (" (" .. tostring(#previous) .. " of "
                    .. tostring(#previous + dropped) .. ")")
                or (" (" .. tostring(#previous) .. ")")
            local age = Targets.lastCrewAgeText(options.lastCrewAt, options.now)
            entries[#entries + 1] = { id = "same",
                name = "Same as last time: " .. table.concat(remembered, ", ") .. suffix
                    .. (age ~= nil and (", " .. age) or "") }
        end
        for _, id in ipairs(order) do
            if isGoing[id] then
                entries[#entries + 1] = { id = "remove:" .. tostring(id),
                    name = names[id] .. " (going)" }
            elseif not full then
                entries[#entries + 1] = { id = "pick:" .. tostring(id), name = names[id] }
            end
        end
        entries[#entries + 1] = { id = "done", name = "Finish picking" }
        local going = {}
        for _, id in ipairs(selected) do going[#going + 1] = names[id] end
        local prompt
        if #selected == 0 then
            prompt = "Who should go?"
        elseif full then
            prompt = "Going: " .. table.concat(going, ", ") .. ". Remove one, or finish."
        else
            prompt = "Going: " .. table.concat(going, ", ") .. ". Anyone else?"
        end
        choose(prompt, entries, function(choice)
            local value = tostring(choice or "")
            if value == "done" or value == "" then return confirmAndSend() end
            if value == "same" then
                selected = {}
                for _, id in ipairs(previous) do selected[#selected + 1] = id end
                return confirmAndSend()
            end
            if value:sub(1, 5) == "pick:" then
                local wanted = value:sub(6)
                for _, id in ipairs(order) do
                    if tostring(id) == wanted then
                        local present = false
                        for _, chosen in ipairs(selected) do
                            if tostring(chosen) == wanted then present = true break end
                        end
                        if not present and #selected < limit then
                            selected[#selected + 1] = id
                        end
                        break
                    end
                end
                return ask()
            end
            if value:sub(1, 7) == "remove:" then
                local unwanted = value:sub(8)
                for index, id in ipairs(selected) do
                    if tostring(id) == unwanted then
                        table.remove(selected, index)
                        break
                    end
                end
                return ask()
            end
            ask()
        end, "Crew")
    end
    -- A last look before an order that cannot be taken back: the names and the
    -- count in one line, and a way to change the crew without losing the picks.
    confirmAndSend = function()
        if #selected == 0 then return finish(selected) end
        local going = {}
        for index, id in ipairs(selected) do going[index] = names[id] end
        choose("Send " .. table.concat(going, ", ") .. "?",
            { { id = "send", name = "Send them" },
              { id = "change", name = "Change the crew" } },
            function(choice)
                if tostring(choice or "") == "send" then return finish(selected) end
                ask()
            end, "Confirm")
    end
    ask()
end

-- One line naming the residents who cannot go and why. Returns nil when
-- nobody is excluded, so a full roster adds no noise. A big base is trimmed to
-- the first three plus a count: the line has to stay readable in a chat feed,
-- and the exact tail is rarely the interesting part.
function Targets.exclusionText(excluded, nameOf)
    if type(excluded) ~= "table" or #excluded == 0 then return nil end
    local parts, limit = {}, math.min(#excluded, 3)
    for index = 1, limit do
        local entry = excluded[index]
        local name = type(nameOf) == "function" and nameOf(entry.id) or nil
        local reason = Targets.EXCLUSION_TEXT[tostring(entry.reason)] or "not available"
        parts[#parts + 1] = tostring(name or "Survivor") .. " (" .. reason .. ")"
    end
    local remaining = #excluded - limit
    if remaining > 0 then
        parts[#parts + 1] = "and " .. tostring(remaining) .. " more"
    end
    return "Not going: " .. table.concat(parts, ", ") .. "."
end

-- Ring scan from the player outward. The first square found for a building is
-- the nearest one, so the representative square is the closest part of it. The
-- player's own home is skipped: sending a crew to search the house they live in
-- is not a mission.
function Targets.scan(cell, originX, originY, originZ, options)
    options = type(options) == "table" and options or {}
    local x0, y0 = tonumber(originX), tonumber(originY)
    if cell == nil or cell.getGridSquare == nil or x0 == nil or y0 == nil then return {} end
    local z = tonumber(originZ) or 0
    local radius = math.floor(math.max(1, math.min(Targets.MAX_DISTANCE,
        tonumber(options.radius) or Targets.MAX_DISTANCE)))
    local limit = math.floor(math.max(1, math.min(Targets.MAX_RESULTS,
        tonumber(options.limit) or Targets.MAX_RESULTS)))
    local skip = trimmed(options.skipBuildingId)
    local seen, places, scanned, stop = {}, {}, 0, false
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if distance == 0 or math.abs(dx) == distance or math.abs(dy) == distance then
                    scanned = scanned + 1
                    if scanned > Targets.MAX_SQUARES then
                        stop = true
                        break
                    end
                    local square = safe(function()
                        return cell:getGridSquare(x0 + dx, y0 + dy, z)
                    end, nil)
                    local building = buildingOf(square)
                    if building ~= nil then
                        local key = buildingKey(building, square)
                        if key ~= nil and seen[key] == nil then
                            local buildingId = ""
                            if type(building.getIDString) == "function" then
                                buildingId = trimmed(safe(function()
                                    return building:getIDString()
                                end, ""))
                            end
                            if skip == "" or buildingId ~= skip then
                                seen[key] = true
                                places[#places + 1] = {
                                    id = key,
                                    name = buildingLabel(building, square),
                                    x = square:getX(), y = square:getY(), z = square:getZ(),
                                    distance = distance,
                                    square = square,
                                }
                            else
                                seen[key] = true
                            end
                        end
                    end
                end
            end
            if stop then break end
        end
        if stop or #places >= limit then break end
    end
    table.sort(places, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return tostring(a.id) < tostring(b.id)
    end)
    if #places > limit then
        local bounded = {}
        for index = 1, limit do bounded[index] = places[index] end
        return bounded
    end
    return places
end

function Targets.visibleBuildings(playerNum, options)
    options = type(options) == "table" and options or {}
    local player = options.player
    if player == nil and getSpecificPlayer ~= nil then
        player = getSpecificPlayer(tonumber(playerNum) or 0)
    end
    if player == nil then return {} end
    local cell = options.cell
    if cell == nil and getCell ~= nil then cell = getCell() end
    local square = nil
    if player.getCurrentSquare ~= nil then
        square = safe(function() return player:getCurrentSquare() end, nil)
    end
    local x, y, z
    if square ~= nil then
        x, y, z = square:getX(), square:getY(), square:getZ()
    else
        x, y = safe(function() return player:getX() end, nil),
            safe(function() return player:getY() end, nil)
        z = safe(function() return player:getZ() end, 0)
    end
    return Targets.scan(cell, x, y, z, options)
end

-- The Missions-tab flow: place, then mission type, then party size, then the one
-- existing dispatch owner. Every step is a chooser; a cancel at any step issues
-- nothing. All collaborators are injectable so the ordering is proven offline.
function Targets.dispatchFlow(playerNum, options)
    options = type(options) == "table" and options or {}
    local notice = options.notice
    if notice == nil then
        notice = function(text)
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then feed.event(tostring(text)) end
        end
    end
    local choose = options.choose
    if choose == nil then
        choose = function(prompt, entries, callback, title)
            local picker = rawget(_G, "KnoxBasePicker")
            if picker == nil or picker.choose == nil then return false end
            return picker.choose(tonumber(playerNum) or 0, prompt, entries, callback, title)
        end
    end
    local player = options.player
    if player == nil and getSpecificPlayer ~= nil then
        player = getSpecificPlayer(tonumber(playerNum) or 0)
    end
    if player == nil then
        notice("No player is available to give that order.")
        return false
    end
    -- The resolved player travels with the options, so the crew check asks about
    -- the same person even when the caller left the player implicit.
    options.player = player
    local base = options.base
    if base == nil and KnoxBaseManager ~= nil and KnoxBaseManager.getForOwner ~= nil
        and KnoxPersistence ~= nil and KnoxPersistence.ensurePlayerId ~= nil then
        local ownerId = KnoxPersistence.ensurePlayerId(player)
        if ownerId ~= nil then base = KnoxBaseManager.getForOwner("player", ownerId) end
    end
    if base == nil then
        notice("You have no base to send a mission from.")
        return false
    end
    -- A map click names the destination. The clicked square still resolves to its
    -- building, so the mission, its search area and its label are the same record
    -- the Missions tab would have produced from a nearby scan.
    local anchor = options.anchor
    local places
    if anchor ~= nil then
        -- A clicked point names ground, not a building: the crew searches the
        -- area around it and may cover several houses in one order. The radius
        -- travels with the place so the dispatcher can record it.
        places = {{
            id = "area:" .. tostring(anchor:getX()) .. ":" .. tostring(anchor:getY())
                .. ":" .. tostring(anchor:getZ()),
            name = Targets.areaLabel(anchor),
            x = anchor:getX(), y = anchor:getY(), z = anchor:getZ(),
            distance = 0, radius = Targets.AREA_RADIUS, square = anchor,
        }}
    else
        local skipBuildingId = nil
        if type(base.home) == "table" then skipBuildingId = base.home.buildingId end
        places = Targets.visibleBuildings(playerNum, {
            player = player, cell = options.cell, skipBuildingId = skipBuildingId,
        })
        if #places == 0 then
            notice("No building in sight to send a mission to. Walk closer or use the world menu.")
            return false
        end
    end
    local dispatch = options.dispatch
    if dispatch == nil then
        dispatch = function(targetBase, square, partySize, missionType, radius, label,
            members)
            local menu = rawget(_G, "KnoxBaseContextMenu")
            if menu == nil or menu.dispatchScout == nil then return false end
            menu.dispatchScout(player, targetBase, square, partySize, missionType,
                radius, label, members)
            return true
        end
    end
    local function askMission(place)
        -- Returns the chooser result: the map-click path ends here, so a nil
        -- return would read as a refused order even though the chooser opened.
        return choose("What should they do there?", Targets.MISSION_CHOICES, function(missionId)
            local missionType = nil
            for _, candidate in ipairs(Targets.MISSION_CHOICES) do
                if tostring(candidate.id) == tostring(missionId) then missionType = candidate.id break end
            end
            if missionType == nil then return end
            -- Ask whether anyone can go before asking for a party size: an
            -- impossible order is explained here instead of failing after the
            -- last question.
            local available, reason = Targets.availability(base, missionType, place.square, options)
            -- Ask who, not how many: the same crew the dispatcher would pick, in
            -- its ranking order, so a player can see the people they are sending.
            local crew = options.crew
            if crew == nil then
                local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
                if autonomy ~= nil and autonomy.missionCrewIds ~= nil then
                    crew = autonomy.missionCrewIds(player, base ~= nil and base.id or nil,
                        missionType, place.square)
                end
            end
            -- Say who stays behind before the first pick, so an absent name is
            -- explained rather than silently missing from the list.
            local excluded = options.excluded
            if excluded == nil then
                local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
                if autonomy ~= nil and autonomy.missionCrewExclusions ~= nil then
                    excluded = autonomy.missionCrewExclusions(player,
                        base ~= nil and base.id or nil, missionType, place.square)
                end
            end
            if options.now == nil and rawget(_G, "getGameTime") ~= nil
                and getGameTime() ~= nil then
                options.now = getGameTime():getWorldAgeHours()
            end
            local staying = Targets.exclusionText(excluded,
                options.crewName or Targets.crewName)
            if staying ~= nil then notice(staying) end
            -- Offer the crew that last went from this base, so a repeat order is
            -- one row and a confirmation instead of the whole picker again.
            if options.lastCrew == nil then
                local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
                if autonomy ~= nil and autonomy.lastMissionCrew ~= nil then
                    local ids, at = autonomy.lastMissionCrew(
                        base ~= nil and base.id or nil, missionType)
                    options.lastCrew, options.lastCrewAt = ids, at
                end
            end
            if type(crew) == "table" and #crew > 0 then
                return Targets.crewPick(crew, options, choose, function(members)
                    if #members == 0 then
                        notice("Nobody is going on that mission.")
                        return
                    end
                    dispatch(base, place.square, #members, missionType,
                        place.radius, place.name, members)
                end)
            end
            -- No crew list available (older caller, or a base with no readable
            -- roster): fall back to the count question rather than refusing.
            local choices = Targets.partyChoices(available)
            if #choices == 0 then
                notice(Targets.availabilityText(reason))
                return
            end
            choose("How many residents?", choices, function(partyId)
                local partySize = tonumber(partyId)
                if partySize == nil then return end
                dispatch(base, place.square, partySize, missionType, place.radius, place.name)
            end, "Party Size")
        end, "Mission Type")
    end
    -- A clicked destination is already chosen; only the order and the party are
    -- left to ask. Skipping the place chooser is the whole difference.
    if anchor ~= nil then return askMission(places[1]) end
    return choose("Send a mission to which place?", places, function(placeId)
        local place = nil
        for _, candidate in ipairs(places) do
            if tostring(candidate.id) == tostring(placeId) then place = candidate break end
        end
        if place == nil then return end
        askMission(place)
    end, "Send a Mission")
end

return Targets
