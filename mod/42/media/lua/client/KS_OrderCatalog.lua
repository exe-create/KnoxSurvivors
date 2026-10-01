-- Knox-owned order vocabulary.  This is a presentation/routing catalogue only;
-- execution remains in CompanionService, the autonomy controller, and the
-- existing base task board.
local Catalog = rawget(_G, "KnoxOrderCatalog") or {}
_G.KnoxOrderCatalog = Catalog

-- Normalize human-facing labels at the catalogue boundary.  Menus, migrated
-- saves, and compatibility callers do not always use the internal snake_case
-- key; keeping this conversion here prevents each executor from growing its
-- own spelling rules.
local function orderKey(value)
    if type(value) ~= "string" then return nil end
    local key = string.lower(value)
    key = string.gsub(key, "^%s+", "")
    key = string.gsub(key, "%s+$", "")
    key = string.gsub(key, "[%s%-]+", "_")
    key = string.gsub(key, "[^%w_]", "")
    key = string.gsub(key, "_+", "_")
    return key ~= "" and key or nil
end

local function labelKeyMatches(value)
    local key = orderKey(value)
    if key == nil then return nil end
    for groupName, group in pairs({
        primary = Catalog.primary,
        directives = Catalog.directives,
        basePreferences = Catalog.basePreferences,
        tasks = Catalog.tasks,
        actions = Catalog.actions,
    }) do
        for canonical, entry in pairs(group or {}) do
            if type(entry) == "table" and orderKey(entry.label) == key then
                return canonical
            end
        end
    end
    return nil
end

Catalog.primary = {
    follow = { label = "Follow", description = "Stay with the player." },
    hold = { label = "Hold", description = "Stay near this position." },
    relax = { label = "Relax and Recover", description = "Rest and handle basic needs." },
    return_to_base = { label = "Return to Base", description = "Return to the assigned home base." },
    resume_normal_duty = { label = "Resume Normal Duty", description = "Clear the temporary directive." },
}

Catalog.directives = {
    go_to = { label = "Move to Location", statusLabel = "Moving to location", description = "Move to the selected location." },
    guard = { label = "Guard Location", statusLabel = "Guarding location", description = "Hold a nearby guard post." },
    patrol_area = { label = "Patrol Area", statusLabel = "Patrolling area", description = "Walk a short route through the area." },
    loot_area = { label = "Explore and Search", statusLabel = "Looting marked area", description = "Search useful nearby containers." },
    loot_building = { label = "Loot Building", statusLabel = "Looting marked building", description = "Search this building for useful supplies." },
    loot_corpses = { label = "Loot Dead Bodies", statusLabel = "Searching nearby bodies", description = "Search nearby corpses when safe." },
    find_food = { label = "Find Food", description = "Look for food nearby." },
    find_water = { label = "Find Water", description = "Look for water nearby." },
    find_medical = { label = "Find Medical Supplies", description = "Look for medical supplies nearby." },
    find_weapon = { label = "Find Better Weapon", description = "Look for a more useful weapon nearby." },
    find_tools = { label = "Find Useful Tools", description = "Look for useful tools nearby." },
    find_wood = { label = "Find Wood", description = "Collect logs and firewood for the settlement." },
    find_materials = { label = "Find Materials", description = "Collect building materials for the settlement." },
    find_clothing = { label = "Find Clothing", description = "Collect clothing and warm gear." },
    find_ammo = { label = "Find Ammunition", description = "Collect ammunition for the settlement." },
    clean_inventory = { label = "Clean Up Inventory", description = "Sort carried supplies." },
}

-- Persistent base-task names use the same vocabulary as player orders. This is
-- presentation metadata only; execution remains in BaseJobs and the autonomy
-- controller.
Catalog.tasks = {
    haul = { label = "Haul Corpses" }, sort_depot = { label = "Retired Storage Job" },
    barricade = { label = "Barricade" }, farm_seed = { label = "Plant Crops" },
    farm_water = { label = "Water Crops" }, farm_harvest = { label = "Harvest Crops" },
    farm_plow = { label = "Prepare Soil" }, chop_tree = { label = "Cut Wood" },
    saw_logs = { label = "Saw Logs" }, guard = { label = "Guard" },
    patrol = { label = "Patrol" }, haul_corpse = { label = "Move Corpses" },
    burn_corpse = { label = "Burn Corpses" },
    repair = { label = "Repair" },
    cook = { label = "Cook Food (Stove / Microwave)" },
}

-- Compatibility names that may appear in early Knox saves or manually-created
-- work areas. These map to the current executor vocabulary only; they do not
-- revive the old task implementations.
Catalog.taskAliases = {
    -- Early settlement saves called the real container-transfer executor
    -- simply `haul`; converge that label instead of leaving an unexecutable
    -- task type in the queue.
    haul = "haul_corpse",
    storage_sorting = "sort_depot",
    sort_loot = "sort_depot",
    corpse = "haul_corpse",
    corpse_cleanup = "haul_corpse",
    woodcutting = "chop_tree",
    wood_processing = "saw_logs",
    log_processing = "saw_logs",
    farming = "farm_seed",
    maintenance = "repair",
    patrol_area = "patrol",
}

Catalog.basePreferences = {
    auto = { label = "Automatic" }, guard = { label = "Guard" }, patrol = { label = "Patrol" },
    cooking = { label = "Cooking", description = "Heat suitable stored food in a stove or powered microwave and return meals to food storage." },
    farming = { label = "Farming" }, woodwork = { label = "Woodwork", description = "Cut wood, saw logs and barricade." },
    barricade = { label = "Barricade Windows", description = "Board up windows at the base." },
    hauling = { label = "Move Corpses" },
    repair = { label = "Repair" }, rest = { label = "Rest / Recover", description = "Stay available at base and recover." },
}

-- Player-facing actions that already have executors elsewhere in Knox. These
-- entries are presentation metadata only; dispatch remains in the existing
-- companion, vehicle, and UI handlers.
Catalog.actions = {
    recruit = { label = "Recruit", description = "Ask this survivor to join you." },
    dismiss = { label = "Dismiss", description = "Release this survivor from your group." },
    check_needs = { label = "Check Needs", description = "Review current needs." },
    enter_vehicle = { label = "Take Passenger Seat", description = "Enter a free passenger seat in your vehicle; the driver seat stays yours." },
    drive_ahead = { label = "Take Driver Seat & Drive", description = "You must leave the driver seat first. The survivor enters or switches seats, then drives a short distance." },
    drive_nearest_vehicle = { label = "Drive Nearest Vehicle", description = "Ask this survivor to drive the nearest usable loaded vehicle within 30 tiles. Requires Experimental NPC Driving." },
    exit_vehicle = { label = "Exit Vehicle", description = "Leave the current vehicle after it stops." },
    allow_climbing = { label = "Allow", description = "Allow vaulting and climbing." },
    disallow_climbing = { label = "Disallow", description = "Do not vault or climb." },
    allow_doors = { label = "Allow", description = "Open closed doors and windows." },
    disallow_doors = { label = "Disallow", description = "Do not open doors or windows." },
    enable_autoloot = { label = "Enable Auto-Loot", description = "Pick up useful nearby items and make a short detour for one safe food item while settled in Follow." },
    disable_autoloot = { label = "Disable Auto-Loot", description = "Do not pick up items on your own." },
    open_activity = { label = "Show Activity Feed" },
    open_notebook = { label = "Open Survivor Notebook" },
    open_base = { label = "Open Base Management" },
    party_orders = { label = "Party Orders" },
    base_work_orders = { label = "Base Work Orders" },
    assign_base_task = { label = "Assign Base Task", description = "Assign a selected queued task to this resident." },
    vehicle_orders = { label = "Vehicle Orders" },
    traversal_orders = { label = "Vaulting and Climbing" },
    door_orders = { label = "Doors and Windows" },
    combat_stance = { label = "Combat Stance" },
    weapon_preference = { label = "Weapon Preference" },
    loot_orders = { label = "Loot Orders" },
    survival_orders = { label = "Survival Orders" },
    move_party = { label = "Move Party Here" },
    guard_location = { label = "Guard This Location" },
    patrol_location = { label = "Patrol This Area" },
}

-- Stable presentation order for menus.  Keeping this beside the catalogue
-- prevents UI files from quietly growing a second, divergent order list.
Catalog.basePreferenceOrder = {
    "auto", "guard", "patrol", "farming", "cooking", "woodwork", "barricade",
    "hauling", "repair", "rest",
}

-- Compatibility vocabulary for familiar survivor commands.  These are aliases
-- only: execution still goes through Knox's existing directive/primary owners.
-- Keeping the mapping here lets future menus and saved legacy commands converge
-- on one Build 42 order representation without importing the old task system.
Catalog.aliases = {
    explore = "loot_area",
    search = "loot_area",
    loot = "loot_area",
    forage = "loot_area",
    loot_room = "loot_building",
    go_find_food = "find_food",
    go_find_water = "find_water",
    go_find_weapon = "find_weapon",
    go_find_medical = "find_medical",
    go_find_tools = "find_tools",
    doctor = "find_medical",
    stand_ground = "hold",
    hold_still = "hold",
    stay = "hold",
    wait = "hold",
    hold_position = "hold",
    defend = "guard",
    escort = "follow",
    stop = "resume_normal_duty",
    return_home = "return_to_base",
    go_home = "return_to_base",
    ["return"] = "return_to_base",
    recover = "relax",
    rest = "relax",
    sort_loot_into_base = "clean_inventory",
    search_area = "loot_area",
    search_building = "loot_building",
    loot_dead_bodies = "loot_corpses",
    loot_bodies = "loot_corpses",
    get_food = "find_food",
    get_water = "find_water",
    get_meds = "find_medical",
    get_medical = "find_medical",
    get_weapon = "find_weapon",
    get_tools = "find_tools",
    guard_area = "guard",
    -- `patrol` is intentionally not an alias here: it is the canonical base
    -- preference. Legacy patrol directives are normalized by persistence, and
    -- payload-bearing shorthand is handled by makeDirective/dispatch.
    go_to_base = "return_to_base",
    cancel_order = "resume_normal_duty",
    cancel = "resume_normal_duty",
    chop_wood = "woodwork",
    pile_corpses = "hauling",
    farming = "farming",
    woodcutting = "woodwork",
    storage_sorting = "hauling",
    corpse_cleanup = "hauling",
    repair_maintenance = "repair",
    rest_recover = "relax",
}

-- One canonical mapping for automatic resident preferences.  The task board
-- still owns task creation/claims; this metadata only answers whether a
-- persisted preference is a sensible match for an already queued task.
Catalog.preferenceTaskGroups = {
    guard = { guard = true },
    patrol = { patrol = true },
    repair = { repair = true },
    cooking = { cook = true },
    farming = { farm_seed = true, farm_water = true, farm_harvest = true, farm_plow = true },
    woodwork = { chop_tree = true, saw_logs = true, barricade = true },
    barricade = { barricade = true },
    hauling = { haul = true, haul_corpse = true, burn_corpse = true },

}

-- Resolve a player-facing order once at the catalogue boundary.  Callers still
-- decide which existing executor owns the result, but they no longer need to
-- repeat alias/category checks (and accidentally let a legacy label fall
-- through a different path).  This is metadata only; it does not create a new
-- task or controller.
function Catalog.resolve(kind)
    local normalized = Catalog.normalize(kind)
    if normalized == nil or not Catalog.isKnown(normalized) then
        return nil, "unknown_order"
    end
    if Catalog.isPrimaryOrder(normalized) then
        return { kind = normalized, category = "primary" }
    end
    if Catalog.isDirective(normalized) then
        return { kind = normalized, category = "directive" }
    end
    if Catalog.isBasePreference(normalized) then
        return { kind = normalized, category = "base_preference" }
    end
    local preference = Catalog.preferenceForTask(normalized)
    if preference ~= nil then
        return {
            kind = normalized,
            category = "task_preference",
            preference = preference,
        }
    end
    if Catalog.actions[normalized] ~= nil then
        return { kind = normalized, category = "action" }
    end
    return nil, "unsupported_order"
end

function Catalog.get(kind)
    if type(kind) ~= "string" or kind == "" then return nil end
    -- Prefer an exact canonical entry before applying compatibility aliases.
    -- Some familiar labels (for example `barricade`) are also aliases for a
    -- broader resident preference; the concrete task/action keeps its own
    -- label when a menu or status view asks for it directly.
    local exact = Catalog.primary[kind] or Catalog.directives[kind]
        or Catalog.basePreferences[kind] or Catalog.tasks[kind]
        or Catalog.actions[kind]
    if exact ~= nil then return exact end
    local normalized = Catalog.normalize(kind)
    if normalized == nil then return nil end
    return Catalog.primary[normalized] or Catalog.directives[normalized]
        or Catalog.basePreferences[normalized] or Catalog.tasks[normalized]
        or Catalog.actions[normalized]
end

function Catalog.normalize(kind)
    if type(kind) ~= "string" or kind == "" then return nil end
    -- `patrol` is both a settlement preference and an older shorthand used
    -- by companion callers. Keep the canonical preference here; payload-
    -- bearing companion calls are promoted to `patrol_area` by dispatch.
    if kind == "patrol" then return "patrol" end
    local key = orderKey(kind) or kind
    local alias = Catalog.aliases[key]
    if alias ~= nil then return alias end
    return labelKeyMatches(kind) or key
end

function Catalog.normalizeTaskType(taskType)
    if type(taskType) ~= "string" or taskType == "" then return nil end
    local key = orderKey(taskType) or taskType
    return Catalog.taskAliases[key] or key
end

function Catalog.normalizeBasePreference(preference)
    local normalized = Catalog.normalize(preference)
    -- Older Knox saves used the directive spelling for a resident's recurring
    -- patrol role. Keep that migration at the preference boundary so explicit
    -- companion patrol-area directives remain distinct.
    if normalized == "patrol_area" then return "patrol" end
    return normalized
end

function Catalog.label(kind, fallback)
    local entry = Catalog.get(kind)
    return entry ~= nil and entry.label or fallback or tostring(kind or "")
end

function Catalog.description(kind)
    local entry = Catalog.get(kind)
    return entry ~= nil and entry.description or nil
end

function Catalog.statusLabel(kind, fallback)
    local entry = Catalog.get(kind)
    return entry ~= nil and (entry.statusLabel or entry.label) or fallback
end

function Catalog.preferenceMatchesTask(preference, taskType)
    -- Preferences are persisted independently from concrete directives.  Use
    -- the preference migration boundary here as well as in the scheduler so
    -- older `patrol_area` resident roles still match current `patrol` tasks
    -- when this helper is called directly by menus or compatibility code.
    preference = (Catalog.normalizeBasePreference ~= nil
        and Catalog.normalizeBasePreference(preference)
        or Catalog.normalize(preference)) or preference
    taskType = Catalog.normalizeTaskType(taskType) or taskType
    if preference == nil or preference == "" or preference == "auto" then
        return true
    end
    if preference == "rest" then return false end
    local group = Catalog.preferenceTaskGroups[preference]
    return group ~= nil and group[tostring(taskType or "")] == true or false
end

function Catalog.preferenceForTask(taskType)
    local value = tostring(Catalog.normalizeTaskType(taskType) or taskType or "")
    for preference, group in pairs(Catalog.preferenceTaskGroups) do
        if group[value] == true then return preference end
    end
    return nil
end

function Catalog.isDirective(kind)
    local normalized = Catalog.normalize(kind)
    return normalized ~= nil and Catalog.directives[normalized] ~= nil
end

function Catalog.isPrimaryOrder(kind)
    local normalized = Catalog.normalize(kind)
    return normalized ~= nil and Catalog.primary[normalized] ~= nil
end

function Catalog.isBasePreference(kind)
    local normalized = Catalog.normalize(kind)
    return normalized ~= nil and Catalog.basePreferences[normalized] ~= nil
end

function Catalog.isKnown(kind)
    return Catalog.get(kind) ~= nil
end

function Catalog.makeDirective(kind, payload)
    local normalized = Catalog.normalize(kind)
    -- Compatibility callers may still construct a patrol directive by its
    -- shorthand. Resolve that form only while building a payload-bearing
    -- directive; payload-less `patrol` remains a base preference.
    if kind == "patrol" then normalized = "patrol_area" end
    if not Catalog.isDirective(normalized) or type(payload) ~= "table" then
        return nil, "invalid_directive"
    end
    local directive = {}
    for key, value in pairs(payload) do directive[key] = value end
    directive.kind = normalized
    return directive
end

return Catalog
