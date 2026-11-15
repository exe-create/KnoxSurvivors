-- The creator button belongs to the main menu screen and nowhere else. The
-- panel owns the facts; the rule that decides is pure, so every wrong screen is
-- provable without a running game.
local Creator = assert(rawget(_G, "KnoxCreator"), "creator model missing")

assert(Creator.MENU_BUTTON_LABEL == "Knox Creator",
    "the button names Knox Creator, got " .. tostring(Creator.MENU_BUTTON_LABEL))
assert(Creator.menuButtonVisible({ mainScreen = true, subScreen = false,
    inGame = false }) == true,
    "the main menu is the one screen that shows the button")
assert(Creator.menuButtonVisible({ mainScreen = true, subScreen = true,
    inGame = false }) == false,
    "a setup screen over the main menu hides the button")
assert(Creator.menuButtonVisible({ mainScreen = false, subScreen = false,
    inGame = true }) == false,
    "a running game hides the button")
assert(Creator.menuButtonVisible({ mainScreen = false, subScreen = false,
    inGame = false }) == false,
    "no main screen means no button")
assert(Creator.menuButtonVisible({ mainScreen = true, subScreen = true,
    inGame = true }) == false,
    "every wrong fact together still hides the button")
assert(Creator.menuButtonVisible(nil) == false,
    "missing facts hide the button instead of guessing")

assert(Creator.MENU_BUTTON_CAPTION == nil, "no caption line ships with the button")
print("creator_menu_button: label=KS Creator no caption menu=shown sub-screens=hidden game=hidden")
