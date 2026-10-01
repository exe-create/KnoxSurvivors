require "KS_SurvivorAutonomyController"
require "KS_CharacterAppearance"
require "KS_Persistence"
require "KS_SurvivorRelationships"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_CompanionService"
require "KS_Settings"
require "KS_SpouseStart"
require "KS_ZombieAwareness"
require "KS_WorldPopulation"
require "KS_SurvivorStartingGear"
require "KS_SurvivorLifecyclePolicy"
require "KS_UnloadedSurvival"
require "KS_FactionCamps"
require "KS_SurvivorNameplates"
require "KS_HumanCombatRelations"
require "KS_FactionProperty"
require "KS_KnoxEvents"
require "KS_EventRuntime"
require "KS_BaseManager"
require "KS_GroupScavenge"

local TAG = "[KnoxSurvivors][Autonomy]"
local Autonomy = rawget(_G, "KnoxSurvivorAutonomy") or {}
_G.KnoxSurvivorAutonomy = Autonomy
local activeIds = {}
local STATUS_INTERVAL_TICKS = 300
local RELATIONSHIP_INTERVAL_TICKS = 60
local POPULATION_INTERVAL_TICKS = 300
local HIBERNATION_INTERVAL_TICKS = 30
local DEFAULT_ACTIVATION_DISTANCE = 280
local function activationDistance()
    return KnoxSettings.survivorEncounterDistance ~= nil
        and KnoxSettings.survivorEncounterDistance() or DEFAULT_ACTIVATION_DISTANCE
end
local function hibernationDistance()
    return activationDistance() + 40
end
local function hibernationDistanceSquared()
    local distance = hibernationDistance()
    return distance * distance
end
local DETACHED_GRACE_CHECKS = 3
local DETACHED_COMPANION_GRACE_CHECKS = 10
local detachedGrace = {}
local recentlyDetached = {}
local departureRetryAt = {}
local departureFailures = {}
local DECISIONS_REQUIRED = 2
local GATE_KEY = "multi_survival_autonomy_v1"
local FACTION_BASE_GATE_KEY = "faction_base_scouting_v1"

local controllers = {}
local hibernateRollbackPending = {}
local reservations = {
    threats = {}, items = {}, containers = {}, restSpots = {}, campPositions = {},
    supportRecipients = {}, supportItems = {}, ambientSpots = {},
    playerFormationTargets = {}, partyDestinationTargets = {},
}
local ticks = 0
local populationReady = false
local passReported = false
local factionBasePassReported = false
local currentScenario = "none"
local scenarioConfigured = false
local scenarioIds = {}
local nextPopulationUpdate = 0
local nextHibernationUpdate = 0
local populationStatus = nil
local bridgeMissingReported = false
local update

-- Reconcile settlement defaults after residents join or return.  The existing
-- manager owns idempotent zone/storage creation; this cadence only makes that
-- owner reachable beyond the initial game-start hook.
local function reconcileSettlementDefinitions()
    if KnoxPersistence.reconcileAllBaseTaskClaims ~= nil then
        local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        KnoxPersistence.reconcileAllBaseTaskClaims(now)
    end
    local manager = rawget(_G, "KnoxBaseManager")
    if manager == nil then return end
    if manager.ensureFactionBases ~= nil then
        pcall(manager.ensureFactionBases)
    end
    if manager.ensurePlayerBases ~= nil then
        pcall(manager.ensurePlayerBases)
    end
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function reportFactionBasePassIfReady()
    if factionBasePassReported then
        return
    end
    for _, id in ipairs(scenarioIds) do
        local faction = KnoxPersistence.getFactionForSurvivor(id)
        if faction ~= nil and faction.homeBase ~= nil
            and faction.engineSafehouseId ~= nil then
            factionBasePassReported = true
            KnoxPersistence.markDevGateComplete(FACTION_BASE_GATE_KEY)
            print(
                TAG .. " RESULT scenario=faction_base status=PASS"
                    .. " faction=" .. tostring(faction.id)
                    .. " leader=" .. tostring(faction.leaderId)
                    .. " members=" .. table.concat(faction.memberIds or {}, ",")
                    .. " building=" .. tostring(faction.homeBase.buildingId)
                    .. " score=" .. tostring(faction.homeBase.score)
                    .. " safehouse=" .. tostring(faction.engineSafehouseId)
            )
            return
        end
    end
end

local function squareForRecord(bridge, record)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success or getCell() == nil then
        return nil, tostring(x)
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function findSpawnSquare(origin)
    if origin == nil or getCell() == nil then
        return nil
    end
    local activeCharacters = {}
    for _, controller in pairs(controllers) do
        activeCharacters[#activeCharacters + 1] = controller.character
    end
    local minimumRadius = KnoxSettings.developerSpawnDistance()
    for radius = minimumRadius, math.max(minimumRadius + 8, 14) do
        local candidates = {}
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local separated = square ~= nil and square:canStand()
                    if separated then
                        for _, character in ipairs(activeCharacters) do
                            if character:getCurrentSquare() ~= nil
                                and distanceSquared(square, character:getCurrentSquare()) < 25 then
                                separated = false
                                break
                            end
                        end
                    end
                    if separated then
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

local function createSurvivorAt(bridge, id, square, developerKit)
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
    local eventPolicy = KnoxEventFactions ~= nil
        and KnoxEventFactions.materializationPolicy(id)
        or nil
    local capabilities, capabilityResult = KnoxSurvivorCapabilities.ensureForOrigin(
        id,
        character,
        true,
        eventPolicy ~= nil and eventPolicy.professionId or nil,
        KnoxPersistence.getSurvivorOrigin(id)
    )
    if capabilities == nil then
        bridge:removeNpc(id)
        return nil, "capabilities_failed=" .. tostring(capabilityResult)
    end
    local appearanceOk, appearance = KnoxCharacterAppearance.randomizeNewSurvivor(
        bridge,
        id,
        capabilities,
        eventPolicy ~= nil and eventPolicy.appearanceItems or nil
    )
    if not appearanceOk then
        bridge:removeNpc(id)
        return nil, "appearance_failed=" .. tostring(appearance)
    end
    local equipmentOk = true
    local equipped
    if developerKit then
        equipped = tostring(bridge:seedAndEquipNpc(id))
        equipmentOk = string.find(equipped, "EQUIPPED", 1, true) == 1
    else
        equipmentOk, equipped = KnoxSurvivorStartingGear.initialize(
            id,
            character,
            bridge,
            eventPolicy ~= nil and eventPolicy.loadoutTheme or nil
        )
    end
    KnoxPersistence.ensureSurvivorIdentityFromCharacter(
        id,
        character,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
    if not equipmentOk or not saved then
        bridge:removeNpc(id)
        return nil, "initialization_failed equipment=" .. equipped .. " save=" .. tostring(evidence)
    end
    return character,
        "SPAWNED " .. id .. " " .. tostring(appearance)
            .. " equipment=" .. tostring(equipped)
end

local function createDeveloperSurvivor(bridge, id, origin)
    local square = findSpawnSquare(origin)
    return createSurvivorAt(bridge, id, square, true)
end

local function restoreSurvivor(bridge, id, record)
    if not KnoxPersistence.isSurvivorAlive(id) then
        return nil, "dead_identity"
    end
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return nil, "saved_square_not_loaded=" .. tostring(location)
    end
    local result = tostring(bridge:restoreTestNpcRecord(record, square))
    if string.find(result, "RESTORED", 1, true) ~= 1 then
        return nil, result
    end
    return bridge:getNpcCharacter(id), result
end

local function addActiveId(id)
    for _, activeId in ipairs(activeIds) do
        if activeId == id then
            return
        end
    end
    activeIds[#activeIds + 1] = id
end

local function removeActiveId(id)
    local retained = {}
    for _, activeId in ipairs(activeIds) do
        if activeId ~= id then
            retained[#retained + 1] = activeId
        end
    end
    activeIds = retained
end

-- A runtime entry is not proof that a native body still exists. If the bridge
-- confirms an ordinary active shell is gone, retaining its ID here makes the
-- population scan skip it forever. Drop only that stale runtime projection;
-- the canonical record and identity remain untouched for the normal restore
-- path. Transitional detach and hibernation rollback owners keep their lease.
local function releaseMissingActiveBodies(bridge)
    if bridge == nil or bridge.getNpcCharacter == nil then return 0 end
    local missing = {}
    for _, id in ipairs(activeIds) do
        if controllers[id] ~= nil and hibernateRollbackPending[id] == nil then
            local lifecycle = KnoxSurvivorRuntime.getLifecycleState ~= nil
                and KnoxSurvivorRuntime.getLifecycleState(id) or nil
            local transitional = lifecycle == "detached_transient"
                or lifecycle == "detached_grace"
                or lifecycle == "detached_stale"
                or lifecycle == "hibernating"
            if not transitional then
                local ok, character = pcall(bridge.getNpcCharacter, bridge, id)
                if ok and character == nil then missing[#missing + 1] = id end
            end
        end
    end
    for _, id in ipairs(missing) do
        local controller = controllers[id]
        -- Do not shutdown/capture a shell the bridge has already lost. Requeue
        -- its durable base claim so another resident can take the real task.
        local duty = KnoxPersistence.getSurvivorDuty(id)
        if duty ~= nil and duty.mode == "base" and duty.baseId ~= nil
            and KnoxPersistence.requeueBaseTasksForSurvivor ~= nil then
            KnoxPersistence.requeueBaseTasksForSurvivor(
                id, duty.baseId, "native_body_missing")
        end
        pcall(KnoxSurvivorRuntime.unregister, id, controller)
        controllers[id] = nil
        removeActiveId(id)
        print(TAG .. " id=" .. tostring(id)
            .. " state=STALE_RUNTIME_RELEASED evidence=bridge_body_absent"
            .. " canonical_record=preserved")
    end
    return #missing
end

local function registerController(bridge, id, character, result)
    if character == nil then
        return false, "character_unavailable"
    end
    if controllers[id] ~= nil then
        return true, "ALREADY_ACTIVE"
    end
    local capabilities, capabilityResult = KnoxSurvivorCapabilities.ensureForOrigin(
        id,
        character,
        false,
        nil,
        KnoxPersistence.getSurvivorOrigin(id)
    )
    if capabilities == nil then
        bridge:removeNpc(id)
        return false, "capabilities=" .. tostring(capabilityResult)
    end
    KnoxPersistence.ensureSurvivorIdentityFromCharacter(
        id,
        character,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    KnoxUnloadedSurvival.applyToLoaded(id, character)
    controllers[id] = KnoxAutonomyController.new(
        id,
        character,
        bridge,
        reservations,
        ticks
    )
    local camp = KnoxPersistence.getCampForSurvivor ~= nil
        and KnoxPersistence.getCampForSurvivor(id) or nil
    if camp ~= nil and controllers[id].setCampAssignment ~= nil then
        controllers[id]:setCampAssignment(
            camp.id,
            camp,
            KnoxFactionCamps.memberSlot(camp, id)
        )
    end
    local awayTeam = KnoxPersistence.getAwayTeamForSurvivor ~= nil
        and KnoxPersistence.getAwayTeamForSurvivor(id) or nil
    if awayTeam ~= nil and controllers[id].setAwayTeam ~= nil then
        controllers[id]:setAwayTeam(awayTeam.id)
    end
    addActiveId(id)
    KnoxSurvivorRuntime.register(id, controllers[id])
    if KnoxBaseManager ~= nil and KnoxBaseManager.syncStructureProtection ~= nil then
        KnoxBaseManager.syncStructureProtection()
    end
    print(TAG .. " id=" .. id .. " state=ACTIVE " .. tostring(result))
    print(
        TAG .. " id=" .. id
            .. " capabilities=" .. tostring(capabilities.professionId)
            .. " traits=" .. table.concat(capabilities.traitIds or {}, ",")
            .. " source=" .. tostring(capabilityResult)
    )
    return true, result
end

local function ensurePopulation(bridge, player, requiredIds)
    for _, id in ipairs(requiredIds or {}) do
        if controllers[id] == nil then
            local character = bridge:getNpcCharacter(id)
            local result = "ADOPTED_ACTIVE"
            if character == nil then
                local record = KnoxPersistence.getRecord(id)
                if record ~= nil then
                    character, result = restoreSurvivor(bridge, id, record)
                else
                    character, result = createDeveloperSurvivor(
                        bridge,
                        id,
                        player:getCurrentSquare()
                    )
                end
            end
            if character == nil then
                return false, "id=" .. id .. " " .. tostring(result)
            end
            local registered, registerResult = registerController(
                bridge,
                id,
                character,
                result
            )
            if not registered then
                return false, "id=" .. id .. " " .. tostring(registerResult)
            end
        end
    end
    for _, id in ipairs(requiredIds or {}) do
        if bridge:getNpcCharacter(id) == nil then
            return false, "missing=" .. tostring(id)
        end
    end
    return true,
        "active=" .. tostring(bridge:getActiveNpcCount())
            .. " ids=" .. tostring(bridge:getActiveNpcIds())
end

local function activeWorldLookup()
    local world = {}
    for _, id in ipairs(KnoxPersistence.getAllWorldSurvivorIds()) do
        world[id] = true
    end
    return world
end

local function currentPlayers()
    local players = {}
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerIndex = 0, math.max(0, tonumber(count) or 1) - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player ~= nil then
            players[#players + 1] = player
        end
    end
    return players
end

-- Any loaded player, not just player 0, so splitscreen / respawned sessions work.
local function getAnyLoadedPlayer()
    for _, player in ipairs(currentPlayers()) do
        if player ~= nil and player.getCurrentSquare ~= nil then
            local ok, square = pcall(function() return player:getCurrentSquare() end)
            if ok and square ~= nil then return player end
        end
    end
    return nil
end

local function retireDeadSurvivor(bridge, id, controller)
    -- Mark dead first so a later capture cannot overwrite the alive record
    -- with a corpse pose.
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    -- Killer attribution for survivor-vs-survivor / zombie kill forensics:
    -- who (or what) landed the killing blow, resolved once at retirement.
    pcall(function()
        local log = rawget(_G, "KnoxDebugLog")
        local runtime = rawget(_G, "KnoxSurvivorRuntime")
        if log == nil or log.log == nil or controller == nil then return end
        local killer, killerId, killerKind = nil, nil, "unknown"
        local okAttacker, attacker = pcall(function()
            return controller.character ~= nil
                and controller.character:getAttackedBy() or nil
        end)
        if okAttacker and attacker ~= nil then
            killer = attacker
            if runtime ~= nil and runtime.idForCharacter ~= nil then
                local okId, found = pcall(function()
                    return runtime.idForCharacter(attacker)
                end)
                if okId and found ~= nil then killerId = tostring(found) end
            end
            if killerId ~= nil then
                killerKind = "survivor"
            else
                local okZombie = pcall(function()
                    if instanceof ~= nil then
                        return instanceof(attacker, "IsoZombie")
                    end
                    return attacker.isZombie ~= nil and attacker:isZombie()
                end)
                killerKind = okZombie and "zombie" or "other"
            end
        end
        log.log("combat", id, "died", { killerKind = killerKind, killer = killerId })
    end)
    if KnoxPersistence.isSurvivorAlive(id) then
        local evidence = { locationSource = "loaded", corpseState = "native_pending" }
        pcall(function()
            evidence.x, evidence.y, evidence.z = controller.character:getX(),
                controller.character:getY(), controller.character:getZ()
        end)
        if KnoxPersistence.markSurvivorDead(id, now, "world_death", evidence) then
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.survivorDied ~= nil then
                pcall(feed.survivorDied, id, controller.character)
            end
        end
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation ~= nil
        and KnoxPersistence.getSurvivorAffiliation(id) or nil
    local companionService = rawget(_G, "KnoxCompanionService")
    if affiliation ~= nil and affiliation.kind == "player"
        and companionService ~= nil then
        -- The canonical death write above makes this identity ineligible. Let
        -- the existing player-order owner prune it from its runtime snapshot.
        if companionService.removePlayerPartyFormationMember ~= nil then
            companionService.removePlayerPartyFormationMember(affiliation.ownerId, id)
        end
        if companionService.getPartyDestination ~= nil then
            companionService.getPartyDestination(affiliation.ownerId)
        end
    end
    pcall(function()
        controller:shutdown()
    end)
    -- Convert the dead shell through Build 42's own IsoDeadBody constructor before
    -- removing its contained runtime shell. This retains the corpse, clothing and
    -- inventory for normal world cleanup/reanimation instead of deleting the body.
    local removed = bridge.retireNpcAsCorpse ~= nil
        and tostring(bridge:retireNpcAsCorpse(id))
        or "CORPSE_FAILED bridge_unavailable"
    local registryStillActive = bridge:getNpcCharacter(id) ~= nil
    if string.find(removed, "CORPSE_CREATED", 1, true) == 1
        or removed == "NONE_ACTIVE" or not registryStillActive then
        if string.find(removed, "CORPSE_CREATED", 1, true) == 1
            and KnoxPersistence.markSurvivorCorpseCreated ~= nil then
            KnoxPersistence.markSurvivorCorpseCreated(id)
        end
        KnoxSurvivorRuntime.unregister(id, controller)
        controllers[id] = nil
        removeActiveId(id)
        print(TAG .. " id=" .. tostring(id)
            .. " state=DEAD persisted=true remove=" .. tostring(removed))
        return
    end
    -- Do not silently forget a failed engine teardown. Keeping the stopped runtime
    -- registered makes the next lifecycle pass retry removal against the same shell
    -- rather than spawning a duplicate identity elsewhere.
    controller.state = "STOPPED"
    print(TAG .. " id=" .. tostring(id)
        .. " state=DEAD_REMOVE_PENDING result=" .. tostring(removed))
end

local function retireDeadControllers(bridge)
    local dead = {}
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        if controller ~= nil and controller.character ~= nil then
            local success, isDead = pcall(function()
                return controller.character:isDead()
            end)
            if success and isDead then
                dead[#dead + 1] = { id = id, controller = controller }
            end
        end
    end
    -- Also catch bridge orphans with no controller (hibernate remove-failed +
    -- register overwrite) so stale bodies cannot stay alive forever.
    local okIds, rawIds = pcall(function() return bridge:getActiveNpcIds() end)
    if okIds and rawIds ~= nil and tostring(rawIds) ~= "" then
        for id in string.gmatch(tostring(rawIds), "[^,]+") do
            if controllers[id] == nil then
                local okCh, ch = pcall(function() return bridge:getNpcCharacter(id) end)
                if okCh and ch ~= nil then
                    local okDead, isDead = pcall(function() return ch:isDead() end)
                    if okDead and isDead then
                        local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                        KnoxPersistence.markSurvivorDead(id, now, "orphan_death")
                        pcall(function() bridge:retireNpcAsCorpse(id) end)
                    end
                end
            end
        end
    end
    for _, entry in ipairs(dead) do
        retireDeadSurvivor(bridge, entry.id, entry.controller)
    end
end

-- Event departure is a two-phase lifecycle boundary. Persistence first blocks
-- reactivation; this runtime owner then captures and removes any live shell.
-- Only a successful teardown finalizes the survivor as having left the county.
local function retirePendingEventDepartures(bridge)
    for _, id in ipairs(KnoxPersistence.getPendingEventDepartureIds()) do
        if ticks >= (departureRetryAt[id] or 0) then
            -- A native teardown failure owns a bounded retry window. The controller
            -- stays stopped and cannot resume ordinary autonomy between attempts.
            local departure = KnoxPersistence.getSurvivorDeparture(id)
            local controller = controllers[id]
            local character = controller ~= nil and controller.character
                or bridge:getNpcCharacter(id)
            local dead = false
            if character ~= nil then
                local ok, value = pcall(function() return character:isDead() end)
                dead = ok and value == true
            end
            if dead and controller ~= nil then
                departureRetryAt[id], departureFailures[id] = nil, nil
                retireDeadSurvivor(bridge, id, controller)
            elseif controller ~= nil then
                controller.state = "STOPPED"
                local success, saved, evidence = pcall(function()
                    return controller:shutdown()
                end)
                if success and saved then
                    local removed = tostring(bridge:removeNpc(id))
                    local registryStillActive = bridge:getNpcCharacter(id) ~= nil
                    if string.find(removed, "REMOVED", 1, true) == 1
                        or removed == "NONE_ACTIVE" or not registryStillActive then
                        KnoxSurvivorRuntime.unregister(id, controller)
                        controllers[id] = nil
                        removeActiveId(id)
                        departureRetryAt[id], departureFailures[id] = nil, nil
                        local finalized, result = KnoxPersistence.finalizeEventDeparture(
                            id,
                            departure.eventId,
                            getGameTime():getWorldAgeHours()
                        )
                        print(TAG .. " id=" .. tostring(id)
                            .. " state=DEPARTED finalized=" .. tostring(finalized)
                            .. " save=" .. tostring(evidence)
                            .. " remove=" .. tostring(removed)
                            .. " result=" .. tostring(result))
                    else
                        local failures = math.min(5, (departureFailures[id] or 0) + 1)
                        departureFailures[id] = failures
                        departureRetryAt[id] = ticks + math.min(300, 30 * 2 ^ (failures - 1))
                        print(TAG .. " id=" .. tostring(id)
                            .. " departure-remove-failed result=" .. tostring(removed)
                            .. " retryAt=" .. tostring(departureRetryAt[id]))
                    end
                else
                    local failures = math.min(5, (departureFailures[id] or 0) + 1)
                    departureFailures[id] = failures
                    departureRetryAt[id] = ticks + math.min(300, 30 * 2 ^ (failures - 1))
                    print(TAG .. " id=" .. tostring(id)
                        .. " departure-save-failed evidence=" .. tostring(evidence)
                        .. " retryAt=" .. tostring(departureRetryAt[id]))
                end
            elseif bridge:getNpcCharacter(id) == nil then
                -- A pending departure restored after a process restart has no live
                -- engine shell to retire. Finalize the durable state directly.
                KnoxPersistence.finalizeEventDeparture(
                    id,
                    departure.eventId,
                    getGameTime():getWorldAgeHours()
                )
                departureRetryAt[id], departureFailures[id] = nil, nil
            else
                local failures = math.min(5, (departureFailures[id] or 0) + 1)
                departureFailures[id] = failures
                departureRetryAt[id] = ticks + math.min(300, 30 * 2 ^ (failures - 1))
                print(TAG .. " id=" .. tostring(id)
                    .. " departure-orphaned-shell retryAt=" .. tostring(departureRetryAt[id]))
            end
        end
    end
end

local function squareDescription(square)
    if square == nil then
        return "none"
    end
    return tostring(square:getX()) .. "," .. tostring(square:getY())
        .. "," .. tostring(square:getZ())
end

local function finiteNearestPlayerDistanceSquared(character, players)
    if character == nil or players == nil or #players == 0 then
        return nil
    end
    local okX, cx = pcall(function()
        return character:getX()
    end)
    local okY, cy = pcall(function()
        return character:getY()
    end)
    local okZ, cz = pcall(function()
        return character:getZ()
    end)
    if not okX or not okY or not okZ or type(cx) ~= "number" or type(cy) ~= "number" or type(cz) ~= "number" then
        return nil
    end
    if cx ~= cx or cy ~= cy or cz ~= cz or math.abs(cx) == math.huge or math.abs(cy) == math.huge or math.abs(cz) == math.huge then
        return nil
    end
    local best = nil
    for _, player in ipairs(players) do
        local okPX, px = pcall(function()
            return player:getX()
        end)
        local okPY, py = pcall(function()
            return player:getY()
        end)
        if okPX and okPY and type(px) == "number" and type(py) == "number" and px == px and py == py and math.abs(px) ~= math.huge and math.abs(py) ~= math.huge then
            local dx = cx - px
            local dy = cy - py
            local d2 = dx * dx + dy * dy
            if best == nil or d2 < best then
                best = d2
            end
        end
    end
    return best
end

local function actorXYZDescription(character)
    if character == nil then
        return "none"
    end
    local okX, x = pcall(function()
        return character:getX()
    end)
    local okY, y = pcall(function()
        return character:getY()
    end)
    local okZ, z = pcall(function()
        return character:getZ()
    end)
    if not okX or not okY or not okZ then
        return "none"
    end
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function recognizedDetachedTransient(character)
    if character == nil then return false end
    local ok, state = pcall(function()
        return character.getCurrentStateName ~= nil and character:getCurrentStateName() or nil
    end)
    if not ok or type(state) ~= "string" then return false end
    state = string.lower(state)
    return string.find(state, "climb", 1, true) ~= nil
        or string.find(state, "vault", 1, true) ~= nil
        or string.find(state, "window", 1, true) ~= nil
        or string.find(state, "fence", 1, true) ~= nil
        or string.find(state, "sheetrope", 1, true) ~= nil
end

local function prepareUnloadedResourceHandoff(id, controller, reason)
    local callOk, prepared, evidence = pcall(function()
        return KnoxUnloadedSurvival.prepareBaseResidentForStorage(
            id,
            controller ~= nil and controller.character or nil,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
    end)
    if not callOk then
        print(TAG .. " id=" .. tostring(id)
            .. " unloaded-provision-error reason=" .. tostring(reason)
            .. " error=" .. tostring(prepared))
        return false, tostring(prepared)
    end
    if prepared then
        print(TAG .. " id=" .. tostring(id)
            .. " unloaded-provision reason=" .. tostring(reason)
            .. " " .. tostring(evidence))
    end
    return prepared == true, evidence
end

local function hibernateDistantWorldSurvivors(bridge, players)
    local world = activeWorldLookup()
    local hibernate = {}
    -- A committed stored snapshot plus a body still owned by the bridge is an
    -- incomplete native teardown, not an offscreen survivor. Retry only the
    -- ledger rollback; never repeat shutdown/remove against a contradictory
    -- live shell, and never create a replacement body.
    for id, pending in pairs(hibernateRollbackPending) do
        local controller = pending.controller
        local okCharacter, liveCharacter = pcall(function()
            return bridge:getNpcCharacter(id)
        end)
        if okCharacter and liveCharacter == nil then
            if controllers[id] == controller then
                KnoxSurvivorRuntime.unregister(id, controller)
                controllers[id] = nil
                removeActiveId(id)
            end
            hibernateRollbackPending[id] = nil
            print(TAG .. " id=" .. tostring(id)
                .. " hibernate-remove-retry=body_absent state=HIBERNATED")
        elseif okCharacter and controller ~= nil
            and liveCharacter == controller.character then
            local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
            local rollbackCallOk, rolledBack, rollbackEvidence = pcall(function()
                return KnoxUnloadedSurvival.rollbackStored(id, now)
            end)
            if rollbackCallOk and rolledBack == true
                and controllers[id] == controller
                and controller.resumeAfterHibernateRollback ~= nil then
                local resumeCallOk, resumed, resumeEvidence = pcall(function()
                    return controller:resumeAfterHibernateRollback(
                        ticks, pending.reason
                    )
                end)
                if resumeCallOk and resumed == true then
                    KnoxSurvivorRuntime.setLifecycleState(id,
                        pending.reason == "detached" and "detached_stale" or "active")
                    hibernateRollbackPending[id] = nil
                    print(TAG .. " id=" .. tostring(id)
                        .. " hibernate-remove-retry=ledger_rollback result=loaded"
                        .. " controller=IDLE reason=" .. tostring(pending.reason))
                else
                    print(TAG .. " id=" .. tostring(id)
                        .. " hibernate-recovery-resume-failed=" .. tostring(resumeEvidence))
                end
            else
                print(TAG .. " id=" .. tostring(id)
                    .. " hibernate-recovery-rollback-pending="
                    .. tostring(rollbackCallOk and rollbackEvidence or rolledBack))
            end
        else
            print(TAG .. " id=" .. tostring(id)
                .. " hibernate-recovery-pending=body_identity_unconfirmed")
        end
    end
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        if controller ~= nil and hibernateRollbackPending[id] == nil then
            local character = controller.character
            -- Passenger shells are owned by the live vehicle. Treating their
            -- transient world square as a detached body would capture/remove a
            -- companion while the player is driving it, losing the native seat
            -- relationship. They remain live until a real vehicle lifecycle is
            -- implemented.
            if character ~= nil and character:getVehicle() ~= nil then
                detachedGrace[id] = nil
                KnoxSurvivorRuntime.setLifecycleState(id, "active")
            else
            local square = character ~= nil and character:getCurrentSquare() or nil
            local distanceSquared = KnoxWorldPopulation.nearestPlayerDistanceSquared(square, players)
            local finiteDistanceSquared = finiteNearestPlayerDistanceSquared(character, players)
            local finiteDistance = finiteDistanceSquared and math.sqrt(finiteDistanceSquared) or nil
            local squareDistance = distanceSquared and math.sqrt(distanceSquared) or nil
            if square == nil then
                -- Nil shell with no bridge character is already gone: drop
                -- immediately instead of spinning hibernate-save-failed forever.
                local live = nil
                pcall(function() live = bridge:getNpcCharacter(id) end)
                if controller.character == nil and live == nil then
                    KnoxSurvivorRuntime.unregister(id, controller)
                    controllers[id] = nil
                    removeActiveId(id)
                    detachedGrace[id] = nil
                else
                local grace = (detachedGrace[id] or 0) + 1
                detachedGrace[id] = grace
                local companion = type(duty) == "table"
                    and tostring(duty.mode or "") == "companion"
                local transient = companion and recognizedDetachedTransient(character)
                local shouldHibernate, decision
                if companion then
                    shouldHibernate, decision =
                        KnoxSurvivorLifecyclePolicy.companionDetachedDecision(
                            transient,
                            finiteDistanceSquared,
                            hibernationDistanceSquared(),
                            grace,
                            DETACHED_COMPANION_GRACE_CHECKS
                        )
                else
                    shouldHibernate, decision =
                        KnoxSurvivorLifecyclePolicy.detachedDecision(
                            finiteDistanceSquared,
                            hibernationDistanceSquared(),
                            grace,
                            DETACHED_GRACE_CHECKS
                        )
                end
                KnoxSurvivorRuntime.setLifecycleState(id,
                    shouldHibernate and "detached_stale"
                        or transient and "detached_transient" or "detached_grace")
                print(TAG .. " detach-detected id=" .. tostring(id) .. " actorXYZ=" .. actorXYZDescription(character) .. " currentSquare=" .. squareDescription(square) .. " finiteDistance=" .. tostring(finiteDistance) .. " squareDistance=" .. tostring(squareDistance) .. " detachedTicks=" .. tostring(grace) .. " decision=" .. tostring(decision))
                if shouldHibernate then
                    detachedGrace[id] = nil
                    hibernate[#hibernate + 1] = {
                        id = id,
                        controller = controller,
                        reason = "detached",
                        square = nil,
                        distanceSquared = finiteDistanceSquared,
                        detachedGrace = grace,
                    }
                end
                end
            else
                if detachedGrace[id] ~= nil then
                    print(TAG .. " detach-recovered id=" .. tostring(id) .. " actorXYZ=" .. actorXYZDescription(character) .. " square=" .. squareDescription(square) .. " finiteDistance=" .. tostring(finiteDistance))
                end
                detachedGrace[id] = nil
                KnoxSurvivorRuntime.setLifecycleState(id, "active")
                -- Ordinary distance hibernation belongs only to production world
                -- survivors. A missing square is different: any shell, including a
                -- companion or developer scenario body, must leave DETACHED through
                -- the transactional capture/remove path instead of remaining an
                -- active engine object forever.
                if KnoxSurvivorLifecyclePolicy.distanceEligible(
                    world[id] == true,
                    duty.mode,
                    distanceSquared,
                    hibernationDistanceSquared()
                ) then
                    hibernate[#hibernate + 1] = {
                        id = id,
                        controller = controller,
                        reason = "distance",
                        square = square,
                        distanceSquared = distanceSquared,
                    }
                end
            end
            end
        end
    end
    for _, entry in ipairs(hibernate) do
        local distance = entry.distanceSquared ~= nil and math.sqrt(entry.distanceSquared) or nil
        print(TAG .. " id=" .. entry.id .. " hibernate-attempt reason=" .. tostring(entry.reason) .. " square=" .. squareDescription(entry.square) .. " playerDistance=" .. tostring(distance) .. " threshold=" .. tostring(hibernationDistance()))
        -- While this resident and its assigned containers are still real loaded
        -- objects, move a bounded reserve from base storage into carried stock.
        -- shutdown() then serializes those exact items for unloaded survival.
        KnoxSurvivorRuntime.setLifecycleState(entry.id, "hibernating")
        prepareUnloadedResourceHandoff(entry.id, entry.controller, "hibernate")
        -- shutdown() captures first. removeNpc() is intentionally not called unless
        -- persistence succeeds, so normal hibernation remains transactional.
        local success, saved, evidence = pcall(function()
            return entry.controller:shutdown()
        end)
        if success and saved then
            -- Commit stored ownership before removing the only native body.
            -- A failed ledger write must leave the captured shell registered so
            -- it can be retried, rather than producing an identity owned by
            -- neither the live runtime nor unloaded simulation.
            local marked, markResult = KnoxUnloadedSurvival.markStored(
                entry.id,
                getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
            )
            if not marked then
                KnoxSurvivorRuntime.setLifecycleState(entry.id, "active")
                print(TAG .. " id=" .. entry.id
                    .. " hibernate-store-failed reason=" .. tostring(entry.reason)
                    .. " result=" .. tostring(markResult))
            else
                local removed = tostring(bridge:removeNpc(entry.id))
                local liveCharacter = bridge:getNpcCharacter(entry.id)
                local registryStillActive = liveCharacter ~= nil
                if not registryStillActive then
                    KnoxSurvivorRuntime.unregister(entry.id, entry.controller)
                    controllers[entry.id] = nil
                    removeActiveId(entry.id)
                    if entry.reason == "detached" then recentlyDetached[entry.id] = ticks end
                    print(TAG .. " id=" .. entry.id
                        .. " state=HIBERNATED reason=" .. tostring(entry.reason)
                        .. " playerDistance=" .. tostring(distance)
                        .. " saved=true"
                        .. " remove=" .. tostring(removed))
                else
                    -- The bridge still owns this exact shell. Restore loaded
                    -- ledger ownership first; only then let its existing
                    -- controller arbitrate again. If persistence refuses, hold
                    -- the pair here and retry rollback alone on a later pass.
                    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                    local rollbackCallOk, rolledBack, rollbackEvidence = pcall(function()
                        return KnoxUnloadedSurvival.rollbackStored(entry.id, now)
                    end)
                    local resumed, resumeEvidence = false, "rollback_not_committed"
                    if rollbackCallOk and rolledBack == true
                        and liveCharacter == entry.controller.character then
                        local resumeCallOk, resumeResult, resumeDetail = pcall(function()
                            return entry.controller:resumeAfterHibernateRollback(
                                ticks, entry.reason
                            )
                        end)
                        resumed = resumeCallOk and resumeResult == true
                        resumeEvidence = resumeCallOk and resumeDetail or resumeResult
                    end
                    if resumed then
                        KnoxSurvivorRuntime.setLifecycleState(entry.id,
                            entry.reason == "detached" and "detached_stale" or "active")
                    else
                        hibernateRollbackPending[entry.id] = {
                            controller = entry.controller,
                            reason = entry.reason,
                        }
                        KnoxSurvivorRuntime.setLifecycleState(entry.id,
                            "hibernate_recovery_pending")
                    end
                    print(TAG .. " id=" .. entry.id
                        .. " hibernate-remove-failed reason=" .. tostring(entry.reason)
                        .. " result=" .. removed
                        .. " rollback=" .. tostring(rollbackCallOk and rollbackEvidence or rolledBack)
                        .. " resumed=" .. tostring(resumed)
                        .. " resumeEvidence=" .. tostring(resumeEvidence))
                end
            end
        else
            KnoxSurvivorRuntime.setLifecycleState(entry.id,
                entry.reason == "detached" and "detached_stale" or "active")
            print(TAG .. " id=" .. entry.id
                .. " hibernate-save-failed reason=" .. tostring(entry.reason)
                .. " square=" .. squareDescription(entry.square)
                .. " playerDistance=" .. tostring(distance)
                .. " evidence=" .. tostring(evidence))
        end
    end
end

local function activateWorldCandidate(bridge, candidate)
    local character = bridge:getNpcCharacter(candidate.id)
    local result = "ADOPTED_ACTIVE"
    if character == nil and candidate.mode == "restore" then
        if candidate.awayMission == true and candidate.square ~= nil then
            result = tostring(bridge:restoreTestNpcRecord(
                candidate.record,
                candidate.square
            ))
            if string.find(result, "RESTORED", 1, true) == 1 then
                character = bridge:getNpcCharacter(candidate.id)
            end
        else
            character, result = restoreSurvivor(
                bridge,
                candidate.id,
                candidate.record
            )
        end
    elseif character == nil and candidate.mode == "spawn" then
        character, result = createSurvivorAt(
            bridge,
            candidate.id,
            candidate.square,
            false
        )
    end
    if character == nil then
        return false, result
    end
    local registered, registerResult = registerController(bridge, candidate.id, character, result)
    if registered and candidate.blockedDispatchRecovery == true then
        local recovered, recoveryResult = KnoxPersistence.recoverBlockedAwayTeamMember(
            candidate.blockedAwayTeamId,
            candidate.id,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
        if not recovered then
            print(TAG .. " id=" .. tostring(candidate.id)
                .. " blocked-dispatch-recovery-failed result=" .. tostring(recoveryResult))
            return false, "blocked_dispatch_recovery_failed=" .. tostring(recoveryResult)
        end
        local controller = controllers[candidate.id]
        if controller ~= nil and controller.setAwayTeam ~= nil then
            controller:setAwayTeam(nil)
        end
        print(TAG .. " id=" .. tostring(candidate.id)
            .. " state=BLOCKED_DISPATCH_RECOVERED team="
            .. tostring(candidate.blockedAwayTeamId))
    end
    return registered, registerResult
end

local function reconcileWorldPopulation(bridge)
    releaseMissingActiveBodies(bridge)
    local players = currentPlayers()
    for _, player in ipairs(players) do
        if KnoxSpouseStart.update(player, function(id, square, record)
            return activateWorldCandidate(bridge, { id = id, square = square, record = record,
                mode = record ~= nil and "restore" or "spawn" })
        end) then
            KnoxActivityFeed.event("Your spouse is here. They will follow you; use Orders to guide them.")
        end
    end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local awayChanged = KnoxPersistence.advanceAwayTeams ~= nil
        and KnoxPersistence.advanceAwayTeams(now) or 0
    local advanced, notable = KnoxUnloadedSurvival.advanceAll(activeIds, now)
    local summary = KnoxWorldPopulation.maintain(now, { players = players })
    KnoxFactionCamps.reconcile(controllers, activeIds, now)
    local remaining = KnoxSettings.activationBudget(#activeIds)
    local candidates, rejected = KnoxWorldPopulation.activationCandidates(
        bridge,
        activeIds,
        remaining,
        { players = players, maximumDistance = activationDistance(),
            acceptCandidate = function(candidate)
                return KnoxSurvivorLifecyclePolicy.restoreAfterDetach(
                    recentlyDetached[candidate.id], ticks, candidate.distanceSquared)
            end }
    )
    -- Away missions are normally excluded from proximity activation. Once a
    -- destination or return point is inside the loaded player band, add those
    -- members through this same population budget so their persisted mission
    -- controller can perform real world work. This is an explicit exception,
    -- not a second activation scheduler.
    local activeLookup = {}
    for _, activeId in ipairs(activeIds) do activeLookup[activeId] = true end
    local missionSeen = {}
    for _, candidate in ipairs(candidates) do missionSeen[candidate.id] = true end
    if #candidates < remaining and KnoxPersistence.getAwayTeams ~= nil then
        for _, team in ipairs(KnoxPersistence.getAwayTeams() or {}) do
            local state = type(team) == "table" and team.state or nil
            if state == "awaiting_collection" or state == "collecting"
                or state == "returning" or state == "blocked" then
                for _, memberId in ipairs(team.memberIds or {}) do
                    if #candidates >= remaining then break end
                    if not activeLookup[memberId] and not missionSeen[memberId] then
                        local candidate = KnoxWorldPopulation.activationCandidate(
                            memberId,
                            bridge,
                            {
                                players = players,
                                maximumDistance = activationDistance(),
                                allowAwayMission = true,
                                allowBlockedDispatchRecovery = true,
                            }
                        )
                        if candidate ~= nil then
                            candidates[#candidates + 1] = candidate
                            missionSeen[memberId] = true
                        end
                    end
                end
            end
            if #candidates >= remaining then break end
        end
    end
    table.sort(candidates, function(first, second)
        local firstPriority = tonumber(first.activationPriority) or 4
        local secondPriority = tonumber(second.activationPriority) or 4
        if firstPriority ~= secondPriority then return firstPriority < secondPriority end
        local firstDistance = tonumber(first.distanceSquared) or math.huge
        local secondDistance = tonumber(second.distanceSquared) or math.huge
        if firstDistance ~= secondDistance then return firstDistance < secondDistance end
        return tostring(first.id) < tostring(second.id)
    end)
    local activated = 0
    for _, candidate in ipairs(candidates) do
        if activated >= remaining then break end
        local ready, evidence = false, "streaming_edge_cooldown"
        if KnoxSurvivorLifecyclePolicy.restoreAfterDetach(
            recentlyDetached[candidate.id], ticks, candidate.distanceSquared) then
            ready, evidence = activateWorldCandidate(bridge, candidate)
        end
        if ready then
            recentlyDetached[candidate.id] = nil
            activated = activated + 1
            local distance = candidate.distanceSquared ~= nil
                and math.sqrt(candidate.distanceSquared)
                or nil
            print(TAG .. " population-activated id=" .. tostring(candidate.id)
                .. " mode=" .. tostring(candidate.mode)
                .. " square=" .. tostring(candidate.x) .. ","
                    .. tostring(candidate.y) .. "," .. tostring(candidate.z)
                .. " playerDistance=" .. tostring(distance))
        else
            print(TAG .. " population-activation-failed id=" .. tostring(candidate.id)
                .. " mode=" .. tostring(candidate.mode)
                .. " evidence=" .. tostring(evidence))
        end
    end
    local statusKey = tostring(summary.status)
        .. ":" .. tostring(summary.living)
        .. ":" .. tostring(#activeIds)
    if populationStatus ~= statusKey or activated > 0 or #(summary.addedIds or {}) > 0 then
        populationStatus = statusKey
        print(TAG .. " population status=" .. tostring(summary.status)
            .. " living=" .. tostring(summary.living)
            .. "/" .. tostring(summary.target)
            .. " capsDisabled=" .. tostring(summary.capsDisabled == true)
            .. " active=" .. tostring(#activeIds)
            .. " activated=" .. tostring(activated)
            .. " waitingSquares=" .. tostring(rejected.saved_square_not_loaded or 0)
            .. " waitingOrigins=" .. tostring(rejected.no_safe_hidden_loaded_square or 0)
            .. " waitingVirtual=" .. tostring(rejected.virtual_square_not_loaded_or_visible or 0)
            .. " outsideBand=" .. tostring(rejected.outside_activation_distance or 0)
            .. " inactiveAdvanced=" .. tostring(advanced))
    end
    if notable > 0 then
        print(TAG .. " unloaded-simulation advanced=" .. tostring(advanced)
            .. " notable=" .. tostring(notable))
    end
    if awayChanged > 0 then
        print(TAG .. " away-teams advanced=" .. tostring(awayChanged))
    end
end

local function completedDecisions(controller)
    return controller.counts.roam
        + controller.counts.loot
        + controller.counts.search
        + controller.counts.needs
        + controller.counts.combat
end

local function reportPassIfReady(bridge)
    if passReported or #scenarioIds == 0 then
        return
    end
    for _, id in ipairs(scenarioIds) do
        if controllers[id] == nil or completedDecisions(controllers[id]) < DECISIONS_REQUIRED then
            return
        end
    end
    local saved, evidence = KnoxPersistence.captureAllActiveSurvivors()
    if not saved then
        print(TAG .. " RESULT status=FAIL reason=capture_all_failed evidence=" .. tostring(evidence))
        return
    end
    KnoxPersistence.markDevGateComplete(GATE_KEY)
    passReported = true
    print(
        TAG
            .. " RESULT scenario=survival status=PASS"
            .. " reason=developer_autonomy_controllers"
            .. " evidence=active=" .. tostring(bridge:getActiveNpcCount())
            .. " decisions=" .. tostring(scenarioIds[1] ~= nil and completedDecisions(controllers[scenarioIds[1]]) or 0)
            .. " saved=" .. tostring(evidence)
    )
end

local function configureScenario(player, scenario, ids)
    if scenario == "single" then
        return true, "independent"
    end
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if scenario == "companion" then
        local playerId = KnoxPersistence.ensurePlayerId(player)
        return KnoxPersistence.setPlayerCompanion(ids[1], playerId, "follow", hours)
    end
    if scenario == "group" or scenario == "faction" or scenario == "faction_base" then
        local group = KnoxPersistence.getTravelGroupFor(ids[1])
        if group ~= nil then
            for _, id in ipairs(ids) do
                local membership = KnoxPersistence.getTravelGroupFor(id)
                if membership == nil or membership.id ~= group.id then
                    group = nil
                    break
                end
            end
        end
        group = group or KnoxPersistence.createTravelGroup(ids, hours)
        if group == nil then
            return false, "group_creation_failed"
        end
        if scenario == "faction" or scenario == "faction_base" then
            local minimumMembers = KnoxSettings.npcFactionMinimumMembers ~= nil
                and KnoxSettings.npcFactionMinimumMembers() or 3
            local faction = group.factionId ~= nil
                and KnoxPersistence.getFaction(group.factionId)
                or KnoxPersistence.promoteTravelGroupToFaction(
                    group.id,
                    hours,
                    minimumMembers
                )
            if faction == nil then
                return false, "faction_creation_failed"
            end
            return true, faction.id
        end
        return true, group.id
    end
    return false, "unknown_scenario"
end

update = function()
    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getAnyLoadedPlayer()
    if bridge == nil then
        if not bridgeMissingReported or ticks % STATUS_INTERVAL_TICKS == 0 then
            print(TAG .. " BLOCKED bridge_unavailable; configure the Steam launch option or use the Knox Survivors launcher")
            bridgeMissingReported = true
        end
        return
    end
    bridgeMissingReported = false
    if player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end
    if not populationReady then
        local ready, evidence = ensurePopulation(bridge, player, scenarioIds)
        if not ready then
            if ticks % STATUS_INTERVAL_TICKS == 0 then
                print(TAG .. " waiting=" .. tostring(evidence))
            end
            return
        end
        populationReady = true
        print(TAG .. " state=RUNNING " .. tostring(evidence))
    end
    retireDeadControllers(bridge)
    retirePendingEventDepartures(bridge)
    if ticks >= nextHibernationUpdate then
        nextHibernationUpdate = ticks + HIBERNATION_INTERVAL_TICKS
        hibernateDistantWorldSurvivors(bridge, currentPlayers())
    end
    if ticks >= nextPopulationUpdate then
        nextPopulationUpdate = ticks + POPULATION_INTERVAL_TICKS
        local hours = getGameTime():getWorldAgeHours()
        KnoxEvents.maintain(hours)
        if KnoxSettings.enableKnoxEvents ~= nil and KnoxSettings.enableKnoxEvents() then
            KnoxEvents.scheduleAutomaticRaid(hours, KnoxSettings.allowFactionRaids(),
                KnoxSettings.factionRaidMinimumDays(), KnoxSettings.factionRaidIntervalDays())
            KnoxEvents.scheduleAutomaticEntry(hours, true, 1, 3)
        end
        reconcileWorldPopulation(bridge)
        reconcileSettlementDefinitions()
    end
    KnoxZombieAwareness.update(controllers, activeIds, ticks)
    if KnoxCompanionVehicles ~= nil and KnoxCompanionVehicles.tick ~= nil then
        local drivingOk, drivingError = pcall(KnoxCompanionVehicles.tick, ticks)
        if not drivingOk then
            print(TAG .. " vehicle-driver-tick-failed=" .. tostring(drivingError))
        end
    end
    KnoxSurvivorNameplates.update(ticks)
    if not scenarioConfigured and #scenarioIds > 0 then
        local configured, evidence = configureScenario(player, currentScenario, scenarioIds)
        scenarioConfigured = configured == true
        print(TAG .. " scenario-configured=" .. tostring(configured)
            .. " type=" .. tostring(currentScenario) .. " evidence=" .. tostring(evidence))
        if not configured then
            return
        end
    end
    KnoxSurvivorRelationships.coordinate(controllers, activeIds, ticks)
    if KnoxGroupScavenge ~= nil and KnoxGroupScavenge.coordinate ~= nil then
        local scavengeOk, scavengeError = pcall(
            KnoxGroupScavenge.coordinate, controllers, activeIds, ticks
        )
        if not scavengeOk then
            print(TAG .. " group-scavenge-tick-failed=" .. tostring(scavengeError))
        end
    end
    if ticks % 30 == 0 and KnoxSettings.enableKnoxEvents ~= nil
        and KnoxSettings.enableKnoxEvents() then
        KnoxEventRuntime.update(controllers, getGameTime():getWorldAgeHours())
        retirePendingEventDepartures(bridge)
    end
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        if controller == nil then
            KnoxSurvivorRuntime.unregister(id, nil)
            removeActiveId(id)
        else
            KnoxCompanionService.syncController(id, controller)
            if controller.state ~= "STOPPED" then
            local success, failure = pcall(function()
                controller:tick(ticks)
            end)
            if not success then
                local recoveryCallOk, recovered, recoveryEvidence = pcall(function()
                    return controller:recoverFromControllerError(
                        ticks,
                        "controller_error=" .. tostring(failure)
                    )
                end)
                if not recoveryCallOk then
                    -- The recovery method is internally isolated, but retain a
                    -- minimal boundary in case the controller itself is malformed.
                    controller.state = "IDLE"
                    controller.activeDecision = nil
                    controller.nextThink = ticks + STATUS_INTERVAL_TICKS
                    recoveryEvidence = recovered
                    recovered = false
                end
                print(TAG .. " id=" .. id .. " ERROR controller_tick=" .. tostring(failure)
                    .. " recovered=" .. tostring(recoveryCallOk and recovered == true)
                    .. " retryAt=" .. tostring(controller.nextThink)
                    .. ((recoveryCallOk and recovered == true) and ""
                        or " recoveryError=" .. tostring(recoveryEvidence)))
            end
            end
        end
    end
    reportPassIfReady(bridge)
    reportFactionBasePassIfReady()
    if ticks % RELATIONSHIP_INTERVAL_TICKS == 0 then
        KnoxSurvivorRelationships.observe(controllers, activeIds, ticks)
    end
    if ticks % STATUS_INTERVAL_TICKS == 0 and KnoxSettings.showDeveloperDiagnostics() then
        print(TAG .. " render " .. tostring(bridge:getRenderDiagnostics()))
        for _, id in ipairs(activeIds) do
            print(TAG .. " status " .. controllers[id]:status())
        end
    end
end

local function onGameStart()
    if not KnoxSettings.enabled() then
        return
    end
    ticks = 0
    recentlyDetached = {}
    detachedGrace = {}
    controllers = {}
    KnoxSurvivorRuntime.clear()
    hibernateRollbackPending = {}
    reservations = {
        threats = {}, items = {}, containers = {}, restSpots = {}, campPositions = {},
        supportRecipients = {}, supportItems = {}, ambientSpots = {},
        playerFormationTargets = {}, partyDestinationTargets = {},
    }
    KnoxSurvivorRelationships.resetRuntime()
    if KnoxSurvivorDialogue ~= nil and KnoxSurvivorDialogue.resetRuntime ~= nil then
        KnoxSurvivorDialogue.resetRuntime()
    end
    populationReady = false
    passReported = false
    factionBasePassReported = false
    activeIds = {}
    departureRetryAt = {}
    departureFailures = {}
    scenarioIds = {}
    nextPopulationUpdate = 1
    nextHibernationUpdate = 1
    populationStatus = nil
    bridgeMissingReported = false
    local scenario = KnoxSettings.developerToolsEnabled()
        and KnoxSettings.developerScenario()
        or "none"
    currentScenario = scenario
    scenarioConfigured = scenario == "none"
    local factionMinimum = KnoxSettings.npcFactionMinimumMembers ~= nil
        and KnoxSettings.npcFactionMinimumMembers() or 3
    local counts = {
        single = 1,
        companion = 1,
        group = 2,
        faction = factionMinimum,
        faction_base = factionMinimum,
    }
    for index = 1, (counts[scenario] or 0) do
        scenarioIds[#scenarioIds + 1] = "ks-dev-auto-" .. scenario .. "-" .. tostring(index)
    end
    populationReady = #scenarioIds == 0
    stop()
    Events.OnTick.Add(update)
    print(TAG .. " START scenario=" .. scenario
        .. " developerSurvivors=" .. tostring(#scenarioIds)
        .. " worldTarget=" .. tostring(KnoxSettings.worldPopulation()))
end

local function onMainMenuEnter()
    -- A quit can occur between the native death flag and the next normal autonomy
    -- tick. Retire those shells first so capture only serializes living survivors.
    KnoxSurvivorNameplates.clear()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil then
        retireDeadControllers(bridge)
    end
    for id, controller in pairs(controllers) do
        local pending = hibernateRollbackPending[id]
        if pending ~= nil then
            local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
            local ok, rolledBack, evidence = pcall(function()
                return KnoxUnloadedSurvival.rollbackStored(id, now)
            end)
            print(TAG .. " id=" .. tostring(id)
                .. " hibernate-rollback-save-boundary="
                .. tostring(ok and rolledBack == true)
                .. " evidence=" .. tostring(ok and evidence or rolledBack))
        end
        controller:shutdown()
        KnoxSurvivorRuntime.unregister(id, controller)
    end
    KnoxPersistence.captureAllActiveSurvivors()
    KnoxSurvivorRuntime.clear()
    controllers = {}
    activeIds = {}
    hibernateRollbackPending = {}
    detachedGrace = {}
    recentlyDetached = {}
    stop()
end

local function findBaseRespawnSquare(base)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then return nil end
    local home = base.home
    local territory = base.territory or home
    local function scanArea(area)
        if area == nil then return nil end
        local minX = tonumber(area.minX) or 0
        local minY = tonumber(area.minY) or 0
        local maxX = tonumber(area.maxX) or (minX + (tonumber(area.width) or 1) - 1)
        local maxY = tonumber(area.maxY) or (minY + (tonumber(area.height) or 1) - 1)
        local z = tonumber(area.z) or 0
        local cx = math.floor((minX + maxX) / 2)
        local cy = math.floor((minY + maxY) / 2)
        local best, bestDist = nil, math.huge
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                if square ~= nil and square.canStand ~= nil then
                    local ok, standable = pcall(function() return square:canStand() end)
                    if ok and standable == true then
                        local d = (x - cx) ^ 2 + (y - cy) ^ 2
                        if d < bestDist then best, bestDist = square, d end
                    end
                end
            end
        end
        return best
    end
    return scanArea(home) or scanArea(territory)
end

local function onCreatePlayer(playerNum)
    if not KnoxSettings.continueSurvivorsAfterPlayerDeath() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    local adopted, result = KnoxPersistence.adoptPendingPlayerSuccession(
        player,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    if adopted then
        -- Spawn back at the base area so the new survivor rejoins residents.
        local base = KnoxPersistence.getBase(result)
        local square = findBaseRespawnSquare(base)
        if square ~= nil then
            pcall(function()
                if player.teleportTo ~= nil then
                    player:teleportTo(square)
                elseif player.setX ~= nil then
                    player:setX(square:getX() + 0.5)
                    player:setY(square:getY() + 0.5)
                    player:setZ(square:getZ())
                    if player.setCurrentSquare ~= nil then player:setCurrentSquare(square) end
                end
            end)
        end
        KnoxActivityFeed.event("Your survivors carried on. You wake up at your base.")
        reconcileSettlementDefinitions()
        for _, id in ipairs(KnoxPersistence.getBaseResidentIds(result) or {}) do
            if KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
                KnoxSurvivorRuntime.notifyDutyChanged(id)
            end
        end
    end
end

local function onPlayerDeath(player)
    if player == nil or not KnoxSettings.continueSurvivorsAfterPlayerDeath() then return end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local saved, result = KnoxPersistence.preparePlayerSuccession(
        playerId,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    if saved then
        print(TAG .. " player-death-succession=pending base=" .. tostring(result))
    end
    -- Freeze companions targeting the corpse so they do not follow a dead square.
    for _, id in ipairs(activeIds) do
        local c = controllers[id]
        if c ~= nil and c.companionOwnerId == playerId then
            c.nextThink = ticks + 300
            pcall(function() c.bridge:cancelNpcMove(id) end)
        end
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)

function Autonomy.spawnDeveloperScenario(player, scenario, qaOwnership)
    if not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_disabled"
    end
    local factionMinimum = KnoxSettings.npcFactionMinimumMembers ~= nil
        and KnoxSettings.npcFactionMinimumMembers() or 3
    local counts = { single = 1, companion = 1, group = 2, faction = factionMinimum, faction_base = factionMinimum }
    local count = counts[scenario]
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or bridge == nil or count == nil then
        return false, "scenario_unavailable"
    end
    local ids = {}
    for _ = 1, count do
        local id = KnoxPersistence.allocateDeveloperSurvivorId()
        ids[#ids + 1] = id
        if qaOwnership ~= nil then
            if type(qaOwnership) ~= "table"
                or type(qaOwnership.runId) ~= "string"
                or type(qaOwnership.ownerToken) ~= "string"
                or KnoxPersistence.tagDeveloperQaFixture == nil then
                return false, "invalid_qa_ownership", table.concat(ids, ",")
            end
            local tagged, tagResult = KnoxPersistence.tagDeveloperQaFixture(
                id, qaOwnership.runId, qaOwnership.ownerToken, qaOwnership.scenarioId)
            if not tagged then
                return false, "qa_fixture_tag_failed:" .. tostring(tagResult), table.concat(ids, ",")
            end
        end
    end
    local ready, result = ensurePopulation(bridge, player, ids)
    if not ready then
        return false, result, table.concat(ids, ",")
    end
    local configured, configureResult = configureScenario(player, scenario, ids)
    if not configured then
        return false, configureResult, table.concat(ids, ",")
    end
    for _, id in ipairs(ids) do
        scenarioIds[#scenarioIds + 1] = id
        KnoxCompanionService.syncController(id, controllers[id])
    end
    return true, table.concat(ids, ",") .. " " .. tostring(configureResult)
end

-- Remove only survivors created through allocateDeveloperSurvivorId. Automated
-- QA runs several real native fixtures in one save; without this ownership
-- boundary an earlier faction can fight, claim a shelter, or occupy a doorway
-- while a later traversal/job case is being measured.
function Autonomy.cleanupDeveloperScenario(ids, reason, qaOwnership)
    if not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_disabled"
    end
    if type(ids) ~= "table" then return false, "invalid_ids" end
    if qaOwnership ~= nil and (type(qaOwnership) ~= "table"
        or type(qaOwnership.runId) ~= "string" or qaOwnership.runId == ""
        or type(qaOwnership.ownerToken) ~= "string" or qaOwnership.ownerToken == "") then
        return false, "invalid_qa_owner"
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then return false, "bridge_unavailable" end
    local removed, failures = 0, {}
    local now = getGameTime() ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
    for _, id in ipairs(ids) do
        if type(id) ~= "string" or string.find(id, "ks-dev-", 1, true) ~= 1 then
            failures[#failures + 1] = tostring(id) .. ":not_developer_survivor"
        elseif qaOwnership ~= nil and (KnoxPersistence.getDeveloperQaFixtureOwner == nil
            or (function()
                local owner = KnoxPersistence.getDeveloperQaFixtureOwner(id)
                return owner == nil or owner.runId ~= qaOwnership.runId
                    or owner.ownerToken ~= qaOwnership.ownerToken
            end)()) then
            failures[#failures + 1] = id .. ":qa_owner_mismatch"
        else
            local controller = controllers[id]
            if controller ~= nil then
                local stopped, stopResult = pcall(function() return controller:shutdown() end)
                if not stopped then
                    failures[#failures + 1] = id .. ":shutdown=" .. tostring(stopResult)
                end
            end
            local removeOk, removeResult = pcall(function() return bridge:removeNpc(id) end)
            local encoded = removeOk and tostring(removeResult) or tostring(removeResult)
            if not removeOk or (string.find(encoded, "REMOVED", 1, true) ~= 1
                and encoded ~= "NONE_ACTIVE") then
                failures[#failures + 1] = id .. ":remove=" .. encoded
            else
                local bodyOk, remainingBody = pcall(function()
                    return bridge:getNpcCharacter(id)
                end)
                if not bodyOk or remainingBody ~= nil then
                    failures[#failures + 1] = id .. ":native_body_remains_or_unverifiable"
                else
                    KnoxSurvivorRuntime.unregister(id, controller)
                    controllers[id] = nil
                    removeActiveId(id)
                    for index = #scenarioIds, 1, -1 do
                        if scenarioIds[index] == id then table.remove(scenarioIds, index) end
                    end
                    local marked = KnoxPersistence.markSurvivorDead(
                        id,
                        now,
                        "developer_fixture_cleanup:" .. tostring(reason or "complete")
                    )
                    if not marked then
                        failures[#failures + 1] = id .. ":persistence_retirement_failed"
                    else
                        if qaOwnership ~= nil
                            and KnoxPersistence.clearDeveloperQaFixtureOwner ~= nil then
                            local cleared = KnoxPersistence.clearDeveloperQaFixtureOwner(
                                id, qaOwnership.runId, qaOwnership.ownerToken)
                            if not cleared then
                                failures[#failures + 1] = id .. ":qa_owner_clear_failed"
                            else
                                removed = removed + 1
                            end
                        else
                            removed = removed + 1
                        end
                    end
                end
            end
        end
    end
    -- QA-scoped cleanup cannot purge other developer factions or bases. Legacy
    -- manual scenarios retain their previous opt-in developer cleanup behavior.
    if qaOwnership == nil and KnoxPersistence.purgeDeveloperQaBases ~= nil then
        pcall(KnoxPersistence.purgeDeveloperQaBases)
    end
    return #failures == 0,
        "removed=" .. tostring(removed)
            .. (#failures > 0 and " failures=" .. table.concat(failures, ";") or "")
end

-- A multi-survivor mission cannot use the ordinary single-body hibernation
-- path: team ownership must be durable before any shell is removed, and a
-- partial native teardown must be recorded as incomplete rather than an
-- outbound mission. This helper owns that bounded handoff.
local function dispatchAwayTeam(bridge, ownerKind, ownerId, selected, missionType,
    destination, now, etaHours, returnDestination, provisionReason)
    local valid, validation = KnoxPersistence.validateAwayTeam(
        ownerKind, ownerId, selected, missionType, destination
    )
    if not valid then return false, "mission_invalid=" .. tostring(validation) end
    local entries = {}
    for _, id in ipairs(selected) do
        local controller = controllers[id]
        if controller == nil or bridge:getNpcCharacter(id) == nil then
            return false, "missing_active_member=" .. tostring(id)
        end
        entries[#entries + 1] = { id = id, controller = controller }
    end
    local function restoreLoaded(entries, first)
        for index = first or 1, #entries do
            local entry = entries[index]
            if entry.controller ~= nil and controllers[entry.id] == entry.controller then
                local rolledBack, rollbackResult = KnoxUnloadedSurvival.rollbackStored(
                    entry.id, now
                )
                pcall(function() entry.controller:shutdown() end)
                KnoxSurvivorRuntime.setLifecycleState(entry.id, "active")
                if not rolledBack then
                    print(TAG .. " id=" .. tostring(entry.id)
                        .. " away-dispatch-store-rollback-failed result="
                        .. tostring(rollbackResult))
                end
            end
        end
    end
    for _, entry in ipairs(entries) do
        prepareUnloadedResourceHandoff(entry.id, entry.controller, provisionReason)
        local captured, saved, evidence = pcall(function()
            return entry.controller:shutdown()
        end)
        if not captured or not saved then
            restoreLoaded(entries)
            return false, "capture_failed=" .. tostring(entry.id) .. " "
                .. tostring(captured and evidence or saved)
        end
    end
    for _, entry in ipairs(entries) do
        local stored, result = KnoxUnloadedSurvival.markStored(entry.id, now)
        if not stored then
            restoreLoaded(entries)
            return false, "store_failed=" .. tostring(entry.id) .. " " .. tostring(result)
        end
    end
    local team, result = KnoxPersistence.prepareAwayTeam(
        ownerKind, ownerId, selected, missionType, destination,
        now, etaHours, returnDestination
    )
    if team == nil then
        restoreLoaded(entries)
        return false, "team_prepare_failed=" .. tostring(result)
    end
    for index, entry in ipairs(entries) do
        local removed = tostring(bridge:removeNpc(entry.id))
        local gone = bridge:getNpcCharacter(entry.id) == nil
        if not gone then
            KnoxPersistence.abortAwayTeamDispatch(
                team.id, "remove_failed=" .. tostring(entry.id) .. ":" .. removed, now
            )
            restoreLoaded(entries, index)
            return false, "dispatch_incomplete=" .. tostring(team.id)
                .. " member=" .. tostring(entry.id) .. " remove=" .. removed
        end
        KnoxPersistence.recordAwayTeamDispatchRemoval(team.id, entry.id)
        KnoxSurvivorRuntime.unregister(entry.id, entry.controller)
        controllers[entry.id] = nil
        removeActiveId(entry.id)
    end
    local finalized, finalResult = KnoxPersistence.finalizeAwayTeamDispatch(team.id, now)
    if finalized == nil then
        KnoxPersistence.abortAwayTeamDispatch(team.id, "finalize_failed=" .. tostring(finalResult), now)
        return false, "dispatch_incomplete=" .. tostring(team.id)
            .. " finalize=" .. tostring(finalResult)
    end
    return true, finalized
end

-- Developer-only handoff gate for the away-team lifecycle.
function Autonomy.dispatchDeveloperScout(player, destinationSquare)
    if not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_disabled"
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or destinationSquare == nil or bridge == nil then
        return false, "dispatch_unavailable"
    end
    local selected, ownerKind, ownerId = {}, nil, nil
    for _, id in ipairs(activeIds) do
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
        if affiliation.kind == "faction" and type(affiliation.factionId) == "string" then
            ownerKind, ownerId = "faction", affiliation.factionId
            break
        end
    end
    if ownerKind == nil then
        return false, "need_loaded_faction_survivor"
    end
    for _, id in ipairs(activeIds) do
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
        if affiliation.kind == ownerKind and affiliation.factionId == ownerId then
            selected[#selected + 1] = id
        end
    end
    if #selected == 0 then
        return false, "no_faction_members"
    end
    local destination = {
        x = destinationSquare:getX(), y = destinationSquare:getY(),
        z = destinationSquare:getZ(), label = "Scouting destination",
    }
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local dispatched, team = dispatchAwayTeam(bridge, ownerKind, ownerId, selected,
        "scout", destination, now, now + 2, nil, "away_team")
    if not dispatched then return false, team end
    print(TAG .. " away-dispatched id=" .. tostring(team.id)
        .. " members=" .. table.concat(selected, ",") .. " result=dispatched")
    return true, team.id
end

-- Normal player-base scouting command. It sends exactly one available, loaded resident
-- so the base never empties itself from a broad context-menu action.
function Autonomy.dispatchBaseScout(player, baseId, destinationSquare)
    local bridge = rawget(_G, "KnoxJavaBridge")
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil or destinationSquare == nil or bridge == nil then
        return false, "dispatch_unavailable"
    end
    local selected, controller = nil, nil
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(baseId)) do
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local runtime = controllers[id]
        if duty.mode == "base" and duty.ownerId == playerId and runtime ~= nil then
            selected, controller = id, runtime
            break
        end
    end
    if selected == nil then
        return false, "need_loaded_base_resident"
    end
    local destination = {
        x = destinationSquare:getX(), y = destinationSquare:getY(),
        z = destinationSquare:getZ(), label = "Player scout destination",
    }
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local dispatched, team = dispatchAwayTeam(bridge, "player", playerId, { selected },
        "scout", destination, now, now + 2,
        {
            x = player:getX(), y = player:getY(), z = player:getZ(),
            label = "Player dispatch point",
        }, "base_scout")
    if not dispatched then return false, team end
    return true, team.id
end

-- CompanionService calls this only after the companion's duty was changed to
-- a player-base assignment and the base destination is not currently loaded.
-- It is the same capture/remove ownership boundary used by distance hibernation
-- and away teams, followed by a persisted virtual route rather than a teleport.
function Autonomy.beginVirtualBaseReturn(survivorId, baseId)
    local bridge = rawget(_G, "KnoxJavaBridge")
    local controller = controllers[survivorId]
    local base = KnoxPersistence.getBase(baseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if bridge == nil or controller == nil or area == nil then
        return false, "return_handoff_unavailable"
    end
    local targetX = math.floor(tonumber(area.minX) or -1)
    local targetY = math.floor(tonumber(area.minY) or -1)
    local targetZ = math.floor(tonumber(area.z) or 0)
    if getCell() ~= nil and getCell():getGridSquare(targetX, targetY, targetZ) ~= nil then
        return false, "base_loaded"
    end
    local saved, evidence = controller:shutdown()
    if not saved then return false, "capture_failed=" .. tostring(evidence) end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local marked, markResult = KnoxUnloadedSurvival.markStored(survivorId, now)
    if not marked then
        return false, "store_failed=" .. tostring(markResult)
    end
    local started, result = KnoxUnloadedSurvival.beginBaseReturn(survivorId, base, now)
    if not started then
        local rolledBack, rollbackResult = KnoxUnloadedSurvival.rollbackBaseReturn(survivorId, now)
        return false, "route_failed=" .. tostring(result)
            .. " rollback=" .. tostring(rolledBack and "ok" or rollbackResult)
    end
    local removed = tostring(bridge:removeNpc(survivorId))
    if string.find(removed, "REMOVED", 1, true) ~= 1 and removed ~= "NONE_ACTIVE" then
        local rolledBack, rollbackResult = KnoxUnloadedSurvival.rollbackBaseReturn(survivorId, now)
        return false, "remove_failed=" .. removed
            .. " rollback=" .. tostring(rolledBack and "ok" or rollbackResult)
    end
    KnoxSurvivorRuntime.unregister(survivorId, controller)
    controllers[survivorId] = nil
    removeActiveId(survivorId)
    print(TAG .. " id=" .. tostring(survivorId)
        .. " state=VIRTUAL_BASE_RETURN base=" .. tostring(baseId)
        .. " result=" .. tostring(result))
    return true, result
end

function Autonomy.status()
    return {
        ids = activeIds,
        controllers = controllers,
        ticks = ticks,
        running = KnoxSettings.enabled(),
        worldPopulation = KnoxPersistence.getPopulationState(),
    }
end

-- Narrow lifecycle test seam; production invokes the same reconciliation
-- before candidate selection.
Autonomy.releaseMissingActiveBodies = releaseMissingActiveBodies

return Autonomy
