-- Knox Survivors — the creator's roster model. PT-40.
--
-- Pure decisions only: what a person may be, what a roster line looks like, and
-- which people are still waiting to exist. The panel (KS_CreatorPanel) asks the
-- questions; the population writer allocates the bodies; the appearance and
-- starting-gear owners dress and kit them. Nothing here touches the world.
local Creator = rawget(_G, "KnoxCreator") or {}
_G.KnoxCreator = Creator

Creator.FILE = "KnoxSurvivors/creator.txt"
Creator.MAX_PEOPLE = 8
Creator.MAX_NAME = 24

-- The main-menu button belongs to the main menu screen and nowhere else: not
-- over the solo, load, sandbox, options or character-creation panels, and not
-- in a running game. The panel gathers the facts; this rule decides, so the
-- wrong-screen cases are provable without a running game.
Creator.MENU_BUTTON_LABEL = "KS Creator"

function Creator.menuButtonVisible(facts)
    if type(facts) ~= "table" then return false end
    if facts.inGame == true then return false end
    if facts.mainScreen ~= true then return false end
    if facts.subScreen == true then return false end
    return true
end

Creator.LOOKS = {
    { id = "casual", label = "Casual",
      items = { "Base.Trousers_Denim", "Base.Shirt_FormalWhite" } },
    { id = "work", label = "Work clothes",
      items = { "Base.Trousers_Workman", "Base.Shirt_Workman" } },
    { id = "police", label = "Police uniform",
      items = { "Base.Trousers_Police", "Base.Shirt_PoliceBlue", "Base.Hat_Police" } },
    { id = "military", label = "Army fatigues",
      items = { "Base.Trousers_CamoGreen", "Base.Jacket_ArmyCamoGreen", "Base.Hat_Army",
                "Base.Shoes_ArmyBoots" } },
    { id = "doctor", label = "Scrubs",
      items = { "Base.JacketLong_Doctor" } },
}

-- One item per clothing slot. The preset above stays the base outfit; a slot
-- choice replaces the preset's item for that slot and nothing else, so a person
-- can wear police trousers with a work shirt. Every fullType is a real item the
-- existing wear path already accepts; a slot with no choice means "from the
-- outfit", which is why an old roster needs no migration.
Creator.SLOTS = {
    { id = "head", label = "Hat", kind = "clothing", options = {
        { fullType = "Base.Hat_Police", label = "Police cap" },
        { fullType = "Base.Hat_Army", label = "Army helmet" },
    } },
    { id = "torso", label = "Coat", kind = "clothing", options = {
        { fullType = "Base.Shirt_FormalWhite", label = "White shirt" },
        { fullType = "Base.Shirt_Workman", label = "Work shirt" },
        { fullType = "Base.Shirt_PoliceBlue", label = "Police shirt" },
        { fullType = "Base.Jacket_ArmyCamoGreen", label = "Army jacket" },
        { fullType = "Base.JacketLong_Doctor", label = "Doctor's coat" },
    } },
    { id = "legs", label = "Trousers", kind = "clothing", options = {
        { fullType = "Base.Trousers_Denim", label = "Jeans" },
        { fullType = "Base.Trousers_Workman", label = "Work trousers" },
        { fullType = "Base.Trousers_Police", label = "Police trousers" },
        { fullType = "Base.Trousers_CamoGreen", label = "Camo trousers" },
    } },
    { id = "feet", label = "Shoes", kind = "clothing", options = {
        { fullType = "Base.Shoes_ArmyBoots", label = "Army boots" },
    } },
    -- A bag is worn, not carried in the hand: it goes through the same bridge
    -- call the randomizer already uses for a starter bag.
    { id = "backpack", label = "Backpack", kind = "bag", options = {
        { fullType = "Base.Bag_Schoolbag", label = "Schoolbag" },
        { fullType = "Base.Bag_DuffelBagTINT", label = "Duffel bag" },
    } },
    -- Two weapon slots, both honestly carried. The game has no dual wield, so the
    -- primary is the item the spawn hand-over carries and the secondary is a
    -- second item in the same inventory.
    { id = "primary", label = "Primary (carried)", kind = "weapon", options = {} },
    { id = "secondary", label = "Secondary (carried)", kind = "weapon", options = {} },
}

-- Themes the existing starting-gear owner already implements. Anything else is
-- an empty-pocket start, the same honest default an ordinary survivor gets.
Creator.KITS = {
    { id = "none", label = "Empty pockets" },
    { id = "police", label = "Police kit" },
    { id = "military", label = "Military kit" },
    { id = "fire_rescue", label = "Fire kit" },
}

-- A pack is the ordinary contents a person would carry, added to the real
-- inventory by the existing starting-gear owner. It is not a second kit: the kit
-- is a profession loadout, the pack is what is in the bag.
Creator.PACKS = {
    { id = "none", label = "Nothing extra", items = {} },
    { id = "meal", label = "Food and water",
      items = { "Base.Crisps", "Base.WaterBottle" } },
    { id = "medical", label = "Medical pouch",
      items = { "Base.Bandage", "Base.RippedSheets" } },
    { id = "tools", label = "Tool bag",
      items = { "Base.Hammer", "Base.Screwdriver" } },
}

Creator.WEAPONS = {
    { id = "none", label = "No weapon" },
    { id = "bat", label = "Baseball bat", fullType = "Base.BaseballBat" },
    { id = "knife", label = "Kitchen knife", fullType = "Base.KitchenKnife" },
    { id = "crowbar", label = "Crowbar", fullType = "Base.Crowbar" },
    { id = "axe", label = "Fire axe", fullType = "Base.FireAxe" },
    { id = "pistol", label = "Pistol", fullType = "Base.Pistol" },
    { id = "shotgun", label = "Shotgun", fullType = "Base.Shotgun" },
    { id = "rifle", label = "Hunting rifle", fullType = "Base.HuntingRifle" },
}

-- The presets above are the suggested carries, not the whole world. Every weapon
-- the script manager reports is appended once, with its fullType as the id, so
-- modded and vanilla guns and melee alike can be carried, and a roster row still
-- resolves by id. Nothing is invented: an entry exists because the engine
-- reported that item.
function Creator.weaponCatalogue()
    if Creator.weaponCatalogueReady then return Creator.WEAPONS end
    Creator.weaponCatalogueReady = true
    local seen = {}
    for _, entry in ipairs(Creator.WEAPONS) do
        if type(entry.fullType) == "string" then seen[entry.fullType] = true end
    end
    local added = {}
    pcall(function()
        local items = getScriptManager():getAllItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local fullType = nil
            if item.getFullName ~= nil then
                pcall(function() fullType = item:getFullName() end)
            end
            if type(fullType) == "string" and fullType ~= "" and not seen[fullType] then
                -- B42's ItemScript does not answer every one of these accessors.
                -- An absent method used to throw out of the pcall and abandon the
                -- whole catalogue, so the weapon list stayed empty and every click
                -- wrote a stack trace. Each accessor is asked for only when the
                -- item really has it.
                local isWeapon = false
                if item.getCategory ~= nil then
                    pcall(function()
                        local category = item:getCategory()
                        if category ~= nil and string.lower(tostring(category)) == "weapon" then
                            isWeapon = true
                        end
                    end)
                end
                if not isWeapon and item.getType ~= nil then
                    pcall(function()
                        isWeapon = string.lower(tostring(item:getType())) == "weapon"
                    end)
                end
                if not isWeapon and item.getTypeString ~= nil then
                    pcall(function()
                        isWeapon = string.lower(tostring(item:getTypeString())) == "weapon"
                    end)
                end
                if isWeapon then
                    local label = fullType
                    if item.getDisplayName ~= nil then
                        pcall(function()
                            label = tostring(item:getDisplayName() or fullType)
                        end)
                    end
                    seen[fullType] = true
                    added[#added + 1] = { id = fullType, label = label, fullType = fullType }
                end
            end
        end
    end)
    table.sort(added, function(a, b)
        local left, right = string.lower(a.label), string.lower(b.label)
        if left == right then return a.fullType < b.fullType end
        return left < right
    end)
    for _, entry in ipairs(added) do Creator.WEAPONS[#Creator.WEAPONS + 1] = entry end
    return Creator.WEAPONS
end

-- Real hair colours, as the vanilla creator presents them. A colour is a preset,
-- not a free picker: the saved value is the preset id, so a roster written today
-- still reads tomorrow.
Creator.HAIR_COLOURS = {
    { id = "black", label = "Black", rgb = { 0.05, 0.05, 0.05 } },
    { id = "darkbrown", label = "Dark brown", rgb = { 0.20, 0.12, 0.07 } },
    { id = "brown", label = "Brown", rgb = { 0.35, 0.22, 0.12 } },
    { id = "blonde", label = "Blonde", rgb = { 0.78, 0.66, 0.38 } },
    { id = "red", label = "Red", rgb = { 0.55, 0.20, 0.08 } },
    { id = "grey", label = "Grey", rgb = { 0.62, 0.62, 0.60 } },
    { id = "white", label = "White", rgb = { 0.88, 0.88, 0.86 } },
}

-- Real perk ids, applied through the character's own experience owner at spawn.
Creator.SKILLS = {
    "Aiming", "Reloading", "Axe", "Blunt", "SmallBlade", "LongBlade",
    "Maintenance", "Carpentry", "Cooking", "Farming", "FirstAid",
    "Electrical", "Mechanics", "Tailoring",
}
Creator.MAX_SKILL = 10

-- Only the catalogue's perks are readable from a file: a stray name in a
-- hand-edited or older roster is ignored instead of levelling nothing.
local SKILL_SET = {}
for _, perkId in ipairs(Creator.SKILLS) do SKILL_SET[perkId] = true end

Creator.PROFESSIONS = {
    { id = "base:unemployed", label = "Survivor" },
    { id = "base:policeofficer", label = "Police officer" },
    { id = "base:veteran", label = "Veteran" },
    { id = "base:doctor", label = "Doctor" },
    { id = "base:mechanics", label = "Mechanic" },
    { id = "base:farmer", label = "Farmer" },
    { id = "base:carpenter", label = "Carpenter" },
    { id = "base:chef", label = "Chef" },
}

local function factionTrim(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    return (text:gsub("[|\r\n]", ""))
end

local function factionIndexOf(list, id)
    for index, entry in ipairs(list or {}) do
        if entry.id == id then return index end
    end
    return nil
end

-- The default factions are code, not save data: an update adds one here and every
-- existing roster keeps reading, because a person names a faction by id. Each
-- default carries the loadout a person created in it starts with, drawn from the
-- same tables the roster stores, so a faction card states what it gives instead
-- of inventing a stat. Hostility, territory and membership in the running world
-- belong to the simulation; this is a grouping and a starting kit.
Creator.FACTIONS = {
    { id = "household", label = "Household", look = "casual", kit = "none",
      weapon = "none", pack = "meal" },
    { id = "police", label = "Police", look = "police", kit = "police",
      weapon = "pistol", pack = "meal" },
    { id = "military", label = "Military", look = "military", kit = "military",
      weapon = "rifle", pack = "medical" },
    { id = "fire_service", label = "Fire service", look = "fire",
      kit = "fire_rescue", weapon = "axe", pack = "medical" },
    { id = "looters", label = "Looters", look = "casual", kit = "none",
      weapon = "crowbar", pack = "tools" },
    { id = "robbers", label = "Robbers", look = "work", kit = "none",
      weapon = "bat", pack = "meal" },
}

local USER_FACTION_PREFIX = "user_"

-- Faction spelling rules. A label is the only thing a player types that reaches
-- both the sidebar and the faction name the world uses, so it is bounded and
-- stripped of the record separator like every other saved name.
function Creator.validateFactionName(value)
    local name = factionTrim(value)
    if #name < 2 then return nil, "That name is too short." end
    if #name > 32 then return nil, "That name is too long." end
    return name
end

local function factionSlug(text)
    local lower = string.lower(tostring(text or ""))
    lower = lower:gsub("[^a-z0-9]+", "_")
    lower = lower:gsub("^_+", "")
    lower = lower:gsub("_+$", "")
    return string.sub(lower, 1, 20)
end

-- User factions live under their own prefix, so a default added by a later
-- update can never collide with one a player made today.
function Creator.newFactionId(label, defs)
    local stem = factionSlug(label)
    if stem == "" then stem = "group" end
    local base = USER_FACTION_PREFIX .. stem
    local id, counter = base, 1
    while Creator.factionIndexIn(defs, id) ~= nil do
        counter = counter + 1
        id = base .. "_" .. tostring(counter)
    end
    return id
end

-- One lookup for defaults and saved definitions together. A person stores an id;
-- an id that no longer exists resolves to the first default rather than losing
-- the person.
function Creator.factionIndexIn(defs, id)
    if type(id) ~= "string" or id == "" then return nil end
    for _, entry in ipairs(Creator.FACTIONS) do
        if entry.id == id then return entry end
    end
    for _, entry in ipairs(type(defs) == "table" and defs or {}) do
        if type(entry) == "table" and entry.id == id then return entry end
    end
    return nil
end

function Creator.factionIndex(id, defs)
    return Creator.factionIndexIn(defs, id)
end

-- Defaults in code order, then the player's own in file order. Nothing appends to
-- Creator.FACTIONS: a saved faction used to be merged into the default table, and
-- a roster that stored a position then moved under it.
function Creator.allFactions(defs)
    local merged = {}
    for _, entry in ipairs(Creator.FACTIONS) do merged[#merged + 1] = entry end
    for _, entry in ipairs(type(defs) == "table" and defs or {}) do
        if type(entry) == "table" and type(entry.id) == "string" and entry.id ~= ""
            and Creator.factionIndexIn(nil, entry.id) == nil then
            merged[#merged + 1] = entry
        end
    end
    return merged
end

function Creator.defaultFactionId()
    return Creator.FACTIONS[1].id
end

function Creator.factionLabel(id, defs)
    local entry = Creator.factionIndexIn(defs, id)
    if entry ~= nil then return entry.label end
    return Creator.FACTIONS[1].label
end

-- The faction a person belongs to: their own choice, else the group's. The group
-- also keeps a legacy index so a format-2 file still reads.
function Creator.personFactionId(person, group)
    if type(person) == "table" and type(person.faction) == "string"
        and person.faction ~= "" then
        return person.faction
    end
    if type(group) == "table" then
        if type(group.factionId) == "string" and group.factionId ~= "" then
            return group.factionId
        end
        local legacy = Creator.FACTIONS[Creator.clamp(group.faction, #Creator.FACTIONS)]
        if legacy ~= nil then return legacy.id end
    end
    return Creator.defaultFactionId()
end

-- An authored outfit is only applied when this build really has every item it
-- names. A later game build that drops a garment falls back to the work outfit
-- once and says why, instead of dressing nobody and saying nothing.
function Creator.resolveLook(lookId)
    if type(lookId) ~= "string" then return "work" end
    local index = factionIndexOf(Creator.LOOKS, lookId)
    if index == nil then return "work" end
    local manager = nil
    pcall(function() manager = getScriptManager() end)
    if manager == nil or manager.FindItem == nil then return lookId end
    for _, fullType in ipairs(Creator.LOOKS[index].items) do
        local found = nil
        pcall(function() found = manager:FindItem(fullType) end)
        if found == nil then
            if not Creator.lookFallbackLogged then
                Creator.lookFallbackLogged = true
                print("[KnoxSurvivors][Creator] outfit '" .. lookId
                    .. "' needs an item this build does not have: " .. fullType)
            end
            return "work"
        end
    end
    return lookId
end

-- What a new person in this faction starts as, as a draft the existing add path
-- already accepts. A user faction starts from the household defaults until the
-- player changes them.
function Creator.draftForFaction(factionId, defs)
    local entry = Creator.factionIndexIn(defs, factionId) or Creator.FACTIONS[1]
    local draft = Creator.newDraft()
    draft.look = factionIndexOf(Creator.LOOKS, Creator.resolveLook(entry.look)) or 1
    draft.kit = factionIndexOf(Creator.KITS, entry.kit) or 1
    draft.weapon = factionIndexOf(Creator.WEAPONS, entry.weapon) or 1
    draft.pack = factionIndexOf(Creator.PACKS, entry.pack) or 1
    draft.profession = 1
    draft.faction = entry.id
    return draft
end

local function trim(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    -- The roster is one record per line; a separator inside a name would
    -- silently split one person into two.
    text = text:gsub("[|\r\n]", "")
    return text
end

local function indexOf(list, id)
    for index, entry in ipairs(list) do
        if entry.id == id then return index end
    end
    return nil
end

function Creator.indexOf(list, id)
    return indexOf(list, id)
end

-- Wrap without relying on the sign of %. Kahlua's remainder is not Lua's floor
-- modulo for a negative step, so the position is placed with an explicit floor
-- subtraction instead.
function Creator.cycle(index, count, step)
    local total = math.max(1, tonumber(count) or 1)
    local current = math.floor(tonumber(index) or 1)
    local position = current - 1 + (tonumber(step) or 1)
    position = position - math.floor(position / total) * total
    return position + 1
end

-- An index is a choice, a cycle is a step. Reading a choice must never advance
-- it, so every catalogue lookup clamps instead of cycling.
function Creator.clamp(index, count)
    local total = math.max(1, tonumber(count) or 1)
    local value = math.floor(tonumber(index) or 1)
    if value < 1 then return 1 end
    if value > total then return total end
    return value
end

function Creator.label(list, index)
    local entry = list[Creator.clamp(index, #list)]
    return entry ~= nil and entry.label or "?"
end

function Creator.newDraft()
    return { name = "", look = 1, kit = 1, weapon = 1, profession = 1, pack = 1,
        female = false, hair = "", beard = "", hairColour = "brown", skills = {},
        slots = {} }
end

function Creator.slotById(slotId)
    for _, slot in ipairs(Creator.SLOTS) do
        if slot.id == slotId then return slot end
    end
    return nil
end

-- The chosen option for one slot, or nil for "from the outfit". A stored value
-- that is not in that slot's own catalogue is nothing, so a hand-edited roster
-- cannot dress a person in an item the catalogue never offered.
-- The catalogue is whatever the engine has: a slot owns its four presets plus
-- every clothing item whose body location belongs to it, so a modded jacket is
-- offered exactly like a vanilla one. Built once per session, sorted by label.
local SLOT_LOCATIONS = {
    torso = { "torso", "base:torso" },
    legs = { "legs", "pants" },
    head = { "hat", "head" },
    feet = { "feet", "shoes", "boots" },
    backpack = { "back" },
}
local catalogueCache = {}

function Creator.slotCatalogue(slotId)
    local slot = Creator.slotById(slotId)
    if slot == nil then return {} end
    -- A weapon slot offers the engine's own weapon list, with the entries that
    -- name a real item only: the "no weapon" preset is a choice, not an item.
    if slot.kind == "weapon" then
        local entries = {}
        for _, entry in ipairs(Creator.weaponCatalogue()) do
            if type(entry.fullType) == "string" and entry.fullType ~= "" then
                entries[#entries + 1] = { fullType = entry.fullType, label = entry.label }
            end
        end
        return entries
    end
    if catalogueCache[slotId] ~= nil then return catalogueCache[slotId] end
    local entries, seen = {}, {}
    for _, option in ipairs(slot.options) do
        entries[#entries + 1] = { fullType = option.fullType, label = option.label }
        seen[option.fullType] = true
    end
    local ok, allItems = pcall(function() return getScriptManager():getAllItems() end)
    if ok and allItems ~= nil and allItems.size ~= nil then
        local sizeOk, size = pcall(function() return allItems:size() end)
        if sizeOk and tonumber(size) ~= nil then
            local words = SLOT_LOCATIONS[slotId] or {}
            for index = 0, tonumber(size) - 1 do
                local item = nil
                pcall(function() item = allItems:get(index) end)
                if item ~= nil then
                    local fullType, location = nil, nil
                    pcall(function() fullType = item:getFullName() end)
                    pcall(function() location = item:getBodyLocation() end)
                    local matches = false
                    if type(location) == "string" then
                        local lower = string.lower(location)
                        for _, word in ipairs(words) do
                            if string.find(lower, word, 1, true) ~= nil then matches = true; break end
                        end
                    end
                    if matches and type(fullType) == "string" and fullType ~= ""
                        and not seen[fullType] then
                        local label = fullType
                        pcall(function() label = tostring(item:getDisplayName() or fullType) end)
                        seen[fullType] = true
                        entries[#entries + 1] = { fullType = fullType, label = label }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        local left, right = string.lower(a.label), string.lower(b.label)
        if left == right then return a.fullType < b.fullType end
        return left < right
    end)
    catalogueCache[slotId] = entries
    return entries
end

function Creator.slotOption(slotId, fullType)
    local slot = Creator.slotById(slotId)
    if slot == nil or type(fullType) ~= "string" then return nil end
    for _, option in ipairs(Creator.slotCatalogue(slotId)) do
        if option.fullType == fullType then return option end
    end
    return nil
end

function Creator.slotChoice(slotId, slots)
    if type(slots) ~= "table" then return nil end
    return Creator.slotOption(slotId, slots[slotId])
end

-- Outfit first, then each real item, then back to the outfit. One step changes
-- exactly one slot.
function Creator.cycleSlot(slots, slotId)
    local slot = Creator.slotById(slotId)
    if slot == nil or type(slots) ~= "table" then return nil end
    local catalogue = Creator.slotCatalogue(slotId)
    local current, nextIndex = slots[slotId], 1
    if type(current) == "string" then
        for index, option in ipairs(catalogue) do
            if option.fullType == current and index < #catalogue then
                nextIndex = index + 1
            elseif option.fullType == current then
                nextIndex = #catalogue + 1
            end
        end
    end
    if nextIndex > #catalogue then
        slots[slotId] = nil
        return nil
    end
    slots[slotId] = catalogue[nextIndex].fullType
    return slots[slotId]
end

function Creator.encodeSlots(slots)
    if type(slots) ~= "table" then return "" end
    local parts = {}
    for _, slot in ipairs(Creator.SLOTS) do
        local fullType = slots[slot.id]
        if Creator.slotOption(slot.id, fullType) ~= nil then
            parts[#parts + 1] = slot.id .. ":" .. fullType
        end
    end
    return table.concat(parts, ";")
end

function Creator.decodeSlots(text)
    local slots = {}
    if type(text) ~= "string" then return slots end
    for pair in text:gmatch("[^;]+") do
        local slotId, fullType = pair:match("^([%a_]+):([%w_%.]+)$")
        if slotId ~= nil and Creator.slotOption(slotId, fullType) ~= nil then
            slots[slotId] = fullType
        end
    end
    return slots
end

function Creator.colourIndexOf(id)
    local index = indexOf(Creator.HAIR_COLOURS, tostring(id))
    return index or indexOf(Creator.HAIR_COLOURS, "brown")
end

function Creator.colourOf(id)
    return Creator.HAIR_COLOURS[Creator.colourIndexOf(id)].rgb
end

function Creator.colourLabel(id)
    return Creator.HAIR_COLOURS[Creator.colourIndexOf(id)].label
end

function Creator.skillLevel(skills, perkId)
    local value = type(skills) == "table" and tonumber(skills[perkId]) or nil
    if value == nil then return 0 end
    value = math.floor(value)
    if value < 0 then return 0 end
    if value > Creator.MAX_SKILL then return Creator.MAX_SKILL end
    return value
end

function Creator.cycleSkill(skills, perkId)
    if type(skills) ~= "table" then return 0 end
    local next = (Creator.skillLevel(skills, perkId) + 1) % (Creator.MAX_SKILL + 1)
    skills[perkId] = next
    return next
end

function Creator.encodeSkills(skills)
    local parts = {}
    for _, perkId in ipairs(Creator.SKILLS) do
        local level = Creator.skillLevel(skills, perkId)
        if level > 0 then parts[#parts + 1] = perkId .. "=" .. tostring(level) end
    end
    return table.concat(parts, ";")
end

function Creator.decodeSkills(text)
    local skills = {}
    if type(text) ~= "string" then return skills end
    for pair in text:gmatch("[^;]+") do
        local perkId, level = pair:match("^([%w_]+)=(%d+)$")
        if perkId ~= nil and SKILL_SET[perkId] == true then
            skills[perkId] = math.min(Creator.MAX_SKILL, tonumber(level))
        end
    end
    return skills
end

-- The roster is a user file, so it outlives a mod update: nothing here writes
-- inside the mod folder, and a record read from an older format keeps its name,
-- look and gear while the new appearance fields fall back to their defaults.
function Creator.resetRoster(roster)
    if type(roster) ~= "table" then return false, "no_roster" end
    while #roster > 0 do table.remove(roster) end
    return true, "empty"
end

function Creator.removeAt(roster, index)
    if type(roster) ~= "table" then return false, "no_roster" end
    index = tonumber(index)
    if index == nil or index < 1 or index > #roster then return false, "no_such_person" end
    return true, table.remove(roster, index)
end

function Creator.setFactionAt(roster, index, factionId, defs)
    if type(roster) ~= "table" then return false, "no_roster" end
    index = tonumber(index)
    if index == nil or index < 1 or index > #roster then return false, "no_such_person" end
    if Creator.factionIndexIn(defs, tostring(factionId)) == nil then
        return false, "no_such_faction"
    end
    roster[index].faction = tostring(factionId)
    return true, roster[index]
end

-- The sidebar and the card grid read the same three rules: who belongs where, in
-- what order, and with what count. They are pure so the shape of the list is
-- provable without a screen.
function Creator.sortByName(roster)
    local list = {}
    for index, person in ipairs(type(roster) == "table" and roster or {}) do
        if type(person) == "table" then
            list[#list + 1] = { index = index, person = person }
        end
    end
    table.sort(list, function(a, b)
        local left = string.lower(tostring(a.person.name or ""))
        local right = string.lower(tostring(b.person.name or ""))
        if left == right then return a.index < b.index end
        return left < right
    end)
    return list
end

function Creator.peopleByFaction(roster, group, factionId)
    local list = {}
    for _, entry in ipairs(Creator.sortByName(roster)) do
        if factionId == nil or Creator.personFactionId(entry.person, group) == factionId then
            list[#list + 1] = entry
        end
    end
    return list
end

function Creator.factionCounts(roster, group, defs)
    local counts = {}
    for _, entry in ipairs(Creator.allFactions(defs)) do counts[entry.id] = 0 end
    for _, person in ipairs(type(roster) == "table" and roster or {}) do
        local id = Creator.personFactionId(person, group)
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

-- One row list for the whole sidebar: every faction, then its people by name,
-- then the row that makes a new one. The card grid filters on the selected
-- faction; the sidebar never hides a name, so a person can always be found.
function Creator.railRows(roster, group, defs, selectedFactionId)
    local rows = {}
    local total = #(type(roster) == "table" and roster or {})
    rows[#rows + 1] = { kind = "all", label = "All factions", count = total,
        selected = selectedFactionId == nil }
    local counts = Creator.factionCounts(roster, group, defs)
    for _, faction in ipairs(Creator.allFactions(defs)) do
        rows[#rows + 1] = { kind = "faction", id = faction.id, label = faction.label,
            count = counts[faction.id] or 0, selected = selectedFactionId == faction.id }
        for _, entry in ipairs(Creator.peopleByFaction(roster, group, faction.id)) do
            rows[#rows + 1] = { kind = "person", id = faction.id, index = entry.index,
                label = tostring(entry.person.name), indent = true }
        end
    end
    rows[#rows + 1] = { kind = "new", label = "+ New faction" }
    return rows
end

-- Card geometry is arithmetic, not a screenshot: the grid wraps by available
-- width, the scroll offset is clamped to the content, and every rect is returned
-- so a fixture can check that no card overlaps another or leaves the area.
Creator.CARD_WIDTH = 170
Creator.CARD_HEIGHT = 210
Creator.CARD_GAP = 10

function Creator.cardGrid(count, x, y, width, height, scroll)
    local cardW, cardH, gap = Creator.CARD_WIDTH, Creator.CARD_HEIGHT, Creator.CARD_GAP
    local columns = math.max(1, math.floor(((tonumber(width) or 0) + gap) / (cardW + gap)))
    local rows = math.ceil(math.max(0, tonumber(count) or 0) / columns)
    local content = rows > 0 and (rows * (cardH + gap) - gap) or 0
    local maxScroll = math.max(0, content - (tonumber(height) or 0))
    local offset = math.max(0, math.min(tonumber(scroll) or 0, maxScroll))
    local cards = {}
    for index = 1, math.max(0, tonumber(count) or 0) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        cards[#cards + 1] = { x = (tonumber(x) or 0) + column * (cardW + gap),
            y = (tonumber(y) or 0) + row * (cardH + gap) - offset,
            width = cardW, height = cardH, index = index }
    end
    return { cards = cards, columns = columns, contentHeight = content,
        maxScroll = maxScroll, scroll = offset }
end

-- Faction editing is decided here, not in the panel: a built-in keeps its name,
-- a player faction can be renamed, and one that still holds people cannot vanish
-- from under them.
function Creator.addFaction(defs, label)
    if type(defs) ~= "table" then return false, "no_faction_list" end
    local name, err = Creator.validateFactionName(label)
    if name == nil then return false, err end
    for _, entry in ipairs(Creator.allFactions(defs)) do
        if string.lower(entry.label) == string.lower(name) then
            return false, "That faction already exists."
        end
    end
    local entry = { id = Creator.newFactionId(name, defs), label = name, user = true,
        look = "casual", kit = "none", weapon = "none", pack = "meal" }
    defs[#defs + 1] = entry
    return true, entry
end

function Creator.renameFaction(defs, id, label)
    local entry = nil
    for _, candidate in ipairs(type(defs) == "table" and defs or {}) do
        if candidate.id == id then entry = candidate end
    end
    if entry == nil then return false, "A built-in faction keeps its name." end
    local name, err = Creator.validateFactionName(label)
    if name == nil then return false, err end
    for _, other in ipairs(Creator.allFactions(defs)) do
        if other.id ~= id and string.lower(other.label) == string.lower(name) then
            return false, "Another faction already has that name."
        end
    end
    entry.label = name
    return true, entry
end

function Creator.deleteFaction(defs, id, roster, group)
    if type(defs) ~= "table" then return false, "no_faction_list" end
    if Creator.factionIndexIn(defs, id) == nil then return false, "No such faction." end
    if Creator.factionIndexIn(nil, id) ~= nil then
        return false, "A built-in faction cannot be deleted."
    end
    for _, person in ipairs(type(roster) == "table" and roster or {}) do
        if Creator.personFactionId(person, group) == id then
            return false, "Move its people to another faction first."
        end
    end
    for index = #defs, 1, -1 do
        if defs[index].id == id then table.remove(defs, index) end
    end
    return true, id
end

function Creator.factionPresetItems(factionId, defs)
    local entry = Creator.factionIndexIn(defs, factionId) or Creator.FACTIONS[1]
    local items = {}
    local look = Creator.LOOKS[factionIndexOf(Creator.LOOKS,
        Creator.resolveLook(entry.look)) or 1]
    for _, fullType in ipairs(look ~= nil and look.items or {}) do
        items[#items + 1] = fullType
    end
    local weapon = Creator.weaponItem(entry.weapon)
    if weapon ~= nil then items[#items + 1] = weapon end
    for _, fullType in ipairs(Creator.packItems(entry.pack)) do
        items[#items + 1] = fullType
    end
    return items
end

-- A person needs a name a human can read and a list with room in it. Every other
-- field falls back to its first entry rather than refusing the person.
function Creator.draftValid(draft, rosterSize)
    if type(draft) ~= "table" then return false, "no_draft" end
    local name = trim(draft.name)
    if #name < 2 then return false, "Name is too short." end
    if #name > Creator.MAX_NAME then return false, "Name is too long." end
    if (tonumber(rosterSize) or 0) >= Creator.MAX_PEOPLE then
        return false, "The list is full."
    end
    return true, name
end

-- One label, never a wrapped list. Three names fit the row; beyond that the
-- count is the information, so the surface cannot clip at Small font.
-- Promotion's one decision about a player-supplied name: take it when it is
-- well-formed and no faction already holds it, otherwise keep the generated one.
-- Pure, so both branches are provable without a save.
function Creator.chooseFactionName(generated, requested, taken)
    if type(requested) ~= "string" or requested == "" or taken == true then
        return generated
    end
    return requested
end

function Creator.summaryText(roster)
    local count, names = 0, {}
    for _, person in ipairs(type(roster) == "table" and roster or {}) do
        count = count + 1
        if count <= 3 then names[#names + 1] = tostring(person.name) end
    end
    if count == 0 then return "Nobody yet. Name one person, then add them." end
    local text = tostring(count) .. " ready: " .. table.concat(names, ", ")
    if count > 3 then text = text .. " and " .. tostring(count - 3) .. " more" end
    return text
end

function Creator.add(roster, draft)
    if type(roster) ~= "table" then return false, "no_roster" end
    local ok, name = Creator.draftValid(draft, #roster)
    if not ok then return false, name end
    -- Two people with one name make every later row and line ambiguous, so the
    -- duplicate is refused where the person is added rather than renamed later.
    local lower = string.lower(name)
    for _, person in ipairs(roster) do
        if type(person) == "table" and type(person.name) == "string"
            and string.lower(person.name) == lower then
            return false, "Somebody here already has that name."
        end
    end
    local look = Creator.LOOKS[Creator.clamp(draft.look, #Creator.LOOKS)]
    local kit = Creator.KITS[Creator.clamp(draft.kit, #Creator.KITS)]
    local weapon = Creator.WEAPONS[Creator.clamp(draft.weapon, #Creator.WEAPONS)]
    local profession = Creator.PROFESSIONS[
        Creator.clamp(draft.profession, #Creator.PROFESSIONS)]
    local pack = Creator.PACKS[Creator.clamp(draft.pack, #Creator.PACKS)]
    local person = {
        name = name,
        profession = profession.id,
        look = look.id,
        kit = kit.id,
        weapon = weapon.fullType,
        weaponId = weapon.id,
        pack = pack.id,
        spawned = false,
        female = draft.female == true,
        hair = type(draft.hair) == "string" and draft.hair or "",
        beard = type(draft.beard) == "string" and draft.beard or "",
        hairColour = Creator.HAIR_COLOURS[Creator.colourIndexOf(draft.hairColour)].id,
        skills = {},
        slots = Creator.decodeSlots(Creator.encodeSlots(draft.slots)),
        -- The faction a person was made in, by id: the card and the sidebar
        -- both read this field, and a group change never rewrites it.
        faction = type(draft.faction) == "string" and draft.faction or nil,
    }
    for _, perkId in ipairs(Creator.SKILLS) do
        local level = Creator.skillLevel(draft.skills, perkId)
        if level > 0 then person.skills[perkId] = level end
    end
    roster[#roster + 1] = person
    return true, person
end

function Creator.removeLast(roster)
    if type(roster) ~= "table" or #roster == 0 then return false end
    return true, table.remove(roster)
end

function Creator.lookItems(id)
    local index = indexOf(Creator.LOOKS, tostring(id))
    if index == nil then return {} end
    local items = {}
    for _, fullType in ipairs(Creator.LOOKS[index].items) do items[#items + 1] = fullType end
    return items
end

-- The preset with the chosen slots swapped in. A slot override removes whatever
-- the preset wore in that same slot, then adds the chosen item, so a person can
-- never end up wearing two shirts because both were applied.
-- Only clothing takes part in the outfit merge. A bag is worn by its own call
-- and a weapon is carried, so neither can be handed to the dressing path that
-- would refuse it.
function Creator.lookItemsWithSlots(lookId, slots)
    local items = Creator.lookItems(lookId)
    if type(slots) ~= "table" then return items end
    local clothing = {}
    for _, slot in ipairs(Creator.SLOTS) do
        if slot.kind == nil or slot.kind == "clothing" then
            clothing[#clothing + 1] = slot
        end
    end
    local kept = {}
    for _, fullType in ipairs(items) do
        local replaced = false
        for _, slot in ipairs(clothing) do
            if Creator.slotOption(slot.id, fullType) ~= nil
                and Creator.slotOption(slot.id, slots[slot.id]) ~= nil then
                replaced = true
                break
            end
        end
        if not replaced then kept[#kept + 1] = fullType end
    end
    for _, slot in ipairs(clothing) do
        local chosen = Creator.slotOption(slot.id, slots[slot.id])
        if chosen ~= nil then kept[#kept + 1] = chosen.fullType end
    end
    return kept
end

-- The bag and the two carried weapons, read from the same slot table the roster
-- stores. One reader, so the spawn path cannot disagree with the card.
function Creator.bagFromSlots(slots)
    return Creator.slotChoice("backpack", slots)
end

function Creator.carriedFromSlots(slots)
    local primary = Creator.slotChoice("primary", slots)
    local secondary = Creator.slotChoice("secondary", slots)
    return primary ~= nil and primary.fullType or nil,
        secondary ~= nil and secondary.fullType or nil
end

-- One hand-over table: everything the body needs, built from the roster person
-- in one place instead of re-listed at the spawn site. The spawn site used to
-- list its own fields and dropped hair, beard, colour, sex, skills and clothing
-- slots, so the card promised a face and a kit that never reached the body.
function Creator.recordFor(person, group)
    if type(person) ~= "table" then return nil end
    group = type(group) == "table" and group or {}
    -- The person's own faction wins; the group's id is the fallback, and the old
    -- numeric position is the last one.
    local factionId = Creator.personFactionId(person, group)
    local slots = Creator.decodeSlots(Creator.encodeSlots(person.slots))
    local primary = Creator.slotChoice("primary", slots)
    local bag = Creator.slotChoice("backpack", slots)
    return {
        name = person.name,
        look = person.look,
        kit = person.kit,
        -- The primary slot is the carried weapon; the "Carries" row stays the
        -- preset that filled these slots for a new person.
        weapon = primary ~= nil and primary.fullType or person.weapon,
        pack = person.pack,
        faction = factionId,
        bag = bag ~= nil and bag.fullType or nil,
        groupName = group.name,
        hair = person.hair,
        beard = person.beard,
        hairColour = person.hairColour,
        female = person.female == true,
        skills = Creator.encodeSkills(person.skills),
        slots = Creator.encodeSlots(person.slots),
    }
end

-- What the appearance owner applies for a saved person: the preset id and the
-- encoded slot field, read through the same two functions the roster uses.
function Creator.lookItemsFromRecord(record)
    if type(record) ~= "table" then return {} end
    return Creator.lookItemsWithSlots(record.look, Creator.decodeSlots(record.slots))
end

-- The name a created group asked for. It becomes a faction's saved name only if
-- it survives the same bounds every other player-typed name does, so a roster
-- file cannot inject a blank, an overlong label or a separator into a faction.
function Creator.requestedFactionName(value)
    local name = trim(value)
    if #name < 2 or #name > 32 then return nil end
    if name:find("_") ~= nil then return nil end
    return name
end

function Creator.packItems(id)
    local index = indexOf(Creator.PACKS, tostring(id))
    if index == nil then return {} end
    local items = {}
    for _, fullType in ipairs(Creator.PACKS[index].items) do items[#items + 1] = fullType end
    return items
end

function Creator.weaponItem(id)
    local index = indexOf(Creator.WEAPONS, tostring(id))
    if index == nil then return nil end
    local entry = Creator.WEAPONS[index]
    if type(entry.fullType) == "string" then return entry.fullType end
    if entry.id ~= nil and entry.id ~= "none" then return entry.id end
    return nil
end

-- One line per person. Unknown ids and unreadable fields fall back to a default
-- rather than dropping the person: an unparsed roster is a lost roster, while a
-- wrong outfit is a defect the player can see and change.
-- Format 2 adds appearance and skills. A format-1 file still reads: the new
-- fields are simply absent, and each falls back to its default.
local function encodeText(value, maximum)
    local text = trim(value)
    text = string.sub(text, 1, maximum or 32)
    return text
end

function Creator.encode(roster, group)
    -- Format 3 adds the group faction as an id and the player's own faction
    -- definitions. Format 2 files are still read, and anything this version does
    -- not understand is written back unchanged rather than dropped.
    local lines = { "knox-creator 3" }
    group = type(group) == "table" and group or {}
    local factionId = group.factionId
    if Creator.factionIndexIn(group.defs, factionId) == nil then
        -- A caller that still hands over the old numeric position gets the
        -- faction that position means today, so nothing silently moves to
        -- the first default.
        local legacy = Creator.FACTIONS[Creator.clamp(group.faction,
            #Creator.FACTIONS)]
        factionId = legacy ~= nil and legacy.id or Creator.defaultFactionId()
    end
    lines[#lines + 1] = "group|" .. trim(group.name)
    lines[#lines + 1] = "groupfaction|" .. factionId
    for _, entry in ipairs(type(group.defs) == "table" and group.defs or {}) do
        local label = Creator.validateFactionName(entry.label)
        if label ~= nil and type(entry.id) == "string" and entry.id ~= "" then
            lines[#lines + 1] = "def|" .. entry.id .. "|" .. label
        end
    end
    for _, person in ipairs(roster or {}) do
        if type(person) == "table" then
            local look = indexOf(Creator.LOOKS, tostring(person.look)) or 1
            local kit = indexOf(Creator.KITS, tostring(person.kit)) or 1
            local weapon = indexOf(Creator.WEAPONS, tostring(person.weaponId)) or 1
            local profession = indexOf(Creator.PROFESSIONS, tostring(person.profession)) or 1
            local pack = indexOf(Creator.PACKS, tostring(person.pack)) or 1
            lines[#lines + 1] = table.concat({
                "p", trim(person.name),
                Creator.LOOKS[look].id, Creator.KITS[kit].id,
                Creator.WEAPONS[weapon].id, Creator.PROFESSIONS[profession].id,
                Creator.PACKS[pack].id,
                person.spawned and "1" or "0",
                person.female and "1" or "0",
                encodeText(person.hair, 32),
                encodeText(person.beard, 32),
                Creator.HAIR_COLOURS[Creator.colourIndexOf(person.hairColour)].id,
                Creator.encodeSkills(person.skills),
                -- A per-person faction is an id, so an update that adds a
                -- default cannot move it. The group's id is written for anyone
                -- who never chose one.
                encodeText(Creator.personFactionId(person, group), 40),
                -- Field fifteen: the per-slot clothing choices. Absent in every
                -- older record, which then reads as "all from the outfit".
                Creator.encodeSlots(person.slots),
            }, "|")
        end
    end
    for _, kept in ipairs(type(group.extras) == "table" and group.extras or {}) do
        lines[#lines + 1] = tostring(kept)
    end
    return table.concat(lines, "\n") .. "\n"
end

function Creator.newGroup()
    return { name = "", faction = 1, factionId = Creator.defaultFactionId(),
        defs = {}, extras = {} }
end

function Creator.decode(text)
    local roster = {}
    local group = Creator.newGroup()
    local skipped = 0
    if type(text) ~= "string" then return roster, group, skipped end
    for line in text:gmatch("[^\r\n]+") do
        local fields = {}
        local cursor = 1
        while cursor <= #line do
            local bar = string.find(line, "|", cursor, true)
            if bar == nil then
                fields[#fields + 1] = string.sub(line, cursor)
                break
            end
            fields[#fields + 1] = string.sub(line, cursor, bar - 1)
            cursor = bar + 1
        end
        local kind = tostring(fields[1] or "")
        if string.sub(kind, 1, 12) == "knox-creator" then
            -- The version line names the format; it is not a record.
        elseif kind == "group" then
            group.name = trim(fields[2])
        elseif kind == "groupfaction" then
            local id = tostring(fields[2] or "")
            if id ~= "" then group.factionId = id end
        elseif kind == "faction" then
            -- Format 2 wrote an id, or the position it used to sit at. An id is
            -- read first so an update that adds a default cannot move a group.
            local raw = tostring(fields[2] or "")
            local byId = Creator.factionIndexIn(group.defs, raw)
            if byId ~= nil then
                group.factionId = byId.id
            else
                local position = tonumber(raw)
                if position ~= nil then
                    local legacy = Creator.FACTIONS[
                        Creator.clamp(position, #Creator.FACTIONS)]
                    group.factionId = legacy ~= nil and legacy.id
                        or Creator.defaultFactionId()
                end
            end
        elseif kind == "def" then
            local id = tostring(fields[2] or "")
            local label = Creator.validateFactionName(fields[3])
            if id ~= "" and label ~= nil then
                group.defs[#group.defs + 1] = { id = id, label = label, user = true,
                    look = "casual", kit = "none", weapon = "none", pack = "meal" }
            else
                group.extras[#group.extras + 1] = line
            end
        elseif kind == "p" and #roster < Creator.MAX_PEOPLE then
            local name = trim(fields[2])
            if #name >= 2 and #name <= Creator.MAX_NAME then
                local weapon = Creator.WEAPONS[indexOf(Creator.WEAPONS,
                    tostring(fields[5])) or 1]
                local packId = #fields >= 8 and fields[7] or "none"
                local spawnedField = #fields >= 8 and fields[8] or fields[7]
                roster[#roster + 1] = {
                    name = name,
                    look = Creator.LOOKS[indexOf(Creator.LOOKS, tostring(fields[3])) or 1].id,
                    kit = Creator.KITS[indexOf(Creator.KITS, tostring(fields[4])) or 1].id,
                    weapon = weapon.fullType,
                    weaponId = weapon.id,
                    profession = Creator.PROFESSIONS[indexOf(Creator.PROFESSIONS,
                        tostring(fields[6])) or 1].id,
                    pack = Creator.PACKS[indexOf(Creator.PACKS, tostring(packId)) or 1].id,
                    spawned = spawnedField == "1",
                    -- Absent in a format-1 record, so an old roster keeps its
                    -- person and gains a default face rather than being lost.
                    female = #fields >= 9 and fields[9] == "1" or false,
                    hair = #fields >= 10 and tostring(fields[10]) or "",
                    beard = #fields >= 11 and tostring(fields[11]) or "",
                    hairColour = Creator.HAIR_COLOURS[Creator.colourIndexOf(
                        #fields >= 12 and fields[12] or "brown")].id,
                    skills = Creator.decodeSkills(#fields >= 13 and fields[13] or ""),
                    -- Only a faction this install knows becomes membership: a
                    -- hand-edited or newer id is ignored, because the faction
                    -- decides who is allied. A user definition written earlier in
                    -- the same file is known by now.
                    faction = (#fields >= 14 and fields[14] ~= ""
                        and Creator.factionIndexIn(group.defs, tostring(fields[14]))
                        ~= nil) and tostring(fields[14]) or nil,
                    slots = Creator.decodeSlots(#fields >= 15 and fields[15] or ""),
                }
            else
                -- An unreadable record is counted, not dropped in silence: the
                -- panel tells the player how many saved people were lost.
                skipped = skipped + 1
            end
        else
            -- A record written by a newer version is kept verbatim, so opening an
            -- older install does not silently delete somebody's faction.
            group.extras[#group.extras + 1] = line
        end
    end
    -- An id that no longer exists (a default removed by a later update, or a
    -- hand-edited line) falls back to the first default rather than losing the
    -- group.
    if Creator.factionIndexIn(group.defs, group.factionId) == nil then
        group.factionId = Creator.defaultFactionId()
    end
    group.faction = indexOf(Creator.FACTIONS, group.factionId) or 1
    return roster, group, skipped
end


function Creator.save(roster, group)
    -- B42's getFileWriter is (name, createIfMissing, append); the two-argument
    -- form threw "expected 3 arguments, got 2" and the roster never saved, so a
    -- created survivor was allocated again on every start.
    local ok, writer = pcall(function() return getFileWriter(Creator.FILE, true, false) end)
    if not ok or writer == nil then return false, "no_file_writer" end
    local wrote = pcall(function()
        writer:write(Creator.encode(roster, group))
        writer:close()
    end)
    if not wrote then return false, "write_failed" end
    return true, "saved"
end

function Creator.load()
    local ok, reader = pcall(function() return getFileReader(Creator.FILE, false) end)
    if not ok or reader == nil then return {}, Creator.newGroup(), 0 end
    local text = {}
    pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            text[#text + 1] = line
        end
        reader:close()
    end)
    return Creator.decode(table.concat(text, "\n"))
end

-- The roster is made at the main menu, before a save exists, so it waits in its
-- own file. Each unspawned person is allocated at the player's square through the
-- population owner; a refusal stays unspawned for the next start rather than
-- being marked done.
function Creator.spawnPending()
    local player = getPlayer ~= nil and getPlayer() or nil
    local square = player ~= nil and player:getSquare() or nil
    if square == nil then return 0, "no_player_square" end
    local roster, group = Creator.load()
    local spawned, degraded = {}, 0
    -- The roster stores the faction as an index; the record owner stores ids, so
    -- the index is resolved here rather than handed over as a number it drops.
    local factionId = (Creator.FACTIONS[Creator.clamp(group.faction, #Creator.FACTIONS)] or {}).id
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    for index, person in ipairs(roster) do
        if person.spawned ~= true then
            local id = KnoxPersistence.allocateWorldSurvivor({
                x = square:getX() + ((index % 3) - 1) * 2,
                y = square:getY() + (math.floor((index - 1) / 3) % 3) * 2,
                z = square:getZ(),
                source = "creator",
                region = "Created",
                professionCandidates = { person.profession },
            }, hours)
            if id ~= nil then
                local recorded = KnoxPersistence.setSurvivorCreatorRecord(id,
                    Creator.recordFor(person, group))
                -- The body exists either way, so the person is never allocated
                -- twice. A refused record is counted instead of swallowed: the
                -- caller can then say that some arrived without their choices.
                person.spawned = true
                spawned[#spawned + 1] = id
                if recorded ~= true then degraded = degraded + 1 end
            end
        end
    end
    if #spawned > 1 then
        pcall(function() KnoxPersistence.createTravelGroup(spawned, hours) end)
    end
    Creator.save(roster, group)
    return #spawned, degraded
end

return Creator
