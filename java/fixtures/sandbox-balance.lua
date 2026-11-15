-- The world should read as a county of survivors: families, loners, small
-- groups and a few factions, not armies. These assertions pin the shipped
-- defaults to that shape so a later edit cannot quietly turn the county into a
-- crowd. They drive the real KnoxSettings readers, with no SandboxVars present,
-- which is the path a fresh save takes.
local S = assert(KnoxSettings, "settings owner is loaded")

-- A county, not a horde: the target identity pool stays in the hundreds.
local population = S.worldPopulation()
assert(population >= 200 and population <= 512,
    "target county population is a county, got " .. tostring(population))

-- Most people are alone. A group is the exception, and it is small.
assert(S.initialGroupChance() <= 50,
    "fewer than half of starting survivors are grouped, got "
        .. tostring(S.initialGroupChance()))
assert(S.initialGroupMaxSize() <= 5,
    "a starting group is a family or a handful, got "
        .. tostring(S.initialGroupMaxSize()))
assert(S.initialGroupCount() <= 64,
    "starting groups stay rare, got " .. tostring(S.initialGroupCount()))
assert(S.initialFactionCount() <= 8,
    "factions are few, got " .. tostring(S.initialFactionCount()))

-- Factions are households with a name, not battalions.
assert(S.npcFactionMinimumMembers() >= 3, "a faction needs several people")
assert(S.npcFactionMaxMembers() <= 12,
    "a faction is not an army, got " .. tostring(S.npcFactionMaxMembers()))
assert(S.npcFactionMaxMembers() >= S.npcFactionMinimumMembers(),
    "the maximum is never below the minimum to form")

-- Companion following is a household, not a platoon.
assert(S.companionLimit() <= 6,
    "a player leads a handful, got " .. tostring(S.companionLimit()))

-- Loading stays bounded so a big county does not cost every frame.
assert(S.maxActiveSurvivors() <= 32,
    "loaded bodies stay bounded, got " .. tostring(S.maxActiveSurvivors()))
assert(S.activationsPerUpdate() <= 4, "loading stays spread across updates")
local previousSandbox=SandboxVars
SandboxVars={KnoxSurvivors={DisableSurvivorCaps=true,MaxActiveSurvivors=24,ActivationsPerUpdate=2}}
assert(S.capsDisabled() and S.maxActiveSurvivors()==24,
    "uncapped county retains its configured automatic loaded-body budget")
assert(S.activationBudget(24)==0 and S.activationBudget(23)==1,
    "automatic activation respects remaining body slots even when county growth is uncapped")
SandboxVars=previousSandbox

-- Realistic, immersive default world (owner direction 2026-11-09): a small
-- crew, fewer bodies loaded at once, people met where you actually go, a county
-- that thins out faster than it refills, and a slower drift into factions.
assert(S.maxActiveSurvivors() == 24, "loaded bodies default to 24, got " .. tostring(S.maxActiveSurvivors()))
assert(S.activationsPerUpdate() == 1, "one new body per update, got " .. tostring(S.activationsPerUpdate()))
assert(S.companionLimit() == 3, "a player leads three, got " .. tostring(S.companionLimit()))
assert(S.zombieEngagementDistance() == 3, "survivors avoid fights unless close, got " .. tostring(S.zombieEngagementDistance()))
assert(S.populationRefillDays() == 14, "the county refills every two weeks, got " .. tostring(S.populationRefillDays()))
assert(S.factionEntryMinimumDays() == 14, "faction arrivals wait two weeks, got " .. tostring(S.factionEntryMinimumDays()))
assert(S.factionRaidMinimumDays() == 30, "first raid waits a month, got " .. tostring(S.factionRaidMinimumDays()))

-- People are met rarely enough to matter.
assert(S.survivorEncounterDistance() <= 260,
    "encounters are not constant, got " .. tostring(S.survivorEncounterDistance()))
assert(S.survivorEncounterDistance() >= S.minimumSpawnDistance() + 10,
    "the encounter band stays beyond the minimum spawn distance")

-- Danger arrives, but not in the first week: arrivals wait, raids wait longer,
-- and checks are measured in days rather than every tick.
assert(S.factionEntryMinimumDays() >= 3, "arrivals wait for the world to settle")
assert(S.factionRaidMinimumDays() >= 14,
    "raids wait longer than arrivals, got " .. tostring(S.factionRaidMinimumDays()))
assert(S.factionRaidMinimumDays() >= S.factionEntryMinimumDays(),
    "a raid is not the first thing that reaches the player")
assert(S.factionEntryIntervalDays() >= 1 and S.factionRaidIntervalDays() >= 1,
    "check intervals are whole days")

-- The switches that decide whether the county can be dangerous at all are on,
-- and the one experimental behaviour still being rebuilt stays off.
assert(S.allowNPCFactions() == true, "factions form by default")
assert(S.allowHostileEncounters() == true, "some survivors are hostile by default")
assert(S.allowFactionRaids() == true, "raids are possible by default")
assert(S.allowAutonomousRetreat() == false,
    "the retreat being rebuilt stays off")

-- A fresh save with no sandbox table still answers with numbers and booleans.
assert(type(S.companionLimit()) == "number", "companion limit is a number")
assert(type(S.showCompanionHUD()) == "boolean", "HUD switch is a boolean")
assert(S.initialGroupChance() >= 0 and S.initialGroupChance() <= 100,
    "a percentage stays a percentage")

-- Precedence (owner contract): the shipped defaults are fallbacks only. A stored
-- sandbox table from an existing save, or a scenario preset, wins untouched.
local savedVars = SandboxVars
SandboxVars = { KnoxSurvivors = { MaxActiveSurvivors = 32, CompanionLimit = 2 } }
assert(S.maxActiveSurvivors() == 32,
    "an existing save keeps its stored loaded-body cap")
assert(S.companionLimit() == 2, "an existing save keeps its stored companion limit")
assert(SandboxVars.KnoxSurvivors.MaxActiveSurvivors == 32
    and SandboxVars.KnoxSurvivors.CompanionLimit == 2,
    "reading the preset never rewrites stored sandbox values")
assert(S.worldPopulation() == 420,
    "keys absent from an old save fall back to the shipped default")
SandboxVars = savedVars

print("Sandbox balance PASS county=true groups=small factions=few raids=late")
