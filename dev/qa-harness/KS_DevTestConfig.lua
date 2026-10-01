require "KS_Settings"

local KnoxDevTests = rawget(_G, "KnoxDevTests") or {}
_G.KnoxDevTests = KnoxDevTests

-- Developer behavior is opt-in per save through the real sandbox options.
KnoxDevTests.enabled = KnoxSettings.developerToolsEnabled()
KnoxDevTests.activeScenario = KnoxSettings.developerScenario()
KnoxDevTests.sandboxOverrides = false
KnoxDevTests.allowZombieCleanup = false
KnoxDevTests.normalZombiePopulation = true
KnoxDevTests.testPopulation = 3
KnoxDevTests.obstacleScanRadius = 12
-- A locked-window test permanently smashes one nearby window in the loaded save.
KnoxDevTests.allowDestructiveWindowTest = KnoxSettings.allowDestructiveDeveloperTests()
-- The current persistence gate always includes a bag so the back slot is regression-tested.
KnoxDevTests.forceStarterBag = false

KnoxDevTests.scenarios = {
    movement = "ACTIVE_IN_OBSTACLE_SUITE",
    door = "ACTIVE_IN_OBSTACLE_SUITE",
    window_open = "ACTIVE_IN_OBSTACLE_SUITE",
    window_locked = "ACTIVE_DESTRUCTIVE_IN_OBSTACLE_SUITE",
    fence = "ACTIVE_IN_OBSTACLE_SUITE",
    locked_entry = "WAITING_FOR_ALTERNATE_ROUTE_PLANNER",
    equipment = "LIVE_PASS_HIBERNATING",
    combat = "LIVE_PASS_HIBERNATING",
    loot = "LIVE_PASS_HIBERNATING",
    health = "LIVE_PASS_HIBERNATING",
    medical = "LIVE_PASS_RELOAD_VERIFIED_BY_NEEDS_PREFLIGHT",
    medical_supplies = "IMPLEMENTED_DORMANT_AFTER_MEDICAL_RELOAD",
    needs = "LIVE_PASS_HIBERNATING",
    autonomy = "REPLACED_BY_MULTI_SURVIVOR_AUTONOMY",
    persistence = "ACTIVE_ACROSS_APPEARANCE_INVENTORY_HEALTH_NEEDS_POPULATION",
    population = "LIVE_PASS_TWO_SURVIVOR_RUNTIME_HIBERNATING",
    survival = "ACTIVE_THREE_SURVIVORS_NORMAL_ZOMBIES_FULL_AUTONOMY",
    relationships = "ACTIVE_ATTRACTION_JOIN_DECLINE_ROBBERY_FACTION_BASE",
    capabilities = "ACTIVE_FIRST_LIVE_OCCUPATION_TRAIT_SKILL_RELOAD",
    companions = "ACTIVE_FIRST_LIVE_TALK_RECRUIT_FOLLOW_HOLD_RETURN_DISMISS",
    companion_hud = "ACTIVE_FIRST_LIVE_PORTRAIT_CONTEXT_SPLITSCREEN",
    base_domain = "ACTIVE_FIRST_LIVE_PLAYER_HOME_STORAGE_RESIDENT_PATROL",
}
