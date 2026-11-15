-- Small, inventory-only equipment policy for loaded survivors.  It does not search
-- the world, create items, consume supplies, or maintain a parallel gear record.
-- Build 42 inventory/worn state remains the authority.
local Equipment = rawget(_G, "KnoxEquipmentIntelligence") or {}
_G.KnoxEquipmentIntelligence = Equipment

local EVALUATION_TICKS = 300
local MELEE_SWITCH_MARGIN = 1.25
local CLOTHING_SWITCH_MARGIN = 0.50
local BAG_SWITCH_MARGIN = 1.00
local states = setmetatable({}, { __mode = "k" })

-- A Java ArrayList can briefly expose a Java null sentinel while an item is
-- removed by combat, looting, or corpse transfer. Kahlua does not always
-- compare that sentinel equal to Lua nil, but indexing it emits an error.
local function usableItem(item)
    return item ~= nil and tostring(item) ~= "null"
end

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then return value end
    return fallback
end

local function fullType(item)
    if not usableItem(item) then return nil end
    return safe(function() return tostring(item:getFullType()) end, nil)
end

local function isMelee(item)
    return usableItem(item)
        and safe(function() return item:IsWeapon() end, false)
        and not safe(function() return item:isRanged() end, true)
        and not safe(function() return item:isBroken() end, true)
end

local function meleeScore(item)
    if not isMelee(item) then return nil end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax or 0
    return (safe(function() return item:getMinDamage() end, 0)
            + safe(function() return item:getMaxDamage() end, 0)) * 5
        + condition * 5
        + safe(function() return item:getMaxRange() end, 0)
        + safe(function() return item:getBaseSpeed() end, 0)
        + safe(function() return item:getCriticalChance() end, 0) * 0.02
end

function Equipment.isUsableMelee(item)
    return meleeScore(item) ~= nil
end

local function isUsableGun(item)
    return usableItem(item)
        and safe(function() return item:IsWeapon() end, false) == true
        and safe(function() return item:isRanged() end, false) == true
        and safe(function() return item:isBroken() end, true) == false
end

-- Role kit tags are vocabulary, not item ids. The policy only accepts a real
-- carried instance that already satisfies the role's tag; it never creates or
-- upgrades an item. Exact types are kept narrow where a broad category would
-- let a cook take a hammer or a quartermaster take a weapon.
local KIT_TYPES = {
    can_opener = { ["Base.CanOpener"] = true },
    clipboard = { ["Base.Clipboard"] = true },
    hammer = { ["Base.Hammer"] = true },
    saw = { ["Base.Saw"] = true },
    wrench = { ["Base.Wrench"] = true, ["Base.LugWrench"] = true },
    screwdriver = { ["Base.Screwdriver"] = true },
    planks = { ["Base.Plank"] = true },
    nails = { ["Base.Nails"] = true },
    hoe = { ["Base.Hoe"] = true, ["Base.HandShovel"] = true,
        ["Base.GardenFork"] = true, ["Base.GardenHoe"] = true },
    disinfectant = { ["Base.BottleDisinfectant"] = true,
        ["Base.AlcoholWipes"] = true, ["Base.Disinfectant"] = true },
    painkiller = { ["Base.Pills"] = true, ["Base.PillsPainkiller"] = true },
    fuel = { ["Base.PetrolCan"] = true, ["Base.EmptyPetrolCan"] = true,
        ["Base.JerryCan"] = true },
}

local function fullTypeStarts(item, prefix)
    local value = fullType(item)
    return value ~= nil and string.sub(value, 1, #prefix) == prefix
end

local function hasKitTag(item, tag)
    if not usableItem(item) then return false end
    local full = fullType(item) or ""
    local types = KIT_TYPES[tag]
    if types ~= nil then
        if types[full] == true then return true end
        return tag == "fuel" and safe(function()
            return item:hasTag(ItemTag.FUEL)
        end, false) == true
    end
    if tag == "melee" then return isMelee(item) end
    if tag == "firearm" then return isUsableGun(item) end
    if tag == "ammo" then
        return fullTypeStarts(item, "Base.Bullets")
            or fullTypeStarts(item, "Base.ShotgunShells")
            or safe(function()
                return item:hasTag(ItemTag.AMMO)
            end, false) == true
    end
    if tag == "bandage" then
        return safe(function() return item:isCanBandage() end, false) == true
    end
    if tag == "water" then
        local needs = rawget(_G, "KnoxSurvivorNeeds")
        return needs ~= nil and needs.isWaterItem ~= nil
            and safe(function() return needs.isWaterItem(item, false) end, false) == true
    end
    if tag == "bag" then
        return safe(function() return item:IsInventoryContainer() end, false) == true
    end
    if tag == "knife" then
        return safe(function() return item:getCategory() end, "") == "Knife"
            or string.find(full, "Knife", 1, true) ~= nil
    end
    if tag == "light" then
        local display = safe(function() return item:getDisplayCategory() end, "")
        return display == "Light" or string.find(full, "Flashlight", 1, true) ~= nil
            or string.find(full, "Lighter", 1, true) ~= nil
            or string.find(full, "Lantern", 1, true) ~= nil
    end
    if tag == "seeds" then return fullTypeStarts(item, "Base.Seed") end
    if tag == "parts" then
        return safe(function() return item:getDisplayCategory() end, "")
            == "VehicleMaintenance"
    end
    return false
end

function Equipment.roleKitMatches(tag, item)
    return type(tag) == "string" and hasKitTag(item, tag)
end

-- "Could this survivor fight with what is in their hands right now?" One
-- definition shared by the equipment chooser and the combat report, so a
-- survivor is never called defenceless while holding a weapon the chooser
-- considers usable, or called armed while holding a broken one.
function Equipment.isArmedWeapon(item)
    return Equipment.isUsableMelee(item) or isUsableGun(item)
end

function Equipment.isArmed(character)
    if character == nil then return false end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    return Equipment.isArmedWeapon(primary)
end

function Equipment.isMeaningfulMeleeUpgrade(character, item)
    local candidateScore = meleeScore(item)
    if candidateScore == nil then return false end
    local primary = character ~= nil and safe(function()
        return character:getPrimaryHandItem()
    end, nil) or nil
    local primaryIsUsableGun = safe(function()
        return primary ~= nil and primary:IsWeapon() and primary:isRanged()
            and not primary:isBroken()
    end, false)
    if primaryIsUsableGun then return false end
    local primaryScore = meleeScore(primary)
    return primary == nil or candidateScore >= (primaryScore or -math.huge) + MELEE_SWITCH_MARGIN
end

-- Explicit weapon orders may also accept a firearm, but only when Build 42
-- says the carried gun is ready. Ammo, magazine and chamber state stay native.
function Equipment.isMeaningfulWeaponUpgrade(character, item)
    if Equipment.isMeaningfulMeleeUpgrade(character, item) then return true end
    if not usableItem(item) or not safe(function() return item:IsWeapon() end, false)
        or not safe(function() return item:isRanged() end, false)
        or safe(function() return item:isBroken() end, true) then
        return false
    end
    local firearms = rawget(_G, "KnoxFirearmSupport")
    if firearms == nil or firearms.isReady == nil
        or not safe(function() return firearms.isReady(character, item) end, false) then
        return false
    end
    local primary = character ~= nil and safe(function()
        return character:getPrimaryHandItem()
    end, nil) or nil
    if primary == item then return false end
    local score = function(gun)
        return safe(function() return gun:getMaxRange() end, 0)
            + safe(function() return gun:getMaxDamage() end, 0) * 8
            + safe(function() return gun:getCondition() end, 0) * 0.1
    end
    local currentReady = primary ~= nil and safe(function()
        return firearms.isReady(character, primary)
    end, false) or false
    return not currentReady or score(item) >= score(primary) + 1.5
end

local function wearableLocation(item)
    if not usableItem(item) then return nil end
    local location = safe(function() return item:getBodyLocation() end, nil)
    if location ~= nil then return location end
    return safe(function() return item:canBeEquipped() end, nil)
end

local function isContainer(item)
    if not usableItem(item) then return false end
    return safe(function() return item:IsInventoryContainer() end, false)
end

local function isClothing(item)
    if not usableItem(item) then return false end
    return safe(function() return item:IsClothing() end, false)
end

local function bagScore(item)
    if not isContainer(item) then return nil end
    return safe(function() return item:getCapacity() end, 0)
        + safe(function() return item:getWeightReduction() end, 0) * 0.15
end

local function clothingScore(item, overheating)
    if not isClothing(item) then return nil end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax or 0
    return safe(function() return item:getBiteDefense() end, 0) * 0.08
        + safe(function() return item:getScratchDefense() end, 0) * 0.04
        + safe(function() return item:getInsulation() end, 0) * (overheating and -2 or 2)
        + condition * 3
end

local function rootItems(character)
    local inventory = safe(function() return character:getInventory() end, nil)
    local items = inventory ~= nil and safe(function() return inventory:getItems() end, nil) or nil
    if items == nil then return {} end
    local result = {}
    local size = safe(function() return items:size() end, 0)
    for index = 0, size - 1 do
        local item = safe(function() return items:get(index) end, nil)
        if usableItem(item) then result[#result + 1] = item end
    end
    return result
end

local function walkCarriedItems(container, visitor, seen)
    seen = seen or {}
    if container == nil or seen[container] then return end
    seen[container] = true
    local items = safe(function() return container:getItems() end, nil)
    if items == nil then return end
    for index = 0, safe(function() return items:size() end, 0) - 1 do
        local item = safe(function() return items:get(index) end, nil)
        if usableItem(item) then
            visitor(item)
            if isContainer(item) then
                walkCarriedItems(safe(function() return item:getInventory() end, nil),
                    visitor, seen)
            end
        end
    end
end

-- Return the role's missing tags in catalogue order. A carried stack counts as
-- present; this is a readiness answer, not a stock count. `available` lets the
-- caller exclude a claim without changing what the body actually carries.
function Equipment.roleKitMissing(character, gear, available)
    if character == nil or type(gear) ~= "table" then return {} end
    local inventory = safe(function() return character:getInventory() end, nil)
    local found = {}
    walkCarriedItems(inventory, function(item)
        for _, tag in ipairs(gear) do
            if not found[tag] and Equipment.roleKitMatches(tag, item)
                and (available == nil or safe(function()
                    return available(tag, item)
                end, false) == true) then
                found[tag] = true
            end
        end
    end)
    local missing = {}
    for _, tag in ipairs(gear) do
        if not found[tag] then missing[#missing + 1] = tag end
    end
    return missing
end

local function actionActive(character)
    -- Unknown native ownership cannot authorize a passive gear change.
    if safe(function() return character:getCharacterActions():isEmpty() end, nil) ~= true then return true end
    local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
    local queue = queues ~= nil and queues[character] or nil
    -- Vanilla clearQueue may retain .current after both actual queues drain.
    return queue ~= nil and (type(queue.queue) ~= "table" or #queue.queue > 0)
end

local function availableItem(item, available)
    return available == nil or safe(function() return available(item) end, false) == true
end

local function carriedRoot(character, item)
    for _, candidate in ipairs(rootItems(character)) do
        if candidate == item then return true end
    end
    return false
end

local function replacedWearScore(character, location, scoreItem)
    local wornItems = character.getWornItems ~= nil and character:getWornItems() or nil
    if wornItems == nil then
        return scoreItem(safe(function() return character:getWornItem(location) end, nil))
    end
    -- Match vanilla doWearClothingTooltip: different locations can be
    -- mutually exclusive (shorts/trousers, for example).
    local group = wornItems:getBodyLocationGroup()
    local total, found = 0, false
    for index = 0, wornItems:size() - 1 do
        local worn = wornItems:get(index)
        if location == worn:getLocation() or group:isExclusive(location, worn:getLocation()) then
            total = total + (scoreItem(worn:getItem()) or 0)
            found = true
        end
    end
    return found and total or nil
end

function Equipment.choose(character, available)
    if character == nil then return nil end
    local candidates = rootItems(character)
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    local heat = needs and needs.thermalMoodle and needs.thermalMoodle(character, "heat") or nil
    local cold = needs and needs.thermalMoodle and needs.thermalMoodle(character, "cold") or nil
    local comfort = states[character] or {nextAt=0}
    states[character] = comfort
    -- Returning to normal is not a reason to put the overheating coat straight
    -- back on. Retain the comfort choice until native cold asks for warmth.
    if heat ~= nil and heat > 0 then comfort.preferCooler = true
    elseif cold ~= nil and cold > 0 then comfort.preferCooler = false end
    local function wearScore(item) return clothingScore(item, comfort.preferCooler == true) end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    local primaryIsUsableGun = isUsableGun(primary)
    local bestMelee, bestMeleeScore = nil, -math.huge
    local bestWear, bestWearGain = nil, 0

    for _, item in ipairs(candidates) do
        if availableItem(item, available) then
            local score = meleeScore(item)
            if score ~= nil and score > bestMeleeScore then
                bestMelee, bestMeleeScore = item, score
            end
            local location = wearableLocation(item)
            if location ~= nil then
                local worn = safe(function() return character:getWornItem(location) end, nil)
                local candidate, current, margin
                if isContainer(item) then
                    candidate, current, margin = bagScore(item),
                        safe(function() return replacedWearScore(character, location, bagScore) end, math.huge),
                        BAG_SWITCH_MARGIN
                elseif isClothing(item) then
                    candidate, current, margin = wearScore(item),
                        safe(function() return replacedWearScore(character, location, wearScore) end, math.huge),
                        CLOTHING_SWITCH_MARGIN
                end
                local gain = candidate ~= nil and candidate - (current or -1) or nil
                if gain ~= nil and gain >= margin and item ~= worn and gain > bestWearGain then
                    bestWear, bestWearGain = item, gain
                end
            end
        end
    end

    local primaryScore = meleeScore(primary)
    if not primaryIsUsableGun and bestMelee ~= nil and bestMelee ~= primary
        and bestMeleeScore >= (primaryScore or -math.huge) + MELEE_SWITCH_MARGIN then
        return { kind = "melee", item = bestMelee, score = bestMeleeScore }
    end
    if bestWear ~= nil then
        return { kind = "wear", item = bestWear, gain = bestWearGain,
            location = wearableLocation(bestWear) }
    end
    return nil
end

-- Enlistment offers actual spare garments matching the donor's worn uniform.
-- No starter kit is regenerated and the donor is never stripped to dress a recruit.
function Equipment.offerFactionUniform(donor, recruit, faction, ticks)
    if donor==nil or recruit==nil or faction==nil or faction.background~="military" then return false end
    local source=donor.character:getInventory()
    local destination=recruit.character:getInventory()
    local worn=donor.character:getWornItems()
    local uniformTypes={}
    for index=0,worn:size()-1 do
        local item=worn:getItemByIndex(index)
        if item~=nil then uniformTypes[item:getFullType()]=true end
    end
    local state=states[recruit.character] or {nextAt=0}
    states[recruit.character]=state
    if state.uniformReceipts~=nil then return false end
    local receipts={}
    local items=source:getItems()
    for index=0,items:size()-1 do
        local item=items:get(index)
        local personal=safe(function() return item:isFavorite() end,true)
        local location=wearableLocation(item)
        local wornItem=location~=nil and donor.character:getWornItem(location) or nil
        local claims=donor.reservations~=nil and donor.reservations.items or nil
        if location~=nil and uniformTypes[fullType(item)] and item~=wornItem and not personal
            and (claims==nil or claims[item]==nil)
            and item~=donor.character:getPrimaryHandItem() and item~=donor.character:getSecondaryHandItem() then
            local function allowed()
                local first=KnoxPersistence.getFactionForSurvivor(donor.id)
                local second=KnoxPersistence.getFactionForSurvivor(recruit.id)
                return first~=nil and second~=nil and first.id==faction.id and second.id==faction.id
                    and not donor.character:isDead() and not recruit.character:isDead()
                    and item:getContainer()==source
                    and donor.character:getWornItem(location)~=item
                    and not safe(function() return item:isFavorite() end,true)
                    and item~=donor.character:getPrimaryHandItem() and item~=donor.character:getSecondaryHandItem()
                    and (donor.reservations==nil or donor.reservations.items==nil
                        or donor.reservations.items[item]==nil)
            end
            local action=KnoxInventoryActions.queueTransfer(donor.character,item,source,destination,nil,allowed)
            if action~=nil then receipts[#receipts+1]={item=item,location=location,expires=(ticks or 0)+600} end
            if #receipts>=3 then break end
        end
    end
    if #receipts>0 then state.uniformReceipts=receipts; return true end
    return false
end

function Equipment.receiveUniform(id, character, bridge, state, ticks)
    local receipts=state.uniformReceipts
    if receipts==nil then return false end
    for index=#receipts,1,-1 do
        local receipt=receipts[index]
        if ticks>=receipt.expires then table.remove(receipts,index)
        elseif receipt.item:getContainer()==character:getInventory() then
            local faction=KnoxPersistence.getFactionForSurvivor(id)
            if faction~=nil and faction.background=="military" then
                local result=tostring(bridge:wearNpcOwnedItemById(id,receipt.item:getFullType(),receipt.item:getID()))
                if result:find("WORN_OWNED",1,true)==1
                    and character:getWornItem(receipt.location)==receipt.item then
                    table.remove(receipts,index)
                    return true
                end
            else table.remove(receipts,index) end
        end
    end
    if #receipts==0 then state.uniformReceipts=nil end
    return false
end

function Equipment.reconsider(id, character, bridge, ticks, force, available)
    if character == nil or bridge == nil then return false, "equipment_unavailable" end
    local state = states[character] or { nextAt = 0 }
    states[character] = state
    if state.inProgress then return false, "equipment_busy" end
    if not force and (ticks or 0) < (state.nextAt or 0) then
        return false, "equipment_cooldown"
    end
    if actionActive(character) then
        state.nextAt = (ticks or 0) + 30
        return false, "equipment_action_active"
    end
    state.nextAt = (ticks or 0) + EVALUATION_TICKS
    if Equipment.receiveUniform(id,character,bridge,state,ticks or 0) then
        return true,"faction_uniform_received"
    end
    -- A broken primary is a real event. Say it once per item through the
    -- dialogue owner's voice selection; the chooser still owns whether to
    -- swap. A skipped line (cooldown, speech off) is retried next evaluation.
    local held = safe(function() return character:getPrimaryHandItem() end, nil)
    if usableItem(held) and safe(function() return held:isBroken() end, false) == true then
        local heldId = safe(function() return held:getID() end, nil)
        state.brokenSpoken = state.brokenSpoken or {}
        local key = tostring(heldId or "unknown")
        if state.brokenSpoken[key] ~= true then
            local dialogue = rawget(_G, "KnoxSurvivorDialogue")
            if dialogue ~= nil and dialogue.say ~= nil then
                local ok, spoke = pcall(dialogue.say, character, id, "weapon_broken", ticks)
                if ok and spoke == true then state.brokenSpoken[key] = true end
            end
        end
    end
    local decision = Equipment.choose(character, available)
    if decision == nil then return false, "equipment_stable" end
    local typeName = fullType(decision.item)
    if typeName == nil then return false, "equipment_unknown_item" end
    local itemId = safe(function() return decision.item:getID() end, nil)
    if type(itemId) ~= "number" or itemId ~= itemId or itemId == math.huge
        or itemId < 0 or itemId ~= math.floor(itemId) then return false, "equipment_identity_unavailable" end
    local operation
    if decision.kind == "melee" then operation = bridge.equipNpcOwnedWeaponById
    elseif decision.kind == "wear" then operation = bridge.wearNpcOwnedItemById end
    if operation == nil then return false, "equipment_bridge_unavailable" end
    -- This transition is synchronous and keeps the existing bridge owner. Do
    -- not substitute a same-type item or enter recursively during capture.
    state.inProgress = true
    local ok, changed, result = pcall(function()
        local current = Equipment.choose(character, available)
        if actionActive(character) or not carriedRoot(character, decision.item)
            or current == nil or current.item ~= decision.item or current.kind ~= decision.kind
            or current.location ~= decision.location or fullType(decision.item) ~= typeName
            or decision.item:getID() ~= itemId then return false, "equipment_permission_changed" end
        local response = tostring(operation(bridge, id, typeName, itemId))
        local prefix = decision.kind == "melee" and "EQUIPPED_WEAPON" or "WORN_OWNED"
        if string.find(response, prefix, 1, true) ~= 1 then return false, response end
        local equipped
        if decision.kind == "melee" then equipped = character:getPrimaryHandItem()
        else equipped = character:getWornItem(decision.location) end
        if equipped ~= decision.item or not carriedRoot(character, decision.item)
            or not availableItem(decision.item, available) then
            return false, "equipment_receipt_unconfirmed"
        end
        return true, response
    end)
    state.inProgress = nil
    if not ok then return false, "equipment_bridge_failed" end
    return changed, result
end

function Equipment.resetRuntime()
    states = setmetatable({}, { __mode = "k" })
end

return Equipment
