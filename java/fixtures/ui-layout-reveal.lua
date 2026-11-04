-- The attention band scrolls an existing control into view. This fixture
-- proves the page-scroll arithmetic; it does not render a surface.
local L = assert(codecLayoutReveal, "layout reveal source is loaded")

local view = { height = 200, scroll = 0, extent = 500, writes = 0 }
function view:getHeight() return self.height end
function view:getYScroll() return self.scroll end
function view:setYScroll(value) self.scroll = value; self.writes = self.writes + 1 end
function view:getScrollHeight() return self.extent end

local control = { y = 300, height = 20 }
function control:getY() return self.y end
function control:getHeight() return self.height end

assert(L.reveal(view, control, 12) == true, "a below-fold control scrolls into view")
assert(view.scroll == -132, "the target leaves the requested margin below the fold")
assert(L.reveal(view, control, 12) == false, "an already visible control does not move")

view.scroll = -100
control.y = 20
assert(L.reveal(view, control, 12) == true, "an above-fold control scrolls up")
assert(view.scroll == -8, "the target leaves the requested margin above the fold")

view.scroll = -100
control.y = 150
local writes = view.writes
assert(L.reveal(view, control, 12) == false, "an in-view control is left alone")
assert(view.writes == writes, "no redundant scroll write")

view.scroll = 0
control.y = 900
assert(L.reveal(view, control, 12) == true, "a long page clamps to its extent")
assert(view.scroll == -300, "the page never scrolls past its last content")
view.scroll = 0

assert(L.reveal(nil, control, 12) == false, "a missing page is refused")
assert(L.reveal(view, nil, 12) == false, "a missing control is refused")

print("UI reveal PASS below=true above=true visible=false clamp=true")
