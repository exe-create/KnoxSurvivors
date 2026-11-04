require "KS_ThreatClassifier"
pcall(function() require "KS_DebugLog" end)
local function isCorpseProxy(character)
    local threats = rawget(_G, "KnoxThreatClassifier")
    return threats ~= nil and threats.isCorpseProxy(character) or false
end

local function diagEvent(id, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("faction", id, event, details) end)
    end
end

require "KS_KnoxEvents"
require "KS_SurvivorRuntime"
require "KS_SurvivorNeeds"
require "KS_FirearmSupport"
require "KS_BaseManager"
require "KS_WorldPopulation"

local Runtime = rawget(_G, "KnoxEventRuntime") or {}
_G.KnoxEventRuntime = Runtime
local cursor = 0
local nextDispatchCheck = {}
local READY_STATES = { IDLE = true, BASE_IDLE = true, BASE_PATROL = true, BASE_RETURN = true }
local ENTRY_OFFSETS = { { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 2, 2 } }
-- A warning needs someone at the home to notice the signs; a player across the
-- county is not told about a column they cannot see. The World tab still shows
-- the live event wherever the player is.
local RAID_WARNING_RADIUS = 60

local function finished(event)
    return event == nil or event.phase == "completed" or event.phase == "failed"
end

local function owns(id, eventId)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    return duty ~= nil and duty.eventId == eventId
end

local function indexOf(event, id)
    for index, member in ipairs(event.memberIds or {}) do if member == id then return index end end
end

local function sourceHome(event)
    if event.kind ~= "faction_raid" then return nil end
    local base = KnoxPersistence.getBase(event.sourceBaseId)
    return base ~= nil and base.ownerKind == "faction" and base.ownerId == event.sourceFactionId and base or nil
end

local function partyLeavesCounty(event)
    if event == nil or event.kind ~= "faction_entry" then return false end
    local policy = KnoxEventFactions ~= nil and KnoxEventFactions.get(event.policyId) or nil
    return policy ~= nil and policy.persistsAfterEvent == false
end

local function areaFor(event, returning)
    if event.kind == "faction_entry" then
        local location = returning and event.entryLocation or event.targetLocation
        if type(location) ~= "table" then return nil end
        return { minX = location.x, minY = location.y, width = 1, height = 1, z = location.z }
    end
    local base = returning and sourceHome(event) or nil
    if not returning then base = KnoxPersistence.getBase(event.targetBaseId) end
    return base ~= nil and base.home or nil
end

function Runtime.destination(event, id)
    local slot = indexOf(event, id)
    local returning = event.phase == "withdrawing"
    local area = areaFor(event, returning)
    if slot == nil or type(area) ~= "table" then return nil end
    local x, y, w, h = tonumber(area.minX), tonumber(area.minY), tonumber(area.width), tonumber(area.height)
    if x == nil or y == nil or w == nil or h == nil or w < 1 or h < 1 then return nil end
    for _, value in ipairs({ x, y, w, h, area.z or 0 }) do
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    end
    if event.kind == "faction_entry" then
        local offset = ENTRY_OFFSETS[(slot - 1) % #ENTRY_OFFSETS + 1]
        return { x = x + offset[1], y = y + offset[2], z = area.z or 0 }
    end
    if returning then
        return { x = x + math.min(w - 1, 1 + (slot - 1) % math.max(1, math.floor(w - 2))),
            y = y + math.min(h - 1, 1 + math.floor((slot - 1) / math.max(1, math.floor(w - 2)))), z = area.z or 0 }
    end
    -- Separate approach points outside the building; do not aim every member at
    -- one centre tile or require a door to be smashed just to arrive nearby.
    local offset = (slot - 1) * 2
    local source = sourceHome(event)
    source = source ~= nil and source.home or nil
    if source ~= nil then
        if type(source) ~= "table" then return nil end
        for _, key in ipairs({ "minX", "minY", "width", "height" }) do
            local value = source[key]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
        end
    end
    local dx = source ~= nil and source.minX + source.width / 2 - (x + w / 2) or -1
    local dy = source ~= nil and source.minY + source.height / 2 - (y + h / 2) or 0
    if math.abs(dx) >= math.abs(dy) then
        return { x = (dx < 0 and x - 3 or x + w + 2)
                + (dx < 0 and -1 or 1) * math.floor(offset / h),
            y = y + offset % h, z = area.z or 0 }
    end
    return { x = x + offset % w, y = (dy < 0 and y - 3 or y + h + 2)
        + (dy < 0 and -1 or 1) * math.floor(offset / w), z = area.z or 0 }
end

local function currentPlayers()
    local players, specific = {}, rawget(_G, "getSpecificPlayer")
    if type(specific) ~= "function" then return players end
    local countFunction = rawget(_G, "getNumActivePlayers")
    local count = type(countFunction) == "function" and tonumber(countFunction()) or 4
    for index = 0, math.max(0, math.floor(count or 0) - 1) do
        local player = specific(index)
        if player ~= nil and player:getCurrentSquare() ~= nil then players[#players + 1] = player end
    end
    return players
end

local function playerNearArea(area, radius)
    if type(area) ~= "table" then return false end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local width, height = tonumber(area.width), tonumber(area.height)
    if minX == nil or minY == nil or width == nil or height == nil then return false end
    local reach = (tonumber(radius) or 0) * (tonumber(radius) or 0)
    for _, player in ipairs(currentPlayers()) do
        local square = player:getCurrentSquare()
        if square ~= nil then
            local x = math.max(minX, math.min(minX + width - 1, square:getX()))
            local y = math.max(minY, math.min(minY + height - 1, square:getY()))
            local dx, dy = square:getX() - x, square:getY() - y
            if dx * dx + dy * dy <= reach then return true end
        end
    end
    return false
end

-- The warning is written once on the event, then said once on the existing
-- notice rail. A reload is silent because the stamp is durable, and a player
-- who arrives later still gets the fact from the World tab and the home line.
local function announceRaidWarning(event, hours)
    if type(event) ~= "table" or event.kind ~= "faction_raid" then return end
    if event.phase ~= "scheduled" and event.phase ~= "spawning"
        and event.phase ~= "approaching" then return end
    if type(event.warning) == "table" then return end
    local base = KnoxPersistence.getBase(event.targetBaseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area == nil or not playerNearArea(area, RAID_WARNING_RADIUS) then return end
    local warning = KnoxEvents.warnRaid(event.id, event.revision, hours)
    if warning == nil then return end
    local feed = rawget(_G, "KnoxActivityFeed")
    local text = KnoxEvents.raidWarningText(warning)
    if feed ~= nil and feed.note ~= nil and text ~= nil then
        pcall(function()
            feed.note(text, { priority = "danger", group = "Raids", key = "raid:" .. event.id })
        end)
    end
    diagEvent(tostring(event.id), "raid_warning", {
        cause = tostring(warning.cause), direction = tostring(warning.direction),
        strength = tostring(warning.strength), etaHours = warning.etaHours,
    })
end

-- A raid that got inside and worked the objective leaves a report, said once at
-- the home. A column that broke at the gate never had an objective, so it has
-- nothing to report and gets no line; the World tab still records the event.
local function announceRaidAftermath(event, hours)
    if type(event) ~= "table" or event.kind ~= "faction_raid" then return end
    if event.phase ~= "withdrawing" or type(event.objective) ~= "table" then return end
    if type(event.aftermath) == "table" then return end
    local base = KnoxPersistence.getBase(event.targetBaseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area == nil or not playerNearArea(area, RAID_WARNING_RADIUS) then return end
    local stamp = KnoxEvents.markRaidAftermath ~= nil
        and KnoxEvents.markRaidAftermath(event.id, event.revision, hours) or nil
    if stamp == nil then return end
    local text = KnoxEvents.raidAftermathText ~= nil
        and KnoxEvents.raidAftermathText(event, hours) or nil
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.note ~= nil and text ~= nil then
        pcall(function()
            feed.note(text, { priority = "danger", group = "Raids", key = "raid-after:" .. event.id })
        end)
    end
    diagEvent(tostring(event.id), "raid_aftermath", {
        items = stamp.items, outcome = tostring(stamp.outcome or "unknown"),
    })
end

function Runtime.memberReady(controller, base)
    if controller == nil or not READY_STATES[controller.state] then return false, "member_busy" end
    local character = controller.character
    local area = base ~= nil and (base.territory or base.home) or nil
    if character == nil or area == nil then return false, "member_unloaded" end
    local ok, ready, reason = pcall(function()
        local square = character:getCurrentSquare()
        if character:isDead() or square == nil then return false, "member_unloaded" end
        if not KnoxBaseManager.containsSquare(base, square) then
            return false, "member_not_home"
        end
        if not character:getCharacterActions():isEmpty() then return false, "member_busy" end
        local state = KnoxSurvivorNeeds.snapshot(character)
        if state.health < 70 or state.bleedingParts > 0 or state.endurance < 0.5
            or state.fatigue > 0.65 or state.hunger > 0.7 or state.thirst > 0.7 then
            return false, "member_needs_care"
        end
        local weapon = character:getPrimaryHandItem()
        if weapon == nil or not weapon:IsWeapon() or weapon:isBroken() then return false, "member_unarmed" end
        if weapon:isRanged() and not KnoxFirearmSupport.isReady(character, weapon) then
            return false, "member_gun_not_ready"
        end
        return true, "ready"
    end)
    return ok and ready == true, ok and reason or "readiness_unavailable"
end

local function nearDestination(character, destination)
    if character == nil or destination == nil then return false end
    local square = character:getCurrentSquare()
    if square == nil or square:getZ() ~= destination.z then return false end
    local dx, dy = character:getX() - destination.x, character:getY() - destination.y
    return dx * dx + dy * dy <= 9
end

-- Raiders approach from deliberately separated points outside a target base.
-- Once the party has reached that perimeter, ordinary combat may move a member
-- around the home while defending, pursuing a nearby intruder, or surviving a
-- zombie interruption.  Do not keep measuring the objective phase against a
-- single approach tile: that strands a live raid when normal combat correctly
-- takes ownership of movement.
local RAID_TARGET_MARGIN = 12

local function inRaidTargetArea(event, id, character)
    if event == nil or event.kind ~= "faction_raid" then return false end
    local base = KnoxPersistence.getBase(event.targetBaseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if type(area) ~= "table" then return false end
    local x, y, z
    if character ~= nil then
        local square = character:getCurrentSquare()
        if square == nil then return false end
        x, y, z = square:getX(), square:getY(), square:getZ()
    else
        local state = KnoxPersistence.getUnloadedSurvivalState(id)
        if state == nil or state.pendingMaterialization then return false end
        x, y, z = state.virtualX, state.virtualY, state.virtualZ
    end
    local minX, minY = tonumber(area.minX), tonumber(area.minY)
    local width, height = tonumber(area.width), tonumber(area.height)
    local storedMaxX, storedMaxY = tonumber(area.maxX), tonumber(area.maxY)
    local areaZ = tonumber(area.z or (base.home ~= nil and base.home.z)) or 0
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
        or minX == nil or minY == nil or z ~= areaZ then return false end
    local maxX = storedMaxX or (width ~= nil and minX + width - 1)
    local maxY = storedMaxY or (height ~= nil and minY + height - 1)
    if maxX == nil or maxY == nil or maxX < minX or maxY < minY then return false end
    return x >= minX - RAID_TARGET_MARGIN and x <= maxX + RAID_TARGET_MARGIN
        and y >= minY - RAID_TARGET_MARGIN and y <= maxY + RAID_TARGET_MARGIN
end

function Runtime.raidMemberAtTarget(event, id, controller)
    return inRaidTargetArea(event, id, controller ~= nil and controller.character or nil)
end

local function atDestination(id, character, destination)
    if character ~= nil then return nearDestination(character, destination) end
    local state = KnoxPersistence.getUnloadedSurvivalState(id)
    if state == nil or destination == nil then return false end
    local x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
    if x == nil or y == nil or z == nil or z ~= destination.z then return false end
    local dx, dy = x - destination.x, y - destination.y
    return dx * dx + dy * dy <= 9
end

local function returnedHome(id, character, home)
    local area = home ~= nil and (home.territory or home.home) or nil
    if area == nil then return false end
    local x, y, z
    if character ~= nil then
        local square = character:getCurrentSquare()
        if square == nil then return false end
        x, y, z = square:getX(), square:getY(), square:getZ()
    else
        local state = KnoxPersistence.getUnloadedSurvivalState(id)
        if state == nil or state.pendingMaterialization then return false end
        x, y, z = state.virtualX, state.virtualY, state.virtualZ
    end
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    return KnoxBaseManager.containsSquare(home, {
        getX = function() return math.floor(x) end,
        getY = function() return math.floor(y) end,
        getZ = function() return z end,
    })
end

-- A raid that ends is written to the durable log once. The log was defined,
-- capped and read by the faction card, but nothing ever wrote it, so the
-- retaliation cause could never fire. Names come from the records that own
-- them; anything unresolvable stays empty instead of being invented, and the
-- writer's own eventId guard turns the several withdraw reasons a raid can pass
-- through into one row.
local function archiveRaidEnd(event, hours, reason)
    if type(event) ~= "table" or event.kind ~= "faction_raid" then return end
    if KnoxPersistence == nil or KnoxPersistence.recordRaidHistory == nil then return end
    local sourceId = tostring(event.sourceFactionId or event.factionId or "")
    local faction = sourceId ~= "" and KnoxPersistence.getFaction ~= nil
        and KnoxPersistence.getFaction(sourceId) or nil
    local base = event.targetBaseId ~= nil and KnoxPersistence.getBase ~= nil
        and KnoxPersistence.getBase(event.targetBaseId) or nil
    local outcome = type(event.objective) == "table"
        and tostring(event.objective.outcome or "") or ""
    if outcome == "" then outcome = tostring(reason or "unknown") end
    pcall(KnoxPersistence.recordRaidHistory, {
        eventId = tostring(event.id or ""),
        atHours = hours,
        sourceFactionId = sourceId,
        sourceName = faction ~= nil and tostring(faction.name or "") or "",
        targetBaseId = tostring(event.targetBaseId or ""),
        targetName = base ~= nil and tostring(base.name or "") or "",
        outcome = outcome,
    })
end

local function change(event, phase, hours, reason)
    local result, status = KnoxEvents.transition(event.id, event.revision, phase, hours, reason)
    if result ~= nil and status == "changed" then
        print("[KnoxSurvivors][Events] id=" .. event.id .. " phase=" .. phase .. " reason=" .. tostring(reason))
        diagEvent(tostring(event.id), "phase_" .. tostring(phase), {
            kind = event.kind, reason = tostring(reason),
            members = event.memberIds ~= nil and #event.memberIds or nil,
        })
        if phase == "withdrawing" then archiveRaidEnd(result, hours, reason) end
    end
    return result
end

function Runtime.storedMemberReady(id, home, hours)
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.isStoredNpcWeaponReady == nil then return false, "stored_readiness_unavailable" end
    if not KnoxPersistence.isSurvivorAlive(id) or KnoxSurvivorRuntime.getCharacter(id) ~= nil then
        return false, "member_not_stored"
    end
    local state, record = KnoxPersistence.getUnloadedSurvivalState(id), KnoxPersistence.getRecord(id)
    if state == nil or state.pendingMaterialization or type(record) ~= "string" or record == "" then
        return false, "real_survival_snapshot_required"
    end
    -- Let the existing offscreen scheduler catch up, rather than dispatch from
    -- old pre-hibernation needs or advance physiology twice in separate systems.
    for _, key in ipairs({ "lastHours", "health", "bleedingParts", "endurance", "fatigue", "hunger", "thirst",
        "virtualX", "virtualY", "virtualZ" }) do
        local value = state[key]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
            return false, "stored_state_unavailable"
        end
    end
    if state.lastHours > hours or hours - state.lastHours > 0.25 then return false, "stored_state_stale" end
    if state.health < 70 or state.health > 100 or state.bleedingParts ~= 0
        or state.endurance < 0.5 or state.endurance > 1 or state.fatigue < 0 or state.fatigue > 0.65
        or state.hunger < 0 or state.hunger > 0.7 or state.thirst < 0 or state.thirst > 0.7
        or state.restMode ~= nil or state.baseReturn ~= nil then return false, "member_needs_care" end
    if not returnedHome(id, nil, home) then return false, "member_not_home" end
    -- Java also checks active ownership and encoded identity. Lua's controller
    -- lookup alone cannot exclude a body that is mid-activation/retirement.
    local ok, ready = pcall(function() return bridge:isStoredNpcWeaponReady(id, record) end)
    return ok and ready == true, ok and (ready and "ready" or "stored_weapon_unready") or "stored_readiness_unavailable"
end

local function hasLoadedRaidMember(event, controllers)
    for _, id in ipairs(event.memberIds or {}) do
        local controller = controllers ~= nil and controllers[id] or nil
        if controller ~= nil and controller.character ~= nil then return true end
    end
    return false
end

function Runtime.dispatch(event, controllers, hours)    if event == nil or (event.phase ~= "scheduled" and event.phase ~= "spawning") then return false, "invalid_phase" end
    if hours < event.dueAtHours then return false, "not_due" end
    local valid, why = KnoxEvents.validate(event)
    if not valid then return false, why end
    if event.kind == "faction_entry" then
        if event.phase == "scheduled" then
            event = change(event, "spawning", hours, "selecting_event_entry")
            if event == nil then return false, "event_changed" end
        end
        if hours < (tonumber(event.nextAttemptAtHours) or 0) then return false, "entry_retry_cooldown" end
        local origins, reason = KnoxWorldPopulation.eventEntryOrigins(event.targetLocation,
            event.partySize, event.id, { players = currentPlayers(), minimumTargetDistance = 100,
                maximumTargetDistance = 600, minimumPlayerDistance = 100 })
        if origins == nil then
            KnoxEvents.deferFactionEntry(event.id, event.revision, hours, reason)
            return false, reason
        end
        local faction, created = KnoxEventFactions.createEntry(event.policyId, event.id, origins, hours)
        if faction == nil then
            KnoxEvents.deferFactionEntry(event.id, event.revision, hours, created)
            return false, created
        end
        local committed, result = KnoxEvents.commitFactionEntry(event.id, event.revision, faction.id, hours)
        return committed ~= nil, committed ~= nil and "dispatched" or result
    end
    local home = KnoxPersistence.getBase(event.sourceBaseId)
    for _, id in ipairs(event.memberIds) do
        if not owns(id, event.id) then
            local ready, reason
            if controllers[id] ~= nil then ready, reason = Runtime.memberReady(controllers[id], home)
            else ready, reason = Runtime.storedMemberReady(id, home, hours) end
            if not ready then return false, reason end
        end
    end
    if event.phase == "scheduled" then
        event = change(event, "spawning", hours, "claiming_real_members")
        if event == nil then return false, "event_changed" end
    end
    -- Single Lua callback, no yield: all-member persistence validation precedes
    -- any duty write. A restored spawning phase can repeat this idempotently.
    local claimed, reason = KnoxPersistence.claimEventDuty(event.id, hours)
    if not claimed then
        change(event, "withdrawing", hours, reason)
        return false, reason
    end
    event = change(event, "approaching", hours, "real_members_dispatched")
    return event ~= nil, event ~= nil and "dispatched" or "event_changed"
end

local function objectiveValid(event)
    return event ~= nil and (event.kind == "faction_raid" and KnoxEvents.isValidRaidObjective(event)
        or event.kind == "faction_entry" and KnoxEvents.isValidFactionEntryObjective(event))
end

local function secureAreaThreatCount(event)
    local target = type(event) == "table" and event.targetLocation or nil
    local cell = getCell ~= nil and getCell() or nil
    local zombies = cell ~= nil and cell:getZombieList() or nil
    if target == nil or zombies == nil then return nil end
    local count, radiusSquared = 0, 18 * 18
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local square = zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombie:getCurrentSquare() or nil
        if square ~= nil and square:getZ() == target.z then
            local dx, dy = square:getX() - target.x, square:getY() - target.y
            if dx * dx + dy * dy <= radiusSquared then
                count = count + 1
                if count >= 24 then return 24 end
            end
        end
    end
    -- Patrols keeping the peace also count hostile survivors menacing the
    -- neighborhood, so the area only reads clear when both are gone.
    if count < 24 and KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.activeIds ~= nil then
        local players = currentPlayers()
        for _, id in ipairs(KnoxSurvivorRuntime.activeIds()) do
            local character = KnoxSurvivorRuntime.getCharacter ~= nil
                and KnoxSurvivorRuntime.getCharacter(id) or nil
            local square = character ~= nil and character:getCurrentSquare() or nil
            if square ~= nil and square:getZ() == target.z then
                local dx, dy = square:getX() - target.x, square:getY() - target.y
                if dx * dx + dy * dy <= radiusSquared then
                    for _, player in ipairs(players) do
                        local playerId = KnoxPersistence.ensurePlayerId ~= nil
                            and KnoxPersistence.ensurePlayerId(player) or nil
                        if playerId ~= nil and KnoxPersistence.isSurvivorHostileToPlayer ~= nil
                            and KnoxPersistence.isSurvivorHostileToPlayer(id, playerId) then
                            count = count + 1
                            break
                        end
                    end
                    if count >= 24 then return 24 end
                end
            end
        end
    end
    return count
end

function Runtime.reviewObjective(event, hours)
    event = event ~= nil and KnoxEvents.get(event.id) or nil
    if event == nil or event.phase ~= "objective" then return end
    if not objectiveValid(event) then change(event, "withdrawing", hours, "objective_state_missing"); return end
    if event.kind == "faction_entry" then
        if event.objective.kind == "secure_area"
            and hours >= event.objective.nextScanAtHours
            and hours < event.objective.deadlineHours then
            local threats = secureAreaThreatCount(event)
            if threats ~= nil then
                event = KnoxEvents.recordSecureAreaScan(event.id, event.revision, hours, threats)
                    or event
                if event.objective.lastThreatCount == 0
                    and event.objective.clearSinceHours ~= nil
                    and hours - event.objective.clearSinceHours >= 0.05 then
                    KnoxEvents.finishFactionEntryObjective(event.id, event.revision, hours, "area_secure")
                    return
                end
            end
        end
        if event.objective.kind == "scavenge_world" then
            local count, exhausted = KnoxEvents.objectiveCount(event), true
            for _, id in ipairs(event.memberIds) do
                if (tonumber(event.objective.misses[id]) or 0) < 3 then exhausted = false end
            end
            if count >= event.objective.requiredItems or exhausted
                or hours >= event.objective.deadlineHours then
                local outcome = count >= event.objective.requiredItems and "supplies_taken"
                    or (count > 0 and "partial_supplies" or "no_supplies")
                KnoxEvents.finishFactionEntryObjective(event.id, event.revision, hours, outcome)
            end
            return
        end
        if hours >= event.objective.deadlineHours then
            KnoxEvents.finishFactionEntryObjective(event.id, event.revision, hours, "elapsed")
        end
        return
    end
    local count, exhausted = KnoxEvents.objectiveCount(event), true
    for _, id in ipairs(event.memberIds) do
        if (tonumber(event.objective.misses[id]) or 0) < 3 then exhausted = false end
    end
    if count >= event.objective.requiredItems or exhausted or hours >= event.objective.deadlineHours then
        local outcome = count >= event.objective.requiredItems and "supplies_taken"
            or (count > 0 and "partial_supplies" or "no_supplies")
        local result = KnoxEvents.finishRaidObjective(event.id, event.revision, hours, outcome)
        if result ~= nil then
            print("[KnoxSurvivors][Events] id=" .. event.id .. " phase=withdrawing reason=" .. outcome .. " items=" .. count)
            diagEvent(tostring(event.id), "raid_withdrawn", {
                outcome = tostring(outcome), items = count,
            })
        end
    end
end

function Runtime.beginObjectiveWork(controller, ticks)
    local assignment = controller.eventAssignment
    local event = assignment ~= nil and KnoxEvents.get(assignment.id) or nil
    if event == nil or event.phase ~= "objective" or not objectiveValid(event) then
        controller.state, controller.nextThink = "EVENT_WAIT", math.max(controller.nextThink or 0, ticks + 90)
        return true
    end
    if event.kind == "faction_entry" then
        if event.policyId == "scavengers" and event.objective.kind == "scavenge_world" then
            local target = event.targetLocation
            local directive = { kind = "loot_area", eventId = event.id,
                minX = target.x - 18, minY = target.y - 18,
                maxX = target.x + 18, maxY = target.y + 18, z = target.z }
            if ticks >= (controller.nextExplorationSearch or 0)
                and (tonumber(event.objective.misses[controller.id]) or 0) < 3
                and controller:beginExploration(ticks, directive) then return true end
        end
        controller.state = "EVENT_WAIT"
        controller.nextThink = math.max(controller.nextThink or 0, ticks + 90)
        return true
    end
    local base = KnoxPersistence.getBase(event.targetBaseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area ~= nil and ticks >= (controller.nextExplorationSearch or 0)
        and (tonumber(event.objective.misses[controller.id]) or 0) < 3 then
        local directive = { kind = "loot_area", eventId = event.id, minX = area.minX, minY = area.minY,
            maxX = area.maxX or (area.minX + area.width - 1), maxY = area.maxY or (area.minY + area.height - 1),
            z = base.home.z or 0 }
        if controller:beginExploration(ticks, directive) then return true end
    end
    controller.state = "EVENT_WAIT"
    controller.nextThink = math.max(controller.nextThink or 0, ticks + 90)
    return true
end

-- Paid raids: the one observation point for a player handing supplies over.
-- The raider-side capture refuses anything whose source is inside a character's
-- inventory, which is exactly what a handover is, so this answers the other
-- direction and nothing else. A transfer gets at most one of the two contexts,
-- and recordLoot refuses a repeated item id, so the two observers cannot both
-- write the same receipt.
function Runtime.captureHandoverContext(character, source, destination)
    if character == nil or source == nil or destination == nil then return nil end
    local inventory = character.getInventory ~= nil and character:getInventory() or nil
    if inventory == nil or source ~= inventory or destination == inventory then return nil end
    local owner = destination.getParent ~= nil and destination:getParent() or nil
    if owner == nil or owner == character then return nil end
    local memberId = KnoxSurvivorRuntime.idForCharacter(owner)
    if memberId == nil or KnoxPersistence.isSurvivorAlive(memberId) ~= true then return nil end
    local duty = KnoxPersistence.getSurvivorDuty(memberId)
    local event = duty ~= nil and duty.eventId ~= nil
        and KnoxEvents.get(duty.eventId) or nil
    if event == nil or event.kind ~= "faction_raid" then return nil end
    local square = character.getCurrentSquare ~= nil and character:getCurrentSquare() or nil
    local theirs = owner.getCurrentSquare ~= nil and owner:getCurrentSquare() or nil
    if square == nil or theirs == nil or square:getZ() ~= theirs:getZ() then return nil end
    local dx, dy = square:getX() - theirs:getX(), square:getY() - theirs:getY()
    if dx * dx + dy * dy > 4 then return nil end
    local state = KnoxEvents.raidDemandState(event, getGameTime():getWorldAgeHours())
    if state == nil or state.demandable ~= true then return nil end
    return {
        eventId = event.id, memberId = memberId,
        x = square:getX(), y = square:getY(), z = square:getZ(),
    }
end

function Runtime.handoverAllowed(context, character, source, destination)
    if context == nil then return true end
    if character == nil or source == nil or destination == nil then return false end
    local inventory = character.getInventory ~= nil and character:getInventory() or nil
    if inventory == nil or source ~= inventory then return false end
    local owner = destination.getParent ~= nil and destination:getParent() or nil
    if owner == nil or KnoxSurvivorRuntime.idForCharacter(owner) ~= context.memberId then
        return false
    end
    local event = KnoxEvents.get(context.eventId)
    local state = event ~= nil
        and KnoxEvents.raidDemandState(event, getGameTime():getWorldAgeHours()) or nil
    return state ~= nil and state.demandable == true
end

function Runtime.observeHandoverTransfer(context, character, source, destination,
    original, transferred, wasPresent)
    if context == nil or not wasPresent or transferred == nil then return false end
    if not Runtime.handoverAllowed(context, character, source, destination) then return false end
    if source:contains(original) or not destination:contains(transferred)
        or transferred:getContainer() ~= destination then return false end
    local id, fullType = transferred:getID(), transferred:getFullType()
    if id == nil or type(fullType) ~= "string" then return false end
    return KnoxEvents.recordLoot(context.eventId, context.memberId,
        { itemId = tostring(id), fullType = fullType,
            x = context.x, y = context.y, z = context.z },
        getGameTime():getWorldAgeHours()) == true
end

function Runtime.captureLootContext(character, source, destination)
    if character == nil or source == nil or destination == nil then return nil end
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    if id == nil or source == destination or destination ~= character:getInventory()
        or source:isInCharacterInventory(character) then return nil end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    local event = duty ~= nil and duty.eventId ~= nil and KnoxEvents.get(duty.eventId) or nil
    if event == nil or event.phase ~= "objective"
        or not objectiveValid(event) then return nil end
    local square, parent = source:getSourceGrid(), source:getParent()
    if square == nil or parent == nil or instanceof(parent, "IsoGameCharacter") then return nil end
    if event.kind == "faction_raid" then
        if not KnoxBaseManager.containsSquare(KnoxPersistence.getBase(event.targetBaseId), square) then
            return nil
        end
    elseif event.kind == "faction_entry" and event.policyId == "scavengers"
        and event.objective.kind == "scavenge_world" then
        local target = event.targetLocation
        local dx, dy = square:getX() - target.x, square:getY() - target.y
        if square:getZ() ~= target.z or dx * dx + dy * dy > 18 * 18 then return nil end
    else
        return nil
    end
    return { eventId = event.id, memberId = id, x = square:getX(), y = square:getY(), z = square:getZ() }
end

function Runtime.lootTransferAllowed(context, character, source, destination)
    if context == nil then return true end
    if KnoxSurvivorRuntime.getCharacter(context.memberId) ~= character then return false end
    local current = Runtime.captureLootContext(character, source, destination)
    if current == nil or current.eventId ~= context.eventId or current.x ~= context.x
        or current.y ~= context.y or current.z ~= context.z then return false end
    local event = KnoxEvents.get(context.eventId)
    local valid = KnoxEvents.validate(event)
    return valid and KnoxEvents.objectiveCount(event) < event.objective.requiredItems
        and getGameTime():getWorldAgeHours() < event.objective.deadlineHours
end

function Runtime.observeLootTransfer(context, character, source, destination, original, transferred, wasPresent)
    if context == nil or not wasPresent or transferred == nil
        or not Runtime.lootTransferAllowed(context, character, source, destination)
        or source:contains(original) or not destination:contains(transferred)
        or transferred:getContainer() ~= destination then return false end
    local id, fullType = transferred:getID(), transferred:getFullType()
    if id == nil or type(fullType) ~= "string" then return false end
    local recorded = KnoxEvents.recordLoot(context.eventId, context.memberId,
        { itemId = tostring(id), fullType = fullType, x = context.x, y = context.y, z = context.z },
        getGameTime():getWorldAgeHours())
    -- A raid that takes something from a container inside the home got in. That
    -- container's own square is the breach, so the player who returns finds
    -- broken glass where it happened instead of nothing. The trace writer
    -- collapses repeats from the same room, so looting five crates is one site.
    local event = context ~= nil and KnoxEvents.get ~= nil
        and KnoxEvents.get(context.eventId) or nil
    if recorded and type(event) == "table" and event.kind == "faction_raid"
        and KnoxPersistence ~= nil and KnoxPersistence.recordTraceSite ~= nil then
        pcall(KnoxPersistence.recordTraceSite, "breach",
            context.x, context.y, context.z, getGameTime():getWorldAgeHours())
    end
    return recorded
end

function Runtime.update(controllers, hours)
    local ids = KnoxEvents.activeIds()
    local present = {}; for _, id in ipairs(ids) do present[id] = true end
    for id in pairs(nextDispatchCheck) do if not present[id] then nextDispatchCheck[id] = nil end end
    for _ = 1, math.min(8, #ids) do
        cursor = cursor % #ids + 1
        local event = KnoxEvents.get(ids[cursor])
        local valid, reason = KnoxEvents.validate(event)
        if not finished(event) and reason ~= "invalid_event_record" then
            if not valid and event.phase ~= "scheduled" and event.phase ~= "withdrawing" then
                event = change(event, "withdrawing", hours, reason) or event
            end
            announceRaidWarning(event, hours)
            announceRaidAftermath(event, hours)
            if event.phase == "scheduled" or event.phase == "spawning" then
                if hours >= (nextDispatchCheck[event.id] or 0) then
                    nextDispatchCheck[event.id] = hours + 0.05
                    Runtime.dispatch(event, controllers, hours)
                end
            elseif event.phase == "approaching" or event.phase == "active" or event.phase == "objective" then
                local arrived = true
                for _, id in ipairs(event.memberIds) do
                    if not owns(id, event.id) then
                        change(event, "withdrawing", hours, "member_duty_changed")
                        arrived = false
                        break
                    end
                    local controller = controllers[id]
                    if controller ~= nil and controller.state == "FLEEING" then
                        change(event, "withdrawing", hours, "party_retreating")
                        arrived = false
                        break
                    end
                    if event.phase == "approaching" and controller ~= nil
                        and (controller.eventMoveFailures or 0) >= 3 then
                        change(event, "withdrawing", hours, "approach_failed")
                        arrived = false
                        break
                    end
                    if event.phase == "approaching" then
                        arrived = atDestination(id, controller ~= nil and controller.character or nil,
                            Runtime.destination(event, id)) and arrived
                    elseif event.phase == "active" and event.kind == "faction_raid" then
                        arrived = Runtime.raidMemberAtTarget(event, id, controller) and arrived
                    end
                end
                if arrived and event.phase == "approaching" then
                    change(event, "active", hours, "party_arrived")
                elseif event.phase == "active" then
                    if event.kind == "faction_raid" then
                        -- Stored travel may establish real arrival, but only a
                        -- loaded body can own native combat and looting.
                        if hasLoadedRaidMember(event, controllers) then
                            KnoxEvents.beginRaidObjective(event.id, event.revision, hours)
                        end
                    else
                        KnoxEvents.beginFactionEntryObjective(event.id, event.revision, hours)
                    end
                elseif event.phase == "objective" then
                    -- Objective review deliberately continues while ordinary
                    -- combat moves raiders around the target.  Fleeing above
                    -- still withdraws the party; this merely avoids freezing
                    -- a valid raid because its fixed approach positions moved.
                    if event.kind ~= "faction_raid" or hasLoadedRaidMember(event, controllers) then
                        Runtime.reviewObjective(event, hours)
                    end
                end
            elseif event.phase == "withdrawing" then
                local resolved, home = true, sourceHome(event)
                for _, id in ipairs(event.memberIds or {}) do
                    if owns(id, event.id) then
                        local controller = controllers[id]
                        local returned = event.kind == "faction_entry"
                            and atDestination(id, controller ~= nil and controller.character or nil,
                                Runtime.destination(event, id))
                            or home ~= nil and returnedHome(id,
                                controller ~= nil and controller.character or nil, home)
                        if not KnoxPersistence.isSurvivorAlive(id) then
                            KnoxPersistence.releaseEventDuty(id, event.id, hours)
                        elseif returned and partyLeavesCounty(event) then
                            local pending = KnoxPersistence.beginEventDeparture(id, event.id, hours)
                            if pending and controller == nil
                                and KnoxSurvivorRuntime.getCharacter(id) == nil then
                                KnoxPersistence.finalizeEventDeparture(id, event.id, hours)
                            else
                                -- A loaded shell must be captured and removed by
                                -- the autonomy lifecycle owner before this event
                                -- can complete. Pending departure is intentionally
                                -- not treated as a released member.
                                resolved = false
                            end
                        elseif returned or event.kind == "faction_raid" and home == nil then
                            KnoxPersistence.releaseEventDuty(id, event.id, hours)
                        else
                            resolved = false
                        end
                    end
                end
                if resolved then
                    local completed = event.kind == "faction_entry" or home ~= nil
                    change(event, completed and "completed" or "failed", hours,
                        completed and "party_returned_or_released" or "home_removed")
                end
            end
        end
    end
end

function Runtime.syncController(id, controller)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    local event = duty ~= nil and duty.eventId ~= nil and KnoxEvents.get(duty.eventId) or nil
    if not finished(event) and not KnoxEvents.isValidRecord(event) then
        controller:setEventAssignment({ id = event.id, phase = "withdrawing" })
        return
    end
    if finished(event) or indexOf(event, id) == nil then
        if duty ~= nil and duty.eventId ~= nil then
            KnoxPersistence.releaseEventDuty(id, duty.eventId, getGameTime():getWorldAgeHours())
        end
        controller:setEventAssignment(nil)
        return
    end
    controller:setEventAssignment({ id = event.id, phase = event.phase, destination = Runtime.destination(event, id) })
    local leaderId, leader, members = nil, nil, {}
    for _, memberId in ipairs(event.memberIds or {}) do
        local body = owns(memberId, event.id) and KnoxSurvivorRuntime.getCharacter(memberId) or nil
        if body ~= nil and not body:isDead() and body:getCurrentSquare() ~= nil then
            members[#members + 1] = body
            if leader == nil then leaderId, leader = memberId, body end
        end
    end
    if leaderId ~= nil and leaderId ~= id then
        controller:setGroupLeader(leaderId, leader, indexOf(event, id) - 1, #members)
        controller:setGroupMembers({})
    else
        controller:clearGroupLeader()
        controller:setGroupMembers(members)
    end
end

return Runtime
