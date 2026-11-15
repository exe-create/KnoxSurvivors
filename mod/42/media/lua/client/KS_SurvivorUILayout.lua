-- Layout adapters only: character data and actions remain owned by vanilla UI.
local Layout = {}
-- Late-bound HUD/card adapters share this same helper with require callers.
_G.KnoxSurvivorUILayout = Layout

-- Shared presentation tokens for the ambient HUD layer. These are colours,
-- spacing and motion only; no gameplay state or decision belongs here. The
-- palette is the accepted visual system in docs/production/design/UI.md.
Layout.theme = {
    charcoal = { 0.10, 0.12, 0.12 },
    bone = { 0.92, 0.95, 0.93 },
    muted = { 0.64, 0.71, 0.68 },
    border = { 0.33, 0.45, 0.38 },
    amber = { 0.851, 0.643, 0.255 },
    red = { 0.769, 0.333, 0.247 },
    green = { 0.431, 0.561, 0.353 },
    blue = { 0.357, 0.498, 0.651 },
    -- Two neutral text tiers between bone and muted: a label is quieter than a
    -- value, and a dim line quieter still. They live here so secondary text has
    -- one tone instead of a grey per window.
    label = { 0.86, 0.91, 0.88 },
    dim = { 0.55, 0.62, 0.59 },
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
    local function appendWord(value)
        if #paragraph > 0 then
            local candidate = table.concat(paragraph, " ") .. " " .. value
            if measureX(candidate) <= limit then
                paragraph[#paragraph + 1] = value
                return
            end
            breakLine()
        end
        -- Long names and modded item names still belong on the sheet. Break
        -- an oversized token across lines without discarding its ending.
        if measureX(value) <= limit then
            paragraph[1] = value
            return
        end
        local part = ""
        for index = 1, #value do
            local char = string.sub(value, index, index)
            if part ~= "" and measureX(part .. char) > limit then
                lines[#lines + 1] = part
                part = char
            else
                part = part .. char
            end
        end
        if part ~= "" then paragraph[1] = part end
    end
    local word = nil
    for index = 1, #text + 1 do
        local char = string.sub(text, index, index)
        if char == " " or char == "\n" or char == "" then
            if word ~= nil then
                appendWord(word)
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
    while #suffix > 0 and measureX(suffix) > limit do
        suffix = string.sub(suffix, 1, #suffix - 1)
    end
    -- Prefix widths in the UI fonts are monotonic. Search instead of measuring
    -- every successively shorter label on each rendered frame. Round each probe
    -- back to a UTF-8 boundary so authored/localized names cannot lose half a glyph.
    local low, high, best = 0, #value, 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local finish = middle
        local byte = string.byte(value, finish + 1)
        while finish > 0 and byte ~= nil and byte >= 128 and byte < 192 do
            finish = finish - 1
            byte = string.byte(value, finish + 1)
        end
        if measureX(string.sub(value, 1, finish) .. suffix) <= limit then
            best, low = finish, middle + 1
        else high = middle - 1 end
    end
    return string.sub(value, 1, best) .. suffix
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
    -- One material for every window (owner direction 2026-11-10): the quiet
    -- button is the sheet button, so a control cannot read warm in one window
    -- and green in the next. Kept as a name because existing callers use it.
    return Layout.tintSheetButton(button)
end

-- SHEET MATERIAL (creator and base management)
-- Dark slate glass with one muted green accent: the owner gave a reference
-- (2026-11-10) of a near-black slate sheet, green hairlines and a green
-- selection, and asked for it in place of the warm paper set. A control
-- sits one visible step above the sheet it is drawn on, because a fill
-- equal to its own background is what left buttons with no readable edge.
-- One owner for both surfaces: the creator and base management read these
-- tokens instead of keeping private copies that drift. Semantic hues (red,
-- green, blue, motion) are not redeclared; sheetTheme passes them through.
Layout.sheet = {
    charcoal = { 0.10, 0.12, 0.12 },
    well = { 0.07, 0.09, 0.09 },
    border = { 0.33, 0.45, 0.38 },
    accent = { 0.46, 0.72, 0.55 },
    bone = { 0.92, 0.95, 0.93 },
    muted = { 0.64, 0.71, 0.68 },
    label = { 0.86, 0.91, 0.88 },
    dim = { 0.55, 0.62, 0.59 },
    amber = { 0.86, 0.68, 0.38 },
    fill = { 0.15, 0.20, 0.18 },
    fillHover = { 0.21, 0.29, 0.24 },
    selected = { 0.22, 0.42, 0.30 },
}

function Layout.sheetTheme()
    local theme = {}
    for key, value in pairs(Layout.theme) do theme[key] = value end
    for key, value in pairs(Layout.sheet) do theme[key] = value end
    return theme
end

-- Button material on the sheet: fill, the hover step and the hairline.
-- Presentation only: a label, callback and enable state stay the control's
-- own and are never touched here.
function Layout.tintSheetButton(button)
    if button == nil then return button end
    local sheet = Layout.sheet
    button.borderColor = { r = sheet.border[1], g = sheet.border[2],
        b = sheet.border[3], a = 0.95 }
    button.backgroundColor = { r = sheet.fill[1], g = sheet.fill[2],
        b = sheet.fill[3], a = 0.98 }
    button.backgroundColorMouseOver = { r = sheet.fillHover[1],
        g = sheet.fillHover[2], b = sheet.fillHover[3], a = 1 }
    return button
end

-- The vivid close control. Its vanilla art is a texture-only cross drawn
-- darker than this sheet, so the way out of the window disappeared into
-- the title bar (owner report, 2026-11-10). The texture stays - it is the
-- real hit target - and is tinted in the accent instead.
function Layout.tintSheetClose(button)
    if button == nil then return button end
    -- Owner decision 2026-11-10: keep the vanilla white circle X everywhere.
    -- Tinting the art green and painting a slate plate behind it is what made
    -- the way out of the window nearly invisible. The native texture stays the
    -- real hit target; only the plate and border are cleared.
    button.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    button.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    button.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    -- ISButton:render reads textureColor.a for the image alpha. A table without
    -- it handed nil to drawTextureScaledAspect, which threw on every frame the
    -- notebook was open and filled the console. White also restores the glyph.
    button.textureColor = { r = 1, g = 1, b = 1, a = 1 }
    return button
end

-- ONE CLOSE (wiring, not art)
-- Every collapsable Knox window keeps the vanilla white circle X, hides pin
-- and collapse, and names the way out in a tooltip. One function so a window
-- cannot drift: an invisible X, a second plate behind the glyph, or a close
-- nobody can name are all the same defect class as a clipped label.
function Layout.finishWindow(window, tooltip)
    if window == nil then return window end
    if window.pinButton ~= nil then
        pcall(function() window.pinButton:setVisible(false) end)
    end
    if window.collapseButton ~= nil then
        pcall(function() window.collapseButton:setVisible(false) end)
    end
    if window.closeButton ~= nil then
        pcall(function() window.closeButton:setVisible(true) end)
        if tooltip ~= nil then window.closeButton.tooltip = tostring(tooltip) end
        Layout.tintSheetClose(window.closeButton)
    end
    Layout.trackWindow(window)
    return window
end

-- A list or panel frame, so a bordered list reads as a box rather than as
-- another run of background.
function Layout.tintSheetBorder(control)
    if control == nil then return control end
    local border = Layout.sheet.border
    control.borderColor = { r = border[1], g = border[2], b = border[3], a = 0.95 }
    return control
end

function Layout.tintSheetWindow(window)
    if window == nil then return window end
    local sheet = Layout.sheet
    window.backgroundColor = { r = sheet.charcoal[1], g = sheet.charcoal[2],
        b = sheet.charcoal[3], a = 0.97 }
    window.borderColor = { r = sheet.border[1], g = sheet.border[2],
        b = sheet.border[3], a = 0.95 }
    return window
end
-- END SHEET MATERIAL

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
    local contentH = view.knoxContentHeight ~= nil
        and math.max(height, view.knoxContentHeight) or math.max(height, currentH)
    view:setScrollWidth(math.max(width, view.knoxContentWidth or width, currentW))
    if currentH ~= contentH then view:setScrollHeight(contentH) end
    if view.vscroll ~= nil then view.vscroll:setVisible(contentH > height) end
    if view.getYScroll ~= nil and view.setYScroll ~= nil then
        local scroll = tonumber(view:getYScroll()) or 0
        local target = math.max(height - contentH, math.min(0, scroll))
        if target ~= scroll then view:setYScroll(target) end
    end
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
        prerender(self)
        -- Knox page layouts can grow or shrink without a window resize.
        -- Native pages without an authored extent retain their measured height.
        Layout.fitView(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    view.render = function(self)
        render(self)
        self:clearStencilRect()
    end
    local wheel = view.onMouseWheel
    view.onMouseWheel = function(self, delta)
        -- ISUIElement supplies an inherited no-op, so testing for nil misses
        -- every normal page. Retain explicit/native handlers, then scroll here.
        if wheel ~= nil and wheel(self, delta) == true then return true end
        return Layout.scrollPage(self, delta)
    end
    Layout.fitView(view)
end

function Layout.scrollPage(view, delta)
    if view == nil or view.setYScroll == nil or view.getYScroll == nil then return false end
    local height = view.getScrollAreaHeight and view:getScrollAreaHeight() or view.height
    local extent = view.getScrollHeight and view:getScrollHeight() or height
    local minimum = math.min(0, (tonumber(height) or 0) - (tonumber(extent) or 0))
    if minimum == 0 then return false end
    local target = math.max(minimum, math.min(0, (view:getYScroll() or 0) - delta * 30))
    view:setYScroll(target)
    return true
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
        return Layout.scrollPage(view, delta), nil
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
    -- Aiming closes a conversation surface, but a loot pane stays usable while
    -- the player holds aim exactly as a world container does. Only a surface
    -- that says so opts out; every other surface keeps the close.
    if aiming and context.checkAiming ~= false then return false, "player_aiming" end
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
            checkAiming = config.checkAiming,
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
    -- Installed 42.21 exposes screen dimensions on Core, not as Lua globals.
    if type(getCore) == "function" then
        local ok, width, height = pcall(function()
            local core=getCore()
            return core:getScreenWidth(),core:getScreenHeight()
        end)
        if ok and tonumber(width) ~= nil and tonumber(height) ~= nil then
            return tonumber(width),tonumber(height)
        end
    end
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
-- the smaller screen dimension. Pure on purpose - the fixture drives it with
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
    -- Field reads, never getX/getY: the installed getters instantiate the
    -- element, and an element built here would run `createChildren` before its
    -- owning class metatable is installed (blank card, 2026-11-10 report).
    local x = tonumber(window.x) or 0
    local y = tonumber(window.y) or 0
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
            for tracked in pairs(Layout.tracked) do
                if tracked ~= nil and tracked.getX ~= nil and tracked:isVisible() then
                    Layout.clampWindow(tracked)
                end
            end
        end)
    end
    if not window.knoxTrackedRemoval and window.removeFromUIManager ~= nil then
        local remove=window.removeFromUIManager
        window.removeFromUIManager=function(self,...)
            -- Removed person windows must not keep their former bodies/controls
            -- alive through this transient set. Reopened windows register again.
            Layout.tracked[self]=nil
            return remove(self,...)
        end
        window.knoxTrackedRemoval=true
    end
    Layout.tracked[window] = true
    Layout.clampWindow(window)
    return window
end


-- PAGE GRAMMAR (2026-11-04)
-- Every Knox page was assembling the same five shapes by hand: a strip of
-- counts, a value row, an empty state, a wrapped footer and the metrics around
-- them. The arithmetic lives here once, with every measurement injected, so a
-- fixture can prove it without a font atlas and one page cannot drift from the
-- next. Nothing here reads gameplay state or decides anything.

-- Counts lead and the unit follows the number: "3 residents", never
-- "Residents: 3". A field label spends width saying the same thing twice and
-- was what clipped its neighbours on every page.
function Layout.valueRow(value, label, options)
    local source = type(options) == "table" and options or {}
    local number = tostring(value == nil and 0 or value)
    local unit = tostring(label == nil and "" or label)
    local tone = tostring(source.tone or "bone")
    if Layout.theme[tone] == nil then tone = "bone" end
    return {
        value = number,
        label = unit,
        text = unit ~= "" and (number .. " " .. unit) or number,
        tone = tone,
    }
end

-- A strip of counts. Each cell is one number and its unit. Cells never shrink
-- past the minimum a number needs to stay readable: the strip wraps to another
-- row instead, which is the difference between a small display and clipped
-- digits. Pure: the caller injects gap, minimum and row height.
function Layout.statStripCells(values, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gap = math.max(0, tonumber(source.gap) or 6)
    local minCell = math.max(1, tonumber(source.minCell) or 96)
    if type(source.measure) == "function" then
        for _, entry in ipairs(type(values) == "table" and values or {}) do
            minCell = math.max(minCell, source.measure(tostring(entry.value or ""))
                + 5 + source.measure(tostring(entry.label or "")))
        end
    end
    local rowH = math.max(1, tonumber(source.rowH) or 26)
    local count = type(values) == "table" and #values or 0
    local perRow = math.max(1, math.floor((available + gap) / (minCell + gap)))
    if count > 0 and perRow > count then perRow = count end
    local cellW = count > 0 and math.floor((available - (perRow - 1) * gap) / perRow)
        or available
    if count > 0 and cellW < minCell then
        perRow = 1
        cellW = available
    end
    local cells = {}
    for index = 1, count do
        local entry = type(values[index]) == "table" and values[index] or {}
        local row = math.floor((index - 1) / perRow)
        local slot = (index - 1) % perRow
        cells[#cells + 1] = {
            value = tostring(entry.value == nil and "" or entry.value),
            label = tostring(entry.label == nil and "" or entry.label),
            text = tostring(entry.text == nil and "" or entry.text),
            tone = tostring(entry.tone or "bone"),
            x = slot * (cellW + gap),
            width = cellW,
            y = row * rowH,
            height = rowH,
            row = row,
        }
    end
    local rows = count > 0 and math.ceil(count / perRow) or 0
    return {
        cells = cells,
        columns = perRow,
        rows = rows,
        cellWidth = cellW,
        rowHeight = rowH,
        width = available,
        height = rows * rowH,
    }
end

-- Paints a strip built by statStripCells. The number is bone and the unit is
-- quieter, so a glance reads the count and a second look reads what it counts.
function Layout.drawStatStrip(view, strip, x, y)
    if view == nil or type(strip) ~= "table" then return 0 end
    local font = UIFont.Small
    local manager = getTextManager()
    local fontH = manager:getFontHeight(font)
    for _, cell in ipairs(strip.cells or {}) do
        local tone = Layout.colour(cell.tone)
        local cellX = (x or 0) + (tonumber(cell.x) or 0)
        local cellY = (y or 0) + (tonumber(cell.y) or 0)
            + math.max(0, math.floor(((tonumber(cell.height) or fontH) - fontH) / 2))
        local width = tonumber(cell.width) or 0
        local cursor = cellX
        if cell.value ~= "" then
            local bone = Layout.colour("bone")
            view:drawText(cell.value, cursor, cellY, bone[1], bone[2], bone[3], 1, font)
            cursor = cursor + manager:MeasureStringX(font, cell.value) + 5
        end
        local room = math.max(1, width - (cursor - cellX))
        local label = Layout.fitText(font, cell.label, room,
            function(candidate) return manager:MeasureStringX(font, candidate) end)
        if label ~= "" then
            view:drawText(label, cursor, cellY, tone[1], tone[2], tone[3], 1, font)
        end
    end
    return tonumber(strip.height) or 0
end

-- The empty state is copy plus the one action that ends it, never a blank
-- field with greyed buttons. Lines are wrapped by the same rule as every other
-- paragraph, with the measure injected.
function Layout.emptyState(text, actionLabel, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local measure = type(source.measure) == "function" and source.measure
        or function(value) return #value end
    local width = math.max(1, tonumber(availableWidth) or 1)
    local copy = tostring(text or "")
    local lines = Layout.wrapLines(copy, width, measure)
    if #lines == 0 and copy ~= "" then lines = { copy } end
    return {
        text = copy,
        lines = lines,
        action = actionLabel ~= nil and tostring(actionLabel) or nil,
        showsAction = actionLabel ~= nil,
        width = width,
    }
end

-- Wrapped footer. Four actions on one line overlapped on a narrow page because
-- each x was derived from the previous button's right edge. Placement is
-- computed here instead: measured width, a second row when the row is full,
-- and a total height the page reserves before it draws anything.
function Layout.footerPlacements(controls, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local available = math.max(1, tonumber(availableWidth) or 1)
    local spacing = math.max(0, tonumber(source.spacing) or 6)
    local buttonH = math.max(1, tonumber(source.buttonHeight) or 20)
    local measure = type(source.measure) == "function" and source.measure
        or function(value) return #value end
    local placements = {}
    local x, row = 0, 0
    for _, control in ipairs(type(controls) == "table" and controls or {}) do
        local label = tostring(control.title or control.name or "")
        local preferred = tonumber(control.knoxPreferredWidth) or tonumber(control.width) or 0
        local width = math.min(available, math.max(preferred, measure(label) + 24))
        if width < 1 then width = math.min(available, 1) end
        if x > 0 and x + width > available then x, row = 0, row + 1 end
        placements[#placements + 1] = {
            control = control, x = x, y = row * (buttonH + spacing),
            width = width, height = buttonH, row = row,
        }
        x = x + width + spacing
    end
    local rows = #placements > 0 and (row + 1) or 0
    return {
        placements = placements,
        rows = rows,
        rowHeight = buttonH,
        height = rows > 0 and (rows * buttonH + (rows - 1) * spacing) or 0,
    }
end
-- END PAGE GRAMMAR


-- TWO COLUMNS (pure)
-- A page splits into two readable columns only when both sides can hold their
-- minimum; otherwise it stays one column. The footprint is therefore measured,
-- never assumed: a small display or a large interface font collapses to one
-- column instead of clipping the right side.
function Layout.columns(availableWidth, options)
    local source = type(options) == "table" and options or {}
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gap = math.max(0, tonumber(source.gap) or 12)
    local minLeft = math.max(1, tonumber(source.minLeft) or 280)
    local minRight = math.max(1, tonumber(source.minRight) or 280)
    if available < minLeft + minRight + gap then
        return {
            count = 1, gap = gap, width = available, height = 0,
            cells = { { x = 0, width = available }, { x = 0, width = available } },
        }
    end
    local left = math.floor((available - gap) / 2)
    local right = available - left - gap
    return {
        count = 2, gap = gap, width = available, height = 0,
        cells = {
            { x = 0, width = left },
            { x = left + gap, width = right },
        },
    }
end

-- STATIC LIST HEIGHT (pure)
-- A list inside a scrolling page must not scroll itself, or the wheel moves two
-- things at once and the page has two scrollbars. Sizing the list to its rows is
-- what leaves exactly one scroller on the page.
function Layout.stackHeight(rows, itemHeight, minimumRows, padding)
    local count = math.max(tonumber(minimumRows) or 1, tonumber(rows) or 0)
    return count * math.max(1, tonumber(itemHeight) or 20) + (tonumber(padding) or 6)
end

-- TIMELINE (pure)
-- Equal blocks with optional measured minimum width. A schedule can grow down
-- the page instead of cutting the end from a time range to keep one thin row.
function Layout.timelineCells(count, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local n = math.max(1, math.floor(tonumber(count) or 1))
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gap = math.max(0, tonumber(source.gap) or 3)
    local height = math.max(1, tonumber(source.height) or 26)
    local columns = n
    local minimum = tonumber(source.minCellWidth)
    if minimum ~= nil and minimum > 0 then
        columns = math.max(1, math.min(n, math.floor((available + gap) / (minimum + gap))))
    end
    local rows = math.ceil(n / columns)
    local cellW = math.floor((available - (columns - 1) * gap) / columns)
    if cellW < 1 then cellW = 1 end
    local cells = {}
    for index = 1, n do
        cells[index] = {
            index = index,
            x = ((index - 1) % columns) * (cellW + gap),
            y = math.floor((index - 1) / columns) * (height + gap),
            width = cellW,
            height = height,
        }
    end
    return { cells = cells, count = n, width = available,
        height = rows * height + (rows - 1) * gap,
        rows = rows, columns = columns, cellWidth = cellW, gap = gap }
end

function Layout.timelineIndexAt(timeline, x, y)
    if type(timeline) ~= "table" or type(timeline.cells) ~= "table" then return nil end
    local point = tonumber(x)
    local vertical = tonumber(y) or 0
    if point == nil then return nil end
    for _, cell in ipairs(timeline.cells) do
        local top = cell.y or 0
        if point >= cell.x and point < cell.x + cell.width
            and vertical >= top and vertical < top + cell.height then
            return cell.index
        end
    end
    return nil
end

-- TABLE (pure)
-- A labelled grid: a gutter for row names, then equal cells. Used for the work
-- preference table, where a row is a job and a column is a state.
function Layout.tableCells(rows, columns, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local rowCount = math.max(0, tonumber(rows) or 0)
    local columnCount = math.max(0, tonumber(columns) or 0)
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gutter = math.max(0, tonumber(source.gutter) or 0)
    local gap = math.max(0, tonumber(source.gap) or 4)
    local rowHeight = math.max(1, tonumber(source.rowHeight) or 20)
    local body = math.max(1, available - gutter - (gutter > 0 and gap or 0))
    local cellW = columnCount > 0
        and math.floor((body - (columnCount - 1) * gap) / columnCount) or body
    if cellW < 1 then cellW = 1 end
    local cells = {}
    for row = 1, rowCount do
        for column = 1, columnCount do
            cells[#cells + 1] = {
                row = row,
                column = column,
                x = gutter + (gutter > 0 and gap or 0) + (column - 1) * (cellW + gap),
                y = (row - 1) * rowHeight,
                width = cellW,
                height = rowHeight,
            }
        end
    end
    return {
        cells = cells, rows = rowCount, columns = columnCount,
        cellWidth = cellW, rowHeight = rowHeight, gutter = gutter,
        width = available, height = rowCount * rowHeight,
    }
end

function Layout.tableCellAt(grid, x, y)
    if type(grid) ~= "table" or type(grid.cells) ~= "table" then return nil end
    local px, py = tonumber(x), tonumber(y)
    if px == nil or py == nil then return nil end
    for _, cell in ipairs(grid.cells) do
        if px >= cell.x and px < cell.x + cell.width
            and py >= cell.y and py < cell.y + cell.height then
            return cell
        end
    end
    return nil
end
-- CARD GRID (pure)
-- Cards are the widest readable unit on a page: three across when the width can
-- hold them, fewer when it cannot, never narrower than the minimum a label, a
-- count and two steppers need. Same measured rule as Layout.columns, one level
-- lower, so a small display stacks cards instead of clipping them.
function Layout.cardGrid(count, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local n = math.max(0, tonumber(count) or 0)
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gap = math.max(0, tonumber(source.gap) or 10)
    local minWidth = math.max(1, tonumber(source.minWidth) or 220)
    local cardHeight = math.max(1, tonumber(source.cardHeight) or 74)
    local maxColumns = math.max(1, math.min(3, tonumber(source.columns) or 3))
    local columns = maxColumns
    local cellW = available
    while columns > 1 do
        cellW = math.floor((available - (columns - 1) * gap) / columns)
        if cellW >= minWidth then break end
        columns = columns - 1
    end
    cellW = math.floor((available - (columns - 1) * gap) / columns)
    if cellW < 1 then cellW = 1 end
    local cells = {}
    for index = 1, n do
        local row = math.floor((index - 1) / columns)
        cells[index] = {
            index = index,
            row = row,
            column = ((index - 1) % columns) + 1,
            x = ((index - 1) % columns) * (cellW + gap),
            y = row * (cardHeight + gap),
            width = cellW,
            height = cardHeight,
        }
    end
    local rows = n > 0 and math.ceil(n / columns) or 0
    return {
        cells = cells, count = n, columns = columns, cellWidth = cellW,
        cardHeight = cardHeight, gap = gap, width = available, rows = rows,
        height = rows > 0 and (rows * cardHeight + (rows - 1) * gap) or 0,
    }
end

-- The three parts inside a card: a level bar and the two steppers. Returned as
-- rects so the drawing code and the hit test read the same numbers.
function Layout.cardParts(cell)
    if type(cell) ~= "table" then return nil end
    local width = math.max(1, tonumber(cell.width) or 1)
    local height = math.max(1, tonumber(cell.height) or 1)
    local pad, stepperH, stepperW, barH = 6, 16, 22, 6
    local plusX = width - pad - stepperW
    local minusX = plusX - 4 - stepperW
    local barY = height - pad - stepperH - 6 - barH
    return {
        bar = { x = pad, y = barY, width = math.max(1, width - pad * 2), height = barH },
        minus = { x = minusX, y = height - pad - stepperH, width = stepperW, height = stepperH },
        plus = { x = plusX, y = height - pad - stepperH, width = stepperW, height = stepperH },
    }
end

-- ITEM TARGET ROW (pure)
-- One row per named item minimum: the name on the left, the count against the
-- right edge and two steppers after it. The label keeps a readable width, so a
-- narrow page drops the count rather than drawing it under a stepper.
function Layout.itemTargetParts(width, rowHeight)
    local w = math.max(1, tonumber(width) or 1)
    local rowH = math.max(1, tonumber(rowHeight) or 26)
    local pad = 8
    local stepper = math.max(18, math.min(28, math.floor(rowH - 6)))
    local plus = { x = w - pad - stepper, y = math.floor((rowH - stepper) / 2),
        width = stepper, height = stepper }
    local minus = { x = plus.x - stepper - 4, y = plus.y,
        width = stepper, height = stepper }
    if w < 190 then
        return {
            label = { x = pad, y = 0, width = math.max(1, minus.x - pad - 6), height = rowH },
            count = { x = math.max(pad, minus.x - 8), y = 0, width = 0, height = rowH },
            minus = minus, plus = plus, stepper = stepper, rowHeight = rowH,
        }
    end
    local countW = math.max(72, math.min(140, math.floor(w * 0.28)))
    local countX = math.max(pad + 70, minus.x - 8 - countW)
    countX = math.min(countX, math.max(pad + 70, minus.x - 8))
    local count = { x = countX, y = 0,
        width = math.max(1, minus.x - 8 - countX), height = rowH }
    return {
        label = { x = pad, y = 0, width = math.max(1, countX - pad - 6), height = rowH },
        count = count, minus = minus, plus = plus,
        stepper = stepper, rowHeight = rowH,
    }
end

-- CHIPS (pure)
-- A chip is one short word in a box: role, standing, "needs 2". Placement is
-- computed here so a row of them cannot overlap or run off the sheet. The
-- measure is injectable for the same reason as every other helper: the
-- arithmetic is provable without a font atlas.
function Layout.chipCells(values, availableWidth, options)
    local source = type(options) == "table" and options or {}
    local available = math.max(1, tonumber(availableWidth) or 1)
    local gap = math.max(0, tonumber(source.gap) or 6)
    local pad = math.max(0, tonumber(source.pad) or 8)
    local height = math.max(1, tonumber(source.height) or 16)
    local measure = type(source.measure) == "function" and source.measure
        or function(value) return #value end
    local cells = {}
    local x, row = 0, 0
    for _, entry in ipairs(type(values) == "table" and values or {}) do
        local text = type(entry) == "table" and tostring(entry.text or "") or tostring(entry or "")
        if text ~= "" then
            local width = math.min(available, math.ceil(measure(text) + pad * 2))
            if x > 0 and x + width > available then x, row = 0, row + 1 end
            cells[#cells + 1] = {
                text = text,
                tone = type(entry) == "table" and entry.tone or nil,
                x = x, y = row * (height + gap),
                width = width, height = height, row = row,
            }
            x = x + width + gap
        end
    end
    local rows = #cells > 0 and (row + 1) or 0
    return {
        cells = cells,
        rows = rows,
        width = available,
        rowHeight = height,
        gap = gap,
        height = rows > 0 and (rows * height + (rows - 1) * gap) or 0,
    }
end

-- Paints a chip row built by chipCells. The box is the border tone at low
-- alpha; the word carries the meaning's accent, so a chip is readable at Small
-- without becoming a second background.
function Layout.drawChips(view, chips, x, y, options)
    if view == nil or type(chips) ~= "table" then return 0 end
    local source = type(options) == "table" and options or {}
    local font = source.font or UIFont.Small
    local manager = getTextManager()
    local fontH = manager:getFontHeight(font)
    local border = Layout.colour("border")
    for _, cell in ipairs(chips.cells or {}) do
        local tone = Layout.colour(cell.tone or source.tone or "muted")
        local cellX = (x or 0) + (tonumber(cell.x) or 0)
        local cellY = (y or 0) + (tonumber(cell.y) or 0)
        local width = tonumber(cell.width) or 0
        local height = tonumber(cell.height) or fontH
        view:drawRect(cellX, cellY, width, height,
            0.30, border[1], border[2], border[3])
        local label = Layout.fitText(font, tostring(cell.text or ""), math.max(1, width - 8),
            function(candidate) return manager:MeasureStringX(font, candidate) end)
        view:drawText(label, cellX + 4,
            cellY + math.max(0, math.floor((height - fontH) / 2)),
            tone[1], tone[2], tone[3], 1, font)
    end
    return tonumber(chips.height) or 0
end
-- END CHIPS

-- END PAGE SHAPES2


return Layout
