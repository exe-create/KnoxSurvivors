-- Optional input/presentation adapter. Context builders and services still own
-- every command and permission. Never require or modify another mod.
local Layout = require "KS_SurvivorUILayout"
require "ISUI/ISContextMenu"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
local Compat = rawget(_G, "KnoxViewpointCompatibility") or {}
_G.KnoxViewpointCompatibility = Compat
local installed, selection = false, nil

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
function Compat.beginSelection(owner, label)
    if not Layout.isPerspective() then return false end
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
local function survivorActions(player, id)
    local menu = rawget(_G, "KnoxSurvivorContextMenu")
    if menu == nil then return {} end
    return harvest(player, function(context, pn) menu.populate(context, pn, id, "all") end)
end
local function invokeFresh(player, rows, label)
    for _, row in ipairs(rows) do
        if row.label == label and row.enabled ~= false then row.run(); return true end
    end
    feedback("That action is no longer available.")
    return false
end
local function collect(target, player, add)
    if not Compat.usesNativeAdapter() then return end
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
    local id = runtime ~= nil and runtime.idForCharacter ~= nil and runtime.idForCharacter(target.object) or nil
    if id ~= nil then
        for _, row in ipairs(survivorActions(player, id)) do
            local label, object = row.label, target.object
            add({ id = "knox.commands:" .. id .. ":" .. label,
                label = label == "Interact" and "Knox survivor interactions" or label,
                primary = label == "Interact", enabled = row.enabled,
                run = function(p)
                    if runtime.getCharacter(id) ~= object or not near(p, object:getCurrentSquare())
                        or not p:CanSee(object) then return false end
                    return invokeFresh(p, survivorActions(p, id), label)
                end })
        end
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
function Compat.install()
    local vp = ui()
    if installed then return true end
    if vp == nil or vp.Interactions == nil or vp.Hub == nil
        or vp.Util == nil or vp.Util.Harvest == nil then return false end
    vp.Interactions.register({ id = "knoxsurvivors.commands", priority = 20, collect = collect })
    vp.Hub.register({ id = "knoxsurvivors", label = "Knox Survivors", order = 95,
        visible = function() return enabled() end, create = createTab })
    installed = true
    return true
end
if Events ~= nil then
    Events.OnGameStart.Add(Compat.install)
    Events.OnTick.Add(function()
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
