-- Bagged disinfectant retrieval through the real maintenance owner.
-- The maintenance planner used to see only a hand-held disinfectant. A survivor
-- with one in a bag therefore never disinfected an exposed wound. The real plan
-- must now select it, and the real Needs.execute must bring it to hand through
-- the same prepare_supply transfer a bagged bandage uses. Companion aid remains
-- direct-only because its native action cannot reach into the doctor's bag.
local N = assert(rawget(_G, "KnoxSurvivorNeeds"), "needs owner missing")
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local A = assert(rawget(_G, "KnoxInventoryActions"), "inventory action owner missing")
local oldSnapshot, oldQueueDisinfect, oldQueueTransfer = N.snapshot, M.queueDisinfect, A.queueTransfer
local oldQueue, oldComponentType = ISTimedActionQueue, ComponentType
ComponentType = ComponentType or { FluidContainer = "fluid" }

local function itemList(...)
    local items = { ... }
    return { size = function() return #items end,
        get = function(_, index) return items[index + 1] end }, items
end
local function container(items, parent)
    local c = { items = items, parent = parent }
    function c:getItems()
        return { size = function() return #self.items end,
            get = function(_, index) return self.items[index + 1] end }
    end
    function c:contains(item)
        for _, candidate in ipairs(self.items) do
            if candidate == item then return true end
        end
        return false
    end
    function c:getContainingItem() return self.parent end
    return c
end

local mainItems, bagItems = {}, {}
local main = container(mainItems)
local bagStore = container(bagItems, main)
local bag = {}
function bag:IsInventoryContainer() return true end
function bag:getInventory() return bagStore end
function bag:getContainer() return main end
mainItems[1] = bag

local disinfectant = { amount = 1, container = bagStore }
function disinfectant:isFavorite() return false end
function disinfectant:isBroken() return false end
function disinfectant:IsInventoryContainer() return false end
function disinfectant:hasComponent() return true end
function disinfectant:getFluidContainer()
    local amount = self.amount
    return { getAmount = function() return amount end,
        getProperties = function() return { getAlcohol = function() return 1 end } end }
end
function disinfectant:getContainer() return self.container end
function disinfectant:getFullType() return "Base.Disinfectant" end
function disinfectant:IsDrainable() return false end
bagItems[1] = disinfectant

local part = {}
function part:HasInjury() return true end
function part:isInfectedWound() return false end
function part:bandaged() return false end
function part:getAlcoholLevel() return 0 end
function part:getBandageLife() return 0 end
function part:getType() return "ForeArm_L" end
local parts = { size = function() return 1 end,
    get = function(_, index) if index == 0 then return part end end }

local square = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local pawn = { getCurrentSquare = function() return square end,
    getInventory = function() return main end,
    getBodyDamage = function() return { getBodyParts = function() return parts end } end,
    isEquipped = function() return false end,
    getReduceInfectionPower = function() return 0 end,
    hasFullInventory = function() return false end,
    isDead = function() return false end,
    getCharacterActions = function() return nil end }
local state = { bleedingParts = 0, thirst = 0, hunger = 0, endurance = 1, fatigue = 0 }
N.snapshot = function() return state end

local queue = { queue = {} }
ISTimedActionQueue = { queues = { [pawn] = queue },
    add = function(action) queue.queue = { action }; return queue end }
local transferCalls, disinfectCalls, rejectToMain = 0, 0, false
A.queueTransfer = function(character, item, source, destination, _, guard)
    transferCalls = transferCalls + 1
    if rejectToMain then return nil, "native_full" end
    local action = { character = character, item = item,
        srcContainer = source, destContainer = destination,
        isValid = function() return true end }
    action.knoxTransferGuard = guard
    queue.queue = { action }
    return action, "queued"
end
M.queueDisinfect = function(character, item, bodyPart, admit)
    disinfectCalls = disinfectCalls + 1
    local action = { character = character, item = item, otherPlayer = character,
        alcohol = item, bodyPart = bodyPart, isValid = function() return true end }
    if admit ~= nil then return admit(character, action) end
    return action, "queued"
end

-- 1. The real maintenance owner now selects a disinfectant from the bag, and
-- the real Needs.execute starts the shared bag-to-main transfer first.
assert(M.disinfectantUsable(disinfectant) == true,
    "medical_disinfect_bag: fixture disinfectant is usable")
assert(part:HasInjury() and not part:bandaged() and part:getAlcoholLevel() <= 0,
    "medical_disinfect_bag: fixture exposes an unbandaged wound")
assert(M.splintPartAllowed(part) == false,
    "medical_disinfect_bag: fixture wound is not a fracture")
local plan = M.maintenancePlan(pawn, pawn)
assert(plan ~= nil and plan.kind == "disinfect" and plan.item == disinfectant,
    "medical_disinfect_bag: maintenance selects a bagged disinfectant")
local decision = N.decide(pawn, nil)
assert(decision ~= nil and decision.kind == "disinfect" and decision.item == disinfectant,
    "medical_disinfect_bag: decide selects the bagged disinfectant")
assert(decision.bodyPart == part,
    "medical_disinfect_bag: the plan keeps the exposed body part")
local action, result, intent = N.execute(pawn, decision, nil)
assert(action ~= nil and intent ~= nil and intent.kind == "prepare_supply",
    "medical_disinfect_bag: bagged disinfectant starts a real transfer")
assert(intent.needKind == "disinfect" and intent.bodyPart == part,
    "medical_disinfect_bag: the transfer keeps the disinfect need and body part")
assert(intent.source == bagStore and intent.destination == main,
    "medical_disinfect_bag: the transfer moves the bagged disinfectant to hand")
assert(transferCalls == 1 and disinfectCalls == 0,
    "medical_disinfect_bag: native disinfection waits for the item to come to hand")

-- 2. A genuinely full pack still reports the rejected transfer; the controller
-- cleanup owner is unchanged and already covered by medical_capacity_recovery.
queue.queue = {}
rejectToMain, disinfectCalls = true, 0
local rejected, why = N.execute(pawn, decision, nil)
assert(rejected == nil and why == "supply_transfer_rejected",
    "medical_disinfect_bag: full pack reports the failed retrieval")
assert(disinfectCalls == 0,
    "medical_disinfect_bag: a full pack never queues disinfection on a bagged item")

-- 3. Unchanged path: a disinfectant already in the main inventory still goes
-- straight to the native owner without a transfer.
bagItems[1] = nil
mainItems[2] = disinfectant
disinfectant.container = main
queue.queue = {}
rejectToMain, transferCalls, disinfectCalls = false, 0, 0
local direct = N.decide(pawn, nil)
assert(direct ~= nil and direct.kind == "disinfect" and direct.item == disinfectant,
    "medical_disinfect_bag: hand-held disinfectant is still selected")
local directAction, directResult, directIntent = N.execute(pawn, direct, nil)
assert(directAction ~= nil and directIntent ~= nil and directIntent.kind == "disinfect",
    "medical_disinfect_bag: hand-held disinfectant queues the native action")
assert(transferCalls == 0 and disinfectCalls == 1,
    "medical_disinfect_bag: hand-held disinfectant takes no retrieval transfer")

-- 4. Companion aid is deliberately unchanged: a bagged supply is not a valid
-- aid item because the native action requires it in the doctor's own inventory.
bagItems[1] = disinfectant
mainItems[2] = nil
disinfectant.container = bagStore
local patient = { getBodyDamage = function()
    return { getBodyParts = function() return parts end }
end }
assert(M.maintenancePlan(pawn, patient) == nil,
    "medical_disinfect_bag: companion aid still requires a hand-held disinfectant")

N.snapshot = oldSnapshot
M.queueDisinfect = oldQueueDisinfect
A.queueTransfer = oldQueueTransfer
ISTimedActionQueue, ComponentType = oldQueue, oldComponentType
print("Medical disinfect bag PASS real_maintenance=true real_execute=true direct=true aid_direct_only=true native_transfer_stub=true")
