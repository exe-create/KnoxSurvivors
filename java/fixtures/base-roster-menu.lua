-- Drives the real SurvivorContextMenu.populateRoster with a recording menu, so
-- the roster's options are proven to be built by the shared order builder rather
-- than merely existing as a function.
local Menu = assert(KnoxSurvivorContextMenu, "the survivor context menu module is loaded")
local Catalog = assert(KnoxOrderCatalog, "the order catalog is loaded")
local Persistence = assert(KnoxPersistence, "the persistence owner is loaded")

local function recordingMenu()
    local menu = { labels = {}, options = {} }
    function menu:addOption(label)
        local option = { label = label, checked = false, notAvailable = false }
        function option:setOptionChecked(value) self.checked = value end
        self.labels[#self.labels + 1] = label
        self.options[#self.options + 1] = option
        return option
    end
    function menu:addSubMenu(option, sub) if option ~= nil then option.sub = sub end end
    function menu:setOptionChecked() end
    return menu
end

local previousMenuClass = ISContextMenu
ISContextMenu = { getNew = function() return recordingMenu() end }
local previousIds = Persistence.getBaseResidentIds
local previousDuty = Persistence.getSurvivorDuty
local previousViewModel = rawget(_G, "KnoxSurvivorViewModel")
local previousPlayer = getSpecificPlayer

getSpecificPlayer = function() return {} end
_G.KnoxSurvivorViewModel = { getSurvivor = function(id) return { displayName = id } end }
Persistence.getBaseResidentIds = function() return { "alpha", "beta" } end
Persistence.getSurvivorDuty = function(id)
    if id == "alpha" then
        return { mode = "base", jobPreference = "guard", allowLootRuns = false,
            baseSupplyOrder = { kind = "find_food" } }
    end
    return { mode = "base", allowLootRuns = true }
end

local roster = recordingMenu()
Menu.populateRoster(roster, 0, { id = "base-roster" })

assert(#roster.labels == 3, "the roster lists every resident beside the shared crew order")
assert(roster.labels[1] == "Send a Gather / Scavenge Crew", "the roster offers the existing mission chooser")
assert(roster.labels[2] == "alpha" and roster.labels[3] == "beta", "residents are named")

local alpha = roster.options[2]
local sub = alpha.sub
assert(sub ~= nil, "each resident opens an order menu")
-- Options live in nested submenus (Base Work Orders, Survival Orders), so the
-- assertion walks the real tree the builder created.
local function collect(menu, into)
    if menu == nil then return into end
    for _, label in ipairs(menu.labels or {}) do into[#into + 1] = label end
    for _, option in ipairs(menu.options or {}) do collect(option.sub, into) end
    return into
end
local joined = collect(sub, {})
local function has(label)
    for _, present in ipairs(joined) do
        if present == label then return true end
    end
    return false
end

assert(has("Base Work Orders"), "the roster offers the full job preference list")
assert(has("Survival Orders"), "the roster offers the existing survival orders")
assert(has("Stay Home During Supply Runs"), "the roster exposes stay-home")
assert(has("Fetch a Specific Item"), "the roster exposes the fetch order")
assert(has("Send Home to Another Base"), "the roster exposes send-home")
assert(has(Catalog.label("resume_normal_duty")), "the roster exposes cancel-supply")

-- Roles from across the catalog are reachable, not just the first entry.
local function roleLabel(preference)
    local entry = Catalog.get(preference)
    if preference == "hauling" then return "Move Corpses" end
    return entry ~= nil and entry.label or nil
end
for _, preference in ipairs(Catalog.basePreferenceOrder) do
    local label = roleLabel(preference)
    assert(label ~= nil, "the catalog names the role " .. tostring(preference))
    assert(has(label), "the roster exposes the role " .. tostring(label))
end

ISContextMenu = previousMenuClass
Persistence.getBaseResidentIds = previousIds
Persistence.getSurvivorDuty = previousDuty
_G.KnoxSurvivorViewModel = previousViewModel
getSpecificPlayer = previousPlayer
