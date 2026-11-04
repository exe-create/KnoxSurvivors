-- The stock transfer hook must accept ordinary items without a container API.
local oldAction = ISInventoryTransferAction
local oldCount, oldPlayer = getNumActivePlayers, getSpecificPlayer
local oldEnsure = KnoxPersistence.ensurePlayerId
local character = {}
local item = { data = { KnoxBaseProvision = "home" } }
function item:getModData() return self.data end
local source = { held = item }
function source:contains(value) return self.held == value end
function source:getParent() return nil end
local destination = {}
function destination:isInCharacterInventory(owner) return owner == character end
function destination:contains(value) return self.held == value end
ISInventoryTransferAction = { transferItem = function(self, value)
    self.srcContainer.held = nil
    self.destContainer.held = value
    return true
end }
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return character end
KnoxPersistence.ensurePlayerId = function() return "transfer-test-player" end
function runFactionTransferFixture()
    local action = setmetatable({ character = character, srcContainer = source,
        destContainer = destination }, { __index = ISInventoryTransferAction })
    assert(action:transferItem(item) == true, "native transfer should complete")
    assert(item.data.KnoxBaseProvision == nil,
        "ordinary transferred item must lose its old communal allocation")
    ISInventoryTransferAction = oldAction
    getNumActivePlayers, getSpecificPlayer = oldCount, oldPlayer
    KnoxPersistence.ensurePlayerId = oldEnsure
    print("Faction transfer allocation PASS ordinary_item=true native_receipt=true")
end
