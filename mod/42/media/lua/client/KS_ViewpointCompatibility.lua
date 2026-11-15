-- Optional input/presentation adapter. Context builders and services still own
-- every command and permission. Never require or modify another mod.
local Layout = require "KS_SurvivorUILayout"
require "ISUI/ISContextMenu"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "KS_OrderCatalog"
local Compat = rawget(_G, "KnoxViewpointCompatibility") or {}
_G.KnoxViewpointCompatibility = Compat
local installed, selection = false, nil
local interactionsRegistered, hubRegistered = false, false
-- Forward declaration. The registration below ran before the local function
-- that follows it, so it captured the *global* name and registered a nil
-- callback: Viewpoint then had no Knox actions to show at all.
local collect

local function ui() return rawget(_G, "ViewpointUI") end
local function enabled()
    local settings = rawget(_G, "KnoxSettings")
    return settings ~= nil and settings.enabled ~= nil and settings.enabled()
end
local function feedback(text)
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed ~= nil and feed.event ~= nil then feed.event(text) end
end
local function near(player, square)
    if player == nil or square == nil or player:isDead() then return false end
    local dx, dy = player:getX() - square:getX(), player:getY() - square:getY()
    if player:getZ() ~= square:getZ() or dx * dx + dy * dy > 16 then return false end
    return square.isCanSee ~= nil and square:isCanSee(player:getPlayerNum()) == true
end
local function currentTarget()
    local vp = ui()
    if vp ~= nil and vp.Interactions ~= nil and vp.Interactions.current ~= nil then
        return vp.Interactions.current()
    end
end
function Compat.ownsInteractionInput()
    return Compat.usesNativeAdapter()
end
function Compat.usesNativeAdapter()
    local vp = ui()
    if not installed or not enabled() or not Layout.isPerspective() or vp == nil
        or vp.isActive == nil or vp.isActive() ~= true then return false end
    if vp.Settings ~= nil then
        if vp.Settings.get ~= nil and vp.Settings.get("legacyFallback") == true then return false end
        if vp.Settings.interactStyle ~= nil and vp.Settings.interactStyle() == "vanilla" then return false end
    end
    return true
end
function Compat.openAimed(playerNum)
    local player = getSpecificPlayer(playerNum)
    local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
    if interaction == nil then return false end
    local target = interaction.nearest(player)
    if target == nil then feedback("That survivor is no longer available to talk."); return false end
    return interaction.open(playerNum, target, player)
end
function Compat.targetSquare(player)
    if not Compat.usesNativeAdapter() then return nil end
    local target = currentTarget()
    local square = target ~= nil and target.square or nil
    return near(player, square) and square or nil
end
-- Area, work-zone and territory selection place a tile under the cursor, so
-- they need the classic isometric view. Viewpoint's own setter is asked for by
-- name and existence-checked; if the installed build does not expose one, the
-- player is told to switch rather than handed a selector that cannot work.
function Compat.ensureIsoView()
    if not Layout.isPerspective() then return true end
    local vp = rawget(_G, "Viewpoint") or rawget(_G, "ViewpointUI") or rawget(_G, "VPUI")
    local setter = vp ~= nil and vp.View ~= nil and vp.View.set or nil
    if type(setter) == "function" then
        pcall(setter, "isometric")
        if not Layout.isPerspective() then return true end
    end
    feedback("Switch to the classic isometric view to select tiles for an area.")
    return false
end

function Compat.beginSelection(owner, label)
    if not Layout.isPerspective() then return false end
    if not Compat.ensureIsoView() then return false end
    if selection ~= nil and selection ~= owner then selection:onSquareSelectedCancel() end
    selection = owner
    owner.perspective = true
    local method = Compat.usesNativeAdapter() and "Interact" or "the world context menu's Select corner here action"
    feedback(label .. ": select the first tile, then the opposite corner with " .. method .. ". Cancel with Escape or your Viewpoint cancel key.")
    local vp = ui()
    if vp ~= nil and vp.Hub ~= nil then vp.Hub.close() end
    local book = rawget(_G, "KnoxSurvivorNotebook")
    if book ~= nil and book.window ~= nil then book.window:setVisible(false) end
    return true
end
function Compat.endSelection(owner)
    if selection == owner then selection = nil end
end
function Compat.hasSelection(player)
    return selection ~= nil and selection.player == player and not selection.pendingConfirm
end
function Compat.selectionAction(player, square)
    local owner = selection
    if owner == nil or owner.player ~= player or owner.pendingConfirm or not near(player, square) then return false end
    owner:onSquareSelected(square)
    return true
end

local function harvest(player, builder)
    local vp = ui()
    local helper = vp ~= nil and vp.Util ~= nil and vp.Util.Harvest or nil
    if helper == nil or helper.run == nil then return {} end
    local pn = player:getPlayerNum()
    local open = getPlayerContextMenu ~= nil and getPlayerContextMenu(pn) or nil
    if open ~= nil and open:getIsVisible() then return {} end -- Respect another open menu.
    return helper.run(pn, function()
        local menu = ISContextMenu.get(pn, 0, 0)
        return builder(menu, pn) or menu
    end)
end
local function visibleSurvivor(player, character)
    if player == nil or character == nil or player:isDead() or character:isDead() then return false end
    local square = character:getCurrentSquare()
    if square == nil or player:getZ() ~= character:getZ() then return false end
    local dx, dy = player:getX() - character:getX(), player:getY() - character:getY()
    if dx * dx + dy * dy > 16 then return false end
    if player.CanSee == nil then return true end
    local ok, seen = pcall(function() return player:CanSee(character) end)
    return not ok or seen == true
end
-- The aimed survivor, resolved without trusting one descriptor shape. Viewpoint
-- builds have handed over {object=...}, {character=...} and bare bodies, and a
-- build that hands over neither used to leave the crosshair with nothing of ours
-- on it while the vanilla player shell still offered its own broken row.
local function targetField(target, key)
    local ok, value = pcall(function() return target[key] end)
    return ok and value or nil
end
local function aimedCharacter(player, target)
    if target == nil then return nil end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil or runtime.idForCharacter == nil then return nil end
    -- Iterate field names: ipairs over sparse candidate values stops at the
    -- first missing object and never tries character/player or the bare body.
    for _, key in ipairs({ "object", "character", "player" }) do
        local candidate = targetField(target, key)
        if candidate ~= nil then
            local ok, id = pcall(runtime.idForCharacter, candidate)
            if ok and id ~= nil then return candidate, id end
        end
    end
    local ok, id = pcall(runtime.idForCharacter, target)
    if ok and id ~= nil then return target, id end
end

-- One rejection diagnostic per session, including direct aim/key attempts.
local function rejectedTarget(reason)
    if not Compat.reportedRejectedTarget then
        Compat.reportedRejectedTarget = true
        print("[KnoxSurvivors][Viewpoint] aim rejected: " .. reason)
    end
    return nil
end
function Compat.aimedTarget(player, descriptor)
    if player == nil then return nil end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local target = descriptor or currentTarget()
    local character, id = aimedCharacter(player, target)
    local square = target ~= nil and targetField(target, "square") or nil
    if id == nil and square ~= nil and runtime ~= nil
        and runtime.nearestToSquare ~= nil then
        local ok, found = pcall(runtime.nearestToSquare, square, 0.75)
        if ok then id = found end
    end
    if character == nil and id ~= nil and runtime ~= nil and runtime.getCharacter ~= nil then
        local ok, live = pcall(runtime.getCharacter, id)
        if ok then character = live end
    end
    if character == nil then return rejectedTarget("no survivor candidate") end
    if not visibleSurvivor(player, character) then return rejectedTarget("survivor not visible or in reach") end
    local view = rawget(_G, "KnoxSurvivorViewModel")
    local snapshot = view ~= nil and view.getSurvivor ~= nil
        and view.getSurvivor(id, player:getPlayerNum()) or nil
    return { id = id, character = character,
        name = snapshot ~= nil and snapshot.displayName or "Survivor" }
end

local function directSurvivorActions(player, id, character, add)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local function addAction(label, primary, run)
        add({ id = "knox.survivor:" .. id .. ":" .. label,
            label = label, primary = primary, run = function(p)
                if runtime == nil or runtime.getCharacter(id) ~= character
                    or not visibleSurvivor(p, character) then return false end
                return run(p)
            end })
    end
    local shelter=rawget(_G,"KnoxNightShelter")
    if shelter~=nil and shelter.pendingVisit(player,id)~=nil then
        for _,choice in ipairs({{key="IGUI_Knox_AllowOvernight",label="Allow overnight stay",accepted=true},
            {key="IGUI_Knox_RefuseOvernight",label="Refuse overnight stay",accepted=false}}) do
            local accepted=choice.accepted
            local label=KnoxOrderCatalog.text(choice.key,choice.label)
            addAction(label,false,function(p)
                return KnoxOrderCatalog.withFeedback(label,shelter.respond,p,id,accepted)
            end)
        end
    end
    addAction("Talk", true, function(p)
        local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
        if interaction == nil or interaction.open == nil then return false end
        local view = rawget(_G, "KnoxSurvivorViewModel")
        local snapshot = view ~= nil and view.getSurvivor ~= nil
            and view.getSurvivor(id, p:getPlayerNum()) or nil
        return interaction.open(p:getPlayerNum(), { id = id, character = character,
            name = snapshot ~= nil and snapshot.displayName or "Survivor" }, p)
    end)
    -- The aim list is the fast way to act on the person in front of you, so it
    -- carries the order desk as well as the conversation: one press opens the
    -- panel already on the order list, where follow/guard/scavenge live.
    addAction("Orders", false, function(p)
        local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
        if interaction == nil or interaction.open == nil then return false end
        local view = rawget(_G, "KnoxSurvivorViewModel")
        local snapshot = view ~= nil and view.getSurvivor ~= nil
            and view.getSurvivor(id, p:getPlayerNum()) or nil
        local opened = interaction.open(p:getPlayerNum(), { id = id, character = character,
            name = snapshot ~= nil and snapshot.displayName or "Survivor" }, p)
        return opened ~= nil and opened ~= false
    end)
    local persistence = rawget(_G, "KnoxPersistence")
    local affiliation = persistence ~= nil and persistence.getSurvivorAffiliation ~= nil
        and persistence.getSurvivorAffiliation(id) or nil
    if affiliation ~= nil and affiliation.kind ~= "player" then
        addAction("Trade", false, function(p)
            local trade = rawget(_G, "KnoxTradeUI")
            return trade ~= nil and trade.show ~= nil and trade.show(p:getPlayerNum(), id) ~= nil
        end)
        addAction("Give Item", false, function(p)
            local trade = rawget(_G, "KnoxTradeUI")
            return trade ~= nil and trade.showGift ~= nil and trade.showGift(p:getPlayerNum(), id) ~= nil
        end)
    elseif affiliation ~= nil and affiliation.kind == "player" then
        addAction("Manage Inventory", false, function(p)
            local inventory = rawget(_G, "KnoxCompanionInventory")
            -- request() reports the shared refusal sentence; show() alone would
            -- leave the crosshair action with only a generic failure.
            return inventory ~= nil and inventory.request ~= nil
                and inventory.request(p:getPlayerNum(), id) == true
        end)
    end
    addAction("Medical Check", false, function(p)
        local menu = rawget(_G, "KnoxSurvivorContextMenu")
        return menu ~= nil and menu.medicalCheck ~= nil and menu.medicalCheck(p:getPlayerNum(), id)
    end)
    addAction("View Stats & Skills", false, function(p)
        local card = rawget(_G, "KnoxSurvivorCard")
        return card ~= nil and card.show ~= nil and card.show(p:getPlayerNum(), id) ~= nil
    end)
end
local function invokeFresh(player, rows, label)
    for _, row in ipairs(rows) do
        if row.label == label and row.enabled ~= false then row.run(); return true end
    end
    feedback("That action is no longer available.")
    return false
end
collect = function(target, player, add)
    -- Viewpoint calls this with its own target descriptor. A build that hands
    -- us something unexpected must not break its crosshair list.
    if target == nil or player == nil or type(add) ~= "function" then return end
    if not Compat.usesNativeAdapter() then
        rejectedTarget("adapter gate (camera/settings/registration)")
        return
    end
    -- One line per session: which target Viewpoint handed us and whether it
    -- resolved to a survivor. Without it a silent crosshair cannot be told
    -- apart from an unaimed one between playtests.
    if not Compat.reportedFirstTarget then
        Compat.reportedFirstTarget = true
        print("[KnoxSurvivors][Viewpoint] first target kind=" .. tostring(target.kind)
            .. " object=" .. tostring(target.object ~= nil)
            .. " square=" .. tostring(target.square ~= nil)
            .. " resolved=" .. tostring(Compat.aimedTarget(player, target) ~= nil))
    end
    if selection ~= nil then
        if selection.player == player and not selection.pendingConfirm and near(player, target.square) then
            local square, owner = target.square, selection
            add({ id = "knox.select-corner", label = owner.firstSquare ~= nil and "Select opposite corner" or "Select first tile",
                primary = true, run = function(p)
                    if selection ~= owner then return false end
                    return Compat.selectionAction(p, square)
                end })
        end
        return
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local aimed = Compat.aimedTarget(player, target)
    local id = aimed ~= nil and aimed.id or nil
    if id ~= nil then
        -- Validate the body that was actually resolved, not the descriptor.
        -- Viewpoint often hands over { square = ... } with no body, which is
        -- exactly the case aimedTarget exists to solve. Checking target.object
        -- here meant that case resolved a survivor and then failed visibility,
        -- so the crosshair showed no Knox rows at all on a person.
        local body = aimed.character or target.object
        if not visibleSurvivor(player, body) then return end
        -- The crosshair carries the few things worth doing to a person. The
        -- order book belongs in the panel these open, not in the aim list.
        directSurvivorActions(player, id, aimed.character, add)
    elseif target.object == nil and near(player, target.square) then
        -- Viewpoint already harvests world-object callbacks. Ground targets have
        -- no object to harvest, so adapt only this missing case; no duplicate actions.
        local square = target.square
        local proxy = { getSquare = function() return square end }
        local baseMenu = rawget(_G, "KnoxBaseContextMenu")
        if baseMenu == nil then return end
        local function rows(p)
            return harvest(p, function(context, pn) baseMenu.onFill(pn, context, { proxy }, false) end)
        end
        for _, row in ipairs(rows(player)) do
            local label = row.label
            add({ id = "knox.base:" .. label, label = label, enabled = row.enabled,
                run = function(p)
                    if not near(p, square) then return false end
                    return invokeFresh(p, rows(p), label)
                end })
        end
    end
end

local function hubRows(player)
    local out = {}
    local party = rawget(_G, "KnoxPartyCommands")
    if party ~= nil then
        for _, row in ipairs(harvest(player, function(_, pn)
            return party.openMenu(pn, 0, 0, player:getCurrentSquare())
        end)) do
            row.label = "Party: " .. row.label
            out[#out + 1] = row
        end
    end
    return out
end
local function createTab(screen)
    local tab = { children = {}, screen = screen, nextRead = 0 }
    local function player() return screen:player() end
    local list = ISScrollingListBox:new(0, 0, 400, 300)
    list:initialise()
    list.itemheight = 24
    list.font = UIFont.Small
    list.doDrawItem = function(self, y, item)
        if self.selected == item.index then self:drawRect(0, y, self.width, self.itemheight, .3, .3, .5, .6) end
        local on = item.item.enabled ~= false
        self:drawText(item.text, 5, y + 3, on and .9 or .45, on and .9 or .45, on and .9 or .45, 1, self.font)
        return y + self.itemheight
    end
    local run = ISButton:new(0, 0, 180, 26, "Run selected order", tab, function(self)
        local item = list.items[list.selected or 0]
        local p = player()
        if item ~= nil and p ~= nil then invokeFresh(p, hubRows(p), item.text) end
    end)
    run:setEnable(false)
    local mouseDown = list.onMouseDown
    list.onMouseDown = function(self, ...)
        local result = mouseDown ~= nil and mouseDown(self, ...) or nil
        local selected = self.items[self.selected or 0]
        run:setEnable(selected ~= nil and selected.item.enabled ~= false)
        return result
    end
    local notebook = ISButton:new(0, 0, 320, 26, "Notebook, companions and base management", tab, function()
        local p = player()
        local book = rawget(_G, "KnoxSurvivorNotebook")
        if p ~= nil and book ~= nil then ui().Hub.close(); book.show(p:getPlayerNum()) end
    end)
    for _, child in ipairs({ list, run, notebook }) do
        if child ~= list then child:initialise() end
        screen:addChild(child)
        tab.children[#tab.children + 1] = child
    end
    function tab:layout(x, y, w, h)
        notebook:setX(x); notebook:setY(y); notebook:setWidth(w)
        list:setX(x); list:setY(y + 34); list:setWidth(w); list:setHeight(math.max(40, h - 72))
        run:setX(x); run:setY(y + h - 30); run:setWidth(w)
    end
    function tab:update(now)
        if now < self.nextRead then return end
        self.nextRead = now + 1000
        local selected = list.items[list.selected or 0]
        local label = selected ~= nil and selected.text or nil
        local scroll = list:getYScroll()
        list:clear()
        local p = player()
        if p ~= nil and not p:isDead() then
            for _, row in ipairs(hubRows(p)) do
                list:addItem(row.label, row)
                if row.label == label then list.selected = #list.items end
            end
        end
        list:setYScroll(scroll)
        selected = list.items[list.selected or 0]
        run:setEnable(selected ~= nil and selected.item.enabled ~= false)
    end
    return tab
end
-- Viewpoint is another mod with its own history. A build may expose
-- Interactions and Hub and no Util.Harvest at all, so registration must not
-- depend on the harvest helper: one missing convenience table used to remove
-- every Knox action from the crosshair while Viewpoint's own harvest still
-- showed the single vanilla option it could read. Each entry point is attempted
-- on its own, and a failure is reported once with the shape actually present.
function Compat.install()
    local vp = ui()
    if vp == nil then
        -- Silence here cost a playtest: the crosshair had no rows and nothing
        -- in the console said whether Viewpoint was absent or our provider
        -- was rejected. Say which, once.
        if not Compat.reportedMissingUI then
            Compat.reportedMissingUI = true
            print("[KnoxSurvivors][Viewpoint] ViewpointUI is not loaded; crosshair actions unavailable")
        end
        return false
    end
    if interactionsRegistered and hubRegistered then
        installed = true
        return true
    end
    if not interactionsRegistered and vp.Interactions ~= nil
        and vp.Interactions.register ~= nil then
        local ok = pcall(vp.Interactions.register, {
            id = "knoxsurvivors.commands",
            priority = 20,
            collect = function(target, player, add) return collect(target, player, add) end,
        })
        interactionsRegistered = ok == true
    end
    if not hubRegistered and vp.Hub ~= nil and vp.Hub.register ~= nil then
        local ok = pcall(vp.Hub.register, {
            id = "knoxsurvivors", label = "Knox Survivors", order = 95,
            visible = function() return enabled() end, create = createTab,
        })
        hubRegistered = ok == true
    end
    installed = interactionsRegistered
    if not installed and not Compat.reportedInstallFailure then
        Compat.reportedInstallFailure = true
        print("[KnoxSurvivors][Viewpoint] crosshair adapter not installed"
            .. " interactions=" .. tostring(vp.Interactions ~= nil)
            .. " register=" .. tostring(vp.Interactions ~= nil
                and vp.Interactions.register ~= nil)
            .. " hub=" .. tostring(vp.Hub ~= nil)
            .. " harvest=" .. tostring(vp.Util ~= nil and vp.Util.Harvest ~= nil))
    end
    return installed
end
if Events ~= nil then
    Events.OnGameStart.Add(Compat.install)
    Events.OnTick.Add(function()
        -- Idle fast path. This handler runs on every frame; with nothing
        -- selected there is nothing to cancel, and re-checking the install
        -- state is only worth doing while the adapter is still missing.
        if installed and selection == nil then return end
        if not installed then Compat.install() end
        if selection ~= nil and (selection.player:isDead() or not Layout.isPerspective()) then
            selection:onSquareSelectedCancel()
        end
    end)
    Events.OnKeyPressed.Add(function(key)
        if selection == nil or selection.pendingConfirm then return end
        local core = getCore()
        if (Keyboard ~= nil and key == Keyboard.KEY_ESCAPE) or core:isKey("VPUI_Cancel", key) then
            selection:onSquareSelectedCancel()
        end
    end)
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(function()
        if selection ~= nil then selection:onSquareSelectedCancel() end
    end) end
end
return Compat
