
local function getAnyLoadedPlayer()
    if getSpecificPlayer == nil then return nil end
    local count = 4
    if getNumActivePlayers ~= nil then
        local ok, n = pcall(getNumActivePlayers)
        if ok and tonumber(n) ~= nil then count = math.max(1, math.floor(tonumber(n))) end
    end
    for i = 0, math.max(0, count - 1) do
        local ok, p = pcall(getSpecificPlayer, i)
        if ok and p ~= nil and p.getCurrentSquare ~= nil then
            local okSq, sq = pcall(function() return p:getCurrentSquare() end)
            if okSq and sq ~= nil then return p end
        end
    end
    return nil
end
local TAG = "[KnoxSurvivors][Population]"
local IDS = { "ks-test-1", "ks-test-2" }
local ROUTES_REQUIRED = 3
local THINK_MIN_TICKS = 45
local THINK_JITTER_TICKS = 90
local MOVE_TIMEOUT_TICKS = 1500
local STATUS_INTERVAL_TICKS = 300
local GATE_KEY = "multi_runtime_v1"
local RELOAD_GATE_KEY = "multi_runtime_reload_v1"

local agents = {}
local ticks = 0
local passReported = false
local populationReady = false
local lastResult = nil
local update

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function squareText(square)
    if square == nil then
        return "none"
    end
    return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function loadedSquareForRecord(bridge, encoded)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(encoded),
            bridge:getTestNpcRecordY(encoded),
            bridge:getTestNpcRecordZ(encoded)
    end)
    if not success or getCell() == nil then
        return nil, tostring(x)
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function farEnoughFromCharacters(square, minimumDistance)
    for _, agent in pairs(agents) do
        if agent.character ~= nil and agent.character:getCurrentSquare() ~= nil
            and distanceSquared(square, agent.character:getCurrentSquare())
                < minimumDistance * minimumDistance then
            return false
        end
    end
    return true
end

local function findStandableSquare(origin, minimumRadius, maximumRadius, minimumSeparation)
    if origin == nil or getCell() == nil then
        return nil
    end
    local candidates = {}
    for radius = minimumRadius, maximumRadius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    if square ~= nil and square:canStand()
                        and farEnoughFromCharacters(square, minimumSeparation) then
                        candidates[#candidates + 1] = square
                    end
                end
            end
        end
        if #candidates > 0 then
            return candidates[ZombRand(#candidates) + 1]
        end
    end
    return nil
end

local function createNewSurvivor(bridge, id, origin)
    local square = findStandableSquare(origin, 6, 14, 5)
    if square == nil then
        return nil, "no_loaded_spawn_square"
    end
    local result = tostring(bridge:spawnNpc(id, square))
    if string.find(result, "SPAWNED", 1, true) ~= 1 then
        return nil, result
    end
    local character = bridge:getNpcCharacter(id)
    if character == nil then
        bridge:removeNpc(id)
        return nil, "spawned_character_unavailable"
    end
    local appearanceOk, appearance = KnoxCharacterAppearance.randomizeNewSurvivor(bridge, id)
    if not appearanceOk then
        bridge:removeNpc(id)
        return nil, "appearance_failed=" .. tostring(appearance)
    end
    local equipped = tostring(bridge:seedAndEquipNpc(id))
    if string.find(equipped, "EQUIPPED", 1, true) ~= 1 then
        bridge:removeNpc(id)
        return nil, "equipment_failed=" .. equipped
    end
    local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
    if not saved then
        bridge:removeNpc(id)
        return nil, "initial_capture_failed=" .. tostring(evidence)
    end
    print(
        TAG
            .. " survivor=SPAWNED id=" .. id
            .. " location=" .. squareText(square)
            .. " " .. tostring(appearance)
            .. " " .. equipped
    )
    return character, result
end

local function restoreSurvivor(bridge, id, encoded)
    local square, location = loadedSquareForRecord(bridge, encoded)
    if square == nil then
        return nil, "saved_square_not_loaded=" .. tostring(location)
    end
    local result = tostring(bridge:restoreTestNpcRecord(encoded, square))
    if string.find(result, "RESTORED", 1, true) ~= 1 then
        return nil, result
    end
    local character = bridge:getNpcCharacter(id)
    if character == nil then
        return nil, "restored_character_unavailable"
    end
    print(TAG .. " survivor=RESTORED id=" .. id .. " " .. result)
    return character, result
end

local function ensurePopulation(bridge, player)
    local origin = player:getCurrentSquare()
    for _, id in ipairs(IDS) do
        if agents[id] == nil then
            local record = KnoxPersistence.getRecord(id)
            local character, result
            if record ~= nil then
                character, result = restoreSurvivor(bridge, id, record)
                if character == nil
                    and string.find(tostring(result), "saved_square_not_loaded", 1, true) ~= nil then
                    return false, result
                end
            else
                character, result = createNewSurvivor(bridge, id, origin)
            end
            if character == nil then
                return false, "id=" .. id .. " " .. tostring(result)
            end
            character:setZombiesDontAttack(true)
            agents[id] = {
                id = id,
                character = character,
                state = "IDLE",
                nextThink = ticks + 15 + ZombRand(30),
                moveStartedAt = 0,
                routes = 0,
                failures = 0,
            }
        end
    end
    return bridge:getActiveNpcCount() == #IDS,
        "active=" .. tostring(bridge:getActiveNpcCount())
            .. " ids=" .. tostring(bridge:getActiveNpcIds())
end

local function beginRoam(bridge, agent)
    local origin = agent.character:getCurrentSquare()
    local target = findStandableSquare(origin, 6, 18, 4)
    if target == nil then
        agent.nextThink = ticks + THINK_MIN_TICKS
        return
    end
    local result = tostring(bridge:moveNpc(agent.id, target))
    if string.find(result, "MOVE_STARTED", 1, true) == 1 then
        agent.state = "ROAMING"
        agent.moveStartedAt = ticks
        print(TAG .. " id=" .. agent.id .. " state=ROAMING target=" .. squareText(target))
    else
        agent.failures = agent.failures + 1
        agent.nextThink = ticks + THINK_MIN_TICKS
        print(TAG .. " id=" .. agent.id .. " roam-deferred=" .. result)
    end
end

local function tickAgent(bridge, agent)
    if agent.state == "IDLE" then
        if ticks >= agent.nextThink then
            beginRoam(bridge, agent)
        end
        return
    end
    local movement = tostring(bridge:tickNpc(agent.id))
    if movement == "Succeeded" then
        agent.routes = agent.routes + 1
        agent.state = "IDLE"
        agent.nextThink = ticks + THINK_MIN_TICKS + ZombRand(THINK_JITTER_TICKS)
        KnoxPersistence.captureActiveSurvivor(agent.id)
        print(TAG .. " id=" .. agent.id .. " route=SUCCEEDED count=" .. tostring(agent.routes))
    elseif string.find(movement, "Failed", 1, true) == 1
        or string.find(movement, "TICK_FAILED", 1, true) == 1
        or ticks - agent.moveStartedAt > MOVE_TIMEOUT_TICKS then
        agent.failures = agent.failures + 1
        agent.state = "IDLE"
        agent.nextThink = ticks + THINK_MIN_TICKS
        print(TAG .. " id=" .. agent.id .. " route=FAILED result=" .. movement)
    end
end

local function reportPassIfReady()
    if passReported then
        return
    end
    for _, id in ipairs(IDS) do
        if agents[id] == nil or agents[id].routes < ROUTES_REQUIRED then
            return
        end
    end
    local saved, evidence = KnoxPersistence.captureAllActiveSurvivors()
    if not saved then
        print(TAG .. " RESULT status=FAIL reason=capture_all_failed evidence=" .. tostring(evidence))
        return
    end
    local alreadyPassed = KnoxPersistence.isDevGateComplete(GATE_KEY)
    KnoxPersistence.markDevGateComplete(GATE_KEY)
    if alreadyPassed then
        KnoxPersistence.markDevGateComplete(RELOAD_GATE_KEY)
    end
    passReported = true
    lastResult = {
        status = "PASS",
        reason = "two_independent_survivors",
        evidence = "active=2 routes=" .. tostring(agents[IDS[1]].routes)
            .. "," .. tostring(agents[IDS[2]].routes)
            .. " saved=" .. tostring(evidence)
            .. " reloadVerified=" .. tostring(alreadyPassed),
    }
    print(
        TAG
            .. " RESULT scenario=population status=PASS"
            .. " reason=two_independent_survivors"
            .. " evidence=active=2 routes="
            .. tostring(agents[IDS[1]].routes) .. "," .. tostring(agents[IDS[2]].routes)
            .. " saved=" .. tostring(evidence)
            .. " reloadVerified=" .. tostring(alreadyPassed)
    )
end

update = function()
    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getAnyLoadedPlayer()
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end
    if not populationReady then
        local ready, evidence = ensurePopulation(bridge, player)
        if not ready then
            if ticks % STATUS_INTERVAL_TICKS == 0 then
                print(TAG .. " waiting=" .. tostring(evidence))
            end
            return
        end
        populationReady = true
        print(TAG .. " state=ACTIVE " .. tostring(evidence))
    end
    for _, id in ipairs(IDS) do
        tickAgent(bridge, agents[id])
    end
    reportPassIfReady()
    if ticks % STATUS_INTERVAL_TICKS == 0 then
        for _, id in ipairs(IDS) do
            local agent = agents[id]
            print(
                TAG
                    .. " status id=" .. id
                    .. " state=" .. tostring(agent.state)
                    .. " routes=" .. tostring(agent.routes)
                    .. " failures=" .. tostring(agent.failures)
                    .. " " .. tostring(bridge:getNpcStatus(id))
            )
        end
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "population" then
        return false, "disabled"
    end
    ticks = 0
    agents = {}
    passReported = false
    populationReady = false
    lastResult = nil
    stop()
    Events.OnTick.Add(update)
    print(TAG .. " START auto=true survivors=2 zombiesDontAttack=true")
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    for _, agent in pairs(agents or {}) do
        pcall(function()
            if agent ~= nil and agent.character ~= nil then
                agent.character:setZombiesDontAttack(false)
            end
        end)
    end
    KnoxPersistence.captureAllActiveSurvivors()
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxPopulationProbe") or {}
_G.KnoxPopulationProbe = Probe
function Probe.start()
    return start()
end
function Probe.status()
    return {
        phase = populationReady and (passReported and "FINISHED" or "ACTIVE") or "WAITING",
        finished = passReported,
        result = lastResult,
        ticks = ticks,
    }
end
function Probe.cleanup()
    for _, agent in pairs(agents or {}) do
        pcall(function()
            if agent ~= nil and agent.character ~= nil then
                agent.character:setZombiesDontAttack(false)
            end
        end)
    end
    stop()
end
