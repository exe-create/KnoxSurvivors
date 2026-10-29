-- Read-only barter quotes. Never a transfer authorization: the exchange action
-- must re-quote current inventory/relationships at completion, then verify receipt.
require "KS_SurvivorNeeds"
require "KS_Currency"
require "KS_TradeAvailability"

local Trade = {}
_G.KnoxTradeValuation = Trade

local MAX_ITEMS, MAX_OFFER = 4096, 32
local TOOLS = { ["Base.Hammer"] = true, ["Base.Saw"] = true,
    ["Base.Screwdriver"] = true, ["Base.Wrench"] = true,
    ["Base.Axe"] = true, ["Base.HandAxe"] = true }
local MEDICINES = {
    ["Base.Pills"] = 3, ["Base.PillsAntiDep"] = 2,
    ["Base.PillsBeta"] = 2, ["Base.PillsSleepingTablets"] = 2, ["Base.PillsVitamins"] = 2,
}
local MATERIALS = {
    ["Base.Nails"] = { "nails", 1, .15, "Base.Nails", 100 },
    ["Base.NailsBox"] = { "nails", 100, .15, "Base.Nails", 100 },
    ["Base.NailsCarton"] = { "nails", 1200, .15, "Base.Nails", 100 },
    ["Base.Screws"] = { "screws", 1, .15, "Base.Screws", 100 },
    ["Base.ScrewsBox"] = { "screws", 100, .15, "Base.Screws", 100 },
    ["Base.ScrewsCarton"] = { "screws", 1200, .15, "Base.Screws", 100 },
    ["Base.SmallSheetMetal"] = { "sheetmetal", 1, 3, "Base.SmallSheetMetal", 4 },
    ["Base.SheetMetal"] = { "sheetmetal", 4, 3, "Base.SmallSheetMetal", 4 },
}

-- Check method presence before invocation. pcall alone still logs missing-method
-- errors in Kahlua. Subtype methods below are additionally behind native type tests.
local function read(object, method, fallback, ...)
    if object == nil or tostring(object) == "null" or object[method] == nil then return fallback end
    local ok, result = pcall(object[method], object, ...)
    if ok and result ~= nil then return result end
    return fallback
end

local function number(value, fallback, minimum, maximum)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(minimum or 0, math.min(maximum or 10000, value))
end

local function condition(item)
    local maximum = number(read(item, "getConditionMax", nil), 0)
    if maximum <= 0 then return 1 end
    return number(read(item, "getCondition", nil), 0, 0, maximum) / maximum
end

local function ammoKey(item)
    local ammo = read(item, "getAmmoType", nil)
    return read(ammo, "getItemKey", nil)
end

local function descriptor(item)
    local full = read(item, "getFullType", nil)
    if type(full) ~= "string" then return nil end
    -- Unknown mod items have no inferred exchange value. A display category is
    -- not enough evidence that an arbitrary item is currency or medicine.
    if full:sub(1, 5) ~= "Base." then return nil end
    local d = { item = item, full = full, quantity = 1, condition = condition(item) }
    local currency = KnoxCurrency.describe(item)
    if currency ~= nil then
        d.kind, d.quantity, d.value = currency.kind, currency.quantity, currency.value
    elseif read(item, "IsFood", false) then
        if not KnoxSurvivorNeeds.isSafeFood(item) then return nil end
        d.kind, d.quantity = "food", number(-read(item, "getHungerChange", 0), 0, 0, 2)
        d.value = 80 * d.quantity
    elseif KnoxSurvivorNeeds.isWaterItem(item, false) then
        d.kind = "water"
        d.quantity = number(read(read(item, "getFluidContainer", nil), "getAmount", 0), 0, 0, 20)
        d.value = 12 * d.quantity
    elseif read(item, "isCanBandage", false) then
        -- Dirty/improvised bandages are worth their real treatment power, not
        -- the value of a fresh bandage simply because their category matches.
        d.kind = "bandage"
        local power = number(read(item, "getBandagePower", 0), 0, 0, 10)
        d.quantity, d.value = power / 4, 4 * power
    elseif MEDICINES[full] ~= nil or full == "Base.AlcoholWipes" or full == "Base.AlcoholedCottonBalls" then
        if not read(item, "IsDrainable", false) then return nil end
        local delta = number(read(item, "getUseDelta", nil), 0, 0, 1)
        local remaining = number(read(item, "getCurrentUsesFloat", nil), 0, 0, 1)
        if delta <= 0 then return nil end
        d.quantity = math.min(100, remaining / delta)
        if MEDICINES[full] then
            d.kind, d.value = "medicine:" .. full, d.quantity * MEDICINES[full]
        else
            d.kind = "antiseptic"
            d.quantity = d.quantity * number(read(item, "getAlcoholPower", nil), 0, 0, 10) / 4
            d.value = d.quantity * 4
            d.availabilityType = "Base.AlcoholWipes"
        end
        d.reserve = 1
    elseif full == "Base.SutureNeedle" or full == "Base.SutureNeedleHolder" or full == "Base.Splint" then
        d.kind, d.value, d.reserve = "medical:" .. full, 6 * d.condition, 1
    elseif MATERIALS[full] then
        local spec = MATERIALS[full]
        d.kind, d.quantity, d.availabilityType, d.stockUnit = spec[1], spec[2], spec[4], spec[5]
        d.value = d.quantity * spec[3] * d.condition
    elseif read(item, "IsWeapon", false) then
        if read(item, "isBroken", true) or d.condition <= 0 then return nil end
        local ranged = read(item, "isRanged", false)
        d.kind = ranged and "firearm" or "melee"
        d.ammo, d.magazine = ammoKey(item), ranged and read(item, "getMagazineType", nil) or nil
        local damage = number(read(item, "getMinDamage", 0), 0, 0, 10)
            + number(read(item, "getMaxDamage", 0), 0, 0, 10)
        d.value = (ranged and 30 or 8) + damage * (ranged and 8 or 5)
        d.value = d.value * d.condition
        -- Loaded rounds travel with the real weapon; no fabricated ammo balance.
        if ranged then d.value = d.value + number(read(item, "getCurrentAmmoCount", 0), 0, 0, 100)
            + (read(item, "isRoundChambered", false) and 1 or 0) end
    elseif rawget(_G, "ItemTag") ~= nil and ItemTag.AMMO ~= nil
        and read(item, "hasTag", false, ItemTag.AMMO) then
        d.kind, d.ammo, d.value = "ammo", full, 1
    elseif ammoKey(item) ~= nil and number(read(item, "getMaxAmmo", 0), 0) > 0 then
        d.kind, d.ammo = "magazine", ammoKey(item)
        d.value = 5 * d.condition + number(read(item, "getCurrentAmmoCount", 0), 0, 0, 100)
    elseif read(item, "IsInventoryContainer", false) then
        local contents = read(read(item, "getInventory", nil), "getItems", nil)
        if read(contents, "size", 1) ~= 0 then return nil end
        d.kind = "bag"
        d.value = (number(read(item, "getCapacity", 0), 0, 0, 100)
            + number(read(item, "getWeightReduction", 0), 0, 0, 100) * .15) * d.condition
    elseif read(item, "IsClothing", false) then
        d.kind = "clothing"
        d.value = (2 + number(read(item, "getBiteDefense", 0), 0, 0, 100) * .12
            + number(read(item, "getScratchDefense", 0), 0, 0, 100) * .06) * d.condition
    elseif TOOLS[full] then
        d.kind, d.value = "tool", 10 * d.condition
    end
    if d.value == nil or d.value <= 0 or d.quantity <= 0 then return nil end
    -- Currency denominations retain their own physical unit ratio; other item
    -- families share an availability key where native packing/conversion exists.
    if currency == nil then d.value = d.value * KnoxTradeAvailability.factor(d.availabilityType or full) end
    return d
end

local function inventory(character)
    local root = read(character, "getInventory", nil)
    local state = { owned = {}, entries = {}, stock = {}, types = {}, guns = {}, magazines = {}, bestMelee = 0 }
    local visited, count = {}, 0
    local function walk(container, depth, protected)
        if container == nil or visited[container] or depth > 16 then return false end
        visited[container] = true
        local items = read(container, "getItems", nil)
        local size = read(items, "size", nil)
        if type(size) ~= "number" or size < 0 or count + size > MAX_ITEMS then return false end
        count = count + size
        for i = 0, size - 1 do
            local item = read(items, "get", nil, i)
            if item == nil or state.owned[item] ~= nil or read(item, "getContainer", nil) ~= container then return false end
            local locked = protected or read(item, "isFavorite", true) or read(item, "isHidden", false)
                or read(character, "isEquipped", true, item) or read(character, "isHandItem", true, item)
                or read(character, "isAttachedItem", false, item)
            state.owned[item] = { container = container, locked = locked }
            local d = descriptor(item)
            if d ~= nil then
                state.entries[item] = d
                state.stock[d.kind] = (state.stock[d.kind] or 0) + d.quantity
                state.types[d.full] = (state.types[d.full] or 0) + 1
                if d.kind == "melee" then state.bestMelee = math.max(state.bestMelee, d.value) end
                if d.kind == "firearm" then
                    if d.ammo ~= nil then state.guns[d.ammo] = true end
                    if d.magazine ~= nil then state.magazines[d.magazine] = true end
                end
            end
            if read(item, "IsInventoryContainer", false)
                and not walk(read(item, "getInventory", nil), depth + 1,
                    protected or read(item, "isFavorite", true) or read(item, "isHidden", false)) then return false end
        end
        return true
    end
    return walk(root, 0, false) and state or nil
end

local function offer(items, owner)
    if type(items) ~= "table" then return nil, "invalid_offer" end
    local count = 0
    for key in pairs(items) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > MAX_OFFER then return nil, "invalid_offer" end
        count = count + 1
    end
    local selected, seen = {}, {}
    for i = 1, count do
        local item = items[i]
        if item == nil or seen[item] then return nil, "duplicate_or_sparse_offer" end
        seen[item] = true
        local ownership = owner.owned[item]
        if ownership == nil then return nil, "item_not_owned" end
        if ownership.locked then return nil, "equipped_or_favorite" end
        local d = owner.entries[item]
        if d == nil then return nil, "unsupported_item" end
        selected[#selected + 1] = d
    end
    return selected
end

local function relationContext(player, id)
    local persistence, runtime = rawget(_G, "KnoxPersistence"), rawget(_G, "KnoxSurvivorRuntime")
    if persistence == nil or runtime == nil or not persistence.isSurvivorAlive(id) then return nil, "not_alive" end
    if runtime.canInteract ~= nil and not runtime.canInteract(id) then
        return nil, "survivor_unavailable"
    end
    local localPlayer = false
    if rawget(_G, "getSpecificPlayer") ~= nil then
        local count = 4
        if rawget(_G, "getNumActivePlayers") ~= nil then
            local ok, n = pcall(getNumActivePlayers)
            if ok and tonumber(n) ~= nil then count = math.max(1, math.floor(tonumber(n))) end
        end
        for index = 0, math.max(0, count - 1) do if getSpecificPlayer(index) == player and player ~= nil then localPlayer = true end end
    end
    if not localPlayer or read(player, "isDead", true) then return nil, "invalid_player" end
    local modData = read(player, "getModData", {})
    local playerId = modData.KnoxSurvivors and modData.KnoxSurvivors.playerId
    if type(playerId) ~= "string" or playerId == "" then return nil, "unknown_player" end
    local npc = runtime.getCharacter(id)
    if npc == nil or npc == player or read(npc, "isDead", true) then return nil, "not_loaded" end
    local p, n = read(player, "getCurrentSquare", nil), read(npc, "getCurrentSquare", nil)
    if p == nil or n == nil or player:getZ() ~= npc:getZ()
        or (player:getX() - npc:getX()) ^ 2 + (player:getY() - npc:getY()) ^ 2 > 9 then return nil, "too_far" end
    local affiliation = persistence.getSurvivorAffiliation(id) or {}
    if affiliation.kind == "player" then return nil, "player_owned" end
    if persistence.isSurvivorHostileToPlayer(id, playerId) then return nil, "hostile" end
    local relation = persistence.getPlayerRelationshipSnapshot(playerId, id) or {}
    local trust = number(relation.trust, 30, 0, 100)
    local faction, playerFaction = persistence.getFactionForSurvivor(id), persistence.getPlayerFaction(playerId)
    local factionRelation = faction ~= nil and playerFaction ~= nil
        and persistence.getFactionRelationship(faction.id, playerFaction.id) or {}
    local reputation = number(factionRelation and factionRelation.reputation, 0, -100, 100)
    -- Even trusted friends retain a spread. Buying back the same items cannot
    -- generate value. No random acceptance reroll or player-provided price.
    local margin = math.max(1.08, math.min(1.7, 1.35 - (trust - 30) * .003 - reputation * .001))
    local duty = persistence.getSurvivorDuty(id) or {}
    local base = duty.baseId ~= nil and persistence.getBase(duty.baseId)
        or (faction ~= nil and persistence.getBaseForOwner("faction", faction.id)) or nil
    local requirements = {}
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task.state == "queued" or task.state == "claimed" then
            for full, amount in pairs(task.requirements and task.requirements.items or {}) do
                requirements[full] = math.max(requirements[full] or 0, number(amount, 0))
            end
        end
    end
    return { npc = npc, playerId = playerId, margin = margin, requirements = requirements }
end

local function totals(entries)
    local kinds, types = {}, {}
    for _, d in ipairs(entries) do
        kinds[d.kind] = (kinds[d.kind] or 0) + d.quantity
        types[d.full] = (types[d.full] or 0) + 1
    end
    return kinds, types
end

-- Whole-offer checks matter: evaluating each bandage/apple independently would
-- let a basket sell the final reserve several times in a single transaction.
local function keepsReserves(stock, incoming, outgoing, requirements)
    local added, addedTypes = totals(incoming)
    local removed, removedTypes = totals(outgoing)
    local reserves = { food = .4, water = 1, bandage = 2 }
    for _, d in pairs(stock.entries) do
        if d.reserve then reserves[d.kind] = math.max(reserves[d.kind] or 0, d.reserve) end
    end
    for kind, reserve in pairs(reserves) do
        local before = stock.stock[kind] or 0
        if before - (removed[kind] or 0) + (added[kind] or 0) + .00001 < math.min(before, reserve) then
            return false, (kind == "food" or kind == "water" or kind == "bandage")
                and kind .. "_reserve" or "medical_reserve"
        end
    end
    for full, required in pairs(requirements) do
        local before = stock.types[full] or 0
        if before - (removedTypes[full] or 0) + (addedTypes[full] or 0) < math.min(before, required) then
            return false, "task_resource"
        end
    end
    local sold, best = {}, 0
    for _, d in ipairs(outgoing) do
        sold[d.item] = true
        if (d.kind == "ammo" and stock.guns[d.ammo]) or (d.kind == "magazine" and stock.magazines[d.full]) then
            return false, "compatible_ammunition_reserve"
        end
    end
    for item, d in pairs(stock.entries) do
        if not sold[item] and d.kind == "melee" then best = math.max(best, d.value) end
    end
    for _, d in ipairs(incoming) do if d.kind == "melee" then best = math.max(best, d.value) end end
    if best + .00001 < stock.bestMelee then return false, "best_melee_reserve" end
    return true
end

local function values(stock, entries, needs, requirements, selling)
    local batch = totals(entries)
    local total = 0
    for _, d in ipairs(entries) do
        local supply = stock.stock[d.kind] or 0
        local urgency = 1
        if d.kind == "food" then urgency = 1 + number(needs.hunger, 0, 0, 1) * 2
        elseif d.kind == "water" then urgency = 1 + number(needs.thirst, 0, 0, 1) * 2
        elseif d.kind == "bandage" or d.kind == "antiseptic" then urgency = 1 + math.min(2, number(needs.bleedingParts, 0))
        elseif d.kind == "ammo" or d.kind == "magazine" then
            urgency = stock.guns[d.ammo] and 1.5 or .25
        end
        if (requirements[d.full] or 0) > (stock.types[d.full] or 0) then urgency = urgency + .5 end
        local unit = d.stockUnit or (d.kind == "food" and .1) or (d.kind == "cash" and 100) or 1
        -- Selling never receives a surplus discount. Incoming duplicate utility
        -- falls with stock and this entire basket, independent of selection order.
        local discount = selling and 1 or 1 / (1 + supply / unit * .15 + (batch[d.kind] / unit) * .075)
        total = total + d.value * urgency * discount
    end
    return total
end

function Trade.partner(player, survivorId)
    return relationContext(player, survivorId)
end

function Trade.stock(player, survivorId)
    local context, reason = relationContext(player, survivorId)
    if context == nil then return nil, reason end
    if player:getInventory() == context.npc:getInventory() then return nil, "shared_inventory" end
    local playerStock, npcStock = inventory(player), inventory(context.npc)
    if playerStock == nil or npcStock == nil then return nil, "inventory_unreadable_or_too_large" end
    local function available(stock)
        local items = {}
        for item in pairs(stock.entries) do
            if not stock.owned[item].locked then items[#items + 1] = item end
        end
        table.sort(items, function(a, b)
            local an, bn = tostring(read(a, "getName", "", player)), tostring(read(b, "getName", "", player))
            if an ~= bn then return an < bn end
            return read(a, "getID", 0) < read(b, "getID", 0)
        end)
        return items
    end
    return { playerItems = available(playerStock), survivorItems = available(npcStock) }
end

function Trade.quote(player, survivorId, playerItems, survivorItems)
    local context, reason = relationContext(player, survivorId)
    if context == nil then return nil, reason end
    if player:getInventory() == context.npc:getInventory() then return nil, "shared_inventory" end
    local playerStock, stock = inventory(player), inventory(context.npc)
    if playerStock == nil or stock == nil then return nil, "inventory_unreadable_or_too_large" end
    local incoming, outgoing
    incoming, reason = offer(playerItems, playerStock)
    if incoming == nil then return nil, reason end
    outgoing, reason = offer(survivorItems, stock)
    if outgoing == nil then return nil, reason end
    if #incoming == 0 or #outgoing == 0 then return nil, "both_sides_required" end
    local allowed
    allowed, reason = keepsReserves(stock, incoming, outgoing, context.requirements)
    if not allowed then return nil, reason end
    local needs = KnoxSurvivorNeeds.snapshot(context.npc)
    local offered = values(stock, incoming, needs, context.requirements, false)
    local requested = values(stock, outgoing, needs, context.requirements, true) * context.margin
    return { acceptable = offered >= requested, offeredValue = offered, requestedValue = requested,
        coverage = math.min(2, offered / requested), margin = context.margin,
        reason = offered >= requested and "fair_offer" or "offer_too_low" }
end

-- A gift is a deliberately one-way item transfer, not an unpriced barter.
-- The recipient still keeps native survival/task reserves, and the transaction
-- owner revalidates this quote before moving the real item instance.
function Trade.quoteGift(player, survivorId, playerItems)
    local context, reason = relationContext(player, survivorId)
    if context == nil then return nil, reason end
    if player:getInventory() == context.npc:getInventory() then return nil, "shared_inventory" end
    local playerStock, npcStock = inventory(player), inventory(context.npc)
    if playerStock == nil or npcStock == nil then return nil, "inventory_unreadable_or_too_large" end
    local incoming
    incoming, reason = offer(playerItems, playerStock)
    if incoming == nil then return nil, reason end
    if #incoming == 0 then return nil, "gift_item_required" end
    local allowed
    allowed, reason = keepsReserves(npcStock, incoming, {}, context.requirements)
    if not allowed then return nil, reason end
    return { acceptable = true, gift = true, offeredValue = values(playerStock, incoming,
        KnoxSurvivorNeeds.snapshot(context.npc), context.requirements, false), requestedValue = 0,
        reason = "gift_ready" }
end

return Trade
