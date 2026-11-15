-- VIEWPOINT TARGET CARD
-- A compact card anchored to the crosshair, in the reference addon's spirit and
-- in our own material: who is under the crosshair, their role and condition in
-- words, and one honest hint. It is not a second action menu - the ordinary
-- interaction panel already owns every action and its refusal lines - so a
-- click opens that panel rather than inventing a parallel list.
--
-- Shown only while a camera mod reports the crosshair is the pointer, never in
-- the isometric view, and never while the interaction panel is already open.
require "KS_SurvivorUILayout"

local Crosshair = {}
_G.KnoxViewpointCrosshair = Crosshair

local CARD_WIDTH, CARD_HEIGHT = 236, 84
local OFFSET_X, OFFSET_Y = 26, 18

local View = ISUIElement:derive("KnoxViewpointTargetCard")

function View:createChildren() end

function View:aimed()
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat == nil or compat.aimedTarget == nil then return nil end
    local player = getSpecificPlayer(self.playerNum or 0)
    if player == nil then return nil end
    local ok, target = pcall(compat.aimedTarget, player)
    return ok and target or nil
end

function View:perspective()
    local layout = rawget(_G, "KnoxSurvivorUILayout")
    if layout == nil or layout.isPerspective == nil then return false end
    local ok, active = pcall(layout.isPerspective)
    return ok and active == true
end

function View:talkPanelOpen()
    local interaction = rawget(_G, "KnoxSurvivorInteractionUI")
    if interaction == nil or interaction.windowFor == nil then return false end
    local ok, window = pcall(interaction.windowFor, self.playerNum or 0)
    return ok and window ~= nil
end

function View:prerender()
    local target = self:aimed()
    -- A camera session owns the pointer; the panel owns the survivor. Hide for
    -- both so the card never competes with the surface that can act.
    if target == nil or not self:perspective() or self:talkPanelOpen() then
        if self:isVisible() then self:setVisible(false) end
        return
    end
    if not self:isVisible() then self:setVisible(true) end
    local core = getCore()
    local mouseX = core ~= nil and core:getMouseX() or 0
    local mouseY = core ~= nil and core:getMouseY() or 0
    self:setX(math.min(mouseX + OFFSET_X, (core ~= nil and core:getScreenWidth() or 1280) - CARD_WIDTH - 8))
    self:setY(math.min(mouseY + OFFSET_Y, (core ~= nil and core:getScreenHeight() or 720) - CARD_HEIGHT - 8))

    local layout = rawget(_G, "KnoxSurvivorUILayout")
    local sheet = layout ~= nil and layout.sheet or nil
    if sheet == nil then return end
    self:drawRect(0, 0, CARD_WIDTH, CARD_HEIGHT, 0.94, sheet.charcoal[1], sheet.charcoal[2], sheet.charcoal[3])
    self:drawRectBorder(0, 0, CARD_WIDTH, CARD_HEIGHT, 0.95, sheet.border[1], sheet.border[2], sheet.border[3])
    self:drawRect(0, 0, 3, CARD_HEIGHT, 1, sheet.accent[1], sheet.accent[2], sheet.accent[3])

    local name = tostring(target.name or "Survivor")
    local model = rawget(_G, "KnoxSurvivorViewModel")
    local snapshot = model ~= nil and model.getSurvivor ~= nil
        and model.getSurvivor(target.id, self.playerNum or 0) or nil
    if snapshot ~= nil and snapshot.displayName ~= nil then name = tostring(snapshot.displayName) end
    self:drawText(name, 12, 8, sheet.bone[1], sheet.bone[2], sheet.bone[3], 1, UIFont.Medium)
    local role = snapshot ~= nil and tostring(snapshot.role or snapshot.job or "") or ""
    if role ~= "" then
        self:drawText(role, 12, 30, sheet.muted[1], sheet.muted[2], sheet.muted[3], 1, UIFont.Small)
    end
    local condition = snapshot ~= nil and tostring(snapshot.condition or "") or ""
    if condition ~= "" then
        self:drawText(condition, 12, 48, sheet.dim[1], sheet.dim[2], sheet.dim[3], 1, UIFont.Small)
    end
    self:drawText("Click to talk", 12, CARD_HEIGHT - 20,
        sheet.accent[1], sheet.accent[2], sheet.accent[3], 1, UIFont.Small)
end

-- The card is an overlay, not a barrier: a click on it opens the panel, and any
-- other click is passed through so the world keeps its input.
function View:onMouseDown(x, y)
    if x < 0 or y < 0 or x > CARD_WIDTH or y > CARD_HEIGHT then return false end
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat == nil or compat.openAimed == nil then return false end
    pcall(compat.openAimed, self.playerNum or 0)
    return false
end

function View:onMouseUp() return false end
function View:onMouseDownOutside() return false end

local function ensureCard()
    if Crosshair.card ~= nil then return Crosshair.card end
    local card = View:new(0, 0, CARD_WIDTH, CARD_HEIGHT)
    card.playerNum = 0
    card:setWantKeyEvents(false)
    card:setVisible(false)
    card:initialise()
    card:addToUIManager()
    Crosshair.card = card
    return card
end

if Events ~= nil and Events.OnGameStart ~= nil and not Crosshair.installed then
    Crosshair.installed = true
    Events.OnGameStart.Add(function()
        local ok = pcall(ensureCard)
        if not ok then Crosshair.card = nil end
    end)
end

return Crosshair
