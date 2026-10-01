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
    end
    local start = data.spouseStart
    if start.status ~= "pending" or not KnoxSettings.spawnWithSpouse() then return false end
    local record = KnoxPersistence.getRecord(start.id)
    if record ~= nil and not KnoxPersistence.isSurvivorAlive(start.id) then
        start.status = "deceased"
        return false
    end
    local origin, square = player:getCurrentSquare(), nil
    local cell = getCell()
    if cell == nil then return false end
    if record == nil then
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    local candidate = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    local occupants = candidate ~= nil and candidate.getMovingObjects ~= nil
                        and candidate:getMovingObjects() or nil
                    if square == nil and candidate ~= nil and candidate:canStand()
                        and (occupants == nil or occupants:size() == 0)
                        and not origin:isSomethingTo(candidate) then square = candidate end
                end
            end
        end
        if square == nil then return false end
    end
    -- The caller reuses normal capture/restore and registry ownership. Persist
    -- the stable reservation first; retries never select a second identity.
    if not activate(start.id, square, record) then return false end
    local spouse = rawget(_G, "KnoxSurvivorRuntime") ~= nil
        and KnoxSurvivorRuntime.getCharacter(start.id) or nil
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
    local now = getGameTime():getWorldAgeHours()
    local assigned = KnoxPersistence.setPlayerCompanion(start.id, playerId, "follow", now)
    if not assigned then return false end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, start.id)
    relation.trust = 90
    relation.meetings = math.max(1, relation.meetings or 0)
    relation.firstMetHours = relation.firstMetHours or now
    start.status = "complete"
    return true
end

return SpouseStart
