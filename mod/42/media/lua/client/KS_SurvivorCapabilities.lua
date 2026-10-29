require "KS_Persistence"
require "KS_SurvivorOrigins"

local Capabilities = rawget(_G, "KnoxSurvivorCapabilities") or {}
_G.KnoxSurvivorCapabilities = Capabilities

local PROFILE_VERSION = 1
local appliedCharacters = setmetatable({}, { __mode = "k" })

local function hash(text)
    local value = 216613
    for index = 1, #text do
        value = (value * 167 + string.byte(text, index)) % 2147483647
    end
    return value
end

local function orderedDefinitions(javaList, idOf)
    local values = {}
    if javaList == nil then
        return values
    end
    for index = 0, javaList:size() - 1 do
        local definition = javaList:get(index)
        if definition ~= nil then
            values[#values + 1] = { value = definition, id = idOf(definition) }
        end
    end
    table.sort(values, function(first, second)
        return first.id < second.id
    end)
    for index, entry in ipairs(values) do values[index] = entry.value end
    return values
end

local function professionId(definition)
    return tostring(definition:getType())
end

local function traitId(definition)
    return tostring(definition:getType())
end

local function ranked(values, survivorId, salt, idOf)
    local copied = {}
    for _, value in ipairs(values) do
        local id = idOf(value)
        copied[#copied + 1] = {
            value = value, id = id, rank = hash(survivorId .. ":" .. salt .. ":" .. id),
        }
    end
    table.sort(copied, function(first, second)
        if first.rank == second.rank then
            return first.id < second.id
        end
        return first.rank < second.rank
    end)
    for index, entry in ipairs(copied) do copied[index] = entry.value end
    return copied
end

local function contains(ids, id)
    for _, existing in ipairs(ids) do
        if existing == id then
            return true
        end
    end
    return false
end

local function findProfession(id)
    local definitions = CharacterProfessionDefinition.getProfessions()
    for index = 0, definitions:size() - 1 do
        local definition = definitions:get(index)
        if definition ~= nil and professionId(definition) == id then
            return definition
        end
    end
    return nil
end

local function findTrait(id)
    local definitions = CharacterTraitDefinition.getTraits()
    for index = 0, definitions:size() - 1 do
        local definition = definitions:get(index)
        if definition ~= nil and traitId(definition) == id then
            return definition
        end
    end
    return nil
end

local function conflicts(definition, selectedDefinitions)
    for _, selected in ipairs(selectedDefinitions) do
        if definition:isMutuallyExclusive(selected) then
            return true
        end
    end
    return false
end

local function appendGrantedTraits(definition, ids, selectedDefinitions)
    local granted = definition ~= nil and definition:getGrantedTraits() or nil
    if granted == nil then
        return
    end
    for index = 0, granted:size() - 1 do
        local grantedDefinition = CharacterTraitDefinition.getCharacterTraitDefinition(
            granted:get(index)
        )
        if grantedDefinition ~= nil then
            local id = traitId(grantedDefinition)
            if not contains(ids, id) then
                ids[#ids + 1] = id
                selectedDefinitions[#selectedDefinitions + 1] = grantedDefinition
                appendGrantedTraits(grantedDefinition, ids, selectedDefinitions)
            end
        end
    end
end

local function distanceFromValidPoints(points)
    if points < 0 then
        return -points
    end
    if points > 3 then
        return points - 3
    end
    return 0
end

local function addTrait(definition, selectedIds, selectedDefinitions)
    local id = traitId(definition)
    if contains(selectedIds, id) or conflicts(definition, selectedDefinitions) then
        return false
    end
    selectedIds[#selectedIds + 1] = id
    selectedDefinitions[#selectedDefinitions + 1] = definition
    appendGrantedTraits(definition, selectedIds, selectedDefinitions)
    return true
end

local function profileForProfession(id, profession, allTraits)
    local positive = {}
    local negative = {}
    for _, definition in ipairs(allTraits) do
        if not definition:isFree()
            and (not isMultiplayer() or not definition:isDisabledInMultiplayer()) then
            if definition:getCost() > 0 then
                positive[#positive + 1] = definition
            elseif definition:getCost() < 0 then
                negative[#negative + 1] = definition
            end
        end
    end

    local selectedIds = {}
    local selectedDefinitions = {}
    appendGrantedTraits(profession, selectedIds, selectedDefinitions)
    local points = tonumber(profession:getCost()) or 0
    local negativeTarget = hash(id .. ":negative-count") % 5
    for _, definition in ipairs(ranked(negative, id, "negative", traitId)) do
        if negativeTarget <= 0 and points >= 0 then
            break
        end
        if addTrait(definition, selectedIds, selectedDefinitions) then
            points = points - definition:getCost()
            negativeTarget = negativeTarget - 1
        end
    end

    local positiveTarget = hash(id .. ":positive-count") % 5
    for _, definition in ipairs(ranked(positive, id, "positive", traitId)) do
        if positiveTarget <= 0 and points <= 3 then
            break
        end
        if definition:getCost() <= points
            and addTrait(definition, selectedIds, selectedDefinitions) then
            points = points - definition:getCost()
            positiveTarget = positiveTarget - 1
        end
    end

    -- Vanilla's creator has a rescue loop because an initial random set can
    -- overspend or leave too many points. Do the same deterministically so a
    -- survivor is never lost merely because its first trait mix did not balance.
    local rescue = 100
    while distanceFromValidPoints(points) > 0 and rescue > 0 do
        rescue = rescue - 1
        local candidates = points < 0 and negative or positive
        local best = nil
        local bestDistance = distanceFromValidPoints(points)
        for _, definition in ipairs(ranked(candidates, id, "rescue-" .. rescue, traitId)) do
            local cost = tonumber(definition:getCost()) or 0
            local nextPoints = points - cost
            local nextDistance = distanceFromValidPoints(nextPoints)
            if not contains(selectedIds, traitId(definition))
                and not conflicts(definition, selectedDefinitions)
                and (best == nil or nextDistance < bestDistance) then
                best = definition
                bestDistance = nextDistance
                if nextDistance == 0 then
                    break
                end
            end
        end
        if best == nil or not addTrait(best, selectedIds, selectedDefinitions) then
            break
        end
        points = points - best:getCost()
    end
    if points < 0 or points > 3 then
        return nil, points
    end
    table.sort(selectedIds)
    return {
        version = PROFILE_VERSION,
        professionId = professionId(profession),
        traitIds = selectedIds,
        skills = {},
        generatedBy = "vanilla-definitions",
        unspentPoints = points,
    }
end

function Capabilities.generate(id, preferredProfessionId)
    if type(id) ~= "string" or id == "" then
        return nil, "invalid_survivor_id"
    end
    local professions = orderedDefinitions(
        CharacterProfessionDefinition.getProfessions(),
        professionId
    )
    if #professions == 0 then
        return nil, "profession_definitions_unavailable"
    end
    professions = ranked(professions, id, "profession", professionId)
    local allTraits = orderedDefinitions(CharacterTraitDefinition.getTraits(), traitId)
    local lastPoints = nil
    if preferredProfessionId ~= nil then
        local preferred = findProfession(preferredProfessionId)
        if preferred == nil then
            return nil, "preferred_profession_missing=" .. tostring(preferredProfessionId)
        end
        local profile, remaining = profileForProfession(id, preferred, allTraits)
        if profile ~= nil then return profile, "generated_preferred" end
        return nil, "unable_to_balance_preferred_profession="
            .. tostring(preferredProfessionId) .. " points=" .. tostring(remaining)
    end
    for _, profession in ipairs(professions) do
        local profile, remaining = profileForProfession(id, profession, allTraits)
        if profile ~= nil then
            return profile, "generated"
        end
        lastPoints = remaining
    end
    return nil, "unable_to_balance_vanilla_points=" .. tostring(lastPoints)
end

local function nutritionSnapshot(character)
    local nutrition = character:getNutrition()
    return {
        carbohydrates = nutrition:getCarbohydrates(),
        proteins = nutrition:getProteins(),
        calories = nutrition:getCalories(),
        lipids = nutrition:getLipids(),
        weight = nutrition:getWeight(),
    }
end

local function restoreNutrition(character, snapshot)
    if snapshot == nil then
        return
    end
    local nutrition = character:getNutrition()
    nutrition:setCarbohydrates(snapshot.carbohydrates)
    nutrition:setProteins(snapshot.proteins)
    nutrition:setCalories(snapshot.calories)
    nutrition:setLipids(snapshot.lipids)
    nutrition:setWeight(snapshot.weight)
end

local function applyIdentity(character, profile, preservePhysiology)
    local profession = findProfession(profile.professionId)
    if profession == nil then
        return false, "profession_missing=" .. tostring(profile.professionId)
    end
    local descriptor = character:getDescriptor()
    descriptor:setCharacterProfession(profession:getType())
    descriptor:setProfessionSkills(profession)

    local knownTraits = character:getCharacterTraits():getKnownTraits()
    knownTraits:clear()
    for _, id in ipairs(profile.traitIds or {}) do
        local definition = findTrait(id)
        if definition ~= nil then
            knownTraits:add(definition:getType())
        end
    end
    local nutrition = preservePhysiology and nutritionSnapshot(character) or nil
    character:applyTraits(knownTraits)
    restoreNutrition(character, nutrition)
    character:applyProfessionRecipes()
    character:applyCharacterTraitsRecipes()
    return true, profession
end

local function restoreSkills(character, skills)
    if type(skills) ~= "table" then
        return
    end
    for perkId, saved in pairs(skills) do
        local perk = Perks.FromString(perkId)
        if perk ~= nil and type(saved) == "table" then
            local level = math.max(0, math.min(10, tonumber(saved.level) or 0))
            character:setPerkLevelDebug(perk, level)
            character:getXp():setXPToLevel(perk, level)
            local current = character:getXp():getXP(perk)
            local desired = math.max(current, tonumber(saved.xp) or current)
            if desired > current then
                character:getXp():AddXPNoMultiplier(perk, desired - current)
            end
        end
    end
end

function Capabilities.ensure(id, character, initializeNew, preferredProfessionId)
    local profile = KnoxPersistence.getSurvivorCapabilities(id)
    local result = "existing"
    if profile == nil then
        profile, result = Capabilities.generate(id, preferredProfessionId)
        if profile == nil or not KnoxPersistence.setSurvivorCapabilities(id, profile) then
            return nil, result
        end
    end
    if character ~= nil and not appliedCharacters[character] then
        local applied, evidence = applyIdentity(
            character,
            profile,
            initializeNew ~= true
        )
        if not applied then
            return nil, evidence
        end
        restoreSkills(character, profile.skills)
        appliedCharacters[character] = true
    end
    return profile, result
end

-- Capability precedence is centralized here so population allocation and
-- first materialization cannot disagree. Authored event professions are
-- strict. Contextual spawn/building evidence is advisory and may fall through
-- to another candidate or the ordinary deterministic vanilla roll.
function Capabilities.ensureForOrigin(
    id,
    character,
    initializeNew,
    eventProfessionId,
    origin
)
    local existing = KnoxPersistence.getSurvivorCapabilities(id)
    if existing ~= nil then
        return Capabilities.ensure(id, character, initializeNew)
    end
    if eventProfessionId ~= nil then
        return Capabilities.ensure(id, character, initializeNew, eventProfessionId)
    end
    local lastReason = nil
    local candidates = KnoxSurvivorOrigins.professionCandidates(origin, id)
    for _, professionId in ipairs(candidates) do
        local profile, reason = Capabilities.ensure(
            id,
            character,
            initializeNew,
            professionId
        )
        if profile ~= nil then return profile, "contextual:" .. tostring(reason) end
        lastReason = reason
    end
    local profile, reason = Capabilities.ensure(id, character, initializeNew)
    if profile ~= nil then
        return profile, #candidates > 0 and "context_fallback:" .. tostring(reason)
            or reason
    end
    return nil, reason or lastReason
end

function Capabilities.capture(id, character)
    local profile = KnoxPersistence.getSurvivorCapabilities(id)
    if profile == nil or character == nil then
        return false
    end
    local previous = profile.skills
    local skills = {}
    for index = 1, Perks.getMaxIndex() do
        local perk = PerkFactory.getPerk(Perks.fromIndex(index - 1))
        if perk ~= nil and perk:getParent() ~= Perks.None then
            local level = character:getPerkLevel(perk)
            local xp = character:getXp():getXP(perk)
            if level > 0 or xp > 0 then
                skills[tostring(perk:getId())] = {
                    level = level,
                    xp = xp,
                }
            end
        end
    end
    profile.skills = skills
    profile.capturedAtHours = getGameTime() ~= nil
        and getGameTime():getWorldAgeHours()
        or 0
    local saved = KnoxPersistence.setSurvivorCapabilities(id, profile)
    -- Survivors level exactly like the player: native actions award XP to
    -- the performing body, capture persists it, restore re-applies it. The
    -- only missing piece was visibility, so announce level-ups here where
    -- the before/after evidence is in hand.
    if saved and type(previous) == "table" then
        local ups = {}
        for perkId, savedSkill in pairs(skills) do
            if type(savedSkill) == "table" then
                local before = previous[perkId]
                local beforeLevel = type(before) == "table"
                    and (tonumber(before.level) or 0) or 0
                local afterLevel = tonumber(savedSkill.level) or 0
                if afterLevel > beforeLevel then
                    ups[#ups + 1] = tostring(perkId) .. " " .. tostring(afterLevel)
                end
            end
        end
        if #ups > 0 then
            table.sort(ups)
            local name = tostring(id)
            pcall(function()
                local persistence = rawget(_G, "KnoxPersistence")
                local identity = persistence ~= nil
                    and persistence.getSurvivorIdentity ~= nil
                    and persistence.getSurvivorIdentity(id) or nil
                if type(identity) == "table" and identity.name ~= nil then
                    name = tostring(identity.name)
                elseif type(identity) == "table" and identity.firstName ~= nil then
                    name = tostring(identity.firstName)
                end
            end)
            local shown = {}
            for index = 1, math.min(3, #ups) do shown[#shown + 1] = ups[index] end
            local text = name .. " reached " .. table.concat(shown, ", ")
            if #ups > 3 then
                text = text .. " (+" .. tostring(#ups - 3) .. " more)"
            end
            pcall(function()
                local feed = rawget(_G, "KnoxActivityFeed")
                if feed ~= nil and feed.event ~= nil then
                    feed.event(text .. ".")
                end
            end)
            pcall(function()
                local log = rawget(_G, "KnoxDebugLog")
                if log ~= nil and log.log ~= nil then
                    log.log("skills", id, "level_up", { gains = table.concat(ups, ",") })
                end
            end)
        end
    end
    return saved
end

function Capabilities.professionLabel(profile)
    local definition = profile ~= nil and findProfession(profile.professionId) or nil
    return definition ~= nil and tostring(definition:getUIName()) or "Survivor"
end

function Capabilities.hasTrait(profile, id)
    return profile ~= nil and contains(profile.traitIds or {}, id)
end

function Capabilities.skillLevel(profile, perkId)
    local saved = profile ~= nil and profile.skills ~= nil and profile.skills[perkId] or nil
    return saved ~= nil and tonumber(saved.level) or 0
end

return Capabilities
