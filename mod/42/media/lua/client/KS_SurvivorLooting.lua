require "KS_SurvivorNeeds"

local Looting = rawget(_G, "KnoxSurvivorLooting") or {}
_G.KnoxSurvivorLooting = Looting

local ESSENTIAL_TOOLS = {
    ["Base.Axe"] = true,
    ["Base.HandAxe"] = true,
    ["Base.Hammer"] = true,
    ["Base.Saw"] = true,
    ["Base.Screwdriver"] = true,
    ["Base.Wrench"] = true,
    ["Base.LugWrench"] = true,
    ["Base.Jack"] = true,
    ["Base.TirePump"] = true,
}

local MEDICAL_TYPES = {
    ["Base.AlcoholWipes"] = true,
    ["Base.BottleDisinfectant"] = true,
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.SutureNeedle"] = true,
    ["Base.Tweezers"] = true,
}

-- Base-value materials worth hauling home for the group even when the
-- carrier personally needs nothing. Ordered looting (loot_area, loot
-- building, loot corpses, raid/event takes) plans for the group; idle
-- self-scavenging stays personal so survivors do not hoard.
local GROUP_MATERIALS = {
    ["Base.Plank"] = true,
    ["Base.Nails"] = true,
    ["Base.NailsBox"] = true,
    ["Base.Log"] = true,
    ["Base.Hinge"] = true,
    ["Base.Doorknob"] = true,
    ["Base.SheetMetal"] = true,
    ["Base.Screws"] = true,
    ["Base.Wire"] = true,
    ["Base.Twine"] = true,
}

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then return value end
    return fallback
end

function Looting.isEssentialTool(item)
    local fullType = item ~= nil and safe(function() return item:getFullType() end, nil) or nil
    return fullType ~= nil and ESSENTIAL_TOOLS[fullType] == true
        and not safe(function() return item:isBroken() end, false)
end

local function usableItem(item)
    return item ~= nil and tostring(item) ~= "null"
end

local function isWeapon(item)
    return usableItem(item) and safe(function() return item:IsWeapon() end, false)
end

local function isContainer(item)
    return usableItem(item) and safe(function() return item:IsInventoryContainer() end, false)
end

local function isClothing(item)
    return usableItem(item) and safe(function() return item:IsClothing() end, false)
end

local function itemType(item)
    return usableItem(item) and safe(function() return item:getFullType() end, nil) or nil
end

local function canBandage(item)
    return item ~= nil and safe(function() return item:isCanBandage() end, false)
end

function Looting.isMedicalSupply(item)
    local fullType = itemType(item)
    return canBandage(item) or (fullType ~= nil and MEDICAL_TYPES[fullType] == true)
end

local function safeFood(item)
    return safe(function() return KnoxSurvivorNeeds.isSafeFood(item) end, false)
end

local function waterItem(item, allowTainted)
    return safe(function() return KnoxSurvivorNeeds.isWaterItem(item, allowTainted) end, false)
end

local function wearableLocation(item)
    local location = item ~= nil and safe(function() return item:getBodyLocation() end, nil) or nil
    if location ~= nil then return location end
    return item ~= nil and safe(function() return item:canBeEquipped() end, nil) or nil
end

local function walkInventory(container, visitor, seen, depth)
    seen, depth = seen or {}, depth or 0
    if container == nil or seen[container] or depth > 32 then return end
    seen[container] = true
    local items = container ~= nil and safe(function() return container:getItems() end, nil) or nil
    if items == nil then return end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if usableItem(item) then
            visitor(item)
            if isContainer(item) then
                walkInventory(safe(function() return item:getInventory() end, nil), visitor, seen, depth + 1)
            end
        end
    end
end

local function weaponScore(item)
    if not isWeapon(item) or safe(function() return item:isRanged() end, true)
        or safe(function() return item:isBroken() end, true) then
        return nil
    end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax
        or 0
    return ((safe(function() return item:getMinDamage() end, 0)
            + safe(function() return item:getMaxDamage() end, 0)) * 5)
        + condition * 5
        + safe(function() return item:getMaxRange() end, 0)
        + safe(function() return item:getBaseSpeed() end, 0)
end

local function firearmScore(item)
    if not isWeapon(item) or not safe(function() return item:isRanged() end, false)
        or safe(function() return item:isBroken() end, true) then
        return nil
    end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax
        or 0
    return safe(function() return item:getMaxRange() end, 0) * 2
        + safe(function() return item:getMaxDamage() end, 0) * 10
        + condition * 5
end

local function isMagazine(item)
    if item == nil then
        return false
    end
    local success, result = pcall(function()
        return item:getAmmoType() ~= nil and item:getMaxAmmo() > 0 and not item:IsWeapon()
    end)
    return success and result == true
end

-- Build 42.20.3 exposes ammunition through the authoritative AMMO item tag.
-- InventoryItem does not define isAmmo(), and probing that absent method with
-- pcall still writes a Kahlua exception before pcall returns.
local function isAmmo(item)
    return usableItem(item)
        and rawget(_G, "ItemTag") ~= nil
        and ItemTag.AMMO ~= nil
        and item:hasTag(ItemTag.AMMO) == true
end

local function clothingScore(item)
    if not isClothing(item) or safe(function() return item:getBodyLocation() end, nil) == nil then
        return nil
    end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax
        or 0
    return safe(function() return item:getBiteDefense() end, 0) * 0.08
        + safe(function() return item:getScratchDefense() end, 0) * 0.04
        + safe(function() return item:getInsulation() end, 0) * 2
        + condition * 3
end

local function bagScore(item)
    if not isContainer(item) then
        return nil
    end
    return safe(function() return item:getCapacity() end, 0)
        + safe(function() return item:getWeightReduction() end, 0) * 0.15
end

local function inventoryFacts(character)
    local facts = {
        bestWeapon = -math.huge,
        firearms = 0,
        ammunition = 0,
        magazines = 0,
        food = 0,
        water = 0,
        bandages = 0,
        medical = 0,
        fullTypes = {},
        counts = {},
    }
    walkInventory(character:getInventory(), function(item)
        local fullType = itemType(item)
        if fullType == nil then return end
        facts.fullTypes[fullType] = true
        facts.counts[fullType] = (facts.counts[fullType] or 0) + 1
        local score = weaponScore(item)
        if score ~= nil then
            facts.bestWeapon = math.max(facts.bestWeapon, score)
        end
        if firearmScore(item) ~= nil then
            facts.firearms = facts.firearms + 1
        end
        if isAmmo(item) then
            facts.ammunition = facts.ammunition + 1
        end
        if isMagazine(item) then
            facts.magazines = facts.magazines + 1
        end
        if safeFood(item) then
            facts.food = facts.food + 1
        end
        if waterItem(item, true) then
            facts.water = facts.water + 1
        end
        if canBandage(item) then
            facts.bandages = facts.bandages + 1
        end
        if MEDICAL_TYPES[fullType] then
            facts.medical = facts.medical + 1
        end
    end)
    return facts
end

local function candidateScore(character, facts, item, forGroup)
    local firearm = firearmScore(item)
    if firearm ~= nil and facts.firearms < 1 then
        return 62 + firearm, "firearm"
    end
    if isAmmo(item) and facts.ammunition < 30 then
        return 42, "ammunition"
    end
    if isMagazine(item) and facts.magazines < 2 then
        return 44, "magazine"
    end
    local weapon = weaponScore(item)
    if weapon ~= nil and weapon > facts.bestWeapon + 0.25 then
        return 100 + weapon - math.max(0, facts.bestWeapon), "weapon_upgrade"
    end
    local location = wearableLocation(item)
    if isClothing(item) and location ~= nil then
        local worn = character:getWornItem(location)
        local current = clothingScore(worn) or -1
        local candidate = clothingScore(item)
        if candidate ~= nil and candidate > current + 0.5 then
            return 70 + candidate - math.max(0, current), "clothing_upgrade"
        end
    end
    if isContainer(item) and location ~= nil then
        local worn = character:getWornItem(location)
        local candidate = bagScore(item)
        local current = bagScore(worn) or -1
        if candidate ~= nil and candidate > current + 1 then
            return 65 + candidate - math.max(0, current), "bag_upgrade"
        end
    end
    if canBandage(item) and facts.bandages < 3 then
        return 60 + safe(function() return item:getBandagePower() end, 0), "medical_stock"
    end
    local fullType = itemType(item)
    if fullType ~= nil and MEDICAL_TYPES[fullType] and facts.medical < 4
        and not facts.fullTypes[fullType] then
        return 55, "medical_stock"
    end
    if waterItem(item, false) and facts.water < 2 then
        return 50, "water_stock"
    end
    if safeFood(item) and facts.food < 4 then
        return 45 + math.abs(safe(function() return item:getHungerChange() end, 0)), "food_stock"
    end
    if fullType ~= nil and ESSENTIAL_TOOLS[fullType] and not facts.fullTypes[fullType] then
        return 40, "tool_stock"
    end
    if forGroup == true then
        -- Ordered looting serves the group, not the carrier's pockets. A
        -- geared survivor still strips food, water, medicine, ammunition,
        -- spare tools, and building materials for the base.
        if isAmmo(item) or isMagazine(item) then
            return 40, "group_ammunition"
        end
        if safeFood(item) then
            return 44, "group_food"
        end
        if waterItem(item, false) then
            return 44, "group_water"
        end
        if canBandage(item) then
            return 44, "group_medical"
        end
        local groupType = itemType(item)
        if groupType ~= nil then
            if MEDICAL_TYPES[groupType] then
                return 44, "group_medical"
            end
            if ESSENTIAL_TOOLS[groupType]
                and not safe(function() return item:isBroken() end, false) then
                return 40, "group_tool"
            end
            if GROUP_MATERIALS[groupType] then
                return 38, "group_material"
            end
        end
    end
    return nil, nil
end

local function applySelectedFacts(facts, item)
    local weapon = weaponScore(item)
    if weapon ~= nil then
        facts.bestWeapon = math.max(facts.bestWeapon, weapon)
    end
    if firearmScore(item) ~= nil then
        facts.firearms = facts.firearms + 1
    end
    if isAmmo(item) then
        facts.ammunition = facts.ammunition + 1
    end
    if isMagazine(item) then
        facts.magazines = facts.magazines + 1
    end
    if safeFood(item) then
        facts.food = facts.food + 1
    end
    if waterItem(item, true) then
        facts.water = facts.water + 1
    end
    if canBandage(item) then
        facts.bandages = facts.bandages + 1
    end
    local fullType = itemType(item)
    if fullType ~= nil and MEDICAL_TYPES[fullType] then
        facts.medical = facts.medical + 1
    end
    if fullType ~= nil then facts.fullTypes[fullType] = true end
end

function Looting.plan(character, container, maximumItems, forGroup, options)
    if character == nil or container == nil then
        return {}
    end
    local groupMode = forGroup == true
    local foodOnly = type(options) == "table" and options.foodOnly == true
    local facts = inventoryFacts(character)
    local candidates = {}
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if not foodOnly or safeFood(item) then
            local score, reason = candidateScore(character, facts, item, groupMode)
            if score ~= nil then
                candidates[#candidates + 1] = { item = item, score = score, reason = reason }
            end
        end
    end
    table.sort(candidates, function(first, second)
        return first.score > second.score
    end)
    local selected = {}
    local categoryCounts = {}
    local limit = math.max(1, math.min(4, maximumItems or 3))
    local remainingCapacity = math.max(
        0,
        character:getInventory():getFreeCapacity(character)
    )
    for _, candidate in ipairs(candidates) do
        local currentScore, currentReason = candidateScore(
            character,
            facts,
            candidate.item,
            groupMode
        )
        local weight = math.max(0, safe(function()
            return candidate.item:getUnequippedWeight()
        end, math.huge))
        if currentScore ~= nil and currentReason == candidate.reason
            and weight <= remainingCapacity + 0.001 then
            local category = candidate.reason
            local categoryLimit = (category == "weapon_upgrade"
                or category == "bag_upgrade"
                or category == "clothing_upgrade") and 1 or limit
            local alreadySelected = categoryCounts[category] or 0
            if alreadySelected < categoryLimit then
                selected[#selected + 1] = candidate
                categoryCounts[category] = alreadySelected + 1
                remainingCapacity = math.max(0, remainingCapacity - weight)
                applySelectedFacts(facts, candidate.item)
                if #selected >= limit then
                    break
                end
            end
        end
    end
    return selected
end

function Looting.equipUpgrade(character, item)
    if character == nil or item == nil then
        return false
    end
    local location = safe(function() return item:getBodyLocation() end, nil)
    if isContainer(item) and location ~= nil then
        local current = character:getWornItem(location)
        local candidateScoreValue = bagScore(item)
        local currentScoreValue = bagScore(current)
        if current == nil or (candidateScoreValue ~= nil
            and candidateScoreValue > (currentScoreValue or -1) + 1) then
            character:setWornItem(location, item)
            character:resetModelNextFrame()
            return true
        end
    elseif isClothing(item) and location ~= nil then
        local current = character:getWornItem(location)
        local candidateScoreValue = clothingScore(item)
        local currentScoreValue = clothingScore(current)
        if current == nil or (candidateScoreValue ~= nil
            and candidateScoreValue > (currentScoreValue or -1) + 0.5) then
            character:setWornItem(location, item)
            character:resetModelNextFrame()
            return true
        end
    end
    return false
end

-- Utility is a retention preference, not a currency price. Unknown/modded items
-- fail closed until their purpose is understood; never assume they are rubbish.
function Looting.itemUtility(character, item, facts, requirements, atBase)
    local full = itemType(item)
    if full == nil then return nil, "unknown_item" end
    if full:sub(1, 5) ~= "Base." then return nil, "unclassified_mod_item" end
    if safe(function() return item:isFavorite() end, true)
        or safe(function() return character:isEquipped(item) end, true)
        or (character.isAttachedItem ~= nil and character:isAttachedItem(item))
        or safe(function() return character:isHandItem(item) end, true) then
        return nil, "equipped_or_favorite"
    end
    if requirements ~= nil and (tonumber(requirements[full]) or 0) > 0 then
        return nil, "task_resource"
    end
    local category = item.getDisplayCategory ~= nil and tostring(item:getDisplayCategory()) or ""
    if category == "Accessory" or category == "Jewelry" or category == "Currency" or category == "Key"
        or full:find("Wallet", 1, true) or full == "Base.Money" or full == "Base.MoneyBundle"
        or full == "Base.GoldCoin" or full == "Base.SilverCoin"
        or full == "Base.GoldBar" or full == "Base.SmallGoldBar" then
        return nil, "valuable"
    end
    if canBandage(item) or MEDICAL_TYPES[full] then
        local limit = canBandage(item) and 4 or 2
        if atBase and (facts.counts[full] or 0) > limit then return 50, "surplus_medical", false end
        return nil, "medical_reserve"
    end
    if isAmmo(item) or isMagazine(item) then
        local limit = isMagazine(item) and 2 or 40
        if atBase and (facts.counts[full] or 0) > limit then return 55, "surplus_ammunition", false end
        return nil, "ammunition_reserve"
    end
    if ESSENTIAL_TOOLS[full] and not safe(function() return item:isBroken() end, false) then
        if atBase and (facts.counts[full] or 0) > 1 then return 50, "spare_tool", false end
        return nil, "essential_tool"
    end
    if safeFood(item) then
        if facts.food <= 4 then return nil, "food_reserve" end
        return 50, "surplus_food", false
    end
    if waterItem(item, true) then
        if facts.water <= 2 then return nil, "water_reserve" end
        return 55, "surplus_water", false
    end
    if isContainer(item) then
        local contents = safe(function() return item:getInventory():getItems():size() end, 1)
        if contents > 0 then return nil, "container_contents" end
        local location = wearableLocation(item)
        local worn = location ~= nil and character:getWornItem(location) or nil
        if worn == nil or (bagScore(item) or 0) > (bagScore(worn) or 0) then return nil, "useful_bag" end
        return 25, "spare_bag", true
    end
    if isWeapon(item) then
        if safe(function() return item:isBroken() end, false) then return 0, "broken_weapon", true end
        if safe(function() return item:isRanged() end, false) then return nil, "firearm_reserve" end
        local score = weaponScore(item)
        if score == nil or score >= facts.bestWeapon then return nil, "best_melee" end
        return 20 + score, "inferior_weapon", true
    end
    if isClothing(item) then
        local location = wearableLocation(item)
        local worn = location ~= nil and character:getWornItem(location) or nil
        if worn == nil or (clothingScore(item) or 0) > (clothingScore(worn) or 0) then
            return nil, "useful_clothing"
        end
        return 15 + (clothingScore(item) or 0), "spare_clothing", true
    end
    local storage = rawget(_G, "KnoxBaseStorage")
    if storage ~= nil and storage.matchesCategory ~= nil
        and (storage.matchesCategory(item, "building") or storage.matchesCategory(item, "farming")) then
        return 45, "base_material", false
    end
    if full:sub(1, 5) == "Base." and category == "Junk" then return 1, "junk", true end
    if atBase then return 60, "base_supplies", false end
    return nil, "unclassified_keep"
end

function Looting.cleanupPlan(character, requirements, continuing, atBase)
    if character == nil then return {}, "no_character" end
    local maximum = safe(function() return character:getMaxWeight() end, 0)
    local weight = safe(function() return character:getInventoryWeight() end, 0)
    if not atBase and (maximum <= 0 or weight <= maximum * (continuing and .80 or .90)) then
        return {}, "comfortable_load"
    end
    local facts, candidates = inventoryFacts(character), {}
    walkInventory(character:getInventory(), function(item)
        local source = item.getContainer ~= nil and item:getContainer() or nil
        -- Do not reach into a favorited/mission bag: its contents share its intent.
        local parent = source
        local protected, visited = false, {}
        while parent ~= nil and parent ~= character:getInventory() and not visited[parent] do
            visited[parent] = true
            local bag = parent.getContainingItem ~= nil and parent:getContainingItem() or nil
            if bag == nil then protected = true break end
            if safe(function() return bag:isFavorite() end, true) then protected = true break end
            parent = bag:getContainer()
        end
        if parent ~= character:getInventory() then protected = true end
        if not protected then
            local value, reason, canDrop = Looting.itemUtility(character, item, facts, requirements, atBase)
            if value ~= nil then
                candidates[#candidates + 1] = { item = item, source = source, value = value,
                    reason = reason, canDrop = canDrop == true,
                    weight = safe(function() return item:getUnequippedWeight() end, 0),
                    sequence = #candidates + 1 }
            end
        end
    end)
    table.sort(candidates, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.sequence < b.sequence
    end)
    return candidates, atBase and "base_deposit" or "heavy_load"
end

return Looting
