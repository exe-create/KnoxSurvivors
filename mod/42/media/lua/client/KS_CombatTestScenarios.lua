require "KS_SurvivorAutonomy"
require "KS_ActivityFeed"
require "KS_FirearmSupport"
pcall(function() require "KS_DebugLog" end)

local CombatTests = rawget(_G, "KnoxCombatTestScenarios") or {}
_G.KnoxCombatTestScenarios = CombatTests

local TAG = "[KnoxSurvivors][CombatTest]"
local TIMEOUT_TICKS = 2400
local SNAPSHOT_INTERVAL_TICKS = 120

local definitions = {
    duel = { population = "single", zombies = 1, label = "Survivor vs Zombie" },
    crawler_duel = {
        population = "single",
        zombies = 1,
        crawler = true,
        label = "Survivor vs Crawler",
    },
    survivor_horde = { population = "single", zombies = 4, label = "Survivor vs Zombie Group" },
    group_horde = { population = "group", zombies = 5, label = "Travel Group vs Zombies" },
    faction_horde = { population = "faction", zombies = 8, label = "Faction vs Zombies" },
    stress = { population = "faction", zombies = 12, label = "Faction Combat Stress Test" },
    firearm_duel = {
        -- Two independently spawned survivors receive real pistols, empty
        -- magazines and loose rounds.  They are hostile only to each other.
        -- This exercises target selection, equip, native reload and native
        -- projectile damage without a zombie or another group changing focus.
        population = "independent_pair",
        survivors = 2,
        firearm = true,
        label = "Hostile Survivor Firearm Duel",
    },
}

local active = nil
-- The scenario ticker is installed only while a test is armed and removed on
-- the same teardown that clears `active`, so an idle game pays one no-op call
-- less per tick and a finished test cannot leave a handler behind.
local tickerInstalled = false
local update
local function installTicker()
    if tickerInstalled or Events == nil or Events.OnTick == nil
        or Events.OnTick.Add == nil then return end
    tickerInstalled = true
    Events.OnTick.Add(update)
end
local function removeTicker()
    if not tickerInstalled then return end
    if Events ~= nil and Events.OnTick ~= nil and Events.OnTick.Remove ~= nil then
        Events.OnTick.Remove(update)
    end
    tickerInstalled = false
end
local lastResult = nil
local trackedZombies = {}
local preferredOwners = setmetatable({}, { __mode = "k" })

local function characterHealth(character)
    local success, value = pcall(function()
        return character:getBodyDamage():getHealth()
    end)
    return success and tonumber(value) or tonumber(character:getHealth()) or 100
end

local function removeZombie(zombie)
    if zombie == nil then
        return
    end
    pcall(function()
        zombie:setTarget(nil)
        zombie:setUseless(true)
        zombie:setCanWalk(false)
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end)
end

function CombatTests.cleanup(silent)
    local removed = 0
    for _, zombie in ipairs(trackedZombies) do
        if zombie ~= nil then
            removeZombie(zombie)
            removed = removed + 1
        end
    end
    trackedZombies = {}
    preferredOwners = setmetatable({}, { __mode = "k" })
    local fixtureIds = active ~= nil and active.fixtureIds or nil
    removeTicker()
    active = nil
    if type(fixtureIds) == "table" and #fixtureIds > 0
        and KnoxSurvivorAutonomy.cleanupDeveloperScenario ~= nil then
        local ok, evidence = pcall(function()
            return KnoxSurvivorAutonomy.cleanupDeveloperScenario(
                fixtureIds, "combat_test_cleanup"
            )
        end)
        print(TAG .. " fixture_cleanup ok=" .. tostring(ok)
            .. " ids=" .. table.concat(fixtureIds, ",")
            .. " evidence=" .. tostring(evidence))
    end
    print(TAG .. " cleanup removedScenarioZombies=" .. tostring(removed))
    if silent ~= true then
        KnoxActivityFeed.event("Combat test cleaned up (" .. tostring(removed) .. " zombies).")
    end
end

function CombatTests.preferredNpcId(zombie)
    return preferredOwners[zombie]
end

function CombatTests.status()
    return {
        active = active ~= nil,
        name = active ~= nil and active.name or nil,
        survivors = active ~= nil and #active.ids or 0,
        zombies = active ~= nil and #active.zombies or 0,
        trackedZombies = #trackedZombies,
        finished = active ~= nil and active.finished or false,
        result = lastResult,
    }
end

local function parseIds(result)
    local encoded = tostring(result or ""):match("^([^ ]+)") or ""
    local ids = {}
    for id in string.gmatch(encoded, "[^,]+") do
        ids[#ids + 1] = id
    end
    return ids
end

local function findSpawnSquare(origin, ordinal, minimumDistance, maximumDistance)
    local cell = getCell()
    if cell == nil or origin == nil then
        return nil
    end
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
    }
    for step = 0, #directions - 1 do
        local direction = directions[((ordinal + step - 1) % #directions) + 1]
        local previous = origin
        local valid = true
        local destination = nil
        for distance = 1, maximumDistance or 3 do
            destination = cell:getGridSquare(
                origin:getX() + direction[1] * distance,
                origin:getY() + direction[2] * distance,
                origin:getZ()
            )
            if destination == nil or not destination:canStand()
                or previous:isBlockedTo(destination) then
                valid = false
                break
            end
            previous = destination
        end
        if valid and ((maximumDistance or 3) >= (minimumDistance or 1)) then
            return destination
        end
    end
    return nil
end

local function report(status, reason)
    if active == nil then
        return
    end
    local brief = tostring(reason)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.brief ~= nil then
        local okBrief, text = pcall(function() return log.brief(reason) end)
        if okBrief and text ~= nil then brief = text end
    end
    print(TAG .. " RESULT scenario=combat_" .. tostring(active.name)
        .. " status=" .. tostring(status)
        .. " reason=" .. tostring(reason)
        .. " brief=" .. tostring(brief)
        .. " survivorHits=" .. tostring(active.survivorHits)
        .. " zombieDamage=" .. tostring(active.zombieDamage)
        .. " attackActionSeen=" .. tostring(active.attackActionSeen)
        .. " attackDidDamageSeen=" .. tostring(active.attackDidDamageSeen)
        .. " zombiesKilled=" .. tostring(active.zombiesKilled)
        .. " humanDamage=" .. tostring(active.humanDamage or 0))
    lastResult = {
        status = status,
        reason = reason,
        scenario = active.name,
        survivorHits = active.survivorHits,
        zombieDamage = active.zombieDamage,
        zombiesKilled = active.zombiesKilled,
        humanDamage = active.humanDamage or 0,
    }
    if tostring(status) == "FAIL" or tostring(status) == "PARTIAL" then
        KnoxActivityFeed.event("Combat test " .. tostring(active.definition.label) .. ": "
            .. tostring(status) .. " - " .. tostring(brief))
    else
        KnoxActivityFeed.event("Combat test " .. tostring(active.definition.label) .. ": "
            .. tostring(status) .. " (" .. tostring(reason) .. ").")
    end
    active.finished = true
    removeTicker()
end

local function zombieAction(zombie)
    local success, action = pcall(function()
        return tostring(zombie:getCurrentActionContextStateName())
    end)
    return success and action or "unavailable"
end

local function variableBoolean(character, name)
    local success, value = pcall(function()
        return character:getVariableBoolean(name)
    end)
    return success and value == true
end

local function firearmAmmo(character)
    if character == nil then
        return "missing"
    end
    local success, result = pcall(function()
        local weapon = character:getPrimaryHandItem()
        if weapon == nil or not weapon:isRanged() then
            return "not_ranged"
        end
        return tostring(weapon:getFullType())
            .. " rounds=" .. tostring(weapon:getCurrentAmmoCount())
            .. " chambered=" .. tostring(weapon:isRoundChambered())
    end)
    return success and result or "unavailable"
end

function CombatTests.writeSnapshot()
    if active == nil then
        print(TAG .. " snapshot active=false trackedZombies=" .. tostring(#trackedZombies))
        KnoxActivityFeed.event("No combat test is currently running.")
        return
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    local status = KnoxSurvivorAutonomy.status()
    print(TAG .. " snapshot scenario=" .. tostring(active.name)
        .. " elapsed=" .. tostring(active.elapsed)
        .. " finished=" .. tostring(active.finished))
    for _, id in ipairs(active.ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        local character = controller ~= nil and controller.character or nil
        if character == nil then
            -- A dead test shell is intentionally removed by the native corpse
            -- lifecycle. Report that plainly rather than repeatedly asking the
            -- Java bridge for a controller that cannot exist anymore.
            print(TAG .. " survivor id=" .. tostring(id) .. " status=eliminated")
        else
            print(TAG .. " survivor id=" .. tostring(id)
                .. " health=" .. tostring(characterHealth(character))
                .. " firearm=" .. tostring(firearmAmmo(character))
                .. " controller=" .. tostring(controller:status()))
        end
        if character ~= nil and bridge ~= nil and bridge.getNpcCombatDiagnostics ~= nil then
            print(TAG .. " survivor-java id=" .. tostring(id)
                .. " " .. tostring(bridge:getNpcCombatDiagnostics(id)))
        end
    end
    for index, zombie in ipairs(active.zombies) do
        local ownerId = active.zombieOwners[index]
        local dead = zombie == nil or zombie:isDead()
        print(TAG .. " zombie index=" .. tostring(index)
            .. " owner=" .. tostring(ownerId)
            .. " dead=" .. tostring(dead)
            .. " health=" .. tostring(not dead and zombie:getHealth() or 0)
            .. " action=" .. tostring(not dead and zombieAction(zombie) or "dead")
            .. " attackDidDamage="
            .. tostring(not dead and variableBoolean(zombie, "AttackDidDamage") or false))
        if not dead and bridge ~= nil and bridge.getZombieAttackDiagnostics ~= nil then
            print(TAG .. " zombie-java index=" .. tostring(index) .. " "
                .. tostring(bridge:getZombieAttackDiagnostics(ownerId, zombie)))
        end
    end
    KnoxActivityFeed.event("Combat snapshot written to console.txt.")
end

function CombatTests.start(playerNum, scenario, aimLevel)
    local definition = definitions[scenario]
    local player = getSpecificPlayer(playerNum)
    if definition == nil or player == nil or getCell() == nil then
        KnoxActivityFeed.event("Combat test could not start here.")
        return false
    end
    CombatTests.cleanup(true)
    lastResult = nil
    local ids = {}
    local function spawnIndependent()
        local success, result = KnoxSurvivorAutonomy.spawnDeveloperScenario(player, "single")
        if success then
            for _, id in ipairs(parseIds(result)) do ids[#ids + 1] = id end
        end
        return success, result
    end
    local success, result
    if definition.population == "independent_pair" then
        success, result = spawnIndependent()
        if success then success, result = spawnIndependent() end
    else
        success, result = KnoxSurvivorAutonomy.spawnDeveloperScenario(player, definition.population)
        if success then ids = parseIds(result) end
    end
    if not success or #ids < (definition.survivors or 1) then
        print(TAG .. " start-failed scenario=" .. tostring(scenario)
            .. " reason=" .. tostring(result))
        KnoxActivityFeed.event("Combat test survivor spawn failed: " .. tostring(result) .. ".")
        return false
    end
    local status = KnoxSurvivorAutonomy.status()
    local bridge = rawget(_G, "KnoxJavaBridge")
    active = {
        name = scenario,
        definition = definition,
        ids = ids,
        fixtureIds = ids,
        zombies = {},
        zombieOwners = {},
        survivorHealth = {},
        zombieHealth = {},
        elapsed = 0,
        survivorHits = 0,
        zombieDamage = 0,
        zombiesKilled = 0,
        rangedHookAttemptCount = 0,
        rangedRequestSeen = false,
        healthChangeNearRangedAttempt = false,
        healthChangeDistance = nil,
        rangedStateById = {},
        hookAttemptsById = {},
        hookAttemptBaselineById = {},
        humanDamage = 0,
        opponentHealth = {},
        opponents = {},
        attackActionSeen = false,
        attackDidDamageSeen = false,
        crawlerConfigured = definition.crawler ~= true,
        finished = false,
    }
    installTicker()
    for _, id in ipairs(ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        if controller ~= nil and controller.character ~= nil then
            active.survivorHealth[id] = characterHealth(controller.character)
            controller.character:setZombiesDontAttack(false)
            -- The duel is a skill test, so the level is set on the real body:
            -- the native Aiming perk then drives aim, settle and spread for
            -- every shot the test measures. Unset means the rolled skill stays.
            if aimLevel ~= nil then
                local level = math.max(1, math.min(10, math.floor(tonumber(aimLevel) or 1)))
                pcall(function()
                    controller.character:getXp():setXPToLevel(Perks.Aiming, level)
                end)
                local reached = level
                pcall(function()
                    reached = tonumber(controller.character:getPerkLevel(Perks.Aiming)) or level
                end)
                print(TAG .. " aiming-set id=" .. tostring(id)
                    .. " wanted=" .. tostring(level) .. " actual=" .. tostring(reached))
                active.aimLevel = reached
            end
        end
        if definition.firearm == true and bridge ~= nil
            and bridge.seedNpcFirearmTestKit ~= nil then
            local kit = tostring(bridge:seedNpcFirearmTestKit(id))
            print(TAG .. " firearm-kit id=" .. tostring(id) .. " result=" .. kit)
            local log = rawget(_G, "KnoxDebugLog")
            -- Verify the native items actually landed. AddItem with a retired
            -- B42 id returns nil without throwing, which used to report
            -- FIREARM_KIT_ADDED while the survivor still had no gun.
            -- Each count is an independent pcall: one missing vanilla query
            -- must not zero out the other two and false-fail the kit.
            local kitCheck = { pistol = false, magazine = false, rounds = 0 }
            local character = controller ~= nil and controller.character or nil
            local inventory = nil
            pcall(function()
                inventory = character ~= nil and character:getInventory() or nil
            end)
            if inventory ~= nil then
                pcall(function()
                    kitCheck.pistol = (tonumber(inventory:getItemCount("Base.Pistol", true)) or 0) > 0
                end)
                pcall(function()
                    kitCheck.magazine = (tonumber(inventory:getItemCount("Base.9mmClip", true)) or 0) > 0
                end)
                pcall(function()
                    kitCheck.rounds = tonumber(inventory:getItemCount("Base.Bullets9mm", true)) or 0
                end)
            end
            if log ~= nil and log.once ~= nil then
                pcall(function() log.once("firearm", id, "kit_seeded", {
                    result = kit, pistol = kitCheck.pistol,
                    magazine = kitCheck.magazine, rounds = kitCheck.rounds,
                }) end)
            end
            if string.find(kit, "FIREARM_KIT_ADDED", 1, true) ~= 1
                or not kitCheck.pistol or (kitCheck.rounds or 0) <= 0 then
                print(TAG .. " firearm-kit-verify id=" .. tostring(id)
                    .. " pistol=" .. tostring(kitCheck.pistol)
                    .. " magazine=" .. tostring(kitCheck.magazine)
                    .. " rounds=" .. tostring(kitCheck.rounds))
                CombatTests.cleanup(true)
                KnoxActivityFeed.event("Firearm test kit failed: " .. kit
                    .. " (pistol=" .. tostring(kitCheck.pistol)
                    .. " rounds=" .. tostring(kitCheck.rounds) .. ").")
                return false
            end
            -- The firearm scenario must exercise reload/fire even when the
            -- randomized test survivor is a novice carrying a good bat.
            if not KnoxPersistence.setSurvivorWeaponPreference(id, "ranged") then
                CombatTests.cleanup(true)
                KnoxActivityFeed.event("Firearm test preference could not be saved.")
                return false
            end
            if controller ~= nil and controller.setWeaponPreference ~= nil then
                controller:setWeaponPreference("ranged")
            end
        end
    end
    if definition.firearm == true and #ids == 2 then
        local firstId, secondId = ids[1], ids[2]
        local hostile = KnoxPersistence.setRelationshipDisposition(
            firstId, secondId, "hostile",
            getGameTime ~= nil and getGameTime():getWorldAgeHours() + 24 or 24
        )
        if hostile == nil then
            print(TAG .. " hostile-pairing-failed hostile=false")
            CombatTests.cleanup(true)
            KnoxActivityFeed.event("Hostile firearm fixture could not record hostility.")
            return false
        end
        -- Staged pairing: freshly seeded pistols have empty magazines, so an
        -- immediate beginCombat only yields for the reload (or close-range
        -- forces a melee fallback that cancels it). Stage loaded guns first
        -- via prepareForThreat, then engage once both report ready. update()
        -- owns the retries; start() only declares the intent.
        active.opponents[firstId], active.opponents[secondId] = secondId, firstId
        active.staging = true
        active.stageNextTry = 0
        print(TAG .. " hostile-staged pair=" .. tostring(firstId)
            .. "," .. tostring(secondId))
    end
    for index = 1, definition.zombies or 0 do
        local ownerId = ids[((index - 1) % math.max(1, #ids)) + 1]
        local controller = status.controllers ~= nil and status.controllers[ownerId] or nil
        local origin = controller ~= nil and controller.character:getCurrentSquare()
            or player:getCurrentSquare()
        -- A firearm acceptance run must begin outside close-pressure range.
        -- The ordinary three-tile spawn is intentional for melee scenarios but
        -- proves only a fallback swing for a pistol carrier.
        local square = findSpawnSquare(
            origin,
            index,
            definition.firearm == true and 8 or 1,
            definition.firearm == true and 8 or 3
        )
        if square ~= nil then
            local spawned = addZombiesInOutfit(
                square:getX(), square:getY(), square:getZ(), 1, nil, nil
            )
            local zombie = spawned ~= nil and spawned:size() > 0 and spawned:get(0) or nil
            if zombie ~= nil then
                if definition.crawler == true then
                    local crawlerSuccess = pcall(function()
                        zombie:setCrawler(true)
                    end)
                    active.crawlerConfigured = crawlerSuccess
                end
                active.zombies[#active.zombies + 1] = zombie
                active.zombieOwners[#active.zombieOwners + 1] = ownerId
                preferredOwners[zombie] = ownerId
                active.zombieHealth[zombie] = zombie:getHealth()
                trackedZombies[#trackedZombies + 1] = zombie
                if bridge ~= nil and bridge.directZombieAtNpc ~= nil then
                    bridge:directZombieAtNpc(ownerId, zombie)
                end
            end
        end
    end
    if (definition.zombies or 0) > 0 and #active.zombies == 0 then
        report("BLOCKED", "no_standable_zombie_spawn_square")
        return false
    end
    print(TAG .. " START scenario=combat_" .. tostring(scenario)
        .. " survivors=" .. table.concat(ids, ",")
        .. " humanOpponents=" .. tostring(definition.firearm == true)
        .. " zombies=" .. tostring(#active.zombies)
        .. " crawler=" .. tostring(definition.crawler == true)
        .. " crawlerConfigured=" .. tostring(active.crawlerConfigured)
        .. " timeoutTicks=" .. tostring(TIMEOUT_TICKS))
    KnoxActivityFeed.event("Started " .. definition.label
        .. ". The test reports itself; use Cleanup Combat Test when finished.")
    return true
end

update = function()
    if active == nil or active.finished then
        return
    end
    active.elapsed = active.elapsed + 1
    local status = KnoxSurvivorAutonomy.status()
    local activeSurvivors = 0
    for _, id in ipairs(active.ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        local character = controller ~= nil and controller.character or nil
        if character ~= nil then
            activeSurvivors = activeSurvivors + 1
            local previous = active.survivorHealth[id] or characterHealth(character)
            local current = characterHealth(character)
            if current < previous - 0.01 then
                active.zombieDamage = active.zombieDamage + (previous - current)
            end
            active.survivorHealth[id] = current
            local attempts = KnoxFirearmSupport.nativeHookAttemptCount ~= nil
                and KnoxFirearmSupport.nativeHookAttemptCount(character) or 0
            if active.hookAttemptBaselineById[id] == nil then
                active.hookAttemptBaselineById[id] = attempts
            end
            attempts = math.max(0, attempts - active.hookAttemptBaselineById[id])
            active.rangedHookAttemptCount = math.max(active.rangedHookAttemptCount or 0, attempts)
            active.hookAttemptsById[id] = math.max(active.hookAttemptsById[id] or 0, attempts)
            local bridge = rawget(_G, "KnoxJavaBridge")
            local diagnostics = bridge ~= nil and bridge.getNpcCombatDiagnostics ~= nil
                and tostring(bridge:getNpcCombatDiagnostics(id)) or ""
            local attacks = tonumber(diagnostics:match("attacks=(%d+)")) or 0
            local distance = tonumber(diagnostics:match("distance=([%d%.]+)")) or 0
            local ranged = string.find(diagnostics, "ranged=true", 1, true) ~= nil
            active.rangedRequestSeen = active.rangedRequestSeen
                or (ranged and attacks > 0)
            active.rangedStateById[id] = {
                active = ranged and attacks > 0 and attempts > 0 and distance >= 4,
                distance = distance,
            }
        end
    end
    if activeSurvivors == 0 then
        report("FAIL", "all_test_survivors_eliminated")
        CombatTests.writeSnapshot()
        return
    end
    if active.definition.firearm == true and active.staging == true then
        -- Hold both duelists' autonomous threat scans while their pistols
        -- load: an adjacent hostile would otherwise force a melee fallback
        -- that cancels the queued native reload. Drive preparation directly
        -- and engage only once both report a ready gun.
        local firstId, secondId = active.ids[1], active.ids[2]
        local first = status.controllers ~= nil and status.controllers[firstId] or nil
        local second = status.controllers ~= nil and status.controllers[secondId] or nil
        if first == nil or second == nil
            or first.character == nil or second.character == nil then
            -- Bodies stream out if the observer walks off; they usually
            -- stream back. Wait instead of failing: the suite timeout bounds
            -- a genuinely lost fixture.
            if active.stageMissingSince == nil then
                active.stageMissingSince = active.elapsed
                print(TAG .. " staging-waiting pair=" .. tostring(firstId)
                    .. "," .. tostring(secondId))
            end
            return
        end
        active.stageMissingSince = nil
        pcall(function() first.nextThreatScan = active.elapsed + 1000 end)
        pcall(function() second.nextThreatScan = active.elapsed + 1000 end)
        if active.elapsed >= (active.stageNextTry or 0) then
            active.stageNextTry = active.elapsed + 90
            local bridge = rawget(_G, "KnoxJavaBridge")
            local firstState, secondState = "unavailable", "unavailable"
            pcall(function()
                KnoxFirearmSupport.prepareForThreat(
                    firstId, first.character, bridge, second.character)
                firstState = KnoxFirearmSupport.currentCombatState(first.character)
            end)
            pcall(function()
                KnoxFirearmSupport.prepareForThreat(
                    secondId, second.character, bridge, first.character)
                secondState = KnoxFirearmSupport.currentCombatState(second.character)
            end)
            print(TAG .. " staging duelists=" .. tostring(firstId)
                .. "," .. tostring(secondId)
                .. " first=" .. tostring(firstState)
                .. " second=" .. tostring(secondState))
            if firstState == "ready" and secondState == "ready" then
                local firstCombat, secondCombat
                pcall(function()
                    firstCombat = first:beginCombat(second.character)
                end)
                pcall(function()
                    if firstCombat == true then
                        secondCombat = second:beginCombat(first.character)
                    end
                end)
                if firstCombat == true and secondCombat == true then
                    active.staging = false
                    active.opponentHealth[firstId] = characterHealth(first.character)
                    active.opponentHealth[secondId] = characterHealth(second.character)
                    print(TAG .. " staged-engaged pair=" .. tostring(firstId)
                        .. "," .. tostring(secondId))
                    pcall(function()
                        KnoxActivityFeed.event("Firearm duel engaged: both pistols ready.")
                    end)
                else
                    print(TAG .. " staging-engage-failed first=" .. tostring(firstCombat)
                        .. " second=" .. tostring(secondCombat))
                end
            end
        end
    end
    if active.definition.firearm == true and active.staging ~= true then
        for attackerId, targetId in pairs(active.opponents or {}) do
            local targetController = status.controllers ~= nil and status.controllers[targetId] or nil
            local target = targetController ~= nil and targetController.character or nil
            if target ~= nil then
                local previous = active.opponentHealth[targetId] or characterHealth(target)
                local current = characterHealth(target)
                if current < previous - 0.01 then
                    active.humanDamage = active.humanDamage + (previous - current)
                    if (active.hookAttemptsById[attackerId] or 0) > 0 then
                        active.healthChangeNearRangedAttempt = true
                    end
                end
                active.opponentHealth[targetId] = current
            end
        end
        local bothAttempted = #active.ids == 2
        for _, id in ipairs(active.ids) do
            bothAttempted = bothAttempted and (active.hookAttemptsById[id] or 0) > 0
        end
        if bothAttempted and active.healthChangeNearRangedAttempt and active.humanDamage > 0 then
            report("PARTIAL", "firearm_hook_attempts_and_health_change_observed_unattributed")
            CombatTests.writeSnapshot()
            return
        end
    end
    active.zombiesKilled = 0
    for index, zombie in ipairs(active.zombies) do
        -- One bad zombie object must never freeze the whole test tick.
        local dead = zombie == nil
        if not dead then
            local okDead, isDead = pcall(function() return zombie:isDead() end)
            dead = not okDead or isDead == true
        end
        if dead then
            -- A kill implies damage: a zombie that was alive with known
            -- health and is now dead took a finishing hit between ticks.
            -- Without this, one-hit kills credit zero hits and a dominant
            -- survivor who takes no damage can never progress the test.
            if active.zombieHealth[zombie] ~= nil then
                active.survivorHits = active.survivorHits + 1
                active.zombieHealth[zombie] = nil
            end
            active.zombiesKilled = active.zombiesKilled + 1
        else
            local okHealth, previous, current = pcall(function()
                local prev = active.zombieHealth[zombie]
                if prev == nil then prev = zombie:getHealth() end
                return prev, zombie:getHealth()
            end)
            if okHealth and (tonumber(current) or 0) < (tonumber(previous) or 0) - 0.001 then
                active.survivorHits = active.survivorHits + 1
                local ranged = active.rangedStateById[active.zombieOwners[index]]
                if ranged ~= nil and ranged.active then
                    active.healthChangeNearRangedAttempt = true
                    active.healthChangeDistance = ranged.distance
                end
            end
            if okHealth then active.zombieHealth[zombie] = current end
            active.attackActionSeen = active.attackActionSeen
                or string.lower(zombieAction(zombie)) == "attack"
            active.attackDidDamageSeen = active.attackDidDamageSeen
                or variableBoolean(zombie, "AttackDidDamage")
        end
    end
    if active.definition.firearm ~= true and active.rangedHookAttemptCount > 0
        and active.rangedRequestSeen and active.healthChangeNearRangedAttempt then
        report("PARTIAL", "firearm_hook_attempt_and_health_change_observed_unattributed")
        CombatTests.writeSnapshot()
        return
    end
    if active.definition.firearm ~= true and active.survivorHits > 0
        and (active.zombieDamage > 0 or active.attackDidDamageSeen) then
        report("PASS", "two_way_combat_observed")
        CombatTests.writeSnapshot()
        return
    end
    -- A survivor who kills every spawned target with observed damage has
    -- proven working combat even without taking a hit. Previously this sat
    -- until timeout/PARTIAL, looking like the test was stuck.
    if active.definition.firearm ~= true and #active.zombies > 0
        and active.zombiesKilled >= #active.zombies
        and active.survivorHits > 0 then
        report("PASS", "all_targets_eliminated")
        CombatTests.writeSnapshot()
        return
    end
    -- Event-driven progress in the activity feed: one line per fresh kill.
    -- This is what proves the test is moving while the survivor works.
    if active.zombiesKilled ~= (active.lastFedKills or 0) then
        active.lastFedKills = active.zombiesKilled
        print(TAG .. " progress scenario=" .. tostring(active.name)
            .. " hits=" .. tostring(active.survivorHits)
            .. " kills=" .. tostring(active.zombiesKilled)
            .. "/" .. tostring(#active.zombies))
        pcall(function()
            KnoxActivityFeed.event("Combat test: " .. tostring(active.zombiesKilled)
                .. "/" .. tostring(#active.zombies) .. " zombies down"
                .. " (hits=" .. tostring(active.survivorHits) .. ").")
        end)
    end
    if active.elapsed % SNAPSHOT_INTERVAL_TICKS == 0 then
        CombatTests.writeSnapshot()
    end
    -- An empty zombie roster (duels) must never satisfy the kill-count arm:
    -- 0 == 0 ended the test on its first tick before staging could run.
    if active.elapsed >= TIMEOUT_TICKS
        or (#active.zombies > 0 and active.zombiesKilled >= #active.zombies) then
        local reason = active.definition.firearm == true and "firearm_damage_unconfirmed"
            or (active.survivorHits > 0 and "survivor_damage_only")
            or (active.attackActionSeen and "zombie_attack_animation_without_damage"
                or "no_two_way_combat")
        if active.definition.firearm == true and active.staging == true then
            reason = "staging_timeout"
        end
        report(active.survivorHits > 0 and "PARTIAL" or "FAIL", reason)
        CombatTests.writeSnapshot()
    end
end

return CombatTests
