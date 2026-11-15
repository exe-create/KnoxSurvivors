-- Knox Survivors - the creator's roster model. PT-40.
--
-- Pure decisions only: what a person may be, what a roster line looks like, and
-- which people are still waiting to exist. The panel (KS_CreatorPanel) asks the
-- questions; the population writer allocates the bodies; the appearance and
-- starting-gear owners dress and kit them. Nothing here touches the world.
local Creator = rawget(_G, "KnoxCreator") or {}
_G.KnoxCreator = Creator

Creator.FILE = "KnoxSurvivors/creator.txt"
Creator.FORMAT_VERSION = 4
Creator.MAX_PEOPLE = 256
Creator.MAX_GROUP_PEOPLE = 24
Creator.MAX_NAME = 24

-- The five skin textures offered by the installed CharacterCreationMain.lua.
-- Indexes are zero-based HumanVisual indexes, not RGB tints.
Creator.SKIN_COLOURS = {
    {r=1,g=0.91,b=0.72}, {r=0.98,g=0.79,b=0.49}, {r=0.8,g=0.65,b=0.45},
    {r=0.54,g=0.38,b=0.25}, {r=0.36,g=0.25,b=0.14},
}

function Creator.skinIndex(value)
    local n = tonumber(value)
    if n == nil or n ~= math.floor(n) or n < 0 or n >= #Creator.SKIN_COLOURS then return nil end
    return n
end

function Creator.randomizeAppearance(person, hair, beard, random)
    if type(person) ~= "table" then return false end
    random = random or ZombRand
    person.skin = random(#Creator.SKIN_COLOURS)
    person.hair = hair[random(#hair) + 1] or ""
    person.beard = not person.female and beard[random(#beard) + 1] or ""
    person.hairColour = Creator.HAIR_COLOURS[random(#Creator.HAIR_COLOURS) + 1].id
    return true
end

-- The main-menu button belongs to the main menu screen and nowhere else: not
-- over the solo, load, sandbox, options or character-creation panels, and not
-- in a running game. The panel gathers the facts; this rule decides, so the
-- wrong-screen cases are provable without a running game.
Creator.MENU_BUTTON_LABEL = "Knox Creator"

function Creator.menuButtonVisible(facts)
    if type(facts) ~= "table" then return false end
    if facts.inGame == true then return false end
    if facts.mainScreen ~= true then return false end
    if facts.subScreen == true then return false end
    return true
end

Creator.LOOKS = {
    { id = "casual", label = "Casual",
      items = { "Base.Trousers_Denim", "Base.Shirt_FormalWhite", "Base.Shoes_TrainerTINT" } },
    { id = "work", label = "Work clothes",
      items = { "Base.Trousers_Workman", "Base.Shirt_Workman", "Base.Shoes_BlackBoots" } },
    { id = "police", label = "Police uniform",
      items = { "Base.Trousers_Police", "Base.Shirt_PoliceBlue", "Base.Hat_Police", "Base.Shoes_Black" } },
    { id = "military", label = "Army fatigues",
      items = { "Base.Trousers_CamoGreen", "Base.Jacket_ArmyCamoGreen", "Base.Hat_Army",
                "Base.Shoes_ArmyBoots", "Base.Vest_BulletArmy" } },
    { id = "doctor", label = "Scrubs",
      items = { "Base.JacketLong_Doctor", "Base.Shirt_Scrubs", "Base.Trousers_Scrubs", "Base.Shoes_TrainerTINT" } },
    { id = "firefighter", label = "Firefighter turnout gear",
      items = { "Base.Hat_Fireman", "Base.Jacket_Fireman", "Base.Trousers_Fireman", "Base.Shoes_BlackBoots" } },
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
    -- The chosen primary is held; a two-handed primary occupies both hand cells.
    -- A separate secondary remains a spare in inventory, not a dual-wield attack.
    { id = "primary", label = "Primary hand", kind = "weapon", options = {} },
    { id = "secondary", label = "Secondary / spare", kind = "weapon", options = {} },
    { id = "vest", label = "Vest", kind = "clothing", options = {} },
    { id = "undershirt", label = "Undershirt", kind = "clothing", options = {} },
    { id = "gloves", label = "Gloves", kind = "clothing", options = {} },
    { id = "mask", label = "Mask", kind = "clothing", options = {} },
    { id = "belt", label = "Belt", kind = "clothing", options = {
        { fullType = "Base.Belt2", label = "Belt" },
    } },
    { id = "holster", label = "Holster", kind = "clothing", options = {
        { fullType = "Base.HolsterSimple", label = "Holster" },
    } },
    { id = "eyes", label = "Eyewear", kind = "clothing", options = {} },
    { id = "socks", label = "Socks", kind = "clothing", options = {} },
    { id = "neck", label = "Neckwear", kind = "clothing", options = {} },
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
    { id = "base:fireofficer", label = "Fire officer" },
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

-- A group is an instance: these people, this purpose, this place. A *kind* is
-- what that group is - a household, a robber gang, a looter crew, a police post -
-- and the player may found as many groups of a kind as they want. This table is
-- the kind catalogue only. It used to also hold (Barley household, Voss family,
-- Turner couple, Mercer home) which were instances wearing a kind's id, so two
-- households could not exist and every new group silently became a household.
-- Kinds are code, not save data: a person names a kind by id, so an update can add
-- one without moving anybody. Each carries the loadout somebody made in it starts
-- with, drawn from the same tables the roster stores. Hostility, territory and
-- membership in the running world belong to the simulation.
Creator.KINDS = {
    { id = "household", label = "Household", group = true,
      note = "a family at home; holds and defends its house",
      look = "casual", kit = "none", weapon = "none", pack = "meal" },
    { id = "police", label = "Police", group = true,
      note = "an officer detail at a station",
      look = "police", kit = "police", weapon = "pistol", pack = "meal" },
    { id = "military", label = "Military", group = true,
      note = "a remnant holding a facility",
      look = "military", kit = "military", weapon = "rifle", pack = "medical" },
    { id = "fire_service", label = "Fire service", group = true,
      note = "a crew working out of a fire station",
      look = "firefighter", kit = "fire_rescue", weapon = "axe", pack = "medical" },
    { id = "looters", label = "Looters", group = true,
      note = "mobile scavengers with no home to hold",
      look = "casual", kit = "none", weapon = "crowbar", pack = "tools", memberCount = 4 },
    { id = "robbers", label = "Robbers", group = true,
      note = "hostile, and they take what they find",
      look = "work", kit = "none", weapon = "bat", pack = "meal" },
    { id = "doctors", label = "Doctors", group = true,
      note = "medical staff, usually at a clinic",
      look = "doctor", kit = "none", weapon = "none", pack = "medical", memberCount = 1 },
    { id = "cannibals", label = "Cannibals", group = true,
      note = "hostile, on the outskirts",
      look = "casual", kit = "none", weapon = "knife", pack = "meal" },
    -- Not a group. This id names a person who belongs to nothing, so it is kept
    -- here only so an old save that stored it still resolves.
    { id = "solo", label = "Solo survivor", group = false,
      note = "independent, never a group",
      look = "casual", kit = "none", weapon = "none", pack = "meal", memberCount = 1 },
    { id = "custom", label = "Custom group", group = true,
      note = "a blank group; choose its people, equipment, attitude and home policy",
      look = "casual", kit = "none", weapon = "none", pack = "none", memberCount = 1 },
}
-- Legacy name. Every caller and every save resolves an id through this table, so
-- the kind catalogue keeps the old key.
Creator.FACTIONS = Creator.KINDS

-- Starting rosters are templates, not new behaviour kinds or a second save.
-- Creating one copies its policy and people into the player's existing roster.
Creator.STARTING_TEMPLATES = {}
for _, town in ipairs({{"rosewood","Rosewood"},{"muldraugh","Muldraugh"},
    {"riverside","Riverside"},{"west_point","West Point"},{"louisville","Louisville"}}) do
    for _, service in ipairs({{"police","Police",4},{"doctors","Medical",3},{"fire_service","Fire Service",3}}) do
        Creator.STARTING_TEMPLATES[#Creator.STARTING_TEMPLATES + 1] = {
            id="template_" .. town[1] .. "_" .. service[1], hidden=true,
            label=town[2] .. " " .. (service[1] == "doctors" and "Doctor" or service[2]),
            profile=service[1] == "doctors" and "solo" or service[1], region=town[2],
            spawnContext=service[1] == "doctors" and "medical" or nil,
            memberCount=service[1] == "doctors" and 1 or service[3],
            note=service[1] == "doctors" and ("an independent doctor at a medical facility in " .. town[2])
                or ("starts at a matching facility in " .. town[2]),
        }
    end
end
Creator.STARTING_TEMPLATES[#Creator.STARTING_TEMPLATES + 1] = {
    id="template_solo_doctor",label="Independent doctor",profile="solo",spawnContext="medical",memberCount=1,
    note="starts alone at a real medical facility; may later join others",
}
for _, example in ipairs({
    {"civilian", "Independent civilian", "casual", "none", "meal"},
    {"worker", "Independent worker", "work", "crowbar", "tools"},
    {"scavenger", "Independent scavenger", "casual", "bat", "meal"},
}) do
    Creator.STARTING_TEMPLATES[#Creator.STARTING_TEMPLATES+1] = {
        id="template_solo_" .. example[1],label=example[2],profile="solo",memberCount=1,
        look=example[3],weapon=example[4],pack=example[5],
        note="an editable independent survivor who may later join others",
    }
end
Creator.STARTING_TEMPLATES[#Creator.STARTING_TEMPLATES + 1] = {
    id="template_fort_knox_military",label="Fort Knox Military",profile="military",hidden=true,
    memberCount=6,note="one command across real mapped military facilities",
}
for _, count in ipairs({2,3,4,5}) do
    Creator.STARTING_TEMPLATES[#Creator.STARTING_TEMPLATES + 1] = {
        id="template_household_" .. count,label="Household of " .. count,profile="household",memberCount=count,hidden=true,
        note="one family in its own house, trailer or farmhouse",
    }
end

-- A hidden roster is a saved id, not a choice. The town-named rosters, the
-- Fort Knox command and the household sizes still resolve for a save that
-- already stored them, but the creator offers kinds and custom groups instead:
-- a player founds a Police detail or a Military remnant that behaves as that
-- kind, rather than copying a town's instance.
function Creator.visibleStartingTemplates()
    local visible = {}
    for _, entry in ipairs(Creator.STARTING_TEMPLATES) do
        if entry.hidden ~= true then visible[#visible + 1] = entry end
    end
    return visible
end

-- STARTING CAST (pure)
-- The creator marks who walks in: companions capped by the sandbox limit, at
-- most one spouse, and everyone unmarked is seeded into the world. Nothing
-- marked means nobody joins - the starting cast is a choice, not a default.
function Creator.startingSplit(roster, limit)
    local cap = math.max(0, math.min(12, math.floor(tonumber(limit) or 0)))
    local companions, spouse, others = {}, nil, {}
    for _, person in ipairs(roster or {}) do
        if person.startSpouse == true and spouse == nil then
            spouse = person
        elseif person.startCompanion == true and #companions < cap then
            companions[#companions + 1] = person
        else
            others[#others + 1] = person
        end
    end
    return companions, spouse, others, cap
end

function Creator.startCounts(roster)
    local companions, spouse = 0, nil
    for _, person in ipairs(roster or {}) do
        if person.startCompanion == true then companions = companions + 1 end
        if person.startSpouse == true and spouse == nil then spouse = person end
    end
    return companions, spouse
end

-- The one place the starting rule is explained. Returns ok plus the sentence the
-- creator panel shows verbatim, naming the limit and who has to be unticked.
-- A refusal also returns a short title: the centered popup names the rule
-- while the note line keeps the full sentence.
-- One person's starting role: a spouse is the player's spouse, a companion
-- walks in with them, and everyone else is seeded. A spouse is never also a
-- companion, so the spouse answer wins and the two marks cannot disagree.
function Creator.startingRole(person)
    if type(person) ~= "table" then return nil end
    if person.startSpouse == true then return "spouse" end
    if person.startCompanion == true then return "companion" end
    return nil
end

-- The marked cast in roster order. The sidebar's Spouses and Companions row
-- reads this, so the row and the card toggles share one definition.
function Creator.markedCast(roster)
    local list = {}
    for index, person in ipairs(type(roster) == "table" and roster or {}) do
        if type(person) == "table" and Creator.startingRole(person) ~= nil then
            list[#list + 1] = { index = index, person = person }
        end
    end
    return list
end

-- The spawn pool switch. Everyone is in unless ticked out; an absent flag is
-- an old record, which always spawned, so it still does. Exclusion only stops
-- automatic allocation: the person stays in the file and dev tools can still
-- place them by hand.
function Creator.spawnIncluded(person)
    if type(person) ~= "table" then return true end
    return person.excludeFromSpawn ~= true
end

function Creator.toggleSpawn(roster, person)
    if type(person) ~= "table" then return false, "Select a survivor first." end
    local name = tostring(person.name or "They")
    if person.excludeFromSpawn == true then
        person.excludeFromSpawn = nil
        return true, name .. " is back in the spawn pool."
    end
    person.excludeFromSpawn = true
    -- Leaving the random pool never strips a walk-in role: a marked Spouse or
    -- Companion still walks in with the player, they just never spawn as a
    -- stranger. Unmarked people stay out entirely until ticked back in.
    if person.startSpouse == true or person.startCompanion == true then
        return true, name .. " leaves the random pool but still walks in as your marked "
            .. (person.startSpouse == true and "spouse." or "companion.")
    end
    return true, name .. " leaves the spawn pool (dev tools can still place them)."
end

function Creator.toggleStart(roster, person, field, limit)
    if type(person) ~= "table" then return false, "Select a survivor first." end
    -- Marks bypass the spawn pool: a Spouse or Companion walks in with the
    -- player without joining the random pool, so the switch never gates them.
    local cap = math.max(0, math.min(12, math.floor(tonumber(limit) or 0)))
    local companions, spouse = Creator.startCounts(roster)
    local name = tostring(person.name or "They")
    if field == "spouse" then
        if person.startSpouse == true then
            person.startSpouse = false
            return true, name .. " will be seeded into the world instead."
        end
        if spouse ~= nil and spouse ~= person then
            return false, "You already have a spouse: " .. tostring(spouse.name or "someone")
                .. ". Untick them first."
                , "One spouse allowed"
        end
        person.startSpouse = true
        person.startCompanion = false
        return true, name .. " will be your spouse at the start."
    end
    if person.startCompanion == true then
        person.startCompanion = false
        return true, name .. " will be seeded into the world instead."
    end
    if person.startSpouse == true then
        return false, name .. " is your spouse, so they already walk in with you.",
            "Already your spouse"
    end
    if cap <= 0 then
        return false, "The Companion Limit is 0, so nobody can join. Raise it in sandbox options.",
            "Companion limit is 0"
    end
    if companions >= cap then
        return false, "You can bring " .. tostring(cap) .. " companion"
            .. (cap == 1 and "" or "s") .. ". Untick one of them first."
            , "Companions at max"
    end
    person.startCompanion = true
    return true, name .. " will walk in with you: " .. tostring(companions + 1)
        .. " of " .. tostring(cap) .. " companions chosen."
end

function Creator.startingTemplate(id)
    for _, entry in ipairs(Creator.STARTING_TEMPLATES) do if entry.id == id then return entry end end
end

function Creator.addSoloTemplate(roster, label, templateId)
    local template = Creator.startingTemplate(templateId)
    if not template or template.profile ~= "solo" then return false, "Choose an independent person template." end
    local draft = Creator.draftForFaction("solo")
    draft.name, draft.spawnContext, draft.region = label, template.spawnContext, template.region
    if template.look then draft.look = Creator.indexOf(Creator.LOOKS,template.look) or 1 end
    if template.weapon then draft.weapon = Creator.indexOf(Creator.WEAPONS,template.weapon) or 1 end
    if template.pack then draft.pack = Creator.indexOf(Creator.PACKS,template.pack) or 1 end
    if template.spawnContext == "medical" then
        draft.look = Creator.indexOf(Creator.LOOKS,"doctor") or 1
        draft.profession = Creator.indexOf(Creator.PROFESSIONS,"base:doctor") or 1
        draft.pack = Creator.indexOf(Creator.PACKS,"medical") or 1
    end
    return Creator.add(roster,draft)
end

function Creator.addTemplateFaction(defs, label, templateId)
    local template = Creator.startingTemplate(templateId)
    if not template then return false, "Unknown starting roster." end
    local ok, entry = Creator.addFaction(defs, label, template.profile)
    if not ok then return false, entry end
    entry.region, entry.memberCount = template.region, template.memberCount
    return true, entry
end


-- Kinds that can be founded as a group. Solo is deliberately absent: it is the
-- absence of a group, so it is never offered as one.
function Creator.groupKinds()
    local kinds = {}
    for _, entry in ipairs(Creator.FACTIONS) do
        if entry.group == true then kinds[#kinds + 1] = entry end
    end
    return kinds
end

-- The descriptors a group can change between after it exists. These are the
-- behaviours the creator stores as data; police, military, fire service and
-- doctors are shipped starting templates a player may copy, not behaviours to
-- switch a group to later. Solo is absent because it is the absence of a group,
-- not another kind of one.
local DESCRIPTOR_KINDS = { "custom", "household", "robbers", "looters", "cannibals" }

function Creator.descriptorKinds()
    local kinds = {}
    for _, id in ipairs(DESCRIPTOR_KINDS) do
        local entry = Creator.factionIndexIn(nil, id)
        if entry ~= nil then kinds[#kinds + 1] = entry end
    end
    return kinds
end

function Creator.isGroupKind(kind)
    local entry = Creator.factionIndexIn(nil, tostring(kind))
    return entry ~= nil and entry.group == true
end

function Creator.kindLabel(kind)
    local entry = Creator.factionIndexIn(nil, tostring(kind))
    return entry ~= nil and entry.label or "Group"
end

-- What a kind *does*. This is the only table the simulation is allowed to ask
-- about behaviour: a group's kind decides whether it settles a home and holds it,
-- whether it roams, whether it founds a faction, and its default stance. Before
-- this, `looters` was re-checked by name in the promotion path and hostility was
-- a copied per-person field, so a group's kind could disagree with its behaviour.
-- These values reproduce the behaviour the payload already had, so nothing here
-- invents a new rule; it removes the second copy of the rule.
local KIND_BEHAVIOUR = {
    custom = { roams = true, formsFaction = true, attitude = "neutral",
        settlementPolicy = "mobile", spawnContext = "any" },
    household = { home = true, defendsHome = true, formsFaction = true,
        attitude = "dynamic", settlementPolicy = "home", spawnContext = "household" },
    police = { home = true, defendsHome = true, formsFaction = true,
        attitude = "friendly", settlementPolicy = "home", spawnContext = "law_enforcement" },
    military = { home = true, defendsHome = true, formsFaction = true,
        attitude = "hostile", settlementPolicy = "home", spawnContext = "military" },
    fire_service = { home = true, defendsHome = true, formsFaction = true,
        attitude = "friendly", settlementPolicy = "home", spawnContext = "fire_service" },
    doctors = { home = true, defendsHome = true, formsFaction = true,
        attitude = "friendly", settlementPolicy = "home", spawnContext = "medical" },
    looters = { roams = true, loots = true, formsFaction = false,
        attitude = "random", settlementPolicy = "mobile", spawnContext = "any" },
    robbers = { home = true, defendsHome = true, formsFaction = true,
        attitude = "hostile", settlementPolicy = "home", spawnContext = "any" },
    cannibals = { home = true, defendsHome = true, formsFaction = true,
        attitude = "hostile", settlementPolicy = "home", spawnContext = "any" },
    solo = { independent = true, formsFaction = false,
        attitude = "dynamic", settlementPolicy = "independent", spawnContext = "any" },
}
Creator.KIND_BEHAVIOUR = KIND_BEHAVIOUR

function Creator.behaviourFor(kind)
    local row = KIND_BEHAVIOUR[tostring(kind or "")]
    if row == nil then return nil end
    local copy = { kind = tostring(kind) }
    for key, value in pairs(row) do copy[key] = value end
    copy.label = Creator.kindLabel(kind)
    copy.hostileToOutsiders = row.attitude == "hostile"
    copy.settles = row.home == true
    copy.canFoundFaction = row.formsFaction == true
    return copy
end

local PROFILE_FIELDS = { "look", "kit", "weapon", "pack", "profile", "attitude", "memberCount", "spawnContext", "vehiclePolicy", "settlementPolicy" }
local PROFILE_DEFAULTS = { look = "casual", kit = "none", weapon = "none", pack = "meal", profile = "household", attitude = "dynamic", memberCount = 3, spawnContext = "default", vehiclePolicy = "default", settlementPolicy = "default" }
local PROFILE_ATTITUDES = { custom = "neutral", household = "dynamic", police = "friendly", doctors = "friendly", military = "hostile", looters = "random", robbers = "hostile", cannibals = "hostile", solo = "dynamic" }
local PROFILE_KINDS = { custom=true, household=true, police=true, military=true, fire_service=true, looters=true, robbers=true, doctors=true, cannibals=true, solo=true }
Creator.PROFILE_FIELDS = PROFILE_FIELDS
Creator.ATTITUDES = { "friendly", "neutral", "hostile", "random", "dynamic" }

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
    for _, entry in ipairs(type(defs) == "table" and defs or {}) do
        if type(entry) == "table" and entry.id == id then return entry end
    end
    for _, entry in ipairs(Creator.FACTIONS) do
        if entry.id == id then return entry end
    end
    -- Regional group templates are authoring defaults, not population spawns.
    -- Independent medical templates stay in the person creation chooser.
    local template = Creator.startingTemplate(id)
    if template ~= nil and template.profile ~= "solo" and template.profile ~= "household" then
        local entry = {}
        for _, kind in ipairs(Creator.FACTIONS) do
            if kind.id == template.profile then
                for key, value in pairs(kind) do entry[key] = value end
                break
            end
        end
        for key, value in pairs(template) do entry[key] = value end
        entry.id, entry.group = template.id, true
        return entry
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
    for _, entry in ipairs(Creator.defaultEntries()) do
        merged[#merged + 1] = Creator.factionIndexIn(defs, entry.id)
    end
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
    return "Unknown faction"
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
    local profile = entry.profile or entry.id
    local profession = ({police="base:policeofficer",military="base:veteran",
        doctors="base:doctor",fire_service="base:fireofficer"})[profile]
    draft.profession = factionIndexOf(Creator.PROFESSIONS, profession) or 1
    draft.faction = entry.id
    return draft
end

-- Where "Add person" really puts somebody. The card grid can show All, one
-- group, or the Spouses and Companions filter, so the selected row is not
-- always a group that can take a person. A shipped kind preview is never an
-- add target either: it has the default id, and adding there would silently
-- grow the default instead of the player's own group.
function Creator.isOwnedGroupId(id, defs)
    for _, entry in ipairs(type(defs) == "table" and defs or {}) do
        if type(entry) == "table" and entry.id == id then return true end
    end
    return false
end

function Creator.resolveAddTarget(selectedFactionId, group)
    local defs = type(group) == "table" and group.defs or {}
    if selectedFactionId == nil then
        return false, "Choose the group they join on the left, or Solo survivors, then add."
    end
    if selectedFactionId == "starting" then
        return false, "You are viewing Spouses and Companions, which is a filter, not a group. Choose the person's group on the left, then add."
    end
    if selectedFactionId == "solo" then return true, "solo" end
    if Creator.isOwnedGroupId(selectedFactionId, defs) then
        return true, selectedFactionId
    end
    local preview = Creator.factionIndexIn(defs, selectedFactionId)
    local label = preview ~= nil and preview.label or "That shipped kind"
    return false, label .. " is a shipped preview, not your group. Copy it into a group of your own, then add people there."
end

-- One line per roster person for the in-game dev spawn menu. Pure: the menu
-- shows names, the spawner builds the hand-over record.
function Creator.devSpawnEntries(roster, group)
    local entries = {}
    for index, person in ipairs(type(roster) == "table" and roster or {}) do
        if type(person) == "table" then
            entries[#entries + 1] = { index = index,
                label = tostring(person.name or "Unnamed"),
                detail = Creator.factionLabel(Creator.personFactionId(person, group),
                    type(group) == "table" and group.defs or nil) }
        end
    end
    return entries
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
    return entry ~= nil and entry.label or "Unnamed"
end

function Creator.newDraft()
    return { name = "", look = 1, kit = 1, weapon = 1, profession = 1, pack = 1,
        female = false, skin = 0, hair = "", beard = "", hairColour = "brown", skills = {}, traits = {},
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
    torso = { "torso", "shirt", "jacket", "sweater", "jacket_bulky", "torsoextra" },
    legs = { "legs", "pants" },
    head = { "hat", "head" },
    feet = { "feet", "shoes", "boots" },
    backpack = { "back" },
    vest = { "torsoextravest", "torsoextravestbullet", "vesttexture" },
    undershirt = { "underweartop" },
    gloves = { "hands", "handsleft", "handsright" },
    mask = { "mask", "maskeyes", "maskfull" },
    belt = { "belt" },
    holster = { "beltextra", "shoulderholster", "ankleholster" },
    eyes = { "eyes" },
    socks = { "socks" },
    neck = { "neck", "necktexture" },
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
                    if location ~= nil then
                        local lower = string.lower(tostring(location)):gsub("^base:", "")
                        for _, word in ipairs(words) do
                            local expected = string.lower(word):gsub("^base:", "")
                            if lower == expected then matches = true; break end
                        end
                    end
                    if slotId == "backpack" then
                        matches = false
                        pcall(function()
                            local itemType = string.lower(tostring(item:getItemType()))
                            matches = itemType == "container" or itemType == "base:container"
                        end)
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

-- Query the installed item's own hand requirements, including modded weapons.
local handRequirements, handFactory = {}, nil
function Creator.isTwoHanded(fullType)
    if type(fullType) ~= "string" or fullType == "" then return false end
    if handFactory ~= instanceItem then handFactory, handRequirements = instanceItem, {} end
    if handRequirements[fullType] ~= nil then return handRequirements[fullType] end
    local result = false
    pcall(function()
        local item = instanceItem(fullType)
        if item ~= nil then
            if item.isTwoHandWeapon ~= nil then result = item:isTwoHandWeapon() end
            if not result and item.isRequiresEquippedBothHands ~= nil then
                result = item:isRequiresEquippedBothHands()
            end
            handRequirements[fullType] = result == true
        end
    end)
    return result == true
end

function Creator.effectiveSlotChoice(person, slotId)
    if type(person) ~= "table" then return nil end
    local slot = Creator.slotById(slotId)
    if slot == nil then return nil end
    if slotId == "secondary" then
        local primary = Creator.effectiveSlotChoice(person, "primary")
        if primary and Creator.isTwoHanded(primary.fullType) then
            return {fullType=primary.fullType,label=primary.label .. " (both hands)"}
        end
    end
    local raw = type(person.slots) == "table" and person.slots[slotId] or nil
    if raw == "__none" then return {label="None (empty slot)"} end
    if raw ~= nil then
        return Creator.slotOption(slotId, raw) or {fullType=raw, label="Unavailable item: " .. tostring(raw)}
    end
    if slotId == "primary" then
        local fullType = person.weapon or Creator.weaponItem(person.weaponId)
        if fullType ~= nil then
            return Creator.slotOption(slotId, fullType) or {fullType=fullType,label="Unavailable item: " .. tostring(fullType)}
        end
    elseif slot.kind == "clothing" then
        for _, fullType in ipairs(Creator.lookItems(person.look)) do
            local choice = Creator.slotOption(slotId, fullType)
            if choice then return {fullType=fullType,label=choice.label .. " (outfit)"} end
        end
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
    local parts, keys = {}, {}
    for slotId, fullType in pairs(slots) do
        if type(slotId) == "string" and slotId:match("^[%a_]+$") and type(fullType) == "string" and fullType:match("^[%w_%.]+$") then keys[#keys + 1] = slotId end
    end
    table.sort(keys)
    for _, slotId in ipairs(keys) do parts[#parts + 1] = slotId .. ":" .. slots[slotId] end
    return table.concat(parts, ";")
end

function Creator.decodeSlots(text)
    local slots = {}
    if type(text) ~= "string" then return slots end
    for pair in text:gmatch("[^;]+") do
        local slotId, fullType = pair:match("^([%a_]+):([%w_%.]+)$")
        if slotId ~= nil then slots[slotId] = fullType end
    end
    return slots
end

function Creator.itemCatalogue()
    local entries, seen = {}, {}
    pcall(function()
        local items = getScriptManager():getAllItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local fullType, label
            pcall(function() fullType = item:getFullName() end)
            local hidden, obsolete = false, false
            pcall(function() hidden = item:isHidden() end)
            pcall(function() obsolete = item:getObsolete() end)
            if type(fullType) == "string" and fullType ~= "" and not hidden and not obsolete and not seen[fullType] then
                label = fullType
                pcall(function() label = tostring(item:getDisplayName() or fullType) end)
                seen[fullType] = true
                entries[#entries + 1] = { fullType = fullType, label = label }
            end
        end
    end)
    table.sort(entries, function(a, b)
        local left, right = string.lower(a.label), string.lower(b.label)
        if left == right then return a.fullType < b.fullType end
        return left < right
    end)
    return entries
end

function Creator.encodeCargo(cargo)
    if type(cargo) ~= "table" then return "" end
    local keys, parts = {}, {}
    for id, count in pairs(cargo) do
        if type(id) == "string" and id:match("^[%w_]+%.[%w_]+$") and type(count) == "number" and count == math.floor(count) and count >= 1 and count <= 100 then keys[#keys + 1] = id end
    end
    table.sort(keys)
    for i = 1, math.min(#keys, 64) do parts[#parts + 1] = keys[i] .. "=" .. tostring(cargo[keys[i]]) end
    return table.concat(parts, ";")
end

function Creator.decodeCargo(text)
    local cargo, count = {}, 0
    if type(text) ~= "string" then return cargo end
    for pair in text:gmatch("[^;]+") do
        local id, amount = pair:match("^([%w_]+%.[%w_]+)=(%d+)$")
        amount = tonumber(amount)
        if id and amount and amount >= 1 and amount <= 100 and cargo[id] == nil and count < 64 then cargo[id], count = amount, count + 1 end
    end
    return cargo
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

-- Add the installed game's leaf perks without dropping the legacy catalogue.
function Creator.refreshSkillCatalogue()
    if Creator.skillsCatalogueReady or Perks == nil or PerkFactory == nil then return end
    local ok = pcall(function()
        for index = 0, Perks.getMaxIndex() - 1 do
            local perk = PerkFactory.getPerk(Perks.fromIndex(index))
            if perk ~= nil and perk:getParent() ~= Perks.None then
                local id = tostring(perk:getId())
                if id:match("^[%w_:]+$") and not SKILL_SET[id] then
                    SKILL_SET[id] = true
                    Creator.SKILLS[#Creator.SKILLS + 1] = id
                end
            end
        end
    end)
    if ok then Creator.skillsCatalogueReady = true end
end

function Creator.refreshProfessionCatalogue()
    if Creator.professionsCatalogueReady or CharacterProfessionDefinition == nil then return end
    local ok = pcall(function()
        local definitions = CharacterProfessionDefinition.getProfessions()
        for index = 0, definitions:size() - 1 do
            local definition = definitions:get(index)
            local id = tostring(definition:getType())
            if Creator.indexOf(Creator.PROFESSIONS, id) == nil then
                Creator.PROFESSIONS[#Creator.PROFESSIONS + 1] = {id=id, label=tostring(definition:getUIName())}
            end
        end
    end)
    if ok then Creator.professionsCatalogueReady = true end
end

function Creator.encodeTraits(traits)
    if type(traits) ~= "table" then return nil end
    local ids, seen = {}, {}
    for _, id in ipairs(traits) do
        if type(id) == "string" and id:match("^[%w_:%.]+$") and not seen[id] then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    table.sort(ids)
    return table.concat(ids, ";")
end

function Creator.decodeTraits(text)
    if type(text) ~= "string" then return nil end
    local result, seen = {}, {}
    for id in text:gmatch("[^;]+") do
        if id:match("^[%w_:%.]+$") and not seen[id] then
            result[#result + 1], seen[id] = id, true
        end
    end
    return result
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
    Creator.refreshSkillCatalogue()
    local parts = {}
    for _, perkId in ipairs(Creator.SKILLS) do
        local level = Creator.skillLevel(skills, perkId)
        if type(skills) == "table" and skills[perkId] ~= nil then parts[#parts + 1] = perkId .. "=" .. tostring(level) end
    end
    return table.concat(parts, ";")
end

function Creator.decodeSkills(text)
    local skills = {}
    Creator.refreshSkillCatalogue()
    if type(text) ~= "string" then return skills end
    for pair in text:gmatch("[^;]+") do
        local perkId, level = pair:match("^([%w_:]+)=(%d+)$")
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
    -- The companions view is a filter, not a faction: the marked cast in roster
    -- order, so nobody can hide from it by belonging elsewhere.
    if factionId == "starting" then return Creator.markedCast(roster) end
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

function Creator.cardGrid(count, x, y, width, height, scroll, rowHeight)
    local cardW, cardH, gap = math.min(Creator.CARD_WIDTH, math.max(1, tonumber(width) or 1)), Creator.CARD_HEIGHT, Creator.CARD_GAP
    cardH = math.max(cardH, (tonumber(rowHeight) or 0) * 7 + 32)
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

-- Faction editing is decided here, not in the panel: a group is created as a
-- kind, a player group can be renamed, and one that still holds people cannot
-- vanish from under them. `kind` is required because "new faction" used to mean
-- "another household" without ever saying so.
function Creator.addFaction(defs, label, kind)
    if type(defs) ~= "table" then return false, "no_faction_list" end
    local source = Creator.factionIndexIn(nil, tostring(kind or "household"))
    if source == nil or source.group ~= true then
        return false, "Choose what kind of group this is."
    end
    local name, err = Creator.validateFactionName(label)
    if name == nil then return false, err end
    for _, entry in ipairs(Creator.allFactions(defs)) do
        if string.lower(entry.label) == string.lower(name) then
            return false, "That group already exists."
        end
    end
    local entry = { id = Creator.newFactionId(name, defs), label = name, user = true,
        profile = source.profile or source.id, look = source.look or "casual", kit = source.kit or "none",
        weapon = source.weapon or "none", pack = source.pack or "meal" }
    if source.memberCount ~= nil then entry.memberCount = source.memberCount end
    entry.region = source.region
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

function Creator.nameKey(name)
    return trim(name):gsub("%s+", " "):lower()
end

function Creator.add(roster, draft)
    Creator.refreshSkillCatalogue()
    Creator.refreshProfessionCatalogue()
    if type(roster) ~= "table" then return false, "no_roster" end
    local ok, name = Creator.draftValid(draft, #roster)
    if not ok then return false, name end
    -- Two people with one name make every later row and line ambiguous, so the
    -- duplicate is refused where the person is added rather than renamed later.
    local lower = Creator.nameKey(name)
    for _, person in ipairs(roster) do
        if type(person) == "table" and type(person.name) == "string"
            and Creator.nameKey(person.name) == lower then
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
        skin = Creator.skinIndex(draft.skin) or 0,
        spawnContext = draft.spawnContext == "medical" and "medical" or nil,
        region = type(draft.region) == "string" and draft.region or nil,
        hair = type(draft.hair) == "string" and draft.hair or "",
        beard = type(draft.beard) == "string" and draft.beard or "",
        hairColour = Creator.HAIR_COLOURS[Creator.colourIndexOf(draft.hairColour)].id,
        skills = {},
        traits = Creator.decodeTraits(Creator.encodeTraits(draft.traits)),
        slots = Creator.decodeSlots(Creator.encodeSlots(draft.slots)),
        cargo = Creator.decodeCargo(Creator.encodeCargo(draft.cargo)),
        bagCargo = Creator.decodeCargo(Creator.encodeCargo(draft.bagCargo)),
        -- The faction a person was made in, by id: the card and the sidebar
        -- both read this field, and a group change never rewrites it.
        faction = type(draft.faction) == "string" and draft.faction or nil,
    }
    Creator.refreshSkillCatalogue()
    for _, perkId in ipairs(Creator.SKILLS) do
        local level = Creator.skillLevel(draft.skills, perkId)
        if draft.skills and draft.skills[perkId] ~= nil then person.skills[perkId] = level end
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
                and (slots[slot.id] == "__none" or Creator.slotOption(slot.id, slots[slot.id]) ~= nil) then
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

-- Profiles are copied starting conditions; the running world's relationships remain authoritative.
function Creator.profileFor(id, defs)
    local source = Creator.factionIndexIn(defs, id)
    if source == nil then return nil end
    local result = {}
    for _, key in ipairs(PROFILE_FIELDS) do result[key] = source[key] or PROFILE_DEFAULTS[key] end
    result.profile = source.profile or (PROFILE_KINDS[id] and id) or "household"
    result.attitude = source.attitude or PROFILE_ATTITUDES[result.profile] or "dynamic"
    result.memberCount = tonumber(source.memberCount) or (result.profile == "solo" and 1 or 3)
    -- The kind owns the derived defaults. A stored value already on the group
    -- still wins, so an explicit choice is never overwritten by the table.
    local behaviour = Creator.behaviourFor(result.profile)
    result.behaviour = behaviour
    if result.spawnContext == "default" then
        result.spawnContext = (behaviour ~= nil and behaviour.spawnContext) or "any"
    end
    if result.vehiclePolicy == "default" then
        result.vehiclePolicy = (result.profile == "police" or result.profile == "military") and result.profile or "any"
    end
    if result.settlementPolicy == "default" then
        result.settlementPolicy = (behaviour ~= nil and behaviour.settlementPolicy) or "home"
    end
    result.id, result.label, result.region = source.id, source.label, source.region
    if result.profile == "cannibals" then
        result.capabilityLimit = "Hostile loadout only. Captivity and eating people are not implemented."
    elseif result.profile == "robbers" then
        result.capabilityLimit = "Hostile loadout only. Group robbery demands and compliance are not implemented."
    elseif result.profile == "looters" then
        result.capabilityLimit = "Mobile scavengers. Coordinated convoys and three people per car are not implemented."
    end
    return result
end

function Creator.copyFaction(defs, sourceId, label)
    local profile = Creator.profileFor(sourceId, defs)
    if profile == nil then return false, "No such faction." end
    local ok, entry = Creator.addFaction(defs, label, profile.profile)
    if not ok then return false, entry end
    for _, key in ipairs(PROFILE_FIELDS) do entry[key] = profile[key] end
    entry.region = profile.region
    return true, entry
end

-- Built-in definitions stay immutable. An explicitly requested edit stores a
-- same-id override in the existing definitions list and codec.
function Creator.isDefault(id)
    return Creator.factionIndexIn(nil, id) ~= nil
end

function Creator.defaultEntries()
    local entries = {}
    for _, entry in ipairs(Creator.FACTIONS) do entries[#entries + 1] = entry end
    for _, template in ipairs(Creator.STARTING_TEMPLATES) do
        if template.profile ~= "solo" and template.profile ~= "household" then entries[#entries + 1] = Creator.factionIndexIn(nil, template.id) end
    end
    return entries
end

function Creator.editDefault(defs, id)
    if type(defs) ~= "table" then return false, "no_faction_list" end
    local source = Creator.factionIndexIn(nil, id)
    if source == nil then return false, "No such built-in group." end
    for _, entry in ipairs(defs) do
        if entry.id == id then return true, entry end
    end
    local entry = { id = source.id, label = source.label, user = true }
    for _, key in ipairs(PROFILE_FIELDS) do entry[key] = source[key] end
    entry.region = source.region
    defs[#defs + 1] = entry
    return true, entry
end

function Creator.resetDefault(defs, id)
    if type(defs) ~= "table" or not Creator.isDefault(id) then return false, "No such built-in group." end
    for index = #defs, 1, -1 do
        if defs[index].id == id then table.remove(defs, index) end
    end
    return true, Creator.factionIndexIn(nil, id)
end

function Creator.updateFaction(defs, id, changes)
    if type(changes) ~= "table" then return false, "Invalid changes." end
    local entry
    for _, candidate in ipairs(type(defs) == "table" and defs or {}) do
        if candidate.id == id then entry = candidate end
    end
    if not entry then return false, "No such saved faction." end
    local allowed = { look=Creator.LOOKS, kit=Creator.KITS, weapon=Creator.WEAPONS, pack=Creator.PACKS }
    for key, value in pairs(changes) do
        if allowed[key] then
            if not factionIndexOf(allowed[key], value) then return false, "Invalid " .. key end
        elseif key == "profile" then
            if not PROFILE_KINDS[value] then return false, "Invalid profile" end
        elseif key == "attitude" then
            local valid = false
            for _, item in ipairs(Creator.ATTITUDES) do if item == value then valid = true end end
            if not valid then return false, "Invalid attitude" end
        elseif key == "memberCount" then
            if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > Creator.MAX_GROUP_PEOPLE then return false, "Invalid member count" end
        elseif key == "region" then
            if type(value) ~= "string" or #value > 48 or value:find("[|\r\n]") then return false, "Invalid region" end
        elseif key == "spawnContext" or key == "vehiclePolicy" or key == "settlementPolicy" then
            if type(value) ~= "string" or #value < 1 or #value > 32 or not string.match(value, "^[%w_]+$") then return false, "Invalid " .. key end
        else return false, "Unknown profile field" end
    end
    for key, value in pairs(changes) do entry[key] = value end
    -- A stored stance belonged to the kind it was chosen for. Changing the kind
    -- re-derives it, unless the same edit names the stance the group wants now.
    if changes.profile ~= nil and changes.attitude == nil then
        entry.attitude = nil
    end
    return true, entry
end

function Creator.capacityForFaction(roster, group, id)
    local count = 0
    for _, person in ipairs(type(roster) == "table" and roster or {}) do
        if Creator.personFactionId(person, group) == id then count = count + 1 end
    end
    return math.max(0, math.min(Creator.MAX_GROUP_PEOPLE - count, Creator.MAX_PEOPLE - #(roster or {})))
end

-- Default professional rosters vary their finite starting equipment. Personal
-- changes to the profile's chosen weapon retain that explicit choice instead.
function Creator.applyPresetLoadout(draft, profile, memberIndex)
    local variants
    local n = math.max(1, tonumber(memberIndex) or 1)
    if profile.profile == "household" then
        if profile.look == "casual" then draft.look = indexOf(Creator.LOOKS, ({"casual","work","casual"})[(n-1)%3+1]) end
        if profile.weapon == "none" then draft.weapon = indexOf(Creator.WEAPONS, ({"none","bat","knife","crowbar"})[(n-1)%4+1]) end
        if profile.pack == "meal" then draft.pack = indexOf(Creator.PACKS, ({"meal","tools","medical","meal"})[(n-1)%4+1]) end
        draft.profession = indexOf(Creator.PROFESSIONS, ({"base:unemployed","base:mechanics","base:farmer","base:carpenter","base:chef"})[(n-1)%5+1])
        return draft
    end
    if profile.profile == "police" and profile.weapon == "pistol" then
        variants = {"Base.Pistol", "Base.Pistol2", "Base.Revolver", "Base.Shotgun", "Base.Pistol"}
    elseif profile.profile == "military" and profile.weapon == "rifle" then
        variants = {"Base.AssaultRifle", "Base.AssaultRifle2", "Base.HuntingRifle", "Base.Shotgun"}
    end
    if variants == nil then return draft end
    local desired = variants[((memberIndex or 1) - 1) % #variants + 1]
    local selected
    for i, weapon in ipairs(Creator.weaponCatalogue()) do
        if weapon.fullType == desired then selected = i; break end
    end
    if selected == nil then return draft end
    draft.weapon, draft.kit = selected, 1
    local cargo = {
        ["Base.Pistol"] = {["Base.9mmClip"]=1,["Base.Bullets9mm"]=24},
        ["Base.Pistol2"] = {["Base.45Clip"]=1,["Base.Bullets45"]=21},
        ["Base.Revolver"] = {["Base.Bullets357"]=18},
        ["Base.Shotgun"] = {["Base.ShotgunShells"]=12},
        ["Base.AssaultRifle"] = {["Base.556Clip"]=2,["Base.556Bullets"]=60},
        ["Base.AssaultRifle2"] = {["Base.M14Clip"]=2,["Base.308Bullets"]=40},
        ["Base.HuntingRifle"] = {["Base.308Bullets"]=20},
    }
    draft.cargo = cargo[desired] or {}
    return draft
end

-- Generation is stable for a group, without consuming the game's random stream.
-- Hair and beard choices still come from the installed character creator APIs.
local function populationSeed(identity)
    local hash = 0
    for i = 1, #identity do hash = (hash * 31 + identity:byte(i)) % 65521 end
    return hash
end

function Creator.hairOptions(female)
    local values = {""}
    pcall(function()
        local styles = getAllHairStyles(female == true)
        for i = 0, styles:size() - 1 do
            local value = tostring(styles:get(i))
            local selectable = true
            if getHairStylesInstance then
                local owner = getHairStylesInstance()
                local style = female and owner:FindFemaleStyle(value) or owner:FindMaleStyle(value)
                selectable = style ~= nil and not style:isNoChoose()
            end
            if value ~= "" and selectable then values[#values + 1] = value end
        end
    end)
    return values
end

function Creator.beardOptions(female)
    local values = {""}
    if female then return values end
    pcall(function()
        local styles = getAllBeardStyles()
        for i = 0, styles:size() - 1 do
            local value = tostring(styles:get(i))
            if value ~= "" then values[#values + 1] = value end
        end
    end)
    return values
end

function Creator.populateFaction(roster, group, id, count, reservedRoster)
    if type(roster) ~= "table" or type(group) ~= "table" then return false, "Invalid roster." end
    local profile = Creator.profileFor(id, group.defs)
    if not profile then return false, "No such faction." end
    count = tonumber(count) or profile.memberCount
    if count ~= math.floor(count) or count < 1 or count > Creator.capacityForFaction(roster, group, id) then return false, "Not enough room." end
    -- Alternating male/female names keep the descriptor sex consistent with the
    -- chosen given name, including when collisions advance the name search.
    local first = { "Elias", "Mara", "Caleb", "Nora", "Jonah", "Ruth", "Owen", "Leah", "Isaac", "June", "Silas", "Eva", "Miles", "Ada", "Graham", "Iris", "Theo", "Cora", "Wesley", "Mae", "Hugh", "Rose", "Grant", "Faye", "Daniel", "Sarah", "Henry", "Clara", "James", "Alice", "Marcus", "Helen", "Thomas", "Laura", "Samuel", "Diana", "Nathan", "Grace", "Arthur", "Elena", "Victor", "Rachel", "Louis", "Naomi", "Peter", "Julia", "Simon", "Lucy" }
    local surnames = { "Bennett", "Davis", "Hayes", "Miller", "Parker", "Reed", "Sutton", "Walker", "Young", "Carter", "Foster", "Brooks", "Collins", "Morgan", "Walsh", "Price", "Cole", "Reynolds", "Webb", "Howard", "Lawson", "Ellis", "Ward", "Palmer", "Harris", "Clark", "Lewis", "Martin", "Scott", "Turner", "Wilson" }
    local seed = populationSeed(tostring(id or "") .. ":" .. tostring(profile.label or ""))
    local nameOffset, defaultNames = seed, false
    for index, entry in ipairs(Creator.defaultEntries()) do
        if entry.id == id then
            nameOffset, defaultNames = (index - 1) * Creator.MAX_GROUP_PEOPLE, true
            break
        end
    end
    -- Recognise family labels without turning titles such as "Household of 4"
    -- or "Trailer Park Survivors" into people's surnames. Generic households
    -- still share one ordinary surname, stable for this group's identity.
    local last = nil
    if profile.profile == "household" then
        local label = tostring(profile.label or ""):match("^%s*(.-)%s*$")
        local word = label:gsub("^[Tt]he%s+", ""):gsub("%s+[Hh]ousehold$", ""):gsub("%s+[Ff]amily$", "")
        if #word >= 2 and word:match("^[%a\128-\255'%-]+$")
            and not ({household=true,households=true,family=true,families=true,survivors=true,group=true,groups=true})[word:lower()] then
            last = word
        else
            -- Shipped previews have disjoint name blocks even before the player
            -- saves any group. Generic households share their own block's name.
            last = surnames[(defaultNames and math.floor(nameOffset / #first) or seed) % #surnames + 1]
        end
    end
    local used = {}
    for _, people in ipairs({roster, reservedRoster or {}}) do
        for _, person in ipairs(people) do used[Creator.nameKey(person.name)] = true end
    end
    local names = {}
    local combinations = #first * (last and 27 or #surnames)
    for n = 0, combinations - 1 do
        local firstIndex = (nameOffset + n) % #first + 1
        local given = first[firstIndex]
        local cycle = math.floor(n / #first)
        local surname = last or surnames[math.floor((nameOffset + n) / #first) % #surnames + 1]
        -- Only unusually crowded same-surname families need a middle initial.
        if last and cycle > 0 then given = given .. " " .. string.char(64 + cycle) .. "." end
        local name = given .. " " .. surname
        local key = Creator.nameKey(name)
        if #name <= Creator.MAX_NAME and not used[key] then
            names[#names + 1] = {name = name, female = firstIndex % 2 == 0}
            used[key] = true
        end
        if #names == count then break end
    end
    if #names < count then return false, "Could not find enough unique names." end
    local hair = {Creator.hairOptions(false), Creator.hairOptions(true)}
    local beards = Creator.beardOptions(false)
    -- Validate the complete batch before changing the caller's roster.
    local pending = {}
    for i, person in ipairs(roster) do pending[i] = person end
    for i, identity in ipairs(names) do
        local draft = Creator.draftForFaction(id, group.defs)
        draft.name, draft.faction, draft.female = identity.name, id, identity.female
        local state = populationSeed(tostring(id) .. ":" .. identity.name) + 1
        Creator.randomizeAppearance(draft, hair[draft.female and 2 or 1], beards, function(limit)
            state = (state * 48271) % 2147483647
            return math.floor(state / 2147483647 * limit)
        end)
        Creator.applyPresetLoadout(draft, profile, i)
        local ok, reason = Creator.add(pending, draft)
        if not ok then return false, reason end
    end
    for i = #roster + 1, #pending do roster[i] = pending[i] end
    local total = 0
    for _, person in ipairs(roster) do if Creator.personFactionId(person, group) == id then total = total + 1 end end
    return true, total
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
    local policy = Creator.profileFor(factionId, group.defs) or {}
    local slots = Creator.decodeSlots(Creator.encodeSlots(person.slots))
    local primary = Creator.slotChoice("primary", slots)
    local weapon = primary ~= nil and primary.fullType or person.weapon
    if slots.primary == "__none" then weapon = nil end
    local bag = Creator.slotChoice("backpack", slots)
    -- A stance equal to the kind's own default is a copy, not a choice. Storing
    -- it made the copy outrank the kind when the engagement decision was made, so
    -- a group whose kind changed kept its old answer. Only a stance the group
    -- actually chose is stored; otherwise the kind answers at decision time.
    local stance = policy.attitude
    local behaviour = policy.behaviour or Creator.behaviourFor(policy.profile)
    if behaviour ~= nil and stance == behaviour.attitude then stance = nil end
    return {
        name = person.name,
        look = person.look,
        kit = person.kit,
        -- The primary slot is the carried weapon; the "Carries" row stays the
        -- preset that filled these slots for a new person.
        weapon = weapon,
        pack = person.pack,
        faction = factionId,
        bag = bag ~= nil and bag.fullType or nil,
        groupName = (string.sub(factionId, 1, 5) == "user_" and policy.label)
            or (type(group.name) == "string" and group.name ~= "" and group.name) or policy.label,
        profile = policy.profile, attitude = stance, spawnContext = (factionId == "solo" and person.spawnContext) or policy.spawnContext,
        vehiclePolicy = policy.vehiclePolicy, settlementPolicy = policy.settlementPolicy,
        hair = person.hair,
        beard = person.beard,
        hairColour = person.hairColour,
        female = person.female == true,
        skin = Creator.skinIndex(person.skin) or 0,
        skills = Creator.encodeSkills(person.skills),
        profession = person.profession,
        traits = Creator.encodeTraits(person.traits),
        slots = Creator.encodeSlots(person.slots),
        cargo = Creator.encodeCargo(person.cargo),
        bagCargo = Creator.encodeCargo(person.bagCargo),
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

-- A pack item must exist in the loaded scripts. getScriptManager():FindItem
-- answers for vanilla and modded items alike; when the manager or the lookup
-- is unavailable the item is kept, because unverifiable is not the same as
-- absent and silently emptying a pack would be worse than a stale id.
local itemKnownCache = {}
local itemLookupAnswers = nil
-- A canary every install ships. If the lookup cannot answer for it, it cannot
-- answer for anything, and its nil must not be read as "that item does not
-- exist" - which is what an engine-less harness would otherwise claim.
local function scriptManagerAnswersItems(manager)
    if itemLookupAnswers ~= nil then return itemLookupAnswers end
    itemLookupAnswers = false
    pcall(function()
        local find = manager.FindItem or manager.getItem
        itemLookupAnswers = find ~= nil and find(manager, "Base.Bandage") ~= nil
    end)
    return itemLookupAnswers
end
function Creator.itemKnown(fullType)
    if type(fullType) ~= "string" or fullType == "" then return false end
    local cached = itemKnownCache[fullType]
    if cached ~= nil then return cached end
    local known = true
    pcall(function()
        local manager = getScriptManager and getScriptManager() or nil
        if manager == nil then return end
        if not scriptManagerAnswersItems(manager) then return end
        local find = manager.FindItem or manager.getItem
        if find == nil then return end
        known = find(manager, fullType) ~= nil
    end)
    itemKnownCache[fullType] = known
    return known
end

function Creator.packItems(id)
    local index = indexOf(Creator.PACKS, tostring(id))
    if index == nil then return {} end
    local items = {}
    for _, fullType in ipairs(Creator.PACKS[index].items) do items[#items + 1] = fullType end
    return items
end

-- The catalogue is what a pack declares; the placement list is what the engine
-- can build right now. A pack naming an item whose mod is absent, or a mistyped
-- id, places the rest instead of inventing a script item that does not exist.
function Creator.packItemsForPlacement(id)
    local placed = {}
    for _, fullType in ipairs(Creator.packItems(id)) do
        if Creator.itemKnown(fullType) then placed[#placed + 1] = fullType end
    end
    return placed
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
    Creator.refreshProfessionCatalogue()
    -- Format 4 adds profile/cargo fields and lossless future-field retention.
    -- Format 3 added the group faction as an id and the player's own faction
    -- definitions. Format 2 files are still read, and anything this version does
    -- not understand is written back unchanged rather than dropped.
    local lines = { "knox-creator " .. tostring(Creator.FORMAT_VERSION) }
    group = type(group) == "table" and group or {}
    local factionId = group.factionId
    if type(factionId) ~= "string" or factionId == "" then
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
            local fields = { "def", entry.id, label }
            local policy = Creator.profileFor(entry.id, group.defs) or PROFILE_DEFAULTS
            local kindDefault = Creator.behaviourFor(policy.profile)
            for _, key in ipairs(PROFILE_FIELDS) do
                local value = entry[key]
                if value == nil then value = policy[key] end
                -- A stance equal to the kind's own default is not a choice. Writing
                -- it to the file would turn the kind's answer into a stored one that
                -- outlives a later kind change, so it is written empty and decodes
                -- as absent; an explicit stance still writes its own value.
                if key == "attitude" and kindDefault ~= nil
                    and value == kindDefault.attitude then
                    value = ""
                end
                fields[#fields + 1] = tostring(value or "")
            end
            for _, value in ipairs(entry.extraFields or {}) do fields[#fields + 1] = value end
            if entry.region and entry.region ~= "" then fields[#fields + 1] = "region=" .. encodeText(entry.region, 48) end
            lines[#lines + 1] = table.concat(fields, "|")
        end
    end
    for _, person in ipairs(roster or {}) do
        if type(person) == "table" then
            local look = indexOf(Creator.LOOKS, tostring(person.look)) or 1
            local kit = indexOf(Creator.KITS, tostring(person.kit)) or 1
            local weapon = indexOf(Creator.WEAPONS, tostring(person.weaponId)) or 1
            local savedWeapon = Creator.WEAPONS[weapon].id
            if type(person.weaponId) == "string" and person.weaponId:match("^[%w_]+%.[%w_]+$") then savedWeapon = person.weaponId end
            local profession = indexOf(Creator.PROFESSIONS, tostring(person.profession)) or 1
            local pack = indexOf(Creator.PACKS, tostring(person.pack)) or 1
            local fields = {
                "p", trim(person.name),
                Creator.LOOKS[look].id, Creator.KITS[kit].id,
                savedWeapon, Creator.PROFESSIONS[profession].id,
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
            }
            for _, value in ipairs(person.extraFields or {}) do fields[#fields + 1] = value end
            local traits = Creator.encodeTraits(person.traits)
            if traits ~= nil then fields[#fields + 1] = "traits=" .. traits end
            if person.spawnContext == "medical" then fields[#fields + 1] = "origin=medical" end
            if person.region and person.region ~= "" then fields[#fields + 1] = "region=" .. encodeText(person.region,48) end
            local skin = Creator.skinIndex(person.skin)
            if skin ~= nil then fields[#fields + 1] = "skin=" .. tostring(skin) end
            local cargo = Creator.encodeCargo(person.cargo)
            if cargo ~= "" then fields[#fields + 1] = "cargo=" .. cargo end
            local bagCargo = Creator.encodeCargo(person.bagCargo)
            if bagCargo ~= "" then fields[#fields + 1] = "bagCargo=" .. bagCargo end
            lines[#lines + 1] = table.concat(fields, "|")
        end
    end
    for _, person in ipairs(roster or {}) do
        if type(person) == "table" then
            local markedName = encodeText(trim(person.name), Creator.MAX_NAME)
            if person.startCompanion == true then
                lines[#lines + 1] = "start|" .. markedName .. "|join"
            end
            if person.startSpouse == true then
                lines[#lines + 1] = "start|" .. markedName .. "|spouse"
            end
            if person.excludeFromSpawn == true then
                lines[#lines + 1] = "start|" .. markedName .. "|nospawn"
            end
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
    Creator.refreshProfessionCatalogue()
    local roster = {}
    local group = Creator.newGroup()
    local skipped = 0
    local startMarks = {}
    local seenNames = {}
    if type(text) ~= "string" then group.readOnly = true; return roster, group, skipped end
    if text ~= "" and not string.match(text, "^knox%-creator %d+[%s\r\n]") then group.readOnly = true end
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
        if string.sub(line, -1) == "|" then fields[#fields + 1] = "" end
        local kind = tostring(fields[1] or "")
        if string.sub(kind, 1, 12) == "knox-creator" then
            local version = tonumber(string.match(kind, "^knox%-creator (%d+)$"))
            if version == nil or version < 1 or version > Creator.FORMAT_VERSION then group.readOnly = true end
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
                local entry = { id = id, label = label, user = true, extraFields = {} }
                for i, key in ipairs(PROFILE_FIELDS) do
                    local value = fields[i + 3]
                    if value and value ~= "" then entry[key] = key == "memberCount" and (tonumber(value) or value) or value end
                end
                for i = 14, #fields do
                    if fields[i]:sub(1,7) == "region=" then entry.region = fields[i]:sub(8)
                    else entry.extraFields[#entry.extraFields + 1] = fields[i] end
                end
                group.defs[#group.defs + 1] = entry
            else
                group.extras[#group.extras + 1] = line
            end
        elseif kind == "start" then
            local target = trim(fields[2])
            local mode = tostring(fields[3] or "")
            if target ~= "" and (mode == "join" or mode == "spouse" or mode == "nospawn") then
                startMarks[#startMarks + 1] = { name = target, mode = mode }
            end
        elseif kind == "p" and #roster < Creator.MAX_PEOPLE then
            local name = trim(fields[2])
            if seenNames[Creator.nameKey(name)] then
                -- One name, one record: a hand-edited duplicate is counted and
                -- kept verbatim in extras, not loaded twice. It sets no
                -- read-only flag, because a dropped duplicate is not corruption
                -- and the start marks match by name.
                skipped = skipped + 1
                group.extras[#group.extras + 1] = line
            elseif #name >= 2 and #name <= Creator.MAX_NAME then
                seenNames[Creator.nameKey(name)] = true
                local weapon = Creator.WEAPONS[indexOf(Creator.WEAPONS,
                    tostring(fields[5])) or 1]
                if type(fields[5]) == "string" and fields[5]:match("^[%w_]+%.[%w_]+$")
                    and indexOf(Creator.WEAPONS, fields[5]) == nil then
                    weapon = {id=fields[5],fullType=fields[5]}
                end
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
                    skin = 0,
                    hair = #fields >= 10 and tostring(fields[10]) or "",
                    beard = #fields >= 11 and tostring(fields[11]) or "",
                    hairColour = Creator.HAIR_COLOURS[Creator.colourIndexOf(
                        #fields >= 12 and fields[12] or "brown")].id,
                    skills = Creator.decodeSkills(#fields >= 13 and fields[13] or ""),
                    -- Only a faction this install knows becomes membership: a
                    -- hand-edited or newer id is ignored, because the faction
                    -- decides who is allied. A user definition written earlier in
                    -- the same file is known by now.
                    faction = (#fields >= 14 and fields[14] ~= "") and tostring(fields[14]) or nil,
                    slots = Creator.decodeSlots(#fields >= 15 and fields[15] or ""),
                    extraFields = {},
                }
                for i = 16, #fields do
                    if fields[i]:sub(1,7) == "traits=" then roster[#roster].traits = Creator.decodeTraits(fields[i]:sub(8))
                    elseif fields[i] == "origin=medical" then roster[#roster].spawnContext = "medical"
                    elseif fields[i]:sub(1,7) == "region=" then roster[#roster].region = fields[i]:sub(8)
                    elseif string.sub(fields[i], 1, 5) == "skin=" and Creator.skinIndex(string.sub(fields[i], 6)) ~= nil then
                        roster[#roster].skin = Creator.skinIndex(string.sub(fields[i], 6))
                    elseif string.sub(fields[i], 1, 6) == "cargo=" and roster[#roster].cargo == nil then
                        roster[#roster].cargo = Creator.decodeCargo(string.sub(fields[i], 7))
                    elseif string.sub(fields[i], 1, 9) == "bagCargo=" and roster[#roster].bagCargo == nil then
                        roster[#roster].bagCargo = Creator.decodeCargo(string.sub(fields[i], 10))
                    else
                        roster[#roster].extraFields[#roster[#roster].extraFields + 1] = fields[i]
                    end
                end
            else
                -- An unreadable record is counted, not dropped in silence: the
                -- panel tells the player how many saved people were lost.
                skipped = skipped + 1
                group.extras[#group.extras + 1] = line
                group.readOnly = true
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
    group.faction = indexOf(Creator.FACTIONS, group.factionId) or 1
    for _, mark in ipairs(startMarks) do
        for _, person in ipairs(roster) do
            if tostring(person.name) == mark.name then
                if mark.mode == "join" then
                    person.startCompanion = true
                elseif mark.mode == "spouse" then
                    person.startSpouse = true
                    person.startCompanion = false
                elseif mark.mode == "nospawn" then
                    person.excludeFromSpawn = true
                end
            end
        end
    end
    return roster, group, skipped
end


-- A failed write can truncate the destination. Keep a completely read previous
-- version before opening it; this is recovery, not an atomic filesystem write.
local function readCreatorFile(path)
    local ok, reader = pcall(function() return getFileReader(path, false) end)
    if not ok then return nil, "read_failed" end
    if reader == nil then return nil, "missing" end
    local lines = {}
    local readOk = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = line
            if #lines > 4096 then error("creator file too large") end
        end
        reader:close()
    end)
    if not readOk then return nil, "read_failed" end
    local text = table.concat(lines, "\n") .. "\n"
    local version = tonumber(string.match(text, "^knox%-creator (%d+)[\r\n]"))
    if not version or version < 1 then return nil, "invalid_file" end
    if version > Creator.FORMAT_VERSION then return nil, "unsupported_file" end
    local _, parsed = Creator.decode(text)
    if parsed.readOnly then return nil, "invalid_file" end
    return text
end

local function writeCreatorFile(path, text)
    local ok, writer = pcall(function() return getFileWriter(path, true, false) end)
    if not ok or writer == nil then return false end
    local wrote = pcall(function() writer:write(text) end)
    local closed = pcall(function() writer:close() end)
    return wrote and closed
end

Creator.BACKUPS = { Creator.FILE .. ".previous.txt", Creator.FILE .. ".previous-alt.txt" }
Creator.LEGACY_BACKUP = Creator.FILE .. ".previous"

function Creator.save(roster, group, allowRecovery)
    group = type(group) == "table" and group or Creator.newGroup()
    if group.readOnly and not (group.needsRecovery and allowRecovery == true) then return false, "read_only_file" end
    local existing, reason = readCreatorFile(Creator.FILE)
    if not existing and reason ~= "missing" and not (group.needsRecovery and allowRecovery == true) then return false, reason end
    if existing then
        -- Keep one verified recovery copy while replacing the other. A failed or
        -- truncated backup never permits the main file to be overwritten.
        local first, firstReason = readCreatorFile(Creator.BACKUPS[1])
        local second, secondReason = readCreatorFile(Creator.BACKUPS[2])
        local target
        if first then target = Creator.BACKUPS[2]
        elseif second then
            -- Re-establish the stable copy before replacing the latest copy.
            if firstReason ~= "missing" then return false, "backup_failed" end
            if not writeCreatorFile(Creator.BACKUPS[1], existing)
                or readCreatorFile(Creator.BACKUPS[1]) ~= existing then return false, "backup_failed" end
            target = Creator.BACKUPS[2]
        elseif firstReason == "missing" then target = Creator.BACKUPS[1]
        elseif secondReason == "missing" then target = Creator.BACKUPS[2]
        else return false, "backup_failed" end
        if not writeCreatorFile(target, existing) or readCreatorFile(target) ~= existing then
            return false, "backup_failed"
        end
    end
    local encoded = Creator.encode(roster, group)
    if not writeCreatorFile(Creator.FILE, encoded) then return false, "write_failed" end
    local verified = readCreatorFile(Creator.FILE)
    if verified ~= encoded then return false, "verification_failed" end
    group.readOnly, group.needsRecovery = false, false
    return true, "saved"
end

function Creator.load()
    local text, reason = readCreatorFile(Creator.FILE)
    if text then return Creator.decode(text) end
    -- A newer format must not be interpreted or replaced by an older install.
    if reason ~= "unsupported_file" then
        local previous = readCreatorFile(Creator.BACKUPS[2]) or readCreatorFile(Creator.BACKUPS[1])
            or readCreatorFile(Creator.LEGACY_BACKUP)
        if previous then
            local roster, group, skipped = Creator.decode(previous)
            group.readOnly, group.needsRecovery, group.recovered = true, true, true
            return roster, group, skipped
        end
    end
    if reason == "missing" then return {}, Creator.newGroup(), 0 end
    local group = Creator.newGroup()
    group.readOnly, group.loadError = true, reason
    return {}, group, 0
end

-- World placement installs methods on this same owner. The library stays in
-- the user folder; per-world allocation receipts stay in population state.
local CreatorWorld = rawget(_G, "KnoxCreatorWorld") or require "KS_CreatorWorld"
CreatorWorld.install(Creator)

return Creator
