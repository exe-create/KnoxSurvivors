local Settings = rawget(_G, "KnoxSettings") or {}
_G.KnoxSettings = Settings

local DEFAULTS = {
    Enabled = true,
    DisableSurvivorCaps = false,
    WorldPopulation = 48,
    InitialGroupChance = 65,
    InitialGroupMaxSize = 4,
    InitialGroupCount = 3,
    MaxActiveSurvivors = 16,
    ActivationsPerUpdate = 2,
    PopulationRefillDays = 5,
    MinimumSpawnDistance = 40,
    SurvivorEncounterDistance = 280,
    CompanionLimit = 4,
    FollowerFormation = 1,
    FollowerSpacing = 1,
    ToolCupboardCapacity = 500,
    EnableExperimentalNpcDriving = false,
    NpcDrivingSpeed = 20,
    SurvivorAimingAssist = 1,
    SpawnWithSpouse = false,
    ContinueSurvivorsAfterPlayerDeath = true,
    AllowNPCFactions = true,
    EnableKnoxEvents = false,
    NPCFactionMinimumMembers = 4,
    NPCFactionMaxMembers = 8,
    AllowHostileEncounters = true,
    AllowAutonomousRetreat = true,
    AllowFactionRaids = false,
    FactionRaidMinimumDays = 14,
    FactionRaidIntervalDays = 7,
    ShowCompanionHUD = true,
    ShowActivityFeed = true,
    ShowSurvivorSpeech = true,
    OrderGestures = true,
    ShowRadialOrders = true,
    ShowLegacyContextCommands = false,
    AllowSurvivorDoorWindowOpening = true,
    CautiousTravel = true,
    BaseReading = true,
    BaseCooking = true,
    ZombieEngagementDistance = 4,
    ShowSurvivorNameplates = true,
    SurvivorNameplateDistance = 24,
    AllowSurvivorPlayerCombat = true,
    UseReputation = true,
    EnableDeveloperTools = false,
    IgnoreJobResourceRequirements = false,
    DeveloperScenario = 1,
    DeveloperSpawnDistance = 10,
    AllowDestructiveDeveloperTests = false,
    ShowDeveloperDiagnostics = false,
    AutoGenerateBaseWorkAreas = true,
    AllowSurvivorsTreatPlayer = true,
}

local SCENARIOS = {
    [1] = "none",
    [2] = "single",
    [3] = "companion",
    [4] = "group",
    [5] = "faction",
    [6] = "faction_base",
}

local function values()
    local sandbox = rawget(_G, "SandboxVars")
    local configured = type(sandbox) == "table" and sandbox.KnoxSurvivors or nil
    return type(configured) == "table" and configured or DEFAULTS
end

local function value(name)
    local configured = values()[name]
    if configured ~= nil then
        return configured
    end
    return DEFAULTS[name]
end

local function integer(name, minimum, maximum)
    local number = tonumber(value(name))
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        number = DEFAULTS[name]
    end
    number = math.floor(number)
    return math.max(minimum, math.min(maximum, number))
end

function Settings.baseCookingEnabled()
    return value("BaseCooking") ~= false
end

function Settings.baseReadingEnabled()
    return value("BaseReading") ~= false
end

function Settings.cautiousTravel()
    return value("CautiousTravel") ~= false
end

function Settings.zombieEngagementDistance()
    return integer("ZombieEngagementDistance", 2, 16)
end

function Settings.enabled()
    return value("Enabled") ~= false
end

function Settings.worldPopulation()
    return integer("WorldPopulation", 0, 256)
end

function Settings.initialGroupChance()
    return integer("InitialGroupChance", 0, 100)
end

function Settings.initialGroupMaxSize()
    return integer("InitialGroupMaxSize", 2, 6)
end

function Settings.initialGroupCount()
    return integer("InitialGroupCount", 1, 4)
end

function Settings.capsDisabled()
    return value("DisableSurvivorCaps") == true
end

function Settings.maxActiveSurvivors()
    if Settings.capsDisabled() then return math.huge end
    return integer("MaxActiveSurvivors", 1, 48)
end

function Settings.activationsPerUpdate()
    return integer("ActivationsPerUpdate", 1, 4)
end

-- Rate limiting is not a lifetime population cap. Even without configured caps,
-- streaming a busy settlement must not construct every body on a single update.
function Settings.activationBudget(activeCount)
    return math.min(Settings.activationsPerUpdate(),
        math.max(0, Settings.maxActiveSurvivors() - math.max(0, activeCount or 0)))
end

function Settings.populationRefillDays()
    return integer("PopulationRefillDays", 0, 30)
end

function Settings.minimumSpawnDistance()
    return integer("MinimumSpawnDistance", 25, 150)
end

function Settings.survivorEncounterDistance()
    -- Keep a usable hidden-spawn band even when independently valid settings
    -- overlap. Never weaken the player's minimum appearance distance.
    return math.max(integer("SurvivorEncounterDistance", 120, 500),
        Settings.minimumSpawnDistance() + 10)
end

function Settings.companionLimit()
    if Settings.capsDisabled() then return math.huge end
    return integer("CompanionLimit", 1, 12)
end

function Settings.followerFormation()
    return integer("FollowerFormation", 1, 2) == 2 and "single_file" or "paired"
end

function Settings.followerSpacing()
    return integer("FollowerSpacing", 1, 3)
end

function Settings.toolCupboardCapacity()
    return integer("ToolCupboardCapacity", 100, 2000)
end

function Settings.enableExperimentalNpcDriving()
    return Settings.enabled() and value("EnableExperimentalNpcDriving") == true
end

function Settings.npcDrivingSpeed()
    return integer("NpcDrivingSpeed", 5, 30)
end

function Settings.allowSurvivorDoorWindowOpening()
    return value("AllowSurvivorDoorWindowOpening") ~= false
end

function Settings.survivorAimingAssist()
    return integer("SurvivorAimingAssist", 1, 3)
end

function Settings.spawnWithSpouse()
    return Settings.enabled() and value("SpawnWithSpouse") == true
end

function Settings.allowNPCFactions()
    return value("AllowNPCFactions") ~= false
end

function Settings.autoGenerateBaseWorkAreas()
    return value("AutoGenerateBaseWorkAreas") ~= false
end

function Settings.allowSurvivorsTreatPlayer()
    return Settings.enabled() and value("AllowSurvivorsTreatPlayer") ~= false
end

function Settings.enableKnoxEvents()
    return Settings.enabled() and value("EnableKnoxEvents") == true
end

function Settings.npcFactionMinimumMembers()
    return integer("NPCFactionMinimumMembers", 3, 8)
end

function Settings.npcFactionMaxMembers()
    return math.max(Settings.npcFactionMinimumMembers(),
        integer("NPCFactionMaxMembers", 3, 24))
end

function Settings.allowHostileEncounters()
    return value("AllowHostileEncounters") ~= false
end

function Settings.allowAutonomousRetreat()
    return value("AllowAutonomousRetreat") ~= false
end

function Settings.allowFactionRaids()
    return Settings.enabled() and Settings.allowNPCFactions()
        and Settings.allowHostileEncounters() and value("AllowFactionRaids") ~= false
end

function Settings.factionRaidMinimumDays()
    return integer("FactionRaidMinimumDays", 1, 90)
end

function Settings.factionRaidIntervalDays()
    return integer("FactionRaidIntervalDays", 1, 30)
end

function Settings.showCompanionHUD()
    return Settings.enabled() and value("ShowCompanionHUD") ~= false
end

function Settings.showActivityFeed()
    return Settings.enabled() and value("ShowActivityFeed") ~= false
end

function Settings.showSurvivorSpeech()
    return Settings.enabled() and value("ShowSurvivorSpeech") ~= false
end

function Settings.showSurvivorNameplates()
    return Settings.enabled() and value("ShowSurvivorNameplates") ~= false
end

function Settings.survivorNameplateDistance()
    return integer("SurvivorNameplateDistance", 8, 40)
end

function Settings.allowSurvivorPlayerCombat()
    return Settings.enabled() and value("AllowSurvivorPlayerCombat") ~= false
end

function Settings.useReputation()
    return Settings.enabled() and value("UseReputation") ~= false
end

function Settings.orderGesturesEnabled()
    return Settings.enabled() and value("OrderGestures") ~= false
end

function Settings.showRadialOrders()
    return Settings.enabled() and value("ShowRadialOrders") ~= false
end

-- Optional right-click order menus. Off by default so the emote radial is the
-- primary command surface. Nil-safe for old saves through DEFAULTS.
function Settings.showLegacyContextCommands()
    return Settings.enabled() and value("ShowLegacyContextCommands") == true
end

function Settings.developerToolsEnabled()
    return Settings.enabled() and value("EnableDeveloperTools") == true
end

function Settings.developerJobSuppliesEnabled()
    -- Retired: use IgnoreJobResourceRequirements instead. Kept for old saves.
    return false
end

function Settings.continueSurvivorsAfterPlayerDeath()
    return Settings.enabled() and value("ContinueSurvivorsAfterPlayerDeath") ~= false
end

function Settings.ignoreJobResourceRequirements()
    return Settings.enabled() and value("IgnoreJobResourceRequirements") == true
end

function Settings.developerScenario()
    return SCENARIOS[integer("DeveloperScenario", 1, 6)] or "none"
end

function Settings.developerSpawnDistance()
    return integer("DeveloperSpawnDistance", 6, 30)
end

function Settings.allowDestructiveDeveloperTests()
    return Settings.developerToolsEnabled()
        and value("AllowDestructiveDeveloperTests") == true
end

function Settings.showDeveloperDiagnostics()
    return Settings.developerToolsEnabled()
        and value("ShowDeveloperDiagnostics") ~= false
end

return Settings
