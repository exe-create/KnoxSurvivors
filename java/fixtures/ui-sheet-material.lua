-- One sheet material is shared by the creator and base management: dark slate
-- glass with a muted green accent, taken from the reference the owner gave on
-- 2026-11-10. The owner's report was that controls and frames were hard to tell
-- apart, so the properties under test are contrast and hue ownership, not taste.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")

assert(type(L.sheet) == "table", "the sheet material exists")
assert(type(L.sheetTheme) == "function", "the sheet theme builder exists")
assert(type(L.tintSheetButton) == "function", "the sheet button material exists")
assert(type(L.tintSheetWindow) == "function", "the sheet window material exists")
assert(type(L.tintSheetBorder) == "function", "the sheet frame material exists")
assert(type(L.tintSheetClose) == "function", "the close control material exists")

local sheet = L.sheet
assert(sheet.charcoal[1] == 0.10 and sheet.charcoal[2] == 0.12 and sheet.charcoal[3] == 0.12,
    "the sheet is the reference slate, not the retired warm paper")
assert(sheet.border[2] > sheet.border[1] and sheet.border[3] > sheet.border[1],
    "the hairline is green-tinted rather than grey")
assert(sheet.accent[2] > sheet.accent[1] and sheet.accent[2] > sheet.accent[3],
    "the one emphasis hue is green")

local function value(colour)
    return colour[1] + colour[2] + colour[3]
end
assert(value(sheet.fill) > value(sheet.charcoal) + 0.1,
    "a control fill sits a visible step above the sheet, got fill " .. tostring(value(sheet.fill))
    .. " against sheet " .. tostring(value(sheet.charcoal)))
assert(value(sheet.fillHover) > value(sheet.fill),
    "hover brightens the fill so the pointer is visible")
assert(value(sheet.well) < value(sheet.charcoal),
    "a list interior is a step below the sheet, so a list reads as a well")
-- The reference selects with a green fill brighter than the hover step, so the
-- property is distinctness, not an ordering between two unrelated states.
local selectedDistance = math.min(math.abs(value(sheet.selected) - value(sheet.charcoal)),
    math.abs(value(sheet.selected) - value(sheet.fillHover)))
assert(selectedDistance > 0.05,
    "the selected fill is visibly distinct from both the sheet and the hover step, got "
    .. tostring(selectedDistance))

local theme = L.sheetTheme()
assert(theme.border[1] == sheet.border[1] and theme.border[2] == sheet.border[2],
    "the sheet theme resolves its hairline from the shared tokens")
assert(theme.charcoal[1] == sheet.charcoal[1], "the sheet theme resolves the sheet colour")
assert(theme.accent[2] == sheet.accent[2], "the sheet theme exposes the accent")
assert(theme.red[1] == L.theme.red[1] and theme.green[2] == L.theme.green[2]
    and theme.blue[3] == L.theme.blue[3],
    "semantic hues pass through sheetTheme unchanged, so status colour still means status")
assert(theme.motion == L.theme.motion, "motion is not a material and stays shared")

local button = { label = "Rename", onClick = function() return "clicked" end }
L.tintSheetButton(button)
assert(button.backgroundColor ~= nil and button.backgroundColorMouseOver ~= nil,
    "the button receives fill and hover fill")
assert(button.backgroundColor.r == sheet.fill[1] and button.backgroundColor.a == 0.98,
    "the fill is the sheet fill token")
assert(button.borderColor.g == sheet.border[2] and button.borderColor.a == 0.95,
    "the border is the sheet hairline")
assert(button.onClick() == "clicked" and button.label == "Rename",
    "tinting never touches the label or the callback")
assert(L.tintSheetButton(nil) == nil, "a missing control is not an error")

local window = {}
L.tintSheetWindow(window)
assert(window.backgroundColor.g == sheet.charcoal[2] and window.backgroundColor.a == 0.97,
    "the window sheet is the slate colour")
assert(window.borderColor.g == sheet.border[2], "the window frame is the green hairline")

local list = {}
L.tintSheetBorder(list)
assert(list.borderColor.g == sheet.border[2] and list.borderColor.a == 0.95,
    "a bordered list gets the same frame")

-- Every window uses one material (owner direction 2026-11-10): the quiet
-- button and the sheet button are the same control.
local plain = { label = "Close" }
L.tintButton(plain)
assert(plain.backgroundColor.g == sheet.fill[2] and plain.borderColor.g == sheet.border[2],
    "the quiet button is the sheet material, not a private palette")

-- Owner decision 2026-11-10: keep the vanilla white circle X. Tinting the art
-- and painting a slate plate behind it made the way out of the window nearly
-- invisible, so only the native glyph is drawn.
local close = { image = "media/ui/inventoryPanes/Button_Close.png" }
L.tintSheetClose(close)
assert(close.textureColor ~= nil and close.textureColor.r == 1
    and close.textureColor.g == 1 and close.textureColor.b == 1,
    "the close cross keeps its vanilla white art")
-- ISButton:render reads textureColor.a for the image alpha. A table without it
-- handed nil to drawTextureScaledAspect, which threw on every rendered frame.
assert(close.textureColor.a == 1, "the close texture carries an alpha")
assert(close.backgroundColor.a == 0 and close.borderColor.a == 0
    and close.backgroundColorMouseOver.a == 0,
    "no slate plate sits behind the vanilla close cross")
assert(close.image == "media/ui/inventoryPanes/Button_Close.png",
    "the vanilla close texture - the hit target - is not replaced")
assert(L.tintSheetClose(nil) == nil, "a missing close control is not an error")

print("UI sheet material PASS contrast=" .. tostring(value(sheet.fill) - value(sheet.charcoal))
    .. " accentGreen=true closeVanilla=true closeAlpha=true semanticPassthrough=true")

-- One close: every window keeps the vanilla X, hides pin and collapse, and
-- names the way out. The rule is wired here so a window cannot drift.
assert(type(L.finishWindow) == "function", "the one-close rule exists")
assert(L.finishWindow(nil) == nil, "a missing window is not an error")
local pin, collapse = {}, {}
local closeBtn = {}
pin.setVisible = function(_, v) pin.hidden = not v end
collapse.setVisible = function(_, v) collapse.hidden = not v end
closeBtn.setVisible = function(_, v) closeBtn.shown = v end
local finished = { pinButton = pin, collapseButton = collapse, closeButton = closeBtn }
L.finishWindow(finished, "Close test panel")
assert(pin.hidden == true and collapse.hidden == true, "pin and collapse are hidden")
assert(closeBtn.shown == true, "the way out stays visible")
assert(closeBtn.tooltip == "Close test panel", "the way out is named")
assert(closeBtn.textureColor ~= nil and closeBtn.textureColor.a == 1,
    "the close glyph keeps its alpha")
print("UI one-close PASS pinCollapseHidden=true closeNamed=true closeAlpha=true")
