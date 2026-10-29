require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_Settings"
require "KS_SurvivorAutonomy"
require "KS_ActivityFeed"
require "KS_CombatTestScenarios"
require "KS_KnoxEvents"
require "KS_JobTestSupplies"
require "KS_JobTestScenarios"

local DeveloperTools = rawget(_G, "KnoxDeveloperTools") or {}
_G.KnoxDeveloperTools = DeveloperTools

local SCENARIOS = {
    { "Spawn Test Survivor", "single" },
    { "Spawn Test Companion", "companion" },
    { "Spawn Test Travel Group", "group" },
    { "Spawn Test Faction", "faction" },
    { "Spawn Test Faction Seeking a Base", "faction_base" },
    { "Spawn Two Strangers (Natural Encounter)", "encounter" },
}
local spawnBatches = {}
local spawnSequence = 0

local COMBAT_SCENARIOS = {
    { "Survivor vs Zombie", "duel" },
    { "Survivor vs Crawler", "crawler_duel" },
    { "Survivor vs Zombie Group", "survivor_horde" },
    { "Travel Group vs Zombies", "group_horde" },
    { "Faction vs Zombies", "faction_horde" },
    { "Faction Combat Stress Test", "stress" },
    { "Survivor Firearm Test", "firearm_duel" },
}

function DeveloperTools.spawn(playerNum, scenario, worldObjects, count)
    local player = getSpecificPlayer(playerNum)
    local object=worldObjects~=nil and worldObjects[1] or nil
    local square=object~=nil and object:getSquare() or nil
    spawnSequence=spawnSequence+1
    local token="manual-spawn-"..tostring(getTimestampMs~=nil and getTimestampMs() or 0).."-"..spawnSequence
    local owner={runId=token,ownerToken=token,scenarioId=scenario}
    local success, result, encodedIds = KnoxSurvivorAutonomy.spawnDeveloperScenario(player, scenario,
        owner,{square=square,count=count})
    local ids={}
    for id in tostring(encodedIds or ""):gmatch("[^,]+") do ids[#ids+1]=id end
    if #ids>0 then spawnBatches[#spawnBatches+1]={ids=ids,owner=owner} end
    if success then
        KnoxActivityFeed.event("Developer scenario spawned: " .. tostring(scenario) .. ".")
    else
        KnoxActivityFeed.event("Developer spawn failed: " .. tostring(result) .. ".")
    end
    print("[KnoxSurvivors][DeveloperTools] scenario=" .. tostring(scenario)
        .. " success=" .. tostring(success) .. " result=" .. tostring(result))
end

function DeveloperTools.cleanupLastSpawn()
    if not KnoxSettings.developerToolsEnabled() then return end
    local batch=spawnBatches[#spawnBatches]
    if batch==nil then KnoxActivityFeed.event("No manual spawn from this session to remove.");return end
    local pending={}
    for _,id in ipairs(batch.ids) do
        local owner=KnoxPersistence.getDeveloperQaFixtureOwner(id)
        if owner~=nil then pending[#pending+1]=id
        else
            -- A successful partial cleanup clears ownership only after verified
            -- native removal and retirement. Missing ownership on a live or
            -- unreadable fixture is not evidence that it was removed.
            local bridge=rawget(_G,"KnoxJavaBridge")
            local ok,body=pcall(function() return bridge:getNpcCharacter(id) end)
            if KnoxPersistence.isSurvivorAlive==nil or KnoxPersistence.isSurvivorAlive(id)~=false
                or not ok or body~=nil then
                KnoxActivityFeed.event("Last test spawn has missing ownership; removal remains blocked.")
                return
            end
        end
    end
    local success,result=KnoxSurvivorAutonomy.cleanupDeveloperScenario(pending,"manual_menu",batch.owner)
    if success then table.remove(spawnBatches) end
    KnoxActivityFeed.event("Remove last test spawn: "..tostring(result)..(success and "." or "; retry available."))
end

function DeveloperTools.writeSettings()
    local vars=rawget(_G,"SandboxVars")
    local keys={}
    for key in pairs(vars~=nil and vars.KnoxSurvivors or {}) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do print("[KnoxSurvivors][Settings] "..key.."="..tostring(vars.KnoxSurvivors[key])) end
    print("[KnoxSurvivors][Settings] effective county="..KnoxSettings.worldPopulation()
        .." bodies="..KnoxSettings.maxActiveSurvivors().." loading="..KnoxSettings.activationsPerUpdate())
    KnoxActivityFeed.event("Sandbox choices and effective population limits written to console.txt.")
end

function DeveloperTools.printStatus()
    local status = KnoxSurvivorAutonomy.status()
    print("[KnoxSurvivors][DeveloperTools] running=" .. tostring(status.running)
        .. " ticks=" .. tostring(status.ticks)
        .. " survivors=" .. table.concat(status.ids or {}, ","))
    for _, id in ipairs(status.ids or {}) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        if controller ~= nil then
            print("[KnoxSurvivors][DeveloperTools] " .. controller:status())
            if controller.recentFailureEvidence ~= nil then
                for index, failure in ipairs(controller:recentFailureEvidence()) do
                    print("[KnoxSurvivors][DeveloperTools] recent_failure id=" .. tostring(id)
                        .. " index=" .. tostring(index)
                        .. " tick=" .. tostring(failure.tick)
                        .. " reason=" .. tostring(failure.reason)
                        .. " state=" .. tostring(failure.state)
                        .. " decision=" .. tostring(failure.decision)
                        .. " retryAt=" .. tostring(failure.retryAt or "none")
                        .. " position=" .. tostring(failure.x or "none") .. ","
                        .. tostring(failure.y or "none") .. "," .. tostring(failure.z or "none"))
                end
            end
        end
    end
    KnoxActivityFeed.event("Developer status written to console.txt.")
end

function DeveloperTools.startPopulationProfile()
    local population = rawget(_G, "KnoxWorldPopulation")
    if population == nil or population.startPopulationProfileSample == nil then
        print("[KnoxSurvivors][PopulationProfile] status=unavailable reason=module_missing")
        return
    end
    local ok, result = population.startPopulationProfileSample()
    print("[KnoxSurvivors][PopulationProfile] status=" .. tostring(result)
        .. " action=" .. tostring(ok) .. " note=runtime_only_no_save_changes")
    KnoxActivityFeed.event("Population profile started; stops automatically after two minutes.")
end

function DeveloperTools.stopPopulationProfile()
    local population = rawget(_G, "KnoxWorldPopulation")
    if population == nil or population.stopPopulationProfileSample == nil then return end
    local ok, result = population.stopPopulationProfileSample()
    print("[KnoxSurvivors][PopulationProfile] status=" .. tostring(result)
        .. " action=" .. tostring(ok) .. " profiling=false")
    KnoxActivityFeed.event("Population profiling is off. The last sample remains available to write.")
end

local function printProfileMap(label, values)
    if type(values) ~= "table" then return end
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = values[key]
        if type(value) == "table" then
            value = "calls=" .. tostring(value.calls or 0)
                .. ",totalMs=" .. tostring(value.totalMs or 0)
                .. ",maxMs=" .. tostring(value.maxMs or 0)
        end
        print("[KnoxSurvivors][PopulationProfile] " .. tostring(label)
            .. " name=" .. key .. " value=" .. tostring(value))
    end
end

function DeveloperTools.writePopulationProfile()
    local population = rawget(_G, "KnoxWorldPopulation")
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    if population == nil or population.writePopulationProfile == nil then
        print("[KnoxSurvivors][PopulationProfile] status=unavailable reason=module_missing")
        return
    end
    local runtime = autonomy ~= nil and autonomy.status ~= nil and autonomy.status() or nil
    local bridge = rawget(_G, "KnoxJavaBridge")
    local ok, report = pcall(population.writePopulationProfile, bridge, runtime)
    if not ok or type(report) ~= "table" then
        print("[KnoxSurvivors][PopulationProfile] status=error reason=report_failed")
        return
    end
    local persistence = report.persistence or {}
    print("[KnoxSurvivors][PopulationProfile] status=report map=" .. tostring(report.map)
        .. " catalog=" .. tostring(report.catalogStatus)
        .. " configuredTarget=" .. tostring(report.target or "unavailable")
        .. " storedLastTarget=" .. tostring(persistence.storedPopulationLastTarget or "unavailable")
        .. " logicalRecords=" .. tostring(persistence.logicalPopulationRecords or "unavailable")
        .. " logicalLiving=" .. tostring(persistence.livingPopulation or "unavailable")
        .. " nativeBodies=" .. tostring(report.nativeActiveBodyCount or "unavailable")
        .. " nativeIdDuplicates=" .. tostring(report.nativeActiveDuplicateIds)
        .. " runtimeActiveIds=" .. tostring(report.runtimeActiveIdCount or "unavailable")
        .. " controllers=" .. tostring(report.controllerCount or "unavailable")
        .. " persistenceStatus=" .. tostring(report.persistenceStatus or "available")
        .. " luaHeapKB=" .. tostring(report.luaHeapKB or "unavailable"))
    local catalog = report.catalog or {}
    print("[KnoxSurvivors][PopulationProfile] catalog metadataStatus="
        .. tostring(catalog.buildingMetadataStatus or "unavailable")
        .. " buildingsScanned=" .. tostring(catalog.metadataBuildingsScanned or "unavailable")
        .. " buildingOriginsSelected=" .. tostring(catalog.buildingOriginsSelected or "unavailable")
        .. " origins=" .. tostring(catalog.catalogOrigins or "unavailable")
        .. " invalidSpawnPoints=" .. tostring(catalog.invalidSpawnPoints or "unavailable")
        .. " duplicateSpawnPoints=" .. tostring(catalog.duplicateSpawnPoints or "unavailable")
        .. " missingGroundRooms=" .. tostring(catalog.metadataBuildingsWithoutGroundRoom or "unavailable")
        .. " metadataReadFailures=" .. tostring(catalog.metadataBuildingReadFailures or "unavailable")
        .. " coverage=" .. tostring(catalog.classificationCoverage or "unavailable"))
    if report.sample ~= nil then
        local sample = report.sample
        print("[KnoxSurvivors][PopulationProfile] sample status=" .. tostring(sample.status)
            .. " active=" .. tostring(sample.active == true)
            .. " durationMs=" .. tostring(sample.durationMs or "unavailable")
            .. " clock=" .. tostring(sample.clock)
            .. " allocationsAttempted=" .. tostring(sample.allocationsAttempted)
            .. " allocationsSucceeded=" .. tostring(sample.allocationsSucceeded)
            .. " allocationsRejected=" .. tostring(sample.allocationsRejected)
            .. " activationBudget=" .. tostring(sample.activationBudget or "unavailable")
            .. " activationScannedIds=" .. tostring(sample.activationScannedIds)
            .. " activationCandidates=" .. tostring(sample.activationCandidates)
            .. " catalogBuilds=" .. tostring(sample.catalogBuilds)
            .. " activationsSucceeded=" .. tostring(sample.activationsSucceeded)
            .. " activationsFailed=" .. tostring(sample.activationsFailed))
        printProfileMap("timing", sample.timings)
        printProfileMap("activation_rejection", sample.activationRejections)
    else
        print("[KnoxSurvivors][PopulationProfile] sample status=not_started note=use_start_sample_then_report")
    end
    printProfileMap("building_context", catalog.buildingsByVerifiedContext)
    printProfileMap("building_category", catalog.buildingsByPopulationCategory)
    printProfileMap("persisted_origin_context", persistence.contexts)
    printProfileMap("persisted_origin_category", persistence.locationCategories)
    printProfileMap("unavailable_category", catalog.unavailableCategories)
    print("[KnoxSurvivors][PopulationProfile] limits diskWriteTiming=unavailable_moddata_create_is_not_disk_write"
        .. " nativeMemory=unavailable objectAllocationCount=unavailable"
        .. " catalogOrigins=" .. tostring(report.memoryObjectCounts.catalogOrigins or "unavailable")
        .. " candidateRows=" .. tostring(report.memoryObjectCounts.lastSampleCandidateRows or "unavailable")
        .. " noAllocatorOrMaterializerCalled=true")
    KnoxActivityFeed.event("Population profile written to console.txt.")
end

function DeveloperTools.printFactionReadiness()
    local seen={}
    for _,id in ipairs(KnoxPersistence.getActivatableSurvivorIds()) do
        local group=KnoxPersistence.getTravelGroupFor(id)
        if group~=nil and not seen[group.id] then
            seen[group.id]=true
            local status=KnoxPersistence.getFactionReadiness(group.id,KnoxSettings.npcFactionMinimumMembers())
            print("[KnoxSurvivors][DeveloperTools] group="..group.id
                .." faction="..tostring(status.factionId or "none")
                .." formation="..tostring(status.reason).." enabled="..tostring(KnoxSettings.allowNPCFactions())
                .." members="..status.members.." required="..status.required
                .." shared="..status.sharedMembers.." waitingFor="..table.concat(status.missingShared,","))
        end
    end
    KnoxActivityFeed.event("Faction formation status written to console.txt.")
end

-- Damage-state diagnostic: prints the ACTUAL protection flags and zombie
-- attack telemetry per active survivor. Shell overrides force several of
-- these false by design, so this distinguishes "protected" (no known writer
-- can do this) from "zombies not acquiring / not completing attacks".
function DeveloperTools.diagnoseDamage(playerNum)
    local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
    local bridge = rawget(_G, "KnoxJavaBridge")
    local status = nil
    pcall(function()
        if autonomy ~= nil and autonomy.status ~= nil then
            status = autonomy.status()
        end
    end)
    local player = nil
    pcall(function()
        if getSpecificPlayer ~= nil then player = getSpecificPlayer(playerNum) end
    end)
    local ids = status ~= nil and status.ids or {}
    print("[KnoxSurvivors][DeveloperTools] damage_diagnostic survivors=" .. tostring(#ids))
    for _, id in ipairs(ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        local character = controller ~= nil and controller.character or nil
        if character == nil then
            print("[KnoxSurvivors][DeveloperTools] id=" .. tostring(id) .. " no_loaded_body")
        else
            local function flag(method)
                local ok, value = pcall(function() return character[method](character) end)
                if not ok then return "error" end
                return tostring(value)
            end
            local health = "unknown"
            pcall(function()
                local damage = character:getBodyDamage()
                if damage ~= nil then health = tostring(damage:getHealth()) end
            end)
            print("[KnoxSurvivors][DeveloperTools] id=" .. tostring(id)
                .. " zombiesDontAttack=" .. flag("isZombiesDontAttack")
                .. " god=" .. flag("isGodMod")
                .. " invulnerable=" .. flag("isInvulnerable")
                .. " ghost=" .. flag("isGhostMode")
                .. " invisible=" .. flag("isInvisible")
                .. " health=" .. health)
            -- Nearest zombie attack telemetry through the existing bridge.
            local nearest, nearestDistance = nil, math.huge
            pcall(function()
                local cell = getCell ~= nil and getCell() or nil
                local zombies = cell ~= nil and cell:getZombieList() or nil
                local square = character:getCurrentSquare()
                if zombies ~= nil and square ~= nil then
                    for index = 0, zombies:size() - 1 do
                        local zombie = zombies:get(index)
                        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
                        if zombieSquare ~= nil and zombieSquare:getZ() == square:getZ() then
                            local distance = (zombieSquare:getX() - square:getX()) ^ 2
                                + (zombieSquare:getY() - square:getY()) ^ 2
                            if distance < nearestDistance then
                                nearest, nearestDistance = zombie, distance
                            end
                        end
                    end
                end
            end)
            if nearest ~= nil and nearestDistance <= 100 then
                local target = "unknown"
                pcall(function()
                    local current = nearest:getTarget()
                    target = current == nil and "none"
                        or (current == character and "this_survivor" or "other")
                end)
                print("[KnoxSurvivors][DeveloperTools] id=" .. tostring(id)
                    .. " nearestZombie distance=" .. string.format("%.2f", math.sqrt(nearestDistance))
                    .. " target=" .. target)
                if bridge ~= nil and bridge.zombieAttackDiagnostics ~= nil then
                    local ok, report = pcall(function()
                        return bridge:zombieAttackDiagnostics(id, nearest)
                    end)
                    print("[KnoxSurvivors][DeveloperTools] id=" .. tostring(id)
                        .. " attackDiagnostics=" .. tostring(ok and report or "unavailable"))
                end
            else
                print("[KnoxSurvivors][DeveloperTools] id=" .. tostring(id)
                    .. " no_zombie_within_10_tiles")
            end
        end
    end
    KnoxActivityFeed.event("Damage diagnostics written to console.txt.")
end

function DeveloperTools.dispatchScout(playerNum, worldObjects)
    local square = worldObjects ~= nil and worldObjects[1] ~= nil
        and worldObjects[1]:getSquare() or nil
    local player = getSpecificPlayer(playerNum)
    local success, result = KnoxSurvivorAutonomy.dispatchDeveloperScout(player, square)
    KnoxActivityFeed.event(success and ("Faction scout team departed: " .. tostring(result) .. ".")
        or ("Scout dispatch failed: " .. tostring(result) .. "."))
end

function DeveloperTools.scheduleEligibleRaid()
    if KnoxSettings.enableKnoxEvents ~= nil and not KnoxSettings.enableKnoxEvents() then
        KnoxActivityFeed.event("Knox Events are disabled in Sandbox settings.")
        return
    end
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event("Raid test requires Allow Destructive Tests.")
        return
    end
    local hours = getGameTime():getWorldAgeHours()
    local event, result = KnoxEvents.scheduleAutomaticRaid(hours, true, 0, 1, true)
    KnoxActivityFeed.event(event ~= nil
        and ("Faction raid scheduled: " .. tostring(event.id) .. ".")
        or ("Raid scheduling failed: " .. tostring(result) .. "."))
    print("[KnoxSurvivors][DeveloperTools] raid=" .. tostring(event ~= nil and event.id or "none")
        .. " result=" .. tostring(result))
end

local function scheduleNamedEntry(worldObjects, policyId, objectiveKind, partySize, label)
    if KnoxSettings.enableKnoxEvents ~= nil and not KnoxSettings.enableKnoxEvents() then
        KnoxActivityFeed.event("Knox Events are disabled in Sandbox settings.")
        return
    end
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event(label .. " entry test requires Allow Destructive Tests.")
        return
    end
    local object = worldObjects ~= nil and worldObjects[1] or nil
    local square = object ~= nil and object:getSquare() or nil
    if square == nil then
        KnoxActivityFeed.event(label .. " entry scheduling failed: no target square.")
        return
    end
    local hours = getGameTime():getWorldAgeHours()
    local event, result = KnoxEvents.scheduleFactionEntry(policyId, objectiveKind, {
        x = square:getX(), y = square:getY(), z = square:getZ(),
    }, partySize, hours, 0)
    KnoxActivityFeed.event(event ~= nil
        and (label .. " Knox Event scheduled: " .. tostring(event.id) .. ".")
        or (label .. " entry scheduling failed: " .. tostring(result) .. "."))
    print("[KnoxSurvivors][DeveloperTools] namedEntry=" .. tostring(policyId)
        .. " event="
        .. tostring(event ~= nil and event.id or "none") .. " result=" .. tostring(result))
end

function DeveloperTools.schedulePoliceEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "police", "secure_area", 3, "Police")
end

function DeveloperTools.scheduleScientistsEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "scientists", "research", 2, "Scientists")
end

function DeveloperTools.scheduleMilitaryEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "military", "secure_area", 3, "Military")
end

function DeveloperTools.scheduleScavengerEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "scavengers", "scavenge_world", 3, "Scavengers")
end

function DeveloperTools.stockJobTests(playerNum)
    local actor = getSpecificPlayer(playerNum)
    local manager = rawget(_G, "KnoxBaseManager")
    local service = rawget(_G, "KnoxCompanionService")
    local owner = actor ~= nil and service ~= nil and service.getPlayerId(actor) or nil
    local base = owner ~= nil and manager ~= nil and manager.getForOwner("player", owner) or nil
    local added, result = KnoxJobTestSupplies.ensure(base, actor, true)
    KnoxActivityFeed.event("Job test supplies: " .. tostring(result) .. " (" .. tostring(added) .. " items added).")
end

function DeveloperTools.runJobTest(playerNum, key, worldObjects)
    local scenarios = rawget(_G, "KnoxJobTestScenarios")
    if scenarios == nil or scenarios.run == nil then
        KnoxActivityFeed.event("Job test scenarios unavailable.")
        return
    end
    scenarios.run(playerNum, key, worldObjects)
end

-- Calm test scene: clears zombies around the player for undisturbed job
-- testing. Sandbox populations cannot change at runtime, so pair this with
-- a zero-population sandbox preset for a fully quiet world; this handles
-- the zombies already on the map.
function DeveloperTools.calmTestScene(playerNum)
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event("Clearing nearby zombies requires Allow Destructive Tests.")
        return
    end
    local player = getSpecificPlayer(playerNum)
    local origin = player ~= nil and player:getCurrentSquare() or nil
    local cell = getCell ~= nil and getCell() or nil
    local removed = 0
    if origin ~= nil and cell ~= nil then
        local radius = 40
        local zone = origin:getZ()
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = cell:getGridSquare(
                    origin:getX() + dx, origin:getY() + dy, zone)
                if square ~= nil and square.getMovingObjects ~= nil then
                    local ok, moving = pcall(function()
                        return square:getMovingObjects()
                    end)
                    if ok and moving ~= nil then
                        for index = moving:size() - 1, 0, -1 do
                            local object = moving:get(index)
                            local isZombie = false
                            pcall(function()
                                if instanceof ~= nil then
                                    isZombie = instanceof(object, "IsoZombie") == true
                                elseif object.isZombie ~= nil then
                                    isZombie = object:isZombie() == true
                                end
                            end)
                            if isZombie then
                                local cleared=pcall(function()
                                    object:setTarget(nil)
                                    object:setUseless(true)
                                    object:setCanWalk(false)
                                    object:removeFromWorld()
                                    object:removeFromSquare()
                                end)
                                if cleared then removed = removed + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    KnoxActivityFeed.event("Calm test scene: cleared " .. tostring(removed)
        .. " zombies within 40 tiles. Enable Ignore Job Resource Requirements for job runs.")
    print("[KnoxSurvivors][DeveloperTools] calm-scene removed=" .. tostring(removed))
end

local function onFill(playerNum, context, worldObjects, test)
    if not KnoxSettings.developerToolsEnabled() then
        return
    end
    if test then
        if ISWorldObjectContextMenu.Test then
            return true
        end
        return ISWorldObjectContextMenu.setTest()
    end
    local rootOption = context:addOption("Knox Survivors - Developer Tools", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)

    local populationOption = menu:addOption("Spawn Survivors, Groups & Factions", nil, nil)
    local populationMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(populationOption, populationMenu)
    for _, definition in ipairs(SCENARIOS) do
        if definition[2]~="group" and definition[2]~="faction" and definition[2]~="faction_base" then
            populationMenu:addOption(definition[1], playerNum, DeveloperTools.spawn, definition[2],worldObjects)
        else
            local option=populationMenu:addOption(definition[1],nil,nil)
            local sizes=ISContextMenu:getNew(populationMenu)
            populationMenu:addSubMenu(option,sizes)
            local minimum=definition[2]=="group" and 2 or KnoxSettings.npcFactionMinimumMembers()
            local maximum=definition[2]=="group" and 12 or KnoxSettings.npcFactionMaxMembers()
            for size=minimum,maximum do
                sizes:addOption(tostring(size).." survivors",playerNum,DeveloperTools.spawn,
                    definition[2],worldObjects,size)
            end
        end
    end
    populationMenu:addOption("Remove Last Spawn (Test Survivors Only)",nil,DeveloperTools.cleanupLastSpawn)

    local jobsOption = menu:addOption("Base & Job Tests", nil, nil)
    local jobsMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(jobsOption, jobsMenu)
    local stock = jobsMenu:addOption("Stock Assigned Storage for Job Tests", playerNum, DeveloperTools.stockJobTests)
    stock.notAvailable = not KnoxSettings.ignoreJobResourceRequirements()
    local scenarios = rawget(_G, "KnoxJobTestScenarios")
    if scenarios ~= nil and scenarios.list ~= nil then
        local jobOption=jobsMenu:addOption("Run a Job Scenario",nil,nil)
        local jobMenu=ISContextMenu:getNew(jobsMenu)
        jobsMenu:addSubMenu(jobOption,jobMenu)
        for _, definition in ipairs(scenarios.list()) do
            jobMenu:addOption(definition.label, playerNum, DeveloperTools.runJobTest,
                definition.key, worldObjects)
        end
    end

    local combatOption = menu:addOption("Combat Tests", nil, nil)
    local combatMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(combatOption, combatMenu)
    for _, definition in ipairs(COMBAT_SCENARIOS) do
        combatMenu:addOption(definition[1], playerNum, KnoxCombatTestScenarios.start, definition[2])
    end
    combatMenu:addOption("Write Combat Snapshot to Log", nil, KnoxCombatTestScenarios.writeSnapshot)
    combatMenu:addOption("Cleanup Combat Test", nil, KnoxCombatTestScenarios.cleanup)

    local worldOption = menu:addOption("Faction & World Events (Experimental)", nil, nil)
    local worldMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(worldOption, worldMenu)
    worldMenu:addOption("Dispatch Loaded Faction Scout Here", playerNum,
        DeveloperTools.dispatchScout, worldObjects)

    if KnoxSettings.allowDestructiveDeveloperTests() then
        local destructiveOption = worldMenu:addOption("Destructive Tests", nil, nil)
        local destructiveMenu = ISContextMenu:getNew(worldMenu)
        worldMenu:addSubMenu(destructiveOption, destructiveMenu)
        destructiveMenu:addOption("Calm Test Scene (Clear Zombies Nearby)",playerNum,DeveloperTools.calmTestScene)
        destructiveMenu:addOption("Schedule Eligible Faction Raid Now", nil,
            DeveloperTools.scheduleEligibleRaid)
        destructiveMenu:addOption("Schedule Police Entry Here", playerNum,
            DeveloperTools.schedulePoliceEntry, worldObjects)
        destructiveMenu:addOption("Schedule Scientists Entry Here", playerNum,
            DeveloperTools.scheduleScientistsEntry, worldObjects)
        destructiveMenu:addOption("Schedule Military Entry Here", playerNum,
            DeveloperTools.scheduleMilitaryEntry, worldObjects)
        destructiveMenu:addOption("Schedule Scavenger Search Here", playerNum,
            DeveloperTools.scheduleScavengerEntry, worldObjects)
    end

    local diagnosticsOption = menu:addOption("Diagnostics", nil, nil)
    local diagnosticsMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(diagnosticsOption, diagnosticsMenu)
    diagnosticsMenu:addOption("Write Survivor Status to Log", nil, DeveloperTools.printStatus)
    diagnosticsMenu:addOption("Write Faction Formation Status to Log",nil,DeveloperTools.printFactionReadiness)
    diagnosticsMenu:addOption("Write Sandbox Settings to Log",nil,DeveloperTools.writeSettings)
    diagnosticsMenu:addOption("Diagnose Survivor Damage State", playerNum, DeveloperTools.diagnoseDamage)
    diagnosticsMenu:addOption("Start Population Profile Sample", nil,
        DeveloperTools.startPopulationProfile)
    diagnosticsMenu:addOption("Stop Population Profile Sample", nil,
        DeveloperTools.stopPopulationProfile)
    diagnosticsMenu:addOption("Write Population & Location Profile", nil,
        DeveloperTools.writePopulationProfile)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

return DeveloperTools
