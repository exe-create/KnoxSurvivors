local KnoxCharacterAppearance = rawget(_G, "KnoxCharacterAppearance") or {}
_G.KnoxCharacterAppearance = KnoxCharacterAppearance

local function wear(bridge, id, fullType, replaceExisting)
    local success, result = pcall(function()
        if id == nil then
            return bridge:wearTestNpcItem(fullType)
        end
        if replaceExisting and bridge.dressNpcItem ~= nil then
            return bridge:dressNpcItem(id, fullType)
        end
        return bridge:wearNpcItem(id, fullType)
    end)
    return success and string.find(tostring(result), "WORN", 1, true) == 1, result
end

-- Uses the same default definitions and probability rule as B42's character creator.
function KnoxCharacterAppearance.randomizeNewTestSurvivor(bridge)
    return KnoxCharacterAppearance.randomizeNewSurvivor(bridge, nil)
end

local function dressDefinitions(bridge, id, definition, female, replaceExisting)
    if definition == nil then
        return true, 0
    end
    local genderDefinition = female and definition.Female
        or (definition.Male or definition.Female)
    if genderDefinition == nil then
        return true, 0
    end
    local worn = 0
    for _, selection in pairs(genderDefinition) do
        local chance = selection.chance
        if (chance == nil or ZombRand(100) < chance) and #selection.items > 0 then
            local fullType = selection.items[ZombRand(0, #selection.items) + 1]
            local success, result = wear(bridge, id, fullType, replaceExisting)
            if not success then
                return false, result
            end
            worn = worn + 1
        end
    end
    return true, worn
end

local function traitDefinition(id)
    local traits = CharacterTraitDefinition.getTraits()
    for index = 0, traits:size() - 1 do
        local definition = traits:get(index)
        if definition ~= nil and tostring(definition:getType()) == id then
            return definition
        end
    end
    return nil
end

function KnoxCharacterAppearance.randomizeNewSurvivor(bridge, id, capabilities, appearanceItems)
    if ClothingSelectionDefinitions == nil or ClothingSelectionDefinitions.default == nil then
        return false, "character_creator_definitions_unavailable"
    end

    local female
    if id == nil then
        female = bridge:isTestNpcFemale()
    else
        female = bridge:isNpcFemale(id)
    end
    local success, worn = dressDefinitions(
        bridge,
        id,
        ClothingSelectionDefinitions.default,
        female,
        false
    )
    if not success then
        return false, worn
    end

    local professionId = capabilities ~= nil and capabilities.professionId or nil
    local professionKey = professionId ~= nil
        and string.match(professionId, "([^:]+)$")
        or nil
    local professionDefinition = professionKey ~= nil
        and ClothingSelectionDefinitions[professionKey]
        or nil
    local professionOk, professionWorn = dressDefinitions(
        bridge,
        id,
        professionDefinition,
        female,
        true
    )
    if not professionOk then
        return false, professionWorn
    end
    worn = worn + professionWorn

    for _, appearanceItem in ipairs(appearanceItems or {}) do
        local themedOk, themedResult = wear(bridge, id, appearanceItem, true)
        if not themedOk then return false, themedResult end
        worn = worn + 1
    end

    if TraitClothingSelectionDefinitions ~= nil then
        for _, traitId in ipairs(capabilities ~= nil and capabilities.traitIds or {}) do
            local trait = traitDefinition(traitId)
            local definition = trait ~= nil
                and TraitClothingSelectionDefinitions[trait:getType()]
                or nil
            local traitOk, traitWorn = dressDefinitions(
                bridge,
                id,
                definition,
                female,
                true
            )
            if not traitOk then
                return false, traitWorn
            end
            worn = worn + traitWorn
        end
    end

    -- A restrained extra roll gives some survivors plausible carried capacity at origin.
    local bag = "none"
    local testConfig = rawget(_G, "KnoxDevTests")
    local forceStarterBag = testConfig ~= nil and testConfig.forceStarterBag == true
    if forceStarterBag or ZombRand(100) < 15 then
        bag = ZombRand(4) == 0 and "Base.Bag_DuffelBagTINT" or "Base.Bag_Schoolbag"
        local success, result = wear(bridge, id, bag, false)
        if not success then
            return false, result
        end
        worn = worn + 1
    end

    return true,
        "gender=" .. (female and "female" or "male")
            .. " worn=" .. tostring(worn)
            .. " bag=" .. bag
end

-- Creator look. The randomizer rolls clothes from the same definitions vanilla
-- uses; a player-made look is not a roll, so each chosen item is worn in order
-- with the same bridge call and the first refusal is reported instead of being
-- swallowed into a half-dressed body.
function KnoxCharacterAppearance.applyLook(bridge, id, items)
    if type(items) ~= "table" or #items == 0 then return true, "no_look" end
    local worn = 0
    for _, fullType in ipairs(items) do
        local ok, result = wear(bridge, id, fullType, true)
        if not ok then return false, tostring(result) end
        worn = worn + 1
    end
    return true, "worn=" .. tostring(worn)
end

-- A created person's face, clothes, weapon and skills. Hair and beard are the
-- engine's own HumanVisual models, so the body wears what the preview showed;
-- clothing still goes through the one item-wear path above, and every level is
-- written through the character's own experience owner.
function KnoxCharacterAppearance.applyCreator(bridge, id, character, record)
    if type(record) ~= "table" then return true, "no_record" end
    local faceEvidence = "face=none"
    if type(record.hair) == "string" or type(record.beard) == "string" then
        local ok, result = pcall(function()
            if character == nil or character.getHumanVisual == nil then
                return false
            end
            local visual = character:getHumanVisual()
            if visual == nil then return false end
            if type(record.hair) == "string" then
                visual:setHairModel(record.hair ~= "" and record.hair or nil)
            end
            if type(record.beard) == "string" then
                visual:setBeardModel(record.beard ~= "" and record.beard or nil)
            end
            local rgb = type(record.hairColour) == "string"
                and KnoxCreator ~= nil and KnoxCreator.colourOf(record.hairColour)
                or nil
            if rgb ~= nil and ImmutableColor ~= nil then
                local colour = ImmutableColor.new(rgb[1], rgb[2], rgb[3])
                visual:setHairColor(colour)
                visual:setBeardColor(colour)
                visual:setNaturalHairColor(colour)
                visual:setNaturalBeardColor(colour)
            end
            return true
        end)
        faceEvidence = ok and result ~= false and "face=set" or "face=refused"
    end
    local clothesEvidence = "look=none"
    if record.look ~= nil and KnoxCreator ~= nil then
        -- The preset with the person's per-slot choices swapped in. The model
        -- owns that merge, so the same list is what the card previewed.
        local lookOk, lookResult = KnoxCharacterAppearance.applyLook(
            bridge, id, KnoxCreator.lookItemsFromRecord(record))
        if not lookOk then return false, tostring(lookResult) end
        clothesEvidence = "look=" .. tostring(lookResult)
    end
    -- Skills are written only where the experience owner exists, so a body that
    -- is still loading is reported instead of being silently levelled later.
    -- A bag is worn, not dressed: the randomizer already puts a starter bag on
    -- a body with this exact call, so the creator uses the same one. It is read
    -- from the record, or from the slot table an older record already carries.
    local bagEvidence = "bag=none"
    local bag = type(record.bag) == "string" and record.bag or nil
    if bag == nil and type(record.slots) == "string" and KnoxCreator ~= nil
        and KnoxCreator.bagFromSlots ~= nil then
        local choice = KnoxCreator.bagFromSlots(KnoxCreator.decodeSlots(record.slots))
        bag = choice ~= nil and choice.fullType or nil
    end
    if bag ~= nil and bag ~= "" then
        local bagOk, bagResult = wear(bridge, id, bag, false)
        if not bagOk then return false, "bag=" .. tostring(bagResult) end
        bagEvidence = "bag=" .. bag
    end
    local skillsEvidence = "skills=none"
    if type(record.skills) == "string" and record.skills ~= ""
        and character ~= nil and character.getXp ~= nil and Perks ~= nil
        and KnoxCreator ~= nil then
        local applied = 0
        for perkId, level in pairs(KnoxCreator.decodeSkills(record.skills)) do
            local ok = pcall(function()
                local perk = Perks.FromString(perkId)
                if perk ~= nil then
                    character:getXp():setXPToLevel(perk, level)
                    applied = applied + 1
                end
            end)
            if not ok then return false, "skill_refused=" .. tostring(perkId) end
        end
        skillsEvidence = "skills=" .. tostring(applied)
    end
    return true, faceEvidence .. " " .. clothesEvidence .. " "
        .. bagEvidence .. " " .. skillsEvidence
end

return KnoxCharacterAppearance
