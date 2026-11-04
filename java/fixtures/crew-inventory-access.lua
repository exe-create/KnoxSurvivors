-- The Crew tab can now open the selected resident's pack, but only through the
-- existing survivor-inventory owner, and a refusal must be explained rather
-- than looking like a dead button. This fixture drives the real extracted
-- refusal wording and the real Crew handler with a fake owner and window.
assert(type(inventoryRefusalText) == "function",
    "the inventory refusal wording must be loaded")
assert(type(inventoryRequest) == "function",
    "the inventory request path must be loaded")
assert(type(crewInventoryHandler) == "function",
    "the Crew inventory handler must be loaded")

local previousCatalog = KnoxOrderCatalog

-- Without the order catalog the owner still explains every reason it can
-- return, in prose, without leaking the code.
KnoxOrderCatalog = nil
local reasons = {
    "player_unavailable", "survivor_unavailable", "not_your_survivor",
    "too_far_away", "interaction_ended", "inventory_ui_unavailable",
}
for _, reason in ipairs(reasons) do
    local text = inventoryRefusalText(reason)
    assert(type(text) == "string" and text ~= "", "a reason needs wording: " .. reason)
    assert(string.find(text, reason, 1, true) == nil,
        "the wording is prose, not the code: " .. reason)
    assert(string.sub(text, -1) == ".", "each refusal is a sentence: " .. reason)
end
assert(inventoryRefusalText("too_far_away") ~= inventoryRefusalText("interaction_ended"),
    "different refusals do not share one sentence")
assert(string.find(inventoryRefusalText("some_new_reason"), "some new reason", 1, true) ~= nil,
    "an unknown reason is still readable")
assert(string.find(inventoryRefusalText(nil), "unknown reason", 1, true) ~= nil,
    "no reason at all is still readable")
KnoxOrderCatalog = previousCatalog

-- With the shared vocabulary loaded, its sentence is used instead, so every
-- surface describes one refusal the same way.
KnoxOrderCatalog = { failureText = function(code) return "shared:" .. tostring(code) end }
assert(inventoryRefusalText("too_far_away") == "shared:too_far_away",
    "the shared order vocabulary owns the sentence when it is loaded")
KnoxOrderCatalog = previousCatalog
assert(inventoryRefusalText("too_far_away") ~= "shared:too_far_away",
    "the fallback returns when the catalog is gone")

-- The handler: refusal reported, success hides the notebook, no selection is a
-- no-op, and a missing owner is explained.
local events, hidden = {}, nil
KnoxActivityFeed = { event = function(text) events[#events + 1] = text end }
local window = {
    playerNum = 0,
    setVisible = function(_, visible) hidden = visible == false end,
}
local selected = "res-a"
local selfView = {
    selectedCrewId = function() return selected end,
    getWindow = function() return window end,
    playerNum = 0,
}

local lastCall = nil
KnoxCompanionInventory = {
    refusalText = inventoryRefusalText,
    show = function(playerNum, id)
        lastCall = { playerNum = playerNum, id = id }
        return false, "too_far_away"
    end,
}
events, hidden = {}, nil
crewInventoryHandler(selfView)
assert(lastCall ~= nil and lastCall.id == "res-a" and lastCall.playerNum == 0,
    "the selected resident and the notebook's player are passed to the owner")
assert(#events == 1 and events[1] == inventoryRefusalText("too_far_away"),
    "a refusal reaches the player as the owner's own wording")
assert(hidden ~= true, "a refusal leaves the roster where it was")

KnoxCompanionInventory = {
    show = function() lastCall = "accepted"; return true, "vanilla_loot_window" end,
}
events, hidden = {}, nil
crewInventoryHandler(selfView)
assert(lastCall == "accepted", "the owner is really asked")
assert(hidden == true, "the notebook steps aside once the pack opened")
assert(#events == 0, "a successful open does not need a message")

selected = nil
KnoxCompanionInventory = { show = function() error("must not be called") end }
events = {}
crewInventoryHandler(selfView)
assert(#events == 0, "no selected resident means no action")

selected = "res-a"
KnoxCompanionInventory = nil
events = {}
crewInventoryHandler(selfView)
assert(#events == 1 and string.find(events[1], "not available", 1, true) ~= nil,
    "a build without the inventory owner says so")

-- An owner without wording still gets a readable line, not a blank panel.
KnoxCompanionInventory = { show = function() return false, "too_far_away" end }
events = {}
crewInventoryHandler(selfView)
assert(#events == 1 and string.find(events[1], "cannot be opened", 1, true) ~= nil,
    "a plain owner falls back to a readable sentence")

-- One request path: a refusal always reports the shared sentence, a success
-- never speaks, and the caller keeps the real reason.
local requestOwner = { refusalText = inventoryRefusalText }
requestOwner.show = function() return false, "too_far_away" end
CompanionInventory = requestOwner
KnoxCompanionInventory = { refusalText = requestOwner.refusalText,
    show = requestOwner.show }
events = {}
local requested, requestReason = inventoryRequest(0, "res-a")
assert(requested == false and requestReason == "too_far_away",
    "the request reports the real refusal code to its caller")
assert(#events == 1 and events[1] == requestOwner.refusalText("too_far_away"),
    "the request explains the refusal with the shared sentence")
requestOwner.show = function() return true, "vanilla_loot_window" end
events = {}
assert(inventoryRequest(0, "res-a") == true and #events == 0,
    "a successful request says nothing")
-- The Crew tab keeps its own success handling on top of the same owner.
KnoxCompanionInventory = requestOwner
events = {}
hidden = nil
crewInventoryHandler(selfView)
assert(#events == 0 and hidden == true,
    "a successful Crew open says nothing and still steps aside")

-- A handler without a window still works: the pack opens and nothing is hidden.
KnoxCompanionInventory = { show = function() return true end }
local bare = { selectedCrewId = function() return "res-a" end, playerNum = 1 }
events = {}
crewInventoryHandler(bare)
assert(#events == 0, "a missing window is not an error")

print("Crew inventory access PASS wording=true refusal=true success=true "
    .. "noSelection=true")
