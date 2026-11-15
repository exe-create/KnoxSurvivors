-- A homecoming is one person noticing that the player came back. It is not a
-- log, a quest, a base summary or a second attention model: it selects one
-- real change the base already recorded and gives it to one resident who is
-- present, visible and close enough to speak.
local Homecoming = rawget(_G, "KnoxHomecoming") or {}
_G.KnoxHomecoming = Homecoming

-- HOME COMING (pure)
Homecoming.MIN_AWAY_HOURS = 6
Homecoming.MAX_SPEAKER_DISTANCE = 12
-- A two-day trip is a different return from an afternoon out: it earns a
-- short briefing rather than one sentence. The cap is the same three-item
-- budget the home band already uses, so the report cannot become a log.
Homecoming.LONG_ABSENCE_HOURS = 48
Homecoming.MAX_REPORT_LINES = 3

-- Only lasting work earns a spoken line. A finished guard shift or patrol is
-- not a change the player can see in the world, so it stays out of the list.
Homecoming.WORK_PHRASES = {
    barricade = "got the barricade up",
    farm_seed = "got the seeds in",
    farm_water = "watered the crops",
    farm_harvest = "brought the harvest in",
    farm_plow = "turned the soil",
    repair = "finished the repair",
    cook = "made a hot meal",
    chop_tree = "cut wood",
    saw_logs = "sawed the logs",
    haul_corpse = "moved the bodies",
    burn_corpse = "cleared the burn pile",
}

Homecoming.SHORTAGE_LABELS = {
    food = "food",
    water = "water",
    medical = "medical supplies",
    ammo = "ammunition",
    fuel = "fuel",
}

local function clean(value)
    local text = type(value) == "string" and value or ""
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function Homecoming.workPhrase(taskType)
    return Homecoming.WORK_PHRASES[tostring(taskType or "")]
end

function Homecoming.shortageLabel(category)
    return Homecoming.SHORTAGE_LABELS[tostring(category or "")]
end

-- A bed, kit or storage problem the home status already counted. The caller
-- names the first one; this only puts it in plain words and refuses to invent
-- a kind or a count the base did not record.
function Homecoming.problemText(problem)
    if type(problem) ~= "table" then return nil end
    local count = math.max(0, math.floor(tonumber(problem.count) or 0))
    if count == 0 then return nil end
    local kind = tostring(problem.kind or "")
    if kind == "beds" then
        return count == 1 and "Someone's sleeping on the floor."
            or ("We're short " .. tostring(count) .. " beds.")
    end
    if kind == "kits" then
        return count == 1 and "One of us is short kit."
            or (tostring(count) .. " of us are short kit.")
    end
    if kind == "storage" then
        return count == 1 and "Something still needs a home."
            or (tostring(count) .. " things still need a home.")
    end
    return nil
end

-- Pick the most recent lasting completion at or after `sinceHours`. A task
-- that was reopened has lost its completion stamp, so this never guesses at
-- work the base did not still record as complete.
function Homecoming.recentWork(base, sinceHours)
    if type(base) ~= "table" or type(base.tasks) ~= "table" then return nil end
    local since = tonumber(sinceHours)
    if since == nil then return nil end
    local selected, selectedAt = nil, nil
    for _, task in pairs(base.tasks) do
        if type(task) == "table"
            and (task.state == "complete" or task.state == "completed")
            and Homecoming.workPhrase(task.type) ~= nil then
            local at = tonumber(task.completedAtHours)
            if at ~= nil and at >= since then
                local newer = selectedAt == nil or at > selectedAt
                    or (at == selectedAt
                        and tostring(task.id or "") < tostring(selected.id or ""))
                if newer then
                    selected, selectedAt = task, at
                end
            end
        end
    end
    return selected
end

-- One line, one fact. Priority is loss, lasting work, injury, shortage, then
-- the honest quiet state. The caller supplies only facts that already exist.
function Homecoming.lineFor(facts)
    facts = type(facts) == "table" and facts or {}
    local speaker = clean(facts.speakerName)
    local lost = math.max(0, math.floor(tonumber(facts.lost) or 0))
    if lost > 0 then
        if lost == 1 then
            return "We lost someone while you were out."
        end
        return "We lost " .. tostring(lost) .. " people while you were out."
    end
    local work = type(facts.work) == "table" and facts.work or nil
    local phrase = work ~= nil and Homecoming.workPhrase(work.key) or nil
    if phrase ~= nil then
        local worker = clean(work.workerName)
        if worker ~= "" and worker == speaker then
            return "I " .. phrase .. "."
        end
        if worker ~= "" then
            return worker .. " " .. phrase .. "."
        end
        return "We " .. phrase .. "."
    end
    local hurt = clean(facts.hurtName)
    if hurt ~= "" then
        if hurt == speaker then
            return "I'm hurt. It needs a look."
        end
        return hurt .. " is hurt. Needs a look."
    end
    local shortage = Homecoming.shortageLabel(facts.shortage)
    if shortage ~= nil then
        return "We're low on " .. shortage .. "."
    end
    local problem = Homecoming.problemText(facts.problem)
    if problem ~= nil then return problem end
    return "We're still here. That's the report."
end

-- A long absence earns up to three facts, one per line, in the same priority
-- order as a single homecoming line. The caller supplies only facts that
-- already exist; a short absence keeps one line so a routine trip out does not
-- turn into a briefing.
function Homecoming.reportFor(facts)
    facts = type(facts) == "table" and facts or {}
    local lines = {}
    if (tonumber(facts.lost) or 0) >= 1 then
        lines[#lines + 1] = Homecoming.lineFor({ lost = facts.lost })
    end
    if type(facts.work) == "table"
        and Homecoming.workPhrase(facts.work.key) ~= nil then
        lines[#lines + 1] = Homecoming.lineFor({
            work = facts.work, speakerName = facts.speakerName })
    end
    if clean(facts.hurtName) ~= "" then
        lines[#lines + 1] = Homecoming.lineFor({
            hurtName = facts.hurtName, speakerName = facts.speakerName })
    end
    if Homecoming.shortageLabel(facts.shortage) ~= nil then
        lines[#lines + 1] = Homecoming.lineFor({ shortage = facts.shortage })
    end
    local problem = Homecoming.problemText(facts.problem)
    if problem ~= nil then lines[#lines + 1] = problem end
    if #lines == 0 then
        lines[1] = Homecoming.lineFor({})
    end
    while #lines > Homecoming.MAX_REPORT_LINES do
        table.remove(lines)
    end
    return lines
end
-- END HOME COMING

local players = {}

local function worldHours()
    if getGameTime == nil then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return nil end
    local read, hours = pcall(function() return gameTime:getWorldAgeHours() end)
    return read and tonumber(hours) or nil
end

local function nameFor(id)
    if id == nil then return nil end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil then
        local ok, identity = pcall(persistence.getSurvivorIdentity, id)
        if ok and type(identity) == "table" then
            local name = clean(identity.forename or identity.firstName or identity.name)
            if name ~= "" then return name end
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(id) or nil
    if character ~= nil then
        local ok, name = pcall(function() return character:getDisplayName() end)
        if ok then
            name = clean(name)
            if name ~= "" then return name end
        end
    end
    return nil
end

local function residentIds(base)
    local persistence = rawget(_G, "KnoxPersistence")
    if base == nil or persistence == nil
        or persistence.getBaseResidentIds == nil then return {} end
    local ok, ids = pcall(persistence.getBaseResidentIds, base.id)
    return ok and type(ids) == "table" and ids or {}
end

local function residentAvailable(id)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return true end
    if persistence.isSurvivorAlive ~= nil and persistence.isSurvivorAlive(id) == false then
        return false
    end
    if persistence.isSurvivorPresent ~= nil and persistence.isSurvivorPresent(id) == false then
        return false
    end
    return true
end

local function canSee(first, second)
    if first == nil or second == nil or first.CanSee == nil then return false end
    local ok, visible = pcall(function() return first:CanSee(second) end)
    return ok and visible == true
end

local function findHurt(base)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.getCharacter == nil then return nil, nil end
    local foundId, foundName, foundHealth = nil, nil, math.huge
    for _, id in ipairs(residentIds(base)) do
        if residentAvailable(id) then
            local character = runtime.getCharacter(id)
            if character ~= nil then
                local deadOk, dead = pcall(function() return character:isDead() end)
                local healthOk, health = pcall(function() return character:getHealth() end)
                health = healthOk and tonumber(health) or nil
                if (not deadOk or dead ~= true) and health ~= nil and health > 0
                    and health < 60 and health < foundHealth then
                    foundId, foundName, foundHealth = id, nameFor(id), health
                end
            end
        end
    end
    return foundId, foundName
end

local function chooseSpeaker(base, player, preferredId)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local here = player ~= nil and player:getCurrentSquare() or nil
    if runtime == nil or runtime.getCharacter == nil or here == nil then
        return nil, nil, nil
    end
    local limit = Homecoming.MAX_SPEAKER_DISTANCE ^ 2
    local selected, selectedId, selectedDistance = nil, nil, math.huge
    for _, id in ipairs(residentIds(base)) do
        if residentAvailable(id) then
            local character = runtime.getCharacter(id)
            local there = character ~= nil and character:getCurrentSquare() or nil
            if character ~= nil and there ~= nil and there:getZ() == here:getZ()
                and canSee(character, player) and canSee(player, character) then
                local deadOk, dead = pcall(function() return character:isDead() end)
                local sleepOk, asleep = pcall(function() return character:isAsleep() end)
                local vehicleOk, vehicle = pcall(function() return character:getVehicle() end)
                local distance = (there:getX() - here:getX()) ^ 2
                    + (there:getY() - here:getY()) ^ 2
                if (not deadOk or dead ~= true)
                    and (not sleepOk or asleep ~= true)
                    and (not vehicleOk or vehicle == nil)
                    and distance <= limit then
                    local preferred = preferredId ~= nil
                        and tostring(preferredId) == tostring(id)
                    if preferred then
                        return character, id, nameFor(id)
                    end
                    if selected == nil or distance < selectedDistance then
                        selected, selectedId, selectedDistance = character, id, distance
                    end
                end
            end
        end
    end
    return selected, selectedId,
        selectedId ~= nil and nameFor(selectedId) or nil
end

function Homecoming.greet(player, playerId, base, state, now)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.showSurvivorSpeech ~= nil
        and settings.showSurvivorSpeech() ~= true then return false end
    local status = KnoxBaseManager ~= nil and KnoxBaseManager.homeStatus ~= nil
        and KnoxBaseManager.homeStatus(base, playerId, true) or nil
    if status == nil then return false end
    local deadNow = math.max(0, math.floor(tonumber(status.dead) or 0))
    local deadAtLeave = math.max(0, math.floor(tonumber(state.deadAtLeave) or deadNow))
    local lost = math.max(0, deadNow - deadAtLeave)
    local work = Homecoming.recentWork(base, state.leftAt)
    local hurtId, hurtName = findHurt(base)
    local shortage = type(status.facts) == "table"
        and type(status.facts.shortage) == "table"
        and status.facts.shortage.category or nil
    -- A bed, kit or storage problem is already counted by the home status. The
    -- report names the first one rather than inventing a repair or a shortage
    -- the base has not recorded. Shortage stays ahead of it in the order.
    local problem = nil
    if type(status.facts) == "table" then
        local beds = math.max(0, math.floor(tonumber(status.facts.bedsWithout) or 0))
        local kits = math.max(0, math.floor(tonumber(status.facts.kitShort) or 0))
        local unshelved = math.max(0, math.floor(tonumber(status.facts.unshelved) or 0))
        if beds > 0 then problem = { kind = "beds", count = beds }
        elseif kits > 0 then problem = { kind = "kits", count = kits }
        elseif unshelved > 0 then problem = { kind = "storage", count = unshelved } end
    end
    local preferred = work ~= nil and work.lastClaimedBy or hurtId
    local speaker, speakerId, speakerName = chooseSpeaker(base, player, preferred)
    if speaker == nil then return false end
    local facts = {
        lost = lost,
        work = work ~= nil and {
            key = work.type,
            workerName = nameFor(work.lastClaimedBy),
        } or nil,
        hurtName = hurtName,
        shortage = shortage,
        problem = problem,
        speakerName = speakerName,
    }
    local away = state.leftAt ~= nil and (now - state.leftAt) or 0
    local lines = away >= Homecoming.LONG_ABSENCE_HOURS
        and Homecoming.reportFor(facts) or { Homecoming.lineFor(facts) }
    if type(lines) ~= "table" or #lines == 0 then return false end
    local runtime = rawget(_G,"KnoxSurvivorRuntime")
    local owner = runtime and runtime.getController and runtime.getController(speakerId)
    if owner and owner.faceForAmbient then owner:faceForAmbient(player) end
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.speak ~= nil then
        for _, line in ipairs(lines) do
            if type(line) == "string" and line ~= "" then
                pcall(feed.speak, speaker, line)
            end
        end
    end
    state.lastGreetingAt = now
    return true
end

function Homecoming.update(player)
    if player == nil then return end
    local deadOk, dead = pcall(function() return player:isDead() end)
    if deadOk and dead == true then return end
    local sleepOk, asleep = pcall(function() return player:isAsleep() end)
    if sleepOk and asleep == true then return end
    local vehicleOk, vehicle = pcall(function() return player:getVehicle() end)
    if vehicleOk and vehicle ~= nil then return end
    local now = worldHours()
    if now == nil then return end
    local squareOk, square = pcall(function() return player:getCurrentSquare() end)
    if not squareOk or square == nil then return end
    local manager = rawget(_G, "KnoxBaseManager")
    local persistence = rawget(_G, "KnoxPersistence")
    if manager == nil or manager.playerBaseAtSquare == nil
        or persistence == nil or persistence.ensurePlayerId == nil then return end
    local base = manager.playerBaseAtSquare(square)
    local playerId = persistence.ensurePlayerId(player)
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
        base = nil
    end
    local key = tostring(playerId or "player")
    local state = players[key] or {}
    players[key] = state

    if base == nil then
        if state.inside then
            local previous = state.baseId ~= nil and persistence.getBase ~= nil
                and persistence.getBase(state.baseId) or nil
            local status = previous ~= nil and manager.homeStatus ~= nil
                and manager.homeStatus(previous, playerId, true) or nil
            state.deadAtLeave = status ~= nil and tonumber(status.dead) or nil
            state.inside = false
            state.leftAt = now
        end
        return
    end

    if not state.inside then
        local canGreet = state.baseId == base.id and state.leftAt ~= nil
            and (now - state.leftAt) >= Homecoming.MIN_AWAY_HOURS
            and (state.lastGreetingAt == nil
                or (now - state.lastGreetingAt) >= Homecoming.MIN_AWAY_HOURS)
        state.inside = true
        if canGreet then
            pcall(Homecoming.greet, player, playerId, base, state, now)
        end
        state.baseId = base.id
        state.leftAt = nil
        state.deadAtLeave = nil
        return
    end

    if state.baseId ~= base.id then
        -- A teleport or a moved home is not a walk back through the gate.
        state.baseId = base.id
        state.leftAt = nil
        state.deadAtLeave = nil
    end
end

if Events ~= nil and Events.OnPlayerUpdate ~= nil
    and Events.OnPlayerUpdate.Add ~= nil then
    Events.OnPlayerUpdate.Add(function(player)
        Homecoming.update(player)
    end)
end

return Homecoming
