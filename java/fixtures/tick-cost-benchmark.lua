-- Real per-tick cost benchmark for the survivor controller. The harness times
-- KS_BENCH_RUN outside this setup, so scenario construction is not part of the
-- number. Every measured tick calls the production Controller:tick on every
-- survivor; only the native engine surfaces (cell, body, bridge) are stubbed.
-- These are Kahlua interpretation costs on the production Lua, not native
-- Project Zomboid frame times.
local C = assert(KnoxAutonomyController)

local saved = {}
for _, name in ipairs({
    "getCell", "instanceof", "KnoxCompanionVehicles", "KnoxSurvivorRuntime",
    "getNumActivePlayers", "getSpecificPlayer",
}) do
    saved[name] = rawget(_G, name)
end

local SURVIVORS = 24
local ZOMBIES = 150
local SCAN_TICKS = 15
local zombieCount = ZOMBIES
local EMPTY_ACTIONS = { isEmpty = function() return true end }

-- Isolated native surfaces. A square answers exactly the reads the controller
-- makes; nothing is invented that a missing method would otherwise supply.
local function makeSquare(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
        isBlockedTo = function() return false end,
        isHoppableTo = function() return false end,
        getMovingObjects = function() return { size = function() return 0 end } end,
        getRoom = function() return nil end,
        getBuilding = function() return nil end,
    }
end

-- One deterministic population: a fifth inside the flee radius, a third inside
-- the visible radius, the rest further out but still on the threat list.
local zombieSquaresNear, zombieSquaresFar, activeSquares, zombies = {}, {}, nil, {}
for index = 1, ZOMBIES do
    local angle = index * 2.39996323
    local radius = 6
    if index % 3 == 0 then radius = 11 end
    if index % 5 == 0 then radius = 28 + (index % 31) end
    local x = 8700 + math.floor(math.cos(angle) * radius)
    local y = 8700 + math.floor(math.sin(angle) * radius)
    zombieSquaresNear[index] = makeSquare(x, y, 0)
    local farRadius = 40 + (index % 20)
    zombieSquaresFar[index] = makeSquare(
        8700 + math.floor(math.cos(angle) * farRadius),
        8700 + math.floor(math.sin(angle) * farRadius), 0)
    local home = zombieSquaresNear[index]
    zombies[index] = {
        getCurrentSquare = function() return activeSquares[index] or home end,
        isDead = function() return false end,
        isCrawling = function() return false end,
        isOnFloor = function() return false end,
        isClimbing = function() return false end,
        getTarget = function() return nil end,
        CanSee = function() return false end,
        getPrimaryHandItem = function() return nil end,
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
    }
end
-- The fact-cache contract the scans rely on: one read per zombie per tick,
-- and a new tick must read the zombie again. The unfixed baseline predates the
-- cache, so the contract is checked whenever the module is present.
local factAwareness = rawget(_G, "KnoxZombieAwareness")
if factAwareness ~= nil and factAwareness.zombieFacts ~= nil then
    local probe = zombies[1]
    local firstFact = factAwareness.zombieFacts(probe, 900001)
    local againFact = factAwareness.zombieFacts(probe, 900001)
    local nextFact = factAwareness.zombieFacts(probe, 900002)
    assert(firstFact ~= nil and firstFact == againFact,
        "one fact set per zombie per tick")
    assert(nextFact ~= nil and nextFact ~= firstFact,
        "a new tick reads the zombie again")
end

local zombieList = {
    size = function() return zombieCount end,
    isEmpty = function() return zombieCount == 0 end,
    get = function(_, index) return zombies[index + 1] end,
}
local cellReads = 0
local cell = {
    getGridSquare = function(_, x, y, z) return makeSquare(x, y, z or 0) end,
    getZombieList = function() cellReads = cellReads + 1 return zombieList end,
}

local function makeBody(x, y)
    local home = makeSquare(x, y, 0)
    local stats = { get = function() return 1 end }
    local damage = { getHealth = function() return 100 end }
    local moodles = { getMoodleLevel = function() return 0 end }
    return {
        getCurrentSquare = function() return home end,
        getCharacterActions = function() return EMPTY_ACTIONS end,
        getCurrentStateName = function() return "idle" end,
        getCurrentActionContextStateName = function() return "idle" end,
        getVehicle = function() return nil end,
        isDead = function() return false end,
        getStats = function() return stats end,
        getBodyDamage = function() return damage end,
        getMoodles = function() return moodles end,
        getBodyPartClothingDefense = function() return 30 end,
        CanSee = function() return false end,
        isSitOnGround = function() return false end,
        isSittingOnFurniture = function() return false end,
        isKnockedDown = function() return false end,
        isOnFloor = function() return false end,
        isPerformingAttackAnimation = function() return false end,
        isPerformingShoveAnimation = function() return false end,
        isPerformingStompAnimation = function() return false end,
        isPerformingGrappleGrabAnimation = function() return false end,
        isAsleep = function() return false end,
        isPlayerMoving = function() return false end,
        getPrimaryHandItem = function() return nil end,
        isClimbing = function() return false end,
        getInventory = function() return nil end,
        isRunning = function() return false end,
        isSprinting = function() return false end,
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
    }
end

local tickNpcCalls = 0
local function makeBridge()
    return setmetatable({
        tickNpc = function() tickNpcCalls = tickNpcCalls + 1 return "MOVING" end,
        tickNpcCombat = function() return "COMBAT_WAITING" end,
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
        moveNpc = function() return "MOVE_STARTED" end,
        moveNpcWithPace = function() return "MOVE_STARTED" end,
        observeNpcNativeAction = function() end,
        observeNpcNativeRecovery = function() end,
        getNpcWindowForGlassRemoval = function() return nil end,
    }, { __index = function() return function() return "" end end })
end

local bench = nil

function KS_BENCH_SETUP(mode)
    mode = tostring(mode)
    cellReads, tickNpcCalls = 0, 0
    -- Attribution modes: the full population is the headline; the variants
    -- only separate zombie-side from ally-side work in the same scan path.
    local survivorCount = (mode == "scan_solo" or mode == "scan_solo_far") and 1 or SURVIVORS
    zombieCount = mode == "scan_empty" and 0 or ZOMBIES
    activeSquares = mode == "scan_solo_far" and zombieSquaresFar or zombieSquaresNear
    local controllers = {}
    local list, byId, byCharacter = {}, {}, {}
    for index = 1, survivorCount do
        local moving = mode == "movement" or (mode == "full" and index % 2 == 0)
        local scanning = mode == "scan" or mode == "scan_solo"
            or mode == "scan_solo_far" or mode == "scan_empty" or mode == "full"
        local phase = (index - 1) % SCAN_TICKS
        local id = "bench-" .. tostring(index)
        local body = makeBody(8700 + (index % 4), 8700 + math.floor(index / 4))
        local controller = setmetatable({
            id = id,
            character = body,
            bridge = makeBridge(),
            state = moving and "MOVING_TO_EXPLORE" or "IDLE",
            observedState = moving and "MOVING_TO_EXPLORE" or "IDLE",
            stateStartedAt = 0,
            currentTicks = 0,
            nextThink = math.huge,
            nextThreatScan = scanning and phase or math.huge,
            nextIdleLatchCheck = 0,
            perceptionPhase = phase,
            counts = { needs = 0, combat = 0, failures = 0, search = 0 },
            failedThreats = {},
            selfCareRetryAt = {},
            reservations = { threats = {} },
            perceivedThreats = setmetatable({}, { __mode = "k" }),
        }, C)
        controllers[index] = controller
        list[#list + 1] = id
        byId[id] = controller
        byCharacter[body] = id
    end
    _G.KnoxSurvivorRuntime = {
        activeIds = function() return list end,
        getCharacter = function(id) return byId[id] ~= nil and byId[id].character or nil end,
        idForCharacter = function(character) return byCharacter[character] end,
        getController = function(id) return byId[id] end,
        canInteract = function() return true end,
    }
    _G.getNumActivePlayers = function() return 1 end
    _G.getSpecificPlayer = function() return nil end
    _G.getCell = function() return cell end
    _G.instanceof = function() return false end
    _G.KnoxCompanionVehicles = nil
    bench = { mode = mode, controllers = controllers, ticks = 0 }
    return true
end

function KS_BENCH_RUN(count)
    if bench == nil then error("KS_BENCH_SETUP must run first") end
    for _ = 1, count do
        bench.ticks = bench.ticks + 1
        local ticks = bench.ticks
        for index = 1, #bench.controllers do
            local controller = bench.controllers[index]
            controller.currentTicks = ticks
            controller:tick(ticks)
        end
    end
    return count * #bench.controllers
end

function KS_BENCH_REPORT()
    if bench == nil then return end
    print("Tick benchmark scenario mode=" .. tostring(bench.mode)
        .. " survivors=" .. tostring(#bench.controllers)
        .. " zombies=" .. tostring(zombieCount)
        .. " ticks=" .. tostring(bench.ticks)
        .. " cellReads=" .. tostring(cellReads)
        .. " tickNpcCalls=" .. tostring(tickNpcCalls))
end

function KS_BENCH_RESTORE()
    for _, name in ipairs({
        "getCell", "instanceof", "KnoxCompanionVehicles", "KnoxSurvivorRuntime",
        "getNumActivePlayers", "getSpecificPlayer",
    }) do
        _G[name] = saved[name]
    end
    bench = nil
end
