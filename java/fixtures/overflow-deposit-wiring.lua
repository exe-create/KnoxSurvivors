-- The overflow decision and the player notice belong to different owners: the
-- storage lookup ranks the destination, the controller queues the real transfer
-- and reports the receipt. This fixture joins them, so the flag and the
-- container name are proven to survive the hand-off rather than only existing in
-- each half.
local C = KnoxAutonomyController
local Storage = KnoxBaseStorage
local p = KnoxPersistence

local previousRoot = data["KnoxSurvivors_IsoPlayer"]
data["KnoxSurvivors_IsoPlayer"] = nil

local captured = {}
local previousFeed = KnoxActivityFeed
KnoxActivityFeed = {
    event = function(text) captured[#captured + 1] = tostring(text) end,
    speak = function() end,
}

local previousManager = KnoxBaseManager
KnoxBaseManager = { containsSquare = function() return true end }

assert(p.setRecord("overflow-wiring", expectedRecord))
p.ensureSurvivorIdentity("overflow-wiring", "Rae", "Moss", 10, 41)
assert(p.setPlayerCompanion("overflow-wiring", "wiring-owner", "hold", 10))
local base = assert(p.createBase("player", "wiring-owner", {
    minX = 100, minY = 200, width = 12, height = 10, z = 0,
    buildingId = "wiring-home",
}, 10, nil, true))

local function box(present)
    return { contains = function(_, item) return present(item) end }
end

local carried = box(function() return true end)
local function newItem(name, fullType)
    return {
        getName = function() return name end,
        getFullType = function() return fullType end,
        -- A hauled-in settlement item is still inside the container the search
        -- filled, so the delivery owner asks the item for its real source.
        getContainer = function() return carried end,
    }
end

local square = { getX = function() return 105 end, getY = function() return 205 end,
    getZ = function() return 0 end }
local inventory = box(function() return true end)
local character = {
    getCurrentSquare = function() return square end,
    getInventory = function() return inventory end,
    getCharacterActions = function() return nil end,
}

local controller = setmetatable({
    id = "overflow-wiring", baseId = base.id, base = { id = base.id },
    character = character,
}, C)

-- The real label owner names the shelf; only the ranked lookup is doubled here,
-- because the ranking itself has its own fixture.
local toolsPolicy = { key = "tools-shelf", storageFilterVersion = 1,
    storageRole = "tools", storageFilters = { tools = true } }
local destination = box(function() return true end)
local overflowHit = true
local requestedKey = nil
local oldTrip, oldNear = Storage.findDepositTrip, Storage.findNearbyDeposit
Storage.findDepositTrip = function() return { policy = toolsPolicy, approach = square }, "nearby_storage" end
Storage.findNearbyDeposit = function(_, _, _, policyKey)
    requestedKey = policyKey
    return { policy = toolsPolicy, container = destination, square = square,
        overflow = overflowHit or nil }
end

local queued = {}
controller.queueInventoryCleanup = function(self, transfer)
    queued[#queued + 1] = transfer
    return true, "queued"
end

-- A redirected haul reaches the transfer with its meaning intact.
local cargo = newItem("Canned Beans", "Base.CannedBeans")
controller.pendingBaseSupplyDeposit = { item = cargo, partyDelivery = true }
assert(controller:beginBaseSupplyDeposit(100) == true,
    "a full base still finds a destination to shelf the haul")
assert(#queued == 1, "one haul queues one transfer")
local transfer = queued[1]
assert(transfer.overflow == true, "the transfer is marked as an overflow decision")
assert(transfer.overflowLabel == "Tools", "the transfer names the container that took it")
assert(transfer.policyKey == "tools-shelf" and requestedKey == "tools-shelf",
    "the planned shelf is re-validated by its own key")
assert(transfer.baseSupply == true and transfer.partyDelivery == true
    and transfer.reason == "base_supply" and transfer.item == cargo
    and transfer.destination == destination,
    "the existing settlement-delivery transfer fields are unchanged")

-- A matching shelf is not an overflow and produces no label.
overflowHit = false
controller.pendingBaseSupplyDeposit = { item = cargo, partyDelivery = true }
assert(controller:beginBaseSupplyDeposit(110) == true)
assert(#queued == 2)
assert(queued[2].overflow ~= true and queued[2].overflowLabel == nil,
    "an ordinary delivery stays an ordinary delivery")

-- No destination at all is still reported, never queued, and stays open.
Storage.findDepositTrip = function() return nil, "storage_full" end
controller.pendingBaseSupplyDeposit = { item = cargo, partyDelivery = true }
captured = {}
assert(controller:beginBaseSupplyDeposit(120) == false,
    "a haul with no destination is not transferred")
assert(#queued == 2, "nothing is queued without a destination")
assert(#captured == 1 and string.find(captured[1], "full", 1, true) ~= nil,
    "the resident still reports the real problem")
assert(#p.getBaseStorageProblems(base.id) == 1,
    "the unshelvable haul is still an open base problem")

-- The receipt is the only place the player learns an overflow happened.
local finished = {}
controller.finishBaseSupplyRun = function(self, reason) finished[#finished + 1] = reason end
controller.clearLifeIntent = function() finished[#finished + 1] = "intent" end
controller.cargoReportAt = nil
local delivered = newItem("Canned Beans", "Base.CannedBeans")
local receipt = {
    baseSupply = true, partyDelivery = false, overflow = true, overflowLabel = "Tools",
    item = delivered, baseId = base.id,
    source = box(function() return false end),
    destination = box(function() return true end),
}
controller.pendingCleanup = receipt
captured = {}
assert(controller:recordBaseSupplyDepositReceipt() == true, "the real receipt is recorded")
assert(#captured == 1, "one overflow delivery produces one notice")
assert(string.find(captured[1], "Rae Moss", 1, true) ~= nil
    and string.find(captured[1], "Canned Beans", 1, true) ~= nil
    and string.find(captured[1], "Tools", 1, true) ~= nil,
    "the notice names the resident, the cargo and the container that took it")
assert(receipt.receiptRecorded == true and controller.pendingBaseSupplyDeposit == nil,
    "the receipt is one-shot and retires the pending haul")
assert(finished[1] == "deposited" and finished[2] == "intent",
    "the ordinary supply-run completion still runs")
assert(controller:recordBaseSupplyDepositReceipt() == true and #captured == 1,
    "a repeated receipt call reports nothing new")

-- An ordinary delivery stays silent.
controller.pendingCleanup = {
    baseSupply = true, partyDelivery = false, item = delivered, baseId = base.id,
    source = box(function() return false end),
    destination = box(function() return true end),
}
captured = {}
assert(controller:recordBaseSupplyDepositReceipt() == true)
assert(#captured == 0, "a delivery into a matching shelf says nothing")

Storage.findDepositTrip, Storage.findNearbyDeposit = oldTrip, oldNear
KnoxBaseManager = previousManager
KnoxActivityFeed = previousFeed
controller.pendingCleanup = nil
data["KnoxSurvivors_IsoPlayer"] = previousRoot
print("Overflow deposit wiring PASS flag=true label=true reported=true ordinarySilent=true")
