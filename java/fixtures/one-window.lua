-- The one-window rule is a registry over close callbacks, not a window. This
-- fixture proves which surface the rule closes, which it leaves alone, and
-- that a broken close cannot take the new surface down with it. It does not
-- open a real window or prove that the game draws only one.
local L = assert(codecOneWindow, "one-window source is loaded")

local closed = {}
local notebook = { close = function(playerNum)
    closed[#closed + 1] = "notebook:" .. tostring(playerNum)
end }
local card = { close = function(playerNum)
    closed[#closed + 1] = "card:" .. tostring(playerNum)
end }

assert(L.claimSurface(0, "notebook", notebook) == nil,
    "the first surface has no predecessor")
assert(L.surfaces[0] ~= nil and L.surfaces[0].kind == "notebook",
    "the first surface is recorded")
local previous = L.claimSurface(0, "card", card)
assert(previous ~= nil and previous.kind == "notebook",
    "the previous surface is returned")
assert(#closed == 1 and closed[1] == "notebook:0",
    "opening a second surface closes the first")
assert(L.surfaces[0].kind == "card", "the new surface owns the player")

L.claimSurface(0, "card", card)
assert(#closed == 1, "re-showing the same kind does not close it")

assert(L.releaseSurface(0, "notebook") == false,
    "a stale release does not clear the owner")
assert(L.releaseSurface(0, "card") == true, "the owner can release")
assert(L.surfaces[0] == nil, "the player has no surface after release")
assert(L.releaseSurface(0, "card") == false, "releasing twice is quiet")

L.claimSurface(1, "card", { close = function() error("boom") end })
assert(L.claimSurface(1, "notebook", notebook) ~= nil,
    "a throwing close still yields the new surface")
assert(L.surfaces[1].kind == "notebook",
    "the new surface survives a failed close")
assert(L.releaseSurface(1) == true, "a nil kind releases any surface")

L.claimSurface(4, "card", {})
assert(L.claimSurface(4, "trade", nil) ~= nil,
    "a surface without an api can still be replaced")
assert(L.surfaces[4].kind == "trade", "the replacement is recorded")

local closedBefore = #closed
L.claimSurface(2, "card", card)
L.claimSurface(3, "notebook", notebook)
assert(#closed == closedBefore,
    "one player's window does not close another player's")
assert(L.surfaces[2].kind == "card" and L.surfaces[3].kind == "notebook",
    "each player keeps their own surface")

print("OneWindow PASS replace=true same=true release=true throw=true split=true")
