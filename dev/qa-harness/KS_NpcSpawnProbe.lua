
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
local TAG = "[KnoxSurvivors][TestLab]"
local Probe = rawget(_G, "KnoxNpcSpawnProbe") or {}
_G.KnoxNpcSpawnProbe = Probe
local DISCOVERY_DELAY_TICKS = 120
local SPAWN_SETTLE_TICKS = 90
local BETWEEN_CASE_TICKS = 45
local MOVE_TIMEOUT_TICKS = 1200
local STATUS_INTERVAL_TICKS = 30

local ticks = 0
local phaseStartedAt = 0
local phase = "IDLE"
local testCases = {}
local caseIndex = 0
local activeCase = nil
local movementRequested = false
local movementStartedAt = 0
local suiteFailures = 0
local obstaclePasses = 0
local completedCases = {}
local completedCaseCount = 0
local update

local EXPECTED_TRAVERSAL_EVIDENCE = {
    door = { "OPENING_DOOR" },
    window_open = {
        "STARTED_WINDOW_OPEN",
        "COMPLETED_WINDOW_OPEN",
        "STARTED_WINDOW_CLIMB",
    },
    window_locked = {
        "STARTED_WINDOW_OPEN",
        "STARTED_WINDOW_SMASH",
        "STARTED_WINDOW_CLIMB",
    },
    fence = { "STARTED_FENCE_CLIMB" },
}

local FORBIDDEN_TRAVERSAL_EVIDENCE = {
    window_open = { "STARTED_WINDOW_SMASH", "SMASHING_WINDOW" },
}

local function squareText(square)
    if square == nil then
        return "none"
    end
    return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
end

local function reportResult(name, status, reason, evidence)
    print(
        TAG
            .. " RESULT scenario="
            .. tostring(name)
            .. " status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function printScenarioRegistry(config)
    local names = {
        "movement",
        "door",
        "window_open",
        "window_locked",
        "fence",
        "locked_entry",
        "equipment",
        "combat",
        "loot",
        "health",
        "medical",
        "persistence",
    }
    for _, name in ipairs(names) do
        print(
            TAG
                .. " SCENARIO name="
                .. name
                .. " state="
                .. tostring(config.scenarios[name] or "UNREGISTERED")
        )
    end
end

local function canUseSquare(square)
    return square ~= nil and square:canStand()
end

local function nearestFirst(playerSquare, first, second)
    local firstDistance = math.abs(first:getX() - playerSquare:getX())
        + math.abs(first:getY() - playerSquare:getY())
    local secondDistance = math.abs(second:getX() - playerSquare:getX())
        + math.abs(second:getY() - playerSquare:getY())
    if secondDistance < firstDistance then
        return second, first
    end
    return first, second
end

local function safeBoolean(object, methodName)
    local success, result = pcall(function()
        return object[methodName](object)
    end)
    return success and result == true
end

local function edgeIsOtherwiseClear(first, second)
    return first:getDoorTo(second) == nil
        and first:getWindowTo(second) == nil
        and first:getWindowThumpableTo(second) == nil
        and first:getWindowFrameTo(second) == nil
end

local function addCase(found, name, first, second, evidence)
    if found[name] ~= nil or not canUseSquare(first) or not canUseSquare(second) then
        return
    end

    local player = getAnyLoadedPlayer()
    if player == nil or player:getCurrentSquare() == nil then
        return
    end

    local startSquare, targetSquare = nearestFirst(player:getCurrentSquare(), first, second)
    found[name] = {
        name = name,
        startSquare = startSquare,
        targetSquare = targetSquare,
        evidence = evidence,
        expectedTraversalEvidence = EXPECTED_TRAVERSAL_EVIDENCE[name] or {},
        forbiddenTraversalEvidence = FORBIDDEN_TRAVERSAL_EVIDENCE[name] or {},
    }
end

local function inspectEdge(found, first, second, config)
    if not canUseSquare(first) or not canUseSquare(second) then
        return
    end

    local door = first:getDoorTo(second)
    if door ~= nil
        and not door:IsOpen()
        and not safeBoolean(door, "isBarricaded")
        and not safeBoolean(door, "isLocked")
        and not safeBoolean(door, "isLockedByKey") then
        addCase(found, "door", first, second, "closed=true locked=false")
    end

    local window = first:getWindowTo(second)
    if window ~= nil
        and not window:IsOpen()
        and not window:isSmashed()
        and not window:isBarricaded() then
        -- Native open cannot turn a key-locked window either: the crossing
        -- policy burns its one open attempt and reports LOCKED_OR_UNUSABLE.
        -- Mirror that here so window_open only admits truly openable glass.
        local locked = window:isLocked() or window:isPermaLocked()
            or safeBoolean(window, "isLockedByKey")
        if locked and config.allowDestructiveWindowTest == true then
            addCase(found, "window_locked", first, second, "locked=true destructive=true")
        elseif not locked then
            addCase(found, "window_open", first, second, "locked=false")
        end
    end

    if edgeIsOtherwiseClear(first, second) and first:isHoppableTo(second) then
        addCase(found, "fence", first, second, "hoppable=true")
    end
end

local function findBaselineMovementCase(player, radius)
    local cell = getCell()
    local playerSquare = player:getCurrentSquare()
    if cell == nil or playerSquare == nil then
        return nil
    end

    local z = playerSquare:getZ()
    local playerRoom = playerSquare:getRoom()
    local directions = {
        { 1, 0 },
        { 0, 1 },
        { -1, 0 },
        { 0, -1 },
    }
    for _, direction in ipairs(directions) do
        local startSquare = cell:getGridSquare(
            playerSquare:getX() + direction[1] * 2,
            playerSquare:getY() + direction[2] * 2,
            z
        )
        local targetSquare = cell:getGridSquare(
            playerSquare:getX() + direction[1] * math.min(radius, 5),
            playerSquare:getY() + direction[2] * math.min(radius, 5),
            z
        )
        if canUseSquare(startSquare)
            and canUseSquare(targetSquare)
            and startSquare:getRoom() == playerRoom
            and targetSquare:getRoom() == playerRoom then
            return {
                name = "movement",
                startSquare = startSquare,
                targetSquare = targetSquare,
                evidence = "baseline=true",
                expectedTraversalEvidence = {},
                forbiddenTraversalEvidence = {},
            }
        end
    end
    return nil
end

local function discoverCases(config)
    local player = getAnyLoadedPlayer()
    local cell = getCell()
    if player == nil or player:getCurrentSquare() == nil or cell == nil then
        return false
    end

    local playerSquare = player:getCurrentSquare()
    local centerX = playerSquare:getX()
    local centerY = playerSquare:getY()
    local z = playerSquare:getZ()
    local radius = tonumber(config.obstacleScanRadius) or 12
    local found = {}

    for scanRadius = 0, radius do
        for dx = -scanRadius, scanRadius do
            for dy = -scanRadius, scanRadius do
                if math.max(math.abs(dx), math.abs(dy)) == scanRadius then
                    local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                    if square ~= nil then
                        inspectEdge(
                            found,
                            square,
                            cell:getGridSquare(square:getX() + 1, square:getY(), z),
                            config
                        )
                        inspectEdge(
                            found,
                            square,
                            cell:getGridSquare(square:getX(), square:getY() + 1, z),
                            config
                        )
                    end
                end
            end
        end
    end

    local baseline = findBaselineMovementCase(player, radius)
    if baseline ~= nil then
        table.insert(testCases, baseline)
    else
        reportResult("movement", "SKIP", "no_open_floor_pair", "scanRadius=" .. tostring(radius))
    end

    local obstacleNames = { "door", "window_open", "window_locked", "fence" }
    for _, name in ipairs(obstacleNames) do
        if found[name] ~= nil then
            table.insert(testCases, found[name])
            print(
                TAG
                    .. " DISCOVERED scenario="
                    .. name
                    .. " start="
                    .. squareText(found[name].startSquare)
                    .. " target="
                    .. squareText(found[name].targetSquare)
                    .. " "
                    .. found[name].evidence
            )
        else
            local reason = "no_suitable_fixture_near_player"
            if name == "window_locked" and config.allowDestructiveWindowTest ~= true then
                reason = "destructive_window_test_disabled"
            end
            reportResult(name, "SKIP", reason, "scanRadius=" .. tostring(radius))
        end
    end

    return true
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function removeTestNpc()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return
    end
    local success, result = pcall(function()
        return bridge:removeTestNpc()
    end)
    print(TAG .. " cleanup=" .. tostring(success) .. " result=" .. tostring(result))
end

local function finishActiveCase(status, reason, evidence)
    if completedCases[activeCase.name] then
        return
    end
    completedCases[activeCase.name] = status
    completedCaseCount = completedCaseCount + 1
    reportResult(activeCase.name, status, reason, evidence)
    if status == "PASS" then
        if activeCase.name ~= "movement" then
            obstaclePasses = obstaclePasses + 1
        end
    elseif status == "FAIL" then
        suiteFailures = suiteFailures + 1
    end

    removeTestNpc()
    activeCase = nil
    movementRequested = false
    phase = "BETWEEN_CASES"
    phaseStartedAt = ticks
end

local function finishSuite()
    local evidence = "cases="
        .. tostring(#testCases)
        .. " obstaclePasses="
        .. tostring(obstaclePasses)
        .. " failures="
        .. tostring(suiteFailures)
        .. " completed="
        .. tostring(completedCaseCount)
    if suiteFailures > 0 then
        reportResult("obstacle_suite", "FAIL", "one_or_more_cases_failed", evidence)
    elseif obstaclePasses == 0 then
        reportResult("obstacle_suite", "BLOCKED", "no_obstacle_fixture_tested", evidence)
    else
        reportResult("obstacle_suite", "PASS", "completed", evidence)
    end
    phase = "FINISHED"
    stop()
end

local function startNextCase()
    caseIndex = caseIndex + 1
    activeCase = testCases[caseIndex]
    if activeCase == nil then
        finishSuite()
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        caseIndex = caseIndex - 1
        activeCase = nil
        return
    end

    print(
        TAG
            .. " CASE_START scenario="
            .. activeCase.name
            .. " start="
            .. squareText(activeCase.startSquare)
            .. " target="
            .. squareText(activeCase.targetSquare)
            .. " "
            .. activeCase.evidence
    )
    local success, result = pcall(function()
        return bridge:spawnTestNpc(activeCase.startSquare)
    end)
    print(TAG .. " spawn=" .. tostring(success) .. " result=" .. tostring(result))
    if not success or string.find(tostring(result), "SPAWNED", 1, true) ~= 1 then
        finishActiveCase("FAIL", "spawn_failed", result)
        return
    end

    phase = "SPAWN_SETTLE"
    phaseStartedAt = ticks
end

local function requestMovement()
    local bridge = rawget(_G, "KnoxJavaBridge")
    local success, result = pcall(function()
        if activeCase.name ~= "movement" then
            return bridge:crossTestNpc(activeCase.targetSquare)
        end
        return bridge:moveTestNpc(activeCase.targetSquare)
    end)
    print(TAG .. " movement-request=" .. tostring(success) .. " result=" .. tostring(result))
    local expectedStart = activeCase.name == "movement" and "MOVE_STARTED" or "CROSS_STARTED"
    if not success or string.find(tostring(result), expectedStart, 1, true) ~= 1 then
        finishActiveCase("FAIL", "movement_request", result)
        return
    end

    movementRequested = true
    movementStartedAt = ticks
    phase = "MOVING"
end

local function findMissingTraversalEvidence(bridge)
    for _, state in ipairs(activeCase.expectedTraversalEvidence) do
        local success, found = pcall(function()
            return bridge:hasTestNpcTraversalEvidence(state)
        end)
        if not success or found ~= true then
            return state
        end
    end
    return nil
end

local function findForbiddenTraversalEvidence(bridge)
    for _, state in ipairs(activeCase.forbiddenTraversalEvidence) do
        local success, found = pcall(function()
            return bridge:hasTestNpcTraversalEvidence(state)
        end)
        if success and found == true then
            return state
        end
    end
    return nil
end

local function finishSuccessfulMovement(bridge, tickResult)
    local statusSuccess, statusResult = pcall(function()
        return bridge:getTestNpcStatus()
    end)
    local forbiddenEvidence = findForbiddenTraversalEvidence(bridge)
    local missingEvidence = findMissingTraversalEvidence(bridge)
    if forbiddenEvidence ~= nil then
        finishActiveCase(
            "FAIL",
            "forbidden_traversal_evidence",
            "found=" .. forbiddenEvidence .. " status=" .. tostring(statusResult)
        )
    elseif missingEvidence ~= nil then
        finishActiveCase(
            "FAIL",
            "missing_traversal_evidence",
            "expected=" .. missingEvidence .. " status=" .. tostring(statusResult)
        )
    else
        finishActiveCase(
            "PASS",
            "crossing_completed",
            activeCase.evidence .. " tick=" .. tostring(tickResult)
                .. " status=" .. tostring(statusSuccess and statusResult or "unavailable")
        )
    end
end

local function tickMovement()
    local bridge = rawget(_G, "KnoxJavaBridge")
    local tickSuccess, tickResult = pcall(function()
        return bridge:tickTestNpc()
    end)
    if not tickSuccess
        or string.find(tostring(tickResult), "Failed", 1, true) ~= nil
        or string.find(tostring(tickResult), "TICK_FAILED", 1, true) ~= nil then
        finishActiveCase("FAIL", "controller_tick", tickResult)
        return
    end

    -- Succeeded is a one-tick terminal result. On the next tick the bridge has
    -- already released the route and reports NOT_REQUESTED, so polling status
    -- only every interval turned completed walks and crossings into timeouts.
    if tostring(tickResult) == "Succeeded" then
        finishSuccessfulMovement(bridge, tickResult)
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        local statusSuccess, statusResult = pcall(function()
            return bridge:getTestNpcStatus()
        end)
        print(TAG .. " status=" .. tostring(statusSuccess) .. " result=" .. tostring(statusResult))
        if statusSuccess
            and string.find(tostring(statusResult), "controller=Succeeded", 1, true) ~= nil then
            finishSuccessfulMovement(bridge, statusResult)
            return
        end
    end

    if movementRequested and ticks - movementStartedAt >= MOVE_TIMEOUT_TICKS then
        local statusSuccess, statusResult = pcall(function()
            return bridge:getTestNpcStatus()
        end)
        finishActiveCase(
            "FAIL",
            "timeout",
            statusSuccess and statusResult or "status_unavailable"
        )
    end
end

update = function()
    ticks = ticks + 1

    if phase == "WAIT_DISCOVERY" then
        if ticks - phaseStartedAt < DISCOVERY_DELAY_TICKS then
            return
        end
        local config = rawget(_G, "KnoxDevTests")
        if discoverCases(config) then
            phase = "BETWEEN_CASES"
            phaseStartedAt = ticks - BETWEEN_CASE_TICKS
        end
        return
    end

    if phase == "BETWEEN_CASES" then
        if ticks - phaseStartedAt >= BETWEEN_CASE_TICKS then
            startNextCase()
        end
        return
    end

    if phase == "SPAWN_SETTLE" then
        if ticks - phaseStartedAt >= SPAWN_SETTLE_TICKS then
            requestMovement()
        end
        return
    end

    if phase == "MOVING" then
        tickMovement()
    end
end

function Probe.status()
    return {
        phase = phase,
        finished = phase == "FINISHED",
        failures = suiteFailures,
        passes = obstaclePasses,
        completed = completedCaseCount,
        total = #testCases,
    }
end

function Probe.start()
    local config = rawget(_G, "KnoxDevTests") or {}
    print(
        TAG
            .. " START auto=true scenario=obstacle_suite sandboxOverrides="
            .. tostring(config.sandboxOverrides)
            .. " scanRadius="
            .. tostring(config.obstacleScanRadius)
            .. " destructiveWindowTest="
            .. tostring(config.allowDestructiveWindowTest)
    )
    printScenarioRegistry(config)

    ticks = 0
    phaseStartedAt = 0
    phase = "WAIT_DISCOVERY"
    testCases = {}
    caseIndex = 0
    activeCase = nil
    movementRequested = false
    movementStartedAt = 0
    suiteFailures = 0
    obstaclePasses = 0
    completedCases = {}
    completedCaseCount = 0
    stop()
    Events.OnTick.Add(update)
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true then
        print(TAG .. " DISABLED")
        return
    end
    if config.activeScenario ~= "obstacle_suite" then
        print(TAG .. " INACTIVE activeScenario=" .. tostring(config.activeScenario))
        return
    end

    Probe.start()
end

local function onMainMenuEnter()
    stop()
    removeTestNpc()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
