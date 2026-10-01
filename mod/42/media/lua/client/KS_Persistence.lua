-- Normal game loading resolves the pure origin policy through require. A few
-- persistence-only offline harnesses execute this file directly without a Lua
-- module path; fail closed there and let missing legacy metadata remain absent.
if rawget(_G, "KnoxSurvivorOrigins") == nil then
    pcall(require, "KS_SurvivorOrigins")
end

local KnoxPersistence = rawget(_G, "KnoxPersistence") or {}
_G.KnoxPersistence = KnoxPersistence

-- Kept separate from the legacy IsoZombie mod data that may exist in reused saves.
local MOD_DATA_KEY = "KnoxSurvivors_IsoPlayer"
local SCHEMA_VERSION = 19
local TEST_SURVIVOR_ID = "ks-test-1"

local WORK_PREFERENCE_GROUPS = {
    guard = true, patrol = true, repair = true, cooking = true,
    farming = true, woodwork = true, barricade = true, hauling = true,
}
local WORK_PREFERENCE_STATES = {
    high = true, normal = true, low = true, disabled = true,
}

local function normalizeWorkPreference(value)
    if value == false then return "disabled" end
    local number = tonumber(value)
    if number ~= nil then
        if number == 1 then return "high" end
        if number == 2 then return "normal" end
        if number == 3 or number == 4 then return "low" end
        return nil
    end
    if type(value) ~= "string" then return nil end
    local state = string.lower(value)
    return WORK_PREFERENCE_STATES[state] and state or nil
end

local function normalizeWorkPreferences(map)
    if type(map) ~= "table" then return nil end
    local normalized = {}
    local hasPreference = false
    for key, value in pairs(map) do
        if WORK_PREFERENCE_GROUPS[key] == true then
            local state = normalizeWorkPreference(value)
            if state ~= nil and state ~= "normal" then
                normalized[key] = state
                hasPreference = true
            end
        end
    end
    -- Project Zomboid's Kahlua environment does not expose Lua's global
    -- `next`; preference writes from the Notebook must use supported pairs.
    return hasPreference and normalized or nil
end

local function sanitizeOriginMetadata(origin, preserveMissing)
    local policy = rawget(_G, "KnoxSurvivorOrigins")
    if policy ~= nil and policy.sanitizeMetadata ~= nil then
        return policy.sanitizeMetadata(origin, preserveMissing)
    end
    local hasMetadata = type(origin) == "table" and (origin.context ~= nil
        or origin.professionCandidates ~= nil or origin.buildingId ~= nil)
    if preserveMissing and not hasMetadata then return {} end
    return { context = "generic" }
end

-- root() is used by nearly every persistence accessor, including hot autonomy
-- and combat decisions. Normalizing every survivor/base/task on every read
-- turns those accessors into full-world scans. Cache only the completed
-- normalization for the exact ModData graph; replacing any authoritative
-- domain table (as happens on world/load changes) invalidates the cache.
local normalizedRootCache = nil

local function invalidateNormalizedRoot()
    normalizedRootCache = nil
end

local function rootCacheMatches(data)
    local cached = normalizedRootCache
    return cached ~= nil and cached.data == data
        and cached.schemaVersion == tonumber(data.schemaVersion)
        and cached.schemaVersion == SCHEMA_VERSION
        and cached.survivors == data.survivors
        and cached.relationships == data.relationships
        and cached.travelGroups == data.travelGroups
        and cached.factions == data.factions
        and cached.factionRelationships == data.factionRelationships
        and cached.bases == data.bases
        and cached.camps == data.camps
        and cached.awayTeams == data.awayTeams
        and cached.players == data.players
        and cached.population == data.population
        and cached.knoxEvents == data.knoxEvents
end

local function rememberNormalizedRoot(data)
    normalizedRootCache = {
        data = data,
        schemaVersion = tonumber(data.schemaVersion),
        survivors = data.survivors,
        relationships = data.relationships,
        travelGroups = data.travelGroups,
        factions = data.factions,
        factionRelationships = data.factionRelationships,
        bases = data.bases,
        camps = data.camps,
        awayTeams = data.awayTeams,
        players = data.players,
        population = data.population,
        knoxEvents = data.knoxEvents,
    }
end

-- Persistence is loaded early in some Build 42 mod-load orders, so keep a
-- small local compatibility map in addition to the catalogue helper. This
-- normalizes only stored task vocabulary; executors remain Knox-owned.
local LEGACY_TASK_TYPES = {
    haul = "haul_corpse", storage_sorting = "sort_depot", sort_loot = "sort_depot",
    corpse = "haul_corpse", corpse_cleanup = "haul_corpse",
    woodcutting = "chop_tree", wood_processing = "saw_logs",
    log_processing = "saw_logs", farming = "farm_seed",
    construction = "construct_defense", defense = "construct_defense",
    patrol_area = "patrol",
    maintenance = "repair",
}

-- Duty records can outlive the menu that created them. Keep the migration
-- boundary able to understand familiar labels even when the order catalogue
-- has not loaded yet. These are aliases only; execution still belongs to the
-- existing companion/controller owners.
local LEGACY_ORDER_ALIASES = {
    explore = "loot_area", search = "loot_area", loot = "loot_area",
    forage = "loot_area", loot_room = "loot_building",
    go_find_food = "find_food", go_find_water = "find_water",
    go_find_weapon = "find_weapon", go_find_medical = "find_medical",
    go_find_tools = "find_tools", doctor = "find_medical",
    stand_ground = "hold", hold_still = "hold", defend = "guard",
    escort = "follow", stop = "resume_normal_duty",
    stay = "hold", wait = "hold", hold_position = "hold",
    return_home = "return_to_base", go_home = "return_to_base",
    ["return"] = "return_to_base",
    recover = "relax", rest = "relax", rest_recover = "relax",
    sort_loot_into_base = "clean_inventory", search_area = "loot_area",
    search_building = "loot_building", chop_wood = "woodwork",
    loot_dead_bodies = "loot_corpses", loot_bodies = "loot_corpses",
    get_food = "find_food", get_water = "find_water",
    get_meds = "find_medical", get_medical = "find_medical",
    get_weapon = "find_weapon", get_tools = "find_tools",
    guard_area = "guard", patrol = "patrol_area",
    go_to_base = "return_to_base", cancel_order = "resume_normal_duty",
    cancel = "resume_normal_duty",
    pile_corpses = "hauling", barricade = "woodwork",
    farming = "farming", woodcutting = "woodwork",
    storage_sorting = "hauling", corpse_cleanup = "hauling",
}

local function canonicalTaskType(value)
    if type(value) ~= "string" or value == "" then return value end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        local normalized = catalog.normalizeTaskType(value)
        if normalized ~= nil then return normalized end
    end
    return LEGACY_TASK_TYPES[value] or value
end

local function canonicalOrder(value)
    if type(value) ~= "string" or value == "" then return value end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalize ~= nil then
        local normalized = catalog.normalize(value)
        if normalized ~= nil then return normalized end
    end
    return LEGACY_ORDER_ALIASES[value] or value
end

local LIFE_INTENT_KINDS = {
    find_food = true,
    find_water = true,
    find_medical = true,
    find_weapon = true,
    find_tools = true,
    base_supply_deposit = true,
    scavenge = true,
    investigate_building = true,
    travel_area = true,
    night_shelter = true,
}

-- Explicit base supply runs use the resident's existing duty record.  This is
-- deliberately separate from companion directives: a base resident must keep
-- the request through reload without becoming a travelling companion.
local BASE_SUPPLY_ORDER_KINDS = {
    find_food = true,
    find_water = true,
    find_medical = true,
    find_weapon = true,
    find_tools = true,
    find_wood = true,
    find_materials = true,
    find_clothing = true,
    find_ammo = true,
}

local LIFE_INTENT_PHASES = {
    seeking = true,
    traveling = true,
    arrived = true,
    reassess = true,
    returning = true,
}

local FACTION_NAME_STYLES = {
    function(name) return "The " .. name .. " Group" end,
    function(name) return name .. "'s People" end,
    function(name) return "The " .. name .. " Crew" end,
    function(name) return name .. "'s Outfit" end,
}

local function stableFactionName(data, factionId, faction)
    if faction ~= nil and type(faction.name) == "string" and faction.name ~= "" then
        return faction.name
    end
    if faction ~= nil and faction.kind == "player" then return "Your Group" end
    local identity = faction ~= nil and faction.leaderId ~= nil
        and data.survivors[faction.leaderId] ~= nil
        and data.survivors[faction.leaderId].identity or nil
    local leaderName = identity ~= nil and tostring(identity.surname or "") or ""
    if leaderName == "" and identity ~= nil then leaderName = tostring(identity.forename or "") end
    if leaderName == "" then
        return "Survivor Group " .. tostring((tostring(factionId):match("(%d+)$")) or "")
    end
    local hash = 0
    for index = 1, #tostring(factionId) do
        hash = (hash * 31 + string.byte(tostring(factionId), index)) % 2147483647
    end
    return FACTION_NAME_STYLES[(hash % #FACTION_NAME_STYLES) + 1](leaderName)
end

-- Generated names should read naturally, but two groups led by people with
-- the same surname must still be distinguishable in the notebook, activity
-- feed, and safehouse title. Preserve an existing name and only suffix a new
-- collision; player- or event-supplied names never pass through this helper.
local function uniqueFactionName(data, factionId, faction)
    local baseName = stableFactionName(data, factionId, faction)
    local candidate = baseName
    local suffix = 2
    local function taken(name)
        for existingId, existing in pairs(data.factions or {}) do
            if existingId ~= factionId and type(existing) == "table"
                and tostring(existing.name or "") == name then
                return true
            end
        end
        return false
    end
    while taken(candidate) do
        candidate = baseName .. " " .. tostring(suffix)
        suffix = suffix + 1
    end
    return candidate
end

-- Companion directives originate from UI ground selections and survive save/load.
-- Keep their validation at the persistence boundary so a corrupted or stale
-- selection cannot become a permanent controller command after restoration.
local function finiteCoordinate(value)
    value = tonumber(value)
    return value ~= nil and value == value and math.abs(value) <= 1000000
end

local function validLifeIntent(intent)
    if type(intent) ~= "table"
        or LIFE_INTENT_KINDS[tostring(intent.kind or "")] ~= true
        or LIFE_INTENT_PHASES[tostring(intent.phase or "")] ~= true then
        return false
    end
    if intent.targetX ~= nil and not finiteCoordinate(intent.targetX) then return false end
    if intent.targetY ~= nil and not finiteCoordinate(intent.targetY) then return false end
    if intent.targetZ ~= nil and not finiteCoordinate(intent.targetZ) then return false end
    return intent.targetKey == nil or type(intent.targetKey) == "string"
end

local function sameLifeIntent(first, second)
    if first == nil or second == nil then return first == second end
    return first.kind == second.kind
        and first.phase == second.phase
        and first.targetKey == second.targetKey
        and first.targetX == second.targetX
        and first.targetY == second.targetY
        and first.targetZ == second.targetZ
end

function KnoxPersistence.isValidCompanionDirective(directive)
    if type(directive) ~= "table" then
        return false
    end
    local kind = tostring(directive.kind or "")
    if kind ~= "loot_area" and kind ~= "loot_building"
        and kind ~= "loot_corpses" and kind ~= "go_to" and kind ~= "guard"
        and kind ~= "find_food" and kind ~= "find_water"
        and kind ~= "find_medical" and kind ~= "find_weapon"
        and kind ~= "find_tools"
        and kind ~= "patrol_area"
        and kind ~= "clean_inventory" then
        return false
    end
    local minX, minY = tonumber(directive.minX), tonumber(directive.minY)
    local maxX = tonumber(directive.maxX) or minX
    local maxY = tonumber(directive.maxY) or minY
    local z = tonumber(directive.z) or 0
    return finiteCoordinate(minX) and finiteCoordinate(minY)
        and finiteCoordinate(maxX) and finiteCoordinate(maxY) and finiteCoordinate(z)
        and minX <= maxX and minY <= maxY
end

-- Forward declarations for migration backup (defined fully below).
local copySerializable
local backupOnce

-- Recovery snapshots must retain nested history/directives and every domain.
-- The bounded public DTO copier below is deliberately unsuitable for backups.
-- Skip cycles and engine objects; only primitive-keyed serializable trees belong
-- in ModData. Track ancestors rather than all seen tables to retain aliases.
local function copyRecoveryTree(source, ancestors)
    local kind = type(source)
    if kind ~= "table" then
        if kind == "string" or kind == "number" or kind == "boolean" then return source end
        return nil
    end
    ancestors = ancestors or {}
    if ancestors[source] then return nil end
    ancestors[source] = true
    local result = {}
    for key, value in pairs(source) do
        if type(key) == "string" or type(key) == "number" then
            result[key] = copyRecoveryTree(value, ancestors)
        end
    end
    ancestors[source] = nil
    return result
end

local function root()
    local data = ModData.getOrCreate(MOD_DATA_KEY)
    if rootCacheMatches(data) then return data end
    local previousVersion = tonumber(data.schemaVersion) or 0
    -- Backup once before any migration mutates old save data, so a failed or
    -- lossy migration never destroys the original tables.
    if previousVersion < SCHEMA_VERSION and data.preMigrationBackup == nil then
        local snapshot = copyRecoveryTree(data)
        data.preMigrationBackup = {
            fromSchema = previousVersion,
            toSchema = SCHEMA_VERSION,
            snapshot = snapshot,
            version = 2,
        }
    end
    if type(data.survivors) ~= "table" then
        data.survivors = {}
    end
    if type(data.relationships) ~= "table" then
        data.relationships = {}
    end
    if type(data.travelGroups) ~= "table" then
        data.travelGroups = {}
    end
    data.nextTravelGroupId = data.nextTravelGroupId or 1
    if type(data.factions) ~= "table" then
        data.factions = {}
    end
    -- Faction disposition is deliberately a separate, symmetric domain.  A
    -- survivor's affiliation answers "who owns this person"; this table
    -- answers "how do those two owners relate".  Keeping that boundary avoids
    -- turning a single encounter flag into permanent base-damage permission.
    if type(data.factionRelationships) ~= "table" then
        data.factionRelationships = {}
    end
    data.nextFactionId = data.nextFactionId or 1
    if type(data.camps) ~= "table" then
        data.camps = {}
    end
    data.nextCampId = tonumber(data.nextCampId) or 1
    if type(data.awayTeams) ~= "table" then
        data.awayTeams = {}
    end
    data.nextAwayTeamId = tonumber(data.nextAwayTeamId) or 1
    if type(data.knoxEvents) ~= "table" then data.knoxEvents = {} end
    if type(data.knoxEvents.records) ~= "table" then data.knoxEvents.records = {} end
    if type(data.knoxEvents.cooldowns) ~= "table" then data.knoxEvents.cooldowns = {} end
    if type(data.knoxEvents.automatic) ~= "table" then data.knoxEvents.automatic = {} end
    local automaticNext = tonumber(data.knoxEvents.automatic.nextCheckHours)
    local automaticCursor = tonumber(data.knoxEvents.automatic.cursor)
    data.knoxEvents.automatic.nextCheckHours = finiteCoordinate(automaticNext)
        and automaticNext >= 0 and automaticNext or 0
    data.knoxEvents.automatic.cursor = finiteCoordinate(automaticCursor)
        and automaticCursor >= 0 and math.floor(automaticCursor) or 0
    local entryNext = tonumber(data.knoxEvents.automatic.entryNextCheckHours)
    local entryCursor = tonumber(data.knoxEvents.automatic.entryCursor)
    data.knoxEvents.automatic.entryNextCheckHours = finiteCoordinate(entryNext)
        and entryNext >= 0 and entryNext or 0
    data.knoxEvents.automatic.entryCursor = finiteCoordinate(entryCursor)
        and entryCursor >= 0 and math.floor(entryCursor) or 0
    data.knoxEvents.nextId = tonumber(data.knoxEvents.nextId) or 1
    if type(data.players) ~= "table" then
        data.players = {}
    end
    data.nextPlayerId = data.nextPlayerId or 1
    data.nextDeveloperSurvivorId = data.nextDeveloperSurvivorId or 1
    data.nextWorldSurvivorId = data.nextWorldSurvivorId or 1
    if type(data.population) ~= "table" then
        data.population = {}
    end
    data.population.initialized = data.population.initialized == true
    data.population.nextRefillHours = tonumber(data.population.nextRefillHours) or 0
    data.population.lastTarget = tonumber(data.population.lastTarget) or 0
    data.population.belowTargetSinceHours = tonumber(
        data.population.belowTargetSinceHours
    )
    data.population.allocationCursor = math.max(
        0,
        math.floor(tonumber(data.population.allocationCursor) or 0)
    )
    if type(data.bases) ~= "table" then
        data.bases = {}
    end
    data.nextBaseId = data.nextBaseId or 1
    for _, base in pairs(data.bases) do
        if type(base) == "table" then
            -- Development builds briefly stored loaded-controller supply
            -- leases on the durable base record. They identify no world state
            -- and expire in runtime ticks, so never serialize or restore them.
            base.supplySearchClaims = nil
            base.zones = type(base.zones) == "table" and base.zones or {}
            base.nextZoneId = tonumber(base.nextZoneId) or 1
            -- Construction areas were removed: drop retired zones so they stop
            -- rendering and scheduling.
            for zoneId, zone in pairs(base.zones) do
                if type(zone) == "table"
                    and (zone.type == "construction" or zone.type == "defense") then
                    base.zones[zoneId] = nil
                end
            end
            base.storage = type(base.storage) == "table" and base.storage or {}
            base.tasks = type(base.tasks) == "table" and base.tasks or {}
            base.nextTaskId = tonumber(base.nextTaskId) or 1
            for _, task in pairs(base.tasks) do
                if type(task) == "table" then
                    local originalType = task.type
                    if task.typeBeforeMigration == nil then
                        task.typeBeforeMigration = originalType
                    end
                    task.type = canonicalTaskType(task.type)
                    -- Animal care retired (vanilla zones later): retire stale
                    -- animal records so they cannot be claimed.
                    if task.type == "animal_care" or task.type == "animal_water"
                        or task.type == "animal_feed" then
                        task.state = "cancelled"
                        task.result = "animal_care_retired"
                        task.claimedBy = nil
                        task.claimedAtHours = nil
                        task.retryAtHours = nil
                        task.manual = nil
                        task.auto = nil
                    end
                    -- Construction retired: retire stale records so they cannot
                    -- be claimed.
                    if task.type == "construct_defense" then
                        task.state = "cancelled"
                        task.result = "construction_retired"
                        task.claimedBy = nil
                        task.claimedAtHours = nil
                        task.retryAtHours = nil
                        task.manual = nil
                        task.auto = nil
                    end
                    if task.type ~= originalType and type(task.signature) == "string" then
                        local separator = string.find(task.signature, ":", 1, true)
                        local targetSignature = separator ~= nil
                            and string.sub(task.signature, separator + 1) or ""
                        task.signature = tostring(task.type) .. ":" .. targetSignature
                    end
                    task.priority = math.max(0, math.min(100, tonumber(task.priority) or 50))
                    task.basePriority = tonumber(task.basePriority) or task.priority
                    task.attempts = math.max(0, math.floor(tonumber(task.attempts) or 0))
                    task.failureStreak = math.max(0, math.min(6,
                        math.floor(tonumber(task.failureStreak) or 0)))
                    if task.retryAtHours ~= nil then
                        task.retryAtHours = math.max(0, tonumber(task.retryAtHours) or 0)
                    end
                    if task.lastClaimedAtHours ~= nil then
                        task.lastClaimedAtHours = math.max(0,
                            tonumber(task.lastClaimedAtHours) or 0)
                    end
                    if task.offscreenWorkHours ~= nil then
                        task.offscreenWorkHours = math.max(0,
                            tonumber(task.offscreenWorkHours) or 0)
                    end
                    if task.offscreenShiftsCompleted ~= nil then
                        task.offscreenShiftsCompleted = math.max(0, math.min(1000000,
                            math.floor(tonumber(task.offscreenShiftsCompleted) or 0)))
                    end
                    if task.guardReliefCount ~= nil then
                        task.guardReliefCount = math.max(0, math.min(1000000,
                            math.floor(tonumber(task.guardReliefCount) or 0)))
                    end
                    if task.type == "patrol" then
                        -- Do not fold persisted progress against a hard-coded
                        -- four-point rectangle here.  Patrol.waypoints derives
                        -- the actual route from the saved area at runtime; a
                        -- migrated/custom area may have a different number of
                        -- distinct standable points.  Keep the progress as a
                        -- bounded counter and let the route owner normalize it
                        -- against its real point count when it is consumed.
                        task.patrolStep = math.max(0,
                            math.min(1000000, math.floor(tonumber(task.patrolStep) or 0)))
                        task.patrolStopsCompleted = math.max(0, math.min(1000000,
                            math.floor(tonumber(task.patrolStopsCompleted) or 0)))
                    else
                        task.patrolStep = nil
                        task.patrolStopsCompleted = nil
                    end
                end
            end
            base.settings = type(base.settings) == "table" and base.settings or {}
            if base.settings.automaticJobs == nil then
                base.settings.automaticJobs = true
            end
            if base.settings.allowWorkOutsideHome == nil then
                base.settings.allowWorkOutsideHome = true
            end
        end
    end
    if data.domainV7Migrated ~= true then
        -- Older saves inferred membership from travel groups and faction copies.
        -- Materialize that ownership once so recruitment can never mistake an
        -- established faction member for an independent survivor.
        for factionId, faction in pairs(data.factions) do
            if type(faction) == "table" then
                faction.kind = faction.kind or "npc"
                faction.memberIds = faction.memberIds or {}
                for _, survivorId in ipairs(faction.memberIds) do
                    local survivor = data.survivors[survivorId] or { id = survivorId }
                    survivor.affiliation = {
                        kind = faction.kind == "player" and "player" or "faction",
                        ownerId = faction.ownerPlayerId,
                        factionId = factionId,
                        migratedAtSchema = 7,
                    }
                    survivor.duty = survivor.duty or {
                        mode = faction.kind == "player" and "companion" or "autonomous",
                        order = faction.kind == "player" and "follow" or "survive",
                        ownerId = faction.ownerPlayerId,
                        revision = 0,
                    }
                    survivor.playerRelationships = survivor.playerRelationships or {}
                    data.survivors[survivorId] = survivor
                end
            end
        end
        for _, group in pairs(data.travelGroups) do
            local faction = type(group) == "table" and group.factionId ~= nil
                and data.factions[group.factionId]
                or nil
            if faction ~= nil then
                faction.memberIds = faction.memberIds or {}
                for _, survivorId in ipairs(group.memberIds or {}) do
                    local found = false
                    for _, memberId in ipairs(faction.memberIds) do
                        if memberId == survivorId then
                            found = true
                            break
                        end
                    end
                    if not found then
                        faction.memberIds[#faction.memberIds + 1] = survivorId
                    end
                    local survivor = data.survivors[survivorId] or { id = survivorId }
                    survivor.affiliation = {
                        kind = faction.kind == "player" and "player" or "faction",
                        ownerId = faction.kind == "player" and faction.ownerPlayerId or nil,
                        factionId = faction.id,
                        migratedAtSchema = 7,
                    }
                    survivor.duty = survivor.duty or {
                        mode = faction.kind == "player" and "companion" or "autonomous",
                        order = faction.kind == "player" and "follow" or "survive",
                        ownerId = faction.kind == "player" and faction.ownerPlayerId or nil,
                        revision = 0,
                    }
                    survivor.playerRelationships = survivor.playerRelationships or {}
                    data.survivors[survivorId] = survivor
                end
                table.sort(faction.memberIds)
            end
        end
        data.domainV7Migrated = true
    end
    -- Names are saved once so a faction keeps its identity even if leadership
    -- changes later. Existing saves receive a deterministic name on migration.
    for factionId, faction in pairs(data.factions) do
        if type(faction) == "table" and (type(faction.name) ~= "string" or faction.name == "") then
            faction.name = stableFactionName(data, factionId, faction)
        end
        local eventIdentity = type(faction) == "table" and faction.eventIdentity or nil
        if eventIdentity ~= nil and (type(eventIdentity) ~= "table"
            or type(eventIdentity.policyId) ~= "string" or eventIdentity.policyId == ""
            or type(eventIdentity.sourceEventId) ~= "string" or eventIdentity.sourceEventId == ""
            or (eventIdentity.basePolicy ~= "event_only" and eventIdentity.basePolicy ~= "optional")
            or not finiteCoordinate(eventIdentity.boundAtHours)
            or eventIdentity.boundAtHours < 0) then
            faction.eventIdentity = nil
        end
    end
    for _, survivor in pairs(data.survivors) do
        if type(survivor) == "table" then
            if type(survivor.origin) == "table" then
                local metadata = sanitizeOriginMetadata(
                    survivor.origin,
                    true
                )
                survivor.origin.context = metadata.context
                survivor.origin.professionCandidates = metadata.professionCandidates
                survivor.origin.buildingId = metadata.buildingId
            end
            survivor.duty = type(survivor.duty) == "table" and survivor.duty or {
                mode = "autonomous", order = "survive", revision = 0,
            }
            survivor.duty.revision = math.max(0,
                math.floor(tonumber(survivor.duty.revision) or 0))
            survivor.duty.mode = tostring(survivor.duty.mode or "autonomous")
            -- Migrate the existing sparse base-work preference map in place.
            -- Older saves used 1-4 / false; missing values remain Normal.
            survivor.duty.workPriorities = normalizeWorkPreferences(
                survivor.duty.workPriorities
            )
            local rawOrder = tostring(survivor.duty.order or "survive")
            local normalizedOrder = canonicalOrder(rawOrder)
            if survivor.duty.mode == "companion" then
                -- Companion execution has exactly three persistent primary
                -- orders. Unknown or legacy values fail closed to Follow so a
                -- migrated save cannot strand a companion in an unowned mode.
                survivor.duty.order = (normalizedOrder == "hold"
                    or normalizedOrder == "relax") and normalizedOrder or "follow"
            elseif survivor.duty.mode == "base" then
                survivor.duty.order = "available"
            elseif survivor.duty.mode == "autonomous" then
                survivor.duty.order = "survive"
            else
                survivor.duty.order = normalizedOrder
            end
            local catalog = rawget(_G, "KnoxOrderCatalog")
            if catalog ~= nil and catalog.normalize ~= nil
                and survivor.duty.jobPreference ~= nil then
                local normalizedPreference = catalog.normalizeBasePreference ~= nil
                    and catalog.normalizeBasePreference(survivor.duty.jobPreference)
                    or catalog.normalize(survivor.duty.jobPreference)
                if normalizedPreference ~= nil then
                    survivor.duty.jobPreference = normalizedPreference
                end
            end
            if type(survivor.duty.directive) == "table" then
                local directive = survivor.duty.directive
                directive.kind = canonicalOrder(directive.kind)
                if not KnoxPersistence.isValidCompanionDirective(directive) then
                    survivor.duty.directive = nil
                end
            end
            if survivor.duty.baseSupplyOrder ~= nil then
                local request = survivor.duty.baseSupplyOrder
                if type(request) ~= "table"
                    or not BASE_SUPPLY_ORDER_KINDS[canonicalOrder(request.kind)]
                    or survivor.duty.mode ~= "base"
                    or type(survivor.affiliation) ~= "table"
                    or survivor.affiliation.kind ~= "player"
                    or survivor.affiliation.ownerId ~= survivor.duty.ownerId
                    or not finiteCoordinate(tonumber(request.issuedAtHours)) then
                    survivor.duty.baseSupplyOrder = nil
                else
                    request.kind = canonicalOrder(request.kind)
                    request.issuedAtHours = math.max(0, tonumber(request.issuedAtHours) or 0)
                    request.expiresAtHours = finiteCoordinate(tonumber(request.expiresAtHours))
                        and math.max(request.issuedAtHours, tonumber(request.expiresAtHours)) or nil
                    request.attempts = math.max(0, math.floor(tonumber(request.attempts) or 0))
                end
            end
            if survivor.duty.activeSupplyRun ~= nil then
                local activeRun = survivor.duty.activeSupplyRun
                if type(activeRun) ~= "table"
                    or survivor.alive == false
                    or survivor.duty.mode ~= "base"
                    or survivor.duty.eventId ~= nil
                    or not BASE_SUPPLY_ORDER_KINDS[canonicalOrder(activeRun.kind)]
                    or not finiteCoordinate(tonumber(activeRun.startedAtHours)) then
                    survivor.duty.activeSupplyRun = nil
                else
                    activeRun.kind = canonicalOrder(activeRun.kind)
                    activeRun.startedAtHours = math.max(
                        0,
                        tonumber(activeRun.startedAtHours) or 0
                    )
                end
            end
            if finiteCoordinate(tonumber(survivor.duty.lastSupplyRunAtHours)) then
                survivor.duty.lastSupplyRunAtHours = math.max(
                    0,
                    tonumber(survivor.duty.lastSupplyRunAtHours)
                )
            else
                survivor.duty.lastSupplyRunAtHours = nil
            end
            local lastSupplyKind = canonicalOrder(survivor.duty.lastSupplyKind)
            survivor.duty.lastSupplyKind = BASE_SUPPLY_ORDER_KINDS[lastSupplyKind]
                and lastSupplyKind or nil
            if type(survivor.duty.lastSupplyOutcome) ~= "string"
                or survivor.duty.lastSupplyOutcome == "" then
                survivor.duty.lastSupplyOutcome = nil
            end
            if survivor.unloadedSurvival ~= nil
                and type(survivor.unloadedSurvival) ~= "table" then
                survivor.unloadedSurvival = nil
            end
            if type(survivor.unloadedSurvival) == "table" then
                local state = survivor.unloadedSurvival
                if state.hunger ~= nil then state.hunger = math.max(0, math.min(1, tonumber(state.hunger) or 0)) end
                if state.thirst ~= nil then state.thirst = math.max(0, math.min(1, tonumber(state.thirst) or 0)) end
                if state.fatigue ~= nil then state.fatigue = math.max(0, math.min(1, tonumber(state.fatigue) or 0)) end
                if state.endurance ~= nil then state.endurance = math.max(0, math.min(1, tonumber(state.endurance) or 0)) end
                if state.health ~= nil then state.health = math.max(0, math.min(100, tonumber(state.health) or 0)) end
                if state.bleedingParts ~= nil then state.bleedingParts = math.max(0, math.floor(tonumber(state.bleedingParts) or 0)) end
                -- Informational only: native body damage owns live pain and
                -- may evolve while the survivor is materialized. Keep an old
                -- saved value finite without manufacturing pain on reload.
                if state.pain ~= nil then
                    local value = tonumber(state.pain)
                    state.pain = value ~= nil and value == value and value or nil
                end
            end
        end
        local departure = type(survivor) == "table" and survivor.departure or nil
        if departure ~= nil then
            local requested = type(departure) == "table"
                and tonumber(departure.requestedAtHours) or nil
            local completed = type(departure) == "table"
                and tonumber(departure.completedAtHours) or nil
            local validDeparture = type(departure) == "table"
                and (departure.status == "pending" or departure.status == "departed")
                and departure.source == "knox_event"
                and type(departure.eventId) == "string" and departure.eventId ~= ""
                and finiteCoordinate(requested) and requested >= 0
                and (departure.status ~= "departed"
                    or finiteCoordinate(completed) and completed >= requested)
            if not validDeparture then survivor.departure = nil end
        end
        if type(survivor) == "table" and survivor.lifeIntent ~= nil
            and not validLifeIntent(survivor.lifeIntent) then
            survivor.lifeIntent = nil
        end
    end
    for _, group in pairs(data.travelGroups) do
        if type(group) == "table" then
            group.objectiveRevision = math.max(
                0,
                math.floor(tonumber(group.objectiveRevision) or 0)
            )
            local objective = group.objective
            local objectiveLeaderPresent = false
            for _, memberId in ipairs(group.memberIds or {}) do
                if objective ~= nil and memberId == objective.leaderId then
                    objectiveLeaderPresent = true
                    break
                end
            end
            if objective ~= nil and (not validLifeIntent(objective)
                or type(objective.leaderId) ~= "string"
                or objective.leaderId ~= group.leaderId
                or not objectiveLeaderPresent) then
                group.objective = nil
                group.objectiveRevision = group.objectiveRevision + 1
            end
        end
    end
    -- A resident may own at most one claimed task. Controller unload does not
    -- cancel that durable claim, so validate it here against current life/duty
    -- state and repair duplicates deterministically before any scheduler reads
    -- the board. This is idempotent and never interrupts a valid sole claim.
    if tonumber(data.claimOwnershipNormalizedSchema) ~= SCHEMA_VERSION then
        local ownedClaims = {}
        local baseIds = {}
        for baseId in pairs(data.bases) do baseIds[#baseIds + 1] = baseId end
        table.sort(baseIds, function(a, b) return tostring(a) < tostring(b) end)
        for _, baseId in ipairs(baseIds) do
            local base = data.bases[baseId]
            local taskIds = {}
            for taskId in pairs(base.tasks or {}) do taskIds[#taskIds + 1] = taskId end
            table.sort(taskIds, function(a, b)
                local first, second = base.tasks[a], base.tasks[b]
                local firstPriority = tonumber(first ~= nil and first.priority) or 0
                local secondPriority = tonumber(second ~= nil and second.priority) or 0
                if firstPriority ~= secondPriority then return firstPriority > secondPriority end
                return tostring(a) < tostring(b)
            end)
            for _, taskId in ipairs(taskIds) do
                local task = base.tasks[taskId]
                if type(task) == "table" and task.state == "claimed" then
                    local survivor = type(task.claimedBy) == "string"
                        and data.survivors[task.claimedBy] or nil
                    local duty = survivor ~= nil and survivor.duty or nil
                    local valid = survivor ~= nil and survivor.alive ~= false
                        and duty ~= nil and duty.mode == "base"
                        and duty.baseId == baseId and duty.eventId == nil
                        and ownedClaims[task.claimedBy] == nil
                    if valid then
                        ownedClaims[task.claimedBy] = taskId
                    else
                        local interruption = "duplicate_survivor_claim"
                        if survivor == nil then
                            interruption = "claimant_missing"
                        elseif survivor.alive == false then
                            interruption = "claimant_dead"
                        elseif duty == nil or duty.mode ~= "base" or duty.baseId ~= baseId then
                            interruption = "claimant_duty_changed"
                        elseif duty.eventId ~= nil then
                            interruption = "claimant_event_owned"
                        end
                        task.lastClaimedBy = task.claimedBy
                        task.claimedBy = nil
                        task.claimedAtHours = nil
                        task.state = "queued"
                        task.interruptedReason = interruption
                    end
                end
            end
        end
        data.claimOwnershipNormalizedSchema = SCHEMA_VERSION
    end
    -- Rebuild schemas 1 and 2 already stored compatible encoded survivor records.
    -- Add newer domain tables in place instead of erasing people on a version bump.
    if previousVersion < SCHEMA_VERSION then
        data.migratedFromSchema = previousVersion
    end
    data.schemaVersion = SCHEMA_VERSION
    rememberNormalizedRoot(data)
    return data
end

local AWAY_MISSION_TYPES = {
    scout = true,
    food = true,
    medicine = true,
    weapons = true,
    tools = true,
    building = true,
}

local function copyFlat(source)
    local copied = {}
    for key, value in pairs(source or {}) do
        copied[key] = value
    end
    return copied
end

copySerializable = function(source, depth)
    if type(source) ~= "table" then
        return source
    end
    if (depth or 0) >= 6 then
        return nil
    end
    local copied = {}
    for key, value in pairs(source) do
        local keyType = type(key)
        local valueType = type(value)
        if (keyType == "string" or keyType == "number")
            and (valueType == "string" or valueType == "number"
                or valueType == "boolean" or valueType == "table") then
            copied[key] = copySerializable(value, (depth or 0) + 1)
        end
    end
    return copied
end

-- Store the original value once before a destructive migration, so restores
-- never overwrite a previously saved original.
backupOnce = function(container, key, value)
    if type(container) ~= "table" or container[key] ~= nil then
        return container ~= nil and container[key] or nil
    end
    container[key] = copySerializable(value, 0)
    return container[key]
end

-- Restore the one-time pre-migration snapshot (manual recovery boundary).
function KnoxPersistence.restorePreMigrationBackup()
    local data = ModData.getOrCreate(MOD_DATA_KEY)
    local backup = data.preMigrationBackup
    if type(backup) ~= "table" then return false, "no_backup" end
    if backup.version == 2 and type(backup.snapshot) == "table" then
        local restored = copyRecoveryTree(backup.snapshot)
        for key in pairs(data) do
            if key ~= "preMigrationBackup" then data[key] = nil end
        end
        for key, value in pairs(restored) do data[key] = value end
        invalidateNormalizedRoot()
        return true, "restored"
    end
    if backup.survivors ~= nil then data.survivors = copySerializable(backup.survivors, 0) end
    if backup.factions ~= nil then data.factions = copySerializable(backup.factions, 0) end
    if backup.travelGroups ~= nil then data.travelGroups = copySerializable(backup.travelGroups, 0) end
    if backup.bases ~= nil then data.bases = copySerializable(backup.bases, 0) end
    if backup.players ~= nil then data.players = copySerializable(backup.players, 0) end
    invalidateNormalizedRoot()
    return true, "restored"
end

local function ensureSurvivorState(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local data = root()
    local survivor = data.survivors[id] or { id = id }
    survivor.affiliation = survivor.affiliation or {
        kind = "independent",
        ownerId = nil,
    }
    survivor.duty = survivor.duty or {
        mode = "autonomous",
        order = "survive",
        revision = 0,
    }
    -- Older saves predate companion stances. Normalize the persisted value at
    -- the identity boundary so every controller sync starts from a deliberate
    -- defensive default instead of treating nil as an implicit attack order.
    if survivor.duty.mode == "companion" then
        local stance = survivor.duty.combatStance
        if stance ~= "passive" and stance ~= "aggressive" and stance ~= "defensive" then
            survivor.duty.combatStance = "defensive"
        end
        survivor.duty.order = survivor.duty.order == "hold" and "hold"
            or (survivor.duty.order == "relax" and "relax" or "follow")
    end
    survivor.playerRelationships = survivor.playerRelationships or {}
    survivor.policies = survivor.policies or {
        allowClimbing = true,
    }
    local weaponPreference = survivor.policies.weaponPreference
    if weaponPreference ~= "melee" and weaponPreference ~= "ranged" and weaponPreference ~= "auto" then
        survivor.policies.weaponPreference = "auto"
    end
    -- Corrupted schedules (hand edits, older experiments) must not survive
    -- the load boundary: an invalid record falls back to nil, which reads
    -- as "anything", instead of poisoning schedule resolution.
    if survivor.duty.schedule ~= nil
        and not KnoxPersistence.validDutySchedule(survivor.duty.schedule) then
        survivor.duty.schedule = nil
        survivor.duty.scheduleAuto = nil
    end
    if survivor.alive == nil then
        survivor.alive = true
    end
    data.survivors[id] = survivor
    return survivor
end

local function requeueClaimsForSurvivor(id, baseId, reason)
    local requeued = 0
    for _, base in pairs(root().bases) do
        if baseId == nil or base.id == baseId then
            for _, task in pairs(base.tasks or {}) do
                if task.state == "claimed" and task.claimedBy == id then
                    task.state = "queued"
                    task.lastClaimedBy = task.claimedBy
                    task.claimedBy = nil
                    task.claimedAtHours = nil
                    -- A claim that leaves with its resident is no longer a
                    -- player-directed assignment. Clear the marker so the
                    -- next eligible resident can receive it as ordinary work.
                    task.manual = nil
                    task.auto = nil
                    task.interruptedReason = tostring(reason or "duty_changed")
                    requeued = requeued + 1
                end
            end
        end
    end
    return requeued
end

function KnoxPersistence.requeueBaseTasksForSurvivor(id, baseId, reason)
    if type(id) ~= "string" or id == "" then
        return 0
    end
    return requeueClaimsForSurvivor(id, baseId, reason)
end

-- Changing an automatic resident preference is a real duty handoff.  Release
-- only non-manual claims so a player-assigned task remains authoritative while
-- routine work can be reconsidered immediately under the new preference.
function KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(id, baseId, reason)
    if type(id) ~= "string" or id == "" then
        return 0
    end
    local requeued = 0
    for _, base in pairs(root().bases) do
        if baseId == nil or base.id == baseId then
            for _, task in pairs(base.tasks or {}) do
                if task.state == "claimed" and task.claimedBy == id
                    and task.manual ~= true then
                    task.state = "queued"
                    task.lastClaimedBy = task.claimedBy
                    task.claimedBy = nil
                    task.claimedAtHours = nil
                    task.offscreenWaitHours = 0
                    task.offscreenLastHours = nil
                    task.auto = nil
                    task.interruptedReason = tostring(reason or "duty_changed")
                    requeued = requeued + 1
                end
            end
        end
    end
    return requeued
end

function KnoxPersistence.getClaimedBaseTaskForSurvivor(id, baseId)
    if type(id) ~= "string" or id == "" then return nil end
    local data = root()
    local base = type(baseId) == "string" and data.bases[baseId] or nil
    if base == nil then return nil end
    local survivor = data.survivors[id]
    local duty = survivor ~= nil and survivor.duty or nil
    if survivor == nil or survivor.alive == false or duty == nil
        or duty.mode ~= "base" or duty.baseId ~= baseId or duty.eventId ~= nil then
        requeueClaimsForSurvivor(id, baseId, "claimant_not_available")
        return nil
    end
    local claimed = {}
    for _, task in pairs(base.tasks or {}) do
        if type(task) == "table" and task.state == "claimed" then
            local claimant = type(task.claimedBy) == "string"
                and data.survivors[task.claimedBy] or nil
            local claimantDuty = claimant ~= nil and claimant.duty or nil
            if claimant == nil or claimant.alive == false or claimantDuty == nil
                or claimantDuty.mode ~= "base" or claimantDuty.baseId ~= baseId
                or claimantDuty.eventId ~= nil then
                task.lastClaimedBy = task.claimedBy
                task.claimedBy = nil
                task.claimedAtHours = nil
                task.state = "queued"
                task.interruptedReason = claimant == nil and "claimant_missing"
                    or claimant.alive == false and "claimant_dead"
                    or "claimant_not_available"
            elseif task.claimedBy == id then
                claimed[#claimed + 1] = task
            end
        end
    end
    table.sort(claimed, function(first, second)
        local firstPriority = tonumber(first.priority) or 0
        local secondPriority = tonumber(second.priority) or 0
        if firstPriority ~= secondPriority then return firstPriority > secondPriority end
        return tostring(first.id or "") < tostring(second.id or "")
    end)
    local selected = claimed[1]
    for index = 2, #claimed do
        local task = claimed[index]
        task.state = "queued"
        task.lastClaimedBy = id
        task.claimedBy = nil
        task.claimedAtHours = nil
        task.interruptedReason = "duplicate_survivor_claim"
    end
    if selected ~= nil then selected.baseId = baseId end
    return selected
end

-- Repair the small amount of task-board drift that can occur between a save,
-- unload, ownership change, and the next loaded controller tick.  Assignment
-- remains atomic in claimBaseTask; this pass is only a persistence-boundary
-- reconciliation for claims whose owner is no longer a valid resident or who
-- accidentally owns more than one task after an interrupted transition.
function KnoxPersistence.reconcileBaseTaskClaims(baseId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return 0, 0 end
    local data = root()
    local residents = {}
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(baseId) or {}) do
        local survivor = data.survivors[id]
        local duty = survivor ~= nil and survivor.duty or nil
        if survivor ~= nil and survivor.alive ~= false and duty ~= nil
            and duty.mode == "base" and duty.baseId == baseId
            and duty.eventId == nil then
            residents[id] = true
        end
    end
    local claimed = {}
    local repaired, duplicates = 0, 0
    local function priority(task)
        return tonumber(task ~= nil and task.priority or 0) or 0
    end
    local function taskId(task, fallback)
        return tostring(task ~= nil and task.id or fallback or "")
    end
    local ids = {}
    for fallbackId in pairs(base.tasks or {}) do ids[#ids + 1] = fallbackId end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, fallbackId in ipairs(ids) do
        local task = base.tasks[fallbackId]
        if type(task) == "table" and task.state == "claimed" then
            local claimant = task.claimedBy
            if type(claimant) ~= "string" or not residents[claimant] then
                task.state = "queued"
                task.lastClaimedBy = claimant
                task.claimedBy = nil
                task.claimedAtHours = nil
                task.offscreenWaitHours = 0
                task.offscreenLastHours = nil
                task.manual = nil
                task.auto = nil
                task.interruptedReason = "claimant_not_available"
                repaired = repaired + 1
            elseif claimed[claimant] == nil then
                claimed[claimant] = task
            else
                local current = claimed[claimant]
                local keepCurrent = priority(current) > priority(task)
                    or (priority(current) == priority(task)
                        and taskId(current, "") < taskId(task, fallbackId))
                local loser = keepCurrent and task or current
                loser.state = "queued"
                loser.lastClaimedBy = claimant
                loser.claimedBy = nil
                loser.claimedAtHours = nil
                loser.offscreenWaitHours = 0
                loser.offscreenLastHours = nil
                loser.manual = nil
                loser.auto = nil
                loser.interruptedReason = "duplicate_resident_claim"
                if not keepCurrent then claimed[claimant] = task end
                repaired = repaired + 1
                duplicates = duplicates + 1
            end
        end
    end
    return repaired, duplicates
end

function KnoxPersistence.reconcileAllBaseTaskClaims(worldAgeHours)
    local repaired, duplicates = 0, 0
    for id, base in pairs(root().bases or {}) do
        local fixed, duplicateCount = KnoxPersistence.reconcileBaseTaskClaims(
            base.id or id, worldAgeHours
        )
        repaired = repaired + (tonumber(fixed) or 0)
        duplicates = duplicates + (tonumber(duplicateCount) or 0)
    end
    return repaired, duplicates
end

local function relationshipKey(firstId, secondId)
    if type(firstId) ~= "string" or firstId == ""
        or type(secondId) ~= "string" or secondId == "" or firstId == secondId then
        return nil
    end
    if firstId < secondId then
        return firstId .. "::" .. secondId, firstId, secondId
    end
    return secondId .. "::" .. firstId, secondId, firstId
end

local function stableTrait(id, salt)
    local value = 17 + salt * 31
    for index = 1, #id do
        value = (value * 33 + string.byte(id, index)) % 10007
    end
    return value % 101
end

-- Social identity is deterministic when first created, then saved with the
-- survivor. This keeps a person's manner consistent across reloads without
-- making every independent survivor hostile or willing to join by default.
local PERSONALITY_PROFILES = {
    frightened = { label = "Scared and alone", playerResponse = "warm_up",
        sociability = 34, aggression = 14, courage = 20, deception = 4 },
    guarded = { label = "Guarded", playerResponse = "warm_up",
        sociability = 30, aggression = 24, courage = 42, deception = 18 },
    brave = { label = "Brave", playerResponse = "join",
        sociability = 58, aggression = 42, courage = 82, deception = 8 },
    loner = { label = "Independent", playerResponse = "independent",
        sociability = 18, aggression = 30, courage = 62, deception = 15 },
    sociable = { label = "Open and cooperative", playerResponse = "join",
        sociability = 84, aggression = 22, courage = 56, deception = 3 },
    unstable = { label = "Unpredictable", playerResponse = "volatile",
        sociability = 42, aggression = 58, courage = 48, deception = 38 },
    opportunist = { label = "Opportunistic", playerResponse = "lure",
        sociability = 48, aggression = 46, courage = 54, deception = 76 },
    gunner = { label = "Volatile gunner", playerResponse = "warn_then_attack",
        sociability = 12, aggression = 88, courage = 70, deception = 20 },
    predatory = { label = "Predatory", playerResponse = "attack_on_sight",
        sociability = 22, aggression = 82, courage = 72, deception = 58 },
}

local function defaultPersonality(id)
    local roll = stableTrait(id, 4)
    if roll <= 14 then return "frightened"
    elseif roll <= 28 then return "guarded"
    elseif roll <= 43 then return "brave"
    elseif roll <= 56 then return "loner"
    elseif roll <= 70 then return "sociable"
    elseif roll <= 81 then return "unstable"
    elseif roll <= 88 then return "opportunist"
    elseif roll <= 93 then return "gunner"
    end
    return "predatory"
end

--- Read-only copy of a personality profile for authored overrides
-- (legacy survivors, event policies). Returns nil for unknown archetypes.
function KnoxPersistence.getPersonalityProfile(archetype)
    local profile = type(archetype) == "string" and PERSONALITY_PROFILES[archetype] or nil
    if profile == nil then return nil end
    local copy = {}
    for key, value in pairs(profile) do copy[key] = value end
    return copy
end

local function initializePersonality(identity, id)
    local archetype = PERSONALITY_PROFILES[identity.personality] ~= nil
        and identity.personality or defaultPersonality(id)
    local profile = PERSONALITY_PROFILES[archetype]
    identity.personality = archetype
    identity.personalityLabel = identity.personalityLabel or profile.label
    identity.playerResponse = identity.playerResponse or profile.playerResponse
    identity.courage = identity.courage or profile.courage
    identity.deception = identity.deception or profile.deception
    -- Preserve authored or legacy sociability/aggression values when present.
    identity.sociability = identity.sociability or profile.sociability
    identity.aggression = identity.aggression or profile.aggression
    return identity
end

function KnoxPersistence.getTestRecord()
    return KnoxPersistence.getRecord(TEST_SURVIVOR_ID)
end

function KnoxPersistence.getRecord(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.record or nil
end

function KnoxPersistence.allocateDeveloperSurvivorId()
    local data = root()
    local value = math.max(1, tonumber(data.nextDeveloperSurvivorId) or 1)
    local id = "ks-dev-" .. tostring(value)
    while data.survivors[id] ~= nil do
        value = value + 1
        id = "ks-dev-" .. tostring(value)
    end
    data.nextDeveloperSurvivorId = value + 1
    return id
end

-- Automated QA ownership lives on the canonical survivor identity record so a
-- reload does not erase the provenance required for safe fixture cleanup.
function KnoxPersistence.tagDeveloperQaFixture(id, runId, ownerToken, scenarioId)
    if type(id) ~= "string" or string.find(id, "ks-dev-", 1, true) ~= 1
        or type(runId) ~= "string" or runId == ""
        or type(ownerToken) ~= "string" or ownerToken == "" then
        return false, "invalid_qa_fixture_owner"
    end
    local survivor = ensureSurvivorState(id)
    local current = survivor.qaOwnership
    if type(current) == "table"
        and (current.runId ~= runId or current.ownerToken ~= ownerToken) then
        return false, "fixture_owned_by_another_run"
    end
    survivor.qaOwnership = {
        runId = runId,
        ownerToken = ownerToken,
        scenarioId = type(scenarioId) == "string" and scenarioId or "unknown",
    }
    return true, "tagged"
end

function KnoxPersistence.getDeveloperQaFixtureOwner(id)
    if type(id) ~= "string" or string.find(id, "ks-dev-", 1, true) ~= 1 then return nil end
    local owner = root().survivors[id] ~= nil and root().survivors[id].qaOwnership or nil
    if type(owner) ~= "table" or type(owner.runId) ~= "string"
        or type(owner.ownerToken) ~= "string" then return nil end
    return { runId = owner.runId, ownerToken = owner.ownerToken,
        scenarioId = tostring(owner.scenarioId or "unknown") }
end

function KnoxPersistence.listDeveloperQaFixtures()
    local fixtures = {}
    for id, survivor in pairs(root().survivors) do
        local owner = type(survivor) == "table" and survivor.qaOwnership or nil
        if type(id) == "string" and string.find(id, "ks-dev-", 1, true) == 1
            and type(owner) == "table" and type(owner.runId) == "string"
            and type(owner.ownerToken) == "string" then
            fixtures[#fixtures + 1] = {
                id = id,
                owner = { runId = owner.runId, ownerToken = owner.ownerToken,
                    scenarioId = tostring(owner.scenarioId or "unknown") },
            }
        end
    end
    table.sort(fixtures, function(a, b) return a.id < b.id end)
    return fixtures
end

function KnoxPersistence.clearDeveloperQaFixtureOwner(id, runId, ownerToken)
    local current = KnoxPersistence.getDeveloperQaFixtureOwner(id)
    if current == nil or current.runId ~= runId or current.ownerToken ~= ownerToken then
        return false, "qa_fixture_owner_mismatch"
    end
    local survivor = root().survivors[id]
    survivor.qaOwnership = nil
    return true, "cleared"
end

function KnoxPersistence.allocateWorldSurvivor(origin, worldAgeHours)
    if type(origin) ~= "table" or tonumber(origin.x) == nil or tonumber(origin.y) == nil then
        return nil, "invalid_origin"
    end
    local data = root()
    local x = math.floor(tonumber(origin.x))
    local y = math.floor(tonumber(origin.y))
    local z = math.floor(tonumber(origin.z) or 0)
    local metadata = sanitizeOriginMetadata(origin, false)
    local originKey = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    for _, existing in pairs(data.survivors) do
        local existingOrigin = type(existing) == "table" and existing.origin or nil
        if existing ~= nil and existing.populationManaged == true
            and type(existingOrigin) == "table" then
            local existingKey = existingOrigin.key
                or (tostring(math.floor(tonumber(existingOrigin.x) or 0))
                    .. "," .. tostring(math.floor(tonumber(existingOrigin.y) or 0))
                    .. "," .. tostring(math.floor(tonumber(existingOrigin.z) or 0)))
            existingOrigin.key = existingKey
            if existingKey == originKey then
                return nil, "origin_already_used"
            end
        end
    end
    local value = math.max(1, tonumber(data.nextWorldSurvivorId) or 1)
    local id = "ks-world-" .. tostring(value)
    while data.survivors[id] ~= nil do
        value = value + 1
        id = "ks-world-" .. tostring(value)
    end
    data.nextWorldSurvivorId = value + 1
    local survivor = ensureSurvivorState(id)
    survivor.populationManaged = true
    survivor.alive = true
    survivor.origin = {
        x = x,
        y = y,
        z = z,
        key = originKey,
        region = tostring(origin.region or "Unknown"),
        regionKey = tostring(origin.regionKey or origin.region or "Unknown"),
        source = tostring(origin.source or "player_spawn"),
        context = metadata.context,
        professionCandidates = metadata.professionCandidates,
        buildingId = metadata.buildingId,
    }
    survivor.createdAtHours = tonumber(worldAgeHours) or 0
    survivor.unloadedSurvival = {
        pendingMaterialization = true, status = "unmaterialized", activity = "origin_shelter",
        virtualX = x, virtualY = y, virtualZ = z,
        lastHours = survivor.createdAtHours, virtualAtHours = survivor.createdAtHours,
        currentTravelKey = originKey,
        departAtHours = survivor.createdAtHours + 1 + value % 4,
    }
    return id, copySerializable(survivor.origin, 0)
end

function KnoxPersistence.getPopulationState()
    return root().population
end

-- Like population state, this domain is mutated by its one owning service.
-- Event records reference canonical survivors/factions, never encoded actor copies.
function KnoxPersistence.getKnoxEventState()
    local events = root().knoxEvents
    -- Event scheduling owns these mutable scalar fields. Validate them at
    -- this narrow boundary so damaged save data cannot poison the scheduler
    -- without making unrelated hot getters rescan the entire persistent world.
    local automatic = type(events.automatic) == "table" and events.automatic or {}
    events.automatic = automatic
    local nextCheck = tonumber(automatic.nextCheckHours)
    local cursor = tonumber(automatic.cursor)
    automatic.nextCheckHours = finiteCoordinate(nextCheck) and nextCheck >= 0
        and nextCheck or 0
    automatic.cursor = finiteCoordinate(cursor) and cursor >= 0
        and math.floor(cursor) or 0
    local entryNextCheck = tonumber(automatic.entryNextCheckHours)
    local entryCursor = tonumber(automatic.entryCursor)
    automatic.entryNextCheckHours = finiteCoordinate(entryNextCheck) and entryNextCheck >= 0
        and entryNextCheck or 0
    automatic.entryCursor = finiteCoordinate(entryCursor) and entryCursor >= 0
        and math.floor(entryCursor) or 0
    return events
end

function KnoxPersistence.getSurvivorOrigin(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.origin) == "table"
        and copySerializable(survivor.origin, 0)
        or nil
end

function KnoxPersistence.getActivatableSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.alive ~= false
            and not (type(survivor.departure) == "table"
                and (survivor.departure.status == "pending"
                    or survivor.departure.status == "departed"))
            and (survivor.record ~= nil or type(survivor.origin) == "table") then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getLivingWorldSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.populationManaged == true and survivor.alive ~= false
            and not (type(survivor.departure) == "table"
                and (survivor.departure.status == "pending"
                    or survivor.departure.status == "departed")) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getAllWorldSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.populationManaged == true then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getUsedWorldOriginKeys()
    local used = {}
    for _, survivor in pairs(root().survivors) do
        local origin = type(survivor) == "table" and survivor.origin or nil
        if survivor ~= nil and survivor.populationManaged == true
            and type(origin) == "table"
            and tonumber(origin.x) ~= nil and tonumber(origin.y) ~= nil then
            local key = origin.key
                or (tostring(math.floor(tonumber(origin.x)))
                    .. "," .. tostring(math.floor(tonumber(origin.y)))
                    .. "," .. tostring(math.floor(tonumber(origin.z) or 0)))
            origin.key = key
            used[key] = true
        end
    end
    return used
end

local function deathEvidenceFor(survivor, worldAgeHours, reason, supplied)
    supplied = type(supplied) == "table" and supplied or {}
    local state = type(survivor.unloadedSurvival) == "table" and survivor.unloadedSurvival or nil
    local x, y, z = tonumber(supplied.x), tonumber(supplied.y), tonumber(supplied.z)
    local source = supplied.locationSource
    if not (finiteCoordinate(x) and finiteCoordinate(y) and finiteCoordinate(z)) and state ~= nil then
        x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
        source = "logical"
    end
    if not (finiteCoordinate(x) and finiteCoordinate(y) and finiteCoordinate(z)) then
        x, y, z, source = nil, nil, nil, nil
    end
    local affiliation = type(survivor.affiliation) == "table" and survivor.affiliation or {}
    local duty = type(survivor.duty) == "table" and survivor.duty or {}
    local corpseState = supplied.corpseState == "native_pending" and "native_pending"
        or "logical_only"
    return {
        version = 1, atHours = tonumber(worldAgeHours) or 0,
        reason = tostring(reason or "died"), x = x, y = y, z = z,
        locationSource = source,
        ownerKind = affiliation.kind, ownerId = affiliation.ownerId, factionId = affiliation.factionId,
        dutyMode = duty.mode, baseId = duty.baseId,
        inventorySummary = tostring(survivor.inventorySummary or ""),
        inventorySummaryAtHours = tonumber(survivor.inventorySummaryAtHours),
        health = state ~= nil and tonumber(state.health) or nil,
        bleedingParts = state ~= nil and tonumber(state.bleedingParts) or nil,
        pain = state ~= nil and tonumber(state.pain) or nil,
        corpseState = corpseState,
    }
end

function KnoxPersistence.markSurvivorDead(id, worldAgeHours, reason, evidence)
    local survivor = ensureSurvivorState(id)
    if survivor == nil then
        return false
    end
    if survivor.alive == false then return true end
    survivor.deathEvidence = deathEvidenceFor(survivor, worldAgeHours, reason, evidence)
    survivor.alive = false
    local assignedBed = survivor.policies ~= nil and survivor.policies.assignedBed or nil
    if type(assignedBed) == "table" and assignedBed.autoFactionId ~= nil then
        survivor.policies.assignedBed = nil
    end
    -- Death wins over a same-tick event withdrawal. The corpse lifecycle must
    -- remain authoritative and a dead entrant must never be recorded as having
    -- safely left Knox County.
    survivor.departure = nil
    survivor.diedAtHours = tonumber(worldAgeHours) or 0
    survivor.deathReason = tostring(reason or "died")
    if KnoxPersistence.removeSurvivorFromSocialDomains ~= nil then
        KnoxPersistence.removeSurvivorFromSocialDomains(id, "died", worldAgeHours)
    end
    return true
end

function KnoxPersistence.isSurvivorAlive(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.alive ~= false
end

function KnoxPersistence.isSurvivorPresent(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    local departure = survivor ~= nil and survivor.departure or nil
    return survivor ~= nil and survivor.alive ~= false
        and not (type(departure) == "table"
            and (departure.status == "pending" or departure.status == "departed"))
end

function KnoxPersistence.getSurvivorDeparture(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.departure) == "table"
        and copySerializable(survivor.departure)
        or nil
end

function KnoxPersistence.getLastKnownNeeds(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.lastKnownNeeds) == "table"
        and copyFlat(survivor.lastKnownNeeds)
        or nil
end

function KnoxPersistence.getInventorySummary(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and tostring(survivor.inventorySummary or "") or ""
end

function KnoxPersistence.setInventorySummary(id, summary, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(summary) ~= "string" then
        return false
    end
    survivor.inventorySummary = summary
    survivor.inventorySummaryAtHours = tonumber(worldAgeHours) or 0
    return true
end

function KnoxPersistence.getUnloadedSurvivalState(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.unloadedSurvival) == "table"
        and copySerializable(survivor.unloadedSurvival)
        or nil
end

function KnoxPersistence.setUnloadedSurvivalState(id, state)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(state) ~= "table" then
        return false
    end
    survivor.unloadedSurvival = copySerializable(state)
    return survivor.unloadedSurvival ~= nil
end

function KnoxPersistence.setTestRecord(encoded)
    return KnoxPersistence.setRecord(TEST_SURVIVOR_ID, encoded)
end

function KnoxPersistence.setRecord(id, encoded)
    if type(id) ~= "string" or id == "" then
        return false
    end
    if type(encoded) ~= "string" or encoded == "" then
        return false
    end
    local survivor = root().survivors[id] or { id = id }
    survivor.record = encoded
    root().survivors[id] = survivor
    return true
end

function KnoxPersistence.ensureSurvivorIdentity(id, forename, surname, worldAgeHours, ageYears)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local data = root()
    local survivor = data.survivors[id] or { id = id }
    survivor.identity = survivor.identity or {}
    -- Lua treats an empty string as truthy, so `saved or live` would preserve
    -- nameless identities forever. Fill missing/empty legacy fields from the
    -- live randomized SurvivorFactory descriptor when it becomes available.
    if survivor.identity.forename == nil or survivor.identity.forename == "" then
        survivor.identity.forename = tostring(forename or "")
    end
    if survivor.identity.surname == nil or survivor.identity.surname == "" then
        survivor.identity.surname = tostring(surname or "")
    end
    survivor.identity.createdAtHours = survivor.identity.createdAtHours
        or tonumber(worldAgeHours)
        or 0
    survivor.identity.ageYears = survivor.identity.ageYears
        or tonumber(ageYears)
        or (18 + stableTrait(id, 3) % 53)
    survivor.identity.sociability = survivor.identity.sociability
        or stableTrait(id, 1)
    survivor.identity.aggression = survivor.identity.aggression
        or stableTrait(id, 2)
    initializePersonality(survivor.identity, id)
    data.survivors[id] = survivor
    return survivor.identity
end

function KnoxPersistence.getSurvivorPersonality(id)
    local identity = type(id) == "string" and KnoxPersistence.getSurvivorIdentity(id) or nil
    if identity == nil and type(id) == "string" then
        identity = KnoxPersistence.ensureSurvivorIdentity(id, "", "", 0, nil)
    end
    if identity == nil then return nil end
    initializePersonality(identity, id)
    return copyFlat(identity)
end

function KnoxPersistence.ensureSurvivorIdentityFromCharacter(id, character, worldAgeHours)
    if character == nil then
        return nil
    end
    local success, forename, surname, hoursSurvived = pcall(function()
        local descriptor = character:getDescriptor()
        return descriptor ~= nil and descriptor:getForename() or "",
            descriptor ~= nil and descriptor:getSurname() or "",
            character:getHoursSurvived()
    end)
    if not success then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    local identity = KnoxPersistence.ensureSurvivorIdentity(
        id,
        forename,
        surname,
        math.max(0, now - math.max(0, tonumber(hoursSurvived) or 0)),
        nil
    )
    if identity ~= nil and tonumber(identity.ageYears) ~= nil then
        pcall(function()
            character:setAge(math.floor(tonumber(identity.ageYears)))
        end)
    end
    return identity
end

function KnoxPersistence.getSurvivorIdentity(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.identity or nil
end

function KnoxPersistence.getPlayerRelationshipSnapshot(playerId, survivorId)
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    local relation = survivor ~= nil and type(survivor.playerRelationships) == "table"
        and survivor.playerRelationships[playerId]
        or nil
    return relation ~= nil and copyFlat(relation) or nil
end

function KnoxPersistence.getSurvivorCapabilities(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and survivor.capabilities or nil
end

function KnoxPersistence.setSurvivorCapabilities(id, capabilities)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(capabilities) ~= "table" then
        return false
    end
    survivor.capabilities = capabilities
    return true
end

function KnoxPersistence.getSurvivorAffiliation(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.affiliation) or nil
end

function KnoxPersistence.getSurvivorDuty(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.duty) or nil
end

-- A life intent is the durable reason behind an autonomous action, not an
-- action owner. Movement, combat, traversal, and timed actions remain runtime
-- state and are deliberately never restored from this record.
function KnoxPersistence.getSurvivorLifeIntent(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and validLifeIntent(survivor.lifeIntent)
        and copySerializable(survivor.lifeIntent) or nil
end

function KnoxPersistence.setSurvivorLifeIntent(id, intent, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.duty == nil or not validLifeIntent(intent) then
        return false
    end
    local autonomousIntent = survivor.duty.mode == "autonomous"
    local baseIntent = survivor.duty.mode == "base"
        and (intent.kind == "find_food" or intent.kind == "find_water"
            or intent.kind == "find_medical" or intent.kind == "find_weapon"
            or intent.kind == "find_tools" or intent.kind == "base_supply_deposit")
    if not autonomousIntent and not baseIntent then return false end
    survivor.lifeIntent = copySerializable(intent)
    survivor.lifeIntent.updatedAtHours = tonumber(worldAgeHours) or 0
    survivor.lifeIntent.startedAtHours = tonumber(
        survivor.lifeIntent.startedAtHours
    ) or survivor.lifeIntent.updatedAtHours
    return true
end

function KnoxPersistence.clearSurvivorLifeIntent(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    if survivor == nil then return false end
    survivor.lifeIntent = nil
    return true
end

-- Events borrow a base duty, never replace faction/home/job intent. Validate the
-- entire party first: no partial assignment if one member changed jobs or died.
function KnoxPersistence.claimEventDuty(eventId, worldAgeHours)
    local data = root()
    local event = type(eventId) == "string" and data.knoxEvents.records[eventId] or nil
    if type(event) ~= "table" or event.kind ~= "faction_raid"
        or (event.phase ~= "scheduled" and event.phase ~= "spawning")
        or type(event.memberIds) ~= "table" or #event.memberIds == 0 then
        return false, "invalid_event"
    end
    local base = data.bases[event.sourceBaseId]
    if base == nil or base.ownerKind ~= "faction" or base.ownerId ~= event.sourceFactionId then
        return false, "invalid_home"
    end
    local seen, pending = {}, {}
    for _, id in ipairs(event.memberIds) do
        local survivor = type(id) == "string" and data.survivors[id] or nil
        local duty = survivor ~= nil and survivor.duty or nil
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        if survivor == nil or survivor.alive == false or survivor.record == nil or seen[id]
            or affiliation == nil or affiliation.factionId ~= event.sourceFactionId
            or duty == nil or duty.mode ~= "base" or duty.baseId ~= event.sourceBaseId
            or (duty.eventId ~= nil and duty.eventId ~= eventId) then
            return false, "member_unavailable"
        end
        for _, task in pairs(base.tasks or {}) do
            if type(task) == "table" and task.state == "claimed" and task.claimedBy == id then
                return false, "member_working"
            end
        end
        seen[id] = true
        if duty.eventId == nil then pending[#pending + 1] = duty end
    end
    for _, duty in ipairs(pending) do
        duty.eventId = eventId
        duty.revision = (tonumber(duty.revision) or 0) + 1
        duty.changedAtHours = tonumber(worldAgeHours) or 0
    end
    return true, #pending == 0 and "existing" or "claimed"
end

function KnoxPersistence.releaseEventDuty(id, eventId, worldAgeHours)
    if type(eventId) ~= "string" or eventId == "" then return false, "invalid_event" end
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    local duty = survivor ~= nil and survivor.duty or nil
    if duty == nil or duty.eventId ~= eventId then return false, "not_event_owner" end
    duty.eventId = nil
    duty.revision = (tonumber(duty.revision) or 0) + 1
    duty.changedAtHours = tonumber(worldAgeHours) or 0
    local state = survivor.unloadedSurvival
    if type(state) == "table" and state.eventEntryId == eventId then
        -- An event can withdraw before every entrant ever materializes. Release
        -- its origin-wait marker with the duty or that persistent identity would
        -- remain permanently frozen at the entry anchor after the event ends.
        state.eventEntryId = nil
        state.activity = "sheltering"
        state.activitySinceHours = duty.changedAtHours
        state.departAtHours = math.max(tonumber(state.departAtHours) or 0, duty.changedAtHours + 1)
    end
    -- A removed home cannot remain an actionable base order. Keep affiliation;
    -- surviving members can use the existing faction/autonomy recovery instead.
    local base = data.bases[duty.baseId]
    if duty.mode == "base" and (base == nil or base.ownerKind ~= "faction"
        or base.ownerId ~= (survivor.affiliation or {}).factionId) then
        duty.mode, duty.order, duty.baseId = "autonomous", "survive", nil
    end
    return true, "released"
end

-- Deserters flagged on a hostile patrol leave it when the patrol's event ends
-- and become ordinary recruitable independents looking for a home. Safe to call
-- for any event id; non-deserters are untouched.
function KnoxPersistence.releaseDeserters(eventId, worldAgeHours)
    if type(eventId) ~= "string" or eventId == "" then return {}, "invalid_event" end
    local data = root()
    local hours = tonumber(worldAgeHours) or 0
    local released = {}
    for id, survivor in pairs(data.survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.deserter == true and survivor.eventSourceId == eventId
            and survivor.alive ~= false then
            KnoxPersistence.releaseEventDuty(id, eventId, hours)
            for _, group in pairs(data.travelGroups) do
                local retained = {}
                for _, memberId in ipairs(group.memberIds or {}) do
                    if memberId ~= id then retained[#retained + 1] = memberId end
                end
                group.memberIds = retained
            end
            for _, faction in pairs(data.factions) do
                local retained = {}
                for _, memberId in ipairs(faction.memberIds or {}) do
                    if memberId ~= id then retained[#retained + 1] = memberId end
                end
                faction.memberIds = retained
            end
            survivor.affiliation = { kind = "independent" }
            survivor.duty = {
                mode = "autonomous",
                order = "survive",
                changedAtHours = hours,
                revision = (tonumber(survivor.duty ~= nil and survivor.duty.revision) or 0) + 1,
            }
            if survivor.identity == nil then survivor.identity = {} end
            survivor.identity.playerResponse = "join"
            released[#released + 1] = id
        end
    end
    table.sort(released)
    return released, "released"
end

function KnoxPersistence.getAwayTeams()
    local teams = {}
    for id, team in pairs(root().awayTeams) do
        if type(team) == "table" then
            teams[id] = copySerializable(team)
        end
    end
    return teams
end

function KnoxPersistence.getAwayTeam(id)
    local team = type(id) == "string" and root().awayTeams[id] or nil
    return type(team) == "table" and copySerializable(team) or nil
end

-- Read-only progress snapshot for the Notebook/HUD.  Mission state remains
-- authoritative in the persisted team record; this helper only derives timing
-- fields and never advances or mutates a mission.
function KnoxPersistence.getAwayTeamProgress(id, worldAgeHours)
    local team = KnoxPersistence.getAwayTeam(id)
    if team == nil then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    local departure = tonumber(team.departedAtHours) or now
    local eta = tonumber(team.etaHours) or departure
    local duration = math.max(0.25, eta - departure)
    local elapsed = math.max(0, now - departure)
    local progress = math.max(0, math.min(1, elapsed / duration))
    local remaining = team.state == "outbound" and math.max(0, eta - now) or 0
    team.elapsedHours = elapsed
    team.remainingHours = remaining
    team.progress = progress
    local collectedItems, collectingMembers = 0, 0
    local collection = type(team.collection) == "table" and team.collection or nil
    local resources = collection ~= nil and collection.resources or nil
    if type(resources) == "table" then
        for _, count in pairs(resources) do
            collectedItems = collectedItems + math.max(0, math.floor(tonumber(count) or 0))
        end
    end
    local byMember = collection ~= nil and collection.byMember or nil
    if type(byMember) == "table" then
        for _, memberItems in pairs(byMember) do
            if type(memberItems) == "table" then
                local memberCount = 0
                for _, count in pairs(memberItems) do
                    memberCount = memberCount + math.max(0, math.floor(tonumber(count) or 0))
                end
                if memberCount > 0 then collectingMembers = collectingMembers + 1 end
            end
        end
    end
    team.collectedItems = collectedItems
    team.collectingMembers = collectingMembers
    team.memberCount = type(team.memberIds) == "table" and #team.memberIds or 0
    team.collectionProgress = team.memberCount > 0
        and math.max(0, math.min(1, collectingMembers / team.memberCount)) or 0
    team.statusLabel = team.state == "outbound" and "En route"
        or team.state == "awaiting_collection" and "At destination"
        or team.state == "collecting" and "Collecting supplies"
        or team.state == "returning" and "Returning"
        or team.state == "complete" and "Returned"
        or team.state == "blocked" and "Unable to complete"
        or tostring(team.state or "Unknown")
    return team
end

function KnoxPersistence.getAwayTeamForSurvivor(survivorId)
    local survivor = ensureSurvivorState(survivorId)
    local id = survivor ~= nil and survivor.duty ~= nil and survivor.duty.awayTeamId or nil
    return id ~= nil and KnoxPersistence.getAwayTeam(id) or nil
end

-- Creates a durable mission assignment. The caller must first hibernate/remove any
-- loaded bodies; this data operation deliberately does not fabricate a world result or
-- mutate their inventories.
local function validateAwayTeamInput(ownerKind, ownerId, memberIds, missionType, destination)
    if (ownerKind ~= "player" and ownerKind ~= "faction")
        or type(ownerId) ~= "string" or ownerId == ""
        or not AWAY_MISSION_TYPES[missionType]
        or type(destination) ~= "table"
        or tonumber(destination.x) == nil or tonumber(destination.y) == nil then
        return nil, "invalid_mission"
    end
    local members, seen = {}, {}
    for _, id in ipairs(memberIds or {}) do
        local survivor = ensureSurvivorState(id)
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        if type(id) ~= "string" or seen[id] or survivor == nil or survivor.alive == false
            or affiliation == nil or affiliation.kind ~= ownerKind
            or (ownerKind == "player" and affiliation.ownerId ~= ownerId)
            or (ownerKind == "faction" and affiliation.factionId ~= ownerId)
            or survivor.duty.mode == "away" or survivor.duty.eventId ~= nil then
            return nil, "invalid_member=" .. tostring(id)
        end
        seen[id] = true
        members[#members + 1] = id
    end
    if #members == 0 then
        return nil, "no_members"
    end
    return members, "valid"
end

local function derivedAwayReturnDestination(memberIds)
    local firstId = type(memberIds) == "table" and memberIds[1] or nil
    local survivor = firstId ~= nil and ensureSurvivorState(firstId) or nil
    local duty = survivor ~= nil and survivor.duty or nil
    if type(duty) ~= "table" or duty.mode ~= "base" or duty.baseId == nil then
        return nil
    end
    local base = KnoxPersistence.getBase(duty.baseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if type(area) ~= "table" or tonumber(area.minX) == nil
        or tonumber(area.minY) == nil then
        return nil
    end
    local width = math.max(1, math.floor(tonumber(area.maxX) ~= nil
        and tonumber(area.maxX) - tonumber(area.minX) + 1 or tonumber(area.width) or 1))
    local height = math.max(1, math.floor(tonumber(area.maxY) ~= nil
        and tonumber(area.maxY) - tonumber(area.minY) + 1 or tonumber(area.height) or 1))
    return {
        x = math.floor(tonumber(area.minX)) + math.floor((width - 1) / 2),
        y = math.floor(tonumber(area.minY)) + math.floor((height - 1) / 2),
        z = math.floor(tonumber(area.z) or 0),
        label = tostring(base.name or "Home Base"),
    }
end

-- Dispatchers validate this before taking a loaded shell down.  This protects
-- the identity/body handoff from ordinary bad owner, destination, or duty data;
-- the subsequent create call repeats the validation at the mutation boundary.
function KnoxPersistence.validateAwayTeam(ownerKind, ownerId, memberIds, missionType, destination)
    local members, result = validateAwayTeamInput(
        ownerKind, ownerId, memberIds, missionType, destination
    )
    return members ~= nil, result
end

local restoreAwayTeamDuties

function KnoxPersistence.createAwayTeam(
    ownerKind, ownerId, memberIds, missionType, destination,
    worldAgeHours, etaHours, returnDestination, dispatching
)
    local members, validation = validateAwayTeamInput(
        ownerKind, ownerId, memberIds, missionType, destination
    )
    if members == nil then
        return nil, validation
    end
    local data = root()
    local teamId = "away-" .. tostring(math.max(1, math.floor(data.nextAwayTeamId)))
    while data.awayTeams[teamId] ~= nil do
        data.nextAwayTeamId = data.nextAwayTeamId + 1
        teamId = "away-" .. tostring(data.nextAwayTeamId)
    end
    data.nextAwayTeamId = data.nextAwayTeamId + 1
    local departure = tonumber(worldAgeHours) or 0
    local eta = math.max(departure + 0.25, tonumber(etaHours) or (departure + 2))
    local returnPoint = returnDestination
    if returnPoint == nil then
        returnPoint = derivedAwayReturnDestination(members)
    end
    if type(returnDestination) == "table"
        and tonumber(returnDestination.x) ~= nil
        and tonumber(returnDestination.y) ~= nil then
        returnPoint = {
            x = math.floor(tonumber(returnDestination.x)),
            y = math.floor(tonumber(returnDestination.y)),
            z = math.floor(tonumber(returnDestination.z) or 0),
            label = tostring(returnDestination.label or "Return point"),
        }
    elseif type(returnPoint) == "table"
        and tonumber(returnPoint.x) ~= nil and tonumber(returnPoint.y) ~= nil then
        returnPoint = {
            x = math.floor(tonumber(returnPoint.x)),
            y = math.floor(tonumber(returnPoint.y)),
            z = math.floor(tonumber(returnPoint.z) or 0),
            label = tostring(returnPoint.label or "Return point"),
        }
    else
        returnPoint = nil
    end
    local team = {
        id = teamId,
        ownerKind = ownerKind,
        ownerId = ownerId,
        memberIds = members,
        missionType = missionType,
        destination = {
            x = math.floor(tonumber(destination.x)),
            y = math.floor(tonumber(destination.y)),
            z = math.floor(tonumber(destination.z) or 0),
            label = tostring(destination.label or "Unknown destination"),
        },
        -- A dispatching team has durable roster ownership but is not a mission
        -- until every native body removal has been acknowledged. This lets the
        -- runtime abort a partial handoff without claiming the team departed.
        state = dispatching == true and "dispatching" or "outbound",
        departedAtHours = departure,
        etaHours = eta,
        returnDestination = returnPoint,
        result = nil,
        dispatch = dispatching == true and { removedMemberIds = {} } or nil,
    }
    data.awayTeams[teamId] = team
    for _, id in ipairs(members) do
        local survivor = ensureSurvivorState(id)
        if survivor.duty.mode == "base" then
            requeueClaimsForSurvivor(id, survivor.duty.baseId, "away_mission")
        end
        survivor.duty = {
            mode = "away",
            order = "mission",
            awayTeamId = teamId,
            ownerId = ownerId,
            previousDuty = copySerializable(survivor.duty),
            changedAtHours = departure,
            revision = (tonumber(survivor.duty.revision) or 0) + 1,
        }
    end
    return copySerializable(team), "created"
end

-- Prepares durable roster/duty ownership before any native shell is removed.
-- The runtime must either finalize this after every removal is acknowledged or
-- abort it, restoring the members' previous duties.
function KnoxPersistence.prepareAwayTeam(
    ownerKind, ownerId, memberIds, missionType, destination,
    worldAgeHours, etaHours, returnDestination
)
    return KnoxPersistence.createAwayTeam(
        ownerKind, ownerId, memberIds, missionType, destination,
        worldAgeHours, etaHours, returnDestination, true
    )
end

function KnoxPersistence.recordAwayTeamDispatchRemoval(teamId, survivorId)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if type(team) ~= "table" or team.state ~= "dispatching" then
        return false, "dispatch_not_pending"
    end
    local member, known = false, false
    for _, id in ipairs(team.memberIds or {}) do
        if id == survivorId then member = true break end
    end
    if not member then return false, "not_team_member" end
    team.dispatch = type(team.dispatch) == "table" and team.dispatch
        or { removedMemberIds = {} }
    team.dispatch.removedMemberIds = type(team.dispatch.removedMemberIds) == "table"
        and team.dispatch.removedMemberIds or {}
    for _, id in ipairs(team.dispatch.removedMemberIds) do
        if id == survivorId then known = true break end
    end
    if not known then table.insert(team.dispatch.removedMemberIds, survivorId) end
    return true, "recorded"
end

function KnoxPersistence.finalizeAwayTeamDispatch(teamId, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if type(team) ~= "table" or team.state ~= "dispatching" then
        return nil, "dispatch_not_pending"
    end
    local removed = type(team.dispatch) == "table" and team.dispatch.removedMemberIds or {}
    local seen = {}
    for _, id in ipairs(removed) do seen[id] = true end
    for _, id in ipairs(team.memberIds or {}) do
        if not seen[id] then return nil, "removal_unconfirmed=" .. tostring(id) end
    end
    team.state = "outbound"
    team.departedAtHours = tonumber(worldAgeHours) or team.departedAtHours
    team.dispatch = nil
    return copySerializable(team), "dispatched"
end

function KnoxPersistence.abortAwayTeamDispatch(teamId, reason, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if type(team) ~= "table" or team.state ~= "dispatching" then
        return nil, "dispatch_not_pending"
    end
    team.state = "blocked"
    team.blockedAtHours = tonumber(worldAgeHours) or 0
    team.result = {
        kind = "dispatch_incomplete",
        reason = tostring(reason or "native_removal_unconfirmed"),
        removedMemberIds = copySerializable(type(team.dispatch) == "table"
            and team.dispatch.removedMemberIds or {}),
    }
    restoreAwayTeamDuties(team, worldAgeHours)
    return copySerializable(team), "aborted"
end

local function blockedDispatchRemovedMember(team, survivorId)
    if type(team) ~= "table" or team.state ~= "blocked"
        or type(team.result) ~= "table" or team.result.kind ~= "dispatch_incomplete" then
        return false
    end
    for _, id in ipairs(team.result.removedMemberIds or {}) do
        if id == survivorId then return true end
    end
    return false
end

-- A native body acknowledged as removed during a failed dispatch stays owned
-- by its hibernated ledger until normal record restoration succeeds. Returning
-- the blocked team here is read-only: no body is invented and no duty changes
-- until the runtime has actually registered that restored shell.
function KnoxPersistence.getBlockedAwayTeamRecovery(survivorId)
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    local duty = survivor ~= nil and survivor.duty or nil
    if survivor == nil or survivor.alive == false or type(duty) ~= "table"
        or duty.mode ~= "away" or type(duty.awayTeamId) ~= "string" then
        return nil
    end
    local team = root().awayTeams[duty.awayTeamId]
    return blockedDispatchRemovedMember(team, survivorId) and copySerializable(team) or nil
end

-- Called only after canonical record restoration has produced and registered a
-- real body. It releases the blocked-away hold without changing identity,
-- inventory/equipment, needs, affiliation, or the historical blocked record.
function KnoxPersistence.recoverBlockedAwayTeamMember(teamId, survivorId, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    if survivor == nil or survivor.alive == false
        or not blockedDispatchRemovedMember(team, survivorId) then
        return false, "blocked_recovery_unavailable"
    end
    local duty = survivor.duty
    if type(duty) ~= "table" or duty.mode ~= "away" or duty.awayTeamId ~= teamId then
        return false, "blocked_recovery_not_owned"
    end
    local previous = duty.previousDuty
    survivor.duty = type(previous) == "table" and copySerializable(previous) or {
        mode = "autonomous", order = "survive", revision = 0,
    }
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    team.result.recoveredMemberIds = type(team.result.recoveredMemberIds) == "table"
        and team.result.recoveredMemberIds or {}
    for _, id in ipairs(team.result.recoveredMemberIds) do
        if id == survivorId then return true, "already_recovered" end
    end
    table.insert(team.result.recoveredMemberIds, survivorId)
    return true, "recovered"
end

function KnoxPersistence.getAwayTeamReturnDestination(teamId)
    local team = KnoxPersistence.getAwayTeam(teamId)
    return team ~= nil and copySerializable(team.returnDestination) or nil
end

restoreAwayTeamDuties = function(team, worldAgeHours)
    for _, id in ipairs(team.memberIds or {}) do
        local survivor = ensureSurvivorState(id)
        -- Death is authoritative even if it races the mission timeout.  Do not
        -- resurrect a corpse's old base/companion ownership while releasing
        -- the living members of the team.
        if survivor.alive == false then
            survivor.duty = {
                mode = "deceased", order = "none",
                changedAtHours = tonumber(worldAgeHours) or 0,
                revision = (tonumber(survivor.duty ~= nil
                    and survivor.duty.revision) or 0) + 1,
            }
        elseif not blockedDispatchRemovedMember(team, id) then
            local previous = survivor.duty.previousDuty
            survivor.duty = type(previous) == "table" and previous or {
                mode = "autonomous", order = "survive", revision = 0,
            }
            survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
            survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
        end
    end
end

-- Resource missions wait for a loaded-world executor to transfer real items.
-- Never let a missing/remote destination hold the members in away duty forever.
-- This is a failure boundary only; it creates no loot and leaves a later
-- dispatch free to try again with a new mission.
local AWAY_COLLECTION_TIMEOUT_HOURS = 72
local AWAY_RETURN_TIMEOUT_HOURS = 72

local function validAwayMember(team, survivorId)
    if team == nil or type(survivorId) ~= "string" then
        return false
    end
    for _, id in ipairs(team.memberIds or {}) do
        if id == survivorId then return true end
    end
    return false
end

-- The live-world executor calls this only after an ordinary inventory transfer
-- has succeeded.  The ledger deliberately accepts item *types*, never counts
-- or creates an item by itself, so an away result can be audited back to real
-- container movement rather than becoming a free-resource generator.
function KnoxPersistence.recordAwayTeamCollection(teamId, survivorId, itemTypes, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if not validAwayMember(team, survivorId) or team.state ~= "collecting"
        or type(itemTypes) ~= "table" then
        return nil, "invalid_collection"
    end
    team.collection = type(team.collection) == "table" and team.collection or {
        resources = {}, byMember = {},
    }
    team.collection.resources = type(team.collection.resources) == "table"
        and team.collection.resources or {}
    team.collection.byMember = type(team.collection.byMember) == "table"
        and team.collection.byMember or {}
    local member = team.collection.byMember[survivorId] or {}
    local accepted = 0
    for _, itemType in ipairs(itemTypes) do
        if type(itemType) == "string" and itemType ~= "" and #itemType <= 160 then
            member[itemType] = (tonumber(member[itemType]) or 0) + 1
            team.collection.resources[itemType] = (tonumber(team.collection.resources[itemType]) or 0) + 1
            accepted = accepted + 1
        end
    end
    -- A member that searched a valid destination and found nothing is still
    -- complete.  Marking the collection acknowledgement separately from the
    -- item ledger prevents a multi-member team from entering return early just
    -- because one member found a single item.
    member.collected = true
    member.collectedAtHours = tonumber(worldAgeHours) or 0
    team.collection.byMember[survivorId] = member
    team.collection.lastCollectedAtHours = tonumber(worldAgeHours) or 0
    return copySerializable(team.collection), accepted > 0 and "recorded" or "no_items"
end

function KnoxPersistence.awayTeamCollectionReady(teamId)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if team == nil or team.state ~= "collecting" then return false end
    local byMember = type(team.collection) == "table"
        and type(team.collection.byMember) == "table"
        and team.collection.byMember or {}
    for _, id in ipairs(team.memberIds or {}) do
        if type(byMember[id]) ~= "table" or byMember[id].collected ~= true then
            return false
        end
    end
    return #(team.memberIds or {}) > 0
end

function KnoxPersistence.beginAwayTeamCollection(teamId, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if team == nil or team.state ~= "awaiting_collection" then
        return nil, "not_awaiting_collection"
    end
    team.state = "collecting"
    team.collectionStartedAtHours = tonumber(worldAgeHours) or 0
    return copySerializable(team), "collecting"
end

-- The live executor calls this after it has finished searching the destination
-- and before members begin the ordinary return trip. Keeping this transition
-- explicit prevents a resource mission from appearing complete while its
-- participants are still away, and gives loaded movement one durable handoff
-- point without simulating travel or inventing supplies.
function KnoxPersistence.beginAwayTeamReturn(teamId, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if team == nil or team.state ~= "collecting" then
        return nil, "not_collecting"
    end
    if type(team.collection) ~= "table" then
        return nil, "collection_not_recorded"
    end
    if not KnoxPersistence.awayTeamCollectionReady(teamId) then
        return nil, "members_pending_collection"
    end
    team.state = "returning"
    team.returnStartedAtHours = tonumber(worldAgeHours) or 0
    return copySerializable(team), "returning"
end

-- Completion is intentionally a separate transition from collection.  A
-- transfer at the destination is not enough: the live executor must return
-- the team to its owner before this restores their ordinary duties.
function KnoxPersistence.completeAwayTeamMember(teamId, survivorId, success, reason, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if not validAwayMember(team, survivorId)
        -- Collection and return are separate ownership phases.  Recording an
        -- item at the destination must never restore the member's old duty;
        -- completion is only legal once the live executor has handed the team
        -- back to its owner and entered the explicit returning state.
        or team.state ~= "returning" then
        return nil, "invalid_completion"
    end
    team.memberResults = type(team.memberResults) == "table" and team.memberResults or {}
    team.memberResults[survivorId] = {
        success = success == true,
        reason = tostring(reason or (success and "returned" or "failed")),
        completedAtHours = tonumber(worldAgeHours) or 0,
    }
    local complete = true
    for _, id in ipairs(team.memberIds or {}) do
        if team.memberResults[id] == nil then complete = false; break end
    end
    if not complete then
        return copySerializable(team), "member_recorded"
    end
    team.state = "complete"
    team.completedAtHours = tonumber(worldAgeHours) or 0
    team.result = {
        kind = "resource_run",
        destination = copySerializable(team.destination),
        resources = copySerializable(team.collection ~= nil and team.collection.resources or {}),
        members = copySerializable(team.memberResults),
    }
    restoreAwayTeamDuties(team, worldAgeHours)
    return copySerializable(team), "complete"
end

-- Scouting has an explicit non-resource result. Resource missions advance only
-- to an awaiting-collection state; no item is generated and duty ownership is
-- retained until a live executor transfers real loot and returns the team.
function KnoxPersistence.advanceAwayTeams(worldAgeHours)
    local now, changed = tonumber(worldAgeHours) or 0, 0
    for _, team in pairs(root().awayTeams) do
        if type(team) == "table" and team.state == "outbound"
            and now >= (tonumber(team.etaHours) or math.huge) then
            if team.missionType == "scout" then
                team.state = "complete"
                team.completedAtHours = now
                team.result = {
                    kind = "scouted",
                    destination = copySerializable(team.destination),
                    resources = {},
                }
                restoreAwayTeamDuties(team, now)
            else
                team.state = "awaiting_collection"
                team.arrivedAtHours = now
                team.result = {
                    kind = "awaiting_live_collection",
                    destination = copySerializable(team.destination),
                    resources = {},
                }
            end
            changed = changed + 1
        elseif type(team) == "table" and team.state == "awaiting_collection"
            and now >= (tonumber(team.arrivedAtHours) or now)
                + AWAY_COLLECTION_TIMEOUT_HOURS then
            team.state = "blocked"
            team.blockedAtHours = now
            team.result = {
                kind = "resource_run_expired",
                destination = copySerializable(team.destination),
                resources = copySerializable(team.collection ~= nil
                    and team.collection.resources or {}),
                reason = "collection_timeout",
            }
            restoreAwayTeamDuties(team, now)
            changed = changed + 1
            print("[KnoxSurvivors][AwayTeams] expired id=" .. tostring(team.id)
                .. " reason=collection_timeout")
        elseif type(team) == "table" and team.state == "returning"
            and now >= (tonumber(team.returnStartedAtHours) or now)
                + AWAY_RETURN_TIMEOUT_HOURS then
            -- A returning team owns its members until every live handoff is
            -- acknowledged. If one member disappears during unload/restore,
            -- do not leave the whole settlement duty leased forever. Record
            -- the missing return as a bounded failure, preserve any real
            -- collected ledger, and restore the prior duties once.
            team.memberResults = type(team.memberResults) == "table"
                and team.memberResults or {}
            for _, id in ipairs(team.memberIds or {}) do
                if team.memberResults[id] == nil then
                    team.memberResults[id] = {
                        success = false,
                        reason = "return_timeout",
                        completedAtHours = now,
                    }
                end
            end
            team.state = "blocked"
            team.blockedAtHours = now
            team.result = {
                kind = "resource_run_return_expired",
                destination = copySerializable(team.destination),
                resources = copySerializable(team.collection ~= nil
                    and team.collection.resources or {}),
                members = copySerializable(team.memberResults),
                reason = "return_timeout",
            }
            restoreAwayTeamDuties(team, now)
            changed = changed + 1
            print("[KnoxSurvivors][AwayTeams] expired id=" .. tostring(team.id)
                .. " reason=return_timeout")
        end
    end
    return changed
end

function KnoxPersistence.isIndependentSurvivor(id)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "independent" then
        return false
    end
    local data = root()
    for _, group in pairs(data.travelGroups) do
        for _, memberId in ipairs(group.memberIds or {}) do
            if memberId == id then
                return false
            end
        end
    end
    for _, faction in pairs(data.factions) do
        for _, memberId in ipairs(faction.memberIds or {}) do
            if memberId == id then
                return false
            end
        end
    end
    return true
end

function KnoxPersistence.setSurvivorIndependent(id, reason, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil then
        return false
    end
    local nextRevision = (tonumber(survivor.duty.revision) or 0) + 1
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "left_base")
    end
    local previousFactionId = survivor.affiliation.factionId
    if previousFactionId ~= nil and KnoxPersistence.removeFactionMember ~= nil then
        KnoxPersistence.removeFactionMember(previousFactionId, id)
    end
    if KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(id)
    end
    for factionId, candidate in pairs(root().factions) do
        local listed = false
        for _, memberId in ipairs(candidate ~= nil and candidate.memberIds or {}) do
            listed = listed or memberId == id
        end
        if listed then
            KnoxPersistence.removeFactionMember(factionId, id, true)
        end
    end
    survivor.affiliation = {
        kind = "independent",
        ownerId = nil,
        changedAtHours = tonumber(worldAgeHours) or 0,
        reason = tostring(reason or "released"),
    }
    survivor.duty = {
        mode = "autonomous",
        order = "survive",
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = nextRevision,
    }
    return true
end

function KnoxPersistence.setPlayerCompanion(id, playerId, order, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return false, "invalid_identity"
    end
    if survivor.record == nil then
        return false, "survivor_not_persisted"
    end
    if survivor.affiliation.kind ~= "independent"
        and not (survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId) then
        return false, "already_affiliated"
    end
    local existingGroup = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(id) or nil
    if existingGroup ~= nil then
        if survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId then
            KnoxPersistence.removeTravelGroupMember(id)
        else
            return false, "already_with_group"
        end
    end
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "recalled_as_companion")
    end
    local workPriorities = normalizeWorkPreferences(survivor.duty.workPriorities)
    -- Player ownership is authoritative. Remove stale copies left in NPC rosters
    -- before assigning the player faction so later faction maintenance cannot
    -- absorb a companion back into an autonomous group.
    if KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(id)
    end
    for factionId, candidate in pairs(root().factions) do
        local listed = false
        for _, memberId in ipairs(candidate ~= nil and candidate.memberIds or {}) do
            listed = listed or memberId == id
        end
        local belongsToThisPlayer = candidate ~= nil and candidate.kind == "player"
            and candidate.ownerPlayerId == playerId
        if candidate ~= nil and listed and not belongsToThisPlayer then
            KnoxPersistence.removeFactionMember(factionId, id, true)
        end
    end
    local faction = KnoxPersistence.ensurePlayerFaction(playerId, worldAgeHours)
    if faction == nil then
        return false, "player_faction_failed"
    end
    survivor.affiliation = {
        kind = "player",
        ownerId = playerId,
        factionId = faction.id,
        joinedAtHours = survivor.affiliation.joinedAtHours
            or tonumber(worldAgeHours)
            or 0,
    }
    survivor.duty = {
        mode = "companion",
        order = order == "hold" and "hold" or "follow",
        workPriorities = workPriorities,
        followerFormation = survivor.duty.followerFormation,
        followerSpacing = survivor.duty.followerSpacing,
        combatStance = "defensive",
        ownerId = playerId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    survivor.lifeIntent = nil
    KnoxPersistence.addFactionMember(faction.id, id, worldAgeHours)
    return true, "companion"
end

function KnoxPersistence.setPlayerBaseResident(id, playerId, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(playerId) ~= "string" or playerId == ""
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId then
        return false, "not_player_survivor"
    end
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
        return false, "invalid_player_base"
    end
    if survivor.duty.mode == "base" and survivor.duty.baseId ~= baseId then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "base_changed")
    end
    local workPriorities = normalizeWorkPreferences(survivor.duty.workPriorities)
    survivor.duty = {
        mode = "base",
        order = "available",
        workPriorities = workPriorities,
        jobPreference = survivor.duty ~= nil and survivor.duty.jobPreference or "auto",
        followerFormation = survivor.duty.followerFormation,
        followerSpacing = survivor.duty.followerSpacing,
        ownerId = playerId,
        baseId = baseId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    survivor.lifeIntent = nil
    return true, "base_resident"
end

function KnoxPersistence.setFactionBaseResident(id, factionId, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local faction = KnoxPersistence.getFaction(factionId)
    local base = KnoxPersistence.getBase(baseId)
    if survivor == nil or faction == nil or faction.kind == "player"
        or survivor.alive == false
        or survivor.eventManaged == true
        or type(survivor.departure) == "table"
            and (survivor.departure.status == "pending"
                or survivor.departure.status == "departed")
        or KnoxPersistence.getAwayTeamForSurvivor(id) ~= nil
        or base == nil or base.ownerKind ~= "faction" or base.ownerId ~= factionId
        or survivor.affiliation.factionId ~= factionId then
        return false, "not_faction_survivor"
    end
    if survivor.duty.mode == "base" and survivor.duty.baseId == baseId then
        return true, "existing"
    end
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "base_changed")
    end
    local bed = survivor.policies ~= nil and survivor.policies.assignedBed or nil
    if type(bed) == "table" and bed.autoFactionId ~= nil
        and (bed.autoFactionId ~= factionId or bed.autoBaseId ~= baseId) then
        survivor.policies.assignedBed = nil
    end
    survivor.duty = {
        mode = "base",
        order = "available",
        jobPreference = survivor.duty ~= nil and survivor.duty.jobPreference or "auto",
        ownerId = factionId,
        baseId = baseId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    survivor.lifeIntent = nil
    return true, "base_resident"
end

function KnoxPersistence.getBaseResidentIds(baseId)
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if survivor ~= nil and survivor.duty ~= nil
            and survivor.duty.mode == "base" and survivor.duty.baseId == baseId then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

-- Read-only player-facing status for a base resident. The task board remains
-- the owner of claims; this helper only projects its persisted state so the
-- Notebook can describe both loaded and off-screen residents consistently.
function KnoxPersistence.getBaseResidentWorkStatus(id, baseId)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    if survivor == nil or survivor.duty == nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return nil
    end
    local base = KnoxPersistence.getBase(baseId)
    if base ~= nil then
        for _, task in pairs(base.tasks or {}) do
            if type(task) == "table" and task.state == "claimed"
                and task.claimedBy == id then
                local offscreenHours = math.max(0,
                    tonumber(task.offscreenWorkHours) or 0)
                return {
                    state = "claimed",
                    taskType = canonicalTaskType(task.type),
                    offscreen = offscreenHours > 0,
                    offscreenHours = offscreenHours,
                }
            end
        end
    end
    -- An explicit request remains persisted while its concrete run is active.
    -- Present the current work owner first instead of describing an in-flight
    -- resident as merely waiting on the original request.
    if type(survivor.duty.activeSupplyRun) == "table" then
        return {
            state = "supply_run",
            taskType = canonicalOrder(survivor.duty.activeSupplyRun.kind),
            startedAtHours = tonumber(survivor.duty.activeSupplyRun.startedAtHours),
        }
    end
    if type(survivor.duty.baseSupplyOrder) == "table" then
        return {
            state = "supply_order",
            taskType = canonicalOrder(survivor.duty.baseSupplyOrder.kind),
            attempts = math.max(0,
                math.floor(tonumber(survivor.duty.baseSupplyOrder.attempts) or 0)),
        }
    end
    if survivor.duty.jobPreference == "rest" then
        return { state = "resting" }
    end
    local lastJob = tostring(survivor.duty.lastJobType or "")
    if lastJob ~= "" then
        return {
            state = "idle",
            taskType = canonicalTaskType(lastJob),
            completedAtHours = tonumber(survivor.duty.lastJobAtHours),
        }
    end
    return { state = "idle" }
end

-- RimWorld-style duty schedule, backend model for the schedule UI.
-- duty.schedule is a list of { from = hour, to = hour, assignment } with
-- hours on 0-24 (from > to means overnight) and assignment one of sleep,
-- work, patrol, guard, recreation or anything. First matching window wins.
-- Nil schedule means anything (current behavior). The scheduler honors
-- sleep and recreation as no-work windows; work, patrol and guard defer
-- to the existing preference, skill and rotation machinery, with patrol
-- and guard biasing election toward watch tasks.
local SCHEDULE_ASSIGNMENTS = {
    sleep = true, work = true, patrol = true, guard = true,
    recreation = true, anything = true,
}

local function validScheduleWindow(window)
    if type(window) ~= "table" then return false end
    local from, to = tonumber(window.from), tonumber(window.to)
    if from == nil or to == nil or from < 0 or from > 24
        or to < 0 or to > 24 then
        return false
    end
    return SCHEDULE_ASSIGNMENTS[window.assignment] == true
end

function KnoxPersistence.validDutySchedule(schedule)
    if type(schedule) ~= "table" or #schedule < 1 or #schedule > 12 then
        return false
    end
    for _, window in ipairs(schedule) do
        if not validScheduleWindow(window) then return false end
    end
    return true
end

function KnoxPersistence.defaultDutySchedule()
    return {
        { from = 22, to = 6, assignment = "sleep" },
        { from = 6, to = 8, assignment = "anything" },
        { from = 8, to = 12, assignment = "work" },
        { from = 12, to = 13, assignment = "recreation" },
        { from = 13, to = 18, assignment = "work" },
        { from = 18, to = 20, assignment = "recreation" },
        { from = 20, to = 22, assignment = "anything" },
    }
end

function KnoxPersistence.scheduleAssignmentFor(schedule, hour)
    if type(schedule) ~= "table" then return "anything" end
    local h = tonumber(hour)
    if h == nil then return "anything" end
    h = h % 24
    for _, window in ipairs(schedule) do
        local from, to = tonumber(window.from), tonumber(window.to)
        if from ~= nil and to ~= nil and SCHEDULE_ASSIGNMENTS[window.assignment] then
            if from <= to then
                if h >= from and h < to then return window.assignment end
            elseif h >= from or h < to then
                return window.assignment
            end
        end
    end
    return "anything"
end

-- RimWorld-style 24-hour strip transforms. The schedule tab paints one
-- assignment per hour (index 1 = hour 0 through index 24 = hour 23) and
-- these pure helpers convert to/from the window backend above, which stays
-- the sole persisted authority. Unknown hours sanitize to anything.
function KnoxPersistence.dutyWindowsToHours(schedule)
    local hours = {}
    for hour = 0, 23 do
        hours[hour + 1] = KnoxPersistence.scheduleAssignmentFor(schedule, hour)
    end
    return hours
end

-- Plain-words summary backing for the schedule UI: hours per assignment in
-- a 24-entry strip. Unknown entries count as anything so the totals
-- always add to 24.
function KnoxPersistence.dutyHourCounts(hours)
    local counts = { sleep = 0, work = 0, patrol = 0, guard = 0,
        recreation = 0, anything = 0 }
    for hour = 1, 24 do
        local assignment = type(hours) == "table" and hours[hour] or nil
        if counts[assignment] == nil then assignment = "anything" end
        counts[assignment] = counts[assignment] + 1
    end
    return counts
end

function KnoxPersistence.hoursToDutyWindows(hours)    local normalized = {}
    for hour = 0, 23 do
        local assignment = type(hours) == "table" and hours[hour + 1] or nil
        if SCHEDULE_ASSIGNMENTS[assignment] ~= true then assignment = "anything" end
        normalized[hour + 1] = assignment
    end
    local runs = {}
    local start, current = 0, normalized[1]
    for hour = 1, 23 do
        if normalized[hour + 1] ~= current then
            runs[#runs + 1] = { from = start, to = hour, assignment = current }
            start, current = hour, normalized[hour + 1]
        end
    end
    runs[#runs + 1] = { from = start, to = 24, assignment = current }
    -- Overnight merge: hour 23 and hour 0 sharing an assignment rejoin
    -- into one wrapping window instead of two stubs.
    if #runs > 1 and runs[1].assignment == runs[#runs].assignment then
        local last = runs[#runs]
        runs[1] = { from = last.from, to = runs[1].to, assignment = runs[1].assignment }
        runs[#runs] = nil
    end
    if #runs == 1 then
        if runs[1].assignment == "anything" then return nil end
        return { { from = 0, to = 24, assignment = runs[1].assignment } }
    end
    -- Pathological striping (alternating hours) can exceed the 12-window
    -- backend cap; absorb the shortest run into its predecessor rather
    -- than failing the save.
    while #runs > 12 do
        local victim, shortest = 2, math.huge
        for index = 2, #runs do
            local length = runs[index].to - runs[index].from
            if runs[index].to < runs[index].from then
                length = length + 24
            end
            if length < shortest then victim, shortest = index, length end
        end
        runs[victim - 1].to = runs[victim].to
        table.remove(runs, victim)
    end
    return runs
end

-- Shape validation only; ownership gating belongs to the future schedule
-- tab callers. The scheduler lazy-ensures NPC defaults through here.
function KnoxPersistence.setDutySchedule(id, schedule, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false then return false end
    if schedule ~= nil and not KnoxPersistence.validDutySchedule(schedule) then
        return false
    end
    if survivor.duty == nil then return false end
    survivor.duty.schedule = schedule ~= nil
        and copySerializable(schedule) or nil
    if schedule == nil then survivor.duty.scheduleAuto = nil end
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- One-time default for NPC groups/factions (by skill-neutral clock; the
-- work windows still defer to profession/skill/rotation). Player survivors
-- keep nil (anything) until the schedule tab writes an explicit one.
function KnoxPersistence.ensureAutoDutySchedule(id, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or survivor.duty == nil or survivor.duty.schedule ~= nil then
        return false
    end
    survivor.duty.schedule = KnoxPersistence.defaultDutySchedule()
    survivor.duty.scheduleAuto = true
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.getDutySchedule(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    local schedule = survivor ~= nil and survivor.duty ~= nil
        and survivor.duty.schedule or nil
    return type(schedule) == "table" and copySerializable(schedule) or nil
end

function KnoxPersistence.setBaseJobPreference(id, playerId, baseId, preference, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    local normalizedPreference = preference
    if catalog ~= nil then
        normalizedPreference = catalog.normalizeBasePreference ~= nil
            and catalog.normalizeBasePreference(preference)
            or (catalog.normalize ~= nil and catalog.normalize(preference) or preference)
    end
    local allowed = (catalog ~= nil
        and catalog.isBasePreference ~= nil
        and catalog.isBasePreference(normalizedPreference) == true)
        or normalizedPreference == "auto" or normalizedPreference == "guard" or normalizedPreference == "patrol"
        or normalizedPreference == "cooking" or normalizedPreference == "farming" or normalizedPreference == "woodwork" or normalizedPreference == "hauling"
        or normalizedPreference == "barricade"
        or normalizedPreference == "repair" or normalizedPreference == "rest"
    if survivor == nil or survivor.alive == false or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.eventId ~= nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    survivor.duty.jobPreference = normalizedPreference
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Player-facing schedule writer: same ownership gating as job preference.
-- A nil schedule clears back to "anything". The raw setDutySchedule stays
-- for the scheduler's internal NPC use.
function KnoxPersistence.setBaseDutySchedule(id, playerId, baseId, schedule, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false then return false end
    if schedule ~= nil and not KnoxPersistence.validDutySchedule(schedule) then
        return false
    end
    if survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.eventId ~= nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    return KnoxPersistence.setDutySchedule(id, schedule, worldAgeHours)
end

-- Four-state preferences are a sparse projection over the existing base task
-- groups. Missing entries mean Normal; old 1-4/false values were normalized
-- when the save root was loaded. This remains inert outside player base duty.
function KnoxPersistence.validWorkPreferences(map)
    if type(map) ~= "table" then return false end
    for key, value in pairs(map) do
        if WORK_PREFERENCE_GROUPS[key] ~= true
            or normalizeWorkPreference(value) == nil then
            return false
        end
    end
    return true
end

function KnoxPersistence.getWorkPreference(id, group)
    if WORK_PREFERENCE_GROUPS[group] ~= true then return "normal" end
    local survivor = ensureSurvivorState(id)
    local duty = survivor ~= nil and survivor.duty or nil
    local base = duty ~= nil and KnoxPersistence.getBase ~= nil
        and KnoxPersistence.getBase(duty.baseId) or nil
    if type(duty) ~= "table" or duty.mode ~= "base"
        or survivor.affiliation == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= duty.ownerId
        or base == nil or base.ownerKind ~= "player"
        or base.ownerId ~= survivor.affiliation.ownerId then
        return "normal"
    end
    local map = normalizeWorkPreferences(duty.workPriorities)
    return map ~= nil and map[group] or "normal"
end

function KnoxPersistence.getWorkPreferences(id)
    local preferences = {}
    for group in pairs(WORK_PREFERENCE_GROUPS) do
        preferences[group] = KnoxPersistence.getWorkPreference(id, group)
    end
    return preferences
end

function KnoxPersistence.setBaseWorkPreferences(id, playerId, baseId, map, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false then return false end
    if map ~= nil and not KnoxPersistence.validWorkPreferences(map) then
        return false
    end
    if survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.eventId ~= nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    local stored = map ~= nil and normalizeWorkPreferences(map) or nil
    survivor.duty.workPriorities = stored
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Keep the old entry points available to local scripts and older UI callers;
-- the stored representation and visible controls now use the four states.
KnoxPersistence.validWorkPriorities = KnoxPersistence.validWorkPreferences
KnoxPersistence.getWorkPriorities = KnoxPersistence.getWorkPreferences
KnoxPersistence.setBaseWorkPriorities = KnoxPersistence.setBaseWorkPreferences

-- Per-resident loot-run permission. Residents stay home unless the player
-- explicitly allows loot runs for them; the automatic shortage election
-- only drafts residents carrying this flag.
function KnoxPersistence.setResidentLootRuns(id, playerId, baseId, allowed, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.eventId ~= nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    survivor.duty.allowLootRuns = allowed == true
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.setBaseSupplyOrder(id, playerId, baseId, kind, worldAgeHours, durationHours)
    local survivor = ensureSurvivorState(id)
    local normalized = canonicalOrder(kind)
    local now = math.max(0, tonumber(worldAgeHours) or 0)
    local duration = math.max(1, tonumber(durationHours) or 24)
    if survivor == nil or survivor.alive == false
        or not BASE_SUPPLY_ORDER_KINDS[normalized]
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "base"
        or survivor.duty.baseId ~= baseId then
        return false
    end
    survivor.duty.baseSupplyOrder = {
        kind = normalized,
        issuedAtHours = now,
        expiresAtHours = now + duration,
        attempts = 0,
    }
    -- A replacement player order supersedes an older in-flight supply search.
    -- The loaded controller receives the duty revision and releases its
    -- transient movement/action ownership before starting the new request.
    survivor.duty.activeSupplyRun = nil
    survivor.duty.changedAtHours = now
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.recordBaseSupplyOrderAttempt(id, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local request = survivor ~= nil and survivor.duty ~= nil
        and survivor.duty.baseSupplyOrder or nil
    if survivor == nil or survivor.alive == false or type(request) ~= "table"
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId
        or not BASE_SUPPLY_ORDER_KINDS[request.kind] then
        return nil
    end
    request.attempts = math.max(0, math.floor(tonumber(request.attempts) or 0)) + 1
    request.lastAttemptAtHours = tonumber(worldAgeHours) or 0
    return request.attempts
end

-- Persist only settlement-level rotation history here. The loaded controller
-- still owns searches, movement, transfers, and their temporary action state.
-- Recording attempts as well as successful collections prevents one resident
-- from monopolizing an empty or dangerous search route after its claim expires.
function KnoxPersistence.recordBaseSupplyRun(id, baseId, kind, outcome, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local normalized = canonicalOrder(kind)
    if survivor == nil or survivor.alive == false
        or survivor.duty == nil or survivor.duty.mode ~= "base"
        or survivor.duty.baseId ~= baseId
        or survivor.duty.eventId ~= nil
        or not BASE_SUPPLY_ORDER_KINDS[normalized] then
        return false
    end
    survivor.duty.lastSupplyRunAtHours = math.max(0, tonumber(worldAgeHours) or 0)
    survivor.duty.lastSupplyKind = normalized
    survivor.duty.lastSupplyOutcome = type(outcome) == "string" and outcome ~= ""
        and outcome or "attempted"
    return true
end

function KnoxPersistence.beginBaseSupplyRun(id, baseId, kind, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local normalized = canonicalOrder(kind)
    if survivor == nil or survivor.alive == false
        or survivor.duty == nil or survivor.duty.mode ~= "base"
        or survivor.duty.baseId ~= baseId
        or survivor.duty.eventId ~= nil
        or not BASE_SUPPLY_ORDER_KINDS[normalized] then
        return false
    end
    local current = survivor.duty.activeSupplyRun
    if type(current) == "table" and current.kind == normalized then
        return true
    end
    local now = math.max(0, tonumber(worldAgeHours) or 0)
    survivor.duty.activeSupplyRun = {
        kind = normalized,
        startedAtHours = now,
    }
    return KnoxPersistence.recordBaseSupplyRun(
        id, baseId, normalized, "started", now
    )
end

function KnoxPersistence.finishBaseSupplyRun(id, baseId, kind, outcome, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local normalized = canonicalOrder(kind)
    if survivor == nil or survivor.duty == nil
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    local active = survivor.duty.activeSupplyRun
    if type(active) == "table" and normalized ~= nil
        and canonicalOrder(active.kind) ~= normalized then
        return false
    end
    survivor.duty.activeSupplyRun = nil
    return KnoxPersistence.recordBaseSupplyRun(
        id,
        baseId,
        normalized or (type(active) == "table" and active.kind or nil),
        outcome,
        worldAgeHours
    )
end

function KnoxPersistence.clearBaseSupplyOrder(id, playerId, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "base"
        or (baseId ~= nil and survivor.duty.baseId ~= baseId) then
        return false
    end
    if survivor.duty.baseSupplyOrder == nil then return true end
    local clearedKind = canonicalOrder(survivor.duty.baseSupplyOrder.kind)
    survivor.duty.baseSupplyOrder = nil
    if type(survivor.duty.activeSupplyRun) == "table"
        and canonicalOrder(survivor.duty.activeSupplyRun.kind) == clearedKind then
        survivor.duty.activeSupplyRun = nil
    end
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Read-only copy of a resident's durable supply order for UI rows.
-- Nil when none is active.
function KnoxPersistence.getBaseSupplyOrder(id)
    local survivor = ensureSurvivorState(id)
    local order = survivor ~= nil and survivor.duty ~= nil
        and survivor.duty.baseSupplyOrder or nil
    if type(order) ~= "table" then return nil end
    return copySerializable(order)
end

function KnoxPersistence.updateCompanionOrder(id, playerId, order, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    local allowed = (catalog ~= nil
        and catalog.isPrimaryOrder ~= nil
        and catalog.isPrimaryOrder(order) == true
        and (order == "follow" or order == "hold" or order == "relax"))
        or order == "follow" or order == "hold" or order == "relax"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    -- Follow/Hold is a replacement order, not an extra layer on top of an old
    -- Move/Guard directive. A player can therefore use either button to cancel
    -- an in-progress point command and immediately restore the primary duty.
    survivor.duty.order = order
    survivor.duty.directive = nil
    survivor.duty.ownerId = playerId
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.setCompanionCombatStance(id, playerId, stance, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local allowed = stance == "passive" or stance == "defensive" or stance == "aggressive"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.duty.combatStance = stance
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.setCompanionFormation(id, playerId, formation, spacing, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId or survivor.duty.mode ~= "companion"
        or (formation ~= "paired" and formation ~= "single_file")
        or (spacing ~= 1 and spacing ~= 2 and spacing ~= 3) then return false end
    survivor.duty.followerFormation = formation
    survivor.duty.followerSpacing = spacing
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.getSurvivorPolicies(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.policies) or nil
end

-- Internal identity policy setter, also used by explicit developer scenarios.
-- Player-facing commands must go through the ownership-checked wrapper below.
function KnoxPersistence.setSurvivorWeaponPreference(id, preference)
    if type(id) ~= "string" or root().survivors[id] == nil then return false end
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or (preference ~= "melee" and preference ~= "ranged" and preference ~= "auto") then return false end
    survivor.policies.weaponPreference = preference
    return true
end

function KnoxPersistence.setCompanionWeaponPreference(id, playerId, preference, worldAgeHours)
    if type(id) ~= "string" or root().survivors[id] == nil then return false end
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or (preference ~= "melee" and preference ~= "ranged" and preference ~= "auto")
        or survivor.affiliation.kind ~= "player" or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then return false end
    if survivor.policies.weaponPreference ~= preference then
        KnoxPersistence.setSurvivorWeaponPreference(id, preference)
        survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
        survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    end
    return true
end

function KnoxPersistence.setCompanionClimbing(id, playerId, allowed, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.policies.allowClimbing = allowed == true
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Door/window opening is its own permission, separate from vaulting and
-- climbing. Nil means inherit the sandbox default; explicit allow/disallow
-- wins for that companion at base, camp and on the road.
function KnoxPersistence.setCompanionDoorOpening(id, playerId, allowed, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    if allowed == nil then
        survivor.policies.allowDoorOpening = nil
    else
        survivor.policies.allowDoorOpening = allowed == true
    end
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Auto-loot while following is its own permission, separate from explicit
-- loot directives. Nil means enabled (the historical behavior); explicit
-- disable wins for that companion everywhere.
function KnoxPersistence.setCompanionAutoLoot(id, playerId, allowed, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    if allowed == nil then
        survivor.policies.autoLoot = nil
    else
        survivor.policies.autoLoot = allowed == true
    end
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Assigned beds: which survivor sleeps in which world bed. Stored as plain
-- coordinates plus object index inside the schemaless policies table, so old
-- saves simply have none and nothing migrates. Resolution is transient and
-- nil-safe: a removed/unloaded/occupied bed falls back to normal search.
local function bedOwnerId(playerId, survivor)
    if survivor == nil then return false end
    if survivor.affiliation.kind == "player"
        and survivor.affiliation.ownerId == playerId then
        return true
    end
    if survivor.duty.mode == "base" and survivor.duty.baseId ~= nil then
        local base = KnoxPersistence.getBase(survivor.duty.baseId)
        if base ~= nil and base.ownerKind == "player"
            and base.ownerId == playerId then
            return true
        end
    end
    return false
end

-- Automatic equipment upgrades are a player preference, not a combat rule.
-- Nil preserves historical enabled behavior for old saves.
function KnoxPersistence.setPlayerAutoEquipment(id, playerId, allowed, worldAgeHours)
    if type(id) ~= "string" or root().survivors[id] == nil
        or type(playerId) ~= "string" or playerId == "" then
        return false, "not_your_survivor"
    end
    local survivor = ensureSurvivorState(id)
    if survivor == nil or not bedOwnerId(playerId, survivor)
        or (allowed ~= nil and type(allowed) ~= "boolean") then
        return false, "not_your_survivor"
    end
    local value = allowed
    if value ~= nil then value = value == true end
    if survivor.policies.autoEquipment ~= value then
        survivor.policies.autoEquipment = value
        survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
        survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    end
    return true
end

function KnoxPersistence.setSurvivorBed(id, playerId, bedRef, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(bedRef) ~= "table"
        or not bedOwnerId(playerId, survivor) then
        return false, "not_your_survivor"
    end
    local x = tonumber(bedRef.x)
    local y = tonumber(bedRef.y)
    local z = tonumber(bedRef.z)
    local objectIndex = tonumber(bedRef.objectIndex)
    if not finiteCoordinate(x) or not finiteCoordinate(y)
        or not finiteCoordinate(z) or objectIndex == nil then
        return false, "invalid_bed"
    end
    survivor.policies.assignedBed = {
        x = x, y = y, z = z, objectIndex = math.floor(objectIndex),
    }
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.clearSurvivorBed(id, playerId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or not bedOwnerId(playerId, survivor) then
        return false, "not_your_survivor"
    end
    if survivor.policies.assignedBed == nil then
        return false, "no_assigned_bed"
    end
    survivor.policies.assignedBed = nil
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Faction bed assignments are automatic base policy, not a player command.
-- Keep this writer separate from setSurvivorBed so a faction can never use
-- the player-owned bed assignment path to mutate a companion or player base.
function KnoxPersistence.setFactionResidentBed(id, factionId, baseId, bedRef, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local faction = KnoxPersistence.getFaction(factionId)
    local base = KnoxPersistence.getBase(baseId)
    if survivor == nil or survivor.alive == false
        or faction == nil or faction.kind == "player"
        or base == nil or base.ownerKind ~= "faction" or base.ownerId ~= factionId
        or faction.homeBaseId ~= baseId
        or survivor.affiliation.factionId ~= factionId
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId
        or type(bedRef) ~= "table" then
        return false, "not_faction_resident"
    end
    local x, y, z = tonumber(bedRef.x), tonumber(bedRef.y), tonumber(bedRef.z)
    local objectIndex = tonumber(bedRef.objectIndex)
    if not finiteCoordinate(x) or not finiteCoordinate(y)
        or not finiteCoordinate(z) or z % 1 ~= 0
        or objectIndex == nil or objectIndex % 1 ~= 0 or objectIndex < 0 then
        return false, "invalid_bed"
    end
    local existing = survivor.policies.assignedBed
    if type(existing) == "table" then
        local alreadyThisBed = tonumber(existing.x) == x
            and tonumber(existing.y) == y and tonumber(existing.z) == z
            and tonumber(existing.objectIndex) == objectIndex
            and existing.autoFactionId == factionId
            and existing.autoBaseId == baseId
        if alreadyThisBed then return true, "existing" end
        if existing.autoFactionId ~= factionId then
            return false, "bed_already_assigned"
        end
    end
    survivor.policies.assignedBed = {
        x = x, y = y, z = z, objectIndex = objectIndex,
        autoFactionId = factionId, autoBaseId = baseId,
    }
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true, existing ~= nil and "reassigned" or "assigned"
end

function KnoxPersistence.clearFactionResidentBed(id, factionId, baseId)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    local bed = survivor ~= nil and survivor.policies ~= nil
        and survivor.policies.assignedBed or nil
    if type(bed) ~= "table" or bed.autoFactionId ~= factionId
        or (baseId ~= nil and bed.autoBaseId ~= baseId) then
        return false
    end
    survivor.policies.assignedBed = nil
    return true
end

function KnoxPersistence.setCompanionDirective(id, playerId, directive, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(directive) ~= "table"
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    if not KnoxPersistence.isValidCompanionDirective(directive) then
        return false
    end
    local kind = tostring(directive.kind or "")
    local minX = tonumber(directive.minX)
    local minY = tonumber(directive.minY)
    local maxX = tonumber(directive.maxX)
    local maxY = tonumber(directive.maxY)
    survivor.duty.directive = {
        kind = kind,
        minX = minX,
        minY = minY,
        maxX = maxX or minX,
        maxY = maxY or minY,
        z = tonumber(directive.z) or 0,
        buildingId = directive.buildingId ~= nil and tostring(directive.buildingId) or nil,
        issuedAtHours = tonumber(worldAgeHours) or 0,
    }
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

-- Arrival/obstacle progress belongs to the existing order. Updating it must
-- neither issue a replacement order nor reset the controller through a revision.
function KnoxPersistence.advanceCompanionPatrol(id, playerId, expected, step, arrived)
    local survivor=ensureSurvivorState(id)
    local patrol=rawget(_G,"KnoxCompanionPatrol")
    if survivor==nil or survivor.alive==false or patrol==nil or type(expected)~="table"
        or survivor.affiliation.kind~="player" or survivor.affiliation.ownerId~=playerId
        or survivor.duty.mode~="companion" or survivor.duty.directive~=expected
        or expected.kind~="patrol_area" then return false end
    local count=#patrol.waypoints(expected)
    step=tonumber(step)
    if count==0 or step==nil or step~=step or step==math.huge or step==-math.huge then return false end
    expected.patrolStep=math.max(0,math.floor(step))%count
    if arrived then
        local complete=patrol.recordDirectiveArrival(expected)
        if complete then expected.patrolLaps=math.min(1000000,(tonumber(expected.patrolLaps) or 0)+1) end
    else
        expected.patrolStep=(expected.patrolStep+1)%count
    end
    return true
end

function KnoxPersistence.clearCompanionDirective(id, playerId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.duty.directive = nil
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.getCompanionIds(playerId)
    local ids = {}
    if type(playerId) ~= "string" or playerId == "" then
        return ids
    end
    for id, survivor in pairs(root().survivors) do
        if survivor ~= nil and survivor.alive ~= false
            and survivor.affiliation ~= nil
            and survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId
            and survivor.duty ~= nil and survivor.duty.mode == "companion" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.ensurePlayerId(player)
    if player == nil or player.getModData == nil then
        return nil
    end
    local modData = player:getModData()
    modData.KnoxSurvivors = modData.KnoxSurvivors or {}
    local playerId = modData.KnoxSurvivors.playerId
    local data = root()
    if type(playerId) ~= "string" or playerId == "" then
        playerId = "player-" .. tostring(data.nextPlayerId)
        data.nextPlayerId = data.nextPlayerId + 1
        modData.KnoxSurvivors.playerId = playerId
    end
    local playerRecord = data.players[playerId] or { id = playerId }
    local descriptor = player.getDescriptor ~= nil and player:getDescriptor() or nil
    if descriptor ~= nil then
        playerRecord.forename = tostring(descriptor:getForename() or "")
        playerRecord.surname = tostring(descriptor:getSurname() or "")
    end
    data.players[playerId] = playerRecord
    return playerId
end

function KnoxPersistence.preparePlayerSuccession(playerId, worldAgeHours)
    if type(playerId) ~= "string" or playerId == "" then return false, "invalid_player" end
    local data = root()
    local base = KnoxPersistence.getBaseForOwner("player", playerId)
    if base == nil then
        data.pendingPlayerSuccession = nil
        return false, "no_player_base"
    end
    data.pendingPlayerSuccession = {
        oldPlayerId = playerId,
        baseId = base.id,
        createdAtHours = tonumber(worldAgeHours) or 0,
    }
    return true, base.id
end

function KnoxPersistence.adoptPendingPlayerSuccession(player, worldAgeHours)
    if player == nil then return false, "invalid_player" end
    local data = root()
    local pending = data.pendingPlayerSuccession
    if type(pending) ~= "table" then return false, "no_pending_succession" end
    local newPlayerId = KnoxPersistence.ensurePlayerId(player)
    if newPlayerId == nil or newPlayerId == pending.oldPlayerId then
        return false, "same_player"
    end
    local oldPlayerId = pending.oldPlayerId
    local base = data.bases[pending.baseId]
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= oldPlayerId then
        data.pendingPlayerSuccession = nil
        return false, "base_unavailable"
    end
    base.ownerId = newPlayerId
    local oldPlayer = data.players[oldPlayerId]
    local newPlayer = data.players[newPlayerId] or { id = newPlayerId }
    if oldPlayer ~= nil and oldPlayer.factionId ~= nil then
        newPlayer.factionId = oldPlayer.factionId
        local faction = data.factions[oldPlayer.factionId]
        if faction ~= nil and faction.kind == "player" then
            faction.ownerPlayerId = newPlayerId
            faction.homeBaseId = base.id
        end
    end
    data.players[newPlayerId] = newPlayer
    for _, survivor in pairs(data.survivors or {}) do
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        if survivor ~= nil and survivor.alive ~= false and affiliation ~= nil
            and affiliation.kind == "player" and affiliation.ownerId == oldPlayerId then
            affiliation.ownerId = newPlayerId
            local duty = survivor.duty or {}
            duty.ownerId = newPlayerId
            if duty.mode == "companion" then
                duty.mode, duty.order, duty.baseId = "base", "available", base.id
            elseif duty.mode == "base" then
                duty.baseId = duty.baseId or base.id
            end
            survivor.duty = duty
        end
    end
    data.pendingPlayerSuccession = nil
    -- This character inherited the existing household and companions. Do not
    -- also run the fresh-character spouse starter for the successor.
    local playerModData = player.getModData ~= nil and player:getModData() or nil
    if playerModData ~= nil then
        playerModData.KnoxSurvivors = playerModData.KnoxSurvivors or {}
        playerModData.KnoxSurvivors.spouseStart = { status = "skipped_succession" }
    end
    return true, base.id
end

function KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local relation = survivor.playerRelationships[playerId]
    if relation == nil then
        relation = {
            trust = 30,
            meetings = 0,
            firstMetHours = nil,
            lastMetHours = nil,
            nextTalkHours = 0,
            nextRecruitHours = 0,
            socialDisposition = nil,
            recruitmentAttempts = 0,
            lureAttempts = 0,
            nearbyHours = 0,
            nextPassiveHours = 0,
        }
        survivor.playerRelationships[playerId] = relation
    end
    relation.recruitmentAttempts = tonumber(relation.recruitmentAttempts) or 0
    relation.lureAttempts = tonumber(relation.lureAttempts) or 0
    relation.nearbyHours = tonumber(relation.nearbyHours) or 0
    relation.nextPassiveHours = tonumber(relation.nextPassiveHours) or 0
    return relation
end

-- Spending time near a survivor builds reputation passively, alongside Talk.
-- Grants +1 trust per 0.5h nearby (capped by cooldown), up to 100.
function KnoxPersistence.recordPlayerProximity(playerId, survivorId, worldAgeHours)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then return nil end
    local now = tonumber(worldAgeHours) or 0
    relation.nearbyHours = (tonumber(relation.nearbyHours) or 0) + 0.05
    if now < (tonumber(relation.nextPassiveHours) or 0) then
        return relation, "cooldown"
    end
    relation.nextPassiveHours = now + 0.5
    relation.trust = math.max(0, math.min(100, (tonumber(relation.trust) or 30) + 1))
    relation.lastMetHours = now
    if relation.firstMetHours == nil then relation.firstMetHours = now end
    return relation, "proximity"
end

-- Player-facing social behavior is selected once per survivor/player pair.
-- Trust remains a record of history, while this disposition controls the
-- person's initial boundary and never changes on a per-frame random roll.
function KnoxPersistence.getPlayerSocialDisposition(playerId, survivorId)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then return nil end
    if relation.socialDisposition == nil then
        local identity = KnoxPersistence.getSurvivorPersonality(survivorId) or {}
        local response = identity.playerResponse
        if response ~= "join" and response ~= "warm_up"
            and response ~= "independent" and response ~= "volatile"
            and response ~= "lure" and response ~= "attack_on_sight"
            and response ~= "warn_then_attack" then
            response = "join"
        end
        relation.socialDisposition = response
    end
    return relation.socialDisposition
end

function KnoxPersistence.recordPlayerSocialEvent(playerId, survivorId, event, worldAgeHours)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then return false end
    relation.lastSocialEvent = tostring(event or "interaction")
    relation.lastSocialEventHours = tonumber(worldAgeHours) or 0
    if event == "recruit_attempt" then
        relation.recruitmentAttempts = (tonumber(relation.recruitmentAttempts) or 0) + 1
    elseif event == "lure_attempt" then
        relation.lureAttempts = (tonumber(relation.lureAttempts) or 0) + 1
    end
    return true
end

function KnoxPersistence.getSurvivorDeathEvidence(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.deathEvidence) == "table"
        and copySerializable(survivor.deathEvidence) or nil
end

function KnoxPersistence.markSurvivorCorpseCreated(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    local evidence = survivor ~= nil and survivor.deathEvidence or nil
    if type(evidence) ~= "table" or evidence.corpseState ~= "native_pending" then return false end
    evidence.corpseState = "native_created"
    return true
end

function KnoxPersistence.recordPlayerRecruitRefusal(
    playerId,
    survivorId,
    worldAgeHours,
    cooldownHours
)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    relation.nextRecruitHours = math.max(
        tonumber(relation.nextRecruitHours) or 0,
        now + math.max(0, tonumber(cooldownHours) or 0)
    )
    return relation
end

function KnoxPersistence.recordPlayerConversation(
    playerId,
    survivorId,
    trustGain,
    worldAgeHours,
    cooldownHours
)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then
        return nil, "invalid_identity"
    end
    local now = tonumber(worldAgeHours) or 0
    -- Talk timer only applies while the survivor is upset with the player;
    -- friendly and neutral survivors happily chat without a cooldown.
    local upset = (tonumber(relation.trust) or 30) < 25
    if upset and (tonumber(relation.nextTalkHours) or 0) > now then
        return relation, "cooldown"
    end
    relation.firstMetHours = relation.firstMetHours or now
    relation.lastMetHours = now
    relation.meetings = (tonumber(relation.meetings) or 0) + 1
    relation.trust = math.max(0, math.min(100,
        (tonumber(relation.trust) or 30) + (tonumber(trustGain) or 0)))
    relation.nextTalkHours = now + math.max(0, tonumber(cooldownHours) or 0)
    return relation, "recorded"
end

-- Sims-style social acts share one trust ledger with Talk. Each act carries
-- its own cooldown (tracked per act, so jokes never block gifts) and trust
-- delta. Upset survivors (trust below 25) keep the shared talk timer on top.
function KnoxPersistence.recordPlayerSocialAct(
    playerId,
    survivorId,
    action,
    trustDelta,
    cooldownHours,
    worldAgeHours
)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then
        return nil, "invalid_identity"
    end
    local now = tonumber(worldAgeHours) or 0
    local act = tostring(action or "talk")
    relation.nextSocialHours = type(relation.nextSocialHours) == "table"
        and relation.nextSocialHours or {}
    if (tonumber(relation.nextSocialHours[act]) or 0) > now then
        return relation, "cooldown"
    end
    local upset = (tonumber(relation.trust) or 30) < 25
    if upset and (tonumber(relation.nextTalkHours) or 0) > now then
        return relation, "cooldown"
    end
    relation.nextSocialHours[act] = now + math.max(0, tonumber(cooldownHours) or 0)
    relation.nextTalkHours = now
    relation.firstMetHours = relation.firstMetHours or now
    relation.lastMetHours = now
    relation.meetings = (tonumber(relation.meetings) or 0) + 1
    relation.trust = math.max(0, math.min(100,
        (tonumber(relation.trust) or 30) + (tonumber(trustDelta) or 0)))
    relation.lastSocialEvent = act
    relation.lastSocialEventHours = now
    return relation, "recorded"
end

function KnoxPersistence.recordEncounter(firstId, secondId, observation)
    local key, lowId, highId = relationshipKey(firstId, secondId)
    if key == nil or type(observation) ~= "table" then
        return nil
    end
    local relationships = root().relationships
    local record = relationships[key] or {
        firstId = lowId,
        secondId = highId,
        meetings = 0,
        nearbyHours = 0,
        sharedRoam = 0,
        sharedLoot = 0,
        sharedCombat = 0,
    }
    local worldAge = tonumber(observation.worldAgeHours) or 0
    record.firstMetHours = record.firstMetHours or worldAge
    record.lastMetHours = worldAge
    if observation.began == true then
        record.meetings = record.meetings + 1
    end
    record.nearbyHours = record.nearbyHours
        + math.max(0, math.min(0.25, tonumber(observation.nearbyHours) or 0))
    record.sharedRoam = record.sharedRoam
        + math.max(0, tonumber(observation.sharedRoam) or 0)
    record.sharedLoot = record.sharedLoot
        + math.max(0, tonumber(observation.sharedLoot) or 0)
    record.sharedCombat = record.sharedCombat
        + math.max(0, tonumber(observation.sharedCombat) or 0)
    relationships[key] = record
    return record
end

function KnoxPersistence.getRelationship(firstId, secondId)
    local key = relationshipKey(firstId, secondId)
    return key ~= nil and root().relationships[key] or nil
end

function KnoxPersistence.setRelationshipDisposition(
    firstId,
    secondId,
    disposition,
    nextEncounterHours
)
    local key, lowId, highId = relationshipKey(firstId, secondId)
    local validDisposition = disposition == "allied" or disposition == "neutral"
        or disposition == "hostile" or disposition == "declined"
    if key == nil or not validDisposition then
        return nil
    end
    local relationships = root().relationships
    local record = relationships[key] or {
        firstId = lowId,
        secondId = highId,
        meetings = 0,
        nearbyHours = 0,
        sharedRoam = 0,
        sharedLoot = 0,
        sharedCombat = 0,
    }
    record.disposition = disposition
    record.nextEncounterHours = tonumber(nextEncounterHours) or 0
    relationships[key] = record
    return record
end

function KnoxPersistence.getFactions()
    return root().factions
end

-- Event factions remain ordinary Knox factions. This metadata identifies why
-- they entered the world; it never owns members, relationships, health or gear.
function KnoxPersistence.bindFactionEventIdentity(
    factionId,
    policyId,
    displayName,
    sourceEventId,
    basePolicy,
    worldAgeHours
)
    local faction = KnoxPersistence.getFaction(factionId)
    local hours = tonumber(worldAgeHours)
    if faction == nil or faction.kind ~= "npc"
        or type(policyId) ~= "string" or not policyId:match("^[a-z][a-z0-9_]*$") or #policyId > 40
        or type(displayName) ~= "string" or displayName == "" or #displayName > 64
        or type(sourceEventId) ~= "string" or sourceEventId == "" or #sourceEventId > 80
        or (basePolicy ~= "event_only" and basePolicy ~= "optional")
        or not finiteCoordinate(hours) or hours < 0 then return nil, "invalid_event_faction" end
    local current = faction.eventIdentity
    if current ~= nil then
        if current.policyId == policyId and current.sourceEventId == sourceEventId then
            return copySerializable(faction), "existing"
        end
        return nil, "event_faction_already_bound"
    end
    faction.eventIdentity = {
        policyId = policyId,
        sourceEventId = sourceEventId,
        basePolicy = basePolicy,
        boundAtHours = hours,
    }
    faction.name = displayName
    return copySerializable(faction), "bound"
end

local FACTION_DISPOSITIONS = {
    allied = true,
    neutral = true,
    hostile = true,
}

local function factionRelationshipKey(firstFactionId, secondFactionId)
    if type(firstFactionId) ~= "string" or firstFactionId == ""
        or type(secondFactionId) ~= "string" or secondFactionId == ""
        or firstFactionId == secondFactionId then
        return nil
    end
    if firstFactionId < secondFactionId then
        return firstFactionId .. "|" .. secondFactionId, firstFactionId, secondFactionId
    end
    return secondFactionId .. "|" .. firstFactionId, secondFactionId, firstFactionId
end

-- This returns a copy so callers cannot silently mutate saved diplomacy
-- without recording the time and reason through the setter below.
function KnoxPersistence.getFactionRelationship(firstFactionId, secondFactionId)
    local key = factionRelationshipKey(firstFactionId, secondFactionId)
    local relationship = key ~= nil and root().factionRelationships[key] or nil
    return relationship ~= nil and copySerializable(relationship) or nil
end

function KnoxPersistence.setFactionRelationshipDisposition(
    firstFactionId,
    secondFactionId,
    disposition,
    worldAgeHours,
    reason
)
    local key, lowId, highId = factionRelationshipKey(firstFactionId, secondFactionId)
    if key == nil or FACTION_DISPOSITIONS[disposition] ~= true
        or KnoxPersistence.getFaction(lowId) == nil
        or KnoxPersistence.getFaction(highId) == nil then
        return nil, "invalid_faction_relationship"
    end
    local relationships = root().factionRelationships
    local relationship = relationships[key] or {
        firstFactionId = lowId,
        secondFactionId = highId,
        disposition = "neutral",
        createdAtHours = tonumber(worldAgeHours) or 0,
    }
    relationship.disposition = disposition
    relationship.changedAtHours = tonumber(worldAgeHours) or 0
    relationship.reason = type(reason) == "string" and reason or nil
    relationships[key] = relationship
    return copySerializable(relationship), "saved"
end

-- Faction-wide disposition has one durable source for member combat, territory
-- responses and raid eligibility. A hostile patrol is itself persisted faction
-- policy, so it remains hostile to other policies even when that other faction
-- formed after the patrol and therefore has no legacy diplomacy row yet.
function KnoxPersistence.getFactionDisposition(firstFactionId, secondFactionId)
    local first = KnoxPersistence.getFaction(firstFactionId)
    local second = KnoxPersistence.getFaction(secondFactionId)
    if first == nil or second == nil then return "neutral" end
    if first.id == second.id then return "allied" end
    local firstPatrol, secondPatrol = first.hostilePatrol, second.hostilePatrol
    if (firstPatrol ~= nil or secondPatrol ~= nil) and firstPatrol ~= secondPatrol then
        return "hostile"
    end
    local relationship = KnoxPersistence.getFactionRelationship(first.id, second.id)
    return relationship ~= nil and relationship.disposition or "neutral"
end

-- A real survivor conflict always records the two people involved. Only an
-- actual conflict between established NPC factions escalates to diplomacy;
-- temporary groups retain individual history so one fight does not permanently
-- turn every traveller in both groups into an enemy.
function KnoxPersistence.escalateSurvivorConflict(
    firstId,
    secondId,
    worldAgeHours,
    reason
)
    if type(firstId) ~= "string" or firstId == ""
        or type(secondId) ~= "string" or secondId == ""
        or firstId == secondId
        or KnoxPersistence.areSurvivorsAllied(firstId, secondId) then
        return nil, "invalid_or_allied"
    end
    local now = tonumber(worldAgeHours) or 0
    local personal = KnoxPersistence.setRelationshipDisposition(
        firstId, secondId, "hostile", now + 24
    )
    if personal == nil then return nil, "relationship_failed" end
    local firstFaction = KnoxPersistence.getFactionForSurvivor(firstId)
    local secondFaction = KnoxPersistence.getFactionForSurvivor(secondId)
    if firstFaction ~= nil and secondFaction ~= nil
        and firstFaction.id ~= secondFaction.id
        and firstFaction.kind == "npc" and secondFaction.kind == "npc" then
        local relation, result = KnoxPersistence.setFactionRelationshipDisposition(
            firstFaction.id,
            secondFaction.id,
            "hostile",
            now,
            type(reason) == "string" and reason or "survivor_conflict"
        )
        if relation ~= nil then return personal, "faction_hostile" end
        return personal, "personal_hostile:" .. tostring(result)
    end
    return personal, "personal_hostile"
end

function KnoxPersistence.getPlayerFaction(playerId)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local player = root().players[playerId]
    local factionId = player ~= nil and player.factionId or nil
    local faction = factionId ~= nil and KnoxPersistence.getFaction(factionId) or nil
    if faction ~= nil and faction.kind == "player" and faction.ownerPlayerId == playerId then
        return faction
    end
    return nil
end

-- Base protection defaults to safety.  Only an explicit legacy hostile flag
-- or durable hostility between the survivor's faction and the owning player's
-- faction permits destructive base actions.
function KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return false
    end
    local affiliation = survivor.affiliation or {}
    if affiliation.hostileToPlayer == true then
        return true
    end
    if type(affiliation.hostileToPlayers) == "table"
        and affiliation.hostileToPlayers[playerId] == true then return true end
    local survivorFactionId = affiliation.factionId
    -- Hostile patrols (military) shoot survivors on sight even when no durable
    -- faction relationship exists yet (e.g. a player faction formed later).
    -- Flagged deserters are exempt: they want a home, not a fight.
    if survivorFactionId ~= nil and survivor.deserter ~= true then
        local data = root()
        local faction = data.factions ~= nil and data.factions[survivorFactionId] or nil
        if type(faction) == "table" and faction.hostilePatrol ~= nil then return true end
    end
    -- Flagged deserters want a home, not a fight: faction records never make
    -- them hostile. Explicit per-survivor flags above still apply.
    if survivor.deserter == true then return false end
    local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
    if survivorFactionId == nil or playerFaction == nil
        or survivorFactionId == playerFaction.id then
        return false
    end
    local relationship = KnoxPersistence.getFactionRelationship(
        survivorFactionId,
        playerFaction.id
    )
    return relationship ~= nil and relationship.disposition == "hostile"
end

function KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, hostile)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then return false end
    survivor.affiliation = survivor.affiliation or { kind = "independent" }
    survivor.affiliation.hostileToPlayers = type(survivor.affiliation.hostileToPlayers) == "table"
        and survivor.affiliation.hostileToPlayers or {}
    survivor.affiliation.hostileToPlayers[playerId] = hostile == true or nil
    return true
end

-- A faction owns its camp as a whole. Stealing from a claimed NPC-faction
-- container is therefore treated like attacking a member: the player's group
-- and that faction become hostile, while an independent survivor's property
-- never accidentally creates a world-wide hostility flag.
function KnoxPersistence.recordPlayerFactionTheft(playerId, baseId, worldAgeHours)
    local now = tonumber(worldAgeHours)
    now = now ~= nil and now == now and now >= 0 and now < math.huge and now or nil
    local base = KnoxPersistence.getBase(baseId)
    if now == nil or type(playerId) ~= "string" or root().players[playerId] == nil
        or base == nil or base.ownerKind ~= "faction" then
        return nil, "invalid_theft"
    end
    local faction = KnoxPersistence.getFaction(base.ownerId)
    if faction == nil or faction.kind == "player" then return nil, "invalid_owner" end
    local playerFaction = KnoxPersistence.ensurePlayerFaction(playerId, now)
    if playerFaction == nil or playerFaction.id == faction.id then return nil, "same_faction" end
    local prior = KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id)
    local relation, result = KnoxPersistence.setFactionRelationshipDisposition(
        faction.id, playerFaction.id, "hostile", now, "player_theft"
    )
    if relation == nil then return nil, result end
    faction.lastPlayerHostileAction = {
        kind = "theft", playerId = playerId, baseId = base.id, atHours = now,
    }
    return relation, prior ~= nil and prior.disposition == "hostile"
        and "already_hostile" or "hostile"
end

function KnoxPersistence.ensurePlayerFaction(playerId, worldAgeHours)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local data = root()
    local player = data.players[playerId] or { id = playerId }
    local faction = player.factionId ~= nil and data.factions[player.factionId] or nil
    if faction ~= nil and (faction.kind ~= "player"
        or faction.ownerPlayerId ~= playerId) then
        faction = nil
        player.factionId = nil
    end
    if faction == nil then
        local factionId = "player-faction-" .. tostring(data.nextFactionId)
        data.nextFactionId = data.nextFactionId + 1
        faction = {
            id = factionId,
            name = "Your Group",
            kind = "player",
            ownerPlayerId = playerId,
            memberIds = {},
            formedAtHours = tonumber(worldAgeHours) or 0,
        }
        data.factions[factionId] = faction
        player.factionId = factionId
        data.players[playerId] = player
    end
    faction.kind = "player"
    faction.ownerPlayerId = playerId
    faction.memberIds = faction.memberIds or {}
    return faction
end

-- Contribution callers must first verify the real action/transfer. This ledger
-- records social consequences only; it never grants supplies or changes health.
local CONTRIBUTION_RULES = {
    defense = { trust = 4, reputation = 2, cooldown = 0.5 },
    gift = { trust = 3, reputation = 1, cooldown = 6 },
    trade = { trust = 2, reputation = 1, cooldown = 3 },
    treatment = { trust = 5, reputation = 2, cooldown = 6 },
    construction = { trust = 3, reputation = 1, cooldown = 6 },
}

local function contributionTime(value)
    local number = tonumber(value)
    return number ~= nil and number == number and number >= 0 and number < math.huge and number or nil
end

local function contributionLedger(owner, now)
    local ledger = owner.contributions
    if type(ledger) ~= "table" then
        ledger = { startedAtHours = now, earned = 0, nextAt = {} }
        owner.contributions = ledger
    end
    ledger.nextAt = type(ledger.nextAt) == "table" and ledger.nextAt or {}
    local start = tonumber(ledger.startedAtHours) or now
    ledger.startedAtHours = start
    if now < start then return nil end -- clock rollback must not reset reward budgets
    if now - start >= 24 then
        ledger.startedAtHours, ledger.earned, ledger.nextAt = now, 0, {}
    end
    return ledger
end

local function playerFactionRelationship(playerId, survivorId, now)
    local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
    if faction == nil or faction.kind == "player" then return nil end
    local playerFaction = KnoxPersistence.ensurePlayerFaction(playerId, now)
    local key, lowId, highId = factionRelationshipKey(faction.id, playerFaction.id)
    if key == nil then return nil end
    local relationship = root().factionRelationships[key]
    if relationship == nil then
        relationship = { firstFactionId = lowId, secondFactionId = highId,
            disposition = "neutral", createdAtHours = now, reputation = 0 }
        root().factionRelationships[key] = relationship
    end
    return relationship
end

function KnoxPersistence.recordPlayerContribution(playerId, survivorId, kind, worldAgeHours)
    local rule, now = CONTRIBUTION_RULES[kind], contributionTime(worldAgeHours)
    if rule == nil or now == nil or type(playerId) ~= "string" or root().players[playerId] == nil
        or not KnoxPersistence.isSurvivorAlive(survivorId) then return nil, "invalid_contribution" end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return nil, "hostile" end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local ledger = contributionLedger(relation, now)
    if ledger == nil then return nil, "clock_rollback" end
    if now < (tonumber(ledger.nextAt[kind]) or 0) then return nil, "cooldown" end
    local gain = math.min(rule.trust, math.max(0, 12 - (tonumber(ledger.earned) or 0)))
    if gain <= 0 then return nil, "daily_limit" end
    ledger.nextAt[kind] = now + rule.cooldown
    ledger.earned = (tonumber(ledger.earned) or 0) + gain
    relation.trust = math.max(0, math.min(100, (tonumber(relation.trust) or 30) + gain))
    relation.firstMetHours = relation.firstMetHours or now
    relation.lastMetHours, relation.lastContribution = now, kind
    local reputationGain = 0
    local factionRelation = playerFactionRelationship(playerId, survivorId, now)
    if factionRelation ~= nil and factionRelation.disposition ~= "hostile" then
        local factionLedger = contributionLedger(factionRelation, now)
        if factionLedger ~= nil then
            reputationGain = math.min(rule.reputation, math.max(0, 8 - (tonumber(factionLedger.earned) or 0)))
            factionLedger.earned = (tonumber(factionLedger.earned) or 0) + reputationGain
            factionRelation.reputation = math.max(-100, math.min(100,
                (tonumber(factionRelation.reputation) or 0) + reputationGain))
            factionRelation.changedAtHours, factionRelation.reason = now, kind
        end
    end
    return { trustGain = gain, reputationGain = reputationGain }, "recorded"
end

-- Called only for a native player hit against a previously non-hostile survivor.
-- Retaliation against an existing hostile is not an unprovoked aggression event.
function KnoxPersistence.recordPlayerAggression(playerId, survivorId, worldAgeHours)
    local now = contributionTime(worldAgeHours)
    if now == nil or type(playerId) ~= "string" or root().players[playerId] == nil
        or type(survivorId) ~= "string" or root().survivors[survivorId] == nil then return false end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if now < (tonumber(relation.nextAggressionHours) or 0) then return false end
    relation.trust = math.max(0, (tonumber(relation.trust) or 30) - 30)
    relation.nextAggressionHours = now + 1
    relation.lastAggressionHours = now
    local factionRelation = playerFactionRelationship(playerId, survivorId, now)
    if factionRelation ~= nil then
        factionRelation.reputation = math.max(-100, (tonumber(factionRelation.reputation) or 0) - 20)
        factionRelation.disposition = "hostile"
        factionRelation.changedAtHours, factionRelation.reason = now, "player_aggression"
    end
    return true
end

local function containsId(ids, id)
    for _, existing in ipairs(ids or {}) do
        if existing == id then
            return true
        end
    end
    return false
end

local function copyIds(ids)
    local copied = {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "string" and id ~= "" and not containsId(copied, id) then
            copied[#copied + 1] = id
        end
    end
    table.sort(copied)
    return copied
end

local function nextUnusedSerial(data, field, prefix, values)
    local value = tonumber(data[field])
    if not finiteCoordinate(value) or value < 1 then value = 1 end
    value = math.floor(value)
    local id = prefix .. tostring(value)
    while values[id] ~= nil do
        value = value + 1
        if not finiteCoordinate(value) then return nil end
        id = prefix .. tostring(value)
    end
    return id, value
end

-- Atomic persistence-only entry for named event parties. Participants are the
-- same population-managed world identities used everywhere else; no body or
-- item is created until ordinary first materialization succeeds.
function KnoxPersistence.createEventFactionPopulation(
    policyId,
    displayName,
    sourceEventId,
    basePolicy,
    origins,
    worldAgeHours
)
    local hours = tonumber(worldAgeHours)
    if type(policyId) ~= "string" or not policyId:match("^[a-z][a-z0-9_]*$") or #policyId > 40
        or type(displayName) ~= "string" or displayName == "" or #displayName > 64
        or type(sourceEventId) ~= "string" or sourceEventId == "" or #sourceEventId > 80
        or (basePolicy ~= "event_only" and basePolicy ~= "optional")
        or not finiteCoordinate(hours) or hours < 0
        or type(origins) ~= "table" or #origins < 2 or #origins > 6 then
        return nil, "invalid_event_entry"
    end
    local data = root()
    for _, faction in pairs(data.factions) do
        local identity = type(faction) == "table" and faction.eventIdentity or nil
        if type(identity) == "table" and identity.sourceEventId == sourceEventId then
            if identity.policyId == policyId then return copySerializable(faction), "existing" end
            return nil, "event_source_already_bound"
        end
    end
    local used, normalized, seen = KnoxPersistence.getUsedWorldOriginKeys(), {}, {}
    local count = 0
    for index, origin in pairs(origins) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #origins
            or type(origin) ~= "table" then return nil, "invalid_event_origin" end
        count = count + 1
    end
    if count ~= #origins then return nil, "invalid_event_origin" end
    for index, origin in ipairs(origins) do
        local x, y, z = tonumber(origin.x), tonumber(origin.y), tonumber(origin.z) or 0
        if not finiteCoordinate(x) or not finiteCoordinate(y) or not finiteCoordinate(z)
            or z % 1 ~= 0 or z < 0 or z > 7 then return nil, "invalid_event_origin" end
        x, y, z = math.floor(x), math.floor(y), math.floor(z)
        local key = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
        if seen[key] or used[key] then return nil, used[key] and "origin_already_used" or "duplicate_event_origin" end
        seen[key] = true
        normalized[index] = {
            x = x, y = y, z = z, key = key,
            region = tostring(origin.region or "Knox Event"),
            regionKey = tostring(origin.regionKey or origin.region or "Knox Event"),
            source = "knox_event",
        }
    end

    local previousWorldId = data.nextWorldSurvivorId
    local allocated = {}
    for _, origin in ipairs(normalized) do
        local id, reason = KnoxPersistence.allocateWorldSurvivor(origin, hours)
        if id == nil then
            for _, createdId in ipairs(allocated) do data.survivors[createdId] = nil end
            data.nextWorldSurvivorId = previousWorldId
            return nil, reason or "event_allocation_failed"
        end
        allocated[#allocated + 1] = id
    end

    local groupId, groupSerial = nextUnusedSerial(data, "nextTravelGroupId", "travel-group-", data.travelGroups)
    local factionId, factionSerial = nextUnusedSerial(data, "nextFactionId", "faction-", data.factions)
    if groupId == nil or factionId == nil then
        for _, createdId in ipairs(allocated) do data.survivors[createdId] = nil end
        data.nextWorldSurvivorId = previousWorldId
        return nil, "event_serial_exhausted"
    end
    data.nextTravelGroupId, data.nextFactionId = groupSerial + 1, factionSerial + 1
    local policyDef = nil
    if rawget(_G, "KnoxEventFactions") ~= nil
        and KnoxEventFactions.get ~= nil then
        local ok, definition = pcall(KnoxEventFactions.get, policyId)
        if ok and type(definition) == "table" then policyDef = definition end
    end
    local members, joined = copyIds(allocated), {}
    for _, id in ipairs(members) do joined[id] = hours end
    local group = { id = groupId, leaderId = members[1], memberIds = members,
        formedAtHours = hours, memberJoinedAtHours = copySerializable(joined), factionId = factionId }
    local faction = { id = factionId, name = displayName, kind = "npc", leaderId = members[1],
        memberIds = copyIds(members), memberJoinedAtHours = copySerializable(joined),
        formedAtHours = hours, homeSafehouse = nil,
        eventIdentity = { policyId = policyId, sourceEventId = sourceEventId,
            basePolicy = basePolicy, boundAtHours = hours } }
    data.travelGroups[groupId], data.factions[factionId] = group, faction
    for _, id in ipairs(members) do
        local survivor = data.survivors[id]
        survivor.eventManaged, survivor.eventSourceId = true, sourceEventId
        survivor.affiliation = { kind = "faction", ownerId = nil, factionId = factionId }
        survivor.unloadedSurvival.eventEntryId = sourceEventId
        survivor.unloadedSurvival.activity = "event_entry_waiting"
    end
    for first = 1, #members do
        for second = first + 1, #members do
            KnoxPersistence.setRelationshipDisposition(members[first], members[second], "allied", hours)
        end
    end
    if policyDef ~= nil and policyDef.hostilePatrol == true then
        -- Hostile patrols (military) shoot on sight: record durable hostility
        -- against every other existing faction and mark the faction itself so
        -- later-joining player factions are covered without a stored record.
        -- Fellow patrols of the same policy are exempt.
        faction.hostilePatrol = policyId
        for otherId, other in pairs(data.factions) do
            local otherIdentity = type(other) == "table" and other.eventIdentity or nil
            if type(otherId) == "string" and type(other) == "table"
                and otherId ~= factionId and other.kind ~= nil
                and (type(otherIdentity) ~= "table"
                    or otherIdentity.policyId ~= policyId) then
                KnoxPersistence.setFactionRelationshipDisposition(
                    factionId, otherId, "hostile", hours, "hostile_patrol")
            end
        end
        -- One member deserts: flagged now, released as a recruitable
        -- independent when the patrol's event ends.
        if policyDef.deserters == true and #members >= 3 then
            local deserter = data.survivors[members[#members]]
            if deserter ~= nil then deserter.deserter = true end
        end
    end
    return copySerializable(faction), "created"
end

-- Finalize a named event entry as one ModData transaction. The allocation
-- helper above is idempotent, so a reload between allocation and this commit
-- can safely retry without creating another faction. No body or item is made.
function KnoxPersistence.commitEventFactionEntry(eventId, expectedRevision, factionId, worldAgeHours)
    local data = root()
    local event = type(eventId) == "string" and data.knoxEvents.records[eventId] or nil
    local faction = type(factionId) == "string" and data.factions[factionId] or nil
    local hours, revision = tonumber(worldAgeHours), tonumber(expectedRevision)
    if type(event) ~= "table" or event.id ~= eventId or event.kind ~= "faction_entry"
        or event.phase ~= "spawning" or event.revision ~= revision
        or not finiteCoordinate(hours) or hours < (tonumber(event.lastChangedAtHours) or math.huge)
        or type(faction) ~= "table" or faction.kind ~= "npc" then
        return nil, "event_changed"
    end
    local identity = faction.eventIdentity
    if type(identity) ~= "table" or identity.policyId ~= event.policyId
        or identity.sourceEventId ~= eventId then return nil, "event_faction_changed" end
    local members = copyIds(faction.memberIds)
    if #members ~= math.floor(tonumber(event.partySize) or 0) then
        return nil, "event_party_changed"
    end
    local group, duties, leaderOrigin = nil, {}, nil
    for _, id in ipairs(members) do
        local survivor = data.survivors[id]
        local duty = survivor ~= nil and survivor.duty or nil
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        local memberGroup = KnoxPersistence.getTravelGroupFor(id)
        if survivor == nil or survivor.alive == false or survivor.eventManaged ~= true
            or survivor.eventSourceId ~= eventId or affiliation == nil
            or affiliation.kind ~= "faction" or affiliation.factionId ~= factionId
            or duty == nil or duty.mode ~= "autonomous" or duty.eventId ~= nil
            or KnoxPersistence.getAwayTeamForSurvivor(id) ~= nil
            or memberGroup == nil or memberGroup.factionId ~= factionId
            or (group ~= nil and memberGroup.id ~= group.id) then
            return nil, "event_member_unavailable"
        end
        group = group or memberGroup
        duties[#duties + 1] = duty
        if id == faction.leaderId then leaderOrigin = survivor.origin end
    end
    leaderOrigin = leaderOrigin or (data.survivors[members[1]] or {}).origin
    if group == nil or type(leaderOrigin) ~= "table"
        or not finiteCoordinate(leaderOrigin.x) or not finiteCoordinate(leaderOrigin.y)
        or not finiteCoordinate(leaderOrigin.z or 0) then return nil, "event_origin_missing" end

    event.sourceFactionId = factionId
    event.sourceGroupId = group.id
    event.memberIds = members
    event.entryLocation = { x = math.floor(tonumber(leaderOrigin.x)),
        y = math.floor(tonumber(leaderOrigin.y)), z = math.floor(tonumber(leaderOrigin.z) or 0) }
    event.phase = "approaching"
    event.revision = revision + 1
    event.lastChangedAtHours = hours
    event.nextAttemptAtHours = hours
    event.reason = "persistent_event_party_entered"
    for _, duty in ipairs(duties) do
        duty.eventId = eventId
        duty.revision = (tonumber(duty.revision) or 0) + 1
        duty.changedAtHours = hours
    end
    return copySerializable(event), "committed"
end

function KnoxPersistence.addFactionMember(factionId, survivorId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local survivor = ensureSurvivorState(survivorId)
    if faction == nil or survivor == nil or survivor.alive == false
        or survivor.eventManaged == true
        or type(survivor.departure) == "table"
            and (survivor.departure.status == "pending"
                or survivor.departure.status == "departed")
        or KnoxPersistence.getAwayTeamForSurvivor(survivorId) ~= nil then
        return false
    end
    if faction.kind ~= "player" and (survivor.affiliation.kind == "player"
        or survivor.duty.mode == "companion"
        or survivor.duty.mode == "base" and survivor.affiliation.kind == "player") then
        return false
    end
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(survivorId)
        or nil
    if group ~= nil and group.factionId ~= factionId
        and KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(survivorId)
    end
    local previousFactionId = survivor.affiliation.factionId
    if previousFactionId ~= nil and previousFactionId ~= factionId then
        KnoxPersistence.removeFactionMember(previousFactionId, survivorId, false)
    end
    faction.memberIds = faction.memberIds or {}
    if not containsId(faction.memberIds, survivorId) then
        faction.memberIds[#faction.memberIds + 1] = survivorId
        table.sort(faction.memberIds)
    end
    faction.memberJoinedAtHours = faction.memberJoinedAtHours or {}
    faction.memberJoinedAtHours[survivorId] = faction.memberJoinedAtHours[survivorId]
        or tonumber(worldAgeHours)
        or 0
    survivor.affiliation.factionId = factionId
    survivor.affiliation.kind = faction.kind == "player" and "player" or "faction"
    survivor.affiliation.ownerId = faction.kind == "player"
        and faction.ownerPlayerId
        or nil
    return true
end

function KnoxPersistence.removeFactionMember(factionId, survivorId, preserveDuty)
    local faction = KnoxPersistence.getFaction(factionId)
    local survivor = ensureSurvivorState(survivorId)
    if faction == nil or survivor == nil then
        return false
    end
    local retained = {}
    for _, id in ipairs(faction.memberIds or {}) do
        if id ~= survivorId then
            retained[#retained + 1] = id
        end
    end
    faction.memberIds = retained
    if faction.memberJoinedAtHours ~= nil then
        faction.memberJoinedAtHours[survivorId] = nil
    end
    KnoxPersistence.clearFactionResidentBed(survivorId, factionId)
    if survivor.affiliation.factionId == factionId then
        if survivor.duty.mode == "base" then
            requeueClaimsForSurvivor(
                survivorId,
                survivor.duty.baseId,
                "faction_membership_changed"
            )
        end
        survivor.affiliation = {
            kind = "independent",
            ownerId = nil,
        }
        if preserveDuty ~= true then
            survivor.duty = {
                mode = "autonomous",
                order = "survive",
                revision = (tonumber(survivor.duty.revision) or 0) + 1,
            }
        end
    end
    -- Membership changes are a lifecycle boundary. A departing leader or last
    -- resident must not leave stale faction/base state until a later reload.
    KnoxPersistence.normalizeRelationshipDomains()
    return true
end

function KnoxPersistence.getTravelGroupFor(id)
    local matches = {}
    for groupId, group in pairs(root().travelGroups) do
        if group ~= nil and containsId(group.memberIds, id) then
            matches[#matches + 1] = {
                id = tostring(group.id or groupId),
                group = group,
            }
        end
    end
    table.sort(matches, function(first, second) return first.id < second.id end)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
    for _, match in ipairs(matches) do
        if affiliation.factionId ~= nil
            and match.group.factionId == affiliation.factionId then
            return match.group
        end
    end
    return matches[1] ~= nil and matches[1].group or nil
end

-- Read-only QA/diagnostic enumeration. Persistence remains the membership
-- owner; consumers must not mutate the returned canonical roster table.
function KnoxPersistence.getTravelGroups()
    return root().travelGroups
end

-- A travel-group objective is a durable, read-only summary of the leader's
-- autonomous purpose. It never owns movement: the leader keeps its normal
-- controller intent and members continue following through formation logic.
function KnoxPersistence.getTravelGroupObjective(groupId)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    return group ~= nil and validLifeIntent(group.objective)
        and copySerializable(group.objective) or nil
end

-- A leader order is a small, explicit group directive. It is separate from
-- the leader's life-intent summary: the objective describes why a leader is
-- acting, while this record tells the existing follower arbitration whether to
-- stay in formation or hold. It never owns native movement or combat.
local function validTravelGroupLeaderOrder(group, leaderId, order)
    return type(group) == "table" and type(leaderId) == "string"
        and group.leaderId == leaderId and containsId(group.memberIds, leaderId)
        and type(order) == "table"
        and order.leaderId == leaderId and order.groupId == group.id
        and KnoxPersistence.isSurvivorAlive(leaderId)
        and (order.kind == "follow" or order.kind == "hold")
end

function KnoxPersistence.getTravelGroupLeaderOrder(groupId, worldAgeHours)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    local order = group ~= nil and group.leaderOrder or nil
    if not validTravelGroupLeaderOrder(group, group ~= nil and group.leaderId or nil, order) then
        return nil
    end
    local faction = group.factionId ~= nil and root().factions[group.factionId] or nil
    if group.factionId ~= nil and (faction == nil or faction.leaderId ~= order.leaderId) then
        return nil
    end
    local expiry = tonumber(order.expiresAtHours)
    if not finiteCoordinate(expiry) then return nil end
    local now = tonumber(worldAgeHours)
    if now == nil and getGameTime ~= nil and getGameTime() ~= nil then
        now = tonumber(getGameTime():getWorldAgeHours())
    end
    if not finiteCoordinate(now) then return nil end
    if now >= expiry then
        group.leaderOrder = nil
        group.leaderOrderRevision = (tonumber(group.leaderOrderRevision) or 0) + 1
        return nil
    end
    return copySerializable(order)
end

function KnoxPersistence.issueTravelGroupLeaderOrder(
    groupId, leaderId, kind, worldAgeHours, expiresAtHours
)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    local nextOrder = { kind = tostring(kind or ""), leaderId = leaderId, groupId = groupId }
    if not validTravelGroupLeaderOrder(group, leaderId, nextOrder) then
        return nil, "invalid_leader_order"
    end
    local faction = group.factionId ~= nil and root().factions[group.factionId] or nil
    if group.factionId ~= nil and (faction == nil or faction.leaderId ~= leaderId) then
        return nil, "faction_leader_mismatch"
    end
    local now = tonumber(worldAgeHours)
    if not finiteCoordinate(now) or now < 0 then return nil, "invalid_order_time" end
    -- A default lease is not renewed by repeated travel signals. Only a new
    -- directive or an expired lease receives a fresh fifteen-game-minute bound.
    local expiry = expiresAtHours == nil and now + 0.25 or tonumber(expiresAtHours)
    if not finiteCoordinate(expiry) or expiry <= now then return nil, "expired_order" end
    local current = KnoxPersistence.getTravelGroupLeaderOrder(groupId, now)
    if current ~= nil and current.kind == nextOrder.kind
        and current.leaderId == leaderId
        and (expiresAtHours == nil or tonumber(current.expiresAtHours) == expiry) then
        return copySerializable(current), "unchanged"
    end
    group.leaderOrderRevision = (tonumber(group.leaderOrderRevision) or 0) + 1
    nextOrder.groupId = group.id
    nextOrder.issuedAtHours = now
    nextOrder.updatedAtHours = now
    nextOrder.expiresAtHours = expiry
    nextOrder.revision = group.leaderOrderRevision
    group.leaderOrder = nextOrder
    return copySerializable(nextOrder), "issued"
end

function KnoxPersistence.clearTravelGroupLeaderOrder(groupId, leaderId)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or group.leaderOrder == nil
        or type(leaderId) ~= "string" or group.leaderId ~= leaderId then
        return false
    end
    group.leaderOrder = nil
    group.leaderOrderRevision = (tonumber(group.leaderOrderRevision) or 0) + 1
    return true
end

function KnoxPersistence.setTravelGroupObjective(
    groupId,
    leaderId,
    intent,
    worldAgeHours
)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or group.leaderId ~= leaderId
        or not containsId(group.memberIds, leaderId)
        or not validLifeIntent(intent) then
        return false
    end
    local nextObjective = copySerializable(intent)
    nextObjective.leaderId = leaderId
    nextObjective.startedAtHours = tonumber(nextObjective.startedAtHours)
        or tonumber(worldAgeHours) or 0
    nextObjective.updatedAtHours = tonumber(worldAgeHours) or 0
    if sameLifeIntent(group.objective, nextObjective)
        and group.objective ~= nil
        and group.objective.leaderId == leaderId then
        return false
    end
    group.objectiveRevision = (tonumber(group.objectiveRevision) or 0) + 1
    nextObjective.revision = group.objectiveRevision
    group.objective = nextObjective
    return true
end

function KnoxPersistence.clearTravelGroupObjective(groupId, leaderId)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or (leaderId ~= nil and group.leaderId ~= leaderId)
        or group.objective == nil then
        return false
    end
    group.objective = nil
    group.objectiveRevision = (tonumber(group.objectiveRevision) or 0) + 1
    return true
end

function KnoxPersistence.removeTravelGroupMember(survivorId)
    local data = root()
    local removed = false
    local factionIds = {}
    local groupIds = {}
    for groupId in pairs(data.travelGroups) do groupIds[#groupIds + 1] = groupId end
    table.sort(groupIds)
    for _, groupId in ipairs(groupIds) do
        local group = data.travelGroups[groupId]
        if group ~= nil and containsId(group.memberIds, survivorId) then
            local retained = {}
            for _, memberId in ipairs(group.memberIds or {}) do
                if memberId ~= survivorId then
                    retained[#retained + 1] = memberId
                end
            end
            group.memberIds = retained
            if group.memberJoinedAtHours ~= nil then
                group.memberJoinedAtHours[survivorId] = nil
            end
            if group.factionId ~= nil then factionIds[group.factionId] = true end
            if group.leaderId == survivorId then
                group.leaderId = retained[1]
                group.objective = nil
                group.objectiveRevision = (tonumber(group.objectiveRevision) or 0) + 1
                group.leaderOrder = nil
                group.leaderOrderRevision = (tonumber(group.leaderOrderRevision) or 0) + 1
            end
            if #retained < 2 then data.travelGroups[groupId] = nil end
            removed = true
        end
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId) or {}
    if affiliation.factionId ~= nil and factionIds[affiliation.factionId] then
        KnoxPersistence.removeFactionMember(affiliation.factionId, survivorId)
    end
    if removed then
        local relationships = rawget(_G, "KnoxSurvivorRelationships")
        if relationships ~= nil
            and relationships.requestGroupAssignmentRefresh ~= nil then
            pcall(relationships.requestGroupAssignmentRefresh)
        end
    end
    return removed
end

function KnoxPersistence.getFaction(id)
    local faction = type(id) == "string" and root().factions[id] or nil
    if faction == nil then return nil end
    -- A faction owns its event identity, so repair malformed identity at this
    -- O(1) access boundary now that root reads no longer perform global repair.
    local identity = faction.eventIdentity
    if identity ~= nil and (type(identity) ~= "table"
        or type(identity.policyId) ~= "string" or identity.policyId == ""
        or type(identity.sourceEventId) ~= "string" or identity.sourceEventId == ""
        or (identity.basePolicy ~= "event_only" and identity.basePolicy ~= "optional")
        or not finiteCoordinate(identity.boundAtHours)
        or identity.boundAtHours < 0) then
        faction.eventIdentity = nil
    end
    return faction
end

function KnoxPersistence.getCamps()
    return root().camps
end

function KnoxPersistence.getFactionCamp(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    local campId = faction ~= nil and faction.campId or nil
    return campId ~= nil and root().camps[campId] or nil
end

-- Camps are deliberately lightweight shelter records.  They are not bases, do
-- not claim a SafeHouse, and do not create work/storage ownership; they merely
-- preserve where a homeless faction has gathered until it establishes a home.
function KnoxPersistence.createFactionCamp(factionId, location, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or faction.homeBase ~= nil or type(location) ~= "table"
        or tonumber(location.x) == nil or tonumber(location.y) == nil then
        return nil, "invalid_camp"
    end
    local existing = KnoxPersistence.getFactionCamp(factionId)
    if existing ~= nil then
        return existing, "existing"
    end
    -- Temporary camps still claim a small piece of ground. Do not let two
    -- factions silently occupy the same building or the same outdoor patch.
    for _, other in pairs(root().camps) do
        if other ~= nil and other.factionId ~= factionId then
            local sameBuilding = location.buildingId ~= nil
                and other.buildingId ~= nil
                and tostring(location.buildingId) == tostring(other.buildingId)
            local dx = (tonumber(location.x) or 0) - (tonumber(other.x) or 0)
            local dy = (tonumber(location.y) or 0) - (tonumber(other.y) or 0)
            local closeOutdoor = location.buildingId == nil and other.buildingId == nil
                and (tonumber(location.z) or 0) == (tonumber(other.z) or 0)
                and dx * dx + dy * dy <= 10 * 10
            if sameBuilding or closeOutdoor then
                return nil, "camp_location_claimed"
            end
        end
    end
    -- A persisted base is authoritative even when its engine safehouse object
    -- is not currently streamed. Do not let an outdoor faction camp appear
    -- inside a player/faction territory through that gap.
    local candidateMinX = tonumber(location.minX) or tonumber(location.x) or 0
    local candidateMinY = tonumber(location.minY) or tonumber(location.y) or 0
    local candidateMaxX = tonumber(location.maxX) or tonumber(location.x) or 0
    local candidateMaxY = tonumber(location.maxY) or tonumber(location.y) or 0
    local candidateZ = tonumber(location.z) or 0
    for _, base in pairs(root().bases) do
        if base ~= nil and base.territory ~= nil then
            local territory = base.territory
            local baseZ = tonumber(territory.z) or 0
            local baseMinX = tonumber(territory.minX) or tonumber(territory.x) or 0
            local baseMinY = tonumber(territory.minY) or tonumber(territory.y) or 0
            local baseMaxX = tonumber(territory.maxX)
                or (baseMinX + (tonumber(territory.width) or 1) - 1)
            local baseMaxY = tonumber(territory.maxY)
                or (baseMinY + (tonumber(territory.height) or 1) - 1)
            if candidateZ == baseZ and candidateMinX <= baseMaxX
                and candidateMaxX >= baseMinX and candidateMinY <= baseMaxY
                and candidateMaxY >= baseMinY then
                return nil, "camp_location_claimed"
            end
        end
    end
    if #(faction.memberIds or {}) < 2 then
        return nil, "not_enough_members"
    end
    local data = root()
    local id = "camp-" .. tostring(data.nextCampId)
    data.nextCampId = data.nextCampId + 1
    local campMembers = {}
    for _, memberId in ipairs(faction.memberIds or {}) do
        campMembers[#campMembers + 1] = memberId
    end
    local camp = {
        id = id,
        factionId = factionId,
        name = tostring(location.name or "Temporary Shelter"),
        x = math.floor(tonumber(location.x)),
        y = math.floor(tonumber(location.y)),
        z = math.floor(tonumber(location.z) or 0),
        buildingId = location.buildingId ~= nil and tostring(location.buildingId) or nil,
        minX = tonumber(location.minX) ~= nil and math.floor(tonumber(location.minX)) or nil,
        minY = tonumber(location.minY) ~= nil and math.floor(tonumber(location.minY)) or nil,
        maxX = tonumber(location.maxX) ~= nil and math.floor(tonumber(location.maxX)) or nil,
        maxY = tonumber(location.maxY) ~= nil and math.floor(tonumber(location.maxY)) or nil,
        memberIds = campMembers,
        createdAtHours = tonumber(worldAgeHours) or 0,
        lastGatheredAtHours = tonumber(worldAgeHours) or 0,
    }
    data.camps[id] = camp
    faction.campId = id
    return camp, "created"
end

function KnoxPersistence.syncFactionCampMembers(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    local camp = faction ~= nil and KnoxPersistence.getFactionCamp(factionId) or nil
    if faction == nil or camp == nil then
        return nil
    end
    if faction.homeBase ~= nil then
        KnoxPersistence.clearFactionCamp(
            factionId,
            "home_established",
            tonumber(camp.lastGatheredAtHours) or 0
        )
        return nil
    end
    local members = {}
    local seen = {}
    for _, survivorId in ipairs(faction.memberIds or {}) do
        local survivor = ensureSurvivorState(survivorId)
        if survivor ~= nil and survivor.alive ~= false
            and survivor.affiliation.factionId == factionId
            and not seen[survivorId] then
            seen[survivorId] = true
            members[#members + 1] = survivorId
        end
    end
    camp.memberIds = members
    return camp
end

function KnoxPersistence.getCampForSurvivor(survivorId)
    local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
    local camp = faction ~= nil and KnoxPersistence.syncFactionCampMembers(faction.id) or nil
    if camp == nil then
        return nil
    end
    for _, memberId in ipairs(camp.memberIds or {}) do
        if memberId == survivorId then
            return camp
        end
    end
    return nil
end

function KnoxPersistence.touchFactionCamp(factionId, worldAgeHours)
    local camp = KnoxPersistence.getFactionCamp(factionId)
    if camp ~= nil then
        camp.lastGatheredAtHours = tonumber(worldAgeHours) or camp.lastGatheredAtHours
    end
    return camp
end

function KnoxPersistence.clearFactionCamp(factionId, reason, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local camp = faction ~= nil and KnoxPersistence.getFactionCamp(factionId) or nil
    if faction == nil or camp == nil then return false end
    root().camps[camp.id] = nil
    faction.campId = nil
    faction.lastCampReason = tostring(reason or "cleared")
    faction.lastCampChangedAtHours = tonumber(worldAgeHours) or 0
    return true
end

function KnoxPersistence.getFactionForSurvivor(id)
    local survivor = ensureSurvivorState(id)
    if survivor ~= nil and survivor.affiliation.factionId ~= nil then
        local faction = KnoxPersistence.getFaction(survivor.affiliation.factionId)
        if faction ~= nil then
            return faction
        end
    end
    local group = KnoxPersistence.getTravelGroupFor(id)
    return group ~= nil and group.factionId ~= nil
        and KnoxPersistence.getFaction(group.factionId)
        or nil
end

-- Persisted affiliation and rosters are authoritative.  Runtime controllers
-- may cache characters for movement, but every friend-or-foe decision should
-- derive from this classifier so unloaded members and save/load agree.
function KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    if type(firstId) ~= "string" or type(secondId) ~= "string" then
        return "neutral"
    end
    if firstId == secondId then
        return "self"
    end
    if not KnoxPersistence.isSurvivorAlive(firstId)
        or not KnoxPersistence.isSurvivorAlive(secondId) then
        return "neutral"
    end
    local first = ensureSurvivorState(firstId)
    local second = ensureSurvivorState(secondId)
    if first == nil or second == nil then
        return "neutral"
    end
    local firstAffiliation = first.affiliation or {}
    local secondAffiliation = second.affiliation or {}
    if firstAffiliation.kind == "player" and secondAffiliation.kind == "player"
        and firstAffiliation.ownerId ~= nil
        and firstAffiliation.ownerId == secondAffiliation.ownerId then
        return "allied"
    end
    local firstGroup = KnoxPersistence.getTravelGroupFor(firstId)
    local secondGroup = KnoxPersistence.getTravelGroupFor(secondId)
    if firstGroup ~= nil and secondGroup ~= nil and firstGroup.id == secondGroup.id then
        return "allied"
    end
    local firstFaction = KnoxPersistence.getFactionForSurvivor(firstId)
    local secondFaction = KnoxPersistence.getFactionForSurvivor(secondId)
    if firstFaction ~= nil and secondFaction ~= nil and firstFaction.id == secondFaction.id then
        return "allied"
    end
    local personal = KnoxPersistence.getRelationship(firstId, secondId)
    if personal ~= nil and personal.disposition == "hostile" then
        return "hostile"
    end
    -- Flagged deserters want a home, not a fight: faction records never make
    -- them hostile (explicit personal hostility above still applies).
    local eitherDeserter = first.deserter == true or second.deserter == true
    if firstFaction ~= nil and secondFaction ~= nil then
        local factionDisposition = KnoxPersistence.getFactionDisposition(
            firstFaction.id, secondFaction.id
        )
        -- Flagged deserters seek a home rather than inheriting faction war.
        -- Explicit personal hostility above remains authoritative.
        if factionDisposition ~= "neutral" and not
            (factionDisposition == "hostile" and eitherDeserter) then
            return factionDisposition
        end
    end
    if personal ~= nil and personal.disposition == "allied" then
        return "allied"
    end
    return "neutral"
end

function KnoxPersistence.areSurvivorsAllied(firstId, secondId)
    local disposition = KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    return disposition == "self" or disposition == "allied"
end

function KnoxPersistence.areSurvivorsHostile(firstId, secondId)
    return KnoxPersistence.getSurvivorDisposition(firstId, secondId) == "hostile"
end

function KnoxPersistence.createTravelGroup(memberIds, worldAgeHours)
    if type(memberIds) ~= "table" or #memberIds < 2 then
        return nil
    end
    for _, id in ipairs(memberIds) do
        local survivor = type(id) == "string" and ensureSurvivorState(id) or nil
        local pendingIdentity = survivor ~= nil and survivor.record == nil
            and type(survivor.origin) == "table"
            and type(survivor.unloadedSurvival) == "table"
            and survivor.unloadedSurvival.pendingMaterialization == true
        if survivor == nil or (survivor.record == nil and not pendingIdentity) then
            return nil
        end
        local existing = KnoxPersistence.getTravelGroupFor(id)
        if existing ~= nil then
            return existing
        end
        if survivor.affiliation == nil or survivor.affiliation.kind ~= "independent"
            or survivor.duty == nil or survivor.duty.mode ~= "autonomous"
            or not KnoxPersistence.isIndependentSurvivor(id) then
            return nil
        end
    end
    local data = root()
    local id = "travel-group-" .. tostring(data.nextTravelGroupId)
    data.nextTravelGroupId = data.nextTravelGroupId + 1
    local members = {}
    for _, memberId in ipairs(memberIds) do
        if type(memberId) == "string" and memberId ~= ""
            and not containsId(members, memberId) then
            members[#members + 1] = memberId
        end
    end
    if #members < 2 then
        return nil
    end
    table.sort(members)
    local group = {
        id = id,
        leaderId = members[1],
        memberIds = members,
        formedAtHours = tonumber(worldAgeHours) or 0,
        memberJoinedAtHours = {},
        factionId = nil,
        objective = nil,
        objectiveRevision = 0,
        leaderOrder = nil,
        leaderOrderRevision = 0,
    }
    for _, memberId in ipairs(members) do
        group.memberJoinedAtHours[memberId] = group.formedAtHours
    end
    data.travelGroups[id] = group
    for firstIndex = 1, #members do
        for secondIndex = firstIndex + 1, #members do
            KnoxPersistence.setRelationshipDisposition(
                members[firstIndex], members[secondIndex], "allied", worldAgeHours
            )
        end
    end
    return group
end

function KnoxPersistence.addTravelGroupMember(groupId, survivorId)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or type(survivorId) ~= "string" or survivorId == "" then
        return nil
    end
    local survivorState = root().survivors[survivorId]
    if survivorState == nil or survivorState.record == nil then
        return nil
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil or duty.mode ~= "autonomous"
        or affiliation == nil or (affiliation.kind ~= "independent"
        and affiliation.factionId ~= group.factionId) then
        return nil
    end
    local otherGroup = KnoxPersistence.getTravelGroupFor(survivorId)
    if otherGroup ~= nil and otherGroup.id ~= group.id then
        return nil
    end
    local alreadyMember = containsId(group.memberIds, survivorId)
    if group.factionId ~= nil and not alreadyMember then
        local settings = rawget(_G, "KnoxSettings")
        local maximum = settings ~= nil and settings.npcFactionMaxMembers ~= nil
            and settings.npcFactionMaxMembers() or 8
        if #group.memberIds >= math.max(3, tonumber(maximum) or 8) then
            return nil, "faction_member_limit"
        end
    end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if group.factionId ~= nil and not alreadyMember
        and not KnoxPersistence.addFactionMember(group.factionId, survivorId, now) then
        -- Faction admission owns lifecycle, affiliation, and away-team gates.
        -- Do not report a group join or mutate relationships when that
        -- authoritative membership owner rejects the survivor.
        return nil, "faction_admission_rejected"
    end
    if not alreadyMember then
        group.memberIds[#group.memberIds + 1] = survivorId
        table.sort(group.memberIds)
        group.memberJoinedAtHours = group.memberJoinedAtHours or {}
        group.memberJoinedAtHours[survivorId] = now
    end
    for _, memberId in ipairs(group.memberIds) do
        if memberId ~= survivorId then
            KnoxPersistence.setRelationshipDisposition(
                memberId,
                survivorId,
                "allied",
                now
            )
        end
    end
    if group.factionId ~= nil then
        -- A faction that already owns a home must admit a new member into the
        -- same resident lifecycle immediately. Leaving the survivor in
        -- autonomous duty would make them appear recruited while the base
        -- roster and task planner never see them.
        local faction = KnoxPersistence.getFaction(group.factionId)
        if faction ~= nil and faction.homeBaseId ~= nil then
            local resident, residentResult = KnoxPersistence.setFactionBaseResident(
                survivorId,
                group.factionId,
                faction.homeBaseId,
                now
            )
            if resident and residentResult ~= "existing"
                and rawget(_G, "KnoxSurvivorRuntime") ~= nil
                and KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
                KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
            end
        end
    end
    return group
end

-- Read-only readiness is shared by simulation and developer diagnostics.
function KnoxPersistence.getFactionReadiness(groupId, minimumMembers)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    local required = math.max(3, math.floor(tonumber(minimumMembers) or 3))
    local status={groupId=groupId,required=required,members=group~=nil and #group.memberIds or 0,
        sharedMembers=0,missingShared={}}
    if group==nil then status.reason="group_unavailable";return status end
    status.factionId=group.factionId
    if group.factionId~=nil then status.reason="already_faction";return status end
    for _,memberId in ipairs(group.memberIds) do
        local ready=memberId==group.leaderId
        if not ready then
            local relationship=KnoxPersistence.getRelationship(group.leaderId,memberId)
            local shared=relationship~=nil and ((relationship.sharedRoam or 0)
                +(relationship.sharedLoot or 0)+(relationship.sharedCombat or 0)) or 0
            ready=relationship~=nil and ((relationship.nearbyHours or 0)>=1 or shared>=1)
        end
        if ready then status.sharedMembers=status.sharedMembers+1
        else status.missingShared[#status.missingShared+1]=memberId end
    end
    status.reason=status.members<required and ("requires_"..required.."_members")
        or (#status.missingShared>0 and "requires_shared_survival" or "ready")
    return status
end

function KnoxPersistence.evaluateTravelGroupFaction(groupId, worldAgeHours, minimumMembers)
    local status=KnoxPersistence.getFactionReadiness(groupId,minimumMembers)
    if status.reason=="already_faction" then return root().factions[status.factionId],"already_faction" end
    if status.reason~="ready" then return nil,status.reason end
    return KnoxPersistence.promoteTravelGroupToFaction(groupId,tonumber(worldAgeHours) or 0,status.required)
end

function KnoxPersistence.promoteTravelGroupToFaction(groupId, worldAgeHours, minimumMembers)
    local data = root()
    local group = type(groupId) == "string" and data.travelGroups[groupId] or nil
    local required = math.max(3, math.floor(tonumber(minimumMembers) or 3))
    if group == nil or #group.memberIds < required then
        return nil, "requires_" .. tostring(required) .. "_members"
    end
    for _, memberId in ipairs(group.memberIds) do
        local survivor = ensureSurvivorState(memberId)
        if survivor.affiliation.kind == "player"
            or survivor.duty.mode == "companion"
            or survivor.duty.mode == "base" and survivor.affiliation.kind == "player" then
            KnoxPersistence.removeTravelGroupMember(memberId)
            return nil, "contains_player_survivor"
        end
    end
    if group.factionId ~= nil then
        return data.factions[group.factionId], "already_faction"
    end
    local factionId = "faction-" .. tostring(data.nextFactionId)
    data.nextFactionId = data.nextFactionId + 1
    local faction = {
        id = factionId,
        kind = "npc",
        leaderId = group.leaderId,
        memberIds = copyIds(group.memberIds),
        formedAtHours = tonumber(worldAgeHours) or 0,
        homeSafehouse = nil,
    }
    faction.name = uniqueFactionName(data, factionId, faction)
    data.factions[factionId] = faction
    group.factionId = factionId
    for _, memberId in ipairs(group.memberIds) do
        local survivor = ensureSurvivorState(memberId)
        survivor.affiliation.kind = "faction"
        survivor.affiliation.ownerId = nil
        KnoxPersistence.addFactionMember(factionId, memberId, worldAgeHours)
    end
    return faction, "created"
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function livingIds(data, ids)
    local result = {}
    for _, id in ipairs(ids or {}) do
        local survivor = type(id) == "string" and data.survivors[id] or nil
        if survivor ~= nil and survivor.alive ~= false and not containsId(result, id) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

-- Repair old or interrupted saves at one persistence boundary.  This is not a
-- second relationship model: it removes contradictory roster copies and then
-- rebuilds each survivor's affiliation from the single retained owner.
function KnoxPersistence.normalizeRelationshipDomains()
    local data = root()
    local changes = 0
    local factionOwner = {}
    local factionIds = sortedKeys(data.factions)

    local collapsedFactionIds = {}
    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        faction.id = faction.id or factionId
        if faction.homeBaseId ~= nil then
            local linkedBase = data.bases[faction.homeBaseId]
            if linkedBase == nil or linkedBase.ownerKind ~= "faction"
                or linkedBase.ownerId ~= factionId then
                -- Keep homeBase (the durable shelter definition) so the base
                -- manager can rebuild it, but discard only the invalid runtime
                -- link during save normalization.
                faction.homeBaseId = nil
                changes = changes + 1
            end
        end
        local cleaned = livingIds(data, faction.memberIds)
        if #cleaned ~= #(faction.memberIds or {}) then changes = changes + 1 end
        faction.memberIds = cleaned
    end

    -- A valid persisted affiliation wins over duplicate roster copies.
    for survivorId, survivor in pairs(data.survivors) do
        local affiliation = type(survivor) == "table" and survivor.affiliation or nil
        local factionId = affiliation ~= nil and affiliation.factionId or nil
        local faction = factionId ~= nil and data.factions[factionId] or nil
        local duty = type(survivor) == "table" and survivor.duty or nil
        local playerOwnerId = affiliation ~= nil and affiliation.kind == "player"
            and affiliation.ownerId
            or (duty ~= nil and (duty.mode == "companion" or duty.mode == "base")
                and duty.ownerId or nil)
        local player = playerOwnerId ~= nil and data.players[playerOwnerId] or nil
        local playerFaction = player ~= nil and data.factions[player.factionId] or nil
        if playerFaction ~= nil and playerFaction.kind == "player"
            and playerFaction.ownerPlayerId == playerOwnerId then
            factionId = playerFaction.id
            faction = playerFaction
        end
        if survivor.alive ~= false and faction ~= nil then
            factionOwner[survivorId] = factionId
            if not containsId(faction.memberIds, survivorId) then
                faction.memberIds[#faction.memberIds + 1] = survivorId
                table.sort(faction.memberIds)
                changes = changes + 1
            end
        elseif affiliation ~= nil and factionId ~= nil then
            survivor.affiliation = { kind = "independent", ownerId = nil }
            changes = changes + 1
        end
    end

    -- Deterministically retain the first valid roster only when affiliation did
    -- not already identify an owner.
    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        local retained = {}
        for _, survivorId in ipairs(faction.memberIds) do
            local owner = factionOwner[survivorId]
            if owner == nil or owner == factionId then
                factionOwner[survivorId] = factionId
                retained[#retained + 1] = survivorId
            else
                changes = changes + 1
            end
        end
        faction.memberIds = retained
    end

    for survivorId, factionId in pairs(factionOwner) do
        local survivor = data.survivors[survivorId]
        local faction = data.factions[factionId]
        local expectedKind = faction.kind == "player" and "player" or "faction"
        local expectedOwner = faction.kind == "player" and faction.ownerPlayerId or nil
        if survivor.affiliation.kind ~= expectedKind
            or survivor.affiliation.factionId ~= factionId
            or survivor.affiliation.ownerId ~= expectedOwner then
            survivor.affiliation = {
                kind = expectedKind,
                ownerId = expectedOwner,
                factionId = factionId,
            }
            changes = changes + 1
        end
    end

    local groupOwner = {}
    local groupIds = sortedKeys(data.travelGroups)
    for _, groupId in ipairs(groupIds) do
        local group = data.travelGroups[groupId]
        group.id = group.id or groupId
        if group.factionId ~= nil and data.factions[group.factionId] == nil then
            group.factionId = nil
            changes = changes + 1
        end
        local retained = {}
        for _, survivorId in ipairs(livingIds(data, group.memberIds)) do
            local survivor = data.survivors[survivorId]
            local affiliation = survivor.affiliation or {}
            local compatible = affiliation.kind ~= "player"
                and (group.factionId == nil or affiliation.factionId == group.factionId)
            if compatible and groupOwner[survivorId] == nil then
                groupOwner[survivorId] = groupId
                retained[#retained + 1] = survivorId
            else
                changes = changes + 1
            end
        end
        group.memberIds = retained
        if #retained < 2 then
            for _, survivorId in ipairs(retained) do
                if groupOwner[survivorId] == groupId then
                    groupOwner[survivorId] = nil
                end
            end
            data.travelGroups[groupId] = nil
            changes = changes + 1
        else
            if not containsId(retained, group.leaderId) then
                group.leaderId = retained[1]
                -- A shared objective belongs to its leader. Clear it during
                -- the ownership transition rather than relying on a later
                -- whole-save normalization pass to discover the mismatch.
                if group.objective ~= nil then
                    group.objective = nil
                    group.objectiveRevision = (tonumber(group.objectiveRevision) or 0) + 1
                end
                -- Direct removal already retires the old leader's order. Apply
                -- the same rule when repairing an interrupted or legacy save;
                -- getters reject stale issuers, but leaving the record behind
                -- would preserve a directive that no current leader owns.
                if group.leaderOrder ~= nil then
                    group.leaderOrder = nil
                    group.leaderOrderRevision = (tonumber(group.leaderOrderRevision) or 0) + 1
                end
                changes = changes + 1
            end
        end
    end

    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        if faction ~= nil then
            if faction.kind ~= "player" and #faction.memberIds == 0
                and not (faction.lifecycle == "departed"
                    and type(faction.eventIdentity) == "table") then
                if faction.campId ~= nil then data.camps[faction.campId] = nil end
                data.factions[factionId] = nil
                collapsedFactionIds[factionId] = true
                changes = changes + 1
            elseif faction.kind ~= "player" and not containsId(
                faction.memberIds,
                faction.leaderId
            ) then
                faction.leaderId = faction.memberIds[1]
                changes = changes + 1
            end
        end
    end

    -- A collapsed faction owns neither territory nor diplomacy. Remove its
    -- complete base record (tasks, zones and storage included), and release
    -- the generated engine safehouse when that API is available. Player bases
    -- are never included in this cleanup.
    for baseId, base in pairs(data.bases) do
        if base ~= nil and base.ownerKind == "faction"
            and (collapsedFactionIds[base.ownerId] == true
                or data.factions[base.ownerId] == nil) then
            local safehouseApi = rawget(_G, "SafeHouse")
            if safehouseApi ~= nil and safehouseApi.getSafehouseByOwner ~= nil
                and safehouseApi.removeSafeHouse ~= nil then
                pcall(function()
                    local safehouse = safehouseApi.getSafehouseByOwner(
                        "KnoxSurvivors:" .. tostring(base.ownerId)
                    )
                    if safehouse ~= nil then safehouseApi.removeSafeHouse(safehouse) end
                end)
            end
            data.bases[baseId] = nil
            changes = changes + 1
        end
    end
    for relationshipKey, relationship in pairs(data.factionRelationships) do
        local first = relationship ~= nil and relationship.firstFactionId or nil
        local second = relationship ~= nil and relationship.secondFactionId or nil
        if data.factions[first] == nil or data.factions[second] == nil then
            data.factionRelationships[relationshipKey] = nil
            changes = changes + 1
        end
    end
    for _, group in pairs(data.travelGroups) do
        if group ~= nil and group.factionId ~= nil
            and data.factions[group.factionId] == nil then
            group.factionId = nil
            group.objective = nil
            group.objectiveRevision = (tonumber(group.objectiveRevision) or 0) + 1
            changes = changes + 1
        end
    end
    for _, survivor in pairs(data.survivors) do
        local duty = type(survivor) == "table" and survivor.duty or nil
        if duty ~= nil and duty.mode == "base" and data.bases[duty.baseId] == nil
            and survivor.alive ~= false then
            survivor.duty = {
                mode = "autonomous", order = "survive",
                revision = (tonumber(duty.revision) or 0) + 1,
            }
            changes = changes + 1
        end
    end

    for campId, camp in pairs(data.camps) do
        local faction = type(camp) == "table" and data.factions[camp.factionId] or nil
        if faction == nil or faction.campId ~= campId then
            data.camps[campId] = nil
            changes = changes + 1
        else
            camp.memberIds = livingIds(data, faction.memberIds)
        end
    end
    return changes
end

local function removeSurvivorFromSocialDomains(id, lifecycle, reason, worldAgeHours)
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    if survivor == nil then return false end
    local formerFactionId = (survivor.affiliation or {}).factionId
    requeueClaimsForSurvivor(id, nil, reason or "social_membership_removed")
    for _, group in pairs(data.travelGroups) do
        local retained = {}
        for _, memberId in ipairs(group.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        group.memberIds = retained
    end
    for _, faction in pairs(data.factions) do
        local retained = {}
        for _, memberId in ipairs(faction.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        faction.memberIds = retained
    end
    for _, camp in pairs(data.camps) do
        local retained = {}
        for _, memberId in ipairs(camp.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        camp.memberIds = retained
    end
    survivor.formerAffiliation = copySerializable(survivor.affiliation)
    survivor.affiliation = { kind = lifecycle, ownerId = nil }
    survivor.duty = {
        mode = lifecycle,
        order = "none",
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty ~= nil and survivor.duty.revision) or 0) + 1,
    }
    if lifecycle == "departed" then
        local faction = formerFactionId ~= nil and data.factions[formerFactionId] or nil
        if type(faction) == "table" and type(faction.eventIdentity) == "table"
            and #(faction.memberIds or {}) == 0 then
            faction.lifecycle = "departed"
            faction.departedAtHours = tonumber(worldAgeHours) or 0
            faction.leaderId = nil
        end
    end
    KnoxPersistence.normalizeRelationshipDomains()
    return true
end

function KnoxPersistence.removeSurvivorFromSocialDomains(id, reason, worldAgeHours)
    return removeSurvivorFromSocialDomains(id, "deceased", reason, worldAgeHours)
end

-- Event-only factions leave through their real entry anchor. Departure is not
-- death and therefore deliberately keeps alive=true, identity, record, gear and
-- relationship history. The pending state is already excluded from activation;
-- the autonomy owner must capture/remove a loaded shell before finalization.
function KnoxPersistence.beginEventDeparture(id, eventId, worldAgeHours)
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    local event = type(eventId) == "string" and data.knoxEvents.records[eventId] or nil
    local duty = survivor ~= nil and survivor.duty or nil
    local affiliation = survivor ~= nil and survivor.affiliation or nil
    local faction = affiliation ~= nil and data.factions[affiliation.factionId] or nil
    local identity = faction ~= nil and faction.eventIdentity or nil
    local hours = tonumber(worldAgeHours)
    if survivor == nil or survivor.alive == false or event == nil
        or event.kind ~= "faction_entry" or event.phase ~= "withdrawing"
        or not containsId(event.memberIds, id) or duty == nil or duty.eventId ~= eventId
        or identity == nil or identity.sourceEventId ~= eventId
        or survivor.eventManaged ~= true or survivor.eventSourceId ~= eventId
        or not finiteCoordinate(hours) or hours < 0 then
        return false, "departure_not_owned"
    end
    local current = survivor.departure
    if type(current) == "table" then
        if current.eventId ~= eventId then return false, "departure_already_owned" end
        return true, current.status
    end
    survivor.departure = {
        status = "pending",
        source = "knox_event",
        eventId = eventId,
        requestedAtHours = hours,
        reason = "event_party_withdrew",
    }
    return true, "pending"
end

function KnoxPersistence.finalizeEventDeparture(id, eventId, worldAgeHours)
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    local departure = survivor ~= nil and survivor.departure or nil
    local hours = tonumber(worldAgeHours)
    if survivor == nil or survivor.alive == false or type(departure) ~= "table"
        or departure.eventId ~= eventId or departure.status ~= "pending"
        or not finiteCoordinate(hours)
        or hours < (tonumber(departure.requestedAtHours) or math.huge) then
        return false, "departure_not_pending"
    end
    local formerFactionId = (survivor.affiliation or {}).factionId
    removeSurvivorFromSocialDomains(id, "departed", "event_departed", hours)
    departure.status = "departed"
    departure.completedAtHours = hours
    survivor.departure = departure
    survivor.eventManaged = false
    -- A departed survivor is gone from the county: drop any entry-wait marker
    -- so it can never freeze a future activation at the old anchor.
    local unloaded = survivor.unloadedSurvival
    if type(unloaded) == "table" and unloaded.eventEntryId == eventId then
        unloaded.eventEntryId = nil
        unloaded.activity = "departed"
    end
    local faction = formerFactionId ~= nil and data.factions[formerFactionId] or nil
    if faction ~= nil and type(faction.eventIdentity) == "table"
        and faction.eventIdentity.sourceEventId == eventId
        and #(faction.memberIds or {}) == 0 then
        faction.lifecycle = "departed"
        faction.departedAtHours = hours
        faction.leaderId = nil
    end
    return true, "departed"
end

function KnoxPersistence.getPendingEventDepartureIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and type(survivor.departure) == "table"
            and survivor.departure.status == "pending" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getFactionBaseCandidate(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    return faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.candidate
        or nil
end

-- A scouting result is a lead, not a permanent claim.  If the world changes
-- (or the leader cannot reach the building) an old lead must eventually be
-- reconsidered instead of pinning the faction to it forever.
function KnoxPersistence.expireFactionBaseCandidate(factionId, worldAgeHours, maxAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local search = faction ~= nil and faction.baseSearch or nil
    local candidate = search ~= nil and search.candidate or nil
    if candidate == nil then return false end
    local discovered = tonumber(candidate.discoveredAtHours)
    local now = tonumber(worldAgeHours) or 0
    local maxAge = math.max(1, tonumber(maxAgeHours) or 72)
    if discovered ~= nil and discovered + maxAge <= now then
        search.candidate = nil
        return true
    end
    return false
end

function KnoxPersistence.isFactionBaseCandidateRejected(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local rejected = faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.rejected
        or nil
    local rejectedUntil = rejected ~= nil and tonumber(rejected[buildingId]) or nil
    if rejectedUntil ~= nil and rejectedUntil <= (tonumber(worldAgeHours) or 0) then
        rejected[buildingId] = nil
        return false
    end
    return rejectedUntil ~= nil
end

function KnoxPersistence.recordFactionBaseCandidate(factionId, candidate, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or faction.homeBase ~= nil or type(candidate) ~= "table"
        or type(candidate.buildingId) ~= "string" then
        return nil, "invalid_candidate"
    end
    faction.baseSearch = faction.baseSearch or { rejected = {} }
    faction.baseSearch.rejected = faction.baseSearch.rejected or {}
    local rejectedUntil = tonumber(faction.baseSearch.rejected[candidate.buildingId]) or 0
    if rejectedUntil > (tonumber(worldAgeHours) or 0) then
        return nil, "candidate_rejected"
    end
    local current = faction.baseSearch.candidate
    if current == nil or (tonumber(candidate.score) or 0) > (tonumber(current.score) or 0) then
        candidate.discoveredAtHours = tonumber(worldAgeHours) or 0
        faction.baseSearch.candidate = candidate
        return candidate, "recorded"
    end
    return current, "kept_better_candidate"
end

function KnoxPersistence.rejectFactionBaseCandidate(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or type(buildingId) ~= "string" then
        return false
    end
    faction.baseSearch = faction.baseSearch or { rejected = {} }
    faction.baseSearch.rejected = faction.baseSearch.rejected or {}
    faction.baseSearch.rejected[buildingId] = (tonumber(worldAgeHours) or 0) + 24
    if faction.baseSearch.candidate ~= nil
        and faction.baseSearch.candidate.buildingId == buildingId then
        faction.baseSearch.candidate = nil
    end
    return true
end

function KnoxPersistence.confirmFactionHomeBase(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local candidate = faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.candidate
        or nil
    if candidate == nil or candidate.buildingId ~= buildingId then
        return nil, "candidate_mismatch"
    end
    -- Revalidate ownership at the commit boundary.  A building can become a
    -- player/faction base or vanilla safehouse after scouting but before the
    -- leader arrives.  Never let a stale candidate create overlapping claims.
    local minX, minY = tonumber(candidate.minX), tonumber(candidate.minY)
    local width, height = tonumber(candidate.width), tonumber(candidate.height)
    if minX ~= nil and minY ~= nil and width ~= nil and height ~= nil then
        local maxX, maxY = minX + width - 1, minY + height - 1
        for otherId, other in pairs(root().bases or {}) do
            local area = other ~= nil and (other.territory or other.home) or nil
            if otherId ~= (faction.homeBaseId or "") and area ~= nil
                and tonumber(area.z or 0) == tonumber(candidate.z or 0) then
                local otherMaxX = tonumber(area.maxX)
                    or (tonumber(area.minX) or 0) + (tonumber(area.width) or 1) - 1
                local otherMaxY = tonumber(area.maxY)
                    or (tonumber(area.minY) or 0) + (tonumber(area.height) or 1) - 1
                if minX <= otherMaxX and maxX >= (tonumber(area.minX) or 0)
                    and minY <= otherMaxY and maxY >= (tonumber(area.minY) or 0) then
                    faction.baseSearch.candidate = nil
                    return nil, "overlaps_existing_base"
                end
            end
        end
        local safehouseApi = rawget(_G, "SafeHouse")
        if safehouseApi ~= nil and type(safehouseApi.getSafehouseOverlapping) == "function" then
            local ok, existing = pcall(
                safehouseApi.getSafehouseOverlapping,
                minX, minY, maxX + 1, maxY + 1
            )
            if ok and existing ~= nil then
                faction.baseSearch.candidate = nil
                return nil, "overlaps_existing_safehouse"
            end
        end
    end
    candidate.selectedAtHours = tonumber(worldAgeHours) or 0
    faction.homeBase = candidate
    faction.baseSearch.candidate = nil
    -- Home selection is the terminal result of the leader's shelter-scout
    -- purpose. Retire both durable summaries in the same transaction as the
    -- home claim so a save, unload, or delayed controller sync cannot send the
    -- group back toward a completed scouting objective.
    KnoxPersistence.clearSurvivorLifeIntent(faction.leaderId)
    local group = KnoxPersistence.getTravelGroupFor(faction.leaderId)
    if group ~= nil and group.factionId == factionId then
        KnoxPersistence.clearTravelGroupObjective(group.id, faction.leaderId)
    end
    KnoxPersistence.clearFactionCamp(factionId, "home_established", worldAgeHours)
    return faction.homeBase, "selected"
end

local function copyWorldArea(source)
    if type(source) ~= "table" then
        return nil
    end
    return {
        buildingId = source.buildingId,
        x = tonumber(source.x),
        y = tonumber(source.y),
        z = tonumber(source.z) or 0,
        minX = tonumber(source.minX),
        minY = tonumber(source.minY),
        width = tonumber(source.width),
        height = tonumber(source.height),
        score = tonumber(source.score),
    }
end

function KnoxPersistence.getBases()
    return root().bases
end

function KnoxPersistence.getBase(id)
    return type(id) == "string" and root().bases[id] or nil
end

local RAID_HISTORY_LIMIT = 12
local TRACE_SITE_LIMIT = 24
local TRACE_SITE_TTL_HOURS = 7 * 24

-- Completed raid log for faction cards and history. Capped, newest last;
-- readers show newest first. Same-save safe: a new optional root key.
function KnoxPersistence.recordRaidHistory(entry)
    if type(entry) ~= "table" then return false end
    local data = root()
    data.raidHistory = data.raidHistory or {}
    data.raidHistory[#data.raidHistory + 1] = {
        atHours = tonumber(entry.atHours) or 0,
        sourceFactionId = tostring(entry.sourceFactionId or ""),
        sourceName = tostring(entry.sourceName or ""),
        targetBaseId = tostring(entry.targetBaseId or ""),
        targetName = tostring(entry.targetName or ""),
        outcome = tostring(entry.outcome or "unknown"),
    }
    while #data.raidHistory > RAID_HISTORY_LIMIT do
        table.remove(data.raidHistory, 1)
    end
    return true
end

function KnoxPersistence.getRaidHistory()
    local data = root()
    local history = {}
    for _, entry in ipairs(type(data.raidHistory) == "table" and data.raidHistory or {}) do
        history[#history + 1] = copySerializable(entry)
    end
    return history
end

-- World trace sites: abstract fights and breaches leave records here, and
-- the materializer turns them into blood and broken windows when a player
-- approaches. Capped with age expiry; visited sites never re-materialize.
function KnoxPersistence.recordTraceSite(kind, x, y, z, atHours)
    if kind ~= "fight" and kind ~= "breach" then return nil end
    x, y, z = tonumber(x), tonumber(y), tonumber(z or 0)
    if x == nil or y == nil then return nil end
    local data = root()
    data.traceSites = data.traceSites or {}
    data.nextTraceId = (tonumber(data.nextTraceId) or 0) + 1
    local site = {
        id = "trace-" .. tostring(data.nextTraceId),
        kind = kind, x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        atHours = tonumber(atHours) or 0, visited = false,
    }
    data.traceSites[#data.traceSites + 1] = site
    KnoxPersistence.pruneTraceSites(site.atHours)
    return site.id
end

function KnoxPersistence.pruneTraceSites(nowHours)
    local data = root()
    if type(data.traceSites) ~= "table" then
        data.traceSites = {}
        return 0
    end
    local now = tonumber(nowHours) or 0
    local kept = {}
    for _, site in ipairs(data.traceSites) do
        if type(site) == "table" and now - (tonumber(site.atHours) or 0) <= TRACE_SITE_TTL_HOURS then
            kept[#kept + 1] = site
        end
    end
    while #kept > TRACE_SITE_LIMIT do
        local victim = 1
        for index, site in ipairs(kept) do
            if site.visited and not kept[victim].visited then victim = index; break end
            if (tonumber(site.atHours) or 0) < (tonumber(kept[victim].atHours) or 0) then
                victim = index
            end
        end
        table.remove(kept, victim)
    end
    data.traceSites = kept
    return #kept
end

function KnoxPersistence.getTraceSites()
    local data = root()
    local sites = {}
    for _, site in ipairs(type(data.traceSites) == "table" and data.traceSites or {}) do
        sites[#sites + 1] = copySerializable(site)
    end
    return sites
end

function KnoxPersistence.markTraceVisited(id)
    local data = root()
    for _, site in ipairs(type(data.traceSites) == "table" and data.traceSites or {}) do
        if type(site) == "table" and tostring(site.id or "") == tostring(id) then
            site.visited = true
            return true
        end
    end
    return false
end

-- Territory is the durable ownership boundary for both player and NPC bases.
-- Keep this lookup in persistence so interaction rules cannot drift from base
-- creation, relocation, or save restoration.
function KnoxPersistence.getBaseAtSquare(x, y, z, ownerKind)
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if x == nil or y == nil then return nil end
    local selected = nil
    for _, base in pairs(root().bases) do
        local territory = base ~= nil and (base.territory or base.home) or nil
        local minX = territory ~= nil and tonumber(territory.minX) or nil
        local minY = territory ~= nil and tonumber(territory.minY) or nil
        local maxX = territory ~= nil and tonumber(territory.maxX)
            or (minX ~= nil and minX + math.max(1, tonumber(territory.width) or 1) - 1)
        local maxY = territory ~= nil and tonumber(territory.maxY)
            or (minY ~= nil and minY + math.max(1, tonumber(territory.height) or 1) - 1)
        local baseZ = territory ~= nil and tonumber(territory.z) or 0
        local onFloor = territory ~= nil and territory.allFloors == true or z == baseZ
        if (ownerKind == nil or base.ownerKind == ownerKind)
            and minX ~= nil and minY ~= nil and x >= minX and x <= maxX
            and y >= minY and y <= maxY and onFloor then
            -- Territories cannot overlap. Stable tie-breaking still makes a
            -- corrupted legacy save deterministic instead of table-order based.
            if selected == nil or tostring(base.id) < tostring(selected.id) then
                selected = base
            end
        end
    end
    return selected
end

function KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
    -- Deterministic primary: the earliest-established base. Single-base
    -- saves behave exactly as before; multi-base owners resolve here.
    local primary, primaryAt = nil, nil
    for _, base in pairs(root().bases) do
        if base ~= nil and base.ownerKind == ownerKind and base.ownerId == ownerId then
            local at = tonumber(base.createdAtHours) or 0
            if primary == nil or at < primaryAt then
                primary, primaryAt = base, at
            end
        end
    end
    return primary
end

-- All bases for an owner, oldest first. Empty table when none.
function KnoxPersistence.getBasesForOwner(ownerKind, ownerId)
    local list = {}
    for _, base in pairs(root().bases) do
        if base ~= nil and base.ownerKind == ownerKind and base.ownerId == ownerId then
            list[#list + 1] = base
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.createdAtHours) or 0) < (tonumber(b.createdAtHours) or 0)
    end)
    return list
end

local PLAYER_BASE_NAME_MAX_CODEPOINTS = 32

local function trimPlayerBaseName(value)
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function utf8CodepointCount(value)
    local count, index = 0, 1
    local length = #value
    while index <= length do
        local first = string.byte(value, index)
        local second = string.byte(value, index + 1)
        local third = string.byte(value, index + 2)
        local fourth = string.byte(value, index + 3)
        local width
        if first <= 0x7F then
            width = 1
        elseif first >= 0xC2 and first <= 0xDF
            and second ~= nil and second >= 0x80 and second <= 0xBF then
            width = 2
        elseif first == 0xE0 and second ~= nil and second >= 0xA0 and second <= 0xBF
            and third ~= nil and third >= 0x80 and third <= 0xBF then
            width = 3
        elseif ((first >= 0xE1 and first <= 0xEC) or (first >= 0xEE and first <= 0xEF))
            and second ~= nil and second >= 0x80 and second <= 0xBF
            and third ~= nil and third >= 0x80 and third <= 0xBF then
            width = 3
        elseif first == 0xED and second ~= nil and second >= 0x80 and second <= 0x9F
            and third ~= nil and third >= 0x80 and third <= 0xBF then
            width = 3
        elseif first == 0xF0 and second ~= nil and second >= 0x90 and second <= 0xBF
            and third ~= nil and third >= 0x80 and third <= 0xBF
            and fourth ~= nil and fourth >= 0x80 and fourth <= 0xBF then
            width = 4
        elseif first >= 0xF1 and first <= 0xF3
            and second ~= nil and second >= 0x80 and second <= 0xBF
            and third ~= nil and third >= 0x80 and third <= 0xBF
            and fourth ~= nil and fourth >= 0x80 and fourth <= 0xBF then
            width = 4
        elseif first == 0xF4 and second ~= nil and second >= 0x80 and second <= 0x8F
            and third ~= nil and third >= 0x80 and third <= 0xBF
            and fourth ~= nil and fourth >= 0x80 and fourth <= 0xBF then
            width = 4
        else
            return nil
        end
        count = count + 1
        if count > PLAYER_BASE_NAME_MAX_CODEPOINTS then return count end
        index = index + width
    end
    return count
end

local function playerBaseNameKey(value)
    -- ASCII case folding is deterministic in Lua 5.1/Kahlua and leaves UTF-8
    -- bytes untouched. Non-ASCII names still reject exact duplicates.
    return (value:gsub("[A-Z]", function(letter)
        return string.char(string.byte(letter) + 32)
    end))
end

function KnoxPersistence.renamePlayerBase(baseId, playerId, requestedName)
    if type(baseId) ~= "string" or baseId == ""
        or type(playerId) ~= "string" or playerId == "" then
        return nil, "invalid_owner_or_base"
    end
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return nil, "invalid_base" end
    if base.ownerKind ~= "player" or base.ownerId ~= playerId then
        return nil, "not_player_owned"
    end
    if type(requestedName) ~= "string" then return nil, "invalid_name" end

    local name = trimPlayerBaseName(requestedName)
    if name == "" then return nil, "blank_name" end
    if string.find(name, "[%z\1-\31\127]") ~= nil then
        return nil, "invalid_name"
    end
    local length = utf8CodepointCount(name)
    if length == nil then return nil, "invalid_name_encoding" end
    if length > PLAYER_BASE_NAME_MAX_CODEPOINTS then return nil, "name_too_long" end

    local nameKey = playerBaseNameKey(name)
    for _, other in ipairs(KnoxPersistence.getBasesForOwner("player", playerId)) do
        if other ~= nil and other.id ~= baseId and type(other.name) == "string" then
            local otherName = trimPlayerBaseName(other.name)
            if otherName ~= "" and playerBaseNameKey(otherName) == nameKey then
                return nil, "duplicate_name"
            end
        end
    end

    if base.name == name then return base, "unchanged" end
    base.name = name
    return base, "renamed"
end

-- Automated QA may create faction safehouses in a disposable save. Remove
-- only bases whose entire membership is made of Knox developer fixtures; a
-- real faction or player base can never satisfy this boundary.
local function developerFactionMembersOnly(faction)
    if faction == nil or type(faction.memberIds) ~= "table" then return false end
    for _, id in ipairs(faction.memberIds) do
        if type(id) ~= "string" or string.find(id, "ks-dev-", 1, true) ~= 1 then
            return false
        end
    end
    return true
end

function KnoxPersistence.removeDeveloperFactionBase(factionId, baseId)
    local data = root()
    local faction = type(factionId) == "string" and data.factions[factionId] or nil
    local base = type(baseId) == "string" and data.bases[baseId] or nil
    if faction == nil or base == nil or base.ownerKind ~= "faction"
        or base.ownerId ~= factionId or not developerFactionMembersOnly(faction) then
        return false, "not_developer_faction_base"
    end
    local safehouseApi = rawget(_G, "SafeHouse")
    if safehouseApi ~= nil and safehouseApi.getSafehouseByOwner ~= nil
        and safehouseApi.removeSafeHouse ~= nil then
        pcall(function()
            local safehouse = safehouseApi.getSafehouseByOwner(
                "KnoxSurvivors:" .. tostring(factionId)
            )
            if safehouse ~= nil then safehouseApi.removeSafeHouse(safehouse) end
        end)
    end
    data.bases[baseId] = nil
    for _, survivorId in ipairs(faction.memberIds or {}) do
        KnoxPersistence.clearFactionResidentBed(survivorId, factionId, baseId)
    end
    if faction.homeBaseId == baseId then faction.homeBaseId = nil end
    faction.engineSafehouseId = nil
    faction.engineSafehouseOwner = nil
    return true, "removed"
end

function KnoxPersistence.purgeDeveloperQaBases()
    local removed = 0
    for baseId, base in pairs(root().bases) do
        if base ~= nil and base.ownerKind == "faction" then
            local faction = root().factions[base.ownerId]
            if developerFactionMembersOnly(faction) then
                local ok = KnoxPersistence.removeDeveloperFactionBase(
                    faction.id, baseId
                )
                if ok then removed = removed + 1 end
            end
        end
    end
    return removed
end

local function normalizedBaseTerritory(baseId, bounds, worldAgeHours)
    if type(bounds) ~= "table" then
        return nil, "invalid_base"
    end
    local minX = math.min(tonumber(bounds.minX) or 0, tonumber(bounds.maxX) or 0)
    local minY = math.min(tonumber(bounds.minY) or 0, tonumber(bounds.maxY) or 0)
    local maxX = math.max(tonumber(bounds.minX) or 0, tonumber(bounds.maxX) or 0)
    local maxY = math.max(tonumber(bounds.minY) or 0, tonumber(bounds.maxY) or 0)
    if maxX - minX < 2 or maxY - minY < 2 then
        return nil, "area_too_small"
    end
    for otherId, other in pairs(root().bases) do
        local territory = other ~= nil and (other.territory or other.home) or nil
        local otherMaxX = territory ~= nil and (territory.maxX
            or (territory.minX + territory.width - 1)) or nil
        local otherMaxY = territory ~= nil and (territory.maxY
            or (territory.minY + territory.height - 1)) or nil
        if otherId ~= baseId and territory ~= nil
            and maxX >= territory.minX and minX <= otherMaxX
            and maxY >= territory.minY and minY <= otherMaxY then
            return nil, "overlaps_existing_base"
        end
    end
    return {
        minX = minX,
        minY = minY,
        maxX = maxX,
        maxY = maxY,
        allFloors = true,
        changedAtHours = tonumber(worldAgeHours) or 0,
    }, "valid"
end

function KnoxPersistence.canSetBaseTerritory(baseId, bounds, worldAgeHours)
    return normalizedBaseTerritory(baseId, bounds, worldAgeHours)
end

function KnoxPersistence.createBase(ownerKind, ownerId, home, worldAgeHours, territoryBounds, allowMultiple)
    if (ownerKind ~= "player" and ownerKind ~= "faction")
        or type(ownerId) ~= "string" or ownerId == "" then
        return nil, "invalid_owner"
    end
    local area = copyWorldArea(home)
    if area == nil or area.minX == nil or area.minY == nil
        or area.width == nil or area.height == nil then
        return nil, "invalid_home"
    end
    -- Single-home owners keep the legacy gate; outposts pass allowMultiple.
    -- Territory overlap against every existing base is still enforced below.
    if allowMultiple ~= true then
        local existing = KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
        if existing ~= nil then
            return existing, "existing"
        end
    end
    local territory = nil
    if territoryBounds ~= nil then
        local result
        territory, result = normalizedBaseTerritory(nil, territoryBounds, worldAgeHours)
        if territory == nil then
            return nil, result
        end
    else
        territory = {
            minX = area.minX,
            minY = area.minY,
            maxX = area.minX + area.width - 1,
            maxY = area.minY + area.height - 1,
            allFloors = true,
        }
    end
    local data = root()
    local id = "base-" .. tostring(data.nextBaseId)
    data.nextBaseId = data.nextBaseId + 1
    local base = {
        id = id,
        ownerKind = ownerKind,
        ownerId = ownerId,
        name = ownerKind == "player" and "Home Base" or "Survivor Camp",
        createdAtHours = tonumber(worldAgeHours) or 0,
        home = area,
        territory = territory,
        zones = {},
        nextZoneId = 1,
        storage = {},
        tasks = {},
        nextTaskId = 1,
        settings = {
            automaticJobs = true,
            allowWorkOutsideHome = true,
        },
    }
    data.bases[id] = base
    return base, "created"
end

function KnoxPersistence.updateBaseTerritory(baseId, bounds, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(bounds) ~= "table" then
        return nil, "invalid_base"
    end
    local territory, result = normalizedBaseTerritory(baseId, bounds, worldAgeHours)
    if territory == nil then return nil, result end
    backupOnce(base, "preTerritoryBackup", { territory = base.territory })
    base.territory = territory
    return base.territory, "updated"
end

function KnoxPersistence.relocateBase(baseId, home, territoryBounds, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local area = copyWorldArea(home)
    if base == nil or area == nil or area.minX == nil or area.minY == nil
        or area.width == nil or area.height == nil then
        return nil, "invalid_home"
    end
    local territory, result = normalizedBaseTerritory(baseId, territoryBounds, worldAgeHours)
    if territory == nil then return nil, result end
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.state == "claimed" then
            return nil, "task_in_progress"
        end
    end
    -- Keep the same base identity so resident/faction ownership remains valid.
    -- Location-bound policies and queued work belong to the old property and are
    -- discarded; the actual world containers, items, and structures are untouched.
    backupOnce(base, "preRelocateBackup", {
        home = base.home, territory = base.territory, zones = base.zones,
        storage = base.storage, tasks = base.tasks, toolCupboardKey = base.toolCupboardKey,
    })
    base.home = area
    base.territory = territory
    base.zones = {}
    base.storage = {}
    base.toolCupboardKey = nil
    base.tasks = {}
    base.relocatedAtHours = tonumber(worldAgeHours) or 0
    return base, "relocated"
end

-- Base territory (border) is the only area allowed to overlap anything.
-- Production work areas are exclusive on the same floor so one tile cannot be
-- both farming and woodcutting. Overlay duties (guard/patrol and
-- similar) remain shareable by design.
local WORK_OVERLAY_TYPES = {
    guard = true, patrol = true,
    general = true,
}

local function workZonesOverlap(aMinX, aMinY, aMaxX, aMaxY, aZ, zone)
    if zone == nil or zone.x1 == nil or (tonumber(zone.z) or 0) ~= (tonumber(aZ) or 0) then
        return false
    end
    local bMinX = math.min(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local bMaxX = math.max(tonumber(zone.x1) or 0, tonumber(zone.x2) or 0)
    local bMinY = math.min(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    local bMaxY = math.max(tonumber(zone.y1) or 0, tonumber(zone.y2) or 0)
    return aMinX <= bMaxX and bMinX <= aMaxX and aMinY <= bMaxY and bMinY <= aMaxY
end

function KnoxPersistence.addBaseZone(baseId, zoneType, bounds, label)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(zoneType) ~= "string" or type(bounds) ~= "table" then
        return nil, "invalid_zone"
    end
    local minX = math.min(tonumber(bounds.x1) or 0, tonumber(bounds.x2) or 0)
    local maxX = math.max(tonumber(bounds.x1) or 0, tonumber(bounds.x2) or 0)
    local minY = math.min(tonumber(bounds.y1) or 0, tonumber(bounds.y2) or 0)
    local maxY = math.max(tonumber(bounds.y1) or 0, tonumber(bounds.y2) or 0)
    local z = tonumber(bounds.z) or 0
    -- Exclusive work areas cannot share tiles with another exclusive work
    -- area. Territory overlap is always allowed; overlay duties are exempt.
    if WORK_OVERLAY_TYPES[zoneType] ~= true then
        for _, existing in pairs(base.zones or {}) do
            if existing ~= nil and existing.enabled ~= false
                and WORK_OVERLAY_TYPES[existing.type] ~= true
                and workZonesOverlap(minX, minY, maxX, maxY, z, existing) then
                return nil, "overlaps_existing_work_area"
            end
        end
    end
    local id = base.id .. "-zone-" .. tostring(base.nextZoneId or 1)
    base.nextZoneId = (base.nextZoneId or 1) + 1
    local zone = {
        id = id,
        type = zoneType,
        label = tostring(label or zoneType),
        x1 = minX,
        y1 = minY,
        x2 = maxX,
        y2 = maxY,
        z = tonumber(bounds.z) or 0,
        enabled = true,
        priority = tonumber(bounds.priority) or 50,
    }
    base.zones[id] = zone
    return zone, "created"
end

function KnoxPersistence.removeBaseZone(baseId, zoneId)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.zones[zoneId] == nil then
        return false, "unknown_zone"
    end
    -- Finite native work must reach a safe boundary before its area is deleted.
    -- Guard/patrol duties are indefinite; removing their area explicitly releases them.
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.target ~= nil
            and (task.target.autoZoneId == zoneId or task.target.zoneId == zoneId)
            and task.state == "claimed" and task.type ~= "guard" and task.type ~= "patrol" then
            return false, "zone_has_active_task"
        end
    end
    for taskId, task in pairs(base.tasks or {}) do
        if task ~= nil and task.target ~= nil
            and (task.target.autoZoneId == zoneId or task.target.zoneId == zoneId) then
            -- Loaded controllers may still hold this exact task table.
            backupOnce(task, "preRemoveBackup", {
                state = task.state, claimedBy = task.claimedBy, reason = task.reason,
            })
            task.state, task.claimedBy, task.reason = "cancelled", nil, "work_area_removed"
            base.tasks[taskId] = nil
        end
    end
    backupOnce(base, "preZoneRemoveBackup", { zones = base.zones })
    base.zones[zoneId] = nil
    return true, "removed"
end

function KnoxPersistence.setBaseStoragePolicy(baseId, reference, category, depot)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(reference) ~= "table" or type(reference.key) ~= "string" then
        return nil, "invalid_container"
    end
    -- Main Supplies (depot/supplies) is retired: typed storages are canonical.
    -- Legacy saves may still contain depot records, but no new ones are created.
    if category == "depot" or depot == true then
        return nil, "main_supplies_retired"
    end
    local validCategories = {
        food=true, water=true, medical=true, weapons=true,
        ammunition=true, tools=true, logs=true, general=true,
        building=true, farming=true, clothing=true, junk=true,
    }
    if not validCategories[category] then return nil, "unknown_storage_category" end
    local policy = {
        key = reference.key,
        x = tonumber(reference.x),
        y = tonumber(reference.y),
        z = tonumber(reference.z) or 0,
        objectIndex = tonumber(reference.objectIndex),
        containerIndex = tonumber(reference.containerIndex) or 0,
        containerType = tostring(reference.containerType or "container"),
        category = category,
        depot = false,
        storageRole = category,
        toolCupboard = false,
        priority = KnoxPersistence.validStoragePriority((base.storage or {})[reference.key] ~= nil
            and (base.storage or {})[reference.key].priority or nil) or "normal",
    }
    local retained = {}
    for key, existing in pairs(base.storage or {}) do
        if key ~= policy.key then
            retained[key] = existing
        else
            backupOnce(existing, "preStorageBackup", {
                category = existing.category, storageRole = existing.storageRole,
            })
        end
    end
    retained[policy.key] = policy
    -- Clear a legacy main marker when its container is converted to typed.
    if base.toolCupboardKey == policy.key then
        base.toolCupboardKey = nil
    end
    base.storage = retained
    return policy, "saved"
end

-- Filter policies extend the same real-container record used by legacy
-- single-role assignments.  Keeping storageRole/category as a stable primary
-- category lets older readers and old-save migrations continue to function.
function KnoxPersistence.setBaseStorageFilters(baseId, reference, filters)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(reference) ~= "table" or type(reference.key) ~= "string"
        or type(filters) ~= "table" then
        return nil, "invalid_container"
    end
    local validCategories = {
        food=true, water=true, medical=true, weapons=true,
        ammunition=true, tools=true, logs=true, general=true,
        building=true, farming=true, clothing=true, junk=true,
    }
    local normalized = {}
    for category, enabled in pairs(filters) do
        local nativeCategory = type(category) == "string"
            and string.match(category, "^display:([%w_%-]+)$") or nil
        if enabled == true and (validCategories[category] == true
            or (nativeCategory ~= nil and #nativeCategory <= 64)) then
            normalized[category] = true
        end
    end
    local hasNormalizedFilter = false
    for _ in pairs(normalized) do
        hasNormalizedFilter = true
        break
    end
    if not hasNormalizedFilter then return nil, "empty_storage_filters" end
    if normalized.general then
        normalized = { general = true }
    end
    local order = { "food", "water", "medical", "weapons", "ammunition",
        "tools", "logs", "building", "farming", "clothing", "junk", "general" }
    local primary = nil
    for _, category in ipairs(order) do
        if normalized[category] then primary = category; break end
    end
    if primary == nil then
        local nativeCategories = {}
        for category in pairs(normalized) do nativeCategories[#nativeCategories + 1] = category end
        table.sort(nativeCategories)
        primary = nativeCategories[1]
    end
    local existing = (base.storage or {})[reference.key]
    local policy = {
        key = reference.key,
        x = tonumber(reference.x), y = tonumber(reference.y), z = tonumber(reference.z) or 0,
        objectIndex = tonumber(reference.objectIndex),
        containerIndex = tonumber(reference.containerIndex) or 0,
        containerType = tostring(reference.containerType or "container"),
        category = primary, storageRole = primary, storageFilters = normalized,
        storageFilterVersion = 1, depot = false, toolCupboard = false,
        priority = KnoxPersistence.validStoragePriority(existing ~= nil and existing.priority)
            or "normal",
    }
    local retained = {}
    for key, value in pairs(base.storage or {}) do
        if key ~= policy.key then retained[key] = value end
    end
    retained[policy.key] = policy
    if base.toolCupboardKey == policy.key then base.toolCupboardKey = nil end
    base.storage = retained
    return policy, "saved"
end

function KnoxPersistence.removeBaseStoragePolicy(baseId, key)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.storage[key] == nil then
        return false, "storage_missing"
    end
    base.storage[key] = nil
    if base.toolCupboardKey == key then
        base.toolCupboardKey = nil
    end
    return true, "removed"
end

local VALID_STORAGE_PRIORITIES = {
    low = true, normal = true, preferred = true, critical = true,
}

-- RimWorld-style storage priority. Nil/unknown normalizes to nil (the
-- caller falls back to "normal"); only the four levels persist.
function KnoxPersistence.validStoragePriority(value)
    if type(value) ~= "string" then return nil end
    if VALID_STORAGE_PRIORITIES[value] == true then return value end
    return nil
end

-- Player-facing priority writer for one assigned container. Same-save
-- safe: a new optional policy field, defaulting to normal everywhere.
function KnoxPersistence.setBaseStoragePriority(baseId, key, priority)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(key) ~= "string" then
        return false, "storage_missing"
    end
    local policy = base.storage ~= nil and base.storage[key] or nil
    if type(policy) ~= "table" then return false, "storage_missing" end
    local normalized = KnoxPersistence.validStoragePriority(priority)
    if normalized == nil then return false, "unknown_priority" end
    policy.priority = normalized
    return true, "saved"
end

function KnoxPersistence.setBaseDoorLock(baseId, x, y, z, locked)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then return false end
    base.lockedDoors = base.lockedDoors or {}
    local key = tostring(tonumber(x) or 0) .. ":" .. tostring(tonumber(y) or 0)
        .. ":" .. tostring(tonumber(z) or 0)
    if locked then
        base.lockedDoors[key] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    else
        base.lockedDoors[key] = nil
    end
    return true
end

function KnoxPersistence.applyBaseDoorLocks()
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return end
    for _, base in pairs(KnoxPersistence.getBases()) do
        if base ~= nil and base.lockedDoors ~= nil then
            for _, coords in pairs(base.lockedDoors) do
                if type(coords) == "table" then
                    local square = cell:getGridSquare(
                        tonumber(coords.x) or 0, tonumber(coords.y) or 0, tonumber(coords.z) or 0)
                    if square ~= nil and square.getObjects ~= nil then
                        local objects = square:getObjects()
                        for index = 0, objects:size() - 1 do
                            local object = objects:get(index)
                            local isDoor = false
                            if instanceof ~= nil then
                                local ok, result = pcall(function()
                                    return instanceof(object, "IsoDoor")
                                end)
                                isDoor = ok and result == true
                            end
                            if isDoor then
                                pcall(function()
                                    if object.setLockedByKey ~= nil then object:setLockedByKey(true) end
                                    if object.setLocked ~= nil then object:setLocked(true) end
                                    if object.setKeyId ~= nil then object:setKeyId(tostring(base.id)) end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function baseTaskTargetSignature(target)
    if type(target) ~= "table" then
        return nil
    end
    if type(target.key) == "string" and target.key ~= "" then
        return "key=" .. target.key
    end
    if type(target.id) == "string" and target.id ~= "" then
        return "id=" .. target.id
    end
    local x = tonumber(target.x or target.x1)
    local y = tonumber(target.y or target.y1)
    if x == nil or y == nil then
        return nil
    end
    return table.concat({
        "x=" .. tostring(x),
        "y=" .. tostring(y),
        "z=" .. tostring(tonumber(target.z) or 0),
        "x2=" .. tostring(tonumber(target.x2) or x),
        "y2=" .. tostring(tonumber(target.y2) or y),
        "object=" .. tostring(tonumber(target.objectIndex) or -1),
        "container=" .. tostring(tonumber(target.containerIndex) or -1),
    }, ";")
end

function KnoxPersistence.queueBaseTask(baseId, taskType, target, requirements, priority)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(taskType) ~= "string" or type(target) ~= "table" then
        return nil, "invalid_task"
    end
    -- The task board is the normal caller, but persistence is also used by
    -- migration paths and focused tools. Normalize here too so a direct caller
    -- cannot create a legacy/non-executable record after the board boundary.
    taskType = canonicalTaskType(taskType)
    local targetSignature = baseTaskTargetSignature(target)
    if targetSignature == nil then
        return nil, "target_needs_stable_identity"
    end
    local signature = tostring(taskType) .. ":" .. targetSignature
    for _, existing in pairs(base.tasks) do
        if existing.signature == signature
            and (existing.state == "queued" or existing.state == "claimed") then
            return existing, "existing"
        end
    end
    local id = base.id .. "-task-" .. tostring(base.nextTaskId or 1)
    base.nextTaskId = (base.nextTaskId or 1) + 1
    local task = {
        id = id,
        signature = signature,
        type = taskType,
        state = "queued",
        priority = math.max(0, math.min(100, tonumber(priority) or 50)),
        target = copySerializable(target, 0),
        requirements = copySerializable(requirements or {}, 0),
        attempts = 0,
    }
    base.tasks[id] = task
    return task, "queued"
end

-- A live worker may replace a streamed/stale barricade opening with another
-- valid opening. Keep the task's durable identity synchronized with that new
-- target and reject an opening already queued or claimed by another worker.
function KnoxPersistence.retargetClaimedBaseTask(
    baseId,
    taskId,
    survivorId,
    target
)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    local targetSignature = baseTaskTargetSignature(target)
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId
        or targetSignature == nil then
        return nil, "not_claimed_by_survivor"
    end
    for otherId, other in pairs(base.tasks or {}) do
        if otherId ~= taskId and other ~= nil and other.type == task.type
            and (other.state == "queued" or other.state == "claimed")
            and baseTaskTargetSignature(other.target) == targetSignature then
            return nil, "target_already_owned"
        end
    end
    task.target = copySerializable(target, 0)
    task.signature = tostring(task.type) .. ":" .. targetSignature
    task.retargetedAtHours = getGameTime ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
    return task, "retargeted"
end

function KnoxPersistence.claimBaseTask(baseId, taskId, survivorId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    if survivor == nil or survivor.record == nil then
        return nil, "unknown_survivor"
    end
    if survivor.alive == false then
        return nil, "survivor_dead"
    end
    if survivor.duty == nil or survivor.duty.mode ~= "base"
        or survivor.duty.baseId ~= baseId or survivor.duty.eventId ~= nil then
        return nil, "not_base_resident"
    end
    -- A resident owns one native task at a time.  This guard protects the
    -- persistent board from duplicate claims when controller refreshes or UI
    -- retries arrive in the same tick.
    for _, existing in pairs(base ~= nil and base.tasks or {}) do
        if existing ~= nil and existing.state == "claimed"
            and existing.claimedBy == survivorId then
            return nil, "already_claimed_task"
        end
    end
    if task == nil or task.state ~= "queued" then
        return nil, "unavailable"
    end
    task.state = "claimed"
    task.claimedBy = survivorId
    task.claimedAtHours = tonumber(worldAgeHours) or 0
    task.lastClaimedAtHours = task.claimedAtHours
    -- A fresh loaded-world claim gets a new off-screen lease. Without this
    -- reset, a task released after a prior unload could be reclaimed and
    -- immediately released again before its resident had a chance to work.
    task.offscreenWaitHours = 0
    task.offscreenLastHours = task.claimedAtHours
    task.attempts = (tonumber(task.attempts) or 0) + 1
    -- Persist the resident's current work type as a lightweight rotation hint.
    -- It is not a second order: the task board still owns eligibility and the
    -- durable base duty still owns the resident's preference.
    if survivor.duty ~= nil then
        survivor.duty.lastJobType = canonicalTaskType(task.type)
        survivor.duty.lastJobAtHours = task.claimedAtHours
    end
    return task, "claimed"
end

function KnoxPersistence.finishBaseTask(
    baseId,
    taskId,
    survivorId,
    succeeded,
    reason,
    worldAgeHours
)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId then
        return nil, "not_claimed_by_survivor"
    end
    task.state = succeeded and "complete" or "blocked"
    task.completedAtHours = tonumber(worldAgeHours) or 0
    task.result = tostring(reason or (succeeded and "complete" or "blocked"))
    -- Completion is the ownership boundary. Keep the last claimant only as a
    -- fairness hint; never leave a finished task attached to a living resident.
    task.lastClaimedBy = task.claimedBy
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.manual = nil
    task.auto = nil
    if succeeded == true then task.manualOrder = nil end
    -- A completed routine should not be reclaimed by the same resident on the
    -- very next thought.  The short cooldown lets other residents claim work
    -- and gives the worker a natural idle/rest interval.  Depot sorting stays
    -- quicker because it is a queue-clearing action; failures use the longer
    -- bounded backoff below.
    local repeatDelay = 0.50
    if succeeded then
        task.failureStreak = 0
        if task.type == "sort_depot" then repeatDelay = 0.10 end
    else
        -- Failed world actions should cool down instead of reopening every
        -- controller tick.  Keep this bounded so a real problem can recover
        -- after supplies/geometry change without creating a retry storm.
        task.failureStreak = math.min(6, (tonumber(task.failureStreak) or 0) + 1)
        repeatDelay = math.min(8, 0.25 * (2 ^ (task.failureStreak - 1)))
        task.lastBlockedAtHours = task.completedAtHours
    end
    task.retryAtHours = task.completedAtHours + repeatDelay
    return task, "finished"
end

-- A physical task cannot execute while its world square is unloaded.  Allow
-- the unloaded-life boundary to release an automatic claim after a bounded
-- wait, but keep explicit player assignments owned until the resident returns
-- to a loaded square.  This is a claim handoff, not a simulated completion.
function KnoxPersistence.releaseBaseTaskClaim(
    baseId,
    taskId,
    survivorId,
    reason,
    worldAgeHours
)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId then
        return nil, "not_claimed_by_survivor"
    end
    if task.manual == true then
        return nil, "manual_assignment_preserved"
    end
    local now = tonumber(worldAgeHours) or 0
    task.state = "blocked"
    task.lastClaimedBy = task.claimedBy
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.completedAtHours = now
    task.result = tostring(reason or "unloaded_execution_wait")
    task.failureStreak = math.min(6, (tonumber(task.failureStreak) or 0) + 1)
    task.retryAtHours = now + math.min(8, 0.25 * (2 ^ (task.failureStreak - 1)))
    task.offscreenWaitHours = 0
    return task, "released"
end

-- A player may stop queued or finished automatic work, but never a task that a
-- resident has already claimed.  Interrupting a native timed action here would
-- leave the action controller and the persistent board disagreeing about who
-- owns the job.  A cancelled record remains as the stable target signature so
-- the automatic planner does not immediately recreate the same unwanted task.
function KnoxPersistence.cancelBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state == "claimed" then
        return nil, "task_in_progress"
    end
    if task.state == "cancelled" then
        return task, "already_cancelled"
    end
    task.state = "cancelled"
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.completedAtHours = tonumber(worldAgeHours) or 0
    task.cancelledAtHours = task.completedAtHours
    task.result = "cancelled_by_player"
    task.retryAtHours = nil
    return task, "cancelled"
end

function KnoxPersistence.resumeBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state ~= "cancelled" then
        return nil, "not_cancelled"
    end
    task.state = "queued"
    task.cancelledAtHours = nil
    task.completedAtHours = nil
    task.result = nil
    task.retryAtHours = nil
    task.resumedAtHours = tonumber(worldAgeHours) or 0
    return task, "resumed"
end

-- Reopen a completed or blocked recurring task without losing its history.
-- One task record represents one persistent work-zone assignment; this avoids
-- creating an unbounded queue every time a guard finishes a patrol.
function KnoxPersistence.requeueBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state ~= "complete" and task.state ~= "blocked" then
        return nil, "not_finished"
    end
    local now = tonumber(worldAgeHours) or 0
    local retryAt = tonumber(task.retryAtHours) or 0
    if now < retryAt then
        return nil, "retry_not_ready"
    end
    task.runs = (tonumber(task.runs) or 0) + 1
    task.lastResult = task.result
    task.lastCompletedAtHours = task.completedAtHours
    task.state = "queued"
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.completedAtHours = nil
    task.result = nil
    task.retryAtHours = nil
    task.requeuedAtHours = now
    return task, "requeued"
end

function KnoxPersistence.recoverInterruptedBaseTasks()
    local recovered = 0
    for _, base in pairs(root().bases) do
        for _, task in pairs(base.tasks or {}) do
            if task.state == "claimed" then
                task.state = "queued"
                task.lastClaimedBy = task.claimedBy
                task.claimedBy = nil
                task.claimedAtHours = nil
                task.interruptedReason = "save_reloaded"
                recovered = recovered + 1
            end
        end
    end
    return recovered
end

function KnoxPersistence.getSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and survivor ~= nil and survivor.record ~= nil then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.captureActiveTestSurvivor()
    return KnoxPersistence.captureActiveSurvivor(TEST_SURVIVOR_ID)
end

function KnoxPersistence.captureActiveSurvivor(id)
    if type(id) ~= "string" or id == "" then return false, "invalid_id" end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return false, "bridge_unavailable"
    end
    -- Never serialize a corpse over the last alive record.
    local bodyOk, character = pcall(function() return bridge:getNpcCharacter(id) end)
    if not bodyOk or character == nil then return false, "character_unavailable" end
    local healthOk, dead = pcall(function() return character:isDead() end)
    if not healthOk or type(dead) ~= "boolean" then return false, "character_state_unavailable" end
    if dead then return false, "character_dead" end
    -- First capture admits a new live identity only after serialization succeeds.
    -- Existing death/departure records are authoritative, including developer
    -- survivors; a stale native body must never resurrect a persisted survivor.
    local existing = root().survivors[id]
    if existing ~= nil and not KnoxPersistence.isSurvivorPresent(id) then
        return false, "not_present"
    end
    local success, encoded = pcall(function()
        return bridge:captureNpcRecord(id)
    end)
    if not success or type(encoded) ~= "string" or encoded == ""
        or string.find(encoded, "CAPTURE_FAILED", 1, true) == 1 then
        return false, encoded
    end
    local saved = KnoxPersistence.setRecord(id, encoded)
    if not saved then return false, "record_store_failed" end
    local postFailures = {}
    if saved and bridge.getNpcRecordInventorySummary ~= nil then
        local summaryOk, summary = pcall(bridge.getNpcRecordInventorySummary, bridge, encoded)
        if summaryOk and type(summary) == "string" then
            local survivor = ensureSurvivorState(id)
            survivor.inventorySummary = summary
            survivor.inventorySummaryAtHours = getGameTime() ~= nil
                and getGameTime():getWorldAgeHours() or 0
        elseif not summaryOk then
            postFailures[#postFailures + 1] = "inventory_summary=" .. tostring(summary)
        end
    end
    local capabilities = rawget(_G, "KnoxSurvivorCapabilities")
    if saved and capabilities ~= nil and capabilities.capture ~= nil then
        local capabilityOk, capabilityFailure = pcall(capabilities.capture, id, character)
        if not capabilityOk then
            postFailures[#postFailures + 1] = "capabilities=" .. tostring(capabilityFailure)
        end
    end
    if saved then
        local needs = rawget(_G, "KnoxSurvivorNeeds")
        if character ~= nil and needs ~= nil and needs.snapshot ~= nil then
            local snapshotOk, snapshot = pcall(needs.snapshot, character)
            if snapshotOk and type(snapshot) == "table" then
                local survivor = ensureSurvivorState(id)
                survivor.lastKnownNeeds = copyFlat(snapshot)
                survivor.lastKnownNeedsAtHours = getGameTime() ~= nil
                    and getGameTime():getWorldAgeHours()
                    or 0
                local unloaded = rawget(_G, "KnoxUnloadedSurvival")
                if unloaded ~= nil and unloaded.captureLoaded ~= nil then
                    local unloadedOk, unloadedFailure = pcall(
                        unloaded.captureLoaded,
                        id,
                        snapshot,
                        survivor.lastKnownNeedsAtHours
                    )
                    if not unloadedOk or unloadedFailure ~= true then
                        postFailures[#postFailures + 1] = "unloaded="
                            .. tostring(unloadedFailure)
                    end
                end
            elseif not snapshotOk then
                postFailures[#postFailures + 1] = "needs=" .. tostring(snapshot)
            end
        end
    end
    if #postFailures > 0 then
        return false, "record_saved post_capture_failed=" .. table.concat(postFailures, ",")
    end
    return saved, encoded
end

function KnoxPersistence.captureAllActiveSurvivors()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return false, "bridge_unavailable"
    end
    local idsOk, rawIds = pcall(function() return bridge:getActiveNpcIds() end)
    if not idsOk then
        return false, "active_ids_failed=" .. tostring(rawIds)
    end
    if rawIds == nil or tostring(rawIds) == "" then
        return true, "none_active"
    end
    local activeIds = tostring(rawIds)
    local captured = 0
    local failures = {}
    for id in string.gmatch(activeIds, "[^,]+") do
        id = string.match(id, "^%s*(.-)%s*$")
        local callOk, saved, evidence = pcall(
            KnoxPersistence.captureActiveSurvivor,
            id
        )
        if not callOk then
            evidence = "exception=" .. tostring(saved)
            saved = false
        end
        if not saved then
            -- Do not let one malformed or unloading shell prevent the remaining
            -- survivors from being written.  Save captures are independent; keep
            -- the successful records and report all failures to the caller.
            failures[#failures + 1] = "id=" .. tostring(id) .. " " .. tostring(evidence)
        else
            captured = captured + 1
        end
    end
    if #failures > 0 then
        return false, "captured=" .. tostring(captured)
            .. " failed=" .. table.concat(failures, " | ")
    end
    return true, "captured=" .. tostring(captured)
end

function KnoxPersistence.isDevGateComplete(name)
    local data = root()
    return data.devTests ~= nil
        and data.devTests.completed ~= nil
        and data.devTests.completed[name] == true
end

function KnoxPersistence.markDevGateComplete(name)
    local data = root()
    data.devTests = data.devTests or {}
    data.devTests.completed = data.devTests.completed or {}
    data.devTests.completed[name] = true
end

local function onSave()
    local saved, evidence = KnoxPersistence.captureAllActiveSurvivors()
    if not saved then
        print("[KnoxSurvivors][Persistence] save-capture-failed=" .. tostring(evidence))
    end
end

local function onGameStart()
    -- The module can be loaded before Project Zomboid finishes attaching the
    -- selected save's ModData. Force one full migration/repair at the actual
    -- world boundary, then let normal gameplay use the cached O(1) root path.
    invalidateNormalizedRoot()
    root()
    local normalized = KnoxPersistence.normalizeRelationshipDomains()
    if normalized > 0 then
        print("[KnoxSurvivors][Persistence] normalized-social-domains="
            .. tostring(normalized))
    end
    local recovered = KnoxPersistence.recoverInterruptedBaseTasks()
    if recovered > 0 then
        print("[KnoxSurvivors][Persistence] requeued-interrupted-base-tasks="
            .. tostring(recovered))
    end
end

Events.OnSave.Add(onSave)
Events.OnGameStart.Add(onGameStart)
