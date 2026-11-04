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
    find_fuel = { label = "Find Fuel", description = "Collect fuel cans for the settlement." },
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
    cooking = { label = "Cooking", description = "Prepare meals from suitable cookware and two different ingredients using game recipes, or cook unsafe raw food directly. Heat and return finished food to storage." },
    farming = { label = "Farming" }, woodwork = { label = "Woodwork", description = "Cut wood, saw logs and barricade." },
    barricade = { label = "Barricade Windows", description = "Board up windows at the base." },
    hauling = { label = "Move Corpses" },
    repair = { label = "Repair" }, rest = { label = "Rest / Recover", description = "Stay available at base and recover." },
}

-- Nine roles are small bundles over the existing duty.jobPreference field.
-- They do not add a second roster or a second task owner: the role key is the
-- stored preference, the existing scheduler selects work, and the existing
-- schedule writer persists the six-block rota. Old preference keys remain
-- valid so compatible saves keep their current behavior.
Catalog.baseRoles = {
    guard = {
        label = "Guard",
        description = "Keep watch, patrol and answer alarms.",
        tasks = { guard = true, patrol = true },
        gear = { "melee", "firearm", "ammo", "bandage", "water" },
    },
    scavenger = {
        label = "Scavenger",
        description = "Lead supply runs and carry useful finds home.",
        tasks = {},
        gear = { "bag", "knife", "bandage", "water", "light" },
    },
    cook = {
        label = "Cook",
        description = "Prepare meals and keep the kitchen supplied.",
        tasks = { cook = true },
        gear = { "knife", "can_opener", "water", "fuel" },
    },
    farmer = {
        label = "Farmer",
        description = "Prepare soil, plant, water and harvest crops.",
        tasks = { farm_seed = true, farm_water = true, farm_harvest = true, farm_plow = true },
        gear = { "hoe", "seeds", "water" },
    },
    builder = {
        label = "Builder",
        description = "Barricade, repair and prepare building materials.",
        tasks = { barricade = true, repair = true, chop_tree = true, saw_logs = true },
        gear = { "hammer", "saw", "planks", "nails" },
    },
    medic = {
        label = "Medic",
        description = "Carry treatment supplies and assist the wounded.",
        tasks = {},
        gear = { "bandage", "disinfectant", "painkiller" },
    },
    mechanic = {
        label = "Mechanic",
        description = "Repair engines and keep tools and vehicles working.",
        tasks = { repair = true },
        gear = { "wrench", "screwdriver", "parts" },
    },
    quartermaster = {
        label = "Quartermaster",
        description = "Haul, count and keep base storage in order.",
        tasks = {},
        gear = { "bag", "clipboard" },
    },
    runner = {
        label = "Runner",
        description = "Carry messages and hand supplies between people.",
        tasks = {},
        gear = { "bag", "water", "bandage" },
    },
}

Catalog.baseRoleOrder = {
    "guard", "scavenger", "cook", "farmer", "builder",
    "medic", "mechanic", "quartermaster", "runner",
}

for key, role in pairs(Catalog.baseRoles) do
    Catalog.basePreferences[key] = {
        label = role.label,
        description = role.description,
        role = true,
    }
end

Catalog.legacyRolePreference = {
    guard = "guard", patrol = "guard", cooking = "cook", farming = "farmer",
    woodwork = "builder", barricade = "builder", hauling = "quartermaster",
    repair = "mechanic",
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
    let_companion_drive = { label = "Let a Companion Drive", description = "Wait beside the driver seat while a companion takes the wheel. You must move to a passenger seat yourself; the mod never moves you." },
    take_wheel = { label = "Take the Wheel", description = "Ask your companion to stop and move to a passenger seat, then take the driver seat with the native control." },
    exit_vehicle = { label = "Exit Vehicle", description = "Leave the current vehicle after it stops." },
    -- One control, one live value (UI.md law 4): each row states the setting
    -- and the state it selects, using the same words as the talk panel's
    -- Doors/Climbing lines. A bare Allow/Disallow pair made the player read a
    -- switch instead of a state, and read the same either way in a submenu.
    allow_climbing = { label = "Climbing: Allowed", description = "Vault and climb through windows and over low walls." },
    disallow_climbing = { label = "Climbing: Closed", description = "Do not vault or climb." },
    allow_doors = { label = "Doors: Allowed", description = "Open closed doors and windows." },
    disallow_doors = { label = "Doors: Closed", description = "Do not open doors or windows." },
    enable_autoloot = { label = "Pick Up: On", description = "Pick up useful nearby items and make a short detour for one safe food item while settled in Follow." },
    disable_autoloot = { label = "Pick Up: Off", description = "Do not pick up items on your own." },
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

-- The schedule UI presents six four-hour blocks, but the persisted authority
-- remains KnoxPersistence's hourly duty windows. This metadata only expands a
-- block choice into the existing 24-hour draft; it never writes a schedule.
Catalog.scheduleBlocks = {
    { key = "night", label = "Night", startHour = 0 },
    { key = "dawn", label = "Dawn", startHour = 4 },
    { key = "morning", label = "Morning", startHour = 8 },
    { key = "afternoon", label = "Afternoon", startHour = 12 },
    { key = "evening", label = "Evening", startHour = 16 },
    { key = "dusk", label = "Dusk", startHour = 20 },
}

-- The schedule blocks are the same six four-hour windows the persistence layer
-- already stores, so their clock range is derived from startHour instead of
-- being typed a second time. 12-hour form because the rest of the survivor UI
-- speaks in clock hours.
function Catalog.hourLabel(hour)
    local value = math.floor((tonumber(hour) or 0) % 24)
    local display = value % 12
    if display == 0 then display = 12 end
    return tostring(display) .. (value < 12 and "am" or "pm")
end

-- "8am-12pm". A block that ends at 24 reads as 12am, not 0am.
-- The separator is a plain ASCII hyphen on purpose: the en dash this used to
-- carry has no glyph in the game's bitmap font, so it was drawn as nothing and
-- the player read "4am7pm". Any separator here must survive the font.
Catalog.hourRangeSeparator = "-"
function Catalog.scheduleBlockHours(block)
    local startHour = type(block) == "table" and tonumber(block.startHour) or nil
    if startHour == nil then return nil end
    return Catalog.hourLabel(startHour) .. Catalog.hourRangeSeparator
        .. Catalog.hourLabel(startHour + 4)
end

-- Player-facing label for a schedule block: "Morning (8am-12pm)".
function Catalog.scheduleBlockLabel(block)
    if type(block) ~= "table" then return nil end
    local hours = Catalog.scheduleBlockHours(block)
    if hours == nil then return block.label end
    return tostring(block.label) .. " (" .. hours .. ")"
end

-- Resolve the single four-hour block containing a clock hour. Temporary duty
-- overrides use this to end at the next block boundary without owning a second
-- clock or schedule table. Returns a new table so callers cannot mutate the
-- catalogue metadata.
function Catalog.scheduleBlockWindow(hour)
    local value = tonumber(hour)
    if value == nil or value ~= value then return nil end
    value = value % 24
    for index, block in ipairs(Catalog.scheduleBlocks) do
        local endsAtHour = block.startHour + 4
        if value >= block.startHour and value < endsAtHour then
            return {
                index = index,
                key = block.key,
                label = block.label,
                hoursText = Catalog.scheduleBlockHours(block),
                startHour = block.startHour,
                endsAtHour = endsAtHour,
                hoursRemaining = endsAtHour - value,
            }
        end
    end
    return nil
end

-- Expand exactly six block assignments into a fresh 24-hour draft. A malformed
-- template is refused rather than producing a partial rota.
function Catalog.scheduleHoursFromBlocks(blocks)
    if type(blocks) ~= "table" or #blocks ~= #Catalog.scheduleBlocks then return nil end
    local hours = {}
    for block = 1, #blocks do
        local value = blocks[block]
        if type(value) ~= "string" or value == "" then return nil end
        for offset = 0, 3 do
            hours[(block - 1) * 4 + offset + 1] = value
        end
    end
    return hours
end

-- A block is only displayable as one value when all four hours agree. Mixed
-- saved hours return nil so the strip can say so instead of inventing one.
function Catalog.scheduleBlockValue(hours, blockIndex)
    local block = Catalog.scheduleBlocks[tonumber(blockIndex) or 0]
    if block == nil or type(hours) ~= "table" then return nil end
    local value = hours[block.startHour + 1]
    if value == nil then return nil end
    for offset = 1, 3 do
        if hours[block.startHour + offset + 1] ~= value then return nil end
    end
    return value
end

-- Apply one block choice to a draft. The caller still owns Save Hours; this
-- helper only keeps the six-block UI and the hourly draft in the same shape.
function Catalog.setScheduleBlock(hours, blockIndex, value)
    local block = Catalog.scheduleBlocks[tonumber(blockIndex) or 0]
    if block == nil or type(hours) ~= "table" or type(value) ~= "string" then
        return false
    end
    for offset = 0, 3 do
        hours[block.startHour + offset + 1] = value
    end
    return true
end

-- Role-hours templates are six four-hour blocks over the existing hourly
-- duty schedule. They are presentation presets, not a second roster: the
-- stored jobPreference remains the role, and the player still saves or edits
-- the resulting hours through the existing schedule writer. Auto and Rest
-- deliberately have no template; neither has a work rhythm to impose.
Catalog.baseRoleBlocks = {
    guard = { "guard", "sleep", "sleep", "work", "work", "guard" },
    patrol = { "sleep", "work", "patrol", "work", "patrol", "recreation" },
    cooking = { "sleep", "work", "work", "recreation", "work", "sleep" },
    farming = { "sleep", "sleep", "work", "work", "work", "anything" },
    woodwork = { "sleep", "sleep", "work", "work", "work", "recreation" },
    barricade = { "sleep", "sleep", "work", "work", "work", "recreation" },
    hauling = { "sleep", "sleep", "work", "work", "recreation", "sleep" },
    repair = { "sleep", "sleep", "work", "work", "work", "recreation" },
    scavenger = { "sleep", "work", "work", "work", "recreation", "sleep" },
    cook = { "sleep", "work", "work", "recreation", "work", "sleep" },
    farmer = { "sleep", "sleep", "work", "work", "work", "anything" },
    builder = { "sleep", "sleep", "work", "work", "work", "recreation" },
    medic = { "sleep", "work", "work", "work", "recreation", "sleep" },
    mechanic = { "sleep", "sleep", "work", "work", "work", "recreation" },
    quartermaster = { "sleep", "work", "work", "work", "recreation", "sleep" },
    runner = { "sleep", "work", "work", "work", "work", "sleep" },
}

-- Return a fresh 24-hour draft for the selected existing role. A nil result
-- means the role has no default hours; callers must leave the draft alone.
function Catalog.roleScheduleHours(preference)
    local normalized = Catalog.normalizeBasePreference(preference)
    local blocks = normalized ~= nil and Catalog.baseRoleBlocks[normalized] or nil
    if blocks == nil then return nil end
    return Catalog.scheduleHoursFromBlocks(blocks)
end

-- Resolve a copy scope against the caller's live base roster. A record is
-- { id = survivorId, role = stored jobPreference }. The source resident is
-- always excluded: copying a rota back onto its owner is not a target.
-- This helper only answers ids; the existing schedule service/writer still
-- owns contact, ownership and persistence.
function Catalog.scheduleCopyTargets(sourceId, roster, scope, value)
    if sourceId == nil or type(roster) ~= "table" then return {} end
    if scope ~= "all" and scope ~= "role" and scope ~= "person" then return {} end
    local wantedRole = scope == "role"
        and Catalog.normalizeBasePreference(value) or nil
    local wantedId = scope == "person" and value ~= nil
        and tostring(value) or nil
    if scope == "role" and wantedRole == nil then return {} end
    if scope == "person" and (wantedId == nil or wantedId == "") then return {} end
    local source = tostring(sourceId)
    local targets, seen = {}, {}
    for _, entry in ipairs(roster) do
        local id = type(entry) == "table" and entry.id or nil
        if id ~= nil then
            local key = tostring(id)
            local role = type(entry) == "table"
                and Catalog.normalizeBasePreference(entry.role) or nil
            local include = scope == "all"
                or (scope == "role" and role == wantedRole)
                or (scope == "person" and key == wantedId)
            if key ~= source and include and not seen[key] then
                seen[key] = true
                targets[#targets + 1] = id
            end
        end
    end
    return targets
end

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
    -- `rest` is a saved base preference, but the general directive aliases
    -- also map the same word to `relax`. Keep the preference spelling at this
    -- boundary so the existing Rest / Recover role remains selectable.
    if orderKey(preference) == "rest" then return "rest" end
    local normalized = Catalog.normalize(preference)
    -- Older Knox saves used the directive spelling for a resident's recurring
    -- patrol role. Keep that migration at the preference boundary so explicit
    -- companion patrol-area directives remain distinct.
    if normalized == "patrol_area" then return "patrol" end
    return normalized
end

-- Resolve a stored preference to one of the nine role bundles. Legacy
-- preferences keep their old work behavior but display as the closest role;
-- auto and rest have no role. This is presentation/selection metadata only.
function Catalog.roleForPreference(preference)
    local normalized = Catalog.normalizeBasePreference(preference)
    if normalized == nil or normalized == "" or normalized == "auto" then return nil end
    if Catalog.baseRoles[normalized] ~= nil then return normalized end
    return Catalog.legacyRolePreference[normalized]
end

function Catalog.roleGear(role)
    local key = Catalog.roleForPreference(role)
    local definition = key ~= nil and Catalog.baseRoles[key] or nil
    if definition == nil or type(definition.gear) ~= "table" then return nil end
    local tags = {}
    for index, tag in ipairs(definition.gear) do tags[index] = tag end
    return tags
end

-- One short readiness sentence for the selected resident. `missing` and
-- `stock` are facts from the real inventory/storage owners; this helper only
-- formats them, so the Crew line and any later surface cannot disagree.
function Catalog.roleKitStatusText(role, gear, missing, stock)
    local key = Catalog.roleForPreference(role)
    local definition = key ~= nil and Catalog.baseRoles[key] or nil
    if definition == nil or type(gear) ~= "table" or #gear == 0 then
        return "Kit: no role assigned."
    end
    if type(missing) ~= "table" or #missing == 0 then
        return "Kit ready: " .. definition.label .. "."
    end
    local labels, available, unavailable = {}, {}, {}
    for _, tag in ipairs(missing) do
        local label = tostring(tag):gsub("_", " ")
        labels[#labels + 1] = label
        if type(stock) == "table" and stock[tag] ~= nil then
            available[#available + 1] = label
        else
            unavailable[#unavailable + 1] = label
        end
    end
    local gap = table.concat(labels, ", ")
    if #available == 0 then
        return "Kit shortage: " .. gap .. " — no assigned stock."
    end
    if #unavailable == 0 then
        return "Kit shortage: " .. gap .. " — stock available."
    end
    return "Kit shortage: " .. gap .. " — stock for "
        .. table.concat(available, ", ") .. " only."
end

-- Role fit for an ordered mission. Dispatch remains in KS_SurvivorAutonomy;
-- this is selection vocabulary only. Auto is the neutral score for an
-- unassigned or legacy preference that has no role bundle. The mission type is
-- the persisted order type, not a display label.
Catalog.missionRoleScores = {
    scout = {
        scavenger = 100, runner = 90, guard = 80, quartermaster = 70,
        auto = 50, farmer = 50, builder = 50, mechanic = 45, cook = 35, medic = 30,
    },
    food = {
        cook = 100, scavenger = 90, quartermaster = 80, farmer = 70, runner = 65,
        guard = 55, auto = 50, builder = 45, mechanic = 45, medic = 40,
    },
    medicine = {
        medic = 100, scavenger = 85, quartermaster = 75, runner = 70, cook = 60,
        guard = 55, auto = 50, farmer = 45, builder = 40, mechanic = 40,
    },
    tools = {
        builder = 100, mechanic = 90, quartermaster = 80, scavenger = 75,
        runner = 65, auto = 50, guard = 45, farmer = 45, cook = 30, medic = 30,
    },
    weapons = {
        guard = 100, scavenger = 90, runner = 80, quartermaster = 70,
        builder = 55, auto = 50, mechanic = 45, farmer = 40, cook = 30, medic = 30,
    },
    building = {
        builder = 100, mechanic = 90, quartermaster = 80, scavenger = 75,
        runner = 65, auto = 50, guard = 45, farmer = 45, cook = 30, medic = 30,
    },
}

function Catalog.missionRoleScore(role, missionType)
    local scores = Catalog.missionRoleScores[tostring(missionType or "scout")]
    if scores == nil then return nil end
    local key = Catalog.roleForPreference(role) or "auto"
    return scores[key] or scores.auto
end

-- Pure role ordering for a mission party. It returns ids, not candidate
-- records: eligibility, party size, live-vs-ledger selection and duty writes
-- still belong to the dispatch owner. Ties resolve by id, then input order, so
-- table iteration can never make the chosen crew unstable.
function Catalog.rankMissionCandidates(candidates, missionType)
    local scores = Catalog.missionRoleScores[tostring(missionType or "scout")]
    if scores == nil or type(candidates) ~= "table" then return {} end
    local ranked = {}
    for index, candidate in ipairs(candidates) do
        local id = type(candidate) == "table" and candidate.id or nil
        if id ~= nil then
            local role = Catalog.roleForPreference(candidate.role) or "auto"
            ranked[#ranked + 1] = {
                id = id, score = scores[role] or scores.auto,
                key = tostring(id), index = index,
            }
        end
    end
    table.sort(ranked, function(left, right)
        if left.score ~= right.score then return left.score > right.score end
        if left.key ~= right.key then return left.key < right.key end
        return left.index < right.index
    end)
    local ids = {}
    for index, entry in ipairs(ranked) do ids[index] = entry.id end
    return ids
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
    local role = Catalog.baseRoles[preference]
    if role ~= nil then
        return role.tasks ~= nil and role.tasks[tostring(taskType or "")] == true
    end
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
    -- Use the base-preference migration boundary, not the general order
    -- aliases: `rest` is a saved preference even though the directive
    -- vocabulary also uses that word for `relax`.
    local normalized = Catalog.normalizeBasePreference(kind)
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

-- Presentation only: the callback remains the existing service/action owner.
-- Preserve both individual (ok, reason) and party (ok, count, reason) receipts.
local FAILURE_TEXT = {
    player_unavailable = "Your character is unavailable.",
    invalid_player = "Your character is unavailable.",
    unavailable = "They are unavailable right now.",
    not_loaded = "They are not nearby. Get back in contact first.",
    survivor_unavailable = "They are unavailable right now.",
    companion_detached = "They cannot receive orders yet. Wait for them to return nearby.",
    busy = "They are busy right now. Try again when they are free.",
    no_companions = "No companion could take this order.",
    no_eligible_companions = "No companion is available for this destination.",
    no_directives = "There are no active orders to clear.",
    no_player_base = "Claim a base before assigning this work.",
    no_base = "Assign a home base first.",
    not_your_survivor = "You can only manage your own survivors.",
    not_your_base_resident = "Select one of your residents at this base.",
    invalid_player_base = "That base is no longer available to you. Choose one of your bases.",
    no_supply_order = "There is no supply order to clear.",
    too_far_away = "Get closer and stay on the same floor before trying again.",
    interaction_ended = "They are no longer waiting for you. Open the pack again.",
    inventory_ui_unavailable = "The inventory screen is not available right now.",
    no_contact = "Get within clear sight or speaking distance before asking them to join.",
    already_with_group = "They are already travelling with other people.",
    not_your_companion = "You can only give this order to your own companions.",
    task_target_required = "Choose a target for this job first.",
    destination_unavailable = "Choose an available destination first.",
    hostile = "They will not accept your request while hostile.",
    companion_limit = "Your companion limit has been reached.",
    needs_time = "They need more time before joining you.",
    prefers_alone = "They prefer to travel alone.",
    low_reputation = "They do not trust you enough yet.",
    save_failed = "The change could not be saved. Try again.",
    task_in_progress = "That job is already in progress. Wait for it to finish.",
    already_cancelled = "That job is already cancelled.",
    not_resumable = "That job can no longer be resumed. Refresh the task list.",
    unknown_task = "That job is no longer available. Choose another job.",
}

function Catalog.failureText(reason)
    return FAILURE_TEXT[reason] or "The request could not be accepted. Try again when they are available."
end

function Catalog.withFeedback(action, callback, ...)
    local executed, accepted, result, reason = pcall(callback, ...)
    if not executed then
        print("[KnoxSurvivors][Orders] action=" .. tostring(action) .. " error=" .. tostring(accepted))
    end
    if not executed or accepted ~= true then
        local code = executed and (type(result) == "string" and result or reason) or nil
        -- deliverOrder already gives a named, knowledge-limited contact failure.
        if code ~= "order_not_delivered" then
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then
                feed.event(tostring(action or "Request") .. ": " .. Catalog.failureText(code))
            end
        end
    end
    if not executed then return false, "action_failed" end
    return accepted, result, reason
end

return Catalog
