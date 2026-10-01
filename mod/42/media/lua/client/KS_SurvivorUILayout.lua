-- Layout adapters only: character data and actions remain owned by vanilla UI.
local Layout = {}

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

return Layout
