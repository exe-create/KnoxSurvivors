-- Layout adapters only: character data and actions remain owned by vanilla UI.
local Layout = {}

-- Shared presentation tokens for the ambient HUD layer. These are colours,
-- spacing and motion only; no gameplay state or decision belongs here. The
-- palette is the accepted visual system in docs/production/design/UI.md.
Layout.theme = {
    charcoal = { 0.090, 0.086, 0.078 },
    bone = { 0.902, 0.878, 0.831 },
    muted = { 0.639, 0.612, 0.561 },
    border = { 0.290, 0.275, 0.247 },
    amber = { 0.851, 0.643, 0.255 },
    red = { 0.769, 0.333, 0.247 },
    green = { 0.431, 0.561, 0.353 },
    blue = { 0.357, 0.498, 0.651 },
    -- Two neutral text tiers between bone and muted: a label is quieter than a
    -- value, and a dim line quieter still. They live here so secondary text has
    -- one tone instead of a grey per window.
    label = { 0.600, 0.576, 0.529 },
    dim = { 0.500, 0.480, 0.443 },
    motion = 120,
}

function Layout.colour(token)
    return Layout.theme[token] or Layout.theme.bone
end

-- TEXT WRAP (pure)
-- One measured word wrap for every paragraph a Knox window draws. ISLabel draws
-- a single line and never wraps: giving it a width only changes its hit box, so
-- a long sentence ran off the sheet. A text that already fits costs one
-- measurement; deliberate breaks and runs of spaces always take the slow path so
-- their shape is kept.
function Layout.wrapLines(text, maxWidth, measure)
    local lines = {}
    if type(text) ~= "string" or text == "" then
        return lines
    end
    local limit = tonumber(maxWidth) or 0
    local measureX = type(measure) == "function" and measure
        or function(value) return #value end
    if limit <= 0 then
        return { text }
    end
    if measureX(text) <= limit
        and string.find(text, "  ", 1, true) == nil
        and string.find(text, "\n", 1, true) == nil then
        return { text }
    end
    local paragraph = {}
    local function breakLine()
        if #paragraph > 0 then
            lines[#lines + 1] = table.concat(paragraph, " ")
            paragraph = {}
        end
    end
    local word = nil
    for index = 1, #text + 1 do
        local char = string.sub(text, index, index)
        if char == " " or char == "\n" or char == "" then
            if word ~= nil then
                if #paragraph == 0 then
                    paragraph[1] = word
                else
                    local candidate = table.concat(paragraph, " ") .. " " .. word
                    if measureX(candidate) > limit then
                        breakLine()
                        paragraph[1] = word
                    else
                        paragraph[#paragraph + 1] = word
                    end
                end
                word = nil
            end
            if char == "\n" then breakLine() end
        else
            word = (word or "") .. char
        end
    end
    breakLine()
    return lines
end
-- END TEXT WRAP

-- TEXT FIT (pure)
-- One rule for "make this single line fit a measured slot". Five surfaces had
-- each written their own copy of this loop; a copy that drifts draws past its
-- edge, and the drift is invisible until a long name lands in a narrow slot.
-- The measure is injectable for the same reason as wrapLines: the arithmetic is
-- provable without a font atlas.
function Layout.fitText(font, text, maxWidth, measure)
    local value = tostring(text or "")
    local limit = tonumber(maxWidth)
    if limit == nil or limit <= 0 then return value end
    local measureX = type(measure) == "function" and measure
        or function(candidate) return getTextManager():MeasureStringX(font, candidate) end
    if measureX(value) <= limit then return value end
    local suffix = "..."
    while #value > 0 and measureX(value .. suffix) > limit do
        value = string.sub(value, 1, #value - 1)
    end
    return value .. suffix
end
-- END TEXT FIT

-- The windows the player opens on purpose share the HUD's material: one
-- charcoal sheet over the world, one hairline border. Presentation only; a
-- window does not get a second palette of its own.
function Layout.tintWindow(window)
    if window == nil then return window end
    local charcoal, border = Layout.theme.charcoal, Layout.theme.border
    window.backgroundColor = { r = charcoal[1], g = charcoal[2], b = charcoal[3], a = 0.94 }
    window.borderColor = { r = border[1], g = border[2], b = border[3], a = 0.90 }
    return window
end

-- The amber accent is retired (owner report, 2026-11-03): on this palette it
-- read as a yellow highlight around a button rather than as emphasis, so a
-- primary control now wears the same hairline as every other button.
-- Presentation only: the callback, label and enable state stay the button's
-- own and are never touched here.
function Layout.tintPrimary(button)
    if button == nil then return button end
    local theme = Layout.theme
    local hairline = theme.border
    button.borderColor = { r = hairline[1], g = hairline[2], b = hairline[3], a = 0.95 }
    button.backgroundColor = { r = theme.charcoal[1], g = theme.charcoal[2],
        b = theme.charcoal[3], a = 0.92 }
    return button
end

-- The quiet half of the button material: charcoal fill, hairline border, no
-- accent. Every Knox window uses this so a control is never lighter than the
-- sheet it sits on. tintPrimary now resolves to this same material.
function Layout.tintButton(button)
    if button == nil then return button end
    local theme = Layout.theme
    button.borderColor = { r = theme.border[1], g = theme.border[2],
        b = theme.border[3], a = 0.80 }
    button.backgroundColor = { r = theme.charcoal[1], g = theme.charcoal[2],
        b = theme.charcoal[3], a = 0.92 }
    return button
end

function Layout.fitView(view)
    local parent = view.parent
    if parent == nil then return end
    local width = math.max(1, parent.width)
    local height = math.max(1, parent.height - (parent.tabHeight or 0))
    view:setWidth(width)
    view:setHeight(height)
    -- Never shrink a scroll extent a vanilla view computed for itself
    -- (skills content height): refits converge instead of fighting it.
    local currentH, currentW = 0, 0
    pcall(function() currentH = view:getScrollHeight() or 0 end)
    pcall(function() currentW = view:getScrollWidth() or 0 end)
    view:setScrollWidth(math.max(width, view.knoxContentWidth or width, currentW))
    view:setScrollHeight(math.max(height, view.knoxContentHeight or height, currentH))
end

function Layout.bindView(view)
    view.setWidthAndParentWidth = function(self, width)
        self.knoxContentWidth = width
        Layout.fitView(self)
    end
    view.setHeightAndParentHeight = function(self, height)
        self.knoxContentHeight = height
        Layout.fitView(self)
    end
    view:setScrollChildren(true)
    -- Vertical only. A horizontal bar object shrinks the vanilla scroll
    -- area on mere presence (getScrollAreaHeight subtracts it), stealing
    -- 17px from every tab and forcing spurious vertical scrollbars.
    view:addScrollBars()
    view:setScrollWithParent(false)
    local prerender, render = view.prerender, view.render
    view.prerender = function(self)
        -- Do not reset native Skills' full scroll extent every frame.
        if self.parent and (self.width ~= self.parent.width
            or self.height ~= math.max(1, self.parent.height - (self.parent.tabHeight or 0))) then
            Layout.fitView(self)
        end
        prerender(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    view.render = function(self)
        render(self)
        self:clearStencilRect()
    end
    if view.onMouseWheel == nil then
        view.onMouseWheel = function(self, delta)
            self:setYScroll(self:getYScroll() - delta * 30)
            return true
        end
    end
    Layout.fitView(view)
end

-- Base & Work embeds native scrolling lists inside a page scroller. Native UI
-- dispatch already gives the hovered list its wheel event. If that event then
-- bubbles to the page, consume it here; forwarding it to the list again causes
-- a second scroll step and makes adjacent sections appear to move together.
-- Bring one existing child of a scrollable page into view. This moves the
-- page scroll only; it never moves a control or changes its layout.
function Layout.reveal(view, control, margin)
    if view == nil or control == nil or view.setYScroll == nil
        or view.getYScroll == nil or control.getY == nil then return false end
    local viewHeight = view.getHeight ~= nil and tonumber(view:getHeight())
        or tonumber(view.height) or 0
    local top = tonumber(control:getY()) or 0
    local height = control.getHeight ~= nil and tonumber(control:getHeight()) or 0
    local scroll = tonumber(view:getYScroll()) or 0
    local visibleTop = -scroll
    local pad = math.max(0, tonumber(margin) or 12)
    local target = scroll
    if top < visibleTop + pad then
        target = -(top - pad)
    elseif top + height > visibleTop + viewHeight - pad then
        target = -(top + height - viewHeight + pad)
    end
    local extent = view.getScrollHeight ~= nil
        and tonumber(view:getScrollHeight()) or viewHeight
    local minimum = math.min(0, viewHeight - math.max(viewHeight, extent or viewHeight))
    target = math.max(minimum, math.min(0, target))
    if target ~= scroll then view:setYScroll(target); return true end
    return false
end

function Layout.routeWheelToChildren(view, delta, children)
    local mouseX = type(getMouseX) == "function" and getMouseX() or nil
    local mouseY = type(getMouseY) == "function" and getMouseY() or nil
    if mouseX ~= nil and mouseY ~= nil then
        for _, child in ipairs(children or {}) do
            if child ~= nil and child.onMouseWheel ~= nil
                and child.getAbsoluteX ~= nil and child.getAbsoluteY ~= nil then
                local x = mouseX - child:getAbsoluteX()
                local y = mouseY - child:getAbsoluteY()
                if x >= 0 and y >= 0 and x < child:getWidth()
                    and y < child:getHeight() then
                    -- The child owns its native wheel event. The page only
                    -- suppresses the bubbled copy; never invoke it twice.
                    return true, child
                end
            end
        end
    end
    if view ~= nil and view.setYScroll ~= nil and view.getYScroll ~= nil then
        view:setYScroll(view:getYScroll() - delta * 30)
        return true, nil
    end
    return false, nil
end

-- ISScrollingListBox's default doDrawItem skips rows outside its viewport.
-- Custom Knox row callbacks replace that method, so they must preserve the
-- same visibility check while still returning the row's full next-Y value.
function Layout.listRowVisible(list, y, item)
    if list == nil or item == nil then return false end
    local height = tonumber(list.itemheight) or tonumber(item.height) or 0
    local scroll = list.getYScroll ~= nil and (list:getYScroll() or 0) or 0
    local rowY = y + scroll
    return not (rowY + height < 0 or rowY >= (tonumber(list.height) or 0))
end

-- Wrap the footer using measured labels; reserve its full height below the list.
function Layout.residentFooter(view, spacing, buttonHeight)
    local controls = {view.viewBtn, view.joinPartyBtn, view.sendHomeBtn, view.jobPicker, view.setJobBtn}
    local available = math.max(1, view.width - spacing * 2)
    local x, row = 0, 0
    local placements = {}
    for _, control in ipairs(controls) do
        local label = control.title or "Automatic"
        local width = math.min(available, math.max(control.knoxPreferredWidth or control.width,
            getTextManager():MeasureStringX(UIFont.Small, label) + 24))
        control.knoxPreferredWidth = control.knoxPreferredWidth or control.width
        if x > 0 and x + width > available then x, row = 0, row + 1 end
        placements[#placements + 1] = {control = control, x = x, row = row, width = width}
        x = x + width + spacing
    end
    local footerHeight = (row + 1) * buttonHeight + row * spacing
    local top = math.max(spacing * 2 + buttonHeight, view.height - spacing - footerHeight)
    view.list:setWidth(available)
    view.list:setHeight(math.max(1, top - spacing * 2))
    for _, placement in ipairs(placements) do
        local control = placement.control
        control:setX(spacing + placement.x)
        control:setY(top + placement.row * (buttonHeight + spacing))
        control:setWidth(placement.width)
        control:setHeight(buttonHeight)
    end
    view:setScrollHeight(top + footerHeight + spacing)
end

-- Read-only camera state shared by input and placement adapters. View.next is
-- the installed Viewpoint API's next-mode query, not a camera-mode setter.
--
-- Two globals are asked because the mod publishes ViewpointUI (API.lua) and
-- older builds answered to Viewpoint. Only the second was asked here, so this
-- returned false in every perspective session: the crosshair adapter switched
-- itself off, and the F hint promised a key that stands aside. isActive() is
-- the camera signal the public API actually guarantees.
function Layout.isPerspective()
    -- The camera takes the cursor off the world pointer; its companion mod
    -- publishes the very state it uses to lock the mouse. That is the only
    -- signal here that means "the crosshair is the pointer". ViewpointUI's own
    -- isActive() means the mod is loaded, which is also true in the isometric
    -- view, so it cannot answer this question.
    local qol = rawget(_G, "ViewpointQOL")
    if type(qol) == "table" and type(qol.isCursorMode) == "function" then
        local ok, free = pcall(qol.isCursorMode)
        if ok and type(free) == "boolean" then return free ~= true end
    end
    local vp = rawget(_G, "Viewpoint")
    if vp ~= nil and vp.View ~= nil and vp.View.next ~= nil then
        local ok, mode = pcall(vp.View.next)
        if ok then return mode == "third" or mode == "isometric" end
    end
    return false
end

function Layout.bindInteractionWindow(window)
    if window.knoxCaptureBound then return end
    window.knoxCaptureBound = true
    local update, close, keyRelease = window.update, window.close, window.onKeyRelease
    local consume = window.isKeyConsumed
    local function ownsKeys(self)
        if not self.knoxOwnsCapture or not self:isVisible() then return false end
        if UIManager == nil or UIManager.getUI == nil or self.javaObject == nil then return true end
        local ok, owner = pcall(function()
            local list = UIManager.getUI()
            for index = list:size() - 1, 0, -1 do
                local element = list:get(index)
                if element:isVisible() and (element:isCapture() or element:isWantKeyEvents()) then
                    return element == self.javaObject
                end
            end
            return false
        end)
        return ok and owner == true
    end
    window.update = function(self, ...)
        if update ~= nil then update(self, ...) end
        if self.setCapture == nil then return end
        if self:isVisible() and self.playerNum ~= nil and getSpecificPlayer ~= nil then
            local player = getSpecificPlayer(self.playerNum)
            if player == nil or (player.isDead ~= nil and player:isDead()) then self:close(); return end
        end
        local capture = Layout.isPerspective() and self:isVisible()
        -- Use the actual native capture state: dragging may have released it.
        local actual = self.javaObject ~= nil and self.javaObject.isCapture ~= nil
            and self.javaObject:isCapture() or false
        if capture ~= actual and (capture or self.knoxOwnsCapture) then self:setCapture(capture) end
        if capture and not self.knoxOwnsCapture then
            self.knoxPriorWantKeys = self.javaObject ~= nil and self.javaObject.isWantKeyEvents ~= nil
                and self.javaObject:isWantKeyEvents() or false
            if self.setWantKeyEvents ~= nil then self:setWantKeyEvents(true) end
        elseif not capture and self.knoxOwnsCapture and self.setWantKeyEvents ~= nil then
            self:setWantKeyEvents(self.knoxPriorWantKeys == true)
        end
        self.knoxOwnsCapture = capture
    end
    window.close = function(self, ...)
        if self.knoxOwnsCapture and self.setCapture ~= nil then self:setCapture(false) end
        if self.knoxOwnsCapture and self.setWantKeyEvents ~= nil then self:setWantKeyEvents(self.knoxPriorWantKeys == true) end
        self.knoxOwnsCapture = false
        if close ~= nil then return close(self, ...) end
        self:setVisible(false)
    end
    window.isKeyConsumed = function(self, key)
        if ownsKeys(self) then return true end
        return consume ~= nil and consume(self, key) or false
    end
    window.onKeyRelease = function(self, key)
        if ownsKeys(self) and Keyboard ~= nil and key == Keyboard.KEY_ESCAPE then
            self:close()
        elseif keyRelease ~= nil then keyRelease(self, key) end
    end
end

-- Person-bound surfaces (talk, trade, pack, card) exist because the player is
-- dealing with one survivor. They share one close rule: the surface lives only
-- while that person is still a valid interlocutor. This predicate is read-only;
-- it never changes trust, orders or attention ownership. The talk panel keeps
-- its richer attention handshake and uses the same reason vocabulary.
local PERSON_SURFACE_DISTANCE_SQUARED = 25 -- five tiles, the design's close bound
local PERSON_SURFACE_SIGHT_GRACE_MS = 1500
local PERSON_SURFACE_CHECK_MS = 250

local function surfaceNow(context)
    local now = tonumber(context ~= nil and context.now) or nil
    if now ~= nil then return now end
    if getTimestampMs == nil then return nil end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or nil
end

local function surfacePoint(entity)
    if entity == nil then return nil end
    local square = nil
    pcall(function() square = entity:getCurrentSquare() end)
    local x, y, z
    if square ~= nil then
        pcall(function() x, y, z = square:getX(), square:getY(), square:getZ() end)
    end
    if x == nil then
        pcall(function() x, y, z = entity:getX(), entity:getY(), entity:getZ() end)
    end
    return x, y, z
end

local function surfaceHostile(player, survivorId)
    local service = rawget(_G, "KnoxCompanionService")
    local persistence = rawget(_G, "KnoxPersistence")
    local check = service ~= nil and service.isSociallyHostileToPlayer or nil
    local playerId = nil
    if service ~= nil and service.getPlayerId ~= nil then
        local ok, id = pcall(service.getPlayerId, player)
        if ok then playerId = id end
    end
    if check == nil and persistence ~= nil then
        check = persistence.isSurvivorHostileToPlayer
    end
    if check == nil or playerId == nil then return false end
    local ok, hostile = pcall(check, survivorId, playerId)
    return ok and hostile == true
end

-- The close rule. `context` may carry the body the surface was opened on, the
-- controller and conversation lease that own it, and the surface's own bounds.
-- Returns true, or false plus one reason: player_gone, player_in_vehicle,
-- player_aiming, survivor_gone, attention_lost, hostile, too_far, lost_sight.
function Layout.personSurfaceState(player, survivorId, context)
    context = type(context) == "table" and context or {}
    if player == nil then return false, "player_gone" end
    local dead, vehicle, aiming = false, nil, false
    pcall(function()
        dead = player:isDead() == true
        vehicle = player:getVehicle()
        aiming = player:isAiming() == true
    end)
    if dead then return false, "player_gone" end
    if vehicle ~= nil then return false, "player_in_vehicle" end
    if aiming then return false, "player_aiming" end
    if type(survivorId) ~= "string" or survivorId == "" then
        return false, "survivor_gone"
    end

    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local live = nil
    if runtime ~= nil and runtime.getCharacter ~= nil then
        local ok, character = pcall(runtime.getCharacter, survivorId)
        live = ok and character or nil
    end
    if context.body ~= nil and (live == nil or live ~= context.body) then
        return false, "survivor_gone"
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.isSurvivorAlive ~= nil then
        local ok, alive = pcall(persistence.isSurvivorAlive, survivorId)
        if ok and alive == false then return false, "survivor_gone" end
    end
    -- A world-bound read (the card for an offscreen resident) has nothing else
    -- it can honestly observe; the person is not loaded to close on.
    if live == nil then return true, nil end
    local bodyDead = false
    pcall(function() bodyDead = live:isDead() == true end)
    if bodyDead then return false, "survivor_gone" end

    if context.controller ~= nil or context.lease ~= nil then
        local controller = nil
        if runtime ~= nil and runtime.getController ~= nil then
            local ok, current = pcall(runtime.getController, survivorId)
            controller = ok and current or nil
        end
        if controller == nil
            or (context.controller ~= nil and controller ~= context.controller)
            or (context.lease ~= nil and controller.playerConversation ~= context.lease) then
            return false, "attention_lost"
        end
    end
    if surfaceHostile(player, survivorId) then return false, "hostile" end

    if context.checkDistance ~= false then
        local px, py, pz = surfacePoint(player)
        local sx, sy, sz = surfacePoint(live)
        local maximum = tonumber(context.maximumDistanceSquared)
            or PERSON_SURFACE_DISTANCE_SQUARED
        if px == nil or py == nil or sx == nil or sy == nil
            or (pz ~= nil and sz ~= nil and pz ~= sz)
            or ((px - sx) * (px - sx) + (py - sy) * (py - sy)) > maximum then
            return false, "too_far"
        end
    end

    local visible = true
    if context.requireSight ~= false then
        local hasSight = false
        pcall(function() hasSight = player.CanSee ~= nil end)
        if hasSight then
            local ok, seen = pcall(function() return player:CanSee(live) end)
            visible = not ok or seen == true
        end
    end
    local state = context.state
    local now = surfaceNow(context)
    if not visible then
        if state ~= nil and now ~= nil then
            state.knoxPersonLostSightAt = state.knoxPersonLostSightAt or now
            local grace = tonumber(context.sightGraceMs) or PERSON_SURFACE_SIGHT_GRACE_MS
            if now - state.knoxPersonLostSightAt < grace then return true, nil end
        end
        return false, "lost_sight"
    end
    if state ~= nil then state.knoxPersonLostSightAt = nil end
    return true, nil
end

-- Only a change the world cannot show earns a sentence when a surface closes.
-- Death, distance, aiming and lost sight are visible at the crosshair; a
-- relationship turning on the player is not.
function Layout.personSurfaceCloseText(reason)
    if reason == "hostile" then return "They've turned on you." end
    return nil
end

function Layout.noticePersonSurfaceClose(reason)
    local text = Layout.personSurfaceCloseText(reason)
    if text == nil then return false end
    local feed = rawget(_G, "KnoxActivityFeed")
    if feed == nil or feed.event == nil then return false end
    local ok = pcall(feed.event, text)
    return ok
end

-- Wrap a person-bound window with the close rule. The window supplies
-- `playerNum`, `survivorId` and, when it was opened on a body, `knoxPersonBody`;
-- options carry `onClose(window, reason)` and the surface's own bounds. The
-- wrapper polls at most four times a second and closes through the window's own
-- close unless the adopter supplied a callback.
function Layout.bindPersonSurface(window, options)
    if window == nil then return window end
    window.knoxPersonSurface = type(options) == "table" and options or {}
    Layout.bindInteractionWindow(window)
    if window.knoxPersonBound then return window end
    window.knoxPersonBound = true
    local update = window.update
    local nextCheckAt = 0
    window.update = function(self, ...)
        if update ~= nil then update(self, ...) end
        if not self:isVisible() or type(self.survivorId) ~= "string" then return end
        local config = self.knoxPersonSurface or {}
        local now = surfaceNow(config)
        local interval = tonumber(config.checkIntervalMs) or PERSON_SURFACE_CHECK_MS
        if now ~= nil and nextCheckAt > 0 and now < nextCheckAt then return end
        if now ~= nil then nextCheckAt = now + interval end
        local player = nil
        if getSpecificPlayer ~= nil then player = getSpecificPlayer(self.playerNum) end
        local ok, reason = Layout.personSurfaceState(player, self.survivorId, {
            body = self.knoxPersonBody,
            controller = self.attentionController,
            lease = self.attentionLease,
            state = self,
            now = now,
            maximumDistanceSquared = config.maximumDistanceSquared,
            checkDistance = config.checkDistance,
            requireSight = config.requireSight,
            sightGraceMs = config.sightGraceMs,
        })
        if ok then return end
        self.knoxPersonCloseReason = reason
        if config.notice ~= false then Layout.noticePersonSurfaceClose(reason) end
        if type(config.onClose) == "function" then
            config.onClose(self, reason)
        else
            self:close()
        end
    end
    return window
end


-- ONE KNOX SURFACE (pure)
-- A player reads one Knox window at a time. The registry lives here because
-- this module already owns window tracking and the person-surface close rule;
-- it is one rule with one table, not a second window system. The caller's API
-- supplies `close(playerNum)`; a surface that throws on close still yields.
Layout.surfaces = {}
function Layout.claimSurface(playerNum, kind, api)
    playerNum = tonumber(playerNum) or 0
    kind = tostring(kind or "")
    local previous = Layout.surfaces[playerNum]
    if previous ~= nil and previous.kind ~= kind and previous.api ~= nil
        and type(previous.api.close) == "function" then
        pcall(previous.api.close, playerNum)
    end
    Layout.surfaces[playerNum] = { kind = kind, api = api }
    return previous
end

function Layout.releaseSurface(playerNum, kind)
    playerNum = tonumber(playerNum) or 0
    local current = Layout.surfaces[playerNum]
    if current == nil then return false end
    if kind ~= nil and current.kind ~= tostring(kind) then return false end
    Layout.surfaces[playerNum] = nil
    return true
end
-- END ONE KNOX SURFACE

-- UI SCALE (one rule for every Knox window)
-- The game already scales its interface font, so the font height is the honest
-- source of the player's scale setting. It is then capped by the smallest
-- screen dimension, because a 1920x1080 design opened on a 1280x720 display is
-- the one case a font-derived factor alone gets wrong.
Layout.BASE_FONT_HEIGHT = 14
Layout.DESIGN_HEIGHT = 720
Layout.MIN_SCALE = 0.80
Layout.MAX_SCALE = 2.00

function Layout.screenSize()
    local width = type(getScreenWidth) == "function" and getScreenWidth() or nil
    local height = type(getScreenHeight) == "function" and getScreenHeight() or nil
    return tonumber(width), tonumber(height)
end

-- The interface font is the player's own scale setting. Read it once, nil-safe.
function Layout.fontHeight()
    if getTextManager == nil then return nil end
    local ok, height = pcall(function()
        return getTextManager():getFontHeight(UIFont.Small)
    end)
    local value = ok and tonumber(height) or nil
    if value == nil or value <= 0 then return nil end
    return value
end

function Layout.fontScale()
    local height = Layout.fontHeight()
    if height == nil then return 1 end
    return height / Layout.BASE_FONT_HEIGHT
end

-- The rule itself, with its inputs explicit: the font-derived scale capped by
-- the smaller screen dimension. Pure on purpose — the fixture drives it with
-- numbers instead of a running game, so a change to the rule is provable.
function Layout.scaleFor(fontHeight, width, height)
    local scale = 1
    local font = tonumber(fontHeight)
    if font ~= nil and font > 0 then
        scale = font / Layout.BASE_FONT_HEIGHT
    end
    local w, h = tonumber(width), tonumber(height)
    if w ~= nil and h ~= nil and w > 0 and h > 0 then
        -- Both dimensions matter: a wide but short display clips height, a
        -- narrow one clips width. Take the strictest, never below the floor.
        scale = math.min(scale,
            math.max(Layout.MIN_SCALE, h / Layout.DESIGN_HEIGHT),
            math.max(Layout.MIN_SCALE, w / 1600))
    end
    return math.max(Layout.MIN_SCALE, math.min(Layout.MAX_SCALE, scale))
end

function Layout.uiScale()
    local width, height = Layout.screenSize()
    return Layout.scaleFor(Layout.fontHeight(), width, height)
end

-- Where a window of this size at this position would sit on that screen. Pure:
-- the caller keeps its own geometry, this only caps and slides it inside.
function Layout.fitRect(width, height, x, y, screenW, screenH, margin)
    local pad = math.max(0, tonumber(margin) or 8)
    local w = math.max(1, tonumber(width) or 1)
    local h = math.max(1, tonumber(height) or 1)
    local sw, sh = tonumber(screenW), tonumber(screenH)
    local px, py = tonumber(x) or 0, tonumber(y) or 0
    if sw == nil or sh == nil or sw <= 0 or sh <= 0 then
        return w, h, px, py
    end
    w = math.min(w, math.max(1, sw - pad * 2))
    h = math.min(h, math.max(1, sh - pad * 2))
    px = math.max(pad, math.min(px, sw - w - pad))
    py = math.max(pad, math.min(py, sh - h - pad))
    return w, h, px, py
end

function Layout.scaled(value)
    return math.floor((tonumber(value) or 0) * Layout.uiScale())
end

-- Keep a window fully on screen. Never enlarges: the caller owns its design
-- size, this only caps it and slides it back inside the margin.
function Layout.clampWindow(window, margin)
    if window == nil then return window end
    local pad = math.max(0, tonumber(margin) or 8)
    local screenW, screenH = Layout.screenSize()
    if screenW == nil or screenH == nil or screenW <= 0 or screenH <= 0 then
        return window
    end
    local width = tonumber(window.width) or 0
    local height = tonumber(window.height) or 0
    local x = tonumber(window:getX()) or 0
    local y = tonumber(window:getY()) or 0
    local fitW, fitH, fitX, fitY = Layout.fitRect(width, height, x, y,
        screenW, screenH, pad)
    if fitW ~= width then window:setWidth(fitW) end
    if fitH ~= height then window:setHeight(fitH) end
    if fitX ~= x then window:setX(fitX) end
    if fitY ~= y then window:setY(fitY) end
    return window
end

-- Windows register once; a single resolution handler re-clamps them all, so a
-- display change mid-session cannot leave a window half off the screen.
Layout.tracked = {}
function Layout.trackWindow(window)
    if window == nil then return window end
    if not Layout.resolutionHookInstalled and Events ~= nil
        and Events.OnResolutionChange ~= nil then
        Layout.resolutionHookInstalled = true
        Events.OnResolutionChange.Add(function()
            for _, tracked in pairs(Layout.tracked) do
                if tracked ~= nil and tracked.getX ~= nil and tracked:isVisible() then
                    Layout.clampWindow(tracked)
                end
            end
        end)
    end
    Layout.tracked[window] = true
    Layout.clampWindow(window)
    return window
end

return Layout
