
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
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 2400
local STATUS_INTERVAL_TICKS = 60
local CONTAINER_SCAN_RADIUS = 24
local TEST_ITEM_TYPE = "Base.Bandage"
local VISIBLE_TRANSFER_TICKS = 120
local LOOT_GATE_KEY = "loot_visible_transfer_v2"

local KnoxNpcInventoryTransferAction = ISInventoryTransferAction:derive(
    "KnoxNpcInventoryTransferAction"
)

-- The stock transfer action also drives the selected local-player loot panel. An
-- off-slot NPC has no loot UI, so preserve the normal action while omitting that UI reference.
function KnoxNpcInventoryTransferAction:startActionAnim()
    ISInventoryTransferAction.startActionAnim(self)
    self.knoxLootAnimationRequested = true
    self.selectedContainer = nil
end

function KnoxNpcInventoryTransferAction:start()
    ISInventoryTransferAction.start(self)
    self.knoxRummageSoundStarted = self.loopSound ~= nil
end

function KnoxNpcInventoryTransferAction:new(character, item, source, destination)
    -- Small items normally transfer in only a handful of ticks. Keep this
    -- development gate visible long enough to confirm the stock Loot animation
    -- and rummaging sound on an off-slot IsoPlayer NPC.
    return ISInventoryTransferAction.new(
        self,
        character,
        item,
        source,
        destination,
        VISIBLE_TRANSFER_TICKS
    )
end

local ticks = 0
local phase = "IDLE"
local npc = nil
local sourceContainer = nil
local targetItem = nil
local transferAction = nil
local actionObserved = false
local lastResult = nil
-- A locked house must not fail the probe when an open one stands nearby.
-- Tried containers are skipped and the next reachable candidate is used.
local triedContainerKeys = {}
local containerAttempts = 0
local MAX_CONTAINER_ATTEMPTS = 4
local update

local function report(status, reason, evidence)
    lastResult = {
        status = tostring(status),
        reason = tostring(reason),
        evidence = tostring(evidence or "none"),
    }
    print(
        TAG
            .. " RESULT scenario=loot status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function fail(reason, evidence)
    report("FAIL", reason, evidence)
    phase = "FINISHED"
    stop()
end

local function removeZombie(zombie)
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end

local function clearLoadedZombies()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.allowZombieCleanup ~= true then
        return 0
    end
    local cell = getCell()
    if cell == nil then
        return 0
    end
    local zombies = cell:getZombieList()
    local removed = 0
    for index = zombies:size() - 1, 0, -1 do
        removeZombie(zombies:get(index))
        removed = removed + 1
    end
    return removed
end

local function squareForRecord(bridge, record)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success then
        return nil, x
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function restoreSurvivor(bridge)
    local persistence = rawget(_G, "KnoxPersistence")
    local record = persistence ~= nil and persistence.getTestRecord() or nil
    if record == nil then
        return false, "missing_persistent_survivor"
    end
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return false, "saved_square_not_loaded location=" .. tostring(location)
    end
    local success, result = pcall(function()
        return bridge:restoreTestNpcRecord(record, square)
    end)
    return success and string.find(tostring(result), "RESTORED", 1, true) == 1, result
end

local function inspectSquare(square, character)
    if square == nil then
        return nil, nil, nil
    end
    local objects = square:getObjects()
    for objectIndex = 0, objects:size() - 1 do
        local object = objects:get(objectIndex)
        local count = object:getContainerCount()
        for containerIndex = 0, count - 1 do
            local container = object:getContainerByIndex(containerIndex)
            if container ~= nil and container:isExistYet() then
                local approach = AdjacentFreeTileFinder.Find(square, character)
                if approach ~= nil then
                    return container, object, approach
                end
            end
        end
    end
    return nil, nil, nil
end

local function containerKey(square, container)
    local ok, text = pcall(function()
        return tostring(square:getX()) .. "," .. tostring(square:getY())
            .. "," .. tostring(square:getZ()) .. ":" .. tostring(container:getType())
    end)
    return ok and text or nil
end

local function findNearestContainer(character)
    local origin = character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then
        return nil, nil, nil
    end
    for radius = 0, CONTAINER_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = cell:getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local container, object, approach = inspectSquare(square, character)
                    if container ~= nil then
                        local key = containerKey(square, container)
                        if key == nil or triedContainerKeys[key] ~= true then
                            return container, object, approach
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

-- Route to the next untried container after a routing failure
-- (locked door, unusable window, stuck). Returns true when a fresh
-- approach started, false when no candidate remains.
local function retryNextContainer(bridge, reason)
    if containerAttempts >= MAX_CONTAINER_ATTEMPTS then
        return false
    end
    pcall(function()
        local parent = sourceContainer ~= nil and sourceContainer:getParent() or nil
        local sourceSquare = parent ~= nil and parent:getSquare() or nil
        if sourceSquare ~= nil and sourceContainer ~= nil then
            local key = containerKey(sourceSquare, sourceContainer)
            if key ~= nil then triedContainerKeys[key] = true end
        end
    end)
    if sourceContainer ~= nil and targetItem ~= nil then
        pcall(function() sourceContainer:Remove(targetItem) end)
        targetItem = nil
    end
    local sourceObject, approachSquare
    sourceContainer, sourceObject, approachSquare = findNearestContainer(npc)
    if sourceContainer == nil then
        return false
    end
    targetItem = sourceContainer:AddItem(TEST_ITEM_TYPE)
    if targetItem == nil then
        return false
    end
    sourceContainer:setDrawDirty(true)
    local moveResult = bridge:moveTestNpc(approachSquare)
    if string.find(tostring(moveResult), "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    containerAttempts = containerAttempts + 1
    print(TAG .. " loot-target=RETRY attempt=" .. tostring(containerAttempts)
        .. "/" .. tostring(MAX_CONTAINER_ATTEMPTS)
        .. " reason=" .. tostring(reason)
        .. " container=" .. tostring(sourceContainer:getType()))
    return true
end

local function beginTransfer()
    local parent = sourceContainer:getParent()
    if parent ~= nil then
        npc:faceThisObject(parent)
        if npc:shouldBeTurning() then
            return false
        end
    end
    transferAction = KnoxNpcInventoryTransferAction:new(
        npc,
        targetItem,
        sourceContainer,
        npc:getInventory()
    )
    ISTimedActionQueue.add(transferAction)
    actionObserved = transferAction.action ~= nil
        and npc:getCharacterActions():contains(transferAction.action)
    phase = "TRANSFERRING"
    print(
        TAG
            .. " loot-action=QUEUED item="
            .. tostring(targetItem:getFullType())
            .. " source="
            .. tostring(sourceContainer:getType())
            .. " durationTicks="
            .. tostring(transferAction.maxTime)
            .. " animationRequested="
            .. tostring(transferAction.knoxLootAnimationRequested == true)
            .. " rummageSound="
            .. tostring(transferAction.knoxRummageSoundStarted == true)
    )
    return true
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_TEST_TICKS then
        fail("timeout", "phase=" .. tostring(phase))
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getAnyLoadedPlayer()
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end

    if ticks % 15 == 0 then
        clearLoadedZombies()
    end

    if phase == "WAIT_START" then
        local restored, result = restoreSurvivor(bridge)
        if not restored then
            if string.find(tostring(result), "saved_square_not_loaded", 1, true) ~= nil then
                return
            end
            fail("survivor_restore_failed", result)
            return
        end
        npc = bridge:getTestNpcCharacterForAction()
        if npc == nil then
            fail("npc_character_unavailable", result)
            return
        end
        print(TAG .. " survivor=" .. tostring(result))

        local persistence = rawget(_G, "KnoxPersistence")
        if persistence.isDevGateComplete(LOOT_GATE_KEY) then
            report("SKIP", "already_passed", "next=health")
            phase = "FINISHED"
            stop()
            return
        end

        local sourceObject, approachSquare
        sourceContainer, sourceObject, approachSquare = findNearestContainer(npc)
        if sourceContainer == nil then
            fail("no_world_container", "radius=" .. tostring(CONTAINER_SCAN_RADIUS))
            return
        end
        targetItem = sourceContainer:AddItem(TEST_ITEM_TYPE)
        if targetItem == nil then
            fail("test_item_creation_failed", TEST_ITEM_TYPE)
            return
        end
        sourceContainer:setDrawDirty(true)
        local moveResult = bridge:moveTestNpc(approachSquare)
        if string.find(tostring(moveResult), "MOVE_STARTED", 1, true) ~= 1 then
            if retryNextContainer(bridge, moveResult) then
                phase = "APPROACHING"
                return
            end
            fail("loot_approach_failed", tostring(moveResult)
                .. " attempts=" .. tostring(containerAttempts))
            return
        end
        phase = "APPROACHING"
        print(
            TAG
                .. " loot-target=FOUND container="
                .. tostring(sourceContainer:getType())
                .. " item="
                .. tostring(targetItem:getFullType())
                .. " object="
                .. tostring(sourceObject:getObjectName())
        )
        return
    end

    if phase == "APPROACHING" then
        local movement = tostring(bridge:tickTestNpc())
        if string.find(movement, "Failed", 1, true) ~= nil
            or string.find(movement, "TICK_FAILED", 1, true) ~= nil then
            -- Locked door / unusable window / stuck: hop to the next
            -- reachable container instead of failing the whole probe.
            if retryNextContainer(bridge, movement) then
                return
            end
            fail("loot_approach_failed", movement
                .. " attempts=" .. tostring(containerAttempts))
            return
        end
        if movement == "Succeeded" then
            phase = "FACING"
        end
        if ticks % STATUS_INTERVAL_TICKS == 0 then
            print(TAG .. " loot-status=APPROACHING movement=" .. movement)
        end
        return
    end

    if phase == "FACING" then
        beginTransfer()
        return
    end

    if phase ~= "TRANSFERRING" then
        return
    end

    if not npc:getCharacterActions():isEmpty() then
        actionObserved = true
    end
    local destination = npc:getInventory()
    if destination:contains(targetItem) and not sourceContainer:contains(targetItem) then
        if not actionObserved then
            fail("transfer_without_timed_action", targetItem:getFullType())
            return
        end
        local persistence = rawget(_G, "KnoxPersistence")
        local saved, record = persistence.captureActiveTestSurvivor()
        if not saved then
            fail("post_loot_save_failed", record)
            return
        end
        persistence.markDevGateComplete("loot")
        persistence.markDevGateComplete(LOOT_GATE_KEY)
        report(
            "PASS",
            "item_transferred",
            "item=" .. targetItem:getFullType()
                .. " actionObserved=" .. tostring(actionObserved)
                .. " animationRequested="
                .. tostring(transferAction.knoxLootAnimationRequested == true)
                .. " rummageSound="
                .. tostring(transferAction.knoxRummageSoundStarted == true)
                .. " inventoryItems=" .. tostring(destination:getItems():size())
        )
        phase = "FINISHED"
        stop()
        return
    end

    if transferAction ~= nil
        and not ISTimedActionQueue.hasAction(transferAction)
        and npc:getCharacterActions():isEmpty() then
        fail(
            "transfer_action_ended_without_item",
            "sourceContains=" .. tostring(sourceContainer:contains(targetItem))
        )
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(
            TAG
                .. " loot-status=TRANSFERRING actionObserved="
                .. tostring(actionObserved)
                .. " sourceContains="
                .. tostring(sourceContainer:contains(targetItem))
        )
    end
end

local function start()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "loot" then
        return false, "disabled"
    end
    print(
        TAG
            .. " START auto=true scenario=loot clearsLoadedZombies=false sandboxOverrides=false"
    )
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    sourceContainer = nil
    targetItem = nil
    transferAction = nil
    actionObserved = false
    lastResult = nil
    triedContainerKeys = {}
    containerAttempts = 0
    stop()
    Events.OnTick.Add(update)
    return true, "started"
end

local function onGameStart()
    start()
end

local function onMainMenuEnter()
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    if npc ~= nil and transferAction ~= nil and ISTimedActionQueue.hasAction(transferAction) then
        ISTimedActionQueue.clear(npc)
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

local Probe = rawget(_G, "KnoxLootProbe") or {}
_G.KnoxLootProbe = Probe
function Probe.start()
    return start()
end
function Probe.status()
    return {
        phase = phase,
        finished = phase == "FINISHED",
        result = lastResult,
        ticks = ticks,
    }
end
function Probe.cleanup()
    if npc ~= nil and transferAction ~= nil and ISTimedActionQueue.hasAction(transferAction) then
        pcall(function() ISTimedActionQueue.clear(npc) end)
    end
    stop()
end
