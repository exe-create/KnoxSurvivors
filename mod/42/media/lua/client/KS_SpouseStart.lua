require "KS_Settings"
require "KS_Persistence"
local SpouseStart = {}
KnoxSpouseStart = SpouseStart

local function allocateSpouseId(playerId)
    local random = rawget(_G, "ZombRand")
    for attempt = 1, 16 do
        local salt
        if type(random) == "function" then
            local ok, value = pcall(random, 1000000000)
            if ok then salt = tonumber(value) end
        end
        if salt == nil and math.random ~= nil then
            salt = math.random(0, 999999999)
        end
        if salt == nil then salt = attempt end
        local id = "ks-spouse-" .. tostring(playerId) .. "-" .. tostring(math.floor(salt))
        if KnoxPersistence.getRecord(id) == nil then return id end
    end
    -- Keep collisions impossible even if the engine RNG repeats a value.
    local suffix = 1
    local id = "ks-spouse-" .. tostring(playerId) .. "-fallback-" .. tostring(suffix)
    while KnoxPersistence.getRecord(id) ~= nil do
        suffix = suffix + 1
        id = "ks-spouse-" .. tostring(playerId) .. "-fallback-" .. tostring(suffix)
    end
    return id
end

-- A survivor who is already standing in the world becomes the player's spouse.
-- The creator's marked spouse uses this, so what a spouse is has one definition
-- and the random reservation is not spawned a second time.
function SpouseStart.adopt(player, id)
    if player == nil or id == nil then return false end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    if playerId == nil then return false end
    local now = getGameTime():getWorldAgeHours()
    local assigned = KnoxPersistence.setPlayerCompanion(id, playerId, "follow", now)
    if not assigned then return false end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, id)
    if relation ~= nil then
        relation.trust = 90
        relation.meetings = math.max(1, relation.meetings or 0)
        relation.firstMetHours = relation.firstMetHours or now
    end
    if KnoxPersistence.rememberObserverKnowledge ~= nil then
        KnoxPersistence.rememberObserverKnowledge(playerId, id, "commitment",
            { role = "companion", order = "follow",
              duty = { mode = "companion", order = "follow", ownerId = playerId } }, now)
    end
    return true
end

-- One free tile beside the player: the marked cast and the random spouse share
-- this search, so a starting survivor never materialises inside the player.
local function freeStartSquare(player, cell)
    local origin = player:getCurrentSquare()
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local candidate = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                local occupants = candidate ~= nil and candidate.getMovingObjects ~= nil
                    and candidate:getMovingObjects() or nil
                if candidate ~= nil and candidate:canStand()
                    and (occupants == nil or occupants:size() == 0)
                    and not origin:isSomethingTo(candidate) then return candidate end
            end
        end
    end
    return nil
end

function SpouseStart.update(player, activate)
    if player == nil or player:getCurrentSquare() == nil or player:isDead() then return false end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    if playerId == nil then return false end
    local data = player:getModData().KnoxSurvivors
    if data.spouseStart == nil then
        -- Opening an established save must not silently manufacture a spouse.
        if not KnoxSettings.spawnWithSpouse() or player:getHoursSurvived() > 0.1 then
            data.spouseStart = { status = "skipped" }
            return false
        end
        -- Personality and other stable identity traits derive from this ID.
        -- A one-time saved random suffix gives new-save spouses variation;
        -- retries and reloads keep the reserved identity unchanged.
        data.spouseStart = { status = "pending", id = allocateSpouseId(playerId) }
        -- Hold the fresh random reservation for one pass: the creator's spawn
        -- pass runs later in this same pass and adopts a marked spouse first,
        -- overwriting this reservation. Placing now would stand a random
        -- spouse beside the player alongside the marked one (owner report:
        -- flag on + marked spouse = two spouses). The next pass acts on it.
        return false
    end
    local start = data.spouseStart
    -- A creator-marked spouse already placed is never re-run: the random path
    -- below must not introduce a second person, with or without the sandbox flag.
    -- The sandbox Start with a Spouse flag governs the random spouse only; the
    -- creator's marked spouse is adopted by the spawn path regardless of it.
    if start.status == "complete" then return false end
    if start.status ~= "pending" then return false end
    -- The spawn path hands over a real allocation with a record: the sandbox
    -- flag governs the random reservation only, and the placement below walks
    -- the marked spouse in beside the player instead of restoring them at
    -- their origin building.
    local marked = start.marked == true and start.id ~= nil
        and KnoxPersistence.getRecord ~= nil
        and KnoxPersistence.getRecord(start.id) ~= nil
    if not marked and not KnoxSettings.spawnWithSpouse() then return false end
    local record = KnoxPersistence.getRecord(start.id)
    if record ~= nil and not KnoxPersistence.isSurvivorAlive(start.id) then
        start.status = "deceased"
        return false
    end
    -- Already standing (a retry after placement, or a body the world woke
    -- first): keep the duty, close the reservation, place nothing.
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local known = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(start.id) or nil
    if known ~= nil then
        if not SpouseStart.adopt(player, start.id) then return false end
        start.status = "complete"
        return true
    end
    local cell = getCell()
    if cell == nil then return false end
    local square = nil
    if record == nil or marked then
        square = freeStartSquare(player, cell)
        if square == nil then return false end
    end
    -- The caller reuses normal capture/restore and registry ownership. Persist
    -- the stable reservation first; retries never select a second identity.
    if not activate(start.id, square, record) then return false end
    local spouse = rawget(_G, "KnoxSurvivorRuntime") ~= nil
        and KnoxSurvivorRuntime.getCharacter(start.id) or nil
    -- The marked spouse arrives as authored: no surname takeover, no gender
    -- redress, no recapture. Those correct the random spouse only.
    if not marked then
    local playerDescriptor = player.getDescriptor ~= nil and player:getDescriptor() or nil
    local spouseDescriptor = spouse ~= nil and spouse.getDescriptor ~= nil
        and spouse:getDescriptor() or nil
    local surname = playerDescriptor ~= nil and playerDescriptor:getSurname() or ""
    local oppositeGender = player.isFemale ~= nil and player:isFemale() ~= true or nil
    if spouseDescriptor ~= nil then
        if oppositeGender ~= nil then
            pcall(function() spouseDescriptor:setFemale(oppositeGender) end)
        end
        if surname ~= "" then pcall(function() spouseDescriptor:setSurname(surname) end) end
    end
    if spouse ~= nil and spouse.setFemale ~= nil and oppositeGender ~= nil then
        pcall(function() spouse:setFemale(oppositeGender) end)
    end
    -- Spawn dressed for a random gender; redress for the spouse gender so body
    -- and clothing agree instead of mismatching.
    if oppositeGender ~= nil and ClothingSelectionDefinitions ~= nil
        and ClothingSelectionDefinitions.default ~= nil then
        pcall(function()
            local bridge = rawget(_G, "KnoxJavaBridge")
            local definition = ClothingSelectionDefinitions.default
            local genderDefinition = oppositeGender and definition.Female
                or (definition.Male or definition.Female)
            if bridge ~= nil and genderDefinition ~= nil then
                for _, selection in pairs(genderDefinition) do
                    local chance = selection.chance
                    if (chance == nil or ZombRand(100) < chance) and #selection.items > 0 then
                        local fullType = selection.items[ZombRand(0, #selection.items) + 1]
                        if bridge.dressNpcItem ~= nil then
                            bridge:dressNpcItem(start.id, fullType)
                        else
                            bridge:wearNpcItem(start.id, fullType)
                        end
                    end
                end
            end
        end)
    end
    if spouse ~= nil and KnoxPersistence.ensureSurvivorIdentityFromCharacter ~= nil then
        local identity = KnoxPersistence.ensureSurvivorIdentityFromCharacter(
            start.id, spouse, getGameTime():getWorldAgeHours()
        )
        if identity ~= nil and surname ~= "" then identity.surname = surname end
        -- Recapture so the corrected surname/gender persist instead of the
        -- random values captured during spawn.
        pcall(function() KnoxPersistence.captureActiveSurvivor(start.id) end)
    end
    end
    if not SpouseStart.adopt(player, start.id) then return false end
    start.status = "complete"
    return true
end

-- The creator's marked companions, stashed by the spawn path as fresh ids:
-- walk each one in beside the player once, then drop them from the stash, so
-- a later load leaves everyone where the world already put them.
function SpouseStart.updateMarkedCompanions(player, activate)
    if player == nil or player.getCurrentSquare == nil or player:isDead() then return false end
    if activate == nil then return false end
    local okMd, modData = pcall(function() return player:getModData() end)
    local data = okMd and type(modData) == "table" and modData.KnoxSurvivors or nil
    if type(data) ~= "table" or type(data.creatorStart) ~= "table" then return false end
    local ids = data.creatorStart.companionIds
    if type(ids) ~= "table" or #ids == 0 then data.creatorStart = nil; return false end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return false end
    local P = KnoxPersistence
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local placedAny, remaining = false, {}
    for _, id in ipairs(ids) do
        local live = runtime ~= nil and runtime.getCharacter ~= nil
            and runtime.getCharacter(id) or nil
        if live ~= nil then
            placedAny = true
        else
            local square = freeStartSquare(player, cell)
            local record = P ~= nil and P.getRecord ~= nil and P.getRecord(id) or nil
            if square ~= nil and activate(id, square, record) then
                placedAny = true
            else
                remaining[#remaining + 1] = id
            end
        end
    end
    if #remaining == 0 then data.creatorStart = nil
    else data.creatorStart.companionIds = remaining end
    return placedAny
end

return SpouseStart
