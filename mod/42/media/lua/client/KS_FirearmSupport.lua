-- Native firearm preparation for contained IsoPlayer survivors.
--
-- Knox never writes magazine/chamber/ammunition fields.  Build 42 owns those
-- transitions through ISReloadWeaponAction; this module only selects a real carried
-- gun, queues the vanilla reload action, and lets the normal combat controller fire it.
require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISRackFirearm"
require "TimedActions/ISTimedActionQueue"
pcall(function() require "KS_DebugLog" end)
local KS_SafeCall = require "KS_SafeCall"

local Firearms = rawget(_G, "KnoxFirearmSupport") or {}
_G.KnoxFirearmSupport = Firearms
local FIREARM_SWITCH_MARGIN = 1.5
-- Forward declaration: exact-weapon melee helpers are defined after the
-- inventory walkers that classify them.
local isUsableMelee
-- This is telemetry only.  It records a successful call into the same native
-- hook a local player uses; it never substitutes for vanilla ballistics or
-- changes a weapon's ammunition/chamber state.
local successfulNativeShots = setmetatable({}, { __mode = "k" })
local AIMING_ASSIST_BONUS = {
    [1] = 0,
    [2] = 2,
    [3] = 4,
}

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then
        return value
    end
    return fallback
end

local function isFunctionalGun(item)
    return item ~= nil
        and safe(function() return item:IsWeapon() end, false)
        and safe(function() return item:isRanged() end, false)
        and not safe(function() return item:isBroken() end, true)
        and not safe(function()
            return item:isSelectFire() and item:getFireMode() == "Safe"
        end, false)
end

local function canShoot(character, gun)
    return isFunctionalGun(gun)
        and safe(function()
            return ISReloadWeaponAction.canShoot(character, gun)
        end, false)
end

-- Read-only classification used by the controller to distinguish "holding a
-- functional gun" (which may still need ammo/reload) from a melee weapon. It
-- never inspects or mutates ammunition/chamber state.
function Firearms.isFunctionalGun(item)
    return isFunctionalGun(item)
end

local function queueFor(character)
    return ISTimedActionQueue ~= nil and ISTimedActionQueue.queues ~= nil
        and ISTimedActionQueue.queues[character] or nil
end

local function firearmActionActive(character, gun)
    if gun == nil then return false end
    local queue = queueFor(character)
    if queue == nil or type(queue.queue) ~= "table" then
        return false
    end
    local magazineType = safe(function() return gun:getMagazineType() end, nil)
    for _, action in ipairs(queue.queue) do
        if action ~= nil and (action.gun == gun or action.reloading == true) then
            return true
        end
        if action ~= nil and action.magazine ~= nil and magazineType ~= nil
            and safe(function()
                return action.magazine:getFullType() == magazineType
            end, false) then
            return true
        end
    end
    return false
end

local function items(character)
    if character == nil then
        return nil
    end
    return safe(function() return character:getInventory():getItems() end, nil)
end

local function topLevelContains(character, candidate)
    local carried = items(character)
    if carried == nil or candidate == nil then return false end
    for index = 0, carried:size() - 1 do
        if carried:get(index) == candidate then return true end
    end
    return false
end

local function gunScore(item)
    return safe(function() return item:getMaxRange() end, 0)
        + safe(function() return item:getMaxDamage() end, 0) * 8
        + safe(function() return item:getCondition() end, 0) * 0.1
end

-- The Java equipment bridge can only equip an item at the survivor's root
-- inventory.  Search bags when selecting a firearm, then move the same real
-- item into that root before equipping it.  This mirrors the existing bagged
-- melee recovery and never creates ammunition, magazines or weapons.
local function carriedGuns(character, qualifies)
    local inventory = character ~= nil
        and safe(function() return character:getInventory() end, nil) or nil
    if inventory == nil or inventory.getItems == nil then return nil end
    local seen, best, bestScore = {}, nil, -math.huge
    local function walk(container)
        if container == nil or seen[container] then return end
        seen[container] = true
        local carried = safe(function() return container:getItems() end, nil)
        if carried == nil then return end
        for index = 0, carried:size() - 1 do
            local item = carried:get(index)
            if qualifies(item) then
                local score = gunScore(item)
                if score > bestScore then best, bestScore = item, score end
            end
            if safe(function() return item:IsInventoryContainer() end, false) then
                walk(safe(function() return item:getInventory() end, nil))
            end
        end
    end
    walk(inventory)
    return best, bestScore
end

local function bestReadyGun(character)
    local best, bestScore = carriedGuns(character, function(item)
        return canShoot(character, item)
    end)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if canShoot(character, primary) and best ~= nil
        and gunScore(primary) + FIREARM_SWITCH_MARGIN >= bestScore then
        return primary
    end
    return best
end

local function canPrepare(character, item)
        if isFunctionalGun(item) then
            local needsRack = safe(function()
                return ISReloadWeaponAction.canRack(item)
            end, false)
            local hasLoadedMagazine = safe(function()
                local magazine = item:getBestMagazine(character)
                return magazine ~= nil and magazine:getCurrentAmmoCount() > 0
            end, false)
            local hasAmmo = safe(function()
                local ammoType = item:getAmmoType()
                return ammoType ~= nil
                    and character:getInventory():getItemCountRecurse(ammoType:getItemKey()) > 0
            end, false)
            if needsRack or hasLoadedMagazine or hasAmmo then
                return true
            end
        end
        return false
end

local function bestReloadableGun(character)
    local best, bestScore = carriedGuns(character, function(item)
        return canPrepare(character, item)
    end)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if canPrepare(character, primary) and best ~= nil
        and gunScore(primary) + FIREARM_SWITCH_MARGIN >= bestScore then
        return primary
    end
    return best
end

local function equip(id, character, bridge, gun)
    if safe(function() return character:getPrimaryHandItem() == gun end, false) then
        return true, "EQUIPMENT_STABLE " .. tostring(gun:getFullType())
    end
    local inventory = safe(function() return character:getInventory() end, nil)
    if not topLevelContains(character, gun) and inventory ~= nil then
        pcall(function() inventory:AddItem(gun) end)
    end
    if not topLevelContains(character, gun) then
        return false, "EQUIP_FAILED_GUN_NOT_AT_ROOT " .. tostring(gun:getFullType())
    end
    local itemId = tonumber(safe(function() return gun:getID() end, nil))
    local result
    if itemId ~= nil and bridge.equipNpcOwnedWeaponById ~= nil then
        result = tostring(bridge:equipNpcOwnedWeaponById(id, gun:getFullType(), itemId))
    else
        result = tostring(bridge:equipNpcOwnedWeapon(id, gun:getFullType()))
    end
    local equipped = string.find(result, "EQUIPPED_WEAPON", 1, true) == 1
        and safe(function() return character:getPrimaryHandItem() == gun end, false)
    if not equipped and string.find(result, "EQUIPPED_WEAPON", 1, true) == 1 then
        result = "EQUIP_FAILED_DIFFERENT_GUN " .. tostring(gun:getFullType())
    end
    return equipped, result
end

local function equipMeleeFallback(id, bridge)
    if bridge.equipBestNpc == nil then
        return "NO_MELEE_BRIDGE"
    end
    return tostring(bridge:equipBestNpc(id))
end

-- Equip the exact carried melee instance rather than letting the Java chooser
-- pick a same-type alternative. Falls back to the existing best-melee bridge
-- when the item id or the id-based bridge is unavailable. Never creates or
-- duplicates an item.
local function equipExactCarriedMelee(id, character, bridge)
    local weapon = Firearms.findCarriedMelee(character)
    if weapon == nil then return nil, "no_carried_melee" end
    local inventory = safe(function() return character:getInventory() end, nil)
    if inventory ~= nil then
        pcall(function() inventory:AddItem(weapon) end)
    end
    local itemId = tonumber(safe(function() return weapon:getID() end, nil))
    if itemId ~= nil and bridge ~= nil and bridge.equipNpcOwnedWeaponById ~= nil then
        local result = tostring(bridge:equipNpcOwnedWeaponById(
            id, weapon:getFullType(), itemId
        ))
        if isUsableMelee(safe(function() return character:getPrimaryHandItem() end, nil)) then
            return result, "melee_equipped"
        end
    end
    if bridge == nil or bridge.equipBestNpc == nil then
        return nil, "no_equip_bridge"
    end
    return tostring(bridge:equipBestNpc(id)), "melee_best"
end

function Firearms.preferenceFor(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local policies = persistence ~= nil and persistence.getSurvivorPolicies ~= nil
        and persistence.getSurvivorPolicies(id) or nil
    local preference = policies ~= nil and policies.weaponPreference or "auto"
    return (preference == "melee" or preference == "ranged") and preference or "auto"
end

local function nativeAimingLevel(character)
    local level = tonumber(safe(function()
        return character:getPerkLevel(Perks.Aiming)
    end, 0)) or 0
    return math.max(0, math.min(10, math.floor(level)))
end

function Firearms.aimingAssistLevel()
    local settings = rawget(_G, "KnoxSettings")
    local configured = settings ~= nil and settings.survivorAimingAssist ~= nil
        and settings.survivorAimingAssist() or 1
    configured = tonumber(configured) or 1
    return math.max(1, math.min(3, math.floor(configured)))
end

-- This is an AI decision level only. It never changes the character's native
-- Aiming perk, XP, weapon stats, or the engine's shot calculation.
function Firearms.aimingDecisionLevel(character)
    local native = nativeAimingLevel(character)
    local bonus = AIMING_ASSIST_BONUS[Firearms.aimingAssistLevel()] or 0
    return math.min(10, native + bonus), native, bonus
end

-- Java owns the visible aim posture. Lua supplies a bounded settle time that
-- reflects the real Aiming level while allowing the sandbox assistance modes to
-- make test/forgiving profiles less hesitant.
function Firearms.aimSettleTicks(id, character)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if not isFunctionalGun(primary) then
        return 18
    end
    local _, native, bonus = Firearms.aimingDecisionLevel(character)
    local ticks = 18 + (5 - native) * 2 - bonus * 2
    return math.max(8, math.min(30, math.floor(ticks)))
end

local function hasUsableMelee(character)
    local carried = items(character)
    if carried == nil then return false end
    for index = 0, carried:size() - 1 do
        local item = carried:get(index)
        if item ~= nil then
            local weapon, weaponReason = KS_SafeCall.invoke(item, "IsWeapon")
            if weapon and weaponReason == nil then
                local ranged = KS_SafeCall.invoke(item, "isRanged")
                local broken = KS_SafeCall.invoke(item, "isBroken")
                if ranged == false and broken == false then
                    return true
                end
            end
        end
    end
    return false
end

isUsableMelee = function(item)
    if item == nil then return false end
    local weapon = KS_SafeCall.invoke(item, "IsWeapon")
    local ranged = KS_SafeCall.invoke(item, "isRanged")
    local broken = KS_SafeCall.invoke(item, "isBroken")
    return weapon == true and ranged == false and broken == false
end

-- Recursive: bagged blades count. The Java equipper only sees top-level
-- inventory, so an armed survivor can still enter combat empty-handed when
-- their only melee weapon sits in a backpack.
function Firearms.findCarriedMelee(character)
    local inventory = character ~= nil
        and safe(function() return character:getInventory() end, nil) or nil
    if inventory == nil or inventory.getItems == nil then return nil end
    local seen, found = {}, nil
    local function walk(container)
        if found ~= nil or container == nil or seen[container] then return end
        seen[container] = true
        local carried = safe(function() return container:getItems() end, nil)
        if carried == nil then return end
        for index = 0, carried:size() - 1 do
            local item = carried:get(index)
            if item ~= nil then
                if isUsableMelee(item) then
                    found = item
                    return
                end
                local isContainer = KS_SafeCall.invoke(item, "IsInventoryContainer")
                if isContainer == true then
                    local nested = KS_SafeCall.invoke(item, "getInventory")
                    if nested ~= nil then walk(nested) end
                end
            end
        end
    end
    walk(inventory)
    return found
end

-- Pulls a bagged melee weapon into the top-level inventory so the normal
-- equip bridge can see it. Native AddItem detaches the same object from its
-- bag; nothing is created or duplicated.
function Firearms.pullMeleeToHands(id, character, bridge)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if isUsableMelee(primary) then return true, "already_equipped" end
    local result = equipExactCarriedMelee(id, character, bridge)
    if result == nil then return false, "no_carried_melee" end
    return isUsableMelee(safe(function() return character:getPrimaryHandItem() end, nil)), result
end

-- This decides preference, never firearm viability. Native ammo/reload checks
-- still decide whether a ranged choice can actually be used.
--
-- `retainRanged` is a bounded hysteresis flag supplied by the controller for the
-- encounter it has already committed to a gun. It keeps the committed class
-- until the threat is genuinely close, so a target pacing across the
-- survivor-choice threshold cannot flip ranged/melee every engagement. It never
-- overrides an explicit melee order or the absence of a real threat.
function Firearms.wantsRanged(id, character, target, retainRanged)
    local preference = Firearms.preferenceFor(id)
    if preference == "ranged" then return true, "ordered_ranged" end
    if not hasUsableMelee(character) then return true, "no_usable_melee" end
    if preference == "melee" then return false, "ordered_melee" end
    local aiming = Firearms.aimingDecisionLevel(character)
    local distance = safe(function()
        if target == nil or character:getZ() ~= target:getZ() then return 0 end
        return (character:getX() - target:getX()) ^ 2 + (character:getY() - target:getY()) ^ 2
    end, 0)
    if retainRanged == true and distance >= 4 then
        return true, "survivor_choice_retained"
    end
    -- Novices normally keep noise down. A trained shot with room to aim may
    -- choose a gun; close-pressure fallback remains owned by native combat.
    return aiming >= 4 and distance >= 9, "survivor_choice"
end

function Firearms.cancelPreparation(character)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    local active = primary ~= nil and safe(function() return primary:IsWeapon() and primary:isRanged() end, false)
        and firearmActionActive(character, primary)
    local queue = queueFor(character)
    -- A player inventory operation may have removed/swapped the primary while
    -- the old gun still owns a queued reload. Do not depend only on the hand slot.
    for _, action in ipairs(queue ~= nil and queue.queue or {}) do
        if action.reloading == true or (action.gun ~= nil and safe(function()
            return action.gun:IsWeapon() and action.gun:isRanged()
        end, false)) then active = true break end
    end
    if active then
        ISTimedActionQueue.clear(character)
        return true
    end
    return false
end

local function diagFirearm(id, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("firearm", id, event, details) end)
    end
end

local function resolveId(character, fallback)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.idForCharacter ~= nil then
        local ok, id = pcall(function() return runtime.idForCharacter(character) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return tostring(fallback or "unknown")
end

local function queueNativePreparation(character, gun)
    if safe(function() return ISReloadWeaponAction.canRack(gun) end, false) then
        ISTimedActionQueue.add(ISRackFirearm:new(character, gun))
        if firearmActionActive(character, gun) then
            return true, "native_rack_queued " .. tostring(gun:getFullType())
        end
    end
    ISReloadWeaponAction.BeginAutomaticReload(character, gun)
    if firearmActionActive(character, gun) then
        return true, "native_reload_queued " .. tostring(gun:getFullType())
    end
    diagFirearm(resolveId(character, nil), "reload_queue_failed", {
        gun = safe(function() return gun:getFullType() end, "unknown"),
        ammo = safe(function() return gun:getCurrentAmmoCount() end, nil),
        chambered = safe(function() return gun:isRoundChambered() end, nil),
    })
    return false, "native_preparation_unavailable " .. tostring(gun:getFullType())
end

-- Returns ready, reloading, or melee.  Reloading deliberately yields combat ownership
-- for the native timed action; a later threat scan resumes once the actual weapon can fire.
function Firearms.prepareForThreat(id, character, bridge, target, retainRanged)
    if character == nil or bridge == nil or bridge.equipNpcOwnedWeapon == nil then
        return "melee", "bridge_unavailable"
    end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if isFunctionalGun(primary) and firearmActionActive(character, primary) then
        return "reloading", "native_action_active"
    end

    local ranged, preferenceReason = Firearms.wantsRanged(
        id, character, target, retainRanged
    )
    if not ranged then
        return "melee", preferenceReason .. " " .. Firearms.fallbackToMelee(id, bridge, character)
    end

    local ready = bestReadyGun(character)
    if ready ~= nil then
        local equipped, result = equip(id, character, bridge, ready)
        return equipped and "ready" or "melee", result
    end

    local reloadable = bestReloadableGun(character)
    if reloadable == nil then
        diagFirearm(id, "no_usable_firearm", nil)
        return "melee", "no_usable_firearm " .. Firearms.fallbackToMelee(id, bridge, character)
    end
    local equipped, result = equip(id, character, bridge, reloadable)
    if not equipped then
        diagFirearm(id, "equip_failed", { detail = tostring(result) })
        return "melee", result
    end
    local queued, preparation = queueNativePreparation(character, reloadable)
    if queued then
        local log = rawget(_G, "KnoxDebugLog")
        if log ~= nil and log.once ~= nil then
            pcall(function() log.once("firearm", id, "reloading", { detail = tostring(preparation) }) end)
        end
        return "reloading", preparation
    end
    diagFirearm(id, "reload_failed", { detail = tostring(preparation) })
    return "melee", preparation .. " " .. Firearms.fallbackToMelee(id, bridge, character)
end

function Firearms.isReady(character, gun)
    return canShoot(character, gun)
end

-- Release firearm ownership and hold an actually carried melee weapon. When a
-- character is supplied and already holds usable melee, this is a no-op so a
-- bounded fallback window cannot repeatedly reset the native melee model/hand
-- state. Only a real carried melee instance is equipped; nothing is fabricated.
function Firearms.fallbackToMelee(id, bridge, character)
    if character ~= nil then
        local primary = safe(function() return character:getPrimaryHandItem() end, nil)
        if isUsableMelee(primary) then return "already_armed_melee" end
        local result = equipExactCarriedMelee(id, character, bridge)
        if result ~= nil then return result end
    end
    return equipMeleeFallback(id, bridge)
end

-- Observes the currently equipped weapon without changing inventory, actions, or
-- combat ownership. The autonomy controller uses this before each bounded ranged
-- combat refresh so an emptied/jammed firearm yields to native preparation.
function Firearms.currentCombatState(character)
    local gun = safe(function() return character:getPrimaryHandItem() end, nil)
    if not isFunctionalGun(gun) then
        return "melee", "primary_not_functional_firearm"
    end
    if firearmActionActive(character, gun) then
        return "reloading", "native_action_active"
    end
    if canShoot(character, gun) then
        return "ready", tostring(gun:getFullType())
    end
    return "needs_preparation", tostring(gun:getFullType())
end

-- This is the exact Build 42 firing hook used by local player input. It owns
-- gunshot audio/world sound and calls DoAttack; later vanilla callbacks own
-- ballistics, damage, chamber, magazine, condition, and ammunition changes.
function Firearms.fireNative(character)
    local gun = safe(function() return character:getPrimaryHandItem() end, nil)
    if firearmActionActive(character, gun) then
        return false, "native_action_active"
    end
    if gun == nil then
        -- Empty hand: fail silently without touching native metadata getters.
        return false, "firearm_not_ready"
    end
    if not canShoot(character, gun) then
        -- Not-ready is the common silent case (empty mag, unchambered,
        -- jammed, broken, safe mode): log the exact gun state so a
        -- survivor that never fires can be diagnosed from one line.
        local state = safe(function() return gun:getFullType() end, "no_gun")
        local ammo = safe(function() return gun:getCurrentAmmoCount() end, nil)
        local chambered = safe(function() return gun:isRoundChambered() end, nil)
        local jammed = safe(function()
            if gun ~= nil and gun.isJammed ~= nil then return gun:isJammed() end
            return false
        end, false)
        diagFirearm(resolveId(character, nil), "not_ready", {
            gun = state, ammo = ammo, chambered = chambered, jammed = jammed,
        })
        return false, "firearm_not_ready"
    end
    -- Preserve the native charge argument. The installed ranged attackHook
    -- calls DoAttack(0); chargeDelta only affects its melee/shove branch.
    local charge = 36.0
    pcall(function()
        if character.getUseChargeDelta ~= nil then
            local v = character:getUseChargeDelta()
            if tonumber(v) ~= nil and tonumber(v) > 0 then charge = tonumber(v) end
        elseif character.useChargeDelta ~= nil and tonumber(character.useChargeDelta) > 0 then
            charge = tonumber(character.useChargeDelta)
        end
    end)
    local success, failure = pcall(
        ISReloadWeaponAction.attackHook,
        character,
        charge,
        gun
    )
    if not success then
        diagFirearm(resolveId(character, nil), "shot_failed", {
            gun = safe(function() return gun:getFullType() end, "unknown"),
            error = tostring(failure),
        })
        return false, "native_attack_hook_failed " .. tostring(failure)
    end
    successfulNativeShots[character] = (successfulNativeShots[character] or 0) + 1
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("firearm", resolveId(character, nil), "shot_fired", {
            gun = safe(function() return gun:getFullType() end, "unknown"),
            total = successfulNativeShots[character],
        }) end)
    end
    return true, "native_attack_hook " .. tostring(gun:getFullType())
end

function Firearms.nativeShotCount(character)
    return character ~= nil and (successfulNativeShots[character] or 0) or 0
end

return Firearms
