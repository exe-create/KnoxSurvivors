-- One rule for every Knox window: the interface font is the player's scale
-- setting, capped by the smaller screen dimension. A 1920x1080 design on a
-- 1280x720 display must shrink; a large interface scale on a big display must
-- grow. Both the scale rule and the on-screen clamp are pure, so this drives
-- them with numbers instead of a running game.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "layout module is loaded")

assert(type(L.scaleFor) == "function", "the scale rule is exported")
assert(type(L.fitRect) == "function", "the window fit rule is exported")
assert(type(L.uiScale) == "function", "the live scale is exported")

-- Base font at 1080p: the design scale, no growth and no shrink.
local base = L.scaleFor(L.BASE_FONT_HEIGHT, 1920, 1080)
assert(base >= 1, "1080p at base font does not shrink, got " .. tostring(base))
assert(base <= 1.25, "1080p at base font does not balloon, got " .. tostring(base))

-- A small display caps the scale even when the font is at its base height.
local small = L.scaleFor(L.BASE_FONT_HEIGHT, 1280, 720)
assert(small <= base, "1280x720 is not larger than 1080p, got " .. tostring(small))
assert(small >= L.MIN_SCALE, "the scale never falls below the floor")

-- A raised interface font on a big display grows the surface.
local large = L.scaleFor(L.BASE_FONT_HEIGHT * 2, 2560, 1440)
assert(large > base, "a double-size font grows the scale, got " .. tostring(large))
assert(large <= L.MAX_SCALE, "the scale never passes the ceiling")

-- A very small screen with a huge font stays inside both limits.
local bounded = L.scaleFor(L.BASE_FONT_HEIGHT * 4, 1280, 720)
assert(bounded >= L.MIN_SCALE and bounded <= L.MAX_SCALE,
    "the scale stays inside its bounds, got " .. tostring(bounded))

-- Missing inputs fall back to the design scale rather than to zero or an error.
assert(L.scaleFor(nil, nil, nil) >= L.MIN_SCALE,
    "a missing font and screen still gives a usable scale")
assert(L.scaleFor(0, 0, 0) >= L.MIN_SCALE, "zero readings are ignored")

-- scaled() rounds down, so a caller gets a pixel count it can place.
assert(L.scaled(10) == math.floor(10 * L.uiScale()), "scaled() applies the scale")
assert(L.scaled(nil) == 0, "scaled(nil) is zero rather than an error")

-- A window larger than the screen is capped and slid back inside the margin.
local w, h, x, y = L.fitRect(2000, 1400, -50, -40, 1280, 720, 8)
assert(w == 1280 - 16, "an oversized window is capped to the screen, got " .. tostring(w))
assert(h == 720 - 16, "an oversized window is capped in height, got " .. tostring(h))
assert(x == 8 and y == 8, "a window off the top-left is slid back in")

-- A window already inside the screen is not moved or resized.
local iw, ih, ix, iy = L.fitRect(400, 300, 100, 90, 1280, 720, 8)
assert(iw == 400 and ih == 300 and ix == 100 and iy == 90,
    "a fitting window is left alone")

-- A window hanging off the bottom-right is pulled in, not shrunk.
local jw, jh, jx, jy = L.fitRect(400, 300, 1200, 700, 1280, 720, 8)
assert(jw == 400 and jh == 300, "an on-screen-sized window keeps its size")
assert(jx == 1280 - 400 - 8 and jy == 720 - 300 - 8,
    "the window is pulled fully inside the margin")

-- No screen reading leaves the rectangle untouched.
local nw, nh, nx, ny = L.fitRect(400, 300, 10, 20, nil, nil, 8)
assert(nw == 400 and nh == 300 and nx == 10 and ny == 20,
    "a missing screen does not move a window")

print("UI scale PASS base=true small=true large=true bounded=true fit=true")
