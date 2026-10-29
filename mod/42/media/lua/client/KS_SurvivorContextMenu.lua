require "ISUI/ISContextMenu"
require "ISUI/ISModalDialog"
require "ISUI/ISWorldObjectContextMenu"
require "XpSystem/ISUI/ISHealthPanel"
require "TimedActions/ISMedicalCheckAction"
require "TimedActions/WalkToTimedAction"
require "KS_CompanionService"
require "KS_BaseManager"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_SurvivorCard"
require "KS_CompanionInventory"
require "KS_Settings"
require "KS_TradeUI"
require "KS_OrderCatalog"
pcall(require, "KS_SurvivorInteractionUI")
if rawget(_G, "KnoxOrderCatalog") == nil then
    _G.KnoxOrderCatalog = { label = function(_, _, fallback) return fallback or "Order" end }
end

local SurvivorContextMenu = rawget(_G, "KnoxSurvivorContextMenu") or {}
_G.KnoxSurvivorContextMenu = SurvivorContextMenu

local WORLD_PICK_RADIUS = 2.25
local CONVERSATION_DISTANCE = 4
local function refreshHud(playerNum)
    local hud = rawget(_G, "KnoxCompanionHUD")
    if hud ~= nil and hud.refresh ~= nil then
        hud.refresh(playerNum)
    end
end

local function runService(playerNum, callback, survivorId)
    local player = getSpecificPlayer(playerNum)
    if player == nil then
        return false, "player_unavailable"
    end
    local feedback = KnoxOrderCatalog.withFeedback or function(_, fn, ...) return fn(...) end
    local success, result, reason = pcall(feedback, "Survivor request", callback, player, survivorId)
    if not success then
        print(
            "[KnoxSurvivors][ContextMenu] action failed survivor="
                .. tostring(survivorId) .. " error=" .. tostring(result)
        )
        return false, tostring(result)
    end
    refreshHud(playerNum)
    return result == true, reason
end

local function distanceToPlayer(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or character == nil then
        return nil
    end
    local success, distance = pcall(function()
        local dx = player:getX() - character:getX()
        local dy = player:getY() - character:getY()
        if player:getZ() ~= character:getZ() then
            return math.huge
        end
        return math.sqrt(dx * dx + dy * dy)
    end)
    return success and distance or nil
end

local function unavailable(option)
    if option ~= nil then
        option.notAvailable = true
    end
    return option
end

-- Right-click orders are an explicit alternate input mode. Never silently
-- restore them when the radial API is unavailable: the player's saved choice
-- controls this surface for the whole save.
local function legacyCommandsVisible()
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.showLegacyContextCommands ~= nil then
        local ok, enabled = pcall(function()
            return settings.showLegacyContextCommands()
        end)
        return ok and enabled == true
    end
    return false
end

local function onTalk(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.talk, survivorId)
end

local function onOpenInteraction(_, playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
    if player == nil or interaction == nil or interaction.open == nil then return end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local character = runtime ~= nil and runtime.getCharacter ~= nil
        and runtime.getCharacter(survivorId) or nil
    if character == nil then return end
    local name = "Survivor"
    local model = rawget(_G, "KnoxSurvivorViewModel")
    local view = model ~= nil and model.getSurvivor ~= nil
        and model.getSurvivor(survivorId, playerNum) or nil
    if view ~= nil and view.displayName ~= nil and tostring(view.displayName) ~= "" then
        name = tostring(view.displayName)
    end
    local ok, opened = pcall(interaction.open, playerNum,
        { id = survivorId, character = character, name = name }, player)
    if not ok or opened ~= true then
        local feed = rawget(_G, "KnoxActivityFeed")
        if feed ~= nil and feed.event ~= nil then
            feed.event("Could not open survivor interaction.")
        end
    end
end

local function onAskNeeds(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "check_needs")
    end, survivorId)
end

local function onSocialAct(_, playerNum, survivorId, act)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.socialAct(player, id, act)
    end, survivorId)
end

local function onTrade(_, playerNum, survivorId)
    KnoxTradeUI.show(playerNum, survivorId)
end

local function onGiveItem(_, playerNum, survivorId)
    KnoxTradeUI.showGift(playerNum, survivorId)
end

local function onViewSurvivor(_, playerNum, survivorId)
    KnoxSurvivorCard.show(playerNum, survivorId)
end

local function medicalMessage(player, survivorId, reason)
    print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " " .. reason)
    if player ~= nil then player:Say(reason) end
    return false, reason
end

local function medicalReach(player, patient)
    if ISHealthPanel.IsCharactersInSameCar(player, patient) then return true end
    local from, to = player:getCurrentSquare(), patient:getCurrentSquare()
    return from ~= nil and to ~= nil and player:getZ() == patient:getZ()
        and math.abs(player:getX() - patient:getX()) <= 2
        and math.abs(player:getY() - patient:getY()) <= 2
        and (from == to or from:canReachTo(to))
end

function SurvivorContextMenu.medicalCheck(playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local patient = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or patient == nil or player:isDead() or patient:isDead() then
        return medicalMessage(player, survivorId, "That survivor is no longer available.")
    end
    local queue = ISTimedActionQueue.queues[player]
    for _, pending in ipairs(queue ~= nil and queue.queue or {}) do
        if pending.knoxMedicalPatient == patient then return true, "already_queued" end
    end
    local sameCar = ISHealthPanel.IsCharactersInSameCar(player, patient)
    local square = patient:getCurrentSquare()
    if not sameCar and (square == nil or player:getZ() ~= patient:getZ()
        or (distanceToPlayer(player, survivorId) or math.huge) > CONVERSATION_DISTANCE
        or not luautils.walkAdjTest(player, square)) then
        return medicalMessage(player, survivorId, "I need to get closer to check them.")
    end
    -- Temporarily hold a following companion while the doctor approaches and
    -- during the native check. Restore Follow only if no newer player order
    -- replaced this temporary Hold in the meantime.
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    local resumeFollow = type(duty) == "table" and duty.mode == "companion"
        and duty.order == "follow" and duty.directive == nil
    local heldRevision = nil
    if resumeFollow then
        local held = runService(playerNum, function(p, id)
            return KnoxCompanionService.issueOrder(p, id, "hold")
        end, survivorId)
        if held then
            local heldDuty = KnoxPersistence.getSurvivorDuty(survivorId)
            heldRevision = type(heldDuty) == "table" and tonumber(heldDuty.revision) or nil
        else
            resumeFollow = false
        end
    end
    local restoredFollow = false
    local function restoreFollow()
        if not resumeFollow or restoredFollow then return end
        local current = KnoxPersistence.getSurvivorDuty(survivorId)
        if type(current) ~= "table" or current.mode ~= "companion"
            or current.order ~= "hold"
            or tonumber(current.revision) ~= heldRevision then return end
        restoredFollow = true
        runService(playerNum, function(p, id)
            return KnoxCompanionService.issueOrder(p, id, "follow")
        end, survivorId)
    end

    if not sameCar and not luautils.walkAdj(player, square) then
        restoreFollow()
        return medicalMessage(player, survivorId, "I can't reach them from here.")
    end
    local action = ISMedicalCheckAction:new(player, patient)
    action.knoxMedicalPatient = patient
    local nativeValid, nativeStart, nativeStop = action.isValid, action.start, action.stop
    local nativePerform = action.perform
    local function available()
        return KnoxSurvivorRuntime.getCharacter(survivorId) == patient
            and not player:isDead() and not patient:isDead() and medicalReach(player, patient)
    end
    function action:isValid()
        -- Snapshot at action start, not before the doctor has finished walking.
        if not self.knoxMedicalStarted then
            self.otherPlayerX, self.otherPlayerY = patient:getX(), patient:getY()
        end
        local valid = available() and nativeValid(self)
        if not valid and not self.knoxMedicalReported then
            self.knoxMedicalReported = true
            medicalMessage(player, survivorId, "Medical check interrupted. Stay close and try again.")
        end
        return valid
    end
    function action:start()
        self.otherPlayerX, self.otherPlayerY = patient:getX(), patient:getY()
        self.knoxMedicalStarted = true
        nativeStart(self)
    end
    function action:stop()
        if not self.knoxMedicalReported then
            self.knoxMedicalReported = true
            medicalMessage(player, survivorId, "Medical check cancelled.")
        end
        nativeStop(self)
        restoreFollow()
    end
    function action:perform()
        if not self:isValid() then
            nativeStop(self)
            restoreFollow()
            return
        end
        nativePerform(self)
        -- Vanilla Medical Check opens the real Health Panel and may keep the
        -- patient stationary while the player treats them. Restore Follow
        -- when that native panel leaves the UI, not when its opening action
        -- merely completes.
        local medicalAction = rawget(_G, "ISMedicalCheckAction")
        local windows = medicalAction ~= nil and medicalAction.HealthWindows or nil
        local healthWindow = type(windows) == "table" and windows[patient] or nil
        if healthWindow ~= nil and type(healthWindow.removeFromUIManager) == "function" then
            local nativeRemove = healthWindow.removeFromUIManager
            healthWindow.removeFromUIManager = function(window, ...)
                window.removeFromUIManager = nativeRemove
                local result = nativeRemove(window, ...)
                restoreFollow()
                return result
            end
        else
            restoreFollow()
        end
        print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " check_completed")
    end
    ISTimedActionQueue.add(action)
    print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " check_queued")
    return true, "queued"
end

local function onMedicalCheck(_, playerNum, survivorId)
    SurvivorContextMenu.medicalCheck(playerNum, survivorId)
end

local function onManageInventory(_, playerNum, survivorId)
    if KnoxOrderCatalog.withFeedback ~= nil then
        return KnoxOrderCatalog.withFeedback("Manage inventory", KnoxCompanionInventory.show, playerNum, survivorId)
    end
    return KnoxCompanionInventory.show(playerNum, survivorId)
end

local function onRecruit(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "recruit")
    end, survivorId)
end

local function onFollow(_, playerNum, survivorId)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local callback = duty.mode == "base"
        and KnoxCompanionService.activateFromBase
        or function(player, id)
            return KnoxCompanionService.issueOrder(player, id, "follow")
        end
    runService(playerNum, callback, survivorId)
end

local function onHold(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "hold")
    end, survivorId)
end

local function onRelax(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "relax")
    end, survivorId)
end

local function onCombatStance(_, playerNum, survivorId, stance)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "combat_stance", { stance = stance })
    end, survivorId)
end

local function onFormation(_, playerNum, survivorId, formation, spacing)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setFormation(player, id, formation, spacing)
    end, survivorId)
end

local function onWeaponPreference(_, playerNum, survivorId, preference)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "weapon_preference", { preference = preference })
    end, survivorId)
end

local function onAutoEquipment(_, playerNum, survivorId, allowed)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setAutoEquipment(player, id, allowed)
    end, survivorId)
end

local function addAutoEquipmentMenu(parent, playerNum, survivorId)
    local root = parent:addOption("Automatic Equipment Upgrades", nil, nil)
    local submenu = ISContextMenu:getNew(parent)
    parent:addSubMenu(root, submenu)
    local policies = KnoxPersistence.getSurvivorPolicies ~= nil
        and (KnoxPersistence.getSurvivorPolicies(survivorId) or {}) or {}
    local enabled = policies.autoEquipment ~= false
    for _, choice in ipairs({ { "Upgrade Better Gear Automatically", true },
        { "Keep Current Equipment", false } }) do
        local option = submenu:addOption(choice[1], SurvivorContextMenu,
            onAutoEquipment, playerNum, survivorId, choice[2])
        submenu:setOptionChecked(option, enabled == choice[2])
    end
end

local function onClimbing(_, playerNum, survivorId, allowed)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id,
            allowed and "allow_climbing" or "disallow_climbing")
    end, survivorId)
end

local function onDoors(_, playerNum, survivorId, allowed)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id,
            allowed and "allow_doors" or "disallow_doors")
    end, survivorId)
end

local function onUnstick(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.unstick(player, id)
    end, survivorId)
end

local function onBoardPlayerVehicle(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "enter_vehicle")
    end, survivorId)
end

local function onDriveAhead(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "drive_ahead")
    end, survivorId)
end

local function onDriveNearestVehicle(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "drive_nearest_vehicle")
    end, survivorId)
end

local function onExitVehicle(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "exit_vehicle")
    end, survivorId)
end

local function pointDirective(kind, square)
    if square == nil then
        return nil
    end
    return {
        kind = kind,
        minX = square:getX(),
        minY = square:getY(),
        maxX = square:getX(),
        maxY = square:getY(),
        z = square:getZ(),
    }
end

local function areaDirective(kind, square, radius)
    if square == nil then return nil end
    local r = math.max(1, tonumber(radius) or 10)
    return {
        kind = kind,
        minX = square:getX() - r,
        minY = square:getY() - r,
        maxX = square:getX() + r,
        maxY = square:getY() + r,
        z = square:getZ(),
    }
end

local function onAutoLoot(_, playerNum, survivorId, allowed)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id,
            allowed and "enable_autoloot" or "disable_autoloot")
    end, survivorId)
end

local function onNeedOrder(_, playerNum, survivorId, kind)
    runService(playerNum, function(player, id)
        local directive = areaDirective(kind, player:getCurrentSquare(), 12)
        if directive == nil then return false, "destination_unavailable" end
        return KnoxCompanionService.issueOrder(player, id, kind, directive)
    end, survivorId)
end

local function onResidentLootRuns(_, playerNum, survivorId, allowed)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setResidentLootRuns(player, id, allowed)
    end, survivorId)
end

local function onMoveToPlayer(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        local directive = pointDirective("go_to", player:getCurrentSquare())
        if directive == nil then return false, "destination_unavailable" end
        return KnoxCompanionService.issueOrder(player, id, "go_to", directive)
    end, survivorId)
end

local function onGuardHere(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local directive = pointDirective("guard",
            character ~= nil and character:getCurrentSquare() or nil)
        if directive == nil then return false, "destination_unavailable" end
        return KnoxCompanionService.issueOrder(player, id, "guard", directive)
    end, survivorId)
end

local function onPatrolHere(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local square = character ~= nil and character:getCurrentSquare()
            or player:getCurrentSquare()
        local directive = areaDirective("patrol_area", square, 10)
        if directive == nil then return false, "destination_unavailable" end
        return KnoxCompanionService.issueOrder(player, id, "patrol_area", directive)
    end, survivorId)
end

local function onReturnToBase(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "return_to_base")
    end, survivorId)
end

local function onResumeNormalDuty(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "resume_normal_duty")
    end, survivorId)
end

local function onBaseJobPreference(_, playerNum, survivorId, preference)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, preference)
    end, survivorId)
end

local function onDismissConfirmed(_, button, playerNum, survivorId)
    if button == nil or button.internal ~= "YES" then
        return
    end
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueOrder(player, id, "dismiss")
    end, survivorId)
end

local function onDismiss(_, playerNum, survivorId)
    local snapshot = KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)
    local name = snapshot ~= nil and snapshot.displayName or "this survivor"
    local width = 320
    local height = 120
    local x = getPlayerScreenLeft(playerNum)
        + (getPlayerScreenWidth(playerNum) - width) / 2
    local y = getPlayerScreenTop(playerNum)
        + (getPlayerScreenHeight(playerNum) - height) / 2
    local modal = ISModalDialog:new(
        x,
        y,
        width,
        height,
        "Tell " .. name .. " to leave your group?",
        true,
        SurvivorContextMenu,
        onDismissConfirmed,
        playerNum,
        playerNum,
        survivorId
    )
    modal:initialise()
    modal:setRenderThisPlayerOnly(playerNum)
    modal:addToUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, modal)
    end
end

local function addRecruitOption(menu, player, survivorId, closeEnough)
    local success, ready, reason = pcall(
        KnoxCompanionService.canRecruit,
        player,
        survivorId
    )
    if not success then
        ready = false
        reason = "unavailable"
    end
    if ready and closeEnough then
        return menu:addOption("Recruit", SurvivorContextMenu, onRecruit, player:getPlayerNum(), survivorId)
    end

    local label = "Recruit"
    if not closeEnough then
        label = "Recruit (too far away)"
    elseif reason == "hostile" then
        label = "Recruit (hostile)"
    elseif reason == "already_with_group" then
        label = "Recruit (already with a group)"
    elseif reason == "no_contact" then
        label = "Recruit (no clear contact)"
    elseif reason == "needs_time" then
        label = "Recruit (needs time)"
    elseif reason == "prefers_alone" then
        label = "Recruit (prefers independence)"
    elseif reason == "lure" then
        label = "Recruit (untrustworthy)"
    elseif reason == "dangerous" then
        label = "Recruit (dangerous)"
    else
        label = "Recruit (not available)"
    end
    return unavailable(menu:addOption(label, nil, nil))
end

function SurvivorContextMenu.populate(menu, playerNum, survivorId, surface)
    local player = getSpecificPlayer(playerNum)
    if menu == nil or player == nil or type(survivorId) ~= "string" then
        return false
    end

    local playerId = KnoxCompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId) or {}
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local owned = affiliation.kind == "player" and affiliation.ownerId == playerId
    local commands = surface == "commands"
    local showCommands = surface == "all" or commands or legacyCommandsVisible()
    if not commands then
        local interact = menu:addOption("Interact", SurvivorContextMenu, onOpenInteraction, playerNum, survivorId)
        local distance = distanceToPlayer(player, survivorId)
        if distance == nil or distance > CONVERSATION_DISTANCE then unavailable(interact) end
    end
    if not commands and owned and (duty.mode == "companion" or duty.mode == "base") then
        menu:addOption(
            "View Survivor",
            SurvivorContextMenu,
            onViewSurvivor,
            playerNum,
            survivorId
        )
    end

    local distance = distanceToPlayer(player, survivorId)
    local closeEnough = distance ~= nil and distance <= CONVERSATION_DISTANCE

    if not owned then
        if not commands and showCommands then addRecruitOption(menu, player, survivorId, closeEnough) end
        return true
    end

    if duty.mode == "companion" and not commands then
        local careMenu = menu
        if uiMenus then
            local careRoot = menu:addOption("Care", nil, nil)
            careMenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(careRoot, careMenu)
        end
        local inventoryLabel = closeEnough and "Manage Inventory"
            or "Manage Inventory (too far away)"
        local inventory = careMenu:addOption(
            inventoryLabel,
            SurvivorContextMenu,
            onManageInventory,
            playerNum,
            survivorId
        )
        if not closeEnough then
            unavailable(inventory)
        end
        local medicalLabel = closeEnough and "Medical Check" or "Medical Check (too far away)"
        local medical = careMenu:addOption(medicalLabel, SurvivorContextMenu,
            onMedicalCheck, playerNum, survivorId)
        if not closeEnough then unavailable(medical) end
    end

    if duty.mode == "base" then
        -- Base residents can be temporarily activated as companions. Keep that
        -- transition explicit in the menu so it is not confused with the
        -- ordinary Follow command, which is already owned by companions.
        if not commands then
        local residentCareMenu = menu
        if uiMenus then
            local careRoot = menu:addOption("Care", nil, nil)
            residentCareMenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(careRoot, residentCareMenu)
        end
        local residentInventoryLabel = closeEnough and "Manage Inventory"
            or "Manage Inventory (too far away)"
        local residentInventory = residentCareMenu:addOption(
            residentInventoryLabel,
            SurvivorContextMenu,
            onManageInventory,
            playerNum,
            survivorId
        )
        if not closeEnough then unavailable(residentInventory) end
        local medicalLabel = closeEnough and "Medical Check" or "Medical Check (too far away)"
        local medical = residentCareMenu:addOption(medicalLabel, SurvivorContextMenu,
            onMedicalCheck, playerNum, survivorId)
        if not closeEnough then unavailable(medical) end
        end
        if showCommands then
        menu:addOption(KnoxOrderCatalog.label("follow"), SurvivorContextMenu,
            onFollow, playerNum, survivorId)
        local orders = menu:addOption("Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(orders, ordersMenu)
        addAutoEquipmentMenu(ordersMenu, playerNum, survivorId)
        local jobs = ordersMenu:addOption("Base Work Orders", nil, nil)
        local jobsMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(jobs, jobsMenu)
        for _, preference in ipairs(KnoxOrderCatalog.basePreferenceOrder) do
            local choice = KnoxOrderCatalog.get(preference)
            local label = preference == "hauling" and "Move Corpses"
                or (choice ~= nil and choice.label or preference)
            local option = jobsMenu:addOption(label, SurvivorContextMenu,
                onBaseJobPreference, playerNum, survivorId, preference)
            jobsMenu:setOptionChecked(option, duty.jobPreference == preference
                or (duty.jobPreference == nil and preference == "auto"))
        end
        local supply = ordersMenu:addOption("Survival Orders", nil, nil)
        local supplyMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(supply, supplyMenu)
        for _, kind in ipairs({ "find_food", "find_water", "find_medical", "find_weapon", "find_tools",
            "find_wood", "find_materials", "find_clothing", "find_ammo" }) do
            supplyMenu:addOption(KnoxOrderCatalog.label(kind), SurvivorContextMenu, onNeedOrder,
                playerNum, survivorId, kind)
        end
        local cancelSupply = ordersMenu:addOption(
            KnoxOrderCatalog.label("resume_normal_duty"), SurvivorContextMenu,
            onResumeNormalDuty, playerNum, survivorId
        )
        cancelSupply.notAvailable = duty.baseSupplyOrder == nil
        local stayHome = duty.allowLootRuns ~= true
        local supplyOption = ordersMenu:addOption(
            "Stay Home During Supply Runs",
            SurvivorContextMenu, onResidentLootRuns, playerNum, survivorId, stayHome
        )
        ordersMenu:setOptionChecked(supplyOption, stayHome)
        end
    elseif duty.mode == "companion" then
        if showCommands then
        local orders = menu:addOption("Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(orders, ordersMenu)
        local follow = ordersMenu:addOption(KnoxOrderCatalog.label("follow"), SurvivorContextMenu, onFollow, playerNum, survivorId)
        local hold = ordersMenu:addOption(KnoxOrderCatalog.label("hold"), SurvivorContextMenu, onHold, playerNum, survivorId)
        local relax = ordersMenu:addOption(duty.order == "relax" and "Stop Relaxing" or KnoxOrderCatalog.label("relax"),
            SurvivorContextMenu, duty.order == "relax" and onFollow or onRelax, playerNum, survivorId)
        ordersMenu:setOptionChecked(follow, duty.order == "follow")
        ordersMenu:setOptionChecked(hold, duty.order == "hold")
        ordersMenu:setOptionChecked(relax, duty.order == "relax")
        local resume = ordersMenu:addOption(KnoxOrderCatalog.label("resume_normal_duty"), SurvivorContextMenu,
            onResumeNormalDuty, playerNum, survivorId)
        resume.notAvailable = duty.directive == nil
        local movementRoot = ordersMenu:addOption("Movement", nil, nil)
        local movementMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(movementRoot, movementMenu)
        movementMenu:addOption(KnoxOrderCatalog.label("go_to"), SurvivorContextMenu, onMoveToPlayer, playerNum, survivorId)
        movementMenu:addOption(KnoxOrderCatalog.label("guard"), SurvivorContextMenu, onGuardHere, playerNum, survivorId)
        movementMenu:addOption(KnoxOrderCatalog.label("patrol_area"), SurvivorContextMenu, onPatrolHere, playerNum, survivorId)
        local companion = KnoxSurvivorRuntime.getCharacter(survivorId)
        if companion ~= nil and companion:getVehicle() ~= nil then
            ordersMenu:addOption(KnoxOrderCatalog.label("exit_vehicle"), SurvivorContextMenu,
                onExitVehicle, playerNum, survivorId)
        elseif player:getVehicle() ~= nil then
            ordersMenu:addOption(KnoxOrderCatalog.label("enter_vehicle"), SurvivorContextMenu,
                onBoardPlayerVehicle, playerNum, survivorId)
            local drive = ordersMenu:addOption(
                KnoxOrderCatalog.label("drive_ahead", "Take Driver Seat & Drive"),
                SurvivorContextMenu, onDriveAhead, playerNum, survivorId)
            if player.getVehicle ~= nil and player:getVehicle() ~= nil
                and player:getVehicle().isDriver ~= nil
                and player:getVehicle():isDriver(player) then
                drive.notAvailable = true
            end
        else
            ordersMenu:addOption(KnoxOrderCatalog.label("drive_nearest_vehicle"),
                SurvivorContextMenu, onDriveNearestVehicle, playerNum, survivorId)
        end
        local tacticsRoot = ordersMenu:addOption("Tactics & Behavior", nil, nil)
        local tacticsMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(tacticsRoot, tacticsMenu)
        local formationRoot = tacticsMenu:addOption("Formation", nil, nil)
        local formationMenu = ISContextMenu:getNew(tacticsMenu)
        tacticsMenu:addSubMenu(formationRoot, formationMenu)
        for _, shape in ipairs({ { "Paired", "paired" }, { "Single File", "single_file" } }) do
            for spacing = 1, 3 do
                local option = formationMenu:addOption(shape[1] .. " - spacing " .. tostring(spacing),
                    SurvivorContextMenu, onFormation, playerNum, survivorId, shape[2], spacing)
                formationMenu:setOptionChecked(option,
                    duty.followerFormation == shape[2] and duty.followerSpacing == spacing)
            end
        end
        local stanceRoot = tacticsMenu:addOption("Combat Stance", nil, nil)
        local stanceMenu = ISContextMenu:getNew(tacticsMenu)
        tacticsMenu:addSubMenu(stanceRoot, stanceMenu)
        local stance = duty.combatStance or "defensive"
        for _, choice in ipairs({
            { "Passive — stay close", "passive" },
            { "Defensive — protect us", "defensive" },
            { "Aggressive — clear threats", "aggressive" },
        }) do
            local option = stanceMenu:addOption(choice[1], SurvivorContextMenu,
                onCombatStance, playerNum, survivorId, choice[2])
            stanceMenu:setOptionChecked(option, stance == choice[2])
        end
        local weaponRoot = tacticsMenu:addOption("Weapon Preference", nil, nil)
        local weaponMenu = ISContextMenu:getNew(tacticsMenu)
        tacticsMenu:addSubMenu(weaponRoot, weaponMenu)
        local weaponPolicies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        for _, choice in ipairs({ { "Prefer Melee", "melee" }, { "Prefer Ranged", "ranged" },
            { "Survivor Choice", "auto" } }) do
            local option = weaponMenu:addOption(choice[1], SurvivorContextMenu,
                onWeaponPreference, playerNum, survivorId, choice[2])
            weaponMenu:setOptionChecked(option, (weaponPolicies.weaponPreference or "auto") == choice[2])
        end
        addAutoEquipmentMenu(tacticsMenu, playerNum, survivorId)
        local climbRoot = tacticsMenu:addOption("Vaulting and Climbing", nil, nil)
        local climbMenu = ISContextMenu:getNew(tacticsMenu)
        tacticsMenu:addSubMenu(climbRoot, climbMenu)
        local climbPolicies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        local climbing = climbPolicies.allowClimbing ~= false
        for _, choice in ipairs({ { "Allow Vaulting and Climbing", true },
            { "Disallow Vaulting and Climbing", false } }) do
            local option = climbMenu:addOption(choice[1], SurvivorContextMenu,
                onClimbing, playerNum, survivorId, choice[2])
            climbMenu:setOptionChecked(option, climbing == choice[2])
        end
        local doorsRoot = tacticsMenu:addOption("Doors and Windows", nil, nil)
        local doorsMenu = ISContextMenu:getNew(tacticsMenu)
        tacticsMenu:addSubMenu(doorsRoot, doorsMenu)
        local doorPolicies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        local doorOpening = doorPolicies.allowDoorOpening
        if doorOpening == nil and KnoxSettings ~= nil
            and KnoxSettings.allowSurvivorDoorWindowOpening ~= nil then
            doorOpening = KnoxSettings.allowSurvivorDoorWindowOpening() ~= false
        end
        for _, choice in ipairs({ { "Allow Opening Doors and Windows", true },
            { "Disallow Opening Doors and Windows", false } }) do
            local option = doorsMenu:addOption(choice[1], SurvivorContextMenu,
                onDoors, playerNum, survivorId, choice[2])
            doorsMenu:setOptionChecked(option, (doorOpening ~= false) == choice[2])
        end
        tacticsMenu:addOption("Unstick Survivor", SurvivorContextMenu,
            onUnstick, playerNum, survivorId)
        do
            local lootRoot = ordersMenu:addOption("Auto-Loot", nil, nil)
            local lootMenu = ISContextMenu:getNew(ordersMenu)
            ordersMenu:addSubMenu(lootRoot, lootMenu)
            local lootPolicies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
            local autoLoot = lootPolicies.autoLoot
            if autoLoot == nil then autoLoot = true end
            for _, choice in ipairs({ { "Auto-Loot While Following", true },
                { "Do Not Pick Up Items", false } }) do
                local option = lootMenu:addOption(choice[1], SurvivorContextMenu,
                    onAutoLoot, playerNum, survivorId, choice[2])
                lootMenu:setOptionChecked(option, (autoLoot ~= false) == choice[2])
            end
        end
        local needsRoot = ordersMenu:addOption("Survival Orders", nil, nil)
        local needsMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(needsRoot, needsMenu)
        needsMenu:addOption(KnoxOrderCatalog.label("find_food"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_food")
        needsMenu:addOption(KnoxOrderCatalog.label("find_water"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_water")
        needsMenu:addOption(KnoxOrderCatalog.label("find_medical"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_medical")
        needsMenu:addOption(KnoxOrderCatalog.label("find_weapon"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_weapon")
        needsMenu:addOption(KnoxOrderCatalog.label("find_tools"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_tools")
        needsMenu:addOption(KnoxOrderCatalog.label("find_wood"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_wood")
        needsMenu:addOption(KnoxOrderCatalog.label("find_materials"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_materials")
        needsMenu:addOption(KnoxOrderCatalog.label("find_clothing"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_clothing")
        needsMenu:addOption(KnoxOrderCatalog.label("find_ammo"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "find_ammo")
        needsMenu:addOption(KnoxOrderCatalog.label("clean_inventory"), SurvivorContextMenu, onNeedOrder,
            playerNum, survivorId, "clean_inventory")
        local base = KnoxBaseManager.getForOwner("player", playerId)
        if base ~= nil then
            ordersMenu:addOption(
                KnoxOrderCatalog.label("return_to_base"),
                SurvivorContextMenu,
                onReturnToBase,
                playerNum,
                survivorId
            )
        end
        end
    end
    if showCommands then
        menu:addOption(KnoxOrderCatalog.label("dismiss"), SurvivorContextMenu, onDismiss, playerNum, survivorId)
    end
    return true
end

function SurvivorContextMenu.open(playerNum, survivorId, x, y)
    local menu = ISContextMenu.get(playerNum, x, y)
    SurvivorContextMenu.populate(menu, playerNum, survivorId)
    return menu
end

local function nearestSurvivor(worldObjects)
    local bestId = nil
    local bestDistance = math.huge
    for _, object in ipairs(worldObjects or {}) do
        local square = object ~= nil and object:getSquare() or nil
        if square ~= nil then
            local id, distance = KnoxSurvivorRuntime.nearestToSquare(square, WORLD_PICK_RADIUS)
            if id ~= nil and distance ~= nil and distance < bestDistance then
                bestId = id
                bestDistance = distance
            end
        end
    end
    return bestId
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    if test and ISWorldObjectContextMenu.Test then
        return true
    end
    local survivorId = nearestSurvivor(worldObjects)
    if survivorId == nil then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end

    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and compat.usesNativeAdapter ~= nil and compat.usesNativeAdapter() then
        -- NPC harvesting supplies a square, not the aimed character. Supply
        -- discovery only here; the registered provider resolves the exact body.
        context:addOptionOnTop("Knox survivor interactions", SurvivorContextMenu,
            function(_, pn) return compat.openAimed(pn) end, playerNum)
        return
    end

    local snapshot = KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)
    local name = snapshot ~= nil and snapshot.displayName or "Survivor"
    local rootOption = context:addOptionOnTop(name, nil, nil)
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, subMenu)
    SurvivorContextMenu.populate(subMenu, playerNum, survivorId)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return SurvivorContextMenu
