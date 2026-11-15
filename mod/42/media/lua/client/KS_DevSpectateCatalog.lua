-- Pure survivor classification for the developer spectator.
--
-- No engine global is read here: the runtime gathers the recorded facts and this
-- module only decides which spectator filters a person belongs to. That makes the
-- rule drivable from the Kahlua fixture, where a camera and a body do not exist.
local Catalog = rawget(_G, "KnoxDevSpectateCatalog") or {}
_G.KnoxDevSpectateCatalog = Catalog

local FILTERS = { "any", "solo", "group", "faction", "police", "military", "other" }
local FILTER_LABELS = {
    any = "All",
    solo = "Solo",
    group = "Group",
    faction = "Faction",
    police = "Police",
    military = "Military",
    other = "Other",
}
local PRIMARY_ORDER = { solo = 1, group = 2, faction = 3, police = 4, military = 5, other = 6 }

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end

local function addTag(tags, tag)
    for _, existing in ipairs(tags) do
        if existing == tag then return end
    end
    tags[#tags + 1] = tag
end

function Catalog.filters()
    local copy = {}
    for index, value in ipairs(FILTERS) do copy[index] = value end
    return copy
end

function Catalog.filterLabel(filter)
    return FILTER_LABELS[filter] or FILTER_LABELS.any
end

function Catalog.primaryOrder(category)
    return PRIMARY_ORDER[category] or PRIMARY_ORDER.other
end

-- One recorded survivor -> the primary kind shown in a row and every filter it
-- belongs to. A police faction carries faction, group (when it travels as a
-- group) and police; the browser filter may therefore overlap on purpose.
function Catalog.describe(facts)
    facts = type(facts) == "table" and facts or {}
    local background = text(facts.factionBackground)
    if background == "" then background = text(facts.groupBackground) end
    local profile = text(facts.creatorProfile)
    local context = text(facts.originContext)
    local policy = text(facts.eventPolicy)
    local inFaction = facts.inFaction == true
    if not inFaction and type(facts.factionId) == "string" and facts.factionId ~= "" then
        inFaction = true
    end
    local members = tonumber(facts.groupMembers) or 0
    local inGroup = members >= 2
    local police = background == "law_enforcement" or background == "police"
        or profile == "police" or context == "law_enforcement" or context == "police"
    local military = background == "military" or profile == "military"
        or context == "military"
    local tags = {}
    if inFaction then addTag(tags, "faction") end
    if inGroup then addTag(tags, "group") end
    if not inFaction and not inGroup then addTag(tags, "solo") end
    if police then addTag(tags, "police") end
    if military then addTag(tags, "military") end
    if policy ~= "" and policy ~= "police" and policy ~= "military"
        and policy ~= "law_enforcement" then
        addTag(tags, "other")
    end
    local primary = "solo"
    if police then
        primary = "police"
    elseif military then
        primary = "military"
    elseif inFaction then
        primary = "faction"
    elseif inGroup then
        primary = "group"
    end
    return {
        primary = primary,
        tags = tags,
        inGroup = inGroup,
        inFaction = inFaction,
        groupMembers = members,
        police = police,
        military = military,
    }
end

function Catalog.matches(filter, described)
    if filter == nil or filter == "" or filter == "any" then return true end
    if type(described) ~= "table" or type(described.tags) ~= "table" then return false end
    for _, tag in ipairs(described.tags) do
        if tag == filter then return true end
    end
    return false
end

function Catalog.kindLabel(described, facts)
    facts = type(facts) == "table" and facts or {}
    local primary = type(described) == "table" and described.primary or "solo"
    if primary == "police" then return "Police" end
    if primary == "military" then return "Military" end
    if primary == "faction" then
        local name = text(facts.factionName)
        return name ~= "" and ("Faction: " .. name) or "Faction"
    end
    if primary == "group" then
        local name = text(facts.groupName)
        if name ~= "" then return "Group: " .. name end
        local count = tonumber(facts.groupMembers) or 0
        return count > 0 and ("Group of " .. tostring(count)) or "Group"
    end
    return "Solo"
end

return Catalog
