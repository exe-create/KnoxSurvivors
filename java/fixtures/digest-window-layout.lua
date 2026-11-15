local factory = assert(digestLayoutFactory)
local function check(font, screenW, screenH)
    local window, x, y = factory(font, screenW, screenH)
    assert(window.width > 0 and window.height > 0, "window has visible dimensions")
    assert(x >= 0 and y >= 0 and x + window.width <= screenW and y + window.height <= screenH,
        "actual window rectangle fits the screen")
    if screenH - window.height >= 42 then
        assert(y == screenH - window.height - 42, "bottom margin uses the actual height")
    end
    if screenW - window.width >= 18 then assert(x == 18, "left margin stays 18") end
    return window, x, y
end
for _, font in ipairs({ 14, 21, 28 }) do
    check(font, 1280, 720)
    check(font, 1920, 1080)
end
local scaled, _, scaledY = check(21, 1920, 1080)
assert(scaled.height == 390 and scaledY == 648, "large font uses the scaled 390px height")
check(28, 100, 80)
print("Digest window layout PASS actual_size=true fonts=true screens=true tiny=true")
