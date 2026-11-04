require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_CompanionService"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_SurvivorNotebook"
require "KS_OrderCatalog"
require "KS_HouseClearing"
-- Optional radial bridge: fail-closed and dormant when the vanilla radial API
-- is absent. Context order menus are separately controlled by their Sandbox option.
pcall(require, "KS_RadialOrders")
if rawget(_G, "KnoxOrderCatalog") == nil then
    _G.KnoxOrderCatalog = { label = function(_, fallback) return fallback or "Order" end }
end

local function catalogLabel(kind, fallback)
    local label = KnoxOrderCatalog.label ~= nil
        and KnoxOrderCatalog.label(kind, fallback) or nil
    return label ~= nil and label ~= "" and label or fallback or tostring(kind)
end

local PartyCommands = rawget(_G, "KnoxPartyCommands") or {}
_G.KnoxPartyCommands = PartyCommands

local function contextOrdersEnabled()
    if KnoxSettings == nil or KnoxSettings.showLegacyContextCommands == nil then return false end
    local ok, enabled = pcall(KnoxSettings.showLegacyContextCommands)
    return ok and enabled == true
end

local function firstSquare(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if square ~= nil then
            return square
        end
    end
    return nil
end

local function areaDirective(kind, square, radius)
    return {
        kind = kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

local function pointDirective(kind, square)
    return {
        kind = kind,
        minX = square:getX(),
        minY = square:getY(),
        maxX = square:getX(),
        maxY = square:getY(),
        z = square:getZ(),
    }
end

local function player(playerNum)
    local n = tonumber(playerNum)
    if n == nil then return nil end
    return getSpecificPlayer(n)
end

-- Feedback observes the existing service receipt; it does not own orders.
local function issueParty(actor, kind, payload)
    if KnoxOrderCatalog.withFeedback ~= nil then
        return KnoxOrderCatalog.withFeedback(catalogLabel(kind) .. " (party)",
            KnoxCompanionService.issueOrderAll, actor, kind, payload)
    end
    return KnoxCompanionService.issueOrderAll(actor, kind, payload)
end

function PartyCommands.followAll(_, playerNum)
    issueParty(player(playerNum), "follow")
end

function PartyCommands.formationAll(_, playerNum, formation, spacing)
    local actor = player(playerNum)
    local changed = 0
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        local apply = KnoxOrderCatalog.withFeedback or function(_, fn, ...) return fn(...) end
        if apply("Formation", KnoxCompanionService.setFormation, actor, id, formation, spacing) then
            changed = changed + 1
        end
    end
    if changed > 0 and KnoxActivityFeed ~= nil then
        KnoxActivityFeed.event("Formation updated for " .. tostring(changed) .. " companions.")
    end
end

function PartyCommands.holdAll(_, playerNum)
    issueParty(player(playerNum), "hold")
end

function PartyCommands.relaxAll(_, playerNum)
    issueParty(player(playerNum), "relax")
end

function PartyCommands.askNeedsAll(_, playerNum)
    issueParty(player(playerNum), "check_needs")
end

function PartyCommands.returnAll(_, playerNum)
    local actor = player(playerNum)
    -- Several homes: the player picks once for the whole party. The old path
    -- fell through to the owner's first base without saying so.
    local picker = rawget(_G, "KnoxBasePicker")
    local bases = actor ~= nil and KnoxCompanionService.baseChoicesFor ~= nil
        and KnoxCompanionService.baseChoicesFor(actor) or {}
    if #bases > 1 and picker ~= nil and picker.choose ~= nil then
        picker.choose(playerNum, "Send the party home to which base?", bases,
            function(baseId)
                if baseId == nil then return end
                local apply = KnoxOrderCatalog.withFeedback
                    or function(_, fn, ...) return fn(...) end
                for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
                    apply("Return to base", KnoxCompanionService.sendToBase, actor, id, baseId)
                end
            end)
        return
    end
    issueParty(actor, "return_to_base")
end

function PartyCommands.boardAll(_, playerNum)
    issueParty(player(playerNum), "enter_vehicle")
end

function PartyCommands.exitAll(_, playerNum)
    issueParty(player(playerNum), "exit_vehicle")
end

function PartyCommands.climbingAll(_, playerNum, allowed)
    issueParty(
        player(playerNum),
        allowed and "allow_climbing" or "disallow_climbing"
    )
end

function PartyCommands.doorsAll(_, playerNum, allowed)
    issueParty(
        player(playerNum),
        allowed and "allow_doors" or "disallow_doors"
    )
end

function PartyCommands.autoLootAll(_, playerNum, allowed)
    issueParty(
        player(playerNum),
        allowed and "enable_autoloot" or "disable_autoloot"
    )
end

function PartyCommands.combatStanceAll(_, playerNum, stance)
    issueParty(player(playerNum), "combat_stance", { stance = stance })
end

function PartyCommands.weaponPreferenceAll(_, playerNum, preference)
    issueParty(player(playerNum), "weapon_preference", { preference = preference })
end

function PartyCommands.autoEquipmentAll(_, playerNum, allowed)
    local apply = KnoxOrderCatalog.withFeedback or function(_, fn, ...) return fn(...) end
    return apply("Automatic equipment", KnoxCompanionService.setAutoEquipmentAll, player(playerNum), allowed)
end

function PartyCommands.directiveAll(_, playerNum, directive)
    if directive ~= nil then
        return issueParty(player(playerNum), directive.kind, directive)
    end
end

function PartyCommands.destinationAll(_, playerNum, directive)
    if directive ~= nil then
        return issueParty(player(playerNum), "go_to", directive)
    end
end

function PartyCommands.cancelPartyDestination(_, playerNum)
    local apply = KnoxOrderCatalog.withFeedback or function(_, fn, ...) return fn(...) end
    return apply("Cancel destination", KnoxCompanionService.cancelPartyDestination, player(playerNum))
end

function PartyCommands.basePreferenceAll(_, playerNum, preference)
    local actor = player(playerNum)
    if actor ~= nil and preference ~= nil then
        issueParty(actor, preference)
    end
end

-- One base's work preference, applied to that base's residents only. The
-- aggregate path used issueOrderAll, which resolves the owner's first base, so
-- a second settlement could never be given a different order from this menu.
function PartyCommands.basePreferenceFor(_, playerNum, baseId, preference)
    local actor = player(playerNum)
    if actor == nil or type(baseId) ~= "string" or preference == nil then return end
    if KnoxPersistence.getBaseResidentIds == nil then return end
    local apply = KnoxOrderCatalog.withFeedback or function(_, fn, ...) return fn(...) end
    local changed = 0
    for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(baseId) or {}) do
        if apply("Base work order", KnoxCompanionService.setBaseJobPreference,
            actor, residentId, preference, baseId) then
            changed = changed + 1
        end
    end
    if changed > 0 and KnoxActivityFeed ~= nil then
        KnoxActivityFeed.event("Work order set for " .. tostring(changed) .. " resident(s).")
    end
end

function PartyCommands.clearDirectiveAll(_, playerNum)
    issueParty(player(playerNum), "resume_normal_duty")
end

-- PT-12: the party sweep is a bounded coordinator over the same
-- loot_building/guard directives, not another order vocabulary. The module
-- owns the transient room plan; this menu only opens or closes it.
function PartyCommands.clearHouse(_, playerNum)
    local actor = player(playerNum)
    local house = rawget(_G, "KnoxHouseClearing")
    if actor ~= nil and house ~= nil and house.issue ~= nil then
        house.issue(actor)
    end
end

function PartyCommands.cancelHouse(_, playerNum)
    local actor = player(playerNum)
    local house = rawget(_G, "KnoxHouseClearing")
    if actor ~= nil and house ~= nil and house.cancel ~= nil then
        house.cancel(actor, "cancelled")
    end
end

function PartyCommands.openActivity()
    KnoxActivityFeed.show()
end

function PartyCommands.toggleActivity()
    if KnoxActivityFeed ~= nil and KnoxActivityFeed.toggle ~= nil then
        KnoxActivityFeed.toggle()
    end
end

function PartyCommands.openNotebook(_, playerNum)
    KnoxSurvivorNotebook.show(playerNum)
end

-- The work preference every resident of one base shares, or nil when the base
-- is empty or split. Read-only, so drawing the menu cannot change duty.
local function sharedBasePreference(baseId)
    if KnoxPersistence.getBaseResidentIds == nil
        or KnoxPersistence.getSurvivorDuty == nil then return nil end
    local shared, set = nil, false
    for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(baseId) or {}) do
        local duty = KnoxPersistence.getSurvivorDuty(residentId) or {}
        local preference = KnoxOrderCatalog.normalizeBasePreference ~= nil
            and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference or "auto")
            or KnoxOrderCatalog.normalize(duty.jobPreference or "auto")
            or "auto"
        if not set then
            shared, set = preference, true
        elseif shared ~= preference then
            return nil
        end
    end
    return shared
end

local function addBasePreferenceOptions(menu, playerNum, baseId, sharedPreference)
    for _, preference in ipairs(KnoxOrderCatalog.basePreferenceOrder or {}) do
        local entry = KnoxOrderCatalog.basePreferences[preference]
        if entry ~= nil then
            local label = preference == "hauling" and "Move Corpses" or entry.label
            local option = menu:addOption(label, PartyCommands,
                PartyCommands.basePreferenceFor, playerNum, baseId, preference)
            menu:setOptionChecked(option, sharedPreference == preference)
        end
    end
end

local function populate(menu, playerNum, square)
    local actor = player(playerNum)
    if contextOrdersEnabled() then
    -- One read-out for the whole menu: the companion service owns the durable
    -- duty/policy defaults, so a checkmark here and the label on the wheel
    -- cannot report different settings for the same party.
    local common = type(KnoxCompanionService.commonTactics) == "function"
        and KnoxCompanionService.commonTactics(actor) or {}
    -- Everyday party orders in one place instead of scattered top-level rows.
    local ordersRoot = menu:addOption("Orders", nil, nil)
    local ordersMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(ordersRoot, ordersMenu)
    local follow = ordersMenu:addOption(KnoxOrderCatalog.label("follow"), PartyCommands, PartyCommands.followAll, playerNum)
    local hold = ordersMenu:addOption(KnoxOrderCatalog.label("hold"), PartyCommands, PartyCommands.holdAll, playerNum)
    local relax = ordersMenu:addOption(KnoxOrderCatalog.label("relax"), PartyCommands, PartyCommands.relaxAll, playerNum)
    ordersMenu:addOption(KnoxOrderCatalog.label("check_needs"), PartyCommands, PartyCommands.askNeedsAll, playerNum)
    ordersMenu:setOptionChecked(follow, common.order == "follow")
    ordersMenu:setOptionChecked(hold, common.order == "hold")
    ordersMenu:setOptionChecked(relax, common.order == "relax")
    local cancelDestination = ordersMenu:addOption("Cancel Party Destination", PartyCommands,
        PartyCommands.cancelPartyDestination, playerNum)
    local hasPartyDestination = KnoxCompanionService.hasPartyDestination ~= nil
        and KnoxCompanionService.hasPartyDestination(actor) or false
    cancelDestination.notAvailable = not hasPartyDestination
    local resume = ordersMenu:addOption(KnoxOrderCatalog.label("resume_normal_duty"), PartyCommands,
        PartyCommands.clearDirectiveAll, playerNum)
    local hasDirective = hasPartyDestination
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        if duty.directive ~= nil then hasDirective = true break end
    end
    resume.notAvailable = not hasDirective
    local playerId = actor ~= nil and KnoxCompanionService.getPlayerId(actor) or nil
    local baseManager = rawget(_G, "KnoxBaseManager")
    local base = baseManager ~= nil and playerId ~= nil
        and baseManager.getForOwner("player", playerId) or nil
    if base ~= nil then
        ordersMenu:addOption(KnoxOrderCatalog.label("return_to_base"), PartyCommands, PartyCommands.returnAll, playerNum)
        -- Keep settlement duty choices on the same canonical order catalogue
        -- used by the Notebook and resident scheduler. This is a player-facing
        -- convenience only; issueOrderAll remains the sole dispatch boundary.
        local baseOrders = menu:addOption(catalogLabel("base_work_orders", "Base Work Orders"), nil, nil)
        local baseOrderMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(baseOrders, baseOrderMenu)
        local bases = KnoxCompanionService.baseChoicesFor ~= nil
            and KnoxCompanionService.baseChoicesFor(actor) or {}
        if #bases == 0 then bases = { base } end
        for _, candidate in ipairs(bases) do
            if type(candidate) == "table" and candidate.id ~= nil then
                local sharedPreference = sharedBasePreference(candidate.id)
                if #bases == 1 then
                    addBasePreferenceOptions(baseOrderMenu, playerNum, candidate.id, sharedPreference)
                else
                    local name = type(candidate.name) == "string" and candidate.name ~= ""
                        and candidate.name or tostring(candidate.id)
                    local root = baseOrderMenu:addOption(name, nil, nil)
                    local perBase = ISContextMenu:getNew(baseOrderMenu)
                    baseOrderMenu:addSubMenu(root, perBase)
                    addBasePreferenceOptions(perBase, playerNum, candidate.id, sharedPreference)
                end
            end
        end
    end
    -- Keep Exit reachable after the player has already stepped out. Vehicle
    -- actions validate each companion and seat at the existing service boundary.
    if actor ~= nil then
        local vehicleRoot = menu:addOption(catalogLabel("vehicle_orders", "Vehicle Orders"), nil, nil)
        local vehicleMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(vehicleRoot, vehicleMenu)
        local board = vehicleMenu:addOption(KnoxOrderCatalog.label("enter_vehicle"), PartyCommands, PartyCommands.boardAll, playerNum)
        board.notAvailable = actor.getVehicle == nil or actor:getVehicle() == nil
        vehicleMenu:addOption(KnoxOrderCatalog.label("exit_vehicle"), PartyCommands, PartyCommands.exitAll, playerNum)
    end
    local tactics = menu:addOption("Tactics & Behavior", nil, nil)
    local tacticsMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(tactics, tacticsMenu)
    local traversal = tacticsMenu:addOption(catalogLabel("traversal_orders", "Vaulting and Climbing"), nil, nil)
    local traversalMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(traversal, traversalMenu)
    local allow = traversalMenu:addOption(KnoxOrderCatalog.label("allow_climbing"), PartyCommands, PartyCommands.climbingAll, playerNum, true)
    local disallow = traversalMenu:addOption(KnoxOrderCatalog.label("disallow_climbing"), PartyCommands, PartyCommands.climbingAll, playerNum, false)
    traversalMenu:setOptionChecked(allow, common.climbing == true)
    traversalMenu:setOptionChecked(disallow, common.climbing == false)
    local doors = tacticsMenu:addOption(catalogLabel("door_orders", "Doors and Windows"), nil, nil)
    local doorsMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(doors, doorsMenu)
    local doorsAllow = doorsMenu:addOption(KnoxOrderCatalog.label("allow_doors"), PartyCommands, PartyCommands.doorsAll, playerNum, true)
    local doorsDisallow = doorsMenu:addOption(KnoxOrderCatalog.label("disallow_doors"), PartyCommands, PartyCommands.doorsAll, playerNum, false)
    doorsMenu:setOptionChecked(doorsAllow, common.doors == true)
    doorsMenu:setOptionChecked(doorsDisallow, common.doors == false)
    local formation = tacticsMenu:addOption("Formation", nil, nil)
    local formationMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(formation, formationMenu)
    for _, shape in ipairs({ { "Paired", "paired" }, { "Single File", "single_file" } }) do
        for spacing = 1, 3 do
            local option = formationMenu:addOption(shape[1] .. " - spacing " .. tostring(spacing), PartyCommands,
                PartyCommands.formationAll, playerNum, shape[2], spacing)
            formationMenu:setOptionChecked(option, common.formation == shape[2]
                and common.spacing == spacing)
        end
    end
    local combat = tacticsMenu:addOption(catalogLabel("combat_stance", "Combat Stance"), nil, nil)
    local combatMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(combat, combatMenu)
    for _, choice in ipairs({ { "Passive - stay close", "passive" },
        { "Defensive - protect us", "defensive" }, { "Aggressive - clear threats", "aggressive" } }) do
        local option = combatMenu:addOption(choice[1], PartyCommands,
            PartyCommands.combatStanceAll, playerNum, choice[2])
        combatMenu:setOptionChecked(option, common.stance == choice[2])
    end
    local weapon = tacticsMenu:addOption(catalogLabel("weapon_preference", "Weapon Preference"), nil, nil)
    local weaponMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(weapon, weaponMenu)
    for _, choice in ipairs({ { "Prefer Melee", "melee" }, { "Prefer Ranged", "ranged" },
        { "Survivor Choice", "auto" } }) do
        local option = weaponMenu:addOption(choice[1], PartyCommands,
            PartyCommands.weaponPreferenceAll, playerNum, choice[2])
        weaponMenu:setOptionChecked(option, common.weapon == choice[2])
    end
    local equipment = tacticsMenu:addOption("Automatic Equipment Upgrades", nil, nil)
    local equipmentMenu = ISContextMenu:getNew(tacticsMenu)
    tacticsMenu:addSubMenu(equipment, equipmentMenu)
    for _, choice in ipairs({ { "Upgrade Better Gear Automatically", true },
        { "Keep Current Equipment", false } }) do
        local option = equipmentMenu:addOption(choice[1], PartyCommands,
            PartyCommands.autoEquipmentAll, playerNum, choice[2])
        equipmentMenu:setOptionChecked(option, common.equipment == choice[2])
    end
    if square ~= nil then
        local location = menu:addOption("Orders for This Location", nil, nil)
        local locationMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(location, locationMenu)
        locationMenu:addOption(catalogLabel("move_party", "Move Party Here"), PartyCommands, PartyCommands.destinationAll,
            playerNum, pointDirective("go_to", square))
        locationMenu:addOption(catalogLabel("guard_location", "Guard This Location"), PartyCommands, PartyCommands.directiveAll,
            playerNum, pointDirective("guard", square))
        locationMenu:addOption(catalogLabel("patrol_location", "Patrol This Area"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("patrol_area", square, 10))
        local loot = locationMenu:addOption(catalogLabel("loot_orders", "Auto-Loot"), nil, nil)
        local lootMenu = ISContextMenu:getNew(locationMenu)
        locationMenu:addSubMenu(loot, lootMenu)
        local lootOn = lootMenu:addOption(KnoxOrderCatalog.label("enable_autoloot"), PartyCommands,
            PartyCommands.autoLootAll, playerNum, true)
        local lootOff = lootMenu:addOption(KnoxOrderCatalog.label("disable_autoloot"), PartyCommands,
            PartyCommands.autoLootAll, playerNum, false)
        lootMenu:setOptionChecked(lootOn, common.loot == true)
        lootMenu:setOptionChecked(lootOff, common.loot == false)
        local house = rawget(_G, "KnoxHouseClearing")
        local inBuilding = square ~= nil and square.getBuilding ~= nil
            and square:getBuilding() ~= nil
        if house ~= nil and inBuilding then
            if house.activeFor ~= nil and house.activeFor(actor) then
                locationMenu:addOption("Cancel House Sweep", PartyCommands,
                    PartyCommands.cancelHouse, playerNum)
            else
                local can, reason = false, nil
                if house.canIssue ~= nil then can, reason = house.canIssue(actor, square) end
                local label = can and "Clear This House"
                    or ("Clear This House (" .. tostring(house.shortReason ~= nil
                        and house.shortReason(reason) or "not available here") .. ")")
                local option = locationMenu:addOption(label, PartyCommands,
                    PartyCommands.clearHouse, playerNum)
                if not can then option.notAvailable = true end
            end
        end
        local survival = locationMenu:addOption(catalogLabel("survival_orders", "Survival Orders"), nil, nil)
        local survivalMenu = ISContextMenu:getNew(locationMenu)
        locationMenu:addSubMenu(survival, survivalMenu)
        survivalMenu:addOption(KnoxOrderCatalog.label("find_food"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("find_food", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_water"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("find_water", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_medical"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_medical", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_weapon"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_weapon", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_tools"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_tools", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("clean_inventory"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("clean_inventory", square, 12))
    end
    end
    local manageRoot = menu:addOption("Manage", nil, nil)
    local manageMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(manageRoot, manageMenu)
    manageMenu:addOption(KnoxOrderCatalog.label("open_notebook"), PartyCommands,
        PartyCommands.openNotebook, playerNum)
    return menu
end

local function hasPlayerBaseResidents(actor)
    if actor == nil or KnoxPersistence == nil
        or KnoxPersistence.getBaseResidentIds == nil then
        return false
    end
    local playerId = KnoxCompanionService.getPlayerId(actor)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = manager ~= nil and playerId ~= nil
        and manager.getForOwner("player", playerId) or nil
    return base ~= nil and #KnoxPersistence.getBaseResidentIds(base.id) > 0
end

function PartyCommands.openMenu(playerNum, x, y, square)
    return populate(ISContextMenu.get(playerNum, x, y), playerNum, square)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    local actor = player(playerNum)
    local square = firstSquare(worldObjects)
    if square == nil then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    if KnoxSettings ~= nil and KnoxSettings.enabled ~= nil
        and KnoxSettings.enabled() and KnoxSettings.showActivityFeed ~= nil
        and KnoxSettings.showActivityFeed() then
        -- No key of its own: this menu entry is how the digest opens.
        context:addOption((KnoxActivityFeed ~= nil and KnoxActivityFeed.isVisible ~= nil
            and KnoxActivityFeed.isVisible() and "Hide recent events" or "Recent events"),
            PartyCommands, PartyCommands.toggleActivity)
    end
    if KnoxSettings == nil or KnoxSettings.enabled == nil or not KnoxSettings.enabled()
        or not contextOrdersEnabled() or actor == nil
        or (#KnoxCompanionService.getCompanionIds(actor) == 0
            and not hasPlayerBaseResidents(actor)) then
        return
    end
    local root = context:addOption(catalogLabel("party_orders", "Party Orders"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    populate(menu, playerNum, square)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return PartyCommands
