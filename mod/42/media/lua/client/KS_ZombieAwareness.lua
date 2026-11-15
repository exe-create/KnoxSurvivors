require "KS_ThreatClassifier"
require "KS_ZombieDiscovery"
local function isCorpseProxy(character)
    local threats = rawget(_G, "KnoxThreatClassifier")
    return threats ~= nil and threats.isCorpseProxy(character) or false
end

local ZombieAwareness = rawget(_G, "KnoxZombieAwareness") or {}
_G.KnoxZombieAwareness = ZombieAwareness

-- One cell zombie list per tick
-- Awareness, threat scans, pressure reads and combat positioning all ask the
-- same cell for the identical candidate set inside one frame. They now share the
-- single list handle, keyed by cell identity and tick, instead of each asking the
-- cell again. Nothing is copied and nothing outlives the tick that filled it.
local zombieListTick, zombieListCell, zombieList = nil, nil, nil
function ZombieAwareness.zombieList(cell, ticks)
    if cell == nil then cell = getCell ~= nil and getCell() or nil end
    if cell == nil or cell.getZombieList == nil then return nil end
    local tick = tonumber(ticks)
    if tick == nil then tick = ZombieAwareness.currentTicks end
    if zombieList ~= nil and tick ~= nil and zombieListTick == tick
        and zombieListCell == cell then
        return zombieList
    end
    local ok, list = pcall(cell.getZombieList, cell)
    if not ok then return nil end
    zombieListTick, zombieListCell, zombieList = tick, cell, list
    return list
end
-- End of the shared zombie list cache

-- One zombie fact set per tick
-- The stealth, retreat and acquisition passes inside one scan ask the same
-- zombie for the same square, death, corpse, target and climb state. They are
-- read once per tick and dropped at the next tick; this holds no decision,
-- copies nothing out of the tick, and does not change what any pass evaluates.
local factsTick, facts = nil, setmetatable({}, { __mode = "k" })
function ZombieAwareness.zombieFacts(zombie, ticks)
    if zombie == nil then return nil end
    local tick = tonumber(ticks)
    if tick == nil then tick = ZombieAwareness.currentTicks end
    if tick == nil then return nil end
    if tick ~= factsTick then
        factsTick = tick
        facts = setmetatable({}, { __mode = "k" })
    end
    local cached = facts[zombie]
    if cached ~= nil then return cached end
    local fact = { square = nil, x = nil, y = nil, z = nil, dead = false,
        corpse = false, target = nil, climbing = false, ignored = false,
        onFloor = false, crawling = false }
    if zombie.getCurrentSquare ~= nil then
        local ok, square = pcall(zombie.getCurrentSquare, zombie)
        if ok and square ~= nil then
            fact.square = square
            fact.x, fact.y, fact.z = square:getX(), square:getY(), square:getZ()
        end
    end
    if zombie.isDead ~= nil then
        local ok, dead = pcall(zombie.isDead, zombie)
        fact.dead = ok and dead == true
    end
    fact.corpse = isCorpseProxy(zombie)
    if zombie.getTarget ~= nil then
        local ok, target = pcall(zombie.getTarget, zombie)
        fact.target = ok and target or nil
    end
    if zombie.isClimbing ~= nil then
        local ok, climbing = pcall(zombie.isClimbing, zombie)
        fact.climbing = ok and climbing == true
    end
    if zombie.isOnFloor ~= nil then
        local ok, onFloor = pcall(zombie.isOnFloor, zombie)
        fact.onFloor = ok and onFloor == true
    end
    if zombie.isCrawling ~= nil then
        local ok, crawling = pcall(zombie.isCrawling, zombie)
        fact.crawling = ok and crawling == true
    end
    local classifier = rawget(_G, "KnoxThreatClassifier")
    fact.ignored = classifier ~= nil and classifier.ignoreForeignNpc ~= nil
        and classifier.ignoreForeignNpc(zombie) == true
    facts[zombie] = fact
    return fact
end

-- One active-player list per tick. Threat evaluation asks whether each
-- candidate is a player; rebuilding the same short list per candidate was the
-- repeated part, not the identity test.
local playersTick, players = nil, nil
function ZombieAwareness.playerList(ticks)
    local tick = tonumber(ticks)
    if tick == nil then tick = ZombieAwareness.currentTicks end
    if tick == nil then return nil end
    if tick ~= playersTick then
        playersTick = tick
        players = {}
        if getNumActivePlayers ~= nil and getSpecificPlayer ~= nil then
            local count = tonumber(getNumActivePlayers()) or 1
            for index = 0, math.max(0, count - 1) do
                local player = getSpecificPlayer(index)
                if player ~= nil then players[#players + 1] = player end
            end
        end
    end
    return players
end

-- Off-slot IsoPlayer shells cannot use IsoPlayer.updateLOS because it writes into
-- local-player lighting. This module supplies only the missing discovery/perception
-- edge; zombie locomotion, attack state, animation, hit rolls, and damage stay vanilla.
--
-- Build 42's LightingJNI visibility state belongs to a real local-player
-- lighting slot. An off-slot survivor shell can read perception through the
-- native target APIs, but writing setCouldSee for that shell repeatedly throws
-- from LightingJNI. Keep combat authoritative: do not synthesize that bit, and
-- let a native bite that cannot complete report its own failure instead.
local visibilityBits = {}
local visibilityBitDisabledReported = false
local AWARENESS_RADIUS_SQUARED = 20 * 20
local SWITCH_MARGIN = 1.0
local NPC_INTERCEPT_RADIUS = 3.0
local REPORT_COOLDOWN_TICKS = 1800
local CLOSE_ATTACK_REFRESH_RADIUS_SQUARED = 2.25 * 2.25
local CLOSE_ATTACK_REFRESH_TICKS = 6
local ACTIVE_TARGET_REFRESH_TICKS = 30
local TARGET_MEMORY_TICKS = 180
local lastFailureReport = -REPORT_COOLDOWN_TICKS
local closeCombatReports = setmetatable({}, { __mode = "k" })
local closeCombatTargets = setmetatable({}, { __mode = "k" })
local targetMemory = setmetatable({}, { __mode = "k" })

local function validNpc(character)
    return character ~= nil
        and character:getCurrentSquare() ~= nil
        and not character:isDead()
end

local function validTarget(target)
    if target == nil then
        return false
    end
    local success, square, dead = pcall(function()
        return target:getCurrentSquare(), target:isDead()
    end)
    return success and square ~= nil and dead ~= true
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function canSeeTarget(observer, target)
    local success, visible = pcall(function()
        return observer:CanSee(target)
    end)
    return success and visible == true
end

local function playerTarget(target)
    if target == nil or getSpecificPlayer == nil then
        return false
    end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for index = 0, math.max(0, tonumber(count) or 1) - 1 do
        if getSpecificPlayer(index) == target then
            return true
        end
    end
    return false
end

local function reportFailure(ticks, result)
    if ticks - lastFailureReport >= REPORT_COOLDOWN_TICKS then
        lastFailureReport = ticks
        print("[KnoxSurvivors][ZombieAwareness] perception_failed=" .. tostring(result))
    end
end

-- Do not invoke IsoGridSquare:setCouldSee for off-slot NPC shells. The method
-- reaches LightingJNI and is unsafe for their viewer index in Build 42.
local function ensureVisibilityBit(id, npc)
    if visibilityBits[id] ~= nil then visibilityBits[id] = nil end
    if not visibilityBitDisabledReported then
        visibilityBitDisabledReported = true
        print("[KnoxSurvivors][ZombieAwareness] visibility_bit_disabled"
            .. " reason=build42_offslot_lightingjni_unsafe")
    end
    return false
end

local function clearVisibilityBit(id)
    visibilityBits[id] = nil
end

-- Drop close combat and discard any old in-memory visibility bookkeeping.
local function dropCloseCombat(zombie)
    local entry = closeCombatTargets[zombie]
    closeCombatTargets[zombie] = nil
    local id = type(entry) == "table" and entry.id or entry
    if id ~= nil then clearVisibilityBit(id) end
end

local function directZombie(bridge, zombie, id, ticks)
    local success, result = pcall(function()
        return tostring(bridge:directZombieAtNpc(id, zombie))
    end)
    if not success
        or string.find(result or "", "ZOMBIE_DIRECTED status=", 1, true) ~= 1 then
        reportFailure(ticks, result)
    elseif string.find(result, "status=attack-ready", 1, true) ~= nil
        or string.find(result, "status=blocked-close", 1, true) ~= nil then
        local lastReport = closeCombatReports[zombie] or -REPORT_COOLDOWN_TICKS
        if ticks - lastReport >= 300 then
            closeCombatReports[zombie] = ticks
            print("[KnoxSurvivors][ZombieAwareness] " .. result)
        end
    end
    return success, result
end

local function rememberTarget(zombie, id, ticks, perceived, directed)
    local memory = targetMemory[zombie]
    if memory == nil then
        memory = {}
        targetMemory[zombie] = memory
    end
    memory.id = id
    if perceived then
        memory.lastSeen = ticks
    end
    if directed then
        memory.lastDirected = ticks
    end
    return memory
end

local function rememberedNpc(controllers, memory, ticks, zombieSquare)
    if memory == nil or memory.id == nil
        or ticks - (memory.lastSeen or -TARGET_MEMORY_TICKS - 1) > TARGET_MEMORY_TICKS then
        return nil
    end
    local controller = controllers ~= nil and controllers[memory.id] or nil
    local npc = controller ~= nil and controller.character or nil
    local npcSquare = validNpc(npc) and npc:getCurrentSquare() or nil
    return npcSquare ~= nil and zombieSquare ~= nil
        and npcSquare:getZ() == zombieSquare:getZ() and npc or nil
end

function ZombieAwareness.update(controllers, orderedIds, ticks)
    if getCell() == nil then
        return
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.directZombieAtNpc == nil then
        return
    end

    -- The NPC shell has no LOS render channel of its own. Once a zombie is in the
    -- bite envelope, refresh only that small active set every tick so Build 42's
    -- bCanSeeTarget and targetSeenTime animation gates survive until collision.
    for zombie, entry in pairs(closeCombatTargets) do
        local id = type(entry) == "table" and entry.id or entry
        local controller = controllers ~= nil and controllers[id] or nil
        local npc = controller ~= nil and controller.character or nil
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        local npcSquare = npc ~= nil and npc:getCurrentSquare() or nil
        if zombie == nil or zombie:isDead() or isCorpseProxy(zombie) or not validNpc(npc)
            or zombieSquare == nil or npcSquare == nil
            or zombie:getTarget() ~= npc
            or zombieSquare:getZ() ~= npcSquare:getZ()
            or distanceSquared(zombieSquare, npcSquare) > CLOSE_ATTACK_REFRESH_RADIUS_SQUARED
            or not canSeeTarget(zombie, npc) then
            dropCloseCombat(zombie)
        elseif ticks >= (type(entry) == "table" and entry.nextRefresh or 0) then
            directZombie(bridge, zombie, id, ticks)
            ensureVisibilityBit(id, npc)
            closeCombatTargets[zombie] = {
                id = id,
                nextRefresh = ticks + CLOSE_ATTACK_REFRESH_TICKS,
            }
            rememberTarget(zombie, id, ticks, true, true)
        end
    end

    if ticks % 15 ~= 0 then
        return
    end
    ZombieAwareness.currentTicks = ticks
    local zombies = ZombieAwareness.zombieList(getCell(), ticks)
    if zombies == nil or zombies:isEmpty() then
        return
    end

    -- Snapshot the small active NPC set once per awareness pass.  The old inner
    -- loop repeatedly resolved controllers, squares, death state, and the native
    -- attack gate for every zombie.  That multiplied hot-path work without
    -- changing the decision.  A per-pass snapshot keeps the same LOS/target
    -- semantics while avoiding redundant reflection-backed character calls.
    local candidates = {}
    local candidatesById = {}
    for _, id in ipairs(orderedIds or {}) do
        local controller = controllers ~= nil and controllers[id] or nil
        local npc = controller ~= nil and controller.character or nil
        if validNpc(npc) then
            pcall(function() npc:setZombiesDontAttack(false) end)
            local candidate = { id = id, npc = npc, square = npc:getCurrentSquare(),
                discovery = KnoxZombieDiscovery.snapshot(npc) }
            candidates[#candidates + 1] = candidate
            candidatesById[id] = candidate
        end
    end

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombieSquare ~= nil then
            local currentTarget = zombie:getTarget()
            local currentNpcId = nil
            local currentNpcVisible = false
            local nearestId = nil
            local nearestDistance = AWARENESS_RADIUS_SQUARED + 1

            for _, candidate in ipairs(candidates) do
                local id, npc, npcSquare = candidate.id, candidate.npc, candidate.square
                if npcSquare ~= nil then
                    if currentTarget == npc then
                        currentNpcId = id
                    end
                    if npcSquare:getZ() == zombieSquare:getZ() then
                        local distance = distanceSquared(zombieSquare, npcSquare)
                        local visible = distance <= AWARENESS_RADIUS_SQUARED
                            and canSeeTarget(zombie, npc)
                        if currentTarget == npc then
                            currentNpcVisible = visible
                        end
                        local discovered = currentTarget == npc and visible
                            or KnoxZombieDiscovery.canAcquire(zombie, npc,
                                candidate.discovery, ticks, distance, visible)
                        if discovered and distance < nearestDistance then
                            nearestId = id
                            nearestDistance = distance
                        end
                    end
                end
            end

            local memory = targetMemory[zombie]
            local hadMemory = memory ~= nil
            local memoryNpc = rememberedNpc(controllers, memory, ticks, zombieSquare)
            local memoryId = memoryNpc ~= nil and memory.id or nil
            if memory ~= nil and memoryId == nil then
                targetMemory[zombie] = nil
                memory = nil
            end
            -- A native target assignment can represent engine hearing even before
            -- geometry LOS succeeds. Admit it once into the same bounded memory;
            -- never refresh that memory merely because the target field remains set.
            if currentNpcId ~= nil and not hadMemory and memory == nil then
                memory = rememberTarget(zombie, currentNpcId, ticks, true, false)
                memoryId = currentNpcId
            end

            local preferredId = rawget(_G, "KnoxCombatTestScenarios") ~= nil
                and KnoxCombatTestScenarios.preferredNpcId ~= nil
                and KnoxCombatTestScenarios.preferredNpcId(zombie) or nil
            local preferredCandidate = preferredId ~= nil and candidatesById[preferredId] or nil
            local preferredSquare = preferredCandidate ~= nil and preferredCandidate.square or nil
            if preferredSquare == nil or preferredSquare:getZ() ~= zombieSquare:getZ() then
                preferredId = nil
            end

            -- Keep a native zombie target stable. Memory is only a fallback when the
            -- engine has temporarily dropped the target; it never overrides a live
            -- player target merely because an NPC is nearby.
            local selectedId = preferredId
                or (currentNpcVisible and currentNpcId or nil)
                or (currentNpcId == memoryId and currentNpcId or nil)
            if selectedId == nil and currentTarget == nil then
                selectedId = memoryId
            end
            if selectedId == nil and nearestId ~= nil then
                if not validTarget(currentTarget) then
                    selectedId = nearestId
                elseif playerTarget(currentTarget) then
                    local targetSquare = currentTarget:getCurrentSquare()
                    if targetSquare ~= nil and targetSquare:getZ() == zombieSquare:getZ() then
                        local currentDistance = math.sqrt(distanceSquared(zombieSquare, targetSquare))
                        local npcDistance = math.sqrt(nearestDistance)
                        if npcDistance <= NPC_INTERCEPT_RADIUS
                            or npcDistance + SWITCH_MARGIN < currentDistance then
                            selectedId = nearestId
                        end
                    end
                end
            end

            if selectedId ~= nil then
                local selectedCandidate = candidatesById[selectedId]
                local npc = selectedCandidate ~= nil and selectedCandidate.npc or nil
                local sameNativeTarget = validNpc(npc) and zombie:getTarget() == npc
                local perceived = preferredId == selectedId or canSeeTarget(zombie, npc)
                local shouldRefresh = not sameNativeTarget
                if sameNativeTarget then
                    memory = memory or rememberTarget(
                        zombie, selectedId, ticks, perceived, false
                    )
                    shouldRefresh = perceived
                        and ticks - (memory.lastDirected or -ACTIVE_TARGET_REFRESH_TICKS)
                            >= ACTIVE_TARGET_REFRESH_TICKS
                end
                if shouldRefresh then
                    directZombie(bridge, zombie, selectedId, ticks)
                    rememberTarget(zombie, selectedId, ticks, perceived, true)
                else
                    rememberTarget(zombie, selectedId, ticks, perceived, false)
                end
                if selectedCandidate ~= nil and zombie:getTarget() == npc
                    and perceived
                    and distanceSquared(zombieSquare, selectedCandidate.square)
                        <= CLOSE_ATTACK_REFRESH_RADIUS_SQUARED then
                    closeCombatTargets[zombie] = {
                        id = selectedId,
                        nextRefresh = ticks + CLOSE_ATTACK_REFRESH_TICKS,
                    }
                    ensureVisibilityBit(selectedId, npc)
                end
            elseif currentNpcId ~= nil and memoryId == nil then
                -- The off-slot visibility adapter cannot let the engine expire this
                -- target through a local-player lighting slot. Release only the NPC
                -- target whose bounded Knox perception memory has actually expired.
                pcall(function()
                    zombie:setTarget(nil)
                end)
                targetMemory[zombie] = nil
                dropCloseCombat(zombie)
            elseif currentTarget == nil then
                targetMemory[zombie] = nil
                dropCloseCombat(zombie)
            end
        end
    end
end

return ZombieAwareness
